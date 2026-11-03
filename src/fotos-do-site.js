// =============================================================================
// Casa Coffee Colab, fotos-do-site.js
//
// A LISTA DOS LUGARES DO SITE QUE MOSTRAM FOTO. Uma linha por `<img>` que a
// casa pode trocar pelo console, sem deploy nenhum (migration 0054).
//
// POR QUE ISTO É UM ARQUIVO À PARTE, contra a regra do "um arquivo grande por
// camada" do CLAUDE.md: esta lista é a única coisa do projeto que o SITE e o
// CONSOLE precisam saber igualzinho. O site usa pra achar o `<img>` e trocar o
// `src`; o console usa pra dizer, em português, que foto é aquela e onde ela
// aparece. Escrita nos dois arquivos, ela divergiria no primeiro slide novo do
// hero — e é exatamente esse o erro que o CLAUDE.md conta duas vezes (o
// catálogo de permissões da 0047, a fila do menu da conta). O `admin.js` não
// pode importar do `app.js` (importar traria junto o bootstrap inteiro do site,
// que monta header, carrossel e carrinho no balcão de trás), então o lugar
// honesto da lista é aqui, no meio dos dois.
//
// A lista TAMBÉM não mora no banco, de propósito: ela é um fato sobre o HTML.
// Slide novo no hero é `<img data-foto="…">` novo no `.html` e uma linha nova
// aqui, no mesmo commit — nunca um INSERT que alguém tem que lembrar de rodar.
//
// COMO SOMAR UM LUGAR:
//   1. no `.html`, põe `data-foto="o-slug"` na `<img>`;
//   2. aqui, uma entrada com o mesmo slug, contando onde ela fica e que
//      formato de foto cai bem ali.
// Pronto: o site já troca e o console já mostra.
// =============================================================================

// O bucket do Storage onde as fotos da casa moram (0054). O caminho do arquivo
// é o que fica guardado no banco; o endereço é montado pelo `getPublicUrl`, com
// o host vindo do env — nunca uma URL vinda do banco.
export const FOTOS_BUCKET = 'fotos-site';

