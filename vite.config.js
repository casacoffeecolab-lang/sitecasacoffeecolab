import { defineConfig } from 'vite';
import { existsSync } from 'node:fs';
import { extname, resolve } from 'node:path';

// Raiz do Vite = src/. As páginas moram AQUI (não mais numa subpasta pages/),
// porque o caminho do arquivo é a URL: src/o-casa.html vira /o-casa. Ver CLAUDE.md.
const root = resolve(__dirname, 'src');

// Em produção quem tira o ".html" da URL é a Vercel (cleanUrls no vercel.json).
// O dev server do Vite não faz isso sozinho, então este middleware anexa o .html
// quando o arquivo existe — assim /o-casa funciona igual em dev e em prod, e os
// links do site podem ser escritos limpos num lugar só.
// Só navegação de página deve cair na 404 — pedidos internos do dev server
// (módulos, HMR, imagens) pedem outra coisa no Accept e seguem o caminho normal.
function aceitaHtml(req) {
  return (req.headers.accept || '').includes('text/html');
}

function urlsLimpasNoDev() {
  return {
    name: 'casa-urls-limpas',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const [caminho, query] = (req.url || '/').split('?');
        // Rota dinâmica: /gente/{handle} → gente.html (o JS lê o handle do path).
        // Espelha o rewrite do vercel.json pra o dev funcionar igual à prod.
        if (/^\/gente\/[^/]+\/?$/.test(caminho)) {
          req.url = '/gente.html' + (query ? '?' + query : '');
          return next();
        }
        if (caminho !== '/' && !extname(caminho)) {
          const arquivo = resolve(root, '.' + caminho + '.html');
          // Pasta com index.html dentro (é o caso do console: src/admin/index.html).
          // Sem isto, /admin não achava /admin.html e caía no 404, enquanto
          // /admin/ funcionava — dois endereços pra mesma porta, um deles morto.
          // Na Vercel o cleanUrls já resolve os dois; aqui o dev passa a fazer igual.
          const semBarra = caminho.replace(/\/$/, '');
          const indice = resolve(root, '.' + semBarra + '/index.html');
          if (existsSync(arquivo)) {
            req.url = caminho + '.html' + (query ? '?' + query : '');
          } else if (existsSync(indice)) {
            req.url = semBarra + '/index.html' + (query ? '?' + query : '');
          } else if (aceitaHtml(req) && !caminho.startsWith('/@')) {
            // Endereço que não existe. Sem isto o fallback de SPA do Vite serviria
            // o index.html, que redireciona pra /home — o link quebrado sumiria em
            // silêncio. Em produção quem faz este papel é a Vercel, que serve o
            // 404.html da raiz do dist automaticamente (com status 404).
            // O `send` do Vite escreve 200 na resposta antes de mandar o HTML, então
            // travar o statusCode é o que faz o dev devolver 404 de verdade (igual à
            // Vercel), e não uma página de erro com cara de página que existe.
            Object.defineProperty(res, 'statusCode', { get: () => 404, set: () => {}, configurable: true });
            req.url = '/404.html';
          }
        }
        next();
      });
    },
  };
}

// Multi-página: cada .html em src/ (e em src/conta/) é uma URL. Página nova
// entra aqui em `input`.
export default defineConfig({
  root,
  plugins: [urlsLimpasNoDev()],
  // .env fica na RAIZ do projeto, mas o root do Vite é src/ — sem isto o Vite
  // procuraria .env dentro de src/ e as VITE_* nunca seriam carregadas.
  envDir: __dirname,
  publicDir: resolve(__dirname, 'src/assets'),
  server: {
    // host: true expõe na rede local (0.0.0.0) sem precisar de "-- --host".
    // Aí dá pra abrir no celular/outro PC via http://<IP-da-maquina>:5173/
    host: true,
    open: '/home',
  },
  build: {
    outDir: resolve(__dirname, 'dist'),
    emptyOutDir: true,
    rollupOptions: {
      input: {
        index: resolve(root, 'index.html'),
        // A Vercel serve este arquivo em qualquer URL que não existe (status 404).
        naoEncontrado: resolve(root, '404.html'),
        home: resolve(root, 'home.html'),
        oCasa: resolve(root, 'o-casa.html'),
        cardapio: resolve(root, 'cardapio.html'),
        loja: resolve(root, 'loja.html'),
        produto: resolve(root, 'produto.html'),
        planos: resolve(root, 'planos.html'),
        presentear: resolve(root, 'presentear.html'),
        gente: resolve(root, 'gente.html'),
        colab: resolve(root, 'colab.html'),
        eventos: resolve(root, 'eventos.html'),
        privacidade: resolve(root, 'privacidade.html'),
        termos: resolve(root, 'termos.html'),
        cadastro: resolve(root, 'cadastro.html'),
        login: resolve(root, 'login.html'),
        authConfirmado: resolve(root, 'auth-confirmado.html'),
        checkoutSucesso: resolve(root, 'checkout-sucesso.html'),
        checkoutCancelado: resolve(root, 'checkout-cancelado.html'),
        perfil: resolve(root, 'conta/perfil.html'),
        clube: resolve(root, 'conta/clube.html'),
        pontos: resolve(root, 'conta/pontos.html'),
        conquistas: resolve(root, 'conta/conquistas.html'),
        pedidos: resolve(root, 'conta/pedidos.html'),
        // console da equipe: uma página com abas + a porta de entrada
        adminEntrar: resolve(root, 'admin/entrar.html'),
        admin: resolve(root, 'admin/index.html'),
      },
    },
  },
});
