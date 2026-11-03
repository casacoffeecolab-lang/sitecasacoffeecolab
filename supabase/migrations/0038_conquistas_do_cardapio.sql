-- =============================================================================
-- 0038_conquistas_do_cardapio.sql — 50 conquistas tiradas do cardápio ☕🥐🍰
--
-- As nove conquistas do seed (0003/0009) falavam da relação com a casa (primeira
-- compra, virou rotina, assinou tal plano). Estas 50 falam do CARDÁPIO: provar o
-- Hot Latte Matcha, comer um bolo e um cookie, dividir um Platter Brunch, passar
-- pelos três métodos de café. Uma por item ou combinação real do impresso, nas
-- 16 seções, na ordem do cardápio.
--
-- ATENÇÃO, ELAS SÓ DESBLOQUEIAM QUANDO A FRENTE DE CAIXA ENTRAR:
--   O `check_achievements` (0009) só avalia o que o banco enxerga, e de consumo
--   ele só enxerga a LOJA (`orders` + `order_items` de produto: vestuário,
--   acessórios, café em grão). O `/cardapio` é informativo, sem carrinho e sem
--   SKU por item, então "tomou um matcha" ainda não existe como dado.
--   O caminho já está definido: o PDV vai mandar o consumo por webhook (a
--   `pos_webhook_events` da 0004 e o `POS_WEBHOOK_SECRET` estão reservados pra
--   isso desde a Fase 3). Por isso os critérios aqui embaixo já vêm ESCRITOS no
--   formato que esse webhook vai alimentar, em vez de um `manual` genérico: no
--   dia D não se reescreve conquista nenhuma, só se ensina a função a ler três
--   tipos novos.
--   Por isso elas nascem DESLIGADAS (`ativo = false`): ficam guardadas no banco,
--   invisíveis no site, e o placar da /conta/conquistas segue "x/9" em vez de
--   virar "x/59" com 50 cadeados que nada abre. O front já filtra por
--   `ativo = true` (initConquistasPage) e o check_achievements também só avalia
--   conquista ativa, então enquanto estiverem desligadas elas não aparecem nem
--   desbloqueiam.
--
--   PRA ACENDER, no dia em que a frente de caixa começar a mandar consumo:
--     update public.achievements set ativo = true where slug like 'cardapio-%';
--
-- Só conteúdo: nenhuma coluna, policy, função ou permissão muda aqui. O front
-- também não precisa de nada, os cards se montam da tabela (a única mudança lá é
-- cosmética: `ICONES_CONQUISTA` ganhou os ícones do cardápio, senão os 50 sairiam
-- todos com o troféu genérico).
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (`on conflict (slug) do update`).
-- =============================================================================

