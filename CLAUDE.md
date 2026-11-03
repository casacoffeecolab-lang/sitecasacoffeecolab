# Casa Coffee Colab — Contexto do Projeto

Site do **Casa Coffee Colab**, um café-casa de encontros em Novo Hamburgo/RS.
"O Casa é café, afeto e comida boa."

Construído em fases. Esta é a fundação visual — sem backend ainda.

---

## Stack

- **Vite** (vanilla, multi-página) — cada página é uma URL/`.html` própria.
- **Tailwind CSS** (CLI/PostCSS) — não usar CDN.
- **JS vanilla** — sem framework.
- **Fontes** via `@fontsource` (bundled, sem CDN externo).

Fases seguintes (ainda **não** implementadas):
- **Supabase** — auth, banco, RLS, edge functions.
- **Asaas** — pagamentos (checkout hospedado).
- **Deploy** na **Vercel**.

---

## Convenção de código

Código **consolidado**: UM arquivo grande por camada, pra facilitar busca durante o desenvolvimento. Não fragmentar em muitos arquivos pequenos.

- `src/app.js` — toda a lógica/JS da camada de interface.
- `src/styles.css` — entrada Tailwind + estilos base.
- `src/schema.sql` — (futuro) todo o schema do banco.

**Uma exceção, e só uma:** o `src/fotos-do-site.js`, a lista dos lugares do site que
mostram foto. Ela é a única coisa que o `app.js` (que troca a foto) e o `admin.js` (que
mostra qual é qual) precisam saber igualzinho, e o `admin.js` não pode importar do `app.js`
sem trazer junto o bootstrap inteiro do site. Escrita nos dois, ela divergiria. Ver "As
fotos do site" abaixo.

**Header, footer e menu são funções dentro do `app.js`** que injetam HTML nos placeholders da página (`<div id="site-header"></div>` / `<div id="site-footer"></div>`).

**Páginas `.html` continuam separadas** — cada uma é uma URL. Ficam direto em `src/` (a área logada em `src/conta/`), porque **o caminho do arquivo é a URL**: `src/o-casa.html` vira `/o-casa`, `src/conta/perfil.html` vira `/conta/perfil`.

---

## Paleta (tokens Tailwind)

| Token       | Hex       | Uso                          |
|-------------|-----------|------------------------------|
| `terracota` | `#8c3a2a` | cor primária / acento quente |
| `verde`     | `#305429` | secundária / natureza        |
| `cafe`      | `#5b3c34` | texto escuro / café          |
| `caramelo`  | `#a56a3a` | destaques dourados           |
| `bege`      | `#ead8c1` | fundos claros / papel        |
| `preto`     | `#000000` | —                            |
| `branco`    | `#ffffff` | —                            |

---

## Tipografia

- **Sora** → `font-sora` — texto/UI, corpo.
- **Títulos** → `font-titulo` — placeholder **Fraunces**.
- **Decorativa/manuscrita** → `font-decor` — placeholder **Caveat**.

> **TODO (fontes reais):** as fontes oficiais da marca são **Rexton** (títulos/UI) e **Mayonice** (decorativa) — ambas **pagas**. Enquanto não temos as licenças, usamos **Fraunces** (títulos) e **Caveat** (decorativa) como placeholder. Quando as fontes reais chegarem, trocar em `@fontsource`/`styles.css` e nos tokens `fontFamily` do `tailwind.config.js`. Sora permanece.

---

## Tom de voz da marca

**SEGUIR SEMPRE** — inclusive em microcopy, botões, mensagens de erro e labels.

- Acolhedor, autoral, poético contido, urbano-afetivo, humilde.
- Tratamento **"tu" / "a gente"**.
- CTAs gentis: *"passa aqui?"*, *"fica um pouco"*, *"entra, senta, fica um pouco"*.

**EVITAR sempre:**
- Palavras: *gourmet, luxo, premium, exclusivo, hype, trend*.
- Imperativos agressivos: *"aproveita já!"*, *"corre!"*.
- Qualquer gamificação com cara de cassino (roleta, "gire pra ganhar", contadores de urgência falsos).
- **Travessão (`—`) em texto que o usuário vê.** No copy visível (HTML e strings do
  `app.js`/`admin.js` que renderizam na tela), **nunca** usar `—` como pontuação de frase —
  usar **vírgula** no lugar. Vale pra qualquer texto novo. **Exceção:** o `—` sozinho como
  glifo de "vazio/sem valor" (célula de tabela vazia, saldo carregando: `valor || '—'`) pode
  ficar — ali a vírgula quebraria a tela. Em comentário de código, documentação e migrations
  o `—` segue liberado (o usuário não vê).

---

## Contato oficial (header/footer)

- **Endereço:** R. Victor Hugo Kunz, 411 — Hamburgo Velho, Novo Hamburgo/RS
- **E-mail:** casacoffeecolab@gmail.com
- **Telefone:** (51) 99360-5262
- **Horário:** Seg a sáb, das 8h às 19h / Domingo, das 15h às 19h. No rodapé isso é uma
  **coluna própria** ("horário de funcionamento"), com as duas faixas em linhas
  separadas, montada do array `MARCA.contato.horarios` (uma string por linha; a casa
  abre igual de segunda a sábado, então listar os sete dias repetia a mesma frase seis
  vezes). Mudou o horário da casa, muda no array e vale em toda página. (O `/o-casa` tem
  a própria cópia do horário no HTML, na seção "Passa aqui?" — essa não vem do `MARCA`.)

Redes (placeholders por enquanto): Instagram, Spotify. **Sem Facebook** — a casa não tem
perfil por lá, e link morto no rodapé é promessa que não se cumpre. Fonte única no
`MARCA.redes` (`app.js`), que serve o rodapé e o link do "som do Casa" na home.

---

## As fotos do site (e o acervo da casa)

As fotos que o site mostra **se trocam no console**, na aba **fotos** (`/admin#fotos`,
migration `0054`), sem esperar deploy. Um café troca de foto quando a estação muda, quando
a fachada ganha toldo novo, quando o prato sai bonito, e nada disso pode passar por
programador.

- **Onde entram fotos hoje:** `home` (2 telas do hero, os 4 cartões do "o que acontece no
  Casa", as 2 metades do bloco duplo), `o-casa` (hero), `colab` (hero + 4 cartões do
  carrossel) e `eventos` (os 6 cartões do "a casa por dentro"). São **20 lugares**, e os
  arquivos de fábrica estão em `src/assets/fotos` (servidos em `/fotos/…`).
- **A lista dos lugares mora no `src/fotos-do-site.js`**, que o `app.js` e o `admin.js`
  importam. É o **único** arquivo compartilhado pelas duas camadas, e a exceção à regra do
  "um arquivo grande por camada" está explicada no cabeçalho dele: o site precisa da lista
  pra achar o `<img>`, o console precisa dela pra dizer em português que foto é aquela, o
  `admin.js` não pode importar do `app.js` (viria o bootstrap inteiro do site junto), e
  escrever a mesma lista duas vezes é o erro que o catálogo de permissões da 0047 já
  cometeu. Ela **não** mora no banco porque é um fato sobre o HTML: lugar novo é um
  `data-foto` no `.html` e uma linha lá, no mesmo commit, nunca um INSERT pra alguém
  lembrar de rodar.
- **O `src` do HTML é o PADRÃO, e continua valendo.** O banco só guarda os lugares que a
  casa trocou; "voltar pra de fábrica" é um DELETE da linha. Com a migration pendente, o
  banco fora do ar ou a visita sem rede, a página mostra a foto de sempre, nunca um quadro
  quebrado.
- **O que se guarda é o CAMINHO do arquivo, nunca a URL.** Quem monta o endereço é o
  `getPublicUrl`, com o host vindo do env, então não há URL de fora entrando na página por
  essa porta (um "contador de acesso disfarçado de foto" no hero, por exemplo). O
  `aplicarFotosDoSite` ainda repete no client a régua do `foto_caminho_ok` do banco, porque
  o cache do localStorage é o único caminho que não passou pelo banco antes.
- **O cache existe por causa do pisca:** sem ele, toda visita mostrava a foto de fábrica
  por um instante antes de a foto da casa entrar, e no hero isso é a tela inteira trocando
  na cara de quem chegou. O `casa_fotos` do localStorage pinta na hora, e a leitura do banco
  confirma (ou corrige) depois.
- **Cada arquivo subido tem caminho único** (`ano/mês/nome-sufixo.ext`), então ele vai pro
  Storage com cache de um ano e trocar a foto de um lugar **nunca reescreve** o arquivo
  antigo, que segue servindo quem está com a página aberta.
- **Arquivo órfão tem varredor:** `npm run fotos-orfas` (ver "O acervo de fotos também",
  em Comandos). Subir é arquivo primeiro e ficha depois, apagar é linha primeiro e arquivo
  depois, então a aba fechada no meio deixa arquivo sem dono, e o Storage não tem cascata.
- **O que ainda NÃO passa por aqui:** o **vídeo** de abertura da home (é vídeo, e o `<img>`
  é o contrato desta aba), o `og:image` das páginas (é a miniatura do link compartilhado,
  escrita no `<head>`) e as telas que ainda são **gradiente**, não foto: a loja, a página de
  produto e o cartão de playlist usam os utilitários `.photo-warm` / `.photo-green` /
  `.photo-bege` do `styles.css`. Quando esses virarem `<img>`, viram lugar da aba com uma
  linha no `fotos-do-site.js`.

---

## Ícones

- **Lucide** via módulo `lucide` (sem CDN). Uso: `<i data-lucide="nome"></i>` no HTML;
  `renderIcons()` no `app.js` chama `createIcons()` e substitui por SVG **após** injetar markup.
- Importar só os ícones usados (tree-shaking) no topo do `app.js` e registrar em `LUCIDE_ICONS`.

---

## Carrossel

- Função `setupCarousel(trackEl, { dots, autoplay, interval })` no `app.js` — serve os tracks
  `[data-carousel="cards"]` (hoje só a **colab**), via `initCarousels`.
- Base em **scroll-snap** horizontal (`.carousel-track`), navegável por swipe/scroll, teclado (setas) e dots.
- A função **suporta** dots e autoplay (com `prefers-reduced-motion` e pausa em hover/foco/toque),
  mas nenhuma página os liga hoje (a colab chama com `dots:false, autoplay:false`).
- **O hero da home NÃO usa `setupCarousel`** — é o `setupHeroCarousel` (fundo full-bleed em
  foto/vídeo por tempo, contrato `[data-hero-carousel]`), chamado no bootstrap.
- Contrato de DOM: `[data-carousel]` › `[data-carousel-track]` (+ opcionais `[data-dots]`,
  `[data-carousel-prev]`, `[data-carousel-next]`).

---

## Loja (catálogo, produto, carrinho)

- **Catálogo (mock)**: array `PRODUTOS` no `app.js` (bloco "CATÁLOGO (MOCK …)"). Cada item:
  `id, nome, slug, categoria (vestuario|acessorios|cafe_grao), preco_centavos, descricao,
  imagemPlaceholder (.photo-*), variantes ({ rotulo, opcoes[] } | null)`.
  > **TODO (Fase 2):** substituir o mock pela tabela **`products` do Supabase** (mesma forma).
- **Busca + ordenação (`/loja`)**: além do filtro por categoria, a vitrine tem um campo de
  busca (`[data-catalog-search]`) e um seletor de ordem (`[data-catalog-sort]`), ligados pela
  `initCatalogPage`. A busca varre **nome + categoria + descrição** já normalizados
  (`normalizarBusca`, sem acento e em minúscula, então "cafe" acha "Café"); a ordem tem
  quatro opções no mapa `ORDENACOES` (`casa` = a ordem curada do array, `preco-asc`,
  `preco-desc`, `nome`). Categoria, busca e ordem vivem num objeto `estado` e são aplicados
  juntos por uma função só. Ordenar **move os nós** do grid (`appendChild`), nunca
  re-renderiza: o que for injetado nos cards depois do primeiro render sobrevive ao move, e
  não sobreviveria a um `innerHTML` novo. Um
  `[data-catalog-count]` (`aria-live`) mostra "X itens de Y" e o estado vazio troca o texto
  quando a pessoa está buscando.
  > `.prod` mora fora de `@layer`, então vence o `.hidden` do Tailwind por ordem de fonte —
  > por isso existe o `.prod.hidden { display: none }` no `styles.css` (mesmo caso do
  > `.notice`). Sem ele, o filtro marca o card como escondido e ele fica na tela.
- **Tabela de medidas (roupa)**: campo opcional `medidas` (`{ colunas[], linhas[][], nota }`,
  valores em centímetros) nos itens de `vestuario` — a loja não tem provador, então quem
  compra precisa conferir o tamanho antes, senão vira troca. A `initProductPage` renderiza
  um `<details>` **"ver a tabela de medidas"** logo abaixo das variantes (recolhido, pra não
  empurrar o botão de comprar), com as medidas **da peça** (não do corpo), a nota de
  modelagem do produto e o recado de que a medida pode variar 1 ou 2 cm. Aparece também no
  produto **esgotado** (quem espera a volta já quer saber o tamanho). Estilo `.medidas-*` no
  `styles.css`: a tabela cabe inteira a partir de ~360px e, mais estreito que isso, rola
  dentro da própria caixa (`.medidas-scroll`) — a coluna do grid leva `min-w-0` pra página
  nunca ganhar scroll lateral.
- **Páginas**: `src/loja.html` (grid + busca + ordenação + filtro por categoria) e
  `src/produto.html` (lê `?slug=`, renderiza detalhe; estado vazio gentil se não achar).
  Ambas registradas no `rollupOptions.input` do `vite.config.js`.
- **Navegação da loja** (só front, sem migration): a página de produto abre com uma
  **trilha de migalhas** (`trilhaProdutoHTML`) *Loja / Categoria / Produto*, onde o crumb
  do meio leva pra `/loja?categoria=<slug>` — a `initCatalogPage` lê esse parâmetro e já
  abre a vitrine filtrada (valor desconhecido cai em "todos"). No fim da página vem a seção
  **"quem sabe tu gosta"** (`relacionadosHTML`): até 3 produtos, os da mesma categoria
  primeiro e o resto da vitrine completando, disponíveis antes dos esgotados. Reusa o
  `cardProdutoHTML` (por isso o grid é `cols-3`, a largura em que os dois botões do card
  cabem), então herda selo de esgotado, "me avisa quando voltar" (`initReposicao` pega os
  `[data-avisar]` de qualquer página) e o coração de "guardar pra depois"
  (`initLojaDesejos` varre `[data-catalog-grid], [data-relacionados]`).
- **Carrinho** (`Cart` no `app.js`): estado em **localStorage** (chave `casa_cart`) — o site é
  multi-página, então o carrinho **sobrevive a reloads/navegação**. API:
  `addItem/removeItem/updateQty/getCart/getSubtotalCentavos/getCount/clearCart/onChange`.
  Sincroniza entre abas via evento `storage`.
- **Drawer**: painel lateral reutilizável, injetado uma vez no `<body>`; abre pelo ícone
  `shopping-bag` do header (com badge de contagem). **Enquanto a Loja está "em breve"
  (`semLink` na NAV) esse ícone não é renderizado**: a barra não pode dizer que a loja não
  abriu e mostrar um carrinho ao lado. O drawer em si continua vivo, e quem entra pela URL
  direta da `/loja` e adiciona algo o vê abrir sozinho; só o atalho permanente sai da
  barra. Religar a loja (tirar o `semLink`) traz a sacolinha de volta junto.
  Fecha por X, Esc e clique no backdrop.
  Botão "finalizar compra" chama a `create-checkout-session` e manda pro **Checkout
  hospedado do Asaas** (ver "Pagamentos"); deslogado, passa pelo login e volta pro carrinho.
- **Preços**: sempre cheios, via `formatBRL(centavos)` (ex.: `R$ 49,90`). O **desconto por tier
  de assinatura NÃO é aplicado aqui** — quem aplica é a Edge Function, pelo banco, no checkout.

---

## Páginas & navegação

Todas as páginas ficam direto em `src/` (a área logada em `src/conta/`) e precisam estar
registradas no `rollupOptions.input` do `vite.config.js`. Header/footer vêm do `app.js`.

**URLs limpas — sem `/pages/` e sem `.html`.** O arquivo `src/o-casa.html` é servido em
`/o-casa`. Quem tira a extensão em produção é a **Vercel** (`cleanUrls: true` no
`vercel.json`, que também redireciona 308 de `/x.html` pra `/x`); em desenvolvimento quem
faz isso é o plugin `urlsLimpasNoDev()` do `vite.config.js`, um middleware que anexa
`.html` na requisição quando o arquivo existe. Assim o link é escrito limpo num lugar só e
funciona igual nos dois ambientes. O `vercel.json` guarda ainda redirects permanentes de
`/pages/*` pros caminhos novos, pra não quebrar links antigos em circulação (e-mails de
confirmação do Supabase, `successUrl` de checkouts já emitidos).

| Página        | Arquivo             | URL                | Conteúdo                                                            |
|---------------|---------------------|--------------------|--------------------------------------------------------------------|
| Home          | `home.html`         | `/home`            | hero + carrosséis + teasers (loja/planos) + playlists              |
| O Casa        | `o-casa.html`       | `/o-casa`          | sobre: história, DNA, Mural do Casa (seção escura), localização (mapa + "como chegar"), tour 360 |
| Cardápio      | `cardapio.html`     | `/cardapio`        | as 16 seções do cardápio impresso + tirinha de atalhos entre elas — informativo, **sem carrinho** |
| Loja          | `loja.html`         | `/loja`            | catálogo + busca + ordenação + filtro por categoria (aceita `?categoria=`) |
| Produto       | `produto.html`      | `/produto?slug=`   | detalhe via `?slug=`, trilha de migalhas + relacionados (conta como "Loja" na nav) |
| Clube         | `planos.html`       | `/planos`          | a assinatura única + a jornada das 4 categorias por tempo, pontos, conquistas |
| Colab         | `colab.html`        | `/colab`           | Residência Gente do Casa; carrossel de colabs; convite (mailto/WhatsApp) |
| Eventos       | `eventos.html`      | `/eventos`         | "faz teu evento aqui": tipos de evento + formulário que grava o pedido e toca o sino no Telegram |
| Cadastro      | `cadastro.html`     | `/cadastro`        | criar conta (nome/telefone/e-mail/senha); estado "confirme seu e-mail" |
| Login         | `login.html`        | `/login`           | entrar (e-mail/senha) + "esqueci a senha" (reset por e-mail)       |
| Auth OK       | `auth-confirmado.html` | `/auth-confirmado` | retorno do link de confirmação; detecta a sessão na URL         |
| Perfil        | `conta/perfil.html` | `/conta/perfil`    | área logada (protegida): dados, pontos, plano; editar nome/telefone |
| Clube (conta) | `conta/clube.html`  | `/conta/clube`     | categoria, tempo de casa, quanto falta pra próxima, pontos e benefícios |
| Privacidade   | `privacidade.html`  | `/privacidade`     | política de privacidade (LGPD); linkada no rodapé e no `/cadastro`  |
| Termos        | `termos.html`       | `/termos`          | termos de uso (conta, assinatura, loja, pontos, mural); mesmo lugar |

A raiz `/` é o `src/index.html`, que só redireciona pra `/home`.

**URL que não existe cai no `src/404.html`** (`/asdf`, link velho, letra trocada), com o
mesmo estado vazio gentil do `/produto` e do `/gente`: header/footer normais, o caminho
tentado mostrado (`init404Page`, escapado) e saídas pra home/cardápio/o-casa. Quem serve
essa página **com status 404** é a **Vercel** (todo arquivo `404.html` na raiz do `dist` vira
a página de erro do site) em produção, e o middleware `urlsLimpasNoDev()` do
`vite.config.js` em desenvolvimento — sem ele, o fallback de SPA do Vite serviria o
`index.html`, que redireciona pra `/home` e faz o link quebrado **sumir em silêncio**. O
`404.html` está no `rollupOptions.input` e leva `robots: noindex`.

- **NAV** (array no `app.js`): O Casa, Colab, Cardápio, Loja, Clube, Eventos — todas
  apontam pras
  páginas reais, com href limpo (`/o-casa`). A ordem conta uma frase: quem a gente é
  (O Casa, Colab), o que a gente serve (Cardápio, Loja), como tu entra (Clube) e como tu
  usa a casa (Eventos, que fecha a fila encostado no "visite-nos"). **A Home não tem item**: o logo do header já é um
  link pra `/home` (no celular, o "C" do meio da tab bar), então o item repetia o mesmo
  destino na posição mais lida da barra. **`/planos` se chama "Clube"** nos cinco lugares
  (header, menu mobile, rodapé, tab bar e o `aria-current`), a pedido da casa em
  13/ago/2026: é assim que o Casa chama a assinatura quando fala dela em voz alta, e a
  barra passa a repetir a palavra da casa. **O href e o arquivo seguem `/planos`** — mudou
  o rótulo da porta, não a porta, então nada de link, âncora (`/planos#planos`) ou
  `successUrl` precisou mudar. O nome vive **só no `rotulo` da NAV** e no rótulo curto da
  tab bar (a fila lá é outra, por isso ela passa o texto à parte). `activeNavHref()` detecta a página atual
  pelo pathname (tolerando um `.html` no fim, pra links antigos) e marca o item ativo com
  `aria-current="page"` + `text-terracota font-semibold` (produto → "Loja";
  raiz/`index`/`home` → "Home", que não está na NAV mas alimenta o `aria-current` do logo
  e do "C" da tab bar).
- **Tab bar do celular: sete lugares** (os seis itens da NAV mais o "C" da home no meio).
  A entrada dos Eventos deixou a NAV com número par de itens, e par mais o botão do meio
  não fecha simétrico: com cinco itens o "C" saía do centro da tela, que é de onde ele
  tira a força de âncora. O sétimo lugar é o **"O Casa"**, que até então não estava na tab
  bar (ela mostrava quatro dos cinco itens), então a simetria ainda corrigiu a ausência da
  página de apresentação na única navegação que o celular tem. A barra virou
  `grid-template-columns: repeat(7, 1fr)` no lugar do `space-around`: com largura livre,
  "Cardápio" empurrava os vizinhos e a fila saía torta; coluna igual mantém o "C" no meio
  exato em qualquer largura. O rótulo **não quebra linha** (a barra é baixa demais), ele
  encolhe: 8.5px de base, 7.5px abaixo de 400px, 7px abaixo de 345px, com ícone e "C"
  acompanhando. Medido no navegador de 320 a 768px: nada estoura, nada gera scroll lateral
  e o "C" fica no pixel do meio.
- **Loja está com selo "em breve" e SEM link** (`semLink: true` na NAV): o item aparece no
  header, no menu mobile e no rodapé como texto morto (`.nav-off`) e na **tab bar do
  mobile** como `.tab-off` (ícone e rótulo apagados, carimbo "em breve" sobre o ícone).
  O mesmo `semLink` **esconde a sacolinha do carrinho no header** (ver "Drawer"), então
  religar vale pros cinco lugares de uma vez: `renderTabbar` e o `renderHeader` consultam
  a NAV pelo href. A página continua no ar — dá pra abrir digitando `/loja`. Pra religar
  o link, é só tirar o `semLink`.
- **Cardápio**, **Planos** e **/presentear** mostram os preços **sem ressalva**. A nota
  "* valores ilustrativos" saiu do cardápio, e a "* valores fictícios, a definir" saiu dos
  planos e do presentear, as três a pedido: dizer que o preço não é bem aquele, na hora de
  escolher o que pedir, de assinar ou de dar de presente, derruba a compra. Botão
  **"assinar"** (`initPlanosPage`) chama a `create-checkout-session` e leva pro Checkout
  hospedado do Asaas.
- **O `/cardapio` é o cardápio impresso, item por item** (itens e preços reais, passados
  pelo humano em 11/ago/2026). As **16 seções e a ordem delas são as do papel**: primeiro a
  página da comida, coluna da esquerda inteira e depois a da direita (Clássicos do Casa,
  Brunch, Bagel, Croissant, Sanduíches, Toasts, Confeitaria), depois a página das bebidas
  do mesmo jeito (Métodos, Puristas, Elaborados, Cafés gelados, Matcha, Chás, Juices e
  sodas, Alcoólicos), e os **Adicionais fechando a página** — no papel eles vêm no meio da
  comida, como quadro lateral, mas não são um prato, são o que se soma a um, e numa página
  que só rola atrapalhavam a fila. Cada seção é uma `<section aria-labelledby>` com uma
  `.menu-list`, que é o contrato de que a `initCardapioNav` e a `initCardapioFavoritos`
  vivem — **seção nova no papel vira seção nova aqui e os chips se montam sozinhos**.
  Duas adaptações do impresso, de propósito: os **três preços do leite** viram uma
  gradezinha de 3 colunas (`.mi-precos`), com cada valor **em cima do leite dele**
  (integral, zero lactose, vegetal) — as duas linhas são do mesmo grid, então preço e
  rótulo nunca saem do prumo, e no celular a grade desce pra baixo do nome do item em vez
  de espremer as colunas. Nota de seção não servia: nem toda seção com três preços tinha
  uma, e quem chega por um chip cai direto na lista. E os **Adicionais** viram grade
  (`.menu-list.adicionais`), porque no papel são duas colunas de itens curtos. Os recados
  do rodapé do impresso (taxa de serviço, comida de fora, uso da casa como cenário)
  **não vão pro site**, a pedido: no papel eles são o combinado de quem já sentou; na
  página, fecham a leitura com uma lista de regras.
- **Âncora `#planos`** na seção dos cards do `planos.html`: quem chega de outra página já
  decidido cai direto na escolha, sem reler a abertura. É o destino do botão "assina um
  plano" do **Mural do Casa** (`/o-casa`), nos dois estados do CTA (deslogado e sem plano).
- **Cardápio, atalhos entre as seções** (`initCardapioNav`): a página é longa e de puro
  scroll, então uma tirinha de chips (`[data-cardapio-nav]`) gruda no topo da janela
  (`position: sticky; top: 0` — o header do site **rola junto com a página**, o sticky dele
  acaba no `#site-header`, então não há altura de header pra descontar), leva direto pra
  seção e marca onde a pessoa está. Os chips são montados a partir das **próprias seções**
  do HTML (as que têm `aria-labelledby` + `.menu-list`), então seção nova no cardápio já
  aparece na tirinha sem tocar no JS. Rola sozinha no mobile pra manter o chip ativo à
  vista; respeita `prefers-reduced-motion`.
  > **São 16 chips, um por seção, e isso não cabe numa linha em tela nenhuma.** A tirinha
  > é **uma fila só que rola na horizontal, em toda largura**: nada de quebrar linha (no
  > celular virariam cinco fileiras grudadas no topo, comendo a tela) e nada de parar na
  > coluna do conteúdo — o `.wrap` solta a largura (`max-width: none; padding: 0`) e a
  > faixa vai de ponta a ponta da tela, com o respiro das pontas acompanhando o do `.wrap`
  > (40px, 22px abaixo de 640) pra o primeiro chip nascer alinhado com o texto da página.
  > As pontas terminam em **degradê** (`mask-image`), que é o aviso de "tem mais pra
  > rolar" no lugar de um chip serrado por uma borda reta.
- **Colab** reutiliza o `setupCarousel` via `data-carousel="cards"` (mesmo contrato da home).

---

## Autenticação (Fase 2 — Supabase Auth)

Toda a lógica fica no bloco `// ===== AUTH =====` do `app.js`. **Só a anon key no client**
(`import.meta.env.VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY`) — a RLS é quem protege
os dados. Nada de service_role no bundle.

- **Client**: `export const supabase` (via `@supabase/supabase-js`). Se o `.env` não
  estiver preenchido (placeholder), `supabase` fica `null` e as telas degradam com aviso
  gentil, sem quebrar.
