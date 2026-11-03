# CASA CLUB — primeira leva

> Spec verificável. Base: o documento `Projeto_CASA_CLUB.docx` (ago/2026) e as decisões
> tomadas na conversa de 18/ago/2026. Nada aqui foi construído ainda.

---

## 1. Escopo

Trocar os **4 planos pagos** do clube por **uma assinatura única** (R$49,90 na 0048,
**R$88,90** desde a 0049), em que as
quatro categorias existentes (Vizinho de Sempre, Frequentador, Gente do Casa, Alma do Casa)
deixam de ser preço e passam a ser **tempo acumulado de casa** (0-3, 3-6, 6-12, 12+ meses),
com pontos **1:1 sem multiplicador**, uma **tela do clube** na área logada, e os fluxos de
upgrade/downgrade **desativados sem serem removidos**.

## 2. Fora de escopo (nesta leva)

- **CASA MAIL** (envio físico mensal, edições numeradas, status de envio, tela de logística).
- **CASA MAIL de mudança de nível** (3/6/12 meses).
- **PASS IT ON** (voucher transferível de café).
- **CASA Friends** (curadoria de parceiros dentro do clube; a tabela `partners` já existe).
- **Integração com a frente de caixa (PDV)**. Sem ela, o consumo no balcão **não pontua** —
  só a loja e a própria mensalidade. A tela do clube tem que dizer isso na cara.
- **Novo catálogo de recompensas** (a escala 100→1.000 do documento). O catálogo atual
  (100/200/400/500) segue como está até o CMV de cada item ser validado.
- **Pontos em dobro por campanha** (item 7 do documento). É multiplicador por janela de
  tempo, peça nova, não entra agora.
- **Renomear os slugs** `bronze`/`prata`/`ouro`/`diamante` na tabela `tiers`. Ver decisão D2.

## 3. Decisões travadas (e por quê)

**D1. O relógio acumula, não corre no calendário.** "Continua de onde parou" significa que o
tempo **pausado não conta e não zera**. Quem ficou 4 meses, pausou 6 e voltou, volta com 4
meses de casa, não com 10. Implementação: **união de intervalos** de todas as linhas de
`subscriptions` da pessoa (`created_at` → `least(current_period_end, now())`), somando a
união (nunca a soma crua, senão presente sobreposto a assinatura contaria duas vezes).
Presente conta, assinatura cancelada conta pelo tempo que cobriu, reassinatura soma.

**D2. Os slugs da tabela `tiers` NÃO mudam.** `tier_slug` está espalhado por mais de trinta
pontos entre front, Edge Functions e migrations, com FK vindo de `subscriptions`,
`gift_subscriptions` e `profiles`. Renomear pediria UPDATE em dado histórico de produção pra
ganhar só legibilidade interna. Os slugs são invisíveis pra quem usa o site. Fica documentado
no CLAUDE.md que `bronze` = Vizinho de Sempre = categoria de entrada, e assim por diante.

**D3. "Não vendável" é COLUNA NOVA, nunca o `ativo`.** O `getUserTierDiscount` devolve
`tier_slug: null` quando o tier está `ativo = false`, e o `creditPoints` dá **zero pontos**
com slug nulo. Marcar as três categorias superiores como inativas faria quem chega em Gente
do Casa **parar de pontuar e perder o desconto**. Entra `tiers.vendavel`, e as quatro
continuam `ativo = true`.

**D4. A categoria vive no `tier_slug`, não só na tela.** Ao subir de categoria, o
`profiles.tier_slug` e o `subscriptions.tier_slug` são atualizados. Assim o header, o painel
do avatar, o cartão do `/gente`, o perfil e o console mostram a categoria certa **sem nenhuma
mudança de código** nesses lugares. Se a categoria fosse só derivada na tela do clube, o
perfil diria "Vizinho de Sempre" pra quem tem dois anos de casa.

**D5. A promoção acontece em dois lugares, de propósito.** No **webhook**, a cada pagamento
de renovação (é o único evento mensal garantido que o site já recebe, e não precisa de cron),
e na **leitura da tela do clube** (auto-cura: se o webhook falhar, a próxima visita conserta).
A conta é sempre refeita no banco a partir das datas; o client nunca informa tempo nem
categoria.