insert into public.achievements (slug, nome, descricao, icone, ordem, ativo) values
  -- ---- Clássicos do Casa -----------------------------------------------------
  ('cardapio-pao-de-queijo',      'Fornada da Hora',      'quentinho, direto do forno pra tua mão.',                   'sandwich',   10, false),
  ('cardapio-brioche-na-chapa',   'Brioche na Chapa',     'manteiga, chapa e queijo derretendo.',                      'sandwich',   11, false),
  ('cardapio-empanada',           'Empanada Argentina',   'um pedaço da Argentina no nosso balcão.',                   'sandwich',   12, false),

  -- ---- Brunch ----------------------------------------------------------------
  ('cardapio-crepioca',           'Crepioca Completa',    'três recheios, escolhidos do teu jeito.',                   'egg-fried',  13, false),
  ('cardapio-tuskany',            'Manhã Toscana',        'búfala e tomate assado, de manhã cedo.',                    'egg-fried',  14, false),
  ('cardapio-avo-brunch',         'Avo Brunch',           'avocado e bacon, o clássico do brunch.',                    'egg-fried',  15, false),
  ('cardapio-pancakes',           'Panqueca com Mel',     'mel escorrendo na panqueca americana.',                     'egg-fried',  16, false),
  ('cardapio-platter',            'Mesa pra Dividir',     'a bandeja que só faz sentido em dupla.',                    'heart',      17, false),

  -- ---- Bagel -----------------------------------------------------------------
  ('cardapio-bagel-classico',     'Bagel de Sempre',      'o bagel tostado de todo dia.',                              'donut',      18, false),
  ('cardapio-bagel-salmon',       'Bagel de Salmão',      'gravlax com picles de cebola roxa.',                        'donut',      19, false),
  ('cardapio-bagel-american',     'Bagel Americano',      'ovos cremosos e bacon no pão americano.',                   'donut',      20, false),

  -- ---- Croissant -------------------------------------------------------------
  ('cardapio-croissant-classico', 'Manteiga de Verdade',  'a folhada feita com manteiga de verdade.',                  'croissant',  21, false),
  ('cardapio-croissant-parma',    'Parma no Croissant',   'parma, brie e rúcula na folhada.',                          'croissant',  22, false),
  ('cardapio-croissant-salmon',   'Croissant de Salmão',  'gravlax e cream cheese dentro do croissant.',               'croissant',  23, false),

  -- ---- Sanduíches ------------------------------------------------------------
  ('cardapio-croque-madame',      'Croque Madame',        'bechamel, presunto e ovo frito por cima.',                  'sandwich',   24, false),
  ('cardapio-carne-de-panela',    'Carne de Panela',      'carne de panela, gorgonzola e aioli.',                      'sandwich',   25, false),
  ('cardapio-parma-pesto',        'Parma com Pesto',      'parma, búfala e pesto na baguete.',                         'sandwich',   26, false),

  -- ---- Toasts ----------------------------------------------------------------
  ('cardapio-avocado-morning',    'Avocado Morning',      'o verde que abre bem o dia.',                               'wheat',      27, false),
  ('cardapio-caprese',            'Caprese na Chapa',     'búfala, tomate assado e pesto no levain.',                  'wheat',      28, false),
  ('cardapio-funghi-eggs',        'Funghi e Eggs',        'cogumelo salteado com ovos cremosos.',                      'wheat',      29, false),
  ('cardapio-fig-parma',          'Figo e Parma',         'o doce do figo com o salgado da parma.',                    'wheat',      30, false),

  -- ---- Confeitaria -----------------------------------------------------------
  ('cardapio-bolo-gisele',        'Bolo Gisele',          'bolo de cenoura com brigadeiro quentinho.',                 'cake-slice', 31, false),
  ('cardapio-cheesecolab',        'Cheesecolab',          'a torta basca que some rápido.',                            'cake-slice', 32, false),
  ('cardapio-cookie',             'Cookie da Casa',       'o cookie que muda de sabor conforme o dia.',                'cookie',     33, false),
  ('cardapio-brownie-sorvete',    'Brownie com Sorvete',  'chocolatudo, com a bola derretendo em cima.',               'cake-slice', 34, false),
  ('cardapio-lab-rolls',          'Lab Rolls',            'canela e cobertura, feitas aqui no Casa.',                  'cake-slice', 35, false),
  ('cardapio-bolo-e-cookie',      'Doce em Dobro',        'porque escolher um só é difícil.',                          'star',       36, false),

  -- ---- Métodos ---------------------------------------------------------------
  ('cardapio-prensa-francesa',    'Prensa Francesa',      'o café que pede tempo pra ficar pronto.',                   'coffee',     37, false),
  ('cardapio-hario-v60',          'Hario V60',            'o filtro que deixa o grão falar.',                          'coffee',     38, false),
  ('cardapio-tres-metodos',       'Passa Café',           'prensa, V60 e drip, os três da casa.',                      'award',      39, false),

  -- ---- Puristas --------------------------------------------------------------
  ('cardapio-espresso',           'Espresso Puro',        'curto, intenso, sem nada por cima.',                        'coffee',     40, false),
  ('cardapio-carioca',            'Carioca de Balcão',    'setenta mililitros mais leves.',                            'coffee',     41, false),

  -- ---- Elaborados ------------------------------------------------------------
  ('cardapio-latte',              'Latte de Sempre',      'espresso e leite vaporizado, sem mistério.',                'milk',       42, false),
  ('cardapio-cappuccino',         'Cappuccino Italiano',  'no ristretto, do jeito de lá.',                             'milk',       43, false),
  ('cardapio-caramel-macchiato',  'Caramel Macchiato',    'caramelo no fundo, leite por cima.',                        'milk',       44, false),
  ('cardapio-mocha',              'Mocha',                'café e chocolate 50%, juntos na xícara.',                   'milk',       45, false),
  ('cardapio-choco-quente',       'Chocolate Cremoso',    'o cobertor de caneca dos dias frios.',                      'milk',       46, false),

  -- ---- Cafés gelados ---------------------------------------------------------
  ('cardapio-iced-black',         'Iced Black',           'espresso, água e gelo, nada mais.',                         'snowflake',  47, false),
  ('cardapio-iced-latte',         'Iced Latte',           'o latte que pede dia de calor.',                            'snowflake',  48, false),
  ('cardapio-coffee-tonic',       'Coffee Tonic',         'tônica, laranja e espresso, borbulhando.',                  'snowflake',  49, false),
  ('cardapio-orange-coffee',      'Café com Laranja',     'a dupla que ninguém espera e dá certo.',                    'citrus',     50, false),

  -- ---- Matcha ----------------------------------------------------------------
  ('cardapio-hot-latte-matcha',   'Hot Latte Matcha',     'matcha Namu com leite vaporizado.',                         'leaf',       51, false),
  ('cardapio-iced-latte-matcha',  'Matcha Gelado',        'o verde da casa, agora com gelo.',                          'leaf',       52, false),
  ('cardapio-strawberry-matcha',  'Matcha com Morango',   'purê de morango no fundo do copo.',                         'leaf',       53, false),
  ('cardapio-tour-do-matcha',     'Tour do Matcha',       'quatro matchas diferentes, um de cada vez.',                'award',      54, false),

  -- ---- Chás ------------------------------------------------------------------
  ('cardapio-blend-tea',          'Chá Quentinho',        'o blend de chá que muda com a estação.',                    'glass-water',55, false),
  ('cardapio-iced-tea',           'Iced Tea da Casa',     'hibisco ou capim limão, com limão e gelo.',                 'glass-water',56, false),

  -- ---- Juices e sodas --------------------------------------------------------
  ('cardapio-suco-verde',         'Suco Verde',           'couve, abacaxi, limão, maracujá e gengibre.',               'citrus',     57, false),
  ('cardapio-suco-do-dia',        'Suco do Dia',          'a fruta que chegou boa na feira.',                          'citrus',     58, false),

  -- ---- Alcoólicos ------------------------------------------------------------
  ('cardapio-taca-de-vinho',      'Taça no Fim da Tarde', 'quando o café dá lugar à taça.',                            'wine',       59, false)
