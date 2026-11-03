// =============================================================================
// scripts/spotify-token.mjs — pega o REFRESH TOKEN do Spotify (uma vez só)
//
// O painel "o som de agora" (home) lê a faixa atual da conta Spotify do Casa via
// a Edge Function spotify-now-playing. Pra ela renovar o acesso sozinha, precisa
// de um refresh token da conta. Este script faz o login OAuth UMA vez e imprime
// esse token — daí ele vira secret da function (nunca vai pro repo).
//
// PASSO A PASSO:
//   1. Cria um app grátis em https://developer.spotify.com/dashboard
//      • em "Redirect URIs" adiciona EXATAMENTE:  http://127.0.0.1:8888/callback
//      • copia o Client ID e o Client Secret.
//   2. No terminal (PowerShell), com o navegador logado na conta do Casa:
//        $env:SPOTIFY_CLIENT_ID="<client id>"
//        $env:SPOTIFY_CLIENT_SECRET="<client secret>"
//        node scripts/spotify-token.mjs
//   3. O script abre o Spotify pra autorizar. Aceita → volta pro 127.0.0.1 e ele
//      IMPRIME o refresh token. Copia esse valor.
//   4. Seta os três secrets na function (ver supabase/functions/README.md):
//        npx supabase secrets set SPOTIFY_CLIENT_ID=... SPOTIFY_CLIENT_SECRET=... SPOTIFY_REFRESH_TOKEN=...
//        npx supabase functions deploy spotify-now-playing --no-verify-jwt
//
// Segurança: as chaves entram por env (nunca hardcoded); o refresh token só é
// impresso no teu terminal. Nada disso vai pro git.
// =============================================================================

import http from 'node:http';
import crypto from 'node:crypto';
import { exec } from 'node:child_process';

const CLIENT_ID = process.env.SPOTIFY_CLIENT_ID;
const CLIENT_SECRET = process.env.SPOTIFY_CLIENT_SECRET;
const PORT = 8888;
const REDIRECT_URI = `http://127.0.0.1:${PORT}/callback`;
const SCOPE = 'user-read-currently-playing user-read-playback-state';

if (!CLIENT_ID || !CLIENT_SECRET) {
  console.error(
    '\n✗ Faltam as chaves. Antes de rodar, seta no terminal:\n' +
      '    $env:SPOTIFY_CLIENT_ID="<client id>"\n' +
      '    $env:SPOTIFY_CLIENT_SECRET="<client secret>"\n',
  );
  process.exit(1);
}

const state = crypto.randomBytes(16).toString('hex');
const authUrl =
  'https://accounts.spotify.com/authorize?' +
  new URLSearchParams({
    response_type: 'code',
    client_id: CLIENT_ID,
    scope: SCOPE,
    redirect_uri: REDIRECT_URI,
    state,
  }).toString();

async function trocarCodigoPorTokens(code) {
  const basic = Buffer.from(`${CLIENT_ID}:${CLIENT_SECRET}`).toString('base64');
  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: {
      Authorization: `Basic ${basic}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: REDIRECT_URI,
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`Spotify respondeu ${res.status}: ${JSON.stringify(data)}`);
  return data;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  if (url.pathname !== '/callback') {
    res.writeHead(404).end('nada aqui');
    return;
  }

  const erro = url.searchParams.get('error');
  const code = url.searchParams.get('code');
  const devolvido = url.searchParams.get('state');

  const fecharPagina = (titulo, texto) =>
    `<!doctype html><meta charset="utf-8"><body style="font-family:system-ui;background:#f3eee3;color:#1b1611;display:grid;place-items:center;height:100vh;margin:0;text-align:center"><div><h1 style="color:#df5638">${titulo}</h1><p>${texto}</p></div></body>`;

  if (erro) {
    res.writeHead(400, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(fecharPagina('deu ruim', `o Spotify recusou: ${erro}`));
    console.error(`\n✗ Autorização recusada: ${erro}\n`);
    server.close();
    process.exit(1);
  }
  if (devolvido !== state) {
    res.writeHead(400, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(fecharPagina('deu ruim', 'state não confere (tenta de novo)'));
    console.error('\n✗ state não confere — abortando por segurança.\n');
    server.close();
    process.exit(1);
  }

  try {
    const tokens = await trocarCodigoPorTokens(code);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(fecharPagina('pronto 💛', 'pode fechar esta aba e voltar pro terminal.'));
    console.log('\n✓ Refresh token do Spotify (guarda como secret, NÃO commita):\n');
    console.log('    SPOTIFY_REFRESH_TOKEN=' + tokens.refresh_token + '\n');
    console.log('Próximo passo:');
    console.log(
      '    npx supabase secrets set \\\n' +
        `      SPOTIFY_CLIENT_ID=${CLIENT_ID} \\\n` +
        '      SPOTIFY_CLIENT_SECRET=<client secret> \\\n' +
        `      SPOTIFY_REFRESH_TOKEN=${tokens.refresh_token}\n` +
        '    npx supabase functions deploy spotify-now-playing --no-verify-jwt\n',
    );
  } catch (e) {
    res.writeHead(500, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(fecharPagina('deu ruim', 'não deu pra trocar o código pelo token, olha o terminal.'));
    console.error('\n✗ Falha ao trocar o código:', e.message, '\n');
  } finally {
    server.close();
    setTimeout(() => process.exit(0), 200);
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log('\nAbrindo o Spotify pra autorizar a conta do Casa...');
  console.log('Se o navegador não abrir sozinho, cola este link:\n');
  console.log('  ' + authUrl + '\n');
  // Tenta abrir no navegador padrão (Windows/macOS/Linux). Se falhar, o link acima resolve.
  const cmd =
    process.platform === 'win32'
      ? `start "" "${authUrl}"`
      : process.platform === 'darwin'
        ? `open "${authUrl}"`
        : `xdg-open "${authUrl}"`;
  exec(cmd, () => {});
});
