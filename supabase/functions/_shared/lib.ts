// =============================================================================
// Casa Coffee Colab — supabase/functions/_shared/lib.ts
// Fundação compartilhada das Edge Functions (Deno). Ver CLAUDE.md › Segurança.
//
// Gateway de pagamento: ASAAS (Pix + Cartão via Checkout hospedado).
//
// Segredos vivem SÓ nas env vars da function (supabase secrets), NUNCA no
// client/bundle/repo:
//   ASAAS_API_KEY, ASAAS_WEBHOOK_TOKEN, SITE_URL  → setados por nós.
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY       → injetados pelo Supabase.
//
// Código AGNÓSTICO DE AMBIENTE: o comportamento é idêntico em sandbox e produção
// — muda só a chave ($aact_hmlg_… ↔ $aact_prod_…) via secrets. A base da API é
// derivada do prefixo da chave (hmlg = sandbox), com override via ASAAS_BASE_URL.
// Nada de "if sandbox/if prod" no código.
// =============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.6';

// --- Env obrigatória (falha alto e cedo se faltar) ---------------------------
export function requireEnv(nome: string): string {
  const v = Deno.env.get(nome);
  if (!v) throw new Error(`env ausente: ${nome} (setar via supabase secrets set)`);
  return v;
}

// =============================================================================
// ASAAS — cliente REST minimalista (fetch + header access_token).
// A chave secreta vem da env (nunca do client/bundle). A base é derivada do
// prefixo: chaves de sandbox contêm "hmlg" (homologação). Override explícito
// via ASAAS_BASE_URL, se um dia precisar.
// =============================================================================
const ASAAS_API_KEY = requireEnv('ASAAS_API_KEY');

function asaasBaseUrl(): string {
  const override = Deno.env.get('ASAAS_BASE_URL');
  if (override) return override.replace(/\/+$/, '');
  // $aact_hmlg_… = sandbox (homologação); $aact_prod_… = produção.
  const isSandbox = /hmlg/i.test(ASAAS_API_KEY);
  return isSandbox ? 'https://api-sandbox.asaas.com/v3' : 'https://api.asaas.com/v3';
}

export class AsaasError extends Error {
  status: number;
  payload: unknown;
  constructor(message: string, status: number, payload: unknown) {
    super(message);
    this.name = 'AsaasError';
    this.status = status;
    this.payload = payload;
  }
}

// Chamada crua à API do Asaas. Lança AsaasError em status != 2xx.
export async function asaasFetch(path: string, init: RequestInit = {}): Promise<any> {
  const res = await fetch(`${asaasBaseUrl()}${path}`, {
    ...init,
    headers: {
      'access_token': ASAAS_API_KEY,
      'Content-Type': 'application/json',
      'User-Agent': 'CasaCoffeeColab/1.0',
      ...(init.headers ?? {}),
    },
  });

  const text = await res.text();
  let data: any = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }

  if (!res.ok) {
    const msg =
      data?.errors?.[0]?.description ?? data?.message ?? `Asaas respondeu ${res.status}`;
    throw new AsaasError(String(msg), res.status, data);
  }
  return data;
}

export const asaasPost = (path: string, body: unknown) =>
  asaasFetch(path, { method: 'POST', body: JSON.stringify(body) });
export const asaasGet = (path: string) => asaasFetch(path, { method: 'GET' });
export const asaasPut = (path: string, body: unknown) =>
  asaasFetch(path, { method: 'PUT', body: JSON.stringify(body) });
export const asaasDelete = (path: string) => asaasFetch(path, { method: 'DELETE' });

// Centavos (inteiro, como guardamos no banco) → reais decimais que o Asaas
// espera no campo `value` (ex.: 4990 → 49.90). Arredonda a 2 casas.
export function reaisFromCentavos(centavos: number): number {
  return Math.round(centavos) / 100;
}
// E o inverso, pra ler valores do Asaas (reais) de volta pra centavos inteiros.
export function centavosFromReais(reais: number): number {
  return Math.round(Number(reais) * 100);
}

