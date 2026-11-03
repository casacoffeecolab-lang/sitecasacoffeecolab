#!/usr/bin/env node
// =============================================================================
// Casa Coffee Colab — scripts/criar-adm-master.mjs
// Cria (uma vez só) a conta do adm master do console: o login "casa".
//
// Por que isso existe: o console é a única parte do site sem tela de cadastro —
// ninguém "se inscreve" como adm. A primeira conta tem que nascer por fora, com
// a service_role, porque ela precisa de duas coisas que nenhuma sessão logada
// pode se dar: role = 'owner' e master = true (a trigger protect_master_account
// da 0017 só deixa a flag mudar quando auth.uid() é nulo, ou seja, por aqui).
//
// O login é "casa", mas o Supabase Auth só entende e-mail — então a conta mora
// em casa@casacoffeecolab.com.br e o próprio console traduz login → e-mail na
// hora de entrar (loginParaEmail, em src/admin.js).
//
// A senha inicial é SORTEADA a cada execução e aparece uma vez só, aqui no
// terminal. Não existe senha padrão: uma senha combinada, escrita no repo, é uma
// porta aberta pra conta mais poderosa do sistema — quem lesse o arquivo entrava
// no endpoint do Auth direto e recebia um JWT de owner, sem passar por tela
// nenhuma. (Ver a 0032_senha_inicial_master, que é a outra metade da correção.)
//
// Enquanto essa senha inicial não for trocada de verdade, o BANCO não reconhece
// nenhum privilégio da conta: `is_owner`, `is_staff` e `tem_permissao` respondem
// falso, então nem o console nem o PostgREST entregam nada. Quem destrava é a
// troca real da senha, no Auth — o banco compara o hash guardado com o de agora,
// e não há RPC que minta sobre isso.
//
// Roda quantas vezes quiser: se a conta já existe, ele só confere e conta o que
// achou — não duplica, não mexe na senha (a menos que peçam --resetar-senha).
//
// Uso (PowerShell — a service_role NUNCA vai pro .env do repo, só pro ambiente
// daquele comando):
//   $env:SUPABASE_URL="https://xxxx.supabase.co"
//   $env:SUPABASE_SERVICE_ROLE_KEY="eyJ..."
//   node scripts/criar-adm-master.mjs                  # cria com senha sorteada
//   node scripts/criar-adm-master.mjs --senha="outra"  # cria com uma senha tua
//   node scripts/criar-adm-master.mjs --resetar-senha  # esqueceu? sorteia outra
//
// PRECISA das migrations 0017_admin (colunas `master` e `senha_alterada_em`) e
// 0032_senha_inicial_master (a trava no banco + a RPC registrar_senha_inicial).
// =============================================================================
import { randomBytes } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const EMAIL = 'casa@casacoffeecolab.com.br';
const LOGIN = 'casa';
const NOME = 'Casa';
const PAGINA = 200; // listUsers pagina; isto é o tamanho de cada página

// Senha inicial sorteada: 24 chars base64url, ~144 bits. Ela vive só nesta
// execução e no terminal de quem rodou — não vai pro repo nem pro banco (o banco
// guarda o hash que o Auth já guardaria de qualquer jeito).
function sortearSenha() {
  return randomBytes(18).toString('base64url');
}

// --- argumentos --------------------------------------------------------------
const args = process.argv.slice(2);
const resetarSenha = args.includes('--resetar-senha');
const senhaArg = args.find((a) => a.startsWith('--senha='));
const senha = senhaArg ? senhaArg.slice('--senha='.length) : sortearSenha();

if (senha.length < 6) {
  console.error('✗ a senha precisa ter pelo menos 6 caracteres (regra do Supabase Auth).');
  process.exit(1);
}

// --- credenciais (só do ambiente, nunca do repo) -----------------------------
const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !serviceKey) {
  console.error('✗ faltam credenciais.');
  console.error('  Este script precisa da service_role (ele cria um usuário no Auth e');
  console.error('  marca o master no profiles). Ela NÃO pode morar no .env do repo —');
  console.error('  passa só no ambiente do comando:');
  console.error('');
  console.error('    $env:SUPABASE_URL="https://xxxx.supabase.co"');
  console.error('    $env:SUPABASE_SERVICE_ROLE_KEY="eyJ..."');
  console.error('    node scripts/criar-adm-master.mjs');
  console.error('');
  console.error('  A chave está no painel: Project Settings › API › service_role.');
  process.exit(1);
}

const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });

// --- helpers -----------------------------------------------------------------

// O Auth não tem "buscar usuário por e-mail": só dá pra listar e procurar.
async function acharUsuarioPorEmail(email) {
  const alvo = email.toLowerCase();
  for (let page = 1; ; page += 1) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: PAGINA });
    if (error) throw error;
    const achado = data.users.find((u) => (u.email || '').toLowerCase() === alvo);
    if (achado) return achado;
    if (data.users.length < PAGINA) return null;
  }
}

// A linha do profiles nasce pela trigger handle_new_user, no mesmo insert do
// auth.users. Ainda assim damos algumas chances: se um dia a trigger sumir do
// banco, é melhor dizer isso em voz alta do que gravar pela metade.
async function esperarPerfil(id) {
  for (let tentativa = 1; tentativa <= 3; tentativa += 1) {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, full_name, role, master, senha_alterada_em')
      .eq('id', id)
      .maybeSingle();
    if (error) throw error;
    if (data) return data;
    await new Promise((r) => setTimeout(r, 300 * tentativa));
  }
  return null;
}

// --- 1) a conta já existe? ---------------------------------------------------
console.log(`Procurando a conta do adm master (${EMAIL})…`);

