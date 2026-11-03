-- =============================================================================
-- Casa Coffee Colab — 0007_orders_stripe.sql
-- Fase 6b — checkout da LOJA (pagamento avulso). Prepara orders/order_items pro
-- webhook gravar o pedido pago, idempotente por sessão do Stripe.
--
-- APPEND-ONLY e IMUTÁVEL (0001–0006 já aplicadas). Idempotente:
-- ADD COLUMN IF NOT EXISTS / CREATE ... IF NOT EXISTS. NÃO renomeia nada.
-- Nomes canônicos travados (colunas em *_centavos, papéis, FKs por slug).
-- Ver CLAUDE.md › Segurança + Migrations.
--
-- AUDITORIA (o que a 0001 já criou — reusamos, NÃO duplicamos):
--   orders:      user_id (FK profiles) · status · subtotal_centavos ·
--                desconto_centavos · total_centavos · tier_slug_aplicado (FK tiers) ·
--                stripe_checkout_id · stripe_payment_intent · origem · created_at.
--   order_items: order_id (FK orders) · product_id (FK products) ·
--                variant_id (FK product_variants) · nome_snapshot ·
--                variante_snapshot · preco_unit_centavos · qtd.
--
-- Mapeamento com os nomes pedidos na spec da 6b (mesma semântica, nome canônico
-- que já existe — por isso NÃO criamos colunas novas com nomes em inglês, o que
-- só duplicaria dados):
--   subtotal_cents        → subtotal_centavos
--   discount_cents        → desconto_centavos
--   total_cents           → total_centavos
--   tier_slug_no_momento  → tier_slug_aplicado
--   stripe_session_id     → stripe_checkout_id   (guarda o cs_… do Checkout)
--   product_slug/variante → product_id/variant_id + *_snapshot (snapshot na compra)
--   unit_price_cents      → preco_unit_centavos
--
-- RLS já vem da 0002 (cliente só LÊ o próprio pedido; escrita só server-side via
-- service_role). Nada a mudar aqui além do índice de idempotência abaixo.
-- =============================================================================

-- Defensivo: se por algum motivo alguma coluna não existir no ambiente, cria.
-- (No banco padrão da 0001 todas já existem — estes ADDs são no-ops idempotentes.)
alter table public.orders add column if not exists stripe_checkout_id     text;
alter table public.orders add column if not exists stripe_payment_intent  text;
alter table public.orders add column if not exists tier_slug_aplicado     text references public.tiers (slug);

-- -----------------------------------------------------------------------------
-- Idempotência do webhook da LOJA: um pedido por sessão de Checkout do Stripe.
-- stripe_checkout_id guarda o `cs_…`. UNIQUE → o webhook faz upsert/skip sem
-- duplicar o pedido em reentregas do evento. NULLs seguem permitidos (múltiplos
-- NULLs são distintos no índice único do Postgres — pedidos de PDV sem cs_ ok).
-- -----------------------------------------------------------------------------
create unique index if not exists orders_stripe_checkout_id_key
  on public.orders (stripe_checkout_id);