// --- Supabase admin (service_role — ignora RLS; escrita server-side) ---------
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são injetados no ambiente da function.
export const supabaseAdmin = createClient(
  requireEnv('SUPABASE_URL'),
  requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
  { auth: { persistSession: false, autoRefreshToken: false } },
);

// --- CORS --------------------------------------------------------------------
export const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Responde o preflight OPTIONS; retorna null pros demais métodos (segue o fluxo).
export function handleCors(req: Request): Response | null {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  return null;
}

// --- Resposta JSON (sempre com CORS) -----------------------------------------
export function jsonResponse(body: unknown, status = 200, extra: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json', ...extra },
  });
}

// --- Auth: valida o JWT do Authorization header e retorna o user -------------
// Verifica a assinatura/validade do token via GoTrue (auth.getUser(jwt)). Só
// usuário autenticado passa. O PAPEL (role) nunca vem do token — quem precisar
// lê do profiles (banco). Retorna null se não houver token válido.
export async function getUserFromRequest(req: Request) {
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return null;
  const { data, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !data?.user) return null;
  return data.user;
}

// --- Base URL do site (montada server-side; nunca vinda do client) -----------
// successUrl/cancelUrl do checkout saem daqui. Idêntico em sandbox e prod —
// muda só o valor de SITE_URL no secrets (dev: http://localhost:5173).
export function getSiteUrl(): string {
  return requireEnv('SITE_URL').replace(/\/+$/, ''); // sem barra final
}

// =============================================================================
// CARRINHO — preço/validação SEMPRE do BANCO (nunca do client).
// O client manda só { product_slug, variant, qtd }. Aqui a gente busca o preço
// real em products/product_variants e soma o subtotal server-side. Ver CLAUDE.md
// › Segurança ("confiança zero no client"). GATEWAY-AGNÓSTICO (Stripe→Asaas não
// muda nada aqui).
// =============================================================================
export interface CartInputItem {
  product_slug: string;
  variant?: string | null; // opcao da product_variants (ex.: 'Moído p/ coado'), ou null
  qtd: number;
}
export interface CartLine {
  product_id: string;
  variant_id: string | null;
  product_slug: string;
  nome: string; // nome do produto (snapshot)
  variant_opcao: string | null; // opcao crua (pra resolver depois)
  variante_label: string | null; // 'Moagem: Moído p/ coado' (exibição/snapshot)
  unit_cents: number; // preço unitário já com delta da variante
  qtd: number;
}

export async function computeCartFromDb(
  items: CartInputItem[],
): Promise<{ lines: CartLine[]; subtotal_cents: number }> {
  if (!Array.isArray(items) || items.length === 0) throw new Error('carrinho vazio');
  if (items.length > 50) throw new Error('carrinho grande demais');

  const lines: CartLine[] = [];
  let subtotal = 0;

  for (const it of items) {
    const slug = String(it?.product_slug ?? '').trim();
    const qtd = Number(it?.qtd);
    if (!slug) throw new Error('item sem product_slug');
    if (!Number.isInteger(qtd) || qtd < 1 || qtd > 99) throw new Error('quantidade inválida');

    const { data: prod, error } = await supabaseAdmin
      .from('products')
      .select('id, slug, nome, preco_centavos, ativo')
      .eq('slug', slug)
      .maybeSingle();
    if (error) throw new Error('erro ao ler produto');
    if (!prod || !prod.ativo) throw new Error(`produto indisponível: ${slug}`);

    let unit = prod.preco_centavos;
    let variantId: string | null = null;
    let variantOpcao: string | null = null;
    let variantLabel: string | null = null;

    const opcao = it?.variant ? String(it.variant).trim() : '';
    if (opcao) {
      const { data: v } = await supabaseAdmin
        .from('product_variants')
        .select('id, rotulo, opcao, preco_delta_centavos, ativo')
        .eq('product_id', prod.id)
        .eq('opcao', opcao)
        .maybeSingle();
      if (!v || !v.ativo) throw new Error(`opção indisponível: ${opcao}`);
      variantId = v.id;
      variantOpcao = v.opcao;
      variantLabel = v.rotulo ? `${v.rotulo}: ${v.opcao}` : v.opcao;
      unit += v.preco_delta_centavos ?? 0;
    }

    subtotal += unit * qtd;
    lines.push({
      product_id: prod.id,
      variant_id: variantId,
      product_slug: prod.slug,
      nome: prod.nome,
      variant_opcao: variantOpcao,
      variante_label: variantLabel,
      unit_cents: unit,
      qtd,
    });
  }

  return { lines, subtotal_cents: subtotal };
}

