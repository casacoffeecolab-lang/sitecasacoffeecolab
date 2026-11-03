// =============================================================================
// Casa Coffee Colab — asaas-webhook (Edge Function, Deno)
// Recebe os eventos do ASAAS e mantém orders/subscriptions/profiles + pontos em dia.
//
// SEGURANÇA (ver CLAUDE.md › Segurança):
//   • Autenticação do webhook: token compartilhado. O Asaas envia o token no
//     header `asaas-access-token` (definido ao cadastrar o webhook). A gente
//     compara com ASAAS_WEBHOOK_TOKEN (secret). Diferente → 401, sem processar.
//     (O Asaas NÃO assina o corpo com HMAC — a defesa é o token no header.)
//   • Idempotência/anti-replay: cada evento tem um `id` (evt_…). Se já está em
//     asaas_events, responde 200 e sai. Grava o id só ao final (após sucesso),
//     então uma entrega que FALHOU é reprocessada na retentativa do Asaas
//     ("at least once delivery").
//   • Escrita via service_role (ignora RLS). Pontos SEMPRE server-side (ledger).
//   • Comportamento idêntico em sandbox e prod — muda só a chave (secrets).
//
// NÃO precisa de JWT (quem chama é o Asaas, autenticado pelo token do header).
// Deploy com --no-verify-jwt.
//
// CORRELAÇÃO (ver create-checkout-session):
//   • LOJA: o checkout foi criado com externalReference = orders.id (UUID). Em
//     CHECKOUT_PAID a gente finaliza ESSE pedido (pendente → pago) e credita os
//     pontos. CHECKOUT_EXPIRED/CANCELED → cancela o pedido pendente.
//   • ASSINATURA (PONTE PELO ID DO CHECKOUT — ver migration 0012_asaas_checkout_link):
//     externalReference = `sub:<user_id>:<tier_slug>:<nonce>`. PROVADO POR LOG: o Asaas
//     NÃO propaga o nosso externalReference pra Subscription nem pros Payments
//     (GET /subscriptions?externalReference volta ∅; payment.externalReference ∅), e o
//     CHECKOUT_PAID NÃO traz o id da assinatura (só a config {cycle,nextDueDate}).
//     Nenhum evento carrega, sozinho, {user, tier, asaas_subscription_id}. O ÚNICO elo
//     comum às duas pontas é o ID DO CHECKOUT:
//       - CHECKOUT_PAID (tem user+tier via ref + checkout.id) → grava a linha em
//         subscriptions chaveada por asaas_checkout_id, status 'ativa', e espelha
//         profiles.tier_slug. O plano VINCULA aqui, sem depender do id da assinatura.
//       - PAYMENT_* (tem asaas_subscription_id + customer + checkoutSession = checkout.id)
//         → acha essa linha por asaas_checkout_id e CARIMBA asaas_subscription_id +
//         customer + status/período reais. Os PONTOS (1ª cobrança e renovações) são
//         creditados AQUI (por payment.id), nunca no CHECKOUT_PAID — assim não duplica e
//         as renovações (sem novo checkout, casadas por asaas_subscription_id) creditam.
// =============================================================================

import {
  supabaseAdmin,
  requireEnv,
  creditPoints,
  checkAchievements,
  asaasGet,
  asaasPut,
  reaisFromCentavos,
  centavosFromReais,
  getEffectiveSubscription,
} from '../_shared/lib.ts';

const WEBHOOK_TOKEN = requireEnv('ASAAS_WEBHOOK_TOKEN');

// INDICA UM AMIGO — recompensa em pontos quando o INDICADO paga a 1ª mensalidade.
// VALORES FICTÍCIOS (provisórios): ajustar aqui depois. Uma fonte de verdade só —
// a premiar_indicacao (0021) recebe estes números; o front /conta/perfil restata a
// mesma copy (procurar "VALOR FICTÍCIO" no app.js). Zerar um lado = não credita aquele lado.
const REFERRAL_PTS_INDICADOR = 150; // quem indicou
const REFERRAL_PTS_INDICADO = 100; // quem foi indicado (boas-vindas)

// --- helpers -----------------------------------------------------------------

// Compara o token recebido com o secret em TEMPO CONSTANTE (defesa contra timing
// side-channel — um `!==` de string curto-circuita no 1º char diferente, vazando
// prefixo/comprimento por timing). Compara os digests SHA-256 (32 bytes fixos), o
// que também esconde a diferença de comprimento. É barato e roda a cada webhook.
async function tokenConfere(recebido: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(recebido)),
    crypto.subtle.digest('SHA-256', enc.encode(WEBHOOK_TOKEN)),
  ]);
  const va = new Uint8Array(a);
  const vb = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < va.length; i++) diff |= va[i] ^ vb[i];
  return diff === 0;
}

// externalReference da assinatura → { userId, tierSlug }. Formato:
// `sub:<user_id>:<tier_slug>:<nonce>`. Retorna null se não for de assinatura.
function parseSubRef(ref: unknown): { userId: string; tierSlug: string } | null {
  if (typeof ref !== 'string' || !ref.startsWith('sub:')) return null;
  const parts = ref.split(':');
  const userId = parts[1];
  const tierSlug = parts[2];
  if (!userId || !tierSlug) return null;
  return { userId, tierSlug };
}

// externalReference de upgrade → { userId, toTier, asaasSubId }. Formato:
// `upg:<user_id>:<to_tier>:<asaas_subscription_id>:<nonce>`. Null se não for upgrade.
function parseUpgRef(
  ref: unknown,
): { userId: string; toTier: string; asaasSubId: string } | null {
  if (typeof ref !== 'string' || !ref.startsWith('upg:')) return null;
  const parts = ref.split(':');
  const userId = parts[1];
  const toTier = parts[2];
  const asaasSubId = parts[3];
  if (!userId || !toTier || !asaasSubId) return null;
  return { userId, toTier, asaasSubId };
}

// externalReference de presente → gift_id. Formato: `gift:<gift_id>`. Null se não
// for presente.
function parseGiftRef(ref: unknown): { giftId: string } | null {
  if (typeof ref !== 'string' || !ref.startsWith('gift:')) return null;
  const giftId = ref.split(':')[1];
  if (!giftId) return null;
  return { giftId };
}

