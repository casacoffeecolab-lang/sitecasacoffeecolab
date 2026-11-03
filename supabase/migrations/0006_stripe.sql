-- =============================================================================
-- Casa Coffee Colab — 0006_stripe.sql
-- Fase 6a — fundação do Stripe (SÓ TEST MODE) + caso de ASSINATURA (4 tiers).
--
-- APPEND-ONLY e IMUTÁVEL (0001–0005 já aplicadas). Idempotente:
-- CREATE TABLE IF NOT EXISTS / ADD COLUMN IF NOT EXISTS / CREATE ... IF NOT EXISTS
-- / drop policy if exists. NÃO renomeia nada. Nomes canônicos travados
-- (tabelas tiers/subscriptions, FKs por slug). Ver CLAUDE.md › Segurança + Migrations.
--
-- ORDEM DE APLICAÇÃO: rode este arquivo no SQL Editor DEPOIS de ter os price IDs
-- do Stripe test (gerados por `node scripts/stripe-seed.mjs`) — cole-os no bloco
-- de UPDATEs comentado lá embaixo antes de rodar (ou rode agora e cole os UPDATEs
-- depois, tanto faz: os UPDATEs são idempotentes).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- stripe_events — idempotência/anti-replay do webhook do Stripe.
-- PK = event.id do Stripe (ex.: 'evt_...'). Se o id já existe, o webhook não
-- reprocessa. Sem acesso a cliente; leitura só owner; escrita só server-side
-- (Edge Function via service_role, que ignora RLS).
-- -----------------------------------------------------------------------------
create table if not exists public.stripe_events (
  id            text primary key,          -- event.id do Stripe
  type          text,                      -- event.type (ex.: 'checkout.session.completed')
  processed_at  timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- profiles.stripe_customer_id — o Customer do Stripe do usuário (criado/reusado
-- na create-checkout-session). É gravado só server-side (service_role).
-- Não é segredo, mas fica atrás da RLS do profiles (só o dono/staff lê).
-- -----------------------------------------------------------------------------
alter table public.profiles add column if not exists stripe_customer_id text;

-- -----------------------------------------------------------------------------
-- subscriptions.stripe_subscription_id — UNIQUE pra o webhook fazer upsert
-- idempotente (uma linha por assinatura do Stripe). NULLs continuam permitidos
-- (múltiplos NULLs são distintos no índice único do Postgres — assinaturas
-- antigas/trial sem id do Stripe não colidem).
-- -----------------------------------------------------------------------------
create unique index if not exists subscriptions_stripe_sub_id_key
  on public.subscriptions (stripe_subscription_id);

-- =============================================================================
-- RLS — stripe_events: deny-by-default. Sem acesso a cliente; só owner lê.
-- Escrita só server-side (service_role ignora RLS) → sem policy de escrita.
-- =============================================================================
alter table public.stripe_events enable row level security;

drop policy if exists stripe_events_select_owner on public.stripe_events;
create policy stripe_events_select_owner on public.stripe_events
  for select to authenticated
  using (public.is_owner());

-- =============================================================================
-- PRICE IDs DO STRIPE (test mode) — preenchidos por `node scripts/stripe-seed.mjs`.
-- Idempotente: pode rodar de novo pra corrigir/atualizar. Se recriar os preços
-- no Stripe (novos price_id), rode o seed de novo e atualize estes valores.
--
-- (No dia do go-live LIVE: gerar produtos/preços em LIVE mode, pegar os price_id
--  live e rodar uma migration NOVA com os UPDATEs live — ver checklist no CLAUDE.md.)
-- =============================================================================
update public.tiers set stripe_price_id = 'price_1TtYEbFUPX1fv0T2ILYU9Vjb' where slug = 'bronze';
update public.tiers set stripe_price_id = 'price_1TtYEcFUPX1fv0T27M5aHMSi' where slug = 'prata';
update public.tiers set stripe_price_id = 'price_1TtYEdFUPX1fv0T29Hw7Rli5' where slug = 'ouro';
update public.tiers set stripe_price_id = 'price_1TtYEeFUPX1fv0T2o6C0thVl' where slug = 'diamante';
