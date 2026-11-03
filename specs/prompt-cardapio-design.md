# Prompt pronto — pedir pro Claude desenhar a página `/cardapio`

Copia tudo o que está dentro do bloco abaixo e cola numa conversa nova com o Claude
(claude.ai, modo design/artifacts). O prompt é autocontido: leva paleta, tipografia,
conteúdo real e as travas técnicas do projeto, então não precisa anexar o repositório.

---

```
Preciso que tu desenhe a página de cardápio de um café. Quero direção visual e um
mockup navegável, não código de produção, mas o desenho tem que caber no sistema que
já existe (vou traduzir pro projeto depois).

## O lugar

Casa Coffee Colab, um café-casa de encontros em Novo Hamburgo/RS, no bairro Hamburgo
Velho. A frase da casa: "o Casa é café, afeto e comida boa". Não é cafeteria de
especialidade fria e minimalista, nem padaria de bairro genérica: é casa de amigo,
madeira, papel, gente sentada sem pressa. O site inteiro tem cara de revista impressa
pequena, não de app.

O tom de voz é acolhedor, autoral, poético contido, urbano-afetivo, humilde. Trata a
pessoa por "tu" e fala de si como "a gente". Chamadas gentis do tipo "passa aqui?",
"fica um pouco". Evita sempre as palavras gourmet, luxo, premium, exclusivo, hype,
trend, e qualquer imperativo agressivo ("aproveita já!", "corre!"). Nada de
gamificação com cara de cassino. E, em texto que a pessoa lê na tela, não usa
travessão como pontuação, usa vírgula.

## A página de hoje (o ponto de partida)

É a `/cardapio`: um menu literário, informativo, SEM carrinho e SEM foto por prato.
Cada item é só nome, uma linha de descrição com um pouco de poesia, e preço. Hoje ela
é uma pilha de listas com filete separando os itens, honesta mas monótona: rola muito,
todas as seções se parecem, e o encanto do texto se perde no meio da repetição.

Estrutura e conteúdo reais (usa esse conteúdo no mockup, não inventa lorem):

Abertura
  sobrelinha: O que a casa serve
  título: Cardápio
  linha de apoio: "Um cardápio pra ler devagar. Cada prato tem a sua história, a gente
  só escreveu a primeira linha."

Cafés & Bebidas
  Espresso, R$ 7,00, "curto, intenso, o começo de tudo."
  Coado do dia, R$ 9,00, "o grão da vez, passado no pano, sem pressa."
  Cappuccino, R$ 12,00, "espuma que abraça, canela pra despedir."
  Alma do Casa, R$ 13,00, "nosso blend autoral, encorpado, de final doce."
  Matchá da Manhã, R$ 15,00, "verdinho, cremoso, pra começar em paz."
  Chocolate quente, R$ 14,00, "o cobertor dos dias de chuva, em caneca."

Comidas & Brunch
  Brunch de Domingo, R$ 59,00, "a mesa farta pra ficar a manhã inteira."
  Tosta de fermentação natural, R$ 26,00, "pão que leva dois dias e some em dois minutos."
  Ovos mexidos do Casa, R$ 22,00, "cremosos, com cebolinha da horta do vizinho."
  Pão na chapa, R$ 12,00, "manteiga derretendo, o clássico que não erra."

Que Seja Doce
  Bolo da vó (fatia), R$ 14,00, "a receita de sempre, do jeito que tu lembra."
  Cookie da casa, R$ 11,00, "crocante na beira, mole no meio, quentinho se der."
  Banana bread, R$ 15,00, "a banana madura que virou aconchego."

Manhãs do Take Away, com um selo "7h às 10h · pra levar"
  Combo Desperta, R$ 18,00, "café coado + pão na chapa pra encarar o dia."
  Combo Verde, R$ 24,00, "matchá + cookie da casa, no teu passo."
  Combo Vizinho, R$ 23,00, "cappuccino + fatia de bolo pra dividir no caminho."

Rodapé da página
  "* valores ilustrativos, só pra dar o tom. O cardápio de verdade a gente ajusta com
  a estação e com o que a cidade traz de bom."

## O que quero de ti

Duas ou três direções visuais distintas pra essa página (não três variações da mesma
ideia, três apostas diferentes de como um cardápio pode ser lido na tela). Pra cada
direção:

1. Um mockup HTML autocontido, responsivo, com o conteúdo real acima, mostrando a
   página inteira de cima a baixo.
2. Três frases de racional: que sensação essa direção persegue e por que ela resolve a
   monotonia da lista atual.
3. Como ela se comporta no mobile (é lá que a maioria abre o cardápio, em pé,
   esperando o café).

No fim, tua recomendação de qual seguir e por quê.

## Sistema visual (obrigatório, é o que o site já usa)

Cores, exatamente estes valores:
  papel de fundo    #f3eee3   papel alternado #ece5d7   cartão #f7f2e9
  tinta (texto)     #1b1611   tinta 2 #241d16           tinta escura #14100b
  texto suave       #7c7160   filete #ddd2bf
  coral (acento)    #df5638   coral claro #e86c4f
  dourado           #c49a46   dourado claro #d6ac57
  verde             #4c7a3e   oliva #3d4a31
  azul              #3f6f9a
  creme (sobre fundo escuro) #efe9dd

Tipografia:
  títulos e preços: Fraunces (serifada), peso 400/500, entrelinha apertada (1.02),
    letter-spacing levemente negativo
  texto e interface: Sora, 300 a 700
  manuscrita decorativa: Caveat, usada com parcimônia, um toque só
  sobrelinhas (eyebrow): Sora 11px, maiúscula, letter-spacing .22em, peso 600

Escala de título que já existe: clamp(40px, 6vw, 74px) pro maior, clamp(30px, 4vw,
50px) pro título de página, clamp(23px, 3vw, 34px) pro título de seção.

Detalhes de linguagem visual que o site inteiro repete e devem aparecer: sobrelinha
maiúscula acima do título, um filete curto de 52x2px em coral logo abaixo do título,
seções alternando papel #f3eee3 e #ece5d7 com um filete de 1px na virada, um selo
redondo de 48px com ícone de traço fino ao lado do título de cada seção, e pílulas de
etiqueta em maiúscula miúda (tipo o "7h às 10h · pra levar").

Preço é sempre em Fraunces, cor coral, com numeral tabular.

## Coisas funcionais que o desenho precisa acomodar

- Uma tirinha de atalhos entre as seções que gruda no topo da janela quando a pessoa
  rola: pílulas com o nome de cada seção, a atual destacada, rolagem horizontal no
  mobile. Ela já existe e precisa continuar existindo, mas pode ganhar desenho novo.
- Um bloco "teus favoritos" no topo, que só aparece pra quem está logado e já marcou
  itens: pílulas com coração que levam de volta ao item na lista.
- Um coração de favoritar em cada item, discreto, que não pode brigar com o preço nem
  quebrar o alinhamento quando some (deslogado ele não existe).
- Header e rodapé do site entram por fora, não desenha eles. Desenha o miolo, do
  cabeçalho da página até a nota de valores ilustrativos.

## Travas técnicas (o mockup precisa ser traduzível)

- O projeto é Vite com Tailwind e JavaScript puro, sem framework, sem CDN. Nada de
  React, nada de biblioteca externa.
- Não existem fotos dos pratos e não vão existir tão cedo. O desenho não pode depender
  de foto por item. Se quiser massa visual, usa gradientes com as cores da casa,
  textura de papel feita em CSS, tipografia grande, espaço em branco.
- Ícones são de traço fino, estilo Lucide, 1.8 de espessura, cantos arredondados.
- Precisa funcionar de 320px de largura até telas ultrawide de 2560px, mobile-first.
- Respeita `prefers-reduced-motion`: toda animação tem que ter versão parada.
- Acessível de verdade: contraste que passa em AA, foco de teclado visível, hierarquia
  de cabeçalho correta, a lista de itens continua sendo lista.

## O que não fazer

- Nada de cara de app de delivery: sem card com foto por prato, sem selo de "mais
  pedido", sem estrela de avaliação, sem contador de urgência.
- Sem botão de comprar ou adicionar ao carrinho, essa página é só pra ler.
- Sem gradiente colorido fora da paleta, sem sombra pesada, sem vidro fosco por
  enfeite.
- Sem texto novo em tom publicitário. Se precisar escrever microcopy, escreve no tom
  da casa descrito lá em cima.

Se faltar alguma informação, assume o caminho mais provável, diz qual suposição tu
fez, e segue. Prefiro ver as três direções desenhadas a responder um questionário.
```

---

## Notas pra mim (não vão no prompt)

- Se quiser só UMA direção em vez de três, troca o bloco "O que quero de ti" por
  "uma direção só, desenvolvida a fundo, com estados de hover e foco".
- Quando o desenho voltar, o trabalho de tradução é: classes novas `.menu-*` no
  `src/styles.css` (o arquivo é consolidado, não fragmentar), conteúdo em
  `src/cardapio.html`, e nenhuma mudança no `app.js` a não ser que a tirinha de
  atalhos ou o bloco de favoritos mudem de contrato de DOM (`[data-cardapio-nav]`,
  `[data-cnav-chips]`, `[data-cardapio-favoritos]`, `[data-cf-chips]`, `.menu-item`,
  `.mi-name`).
- O `initCardapioFavoritos` deriva o slug do item **do nome**, então renomear item no
  cardápio zera o favorito de quem já tinha marcado. Se o desenho pedir renomeação,
  vale lembrar disso.
