-- =============================================================================
-- Casa Coffee Colab — 0010_achievement_hints.sql
-- Fase 3 — conquistas: dá a cada emblema uma DICA acionável ("como desbloquear"),
-- separada do `descricao` (que é o texto poético, mostrado quando JÁ desbloqueou).
--
-- O front (initConquistasPage) mostra a `dica` no card BLOQUEADO, num bloco
-- "como desbloquear", e no tooltip dos mini-emblemas do painel do usuário.
--
-- APPEND-ONLY e IMUTÁVEL (0001–0009 já aplicadas). Idempotente:
-- ADD COLUMN IF NOT EXISTS + UPDATE por slug (reexecutável). Ver CLAUDE.md.
--
-- TOM DE VOZ (obrigatório): "tu"/"a gente", acolhedor, sem imperativo agressivo,
-- ZERO cara de cassino. As dicas espelham os CRITÉRIOS reais da 0009.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Coluna da dica (texto livre em PT). Null = sem dica (cai no fallback gentil).
-- -----------------------------------------------------------------------------
alter table public.achievements add column if not exists dica text;

-- -----------------------------------------------------------------------------
-- 2) Dicas dos 9 emblemas — uma por slug, alinhada ao critério da 0009.
-- -----------------------------------------------------------------------------

-- purchase_count >= 1 (qualquer compra paga).
update public.achievements
   set dica = 'faz teu primeiro pedido — aqui na loja ou lá no balcão.'
 where slug = 'primeira-xicara';

-- purchase_count >= 5, janela manhã (pedidos pagos antes do meio-dia).
update public.achievements
   set dica = 'passa cinco manhãs com a gente — pedidos antes do meio-dia contam.'
 where slug = 'manha-de-sempre';

-- tier = ouro (assinatura Gente do Casa).
update public.achievements
   set dica = 'vira assinante do plano Gente do Casa.'
 where slug = 'gente-do-casa';

-- tier = diamante (assinatura Alma do Casa).
update public.achievements
   set dica = 'vira assinante do plano Alma do Casa.'
 where slug = 'alma-do-casa';

-- product_category = cafe_grao (>= 1 numa compra paga).
update public.achievements
   set dica = 'leva um dos nossos cafés em grão pra casa.'
 where slug = 'cafe-viajante';

-- MANUAL (sem fonte de dados ainda) — desbloqueio no balcão.
update public.achievements
   set dica = 'traz alguém novo pra sentar na nossa mesa — a gente marca no balcão.'
 where slug = 'mesa-comprida';

-- MANUAL (o cardápio não tem SKU por doce) — desbloqueio no balcão.
update public.achievements
   set dica = 'prova todos os doces da casa — a gente confirma no balcão.'
 where slug = 'que-seja-doce';

-- purchase_count >= 4, janela domingo (pedidos pagos aos domingos).
update public.achievements
   set dica = 'vem a quatro brunchs de domingo — a mesa te espera.'
 where slug = 'domingo-de-brunch';

-- MANUAL (ainda não marcamos quais produtos são de residência) — balcão.
update public.achievements
   set dica = 'leva pra casa um produto feito na Residência Gente do Casa.'
 where slug = 'colab-de-vizinho';
