// =============================================================================
// Casa Coffee Colab — postar-mural (Edge Function, Deno)
// Deixa um recado no "Mural do Casa" (/o-casa). Perk EXCLUSIVO de assinante:
// só quem tem plano vigente escreve (mesma regra dos pontos). Validação e gating
// 100% server-side — o client nunca decide quem pode postar.
//
// SEGURANÇA (ver CLAUDE.md › Segurança):
//   • Exige JWT válido (getUserFromRequest).
//   • "É assinante vigente?" via getEffectiveSubscription (status/período, não
//     confia no profiles.tier_slug cru nem no client). Sem plano → 403 gentil.
//   • Sanitiza o texto (trim, tira caracteres de controle, limita 240) e grava um
//     SNAPSHOT do primeiro nome — o mural não lê profiles de terceiros.
//   • Escrita via service_role (a tabela nega INSERT pro client; ver 0020_mural).
//   • Anti-flood leve: 30s entre recados do mesmo usuário.
//
// Recebe: { texto: string }
// Retorna: { ok, note } ou { error } (mensagem gentil).
// =============================================================================

import {
  supabaseAdmin,
  handleCors,
  jsonResponse,
  getUserFromRequest,
  getEffectiveSubscription,
} from '../_shared/lib.ts';

const MAX_LEN = 240;
const COOLDOWN_MS = 30_000;

// Tira caracteres de controle (mantendo a quebra de linha), normaliza quebras e
// espaços, e corta em MAX_LEN. Filtra por code point pra não ter nenhum char de
// controle no código-fonte. O texto ainda é escapado no client antes do DOM.
function limparTexto(raw: string): string {
  const semControle = Array.from(String(raw ?? ''))
    .filter((ch) => {
      const c = ch.codePointAt(0) ?? 0;
      if (c === 0x0a) return true; // mantém a quebra de linha
      return c >= 0x20 && c !== 0x7f; // fora: demais controles + DEL
    })
    .join('');
  let t = semControle
    .replace(/\n{3,}/g, '\n\n') // no máx. uma linha em branco
    .replace(/ {2,}/g, ' ') // espaços repetidos
    .trim();
  if (t.length > MAX_LEN) t = t.slice(0, MAX_LEN).trim();
  return t;
}

function primeiroNome(full: unknown): string {
  const s = String(full ?? '').trim();
  if (!s) return 'alguém do Casa';
  return s.split(/\s+/)[0].slice(0, 40);
}

Deno.serve(async (req) => {
  const pre = handleCors(req);
  if (pre) return pre;

  if (req.method !== 'POST') return jsonResponse({ error: 'método não permitido' }, 405);

  const user = await getUserFromRequest(req);
  if (!user) return jsonResponse({ error: 'não autenticado' }, 401);

  let body: { texto?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'JSON inválido' }, 400);
  }

  const texto = limparTexto(body.texto as string);
  if (!texto) return jsonResponse({ error: 'escreve teu recado 💛' }, 400);

  // Gating de assinante vigente (server-side). Sem plano → não posta.
  const sub = await getEffectiveSubscription(user.id);
  if (!sub) {
    return jsonResponse(
      {
        error: 'o mural é um cantinho de quem faz parte do Casa 💛 assina um plano pra deixar teu recado na parede.',
        precisa_assinar: true,
      },
      403,
    );
  }

  // Anti-flood leve: 30s entre recados do mesmo usuário.
  const { data: ultimo } = await supabaseAdmin
    .from('mural_notes')
    .select('created_at')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (ultimo?.created_at) {
    const desde = Date.now() - Date.parse(ultimo.created_at);
    if (Number.isFinite(desde) && desde >= 0 && desde < COOLDOWN_MS) {
      return jsonResponse({ error: 'calma, deixa a tinta secar 💛 espera um pouquinho pra deixar outro recado.' }, 429);
    }
  }

  // Nome do autor (snapshot). Best-effort — sem nome, cai no genérico gentil.
  const { data: perfil } = await supabaseAdmin
    .from('profiles')
    .select('full_name')
    .eq('id', user.id)
    .maybeSingle();
  const autor_nome = primeiroNome(perfil?.full_name);

  const { data: nota, error } = await supabaseAdmin
    .from('mural_notes')
    .insert({ user_id: user.id, autor_nome, texto, status: 'aprovado' })
    .select('id, autor_nome, texto, created_at')
    .single();
  if (error || !nota) {
    console.error('[postar-mural]', error);
    return jsonResponse({ error: 'não deu pra colar teu recado agora. tenta de novo daqui a pouco? 💛' }, 500);
  }

  return jsonResponse({ ok: true, note: nota });
});