// Aceita string ('cus_…') ou objeto ({ id }) — o Asaas varia por endpoint.
function idOf(v: unknown): string | null {
  if (!v) return null;
  if (typeof v === 'string') return v;
  if (typeof v === 'object' && v !== null && 'id' in v) return String((v as { id: unknown }).id);
  return null;
}

// UUID v-qualquer. Usado pra BLINDAR as queries `.eq('id'|'user_id', …)` em colunas
// uuid: um externalReference forjado/externo (checkout criado fora do nosso fluxo na
// MESMA conta Asaas) com id não-UUID faria o Postgres levantar 22P02 (invalid input
// syntax for uuid) — um erro PERMANENTE que, com o throw-on-error, viraria 500 eterno
// (poison event travando a fila). Filtrando ANTES, o não-UUID é descartado como órfão
// (200) e o throw fica reservado a erros REALMENTE transitórios.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function isUuid(v: unknown): v is string {
  return typeof v === 'string' && UUID_RE.test(v);
}

// Status da Subscription do Asaas → enum do banco (trial|ativa|pausada|cancelada).
function mapSubStatus(s: unknown): string {
  switch (String(s ?? '').toUpperCase()) {
    case 'ACTIVE':
      return 'ativa';
    case 'EXPIRED':
      return 'cancelada';
    case 'INACTIVE':
      return 'pausada';
    default:
      return 'ativa';
  }
}

// nextDueDate ('YYYY-MM-DD') → ISO (meia-noite) pra current_period_end. Null-safe.
function dueDateToIso(d: unknown): string | null {
  if (typeof d !== 'string' || !d) return null;
  const t = Date.parse(d);
  return Number.isNaN(t) ? null : new Date(t).toISOString();
}

// CHECKOUT_PAID → grava/atualiza a linha da assinatura a partir do externalReference
// (a ÚNICA fonte de user+tier), chaveada pelo asaas_checkout_id (checkout.id). NÃO
// depende do id da assinatura (o CHECKOUT_PAID não traz) nem do customer (que chega
// como objeto SEM id top-level). status='ativa' + current_period_end=null: já concede
// o benefício (getEffectiveSubscription concede pra 'ativa' mesmo com período null) e
// o PAYMENT depois carimba asaas_subscription_id + customer + período REAIS.
//
// Idempotente por asaas_checkout_id (índice único não-parcial da 0012). Envia SÓ as colunas
// que o CHECKOUT_PAID conhece — de propósito NÃO manda asaas_subscription_id/customer/
// current_period_end: assim um REENVIO do CHECKOUT_PAID (o Asaas martela o mesmo evento)
// NÃO apaga o que o PAYMENT já carimbou (no upsert, coluna ausente do payload não entra
// no SET do conflito).
async function activateSubscriptionRowByCheckout(args: {
  userId: string;
  tierSlug: string;
  checkoutId: string;
}): Promise<void> {
  const { userId, tierSlug, checkoutId } = args;
  const { error } = await supabaseAdmin.from('subscriptions').upsert(
    {
      user_id: userId,
      tier_slug: tierSlug,
      status: 'ativa',
      asaas_checkout_id: checkoutId,
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'asaas_checkout_id' },
  );
  if (error) throw error;
}

// PAYMENT → carimba a linha JÁ EXISTENTE (a que o CHECKOUT_PAID gravou) com o id da
// assinatura + customer + status/período reais. Atualiza pela PK (rowId) pra não criar
// duplicata nem esbarrar no UNIQUE de asaas_subscription_id. Só seta o que veio (não
// sobrescreve um período/customer bom com null).
//
// applyDowngradeTo: quando setado (renovação com downgrade AGENDADO), troca o
// tier_slug pro plano leve e LIMPA scheduled_downgrade_to — a descida vale a partir
// deste ciclo. Feito no MESMO update (atômico) que carimba o pagamento.
async function stampSubscriptionRow(
  rowId: string,
  args: {
    asaasSubId: string | null;
    customerId: string | null;
    status: string;
    periodEndIso: string | null;
    applyDowngradeTo?: string | null;
  },
): Promise<void> {
  const patch: Record<string, unknown> = { status: args.status, updated_at: new Date().toISOString() };
  if (args.asaasSubId) patch.asaas_subscription_id = args.asaasSubId;
  if (args.customerId) patch.asaas_customer_id = args.customerId;
  if (args.periodEndIso) patch.current_period_end = args.periodEndIso;
  if (args.applyDowngradeTo) {
    patch.tier_slug = args.applyDowngradeTo;
    patch.scheduled_downgrade_to = null;
  }
  const { error } = await supabaseAdmin.from('subscriptions').update(patch).eq('id', rowId);
  if (error) throw error;
}

// Busca a Subscription no Asaas por asaas_subscription_id (pra atualizar
// nextDueDate/status). Best-effort — retorna null se não achar.
async function fetchAsaasSubscription(subId: string): Promise<any | null> {
  try {
    return await asaasGet(`/subscriptions/${encodeURIComponent(subId)}`);
  } catch (err) {
    console.warn('[asaas-webhook] falha ao buscar subscription', subId, (err as Error).message);
    return null;
  }
}

// Existe profile pra esse user? Usado pra DESCARTAR (200, sem retry) eventos
// órfãos — ex.: um CHECKOUT_PAID/pagamento de um usuário que foi APAGADO (conta
// deletada). Sem isso, o upsert/creditPoints bateria na FK de profiles, o webhook
// daria 500 e o Asaas reenviaria pra sempre — podendo INTERROMPER a fila e travar
// os eventos novos que estão ATRÁS do órfão. Órfão não é erro nosso: é nada-a-fazer.
async function profileExists(userId: string): Promise<boolean> {
  // Não-UUID nunca existe em profiles (coluna uuid) e ainda dispararia 22P02 na
  // query: trata como ausência (órfão) sem tocar o banco. Blinda o throw abaixo.
  if (!isUuid(userId)) return false;
  const { data, error } = await supabaseAdmin
    .from('profiles')
    .select('id')
    .eq('id', userId)
    .maybeSingle();
  // Erro de consulta (rede/DB) NÃO é ausência de profile: propaga pra virar 500 e
  // o Asaas reenviar. `false` fica reservado pra ausência REAL (usuário apagado) —
  // senão um soluço transitório descartaria como órfão um evento legítimo (perde-se
  // a vinculação da assinatura pra sempre, sem retry).
  if (error) throw error;
  return !!data;
}