- **Helpers**: `getSession()`, `getUser()`, `getProfile()` (lê a **própria** linha do
  `profiles` — RLS `id = auth.uid()`), `signOut()`. O **papel (role) vem sempre do
  `profiles`**, nunca de valor do client.
- **Header**: `initAuth()` + `updateAuthUI(session)` preenchem `[data-auth-slot]` /
  `[data-auth-slot-mobile]`. Deslogado → "entrar"; logado → nome + "sair". Reage a
  `onAuthStateChange` (inclusive login/logout em outra aba). O nome de exibição vem do
  `user_metadata.full_name` e é **sempre escapado** (`escapeHtml`) antes de ir pro DOM.
- **Cadastro** (`initCadastroPage`): valida no client (nome, e-mail, senha ≥ 8, confirmação);
  `signUp` passa `full_name` + `telefone` em `options.data` → a trigger `handle_new_user`
  popula o `profiles`. Com "Confirm email" ligado, mostra o estado "confirme seu e-mail".
  O link de confirmação volta pra `auth-confirmado.html` via `options.emailRedirectTo`.
- **Login** (`initLoginPage`): `signInWithPassword`; "esqueci a senha" usa
  `resetPasswordForEmail`. Após entrar, respeita `?redirect=` (só caminho interno —
  `sanitizeRedirect`, anti open-redirect).
- **Confirmação** (`initAuthConfirmadoPage`, `auth-confirmado.html`): o supabase-js
  detecta a sessão na URL (`detectSessionInUrl`, padrão). Logado → "ir pra minha conta";
  senão → link pro login.
- **Base URL dos e-mails** (`siteBase()`): `import.meta.env.VITE_SITE_URL || window.location.origin`
  — **sem localhost hardcoded**. Serve `emailRedirectTo` (confirmação) e `redirectTo` (reset).
  Em prod, defina `VITE_SITE_URL` como env var na Vercel apontando pro domínio final.
- **Guard** (`requireAuth`): páginas com `[data-perfil-root]` (área `conta/`) exigem sessão;
  sem sessão → redireciona pro login guardando o destino. Nunca confia em role do client.
- **Perfil** (`initPerfilPage`): mostra dados + pontos + plano (via `tier_slug`); edita
  nome/telefone com `update` na própria linha (RLS garante) **e** espelha no `auth.updateUser`
  (metadata) pra o header refletir o nome novo.

> **Hardening / go-live (checklist de deploy):**
> - **"Confirm email" DEVE estar LIGADO** no Supabase (Auth settings). Pra testar o
>   happy-path local, o humano pode desligar temporariamente — mas **RE-LIGAR antes do deploy**.
> - **Site URL + Redirect URLs** (Supabase → Authentication → URL Configuration): precisam
>   listar **tanto o localhost de dev** (ex.: `http://localhost:5173` e `http://localhost:4173`)
>   **quanto o domínio final da Vercel** (prod). Sem isso, os links de confirmação/reset são
>   rejeitados. **Isto é config de painel, não código.**
> - Definir a env var **`VITE_SITE_URL`** na Vercel apontando pro domínio de prod (o código
>   já usa `siteBase()`; localmente o fallback é `window.location.origin`).

---

## Pagamentos (Asaas — substituiu o Stripe)

Gateway atual: **Asaas** (gateway BR). Assinatura dos 4 tiers **e** loja via
**Asaas Checkout** hospedado (`POST /checkouts` → redireciona pro `link`).
**Sem boleto.** Loja: **Pix + Cartão**; assinatura: **só cartão** — o Asaas não
permite Pix em cobrança recorrente (`RECURRENT` exige `CREDIT_CARD`; Pix não é
debitado sozinho todo mês). O **CPF é coletado na página hospedada do
Asaas** — a gente não guarda CPF. Toda a lógica sensível fica nas **Edge Functions**
(`supabase/functions/`), nunca no client.

> **Migrou do Stripe → Asaas.** As functions `stripe-webhook/` e
> `create-portal-session/` e o `scripts/stripe-seed.mjs` foram **removidos**. As
> colunas `stripe_*` continuam no banco (migrations são imutáveis) mas não são mais
> usadas. O Asaas **não tem seed de preços** (o valor vai no corpo do checkout) nem
> **portal de cobrança hospedado** (por isso as telas de pausar/retomar/upgrade são NOSSAS).

> **Cancelar = pausar (não deletar).** "Cancelar assinatura" faz `PUT status=INACTIVE`
> no Asaas (pausa, não `DELETE`): a pessoa **mantém o benefício até o fim do período já
> pago** (`current_period_end`) e a assinatura vira `status='pausada'` **guardando o
> tier**. "Retomar plano" reativa a MESMA assinatura (`PUT status=ACTIVE`) — dentro do
> período pago, **sem cobrar de novo**; se o período já venceu, reativa cobrando a
> partir de hoje. Assim ninguém "paga do zero" ao voltar. Só quando o Asaas responde
> 404 (assinatura sumiu do gateway) é que tratamos como `cancelada` de fato e limpamos
> o tier.

> **DESLIGADOS PELO CASA CLUB (ago/2026): upgrade e downgrade.** As duas Edge Functions
> seguem deployadas e com o código inteiro, e passaram a **recusar com recado em português**
> enquanto existir **uma categoria vendável só** (`tiers.vendavel`). Os dois blocos abaixo
> descrevem o que elas fazem quando religadas, e valem como referência, não como
> comportamento de hoje. Pausar, retomar e reassinar **não** mudaram. Ver "O CASA CLUB".

> **Upgrade = só a diferença proporcional.** Ao subir de tier, cobramos **apenas**
> `floor((preço_novo − preço_atual) × diasRestantes / 30)` agora (os dias já usados do
> ciclo NÃO são cobrados de novo); no próximo vencimento a assinatura já renova pelo
> preço cheio do tier novo. Se a diferença proporcional ficar abaixo do mínimo do Asaas
> (R$5,00 / 500 centavos), a gente **não cobra** — aplica o upgrade na hora de graça e
> só ajusta o `value` da assinatura pro preço novo.

> **Downgrade = agendado, sem reembolso.** O espelho invertido do upgrade: descer de
> plano **não cobra nem devolve nada agora**. A gente baixa o `value` recorrente no Asaas
> (só a PRÓXIMA cobrança vem menor) e grava `subscriptions.scheduled_downgrade_to` — a
> pessoa **mantém o tier atual até `current_period_end`**. Quem troca o tier de fato é o
> `asaas-webhook`, quando o pagamento da renovação cai. Dá pra desfazer enquanto não
> renova ("manter o plano atual"), e um upgrade também cancela a descida agendada.

- **Redirect 100% hospedado:** NÃO existe chave pública de pagamento no bundle. O
  client só chama a function e redireciona pro `link` que ela devolve.
- **Código agnóstico de ambiente:** sandbox e prod rodam o MESMO código — muda só a
  chave (secrets). A base da API (`api-sandbox` vs `api`) é derivada do **prefixo da
  chave** (`hmlg` = sandbox), override opcional via `ASAAS_BASE_URL`. Sem `if` no código.
- **Segredos SÓ nas Edge Functions** (`supabase secrets`, nunca client/bundle/repo):
  `ASAAS_API_KEY` (`$aact_hmlg_…` em sandbox), `ASAAS_WEBHOOK_TOKEN` (token que a gente
  escolhe e cadastra no webhook), `SITE_URL`. Injetados pelo Supabase: `SUPABASE_URL`,
  `SUPABASE_SERVICE_ROLE_KEY`. No **client**, nenhuma chave de pagamento.
- **`_shared/lib.ts` (Asaas)**: `asaasBaseUrl()`, `AsaasError`, `asaasFetch/Post/Get/Delete`
  (auth via header `access_token`), `reaisFromCentavos`/`centavosFromReais` (o Asaas fala
  em REAIS decimais; o banco em centavos). Helpers agnósticos de gateway (reusados):
  `computeCartFromDb()` (SOMA o subtotal pelo **BANCO** — products/product_variants, nunca
  do client), `getEffectiveSubscription(userId)` (assinatura que CONCEDE benefício agora:
  status em `['ativa','pausada']`, mais recente por `current_period_end`; a `pausada` só
  vale enquanto o período pago não venceu — se nenhuma concede, **auto-cura** limpando
  `profiles.tier_slug`), `getUserTierDiscount()` (desconto do tier vigente via
  `getEffectiveSubscription` → `tiers.discount_percent`; sem assinatura = 0%),
  `getTierMultiplier()`, `asaasPut()` (`PUT /subscriptions/{id}` — muda status/value/
  nextDueDate), `creditPoints()` (idempotente por `(ref_type,ref_id)`), `checkAchievements()`,
  `getUserFromRequest()`, CORS, `jsonResponse()`, `getSiteUrl()`.
- **`create-checkout-session`** — três modos, todos exigem JWT:
  - **assinatura** (`{ tier_slug }` → `chargeTypes:["RECURRENT"]`): lê `preco_centavos` do
    tier no BANCO, `subscription:{ cycle:"MONTHLY", nextDueDate: hoje }`. `externalReference`
    = `sub:<userId>:<tierSlug>:<nonce>` (o nonce garante 1 match ao resolver a assinatura
    criada, mesmo em re-assinatura). `successUrl` → `checkout-sucesso.html?assinatura=1`.
  - **loja** (`{ items: [{product_slug, variant, qtd}] }` → `chargeTypes:["DETACHED"]`):
    recalcula subtotal server-side, aplica o desconto do tier. Como o **Asaas não tem
    campo de desconto**, o carrinho vira **UM item consolidado** cujo `value` = total já
    com desconto (a discriminação real fica em `order_items`). **Pré-cria a `orders`
    como `pendente` + `order_items`**; `externalReference` = `order.id` (UUID); em falha
    do Asaas, apaga a order. `successUrl` → `checkout-sucesso.html?ref=<order.id>`.
  - **upgrade** (`{ upgrade_to_tier }` → `chargeTypes:["DETACHED"]`): valida a assinatura
    vigente via `getEffectiveSubscription`, lê os dois preços no BANCO, **exige que o tier
    novo seja mais caro**. Calcula `diasRestantes = clamp(ceil((fimPeríodo−agora)/dia),
    0..30)` e `delta = max(0, floor((preçoNovo−preçoAtual) × diasRestantes / 30))` —
    **só a diferença proporcional aos dias que faltam**. Se `delta < 500` (mínimo do
    Asaas), aplica o upgrade **na hora e de graça** (`asaasPut` o `value` da assinatura
    pro preço novo + atualiza `subscriptions.tier_slug`/`profiles.tier_slug`) e retorna
    `{ applied:true, valor_delta_centavos }`. Senão, gera um checkout DETACHED só do delta,
    `externalReference` = `upg:<userId>:<toTier>:<asaas_subscription_id>:<nonce>`,
    `successUrl` → `checkout-sucesso.html?upgrade=1`, retorna `{ url, valor_delta_centavos }`.
  - `billingTypes`: **loja/upgrade** `["PIX","CREDIT_CARD"]`; **assinatura** `["CREDIT_CARD"]`
    (o Asaas recusa `RECURRENT` com PIX — só cartão renova sozinho). **Sem `customerData`**
    (mandar parcial faria o Asaas exigir CPF+endereço completo; a página hospedada coleta
    tudo). Todos: `callback` com `successUrl`/`cancelUrl`/`expiredUrl` via `getSiteUrl()`.
- **`cancel-subscription`** (a NOSSA tela substitui o portal): exige JWT, lê a assinatura
  ATIVA do **próprio** usuário (nunca id vindo do client), faz `PUT /subscriptions/{id}`
  com `status=INACTIVE` (**pausa, não deleta**), marca `subscriptions.status='pausada'`
  **mantendo o `tier_slug` e o período** — o benefício segue até `current_period_end`.
  Retorna `{ ok, pausada:true, ativo_ate }`. Asaas 404 (assinatura sumiu do gateway) →
  trata como `cancelada` de fato, limpa o tier, retorna `{ ok, cancelada:true }`.
- **`resume-subscription`** (contrapartida do cancel): exige JWT, lê a assinatura
  **`pausada`** do próprio usuário, faz `PUT /subscriptions/{id}` com `status=ACTIVE`.
  Dentro do período pago → mantém o `nextDueDate` original (**sem cobrar agora**); período
  vencido → `nextDueDate = hoje` (o Asaas cobra o cartão salvo e recomeça o ciclo).
  Marca `subscriptions.status='ativa'` + garante `profiles.tier_slug`. Retorna
  `{ ok, retomada:true, proxima_cobranca }`.
- **`downgrade-subscription`** (o espelho invertido do upgrade): exige JWT, lê a assinatura
  **`ativa`** do próprio usuário. **AGENDAR** (`{ tier_slug }`): exige destino mais barato
  (os dois preços vêm do BANCO), faz `asaasPut` baixando o `value` — só a PRÓXIMA cobrança
  vem menor, o ciclo já pago não muda — e grava `subscriptions.scheduled_downgrade_to`
  **sem tocar no tier atual**; nada é cobrado nem reembolsado. Retorna
  `{ ok, agendado:true, efetivo_em, novo_plano, novo_slug }`. **DESFAZER**
  (`{ acao:'cancelar' }`): limpa a coluna e restaura o `value` cheio. Os dois passos
  (Asaas ↔ banco) se revertem mutuamente em caso de falha, pra nunca sobrar `value` baixo
  sem downgrade agendado. Quem troca o tier de fato é o webhook, na renovação.
- **Presentear um plano** (`create-checkout-session` modo presente + `resgatar-presente`):
  o comprador paga **um mês cheio** de um tier **de presente** (cobrança avulsa `DETACHED`,
  Pix ou cartão — **não** vira assinatura dele). Fluxo: `{ gift_tier, mensagem }` →
  pré-cria `gift_subscriptions` (`pendente`) → checkout `externalReference = gift:<id>`,
  `successUrl` → `checkout-sucesso.html?presente=<id>`. No `CHECKOUT_PAID` o webhook marca
  `pago` e gera o **código** `CASA-XXXXXX` (RPC `marcar_presente_pago`, idempotente);
  `CHECKOUT_EXPIRED/CANCELED` cancela o presente `pendente`. Quem ganha resgata o código
  no `/conta/perfil` ("tem um presente?") → `resgatar-presente` → RPC atômica
  `resgatar_presente` (lock, anti-duplo-resgate): cria uma `subscriptions` **`pausada` +
  `current_period_end = agora+30d`** marcada com `presente_id` (SEM `asaas_*` — não recorre)
  e espelha o tier. **Por quê `pausada`+período e não `ativa`:** `getEffectiveSubscription`
  concede benefício pra `pausada` só enquanto o período está no futuro → o presente
  **expira sozinho em 30 dias**, sem cron e sem o risco do "`ativa` concede pra sempre"
  (não há assinatura no Asaas pra gerar `PAYMENT_OVERDUE`). O resgate é **bloqueado** se a
  pessoa já tem plano vigente (o presente fica guardado — não empilha). O perfil trata
  `presente_id` à parte (selo "presente · ativo até {data}", **sem** pausar/retomar/upgrade);
  o `resume-subscription` já barra `pausada` sem `asaas_subscription_id`. Página de compra:
  **`/presentear`** (`initPresentearPage`), linkada nos `/planos`.
- **`asaas-webhook`** (deploy com `--no-verify-jwt`): auth = **token compartilhado** no
  header `asaas-access-token` (comparado com `ASAAS_WEBHOOK_TOKEN`; NÃO é HMAC).
  Idempotência via `asaas_events` (PK = `id` do evento, `evt_…`). Em erro → 500 sem gravar
  o evento (o Asaas reenvia); em sucesso → grava e 200.
  - **loja**: `CHECKOUT_PAID` finaliza a MESMA `orders` (por `id` = externalReference) pra
    `pago` (nunca faz downgrade de `pago`) + credita pontos (`ref_type='order'`,
    `ref_id=order.id`, motivo `'compra na loja'`) + `checkAchievements`. `CHECKOUT_EXPIRED`/
    `CHECKOUT_CANCELED` marca o pedido pendente como `cancelado`.
  - **assinatura**: `CHECKOUT_PAID` resolve a assinatura criada via
    `GET /subscriptions?externalReference=…`, faz upsert em `subscriptions` (por
    `asaas_subscription_id`) e espelha `profiles.tier_slug` — **sem pontos aqui**. Os pontos
    vêm dos eventos de **pagamento** `PAYMENT_CONFIRMED`/`PAYMENT_RECEIVED` (`ref_type=
    'subscription'`, `ref_id=payment.id`, motivo `'assinatura'`) — 1ª cobrança E renovações,
    sem duplicar (idempotente por `payment.id`). O handler de pagamento **se auto-cura**
    (cria a linha de subscription se o evento de pagamento chegar antes do checkout).
  - **upgrade** (`externalReference` começa com `upg:`): `CHECKOUT_PAID` do delta aplica o
    upgrade — `asaasPut` o `value` da assinatura (id vem no próprio ref) pro preço cheio do
    tier novo, atualiza `subscriptions.tier_slug`/`profiles.tier_slug` e roda
    `checkAchievements` — **sem creditar pontos pelo delta**. Também **limpa
    `scheduled_downgrade_to`**: subir de plano cancela uma descida agendada.
    `CHECKOUT_EXPIRED`/`CHECKOUT_CANCELED` ignoram refs `sub:`/`upg:` (só cancelam pedidos
    de loja pendentes).
  - **downgrade agendado**: no `PAYMENT_CONFIRMED`/`PAYMENT_RECEIVED` da renovação, se a
    linha tem `scheduled_downgrade_to`, o handler troca o `tier_slug` pro plano leve
    **antes** de creditar os pontos (pra já valer o multiplicador novo) e limpa a coluna
    no mesmo update — idempotente, o reenvio do evento não desce duas vezes.
  - **estorno e chargeback** (`PAYMENT_REFUNDED`/`PAYMENT_CHARGEBACK_REQUESTED`): devolve os
    pontos que aquele pagamento creditou, senão dá pra pagar, ganhar pontos, resgatar a
    recompensa e pedir chargeback ficando com tudo. O delta negativo pode deixar o saldo
    **negativo** de propósito (a pessoa "deve" pontos; resgate só volta a passar quando o
    saldo cobre). Os dois fluxos creditam com chaves diferentes, então são dois caminhos:
    **assinatura** acha o crédito por `ref_id=payment.id` e estorna em `ref_type='estorno'`;
    **loja** acha o pedido pela ponte `payment.checkoutSession` = `orders.asaas_checkout_id`
    (o crédito da loja é por `order.id`, o id do pagamento não aparece nele), estorna em
    `ref_type='estorno_order'` / `ref_id=order.id` **e marca o pedido `'estornado'`** (0035),
    pra ele sair da fila de separar e entregar. Carimba o `asaas_payment_id` no pedido, que
    até então nunca era gravado. Idempotente nos dois; `CHECKOUT_PAID` reenviado **não**
    ressuscita pedido estornado.
- **Migration `0011_asaas`**: `profiles.asaas_customer_id`; `subscriptions.asaas_customer_id`
  + `asaas_subscription_id` (UNIQUE); `orders.asaas_checkout_id` (UNIQUE) + `asaas_payment_id`;
  tabela `asaas_events(id text pk, event, processed_at)` com RLS (SELECT só do owner).
  Idempotente; não mexe em nada anterior (as colunas `stripe_*` ficam intactas, sem uso).
- **Erro do checkout na tela**: quando a `create-checkout-session` recusa (plano
  indisponível, assinatura vigente, presente que não deu pra criar), o motivo vem em
  português no corpo **não-2xx**, que o supabase-js guarda em `error.context`. O
  `/presentear` e o "assinar" dos `/planos` liam só `error` e mostravam sempre o mesmo
  "tenta de novo daqui a pouco", escondendo a causa de quem usa e da gente. Agora os dois
  leem `await error.context.json()` e mostram o recado da function (o genérico fica de
  reserva pra corpo não-JSON, tipo 502). Quando quem recusa é o **Asaas com 4xx**
  (validação de payload), a function manda junto um `detalhe` com a descrição crua do
  gateway e a tela mostra entre parênteses; 5xx do Asaas segue genérico, porque ali não é
  recado pra quem está comprando.
- **Nada de emoji no que vai pro Asaas.** O `/presentear` nasceu com um 💛 na descrição do
  item do checkout e era o **único** dos quatro checkouts do site com um caractere de 4
  bytes ali; o gateway recusava, virava `AsaasError`, e o presente morria em "não deu pra
  iniciar o checkout agora" desde sempre. Assinatura, loja e upgrade só usaram texto e
  "·", e por isso nunca quebraram. Emoji no site, à vontade; em `name`/`description` de
  payload do Asaas, não.
