# Repair — 9 bugs confirmados na varredura

Origem: varredura de 5 runs × 10 levas no código do Casa. Dos achados, 9 foram
confirmados por verificação adversarial (maioria de céticos não conseguiu refutar)
e 9 foram refutados. Este arquivo é o registro do ciclo spec → build → review
desse repair.

## Critério de aceite

Cada item abaixo só conta como fechado quando (a) a causa está corrigida no lugar
certo — servidor/banco quando envolve confiança, nunca só na tela —, (b) `npm run
build` passa e (c) `npm run security-check` passa.

## Itens e o que foi feito

| # | Bug | Onde foi corrigido | Estado |
|---|-----|--------------------|--------|
| 1 | Planos anunciavam "Bronze"/"Prata", nomes que não existem no `0003_seed` (os reais são "Vizinho de Sempre" e "Frequentador") | `src/planos.html` | fechado |
| 2 | `Cart.getCount()` somava linhas em vez de quantidades — o badge do header mentia | `src/app.js` | fechado |
| 3 | `wireResgates()` religava os handlers a cada render, acumulando listeners (resgate duplo por clique único) | `src/app.js` | fechado |
| 4 | `applyUpgrade` não limpava o downgrade agendado: subir de plano e continuar descendo na renovação | `supabase/functions/asaas-webhook/index.ts` | fechado |
| 5 | `cancel-subscription` marcava 'pausada' mesmo com a linha ainda sem `asaas_subscription_id` — UI dizia "pausado" com o cartão sendo cobrado | `supabase/functions/cancel-subscription/index.ts` (409 `sem_vinculo`) | fechado |
| 6 | Apagar a conta entre o cartão ser cobrado e o `CHECKOUT_PAID` chegar deixava recorrência órfã | `create-checkout-session` pré-marca `status='pendente'` + gate no `delete-account` (janela de 60 min) | fechado — **depende da migration 0018** |
| 7 | `subscriptions.status` não aceitava `'pendente'` (CHECK da 0001) — sem isso o item 6 nunca protege ninguém | `supabase/migrations/0018_...sql` (a) | fechado — **aplicar no SQL Editor** |
| 8 | `admin_definir_permissoes` barrava por "veio na lista" em vez de por delta: travava gestor não-owner ao editar qualquer permissão de quem já tinha 'equipe', e deixava passar a REVOGAÇÃO da 'equipe' | `supabase/migrations/0018_...sql` (b) | fechado — **aplicar no SQL Editor** |
| 9 | "Esqueci a senha" mandava pro `/login`, que só tem campo de senha ATUAL — não havia como criar senha nova | `src/app.js`: redirect pra `/auth-confirmado` + painel de senha nova lá | fechado |

A correção do item 8 ficou no RPC, não em `src/admin.js`: a lista que o console
manda é o estado COMPLETO das permissões, então filtrar checkbox desabilitado no
client REMOVERIA a permissão 'equipe' do alvo — seria pior que o bug.

## Achado da review (corrigido na mesma rodada)

O painel de senha nova é injetado por JS em `/auth-confirmado`, e reusava classes
que só existiam no `<style>` local do `login.html` — o olhinho de mostrar/ocultar
senha ficaria sem posicionamento. Na verdade o mesmo componente estava duplicado
com dois nomes (`.pw-*` no cadastro, `.log-pass-*` no login). Promovido um par só
(`.pw-wrap`/`.pw-toggle`) pro `styles.css`, com as três telas apontando pra ele.

Junto veio `.notice.hidden { display: none }`: como `.notice` mora fora de `@layer`
pra vencer os utilitários do Tailwind, ela vencia o `.hidden` também — toda notice
escondida pelo JS nascia visível e vazia. Estava remendado só no `login.html`.

## Refutados — NÃO aplicar

Trava anti-duplicação sem lock (`create-checkout-session:387`); `CHECKOUT_PAID`
revivendo pedido cancelado (`asaas-webhook:274`); duplo clique no "finalizar
compra" (`app.js:1098`); rollback do upgrade grátis (`create-checkout-session:183`);
`updateCartUI` relendo localStorage (`app.js:903`); `getEffectiveSubscription`
engolindo erro (`_shared/lib.ts:255`); `resume-subscription` reativando só uma
(`resume-subscription:51`); `staff_permissions` fora de `SENSIVEIS`
(`security-check.mjs:134`); carrinho não limpo no logout (`app.js:1770`).

## Verificação

- `npm run build` — passou.
- `npm run security-check` — passou (RLS em 21 tabelas, nenhum segredo em src/dist,
  npm audit sem high/critical).

## Pendente com o humano

1. Aplicar `supabase/migrations/0018_assinatura_pendente_e_equipe.sql` no SQL
   Editor, depois da `0017_admin`. Sem ela, o insert de `status='pendente'` bate na
   CHECK e o checkout de assinatura quebra.
2. Deploy das quatro Edge Functions alteradas (`create-checkout-session`,
   `delete-account`, `cancel-subscription`, `asaas-webhook`) — aguarda aprovação.
