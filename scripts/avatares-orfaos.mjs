#!/usr/bin/env node
// =============================================================================
// Casa Coffee Colab — scripts/avatares-orfaos.mjs
// Acha (e, se mandarem, apaga) fotos do bucket "avatares" que ninguém usa mais.
//
// Por que isso existe: o Storage não tem cascata. Quando uma conta some por fora
// da delete-account, ou quando um upload sobe mas o update do perfil falha
// depois, o arquivo fica lá ocupando espaço sem dono nenhum apontando pra ele.
//
// Como decide o que é órfão: a fonte da verdade é profiles.avatar_url. Todo
// arquivo do bucket que NÃO é apontado por alguma linha de profiles é órfão —
// isso cobre de uma vez a pasta de conta apagada, a foto antiga que sobrou e o
// upload meio-caminho.
//
// Por padrão só RELATA (dry-run). Pra apagar de verdade: --apagar
//
// Uso (PowerShell — a service_role NUNCA vai pro .env do repo, só pro ambiente
// daquele comando):
//   $env:SUPABASE_URL="https://xxxx.supabase.co"
//   $env:SUPABASE_SERVICE_ROLE_KEY="eyJ..."
//   node scripts/avatares-orfaos.mjs            # só olha
//   node scripts/avatares-orfaos.mjs --apagar   # olha e limpa
//   node scripts/avatares-orfaos.mjs --horas=0  # ignora a janela de carência
// =============================================================================
import { createClient } from '@supabase/supabase-js';

const BUCKET = 'avatares';
const PAGINA = 100; // o list() do Storage devolve no máximo isso por chamada

// Carência: um arquivo recém-subido pode ser órfão só porque o update do perfil
// ainda não chegou (ou porque a pessoa está com a página aberta agora). Só
// consideramos lixo o que já passou dessa idade.
const GRACA_HORAS_PADRAO = 24;

// --- argumentos --------------------------------------------------------------
const args = process.argv.slice(2);
const apagar = args.includes('--apagar');
const horasArg = args.find((a) => a.startsWith('--horas='));
const gracaHoras = horasArg ? Number(horasArg.slice('--horas='.length)) : GRACA_HORAS_PADRAO;

if (!Number.isFinite(gracaHoras) || gracaHoras < 0) {
  console.error('✗ --horas precisa ser um número >= 0');
  process.exit(1);
}

// --- credenciais (só do ambiente, nunca do repo) -----------------------------
const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !serviceKey) {
  console.error('✗ faltam credenciais.');
  console.error('  Este script precisa da service_role (ele lê o bucket inteiro e a');
  console.error('  tabela profiles). Ela NÃO pode morar no .env do repo — passa só no');
  console.error('  ambiente do comando:');
  console.error('');
  console.error('    $env:SUPABASE_URL="https://xxxx.supabase.co"');
  console.error('    $env:SUPABASE_SERVICE_ROLE_KEY="eyJ..."');
  console.error('    node scripts/avatares-orfaos.mjs');
  console.error('');
  console.error('  A chave está no painel: Project Settings › API › service_role.');
  process.exit(1);
}

const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });

// --- helpers -----------------------------------------------------------------

// O list() pagina de 100 em 100; isto junta tudo de um prefixo.
async function listarTudo(prefixo) {
  const tudo = [];
  for (let offset = 0; ; offset += PAGINA) {
    const { data, error } = await supabase.storage.from(BUCKET).list(prefixo, {
      limit: PAGINA,
      offset,
      sortBy: { column: 'name', order: 'asc' },
    });
    if (error) throw error;
    tudo.push(...data);
    if (data.length < PAGINA) return tudo;
  }
}

// Da URL pública guardada em profiles.avatar_url, extrai o caminho dentro do
// bucket. A URL é ".../object/public/avatares/<uuid>/avatar?v=169…" — o ?v= é o
// nosso cache-buster e não faz parte do caminho.
function caminhoDaUrl(avatarUrl) {
  try {
    const { pathname } = new URL(avatarUrl);
    const marca = `/object/public/${BUCKET}/`;
    const i = pathname.indexOf(marca);
    if (i === -1) return null;
    return decodeURIComponent(pathname.slice(i + marca.length));
  } catch {
    return null;
  }
}

const formatarTamanho = (bytes) =>
  bytes >= 1024 * 1024
    ? `${(bytes / 1024 / 1024).toFixed(1)} MB`
    : `${Math.max(1, Math.round(bytes / 1024))} KB`;

// --- 1) tudo que existe no bucket -------------------------------------------
console.log(`Varrendo o bucket "${BUCKET}"…`);

