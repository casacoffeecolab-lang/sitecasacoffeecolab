#!/usr/bin/env node
// =============================================================================
// Casa Coffee Colab — scripts/fotos-orfas.mjs
// Acha (e, se mandarem, apaga) arquivos do bucket "fotos-site" que ninguém usa.
// É o irmão do avatares-orfaos.mjs, pro acervo de fotos da 0054.
//
// POR QUE ISSO EXISTE: o Storage não tem cascata, e a aba "fotos" do console faz
// duas coisas em sequência que podem se separar no meio:
//   • subir uma foto é PRIMEIRO o arquivo, DEPOIS o `admin_foto_registrar`. Se a
//     segunda parte falhar (rede, sessão vencida, aba fechada), o arquivo fica
//     no bucket sem ficha nenhuma apontando pra ele.
//   • apagar do acervo é PRIMEIRO a linha (que o banco recusa se a foto estiver
//     em uso), DEPOIS o arquivo. Se a aba fechar entre uma coisa e outra, a
//     ficha some e o arquivo fica.
// Nos dois casos sobra um arquivo pago e invisível, que só um varredor acha.
//
// COMO DECIDE O QUE É ÓRFÃO: a fonte da verdade é o ACERVO (`fotos_galeria`),
// mais os LUGARES ocupados (`site_fotos`). Arquivo que nenhuma das duas aponta
// não existe pra ninguém, e é isso que este script chama de órfão.
//
// O QUE ELE NÃO CHAMA DE ÓRFÃO, DE PROPÓSITO: foto que está no acervo e não está
// em lugar nenhum do site. Isso não é lixo, é o acervo fazendo o trabalho dele —
// a casa sobe a foto uma vez e usa quando quiser, no mês que vem inclusive.
//
// Por padrão só RELATA (dry-run). Pra apagar de verdade: --apagar
//
// Uso (PowerShell — a service_role NUNCA vai pro .env do repo, só pro ambiente
// daquele comando):
//   $env:SUPABASE_URL="https://xxxx.supabase.co"
//   $env:SUPABASE_SERVICE_ROLE_KEY="eyJ..."
//   node scripts/fotos-orfas.mjs            # só olha
//   node scripts/fotos-orfas.mjs --apagar   # olha e limpa
//   node scripts/fotos-orfas.mjs --horas=0  # ignora a janela de carência
// =============================================================================
import { createClient } from '@supabase/supabase-js';

const BUCKET = 'fotos-site';
const PAGINA = 100; // o list() do Storage devolve no máximo isso por chamada

// O caminho é `ano/mes/nome-sufixo.ext` (ver o `subirFotoDoSite` do admin.js),
// então a varredura desce dois níveis. O limite existe pra o script não entrar
// em recursão infinita se um dia alguém subir uma árvore mais funda na mão.
const FUNDURA_MAX = 4;

// Carência: um arquivo recém-subido pode estar sem ficha só porque o
// `admin_foto_registrar` ainda não voltou. Só é lixo o que já passou dessa idade.
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
  console.error('  Este script precisa da service_role (ele lê o bucket inteiro e as');
  console.error('  tabelas fotos_galeria e site_fotos, que são deny-by-default). Ela NÃO');
  console.error('  pode morar no .env do repo — passa só no ambiente do comando:');
  console.error('');
  console.error('    $env:SUPABASE_URL="https://xxxx.supabase.co"');
  console.error('    $env:SUPABASE_SERVICE_ROLE_KEY="eyJ..."');
  console.error('    node scripts/fotos-orfas.mjs');
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

// Desce a árvore inteira. Pasta é a entrada com `id === null` (é assim que o
// Storage do Supabase diferencia pasta de arquivo).
async function varrer(prefixo = '', fundura = 0) {
  if (fundura >= FUNDURA_MAX) return [];
  const achados = [];
  for (const item of await listarTudo(prefixo)) {
    const caminho = prefixo ? `${prefixo}/${item.name}` : item.name;
    if (item.id === null) {
      achados.push(...(await varrer(caminho, fundura + 1)));
      continue;
    }
    achados.push({
      caminho,
      bytes: item.metadata?.size ?? 0,
      quando: item.updated_at || item.created_at || null,
    });
  }
  return achados;
}

// Lê uma tabela inteira, de mil em mil.
async function lerTudo(tabela, colunas) {
  const linhas = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await supabase.from(tabela).select(colunas).range(from, from + 999);
    if (error) {
      console.error(`✗ não deu pra ler ${tabela}: ${error.message}`);
      if (/does not exist|schema cache/i.test(error.message || '')) {
        console.error('  (parece que a migration 0054 ainda não foi aplicada neste banco)');
      }
      process.exit(1);
    }
    linhas.push(...data);
    if (data.length < 1000) return linhas;
  }
}

