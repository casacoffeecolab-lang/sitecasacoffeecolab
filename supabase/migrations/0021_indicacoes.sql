-- =============================================================================
-- 0021_indicacoes.sql — "Indica um amigo" 🤝
--
-- Cada usuário ganha um CÓDIGO de indicação. Quem é trazido cria conta com o
-- código, assina, e quando o PRIMEIRO PAGAMENTO confirma os DOIS ganham pontos.
--
-- POR QUE A RECOMPENSA CAI NO PAGAMENTO, NÃO NO CADASTRO:
--   Premiar no cadastro convidaria fraude (contas fantasma). Amarrando ao
--   primeiro pagamento CONFIRMADO de uma assinatura real (via asaas-webhook),
--   indicar só compensa quando entra gente de verdade pagando.
--
-- SEGURANÇA (ver CLAUDE.md › Segurança):
--   • RLS deny-by-default. Cada um lê só as indicações que fez / que recebeu.
--   • Registro do vínculo: RPC registrar_indicacao (SECURITY DEFINER) usa
--     auth.uid() como INDICADO — o client nunca diz "sou fulano". Barra
--     auto-indicação, conta que já é da casa (tem assinatura) e duplo-vínculo.
--   • Premiação: RPC premiar_indicacao (SECURITY DEFINER), chamada SÓ pelo
--     asaas-webhook (service_role) no pagamento. Idempotente (pendente→premiado).
--     Os pontos entram pelo points_ledger (append-only), nunca pelo client.
--
-- VALORES DOS PONTOS: são FICTÍCIOS e vivem nas constantes do asaas-webhook
-- (REFERRAL_PTS_INDICADOR / REFERRAL_PTS_INDICADO) — passados pra premiar_indicacao.
-- A migration não fixa valor: quem decide quanto é o webhook. Ajustar lá depois.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

-- Código de indicação do usuário (gerado sob demanda pela RPC abaixo).
alter table public.profiles
  add column if not exists referral_code text unique;

-- -----------------------------------------------------------------------------
-- Vínculo de indicação. Um indicado só pode ser indicado UMA vez (UNIQUE).
-- -----------------------------------------------------------------------------
create table if not exists public.referrals (
  id            uuid primary key default gen_random_uuid(),
  referrer_id   uuid references public.profiles (id) on delete set null, -- quem indicou
  referred_id   uuid not null references public.profiles (id) on delete cascade, -- quem foi indicado
  codigo        text,                             -- snapshot do código usado
  status        text not null default 'pendente'
                check (status in ('pendente', 'premiado', 'invalido')),
  premiado_em   timestamptz,
  created_at    timestamptz not null default now(),
  unique (referred_id)                            -- cada conta é indicada no máx. 1 vez
);

create index if not exists idx_referrals_referrer on public.referrals (referrer_id, status);

-- -----------------------------------------------------------------------------
-- RLS: cada um lê só o que fez/recebeu. Sem escrita pelo client (as RPCs
-- SECURITY DEFINER e o webhook/service_role é que escrevem).
-- -----------------------------------------------------------------------------
alter table public.referrals enable row level security;

drop policy if exists referrals_select_own on public.referrals;
create policy referrals_select_own on public.referrals
  for select to authenticated
  using (referrer_id = auth.uid() or referred_id = auth.uid());

-- -----------------------------------------------------------------------------
-- meu_codigo_indicacao() → text
-- Retorna o código do PRÓPRIO usuário (auth.uid()), gerando um único na primeira
-- vez (CASA6, 6 hex maiúsculos, com retry anti-colisão). SECURITY DEFINER.
-- -----------------------------------------------------------------------------
create or replace function public.meu_codigo_indicacao()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_codigo text;
begin
  if v_uid is null then
    raise exception 'não autenticado';
  end if;

  select referral_code into v_codigo from public.profiles where id = v_uid;
  if v_codigo is not null then
    return v_codigo;
  end if;

  loop
    v_codigo := upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.profiles where referral_code = v_codigo);
  end loop;

  update public.profiles set referral_code = v_codigo where id = v_uid;
  return v_codigo;
end;
$$;

revoke all on function public.meu_codigo_indicacao() from public;
grant execute on function public.meu_codigo_indicacao() to authenticated;