// Espelha o tier ativo no profiles + persiste o customer do Asaas (best-effort).
async function mirrorProfile(userId: string, tierSlug: string | null, customerId: string | null): Promise<void> {
  const patch: Record<string, unknown> = { tier_slug: tierSlug };
  if (customerId) patch.asaas_customer_id = customerId;
  const { error } = await supabaseAdmin.from('profiles').update(patch).eq('id', userId);
  if (error) throw error;
}

// =============================================================================
// LOJA — finaliza o pedido pré-criado (externalReference = orders.id).
// Idempotente: se já está no status alvo, não retrabalha (creditPoints também é
// idempotente por (order, order.id)). Nunca rebaixa um pedido já 'pago'.
// =============================================================================
async function finalizeStoreOrder(checkout: any, alvo: 'pago' | 'cancelado'): Promise<void> {
  const orderId = typeof checkout?.externalReference === 'string' ? checkout.externalReference : null;
  if (!orderId) {
    console.warn('[asaas-webhook] checkout de loja sem externalReference (order id)');
    return;
  }
  // Nossos pedidos usam SEMPRE order.id (uuid) como externalReference. Um id não-UUID
  // é de um checkout externo/forjado na mesma conta Asaas — descarta gracioso (200) em
  // vez de deixar o `.eq('id', <texto>)` estourar 22P02 e virar 500 eterno (poison).
  if (!isUuid(orderId)) {
    console.warn('[asaas-webhook] externalReference de loja não é UUID (checkout externo?), ignorando:', orderId);
    return;
  }

  const { data: order, error: orderErr } = await supabaseAdmin
    .from('orders')
    .select('id, user_id, status, total_centavos, tier_slug_aplicado')
    .eq('id', orderId)
    .maybeSingle();
  // Falha de consulta ≠ pedido inexistente: propaga (→ 500 → Asaas reenvia). Só o
  // `!order` limpo (sem erro) é ausência real — um pedido de outro fluxo/órfão.
  if (orderErr) throw orderErr;
  if (!order) {
    console.warn('[asaas-webhook] pedido não encontrado pra checkout:', orderId);
    return;
  }

  // Pedido já estornado não volta pra 'pago' num reenvio do CHECKOUT_PAID (o
  // dinheiro foi devolvido; o evento antigo não desfaz isso).
  if (order.status === 'estornado') return;
  // Nunca cancela/mexe num pedido que já foi pago.
  if (order.status === 'pago' && alvo === 'cancelado') return;
  // Só cancela pedidos ainda pendentes.
  if (alvo === 'cancelado' && order.status !== 'pendente') return;

  const customerId = idOf(checkout?.customer);
  const patch: Record<string, unknown> = { status: alvo, updated_at: new Date().toISOString() };
  if (order.status !== alvo) {
    const { error } = await supabaseAdmin.from('orders').update(patch).eq('id', order.id);
    if (error) throw error;
  }

  if (alvo !== 'pago') return;

  // Persiste o customer do Asaas no profile do dono (só se ainda não tiver).
  if (customerId && order.user_id) {
    await supabaseAdmin
      .from('profiles')
      .update({ asaas_customer_id: customerId })
      .eq('id', order.user_id)
      .is('asaas_customer_id', null);
  }

  // Pontos da COMPRA: total JÁ COM DESCONTO × multiplicador do tier. Idempotente
  // por (ref_type='order', ref_id=order.id).
  if (order.user_id) {
    await creditPoints({
      userId: order.user_id,
      valorCentavos: order.total_centavos,
      motivo: 'compra na loja',
      refType: 'order',
      refId: order.id,
      tierSlug: order.tier_slug_aplicado,
    });
    await checkAchievements(order.user_id); // Primeira Xícara, Café Viajante… best-effort
  }
}

// =============================================================================
// ASSINATURA — em CHECKOUT_PAID (ref `sub:`): grava a linha chaveada pelo checkout.id
// e espelha o tier. É o ÚNICO evento que carrega user+tier (via externalReference),
// então é o VINCULADOR. NÃO precisa do id da assinatura (que o Asaas NÃO manda aqui —
// o campo `subscription` do CHECKOUT_PAID é só config {cycle,nextDueDate}): o PAYMENT
// completa o asaas_subscription_id depois, casando pelo asaas_checkout_id (ponte — ver
// handleSubscriptionPayment). NÃO credita pontos aqui (isso é nos eventos de pagamento).
// NOTA: NÃO existe `GET /checkouts/{id}` no Asaas (dá 404); e GET /subscriptions?
// externalReference volta ∅ (o Asaas não indexa pelo nosso ref) — por isso a ponte
// pelo id do checkout, não mais a resolução do sub id aqui.
// =============================================================================
async function activateSubscription(checkout: any): Promise<void> {
  const parsed = parseSubRef(checkout?.externalReference);
  if (!parsed) {
    console.warn('[asaas-webhook] checkout de assinatura com externalReference inválido');
    return;
  }
  const { userId, tierSlug } = parsed;

  const checkoutId = typeof checkout?.id === 'string' ? checkout.id : null;
  if (!checkoutId) {
    // Sem o id do checkout não dá pra ancorar a ponte com o PAYMENT. Lança pra retry
    // (não deve acontecer — CHECKOUT_PAID sempre traz id).
    throw new Error('CHECKOUT_PAID sem checkout.id — retry');
  }

  // Usuário apagado (conta deletada) → descarta o evento (200, sem retry). Sem isso,
  // o upsert bateria na FK de profiles e daria 500 pra sempre, travando a fila.
  if (!(await profileExists(userId))) {
    console.warn('[asaas-webhook] checkout de assinatura de usuário inexistente — ignorando:', userId);
    return;
  }

  // Grava/atualiza a linha (status 'ativa'; sub_id/customer/período ficam pro PAYMENT) e
  // espelha o tier no profile — o plano VINCULA aqui, na hora.
  await activateSubscriptionRowByCheckout({ userId, tierSlug, checkoutId });
  await mirrorProfile(userId, tierSlug, null);
  await checkAchievements(userId); // conquistas de tier (ex.: virar assinante) best-effort
}

