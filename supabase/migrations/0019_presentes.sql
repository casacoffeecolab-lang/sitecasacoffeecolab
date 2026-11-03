-- =============================================================================
-- 0019_presentes.sql — "Presentear um plano" 🎁
--
-- Deixa uma pessoa PAGAR uma assinatura de presente pra outra. O comprador paga
-- UM mês cheio do tier (cobrança avulsa, DETACHED — Pix ou cartão), escreve um
-- bilhete, e recebe um CÓDIGO. Quem ganha resgata o código na conta e ganha o
-- benefício do plano por 30 dias — SEM cartão, SEM recorrência: é presente, não
-- vira cobrança-surpresa quando o mês acaba.
--
-- MODELAGEM (por que estas escolhas):
--   • gift_subscriptions guarda o presente (comprador, tier, bilhete, código,
--     status, quem resgatou). Idempotência do webhook por asaas_checkout_id.
--   • Ao RESGATAR, criamos uma linha em `subscriptions` como status='pausada' com
--     current_period_end = agora + 30 dias. Por quê 'pausada' e não 'ativa'?
--     getEffectiveSubscription (_shared/lib.ts) concede benefício pra 'pausada'
--     SÓ enquanto current_period_end está no futuro — então o presente EXPIRA
--     sozinho em 30 dias, sem cron e sem o risco do "'ativa' concede pra sempre"
--     (uma 'ativa' sem renovação daria plano de graça eterno — ver auditoria do
--     asaas-webhook). O presente não tem assinatura no Asaas pra gerar
--     PAYMENT_OVERDUE, então a auto-expiração pelo período é o mecanismo certo.
--   • subscriptions.presente_id marca essa linha como originada de presente:
--     é o que faz o perfil e o resume-subscription NÃO a tratarem como assinatura
--     paga (não tem asaas_subscription_id pra "retomar"/"cancelar" no gateway).
--
-- SEGURANÇA (ver CLAUDE.md › Segurança):
--   • RLS deny-by-default. O comprador lê os presentes que deu; quem resgatou lê
--     o que ganhou. NENHUMA escrita pelo client — só via Edge Function
--     (service_role) e pelas RPCs SECURITY DEFINER abaixo.
--   • A resolução por CÓDIGO (resgate) roda só na RPC (revogada de anon/
--     authenticated): o client nunca varre a tabela por código.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Marcador na subscriptions: linha de assinatura que nasceu de um presente.
-- Nullable; o FK aponta pro presente que a originou (auditoria).
-- -----------------------------------------------------------------------------
alter table public.subscriptions
  add column if not exists presente_id uuid;

