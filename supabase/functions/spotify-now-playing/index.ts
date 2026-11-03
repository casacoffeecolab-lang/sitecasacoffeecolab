// =============================================================================
// Casa Coffee Colab — spotify-now-playing (Edge Function, Deno)
// Diz o que está tocando AGORA na conta Spotify do Casa, pro painel "o som de
// agora" da home. Leitura PÚBLICA (qualquer visitante, logado ou não) — não
// devolve nada sensível, só a faixa atual.
//
// SEGURANÇA (ver CLAUDE.md › Segurança):
//   • Os segredos vivem SÓ aqui (supabase secrets), NUNCA no client/bundle/repo:
//       SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET, SPOTIFY_REFRESH_TOKEN.
//   • Deploy com --no-verify-jwt (público): o gateway ainda exige a anon key, mas
//     não precisa de sessão. Nenhum dado de usuário entra ou sai.
//   • NÃO importa o _shared/lib.ts de propósito: aquele módulo exige ASAAS_API_KEY
//     no topo, e esta function não fala com o Asaas. Fica auto-contida.
//
// Como funciona: troca o refresh token por um access token (dura 1h, cacheado na
// instância quente) e chama GET /me/player/currently-playing. Um cache curto do
// resultado (10s) protege de rate limit quando muita gente abre a home junto.
//
// Retorna (sempre 200):
//   tocando=true  → { tocando, nome, artista, album, capa, url, progresso_ms, duracao_ms }
//   nada rolando  → { tocando: false }   (o front cai no estado gentil)
//   sem secrets   → { tocando: false, configurado: false }
// =============================================================================

const cors: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

const CLIENT_ID = Deno.env.get('SPOTIFY_CLIENT_ID') ?? '';
const CLIENT_SECRET = Deno.env.get('SPOTIFY_CLIENT_SECRET') ?? '';
const REFRESH_TOKEN = Deno.env.get('SPOTIFY_REFRESH_TOKEN') ?? '';

// Cache do access token dentro da instância quente (o token dura ~1h). Renova
// 60s antes de expirar pra nunca chamar a API com token vencido.
let tokenCache: { value: string; exp: number } = { value: '', exp: 0 };

async function getAccessToken(): Promise<string> {
  const agora = Date.now();
  if (tokenCache.value && agora < tokenCache.exp) return tokenCache.value;

  const basic = btoa(`${CLIENT_ID}:${CLIENT_SECRET}`);
  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${basic}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: REFRESH_TOKEN }),
  });
  if (!res.ok) throw new Error(`spotify token ${res.status}`);
  const data = await res.json();
  tokenCache = {
    value: data.access_token,
    exp: agora + Math.max(0, (Number(data.expires_in) || 3600) - 60) * 1000,
  };
  return tokenCache.value;
}

// Cache curto do "tocando agora": rajadas de visitantes compartilham uma leitura.
let npCache: { body: unknown; at: number } = { body: null, at: 0 };
const NP_TTL_MS = 10_000;

async function nowPlaying(): Promise<unknown> {
  const agora = Date.now();
  if (npCache.body && agora - npCache.at < NP_TTL_MS) return npCache.body;

  const token = await getAccessToken();
  const res = await fetch('https://api.spotify.com/v1/me/player/currently-playing', {
    headers: { 'Authorization': `Bearer ${token}` },
  });

  let out: Record<string, unknown> = { tocando: false };
  // 204 (nada rolando) / 202 (device acordando) / erro → estado gentil.
  if (res.ok && res.status !== 204 && res.status !== 202) {
    const d = await res.json();
    const item = d?.item;
    // Só faixa de música tocando de fato (ignora pausado, anúncio, podcast).
    if (item && d.currently_playing_type === 'track' && d.is_playing) {
      out = {
        tocando: true,
        nome: String(item.name ?? ''),
        artista: (item.artists ?? []).map((a: { name: string }) => a.name).join(', '),
        album: String(item.album?.name ?? ''),
        capa: String(item.album?.images?.[0]?.url ?? ''),
        url: String(item.external_urls?.spotify ?? ''),
        progresso_ms: Number(d.progress_ms) || 0,
        duracao_ms: Number(item.duration_ms) || 0,
      };
    }
  }

  npCache = { body: out, at: agora };
  return out;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  // Sem os secrets ainda? Responde "nada tocando" pra o front seguir gentil.
  if (!CLIENT_ID || !CLIENT_SECRET || !REFRESH_TOKEN) {
    return json({ tocando: false, configurado: false });
  }
  try {
    return json(await nowPlaying());
  } catch (_e) {
    return json({ tocando: false });
  }
});
