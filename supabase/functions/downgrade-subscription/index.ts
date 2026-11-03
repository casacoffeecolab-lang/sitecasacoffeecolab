// =============================================================================
// Casa Coffee Colab — downgrade-subscription (Edge Function, Deno)
// "Ficar num plano mais leve" — o espelho INVERTIDO do upgrade. Em vez de cobrar
// a diferença e subir na hora, a gente AGENDA a descida pro próximo ciclo:
//   • A pessoa MANTÉM o tier atual (e todos os benefícios) até o fim do período
//     JÁ PAGO (current_period_end) — nada de reembolso, nada de cobrança agora.
//   • A mensalidade recorrente do Asaas já baixa pro preço do plano leve (o PUT
//     do `value` só afeta a PRÓXIMA cobrança gerada; o ciclo atual, já pago, não
//     muda). No próximo vencimento a renovação vem no valor menor.
//   • O tier só troca DE FATO quando o pagamento da renovação cai — quem faz isso
//     é o webhook (asaas-webhook › handleSubscriptionPayment), que lê
//     `scheduled_downgrade_to`, troca o tier ANTES de creditar pontos (pra creditar
//     já no multiplicador novo) e LIMPA a coluna.
//
// Duas ações (mesma function):
//   • AGENDAR    (body { tier_slug: <plano leve> }): valida a assinatura ATIVA do
//                próprio usuário, exige tier de destino MAIS BARATO, baixa o value
//                no Asaas e grava scheduled_downgrade_to — SEM mexer no tier atual.
//   • DESFAZER   (body { acao: 'cancelar' }): limpa scheduled_downgrade_to e
//                restaura o value cheio no Asaas (volta a renovar no plano atual).
//
// SEGURANÇA (ver CLAUDE.md › Segurança):
//   • Exige JWT válido. Só o DONO agenda/desfaz na PRÓPRIA assinatura (lê a linha
//     DELE, nunca id vindo do client). NUNCA confia em preço do client — os dois
//     preços saem do BANCO (tiers) pelo slug.
//   • Escrita via service_role. MANTÉM profiles.tier_slug (benefício segue vivo).
//   • value↔coluna sempre consistentes: se um passo falhar, reverte o outro (nunca
//     deixa "value baixo sem downgrade agendado" nem "downgrade agendado com value
//     cheio"). Espelha o padrão de revert do modo upgrade do create-checkout-session.
//   • Idêntico em sandbox e prod — muda só a chave (secrets).
//
// Retorna (agendar):  { ok, agendado: true, efetivo_em, novo_plano, novo_slug }
//         (desfazer): { ok, desfeito: true }  — ou erro gentil.
// =============================================================================

import {
  supabaseAdmin,
  handleCors,
  jsonResponse,
  getUserFromRequest,
  asaasPut,
  reaisFromCentavos,
  AsaasError,
} from '../_shared/lib.ts';

