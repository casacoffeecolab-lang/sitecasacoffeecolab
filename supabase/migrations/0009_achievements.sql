-- =============================================================================
-- Casa Coffee Colab — 0009_achievements.sql
-- Fase 3 — conquistas/emblemas. Dá CRITÉRIOS declarativos (jsonb) a cada
-- achievement (seed 0003) e uma função server-side que AVALIA esses critérios
-- pra um usuário e desbloqueia (insere em user_achievements) o que ele cumpriu.
--
-- APPEND-ONLY e IMUTÁVEL (0001–0008 já aplicadas). Idempotente:
-- ADD COLUMN IF NOT EXISTS / UPDATE por slug (reexecutável) / CREATE OR REPLACE.
-- NÃO recria tabela nem índice (a PK de user_achievements já é o índice único).
-- NÃO renomeia nada. Ver CLAUDE.md › Segurança + Migrations.
--
-- MODELO DE CONFIANÇA (igual redeem_reward da 0008): check_achievements é
-- SECURITY DEFINER (roda como owner, ignora RLS) e recebe SÓ p_user_id de
-- chamadas server-side confiáveis (Edge Function com service_role passando o id
-- do PRÓPRIO usuário autenticado). Nunca é chamada direto pelo client.
--
-- REGRA (travada): conquista NÃO credita pontos (a Leva 8 já cobre o crédito).
-- Aqui só se concede o emblema: insert em user_achievements, idempotente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Coluna de critérios (jsonb declarativo). Null = conquista sem regra
--    automática (não é avaliada pela função).
-- -----------------------------------------------------------------------------
alter table public.achievements add column if not exists criterios jsonb;

-- -----------------------------------------------------------------------------
-- 2) Critérios dos 9 emblemas do seed (0003). Um UPDATE por slug — reexecutável
--    à vontade (só reescreve o mesmo jsonb).
-- -----------------------------------------------------------------------------

-- 1ª compra paga em qualquer momento.
update public.achievements set criterios = '{"type":"purchase_count","min":1}'::jsonb
  where slug = 'primeira-xicara';

-- 5 compras pagas de manhã (< 12h no horário de São Paulo) — virou rotina.
update public.achievements set criterios = '{"type":"purchase_count","min":5,"window":"morning"}'::jsonb
  where slug = 'manha-de-sempre';

-- Assinante do tier Ouro — já é de casa.
update public.achievements set criterios = '{"type":"tier","slug":"ouro"}'::jsonb
  where slug = 'gente-do-casa';

-- Assinante do tier Diamante — o coração do lugar bate contigo.
update public.achievements set criterios = '{"type":"tier","slug":"diamante"}'::jsonb
  where slug = 'alma-do-casa';

-- Ao menos 1 saco de grão (categoria cafe_grao) numa compra paga — levou o grão.
update public.achievements set criterios = '{"type":"product_category","category":"cafe_grao","min":1}'::jsonb
  where slug = 'cafe-viajante';

-- MANUAL: trazer gente nova pra sentar junto (indicação). Ainda NÃO temos fonte
-- de dados de indicação — reservado p/ desbloqueio futuro (staff/PDV).
update public.achievements set criterios = '{"type":"manual"}'::jsonb
  where slug = 'mesa-comprida';

-- MANUAL: provar todos os doces do cardápio. Ainda NÃO temos como derivar isso
-- dos pedidos (o cardápio é informativo, sem SKU por doce) — reservado p/ futuro.
update public.achievements set criterios = '{"type":"manual"}'::jsonb
  where slug = 'que-seja-doce';

-- 4 compras pagas em domingos (dow=0 no horário de São Paulo) — brunch de domingo.
update public.achievements set criterios = '{"type":"purchase_count","min":4,"window":"sunday"}'::jsonb
  where slug = 'domingo-de-brunch';

-- MANUAL: levar um produto feito em residência no Casa. Ainda NÃO marcamos quais
-- produtos são de residência — reservado p/ desbloqueio futuro (staff/PDV).
update public.achievements set criterios = '{"type":"manual"}'::jsonb
  where slug = 'colab-de-vizinho';