on conflict (slug) do update set
  nome      = excluded.nome,
  descricao = excluded.descricao,
  icone     = excluded.icone,
  ordem     = excluded.ordem;
-- Nota: o `ativo` de propósito NÃO entra no update acima. Rodar este arquivo de
-- novo depois de acender as 50 não as apagaria da tela sem querer.

-- -----------------------------------------------------------------------------
-- CRITÉRIOS: já escritos no formato que o PDV vai alimentar.
--
-- Hoje o `check_achievements` (0009) não conhece estes três tipos, e o `case`
-- dele manda tipo desconhecido pro mesmo lugar que manda `manual`: não
-- desbloqueia, não estoura, não atrapalha a avaliação das outras conquistas.
-- Ou seja, aplicar isto agora é seguro e não muda comportamento nenhum.
--
-- Quando a frente de caixa começar a mandar o consumo, o trabalho vira: gravar
-- o que veio (a `pos_webhook_events` da 0004 já está reservada pro evento cru) e
-- ensinar o `check_achievements` a ler estes três tipos. Nenhuma destas 50
-- linhas precisa ser reescrita.
--
--   {"type":"menu_item","itens":[…]}            → consumiu QUALQUER um da lista.
--   {"type":"menu_item_distintos","itens":[…],
--    "min":N}                                   → consumiu N itens DIFERENTES da lista.
--   {"type":"menu_item_combo","grupos":[[…],[…]],
--    "janela":"mesma_visita"}                   → um item de CADA grupo, na mesma visita.
--
-- Os `itens` usam o slug do nome do item no cardápio, pela mesma regra do
-- `slugify` que o `cardapio_favoritos` (0027) já usa: sem acento, minúsculo,
-- espaço vira hífen. Quatro nomes se repetem entre seções ("Clássico" no bagel e
-- no croissant, "Presunto + queijo" no croissant e no sanduíche, "Carne de
-- panela" no sanduíche e nos adicionais), então esses vão qualificados
-- (`bagel-classico`, `croissant-classico`, `sanduiche-carne-de-panela`). Quando
-- o PDV entrar, vai precisar de um de-para entre o código dele e estes slugs.
-- -----------------------------------------------------------------------------
update public.achievements set criterios = '{"type":"menu_item","itens":["pao-de-queijo"]}'::jsonb
 where slug = 'cardapio-pao-de-queijo';
update public.achievements set criterios = '{"type":"menu_item","itens":["misto-quente","queijo-quente"]}'::jsonb
 where slug = 'cardapio-brioche-na-chapa';
update public.achievements set criterios = '{"type":"menu_item","itens":["empanadas"]}'::jsonb
 where slug = 'cardapio-empanada';
update public.achievements set criterios = '{"type":"menu_item","itens":["crepioca"]}'::jsonb
 where slug = 'cardapio-crepioca';
update public.achievements set criterios = '{"type":"menu_item","itens":["tuskany-morning"]}'::jsonb
 where slug = 'cardapio-tuskany';
update public.achievements set criterios = '{"type":"menu_item","itens":["avo-brunch"]}'::jsonb
 where slug = 'cardapio-avo-brunch';
update public.achievements set criterios = '{"type":"menu_item","itens":["sunny-honey-pancakes"]}'::jsonb
 where slug = 'cardapio-pancakes';
update public.achievements set criterios = '{"type":"menu_item","itens":["platter-brunch"]}'::jsonb
 where slug = 'cardapio-platter';
update public.achievements set criterios = '{"type":"menu_item","itens":["bagel-classico"]}'::jsonb
 where slug = 'cardapio-bagel-classico';
update public.achievements set criterios = '{"type":"menu_item","itens":["salmon-bagel"]}'::jsonb
 where slug = 'cardapio-bagel-salmon';
update public.achievements set criterios = '{"type":"menu_item","itens":["american-bagel"]}'::jsonb
 where slug = 'cardapio-bagel-american';
update public.achievements set criterios = '{"type":"menu_item","itens":["croissant-classico"]}'::jsonb
 where slug = 'cardapio-croissant-classico';
update public.achievements set criterios = '{"type":"menu_item","itens":["parma-brie-rucula"]}'::jsonb
 where slug = 'cardapio-croissant-parma';
update public.achievements set criterios = '{"type":"menu_item","itens":["salmon-croissant"]}'::jsonb
 where slug = 'cardapio-croissant-salmon';
update public.achievements set criterios = '{"type":"menu_item","itens":["croque-madame"]}'::jsonb
 where slug = 'cardapio-croque-madame';
update public.achievements set criterios = '{"type":"menu_item","itens":["sanduiche-carne-de-panela"]}'::jsonb
 where slug = 'cardapio-carne-de-panela';
update public.achievements set criterios = '{"type":"menu_item","itens":["parma-pesto"]}'::jsonb
 where slug = 'cardapio-parma-pesto';
update public.achievements set criterios = '{"type":"menu_item","itens":["avocado-morning"]}'::jsonb
 where slug = 'cardapio-avocado-morning';
update public.achievements set criterios = '{"type":"menu_item","itens":["caprese"]}'::jsonb
 where slug = 'cardapio-caprese';
update public.achievements set criterios = '{"type":"menu_item","itens":["funghi-eggs"]}'::jsonb
 where slug = 'cardapio-funghi-eggs';
update public.achievements set criterios = '{"type":"menu_item","itens":["fig-parma"]}'::jsonb
 where slug = 'cardapio-fig-parma';
update public.achievements set criterios = '{"type":"menu_item","itens":["bolo-gisele"]}'::jsonb
 where slug = 'cardapio-bolo-gisele';
update public.achievements set criterios = '{"type":"menu_item","itens":["cheesecolab"]}'::jsonb
 where slug = 'cardapio-cheesecolab';
update public.achievements set criterios = '{"type":"menu_item","itens":["cookie-gourmet"]}'::jsonb
 where slug = 'cardapio-cookie';
update public.achievements set criterios = '{"type":"menu_item_combo","grupos":[["brownie"],["sorvete"]],"janela":"mesma_visita"}'::jsonb
 where slug = 'cardapio-brownie-sorvete';
update public.achievements set criterios = '{"type":"menu_item","itens":["lab-rolls"]}'::jsonb
 where slug = 'cardapio-lab-rolls';
update public.achievements set criterios = '{"type":"menu_item_combo","grupos":[["bolo-gisele","petit-lab","cakelab"],["cookie-gourmet"]],"janela":"mesma_visita"}'::jsonb
 where slug = 'cardapio-bolo-e-cookie';
update public.achievements set criterios = '{"type":"menu_item","itens":["prensa-francesa"]}'::jsonb
 where slug = 'cardapio-prensa-francesa';
update public.achievements set criterios = '{"type":"menu_item","itens":["hario-v60"]}'::jsonb
 where slug = 'cardapio-hario-v60';
update public.achievements set criterios = '{"type":"menu_item_distintos","itens":["prensa-francesa","hario-v60","drip-coffee-bunn"],"min":3}'::jsonb
 where slug = 'cardapio-tres-metodos';
update public.achievements set criterios = '{"type":"menu_item","itens":["espresso"]}'::jsonb
 where slug = 'cardapio-espresso';
update public.achievements set criterios = '{"type":"menu_item","itens":["carioca"]}'::jsonb
 where slug = 'cardapio-carioca';
update public.achievements set criterios = '{"type":"menu_item","itens":["latte"]}'::jsonb
 where slug = 'cardapio-latte';
update public.achievements set criterios = '{"type":"menu_item","itens":["cappuccino-italiano"]}'::jsonb
 where slug = 'cardapio-cappuccino';
update public.achievements set criterios = '{"type":"menu_item","itens":["caramel-macchiato"]}'::jsonb
 where slug = 'cardapio-caramel-macchiato';
update public.achievements set criterios = '{"type":"menu_item","itens":["mocha"]}'::jsonb
 where slug = 'cardapio-mocha';
update public.achievements set criterios = '{"type":"menu_item","itens":["choco-quente"]}'::jsonb
 where slug = 'cardapio-choco-quente';
update public.achievements set criterios = '{"type":"menu_item","itens":["iced-black"]}'::jsonb
 where slug = 'cardapio-iced-black';
update public.achievements set criterios = '{"type":"menu_item","itens":["iced-latte"]}'::jsonb
 where slug = 'cardapio-iced-latte';
update public.achievements set criterios = '{"type":"menu_item","itens":["coffee-tonic"]}'::jsonb
 where slug = 'cardapio-coffee-tonic';
update public.achievements set criterios = '{"type":"menu_item","itens":["orange-coffee"]}'::jsonb
 where slug = 'cardapio-orange-coffee';
update public.achievements set criterios = '{"type":"menu_item","itens":["hot-latte-matcha"]}'::jsonb
 where slug = 'cardapio-hot-latte-matcha';
update public.achievements set criterios = '{"type":"menu_item","itens":["iced-latte-matcha"]}'::jsonb
 where slug = 'cardapio-iced-latte-matcha';
update public.achievements set criterios = '{"type":"menu_item","itens":["strawberry-matcha"]}'::jsonb
 where slug = 'cardapio-strawberry-matcha';
update public.achievements set criterios = '{"type":"menu_item_distintos","itens":["hot-latte-matcha","hot-vanilla-matcha","iced-latte-matcha","vanilla-iced-matcha","caramel-iced-matcha","strawberry-matcha","passion-matcha","orange-matcha"],"min":4}'::jsonb
 where slug = 'cardapio-tour-do-matcha';
update public.achievements set criterios = '{"type":"menu_item","itens":["blend-tea"]}'::jsonb
 where slug = 'cardapio-blend-tea';
update public.achievements set criterios = '{"type":"menu_item","itens":["hibisco-iced-tea","capim-limao-iced-tea"]}'::jsonb
 where slug = 'cardapio-iced-tea';
update public.achievements set criterios = '{"type":"menu_item","itens":["suco-verde"]}'::jsonb
 where slug = 'cardapio-suco-verde';
update public.achievements set criterios = '{"type":"menu_item","itens":["suco-natural-ou-integral"]}'::jsonb
 where slug = 'cardapio-suco-do-dia';
update public.achievements set criterios = '{"type":"menu_item","itens":["vinho-taca-ou-garrafa"]}'::jsonb
 where slug = 'cardapio-taca-de-vinho';

-- -----------------------------------------------------------------------------
-- Dicas ("como desbloquear"), no tom da casa: o que pedir no balcão. Aparecem no
-- cartão bloqueado da /conta/conquistas e no tooltip dos emblemas do painel.
-- -----------------------------------------------------------------------------
update public.achievements set dica = 'pede um pão de queijo, ele sai quentinho do forno.'                    where slug = 'cardapio-pao-de-queijo';
update public.achievements set dica = 'pede um misto quente ou um queijo quente, os dois valem.'               where slug = 'cardapio-brioche-na-chapa';
update public.achievements set dica = 'pede uma empanada, ela vem recheada de carne, azeitona e ovo.'         where slug = 'cardapio-empanada';
update public.achievements set dica = 'pede uma crepioca e escolhe os três recheios.'                          where slug = 'cardapio-crepioca';
update public.achievements set dica = 'pede o Tuskany Morning, com búfala e tomate assado.'                    where slug = 'cardapio-tuskany';
update public.achievements set dica = 'pede o Avo Brunch, com creme de avocado e bacon.'                       where slug = 'cardapio-avo-brunch';
update public.achievements set dica = 'pede as Sunny Honey Pancakes, com mel e manteiga.'                      where slug = 'cardapio-pancakes';
update public.achievements set dica = 'pede o Platter Brunch, ele é feito pra dividir.'                        where slug = 'cardapio-platter';
update public.achievements set dica = 'pede o bagel clássico, com cream cheese ou manteiga.'                   where slug = 'cardapio-bagel-classico';
update public.achievements set dica = 'pede o Salmon Bagel, com gravlax e picles de cebola roxa.'              where slug = 'cardapio-bagel-salmon';
update public.achievements set dica = 'pede o American Bagel, com ovos cremosos e bacon.'                      where slug = 'cardapio-bagel-american';
update public.achievements set dica = 'pede o croissant clássico, com cream cheese, manteiga ou geleia.'       where slug = 'cardapio-croissant-classico';
update public.achievements set dica = 'pede o croissant de parma, brie e rúcula.'                              where slug = 'cardapio-croissant-parma';
update public.achievements set dica = 'pede o Salmon Croissant, com cream cheese e gravlax.'                   where slug = 'cardapio-croissant-salmon';
update public.achievements set dica = 'pede o croque madame, com bechamel e ovo frito.'                        where slug = 'cardapio-croque-madame';
update public.achievements set dica = 'pede o sanduíche de carne de panela, com gorgonzola e aioli.'           where slug = 'cardapio-carne-de-panela';
update public.achievements set dica = 'pede o sanduíche de parma, búfala e pesto.'                             where slug = 'cardapio-parma-pesto';
update public.achievements set dica = 'pede o Avocado Morning, com creme de avocado e ovos cremosos.'          where slug = 'cardapio-avocado-morning';
update public.achievements set dica = 'pede o toast caprese, com búfala, tomate assado e pesto.'               where slug = 'cardapio-caprese';
update public.achievements set dica = 'pede o Funghi & Eggs, com cogumelo salteado e cebolete.'                where slug = 'cardapio-funghi-eggs';
update public.achievements set dica = 'pede o Fig & Parma, com brie, figo e molho especial.'                   where slug = 'cardapio-fig-parma';
update public.achievements set dica = 'pede o Bolo Gisele, ele vem com brigadeiro de panela quentinho.'        where slug = 'cardapio-bolo-gisele';
update public.achievements set dica = 'pede o Cheesecolab, de frutas vermelhas ou de doce de leite.'           where slug = 'cardapio-cheesecolab';
update public.achievements set dica = 'pede um cookie gourmet e pergunta o sabor do dia.'                      where slug = 'cardapio-cookie';
update public.achievements set dica = 'pede o brownie e soma o adicional de sorvete.'                          where slug = 'cardapio-brownie-sorvete';
update public.achievements set dica = 'pede o Lab Rolls e escolhe a cobertura do dia.'                         where slug = 'cardapio-lab-rolls';
update public.achievements set dica = 'pede um bolo e um cookie na mesma visita, a gente anota no balcão.'     where slug = 'cardapio-bolo-e-cookie';
update public.achievements set dica = 'pede o café da prensa francesa, de 300ml ou 500ml.'                     where slug = 'cardapio-prensa-francesa';
update public.achievements set dica = 'pede o café passado no Hario V60.'                                      where slug = 'cardapio-hario-v60';
update public.achievements set dica = 'passa pelos três: prensa francesa, V60 e drip coffee.'                  where slug = 'cardapio-tres-metodos';
update public.achievements set dica = 'pede um espresso curto, do jeito purista.'                              where slug = 'cardapio-espresso';
update public.achievements set dica = 'pede um carioca, os 70ml mais leves do balcão.'                         where slug = 'cardapio-carioca';
update public.achievements set dica = 'pede um latte, com o leite que tu preferir.'                            where slug = 'cardapio-latte';
update public.achievements set dica = 'pede o cappuccino italiano, feito no ristretto.'                        where slug = 'cardapio-cappuccino';
update public.achievements set dica = 'pede o caramel macchiato.'                                              where slug = 'cardapio-caramel-macchiato';
update public.achievements set dica = 'pede o mocha, com calda de chocolate 50%.'                              where slug = 'cardapio-mocha';
update public.achievements set dica = 'pede um choco quente, o cremoso da casa.'                               where slug = 'cardapio-choco-quente';
update public.achievements set dica = 'pede um iced black em dia de calor.'                                    where slug = 'cardapio-iced-black';
update public.achievements set dica = 'pede um iced latte, com o leite que tu preferir.'                       where slug = 'cardapio-iced-latte';
update public.achievements set dica = 'pede o coffee tonic, com água tônica e laranja.'                        where slug = 'cardapio-coffee-tonic';
update public.achievements set dica = 'pede o orange coffee, espresso com suco de laranja.'                    where slug = 'cardapio-orange-coffee';
update public.achievements set dica = 'pede o hot latte matcha, matcha Namu com leite vaporizado.'             where slug = 'cardapio-hot-latte-matcha';
update public.achievements set dica = 'pede o iced latte matcha, com gelo.'                                    where slug = 'cardapio-iced-latte-matcha';
update public.achievements set dica = 'pede o strawberry matcha, com purê de morango.'                         where slug = 'cardapio-strawberry-matcha';
update public.achievements set dica = 'prova quatro matchas diferentes da nossa carta.'                        where slug = 'cardapio-tour-do-matcha';
update public.achievements set dica = 'pede o blend tea quentinho e consulta as opções do dia.'                where slug = 'cardapio-blend-tea';
update public.achievements set dica = 'pede o iced tea, de hibisco ou de capim limão.'                         where slug = 'cardapio-iced-tea';
update public.achievements set dica = 'pede o suco verde, com couve, abacaxi, limão, maracujá e gengibre.'     where slug = 'cardapio-suco-verde';
update public.achievements set dica = 'pede o suco natural do dia e pergunta qual é a fruta.'                  where slug = 'cardapio-suco-do-dia';
update public.achievements set dica = 'fica pra uma taça de vinho no fim da tarde.'                            where slug = 'cardapio-taca-de-vinho';