Deno.serve(async (req) => {
  const pre = handleCors(req);
  if (pre) return pre;

  if (req.method !== 'POST') return jsonResponse({ error: 'método não permitido' }, 405);

  // 1) Só usuário autenticado.
  const user = await getUserFromRequest(req);
  if (!user) return jsonResponse({ error: 'não autenticado' }, 401);

  // 2) Body.
  let body: { tier_slug?: unknown; acao?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'JSON inválido' }, 400);
  }
  const desfazer = body.acao === 'cancelar';

  // DESLIGADO PELO CASA CLUB (ago/2026), não removido. O clube virou UMA
  // assinatura e as categorias passaram a ser tempo de casa: não existe plano
  // mais leve pra onde descer. O código do agendamento segue inteiro abaixo e
  // volta a valer quando existir mais de uma categoria vendável.
  //
  // DESFAZER continua passando de propósito: quem agendou uma descida ANTES da
  // virada precisa poder cancelar ela, senão a assinatura renovaria pelo valor
  // baixo de um plano que não existe mais.
  if (!desfazer) {
    const { count: vendaveis } = await supabaseAdmin
      .from('tiers')
      .select('slug', { count: 'exact', head: true })
      .eq('vendavel', true)
      .eq('ativo', true);
    if ((vendaveis ?? 0) <= 1) {
      return jsonResponse(
        {
          error:
            'agora o clube é uma assinatura só 💛 não tem plano mais leve pra onde descer, e o que tu já ficou de casa continua guardado contigo.',
        },
        400,
      );
    }
  }

  // 3) Assinatura ATIVA do próprio usuário (a mais recente por período). O
  // downgrade só faz sentido numa assinatura que o Asaas ainda renova — por isso
  // 'ativa' (não 'pausada', que já é o fluxo de cancelar). Nunca id do client.
  const { data: sub, error: subErr } = await supabaseAdmin
    .from('subscriptions')
    .select('id, tier_slug, asaas_subscription_id, status, current_period_end, scheduled_downgrade_to')
    .eq('user_id', user.id)
    .eq('status', 'ativa')
    .order('current_period_end', { ascending: false, nullsFirst: false })
    .limit(1)
    .maybeSingle();

  if (subErr) {
    console.error('[downgrade-subscription] erro ao ler subscriptions', subErr);
    return jsonResponse({ error: 'não deu pra ler tua assinatura agora' }, 500);
  }
  if (!sub) {
    return jsonResponse({ error: 'a gente não achou uma assinatura ativa no teu nome' }, 404);
  }
  if (!sub.asaas_subscription_id) {
    // Sem vínculo no gateway não dá pra mexer no value da recorrência.
    return jsonResponse(
      { error: 'essa assinatura ficou sem vínculo com o gateway, então não dá pra mudar o plano por aqui' },
      409,
    );
  }
  const asaasSubId = encodeURIComponent(sub.asaas_subscription_id);

  try {
    // =========================================================================
    // DESFAZER — "manter o plano atual". Limpa o agendamento e volta a renovar no
    // preço cheio do tier atual.
    // =========================================================================
    if (desfazer) {
      if (!sub.scheduled_downgrade_to) {
        // Nada agendado — idempotente, responde ok sem mexer em nada.
        return jsonResponse({ ok: true, desfeito: true, nada_a_fazer: true });
      }

      // Preço cheio do tier ATUAL (pra restaurar o value) e do agendado (pra
      // reverter em caso de falha). Ambos do BANCO.
      const { data: tiersData, error: tErr } = await supabaseAdmin
        .from('tiers')
        .select('slug, preco_centavos')
        .in('slug', [sub.tier_slug, sub.scheduled_downgrade_to]);
      if (tErr) return jsonResponse({ error: 'erro ao buscar os planos' }, 500);
      const atual = (tiersData ?? []).find((t) => t.slug === sub.tier_slug);
      const agendado = (tiersData ?? []).find((t) => t.slug === sub.scheduled_downgrade_to);
      if (!atual || !atual.preco_centavos || atual.preco_centavos <= 0) {
        return jsonResponse({ error: 'plano atual indisponível' }, 400);
      }

      // 1) Limpa a coluna (fonte da verdade que o webhook lê). 2) Restaura o value
      // cheio no Asaas. Se o Asaas falhar, RE-AGENDA a coluna (volta pro destino)
      // pra value↔coluna seguirem consistentes (value baixo ↔ downgrade agendado).
      const { error: clrErr } = await supabaseAdmin
        .from('subscriptions')
        .update({ scheduled_downgrade_to: null, updated_at: new Date().toISOString() })
        .eq('id', sub.id);
      if (clrErr) throw clrErr;

      try {
        await asaasPut(`/subscriptions/${asaasSubId}`, {
          value: reaisFromCentavos(atual.preco_centavos),
        });
      } catch (asaasErr) {
        // Reverte a coluna pro destino agendado — best-effort — pra não sobrar
        // "value baixo sem downgrade agendado" (renovaria barato sem trocar o tier).
        if (agendado) {
          const { error: revErr } = await supabaseAdmin
            .from('subscriptions')
            .update({ scheduled_downgrade_to: agendado.slug, updated_at: new Date().toISOString() })
            .eq('id', sub.id);
          if (revErr) console.error('[downgrade-subscription] falha ao re-agendar após erro no Asaas:', revErr);
        }
        throw asaasErr;
      }

      return jsonResponse({ ok: true, desfeito: true });
    }

    // =========================================================================
    // AGENDAR — descer pro plano leve no próximo ciclo.
    // =========================================================================
    const toSlug = typeof body.tier_slug === 'string' ? body.tier_slug.trim() : '';
    if (!toSlug) {
      return jsonResponse({ error: 'informe o tier_slug do plano mais leve' }, 400);
    }
    if (toSlug === sub.tier_slug) {
      return jsonResponse({ error: 'você já está nesse plano' }, 400);
    }

    // Preços dos DOIS tiers, do BANCO. Exige destino ATIVO e MAIS BARATO.
    const { data: tiersData, error: tErr } = await supabaseAdmin
      .from('tiers')
      .select('slug, nome, preco_centavos, ordem, ativo')
      .in('slug', [sub.tier_slug, toSlug]);
    if (tErr) return jsonResponse({ error: 'erro ao buscar os planos' }, 500);
    const atual = (tiersData ?? []).find((t) => t.slug === sub.tier_slug);
    const novo = (tiersData ?? []).find((t) => t.slug === toSlug);

    if (!novo || !novo.ativo || !novo.preco_centavos || novo.preco_centavos <= 0) {
      return jsonResponse({ error: 'plano de destino indisponível' }, 400);
    }
    if (!atual || !atual.preco_centavos || atual.preco_centavos <= 0) {
      return jsonResponse({ error: 'plano atual indisponível' }, 400);
    }
    if (novo.preco_centavos >= atual.preco_centavos) {
      // Subir de preço é UPGRADE (outro fluxo, cobra a diferença). Aqui só desce.
      return jsonResponse({ error: 'esse plano não é mais leve que o teu atual' }, 400);
    }

    // Já tem ESTE mesmo downgrade agendado? Idempotente, não repete o PUT.
    if (sub.scheduled_downgrade_to === toSlug) {
      return jsonResponse({
        ok: true,
        agendado: true,
        efetivo_em: sub.current_period_end,
        novo_plano: novo.nome,
        novo_slug: toSlug,
        ja_estava: true,
      });
    }

    // 1) Baixa o value recorrente no Asaas (só a PRÓXIMA cobrança vem menor; o
    // ciclo atual já pago não muda). 2) Grava o agendamento no banco — SEM mexer
    // no tier atual (benefício segue até current_period_end). Se o banco falhar,
    // restaura o value cheio no Asaas (revert) e devolve 500, pra não deixar
    // "value baixo sem downgrade agendado".
    await asaasPut(`/subscriptions/${asaasSubId}`, {
      value: reaisFromCentavos(novo.preco_centavos),
    });

    const { error: updErr } = await supabaseAdmin
      .from('subscriptions')
      .update({ scheduled_downgrade_to: toSlug, updated_at: new Date().toISOString() })
      .eq('id', sub.id);
    if (updErr) {
      try {
        await asaasPut(`/subscriptions/${asaasSubId}`, {
          value: reaisFromCentavos(atual.preco_centavos),
        });
      } catch (revErr) {
        console.error('[downgrade-subscription] falha ao reverter value no Asaas:', revErr);
      }
      throw updErr;
    }

    return jsonResponse({
      ok: true,
      agendado: true,
      efetivo_em: sub.current_period_end, // quando a troca de tier acontece (renovação)
      novo_plano: novo.nome,
      novo_slug: toSlug,
    });
  } catch (err) {
    if (err instanceof AsaasError) {
      console.error('[downgrade-subscription] Asaas', err.status, err.payload);
      return jsonResponse({ error: 'não deu pra mudar teu plano no gateway agora' }, 502);
    }
    console.error('[downgrade-subscription]', err);
    return jsonResponse({ error: 'não deu pra mudar teu plano agora' }, 500);
  }
});