// =============================================================================
// UPGRADE — em CHECKOUT_PAID de um checkout `upg:`: a diferença proporcional foi
// paga. Sobe o value recorrente da assinatura no Asaas pro preço CHEIO do tier
// novo (vale do próximo vencimento em diante), atualiza a linha de subscriptions
// e espelha o tier no profile. Se estava pausada em graça, reativa. SEM pontos
// aqui — o delta é ajuste proporcional, não uma compra. Idempotente: reprocessar
// deixa tudo no mesmo estado.
// =============================================================================
async function applyUpgrade(checkout: any): Promise<void> {
  const parsed = parseUpgRef(checkout?.externalReference);
  if (!parsed) {
    console.warn('[asaas-webhook] checkout de upgrade com externalReference inválido');
    return;
  }
  const { userId, toTier, asaasSubId } = parsed;

  // Preço cheio do tier novo (do banco) → novo value da recorrência.
  const { data: tier, error: tierErr } = await supabaseAdmin
    .from('tiers')
    .select('slug, preco_centavos, ativo')
    .eq('slug', toTier)
    .maybeSingle();
  // Falha de LEITURA não é tier inválido: se engolisse, este upgrade já pago
  // sairia com 200, o evento viraria processado e o Asaas nunca reenviaria.
  // Jogando, o handler responde 500 sem gravar o evento → o Asaas reenvia.
  if (tierErr) throw tierErr;
  if (!tier || !tier.ativo || !tier.preco_centavos) {
    console.warn('[asaas-webhook] upgrade pra tier inválido:', toTier);
    return;
  }

  // Sobe o value da assinatura recorrente no Asaas e garante ACTIVE. Best-effort
  // no Asaas — a fonte do benefício é o banco (subscriptions/profiles).
  try {
    await asaasPut(`/subscriptions/${encodeURIComponent(asaasSubId)}`, {
      status: 'ACTIVE',
      value: reaisFromCentavos(tier.preco_centavos),
    });
  } catch (err) {
    console.error('[asaas-webhook] falha ao subir value no upgrade:', (err as Error).message);
  }

  // Reflete no banco: tier novo + ativa (por asaas_subscription_id). LIMPA
  // scheduled_downgrade_to: se havia uma descida agendada, o upgrade a cancela —
  // senão, na renovação, handleSubscriptionPayment aplicaria a descida e desfaria
  // este upgrade. Idempotente (reprocessar deixa null em null).
  const { error: uErr } = await supabaseAdmin
    .from('subscriptions')
    .update({
      tier_slug: toTier,
      status: 'ativa',
      scheduled_downgrade_to: null,
      updated_at: new Date().toISOString(),
    })
    .eq('asaas_subscription_id', asaasSubId);
  if (uErr) throw uErr;

  // Espelha o tier no profile (customerId=null: não mexe no asaas_customer_id, que
  // é o da assinatura, não o desta cobrança avulsa).
  await mirrorProfile(userId, toTier, null);
  await checkAchievements(userId); // best-effort
}

// =============================================================================
// PRESENTE — em CHECKOUT_PAID de um checkout `gift:`: o comprador pagou. Marca o
// presente como 'pago' e gera o código (via RPC atômica marcar_presente_pago).
// SEM pontos aqui (o presente pontua pra quem RESGATA, na renovação... não — o
// presente é avulso e não recorre; a pessoa que resgata ganha o BENEFÍCIO, não
// pontos pela compra do comprador). Idempotente: a RPC devolve o código
// existente num reenvio, sem regerar.
// =============================================================================
async function handleGiftPaid(checkout: any): Promise<void> {
  const parsed = parseGiftRef(checkout?.externalReference);
  if (!parsed) {
    console.warn('[asaas-webhook] checkout de presente com externalReference inválido');
    return;
  }
  // Presentes usam sempre gift.id (uuid). Não-UUID = checkout externo → descarta (200).
  if (!isUuid(parsed.giftId)) {
    console.warn('[asaas-webhook] externalReference de presente não é UUID, ignorando:', parsed.giftId);
    return;
  }
  const paymentId = idOf(checkout?.payment);
  const { error } = await supabaseAdmin.rpc('marcar_presente_pago', {
    p_gift_id: parsed.giftId,
    p_payment_id: paymentId,
  });
  if (error) throw error; // → 500 → Asaas reenvia (a RPC é idempotente)
}

// PRESENTE — CHECKOUT_EXPIRED/CANCELED de um `gift:`: cancela o presente ainda
// 'pendente' (não pago). Nunca mexe num presente já 'pago'/'resgatado'.
async function cancelGift(checkout: any): Promise<void> {
  const parsed = parseGiftRef(checkout?.externalReference);
  if (!parsed || !isUuid(parsed.giftId)) return;
  const { error } = await supabaseAdmin
    .from('gift_subscriptions')
    .update({ status: 'cancelado', updated_at: new Date().toISOString() })
    .eq('id', parsed.giftId)
    .eq('status', 'pendente');
  if (error) throw error;
}

// Idade do pagamento (pra bound do throw-to-retry lá embaixo). Se não der pra ler a
// data, retorna false (prefere reprocessar). Aceita os campos de data mais comuns do
// payload de pagamento do Asaas.
function pagamentoMuitoAntigo(payment: any): boolean {
  const raw = payment?.dateCreated ?? payment?.confirmedDate ?? payment?.paymentDate ?? payment?.clientPaymentDate;
  if (typeof raw !== 'string') return false;
  const t = Date.parse(raw);
  if (Number.isNaN(t)) return false;
  // BUG CORRIGIDO (comprovado em log): os campos de data do Asaas são DATE-ONLY
  // ("YYYY-MM-DD") → Date.parse assume MEIA-NOITE UTC. Um pagamento de HOJE processado às
  // 12h UTC parecia ter "12h de idade" e estourava o antigo limite de 6h → a gente
  // DESISTIA de vincular a assinatura (o PAYMENT perdia a corrida pro CHECKOUT_PAID e, em
  // vez de dar 500 pra retry, gravava 200 → o asaas_subscription_id NUNCA era carimbado →
  // "retomar" quebrava pra sempre). Correção: (1) se for date-only, dá a folga do dia
  // inteiro (o pagamento pode ter sido criado em qualquer hora daquele dia — mede pela
  // versão mais RECENTE possível, fim do dia) e (2) sobe o limite pra 3 dias — muito além
  // da corrida normal (segundos), então só descarta órfão de longuíssimo prazo.
  const dateOnly = /^\d{4}-\d{2}-\d{2}$/.test(raw.trim());
  const folgaMs = dateOnly ? 24 * 60 * 60 * 1000 : 0;
  const idadeMs = Math.max(0, Date.now() - t - folgaMs);
  return idadeMs > 3 * 24 * 60 * 60 * 1000; // > 3 dias (com folga do dia p/ date-only)
}

