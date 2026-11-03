-- =============================================================================
-- Casa Coffee Colab — 0008_points.sql
-- Fase 3 — fidelidade (pontos + resgates). Torna o points_ledger a fonte da
-- verdade e o profiles.points_balance um cache que NUNCA diverge (trigger).
--
-- APPEND-ONLY e IMUTÁVEL (0001–0007 já aplicadas). Idempotente:
-- ADD COLUMN IF NOT EXISTS / CREATE OR REPLACE / CREATE ... IF NOT EXISTS /
-- DO-block pra dropar constraint por nome. NÃO renomeia nada. Nomes canônicos
-- travados (tiers/partners por slug, papéis). Ver CLAUDE.md › Segurança + Migrations.
--
-- REGRA DE NEGÓCIO (travada): 1 ponto por R$1 gasto × points_multiplier do tier
-- ATIVO no momento (sem assinatura = 1x). Loja: sobre o total JÁ COM DESCONTO.
-- Sempre floor (arredonda pra baixo). Ex.: R$49,41 no Ouro (1,5x) →
-- floor(49.41 × 1.5) = floor(74.115) = 74 pontos. Todo lançamento passa pelo
-- ledger (append-only); NUNCA update direto no saldo.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- points_ledger: colunas de referência pra idempotência do crédito + relaxa o
-- CHECK de `motivo` (agora aceita descrições em PT da Fase 3, inclusive o
-- dinâmico 'resgate: <nome>'). `motivo` segue NOT NULL.
-- -----------------------------------------------------------------------------
alter table public.points_ledger add column if not exists ref_type text;
alter table public.points_ledger add column if not exists ref_id   text;

-- Dropa o CHECK restritivo de motivo, seja qual for o nome auto-gerado dele.
do $$
declare c text;
begin
  select conname into c
    from pg_constraint
   where conrelid = 'public.points_ledger'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%motivo%';
  if c is not null then
    execute format('alter table public.points_ledger drop constraint %I', c);
  end if;
end $$;

-- Anti-duplicação no BANCO: um lançamento por (ref_type, ref_id). Mesmo que o
-- webhook reprocesse o evento, o crédito não duplica. NULLs livres (ajustes
-- manuais/bônus sem referência não colidem — índice parcial).
create unique index if not exists points_ledger_ref_unique
  on public.points_ledger (ref_type, ref_id)
  where ref_type is not null;

-- -----------------------------------------------------------------------------
-- prevent_points_tamper (redefine a de 0005): continua barrando o CLIENT de
-- mexer em points_balance/tier_slug direto. MAS libera quando o write vem de um
-- caminho server-side confiável, sinalizado por uma GUC transaction-local
-- (`casa.trusted_points='on'`), setada pelo trigger de saldo abaixo. Isso é
-- necessário porque o resgate roda como SECURITY DEFINER mas auth.uid() continua
-- sendo o do usuário (SECURITY DEFINER não troca o auth.uid()).
-- -----------------------------------------------------------------------------
create or replace function public.prevent_points_tamper()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Caminho confiável (trigger do ledger / funções server-side): libera.
  if coalesce(current_setting('casa.trusted_points', true), '') = 'on' then
    return new;
  end if;
  -- Cliente autenticado que não é owner: barra mudança nesses campos.
  if auth.uid() is not null and not public.is_owner() then
    if new.points_balance is distinct from old.points_balance then
      raise exception 'points_balance é gravado só server-side (não pelo client).';
    end if;
    if new.tier_slug is distinct from old.tier_slug then
      raise exception 'tier_slug é gravado só server-side (não pelo client).';
    end if;
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- update_points_balance: a cada INSERT no ledger, soma o delta no cache do
-- profiles. Seta a GUC confiável antes do update pro prevent_points_tamper
-- deixar passar (o resgate é chamado por usuário autenticado). SECURITY DEFINER
-- + search_path fixo (mesmo padrão dos triggers de 0001/0005).
-- -----------------------------------------------------------------------------
create or replace function public.update_points_balance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('casa.trusted_points', 'on', true); -- transação confiável
  update public.profiles
     set points_balance = coalesce(points_balance, 0) + new.delta
   where id = new.user_id;
  return new;
end;
$$;

drop trigger if exists trg_update_points_balance on public.points_ledger;
create trigger trg_update_points_balance
  after insert on public.points_ledger
  for each row execute function public.update_points_balance();