-- -----------------------------------------------------------------------------
-- Tabela dos presentes.
-- -----------------------------------------------------------------------------
create table if not exists public.gift_subscriptions (
  id                  uuid primary key default gen_random_uuid(),
  -- Nullable de propósito: se o comprador apagar a conta, o presente que ele deu
  -- NÃO some (quem ganhou ainda precisa poder resgatar) — o vínculo vira null via
  -- ON DELETE SET NULL. Por isso não pode ser NOT NULL (senão o delete da conta
  -- travaria). O comprador é gravado server-side no checkout (auth.uid()).
  comprador_id        uuid references public.profiles (id) on delete set null,
  tier_slug           text not null references public.tiers (slug),
  valor_centavos      integer not null check (valor_centavos > 0),
  mensagem            text,                         -- o bilhete (opcional, limitado no app)
  status              text not null default 'pendente'
                      check (status in ('pendente', 'pago', 'resgatado', 'cancelado')),
  codigo              text unique,                  -- gerado quando o presente é PAGO
  asaas_checkout_id   text unique,                  -- idempotência do checkout
  asaas_payment_id    text,                         -- pagamento que confirmou
  resgatado_por       uuid references public.profiles (id) on delete set null,
  resgatado_em        timestamptz,
  subscription_id     uuid references public.subscriptions (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- Agora que a tabela existe, amarra o FK do marcador (idempotente).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'subscriptions_presente_id_fkey'
  ) then
    alter table public.subscriptions
      add constraint subscriptions_presente_id_fkey
      foreign key (presente_id) references public.gift_subscriptions (id) on delete set null;
  end if;
end $$;

create index if not exists idx_gift_comprador   on public.gift_subscriptions (comprador_id);
create index if not exists idx_gift_resgatado   on public.gift_subscriptions (resgatado_por);
create index if not exists idx_gift_status      on public.gift_subscriptions (status);

-- -----------------------------------------------------------------------------
-- RLS: deny-by-default. Leitura só do comprador e de quem resgatou. Sem escrita
-- pelo client (service_role ignora RLS; as RPCs abaixo são SECURITY DEFINER).
-- -----------------------------------------------------------------------------
alter table public.gift_subscriptions enable row level security;

drop policy if exists gift_select_own on public.gift_subscriptions;
create policy gift_select_own on public.gift_subscriptions
  for select to authenticated
  using (comprador_id = auth.uid() or resgatado_por = auth.uid());

-- -----------------------------------------------------------------------------
-- marcar_presente_pago(gift_id, payment_id) → codigo
-- Chamada pelo asaas-webhook no CHECKOUT_PAID do presente. Idempotente: se já
-- está 'pago'/'resgatado', devolve o código existente sem regerar. Gera um código
-- legível e único (CASA-XXXXXX, 6 hex maiúsculos), com retry anti-colisão.
-- SECURITY DEFINER; só service_role chama.
-- -----------------------------------------------------------------------------
create or replace function public.marcar_presente_pago(p_gift_id uuid, p_payment_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gift    public.gift_subscriptions;
  v_codigo  text;
begin
  select * into v_gift from public.gift_subscriptions where id = p_gift_id for update;
  if not found then
    return null; -- presente inexistente (checkout externo/forjado) → nada a fazer
  end if;

  -- Já processado: devolve o código que já existe (idempotência do reenvio).
  if v_gift.status in ('pago', 'resgatado') then
    return v_gift.codigo;
  end if;
  -- Só um 'pendente' vira 'pago'. 'cancelado' não ressuscita.
  if v_gift.status <> 'pendente' then
    return v_gift.codigo;
  end if;

  -- Código único legível: CASA-XXXXXX. Retenta se colidir.
  loop
    v_codigo := 'CASA-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.gift_subscriptions where codigo = v_codigo);
  end loop;

  update public.gift_subscriptions
     set status = 'pago',
         codigo = v_codigo,
         asaas_payment_id = coalesce(p_payment_id, asaas_payment_id),
         updated_at = now()
   where id = p_gift_id;

  return v_codigo;
end;
$$;

revoke all on function public.marcar_presente_pago(uuid, text) from public;
grant execute on function public.marcar_presente_pago(uuid, text) to service_role;

-- -----------------------------------------------------------------------------
-- resgatar_presente(user_id, codigo) → jsonb
-- Resgate ATÔMICO (lock na linha do presente): valida código/estado, garante que
-- quem resgata não tem plano vigente (pra não empilhar benefício/desperdiçar o
-- presente), cria a assinatura 'pausada' (+30 dias) marcada como presente, espelha
-- o tier no profiles e fecha o presente. SECURITY DEFINER; só service_role chama.
--
-- Retorna { ok:true, tier, tier_nome, ativo_ate } ou { ok:false, erro }.
-- -----------------------------------------------------------------------------
create or replace function public.resgatar_presente(p_user_id uuid, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gift      public.gift_subscriptions;
  v_codigo    text := upper(trim(coalesce(p_codigo, '')));
  v_tier      public.tiers;
  v_sub_id    uuid;
  v_ativo_ate timestamptz := now() + interval '30 days';
begin
  if v_codigo = '' then
    return jsonb_build_object('ok', false, 'erro', 'digita o código do presente 💛');
  end if;

  -- Lock pessimista na linha do presente: serializa resgates concorrentes do mesmo
  -- código (dois cliques / duas abas não resgatam duas vezes).
  select * into v_gift from public.gift_subscriptions where codigo = v_codigo for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'não achei esse presente. confere o código?');
  end if;
  if v_gift.status = 'resgatado' then
    return jsonb_build_object('ok', false, 'erro', 'esse presente já foi resgatado 💛');
  end if;
  if v_gift.status <> 'pago' then
    return jsonb_build_object('ok', false, 'erro', 'esse presente ainda não tá disponível pra resgate');
  end if;

  -- Já tem plano vigente? Não empilha (o presente ficaria "desperdiçado" por baixo
  -- de uma 'ativa', que sempre ganha). Deixa o presente guardado pra quando o plano
  -- atual acabar. Mesma regra de "concede benefício" do getEffectiveSubscription.
  if exists (
    select 1 from public.subscriptions
     where user_id = p_user_id
       and status in ('ativa', 'pausada')
       and (status = 'ativa' or (current_period_end is not null and current_period_end > now()))
  ) then
    return jsonb_build_object(
      'ok', false,
      'erro', 'tu já tem um plano rolando por aqui 💛 esse presente fica guardadinho — resgata quando ele acabar.',
      'guardado', true);
  end if;

  select * into v_tier from public.tiers where slug = v_gift.tier_slug;
  if not found or not coalesce(v_tier.ativo, false) then
    return jsonb_build_object('ok', false, 'erro', 'o plano desse presente não tá disponível agora');
  end if;

  -- Cria a assinatura 'pausada' (+30 dias), marcada como presente. Sem asaas_* —
  -- não é recorrência no gateway. Expira sozinha quando o período vence.
  insert into public.subscriptions (user_id, tier_slug, status, current_period_end, presente_id)
  values (p_user_id, v_gift.tier_slug, 'pausada', v_ativo_ate, v_gift.id)
  returning id into v_sub_id;

  -- Espelha o tier no profiles (cache). A GUC libera o prevent_points_tamper pra
  -- este write server-side (mesmo padrão do update_points_balance / 0008).
  perform set_config('casa.trusted_points', 'on', true);
  update public.profiles set tier_slug = v_gift.tier_slug where id = p_user_id;

  -- Fecha o presente.
  update public.gift_subscriptions
     set status = 'resgatado',
         resgatado_por = p_user_id,
         resgatado_em = now(),
         subscription_id = v_sub_id,
         updated_at = now()
   where id = v_gift.id;

  return jsonb_build_object(
    'ok', true,
    'tier', v_gift.tier_slug,
    'tier_nome', v_tier.nome,
    'ativo_ate', v_ativo_ate);
end;
$$;

revoke all on function public.resgatar_presente(uuid, text) from public;
grant execute on function public.resgatar_presente(uuid, text) to service_role;
