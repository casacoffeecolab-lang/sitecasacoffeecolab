-- =============================================================================
-- 0012_asaas_checkout_link — ponte assinatura ↔ checkout do Asaas.
--
-- POR QUÊ (causa-raiz do "plano não vincula", provada por log ao vivo):
--   Nenhum evento do Asaas carrega, sozinho, as 3 peças que a gente precisa
--   ({user_id, tier_slug, asaas_subscription_id}):
--     • CHECKOUT_PAID  → tem o nosso externalReference (`sub:<user>:<tier>:<nonce>`),
--       logo sabe o USER e o TIER — mas NÃO traz o id da assinatura (o campo
--       `subscription` é só a config `{cycle,nextDueDate}`), e o Asaas NÃO indexa
--       a assinatura pelo nosso externalReference (GET ?externalReference volta ∅).
--     • PAYMENT_*      → traz o `subscription` id (`sub_…`) e o `customer` (`cus_…`),
--       mas com externalReference ∅ → não sabe de QUEM é.
--   O ÚNICO elo comum às duas pontas é o ID DO CHECKOUT: a gente o cria e recebe de
--   volta, ele vem no CHECKOUT_PAID (`checkout.id`) e no pagamento
--   (`payment.checkoutSession`). É o mesmo padrão que a LOJA já usa com sucesso
--   (orders.asaas_checkout_id). Guardando-o na linha da assinatura, o CHECKOUT_PAID
--   vincula user+tier na hora e o PAYMENT completa o asaas_subscription_id + pontos.
--
-- SEGURO / IDEMPOTENTE: só ADICIONA uma coluna nullable + índice único (não-parcial).
--   Não mexe em nada existente (as colunas stripe_*/asaas_* anteriores ficam intactas).
--   Re-rodar não quebra (IF NOT EXISTS).
--
-- Aplicar no SQL Editor do Supabase DEPOIS da 0011_asaas.
-- =============================================================================

alter table public.subscriptions
  add column if not exists asaas_checkout_id text;

comment on column public.subscriptions.asaas_checkout_id is
  'ID do Asaas Checkout que originou esta assinatura. Elo de correlação entre o '
  'CHECKOUT_PAID (checkout.id → grava user/tier) e o PAYMENT '
  '(payment.checkoutSession → completa o asaas_subscription_id + pontos). '
  'NULL em renovações e em linhas legadas.';

-- Único NÃO-parcial (espelha subscriptions_asaas_sub_id_key da 0011): no máximo UMA
-- assinatura por checkout. NULLs são DISTINTOS num índice único do Postgres, então
-- VÁRIAS linhas com asaas_checkout_id NULL (renovações / legado) continuam permitidas
-- — não precisa de índice parcial pra isso.
--
-- POR QUE NÃO-PARCIAL (importante): o upsert do webhook usa
-- `.upsert(..., { onConflict: 'asaas_checkout_id' })`, que o PostgREST traduz pra
-- `ON CONFLICT (asaas_checkout_id)` SEM predicado. O Postgres NÃO consegue inferir um
-- índice único PARCIAL como árbitro sem o `WHERE` no ON CONFLICT (erro 42P10), e o
-- PostgREST não emite esse `WHERE`. Um índice não-parcial é inferido direto — igual ao
-- `asaas_subscription_id` (0011), que por isso funciona com o mesmo padrão de upsert.
create unique index if not exists ux_subscriptions_asaas_checkout
  on public.subscriptions (asaas_checkout_id);