**D6. Um mês = 30 dias.** A Asaas renova em ciclo `MONTHLY` (~30,44 dias em média), então
30 dias faz o marco de 12 meses cair uns cinco dias antes. O arredondamento fica **a favor de
quem fica**, que é o lado certo pra errar.

**D7. As conquistas `gente-do-casa` e `alma-do-casa` viram o carimbo da categoria.** Hoje elas
existem com o mesmo nome das categorias, o que faria a mesma palavra significar duas coisas.
Em vez de renomear, elas passam a desbloquear **exatamente quando a categoria é alcançada**,
via um tipo de critério novo (`meses_de_casa`) no `check_achievements`.

## 4. Arquivos afetados

**Banco**
- `supabase/migrations/0048_casa_club.sql` — **novo**. Colunas `tiers.vendavel` e
  `tiers.meses_min`; reseed dos quatro tiers (preço único, desconto único, multiplicador 1.00);
  função `meses_de_casa(uuid)`; função `categoria_por_tempo(integer)`;
  `sincronizar_categoria(uuid)`; RPC `meu_clube()`; critério `meses_de_casa` no
  `check_achievements`; critérios das duas conquistas de categoria.

**Edge Functions**
- `supabase/functions/create-checkout-session/index.ts` — assinatura só aceita tier
  `vendavel`; modo upgrade recusa com recado em português; modo presente usa o tier único.
- `supabase/functions/downgrade-subscription/index.ts` — recusa com recado em português.
- `supabase/functions/asaas-webhook/index.ts` — chama `sincronizar_categoria` depois de
  creditar os pontos da assinatura.

**Front**
- `src/planos.html` — um cartão no lugar de quatro; a seção passa a contar a jornada de
  categorias e a explicar os pontos 1:1.
- `src/presentear.html` — um plano no lugar de quatro radios.
- `src/conta/clube.html` — **novo**. A tela do clube.
- `src/app.js` — `CONTA_LINKS` ganha `/conta/clube`; `initClubePage` nova; `initPlanosPage`
  sem escolha de tier; `initPresentearPage` sem escolha de tier; no perfil, `tiersUpgrade` e
  `tiersDowngrade` passam a filtrar por `vendavel`.
- `src/styles.css` — estilos `.clube-*`.
- `vite.config.js` — `conta/clube.html` no `rollupOptions.input`.
- `CLAUDE.md` — a seção do clube reescrita, mais a nota da 0048.

## 5. Critérios de aceite

**Banco e regra de tempo**
1. `tiers` tem as colunas `vendavel` (boolean, default false) e `meses_min` (integer), e as
   quatro linhas seguem com `ativo = true`.
2. Exatamente **uma** linha de `tiers` tem `vendavel = true`, e é a categoria de entrada
   (`bronze`, Vizinho de Sempre), com o preço da assinatura em `preco_centavos`.
3. As quatro linhas têm `points_multiplier = 1.00` e `discount_percent` **igual entre si**.
4. `meses_de_casa(uuid)` devolve a **união** dos períodos, não a soma crua: duas assinaturas
   sobrepostas (ex.: presente durante assinatura ativa) contam o tempo **uma vez só**.
5. `meses_de_casa` conta assinatura `cancelada` pelo tempo que ela cobriu, e **nunca** conta
   tempo futuro (todo período é cortado em `now()`).
6. Uma pessoa sem nenhuma assinatura devolve `0`, sem erro.
7. `categoria_por_tempo` devolve a categoria de maior `meses_min` que caiba no tempo: 0→entrada,
   2→entrada, 3→segunda, 6→terceira, 12→quarta, 400→quarta.
8. `sincronizar_categoria` atualiza `profiles.tier_slug` **e** `subscriptions.tier_slug` da
   assinatura vigente, e **só** quando a categoria calculada difere da gravada (chamada duas
   vezes seguidas não gera escrita nem linha de auditoria na segunda).
9. `sincronizar_categoria` **não** promove quem não tem assinatura vigente (sem plano, o
   `tier_slug` fica nulo, senão viraria benefício de graça).
10. A escrita em `profiles.tier_slug` acende a GUC `casa.trusted_points`, senão a trigger
    `prevent_points_tamper` derruba a promoção.
11. `meu_clube()` é `authenticated`, usa `auth.uid()` (nunca id vindo do client), sincroniza
    a própria categoria e devolve: categoria atual, nome, meses de casa, próxima categoria,
    dias que faltam, saldo de pontos e se a assinatura está vigente.
