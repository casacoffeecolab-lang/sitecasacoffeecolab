# Handoff — passar o Casa Coffee Colab pras contas do dono do site

Este guia é o passo-a-passo pra **transferir o site pras contas do proprietário
do café**. Hoje a infra roda em contas do desenvolvedor (fase de building/testes);
mais pra frente o dono assume.

São **3 peças que podem trocar de dono** — cada uma de forma **independente** ou
todas juntas:

| Peça         | O que guarda                                             | Conta hoje |
|--------------|----------------------------------------------------------|------------|
| **Asaas**    | gateway de pagamento (Pix + Cartão), chave de API, webhook | do dev, **sandbox** |
| **Supabase** | banco (Postgres + RLS), Auth, Edge Functions, secrets    | projeto `shqmtddhktcxfsccubay` |
| **Vercel**   | hospedagem do front (build do Vite), env públicas, domínio | deploy atual |

> **A ideia central, pra TODAS as peças:** o **código não muda**. O que muda é
> **config, secrets e cadastro em painel**. Nenhuma linha do site ou das functions
> precisa ser editada pra virar de conta.

O caminho mais provável e mais simples é **só o Asaas** ([Parte 1](#parte-1--asaas-pagamentos));
Supabase ([Parte 2](#parte-2--supabase-banco--auth--functions)) e Vercel
([Parte 3](#parte-3--vercel-hospedagem)) são migrações maiores, documentadas aqui
porque **bem provavelmente também vão acontecer** no futuro. Se for migrar mais de
uma peça de uma vez, leia antes a [ordem recomendada + mapa de dependências](#migrar-mais-de-uma-peça-ordem--dependências).

---

## Regra de ouro (segurança) — vale pras 3 peças

- **O agente/IA NUNCA manuseia chave secreta.** Nem a `ASAAS_API_KEY`, nem a
  `SUPABASE_SERVICE_ROLE_KEY`, nem senha de painel. Uma chave de **sandbox/teste**
  vazada é tolerável; a de **produção NUNCA** pode vazar.
- Chave/segredo de **produção** vai **direto das mãos do dono pro painel** (Supabase
  secrets ou Vercel env) — nunca colada no repositório, no código, em chat, e-mail
  ou print.
- No **client/Vercel** só entram variáveis **públicas** (prefixo `VITE_`): a URL e a
  **anon key** do Supabase, e a URL do site. **Nenhuma chave de pagamento** — o
  Checkout do Asaas é 100% hospedado.
- **Migrations do banco são append-only e imutáveis.** Migrar Supabase = **re-rodar**
  as migrations existentes num projeto novo, nunca editá-las.
- RLS-by-default e "zero confiança no client" continuam valendo: preço, desconto,
  total e pontos são sempre recalculados server-side (ver `CLAUDE.md` › Segurança).

---

## Migrar mais de uma peça: ordem + dependências

Se **duas ou três** peças mudarem juntas, a ordem importa — senão você seta um valor
e logo tem que refazer. As peças se apontam assim:

| Muda isto…                              | …e estes valores precisam acompanhar                                             |
|-----------------------------------------|----------------------------------------------------------------------------------|
| **Projeto Supabase** (novo `project-ref`) | URL do **webhook** do Asaas · `VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY` no client (Vercel) · onde rodam migrations/functions/secrets |
| **Domínio** (novo, na Vercel)           | secret `SITE_URL` (callbacks do Asaas) · `VITE_SITE_URL` (client) · **Supabase → Auth → URL Configuration** (Site URL + Redirect URLs) |
| **Conta Asaas** (nova)                  | secrets `ASAAS_API_KEY` + `ASAAS_WEBHOOK_TOKEN` · cadastro do webhook na conta nova |

**Ordem recomendada quando for tudo junto:**

1. **Supabase primeiro** ([Parte 2](#parte-2--supabase-banco--auth--functions)) — é a
   base: dele sai o `project-ref` (que a URL do webhook e o client dependem) e as
   Edge Functions.
2. **Vercel + domínio** ([Parte 3](#parte-3--vercel-hospedagem)) — publica o front e
   **decide o domínio final**. Só depois de ter o domínio dá pra fixar `SITE_URL`,
   `VITE_SITE_URL` e as URLs de Auth do Supabase.
3. **Asaas por último** ([Parte 1](#parte-1--asaas-pagamentos)) — precisa da URL final
   das functions (Supabase) pro webhook **e** do domínio final pros callbacks.

> Cada Parte abaixo é **autossuficiente** (serve pra migrar só aquela peça). Quando
> uma migração depende de outra, tem um aviso "⇄ depende de…" no lugar.

---

# Parte 1 — Asaas (pagamentos)

Trocar a conta Asaas de testes (hoje, do desenvolvedor) pela **conta do dono**. É a
única troca que falta pra os pagamentos rodarem "de verdade" no nome do café — e a
mais provável de acontecer sozinha.

> A base da API (sandbox × produção) é **deduzida do prefixo da chave**
> (`$aact_hmlg_…` = sandbox, `$aact_prod_…` = produção) — não tem `if` de ambiente
> no código. Trocar de conta = trocar a chave nos secrets + re-cadastrar o webhook.

**Premissa desta Parte:** Supabase (`shqmtddhktcxfsccubay`) e Vercel **continuam como
estão**. Só a conta Asaas muda. (Se Supabase/Vercel também mudarem, veja as Partes 2/3.)

## 1.1 · O que muda × o que NÃO muda

| Muda (config, no painel/secrets)                          | NÃO muda (fica como está)                     |
|-----------------------------------------------------------|-----------------------------------------------|
| A conta Asaas (passa pra do dono)                         | Todo o código (functions + front)             |
| `ASAAS_API_KEY` (chave da nova conta)                     | As migrations do banco (0001→0011)            |
| `ASAAS_WEBHOOK_TOKEN` (token novo)                        | O projeto Supabase (`shqmtddhktcxfsccubay`)   |
| `SITE_URL` (só se o domínio final mudar)                  | A URL do webhook (deriva do projeto Supabase) |
| O cadastro do webhook (na conta nova)                     | O front / drawer / checkout                   |
| Habilitar Pix + Cartão e criar a chave Pix (conta nova)   |                                               |

## 1.2 · Quem faz o quê

**Só o dono da conta consegue fazer** (é nível de conta, ninguém faz por ele):

1. Criar a conta Asaas e completar o **cadastro/KYC** (obrigatório pra receber de verdade).
2. **Habilitar Pix e Cartão** na conta.
3. **Criar uma chave Pix** (tipo **Aleatória / EVP**) — sem ela o Asaas recusa o
   checkout inteiro (mesmo o de cartão).
4. **Gerar a chave de API** (`ASAAS_API_KEY`).

**Quem tem acesso ao Supabase** (o dono, ou um dev ajudando):

5. Setar os secrets e fazer o redeploy das functions.
6. Cadastrar o webhook no painel do Asaas.

> ⚠️ **Segurança da chave de produção.** A `ASAAS_API_KEY` de **produção** dá acesso
> total à conta (dinheiro de verdade). Ela vai **direto das mãos do dono pros secrets
> do Supabase** — nunca no repositório, no código, em chat, e-mail ou print.

## 1.3 · Caminho recomendado: sandbox do dono → produção

Vale testar primeiro na **conta sandbox do próprio dono** (não cobra nada). Depois,
com tudo ok, virar pra **produção**. São os mesmos passos — muda só a chave e o painel.

### Etapa A — validar na conta SANDBOX do dono (recomendado)

1. Dono cria a conta grátis em **https://sandbox.asaas.com**.
2. No painel: **Pix → Minhas chaves → Nova chave** → tipo **Aleatória (EVP)**
   (cria na hora, sem validar nada).
3. **Configurações → Integrações → Chave de API → Gerar chave.** Começa com
   `$aact_hmlg_…`. É a `ASAAS_API_KEY` (sandbox).
4. Escolhe um **token de webhook** novo (uma senha forte / um UUID). É o
   `ASAAS_WEBHOOK_TOKEN`.
5. (quem tem acesso ao Supabase) seta os secrets — ver [comandos](#14--comandos-de-referência-supabase-cli).
6. (idem) **redeploy das 4 functions** — ver [comandos](#14--comandos-de-referência-supabase-cli).
7. Cadastra o **webhook** no painel sandbox do dono — ver [webhook](#15--cadastro-do-webhook).
8. **Testa de ponta a ponta** — loja (cartão de teste ou Pix) e assinatura
   (cartão de teste; recorrência no Asaas é cartão-só)
   simulado — ver [teste](#16--como-testar-um-pagamento).

### Etapa B — virar pra PRODUÇÃO (dinheiro real)

1. Dono cria/usa a conta em **https://www.asaas.com** e completa o **KYC**.
2. **Habilita Pix e Cartão** na conta de produção.
3. **Cria a chave Pix** (Aleatória / EVP) na conta de produção.
4. **Gera a chave de API de produção** (`$aact_prod_…`).
5. Escolhe um **`ASAAS_WEBHOOK_TOKEN` novo** (não reaproveita o de sandbox).
6. (Supabase) troca os secrets pros valores de produção e faz **redeploy das 4
   functions**.
7. **Cadastra o webhook na conta de PRODUÇÃO** (o cadastro de sandbox não vale em
   prod) — mesmos eventos.
8. **Smoke test:** uma assinatura ou compra pequena de verdade, e confere que caiu
   na conta do dono e que o pedido/assinatura foi finalizado no site.

## 1.4 · Comandos de referência (Supabase CLI)

Precisa do [Supabase CLI](https://supabase.com/docs/guides/cli) e de **acesso ao
projeto** (logado: `supabase login`). Aqui o `project-ref` é o atual,
`shqmtddhktcxfsccubay` — se o Supabase também migrou, use o novo (Parte 2).

**Setar os secrets** (aspas simples: a chave tem `$`):

```bash
# sandbox do dono:
supabase secrets set ASAAS_API_KEY='$aact_hmlg_...'        --project-ref shqmtddhktcxfsccubay
# produção (quando virar):
# supabase secrets set ASAAS_API_KEY='$aact_prod_...'      --project-ref shqmtddhktcxfsccubay

supabase secrets set ASAAS_WEBHOOK_TOKEN='o-token-novo'    --project-ref shqmtddhktcxfsccubay
supabase secrets set SITE_URL='https://casacoffeecolab.vercel.app' --project-ref shqmtddhktcxfsccubay

# conferir (mostra só os NOMES e um hash — nunca o valor real; é seguro):
supabase secrets list --project-ref shqmtddhktcxfsccubay
```

> `SITE_URL` só muda se o site ganhar um **domínio próprio** (ex.:
> `https://casacoffeecolab.com.br`) ou se a Vercel migrar (Parte 3). Enquanto for a
> URL atual da Vercel, continua a mesma.

**Redeploy das 4 functions** (`--use-api` evita precisar de Docker local; o webhook
vai com `--no-verify-jwt` porque quem chama é o Asaas, não um usuário logado):

```bash
supabase functions deploy create-checkout-session --project-ref shqmtddhktcxfsccubay --use-api
supabase functions deploy cancel-subscription      --project-ref shqmtddhktcxfsccubay --use-api
supabase functions deploy resume-subscription      --project-ref shqmtddhktcxfsccubay --use-api
supabase functions deploy downgrade-subscription   --project-ref shqmtddhktcxfsccubay --use-api
supabase functions deploy redeem-reward            --project-ref shqmtddhktcxfsccubay --use-api
supabase functions deploy asaas-webhook            --project-ref shqmtddhktcxfsccubay --use-api --no-verify-jwt
```

> Trocar **só os secrets** já basta pra próxima chamada usar a conta nova (o segredo
> é lido a cada invocação). O redeploy acima é a garantia — faça sempre que trocar
> chave/token.

## 1.5 · Cadastro do webhook

No painel do Asaas (sandbox **ou** produção, conforme a etapa) →
**Configurações → Integrações → Webhooks** → **Adicionar**:

- **URL:** `https://shqmtddhktcxfsccubay.functions.supabase.co/asaas-webhook`
  *(⇄ se o Supabase migrou, essa URL muda pro novo `project-ref` — ver Parte 2.)*
- **Token de autenticação:** o mesmo valor de `ASAAS_WEBHOOK_TOKEN` (o Asaas manda
  ele no header `asaas-access-token`; a function rejeita `401` se não bater).
- **Versão da API:** v3.
- **Eventos:**
  - Checkout: `CHECKOUT_PAID`, `CHECKOUT_EXPIRED`, `CHECKOUT_CANCELED`.
  - Pagamento (pontos da assinatura — 1ª cobrança + renovações):
    `PAYMENT_CONFIRMED`, `PAYMENT_RECEIVED`.

## 1.6 · Como testar um pagamento

Logado no site (rodando local ou publicado):

- **Loja:** adiciona itens → abre o carrinho → "finalizar compra" → paga com
  **cartão de teste** (doc do Asaas) ou **Pix simulado** (o painel sandbox marca o
  Pix como recebido). Deve voltar pra tela de sucesso mostrando **"+X pontos"**.
- **Assinatura:** `/planos` → "assinar" num plano → paga → volta pra sucesso; o
  perfil passa a mostrar a **próxima cobrança**, e os **pontos** entram.

Confere pela própria interface: `conta/perfil` (plano + próxima cobrança) e
`conta/pontos` (extrato). Se apareceu, o webhook rodou certo.

## 1.7 · Checklist (Asaas)

Conta nova (dono):
- [ ] Conta Asaas criada e **KYC** completo (produção)
- [ ] **Pix e Cartão** habilitados
- [ ] **Chave Pix** (Aleatória/EVP) criada
- [ ] `ASAAS_API_KEY` gerada
- [ ] `ASAAS_WEBHOOK_TOKEN` novo escolhido

Supabase:
- [ ] `ASAAS_API_KEY`, `ASAAS_WEBHOOK_TOKEN`, `SITE_URL` setados
- [ ] **4 functions** re-deployadas (webhook com `--no-verify-jwt`)

Asaas (painel):
- [ ] **Webhook cadastrado** na conta certa, com o token e os 5 eventos

Validação:
- [ ] Loja testada de ponta a ponta (pagou → pedido `pago` → pontos)
- [ ] Assinatura testada (pagou → plano no perfil → próxima cobrança → pontos)

---

# Parte 2 — Supabase (banco + auth + functions)

Passar o **projeto Supabase** pra conta do dono. É uma migração maior que a do Asaas:
o Supabase guarda o **banco**, o **Auth** e as **4 Edge Functions**. Como o
`project-ref` muda, ele **arrasta** valores no Asaas e na Vercel (ver os avisos "⇄").

> **Migrations são imutáveis** — aqui a gente **re-roda** as que já existem num
> projeto novo, sem editar nenhuma.

## 2.1 · Criar o projeto novo

1. Dono cria uma conta em **https://supabase.com** e um **projeto novo** (escolhe
   região — de preferência São Paulo/`sa-east-1` pra latência no Brasil).
2. Anota o **`project-ref`** novo (aparece na URL do painel e em **Settings →
   General**). Ele substitui `shqmtddhktcxfsccubay` em todos os comandos.
3. Guarda, de **Settings → API**: a **Project URL** (`https://<REF>.supabase.co`) e a
   **anon/public key** — vão pro client na Vercel (Parte 3). A **`service_role` key
   NUNCA vai pro client** (é injetada automaticamente nas functions).

## 2.2 · Rodar as migrations (SQL Editor, EM ORDEM)

No painel: **SQL Editor** → cola e roda **cada arquivo** de `supabase/migrations/`,
na ordem numérica. Hoje são estas (confira a pasta — pode haver novas):

```
0001_init            0005_profiles_phone   0009_achievements
0002_rls             0006_stripe           0010_achievement_hints
0003_seed            0007_orders_stripe    0011_asaas
0004_reconcile       0008_points           0012_asaas_checkout_link
                                           0012_downgrade
                                           0013_redeem_reward_user_lock
```

> Os dois arquivos com prefixo `0012` são independentes entre si — a ordem **entre eles**
> não importa, só precisam vir depois da `0011`.

> As `0006_stripe`/`0007_orders_stripe` criam colunas `stripe_*` que **não são mais
> usadas** (migramos pro Asaas), mas rodam mesmo assim — migrations são append-only,
> a sequência precisa ficar íntegra. Não pule nenhuma.

Depois de rodar, dá pra conferir com `supabase/migrations/` + `scripts/check-rls.sql`
(prova de RLS ao vivo, incl. teste negativo como anon).

## 2.3 · Linkar o CLI e setar os secrets

```bash
supabase login
supabase link --project-ref <NOVO_PROJECT_REF>

# secrets das functions (os MESMOS 3 de sempre; valores conforme a conta Asaas em uso):
supabase secrets set ASAAS_API_KEY='$aact_hmlg_...'  --project-ref <NOVO_PROJECT_REF>
supabase secrets set ASAAS_WEBHOOK_TOKEN='...'       --project-ref <NOVO_PROJECT_REF>
supabase secrets set SITE_URL='https://<domínio-final>' --project-ref <NOVO_PROJECT_REF>
```

> `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` e `SUPABASE_ANON_KEY` são **injetados
> automaticamente** pelo Supabase em cada function — **não precisa setar**.

## 2.4 · Deploy das 4 functions

```bash
supabase functions deploy create-checkout-session --project-ref <NOVO_PROJECT_REF> --use-api
supabase functions deploy cancel-subscription      --project-ref <NOVO_PROJECT_REF> --use-api
supabase functions deploy resume-subscription      --project-ref <NOVO_PROJECT_REF> --use-api
supabase functions deploy downgrade-subscription   --project-ref <NOVO_PROJECT_REF> --use-api
supabase functions deploy redeem-reward            --project-ref <NOVO_PROJECT_REF> --use-api
supabase functions deploy asaas-webhook            --project-ref <NOVO_PROJECT_REF> --use-api --no-verify-jwt
```

## 2.5 · Configurar o Auth (senão login/cadastro quebram)

No painel: **Authentication → URL Configuration** (⇄ precisa do domínio final da
Vercel — Parte 3):

- **Site URL:** o domínio final de produção (ex.: `https://casacoffeecolab.vercel.app`).
- **Redirect URLs:** listar **tanto** o domínio de prod **quanto** os de dev
  (`http://localhost:5173` e `http://localhost:4173`) — senão os links de
  **confirmação de e-mail** e **reset de senha** são rejeitados.
- **Authentication → Providers → Email:** **"Confirm email" LIGADO** pro go-live
  (pode desligar temporariamente só pra testar o happy-path local — e **re-ligar**
  antes de publicar).

## 2.6 · O que essa migração ARRASTA (⇄)

Como o `project-ref` mudou, **dois valores externos precisam acompanhar**:

- **Asaas — URL do webhook:** re-cadastrar apontando pra
  `https://<NOVO_PROJECT_REF>.functions.supabase.co/asaas-webhook` (Parte 1.5).
- **Vercel — client:** atualizar `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` pros
  valores do projeto novo (Parte 3.2).

## 2.7 · Checklist (Supabase)

- [ ] Projeto novo criado; `project-ref` e anon key anotados
- [ ] **Todas** as migrations `0001`→`0011` rodadas em ordem no SQL Editor
- [ ] `supabase link` no projeto novo
- [ ] Secrets `ASAAS_API_KEY` / `ASAAS_WEBHOOK_TOKEN` / `SITE_URL` setados
- [ ] **4 functions** deployadas (webhook com `--no-verify-jwt`)
- [ ] **Auth URL Configuration** (Site URL + Redirect URLs) + **Confirm email ON**
- [ ] ⇄ Webhook do Asaas re-cadastrado com a URL nova (Parte 1.5)
- [ ] ⇄ `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` atualizados na Vercel (Parte 3)

---

# Parte 3 — Vercel (hospedagem)

Publicar o front na conta Vercel do dono. É a migração mais leve — o site é estático
(build do Vite), **sem segredo nenhum** além das variáveis públicas `VITE_`.

## 3.1 · Importar o repositório

1. Dono conecta a conta Vercel ao repositório (GitHub/GitLab) e faz **Import Project**.
2. **Framework Preset:** Vite. Config já vem do `vite.config.js`:
   - **Build Command:** `npm run build`
   - **Output Directory:** `dist`
   - **Install Command:** `npm install`

## 3.2 · Variáveis de ambiente (Settings → Environment Variables)

Só as **públicas** do client (prefixo `VITE_`) — **nenhuma chave de pagamento**:

| Variável                  | Valor                                                        |
|---------------------------|-------------------------------------------------------------|
| `VITE_SUPABASE_URL`       | a Project URL do Supabase (⇄ se o Supabase migrou, a do projeto novo) |
| `VITE_SUPABASE_ANON_KEY`  | a anon/public key do Supabase                               |
| `VITE_SITE_URL`           | o domínio final de produção (base dos e-mails de auth)      |

## 3.3 · Domínio (se for usar um próprio)

Se o dono apontar um **domínio próprio** (ex.: `casacoffeecolab.com.br`) em
**Settings → Domains**, o domínio final muda — e **três valores precisam acompanhar** (⇄):

- **Supabase secret `SITE_URL`** → o novo domínio (Parte 1.4 / 2.3).
- **Vercel env `VITE_SITE_URL`** → o novo domínio (Parte 3.2).
- **Supabase → Auth → URL Configuration** → Site URL + Redirect URLs com o novo
  domínio (Parte 2.5).

> Enquanto ficar na URL `*.vercel.app`, nada disso muda.

## 3.4 · Checklist (Vercel)

- [ ] Repo importado; preset **Vite**, build `npm run build`, output `dist`
- [ ] `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` / `VITE_SITE_URL` setadas
- [ ] Deploy verde e o site abre
- [ ] (se domínio próprio) ⇄ `SITE_URL`, `VITE_SITE_URL` e Auth URLs atualizados
- [ ] Login/cadastro funcionam (e-mail de confirmação chega e o link volta certo)

---

## Referências

- `supabase/functions/README.md` — setup detalhado das functions + teste em sandbox.
- `CLAUDE.md` › **Pagamentos (Asaas)**, **Autenticação**, **Segurança**, **Migrations**.
- `scripts/security-check.mjs` (`npm run security-check`) + `scripts/check-rls.sql` —
  gate de segurança antes de publicar.