const formatarTamanho = (bytes) =>
  bytes >= 1024 * 1024
    ? `${(bytes / 1024 / 1024).toFixed(1)} MB`
    : `${Math.max(1, Math.round(bytes / 1024))} KB`;

// --- 1) tudo que existe no bucket -------------------------------------------
console.log(`Varrendo o bucket "${BUCKET}"…`);
const arquivos = await varrer();
console.log(`  ${arquivos.length} arquivo(s).`);

// --- 2) tudo que alguém aponta ----------------------------------------------
const acervo = new Map(); // caminho → nome que a casa deu
for (const f of await lerTudo('fotos_galeria', 'caminho, nome')) acervo.set(f.caminho, f.nome);

const emUso = new Map(); // caminho → lugares do site que mostram essa foto
for (const s of await lerTudo('site_fotos', 'slot, caminho')) {
  if (!emUso.has(s.caminho)) emUso.set(s.caminho, []);
  emUso.get(s.caminho).push(s.slot);
}

console.log(`  ${acervo.size} no acervo, ${emUso.size} em ${[...emUso.values()].flat().length} lugar(es) do site.`);
console.log('');

// --- 3) cruza ----------------------------------------------------------------
const agora = Date.now();
const limite = agora - gracaHoras * 3600 * 1000;

const orfaos = [];
const novosDemais = [];
for (const a of arquivos) {
  if (acervo.has(a.caminho) || emUso.has(a.caminho)) continue;
  const quando = a.quando ? Date.parse(a.quando) : NaN;
  // Idade desconhecida (sem timestamp legível) = trata como RECENTE DEMAIS, não
  // apaga. Ferramenta destrutiva falha pro lado conservador: um arquivo sem data
  // pode ser upload recém-chegado, não um órfão antigo.
  if (!Number.isFinite(quando) || quando > limite) novosDemais.push(a);
  else orfaos.push(a);
}

// Referência quebrada. No acervo é chateação (a miniatura do console não
// carrega); num LUGAR DO SITE é buraco na página pública, e por isso a lista é
// separada e vem primeiro.
const existentes = new Set(arquivos.map((a) => a.caminho));
const acervoQuebrado = [...acervo].filter(([caminho]) => !existentes.has(caminho));
const siteQuebrado = [...emUso].filter(([caminho]) => !existentes.has(caminho));

// --- 4) relatório ------------------------------------------------------------
if (siteQuebrado.length) {
  console.log(`⚠ ${siteQuebrado.length} LUGAR(ES) DO SITE apontam pra arquivo que não existe:`);
  for (const [caminho, slots] of siteQuebrado) console.log(`   ${slots.join(', ')} → ${caminho}`);
  console.log('   (isso é foto quebrada na página pública. no console, "voltar pra de');
  console.log('   fábrica" nesse lugar resolve na hora, ou escolhe outra foto do acervo)');
  console.log('');
}

if (acervoQuebrado.length) {
  console.log(`⚠ ${acervoQuebrado.length} foto(s) do acervo sem arquivo no bucket:`);
  for (const [caminho, nome] of acervoQuebrado) console.log(`   "${nome}" → ${caminho}`);
  console.log('   (a miniatura não carrega no console; dá pra apagar a ficha por lá)');
  console.log('');
}

if (novosDemais.length) {
  console.log(`⏳ ${novosDemais.length} arquivo(s) sem ficha mas recente(s) demais (< ${gracaHoras}h) — deixei quieto:`);
  for (const a of novosDemais) console.log(`   ${a.caminho} · ${formatarTamanho(a.bytes)}`);
  console.log('   (pode ser upload em andamento; roda de novo depois, ou use --horas=0)');
  console.log('');
}

if (!orfaos.length) {
  console.log('✓ nenhum arquivo órfão. o bucket tá limpo.');
  process.exit(0);
}

const total = orfaos.reduce((s, a) => s + a.bytes, 0);
console.log(`${orfaos.length} arquivo(s) órfão(s), ${formatarTamanho(total)} no total:`);
for (const a of orfaos) console.log(`   ${a.caminho} · ${formatarTamanho(a.bytes)}`);
console.log('   (nenhum deles está no acervo nem em lugar nenhum do site)');
console.log('');

if (!apagar) {
  console.log('Nada foi apagado (isto é um relatório).');
  console.log('Pra limpar de verdade: node scripts/fotos-orfas.mjs --apagar');
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
console.log(`✓ ${apagados} arquivo(s) apagado(s), ${formatarTamanho(total)} de volta.`);
