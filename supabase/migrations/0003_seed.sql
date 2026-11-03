-- =============================================================================
-- Casa Coffee Colab — 0003_seed.sql
-- Seed dos 4 tiers, 10 produtos + variantes, 9 conquistas e parceiros locais.
--
-- APPEND-ONLY e IMUTÁVEL. Idempotente: upsert (ON CONFLICT DO UPDATE / DO NOTHING)
-- — pode rodar de novo sem duplicar. Preços em centavos, iguais aos do app.js.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TIERS (planos de assinatura). * valores fictícios, a definir.
-- -----------------------------------------------------------------------------
insert into public.tiers (slug, nome, preco_centavos, desconto_pct, pontos_multiplicador, destaque, ordem) values
  ('bronze',   'Vizinho de Sempre',  2990,  3, 1.00, false, 1),
  ('prata',    'Frequentador',       4990,  6, 1.25, false, 2),
  ('ouro',     'Gente do Casa',      7990, 10, 1.50, true,  3),
  ('diamante', 'Alma do Casa',      12990, 15, 2.00, false, 4)
on conflict (slug) do update set
  nome                 = excluded.nome,
  preco_centavos       = excluded.preco_centavos,
  desconto_pct         = excluded.desconto_pct,
  pontos_multiplicador = excluded.pontos_multiplicador,
  destaque             = excluded.destaque,
  ordem                = excluded.ordem;

-- -----------------------------------------------------------------------------
-- PRODUCTS (10). Mesmos slug/nome/preço/categoria/placeholder do array PRODUTOS.
-- -----------------------------------------------------------------------------
insert into public.products (slug, nome, categoria, preco_centavos, descricao, imagem_placeholder) values
  ('cafe-alma-do-casa-250g', 'Café em grão · Alma do Casa · 250g', 'cafe_grao', 4990,
    'Nosso blend autoral — encorpado, de final doce. Torrado em micro-lote pra chegar fresquinho na tua xícara.', 'photo-warm'),
  ('cafe-torra-vale-dos-sinos-250g', 'Café em grão · Torra Vale dos Sinos · 250g', 'cafe_grao', 5490,
    'Micro-lote de um produtor vizinho, com notas de castanha e caramelo. A gente serve por tempo limitado.', 'photo-green'),
  ('cafe-descafeinado-afeto-250g', 'Café em grão · Descafeinado Afeto · 250g', 'cafe_grao', 5290,
    'Pra ficar um pouco mais sem perder o sono. Descafeinado suave, doce e redondo — no teu ritmo.', 'photo-bege'),
  ('moletom-casa-coffee', 'Moletom Casa Coffee', 'vestuario', 19990,
    'Quentinho pra vestir nos dias de café e chuva. Algodão macio, bordado discreto do Casa no peito.', 'photo-green'),
  ('camiseta-feito-no-casa', 'Camiseta "feito no Casa"', 'vestuario', 8990,
    'Leve, de algodão, com a nossa frase preferida estampada. Pra levar um pedacinho do Casa por aí.', 'photo-warm'),
  ('avental-do-casa', 'Avental do Casa', 'vestuario', 11990,
    'O mesmo avental que a gente usa na cozinha. Linho encorpado, bolso na frente, feito pra durar.', 'photo-bege'),
  ('caneca-de-autor', 'Caneca de autor', 'acessorios', 5990,
    'Cerâmica feita à mão pelo Ateliê Lomba Grande, em residência com a gente. Cada peça é única.', 'photo-warm'),
  ('bolsa-de-linho', 'Bolsa de linho', 'acessorios', 7990,
    'Do tamanho certo pra um livro, o café e o resto do dia. Linho natural que envelhece bonito.', 'photo-green'),
  ('ecobag-passa-aqui', 'Ecobag "passa aqui?"', 'acessorios', 3990,
    'Nosso convite favorito, pra carregar junto. Algodão cru, alça reforçada, cabe a feira inteira.', 'photo-bege'),
  ('kit-coador-filtro-pano', 'Kit coador + filtro de pano', 'acessorios', 6990,
    'Pra fazer em casa o café que tu toma aqui. Suporte de madeira e filtro de pano reutilizável.', 'photo-warm')
on conflict (slug) do update set
  nome               = excluded.nome,
  categoria          = excluded.categoria,
  preco_centavos     = excluded.preco_centavos,
  descricao          = excluded.descricao,
  imagem_placeholder = excluded.imagem_placeholder;