// =============================================================================
// PAGAMENTO de assinatura (PAYMENT_CONFIRMED/RECEIVED) — acha a linha que o
// CHECKOUT_PAID gravou (ponte pelo asaas_checkout_id = payment.checkoutSession),
// CARIMBA o asaas_subscription_id + customer + status/período reais e credita os
// pontos. Ignora pagamentos de LOJA (DETACHED, sem subscription). Idempotente por
// (ref_type='subscription', ref_id=payment.id).
// =============================================================================
async function handleSubscriptionPayment(payment: any): Promise<void> {
  const asaasSubId = idOf(payment?.subscription);
  const checkoutSession = typeof payment?.checkoutSession === 'string' ? payment.checkoutSession : null;
  const parsed = parseSubRef(payment?.externalReference);

  // É pagamento de assinatura? Loja é DETACHED (sem subscription id). Sem subscription id
  // E sem ref `sub:` → não é nosso fluxo de assinatura → ignora.
  if (!asaasSubId && !parsed) return;

  // Resolve a LINHA de subscriptions por cascata de confiança:
  //  (1) asaas_subscription_id      → renovações e 1ª cobrança já carimbada.
  //  (2) asaas_checkout_id = checkoutSession → A PONTE: casa com a linha que o
  //      CHECKOUT_PAID gravou (user+tier). É o elo da 1ª cobrança.
  let subRow: { id: string; user_id: string; tier_slug: string; scheduled_downgrade_to: string | null } | null = null;
  if (asaasSubId) {
    const { data } = await supabaseAdmin
      .from('subscriptions')
      .select('id, user_id, tier_slug, scheduled_downgrade_to')
      .eq('asaas_subscription_id', asaasSubId)
      .maybeSingle();
    if (data) { subRow = data; }
  }
  if (!subRow && checkoutSession) {
    const { data } = await supabaseAdmin
      .from('subscriptions')
      .select('id, user_id, tier_slug, scheduled_downgrade_to')
      .eq('asaas_checkout_id', checkoutSession)
      .maybeSingle();
    if (data) { subRow = data; }
  }

  // CORRIDA DE ORDEM (comprovada em log): o PAYMENT_CONFIRMED e o CHECKOUT_PAID chegam
  // quase juntos (~100ms). Quando o PAYMENT ganha, a linha que o CHECKOUT grava (por
  // asaas_checkout_id) ainda não existe → byCheckout volta ∅. Como o PAYMENT já traz o
  // asaas_subscription_id REAL e o checkoutSession, vale esperar um instante e reconsultar
  // a PONTE na MESMA invocação — assim o vínculo fecha na hora, sem depender do retry (bem
  // mais lento) do Asaas. Janela curta e barata (~1,6s no pior caso); só acontece nessa
  // corrida específica (renovação casa por bySubId; PAYMENT tardio casa de primeira).
  if (!subRow && checkoutSession && asaasSubId) {
    for (let tent = 0; tent < 4 && !subRow; tent++) {
      await new Promise((r) => setTimeout(r, 400));
      const { data } = await supabaseAdmin
        .from('subscriptions')
        .select('id, user_id, tier_slug, scheduled_downgrade_to')
        .eq('asaas_checkout_id', checkoutSession)
        .maybeSingle();
      if (data) { subRow = data; }
    }
  }

  let userId: string | null = subRow?.user_id ?? null;
  let tierSlug: string | null = subRow?.tier_slug ?? null;
  // Fallback: se o pagamento carregar o nosso ref `sub:` (raro — quase sempre ∅), usa-o.
  if ((!userId || !tierSlug) && parsed) { userId = parsed.userId; tierSlug = parsed.tierSlug; }

  if (!userId || !tierSlug) {
    // É nosso (tem subscription id) mas a linha ainda não existe: o CHECKOUT_PAID que a
    // grava provavelmente ainda não foi processado (corrida de ordem — o PAYMENT chegou
    // primeiro). LANÇA pra o Asaas reenviar — SEGURO: comprovado em log que um 500 NÃO
    // bloqueia a fila (um CHECKOUT_PAID em erro é reenviado sozinho enquanto PAYMENTs
    // seguem em 200). Na retentativa a linha já existe e resolve. Guard de idade: se o
    // pagamento já é bem antigo (>3 dias) e ainda não há linha, o checkoutSession não deve
    // ser o checkout.id esperado — desiste com graça (evita martelar 500 pra sempre; o
    // diag acima revela o checkoutSession real pra ajuste). Corridas normais resolvem em
    // minutos, muito dentro da janela.
    if (pagamentoMuitoAntigo(payment)) {
      console.warn('[asaas-webhook] pagamento de assinatura sem linha (antigo — desistindo):', payment?.id);
      return;
    }
    throw new Error('linha da assinatura ainda não gravada (CHECKOUT_PAID pendente) — retry');
  }

  // Usuário apagado → descarta (200, sem retry). Sem isso, creditPoints bateria na
  // FK de points_ledger→profiles e daria 500 pra sempre, travando a fila.
  if (!(await profileExists(userId))) {
    console.warn('[asaas-webhook] pagamento de assinatura de usuário inexistente — ignorando:', userId);
    return;
  }

  // DOWNGRADE AGENDADO: a pessoa pediu pra descer de plano e escolhemos aplicar no
  // PRÓXIMO ciclo (ver downgrade-subscription). Este pagamento é a RENOVAÇÃO — a hora
  // de efetivar. Se a linha tem scheduled_downgrade_to (≠ do tier atual), o tier
  // EFETIVO daqui pra frente é o plano leve. Aplicar ANTES do stamp/mirror/pontos
  // garante que os pontos desta cobrança já contam pelo multiplicador NOVO (menor) e
  // que o valor já é o menor (o value recorrente foi baixado quando agendamos).
  // Idempotente: o stamp limpa scheduled_downgrade_to no mesmo update, então um
  // reprocessamento não reaplica (a coluna já vem null). Só vale quando há subRow
  // (self-heal por ref não tem agendamento). O motivo do ledger continua 'assinatura'.
  const scheduledTo = subRow?.scheduled_downgrade_to ?? null;
  const aplicandoDowngrade = !!scheduledTo && scheduledTo !== tierSlug;
  const tierEfetivo = aplicandoDowngrade ? (scheduledTo as string) : tierSlug;

  // Status/período REAIS do gateway (nunca chuta — ver auditoria Raiz B). Best-effort:
  // se o fetch falhar, mantém 'ativa' e não mexe no período (o pagamento aconteceu).
  const customerId = idOf(payment?.customer);
  const asaasSub = asaasSubId ? await fetchAsaasSubscription(asaasSubId) : null;
  const statusReal = asaasSub ? mapSubStatus(asaasSub.status) : 'ativa';
  const periodEndIso = asaasSub ? dueDateToIso(asaasSub?.nextDueDate) : null;

  if (subRow) {
    // Carimba a linha existente (a do CHECKOUT_PAID) com sub_id + customer + status/período.
    // Se há downgrade agendado, o MESMO update troca o tier pro leve e limpa o agendamento.
    await stampSubscriptionRow(subRow.id, {
      asaasSubId,
      customerId,
      status: statusReal,
      periodEndIso,
      applyDowngradeTo: aplicandoDowngrade ? tierEfetivo : null,
    });
  } else if (asaasSubId) {
    // Self-heal (raro): resolvemos user/tier pelo ref DO PAGAMENTO mas não havia linha.
    // Cria por asaas_subscription_id (UNIQUE) pra não perder o vínculo.
    const { error } = await supabaseAdmin.from('subscriptions').upsert(
      {
        user_id: userId,
        tier_slug: tierEfetivo,
        status: statusReal,
        asaas_subscription_id: asaasSubId,
        asaas_customer_id: customerId,
        current_period_end: periodEndIso,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'asaas_subscription_id' },
    );
    if (error) throw error;
  }

  // Espelha o tier (EFETIVO) no profile só se a assinatura CONCEDE benefício agora (ativa).
  if (statusReal === 'ativa') await mirrorProfile(userId, tierEfetivo, customerId);

  // Pontos: valor REAL pago × multiplicador do tier EFETIVO. Idempotente por
  // (subscription, payment.id).
  const valorCentavos = centavosFromReais(Number(payment?.value ?? 0));
  if (valorCentavos > 0) {
    await creditPoints({
      userId,
      valorCentavos,
      motivo: 'assinatura',
      refType: 'subscription',
      refId: String(payment.id),
      tierSlug: tierEfetivo,
    });
    await checkAchievements(userId); // conquistas de tempo de casa best-effort
  }

  // CASA CLUB: a categoria é TEMPO DE CASA, e este é o único evento mensal que o
  // site recebe de graça — por isso a promoção mora aqui, e não num cron. A RPC
  // recalcula tudo pelo banco (união dos períodos), só escreve quando a categoria
  // muda de verdade, e carimba a conquista do marco. A tela do clube refaz a mesma
  // conta na leitura, então uma falha aqui se conserta na próxima visita: best-effort
  // de propósito, não vale derrubar o processamento de um pagamento por causa disso.
  const { error: catErr } = await supabaseAdmin.rpc('sincronizar_categoria', { p_user: userId });
  if (catErr) console.error('[asaas-webhook] falha ao sincronizar a categoria do clube:', catErr);

  // INDICA UM AMIGO: se ESTE pagante entrou por indicação pendente, premia os dois.
  // Idempotente (a RPC só processa vínculo 'pendente' → 'premiado'); no caso normal
  // (sem indicação) retorna rewarded:false sem erro. Se der erro de DB, deixa
  // estourar: o Asaas reenvia e a premiação/pontos são idempotentes.
  const { error: indErr } = await supabaseAdmin.rpc('premiar_indicacao', {
    p_referred_id: userId,
    p_pontos_indicador: REFERRAL_PTS_INDICADOR,
    p_pontos_indicado: REFERRAL_PTS_INDICADO,
  });
  if (indErr) throw indErr;
}

