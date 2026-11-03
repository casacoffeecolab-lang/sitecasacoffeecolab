-- =============================================================================
-- 0039_slug_carne_de_panela.sql — acerta UM slug de item nos critérios da 0038
--
-- A 0038 escreveu o critério da conquista `cardapio-carne-de-panela` como
-- `sanduiche-carne-de-panela`, no singular. O front deriva esse slug sozinho, a
-- partir do título da seção do cardápio ("Sanduíches"), então o que ele produz
-- é `sanduiches-carne-de-panela`. Dois nomes pro mesmo prato é de-para errado no
-- dia em que a frente de caixa entrar: a conquista simplesmente nunca abriria.
--
-- POR QUE existe o sufixo: o slug do item sai do NOME, e quatro nomes se repetem
-- entre seções do impresso ("Clássico" no bagel e no croissant, "Presunto +
-- queijo" no croissant e no sanduíche, "Carne de panela" no sanduíche e nos
-- adicionais). Esses vão qualificados pelo título da seção, tanto aqui quanto no
-- `cardapio_favoritos` (0027) — que é de onde veio o problema: o segundo item de
-- cada dupla colidia com o primeiro e ficava sem o coração de favoritar.
--
-- Só conteúdo, e só uma linha: nenhuma coluna, policy, função ou permissão muda.
-- As 50 conquistas do cardápio seguem DESLIGADAS (`ativo = false`), como a 0038
-- as criou — este arquivo não acende nenhuma.
--
-- APLICAR: rodar no SQL Editor do Supabase, uma vez. Idempotente (o `where`
-- ignora a linha que já está certa, então reaplicar não faz nada).
-- =============================================================================

update public.achievements
   set criterios = '{"type":"menu_item","itens":["sanduiches-carne-de-panela"]}'::jsonb
 where slug = 'cardapio-carne-de-panela'
   and criterios is distinct from '{"type":"menu_item","itens":["sanduiches-carne-de-panela"]}'::jsonb;
