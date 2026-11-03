// =============================================================================
// Casa Coffee Colab — resume-subscription (Edge Function, Deno)
// "Retomar o plano": reativa a MESMA assinatura pausada no Asaas, SEM cobrar do
// zero. Contrapartida do cancel-subscription (que pausa em vez de deletar).
//
// Como funciona (PUT /subscriptions/{id} status=ACTIVE):
//   • Ainda no período pago (current_period_end no futuro): mantém o nextDueDate
//     original → NENHUMA cobrança agora; volta a cobrar normal no vencimento. Como
//     já está pago, concede o benefício NA HORA ('ativa' + tier no profile).
//   • Período já vencido (graça acabou): reativa com nextDueDate = hoje → o Asaas
//     cobra o cartão salvo e começa um novo ciclo. Aqui a gente NÃO concede na hora
//     (o cartão pode recusar): a linha segue 'pausada' (vencida) e quem promove pra
//     'ativa' + espelha o tier + credita pontos é o webhook, no PAYMENT_CONFIRMED.
//     Retorna { cobranca_em_processamento: true } pra UI avisar que tá processando.
//
// SEGURANÇA (ver CLAUDE.md › Segurança):
//   • Exige JWT válido. Só o DONO retoma a PRÓPRIA assinatura (lê a linha DELE,
//     nunca id vindo do client).
//   • Escrita via service_role. Garante profiles.tier_slug = tier retomado.
//   • Idêntico em sandbox e prod — muda só a chave (secrets).
//
// Retorna: { ok: true, retomada: true, proxima_cobranca } (no período: benefício já
// vale) — ou { ok, retomada, cobranca_em_processamento: true } (vencido: aguarda o
// pagamento confirmar) — ou erro gentil.
// =============================================================================

import {
  supabaseAdmin,
  handleCors,
  jsonResponse,
  getUserFromRequest,
  asaasPut,
  AsaasError,
} from '../_shared/lib.ts';

// Date ISO/Date → 'YYYY-MM-DD' (formato que o Asaas espera em nextDueDate).
function toAsaasDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

Deno.serve(async (req) => {
  const pre = handleCors(req);
  if (pre) return pre;

  if (req.method !== 'POST') return jsonResponse({ error: 'método não permitido' }, 405);

  // 1) Só usuário autenticado.
  const user = await getUserFromRequest(req);
  if (!user) return jsonResponse({ error: 'não autenticado' }, 401);

  // 2) Acha a assinatura PAUSADA do próprio usuário (a mais recente).
  const { data: sub, error: subErr } = await supabaseAdmin
    .from('subscriptions')
    .select('id, tier_slug, asaas_subscription_id, status, current_period_end')
    .eq('user_id', user.id)
    .eq('status', 'pausada')
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (subErr) {
    console.error('[resume-subscription] erro ao ler subscriptions', subErr);
    return jsonResponse({ error: 'não deu pra ler tua assinatura agora' }, 500);
  }
  if (!sub) {
    return jsonResponse({ error: 'a gente não achou uma assinatura pausada no teu nome' }, 404);
  }

  // 2.1) Assinatura SEM vínculo no Asaas (asaas_subscription_id nulo): é linha
  // antiga/incompleta — o webhook nunca carimbou o id da assinatura no gateway. Não
  // dá pra "retomar" o que não existe lá. Fingir sucesso (o comportamento antigo,
  // caía no ramo 'cobranca_em_processamento') deixaria a pessoa presa em 'pausada'
  // pra sempre, esperando um PAYMENT_CONFIRMED que nunca vem. Ser honesto: sinaliza
  // pra UI oferecer "assinar de novo" (é uma assinatura nova, ciclo do zero).
  if (!sub.asaas_subscription_id) {
    console.warn('[resume-subscription] pausada sem asaas_subscription_id (não reativável):', sub.id);
    return jsonResponse(
      {
        error: 'essa assinatura ficou sem vínculo com o gateway, então não dá pra retomar aqui. bora assinar de novo?',
        precisa_reassinar: true,
        tier_slug: sub.tier_slug,
      },
      409,
    );
  }

  // 3) nextDueDate: se ainda estamos no período pago, mantém a data original
  // (sem cobrança agora). Se já venceu, cobra a partir de hoje.
  const now = Date.now();
  const periodEndMs = sub.current_period_end ? Date.parse(sub.current_period_end) : NaN;
  const aindaNoPeriodo = Number.isFinite(periodEndMs) && periodEndMs > now;
  const nextDue = aindaNoPeriodo ? new Date(periodEndMs) : new Date(now);
  const nextDueStr = toAsaasDate(nextDue);

  try {
    // 4) Reativa no Asaas (PUT status=ACTIVE + nextDueDate calculado).
    if (sub.asaas_subscription_id) {
      await asaasPut(`/subscriptions/${encodeURIComponent(sub.asaas_subscription_id)}`, {
        status: 'ACTIVE',
        nextDueDate: nextDueStr,
      });
    }

    // 5) Reflete no banco — DEPENDE de já ter sido pago ou não:
    if (aindaNoPeriodo) {
      // Ainda no período JÁ PAGO: o benefício já é dele e não há cobrança agora.
      // Concede na hora, MANTENDO o current_period_end original (não empurra a data).
      const periodIso = new Date(periodEndMs).toISOString();
      const { error: uErr } = await supabaseAdmin
        .from('subscriptions')
        .update({
          status: 'ativa',
          current_period_end: periodIso,
          updated_at: new Date().toISOString(),
        })
        .eq('id', sub.id);
      if (uErr) throw uErr;

      const { error: pErr } = await supabaseAdmin
        .from('profiles')
        .update({ tier_slug: sub.tier_slug })
        .eq('id', user.id);
      if (pErr) throw pErr;

      return jsonResponse({ ok: true, retomada: true, proxima_cobranca: periodIso });
    }

    // Período VENCIDO: o PUT acima dispara uma cobrança NOVA (nextDueDate=hoje) no
    // cartão salvo — que PODE recusar. Então NÃO concede benefício agora: não marca
    // 'ativa', não espelha o tier, não mexe no current_period_end (deixa vencido, pra
    // getEffectiveSubscription não conceder). Quem promove pra 'ativa' + espelha o
    // tier + grava o current_period_end real (~hoje+ciclo) + credita pontos é o
    // webhook, no PAYMENT_CONFIRMED/RECEIVED. (Ver auditoria, Raiz B — B2/B4.)
    return jsonResponse({
      ok: true,
      retomada: true,
      cobranca_em_processamento: true,
      proxima_cobranca: nextDueStr,
    });
  } catch (err) {
    if (err instanceof AsaasError) {
      console.error('[resume-subscription] Asaas', err.status, err.payload);
      return jsonResponse({ error: 'não deu pra retomar no gateway agora' }, 502);
    }
    console.error('[resume-subscription]', err);
    return jsonResponse({ error: 'não deu pra retomar agora' }, 500);
  }
});