// =============================================================================
// FALHA de cobrança de assinatura (PAYMENT_OVERDUE/DELETED/REFUNDED/CHARGEBACK).
// Sem isso, uma RENOVAÇÃO que o cartão recusa deixaria a linha travada em 'ativa'
// com current_period_end no passado — e getEffectiveSubscription concede benefício
// pra QUALQUER linha 'ativa' (a checagem de período só vale pra 'pausada'). Ou
// seja: renovação falha = plano de graça pra sempre. (Ver auditoria, Raiz B.)
//
// Correção: ao falhar, pausa a assinatura no BANCO (status='pausada', SEM mexer no
// período — que já está vencido, então não concede). Se o cartão for recuperado
// depois (o Asaas continua tentando), o PAYMENT_CONFIRMED reativa via
// handleSubscriptionPayment. Self-heal do profiles.tier_slug via
// getEffectiveSubscription (limpa se nenhuma assinatura concede mais).
//
// A LINHA é resolvida pela MESMA cascata do handler de pagamento: (1) asaas_subscription_id
// (renovações / 1ª cobrança já carimbada), (2) asaas_checkout_id = checkoutSession (a PONTE
// — pega a linha que o CHECKOUT_PAID gravou MESMO se o asaas_subscription_id ainda não foi
// carimbado). Sem o passo (2), uma 1ª cobrança que falha numa assinatura recém-vinculada
// (linha 'ativa' sem sub_id) ficaria travada em 'ativa' concedendo o tier de graça — porque
// getEffectiveSubscription concede pra QUALQUER 'ativa' — sem NENHUM caminho pra rebaixar.
//
// NÃO tocamos no gateway aqui (o Asaas já sabe do overdue e gerencia a retentativa
// dele). Só refletimos o estado no nosso banco. Ignora pagamentos de LOJA/avulsos.
async function handleSubscriptionPaymentFailure(payment: any): Promise<void> {
  const asaasSubId = idOf(payment?.subscription);
  const checkoutSession = typeof payment?.checkoutSession === 'string' ? payment.checkoutSession : null;
  const parsed = parseSubRef(payment?.externalReference);
  if (!asaasSubId && !parsed) return; // cobrança de loja/avulsa não recorre → ignora

  let subRow: { id: string; user_id: string; status: string } | null = null;
  if (asaasSubId) {
    const { data } = await supabaseAdmin
      .from('subscriptions')
      .select('id, user_id, status')
      .eq('asaas_subscription_id', asaasSubId)
      .maybeSingle();
    if (data) subRow = data;
  }
  if (!subRow && checkoutSession) {
    const { data } = await supabaseAdmin
      .from('subscriptions')
      .select('id, user_id, status')
      .eq('asaas_checkout_id', checkoutSession)
      .maybeSingle();
    if (data) subRow = data;
  }

  let userId: string | null = subRow?.user_id ?? null;

  // Só rebaixa se estava 'ativa' (não sobrescreve uma 'cancelada'/'pausada' já
  // decidida por outro fluxo). Mantém current_period_end (vencido/null → sem grant).
  if (subRow && subRow.status === 'ativa') {
    const { error: uErr } = await supabaseAdmin
      .from('subscriptions')
      .update({ status: 'pausada', updated_at: new Date().toISOString() })
      .eq('id', subRow.id);
    if (uErr) throw uErr;
  }

  if (!userId && parsed) userId = parsed.userId;

  // Self-heal do tier: se NENHUMA assinatura concede mais, limpa profiles.tier_slug.
  if (userId) await getEffectiveSubscription(userId);
}