-- -----------------------------------------------------------------------------
-- registrar_indicacao(codigo) → jsonb
-- Registra que o usuário ATUAL (auth.uid()) foi indicado por quem tem esse código.
-- Barra: código inválido, auto-indicação, quem já foi indicado, e quem já é da
-- casa (tem qualquer assinatura). Cria o vínculo 'pendente'. SECURITY DEFINER.
-- -----------------------------------------------------------------------------
create or replace function public.registrar_indicacao(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_referred uuid := auth.uid();
  v_codigo   text := upper(btrim(coalesce(p_codigo, '')));
  v_referrer uuid;
begin
  if v_referred is null then
    return jsonb_build_object('ok', false, 'erro', 'não autenticado');
  end if;
  if v_codigo = '' then
    return jsonb_build_object('ok', false, 'erro', 'código vazio');
  end if;

  select id into v_referrer from public.profiles where referral_code = v_codigo;
  if v_referrer is null then
    return jsonb_build_object('ok', false, 'erro', 'código de indicação inválido');
  end if;
  if v_referrer = v_referred then
    return jsonb_build_object('ok', false, 'erro', 'não dá pra indicar a si mesmo 💛');
  end if;

  -- Já foi indicado antes? (UNIQUE garante, mas respondemos gentil.)
  if exists (select 1 from public.referrals where referred_id = v_referred) then
    return jsonb_build_object('ok', false, 'erro', 'você já entrou por uma indicação', 'ja', true);
  end if;

  -- Já é da casa (tem/teve assinatura)? Então não é "conta nova indicada".
  if exists (select 1 from public.subscriptions where user_id = v_referred) then
    return jsonb_build_object('ok', false, 'erro', 'essa conta já é da casa', 'ja', true);
  end if;

  insert into public.referrals (referrer_id, referred_id, codigo, status)
  values (v_referrer, v_referred, v_codigo, 'pendente');

  return jsonb_build_object('ok', true);
exception
  when unique_violation then
    -- corrida: outra chamada registrou primeiro. Trata como "já indicado".
    return jsonb_build_object('ok', false, 'erro', 'você já entrou por uma indicação', 'ja', true);
end;
$$;

revoke all on function public.registrar_indicacao(text) from public;
grant execute on function public.registrar_indicacao(text) to authenticated;

-- -----------------------------------------------------------------------------
-- premiar_indicacao(referred_id, pontos_indicador, pontos_indicado) → jsonb
-- Chamada pelo asaas-webhook (service_role) quando o PAGAMENTO do indicado
-- confirma. Trava o vínculo 'pendente' do indicado, credita os DOIS lados no
-- ledger e marca 'premiado'. Idempotente (só processa 'pendente'). Os pontos
-- entram como lançamentos fixos (ref_type 'indicacao'/'indicacao_bonus',
-- ref_id = referral.id) — NÃO passam pelo multiplicador de tier.
-- -----------------------------------------------------------------------------
create or replace function public.premiar_indicacao(
  p_referred_id uuid,
  p_pontos_indicador integer,
  p_pontos_indicado integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref public.referrals;
begin
  select * into v_ref
    from public.referrals
   where referred_id = p_referred_id and status = 'pendente'
   for update;
  if not found then
    return jsonb_build_object('rewarded', false); -- sem vínculo pendente → nada a fazer
  end if;

  -- Indicador sumiu (conta apagada) → invalida, sem premiar.
  if v_ref.referrer_id is null then
    update public.referrals set status = 'invalido' where id = v_ref.id;
    return jsonb_build_object('rewarded', false, 'motivo', 'indicador inexistente');
  end if;

  -- Credita os dois (append-only; o trigger sincroniza o cache de saldo).
  -- ref_type distinto por lado → o UNIQUE (ref_type, ref_id) deixa os dois coexistirem.
  if coalesce(p_pontos_indicador, 0) > 0 then
    insert into public.points_ledger (user_id, delta, motivo, descricao, ref_type, ref_id)
    values (v_ref.referrer_id, p_pontos_indicador, 'indicou um amigo', 'indicou um amigo',
            'indicacao', v_ref.id::text)
    on conflict (ref_type, ref_id) where ref_type is not null do nothing;
  end if;
  if coalesce(p_pontos_indicado, 0) > 0 then
    insert into public.points_ledger (user_id, delta, motivo, descricao, ref_type, ref_id)
    values (v_ref.referred_id, p_pontos_indicado, 'veio pela indicação de um amigo',
            'veio pela indicação de um amigo', 'indicacao_bonus', v_ref.id::text)
    on conflict (ref_type, ref_id) where ref_type is not null do nothing;
  end if;

  update public.referrals
     set status = 'premiado', premiado_em = now()
   where id = v_ref.id;

  return jsonb_build_object('rewarded', true, 'referrer', v_ref.referrer_id, 'referred', v_ref.referred_id);
end;
$$;

revoke all on function public.premiar_indicacao(uuid, integer, integer) from public;
grant execute on function public.premiar_indicacao(uuid, integer, integer) to service_role;