-- -----------------------------------------------------------------------------
-- PRODUCT_VARIANTS. Insert-select por slug do produto (idempotente por (product_id, opcao)).
-- Cafés → Moagem (3 opções). Moletom/Camiseta → Tamanho P/M/G/GG. Avental → Único.
-- Demais acessórios não têm variante.
-- -----------------------------------------------------------------------------
insert into public.product_variants (product_id, rotulo, opcao, ordem)
select p.id, v.rotulo, v.opcao, v.ordem
from public.products p
join (
  values
    -- cafés (Moagem)
    ('cafe-alma-do-casa-250g',            'Moagem', 'Grão inteiro',      1),
    ('cafe-alma-do-casa-250g',            'Moagem', 'Moído p/ coado',    2),
    ('cafe-alma-do-casa-250g',            'Moagem', 'Moído p/ espresso', 3),
    ('cafe-torra-vale-dos-sinos-250g',    'Moagem', 'Grão inteiro',      1),
    ('cafe-torra-vale-dos-sinos-250g',    'Moagem', 'Moído p/ coado',    2),
    ('cafe-torra-vale-dos-sinos-250g',    'Moagem', 'Moído p/ espresso', 3),
    ('cafe-descafeinado-afeto-250g',      'Moagem', 'Grão inteiro',      1),
    ('cafe-descafeinado-afeto-250g',      'Moagem', 'Moído p/ coado',    2),
    ('cafe-descafeinado-afeto-250g',      'Moagem', 'Moído p/ espresso', 3),
    -- vestuário (Tamanho)
    ('moletom-casa-coffee',   'Tamanho', 'P',     1),
    ('moletom-casa-coffee',   'Tamanho', 'M',     2),
    ('moletom-casa-coffee',   'Tamanho', 'G',     3),
    ('moletom-casa-coffee',   'Tamanho', 'GG',    4),
    ('camiseta-feito-no-casa', 'Tamanho', 'P',    1),
    ('camiseta-feito-no-casa', 'Tamanho', 'M',    2),
    ('camiseta-feito-no-casa', 'Tamanho', 'G',    3),
    ('camiseta-feito-no-casa', 'Tamanho', 'GG',   4),
    ('avental-do-casa',        'Tamanho', 'Único', 1)
) as v (slug, rotulo, opcao, ordem) on v.slug = p.slug
on conflict (product_id, opcao) do nothing;

-- -----------------------------------------------------------------------------
-- ACHIEVEMENTS (9 conquistas). Ícones = nomes Lucide.
-- -----------------------------------------------------------------------------
insert into public.achievements (slug, nome, descricao, icone, ordem) values
  ('primeira-xicara',   'Primeira Xícara',    'o teu primeiro café aqui.',                     'coffee',         1),
  ('manha-de-sempre',   'Manhã de Sempre',    'virou rotina passar de manhã.',                 'sunrise',        2),
  ('gente-do-casa',     'Gente do Casa',      'tu já é de casa por aqui.',                      'heart',          3),
  ('alma-do-casa',      'Alma do Casa',       'o coração desse lugar bate contigo.',            'award',          4),
  ('cafe-viajante',     'Café Viajante',      'levou o nosso grão pra casa.',                   'coffee',         5),
  ('mesa-comprida',     'Mesa Comprida',      'trouxe gente nova pra sentar junto.',            'heart',          6),
  ('que-seja-doce',     'Que Seja Doce',      'provou todos os doces da casa.',                 'star',           7),
  ('domingo-de-brunch', 'Domingo de Brunch',  'não perde um brunch de domingo.',               'sunrise',        8),
  ('colab-de-vizinho',  'Colab de Vizinho',   'levou um produto feito em residência no Casa.',  'sparkles',       9)
on conflict (slug) do update set
  nome      = excluded.nome,
  descricao = excluded.descricao,
  icone     = excluded.icone,
  ordem     = excluded.ordem;

-- -----------------------------------------------------------------------------
-- PARTNERS (parceiros locais — colab e/ou resgate de pontos).
-- -----------------------------------------------------------------------------
insert into public.partners (slug, nome, descricao, tipo, bairro, cidade, ordem) values
  ('atelie-lomba-grande',   'Ateliê Lomba Grande',       'cerâmica feita à mão que veste as mesas do Casa.',      'ambos',   'Lomba Grande',    'Novo Hamburgo', 1),
  ('torrefacao-vale-sinos', 'Torrefação Vale dos Sinos', 'micro-lote de café que a gente serve por temporada.',   'colab',   'Centro',          'Novo Hamburgo', 2),
  ('feira-hamburgo-velho',  'Feira da Hamburgo Velho',   'produtores do bairro que abastecem a nossa cozinha.',   'colab',   'Hamburgo Velho',  'Novo Hamburgo', 3),
  ('livraria-da-esquina',   'Livraria da Esquina',       'livro bom combina com café — resgata um vale por aqui.','resgate', 'Hamburgo Velho',  'Novo Hamburgo', 4),
  ('floricultura-raiz',     'Floricultura Raiz',         'um ramo de flores do vizinho pra alegrar a mesa.',      'resgate', 'Hamburgo Velho',  'Novo Hamburgo', 5)
on conflict (slug) do update set
  nome      = excluded.nome,
  descricao = excluded.descricao,
  tipo      = excluded.tipo,
  bairro    = excluded.bairro,
  cidade    = excluded.cidade,
  ordem     = excluded.ordem;