// =============================================================================
// ESTADO DA ASSINATURA — benefício vigente AGORA.
// Uma assinatura concede benefício (desconto + multiplicador de pontos) quando:
//   • status = 'ativa'  (cobrando normalmente), OU
//   • status = 'pausada' E current_period_end ainda no futuro (período já pago —
//     o "cancelar" hoje é PAUSAR: o benefício segue até o fim do ciclo).
// Uma 'pausada' cujo período já venceu NÃO concede nada.
//
// Efeito colateral (self-heal, sem cron): se não há benefício vigente mas o
// profiles.tier_slug ainda aponta pra um tier, limpa (lazy) — assim o desconto
// da loja e o multiplicador de pontos zeram sozinhos quando a graça expira.
// Escrita via service_role (auth.uid()=null) → passa pelo prevent_points_tamper.
// =============================================================================
export interface EffectiveSubscription {
  id: string;
  tier_slug: string;
  status: string;
  current_period_end: string | null;
  asaas_subscription_id: string | null;
}

export async function getEffectiveSubscription(
  userId: string,
): Promise<EffectiveSubscription | null> {
  if (!userId) return null;
  const { data: subs } = await supabaseAdmin
    .from('subscriptions')
    .select('id, tier_slug, status, current_period_end, asaas_subscription_id')
    .eq('user_id', userId)
    .in('status', ['ativa', 'pausada'])
    .order('current_period_end', { ascending: false, nullsFirst: false });

  const rows = (subs ?? []) as EffectiveSubscription[];
  const now = Date.now();

  // Desempate: uma assinatura 'ativa' SEMPRE ganha de uma 'pausada', mesmo que a
  // pausada tenha current_period_end maior. Motivo: a 'ativa' é a que o Asaas
  // renova de verdade — é ela que o upgrade deve subir e que concede benefício.
  // A ordenação do banco (current_period_end desc) desempata DENTRO de cada grupo.
  const ativaMs = (r: EffectiveSubscription) => (r.status === 'ativa' ? 0 : 1);
  rows.sort((a, b) => ativaMs(a) - ativaMs(b)); // estável: preserva a ordem por período

  const granting =
    rows.find(
      (r) =>
        r.status === 'ativa' ||
        (r.status === 'pausada' &&
          !!r.current_period_end &&
          Date.parse(r.current_period_end) > now),
    ) ?? null;

  if (!granting) {
    // Nenhum benefício vigente → garante profiles.tier_slug limpo (idempotente).
    await supabaseAdmin.from('profiles').update({ tier_slug: null }).eq('id', userId);
  }
  return granting;
}

// Desconto do tier com benefício VIGENTE (via getEffectiveSubscription → gating
// por status/período, não confia no profiles.tier_slug cru). Sem benefício = 0%.
// Nunca vem do client.
export async function getUserTierDiscount(
  userId: string,
): Promise<{ tier_slug: string | null; discount_percent: number }> {
  const sub = await getEffectiveSubscription(userId);
  const slug = sub?.tier_slug ?? null;
  if (!slug) return { tier_slug: null, discount_percent: 0 };

  const { data: tier } = await supabaseAdmin
    .from('tiers')
    .select('slug, discount_percent, ativo')
    .eq('slug', slug)
    .maybeSingle();
  if (!tier || !tier.ativo) return { tier_slug: null, discount_percent: 0 };

  const pct = Number(tier.discount_percent ?? 0);
  return { tier_slug: tier.slug, discount_percent: pct > 0 && pct <= 100 ? pct : 0 };
}

