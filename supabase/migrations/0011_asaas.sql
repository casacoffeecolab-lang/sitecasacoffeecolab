-- =============================================================================
-- Casa Coffee Colab — 0011_asaas.sql
-- Troca do gateway de pagamento: Stripe → ASAAS (Pix + Cartão, Checkout hospedado).
-- Cobre LOJA (pagamento avulso) e ASSINATURA (4 tiers, recorrente mensal).
--
-- APPEND-ONLY e IMUTÁVEL (0001–0010 já aplicadas). NÃO edita/renomeia nada das
-- migrations anteriores — as colunas do Stripe (stripe_*) PERMANECEM no banco
-- (migrations passadas são imutáveis), apenas deixam de ser usadas pelo código.
-- Idempotente: ADD COLUMN IF NOT EXISTS / CREATE ... IF NOT EXISTS /
-- drop policy if exists. Ver CLAUDE.md › Segurança + Migrations.
--
-- ORDEM DE APLICAÇÃO: rode este arquivo no SQL Editor DEPOIS da 0010.
-- NÃO precisa de seed de "price id" — no Asaas a assinatura é criada com o
-- `value` (preço do tier em reais) direto; não existe objeto de preço a semear.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- profiles.asaas_customer_id — o Customer do Asaas do usuário (id retornado pelo
-- Asaas quando o checkout é pago; gravado só server-side via service_role no
-- webhook). Fica atrás da RLS do profiles (só o dono/staff lê). Não é segredo.
-- -----------------------------------------------------------------------------
alter table public.profiles add column if not exists asaas_customer_id text;

-- -----------------------------------------------------------------------------
-- subscriptions — ids do Asaas. asaas_subscription_id UNIQUE pro webhook fazer
-- upsert idempotente (uma linha por assinatura do Asaas). NULLs continuam
-- permitidos (múltiplos NULLs são distintos no índice único do Postgres —
-- assinaturas antigas/trial sem id não colidem).
-- -----------------------------------------------------------------------------
alter table public.subscriptions add column if not exists asaas_customer_id     text;
alter table public.subscriptions add column if not exists asaas_subscription_id text;
create unique index if not exists subscriptions_asaas_sub_id_key
  on public.subscriptions (asaas_subscription_id);

-- -----------------------------------------------------------------------------
-- orders — ids do Asaas.
--   asaas_checkout_id: o id do Checkout do Asaas (chk_...). UNIQUE → idempotência
--     da LOJA. Como a gente PRÉ-CRIA o pedido 'pendente' já com este id e usa o
--     `orders.id` como externalReference do checkout, o webhook só finaliza o
--     pedido existente (não duplica em reentregas do evento).
--   asaas_payment_id: id do pagamento gerado (best-effort; auditoria).
-- NULLs permitidos (pedidos de PDV sem checkout do Asaas).
-- -----------------------------------------------------------------------------
alter table public.orders add column if not exists asaas_checkout_id text;
alter table public.orders add column if not exists asaas_payment_id  text;
create unique index if not exists orders_asaas_checkout_id_key
  on public.orders (asaas_checkout_id);

-- -----------------------------------------------------------------------------
-- asaas_events — idempotência/anti-replay do webhook do Asaas.
-- PK = id do evento do Asaas (campo `id` do payload, ex.: 'evt_...'). Se o id já
-- existe, o webhook não reprocessa. Sem acesso a cliente; leitura só owner;
-- escrita só server-side (Edge Function via service_role, que ignora RLS).
-- Espelha a stripe_events da 0006.
-- -----------------------------------------------------------------------------
create table if not exists public.asaas_events (
  id            text primary key,          -- id do evento do Asaas
  event         text,                      -- tipo do evento (ex.: 'CHECKOUT_PAID')
  processed_at  timestamptz not null default now()
);

-- =============================================================================
-- RLS — asaas_events: deny-by-default. Sem acesso a cliente; só owner lê.
-- Escrita só server-side (service_role ignora RLS) → sem policy de escrita.
-- =============================================================================
alter table public.asaas_events enable row level security;

drop policy if exists asaas_events_select_owner on public.asaas_events;
create policy asaas_events_select_owner on public.asaas_events
  for select to authenticated
  using (public.is_owner());
