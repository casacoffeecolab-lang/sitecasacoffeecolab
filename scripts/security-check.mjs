#!/usr/bin/env node
// =============================================================================
// Casa Coffee Colab — scripts/security-check.mjs
// Gate de fim de leva (backend). Ver CLAUDE.md › Segurança. Roda estático (não
// conecta no banco). Sai != 0 se qualquer verificação falhar.
//
//   1) Sem chaves secretas versionadas em src/ e dist/.
//   2) .env não rastreado pelo git.
//   3) Migrations: RLS habilitada em TODA tabela criada.
//   4) Migrations: tabelas sensíveis sem policy pra anon e sem escrita pelo client
//      (o teste negativo ao vivo — anon não insere/lê — está em scripts/check-rls.sql).
//   5) npm audit sem vulnerabilidade high/critical.
// =============================================================================
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const problemas = [];
const fail = (msg) => problemas.push(msg);
const ok = (msg) => console.log(`  ✓ ${msg}`);

// --- util: lista arquivos recursivamente, ignorando dirs pesados ------------
function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    if (['node_modules', '.git', '.vite'].includes(name)) continue;
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

// =============================================================================
// 1) Chaves secretas em src/ e dist/ (código que vai pro cliente).
// Procuramos VALORES de segredo, não a palavra "service_role" (que aparece em
// comentários/SQL legitimamente).
// =============================================================================
console.log('1) Segredos em src/, dist/, supabase/ e scripts/');
const SECRET_PATTERNS = [
  // ASAAS — gateway atual. A API key vaza tudo; NUNCA pode ir pro client/repo.
  { re: /\$aact_[0-9A-Za-z_=+/-]{10,}/, nome: 'Asaas API key ($aact_)' },
  // Stripe — gateway antigo (aposentado), mas manter os padrões não custa nada
  // e continua barrando qualquer segredo desse tipo que apareça por engano.
  { re: /\bsk_live_[0-9a-zA-Z]{10,}/, nome: 'Stripe secret key (sk_live_)' },
  { re: /\bsk_test_[0-9a-zA-Z]{10,}/, nome: 'Stripe secret key (sk_test_)' },
  { re: /\brk_live_[0-9a-zA-Z]{10,}/, nome: 'Stripe restricted key (rk_live_)' },
  { re: /\bwhsec_[0-9a-zA-Z]{10,}/, nome: 'Stripe webhook secret (whsec_)' },
  { re: /\bAKIA[0-9A-Z]{16}\b/, nome: 'AWS access key id' },
];

// Atribuição explícita de segredo em código: `ASAAS_API_KEY = "..."`. Aqui o nome
// da variável não basta pra acusar — os READMEs e os cabeçalhos dos scripts estão
// cheios de exemplo de uso (`$env:SUPABASE_SERVICE_ROLE_KEY="eyJ..."`), que é
// documentação, não vazamento. Quem denuncia é o VALOR: um segredo de verdade é
// longo e não tem reticência, `<placeholder>` nem "xxx".
const ATRIB_RE = /(SERVICE_ROLE_KEY|ASAAS_API_KEY|ASAAS_WEBHOOK_TOKEN|STRIPE_SECRET_KEY|STRIPE_WEBHOOK_SECRET|POS_WEBHOOK_SECRET)\s*[:=]\s*['"]([^'"]+)['"]/g;
function pareceExemplo(valor) {
  if (valor.length < 16) return true; // curto demais pra ser chave de verdade
  return /\.\.\.|…|[<>]|\bxxx|\byour\b|\bseu\b|\bsua\b|_aqui\b|\btroca\b|\bcole\b/i.test(valor);
}

