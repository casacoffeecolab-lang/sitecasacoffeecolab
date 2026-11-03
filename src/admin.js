// =============================================================================
// Casa Coffee Colab, admin.js
// Console da equipe (/admin). Camada própria, separada do app.js de propósito:
// o app.js auto-inicializa header, carrossel, carrinho e drawer da loja no
// bootstrap — nada disso faz sentido no balcão de trás.
//
// Tudo que aparece aqui vem das funções `admin_*` do banco (migration 0017),
// SECURITY DEFINER, com a permissão conferida dentro do SQL. O client só
// desenha o que a RPC devolveu: esconder um botão aqui é gentileza de UI, a
// tranca de verdade está no banco.
// =============================================================================

import './styles.css';
import {
  createIcons,
  LayoutDashboard,
  ShoppingBag,
  Gift,
  Users,
  BarChart3,
  ShieldCheck,
  KeyRound,
  LogOut,
  Coffee,
  Truck,
  Store,
  Check,
  X,
  Search,
  RefreshCw,
  Eye,
  EyeOff,
  Lock,
  ArrowLeft,
  Megaphone,
  Music,
  Cake,
  CalendarDays,
  Heart,
  Bookmark,
  BellRing,
  Mail,
  PartyPopper,
  Archive,
  RotateCcw,
  StickyNote,
  Undo2,
  Trash2,
  ClipboardList,
  UserRound,
  CalendarClock,
  Pencil,
  Plus,
  Table2,
  Columns3,
  ChevronDown,
  ChevronRight,
  ChevronUp,
  AlignLeft,
  MessageSquare,
  CircleDot,
  UserPlus,
  BadgeCheck,
  Coins,
  Wrench,
  SlidersHorizontal,
  Footprints,
  Snowflake,
  DoorOpen,
  MousePointerClick,
  Image,
  ImagePlus,
} from 'lucide';
import { createClient } from '@supabase/supabase-js';
// A lista dos lugares do site que mostram foto. Mesma lista que o app.js usa
// pra trocar de verdade — ver o cabeçalho do fotos-do-site.js.
import { FOTOS_BUCKET, FOTOS_DO_SITE, fotosPorPagina } from './fotos-do-site.js';

const LUCIDE_ICONS = {
  LayoutDashboard,
  ShoppingBag,
  Gift,
  Users,
  BarChart3,
  ShieldCheck,
  KeyRound,
  LogOut,
  Coffee,
  Truck,
  Store,
  Check,
  X,
  Search,
  RefreshCw,
  Eye,
  EyeOff,
  Lock,
  ArrowLeft,
  Megaphone,
  Music,
  Cake,
  CalendarDays,
  Heart,
  Bookmark,
  BellRing,
  Mail,
  PartyPopper,
  Archive,
  RotateCcw,
  StickyNote,
  Undo2,
  Trash2,
  ClipboardList,
  UserRound,
  CalendarClock,
  Pencil,
  Plus,
  Table2,
  Columns3,
  ChevronDown,
  ChevronRight,
  ChevronUp,
  AlignLeft,
  MessageSquare,
  CircleDot,
  UserPlus,
  BadgeCheck,
  Coins,
  Wrench,
  SlidersHorizontal,
  Footprints,
  Snowflake,
  DoorOpen,
  MousePointerClick,
  Image,
  ImagePlus,
};

function renderIcons() {
  createIcons({ icons: LUCIDE_ICONS });
}

// ===== SUPABASE =====================================================
// Só a anon key, como no resto do site. Quem protege os dados é a RLS + as
// funções do 0017.
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;
const supabaseConfigurado =
  Boolean(SUPABASE_URL && SUPABASE_ANON_KEY) && !/placeholder/i.test(SUPABASE_URL);
const supabase = supabaseConfigurado ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY) : null;

// O Supabase Auth só entende e-mail. O adm master entra digitando "casa", então
// a gente traduz login → e-mail interno aqui. Quem já digita um e-mail passa reto.
const DOMINIO_INTERNO = 'casacoffeecolab.com.br';
function loginParaEmail(valor) {
  const v = String(valor || '').trim().toLowerCase();
  return v.includes('@') ? v : `${v}@${DOMINIO_INTERNO}`;
}

// ===== HELPERS ======================================================
const $ = (sel, raiz = document) => raiz.querySelector(sel);
const $$ = (sel, raiz = document) => Array.from(raiz.querySelectorAll(sel));

function escapeHtml(valor) {
  return String(valor ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatBRL(centavos) {
  const n = Number(centavos || 0) / 100;
  return n.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}

function formatNumero(n) {
  return Number(n || 0).toLocaleString('pt-BR');
}

function formatData(iso, comHora = true) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  const data = d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' });
  if (!comHora) return data;
  const hora = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  return `${data} às ${hora}`;
}

// Pedido é UUID; ninguém no balcão vai ler os 36 caracteres. Os 6 primeiros
// bastam pra conferir com o cliente.
function refCurta(id) {
  return String(id || '').slice(0, 6).toUpperCase();
}

let toastTimer;
function toast(mensagem, tom = 'ok') {
  const el = $('[data-toast]');
  if (!el) return;
  el.textContent = mensagem;
  el.dataset.tom = tom;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    el.hidden = true;
  }, 3600);
}

// Toda chamada ao banco passa por aqui: erro vira Error com a mensagem em pt-BR
// que a própria função SQL levantou (as do 0017 falam a língua da casa).
async function rpc(nome, params) {
  if (!supabase) throw new Error('o banco ainda não está configurado por aqui');
  const { data, error } = await supabase.rpc(nome, params);
  if (error) throw new Error(error.message || 'não deu pra falar com o banco agora');
  return data;
}

// Modal de confirmação, pra ações que não dá pra desfazer (dar baixa, tirar
// alguém do console). Promise<boolean>.
function confirmar({ titulo, texto, ok = 'confirmar', tom = '' }) {
  return new Promise((resolve) => {
    const fundo = document.createElement('div');
    fundo.className = 'ad-modal';
    fundo.innerHTML = `
      <div class="ad-modal-caixa" role="dialog" aria-modal="true" aria-label="${escapeHtml(titulo)}">
        <h3 class="title sm">${escapeHtml(titulo)}</h3>
        <p class="ad-modal-texto">${escapeHtml(texto)}</p>
        <div class="ad-modal-acoes">
          <button type="button" class="btn ghost sm" data-nao>deixa pra lá</button>
          <button type="button" class="btn ${tom === 'perigo' ? 'ink' : 'solid'} sm" data-sim>${escapeHtml(ok)}</button>
        </div>
      </div>`;
    const fechar = (resposta) => {
      document.removeEventListener('keydown', aoTeclar);
      fundo.remove();
      resolve(resposta);
    };
    const aoTeclar = (e) => {
      if (e.key === 'Escape') fechar(false);
    };
    fundo.addEventListener('click', (e) => {
      if (e.target === fundo) fechar(false);
    });
    $('[data-nao]', fundo).addEventListener('click', () => fechar(false));
    $('[data-sim]', fundo).addEventListener('click', () => fechar(true));
    document.addEventListener('keydown', aoTeclar);
    document.body.appendChild(fundo);
    $('[data-sim]', fundo).focus();
  });
}

// Botãozinho de olho nos campos de senha (mesmo comportamento do login do site).
function ligarOlhosDeSenha(escopo) {
  $$('[data-olho]', escopo).forEach((botao) => {
    botao.addEventListener('click', () => {
      const campo = $(`#${botao.dataset.olho}`, escopo);
      if (!campo) return;
      const mostrando = campo.type === 'text';
      campo.type = mostrando ? 'password' : 'text';
      botao.setAttribute('aria-label', mostrando ? 'mostrar a senha' : 'esconder a senha');
      botao.innerHTML = `<i data-lucide="${mostrando ? 'eye' : 'eye-off'}"></i>`;
      renderIcons();
    });
  });
}

// Um "carregando" honesto no lugar do conteúdo, pra tela nunca ficar em branco.
function carregando(alvo, texto = 'buscando…') {
  alvo.innerHTML = `<div class="ad-carregando">${escapeHtml(texto)}</div>`;
}

function vazio(titulo, texto) {
  return `<div class="empty"><p class="e-title">${escapeHtml(titulo)}</p><p>${escapeHtml(texto)}</p></div>`;
}

function erroNaTela(alvo, e) {
  alvo.innerHTML = `<div class="notice err"><p>${escapeHtml(e.message || 'algo não saiu como esperado')}</p></div>`;
}

// ===== ESTADO =======================================================
const estado = {
  sessao: null,
  perms: null, // { console, nome, papel, master, senha_trocada, permissoes[], tudo }
  aba: null,
};

// `estado.perms.permissoes` vem do banco JÁ EXPANDIDO (a 0047 resolve a
// hierarquia lá dentro: quem tem `mural.arrumar` recebe `mural.mexer` e
// `mural.ver` na mesma lista). Aqui só se pergunta pelo slug exato — a régua
// mora no banco, e o front não repete regra de permissão.
function pode(slug) {
  if (!estado.perms) return false;
  if (estado.perms.tudo) return true;
  return Array.isArray(estado.perms.permissoes) && estado.perms.permissoes.includes(slug);
}

// ===== NAVEGAÇÃO ====================================================
// Cada aba pede o `ver` da PÁGINA dela. O que se FAZ dentro da aba (dar baixa,
// publicar, apagar) pede `<pagina>.mexer` ou `<pagina>.arrumar`, e isso é
// perguntado no botão, não aqui: dá pra enxergar uma tela inteira sem poder
// mexer em nada dela.
const NAV = [
  { id: 'painel', rotulo: 'painel', icone: 'layout-dashboard', perm: 'painel.ver' },
  // O quadro de pautas (0043/0045) vem logo depois do painel porque é por onde o
  // dia começa pra quem trabalha no salão: o que a casa combinou pra hoje.
  { id: 'pautas', rotulo: 'pautas', icone: 'clipboard-list', perm: 'pautas.ver' },
  // Os rastros (0053): por onde a visita andou e onde ela largou o site. Fica
  // na fila do "dia a dia" porque é número do site inteiro, e é o tipo de coisa
  // que se olha no começo da semana, não no meio do turno.
  { id: 'rastros', rotulo: 'rastros', icone: 'footprints', perm: 'rastros.ver' },
  { id: 'pedidos', rotulo: 'pedidos', icone: 'shopping-bag', perm: 'pedidos.ver' },
  { id: 'resgates', rotulo: 'resgates', icone: 'gift', perm: 'resgates.ver' },
  { id: 'aniversarios', rotulo: 'brunches', icone: 'cake', perm: 'aniversarios.ver' },
  // Presentes vendidos (0041). O código é título ao portador, quem tem o texto
  // resgata um mês de plano, então a página tem permissão própria.
  { id: 'presentes', rotulo: 'presentes', icone: 'gift', perm: 'presentes.ver' },
  // As duas telas que a 0047 abriu, e que eram os dois buracos do console: a
  // casa não conseguia OLHAR uma assinatura nem o extrato de pontos de ninguém,
  // que é justamente o que a pessoa liga pra perguntar.
  { id: 'assinaturas', rotulo: 'assinaturas', icone: 'badge-check', perm: 'assinaturas.ver' },
  { id: 'pontos', rotulo: 'pontos', icone: 'coins', perm: 'pontos.ver' },
  { id: 'pessoas', rotulo: 'pessoas', icone: 'users', perm: 'pessoas.ver' },
  { id: 'mural', rotulo: 'mural', icone: 'sticky-note', perm: 'mural.ver' },
  { id: 'relatorios', rotulo: 'relatórios', icone: 'bar-chart-3', perm: 'relatorios.ver' },
  { id: 'favoritos', rotulo: 'favoritos', icone: 'heart', perm: 'favoritos.ver' },
  { id: 'desejos', rotulo: 'desejos', icone: 'bookmark', perm: 'desejos.ver' },
  { id: 'esperando', rotulo: 'esperando', icone: 'bell-ring', perm: 'reposicao.ver' },
  { id: 'espera', rotulo: 'lista de espera', icone: 'mail', perm: 'espera.ver' },
  // "quem quer fazer evento aqui" — os pedidos da página /eventos (0040). Note
  // que é OUTRA coisa que a aba 'agenda', que é dos encontros que a casa
  // promove; esta é de quem quer usar a casa pro evento dele.
  { id: 'leads', rotulo: 'eventos', icone: 'party-popper', perm: 'leads.ver' },
  { id: 'equipe', rotulo: 'equipe', icone: 'shield-check', perm: 'equipe.ver' },
  { id: 'recados', rotulo: 'recados', icone: 'megaphone', perm: 'recados.ver' },
  { id: 'trilha', rotulo: 'trilha', icone: 'music', perm: 'trilha.ver' },
  { id: 'agenda', rotulo: 'agenda', icone: 'calendar-days', perm: 'agenda.ver' },
  // As fotos do site (0054): fica junto com o resto do que a casa PUBLICA
  // (mural, recado, trilha, agenda), que é a seção 'a casa' do catálogo.
  { id: 'fotos', rotulo: 'fotos', icone: 'image', perm: 'fotos.ver' },
  { id: 'conta', rotulo: 'tua conta', icone: 'key-round', perm: null },
];

// O catálogo de permissões (seção › página › ação) NÃO mora aqui: mora no banco,
// nas tabelas da 0047, e chega pela `admin_permissoes_catalogo`. Foi uma escolha:
// enquanto a lista era escrita nos dois lugares, ela divergia, e a que a tela
// mostrava não era a que o banco cobrava. Aqui fica só o cache da resposta.
let catalogoPermissoes = null;

async function carregarCatalogo() {
  if (catalogoPermissoes) return catalogoPermissoes;
  const dados = await rpc('admin_permissoes_catalogo');
  catalogoPermissoes = Array.isArray(dados) ? dados : [];
  return catalogoPermissoes;
}

// Todas as ações do catálogo, achatadas, pra contar e procurar.
function todasAsAcoes(secoes) {
  return (secoes || []).flatMap((s) => (s.paginas || []).flatMap((p) => p.acoes || []));
}

// Quando a pessoa só ENXERGA a página, o que ela não pode fazer nem aparece, e
// no lugar fica um recado dizendo por quê. Tela sem explicação vira "tá
// quebrado"; o banco barra de qualquer jeito, isto é pra não oferecer.
function soLeitura(texto) {
  return `<div class="notice info"><p>${escapeHtml(texto)}</p></div>`;
}

const ROTULO_PAPEL = {
  owner: 'adm do Casa',
  gerente: 'gerência',
  staff: 'equipe',
  cliente: 'cliente',
};

// ===== TELA DE ENTRADA (/admin/entrar) ==============================
async function initEntrar() {
  const alvo = $('[data-entrar-form]');
  if (!alvo) return;

  if (!supabase) {
    alvo.innerHTML = `<div class="notice warn"><p>o banco ainda não está configurado neste ambiente. preenche o .env e volta aqui.</p></div>`;
    return;
  }

  // Quem já tem sessão de equipe não precisa digitar de novo.
  const { data } = await supabase.auth.getSession();
  if (data?.session) {
    try {
      const perms = await rpc('admin_minhas_permissoes');
      if (perms?.console) {
        window.location.replace('/admin/');
        return;
      }
    } catch {
      /* segue pro formulário */
    }
  }

  alvo.innerHTML = `
    <form class="ad-entrar-form" novalidate>
      <div class="field">
        <label for="quem">teu login ou e-mail</label>
        <input id="quem" name="quem" type="text" autocomplete="username" autocapitalize="off" spellcheck="false" placeholder="casa" required />
      </div>
      <div class="field">
        <label for="senha">tua senha</label>
        <div class="ad-senha">
          <input id="senha" name="senha" type="password" autocomplete="current-password" required />
          <button type="button" class="ad-olho" data-olho="senha" aria-label="mostrar a senha"><i data-lucide="eye"></i></button>
        </div>
      </div>
      <div data-aviso></div>
      <button type="submit" class="btn solid block">entrar</button>
    </form>`;

  ligarOlhosDeSenha(alvo);
  renderIcons();

  const form = $('form', alvo);
  const aviso = $('[data-aviso]', alvo);
  const botao = $('button[type="submit"]', alvo);

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const quem = $('#quem', form).value.trim();
    const senha = $('#senha', form).value;
    aviso.innerHTML = '';
    if (!quem || !senha) {
      aviso.innerHTML = `<div class="notice warn"><p>falta preencher os dois campos.</p></div>`;
      return;
    }
    botao.disabled = true;
    botao.textContent = 'abrindo…';
    const { error } = await supabase.auth.signInWithPassword({
      email: loginParaEmail(quem),
      password: senha,
    });
    if (error) {
      botao.disabled = false;
      botao.textContent = 'entrar';
      aviso.innerHTML = `<div class="notice err"><p>login ou senha não conferem. tenta de novo?</p></div>`;
      return;
    }
    // Sessão criada: quem decide se essa pessoa entra no console é o banco.
    try {
      const perms = await rpc('admin_minhas_permissoes');
      if (!perms?.console) {
        await supabase.auth.signOut();
        botao.disabled = false;
        botao.textContent = 'entrar';
        aviso.innerHTML = `<div class="notice warn"><p>essa conta não tem acesso ao console. se tu é cliente, entra por <a class="form-link" href="/login">aqui</a>.</p></div>`;
        return;
      }
    } catch (err) {
      botao.disabled = false;
      botao.textContent = 'entrar';
      aviso.innerHTML = `<div class="notice err"><p>${escapeHtml(err.message)}</p></div>`;
      return;
    }
    window.location.replace('/admin/');
  });
}

// ===== CONSOLE (/admin/) ============================================
async function initConsole() {
  const raiz = $('[data-console-root]');
  if (!raiz) return;

  if (!supabase) {
    raiz.innerHTML = `<div class="ad-aviso-cheio"><div class="notice warn"><p>o banco ainda não está configurado neste ambiente.</p></div></div>`;
    return;
  }

  const { data } = await supabase.auth.getSession();
  if (!data?.session) {
    window.location.replace('/admin/entrar');
    return;
  }
  estado.sessao = data.session;

  try {
    estado.perms = await rpc('admin_minhas_permissoes');
  } catch (e) {
    raiz.innerHTML = `<div class="ad-aviso-cheio"><div class="notice err"><p>${escapeHtml(e.message)}</p></div></div>`;
    return;
  }

  if (!estado.perms?.console) {
    raiz.innerHTML = `
      <div class="ad-aviso-cheio">
        <div class="ad-entrar-card">
          <p class="eyebrow coral">console do Casa</p>
          <h1 class="title md">esse balcão não é teu</h1>
          <p class="ad-entrar-sub">essa conta não tem acesso ao console. se tu é cliente, teu lugar é na <a class="form-link" href="/conta/perfil">tua conta</a>.</p>
          <div class="ad-modal-acoes" style="justify-content:flex-start">
            <button type="button" class="btn ghost sm" data-sair>sair</button>
            <a class="btn solid sm" href="/home">voltar pro site</a>
          </div>
        </div>
      </div>`;
    $('[data-sair]', raiz).addEventListener('click', sair);
    return;
  }

  // Primeiro acesso do adm master: a senha inicial é combinada, então não vale
  // deixar entrar em nada antes de trocar. SÓ vale pro master: `senha_alterada_em`
  // nasce null pra todo mundo (o handle_new_user não preenche), então sem o gate de
  // `master` qualquer funcionário adicionado a partir de conta de cliente já
  // existente cairia aqui e seria forçado a rotacionar a própria senha real.
  if (estado.perms.master && estado.perms.senha_trocada === false) {
    telaTrocaObrigatoria(raiz);
    return;
  }

  montarShell(raiz);
}

async function sair() {
  try {
    await supabase.auth.signOut();
  } finally {
    window.location.replace('/admin/entrar');
  }
}

// ===== TROCA DE SENHA ===============================================
// Um formulário só, usado no primeiro acesso (obrigatório) e na aba "tua conta".
function formSenhaHTML() {
  return `
    <form class="ad-form-senha" novalidate>
      <div class="field">
        <label for="senha-atual">a senha de agora</label>
        <div class="ad-senha">
          <input id="senha-atual" type="password" autocomplete="current-password" required />
          <button type="button" class="ad-olho" data-olho="senha-atual" aria-label="mostrar a senha"><i data-lucide="eye"></i></button>
        </div>
      </div>
      <div class="field">
        <label for="senha-nova">a senha nova</label>
        <div class="ad-senha">
          <input id="senha-nova" type="password" autocomplete="new-password" minlength="8" required />
          <button type="button" class="ad-olho" data-olho="senha-nova" aria-label="mostrar a senha"><i data-lucide="eye"></i></button>
        </div>
        <p class="ad-dica">pelo menos 8 caracteres.</p>
      </div>
      <div class="field">
        <label for="senha-nova-2">de novo, pra conferir</label>
        <div class="ad-senha">
          <input id="senha-nova-2" type="password" autocomplete="new-password" minlength="8" required />
          <button type="button" class="ad-olho" data-olho="senha-nova-2" aria-label="mostrar a senha"><i data-lucide="eye"></i></button>
        </div>
      </div>
      <div data-aviso-senha></div>
      <button type="submit" class="btn solid">guardar a senha nova</button>
    </form>`;
}

function ligarFormSenha(escopo, aoTrocar) {
  ligarOlhosDeSenha(escopo);
  renderIcons();
  const form = $('form', escopo);
  const aviso = $('[data-aviso-senha]', escopo);
  const botao = $('button[type="submit"]', escopo);

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const atual = $('#senha-atual', form).value;
    const nova = $('#senha-nova', form).value;
    const nova2 = $('#senha-nova-2', form).value;
    aviso.innerHTML = '';

    if (nova.length < 8) {
      aviso.innerHTML = `<div class="notice warn"><p>a senha nova precisa de pelo menos 8 caracteres.</p></div>`;
      return;
    }
    if (nova !== nova2) {
      aviso.innerHTML = `<div class="notice warn"><p>as duas senhas novas não bateram.</p></div>`;
      return;
    }
    if (nova === atual) {
      aviso.innerHTML = `<div class="notice warn"><p>essa é a mesma senha de agora. escolhe outra?</p></div>`;
      return;
    }

    botao.disabled = true;
    botao.textContent = 'guardando…';

    // Confere a senha antiga entrando de novo com ela — é o jeito honesto de
    // provar que quem está no teclado sabe a senha atual.
    const email = estado.sessao?.user?.email;
    const { error: erroLogin } = await supabase.auth.signInWithPassword({
      email,
      password: atual,
    });
    if (erroLogin) {
      botao.disabled = false;
      botao.textContent = 'guardar a senha nova';
      aviso.innerHTML = `<div class="notice err"><p>a senha de agora não confere.</p></div>`;
      return;
    }

    const { error: erroUpdate } = await supabase.auth.updateUser({ password: nova });
    if (erroUpdate) {
      botao.disabled = false;
      botao.textContent = 'guardar a senha nova';
      aviso.innerHTML = `<div class="notice err"><p>${escapeHtml(erroUpdate.message)}</p></div>`;
      return;
    }

    try {
      await rpc('admin_senha_alterada');
    } catch {
      // A senha já trocou; se o carimbo falhar, o console só vai pedir de novo.
    }

    const { data } = await supabase.auth.getSession();
    estado.sessao = data?.session || estado.sessao;
    if (typeof aoTrocar === 'function') aoTrocar();
  });
}

function telaTrocaObrigatoria(raiz) {
  raiz.innerHTML = `
    <div class="ad-aviso-cheio">
      <div class="ad-entrar-card">
        <p class="eyebrow coral">primeiro acesso</p>
        <h1 class="title md">escolhe uma senha tua</h1>
        <p class="ad-entrar-sub">a senha que tu usou pra entrar é a combinada de fábrica. antes de abrir o console, guarda uma que só tu sabe.</p>
        <div data-troca></div>
      </div>
    </div>`;
  const caixa = $('[data-troca]', raiz);
  caixa.innerHTML = formSenhaHTML();
  ligarFormSenha(caixa, async () => {
    estado.perms = await rpc('admin_minhas_permissoes');
    toast('senha trocada, bem-vindo ao balcão');
    montarShell(raiz);
  });
}

// ===== CASCA DO CONSOLE =============================================
function montarShell(raiz) {
  const abas = NAV.filter((item) => item.perm === null || pode(item.perm));
  const nome = estado.perms.nome || 'equipe';
  const papel = ROTULO_PAPEL[estado.perms.papel] || estado.perms.papel || '';

  raiz.innerHTML = `
    <div class="ad-shell">
      <aside class="ad-lado">
        <a class="ad-marca" href="/home">
          <i data-lucide="coffee"></i>
          <span>Casa <em>console</em></span>
        </a>
        <nav class="ad-nav" aria-label="seções do console">
          ${abas
            .map(
              (item) => `
            <button type="button" class="ad-nav-item" data-aba="${item.id}">
              <i data-lucide="${item.icone}"></i><span>${escapeHtml(item.rotulo)}</span>
            </button>`,
            )
            .join('')}
        </nav>
        <div class="ad-quem">
          <p class="ad-quem-nome">${escapeHtml(nome)}</p>
          <p class="ad-quem-papel">${escapeHtml(papel)}${estado.perms.master ? ' · conta do Casa' : ''}</p>
          <button type="button" class="ad-sair" data-sair><i data-lucide="log-out"></i><span>sair</span></button>
        </div>
      </aside>
      <main class="ad-conteudo" data-view></main>
    </div>`;

  $('[data-sair]', raiz).addEventListener('click', sair);
  $$('[data-aba]', raiz).forEach((botao) => {
    botao.addEventListener('click', () => {
      window.location.hash = botao.dataset.aba;
    });
  });
  renderIcons();

  window.addEventListener('hashchange', abrirDoHash);
  abrirDoHash();
}

// Trocar de aba NÃO recarrega a página (é hash), e cada view remonta o HTML do
// zero — mas o estado de edição e o texto de busca vivem em variáveis de módulo
// e sobreviviam à remontagem. Isso fazia a tela mentir de dois jeitos:
//   • clicar "editar" num recado, sair da aba e voltar deixava o formulário
//     limpo (botão "publicar") com o id antigo ainda na memória, então o
//     próximo "publicar" SOBRESCREVIA o recado velho em vez de criar um novo.
//     Na agenda era pior: o encontro reescrito leva junto as presenças já
//     confirmadas, que continuam na mesma linha de `events`.
//   • o campo de busca voltava vazio mas a lista continuava filtrada pelo termo
//     de antes, sem nada na tela dizendo por quê.
// O filtro de STATUS não entra aqui de propósito: ele tem um chip aceso na
// tela, então ele não mente.
// No quadro de pautas, o QUADRO ABERTO e o jeito de ver (tabela/quadro) NÃO são
// zerados: os dois têm um chip aceso na tela dizendo onde a pessoa está, então
// eles não mentem, e voltar pro quadro onde se estava é o certo.
function zerarEstadoDasAbas() {
  recadoEditando = null;
  trilhaEditando = null;
  agendaEditando = null;
  pontosPessoa = null;
  [filtrosBrindes, filtrosPresentes, filtrosMural, filtrosLeads, filtrosAssinaturas, estadoQuadro].forEach((f) => {
    f.busca = '';
  });
}

function abrirDoHash() {
  const pedida = (window.location.hash || '').replace('#', '');
  const abas = NAV.filter((item) => item.perm === null || pode(item.perm));
  const item = abas.find((a) => a.id === pedida) || abas[0];
  if (!item) return;
  estado.aba = item.id;
  // Arrumação da casa nunca pode derrubar a tela: se isto estourar, a aba ainda
  // tem que abrir.
  try {
    zerarEstadoDasAbas();
  } catch (e) {
    console.error('[console] não deu pra zerar o estado das abas:', e);
  }

  try {
    marcarAbaEabrir(item);
  } catch (e) {
    // Qualquer tropeço AQUI (marcar a aba ativa, puxar a fila pra vista, montar
    // o mapa de telas) deixava a área do conteúdo em branco, com a barra
    // lateral inteira de pé: da tela, igualzinho a "essa aba não tem nada".
    // Era o último lugar do console capaz de falhar calado.
    const view = $('[data-view]');
    if (view) falhaDaAba(view, item.id, e);
    else console.error('[console] o roteador tropeçou e não achei onde escrever:', e);
  }
}

