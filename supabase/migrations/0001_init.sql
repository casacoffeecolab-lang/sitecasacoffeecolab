-- =============================================================================
-- Casa Coffee Colab — 0001_init.sql
-- Tabelas + índices + funções auxiliares (is_staff / is_gerente_or_owner /
-- is_owner) + triggers (handle_new_user, prevent_role_change).
--
-- APPEND-ONLY e IMUTÁVEL: depois de aplicada, nunca edite. Mudança = migration nova.
-- Autocontida e idempotente (IF NOT EXISTS / CREATE OR REPLACE) onde dá.
-- RLS é ligada na 0002. Seed é a 0003.
-- =============================================================================

-- gen_random_uuid() é nativo do Postgres 13+ (usado pelo Supabase). Sem extensão extra.

-- -----------------------------------------------------------------------------
-- Papéis do usuário (fonte confiável = coluna profiles.role, NUNCA o client).
--   cliente < staff < gerente < owner
-- -----------------------------------------------------------------------------

-- profiles — estende auth.users (1:1). Criado no signup pela trigger handle_new_user.
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text,
  role        text not null default 'cliente'
              check (role in ('cliente', 'staff', 'gerente', 'owner')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- audit_log — trilha de auditoria. Escrita só server-side / por trigger. Só owner lê.
-- Criado cedo porque a trigger prevent_role_change grava aqui.
create table if not exists public.audit_log (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references auth.users (id) on delete set null,
  action      text not null,
  entity      text,
  entity_id   text,
  detalhe     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists idx_audit_log_created  on public.audit_log (created_at desc);
create index if not exists idx_audit_log_actor     on public.audit_log (actor_id);

-- -----------------------------------------------------------------------------
-- Catálogo / referência (leitura pública). Ver seed na 0003.
-- -----------------------------------------------------------------------------

-- tiers — os planos de assinatura (Bronze/Prata/Ouro/Diamante).
create table if not exists public.tiers (
  slug                    text primary key,
  nome                    text not null,
  preco_centavos          integer not null check (preco_centavos >= 0),
  desconto_pct            integer not null default 0 check (desconto_pct between 0 and 100),
  pontos_multiplicador    numeric(4,2) not null default 1 check (pontos_multiplicador >= 0),
  destaque                boolean not null default false,
  ordem                   integer not null default 0,
  ativo                   boolean not null default true,
  stripe_price_id         text,          -- preenchido na Fase 2 (Stripe)
  created_at              timestamptz not null default now()
);

-- products — catálogo da loja.
create table if not exists public.products (
  id                    uuid primary key default gen_random_uuid(),
  slug                  text not null unique,
  nome                  text not null,
  categoria             text not null check (categoria in ('vestuario', 'acessorios', 'cafe_grao')),
  preco_centavos        integer not null check (preco_centavos >= 0),
  descricao             text,
  imagem_placeholder    text,            -- classe .photo-* enquanto não há foto real
  ativo                 boolean not null default true,
  created_at            timestamptz not null default now()
);
create index if not exists idx_products_categoria  on public.products (categoria);
create index if not exists idx_products_ativo       on public.products (ativo);

-- product_variants — opções de um produto (Moagem / Tamanho). Produto sem variante: 0 linhas.
create table if not exists public.product_variants (
  id                    uuid primary key default gen_random_uuid(),
  product_id            uuid not null references public.products (id) on delete cascade,
  rotulo                text not null,   -- ex.: 'Moagem', 'Tamanho'
  opcao                 text not null,   -- ex.: 'Grão inteiro', 'P'
  preco_delta_centavos  integer not null default 0,
  ordem                 integer not null default 0,
  ativo                 boolean not null default true,
  unique (product_id, opcao)
);
create index if not exists idx_variants_product  on public.product_variants (product_id);

-- achievements — conquistas/emblemas que o cliente desbloqueia usando o Casa.
create table if not exists public.achievements (
  slug        text primary key,
  nome        text not null,
  descricao   text,
  icone       text,             -- nome do ícone Lucide
  ordem       integer not null default 0,
  ativo       boolean not null default true,
  created_at  timestamptz not null default now()
);

-- partners — parceiros locais (colab e/ou resgate de pontos).
create table if not exists public.partners (
  slug        text primary key,
  nome        text not null,
  descricao   text,
  tipo        text not null default 'colab' check (tipo in ('colab', 'resgate', 'ambos')),
  bairro      text,
  cidade      text,
  ordem       integer not null default 0,
  ativo       boolean not null default true,
  created_at  timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Dados sensíveis do usuário (cliente só lê o próprio; escrita server-side).
-- -----------------------------------------------------------------------------

-- subscriptions — assinatura ativa do usuário num tier.
create table if not exists public.subscriptions (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null references public.profiles (id) on delete cascade,
  tier_slug               text not null references public.tiers (slug),
  status                  text not null default 'trial'
                          check (status in ('trial', 'ativa', 'pausada', 'cancelada')),
  stripe_customer_id      text,
  stripe_subscription_id  text,
  current_period_end      timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
create index if not exists idx_subscriptions_user    on public.subscriptions (user_id);
create index if not exists idx_subscriptions_status  on public.subscriptions (status);

-- orders — pedidos (site ou PDV). Totais recalculados no server (nunca do client).
create table if not exists public.orders (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid references public.profiles (id) on delete set null,
  status                text not null default 'pendente'
                        check (status in ('pendente', 'pago', 'preparando', 'pronto', 'entregue', 'cancelado')),
  origem                text not null default 'site' check (origem in ('site', 'pdv')),
  subtotal_centavos     integer not null default 0 check (subtotal_centavos >= 0),
  desconto_centavos     integer not null default 0 check (desconto_centavos >= 0),
  total_centavos        integer not null default 0 check (total_centavos >= 0),
  tier_slug_aplicado    text references public.tiers (slug),
  stripe_checkout_id    text,
  stripe_payment_intent text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index if not exists idx_orders_user     on public.orders (user_id);
create index if not exists idx_orders_status   on public.orders (status);
create index if not exists idx_orders_created  on public.orders (created_at desc);

-- order_items — itens do pedido, com snapshot de nome/variante/preço no momento da compra.
create table if not exists public.order_items (
  id                    uuid primary key default gen_random_uuid(),
  order_id              uuid not null references public.orders (id) on delete cascade,
  product_id            uuid references public.products (id) on delete set null,
  variant_id            uuid references public.product_variants (id) on delete set null,
  nome_snapshot         text not null,
  variante_snapshot     text,
  preco_unit_centavos   integer not null check (preco_unit_centavos >= 0),
  qtd                   integer not null default 1 check (qtd > 0)
);
create index if not exists idx_order_items_order    on public.order_items (order_id);
create index if not exists idx_order_items_product  on public.order_items (product_id);

-- points_ledger — razão de pontos APPEND-ONLY. delta>0 ganha, delta<0 resgata.
-- Saldo = soma dos deltas. Front só lê; gravação só server-side.
create table if not exists public.points_ledger (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  delta         integer not null,
  motivo        text not null check (motivo in ('compra', 'resgate', 'bonus', 'ajuste', 'conquista', 'estorno')),
  order_id      uuid references public.orders (id) on delete set null,
  redemption_id uuid,   -- FK lógica pra redemptions (evita ciclo de criação); ver 0003+ se necessário
  descricao     text,
  created_at    timestamptz not null default now()
);
create index if not exists idx_points_ledger_user     on public.points_ledger (user_id);
create index if not exists idx_points_ledger_created  on public.points_ledger (user_id, created_at desc);

-- redemptions — resgates de pontos (produto da loja, parceiro local ou cupom).
create table if not exists public.redemptions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  tipo          text not null check (tipo in ('produto', 'parceiro', 'cupom')),
  product_id    uuid references public.products (id) on delete set null,
  partner_slug  text references public.partners (slug),
  pontos_gastos integer not null check (pontos_gastos >= 0),
  status        text not null default 'solicitado'
                check (status in ('solicitado', 'aprovado', 'usado', 'cancelado', 'expirado')),
  codigo        text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists idx_redemptions_user  on public.redemptions (user_id);

-- user_achievements — quais conquistas cada usuário desbloqueou. Concessão é server-side.
create table if not exists public.user_achievements (
  user_id           uuid not null references public.profiles (id) on delete cascade,
  achievement_slug  text not null references public.achievements (slug) on delete cascade,
  unlocked_at       timestamptz not null default now(),
  primary key (user_id, achievement_slug)
);
create index if not exists idx_user_achievements_user  on public.user_achievements (user_id);

-- =============================================================================
-- Funções auxiliares de papel — SECURITY DEFINER + search_path fixo.
-- Rodam como owner e por isso NÃO disparam RLS em profiles (evita recursão nas
-- policies que as chamam). Fonte da verdade do papel: profiles.role.
-- =============================================================================
create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.profiles where id = auth.uid()) = 'owner',
    false
  );
$$;

create or replace function public.is_gerente_or_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.profiles where id = auth.uid()) in ('gerente', 'owner'),
    false
  );
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.profiles where id = auth.uid()) in ('staff', 'gerente', 'owner'),
    false
  );
$$;

-- =============================================================================
-- Trigger: handle_new_user — cria o profile no signup (role 'cliente').
-- SECURITY DEFINER pra inserir em profiles mesmo com RLS ligada.
-- =============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    'cliente'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =============================================================================
-- Trigger: prevent_role_change — papel é imutável exceto pelo owner (ou pelo
-- service_role, que roda sem auth.uid()). Toda troca de papel vai pro audit_log.
-- Defesa em profundidade: vale mesmo que uma policy de UPDATE deixe passar.
-- =============================================================================
create or replace function public.prevent_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role then
    -- Sessão autenticada que NÃO é owner: barra. service_role (auth.uid() null): passa.
    if auth.uid() is not null and not public.is_owner() then
      raise exception 'Troca de papel não permitida (só o owner pode alterar papéis).';
    end if;

    insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
    values (
      auth.uid(),
      'role_change',
      'profiles',
      new.id::text,
      jsonb_build_object('de', old.role, 'para', new.role)
    );
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_prevent_role_change on public.profiles;
create trigger trg_prevent_role_change
  before update on public.profiles
  for each row execute function public.prevent_role_change();