// JWTs do Supabase são todos "eyJ...". A ANON key é PÚBLICA e PODE ir pro bundle
// do client (a RLS é quem protege). Já a SERVICE_ROLE key jamais pode vazar.
// Então: decodifica o payload e só reprova se a role NÃO for anon/authenticated.
const JWT_RE = /\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}/g;
function papelDoJwt(token) {
  try {
    const payload = token.split('.')[1];
    const json = Buffer.from(payload.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
    return JSON.parse(json).role ?? null;
  } catch {
    return null;
  }
}

// `src/` e `dist/` são o que vai pro navegador, mas os segredos de verdade
// (ASAAS_API_KEY, ASAAS_WEBHOOK_TOKEN, service_role) moram em `supabase/functions/`
// e `scripts/` — os dois versionados. Varrer só o que vai pro client deixava o
// gate cego justamente onde um fallback do tipo `Deno.env.get('X') ?? '$aact_…'`
// apareceria, e ele passaria com ✓ e seria commitado.
const scanDirs = [
  join(ROOT, 'src'),
  join(ROOT, 'dist'),
  join(ROOT, 'supabase'),
  join(ROOT, 'scripts'),
];
let segredoAchado = false;
for (const dir of scanDirs) {
  for (const file of walk(dir)) {
    let txt;
    try { txt = readFileSync(file, 'utf8'); } catch { continue; }
    for (const { re, nome } of SECRET_PATTERNS) {
      if (re.test(txt)) {
        segredoAchado = true;
        fail(`segredo (${nome}) em ${relative(ROOT, file)}`);
      }
    }
    // Segredo atribuído literal: acusa só quando o valor não é exemplo, e só em
    // CÓDIGO. Num .md a linha quase sempre é a documentação do próprio comando de
    // `supabase secrets set`, com um valor inventado no lugar do segredo, e não
    // dá pra distinguir isso de um segredo por heurística de valor. Nada se perde:
    // chave de verdade colada num README continua caindo nas regras por FORMATO
    // ($aact_, sk_live_, AKIA) e no decodificador de JWT, que varrem todo arquivo.
    for (const m of file.endsWith('.md') ? [] : txt.matchAll(ATRIB_RE)) {
      if (pareceExemplo(m[2])) continue;
      segredoAchado = true;
      fail(`segredo (${m[1]} atribuído literal) em ${relative(ROOT, file)}`);
    }
    // JWTs: anon/authenticated OK; qualquer outra role (ex.: service_role) reprova.
    for (const m of txt.matchAll(JWT_RE)) {
      const papel = papelDoJwt(m[0]);
      if (papel === 'anon' || papel === 'authenticated') continue;
      segredoAchado = true;
      fail(`JWT com role "${papel || 'indecifrável'}" em ${relative(ROOT, file)} (só a anon key pode ir pro client)`);
    }
  }
}
if (!segredoAchado) ok('nenhum segredo no código versionado (anon key é permitida; service_role reprova)');
if (!existsSync(join(ROOT, 'dist'))) console.log('    (dist/ ausente — rode "npm run build" pra escanear o bundle também)');

// =============================================================================
// 2) .env não rastreado pelo git.
// =============================================================================
console.log('2) .env fora do git');
try {
  const tracked = execSync('git ls-files .env .env.* ', { cwd: ROOT }).toString().trim();
  const ruins = tracked.split('\n').map((s) => s.trim()).filter((s) => s && s !== '.env.example');
  if (ruins.length) fail(`arquivo(s) de env rastreado(s): ${ruins.join(', ')}`);
  else ok('.env não está versionado (.env.example é permitido)');
} catch {
  ok('git indisponível ou nenhum .env rastreado');
}

// =============================================================================
// 3) e 4) Análise das migrations.
// =============================================================================
console.log('3+4) RLS e policies nas migrations');
const migDir = join(ROOT, 'supabase', 'migrations');
const migFiles = existsSync(migDir) ? readdirSync(migDir).filter((f) => f.endsWith('.sql')).sort() : [];
const sql = migFiles.map((f) => readFileSync(join(migDir, f), 'utf8')).join('\n');

// tabelas criadas em public
const criadas = new Set();
// `if not exists` é OPCIONAL: uma tabela nova criada sem essa cláusula (SQL válido)
// também precisa ser detectada — senão ela escapa do gate de RLS e um `enable row
// level security` esquecido passaria batido.
for (const m of sql.matchAll(/create table\s+(?:if not exists\s+)?public\.(\w+)/gi)) criadas.add(m[1]);
// tabelas com RLS habilitada
const comRls = new Set();
for (const m of sql.matchAll(/alter table\s+public\.(\w+)\s+enable row level security/gi)) comRls.add(m[1]);

const semRls = [...criadas].filter((t) => !comRls.has(t));
if (semRls.length) fail(`tabelas criadas sem "enable row level security": ${semRls.join(', ')}`);
else ok(`RLS habilitada em todas as ${criadas.size} tabelas criadas`);

// policies: captura "create policy <nome> on public.<tabela> ... ;"
const policies = [];
for (const m of sql.matchAll(/create policy\s+(\w+)\s+on\s+public\.(\w+)([\s\S]*?);/gi)) {
  policies.push({ nome: m[1], tabela: m[2], corpo: m[3].toLowerCase() });
}

// Tabelas sensíveis: nada de anon; escrita só server-side (nenhuma policy de escrita).
const SENSIVEIS = new Set([
  'profiles', 'audit_log', 'subscriptions', 'orders', 'order_items',
  'points_ledger', 'redemptions', 'user_achievements',
  'coupons', 'pos_webhook_events', 'unclaimed_points',
  'stripe_events', 'asaas_events',
]);
let sensivelOk = true;
for (const pol of policies) {
  if (!SENSIVEIS.has(pol.tabela)) continue;
  if (/\bto\b[^;]*\banon\b/.test(pol.corpo) || /\bto\s+public\b/.test(pol.corpo)) {
    sensivelOk = false;
    fail(`policy "${pol.nome}" expõe tabela sensível ${pol.tabela} a anon/public`);
  }
  const escrita = /\bfor\s+(insert|update|delete|all)\b/.test(pol.corpo);
  // profiles tem update-self permitido (o cliente edita o próprio nome); o resto: só leitura.
  const excecao = pol.tabela === 'profiles' && pol.nome === 'profiles_update_self';
  if (escrita && !excecao) {
    sensivelOk = false;
    fail(`policy "${pol.nome}" permite escrita pelo client na tabela sensível ${pol.tabela}`);
  }
}
if (sensivelOk) ok('tabelas sensíveis sem exposição a anon e sem escrita pelo client');

// Garantia específica das novas tabelas de webhook/pontos não reclamados.
for (const t of ['pos_webhook_events', 'unclaimed_points']) {
  const pols = policies.filter((p) => p.tabela === t);
  const soOwnerSelect = pols.length > 0 && pols.every((p) => /for\s+select/.test(p.corpo) && /is_owner\(\)/.test(p.corpo));
  if (!soOwnerSelect) fail(`${t}: esperado só policy de SELECT restrita a is_owner() (achado: ${pols.map((p) => p.nome).join(', ') || 'nenhuma'})`);
  else ok(`${t}: só leitura do owner (anon barrado por deny-by-default)`);
}

// =============================================================================
// 5) npm audit (high/critical).
// =============================================================================
console.log('5) npm audit (high/critical)');
try {
  const raw = execSync('npm audit --json', { cwd: ROOT, stdio: ['ignore', 'pipe', 'ignore'] }).toString();
  const audit = JSON.parse(raw);
  const v = audit.metadata?.vulnerabilities || {};
  const graves = (v.high || 0) + (v.critical || 0);
  if (graves > 0) fail(`npm audit: ${v.critical || 0} critical, ${v.high || 0} high`);
  else ok(`npm audit sem high/critical (low: ${v.low || 0}, moderate: ${v.moderate || 0})`);
} catch (e) {
  // npm audit sai != 0 quando ACHA vulnerabilidade; tenta parsear o stdout mesmo assim.
  try {
    const audit = JSON.parse(e.stdout?.toString() || '{}');
    const v = audit.metadata?.vulnerabilities || {};
    const graves = (v.high || 0) + (v.critical || 0);
    if (graves > 0) fail(`npm audit: ${v.critical || 0} critical, ${v.high || 0} high`);
    else ok(`npm audit sem high/critical (low: ${v.low || 0}, moderate: ${v.moderate || 0})`);
  } catch {
    console.log('    (npm audit indisponível — pulei)');
  }
}

// =============================================================================
// Resultado
// =============================================================================
console.log('');
if (problemas.length) {
  console.error(`✗ security-check FALHOU (${problemas.length}):`);
  for (const p of problemas) console.error(`   - ${p}`);
  process.exit(1);
}
console.log('✓ security-check passou.');