12. A migration é **idempotente**: rodar duas vezes seguidas não duplica nem erra.

**Pontos**
13. Uma compra de R$49,41 na loja rende **49 pontos** em qualquer categoria (1:1, `floor`),
    e continua rendendo **0** pra quem não tem plano.
14. O desconto aplicado no checkout da loja é o **mesmo** em qualquer categoria.

**Upgrade e downgrade desativados, não removidos**
15. As funções `create-checkout-session` (modo upgrade) e `downgrade-subscription` **seguem
    deployadas** e respondem com recado em português explicando que o clube agora é uma
    assinatura só. Nenhum arquivo de function foi apagado.
16. `create-checkout-session` no modo assinatura **recusa** um `tier_slug` que não seja
    `vendavel`, mesmo que o client peça direto pela API. (Sem isso, dava pra comprar categoria.)
17. No `/conta/perfil`, o painel "fazer upgrade" e o desvio "descer de plano" **não aparecem**,
    e o filtro que os monta passa a olhar `vendavel` (hoje o do upgrade só compara `ordem`,
    então listaria as três categorias superiores como se fossem compráveis).
18. "Pausar", "retomar" e "voltar pro plano" continuam funcionando como hoje.

**Telas**
19. `/planos` mostra **um** preço e **uma** chamada de assinar; a jornada das quatro
    categorias aparece como linha do tempo, sem botão de comprar categoria.
20. `/presentear` presenteia o plano único, sem escolha de tier, e o checkout do presente
    continua sem emoji no payload do Asaas.
21. `/conta/clube` existe, está atrás do `requireAuth`, entra no `CONTA_LINKS` e na tirinha
    das páginas da conta, e responde as quatro perguntas do item 15 do documento: em que
    categoria estou, quanto falta pra próxima, quantos pontos tenho e o que dá pra trocar.
22. `/conta/clube` diz, sem rodeio, que **hoje os pontos vêm da loja e da mensalidade**, e que
    o consumo no balcão ainda não pontua.
23. Quem não tem plano abre `/conta/clube` e vê um convite pros planos, não uma tela quebrada.
24. Todas as telas novas são tolerantes à migration pendente: sem a 0048, nada estoura, a
    parte que depende dela some.

**Tom e padrões da casa**
25. Nenhum travessão (`—`) em texto visível novo, em HTML ou em string do `app.js`.
26. Tratamento em "tu"/"a gente"; nenhuma das palavras banidas (gourmet, luxo, premium,
    exclusivo, hype, trend) no copy novo.
27. Toda string vinda do banco é escapada antes de ir pro DOM.
28. `npm run build` passa e `npm run security-check` passa.

## 6. Edge cases

- **Presente sobreposto a assinatura ativa** — o tempo conta uma vez (critério 4).
- **Assinatura pausada dentro do período pago** — o benefício segue até `current_period_end`,
  mas o tempo só acumula até `now()`; a tela mostra "teu tempo tá guardado" em vez de uma
  contagem regressiva que não anda.
- **Assinatura `cancelada` (Asaas 404)** — o tempo já vivido não some; se a pessoa reassina,
  a categoria volta de onde parou já na primeira sincronização.
- **Pessoa que sobe de categoria no meio do ciclo** — a promoção nunca mexe no `value` da
  assinatura no Asaas (todas as categorias custam o mesmo), então não há cobrança nova.
- **Assinante de hoje no Diamante ou no Bronze** — a virada de preço é decisão do humano no
  painel do Asaas, não desta leva. O código passa a tratar todos como uma assinatura só, e a
  categoria é recalculada pelo tempo real de casa (quem já tem um ano vira Alma do Casa na
  primeira sincronização, sem intervenção).
- **Webhook que não chega** — a leitura da tela do clube conserta a categoria sozinha.
- **Chamada concorrente de `sincronizar_categoria`** — a função só escreve quando há
  diferença, então a segunda chamada é inócua.
- **`gift_subscriptions` com o tier antigo** — presentes já pagos e não resgatados apontam pra
  um slug que continua existindo, então nada quebra no resgate.

## 7. Aprovado sem ressalvas

