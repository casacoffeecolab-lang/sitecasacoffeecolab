-- =============================================================================
-- 0049_preco_do_clube.sql — a assinatura do clube passa a R$88,90 💛
--
-- O PEDIDO (18/ago/2026, direto da casa): o valor da assinatura sobe de R$49,90
-- pra R$88,90. O R$49,90 da 0048 era o "valor estratégico inicial, a validar" que
-- o documento do CASA CLUB já marcava como provisório.
--
-- POR QUE É ARQUIVO NOVO E NÃO UMA EDIÇÃO DA 0048: migration aplicada é imutável
-- (a 0048 já rodou em produção em 18/ago). Mudança nova = arquivo novo.
--
-- AS QUATRO CATEGORIAS ANDAM JUNTAS. Elas custam o mesmo desde a 0048, porque a
-- categoria é tempo de casa e não preço. Deixar só a vendável subir criaria uma
-- escada de preço fantasma no banco: ninguém compra as outras três hoje, mas a
-- `create-checkout-session` lê `preco_centavos` do tier pra montar o valor do
-- presente e do checkout, e o dia em que alguma delas voltar a ser vendável ela
-- estaria com o preço velho.
--
-- O QUE ESTE ARQUIVO **NÃO** FAZ: mexer nas assinaturas que já existem no Asaas.
-- Lá o `value` de cada assinatura foi gravado no dia em que ela nasceu, e só muda
-- por `PUT /subscriptions/{id}`. Então quem já assina **segue pagando o valor
-- antigo** até alguém mudar no painel do Asaas, e isso é decisão da casa (mexer no
-- preço de assinatura viva é conversa com quem assinou, não migration). O preço
-- novo vale pra quem assinar de agora em diante, e pros presentes comprados daqui
-- pra frente.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente.
-- =============================================================================

update public.tiers
   set preco_centavos = 8890
 where slug in ('bronze', 'prata', 'ouro', 'diamante');