let usuario;
try {
  usuario = await acharUsuarioPorEmail(EMAIL);
} catch (e) {
  console.error(`✗ não deu pra listar os usuários do Auth: ${e.message}`);
  process.exit(1);
}

let criado = false;
if (!usuario) {
  const { data, error } = await supabase.auth.admin.createUser({
    email: EMAIL,
    password: senha,
    email_confirm: true, // e-mail interno: não existe caixa de entrada pra confirmar
    user_metadata: { full_name: NOME },
  });
  if (error) {
    console.error(`✗ não deu pra criar a conta: ${error.message}`);
    process.exit(1);
  }
  usuario = data.user;
  criado = true;
  console.log(`  conta criada. id: ${usuario.id}`);
} else {
  console.log(`  já existe. id: ${usuario.id}`);
}

// --- 2) senha ----------------------------------------------------------------
// Numa conta que já existe a gente não encosta na senha: ela já pode ter sido
// trocada no painel. Só com --resetar-senha, que é o caminho de quem esqueceu
// (o e-mail é interno, então "esqueci a senha" não chega em lugar nenhum).
if (!criado && resetarSenha) {
  const { error } = await supabase.auth.admin.updateUserById(usuario.id, { password: senha });
  if (error) {
    console.error(`✗ não deu pra repor a senha: ${error.message}`);
    process.exit(1);
  }
  console.log('  senha reposta.');
}

// --- 3) o perfil: owner + master --------------------------------------------
let perfil;
try {
  perfil = await esperarPerfil(usuario.id);
} catch (e) {
  console.error(`✗ não deu pra ler o profiles: ${e.message}`);
  process.exit(1);
}

if (!perfil) {
  console.error('✗ a conta foi criada no Auth mas a linha do profiles não apareceu.');
  console.error('  A trigger handle_new_user (migration 0001) deveria criá-la. Confere');
  console.error('  se ela está no banco antes de rodar de novo.');
  process.exit(1);
}

// Um update só: enquanto `master` ainda é false, a trigger deixa o role mudar
// junto. Depois de marcado, ela passa a proteger o papel — por isso as duas
// coisas vão na mesma ida.
const mudancas = {};
if (perfil.role !== 'owner') mudancas.role = 'owner';
if (!perfil.master) mudancas.master = true;
if (!perfil.full_name) mudancas.full_name = NOME;
// Se pediram pra repor a senha, o primeiro acesso volta a ser obrigatório.
if (!criado && resetarSenha) mudancas.senha_alterada_em = null;

if (Object.keys(mudancas).length) {
  const { error } = await supabase.from('profiles').update(mudancas).eq('id', usuario.id);
  if (error) {
    if (error.code === '23505') {
      console.error('✗ já existe OUTRA conta marcada como adm master neste banco.');
      console.error('  Só pode existir uma (índice profiles_master_unico, da 0017).');
      console.error('  Descobre quem é com:  select id, full_name from profiles where master;');
    } else if (error.message?.includes('0017')) {
      console.error(`✗ ${error.message}`);
    } else {
      console.error(`✗ não deu pra marcar o perfil: ${error.message}`);
      console.error('  Se ele reclamou de coluna inexistente, falta aplicar a migration');
      console.error('  supabase/migrations/0017_admin.sql no SQL Editor.');
    }
    process.exit(1);
  }
  console.log(`  perfil ajustado: ${Object.keys(mudancas).join(', ')}.`);
} else {
  console.log('  perfil já estava certinho.');
}

// --- 4) a trava da senha inicial ---------------------------------------------
// Guarda o hash da senha que acabou de nascer. É ele que a 0032 compara com o
// hash de agora pra saber se a troca aconteceu de verdade — sem esse registro a
// conta ficaria com privilégio de owner valendo desde o primeiro login, que é
// justamente o que a gente está fechando. O hash mora em auth.users, que o
// PostgREST não expõe, então quem copia é a RPC (service_role).
if (criado || resetarSenha) {
  const { error } = await supabase.rpc('registrar_senha_inicial', { p_user_id: usuario.id });
  if (error) {
    console.error('');
    console.error('✗ não deu pra registrar o hash da senha inicial:');
    console.error(`  ${error.message}`);
    console.error('');
    console.error('  Sem isso a conta entra no console JÁ com todo o poder de owner,');
    console.error('  antes de trocar a senha. Aplica a migration');
    console.error('  supabase/migrations/0032_senha_inicial_master.sql no SQL Editor e');
    console.error('  roda este comando de novo com --resetar-senha.');
    process.exit(1);
  }
  console.log('  trava da senha inicial registrada.');
}

// --- 5) relatório ------------------------------------------------------------
const precisaTrocar = criado || resetarSenha || !perfil.senha_alterada_em;

console.log('');
console.log('✓ adm master pronto.');
console.log('');
console.log(`   console:  /admin/entrar`);
console.log(`   login:    ${LOGIN}`);
if (criado || resetarSenha) {
  console.log(`   senha:    ${senha}`);
} else {
  console.log('   senha:    a que já estava lá (use --resetar-senha se esqueceu)');
}
console.log('');
if (precisaTrocar) {
  console.log('Essa senha aparece uma vez só, aqui. Copia ela agora: ela não fica');
  console.log('guardada em lugar nenhum e não dá pra pedir de volta (o e-mail é');
  console.log('interno, então "esqueci a senha" não chega em caixa nenhuma). Se');
  console.log('perder, roda de novo com --resetar-senha e sorteia outra.');
  console.log('');
  console.log('O console vai pedir uma senha nova no primeiro acesso, e até essa troca');
  console.log('acontecer a conta não tem poder nenhum: o banco recusa toda permissão');
  console.log('de owner enquanto a senha for esta. Trocou, destrava sozinho.');
} else {
  console.log('A senha já foi trocada no painel — essa conta está em uso normal.');
}
