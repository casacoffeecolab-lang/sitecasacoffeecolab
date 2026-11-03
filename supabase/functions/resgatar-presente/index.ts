// =============================================================================
// Casa Coffee Colab — resgatar-presente (Edge Function, Deno)
// Resgata um presente (assinatura dada por outra pessoa) pelo CÓDIGO. Toda a
// lógica de validação/atomicidade fica na RPC resgatar_presente (SECURITY
// DEFINER, com lock na linha do presente) — o client nunca varre a tabela nem
// concede benefício sozinho.
//
// SEGURANÇA (ver CLAUDE.md › Segurança):
//   • Valida o JWT e usa o id do PRÓPRIO usuário (nunca um id vindo do client).
//   • Chama a RPC via service_role (resgatar_presente é revogada de anon/
//     authenticated) — o client não consegue chamá-la direto passando outro id.
//   • Atomicidade/anti-duplo-resgate: garantidas no banco (lock + status).
//
// Recebe: { codigo: string }
// Retorna: { ok, tier, tier_nome, ativo_ate } ou { error } (mensagem gentil).
// =============================================================================

import { supabaseAdmin, handleCors, jsonResponse, getUserFromRequest, checkAchievements } from '../_shared/lib.ts';

Deno.serve(async (req) => {
  const pre = handleCors(req);
  if (pre) return pre;

  if (req.method !== 'POST') return jsonResponse({ error: 'método não permitido' }, 405);

  const user = await getUserFromRequest(req);
  if (!user) return jsonResponse({ error: 'não autenticado' }, 401);

  let body: { codigo?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'JSON inválido' }, 400);
  }
  const codigo = body.codigo;
  if (typeof codigo !== 'string' || !codigo.trim()) {
    return jsonResponse({ error: 'digita o código do presente 💛' }, 400);
  }

  // Chama a RPC atômica com o id VERIFICADO do usuário (do JWT).
  const { data, error } = await supabaseAdmin.rpc('resgatar_presente', {
    p_user_id: user.id,
    p_codigo: codigo,
  });

  if (error) {
    console.error('[resgatar-presente]', error);
    return jsonResponse({ error: 'não deu pra resgatar agora' }, 500);
  }

  // A RPC retorna { ok:false, erro } pros casos de negócio (código inválido, já
  // resgatado, já tem plano vigente).
  if (!data || data.ok !== true) {
    return jsonResponse({ error: data?.erro ?? 'não deu pra resgatar', ...data }, 400);
  }

  // Resgate ok → reavalia conquistas (ex.: virar gente do Casa). Best-effort: não
  // pode derrubar a resposta de sucesso.
  await checkAchievements(user.id);

  return jsonResponse(data);
});
