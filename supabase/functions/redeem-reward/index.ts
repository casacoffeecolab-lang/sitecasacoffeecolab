// =============================================================================
// Casa Coffee Colab — redeem-reward (Edge Function, Deno)
// Resgata uma recompensa do rewards_catalog usando pontos. TODA a lógica de
// saldo/estoque/atomicidade fica na função SQL redeem_reward (SECURITY DEFINER,
// com lock na linha do reward) — o client NUNCA calcula saldo.
//
// SEGURANÇA (ver CLAUDE.md › Segurança):
//   • Valida o JWT e usa o id do PRÓPRIO usuário (nunca um id vindo do client).
//   • Chama a RPC via service_role (a redeem_reward é revogada de anon/authenticated,
//     então o client não consegue chamá-la direto passando outro user_id).
//   • Idempotência/atomicidade: garantidas no banco (lock + unique do ledger).
//
// Recebe: { reward_id: uuid }
// Retorna: { ok, saldo, reward, codigo? } ou { error } com mensagem gentil.
// =============================================================================

import { supabaseAdmin, handleCors, jsonResponse, getUserFromRequest, checkAchievements } from '../_shared/lib.ts';

Deno.serve(async (req) => {
  const pre = handleCors(req);
  if (pre) return pre;

  if (req.method !== 'POST') return jsonResponse({ error: 'método não permitido' }, 405);

  const user = await getUserFromRequest(req);
  if (!user) return jsonResponse({ error: 'não autenticado' }, 401);

  let body: { reward_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'JSON inválido' }, 400);
  }
  const rewardId = body.reward_id;
  if (typeof rewardId !== 'string' || !rewardId) {
    return jsonResponse({ error: 'reward_id obrigatório' }, 400);
  }

  // Chama a função SQL atômica com o id VERIFICADO do usuário (do JWT).
  const { data, error } = await supabaseAdmin.rpc('redeem_reward', {
    p_user_id: user.id,
    p_reward_id: rewardId,
  });

  if (error) {
    console.error('[redeem-reward]', error);
    return jsonResponse({ error: 'não deu pra resgatar agora' }, 500);
  }

  // A função retorna { ok:false, erro } pros casos de negócio (saldo/esgotado).
  if (!data || data.ok !== true) {
    return jsonResponse({ error: data?.erro ?? 'não deu pra resgatar', ...data }, 400);
  }

  // Resgate ok → reavalia conquistas (ex.: primeiro resgate). Best-effort: não
  // pode derrubar a resposta de sucesso do resgate se falhar.
  await checkAchievements(user.id);

  return jsonResponse(data);
});