// ESTORNO DE PONTOS — quando um pagamento é estornado (refund) ou vira chargeback,
// os pontos que ele creditou precisam voltar; senão dá pra pagar → ganhar pontos →
// resgatar recompensa → pedir chargeback e ficar com tudo. Lança um delta NEGATIVO
// no ledger (o cache do saldo pode ir a negativo — é o correto: a pessoa "deve"
// pontos, e resgates só voltam a passar quando o saldo cobre de novo). Só estorna o
// que foi DE FATO creditado; nada creditado (não-assinante, valor 0) → no-op.
//
// Os dois fluxos creditam com chaves diferentes, então são dois caminhos:
//   • ASSINATURA — crédito em (ref_type='subscription', ref_id=payment.id), então o
//     próprio id do pagamento acha. Estorno em (ref_type='estorno', ref_id=payment.id).
//   • LOJA — crédito em (ref_type='order', ref_id=order.id): o id do pagamento não
//     aparece em lugar nenhum do crédito. A ponte é o `payment.checkoutSession`, que
//     é o `orders.asaas_checkout_id` gravado na criação do checkout. Estorno em
//     (ref_type='estorno_order', ref_id=order.id) — ref_type distinto do crédito pra
//     conviver com ele no UNIQUE (ref_type, ref_id).
// Idempotente nos dois: REFUNDED e CHARGEBACK do MESMO pagamento estornam uma vez só.
async function reversePointsForPayment(payment: any): Promise<void> {
  const paymentId = idOf(payment);
  if (!paymentId) return;

  const { data: credito, error: selErr } = await supabaseAdmin
    .from('points_ledger')
    .select('user_id, delta')
    .eq('ref_type', 'subscription')
    .eq('ref_id', paymentId)
    .gt('delta', 0)
    .maybeSingle();
  if (selErr) throw selErr;

  if (credito && Number(credito.delta) > 0) {
    const { error: insErr } = await supabaseAdmin.from('points_ledger').insert({
      user_id: credito.user_id,
      delta: -Number(credito.delta),
      motivo: 'estorno da assinatura',
      descricao: 'estorno da assinatura',
      ref_type: 'estorno',
      ref_id: paymentId,
    });
    // 23505 = já estornado (segundo evento do mesmo pagamento) → idempotente, ok.
    if (insErr && insErr.code !== '23505') throw insErr;
    return;
  }

  // Não era assinatura: pode ser uma compra na loja.
  await reverseStoreOrderForPayment(payment);
}

