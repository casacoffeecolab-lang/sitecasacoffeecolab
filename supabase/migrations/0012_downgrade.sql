-- =============================================================================
-- Casa Coffee Colab — 0012_downgrade.sql
-- DOWNGRADE de assinatura AGENDADO (vale no próximo ciclo, sem reembolso).
-- Espelho ao contrário do upgrade: em vez de cobrar a diferença e subir na hora,
-- a pessoa MANTÉM o tier atual até o fim do período já pago (current_period_end)
-- e, no próximo vencimento, a assinatura renova já no plano mais leve.
--
-- Como funciona: a Edge Function `downgrade-subscription` baixa o `value` da
-- assinatura no Asaas (a PRÓXIMA cobrança já vem menor) e grava aqui o slug do
-- tier de destino — SEM mexer no tier atual. Quando o pagamento da renovação
-- cai, o webhook (asaas-webhook › handleSubscriptionPayment) troca o tier pra
-- este destino e LIMPA a coluna. "Desfazer" volta a coluna pra NULL e restaura o
-- `value` cheio no Asaas.
--
-- APPEND-ONLY e IMUTÁVEL (0001–0011 já aplicadas). Não edita nada anterior.
-- Idempotente: ADD COLUMN IF NOT EXISTS. Ver CLAUDE.md › Segurança + Migrations.
--
-- ORDEM DE APLICAÇÃO: rode este arquivo no SQL Editor DEPOIS da 0011.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- subscriptions.scheduled_downgrade_to — slug do tier de destino de um downgrade
-- AGENDADO (NULL = nenhum agendado, o caso normal). FK pra tiers.slug (PK dos
-- tiers é slug). ON DELETE SET NULL: se um tier for removido do catálogo, o
-- agendamento apenas se dissolve (não trava o delete nem quebra a assinatura).
-- Fica atrás da RLS já existente de subscriptions (o dono lê a própria linha; a
-- ESCRITA é só server-side via service_role na Edge Function / webhook).
-- -----------------------------------------------------------------------------
alter table public.subscriptions
  add column if not exists scheduled_downgrade_to text
  references public.tiers(slug) on delete set null;