function marcarAbaEabrir(item) {
  $$('[data-aba]').forEach((botao) => {
    const ativo = botao.dataset.aba === item.id;
    botao.classList.toggle('is-active', ativo);
    if (ativo) botao.setAttribute('aria-current', 'page');
    else botao.removeAttribute('aria-current');
    // Na tela estreita a barra vira uma fila que rola, e a aba aberta pode
    // nascer fora da vista (as últimas da fila sempre nasceriam). Puxa ela pra
    // dentro, do mesmo jeito que a tirinha do /cardapio faz com os chips.
    const fila = ativo ? botao.closest('.ad-nav') : null;
    if (fila && fila.scrollWidth > fila.clientWidth) {
      const semMovimento = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      botao.scrollIntoView({ inline: 'center', block: 'nearest', behavior: semMovimento ? 'auto' : 'smooth' });
    }
  });

  const view = $('[data-view]');
  if (!view) return;
  view.scrollTop = 0;
  const telas = {
    painel: viewPainel,
    pautas: viewPautas,
    rastros: viewRastros,
    pedidos: viewPedidos,
    resgates: viewResgates,
    aniversarios: viewAniversarios,
    presentes: viewPresentes,
    assinaturas: viewAssinaturas,
    pontos: viewPontos,
    pessoas: viewPessoas,
    mural: viewMural,
    relatorios: viewRelatorios,
    favoritos: viewFavoritos,
    desejos: viewDesejos,
    esperando: viewReposicao,
    espera: viewListaEspera,
    leads: viewLeadsEventos,
    equipe: viewEquipe,
    recados: viewRecados,
    trilha: viewTrilha,
    agenda: viewAgenda,
    fotos: viewFotos,
    conta: viewConta,
  };
  // TODA view é `async`. Se uma delas estoura ANTES do try/catch que ela tem por
  // dentro (um elemento que não veio, um helper que sumiu), a promise rejeita e
  // a área do conteúdo fica EM BRANCO, sem uma linha dizendo o quê: a tela toda
  // parece vazia e não há como saber de onde veio. Falha de tela tem que
  // aparecer NA TELA.
  const abrirAba = telas[item.id] || viewPainel;
  try {
    Promise.resolve(abrirAba(view)).catch((e) => falhaDaAba(view, item.id, e));
  } catch (e) {
    falhaDaAba(view, item.id, e);
  }
}

function falhaDaAba(view, aba, e) {
  // O nome da aba e o erro vão como ARGUMENTOS, não interpolados no texto: se
  // um dia o rótulo vier de fora, um "%s" dentro dele forjaria a linha do log.
  console.error('[console] a aba não abriu:', aba, e);
  view.innerHTML = `
    <div class="notice err">
      <p><strong>essa aba não abriu.</strong></p>
      <p>${escapeHtml(e?.message || String(e))}</p>
      <p class="ad-dica">troca de aba pra seguir usando o resto do console, e me manda esse texto que eu conserto.</p>
    </div>`;
}

function cabecalho(titulo, texto, extra = '') {
  return `
    <header class="ad-head">
      <div>
        <h1 class="title md">${escapeHtml(titulo)}</h1>
        <p class="ad-head-sub">${escapeHtml(texto)}</p>
      </div>
      <div class="ad-head-acoes">${extra}</div>
    </header>`;
}