export const FOTOS_DO_SITE = [
  // ── Home ──────────────────────────────────────────────────────────────────
  {
    slot: 'home-hero-2',
    pagina: 'Home',
    url: '/home',
    local: 'hero, 2ª tela',
    oque: 'o fundo grande da abertura, atrás do título. o hero passa três telas em sequência, e esta é a segunda.',
    formato: 'deitada e bem larga (16:9 ou mais). o centro é o que fica visível no celular.',
    padrao: '/fotos/o-casa-fachada.jpg',
  },
  {
    slot: 'home-hero-3',
    pagina: 'Home',
    url: '/home',
    local: 'hero, 3ª tela',
    oque: 'a última tela da abertura, antes de voltar pro vídeo.',
    formato: 'deitada e bem larga (16:9 ou mais). o centro é o que fica visível no celular.',
    padrao: '/fotos/clube-abraco.jpg',
  },
  {
    slot: 'home-agenda-in-the-flow',
    pagina: 'Home',
    url: '/home',
    local: '"o que acontece no Casa", cartão 01',
    oque: 'a foto do In the Flow.',
    formato: 'quadrada (1:1).',
    padrao: '/fotos/agenda-in-the-flow.jpg',
  },
  {
    slot: 'home-agenda-matcha',
    pagina: 'Home',
    url: '/home',
    local: '"o que acontece no Casa", cartão 02',
    oque: 'a foto do Matcha Club.',
    formato: 'quadrada (1:1).',
    padrao: '/fotos/agenda-matcha-club.jpg',
  },
  {
    slot: 'home-agenda-brunch',
    pagina: 'Home',
    url: '/home',
    local: '"o que acontece no Casa", cartão 03',
    oque: 'a foto do brunch de domingo.',
    formato: 'quadrada (1:1).',
    padrao: '/fotos/agenda-brunch.jpg',
  },
  {
    slot: 'home-agenda-happy-hour',
    pagina: 'Home',
    url: '/home',
    local: '"o que acontece no Casa", cartão 04',
    oque: 'a foto do happy hour de sexta.',
    formato: 'quadrada (1:1).',
    padrao: '/fotos/agenda-happy-hour.jpg',
  },
  {
    slot: 'home-duo-clube',
    pagina: 'Home',
    url: '/home',
    local: 'bloco duplo, metade do Clube',
    oque: 'a foto atrás da chamada "fazer parte muda tudo".',
    formato: 'em pé ou quadrada. no computador ela vira uma faixa alta na direita, no celular uma faixa deitada.',
    padrao: '/fotos/clube-abraco.jpg',
  },
  {
    slot: 'home-duo-loja',
    pagina: 'Home',
    url: '/home',
    local: 'bloco duplo, metade da Loja',
    oque: 'a foto atrás da chamada da loja.',
    formato: 'em pé ou quadrada. no computador ela vira uma faixa alta na direita, no celular uma faixa deitada.',
    padrao: '/fotos/loja-cafe.jpg',
  },

  // ── O Casa ────────────────────────────────────────────────────────────────
  {
    slot: 'o-casa-hero',
    pagina: 'O Casa',
    url: '/o-casa',
    local: 'hero da página',
    oque: 'a foto de abertura do /o-casa, atrás de "O Casa é café, afeto e comida boa".',
    formato: 'deitada e bem larga. o corte fica um pouco acima do meio, então deixa o assunto no terço de cima.',
    padrao: '/fotos/o-casa-fachada.jpg',
  },

  // ── Colab ─────────────────────────────────────────────────────────────────
  {
    slot: 'colab-hero',
    pagina: 'Colab',
    url: '/colab',
    local: 'hero da página',
    oque: 'a foto de abertura da Residência Gente do Casa.',
    formato: 'deitada e bem larga. o corte fica um pouco acima do meio.',
    padrao: '/fotos/agenda-in-the-flow.jpg',
  },
  {
    slot: 'colab-card-1',
    pagina: 'Colab',
    url: '/colab',
    local: 'carrossel de colabs, 1º cartão (Ateliê Lomba Grande)',
    oque: 'a faixinha de foto na lateral do cartão.',
    formato: 'em pé (retrato). é uma tira estreita e alta, então foto com o assunto no meio funciona melhor.',
    padrao: '/fotos/agenda-brunch.jpg',
  },
  {
    slot: 'colab-card-2',
    pagina: 'Colab',
    url: '/colab',
    local: 'carrossel de colabs, 2º cartão (Torrefação Vale dos Sinos)',
    oque: 'a faixinha de foto na lateral do cartão.',
    formato: 'em pé (retrato). é uma tira estreita e alta.',
    padrao: '/fotos/loja-cafe.jpg',
  },
  {
    slot: 'colab-card-3',
    pagina: 'Colab',
    url: '/colab',
    local: 'carrossel de colabs, 3º cartão (Feira da Hamburgo Velho)',
    oque: 'a faixinha de foto na lateral do cartão.',
    formato: 'em pé (retrato). é uma tira estreita e alta.',
    padrao: '/fotos/agenda-matcha-club.jpg',
  },
  {
    slot: 'colab-card-4',
    pagina: 'Colab',
    url: '/colab',
    local: 'carrossel de colabs, 4º cartão (Selo Trilha Sonora)',
    oque: 'a faixinha de foto na lateral do cartão.',
    formato: 'em pé (retrato). é uma tira estreita e alta.',
    padrao: '/fotos/clube-abraco.jpg',
  },

  // ── Eventos ───────────────────────────────────────────────────────────────
  {
    slot: 'eventos-casa-1',
    pagina: 'Eventos',
    url: '/eventos',
    local: '"a casa por dentro", 1º cartão (dentro e na calçada)',
    oque: 'a foto no topo do cartão. este carrossel é o argumento da página: quem pensa em fazer um evento decide com os olhos.',
    formato: 'deitada 4:3.',
    padrao: '/fotos/o-casa-fachada.jpg',
  },
  {
    slot: 'eventos-casa-2',
    pagina: 'Eventos',
    url: '/eventos',
    local: '"a casa por dentro", 2º cartão (brunch pra tua gente)',
    oque: 'a foto no topo do cartão.',
    formato: 'deitada 4:3.',
    padrao: '/fotos/agenda-brunch.jpg',
  },
  {
    slot: 'eventos-casa-3',
    pagina: 'Eventos',
    url: '/eventos',
    local: '"a casa por dentro", 3º cartão (música, se tu quiser)',
    oque: 'a foto no topo do cartão.',
    formato: 'deitada 4:3.',
    padrao: '/fotos/agenda-in-the-flow.jpg',
  },
  {
    slot: 'eventos-casa-4',
    pagina: 'Eventos',
    url: '/eventos',
    local: '"a casa por dentro", 4º cartão (fim de tarde que vira noite)',
    oque: 'a foto no topo do cartão.',
    formato: 'deitada 4:3.',
    padrao: '/fotos/agenda-happy-hour.jpg',
  },
  {
    slot: 'eventos-casa-5',
    pagina: 'Eventos',
    url: '/eventos',
    local: '"a casa por dentro", 5º cartão (café, matchá e coffee break)',
    oque: 'a foto no topo do cartão.',
    formato: 'deitada 4:3.',
    padrao: '/fotos/agenda-matcha-club.jpg',
  },
  {
    slot: 'eventos-casa-6',
    pagina: 'Eventos',
    url: '/eventos',
    local: '"a casa por dentro", 6º cartão (gente junta, que é o ponto)',
    oque: 'a foto no topo do cartão.',
    formato: 'deitada 4:3.',
    padrao: '/fotos/clube-abraco.jpg',
  },
];

// A mesma lista agrupada por página, que é como o console mostra e como a casa
// pensa ("quero trocar as fotos da home"). A ordem das páginas é a ordem em que
// as entradas aparecem acima, então não há uma segunda lista pra manter.
export function fotosPorPagina() {
  const paginas = [];
  FOTOS_DO_SITE.forEach((foto) => {
    let grupo = paginas.find((p) => p.pagina === foto.pagina);
    if (!grupo) {
      grupo = { pagina: foto.pagina, url: foto.url, fotos: [] };
      paginas.push(grupo);
    }
    grupo.fotos.push(foto);
  });
  return paginas;
}