-- -----------------------------------------------------------------------------
-- recalc_points_balance: ferramenta de reparo — recalcula o cache somando o
-- ledger. Só service_role/owner (revogada de anon/authenticated).
-- -----------------------------------------------------------------------------
create or replace function public.recalc_points_balance(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer;
begin
  select coalesce(sum(delta), 0) into v_total
    from public.points_ledger where user_id = p_user_id;
  perform set_config('casa.trusted_points', 'on', true);
  update public.profiles set points_balance = v_total where id = p_user_id;
  return v_total;
end;
$$;

revoke all on function public.recalc_points_balance(uuid) from public;

-- -----------------------------------------------------------------------------
-- rewards_catalog: slug estável (idempotência do seed + referência) e o valor
-- do cupom em centavos (quando tipo='cupom').
-- -----------------------------------------------------------------------------
alter table public.rewards_catalog add column if not exists slug                 text;
alter table public.rewards_catalog add column if not exists cupom_valor_centavos integer;
create unique index if not exists rewards_catalog_slug_key on public.rewards_catalog (slug);

-- -----------------------------------------------------------------------------
-- redeem_reward: resgate ATÔMICO e à prova de corrida. Lock na linha do reward,
-- valida (ativo, estoque, saldo do LEDGER — não do cache), lança o NEGATIVO no
-- ledger, cria a redemption, decrementa estoque e, se for cupom, gera um código
-- único legível (CASA-XXXX, validade 30 dias). SECURITY DEFINER; só service_role
-- chama (via Edge Function redeem-reward). Resgate duplo fica impossível.
-- -----------------------------------------------------------------------------
create or replace function public.redeem_reward(p_user_id uuid, p_reward_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reward         public.rewards_catalog;
  v_saldo          integer;
  v_redemption_id  uuid;
  v_codigo         text := null;
  v_tipo_redemption text;
begin
  -- Lock pessimista na linha do reward: serializa resgates concorrentes.
  select * into v_reward from public.rewards_catalog where id = p_reward_id for update;
  if not found or not v_reward.ativo then
    return jsonb_build_object('ok', false, 'erro', 'recompensa indisponível');
  end if;
  if v_reward.estoque is not null and v_reward.estoque <= 0 then
    return jsonb_build_object('ok', false, 'erro', 'esgotado');
  end if;

  -- Saldo pela FONTE DA VERDADE (soma do ledger), nunca pelo cache.
  select coalesce(sum(delta), 0) into v_saldo
    from public.points_ledger where user_id = p_user_id;
  if v_saldo < v_reward.custo_em_pontos then
    return jsonb_build_object(
      'ok', false, 'erro', 'saldo insuficiente',
      'saldo', v_saldo, 'custo', v_reward.custo_em_pontos,
      'faltam', v_reward.custo_em_pontos - v_saldo);
  end if;

  v_tipo_redemption := case v_reward.tipo
    when 'produto_loja'  then 'produto'
    when 'produto_local' then 'parceiro'
    when 'cupom'         then 'cupom'
    else 'produto' end;

  insert into public.redemptions (user_id, tipo, partner_slug, pontos_gastos, status)
  values (p_user_id, v_tipo_redemption, v_reward.partner_slug, v_reward.custo_em_pontos, 'aprovado')
  returning id into v_redemption_id;

  -- Lançamento NEGATIVO (dispara o trigger que baixa o saldo). ref_* garante
  -- que um mesmo resgate nunca vira dois débitos.
  insert into public.points_ledger (user_id, delta, motivo, redemption_id, descricao, ref_type, ref_id)
  values (p_user_id, -v_reward.custo_em_pontos, 'resgate: ' || v_reward.nome,
          v_redemption_id, v_reward.nome, 'redemption', v_redemption_id::text);

  if v_reward.estoque is not null then
    update public.rewards_catalog set estoque = estoque - 1 where id = p_reward_id;
  end if;

  if v_reward.tipo = 'cupom' then
    -- Código único legível: CASA-XXXX (4 hex maiúsculos). Retenta se colidir.
    loop
      v_codigo := 'CASA-' || upper(substr(md5(gen_random_uuid()::text), 1, 4));
      exit when not exists (select 1 from public.coupons where codigo = v_codigo);
    end loop;
    insert into public.coupons (codigo, tipo_desconto, valor, validade, redemption_id, user_id)
    values (v_codigo, 'fixo', coalesce(v_reward.cupom_valor_centavos, 0),
            now() + interval '30 days', v_redemption_id, p_user_id);
    update public.redemptions set codigo = v_codigo where id = v_redemption_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'reward', v_reward.nome,
    'gasto', v_reward.custo_em_pontos,
    'saldo', v_saldo - v_reward.custo_em_pontos,
    'codigo', v_codigo);
end;
$$;

revoke all on function public.redeem_reward(uuid, uuid) from public;
grant execute on function public.redeem_reward(uuid, uuid) to service_role;

-- -----------------------------------------------------------------------------
-- SEED de recompensas (tom da marca). Idempotente por slug. Estoque null =
-- ilimitado. O parceiro do vale local sai do seed de partners (0003).
-- -----------------------------------------------------------------------------
insert into public.rewards_catalog (slug, nome, tipo, custo_em_pontos, estoque, partner_slug, cupom_valor_centavos, ativo) values
  ('cafe-coado-do-dia',   'Café coado do dia, por nossa conta', 'produto_loja',  100, null, null,                  null, true),
  ('vale-10-na-loja',     'Vale R$10 na nossa loja',            'cupom',         200, null, null,                  1000, true),
  ('saco-grao-250g',      'Saco de grão do Casa · 250g',        'produto_loja',  400, null, null,                  null, true),
  ('vale-livraria',       'Um vale na Livraria da Esquina',     'produto_local', 500, null, 'livraria-da-esquina', null, true)
on conflict (slug) do update set
  nome                 = excluded.nome,
  tipo                 = excluded.tipo,
  custo_em_pontos      = excluded.custo_em_pontos,
  partner_slug         = excluded.partner_slug,
  cupom_valor_centavos = excluded.cupom_valor_centavos,
  ativo                = excluded.ativo;
