-- =============================================================================
-- Casa Coffee Colab — 0002_rls.sql
-- Habilita RLS em TODA tabela + todas as policies (deny-by-default).
--
-- Modelo (ver CLAUDE.md › Segurança):
--   • Catálogo/referência (tiers, products, product_variants, achievements,
--     partners): LEITURA PÚBLICA (anon + authenticated) do que está ativo;
--     escrita só gerente/owner (admin autenticado).
--   • Dados sensíveis do usuário (profiles, subscriptions, orders, order_items,
--     points_ledger, redemptions, user_achievements): cliente só LÊ o PRÓPRIO
--     registro (ou staff+). Escrita = server-side (service_role, que ignora RLS)
--     ou trigger. Sem policy de escrita pro client → negado por padrão.
--   • audit_log: só o owner lê. Escrita só por trigger/server-side.
--
-- APPEND-ONLY e IMUTÁVEL. Idempotente: drop policy if exists + create.
-- service_role SEMPRE ignora RLS (usado pelas Edge Functions na Fase 2).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Liga RLS em todas as tabelas (deny-by-default: sem policy = nada passa).
-- -----------------------------------------------------------------------------
alter table public.profiles           enable row level security;
alter table public.audit_log          enable row level security;
alter table public.tiers              enable row level security;
alter table public.products           enable row level security;
alter table public.product_variants   enable row level security;
alter table public.achievements       enable row level security;
alter table public.partners           enable row level security;
alter table public.subscriptions      enable row level security;
alter table public.orders             enable row level security;
alter table public.order_items        enable row level security;
alter table public.points_ledger      enable row level security;
alter table public.redemptions        enable row level security;
alter table public.user_achievements  enable row level security;

-- =============================================================================
-- profiles — cliente lê/edita o próprio; staff+ lê todos; owner edita qualquer.
-- Troca de papel é barrada pela trigger prevent_role_change (defesa extra).
-- INSERT é feito pela trigger handle_new_user (SECURITY DEFINER) — sem policy.
-- =============================================================================
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_staff());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_owner())
  with check (id = auth.uid() or public.is_owner());

-- =============================================================================
-- audit_log — só o owner lê. Escrita só server-side/trigger (sem policy).
-- =============================================================================
drop policy if exists audit_log_select_owner on public.audit_log;
create policy audit_log_select_owner on public.audit_log
  for select to authenticated
  using (public.is_owner());

-- =============================================================================
-- CATÁLOGO / REFERÊNCIA — leitura pública (ativos); escrita gerente/owner.
-- =============================================================================

-- tiers
drop policy if exists tiers_select_public on public.tiers;
create policy tiers_select_public on public.tiers
  for select to anon, authenticated
  using (ativo or public.is_staff());

drop policy if exists tiers_write_admin on public.tiers;
create policy tiers_write_admin on public.tiers
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- products
drop policy if exists products_select_public on public.products;
create policy products_select_public on public.products
  for select to anon, authenticated
  using (ativo or public.is_staff());

drop policy if exists products_write_admin on public.products;
create policy products_write_admin on public.products
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- product_variants
drop policy if exists variants_select_public on public.product_variants;
create policy variants_select_public on public.product_variants
  for select to anon, authenticated
  using (
    ativo or public.is_staff()
  );

drop policy if exists variants_write_admin on public.product_variants;
create policy variants_write_admin on public.product_variants
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- achievements
drop policy if exists achievements_select_public on public.achievements;
create policy achievements_select_public on public.achievements
  for select to anon, authenticated
  using (ativo or public.is_staff());

drop policy if exists achievements_write_admin on public.achievements;
create policy achievements_write_admin on public.achievements
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- partners
drop policy if exists partners_select_public on public.partners;
create policy partners_select_public on public.partners
  for select to anon, authenticated
  using (ativo or public.is_staff());

drop policy if exists partners_write_admin on public.partners;
create policy partners_write_admin on public.partners
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- =============================================================================
-- DADOS SENSÍVEIS DO USUÁRIO — cliente só LÊ o próprio (ou staff+).
-- Nenhuma policy de INSERT/UPDATE/DELETE pro client: escrita é server-side
-- (service_role ignora RLS) ou por trigger. Negado por padrão.
-- =============================================================================

-- subscriptions
drop policy if exists subscriptions_select_own on public.subscriptions;
create policy subscriptions_select_own on public.subscriptions
  for select to authenticated
  using (user_id = auth.uid() or public.is_staff());

-- orders
drop policy if exists orders_select_own on public.orders;
create policy orders_select_own on public.orders
  for select to authenticated
  using (user_id = auth.uid() or public.is_staff());

-- order_items — segue a visibilidade do pedido pai.
drop policy if exists order_items_select_own on public.order_items;
create policy order_items_select_own on public.order_items
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and (o.user_id = auth.uid() or public.is_staff())
    )
  );

-- points_ledger — append-only; cliente só lê o próprio. Sem UPDATE/DELETE pra ninguém.
drop policy if exists points_ledger_select_own on public.points_ledger;
create policy points_ledger_select_own on public.points_ledger
  for select to authenticated
  using (user_id = auth.uid() or public.is_staff());

-- redemptions
drop policy if exists redemptions_select_own on public.redemptions;
create policy redemptions_select_own on public.redemptions
  for select to authenticated
  using (user_id = auth.uid() or public.is_staff());

-- user_achievements
drop policy if exists user_achievements_select_own on public.user_achievements;
create policy user_achievements_select_own on public.user_achievements
  for select to authenticated
  using (user_id = auth.uid() or public.is_staff());
