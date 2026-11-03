# Roteamento modelo / effort — Casa Coffee Colab

> Regra oficial de qual **modelo** e qual **effort** usar em cada tipo de trabalho
> deste repo. Clonada da base do GASTROMUNDI e adaptada aos arquivos reais do site.

## [1] Propósito

Existe pra não decidir modelo/effort do zero a cada tarefa, e pra não queimar
orçamento em trabalho que não exige. Consultou aqui, escolheu, seguiu.

## [2] Princípio base

Modelo e effort são **alavancas independentes**. Modelo mais novo **não** autoriza
baixar effort em trabalho difícil. Effort alto em tarefa simples é desperdício;
effort baixo em tarefa difícil é bug em produção.

## [3] Tabela de roteamento

| Modelo | Effort | Quando usar | Exemplo real no repo |
|--------|--------|-------------|----------------------|
| **Opus 5** | `xhigh` | erro silencioso custa dinheiro ou quebra RLS/compliance | aritmética de cobrança em centavos — delta proporcional de upgrade e downgrade agendado: `supabase/functions/create-checkout-session/index.ts`, `supabase/functions/downgrade-subscription/index.ts`; idempotência de webhook + crédito de pontos: `supabase/functions/asaas-webhook/index.ts`; RLS e trava anti-tamper de pontos: `supabase/migrations/0002_rls.sql`, `supabase/migrations/0008_points.sql`; resgate atômico com lock: `supabase/functions/redeem-reward/index.ts` |
| **Sonnet 5** | `high` | default do dia a dia | tela/componente e header-footer-menu: `src/app.js`; estilos: `src/styles.css`; console admin: `src/admin.js`; páginas `.html`, query, refactor, revisão de PR |
| **Haiku 4.5** | `low` | volume mecânico sem julgamento | seed de tiers/produtos/conquistas: `supabase/migrations/0003_seed.sql`; boilerplate; doc gerada de spec já aprovada |

## [4] Teste de decisão

**"Consigo justificar Opus em uma frase?"** Não → Sonnet.

- *"Trocar o texto de um botão do drawer no `app.js`"* → não justifica Opus (é
  microcopy/UI) → **Sonnet**.
- *"Mexer no cálculo do delta proporcional do upgrade, que cobra o cartão do
  cliente"* → justifica em uma frase (conta errada = valor errado cobrado) →
  **Opus xhigh**.

## [5] Parâmetros técnicos

- `xhigh` exige `max_tokens` grande (base **64k**) pra não truncar no meio de tool
  calls / subagentes.
- O effort default da API é `high`; o valor passado **sobrescreve**.
- `temperature` / `top_p` / `top_k` **não** são suportados — guie por prompt.

## [6] Antipadrões

- Rodar tudo em Opus `xhigh` "por segurança" — queima orçamento sem ganho.
- Baixar effort no meio de um review longo — ele passa a aprovar o que não checou.
- Trocar de modelo sem revisar o prompt.
- Pular a spec — retrabalho custa mais token que effort alto.

## [7] Revisão

Última revisão: **3/ago/2026**. Revisar quando sair modelo novo (nova família
Claude) ou quando o custo mensal fugir do esperado.
