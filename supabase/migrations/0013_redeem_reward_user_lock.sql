-- =============================================================================
-- 0013_redeem_reward_user_lock
-- -----------------------------------------------------------------------------
-- CORREÇÃO (gasto duplo de pontos): a redeem_reward da 0008 trava a LINHA DO
-- REWARD (`rewards_catalog … for update`), o que serializa resgates concorrentes
-- da MESMA recompensa — mas NÃO resgates simultâneos de recompensas DIFERENTES
-- pelo mesmo usuário. Sob READ COMMITTED, duas transações podem ler o mesmo saldo
-- (sum do ledger), cada uma passar no `v_saldo < custo` do seu reward e ambas
-- lançarem o débito: a pessoa gasta mais pontos do que tem (saldo fica negativo).
--
-- Fix: trava a LINHA DO PRÓPRIO USUÁRIO (`profiles … for update`) logo no início,
-- ANTES de ler o saldo. Isso serializa TODOS os resgates daquele usuário, seja qual
-- for a recompensa. Ordem de lock consistente (usuário → reward) evita deadlock; o
-- trigger update_points_balance atualiza a MESMA linha de profiles dentro da própria
-- transação (que já a detém), sem conflito.
--
-- Idempotente (CREATE OR REPLACE) e autocontida. Reaplica revoke/grant.
-- Migrations são imutáveis: esta SUBSTITUI o corpo da função definida na 0008.
-- =============================================================================
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
  -- Lock pessimista na linha do PRÓPRIO usuário: serializa TODOS os resgates dele
  -- (inclusive de recompensas diferentes) — impede leitura de saldo defasada e o
  -- consequente gasto duplo. Travar o usuário ANTES do reward mantém ordem única.
  perform 1 from public.profiles where id = p_user_id for update;

  -- Lock pessimista na linha do reward: serializa resgates concorrentes do MESMO
  -- item (estoque) e mantém o comportamento original.
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