Quando os 28 critérios estiverem marcados como sim, sem TODO pendente, sem `console.log`
esquecido, com `npm run build` e `npm run security-check` passando, e sem regressão nos fluxos
que já estão no ar (pausar, retomar, reassinar, resgatar presente, resgatar recompensa, mural,
cantinho, RSVP da agenda) — todos eles gated por `tier_slug`, que esta leva passa a mexer.

## 8. Decisão que estava pendente, e foi tomada

**O desconto na loja: 10%, igual pra todo membro** (decidido em 18/ago/2026). O documento pede
pra não transformar o clube num programa de desconto, mas lista "benefícios selecionados na
loja", então ficou um percentual único, sem escada por categoria. É uma linha do seed da 0048.

## 9. Estado

**No ar desde 18/ago/2026.** A migration `0048_casa_club` rodou no SQL Editor, o front foi pra
`main` e as três Edge Functions da leva (`create-checkout-session`, `downgrade-subscription`,
`asaas-webhook`) foram re-deployadas, tudo no mesmo dia. Nada da leva ficou pela metade.

Fora do código, resta uma decisão de operação que é do humano: **ajustar no painel do Asaas o
valor das assinaturas antigas** que estavam em outro preço.

---

## 10. Review (18/ago/2026)

Auditoria dos 28 critérios contra o código no ar. **Dois furos achados e corrigidos**, os dois
do mesmo tipo: coisas que só aparecem cruzando a leva nova com o que já existia.

**(a) "voltar pro plano" quebrava pra quem não estava na categoria de entrada** (critério 18).
O botão mandava `tier_slug` = a categoria da pessoa, e a `create-checkout-session` passou a
recusar tudo que não é `vendavel`. Quem tinha assinatura encerrada e três meses ou mais de
casa (`prata`, `ouro`, `diamante`) receberia "esse é um degrau do clube, não um plano à
venda" ao tentar voltar, justamente quem tem mais tempo de casa. Agora o botão manda o slug
**vendável** e o rótulo virou "voltar pro clube"; a copy explica que o tempo continua
guardado, então a categoria volta sozinha quando a primeira cobrança passar.

**(b) a tirinha das páginas da conta não aparecia na `/conta/clube`** (critério 21). O
`renderContaNav` casa por uma lista de seletores e a página nova não estava nela. Provado
contra o HTML real da página: o seletor antigo não casava, o novo casa, e a `<section>` com
pai que a função precisa pra inserir a faixa está lá.

**Não deu pra verificar no navegador:** este ambiente não tem Supabase configurado, então toda
página de `/conta/` redireciona pro `/login` antes de dar pra observar qualquer coisa. Vale
igual pras quatro páginas que já existiam, então é limite do ambiente, não regressão.

**Duas observações que não viraram correção:**
- O `data-tier="bronze"` do `/planos` é escrito à mão no HTML. Se um dia a casa mudar qual
  categoria é vendável, o botão passa a mandar um slug recusado. Degrada **visível** (a
  página mostra o recado em português da function), não em silêncio, então ficou como está.
- Existe um travessão em copy visível no card do brunch de aniversário (`app.js`), que é
  anterior a esta leva. Fora de escopo aqui, mas fica anotado.

---

## 11. O que veio depois da primeira leva (18/ago/2026)

A leva foi seguida, no mesmo dia, por quatro pedidos da casa, todos já no ar:

- **`0049`** — a assinatura sobe de R$49,90 pra **R$88,90**. As quatro categorias andam
  juntas (categoria é tempo, não preço), e assinatura viva no Asaas mantém o valor com que
  nasceu.
- **A lista de benefícios mudou:** entra o **platter brunch mensal pra duas pessoas** e a
  **caixa do Casa na porta**, e o brunch de aniversário sai da lista (o mensal ocupou o
  lugar).
- **`0050`** — os dois brunches viram **voucher com código**, a mesma mecânica pros dois. O
  de aniversário deixou de exigir plano e ganhou janela de **7 dias**; o do mês é de quem
  assina, um por mês, e não acumula.
- **`0051`** — o aniversário passa a ser pedido no **cadastro** e **não se troca depois**,
  que é o que fecha a conta de abrir o brunch de aniversário pra qualquer pessoa com conta.

**Segue sem software por baixo:** a caixa do Casa (o CASA MAIL do documento). Ela aparece na
vitrine, mas nada no site registra envio.
