// =============================================================================
// Casa Coffee Colab — cancel-subscription (Edge Function, Deno)
// O Asaas NÃO tem portal de cobrança hospedado (como o Billing Portal do Stripe),
// então a gente tem a NOSSA tela. Aqui "cancelar" = PAUSAR: a pessoa para de ser
// cobrada, MAS mantém o benefício até o fim do período já pago
// (current_period_end). Depois é só "retomar" (resume-subscription) — sem pagar
// de novo, reativando a MESMA assinatura no Asaas.
//
// Por que pausar em vez de deletar: o checkout hospedado do Asaas cobra na hora
// que a pessoa digita o cartão. Se a gente deletasse, "retomar" viraria um novo
// checkout cobrando do zero. Pausar (PUT status=INACTIVE) para as próximas
// cobranças sem perder a assinatura — reativar (status=ACTIVE) não gera cobrança
// nova enquanto o nextDueDate estiver no futuro.
//
// SEGURANÇA (ver CLAUDE.md › Segurança):
//   • Exige JWT válido (getUserFromRequest). Só o DONO pausa a PRÓPRIA
//     assinatura — a gente lê a linha de subscriptions DELE (nunca um id vindo
//     do client) e é essa que mandamos pausar no Asaas.
//   • Escrita via service_role (auth.uid()=null → passa pelo prevent_points_tamper).
//     Em pausa, MANTÉM profiles.tier_slug (o benefício segue até o vencimento).
//   • Comportamento idêntico em sandbox e prod — muda só a chave (secrets).
//
// Retorna: { ok: true, pausada: true, ativo_ate } — ou { ok, cancelada: true } se
// o Asaas já não tiver a assinatura — ou erro gentil.
// =============================================================================

import {
  supabaseAdmin,
  handleCors,
  jsonResponse,
  getUserFromRequest,
  asaasPut,
  AsaasError,
} from '../_shared/lib.ts';

Deno.serve(async (req) => {
  const pre = handleCors(req);
  if (pre) return pre;

  if (req.method !== 'POST') return jsonResponse({ error: 'método não permitido' }, 405);

  // 1) Só usuário autenticado.
  const user = await getUserFromRequest(req);
  if (!user) return jsonResponse({ error: 'não autenticado' }, 401);

  // 2) Acha TODAS as assinaturas ATIVAS do próprio usuário. Normalmente é uma só,
  // mas a trava anti-duplicação é recente — contas antigas podem ter mais de uma
  // linha 'ativa' (bug histórico). Pausar UMA só deixaria a(s) outra(s) cobrando o
  // cartão todo mês. Então pausamos TODAS. A mais recente (por current_period_end)
  // define o `ativo_ate` que devolvemos pra UI.
  const { data: subs, error: subErr } = await supabaseAdmin
    .from('subscriptions')
    .select('id, asaas_subscription_id, status, current_period_end')
    .eq('user_id', user.id)
    .eq('status', 'ativa')
    .order('current_period_end', { ascending: false, nullsFirst: false });

  if (subErr) {
    console.error('[cancel-subscription] erro ao ler subscriptions', subErr);
    return jsonResponse({ error: 'não deu pra ler tua assinatura agora' }, 500);
  }
  if (!subs || subs.length === 0) {
    return jsonResponse({ error: 'a gente não achou uma assinatura ativa no teu nome' }, 404);
  }

  // Linha 'ativa' ainda SEM asaas_subscription_id: o CHECKOUT_PAID grava a linha e
  // é o PAYMENT_* que carimba o id da recorrência — existe uma janela de segundos
  // entre os dois. Se seguisse, o laço abaixo pularia o PUT no gateway e mesmo
  // assim marcaria 'pausada': a UI diria "pausado" com o cartão ainda sendo
  // cobrado todo mês. Igual ao que resume-subscription e downgrade-subscription
  // já fazem: para aqui e pede pra tentar de novo daqui a pouco.
  if (subs.some((s) => !s.asaas_subscription_id)) {
    return jsonResponse(
      {
        error: 'tua assinatura ainda tá sendo confirmada. tenta de novo daqui a pouquinho? 💛',
        sem_vinculo: true,
      },
      409,
    );
  }

  try {
    // 3) Pausa CADA assinatura no Asaas (PUT status=INACTIVE) e reflete no banco.
    // Um 404 numa linha (assinatura sumiu do gateway) não aborta as demais: essa
    // vira 'cancelada' de vez; as outras seguem sendo pausadas.
    const pausadas: typeof subs = []; // linhas que ficaram 'pausada' (benefício vivo)
    for (const sub of subs) {
      let sumiu = false;
      if (sub.asaas_subscription_id) {
        try {
          await asaasPut(`/subscriptions/${encodeURIComponent(sub.asaas_subscription_id)}`, {
            status: 'INACTIVE',
          });
        } catch (err) {
          if (err instanceof AsaasError && err.status === 404) {
            sumiu = true; // assinatura já não existe no Asaas → encerrar de vez
          } else {
            throw err; // erro de rede/5xx → deixa o Asaas/retry lidar (aborta tudo)
          }
        }
      }

      // Reflete no banco. Sumiu no gateway → 'cancelada' (não há período a manter).
      // Senão → 'pausada' MANTENDO tier_slug e current_period_end (benefício segue
      // até o fim do período pago).
      const novoStatus = sumiu ? 'cancelada' : 'pausada';
      const { error: uErr } = await supabaseAdmin
        .from('subscriptions')
        .update({ status: novoStatus, updated_at: new Date().toISOString() })
        .eq('id', sub.id);
      if (uErr) throw uErr;
      if (!sumiu) pausadas.push(sub);
    }

    // 4) Decide o benefício. Se SOBROU alguma pausada, o benefício segue vivo até o
    // fim do maior período pago entre elas — mantém o tier no profile. Se TODAS
    // sumiram do gateway (nada pausado), encerra de vez: limpa o tier.
    if (pausadas.length === 0) {
      await supabaseAdmin.from('profiles').update({ tier_slug: null }).eq('id', user.id);
      return jsonResponse({ ok: true, cancelada: true, ativo_ate: null });
    }

    // ativo_ate = maior current_period_end entre as que ficaram pausadas (subs já
    // vem ordenado desc por current_period_end, então a 1ª pausada é a maior).
    const ativoAte = pausadas[0].current_period_end ?? null;
    return jsonResponse({ ok: true, pausada: true, ativo_ate: ativoAte });
  } catch (err) {
    if (err instanceof AsaasError) {
      console.error('[cancel-subscription] Asaas', err.status, err.payload);
      return jsonResponse({ error: 'não deu pra pausar no gateway agora' }, 502);
    }
    console.error('[cancel-subscription]', err);
    return jsonResponse({ error: 'não deu pra pausar agora' }, 500);
  }
});