// ESTORNO DA LOJA — devolve os pontos da compra E tira o pedido da fila. Sem a
// segunda parte o pedido seguiria 'pago' pra quem separa e entrega, com o dinheiro
// já devolvido. Carimba também o `asaas_payment_id` (que até aqui nunca era
// gravado), pra o pedido guardar de qual pagamento ele veio.
async function reverseStoreOrderForPayment(payment: any): Promise<void> {
  const checkoutSession = typeof payment?.checkoutSession === 'string' ? payment.checkoutSession : null;
  if (!checkoutSession) return; // cobrança avulsa fora do nosso checkout → nada a fazer

  const { data: order, error: orderErr } = await supabaseAdmin
    .from('orders')
    .select('id, user_id, status')
    .eq('asaas_checkout_id', checkoutSession)
    .maybeSingle();
  if (orderErr) throw orderErr;
  if (!order) return; // checkout de assinatura/presente, ou pedido de outro fluxo

  if (order.status !== 'estornado') {
    const { error } = await supabaseAdmin
      .from('orders')
      .update({
        status: 'estornado',
        asaas_payment_id: idOf(payment),
        updated_at: new Date().toISOString(),
      })
      .eq('id', order.id);
    if (error) throw error;
  }

  if (!order.user_id) return;

  const { data: credito, error: selErr } = await supabaseAdmin
    .from('points_ledger')
    .select('user_id, delta')
    .eq('ref_type', 'order')
    .eq('ref_id', order.id)
    .gt('delta', 0)
    .maybeSingle();
  if (selErr) throw selErr;
  if (!credito || !(Number(credito.delta) > 0)) return; // não pontuou → nada a estornar

  const { error: insErr } = await supabaseAdmin.from('points_ledger').insert({
    user_id: credito.user_id,
    delta: -Number(credito.delta),
    motivo: 'estorno da compra',
    descricao: 'estorno da compra',
    ref_type: 'estorno_order',
    ref_id: order.id,
  });
  if (insErr && insErr.code !== '23505') throw insErr;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('método não permitido', { status: 405 });

  // 1) Autenticação do webhook (token compartilhado no header do Asaas).
  // Comparação em tempo constante (ver tokenConfere) — não usar `!==` direto.
  const token = req.headers.get('asaas-access-token') ?? '';
  if (!(await tokenConfere(token))) {
    console.warn('[asaas-webhook] token inválido/ausente no header asaas-access-token');
    return new Response('não autorizado', { status: 401 });
  }

  // 2) Corpo (JSON). O Asaas manda { id, event, dateCreated, ...payload }.
  let evt: any;
  try {
    evt = await req.json();
  } catch {
    return new Response('JSON inválido', { status: 400 });
  }

  // O id do evento vem como `evt_<hash>&<sequencia>`. A chave de idempotência é o id
  // INTEIRO (com o sufixo). Já tentamos usar só a parte antes do `&` pra deduplicar
  // reenvios do mesmo evento — mas o sandbox do Asaas REUTILIZA o mesmo `<hash>` base
  // entre eventos GENUINAMENTE distintos (checkouts/pagamentos diferentes, dias
  // diferentes). Com a chave base, o 1º CHECKOUT_PAID gravava `evt_<hash>` e TODO
  // pagamento seguinte (mesmo hash) era descartado como "duplicado" → a assinatura
  // NUNCA vinculava. Usar o id inteiro é seguro: os handlers já são idempotentes por
  // objeto de negócio (creditPoints por payment.id; order por id; subscription por
  // asaas_subscription_id via upsert), então, no pior caso, um reenvio só refaz um
  // upsert inócuo — nunca duplica pontos nem pula um evento legítimo.
  const eventId: string | null = evt?.id ?? null;
  const eventType: string = evt?.event ?? '';
  if (!eventId || !eventType) return new Response('payload sem id/event', { status: 400 });

  // 3) Idempotência: se já processamos esse event.id, sai com 200.
  const { data: jaVisto } = await supabaseAdmin
    .from('asaas_events')
    .select('id')
    .eq('id', eventId)
    .maybeSingle();
  if (jaVisto) return new Response(JSON.stringify({ received: true, duplicate: true }), { status: 200 });

  // 4) Processa.
  try {
    switch (eventType) {
      // ---- Checkout ----
      case 'CHECKOUT_PAID': {
        const checkout = evt.checkout ?? {};
        const ref = typeof checkout.externalReference === 'string' ? checkout.externalReference : '';
        if (ref.startsWith('sub:')) {
          await activateSubscription(checkout);
        } else if (ref.startsWith('upg:')) {
          await applyUpgrade(checkout);
        } else if (ref.startsWith('gift:')) {
          await handleGiftPaid(checkout);
        } else {
          await finalizeStoreOrder(checkout, 'pago');
        }
        break;
      }
      case 'CHECKOUT_EXPIRED':
      case 'CHECKOUT_CANCELED': {
        const checkout = evt.checkout ?? {};
        const ref = typeof checkout.externalReference === 'string' ? checkout.externalReference : '';
        // Só a LOJA e o PRESENTE pré-criam linha pra cancelar. Assinatura (sub:) e
        // upgrade (upg:) não pré-criam, então não há nada a reverter neles.
        if (ref.startsWith('gift:')) {
          await cancelGift(checkout);
        } else if (!ref.startsWith('sub:') && !ref.startsWith('upg:')) {
          await finalizeStoreOrder(checkout, 'cancelado');
        }
        break;
      }

      // ---- Pagamento (assinatura: 1ª cobrança + renovações) ----
      case 'PAYMENT_CONFIRMED':
      case 'PAYMENT_RECEIVED': {
        await handleSubscriptionPayment(evt.payment ?? {});
        break;
      }

      // ---- Falha de cobrança de assinatura (renovação recusada / dispute) ----
      // Rebaixa a assinatura pra 'pausada' pra o benefício não persistir de graça.
      // OVERDUE/DELETED/DISPUTE não estornam pontos: uma renovação vencida ou uma
      // disputa aberta não é (ainda) dinheiro devolvido — só pausa o benefício.
      case 'PAYMENT_OVERDUE':
      case 'PAYMENT_DELETED':
      case 'PAYMENT_CHARGEBACK_DISPUTE': {
        await handleSubscriptionPaymentFailure(evt.payment ?? {});
        break;
      }

      // ---- Estorno de verdade (dinheiro devolvido) ----
      // Além de pausar, ESTORNA os pontos creditados por aquele pagamento — senão
      // dá pra pagar → ganhar pontos → resgatar → pedir chargeback e ficar com tudo.
      case 'PAYMENT_REFUNDED':
      case 'PAYMENT_CHARGEBACK_REQUESTED': {
        await handleSubscriptionPaymentFailure(evt.payment ?? {});
        await reversePointsForPayment(evt.payment ?? {});
        break;
      }

      default:
        // Evento que não tratamos: ignora (mas registra como visto pra não voltar).
        break;
    }
  } catch (err) {
    // Falhou → NÃO grava asaas_events; o Asaas reenvia e a gente reprocessa
    // (a idempotência dos créditos/pedidos protege contra duplicar). Responde 500.
    // Tipo e id do evento vêm do CORPO que o Asaas manda, ou seja, de fora.
    // Passados como argumentos, um "%s" plantado ali não forja a linha do log.
    console.error('[asaas-webhook] erro processando:', eventType, eventId, err);
    return new Response('erro ao processar', { status: 500 });
  }

  // 5) Marca o event.id como processado (idempotência).
  const { error: insErr } = await supabaseAdmin
    .from('asaas_events')
    .insert({ id: eventId, event: eventType });
  if (insErr && insErr.code !== '23505') {
    console.error('[asaas-webhook] falha ao registrar event.id:', insErr);
    return new Response('erro ao registrar evento', { status: 500 });
  }

  return new Response(JSON.stringify({ received: true }), { status: 200 });
});