// ===== PAINEL =======================================================
async function viewPainel(view) {
  view.innerHTML = cabecalho('o dia no Casa', 'como está a casa agora.') + '<div data-corpo></div>';
  const corpo = $('[data-corpo]', view);
  carregando(corpo, 'contando…');
  try {
    const d = await rpc('admin_dashboard');
    const numeros = [
      { n: formatNumero(d.pedidos_hoje), l: 'pedidos hoje' },
      { n: formatBRL(d.receita_hoje_centavos), l: 'entrou hoje' },
      { n: formatBRL(d.receita_mes_centavos), l: 'entrou no mês' },
      { n: formatNumero(d.a_entregar), l: 'pra entregar' },
      { n: formatNumero(d.a_retirar), l: 'pra retirar' },
      { n: formatNumero(d.resgates_abertos), l: 'resgates abertos' },
      { n: formatNumero(d.pessoas), l: 'pessoas cadastradas' },
      { n: formatNumero(d.assinantes_ativos), l: 'assinantes ativos' },
      { n: formatNumero(d.pontos_em_circulacao), l: 'pontos em circulação' },
    ];
    corpo.innerHTML = `
      <div class="ad-stats">
        ${numeros
          .map(
            (item) => `
          <div class="stat card">
            <p class="n">${escapeHtml(item.n)}</p>
            <p class="l">${escapeHtml(item.l)}</p>
          </div>`,
          )
          .join('')}
      </div>
      ${
        Number(d.a_entregar) + Number(d.a_retirar) > 0 && pode('pedidos.ver')
          ? `<div class="notice info"><p>tem gente esperando: <a class="form-link" href="#pedidos">ver os pedidos abertos</a>.</p></div>`
          : ''
      }`;
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

// ===== RASTROS (por onde a pessoa andou) ============================
// A tela que faltava pra casa responder três perguntas que o console não
// respondia: em que tela a pessoa estava quando fechou a aba, que seção todo
// mundo vê e ninguém toca, e quanta gente encheu o carrinho e foi embora.
//
// Vem tudo da 0053: `admin_rastros_resumo` (anônimo, gated em `rastros.ver`) e
// `admin_rastros_leads` (COM nome e telefone, gated em `pedidos.ver`). São duas
// travas diferentes de propósito, e por isso a lista de contatos só é BUSCADA
// quando a pessoa alcança os pedidos — pedir e tomar erro na cara seria dizer
// que ela devia poder.
const RASTRO_PERIODOS = [
  { dias: 7, rotulo: '7 dias' },
  { dias: 30, rotulo: '30 dias' },
  { dias: 90, rotulo: '90 dias' },
];
let rastrosDias = 30;

async function viewRastros(view) {
  view.innerHTML =
    cabecalho(
      'os rastros',
      'por onde a pessoa andou, e em que tela ela largou o site.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    `<div class="ad-filtros" role="group" aria-label="período do relatório">
      ${RASTRO_PERIODOS.map(
        (p) => `<button type="button" class="filtro" data-f-dias="${p.dias}">${escapeHtml(p.rotulo)}</button>`,
      ).join('')}
    </div>
    <div data-corpo></div>`;

  const corpo = $('[data-corpo]', view);
  const marcar = () =>
    $$('[data-f-dias]', view).forEach((b) =>
      b.setAttribute('aria-pressed', String(Number(b.dataset.fDias) === rastrosDias)),
    );
  $$('[data-f-dias]', view).forEach((b) =>
    b.addEventListener('click', () => {
      rastrosDias = Number(b.dataset.fDias) || 30;
      marcar();
      carregarRastros(corpo);
    }),
  );
  $('[data-recarregar]', view).addEventListener('click', () => carregarRastros(corpo));
  marcar();
  renderIcons();
  carregarRastros(corpo);
}

async function carregarRastros(corpo) {
  carregando(corpo, 'seguindo os passos…');
  try {
    const [resumo, leads] = await Promise.all([
      rpc('admin_rastros_resumo', { p_dias: rastrosDias }),
      // Só pede os contatos se a pessoa alcança os pedidos: a lista tem nome e
      // telefone de quem comprou quase, e `rastros.ver` não é chave pra isso.
      pode('pedidos.ver') ? rpc('admin_rastros_leads', { p_dias: rastrosDias, p_limite: 50 }) : Promise.resolve(null),
    ]);

    const n = resumo?.numeros || {};
    if (!Number(n.visitas)) {
      corpo.innerHTML = vazio(
        'ainda não tem rastro nenhum',
        'assim que o site novo estiver no ar e alguém passar por lá, os passos começam a aparecer aqui.',
      );
      return;
    }

    // O respiro entre os blocos vem do `.ad-rastros`: o `.ad-conteudo` tem gap,
    // mas o div do corpo é um bloco pelado, e cinco `.ad-bloco` irmãos ficariam
    // colados um no outro.
    corpo.innerHTML =
      '<div class="ad-rastros">' +
      [
        blocoNumerosRastro(n),
        blocoSaidas(resumo?.saidas || []),
        blocoSecoes(resumo?.secoes || []),
        blocoFunilLoja(resumo?.loja || {}, Number(n.visitas)),
        blocoCarrinhosFrios(leads),
      ].join('') +
      '</div>';
    renderIcons();
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

function blocoNumerosRastro(n) {
  const visitas = Number(n.visitas) || 0;
  const pct = (v) => (visitas ? `${Math.round((Number(v) || 0) * 100 / visitas)}%` : '0%');
  const numeros = [
    { n: formatNumero(n.visitas), l: 'visitas' },
    { n: formatNumero(n.cliques), l: 'cliques' },
    // A leitura mais dura da tela, e a que mais ensina: quem entrou, olhou e
    // não tocou em nada.
    { n: pct(n.sem_clique), l: 'saíram sem tocar em nada' },
    { n: pct(n.uma_pagina), l: 'viram uma página só' },
    { n: pct(n.no_celular), l: 'vieram pelo celular' },
    { n: formatNumero(n.com_carrinho), l: 'encheram o carrinho' },
  ];
  return `
    <div class="ad-stats">
      ${numeros
        .map(
          (item) => `
        <div class="stat card">
          <p class="n">${escapeHtml(item.n)}</p>
          <p class="l">${escapeHtml(item.l)}</p>
        </div>`,
        )
        .join('')}
    </div>`;
}

function blocoSaidas(saidas) {
  if (!saidas.length) {
    return secaoRastro(
      'onde a visita terminou',
      'a última tela antes de fechar',
      vazio('ninguém saiu ainda', 'ou o rastro é novo demais pra ter fim de visita.'),
    );
  }
  const linhas = saidas
    .map(
      (s) => `
      <tr>
        <td><span class="ad-td-forte">${escapeHtml(s.pagina || '—')}</span></td>
        <td><span class="ad-td-meta">${escapeHtml(s.secao || '—')}</span></td>
        <td>${
          s.alvo
            ? `<span class="ad-td-meta">${escapeHtml(s.alvo)}</span>`
            : '<span class="tag">não tocou em nada</span>'
        }</td>
        <td class="num">${formatNumero(s.visitas)}</td>
        <td class="num">${Number(s.com_carrinho) ? `<span class="tag coral">${formatNumero(s.com_carrinho)}</span>` : '—'}</td>
      </tr>`,
    )
    .join('');
  return secaoRastro(
    'onde a visita terminou',
    'a última coisa tocada antes de fechar o site',
    `<div class="ad-tabela-wrap">
       <table class="ad-tabela">
         <thead><tr><th>página</th><th>seção</th><th>último clique</th><th class="num">visitas</th><th class="num">com carrinho</th></tr></thead>
         <tbody>${linhas}</tbody>
       </table>
     </div>
     <p class="ad-dica">a coluna "com carrinho" é a que dói: são visitas que escolheram alguma coisa e foram embora dessa tela.</p>`,
  );
}

function blocoSecoes(secoes) {
  if (!secoes.length) {
    return secaoRastro('o que está frio', 'quem todo mundo vê e ninguém toca', vazio('sem seção medida ainda', 'volta aqui depois de umas visitas.'));
  }
  const linhas = secoes
    .map((s) => {
      const vistas = Number(s.vistas) || 0;
      const cliques = Number(s.cliques) || 0;
      // Sem plateia não há o que concluir: a linha aparece, mas não finge ter
      // uma taxa que signifique alguma coisa.
      const taxa = vistas ? Math.round((cliques / vistas) * 100) : null;
      const largura = taxa === null ? 0 : Math.min(100, Math.max(3, taxa));
      return `
      <tr>
        <td>
          <span class="ad-td-forte">${escapeHtml(s.secao || '—')}</span>
          <span class="ad-td-meta">${escapeHtml(s.pagina || '')}</span>
        </td>
        <td class="num">${formatNumero(vistas)}</td>
        <td class="num">${formatNumero(cliques)}</td>
        <td>
          <div class="ad-fav-bar"><span style="width:${largura}%"></span></div>
        </td>
        <td class="num">${taxa === null ? '—' : `${taxa}%`}</td>
        <td>${s.fria ? '<span class="tag blue"><i data-lucide="snowflake"></i>fria</span>' : ''}</td>
      </tr>`;
    })
    .join('');
  return secaoRastro(
    'o que está frio',
    'a seção que muita gente vê e quase ninguém toca',
    `<div class="ad-tabela-wrap">
       <table class="ad-tabela">
         <thead><tr><th>seção</th><th class="num">olhos</th><th class="num">dedos</th><th>toque</th><th class="num">taxa</th><th></th></tr></thead>
         <tbody>${linhas}</tbody>
       </table>
     </div>
     <p class="ad-dica">"olhos" é quantas vezes a seção ficou meio segundo na tela de alguém; "dedos" é quantas vezes alguém tocou nela. A fria leva selo quando teve 20 olhos ou mais e menos de 5% de toque. Seção sem olho nenhum fica no fim da fila: ali não é frieza, é que ninguém chegou até lá.</p>`,
  );
}

function blocoFunilLoja(loja, visitas) {
  const degraus = [
    { l: 'abriram a loja', v: loja.viram_loja },
    { l: 'abriram um produto', v: loja.viram_produto },
    { l: 'puseram no carrinho', v: loja.com_carrinho },
    { l: 'foram ao checkout', v: loja.foram_ao_checkout },
    { l: 'compraram', v: loja.compraram },
  ];
  const topo = Math.max(...degraus.map((d) => Number(d.v) || 0), 1);
  const frio = Number(loja.carrinho_frio_centavos) || 0;
  return secaoRastro(
    'o funil da loja',
    `de ${formatNumero(visitas)} visitas até a compra`,
    `<div class="ad-fav-lista">
       ${degraus
         .map((d, i) => {
           const v = Number(d.v) || 0;
           const pct = Math.max(3, Math.round((v / topo) * 100));
           return `
        <div class="ad-fav-row">
          <span class="ad-fav-pos">${i + 1}</span>
          <div class="ad-fav-main">
            <p class="ad-fav-nome">${escapeHtml(d.l)}</p>
            <div class="ad-fav-bar"><span style="width:${pct}%"></span></div>
          </div>
          <span class="ad-fav-n">${formatNumero(v)}</span>
        </div>`;
         })
         .join('')}
     </div>
     ${
       frio > 0
         ? `<div class="notice info"><p>ficou <strong>${escapeHtml(formatBRL(frio))}</strong> parado em carrinho que não virou compra no período.</p></div>`
         : ''
     }
     <p class="ad-dica">a queda entre dois degraus é onde a compra morre. Se muita gente abre produto e pouca põe no carrinho, o problema é a página do produto; se enche o carrinho e não vai ao checkout, é o carrinho.</p>`,
  );
}

function blocoCarrinhosFrios(leads) {
  // `null` = a pessoa não alcança os pedidos, então a lista nem foi buscada.
  // Dizer isso é melhor do que sumir com a seção: quem lê o relatório precisa
  // saber que existe uma metade acionável, e a quem pedir.
  if (leads === null) {
    return secaoRastro(
      'os carrinhos frios',
      'quem chegou perto de comprar',
      `<div class="notice"><p>quem enche o carrinho e não paga tem nome e telefone, então essa lista mora atrás da permissão dos <strong>pedidos</strong>. pede pro adm do Casa se tu precisa falar com essa gente.</p></div>`,
    );
  }
  if (!leads.length) {
    return secaoRastro(
      'os carrinhos frios',
      'quem chegou perto de comprar',
      vazio('ninguém parou no meio do caminho', 'todo checkout aberto no período virou compra, ou ainda não houve nenhum.'),
    );
  }
  const linhas = leads
    .map((l) => {
      const digitos = String(l.telefone || '').replace(/\D/g, '');
      const zap = digitos.length >= 10 ? `https://wa.me/55${digitos.slice(-11)}` : null;
      const itens = Array.isArray(l.itens) ? l.itens : [];
      const oQue = itens.length
        ? itens.map((i) => `${i.qtd}× ${i.nome}${i.variante ? ` (${i.variante})` : ''}`).join(', ')
        : 'não chegou a escolher';
      return `
      <tr>
        <td>
          <span class="ad-td-forte">${escapeHtml(l.nome || 'sem nome')}</span>
          <span class="ad-td-meta">${escapeHtml(l.email || '')}</span>
        </td>
        <td>${
          zap
            ? `<a class="form-link" href="${escapeHtml(zap)}" target="_blank" rel="noopener">${escapeHtml(l.telefone)}</a>`
            : `<span class="ad-td-meta">${escapeHtml(l.telefone || '—')}</span>`
        }</td>
        <td><span class="ad-td-meta">${escapeHtml(oQue)}</span></td>
        <td class="num">${escapeHtml(formatBRL(l.total_centavos))}</td>
        <td><span class="ad-td-meta">${escapeHtml(formatData(l.criado_em, false))}</span></td>
        <td>${
          l.voltou
            ? '<span class="tag green">voltou e comprou</span>'
            : '<span class="tag gold">esfriou</span>'
        }</td>
      </tr>`;
    })
    .join('');
  return secaoRastro(
    'os carrinhos frios',
    'quem abriu o checkout e não pagou',
    `<div class="ad-tabela-wrap">
       <table class="ad-tabela">
         <thead><tr><th>quem</th><th>telefone</th><th>o que ficou no carrinho</th><th class="num">valor</th><th>quando</th><th></th></tr></thead>
         <tbody>${linhas}</tbody>
       </table>
     </div>
     <p class="ad-dica">o telefone abre a conversa no WhatsApp daqui mesmo. quem já "voltou e comprou" não precisa de recado, foi tentativa que deu errado e resolveu sozinha.</p>`,
  );
}

function secaoRastro(titulo, sub, dentro) {
  return `
    <section class="ad-bloco">
      <div class="ad-bloco-head">
        <h2 class="title sm">${escapeHtml(titulo)}</h2>
        <p class="ad-head-sub">${escapeHtml(sub)}</p>
      </div>
      ${dentro}
    </section>`;
}


// ===== PAUTAS (o quadro da casa) ====================================
// A 0043 entregou um quadro só, com três colunas fixas e um formulário grande
// em cima. A 0045 trouxe o que faltava pra ele ser um quadro de verdade: vários
// QUADROS, GRUPOS dentro de cada um, o estado 'travada', comentário por pauta e
// edição direto na célula.
//
// Como isto funciona, e por que assim:
//   • Uma leitura só (`admin_quadro_abrir`) traz quadro + grupos + itens. Tudo
//     que a tela mostra sai de `estadoQuadro.dados`, sem segunda viagem.
//   • UM listener delegado no corpo do quadro, não um por botão. Com célula
//     clicável em toda linha, religar listener a cada render seria caro e
//     frágil.
//   • Mudar uma célula NÃO recarrega o quadro: a linha se reescreve sozinha.
//     Recarregar faria a tela piscar e devolver o scroll ao topo a cada toque,
//     no aparelho onde o console é usado no meio do turno.
//   • Pauta nova nasce na linha "+ pauta" do próprio grupo, só com o título. O
//     resto se preenche clicando nas células, que é como se usa um quadro.

// As seis cores são exatamente as variantes de `.tag` que já existem no CSS, e
// o banco só aceita esses seis slugs. Cor do banco nunca vira `style=`.
const CORES_QUADRO = [
  { slug: 'coral', rotulo: 'terracota' },
  { slug: 'gold', rotulo: 'caramelo' },
  { slug: 'green', rotulo: 'verde' },
  { slug: 'olive', rotulo: 'oliva' },
  { slug: 'blue', rotulo: 'azul' },
  { slug: 'neutro', rotulo: 'sem cor' },
];

const ESTADOS_PAUTA = [
  { slug: 'aberta', rotulo: 'a fazer', cor: 'neutro' },
  { slug: 'fazendo', rotulo: 'fazendo', cor: 'gold' },
  { slug: 'travada', rotulo: 'travada', cor: 'coral' },
  { slug: 'feita', rotulo: 'feita', cor: 'green' },
];

const PRIORIDADES = [
  { slug: 'alta', rotulo: 'urgente', cor: 'coral' },
  { slug: 'normal', rotulo: 'normal', cor: 'olive' },
  { slug: 'baixa', rotulo: 'quando der', cor: 'neutro' },
];

const estadoQuadro = {
  quadroId: null,
  visao: 'tabela', // 'tabela' | 'quadro'
  busca: '',
  dequem: '',
  dados: null,
  quadros: [],
};
let equipeDasPautas = [];

const corValida = (c) => (CORES_QUADRO.some((x) => x.slug === c) ? c : 'neutro');
const acheEstado = (s) => ESTADOS_PAUTA.find((e) => e.slug === s) || ESTADOS_PAUTA[0];
const achePrioridade = (s) => PRIORIDADES.find((p) => p.slug === s) || PRIORIDADES[1];

// O prazo vem como date puro (YYYY-MM-DD). `new Date` leria isso como UTC e no
// Brasil voltaria um dia, então a data é montada na mão, sem fuso.
function dataDoPrazo(iso) {
  if (!iso) return '';
  const [a, m, d] = String(iso).slice(0, 10).split('-');
  return a && m && d ? `${d}/${m}` : '';
}

function hojeISO() {
  const h = new Date();
  return `${h.getFullYear()}-${String(h.getMonth() + 1).padStart(2, '0')}-${String(h.getDate()).padStart(2, '0')}`;
}

function maisDias(n) {
  const h = new Date();
  h.setDate(h.getDate() + n);
  return `${h.getFullYear()}-${String(h.getMonth() + 1).padStart(2, '0')}-${String(h.getDate()).padStart(2, '0')}`;
}

function prazoVencido(iso) {
  return Boolean(iso) && String(iso).slice(0, 10) < hojeISO();
}

function iniciais(nome) {
  const partes = String(nome || '').trim().split(/\s+/).filter(Boolean);
  if (!partes.length) return '?';
  return (partes[0][0] + (partes.length > 1 ? partes[partes.length - 1][0] : '')).toUpperCase();
}

// ---------------------------------------------------------------------------
// escolher() — a folhinha de opções que abre ao tocar numa célula.
// Reusa a casca do `confirmar()` (Esc, clique fora, foco), então ganha de graça
// o comportamento que aquele modal já tem. Vira folha de rodapé no celular só
// por media query: uma marcação, dois comportamentos.
// ---------------------------------------------------------------------------
function escolher({ titulo, opcoes, atual, rodape = '' }) {
  return new Promise((resolve) => {
    const fundo = document.createElement('div');
    fundo.className = 'ad-modal pauta-escolha';
    fundo.innerHTML = `
      <div class="ad-modal-caixa pauta-escolha-caixa" role="dialog" aria-modal="true" aria-label="${escapeHtml(titulo)}">
        <p class="lbl">${escapeHtml(titulo)}</p>
        <div class="pauta-opcoes">
          ${opcoes
            .map(
              (o) => `
            <button type="button" class="pauta-opcao${o.valor === atual ? ' is-atual' : ''}" data-valor="${escapeHtml(String(o.valor ?? ''))}">
              ${o.cor ? `<span class="pauta-bolha tag ${escapeHtml(corValida(o.cor))}" aria-hidden="true"></span>` : ''}
              ${o.inicial ? `<span class="pauta-avatar" aria-hidden="true">${escapeHtml(o.inicial)}</span>` : ''}
              <span>${escapeHtml(o.rotulo)}</span>
              ${o.valor === atual ? '<i data-lucide="check"></i>' : ''}
            </button>`,
            )
            .join('')}
        </div>
        ${rodape}
        <div class="ad-modal-acoes">
          <button type="button" class="btn ghost sm" data-fechar>deixa pra lá</button>
        </div>
      </div>`;

    const fechar = (resposta) => {
      document.removeEventListener('keydown', aoTeclar);
      fundo.remove();
      resolve(resposta);
    };
    const aoTeclar = (e) => {
      if (e.key === 'Escape') fechar(null);
    };
    fundo.addEventListener('click', (e) => {
      if (e.target === fundo) return fechar(null);
      const botao = e.target.closest('[data-valor]');
      if (botao) return fechar(botao.dataset.valor);
      if (e.target.closest('[data-fechar]')) return fechar(null);
    });
    // O campo de data manda o valor por submit, pra o teclado do celular fechar
    // com "ok" em vez de pedir um toque a mais.
    fundo.addEventListener('submit', (e) => {
      e.preventDefault();
      const campo = $('[data-data-livre]', fundo);
      if (campo) fechar(campo.value || '');
    });
    document.addEventListener('keydown', aoTeclar);
    document.body.appendChild(fundo);
    renderIcons();
    $('.pauta-opcao', fundo)?.focus();
  });
}

// ---------------------------------------------------------------------------
// A tela
// ---------------------------------------------------------------------------
async function viewPautas(view) {
  view.innerHTML =
    cabecalho(
      'o quadro da casa',
      'o que a gente combinou. cada quadro é um canto da casa, cada grupo é uma fila, e o estado se muda tocando na célula.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    `<div class="pauta-quadros" data-quadros></div>
     <div class="pauta-barra">
       <form class="ad-busca pauta-busca" data-busca-pauta>
         <div class="field">
           <label for="busca-pauta" class="sr-only">buscar por pauta ou por quem recebeu</label>
           <input id="busca-pauta" type="search" placeholder="buscar no quadro" autocomplete="off" />
         </div>
         <button type="submit" class="btn ghost sm"><i data-lucide="search"></i>buscar</button>
       </form>
       <div class="ad-filtros" role="group" aria-label="filtrar pautas">
         <button type="button" class="filtro" data-f-quem="">de todo mundo</button>
         <button type="button" class="filtro" data-f-quem="eu">minhas</button>
       </div>
       <div class="ad-filtros pauta-visoes" role="group" aria-label="jeito de ver o quadro">
         <button type="button" class="filtro" data-visao="tabela"><i data-lucide="table-2"></i>tabela</button>
         <button type="button" class="filtro" data-visao="quadro"><i data-lucide="columns-3"></i>quadro</button>
       </div>
     </div>
     <div data-quadro-corpo></div>`;

  const corpo = $('[data-quadro-corpo]', view);
  const barraQuadros = $('[data-quadros]', view);

  const marcar = () => {
    $$('[data-f-quem]', view).forEach((b) =>
      b.setAttribute('aria-pressed', String(b.dataset.fQuem === estadoQuadro.dequem)),
    );
    $$('[data-visao]', view).forEach((b) =>
      b.setAttribute('aria-pressed', String(b.dataset.visao === estadoQuadro.visao)),
    );
  };

  $$('[data-f-quem]', view).forEach((b) =>
    b.addEventListener('click', () => {
      estadoQuadro.dequem = b.dataset.fQuem;
      marcar();
      abrirQuadro(corpo);
    }),
  );
  $$('[data-visao]', view).forEach((b) =>
    b.addEventListener('click', () => {
      estadoQuadro.visao = b.dataset.visao;
      marcar();
      desenharQuadro(corpo);
    }),
  );
  $('[data-busca-pauta]', view).addEventListener('submit', (e) => {
    e.preventDefault();
    estadoQuadro.busca = $('#busca-pauta', view).value.trim();
    abrirQuadro(corpo);
  });
  $('[data-recarregar]', view).addEventListener('click', () => {
    carregarQuadros(barraQuadros, corpo);
  });

  // Um listener só, delegado, pro corpo inteiro do quadro.
  corpo.addEventListener('click', (ev) => aoTocarNoQuadro(ev, corpo));
  corpo.addEventListener('submit', (ev) => aoSubmeterNoQuadro(ev, corpo));
  barraQuadros.addEventListener('click', (ev) => aoTocarNosQuadros(ev, barraQuadros, corpo));

  marcar();
  renderIcons();
  await carregarEquipeDasPautas();
  await carregarQuadros(barraQuadros, corpo);
}

async function carregarEquipeDasPautas() {
  try {
    const gente = await rpc('admin_pautas_equipe');
    equipeDasPautas = Array.isArray(gente) ? gente : [];
  } catch {
    equipeDasPautas = [];
  }
}

async function carregarQuadros(barra, corpo) {
  try {
    const lista = await rpc('admin_quadros_listar');
    estadoQuadro.quadros = Array.isArray(lista) ? lista : [];
  } catch (e) {
    estadoQuadro.quadros = [];
    erroNaTela(corpo, e);
    return;
  }
  desenharBarraDeQuadros(barra);
  await abrirQuadro(corpo);
}

function desenharBarraDeQuadros(barra) {
  const vivos = estadoQuadro.quadros.filter((q) => !q.arquivado);
  const arquivados = estadoQuadro.quadros.filter((q) => q.arquivado);
  barra.innerHTML = `
    ${vivos
      .map(
        (q) => `
      <button type="button" class="pauta-quadro-chip${q.id === estadoQuadro.quadroId ? ' is-atual' : ''}"
              data-abrir-quadro="${escapeHtml(q.id)}" aria-pressed="${q.id === estadoQuadro.quadroId}">
        <span class="pauta-bolha tag ${escapeHtml(corValida(q.cor))}" aria-hidden="true"></span>
        <span>${escapeHtml(q.nome)}</span>
        ${Number(q.abertas) > 0 ? `<span class="pauta-chip-n">${formatNumero(q.abertas)}</span>` : ''}
      </button>`,
      )
      .join('')}
    <button type="button" class="pauta-quadro-novo" data-novo-quadro><i data-lucide="plus"></i>novo quadro</button>
    ${
      arquivados.length
        ? `<button type="button" class="pauta-quadro-novo" data-ver-arquivados><i data-lucide="archive"></i>arquivados (${formatNumero(arquivados.length)})</button>`
        : ''
    }`;
  renderIcons();
}

async function abrirQuadro(corpo) {
  carregando(corpo, 'abrindo o quadro…');
  try {
    const dados = await rpc('admin_quadro_abrir', {
      p_quadro_id: estadoQuadro.quadroId,
      p_busca: estadoQuadro.busca || null,
      p_de_quem: estadoQuadro.dequem === 'eu' ? estado.sessao?.user?.id || null : null,
    });
    estadoQuadro.dados = dados || null;
    estadoQuadro.quadroId = dados?.quadro?.id || null;
    const barra = $('[data-quadros]');
    if (barra) desenharBarraDeQuadros(barra);
    desenharQuadro(corpo);
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

function desenharQuadro(corpo) {
  const d = estadoQuadro.dados;
  if (!d || !d.quadro) {
    corpo.innerHTML = vazio(
      'nenhum quadro ainda',
      'cria o primeiro aí em cima. um quadro por canto da casa (salão, cozinha, o que fizer sentido).',
    );
    return;
  }
  corpo.innerHTML = estadoQuadro.visao === 'quadro' ? kanbanHTML(d) : tabelaHTML(d);
  renderIcons();
}

// ---------------------------------------------------------------------------
// Visão TABELA: grupos com faixa colorida e linhas com célula clicável.
// ---------------------------------------------------------------------------
function tabelaHTML(d) {
  const grupos = Array.isArray(d.grupos) ? d.grupos : [];
  const itens = Array.isArray(d.itens) ? d.itens : [];
  const soltos = itens.filter((i) => !i.grupo_id || !grupos.some((g) => g.id === i.grupo_id));

  const blocos = grupos.map((g) => grupoHTML(g, itens.filter((i) => i.grupo_id === g.id)));
  if (soltos.length) {
    blocos.push(grupoHTML({ id: '', nome: 'sem grupo', cor: 'neutro', recolhido: false }, soltos, true));
  }

  return `
    <div class="pauta-topo-acoes">
      <button type="button" class="btn ghost sm" data-novo-grupo><i data-lucide="plus"></i>novo grupo</button>
      <button type="button" class="btn ghost sm" data-editar-quadro><i data-lucide="pencil"></i>renomear o quadro</button>
      <button type="button" class="btn ghost sm" data-arquivar-quadro><i data-lucide="archive"></i>arquivar</button>
      <button type="button" class="btn ghost sm" data-apagar-quadro><i data-lucide="trash-2"></i>apagar</button>
    </div>
    <div class="pauta-tabela" role="table" aria-label="${escapeHtml(d.quadro.nome || 'quadro')}">
      <div class="pauta-cabeca" role="row">
        <span role="columnheader">a pauta</span>
        <span role="columnheader">pra quem</span>
        <span role="columnheader">estado</span>
        <span role="columnheader">até quando</span>
        <span role="columnheader">urgência</span>
        <span role="columnheader"><span class="sr-only">ações</span></span>
      </div>
      ${blocos.join('') || vazio('esse quadro está limpo', 'cria um grupo e escreve a primeira pauta.')}
    </div>`;
}

function grupoHTML(g, itens, semGrupo = false) {
  const cor = corValida(g.cor);
  const feitas = itens.filter((i) => i.status === 'feita').length;
  return `
    <section class="pauta-grupo" data-grupo="${escapeHtml(g.id || '')}" data-cor="${escapeHtml(cor)}" role="rowgroup">
      <header class="pauta-grupo-topo">
        <button type="button" class="pauta-grupo-abrir" data-recolher="${escapeHtml(g.id || '')}"
                aria-expanded="${!g.recolhido}" ${semGrupo ? 'disabled' : ''}>
          <i data-lucide="${g.recolhido ? 'chevron-right' : 'chevron-down'}"></i>
        </button>
        <span class="pauta-grupo-cor" aria-hidden="true"></span>
        <p class="pauta-grupo-nome">${escapeHtml(g.nome)}</p>
        <span class="pauta-grupo-conta">${formatNumero(itens.length)} ${itens.length === 1 ? 'pauta' : 'pautas'}${feitas ? ` · ${formatNumero(feitas)} feita${feitas > 1 ? 's' : ''}` : ''}</span>
        ${
          semGrupo
            ? ''
            : `<span class="pauta-grupo-acoes">
                 <button type="button" class="btn ghost sm pauta-ico" data-editar-grupo="${escapeHtml(g.id)}" aria-label="renomear o grupo" title="renomear"><i data-lucide="pencil"></i></button>
                 <button type="button" class="btn ghost sm pauta-ico" data-apagar-grupo="${escapeHtml(g.id)}" data-nome="${escapeHtml(g.nome)}" aria-label="apagar o grupo" title="apagar"><i data-lucide="trash-2"></i></button>
               </span>`
        }
      </header>
      ${
        g.recolhido
          ? ''
          : `${itens.map(linhaPautaHTML).join('')}
             ${
               semGrupo
                 ? ''
                 : `<form class="pauta-nova" data-nova-pauta="${escapeHtml(g.id)}">
                      <i data-lucide="plus"></i>
                      <input type="text" maxlength="120" placeholder="escreve uma pauta e dá enter" aria-label="escrever uma pauta em ${escapeHtml(g.nome)}" />
                    </form>`
             }`
      }
    </section>`;
}

function linhaPautaHTML(p) {
  const est = acheEstado(p.status);
  const pri = achePrioridade(p.prioridade);
  const vencido = p.status !== 'feita' && prazoVencido(p.prazo);
  return `
    <div class="pauta-linha${p.status === 'feita' ? ' is-feita' : ''}" role="row" data-pauta="${escapeHtml(p.id)}">
      <div class="pl-titulo" role="cell">
        <button type="button" class="pauta-abrir-item" data-abrir-item="${escapeHtml(p.id)}">
          <span class="pl-txt">${escapeHtml(p.titulo || '')}</span>
        </button>
        <span class="pl-sinais">
          ${p.briefing ? '<i data-lucide="align-left" title="tem briefing"></i>' : ''}
          ${Number(p.comentarios) > 0 ? `<span class="pl-coment"><i data-lucide="message-square"></i>${formatNumero(p.comentarios)}</span>` : ''}
        </span>
      </div>
      <div class="pl-pessoa" role="cell">
        <button type="button" class="pauta-celula" data-celula="atribuido_a" title="pra quem">
          ${
            p.atribuido_a
              ? `<span class="pauta-avatar">${escapeHtml(iniciais(p.atribuido_nome))}</span><span class="pl-nome">${escapeHtml(p.atribuido_nome || 'alguém')}</span>`
              : '<span class="pauta-avatar is-vazio">+</span><span class="pl-nome pl-fraco">toda a equipe</span>'
          }
        </button>
      </div>
      <div class="pl-estado" role="cell">
        <button type="button" class="pauta-celula pauta-estado tag ${escapeHtml(est.cor)}" data-celula="status" title="estado">
          ${escapeHtml(est.rotulo)}
        </button>
      </div>
      <div class="pl-prazo" role="cell">
        <button type="button" class="pauta-celula${vencido ? ' is-vencido' : ''}" data-celula="prazo" title="até quando">
          ${p.prazo ? `<i data-lucide="calendar-clock"></i>${escapeHtml(dataDoPrazo(p.prazo))}` : '<span class="pl-fraco">sem prazo</span>'}
        </button>
      </div>
      <div class="pl-urg" role="cell">
        <button type="button" class="pauta-celula pauta-urg tag ${escapeHtml(pri.cor)}" data-celula="prioridade" title="urgência">
          ${escapeHtml(pri.rotulo)}
        </button>
      </div>
      <div class="pl-acoes" role="cell">
        <button type="button" class="btn ghost sm pauta-ico" data-mover="cima" aria-label="subir a pauta" title="subir"><i data-lucide="chevron-up"></i></button>
        <button type="button" class="btn ghost sm pauta-ico" data-mover="baixo" aria-label="descer a pauta" title="descer"><i data-lucide="chevron-down"></i></button>
        <button type="button" class="btn ghost sm pauta-ico" data-apagar-pauta aria-label="apagar a pauta" title="apagar"><i data-lucide="trash-2"></i></button>
      </div>
    </div>`;
}

// ---------------------------------------------------------------------------
// Visão QUADRO (kanban): as mesmas pautas, empilhadas por estado.
// ---------------------------------------------------------------------------
function kanbanHTML(d) {
  const itens = Array.isArray(d.itens) ? d.itens : [];
  return `
    <div class="pauta-kanban">
      ${ESTADOS_PAUTA.map((e) => {
        const daColuna = itens.filter((i) => i.status === e.slug);
        return `
        <section class="pauta-col" aria-label="${escapeHtml(e.rotulo)}">
          <header class="pauta-col-topo">
            <p class="pauta-grupo-nome tag ${escapeHtml(e.cor)}">${escapeHtml(e.rotulo)}</p>
            <span class="pauta-col-conta">${formatNumero(daColuna.length)}</span>
          </header>
          ${
            daColuna.length
              ? daColuna.map(cartaoPautaHTML).join('')
              : '<p class="pauta-col-vazia">nada por aqui</p>'
          }
        </section>`;
      }).join('')}
    </div>`;
}

function cartaoPautaHTML(p) {
  const pri = achePrioridade(p.prioridade);
  const vencido = p.status !== 'feita' && prazoVencido(p.prazo);
  return `
    <article class="card pauta-card${p.prioridade === 'alta' ? ' is-urgente' : ''}" data-pauta="${escapeHtml(p.id)}">
      <button type="button" class="pauta-abrir-item" data-abrir-item="${escapeHtml(p.id)}">
        <span class="pauta-titulo">${escapeHtml(p.titulo || '')}</span>
      </button>
      <div class="pauta-meta">
        <span class="pauta-meta-item"><i data-lucide="user-round"></i>${escapeHtml(p.atribuido_a ? p.atribuido_nome || 'alguém' : 'toda a equipe')}</span>
        ${p.prazo ? `<span class="pauta-meta-item${vencido ? ' is-vencido' : ''}"><i data-lucide="calendar-clock"></i>até ${escapeHtml(dataDoPrazo(p.prazo))}</span>` : ''}
        ${Number(p.comentarios) > 0 ? `<span class="pauta-meta-item"><i data-lucide="message-square"></i>${formatNumero(p.comentarios)}</span>` : ''}
      </div>
      <div class="pauta-acoes">
        <button type="button" class="pauta-celula pauta-urg tag ${escapeHtml(pri.cor)}" data-celula="prioridade">${escapeHtml(pri.rotulo)}</button>
        <span class="pauta-acoes-fim">
          <button type="button" class="btn ghost sm pauta-ico" data-celula="status" aria-label="mudar o estado" title="estado"><i data-lucide="circle-dot"></i></button>
        </span>
      </div>
    </article>`;
}

// ---------------------------------------------------------------------------
// Um toque no quadro: tudo passa por aqui.
// ---------------------------------------------------------------------------
function itemPorId(id) {
  return (estadoQuadro.dados?.itens || []).find((i) => i.id === id) || null;
}

function redesenharLinha(id) {
  const p = itemPorId(id);
  if (!p) return;
  const alvo = document.querySelector(`[data-pauta="${CSS.escape(id)}"]`);
  if (!alvo) return;
  const molde = document.createElement('div');
  molde.innerHTML = estadoQuadro.visao === 'quadro' ? cartaoPautaHTML(p) : linhaPautaHTML(p);
  const nova = molde.firstElementChild;
  alvo.replaceWith(nova);
  renderIcons();
}

async function aoTocarNoQuadro(ev, corpo) {
  const alvo = (sel) => ev.target.closest(sel);
  const idDaLinha = () => ev.target.closest('[data-pauta]')?.dataset.pauta;

  // --- célula: pessoa, estado, prazo, urgência
  const celula = alvo('[data-celula]');
  if (celula) {
    const id = idDaLinha();
    const campo = celula.dataset.celula;
    const p = itemPorId(id);
    if (!id || !p) return;
    const valor = await pedirValorDaCelula(campo, p);
    if (valor === null) return;
    try {
      const r = await rpc('admin_pauta_celula', { p_id: id, p_campo: campo, p_valor: valor === '' ? null : valor });
      if (r && r.ok === false) throw new Error(r.erro || 'não deu pra mudar');
      aplicarNoEstado(p, campo, valor);
      // Mudar de grupo tira a linha de lugar; o resto se resolve na própria linha.
      if (campo === 'grupo_id') desenharQuadro(corpo);
      else redesenharLinha(id);
    } catch (e) {
      toast(e.message, 'erro');
    }
    return;
  }

  if (alvo('[data-abrir-item]')) {
    return abrirPainelDaPauta(alvo('[data-abrir-item]').dataset.abrirItem, corpo);
  }

  const mover = alvo('[data-mover]');
  if (mover) {
    const id = idDaLinha();
    mover.disabled = true;
    try {
      const r = await rpc('admin_pauta_ordenar', { p_id: id, p_direcao: mover.dataset.mover });
      if (r && r.ok === false) throw new Error(r.erro);
      await abrirQuadro(corpo);
    } catch (e) {
      toast(e.message, 'erro');
      mover.disabled = false;
    }
    return;
  }

  if (alvo('[data-apagar-pauta]')) {
    const id = idDaLinha();
    const p = itemPorId(id);
    const ok = await confirmar({
      titulo: `apagar "${p?.titulo || 'essa pauta'}"?`,
      texto: 'some do quadro pra todo mundo, com os comentários dela, e não tem como voltar.',
      ok: 'apagar',
      tom: 'perigo',
    });
    if (!ok) return;
    try {
      const r = await rpc('admin_pauta_remover', { p_id: id });
      if (r && r.ok === false) throw new Error(r.erro);
      toast('pauta apagada');
      await abrirQuadro(corpo);
    } catch (e) {
      toast(e.message, 'erro');
    }
    return;
  }

  const recolher = alvo('[data-recolher]');
  if (recolher) {
    const id = recolher.dataset.recolher;
    const g = (estadoQuadro.dados?.grupos || []).find((x) => x.id === id);
    if (!g) return;
    try {
      await rpc('admin_grupo_recolher', { p_id: id, p_recolhido: !g.recolhido });
      g.recolhido = !g.recolhido;
      desenharQuadro(corpo);
    } catch (e) {
      toast(e.message, 'erro');
    }
    return;
  }

  if (alvo('[data-novo-grupo]')) return salvarGrupo(corpo, null);
  const editarGrupo = alvo('[data-editar-grupo]');
  if (editarGrupo) return salvarGrupo(corpo, editarGrupo.dataset.editarGrupo);

  const apagarGrupo = alvo('[data-apagar-grupo]');
  if (apagarGrupo) {
    const ok = await confirmar({
      titulo: `apagar o grupo "${apagarGrupo.dataset.nome}"?`,
      texto: 'o grupo precisa estar vazio. as pautas dentro dele não somem junto.',
      ok: 'apagar',
      tom: 'perigo',
    });
    if (!ok) return;
    try {
      const r = await rpc('admin_grupo_remover', { p_id: apagarGrupo.dataset.apagarGrupo });
      if (r && r.ok === false) throw new Error(r.erro);
      toast('grupo apagado');
      await abrirQuadro(corpo);
    } catch (e) {
      toast(e.message, 'erro');
    }
    return;
  }

  if (alvo('[data-editar-quadro]')) return salvarQuadro(corpo, estadoQuadro.quadroId);
  if (alvo('[data-arquivar-quadro]')) {
    try {
      await rpc('admin_quadro_arquivar', { p_id: estadoQuadro.quadroId, p_arquivar: true });
      toast('quadro arquivado');
      estadoQuadro.quadroId = null;
      await carregarQuadros($('[data-quadros]'), corpo);
    } catch (e) {
      toast(e.message, 'erro');
    }
    return;
  }
  if (alvo('[data-apagar-quadro]')) {
    const nome = estadoQuadro.dados?.quadro?.nome || 'esse quadro';
    const ok = await confirmar({
      titulo: `apagar o quadro "${nome}"?`,
      texto: 'só dá se ele estiver vazio. se ainda tem pauta dentro, arquiva em vez de apagar.',
      ok: 'apagar',
      tom: 'perigo',
    });
    if (!ok) return;
    try {
      const r = await rpc('admin_quadro_remover', { p_id: estadoQuadro.quadroId });
      if (r && r.ok === false) throw new Error(r.erro);
      toast('quadro apagado');
      estadoQuadro.quadroId = null;
      await carregarQuadros($('[data-quadros]'), corpo);
    } catch (e) {
      toast(e.message, 'erro');
    }
  }
}

// A linha "+ pauta" no pé de cada grupo: escreve o título e dá enter.
async function aoSubmeterNoQuadro(ev, corpo) {
  const form = ev.target.closest('[data-nova-pauta]');
  if (!form) return;
  ev.preventDefault();
  const campo = $('input', form);
  const titulo = campo.value.trim();
  if (!titulo) return;
  campo.disabled = true;
  try {
    const r = await rpc('admin_pauta_salvar', {
      p_id: null,
      p_quadro_id: estadoQuadro.quadroId,
      p_grupo_id: form.dataset.novaPauta || null,
      p_titulo: titulo,
      p_briefing: null,
      p_atribuido_a: null,
      p_prazo: null,
      p_prioridade: 'normal',
    });
    if (r && r.ok === false) throw new Error(r.erro);
    campo.value = '';
    await abrirQuadro(corpo);
    // Devolve o foco pra a mesma linha: quem escreve uma pauta quase sempre
    // escreve a próxima em seguida.
    $(`[data-nova-pauta="${CSS.escape(form.dataset.novaPauta)}"] input`)?.focus();
  } catch (e) {
    toast(e.message, 'erro');
    campo.disabled = false;
  }
}

async function aoTocarNosQuadros(ev, barra, corpo) {
  const chip = ev.target.closest('[data-abrir-quadro]');
  if (chip) {
    estadoQuadro.quadroId = chip.dataset.abrirQuadro;
    return abrirQuadro(corpo);
  }
  if (ev.target.closest('[data-novo-quadro]')) return salvarQuadro(corpo, null);
  if (ev.target.closest('[data-ver-arquivados]')) {
    const arquivados = estadoQuadro.quadros.filter((q) => q.arquivado);
    const escolha = await escolher({
      titulo: 'quadros arquivados',
      opcoes: arquivados.map((q) => ({ valor: q.id, rotulo: q.nome, cor: q.cor })),
      atual: null,
    });
    if (!escolha) return;
    try {
      await rpc('admin_quadro_arquivar', { p_id: escolha, p_arquivar: false });
      estadoQuadro.quadroId = escolha;
      toast('quadro de volta 💛');
      await carregarQuadros(barra, corpo);
    } catch (e) {
      toast(e.message, 'erro');
    }
  }
}

// ---------------------------------------------------------------------------
// Os pedidos de valor (a folhinha de opções de cada célula)
// ---------------------------------------------------------------------------
async function pedirValorDaCelula(campo, p) {
  if (campo === 'status') {
    return escolher({
      titulo: 'como está essa pauta?',
      opcoes: ESTADOS_PAUTA.map((e) => ({ valor: e.slug, rotulo: e.rotulo, cor: e.cor })),
      atual: p.status,
    });
  }
  if (campo === 'prioridade') {
    return escolher({
      titulo: 'qual a urgência?',
      opcoes: PRIORIDADES.map((e) => ({ valor: e.slug, rotulo: e.rotulo, cor: e.cor })),
      atual: p.prioridade,
    });
  }
  if (campo === 'atribuido_a') {
    return escolher({
      titulo: 'pra quem é essa pauta?',
      opcoes: [
        { valor: '', rotulo: 'toda a equipe' },
        ...equipeDasPautas.map((g) => ({ valor: g.id, rotulo: g.nome, inicial: iniciais(g.nome) })),
      ],
      atual: p.atribuido_a || '',
    });
  }
  if (campo === 'prazo') {
    // No balcão ninguém digita 20/08. Os atalhos resolvem quase sempre, e o
    // campo de data fica pro caso que eles não cobrem.
    return escolher({
      titulo: 'até quando?',
      opcoes: [
        { valor: hojeISO(), rotulo: 'hoje' },
        { valor: maisDias(1), rotulo: 'amanhã' },
        { valor: maisDias(7), rotulo: 'daqui uma semana' },
        { valor: '', rotulo: 'sem prazo' },
      ],
      atual: p.prazo ? String(p.prazo).slice(0, 10) : '',
      rodape: `<form class="pauta-data-livre">
                 <label for="pauta-data" class="lbl">ou escolhe o dia</label>
                 <div class="pauta-data-linha">
                   <input id="pauta-data" type="date" data-data-livre value="${escapeHtml(p.prazo ? String(p.prazo).slice(0, 10) : '')}" />
                   <button type="submit" class="btn solid sm">usar</button>
                 </div>
               </form>`,
    });
  }
  return null;
}

function aplicarNoEstado(p, campo, valor) {
  if (campo === 'atribuido_a') {
    p.atribuido_a = valor || null;
    p.atribuido_nome = valor ? equipeDasPautas.find((g) => g.id === valor)?.nome || '' : '';
  } else if (campo === 'prazo') {
    p.prazo = valor || null;
  } else if (campo === 'grupo_id') {
    p.grupo_id = valor || null;
  } else {
    p[campo] = valor;
  }
}

// ---------------------------------------------------------------------------
// Quadro e grupo: criar e renomear
// ---------------------------------------------------------------------------
async function salvarQuadro(corpo, id) {
  const atual = id ? estadoQuadro.quadros.find((q) => q.id === id) : null;
  const nome = window.prompt(id ? 'novo nome do quadro' : 'nome do quadro novo', atual?.nome || '');
  if (nome === null) return;
  const cor = await escolher({
    titulo: 'a cor do quadro',
    opcoes: CORES_QUADRO.map((c) => ({ valor: c.slug, rotulo: c.rotulo, cor: c.slug })),
    atual: atual?.cor || 'coral',
  });
  if (cor === null) return;
  try {
    const r = await rpc('admin_quadro_salvar', { p_id: id, p_nome: nome.trim(), p_cor: cor });
    if (r && r.ok === false) throw new Error(r.erro);
    if (!id) estadoQuadro.quadroId = r.id;
    toast(id ? 'quadro salvo 💛' : 'quadro criado 💛');
    await carregarQuadros($('[data-quadros]'), corpo);
  } catch (e) {
    toast(e.message, 'erro');
  }
}

async function salvarGrupo(corpo, id) {
  const atual = id ? (estadoQuadro.dados?.grupos || []).find((g) => g.id === id) : null;
  const nome = window.prompt(id ? 'novo nome do grupo' : 'nome do grupo novo', atual?.nome || '');
  if (nome === null) return;
  const cor = await escolher({
    titulo: 'a cor do grupo',
    opcoes: CORES_QUADRO.map((c) => ({ valor: c.slug, rotulo: c.rotulo, cor: c.slug })),
    atual: atual?.cor || 'neutro',
  });
  if (cor === null) return;
  try {
    const r = await rpc('admin_grupo_salvar', {
      p_id: id,
      p_quadro_id: estadoQuadro.quadroId,
      p_nome: nome.trim(),
      p_cor: cor,
    });
    if (r && r.ok === false) throw new Error(r.erro);
    toast(id ? 'grupo salvo 💛' : 'grupo criado 💛');
    await abrirQuadro(corpo);
  } catch (e) {
    toast(e.message, 'erro');
  }
}

// ---------------------------------------------------------------------------
// O painel da pauta: briefing, dados e a conversa.
// ---------------------------------------------------------------------------
async function abrirPainelDaPauta(id, corpo) {
  const fundo = document.createElement('div');
  fundo.className = 'pauta-painel-fundo';
  fundo.innerHTML = `<aside class="pauta-painel" role="dialog" aria-modal="true" aria-label="a pauta">
    <div class="ad-carregando">abrindo a pauta…</div>
  </aside>`;
  const fechar = () => {
    document.removeEventListener('keydown', aoTeclar);
    fundo.remove();
  };
  const aoTeclar = (e) => {
    if (e.key === 'Escape') fechar();
  };
  fundo.addEventListener('click', (e) => {
    if (e.target === fundo || e.target.closest('[data-fechar-painel]')) fechar();
  });
  document.addEventListener('keydown', aoTeclar);
  document.body.appendChild(fundo);

  const painel = $('.pauta-painel', fundo);
  let dados;
  try {
    dados = await rpc('admin_pauta_ver', { p_id: id });
    if (!dados || dados.ok === false) throw new Error(dados?.erro || 'não achei essa pauta');
  } catch (e) {
    painel.innerHTML = `<div class="notice err"><p>${escapeHtml(e.message)}</p></div>`;
    return;
  }

  const desenhar = () => {
    const p = dados.pauta;
    const est = acheEstado(p.status);
    painel.innerHTML = `
      <header class="pauta-painel-topo">
        <span class="tag ${escapeHtml(est.cor)}">${escapeHtml(est.rotulo)}</span>
        <button type="button" class="btn ghost sm pauta-ico" data-fechar-painel aria-label="fechar"><i data-lucide="x"></i></button>
      </header>
      <h2 class="title sm pauta-painel-titulo">${escapeHtml(p.titulo || '')}</h2>
      <p class="pauta-painel-sub">${escapeHtml(p.grupo_nome || 'sem grupo')} · escrita por ${escapeHtml(p.criado_por_nome || 'alguém da equipe')}</p>

      <div class="pauta-painel-campos">
        <div><span class="lbl">pra quem</span><p>${escapeHtml(p.atribuido_a ? p.atribuido_nome || 'alguém' : 'toda a equipe')}</p></div>
        <div><span class="lbl">até quando</span><p>${p.prazo ? escapeHtml(dataDoPrazo(p.prazo)) : 'sem prazo'}</p></div>
        <div><span class="lbl">urgência</span><p>${escapeHtml(achePrioridade(p.prioridade).rotulo)}</p></div>
      </div>

      <div class="field">
        <label for="painel-briefing">o briefing</label>
        <textarea id="painel-briefing" rows="5" maxlength="4000" data-painel-briefing
          placeholder="o que precisa ser feito, onde, e o que fazer se der ruim.">${escapeHtml(p.briefing || '')}</textarea>
        <div class="ad-card-acoes">
          <button type="button" class="btn solid sm" data-salvar-briefing>salvar o briefing</button>
        </div>
      </div>

      <div class="pauta-conversa">
        <p class="lbl">a conversa dessa pauta</p>
        ${
          dados.comentarios.length
            ? dados.comentarios
                .map(
                  (c) => `
          <article class="pauta-coment" data-coment="${escapeHtml(c.id)}">
            <p class="pauta-coment-quem"><span class="pauta-avatar">${escapeHtml(iniciais(c.autor_nome))}</span>${escapeHtml(c.autor_nome)}<span class="pauta-coment-quando">${escapeHtml(formatData(c.created_at))}</span></p>
            <p class="pauta-coment-txt">${escapeHtml(c.texto)}</p>
            <button type="button" class="pauta-coment-apagar" data-apagar-coment="${escapeHtml(c.id)}">apagar</button>
          </article>`,
                )
                .join('')
            : '<p class="pauta-col-vazia">ninguém escreveu nada ainda.</p>'
        }
        <form class="pauta-coment-form" data-form-coment>
          <label for="painel-coment" class="sr-only">escrever na conversa</label>
          <input id="painel-coment" class="inp" type="text" maxlength="2000" placeholder="escreve aqui o que aconteceu" autocomplete="off" />
          <button type="submit" class="btn solid sm">mandar</button>
        </form>
      </div>`;
    renderIcons();
  };

  desenhar();

  painel.addEventListener('click', async (ev) => {
    if (ev.target.closest('[data-salvar-briefing]')) {
      const texto = $('[data-painel-briefing]', painel).value;
      try {
        const r = await rpc('admin_pauta_salvar', {
          p_id: dados.pauta.id,
          p_quadro_id: dados.pauta.quadro_id,
          p_grupo_id: dados.pauta.grupo_id,
          p_titulo: dados.pauta.titulo,
          p_briefing: texto || null,
          p_atribuido_a: dados.pauta.atribuido_a,
          p_prazo: dados.pauta.prazo,
          p_prioridade: dados.pauta.prioridade,
        });
        if (r && r.ok === false) throw new Error(r.erro);
        dados.pauta.briefing = texto || null;
        const naTela = itemPorId(dados.pauta.id);
        if (naTela) {
          naTela.briefing = dados.pauta.briefing;
          redesenharLinha(dados.pauta.id);
        }
        toast('briefing salvo 💛');
      } catch (e) {
        toast(e.message, 'erro');
      }
      return;
    }
    const apagar = ev.target.closest('[data-apagar-coment]');
    if (apagar) {
      try {
        const r = await rpc('admin_pauta_comentario_remover', { p_id: apagar.dataset.apagarComent });
        if (r && r.ok === false) throw new Error(r.erro);
        dados.comentarios = dados.comentarios.filter((c) => c.id !== apagar.dataset.apagarComent);
        const naTela = itemPorId(dados.pauta.id);
        if (naTela) {
          naTela.comentarios = dados.comentarios.length;
          redesenharLinha(dados.pauta.id);
        }
        desenhar();
      } catch (e) {
        toast(e.message, 'erro');
      }
    }
  });

  painel.addEventListener('submit', async (ev) => {
    if (!ev.target.closest('[data-form-coment]')) return;
    ev.preventDefault();
    const campo = $('#painel-coment', painel);
    const texto = campo.value.trim();
    if (!texto) return;
    campo.disabled = true;
    try {
      const r = await rpc('admin_pauta_comentar', { p_pauta_id: dados.pauta.id, p_texto: texto });
      if (r && r.ok === false) throw new Error(r.erro);
      dados = await rpc('admin_pauta_ver', { p_id: dados.pauta.id });
      const naTela = itemPorId(dados.pauta.id);
      if (naTela) {
        naTela.comentarios = dados.comentarios.length;
        redesenharLinha(dados.pauta.id);
      }
      desenhar();
      $('#painel-coment', painel)?.focus();
    } catch (e) {
      toast(e.message, 'erro');
      campo.disabled = false;
    }
  });
}

// ===== PEDIDOS ======================================================
const filtrosPedidos = { status: 'abertos', modo: null };

async function viewPedidos(view) {
  view.innerHTML =
    cabecalho(
      'pedidos da loja',
      'o que a galera comprou pelo site.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    `<div class="ad-filtros" role="group" aria-label="filtrar pedidos">
      <button type="button" class="filtro" data-f-status="abertos">abertos</button>
      <button type="button" class="filtro" data-f-status="entregue">entregues</button>
      <button type="button" class="filtro" data-f-status="cancelado">cancelados</button>
      <button type="button" class="filtro" data-f-status="">todos</button>
      <span class="ad-filtros-divisor" aria-hidden="true"></span>
      <button type="button" class="filtro" data-f-modo="">entrega e retirada</button>
      <button type="button" class="filtro" data-f-modo="entrega">só entrega</button>
      <button type="button" class="filtro" data-f-modo="retirada">só retirada</button>
    </div>
    <div data-corpo></div>`;

  const corpo = $('[data-corpo]', view);
  const marcar = () => {
    $$('[data-f-status]', view).forEach((b) =>
      b.setAttribute('aria-pressed', String((b.dataset.fStatus || null) === filtrosPedidos.status)),
    );
    $$('[data-f-modo]', view).forEach((b) =>
      b.setAttribute('aria-pressed', String((b.dataset.fModo || null) === filtrosPedidos.modo)),
    );
  };
  $$('[data-f-status]', view).forEach((b) =>
    b.addEventListener('click', () => {
      filtrosPedidos.status = b.dataset.fStatus || null;
      marcar();
      carregarPedidos(corpo);
    }),
  );
  $$('[data-f-modo]', view).forEach((b) =>
    b.addEventListener('click', () => {
      filtrosPedidos.modo = b.dataset.fModo || null;
      marcar();
      carregarPedidos(corpo);
    }),
  );
  $('[data-recarregar]', view).addEventListener('click', () => carregarPedidos(corpo));
  marcar();
  renderIcons();
  carregarPedidos(corpo);
}

async function carregarPedidos(corpo) {
  carregando(corpo);
  try {
    const linhas = await rpc('admin_pedidos', {
      p_status: filtrosPedidos.status,
      p_modo: filtrosPedidos.modo,
      p_limite: 200,
    });
    if (!linhas || !linhas.length) {
      corpo.innerHTML = vazio('nenhum pedido por aqui', 'quando alguém comprar, aparece nesta lista.');
      return;
    }
    corpo.innerHTML = `<div class="ad-lista">${linhas.map(cardPedido).join('')}</div>`;
    renderIcons();
    $$('[data-baixa]', corpo).forEach((botao) => {
      botao.addEventListener('click', () => darBaixaPedido(botao, corpo));
    });
    $$('[data-pedido-arrumar]', corpo).forEach((botao) => {
      botao.addEventListener('click', () => arrumarPedido(botao, corpo));
    });
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

function tagStatusPedido(status) {
  const mapa = {
    pendente: ['gold', 'esperando pagamento'],
    pago: ['green', 'pago'],
    preparando: ['blue', 'preparando'],
    pronto: ['olive', 'pronto'],
    entregue: ['', 'entregue'],
    cancelado: ['coral', 'cancelado'],
  };
  const [cor, rotulo] = mapa[status] || ['', status || '—'];
  return `<span class="tag ${cor}">${escapeHtml(rotulo)}</span>`;
}

function enderecoDoPedido(p) {
  const linha1 = [p.entrega_rua, p.entrega_numero].filter(Boolean).join(', ');
  const linha2 = [p.entrega_bairro, p.entrega_cidade, p.entrega_uf].filter(Boolean).join(' · ');
  const partes = [linha1, p.entrega_complemento, linha2, p.entrega_cep].filter(Boolean);
  return partes.length ? partes.map((t) => escapeHtml(t)).join('<br />') : '';
}

function cardPedido(p) {
  const modo = p.modo_entrega === 'retirada' ? 'retirada' : 'entrega';
  const itens = Array.isArray(p.itens) ? p.itens : [];
  const aberto = ['pago', 'preparando', 'pronto'].includes(p.status);
  const podeBaixar = aberto && pode('pedidos.mexer');
  // Arrumar é pra quando a fila passou a mentir: baixa dada no pedido errado,
  // pedido que voltou pro forno. 'pendente' e 'estornado' não entram, ali quem
  // manda é o gateway (o banco recusa também, isto aqui é pra não oferecer).
  const podeArrumar = pode('pedidos.arrumar') && !['pendente', 'estornado'].includes(p.status);
  const endereco = modo === 'entrega' ? enderecoDoPedido(p) : '';

  return `
    <article class="card ad-card">
      <div class="ad-card-topo">
        <div>
          <p class="ad-ref">#${escapeHtml(refCurta(p.id))}</p>
          <p class="ad-card-nome">${escapeHtml(p.cliente_nome || 'sem nome')}</p>
          <p class="ad-card-meta">${escapeHtml(p.cliente_email || '')}${p.cliente_telefone ? ' · ' + escapeHtml(p.cliente_telefone) : ''}</p>
        </div>
        <div class="ad-card-tags">
          ${tagStatusPedido(p.status)}
          <span class="tag ${modo === 'retirada' ? 'olive' : 'blue'}"><i data-lucide="${modo === 'retirada' ? 'store' : 'truck'}"></i>${modo}</span>
        </div>
      </div>

      <div class="rows">
        ${itens
          .map(
            (i) => `
          <div class="row">
            <div class="row-main">
              <span>${escapeHtml(i.nome || 'item')}</span>
              ${i.variante ? `<span class="row-meta">${escapeHtml(i.variante)}</span>` : ''}
            </div>
            <span class="row-meta">${formatNumero(i.qtd)}×</span>
            <span class="row-val">${formatBRL(i.preco_centavos)}</span>
          </div>`,
          )
          .join('')}
      </div>

      <div class="ad-card-rodape">
        <div class="ad-card-info">
          <p class="ad-card-meta">${escapeHtml(formatData(p.criado_em))}</p>
          ${
            Number(p.desconto_centavos) > 0
              ? `<p class="ad-card-meta">desconto do plano ${escapeHtml(p.tier_slug || '')}: −${formatBRL(p.desconto_centavos)}</p>`
              : ''
          }
          ${endereco ? `<p class="ad-endereco">${endereco}</p>` : ''}
          ${
            p.entregue_em
              ? `<p class="ad-card-meta ok"><i data-lucide="check"></i> ${modo === 'retirada' ? 'retirado' : 'entregue'} em ${escapeHtml(formatData(p.entregue_em))}${p.entregue_por_nome ? ' por ' + escapeHtml(p.entregue_por_nome) : ''}</p>`
              : ''
          }
        </div>
        <div class="ad-card-acao">
          <p class="ad-total">${formatBRL(p.total_centavos)}</p>
          ${
            podeBaixar
              ? `<button type="button" class="btn solid sm" data-baixa="${escapeHtml(p.id)}" data-modo="${modo}">
                   <i data-lucide="check"></i>${modo === 'retirada' ? 'confirmar retirada' : 'confirmar entrega'}
                 </button>`
              : ''
          }
          ${
            podeArrumar
              ? `<button type="button" class="btn ghost sm" data-pedido-arrumar="${escapeHtml(p.id)}" data-status="${escapeHtml(p.status || '')}">
                   <i data-lucide="wrench"></i>arrumar
                 </button>`
              : ''
          }
        </div>
      </div>
    </article>`;
}

async function darBaixaPedido(botao, corpo) {
  const id = botao.dataset.baixa;
  const modo = botao.dataset.modo;
  const ok = await confirmar({
    titulo: modo === 'retirada' ? 'a pessoa levou o pedido?' : 'o pedido saiu pra entrega?',
    texto:
      modo === 'retirada'
        ? 'isso marca o pedido como retirado no balcão. não dá pra desfazer por aqui.'
        : 'isso marca o pedido como entregue. não dá pra desfazer por aqui.',
    ok: 'sim, confirmar',
  });
  if (!ok) return;

  botao.disabled = true;
  try {
    const r = await rpc('admin_marcar_entregue', { p_order_id: id });
    if (r?.ok === false) {
      toast(r.erro || 'não deu pra dar baixa nesse pedido', 'erro');
      botao.disabled = false;
      return;
    }
    toast(r?.ja_estava ? 'esse já estava dado como entregue' : 'pronto, baixa confirmada 💛');
    carregarPedidos(corpo);
  } catch (e) {
    toast(e.message, 'erro');
    botao.disabled = false;
  }
}

// Arrumar o estado do pedido na mão (permissão `pedidos.arrumar`). Existe porque
// a baixa da 0017 era só de ida: marcou entregue no pedido errado e a fila
// mentia pra sempre. Cancelar aqui tira da fila e não devolve dinheiro nenhum,
// e a folhinha diz isso na cara.
const ESTADOS_PEDIDO = [
  { valor: 'pago', rotulo: 'pago, ainda não começou' },
  { valor: 'preparando', rotulo: 'preparando' },
  { valor: 'pronto', rotulo: 'pronto, esperando sair' },
  { valor: 'entregue', rotulo: 'entregue ou retirado' },
  { valor: 'cancelado', rotulo: 'cancelado' },
];

async function arrumarPedido(botao, corpo) {
  const id = botao.dataset.pedidoArrumar;
  const novo = await escolher({
    titulo: 'em que pé está esse pedido?',
    opcoes: ESTADOS_PEDIDO,
    atual: botao.dataset.status,
    rodape: '<p class="ad-dica">isso muda só a fila daqui. devolver o dinheiro de um pedido pago continua sendo no Asaas.</p>',
  });
  if (!novo || novo === botao.dataset.status) return;

  botao.disabled = true;
  try {
    const r = await rpc('admin_pedido_status', { p_order_id: id, p_status: novo });
    if (r?.ok === false) {
      toast(r.erro || 'não deu pra arrumar esse pedido', 'erro');
      botao.disabled = false;
      return;
    }
    toast('pronto, pedido arrumado 💛');
    carregarPedidos(corpo);
  } catch (e) {
    toast(e.message, 'erro');
    botao.disabled = false;
  }
}

// ===== RESGATES =====================================================
const filtrosResgates = { status: 'abertos' };

async function viewResgates(view) {
  view.innerHTML =
    cabecalho(
      'recompensas resgatadas',
      'o que saiu por pontos e ainda precisa chegar na mão de alguém.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    `<div class="ad-filtros" role="group" aria-label="filtrar resgates">
      <button type="button" class="filtro" data-f-status="abertos">a entregar</button>
      <button type="button" class="filtro" data-f-status="usado">já entregues</button>
      <button type="button" class="filtro" data-f-status="">todos</button>
    </div>
    <div data-corpo></div>`;

  const corpo = $('[data-corpo]', view);
  const marcar = () =>
    $$('[data-f-status]', view).forEach((b) =>
      b.setAttribute('aria-pressed', String((b.dataset.fStatus || null) === filtrosResgates.status)),
    );
  $$('[data-f-status]', view).forEach((b) =>
    b.addEventListener('click', () => {
      filtrosResgates.status = b.dataset.fStatus || null;
      marcar();
      carregarResgates(corpo);
    }),
  );
  $('[data-recarregar]', view).addEventListener('click', () => carregarResgates(corpo));
  marcar();
  renderIcons();
  carregarResgates(corpo);
}

async function carregarResgates(corpo) {
  carregando(corpo);
  try {
    const linhas = await rpc('admin_resgates', {
      p_status: filtrosResgates.status,
      p_limite: 200,
    });
    if (!linhas || !linhas.length) {
      corpo.innerHTML = vazio('nada resgatado por aqui', 'quando alguém trocar pontos por algo, aparece nesta lista.');
      return;
    }
    corpo.innerHTML = `<div class="ad-lista">${linhas.map(cardResgate).join('')}</div>`;
    renderIcons();
    $$('[data-usado]', corpo).forEach((botao) => {
      botao.addEventListener('click', () => darBaixaResgate(botao, corpo));
    });
    $$('[data-resgate-desfazer]', corpo).forEach((botao) => {
      botao.addEventListener('click', () => desfazerResgate(botao, corpo));
    });
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

function cardResgate(r) {
  const aberto = ['solicitado', 'aprovado'].includes(r.status);
  const podeBaixar = aberto && pode('resgates.mexer');
  // Desfazer devolve os pontos. Até a 0047 não existia jeito nenhum: o ledger é
  // append-only, então resgate clicado sem querer custava os pontos pra sempre.
  const podeDesfazer = r.status !== 'cancelado' && pode('resgates.arrumar');
  return `
    <article class="card ad-card">
      <div class="ad-card-topo">
        <div>
          <p class="ad-ref">#${escapeHtml(refCurta(r.id))}</p>
          <p class="ad-card-nome">${escapeHtml(r.recompensa || 'recompensa')}</p>
          <p class="ad-card-meta">${escapeHtml(r.cliente_nome || 'sem nome')}${r.cliente_email ? ' · ' + escapeHtml(r.cliente_email) : ''}</p>
        </div>
        <div class="ad-card-tags">
          <span class="tag ${aberto ? 'gold' : ''}">${escapeHtml(aberto ? 'a entregar' : r.status || '—')}</span>
          ${r.tipo ? `<span class="tag olive">${escapeHtml(r.tipo)}</span>` : ''}
        </div>
      </div>
      <div class="ad-card-rodape">
        <div class="ad-card-info">
          <p class="ad-card-meta">pedido em ${escapeHtml(formatData(r.criado_em))}</p>
          ${r.codigo ? `<p class="ad-codigo">${escapeHtml(r.codigo)}</p>` : ''}
          ${
            r.usado_em
              ? `<p class="ad-card-meta ok"><i data-lucide="check"></i> entregue em ${escapeHtml(formatData(r.usado_em))}${r.usado_por_nome ? ' por ' + escapeHtml(r.usado_por_nome) : ''}</p>`
              : ''
          }
        </div>
        <div class="ad-card-acao">
          <p class="ad-total">${formatNumero(r.pontos_gastos)} pts</p>
          ${
            podeBaixar
              ? `<button type="button" class="btn solid sm" data-usado="${escapeHtml(r.id)}"><i data-lucide="check"></i>entreguei</button>`
              : ''
          }
          ${
            podeDesfazer
              ? `<button type="button" class="btn ghost sm" data-resgate-desfazer="${escapeHtml(r.id)}" data-pontos="${escapeHtml(String(r.pontos_gastos || 0))}">
                   <i data-lucide="undo-2"></i>desfazer e devolver
                 </button>`
              : ''
          }
        </div>
      </div>
    </article>`;
}

async function darBaixaResgate(botao, corpo) {
  const ok = await confirmar({
    titulo: 'a recompensa foi pra mão da pessoa?',
    texto: 'isso marca o resgate como entregue. não dá pra desfazer por aqui.',
    ok: 'sim, entreguei',
  });
  if (!ok) return;
  botao.disabled = true;
  try {
    const r = await rpc('admin_marcar_resgate_usado', { p_redemption_id: botao.dataset.usado });
    if (r?.ok === false) {
      toast(r.erro || 'não deu pra dar baixa nesse resgate', 'erro');
      botao.disabled = false;
      return;
    }
    toast(r?.ja_estava ? 'esse já estava entregue' : 'pronto, resgate entregue 💛');
    carregarResgates(corpo);
  } catch (e) {
    toast(e.message, 'erro');
    botao.disabled = false;
  }
}

async function desfazerResgate(botao, corpo) {
  const pontos = formatNumero(botao.dataset.pontos || 0);
  const ok = await confirmar({
    titulo: 'desfazer esse resgate?',
    texto: `os ${pontos} pontos voltam pro saldo da pessoa, a recompensa volta pro estoque e o cupom, se tinha um, sai de circulação. tudo isso fica registrado.`,
    ok: 'sim, devolver os pontos',
    tom: 'perigo',
  });
  if (!ok) return;
  botao.disabled = true;
  try {
    const r = await rpc('admin_resgate_desfazer', {
      p_redemption_id: botao.dataset.resgateDesfazer,
      p_motivo: null,
    });
    if (r?.ok === false) {
      toast(r.erro || 'não deu pra desfazer esse resgate', 'erro');
      botao.disabled = false;
      return;
    }
    toast(r?.ja_estava ? 'esse resgate já estava desfeito' : `pronto, ${formatNumero(r?.devolvidos || 0)} pontos de volta 💛`);
    carregarResgates(corpo);
  } catch (e) {
    toast(e.message, 'erro');
    botao.disabled = false;
  }
}

// ===== ANIVERSÁRIOS (brunch) ========================================
// O brunch de aniversário que a pessoa reservou no /conta/perfil. Aqui o balcão
// confere o código e dá baixa. Trava por `tem_permissao('resgates')` no banco
// (0025) — aqui é só a tela. Um brunch por pessoa por ano.
const filtrosBrindes = { status: 'ativo', busca: '', tipo: '' };

async function viewAniversarios(view) {
  view.innerHTML =
    cabecalho(
      'brunches do Casa',
      'os brunches reservados, o platter do mês e o de aniversário. confere o código de quem chega e dá a baixa.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    `<form class="ad-busca" data-busca>
      <div class="field">
        <label for="busca-brinde" class="sr-only">buscar por código ou nome</label>
        <input id="busca-brinde" type="search" placeholder="código (CASA-XXXXXX) ou nome" autocomplete="off" spellcheck="false" />
      </div>
      <button type="submit" class="btn ghost sm"><i data-lucide="search"></i>buscar</button>
    </form>
    <div class="ad-filtros" role="group" aria-label="filtrar brunches">
      <button type="button" class="filtro" data-f-status="ativo">a validar</button>
      <button type="button" class="filtro" data-f-status="usado">já usados</button>
      <button type="button" class="filtro" data-f-status="expirado">vencidos</button>
      <button type="button" class="filtro" data-f-status="">todos</button>
    </div>
    <div class="ad-filtros" role="group" aria-label="filtrar por tipo de brunch">
      <button type="button" class="filtro" data-f-tipo="">os dois</button>
      <button type="button" class="filtro" data-f-tipo="mensal">do mês</button>
      <button type="button" class="filtro" data-f-tipo="aniversario">de aniversário</button>
    </div>
    <div data-corpo></div>`;

  const corpo = $('[data-corpo]', view);
  const form = $('[data-busca]', view);
  const marcar = () => {
    $$('[data-f-status]', view).forEach((b) =>
      b.setAttribute('aria-pressed', String((b.dataset.fStatus || '') === filtrosBrindes.status)),
    );
    $$('[data-f-tipo]', view).forEach((b) =>
      b.setAttribute('aria-pressed', String((b.dataset.fTipo || '') === filtrosBrindes.tipo)),
    );
  };
  $$('[data-f-status]', view).forEach((b) =>
    b.addEventListener('click', () => {
      filtrosBrindes.status = b.dataset.fStatus || '';
      marcar();
      carregarBrindes(corpo);
    }),
  );
  $$('[data-f-tipo]', view).forEach((b) =>
    b.addEventListener('click', () => {
      filtrosBrindes.tipo = b.dataset.fTipo || '';
      marcar();
      carregarBrindes(corpo);
    }),
  );
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    filtrosBrindes.busca = $('#busca-brinde', form).value.trim();
    carregarBrindes(corpo);
  });
  $('[data-recarregar]', view).addEventListener('click', () => carregarBrindes(corpo));
  marcar();
  renderIcons();
  carregarBrindes(corpo);
}

async function carregarBrindes(corpo) {
  carregando(corpo);
  try {
    // A `admin_brunches_listar` (0050) devolve jsonb com os DOIS tipos numa lista
    // só. É jsonb e não `returns table` pela lição da 0042: leitura composta com
    // uma dúzia de colunas é onde varchar declarado como text derruba a função
    // inteira, e só na primeira chamada.
    const resp = await rpc('admin_brunches_listar', {
      p_busca: filtrosBrindes.busca || null,
      p_status: filtrosBrindes.status || null,
      p_tipo: filtrosBrindes.tipo || null,
      p_limite: 200,
    });
    const linhas = Array.isArray(resp?.itens) ? resp.itens : [];
    if (!linhas.length) {
      corpo.innerHTML = vazio(
        'nenhum brunch por aqui',
        'quando alguém reservar o platter do mês ou o brunch de aniversário, o código aparece nesta lista.',
      );
      return;
    }
    corpo.innerHTML = `<div class="ad-lista">${linhas.map(cardBrinde).join('')}</div>`;
    renderIcons();
    $$('[data-brinde-usar]', corpo).forEach((botao) => {
      botao.addEventListener('click', () => darBaixaBrinde(botao, corpo));
    });
    $$('[data-brinde-arrumar]', corpo).forEach((botao) => {
      botao.addEventListener('click', () => arrumarBrinde(botao, corpo));
    });
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

function cardBrinde(b) {
  const ativo = b.situacao === 'ativo';
  const podeBaixar = ativo && pode('aniversarios.mexer');
  // Os dois consertos do brunch: a baixa dada no código errado, e a pessoa que
  // não conseguiu vir dentro dos 30 dias.
  const podeArrumar = pode('aniversarios.arrumar');
  const ehMensal = b.tipo === 'mensal';
  const tag =
    b.situacao === 'usado'
      ? '<span class="tag">usado</span>'
      : b.situacao === 'expirado'
        ? '<span class="tag">vencido</span>'
        : '<span class="tag gold">a validar</span>';
  // Quem está no balcão precisa saber QUAL brunch é antes de servir: o do mês
  // serve duas pessoas, o de aniversário é uma vez por ano.
  const tagTipo = ehMensal
    ? '<span class="tag coral">platter do mês</span>'
    : '<span class="tag green">aniversário</span>';
  return `
    <article class="card ad-card">
      <div class="ad-card-topo">
        <div>
          <p class="ad-codigo">${escapeHtml(b.codigo)}</p>
          <p class="ad-card-nome">${escapeHtml(b.cliente_nome || 'sem nome')}${b.cliente_email ? ' · ' + escapeHtml(b.cliente_email) : ''}</p>
        </div>
        <div class="ad-card-tags">${tagTipo}${tag}</div>
      </div>
      <div class="ad-card-rodape">
        <div class="ad-card-info">
          ${
            b.referencia
              ? `<p class="ad-card-meta">${ehMensal ? '🥐 brunch de ' : '🎂 faz aniversário em '}${escapeHtml(b.referencia)}${ehMensal ? ', serve duas pessoas' : ''}</p>`
              : ''
          }
          <p class="ad-card-meta">reservado em ${escapeHtml(formatData(b.criado_em))} · vale até ${escapeHtml(b.valido_ate_label || '—')}</p>
          ${
            b.usado_em
              ? `<p class="ad-card-meta ok"><i data-lucide="check"></i> brunch entregue em ${escapeHtml(formatData(b.usado_em))}${b.usado_por_nome ? ' por ' + escapeHtml(b.usado_por_nome) : ''}</p>`
              : ''
          }
        </div>
        <div class="ad-card-acao">
          ${
            podeBaixar
              ? `<button type="button" class="btn solid sm" data-brinde-usar="${escapeHtml(b.id)}" data-tipo="${escapeHtml(b.tipo)}"><i data-lucide="cake"></i>brunch entregue</button>`
              : ''
          }
          ${
            podeArrumar && b.situacao === 'usado'
              ? `<button type="button" class="btn ghost sm" data-brinde-arrumar="${escapeHtml(b.id)}" data-tipo="${escapeHtml(b.tipo)}" data-acao="desfazer"><i data-lucide="undo-2"></i>desfazer a baixa</button>`
              : ''
          }
          ${
            podeArrumar && b.situacao !== 'usado'
              ? `<button type="button" class="btn ghost sm" data-brinde-arrumar="${escapeHtml(b.id)}" data-tipo="${escapeHtml(b.tipo)}" data-acao="esticar"><i data-lucide="calendar-clock"></i>esticar 30 dias</button>`
              : ''
          }
        </div>
      </div>
    </article>`;
}

async function darBaixaBrinde(botao, corpo) {
  const ok = await confirmar({
    titulo: 'a pessoa aproveitou o brunch?',
    texto: 'isso marca o brunch como usado. quem tem "arrumar" consegue desfazer depois.',
    ok: 'sim, entregue',
  });
  if (!ok) return;
  botao.disabled = true;
  try {
    const r = await rpc('admin_brunch_usar', {
      p_tipo: botao.dataset.tipo,
      p_id: botao.dataset.brindeUsar,
    });
    if (r?.ok === false) {
      toast(r.erro || 'não deu pra dar baixa nesse brinde', 'erro');
      botao.disabled = false;
      return;
    }
    toast(r?.ja_estava ? 'esse brunch já estava dado como usado' : 'pronto, feliz aniversário 💛');
    carregarBrindes(corpo);
  } catch (e) {
    toast(e.message, 'erro');
    botao.disabled = false;
  }
}

async function arrumarBrinde(botao, corpo) {
  const acao = botao.dataset.acao;
  const ok = await confirmar({
    titulo: acao === 'desfazer' ? 'desfazer a baixa desse brunch?' : 'esticar a validade em 30 dias?',
    texto:
      acao === 'desfazer'
        ? 'o código volta a valer, como se a baixa não tivesse acontecido.'
        : 'o código ganha mais 30 dias a partir de hoje. serve pra quem não conseguiu vir a tempo.',
    ok: acao === 'desfazer' ? 'sim, desfazer' : 'sim, esticar',
  });
  if (!ok) return;
  botao.disabled = true;
  try {
    const r = await rpc('admin_brunch_arrumar', {
      p_tipo: botao.dataset.tipo,
      p_id: botao.dataset.brindeArrumar,
      p_acao: acao,
    });
    if (r?.ok === false) {
      toast(r.erro || 'não deu pra arrumar esse brunch', 'erro');
      botao.disabled = false;
      return;
    }
    toast(acao === 'desfazer' ? 'baixa desfeita, o código volta a valer' : `pronto, vale até ${r?.valido_ate || 'mais tarde'} 💛`);
    carregarBrindes(corpo);
  } catch (e) {
    toast(e.message, 'erro');
    botao.disabled = false;
  }
}

// ===== PESSOAS ======================================================
async function viewPessoas(view) {
  view.innerHTML =
    cabecalho('gente do Casa', 'quem já criou conta no site.') +
    `<form class="ad-busca" data-busca>
      <div class="field">
        <label for="busca-pessoa" class="sr-only">buscar por nome, e-mail ou telefone</label>
        <input id="busca-pessoa" type="search" placeholder="buscar por nome, e-mail ou telefone" autocomplete="off" />
      </div>
      <button type="submit" class="btn ghost sm"><i data-lucide="search"></i>buscar</button>
    </form>
    <div data-corpo></div>`;

  const corpo = $('[data-corpo]', view);
  const form = $('[data-busca]', view);
  renderIcons();
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    carregarPessoas(corpo, $('#busca-pessoa', form).value.trim());
  });
  carregarPessoas(corpo, '');
}

async function carregarPessoas(corpo, busca) {
  carregando(corpo);
  try {
    const linhas = await rpc('admin_usuarios', { p_busca: busca || null, p_limite: 200 });
    if (!linhas || !linhas.length) {
      corpo.innerHTML = vazio('ninguém por aqui', busca ? 'não achei ninguém com esse jeito de escrever.' : 'quando alguém criar conta, aparece aqui.');
      return;
    }
    corpo.innerHTML = `
      <div class="ad-tabela-wrap">
        <table class="ad-tabela">
          <thead>
            <tr>
              <th>pessoa</th><th>contato</th><th>plano</th>
              <th class="num">pontos</th><th class="num">pedidos</th><th class="num">gastou</th>
              <th>entrou</th><th>última vez</th>
            </tr>
          </thead>
          <tbody>
            ${linhas
              .map(
                (u) => `
              <tr>
                <td>
                  <span class="ad-td-forte">${escapeHtml(u.nome || 'sem nome')}</span>
                  ${u.master ? '<span class="tag gold">Casa</span>' : ''}
                  ${u.papel && u.papel !== 'cliente' ? `<span class="tag olive">${escapeHtml(ROTULO_PAPEL[u.papel] || u.papel)}</span>` : ''}
                </td>
                <td>
                  <span class="ad-td-meta">${escapeHtml(u.email || '')}</span>
                  ${u.telefone ? `<span class="ad-td-meta">${escapeHtml(u.telefone)}</span>` : ''}
                </td>
                <td>${u.plano ? `${escapeHtml(u.plano)}<span class="ad-td-meta">${escapeHtml(u.plano_status || '')}</span>` : '<span class="ad-td-meta">sem plano</span>'}</td>
                <td class="num">${formatNumero(u.pontos)}</td>
                <td class="num">${formatNumero(u.pedidos)}</td>
                <td class="num">${formatBRL(u.gasto_centavos)}</td>
                <td><span class="ad-td-meta">${escapeHtml(formatData(u.cadastrado_em, false))}</span></td>
                <td><span class="ad-td-meta">${escapeHtml(formatData(u.ultimo_acesso))}</span></td>
              </tr>`,
              )
              .join('')}
          </tbody>
        </table>
      </div>
      <p class="ad-rodape-nota">${formatNumero(linhas.length)} ${linhas.length === 1 ? 'pessoa' : 'pessoas'} nesta lista.</p>`;
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

// ===== RELATÓRIOS ===================================================
function isoInicio(v) {
  if (!v) return null;
  const d = new Date(`${v}T00:00:00`);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}
// O SQL compara com `<`, então "até" é a virada do dia seguinte.
function isoFim(v) {
  if (!v) return null;
  const d = new Date(`${v}T00:00:00`);
  if (Number.isNaN(d.getTime())) return null;
  d.setDate(d.getDate() + 1);
  return d.toISOString();
}
function dataInput(d) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

async function viewRelatorios(view) {
  const hoje = new Date();
  const trintaDias = new Date();
  trintaDias.setDate(trintaDias.getDate() - 29);

  view.innerHTML =
    cabecalho('relatórios', 'o que vendeu e o que saiu por pontos, no período que tu escolher.') +
    `<form class="ad-periodo" data-periodo>
      <div class="field">
        <label for="desde">de</label>
        <input id="desde" type="date" value="${dataInput(trintaDias)}" />
      </div>
      <div class="field">
        <label for="ate">até</label>
        <input id="ate" type="date" value="${dataInput(hoje)}" />
      </div>
      <button type="submit" class="btn ghost sm"><i data-lucide="refresh-cw"></i>atualizar</button>
    </form>
    <div data-corpo></div>`;

  const corpo = $('[data-corpo]', view);
  renderIcons();
  $('[data-periodo]', view).addEventListener('submit', (e) => {
    e.preventDefault();
    carregarRelatorios(corpo, $('#desde', view).value, $('#ate', view).value);
  });
  carregarRelatorios(corpo, dataInput(trintaDias), dataInput(hoje));
}

async function carregarRelatorios(corpo, desde, ate) {
  carregando(corpo, 'somando…');
  try {
    const params = { p_desde: isoInicio(desde), p_ate: isoFim(ate) };
    const [itens, resgates] = await Promise.all([
      rpc('admin_relatorio_itens', params),
      rpc('admin_relatorio_resgates', params),
    ]);

    const totalVendido = (itens || []).reduce((s, i) => s + Number(i.total_centavos || 0), 0);
    const totalPontos = (resgates || []).reduce((s, r) => s + Number(r.pontos || 0), 0);

    corpo.innerHTML = `
      <section class="ad-bloco">
        <div class="ad-bloco-head">
          <h2 class="title sm">o que vendeu</h2>
          <p class="ad-head-sub">${formatBRL(totalVendido)} no período</p>
        </div>
        ${
          itens && itens.length
            ? `<div class="ad-tabela-wrap">
                 <table class="ad-tabela">
                   <thead><tr><th>item</th><th>variante</th><th class="num">unidades</th><th class="num">pedidos</th><th class="num">total</th></tr></thead>
                   <tbody>
                     ${itens
                       .map(
                         (i) => `
                       <tr>
                         <td><span class="ad-td-forte">${escapeHtml(i.item || '—')}</span></td>
                         <td><span class="ad-td-meta">${escapeHtml(i.variante || '—')}</span></td>
                         <td class="num">${formatNumero(i.qtd)}</td>
                         <td class="num">${formatNumero(i.pedidos)}</td>
                         <td class="num">${formatBRL(i.total_centavos)}</td>
                       </tr>`,
                       )
                       .join('')}
                   </tbody>
                 </table>
               </div>`
            : vazio('nada vendido nesse período', 'tenta esticar as datas.')
        }
      </section>

      <section class="ad-bloco">
        <div class="ad-bloco-head">
          <h2 class="title sm">o que saiu por pontos</h2>
          <p class="ad-head-sub">${formatNumero(totalPontos)} pontos trocados no período</p>
        </div>
        ${
          resgates && resgates.length
            ? `<div class="ad-tabela-wrap">
                 <table class="ad-tabela">
                   <thead><tr><th>recompensa</th><th>tipo</th><th class="num">vezes</th><th class="num">pontos</th><th class="num">entregues</th></tr></thead>
                   <tbody>
                     ${resgates
                       .map(
                         (r) => `
                       <tr>
                         <td><span class="ad-td-forte">${escapeHtml(r.recompensa || '—')}</span></td>
                         <td><span class="ad-td-meta">${escapeHtml(r.tipo || '—')}</span></td>
                         <td class="num">${formatNumero(r.vezes)}</td>
                         <td class="num">${formatNumero(r.pontos)}</td>
                         <td class="num">${formatNumero(r.entregues)}</td>
                       </tr>`,
                       )
                       .join('')}
                   </tbody>
                 </table>
               </div>`
            : vazio('nenhum resgate nesse período', 'tenta esticar as datas.')
        }
      </section>`;
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

// ===== EQUIPE =======================================================
// Onde se dá e se tira acesso. A busca vivia no topo, sempre aberta, e isso
// fazia a tela abrir com um campo em vez de abrir com A EQUIPE — que é o que
// alguém vem ver aqui. Agora a lista vem primeiro e a busca virou o botão
// "+ na equipe", que abre a folhinha de procurar quem cadastrar.
async function viewEquipe(view) {
  view.innerHTML =
    cabecalho(
      'quem cuida do quê',
      'as permissões vêm por seção do site, e cada página tem as ações dela: quem enxerga, quem mexe, quem arruma.',
      `<button type="button" class="btn solid sm" data-add-equipe><i data-lucide="user-plus"></i>+equipe</button>
       <button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) + `<div data-corpo></div>`;

  const corpo = $('[data-corpo]', view);
  renderIcons();

  $('[data-add-equipe]', view).addEventListener('click', () => procurarPessoaParaEquipe(corpo));
  $('[data-recarregar]', view).addEventListener('click', () => carregarEquipe(corpo));

  carregarEquipe(corpo);
}

// A folhinha de "quem tu quer trazer": procura no cadastro do site e devolve a
// pessoa escolhida. Quem não tem conta no site ainda não aparece aqui, e isso é
// dito na cara em vez de virar "não achei ninguém".
async function procurarPessoaParaEquipe(corpo) {
  const fundo = document.createElement('div');
  fundo.className = 'ad-modal pauta-escolha';
  fundo.innerHTML = `
    <div class="ad-modal-caixa pauta-escolha-caixa" role="dialog" aria-modal="true" aria-label="trazer alguém pra equipe">
      <p class="lbl">trazer alguém pra equipe</p>
      <form class="ad-busca" data-busca-pessoa style="margin: 12px 0">
        <div class="field">
          <label for="busca-equipe" class="sr-only">buscar pelo nome ou e-mail</label>
          <input id="busca-equipe" type="search" placeholder="nome ou e-mail" autocomplete="off" />
        </div>
        <button type="submit" class="btn ghost sm"><i data-lucide="search"></i>buscar</button>
      </form>
      <p class="ad-dica">a pessoa precisa ter conta no site. se ainda não tem, pede pra ela se cadastrar em /cadastro e volta aqui.</p>
      <div data-achados></div>
      <div class="ad-modal-acoes">
        <button type="button" class="btn ghost sm" data-fechar>deixa pra lá</button>
      </div>
    </div>`;

  const fechar = () => {
    document.removeEventListener('keydown', aoTeclar);
    fundo.remove();
  };
  const aoTeclar = (e) => {
    if (e.key === 'Escape') fechar();
  };
  fundo.addEventListener('click', (e) => {
    if (e.target === fundo || e.target.closest('[data-fechar]')) fechar();
  });
  document.addEventListener('keydown', aoTeclar);
  document.body.appendChild(fundo);
  renderIcons();
  $('#busca-equipe', fundo).focus();

  const achados = $('[data-achados]', fundo);
  $('[data-busca-pessoa]', fundo).addEventListener('submit', async (e) => {
    e.preventDefault();
    const termo = $('#busca-equipe', fundo).value.trim();
    if (termo.length < 3) {
      achados.innerHTML = `<div class="notice warn"><p>escreve pelo menos 3 letras pra eu procurar.</p></div>`;
      return;
    }
    carregando(achados, 'procurando…');
    try {
      const pessoas = await rpc('admin_buscar_pessoa', { p_busca: termo });
      if (!pessoas || !pessoas.length) {
        achados.innerHTML = vazio('não achei ninguém', 'confere o nome ou o e-mail. só aparece quem já tem conta no site.');
        return;
      }
      achados.innerHTML = `
        <div class="rows">
          ${pessoas
            .map(
              (p) => `
            <div class="row">
              <div class="row-main">
                <span>${escapeHtml(p.nome || 'sem nome')}</span>
                <span class="row-meta">${escapeHtml(p.email || '')}</span>
              </div>
              <button type="button" class="btn ghost sm" data-add="${escapeHtml(p.id)}" data-nome="${escapeHtml(p.nome || 'sem nome')}" data-email="${escapeHtml(p.email || '')}">trazer</button>
            </div>`,
            )
            .join('')}
        </div>`;
      $$('[data-add]', achados).forEach((botao) => {
        botao.addEventListener('click', () => {
          const nova = {
            id: botao.dataset.add,
            nome: botao.dataset.nome,
            email: botao.dataset.email,
            papel: 'cliente',
            master: false,
            permissoes: [],
            novo: true,
          };
          fechar();
          const lista = $('.ad-lista', corpo);
          if (!lista) {
            toast('a lista da equipe não carregou; recarrega a página pra adicionar');
            return;
          }
          if ($(`[data-pessoa="${CSS.escape(nova.id)}"]`, corpo)) {
            toast('essa pessoa já está na lista');
            return;
          }
          lista.insertAdjacentHTML('afterbegin', cardEquipe(nova));
          ligarCardsEquipe(corpo);
          renderIcons();
          $(`[data-pessoa="${CSS.escape(nova.id)}"]`, corpo)?.scrollIntoView({ block: 'center', behavior: 'smooth' });
        });
      });
    } catch (err) {
      erroNaTela(achados, err);
    }
  });
}

async function carregarEquipe(corpo) {
  carregando(corpo);
  try {
    // O catálogo e a equipe vêm juntos: sem o catálogo não dá pra desenhar
    // caixinha nenhuma, e sem a equipe não há em quem marcar.
    const [resposta] = await Promise.all([rpc('admin_equipe'), carregarCatalogo()]);
    const linhas = Array.isArray(resposta) ? resposta : [];
    // Lista vazia era uma área em BRANCO, sem nada dizendo por quê. Se nem o adm
    // do Casa voltou, o problema não é "ninguém na equipe", é a leitura.
    corpo.innerHTML =
      (linhas.length
        ? ''
        : vazio(
            'não veio ninguém do banco',
            'nem a tua própria conta voltou nessa lista, então isso não é "equipe vazia". recarrega; se continuar, me avisa.',
          )) + `<div class="ad-lista">${linhas.map((p) => cardEquipe(p)).join('')}</div>`;
    ligarCardsEquipe(corpo);
    renderIcons();
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

// Uma linha em cima das caixinhas dizendo o que a pessoa alcança hoje. Com mais
// de quarenta permissões, ler a grade inteira pra descobrir isso é trabalho.
// Conta as páginas, não as permissões: "alcança 6 páginas" diz mais do que
// "tem 11 permissões", e é assim que a casa pensa.
function resumoDoAcesso(permissoes) {
  const acoes = todasAsAcoes(catalogoPermissoes);
  const minhas = acoes.filter((a) => permissoes.includes(a.slug));
  if (!minhas.length) return 'ainda não enxerga nada por aqui.';

  const paginas = (catalogoPermissoes || []).flatMap((s) => s.paginas || []);
  const alcanca = paginas.filter((pg) => (pg.acoes || []).some((a) => permissoes.includes(a.slug)));
  const arruma = paginas.filter((pg) =>
    (pg.acoes || []).some((a) => a.acao === 'arrumar' && permissoes.includes(a.slug)),
  );

  const partes = [`alcança ${alcanca.length} de ${paginas.length} páginas: ${alcanca.map((pg) => pg.rotulo).join(', ')}`];
  if (arruma.length) partes.push(`e arruma ${arruma.map((pg) => pg.rotulo).join(', ')}`);
  return `${partes.join('. ')}.`;
}

function cardEquipe(p) {
  const permissoes = Array.isArray(p.permissoes) ? p.permissoes : [];
  const euMesmo = p.id === estado.sessao?.user?.id;
  const intocavel = p.master || p.papel === 'owner';
  const souOwner = Boolean(estado.perms?.tudo);

  if (intocavel) {
    return `
      <article class="card ad-card" data-pessoa="${escapeHtml(p.id)}">
        <div class="ad-card-topo">
          <div>
            <p class="ad-card-nome">${escapeHtml(p.nome || 'sem nome')}</p>
            <p class="ad-card-meta">${escapeHtml(p.email || '')}</p>
          </div>
          <div class="ad-card-tags"><span class="tag gold">adm do Casa</span></div>
        </div>
        <p class="ad-card-meta">essa conta cuida da casa inteira e não some daqui. não há o que ajustar.</p>
      </article>`;
  }

  return `
    <article class="card ad-card" data-pessoa="${escapeHtml(p.id)}">
      <div class="ad-card-topo">
        <div>
          <p class="ad-card-nome">${escapeHtml(p.nome || 'sem nome')}</p>
          <p class="ad-card-meta">${escapeHtml(p.email || '')}</p>
        </div>
        <div class="ad-card-tags">
          ${p.papel && p.papel !== 'cliente' ? `<span class="tag olive">${escapeHtml(ROTULO_PAPEL[p.papel] || p.papel)}</span>` : ''}
          ${p.novo ? '<span class="tag gold">ainda sem acesso</span>' : ''}
        </div>
      </div>

      ${euMesmo ? '<div class="notice info"><p>essas são as tuas permissões. quem muda as tuas é outra pessoa do time.</p></div>' : ''}

      <p class="ad-perm-resumo" data-resumo="${escapeHtml(p.id)}">${resumoDoAcesso(permissoes)}</p>

      <div class="ad-perm-caixa" data-perms ${p.novo ? '' : 'hidden'}>
      ${(catalogoPermissoes || [])
        .map(
          (secao) => `
        <section class="ad-perm-area">
          <header class="ad-perm-area-topo">
            <span class="ad-perm-area-titulo">
              <span class="lbl">${escapeHtml(secao.rotulo)}</span>
              ${secao.descricao ? `<em>${escapeHtml(secao.descricao)}</em>` : ''}
            </span>
            ${
              euMesmo
                ? ''
                : `<span class="ad-perm-area-acoes">
                     <button type="button" class="ad-perm-mini" data-area-marcar>marcar tudo</button>
                     <button type="button" class="ad-perm-mini" data-area-limpar>limpar</button>
                   </span>`
            }
          </header>
          <div class="ad-perms">
            ${(secao.paginas || [])
              .map((pagina) => {
                // Delegar a página da equipe é o único poder que não se delega:
                // senão o controle vaza de mão em mão. O banco também recusa.
                const soOwner = pagina.slug === 'equipe' && !souOwner;
                const travado = euMesmo || soOwner;
                return `
              <div class="ad-perm-pagina">
                <p class="ad-perm-pagina-nome">
                  <strong>${escapeHtml(pagina.rotulo)}</strong>
                  <em>${escapeHtml(soOwner ? 'só o adm do Casa delega isto' : pagina.descricao || '')}</em>
                </p>
                <div class="ad-perm-acoes">
                  ${(pagina.acoes || [])
                    .map((acao) => {
                      const marcado = permissoes.includes(acao.slug);
                      return `
                    <label class="ad-perm-acao${travado ? ' is-travado' : ''}" title="${escapeHtml(acao.descricao || '')}">
                      <input type="checkbox" value="${escapeHtml(acao.slug)}"
                             data-pagina="${escapeHtml(pagina.slug)}" data-nivel="${Number(acao.nivel) || 1}"
                             ${marcado ? 'checked' : ''} ${travado ? 'disabled' : ''} />
                      <span>${escapeHtml(acao.rotulo)}</span>
                    </label>`;
                    })
                    .join('')}
                </div>
              </div>`;
              })
              .join('')}
          </div>
        </section>`,
        )
        .join('')}
      </div>

      <div class="ad-card-acoes">
        <button type="button" class="btn ghost sm" data-editar-perms ${p.novo ? 'hidden' : ''}>
          <i data-lucide="pencil"></i>${euMesmo ? 'ver as minhas permissões' : 'editar permissões'}
        </button>
        ${
          euMesmo
            ? `<button type="button" class="btn ghost sm" data-fechar-perms ${p.novo ? '' : 'hidden'}>fechar</button>`
            : `<button type="button" class="btn solid sm" data-salvar="${escapeHtml(p.id)}" ${p.novo ? '' : 'hidden'}>salvar</button>
               <button type="button" class="btn ghost sm" data-fechar-perms ${p.novo ? '' : 'hidden'}>cancelar</button>
               ${p.novo ? '' : `<button type="button" class="btn ghost sm" data-tirar="${escapeHtml(p.id)}" data-nome="${escapeHtml(p.nome || 'essa pessoa')}">tirar do console</button>`}`
        }
      </div>
    </article>`;
}

// A grade tem 43 caixinhas (20 páginas × as ações de cada uma): deixá-la aberta
// em todo mundo transforma a lista da equipe num paredão de checkbox, e depois
// de salvar ela continuava escancarada como se ainda houvesse o que fazer. O
// cartão fecha e mostra só o resumo; quem vai mexer abre no "editar permissões".
function abrirCartaoDeEquipe(card, aberto) {
  const caixa = $('[data-perms]', card);
  if (caixa) caixa.hidden = !aberto;
  $$('[data-editar-perms]', card).forEach((b) => (b.hidden = aberto));
  $$('[data-salvar], [data-fechar-perms]', card).forEach((b) => (b.hidden = !aberto));
}

function ligarCardsEquipe(corpo) {
  // Marcar tudo / limpar por seção, e o resumo se atualizando a cada clique: com
  // mais de quarenta caixinhas, dar acesso "a tudo da loja" na mão é enfadonho e
  // dá erro.
  $$('[data-pessoa]', corpo).forEach((card) => {
    if (card.dataset.ligado) return;
    card.dataset.ligado = '1';
    const atualizarResumo = () => {
      const resumo = $('[data-resumo]', card);
      if (!resumo) return;
      const marcadas = $$('input[type="checkbox"]', card).filter((c) => c.checked).map((c) => c.value);
      resumo.textContent = resumoDoAcesso(marcadas);
    };

    // A hierarquia da 0047, espelhada na tela: quem arruma também mexe e
    // enxerga. O banco já resolve isso sozinho, mas se a tela deixasse marcar
    // "arrumar" com "enxergar" em branco, ela estaria mostrando um acesso que
    // não é o que a pessoa tem. Marcar um nível acende os de baixo; desmarcar
    // um nível apaga os de cima.
    const irmas = (alvo) =>
      $$(`input[data-pagina="${CSS.escape(alvo.dataset.pagina)}"]`, card).filter((c) => !c.disabled);

    card.addEventListener('change', (ev) => {
      const alvo = ev.target;
      if (!alvo.matches('input[type="checkbox"][data-pagina]')) return;
      const nivel = Number(alvo.dataset.nivel) || 1;
      irmas(alvo).forEach((c) => {
        const n = Number(c.dataset.nivel) || 1;
        if (alvo.checked && n < nivel) c.checked = true;
        if (!alvo.checked && n > nivel) c.checked = false;
      });
      atualizarResumo();
    });
    card.addEventListener('click', (ev) => {
      const marcar = ev.target.closest('[data-area-marcar]');
      const limpar = ev.target.closest('[data-area-limpar]');
      if (!marcar && !limpar) return;
      const area = ev.target.closest('.ad-perm-area');
      $$('input[type="checkbox"]', area).forEach((c) => {
        if (!c.disabled) c.checked = Boolean(marcar);
      });
      atualizarResumo();
    });
  });

  $$('[data-editar-perms]', corpo).forEach((botao) => {
    if (botao.dataset.ligado) return;
    botao.dataset.ligado = '1';
    botao.addEventListener('click', () => {
      const card = botao.closest('[data-pessoa]');
      abrirCartaoDeEquipe(card, true);
      $('input[type="checkbox"]:not([disabled])', card)?.focus();
    });
  });

  // "cancelar" recarrega a lista de propósito: assim o que foi marcado sem
  // salvar não fica na tela fingindo que valeu.
  $$('[data-fechar-perms]', corpo).forEach((botao) => {
    if (botao.dataset.ligado) return;
    botao.dataset.ligado = '1';
    botao.addEventListener('click', () => carregarEquipe(corpo));
  });

  $$('[data-salvar]', corpo).forEach((botao) => {
    if (botao.dataset.ligado) return;
    botao.dataset.ligado = '1';
    botao.addEventListener('click', async () => {
      const card = botao.closest('[data-pessoa]');
      const marcadas = $$('input[type="checkbox"]', card)
        .filter((c) => c.checked)
        .map((c) => c.value);
      botao.disabled = true;
      try {
        const r = await rpc('admin_definir_permissoes', {
          p_user_id: botao.dataset.salvar,
          p_permissoes: marcadas,
        });
        if (r?.ok === false) {
          toast(r.erro || 'não deu pra salvar', 'erro');
          botao.disabled = false;
          return;
        }
        toast('pronto, permissões salvas 💛');
        carregarEquipe(corpo);
      } catch (e) {
        toast(e.message, 'erro');
        botao.disabled = false;
      }
    });
  });

  $$('[data-tirar]', corpo).forEach((botao) => {
    if (botao.dataset.ligado) return;
    botao.dataset.ligado = '1';
    botao.addEventListener('click', async () => {
      const ok = await confirmar({
        titulo: `tirar ${botao.dataset.nome} do console?`,
        texto: 'a conta continua existindo como cliente; só o acesso ao balcão sai.',
        ok: 'sim, tirar',
        tom: 'perigo',
      });
      if (!ok) return;
      botao.disabled = true;
      try {
        const r = await rpc('admin_definir_permissoes', {
          p_user_id: botao.dataset.tirar,
          p_permissoes: [],
        });
        if (r?.ok === false) {
          toast(r.erro || 'não deu pra tirar', 'erro');
          botao.disabled = false;
          return;
        }
        toast('acesso removido');
        carregarEquipe(corpo);
      } catch (e) {
        toast(e.message, 'erro');
        botao.disabled = false;
      }
    });
  });
}

// ===== RECADOS DA CASA ==============================================
// Owner-only. A tarja de aviso que acende no topo do site. As RPCs admin_aviso_*
// (0022) trancam por is_owner() no banco; aqui é só a tela.
let recadoEditando = null; // id em edição, ou null (criando um novo)

// ISO ↔ valor de <input type="datetime-local"> (hora local do navegador).
function isoDeDtLocal(v) {
  if (!v) return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}
function dtLocalDeIso(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

function statusDoRecado(a) {
  if (!a.ativo) return { txt: 'desligado', tom: 'off' };
  const agora = Date.now();
  const ini = a.inicio_em ? Date.parse(a.inicio_em) : null;
  const fim = a.fim_em ? Date.parse(a.fim_em) : null;
  if (ini && ini > agora) return { txt: `agendado pra ${formatData(a.inicio_em)}`, tom: 'wait' };
  if (fim && fim < agora) return { txt: `expirou em ${formatData(a.fim_em)}`, tom: 'off' };
  return { txt: 'no ar agora', tom: 'on' };
}

async function viewRecados(view) {
  const podeEscrever = pode('recados.mexer');
  const podeApagar = pode('recados.arrumar');

  view.innerHTML =
    cabecalho(
      'recados da casa',
      'a tarjinha que acende no topo do site. escreve curto, dá um prazo, e ela some sozinha quando vence.',
    ) +
    (podeEscrever
      ? ''
      : soLeitura('tu enxerga os recados, mas quem escreve e agenda é quem tem a permissão de mexer aqui. fala com o adm do Casa se precisar dela.')) +
    (!podeEscrever
      ? ''
      : `<form class="card ad-form-recado" data-form-recado novalidate>
       <input type="hidden" data-r-id />
       <div class="field">
         <label for="r-texto">o recado</label>
         <textarea id="r-texto" data-r-texto rows="2" maxlength="160" placeholder="hoje tem fornada de brioche a partir das 15h 🥐" required></textarea>
         <p class="ad-dica">curtinho, até 160 caracteres. o tom é o de sempre: acolhedor, sem pressa.</p>
       </div>
       <div class="ad-recado-linha">
         <div class="field ad-recado-emoji">
           <label for="r-emoji">emoji (opcional)</label>
           <input id="r-emoji" data-r-emoji maxlength="8" placeholder="🥐" />
         </div>
         <div class="field ad-recado-prio">
           <label for="r-prio">prioridade</label>
           <input id="r-prio" data-r-prio type="number" value="0" step="1" />
           <p class="ad-dica">maior aparece primeiro se houver mais de um.</p>
         </div>
       </div>
       <div class="ad-recado-linha">
         <div class="field">
           <label for="r-inicio">começa a aparecer</label>
           <input id="r-inicio" data-r-inicio type="datetime-local" />
           <p class="ad-dica">vazio = já vale agora.</p>
         </div>
         <div class="field">
           <label for="r-fim">para de aparecer</label>
           <input id="r-fim" data-r-fim type="datetime-local" />
           <p class="ad-dica">vazio = fica até tu desligar.</p>
         </div>
       </div>
       <div class="ad-recado-linha">
         <div class="field">
           <label for="r-link">link (opcional)</label>
           <input id="r-link" data-r-link placeholder="/planos ou https://…" />
         </div>
         <div class="field">
           <label for="r-link-label">texto do link</label>
           <input id="r-link-label" data-r-link-label maxlength="40" placeholder="ver os planos" />
         </div>
       </div>
       <label class="ad-recado-ativo"><input type="checkbox" data-r-ativo checked /> <span>ligado (aparece no site)</span></label>
       <div data-r-aviso></div>
       <div class="ad-card-acoes">
         <button type="submit" class="btn solid" data-r-salvar>publicar recado</button>
         <button type="button" class="btn ghost" data-r-cancelar hidden>cancelar edição</button>
       </div>
     </form>`) +
    `<div class="ad-recado-lista" data-recado-lista></div>`;

  renderIcons();
  const form = $('[data-form-recado]', view);
  const lista = $('[data-recado-lista]', view);
  const avisoForm = form ? $('[data-r-aviso]', form) : null;

  const limparForm = () => {
    if (!form) return;
    recadoEditando = null;
    form.reset();
    $('[data-r-id]', form).value = '';
    $('[data-r-ativo]', form).checked = true;
    $('[data-r-salvar]', form).textContent = 'publicar recado';
    $('[data-r-cancelar]', form).hidden = true;
    avisoForm.innerHTML = '';
  };

  const preencherForm = (a) => {
    if (!form) return;
    recadoEditando = a.id;
    $('[data-r-id]', form).value = a.id;
    $('[data-r-texto]', form).value = a.texto || '';
    $('[data-r-emoji]', form).value = a.emoji || '';
    $('[data-r-prio]', form).value = Number(a.prioridade) || 0;
    $('[data-r-inicio]', form).value = dtLocalDeIso(a.inicio_em);
    $('[data-r-fim]', form).value = dtLocalDeIso(a.fim_em);
    $('[data-r-link]', form).value = a.link_url || '';
    $('[data-r-link-label]', form).value = a.link_label || '';
    $('[data-r-ativo]', form).checked = Boolean(a.ativo);
    $('[data-r-salvar]', form).textContent = 'salvar recado';
    $('[data-r-cancelar]', form).hidden = false;
    view.scrollTop = 0;
    $('[data-r-texto]', form).focus();
  };

  async function carregarRecados() {
    carregando(lista, 'buscando os recados…');
    try {
      const dados = await rpc('admin_avisos_listar');
      const avisos = Array.isArray(dados) ? dados : [];
      if (!avisos.length) {
        lista.innerHTML = vazio(
          'nenhum recado ainda',
          podeEscrever
            ? 'escreve o primeiro aí em cima, ele acende no topo do site.'
            : 'quando alguém da casa escrever um recado, ele aparece aqui.',
        );
        return;
      }
      lista.innerHTML = avisos.map(cardRecado).join('');
      renderIcons();
      ligarCardsRecado();
    } catch (e) {
      erroNaTela(lista, e);
    }
  }

  function cardRecado(a) {
    const st = statusDoRecado(a);
    const janela = [];
    if (a.inicio_em) janela.push(`de ${formatData(a.inicio_em)}`);
    if (a.fim_em) janela.push(`até ${formatData(a.fim_em)}`);
    const linkTxt = a.link_url ? ` · link: ${escapeHtml(a.link_label || a.link_url)}` : '';
    return `
      <article class="card ad-card" data-recado="${escapeHtml(a.id)}">
        <div class="ad-card-topo">
          <div>
            <p class="ad-card-nome">${a.emoji ? escapeHtml(a.emoji) + ' ' : ''}${escapeHtml(a.texto || '')}</p>
            <p class="ad-card-meta">${janela.length ? escapeHtml(janela.join(' ')) : 'sem prazo'} · prioridade ${Number(a.prioridade) || 0}${linkTxt}</p>
          </div>
          <div class="ad-card-tags"><span class="tag ${st.tom === 'on' ? 'olive' : 'gold'}">${escapeHtml(st.txt)}</span></div>
        </div>
        <div class="ad-card-acoes">
          ${podeEscrever ? `<button type="button" class="btn ghost sm" data-r-editar="${escapeHtml(a.id)}">editar</button>` : ''}
          ${podeApagar ? `<button type="button" class="btn ghost sm" data-r-remover="${escapeHtml(a.id)}" data-r-resumo="${escapeHtml((a.texto || '').slice(0, 40))}">remover</button>` : ''}
        </div>
      </article>`;
  }

  function ligarCardsRecado() {
    $$('[data-r-editar]', lista).forEach((b) => {
      b.addEventListener('click', async () => {
        try {
          const dados = await rpc('admin_avisos_listar');
          const a = (Array.isArray(dados) ? dados : []).find((x) => x.id === b.dataset.rEditar);
          if (a) preencherForm(a);
        } catch (e) {
          toast(e.message, 'erro');
        }
      });
    });
    $$('[data-r-remover]', lista).forEach((b) => {
      b.addEventListener('click', async () => {
        const ok = await confirmar({
          titulo: 'remover este recado?',
          texto: `"${b.dataset.rResumo}…" — some do site na hora e não dá pra desfazer.`,
          ok: 'sim, remover',
          tom: 'perigo',
        });
        if (!ok) return;
        b.disabled = true;
        try {
          await rpc('admin_aviso_remover', { p_id: b.dataset.rRemover });
          toast('recado removido');
          if (recadoEditando === b.dataset.rRemover) limparForm();
          carregarRecados();
        } catch (e) {
          toast(e.message, 'erro');
          b.disabled = false;
        }
      });
    });
  }

  form?.addEventListener('submit', async (e) => {
    e.preventDefault();
    avisoForm.innerHTML = '';
    const texto = $('[data-r-texto]', form).value.trim();
    if (!texto) {
      avisoForm.innerHTML = '<div class="notice err"><p>escreve o recado 💛</p></div>';
      return;
    }
    const inicio = isoDeDtLocal($('[data-r-inicio]', form).value);
    const fim = isoDeDtLocal($('[data-r-fim]', form).value);
    if (inicio && fim && Date.parse(fim) <= Date.parse(inicio)) {
      avisoForm.innerHTML = '<div class="notice err"><p>o fim tem que ser depois do começo.</p></div>';
      return;
    }
    const botao = $('[data-r-salvar]', form);
    botao.disabled = true;
    try {
      await rpc('admin_aviso_salvar', {
        p_id: recadoEditando || null,
        p_texto: texto,
        p_emoji: $('[data-r-emoji]', form).value.trim() || null,
        p_link_url: $('[data-r-link]', form).value.trim() || null,
        p_link_label: $('[data-r-link-label]', form).value.trim() || null,
        p_inicio: inicio,
        p_fim: fim,
        p_prioridade: Number($('[data-r-prio]', form).value) || 0,
        p_ativo: $('[data-r-ativo]', form).checked,
      });
      toast(recadoEditando ? 'recado salvo 💛' : 'recado publicado 💛');
      limparForm();
      carregarRecados();
    } catch (e2) {
      toast(e2.message, 'erro');
    } finally {
      botao.disabled = false;
    }
  });

  if (form) $('[data-r-cancelar]', form).addEventListener('click', limparForm);

  carregarRecados();
}

// ===== TRILHA DO CASA ===============================================
// Owner-only. As playlists do Spotify que aparecem na home. RPCs admin_trilha_*
// (0023) trancam por is_owner() no banco.
let trilhaEditando = null;

// Cheiro de link do Spotify (bloqueio gentil no submit; a home revalida antes do embed).
function pareceSpotify(url) {
  const s = String(url || '').trim();
  if (/^spotify:(playlist|album|track|artist|show|episode):[A-Za-z0-9]+$/i.test(s)) return true;
  try {
    return new URL(s).hostname === 'open.spotify.com';
  } catch {
    return false;
  }
}

async function viewTrilha(view) {
  const podeEscrever = pode('trilha.mexer');
  const podeApagar = pode('trilha.arrumar');

  view.innerHTML =
    cabecalho(
      'a trilha do Casa',
      'as playlists do Spotify que tocam na home. cola o link, dá um clima, e marca qual está tocando agora.',
    ) +
    (podeEscrever
      ? ''
      : soLeitura('tu enxerga a trilha, mas quem cadastra e escolhe a que está tocando é quem tem a permissão de mexer aqui.')) +
    (!podeEscrever
      ? ''
      : `<form class="card ad-form-recado" data-form-trilha novalidate>
       <input type="hidden" data-t-id />
       <div class="ad-recado-linha">
         <div class="field">
           <label for="t-nome">nome da playlist</label>
           <input id="t-nome" data-t-nome maxlength="80" placeholder="tarde de trabalho" required />
         </div>
         <div class="field">
           <label for="t-clima">clima (opcional)</label>
           <input id="t-clima" data-t-clima maxlength="40" placeholder="pra focar" />
         </div>
       </div>
       <div class="field">
         <label for="t-url">link do Spotify</label>
         <input id="t-url" data-t-url placeholder="https://open.spotify.com/playlist/…" required />
         <p class="ad-dica">abre a playlist no Spotify → compartilhar → copiar link. cola aqui.</p>
       </div>
       <div class="ad-recado-linha">
         <div class="field ad-recado-prio">
           <label for="t-ordem">ordem</label>
           <input id="t-ordem" data-t-ordem type="number" value="0" step="1" />
           <p class="ad-dica">menor aparece primeiro.</p>
         </div>
         <div class="ad-trilha-flags">
           <label class="ad-recado-ativo"><input type="checkbox" data-t-ativo checked /> <span>na home</span></label>
           <label class="ad-recado-ativo"><input type="checkbox" data-t-tocando /> <span>tocando agora 🎧</span></label>
         </div>
       </div>
       <div data-t-aviso></div>
       <div class="ad-card-acoes">
         <button type="submit" class="btn solid" data-t-salvar>adicionar playlist</button>
         <button type="button" class="btn ghost" data-t-cancelar hidden>cancelar edição</button>
       </div>
     </form>`) +
    `<div class="ad-recado-lista" data-trilha-lista></div>`;

  renderIcons();
  const form = $('[data-form-trilha]', view);
  const lista = $('[data-trilha-lista]', view);
  const avisoForm = form ? $('[data-t-aviso]', form) : null;

  const limparForm = () => {
    if (!form) return;
    trilhaEditando = null;
    form.reset();
    $('[data-t-id]', form).value = '';
    $('[data-t-ativo]', form).checked = true;
    $('[data-t-tocando]', form).checked = false;
    $('[data-t-salvar]', form).textContent = 'adicionar playlist';
    $('[data-t-cancelar]', form).hidden = true;
    avisoForm.innerHTML = '';
  };

  const preencherForm = (p) => {
    if (!form) return;
    trilhaEditando = p.id;
    $('[data-t-id]', form).value = p.id;
    $('[data-t-nome]', form).value = p.nome || '';
    $('[data-t-clima]', form).value = p.clima || '';
    $('[data-t-url]', form).value = p.spotify_url || '';
    $('[data-t-ordem]', form).value = Number(p.ordem) || 0;
    $('[data-t-ativo]', form).checked = Boolean(p.ativo);
    $('[data-t-tocando]', form).checked = Boolean(p.tocando);
    $('[data-t-salvar]', form).textContent = 'salvar playlist';
    $('[data-t-cancelar]', form).hidden = false;
    view.scrollTop = 0;
    $('[data-t-nome]', form).focus();
  };

  async function carregarTrilha() {
    carregando(lista, 'buscando as playlists…');
    try {
      const dados = await rpc('admin_trilha_listar');
      const pls = Array.isArray(dados) ? dados : [];
      if (!pls.length) {
        lista.innerHTML = vazio(
          'nenhuma playlist ainda',
          podeEscrever
            ? 'cola a primeira aí em cima, ela aparece na home.'
            : 'quando alguém da casa cadastrar uma playlist, ela aparece aqui.',
        );
        return;
      }
      lista.innerHTML = pls.map(cardTrilha).join('');
      renderIcons();
      ligarCardsTrilha();
    } catch (e) {
      erroNaTela(lista, e);
    }
  }

  function cardTrilha(p) {
    const tags = [];
    if (p.tocando) tags.push('<span class="tag olive">tocando agora</span>');
    if (!p.ativo) tags.push('<span class="tag gold">fora da home</span>');
    return `
      <article class="card ad-card" data-trilha-item="${escapeHtml(p.id)}">
        <div class="ad-card-topo">
          <div>
            <p class="ad-card-nome">${p.clima ? escapeHtml(p.clima) + ' · ' : ''}${escapeHtml(p.nome || '')}</p>
            <p class="ad-card-meta">ordem ${Number(p.ordem) || 0} · ${escapeHtml(p.spotify_url || '')}</p>
          </div>
          <div class="ad-card-tags">${tags.join('')}</div>
        </div>
        <div class="ad-card-acoes">
          ${podeEscrever ? `<button type="button" class="btn ghost sm" data-t-editar="${escapeHtml(p.id)}">editar</button>` : ''}
          ${podeApagar ? `<button type="button" class="btn ghost sm" data-t-remover="${escapeHtml(p.id)}" data-t-nome="${escapeHtml(p.nome || 'essa playlist')}">remover</button>` : ''}
        </div>
      </article>`;
  }

  function ligarCardsTrilha() {
    $$('[data-t-editar]', lista).forEach((b) => {
      b.addEventListener('click', async () => {
        try {
          const dados = await rpc('admin_trilha_listar');
          const p = (Array.isArray(dados) ? dados : []).find((x) => x.id === b.dataset.tEditar);
          if (p) preencherForm(p);
        } catch (e) {
          toast(e.message, 'erro');
        }
      });
    });
    $$('[data-t-remover]', lista).forEach((b) => {
      b.addEventListener('click', async () => {
        const ok = await confirmar({
          titulo: `remover "${b.dataset.tNome}"?`,
          texto: 'some da home na hora e não dá pra desfazer.',
          ok: 'sim, remover',
          tom: 'perigo',
        });
        if (!ok) return;
        b.disabled = true;
        try {
          await rpc('admin_trilha_remover', { p_id: b.dataset.tRemover });
          toast('playlist removida');
          if (trilhaEditando === b.dataset.tRemover) limparForm();
          carregarTrilha();
        } catch (e) {
          toast(e.message, 'erro');
          b.disabled = false;
        }
      });
    });
  }

  form?.addEventListener('submit', async (e) => {
    e.preventDefault();
    avisoForm.innerHTML = '';
    const nome = $('[data-t-nome]', form).value.trim();
    const url = $('[data-t-url]', form).value.trim();
    if (!nome) {
      avisoForm.innerHTML = '<div class="notice err"><p>dá um nome pra playlist 💛</p></div>';
      return;
    }
    if (!pareceSpotify(url)) {
      avisoForm.innerHTML = '<div class="notice err"><p>cola um link do Spotify (open.spotify.com/…).</p></div>';
      return;
    }
    const botao = $('[data-t-salvar]', form);
    botao.disabled = true;
    try {
      await rpc('admin_trilha_salvar', {
        p_id: trilhaEditando || null,
        p_nome: nome,
        p_clima: $('[data-t-clima]', form).value.trim() || null,
        p_url: url,
        p_ordem: Number($('[data-t-ordem]', form).value) || 0,
        p_ativo: $('[data-t-ativo]', form).checked,
        p_tocando: $('[data-t-tocando]', form).checked,
      });
      toast(trilhaEditando ? 'playlist salva 💛' : 'playlist adicionada 💛');
      limparForm();
      carregarTrilha();
    } catch (e2) {
      toast(e2.message, 'erro');
    } finally {
      botao.disabled = false;
    }
  });

  if (form) $('[data-t-cancelar]', form).addEventListener('click', limparForm);

  carregarTrilha();
}

// ===== AGENDA (encontros) ===========================================
// Os próximos encontros que aparecem na home. Trancam por is_owner() no banco
// (0026); aqui é só a tela. O RSVP (confirmar presença) é do lado do assinante,
// na home — aqui a gente só vê quantos confirmaram.
let agendaEditando = null;

async function viewAgenda(view) {
  const podeEscrever = pode('agenda.mexer');
  const podeApagar = pode('agenda.arrumar');

  view.innerHTML =
    cabecalho(
      'a agenda do Casa',
      'os próximos encontros que aparecem na home. marca a data, o lugar e quantas vagas.',
    ) +
    (podeEscrever
      ? ''
      : soLeitura('tu enxerga a agenda e quantos confirmaram, mas quem cria e edita encontro é quem tem a permissão de mexer aqui.')) +
    (!podeEscrever
      ? ''
      : `<form class="card ad-form-recado" data-form-agenda novalidate>
       <input type="hidden" data-a-id />
       <div class="field">
         <label for="a-nome">nome do encontro</label>
         <input id="a-nome" data-a-nome maxlength="120" placeholder="sarau de quarta" required />
       </div>
       <div class="ad-recado-linha">
         <div class="field">
           <label for="a-data">quando</label>
           <input id="a-data" data-a-data type="datetime-local" />
           <p class="ad-dica">deixa em branco pra "em breve".</p>
         </div>
         <div class="field">
           <label for="a-local">onde (opcional)</label>
           <input id="a-local" data-a-local maxlength="120" placeholder="no salão de cima" />
         </div>
       </div>
       <div class="field">
         <label for="a-desc">descrição (opcional)</label>
         <textarea id="a-desc" data-a-desc rows="2" maxlength="400" placeholder="uma linha sobre o encontro"></textarea>
       </div>
       <div class="ad-recado-linha">
         <div class="field ad-recado-prio">
           <label for="a-vagas">vagas</label>
           <input id="a-vagas" data-a-vagas type="number" min="0" step="1" placeholder="sem limite" />
           <p class="ad-dica">em branco = sem limite.</p>
         </div>
         <div class="ad-trilha-flags">
           <label class="ad-recado-ativo"><input type="checkbox" data-a-ativo checked /> <span>na home</span></label>
         </div>
       </div>
       <div data-a-aviso></div>
       <div class="ad-card-acoes">
         <button type="submit" class="btn solid" data-a-salvar>adicionar encontro</button>
         <button type="button" class="btn ghost" data-a-cancelar hidden>cancelar edição</button>
       </div>
     </form>`) +
    `<div class="ad-recado-lista" data-agenda-lista></div>`;

  renderIcons();
  const form = $('[data-form-agenda]', view);
  const lista = $('[data-agenda-lista]', view);
  const avisoForm = form ? $('[data-a-aviso]', form) : null;

  const limparForm = () => {
    if (!form) return;
    agendaEditando = null;
    form.reset();
    $('[data-a-id]', form).value = '';
    $('[data-a-ativo]', form).checked = true;
    $('[data-a-salvar]', form).textContent = 'adicionar encontro';
    $('[data-a-cancelar]', form).hidden = true;
    avisoForm.innerHTML = '';
  };

  const preencherForm = (e) => {
    if (!form) return;
    agendaEditando = e.id;
    $('[data-a-id]', form).value = e.id;
    $('[data-a-nome]', form).value = e.nome || '';
    $('[data-a-data]', form).value = dtLocalDeIso(e.data);
    $('[data-a-local]', form).value = e.local || '';
    $('[data-a-desc]', form).value = e.descricao || '';
    $('[data-a-vagas]', form).value = e.vagas == null ? '' : Number(e.vagas);
    $('[data-a-ativo]', form).checked = Boolean(e.ativo);
    $('[data-a-salvar]', form).textContent = 'salvar encontro';
    $('[data-a-cancelar]', form).hidden = false;
    view.scrollTop = 0;
    $('[data-a-nome]', form).focus();
  };

  async function carregarAgenda() {
    carregando(lista, 'buscando os encontros…');
    try {
      const dados = await rpc('admin_eventos_listar');
      const evs = Array.isArray(dados) ? dados : [];
      if (!evs.length) {
        lista.innerHTML = vazio(
          'nenhum encontro ainda',
          podeEscrever
            ? 'marca o primeiro aí em cima, ele aparece na home.'
            : 'quando a casa marcar um encontro, ele aparece aqui.',
        );
        return;
      }
      lista.innerHTML = evs.map(cardAgenda).join('');
      renderIcons();
      ligarCardsAgenda();
    } catch (e) {
      erroNaTela(lista, e);
    }
  }

  function cardAgenda(e) {
    const tags = [];
    if (!e.ativo) tags.push('<span class="tag gold">fora da home</span>');
    const passou = e.data && Date.parse(e.data) < Date.now();
    if (passou) tags.push('<span class="tag">já passou</span>');
    const vagas =
      e.vagas == null
        ? `${formatNumero(e.confirmados)} confirmados`
        : `${formatNumero(e.confirmados)}/${formatNumero(e.vagas)} confirmados`;
    return `
      <article class="card ad-card" data-agenda-item="${escapeHtml(e.id)}">
        <div class="ad-card-topo">
          <div>
            <p class="ad-card-nome">${escapeHtml(e.nome || '')}</p>
            <p class="ad-card-meta">${escapeHtml(formatData(e.data))}${e.local ? ' · ' + escapeHtml(e.local) : ''} · ${vagas}</p>
          </div>
          <div class="ad-card-tags">${tags.join('')}</div>
        </div>
        <div class="ad-card-acoes">
          ${podeEscrever ? `<button type="button" class="btn ghost sm" data-a-editar="${escapeHtml(e.id)}">editar</button>` : ''}
          ${podeApagar ? `<button type="button" class="btn ghost sm" data-a-remover="${escapeHtml(e.id)}" data-a-nome="${escapeHtml(e.nome || 'esse encontro')}">remover</button>` : ''}
        </div>
      </article>`;
  }

  function ligarCardsAgenda() {
    $$('[data-a-editar]', lista).forEach((b) => {
      b.addEventListener('click', async () => {
        try {
          const dados = await rpc('admin_eventos_listar');
          const e = (Array.isArray(dados) ? dados : []).find((x) => x.id === b.dataset.aEditar);
          if (e) preencherForm(e);
        } catch (e2) {
          toast(e2.message, 'erro');
        }
      });
    });
    $$('[data-a-remover]', lista).forEach((b) => {
      b.addEventListener('click', async () => {
        const ok = await confirmar({
          titulo: `remover "${b.dataset.aNome}"?`,
          texto: 'some da home na hora, junto com as confirmações. não dá pra desfazer.',
          ok: 'sim, remover',
          tom: 'perigo',
        });
        if (!ok) return;
        b.disabled = true;
        try {
          await rpc('admin_evento_remover', { p_id: b.dataset.aRemover });
          toast('encontro removido');
          if (agendaEditando === b.dataset.aRemover) limparForm();
          carregarAgenda();
        } catch (e) {
          toast(e.message, 'erro');
          b.disabled = false;
        }
      });
    });
  }

  form?.addEventListener('submit', async (e) => {
    e.preventDefault();
    avisoForm.innerHTML = '';
    const nome = $('[data-a-nome]', form).value.trim();
    if (!nome) {
      avisoForm.innerHTML = '<div class="notice err"><p>dá um nome pro encontro 💛</p></div>';
      return;
    }
    const vagasRaw = $('[data-a-vagas]', form).value.trim();
    const botao = $('[data-a-salvar]', form);
    botao.disabled = true;
    try {
      await rpc('admin_evento_salvar', {
        p_id: agendaEditando || null,
        p_nome: nome,
        p_descricao: $('[data-a-desc]', form).value.trim() || null,
        p_data: isoDeDtLocal($('[data-a-data]', form).value),
        p_local: $('[data-a-local]', form).value.trim() || null,
        p_vagas: vagasRaw === '' ? null : Math.max(0, Number(vagasRaw) || 0),
        p_ativo: $('[data-a-ativo]', form).checked,
      });
      toast(agendaEditando ? 'encontro salvo 💛' : 'encontro adicionado 💛');
      limparForm();
      carregarAgenda();
    } catch (e2) {
      toast(e2.message, 'erro');
    } finally {
      botao.disabled = false;
    }
  });

  if (form) $('[data-a-cancelar]', form).addEventListener('click', limparForm);

  carregarAgenda();
}

// ===== FOTOS DO SITE ================================================
// A aba que deixa a casa trocar as fotos do site sem esperar deploy (0054).
//
// São duas coisas na mesma tela, e a ordem importa: primeiro OS LUGARES (cada
// `<img>` do site que dá pra trocar, com o nome do lugar, o que ele mostra e
// que formato de foto cai bem ali), depois O ACERVO (as fotos que a casa já
// subiu). Quem chega aqui quer trocar a foto de um lugar, não administrar
// arquivo: o acervo é o meio, e por isso vem embaixo.
//
// A lista dos lugares vem do `fotos-do-site.js`, o mesmo arquivo que o site
// importa pra trocar. Ela NÃO é reescrita aqui — foi por escrever a mesma lista
// em dois lugares que o catálogo de permissões da 0047 divergiu do que o banco
// cobrava.
const FOTO_TIPOS = ['image/jpeg', 'image/png', 'image/webp', 'image/avif'];
const FOTO_EXTENSOES = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/avif': 'avif' };
const FOTO_MAX_BYTES = 8 * 1024 * 1024; // o mesmo teto do bucket (0054)

// O banco guarda o CAMINHO do arquivo, nunca a URL: o endereço é montado aqui,
// com o host vindo do env. Ver o cabeçalho da 0054.
function fotoUrl(caminho) {
  if (!supabase || !caminho) return null;
  try {
    const { data } = supabase.storage.from(FOTOS_BUCKET).getPublicUrl(caminho);
    return data?.publicUrl || null;
  } catch {
    return null;
  }
}

function tamanhoLegivel(bytes) {
  const n = Number(bytes || 0);
  if (!n) return '';
  if (n < 1024 * 1024) return `${Math.round(n / 1024)} KB`;
  return `${(n / 1024 / 1024).toFixed(1).replace('.', ',')} MB`;
}

// Nome de arquivo previsível a partir do nome que a casa deu: sem acento, sem
// espaço, sem maiúscula. O caminho ainda ganha um sufixo sorteado, então subir
// duas fotos com o mesmo nome nunca sobrescreve uma a outra.
function slugDeFoto(nome) {
  return (
    String(nome || 'foto')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 40) || 'foto'
  );
}

async function subirFotoDoSite({ arquivo, nome, alt }) {
  if (!supabase) throw new Error('o banco ainda não está configurado por aqui');
  if (!FOTO_TIPOS.includes(arquivo.type)) {
    throw new Error('essa a gente não abre. manda jpg, png, webp ou avif?');
  }
  if (arquivo.size > FOTO_MAX_BYTES) {
    throw new Error(`essa tem ${tamanhoLegivel(arquivo.size)} e o limite é 8 MB. dá uma diminuída?`);
  }

  const agora = new Date();
  const pasta = `${agora.getFullYear()}/${String(agora.getMonth() + 1).padStart(2, '0')}`;
  const sufixo = (crypto.randomUUID?.() || String(Math.random())).replace(/-/g, '').slice(0, 8);
  const caminho = `${pasta}/${slugDeFoto(nome)}-${sufixo}.${FOTO_EXTENSOES[arquivo.type]}`;

  const { error } = await supabase.storage.from(FOTOS_BUCKET).upload(caminho, arquivo, {
    contentType: arquivo.type,
    // O caminho leva um sufixo sorteado, então cada arquivo é único e pode
    // ficar guardado no cache do CDN pra sempre. Trocar a foto de um lugar sobe
    // um arquivo NOVO — nunca reescreve o antigo, que segue servindo quem
    // ainda tem a página aberta.
    cacheControl: '31536000',
    upsert: false,
  });
  if (error) {
    throw new Error(
      /row-level security|policy/i.test(error.message || '')
        ? 'o banco não deixou subir o arquivo. confere se tu tem a permissão de mexer nas fotos.'
        : `não deu pra subir o arquivo: ${error.message || 'tenta de novo daqui a pouco'}`,
    );
  }

  return rpc('admin_foto_registrar', {
    p_caminho: caminho,
    p_nome: nome,
    p_alt: alt || null,
    p_bytes: arquivo.size,
    p_tipo: arquivo.type,
  });
}

// A folhinha de escolher foto do acervo. Promise<id da foto | null>.
function escolherFotoDoAcervo(galeria, lugar) {
  return new Promise((resolve) => {
    const fundo = document.createElement('div');
    fundo.className = 'ad-modal';
    const grade = (galeria || [])
      .map((f) => {
        const url = fotoUrl(f.caminho);
        return `
          <button type="button" class="ad-foto-escolha" data-escolher="${escapeHtml(f.id)}">
            <span class="ad-foto-thumb">${url ? `<img src="${escapeHtml(url)}" alt="" loading="lazy" />` : ''}</span>
            <span class="ad-foto-escolha-nome">${escapeHtml(f.nome || 'sem nome')}</span>
          </button>`;
      })
      .join('');

    fundo.innerHTML = `
      <div class="ad-modal-caixa ad-modal-largo" role="dialog" aria-modal="true" aria-label="escolher a foto">
        <h3 class="title sm">que foto vai aqui?</h3>
        <p class="ad-modal-texto">${escapeHtml(lugar)}</p>
        ${
          grade
            ? `<div class="ad-fotos-escolher">${grade}</div>`
            : `<div class="notice info"><p>o acervo ainda está vazio. sobe a primeira foto ali embaixo, em "o acervo da casa", e ela aparece aqui.</p></div>`
        }
        <div class="ad-modal-acoes">
          <button type="button" class="btn ghost sm" data-nao>deixa pra lá</button>
        </div>
      </div>`;

    const fechar = (resposta) => {
      document.removeEventListener('keydown', aoTeclar);
      fundo.remove();
      resolve(resposta);
    };
    const aoTeclar = (e) => {
      if (e.key === 'Escape') fechar(null);
    };
    fundo.addEventListener('click', (e) => {
      if (e.target === fundo) fechar(null);
    });
    $('[data-nao]', fundo).addEventListener('click', () => fechar(null));
    $$('[data-escolher]', fundo).forEach((b) => {
      b.addEventListener('click', () => fechar(b.dataset.escolher));
    });
    document.addEventListener('keydown', aoTeclar);
    document.body.appendChild(fundo);
  });
}

async function viewFotos(view) {
  const podeMexer = pode('fotos.mexer');
  const podeApagar = pode('fotos.arrumar');

  view.innerHTML =
    cabecalho(
      'as fotos do site',
      'cada foto que o site mostra, com o lugar dela. troca aqui e ela troca no ar, sem esperar ninguém publicar nada.',
    ) +
    (podeMexer
      ? ''
      : soLeitura('tu enxerga o acervo e sabe que foto está em cada lugar, mas quem troca é quem tem a permissão de mexer aqui.')) +
    '<div data-fotos-corpo></div>';

  const corpo = $('[data-fotos-corpo]', view);
  let galeria = [];
  let lugares = new Map();

  // Um índice do contrário: pra cada foto do acervo, em que lugares do site ela
  // está. É o que faz o cartão do acervo dizer "essa é a do hero da home" em
  // vez de só "usada em 2 lugares".
  function ondeEstaAFoto(caminho) {
    return FOTOS_DO_SITE.filter((l) => lugares.get(l.slot)?.caminho === caminho)
      .map((l) => `${l.pagina} · ${l.local}`);
  }

  function lugarHTML(lugar) {
    const posta = lugares.get(lugar.slot);
    const url = posta ? fotoUrl(posta.caminho) : lugar.padrao;
    const quando = posta ? formatData(posta.atualizado_em, false) : '';
    const quem = posta?.quem ? ` por ${escapeHtml(posta.quem)}` : '';
    return `
      <article class="ad-foto-lugar" data-lugar="${escapeHtml(lugar.slot)}">
        <div class="ad-foto-thumb">${url ? `<img src="${escapeHtml(url)}" alt="" loading="lazy" />` : ''}</div>
        <div class="ad-foto-txt">
          <p class="ad-foto-onde">${escapeHtml(lugar.local)}</p>
          <p class="ad-foto-oque">${escapeHtml(lugar.oque)}</p>
          <p class="ad-dica">${escapeHtml(lugar.formato)}</p>
          <p class="ad-foto-estado">
            ${
              posta
                ? `<span class="tag olive">foto da casa</span> <span class="ad-card-meta">trocada em ${escapeHtml(quando)}${quem}</span>`
                : `<span class="tag">a que veio de fábrica</span>`
            }
          </p>
        </div>
        <div class="ad-foto-acoes">
          ${podeMexer ? `<button type="button" class="btn ghost sm" data-foto-trocar="${escapeHtml(lugar.slot)}">trocar</button>` : ''}
          ${
            podeMexer && posta
              ? `<button type="button" class="btn ghost sm" data-foto-soltar="${escapeHtml(lugar.slot)}">voltar pra de fábrica</button>`
              : ''
          }
        </div>
      </article>`;
  }

  function acervoHTML() {
    if (!galeria.length) {
      return vazio(
        'o acervo ainda está vazio',
        podeMexer
          ? 'sobe a primeira foto aí em cima. depois ela serve pra quantos lugares do site tu quiser.'
          : 'quando alguém da casa subir uma foto, ela aparece aqui.',
      );
    }
    return `<div class="ad-fotos-grade">${galeria
      .map((f) => {
        const url = fotoUrl(f.caminho);
        const onde = ondeEstaAFoto(f.caminho);
        const meta = [tamanhoLegivel(f.bytes), formatData(f.enviada_em, false), f.quem]
          .filter(Boolean)
          .map((t) => escapeHtml(t))
          .join(' · ');
        return `
          <article class="card ad-foto-item">
            <div class="ad-foto-thumb grande">${url ? `<img src="${escapeHtml(url)}" alt="" loading="lazy" />` : ''}</div>
            <p class="ad-card-nome">${escapeHtml(f.nome || 'sem nome')}</p>
            <p class="ad-card-meta">${meta}</p>
            <p class="ad-card-meta">${
              onde.length
                ? `no site: ${onde.map((o) => escapeHtml(o)).join('; ')}`
                : 'não está em nenhum lugar do site'
            }</p>
            ${
              !podeApagar
                ? ''
                : onde.length
                  ? `<p class="ad-dica">pra apagar essa foto, tira ela dos lugares acima primeiro.</p>`
                  : `<div class="ad-card-acoes"><button type="button" class="btn ghost sm" data-foto-apagar="${escapeHtml(f.id)}" data-foto-nome="${escapeHtml(f.nome || 'essa foto')}">apagar do acervo</button></div>`
            }
          </article>`;
      })
      .join('')}</div>`;
  }

  function desenhar() {
    corpo.innerHTML = `
      <div class="ad-fotos">
        <section class="ad-bloco">
          <div class="ad-bloco-head">
            <h2 class="title sm">os lugares do site</h2>
            <p class="ad-head-sub">${FOTOS_DO_SITE.length} lugares · ${lugares.size} com foto da casa</p>
          </div>
          <div class="notice info">
            <p>a foto de fábrica é a que veio com o site: enquanto ninguém troca um lugar, é ela que aparece, e "voltar pra de fábrica" traz ela de volta a qualquer hora.</p>
            <p>o vídeo de abertura da home e as telas que ainda são fundo colorido (loja, produto) não estão aqui: essas duas entram quando virarem foto.</p>
          </div>
          ${fotosPorPagina()
            .map(
              (grupo) => `
            <div class="ad-fotos-pagina">
              <h3 class="ad-fotos-pagina-nome">${escapeHtml(grupo.pagina)} <a class="ad-fotos-pagina-link" href="${escapeHtml(grupo.url)}" target="_blank" rel="noopener">ver a página</a></h3>
              <div class="ad-fotos-lista">${grupo.fotos.map(lugarHTML).join('')}</div>
            </div>`,
            )
            .join('')}
        </section>

        <section class="ad-bloco">
          <div class="ad-bloco-head">
            <h2 class="title sm">o acervo da casa</h2>
            <p class="ad-head-sub">${galeria.length} foto${galeria.length === 1 ? '' : 's'} guardada${galeria.length === 1 ? '' : 's'}</p>
          </div>
          ${
            !podeMexer
              ? ''
              : `<form class="card ad-form-recado" data-form-foto novalidate>
                   <div class="field">
                     <label for="f-arquivo">a foto</label>
                     <input id="f-arquivo" type="file" data-f-arquivo accept="image/jpeg,image/png,image/webp,image/avif" required />
                     <p class="ad-dica">jpg, png, webp ou avif, até 8 MB. quanto mais leve, mais rápido o site abre.</p>
                   </div>
                   <div class="field">
                     <label for="f-nome">como a casa chama essa foto</label>
                     <input id="f-nome" data-f-nome maxlength="80" placeholder="fachada no fim da tarde" required />
                   </div>
                   <div class="field">
                     <label for="f-alt">o que aparece nela</label>
                     <input id="f-alt" data-f-alt maxlength="220" placeholder="a fachada do Casa com as mesas na calçada e gente conversando" />
                     <p class="ad-dica">isso é o que quem não enxerga vai ouvir no lugar da foto, e o que aparece se ela não carregar. escreve como se estivesse contando pra alguém do outro lado do telefone.</p>
                   </div>
                   <div data-f-aviso></div>
                   <div class="ad-card-acoes">
                     <button type="submit" class="btn solid" data-f-salvar><i data-lucide="image-plus"></i> subir pro acervo</button>
                   </div>
                 </form>`
          }
          <div data-acervo>${acervoHTML()}</div>
        </section>
      </div>`;
    renderIcons();
    ligar();
  }

  function ligar() {
    $$('[data-foto-trocar]', corpo).forEach((b) => {
      b.addEventListener('click', async () => {
        const slot = b.dataset.fotoTrocar;
        const lugar = FOTOS_DO_SITE.find((l) => l.slot === slot);
        const escolhida = await escolherFotoDoAcervo(galeria, `${lugar.pagina} · ${lugar.local}`);
        if (!escolhida) return;
        b.disabled = true;
        try {
          await rpc('admin_foto_definir', { p_slot: slot, p_foto_id: escolhida });
          toast('foto trocada, já está no ar 💛');
          await carregar();
        } catch (e) {
          toast(e.message, 'erro');
          b.disabled = false;
        }
      });
    });

    $$('[data-foto-soltar]', corpo).forEach((b) => {
      b.addEventListener('click', async () => {
        b.disabled = true;
        try {
          await rpc('admin_foto_soltar', { p_slot: b.dataset.fotoSoltar });
          toast('voltou a foto de fábrica');
          await carregar();
        } catch (e) {
          toast(e.message, 'erro');
          b.disabled = false;
        }
      });
    });

    $$('[data-foto-apagar]', corpo).forEach((b) => {
      b.addEventListener('click', async () => {
        const ok = await confirmar({
          titulo: `apagar "${b.dataset.fotoNome}"?`,
          texto: 'o arquivo sai do acervo e não dá pra desfazer. pra usar de novo, seria subir outra vez.',
          ok: 'sim, apagar',
          tom: 'perigo',
        });
        if (!ok) return;
        b.disabled = true;
        try {
          // O banco primeiro: é ele que recusa apagar foto que ainda está em
          // algum lugar do site. Só depois o arquivo sai do Storage — na ordem
          // contrária, uma recusa deixaria o lugar apontando pra um arquivo que
          // não existe mais.
          const r = await rpc('admin_foto_remover', { p_id: b.dataset.fotoApagar });
          if (r?.caminho && supabase) {
            await supabase.storage.from(FOTOS_BUCKET).remove([r.caminho]);
          }
          toast('foto apagada do acervo');
          await carregar();
        } catch (e) {
          toast(e.message, 'erro');
          b.disabled = false;
        }
      });
    });

    const form = $('[data-form-foto]', corpo);
    form?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const aviso = $('[data-f-aviso]', form);
      const campoArquivo = $('[data-f-arquivo]', form);
      const arquivo = campoArquivo.files?.[0];
      const nome = $('[data-f-nome]', form).value.trim();
      aviso.innerHTML = '';
      if (!arquivo) {
        aviso.innerHTML = '<div class="notice err"><p>escolhe a foto no teu computador 💛</p></div>';
        return;
      }
      if (!nome) {
        aviso.innerHTML = '<div class="notice err"><p>dá um nome pra foto, pra achar ela depois.</p></div>';
        return;
      }
      const botao = $('[data-f-salvar]', form);
      botao.disabled = true;
      botao.textContent = 'subindo…';
      try {
        await subirFotoDoSite({ arquivo, nome, alt: $('[data-f-alt]', form).value.trim() });
        toast('foto no acervo 💛');
        await carregar();
      } catch (e2) {
        aviso.innerHTML = `<div class="notice err"><p>${escapeHtml(e2.message)}</p></div>`;
        botao.disabled = false;
        botao.innerHTML = '<i data-lucide="image-plus"></i> subir pro acervo';
        renderIcons();
      }
    });
  }

  async function carregar() {
    carregando(corpo, 'buscando as fotos…');
    try {
      const dados = await rpc('admin_fotos_painel');
      galeria = Array.isArray(dados?.galeria) ? dados.galeria : [];
      lugares = new Map((Array.isArray(dados?.lugares) ? dados.lugares : []).map((l) => [l.slot, l]));
      desenhar();
    } catch (e) {
      erroNaTela(corpo, e);
    }
  }

  await carregar();
}

// ===== FAVORITOS (o que a casa mais ama) ============================
// Os itens do cardápio mais favoritados. Trava por tem_permissao('relatorios')
// no banco (0027); o agregado usa o nome mais frequente por slug (defesa contra
// snapshot adulterado). Só leitura — nenhuma baixa.
async function viewFavoritos(view) {
  view.innerHTML =
    cabecalho(
      'o que a casa mais ama',
      'os itens do cardápio que mais viraram favorito de quem vem.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    '<div data-corpo></div>';
  const corpo = $('[data-corpo]', view);
  $('[data-recarregar]', view).addEventListener('click', () => carregarFavoritos(corpo));
  renderIcons();
  carregarFavoritos(corpo);
}

async function carregarFavoritos(corpo) {
  carregando(corpo);
  try {
    const linhas = await rpc('admin_cardapio_favoritos');
    if (!linhas || !linhas.length) {
      corpo.innerHTML = vazio(
        'ninguém favoritou ainda',
        'quando alguém marcar um item no cardápio, ele aparece aqui, do mais amado pro menos.',
      );
      return;
    }
    const max = Math.max(...linhas.map((l) => Number(l.favoritos) || 0), 1);
    corpo.innerHTML = `<div class="ad-fav-lista">${linhas.map((l, i) => cardFav(l, i, max)).join('')}</div>`;
    renderIcons();
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

function cardFav(l, i, max) {
  const n = Number(l.favoritos) || 0;
  const pct = Math.max(6, Math.round((n / max) * 100));
  return `
    <div class="ad-fav-row">
      <span class="ad-fav-pos">${i + 1}</span>
      <div class="ad-fav-main">
        <p class="ad-fav-nome">${escapeHtml(l.item_nome || l.item_slug || 'item')}</p>
        <div class="ad-fav-bar"><span style="width:${pct}%"></span></div>
      </div>
      <span class="ad-fav-n"><i data-lucide="heart"></i>${formatNumero(n)}</span>
    </div>`;
}

// ===== DESEJOS DA LOJA ("o que a casa mais quer") ==================
async function viewDesejos(view) {
  view.innerHTML =
    cabecalho(
      'o que a casa mais quer',
      'os produtos da loja que mais viraram "ficou pra depois" de quem vem.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    '<div data-corpo></div>';
  const corpo = $('[data-corpo]', view);
  $('[data-recarregar]', view).addEventListener('click', () => carregarDesejos(corpo));
  renderIcons();
  carregarDesejos(corpo);
}

async function carregarDesejos(corpo) {
  carregando(corpo);
  try {
    const linhas = await rpc('admin_loja_desejos');
    if (!linhas || !linhas.length) {
      corpo.innerHTML = vazio(
        'ninguém guardou nada ainda',
        'quando alguém guardar um produto pra depois, ele aparece aqui, do mais desejado pro menos.',
      );
      return;
    }
    const max = Math.max(...linhas.map((l) => Number(l.desejos) || 0), 1);
    corpo.innerHTML = `<div class="ad-fav-lista">${linhas.map((l, i) => cardDesejo(l, i, max)).join('')}</div>`;
    renderIcons();
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

function cardDesejo(l, i, max) {
  const n = Number(l.desejos) || 0;
  const pct = Math.max(6, Math.round((n / max) * 100));
  return `
    <div class="ad-fav-row">
      <span class="ad-fav-pos">${i + 1}</span>
      <div class="ad-fav-main">
        <p class="ad-fav-nome">${escapeHtml(l.produto_nome || l.produto_slug || 'produto')}</p>
        <div class="ad-fav-bar"><span style="width:${pct}%"></span></div>
      </div>
      <span class="ad-fav-n"><i data-lucide="bookmark"></i>${formatNumero(n)}</span>
    </div>`;
}

// ===== ESPERANDO REPOSIÇÃO ("quem espera o quê") ===================
async function viewReposicao(view) {
  view.innerHTML =
    cabecalho(
      'quem espera reposição',
      'os produtos esgotados que mais gente pediu pra avisar quando voltar, o teu norte pra repor.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    '<div data-corpo></div>';
  const corpo = $('[data-corpo]', view);
  $('[data-recarregar]', view).addEventListener('click', () => carregarReposicao(corpo));
  renderIcons();
  carregarReposicao(corpo);
}

async function carregarReposicao(corpo) {
  carregando(corpo);
  try {
    const linhas = await rpc('admin_avisos_reposicao');
    if (!linhas || !linhas.length) {
      corpo.innerHTML = vazio(
        'ninguém esperando por enquanto',
        'quando alguém pedir pra ser avisado de um produto esgotado, ele aparece aqui, do mais esperado pro menos.',
      );
      return;
    }
    const max = Math.max(...linhas.map((l) => Number(l.esperando) || 0), 1);
    corpo.innerHTML = `<div class="ad-fav-lista">${linhas.map((l, i) => cardReposicao(l, i, max)).join('')}</div>`;
    renderIcons();
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

function cardReposicao(l, i, max) {
  const n = Number(l.esperando) || 0;
  const pct = Math.max(6, Math.round((n / max) * 100));
  return `
    <div class="ad-fav-row">
      <span class="ad-fav-pos">${i + 1}</span>
      <div class="ad-fav-main">
        <p class="ad-fav-nome">${escapeHtml(l.produto_nome || l.produto_slug || 'produto')}</p>
        <div class="ad-fav-bar"><span style="width:${pct}%"></span></div>
      </div>
      <span class="ad-fav-n"><i data-lucide="bell-ring"></i>${formatNumero(n)}</span>
    </div>`;
}

// ===== LISTA DE ESPERA ("quem deixou o e-mail") ====================
// O campinho do rodapé do site (initListaEspera no app.js) grava em
// `lista_espera` (0031), que ninguém lê pelo client — nem quem está logado. A
// leitura mora aqui, pela RPC gated por 'relatorios'.
async function viewListaEspera(view) {
  view.innerHTML =
    cabecalho(
      'quem deixou o e-mail',
      'gente que pediu pra ser avisada quando a loja abrir de vez, da mais recente pra mais antiga.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    '<div data-corpo></div>';
  const corpo = $('[data-corpo]', view);
  $('[data-recarregar]', view).addEventListener('click', () => carregarListaEspera(corpo));
  renderIcons();
  carregarListaEspera(corpo);
}

async function carregarListaEspera(corpo) {
  carregando(corpo);
  try {
    const linhas = await rpc('admin_lista_espera');
    if (!linhas || !linhas.length) {
      corpo.innerHTML = vazio(
        'ninguém na fila ainda',
        'quando alguém deixar o e-mail no rodapé do site, ele aparece aqui.',
      );
      return;
    }
    corpo.innerHTML = `
      <section class="card ad-card">
        <p class="lbl">${formatNumero(linhas.length)} ${linhas.length === 1 ? 'e-mail' : 'e-mails'}</p>
        <div class="rows">
          ${linhas
            .map(
              (l) => `
            <div class="row">
              <div class="row-main">
                <span>${escapeHtml(l.email || '')}</span>
                ${l.origem ? `<span class="row-meta">deixou em ${escapeHtml(l.origem)}</span>` : ''}
              </div>
              <span class="row-meta">${escapeHtml(formatData(l.created_at, false))}</span>
              ${
                pode('espera.arrumar')
                  ? `<button type="button" class="btn ghost sm" data-espera-remover="${escapeHtml(l.id)}" data-email="${escapeHtml(l.email || '')}"><i data-lucide="trash-2"></i>tirar</button>`
                  : ''
              }
            </div>`,
            )
            .join('')}
        </div>
      </section>`;
    renderIcons();
    // "me tira dessa lista" é pedido comum e é direito de quem deixou o e-mail
    // (LGPD). Antes só saía com SQL na mão.
    $$('[data-espera-remover]', corpo).forEach((botao) =>
      botao.addEventListener('click', async () => {
        const certeza = await confirmar({
          titulo: 'tirar esse e-mail da lista?',
          texto: `${botao.dataset.email} some do banco. é o que fazer quando a pessoa pede pra sair.`,
          ok: 'sim, tirar',
          tom: 'perigo',
        });
        if (!certeza) return;
        botao.disabled = true;
        try {
          const r = await rpc('admin_espera_remover', { p_id: botao.dataset.esperaRemover });
          if (r?.ok === false) throw new Error(r.erro || 'não deu pra tirar agora');
          toast('pronto, saiu da lista');
          carregarListaEspera(corpo);
        } catch (e) {
          botao.disabled = false;
          toast(e?.message || 'não deu pra tirar agora', 'erro');
        }
      }),
    );
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

// ===== PRESENTES (planos dados de presente) =========================
// Só leitura, e de propósito: quem gera o código é o webhook, quem resgata é a
// pessoa na própria conta. Aqui a casa só ENXERGA — quantos saíram, quais já
// foram abertos, e se um código que alguém mostrou no balcão é de verdade.
// O bilhete que o comprador escreveu não vem na RPC (0041): é recado de uma
// pessoa pra outra.
const filtrosPresentes = { status: '', busca: '' };

async function viewPresentes(view) {
  view.innerHTML =
    cabecalho(
      'presentes do Casa',
      'os planos que alguém comprou pra dar. dá pra conferir se um código é válido e ver o que já foi aberto.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    `<form class="ad-busca" data-busca>
      <div class="field">
        <label for="busca-presente" class="sr-only">buscar por código, comprador ou quem resgatou</label>
        <input id="busca-presente" type="search" placeholder="código (CASA-XXXXXX), nome ou e-mail" autocomplete="off" spellcheck="false" />
      </div>
      <button type="submit" class="btn ghost sm"><i data-lucide="search"></i>buscar</button>
    </form>
    <div class="ad-filtros" role="group" aria-label="filtrar presentes">
      <button type="button" class="filtro" data-f-status="pago">esperando quem ganha</button>
      <button type="button" class="filtro" data-f-status="resgatado">já resgatados</button>
      <button type="button" class="filtro" data-f-status="pendente">pagamento pendente</button>
      <button type="button" class="filtro" data-f-status="">todos</button>
    </div>
    <div data-corpo></div>`;

  const corpo = $('[data-corpo]', view);
  const form = $('[data-busca]', view);
  const marcar = () =>
    $$('[data-f-status]', view).forEach((b) =>
      b.setAttribute('aria-pressed', String((b.dataset.fStatus || '') === filtrosPresentes.status)),
    );
  $$('[data-f-status]', view).forEach((b) =>
    b.addEventListener('click', () => {
      filtrosPresentes.status = b.dataset.fStatus || '';
      marcar();
      carregarPresentes(corpo);
    }),
  );
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    filtrosPresentes.busca = $('#busca-presente', form).value.trim();
    carregarPresentes(corpo);
  });
  $('[data-recarregar]', view).addEventListener('click', () => carregarPresentes(corpo));
  marcar();
  renderIcons();
  carregarPresentes(corpo);
}

async function carregarPresentes(corpo) {
  carregando(corpo);
  try {
    const linhas = await rpc('admin_presentes', {
      p_busca: filtrosPresentes.busca || null,
      p_status: filtrosPresentes.status || null,
    });
    if (!linhas || !linhas.length) {
      corpo.innerHTML = vazio(
        filtrosPresentes.busca ? 'nada com esse termo' : 'nenhum presente por aqui',
        filtrosPresentes.busca
          ? 'confere o código ou tenta pelo nome de quem comprou.'
          : 'quando alguém der um plano de presente pela /presentear, ele aparece aqui.',
      );
      return;
    }

    // O resumo em cima responde a pergunta que a casa faz primeiro ("quantos
    // saíram e quantos já foram abertos?") sem precisar contar card na mão.
    const abertos = linhas.filter((l) => l.status === 'resgatado').length;
    const esperando = linhas.filter((l) => l.status === 'pago').length;

    corpo.innerHTML = `
      <div class="ad-stats" style="margin-bottom: 20px">
        <div class="stat card"><p class="n">${formatNumero(linhas.length)}</p><p class="l">presentes na lista</p></div>
        <div class="stat card"><p class="n">${formatNumero(esperando)}</p><p class="l">esperando quem ganha</p></div>
        <div class="stat card"><p class="n">${formatNumero(abertos)}</p><p class="l">já resgatados</p></div>
      </div>
      <div class="ad-lista">${linhas.map(cardPresente).join('')}</div>`;
    renderIcons();
    $$('[data-presente-arrumar]', corpo).forEach((botao) => {
      botao.addEventListener('click', () => arrumarPresente(botao, corpo));
    });
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

// Os dois presentes que travam, e que antes só saíam com SQL na mão:
//   • pago sem código, quando o webhook caiu entre o pagamento e a
//     `marcar_presente_pago`. Quem pagou ficava com um presente que não existe;
//   • pendente que nunca fechou o checkout, entulhando a lista.
// Presente PAGO não se cancela por aqui: o código pode estar na mão de alguém.
async function arrumarPresente(botao, corpo) {
  const acao = botao.dataset.acao;
  const ok = await confirmar({
    titulo: acao === 'gerar_codigo' ? 'gerar o código desse presente?' : 'cancelar esse presente?',
    texto:
      acao === 'gerar_codigo'
        ? 'o presente foi pago e ficou sem código. isso cria o código pra entregar a quem comprou.'
        : 'o checkout nunca fechou, então ele sai da lista. presente pago não some por aqui.',
    ok: acao === 'gerar_codigo' ? 'sim, gerar' : 'sim, cancelar',
    tom: acao === 'gerar_codigo' ? '' : 'perigo',
  });
  if (!ok) return;
  botao.disabled = true;
  try {
    const r = await rpc('admin_presente_arrumar', { p_id: botao.dataset.presenteArrumar, p_acao: acao });
    if (r?.ok === false) {
      toast(r.erro || 'não deu pra arrumar esse presente', 'erro');
      botao.disabled = false;
      return;
    }
    toast(acao === 'gerar_codigo' ? `pronto, o código é ${r?.codigo || ''} 💛` : 'presente cancelado');
    carregarPresentes(corpo);
  } catch (e) {
    toast(e.message, 'erro');
    botao.disabled = false;
  }
}

function cardPresente(g) {
  const tag =
    g.status === 'resgatado'
      ? '<span class="tag green">resgatado</span>'
      : g.status === 'pago'
        ? '<span class="tag gold">esperando quem ganha</span>'
        : g.status === 'pendente'
          ? '<span class="tag">pagamento pendente</span>'
          : '<span class="tag">cancelado</span>';

  return `
    <article class="card ad-card">
      <div class="ad-card-topo">
        <div>
          <p class="ad-codigo">${escapeHtml(g.codigo || 'sem código ainda')}</p>
          <p class="ad-card-nome">${escapeHtml(g.tier_nome || g.tier_slug || 'plano')} · ${escapeHtml(formatBRL(g.valor_centavos))}</p>
        </div>
        <div class="ad-card-tags">${tag}</div>
      </div>
      <div class="ad-card-rodape">
        <div class="ad-card-info">
          <p class="ad-card-meta">deu de presente: ${escapeHtml(g.comprador_nome || 'conta apagada')}${
            g.comprador_email ? ' · ' + escapeHtml(g.comprador_email) : ''
          }</p>
          <p class="ad-card-meta">comprado em ${escapeHtml(formatData(g.created_at))}</p>
          ${
            g.resgatado_em
              ? `<p class="ad-card-meta ok"><i data-lucide="check"></i> aberto por ${escapeHtml(
                  g.resgatado_por_nome || 'alguém',
                )} em ${escapeHtml(formatData(g.resgatado_em))}</p>`
              : ''
          }
        </div>
        <div class="ad-card-acao">
          ${
            pode('presentes.arrumar') && g.status === 'pago' && !g.codigo
              ? `<button type="button" class="btn solid sm" data-presente-arrumar="${escapeHtml(g.id)}" data-acao="gerar_codigo"><i data-lucide="wrench"></i>gerar o código</button>`
              : ''
          }
          ${
            pode('presentes.arrumar') && g.status === 'pendente'
              ? `<button type="button" class="btn ghost sm" data-presente-arrumar="${escapeHtml(g.id)}" data-acao="cancelar"><i data-lucide="x"></i>cancelar</button>`
              : ''
          }
        </div>
      </div>
    </article>`;
}

// ===== ASSINATURAS ==================================================
// O clube é o principal benefício do site, e até a 0047 o console era CEGO pra
// ele: quando alguém ligava dizendo "paguei e não caiu", não havia tela nenhuma
// pra olhar. Aqui a casa VÊ. Mexer de verdade (pausar, retomar, subir e descer
// de plano) continua nas Edge Functions, que falam com o Asaas; o único conserto
// daqui é esticar o período já pago, que não cobra nem estorna nada.
const filtrosAssinaturas = { status: '', busca: '' };

const ROTULO_STATUS_ASSINATURA = {
  ativa: ['green', 'ativa'],
  pausada: ['gold', 'pausada'],
  cancelada: ['coral', 'encerrada'],
  pendente: ['', 'esperando pagamento'],
  trial: ['', 'teste'],
};

async function viewAssinaturas(view) {
  view.innerHTML =
    cabecalho(
      'as assinaturas',
      'quem é do clube, em que plano e até quando vale. é a tela pra abrir quando alguém liga perguntando do plano.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    `<form class="ad-busca" data-busca>
      <div class="field">
        <label for="busca-assinatura" class="sr-only">buscar por nome ou e-mail</label>
        <input id="busca-assinatura" type="search" placeholder="nome ou e-mail de quem assina" autocomplete="off" />
      </div>
      <button type="submit" class="btn ghost sm"><i data-lucide="search"></i>buscar</button>
    </form>
    <div class="ad-filtros" role="group" aria-label="filtrar assinaturas">
      <button type="button" class="filtro" data-f-status="ativa">ativas</button>
      <button type="button" class="filtro" data-f-status="pausada">pausadas</button>
      <button type="button" class="filtro" data-f-status="cancelada">encerradas</button>
      <button type="button" class="filtro" data-f-status="">todas</button>
    </div>
    <div data-corpo></div>`;

  const corpo = $('[data-corpo]', view);
  const form = $('[data-busca]', view);
  const marcar = () =>
    $$('[data-f-status]', view).forEach((b) =>
      b.setAttribute('aria-pressed', String((b.dataset.fStatus || '') === filtrosAssinaturas.status)),
    );
  $$('[data-f-status]', view).forEach((b) =>
    b.addEventListener('click', () => {
      filtrosAssinaturas.status = b.dataset.fStatus || '';
      marcar();
      carregarAssinaturas(corpo);
    }),
  );
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    filtrosAssinaturas.busca = $('#busca-assinatura', form).value.trim();
    carregarAssinaturas(corpo);
  });
  $('[data-recarregar]', view).addEventListener('click', () => carregarAssinaturas(corpo));
  marcar();
  renderIcons();
  carregarAssinaturas(corpo);
}

async function carregarAssinaturas(corpo) {
  carregando(corpo);
  try {
    const dados = await rpc('admin_assinaturas', {
      p_busca: filtrosAssinaturas.busca || null,
      p_status: filtrosAssinaturas.status || null,
    });
    const linhas = Array.isArray(dados) ? dados : [];
    if (!linhas.length) {
      corpo.innerHTML = vazio(
        filtrosAssinaturas.busca ? 'nada com esse termo' : 'nenhuma assinatura por aqui',
        filtrosAssinaturas.busca
          ? 'tenta outro nome ou e-mail.'
          : 'quando alguém assinar um plano, ele aparece nesta lista.',
      );
      return;
    }
    corpo.innerHTML = `
      <p class="lbl" style="margin-bottom: 14px">${formatNumero(linhas.length)} ${linhas.length === 1 ? 'assinatura' : 'assinaturas'}</p>
      <div class="ad-lista">${linhas.map(cardAssinatura).join('')}</div>`;
    renderIcons();
    $$('[data-assinatura-esticar]', corpo).forEach((botao) => {
      botao.addEventListener('click', () => esticarAssinatura(botao, corpo));
    });
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

function cardAssinatura(s) {
  const [cor, rotulo] = ROTULO_STATUS_ASSINATURA[s.status] || ['', s.status || '—'];
  const tags = [`<span class="tag ${cor}">${escapeHtml(rotulo)}</span>`];
  if (s.de_presente) tags.push('<span class="tag olive">presente</span>');
  if (!s.no_gateway && !s.de_presente) tags.push('<span class="tag">fora do gateway</span>');

  return `
    <article class="card ad-card">
      <div class="ad-card-topo">
        <div>
          <p class="ad-card-nome">${escapeHtml(s.pessoa || 'sem nome')}</p>
          <p class="ad-card-meta">${escapeHtml(s.email || '')}</p>
        </div>
        <div class="ad-card-tags">${tags.join('')}</div>
      </div>
      <div class="ad-card-rodape">
        <div class="ad-card-info">
          <p class="ad-card-meta">plano ${escapeHtml(s.plano || s.tier_slug || '')} · assinou em ${escapeHtml(formatData(s.criada_em, false))}</p>
          <p class="ad-card-meta">${
            s.vale_ate
              ? `${s.vencida ? 'venceu' : 'vale até'} ${escapeHtml(formatData(s.vale_ate, false))}`
              : 'sem data de fim registrada'
          }</p>
          ${
            s.descida_agendada
              ? `<p class="ad-card-meta">desce pro ${escapeHtml(s.descida_agendada)} na próxima renovação</p>`
              : ''
          }
        </div>
        <div class="ad-card-acao">
          ${
            pode('assinaturas.arrumar') && s.status !== 'cancelada'
              ? `<button type="button" class="btn ghost sm" data-assinatura-esticar="${escapeHtml(s.id)}" data-nome="${escapeHtml(s.pessoa || 'essa pessoa')}">
                   <i data-lucide="calendar-clock"></i>esticar o período
                 </button>`
              : ''
          }
        </div>
      </div>
    </article>`;
}

async function esticarAssinatura(botao, corpo) {
  const dias = await escolher({
    titulo: `quantos dias de cortesia pra ${botao.dataset.nome}?`,
    opcoes: [
      { valor: '7', rotulo: 'uma semana' },
      { valor: '15', rotulo: 'quinze dias' },
      { valor: '30', rotulo: 'um mês' },
    ],
    atual: null,
    rodape: '<p class="ad-dica">isso só faz o benefício durar mais deste lado. no Asaas a assinatura segue no ciclo dela, e nada é cobrado agora.</p>',
  });
  if (!dias) return;

  botao.disabled = true;
  try {
    const r = await rpc('admin_assinatura_esticar', { p_id: botao.dataset.assinaturaEsticar, p_dias: Number(dias) });
    if (r?.ok === false) {
      toast(r.erro || 'não deu pra esticar essa assinatura', 'erro');
      botao.disabled = false;
      return;
    }
    toast(`pronto, vale até ${formatData(r?.vale_ate, false)} 💛`);
    carregarAssinaturas(corpo);
  } catch (e) {
    toast(e.message, 'erro');
    botao.disabled = false;
  }
}

// ===== PONTOS =======================================================
// O `points_ledger` é append-only e é a fonte da verdade do saldo (0008). A casa
// não tinha como OLHAR o extrato de ninguém, nem como consertar quando o webhook
// do pagamento falhava e o ponto não caía; sobrava responder "não sei" pra quem
// perguntava. O ajuste é um LANÇAMENTO como qualquer outro, com motivo
// obrigatório: nada de `update` no saldo, que é só cache.
let pontosPessoa = null;

async function viewPontos(view) {
  view.innerHTML =
    cabecalho('os pontos', 'o saldo e o extrato de cada pessoa. procura por nome ou e-mail.') +
    `<form class="ad-busca" data-busca>
      <div class="field">
        <label for="busca-pontos" class="sr-only">buscar por nome ou e-mail</label>
        <input id="busca-pontos" type="search" placeholder="nome ou e-mail (pelo menos 3 letras)" autocomplete="off" />
      </div>
      <button type="submit" class="btn ghost sm"><i data-lucide="search"></i>buscar</button>
    </form>
    <div data-achados></div>
    <div data-extrato></div>`;

  const achados = $('[data-achados]', view);
  const extrato = $('[data-extrato]', view);
  const form = $('[data-busca]', view);
  renderIcons();

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const termo = $('#busca-pontos', form).value.trim();
    if (termo.length < 3) {
      achados.innerHTML = '<div class="notice warn"><p>escreve pelo menos 3 letras pra eu procurar.</p></div>';
      return;
    }
    carregando(achados, 'procurando…');
    extrato.innerHTML = '';
    try {
      const dados = await rpc('admin_pontos_pessoas', { p_busca: termo });
      const gente = Array.isArray(dados) ? dados : [];
      if (!gente.length) {
        achados.innerHTML = vazio('não achei ninguém', 'confere o nome ou o e-mail.');
        return;
      }
      achados.innerHTML = `
        <section class="card ad-card">
          <p class="lbl">quem eu achei</p>
          <div class="rows">
            ${gente
              .map(
                (g) => `
              <div class="row">
                <div class="row-main">
                  <span>${escapeHtml(g.nome || 'sem nome')}</span>
                  <span class="row-meta">${escapeHtml(g.email || '')}${g.plano ? ' · ' + escapeHtml(g.plano) : ''}</span>
                </div>
                <span class="row-val">${formatNumero(g.saldo)} pts</span>
                <button type="button" class="btn ghost sm" data-abrir-extrato="${escapeHtml(g.id)}">ver o extrato</button>
              </div>`,
              )
              .join('')}
          </div>
        </section>`;
      renderIcons();
      $$('[data-abrir-extrato]', achados).forEach((botao) =>
        botao.addEventListener('click', () => abrirExtrato(botao.dataset.abrirExtrato, extrato)),
      );
    } catch (err) {
      erroNaTela(achados, err);
    }
  });

}

async function abrirExtrato(userId, alvo) {
  pontosPessoa = userId;
  carregando(alvo, 'somando…');
  try {
    const d = await rpc('admin_pontos_extrato', { p_user_id: userId });
    if (!d || d.ok === false) {
      erroNaTela(alvo, new Error(d?.erro || 'não achei essa pessoa'));
      return;
    }
    const lancamentos = Array.isArray(d.lancamentos) ? d.lancamentos : [];
    // Saldo do cache diferente da soma do ledger é sintoma, não detalhe: quer
    // dizer que alguma escrita passou por fora da trigger. A tela conta em vez
    // de esconder atrás de um número só.
    const bate = Number(d.saldo_cache) === Number(d.saldo_ledger);

    alvo.innerHTML = `
      <section class="card ad-card" style="margin-top: 20px">
        <div class="ad-card-topo">
          <div>
            <p class="ad-card-nome">${escapeHtml(d.nome || 'sem nome')}</p>
            <p class="ad-card-meta">${escapeHtml(d.email || '')}${d.plano ? ' · ' + escapeHtml(d.plano) : ' · sem plano'}</p>
          </div>
          <div class="ad-card-tags"><span class="tag gold">${formatNumero(d.saldo_ledger)} pts</span></div>
        </div>

        ${
          bate
            ? ''
            : `<div class="notice warn"><p>o saldo guardado no perfil (${formatNumero(d.saldo_cache)}) não bate com a soma do extrato (${formatNumero(
                d.saldo_ledger,
              )}). quem vale é o extrato. me avisa que a gente conserta o cache.</p></div>`
        }

        ${
          pode('pontos.arrumar')
            ? `<form class="ad-ajuste" data-ajuste>
                 <p class="lbl">lançar um ajuste</p>
                 <div class="ad-recado-linha">
                   <div class="field ad-recado-prio">
                     <label for="aj-delta">pontos</label>
                     <input id="aj-delta" type="number" step="1" placeholder="50 ou -50" required />
                     <p class="ad-dica">negativo tira. até 5.000 por vez.</p>
                   </div>
                   <div class="field">
                     <label for="aj-motivo">motivo</label>
                     <input id="aj-motivo" maxlength="120" placeholder="o pagamento caiu e o ponto não" required />
                     <p class="ad-dica">isso fica no extrato da pessoa, escreve pensando em quem vai ler.</p>
                   </div>
                 </div>
                 <div data-aj-aviso></div>
                 <div class="ad-card-acoes">
                   <button type="submit" class="btn solid sm"><i data-lucide="sliders-horizontal"></i>lançar</button>
                 </div>
               </form>`
            : ''
        }

        <div class="divider"></div>
        <p class="lbl">o extrato</p>
        ${
          lancamentos.length
            ? `<div class="rows">
                 ${lancamentos
                   .map(
                     (l) => `
                   <div class="row">
                     <div class="row-main">
                       <span>${escapeHtml(l.motivo || 'lançamento')}</span>
                       <span class="row-meta">${escapeHtml(l.descricao || l.ref_type || '')} · ${escapeHtml(formatData(l.quando))}</span>
                     </div>
                     <span class="row-val">${Number(l.delta) > 0 ? '+' : ''}${formatNumero(l.delta)}</span>
                   </div>`,
                   )
                   .join('')}
               </div>`
            : vazio('nenhum ponto ainda', 'pontuar é coisa de quem assina, então conta sem plano não tem lançamento.')
        }
      </section>`;
    renderIcons();

    const ajuste = $('[data-ajuste]', alvo);
    ajuste?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const aviso = $('[data-aj-aviso]', ajuste);
      const delta = Number($('#aj-delta', ajuste).value);
      const motivo = $('#aj-motivo', ajuste).value.trim();
      aviso.innerHTML = '';
      if (!delta) {
        aviso.innerHTML = '<div class="notice err"><p>diz quantos pontos, pra mais ou pra menos.</p></div>';
        return;
      }
      if (motivo.length < 3) {
        aviso.innerHTML = '<div class="notice err"><p>escreve o motivo, é o que explica esse lançamento depois.</p></div>';
        return;
      }
      const ok = await confirmar({
        titulo: `lançar ${delta > 0 ? '+' : ''}${formatNumero(delta)} pontos?`,
        texto: `vai aparecer no extrato de ${d.nome || 'quem recebe'} como "${motivo}". o extrato é append-only, então um ajuste não se apaga, se corrige com outro.`,
        ok: 'sim, lançar',
      });
      if (!ok) return;
      try {
        const r = await rpc('admin_pontos_ajustar', { p_user_id: userId, p_delta: delta, p_motivo: motivo });
        if (r?.ok === false) {
          aviso.innerHTML = `<div class="notice err"><p>${escapeHtml(r.erro || 'não deu pra lançar agora')}</p></div>`;
          return;
        }
        toast(`pronto, saldo agora é ${formatNumero(r?.saldo || 0)} 💛`);
        abrirExtrato(userId, alvo);
      } catch (err) {
        aviso.innerHTML = `<div class="notice err"><p>${escapeHtml(err.message || 'não deu pra lançar agora')}</p></div>`;
      }
    });
  } catch (e) {
    erroNaTela(alvo, e);
  }
}

// ===== MURAL (moderação) ============================================
// O Mural do /o-casa é uma parede PÚBLICA, e até esta aba existir um recado
// ofensivo só saía rodando SQL na mão.
//
// A aba nasceu escrevendo DIRETO pela RLS (as policies da 0020 falam em
// `is_staff()`), e isso funcionava só pra quem é dono da casa: o console concede
// PERMISSÃO e nunca troca o PAPEL de ninguém, então quem recebia 'usuarios'
// continuava com role='cliente', via só os recados aprovados e batia na RLS ao
// tentar esconder ou apagar. A 0044 pôs a moderação em três funções gated por
// `tem_permissao('usuarios')`, como todas as outras abas — e nada foi promovido
// a staff, porque promover abriria junto pedidos, resgates e brindes.
//
// A trigger da 0036 continua valendo por baixo: `texto`, `autor_nome` e
// `user_id` são intocáveis. Dá pra esconder e apagar, nunca pra pôr na parede
// uma frase que a pessoa não escreveu.
const filtrosMural = { status: 'aprovado', busca: '' };

async function viewMural(view) {
  view.innerHTML =
    cabecalho(
      'o mural do Casa',
      'os recados que a turma deixou na parede do /o-casa. dá pra esconder o que não combina com a casa, e devolver depois.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    `<form class="ad-busca" data-busca>
      <div class="field">
        <label for="busca-mural" class="sr-only">buscar por recado ou autor</label>
        <input id="busca-mural" type="search" placeholder="um trecho do recado ou o nome de quem escreveu" autocomplete="off" spellcheck="false" />
      </div>
      <button type="submit" class="btn ghost sm"><i data-lucide="search"></i>buscar</button>
    </form>
    <div class="ad-filtros" role="group" aria-label="filtrar recados do mural">
      <button type="button" class="filtro" data-f-status="aprovado">na parede</button>
      <button type="button" class="filtro" data-f-status="oculto">escondidos</button>
      <button type="button" class="filtro" data-f-status="">todos</button>
    </div>
    <div data-corpo></div>`;

  const corpo = $('[data-corpo]', view);
  const form = $('[data-busca]', view);
  const marcar = () =>
    $$('[data-f-status]', view).forEach((b) =>
      b.setAttribute('aria-pressed', String((b.dataset.fStatus || '') === filtrosMural.status)),
    );
  $$('[data-f-status]', view).forEach((b) =>
    b.addEventListener('click', () => {
      filtrosMural.status = b.dataset.fStatus || '';
      marcar();
      carregarMural(corpo);
    }),
  );
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    filtrosMural.busca = $('#busca-mural', form).value.trim();
    carregarMural(corpo);
  });
  $('[data-recarregar]', view).addEventListener('click', () => carregarMural(corpo));
  marcar();
  renderIcons();
  carregarMural(corpo);
}

async function carregarMural(corpo) {
  carregando(corpo);
  try {
    const dados = await rpc('admin_mural_listar', {
      p_busca: filtrosMural.busca || null,
      p_status: filtrosMural.status || null,
    });
    const data = Array.isArray(dados) ? dados : [];

    if (!data.length) {
      // O vazio precisa dizer QUAL recorte veio vazio. "nenhum recado ainda" com
      // o filtro "na parede" ligado faz quem procura um recado que existe (mas
      // está escondido) concluir que ele sumiu do banco.
      const recorte = { aprovado: 'na parede', oculto: 'escondido' }[filtrosMural.status];
      corpo.innerHTML = vazio(
        filtrosMural.busca
          ? 'nada com esse termo'
          : recorte
            ? `nenhum recado ${recorte}`
            : 'nenhum recado ainda',
        filtrosMural.busca
          ? 'tenta outro trecho ou outro nome.'
          : recorte
            ? 'o mural pode ter recados no outro estado, dá uma olhada em "todos".'
            : 'quando a turma começar a escrever no mural do /o-casa, os recados aparecem aqui.',
      );
      return;
    }

    corpo.innerHTML = `
      <p class="lbl" style="margin-bottom: 14px">${formatNumero(data.length)} ${data.length === 1 ? 'recado' : 'recados'}</p>
      <div class="ad-lista">${data.map(cardRecadoMural).join('')}</div>`;
    ligarAcoesMural(corpo);
    renderIcons();
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

function cardRecadoMural(r) {
  const oculto = r.status === 'oculto';
  return `
    <article class="card ad-card" data-mural="${escapeHtml(r.id)}">
      <div class="ad-card-topo">
        <div>
          <p class="ad-card-nome">${escapeHtml(r.autor_nome || 'alguém do Casa')}</p>
          <p class="ad-card-meta">escreveu em ${escapeHtml(formatData(r.created_at))}</p>
        </div>
        <div class="ad-card-tags">
          ${oculto ? '<span class="tag">escondido</span>' : '<span class="tag green">na parede</span>'}
        </div>
      </div>
      <p class="ad-card-texto">${escapeHtml(r.texto || '')}</p>
      <div class="ad-card-rodape">
        <div class="ad-card-info"></div>
        <div class="ad-card-acao">
          ${
            pode('mural.arrumar')
              ? '<button type="button" class="btn ghost sm" data-mural-apagar><i data-lucide="trash-2"></i>apagar</button>'
              : ''
          }
          ${
            !pode('mural.mexer')
              ? ''
              : oculto
                ? `<button type="button" class="btn solid sm" data-mural-status="aprovado"><i data-lucide="undo-2"></i>devolver pra parede</button>`
                : `<button type="button" class="btn ghost sm" data-mural-status="oculto"><i data-lucide="eye-off"></i>esconder</button>`
          }
        </div>
      </div>
    </article>`;
}

function ligarAcoesMural(corpo) {
  const idDo = (botao) => botao.closest('[data-mural]')?.dataset.mural;

  $$('[data-mural-status]', corpo).forEach((botao) =>
    botao.addEventListener('click', async () => {
      const id = idDo(botao);
      if (!id) return;
      botao.disabled = true;
      const novo = botao.dataset.muralStatus;
      try {
        const r = await rpc('admin_mural_status', { p_id: id, p_status: novo });
        if (r && r.ok === false) throw new Error(r.erro || 'não deu pra mudar agora');
      } catch (e) {
        botao.disabled = false;
        toast(e.message || 'não deu pra mudar agora', 'erro');
        return;
      }
      toast(novo === 'oculto' ? 'recado escondido' : 'recado de volta na parede 💛');
      carregarMural(corpo);
    }),
  );

  // Apagar é o único caminho sem volta desta tela, então passa por confirmação.
  // Esconder resolve quase tudo e dá pra desfazer; apagar é pra o que não pode
  // ficar registrado nem escondido.
  $$('[data-mural-apagar]', corpo).forEach((botao) =>
    botao.addEventListener('click', async () => {
      const id = idDo(botao);
      if (!id) return;
      const certeza = await confirmar({
        titulo: 'apagar este recado de vez?',
        texto: 'ele some do banco e não tem como voltar. se for só pra tirar da parede, "esconder" resolve e dá pra desfazer.',
        ok: 'apagar',
        tom: 'perigo',
      });
      if (!certeza) return;
      botao.disabled = true;
      try {
        const r = await rpc('admin_mural_remover', { p_id: id });
        if (r && r.ok === false) throw new Error(r.erro || 'não deu pra apagar agora');
      } catch (e) {
        botao.disabled = false;
        toast(e.message || 'não deu pra apagar agora', 'erro');
        return;
      }
      toast('recado apagado');
      carregarMural(corpo);
    }),
  );
}

// ===== PEDIDOS DE EVENTO (a /eventos) ===============================
// Quem preencheu o formulário de "faz teu evento aqui". A conversa acontece no
// WhatsApp; esta tela é o arquivo, pra nenhum pedido se perder embaixo de trinta
// mensagens novas. O botão "já falei" é o que tira da fila.
const filtrosLeads = { status: 'novo', busca: '' };

async function viewLeadsEventos(view) {
  view.innerHTML =
    cabecalho(
      'quem quer fazer evento aqui',
      'os pedidos que chegaram pela página de eventos, do mais recente pro mais antigo.',
      `<button type="button" class="btn ghost sm" data-recarregar><i data-lucide="refresh-cw"></i>atualizar</button>`,
    ) +
    `<form class="ad-busca" data-busca>
      <div class="field">
        <label for="busca-lead" class="sr-only">buscar por nome, telefone ou tipo</label>
        <input id="busca-lead" type="search" placeholder="nome, telefone, e-mail ou tipo de evento" autocomplete="off" spellcheck="false" />
      </div>
      <button type="submit" class="btn ghost sm"><i data-lucide="search"></i>buscar</button>
    </form>
    <div class="ad-filtros" role="group" aria-label="filtrar pedidos de evento">
      <button type="button" class="filtro" data-f-status="novo">a responder</button>
      <button type="button" class="filtro" data-f-status="atendido">já falei</button>
      <button type="button" class="filtro" data-f-status="arquivado">arquivados</button>
      <button type="button" class="filtro" data-f-status="">todos</button>
    </div>
    <div data-corpo></div>`;

  const corpo = $('[data-corpo]', view);
  const form = $('[data-busca]', view);
  const marcar = () =>
    $$('[data-f-status]', view).forEach((b) =>
      b.setAttribute('aria-pressed', String((b.dataset.fStatus || '') === filtrosLeads.status)),
    );
  $$('[data-f-status]', view).forEach((b) =>
    b.addEventListener('click', () => {
      filtrosLeads.status = b.dataset.fStatus || '';
      marcar();
      carregarLeadsEventos(corpo);
    }),
  );
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    filtrosLeads.busca = $('#busca-lead', form).value.trim();
    carregarLeadsEventos(corpo);
  });
  $('[data-recarregar]', view).addEventListener('click', () => carregarLeadsEventos(corpo));
  marcar();
  renderIcons();
  carregarLeadsEventos(corpo);
}

async function carregarLeadsEventos(corpo) {
  carregando(corpo);
  try {
    const linhas = await rpc('admin_leads_evento', {
      p_busca: filtrosLeads.busca || null,
      p_status: filtrosLeads.status || null,
    });
    if (!linhas || !linhas.length) {
      corpo.innerHTML = vazio(
        filtrosLeads.busca ? 'nada com esse termo' : 'nenhum pedido por aqui',
        filtrosLeads.busca
          ? 'tenta outro nome ou telefone.'
          : 'quando alguém preencher o formulário da página de eventos, o pedido aparece aqui.',
      );
      return;
    }
    corpo.innerHTML = `
      <p class="lbl" style="margin-bottom: 14px">${formatNumero(linhas.length)} ${linhas.length === 1 ? 'pedido' : 'pedidos'}</p>
      <div class="ad-lista">${linhas.map(cardLead).join('')}</div>`;
    ligarAcoesLead(corpo);
    renderIcons();
  } catch (e) {
    erroNaTela(corpo, e);
  }
}

// A data pretendida vem como DATE (AAAA-MM-DD). Formatar na mão evita o drift de
// fuso do new Date, que num dia 01 devolveria o dia anterior.
function dataPretendida(v) {
  const p = String(v || '').split('-');
  return p.length === 3 ? `${p[2]}/${p[1]}/${p[0]}` : '';
}

function cardLead(l) {
  const tag =
    l.status === 'atendido'
      ? '<span class="tag">já falei</span>'
      : l.status === 'arquivado'
        ? '<span class="tag">arquivado</span>'
        : '<span class="tag gold">a responder</span>';

  // O telefone vira link de WhatsApp: quem atende abre a conversa daqui mesmo,
  // sem copiar número na mão. Só dígitos, com o 55 na frente.
  const digitos = String(l.contato || '').replace(/\D/g, '');
  const zap = digitos.length >= 10 ? `https://wa.me/55${digitos.slice(-11)}` : null;

  const detalhes = [
    l.data_pretendida ? `📅 ${dataPretendida(l.data_pretendida)}` : 'sem data ainda',
    l.pessoas ? `👥 cerca de ${escapeHtml(String(l.pessoas))} pessoas` : null,
  ].filter(Boolean);

  return `
    <article class="card ad-card" data-lead="${escapeHtml(l.id)}">
      <div class="ad-card-topo">
        <div>
          <p class="ad-card-nome">${escapeHtml(l.nome || 'sem nome')}</p>
          <p class="ad-card-meta">${escapeHtml(l.tipo || '')} · ${escapeHtml(detalhes.join(' · '))}</p>
        </div>
        <div class="ad-card-tags">${tag}</div>
      </div>
      ${l.mensagem ? `<p class="ad-card-texto">${escapeHtml(l.mensagem)}</p>` : ''}
      <div class="ad-card-rodape">
        <div class="ad-card-info">
          <p class="ad-card-meta">
            ${
              zap
                ? `<a class="form-link" href="${zap}" target="_blank" rel="noopener noreferrer">${escapeHtml(l.contato)}</a>`
                : escapeHtml(l.contato || '')
            }${l.email ? ' · ' + escapeHtml(l.email) : ''}
          </p>
          <p class="ad-card-meta">pediu em ${escapeHtml(formatData(l.created_at))}${
            l.atendido_em ? ` · atendido em ${escapeHtml(formatData(l.atendido_em))}` : ''
          }</p>
        </div>
        <div class="ad-card-acao">
          ${
            !pode('leads.mexer')
              ? ''
              : l.status === 'novo'
                ? `<button type="button" class="btn ghost sm" data-lead-status="arquivado"><i data-lucide="archive"></i>arquivar</button>
                   <button type="button" class="btn solid sm" data-lead-status="atendido"><i data-lucide="check"></i>já falei</button>`
                : `<button type="button" class="btn ghost sm" data-lead-status="novo"><i data-lucide="rotate-ccw"></i>voltar pra fila</button>`
          }
          ${
            pode('leads.arrumar')
              ? '<button type="button" class="btn ghost sm" data-lead-apagar><i data-lucide="trash-2"></i>apagar</button>'
              : ''
          }
        </div>
      </div>
    </article>`;
}

function ligarAcoesLead(corpo) {
  $$('[data-lead-status]', corpo).forEach((botao) =>
    botao.addEventListener('click', async () => {
      const id = botao.closest('[data-lead]')?.dataset.lead;
      if (!id) return;
      botao.disabled = true;
      try {
        await rpc('admin_lead_evento_status', { p_id: id, p_status: botao.dataset.leadStatus });
        toast(botao.dataset.leadStatus === 'novo' ? 'voltou pra fila' : 'anotado 💛');
        carregarLeadsEventos(corpo);
      } catch (e) {
        botao.disabled = false;
        toast(e?.message || 'não deu pra mudar agora', 'erro');
      }
    }),
  );

  // Apagar é pra o pedido que a própria pessoa pediu pra tirar, e pra spam.
  // Arquivar resolve o resto e dá pra desfazer, então o texto oferece isso antes.
  $$('[data-lead-apagar]', corpo).forEach((botao) =>
    botao.addEventListener('click', async () => {
      const id = botao.closest('[data-lead]')?.dataset.lead;
      if (!id) return;
      const certeza = await confirmar({
        titulo: 'apagar este pedido de vez?',
        texto: 'nome, telefone e recado somem do banco e não tem como voltar. se for só pra tirar da fila, "arquivar" resolve.',
        ok: 'apagar',
        tom: 'perigo',
      });
      if (!certeza) return;
      botao.disabled = true;
      try {
        const r = await rpc('admin_lead_evento_remover', { p_id: id });
        if (r?.ok === false) throw new Error(r.erro || 'não deu pra apagar agora');
        toast('pedido apagado');
        carregarLeadsEventos(corpo);
      } catch (e) {
        botao.disabled = false;
        toast(e?.message || 'não deu pra apagar agora', 'erro');
      }
    }),
  );
}

// ===== TUA CONTA ====================================================
function viewConta(view) {
  const nome = estado.perms.nome || 'equipe';
  const papel = ROTULO_PAPEL[estado.perms.papel] || estado.perms.papel || '';
  // O `alcance` vem pronto do banco, agrupado por seção e página. Esta tela é
  // livre (qualquer pessoa do console abre), então ela não pode depender do
  // catálogo, que é da permissão `equipe.ver`.
  const alcance = Array.isArray(estado.perms.alcance) ? estado.perms.alcance : [];

  view.innerHTML =
    cabecalho('tua conta', 'a senha é tua; ninguém aqui consegue ver.') +
    `<div class="ad-duas">
      <section class="card ad-card">
        <p class="lbl">quem tu é por aqui</p>
        <p class="ad-card-nome">${escapeHtml(nome)}</p>
        <p class="ad-card-meta">${escapeHtml(estado.sessao?.user?.email || '')}</p>
        <p class="ad-card-meta">${escapeHtml(papel)}${estado.perms.master ? ' · conta do Casa, essa não some' : ''}</p>
        <div class="divider"></div>
        <p class="lbl">o que tu alcança</p>
        ${
          alcance.length
            ? `<ul class="ad-lista-simples">
                 ${alcance
                   .map(
                     (a) =>
                       `<li><i data-lucide="check"></i>${escapeHtml(a.secao)} · ${escapeHtml(a.pagina)}: ${escapeHtml(
                         (Array.isArray(a.acoes) ? a.acoes : []).join(', '),
                       )}</li>`,
                   )
                   .join('')}
               </ul>`
            : '<p class="ad-card-meta">ainda sem permissão nenhuma por aqui. quem cuida da equipe consegue te dar.</p>'
        }
      </section>

      <section class="card ad-card">
        <p class="lbl">trocar a senha</p>
        <div data-troca-senha></div>
      </section>
    </div>`;

  const caixa = $('[data-troca-senha]', view);
  caixa.innerHTML = formSenhaHTML();
  ligarFormSenha(caixa, () => {
    toast('senha trocada 💛');
    viewConta(view);
  });
  renderIcons();
}

// ===== BOOTSTRAP ====================================================
// Uma camada, duas páginas: a de entrada e o console. O pathname decide.
function bootstrap() {
  const caminho = window.location.pathname.replace(/\.html$/, '');
  if (caminho.endsWith('/admin/entrar') || caminho.endsWith('/admin/entrar/')) {
    initEntrar();
  } else {
    initConsole();
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', bootstrap);
} else {
  bootstrap();
}