-- -----------------------------------------------------------------------------
-- 3) check_achievements(p_user_id): avalia os critérios de todas as conquistas
--    ativas que o usuário AINDA não tem e concede as que ele cumpriu. Retorna
--    quantas foram desbloqueadas NESTA chamada. SECURITY DEFINER + search_path
--    fixo (mesmo padrão de redeem_reward/recalc_points_balance da 0008).
--
--    Compra válida = orders.status = 'pago'. Janelas de tempo usam o fuso
--    'America/Sao_Paulo' (manhã = hora < 12; domingo = dow 0). Tipos suportados:
--    purchase_count | tier | product_category | points_total |
--    subscription_months | redemption_count. 'manual' e tipos desconhecidos
--    NÃO desbloqueiam (skip) — ficam pra concessão manual futura.
-- -----------------------------------------------------------------------------
create or replace function public.check_achievements(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  rec       record;
  v_novas   integer := 0;   -- conquistas desbloqueadas nesta chamada
  v_rows    integer;        -- linhas realmente inseridas por conquista (0 ou 1)
  v_cumpre  boolean;        -- se o critério da conquista atual foi cumprido
  v_count   bigint;         -- contagem/soma auxiliar por critério
  v_window  text;           -- janela de tempo (morning|sunday) quando houver
  v_tier    text;           -- tier_slug do usuário (critério 'tier')
begin
  -- Só as conquistas ativas, com critério definido e que o usuário AINDA não tem.
  for rec in
    select a.slug, a.criterios
      from public.achievements a
     where a.ativo = true
       and a.criterios is not null
       and not exists (
         select 1 from public.user_achievements ua
          where ua.user_id = p_user_id
            and ua.achievement_slug = a.slug
       )
  loop
    v_cumpre := false;

    case rec.criterios->>'type'

      when 'purchase_count' then
        v_window := rec.criterios->>'window';
        if v_window = 'morning' then
          select count(*) into v_count
            from public.orders
           where user_id = p_user_id
             and status = 'pago'
             and extract(hour from (created_at at time zone 'America/Sao_Paulo')) < 12;
        elsif v_window = 'sunday' then
          select count(*) into v_count
            from public.orders
           where user_id = p_user_id
             and status = 'pago'
             and extract(dow from (created_at at time zone 'America/Sao_Paulo')) = 0;
        else
          select count(*) into v_count
            from public.orders
           where user_id = p_user_id
             and status = 'pago';
        end if;
        v_cumpre := v_count >= coalesce((rec.criterios->>'min')::int, 1);

      when 'tier' then
        select tier_slug into v_tier from public.profiles where id = p_user_id;
        v_cumpre := v_tier = (rec.criterios->>'slug');

      when 'product_category' then
        select count(*) into v_count
          from public.order_items oi
          join public.orders   o on o.id = oi.order_id
          join public.products p on p.id = oi.product_id
         where o.user_id = p_user_id
           and o.status  = 'pago'
           and p.categoria = (rec.criterios->>'category');
        v_cumpre := v_count >= coalesce((rec.criterios->>'min')::int, 1);

      when 'points_total' then
        select coalesce(sum(delta) filter (where delta > 0), 0) into v_count
          from public.points_ledger where user_id = p_user_id;
        v_cumpre := v_count >= coalesce((rec.criterios->>'min')::int, 0);

      when 'subscription_months' then
        select count(*) into v_count
          from public.points_ledger
         where user_id = p_user_id
           and ref_type in ('subscription_start', 'subscription_renewal');
        v_cumpre := v_count >= coalesce((rec.criterios->>'min')::int, 0);

      when 'redemption_count' then
        select count(*) into v_count
          from public.redemptions where user_id = p_user_id;
        v_cumpre := v_count >= coalesce((rec.criterios->>'min')::int, 0);

      else
        -- 'manual' ou tipo desconhecido: não desbloqueia (concessão manual futura).
        v_cumpre := false;
    end case;

    if v_cumpre then
      insert into public.user_achievements (user_id, achievement_slug)
      values (p_user_id, rec.slug)
      on conflict (user_id, achievement_slug) do nothing;
      -- Conta só se REALMENTE inseriu (evita contar corrida com outra sessão).
      get diagnostics v_rows = row_count;
      v_novas := v_novas + v_rows;
    end if;
  end loop;

  return v_novas;
end;
$$;

-- Só server-side (Edge Function com service_role). Nunca anon/authenticated.
revoke all on function public.check_achievements(uuid) from public;
grant execute on function public.check_achievements(uuid) to service_role;