// =============================================================================
// PONTOS (Fase 3) — crédito server-side, sempre pelo ledger (append-only).
// Regra: fidelidade é EXCLUSIVA de assinante. Só pontua quem tem plano ATIVO no
// momento da compra — aí ganha 1 ponto por R$1 × points_multiplier do tier. SEM
// assinatura = ZERO pontos (não é mais "1x"). floor (arredonda pra baixo). O
// trigger update_points_balance (0008) sincroniza o cache profiles.points_balance.
// Idempotente por (ref_type, ref_id) — UNIQUE no ledger (0008): reprocessar o
// evento não duplica. GATEWAY-AGNÓSTICO.
// =============================================================================
export async function getTierMultiplier(tierSlug: string | null): Promise<number> {
  if (!tierSlug) return 1;
  const { data } = await supabaseAdmin
    .from('tiers')
    .select('points_multiplier')
    .eq('slug', tierSlug)
    .maybeSingle();
  const m = Number(data?.points_multiplier ?? 1);
  return m > 0 ? m : 1;
}

// Calcula floor(reais × multiplicador) e insere o crédito no ledger.
// Retorna os pontos creditados (0 se nada ou se já creditado — idempotência).
export async function creditPoints(args: {
  userId: string;
  valorCentavos: number;
  motivo: string;
  refType: string;
  refId: string;
  tierSlug: string | null;
}): Promise<number> {
  const { userId, valorCentavos, motivo, refType, refId, tierSlug } = args;
  if (!userId || !valorCentavos || valorCentavos <= 0) return 0;

  // Fidelidade é EXCLUSIVA de assinante: sem tier vigente (nenhum plano ativo no
  // momento da compra) → 0 pontos. A LOJA passa order.tier_slug_aplicado, que é
  // null quando não havia assinatura no checkout; a cobrança da ASSINATURA sempre
  // passa o tier vigente. Assim, quem não tem plano não pontua — de propósito.
  if (!tierSlug) return 0;

  const mult = await getTierMultiplier(tierSlug);
  // 1 ponto por R$1 (valorCentavos/100) × multiplicador, arredondado PRA BAIXO.
  const pontos = Math.floor((valorCentavos * mult) / 100);
  if (pontos <= 0) return 0;

  const { error } = await supabaseAdmin.from('points_ledger').insert({
    user_id: userId,
    delta: pontos,
    motivo,
    descricao: motivo,
    ref_type: refType,
    ref_id: refId,
  });
  // 23505 = (ref_type, ref_id) já existe → já foi creditado. Idempotente, ok.
  if (error) {
    if (error.code === '23505') return 0;
    throw error;
  }
  return pontos;
}

// =============================================================================
// CONQUISTAS (Fase 3) — reavalia os emblemas do usuário via engine SQL.
// check_achievements (SECURITY DEFINER, 0009) roda como owner, avalia os
// critérios contra os dados reais (orders/tier/ledger/redemptions) e insere os
// cumpridos em user_achievements (ON CONFLICT DO NOTHING → idempotente).
// Best-effort: NUNCA lança — conquista é secundária e não pode derrubar o
// crédito de pontos nem o resgate. Chamada só server-side com o id do PRÓPRIO
// usuário. Retorna quantas conquistas NOVAS foram desbloqueadas.
// =============================================================================
export async function checkAchievements(userId: string): Promise<number> {
  if (!userId) return 0;
  const { data, error } = await supabaseAdmin.rpc('check_achievements', { p_user_id: userId });
  if (error) {
    console.error('[checkAchievements]', error);
    return 0;
  }
  return Number(data ?? 0);
}
