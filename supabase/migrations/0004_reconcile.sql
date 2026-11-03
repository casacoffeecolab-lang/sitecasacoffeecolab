-- =============================================================================
-- Casa Coffee Colab — 0004_reconcile.sql
-- Reconcilia o banco com a seção 3 (modelo de dados) da Fase 3: adiciona as 5
-- tabelas que faltavam + colunas ausentes em tiers/profiles.
--
-- APPEND-ONLY e IMUTÁVEL (0001–0003 já aplicadas; correção = arquivo novo).
-- Idempotente: IF NOT EXISTS / ADD COLUMN IF NOT EXISTS / drop policy if exists.
-- NÃO renomeia nada existente. Nomes canônicos travados: tabelas `tiers`/`partners`,
-- papéis cliente/staff/gerente/owner.
--
-- NOTA sobre FKs: `partners` e `tiers` têm PK = slug (canônico). Os FKs abaixo
-- apontam pro slug e seguem a convenção já usada no banco (*_slug), NÃO *_id.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- AJUSTES EM TABELAS EXISTENTES
-- -----------------------------------------------------------------------------

-- tiers: colunas points_multiplier / discount_percent (nomes da seção 3).
-- Mantém as colunas PT já existentes (pontos_multiplicador/desconto_pct) e
-- espelha os valores. Backfill idempotente via coalesce.
alter table public.tiers add column if not exists points_multiplier numeric(4,2);
alter table public.tiers add column if not exists discount_percent  integer;

update public.tiers set
  points_multiplier = coalesce(points_multiplier, pontos_multiplicador),
  discount_percent  = coalesce(discount_percent,  desconto_pct);

-- Reforço explícito dos valores da seção 3 (Vizinho 1x/3%, Frequentador 1.25x/6%,
-- Gente do Casa 1.5x/10%, Alma do Casa 2x/15%) — só onde ainda estiver nulo.
update public.tiers set points_multiplier = 1.00, discount_percent = 3  where slug = 'bronze'   and (points_multiplier is null or discount_percent is null);
update public.tiers set points_multiplier = 1.25, discount_percent = 6  where slug = 'prata'    and (points_multiplier is null or discount_percent is null);
update public.tiers set points_multiplier = 1.50, discount_percent = 10 where slug = 'ouro'     and (points_multiplier is null or discount_percent is null);
update public.tiers set points_multiplier = 2.00, discount_percent = 15 where slug = 'diamante' and (points_multiplier is null or discount_percent is null);

-- profiles: saldo de pontos (cache) + tier atual (FK tiers via slug — ver NOTA).
alter table public.profiles add column if not exists points_balance integer not null default 0;
alter table public.profiles add column if not exists tier_slug      text references public.tiers (slug);

-- =============================================================================
-- TABELAS NOVAS
-- =============================================================================

-- 1) rewards_catalog — o que dá pra resgatar com pontos.
--    (partner_slug: FK partners via slug — ver NOTA sobre *_slug.)
create table if not exists public.rewards_catalog (
  id               uuid primary key default gen_random_uuid(),
  nome             text not null,
  tipo             text not null check (tipo in ('produto_loja', 'cupom', 'produto_local')),
  custo_em_pontos  integer not null check (custo_em_pontos >= 0),
  estoque          integer,        -- null = ilimitado
  partner_slug     text references public.partners (slug),
  ativo            boolean not null default true,
  created_at       timestamptz not null default now()
);
create index if not exists idx_rewards_catalog_ativo    on public.rewards_catalog (ativo);
create index if not exists idx_rewards_catalog_partner  on public.rewards_catalog (partner_slug);

-- 2) events — encontros/eventos do Casa.
create table if not exists public.events (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  descricao   text,
  data        timestamptz,
  vagas       integer check (vagas is null or vagas >= 0),
  ativo       boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists idx_events_ativo  on public.events (ativo);
create index if not exists idx_events_data    on public.events (data);

-- 3) coupons — cupons de desconto (geralmente gerados por um resgate).
--    Leitura só do dono (ou staff+); escrita só server-side.
create table if not exists public.coupons (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null unique,
  tipo_desconto  text not null check (tipo_desconto in ('percent', 'fixo')),
  valor          integer not null check (valor >= 0),  -- percent: 0–100 · fixo: centavos
  validade       timestamptz,
  redemption_id  uuid references public.redemptions (id) on delete set null,
  user_id        uuid references public.profiles (id)    on delete cascade,
  created_at     timestamptz not null default now()
);
create index if not exists idx_coupons_user  on public.coupons (user_id);

-- 4) pos_webhook_events — eventos do PDV (webhook). Sem acesso a cliente.
--    external_transaction_id UNIQUE = idempotência/anti-replay.
create table if not exists public.pos_webhook_events (
  id                       uuid primary key default gen_random_uuid(),
  external_transaction_id  text not null unique,
  payload                  jsonb not null default '{}'::jsonb,
  status                   text not null default 'recebido'
                           check (status in ('recebido', 'processado', 'erro', 'ignorado')),
  processed_at             timestamptz,
  created_at               timestamptz not null default now()
);

-- 5) unclaimed_points — pontos ganhos por quem ainda não tem conta (por telefone/e-mail).
--    Sem acesso a cliente; leitura só owner; escrita só server-side.
create table if not exists public.unclaimed_points (
  id                uuid primary key default gen_random_uuid(),
  identifier_type   text not null check (identifier_type in ('phone', 'email')),
  identifier_value  text not null,
  pontos            integer not null,
  origem            text,
  created_at        timestamptz not null default now(),
  claimed_at        timestamptz
);
create index if not exists idx_unclaimed_points_identifier
  on public.unclaimed_points (identifier_type, identifier_value);

-- =============================================================================
-- RLS — habilita nas 5 novas tabelas (deny-by-default) + policies.
-- =============================================================================
alter table public.rewards_catalog    enable row level security;
alter table public.events             enable row level security;
alter table public.coupons            enable row level security;
alter table public.pos_webhook_events enable row level security;
alter table public.unclaimed_points   enable row level security;

-- rewards_catalog — leitura pública dos ativos; escrita gerente/owner.
drop policy if exists rewards_catalog_select_public on public.rewards_catalog;
create policy rewards_catalog_select_public on public.rewards_catalog
  for select to anon, authenticated
  using (ativo or public.is_staff());

drop policy if exists rewards_catalog_write_admin on public.rewards_catalog;
create policy rewards_catalog_write_admin on public.rewards_catalog
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- events — leitura pública dos ativos; escrita gerente/owner.
drop policy if exists events_select_public on public.events;
create policy events_select_public on public.events
  for select to anon, authenticated
  using (ativo or public.is_staff());

drop policy if exists events_write_admin on public.events;
create policy events_write_admin on public.events
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- coupons — só o dono lê (ou staff+). Escrita server-side (sem policy → negado).
drop policy if exists coupons_select_own on public.coupons;
create policy coupons_select_own on public.coupons
  for select to authenticated
  using (user_id = auth.uid() or public.is_staff());

-- pos_webhook_events — sem acesso a cliente; só owner lê. Escrita server-side.
drop policy if exists pos_webhook_events_select_owner on public.pos_webhook_events;
create policy pos_webhook_events_select_owner on public.pos_webhook_events
  for select to authenticated
  using (public.is_owner());

-- unclaimed_points — sem acesso a cliente; só owner lê. Escrita server-side.
drop policy if exists unclaimed_points_select_owner on public.unclaimed_points;
create policy unclaimed_points_select_owner on public.unclaimed_points
  for select to authenticated
  using (public.is_owner());