- **A espera do código do presente** (`aguardarCodigoPresente`, na `checkout-sucesso`):
  quando a pessoa volta do pagamento, o código **ainda não existe** — quem gera é o
  `asaas-webhook` no `CHECKOUT_PAID`, e entre uma coisa e outra passam alguns segundos.
  Isso pesa mais aqui que em qualquer outro fluxo porque **o código do presente não
  aparece em nenhuma outra tela do site**: quem fechava a aba antes ficava sem. A tela
  tem três estados no `[data-presente-bloco]`: **espera** (girinho + "estamos preparando o
  código do teu presente", com o texto trocando depois de 30s pra não parecer travado),
  **pronto** (o código grande, botão de copiar e o que fazer com ele) e **demora** (recado
  com o WhatsApp da casa). A sondagem vai a **~2 minutos** (15 tentativas de 2s e mais 18
  de 5s), no lugar dos 9 segundos de antes. E os atalhos de sair (`[data-sucesso-saidas]`)
  ficam **escondidos enquanto a espera não resolve**: é o jeito gentil de segurar a pessoa
  na tela, sem sequestrar o botão de voltar do navegador.
- **"os presentes que tu deu" (`/conta/perfil#presentes`) é a rede de segurança disso:**
  a seção `[data-meus-presentes]` lista os presentes que a pessoa **comprou**, com código,
  plano, data e se já foi resgatado (mais o "copiar"). Sem ela, o código existia numa tela
  só e "perdeu, perdeu". **Sem migration nem serviço novo**: a `gift_select_own` da `0019`
  já deixa o comprador ler a própria linha, então é uma quarta consulta no `Promise.all`
  que a `initPerfilPage` já fazia, filtrando `status in ('pago','resgatado')` (`pendente`
  é checkout que nunca fechou e nem tem código). A seção **só entra no HTML quando existe
  algum presente**, então quem nunca presenteou não vê caixa vazia e o índice de seções
  também não a lista. Os dois estados da tela de sucesso apontam pra cá. O pulo de âncora
  do perfil deixou de ser hardcoded no `#assinatura` e passou a valer pra qualquer `#id`
  da página (a âncora nativa não pega numa página montada depois do guard de auth).
  > **E-mail do código: adiado a pedido (13/ago/2026).** O site não manda e-mail nenhum
  > hoje (só os automáticos do Supabase Auth), então mandar o código por e-mail pediria um
  > provedor novo (Gmail com senha de app, ou Resend com domínio verificado) e um secret
  > novo. Ficou pra depois; a espera na tela mais a lista no perfil cobrem o caso.
- **Front**: o drawer "finalizar compra" chama a function da loja (deslogado → login e
  volta pro carrinho via `?cart=open`); mostra o aviso do desconto do tier; `checkout-
  sucesso.html` limpa o carrinho e — na loja — sonda `points_ledger` por `?ref=` pra mostrar
  "+X pontos"; na assinatura (`?assinatura=1`) não sonda (os pontos vêm por `payment.id`,
  desconhecido do client); no upgrade (`?upgrade=1`) troca o texto pra "plano turbinado 💛"
  e também não sonda.
- **Front — "gerenciar assinatura" (perfil)**: `initPerfilPage` carrega a assinatura
  (`status` em `['ativa','pausada','cancelada']`, a mais recente) + a lista de `tiers` em
  paralelo e deriva o estado da UI. A célula "teu plano" mostra o nome + um selo de status
  (ativa → ponto verde "ativo"; pausada dentro do período → "pausado · ativo até {data}";
  pausada vencida → "pausado"; cancelada → "encerrado"). A seção `[data-gerenciar]` aparece
  com assinatura ativa/pausada **ou** cancelada-com-tier-conhecido e traz:
  - **ativa** → "fazer upgrade" (abre painel `[data-upgrade-painel]` só com os tiers de
    `ordem` maior, cada botão explicando que cobra **só a diferença dos dias que faltam**;
    ao escolher, chama `create-checkout-session {upgrade_to_tier}` → se `data.url` redireciona
    pro checkout do delta, se `data.applied` mostra "a diferença ficou por nossa conta" e
    recarrega) **e** "pausar assinatura" (confirma → `cancel-subscription`).
  - **ativa, no modal de pausar** → antes de confirmar a pausa, um desvio gentil oferece
    **descer de plano** em vez de sair (`[data-modal-downgrade]`, só com os tiers de `ordem`
    menor). Escolher um abre um passo de confirmação com o preço e a data em que passa a
    valer; confirmar chama `downgrade-subscription { tier_slug }`. Com downgrade já agendado,
    o texto vira "teu {plano} segue ativo até {data}, e a partir daí vira {plano leve}" e
    aparece **"manter o {plano}"** (`[data-manter-plano]` → `downgrade-subscription
    { acao:'cancelar' }`, sem confirmação — é a ação positiva). O upgrade continua ofertado
    e desfaz a descida agendada.
  - **pausada** → "retomar plano" (`resume-subscription`; dentro do período não cobra nada).
  - **cancelada** (Asaas 404 — sumiu do gateway, não dá pra "retomar") → "voltar pro {plano}"
    (`[data-reassinar]`): chama `create-checkout-session {tier_slug}` do MESMO tier — é uma
    **assinatura nova** (checkout hospedado, ciclo do zero), redireciona pro `data.url`.
- **Setup/deploy**: ver `supabase/functions/README.md`. Teste em sandbox com cartão de
  teste (doc do Asaas) ou Pix simulado no painel sandbox.

> **Go-live LIVE (o que muda no dia — só config/secrets, o código NÃO muda):**
> - Criar/usar a conta de **produção** do Asaas (KYC completo) e gerar a chave
>   `$aact_prod_…`.
> - Trocar os secrets das functions: `supabase secrets set` de `ASAAS_API_KEY`
>   (`$aact_prod_…`), um `ASAAS_WEBHOOK_TOKEN` novo e `SITE_URL` (domínio de prod).
>   Re-deploy das **seis** functions.
> - **Cadastrar o webhook na conta LIVE** (o token/endpoint de sandbox não vale em
>   prod), com os eventos de checkout (`CHECKOUT_PAID`/`EXPIRED`/`CANCELED`) e de
>   pagamento (`PAYMENT_CONFIRMED`/`PAYMENT_RECEIVED`).
> - **Habilitar Pix e Cartão na conta LIVE**.
> - No client/Vercel: nada de chave de pagamento (o checkout é hospedado).

---

## O CASA CLUB — uma assinatura, quatro categorias por tempo

O clube deixou de ser **quatro planos pagos** e virou **uma assinatura só, de R$88,90/mês**
(documento "Projeto CASA CLUB", ago/2026; decisões fechadas com a casa em 18/ago/2026). Os
quatro nomes que já existiam continuam, mas **trocaram de eixo**: eram PREÇO, viraram
**TEMPO DE CASA**.

| Slug (interno) | Categoria | A partir de | Significado |
|----------------|-----------|-------------|-------------|
| `bronze`   | Vizinho de Sempre | na entrada | chegou, e já faz parte |
| `prata`    | Frequentador      | 3 meses    | o Casa entrou na rotina |
| `ouro`     | Gente do Casa     | 6 meses    | já é gente daqui |
| `diamante` | Alma do Casa      | 12 meses   | o que era visita virou história |

As quatro custam o mesmo, dão o **mesmo 10% na loja** e o **mesmo 1 ponto por R$1**. O que
muda de uma pra outra é só o reconhecimento de quem fica. **Só a de entrada é comprável**
(`tiers.vendavel`), e o índice `idx_tiers_vendavel_unica` garante que seja uma só.

- **Os slugs `bronze`/`prata`/`ouro`/`diamante` NÃO mudaram, e isso é decisão.** O
  `tier_slug` está em mais de trinta pontos entre front, Edge Functions e migrations, com FK
  vindo de `subscriptions`, `gift_subscriptions` e `profiles`. Renomear pediria UPDATE em
  dado histórico de produção pra ganhar só legibilidade interna, e o slug nunca aparece na
  tela de ninguém. Quem ler o banco daqui pra frente precisa saber que **`ouro` quer dizer
  "seis meses de casa"**, não "plano de setenta e nove reais".
- **`vendavel` é coluna NOVA, e nunca o `ativo` que já existia.** O `getUserTierDiscount`
  devolve `tier_slug` **nulo** pra tier `ativo = false`, e o `creditPoints` dá **zero ponto**
  com slug nulo. Marcar as três categorias superiores como inativas faria quem sobe de
  categoria **parar de pontuar e perder o desconto** no mesmo instante em que a casa quis
  agradecer a permanência. As quatro seguem `ativo = true`.
- **O relógio ACUMULA, não corre no calendário.** Quem ficou 4 meses, pausou 6 e voltou,
  volta com **4** meses de casa, não com 10. O tempo é a **união dos intervalos** de todas as
  linhas de `subscriptions` da pessoa (`created_at` → `least(current_period_end, now())`),
  nunca a soma crua: um presente resgatado por cima de uma assinatura ativa contaria o mesmo
  mês **duas vezes**. Assinatura `cancelada` conta pelo tempo que cobriu (o vivido não some),
  e **um mês de presente conta igual**. Um mês = **30 dias**, arredondando a favor de quem
  fica (a Asaas renova em ~30,44 dias, então 12 meses caem uns cinco dias antes).
- **A categoria mora no `tier_slug`, não só na tela do clube.** Escrevendo a promoção lá, o
  header, o painel do avatar, o cartão do `/gente`, o `/conta/perfil` e o console mostram a
  categoria certa **sem uma linha de código nova nesses lugares**. Se fosse derivada só na
  tela, o perfil diria "Vizinho de Sempre" pra quem tem dois anos de casa.
- **Sem cron.** Quem promove é a `sincronizar_categoria`, chamada em dois lugares de
  propósito: no **`asaas-webhook`**, a cada pagamento de renovação (é o único evento mensal
  que o site já recebe de graça), e na **leitura da `/conta/clube`** (auto-cura: se o webhook
  falhar, a próxima visita conserta). Ela só escreve quando a categoria muda de verdade,
  então chamar duas vezes é inócuo, e acende a GUC `casa.trusted_points` porque a trigger
  `prevent_points_tamper` barra escrita de `tier_slug` vinda de sessão autenticada.
- **Sem plano vigente, a categoria é limpa** (mesma auto-cura do `getEffectiveSubscription`).
  O tempo continua guardado no banco, mas categoria é benefício, e benefício não é vitalício.
- **As conquistas não precisaram mudar.** A `gente-do-casa` e a `alma-do-casa` já tinham
  critério `{"type":"tier","slug":"ouro"|"diamante"}` desde a 0009: como a categoria agora
  mora no mesmo `tier_slug`, elas viraram sozinhas **o carimbo de chegada na categoria**, que
  é o que o documento pede. Sem isso, o mesmo nome significaria duas coisas (a residência do
  `/colab` já se chama "Gente do Casa").
- **`/conta/clube`** (`initClubePage`, atrás do `requireAuth`) responde as quatro perguntas do
  documento numa chamada só (`meu_clube`): em que categoria tu está, quanto falta pra próxima,
  quantos pontos tu tem e o que dá pra trocar. E **diz na cara** que hoje os pontos vêm da
  loja e da mensalidade, porque o consumo no balcão ainda não pontua (ver abaixo).
- **Upgrade e downgrade foram DESLIGADOS, não removidos.** As Edge Functions
  `create-checkout-session` (modo upgrade) e `downgrade-subscription` seguem deployadas e
  intactas; as duas passaram a recusar com recado em português **quando existe uma categoria
  vendável só**, então religar é dado, não código. No `/conta/perfil`, os painéis somem
  sozinhos porque as listas passaram a filtrar por `vendavel` (o filtro do upgrade olhava só
  a `ordem`, e teria oferecido as três categorias superiores como se fossem compráveis). O
  **desfazer** do downgrade continua passando de propósito: quem agendou uma descida antes da
  virada precisa poder cancelar, senão renovaria pelo valor de um plano que não existe mais.
  "Pausar", "retomar" e "voltar pro plano" não mudaram.
- **O que o balcão ainda não faz:** o documento assume que consumo no salão pontua, e o site
  só enxerga o checkout (loja e mensalidade). A `pos_webhook_events` e o `POS_WEBHOOK_SECRET`
  seguem reservados desde a Fase 3, e as 50 conquistas do cardápio (0038) seguem `ativo =
  false` esperando o mesmo dia. Enquanto isso, o `/conta/clube` e o `/planos` falam a verdade
  em vez de prometer.
- **Ficou fora desta leva** (do documento, pra levas seguintes): CASA MAIL (o envio físico
  mensal, com edições numeradas e logística), os mails de mudança de nível, PASS IT ON, CASA
  Friends, o catálogo de recompensas novo (a escala 100→1.000, que pede CMV item a item) e os
  "pontos em dobro" por campanha.
- **O platter brunch mensal virou software na `0050`** (ver "Os dois brunches" abaixo): tem
  resgate, código, validade e baixa no console, no mesmo desenho do brunch de aniversário.
- **A CAIXA DO CASA AINDA É PROMESSA DE VITRINE, SEM SOFTWARE POR BAIXO.** Ela aparece na
  lista do `/planos`, do `/conta/clube`, do `/presentear` e do convite do painel, mas **nada
  no site a controla**: não há registro de envio, não dá pra saber se a caixa deste mês saiu
  nem pra quem. Quem controla é a casa, na expedição. É o CASA MAIL do documento e volta como
  leva própria (o endereço já está no `profiles` desde a 0014).
- **Migração de quem já assinava:** o código trata todo mundo como uma assinatura só, e a
  categoria é recalculada pelo tempo real de casa (quem já tinha um ano vira Alma do Casa na
  primeira sincronização, sem ninguém mexer). **Ajustar o valor das assinaturas antigas no
  painel do Asaas é trabalho do humano**, não desta leva.

## Fidelidade / Pontos (Fase 3)

O `points_ledger` (0001, append-only) é a **fonte da verdade**; `profiles.points_balance`
é um **cache** que nunca diverge (trigger). Todo cálculo de saldo é server-side; o front
só LÊ (RLS: cada um lê o próprio ledger).

- **Regra (travada):** fidelidade é **exclusiva de assinante**. Só pontua quem tem plano
  ATIVO no momento da compra. **Sem assinatura ativa = ZERO pontos** (a trava fica no
  `creditPoints`: `tierSlug` nulo → 0). **Desde o CASA CLUB (ago/2026) a conta é 1 ponto por
  R$1, sem multiplicador**: as quatro categorias têm `points_multiplier = 1.00`, porque a
  regra tinha que caber na cabeça de quem ouve no balcão. A coluna e o `getTierMultiplier`
  continuam existindo (é o que permitiria uma campanha futura), só que hoje todas valem 1.
  Loja: sobre o total **já com desconto**. Sempre `floor`. Ex.: R$49,41 rende 49 pontos com
  plano, e 0 sem plano. A LOJA passa `order.tier_slug_aplicado` (null quando não havia
  assinatura no checkout) e a ASSINATURA sempre passa a categoria vigente.
  > **O balcão ainda não pontua.** O `creditPoints` só é chamado pelo `asaas-webhook`, então
  > hoje pontuam a **loja** e a **mensalidade**. O consumo no salão entra quando a frente de
  > caixa entrar (`pos_webhook_events` + `POS_WEBHOOK_SECRET`, reservados desde a Fase 3).
  > O `/conta/clube` e o `/planos` dizem isso na tela, em vez de prometer ponto que não vem.
- **Migration `0008_points`**: `points_ledger.ref_type/ref_id` (+ UNIQUE parcial pra
  anti-duplicação), trigger `update_points_balance` (soma o delta no cache; seta a GUC
  `casa.trusted_points` pra o `prevent_points_tamper` liberar o write server-side),
  `recalc_points_balance` (reparo, só service_role), `redeem_reward` (resgate ATÔMICO com
  `for update`), `rewards_catalog.slug/cupom_valor_centavos` + seed de recompensas. O
  `motivo` do ledger virou texto livre em PT (`'compra na loja'`, `'assinatura'`,
  `'renovação da assinatura'`, `'resgate: <nome>'`) — o CHECK restritivo foi removido.
- **Crédito (`asaas-webhook`, via `creditPoints` de `_shared/lib.ts`)**: loja →
  `CHECKOUT_PAID` (só quando o pedido vira `pago`), `ref_type='order'` / `ref_id=order.id`,
  motivo `'compra na loja'`; assinatura → `PAYMENT_CONFIRMED`/`PAYMENT_RECEIVED`,
  `ref_type='subscription'` / `ref_id=payment.id`, motivo `'assinatura'` — o MESMO caminho
  serve a 1ª mensalidade e as renovações (o `payment.id` novo de cada ciclo é o que
  diferencia). O `CHECKOUT_PAID` de assinatura **não** credita ponto (senão a 1ª cobrança
  contaria duas vezes), e o delta de upgrade também não. Idempotente por
  `(ref_type, ref_id)` + `asaas_events`. Crédito **nunca** vem do client.
- **Resgate (`redeem-reward` → RPC `redeem_reward`)**: valida JWT, chama a função SQL via
  service_role com o id do PRÓPRIO usuário. A função (revogada de anon/authenticated) trava
  a linha do reward, valida saldo pelo LEDGER/estoque, lança o negativo, cria `redemptions`,
  baixa estoque e gera cupom `CASA-XXXX` (30 dias) se for do tipo cupom. Resgate duplo é
  impossível (lock). Saldo insuficiente → erro gentil, sem débito.
- **Front**: `conta/pontos.html` (`initPontosPage`, atrás do `requireAuth`) — saldo,
  multiplicador do tier, extrato do ledger e grid de recompensas com "resgatar" (desabilitado
  gentil "faltam X pontos" quando não dá). O perfil linka pro extrato; na loja a
  `checkout-sucesso` sonda o ledger pelo `?ref=` (id da order) e mostra "+X pontos 💛" —
  na assinatura não sonda, porque o `ref_id` é o `payment.id`, que o client não conhece.
  Tom acolhedor, ZERO cara de cassino.
- **Alinhamento dos cards de recompensa:** o rótulo do tipo ("cupom de desconto",
  "parceiro local") quebra em uma ou duas linhas conforme o texto, e isso empurrava o
  título de cada card pra uma altura diferente. O `.pt-rw-tipo` reserva as duas linhas
  (`min-height: 3.2em`), então os quatro títulos, preços e botões nascem no mesmo prumo.
- **"Quase lá" (o carimbo digital):** um cartão de foco no topo da `/conta/pontos`, logo abaixo
  do saldo, no espírito do cartão de carimbo de cafeteria. Aponta o **próximo mimo fora de
  alcance** (a recompensa mais barata que o saldo ainda não cobre, do `rewards_catalog` já
  carregado, ordenado asc; estoque zerado não conta) com uma **barrinha de progresso**
  (`saldo/custo`, mínimo 3% pra sempre aparecer): *"faltam X pontos pro teu {mimo}"*. Se o saldo
  já cobre tudo o que está na vitrine, vira o recado *"tu já pode pegar teu mimo"*. **Puro
  visual e só-leitura** (sem migration/secret/função nova): reusa `saldo` + `rewards` que a
  `initPontosPage` já busca. Markup em classes Tailwind (`.card`, `bg-coral`/`bg-line`), honesto,
  sem contador de urgência.
- **Go-live:** garantir que o webhook do Asaas (sandbox e live) escuta **`PAYMENT_CONFIRMED`
  e `PAYMENT_RECEIVED`** além dos eventos de checkout — sem eles a assinatura nunca pontua —
  e fazer deploy do `redeem-reward`. Nenhuma regra de pontos muda entre sandbox e live.

---

## Indica um amigo (Fase 3 — crescimento)

Cada usuário ganha um **código de indicação**; quem é trazido cria conta pelo link
`/cadastro?indica=CÓDIGO`, assina, e quando o **primeiro pagamento confirma** os **dois
ganham pontos**. A recompensa cai no PAGAMENTO (não no cadastro) de propósito: só
compensa quando entra gente de verdade pagando, matando conta-fantasma.

- **Migration `0021_indicacoes` (APLICADA em 10/ago/2026):** coluna
  `profiles.referral_code` (unique), tabela `referrals` (`referrer_id` ON DELETE SET
  NULL, `referred_id` UNIQUE → cada conta é indicada no máx. 1 vez, `status`
  pendente|premiado|invalido) com RLS (cada um lê só o que fez/recebeu; **sem escrita
  pelo client**), e 3 RPCs SECURITY DEFINER: `meu_codigo_indicacao()` (gera/retorna o
  código do próprio `auth.uid()`, granted a `authenticated`), `registrar_indicacao(codigo)`
  (usa `auth.uid()` como INDICADO — o client nunca diz quem é; barra auto-indicação, quem
  já foi indicado e quem já tem assinatura; granted a `authenticated`) e
  `premiar_indicacao(referred_id, pts_indicador, pts_indicado)` (idempotente
  pendente→premiado, credita os dois no `points_ledger`; granted **só a `service_role`**).
- **Valores dos pontos = FICTÍCIOS**, provisórios: constantes `REFERRAL_PTS_INDICADOR`
  (150) / `REFERRAL_PTS_INDICADO` (100) no topo do `asaas-webhook` — **uma fonte de
  verdade**, passadas pra `premiar_indicacao`. A copy do `/conta/perfil` restata os
  números (procurar "VALOR FICTÍCIO"). Ajustar depois.
- **Pontos de indicação NÃO passam pelo multiplicador de tier** (é bônus fixo, não compra):
  entram direto no ledger com `ref_type='indicacao'` (indicador) e `'indicacao_bonus'`
  (indicado), ambos `ref_id = referral.id` — ref_type distinto deixa os dois coexistir no
  UNIQUE `(ref_type, ref_id)`.
- **`asaas-webhook` (já deployado em 03/ago/2026):** no `PAYMENT_CONFIRMED`/`RECEIVED` da
  assinatura, depois de creditar os pontos da assinatura, chama `premiar_indicacao` com o
  id do pagante. Sem indicação pendente → `rewarded:false` sem erro; erro de DB estoura
  (o Asaas reenvia, tudo idempotente).
- **Front:** `initIndicacao()` (boot, toda página) capta o `?indica=` pro localStorage e,
  quando logado, registra o vínculo uma vez via `registrar_indicacao` (limpa o rastro só
  na resposta definitiva do banco). `/cadastro` mostra um oi gentil se veio por convite.
  `/conta/perfil` tem a seção "traz quem tu gosta" (`[data-indica]`): pega o código via
  `meu_codigo_indicacao`, monta o link, botão "copiar" (com fallback de seleção), e conta
  quantos amigos já entraram (`referrals` premiados). Tudo **tolerante**: se a 0021 ainda
  não foi aplicada, a seção fica escondida e o registro só é adiado — nada quebra.
- **No ar:** migration aplicada em 10/ago/2026, front na `main`.

---

## Recado da casa (aviso no topo do site)

Uma tarja fina no topo (antes do `<header>`) que o Casa acende com um recado curto e
datado: *"hoje tem fornada de brioche a partir das 15h 🥐"*, *"a gente fecha 17h nesse
sábado"*. Some sozinha quando a janela expira; a pessoa pode fechar e ela não volta
(o front lembra pelo id). Editável **só pelo owner** no console do adm.

- **Migration `0022_avisos` (APLICADA em 10/ago/2026):** tabela `avisos_casa`
  (`texto` ≤160, `emoji`, `link_url`/`link_label`, janela `inicio_em`/`fim_em`,
  `prioridade`, `ativo`) com RLS: **leitura pública SÓ do vigente** (a policy filtra
  `ativo` + janela com `now()` — anon nunca vê rascunho/agendado/expirado; owner vê tudo).
  **Escrita** só via 3 RPCs SECURITY DEFINER gated por `is_owner()`:
  `admin_avisos_listar()`, `admin_aviso_salvar(...)` (cria/edita), `admin_aviso_remover(id)`
  — deny-by-default pro client, sem INSERT/UPDATE/DELETE de RLS.
- **Owner-only de propósito:** o whitelist de permissões do console é fechado por CHECK
  (0017), então "avisos" **não** entra em `PERMISSOES` como grantável; a aba `recados`
  usa `perm: 'avisos'`, que só quem tem `tudo` (adm do Casa) enxerga. Delegar pra outro
  papel pediria uma migration alterando aquele CHECK.
- **Front:** `renderAvisoBar()` (boot, toda página) lê o vigente (RLS), injeta a tarja
  antes do header, escapa texto/link (link só interno `/x` ou `http(s)`), fecha com ×
  (colapso via `grid-template-rows`, sem cortar texto) e lembra o id fechado no
  localStorage (`casa_avisos_lidos`). Tolerante: sem a 0022, a tarja só não aparece.
- **Console:** aba **recados** (`viewRecados` em `admin.js`) — form pra escrever/agendar/
  ligar-desligar + lista com editar/remover.
- **No ar:** migration aplicada em 10/ago/2026, front na `main`.

---

## A trilha do Casa (playlists do Spotify)

A seção "a trilha do Casa" na home: playlists reais do Spotify (embed), curadas por
clima ("pra focar", "manhã lenta"), com uma marcada como **tocando agora** (selo
pulsante). Editável **só pelo owner** no console — nada de URL hardcoded.

- **Migration `0023_trilha` (APLICADA em 10/ago/2026):** tabela `playlists_casa`
  (`nome`, `clima`, `spotify_url`, `ordem`, `ativo`, `tocando`) com RLS (**leitura pública
  só das ativas**; owner vê tudo) + índice único parcial garantindo **uma `tocando` por
  vez**. Escrita só via 3 RPCs SECURITY DEFINER `is_owner()` (`admin_trilha_listar`/
  `admin_trilha_salvar`/`admin_trilha_remover`) — `salvar` zera o `tocando` das outras.
- **Owner-only:** aba `trilha` no console usa `perm: 'trilha'` (não grantável, igual a
  `avisos` — o whitelist de permissões é fechado por CHECK).
- **Front:** `initTrilha()` (boot, home) lê as ativas e monta os cards; a `tocando` vem
  primeiro com selo. **`spotifyEmbed()` é a trava de segurança:** converte o link no src
  de embed e **só devolve `open.spotify.com/embed/...`** (URL normal, `/embed`, `/intl-xx`
  ou URI `spotify:`) — qualquer outra coisa vira `null` e NÃO vira `<iframe>` (bloqueia
  host falso, subdomínio-armadilha `open.spotify.com.evil.com`, `javascript:`). Tolerante:
  sem a 0023, a seção fica escondida.
- **Console:** `viewTrilha` (`admin.js`) — form (nome/clima/link/ordem/na-home/tocando) +
  lista com editar/remover. Bloqueia no submit link que não é do Spotify.
- **No ar:** migration aplicada em 10/ago/2026, front na `main`.

### O som de agora (faixa ao vivo do Spotify, na home)

Uma seção **minimalista e centralizada** entre as *features* e o rodapé da home, na paleta
da casa (terracota/paper), **sem card pesado**, dois estados:

- **AO VIVO** (`[data-som-live]`): capa do álbum, selo "tocando agora" (pontinho pulsando),
  nome da faixa (serifado), artista e uma **barrinha de progresso** que anda sozinha. Vem da
  faixa que realmente toca na conta Spotify do Casa.
- **GENTIL** (`[data-som-idle]`): equalizador miúdo, "o som do Casa", título "o que embala a
  casa" e o **link "ouvir no Spotify"** — quando nada está tocando (ou a integração está off).

**Como o ao vivo funciona (built, DESLIGADO por enquanto):**
- **Edge Function `spotify-now-playing`** (deploy com `--no-verify-jwt`, leitura pública):
  troca o `SPOTIFY_REFRESH_TOKEN` por um access token (cacheado 1h na instância), chama
  `GET /me/player/currently-playing` e devolve `{ tocando, nome, artista, album, capa, url,
  progresso_ms, duracao_ms }` ou `{ tocando:false }`. **Não** importa o `_shared/lib.ts` (que
  exige `ASAAS_API_KEY` no topo) — é auto-contida. Cache curto de 10s protege de rate limit.
  Secrets **só na function**: `SPOTIFY_CLIENT_ID`/`SPOTIFY_CLIENT_SECRET`/`SPOTIFY_REFRESH_TOKEN`.
- **Front `initSomDoCasa()`**: com a flag `SOM_AO_VIVO` (hoje `false`) sonda a function a cada
  15s e alterna live↔idle; a barra avança client-side entre os polls; pausa em aba escondida;
  para de sondar se a function some (erro) ou volta `configurado:false`. Capa só de `i.scdn.co`,
  link só de `open.spotify.com` (trava anti-URL-forjada). Link do idle vem do `MARCA.redes`
  (fonte única do rodapé); placeholder `'#'` não abre aba em branco.
- **Pra LIGAR** (a Spotify Web API é **grátis**, não exige Premium pra LER): `npm run
  spotify-token` (OAuth uma vez, pega o refresh token), `npx supabase secrets set` os três
  `SPOTIFY_*`, `npx supabase functions deploy spotify-now-playing --no-verify-jwt`, e virar
  `SOM_AO_VIVO = true` no `app.js`. **Condição prática:** o som do Casa precisa tocar por essa
  conta Spotify (é o que a API enxerga). Passo a passo no cabeçalho de `scripts/spotify-token.mjs`.

---

## Meu cantinho (perfil público do assinante)

Um cartãozinho público e **opt-in** do assinante em **`/gente/{handle}`** — dá rosto à
comunidade sem expor nada sensível. Mostra: apelido (ou 1º nome), foto, plano, "na casa
desde", o "café de sempre" (dos campos do 0014) e os recados que deixou no Mural.
**Ficam SEMPRE de fora:** e-mail, telefone, pontos, endereço, nome real completo.

- **Migration `0024_perfil_publico` (APLICADA em 10/ago/2026):** colunas
  `profiles.perfil_publico` (bool, opt-in) e `profiles.handle` (slug único da URL) + 2 RPCs
  SECURITY DEFINER:
  - `definir_perfil_publico(ativar)` — o dono (`auth.uid()`) liga/desliga; ao ligar gera um
    handle único e estável (slug do apelido/nome, tira acento). **Exige assinante**
    (`tier_slug` não nulo), como o Mural. Granted a `authenticated`.
  - `perfil_publico(handle)` — leitura **pública** (granted a `anon`), devolve um jsonb com
    EXATAMENTE os campos seguros (hand-picked) + os recados do dono; `null` se não existe ou
    não é público. **A exposição NÃO é RLS na `profiles`** (abriria a linha toda) — é este
    payload curado.
- **Rota `/gente/{handle}`:** `gente.html` (registrada no `rollupOptions.input`). URL
  dinâmica servida por **rewrite**: `vercel.json` (`rewrites: /gente/:handle → /gente.html`)
  em prod e o middleware `urlsLimpasNoDev` (regex `/gente/{x}` → `gente.html`) no dev.
- **Front:** `initGentePage()` lê o handle do path, chama `perfil_publico`, monta o cartão
  (café via `cafeFrase`, "desde" via `membroDesde`), escapa tudo; estado vazio gentil se o
  handle não existe/fechou. `/conta/perfil` ganhou a seção **"meu cantinho"**
  (`[data-cantinho]`): toggle liga/desliga (`definir_perfil_publico`), mostra o link + copiar.
  Tudo tolerante à migration pendente (seção some, página cai no vazio).
- **A `0033_perfil_publico_trava` é obrigatória junto:** a RPC é a porta com a régua
  (exige plano, gera handle livre), mas não era a única — a `profiles_update_self` (0002)
  libera UPDATE da **linha inteira** e RLS não restringe coluna, então um PATCH direto
  ligava `perfil_publico` e escolhia `handle` sem nunca ter assinado, e handle é unique
  (dava pra tomar de vez o nome da casa). A 0033 põe uma trigger nas duas colunas, no mesmo
  desenho do `prevent_points_tamper`, e reserva um punhado de handles.
- **A `0036` fecha a régua na leitura:** ligar o cantinho sempre exigiu plano, mas a
  `perfil_publico(handle)` só olhava a flag, então quem assinava, ligava e depois saía do
  plano ficava no ar pra sempre. Agora a leitura pública também pede `tier_slug`. Quem fica
  sem plano **some da vitrine e volta sozinho** ao reassinar: a flag e o handle continuam
  guardados, nada é apagado nem reciclado. O `/conta/perfil` conta isso na cara ("teu
  cantinho tá guardado") em vez de mostrar um link que abriria no estado vazio.
- **No ar:** as três (`0024`, `0033` e `0036`) foram aplicadas em 10/ago/2026 e o front
  está na `main`.

---

## Os dois brunches (voucher com código, `0050`)

O platter brunch do clube e o brunch de aniversário são **a mesma mecânica**, de propósito: a
pessoa resgata na conta, recebe um `CASA-XXXXXX`, mostra no balcão, e o staff dá baixa no
console. Quem trabalha no salão aprende uma coisa e serve as duas.

| | quem tem | quantos | janela | validade do código |
|---|---|---|---|---|
| **platter do mês** | só quem assina (`tier_slug`) | 1 por mês do calendário | o mês inteiro | até o fim do mês, com **piso de 7 dias** |
| **aniversário** | **qualquer pessoa com conta**, plano ou não | 1 por ano | os **7 dias** que começam no dia | até o fim da própria janela |

- **O de aniversário mudou de régua na `0050`.** A `0025` dava o **mês inteiro** e **exigia
  plano**; agora é a semana do aniversário e não pede assinatura. A casa comemora com quem faz
  aniversário, sendo do clube ou não, e a janela curta é o que faz a pessoa **vir**.
- **O do mês não acumula.** Um por mês do calendário (UNIQUE `user+ano+mês`), e o de agosto
  morre em agosto: sem isso dava pra juntar doze e sentar em dezembro. O **piso de 7 dias**
  existe pra quem resgata no dia 30 não ganhar um voucher que vence amanhã (ele pode encostar
  nos primeiros dias do mês seguinte, e tudo bem, aquele mês foi pago).
- **`aniversario_no_ano(nascimento, ano)` existe por causa do 29/02:** `make_date(2027,2,29)`
  **estoura** em vez de devolver nulo, então quem nasceu em ano bissexto veria um erro na cara
  num ano comum. Cai pro 28/02.
- **A janela do aniversário é contada a partir do aniversário MAIS RECENTE**, não do deste ano:
  quem faz 30/dez e entra em 2/jan ainda está dentro dos 7 dias, e o `ano` do brinde continua
  sendo o do aniversário.
- **Tabela nova, não coluna nova.** A chave natural dos dois é diferente (ano vs ano+mês), e
  juntar os dois numa tabela pediria um UNIQUE parcial por tipo mais um `mes` nulo pro
  aniversário. `brunches_mensais` é irmã da `brindes_aniversario`, e **o console junta as duas
  na leitura** (`admin_brunches_listar`, jsonb).
- **Permissão: reusa a página `aniversarios`** do catálogo da 0047 (`.ver`/`.mexer`/`.arrumar`).
  Não é permissão nova: quem confere brunch no balcão confere os dois. A aba passou a se
  chamar **"brunches"** e ganhou um filtro de tipo.
- **O sino ganhou a sexta fonte** (`meu_brunch_mensal`): avisa quem assina e ainda não pegou o
  brunch do mês. E o aviso do aniversário passou a seguir a janela de 7 dias, senão mandaria
  gente vir num dia em que o código já não sai.
- **As funções velhas seguem no ar:** `admin_brindes_listar`, `admin_brinde_usar` e
  `admin_brinde_arrumar` (0025/0046/0047) continuam existindo e servindo só o aniversário. O
  console não as chama mais.

### A data de aniversário se escreve uma vez (`0051`)

Abrir o brunch de aniversário pra **qualquer pessoa com conta** só fecha se a data não for
editável: o UNIQUE `(user_id, ano)` segura um por ANO, mas não segura quem **move a data**
pra dentro da janela toda vez que quer vir. Então:

- **O `/cadastro` passou a pedir o aniversário**, e ele vai no `raw_user_meta_data` →
  `handle_new_user` grava no `profiles`. O parse é **tolerante**: data ilegível, futura ou de
  mais de 120 anos atrás vira **nulo** em vez de derrubar o cadastro. Uma pessoa nova vale
  mais que um campo de mimo.
- **A trigger `prevent_nascimento_tamper`** é a trava de verdade (mesmo desenho do
  `prevent_points_tamper`, porque a `profiles_update_self` libera a linha inteira e RLS não
  restringe coluna). Depois de preenchida, a data não muda por sessão de cliente. **De nulo
  pra uma data ainda passa**, senão as contas criadas antes desta regra nunca poderiam
  preencher. O **owner passa sempre**: é a saída pra um dígito trocado, hoje pelo SQL Editor,
  porque o console não tem campo pra isso.
- **No `/conta/perfil` o campo nasce `readonly`** quando já existe data, e o salvamento
  **nem manda a coluna** nesse caso: se mandasse nulo por qualquer tropeço, a trigger
  derrubaria o salvamento inteiro, levando junto o nome e o telefone que a pessoa quis mudar.
- **O cadastro pelo Google não passa por esse campo** (o fluxo é do provedor). Quem entra por
  ali cai no site sem data e preenche uma vez no perfil, já travado dali em diante. A brecha
  que importava, mudar a data todo mês, está fechada nos dois caminhos.

## Hoje o Casa é teu — brunch de aniversário (Fase 3)

Cumpre a promessa que a 0014 já deixava no ar (`profiles.nascimento`: "no dia tem café
por nossa conta"), num tamanho maior: no **mês do aniversário**, o assinante reserva um
**brunch de aniversário** (pra uma pessoa — o mesmo mimo que a casa já dá hoje). Resgata
no `/conta/perfil`, recebe um **código** `CASA-XXXXXX`, mostra no balcão; o staff confere
e dá baixa no console. **Um por ano.**

- **Perk de assinante**, como o Mural/pontos/cantinho: só resgata quem tem `tier_slug`
  vigente. E só **no mês** do aniversário (janela generosa — dá pra vir num dia de semana).
  O código vale **30 dias** a partir do resgate.
- **Migration `0025_brinde_aniversario` (APLICADA em 10/ago/2026):** tabela
  `brindes_aniversario` (`user_id`, `ano`, `codigo` unique, `valido_ate`, `status`
  ativo|usado, UNIQUE `(user_id, ano)`) com RLS (cada um lê o próprio; staff com
  `resgates` lê todos; **escrita só via RPC**) + 4 RPCs SECURITY DEFINER:
  - `meu_brinde_aniversario()` (authenticated) — só LÊ: devolve o estado pro card
    (`tem_data`, `assinante`, `eh_mes`, `eh_dia`, `ja_resgatou`, `codigo`, `valido_ate`,
    `situacao` ativo|usado|expirado). Fuso `America/Sao_Paulo`.
  - `resgatar_brinde_aniversario()` (authenticated) — reserva o brunch do ano;
    **recomputa todas as travas no banco** (mês, assinatura, duplicidade), lock na própria
    linha + trata `unique_violation` → idempotente por `(user, ano)`.
  - `admin_brindes_listar(busca, status, limite)` e `admin_brinde_usar(id)` — gated por
    **`tem_permissao('resgates')`** (não precisou de permissão nova no whitelist do 0017:
    honrar o brunch no balcão É baixa de recompensa em mãos). `usar` recusa código já usado
    (idempotente) ou vencido, e grava no `audit_log`.
- **Front:** o card `[data-aniversario]` no `/conta/perfil` aparece **só** quando faz
  sentido (é o mês, ou há código vivo): assinante no mês → botão "quero meu brunch"; código
  reservado → a caixa com o código + validade; usado/expirado → recado gentil; sem plano no
  mês → CTA pros planos. No console, a aba **"aniversários"** (`viewAniversarios`, ícone
  `cake`, visível a quem tem `resgates`) lista os brindes com busca (código/nome) + filtros
  (a validar / usados / vencidos) e o botão "brunch entregue". Tudo tolerante à migration
  pendente (a RPC falha → card some, sem ruído). Helper `dataDiaMes` formata datas FUTURAS
  (validade) sem o drift de fuso do `new Date` — o `dataCurta` não serve (devolve "hoje").
- **No ar:** migration aplicada em 10/ago/2026, front na `main`.

---

## A agenda do Casa — encontros (Fase 3)

O Casa se define como *"um café-casa de **encontros**"*, e agora o site tem encontro. A
tabela `events` já existia na `0004_reconcile` (nome, descrição, data, vagas, ativo) e
**nunca fora usada** — a `0026` a acorda: o owner cadastra os próximos encontros no
console, eles aparecem numa seção **"a agenda do Casa"** na home, e o **assinante confirma
presença** ("eu vou"), com uma lotação gentil (as `vagas` que a 0004 já previa).

- **Migration `0026_agenda` (APLICADA em 10/ago/2026):** duas colunas novas em
  `events` (`local`, `updated_at`) + tabela `event_rsvps` (`(event_id, user_id)` PK =
  anti-duplicata, RLS: cada um lê o próprio, owner lê todos; **escrita só via RPC**) + 6
  RPCs SECURITY DEFINER:
  - `agenda_proximos()` — leitura **pública** (anon vê a agenda; só não tem "eu vou"),
    devolve os ativos e futuros (tolera 4h de folga) com `confirmados` (contagem SEM expor
    quem) e `eu_vou`/`lotado` do próprio caller. Granted a `anon`+`authenticated`.
  - `confirmar_presenca(id)` / `cancelar_presenca(id)` (authenticated) — RSVP. Confirmar é
    **perk de assinante** (exige `tier_slug`); recomputa tudo no banco (assinante, evento
    ativo/futuro, lotação) com **lock na linha do evento** (a vaga não estoura); idempotente.
  - `admin_eventos_listar()` / `admin_evento_salvar(...)` / `admin_evento_remover(id)` —
    gated por `is_owner()` (owner-only, `perm:'eventos'` não grantável, igual a avisos/trilha).
- **Front:** `initAgenda()` (boot, home) lê `agenda_proximos` e monta os cards (data via
  `dataEvento`, "eu vou" alterna sem recarregar; deslogado → login e volta; sem-plano → a
  RPC barra com recado gentil). A seção fica escondida sem encontros ou sem a migration. No
  console, a aba **"agenda"** (`viewAgenda`, ícone `calendar-days`, owner-only) tem form
  (nome/data/local/vagas/descrição/na-home) + lista com confirmados, editar e remover.
- **"Quem vai" (`0028_agenda_quem_vai`, aplicada):** a `agenda_proximos` ganhou a coluna
  `vao_publicos` (jsonb) — os **rostinhos** de quem confirmou **E** ligou o perfil público
  (`perfil_publico`), com `handle`/nome de exibição/`avatar_url` (os mesmos campos já
  públicos do `/gente`). Quem não optou nunca aparece, só soma em `confirmados`. O card da
  home mostra até 6 avatares (`avatarBolha`, link pro `/gente/{handle}`, inicial como
  fallback) + um "+N" pro resto. Reescreve só a função de leitura (DROP+CREATE, muda a
  assinatura); nenhuma tabela/permissão nova.
- **"Guarda no teu calendário" (só front, sem migration):** cada card com data marcada
  ganha o link **"guarda no teu calendário"** (`googleCalUrl`), um **link direto pro Google
  Agenda** (`calendar.google.com/calendar/render?action=TEMPLATE&…`) — abre numa aba nova
  com nome/quando/onde/descrição prontos, **sem baixar arquivo** (`.ics`). Monta a URL 100%
  no client a partir dos dados que a `initAgenda` já tem: `text=nome`, `dates` em UTC
  compacto (`YYYYMMDDTHHMMSSZ`, sufixo `Z` → cai certo em qualquer fuso), duração assumida
  de **2h** (os eventos não têm hora de fim), `location = local + endereço do Casa` e
  `details=descricao`. Encontro **sem data** (`em breve`) não mostra o link (não dá pra
  agendar o indefinido). Ícone `calendar-plus`.
- **No ar:** as duas (`0026` e `0028`) foram aplicadas em 10/ago/2026 e o front está na
  `main`.

---

## Faz teu evento aqui (/eventos) — o pedido vira lead e vai pro WhatsApp

O irmão comercial da agenda, e **não se confunde com ela**: a `/agenda` é dos encontros
que a **casa** promove; a `/eventos` é de quem quer usar a casa pro evento **dele**
(aniversário, reunião, workshop, chá, ensaio, lançamento). Até aqui esse pedido só tinha
um caminho: achar o telefone no rodapé e começar a conversa do zero, sem dizer quando, pra
quantos nem do quê.

- **A página** (`eventos.html`, no `rollupOptions.input`): abertura, o carrossel "a casa
  por dentro", seis cartões de tipo de evento, o formulário e "o que acontece depois".
  O **carrossel vem logo depois da abertura** de propósito: quem pensa em fazer um evento
  decide com os olhos, e ler seis cartões de texto antes de ver a casa é pedir fé. Ele
  reusa o `setupCarousel` pelo `data-carousel="cards"` (mesmo contrato do `/colab`) com as
  seis fotos reais que já estão no `src/assets/fotos`, e o cartão dele (`.ev-slide`) põe a
  foto em cima, na largura toda, em vez da faixa lateral estreita do `/colab`, porque aqui
  a foto é o argumento. Campos do formulário: nome e whatsapp
  (obrigatórios), tipo (select), data, quantas pessoas, e-mail e um "conta um pouco"
  (todos opcionais) — pedir pouco é o ponto, o resto se acerta na conversa.
- **`initEventosPage()` faz UMA coisa: grava o pedido** (RPC `registrar_lead_evento`).
  Nada de abrir o WhatsApp. **O redirecionamento automático saiu em 20/ago/2026, a pedido:**
  a casa não tem um WhatsApp só pra eventos, então jogar quem acabou de preencher numa
  conversa genérica confundia mais do que ajudava — a pessoa já tinha dito tudo no
  formulário e era mandada a dizer tudo de novo. O pedido vai pro console e o aviso toca no
  Telegram da equipe (ver "O pedido toca o sino da equipe"); quem abre a conversa é a casa,
  pelo botão que já vem na mensagem do Telegram. O botão da página deixou de ser "chamar a
  gente no WhatsApp" e virou **"enviar meu pedido"**.
  > **A INVERSÃO QUE ISSO CAUSA, e que vale entender antes de mexer aqui:** enquanto o
  > WhatsApp era o canal, o banco era a rede de segurança, e por isso a função engolia erro
  > da RPC em silêncio ("o banco nunca barra a pessoa"). Agora **o banco é o caminho
  > inteiro**, então falhar ali não é contratempo, é o pedido perdido sem ninguém saber. O
  > caminho de erro parou de ser silencioso: os campos ficam preenchidos (dá pra tentar de
  > novo sem redigitar) e a tela mostra o telefone e o e-mail da casa. É um `tel:`, uma
  > ligação, **não** o `wa.me` — reabrir o link do WhatsApp ali traria de volta justamente
  > a confusão que se quis tirar.
  > **E o pedido REPETIDO diz que é repetido (0055):** o anti-flood de 30s da 0040
  > não cria linha nova e respondia igualzinho a um pedido que entrou. Com o
  > WhatsApp no meio isso era invisível, porque a conversa levava a versão certa;
  > sem ele, quem viu um erro no recado, corrigiu e reenviou dentro da janela lia
  > "anotado" e ia embora achando que a casa tinha a correção. A RPC passou a
  > devolver `repetido: true`, a tela conta isso ("esse pedido já tá com a gente,
  > se tu mudou alguma coisa espera um minutinho e manda de novo") e **não limpa
  > o formulário**, pra o reenvio não pedir tudo de novo.
  > **E no sucesso o formulário limpa:** sem a aba do WhatsApp abrindo, era a única coisa na
  > tela dizendo "foi", senão o estado de sucesso fica idêntico ao de antes de apertar.
- **Migration `0040_leads_evento` (APLICADA em 13/ago/2026):** tabela `leads_evento`
  **deny-by-default** (RLS ligada e **nenhuma policy** — o client não lê nem escreve
  direto). Diferente da `0031`, que nasceu com policy de INSERT pro client e precisou da
  `0034` pra tirar; aqui já nasce pela porta certa. Nome e telefone são dado **pessoal**,
  então isto **não** é da turma dos "benignos" (favoritos, desejos) que o client escreve
  direto. Três RPCs SECURITY DEFINER: `registrar_lead_evento(...)` (granted a **anon**,
  porque quem pede evento raramente tem conta; valida tudo no corpo e tem **anti-flood de
  30s pelo mesmo contato**, senão um endpoint público de escrita vira alvo),
  `admin_leads_evento(busca, status, limite)` e `admin_lead_evento_status(id, status)`,
  as duas gated por `tem_permissao('relatorios')` — a mesma porta dos outros relatórios de
  interesse, então **não precisou de permissão nova** (o whitelist é fechado por CHECK na
  0017 e permissão nova pediria outra migration).
- **Console:** aba **"eventos"** (`viewLeadsEventos`, ícone `party-popper`, quem tem
  `relatorios`) com busca, filtros (a responder / já falei / arquivados) e o telefone como
  **link de WhatsApp**, pra quem atende abrir a conversa dali mesmo. O botão "já falei" é
  o que tira da fila: lista de pedidos sem onde riscar o que já foi atendido é pilha que
  só cresce.
- **No ar:** migration aplicada em 13/ago/2026, front na `main`. Naquela leva não houve
  secret nem Edge Function nova (o formulário falava com o banco pela RPC e com o WhatsApp
  por link). **A `0052` mudou isso** — ver logo abaixo.

### O pedido toca o sino da equipe (Telegram + uma leitura do Gemini, `0052`)

A `0040` resolveu metade do problema: o pedido **sobrevive ao canal**. Ficou faltando a
outra metade, que é **alguém saber que ele chegou**. Até aqui o lead caía na tabela e
esperava alguém abrir o console e lembrar de olhar a aba "eventos", e quem pede um evento
está pedindo pra três casas ao mesmo tempo: responder no dia seguinte é responder depois de
a pessoa já ter fechado com outro lugar.

- **O gatilho é o INSERT, e isso é a decisão central.** Nada disso mora no front. Chamar do
  navegador exigiria a chave do Telegram/Gemini no bundle (proibido, ver "Segurança") e o
  aviso morreria junto com a aba de quem preenche e sai correndo, que é exatamente o lead
  que não dá pra perder. Uma trigger `after insert` na `leads_evento` chama a Edge Function
  pelo **`pg_net`**, que enfileira a requisição e devolve na hora (a transação não espera o
  Telegram responder) — e como a fila é uma tabela, um rollback leva o aviso junto: ninguém
  é avisado de um pedido que não existe.
- **O anti-flood da 0040 virou o freio do sino de graça:** pedido repetido sem querer não
  vira linha nova, então também não vira ping repetido.
- **A trigger inteira roda dentro de um `exception when others`.** É a peça mais importante
  do arquivo: extensão faltando, segredo não cadastrado ou Telegram fora do ar viram um
  `warning` no log do Postgres e nada mais. O lead entra do mesmo jeito. É a mesma regra que
  a página já seguia ("o banco nunca barra a pessoa"), um degrau abaixo. **Perder um aviso é
  ruim; perder o lead é pior.**
- **Os segredos moram no Vault, não neste repo e não numa tabela de config em texto.** A
  migration sobe sem saber a URL nem o token (`casa_aviso_lead_url` / `casa_aviso_lead_token`,
  lidos pela `aviso_lead_config()`); enquanto os dois não forem cadastrados, a trigger não
  faz nada, nem erro. Aplicar a migration antes de configurar é seguro.
- **Edge Function `avisar-lead-evento`** (deploy com `--no-verify-jwt`): a porta é o token
  compartilhado no header `x-casa-token` comparado em **tempo constante** com
  `LEAD_WEBHOOK_TOKEN` — mesmo desenho do `asaas-webhook` (não é HMAC, e não precisa ser, os
  dois lados são nossos). **Não importa o `_shared/lib.ts`**, que exige `ASAAS_API_KEY` no
  topo; é auto-contida, igual à `spotify-now-playing`.
- **O Gemini é conforto, não requisito.** Ele devolve resumo em uma frase, urgência e uma
  sugestão de primeira resposta no tom da casa (saída estruturada por `responseSchema`, então
  não há parsing criativo). Sem chave, com quota estourada ou com timeout, **o aviso sai do
  mesmo jeito**, só sem o bloco de leitura. Modelo default `gemini-2.5-flash-lite`, trocável
  pelo secret `GEMINI_MODEL` — o Google renomeia modelo mais rápido do que a gente faz deploy.
  Custo real no volume de um café: o tier gratuito cobre, e o Telegram Bot API é grátis.
- **O recado da pessoa é entrada não confiável em dois lugares, e os dois estão tratados:**
  vai pro Gemini **delimitado** (`<<<RECADO … RECADO>>>`) com a instrução explícita de que
  ali é pedido de cliente e nunca ordem pro modelo; e vai pro Telegram com **escape de HTML
  em todo valor de fora**, inclusive no texto que o Gemini devolveu (o `parse_mode` é HTML, e
  um `<` solto num recado quebraria a mensagem inteira).
- **A mensagem tem botão de responder.** Responder é a única coisa que se faz com esse aviso,
  então ela fica a um toque: um `inline_keyboard` com o link do WhatsApp da pessoa (o telefone
  é guardado formatado, então vira dígitos com o DDI 55) e, se o `SITE_URL` estiver setado, um
  atalho pro `/admin#eventos`.
- **Teto de 20 avisos por hora.** A `registrar_lead_evento` é aberta a `anon` e o anti-flood
  dela é **por contato**, então quem variar o telefone gera pedido à vontade. Isso já era
  verdade antes, só que o estrago parava na tabela; com o sino ligado, viraria o celular de
  quem atende tocando a noite inteira. Acima do teto **o pedido entra normalmente e aparece
  no console**, só não vira ping.
- **O corte da mensagem é por CAMPO, nunca na mensagem montada.** O `parse_mode`
  é HTML e o `esc` transforma um "&" em "&amp;", então cortar os 4096 caracteres
  do Telegram na mensagem pronta partia uma entidade no meio e, pior, deixava um
  `<blockquote>` sem fechar: o Telegram recusa com 400, a function devolve 500, o
  `pg_net` não repete, e o lead fica salvo com o sino mudo. Um recado de 600 "&"
  chegava a 10 mil caracteres e caía nisso. Agora cada valor de fora entra
  aparado pelo `cortarEscapado` (recado 1200, resumo 500, resposta 900), com a
  soma provada abaixo do teto no pior caso, e as tags são fechadas por fora do
  corte.
- **Rastro:** a coluna `leads_evento.aviso_em` é carimbada pela function depois que o Telegram
  aceita a mensagem, pra responder "o sino tocou?" sem cavar log. O carimbo é best-effort: se
  não gravar, o aviso já chegou, e devolver erro ali faria parecer que não.
- **Ligar pede config, não código:** bot no @BotFather, `chat_id` do grupo, chave do AI Studio,
  quatro secrets e os dois segredos do Vault. Passo a passo (com o que olhar quando não chega)
  no apêndice do `supabase/functions/README.md`.

---

## Teus favoritos no cardápio (Fase 3)

O `/cardapio` era uma lista bonita mas estática. Agora quem está logado **favorita**
um item (um coraçãozinho) e ganha um bloco **"teus favoritos"** no topo, pra reencontrar
o de sempre num toque. De quebra, o Casa vê no console **o que a casa mais ama**.

- **Aberto a qualquer pessoa logada** (não é perk de assinante) — quanto mais gente marca,
  mais sinal pra casa. O cardápio é HTML curado, então o item é identificado por um `slug`
  **derivado do nome** (`slugify`, no client) — nada de tabela de menu. **Nome que se
  repete entre seções vai qualificado pelo título da seção** (`bagel-classico`,
  `croissant-classico`, `croissant-presunto-queijo`, `sanduiches-presunto-queijo`,
  `sanduiches-carne-de-panela`, `adicionais-carne-de-panela`): o slug saía só do nome, os
  seis colidiam de dois em dois e o segundo item de cada dupla ficava **sem coração
  nenhum** (o `porSlug.has(slug)` pulava). No bloco "teus favoritos", esses chips levam a
  seção entre parênteses, senão viriam dois idênticos. São os mesmos slugs dos critérios
  da 0038.
- **Migration `0027_cardapio_favoritos` (APLICADA em 10/ago/2026):** tabela
  `cardapio_favoritos` (`(user_id, item_slug)` PK, `item_nome` snapshot pro console,
  `user_id` default `auth.uid()`). Favorito é dado **benigno** (não entra na lista de
  sensíveis do security-check): a **escrita é direta pelo client via RLS**, sempre travada
  em `auth.uid()` (policies select/insert/delete own) — sem Edge Function. O console lê o
  agregado por `admin_cardapio_favoritos()` (SECURITY DEFINER, gated por
  `tem_permissao('relatorios')`), que conta por slug e mostra o nome **mais frequente**
  (resiliente a um snapshot adulterado; o console escapa tudo).
- **Front:** `initCardapioFavoritos()` (boot) só age logado: deriva o slug de cada
  `.menu-item` pelo nome, injeta um coração em cada um, lê os favoritos do usuário e monta o
  bloco de chips (cada chip rola até o item com um flash). Toggle otimista (insert/delete),
  desfaz se o servidor recusar; `23505` (já favoritado) conta como sucesso. Tolerante: sem
  sessão ou sem a migration, nenhum coração aparece. No console, a aba **"favoritos"**
  (`viewFavoritos`, ícone `heart`, quem tem `relatorios`) lista o ranking com barrinha.
- **No ar:** migration aplicada em 10/ago/2026, front na `main`.

---

## Ficou pra depois (lista de desejos da loja) (Fase 3)

O irmão do "teus favoritos" do cardápio, agora na loja: um **coração em cada produto**
(catálogo e página de produto) que **salva pra depois** sem botar no carrinho. Uma tirinha
**"ficou pra depois"** no topo da `/loja` e um **espelho no `/conta/perfil`** reúnem o que a
pessoa guardou, tirando o atrito do "gostei mas agora não". De quebra, o Casa vê no console
**o que a casa mais quer** (demanda represada por produto).

- **Aberto a qualquer pessoa logada** (não é perk de assinante). O catálogo é mock no client
  (`PRODUTOS`), então o produto é identificado pelo **mesmo `slug` da URL `/produto`**; o
  `produto_nome` é snapshot pro console.
- **Migration `0029_loja_desejos` (APLICADA em 10/ago/2026):** tabela `loja_desejos`
  (`(user_id, produto_slug)` PK, `produto_nome` snapshot, `user_id` default `auth.uid()`).
  Desejo é dado **benigno** (fora da lista de sensíveis do security-check): **escrita direta
  pelo client via RLS**, sempre travada em `auth.uid()` (policies select/insert/delete own),
  sem Edge Function. O console lê o agregado por `admin_loja_desejos()` (SECURITY DEFINER,
  `tem_permissao('relatorios')`), que conta por slug e mostra o nome **mais frequente**
  (resiliente a snapshot adulterado; o console escapa tudo).
- **Front:** `initLojaDesejos()` só age logado, em três superfícies (tolerante sem a 0029,
  sem sessão → nada aparece): (1) injeta um coração sobre a foto de cada card do catálogo
  (`.prod-fav`, via `[data-produto][data-slug]`); (2) revela o botão "guardar pra depois" na
  página de produto (`[data-desejo-produto]`, `hidden` até logar); (3) monta a tirinha de
  chips (link pro produto + `×` pra tirar) nas seções `[data-loja-desejos]` (topo da `/loja`)
  e `[data-desejos-perfil]` (perfil). Todos os corações de um mesmo slug andam juntos; toggle
  **otimista** (insert/delete, `23505` = já guardado = sucesso), desfaz se o servidor recusar.
  A chamada do boot não pega o perfil (montado pós-guard), então `initPerfilPage` **religa**
  `initLojaDesejos()` no fim. No console, a aba **"desejos"** (`viewDesejos`, ícone `bookmark`,
  quem tem `relatorios`) lista o ranking com barrinha, igual aos favoritos.
- **No ar:** migration aplicada em 10/ago/2026, front na `main`.

---

## Volta pra vitrine (avisa quando o produto voltar) (Fase 3)

Puxa o gancho da lista de desejos: produto **esgotado** (`disponivel: false` no mock
`PRODUTOS`) não fica mudo, ganha um selo **"esgotado"** e o botão **"me avisa quando
voltar"**. Quando a casa repõe (flip pra disponível), o aviso chega no **sino de
notificações do header** ("voltou pra vitrine"), visível em qualquer página. Pro Casa, o
console mostra **quantas pessoas esperam cada produto** — o sinal mais forte pra reposição.

- **Disponibilidade no mock:** `PRODUTOS[].disponivel` (ausente = disponível; só marca-se
  `false`). Hoje **Torra Vale dos Sinos** e **Caneca de autor** estão esgotados.
- **Migration `0030_avisos_reposicao` (APLICADA em 10/ago/2026):** tabela
  `avisos_reposicao` (mesma forma do `loja_desejos`: PK `(user_id, produto_slug)`,
  `produto_nome` snapshot, `user_id` default `auth.uid()`). Dado **benigno** (fora da lista
  de sensíveis): **escrita direta pelo client via RLS** (select/insert/delete own), sem Edge
  Function. Agregado do console por `admin_avisos_reposicao()` (SECURITY DEFINER,
  `tem_permissao('relatorios')`, conta por slug com o nome mais frequente).
- **Front — botões "me avisa":** o esgotado é 100% do mock (client), então `cardProdutoHTML`
  e `initProductPage` já renderizam o selo + "me avisa" sem depender de sessão/banco (na
  página de produto, esgotado troca quantidade/carrinho pela nota + botão). `initReposicao()`
  liga só os botões: deslogado → manda pro login; logado → carrega os avisos, pinta o estado
  (toggle otimista, `23505` = já pediu = sucesso); migration pendente → botão inerte ("aviso
  em breve"). **Não há mais tirinha inline** — quem mostra o "voltou" é o sino.
- **Front — o "voltou" é UMA das fontes do sino de notificações** (`initNotificacoes`,
  header, toda página — ver **"O Casa te avisa"** abaixo). Filtra os `avisos_reposicao` cujo
  produto **voltou** (existe e está disponível agora); "já vi" **apaga a linha** do banco
  (best-effort, RLS-direct).
- **Console:** aba **"esperando"** (`viewReposicao`, ícone `bell-ring`, quem tem `relatorios`)
  lista o ranking de quem espera cada produto, com barrinha.
- **No ar:** migration aplicada em 10/ago/2026, front na `main`.

---

## O Casa te avisa (central de notificações no header)

O sino do header deixou de servir só o "voltou pra vitrine" e virou uma **central** que
junta, num painel só, os avisos que antes viviam espalhados pelo site. **Cinco fontes**,
todas **só-leitura** de tabelas que já existem, cada uma lendo apenas o registro do
**próprio** usuário (RLS own-record) — **nenhuma tabela, secret ou Edge Function nova**.

- **As fontes** (`initNotificacoes`, boot, toda página — cada uma é tolerante: erro /
  migration pendente → `[]`, some sem quebrar):
  1. **voltou pra vitrine** — `avisos_reposicao` (0030) cujo produto está disponível agora.
     Ícone `bell-ring`. Dispensa **apagando a linha** (RLS-direct).
  2. **indicação premiada** — `referrals` (0021) com `referrer_id = eu` e `status='premiado'`.
     Ícone `users`, leva pro `/conta/perfil`.
  3. **presente resgatado** — `gift_subscriptions` (0019) com `comprador_id = eu` e
     `status='resgatado'`. Ícone `gift`, leva pro `/conta/perfil`.
  4. **brunch de aniversário** — RPC `meu_brinde_aniversario` (0025) quando `assinante &&
     eh_mes && !ja_resgatou`. Ícone `cake`, leva pro `/conta/perfil`.
  5. **encontro chegando** — RPC `agenda_proximos` (0026) com `eu_vou` e `data` numa janela
     de **48h** (tolera 4h já começado). Ícone `calendar-days`, sub via `dataEvento`.
- **Dispensar ("já vi"):** o **voltou** apaga a linha do banco; as **derivadas** (não há linha
  pra apagar) guardam o `id` no **localStorage** (`casa_notif_lidas`, helpers `notifLidas()`/
  `marcarNotifLida()`, mesmo padrão do `renderAvisoBar`). O badge tampa em **"9+"**.
- **Markup/estilo:** cada item ganhou uma **coluna de ícone** (`.notif-item-ico` redondo +
  `.notif-item-corpo` com tag/nome/sub). No **mobile** o painel é `position: fixed` com o
  `top` medido do header ao abrir (respeita a tarja de recado). Mecânica de abrir/fechar
  (clique-fora/Esc/scale-opacity) reusa o padrão do painel do usuário.
- **Alinhamento na barra:** o alvo de toque do `.hdr-icon` é 38px, mas o desenho tem
  24px, e essa folga somava ao `gap: 16px` da `.header-right`: o sino ficava a 26px do
  avatar (que tem 2px de folga), parecendo fora da fila. A caixa recua com
  `margin-inline: -5px`, então o dedo continua com os 38px e o espaço que se VÊ é o mesmo
  dos vizinhos.
- **Quando o sino aparece:** **logado, sempre** — mesmo sem aviso nenhum. Ele é montado e
  fica clicável ANTES de as cinco fontes responderem (senão a barra pulava quando as
  consultas voltassem), e sem nada pendente fica sem badge, com o painel dizendo "por aqui
  tá calmo" (`.notif-vazio`). Antes ele só existia quando havia item, então quem entrava
  numa conta em dia nunca via o ícone e não aprendia que ele existe. **Deslogado →
  escondido**, isso não muda.
- **Só-leitura, zero confiança nova:** o sino nunca **credita** nada, só **reflete** estado
  que os webhooks/RPCs já produziram.
- **No ar:** as cinco fontes (0019/0021/0025/0026/0030) estão aplicadas e o front está na
  `main`, então o painel serve as cinco.

---

## A tua área (menu da conta)

As portas da área logada, nos quatro lugares em que elas aparecem. **Fonte única:
`CONTA_LINKS` no `app.js`** (href, ícone, rótulo e um rótulo curto pras tirinhas; hoje são
cinco: tua conta, **teu clube**, teus pontos, tuas conquistas, teus pedidos) —
a fila estava escrita duas vezes e já tinha divergido, então página nova em
`/conta/` era lembrar de três lugares. Tratamento em **"tu"** (tua conta, teus
pontos, tuas conquistas, teus pedidos, tua assinatura): o menu era o único canto
do site que dizia "meu perfil" enquanto a página dizia "teus dados".

- **Painel do avatar (desktop)** — anel de progresso (pontos → próxima recompensa),
  saldo em count-up, emblemas e a fila do `CONTA_LINKS`. **Recarrega a cada
  abertura** (o conteúdo antigo fica na tela enquanto a leitura nova não chega, e
  um contador `userPanelPedido` descarta resposta atrasada): antes um
  `carregado=true` montava uma vez só, e quem resgatava um mimo seguia vendo o
  saldo velho pelo resto da navegação. Uma rodada só de leituras (`Promise.all`
  com `getProfile` + tiers/rewards/achievements), não três em fila.
- **`updateAuthUI` não re-renderiza à toa:** o slot guarda o `dataset.uid` e a
  função sai cedo quando a conta montada é a mesma. O `onAuthStateChange` dispara
  em `TOKEN_REFRESHED` e no `SIGNED_IN` de quando a aba volta ao foco, e reescrever
  o slot ali fechava o painel aberto na cara da pessoa.
- **Menu mobile** — era a versão pobre do painel: sem plano, sem emblema e **sem
  porta nenhuma pra assinatura ou pros planos**, no aparelho onde a maioria está.
  Agora abre com um cartão (foto, nome, plano, saldo) que também é atalho pro
  perfil, traz a mesma fila e fecha com a porta do clube. Plano e convite chegam
  pelo `hydrateAuthHeader`, que já ia ao banco pelo saldo.
- **Atalho no header mobile** (`[data-conta-mob]`) — a bolinha do avatar ao lado do
  sino, só pra quem entrou. Sem ela, chegar na própria conta pelo celular era abrir
  o hambúrguer e rolar até depois da navegação inteira (a tab bar não tem item de
  conta, e não vai ter: ela conta a frase do site, não a da pessoa).
- **Tirinha entre as páginas da conta** (`renderContaNav`, boot) — as quatro
  páginas de `/conta/` não se falavam, e o `/conta/pedidos` não era linkado de
  lugar nenhum fora do menu. Mesmo desenho da tirinha do `/cardapio` (`.cnav-*`,
  grudada no topo, `aria-current` na atual); entra antes da `<section>` da página
  pra a faixa ir de ponta a ponta. Some sozinha fora de `/conta/`.
- **Sem `role="menu"`** no painel da conta nem no do sino: os filhos são links, e
  menu de verdade exige `menuitem` em cada um e navegação por setas — sem isso o
  leitor de tela anunciava um menu vazio. Os dois são disclosure (`aria-expanded` +
  `aria-controls`) e usam **`inert`** enquanto fechados, o que também fecha a
  janelinha de 200ms da transição de saída em que os links seguiam focáveis. Os
  emblemas ganharam `aria-label` (o `title` sozinho não existe em toque, então a
  dica de "como desbloquear" da 0010 nunca chegava ao celular).
- **Honestidade do clube:** sem plano e com saldo zero, o painel (e o "quase lá" da
  `/conta/pontos`) não dizem mais "faltam X pontos pro teu primeiro agrado" —
  pontuar é exclusivo de assinante, então aquela conta nunca ia andar. No lugar,
  contam de onde vêm os pontos e abrem a porta dos planos. Resgatar **não** exige
  plano, então quem tem saldo segue vendo a barrinha normal.
- **Barra "perfil completo" some aos 100%:** ela existe pra pedir o que falta; com tudo
  preenchido virava um troféu no topo da página com cara de aviso pendente que não dá pra
  resolver. A `.pf-prog` recebe `hidden` quando a conta bate 100% (o texto é atualizado
  antes, pra ela voltar coerente se a pessoa apagar um campo). Com os campos todos cheios
  e só o **e-mail por confirmar**, o recado deixa de ser "tá tudo preenchido" e passa a
  dizer que falta confirmar o e-mail, senão a página se contradizia com a barra em 94%.
- **"baixar meus dados" sai em PDF, não em JSON:** o direito à cópia dos dados (LGPD) era
  atendido com um `.json` que ninguém que não é programador consegue ler. Agora a
  `abrirMeusDadosPdf` monta uma **folha formatada** (conta, café, endereço, plano e extrato
  de pontos, com os rótulos que a pessoa escolheu na tela, não o valor cru do banco) numa
  aba nova, com um botão "salvar em PDF" que chama a impressão do navegador. **Sem
  biblioteca no bundle e sem mandar dado pessoal pra lugar nenhum**: a folha é montada no
  aparelho da pessoa. Pop-up bloqueado cai num iframe escondido que imprime direto.
- **`/conta/perfil`:** a "gerenciar assinatura" **nasce no template** logo depois da
  linha de resumo (era movida por JS depois do render), com `id="assinatura"` — é o
  destino do "tua assinatura" do menu, e a `initPerfilPage` faz o pulo na mão,
  porque a âncora nativa não pega numa página montada depois do guard de auth. A
  página ganhou um **índice de seções** (montado das `[data-section]` visíveis, some
  seção nova entra sozinha) e a barra "perfil completo" passou a mostrar **o que
  falta em chips que levam ao campo**. Na célula "teu plano", quem não assina vê
  "ver os planos" com cara de botão e o "tem um presente?" discreto — estava ao
  contrário, e o caso raro ganhava do principal.

---

## O teu de sempre (cartão pessoal na home) — DESATIVADO

> **DESATIVADO em 04/ago/2026** (a pedido): a chamada `initTeuDeSempre()` está comentada
> no bootstrap, então o cartão **não renderiza**. O visual e a posição vão ser repensados
> pra não competir com o hero da home. A função e a seção `[data-teu-de-sempre]` (que fica
> `hidden`) seguem no código, é só descomentar a linha do boot pra religar.

Um cartãozinho no **topo da home**, só pra **quem está logado**, que junta num olhar o
que a pessoa já tem espalhado pelo site, um atalho afetivo pro dia a dia. **Só-leitura**,
**sem migration, sem secret, sem Edge Function** (reusa tabelas/RPCs que já existem).

- **O que mostra** (`initTeuDeSempre`, boot, só age com `[data-teu-de-sempre]` + logado):
  uma saudação pela hora local com o 1º nome do `profile` e até três blocos:
  1. **plano + pontos** — `profile.tier_slug` (nome via `tiers`) + `points_balance`, leva
     pro `/conta/pontos`. **Sem plano** → um convite gentil "vem fazer parte" pro `/planos`.
  2. **próximo encontro que confirmou** — `agenda_proximos` (0026) filtrando `eu_vou` e
     pegando o mais próximo ainda por vir; leva pra `#a-agenda` (a seção da agenda ganhou
     esse `id` na home). Sub via `dataEvento`.
  3. **teus favoritos do cardápio** — `cardapio_favoritos` (0027), até 4 chips (link pro
     `/cardapio`) + "+N".
- **Tolerante:** cada fonte é isolada (erro/migration pendente → aquela parte some); o
  cartão só depende do `profiles` (tabela base). Deslogado → seção fica `hidden`. Nada de
  escrita. Estilo `.tds-*` no `styles.css` (grid `auto-fit`, empilha no mobile).
- **No ar:** nada de banco a fazer; as migrations 0026/0027, que dão conteúdo às partes 2
  e 3, já estão aplicadas. O cartão segue desativado no boot, por decisão de visual.

---

## Como chegar (/o-casa)

O bloco de localização do `/o-casa` já tinha o **mapa** (embed do Google, que geocoda o
negócio pelo nome+endereço). Faltava a **ação de chegar**: `initComoChegar()` preenche
`[data-como-chegar]` com três botões, a partir do `MARCA.contato.endereco` (fonte única):

- **"traçar rota"** → Google Maps directions (`maps/dir/?api=1&destination=<nome+endereço>`).
- **"abrir no Waze"** → `waze.com/ul?q=<nome+endereço>&navigate=yes` (Waze é muito usado no RS).
- **"copiar endereço"** → `navigator.clipboard` com feedback ("copiado"); fallback gentil
  ("copia na mão") se o clipboard estiver bloqueado.

Front puro, **sem chave/API paga, sem migration**: as URLs de rota levam o endereço por
texto e o app de mapa geocoda o lugar certo. O endereço vive só no `MARCA` (mesmo do rodapé).

---

## Privacidade, termos e a lista de espera (rodapé)

Três coisas que faltavam pro site poder ir ao ar: os dois documentos legais e um jeito
de quem só está de passagem deixar contato.

- **`/privacidade` e `/termos`** (`privacidade.html`/`termos.html`, no `rollupOptions.input`):
  texto no tom da casa, mas valendo de verdade. A privacidade cobre o que a gente guarda
  (por tela: cadastro, perfil, compra, clube, sessões, lista de espera), por quê, com quem
  divide (Supabase, Asaas, Vercel, e os embeds de Google Maps e Spotify), o que fica no
  localStorage, prazos e os direitos do art. 18 da LGPD, apontando pro que a pessoa já
  resolve sozinha no `/conta/perfil`. Os termos cobrem conta, assinatura (pausar, retomar,
  upgrade proporcional, downgrade agendado, presente), loja (arrependimento de 7 dias e
  prazos do CDC), pontos, indicação e Mural. Linkados no **rodapé** (`.ft-legal`, toda
  página) e no `/cadastro`, logo abaixo do botão de criar conta.
  > **Razão social e CNPJ já entraram** (Casa Coffee Colab Ltda, 58.138.120/0001-30, em
  > 12/ago/2026). **TODO (humano, antes do go-live):** fechar o **prazo real de retirada e
  > entrega** nos termos e atualizar a **data** de "última atualização" nos dois arquivos
  > (há comentário `TODO` no lugar exato).
- **Lista de espera** (`initListaEspera`, campinho no rodapé): quem não vai criar conta
  hoje deixa só o e-mail ("avisa quando a loja abrir de vez"). Grava na tabela
  `lista_espera` (**migrations 0031 + 0034**), que o client **não toca
  direto**: nem lê (nenhuma policy de select) nem escreve (a 0034 tira a policy de
  INSERT). Quem escreve é a RPC `entrar_na_lista_espera(email, origem)`, quem lê é o
  console, pela `admin_lista_espera()` (`tem_permissao('relatorios')`), na aba **"lista
  de espera"** (`viewListaEspera`, ícone `mail`). O `on conflict do nothing` mora
  **dentro** da RPC e a resposta é a mesma pra e-mail novo e repetido, então o
  formulário não vira sonda de "quem já está na lista".
  > **Por que não é mais INSERT direto:** antes quem garantia a resposta igual era o
  > `ignoreDuplicates` do `app.js`, que é só um header do client. Chamando a tabela
  > sem ele, o PostgREST devolvia 409 (`23505`) pra e-mail já cadastrado e 201 pra
  > novo — com a anon key, sem conta nenhuma, dava pra varrer uma lista de endereços
  > e descobrir quem tinha se inscrito. Promessa de privacidade não pode depender de
  > como o client resolve pedir.

  Sem `supabase` configurado o campo nem aparece; com as migrations pendentes, a
  mensagem é honesta (não finge que guardou) e oferece o e-mail da casa.

---

## Os rastros (onde a pessoa largou o site)

O console sabia tudo sobre o que a casa **vende** e nada sobre o que a pessoa
**faz** antes de comprar (ou de desistir). Dava pra ver o pedido pago e o mimo
resgatado; não dava pra responder as três perguntas que a casa faz quando olha o
site: em que tela a pessoa estava quando fechou a aba, que seção ninguém toca, e
quanta gente encheu o carrinho e foi embora. A aba **rastros**
(`/admin#rastros`, `perm: 'rastros.ver'`) responde as três.

- **A "vista" de seção é a metade que faz a pergunta ter resposta.** Contar só
  clique diz qual seção é quente; não diz qual é **fria**, porque seção sem
  clique não gera linha nenhuma e **some** do relatório. Com a vista (a seção
  ficou meio segundo na tela de alguém), "todo mundo passa e ninguém toca" e
  "ninguém chega até lá" deixam de ser a mesma ausência, e são problemas
  opostos. A tela chama as duas colunas de **olhos** e **dedos**, e marca como
  fria a seção com 20 olhos ou mais e menos de 5% de toque.
- **O nome da seção sai do próprio HTML** (`rastroSecao`): sobe até o container
  mais próximo e usa o `data-rastro-secao` se a casa escreveu um, senão o
  `aria-labelledby`, senão o primeiro título **que pertence àquela seção e não a
  um card de dentro dela**. Sem essa última régua, a grade da `/loja` se
  chamava "Café em grão · Alma do Casa · 250g" (o primeiro produto). Seção nova
  no site já aparece no relatório sem tocar no JS; seção que nasce **sem título
  nenhum** aparece como "sem título", e o conserto é escrever
  `data-rastro-secao` nela (foi o que fizeram a agenda e os quatro atalhos da
  home, e a vitrine da `/loja`).
- **O `<footer>` do drawer do carrinho fica FORA da conta de seção.** Sem isso,
  "finalizar compra", que é o clique mais importante da loja, saía atribuído ao
  **rodapé do site**. Pulando ele, o `closest` sobe até o `<aside aria-label="Teu
  carrinho">` e a saída lê o que tem que ler: `/produto?slug=… · Teu carrinho ·
  finalizar compra`.
- **A visita é uma ABA ABERTA, não uma pessoa.** O id nasce no `sessionStorage`
  e morre quando a aba fecha, então ninguém é seguido de um dia pro outro e o
  mesmo celular voltando amanhã conta como visita nova. Pro que a casa quer
  saber (onde ESTA navegação terminou), a aba é a unidade certa, e é a escolha
  mais privada das disponíveis. Quem está logado é reconhecido pelo **banco**,
  por `auth.uid()`: a 0053 **ignora** um `user_id` que venha do corpo da
  chamada, senão qualquer um carimbaria a visita dele com o id de outra pessoa.
- **Os eventos vão em LOTE, e o último lote sai no `pagehide`.** O site é
  multi-página, então uma requisição por clique seria uma dúzia de viagens por
  visita, e a última, a mais importante, sairia no meio da página sendo
  destruída. O envio usa `fetch(..., { keepalive: true })` (com `sendBeacon` de
  reserva): sem isso o navegador cancela a requisição junto com a página, e **a
  saída, que é o dado que a casa mais quer, é exatamente o que nunca chegaria**.
- **Não guarda IP, não guarda o que a pessoa digitou e não guarda o que ela
  leu** — só o caminho da página, o nome da seção e o rótulo do que foi tocado.
  O `/privacidade` conta isso na cara, na lista do "o que a gente guarda", nos
  cookies e no prazo (o rastro se apaga sozinho aos 180 dias, sorteado dentro da
  própria função de escrita: cron seria peça nova de infra pra uma linha de SQL).
- **O rótulo do clique não pode ser o nome de ninguém.** O `rastroRotulo` lê,
  nesta ordem, `data-rastro`, `aria-label`, o `alt` da imagem e só então o TEXTO
  do elemento, e foi o texto que abriu um buraco: o gatilho da conta no topo
  mostra o nome de quem está logado, e o cartão do menu do celular mostra nome,
  saldo e plano. O rastro guardava `"MA Maria Souza Andrade 0 pontos · sem plano
  ainda"` como rótulo, ao lado do `user_id`, e o relatório que se diz anônimo
  (e que abre com `rastros.ver`, não com `pedidos.ver`) passava a ter gente com
  nome dentro. Os dois ganharam **`data-rastro`**, que é o jeito de dizer como
  aquele botão se chama no relatório. **Elemento novo cujo texto é dado da
  pessoa precisa de `data-rastro`**, e o `limparRotulo` é a rede embaixo: ele
  troca e-mail e sequência longa de dígitos por "(e-mail)" e "(número)" antes de
  qualquer coisa ir pro banco.
- **A trava dos contatos é OUTRA, de propósito.** O relatório anônimo abre com
  `rastros.ver`; a lista **"os carrinhos frios"**, que tem nome, e-mail e
  telefone de quem comprou quase, exige `pedidos.ver` (ela sai de `orders`
  pendente/cancelada, que a `create-checkout-session` já pré-criava desde a
  0007, só não tinha tela). Deixar as duas atrás da mesma chave faria "ver que
  seção está fria" virar, de graça, "ler a agenda de contatos da loja". Quem não
  alcança os pedidos vê a seção explicando isso, não uma seção sumida.
- **Três freios na escrita**, porque o endpoint é aberto a `anon` (a maior parte
  de quem visita não tem conta, e é essa gente que a casa não enxergava): 40
  eventos por chamada, 400 por visita, 400 visitas novas por hora. Passou do
  teto, a resposta segue `ok:true` e nada é gravado, e **visita que já existe
  continua escrevendo** — quem está navegando de verdade não é cortado no meio
  por causa de uma enxurrada de fora.
- **No ar:** migration aplicada em 03/set/2026, front na `main`. Nenhuma Edge
  Function foi tocada nesta leva, e não há secret nem config de painel a fazer:
  a `0053` vive inteira no banco e no front.

---

## O console da equipe (/admin)

Fica em **`/admin`**, com a porta em **`/admin/entrar`** (login `casa` ou o e-mail
interno; o campo aceita os dois e o `loginParaEmail` traduz). É `noindex` e não é linkado
de lugar nenhum do site público. Quem decide se a pessoa entra é o **banco**, não a tela:
`pode_entrar_no_console()` + `tem_permissao(...)` (0017), e enquanto a senha inicial não
for trocada de verdade a conta não tem privilégio nenhum (0032).

**As 23 abas**, agrupadas por **seção do site** (é assim que a `0047` organiza as
permissões, e é assim que a casa pensa quando decide quem cuida do quê). O `perm` de cada
aba é o `<pagina>.ver` dela, no array `NAV` do `admin.js`; `tudo` = owner vê todas. Todas
as funções que o console chama foram rodadas contra um banco de verdade em 13/ago/2026
(depois da `0042`), em 17/ago (depois da `0043`/`0044`) e de novo depois da `0047`, com
uma pessoa de cada nível chamando cada função, e todas respondem:

> **A auditoria de 13/ago foi feita com as respostas do banco simuladas no navegador**, e
> por isso deu tudo certo enquanto cinco abas estavam quebradas no banco de verdade desde a
> 0017 (ver `0042` na lista de migrations). Tela que renderiza não é prova de função que
> responde: pra valer, a função tem que ser **chamada**.

| Seção | Aba | Ações que existem nela | O que faz |
|-------|-----|------------------------|-----------|
| o dia a dia | painel | ver | os números do dia (`admin_dashboard`) |
| o dia a dia | pautas | ver · mexer · arrumar | o quadro de briefings da equipe (0043/0045) |
| o dia a dia | **rastros** | ver | **nova (0053):** onde a visita terminou, que seção está fria e o funil da loja |
| a loja | pedidos | ver · mexer · arrumar | fila da loja, baixa de entrega/retirada, e arrumar o estado |
| a loja | relatórios | ver | o que vendeu e o que saiu por pontos |
| a loja | desejos | ver | ranking da loja (0029) |
| a loja | esperando | ver | quem espera reposição (0030) |
| o clube | **assinaturas** | ver · arrumar | **nova (0047):** quem assina, e esticar o período pago |
| o clube | **pontos** | ver · arrumar | **nova (0047):** o extrato de cada pessoa, e o ajuste manual |
| o clube | resgates | ver · mexer · arrumar | recompensas trocadas, baixa em mãos, e desfazer devolvendo os pontos |
| o clube | presentes | ver · arrumar | os planos dados de presente (0041), e gerar o código que faltou |
| o clube | aniversários | ver · mexer · arrumar | os brunches reservados (0025), a baixa, e esticar a validade |
| o cardápio | favoritos | ver | ranking do cardápio (0027) |
| a casa | mural | ver · mexer · arrumar | esconder (reversível) e apagar a parede do `/o-casa` (0020/0044) |
| a casa | recados | ver · mexer · arrumar | a tarja no topo do site (0022) |
| a casa | trilha | ver · mexer · arrumar | playlists da home (0023) |
| a casa | agenda | ver · mexer · arrumar | encontros da casa (0026) |
| a casa | **fotos** | ver · mexer · arrumar | **nova (0054):** as 20 fotos do site, o acervo, e apagar do acervo |
| a gente | pessoas | ver | quem já passou por aqui, com plano e pontos |
| a gente | lista de espera | ver · arrumar | e-mails do rodapé (0031/0034), e tirar quem pediu pra sair |
| os eventos | eventos | ver · mexer · arrumar | pedidos de evento (0040), atender e apagar |
| o console | equipe | ver · mexer | dar e tirar permissões |
| (livre) | tua conta | livre | trocar a própria senha, e ver o que se alcança |

- **Permissão não é cargo, e isso tem consequência.** A `admin_definir_permissoes` grava
  em `staff_permissions` e **nunca toca em `profiles.role`** (o princípio da casa é "cargo
  não abre porta, permissão abre"). Então quem recebe acesso pelo console continua com
  `role='cliente'`, e **`is_staff()` responde falso pra essa pessoa**. Toda aba do console
  passa por `tem_permissao(...)` dentro de uma função `security definer`, então isso não
  atrapalha, **com uma exceção que existiu até a `0044`**: o mural escrevia direto pela
  RLS, que fala em `is_staff()`. Regra pra daqui em diante: **aba nova fala com o banco
  por RPC gated em `tem_permissao`**, nunca por tabela direta. Hoje **nenhuma** aba escreve
  direto (o `admin.js` não tem mais um `supabase.from(` sequer).
- **`mural`** modera por três RPCs da `0044` (`admin_mural_listar`/`_status`/`_remover`),
  hoje gated por `mural.ver`, `mural.mexer` e `mural.arrumar` (a 0044 as pôs em
  `tem_permissao('usuarios')`; a 0046 passou pra `mural` e a 0047 separou as três). A trigger da `0036` segue por baixo impedindo que
  qualquer um reescreva `texto`/`autor_nome`/`user_id`: dá pra esconder e apagar, **nunca**
  pra pôr na parede uma frase que a pessoa não escreveu. "Esconder" é reversível e resolve
  quase tudo; "apagar" passa por confirmação e fica registrado no `audit_log` **com o texto
  apagado** (apagar da parede não pode apagar também a memória do que era).
- **`presentes`** é leitura mais dois consertos (RPC `admin_presentes` da 0041 +
  `admin_presente_arrumar` da 0047). O código do presente é **título ao portador**, então a
  página tem permissão própria e não anda junto com a de resgates. O **bilhete** que o
  comprador escreveu **não** vem na RPC: é recado de uma pessoa pra outra.
- **Ainda sem aba** (ficaram de fora a pedido): conquistas (ligar/desligar) e indicações. A
  primeira **não precisaria de migration** (a policy de `achievements` já libera staff); a
  segunda precisaria. Assinaturas e o extrato de pontos, que também estavam nesta lista,
  **entraram com a 0047**.

### Permissão por seção do site, e por ação (`0047`)

O pedido foi: *"um agrupamento de permissões por seção do site; página de vendas, algumas
permissões de ação; página de resgate/presentes, permissões de quem enxerga, de quem mexe,
de quem arruma."* O desenho tem **três camadas**, e as três moram no banco:

- **SEÇÃO** — um pedaço do site: o dia a dia, a loja, o clube, o cardápio, a casa, a gente,
  os eventos, o console. É por aqui que a tela da equipe agrupa, então quem dá acesso
  raciocina *"essa pessoa cuida da loja"*, não *"essa pessoa precisa das caixinhas 3, 7 e 12"*.
- **PÁGINA** — uma tela do console dentro daquela seção. É o que a 0046 chamava de permissão.
- **AÇÃO** — o que se faz naquela página, em três níveis fixos: **ver** (enxergar), **mexer**
  (o dia a dia: dar baixa, publicar, atender) e **arrumar** (o que desfaz, apaga ou mexe em
  ponto, código e dinheiro; sempre com rastro no `audit_log`).

O slug ficou `<pagina>.<acao>` (`pedidos.ver`, `mural.arrumar`), e quem tem um nível
**alcança os de baixo na mesma página** (arrumar > mexer > ver): ninguém fica podendo
consertar uma tela que não pode abrir. São **8 seções, 20 páginas, 43 permissões** (a `0053` acrescentou a 21ª página, `rastros`, com uma ação só, e a `0054` a 22ª, `fotos`, com as três).

- **O whitelist virou TABELA.** Era um CHECK escrito à mão, que a 0043 e a 0046 já tiveram
  que reescrever; agora são as tabelas `permissao_secoes` › `permissao_paginas` ›
  `permissoes`, com FK vinda da `staff_permissions`. **Permissão nova daqui pra frente é
  INSERT numa tabela de catálogo, não `alter constraint`.**
- **O catálogo não é repetido no front.** A tela da equipe monta o que vier da
  `admin_permissoes_catalogo()`. Enquanto a lista estava escrita nos dois lugares, ela
  divergia, e a que a tela mostrava não era a que o banco cobrava.
- **A ponte com os slugs velhos** (`permissoes_legado` + `permissao_canonica`): as funções e
  as policies que a 0047 não reescreve continuam perguntando pelo slug da 0046
  (`tem_permissao('favoritos')`) e caem no `favoritos.ver`. Sem isso, aplicar a 0047
  apagaria o acesso de todo mundo até a última função ser reescrita. **Cuidado ao escrever
  função nova:** o slug velho resolve pro nível de LEITURA, então gate novo se escreve
  sempre no formato `<pagina>.<acao>`.
- **`admin_minhas_permissoes` devolve a lista já EXPANDIDA** (quem tem `mural.arrumar`
  recebe `mural.mexer` e `mural.ver` junto), e o front só pergunta `pode('mural.ver')`. A
  regra da hierarquia é do banco; o front não repete régua de permissão.
- **A tela da equipe** (`/admin#equipe`) mostra seção por seção, cada página com as
  caixinhas das ações dela, **"marcar tudo"/"limpar" por seção**, e uma linha de resumo em
  português ("alcança 6 de 20 páginas: …, e arruma o mural"). Marcar um nível acende os de
  baixo; desmarcar apaga os de cima, pra a tela nunca mostrar um acesso que não é o que a
  pessoa tem. A página **equipe** é a única que só o dono delega.
- **O cartão da pessoa abre e fecha.** A grade tem 43 caixinhas: com todas abertas a lista
  vira um paredão de checkbox, e depois de salvar ela continuava escancarada, como se ainda
  houvesse o que fazer. O cartão mostra o nome, o e-mail e **o resumo do acesso**; quem vai
  mexer aperta **"editar permissões"**. Salvar recarrega a lista (fecha e mostra o estado
  novo) e **"cancelar" também recarrega** de propósito, pra o que foi marcado sem salvar
  não ficar na tela fingindo que valeu. Quem acaba de ser trazido pelo **+equipe** nasce com
  o cartão ABERTO, porque aí a próxima coisa a fazer é justamente marcar.
- **Na virada ninguém perdeu nada:** a 0047 faz backfill de cada slug da 0046 pra fila do
  que aquela pessoa já fazia. `mural`, `avisos`, `trilha` e `agenda` levam o `arrumar` junto
  (apagar já estava dentro delas); `resgates`, `aniversarios` e `leads` param no `mexer`. O
  `arrumar` de pedido, ponto, presente e assinatura **não vai pra ninguém automaticamente**:
  é poder novo, e poder novo se dá na mão.

### O "arrumar" existe de verdade

Permissão que não abre porta nenhuma é enfeite. A 0047 entrega, junto, os consertos que a
casa não tinha como fazer sem SQL na mão, e cada um deles deixa rastro no `audit_log`:

| Conserto | Função | Por que precisava existir |
|----------|--------|---------------------------|
| desfazer resgate | `admin_resgate_desfazer` | o ledger é append-only, então resgate clicado sem querer custava os pontos **pra sempre**. Devolve os pontos (idempotente pelo índice `(ref_type, ref_id)`), volta o estoque e tira o cupom de circulação |
| ajustar pontos | `admin_pontos_ajustar` | webhook que falhou, ponto que caiu duplicado, cortesia. Lançamento no ledger com **motivo obrigatório**, teto de 5.000 por vez, saldo pode ficar negativo (igual ao estorno do webhook) |
| arrumar pedido | `admin_pedido_status` | a baixa da 0017 era só de ida: marcou entregue no pedido errado e a fila mentia pra sempre. `pendente` e `estornado` seguem fechados, ali quem manda é o gateway |
| gerar o código do presente | `admin_presente_arrumar` | presente **pago sem código** (o webhook caiu entre o pagamento e a `marcar_presente_pago`): quem pagou ficava com um presente que não existe. Também cancela um `pendente` parado. Presente pago **não** se cancela por aqui |
| desfazer/esticar o brunch | `admin_brinde_arrumar` | baixa no código errado, e quem não conseguiu vir nos 30 dias |
| esticar a assinatura | `admin_assinatura_esticar` | dias de cortesia no período já pago. **Não cobra, não estorna e não contradiz o Asaas** (lá o ciclo segue igual); pausar, retomar, subir e descer de plano continuam nas Edge Functions |
| tirar da lista de espera | `admin_espera_remover` | "me tira dessa lista" é direito de quem deixou o e-mail. O endereço **não** vai pro `audit_log`, só o domínio: apagar da tela e guardar na gaveta não é apagar |
| apagar pedido de evento | `admin_lead_evento_remover` | mesmo caso, com nome e telefone. O audit guarda só o tipo do evento |
- **A faixa de abas gruda no topo em tela estreita.** Abaixo de 900px a lateral escura vira
  uma faixa no topo, e ela era `position: static`: numa aba comprida bastava rolar um pouco
  e **a navegação inteira saía da tela**, deixando o conteúdo solto no fundo bege, com cara
  de página quebrada e sem jeito de trocar de aba a não ser voltando ao topo. Vale pra
  qualquer janela abaixo de 900px **e pro notebook com o zoom do navegador aumentado**, que
  é como isso apareceu. Agora é `sticky`.
- **A barra de abas em tela estreita** (abaixo de 900px a lateral escura vira uma faixa no
  topo): o `.ad-nav-item` levava `width: 100%` da versão vertical, e em fila horizontal
  isso dá a **largura inteira da faixa pra cada item**. Os 18 viravam uma fila de 15.654px
  e **só o "painel" aparecia**, sem nenhum aviso de que havia mais, então quem abria o
  console no notebook menor ou no celular não alcançava aba nenhuma. Em fila a largura
  passa a ser a do texto (`width: auto` + `white-space: nowrap`), a ponta ganhou o mesmo
  degradê da tirinha do `/cardapio` e a aba aberta **se puxa pra dentro da vista**
  (`scrollIntoView`, respeitando `prefers-reduced-motion`) — sem isso as últimas da fila
  nasciam fora da tela toda vez.
- **Onde se dá acesso a alguém** (aba **equipe**, `perm: 'equipe'`, só quem é owner delega
  a própria `equipe`): a tela abre com **a equipe**, não com um campo de busca. O botão
  **"+equipe"** no cabeçalho abre a folhinha de procurar (`admin_buscar_pessoa`, mínimo 3
  letras); a pessoa escolhida entra na lista com as permissões em branco, e aí se marca e
  salva (`admin_definir_permissoes`). A busca sempre-aberta no topo fazia a aba abrir com
  um campo em vez de abrir com quem já está lá, que é o que se vem ver aqui. **Lista vazia
  agora fala**: se nem a própria conta voltou do banco, isso não é "equipe vazia", é a
  leitura, e a tela diz isso em vez de ficar em branco.
  "Tirar do console" limpa todas. O adm do Casa e o master aparecem como intocáveis, e
  ninguém edita as próprias permissões. **A pessoa precisa ter conta no site primeiro** (a
  busca varre o `profiles`): não existe convite por e-mail, ela se cadastra em `/cadastro`
  e aí aparece na busca. **Esta aba ficou quebrada da `0017` até a `0042`** (as duas
  funções dela caíam no erro de tipo do e-mail), então ela nunca tinha funcionado de
  verdade antes de 13/ago/2026.
- **Aba que estoura mostra o motivo, não fica em branco.** Toda `view*` é `async`, e o
  roteador chamava `(telas[id] || viewPainel)(view)` sem `catch`: se a view estourasse
  ANTES do try/catch que ela tem por dentro (um elemento que não veio, um helper que
  sumiu), a promise rejeitava em silêncio e a **área do conteúdo ficava vazia**, sem uma
  linha dizendo o quê. Da tela, isso é indistinguível de "não tem dado", e foi assim que um
  problema real ficou invisível. Agora o roteador embrulha a chamada (sync e async) e a
  `falhaDaAba` escreve "essa aba não abriu" com a mensagem do erro. O `zerarEstadoDasAbas`
  também virou try/catch: arrumação de casa não pode derrubar a tela.
- **Trocar de aba zera o que a tela não mostra** (`zerarEstadoDasAbas`, chamada pelo
  `abrirDoHash`). O id em edição e o texto de busca viviam em variável de módulo e
  sobreviviam à remontagem da view, então a tela mentia de dois jeitos. O grave: clicar
  "editar" num recado, sair da aba e voltar deixava o formulário limpo (botão "publicar")
  com o id antigo na memória, e o próximo "publicar" **sobrescrevia o recado velho** em vez
  de criar um novo. Na **agenda** era pior, porque o encontro reescrito leva junto as
  presenças já confirmadas (as linhas de `event_rsvps` continuam na mesma `events.id`, e
  quem confirmou presença passa a estar confirmado em outro evento). O leve: o campo de
  busca voltava vazio e a lista continuava filtrada por um termo que não aparecia em lugar
  nenhum. **O filtro de status não entra no reset** de propósito: ele tem um chip aceso na
  tela, então ele não mente.
- **Os modificadores certos são `.notice.err` e `data-tom="erro"`**, e o console usava o
  par trocado: oito avisos de validação pediam `.notice.erro` (classe que não existe, então
  o erro saía com cara de recado neutro) e um toast pedia `'err'` (que o CSS não pinta de
  vermelho). Regra: **no `notice` é `err`, no `toast` é `erro`**.
- **`/admin` e `/admin/` abrem os dois.** O middleware do dev só tentava
  `<caminho>.html`, então `/admin` (sem barra) não achava `admin.html` e caía no 404,
  enquanto `/admin/` funcionava. Agora ele também tenta `<caminho>/index.html`, que é como
  a Vercel já servia em produção.

---

## O quadro da casa (pautas da equipe)

O console sabia tudo sobre o que a casa **vende** e nada sobre o que a equipe **combina**.
O que a turma tinha que fazer no dia vivia em bilhete no balcão e em conversa de grupo,
que é onde combinado some. A aba **pautas** (`/admin#pautas`, primeira depois do painel,
porque é por onde o dia começa pra quem trabalha no salão) é o quadro da casa.

A `0043` entregou um quadro só, com três colunas fixas e um formulário grande em cima. A
**`0045`** virou isso num quadro de verdade, no formato que todo mundo já conhece de
ferramenta de quadro:

- **Vários quadros**, um por canto da casa (salão, cozinha, marketing), cada um com nome e
  cor, numa fila de chips no topo. Dá pra **arquivar** (some da fila, volta quando quiser)
  e **apagar** (só vazio: apagar quadro cheio levaria trabalho combinado junto).
- **Grupos dentro do quadro**, que é a faixa colorida com as linhas embaixo ("essa
  semana", "quando der"). Grupo **recolhe**, e o recolhido mora no BANCO, não no
  navegador: a casa fecha "feitas" uma vez e vale pra quem abrir depois.
- **Visão de tabela** (o padrão) com **célula clicável**: tocar em pra-quem, estado, prazo
  ou urgência abre uma folhinha de opções e muda ali mesmo. E **visão de quadro**, as
  mesmas pautas empilhadas por estado, pra quem prefere ler por coluna.
- **Quatro estados**, com cor: *a fazer* (neutro), *fazendo* (caramelo), **travada**
  (terracota) e *feita* (verde). O `travada` é o mais informativo num café ("o fornecedor
  não entregou"): sem ele, a pauta parada fica igual à que ninguém pegou.
- **Comentários por pauta**: tocar no título abre um painel lateral com o briefing e a
  conversa. É o que faz o combinado ficar na pauta em vez de sumir no grupo do zap.
- **Pauta nova nasce na linha "+ pauta" do próprio grupo**, só com o título; o resto se
  preenche clicando nas células. Formulário grande em cima saiu.
- **Ordem por botão** (subir/descer), não por arrastar: o console é usado no celular no
  meio do turno, e arrastar em tela pequena erra mais do que acerta.

**Três decisões que valem conhecer:**
- **A leitura é `returns jsonb`, não `returns table`.** Foi o `returns table` que derrubou
  cinco abas da 0017 até a 0042 (varchar declarado como text). Uma leitura composta como a
  `admin_quadro_abrir`, que devolve quadro + grupos + itens de uma vez, teria uma dúzia de
  colunas pra errar. Em jsonb essa classe de erro não existe, e vem tudo numa viagem só.
- **Mudar uma célula NÃO recarrega o quadro:** a linha se reescreve sozinha
  (`redesenharLinha`). Recarregar faria a tela piscar e devolver o scroll ao topo a cada
  toque, no aparelho onde o console é usado em pé.
- **Um listener delegado** no corpo do quadro (`aoTocarNoQuadro`), não um por botão: com
  célula clicável em toda linha, religar listener a cada render seria caro e frágil.

**Quem pode o quê:** ver, criar, editar, mover e comentar → `tem_permissao('pautas')`.
**Apagar pauta →** só quem escreveu, ou o adm do Casa. **Apagar comentário →** só quem
escreveu, ou o adm. Criar, editar e apagar ficam no `audit_log`.

**As seis cores** (`neutro`, `coral`, `gold`, `green`, `olive`, `blue`) são exatamente as
variantes de `.tag` que já existem no CSS, e o banco só aceita esses seis slugs: cor nunca
vem do banco como hex, nem vira `style=`. Do handoff de design em diante, o mapa dos seis
slugs virou **uma variável só** (`--grupo-cor`, no `.pauta-grupo[data-cor]`), que serve a
barrinha do nome do grupo e o eco no começo de cada linha.

**O acabamento da tela** (handoff de design, 17/ago/2026, só CSS mais dois retoques de
markup): a tabela era **linhas soltas boiando** e o cabeçalho não caía no prumo das
células. Agora as linhas são **um cartão contínuo** (raio só na primeira e na última, a
linha "+ pauta" grudada no pé), o cabeçalho espelha o padding real da célula (14px da
linha mais 1px de borda, mais os 10px de dentro da `.pauta-celula`), o nome do grupo
troca a pílula pela **barrinha de cor** e os controles ficam quietos (os dois filtros
viram trilho de *segmented control*, as quatro ações do quadro e as três da linha perdem
a caixa). Três coisas que valem saber:
- **O corte é 861px, não os 720px do handoff.** É aqui que a tabela deixa de ser tabela: o
  `@media (max-width: 860px)` que já existia empilha cada pauta como cartão, e ali cada
  linha PRECISA do próprio raio. Todo o bloco de layout do acabamento mora atrás de
  `@media (min-width: 861px)`, então o celular não muda.
- **O `gap: 6px` do `.pauta-grupo` era o que afastava as linhas** (menos o `-1px` que a
  linha já puxava = 5px de ar). Sem zerar esse gap, o cartão contínuo não fecha, por mais
  raio que se tire; o respiro entre o cabeçalho do grupo e a primeira linha passou a ser
  um `margin-bottom`.
- **O nome do grupo perdeu o `tag <cor>` no HTML, o da coluna do kanban não.** A classe
  `.pauta-grupo-nome` serve os dois lugares, e no kanban a cor é o estado (a fazer,
  fazendo, travada, feita), que não pode virar rótulo cinza. Como `.tag.coral` tem
  especificidade maior que `.pauta-grupo-nome`, a mesma regra de tipografia serve os dois
  e só a tabela fica quieta. O chip neutro ganhou fundo `--paper-2` pelo mesmo motivo:
  sem ele, "a fazer" e "quando der" eram texto solto no meio de uma coluna de pílulas.

**O que NÃO foi feito, de propósito:** coluna customizável por quadro (criar uma coluna
"turno" ou renomear os estados). É a peça mais cara de uma ferramenta dessas, e um café
não vai mexer nisso; os quatro estados fixos já são os quatro de qualquer quadro. Se um
dia precisar, o caminho é uma tabela de definição de coluna, não remendo no que existe.

---

## Acessibilidade

- **"pular pro conteúdo"** (`renderSkipLink`, chamado pelo `renderHeader`, toda página):
  primeiro foco do teclado, fora da tela até receber foco. O alvo é descoberto no DOM
  (`main`, ou a primeira `section` depois do header, que é o caso da área `conta/`), ganha
  `id` + `tabindex="-1"` + `data-skip-alvo` — assim vale em todas as páginas sem precisar
  marcar cada `.html`. Entra como primeiro filho do `<body>`, antes até da tarja de recado.
- **`[hidden] { display: none !important }`** no `styles.css`: o `[hidden]` é regra do
  user-agent e **qualquer** `display` de classe nossa vencia ele (o arquivo mora fora de
  `@layer`), fazendo aparecer na tela elemento que nasceu escondido — aconteceu com
  `.som-live`, `.prod-guardar` e o "cancelar edição" dos recados no console. A regra global
  fecha a família; as regras `.classe[hidden]` espalhadas pelo arquivo viram só reforço.
  **Elemento novo que nasce `hidden` só precisa de `el.hidden = false` pra aparecer** (é o
  padrão do projeto) — mostrar por classe não funciona enquanto o atributo estiver lá.
- **Hero da home**: além de "voltar"/"pular", agora tem **bolinhas de posição**
  (`[data-hero-dots]`, montadas pelo `setupHeroCarousel`, uma por slide, clicáveis,
  `aria-current` na atual). Com um slide só, a fila nem aparece.
- **Tour 360 do `/o-casa`**: link **"o tour não abriu? dá a volta no Google Maps"** abaixo
  do quadro (mesmo papel do "traçar rota" pro mapa) — se o iframe não carregar, o giro
  continua a um toque, com o `pano` da mesma foto esférica e o `viewpoint` da porta do Casa
  como rede de segurança.
- **WhatsApp no rodapé**: o telefone sempre abriu o WhatsApp, mas nada dizia isso na tela.
  Agora tem ícone e rótulo (`.ft-whats`), em toda página, sem depender do link da `/colab`.

---

## Responsividade

- **Mobile-first**, funcionando desde **~320px** (Galaxy Pocket) até **ultrawide (2560px+)**.
- **Botão de rótulo comprido quebra linha embaixo de 430px** (`@media` logo abaixo do
  `.btn` no `styles.css`). O `.btn` nasce com `white-space: nowrap`, que é certo pra
  "comprar" e errado pra uma frase: o "o tour não abriu? dá a volta no Google Maps" do
  `/o-casa` media **381px fixos** e o "segue a gente @casacoffeecolab" do `/colab`, 325px,
  então **a página inteira ganhava scroll lateral** no celular. As 19 páginas foram
  medidas de novo a 320, 360 e 390px depois disso: nenhuma estoura.
- Breakpoints extras no Tailwind: `xs` 375, `3xl` 1920, `4xl` 2560 (mantendo `sm/md/lg/xl/2xl` padrão).
- Sempre respeitar **`prefers-reduced-motion`**.

---

## Estrutura de pastas

```
/
├── src/                  # root do Vite — o caminho do arquivo é a URL
│   ├── index.html        # raiz "/" → redireciona pra /home
│   ├── home.html         # /home … e assim por diante, uma página por URL
│   ├── app.js            # header/footer/menu + lógica de UI
│   ├── fotos-do-site.js  # a lista dos lugares do site que mostram foto (site + console)
│   ├── styles.css        # entrada Tailwind + base
│   ├── conta/            # área logada (/conta/perfil, /conta/pontos, …)
│   └── assets/           # publicDir: servido na raiz (/fotos/…)
├── supabase/
│   ├── migrations/       # SQL numerado, append-only
│   └── functions/        # Edge Functions (segredos só aqui)
├── vercel.json           # cleanUrls + redirects do /pages/ legado
├── tailwind.config.js
├── postcss.config.js
├── vite.config.js
└── package.json
```

---

## Comandos

- `npm run dev` — servidor de desenvolvimento (Vite).
- `npm run build` — build de produção.
- `npm run preview` — pré-visualiza o build.
- `npm run avatares-orfaos` — varre o bucket `avatares` do Storage e lista as fotos
  que ninguém usa. Ver "Fotos órfãs no Storage" abaixo.
- `npm run fotos-orfas` — o mesmo pro bucket `fotos-site` (o acervo da 0054). Mesmo
  desenho, mesma carência, mesmo dry-run por padrão.
- `npm run criar-adm-master` — cria a conta do adm master do console (login `casa`,
  e-mail interno `casa@casacoffeecolab.com.br`, `role='owner'` + `master=true`).
  Precisa da **service_role no ambiente** (mesmo esquema do comando acima) e das
  migrations `0017_admin` e `0032_senha_inicial_master` aplicadas. Idempotente: se a
  conta já existe, não duplica nem mexe na senha — `--resetar-senha` sorteia outra
  (o e-mail é interno, então "esqueci a senha" não chega em lugar nenhum) e volta a
  exigir a troca no primeiro acesso.
  > **A senha inicial é SORTEADA e aparece uma vez só, no terminal.** Não existe
  > mais senha padrão: uma senha combinada no repo era porta aberta pra conta mais
  > poderosa do sistema (a URL do projeto e a anon key estão no bundle público, como
  > têm que estar, então dava pra logar no endpoint do Auth e receber um JWT de owner
  > sem passar por tela nenhuma). Enquanto essa senha não for trocada de verdade, o
  > **banco** não reconhece privilégio nenhum da conta: `is_owner`, `is_staff`,
  > `is_gerente_or_owner`, `tem_permissao` e `pode_entrar_no_console` respondem falso
  > (0032), então nem o console nem o PostgREST entregam nada. A trava compara o
  > **hash** da senha inicial com o de agora, não um carimbo — só a troca real
  > destrava, e destrava sozinha.

### Fotos órfãs no Storage (`scripts/avatares-orfaos.mjs`)

O Storage **não tem cascata**: se uma conta some por fora da `delete-account`, ou se o
upload sobe mas o `update` do perfil falha depois, o arquivo fica lá ocupando espaço sem
dono. O script cruza o bucket com a **fonte da verdade — `profiles.avatar_url`** (extrai o
caminho da URL pública, ignorando o `?v=`): todo arquivo que ninguém aponta é órfão, o que
cobre de uma vez pasta de conta apagada, foto antiga e upload meio-caminho.

Precisa da **service_role** (lê o bucket inteiro e o `profiles`), então ela vai **só no
ambiente do comando** — nunca no `.env` do repo, nunca hardcoded:

```powershell
$env:SUPABASE_URL="https://<ref>.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="<service_role>"
node scripts/avatares-orfaos.mjs            # só relata (dry-run, o padrão)
node scripts/avatares-orfaos.mjs --apagar   # relata e limpa
```

- **Dry-run por padrão.** Sem `--apagar` nada é removido.
- **Carência de 24h:** arquivo sem dono mas recém-subido não é apagado (pode ser upload em
  andamento com o `update` do perfil ainda a caminho). Override: `--horas=0`.
- Também avisa **referência quebrada** (perfil aponta pra arquivo que não existe mais) —
  não é lixo, mas é avatar que não carrega.

### O acervo de fotos também (`scripts/fotos-orfas.mjs`, `npm run fotos-orfas`)

O irmão do de cima, pro bucket **`fotos-site`** da 0054, com as mesmas regras (service_role
só no ambiente, dry-run por padrão, `--apagar`, `--horas=`). O que muda é o que ele
considera dono, e por quê:

- **Órfão é o arquivo que nem o ACERVO (`fotos_galeria`) nem os LUGARES (`site_fotos`)
  apontam.** Ele sobra de dois jeitos, os dois porque a aba faz duas coisas em sequência:
  subir é primeiro o arquivo e depois a ficha (`admin_foto_registrar`), e apagar do acervo
  é primeiro a linha e depois o arquivo. Fechou a aba no meio, sobra arquivo pago e
  invisível.
- **Foto no acervo e em lugar nenhum do site NÃO é órfã**, e essa é a diferença que importa
  em relação ao de avatares: o acervo existe justamente pra guardar foto que a casa vai usar
  no mês que vem. Quem confundisse isso apagaria o acervo inteiro.
- **Arquivo que está num lugar do site mas perdeu a ficha também não é apagado.** Não
  deveria acontecer (a `admin_foto_remover` recusa apagar foto em uso), mas se alguém mexer
  no banco pelo SQL Editor, apagar esse arquivo abriria um buraco na página pública.
- **Referência quebrada vem em duas listas, e a do site vem primeiro:** ficha do acervo sem
  arquivo é miniatura que não carrega no console; **lugar do site sem arquivo é foto
  quebrada na página pública**, e o recado diz o conserto ("voltar pra de fábrica" naquele
  lugar).
  > **Como foi verificado:** rodado contra um Supabase dublado, com um bucket de 111
  > arquivos em três pastas (pra exercitar a recursão e a paginação de 100 em 100): a foto
  > do acervo sem lugar ficou, a que está num lugar sem ficha ficou, a recém-subida e a
  > **sem data legível** ficaram, as duas referências quebradas foram listadas separadas, e
  > o `--apagar` mandou apagar **exatamente um caminho**, o único órfão de verdade. Com
  > `--horas=0` a recente vira órfã e a sem data continua protegida.

## Segurança (regras obrigatórias — valem a partir da Fase 2)

**Favicon em arquivo, não embutido no `href` (console).** As duas páginas de `/admin`
traziam o SVG do favicon num `data:` URI percent-encoded, e o `xmlns='http://www.w3.org/2000/svg'`
que o SVG precisa pra renderizar aparecia como texto legível dentro do atributo. Scanner de
segurança (Semgrep `missing-integrity`) lê ali um recurso externo sem `integrity` e abre um
alerta **que não tem como resolver**: SRI não se aplica a `data:` URI e o navegador ignora
`integrity` em `rel="icon"`. Agora elas apontam pro `/favicon.svg` (em `src/assets/`, que é o
`publicDir`). As 25 páginas do site seguem com o favicon embutido **sem** percent-encoding, e
por isso não caem na mesma regra; se algum dia uma delas for codificada, aponta pro arquivo.

**Nada de variável dentro do texto de `console.*`.** Valor que vem de fora (nome de aba,
tipo de evento do webhook) vai como **argumento separado**, nunca interpolado na string: um
`%s` plantado no valor forjaria a linha do log. Vale pro `admin.js` e pras Edge Functions.


Segredos:
- .env no .gitignore; .env.example (sem valores reais) versionado. NUNCA commitar segredo.
- Só no client/Vercel: SUPABASE_URL, SUPABASE_ANON_KEY. (O checkout do Asaas é hospedado — NÃO existe chave pública de pagamento no bundle.)
- SÓ nas env vars das Edge Functions (nunca no bundle/Vercel/repo): SUPABASE_SERVICE_ROLE_KEY, ASAAS_API_KEY, ASAAS_WEBHOOK_TOKEN, POS_WEBHOOK_SECRET.

Banco (RLS-by-default):
- Toda tabela sobe com RLS habilitado e deny-by-default. Nenhuma tabela sem política explícita.
- points_ledger, subscriptions, orders, redemptions, audit_log: cliente só LÊ o próprio registro; escrita só via Edge Function (service_role) ou trigger.
- role do usuário vem de profiles (fonte confiável), NUNCA de valor enviado pelo client. Troca de papel só pelo owner e registrada no audit_log.

Confiança zero no client:
- Pontos calculados e gravados só server-side (ledger append-only). Front só lê.
- create-checkout-session recalcula preço, desconto do tier e total pelo BANCO — nunca confia no valor/carrinho do client.
- Webhooks (Asaas e PDV): verificar autenticidade (Asaas → token no header `asaas-access-token` vs `ASAAS_WEBHOOK_TOKEN`; PDV → HMAC) + idempotência por id de evento (anti-replay). SEMPRE.
- Escapar toda string vinda do banco antes de injetar no DOM (evitar XSS no JS vanilla).

Gate de fim de leva (backend): rodar antes de commitar —
1) grep por chaves secretas no código/dist; 2) confirmar RLS on em toda tabela nova; 3) npm audit; 4) nenhuma escrita sensível no client.
- Implementado em `npm run security-check` (`scripts/security-check.mjs`, estático) + `scripts/check-rls.sql` (prova de RLS ao vivo no SQL Editor, incl. teste negativo como anon). Rodar o security-check ANTES de commitar/subir.

## Migrations do banco (Supabase)

Todo SQL que precisa rodar no SQL Editor do Supabase vira um arquivo numerado em supabase/migrations/, na ordem de aplicação (ex: 0001_init.sql, 0002_rls.sql, 0003_seed.sql). O humano aplica cada migration MANUALMENTE no SQL Editor, em ordem.
- Migrations são APPEND-ONLY e IMUTÁVEIS: depois de aplicada, nunca edite. Mudança nova = arquivo novo numerado.
- Cada migration deve ser autocontida e, quando possível, idempotente (IF NOT EXISTS / CREATE OR REPLACE).
- Ao gerar migrations, SEMPRE diga ao humano exatamente quais arquivos rodar e em que ordem.
- Não existe mais um schema.sql único — as migrations numeradas são a fonte da verdade do banco.
- Aplicadas até agora: `0001_init` (tabelas + funções de papel + triggers), `0002_rls` (RLS + policies), `0003_seed` (tiers/produtos/conquistas/parceiros), `0004_reconcile` (5 tabelas da Fase 3: `rewards_catalog`, `events`, `coupons`, `pos_webhook_events`, `unclaimed_points` + colunas `tiers.points_multiplier/discount_percent` e `profiles.points_balance/tier_slug`), `0005_profiles_phone` (coluna `profiles.telefone` + `handle_new_user` populando telefone + trigger `prevent_points_tamper` blindando `points_balance`/`tier_slug` contra escrita do client), `0006_stripe` (`stripe_events` + `profiles.stripe_customer_id` + UNIQUE em `subscriptions.stripe_subscription_id` + price IDs dos tiers), `0007_orders_stripe` (UNIQUE em `orders.stripe_checkout_id` pra idempotência da loja), `0008_points` (Fase 3: `points_ledger.ref_type/ref_id` + UNIQUE `(ref_type,ref_id)`, trigger `update_points_balance` que sincroniza o cache, `prevent_points_tamper` com bypass via GUC `casa.trusted_points`, `recalc_points_balance`, `redeem_reward` atômica, `rewards_catalog.slug/cupom_valor_centavos` + seed de recompensas), `0009_achievements` (Fase 3 conquistas: coluna `achievements.criterios` jsonb + função `check_achievements(uuid)` SECURITY DEFINER que avalia os critérios e concede os emblemas server-side, chamada nos webhooks e no resgate), `0010_achievement_hints` (coluna `achievements.dica` + seed das dicas "como desbloquear" por slug, mostradas no card bloqueado e no tooltip dos emblemas do painel), `0011_asaas` (**migração Stripe→Asaas**: `profiles.asaas_customer_id`, `subscriptions.asaas_customer_id`/`asaas_subscription_id` (UNIQUE), `orders.asaas_checkout_id` (UNIQUE)/`asaas_payment_id`, tabela `asaas_events` com RLS), `0012_asaas_checkout_link` (`subscriptions.asaas_checkout_id` — o elo que liga o `CHECKOUT_PAID`, que sabe user+tier, ao `PAYMENT_*`, que sabe o id da assinatura), `0012_downgrade` (`subscriptions.scheduled_downgrade_to` — sem ela a `downgrade-subscription` não roda; os dois arquivos `0012` são independentes entre si, a ordem entre eles não importa), `0013_redeem_reward_user_lock` (trava a linha do usuário antes de ler o saldo, matando o gasto duplo de pontos em resgates simultâneos).
- **Banco em dia:** o humano aplicou a leva `0011_asaas` → `0012_asaas_checkout_link` → `0012_downgrade` → `0013_redeem_reward_user_lock` no SQL Editor em **28/jul/2026**, e a `0014_perfil` (campos novos do `/conta/perfil`) na sequência.
- **`0055_tetos_e_repetido` — APLICADA em 09/set/2026** (na sequência da `0054`). São as duas correções que a auditoria dos dez últimos commits achou no banco,
  as duas nas funções abertas a `anon`, que são as únicas portas de escrita que qualquer
  pessoa alcança com a chave do bundle. O corpo das duas funções é o que já estava no ar;
  só o marcado com "(0055)" muda. **Teto global de 20 mil eventos por hora** no
  `registrar_rastro`: os dois tetos da 0053 (400 visitas novas por hora, 400 eventos por
  visita) seguram cada dimensão sozinha, mas se **multiplicam**, e o teto de verdade era
  160 mil linhas por hora, uns meio giga por dia. O contador de `paginas` da visita também
  ganhou fim (500), porque visita que já existe não passa pelo freio horário. E o
  `registrar_lead_evento` passou a devolver **`repetido: true`** quando o anti-flood segura
  o pedido (ver "/eventos" acima). Nenhuma tabela, coluna, policy ou permissão muda, e
  nada aqui pede re-deploy de function. **A numeração livre pra próxima é a `0056`.**
  > **Como foi verificada:** as 55 migrations rodaram do zero num Postgres 16 local, a 0055
  > rodou **duas vezes** pra provar idempotência, e as duas funções foram **chamadas** com
  > dado de verdade: lead novo entra, o mesmo contato em seguida volta `repetido: true` e
  > **não** grava (o recado corrigido não entra, que é justamente o bug), contato diferente
  > entra; 600 pulsos de página nova param em 500; com a hora cheia de eventos o pulso não
  > grava evento nenhum, **a visita entra do mesmo jeito** e o contador de cliques dela fica
  > em 0 em vez de mentir; e com a hora limpa os dois eventos entram e o contador bate.
- **`0054_fotos_do_site` — APLICADA em 09/set/2026**, junto com a `0055`, e o front das
  duas foi pra `main` no mesmo dia. Não pediu Edge Function, secret nem config de painel. Ela
  cria o bucket `fotos-site`, as tabelas `fotos_galeria` e `site_fotos`, a página `fotos`
  no catálogo de permissões da 0047 e as seis funções da aba. **Sem ela o site não quebra**
  (as fotos de fábrica do HTML continuam no ar) e **a aba "fotos" não aparece pra ninguém**,
  porque a permissão dela nasce aqui dentro. Depois de aplicada, o dono já enxerga a aba;
  quem mais for cuidar das fotos precisa receber `fotos.mexer` na aba **equipe** — a
  migration **não** dá essa permissão a ninguém automaticamente, de propósito (é a cara do
  site na internet, e poder novo se dá na mão).
  > **Como foi verificada:** as 54 migrations rodaram do zero num Postgres 16 local (os
  > mesmos stubs de `auth`/`storage` que a 0042 já descrevia; só a 0015, a 0016 e a 0052
  > seguem precisando do Supabase de verdade), a 0054 rodou **duas vezes** pra provar
  > idempotência, e as funções foram **chamadas** com dado de verdade por cinco pessoas
  > diferentes (dono, só-enxerga, quem-mexe, quem-arruma e um cliente sem nada): registrar
  > foto, caminho torto (`../../etc/passwd`, `https://…`, `//`) recusado, foto sem nome
  > recusada, trocar o lugar, slot inválido recusado, id de foto que não existe recusado,
  > soltar (e soltar de novo, que responde `ja_era`), apagar do acervo recusado enquanto a
  > foto está em uso e aceito depois de solta, a leitura pública devolvendo só slot/caminho/
  > alt, a RLS recusando leitura direta das duas tabelas **até pro dono**, o `anon` sem poder
  > executar as `admin_*`, e as policies do bucket deixando subir só quem tem `fotos.mexer`
  > e apagar só quem tem `fotos.arrumar`.
  > **E o front foi rodado num navegador de verdade** (Chromium, contra um Supabase dublado):
  > na home, o lugar trocado troca de `src` e de descrição, o lugar intacto fica com a foto de
  > fábrica, foto sem descrição nova **não** apaga o `alt` do HTML, caminho torto vindo do
  > banco é ignorado, slot que não existe não estoura, e com o banco fora do ar o cache
  > segura a foto certa (sem cache, volta a de fábrica). No console, as 20 fichas nascem
  > agrupadas pelas 4 páginas, quem tem só `fotos.mexer` não vê o botão de apagar, o texto
  > vindo do banco sai escapado, e trocar/soltar redesenham a ficha.
- **Banco em dia (09/set/2026):** a **`0054_fotos_do_site`** e a **`0055_tetos_e_repetido`**
  foram aplicadas no SQL Editor nessa ordem, e o front das duas está na `main`. **Não há
  migration pendente**, e a numeração livre pra próxima é a **`0056`**. O que ficou fora do
  banco nesta leva, e é passo de terminal, não de SQL: **re-deployar a `avisar-lead-evento`**
  (`npx supabase functions deploy avisar-lead-evento --no-verify-jwt`), que é onde mora o
  corte seguro da mensagem do Telegram. Sem ela o sino segue tocando igual, só continua
  quebrando com recado gigante.
- **Banco em dia (03/set/2026):** a **`0053_rastros`** foi aplicada no SQL Editor,
  e o front foi pra `main` no mesmo dia. **Não há migration pendente**, e a
  numeração livre pra próxima é a **`0054`**. Ela foi a mais barata de aplicar da
  história do projeto: não pede Edge Function, não pede secret e não pede config
  de painel, é só o arquivo. **A aba "rastros" do console só aparece depois desta
  migration** (a permissão dela nasce no catálogo da 0047 aqui dentro), então
  quem não a via antes de 03/set não estava com a tela quebrada.
- **Banco em dia (19/ago/2026):** a **`0052_aviso_lead_evento`** foi aplicada no SQL Editor
  em 19/ago, e a numeração livre pra próxima é a **`0053`**. Diferente da leva anterior,
  **esta pede Edge Function**: a `avisar-lead-evento` foi deployada no mesmo dia com
  `--no-verify-jwt` (quem chama é o `pg_net`, que não tem sessão de usuário). O resto do que
  ela precisa é **configuração, não código** — os dois segredos do Vault
  (`casa_aviso_lead_url` / `casa_aviso_lead_token`) e os secrets da function
  (`LEAD_WEBHOOK_TOKEN`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `GEMINI_API_KEY`,
  `SITE_URL`). **Aviso que não chega quase sempre é um desses valores, não a migration:** na
  estreia foram dois, em sequência — a URL do Vault apontando pro endereço do *painel* em vez
  do endpoint da function (o `pg_net` registra isso como `status_code` **nulo** com
  `error_msg` "Couldn't resolve host name", não como 404) e o `TELEGRAM_CHAT_ID` apontando pra
  um chat que o bot não enxergava (`400 chat not found`, que a function devolve como 500). O
  caminho de diagnóstico está no apêndice do `supabase/functions/README.md`.
  > **Pendência conhecida:** o `gemini-2.5-flash-lite` do default responde **404** pra chave
  > em uso, então o aviso chega **sem** o bloco de leitura da IA. Não impede nada (o Gemini é
  > opcional por desenho) e o conserto é secret, não código: `GEMINI_MODEL` com um nome que a
  > chave aceite.
- **Banco em dia (18/ago/2026, fim do dia):** a leva **`0049` → `0051`** foi aplicada no
  mesmo dia da `0048`, com o front indo junto pra `main`. **Não há migration pendente**, e a
  numeração livre pra próxima, naquele dia, era a **`0052`**. As três (preço do clube, os
  dois brunches como voucher, e o aniversário travado) **não pedem re-deploy de Edge
  Function nenhuma**: elas vivem inteiras no banco e no front, e nenhuma function chama as
  RPCs delas. O que ficou fora do código, e é decisão da casa: **ajustar no painel do Asaas
  o valor das assinaturas antigas** (assinatura viva mantém o `value` do dia em que nasceu,
  então quem entrou antes segue pagando R$49,90 até alguém mudar lá).
- **Banco em dia (18/ago/2026):** o humano aplicou a **`0048_casa_club`** em 18/ago, e o
  front dela foi pra `main` no mesmo dia (as duas juntas de propósito, ver a lição da 0047
  logo abaixo).
  As três Edge Functions que a leva do clube tocou (`create-checkout-session`,
  `downgrade-subscription`, `asaas-webhook`) foram **re-deployadas em 18/ago/2026**, então a
  trava do `vendavel`, a recusa do upgrade/downgrade e a promoção de categoria no pagamento da
  renovação já estão valendo em produção. **A leva do clube está inteira no ar.**
- **Banco em dia (17/ago/2026):** o humano aplicou a leva `0017` → `0041` no
  SQL Editor (as `0040` e `0041` em 13/ago), a leva **`0042` → `0046`** e a **`0047`**, as
  duas em 17/ago. A numeração livre pra próxima, naquele dia, era a
  **`0048`**. O
  front correspondente está **todo na `main`**, incluindo o da `0047` (entrou pelo merge
  `813bb88`). Houve uma janela, entre aplicar a `0047` e esse merge, em que quem NÃO era o
  dono não enxergava aba nenhuma no console de produção: o front antigo perguntava por
  `pode('pedidos')` enquanto a `admin_minhas_permissoes` já devolvia `pedidos.ver` (o dono
  passava porque o `tudo` dele curto-circuita a checagem), e a ponte da `permissoes_legado`
  segura as FUNÇÕES, não a lista de abas que o front monta. **Lição:** migration que muda o
  formato do slug de permissão e o front que lê esse slug têm que ir juntos pra produção. O
  `asaas-webhook` foi re-deployado na mesma data (é ele quem usa o status `'estornado'` da
  `0035`). A **senha do adm master foi trocada de verdade em 12/ago/2026**, então a trava
  da `0032` está destravada e o console responde. Pra conferir o banco a qualquer momento,
  rodar `scripts/check-migrations.sql` no SQL Editor.
- **`0015_avatar` — APLICADA em 29/jul/2026.** Bucket `avatares` no Storage (público, limite de **3 MB**, só `image/jpeg|png|webp`), coluna `profiles.avatar_url` e as policies de `storage.objects` (leitura pública; escrita/troca/apagar só na pasta `{auth.uid()}/`). É o que faz a foto de perfil subir.
- **`0016_sessoes` — APLICADA em 29/jul/2026.** Funções `minhas_sessoes()`, `encerrar_sessao(uuid)`
  e `encerrar_outras_sessoes()` (SECURITY DEFINER, `search_path` fixo, `revoke` de `anon`/`public`,
  `grant` só a `authenticated`). Existem porque o schema `auth` **não é exposto pelo PostgREST** —
  sem elas o client não consegue ler `auth.sessions`. Dono sempre de `auth.uid()`, sessão atual
  sempre da claim `session_id` do JWT: o client nunca diz de quem é a sessão. É o que alimenta a
  lista de aparelhos conectados no `/conta/perfil` (sem ela a tela cai no fallback "sair de todos
  os aparelhos").
- **`0019_presentes` — APLICADA em 10/ago/2026.** "Presentear um plano": tabela
  `gift_subscriptions` (+ RLS: comprador/quem-resgatou lê o próprio), coluna
  `subscriptions.presente_id` (marca a assinatura vinda de presente), e as RPCs
  SECURITY DEFINER `marcar_presente_pago(uuid,text)` (webhook gera o código no pagamento)
  e `resgatar_presente(uuid,text)` (resgate atômico com lock). **As Edge Functions já foram
  deployadas em 03/ago/2026** (`create-checkout-session`, `asaas-webhook` com
  `--no-verify-jwt`, e a nova `resgatar-presente`). **No ar:** migration aplicada em
  10/ago/2026, front na `main`; nenhum evento novo no webhook (usa
  `CHECKOUT_PAID/EXPIRED/CANCELED`).
- **`0020_mural` — APLICADA em 10/ago/2026.** "Mural do Casa": tabela
  `mural_notes` (recado curto ≤240, `autor_nome` snapshot, `status` aprovado|oculto) com
  RLS — **leitura pública** dos `aprovado` (o `/o-casa` é aberto; autor vê os próprios,
  staff vê tudo), **escrita só via Edge Function** (deny-by-default pro client), autor
  apaga o próprio recado, staff modera (ocultar/apagar) — **"modera" vira verdade só com a
  `0036`**, que barra o staff de reescrever `texto`/`autor_nome`/`user_id`; a policy daqui,
  sozinha, libera a linha inteira. Function **nova** `postar-mural`
  (**já deployada em 03/ago/2026**): exige JWT, valida **assinante vigente** via
  `getEffectiveSubscription` (perk exclusivo de assinante, igual aos pontos), sanitiza o
  texto, anti-flood 30s, grava via service_role. Front: seção no `/o-casa` (post-its na
  **seção escura**, no lugar do antigo selo "Feito no Casa", que saiu da página) +
  `initMuralPage` (lê a parede público; compose só pra assinante; deslogado/sem-plano vê
  CTA pros planos; leitura tolerante se a migration ainda não foi aplicada). **No ar:**
  migration aplicada em 10/ago/2026, front na `main`.
- **`0021_indicacoes` — APLICADA em 10/ago/2026.** "Indica um amigo": coluna
  `profiles.referral_code` (unique), tabela `referrals` (`referred_id` UNIQUE, `status`
  pendente|premiado|invalido) com RLS (lê só o que fez/recebeu; sem escrita pelo client), e
  as RPCs `meu_codigo_indicacao()`/`registrar_indicacao(text)` (granted a `authenticated`,
  usam `auth.uid()`) + `premiar_indicacao(uuid,int,int)` (granted só a `service_role`,
  idempotente pendente→premiado, credita os dois no ledger). O `asaas-webhook` (**já
  deployado em 03/ago/2026**) chama `premiar_indicacao` no primeiro pagamento do indicado;
  valores dos pontos são FICTÍCIOS nas constantes do webhook. Front tolerante à migration
  pendente. **No ar:** migration aplicada em 10/ago/2026, front na `main`. Ver "Indica
  um amigo" acima.
- **`0022_avisos` — APLICADA em 10/ago/2026.** "Recado da casa": tabela
  `avisos_casa` (RLS: leitura pública só do vigente por `ativo`+janela; owner vê tudo) +
  3 RPCs SECURITY DEFINER `is_owner()` (`admin_avisos_listar`/`admin_aviso_salvar`/
  `admin_aviso_remover`) — sem escrita pelo client. Front: `renderAvisoBar` (tarja no topo,
  toda página) + aba **recados** no console (owner-only). Tolerante à migration pendente.
  **No ar:** migration aplicada em 10/ago/2026, front na `main`. Ver "Recado da casa" acima.
- **`0023_trilha` — APLICADA em 10/ago/2026.** "A trilha do Casa": tabela
  `playlists_casa` (RLS leitura pública só das ativas; owner vê tudo; índice único parcial
  = uma `tocando` por vez) + 3 RPCs SECURITY DEFINER `is_owner()` (`admin_trilha_listar`/
  `salvar`/`remover`). Front: `initTrilha` (home) com `spotifyEmbed` trancando o src em
  `open.spotify.com/embed` + aba **trilha** no console (owner-only). Tolerante à migration
  pendente. **No ar:** migration aplicada em 10/ago/2026, front na `main`. Ver "A trilha
  do Casa" acima.
- **`0024_perfil_publico` — APLICADA em 10/ago/2026.** "Meu cantinho": colunas
  `profiles.perfil_publico`/`handle` + RPCs `definir_perfil_publico(bool)` (dono liga/desliga,
  exige assinante) e `perfil_publico(text)` (leitura pública anon, payload seguro curado —
  NÃO é RLS na profiles). Front: página `/gente/{handle}` (rewrite no vercel.json + middleware
  do dev) + seção "meu cantinho" no `/conta/perfil`. Tolerante à migration pendente.
  **No ar:** migration aplicada em 10/ago/2026, front na `main`. Ver "Meu cantinho" acima.
- **`0025_brinde_aniversario` — APLICADA em 10/ago/2026.** "Hoje o Casa é teu":
  tabela `brindes_aniversario` (UNIQUE `(user_id, ano)`, RLS: dono lê o próprio, staff com
  `resgates` lê todos, escrita só via RPC) + 4 RPCs SECURITY DEFINER
  (`meu_brinde_aniversario`/`resgatar_brinde_aniversario` a `authenticated`;
  `admin_brindes_listar`/`admin_brinde_usar` gated por `tem_permissao('resgates')`). Front:
  card no `/conta/perfil` + aba "aniversários" no console. Tolerante à migration pendente.
  **No ar:** migration aplicada em 10/ago/2026, front na `main`. Ver "Hoje o Casa é teu
  — brunch de aniversário" acima.
- **`0026_agenda` — APLICADA em 10/ago/2026.** "A agenda do Casa": acorda a tabela
  `events` (0004) com colunas `local`/`updated_at` + tabela `event_rsvps` (PK composta, RLS
  dono/owner, escrita só via RPC) + 6 RPCs SECURITY DEFINER (`agenda_proximos` pública;
  `confirmar_presenca`/`cancelar_presenca` a `authenticated`, RSVP perk de assinante com lock
  anti-estouro de vaga; `admin_evento_listar/salvar/remover` gated por `is_owner()`,
  owner-only). Front: seção "a agenda do Casa" na home (`initAgenda`) + aba "agenda" no
  console. Tolerante à migration pendente. **No ar:** migration aplicada em 10/ago/2026,
  front na `main`. Ver "A agenda do Casa — encontros" acima.
- **`0027_cardapio_favoritos` — APLICADA em 10/ago/2026.** "Teus favoritos":
  tabela `cardapio_favoritos` (PK `(user_id, item_slug)`, `item_nome` snapshot,
  `user_id` default `auth.uid()`) com RLS de **escrita direta pelo client** (select/insert/
  delete own, sempre `auth.uid()` — dado benigno, fora da lista de sensíveis) + RPC
  `admin_cardapio_favoritos()` (SECURITY DEFINER, `tem_permissao('relatorios')`, agrega por
  slug com o nome mais frequente). Front: corações no `/cardapio` + bloco "teus favoritos"
  (`initCardapioFavoritos`, slug derivado do nome) + aba "favoritos" no console. Tolerante à
  migration pendente. **No ar:** migration aplicada em 10/ago/2026, front na `main`. Ver
  "Teus favoritos no cardápio" acima.
- **`0028_agenda_quem_vai` — APLICADA em 10/ago/2026.** "Quem vai": reescreve a
  função `agenda_proximos` (DROP+CREATE, muda a assinatura) pra devolver `vao_publicos`
  (jsonb) — os presentes que ligaram o perfil público (handle/nome/avatar, curado, só campos
  já públicos). Sem tabela nova, sem permissão nova. Front: avatares no card da agenda
  (`avatarBolha`). **Depende da `0026` estar aplicada** (usa `event_rsvps`). Tolerante:
  sem ela, `agenda_proximos` fica na versão da 0026 e a home só não mostra rostos. **No
  ar:** migration aplicada em 10/ago/2026, front na `main`. Ver "Quem vai" na seção da
  agenda.
- **`0029_loja_desejos` — APLICADA em 10/ago/2026.** "Ficou pra depois": tabela
  `loja_desejos` (PK `(user_id, produto_slug)`, `produto_nome` snapshot, `user_id` default
  `auth.uid()`) com RLS de **escrita direta pelo client** (select/insert/delete own, sempre
  `auth.uid()` — dado benigno, fora da lista de sensíveis) + RPC `admin_loja_desejos()`
  (SECURITY DEFINER, `tem_permissao('relatorios')`, agrega por slug com o nome mais
  frequente). Front: corações no catálogo/produto + tirinha "ficou pra depois" na `/loja` e
  espelho no `/conta/perfil` (`initLojaDesejos`) + aba "desejos" no console. Tolerante à
  migration pendente. **No ar:** migration aplicada em 10/ago/2026, front na `main`. Ver
  "Ficou pra depois (lista de desejos da loja)" acima.
- **`0030_avisos_reposicao` — APLICADA em 10/ago/2026.** "Volta pra vitrine":
  tabela `avisos_reposicao` (PK `(user_id, produto_slug)`, `produto_nome` snapshot,
  `user_id` default `auth.uid()`) com RLS de **escrita direta pelo client** (select/insert/
  delete own — dado benigno, fora da lista de sensíveis) + RPC `admin_avisos_reposicao()`
  (SECURITY DEFINER, `tem_permissao('relatorios')`, agrega por slug com o nome mais
  frequente). Front: selo "esgotado" + "me avisa quando voltar" nos produtos `disponivel:
  false`, tirinha "voltou pra vitrine" na `/loja` e no `/conta/perfil` (`initReposicao`) +
  aba "esperando" no console. Tolerante à migration pendente. **No ar:** migration
  aplicada em 10/ago/2026, front na `main`. Ver "Volta pra vitrine" acima.
- **`0031_lista_espera` — APLICADA em 10/ago/2026.** "Avisa quando a loja abrir":
  tabela `lista_espera` (`email` unique com CHECK de formato/tamanho, `origem` = o caminho
  da página, sem `user_id` — a graça é justamente não exigir conta) com RLS **insert-only
  pro client**: policy de INSERT pra `anon` e `authenticated` repetindo os limites no
  `with check`, e **nenhuma policy de select** (deny-by-default), então ninguém lê a lista
  pelo client. Leitura só pela RPC `admin_lista_espera(limite)` (SECURITY DEFINER,
  `tem_permissao('relatorios')`). Front: campinho no rodapé (`initListaEspera`) + aba
  "lista de espera" no console. **No ar:** migration aplicada em 10/ago/2026, front na
  `main`. **A 0034 revogou a policy de INSERT desta migration** e trocou o insert direto
  do client pela RPC `entrar_na_lista_espera`; as duas estão aplicadas. Ver "Privacidade,
  termos e a lista de espera" acima.
- **`0032_senha_inicial_master` — APLICADA em 10/ago/2026.** Fecha o buraco de a
  senha inicial do adm master só ser cobrada na tela: coluna `profiles.senha_inicial_hash`
  (backfill pro master que ainda não trocou), função `senha_inicial_pendente()` e o mesmo
  `and not senha_inicial_pendente()` acrescentado a `is_owner`, `is_gerente_or_owner`,
  `is_staff`, `tem_permissao` e `pode_entrar_no_console` — enquanto a senha for a inicial,
  a conta não tem privilégio em lugar nenhum (nem RLS, nem `admin_*`). `admin_senha_alterada`
  passa a **conferir** que o hash mudou antes de carimbar (era por aí que dava pra desarmar
  a tela sem trocar nada) e `admin_minhas_permissoes` segue devolvendo `console:true` pro
  master travado, senão ele não alcançaria o formulário de troca. Mais a RPC
  `registrar_senha_inicial(uuid)` (só `service_role`) que o script chama. A **senha do
  master foi trocada em 12/ago/2026**, então a trava está destravada. Vale lembrar como
  ela funciona pra próxima vez: enquanto a senha for a inicial (inclusive a sorteada por um
  `--resetar-senha`), o banco não reconhece privilégio nenhum da conta, e quem destrava é a
  troca de verdade, pela tela obrigatória do console. Só quem perdeu a senha precisa do
  script, e aí é `npm run criar-adm-master -- --resetar-senha` (o `--` solto é
  obrigatório, senão o npm engole a flag e o script não reseta nada).
- **`0033_perfil_publico_trava` — APLICADA em 10/ago/2026.** Trigger
  `prevent_perfil_publico_tamper` (mesmo desenho do `prevent_points_tamper`, com GUC
  `casa.trusted_perfil`): `profiles.perfil_publico` e `profiles.handle` param de ser
  graváveis por PATCH direto — a `profiles_update_self` libera a linha inteira e RLS não
  restringe coluna, então dava pra publicar um cantinho **sem plano** e tomar qualquer
  handle livre. A `definir_perfil_publico` volta a ser a única porta (acende a GUC) e passa
  a recusar handles reservados (`casa`, `contato`, `equipe`…), pra ninguém virar
  `/gente/casa`. **No ar:** migration aplicada em 10/ago/2026, front na `main`.
- **`0034_lista_espera_rpc` — APLICADA em 10/ago/2026.** Tira a policy de INSERT
  da `lista_espera` e põe a RPC `entrar_na_lista_espera(email, origem)` (SECURITY DEFINER,
  granted a `anon`+`authenticated`) com o `on conflict do nothing` por dentro e **resposta
  constante**. Sem isso o formulário respondia 409 pra e-mail já cadastrado e 201 pra novo,
  virando sonda de quem está na lista pra qualquer um com a anon key. **No ar:**
  migration aplicada em 10/ago/2026, front na `main`.
- **`0035_orders_estornado` — APLICADA em 10/ago/2026.** Acrescenta `'estornado'`
  ao CHECK de `orders.status`. É o estado que faltava pro webhook marcar a compra devolvida:
  `'cancelado'` é o pedido que nunca foi pago, e usar ele apagaria a diferença no histórico.
  O `asaas-webhook`, que é quem marca o pedido como `'estornado'`, foi **re-deployado em
  10/ago/2026** (`npx supabase functions deploy asaas-webhook --no-verify-jwt`).
- **`0036_mural_e_cantinho_estritos` — APLICADA em 10/ago/2026.** Os
  dois apertos que a auditoria apontou e que ficaram de fora da leva 0032–0035 por mexerem
  em comportamento, não em falha alcançável pelo cliente:
  **(a) mural** — a `mural_update_staff` (0020) libera UPDATE da linha inteira pra quem é
  `is_staff()`, e RLS não restringe coluna, então o staff podia **reescrever** `texto`,
  `autor_nome` e `user_id`, não só ocultar: dava pra pôr na parede uma frase que a pessoa
  não escreveu, assinada com o nome dela. Trigger `prevent_mural_content_tamper` barra as
  três colunas vindas de sessão logada; mexer no `status` (moderar) segue liberado e a
  `postar-mural` não é afetada (escreve com service_role, `auth.uid()` nulo). Nenhuma tela
  do console modera mural hoje, então não quebra fluxo nenhum.
  **(b) cantinho** — a `perfil_publico(handle)` passa a exigir `tier_slug`, a mesma régua
  que a `definir_perfil_publico` usa pra deixar ligar. Ver "Meu cantinho" acima.
- **`0037_dicas_sem_travessao` — APLICADA em 12/ago/2026.** Cinco das nove
  **dicas** de conquista semeadas pela `0010` nasceram antes da regra de tom de voz que
  proíbe travessão em texto visível, e o `—` aparecia no card bloqueado da
  `/conta/conquistas` e no tooltip dos emblemas do painel. Este arquivo troca por vírgula.
  Só texto: nenhuma coluna, policy, função ou permissão muda; o front não precisou mudar,
  porque a dica vem do banco.
- **`0038_conquistas_do_cardapio` — APLICADA em 12/ago/2026.** 50 conquistas
  novas, uma por item ou combinação real do cardápio impresso, nas 16 seções e na ordem
  do papel. **Elas nascem DESLIGADAS (`ativo = false`)**: ficam guardadas no banco e
  invisíveis no site, pra o placar da `/conta/conquistas` não pular de "x/9" pra "x/59"
  com 50 cadeados que nada abre. O front filtra por `ativo = true` e o
  `check_achievements` também, então desligada não aparece nem desbloqueia. Pra acender no
  dia da integração: `update public.achievements set ativo = true where slug like
  'cardapio-%';` (o `on conflict` da migration não mexe no `ativo`, então reaplicar o
  arquivo depois não apaga as 50 da tela). **Elas só desbloqueiam quando a frente de caixa
  entrar:** o `check_achievements` (0009) só avalia o que o banco
  enxerga, e de consumo ele só enxerga a LOJA (`orders`/`order_items` de produto); o
  `/cardapio` é informativo, sem carrinho e sem SKU por item. Como o PDV vai mandar o
  consumo por webhook (a `pos_webhook_events` da 0004 e o `POS_WEBHOOK_SECRET` estão
  reservados desde a Fase 3), **os critérios já vêm escritos no formato que esse webhook
  vai alimentar**, em vez de um `manual` genérico, em três tipos novos:
  `menu_item` (consumiu qualquer um da lista), `menu_item_distintos` (N itens diferentes,
  é o "Tour do Matcha" e o "Passa Café") e `menu_item_combo` (um de cada grupo na mesma
  visita, é o "bolo e cookie" e o "brownie com sorvete"). O `case` do
  `check_achievements` manda tipo desconhecido pro mesmo lugar que manda `manual` (não
  desbloqueia, não estoura), então **aplicar agora é seguro e não muda comportamento**; no
  dia D não se reescreve conquista nenhuma, só se ensina a função a ler os três tipos. Os
  `itens` usam o slug do nome do item no cardápio (mesma regra do `slugify` do
  `cardapio_favoritos`), com os quatro nomes repetidos entre seções qualificados pelo
  título da seção (`bagel-classico`, `croissant-classico`,
  `sanduiches-carne-de-panela`), do mesmo jeito que o front deriva; o PDV vai precisar
  de um de-para do código dele pra esses slugs. **Este arquivo escreveu um deles no
  singular (`sanduiche-carne-de-panela`), e quem acerta é a `0039`** (o arquivo aqui não
  se toca, já foi aplicado). Só conteúdo: nenhuma coluna, policy, função ou permissão muda. No front,
  a única mudança é cosmética: `ICONES_CONQUISTA` ganhou os ícones do cardápio (croissant,
  cake-slice, leaf, wine…), senão os 50 sairiam todos com o troféu genérico.
- **`0039_slug_carne_de_panela` — APLICADA em 12/ago/2026.** Uma linha: troca o
  critério da conquista `cardapio-carne-de-panela` de `sanduiche-carne-de-panela` pra
  `sanduiches-carne-de-panela`, que é o slug que o front deriva do título da seção
  ("Sanduíches"). Sem ela, o de-para fica com dois nomes pro mesmo prato e a conquista
  nunca abriria quando a frente de caixa entrar. Idempotente (o `where` pula a linha que já
  está certa) e não acende nenhuma das 50 (seguem `ativo = false`).
- **`0040_leads_evento` — APLICADA em 13/ago/2026.** "Faz teu evento aqui": tabela
  `leads_evento` **sem policy nenhuma** (RLS ligada = deny-by-default pro client; dado
  pessoal, então nada de escrita direta) + 3 RPCs SECURITY DEFINER:
  `registrar_lead_evento(...)` (granted a **anon**, valida no corpo, anti-flood de 30s pelo
  mesmo contato) e `admin_leads_evento`/`admin_lead_evento_status` (gated por
  `tem_permissao('relatorios')`, sem permissão nova). Front: página `/eventos` +
  `initEventosPage` + aba "eventos" no console. **A tolerância descrita aqui mudou em
  20/ago/2026:** com o redirecionamento pro WhatsApp fora, a RPC virou o único caminho, então
  falhar nela mostra o contato da casa e mantém o formulário preenchido, em vez de seguir
  adiante em silêncio. Ver "Faz teu evento aqui" acima.
- **`0041_admin_presentes` — APLICADA em 13/ago/2026.** A aba "presentes" do
  console: RPC `admin_presentes(busca, status, limite)` (SECURITY DEFINER, gated por
  `tem_permissao('resgates')`, sem permissão nova). Existe porque a `gift_select_own` da
  `0019` só deixa ler quem é parte do presente, então a casa não enxergava o que vendeu.
  **Não devolve a `mensagem`** (o bilhete é de uma pessoa pra outra). Só leitura: nenhuma
  tabela, coluna ou policy muda.
- **`0042_email_do_console` — APLICADA em 17/ago/2026.** Cinco abas do console
  (**pedidos, resgates, pessoas, equipe e aniversários**) respondiam sempre
  `structure of query does not match function result type`, com dado ou sem dado.
  **`auth.users.email` é `character varying(255)` no Supabase, não `text`** — e as seis
  funções que devolvem esse e-mail (`admin_pedidos`, `admin_resgates`, `admin_usuarios`,
  `admin_equipe`, `admin_buscar_pessoa` da 0017; `admin_brindes_listar` da 0025) declaravam
  a coluna como `text` no `returns table`. O `return query` do plpgsql compara os tipos um a
  um e **exige igualdade exata**: varchar e text são parentes, não são o mesmo tipo, e a
  função morre **antes de devolver a primeira linha** (por isso o erro aparecia até com a
  tabela vazia, e por isso essas abas nunca funcionaram desde a 0017). A correção é
  `u.email::text`, seis vezes; o resto do corpo das funções é idêntico. Nenhuma tabela,
  coluna, policy ou permissão muda, e o front não precisou mudar.
  > **Como isto foi verificado, e como verificar da próxima vez:** dá pra rodar as
  > migrations inteiras num Postgres local antes de aplicar no Supabase, com uns poucos
  > stubs (`create role anon/authenticated/service_role`, um schema `auth` com a
  > `users`/`sessions` e `auth.uid()`). Da `0001` à `0042` tudo roda; só a `0015` (bucket do
  > Storage) e a `0028` (que depende da coluna `avatar_url` criada pela 0015) precisam do
  > Supabase de verdade. Erro de tipo em `returns table` **não aparece na criação da
  > função**, só na primeira chamada, então ler o SQL não basta: tem que chamar.
- **`0043_pautas` — APLICADA em 17/ago/2026.** O quadro da equipe: tabela `pautas`
  (deny-by-default, RLS ligada e nenhuma policy) + 5 RPCs SECURITY DEFINER gated por
  `tem_permissao('pautas')`, e a permissão `'pautas'` entrando no **whitelist fechado por
  CHECK da `0017`** (a primeira vez que aquele CHECK muda; o `do $$` acha a constraint pelo
  conteúdo em vez de confiar no nome). Apagar exige ser quem escreveu, ou o owner. Ver
  "O quadro da casa" acima.
- **`0044_mural_pela_permissao` — APLICADA em 17/ago/2026.** A aba do mural
  escrevia direto pela RLS, e as policies da `0020` falam em `is_staff()` — que é papel,
  não permissão. Como o console **concede permissão sem nunca trocar o papel de ninguém**,
  quem recebia `'usuarios'` via só os recados aprovados e batia na RLS ao tentar esconder
  ou apagar: a aba funcionava apenas pro adm do Casa. Três RPCs
  (`admin_mural_listar`/`_status`/`_remover`) gated por `tem_permissao('usuarios')`
  resolvem na porta certa. **Promover a pessoa a `staff` NÃO era a saída**: abriria junto,
  pela RLS, toda tabela que confia em `is_staff()` (pedidos, resgates, brindes), e
  permissão de moderar mural não é permissão de ler o caixa. As policies da `0020` e a
  trigger da `0036` seguem intactas.
- **`0045_quadros` — APLICADA em 17/ago/2026.** O quadro de pautas vira board:
  tabelas `pauta_quadros`, `pauta_grupos` e `pauta_updates` (as três deny-by-default), as
  colunas `quadro_id`/`grupo_id`/`ordem` na `pautas`, o estado `'travada'` entrando no
  CHECK, e 15 RPCs gated em `tem_permissao('pautas')`. **Faz backfill**: as pautas que já
  existem caem num quadro "o quadro da casa" com um grupo "o dia a dia", sem perder nada,
  e só depois disso o `quadro_id` vira NOT NULL. A `admin_pauta_salvar` e a
  `admin_pautas_listar` da 0043 são **dropadas e recriadas** (a assinatura mudou, e
  acrescentar parâmetro com default criaria uma sobrecarga que o PostgREST poderia
  escolher, gravando pauta sem quadro). Leitura em `returns jsonb`, ver "O quadro da casa".
- **`0046_permissao_por_pagina` — APLICADA em 17/ago/2026.** Abre o whitelist de
  permissões pra **19 slugs, um por página** (mais a ação `entregas`), e troca a trava de
  **21 funções** pra a permissão da própria página. O corpo das 21 é idêntico ao que já
  estava no ar (foi extraído da última versão de cada uma); só a linha do `if not
  public...` muda. As três funções de aba do dono deixam de perguntar `is_owner()` e passam
  a perguntar `tem_permissao(...)`, o que **não tira nada do dono** e passa a permitir
  delegar. Tem **backfill**: quem já tinha `resgates`, `usuarios` ou `relatorios` recebe,
  uma a uma, as permissões que saíram de dentro delas, então ninguém perde acesso na
  virada.
- **`0047_permissoes_por_secao` — APLICADA em 17/ago/2026.** Permissão por **seção do
  site** e por **ação**: as tabelas de catálogo `permissao_secoes` › `permissao_paginas` ›
  `permissoes` (8 seções, 20 páginas, 43 permissões `<pagina>.<acao>`), o FK vindo da
  `staff_permissions` no lugar do CHECK escrito à mão, a `permissao_canonica` traduzindo os
  slugs da 0046, e a `tem_permissao` com hierarquia (arrumar > mexer > ver, dentro da mesma
  página). Reescreve **25 funções** só pra separar quem mexe de quem enxerga (o corpo é
  idêntico ao que está no ar, extraído da última versão de cada uma), reapronta as **8
  policies** que falavam os slugs velhos, e cria **12 funções novas**: as duas páginas que
  faltavam (`admin_assinaturas`, `admin_pontos_extrato`/`_pessoas`) e os oito consertos do
  "arrumar". Tem **backfill**, então ninguém perde acesso na virada.
  > **A ordem interna dela é frágil de propósito e está comentada no arquivo:** o CHECK da
  > 0046 tem que sair ANTES do backfill (senão `pedidos.ver` é valor proibido e o insert
  > morre na primeira linha), e o FK só entra DEPOIS de as linhas velhas saírem. Foi
  > exatamente esse o defeito que o teste com dado de verdade pegou, e que um banco vazio
  > não teria mostrado.
  > **Como foi verificada:** as 48 migrations rodaram do zero num Postgres local (os stubs
  > do `auth`/`storage` que o CLAUDE.md já descrevia na 0042), a 0047 rodou **duas vezes**
  > pra provar idempotência, o corpo das 25 funções reescritas foi comparado com
  > `pg_get_functiondef` antes e depois (**só a linha da trava mudou, nas 25**), e as 46
  > funções do console foram **chamadas** por cinco pessoas de permissões diferentes: só
  > enxerga, mexe, arruma, o dono e um cliente sem nada. 230 chamadas, todas com o
  > allow/deny esperado.
- **`0048_casa_club` — APLICADA em 18/ago/2026.** O clube vira **uma
  assinatura só** e as quatro categorias passam a ser **tempo de casa**: colunas
  `tiers.vendavel` (só a de entrada é comprável, com índice único garantindo "uma só") e
  `tiers.meses_min`; reseed das quatro (mesmo preço, mesmo desconto 10%, mesmo
  `points_multiplier = 1.00`, as duas duplas de colunas de 0001 e 0004 andando juntas); e
  cinco funções: `dias_de_casa`/`meses_de_casa` (**união** dos períodos das assinaturas, não
  a soma crua), `categoria_por_tempo`, `sincronizar_categoria` (escreve o `tier_slug` só
  quando muda, acende a GUC do `prevent_points_tamper`, carimba a conquista do marco e
  registra no `audit_log`) e `meu_clube` (a leitura da tela, por `auth.uid()`). As três
  primeiras ficam **fora do alcance do client** (recebem `user_id` por parâmetro; quem serve
  o front é a `meu_clube`). Idempotente.
  > **Como foi verificada:** as 49 migrations rodaram do zero num Postgres local (os mesmos
  > stubs de `auth`/`storage` que a 0042 já descrevia), a 0048 rodou **duas vezes** pra provar
  > idempotência, e as funções foram **chamadas** com dado de verdade: assinatura corrida,
  > pausa e volta (união = 160 dias, não 340), presente sobreposto a assinatura ativa (100
  > dias, não 130), quem nunca assinou (0), as bordas do `categoria_por_tempo` (0, 2, 3, 5, 6,
  > 11, 12, 400 e um negativo), a promoção passando pela trigger `prevent_points_tamper` numa
  > sessão `authenticated`, a segunda chamada não gerando linha nova de auditoria, e o índice
  > recusando uma segunda categoria vendável.
- **`0049_preco_do_clube` — APLICADA em 18/ago/2026.** Uma linha: a assinatura passa de R$49,90 pra
  **R$88,90** (`preco_centavos = 8890`). **As quatro categorias andam juntas**, porque elas
  custam o mesmo desde a 0048 (categoria é tempo, não preço) e a `create-checkout-session` lê
  o `preco_centavos` do tier pra montar o valor do checkout e do presente: deixar as três não
  vendáveis com o preço velho criaria uma escada fantasma no banco, pronta pra cobrar errado
  no dia em que alguma voltasse a ser vendável. **Não toca no Asaas**: assinatura viva mantém
  o `value` com que nasceu.
- **`0050_brunches` — APLICADA em 18/ago/2026.** Os dois brunches viram voucher com código: tabela
  `brunches_mensais` (UNIQUE `user+ano+mês`, RLS dono/`aniversarios.ver`, escrita só por RPC),
  as RPCs `meu_brunch_mensal`/`resgatar_brunch_mensal`, a **reescrita** de
  `meu_brinde_aniversario`/`resgatar_brinde_aniversario` (sem exigir plano, janela de 7 dias),
  o helper `aniversario_no_ano` (o 29/02) e três funções de console
  (`admin_brunches_listar` em jsonb com os dois tipos, `admin_brunch_usar`,
  `admin_brunch_arrumar`). Idempotente.
  > **Como foi verificada:** rodou num Postgres local depois das 49 anteriores e as funções
  > foram **chamadas** com dado de verdade: aniversário hoje sem plano nenhum (passa),
  > 5 dias atrás (passa), 20 dias atrás e ainda no mês (recusa, que é a mudança da régua),
  > o 29/02 em ano comum e bissexto, o mensal de quem assina e a recusa de quem não assina,
  > a idempotência dos dois resgates, a lista do console juntando os dois tipos e filtrando
  > por tipo, a baixa e o desfazer, o tipo inválido recusado, e a RLS mostrando o brunch só
  > pro dono. **Um bug foi pego aí:** a `admin_brunches_listar` criava sem reclamar e
  > estourava na primeira chamada (o `order by` do `jsonb_agg` olhava a chave do jsonb em vez
  > da coluna do subselect). Ler o SQL não teria pego.
- **`0051_nascimento_travado` — APLICADA em 18/ago/2026.** O aniversário entra no cadastro e para de ser
  editável: `handle_new_user` passa a gravar `nascimento` do metadata (com parse tolerante e
  régua de sanidade) e a trigger `prevent_nascimento_tamper` barra a troca depois de
  preenchido (nulo → data ainda passa; owner passa sempre). Ver "A data de aniversário se
  escreve uma vez" acima.
  > **Como foi verificada:** rodou no Postgres local e as regras foram **chamadas** com dado
  > de verdade: metadata com data boa (grava), com lixo (nulo), com data futura (nulo) e sem
  > o campo (nulo); cliente tentando trocar data existente (recusa), preenchendo pela primeira
  > vez (passa), tentando trocar depois disso (recusa), mandando data futura (recusa) e data
  > de 1700 (recusa); e salvar o resto do perfil sem tocar na data (passa).
- **`0052_aviso_lead_evento` — APLICADA em 19/ago/2026.** O pedido de evento passa a tocar o sino no
  Telegram da equipe: extensão `pg_net`, coluna `leads_evento.aviso_em` (rastro de quando o
  aviso saiu), a `aviso_lead_config()` (lê URL e token do **Vault**, e devolve zero linhas se
  não estiverem cadastrados) e a trigger `avisar_lead_evento` no INSERT, que chama a Edge
  Function nova `avisar-lead-evento`. **A trigger inteira vive dentro de um `exception when
  others`**, então nada no caminho do aviso pode derrubar o formulário. Teto de 20 avisos por
  hora. Idempotente. Ver "O pedido toca o sino da equipe" acima.
  > **Como foi verificada:** rodou num Postgres local com stubs de `auth`, `vault` e uma
  > extensão `pg_net` falsa que **captura o payload** em vez de mandar, aplicada **duas vezes**
  > pra provar idempotência, e as funções foram **chamadas** com dado de verdade, como `anon`:
  > sem os segredos no Vault (lead entra, nenhum aviso, nenhum erro), com os segredos (payload
  > e header conferidos um a um), o anti-flood da 0040 segurando o segundo pedido do mesmo
  > contato, o teto (25 pedidos → 25 leads gravados, 20 avisos) e **a prova de fogo: com o
  > `net.http_post` estourando exceção, o lead entra igual e sobra só um `warning`**. A Edge
  > Function passou por `deno check` e por 24 asserções com Gemini e Telegram dublados, entre
  > elas o 401 de token errado, o escape de `<script>` no nome, e o Gemini com 429 e com
  > timeout **sem impedir o aviso**.
- **`0053_rastros` — APLICADA em 03/set/2026.** "Os rastros": as tabelas
  `rastro_visitas` (a aba aberta: por onde entrou, por onde saiu, quantos
  cliques, se tinha carrinho) e `rastro_eventos` (clique e vista de seção), as
  duas **deny-by-default** (RLS ligada e nenhuma policy); a página `rastros` e a
  permissão `rastros.ver` entrando nas tabelas de catálogo da 0047 (**permissão
  nova é INSERT no catálogo, não `alter constraint`** — é o que aquela migration
  comprou), com backfill pra quem já tem `relatorios.ver`; e três funções:
  `registrar_rastro(jsonb)` (a única porta de escrita, aberta a **anon**, com os
  três tetos e a faxina de 180 dias sorteada por dentro),
  `admin_rastros_resumo(dias)` (gated em `rastros.ver`) e
  `admin_rastros_leads(dias, limite)` (gated em **`pedidos.ver`**, porque tem
  nome e telefone). As duas leituras são `returns jsonb`, e não `returns table`,
  pelo mesmo motivo da 0045: uma leitura composta teria duas dúzias de colunas
  declaradas pra errar, e foi um erro desses que deixou cinco abas quebradas da
  0017 até a 0042. Idempotente.
  > **Como foi verificada:** as 53 migrations rodaram do zero num Postgres 16
  > local (os mesmos stubs de `auth`/`storage` que a 0042 já descrevia; só a
  > 0015, a 0016 e a 0052 seguem precisando do Supabase de verdade), a 0053 rodou
  > **duas vezes** pra provar idempotência, e as funções foram **chamadas** com
  > dado de verdade: pulso de visita nova e de visita que já existe, a saída nova
  > ganhando da antiga e o pulso sem saída **não apagando** a que estava lá, os
  > marcos que não desligam, o `user_id` vindo de `auth.uid()` mesmo com o corpo
  > mandando o id do dono, uuid torto e jsonb que não é objeto (não gravam e não
  > estouram), caminho forjado (`https://evil.com`, `javascript:`) virando
  > 'outra', texto de 300 caracteres aparado em 80, os três tetos batendo no
  > número exato (40 por chamada, 400 por visita com o contador da visita **sem
  > divergir** do que entrou, 400 visitas novas na hora), as duas travas de
  > permissão com cinco pessoas diferentes (dono, só-rastros, rastros+pedidos,
  > cliente e deslogado) e o `anon` sem sequer poder executar as `admin_*`, e a
  > RLS recusando leitura direta das duas tabelas **até pro dono**.
  > **Um defeito foi pego aí**, e só com dado real: a lista de seções vinha
  > ordenada com `nulls first`, então seção com ZERO vista (que não é fria, é
  > sem informação) encabeçava o relatório e empurrava pra baixo justamente a
  > seção com plateia e sem toque, que é a que a casa veio ver.
  > **E o front foi rodado num navegador de verdade** (Chromium, contra um
  > servidor falso que capturava os pulsos), que pegou outros quatro: seção
  > mais alta que a janela **nunca** registrava vista (`threshold: 0.5` não
  > alcança 50% de um elemento maior que a tela), seção sem título direto virando
  > o texto "section", a grade da loja sendo batizada com o nome do primeiro
  > produto, e o `<footer>` do drawer fazendo "finalizar compra" contar como
  > clique no rodapé do site. Depois disso, os payloads que o navegador produziu
  > foram injetados no Postgres e o relatório saiu correto de ponta a ponta.
- `partners` e `tiers` têm PK = **slug**; FKs pra elas seguem a convenção `*_slug` (ex.: `profiles.tier_slug`, `rewards_catalog.partner_slug`), não `*_id`.

---

## Operação

Estas regras existem porque o custo de uma sessão agêntica se concentra em turnos
e subagentes, não em tokens de resposta. Entenda o motivo e aplique com julgamento;
não são checklist.

### Subagentes

Cada subagente refaz contexto do zero, explora, reporta, e eu releio o relatório —
o custo se multiplica e a latência também.

- Delegue apenas para investigação ampla genuinamente paralela em vários arquivos,
  ou trilhas independentes de tamanho real.
- Não delegue trabalho que se resolve em algumas chamadas de ferramenta.
- Nunca delegue para verificar o próprio trabalho: verificação pertence ao loop
  principal.
- Se um subagente resolve, use um. Mantenha a contagem baixa e não redo o trabalho
  dele depois que ele reporta.
- Ao disparar vários para trabalho independente, mande todos no mesmo bloco para
  rodarem em paralelo.

### Verificação

Você já verifica seu próprio trabalho por padrão. Não adicione um passo separado de
verificação nem revise duas vezes por precaução — isso duplica custo sem achar mais
nada. Verifique quando houver motivo concreto (teste falhou, resultado inesperado),
não por ritual.

### Escopo

Entregue o que foi pedido, no escopo pedido. Interprete ambiguidade como um colega
cuidadoso faria: decisões pequenas (nome de variável, valor default, qual de duas
abordagens equivalentes) você toma e menciona; mudança de escopo ou ação destrutiva
você pergunta antes.

Se achar que o pedido está errado ou que existe caminho melhor, diga em uma frase e
siga com o pedido — não estreite, alargue nem transforme por conta própria. Termine a
tarefa inteira; se algo ficou de fora, diga o que e por quê em vez de reportar
"pronto".

Não adicione features, refactor, abstração, error handling ou fallback além do que a
tarefa exige. Correção de bug não pede faxina em volta.

### Comunicação

Seu texto entre chamadas de ferramenta é o que eu leio — eu não vejo seu raciocínio
nem os resultados crus.

- Antes da primeira ferramenta, uma frase do que você vai fazer.
- Durante, atualize só quando achar algo que importa ou mudar de direção.
- Não narre ação rotineira ("agora vou...", "deixa eu ver...").
- Ao terminar, abra pelo resultado — a primeira frase responde "o que aconteceu".
  Detalhe depois.
- Legível vale mais que curto. Encurte cortando o que não muda minha decisão, não
  comprimindo em fragmentos, setas (`A → B → falha`) ou abreviação. Escreva frases
  completas com os termos por extenso.
- Se corrigir um erro seu, corrija e siga. Só comente quando o erro muda o que eu
  faria; sem pedido de desculpas, sem ruminar.