const pastas = (await listarTudo('')).filter((e) => e.id === null); // pasta = id null
const arquivos = [];
for (const pasta of pastas) {
  for (const item of await listarTudo(pasta.name)) {
    if (item.id === null) continue; // subpasta: hoje não existe, mas não custa ignorar
    arquivos.push({
      caminho: `${pasta.name}/${item.name}`,
      dono: pasta.name, // a pasta É o user_id (a policy do Storage garante isso)
      bytes: item.metadata?.size ?? 0,
      quando: item.updated_at || item.created_at || null,
    });
  }
}
console.log(`  ${arquivos.length} arquivo(s) em ${pastas.length} pasta(s).`);

// --- 2) tudo que alguém aponta ----------------------------------------------
const referenciados = new Map(); // caminho → user_id que aponta
const donos = new Set();         // ids que existem em profiles
for (let from = 0; ; from += 1000) {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, avatar_url')
    .range(from, from + 999);
  if (error) {
    console.error('✗ não deu pra ler profiles:', error.message);
    process.exit(1);
  }
  for (const p of data) {
    donos.add(p.id);
    if (!p.avatar_url) continue;
    const caminho = caminhoDaUrl(p.avatar_url);
    if (caminho) referenciados.set(caminho, p.id);
  }
  if (data.length < 1000) break;
}
console.log(`  ${referenciados.size} foto(s) em uso, de ${donos.size} perfil(is).`);
console.log('');

// --- 3) cruza ----------------------------------------------------------------
const agora = Date.now();
const limite = agora - gracaHoras * 3600 * 1000;

const orfaos = [];
const novosDemais = [];
for (const a of arquivos) {
  if (referenciados.has(a.caminho)) continue;
  a.motivo = donos.has(a.dono) ? 'ninguém aponta pra ela' : 'a conta não existe mais';
  const quando = a.quando ? Date.parse(a.quando) : NaN;
  // Idade desconhecida (sem timestamp legível) = trata como RECENTE DEMAIS, não
  // apaga. Ferramenta destrutiva falha pro lado conservador: um arquivo sem data
  // pode ser upload recém-chegado, não um órfão antigo.
  if (!Number.isFinite(quando) || quando > limite) novosDemais.push(a);
  else orfaos.push(a);
}

// Referência quebrada: o perfil aponta pra um arquivo que não está mais lá. Não
// é lixo (não ocupa espaço), mas é um avatar que não carrega — vale saber.
const existentes = new Set(arquivos.map((a) => a.caminho));
const quebradas = [...referenciados].filter(([caminho]) => !existentes.has(caminho));

// --- 4) relatório ------------------------------------------------------------
if (novosDemais.length) {
  console.log(`⏳ ${novosDemais.length} arquivo(s) sem dono mas recente(s) demais (< ${gracaHoras}h) — deixei quieto:`);
  for (const a of novosDemais) console.log(`   ${a.caminho} · ${formatarTamanho(a.bytes)} · ${a.motivo}`);
  console.log('   (pode ser upload em andamento; roda de novo depois, ou use --horas=0)');
  console.log('');
}

if (quebradas.length) {
  console.log(`⚠ ${quebradas.length} perfil(is) apontam pra foto que não existe mais:`);
  for (const [caminho, id] of quebradas) console.log(`   ${id} → ${caminho}`);
  console.log('   (o avatar cai nas iniciais; some limpando o avatar_url ou subindo outra)');
  console.log('');
}

if (!orfaos.length) {
  console.log('✓ nenhuma foto órfã. o bucket tá limpo.');
  process.exit(0);
}

const total = orfaos.reduce((s, a) => s + a.bytes, 0);
console.log(`${orfaos.length} foto(s) órfã(s), ${formatarTamanho(total)} no total:`);
for (const a of orfaos) console.log(`   ${a.caminho} · ${formatarTamanho(a.bytes)} · ${a.motivo}`);
console.log('');

if (!apagar) {
  console.log('Nada foi apagado (isto é um relatório).');
  console.log('Pra limpar de verdade: node scripts/avatares-orfaos.mjs --apagar');
  process.exit(0);
}

// --- 5) apagar ---------------------------------------------------------------
console.log('Apagando…');
let apagados = 0;
for (let i = 0; i < orfaos.length; i += PAGINA) {
  const lote = orfaos.slice(i, i + PAGINA).map((a) => a.caminho);
  const { error } = await supabase.storage.from(BUCKET).remove(lote);
  if (error) {
    console.error(`✗ falhou num lote de ${lote.length}: ${error.message}`);
    console.error(`  (${apagados} já tinham sido apagados; roda de novo pra continuar)`);
    process.exit(1);
  }
  apagados += lote.length;
}
console.log(`✓ ${apagados} foto(s) apagada(s), ${formatarTamanho(total)} de volta.`);
