// =============================================================================
// Casa Coffee Colab — delete-account (Edge Function, Deno)
// "excluir minha conta" no /conta/perfil. Apaga o usuário do auth; o resto cai
// por cascata (profiles.id → auth.users on delete cascade, e todo o resto
// referencia profiles.id on delete cascade).
//
// COM ASSINATURA ATIVA A GENTE NÃO APAGA (409): encerrar o plano é um passo
// separado e consciente. Pausada não barra — pausar já É o encerrar da nossa UI.
//
// ORDEM IMPORTA: primeiro a gente ENCERRA as assinaturas no Asaas, só depois
// apaga a conta. Se apagasse antes e o DELETE no gateway falhasse, a pessoa
// continuaria sendo cobrada todo mês sem conta pra reclamar — e a gente não
// teria mais o asaas_subscription_id pra achar. Aqui é DELETE mesmo (não o
// PUT status=INACTIVE do cancel-subscription): não existe "retomar" depois de
// apagar a conta.
//
// SEGURANÇA (ver CLAUDE.md › Segurança):
//   • Exige JWT válido (getUserFromRequest). A pessoa só apaga a PRÓPRIA conta —
//     o id vem do token, NUNCA do corpo da requisição.
//   • Escrita via service_role, só dentro da function.
//   • Comportamento idêntico em sandbox e prod — muda só a chave (secrets).
//
// Retorna: { ok: true, apagada: true } — ou erro gentil.
// =============================================================================

import {
  supabaseAdmin,
  handleCors,
  jsonResponse,
  getUserFromRequest,
  asaasDelete,
  AsaasError,
} from '../_shared/lib.ts';

Deno.serve(async (req) => {
  const pre = handleCors(req);
  if (pre) return pre;

  if (req.method !== 'POST') return jsonResponse({ error: 'método não permitido' }, 405);

  const user = await getUserFromRequest(req);
  if (!user) return jsonResponse({ error: 'não autenticado' }, 401);

  // 1) Assinatura ATIVA barra a exclusão. Encerrar o plano é um passo separado e
  // consciente (a tela de "gerenciar assinatura" faz isso) — ninguém apaga a
  // conta no meio de um ciclo pago sem saber que tá abrindo mão do que pagou.
  //
  // Pausada NÃO barra: pausar já é o "encerrar" da nossa UI (PUT status=INACTIVE
  // no Asaas, não cobra mais). Se barrasse, a pessoa ficaria presa até o fim do
  // período sem ação nenhuma capaz de destravar.
  const { data: ativa, error: ativaErr } = await supabaseAdmin
    .from('subscriptions')
    .select('id, tier_slug')
    .eq('user_id', user.id)
    .eq('status', 'ativa')
    .limit(1)
    .maybeSingle();

  if (ativaErr) {
    console.error('[delete-account] erro ao checar assinatura ativa', ativaErr);
    return jsonResponse({ error: 'não deu pra apagar agora' }, 500);
  }

  if (ativa) {
    return jsonResponse(
      {
        error: 'encerra tua assinatura antes de apagar a conta',
        assinatura_ativa: true,
        tier_slug: ativa.tier_slug ?? null,
      },
      409,
    );
  }

  // 1b) Assinatura recém-paga com o webhook ainda a caminho: a create-checkout-session
  // deixa a linha como 'pendente' antes de mandar pro Asaas, e o CHECKOUT_PAID é quem
  // a promove a 'ativa'. Sem esta trava, apagar a conta nesse intervalo deixaria uma
  // recorrência órfã cobrando o cartão de quem já não existe aqui. Só barra dentro da
  // janela do checkout (60 min, o minutesToExpire) — passado isso o link já expirou e
  // um checkout abandonado não pode prender ninguém.
  const limitePendente = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { data: pendente, error: pendErr } = await supabaseAdmin
    .from('subscriptions')
    .select('id')
    .eq('user_id', user.id)
    .eq('status', 'pendente')
    .gte('created_at', limitePendente)
    .limit(1)
    .maybeSingle();

  if (pendErr) {
    console.error('[delete-account] erro ao checar assinatura pendente', pendErr);
    return jsonResponse({ error: 'não deu pra apagar agora' }, 500);
  }

  if (pendente) {
    return jsonResponse(
      {
        error: 'tem um pagamento de assinatura sendo confirmado agora. espera uns minutinhos e tenta de novo 💛',
        assinatura_processando: true,
      },
      409,
    );
  }

  // 2) Toda assinatura que ainda pode gerar cobrança (pausada dentro do período).
  // Cancelada já não cobra — mas listar não custa e evita fantasma.
  const { data: subs, error: subErr } = await supabaseAdmin
    .from('subscriptions')
    .select('id, asaas_subscription_id')
    .eq('user_id', user.id)
    .not('asaas_subscription_id', 'is', null);

  if (subErr) {
    console.error('[delete-account] erro ao ler subscriptions', subErr);
    return jsonResponse({ error: 'não deu pra apagar agora' }, 500);
  }

  // 3) Encerra cada uma no gateway. 404 = já não existe lá, segue o baile.
  // Qualquer outro erro ABORTA: melhor a conta continuar de pé do que existir
  // uma cobrança recorrente sem dono.
  try {
    for (const sub of subs ?? []) {
      try {
        await asaasDelete(`/subscriptions/${encodeURIComponent(sub.asaas_subscription_id)}`);
      } catch (err) {
        if (!(err instanceof AsaasError) || err.status !== 404) throw err;
      }
    }
  } catch (err) {
    if (err instanceof AsaasError) {
      console.error('[delete-account] Asaas', err.status, err.payload);
      return jsonResponse({ error: 'não deu pra encerrar tua assinatura agora' }, 502);
    }
    console.error('[delete-account]', err);
    return jsonResponse({ error: 'não deu pra apagar agora' }, 500);
  }

  // 4) Apaga a foto de perfil. O cascata do banco NÃO alcança o Storage — sem
  // isso sobraria o rosto de alguém que pediu pra sumir. Vai ANTES do delete:
  // se falhar aqui, a conta continua de pé e dá pra tentar de novo; se fosse
  // depois, uma falha deixaria a foto órfã sem dono pra reclamar.
  const { data: fotos, error: listErr } = await supabaseAdmin.storage
    .from('avatares')
    .list(user.id);

  if (!listErr && fotos?.length) {
    const { error: rmErr } = await supabaseAdmin.storage
      .from('avatares')
      .remove(fotos.map((f) => `${user.id}/${f.name}`));
    if (rmErr) {
      console.error('[delete-account] erro ao apagar avatar', rmErr);
      return jsonResponse({ error: 'não deu pra apagar agora' }, 500);
    }
  }

  // 5) Apaga o usuário. O cascata leva profiles, orders, points_ledger,
  // subscriptions, redemptions e as conquistas junto.
  const { error: delErr } = await supabaseAdmin.auth.admin.deleteUser(user.id);
  if (delErr) {
    console.error('[delete-account] erro ao apagar usuário', delErr);
    return jsonResponse({ error: 'não deu pra apagar agora' }, 500);
  }

  return jsonResponse({ ok: true, apagada: true });
});
