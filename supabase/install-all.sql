-- ======================================================
-- Banco Casa Coffee Colab
-- Instalação completa em um único arquivo SQL
-- Orden: supabase/migrations/*.sql
-- ======================================================

BEGIN;

-- Este arquivo foi gerado a partir das migrações existentes no projeto.
-- Execute em uma base vazia ou em um ambiente preparado para a aplicação.
--
-- Se quiser rodar em psql: psql -f supabase/install-all.sql
-- Se quiser rodar no Supabase SQL Editor: cole o conteúdo do arquivo e execute.

-- ======================================================

-- ===== 0001_init.sql =====

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



-- ===== 0002_rls.sql =====

-- =============================================================================
-- Casa Coffee Colab — 0002_rls.sql
-- Habilita RLS em TODA tabela + todas as policies (deny-by-default).
--
-- Modelo (ver CLAUDE.md › Segurança):
--   • Catálogo/referência (tiers, products, product_variants, achievements,
--     partners): LEITURA PÚBLICA (anon + authenticated) do que está ativo;
--     escrita só gerente/owner (admin autenticado).
--   • Dados sensíveis do usuário (profiles, subscriptions, orders, order_items,
--     points_ledger, redemptions, user_achievements): cliente só LÊ o PRÓPRIO
--     registro (ou staff+). Escrita = server-side (service_role, que ignora RLS)
--     ou trigger. Sem policy de escrita pro client → negado por padrão.
--   • audit_log: só o owner lê. Escrita só por trigger/server-side.
--
-- APPEND-ONLY e IMUTÁVEL. Idempotente: drop policy if exists + create.
-- service_role SEMPRE ignora RLS (usado pelas Edge Functions na Fase 2).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Liga RLS em todas as tabelas (deny-by-default: sem policy = nada passa).
-- -----------------------------------------------------------------------------
alter table public.profiles           enable row level security;
alter table public.audit_log          enable row level security;
alter table public.tiers              enable row level security;
alter table public.products           enable row level security;
alter table public.product_variants   enable row level security;
alter table public.achievements       enable row level security;
alter table public.partners           enable row level security;
alter table public.subscriptions      enable row level security;
alter table public.orders             enable row level security;
alter table public.order_items        enable row level security;
alter table public.points_ledger      enable row level security;
alter table public.redemptions        enable row level security;
alter table public.user_achievements  enable row level security;

-- =============================================================================
-- profiles — cliente lê/edita o próprio; staff+ lê todos; owner edita qualquer.
-- Troca de papel é barrada pela trigger prevent_role_change (defesa extra).
-- INSERT é feito pela trigger handle_new_user (SECURITY DEFINER) — sem policy.
-- =============================================================================
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_staff());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_owner())
  with check (id = auth.uid() or public.is_owner());

-- =============================================================================
-- audit_log — só o owner lê. Escrita só server-side/trigger (sem policy).
-- =============================================================================
drop policy if exists audit_log_select_owner on public.audit_log;
create policy audit_log_select_owner on public.audit_log
  for select to authenticated
  using (public.is_owner());

-- =============================================================================
-- CATÁLOGO / REFERÊNCIA — leitura pública (ativos); escrita gerente/owner.
-- =============================================================================

-- tiers
drop policy if exists tiers_select_public on public.tiers;
create policy tiers_select_public on public.tiers
  for select to anon, authenticated
  using (ativo or public.is_staff());

drop policy if exists tiers_write_admin on public.tiers;
create policy tiers_write_admin on public.tiers
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- products
drop policy if exists products_select_public on public.products;
create policy products_select_public on public.products
  for select to anon, authenticated
  using (ativo or public.is_staff());

drop policy if exists products_write_admin on public.products;
create policy products_write_admin on public.products
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- product_variants
drop policy if exists variants_select_public on public.product_variants;
create policy variants_select_public on public.product_variants
  for select to anon, authenticated
  using (
    ativo or public.is_staff()
  );

drop policy if exists variants_write_admin on public.product_variants;
create policy variants_write_admin on public.product_variants
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- achievements
drop policy if exists achievements_select_public on public.achievements;
create policy achievements_select_public on public.achievements
  for select to anon, authenticated
  using (ativo or public.is_staff());

drop policy if exists achievements_write_admin on public.achievements;
create policy achievements_write_admin on public.achievements
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- partners
drop policy if exists partners_select_public on public.partners;
create policy partners_select_public on public.partners
  for select to anon, authenticated
  using (ativo or public.is_staff());

drop policy if exists partners_write_admin on public.partners;
create policy partners_write_admin on public.partners
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- =============================================================================
-- DADOS SENSÍVEIS DO USUÁRIO — cliente só LÊ o próprio (ou staff+).
-- Nenhuma policy de INSERT/UPDATE/DELETE pro client: escrita é server-side
-- (service_role ignora RLS) ou por trigger. Negado por padrão.
-- =============================================================================

-- subscriptions
drop policy if exists subscriptions_select_own on public.subscriptions;
create policy subscriptions_select_own on public.subscriptions
  for select to authenticated
  using (user_id = auth.uid() or public.is_staff());

-- orders
drop policy if exists orders_select_own on public.orders;
create policy orders_select_own on public.orders
  for select to authenticated
  using (user_id = auth.uid() or public.is_staff());

-- order_items — segue a visibilidade do pedido pai.
drop policy if exists order_items_select_own on public.order_items;
create policy order_items_select_own on public.order_items
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and (o.user_id = auth.uid() or public.is_staff())
    )
  );

-- points_ledger — append-only; cliente só lê o próprio. Sem UPDATE/DELETE pra ninguém.
drop policy if exists points_ledger_select_own on public.points_ledger;
create policy points_ledger_select_own on public.points_ledger
  for select to authenticated
  using (user_id = auth.uid() or public.is_staff());

-- redemptions
drop policy if exists redemptions_select_own on public.redemptions;
create policy redemptions_select_own on public.redemptions
  for select to authenticated
  using (user_id = auth.uid() or public.is_staff());

-- user_achievements
drop policy if exists user_achievements_select_own on public.user_achievements;
create policy user_achievements_select_own on public.user_achievements
  for select to authenticated
  using (user_id = auth.uid() or public.is_staff());



-- ===== 0003_seed.sql =====

-- =============================================================================
-- Casa Coffee Colab — 0003_seed.sql
-- Seed dos 4 tiers, 10 produtos + variantes, 9 conquistas e parceiros locais.
--
-- APPEND-ONLY e IMUTÁVEL. Idempotente: upsert (ON CONFLICT DO UPDATE / DO NOTHING)
-- — pode rodar de novo sem duplicar. Preços em centavos, iguais aos do app.js.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TIERS (planos de assinatura). * valores fictícios, a definir.
-- -----------------------------------------------------------------------------
insert into public.tiers (slug, nome, preco_centavos, desconto_pct, pontos_multiplicador, destaque, ordem) values
  ('bronze',   'Vizinho de Sempre',  2990,  3, 1.00, false, 1),
  ('prata',    'Frequentador',       4990,  6, 1.25, false, 2),
  ('ouro',     'Gente do Casa',      7990, 10, 1.50, true,  3),
  ('diamante', 'Alma do Casa',      12990, 15, 2.00, false, 4)
on conflict (slug) do update set
  nome                 = excluded.nome,
  preco_centavos       = excluded.preco_centavos,
  desconto_pct         = excluded.desconto_pct,
  pontos_multiplicador = excluded.pontos_multiplicador,
  destaque             = excluded.destaque,
  ordem                = excluded.ordem;

-- -----------------------------------------------------------------------------
-- PRODUCTS (10). Mesmos slug/nome/preço/categoria/placeholder do array PRODUTOS.
-- -----------------------------------------------------------------------------
insert into public.products (slug, nome, categoria, preco_centavos, descricao, imagem_placeholder) values
  ('cafe-alma-do-casa-250g', 'Café em grão · Alma do Casa · 250g', 'cafe_grao', 4990,
    'Nosso blend autoral — encorpado, de final doce. Torrado em micro-lote pra chegar fresquinho na tua xícara.', 'photo-warm'),
  ('cafe-torra-vale-dos-sinos-250g', 'Café em grão · Torra Vale dos Sinos · 250g', 'cafe_grao', 5490,
    'Micro-lote de um produtor vizinho, com notas de castanha e caramelo. A gente serve por tempo limitado.', 'photo-green'),
  ('cafe-descafeinado-afeto-250g', 'Café em grão · Descafeinado Afeto · 250g', 'cafe_grao', 5290,
    'Pra ficar um pouco mais sem perder o sono. Descafeinado suave, doce e redondo — no teu ritmo.', 'photo-bege'),
  ('moletom-casa-coffee', 'Moletom Casa Coffee', 'vestuario', 19990,
    'Quentinho pra vestir nos dias de café e chuva. Algodão macio, bordado discreto do Casa no peito.', 'photo-green'),
  ('camiseta-feito-no-casa', 'Camiseta "feito no Casa"', 'vestuario', 8990,
    'Leve, de algodão, com a nossa frase preferida estampada. Pra levar um pedacinho do Casa por aí.', 'photo-warm'),
  ('avental-do-casa', 'Avental do Casa', 'vestuario', 11990,
    'O mesmo avental que a gente usa na cozinha. Linho encorpado, bolso na frente, feito pra durar.', 'photo-bege'),
  ('caneca-de-autor', 'Caneca de autor', 'acessorios', 5990,
    'Cerâmica feita à mão pelo Ateliê Lomba Grande, em residência com a gente. Cada peça é única.', 'photo-warm'),
  ('bolsa-de-linho', 'Bolsa de linho', 'acessorios', 7990,
    'Do tamanho certo pra um livro, o café e o resto do dia. Linho natural que envelhece bonito.', 'photo-green'),
  ('ecobag-passa-aqui', 'Ecobag "passa aqui?"', 'acessorios', 3990,
    'Nosso convite favorito, pra carregar junto. Algodão cru, alça reforçada, cabe a feira inteira.', 'photo-bege'),
  ('kit-coador-filtro-pano', 'Kit coador + filtro de pano', 'acessorios', 6990,
    'Pra fazer em casa o café que tu toma aqui. Suporte de madeira e filtro de pano reutilizável.', 'photo-warm')
on conflict (slug) do update set
  nome               = excluded.nome,
  categoria          = excluded.categoria,
  preco_centavos     = excluded.preco_centavos,
  descricao          = excluded.descricao,
  imagem_placeholder = excluded.imagem_placeholder;

-- -----------------------------------------------------------------------------
-- PRODUCT_VARIANTS. Insert-select por slug do produto (idempotente por (product_id, opcao)).
-- Cafés → Moagem (3 opções). Moletom/Camiseta → Tamanho P/M/G/GG. Avental → Único.
-- Demais acessórios não têm variante.
-- -----------------------------------------------------------------------------
insert into public.product_variants (product_id, rotulo, opcao, ordem)
select p.id, v.rotulo, v.opcao, v.ordem
from public.products p
join (
  values
    -- cafés (Moagem)
    ('cafe-alma-do-casa-250g',            'Moagem', 'Grão inteiro',      1),
    ('cafe-alma-do-casa-250g',            'Moagem', 'Moído p/ coado',    2),
    ('cafe-alma-do-casa-250g',            'Moagem', 'Moído p/ espresso', 3),
    ('cafe-torra-vale-dos-sinos-250g',    'Moagem', 'Grão inteiro',      1),
    ('cafe-torra-vale-dos-sinos-250g',    'Moagem', 'Moído p/ coado',    2),
    ('cafe-torra-vale-dos-sinos-250g',    'Moagem', 'Moído p/ espresso', 3),
    ('cafe-descafeinado-afeto-250g',      'Moagem', 'Grão inteiro',      1),
    ('cafe-descafeinado-afeto-250g',      'Moagem', 'Moído p/ coado',    2),
    ('cafe-descafeinado-afeto-250g',      'Moagem', 'Moído p/ espresso', 3),
    -- vestuário (Tamanho)
    ('moletom-casa-coffee',   'Tamanho', 'P',     1),
    ('moletom-casa-coffee',   'Tamanho', 'M',     2),
    ('moletom-casa-coffee',   'Tamanho', 'G',     3),
    ('moletom-casa-coffee',   'Tamanho', 'GG',    4),
    ('camiseta-feito-no-casa', 'Tamanho', 'P',    1),
    ('camiseta-feito-no-casa', 'Tamanho', 'M',    2),
    ('camiseta-feito-no-casa', 'Tamanho', 'G',    3),
    ('camiseta-feito-no-casa', 'Tamanho', 'GG',   4),
    ('avental-do-casa',        'Tamanho', 'Único', 1)
) as v (slug, rotulo, opcao, ordem) on v.slug = p.slug
on conflict (product_id, opcao) do nothing;

-- -----------------------------------------------------------------------------
-- ACHIEVEMENTS (9 conquistas). Ícones = nomes Lucide.
-- -----------------------------------------------------------------------------
insert into public.achievements (slug, nome, descricao, icone, ordem) values
  ('primeira-xicara',   'Primeira Xícara',    'o teu primeiro café aqui.',                     'coffee',         1),
  ('manha-de-sempre',   'Manhã de Sempre',    'virou rotina passar de manhã.',                 'sunrise',        2),
  ('gente-do-casa',     'Gente do Casa',      'tu já é de casa por aqui.',                      'heart',          3),
  ('alma-do-casa',      'Alma do Casa',       'o coração desse lugar bate contigo.',            'award',          4),
  ('cafe-viajante',     'Café Viajante',      'levou o nosso grão pra casa.',                   'coffee',         5),
  ('mesa-comprida',     'Mesa Comprida',      'trouxe gente nova pra sentar junto.',            'heart',          6),
  ('que-seja-doce',     'Que Seja Doce',      'provou todos os doces da casa.',                 'star',           7),
  ('domingo-de-brunch', 'Domingo de Brunch',  'não perde um brunch de domingo.',               'sunrise',        8),
  ('colab-de-vizinho',  'Colab de Vizinho',   'levou um produto feito em residência no Casa.',  'sparkles',       9)
on conflict (slug) do update set
  nome      = excluded.nome,
  descricao = excluded.descricao,
  icone     = excluded.icone,
  ordem     = excluded.ordem;

-- -----------------------------------------------------------------------------
-- PARTNERS (parceiros locais — colab e/ou resgate de pontos).
-- -----------------------------------------------------------------------------
insert into public.partners (slug, nome, descricao, tipo, bairro, cidade, ordem) values
  ('atelie-lomba-grande',   'Ateliê Lomba Grande',       'cerâmica feita à mão que veste as mesas do Casa.',      'ambos',   'Lomba Grande',    'Novo Hamburgo', 1),
  ('torrefacao-vale-sinos', 'Torrefação Vale dos Sinos', 'micro-lote de café que a gente serve por temporada.',   'colab',   'Centro',          'Novo Hamburgo', 2),
  ('feira-hamburgo-velho',  'Feira da Hamburgo Velho',   'produtores do bairro que abastecem a nossa cozinha.',   'colab',   'Hamburgo Velho',  'Novo Hamburgo', 3),
  ('livraria-da-esquina',   'Livraria da Esquina',       'livro bom combina com café — resgata um vale por aqui.','resgate', 'Hamburgo Velho',  'Novo Hamburgo', 4),
  ('floricultura-raiz',     'Floricultura Raiz',         'um ramo de flores do vizinho pra alegrar a mesa.',      'resgate', 'Hamburgo Velho',  'Novo Hamburgo', 5)
on conflict (slug) do update set
  nome      = excluded.nome,
  descricao = excluded.descricao,
  tipo      = excluded.tipo,
  bairro    = excluded.bairro,
  cidade    = excluded.cidade,
  ordem     = excluded.ordem;



-- ===== 0004_reconcile.sql =====

-- =============================================================================
-- Casa Coffee Colab — 0004_reconcile.sql
-- Reconcilia o banco com a seção 3 (modelo de dados) da Fase 3: adiciona as 5
-- tabelas que faltavam + colunas ausentes em tiers/profiles.
--
-- APPEND-ONLY e IMUTÁVEL (0001–0003 já aplicadas; correção = arquivo novo).
-- Idempotente: IF NOT EXISTS / ADD COLUMN IF NOT EXISTS / drop policy if exists.
-- NÃO renomeia nada existente. Nomes canônicos travados: tabelas `tiers`/`partners`,
-- papéis cliente/staff/gerente/owner.
--
-- NOTA sobre FKs: `partners` e `tiers` têm PK = slug (canônico). Os FKs abaixo
-- apontam pro slug e seguem a convenção já usada no banco (*_slug), NÃO *_id.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- AJUSTES EM TABELAS EXISTENTES
-- -----------------------------------------------------------------------------

-- tiers: colunas points_multiplier / discount_percent (nomes da seção 3).
-- Mantém as colunas PT já existentes (pontos_multiplicador/desconto_pct) e
-- espelha os valores. Backfill idempotente via coalesce.
alter table public.tiers add column if not exists points_multiplier numeric(4,2);
alter table public.tiers add column if not exists discount_percent  integer;

update public.tiers set
  points_multiplier = coalesce(points_multiplier, pontos_multiplicador),
  discount_percent  = coalesce(discount_percent,  desconto_pct);

-- Reforço explícito dos valores da seção 3 (Vizinho 1x/3%, Frequentador 1.25x/6%,
-- Gente do Casa 1.5x/10%, Alma do Casa 2x/15%) — só onde ainda estiver nulo.
update public.tiers set points_multiplier = 1.00, discount_percent = 3  where slug = 'bronze'   and (points_multiplier is null or discount_percent is null);
update public.tiers set points_multiplier = 1.25, discount_percent = 6  where slug = 'prata'    and (points_multiplier is null or discount_percent is null);
update public.tiers set points_multiplier = 1.50, discount_percent = 10 where slug = 'ouro'     and (points_multiplier is null or discount_percent is null);
update public.tiers set points_multiplier = 2.00, discount_percent = 15 where slug = 'diamante' and (points_multiplier is null or discount_percent is null);

-- profiles: saldo de pontos (cache) + tier atual (FK tiers via slug — ver NOTA).
alter table public.profiles add column if not exists points_balance integer not null default 0;
alter table public.profiles add column if not exists tier_slug      text references public.tiers (slug);

-- =============================================================================
-- TABELAS NOVAS
-- =============================================================================

-- 1) rewards_catalog — o que dá pra resgatar com pontos.
--    (partner_slug: FK partners via slug — ver NOTA sobre *_slug.)
create table if not exists public.rewards_catalog (
  id               uuid primary key default gen_random_uuid(),
  nome             text not null,
  tipo             text not null check (tipo in ('produto_loja', 'cupom', 'produto_local')),
  custo_em_pontos  integer not null check (custo_em_pontos >= 0),
  estoque          integer,        -- null = ilimitado
  partner_slug     text references public.partners (slug),
  ativo            boolean not null default true,
  created_at       timestamptz not null default now()
);
create index if not exists idx_rewards_catalog_ativo    on public.rewards_catalog (ativo);
create index if not exists idx_rewards_catalog_partner  on public.rewards_catalog (partner_slug);

-- 2) events — encontros/eventos do Casa.
create table if not exists public.events (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  descricao   text,
  data        timestamptz,
  vagas       integer check (vagas is null or vagas >= 0),
  ativo       boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists idx_events_ativo  on public.events (ativo);
create index if not exists idx_events_data    on public.events (data);

-- 3) coupons — cupons de desconto (geralmente gerados por um resgate).
--    Leitura só do dono (ou staff+); escrita só server-side.
create table if not exists public.coupons (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null unique,
  tipo_desconto  text not null check (tipo_desconto in ('percent', 'fixo')),
  valor          integer not null check (valor >= 0),  -- percent: 0–100 · fixo: centavos
  validade       timestamptz,
  redemption_id  uuid references public.redemptions (id) on delete set null,
  user_id        uuid references public.profiles (id)    on delete cascade,
  created_at     timestamptz not null default now()
);
create index if not exists idx_coupons_user  on public.coupons (user_id);

-- 4) pos_webhook_events — eventos do PDV (webhook). Sem acesso a cliente.
--    external_transaction_id UNIQUE = idempotência/anti-replay.
create table if not exists public.pos_webhook_events (
  id                       uuid primary key default gen_random_uuid(),
  external_transaction_id  text not null unique,
  payload                  jsonb not null default '{}'::jsonb,
  status                   text not null default 'recebido'
                           check (status in ('recebido', 'processado', 'erro', 'ignorado')),
  processed_at             timestamptz,
  created_at               timestamptz not null default now()
);

-- 5) unclaimed_points — pontos ganhos por quem ainda não tem conta (por telefone/e-mail).
--    Sem acesso a cliente; leitura só owner; escrita só server-side.
create table if not exists public.unclaimed_points (
  id                uuid primary key default gen_random_uuid(),
  identifier_type   text not null check (identifier_type in ('phone', 'email')),
  identifier_value  text not null,
  pontos            integer not null,
  origem            text,
  created_at        timestamptz not null default now(),
  claimed_at        timestamptz
);
create index if not exists idx_unclaimed_points_identifier
  on public.unclaimed_points (identifier_type, identifier_value);

-- =============================================================================
-- RLS — habilita nas 5 novas tabelas (deny-by-default) + policies.
-- =============================================================================
alter table public.rewards_catalog    enable row level security;
alter table public.events             enable row level security;
alter table public.coupons            enable row level security;
alter table public.pos_webhook_events enable row level security;
alter table public.unclaimed_points   enable row level security;

-- rewards_catalog — leitura pública dos ativos; escrita gerente/owner.
drop policy if exists rewards_catalog_select_public on public.rewards_catalog;
create policy rewards_catalog_select_public on public.rewards_catalog
  for select to anon, authenticated
  using (ativo or public.is_staff());

drop policy if exists rewards_catalog_write_admin on public.rewards_catalog;
create policy rewards_catalog_write_admin on public.rewards_catalog
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- events — leitura pública dos ativos; escrita gerente/owner.
drop policy if exists events_select_public on public.events;
create policy events_select_public on public.events
  for select to anon, authenticated
  using (ativo or public.is_staff());

drop policy if exists events_write_admin on public.events;
create policy events_write_admin on public.events
  for all to authenticated
  using (public.is_gerente_or_owner())
  with check (public.is_gerente_or_owner());

-- coupons — só o dono lê (ou staff+). Escrita server-side (sem policy → negado).
drop policy if exists coupons_select_own on public.coupons;
create policy coupons_select_own on public.coupons
  for select to authenticated
  using (user_id = auth.uid() or public.is_staff());

-- pos_webhook_events — sem acesso a cliente; só owner lê. Escrita server-side.
drop policy if exists pos_webhook_events_select_owner on public.pos_webhook_events;
create policy pos_webhook_events_select_owner on public.pos_webhook_events
  for select to authenticated
  using (public.is_owner());

-- unclaimed_points — sem acesso a cliente; só owner lê. Escrita server-side.
drop policy if exists unclaimed_points_select_owner on public.unclaimed_points;
create policy unclaimed_points_select_owner on public.unclaimed_points
  for select to authenticated
  using (public.is_owner());



-- ===== 0005_profiles_phone.sql =====

-- =============================================================================
-- Casa Coffee Colab — 0005_profiles_phone.sql
-- Auth (Fase 2): guarda o telefone no profiles e blinda os campos de fidelidade.
--
-- APPEND-ONLY e IMUTÁVEL (0001–0004 já aplicadas). Idempotente:
-- ADD COLUMN IF NOT EXISTS / CREATE OR REPLACE / drop trigger if exists.
-- NÃO renomeia nada. Nomes canônicos travados (tabelas tiers/partners, papéis
-- cliente/staff/gerente/owner). Ver CLAUDE.md › Segurança + Migrations.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- profiles.telefone — coletado no cadastro (raw_user_meta_data 'telefone').
-- (E-mail NÃO fica aqui: vive em auth.users; o perfil lê da sessão.)
-- (CPF NÃO fica aqui: decisão registrada — o Stripe coleta/guarda o CPF.)
-- -----------------------------------------------------------------------------
alter table public.profiles add column if not exists telefone text;

-- -----------------------------------------------------------------------------
-- handle_new_user — agora também popula o telefone no signup.
-- CREATE OR REPLACE atualiza o corpo; a trigger on_auth_user_created (0001)
-- continua apontando pra esta função (não precisa recriar a trigger).
-- SECURITY DEFINER + search_path fixo (mesma postura da 0001).
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, telefone, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'telefone',
    'cliente'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- prevent_points_tamper — confiança zero no client.
-- A policy profiles_update_self (0002) deixa o cliente editar a PRÓPRIA linha,
-- mas sem restrição de coluna ele poderia tentar mexer em points_balance /
-- tier_slug (adicionados na 0004). Pontos e plano são gravados SÓ server-side
-- (Edge Function/service_role, que roda sem auth.uid()) ou pelo owner.
-- Defesa em profundidade, no mesmo espírito da trigger prevent_role_change.
-- -----------------------------------------------------------------------------
create or replace function public.prevent_points_tamper()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Sessão autenticada que NÃO é owner: barra qualquer mudança nesses campos.
  -- service_role (auth.uid() null) e owner passam.
  if auth.uid() is not null and not public.is_owner() then
    if new.points_balance is distinct from old.points_balance then
      raise exception 'points_balance é gravado só server-side (não pelo client).';
    end if;
    if new.tier_slug is distinct from old.tier_slug then
      raise exception 'tier_slug é gravado só server-side (não pelo client).';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_points_tamper on public.profiles;
create trigger trg_prevent_points_tamper
  before update on public.profiles
  for each row execute function public.prevent_points_tamper();



-- ===== 0006_stripe.sql =====

-- =============================================================================
-- Casa Coffee Colab — 0006_stripe.sql
-- Fase 6a — fundação do Stripe (SÓ TEST MODE) + caso de ASSINATURA (4 tiers).
--
-- APPEND-ONLY e IMUTÁVEL (0001–0005 já aplicadas). Idempotente:
-- CREATE TABLE IF NOT EXISTS / ADD COLUMN IF NOT EXISTS / CREATE ... IF NOT EXISTS
-- / drop policy if exists. NÃO renomeia nada. Nomes canônicos travados
-- (tabelas tiers/subscriptions, FKs por slug). Ver CLAUDE.md › Segurança + Migrations.
--
-- ORDEM DE APLICAÇÃO: rode este arquivo no SQL Editor DEPOIS de ter os price IDs
-- do Stripe test (gerados por `node scripts/stripe-seed.mjs`) — cole-os no bloco
-- de UPDATEs comentado lá embaixo antes de rodar (ou rode agora e cole os UPDATEs
-- depois, tanto faz: os UPDATEs são idempotentes).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- stripe_events — idempotência/anti-replay do webhook do Stripe.
-- PK = event.id do Stripe (ex.: 'evt_...'). Se o id já existe, o webhook não
-- reprocessa. Sem acesso a cliente; leitura só owner; escrita só server-side
-- (Edge Function via service_role, que ignora RLS).
-- -----------------------------------------------------------------------------
create table if not exists public.stripe_events (
  id            text primary key,          -- event.id do Stripe
  type          text,                      -- event.type (ex.: 'checkout.session.completed')
  processed_at  timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- profiles.stripe_customer_id — o Customer do Stripe do usuário (criado/reusado
-- na create-checkout-session). É gravado só server-side (service_role).
-- Não é segredo, mas fica atrás da RLS do profiles (só o dono/staff lê).
-- -----------------------------------------------------------------------------
alter table public.profiles add column if not exists stripe_customer_id text;

-- -----------------------------------------------------------------------------
-- subscriptions.stripe_subscription_id — UNIQUE pra o webhook fazer upsert
-- idempotente (uma linha por assinatura do Stripe). NULLs continuam permitidos
-- (múltiplos NULLs são distintos no índice único do Postgres — assinaturas
-- antigas/trial sem id do Stripe não colidem).
-- -----------------------------------------------------------------------------
create unique index if not exists subscriptions_stripe_sub_id_key
  on public.subscriptions (stripe_subscription_id);

-- =============================================================================
-- RLS — stripe_events: deny-by-default. Sem acesso a cliente; só owner lê.
-- Escrita só server-side (service_role ignora RLS) → sem policy de escrita.
-- =============================================================================
alter table public.stripe_events enable row level security;

drop policy if exists stripe_events_select_owner on public.stripe_events;
create policy stripe_events_select_owner on public.stripe_events
  for select to authenticated
  using (public.is_owner());

-- =============================================================================
-- PRICE IDs DO STRIPE (test mode) — preenchidos por `node scripts/stripe-seed.mjs`.
-- Idempotente: pode rodar de novo pra corrigir/atualizar. Se recriar os preços
-- no Stripe (novos price_id), rode o seed de novo e atualize estes valores.
--
-- (No dia do go-live LIVE: gerar produtos/preços em LIVE mode, pegar os price_id
--  live e rodar uma migration NOVA com os UPDATEs live — ver checklist no CLAUDE.md.)
-- =============================================================================
update public.tiers set stripe_price_id = 'price_1TtYEbFUPX1fv0T2ILYU9Vjb' where slug = 'bronze';
update public.tiers set stripe_price_id = 'price_1TtYEcFUPX1fv0T27M5aHMSi' where slug = 'prata';
update public.tiers set stripe_price_id = 'price_1TtYEdFUPX1fv0T29Hw7Rli5' where slug = 'ouro';
update public.tiers set stripe_price_id = 'price_1TtYEeFUPX1fv0T2o6C0thVl' where slug = 'diamante';



-- ===== 0007_orders_stripe.sql =====

-- =============================================================================
-- Casa Coffee Colab — 0007_orders_stripe.sql
-- Fase 6b — checkout da LOJA (pagamento avulso). Prepara orders/order_items pro
-- webhook gravar o pedido pago, idempotente por sessão do Stripe.
--
-- APPEND-ONLY e IMUTÁVEL (0001–0006 já aplicadas). Idempotente:
-- ADD COLUMN IF NOT EXISTS / CREATE ... IF NOT EXISTS. NÃO renomeia nada.
-- Nomes canônicos travados (colunas em *_centavos, papéis, FKs por slug).
-- Ver CLAUDE.md › Segurança + Migrations.
--
-- AUDITORIA (o que a 0001 já criou — reusamos, NÃO duplicamos):
--   orders:      user_id (FK profiles) · status · subtotal_centavos ·
--                desconto_centavos · total_centavos · tier_slug_aplicado (FK tiers) ·
--                stripe_checkout_id · stripe_payment_intent · origem · created_at.
--   order_items: order_id (FK orders) · product_id (FK products) ·
--                variant_id (FK product_variants) · nome_snapshot ·
--                variante_snapshot · preco_unit_centavos · qtd.
--
-- Mapeamento com os nomes pedidos na spec da 6b (mesma semântica, nome canônico
-- que já existe — por isso NÃO criamos colunas novas com nomes em inglês, o que
-- só duplicaria dados):
--   subtotal_cents        → subtotal_centavos
--   discount_cents        → desconto_centavos
--   total_cents           → total_centavos
--   tier_slug_no_momento  → tier_slug_aplicado
--   stripe_session_id     → stripe_checkout_id   (guarda o cs_… do Checkout)
--   product_slug/variante → product_id/variant_id + *_snapshot (snapshot na compra)
--   unit_price_cents      → preco_unit_centavos
--
-- RLS já vem da 0002 (cliente só LÊ o próprio pedido; escrita só server-side via
-- service_role). Nada a mudar aqui além do índice de idempotência abaixo.
-- =============================================================================

-- Defensivo: se por algum motivo alguma coluna não existir no ambiente, cria.
-- (No banco padrão da 0001 todas já existem — estes ADDs são no-ops idempotentes.)
alter table public.orders add column if not exists stripe_checkout_id     text;
alter table public.orders add column if not exists stripe_payment_intent  text;
alter table public.orders add column if not exists tier_slug_aplicado     text references public.tiers (slug);

-- -----------------------------------------------------------------------------
-- Idempotência do webhook da LOJA: um pedido por sessão de Checkout do Stripe.
-- stripe_checkout_id guarda o `cs_…`. UNIQUE → o webhook faz upsert/skip sem
-- duplicar o pedido em reentregas do evento. NULLs seguem permitidos (múltiplos
-- NULLs são distintos no índice único do Postgres — pedidos de PDV sem cs_ ok).
-- -----------------------------------------------------------------------------
create unique index if not exists orders_stripe_checkout_id_key
  on public.orders (stripe_checkout_id);



-- ===== 0008_points.sql =====

-- =============================================================================
-- Casa Coffee Colab — 0008_points.sql
-- Fase 3 — fidelidade (pontos + resgates). Torna o points_ledger a fonte da
-- verdade e o profiles.points_balance um cache que NUNCA diverge (trigger).
--
-- APPEND-ONLY e IMUTÁVEL (0001–0007 já aplicadas). Idempotente:
-- ADD COLUMN IF NOT EXISTS / CREATE OR REPLACE / CREATE ... IF NOT EXISTS /
-- DO-block pra dropar constraint por nome. NÃO renomeia nada. Nomes canônicos
-- travados (tiers/partners por slug, papéis). Ver CLAUDE.md › Segurança + Migrations.
--
-- REGRA DE NEGÓCIO (travada): 1 ponto por R$1 gasto × points_multiplier do tier
-- ATIVO no momento (sem assinatura = 1x). Loja: sobre o total JÁ COM DESCONTO.
-- Sempre floor (arredonda pra baixo). Ex.: R$49,41 no Ouro (1,5x) →
-- floor(49.41 × 1.5) = floor(74.115) = 74 pontos. Todo lançamento passa pelo
-- ledger (append-only); NUNCA update direto no saldo.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- points_ledger: colunas de referência pra idempotência do crédito + relaxa o
-- CHECK de `motivo` (agora aceita descrições em PT da Fase 3, inclusive o
-- dinâmico 'resgate: <nome>'). `motivo` segue NOT NULL.
-- -----------------------------------------------------------------------------
alter table public.points_ledger add column if not exists ref_type text;
alter table public.points_ledger add column if not exists ref_id   text;

-- Dropa o CHECK restritivo de motivo, seja qual for o nome auto-gerado dele.
do $$
declare c text;
begin
  select conname into c
    from pg_constraint
   where conrelid = 'public.points_ledger'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%motivo%';
  if c is not null then
    execute format('alter table public.points_ledger drop constraint %I', c);
  end if;
end $$;

-- Anti-duplicação no BANCO: um lançamento por (ref_type, ref_id). Mesmo que o
-- webhook reprocesse o evento, o crédito não duplica. NULLs livres (ajustes
-- manuais/bônus sem referência não colidem — índice parcial).
create unique index if not exists points_ledger_ref_unique
  on public.points_ledger (ref_type, ref_id)
  where ref_type is not null;

-- -----------------------------------------------------------------------------
-- prevent_points_tamper (redefine a de 0005): continua barrando o CLIENT de
-- mexer em points_balance/tier_slug direto. MAS libera quando o write vem de um
-- caminho server-side confiável, sinalizado por uma GUC transaction-local
-- (`casa.trusted_points='on'`), setada pelo trigger de saldo abaixo. Isso é
-- necessário porque o resgate roda como SECURITY DEFINER mas auth.uid() continua
-- sendo o do usuário (SECURITY DEFINER não troca o auth.uid()).
-- -----------------------------------------------------------------------------
create or replace function public.prevent_points_tamper()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Caminho confiável (trigger do ledger / funções server-side): libera.
  if coalesce(current_setting('casa.trusted_points', true), '') = 'on' then
    return new;
  end if;
  -- Cliente autenticado que não é owner: barra mudança nesses campos.
  if auth.uid() is not null and not public.is_owner() then
    if new.points_balance is distinct from old.points_balance then
      raise exception 'points_balance é gravado só server-side (não pelo client).';
    end if;
    if new.tier_slug is distinct from old.tier_slug then
      raise exception 'tier_slug é gravado só server-side (não pelo client).';
    end if;
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- update_points_balance: a cada INSERT no ledger, soma o delta no cache do
-- profiles. Seta a GUC confiável antes do update pro prevent_points_tamper
-- deixar passar (o resgate é chamado por usuário autenticado). SECURITY DEFINER
-- + search_path fixo (mesmo padrão dos triggers de 0001/0005).
-- -----------------------------------------------------------------------------
create or replace function public.update_points_balance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('casa.trusted_points', 'on', true); -- transação confiável
  update public.profiles
     set points_balance = coalesce(points_balance, 0) + new.delta
   where id = new.user_id;
  return new;
end;
$$;

drop trigger if exists trg_update_points_balance on public.points_ledger;
create trigger trg_update_points_balance
  after insert on public.points_ledger
  for each row execute function public.update_points_balance();

-- -----------------------------------------------------------------------------
-- recalc_points_balance: ferramenta de reparo — recalcula o cache somando o
-- ledger. Só service_role/owner (revogada de anon/authenticated).
-- -----------------------------------------------------------------------------
create or replace function public.recalc_points_balance(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer;
begin
  select coalesce(sum(delta), 0) into v_total
    from public.points_ledger where user_id = p_user_id;
  perform set_config('casa.trusted_points', 'on', true);
  update public.profiles set points_balance = v_total where id = p_user_id;
  return v_total;
end;
$$;

revoke all on function public.recalc_points_balance(uuid) from public;

-- -----------------------------------------------------------------------------
-- rewards_catalog: slug estável (idempotência do seed + referência) e o valor
-- do cupom em centavos (quando tipo='cupom').
-- -----------------------------------------------------------------------------
alter table public.rewards_catalog add column if not exists slug                 text;
alter table public.rewards_catalog add column if not exists cupom_valor_centavos integer;
create unique index if not exists rewards_catalog_slug_key on public.rewards_catalog (slug);

-- -----------------------------------------------------------------------------
-- redeem_reward: resgate ATÔMICO e à prova de corrida. Lock na linha do reward,
-- valida (ativo, estoque, saldo do LEDGER — não do cache), lança o NEGATIVO no
-- ledger, cria a redemption, decrementa estoque e, se for cupom, gera um código
-- único legível (CASA-XXXX, validade 30 dias). SECURITY DEFINER; só service_role
-- chama (via Edge Function redeem-reward). Resgate duplo fica impossível.
-- -----------------------------------------------------------------------------
create or replace function public.redeem_reward(p_user_id uuid, p_reward_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reward         public.rewards_catalog;
  v_saldo          integer;
  v_redemption_id  uuid;
  v_codigo         text := null;
  v_tipo_redemption text;
begin
  -- Lock pessimista na linha do reward: serializa resgates concorrentes.
  select * into v_reward from public.rewards_catalog where id = p_reward_id for update;
  if not found or not v_reward.ativo then
    return jsonb_build_object('ok', false, 'erro', 'recompensa indisponível');
  end if;
  if v_reward.estoque is not null and v_reward.estoque <= 0 then
    return jsonb_build_object('ok', false, 'erro', 'esgotado');
  end if;

  -- Saldo pela FONTE DA VERDADE (soma do ledger), nunca pelo cache.
  select coalesce(sum(delta), 0) into v_saldo
    from public.points_ledger where user_id = p_user_id;
  if v_saldo < v_reward.custo_em_pontos then
    return jsonb_build_object(
      'ok', false, 'erro', 'saldo insuficiente',
      'saldo', v_saldo, 'custo', v_reward.custo_em_pontos,
      'faltam', v_reward.custo_em_pontos - v_saldo);
  end if;

  v_tipo_redemption := case v_reward.tipo
    when 'produto_loja'  then 'produto'
    when 'produto_local' then 'parceiro'
    when 'cupom'         then 'cupom'
    else 'produto' end;

  insert into public.redemptions (user_id, tipo, partner_slug, pontos_gastos, status)
  values (p_user_id, v_tipo_redemption, v_reward.partner_slug, v_reward.custo_em_pontos, 'aprovado')
  returning id into v_redemption_id;

  -- Lançamento NEGATIVO (dispara o trigger que baixa o saldo). ref_* garante
  -- que um mesmo resgate nunca vira dois débitos.
  insert into public.points_ledger (user_id, delta, motivo, redemption_id, descricao, ref_type, ref_id)
  values (p_user_id, -v_reward.custo_em_pontos, 'resgate: ' || v_reward.nome,
          v_redemption_id, v_reward.nome, 'redemption', v_redemption_id::text);

  if v_reward.estoque is not null then
    update public.rewards_catalog set estoque = estoque - 1 where id = p_reward_id;
  end if;

  if v_reward.tipo = 'cupom' then
    -- Código único legível: CASA-XXXX (4 hex maiúsculos). Retenta se colidir.
    loop
      v_codigo := 'CASA-' || upper(substr(md5(gen_random_uuid()::text), 1, 4));
      exit when not exists (select 1 from public.coupons where codigo = v_codigo);
    end loop;
    insert into public.coupons (codigo, tipo_desconto, valor, validade, redemption_id, user_id)
    values (v_codigo, 'fixo', coalesce(v_reward.cupom_valor_centavos, 0),
            now() + interval '30 days', v_redemption_id, p_user_id);
    update public.redemptions set codigo = v_codigo where id = v_redemption_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'reward', v_reward.nome,
    'gasto', v_reward.custo_em_pontos,
    'saldo', v_saldo - v_reward.custo_em_pontos,
    'codigo', v_codigo);
end;
$$;

revoke all on function public.redeem_reward(uuid, uuid) from public;
grant execute on function public.redeem_reward(uuid, uuid) to service_role;

-- -----------------------------------------------------------------------------
-- SEED de recompensas (tom da marca). Idempotente por slug. Estoque null =
-- ilimitado. O parceiro do vale local sai do seed de partners (0003).
-- -----------------------------------------------------------------------------
insert into public.rewards_catalog (slug, nome, tipo, custo_em_pontos, estoque, partner_slug, cupom_valor_centavos, ativo) values
  ('cafe-coado-do-dia',   'Café coado do dia, por nossa conta', 'produto_loja',  100, null, null,                  null, true),
  ('vale-10-na-loja',     'Vale R$10 na nossa loja',            'cupom',         200, null, null,                  1000, true),
  ('saco-grao-250g',      'Saco de grão do Casa · 250g',        'produto_loja',  400, null, null,                  null, true),
  ('vale-livraria',       'Um vale na Livraria da Esquina',     'produto_local', 500, null, 'livraria-da-esquina', null, true)
on conflict (slug) do update set
  nome                 = excluded.nome,
  tipo                 = excluded.tipo,
  custo_em_pontos      = excluded.custo_em_pontos,
  partner_slug         = excluded.partner_slug,
  cupom_valor_centavos = excluded.cupom_valor_centavos,
  ativo                = excluded.ativo;



-- ===== 0009_achievements.sql =====

-- =============================================================================
-- Casa Coffee Colab — 0009_achievements.sql
-- Fase 3 — conquistas/emblemas. Dá CRITÉRIOS declarativos (jsonb) a cada
-- achievement (seed 0003) e uma função server-side que AVALIA esses critérios
-- pra um usuário e desbloqueia (insere em user_achievements) o que ele cumpriu.
--
-- APPEND-ONLY e IMUTÁVEL (0001–0008 já aplicadas). Idempotente:
-- ADD COLUMN IF NOT EXISTS / UPDATE por slug (reexecutável) / CREATE OR REPLACE.
-- NÃO recria tabela nem índice (a PK de user_achievements já é o índice único).
-- NÃO renomeia nada. Ver CLAUDE.md › Segurança + Migrations.
--
-- MODELO DE CONFIANÇA (igual redeem_reward da 0008): check_achievements é
-- SECURITY DEFINER (roda como owner, ignora RLS) e recebe SÓ p_user_id de
-- chamadas server-side confiáveis (Edge Function com service_role passando o id
-- do PRÓPRIO usuário autenticado). Nunca é chamada direto pelo client.
--
-- REGRA (travada): conquista NÃO credita pontos (a Leva 8 já cobre o crédito).
-- Aqui só se concede o emblema: insert em user_achievements, idempotente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Coluna de critérios (jsonb declarativo). Null = conquista sem regra
--    automática (não é avaliada pela função).
-- -----------------------------------------------------------------------------
alter table public.achievements add column if not exists criterios jsonb;

-- -----------------------------------------------------------------------------
-- 2) Critérios dos 9 emblemas do seed (0003). Um UPDATE por slug — reexecutável
--    à vontade (só reescreve o mesmo jsonb).
-- -----------------------------------------------------------------------------

-- 1ª compra paga em qualquer momento.
update public.achievements set criterios = '{"type":"purchase_count","min":1}'::jsonb
  where slug = 'primeira-xicara';

-- 5 compras pagas de manhã (< 12h no horário de São Paulo) — virou rotina.
update public.achievements set criterios = '{"type":"purchase_count","min":5,"window":"morning"}'::jsonb
  where slug = 'manha-de-sempre';

-- Assinante do tier Ouro — já é de casa.
update public.achievements set criterios = '{"type":"tier","slug":"ouro"}'::jsonb
  where slug = 'gente-do-casa';

-- Assinante do tier Diamante — o coração do lugar bate contigo.
update public.achievements set criterios = '{"type":"tier","slug":"diamante"}'::jsonb
  where slug = 'alma-do-casa';

-- Ao menos 1 saco de grão (categoria cafe_grao) numa compra paga — levou o grão.
update public.achievements set criterios = '{"type":"product_category","category":"cafe_grao","min":1}'::jsonb
  where slug = 'cafe-viajante';

-- MANUAL: trazer gente nova pra sentar junto (indicação). Ainda NÃO temos fonte
-- de dados de indicação — reservado p/ desbloqueio futuro (staff/PDV).
update public.achievements set criterios = '{"type":"manual"}'::jsonb
  where slug = 'mesa-comprida';

-- MANUAL: provar todos os doces do cardápio. Ainda NÃO temos como derivar isso
-- dos pedidos (o cardápio é informativo, sem SKU por doce) — reservado p/ futuro.
update public.achievements set criterios = '{"type":"manual"}'::jsonb
  where slug = 'que-seja-doce';

-- 4 compras pagas em domingos (dow=0 no horário de São Paulo) — brunch de domingo.
update public.achievements set criterios = '{"type":"purchase_count","min":4,"window":"sunday"}'::jsonb
  where slug = 'domingo-de-brunch';

-- MANUAL: levar um produto feito em residência no Casa. Ainda NÃO marcamos quais
-- produtos são de residência — reservado p/ desbloqueio futuro (staff/PDV).
update public.achievements set criterios = '{"type":"manual"}'::jsonb
  where slug = 'colab-de-vizinho';

-- -----------------------------------------------------------------------------
-- 3) check_achievements(p_user_id): avalia os critérios de todas as conquistas
--    ativas que o usuário AINDA não tem e concede as que ele cumpriu. Retorna
--    quantas foram desbloqueadas NESTA chamada. SECURITY DEFINER + search_path
--    fixo (mesmo padrão de redeem_reward/recalc_points_balance da 0008).
--
--    Compra válida = orders.status = 'pago'. Janelas de tempo usam o fuso
--    'America/Sao_Paulo' (manhã = hora < 12; domingo = dow 0). Tipos suportados:
--    purchase_count | tier | product_category | points_total |
--    subscription_months | redemption_count. 'manual' e tipos desconhecidos
--    NÃO desbloqueiam (skip) — ficam pra concessão manual futura.
-- -----------------------------------------------------------------------------
create or replace function public.check_achievements(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  rec       record;
  v_novas   integer := 0;   -- conquistas desbloqueadas nesta chamada
  v_rows    integer;        -- linhas realmente inseridas por conquista (0 ou 1)
  v_cumpre  boolean;        -- se o critério da conquista atual foi cumprido
  v_count   bigint;         -- contagem/soma auxiliar por critério
  v_window  text;           -- janela de tempo (morning|sunday) quando houver
  v_tier    text;           -- tier_slug do usuário (critério 'tier')
begin
  -- Só as conquistas ativas, com critério definido e que o usuário AINDA não tem.
  for rec in
    select a.slug, a.criterios
      from public.achievements a
     where a.ativo = true
       and a.criterios is not null
       and not exists (
         select 1 from public.user_achievements ua
          where ua.user_id = p_user_id
            and ua.achievement_slug = a.slug
       )
  loop
    v_cumpre := false;

    case rec.criterios->>'type'

      when 'purchase_count' then
        v_window := rec.criterios->>'window';
        if v_window = 'morning' then
          select count(*) into v_count
            from public.orders
           where user_id = p_user_id
             and status = 'pago'
             and extract(hour from (created_at at time zone 'America/Sao_Paulo')) < 12;
        elsif v_window = 'sunday' then
          select count(*) into v_count
            from public.orders
           where user_id = p_user_id
             and status = 'pago'
             and extract(dow from (created_at at time zone 'America/Sao_Paulo')) = 0;
        else
          select count(*) into v_count
            from public.orders
           where user_id = p_user_id
             and status = 'pago';
        end if;
        v_cumpre := v_count >= coalesce((rec.criterios->>'min')::int, 1);

      when 'tier' then
        select tier_slug into v_tier from public.profiles where id = p_user_id;
        v_cumpre := v_tier = (rec.criterios->>'slug');

      when 'product_category' then
        select count(*) into v_count
          from public.order_items oi
          join public.orders   o on o.id = oi.order_id
          join public.products p on p.id = oi.product_id
         where o.user_id = p_user_id
           and o.status  = 'pago'
           and p.categoria = (rec.criterios->>'category');
        v_cumpre := v_count >= coalesce((rec.criterios->>'min')::int, 1);

      when 'points_total' then
        select coalesce(sum(delta) filter (where delta > 0), 0) into v_count
          from public.points_ledger where user_id = p_user_id;
        v_cumpre := v_count >= coalesce((rec.criterios->>'min')::int, 0);

      when 'subscription_months' then
        select count(*) into v_count
          from public.points_ledger
         where user_id = p_user_id
           and ref_type in ('subscription_start', 'subscription_renewal');
        v_cumpre := v_count >= coalesce((rec.criterios->>'min')::int, 0);

      when 'redemption_count' then
        select count(*) into v_count
          from public.redemptions where user_id = p_user_id;
        v_cumpre := v_count >= coalesce((rec.criterios->>'min')::int, 0);

      else
        -- 'manual' ou tipo desconhecido: não desbloqueia (concessão manual futura).
        v_cumpre := false;
    end case;

    if v_cumpre then
      insert into public.user_achievements (user_id, achievement_slug)
      values (p_user_id, rec.slug)
      on conflict (user_id, achievement_slug) do nothing;
      -- Conta só se REALMENTE inseriu (evita contar corrida com outra sessão).
      get diagnostics v_rows = row_count;
      v_novas := v_novas + v_rows;
    end if;
  end loop;

  return v_novas;
end;
$$;

-- Só server-side (Edge Function com service_role). Nunca anon/authenticated.
revoke all on function public.check_achievements(uuid) from public;
grant execute on function public.check_achievements(uuid) to service_role;



-- ===== 0010_achievement_hints.sql =====

-- =============================================================================
-- Casa Coffee Colab — 0010_achievement_hints.sql
-- Fase 3 — conquistas: dá a cada emblema uma DICA acionável ("como desbloquear"),
-- separada do `descricao` (que é o texto poético, mostrado quando JÁ desbloqueou).
--
-- O front (initConquistasPage) mostra a `dica` no card BLOQUEADO, num bloco
-- "como desbloquear", e no tooltip dos mini-emblemas do painel do usuário.
--
-- APPEND-ONLY e IMUTÁVEL (0001–0009 já aplicadas). Idempotente:
-- ADD COLUMN IF NOT EXISTS + UPDATE por slug (reexecutável). Ver CLAUDE.md.
--
-- TOM DE VOZ (obrigatório): "tu"/"a gente", acolhedor, sem imperativo agressivo,
-- ZERO cara de cassino. As dicas espelham os CRITÉRIOS reais da 0009.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Coluna da dica (texto livre em PT). Null = sem dica (cai no fallback gentil).
-- -----------------------------------------------------------------------------
alter table public.achievements add column if not exists dica text;

-- -----------------------------------------------------------------------------
-- 2) Dicas dos 9 emblemas — uma por slug, alinhada ao critério da 0009.
-- -----------------------------------------------------------------------------

-- purchase_count >= 1 (qualquer compra paga).
update public.achievements
   set dica = 'faz teu primeiro pedido — aqui na loja ou lá no balcão.'
 where slug = 'primeira-xicara';

-- purchase_count >= 5, janela manhã (pedidos pagos antes do meio-dia).
update public.achievements
   set dica = 'passa cinco manhãs com a gente — pedidos antes do meio-dia contam.'
 where slug = 'manha-de-sempre';

-- tier = ouro (assinatura Gente do Casa).
update public.achievements
   set dica = 'vira assinante do plano Gente do Casa.'
 where slug = 'gente-do-casa';

-- tier = diamante (assinatura Alma do Casa).
update public.achievements
   set dica = 'vira assinante do plano Alma do Casa.'
 where slug = 'alma-do-casa';

-- product_category = cafe_grao (>= 1 numa compra paga).
update public.achievements
   set dica = 'leva um dos nossos cafés em grão pra casa.'
 where slug = 'cafe-viajante';

-- MANUAL (sem fonte de dados ainda) — desbloqueio no balcão.
update public.achievements
   set dica = 'traz alguém novo pra sentar na nossa mesa — a gente marca no balcão.'
 where slug = 'mesa-comprida';

-- MANUAL (o cardápio não tem SKU por doce) — desbloqueio no balcão.
update public.achievements
   set dica = 'prova todos os doces da casa — a gente confirma no balcão.'
 where slug = 'que-seja-doce';

-- purchase_count >= 4, janela domingo (pedidos pagos aos domingos).
update public.achievements
   set dica = 'vem a quatro brunchs de domingo — a mesa te espera.'
 where slug = 'domingo-de-brunch';

-- MANUAL (ainda não marcamos quais produtos são de residência) — balcão.
update public.achievements
   set dica = 'leva pra casa um produto feito na Residência Gente do Casa.'
 where slug = 'colab-de-vizinho';



-- ===== 0011_asaas.sql =====

-- =============================================================================
-- Casa Coffee Colab — 0011_asaas.sql
-- Troca do gateway de pagamento: Stripe → ASAAS (Pix + Cartão, Checkout hospedado).
-- Cobre LOJA (pagamento avulso) e ASSINATURA (4 tiers, recorrente mensal).
--
-- APPEND-ONLY e IMUTÁVEL (0001–0010 já aplicadas). NÃO edita/renomeia nada das
-- migrations anteriores — as colunas do Stripe (stripe_*) PERMANECEM no banco
-- (migrations passadas são imutáveis), apenas deixam de ser usadas pelo código.
-- Idempotente: ADD COLUMN IF NOT EXISTS / CREATE ... IF NOT EXISTS /
-- drop policy if exists. Ver CLAUDE.md › Segurança + Migrations.
--
-- ORDEM DE APLICAÇÃO: rode este arquivo no SQL Editor DEPOIS da 0010.
-- NÃO precisa de seed de "price id" — no Asaas a assinatura é criada com o
-- `value` (preço do tier em reais) direto; não existe objeto de preço a semear.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- profiles.asaas_customer_id — o Customer do Asaas do usuário (id retornado pelo
-- Asaas quando o checkout é pago; gravado só server-side via service_role no
-- webhook). Fica atrás da RLS do profiles (só o dono/staff lê). Não é segredo.
-- -----------------------------------------------------------------------------
alter table public.profiles add column if not exists asaas_customer_id text;

-- -----------------------------------------------------------------------------
-- subscriptions — ids do Asaas. asaas_subscription_id UNIQUE pro webhook fazer
-- upsert idempotente (uma linha por assinatura do Asaas). NULLs continuam
-- permitidos (múltiplos NULLs são distintos no índice único do Postgres —
-- assinaturas antigas/trial sem id não colidem).
-- -----------------------------------------------------------------------------
alter table public.subscriptions add column if not exists asaas_customer_id     text;
alter table public.subscriptions add column if not exists asaas_subscription_id text;
create unique index if not exists subscriptions_asaas_sub_id_key
  on public.subscriptions (asaas_subscription_id);

-- -----------------------------------------------------------------------------
-- orders — ids do Asaas.
--   asaas_checkout_id: o id do Checkout do Asaas (chk_...). UNIQUE → idempotência
--     da LOJA. Como a gente PRÉ-CRIA o pedido 'pendente' já com este id e usa o
--     `orders.id` como externalReference do checkout, o webhook só finaliza o
--     pedido existente (não duplica em reentregas do evento).
--   asaas_payment_id: id do pagamento gerado (best-effort; auditoria).
-- NULLs permitidos (pedidos de PDV sem checkout do Asaas).
-- -----------------------------------------------------------------------------
alter table public.orders add column if not exists asaas_checkout_id text;
alter table public.orders add column if not exists asaas_payment_id  text;
create unique index if not exists orders_asaas_checkout_id_key
  on public.orders (asaas_checkout_id);

-- -----------------------------------------------------------------------------
-- asaas_events — idempotência/anti-replay do webhook do Asaas.
-- PK = id do evento do Asaas (campo `id` do payload, ex.: 'evt_...'). Se o id já
-- existe, o webhook não reprocessa. Sem acesso a cliente; leitura só owner;
-- escrita só server-side (Edge Function via service_role, que ignora RLS).
-- Espelha a stripe_events da 0006.
-- -----------------------------------------------------------------------------
create table if not exists public.asaas_events (
  id            text primary key,          -- id do evento do Asaas
  event         text,                      -- tipo do evento (ex.: 'CHECKOUT_PAID')
  processed_at  timestamptz not null default now()
);

-- =============================================================================
-- RLS — asaas_events: deny-by-default. Sem acesso a cliente; só owner lê.
-- Escrita só server-side (service_role ignora RLS) → sem policy de escrita.
-- =============================================================================
alter table public.asaas_events enable row level security;

drop policy if exists asaas_events_select_owner on public.asaas_events;
create policy asaas_events_select_owner on public.asaas_events
  for select to authenticated
  using (public.is_owner());



-- ===== 0012_asaas_checkout_link.sql =====

-- =============================================================================
-- 0012_asaas_checkout_link — ponte assinatura ↔ checkout do Asaas.
--
-- POR QUÊ (causa-raiz do "plano não vincula", provada por log ao vivo):
--   Nenhum evento do Asaas carrega, sozinho, as 3 peças que a gente precisa
--   ({user_id, tier_slug, asaas_subscription_id}):
--     • CHECKOUT_PAID  → tem o nosso externalReference (`sub:<user>:<tier>:<nonce>`),
--       logo sabe o USER e o TIER — mas NÃO traz o id da assinatura (o campo
--       `subscription` é só a config `{cycle,nextDueDate}`), e o Asaas NÃO indexa
--       a assinatura pelo nosso externalReference (GET ?externalReference volta ∅).
--     • PAYMENT_*      → traz o `subscription` id (`sub_…`) e o `customer` (`cus_…`),
--       mas com externalReference ∅ → não sabe de QUEM é.
--   O ÚNICO elo comum às duas pontas é o ID DO CHECKOUT: a gente o cria e recebe de
--   volta, ele vem no CHECKOUT_PAID (`checkout.id`) e no pagamento
--   (`payment.checkoutSession`). É o mesmo padrão que a LOJA já usa com sucesso
--   (orders.asaas_checkout_id). Guardando-o na linha da assinatura, o CHECKOUT_PAID
--   vincula user+tier na hora e o PAYMENT completa o asaas_subscription_id + pontos.
--
-- SEGURO / IDEMPOTENTE: só ADICIONA uma coluna nullable + índice único (não-parcial).
--   Não mexe em nada existente (as colunas stripe_*/asaas_* anteriores ficam intactas).
--   Re-rodar não quebra (IF NOT EXISTS).
--
-- Aplicar no SQL Editor do Supabase DEPOIS da 0011_asaas.
-- =============================================================================

alter table public.subscriptions
  add column if not exists asaas_checkout_id text;

comment on column public.subscriptions.asaas_checkout_id is
  'ID do Asaas Checkout que originou esta assinatura. Elo de correlação entre o '
  'CHECKOUT_PAID (checkout.id → grava user/tier) e o PAYMENT '
  '(payment.checkoutSession → completa o asaas_subscription_id + pontos). '
  'NULL em renovações e em linhas legadas.';

-- Único NÃO-parcial (espelha subscriptions_asaas_sub_id_key da 0011): no máximo UMA
-- assinatura por checkout. NULLs são DISTINTOS num índice único do Postgres, então
-- VÁRIAS linhas com asaas_checkout_id NULL (renovações / legado) continuam permitidas
-- — não precisa de índice parcial pra isso.
--
-- POR QUE NÃO-PARCIAL (importante): o upsert do webhook usa
-- `.upsert(..., { onConflict: 'asaas_checkout_id' })`, que o PostgREST traduz pra
-- `ON CONFLICT (asaas_checkout_id)` SEM predicado. O Postgres NÃO consegue inferir um
-- índice único PARCIAL como árbitro sem o `WHERE` no ON CONFLICT (erro 42P10), e o
-- PostgREST não emite esse `WHERE`. Um índice não-parcial é inferido direto — igual ao
-- `asaas_subscription_id` (0011), que por isso funciona com o mesmo padrão de upsert.
create unique index if not exists ux_subscriptions_asaas_checkout
  on public.subscriptions (asaas_checkout_id);



-- ===== 0012_downgrade.sql =====

-- =============================================================================
-- Casa Coffee Colab — 0012_downgrade.sql
-- DOWNGRADE de assinatura AGENDADO (vale no próximo ciclo, sem reembolso).
-- Espelho ao contrário do upgrade: em vez de cobrar a diferença e subir na hora,
-- a pessoa MANTÉM o tier atual até o fim do período já pago (current_period_end)
-- e, no próximo vencimento, a assinatura renova já no plano mais leve.
--
-- Como funciona: a Edge Function `downgrade-subscription` baixa o `value` da
-- assinatura no Asaas (a PRÓXIMA cobrança já vem menor) e grava aqui o slug do
-- tier de destino — SEM mexer no tier atual. Quando o pagamento da renovação
-- cai, o webhook (asaas-webhook › handleSubscriptionPayment) troca o tier pra
-- este destino e LIMPA a coluna. "Desfazer" volta a coluna pra NULL e restaura o
-- `value` cheio no Asaas.
--
-- APPEND-ONLY e IMUTÁVEL (0001–0011 já aplicadas). Não edita nada anterior.
-- Idempotente: ADD COLUMN IF NOT EXISTS. Ver CLAUDE.md › Segurança + Migrations.
--
-- ORDEM DE APLICAÇÃO: rode este arquivo no SQL Editor DEPOIS da 0011.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- subscriptions.scheduled_downgrade_to — slug do tier de destino de um downgrade
-- AGENDADO (NULL = nenhum agendado, o caso normal). FK pra tiers.slug (PK dos
-- tiers é slug). ON DELETE SET NULL: se um tier for removido do catálogo, o
-- agendamento apenas se dissolve (não trava o delete nem quebra a assinatura).
-- Fica atrás da RLS já existente de subscriptions (o dono lê a própria linha; a
-- ESCRITA é só server-side via service_role na Edge Function / webhook).
-- -----------------------------------------------------------------------------
alter table public.subscriptions
  add column if not exists scheduled_downgrade_to text
  references public.tiers(slug) on delete set null;



-- ===== 0013_redeem_reward_user_lock.sql =====

-- =============================================================================
-- 0013_redeem_reward_user_lock
-- -----------------------------------------------------------------------------
-- CORREÇÃO (gasto duplo de pontos): a redeem_reward da 0008 trava a LINHA DO
-- REWARD (`rewards_catalog … for update`), o que serializa resgates concorrentes
-- da MESMA recompensa — mas NÃO resgates simultâneos de recompensas DIFERENTES
-- pelo mesmo usuário. Sob READ COMMITTED, duas transações podem ler o mesmo saldo
-- (sum do ledger), cada uma passar no `v_saldo < custo` do seu reward e ambas
-- lançarem o débito: a pessoa gasta mais pontos do que tem (saldo fica negativo).
--
-- Fix: trava a LINHA DO PRÓPRIO USUÁRIO (`profiles … for update`) logo no início,
-- ANTES de ler o saldo. Isso serializa TODOS os resgates daquele usuário, seja qual
-- for a recompensa. Ordem de lock consistente (usuário → reward) evita deadlock; o
-- trigger update_points_balance atualiza a MESMA linha de profiles dentro da própria
-- transação (que já a detém), sem conflito.
--
-- Idempotente (CREATE OR REPLACE) e autocontida. Reaplica revoke/grant.
-- Migrations são imutáveis: esta SUBSTITUI o corpo da função definida na 0008.
-- =============================================================================
create or replace function public.redeem_reward(p_user_id uuid, p_reward_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reward         public.rewards_catalog;
  v_saldo          integer;
  v_redemption_id  uuid;
  v_codigo         text := null;
  v_tipo_redemption text;
begin
  -- Lock pessimista na linha do PRÓPRIO usuário: serializa TODOS os resgates dele
  -- (inclusive de recompensas diferentes) — impede leitura de saldo defasada e o
  -- consequente gasto duplo. Travar o usuário ANTES do reward mantém ordem única.
  perform 1 from public.profiles where id = p_user_id for update;

  -- Lock pessimista na linha do reward: serializa resgates concorrentes do MESMO
  -- item (estoque) e mantém o comportamento original.
  select * into v_reward from public.rewards_catalog where id = p_reward_id for update;
  if not found or not v_reward.ativo then
    return jsonb_build_object('ok', false, 'erro', 'recompensa indisponível');
  end if;
  if v_reward.estoque is not null and v_reward.estoque <= 0 then
    return jsonb_build_object('ok', false, 'erro', 'esgotado');
  end if;

  -- Saldo pela FONTE DA VERDADE (soma do ledger), nunca pelo cache.
  select coalesce(sum(delta), 0) into v_saldo
    from public.points_ledger where user_id = p_user_id;
  if v_saldo < v_reward.custo_em_pontos then
    return jsonb_build_object(
      'ok', false, 'erro', 'saldo insuficiente',
      'saldo', v_saldo, 'custo', v_reward.custo_em_pontos,
      'faltam', v_reward.custo_em_pontos - v_saldo);
  end if;

  v_tipo_redemption := case v_reward.tipo
    when 'produto_loja'  then 'produto'
    when 'produto_local' then 'parceiro'
    when 'cupom'         then 'cupom'
    else 'produto' end;

  insert into public.redemptions (user_id, tipo, partner_slug, pontos_gastos, status)
  values (p_user_id, v_tipo_redemption, v_reward.partner_slug, v_reward.custo_em_pontos, 'aprovado')
  returning id into v_redemption_id;

  -- Lançamento NEGATIVO (dispara o trigger que baixa o saldo). ref_* garante
  -- que um mesmo resgate nunca vira dois débitos.
  insert into public.points_ledger (user_id, delta, motivo, redemption_id, descricao, ref_type, ref_id)
  values (p_user_id, -v_reward.custo_em_pontos, 'resgate: ' || v_reward.nome,
          v_redemption_id, v_reward.nome, 'redemption', v_redemption_id::text);

  if v_reward.estoque is not null then
    update public.rewards_catalog set estoque = estoque - 1 where id = p_reward_id;
  end if;

  if v_reward.tipo = 'cupom' then
    -- Código único legível: CASA-XXXX (4 hex maiúsculos). Retenta se colidir.
    loop
      v_codigo := 'CASA-' || upper(substr(md5(gen_random_uuid()::text), 1, 4));
      exit when not exists (select 1 from public.coupons where codigo = v_codigo);
    end loop;
    insert into public.coupons (codigo, tipo_desconto, valor, validade, redemption_id, user_id)
    values (v_codigo, 'fixo', coalesce(v_reward.cupom_valor_centavos, 0),
            now() + interval '30 days', v_redemption_id, p_user_id);
    update public.redemptions set codigo = v_codigo where id = v_redemption_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'reward', v_reward.nome,
    'gasto', v_reward.custo_em_pontos,
    'saldo', v_saldo - v_reward.custo_em_pontos,
    'codigo', v_codigo);
end;
$$;

revoke all on function public.redeem_reward(uuid, uuid) from public;
grant execute on function public.redeem_reward(uuid, uuid) to service_role;



-- ===== 0014_perfil.sql =====

-- =============================================================================
-- 0014_perfil — os campos que faltavam no perfil da conta.
--
-- Repaginação de /conta/perfil (handoff de design): identidade (apelido,
-- aniversário), preferências de café, endereço de entrega da assinatura e
-- preferências de aviso. Tudo mora em `profiles` — é 1:1 com a pessoa, não
-- tem cardinalidade própria, e assim continua valendo a policy que já existe
-- (`profiles_update_self`: o dono edita a PRÓPRIA linha, RLS garante).
--
-- CPF NÃO entra aqui de propósito: o CPF é coletado na página hospedada do
-- Asaas, a gente não guarda. Menos dado sensível no banco, menos superfície.
--
-- A trigger `prevent_points_tamper` (0008) segue blindando points_balance e
-- tier_slug contra escrita do client; as colunas abaixo são livres pro dono.
--
-- Idempotente (add column if not exists). Não mexe em nada anterior.
-- =============================================================================

-- ── identidade ───────────────────────────────────────────────────────────────
alter table public.profiles add column if not exists apelido    text;
alter table public.profiles add column if not exists nascimento date;

-- ── preferências de café (o barista dá uma olhada antes de moer) ─────────────
alter table public.profiles add column if not exists cafe_metodo     text;
alter table public.profiles add column if not exists cafe_torra      text;
alter table public.profiles add column if not exists cafe_leite      text;
alter table public.profiles add column if not exists cafe_restricoes text;
alter table public.profiles add column if not exists cafe_horario    text;

-- ── endereço de entrega da assinatura ────────────────────────────────────────
alter table public.profiles add column if not exists end_cep         text;
alter table public.profiles add column if not exists end_rua         text;
alter table public.profiles add column if not exists end_numero      text;
alter table public.profiles add column if not exists end_complemento text;
alter table public.profiles add column if not exists end_bairro      text;
alter table public.profiles add column if not exists end_cidade      text;
alter table public.profiles add column if not exists end_uf          text;

-- ── avisos (a gente fala pouco, e só do que importa) ─────────────────────────
-- jsonb com os cinco canais. Default = o que o desenho mostra ligado.
alter table public.profiles add column if not exists avisos jsonb
  not null default '{"lotes":true,"pontos":true,"cobranca":true,"eventos":false,"whats":true}'::jsonb;

-- =============================================================================
-- CHECKs — o client é livre pra mandar o que quiser, o banco é quem decide o
-- que é válido. Valores nulos passam (campo em branco é um estado legítimo).
-- =============================================================================
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_cafe_metodo_check') then
    alter table public.profiles add constraint profiles_cafe_metodo_check
      check (cafe_metodo is null or cafe_metodo in ('coado','prensa','aeropress','espresso','moka'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'profiles_cafe_torra_check') then
    alter table public.profiles add constraint profiles_cafe_torra_check
      check (cafe_torra is null or cafe_torra in ('clara','media','escura'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'profiles_cafe_leite_check') then
    alter table public.profiles add constraint profiles_cafe_leite_check
      check (cafe_leite is null or cafe_leite in ('puro','integral','vegetal','tanto'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'profiles_cafe_horario_check') then
    alter table public.profiles add constraint profiles_cafe_horario_check
      check (cafe_horario is null or cafe_horario in ('manha','almoco','tarde','fim'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'profiles_end_uf_check') then
    alter table public.profiles add constraint profiles_end_uf_check
      check (end_uf is null or end_uf ~ '^[A-Z]{2}$');
  end if;

  -- Aniversário no passado (e num intervalo humano) — barra typo tipo 2205.
  if not exists (select 1 from pg_constraint where conname = 'profiles_nascimento_check') then
    alter table public.profiles add constraint profiles_nascimento_check
      check (nascimento is null or (nascimento < current_date and nascimento > date '1900-01-01'));
  end if;
end $$;

-- =============================================================================
-- Documentação das colunas (aparece no painel do Supabase).
-- =============================================================================
comment on column public.profiles.apelido    is 'como a pessoa prefere ser chamada no balcão';
comment on column public.profiles.nascimento is 'aniversário — no dia tem café por nossa conta';
comment on column public.profiles.avisos     is 'canais de aviso: lotes, pontos, cobranca, eventos, whats (booleans)';



-- ===== 0015_avatar.sql =====

-- =============================================================================
-- 0015_avatar — foto de perfil (Storage)
--
-- Bucket `avatares` + a coluna que guarda a URL. O limite de 3 MB e os tipos
-- aceitos ficam NO BUCKET, não só no JS: o client valida pra dar recado rápido,
-- mas quem realmente barra o arquivo grande é o Storage (confiança zero no
-- client, ver CLAUDE.md › Segurança).
--
-- Bucket PÚBLICO de propósito: avatar aparece na tela toda hora e signed URL
-- expira — o caminho tem o uuid do usuário, que não é adivinhável. Escrever,
-- porém, só o dono: as policies abaixo exigem que a primeira pasta do caminho
-- seja o próprio auth.uid() (`{user_id}/avatar`).
-- =============================================================================

-- Bucket ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatares',
  'avatares',
  true,
  3145728, -- 3 MB
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Coluna ---------------------------------------------------------------------
alter table public.profiles add column if not exists avatar_url text;

-- Policies (storage.objects já sobe com RLS ligado) ---------------------------
-- Leitura: o bucket é público, mas a policy explícita mantém o padrão
-- deny-by-default honesto — nada fica aberto por acidente de configuração.
drop policy if exists "avatares: qualquer um vê" on storage.objects;
create policy "avatares: qualquer um vê"
  on storage.objects for select
  using (bucket_id = 'avatares');

-- Escrita: só na PRÓPRIA pasta. `storage.foldername(name)` quebra o caminho em
-- array; a posição 1 é o uuid do dono.
drop policy if exists "avatares: dono manda a dele" on storage.objects;
create policy "avatares: dono manda a dele"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatares'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatares: dono troca a dele" on storage.objects;
create policy "avatares: dono troca a dele"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatares'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatares'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatares: dono apaga a dele" on storage.objects;
create policy "avatares: dono apaga a dele"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatares'
    and (storage.foldername(name))[1] = auth.uid()::text
  );



-- ===== 0016_sessoes.sql =====

-- =============================================================================
-- 0016_sessoes
-- -----------------------------------------------------------------------------
-- "sair de todos os aparelhos" vira "aparelhos conectados": a pessoa VÊ a lista
-- de onde a conta dela está aberta (nome do aparelho + endereço de IP + quando
-- foi visto) e escolhe o que encerrar, em vez de derrubar tudo no escuro.
--
-- Por que precisa de migration: as sessões vivem em `auth.sessions`, tabela
-- INTERNA do GoTrue. O schema `auth` NÃO é exposto pelo PostgREST, então o
-- client não consegue lê-la de jeito nenhum — nem com RLS, nem com policy. E o
-- supabase-js só oferece `signOut({ scope: 'global' })`, que é justamente o
-- tudo-ou-nada que a gente está trocando. O caminho é uma função SECURITY
-- DEFINER no schema `public`, que lê o `auth.sessions` por dentro e devolve
-- SÓ as linhas do próprio usuário.
--
-- Confiança zero no client, do mesmo jeito que no resto do projeto:
--   • o dono é sempre `auth.uid()`, lido do JWT no servidor — nunca um id que
--     o client mandou. Passar o id de outra pessoa não devolve nem apaga nada.
--   • "esta é a sessão atual" também vem do JWT (claim `session_id`), então
--     "sair dos outros aparelhos" não consegue ser enganado a manter o aparelho
--     errado (ou a derrubar o próprio e deixar o invasor dentro).
--   • as três funções são revogadas de `anon`/`public` e concedidas só a
--     `authenticated`. Deslogado não enxerga nada.
--   • `search_path` fixo (padrão das SECURITY DEFINER do projeto).
--
-- Apagar a linha de `auth.sessions` é o que de fato desconecta: os refresh
-- tokens daquela sessão morrem junto (a gente apaga explicitamente antes, pra
-- não depender do ON DELETE do GoTrue), então o aparelho não consegue mais
-- renovar. O access token que ele já tem na mão continua valendo até expirar
-- sozinho — é o MESMO comportamento do `signOut({ scope:'global' })` do
-- Supabase, que também não revoga JWT já emitido.
--
-- Idempotente (CREATE OR REPLACE) e autocontida. Não mexe em nada anterior.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- minhas_sessoes() — a lista pra tela.
-- Devolve o user_agent cru (quem transforma em "Chrome no Windows" é o front) e
-- o IP como texto. Só sessões vivas (`not_after` no futuro ou nulo), da mais
-- recente pra mais antiga.
-- -----------------------------------------------------------------------------
create or replace function public.minhas_sessoes()
returns table (
  id         uuid,
  aparelho   text,
  endereco   text,
  criada_em  timestamptz,
  vista_em   timestamptz,
  atual      boolean
)
language sql
security definer
stable
set search_path = public, auth, pg_temp
as $$
  select
    s.id,
    coalesce(s.user_agent, '')                          as aparelho,
    coalesce(host(s.ip), '')                            as endereco,
    s.created_at                                        as criada_em,
    coalesce(s.updated_at, s.created_at)                as vista_em,
    s.id is not distinct from nullif(
      current_setting('request.jwt.claims', true)::jsonb ->> 'session_id', ''
    )::uuid                                             as atual
  from auth.sessions s
  where s.user_id = auth.uid()
    and (s.not_after is null or s.not_after > now())
  order by coalesce(s.updated_at, s.created_at) desc;
$$;

-- -----------------------------------------------------------------------------
-- encerrar_sessao(uuid) — desconecta UM aparelho.
-- O `and user_id = auth.uid()` é a trava: id de terceiro simplesmente não casa
-- e a função devolve false, sem vazar se aquela sessão existe.
-- -----------------------------------------------------------------------------
create or replace function public.encerrar_sessao(p_session_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_n   integer;
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  delete from auth.refresh_tokens rt
   where rt.session_id = p_session_id
     and exists (
       select 1 from auth.sessions s
        where s.id = p_session_id and s.user_id = v_uid
     );

  delete from auth.sessions s
   where s.id = p_session_id
     and s.user_id = v_uid;

  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$$;

-- -----------------------------------------------------------------------------
-- encerrar_outras_sessoes() — desconecta todos MENOS este aparelho.
-- Qual é "este" vem do JWT, não do client. Se por algum motivo a claim
-- `session_id` não vier, a gente NÃO derruba nada (melhor não fazer do que
-- deslogar a pessoa do próprio aparelho por engano).
-- -----------------------------------------------------------------------------
create or replace function public.encerrar_outras_sessoes()
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_atual  uuid;
  v_n      integer;
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  v_atual := nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'session_id', '')::uuid;
  if v_atual is null then
    return 0;
  end if;

  delete from auth.refresh_tokens rt
   where rt.session_id in (
     select s.id from auth.sessions s
      where s.user_id = v_uid and s.id <> v_atual
   );

  delete from auth.sessions s
   where s.user_id = v_uid
     and s.id <> v_atual;

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- -----------------------------------------------------------------------------
-- Permissões: deslogado não enxerga nem encerra nada.
-- -----------------------------------------------------------------------------
revoke all on function public.minhas_sessoes()            from public, anon;
revoke all on function public.encerrar_sessao(uuid)       from public, anon;
revoke all on function public.encerrar_outras_sessoes()   from public, anon;

grant execute on function public.minhas_sessoes()          to authenticated;
grant execute on function public.encerrar_sessao(uuid)     to authenticated;
grant execute on function public.encerrar_outras_sessoes() to authenticated;



-- ===== 0017_admin.sql =====

-- =============================================================================
-- 0017_admin — o banco do console do administrador
-- -----------------------------------------------------------------------------
-- O console precisa de quatro coisas que o banco ainda não tinha:
--
--   1. SABER SE O PEDIDO É PRA ENTREGAR OU PRA RETIRAR. A `orders` guardava o
--      que foi comprado e quanto custou, mas não como a pessoa vai receber —
--      então o botão "confirmar enviado / retirado" não teria como saber de qual
--      dos dois casos se trata. Entram a coluna `modo_entrega` e um SNAPSHOT do
--      endereço no momento da compra (se a pessoa mudar de casa depois, o pedido
--      antigo continua mostrando pra onde foi de verdade), mais quem deu a baixa
--      e quando.
--
--   2. UM ADM QUE NUNCA SOME. `profiles.master` marca a conta do Casa; um
--      trigger BEFORE DELETE aborta a exclusão — inclusive a que viria em
--      cascata se alguém apagasse a linha em `auth.users`. E `senha_alterada_em`
--      nulo é o que faz o console exigir a troca da senha inicial no primeiro
--      acesso, antes de abrir qualquer tela.
--
--   3. PERMISSÃO INDIVIDUAL POR FUNCIONÁRIO. Hoje as policies liberam tudo com
--      `is_staff()`: quem é staff enxerga todos os pedidos, todo o ledger, todo
--      mundo. Isso não é "seleção individual". Entra a tabela
--      `staff_permissions` (uma linha por pessoa × permissão) e a função
--      `tem_permissao(...)`, e as policies sensíveis passam a perguntar pela
--      PERMISSÃO, não pelo cargo. O owner continua enxergando tudo.
--
--   4. LER O QUE O CLIENT NÃO ALCANÇA. O e-mail de cadastro mora em
--      `auth.users`, e o schema `auth` não é exposto pelo PostgREST (o mesmo
--      motivo que fez a 0016 existir). Então todo o console lê por RPC
--      SECURITY DEFINER: a permissão é checada lá dentro, o resultado já vem no
--      formato da tela, e o client nunca diz de quem é o dado que está pedindo.
--
-- Confiança zero no client, como no resto do projeto: quem age é sempre
-- `auth.uid()` lido do JWT; nenhuma função aceita "sou fulano" vindo de fora.
-- Toda ação que muda alguma coisa deixa rastro no `audit_log`.
--
-- APPEND-ONLY e IMUTÁVEL. Idempotente (IF NOT EXISTS / CREATE OR REPLACE /
-- drop policy + create).
-- =============================================================================


-- =============================================================================
-- 1. orders — entrega ou retirada, o snapshot do endereço e a baixa
-- =============================================================================

-- 'retirada' = a pessoa busca na casa; 'entrega' = a gente leva no endereço.
-- Fica nulo nos pedidos antigos (feitos antes de a loja perguntar).
alter table public.orders add column if not exists modo_entrega text
  check (modo_entrega in ('retirada', 'entrega'));

-- Snapshot do endereço no momento da compra. Copiado do `profiles` pela Edge
-- Function (nunca do client) e congelado aqui: o pedido tem que continuar
-- dizendo pra onde foi, mesmo que a pessoa mude o endereço do perfil depois.
alter table public.orders add column if not exists entrega_nome        text;
alter table public.orders add column if not exists entrega_telefone    text;
alter table public.orders add column if not exists entrega_cep         text;
alter table public.orders add column if not exists entrega_rua         text;
alter table public.orders add column if not exists entrega_numero      text;
alter table public.orders add column if not exists entrega_complemento text;
alter table public.orders add column if not exists entrega_bairro      text;
alter table public.orders add column if not exists entrega_cidade      text;
alter table public.orders add column if not exists entrega_uf          text;

-- Quem confirmou que saiu / foi retirado, e quando. O status vira 'entregue'
-- (já existe no CHECK desde a 0001); o rótulo "enviado" ou "retirado" quem dá
-- é o `modo_entrega`.
alter table public.orders add column if not exists entregue_em  timestamptz;
alter table public.orders add column if not exists entregue_por uuid
  references public.profiles (id) on delete set null;

create index if not exists idx_orders_modo_entrega on public.orders (modo_entrega);


-- =============================================================================
-- 2. redemptions — qual recompensa foi resgatada, e a baixa da retirada
-- -----------------------------------------------------------------------------
-- A `redeem_reward` guardava só o tipo e os pontos gastos: pra saber QUAL
-- recompensa era, o relatório teria que garimpar a descrição no ledger. Com
-- `reward_id` o relatório vira um join. Linhas antigas ficam nulas e caem no
-- fallback pela descrição do ledger.
-- =============================================================================
alter table public.redemptions add column if not exists reward_id uuid
  references public.rewards_catalog (id) on delete set null;

alter table public.redemptions add column if not exists usado_em  timestamptz;
alter table public.redemptions add column if not exists usado_por uuid
  references public.profiles (id) on delete set null;

create index if not exists idx_redemptions_status on public.redemptions (status);

-- redeem_reward: mesmo corpo da 0013 (lock do usuário antes do saldo), só
-- passando a gravar o `reward_id`. Migrations são imutáveis, então a função é
-- reescrita inteira aqui.
create or replace function public.redeem_reward(p_user_id uuid, p_reward_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reward         public.rewards_catalog;
  v_saldo          integer;
  v_redemption_id  uuid;
  v_codigo         text := null;
  v_tipo_redemption text;
begin
  -- Lock pessimista na linha do PRÓPRIO usuário: serializa TODOS os resgates
  -- dele (inclusive de recompensas diferentes) — impede leitura de saldo
  -- defasada e o consequente gasto duplo. Usuário antes do reward = ordem única.
  perform 1 from public.profiles where id = p_user_id for update;

  select * into v_reward from public.rewards_catalog where id = p_reward_id for update;
  if not found or not v_reward.ativo then
    return jsonb_build_object('ok', false, 'erro', 'recompensa indisponível');
  end if;
  if v_reward.estoque is not null and v_reward.estoque <= 0 then
    return jsonb_build_object('ok', false, 'erro', 'esgotado');
  end if;

  -- Saldo pela FONTE DA VERDADE (soma do ledger), nunca pelo cache.
  select coalesce(sum(delta), 0) into v_saldo
    from public.points_ledger where user_id = p_user_id;
  if v_saldo < v_reward.custo_em_pontos then
    return jsonb_build_object(
      'ok', false, 'erro', 'saldo insuficiente',
      'saldo', v_saldo, 'custo', v_reward.custo_em_pontos,
      'faltam', v_reward.custo_em_pontos - v_saldo);
  end if;

  v_tipo_redemption := case v_reward.tipo
    when 'produto_loja'  then 'produto'
    when 'produto_local' then 'parceiro'
    when 'cupom'         then 'cupom'
    else 'produto' end;

  insert into public.redemptions (user_id, tipo, product_id, partner_slug, pontos_gastos, status, reward_id)
  values (p_user_id, v_tipo_redemption, null, v_reward.partner_slug,
          v_reward.custo_em_pontos, 'aprovado', v_reward.id)
  returning id into v_redemption_id;

  insert into public.points_ledger (user_id, delta, motivo, redemption_id, descricao, ref_type, ref_id)
  values (p_user_id, -v_reward.custo_em_pontos, 'resgate: ' || v_reward.nome,
          v_redemption_id, v_reward.nome, 'redemption', v_redemption_id::text);

  if v_reward.estoque is not null then
    update public.rewards_catalog set estoque = estoque - 1 where id = p_reward_id;
  end if;

  if v_reward.tipo = 'cupom' then
    loop
      v_codigo := 'CASA-' || upper(substr(md5(gen_random_uuid()::text), 1, 4));
      exit when not exists (select 1 from public.coupons where codigo = v_codigo);
    end loop;
    insert into public.coupons (codigo, tipo_desconto, valor, validade, redemption_id, user_id)
    values (v_codigo, 'fixo', coalesce(v_reward.cupom_valor_centavos, 0),
            now() + interval '30 days', v_redemption_id, p_user_id);
    update public.redemptions set codigo = v_codigo where id = v_redemption_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'reward', v_reward.nome,
    'gasto', v_reward.custo_em_pontos,
    'saldo', v_saldo - v_reward.custo_em_pontos,
    'codigo', v_codigo);
end;
$$;

revoke all on function public.redeem_reward(uuid, uuid) from public;
grant execute on function public.redeem_reward(uuid, uuid) to service_role;


-- =============================================================================
-- 3. profiles — o adm que não some, e a senha inicial
-- =============================================================================
alter table public.profiles add column if not exists master boolean not null default false;
alter table public.profiles add column if not exists senha_alterada_em timestamptz;

-- Só pode existir UM master. Índice único PARCIAL: como ele só indexa as linhas
-- com `master = true`, e o valor indexado é sempre o mesmo `true`, uma segunda
-- conta marcada como master colide e é recusada pelo banco.
create unique index if not exists profiles_master_unico
  on public.profiles (master) where master;

-- ---------------------------------------------------------------------------
-- protect_master_account — a conta do Casa não se apaga e não se rebaixa.
--
-- DELETE: apagar a linha do master aborta a transação. Isso cobre também o
-- caminho indireto: `delete from auth.users` cascateia pra `profiles`, o
-- trigger levanta a exceção e a exclusão inteira volta atrás. Nem o
-- service_role passa — é de propósito, o pedido era "nunca pode ser excluído".
--
-- UPDATE: `master` só muda por dentro do banco (service_role, com `auth.uid()`
-- nulo) — é o script de criação. Sessão logada nenhuma liga ou desliga a
-- flag em si mesma. E o master não perde o papel de owner.
-- ---------------------------------------------------------------------------
create or replace function public.protect_master_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if old.master then
      raise exception 'a conta do adm master do Casa não pode ser excluída';
    end if;
    return old;
  end if;

  if new.master is distinct from old.master and auth.uid() is not null then
    raise exception 'a marcação de adm master não é editável por aqui';
  end if;

  if old.master and new.role is distinct from old.role then
    raise exception 'o adm master não pode mudar de papel';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protect_master_delete on public.profiles;
create trigger trg_protect_master_delete
  before delete on public.profiles
  for each row execute function public.protect_master_account();

-- Nome começando com "trg_p…" faz este rodar depois do trg_prevent_role_change
-- (triggers do mesmo evento disparam em ordem alfabética); os dois são BEFORE
-- UPDATE e independentes, então a ordem entre eles não muda o resultado.
drop trigger if exists trg_protect_master_update on public.profiles;
create trigger trg_protect_master_update
  before update on public.profiles
  for each row execute function public.protect_master_account();


-- =============================================================================
-- 4. staff_permissions — a seleção individual
-- -----------------------------------------------------------------------------
-- Uma linha por (pessoa, permissão). Sem linha = sem acesso. As sete permissões
-- são fechadas no CHECK pra não virar campo livre:
--
--   dashboard   ver o resumo do dia
--   pedidos     ver os pedidos da loja e o que tem dentro deles
--   entregas    dar baixa: confirmar enviado / retirado
--   resgates    ver e dar baixa nas recompensas trocadas por pontos
--   usuarios    ver a lista de pessoas cadastradas
--   relatorios  ver os relatórios (itens vendidos, itens resgatados, pontos)
--   equipe      conceder e tirar permissões dos outros
-- =============================================================================
create table if not exists public.staff_permissions (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  permissao   text not null check (permissao in (
                'dashboard', 'pedidos', 'entregas', 'resgates',
                'usuarios', 'relatorios', 'equipe')),
  granted_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  primary key (user_id, permissao)
);

alter table public.staff_permissions enable row level security;

-- Cada um vê as próprias permissões; quem cuida da equipe vê as de todos.
-- Escrita é só pela RPC `admin_definir_permissoes` (SECURITY DEFINER): sem
-- policy de INSERT/UPDATE/DELETE, ninguém escreve daqui.
drop policy if exists staff_permissions_select on public.staff_permissions;
create policy staff_permissions_select on public.staff_permissions
  for select to authenticated
  using (user_id = auth.uid() or public.is_owner());


-- =============================================================================
-- 5. tem_permissao / pode_entrar_no_console
-- -----------------------------------------------------------------------------
-- O owner tem tudo, sempre — é o dono do Casa, e é a saída de emergência caso
-- alguém se tranque pra fora da própria equipe. Todo o resto (inclusive
-- gerente e staff) depende da permissão individual: cargo não abre porta.
--
-- SECURITY DEFINER, então a leitura de `staff_permissions` aqui dentro não
-- passa pela RLS — o que evita a recursão de uma policy chamar a função que
-- consulta a tabela protegida pela própria policy.
-- =============================================================================
create or replace function public.tem_permissao(p_perm text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.profiles where id = auth.uid()) = 'owner'
    or exists (
      select 1 from public.staff_permissions
       where user_id = auth.uid() and permissao = p_perm
    ),
    false
  );
$$;

-- Quem pode ao menos ABRIR o console: o owner, ou quem tem qualquer permissão.
create or replace function public.pode_entrar_no_console()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.profiles where id = auth.uid()) = 'owner'
    or exists (select 1 from public.staff_permissions where user_id = auth.uid()),
    false
  );
$$;

revoke all on function public.tem_permissao(text)        from public, anon;
revoke all on function public.pode_entrar_no_console()   from public, anon;
grant execute on function public.tem_permissao(text)      to authenticated;
grant execute on function public.pode_entrar_no_console() to authenticated;


-- =============================================================================
-- 6. Policies — de "é staff?" pra "tem ESTA permissão?"
-- -----------------------------------------------------------------------------
-- Mesmo com todo o console lendo por RPC, as policies precisam apertar: elas
-- são a porta que o PostgREST abre direto, e enquanto disserem `is_staff()`
-- qualquer pessoa marcada como staff lê tudo, permissão ou não.
-- O trecho `= auth.uid()` de cada uma continua igual: o cliente nunca perde
-- acesso ao próprio dado.
-- =============================================================================
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.tem_permissao('usuarios'));

drop policy if exists subscriptions_select_own on public.subscriptions;
create policy subscriptions_select_own on public.subscriptions
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('usuarios'));

drop policy if exists orders_select_own on public.orders;
create policy orders_select_own on public.orders
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('pedidos'));

drop policy if exists order_items_select_own on public.order_items;
create policy order_items_select_own on public.order_items
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and (o.user_id = auth.uid() or public.tem_permissao('pedidos'))
    )
  );

drop policy if exists points_ledger_select_own on public.points_ledger;
create policy points_ledger_select_own on public.points_ledger
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('relatorios'));

drop policy if exists redemptions_select_own on public.redemptions;
create policy redemptions_select_own on public.redemptions
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('resgates'));

drop policy if exists user_achievements_select_own on public.user_achievements;
create policy user_achievements_select_own on public.user_achievements
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('usuarios'));


-- =============================================================================
-- 7. As RPCs do console
-- -----------------------------------------------------------------------------
-- Todas conferem a permissão na primeira linha e levantam exceção sem ela — o
-- front esconder o botão é conforto, não segurança. Todas são revogadas de
-- `anon`/`public`. As que mudam alguma coisa gravam no `audit_log`.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- admin_minhas_permissoes — o que o console pergunta antes de desenhar a tela:
-- quem é, o que pode abrir, e se ainda está com a senha inicial.
-- Não exige permissão nenhuma (só sessão): é a própria linha de quem chama.
-- ---------------------------------------------------------------------------
create or replace function public.admin_minhas_permissoes()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_prof public.profiles;
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('console', false);
  end if;

  return jsonb_build_object(
    'console',        public.pode_entrar_no_console(),
    'nome',           coalesce(v_prof.full_name, ''),
    'papel',          v_prof.role,
    'master',         v_prof.master,
    'senha_trocada',  v_prof.senha_alterada_em is not null,
    'permissoes',     coalesce(
                        (select jsonb_agg(permissao order by permissao)
                           from public.staff_permissions where user_id = v_uid),
                        '[]'::jsonb),
    'tudo',           v_prof.role = 'owner'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_senha_alterada — marca que a senha inicial já foi trocada. Quem troca a
-- senha de verdade é o Supabase Auth (updateUser), no client; isto aqui só
-- desarma a tela de "troca obrigatória".
-- ---------------------------------------------------------------------------
create or replace function public.admin_senha_alterada()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  update public.profiles set senha_alterada_em = now(), updated_at = now()
   where id = v_uid;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'senha_alterada', 'profiles', v_uid::text, '{}'::jsonb);

  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_dashboard — o resumo do dia. Datas no fuso de Novo Hamburgo, senão
-- "hoje" viraria o dia às 21h.
-- ---------------------------------------------------------------------------
create or replace function public.admin_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not public.tem_permissao('dashboard') then
    raise exception 'sem permissão pra ver o painel';
  end if;

  return jsonb_build_object(
    'pedidos_hoje', (
      select count(*) from public.orders o
       where (o.created_at at time zone 'America/Sao_Paulo')::date = v_hoje
         and o.status <> 'cancelado'),
    'receita_hoje_centavos', (
      select coalesce(sum(o.total_centavos), 0) from public.orders o
       where (o.created_at at time zone 'America/Sao_Paulo')::date = v_hoje
         and o.status in ('pago', 'preparando', 'pronto', 'entregue')),
    'receita_mes_centavos', (
      select coalesce(sum(o.total_centavos), 0) from public.orders o
       where date_trunc('month', o.created_at at time zone 'America/Sao_Paulo')
             = date_trunc('month', v_hoje::timestamp)
         and o.status in ('pago', 'preparando', 'pronto', 'entregue')),
    'a_entregar', (
      select count(*) from public.orders o
       where o.status in ('pago', 'preparando', 'pronto')
         and coalesce(o.modo_entrega, 'entrega') = 'entrega'),
    'a_retirar', (
      select count(*) from public.orders o
       where o.status in ('pago', 'preparando', 'pronto')
         and o.modo_entrega = 'retirada'),
    'resgates_abertos', (
      select count(*) from public.redemptions r
       where r.status in ('solicitado', 'aprovado')),
    'pessoas', (select count(*) from public.profiles),
    'assinantes_ativos', (
      select count(distinct s.user_id) from public.subscriptions s
       where s.status = 'ativa'),
    'pontos_em_circulacao', (
      select coalesce(sum(p.points_balance), 0) from public.profiles p)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_pedidos — a lista de pedidos da loja.
--   p_status  filtra por status ('abertos' = tudo que já foi pago e ainda não
--             saiu); nulo = todos.
--   p_modo    'entrega' | 'retirada'; nulo = os dois.
-- ---------------------------------------------------------------------------
create or replace function public.admin_pedidos(
  p_status text default null,
  p_modo   text default null,
  p_limite integer default 200
)
returns table (
  id                uuid,
  criado_em         timestamptz,
  status            text,
  modo_entrega      text,
  cliente_nome      text,
  cliente_email     text,
  cliente_telefone  text,
  total_centavos    integer,
  desconto_centavos integer,
  tier_slug         text,
  entrega_cep       text,
  entrega_rua       text,
  entrega_numero    text,
  entrega_complemento text,
  entrega_bairro    text,
  entrega_cidade    text,
  entrega_uf        text,
  entregue_em       timestamptz,
  entregue_por_nome text,
  itens             jsonb
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if not public.tem_permissao('pedidos') then
    raise exception 'sem permissão pra ver os pedidos';
  end if;

  return query
    select
      o.id,
      o.created_at,
      o.status,
      o.modo_entrega,
      coalesce(o.entrega_nome, pr.full_name, '')            as cliente_nome,
      coalesce(u.email, '')                                  as cliente_email,
      coalesce(o.entrega_telefone, pr.telefone, '')          as cliente_telefone,
      o.total_centavos,
      o.desconto_centavos,
      o.tier_slug_aplicado,
      o.entrega_cep, o.entrega_rua, o.entrega_numero, o.entrega_complemento,
      o.entrega_bairro, o.entrega_cidade, o.entrega_uf,
      o.entregue_em,
      coalesce(baixa.full_name, '')                          as entregue_por_nome,
      coalesce((
        select jsonb_agg(jsonb_build_object(
                 'nome',     oi.nome_snapshot,
                 'variante', oi.variante_snapshot,
                 'qtd',      oi.qtd,
                 'preco_centavos', oi.preco_unit_centavos)
                 order by oi.nome_snapshot)
          from public.order_items oi where oi.order_id = o.id
      ), '[]'::jsonb)                                        as itens
    from public.orders o
    left join public.profiles pr on pr.id = o.user_id
    left join auth.users     u  on u.id  = o.user_id
    left join public.profiles baixa on baixa.id = o.entregue_por
    where o.origem = 'site'
      and (
        p_status is null
        or (p_status = 'abertos' and o.status in ('pago', 'preparando', 'pronto'))
        or o.status = p_status
      )
      and (p_modo is null or coalesce(o.modo_entrega, 'entrega') = p_modo)
    order by o.created_at desc
    limit greatest(1, least(coalesce(p_limite, 200), 500));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_marcar_entregue — o botão "confirmar enviado / retirado".
-- Só pedido PAGO pode receber baixa: pendente ou cancelado não saiu da casa.
-- Idempotente: confirmar de novo devolve `ok` sem mexer no que já foi gravado.
-- ---------------------------------------------------------------------------
create or replace function public.admin_marcar_entregue(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ord public.orders;
begin
  if not public.tem_permissao('entregas') then
    raise exception 'sem permissão pra dar baixa em pedido';
  end if;

  select * into v_ord from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'pedido não encontrado');
  end if;

  if v_ord.status = 'entregue' then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'entregue_em', v_ord.entregue_em);
  end if;

  if v_ord.status not in ('pago', 'preparando', 'pronto') then
    return jsonb_build_object(
      'ok', false,
      'erro', case v_ord.status
                when 'pendente'  then 'esse pedido ainda não foi pago'
                when 'cancelado' then 'esse pedido foi cancelado'
                else 'esse pedido não pode receber baixa agora' end);
  end if;

  update public.orders
     set status = 'entregue', entregue_em = now(), entregue_por = v_uid, updated_at = now()
   where id = p_order_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'pedido_entregue', 'orders', p_order_id::text,
          jsonb_build_object('modo', coalesce(v_ord.modo_entrega, 'entrega')));

  return jsonb_build_object(
    'ok', true,
    'modo', coalesce(v_ord.modo_entrega, 'entrega'),
    'entregue_em', now());
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_resgates — as recompensas trocadas por pontos.
-- O nome da recompensa vem do `reward_id`; nos resgates antigos (sem a coluna)
-- cai na descrição que o ledger guardou.
-- ---------------------------------------------------------------------------
create or replace function public.admin_resgates(
  p_status text default null,
  p_limite integer default 200
)
returns table (
  id             uuid,
  criado_em      timestamptz,
  status         text,
  tipo           text,
  recompensa     text,
  pontos_gastos  integer,
  codigo         text,
  cliente_nome   text,
  cliente_email  text,
  usado_em       timestamptz,
  usado_por_nome text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if not public.tem_permissao('resgates') then
    raise exception 'sem permissão pra ver os resgates';
  end if;

  return query
    select
      r.id,
      r.created_at,
      r.status,
      r.tipo,
      coalesce(rw.nome, pl.descricao, 'recompensa')  as recompensa,
      r.pontos_gastos,
      coalesce(r.codigo, '')                          as codigo,
      coalesce(pr.full_name, '')                      as cliente_nome,
      coalesce(u.email, '')                           as cliente_email,
      r.usado_em,
      coalesce(baixa.full_name, '')                   as usado_por_nome
    from public.redemptions r
    left join public.rewards_catalog rw on rw.id = r.reward_id
    left join public.points_ledger  pl on pl.redemption_id = r.id
    left join public.profiles       pr on pr.id = r.user_id
    left join auth.users            u  on u.id  = r.user_id
    left join public.profiles       baixa on baixa.id = r.usado_por
    where (
      p_status is null
      or (p_status = 'abertos' and r.status in ('solicitado', 'aprovado'))
      or r.status = p_status
    )
    order by r.created_at desc
    limit greatest(1, least(coalesce(p_limite, 200), 500));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_marcar_resgate_usado — "entregue em mãos". Vira status 'usado'.
-- Não devolve ponto nenhum: o débito já está no ledger, e o ledger é
-- append-only.
-- ---------------------------------------------------------------------------
create or replace function public.admin_marcar_resgate_usado(p_redemption_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_red public.redemptions;
begin
  if not public.tem_permissao('resgates') then
    raise exception 'sem permissão pra dar baixa em resgate';
  end if;

  select * into v_red from public.redemptions where id = p_redemption_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'resgate não encontrado');
  end if;

  if v_red.status = 'usado' then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'usado_em', v_red.usado_em);
  end if;

  if v_red.status not in ('solicitado', 'aprovado') then
    return jsonb_build_object('ok', false, 'erro', 'esse resgate já foi ' || v_red.status);
  end if;

  update public.redemptions
     set status = 'usado', usado_em = now(), usado_por = v_uid, updated_at = now()
   where id = p_redemption_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'resgate_usado', 'redemptions', p_redemption_id::text,
          jsonb_build_object('pontos', v_red.pontos_gastos));

  return jsonb_build_object('ok', true, 'usado_em', now());
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_usuarios — o relatório de pessoas. O e-mail sai daqui porque mora em
-- `auth.users`, que o PostgREST não expõe.
-- `p_busca` casa por nome, e-mail ou telefone (case-insensitive).
-- ---------------------------------------------------------------------------
create or replace function public.admin_usuarios(
  p_busca  text default null,
  p_limite integer default 200
)
returns table (
  id                uuid,
  nome              text,
  email             text,
  telefone          text,
  papel             text,
  master            boolean,
  plano             text,
  plano_status      text,
  pontos            integer,
  pedidos           bigint,
  gasto_centavos    bigint,
  cadastrado_em     timestamptz,
  ultimo_acesso     timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('usuarios') then
    raise exception 'sem permissão pra ver as pessoas';
  end if;

  return query
    select
      p.id,
      coalesce(p.full_name, '')          as nome,
      coalesce(u.email, '')              as email,
      coalesce(p.telefone, '')           as telefone,
      p.role                             as papel,
      p.master,
      coalesce(t.nome, '')               as plano,
      coalesce((
        select s.status from public.subscriptions s
         where s.user_id = p.id
         order by s.current_period_end desc nulls last, s.created_at desc
         limit 1
      ), '')                             as plano_status,
      coalesce(p.points_balance, 0)      as pontos,
      (select count(*) from public.orders o
        where o.user_id = p.id and o.status in ('pago','preparando','pronto','entregue'))
                                         as pedidos,
      (select coalesce(sum(o.total_centavos), 0) from public.orders o
        where o.user_id = p.id and o.status in ('pago','preparando','pronto','entregue'))
                                         as gasto_centavos,
      p.created_at                       as cadastrado_em,
      u.last_sign_in_at                  as ultimo_acesso
    from public.profiles p
    left join auth.users  u on u.id = p.id
    left join public.tiers t on t.slug = p.tier_slug
    where v_busca is null
       or p.full_name ilike '%' || v_busca || '%'
       or u.email     ilike '%' || v_busca || '%'
       or p.telefone  ilike '%' || v_busca || '%'
    order by p.created_at desc
    limit greatest(1, least(coalesce(p_limite, 200), 1000));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_relatorio_itens — o que a loja vendeu, agrupado por item + variante.
-- Conta pedido pago pra cima (pago/preparando/pronto/entregue); pendente e
-- cancelado ficam de fora.
-- ---------------------------------------------------------------------------
create or replace function public.admin_relatorio_itens(
  p_desde timestamptz default null,
  p_ate   timestamptz default null
)
returns table (
  item            text,
  variante        text,
  qtd             bigint,
  pedidos         bigint,
  total_centavos  bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra ver os relatórios';
  end if;

  return query
    select
      oi.nome_snapshot                       as item,
      coalesce(oi.variante_snapshot, '')     as variante,
      sum(oi.qtd)::bigint                    as qtd,
      count(distinct oi.order_id)::bigint    as pedidos,
      sum(oi.qtd * oi.preco_unit_centavos)::bigint as total_centavos
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where o.status in ('pago', 'preparando', 'pronto', 'entregue')
      and (p_desde is null or o.created_at >= p_desde)
      and (p_ate   is null or o.created_at <  p_ate)
    group by oi.nome_snapshot, coalesce(oi.variante_snapshot, '')
    order by sum(oi.qtd) desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_relatorio_resgates — o que saiu por pontos, agrupado por recompensa.
-- ---------------------------------------------------------------------------
create or replace function public.admin_relatorio_resgates(
  p_desde timestamptz default null,
  p_ate   timestamptz default null
)
returns table (
  recompensa      text,
  tipo            text,
  vezes           bigint,
  pontos          bigint,
  entregues       bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra ver os relatórios';
  end if;

  return query
    select
      coalesce(rw.nome, pl.descricao, 'recompensa')      as recompensa,
      r.tipo,
      count(*)::bigint                                    as vezes,
      sum(r.pontos_gastos)::bigint                        as pontos,
      count(*) filter (where r.status = 'usado')::bigint  as entregues
    from public.redemptions r
    left join public.rewards_catalog rw on rw.id = r.reward_id
    left join public.points_ledger  pl on pl.redemption_id = r.id
    where r.status <> 'cancelado'
      and (p_desde is null or r.created_at >= p_desde)
      and (p_ate   is null or r.created_at <  p_ate)
    group by coalesce(rw.nome, pl.descricao, 'recompensa'), r.tipo
    order by count(*) desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_equipe — quem já tem alguma permissão, e quais.
-- ---------------------------------------------------------------------------
create or replace function public.admin_equipe()
returns table (
  id          uuid,
  nome        text,
  email       text,
  papel       text,
  master      boolean,
  permissoes  jsonb
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if not public.tem_permissao('equipe') then
    raise exception 'sem permissão pra ver a equipe';
  end if;

  return query
    select
      p.id,
      coalesce(p.full_name, '')  as nome,
      coalesce(u.email, '')      as email,
      p.role                     as papel,
      p.master,
      coalesce((
        select jsonb_agg(sp.permissao order by sp.permissao)
          from public.staff_permissions sp where sp.user_id = p.id
      ), '[]'::jsonb)            as permissoes
    from public.profiles p
    left join auth.users u on u.id = p.id
    where p.role = 'owner'
       or exists (select 1 from public.staff_permissions sp where sp.user_id = p.id)
    order by p.role = 'owner' desc, p.full_name nulls last;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_definir_permissoes — dá e tira permissões, de uma pessoa por vez.
-- A lista chega inteira e substitui a anterior (o que não veio, sai).
--
-- Travas contra escalada de privilégio:
--   • ninguém edita as próprias permissões (nem pra tirar);
--   • o owner e o master não têm permissão editável — eles já têm tudo;
--   • só o owner concede a permissão 'equipe' (senão um funcionário criaria
--     outro gestor de equipe e o controle vazaria de mão em mão).
-- ---------------------------------------------------------------------------
create or replace function public.admin_definir_permissoes(
  p_user_id     uuid,
  p_permissoes  text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_alvo  public.profiles;
  v_lista text[] := coalesce(p_permissoes, '{}');
begin
  if not public.tem_permissao('equipe') then
    raise exception 'sem permissão pra mexer na equipe';
  end if;

  if p_user_id = v_uid then
    raise exception 'não dá pra mudar as próprias permissões';
  end if;

  select * into v_alvo from public.profiles where id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'pessoa não encontrada');
  end if;

  if v_alvo.role = 'owner' or v_alvo.master then
    return jsonb_build_object('ok', false, 'erro', 'o adm do Casa já tem tudo — não há o que ajustar aqui');
  end if;

  if 'equipe' = any (v_lista) and not public.is_owner() then
    return jsonb_build_object('ok', false, 'erro', 'só o adm do Casa pode delegar o cuidado da equipe');
  end if;

  delete from public.staff_permissions
   where user_id = p_user_id
     and not (permissao = any (v_lista));

  insert into public.staff_permissions (user_id, permissao, granted_by)
  select p_user_id, perm, v_uid from unnest(v_lista) as perm
  on conflict (user_id, permissao) do nothing;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'permissoes_definidas', 'staff_permissions', p_user_id::text,
          jsonb_build_object('permissoes', to_jsonb(v_lista)));

  return jsonb_build_object('ok', true, 'permissoes', to_jsonb(v_lista));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_buscar_pessoa — procura alguém pra convidar pro time (por e-mail ou
-- nome). Só quem cuida da equipe. Devolve pouca coisa de propósito.
-- ---------------------------------------------------------------------------
create or replace function public.admin_buscar_pessoa(p_busca text)
returns table (
  id     uuid,
  nome   text,
  email  text,
  papel  text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('equipe') then
    raise exception 'sem permissão pra mexer na equipe';
  end if;
  if v_busca is null or length(v_busca) < 3 then
    return;
  end if;

  return query
    select p.id, coalesce(p.full_name, ''), coalesce(u.email, ''), p.role
    from public.profiles p
    left join auth.users u on u.id = p.id
    where p.full_name ilike '%' || v_busca || '%'
       or u.email     ilike '%' || v_busca || '%'
    order by p.full_name nulls last
    limit 20;
end;
$$;


-- =============================================================================
-- 8. Permissões das RPCs — deslogado não alcança nada.
-- =============================================================================
revoke all on function public.admin_minhas_permissoes()                     from public, anon;
revoke all on function public.admin_senha_alterada()                        from public, anon;
revoke all on function public.admin_dashboard()                             from public, anon;
revoke all on function public.admin_pedidos(text, text, integer)            from public, anon;
revoke all on function public.admin_marcar_entregue(uuid)                   from public, anon;
revoke all on function public.admin_resgates(text, integer)                 from public, anon;
revoke all on function public.admin_marcar_resgate_usado(uuid)              from public, anon;
revoke all on function public.admin_usuarios(text, integer)                 from public, anon;
revoke all on function public.admin_relatorio_itens(timestamptz, timestamptz)    from public, anon;
revoke all on function public.admin_relatorio_resgates(timestamptz, timestamptz) from public, anon;
revoke all on function public.admin_equipe()                                from public, anon;
revoke all on function public.admin_definir_permissoes(uuid, text[])        from public, anon;
revoke all on function public.admin_buscar_pessoa(text)                     from public, anon;

grant execute on function public.admin_minhas_permissoes()                   to authenticated;
grant execute on function public.admin_senha_alterada()                      to authenticated;
grant execute on function public.admin_dashboard()                           to authenticated;
grant execute on function public.admin_pedidos(text, text, integer)          to authenticated;
grant execute on function public.admin_marcar_entregue(uuid)                 to authenticated;
grant execute on function public.admin_resgates(text, integer)               to authenticated;
grant execute on function public.admin_marcar_resgate_usado(uuid)            to authenticated;
grant execute on function public.admin_usuarios(text, integer)               to authenticated;
grant execute on function public.admin_relatorio_itens(timestamptz, timestamptz)    to authenticated;
grant execute on function public.admin_relatorio_resgates(timestamptz, timestamptz) to authenticated;
grant execute on function public.admin_equipe()                              to authenticated;
grant execute on function public.admin_definir_permissoes(uuid, text[])      to authenticated;
grant execute on function public.admin_buscar_pessoa(text)                   to authenticated;



-- ===== 0018_assinatura_pendente_e_equipe.sql =====

-- =============================================================================
-- 0018 — Assinatura 'pendente' + trava por delta na permissão 'equipe'
--
-- Duas correções independentes que vieram da mesma varredura de bugs. Ficam no
-- mesmo arquivo porque são pequenas e entram juntas na mesma leva.
--
--  (a) subscriptions.status ganha o valor 'pendente'. A create-checkout-session
--      passou a pré-marcar a assinatura ANTES de mandar a pessoa pro checkout
--      hospedado do Asaas — é essa linha que a delete-account consulta pra não
--      apagar uma conta no exato intervalo entre o cartão ser cobrado e o
--      CHECKOUT_PAID chegar (senão sobra uma recorrência órfã cobrando alguém
--      que já não existe aqui). Sem ampliar o CHECK da 0001, esse insert bate
--      na constraint e a trava nunca protege ninguém.
--
--  (b) admin_definir_permissoes passa a comparar o DELTA da permissão 'equipe'
--      em vez do simples "veio na lista". Ver o bloco lá embaixo.
--
-- Idempotente: dá pra rodar mais de uma vez sem estrago.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- (a) subscriptions.status aceita 'pendente'
--
-- A CHECK da 0001 foi declarada inline na coluna, então quem nomeou foi o
-- Postgres. Em vez de chutar o nome padrão, a gente descobre qual é a CHECK que
-- fala de `status` e derruba essa — assim a migration não quebra se o nome
-- gerado for outro.
--
-- Nada de dado existente muda: 'pendente' é um valor NOVO, os quatro antigos
-- continuam válidos. E ele NÃO concede benefício: getEffectiveSubscription só
-- olha ('ativa','pausada'), então uma linha pendente não vira plano de graça.
-- ---------------------------------------------------------------------------
do $$
declare
  v_nome text;
begin
  select con.conname
    into v_nome
    from pg_constraint con
    join pg_class      rel on rel.oid = con.conrelid
    join pg_namespace  nsp on nsp.oid = rel.relnamespace
   where nsp.nspname = 'public'
     and rel.relname = 'subscriptions'
     and con.contype = 'c'
     and pg_get_constraintdef(con.oid) ilike '%status%'
   limit 1;

  if v_nome is not null then
    execute format('alter table public.subscriptions drop constraint %I', v_nome);
  end if;
end $$;

alter table public.subscriptions
  add constraint subscriptions_status_check
  check (status in ('trial', 'pendente', 'ativa', 'pausada', 'cancelada'));

-- ---------------------------------------------------------------------------
-- (b) admin_definir_permissoes — trava da 'equipe' por DELTA
--
-- A versão da 0017 barrava quando 'equipe' aparecia na lista que chegou. Só que
-- a lista é o estado COMPLETO das permissões da pessoa (o que não vem, sai), e
-- o console manda de volta tudo que está marcado — inclusive os checkboxes que
-- ele mesmo desabilitou. Isso dava dois erros de lado opostos:
--
--   • FALSO POSITIVO — um gestor de equipe (não-owner) mexendo em QUALQUER
--     outra permissão de alguém que JÁ tinha 'equipe' via a lista chegar com
--     'equipe' dentro e levava "só o adm do Casa pode delegar...", sem estar
--     tentando delegar nada. A tela travava por completo pra essa pessoa.
--
--   • FALSO NEGATIVO — TIRAR a 'equipe' de alguém passava batido, porque aí
--     'equipe' justamente NÃO vem na lista. Ou seja: conceder era protegido,
--     revogar não. Um funcionário podia derrubar o gestor de equipe.
--
-- A comparação certa é a mudança: se a pessoa tinha 'equipe' e continua tendo
-- (ou não tinha e segue sem), não há nada a proteger — passa. Se o estado da
-- 'equipe' MUDA, nos dois sentidos, aí sim só o owner.
--
-- O resto da função é idêntico à 0017 (create or replace exige o corpo inteiro).
-- ---------------------------------------------------------------------------
create or replace function public.admin_definir_permissoes(
  p_user_id     uuid,
  p_permissoes  text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid          uuid := auth.uid();
  v_alvo         public.profiles;
  v_lista        text[] := coalesce(p_permissoes, '{}');
  v_tinha_equipe boolean;
  v_tera_equipe  boolean;
begin
  if not public.tem_permissao('equipe') then
    raise exception 'sem permissão pra mexer na equipe';
  end if;

  if p_user_id = v_uid then
    raise exception 'não dá pra mudar as próprias permissões';
  end if;

  select * into v_alvo from public.profiles where id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'pessoa não encontrada');
  end if;

  if v_alvo.role = 'owner' or v_alvo.master then
    return jsonb_build_object('ok', false, 'erro', 'o adm do Casa já tem tudo — não há o que ajustar aqui');
  end if;

  -- A trava por delta: compara o que a pessoa TEM com o que vai ficar.
  v_tinha_equipe := exists (
    select 1 from public.staff_permissions
     where user_id = p_user_id and permissao = 'equipe'
  );
  v_tera_equipe := 'equipe' = any (v_lista);

  if v_tinha_equipe is distinct from v_tera_equipe and not public.is_owner() then
    return jsonb_build_object(
      'ok', false,
      'erro', 'só o adm do Casa mexe em quem cuida da equipe'
    );
  end if;

  delete from public.staff_permissions
   where user_id = p_user_id
     and not (permissao = any (v_lista));

  insert into public.staff_permissions (user_id, permissao, granted_by)
  select p_user_id, perm, v_uid from unnest(v_lista) as perm
  on conflict (user_id, permissao) do nothing;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'permissoes_definidas', 'staff_permissions', p_user_id::text,
          jsonb_build_object('permissoes', to_jsonb(v_lista)));

  return jsonb_build_object('ok', true, 'permissoes', to_jsonb(v_lista));
end;
$$;



-- ===== 0019_menor_privilegio_equipe.sql =====

-- =============================================================================
-- 0019 — Menor privilégio na delegação de permissões da equipe
--
-- Fecha uma escalada de privilégio no admin_definir_permissoes (0017/0018): um
-- gestor de equipe (não-owner, com a permissão 'equipe') conseguia CONCEDER a
-- terceiros permissões que ele mesmo NÃO tinha — inclusive 'usuarios' (todo o
-- cadastro/PII) e 'relatorios' (financeiro) — e depois logar na conta que ele
-- mesmo elevou. As travas anteriores só cobriam: ator tem 'equipe', alvo não é
-- owner/master, e mudança na permissão 'equipe' (só owner). Faltava exigir que o
-- ator já possua a permissão que está concedendo.
--
-- REGRA NOVA: quem não é owner só pode CONCEDER permissões que ele mesmo tem. A
-- checagem é sobre o DELTA (o que está sendo ADICIONADO): p_permissoes é o estado
-- COMPLETO desejado, então uma permissão que o alvo JÁ tinha e continua tendo não
-- conta como concessão nova (senão um gestor sem 'relatorios' não conseguiria
-- mexer em nada de quem já tem 'relatorios'). 'equipe' segue governada só pela
-- trava por delta (só owner concede/revoga). Owner (inclui o master) concede tudo.
--
-- create or replace exige o corpo INTEIRO — o resto é idêntico à 0018.
-- Idempotente. Append-only: não edita a 0018.
-- =============================================================================
create or replace function public.admin_definir_permissoes(
  p_user_id     uuid,
  p_permissoes  text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid          uuid := auth.uid();
  v_alvo         public.profiles;
  v_lista        text[] := coalesce(p_permissoes, '{}');
  v_tinha_equipe boolean;
  v_tera_equipe  boolean;
begin
  if not public.tem_permissao('equipe') then
    raise exception 'sem permissão pra mexer na equipe';
  end if;

  if p_user_id = v_uid then
    raise exception 'não dá pra mudar as próprias permissões';
  end if;

  select * into v_alvo from public.profiles where id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'pessoa não encontrada');
  end if;

  if v_alvo.role = 'owner' or v_alvo.master then
    return jsonb_build_object('ok', false, 'erro', 'o adm do Casa já tem tudo — não há o que ajustar aqui');
  end if;

  -- A trava por delta: compara o que a pessoa TEM com o que vai ficar.
  v_tinha_equipe := exists (
    select 1 from public.staff_permissions
     where user_id = p_user_id and permissao = 'equipe'
  );
  v_tera_equipe := 'equipe' = any (v_lista);

  if v_tinha_equipe is distinct from v_tera_equipe and not public.is_owner() then
    return jsonb_build_object(
      'ok', false,
      'erro', 'só o adm do Casa mexe em quem cuida da equipe'
    );
  end if;

  -- MENOR PRIVILÉGIO: quem não é owner só CONCEDE o que ele mesmo tem. Barra se
  -- alguma permissão da lista (a) não é 'equipe' (já tratada acima), (b) o alvo
  -- ainda NÃO tinha (é concessão nova) e (c) o ATOR não possui. Assim, adicionar
  -- 'usuarios'/'relatorios'/etc que o gestor não tem é recusado; manter o que o
  -- alvo já tinha, ou revogar, segue passando.
  if not public.is_owner() then
    if exists (
      select 1
        from unnest(v_lista) as perm
       where perm <> 'equipe'
         and not exists (
               select 1 from public.staff_permissions
                where user_id = p_user_id and permissao = perm)
         and not exists (
               select 1 from public.staff_permissions
                where user_id = v_uid and permissao = perm)
    ) then
      return jsonb_build_object(
        'ok', false,
        'erro', 'tu só pode dar acessos que tu mesmo tem'
      );
    end if;
  end if;

  delete from public.staff_permissions
   where user_id = p_user_id
     and not (permissao = any (v_lista));

  insert into public.staff_permissions (user_id, permissao, granted_by)
  select p_user_id, perm, v_uid from unnest(v_lista) as perm
  on conflict (user_id, permissao) do nothing;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'permissoes_definidas', 'staff_permissions', p_user_id::text,
          jsonb_build_object('permissoes', to_jsonb(v_lista)));

  return jsonb_build_object('ok', true, 'permissoes', to_jsonb(v_lista));
end;
$$;



-- ===== 0019_presentes.sql =====

-- =============================================================================
-- 0019_presentes.sql — "Presentear um plano" 🎁
--
-- Deixa uma pessoa PAGAR uma assinatura de presente pra outra. O comprador paga
-- UM mês cheio do tier (cobrança avulsa, DETACHED — Pix ou cartão), escreve um
-- bilhete, e recebe um CÓDIGO. Quem ganha resgata o código na conta e ganha o
-- benefício do plano por 30 dias — SEM cartão, SEM recorrência: é presente, não
-- vira cobrança-surpresa quando o mês acaba.
--
-- MODELAGEM (por que estas escolhas):
--   • gift_subscriptions guarda o presente (comprador, tier, bilhete, código,
--     status, quem resgatou). Idempotência do webhook por asaas_checkout_id.
--   • Ao RESGATAR, criamos uma linha em `subscriptions` como status='pausada' com
--     current_period_end = agora + 30 dias. Por quê 'pausada' e não 'ativa'?
--     getEffectiveSubscription (_shared/lib.ts) concede benefício pra 'pausada'
--     SÓ enquanto current_period_end está no futuro — então o presente EXPIRA
--     sozinho em 30 dias, sem cron e sem o risco do "'ativa' concede pra sempre"
--     (uma 'ativa' sem renovação daria plano de graça eterno — ver auditoria do
--     asaas-webhook). O presente não tem assinatura no Asaas pra gerar
--     PAYMENT_OVERDUE, então a auto-expiração pelo período é o mecanismo certo.
--   • subscriptions.presente_id marca essa linha como originada de presente:
--     é o que faz o perfil e o resume-subscription NÃO a tratarem como assinatura
--     paga (não tem asaas_subscription_id pra "retomar"/"cancelar" no gateway).
--
-- SEGURANÇA (ver CLAUDE.md › Segurança):
--   • RLS deny-by-default. O comprador lê os presentes que deu; quem resgatou lê
--     o que ganhou. NENHUMA escrita pelo client — só via Edge Function
--     (service_role) e pelas RPCs SECURITY DEFINER abaixo.
--   • A resolução por CÓDIGO (resgate) roda só na RPC (revogada de anon/
--     authenticated): o client nunca varre a tabela por código.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Marcador na subscriptions: linha de assinatura que nasceu de um presente.
-- Nullable; o FK aponta pro presente que a originou (auditoria).
-- -----------------------------------------------------------------------------
alter table public.subscriptions
  add column if not exists presente_id uuid;

-- -----------------------------------------------------------------------------
-- Tabela dos presentes.
-- -----------------------------------------------------------------------------
create table if not exists public.gift_subscriptions (
  id                  uuid primary key default gen_random_uuid(),
  -- Nullable de propósito: se o comprador apagar a conta, o presente que ele deu
  -- NÃO some (quem ganhou ainda precisa poder resgatar) — o vínculo vira null via
  -- ON DELETE SET NULL. Por isso não pode ser NOT NULL (senão o delete da conta
  -- travaria). O comprador é gravado server-side no checkout (auth.uid()).
  comprador_id        uuid references public.profiles (id) on delete set null,
  tier_slug           text not null references public.tiers (slug),
  valor_centavos      integer not null check (valor_centavos > 0),
  mensagem            text,                         -- o bilhete (opcional, limitado no app)
  status              text not null default 'pendente'
                      check (status in ('pendente', 'pago', 'resgatado', 'cancelado')),
  codigo              text unique,                  -- gerado quando o presente é PAGO
  asaas_checkout_id   text unique,                  -- idempotência do checkout
  asaas_payment_id    text,                         -- pagamento que confirmou
  resgatado_por       uuid references public.profiles (id) on delete set null,
  resgatado_em        timestamptz,
  subscription_id     uuid references public.subscriptions (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- Agora que a tabela existe, amarra o FK do marcador (idempotente).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'subscriptions_presente_id_fkey'
  ) then
    alter table public.subscriptions
      add constraint subscriptions_presente_id_fkey
      foreign key (presente_id) references public.gift_subscriptions (id) on delete set null;
  end if;
end $$;

create index if not exists idx_gift_comprador   on public.gift_subscriptions (comprador_id);
create index if not exists idx_gift_resgatado   on public.gift_subscriptions (resgatado_por);
create index if not exists idx_gift_status      on public.gift_subscriptions (status);

-- -----------------------------------------------------------------------------
-- RLS: deny-by-default. Leitura só do comprador e de quem resgatou. Sem escrita
-- pelo client (service_role ignora RLS; as RPCs abaixo são SECURITY DEFINER).
-- -----------------------------------------------------------------------------
alter table public.gift_subscriptions enable row level security;

drop policy if exists gift_select_own on public.gift_subscriptions;
create policy gift_select_own on public.gift_subscriptions
  for select to authenticated
  using (comprador_id = auth.uid() or resgatado_por = auth.uid());

-- -----------------------------------------------------------------------------
-- marcar_presente_pago(gift_id, payment_id) → codigo
-- Chamada pelo asaas-webhook no CHECKOUT_PAID do presente. Idempotente: se já
-- está 'pago'/'resgatado', devolve o código existente sem regerar. Gera um código
-- legível e único (CASA-XXXXXX, 6 hex maiúsculos), com retry anti-colisão.
-- SECURITY DEFINER; só service_role chama.
-- -----------------------------------------------------------------------------
create or replace function public.marcar_presente_pago(p_gift_id uuid, p_payment_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gift    public.gift_subscriptions;
  v_codigo  text;
begin
  select * into v_gift from public.gift_subscriptions where id = p_gift_id for update;
  if not found then
    return null; -- presente inexistente (checkout externo/forjado) → nada a fazer
  end if;

  -- Já processado: devolve o código que já existe (idempotência do reenvio).
  if v_gift.status in ('pago', 'resgatado') then
    return v_gift.codigo;
  end if;
  -- Só um 'pendente' vira 'pago'. 'cancelado' não ressuscita.
  if v_gift.status <> 'pendente' then
    return v_gift.codigo;
  end if;

  -- Código único legível: CASA-XXXXXX. Retenta se colidir.
  loop
    v_codigo := 'CASA-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.gift_subscriptions where codigo = v_codigo);
  end loop;

  update public.gift_subscriptions
     set status = 'pago',
         codigo = v_codigo,
         asaas_payment_id = coalesce(p_payment_id, asaas_payment_id),
         updated_at = now()
   where id = p_gift_id;

  return v_codigo;
end;
$$;

revoke all on function public.marcar_presente_pago(uuid, text) from public;
grant execute on function public.marcar_presente_pago(uuid, text) to service_role;

-- -----------------------------------------------------------------------------
-- resgatar_presente(user_id, codigo) → jsonb
-- Resgate ATÔMICO (lock na linha do presente): valida código/estado, garante que
-- quem resgata não tem plano vigente (pra não empilhar benefício/desperdiçar o
-- presente), cria a assinatura 'pausada' (+30 dias) marcada como presente, espelha
-- o tier no profiles e fecha o presente. SECURITY DEFINER; só service_role chama.
--
-- Retorna { ok:true, tier, tier_nome, ativo_ate } ou { ok:false, erro }.
-- -----------------------------------------------------------------------------
create or replace function public.resgatar_presente(p_user_id uuid, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gift      public.gift_subscriptions;
  v_codigo    text := upper(trim(coalesce(p_codigo, '')));
  v_tier      public.tiers;
  v_sub_id    uuid;
  v_ativo_ate timestamptz := now() + interval '30 days';
begin
  if v_codigo = '' then
    return jsonb_build_object('ok', false, 'erro', 'digita o código do presente 💛');
  end if;

  -- Lock pessimista na linha do presente: serializa resgates concorrentes do mesmo
  -- código (dois cliques / duas abas não resgatam duas vezes).
  select * into v_gift from public.gift_subscriptions where codigo = v_codigo for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'não achei esse presente. confere o código?');
  end if;
  if v_gift.status = 'resgatado' then
    return jsonb_build_object('ok', false, 'erro', 'esse presente já foi resgatado 💛');
  end if;
  if v_gift.status <> 'pago' then
    return jsonb_build_object('ok', false, 'erro', 'esse presente ainda não tá disponível pra resgate');
  end if;

  -- Já tem plano vigente? Não empilha (o presente ficaria "desperdiçado" por baixo
  -- de uma 'ativa', que sempre ganha). Deixa o presente guardado pra quando o plano
  -- atual acabar. Mesma regra de "concede benefício" do getEffectiveSubscription.
  if exists (
    select 1 from public.subscriptions
     where user_id = p_user_id
       and status in ('ativa', 'pausada')
       and (status = 'ativa' or (current_period_end is not null and current_period_end > now()))
  ) then
    return jsonb_build_object(
      'ok', false,
      'erro', 'tu já tem um plano rolando por aqui 💛 esse presente fica guardadinho — resgata quando ele acabar.',
      'guardado', true);
  end if;

  select * into v_tier from public.tiers where slug = v_gift.tier_slug;
  if not found or not coalesce(v_tier.ativo, false) then
    return jsonb_build_object('ok', false, 'erro', 'o plano desse presente não tá disponível agora');
  end if;

  -- Cria a assinatura 'pausada' (+30 dias), marcada como presente. Sem asaas_* —
  -- não é recorrência no gateway. Expira sozinha quando o período vence.
  insert into public.subscriptions (user_id, tier_slug, status, current_period_end, presente_id)
  values (p_user_id, v_gift.tier_slug, 'pausada', v_ativo_ate, v_gift.id)
  returning id into v_sub_id;

  -- Espelha o tier no profiles (cache). A GUC libera o prevent_points_tamper pra
  -- este write server-side (mesmo padrão do update_points_balance / 0008).
  perform set_config('casa.trusted_points', 'on', true);
  update public.profiles set tier_slug = v_gift.tier_slug where id = p_user_id;

  -- Fecha o presente.
  update public.gift_subscriptions
     set status = 'resgatado',
         resgatado_por = p_user_id,
         resgatado_em = now(),
         subscription_id = v_sub_id,
         updated_at = now()
   where id = v_gift.id;

  return jsonb_build_object(
    'ok', true,
    'tier', v_gift.tier_slug,
    'tier_nome', v_tier.nome,
    'ativo_ate', v_ativo_ate);
end;
$$;

revoke all on function public.resgatar_presente(uuid, text) from public;
grant execute on function public.resgatar_presente(uuid, text) to service_role;



-- ===== 0020_mural.sql =====

-- =============================================================================
-- 0020_mural.sql — "Mural do Casa" 📌
--
-- Um mural leve no /o-casa onde quem é do Casa (assinante) deixa um recado curto
-- que aparece como post-it na parede. Perk exclusivo de assinante, puro afeto.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Leitura PÚBLICA dos recados 'aprovado' (o /o-casa é página aberta) — anon lê
--     o mural. O autor vê também os próprios 'oculto'; staff vê tudo.
--   • ESCRITA só via Edge Function (`postar-mural`, service_role): deny-by-default
--     pro client. A function é quem valida "é assinante vigente?" server-side
--     (mesma regra dos pontos: fidelidade é exclusiva de assinante) — não dá pra
--     confiar no client pra isso, e uma policy de RLS não consegue reproduzir o
--     gating de período de forma barata. O nome do autor é um SNAPSHOT gravado
--     pela function (primeiro nome), então o mural NÃO precisa ler `profiles` de
--     terceiros (nada de vazar dado de outra pessoa).
--   • O autor pode APAGAR o próprio recado; staff modera (ocultar/apagar qualquer).
--   • `texto` é sempre injetado no DOM via textContent/escape no client — sem XSS.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE ... / DROP POLICY IF EXISTS).
-- =============================================================================

create table if not exists public.mural_notes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  autor_nome  text,                          -- snapshot do primeiro nome (gravado server-side)
  texto       text not null check (char_length(btrim(texto)) between 1 and 240),
  status      text not null default 'aprovado' check (status in ('aprovado', 'oculto')),
  created_at  timestamptz not null default now()
);

create index if not exists idx_mural_publico on public.mural_notes (status, created_at desc);
create index if not exists idx_mural_autor   on public.mural_notes (user_id, created_at desc);

-- -----------------------------------------------------------------------------
-- RLS: leitura pública dos aprovados (+ próprios + staff vê tudo). Escrita só
-- via Edge Function (service_role). Autor apaga o próprio; staff modera.
-- -----------------------------------------------------------------------------
alter table public.mural_notes enable row level security;

drop policy if exists mural_select_public on public.mural_notes;
create policy mural_select_public on public.mural_notes
  for select to anon, authenticated
  using (status = 'aprovado' or user_id = auth.uid() or public.is_staff());

-- Autor apaga o próprio recado; staff apaga qualquer um. (Sem INSERT/UPDATE pro
-- client: quem escreve é a function via service_role; quem oculta é o staff.)
drop policy if exists mural_delete_own_or_staff on public.mural_notes;
create policy mural_delete_own_or_staff on public.mural_notes
  for delete to authenticated
  using (user_id = auth.uid() or public.is_staff());

-- Moderação: staff altera status (ex.: ocultar).
drop policy if exists mural_update_staff on public.mural_notes;
create policy mural_update_staff on public.mural_notes
  for update to authenticated
  using (public.is_staff())
  with check (public.is_staff());



-- ===== 0021_indicacoes.sql =====

-- =============================================================================
-- 0021_indicacoes.sql — "Indica um amigo" 🤝
--
-- Cada usuário ganha um CÓDIGO de indicação. Quem é trazido cria conta com o
-- código, assina, e quando o PRIMEIRO PAGAMENTO confirma os DOIS ganham pontos.
--
-- POR QUE A RECOMPENSA CAI NO PAGAMENTO, NÃO NO CADASTRO:
--   Premiar no cadastro convidaria fraude (contas fantasma). Amarrando ao
--   primeiro pagamento CONFIRMADO de uma assinatura real (via asaas-webhook),
--   indicar só compensa quando entra gente de verdade pagando.
--
-- SEGURANÇA (ver CLAUDE.md › Segurança):
--   • RLS deny-by-default. Cada um lê só as indicações que fez / que recebeu.
--   • Registro do vínculo: RPC registrar_indicacao (SECURITY DEFINER) usa
--     auth.uid() como INDICADO — o client nunca diz "sou fulano". Barra
--     auto-indicação, conta que já é da casa (tem assinatura) e duplo-vínculo.
--   • Premiação: RPC premiar_indicacao (SECURITY DEFINER), chamada SÓ pelo
--     asaas-webhook (service_role) no pagamento. Idempotente (pendente→premiado).
--     Os pontos entram pelo points_ledger (append-only), nunca pelo client.
--
-- VALORES DOS PONTOS: são FICTÍCIOS e vivem nas constantes do asaas-webhook
-- (REFERRAL_PTS_INDICADOR / REFERRAL_PTS_INDICADO) — passados pra premiar_indicacao.
-- A migration não fixa valor: quem decide quanto é o webhook. Ajustar lá depois.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

-- Código de indicação do usuário (gerado sob demanda pela RPC abaixo).
alter table public.profiles
  add column if not exists referral_code text unique;

-- -----------------------------------------------------------------------------
-- Vínculo de indicação. Um indicado só pode ser indicado UMA vez (UNIQUE).
-- -----------------------------------------------------------------------------
create table if not exists public.referrals (
  id            uuid primary key default gen_random_uuid(),
  referrer_id   uuid references public.profiles (id) on delete set null, -- quem indicou
  referred_id   uuid not null references public.profiles (id) on delete cascade, -- quem foi indicado
  codigo        text,                             -- snapshot do código usado
  status        text not null default 'pendente'
                check (status in ('pendente', 'premiado', 'invalido')),
  premiado_em   timestamptz,
  created_at    timestamptz not null default now(),
  unique (referred_id)                            -- cada conta é indicada no máx. 1 vez
);

create index if not exists idx_referrals_referrer on public.referrals (referrer_id, status);

-- -----------------------------------------------------------------------------
-- RLS: cada um lê só o que fez/recebeu. Sem escrita pelo client (as RPCs
-- SECURITY DEFINER e o webhook/service_role é que escrevem).
-- -----------------------------------------------------------------------------
alter table public.referrals enable row level security;

drop policy if exists referrals_select_own on public.referrals;
create policy referrals_select_own on public.referrals
  for select to authenticated
  using (referrer_id = auth.uid() or referred_id = auth.uid());

-- -----------------------------------------------------------------------------
-- meu_codigo_indicacao() → text
-- Retorna o código do PRÓPRIO usuário (auth.uid()), gerando um único na primeira
-- vez (CASA6, 6 hex maiúsculos, com retry anti-colisão). SECURITY DEFINER.
-- -----------------------------------------------------------------------------
create or replace function public.meu_codigo_indicacao()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_codigo text;
begin
  if v_uid is null then
    raise exception 'não autenticado';
  end if;

  select referral_code into v_codigo from public.profiles where id = v_uid;
  if v_codigo is not null then
    return v_codigo;
  end if;

  loop
    v_codigo := upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.profiles where referral_code = v_codigo);
  end loop;

  update public.profiles set referral_code = v_codigo where id = v_uid;
  return v_codigo;
end;
$$;

revoke all on function public.meu_codigo_indicacao() from public;
grant execute on function public.meu_codigo_indicacao() to authenticated;

-- -----------------------------------------------------------------------------
-- registrar_indicacao(codigo) → jsonb
-- Registra que o usuário ATUAL (auth.uid()) foi indicado por quem tem esse código.
-- Barra: código inválido, auto-indicação, quem já foi indicado, e quem já é da
-- casa (tem qualquer assinatura). Cria o vínculo 'pendente'. SECURITY DEFINER.
-- -----------------------------------------------------------------------------
create or replace function public.registrar_indicacao(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_referred uuid := auth.uid();
  v_codigo   text := upper(btrim(coalesce(p_codigo, '')));
  v_referrer uuid;
begin
  if v_referred is null then
    return jsonb_build_object('ok', false, 'erro', 'não autenticado');
  end if;
  if v_codigo = '' then
    return jsonb_build_object('ok', false, 'erro', 'código vazio');
  end if;

  select id into v_referrer from public.profiles where referral_code = v_codigo;
  if v_referrer is null then
    return jsonb_build_object('ok', false, 'erro', 'código de indicação inválido');
  end if;
  if v_referrer = v_referred then
    return jsonb_build_object('ok', false, 'erro', 'não dá pra indicar a si mesmo 💛');
  end if;

  -- Já foi indicado antes? (UNIQUE garante, mas respondemos gentil.)
  if exists (select 1 from public.referrals where referred_id = v_referred) then
    return jsonb_build_object('ok', false, 'erro', 'você já entrou por uma indicação', 'ja', true);
  end if;

  -- Já é da casa (tem/teve assinatura)? Então não é "conta nova indicada".
  if exists (select 1 from public.subscriptions where user_id = v_referred) then
    return jsonb_build_object('ok', false, 'erro', 'essa conta já é da casa', 'ja', true);
  end if;

  insert into public.referrals (referrer_id, referred_id, codigo, status)
  values (v_referrer, v_referred, v_codigo, 'pendente');

  return jsonb_build_object('ok', true);
exception
  when unique_violation then
    -- corrida: outra chamada registrou primeiro. Trata como "já indicado".
    return jsonb_build_object('ok', false, 'erro', 'você já entrou por uma indicação', 'ja', true);
end;
$$;

revoke all on function public.registrar_indicacao(text) from public;
grant execute on function public.registrar_indicacao(text) to authenticated;

-- -----------------------------------------------------------------------------
-- premiar_indicacao(referred_id, pontos_indicador, pontos_indicado) → jsonb
-- Chamada pelo asaas-webhook (service_role) quando o PAGAMENTO do indicado
-- confirma. Trava o vínculo 'pendente' do indicado, credita os DOIS lados no
-- ledger e marca 'premiado'. Idempotente (só processa 'pendente'). Os pontos
-- entram como lançamentos fixos (ref_type 'indicacao'/'indicacao_bonus',
-- ref_id = referral.id) — NÃO passam pelo multiplicador de tier.
-- -----------------------------------------------------------------------------
create or replace function public.premiar_indicacao(
  p_referred_id uuid,
  p_pontos_indicador integer,
  p_pontos_indicado integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref public.referrals;
begin
  select * into v_ref
    from public.referrals
   where referred_id = p_referred_id and status = 'pendente'
   for update;
  if not found then
    return jsonb_build_object('rewarded', false); -- sem vínculo pendente → nada a fazer
  end if;

  -- Indicador sumiu (conta apagada) → invalida, sem premiar.
  if v_ref.referrer_id is null then
    update public.referrals set status = 'invalido' where id = v_ref.id;
    return jsonb_build_object('rewarded', false, 'motivo', 'indicador inexistente');
  end if;

  -- Credita os dois (append-only; o trigger sincroniza o cache de saldo).
  -- ref_type distinto por lado → o UNIQUE (ref_type, ref_id) deixa os dois coexistirem.
  if coalesce(p_pontos_indicador, 0) > 0 then
    insert into public.points_ledger (user_id, delta, motivo, descricao, ref_type, ref_id)
    values (v_ref.referrer_id, p_pontos_indicador, 'indicou um amigo', 'indicou um amigo',
            'indicacao', v_ref.id::text)
    on conflict (ref_type, ref_id) where ref_type is not null do nothing;
  end if;
  if coalesce(p_pontos_indicado, 0) > 0 then
    insert into public.points_ledger (user_id, delta, motivo, descricao, ref_type, ref_id)
    values (v_ref.referred_id, p_pontos_indicado, 'veio pela indicação de um amigo',
            'veio pela indicação de um amigo', 'indicacao_bonus', v_ref.id::text)
    on conflict (ref_type, ref_id) where ref_type is not null do nothing;
  end if;

  update public.referrals
     set status = 'premiado', premiado_em = now()
   where id = v_ref.id;

  return jsonb_build_object('rewarded', true, 'referrer', v_ref.referrer_id, 'referred', v_ref.referred_id);
end;
$$;

revoke all on function public.premiar_indicacao(uuid, integer, integer) from public;
grant execute on function public.premiar_indicacao(uuid, integer, integer) to service_role;



-- ===== 0022_avisos.sql =====

-- =============================================================================
-- 0022_avisos.sql — "Recado da casa" 📣
--
-- Uma tarjinha fina e opcional no topo do site onde o Casa acende um recado curto
-- e datado: "hoje tem fornada de brioche a partir das 15h 🥐", "a gente fecha 17h
-- nesse sábado". Some sozinha quando a janela expira; a pessoa pode fechar e ela
-- não volta a incomodar (o front lembra pelo id). É o jeito mais barato de deixar
-- o site "vivo" no dia a dia, sem depender de rede social.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Leitura PÚBLICA (anon) SÓ do recado vigente — a policy filtra ativo + janela
--     (inicio/fim) com now(). O front nunca vê rascunho nem recado agendado/expirado.
--   • ESCRITA só via RPC SECURITY DEFINER gated por is_owner() (mesmo padrão de RPC
--     do console; nada de INSERT/UPDATE/DELETE pelo client — deny-by-default). Recado
--     é conteúdo público: fica owner-only de propósito (o whitelist de permissões do
--     console é fechado por CHECK; abrir uma permissão 'avisos' granular pediria mexer
--     naquele CHECK — deixado pra depois se quiserem delegar).
--   • `texto`/`link` são sempre escapados no client antes do DOM (JS vanilla, sem XSS).
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

create table if not exists public.avisos_casa (
  id          uuid primary key default gen_random_uuid(),
  texto       text not null check (char_length(btrim(texto)) between 1 and 160),
  emoji       text check (emoji is null or char_length(emoji) <= 8),
  link_url    text check (link_url is null or char_length(link_url) <= 300),
  link_label  text check (link_label is null or char_length(link_label) <= 40),
  inicio_em   timestamptz,                    -- null = já vale agora
  fim_em      timestamptz,                    -- null = sem prazo (até desligar/remover)
  prioridade  integer not null default 0,     -- maior aparece primeiro se houver vários
  ativo       boolean not null default true,  -- liga/desliga manual (sem apagar)
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists idx_avisos_vigentes on public.avisos_casa (ativo, prioridade desc, created_at desc);

-- -----------------------------------------------------------------------------
-- RLS: leitura pública SÓ do recado vigente (ativo + dentro da janela). Owner vê
-- tudo (pra o console listar rascunhos/agendados/expirados). Escrita: nenhuma
-- policy → só as RPCs SECURITY DEFINER abaixo escrevem.
-- -----------------------------------------------------------------------------
alter table public.avisos_casa enable row level security;

drop policy if exists avisos_select_publico on public.avisos_casa;
create policy avisos_select_publico on public.avisos_casa
  for select to anon, authenticated
  using (
    (ativo
      and (inicio_em is null or inicio_em <= now())
      and (fim_em is null or fim_em >= now()))
    or public.is_owner()
  );

-- -----------------------------------------------------------------------------
-- admin_avisos_listar() → setof avisos_casa
-- TODOS os recados (inclusive desligados/expirados), pro console. Owner-only.
-- -----------------------------------------------------------------------------
create or replace function public.admin_avisos_listar()
returns setof public.avisos_casa
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_owner() then
    raise exception 'sem permissão';
  end if;
  return query
    select * from public.avisos_casa
    order by ativo desc, prioridade desc, created_at desc;
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_aviso_salvar(...) → avisos_casa
-- Cria (p_id null) ou edita (p_id existente) um recado. Owner-only. Normaliza
-- strings vazias pra null. Devolve a linha final.
-- -----------------------------------------------------------------------------
create or replace function public.admin_aviso_salvar(
  p_id         uuid,
  p_texto      text,
  p_emoji      text,
  p_link_url   text,
  p_link_label text,
  p_inicio     timestamptz,
  p_fim        timestamptz,
  p_prioridade integer,
  p_ativo      boolean
)
returns public.avisos_casa
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_texto text := btrim(coalesce(p_texto, ''));
  v_row   public.avisos_casa;
begin
  if not public.is_owner() then
    raise exception 'sem permissão';
  end if;
  if char_length(v_texto) < 1 then
    raise exception 'o recado não pode ser vazio';
  end if;

  if p_id is null then
    insert into public.avisos_casa
      (texto, emoji, link_url, link_label, inicio_em, fim_em, prioridade, ativo, created_by)
    values
      (v_texto, nullif(btrim(coalesce(p_emoji, '')), ''),
       nullif(btrim(coalesce(p_link_url, '')), ''),
       nullif(btrim(coalesce(p_link_label, '')), ''),
       p_inicio, p_fim, coalesce(p_prioridade, 0), coalesce(p_ativo, true), v_uid)
    returning * into v_row;
  else
    update public.avisos_casa set
      texto      = v_texto,
      emoji      = nullif(btrim(coalesce(p_emoji, '')), ''),
      link_url   = nullif(btrim(coalesce(p_link_url, '')), ''),
      link_label = nullif(btrim(coalesce(p_link_label, '')), ''),
      inicio_em  = p_inicio,
      fim_em     = p_fim,
      prioridade = coalesce(p_prioridade, 0),
      ativo      = coalesce(p_ativo, true),
      updated_at = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'recado não encontrado';
    end if;
  end if;

  return v_row;
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_aviso_remover(id) → boolean. Owner-only.
-- -----------------------------------------------------------------------------
create or replace function public.admin_aviso_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_owner() then
    raise exception 'sem permissão';
  end if;
  delete from public.avisos_casa where id = p_id;
  return true;
end;
$$;

revoke all on function public.admin_avisos_listar()                                              from public, anon;
revoke all on function public.admin_aviso_salvar(uuid, text, text, text, text, timestamptz, timestamptz, integer, boolean) from public, anon;
revoke all on function public.admin_aviso_remover(uuid)                                          from public, anon;
grant execute on function public.admin_avisos_listar()                                            to authenticated;
grant execute on function public.admin_aviso_salvar(uuid, text, text, text, text, timestamptz, timestamptz, integer, boolean)  to authenticated;
grant execute on function public.admin_aviso_remover(uuid)                                        to authenticated;



-- ===== 0023_trilha.sql =====

-- =============================================================================
-- 0023_trilha.sql — "A trilha do Casa" 🎧
--
-- As playlists reais do Casa (embed do Spotify), curadas por clima ("manhã lenta",
-- "tarde de trabalho", "fim de tarde"). Uma delas pode ser marcada como TOCANDO
-- AGORA — aparece em destaque na home com um selinho pulsante, o site respirando
-- junto com o balcão. Tudo editável pelo owner no console (nada de hardcode de URL).
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Leitura PÚBLICA só das playlists ativas (o front é aberto). Owner vê tudo.
--   • ESCRITA só via RPC SECURITY DEFINER gated por is_owner() (mesmo padrão do
--     0022_avisos; nada de INSERT/UPDATE/DELETE pelo client — deny-by-default).
--   • `spotify_url` é validado/convertido pra embed NO CLIENT antes de virar
--     src de <iframe> (só aceita open.spotify.com) — o banco guarda o texto cru.
--   • Só UMA playlist "tocando" por vez: a RPC de salvar zera as outras.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

create table if not exists public.playlists_casa (
  id           uuid primary key default gen_random_uuid(),
  nome         text not null check (char_length(btrim(nome)) between 1 and 80),
  clima        text check (clima is null or char_length(clima) <= 40),  -- eyebrow: "pra focar"
  spotify_url  text not null check (char_length(btrim(spotify_url)) between 1 and 400),
  ordem        integer not null default 0,      -- menor primeiro
  ativo        boolean not null default true,   -- aparece na home
  tocando      boolean not null default false,  -- "tá tocando agora" (só uma por vez)
  created_by   uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists idx_playlists_home on public.playlists_casa (ativo, ordem, created_at);
-- Garante no máximo UMA "tocando" ao mesmo tempo (defesa no banco além da RPC).
create unique index if not exists uidx_playlist_tocando on public.playlists_casa (tocando) where tocando;

-- -----------------------------------------------------------------------------
-- RLS: leitura pública das ativas (+ owner vê tudo). Escrita só pelas RPCs.
-- -----------------------------------------------------------------------------
alter table public.playlists_casa enable row level security;

drop policy if exists playlists_select_publico on public.playlists_casa;
create policy playlists_select_publico on public.playlists_casa
  for select to anon, authenticated
  using (ativo or public.is_owner());

-- -----------------------------------------------------------------------------
-- admin_trilha_listar() → setof playlists_casa (TODAS, pro console). Owner-only.
-- -----------------------------------------------------------------------------
create or replace function public.admin_trilha_listar()
returns setof public.playlists_casa
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_owner() then
    raise exception 'sem permissão';
  end if;
  return query
    select * from public.playlists_casa
    order by ativo desc, ordem asc, created_at asc;
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_trilha_salvar(...) → playlists_casa. Cria (p_id null) ou edita. Owner-only.
-- Se p_tocando = true, zera o "tocando" das outras (só uma toca por vez).
-- -----------------------------------------------------------------------------
create or replace function public.admin_trilha_salvar(
  p_id       uuid,
  p_nome     text,
  p_clima    text,
  p_url      text,
  p_ordem    integer,
  p_ativo    boolean,
  p_tocando  boolean
)
returns public.playlists_casa
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_url  text := btrim(coalesce(p_url, ''));
  v_toca boolean := coalesce(p_tocando, false);
  v_row  public.playlists_casa;
begin
  if not public.is_owner() then
    raise exception 'sem permissão';
  end if;
  if char_length(v_nome) < 1 then
    raise exception 'dá um nome pra playlist';
  end if;
  if char_length(v_url) < 1 then
    raise exception 'cola o link do Spotify';
  end if;

  -- Só uma toca por vez: zera as outras antes (o unique index reforça).
  if v_toca then
    update public.playlists_casa set tocando = false
     where tocando = true and (p_id is null or id <> p_id);
  end if;

  if p_id is null then
    insert into public.playlists_casa (nome, clima, spotify_url, ordem, ativo, tocando, created_by)
    values (v_nome, nullif(btrim(coalesce(p_clima, '')), ''), v_url,
            coalesce(p_ordem, 0), coalesce(p_ativo, true), v_toca, v_uid)
    returning * into v_row;
  else
    update public.playlists_casa set
      nome        = v_nome,
      clima       = nullif(btrim(coalesce(p_clima, '')), ''),
      spotify_url = v_url,
      ordem       = coalesce(p_ordem, 0),
      ativo       = coalesce(p_ativo, true),
      tocando     = v_toca,
      updated_at  = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'playlist não encontrada';
    end if;
  end if;

  return v_row;
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_trilha_remover(id) → boolean. Owner-only.
-- -----------------------------------------------------------------------------
create or replace function public.admin_trilha_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_owner() then
    raise exception 'sem permissão';
  end if;
  delete from public.playlists_casa where id = p_id;
  return true;
end;
$$;

revoke all on function public.admin_trilha_listar()                                        from public, anon;
revoke all on function public.admin_trilha_salvar(uuid, text, text, text, integer, boolean, boolean) from public, anon;
revoke all on function public.admin_trilha_remover(uuid)                                   from public, anon;
grant execute on function public.admin_trilha_listar()                                      to authenticated;
grant execute on function public.admin_trilha_salvar(uuid, text, text, text, integer, boolean, boolean) to authenticated;
grant execute on function public.admin_trilha_remover(uuid)                                 to authenticated;



-- ===== 0024_perfil_publico.sql =====

-- =============================================================================
-- 0024_perfil_publico.sql — "Meu cantinho" 🏡
--
-- Um cartãozinho público e OPCIONAL do assinante em /gente/{handle}: só o essencial
-- e gentil — apelido, "meu café de sempre", o plano, há quanto tempo é da casa, a
-- foto e os recados que deixou no Mural. Dá rosto à comunidade SEM expor nada
-- sensível: e-mail, telefone, pontos, endereço e nome real ficam DE FORA.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Opt-in explícito: `profiles.perfil_publico` (default false). Ninguém aparece
--     sem ligar. O `handle` (slug único da URL) é gerado ao ligar e fica estável.
--   • A exposição pública NÃO é RLS na `profiles` (arriscado — abriria a linha
--     inteira). É uma RPC `perfil_publico(handle)` SECURITY DEFINER que devolve um
--     jsonb com EXATAMENTE os campos seguros (hand-picked), só pra quem optou.
--     e-mail/telefone/pontos/endereço nunca entram no payload.
--   • Ligar/desligar: RPC `definir_perfil_publico(ativar)` usa auth.uid() (o client
--     nunca diz de quem é) e exige ser assinante (perk de assinante, como o Mural).
--   • Os recados vêm do Mural (já público os 'aprovado'); o payload injeta os do dono.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (add column if not exists / CREATE OR REPLACE).
-- =============================================================================

alter table public.profiles add column if not exists perfil_publico boolean not null default false;
alter table public.profiles add column if not exists handle text unique;

-- -----------------------------------------------------------------------------
-- definir_perfil_publico(ativar) → jsonb {ok, ativo, handle} | {ok:false, erro}
-- O dono (auth.uid) liga/desliga o próprio cantinho. Ao ligar, garante um handle
-- único e estável (slug do apelido/nome). Exige assinatura vigente (tier_slug).
-- -----------------------------------------------------------------------------
create or replace function public.definir_perfil_publico(p_ativar boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_prof   public.profiles;
  v_base   text;
  v_handle text;
  v_i      integer := 1;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'não autenticado');
  end if;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'perfil não encontrado');
  end if;

  -- Desligar é sempre permitido; guarda o handle pra reativar na mesma URL.
  if not coalesce(p_ativar, false) then
    update public.profiles set perfil_publico = false where id = v_uid;
    return jsonb_build_object('ok', true, 'ativo', false, 'handle', v_prof.handle);
  end if;

  -- Ligar é perk de assinante (mesma régua do Mural/pontos): precisa de plano vigente.
  if v_prof.tier_slug is null then
    return jsonb_build_object('ok', false, 'erro', 'o teu cantinho é um mimo de quem tem plano 💛', 'precisa_assinar', true);
  end if;

  v_handle := v_prof.handle;
  if v_handle is null then
    -- slug base: apelido → nome → 'amigo'. Tira acento comum, deixa a-z0-9 e hífen.
    v_base := lower(coalesce(nullif(btrim(v_prof.apelido), ''), nullif(btrim(v_prof.full_name), ''), 'amigo'));
    v_base := translate(v_base, 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn');
    v_base := btrim(regexp_replace(v_base, '[^a-z0-9]+', '-', 'g'), '-');
    if v_base = '' then v_base := 'amigo'; end if;
    v_handle := v_base;
    while exists (select 1 from public.profiles where handle = v_handle and id <> v_uid) loop
      v_i := v_i + 1;
      v_handle := v_base || '-' || v_i;
    end loop;
  end if;

  update public.profiles set perfil_publico = true, handle = v_handle where id = v_uid;
  return jsonb_build_object('ok', true, 'ativo', true, 'handle', v_handle);
end;
$$;

revoke all on function public.definir_perfil_publico(boolean) from public, anon;
grant execute on function public.definir_perfil_publico(boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- perfil_publico(handle) → jsonb (payload seguro) | null
-- Leitura PÚBLICA (anon) do cantinho de quem optou. SÓ campos seguros. Devolve
-- null se o handle não existe ou o perfil não é público.
-- -----------------------------------------------------------------------------
create or replace function public.perfil_publico(p_handle text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prof   public.profiles;
  v_tier   text;
  v_nome   text;
  v_recados jsonb;
begin
  select * into v_prof
    from public.profiles
   where lower(handle) = lower(btrim(coalesce(p_handle, ''))) and perfil_publico = true;
  if not found then
    return null;
  end if;

  select nome into v_tier from public.tiers where slug = v_prof.tier_slug;

  -- Nome de exibição: apelido, senão o PRIMEIRO nome (nunca o nome completo real).
  v_nome := nullif(btrim(v_prof.apelido), '');
  if v_nome is null then
    v_nome := split_part(btrim(coalesce(v_prof.full_name, '')), ' ', 1);
  end if;
  if v_nome is null or v_nome = '' then v_nome := 'alguém do Casa'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('texto', m.texto, 'created_at', m.created_at)
                            order by m.created_at desc), '[]'::jsonb)
    into v_recados
    from public.mural_notes m
   where m.user_id = v_prof.id and m.status = 'aprovado';

  return jsonb_build_object(
    'nome',         v_nome,
    'avatar_url',   v_prof.avatar_url,
    'tier_slug',    v_prof.tier_slug,
    'tier_nome',    v_tier,
    'membro_desde', v_prof.created_at,
    'cafe_metodo',  v_prof.cafe_metodo,
    'cafe_torra',   v_prof.cafe_torra,
    'cafe_leite',   v_prof.cafe_leite,
    'cafe_horario', v_prof.cafe_horario,
    'recados',      v_recados
  );
end;
$$;

revoke all on function public.perfil_publico(text) from public;
grant execute on function public.perfil_publico(text) to anon, authenticated;



-- ===== 0025_brinde_aniversario.sql =====

-- =============================================================================
-- 0025_brinde_aniversario.sql — "Hoje o Casa é teu" 🎂
--
-- A 0014 já guardava o aniversário (`profiles.nascimento`) e o comentário dela
-- prometia: "no dia tem café por nossa conta". Isto aqui cumpre a promessa — e
-- num tamanho maior: no MÊS do aniversário, quem é do Casa (assinante) reserva
-- um BRUNCH DE ANIVERSÁRIO (pra uma pessoa — o mesmo mimo que a casa já dá hoje).
-- A pessoa "resgata" no /conta/perfil, recebe um código, e mostra no balcão.
-- O staff confere e dá baixa no console. Uma vez por ano.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Perk de ASSINANTE, como o Mural e os pontos: só resgata quem tem plano
--     vigente (`tier_slug`). E só no MÊS do aniversário (janela generosa — dá pra
--     vir num dia de semana, sem correr).
--   • Um por ano: UNIQUE (user_id, ano). O `resgatar` recomputa TODAS as travas
--     no banco (mês, assinatura, duplicidade) — o front é conforto, não porteiro.
--   • ESCRITA só pelas RPCs SECURITY DEFINER. A tabela é deny-by-default pro
--     client: ele só LÊ o próprio brinde (e o staff com permissão 'resgates' lê
--     todos, porque é quem confere no balcão — é uma baixa de recompensa em mãos,
--     mesma régua dos `redemptions`).
--   • Baixa (marcar usado) exige `tem_permissao('resgates')` — sem permissão nova
--     no whitelist do 0017; honrar um brunch no balcão É cuidar de resgate.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

create table if not exists public.brindes_aniversario (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  ano         integer not null,                 -- ano do aniversário celebrado (1 por ano)
  codigo      text not null unique,             -- CASA-XXXXXX (mostra no balcão)
  valido_ate  date not null,                    -- último dia pra aproveitar
  status      text not null default 'ativo' check (status in ('ativo', 'usado')),
  usado_em    timestamptz,
  usado_por   uuid references public.profiles (id) on delete set null,
  criado_em   timestamptz not null default now(),
  unique (user_id, ano)
);

create index if not exists idx_brindes_status on public.brindes_aniversario (status, valido_ate);

-- -----------------------------------------------------------------------------
-- RLS: cada um lê o próprio brinde; o staff com 'resgates' lê todos (confere no
-- balcão). Escrita nenhuma pelo client — só pelas RPCs abaixo.
-- -----------------------------------------------------------------------------
alter table public.brindes_aniversario enable row level security;

drop policy if exists brindes_select_own on public.brindes_aniversario;
create policy brindes_select_own on public.brindes_aniversario
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('resgates'));

-- -----------------------------------------------------------------------------
-- meu_brinde_aniversario() → jsonb com o estado pra desenhar o card do perfil.
-- Não muda nada; só conta a situação (com o fuso de Novo Hamburgo, senão "o mês"
-- viraria à meia-noite UTC). Sem sessão → erro.
-- -----------------------------------------------------------------------------
create or replace function public.meu_brinde_aniversario()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_prof   public.profiles;
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ano    integer := extract(year from v_hoje)::int;
  v_brinde public.brindes_aniversario;
  v_eh_mes boolean := false;
  v_eh_dia boolean := false;
  v_sit    text := null;
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('tem_data', false, 'assinante', false);
  end if;

  if v_prof.nascimento is not null then
    v_eh_mes := extract(month from v_prof.nascimento) = extract(month from v_hoje);
    v_eh_dia := v_eh_mes and extract(day from v_prof.nascimento) = extract(day from v_hoje);
  end if;

  select * into v_brinde
    from public.brindes_aniversario
   where user_id = v_uid and ano = v_ano;

  if found then
    v_sit := case when v_brinde.status = 'usado' then 'usado'
                  when v_brinde.valido_ate < v_hoje then 'expirado'
                  else 'ativo' end;
  end if;

  return jsonb_build_object(
    'tem_data',    v_prof.nascimento is not null,
    'assinante',   v_prof.tier_slug is not null,
    'eh_mes',      v_eh_mes,
    'eh_dia',      v_eh_dia,
    'ja_resgatou', found,
    'codigo',      v_brinde.codigo,
    'valido_ate',  v_brinde.valido_ate,
    'situacao',    v_sit,
    'usado_em',    v_brinde.usado_em
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- resgatar_brinde_aniversario() → jsonb {ok, codigo, valido_ate, novo|ja_tinha}
-- Reserva o brunch do ano. Recomputa TODAS as travas no banco. Idempotente por
-- (user, ano): pedir de novo devolve o mesmo código. O código vale 30 dias.
-- -----------------------------------------------------------------------------
create or replace function public.resgatar_brinde_aniversario()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_prof   public.profiles;
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ano    integer := extract(year from v_hoje)::int;
  v_brinde public.brindes_aniversario;
  v_codigo text;
  v_valido date := v_hoje + 30;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'precisa estar logado');
  end if;

  -- Serializa os resgates do PRÓPRIO usuário (mesmo padrão do redeem_reward):
  -- dois cliques simultâneos não geram dois brindes.
  perform 1 from public.profiles where id = v_uid for update;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'perfil não encontrado');
  end if;

  if v_prof.nascimento is null then
    return jsonb_build_object('ok', false, 'precisa_data', true,
      'erro', 'conta pra gente teu aniversário no perfil, aí a gente comemora 🎂');
  end if;

  if v_prof.tier_slug is null then
    return jsonb_build_object('ok', false, 'precisa_assinar', true,
      'erro', 'o brunch de aniversário é um mimo de quem tem plano 💛');
  end if;

  if extract(month from v_prof.nascimento) <> extract(month from v_hoje) then
    return jsonb_build_object('ok', false, 'fora_do_mes', true,
      'erro', 'ainda não é teu mês — guarda esse abraço pra quando chegar');
  end if;

  -- Já resgatou este ano? Devolve o mesmo (idempotente).
  select * into v_brinde
    from public.brindes_aniversario
   where user_id = v_uid and ano = v_ano;
  if found then
    return jsonb_build_object('ok', true, 'ja_tinha', true,
      'codigo', v_brinde.codigo, 'valido_ate', v_brinde.valido_ate,
      'status', v_brinde.status);
  end if;

  -- Código único CASA-XXXXXX.
  loop
    v_codigo := 'CASA-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.brindes_aniversario where codigo = v_codigo);
  end loop;

  begin
    insert into public.brindes_aniversario (user_id, ano, codigo, valido_ate)
    values (v_uid, v_ano, v_codigo, v_valido)
    returning * into v_brinde;
  exception when unique_violation then
    -- Corrida: outro request criou primeiro. Lê e devolve o dele.
    select * into v_brinde
      from public.brindes_aniversario
     where user_id = v_uid and ano = v_ano;
    return jsonb_build_object('ok', true, 'ja_tinha', true,
      'codigo', v_brinde.codigo, 'valido_ate', v_brinde.valido_ate,
      'status', v_brinde.status);
  end;

  return jsonb_build_object('ok', true, 'novo', true,
    'codigo', v_brinde.codigo, 'valido_ate', v_brinde.valido_ate);
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_brindes_listar(busca, status) → tabela pro console. Owner ou 'resgates'.
--   p_busca   casa por código ou nome (case-insensitive); nulo = todos.
--   p_status  'ativo' | 'usado' | 'expirado' | null.
-- -----------------------------------------------------------------------------
create or replace function public.admin_brindes_listar(
  p_busca  text default null,
  p_status text default null,
  p_limite integer default 200
)
returns table (
  id                uuid,
  criado_em         timestamptz,
  codigo            text,
  situacao          text,
  valido_ate_label  text,
  aniversario       text,
  cliente_nome      text,
  cliente_email     text,
  usado_em          timestamptz,
  usado_por_nome    text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not public.tem_permissao('resgates') then
    raise exception 'sem permissão pra ver os brindes';
  end if;

  return query
    select
      b.id,
      b.criado_em,
      b.codigo,
      case when b.status = 'usado' then 'usado'
           when b.valido_ate < v_hoje then 'expirado'
           else 'ativo' end                        as situacao,
      to_char(b.valido_ate, 'DD/MM')               as valido_ate_label,
      to_char(pr.nascimento, 'DD/MM')              as aniversario,
      coalesce(pr.apelido, pr.full_name, '')       as cliente_nome,
      coalesce(u.email, '')                        as cliente_email,
      b.usado_em,
      coalesce(baixa.full_name, '')                as usado_por_nome
    from public.brindes_aniversario b
    left join public.profiles pr    on pr.id = b.user_id
    left join auth.users      u     on u.id  = b.user_id
    left join public.profiles baixa on baixa.id = b.usado_por
    where (v_busca is null
           or b.codigo ilike '%' || v_busca || '%'
           or pr.full_name ilike '%' || v_busca || '%'
           or pr.apelido ilike '%' || v_busca || '%')
      and (
        p_status is null
        or (p_status = 'usado'    and b.status = 'usado')
        or (p_status = 'ativo'    and b.status = 'ativo' and b.valido_ate >= v_hoje)
        or (p_status = 'expirado' and b.status = 'ativo' and b.valido_ate <  v_hoje)
      )
    order by b.criado_em desc
    limit greatest(1, least(coalesce(p_limite, 200), 500));
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_brinde_usar(id) → jsonb. "Brunch entregue". Owner ou 'resgates'.
-- Idempotente. Recusa código já usado (com bom humor) ou vencido.
-- -----------------------------------------------------------------------------
create or replace function public.admin_brinde_usar(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_brinde public.brindes_aniversario;
begin
  if not public.tem_permissao('resgates') then
    raise exception 'sem permissão pra dar baixa em brinde';
  end if;

  select * into v_brinde from public.brindes_aniversario where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'brinde não encontrado');
  end if;

  if v_brinde.status = 'usado' then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'usado_em', v_brinde.usado_em);
  end if;

  if v_brinde.valido_ate < v_hoje then
    return jsonb_build_object('ok', false, 'erro',
      'esse código venceu em ' || to_char(v_brinde.valido_ate, 'DD/MM'));
  end if;

  update public.brindes_aniversario
     set status = 'usado', usado_em = now(), usado_por = v_uid
   where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'brinde_aniversario_usado', 'brindes_aniversario', p_id::text,
          jsonb_build_object('codigo', v_brinde.codigo));

  return jsonb_build_object('ok', true, 'usado_em', now());
end;
$$;

revoke all on function public.meu_brinde_aniversario()                       from public, anon;
revoke all on function public.resgatar_brinde_aniversario()                  from public, anon;
revoke all on function public.admin_brindes_listar(text, text, integer)      from public, anon;
revoke all on function public.admin_brinde_usar(uuid)                        from public, anon;

grant execute on function public.meu_brinde_aniversario()                    to authenticated;
grant execute on function public.resgatar_brinde_aniversario()               to authenticated;
grant execute on function public.admin_brindes_listar(text, text, integer)   to authenticated;
grant execute on function public.admin_brinde_usar(uuid)                     to authenticated;



-- ===== 0026_agenda.sql =====

-- =============================================================================
-- 0026_agenda.sql — "A agenda do Casa" 📅
--
-- O Casa se define como "um café-casa de ENCONTROS", mas o site não tinha
-- encontro nenhum. A tabela `events` já existia (0004_reconcile) e nunca foi
-- usada — esta migration a acorda: o owner cadastra os próximos encontros no
-- console, eles aparecem numa seção na home, e o ASSINANTE confirma presença
-- ("eu vou"), com uma lotação gentil (as `vagas` que a 0004 já previa).
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Leitura da agenda é PÚBLICA, mas por uma RPC curada (`agenda_proximos`) —
--     ela conta os confirmados SEM expor quem confirmou (as linhas de RSVP são
--     pessoais). A `events` já tinha leitura pública dos ativos (0004); o que a
--     RPC acrescenta é a contagem + "eu vou" do próprio usuário.
--   • RSVP é perk de ASSINANTE (como o Mural/brinde): só confirma quem tem plano
--     vigente. Toda trava (assinante, evento ativo/futuro, lotação) é recomputada
--     no banco, com lock na linha do evento — duas confirmações simultâneas não
--     estouram a vaga.
--   • `event_rsvps` é deny-by-default pro client: cada um lê só o próprio RSVP
--     (o owner lê todos); ESCRITA só pelas RPCs SECURITY DEFINER.
--   • Curadoria no console: RPCs `admin_evento_*` gated por is_owner() (mesmo
--     padrão de avisos/trilha; owner-only, sem permissão nova no whitelist do 0017).
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

-- A 0004 criou `events` (nome, descricao, data, vagas, ativo). Dois campos a mais:
alter table public.events add column if not exists local      text;
alter table public.events add column if not exists updated_at timestamptz;

-- -----------------------------------------------------------------------------
-- event_rsvps — quem confirmou presença em cada encontro. Uma linha por pessoa
-- × evento (PK composta = anti-duplicata natural).
-- -----------------------------------------------------------------------------
create table if not exists public.event_rsvps (
  event_id    uuid not null references public.events (id)   on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (event_id, user_id)
);

create index if not exists idx_event_rsvps_event on public.event_rsvps (event_id);

alter table public.event_rsvps enable row level security;

-- Cada um lê o próprio RSVP; o owner lê todos (pro console). Escrita nenhuma pelo
-- client — só pelas RPCs abaixo.
drop policy if exists event_rsvps_select_own on public.event_rsvps;
create policy event_rsvps_select_own on public.event_rsvps
  for select to authenticated
  using (user_id = auth.uid() or public.is_owner());

-- -----------------------------------------------------------------------------
-- agenda_proximos() → setof (encontros ativos e futuros, com contagem e "eu vou").
-- Leitura PÚBLICA (anon vê a agenda; só não tem "eu vou"). Conta os confirmados
-- sem revelar quem são. "Futuro" tolera 4h de folga (evento rolando ainda aparece).
-- -----------------------------------------------------------------------------
create or replace function public.agenda_proximos()
returns table (
  id           uuid,
  nome         text,
  descricao    text,
  data         timestamptz,
  local        text,
  vagas        integer,
  confirmados  bigint,
  eu_vou       boolean,
  lotado       boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    e.id, e.nome, e.descricao, e.data, e.local, e.vagas,
    coalesce(c.n, 0)                                   as confirmados,
    (auth.uid() is not null and r.user_id is not null) as eu_vou,
    (e.vagas is not null and coalesce(c.n, 0) >= e.vagas) as lotado
  from public.events e
  left join lateral (
    select count(*) as n from public.event_rsvps rr where rr.event_id = e.id
  ) c on true
  left join public.event_rsvps r
    on r.event_id = e.id and r.user_id = auth.uid()
  where e.ativo
    and (e.data is null or e.data >= now() - interval '4 hours')
  order by e.data asc nulls last, e.created_at asc
  limit 12;
$$;

-- -----------------------------------------------------------------------------
-- confirmar_presenca(event_id) → jsonb. Perk de assinante. Recomputa TUDO no
-- banco (assinante, evento ativo/futuro, lotação) com lock na linha do evento.
-- Idempotente: confirmar de novo devolve "eu vou" sem duplicar.
-- -----------------------------------------------------------------------------
create or replace function public.confirmar_presenca(p_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_prof  public.profiles;
  v_ev    public.events;
  v_n     integer;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'precisa estar logado');
  end if;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'perfil não encontrado');
  end if;
  if v_prof.tier_slug is null then
    return jsonb_build_object('ok', false, 'precisa_assinar', true,
      'erro', 'confirmar presença é um mimo de quem tem plano 💛');
  end if;

  -- Lock no evento: serializa as confirmações concorrentes (a vaga não estoura).
  select * into v_ev from public.events where id = p_event_id for update;
  if not found or not v_ev.ativo then
    return jsonb_build_object('ok', false, 'erro', 'esse encontro não está mais aberto');
  end if;
  if v_ev.data is not null and v_ev.data < now() - interval '4 hours' then
    return jsonb_build_object('ok', false, 'erro', 'esse encontro já passou');
  end if;

  -- Já vou? Idempotente.
  if exists (select 1 from public.event_rsvps where event_id = p_event_id and user_id = v_uid) then
    select count(*) into v_n from public.event_rsvps where event_id = p_event_id;
    return jsonb_build_object('ok', true, 'eu_vou', true, 'ja_estava', true, 'confirmados', v_n);
  end if;

  select count(*) into v_n from public.event_rsvps where event_id = p_event_id;
  if v_ev.vagas is not null and v_n >= v_ev.vagas then
    return jsonb_build_object('ok', false, 'lotado', true,
      'erro', 'as vagas desse encontro acabaram — mas vem que a gente dá um jeito 💛');
  end if;

  insert into public.event_rsvps (event_id, user_id) values (p_event_id, v_uid)
  on conflict (event_id, user_id) do nothing;

  select count(*) into v_n from public.event_rsvps where event_id = p_event_id;
  return jsonb_build_object('ok', true, 'eu_vou', true, 'confirmados', v_n);
end;
$$;

-- -----------------------------------------------------------------------------
-- cancelar_presenca(event_id) → jsonb. Tira o próprio RSVP. Idempotente.
-- -----------------------------------------------------------------------------
create or replace function public.cancelar_presenca(p_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_n   integer;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'precisa estar logado');
  end if;

  delete from public.event_rsvps where event_id = p_event_id and user_id = v_uid;

  select count(*) into v_n from public.event_rsvps where event_id = p_event_id;
  return jsonb_build_object('ok', true, 'eu_vou', false, 'confirmados', v_n);
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_eventos_listar() → setof (TODOS, incl. inativos e passados). Owner-only.
-- -----------------------------------------------------------------------------
create or replace function public.admin_eventos_listar()
returns table (
  id           uuid,
  nome         text,
  descricao    text,
  data         timestamptz,
  local        text,
  vagas        integer,
  ativo        boolean,
  confirmados  bigint,
  created_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_owner() then
    raise exception 'sem permissão';
  end if;
  return query
    select e.id, e.nome, e.descricao, e.data, e.local, e.vagas, e.ativo,
           (select count(*) from public.event_rsvps r where r.event_id = e.id) as confirmados,
           e.created_at
    from public.events e
    order by e.data desc nulls last, e.created_at desc;
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_evento_salvar(...) → events. Cria (p_id null) ou edita. Owner-only.
-- -----------------------------------------------------------------------------
create or replace function public.admin_evento_salvar(
  p_id        uuid,
  p_nome      text,
  p_descricao text,
  p_data      timestamptz,
  p_local     text,
  p_vagas     integer,
  p_ativo     boolean
)
returns public.events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome text := btrim(coalesce(p_nome, ''));
  v_row  public.events;
begin
  if not public.is_owner() then
    raise exception 'sem permissão';
  end if;
  if char_length(v_nome) < 1 then
    raise exception 'dá um nome pro encontro';
  end if;
  if p_vagas is not null and p_vagas < 0 then
    raise exception 'vagas não pode ser negativo';
  end if;

  if p_id is null then
    insert into public.events (nome, descricao, data, local, vagas, ativo, updated_at)
    values (v_nome, nullif(btrim(coalesce(p_descricao, '')), ''), p_data,
            nullif(btrim(coalesce(p_local, '')), ''), p_vagas,
            coalesce(p_ativo, true), now())
    returning * into v_row;
  else
    update public.events set
      nome       = v_nome,
      descricao  = nullif(btrim(coalesce(p_descricao, '')), ''),
      data       = p_data,
      local      = nullif(btrim(coalesce(p_local, '')), ''),
      vagas      = p_vagas,
      ativo      = coalesce(p_ativo, true),
      updated_at = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'encontro não encontrado';
    end if;
  end if;

  return v_row;
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_evento_remover(id) → boolean. Owner-only. (RSVPs somem em cascata.)
-- -----------------------------------------------------------------------------
create or replace function public.admin_evento_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_owner() then
    raise exception 'sem permissão';
  end if;
  delete from public.events where id = p_id;
  return true;
end;
$$;

revoke all on function public.agenda_proximos()                                          from public;
revoke all on function public.confirmar_presenca(uuid)                                   from public, anon;
revoke all on function public.cancelar_presenca(uuid)                                    from public, anon;
revoke all on function public.admin_eventos_listar()                                     from public, anon;
revoke all on function public.admin_evento_salvar(uuid, text, text, timestamptz, text, integer, boolean) from public, anon;
revoke all on function public.admin_evento_remover(uuid)                                 from public, anon;

grant execute on function public.agenda_proximos()                                        to anon, authenticated;
grant execute on function public.confirmar_presenca(uuid)                                 to authenticated;
grant execute on function public.cancelar_presenca(uuid)                                  to authenticated;
grant execute on function public.admin_eventos_listar()                                   to authenticated;
grant execute on function public.admin_evento_salvar(uuid, text, text, timestamptz, text, integer, boolean) to authenticated;
grant execute on function public.admin_evento_remover(uuid)                               to authenticated;



-- ===== 0027_cardapio_favoritos.sql =====

-- =============================================================================
-- 0027_cardapio_favoritos.sql — "Teus favoritos" no cardápio 💛
--
-- O /cardapio era uma lista bonita mas estática. Agora quem está logado favorita
-- um item (um coraçãozinho) e ganha um bloco "teus favoritos" no topo — o de
-- sempre a um toque. De quebra, o Casa vê no console o que a casa mais ama.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • O cardápio é HTML curado (não vem do banco), então o item é identificado
--     por um `item_slug` estável escrito no HTML (`data-item`); o `item_nome` é
--     um snapshot pro console. Favoritar é aberto a QUALQUER pessoa logada (não é
--     perk de assinante) — quanto mais gente marca, mais sinal pra casa.
--   • Favorito é dado BENIGNO e por-usuário (não entra na lista de tabelas
--     sensíveis do security-check): a escrita é DIRETA pelo client via RLS, sempre
--     travada em `auth.uid()` (o default preenche o dono; a policy confere). Cada
--     um só lê/marca/desmarca o PRÓPRIO favorito.
--   • O console lê o agregado por uma RPC SECURITY DEFINER (RLS barraria a soma
--     entre usuários), gated por `tem_permissao('relatorios')` — é um relatório.
--     Pra não confiar cegamente no nome que o client mandou, o agregado usa o
--     nome MAIS FREQUENTE por slug (resiliente a uma linha adulterada; o console
--     ainda escapa tudo).
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

create table if not exists public.cardapio_favoritos (
  user_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  item_slug  text not null check (char_length(btrim(item_slug)) between 1 and 80),
  item_nome  text not null check (char_length(btrim(item_nome)) between 1 and 160),
  created_at timestamptz not null default now(),
  primary key (user_id, item_slug)
);

create index if not exists idx_cardapio_fav_slug on public.cardapio_favoritos (item_slug);

alter table public.cardapio_favoritos enable row level security;

-- Cada um cuida só do próprio favorito. `default auth.uid()` preenche o dono, e a
-- policy confere — o client nunca favorita em nome de outro.
drop policy if exists cardapio_fav_select_own on public.cardapio_favoritos;
create policy cardapio_fav_select_own on public.cardapio_favoritos
  for select to authenticated using (user_id = auth.uid());

drop policy if exists cardapio_fav_insert_own on public.cardapio_favoritos;
create policy cardapio_fav_insert_own on public.cardapio_favoritos
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists cardapio_fav_delete_own on public.cardapio_favoritos;
create policy cardapio_fav_delete_own on public.cardapio_favoritos
  for delete to authenticated using (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- admin_cardapio_favoritos() → o que a casa mais ama. Owner ou 'relatorios'.
-- Agrega por slug; o nome exibido é o mais frequente daquele slug (defesa contra
-- um snapshot adulterado numa linha solta).
-- -----------------------------------------------------------------------------
create or replace function public.admin_cardapio_favoritos()
returns table (
  item_slug  text,
  item_nome  text,
  favoritos  bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra ver os favoritos';
  end if;
  return query
    select
      f.item_slug,
      (select f2.item_nome
         from public.cardapio_favoritos f2
        where f2.item_slug = f.item_slug
        group by f2.item_nome
        order by count(*) desc, f2.item_nome asc
        limit 1)                as item_nome,
      count(*)::bigint          as favoritos
    from public.cardapio_favoritos f
    group by f.item_slug
    order by count(*) desc, item_nome asc;
end;
$$;

revoke all on function public.admin_cardapio_favoritos() from public, anon;
grant execute on function public.admin_cardapio_favoritos() to authenticated;



-- ===== 0028_agenda_quem_vai.sql =====

-- =============================================================================
-- 0028_agenda_quem_vai.sql — "Quem vai" nos encontros 👋
--
-- A agenda (0026) já conta os confirmados; o "meu cantinho" (0024) já dá rosto
-- público a quem quer. Isto junta os dois: cada encontro passa a mostrar os
-- ROSTINHOS de quem vai — mas SÓ de quem ligou o perfil público. Todo o resto
-- continua contado de forma anônima, exatamente como antes.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Privacidade por construção: só entram no payload os RSVPs de quem tem
--     `perfil_publico = true`. Quem não optou nunca aparece — só soma na contagem.
--   • O payload é CURADO (handle, nome de exibição, avatar) — os mesmos campos já
--     públicos pelo `perfil_publico()` e pela página `/gente/{handle}`. Nada novo é
--     exposto; e-mail/telefone/nome real completo continuam de fora.
--   • Só reescreve a função de LEITURA `agenda_proximos` (adiciona a coluna
--     `vao_publicos`). Nenhuma tabela nova, nenhuma permissão nova.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (DROP FUNCTION IF EXISTS + CREATE).
-- =============================================================================

-- Adicionar uma coluna ao retorno muda a assinatura → precisa dropar e recriar
-- (CREATE OR REPLACE não troca o tipo de retorno de uma função que devolve TABLE).
drop function if exists public.agenda_proximos();

create function public.agenda_proximos()
returns table (
  id            uuid,
  nome          text,
  descricao     text,
  data          timestamptz,
  local         text,
  vagas         integer,
  confirmados   bigint,
  eu_vou        boolean,
  lotado        boolean,
  vao_publicos  jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    e.id, e.nome, e.descricao, e.data, e.local, e.vagas,
    coalesce(c.n, 0)                                     as confirmados,
    (auth.uid() is not null and r.user_id is not null)   as eu_vou,
    (e.vagas is not null and coalesce(c.n, 0) >= e.vagas) as lotado,
    -- Só os presentes com perfil público (handle, nome de exibição, avatar).
    -- Quem não optou nunca entra aqui — mas continua contado em `confirmados`.
    coalesce((
      select jsonb_agg(sub.obj order by sub.ord)
      from (
        select
          jsonb_build_object(
            'handle',     p.handle,
            'nome',       coalesce(
                            nullif(btrim(p.apelido), ''),
                            nullif(split_part(btrim(coalesce(p.full_name, '')), ' ', 1), ''),
                            'alguém do Casa'),
            'avatar_url', p.avatar_url
          )        as obj,
          rr.created_at as ord
        from public.event_rsvps rr
        join public.profiles p on p.id = rr.user_id
        where rr.event_id = e.id
          and p.perfil_publico = true
          and p.handle is not null
        order by rr.created_at asc
        limit 12
      ) sub
    ), '[]'::jsonb)                                      as vao_publicos
  from public.events e
  left join lateral (
    select count(*) as n from public.event_rsvps rc where rc.event_id = e.id
  ) c on true
  left join public.event_rsvps r
    on r.event_id = e.id and r.user_id = auth.uid()
  where e.ativo
    and (e.data is null or e.data >= now() - interval '4 hours')
  order by e.data asc nulls last, e.created_at asc
  limit 12;
$$;

revoke all on function public.agenda_proximos() from public;
grant execute on function public.agenda_proximos() to anon, authenticated;



-- ===== 0029_loja_desejos.sql =====

-- =============================================================================
-- 0029_loja_desejos.sql — "Ficou pra depois" (lista de desejos da loja) 🔖
--
-- O irmão do "teus favoritos" do cardápio (0027), agora na loja: um coração em
-- cada produto SALVA pra depois sem botar no carrinho. Uma tirinha "ficou pra
-- depois" no topo da /loja (e um espelho no /conta/perfil) reúne o que a pessoa
-- guardou, tirando o atrito do "gostei mas agora não". De quebra, o Casa vê no
-- console a demanda represada por produto.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • O catálogo é um mock no client (PRODUTOS no app.js), então o produto é
--     identificado por um `produto_slug` estável (o mesmo slug da URL /produto);
--     o `produto_nome` é um snapshot pro console. Guardar é aberto a QUALQUER
--     pessoa logada (não é perk de assinante) — quanto mais gente guarda, mais
--     sinal pra casa.
--   • Desejo é dado BENIGNO e por-usuário (não entra na lista de tabelas
--     sensíveis do security-check): a escrita é DIRETA pelo client via RLS,
--     sempre travada em `auth.uid()` (o default preenche o dono; a policy
--     confere). Cada um só lê/guarda/tira o PRÓPRIO desejo.
--   • O console lê o agregado por uma RPC SECURITY DEFINER (RLS barraria a soma
--     entre usuários), gated por `tem_permissao('relatorios')` — é um relatório.
--     Pra não confiar cegamente no nome que o client mandou, o agregado usa o
--     nome MAIS FREQUENTE por slug (resiliente a uma linha adulterada; o console
--     ainda escapa tudo).
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

create table if not exists public.loja_desejos (
  user_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  produto_slug text not null check (char_length(btrim(produto_slug)) between 1 and 80),
  produto_nome text not null check (char_length(btrim(produto_nome)) between 1 and 160),
  created_at   timestamptz not null default now(),
  primary key (user_id, produto_slug)
);

create index if not exists idx_loja_desejos_slug on public.loja_desejos (produto_slug);

alter table public.loja_desejos enable row level security;

-- Cada um cuida só do próprio desejo. `default auth.uid()` preenche o dono, e a
-- policy confere — o client nunca guarda em nome de outro.
drop policy if exists loja_desejos_select_own on public.loja_desejos;
create policy loja_desejos_select_own on public.loja_desejos
  for select to authenticated using (user_id = auth.uid());

drop policy if exists loja_desejos_insert_own on public.loja_desejos;
create policy loja_desejos_insert_own on public.loja_desejos
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists loja_desejos_delete_own on public.loja_desejos;
create policy loja_desejos_delete_own on public.loja_desejos
  for delete to authenticated using (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- admin_loja_desejos() → o que a casa mais quer. Owner ou 'relatorios'.
-- Agrega por slug; o nome exibido é o mais frequente daquele slug (defesa contra
-- um snapshot adulterado numa linha solta).
-- -----------------------------------------------------------------------------
create or replace function public.admin_loja_desejos()
returns table (
  produto_slug text,
  produto_nome text,
  desejos      bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra ver os desejos';
  end if;
  return query
    select
      d.produto_slug,
      (select d2.produto_nome
         from public.loja_desejos d2
        where d2.produto_slug = d.produto_slug
        group by d2.produto_nome
        order by count(*) desc, d2.produto_nome asc
        limit 1)                as produto_nome,
      count(*)::bigint          as desejos
    from public.loja_desejos d
    group by d.produto_slug
    order by count(*) desc, produto_nome asc;
end;
$$;

revoke all on function public.admin_loja_desejos() from public, anon;
grant execute on function public.admin_loja_desejos() to authenticated;



-- ===== 0030_avisos_reposicao.sql =====

-- =============================================================================
-- 0030_avisos_reposicao.sql — "Volta pra vitrine" (avisa quando o produto voltar) 🔔
--
-- Puxa o gancho da lista de desejos (0029): quando um produto está esgotado /
-- fora da vitrine, em vez de um "esgotado" mudo, a pessoa toca em "me avisa
-- quando voltar" e deixa o interesse registrado. Quando a casa repõe, o front
-- mostra um "voltou 💛" na volta dela (sem e-mail por enquanto). Pro Casa, o
-- console mostra QUANTAS pessoas esperam cada produto voltar — o sinal mais
-- forte pra guiar a reposição.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Mesmo padrão do loja_desejos (0029): o produto é identificado pelo `slug`
--     da URL /produto; `produto_nome` é snapshot pro console. Registrar interesse
--     é aberto a qualquer pessoa logada (não é perk de assinante).
--   • Interesse de reposição é dado BENIGNO e por-usuário (não entra na lista de
--     tabelas sensíveis do security-check): a escrita é DIRETA pelo client via
--     RLS, sempre travada em `auth.uid()`. Cada um só lê/põe/tira o PRÓPRIO aviso.
--   • O console lê o agregado por uma RPC SECURITY DEFINER (RLS barraria a soma
--     entre usuários), gated por `tem_permissao('relatorios')` — é um relatório.
--     O nome exibido é o MAIS FREQUENTE por slug (resiliente a linha adulterada).
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

create table if not exists public.avisos_reposicao (
  user_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  produto_slug text not null check (char_length(btrim(produto_slug)) between 1 and 80),
  produto_nome text not null check (char_length(btrim(produto_nome)) between 1 and 160),
  created_at   timestamptz not null default now(),
  primary key (user_id, produto_slug)
);

create index if not exists idx_avisos_reposicao_slug on public.avisos_reposicao (produto_slug);

alter table public.avisos_reposicao enable row level security;

-- Cada um cuida só do próprio aviso. `default auth.uid()` preenche o dono, e a
-- policy confere — o client nunca registra em nome de outro.
drop policy if exists avisos_reposicao_select_own on public.avisos_reposicao;
create policy avisos_reposicao_select_own on public.avisos_reposicao
  for select to authenticated using (user_id = auth.uid());

drop policy if exists avisos_reposicao_insert_own on public.avisos_reposicao;
create policy avisos_reposicao_insert_own on public.avisos_reposicao
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists avisos_reposicao_delete_own on public.avisos_reposicao;
create policy avisos_reposicao_delete_own on public.avisos_reposicao
  for delete to authenticated using (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- admin_avisos_reposicao() → quem está esperando o quê. Owner ou 'relatorios'.
-- Agrega por slug; o nome exibido é o mais frequente daquele slug (defesa contra
-- um snapshot adulterado numa linha solta).
-- -----------------------------------------------------------------------------
create or replace function public.admin_avisos_reposicao()
returns table (
  produto_slug text,
  produto_nome text,
  esperando    bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra ver os avisos de reposição';
  end if;
  return query
    select
      a.produto_slug,
      (select a2.produto_nome
         from public.avisos_reposicao a2
        where a2.produto_slug = a.produto_slug
        group by a2.produto_nome
        order by count(*) desc, a2.produto_nome asc
        limit 1)                as produto_nome,
      count(*)::bigint          as esperando
    from public.avisos_reposicao a
    group by a.produto_slug
    order by count(*) desc, produto_nome asc;
end;
$$;

revoke all on function public.admin_avisos_reposicao() from public, anon;
grant execute on function public.admin_avisos_reposicao() to authenticated;



-- ===== 0031_lista_espera.sql =====

-- =============================================================================
-- 0031_lista_espera.sql — "avisa quando a loja abrir" (captura de e-mail) 💌
--
-- Quem passa pelo site e ainda não quer criar conta hoje não deixa rastro
-- nenhum: ou cadastra tudo, ou some. Um campinho no rodapé ("avisa quando a
-- loja abrir de vez") guarda só o e-mail, pra a casa chamar quando abrir.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • É a única tabela do projeto que o VISITANTE DESLOGADO escreve — é o ponto
--     dela. Por isso ela é insert-only pro client: existe policy de INSERT (anon
--     e authenticated) e NENHUMA de select/update/delete, então o deny-by-default
--     do RLS faz o resto. Ninguém, nem logado, LÊ esta tabela pelo client: quem
--     lê é o console, pela RPC abaixo.
--   • A policy repete no `with check` os mesmos limites do CHECK da coluna
--     (formato e tamanho do e-mail) — o client é quem manda o valor, então a
--     trava mora no banco.
--   • Sem user_id de propósito: a graça é justamente não exigir conta. O
--     `origem` guarda só o caminho da página onde a pessoa deixou o e-mail
--     (/home, /loja…), pra a casa saber de onde veio o interesse.
--   • UNIQUE no e-mail pra ninguém entrar duas vezes. O front manda com
--     `ignoreDuplicates` (INSERT … ON CONFLICT DO NOTHING), então repetir o
--     cadastro responde igual a cadastrar pela primeira vez — não dá pra usar a
--     resposta pra descobrir quem já está na lista.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

create table if not exists public.lista_espera (
  id         uuid primary key default gen_random_uuid(),
  email      text not null unique
               check (char_length(email) between 6 and 160 and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  origem     text check (origem is null or char_length(origem) <= 120),
  created_at timestamptz not null default now()
);

create index if not exists idx_lista_espera_created on public.lista_espera (created_at desc);

alter table public.lista_espera enable row level security;

-- Só INSERT, e só o que passa pelos limites. Sem policy de select: nem anon nem
-- authenticated leem a lista (deny-by-default).
drop policy if exists lista_espera_insert_publico on public.lista_espera;
create policy lista_espera_insert_publico on public.lista_espera
  for insert to anon, authenticated
  with check (
    char_length(email) between 6 and 160
    and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    and (origem is null or char_length(origem) <= 120)
  );

-- -----------------------------------------------------------------------------
-- admin_lista_espera(limite) → quem está esperando o aviso. Owner ou 'relatorios'
-- (é relatório de interesse, mesma porta dos favoritos/desejos).
-- -----------------------------------------------------------------------------
create or replace function public.admin_lista_espera(p_limite int default 500)
returns table (
  id         uuid,
  email      text,
  origem     text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra ver a lista de espera';
  end if;
  return query
    select e.id, e.email, e.origem, e.created_at
      from public.lista_espera e
     order by e.created_at desc
     limit greatest(1, least(coalesce(p_limite, 500), 2000));
end;
$$;

revoke all on function public.admin_lista_espera(int) from public, anon;
grant execute on function public.admin_lista_espera(int) to authenticated;



-- ===== 0032_senha_inicial_master.sql =====

-- =============================================================================
-- 0032_senha_inicial_master.sql — a senha inicial do adm master trava o console
--
-- O PROBLEMA (achado em auditoria de segurança):
--   O `scripts/criar-adm-master.mjs` criava a conta do adm master com uma senha
--   combinada, e a obrigação de trocá-la no primeiro acesso existia SÓ na tela
--   (`src/admin.js`). No banco, `senha_alterada_em` era apenas LIDA pra montar o
--   JSON da tela — nenhuma função de papel consultava ela. Ou seja: quem soubesse
--   a senha inicial fazia login direto no endpoint do Auth (a anon key e a URL do
--   projeto estão no bundle público, como têm que estar), recebia um JWT de owner
--   e chamava `admin_usuarios`, `admin_pedidos`, `admin_definir_permissoes` por
--   fora da tela, sem nunca ver o formulário de troca. Pior: `is_staff()` inclui
--   o owner, e a policy `profiles_select` (0002) usa `is_staff()`, então dava pra
--   ler a `profiles` inteira (nome, e-mail, telefone) direto pelo PostgREST.
--
-- A CORREÇÃO, em duas metades:
--   1. O script passa a sortear uma senha aleatória por execução (nada de senha
--      combinada no repo) — ver `scripts/criar-adm-master.mjs`.
--   2. Esta migration move a trava pro BANCO, que é o único lugar onde ela vale.
--
-- COMO A TRAVA SABE QUE A SENHA AINDA É A INICIAL:
--   Não pelo carimbo `senha_alterada_em` — ele é gravado por uma RPC que o próprio
--   invasor poderia chamar, e aí a trava se desarmaria sozinha. A gente guarda o
--   HASH da senha inicial (`profiles.senha_inicial_hash`, copiado de
--   `auth.users.encrypted_password`) e compara com o hash de agora. Enquanto forem
--   iguais, a senha NÃO mudou, ponto — não há RPC que minta sobre isso. Trocar a
--   senha de verdade, pelo Auth, é o único jeito de destravar, e o destravamento é
--   automático (o hash muda). Guardar o hash não é guardar a senha: é o mesmo
--   bcrypt que o Auth já guarda, e ele fica numa coluna que o client não lê
--   (a `profiles` só é legível pelo dono e pelo staff).
--
-- O QUE FICA TRAVADO: todas as funções de papel (`is_owner`, `is_staff`,
--   `is_gerente_or_owner`, `tem_permissao`, `pode_entrar_no_console`) respondem
--   FALSO enquanto a senha inicial estiver de pé. Como as policies de RLS e o
--   corpo de cada `admin_*` chamam essas funções, a conta fica sem privilégio
--   nenhum em lugar nenhum — só a própria linha do `profiles`, como qualquer
--   cliente. O `admin_minhas_permissoes` continua respondendo `console: true` de
--   propósito, senão o console diria "esse balcão não é teu" e a pessoa não teria
--   por onde trocar a senha.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Depende da 0017_admin (colunas `master` / `senha_alterada_em`).
-- Idempotente (add column if not exists / CREATE OR REPLACE).
-- =============================================================================

alter table public.profiles add column if not exists senha_inicial_hash text;

-- Backfill pra quem já tem o master criado: se ele NUNCA trocou a senha
-- (`senha_alterada_em is null`), o hash de agora É o da senha inicial — grava e a
-- trava já vale pra deployments existentes. Quem já trocou fica com a coluna null
-- (nada a travar).
update public.profiles p
   set senha_inicial_hash = u.encrypted_password
  from auth.users u
 where u.id = p.id
   and p.master
   and p.senha_alterada_em is null
   and p.senha_inicial_hash is null;

-- -----------------------------------------------------------------------------
-- senha_inicial_pendente() — true enquanto o master não trocou a senha de fato.
-- Compara o hash guardado com o hash atual do Auth: só a troca real desarma.
-- Vale só pro master (o `handle_new_user` não preenche `senha_alterada_em`, então
-- sem o gate de `master` todo funcionário promovido a partir de conta de cliente
-- cairia aqui e perderia o acesso sem motivo).
-- -----------------------------------------------------------------------------
create or replace function public.senha_inicial_pendente()
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select exists (
    select 1
      from public.profiles p
      join auth.users u on u.id = p.id
     where p.id = auth.uid()
       and p.master
       and p.senha_inicial_hash is not null
       and u.encrypted_password = p.senha_inicial_hash
  );
$$;

revoke all on function public.senha_inicial_pendente() from public, anon;
grant execute on function public.senha_inicial_pendente() to authenticated;

-- -----------------------------------------------------------------------------
-- As funções de papel, agora com a trava. Corpo idêntico ao original (0001/0017),
-- só acrescido do `and not public.senha_inicial_pendente()`.
-- -----------------------------------------------------------------------------
create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.profiles where id = auth.uid()) = 'owner'
    and not public.senha_inicial_pendente(),
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
    (select role from public.profiles where id = auth.uid()) in ('gerente', 'owner')
    and not public.senha_inicial_pendente(),
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
    (select role from public.profiles where id = auth.uid()) in ('staff', 'gerente', 'owner')
    and not public.senha_inicial_pendente(),
    false
  );
$$;

create or replace function public.tem_permissao(p_perm text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      (select role from public.profiles where id = auth.uid()) = 'owner'
      or exists (
        select 1 from public.staff_permissions
         where user_id = auth.uid() and permissao = p_perm
      )
    )
    and not public.senha_inicial_pendente(),
    false
  );
$$;

create or replace function public.pode_entrar_no_console()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      (select role from public.profiles where id = auth.uid()) = 'owner'
      or exists (select 1 from public.staff_permissions where user_id = auth.uid())
    )
    and not public.senha_inicial_pendente(),
    false
  );
$$;

-- -----------------------------------------------------------------------------
-- admin_senha_alterada — agora CONFERE antes de carimbar. Se o hash continua o
-- mesmo, a senha não mudou e a função recusa (era exatamente por aqui que dava
-- pra desarmar a tela sem trocar nada). Ao confirmar a troca, apaga o hash
-- guardado: a trava é uma porta de mão única.
-- -----------------------------------------------------------------------------
create or replace function public.admin_senha_alterada()
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_uid           uuid := auth.uid();
  v_hash_inicial  text;
  v_hash_atual    text;
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  select p.senha_inicial_hash, u.encrypted_password
    into v_hash_inicial, v_hash_atual
    from public.profiles p
    join auth.users u on u.id = p.id
   where p.id = v_uid;

  if v_hash_inicial is not null and v_hash_atual = v_hash_inicial then
    return jsonb_build_object('ok', false, 'erro', 'a senha ainda é a inicial, escolhe uma nova antes');
  end if;

  update public.profiles
     set senha_alterada_em = now(), senha_inicial_hash = null, updated_at = now()
   where id = v_uid;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'senha_alterada', 'profiles', v_uid::text, '{}'::jsonb);

  return jsonb_build_object('ok', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_minhas_permissoes — o console precisa ENTRAR pra mostrar o formulário de
-- troca, então `console` continua true pro master travado (é a única tela que ele
-- alcança; toda RPC de dado está barrada pelas funções de papel acima). E
-- `senha_trocada` passa a vir da checagem viva do hash, não do carimbo.
-- -----------------------------------------------------------------------------
create or replace function public.admin_minhas_permissoes()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_uid      uuid := auth.uid();
  v_prof     public.profiles;
  v_pendente boolean;
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('console', false);
  end if;

  v_pendente := public.senha_inicial_pendente();

  return jsonb_build_object(
    'console',        public.pode_entrar_no_console() or (v_prof.master and v_pendente),
    'nome',           coalesce(v_prof.full_name, ''),
    'papel',          v_prof.role,
    'master',         v_prof.master,
    'senha_trocada',  not v_pendente,
    'permissoes',     coalesce(
                        (select jsonb_agg(permissao order by permissao)
                           from public.staff_permissions where user_id = v_uid),
                        '[]'::jsonb),
    'tudo',           v_prof.role = 'owner' and not v_pendente
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- registrar_senha_inicial(user_id) — o script de criação chama isto logo depois
-- de criar/repor a senha, pra guardar o hash inicial. O schema `auth` não é
-- exposto pelo PostgREST, então o script (que tem service_role) não consegue ler
-- `encrypted_password` sozinho. Só service_role executa.
-- -----------------------------------------------------------------------------
create or replace function public.registrar_senha_inicial(p_user_id uuid)
returns void
language sql
security definer
set search_path = public, auth, pg_temp
as $$
  update public.profiles p
     set senha_inicial_hash = u.encrypted_password,
         senha_alterada_em  = null,
         updated_at         = now()
    from auth.users u
   where u.id = p.id and p.id = p_user_id;
$$;

revoke all on function public.registrar_senha_inicial(uuid) from public, anon, authenticated;
grant execute on function public.registrar_senha_inicial(uuid) to service_role;



-- ===== 0033_perfil_publico_trava.sql =====

-- =============================================================================
-- 0033_perfil_publico_trava.sql — o cantinho só liga pela porta da frente
--
-- O PROBLEMA (achado em auditoria de segurança):
--   A `definir_perfil_publico(ativar)` (0024) é a porta que exige plano vigente
--   (`tier_slug`) e gera um handle livre. Só que ela não era a ÚNICA porta: a
--   policy `profiles_update_self` (0002) libera UPDATE da linha inteira, e RLS
--   não sabe restringir coluna. Quem protege coluna aqui são triggers — e as que
--   existiam cobrem `role` (0001), `points_balance`/`tier_slug` (0005/0008) e
--   `master` (0017). As colunas da 0024 não tinham nenhuma.
--
--   Resultado: qualquer conta grátis mandava um PATCH direto no PostgREST
--     PATCH /rest/v1/profiles?id=eq.<próprio uid>
--     { "perfil_publico": true, "handle": "casa", "apelido": "Casa Coffee Colab" }
--   e publicava um cantinho sem nunca ter assinado — e, como `handle` é unique e
--   a RPC só escolhe slug livre, dava pra tomar de vez um nome cobiçado (o da
--   própria casa, o de alguém conhecido) numa página do domínio oficial.
--
-- A CORREÇÃO: uma trigger no mesmo formato do `prevent_points_tamper` (0008),
--   com a mesma mecânica de GUC transaction-local pro caminho confiável — a
--   `definir_perfil_publico` acende `casa.trusted_perfil` antes de escrever, e é
--   o único caminho que passa. (SECURITY DEFINER não troca o `auth.uid()`, então
--   a trigger não tem como distinguir a RPC do PATCH cru sem esse sinal.)
--
--   De quebra, a RPC passa a recusar um punhado de handles reservados: o slug sai
--   do apelido, que a pessoa escolhe, então sem isso um assinante ainda poderia
--   virar /gente/casa e falar como se fosse a casa.
--
-- O QUE NÃO MUDA: quem assinou, ligou o cantinho e depois saiu do plano continua
--   com a página no ar. Isso é comportamento de produto (a `perfil_publico(handle)`
--   nunca reconferiu o plano na leitura), não a falha — e derrubar página de gente
--   que pausou o plano é decisão de vocês, não de uma correção de segurança.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez,
-- DEPOIS da 0024_perfil_publico (é ela que cria as colunas e a RPC).
-- Idempotente (CREATE OR REPLACE / drop trigger if exists).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- prevent_perfil_publico_tamper — `perfil_publico` e `handle` só mudam pelo
-- caminho confiável. Mesmo desenho do prevent_points_tamper: GUC libera, cliente
-- autenticado que não é owner apanha.
-- -----------------------------------------------------------------------------
create or replace function public.prevent_perfil_publico_tamper()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Caminho confiável (definir_perfil_publico): libera.
  if coalesce(current_setting('casa.trusted_perfil', true), '') = 'on' then
    return new;
  end if;

  if auth.uid() is not null and not public.is_owner() then
    if new.perfil_publico is distinct from old.perfil_publico then
      raise exception 'o cantinho liga e desliga só pela tela do perfil (não pelo client).';
    end if;
    if new.handle is distinct from old.handle then
      raise exception 'o endereço do cantinho é gerado pelo servidor (não pelo client).';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prevent_perfil_publico_tamper on public.profiles;
create trigger trg_prevent_perfil_publico_tamper
  before update on public.profiles
  for each row execute function public.prevent_perfil_publico_tamper();

-- -----------------------------------------------------------------------------
-- definir_perfil_publico — mesma função da 0024, com duas mudanças:
--   • acende a GUC confiável antes de cada escrita (senão a trigger acima barra
--     a própria porta da frente);
--   • recusa handle reservado, caindo pro sufixo numerado (`casa-2`), pra ninguém
--     virar a casa por escolher o apelido certo.
-- -----------------------------------------------------------------------------
create or replace function public.definir_perfil_publico(p_ativar boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_prof   public.profiles;
  v_base   text;
  v_handle text;
  v_i      integer := 1;
  -- Nomes que falam pela casa (ou pela equipe) e não podem sair no sorteio do slug.
  v_reservados text[] := array[
    'casa', 'casacoffee', 'casacoffeecolab', 'casa-coffee', 'casa-coffee-colab',
    'admin', 'adm', 'equipe', 'staff', 'contato', 'atendimento', 'suporte',
    'oficial', 'loja', 'cardapio', 'planos', 'colab', 'conta', 'gente'
  ];
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'não autenticado');
  end if;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'perfil não encontrado');
  end if;

  -- Desligar é sempre permitido; guarda o handle pra reativar na mesma URL.
  if not coalesce(p_ativar, false) then
    perform set_config('casa.trusted_perfil', 'on', true);
    update public.profiles set perfil_publico = false where id = v_uid;
    return jsonb_build_object('ok', true, 'ativo', false, 'handle', v_prof.handle);
  end if;

  -- Ligar é perk de assinante (mesma régua do Mural/pontos): precisa de plano vigente.
  if v_prof.tier_slug is null then
    return jsonb_build_object('ok', false, 'erro', 'o teu cantinho é um mimo de quem tem plano 💛', 'precisa_assinar', true);
  end if;

  v_handle := v_prof.handle;
  if v_handle is null then
    -- slug base: apelido → nome → 'amigo'. Tira acento comum, deixa a-z0-9 e hífen.
    v_base := lower(coalesce(nullif(btrim(v_prof.apelido), ''), nullif(btrim(v_prof.full_name), ''), 'amigo'));
    v_base := translate(v_base, 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn');
    v_base := btrim(regexp_replace(v_base, '[^a-z0-9]+', '-', 'g'), '-');
    if v_base = '' then v_base := 'amigo'; end if;
    v_handle := v_base;
    -- Reservado ou já tomado: tenta o próximo sufixo. ('casa' → 'casa-2')
    while v_handle = any (v_reservados)
       or exists (select 1 from public.profiles where handle = v_handle and id <> v_uid) loop
      v_i := v_i + 1;
      v_handle := v_base || '-' || v_i;
    end loop;
  end if;

  perform set_config('casa.trusted_perfil', 'on', true);
  update public.profiles set perfil_publico = true, handle = v_handle where id = v_uid;
  return jsonb_build_object('ok', true, 'ativo', true, 'handle', v_handle);
end;
$$;

revoke all on function public.definir_perfil_publico(boolean) from public, anon;
grant execute on function public.definir_perfil_publico(boolean) to authenticated;



-- ===== 0034_lista_espera_rpc.sql =====

-- =============================================================================
-- 0034_lista_espera_rpc.sql — a lista de espera para de responder quem já entrou
--
-- O PROBLEMA (achado em auditoria de segurança):
--   A 0031 fecha a LEITURA direito: `lista_espera` tem policy de INSERT e nenhuma
--   de SELECT, então ninguém lê a lista pelo client. A promessa era que repetir um
--   e-mail respondesse igual a entrar pela primeira vez, pro formulário não virar
--   sonda de "fulano se inscreveu?". Só que quem garantia isso era o CLIENT: o
--   `ignoreDuplicates: true` do `app.js` vira o header `Prefer:
--   resolution=ignore-duplicates`. Quem não manda esse header recebe 201 pra
--   e-mail novo e 409 (`23505`) pra e-mail já cadastrado — com a anon key, sem
--   conta nenhuma. Com uma lista de endereços na mão, dá pra descobrir exatamente
--   quem se inscreveu. Era o único canal de leitura que o desenho queria fechar.
--
-- A CORREÇÃO: tirar o INSERT da mão do client e passar por uma RPC que faz o
--   `on conflict do nothing` POR DENTRO e devolve SEMPRE a mesma coisa. A
--   diferença entre e-mail novo e repetido deixa de existir do lado de fora, não
--   importa que header o chamador mande. Os mesmos limites da 0031 (formato e
--   tamanho) continuam valendo, agora no corpo da função.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez,
-- DEPOIS da 0031_lista_espera. Idempotente.
-- =============================================================================

-- Sem policy de INSERT, sem policy de SELECT: a tabela fica deny-by-default pro
-- client. Quem escreve é a RPC abaixo (SECURITY DEFINER), quem lê é a
-- admin_lista_espera (0031, gated por tem_permissao('relatorios')).
drop policy if exists lista_espera_insert_publico on public.lista_espera;

-- -----------------------------------------------------------------------------
-- entrar_na_lista_espera(email, origem) → jsonb {ok:true} | {ok:false, erro}
-- Resposta CONSTANTE pra e-mail novo e pra e-mail repetido: é isso que impede o
-- formulário de virar sonda. O único `ok:false` é e-mail malformado, que o
-- chamador já sabe (ele digitou) e não conta nada sobre a lista.
-- -----------------------------------------------------------------------------
create or replace function public.entrar_na_lista_espera(p_email text, p_origem text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email  text := lower(btrim(coalesce(p_email, '')));
  v_origem text := nullif(btrim(coalesce(p_origem, '')), '');
begin
  if char_length(v_email) not between 6 and 160
     or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    return jsonb_build_object('ok', false, 'erro', 'esse e-mail não parece completo');
  end if;

  if v_origem is not null then
    v_origem := left(v_origem, 120);
  end if;

  insert into public.lista_espera (email, origem)
  values (v_email, v_origem)
  on conflict (email) do nothing;

  -- Repetido ou novo, a mesma resposta. Pra quem está do outro lado da tela é a
  -- mesma coisa mesmo: já está na lista.
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.entrar_na_lista_espera(text, text) from public;
grant execute on function public.entrar_na_lista_espera(text, text) to anon, authenticated;



-- ===== 0035_orders_estornado.sql =====

-- =============================================================================
-- 0035_orders_estornado.sql — um pedido estornado precisa saber que foi estornado
--
-- O PROBLEMA (achado em auditoria de segurança):
--   O `asaas-webhook` já estorna os pontos de uma ASSINATURA quando o pagamento é
--   devolvido ou vira chargeback — a defesa está lá, com o ataque descrito no
--   próprio comentário: pagar, ganhar pontos, resgatar a recompensa e pedir
--   chargeback. Só que o estorno procura o crédito por `ref_type='subscription'`
--   e `ref_id=payment.id`, e a LOJA credita por `ref_type='order'` /
--   `ref_id=order.id`. Nenhuma compra de loja era alcançada.
--
--   Além dos pontos, o pedido continuava `pago` — ou seja, seguia na fila de quem
--   vai separar e entregar, com o dinheiro já devolvido.
--
--   O `status` da 0001 não tinha como dizer isso: 'cancelado' é o pedido que nunca
--   foi pago (checkout expirou), e usar ele pra um pedido que foi pago e devolvido
--   apagaria a diferença entre as duas coisas no histórico e nos relatórios.
--
-- A CORREÇÃO: mais um estado, 'estornado'. O webhook passa a usá-lo (ver
--   `supabase/functions/asaas-webhook/index.ts`) junto com o lançamento negativo
--   no ledger.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (derruba o CHECK antigo pelo nome que estiver lá e recria).
-- =============================================================================

do $$
declare
  v_nome text;
begin
  select con.conname into v_nome
    from pg_constraint con
    join pg_class      rel on rel.oid = con.conrelid
    join pg_namespace  nsp on nsp.oid = rel.relnamespace
   where nsp.nspname = 'public'
     and rel.relname = 'orders'
     and con.contype = 'c'
     and pg_get_constraintdef(con.oid) ilike '%status%'
   limit 1;

  if v_nome is not null then
    execute format('alter table public.orders drop constraint %I', v_nome);
  end if;
end $$;

alter table public.orders
  add constraint orders_status_check
  check (status in ('pendente', 'pago', 'preparando', 'pronto', 'entregue', 'cancelado', 'estornado'));



-- ===== 0036_mural_e_cantinho_estritos.sql =====

-- =============================================================================
-- 0036_mural_e_cantinho_estritos.sql — os dois apertos que a auditoria apontou
--
-- Nenhum dos dois era buraco alcançável pelo cliente comum: eles ficaram de fora
-- da leva 0032–0035 porque mexiam em comportamento de produto, não em falha. Com
-- o site ainda em teste, o custo de apertar agora é zero e o desenho fica honesto.
--
-- (a) MURAL — o staff podia REESCREVER o recado, não só ocultar.
--     A policy `mural_update_staff` (0020) libera UPDATE da linha inteira pra quem
--     é `is_staff()`, e RLS não sabe restringir coluna. A intenção declarada ali
--     ("staff altera status (ex.: ocultar)") não era o que o banco garantia: dava
--     pra trocar o `texto` e até o `user_id`, ou seja, pôr na parede uma frase que
--     a pessoa não escreveu, assinada com o nome dela. Não era escalada (staff só
--     o owner concede), mas é poder que ninguém pediu.
--     → Trigger que barra mudança em `texto`, `autor_nome` e `user_id` vinda de
--       sessão logada. Moderar (mexer no `status`) segue liberado, e a
--       `postar-mural` não é afetada: ela escreve com service_role, onde
--       `auth.uid()` é nulo. Mesmo desenho dos outros guardas de coluna do projeto
--       (prevent_points_tamper, prevent_perfil_publico_tamper).
--
-- (b) CANTINHO — a leitura pública não reconferia o plano.
--     A `perfil_publico(handle)` (0024) só olhava a flag `perfil_publico`. Quem
--     assinou, ligou o cantinho e depois saiu do plano continuava com a página no
--     ar pra sempre. Ligar é perk de assinante; ficar no ar também deveria ser.
--     → A leitura passa a exigir `tier_slug` — a MESMA régua que a
--       `definir_perfil_publico` usa pra deixar ligar. Quem pausa o plano some da
--       vitrine e VOLTA sozinho quando reassina: a flag e o handle continuam
--       guardados na linha, nada é apagado. Handle não é perdido nem reciclado.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez, DEPOIS
-- da 0020_mural e da 0024_perfil_publico. Idempotente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (a) o recado do mural não se reescreve
-- -----------------------------------------------------------------------------
create or replace function public.prevent_mural_content_tamper()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Sessão logada (staff moderando pelo console): só o status pode mudar.
  -- service_role (a postar-mural) tem auth.uid() nulo e passa direto.
  if auth.uid() is not null then
    if new.texto is distinct from old.texto then
      raise exception 'o texto do recado não se reescreve — dá pra ocultar, não pra trocar as palavras.';
    end if;
    if new.autor_nome is distinct from old.autor_nome then
      raise exception 'o nome de quem escreveu o recado não se troca.';
    end if;
    if new.user_id is distinct from old.user_id then
      raise exception 'o recado não muda de dono.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_mural_content_tamper on public.mural_notes;
create trigger trg_prevent_mural_content_tamper
  before update on public.mural_notes
  for each row execute function public.prevent_mural_content_tamper();

-- -----------------------------------------------------------------------------
-- (b) o cantinho fica no ar enquanto o plano estiver de pé
-- Mesma função da 0024, com `tier_slug is not null` na busca. O resto é idêntico.
-- -----------------------------------------------------------------------------
create or replace function public.perfil_publico(p_handle text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prof    public.profiles;
  v_tier    text;
  v_nome    text;
  v_recados jsonb;
begin
  select * into v_prof
    from public.profiles
   where lower(handle) = lower(btrim(coalesce(p_handle, '')))
     and perfil_publico = true
     and tier_slug is not null;   -- perk de assinante também na leitura
  if not found then
    return null;
  end if;

  select nome into v_tier from public.tiers where slug = v_prof.tier_slug;

  -- Nome de exibição: apelido, senão o PRIMEIRO nome (nunca o nome completo real).
  v_nome := nullif(btrim(v_prof.apelido), '');
  if v_nome is null then
    v_nome := split_part(btrim(coalesce(v_prof.full_name, '')), ' ', 1);
  end if;
  if v_nome is null or v_nome = '' then v_nome := 'alguém do Casa'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('texto', m.texto, 'created_at', m.created_at)
                            order by m.created_at desc), '[]'::jsonb)
    into v_recados
    from public.mural_notes m
   where m.user_id = v_prof.id and m.status = 'aprovado';

  return jsonb_build_object(
    'nome',         v_nome,
    'avatar_url',   v_prof.avatar_url,
    'tier_slug',    v_prof.tier_slug,
    'tier_nome',    v_tier,
    'membro_desde', v_prof.created_at,
    'cafe_metodo',  v_prof.cafe_metodo,
    'cafe_torra',   v_prof.cafe_torra,
    'cafe_leite',   v_prof.cafe_leite,
    'cafe_horario', v_prof.cafe_horario,
    'recados',      v_recados
  );
end;
$$;

revoke all on function public.perfil_publico(text) from public;
grant execute on function public.perfil_publico(text) to anon, authenticated;



-- ===== 0037_dicas_sem_travessao.sql =====

-- =============================================================================
-- 0037_dicas_sem_travessao.sql — as dicas das conquistas trocam o "—" por vírgula ✍️
--
-- O tom de voz da casa (ver CLAUDE.md › Tom de voz da marca) não usa travessão
-- em texto que o usuário vê: no lugar dele vai vírgula. Cinco das nove dicas
-- semeadas pela 0010 nasceram antes dessa regra e aparecem com o "—" no card
-- bloqueado da /conta/conquistas e no tooltip dos emblemas do painel da conta.
--
-- Só texto: nenhuma coluna, policy, função ou permissão muda aqui. As outras
-- quatro dicas da 0010 já estavam sem travessão e ficam como estão.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (é UPDATE por slug, com o texto final escrito à mão).
-- =============================================================================

update public.achievements
   set dica = 'faz teu primeiro pedido, aqui na loja ou lá no balcão.'
 where slug = 'primeira-xicara';

update public.achievements
   set dica = 'passa cinco manhãs com a gente, pedidos antes do meio-dia contam.'
 where slug = 'manha-de-sempre';

update public.achievements
   set dica = 'traz alguém novo pra sentar na nossa mesa, a gente marca no balcão.'
 where slug = 'mesa-comprida';

update public.achievements
   set dica = 'prova todos os doces da casa, a gente confirma no balcão.'
 where slug = 'que-seja-doce';

update public.achievements
   set dica = 'vem a quatro brunchs de domingo, a mesa te espera.'
 where slug = 'domingo-de-brunch';



-- ===== 0038_conquistas_do_cardapio.sql =====

-- =============================================================================
-- 0038_conquistas_do_cardapio.sql — 50 conquistas tiradas do cardápio ☕🥐🍰
--
-- As nove conquistas do seed (0003/0009) falavam da relação com a casa (primeira
-- compra, virou rotina, assinou tal plano). Estas 50 falam do CARDÁPIO: provar o
-- Hot Latte Matcha, comer um bolo e um cookie, dividir um Platter Brunch, passar
-- pelos três métodos de café. Uma por item ou combinação real do impresso, nas
-- 16 seções, na ordem do cardápio.
--
-- ATENÇÃO, ELAS SÓ DESBLOQUEIAM QUANDO A FRENTE DE CAIXA ENTRAR:
--   O `check_achievements` (0009) só avalia o que o banco enxerga, e de consumo
--   ele só enxerga a LOJA (`orders` + `order_items` de produto: vestuário,
--   acessórios, café em grão). O `/cardapio` é informativo, sem carrinho e sem
--   SKU por item, então "tomou um matcha" ainda não existe como dado.
--   O caminho já está definido: o PDV vai mandar o consumo por webhook (a
--   `pos_webhook_events` da 0004 e o `POS_WEBHOOK_SECRET` estão reservados pra
--   isso desde a Fase 3). Por isso os critérios aqui embaixo já vêm ESCRITOS no
--   formato que esse webhook vai alimentar, em vez de um `manual` genérico: no
--   dia D não se reescreve conquista nenhuma, só se ensina a função a ler três
--   tipos novos.
--   Por isso elas nascem DESLIGADAS (`ativo = false`): ficam guardadas no banco,
--   invisíveis no site, e o placar da /conta/conquistas segue "x/9" em vez de
--   virar "x/59" com 50 cadeados que nada abre. O front já filtra por
--   `ativo = true` (initConquistasPage) e o check_achievements também só avalia
--   conquista ativa, então enquanto estiverem desligadas elas não aparecem nem
--   desbloqueiam.
--
--   PRA ACENDER, no dia em que a frente de caixa começar a mandar consumo:
--     update public.achievements set ativo = true where slug like 'cardapio-%';
--
-- Só conteúdo: nenhuma coluna, policy, função ou permissão muda aqui. O front
-- também não precisa de nada, os cards se montam da tabela (a única mudança lá é
-- cosmética: `ICONES_CONQUISTA` ganhou os ícones do cardápio, senão os 50 sairiam
-- todos com o troféu genérico).
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (`on conflict (slug) do update`).
-- =============================================================================

insert into public.achievements (slug, nome, descricao, icone, ordem, ativo) values
  -- ---- Clássicos do Casa -----------------------------------------------------
  ('cardapio-pao-de-queijo',      'Fornada da Hora',      'quentinho, direto do forno pra tua mão.',                   'sandwich',   10, false),
  ('cardapio-brioche-na-chapa',   'Brioche na Chapa',     'manteiga, chapa e queijo derretendo.',                      'sandwich',   11, false),
  ('cardapio-empanada',           'Empanada Argentina',   'um pedaço da Argentina no nosso balcão.',                   'sandwich',   12, false),

  -- ---- Brunch ----------------------------------------------------------------
  ('cardapio-crepioca',           'Crepioca Completa',    'três recheios, escolhidos do teu jeito.',                   'egg-fried',  13, false),
  ('cardapio-tuskany',            'Manhã Toscana',        'búfala e tomate assado, de manhã cedo.',                    'egg-fried',  14, false),
  ('cardapio-avo-brunch',         'Avo Brunch',           'avocado e bacon, o clássico do brunch.',                    'egg-fried',  15, false),
  ('cardapio-pancakes',           'Panqueca com Mel',     'mel escorrendo na panqueca americana.',                     'egg-fried',  16, false),
  ('cardapio-platter',            'Mesa pra Dividir',     'a bandeja que só faz sentido em dupla.',                    'heart',      17, false),

  -- ---- Bagel -----------------------------------------------------------------
  ('cardapio-bagel-classico',     'Bagel de Sempre',      'o bagel tostado de todo dia.',                              'donut',      18, false),
  ('cardapio-bagel-salmon',       'Bagel de Salmão',      'gravlax com picles de cebola roxa.',                        'donut',      19, false),
  ('cardapio-bagel-american',     'Bagel Americano',      'ovos cremosos e bacon no pão americano.',                   'donut',      20, false),

  -- ---- Croissant -------------------------------------------------------------
  ('cardapio-croissant-classico', 'Manteiga de Verdade',  'a folhada feita com manteiga de verdade.',                  'croissant',  21, false),
  ('cardapio-croissant-parma',    'Parma no Croissant',   'parma, brie e rúcula na folhada.',                          'croissant',  22, false),
  ('cardapio-croissant-salmon',   'Croissant de Salmão',  'gravlax e cream cheese dentro do croissant.',               'croissant',  23, false),

  -- ---- Sanduíches ------------------------------------------------------------
  ('cardapio-croque-madame',      'Croque Madame',        'bechamel, presunto e ovo frito por cima.',                  'sandwich',   24, false),
  ('cardapio-carne-de-panela',    'Carne de Panela',      'carne de panela, gorgonzola e aioli.',                      'sandwich',   25, false),
  ('cardapio-parma-pesto',        'Parma com Pesto',      'parma, búfala e pesto na baguete.',                         'sandwich',   26, false),

  -- ---- Toasts ----------------------------------------------------------------
  ('cardapio-avocado-morning',    'Avocado Morning',      'o verde que abre bem o dia.',                               'wheat',      27, false),
  ('cardapio-caprese',            'Caprese na Chapa',     'búfala, tomate assado e pesto no levain.',                  'wheat',      28, false),
  ('cardapio-funghi-eggs',        'Funghi e Eggs',        'cogumelo salteado com ovos cremosos.',                      'wheat',      29, false),
  ('cardapio-fig-parma',          'Figo e Parma',         'o doce do figo com o salgado da parma.',                    'wheat',      30, false),

  -- ---- Confeitaria -----------------------------------------------------------
  ('cardapio-bolo-gisele',        'Bolo Gisele',          'bolo de cenoura com brigadeiro quentinho.',                 'cake-slice', 31, false),
  ('cardapio-cheesecolab',        'Cheesecolab',          'a torta basca que some rápido.',                            'cake-slice', 32, false),
  ('cardapio-cookie',             'Cookie da Casa',       'o cookie que muda de sabor conforme o dia.',                'cookie',     33, false),
  ('cardapio-brownie-sorvete',    'Brownie com Sorvete',  'chocolatudo, com a bola derretendo em cima.',               'cake-slice', 34, false),
  ('cardapio-lab-rolls',          'Lab Rolls',            'canela e cobertura, feitas aqui no Casa.',                  'cake-slice', 35, false),
  ('cardapio-bolo-e-cookie',      'Doce em Dobro',        'porque escolher um só é difícil.',                          'star',       36, false),

  -- ---- Métodos ---------------------------------------------------------------
  ('cardapio-prensa-francesa',    'Prensa Francesa',      'o café que pede tempo pra ficar pronto.',                   'coffee',     37, false),
  ('cardapio-hario-v60',          'Hario V60',            'o filtro que deixa o grão falar.',                          'coffee',     38, false),
  ('cardapio-tres-metodos',       'Passa Café',           'prensa, V60 e drip, os três da casa.',                      'award',      39, false),

  -- ---- Puristas --------------------------------------------------------------
  ('cardapio-espresso',           'Espresso Puro',        'curto, intenso, sem nada por cima.',                        'coffee',     40, false),
  ('cardapio-carioca',            'Carioca de Balcão',    'setenta mililitros mais leves.',                            'coffee',     41, false),

  -- ---- Elaborados ------------------------------------------------------------
  ('cardapio-latte',              'Latte de Sempre',      'espresso e leite vaporizado, sem mistério.',                'milk',       42, false),
  ('cardapio-cappuccino',         'Cappuccino Italiano',  'no ristretto, do jeito de lá.',                             'milk',       43, false),
  ('cardapio-caramel-macchiato',  'Caramel Macchiato',    'caramelo no fundo, leite por cima.',                        'milk',       44, false),
  ('cardapio-mocha',              'Mocha',                'café e chocolate 50%, juntos na xícara.',                   'milk',       45, false),
  ('cardapio-choco-quente',       'Chocolate Cremoso',    'o cobertor de caneca dos dias frios.',                      'milk',       46, false),

  -- ---- Cafés gelados ---------------------------------------------------------
  ('cardapio-iced-black',         'Iced Black',           'espresso, água e gelo, nada mais.',                         'snowflake',  47, false),
  ('cardapio-iced-latte',         'Iced Latte',           'o latte que pede dia de calor.',                            'snowflake',  48, false),
  ('cardapio-coffee-tonic',       'Coffee Tonic',         'tônica, laranja e espresso, borbulhando.',                  'snowflake',  49, false),
  ('cardapio-orange-coffee',      'Café com Laranja',     'a dupla que ninguém espera e dá certo.',                    'citrus',     50, false),

  -- ---- Matcha ----------------------------------------------------------------
  ('cardapio-hot-latte-matcha',   'Hot Latte Matcha',     'matcha Namu com leite vaporizado.',                         'leaf',       51, false),
  ('cardapio-iced-latte-matcha',  'Matcha Gelado',        'o verde da casa, agora com gelo.',                          'leaf',       52, false),
  ('cardapio-strawberry-matcha',  'Matcha com Morango',   'purê de morango no fundo do copo.',                         'leaf',       53, false),
  ('cardapio-tour-do-matcha',     'Tour do Matcha',       'quatro matchas diferentes, um de cada vez.',                'award',      54, false),

  -- ---- Chás ------------------------------------------------------------------
  ('cardapio-blend-tea',          'Chá Quentinho',        'o blend de chá que muda com a estação.',                    'glass-water',55, false),
  ('cardapio-iced-tea',           'Iced Tea da Casa',     'hibisco ou capim limão, com limão e gelo.',                 'glass-water',56, false),

  -- ---- Juices e sodas --------------------------------------------------------
  ('cardapio-suco-verde',         'Suco Verde',           'couve, abacaxi, limão, maracujá e gengibre.',               'citrus',     57, false),
  ('cardapio-suco-do-dia',        'Suco do Dia',          'a fruta que chegou boa na feira.',                          'citrus',     58, false),

  -- ---- Alcoólicos ------------------------------------------------------------
  ('cardapio-taca-de-vinho',      'Taça no Fim da Tarde', 'quando o café dá lugar à taça.',                            'wine',       59, false)
on conflict (slug) do update set
  nome      = excluded.nome,
  descricao = excluded.descricao,
  icone     = excluded.icone,
  ordem     = excluded.ordem;
-- Nota: o `ativo` de propósito NÃO entra no update acima. Rodar este arquivo de
-- novo depois de acender as 50 não as apagaria da tela sem querer.

-- -----------------------------------------------------------------------------
-- CRITÉRIOS: já escritos no formato que o PDV vai alimentar.
--
-- Hoje o `check_achievements` (0009) não conhece estes três tipos, e o `case`
-- dele manda tipo desconhecido pro mesmo lugar que manda `manual`: não
-- desbloqueia, não estoura, não atrapalha a avaliação das outras conquistas.
-- Ou seja, aplicar isto agora é seguro e não muda comportamento nenhum.
--
-- Quando a frente de caixa começar a mandar o consumo, o trabalho vira: gravar
-- o que veio (a `pos_webhook_events` da 0004 já está reservada pro evento cru) e
-- ensinar o `check_achievements` a ler estes três tipos. Nenhuma destas 50
-- linhas precisa ser reescrita.
--
--   {"type":"menu_item","itens":[…]}            → consumiu QUALQUER um da lista.
--   {"type":"menu_item_distintos","itens":[…],
--    "min":N}                                   → consumiu N itens DIFERENTES da lista.
--   {"type":"menu_item_combo","grupos":[[…],[…]],
--    "janela":"mesma_visita"}                   → um item de CADA grupo, na mesma visita.
--
-- Os `itens` usam o slug do nome do item no cardápio, pela mesma regra do
-- `slugify` que o `cardapio_favoritos` (0027) já usa: sem acento, minúsculo,
-- espaço vira hífen. Quatro nomes se repetem entre seções ("Clássico" no bagel e
-- no croissant, "Presunto + queijo" no croissant e no sanduíche, "Carne de
-- panela" no sanduíche e nos adicionais), então esses vão qualificados
-- (`bagel-classico`, `croissant-classico`, `sanduiche-carne-de-panela`). Quando
-- o PDV entrar, vai precisar de um de-para entre o código dele e estes slugs.
-- -----------------------------------------------------------------------------
update public.achievements set criterios = '{"type":"menu_item","itens":["pao-de-queijo"]}'::jsonb
 where slug = 'cardapio-pao-de-queijo';
update public.achievements set criterios = '{"type":"menu_item","itens":["misto-quente","queijo-quente"]}'::jsonb
 where slug = 'cardapio-brioche-na-chapa';
update public.achievements set criterios = '{"type":"menu_item","itens":["empanadas"]}'::jsonb
 where slug = 'cardapio-empanada';
update public.achievements set criterios = '{"type":"menu_item","itens":["crepioca"]}'::jsonb
 where slug = 'cardapio-crepioca';
update public.achievements set criterios = '{"type":"menu_item","itens":["tuskany-morning"]}'::jsonb
 where slug = 'cardapio-tuskany';
update public.achievements set criterios = '{"type":"menu_item","itens":["avo-brunch"]}'::jsonb
 where slug = 'cardapio-avo-brunch';
update public.achievements set criterios = '{"type":"menu_item","itens":["sunny-honey-pancakes"]}'::jsonb
 where slug = 'cardapio-pancakes';
update public.achievements set criterios = '{"type":"menu_item","itens":["platter-brunch"]}'::jsonb
 where slug = 'cardapio-platter';
update public.achievements set criterios = '{"type":"menu_item","itens":["bagel-classico"]}'::jsonb
 where slug = 'cardapio-bagel-classico';
update public.achievements set criterios = '{"type":"menu_item","itens":["salmon-bagel"]}'::jsonb
 where slug = 'cardapio-bagel-salmon';
update public.achievements set criterios = '{"type":"menu_item","itens":["american-bagel"]}'::jsonb
 where slug = 'cardapio-bagel-american';
update public.achievements set criterios = '{"type":"menu_item","itens":["croissant-classico"]}'::jsonb
 where slug = 'cardapio-croissant-classico';
update public.achievements set criterios = '{"type":"menu_item","itens":["parma-brie-rucula"]}'::jsonb
 where slug = 'cardapio-croissant-parma';
update public.achievements set criterios = '{"type":"menu_item","itens":["salmon-croissant"]}'::jsonb
 where slug = 'cardapio-croissant-salmon';
update public.achievements set criterios = '{"type":"menu_item","itens":["croque-madame"]}'::jsonb
 where slug = 'cardapio-croque-madame';
update public.achievements set criterios = '{"type":"menu_item","itens":["sanduiche-carne-de-panela"]}'::jsonb
 where slug = 'cardapio-carne-de-panela';
update public.achievements set criterios = '{"type":"menu_item","itens":["parma-pesto"]}'::jsonb
 where slug = 'cardapio-parma-pesto';
update public.achievements set criterios = '{"type":"menu_item","itens":["avocado-morning"]}'::jsonb
 where slug = 'cardapio-avocado-morning';
update public.achievements set criterios = '{"type":"menu_item","itens":["caprese"]}'::jsonb
 where slug = 'cardapio-caprese';
update public.achievements set criterios = '{"type":"menu_item","itens":["funghi-eggs"]}'::jsonb
 where slug = 'cardapio-funghi-eggs';
update public.achievements set criterios = '{"type":"menu_item","itens":["fig-parma"]}'::jsonb
 where slug = 'cardapio-fig-parma';
update public.achievements set criterios = '{"type":"menu_item","itens":["bolo-gisele"]}'::jsonb
 where slug = 'cardapio-bolo-gisele';
update public.achievements set criterios = '{"type":"menu_item","itens":["cheesecolab"]}'::jsonb
 where slug = 'cardapio-cheesecolab';
update public.achievements set criterios = '{"type":"menu_item","itens":["cookie-gourmet"]}'::jsonb
 where slug = 'cardapio-cookie';
update public.achievements set criterios = '{"type":"menu_item_combo","grupos":[["brownie"],["sorvete"]],"janela":"mesma_visita"}'::jsonb
 where slug = 'cardapio-brownie-sorvete';
update public.achievements set criterios = '{"type":"menu_item","itens":["lab-rolls"]}'::jsonb
 where slug = 'cardapio-lab-rolls';
update public.achievements set criterios = '{"type":"menu_item_combo","grupos":[["bolo-gisele","petit-lab","cakelab"],["cookie-gourmet"]],"janela":"mesma_visita"}'::jsonb
 where slug = 'cardapio-bolo-e-cookie';
update public.achievements set criterios = '{"type":"menu_item","itens":["prensa-francesa"]}'::jsonb
 where slug = 'cardapio-prensa-francesa';
update public.achievements set criterios = '{"type":"menu_item","itens":["hario-v60"]}'::jsonb
 where slug = 'cardapio-hario-v60';
update public.achievements set criterios = '{"type":"menu_item_distintos","itens":["prensa-francesa","hario-v60","drip-coffee-bunn"],"min":3}'::jsonb
 where slug = 'cardapio-tres-metodos';
update public.achievements set criterios = '{"type":"menu_item","itens":["espresso"]}'::jsonb
 where slug = 'cardapio-espresso';
update public.achievements set criterios = '{"type":"menu_item","itens":["carioca"]}'::jsonb
 where slug = 'cardapio-carioca';
update public.achievements set criterios = '{"type":"menu_item","itens":["latte"]}'::jsonb
 where slug = 'cardapio-latte';
update public.achievements set criterios = '{"type":"menu_item","itens":["cappuccino-italiano"]}'::jsonb
 where slug = 'cardapio-cappuccino';
update public.achievements set criterios = '{"type":"menu_item","itens":["caramel-macchiato"]}'::jsonb
 where slug = 'cardapio-caramel-macchiato';
update public.achievements set criterios = '{"type":"menu_item","itens":["mocha"]}'::jsonb
 where slug = 'cardapio-mocha';
update public.achievements set criterios = '{"type":"menu_item","itens":["choco-quente"]}'::jsonb
 where slug = 'cardapio-choco-quente';
update public.achievements set criterios = '{"type":"menu_item","itens":["iced-black"]}'::jsonb
 where slug = 'cardapio-iced-black';
update public.achievements set criterios = '{"type":"menu_item","itens":["iced-latte"]}'::jsonb
 where slug = 'cardapio-iced-latte';
update public.achievements set criterios = '{"type":"menu_item","itens":["coffee-tonic"]}'::jsonb
 where slug = 'cardapio-coffee-tonic';
update public.achievements set criterios = '{"type":"menu_item","itens":["orange-coffee"]}'::jsonb
 where slug = 'cardapio-orange-coffee';
update public.achievements set criterios = '{"type":"menu_item","itens":["hot-latte-matcha"]}'::jsonb
 where slug = 'cardapio-hot-latte-matcha';
update public.achievements set criterios = '{"type":"menu_item","itens":["iced-latte-matcha"]}'::jsonb
 where slug = 'cardapio-iced-latte-matcha';
update public.achievements set criterios = '{"type":"menu_item","itens":["strawberry-matcha"]}'::jsonb
 where slug = 'cardapio-strawberry-matcha';
update public.achievements set criterios = '{"type":"menu_item_distintos","itens":["hot-latte-matcha","hot-vanilla-matcha","iced-latte-matcha","vanilla-iced-matcha","caramel-iced-matcha","strawberry-matcha","passion-matcha","orange-matcha"],"min":4}'::jsonb
 where slug = 'cardapio-tour-do-matcha';
update public.achievements set criterios = '{"type":"menu_item","itens":["blend-tea"]}'::jsonb
 where slug = 'cardapio-blend-tea';
update public.achievements set criterios = '{"type":"menu_item","itens":["hibisco-iced-tea","capim-limao-iced-tea"]}'::jsonb
 where slug = 'cardapio-iced-tea';
update public.achievements set criterios = '{"type":"menu_item","itens":["suco-verde"]}'::jsonb
 where slug = 'cardapio-suco-verde';
update public.achievements set criterios = '{"type":"menu_item","itens":["suco-natural-ou-integral"]}'::jsonb
 where slug = 'cardapio-suco-do-dia';
update public.achievements set criterios = '{"type":"menu_item","itens":["vinho-taca-ou-garrafa"]}'::jsonb
 where slug = 'cardapio-taca-de-vinho';

-- -----------------------------------------------------------------------------
-- Dicas ("como desbloquear"), no tom da casa: o que pedir no balcão. Aparecem no
-- cartão bloqueado da /conta/conquistas e no tooltip dos emblemas do painel.
-- -----------------------------------------------------------------------------
update public.achievements set dica = 'pede um pão de queijo, ele sai quentinho do forno.'                    where slug = 'cardapio-pao-de-queijo';
update public.achievements set dica = 'pede um misto quente ou um queijo quente, os dois valem.'               where slug = 'cardapio-brioche-na-chapa';
update public.achievements set dica = 'pede uma empanada, ela vem recheada de carne, azeitona e ovo.'         where slug = 'cardapio-empanada';
update public.achievements set dica = 'pede uma crepioca e escolhe os três recheios.'                          where slug = 'cardapio-crepioca';
update public.achievements set dica = 'pede o Tuskany Morning, com búfala e tomate assado.'                    where slug = 'cardapio-tuskany';
update public.achievements set dica = 'pede o Avo Brunch, com creme de avocado e bacon.'                       where slug = 'cardapio-avo-brunch';
update public.achievements set dica = 'pede as Sunny Honey Pancakes, com mel e manteiga.'                      where slug = 'cardapio-pancakes';
update public.achievements set dica = 'pede o Platter Brunch, ele é feito pra dividir.'                        where slug = 'cardapio-platter';
update public.achievements set dica = 'pede o bagel clássico, com cream cheese ou manteiga.'                   where slug = 'cardapio-bagel-classico';
update public.achievements set dica = 'pede o Salmon Bagel, com gravlax e picles de cebola roxa.'              where slug = 'cardapio-bagel-salmon';
update public.achievements set dica = 'pede o American Bagel, com ovos cremosos e bacon.'                      where slug = 'cardapio-bagel-american';
update public.achievements set dica = 'pede o croissant clássico, com cream cheese, manteiga ou geleia.'       where slug = 'cardapio-croissant-classico';
update public.achievements set dica = 'pede o croissant de parma, brie e rúcula.'                              where slug = 'cardapio-croissant-parma';
update public.achievements set dica = 'pede o Salmon Croissant, com cream cheese e gravlax.'                   where slug = 'cardapio-croissant-salmon';
update public.achievements set dica = 'pede o croque madame, com bechamel e ovo frito.'                        where slug = 'cardapio-croque-madame';
update public.achievements set dica = 'pede o sanduíche de carne de panela, com gorgonzola e aioli.'           where slug = 'cardapio-carne-de-panela';
update public.achievements set dica = 'pede o sanduíche de parma, búfala e pesto.'                             where slug = 'cardapio-parma-pesto';
update public.achievements set dica = 'pede o Avocado Morning, com creme de avocado e ovos cremosos.'          where slug = 'cardapio-avocado-morning';
update public.achievements set dica = 'pede o toast caprese, com búfala, tomate assado e pesto.'               where slug = 'cardapio-caprese';
update public.achievements set dica = 'pede o Funghi & Eggs, com cogumelo salteado e cebolete.'                where slug = 'cardapio-funghi-eggs';
update public.achievements set dica = 'pede o Fig & Parma, com brie, figo e molho especial.'                   where slug = 'cardapio-fig-parma';
update public.achievements set dica = 'pede o Bolo Gisele, ele vem com brigadeiro de panela quentinho.'        where slug = 'cardapio-bolo-gisele';
update public.achievements set dica = 'pede o Cheesecolab, de frutas vermelhas ou de doce de leite.'           where slug = 'cardapio-cheesecolab';
update public.achievements set dica = 'pede um cookie gourmet e pergunta o sabor do dia.'                      where slug = 'cardapio-cookie';
update public.achievements set dica = 'pede o brownie e soma o adicional de sorvete.'                          where slug = 'cardapio-brownie-sorvete';
update public.achievements set dica = 'pede o Lab Rolls e escolhe a cobertura do dia.'                         where slug = 'cardapio-lab-rolls';
update public.achievements set dica = 'pede um bolo e um cookie na mesma visita, a gente anota no balcão.'     where slug = 'cardapio-bolo-e-cookie';
update public.achievements set dica = 'pede o café da prensa francesa, de 300ml ou 500ml.'                     where slug = 'cardapio-prensa-francesa';
update public.achievements set dica = 'pede o café passado no Hario V60.'                                      where slug = 'cardapio-hario-v60';
update public.achievements set dica = 'passa pelos três: prensa francesa, V60 e drip coffee.'                  where slug = 'cardapio-tres-metodos';
update public.achievements set dica = 'pede um espresso curto, do jeito purista.'                              where slug = 'cardapio-espresso';
update public.achievements set dica = 'pede um carioca, os 70ml mais leves do balcão.'                         where slug = 'cardapio-carioca';
update public.achievements set dica = 'pede um latte, com o leite que tu preferir.'                            where slug = 'cardapio-latte';
update public.achievements set dica = 'pede o cappuccino italiano, feito no ristretto.'                        where slug = 'cardapio-cappuccino';
update public.achievements set dica = 'pede o caramel macchiato.'                                              where slug = 'cardapio-caramel-macchiato';
update public.achievements set dica = 'pede o mocha, com calda de chocolate 50%.'                              where slug = 'cardapio-mocha';
update public.achievements set dica = 'pede um choco quente, o cremoso da casa.'                               where slug = 'cardapio-choco-quente';
update public.achievements set dica = 'pede um iced black em dia de calor.'                                    where slug = 'cardapio-iced-black';
update public.achievements set dica = 'pede um iced latte, com o leite que tu preferir.'                       where slug = 'cardapio-iced-latte';
update public.achievements set dica = 'pede o coffee tonic, com água tônica e laranja.'                        where slug = 'cardapio-coffee-tonic';
update public.achievements set dica = 'pede o orange coffee, espresso com suco de laranja.'                    where slug = 'cardapio-orange-coffee';
update public.achievements set dica = 'pede o hot latte matcha, matcha Namu com leite vaporizado.'             where slug = 'cardapio-hot-latte-matcha';
update public.achievements set dica = 'pede o iced latte matcha, com gelo.'                                    where slug = 'cardapio-iced-latte-matcha';
update public.achievements set dica = 'pede o strawberry matcha, com purê de morango.'                         where slug = 'cardapio-strawberry-matcha';
update public.achievements set dica = 'prova quatro matchas diferentes da nossa carta.'                        where slug = 'cardapio-tour-do-matcha';
update public.achievements set dica = 'pede o blend tea quentinho e consulta as opções do dia.'                where slug = 'cardapio-blend-tea';
update public.achievements set dica = 'pede o iced tea, de hibisco ou de capim limão.'                         where slug = 'cardapio-iced-tea';
update public.achievements set dica = 'pede o suco verde, com couve, abacaxi, limão, maracujá e gengibre.'     where slug = 'cardapio-suco-verde';
update public.achievements set dica = 'pede o suco natural do dia e pergunta qual é a fruta.'                  where slug = 'cardapio-suco-do-dia';
update public.achievements set dica = 'fica pra uma taça de vinho no fim da tarde.'                            where slug = 'cardapio-taca-de-vinho';



-- ===== 0039_slug_carne_de_panela.sql =====

-- =============================================================================
-- 0039_slug_carne_de_panela.sql — acerta UM slug de item nos critérios da 0038
--
-- A 0038 escreveu o critério da conquista `cardapio-carne-de-panela` como
-- `sanduiche-carne-de-panela`, no singular. O front deriva esse slug sozinho, a
-- partir do título da seção do cardápio ("Sanduíches"), então o que ele produz
-- é `sanduiches-carne-de-panela`. Dois nomes pro mesmo prato é de-para errado no
-- dia em que a frente de caixa entrar: a conquista simplesmente nunca abriria.
--
-- POR QUE existe o sufixo: o slug do item sai do NOME, e quatro nomes se repetem
-- entre seções do impresso ("Clássico" no bagel e no croissant, "Presunto +
-- queijo" no croissant e no sanduíche, "Carne de panela" no sanduíche e nos
-- adicionais). Esses vão qualificados pelo título da seção, tanto aqui quanto no
-- `cardapio_favoritos` (0027) — que é de onde veio o problema: o segundo item de
-- cada dupla colidia com o primeiro e ficava sem o coração de favoritar.
--
-- Só conteúdo, e só uma linha: nenhuma coluna, policy, função ou permissão muda.
-- As 50 conquistas do cardápio seguem DESLIGADAS (`ativo = false`), como a 0038
-- as criou — este arquivo não acende nenhuma.
--
-- APLICAR: rodar no SQL Editor do Supabase, uma vez. Idempotente (o `where`
-- ignora a linha que já está certa, então reaplicar não faz nada).
-- =============================================================================

update public.achievements
   set criterios = '{"type":"menu_item","itens":["sanduiches-carne-de-panela"]}'::jsonb
 where slug = 'cardapio-carne-de-panela'
   and criterios is distinct from '{"type":"menu_item","itens":["sanduiches-carne-de-panela"]}'::jsonb;



-- ===== 0040_leads_evento.sql =====

-- =============================================================================
-- 0040_leads_evento.sql — "faz teu evento aqui" (pedidos de festa/encontro) 🎉
--
-- O Casa se define como café-casa de ENCONTROS, e quem quer alugar o espaço pra
-- um aniversário, um workshop ou uma reunião só tinha um caminho: descobrir o
-- telefone no rodapé e começar a conversa do zero, sem dizer quando, pra quantos
-- nem do quê. A página /eventos coleta isso num formulário e leva a pessoa pro
-- WhatsApp da casa com a mensagem já escrita.
--
-- POR QUE O PEDIDO TAMBÉM FICA GUARDADO AQUI:
--   O WhatsApp é o canal, não o arquivo. Se a pessoa preenche e não aperta
--   enviar, se o link não abre no aparelho dela, ou se a conversa se perde em
--   trinta mensagens novas, o pedido evapora. Gravar ANTES de mandar pro
--   WhatsApp faz o lead sobreviver ao canal: o console mostra todos, do mais
--   recente pro mais antigo, com um botão de "já falei com essa pessoa".
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Tabela DENY-BY-DEFAULT: RLS ligada e NENHUMA policy. O client não lê nem
--     escreve direto. Quem escreve é a `registrar_lead_evento` (SECURITY
--     DEFINER, aberta a anon porque quem pede evento normalmente nem tem conta);
--     quem lê é o console, pela `admin_leads_evento`.
--     É diferente da 0031, que nasceu com policy de INSERT pro client e precisou
--     da 0034 pra tirar. Aqui já nasce pela porta certa.
--   • O dado É pessoal (nome + telefone + o que a pessoa quer comemorar), então
--     não entra na turma dos "benignos" (favoritos, desejos) que o client
--     escreve direto. Nada de INSERT do lado de fora.
--   • Anti-flood de 30s pelo mesmo contato, no corpo da função: endpoint público
--     de escrita sem freio é convite pra encher a tabela. Repetição dentro da
--     janela responde `ok:true` e não grava, que é o mesmo que a pessoa vê ao
--     apertar duas vezes sem querer.
--   • `user_id` guarda quem estava logado, se estava. É opcional de propósito:
--     exigir conta pra pedir um orçamento afastaria justamente quem ainda não é
--     de casa.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE).
-- =============================================================================

create table if not exists public.leads_evento (
  id              uuid primary key default gen_random_uuid(),
  nome            text not null check (char_length(nome) between 2 and 80),
  -- O telefone chega formatado pela máscara do site ((51) 99999-9999). Guardar o
  -- texto como a pessoa vê é a mesma escolha do profiles.telefone.
  contato         text not null check (char_length(contato) between 8 and 40),
  email           text check (
                    email is null
                    or (char_length(email) between 6 and 160
                        and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
                  ),
  -- Tipo é texto livre limitado, não CHECK com lista: a casa vai inventar tipo
  -- de evento novo antes de a gente escrever outra migration, e o console escapa
  -- tudo o que mostra.
  tipo            text not null check (char_length(tipo) between 2 and 40),
  data_pretendida date,
  pessoas         int check (pessoas is null or pessoas between 1 and 500),
  mensagem        text check (mensagem is null or char_length(mensagem) <= 600),
  origem          text check (origem is null or char_length(origem) <= 120),
  status          text not null default 'novo' check (status in ('novo', 'atendido', 'arquivado')),
  user_id         uuid references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  atendido_em     timestamptz,
  atendido_por    uuid references auth.users (id) on delete set null
);

create index if not exists idx_leads_evento_created on public.leads_evento (created_at desc);
create index if not exists idx_leads_evento_status on public.leads_evento (status, created_at desc);

alter table public.leads_evento enable row level security;

-- Nenhuma policy, de propósito: RLS ligada sem policy = ninguém passa pelo
-- PostgREST, nem anon nem logado. As duas portas são as funções abaixo.

-- -----------------------------------------------------------------------------
-- registrar_lead_evento(...) → jsonb {ok:true} | {ok:false, erro}
-- Aberta a anon: quem quer fazer um evento aqui raramente já tem conta.
-- O `ok:false` só acontece em campo malformado, que quem digitou já sabe.
-- -----------------------------------------------------------------------------
create or replace function public.registrar_lead_evento(
  p_nome      text,
  p_contato   text,
  p_tipo      text,
  p_email     text default null,
  p_data      date default null,
  p_pessoas   int default null,
  p_mensagem  text default null,
  p_origem    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome     text := btrim(coalesce(p_nome, ''));
  v_contato  text := btrim(coalesce(p_contato, ''));
  v_tipo     text := btrim(coalesce(p_tipo, ''));
  v_email    text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_mensagem text := nullif(btrim(coalesce(p_mensagem, '')), '');
  v_origem   text := nullif(btrim(coalesce(p_origem, '')), '');
  v_id       uuid;
begin
  if char_length(v_nome) not between 2 and 80 then
    return jsonb_build_object('ok', false, 'erro', 'falta teu nome');
  end if;

  -- Precisa de dígito suficiente pra ser telefone; a máscara do site já entrega
  -- formatado, mas quem chama a função por fora não passa por ela.
  if char_length(v_contato) not between 8 and 40
     or char_length(regexp_replace(v_contato, '[^0-9]', '', 'g')) < 10 then
    return jsonb_build_object('ok', false, 'erro', 'esse telefone não parece completo');
  end if;

  if char_length(v_tipo) not between 2 and 40 then
    return jsonb_build_object('ok', false, 'erro', 'conta pra gente que tipo de evento é');
  end if;

  if v_email is not null
     and (char_length(v_email) not between 6 and 160
          or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then
    return jsonb_build_object('ok', false, 'erro', 'esse e-mail não parece completo');
  end if;

  if p_pessoas is not null and p_pessoas not between 1 and 500 then
    return jsonb_build_object('ok', false, 'erro', 'quantas pessoas, mais ou menos?');
  end if;

  if v_mensagem is not null then v_mensagem := left(v_mensagem, 600); end if;
  if v_origem   is not null then v_origem   := left(v_origem, 120);   end if;

  -- Anti-flood: mesmo contato de novo dentro de 30s não vira linha nova. A
  -- resposta é a mesma, porque pra quem está do outro lado é a mesma coisa
  -- (o pedido já entrou).
  if exists (
    select 1 from public.leads_evento
     where contato = v_contato
       and created_at > now() - interval '30 seconds'
  ) then
    return jsonb_build_object('ok', true);
  end if;

  insert into public.leads_evento (nome, contato, email, tipo, data_pretendida, pessoas, mensagem, origem, user_id)
  values (v_nome, v_contato, v_email, v_tipo, p_data, p_pessoas, v_mensagem, v_origem, auth.uid())
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

revoke all on function public.registrar_lead_evento(text, text, text, text, date, int, text, text) from public;
grant execute on function public.registrar_lead_evento(text, text, text, text, date, int, text, text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- admin_leads_evento(busca, status, limite) → a fila de pedidos de evento.
-- Mesma porta dos outros relatórios de interesse (favoritos, desejos, lista de
-- espera): 'relatorios'. Não precisou de permissão nova, e ainda bem — o
-- whitelist de permissões é fechado por CHECK na 0017, então permissão nova
-- pediria outra migration só pra isso.
-- -----------------------------------------------------------------------------
create or replace function public.admin_leads_evento(
  p_busca  text default null,
  p_status text default null,
  p_limite int default 300
)
returns table (
  id              uuid,
  nome            text,
  contato         text,
  email           text,
  tipo            text,
  data_pretendida date,
  pessoas         int,
  mensagem        text,
  origem          text,
  status          text,
  created_at      timestamptz,
  atendido_em     timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra ver os pedidos de evento';
  end if;

  return query
    select l.id, l.nome, l.contato, l.email, l.tipo, l.data_pretendida, l.pessoas,
           l.mensagem, l.origem, l.status, l.created_at, l.atendido_em
      from public.leads_evento l
     where (p_status is null or p_status = '' or l.status = p_status)
       and (
         v_busca is null
         or l.nome ilike '%' || v_busca || '%'
         or l.contato ilike '%' || v_busca || '%'
         or coalesce(l.email, '') ilike '%' || v_busca || '%'
         or l.tipo ilike '%' || v_busca || '%'
       )
     order by l.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 2000));
end;
$$;

revoke all on function public.admin_leads_evento(text, text, int) from public, anon;
grant execute on function public.admin_leads_evento(text, text, int) to authenticated;

-- -----------------------------------------------------------------------------
-- admin_lead_evento_status(id, status) → marca "já falei" / "arquivado" / volta
-- pra "novo". Uma lista de pedidos sem onde riscar o que já foi atendido vira
-- uma pilha que só cresce.
-- -----------------------------------------------------------------------------
create or replace function public.admin_lead_evento_status(p_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_status text := btrim(coalesce(p_status, ''));
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra mexer nos pedidos de evento';
  end if;

  if v_status not in ('novo', 'atendido', 'arquivado') then
    raise exception 'status inválido';
  end if;

  update public.leads_evento
     set status       = v_status,
         atendido_em  = case when v_status = 'novo' then null else now() end,
         atendido_por = case when v_status = 'novo' then null else v_uid end
   where id = p_id;

  if not found then
    raise exception 'pedido não encontrado';
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'lead_evento_status', 'leads_evento', p_id::text,
          jsonb_build_object('status', v_status));

  return jsonb_build_object('ok', true, 'status', v_status);
end;
$$;

revoke all on function public.admin_lead_evento_status(uuid, text) from public, anon;
grant execute on function public.admin_lead_evento_status(uuid, text) to authenticated;



-- ===== 0041_admin_presentes.sql =====

-- =============================================================================
-- 0041_admin_presentes.sql — a casa enxerga os presentes vendidos 🎁
--
-- A `gift_select_own` (0019) deixa ler só quem é parte do presente: o comprador
-- e quem resgatou. Isso está certo pro site, mas deixava a CASA cega: ninguém
-- da equipe conseguia responder "quantos presentes foram vendidos esse mês?"
-- nem "esse código aqui é válido?" sem abrir o SQL Editor.
--
-- QUAL PERMISSÃO, E POR QUÊ 'resgates':
--   O código do presente é um título ao portador — quem tem o texto resgata um
--   mês de plano. Então isto não podia cair na permissão mais larga do console.
--   'resgates' é quem já entrega recompensa em mãos e dá baixa nela: mesmo nível
--   de confiança, mesma natureza de trabalho, e nenhuma permissão nova (o
--   whitelist do 0017 é fechado por CHECK, criar uma pediria outra migration).
--
-- O QUE NÃO SAI DAQUI:
--   A `mensagem` (o bilhete que o comprador escreveu pra quem ganha) NÃO entra
--   no retorno. É recado de uma pessoa pra outra, não tem uso operacional
--   nenhum, e ler correspondência alheia não vira função de balcão.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (CREATE OR REPLACE).
-- =============================================================================

create or replace function public.admin_presentes(
  p_busca  text default null,
  p_status text default null,
  p_limite int default 300
)
returns table (
  id                 uuid,
  tier_slug          text,
  tier_nome          text,
  valor_centavos     integer,
  codigo             text,
  status             text,
  comprador_nome     text,
  comprador_email    text,
  resgatado_por_nome text,
  resgatado_em       timestamptz,
  created_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('resgates') then
    raise exception 'sem permissão pra ver os presentes';
  end if;

  return query
    select
      g.id,
      g.tier_slug,
      coalesce(t.nome, g.tier_slug)      as tier_nome,
      g.valor_centavos,
      g.codigo,
      g.status,
      coalesce(pc.full_name, '')         as comprador_nome,
      coalesce(uc.email::text, '')       as comprador_email,
      coalesce(pr.full_name, '')         as resgatado_por_nome,
      g.resgatado_em,
      g.created_at
      from public.gift_subscriptions g
      left join public.tiers      t  on t.slug = g.tier_slug
      left join public.profiles   pc on pc.id  = g.comprador_id
      left join auth.users        uc on uc.id  = g.comprador_id
      left join public.profiles   pr on pr.id  = g.resgatado_por
     where (p_status is null or p_status = '' or g.status = p_status)
       and (
         v_busca is null
         or g.codigo ilike '%' || v_busca || '%'
         or coalesce(pc.full_name, '') ilike '%' || v_busca || '%'
         or coalesce(uc.email::text, '') ilike '%' || v_busca || '%'
         or coalesce(pr.full_name, '') ilike '%' || v_busca || '%'
       )
     order by g.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 2000));
end;
$$;

revoke all on function public.admin_presentes(text, text, int) from public, anon;
grant execute on function public.admin_presentes(text, text, int) to authenticated;



-- ===== 0042_email_do_console.sql =====

-- =============================================================================
-- 0042_email_do_console.sql — as abas do console voltam a abrir 🛠️
--
-- O SINTOMA: cinco abas do console (pedidos, resgates, pessoas, equipe e
-- aniversários) respondiam sempre a mesma frase, com dado ou sem dado:
--
--     structure of query does not match function result type
--
-- A CAUSA: `auth.users.email` é `character varying(255)` no Supabase, não
-- `text`. As seis funções abaixo devolvem esse e-mail (`coalesce(u.email, '')`,
-- que herda o varchar) numa coluna declarada `text` no `returns table`. O
-- `return query` do plpgsql compara os tipos UM A UM e exige igualdade exata:
-- varchar e text são parentes, mas não são o mesmo tipo, e a função morre antes
-- de devolver a primeira linha.
--
-- Por isso o erro aparecia mesmo com a tabela vazia: a conferência acontece na
-- montagem do resultado, antes de qualquer linha ser lida. Não era banco vazio,
-- não era permissão, não era a leva de migrations pela metade.
--
-- A CORREÇÃO: `u.email::text`. Uma conversão explícita, seis vezes, nada mais.
-- Nenhuma tabela, coluna, policy ou permissão muda; o corpo das funções segue
-- idêntico ao que a 0017 e a 0025 escreveram, com esse único acréscimo.
--
-- POR QUE UM ARQUIVO NOVO: migrations são imutáveis. A 0017 e a 0025 já foram
-- aplicadas, então elas não se tocam — quem corrige é este arquivo, com
-- `create or replace` (a assinatura de cada função é a mesma, então isto
-- substitui a versão antiga em vez de criar uma irmã).
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (create or replace).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- admin_pedidos — a fila da loja (0017).
-- ---------------------------------------------------------------------------
create or replace function public.admin_pedidos(
  p_status text default null,
  p_modo   text default null,
  p_limite integer default 200
)
returns table (
  id                uuid,
  criado_em         timestamptz,
  status            text,
  modo_entrega      text,
  cliente_nome      text,
  cliente_email     text,
  cliente_telefone  text,
  total_centavos    integer,
  desconto_centavos integer,
  tier_slug         text,
  entrega_cep       text,
  entrega_rua       text,
  entrega_numero    text,
  entrega_complemento text,
  entrega_bairro    text,
  entrega_cidade    text,
  entrega_uf        text,
  entregue_em       timestamptz,
  entregue_por_nome text,
  itens             jsonb
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if not public.tem_permissao('pedidos') then
    raise exception 'sem permissão pra ver os pedidos';
  end if;

  return query
    select
      o.id,
      o.created_at,
      o.status,
      o.modo_entrega,
      coalesce(o.entrega_nome, pr.full_name, '')            as cliente_nome,
      coalesce(u.email::text, '')                            as cliente_email,
      coalesce(o.entrega_telefone, pr.telefone, '')          as cliente_telefone,
      o.total_centavos,
      o.desconto_centavos,
      o.tier_slug_aplicado,
      o.entrega_cep, o.entrega_rua, o.entrega_numero, o.entrega_complemento,
      o.entrega_bairro, o.entrega_cidade, o.entrega_uf,
      o.entregue_em,
      coalesce(baixa.full_name, '')                          as entregue_por_nome,
      coalesce((
        select jsonb_agg(jsonb_build_object(
                 'nome',     oi.nome_snapshot,
                 'variante', oi.variante_snapshot,
                 'qtd',      oi.qtd,
                 'preco_centavos', oi.preco_unit_centavos)
                 order by oi.nome_snapshot)
          from public.order_items oi where oi.order_id = o.id
      ), '[]'::jsonb)                                        as itens
    from public.orders o
    left join public.profiles pr on pr.id = o.user_id
    left join auth.users     u  on u.id  = o.user_id
    left join public.profiles baixa on baixa.id = o.entregue_por
    where o.origem = 'site'
      and (
        p_status is null
        or (p_status = 'abertos' and o.status in ('pago', 'preparando', 'pronto'))
        or o.status = p_status
      )
      and (p_modo is null or coalesce(o.modo_entrega, 'entrega') = p_modo)
    order by o.created_at desc
    limit greatest(1, least(coalesce(p_limite, 200), 500));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_resgates — as recompensas resgatadas (0017).
-- ---------------------------------------------------------------------------
create or replace function public.admin_resgates(
  p_status text default null,
  p_limite integer default 200
)
returns table (
  id             uuid,
  criado_em      timestamptz,
  status         text,
  tipo           text,
  recompensa     text,
  pontos_gastos  integer,
  codigo         text,
  cliente_nome   text,
  cliente_email  text,
  usado_em       timestamptz,
  usado_por_nome text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if not public.tem_permissao('resgates') then
    raise exception 'sem permissão pra ver os resgates';
  end if;

  return query
    select
      r.id,
      r.created_at,
      r.status,
      r.tipo,
      coalesce(rw.nome, pl.descricao, 'recompensa')  as recompensa,
      r.pontos_gastos,
      coalesce(r.codigo, '')                          as codigo,
      coalesce(pr.full_name, '')                      as cliente_nome,
      coalesce(u.email::text, '')                     as cliente_email,
      r.usado_em,
      coalesce(baixa.full_name, '')                   as usado_por_nome
    from public.redemptions r
    left join public.rewards_catalog rw on rw.id = r.reward_id
    left join public.points_ledger  pl on pl.redemption_id = r.id
    left join public.profiles       pr on pr.id = r.user_id
    left join auth.users            u  on u.id  = r.user_id
    left join public.profiles       baixa on baixa.id = r.usado_por
    where (
      p_status is null
      or (p_status = 'abertos' and r.status in ('solicitado', 'aprovado'))
      or r.status = p_status
    )
    order by r.created_at desc
    limit greatest(1, least(coalesce(p_limite, 200), 500));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_usuarios — quem já passou por aqui (0017).
-- ---------------------------------------------------------------------------
create or replace function public.admin_usuarios(
  p_busca  text default null,
  p_limite integer default 200
)
returns table (
  id                uuid,
  nome              text,
  email             text,
  telefone          text,
  papel             text,
  master            boolean,
  plano             text,
  plano_status      text,
  pontos            integer,
  pedidos           bigint,
  gasto_centavos    bigint,
  cadastrado_em     timestamptz,
  ultimo_acesso     timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('usuarios') then
    raise exception 'sem permissão pra ver as pessoas';
  end if;

  return query
    select
      p.id,
      coalesce(p.full_name, '')          as nome,
      coalesce(u.email::text, '')        as email,
      coalesce(p.telefone, '')           as telefone,
      p.role                             as papel,
      p.master,
      coalesce(t.nome, '')               as plano,
      coalesce((
        select s.status from public.subscriptions s
         where s.user_id = p.id
         order by s.current_period_end desc nulls last, s.created_at desc
         limit 1
      ), '')                             as plano_status,
      coalesce(p.points_balance, 0)      as pontos,
      (select count(*) from public.orders o
        where o.user_id = p.id and o.status in ('pago','preparando','pronto','entregue'))
                                         as pedidos,
      (select coalesce(sum(o.total_centavos), 0) from public.orders o
        where o.user_id = p.id and o.status in ('pago','preparando','pronto','entregue'))
                                         as gasto_centavos,
      p.created_at                       as cadastrado_em,
      u.last_sign_in_at                  as ultimo_acesso
    from public.profiles p
    left join auth.users  u on u.id = p.id
    left join public.tiers t on t.slug = p.tier_slug
    where v_busca is null
       or p.full_name ilike '%' || v_busca || '%'
       or u.email     ilike '%' || v_busca || '%'
       or p.telefone  ilike '%' || v_busca || '%'
    order by p.created_at desc
    limit greatest(1, least(coalesce(p_limite, 200), 1000));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_equipe — quem tem permissão, e quais (0017).
-- ---------------------------------------------------------------------------
create or replace function public.admin_equipe()
returns table (
  id          uuid,
  nome        text,
  email       text,
  papel       text,
  master      boolean,
  permissoes  jsonb
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if not public.tem_permissao('equipe') then
    raise exception 'sem permissão pra ver a equipe';
  end if;

  return query
    select
      p.id,
      coalesce(p.full_name, '')     as nome,
      coalesce(u.email::text, '')   as email,
      p.role                        as papel,
      p.master,
      coalesce((
        select jsonb_agg(sp.permissao order by sp.permissao)
          from public.staff_permissions sp where sp.user_id = p.id
      ), '[]'::jsonb)               as permissoes
    from public.profiles p
    left join auth.users u on u.id = p.id
    where p.role = 'owner'
       or exists (select 1 from public.staff_permissions sp where sp.user_id = p.id)
    order by p.role = 'owner' desc, p.full_name nulls last;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_buscar_pessoa — o campo de busca de "dar permissão a alguém" (0017).
-- ---------------------------------------------------------------------------
create or replace function public.admin_buscar_pessoa(p_busca text)
returns table (
  id     uuid,
  nome   text,
  email  text,
  papel  text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('equipe') then
    raise exception 'sem permissão pra mexer na equipe';
  end if;
  if v_busca is null or length(v_busca) < 3 then
    return;
  end if;

  return query
    select p.id, coalesce(p.full_name, ''), coalesce(u.email::text, ''), p.role
    from public.profiles p
    left join auth.users u on u.id = p.id
    where p.full_name ilike '%' || v_busca || '%'
       or u.email     ilike '%' || v_busca || '%'
    order by p.full_name nulls last
    limit 20;
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_brindes_listar — os brunches de aniversário reservados (0025).
-- ---------------------------------------------------------------------------
create or replace function public.admin_brindes_listar(
  p_busca  text default null,
  p_status text default null,
  p_limite integer default 200
)
returns table (
  id                uuid,
  criado_em         timestamptz,
  codigo            text,
  situacao          text,
  valido_ate_label  text,
  aniversario       text,
  cliente_nome      text,
  cliente_email     text,
  usado_em          timestamptz,
  usado_por_nome    text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not public.tem_permissao('resgates') then
    raise exception 'sem permissão pra ver os brindes';
  end if;

  return query
    select
      b.id,
      b.criado_em,
      b.codigo,
      case when b.status = 'usado' then 'usado'
           when b.valido_ate < v_hoje then 'expirado'
           else 'ativo' end                        as situacao,
      to_char(b.valido_ate, 'DD/MM')               as valido_ate_label,
      to_char(pr.nascimento, 'DD/MM')              as aniversario,
      coalesce(pr.apelido, pr.full_name, '')       as cliente_nome,
      coalesce(u.email::text, '')                  as cliente_email,
      b.usado_em,
      coalesce(baixa.full_name, '')                as usado_por_nome
    from public.brindes_aniversario b
    left join public.profiles pr    on pr.id = b.user_id
    left join auth.users      u     on u.id  = b.user_id
    left join public.profiles baixa on baixa.id = b.usado_por
    where (v_busca is null
           or b.codigo ilike '%' || v_busca || '%'
           or pr.full_name ilike '%' || v_busca || '%'
           or pr.apelido ilike '%' || v_busca || '%')
      and (
        p_status is null
        or (p_status = 'usado'    and b.status = 'usado')
        or (p_status = 'ativo'    and b.status = 'ativo' and b.valido_ate >= v_hoje)
        or (p_status = 'expirado' and b.status = 'ativo' and b.valido_ate <  v_hoje)
      )
    order by b.criado_em desc
    limit greatest(1, least(coalesce(p_limite, 200), 500));
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissões. O `create or replace` preserva os grants que já existiam, mas
-- repetir aqui deixa este arquivo se bastar sozinho (e é o mesmo texto da 0017
-- e da 0025, então não afrouxa nada).
-- ---------------------------------------------------------------------------
revoke all on function public.admin_pedidos(text, text, integer)             from public, anon;
revoke all on function public.admin_resgates(text, integer)                  from public, anon;
revoke all on function public.admin_usuarios(text, integer)                  from public, anon;
revoke all on function public.admin_equipe()                                 from public, anon;
revoke all on function public.admin_buscar_pessoa(text)                      from public, anon;
revoke all on function public.admin_brindes_listar(text, text, integer)      from public, anon;

grant execute on function public.admin_pedidos(text, text, integer)          to authenticated;
grant execute on function public.admin_resgates(text, integer)               to authenticated;
grant execute on function public.admin_usuarios(text, integer)               to authenticated;
grant execute on function public.admin_equipe()                              to authenticated;
grant execute on function public.admin_buscar_pessoa(text)                   to authenticated;
grant execute on function public.admin_brindes_listar(text, text, integer)   to authenticated;



-- ===== 0043_pautas.sql =====

-- =============================================================================
-- 0043_pautas.sql — o quadro de pautas da equipe 📋
--
-- O console sabia tudo sobre o que a CASA vende e nada sobre o que a EQUIPE
-- combina. O que a turma tinha que fazer no dia vivia em bilhete no balcão e em
-- conversa de grupo, que é onde combinado some. Isto é o quadro: a casa escreve
-- a pauta (título + briefing), diz pra quem é e até quando, e quem trabalha
-- move o cartão até "feita".
--
-- PERMISSÃO NOVA ('pautas'), e por que ela precisa existir:
--   O whitelist de permissões do console é fechado por CHECK (0017), então
--   permissão nova pede migration — é exatamente o que este arquivo faz. As
--   outras abas puderam reusar 'relatorios' ou 'resgates' porque eram leitura
--   do mesmo tipo. Aqui não dá: o quadro é o único lugar do console onde quem
--   NÃO cuida do dinheiro nem do cadastro precisa entrar. Enfiar a pauta em
--   'relatorios' daria, junto, a lista de e-mails e o que a casa vendeu.
--
-- QUEM PODE O QUÊ (a régua toda mora no banco, não na tela):
--   • ver o quadro, criar, editar e mover cartão → tem_permissao('pautas');
--   • APAGAR → só quem criou a pauta, ou o adm do Casa. Briefing é combinado
--     escrito: quem escreveu pode voltar atrás, os outros não apagam por cima.
--   Escrita direta pelo client não existe: RLS ligada e nenhuma policy
--   (deny-by-default), tudo pelas RPCs abaixo. É a mesma porta da 0040.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. A permissão nova entra no whitelist fechado da 0017.
--    O CHECK nasceu inline na coluna, então o nome dele é o que o Postgres dá
--    (staff_permissions_permissao_check). Procurar pelo conteúdo em vez de
--    confiar no nome deixa isto seguro mesmo se o banco tiver outro rótulo.
-- -----------------------------------------------------------------------------
do $$
declare
  v_nome text;
begin
  select con.conname into v_nome
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
   where nsp.nspname = 'public'
     and rel.relname = 'staff_permissions'
     and con.contype = 'c'
     and pg_get_constraintdef(con.oid) ilike '%dashboard%'
   limit 1;

  if v_nome is not null then
    execute format('alter table public.staff_permissions drop constraint %I', v_nome);
  end if;

  alter table public.staff_permissions
    add constraint staff_permissions_permissao_check
    check (permissao in (
      'dashboard', 'pedidos', 'entregas', 'resgates',
      'usuarios', 'relatorios', 'equipe', 'pautas'));
end $$;

-- -----------------------------------------------------------------------------
-- 2. A tabela.
--    `atribuido_a` nulo = pauta da casa inteira (o recado que vale pra todo
--    mundo, tipo "sexta a gente abre 7h"). ON DELETE SET NULL nos três vínculos
--    de pessoa: conta que sai da casa não leva a pauta junto, e o histórico do
--    que foi combinado continua de pé.
-- -----------------------------------------------------------------------------
create table if not exists public.pautas (
  id            uuid primary key default gen_random_uuid(),
  titulo        text not null check (char_length(btrim(titulo)) between 1 and 120),
  briefing      text check (briefing is null or char_length(briefing) <= 4000),
  atribuido_a   uuid references public.profiles (id) on delete set null,
  prazo         date,
  prioridade    text not null default 'normal' check (prioridade in ('baixa', 'normal', 'alta')),
  status        text not null default 'aberta' check (status in ('aberta', 'fazendo', 'feita')),
  criado_por    uuid references public.profiles (id) on delete set null,
  concluida_em  timestamptz,
  concluida_por uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_pautas_status    on public.pautas (status, created_at desc);
create index if not exists idx_pautas_atribuido on public.pautas (atribuido_a, status);

-- Deny-by-default: RLS ligada e NENHUMA policy. O client não lê nem escreve
-- direto; quem fala com a tabela são as funções abaixo, que checam a permissão.
alter table public.pautas enable row level security;

-- -----------------------------------------------------------------------------
-- 3. admin_pautas_listar — o quadro inteiro.
--    Devolve o nome de quem recebeu, de quem escreveu e de quem concluiu, pra a
--    tela não precisar de uma segunda consulta em `profiles` (que a RLS de lá
--    nem permitiria pra terceiros).
-- -----------------------------------------------------------------------------
create or replace function public.admin_pautas_listar(
  p_status  text default null,
  p_de_quem uuid default null,
  p_busca   text default null,
  p_limite  int  default 300
)
returns table (
  id                 uuid,
  titulo             text,
  briefing           text,
  atribuido_a        uuid,
  atribuido_nome     text,
  prazo              date,
  prioridade         text,
  status             text,
  criado_por         uuid,
  criado_por_nome    text,
  concluida_em       timestamptz,
  concluida_por_nome text,
  created_at         timestamptz,
  updated_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra ver as pautas';
  end if;

  return query
    select
      p.id,
      p.titulo,
      p.briefing,
      p.atribuido_a,
      coalesce(pa.full_name, '')  as atribuido_nome,
      p.prazo,
      p.prioridade,
      p.status,
      p.criado_por,
      coalesce(pc.full_name, '')  as criado_por_nome,
      p.concluida_em,
      coalesce(pf.full_name, '')  as concluida_por_nome,
      p.created_at,
      p.updated_at
      from public.pautas p
      left join public.profiles pa on pa.id = p.atribuido_a
      left join public.profiles pc on pc.id = p.criado_por
      left join public.profiles pf on pf.id = p.concluida_por
     where (p_status is null or p_status = '' or p.status = p_status)
       and (p_de_quem is null or p.atribuido_a = p_de_quem)
       and (
         v_busca is null
         or p.titulo ilike '%' || v_busca || '%'
         or coalesce(p.briefing, '') ilike '%' || v_busca || '%'
         or coalesce(pa.full_name, '') ilike '%' || v_busca || '%'
       )
     order by
       case p.status when 'fazendo' then 0 when 'aberta' then 1 else 2 end,
       case p.prioridade when 'alta' then 0 when 'normal' then 1 else 2 end,
       p.prazo asc nulls last,
       p.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 1000));
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. admin_pautas_equipe — quem pode receber uma pauta.
--    Existe pra o campo "pra quem" do formulário. NÃO é a `admin_equipe`: aquela
--    pede a permissão 'equipe' (quem manda no acesso dos outros) e devolve
--    e-mail. Aqui basta id + nome, e a régua é a mesma do quadro.
-- -----------------------------------------------------------------------------
create or replace function public.admin_pautas_equipe()
returns table (id uuid, nome text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra ver a equipe';
  end if;

  return query
    select p.id, coalesce(nullif(btrim(p.full_name), ''), 'sem nome') as nome
      from public.profiles p
     where p.role = 'owner'
        or exists (select 1 from public.staff_permissions sp where sp.user_id = p.id)
     order by p.role = 'owner' desc, p.full_name nulls last;
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. admin_pauta_salvar — cria (p_id null) ou edita.
--    O status NÃO vem por aqui: quem move cartão é a `admin_pauta_status`, pra
--    "salvar uma edição" nunca desfazer sem querer o andamento que alguém deu.
-- -----------------------------------------------------------------------------
create or replace function public.admin_pauta_salvar(
  p_id          uuid,
  p_titulo      text,
  p_briefing    text,
  p_atribuido_a uuid,
  p_prazo       date,
  p_prioridade  text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_titulo text := btrim(coalesce(p_titulo, ''));
  v_prio   text := coalesce(nullif(btrim(coalesce(p_prioridade, '')), ''), 'normal');
  v_id     uuid;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;
  if char_length(v_titulo) < 1 or char_length(v_titulo) > 120 then
    return jsonb_build_object('ok', false, 'erro', 'a pauta precisa de um título de até 120 letras');
  end if;
  if v_prio not in ('baixa', 'normal', 'alta') then
    v_prio := 'normal';
  end if;
  -- Só dá pra atribuir a quem entra no console: pauta pra cliente não existe.
  if p_atribuido_a is not null
     and not exists (
       select 1 from public.profiles p
        where p.id = p_atribuido_a
          and (p.role = 'owner'
               or exists (select 1 from public.staff_permissions sp where sp.user_id = p.id))
     ) then
    return jsonb_build_object('ok', false, 'erro', 'essa pessoa não é da equipe do console');
  end if;

  if p_id is null then
    insert into public.pautas (titulo, briefing, atribuido_a, prazo, prioridade, criado_por)
    values (v_titulo, nullif(btrim(coalesce(p_briefing, '')), ''), p_atribuido_a, p_prazo, v_prio, v_uid)
    returning id into v_id;
  else
    update public.pautas
       set titulo      = v_titulo,
           briefing    = nullif(btrim(coalesce(p_briefing, '')), ''),
           atribuido_a = p_atribuido_a,
           prazo       = p_prazo,
           prioridade  = v_prio,
           updated_at  = now()
     where id = p_id
    returning id into v_id;

    if v_id is null then
      return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
    end if;
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, case when p_id is null then 'pauta_criada' else 'pauta_editada' end,
          'pautas', v_id::text, jsonb_build_object('titulo', v_titulo));

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. admin_pauta_status — mover o cartão.
--    Idempotente: mandar o status que já está não é erro. Ao virar 'feita'
--    carimba quem concluiu e quando; ao voltar, limpa o carimbo (senão o quadro
--    contaria como entregue algo que voltou pra fila).
-- -----------------------------------------------------------------------------
create or replace function public.admin_pauta_status(p_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_novo text := btrim(coalesce(p_status, ''));
  v_id   uuid;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;
  if v_novo not in ('aberta', 'fazendo', 'feita') then
    return jsonb_build_object('ok', false, 'erro', 'esse estado não existe no quadro');
  end if;

  update public.pautas
     set status        = v_novo,
         concluida_em  = case when v_novo = 'feita' then now() else null end,
         concluida_por = case when v_novo = 'feita' then v_uid else null end,
         updated_at    = now()
   where id = p_id
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;

  return jsonb_build_object('ok', true, 'status', v_novo);
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. admin_pauta_remover — só quem escreveu, ou o adm do Casa.
--    Quem não pode apagar ainda pode marcar como feita: nada fica preso.
-- -----------------------------------------------------------------------------
create or replace function public.admin_pauta_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_pauta public.pautas;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;

  select * into v_pauta from public.pautas where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  if not (public.is_owner() or v_pauta.criado_por = v_uid) then
    return jsonb_build_object('ok', false, 'erro',
      'essa pauta é de quem escreveu. tu pode marcar como feita, apagar só quem escreveu ou o adm do Casa');
  end if;

  delete from public.pautas where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'pauta_removida', 'pautas', p_id::text,
          jsonb_build_object('titulo', v_pauta.titulo));

  return jsonb_build_object('ok', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. Permissões das funções. Deslogado (anon) não alcança nada.
-- -----------------------------------------------------------------------------
revoke all on function public.admin_pautas_listar(text, uuid, text, int)          from public, anon;
revoke all on function public.admin_pautas_equipe()                               from public, anon;
revoke all on function public.admin_pauta_salvar(uuid, text, text, uuid, date, text) from public, anon;
revoke all on function public.admin_pauta_status(uuid, text)                      from public, anon;
revoke all on function public.admin_pauta_remover(uuid)                           from public, anon;

grant execute on function public.admin_pautas_listar(text, uuid, text, int)          to authenticated;
grant execute on function public.admin_pautas_equipe()                               to authenticated;
grant execute on function public.admin_pauta_salvar(uuid, text, text, uuid, date, text) to authenticated;
grant execute on function public.admin_pauta_status(uuid, text)                      to authenticated;
grant execute on function public.admin_pauta_remover(uuid)                           to authenticated;



-- ===== 0044_mural_pela_permissao.sql =====

-- =============================================================================
-- 0044_mural_pela_permissao.sql — a aba do mural passa a valer pra equipe 🧹
--
-- O BURACO: a aba "mural" do console é a única que escreve DIRETO pela RLS, e as
-- policies da 0020 falam em `is_staff()`, que é `profiles.role in (staff,
-- gerente, owner)`. Só que o console NUNCA troca o papel de ninguém: a
-- `admin_definir_permissoes` (0017) grava em `staff_permissions` e sai, de
-- propósito — o princípio da casa é "cargo não abre porta, permissão abre".
--
-- Resultado prático: quem recebe a permissão 'usuarios' pelo console vê a aba,
-- lê os recados aprovados (essa leitura é pública) e **não consegue nada mais**:
-- os escondidos não aparecem, "esconder" e "apagar" batem na RLS. A aba
-- funcionava só pro adm do Casa, que é o único com role='owner'. Isso não
-- aparecia enquanto a casa era de uma pessoa só.
--
-- A CORREÇÃO, na porta certa: a moderação passa a ser três funções gated por
-- `tem_permissao('usuarios')`, como TODAS as outras abas. Nada de promover
-- ninguém a staff pra destravar — promover abriria junto, pela RLS, toda tabela
-- que confia em `is_staff()` (pedidos, resgates, brindes), e permissão de
-- moderar mural não é permissão de ler o caixa.
--
-- O que NÃO muda: as policies da 0020 continuam de pé (o autor segue apagando o
-- próprio recado no /o-casa, o staff de verdade segue enxergando tudo), e a
-- trigger da 0036 continua impedindo QUALQUER UM de reescrever `texto`,
-- `autor_nome` e `user_id` — daqui também. Dá pra esconder e apagar, nunca pra
-- pôr na parede uma frase que a pessoa não escreveu.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (CREATE OR REPLACE).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- admin_mural_listar — a parede inteira, inclusive o que está escondido.
-- -----------------------------------------------------------------------------
create or replace function public.admin_mural_listar(
  p_busca  text default null,
  p_status text default null,
  p_limite int  default 300
)
returns table (
  id         uuid,
  autor_nome text,
  texto      text,
  status     text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('usuarios') then
    raise exception 'sem permissão pra cuidar do mural';
  end if;

  return query
    select m.id, coalesce(m.autor_nome, ''), m.texto, m.status, m.created_at
      from public.mural_notes m
     where (p_status is null or p_status = '' or m.status = p_status)
       and (
         v_busca is null
         or m.texto ilike '%' || v_busca || '%'
         or coalesce(m.autor_nome, '') ilike '%' || v_busca || '%'
       )
     order by m.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 1000));
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_mural_status — esconder e devolver pra parede. Idempotente.
-- Mexe SÓ no status: o texto e o nome de quem escreveu não passam por aqui, e a
-- trigger da 0036 barraria de qualquer jeito.
-- -----------------------------------------------------------------------------
create or replace function public.admin_mural_status(p_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_novo text := btrim(coalesce(p_status, ''));
  v_id   uuid;
begin
  if not public.tem_permissao('usuarios') then
    raise exception 'sem permissão pra cuidar do mural';
  end if;
  if v_novo not in ('aprovado', 'oculto') then
    return jsonb_build_object('ok', false, 'erro', 'esse estado não existe no mural');
  end if;

  update public.mural_notes set status = v_novo where id = p_id
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'esse recado não existe mais');
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'mural_status', 'mural_notes', p_id::text,
          jsonb_build_object('status', v_novo));

  return jsonb_build_object('ok', true, 'status', v_novo);
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_mural_remover — o caminho sem volta, registrado no audit_log.
-- Guarda o texto no registro: apagar da parede não pode apagar também a memória
-- de que alguém apagou, e o que era.
-- -----------------------------------------------------------------------------
create or replace function public.admin_mural_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_nota public.mural_notes;
begin
  if not public.tem_permissao('usuarios') then
    raise exception 'sem permissão pra cuidar do mural';
  end if;

  select * into v_nota from public.mural_notes where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  delete from public.mural_notes where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'mural_removido', 'mural_notes', p_id::text,
          jsonb_build_object('autor_nome', coalesce(v_nota.autor_nome, ''),
                             'texto', v_nota.texto));

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_mural_listar(text, text, int) from public, anon;
revoke all on function public.admin_mural_status(uuid, text)      from public, anon;
revoke all on function public.admin_mural_remover(uuid)           from public, anon;

grant execute on function public.admin_mural_listar(text, text, int) to authenticated;
grant execute on function public.admin_mural_status(uuid, text)      to authenticated;
grant execute on function public.admin_mural_remover(uuid)           to authenticated;



-- ===== 0045_quadros.sql =====

-- =============================================================================
-- 0045_quadros.sql — o quadro de pautas vira um quadro de verdade 🗂️
--
-- A 0043 entregou UM quadro só, com três colunas fixas e cartões. Isto traz o
-- que faltava pra ele funcionar como a casa precisa e parecer com o que todo
-- mundo já conhece de ferramenta de quadro:
--
--   • VÁRIOS QUADROS (salão, cozinha, marketing…), cada um com nome e cor.
--   • GRUPOS dentro do quadro (a faixa colorida com as linhas embaixo):
--     "essa semana", "quando der", "toda segunda".
--   • Um ESTADO A MAIS: 'travada'. É o "stuck" de qualquer quadro, e num café é
--     o mais informativo que existe ("o fornecedor não entregou"). Sem ele, a
--     pauta parada fica indistinguível da que ninguém pegou.
--   • COMENTÁRIOS por pauta (`pauta_updates`): o combinado continua na pauta em
--     vez de virar conversa de grupo, que é onde combinado some.
--   • ORDEM dentro do grupo, movida por botão (subir/descer). Arrastar foi
--     recusado de propósito: o console é usado no celular no meio do turno.
--
-- SOBRE A LEITURA SER `returns jsonb` E NÃO `returns table`:
--   Foi o `returns table` que derrubou cinco abas do console da 0017 até a 0042
--   (o `auth.users.email` é varchar e a coluna era declarada text; o plpgsql
--   compara tipo a tipo e a função morria antes da primeira linha). Uma leitura
--   composta como esta, que devolve quadro + grupos + itens de uma vez, teria
--   uma dúzia de colunas pra errar. Em jsonb não existe essa classe de erro, e
--   ainda vem tudo numa viagem só.
--
-- SEGURANÇA: as três tabelas novas sobem com RLS ligada e NENHUMA policy
-- (deny-by-default). Toda leitura e escrita passa pelas funções abaixo, gated
-- em `tem_permissao('pautas')`, igual ao resto do console.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / backfill condicional).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Quadros e grupos.
--    `cor` é um slug curto que o front traduz pra cor da casa — nada de hex no
--    banco, senão o dia que a paleta mudar o quadro fica falando outra língua.
-- -----------------------------------------------------------------------------
create table if not exists public.pauta_quadros (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null check (char_length(btrim(nome)) between 1 and 60),
  cor        text not null default 'coral'
             check (cor in ('neutro', 'coral', 'gold', 'green', 'olive', 'blue')),
  ordem      int  not null default 0,
  arquivado  boolean not null default false,
  criado_por uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pauta_grupos (
  id         uuid primary key default gen_random_uuid(),
  quadro_id  uuid not null references public.pauta_quadros (id) on delete cascade,
  nome       text not null check (char_length(btrim(nome)) between 1 and 60),
  cor        text not null default 'neutro'
             check (cor in ('neutro', 'coral', 'gold', 'green', 'olive', 'blue')),
  ordem      int  not null default 0,
  -- Grupo fechado é do QUADRO, não do navegador de quem fechou: a casa fecha
  -- "feitas" uma vez e vale pra todo mundo que abrir depois.
  recolhido  boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_pauta_grupos_quadro on public.pauta_grupos (quadro_id, ordem);

alter table public.pauta_quadros enable row level security;
alter table public.pauta_grupos  enable row level security;

-- -----------------------------------------------------------------------------
-- 2. A `pautas` ganha quadro, grupo e ordem, e o estado 'travada'.
-- -----------------------------------------------------------------------------
alter table public.pautas add column if not exists quadro_id uuid references public.pauta_quadros (id) on delete cascade;
alter table public.pautas add column if not exists grupo_id  uuid references public.pauta_grupos (id) on delete set null;
alter table public.pautas add column if not exists ordem     int not null default 0;

create index if not exists idx_pautas_quadro on public.pautas (quadro_id, grupo_id, ordem);

do $$
declare
  v_nome text;
begin
  select con.conname into v_nome
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
   where nsp.nspname = 'public' and rel.relname = 'pautas' and con.contype = 'c'
     and pg_get_constraintdef(con.oid) ilike '%fazendo%'
   limit 1;
  if v_nome is not null then
    execute format('alter table public.pautas drop constraint %I', v_nome);
  end if;
  alter table public.pautas
    add constraint pautas_status_check
    check (status in ('aberta', 'fazendo', 'travada', 'feita'));
end $$;

-- -----------------------------------------------------------------------------
-- 3. Comentários da pauta (os "updates").
--    `autor_nome` é SNAPSHOT: quem comentou continua nomeado mesmo se a conta
--    sair da casa depois (o `user_id` vira null e o recado não fica órfão).
-- -----------------------------------------------------------------------------
create table if not exists public.pauta_updates (
  id         uuid primary key default gen_random_uuid(),
  pauta_id   uuid not null references public.pautas (id) on delete cascade,
  user_id    uuid references public.profiles (id) on delete set null,
  autor_nome text,
  texto      text not null check (char_length(btrim(texto)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists idx_pauta_updates_pauta on public.pauta_updates (pauta_id, created_at);

alter table public.pauta_updates enable row level security;

-- -----------------------------------------------------------------------------
-- 4. Backfill: o que já estava no quadro antigo entra no desenho novo.
--    Roda uma vez; reaplicar o arquivo não duplica nada (as condições barram).
-- -----------------------------------------------------------------------------
do $$
declare
  v_quadro uuid;
  v_grupo  uuid;
begin
  if not exists (select 1 from public.pauta_quadros) then
    insert into public.pauta_quadros (nome, cor, ordem)
    values ('o quadro da casa', 'coral', 0)
    returning id into v_quadro;
  else
    select id into v_quadro from public.pauta_quadros order by ordem, created_at limit 1;
  end if;

  if not exists (select 1 from public.pauta_grupos where quadro_id = v_quadro) then
    insert into public.pauta_grupos (quadro_id, nome, cor, ordem)
    values (v_quadro, 'o dia a dia', 'neutro', 0)
    returning id into v_grupo;
  else
    select id into v_grupo from public.pauta_grupos where quadro_id = v_quadro order by ordem limit 1;
  end if;

  update public.pautas
     set quadro_id = v_quadro,
         grupo_id  = coalesce(grupo_id, v_grupo)
   where quadro_id is null;
end $$;

-- Depois do backfill nenhuma pauta pode ficar sem quadro: sem isso, uma linha
-- órfã não apareceria em quadro nenhum e viraria trabalho invisível.
alter table public.pautas alter column quadro_id set not null;

-- -----------------------------------------------------------------------------
-- 5. Leitura: um quadro inteiro (grupos + itens) numa viagem só.
-- -----------------------------------------------------------------------------
create or replace function public.admin_quadros_listar()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra ver os quadros';
  end if;

  return coalesce((
    select jsonb_agg(q order by q.ordem, q.created_at)
      from (
        select jsonb_build_object(
                 'id', k.id, 'nome', k.nome, 'cor', k.cor,
                 'ordem', k.ordem, 'arquivado', k.arquivado,
                 'itens', (select count(*) from public.pautas p where p.quadro_id = k.id),
                 'abertas', (select count(*) from public.pautas p
                              where p.quadro_id = k.id and p.status <> 'feita')
               ) as q,
               k.ordem, k.created_at
          from public.pauta_quadros k
      ) q
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_quadro_abrir(
  p_quadro_id uuid default null,
  p_busca     text default null,
  p_de_quem   uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_busca  text := nullif(btrim(coalesce(p_busca, '')), '');
  v_quadro uuid := p_quadro_id;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra ver o quadro';
  end if;

  -- Sem quadro pedido (primeira visita, ou o quadro salvo sumiu), abre o primeiro.
  if v_quadro is null or not exists (select 1 from public.pauta_quadros where id = v_quadro) then
    select id into v_quadro from public.pauta_quadros where not arquivado order by ordem, created_at limit 1;
  end if;
  if v_quadro is null then
    return jsonb_build_object('quadro', null, 'grupos', '[]'::jsonb, 'itens', '[]'::jsonb);
  end if;

  return jsonb_build_object(
    'quadro', (select jsonb_build_object('id', k.id, 'nome', k.nome, 'cor', k.cor, 'arquivado', k.arquivado)
                 from public.pauta_quadros k where k.id = v_quadro),
    'grupos', coalesce((
      select jsonb_agg(jsonb_build_object('id', g.id, 'nome', g.nome, 'cor', g.cor,
                                          'ordem', g.ordem, 'recolhido', g.recolhido)
                       order by g.ordem, g.created_at)
        from public.pauta_grupos g where g.quadro_id = v_quadro), '[]'::jsonb),
    'itens', coalesce((
      select jsonb_agg(j order by j_ordem, j_criado)
        from (
          select jsonb_build_object(
                   'id', p.id,
                   'titulo', p.titulo,
                   'briefing', p.briefing,
                   'grupo_id', p.grupo_id,
                   'atribuido_a', p.atribuido_a,
                   'atribuido_nome', coalesce(pa.full_name, ''),
                   'prazo', p.prazo,
                   'prioridade', p.prioridade,
                   'status', p.status,
                   'ordem', p.ordem,
                   'criado_por_nome', coalesce(pc.full_name, ''),
                   'concluida_em', p.concluida_em,
                   'concluida_por_nome', coalesce(pf.full_name, ''),
                   'comentarios', (select count(*) from public.pauta_updates u where u.pauta_id = p.id),
                   'created_at', p.created_at
                 ) as j,
                 p.ordem as j_ordem, p.created_at as j_criado
            from public.pautas p
            left join public.profiles pa on pa.id = p.atribuido_a
            left join public.profiles pc on pc.id = p.criado_por
            left join public.profiles pf on pf.id = p.concluida_por
           where p.quadro_id = v_quadro
             and (p_de_quem is null or p.atribuido_a = p_de_quem)
             and (
               v_busca is null
               or p.titulo ilike '%' || v_busca || '%'
               or coalesce(p.briefing, '') ilike '%' || v_busca || '%'
               or coalesce(pa.full_name, '') ilike '%' || v_busca || '%'
             )
        ) itens
    ), '[]'::jsonb)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. Escrita nos quadros e grupos.
-- -----------------------------------------------------------------------------
create or replace function public.admin_quadro_salvar(
  p_id   uuid default null,
  p_nome text default null,
  p_cor  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_cor  text := coalesce(nullif(btrim(coalesce(p_cor, '')), ''), 'coral');
  v_id   uuid;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nos quadros';
  end if;
  if char_length(v_nome) < 1 or char_length(v_nome) > 60 then
    return jsonb_build_object('ok', false, 'erro', 'dá um nome de até 60 letras pro quadro');
  end if;
  if v_cor not in ('neutro', 'coral', 'gold', 'green', 'olive', 'blue') then
    v_cor := 'coral';
  end if;

  if p_id is null then
    insert into public.pauta_quadros (nome, cor, ordem, criado_por)
    values (v_nome, v_cor,
            coalesce((select max(ordem) + 1 from public.pauta_quadros), 0),
            v_uid)
    returning id into v_id;

    -- Quadro nasce com um grupo, senão a primeira pauta não teria onde cair.
    insert into public.pauta_grupos (quadro_id, nome, cor, ordem)
    values (v_id, 'o dia a dia', 'neutro', 0);
  else
    update public.pauta_quadros
       set nome = v_nome, cor = v_cor, updated_at = now()
     where id = p_id
    returning id into v_id;
    if v_id is null then
      return jsonb_build_object('ok', false, 'erro', 'esse quadro não existe mais');
    end if;
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, case when p_id is null then 'quadro_criado' else 'quadro_editado' end,
          'pauta_quadros', v_id::text, jsonb_build_object('nome', v_nome));

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- Remover quadro: só quem criou, ou o adm do Casa, e SÓ SE ESTIVER VAZIO.
-- Apagar quadro com pauta dentro levaria junto trabalho combinado (o cascade
-- limparia grupos e pautas em silêncio). Quem quer sumir com o quadro cheio
-- arquiva.
create or replace function public.admin_quadro_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_quadro public.pauta_quadros;
  v_itens  bigint;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nos quadros';
  end if;

  select * into v_quadro from public.pauta_quadros where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;
  if not (public.is_owner() or v_quadro.criado_por = v_uid) then
    return jsonb_build_object('ok', false, 'erro',
      'esse quadro é de quem criou. dá pra arquivar, apagar só quem criou ou o adm do Casa');
  end if;

  select count(*) into v_itens from public.pautas where quadro_id = p_id;
  if v_itens > 0 then
    return jsonb_build_object('ok', false, 'erro',
      'esse quadro ainda tem ' || v_itens || ' pauta(s) dentro. move ou apaga elas antes, ou arquiva o quadro');
  end if;

  delete from public.pauta_quadros where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'quadro_removido', 'pauta_quadros', p_id::text,
          jsonb_build_object('nome', v_quadro.nome));

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.admin_quadro_arquivar(p_id uuid, p_arquivar boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nos quadros';
  end if;
  update public.pauta_quadros set arquivado = coalesce(p_arquivar, true), updated_at = now()
   where id = p_id returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'esse quadro não existe mais');
  end if;
  return jsonb_build_object('ok', true, 'arquivado', coalesce(p_arquivar, true));
end;
$$;

create or replace function public.admin_grupo_salvar(
  p_id        uuid default null,
  p_quadro_id uuid default null,
  p_nome      text default null,
  p_cor       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_cor  text := coalesce(nullif(btrim(coalesce(p_cor, '')), ''), 'coral');
  v_id   uuid;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nos grupos';
  end if;
  if char_length(v_nome) < 1 or char_length(v_nome) > 60 then
    return jsonb_build_object('ok', false, 'erro', 'dá um nome de até 60 letras pro grupo');
  end if;
  if v_cor not in ('neutro', 'coral', 'gold', 'green', 'olive', 'blue') then
    v_cor := 'coral';
  end if;

  if p_id is null then
    if p_quadro_id is null or not exists (select 1 from public.pauta_quadros where id = p_quadro_id) then
      return jsonb_build_object('ok', false, 'erro', 'esse quadro não existe mais');
    end if;
    insert into public.pauta_grupos (quadro_id, nome, cor, ordem)
    values (p_quadro_id, v_nome, v_cor,
            coalesce((select max(ordem) + 1 from public.pauta_grupos where quadro_id = p_quadro_id), 0))
    returning id into v_id;
  else
    update public.pauta_grupos set nome = v_nome, cor = v_cor where id = p_id
    returning id into v_id;
    if v_id is null then
      return jsonb_build_object('ok', false, 'erro', 'esse grupo não existe mais');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- Remover grupo só quando ele está VAZIO. Mover as pautas pra outro grupo em
-- silêncio seria pior que recusar: quem apaga não faz ideia de onde o trabalho
-- foi parar. A recusa diz quantas estão dentro e o que fazer, que é o mesmo
-- desenho da recusa do quadro logo acima.
create or replace function public.admin_grupo_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_grupo public.pauta_grupos;
  v_itens bigint;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nos grupos';
  end if;

  select * into v_grupo from public.pauta_grupos where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  select count(*) into v_itens from public.pautas where grupo_id = p_id;
  if v_itens > 0 then
    return jsonb_build_object('ok', false, 'erro',
      'esse grupo tem ' || v_itens || ' pauta(s) dentro. move elas pra outro grupo antes');
  end if;

  delete from public.pauta_grupos where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'grupo_removido', 'pauta_grupos', p_id::text,
          jsonb_build_object('nome', v_grupo.nome));

  return jsonb_build_object('ok', true);
end;
$$;

-- Recolher/abrir o grupo. Mora no banco (não no navegador) porque grupo fechado
-- é decisão do quadro: a casa fecha "feitas" uma vez e vale pra quem abrir depois.
create or replace function public.admin_grupo_recolher(p_id uuid, p_recolhido boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nos grupos';
  end if;
  update public.pauta_grupos set recolhido = coalesce(p_recolhido, true)
   where id = p_id returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'esse grupo não existe mais');
  end if;
  return jsonb_build_object('ok', true, 'recolhido', coalesce(p_recolhido, true));
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. A pauta: criar/editar já com quadro e grupo.
--    A assinatura mudou (ganhou quadro e grupo), então a versão da 0043 sai de
--    cena — `create or replace` não muda lista de parâmetro.
-- -----------------------------------------------------------------------------
drop function if exists public.admin_pauta_salvar(uuid, text, text, uuid, date, text);
drop function if exists public.admin_pautas_listar(text, uuid, text, int);

create or replace function public.admin_pauta_salvar(
  p_id          uuid,
  p_quadro_id   uuid,
  p_grupo_id    uuid,
  p_titulo      text,
  p_briefing    text,
  p_atribuido_a uuid,
  p_prazo       date,
  p_prioridade  text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_titulo text := btrim(coalesce(p_titulo, ''));
  v_prio   text := coalesce(nullif(btrim(coalesce(p_prioridade, '')), ''), 'normal');
  v_quadro uuid := p_quadro_id;
  v_grupo  uuid := p_grupo_id;
  v_id     uuid;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;
  if char_length(v_titulo) < 1 or char_length(v_titulo) > 120 then
    return jsonb_build_object('ok', false, 'erro', 'a pauta precisa de um título de até 120 letras');
  end if;
  if v_prio not in ('baixa', 'normal', 'alta') then
    v_prio := 'normal';
  end if;
  if p_atribuido_a is not null
     and not exists (
       select 1 from public.profiles p
        where p.id = p_atribuido_a
          and (p.role = 'owner'
               or exists (select 1 from public.staff_permissions sp where sp.user_id = p.id))
     ) then
    return jsonb_build_object('ok', false, 'erro', 'essa pessoa não é da equipe do console');
  end if;

  if p_id is null then
    if v_quadro is null then
      select id into v_quadro from public.pauta_quadros where not arquivado order by ordem, created_at limit 1;
    end if;
    if v_quadro is null then
      return jsonb_build_object('ok', false, 'erro', 'cria um quadro antes de escrever a primeira pauta');
    end if;
    -- Grupo não informado (ou de outro quadro) cai no primeiro do quadro.
    if v_grupo is null or not exists (select 1 from public.pauta_grupos where id = v_grupo and quadro_id = v_quadro) then
      select id into v_grupo from public.pauta_grupos where quadro_id = v_quadro order by ordem, created_at limit 1;
    end if;

    insert into public.pautas (titulo, briefing, atribuido_a, prazo, prioridade, criado_por,
                               quadro_id, grupo_id, ordem)
    values (v_titulo, nullif(btrim(coalesce(p_briefing, '')), ''), p_atribuido_a, p_prazo, v_prio, v_uid,
            v_quadro, v_grupo,
            coalesce((select max(ordem) + 1 from public.pautas where grupo_id = v_grupo), 0))
    returning id into v_id;
  else
    update public.pautas
       set titulo      = v_titulo,
           briefing    = nullif(btrim(coalesce(p_briefing, '')), ''),
           atribuido_a = p_atribuido_a,
           prazo       = p_prazo,
           prioridade  = v_prio,
           grupo_id    = coalesce(
                           (select g.id from public.pauta_grupos g
                             where g.id = p_grupo_id and g.quadro_id = public.pautas.quadro_id),
                           grupo_id),
           updated_at  = now()
     where id = p_id
    returning id into v_id;

    if v_id is null then
      return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
    end if;
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, case when p_id is null then 'pauta_criada' else 'pauta_editada' end,
          'pautas', v_id::text, jsonb_build_object('titulo', v_titulo));

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. Edição de célula (é o que faz o quadro parecer um quadro): clicar no
--    status, no responsável, na data ou na urgência e mudar ali mesmo.
--    O campo é WHITELIST: nada de nome de coluna vindo do client em SQL solto.
-- -----------------------------------------------------------------------------
create or replace function public.admin_pauta_celula(p_id uuid, p_campo text, p_valor text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_campo text := btrim(coalesce(p_campo, ''));
  v_valor text := nullif(btrim(coalesce(p_valor, '')), '');
  v_id    uuid;
  v_alvo  uuid;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;

  if v_campo = 'status' then
    if v_valor is null or v_valor not in ('aberta', 'fazendo', 'travada', 'feita') then
      return jsonb_build_object('ok', false, 'erro', 'esse estado não existe no quadro');
    end if;
    update public.pautas
       set status        = v_valor,
           concluida_em  = case when v_valor = 'feita' then now() else null end,
           concluida_por = case when v_valor = 'feita' then v_uid else null end,
           updated_at    = now()
     where id = p_id returning id into v_id;

  elsif v_campo = 'prioridade' then
    if v_valor is null or v_valor not in ('baixa', 'normal', 'alta') then
      return jsonb_build_object('ok', false, 'erro', 'essa urgência não existe');
    end if;
    update public.pautas set prioridade = v_valor, updated_at = now()
     where id = p_id returning id into v_id;

  elsif v_campo = 'prazo' then
    update public.pautas set prazo = v_valor::date, updated_at = now()
     where id = p_id returning id into v_id;

  elsif v_campo = 'atribuido_a' then
    v_alvo := v_valor::uuid;
    if v_alvo is not null
       and not exists (
         select 1 from public.profiles p
          where p.id = v_alvo
            and (p.role = 'owner'
                 or exists (select 1 from public.staff_permissions sp where sp.user_id = p.id))
       ) then
      return jsonb_build_object('ok', false, 'erro', 'essa pessoa não é da equipe do console');
    end if;
    update public.pautas set atribuido_a = v_alvo, updated_at = now()
     where id = p_id returning id into v_id;

  elsif v_campo = 'grupo_id' then
    v_alvo := v_valor::uuid;
    if v_alvo is null or not exists (
         select 1 from public.pauta_grupos g
          join public.pautas p on p.quadro_id = g.quadro_id
         where g.id = v_alvo and p.id = p_id) then
      return jsonb_build_object('ok', false, 'erro', 'esse grupo não é deste quadro');
    end if;
    update public.pautas
       set grupo_id = v_alvo,
           ordem    = coalesce((select max(ordem) + 1 from public.pautas where grupo_id = v_alvo), 0),
           updated_at = now()
     where id = p_id returning id into v_id;

  else
    return jsonb_build_object('ok', false, 'erro', 'esse campo não se edita por aqui');
  end if;

  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;
  return jsonb_build_object('ok', true, 'campo', v_campo, 'valor', v_valor);
exception
  -- Data ruim e uuid ruim NÃO estouram no mesmo código: 'banana'::date é 22007
  -- (invalid_datetime_format) e 'banana'::uuid é 22P02 (invalid_text_representation).
  -- Sem os dois na lista, uma data digitada errada subia como erro cru do Postgres
  -- em vez do recado da casa.
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    return jsonb_build_object('ok', false, 'erro', 'esse valor não serve pra esse campo');
end;
$$;

-- -----------------------------------------------------------------------------
-- 9. Ordem dentro do grupo: sobe e desce trocando com o vizinho.
--    Sem arrastar: o console é usado no celular, com uma mão só.
-- -----------------------------------------------------------------------------
create or replace function public.admin_pauta_ordenar(p_id uuid, p_direcao text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_pauta   public.pautas;
  v_vizinho public.pautas;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;

  select * into v_pauta from public.pautas where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;

  if p_direcao = 'cima' then
    select * into v_vizinho from public.pautas
     where grupo_id is not distinct from v_pauta.grupo_id
       and quadro_id = v_pauta.quadro_id
       and (ordem, created_at) < (v_pauta.ordem, v_pauta.created_at)
     order by ordem desc, created_at desc limit 1 for update;
  elsif p_direcao = 'baixo' then
    select * into v_vizinho from public.pautas
     where grupo_id is not distinct from v_pauta.grupo_id
       and quadro_id = v_pauta.quadro_id
       and (ordem, created_at) > (v_pauta.ordem, v_pauta.created_at)
     order by ordem asc, created_at asc limit 1 for update;
  else
    return jsonb_build_object('ok', false, 'erro', 'só dá pra mover pra cima ou pra baixo');
  end if;

  if v_vizinho.id is null then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  -- Empate de `ordem` (todo mundo em 0, por exemplo) não trocaria nada só
  -- invertendo os valores; por isso a troca é feita com números distintos.
  update public.pautas set ordem = v_vizinho.ordem, updated_at = now() where id = v_pauta.id;
  update public.pautas set ordem = case when v_vizinho.ordem = v_pauta.ordem
                                        then case when p_direcao = 'cima' then v_pauta.ordem + 1
                                                  else v_pauta.ordem - 1 end
                                        else v_pauta.ordem end,
                           updated_at = now()
   where id = v_vizinho.id;

  return jsonb_build_object('ok', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- 9b. admin_pauta_ver — tudo de UMA pauta (o painel que abre ao tocar na linha).
--     Existe porque a alternativa é o front relistar o quadro inteiro e achar a
--     linha no client, que é o que a versão anterior fazia: baixar até 300 itens
--     pra ler um. Aqui vem a pauta e a conversa dela numa viagem.
-- -----------------------------------------------------------------------------
create or replace function public.admin_pauta_ver(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_item jsonb;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra ver a pauta';
  end if;

  select jsonb_build_object(
           'id', p.id,
           'titulo', p.titulo,
           'briefing', p.briefing,
           'quadro_id', p.quadro_id,
           'grupo_id', p.grupo_id,
           'grupo_nome', coalesce(g.nome, ''),
           'atribuido_a', p.atribuido_a,
           'atribuido_nome', coalesce(pa.full_name, ''),
           'prazo', p.prazo,
           'prioridade', p.prioridade,
           'status', p.status,
           'criado_por', p.criado_por,
           'criado_por_nome', coalesce(pc.full_name, ''),
           'concluida_em', p.concluida_em,
           'concluida_por_nome', coalesce(pf.full_name, ''),
           'created_at', p.created_at,
           'updated_at', p.updated_at)
    into v_item
    from public.pautas p
    left join public.pauta_grupos g on g.id = p.grupo_id
    left join public.profiles pa on pa.id = p.atribuido_a
    left join public.profiles pc on pc.id = p.criado_por
    left join public.profiles pf on pf.id = p.concluida_por
   where p.id = p_id;

  if v_item is null then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;

  return jsonb_build_object(
    'ok', true,
    'pauta', v_item,
    'comentarios', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', u.id,
               'texto', u.texto,
               'autor_nome', coalesce(nullif(btrim(coalesce(pr.full_name, '')), ''), u.autor_nome, 'alguém da equipe'),
               'user_id', u.user_id,
               'created_at', u.created_at) order by u.created_at)
        from public.pauta_updates u
        left join public.profiles pr on pr.id = u.user_id
       where u.pauta_id = p_id), '[]'::jsonb));
end;
$$;

-- -----------------------------------------------------------------------------
-- 10. Comentários da pauta.
-- -----------------------------------------------------------------------------
create or replace function public.admin_pauta_comentarios(p_pauta_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra ver a pauta';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', u.id,
             'texto', u.texto,
             'autor_nome', coalesce(nullif(btrim(coalesce(pr.full_name, '')), ''), u.autor_nome, 'alguém da equipe'),
             'user_id', u.user_id,
             'created_at', u.created_at) order by u.created_at)
      from public.pauta_updates u
      left join public.profiles pr on pr.id = u.user_id
     where u.pauta_id = p_pauta_id), '[]'::jsonb);
end;
$$;

create or replace function public.admin_pauta_comentar(p_pauta_id uuid, p_texto text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_texto text := btrim(coalesce(p_texto, ''));
  v_id    uuid;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra comentar';
  end if;
  if char_length(v_texto) < 1 or char_length(v_texto) > 2000 then
    return jsonb_build_object('ok', false, 'erro', 'escreve o recado (até 2000 letras)');
  end if;
  if not exists (select 1 from public.pautas where id = p_pauta_id) then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;

  insert into public.pauta_updates (pauta_id, user_id, autor_nome, texto)
  values (p_pauta_id, v_uid,
          (select coalesce(full_name, '') from public.profiles where id = v_uid),
          v_texto)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

create or replace function public.admin_pauta_comentario_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_com public.pauta_updates;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nos comentários';
  end if;
  select * into v_com from public.pauta_updates where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;
  if not (public.is_owner() or v_com.user_id = v_uid) then
    return jsonb_build_object('ok', false, 'erro', 'esse recado é de quem escreveu');
  end if;
  delete from public.pauta_updates where id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- 11. Permissões das funções.
-- -----------------------------------------------------------------------------
revoke all on function public.admin_quadros_listar()                              from public, anon;
revoke all on function public.admin_quadro_abrir(uuid, text, uuid)                from public, anon;
revoke all on function public.admin_quadro_salvar(uuid, text, text)               from public, anon;
revoke all on function public.admin_quadro_remover(uuid)                          from public, anon;
revoke all on function public.admin_quadro_arquivar(uuid, boolean)                from public, anon;
revoke all on function public.admin_grupo_salvar(uuid, uuid, text, text)          from public, anon;
revoke all on function public.admin_grupo_remover(uuid)                           from public, anon;
revoke all on function public.admin_grupo_recolher(uuid, boolean)                 from public, anon;
revoke all on function public.admin_pauta_ver(uuid)                               from public, anon;
revoke all on function public.admin_pauta_salvar(uuid, uuid, uuid, text, text, uuid, date, text) from public, anon;
revoke all on function public.admin_pauta_celula(uuid, text, text)                from public, anon;
revoke all on function public.admin_pauta_ordenar(uuid, text)                     from public, anon;
revoke all on function public.admin_pauta_comentarios(uuid)                       from public, anon;
revoke all on function public.admin_pauta_comentar(uuid, text)                    from public, anon;
revoke all on function public.admin_pauta_comentario_remover(uuid)                from public, anon;

grant execute on function public.admin_quadros_listar()                           to authenticated;
grant execute on function public.admin_quadro_abrir(uuid, text, uuid)             to authenticated;
grant execute on function public.admin_quadro_salvar(uuid, text, text)            to authenticated;
grant execute on function public.admin_quadro_remover(uuid)                       to authenticated;
grant execute on function public.admin_quadro_arquivar(uuid, boolean)             to authenticated;
grant execute on function public.admin_grupo_salvar(uuid, uuid, text, text)       to authenticated;
grant execute on function public.admin_grupo_remover(uuid)                        to authenticated;
grant execute on function public.admin_pauta_salvar(uuid, uuid, uuid, text, text, uuid, date, text) to authenticated;
grant execute on function public.admin_pauta_celula(uuid, text, text)             to authenticated;
grant execute on function public.admin_pauta_ordenar(uuid, text)                  to authenticated;
grant execute on function public.admin_pauta_comentarios(uuid)                    to authenticated;
grant execute on function public.admin_pauta_comentar(uuid, text)                 to authenticated;
grant execute on function public.admin_pauta_comentario_remover(uuid)             to authenticated;



-- ===== 0046_permissao_por_pagina.sql =====

-- =============================================================================
-- 0046_permissao_por_pagina.sql — acesso página por página 🔑
--
-- O PEDIDO: "dar permissão customizada pra dar ou não dar acesso a certas
-- páginas e ações".
--
-- O QUE ESTAVA NO CAMINHO: o console tinha 8 permissões pra 19 abas, então
-- várias abas andavam grudadas. Quem recebia 'relatorios' pra ver o que a loja
-- vendeu levava junto a lista de e-mails do rodapé e os pedidos de evento (com
-- nome e telefone de quem pediu). Quem recebia 'resgates' pra entregar
-- recompensa no balcão levava junto os códigos dos presentes vendidos. E três
-- abas (recados, trilha, agenda) eram do dono e ponto: não havia como delegar
-- nem que a casa quisesse, porque as funções delas perguntavam `is_owner()`.
--
-- O QUE ESTE ARQUIVO FAZ:
--   1. Abre o whitelist de permissões (o CHECK fechado da 0017) pra 19 slugs,
--      um por aba, mais as ações.
--   2. Troca a trava de 21 funções: cada uma passa a pedir a permissão DA
--      PRÓPRIA PÁGINA. O corpo delas é idêntico ao que já estava no ar (foi
--      extraído da última versão de cada uma), só a linha da trava muda.
--   3. As três abas do dono deixam de perguntar `is_owner()` e passam a
--      perguntar `tem_permissao(...)`. **O dono não perde nada**: a
--      `tem_permissao` responde verdadeiro pra owner em qualquer slug (0017,
--      reforçada na 0032). O que muda é que agora dá pra DELEGAR.
--   4. BACKFILL: quem já tinha a permissão larga recebe as novas que saíram de
--      dentro dela, uma por uma. Ninguém perde acesso na virada, e daqui pra
--      frente a casa tira o que não quiser dar.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. O whitelist, agora com uma permissão por página.
--    O CHECK nasceu inline na 0017 e foi mexido pela 0043, então o nome dele
--    pode variar: acha pelo conteúdo, não pelo nome.
-- -----------------------------------------------------------------------------
do $$
declare
  v_nome text;
begin
  select con.conname into v_nome
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
   where nsp.nspname = 'public' and rel.relname = 'staff_permissions' and con.contype = 'c'
     and pg_get_constraintdef(con.oid) ilike '%dashboard%'
   limit 1;
  if v_nome is not null then
    execute format('alter table public.staff_permissions drop constraint %I', v_nome);
  end if;

  alter table public.staff_permissions
    add constraint staff_permissions_permissao_check
    check (permissao in (
      -- o dia a dia
      'dashboard', 'pautas',
      -- a loja e o balcão
      'pedidos', 'entregas', 'resgates', 'aniversarios', 'presentes',
      -- a gente
      'usuarios', 'mural', 'equipe',
      -- o que a casa lê
      'relatorios', 'favoritos', 'desejos', 'reposicao', 'lista_espera', 'leads',
      -- o que a casa publica
      'avisos', 'trilha', 'agenda'));
end $$;

-- -----------------------------------------------------------------------------
-- 2. Backfill: ninguém perde o que já tinha.
--    Quem tem a permissão larga ganha, explicitamente, as que saíram de dentro
--    dela. A partir daqui a casa pode tirar uma a uma.
-- -----------------------------------------------------------------------------
insert into public.staff_permissions (user_id, permissao, granted_by)
select sp.user_id, nova.permissao, sp.granted_by
  from public.staff_permissions sp
  join (values
          ('resgates',   'aniversarios'),
          ('resgates',   'presentes'),
          ('usuarios',   'mural'),
          ('relatorios', 'favoritos'),
          ('relatorios', 'desejos'),
          ('relatorios', 'reposicao'),
          ('relatorios', 'lista_espera'),
          ('relatorios', 'leads')
       ) as nova(de, permissao) on nova.de = sp.permissao
on conflict (user_id, permissao) do nothing;

-- -----------------------------------------------------------------------------
-- 3. As 21 funções, com a trava da própria página.
--    Corpo idêntico ao que estava no ar; só a linha do `if not public...` muda.
--    `create or replace` preserva os grants que cada uma já tinha.
-- -----------------------------------------------------------------------------

-- admin_brindes_listar → pede 'aniversarios'
create or replace function public.admin_brindes_listar(
  p_busca  text default null,
  p_status text default null,
  p_limite integer default 200
)
returns table (
  id                uuid,
  criado_em         timestamptz,
  codigo            text,
  situacao          text,
  valido_ate_label  text,
  aniversario       text,
  cliente_nome      text,
  cliente_email     text,
  usado_em          timestamptz,
  usado_por_nome    text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not public.tem_permissao('aniversarios') then
    raise exception 'sem permissão pra ver os brindes';
  end if;

  return query
    select
      b.id,
      b.criado_em,
      b.codigo,
      case when b.status = 'usado' then 'usado'
           when b.valido_ate < v_hoje then 'expirado'
           else 'ativo' end                        as situacao,
      to_char(b.valido_ate, 'DD/MM')               as valido_ate_label,
      to_char(pr.nascimento, 'DD/MM')              as aniversario,
      coalesce(pr.apelido, pr.full_name, '')       as cliente_nome,
      coalesce(u.email::text, '')                  as cliente_email,
      b.usado_em,
      coalesce(baixa.full_name, '')                as usado_por_nome
    from public.brindes_aniversario b
    left join public.profiles pr    on pr.id = b.user_id
    left join auth.users      u     on u.id  = b.user_id
    left join public.profiles baixa on baixa.id = b.usado_por
    where (v_busca is null
           or b.codigo ilike '%' || v_busca || '%'
           or pr.full_name ilike '%' || v_busca || '%'
           or pr.apelido ilike '%' || v_busca || '%')
      and (
        p_status is null
        or (p_status = 'usado'    and b.status = 'usado')
        or (p_status = 'ativo'    and b.status = 'ativo' and b.valido_ate >= v_hoje)
        or (p_status = 'expirado' and b.status = 'ativo' and b.valido_ate <  v_hoje)
      )
    order by b.criado_em desc
    limit greatest(1, least(coalesce(p_limite, 200), 500));
end;
$$;

-- admin_brinde_usar → pede 'aniversarios'
create or replace function public.admin_brinde_usar(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_brinde public.brindes_aniversario;
begin
  if not public.tem_permissao('aniversarios') then
    raise exception 'sem permissão pra dar baixa em brinde';
  end if;

  select * into v_brinde from public.brindes_aniversario where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'brinde não encontrado');
  end if;

  if v_brinde.status = 'usado' then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'usado_em', v_brinde.usado_em);
  end if;

  if v_brinde.valido_ate < v_hoje then
    return jsonb_build_object('ok', false, 'erro',
      'esse código venceu em ' || to_char(v_brinde.valido_ate, 'DD/MM'));
  end if;

  update public.brindes_aniversario
     set status = 'usado', usado_em = now(), usado_por = v_uid
   where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'brinde_aniversario_usado', 'brindes_aniversario', p_id::text,
          jsonb_build_object('codigo', v_brinde.codigo));

  return jsonb_build_object('ok', true, 'usado_em', now());
end;
$$;

-- admin_presentes → pede 'presentes'
create or replace function public.admin_presentes(
  p_busca  text default null,
  p_status text default null,
  p_limite int default 300
)
returns table (
  id                 uuid,
  tier_slug          text,
  tier_nome          text,
  valor_centavos     integer,
  codigo             text,
  status             text,
  comprador_nome     text,
  comprador_email    text,
  resgatado_por_nome text,
  resgatado_em       timestamptz,
  created_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('presentes') then
    raise exception 'sem permissão pra ver os presentes';
  end if;

  return query
    select
      g.id,
      g.tier_slug,
      coalesce(t.nome, g.tier_slug)      as tier_nome,
      g.valor_centavos,
      g.codigo,
      g.status,
      coalesce(pc.full_name, '')         as comprador_nome,
      coalesce(uc.email::text, '')       as comprador_email,
      coalesce(pr.full_name, '')         as resgatado_por_nome,
      g.resgatado_em,
      g.created_at
      from public.gift_subscriptions g
      left join public.tiers      t  on t.slug = g.tier_slug
      left join public.profiles   pc on pc.id  = g.comprador_id
      left join auth.users        uc on uc.id  = g.comprador_id
      left join public.profiles   pr on pr.id  = g.resgatado_por
     where (p_status is null or p_status = '' or g.status = p_status)
       and (
         v_busca is null
         or g.codigo ilike '%' || v_busca || '%'
         or coalesce(pc.full_name, '') ilike '%' || v_busca || '%'
         or coalesce(uc.email::text, '') ilike '%' || v_busca || '%'
         or coalesce(pr.full_name, '') ilike '%' || v_busca || '%'
       )
     order by g.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 2000));
end;
$$;

-- admin_mural_listar → pede 'mural'
create or replace function public.admin_mural_listar(
  p_busca  text default null,
  p_status text default null,
  p_limite int  default 300
)
returns table (
  id         uuid,
  autor_nome text,
  texto      text,
  status     text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('mural') then
    raise exception 'sem permissão pra cuidar do mural';
  end if;

  return query
    select m.id, coalesce(m.autor_nome, ''), m.texto, m.status, m.created_at
      from public.mural_notes m
     where (p_status is null or p_status = '' or m.status = p_status)
       and (
         v_busca is null
         or m.texto ilike '%' || v_busca || '%'
         or coalesce(m.autor_nome, '') ilike '%' || v_busca || '%'
       )
     order by m.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 1000));
end;
$$;

-- admin_mural_status → pede 'mural'
create or replace function public.admin_mural_status(p_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_novo text := btrim(coalesce(p_status, ''));
  v_id   uuid;
begin
  if not public.tem_permissao('mural') then
    raise exception 'sem permissão pra cuidar do mural';
  end if;
  if v_novo not in ('aprovado', 'oculto') then
    return jsonb_build_object('ok', false, 'erro', 'esse estado não existe no mural');
  end if;

  update public.mural_notes set status = v_novo where id = p_id
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'esse recado não existe mais');
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'mural_status', 'mural_notes', p_id::text,
          jsonb_build_object('status', v_novo));

  return jsonb_build_object('ok', true, 'status', v_novo);
end;
$$;

-- admin_mural_remover → pede 'mural'
create or replace function public.admin_mural_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_nota public.mural_notes;
begin
  if not public.tem_permissao('mural') then
    raise exception 'sem permissão pra cuidar do mural';
  end if;

  select * into v_nota from public.mural_notes where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  delete from public.mural_notes where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'mural_removido', 'mural_notes', p_id::text,
          jsonb_build_object('autor_nome', coalesce(v_nota.autor_nome, ''),
                             'texto', v_nota.texto));

  return jsonb_build_object('ok', true);
end;
$$;

-- admin_cardapio_favoritos → pede 'favoritos'
create or replace function public.admin_cardapio_favoritos()
returns table (
  item_slug  text,
  item_nome  text,
  favoritos  bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('favoritos') then
    raise exception 'sem permissão pra ver os favoritos';
  end if;
  return query
    select
      f.item_slug,
      (select f2.item_nome
         from public.cardapio_favoritos f2
        where f2.item_slug = f.item_slug
        group by f2.item_nome
        order by count(*) desc, f2.item_nome asc
        limit 1)                as item_nome,
      count(*)::bigint          as favoritos
    from public.cardapio_favoritos f
    group by f.item_slug
    order by count(*) desc, item_nome asc;
end;
$$;

-- admin_loja_desejos → pede 'desejos'
create or replace function public.admin_loja_desejos()
returns table (
  produto_slug text,
  produto_nome text,
  desejos      bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('desejos') then
    raise exception 'sem permissão pra ver os desejos';
  end if;
  return query
    select
      d.produto_slug,
      (select d2.produto_nome
         from public.loja_desejos d2
        where d2.produto_slug = d.produto_slug
        group by d2.produto_nome
        order by count(*) desc, d2.produto_nome asc
        limit 1)                as produto_nome,
      count(*)::bigint          as desejos
    from public.loja_desejos d
    group by d.produto_slug
    order by count(*) desc, produto_nome asc;
end;
$$;

-- admin_avisos_reposicao → pede 'reposicao'
create or replace function public.admin_avisos_reposicao()
returns table (
  produto_slug text,
  produto_nome text,
  esperando    bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('reposicao') then
    raise exception 'sem permissão pra ver os avisos de reposição';
  end if;
  return query
    select
      a.produto_slug,
      (select a2.produto_nome
         from public.avisos_reposicao a2
        where a2.produto_slug = a.produto_slug
        group by a2.produto_nome
        order by count(*) desc, a2.produto_nome asc
        limit 1)                as produto_nome,
      count(*)::bigint          as esperando
    from public.avisos_reposicao a
    group by a.produto_slug
    order by count(*) desc, produto_nome asc;
end;
$$;

-- admin_lista_espera → pede 'lista_espera'
create or replace function public.admin_lista_espera(p_limite int default 500)
returns table (
  id         uuid,
  email      text,
  origem     text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('lista_espera') then
    raise exception 'sem permissão pra ver a lista de espera';
  end if;
  return query
    select e.id, e.email, e.origem, e.created_at
      from public.lista_espera e
     order by e.created_at desc
     limit greatest(1, least(coalesce(p_limite, 500), 2000));
end;
$$;

-- admin_leads_evento → pede 'leads'
create or replace function public.admin_leads_evento(
  p_busca  text default null,
  p_status text default null,
  p_limite int default 300
)
returns table (
  id              uuid,
  nome            text,
  contato         text,
  email           text,
  tipo            text,
  data_pretendida date,
  pessoas         int,
  mensagem        text,
  origem          text,
  status          text,
  created_at      timestamptz,
  atendido_em     timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('leads') then
    raise exception 'sem permissão pra ver os pedidos de evento';
  end if;

  return query
    select l.id, l.nome, l.contato, l.email, l.tipo, l.data_pretendida, l.pessoas,
           l.mensagem, l.origem, l.status, l.created_at, l.atendido_em
      from public.leads_evento l
     where (p_status is null or p_status = '' or l.status = p_status)
       and (
         v_busca is null
         or l.nome ilike '%' || v_busca || '%'
         or l.contato ilike '%' || v_busca || '%'
         or coalesce(l.email, '') ilike '%' || v_busca || '%'
         or l.tipo ilike '%' || v_busca || '%'
       )
     order by l.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 2000));
end;
$$;

-- admin_lead_evento_status → pede 'leads'
create or replace function public.admin_lead_evento_status(p_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_status text := btrim(coalesce(p_status, ''));
begin
  if not public.tem_permissao('leads') then
    raise exception 'sem permissão pra mexer nos pedidos de evento';
  end if;

  if v_status not in ('novo', 'atendido', 'arquivado') then
    raise exception 'status inválido';
  end if;

  update public.leads_evento
     set status       = v_status,
         atendido_em  = case when v_status = 'novo' then null else now() end,
         atendido_por = case when v_status = 'novo' then null else v_uid end
   where id = p_id;

  if not found then
    raise exception 'pedido não encontrado';
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'lead_evento_status', 'leads_evento', p_id::text,
          jsonb_build_object('status', v_status));

  return jsonb_build_object('ok', true, 'status', v_status);
end;
$$;

-- admin_avisos_listar → pede 'avisos'
create or replace function public.admin_avisos_listar()
returns setof public.avisos_casa
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('avisos') then
    raise exception 'sem permissão';
  end if;
  return query
    select * from public.avisos_casa
    order by ativo desc, prioridade desc, created_at desc;
end;
$$;

-- admin_aviso_salvar → pede 'avisos'
create or replace function public.admin_aviso_salvar(
  p_id         uuid,
  p_texto      text,
  p_emoji      text,
  p_link_url   text,
  p_link_label text,
  p_inicio     timestamptz,
  p_fim        timestamptz,
  p_prioridade integer,
  p_ativo      boolean
)
returns public.avisos_casa
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_texto text := btrim(coalesce(p_texto, ''));
  v_row   public.avisos_casa;
begin
  if not public.tem_permissao('avisos') then
    raise exception 'sem permissão';
  end if;
  if char_length(v_texto) < 1 then
    raise exception 'o recado não pode ser vazio';
  end if;

  if p_id is null then
    insert into public.avisos_casa
      (texto, emoji, link_url, link_label, inicio_em, fim_em, prioridade, ativo, created_by)
    values
      (v_texto, nullif(btrim(coalesce(p_emoji, '')), ''),
       nullif(btrim(coalesce(p_link_url, '')), ''),
       nullif(btrim(coalesce(p_link_label, '')), ''),
       p_inicio, p_fim, coalesce(p_prioridade, 0), coalesce(p_ativo, true), v_uid)
    returning * into v_row;
  else
    update public.avisos_casa set
      texto      = v_texto,
      emoji      = nullif(btrim(coalesce(p_emoji, '')), ''),
      link_url   = nullif(btrim(coalesce(p_link_url, '')), ''),
      link_label = nullif(btrim(coalesce(p_link_label, '')), ''),
      inicio_em  = p_inicio,
      fim_em     = p_fim,
      prioridade = coalesce(p_prioridade, 0),
      ativo      = coalesce(p_ativo, true),
      updated_at = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'recado não encontrado';
    end if;
  end if;

  return v_row;
end;
$$;

-- admin_aviso_remover → pede 'avisos'
create or replace function public.admin_aviso_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('avisos') then
    raise exception 'sem permissão';
  end if;
  delete from public.avisos_casa where id = p_id;
  return true;
end;
$$;

-- admin_trilha_listar → pede 'trilha'
create or replace function public.admin_trilha_listar()
returns setof public.playlists_casa
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('trilha') then
    raise exception 'sem permissão';
  end if;
  return query
    select * from public.playlists_casa
    order by ativo desc, ordem asc, created_at asc;
end;
$$;

-- admin_trilha_salvar → pede 'trilha'
create or replace function public.admin_trilha_salvar(
  p_id       uuid,
  p_nome     text,
  p_clima    text,
  p_url      text,
  p_ordem    integer,
  p_ativo    boolean,
  p_tocando  boolean
)
returns public.playlists_casa
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_url  text := btrim(coalesce(p_url, ''));
  v_toca boolean := coalesce(p_tocando, false);
  v_row  public.playlists_casa;
begin
  if not public.tem_permissao('trilha') then
    raise exception 'sem permissão';
  end if;
  if char_length(v_nome) < 1 then
    raise exception 'dá um nome pra playlist';
  end if;
  if char_length(v_url) < 1 then
    raise exception 'cola o link do Spotify';
  end if;

  -- Só uma toca por vez: zera as outras antes (o unique index reforça).
  if v_toca then
    update public.playlists_casa set tocando = false
     where tocando = true and (p_id is null or id <> p_id);
  end if;

  if p_id is null then
    insert into public.playlists_casa (nome, clima, spotify_url, ordem, ativo, tocando, created_by)
    values (v_nome, nullif(btrim(coalesce(p_clima, '')), ''), v_url,
            coalesce(p_ordem, 0), coalesce(p_ativo, true), v_toca, v_uid)
    returning * into v_row;
  else
    update public.playlists_casa set
      nome        = v_nome,
      clima       = nullif(btrim(coalesce(p_clima, '')), ''),
      spotify_url = v_url,
      ordem       = coalesce(p_ordem, 0),
      ativo       = coalesce(p_ativo, true),
      tocando     = v_toca,
      updated_at  = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'playlist não encontrada';
    end if;
  end if;

  return v_row;
end;
$$;

-- admin_trilha_remover → pede 'trilha'
create or replace function public.admin_trilha_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('trilha') then
    raise exception 'sem permissão';
  end if;
  delete from public.playlists_casa where id = p_id;
  return true;
end;
$$;

-- admin_eventos_listar → pede 'agenda'
create or replace function public.admin_eventos_listar()
returns table (
  id           uuid,
  nome         text,
  descricao    text,
  data         timestamptz,
  local        text,
  vagas        integer,
  ativo        boolean,
  confirmados  bigint,
  created_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('agenda') then
    raise exception 'sem permissão';
  end if;
  return query
    select e.id, e.nome, e.descricao, e.data, e.local, e.vagas, e.ativo,
           (select count(*) from public.event_rsvps r where r.event_id = e.id) as confirmados,
           e.created_at
    from public.events e
    order by e.data desc nulls last, e.created_at desc;
end;
$$;

-- admin_evento_salvar → pede 'agenda'
create or replace function public.admin_evento_salvar(
  p_id        uuid,
  p_nome      text,
  p_descricao text,
  p_data      timestamptz,
  p_local     text,
  p_vagas     integer,
  p_ativo     boolean
)
returns public.events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome text := btrim(coalesce(p_nome, ''));
  v_row  public.events;
begin
  if not public.tem_permissao('agenda') then
    raise exception 'sem permissão';
  end if;
  if char_length(v_nome) < 1 then
    raise exception 'dá um nome pro encontro';
  end if;
  if p_vagas is not null and p_vagas < 0 then
    raise exception 'vagas não pode ser negativo';
  end if;

  if p_id is null then
    insert into public.events (nome, descricao, data, local, vagas, ativo, updated_at)
    values (v_nome, nullif(btrim(coalesce(p_descricao, '')), ''), p_data,
            nullif(btrim(coalesce(p_local, '')), ''), p_vagas,
            coalesce(p_ativo, true), now())
    returning * into v_row;
  else
    update public.events set
      nome       = v_nome,
      descricao  = nullif(btrim(coalesce(p_descricao, '')), ''),
      data       = p_data,
      local      = nullif(btrim(coalesce(p_local, '')), ''),
      vagas      = p_vagas,
      ativo      = coalesce(p_ativo, true),
      updated_at = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'encontro não encontrado';
    end if;
  end if;

  return v_row;
end;
$$;

-- admin_evento_remover → pede 'agenda'
create or replace function public.admin_evento_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('agenda') then
    raise exception 'sem permissão';
  end if;
  delete from public.events where id = p_id;
  return true;
end;
$$;



-- ===== 0047_permissoes_por_secao.sql =====

-- =============================================================================
-- 0047_permissoes_por_secao.sql — permissão por SEÇÃO do site e por AÇÃO 🔑
--
-- O PEDIDO: "um agrupamento de permissões por seção do site. exemplo: página de
-- vendas, algumas permissões de ação; página de resgate/presentes, permissões de
-- quem enxerga, de quem mexe, de quem arruma."
--
-- O QUE ESTAVA NO CAMINHO: a 0046 deu uma permissão por PÁGINA do console, e
-- isso resolveu o "quem enxerga o quê". Mas dentro de cada página continuava
-- tudo junto: quem recebia `mural` pra esconder um recado podia apagar a parede
-- inteira; quem recebia `leads` pra ler os pedidos de evento podia arquivar;
-- quem recebia `agenda` pra cadastrar um encontro podia apagar um encontro com
-- as presenças todas dentro. Ou seja: enxergar, mexer e arrumar eram a mesma
-- chave. E a fila de 19 permissões era uma lista plana, sem dizer de que parte
-- do SITE cada uma fala.
--
-- O DESENHO NOVO, em três camadas:
--
--   SEÇÃO   um pedaço do site (a loja, o clube, a casa, o cardápio, a gente,
--           os eventos, o dia a dia, o console). É por aqui que a tela da
--           equipe agrupa, então quem dá acesso raciocina "essa pessoa cuida
--           da loja", não "essa pessoa precisa das caixinhas 3, 7 e 12".
--   PÁGINA  uma tela do console dentro daquela seção (os pedidos, os resgates,
--           o mural…). É o que a 0046 chamava de permissão.
--   AÇÃO    o que a pessoa faz naquela página, em três níveis fixos:
--             ver      (1) enxergar
--             mexer    (2) o dia a dia da página: dar baixa, publicar, atender
--             arrumar  (3) o que desfaz, apaga ou mexe em ponto e código
--
-- O slug fica `<pagina>.<acao>` — `pedidos.ver`, `mural.arrumar`. Quem tem um
-- nível ALCANÇA os de baixo na MESMA página (arrumar > mexer > ver), então
-- ninguém fica podendo consertar uma tela que não pode abrir.
--
-- O whitelist deixou de ser um CHECK escrito à mão (que a 0043 e a 0046 já
-- tiveram que reescrever) e virou TABELA: `permissoes`, com FK vinda da
-- `staff_permissions`. Permissão nova daqui pra frente é INSERT numa tabela de
-- catálogo, não `alter constraint`.
--
-- O QUE MAIS ESTE ARQUIVO FAZ:
--   • O "arrumar" passa a EXISTIR: dez funções novas pros consertos que a casa
--     não tinha como fazer (devolver ponto de resgate errado, desfazer baixa de
--     pedido, gerar o código de presente que o webhook não gerou, esticar
--     validade de brunch, lançar ajuste de pontos, tirar e-mail da lista…).
--     Permissão que não abre porta nenhuma é enfeite; estas abrem.
--   • Duas páginas novas no console: **as assinaturas** e **os pontos**, que
--     eram justamente os dois benefícios sobre os quais a casa era cega.
--   • BACKFILL: quem já tinha a permissão da 0046 recebe a fila inteira do que
--     fazia. Ninguém perde nada na virada, e o "arrumar" (que é novidade) só
--     vai pra quem já podia apagar antes.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente.
-- =============================================================================


-- =============================================================================
-- 1. O catálogo: seção › página › ação
-- -----------------------------------------------------------------------------
-- Três tabelas de dicionário. Elas não guardam quem pode o quê (isso continua na
-- `staff_permissions`), guardam o que EXISTE pra poder. RLS ligada: quem lê é
-- quem já entra no console, e a tela da equipe lê pela RPC.
-- =============================================================================

create table if not exists public.permissao_secoes (
  slug       text primary key,
  rotulo     text not null,
  descricao  text,
  ordem      integer not null default 0
);

create table if not exists public.permissao_paginas (
  slug        text primary key,
  secao_slug  text not null references public.permissao_secoes (slug) on delete restrict,
  rotulo      text not null,
  descricao   text,
  -- o id da aba no console (`NAV` do admin.js). Nulo = permissão que não tem
  -- tela própria.
  aba         text,
  ordem       integer not null default 0
);

create table if not exists public.permissoes (
  slug         text primary key,
  pagina_slug  text not null references public.permissao_paginas (slug) on delete restrict,
  -- 'ver' | 'mexer' | 'arrumar'. O nível é o que faz a hierarquia funcionar.
  acao         text not null check (acao in ('ver', 'mexer', 'arrumar')),
  nivel        smallint not null check (nivel between 1 and 3),
  rotulo       text not null,
  descricao    text,
  unique (pagina_slug, acao)
);

-- A ponte de compatibilidade. As policies e as funções que este arquivo NÃO
-- reescreve continuam perguntando pelo slug velho da 0046 (`tem_permissao
-- ('favoritos')`), e a `permissao_canonica` traduz. Sem isto, aplicar a 0047
-- apagaria o acesso de todo mundo até a última função ser reescrita.
create table if not exists public.permissoes_legado (
  slug_velho  text primary key,
  slug_novo   text not null references public.permissoes (slug) on delete restrict
);

alter table public.permissao_secoes   enable row level security;
alter table public.permissao_paginas  enable row level security;
alter table public.permissoes         enable row level security;
alter table public.permissoes_legado  enable row level security;

-- Leitura pra quem entra no console (é dicionário, não dado de ninguém).
-- Escrita: nenhuma policy. O catálogo muda por migration, não por tela.
drop policy if exists permissao_secoes_select on public.permissao_secoes;
create policy permissao_secoes_select on public.permissao_secoes
  for select to authenticated using (public.pode_entrar_no_console());

drop policy if exists permissao_paginas_select on public.permissao_paginas;
create policy permissao_paginas_select on public.permissao_paginas
  for select to authenticated using (public.pode_entrar_no_console());

drop policy if exists permissoes_select on public.permissoes;
create policy permissoes_select on public.permissoes
  for select to authenticated using (public.pode_entrar_no_console());

drop policy if exists permissoes_legado_select on public.permissoes_legado;
create policy permissoes_legado_select on public.permissoes_legado
  for select to authenticated using (public.pode_entrar_no_console());


-- =============================================================================
-- 2. O seed do catálogo — as 8 seções, as 20 páginas, as 43 ações
-- -----------------------------------------------------------------------------
-- A seção é um pedaço do SITE, não uma gaveta do console: é assim que a casa
-- pensa quando decide quem cuida do quê ("fulana cuida da loja", "beltrano
-- cuida do clube").
-- =============================================================================

insert into public.permissao_secoes (slug, rotulo, descricao, ordem) values
  ('dia',      'o dia a dia',   'por onde o turno começa',                              10),
  ('loja',     'a loja',        'o que a casa vende pela internet',                     20),
  ('clube',    'o clube',       'assinatura, pontos, presentes e os mimos de quem é de casa', 30),
  ('cardapio', 'o cardápio',    'o que sai da cozinha e do balcão',                     40),
  ('casa',     'a casa',        'o que a casa publica e o que a turma escreve',         50),
  ('gente',    'a gente',       'quem passa por aqui',                                  60),
  ('eventos',  'os eventos',    'quem quer fazer o evento dele aqui',                   70),
  ('console',  'o console',     'quem entra por esta porta',                            80)
on conflict (slug) do update
  set rotulo = excluded.rotulo, descricao = excluded.descricao, ordem = excluded.ordem;

insert into public.permissao_paginas (slug, secao_slug, rotulo, descricao, aba, ordem) values
  ('painel',       'dia',      'o painel',            'os números do dia',                              'painel',       10),
  ('pautas',       'dia',      'o quadro de pautas',  'o que a casa combinou pra hoje',                 'pautas',       20),

  ('pedidos',      'loja',     'os pedidos',          'a fila de compras da loja',                      'pedidos',      10),
  ('relatorios',   'loja',     'os relatórios',       'o que vendeu e o que saiu por pontos',           'relatorios',   20),
  ('desejos',      'loja',     'ficou pra depois',    'o que a casa mais quer',                         'desejos',      30),
  ('reposicao',    'loja',     'quem espera voltar',  'produto esgotado com fila',                      'esperando',    40),

  ('assinaturas',  'clube',    'as assinaturas',      'quem assina, em que plano e até quando vale',    'assinaturas',  10),
  ('pontos',       'clube',    'os pontos',           'o saldo e o extrato de cada pessoa',             'pontos',       20),
  ('resgates',     'clube',    'os resgates',         'as recompensas trocadas por pontos',             'resgates',     30),
  ('presentes',    'clube',    'os presentes',        'os planos dados de presente',                    'presentes',    40),
  ('aniversarios', 'clube',    'os aniversários',     'o brunch de quem faz aniversário no mês',        'aniversarios', 50),

  ('favoritos',    'cardapio', 'os favoritos',        'o que a casa mais ama',                          'favoritos',    10),

  ('mural',        'casa',     'o mural',             'a parede de recados do /o-casa',                 'mural',        10),
  ('recados',      'casa',     'o recado do topo',    'a tarja que acende no site',                     'recados',      20),
  ('trilha',       'casa',     'a trilha',            'as playlists da home',                           'trilha',       30),
  ('agenda',       'casa',     'a agenda',            'os encontros que a casa promove',                'agenda',       40),

  ('pessoas',      'gente',    'as pessoas',          'quem já passou por aqui',                        'pessoas',      10),
  ('espera',       'gente',    'a lista de espera',   'os e-mails deixados no rodapé',                  'espera',       20),

  ('leads',        'eventos',  'os pedidos de evento','quem quer fazer evento aqui',                    'leads',        10),

  ('equipe',       'console',  'a equipe',            'quem entra no console e alcança o quê',          'equipe',       10)
on conflict (slug) do update
  set secao_slug = excluded.secao_slug, rotulo = excluded.rotulo,
      descricao  = excluded.descricao,  aba    = excluded.aba, ordem = excluded.ordem;

insert into public.permissoes (slug, pagina_slug, acao, nivel, rotulo, descricao) values
  -- o dia a dia -------------------------------------------------------------
  ('painel.ver',        'painel',       'ver',     1, 'enxergar', 'abrir o painel e ler os números do dia'),

  ('pautas.ver',        'pautas',       'ver',     1, 'enxergar', 'ler os quadros, as pautas e os comentários'),
  ('pautas.mexer',      'pautas',       'mexer',   2, 'mexer',    'criar, editar, mover e comentar'),
  ('pautas.arrumar',    'pautas',       'arrumar', 3, 'arrumar',  'apagar pauta, quadro, grupo ou comentário'),

  -- a loja -------------------------------------------------------------------
  ('pedidos.ver',       'pedidos',      'ver',     1, 'enxergar', 'ver a fila de compras e o que tem dentro'),
  ('pedidos.mexer',     'pedidos',      'mexer',   2, 'mexer',    'dar baixa: confirmar entregue ou retirado'),
  ('pedidos.arrumar',   'pedidos',      'arrumar', 3, 'arrumar',  'mudar o estado do pedido na mão, inclusive desfazer uma baixa'),

  ('relatorios.ver',    'relatorios',   'ver',     1, 'enxergar', 'ler o que vendeu e o que saiu por pontos'),
  ('desejos.ver',       'desejos',      'ver',     1, 'enxergar', 'ver o que a casa mais quer'),
  ('reposicao.ver',     'reposicao',    'ver',     1, 'enxergar', 'ver quem espera cada produto voltar'),

  -- o clube ------------------------------------------------------------------
  ('assinaturas.ver',   'assinaturas',  'ver',     1, 'enxergar', 'ver quem assina, o plano e até quando vale'),
  ('assinaturas.arrumar','assinaturas', 'arrumar', 3, 'arrumar',  'esticar o período já pago, de cortesia'),

  ('pontos.ver',        'pontos',       'ver',     1, 'enxergar', 'ver o saldo e o extrato de cada pessoa'),
  ('pontos.arrumar',    'pontos',       'arrumar', 3, 'arrumar',  'lançar um ajuste de pontos, sempre com motivo'),

  ('resgates.ver',      'resgates',     'ver',     1, 'enxergar', 'ver as recompensas trocadas por pontos'),
  ('resgates.mexer',    'resgates',     'mexer',   2, 'mexer',    'dar baixa: entregar a recompensa em mãos'),
  ('resgates.arrumar',  'resgates',     'arrumar', 3, 'arrumar',  'desfazer o resgate e devolver os pontos'),

  ('presentes.ver',     'presentes',    'ver',     1, 'enxergar', 'ver os presentes vendidos, com o código'),
  ('presentes.arrumar', 'presentes',    'arrumar', 3, 'arrumar',  'gerar o código que faltou, ou cancelar um presente parado'),

  ('aniversarios.ver',  'aniversarios', 'ver',     1, 'enxergar', 'ver os brunches reservados'),
  ('aniversarios.mexer','aniversarios', 'mexer',   2, 'mexer',    'dar baixa: brunch entregue'),
  ('aniversarios.arrumar','aniversarios','arrumar',3, 'arrumar',  'desfazer a baixa ou esticar a validade do código'),

  -- o cardápio ---------------------------------------------------------------
  ('favoritos.ver',     'favoritos',    'ver',     1, 'enxergar', 'ver o ranking do cardápio'),

  -- a casa -------------------------------------------------------------------
  ('mural.ver',         'mural',        'ver',     1, 'enxergar', 'ler a parede inteira, inclusive o que está escondido'),
  ('mural.mexer',       'mural',        'mexer',   2, 'mexer',    'esconder um recado, e devolver pra parede'),
  ('mural.arrumar',     'mural',        'arrumar', 3, 'arrumar',  'apagar recado de vez'),

  ('recados.ver',       'recados',      'ver',     1, 'enxergar', 'ler os recados escritos e agendados'),
  ('recados.mexer',     'recados',      'mexer',   2, 'mexer',    'escrever, agendar e ligar ou desligar'),
  ('recados.arrumar',   'recados',      'arrumar', 3, 'arrumar',  'apagar um recado'),

  ('trilha.ver',        'trilha',       'ver',     1, 'enxergar', 'ver as playlists da casa'),
  ('trilha.mexer',      'trilha',       'mexer',   2, 'mexer',    'cadastrar, editar e escolher a que está tocando'),
  ('trilha.arrumar',    'trilha',       'arrumar', 3, 'arrumar',  'tirar uma playlist da trilha'),

  ('agenda.ver',        'agenda',       'ver',     1, 'enxergar', 'ver os encontros e quantos confirmaram'),
  ('agenda.mexer',      'agenda',       'mexer',   2, 'mexer',    'criar e editar encontro'),
  ('agenda.arrumar',    'agenda',       'arrumar', 3, 'arrumar',  'apagar encontro, que leva as presenças junto'),

  -- a gente ------------------------------------------------------------------
  ('pessoas.ver',       'pessoas',      'ver',     1, 'enxergar', 'ver quem já passou por aqui, com plano e pontos'),

  ('espera.ver',        'espera',       'ver',     1, 'enxergar', 'ler os e-mails deixados no rodapé'),
  ('espera.arrumar',    'espera',       'arrumar', 3, 'arrumar',  'tirar um e-mail da lista, a pedido de quem deixou'),

  -- os eventos ---------------------------------------------------------------
  ('leads.ver',         'leads',        'ver',     1, 'enxergar', 'ler os pedidos de evento, com nome e telefone'),
  ('leads.mexer',       'leads',        'mexer',   2, 'mexer',    'marcar já falei, e arquivar'),
  ('leads.arrumar',     'leads',        'arrumar', 3, 'arrumar',  'apagar o pedido de vez'),

  -- o console ----------------------------------------------------------------
  ('equipe.ver',        'equipe',       'ver',     1, 'enxergar', 'ver quem está no console e o que cada um alcança'),
  ('equipe.mexer',      'equipe',       'mexer',   2, 'mexer',    'dar e tirar permissões')
on conflict (slug) do update
  set pagina_slug = excluded.pagina_slug, acao = excluded.acao, nivel = excluded.nivel,
      rotulo = excluded.rotulo, descricao = excluded.descricao;

-- O de-para dos slugs da 0046. Cada slug velho aponta pro nível de LEITURA da
-- página: as funções que este arquivo não reescreve são todas de leitura, e a
-- única de escrita que ficou (`admin_marcar_entregue`, que pergunta por
-- 'entregas') aponta pro `pedidos.mexer`, que é exatamente o que ela sempre foi.
insert into public.permissoes_legado (slug_velho, slug_novo) values
  ('dashboard',    'painel.ver'),
  ('pautas',       'pautas.ver'),
  ('pedidos',      'pedidos.ver'),
  ('entregas',     'pedidos.mexer'),
  ('resgates',     'resgates.ver'),
  ('aniversarios', 'aniversarios.ver'),
  ('presentes',    'presentes.ver'),
  ('usuarios',     'pessoas.ver'),
  ('mural',        'mural.ver'),
  ('equipe',       'equipe.ver'),
  ('relatorios',   'relatorios.ver'),
  ('favoritos',    'favoritos.ver'),
  ('desejos',      'desejos.ver'),
  ('reposicao',    'reposicao.ver'),
  ('lista_espera', 'espera.ver'),
  ('leads',        'leads.ver'),
  ('avisos',       'recados.ver'),
  ('trilha',       'trilha.ver'),
  ('agenda',       'agenda.ver')
on conflict (slug_velho) do update set slug_novo = excluded.slug_novo;


-- =============================================================================
-- 3. permissao_canonica + tem_permissao — a régua
-- -----------------------------------------------------------------------------
-- `permissao_canonica` traduz o slug velho e devolve o novo. Slug que não existe
-- em lugar nenhum volta como veio, não casa com o catálogo, e a resposta é
-- "não pode": deny-by-default de graça.
--
-- `tem_permissao` ganhou a hierarquia: quem tem `mural.arrumar` responde
-- verdadeiro pra `mural.mexer` e pra `mural.ver`, porque são a mesma PÁGINA e
-- o nível é maior. A comparação é sempre dentro da página, nunca entre páginas.
-- O resto continua igual à 0032: owner tem tudo, e a senha inicial pendente
-- zera qualquer privilégio.
-- =============================================================================
create or replace function public.permissao_canonica(p_perm text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.slug from public.permissoes p where p.slug = p_perm),
    (select l.slug_novo from public.permissoes_legado l where l.slug_velho = p_perm),
    p_perm
  );
$$;

create or replace function public.tem_permissao(p_perm text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      (select role from public.profiles where id = auth.uid()) = 'owner'
      or exists (
        select 1
          from public.staff_permissions sp
          join public.permissoes tenho on tenho.slug = sp.permissao
          join public.permissoes quero on quero.slug = public.permissao_canonica(p_perm)
         where sp.user_id = auth.uid()
           and tenho.pagina_slug = quero.pagina_slug
           and tenho.nivel >= quero.nivel
      )
    )
    and not public.senha_inicial_pendente(),
    false
  );
$$;

revoke all on function public.permissao_canonica(text) from public, anon;
grant execute on function public.permissao_canonica(text) to authenticated;


-- =============================================================================
-- 4. staff_permissions — do CHECK escrito à mão pro catálogo
-- -----------------------------------------------------------------------------
-- A ordem aqui é a coisa mais frágil do arquivo, e cada passo só funciona
-- depois do anterior:
--   1º o CHECK da 0046 SAI. Enquanto ele estiver lá, `pedidos.ver` é um valor
--      proibido e o backfill morre na primeira linha (a lista dele é a dos
--      slugs velhos);
--   2º o backfill entra, com as linhas novas ao lado das velhas;
--   3º as velhas saem;
--   4º só então o FK entra. Se ele viesse antes, as linhas da 0046 (que não
--      existem no catálogo novo) barrariam a própria migration.
-- =============================================================================

-- 4a. O CHECK sai (acha pelo conteúdo: o nome mudou entre 0017, 0043 e 0046).
do $$
declare
  v_nome text;
begin
  for v_nome in
    select con.conname
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace nsp on nsp.oid = rel.relnamespace
     where nsp.nspname = 'public' and rel.relname = 'staff_permissions'
       and con.contype = 'c'
       and pg_get_constraintdef(con.oid) ilike '%dashboard%'
  loop
    execute format('alter table public.staff_permissions drop constraint %I', v_nome);
  end loop;
end $$;

-- 4b. Backfill. Cada slug da 0046 vira a FILA do que aquela pessoa já fazia.
--     `mural`, `avisos`, `trilha` e `agenda` levam o 'arrumar' junto porque
--     apagar já estava dentro delas; `resgates`, `aniversarios` e `leads` param
--     no 'mexer' (dar baixa e atender já dava, desfazer é novidade); e o
--     'arrumar' de pedido, ponto, presente e assinatura não vai pra ninguém
--     automaticamente: é poder novo, e poder novo se dá na mão.
insert into public.staff_permissions (user_id, permissao, granted_by, created_at)
select sp.user_id, novo.permissao, sp.granted_by, sp.created_at
  from public.staff_permissions sp
  join (values
          ('dashboard',    'painel.ver'),
          ('pautas',       'pautas.ver'),
          ('pautas',       'pautas.mexer'),
          ('pautas',       'pautas.arrumar'),
          ('pedidos',      'pedidos.ver'),
          ('entregas',     'pedidos.mexer'),
          ('resgates',     'resgates.ver'),
          ('resgates',     'resgates.mexer'),
          ('aniversarios', 'aniversarios.ver'),
          ('aniversarios', 'aniversarios.mexer'),
          ('presentes',    'presentes.ver'),
          ('usuarios',     'pessoas.ver'),
          ('mural',        'mural.ver'),
          ('mural',        'mural.mexer'),
          ('mural',        'mural.arrumar'),
          ('equipe',       'equipe.ver'),
          ('equipe',       'equipe.mexer'),
          ('relatorios',   'relatorios.ver'),
          ('favoritos',    'favoritos.ver'),
          ('desejos',      'desejos.ver'),
          ('reposicao',    'reposicao.ver'),
          ('lista_espera', 'espera.ver'),
          ('leads',        'leads.ver'),
          ('leads',        'leads.mexer'),
          ('avisos',       'recados.ver'),
          ('avisos',       'recados.mexer'),
          ('avisos',       'recados.arrumar'),
          ('trilha',       'trilha.ver'),
          ('trilha',       'trilha.mexer'),
          ('trilha',       'trilha.arrumar'),
          ('agenda',       'agenda.ver'),
          ('agenda',       'agenda.mexer'),
          ('agenda',       'agenda.arrumar')
       ) as novo(velho, permissao) on novo.velho = sp.permissao
on conflict (user_id, permissao) do nothing;

-- 4c. As linhas velhas saem (o que elas davam já foi entregue acima).
delete from public.staff_permissions sp
 where exists (select 1 from public.permissoes_legado l where l.slug_velho = sp.permissao);

-- 4d. O FK entra. Daqui pra frente o catálogo é o whitelist, e permissão nova é
--     INSERT numa tabela, não `alter constraint`.
do $$
begin
  if not exists (
    select 1 from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace nsp on nsp.oid = rel.relnamespace
     where nsp.nspname = 'public' and rel.relname = 'staff_permissions'
       and con.conname = 'staff_permissions_permissao_fkey'
  ) then
    alter table public.staff_permissions
      add constraint staff_permissions_permissao_fkey
      foreign key (permissao) references public.permissoes (slug) on delete restrict;
  end if;
end $$;


-- =============================================================================
-- 5. As policies passam a falar a língua nova
-- -----------------------------------------------------------------------------
-- Elas funcionariam pela ponte da `permissao_canonica`, mas a RLS é a camada que
-- não pode depender de tradução: é ela que o PostgREST abre direto. Duas
-- ganham dono novo de propósito:
--   • `brindes_aniversario` perguntava por 'resgates' desde a 0025 (antes de os
--     aniversários terem página própria) e agora pergunta pela dela;
--   • `points_ledger` perguntava por 'relatorios' e passa a perguntar por
--     `pontos.ver`, que é a página nova do extrato. Quem cuida de relatório de
--     venda não precisa do extrato de pontos de cada pessoa.
-- O `= auth.uid()` de cada uma continua igual: ninguém perde o próprio dado.
-- =============================================================================
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.tem_permissao('pessoas.ver'));

drop policy if exists subscriptions_select_own on public.subscriptions;
create policy subscriptions_select_own on public.subscriptions
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('assinaturas.ver'));

drop policy if exists orders_select_own on public.orders;
create policy orders_select_own on public.orders
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('pedidos.ver'));

drop policy if exists order_items_select_own on public.order_items;
create policy order_items_select_own on public.order_items
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and (o.user_id = auth.uid() or public.tem_permissao('pedidos.ver'))
    )
  );

drop policy if exists points_ledger_select_own on public.points_ledger;
create policy points_ledger_select_own on public.points_ledger
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('pontos.ver'));

drop policy if exists redemptions_select_own on public.redemptions;
create policy redemptions_select_own on public.redemptions
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('resgates.ver'));

drop policy if exists user_achievements_select_own on public.user_achievements;
create policy user_achievements_select_own on public.user_achievements
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('pessoas.ver'));

drop policy if exists brindes_select_own on public.brindes_aniversario;
create policy brindes_select_own on public.brindes_aniversario
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('aniversarios.ver'));


-- =============================================================================
-- 6. As funções que precisavam SEPARAR ver de mexer
-- -----------------------------------------------------------------------------
-- Só entram aqui as que mudam de nível. Todas as outras (as de leitura, e a
-- `admin_marcar_entregue`, que sempre pediu 'entregas') seguem intactas: o slug
-- antigo delas atravessa a `permissao_canonica` e cai no lugar certo.
--
-- O corpo de cada uma é IDÊNTICO ao que já estava no ar (extraído da última
-- migration que a definiu); muda a linha da trava e mais nada. `create or
-- replace` preserva os grants.
-- =============================================================================

-- a loja e o clube: dar baixa deixou de ser a mesma chave de enxergar ----

-- admin_marcar_resgate_usado -> resgates.mexer
create or replace function public.admin_marcar_resgate_usado(p_redemption_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_red public.redemptions;
begin
  if not public.tem_permissao('resgates.mexer') then
    raise exception 'sem permissão pra dar baixa em resgate';
  end if;

  select * into v_red from public.redemptions where id = p_redemption_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'resgate não encontrado');
  end if;

  if v_red.status = 'usado' then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'usado_em', v_red.usado_em);
  end if;

  if v_red.status not in ('solicitado', 'aprovado') then
    return jsonb_build_object('ok', false, 'erro', 'esse resgate já foi ' || v_red.status);
  end if;

  update public.redemptions
     set status = 'usado', usado_em = now(), usado_por = v_uid, updated_at = now()
   where id = p_redemption_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'resgate_usado', 'redemptions', p_redemption_id::text,
          jsonb_build_object('pontos', v_red.pontos_gastos));

  return jsonb_build_object('ok', true, 'usado_em', now());
end;
$$;

-- admin_brinde_usar -> aniversarios.mexer
create or replace function public.admin_brinde_usar(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_brinde public.brindes_aniversario;
begin
  if not public.tem_permissao('aniversarios.mexer') then
    raise exception 'sem permissão pra dar baixa em brinde';
  end if;

  select * into v_brinde from public.brindes_aniversario where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'brinde não encontrado');
  end if;

  if v_brinde.status = 'usado' then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'usado_em', v_brinde.usado_em);
  end if;

  if v_brinde.valido_ate < v_hoje then
    return jsonb_build_object('ok', false, 'erro',
      'esse código venceu em ' || to_char(v_brinde.valido_ate, 'DD/MM'));
  end if;

  update public.brindes_aniversario
     set status = 'usado', usado_em = now(), usado_por = v_uid
   where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'brinde_aniversario_usado', 'brindes_aniversario', p_id::text,
          jsonb_build_object('codigo', v_brinde.codigo));

  return jsonb_build_object('ok', true, 'usado_em', now());
end;
$$;

-- a casa: moderar (reversível) e apagar (não) viraram chaves diferentes --

-- admin_mural_status -> mural.mexer
create or replace function public.admin_mural_status(p_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_novo text := btrim(coalesce(p_status, ''));
  v_id   uuid;
begin
  if not public.tem_permissao('mural.mexer') then
    raise exception 'sem permissão pra cuidar do mural';
  end if;
  if v_novo not in ('aprovado', 'oculto') then
    return jsonb_build_object('ok', false, 'erro', 'esse estado não existe no mural');
  end if;

  update public.mural_notes set status = v_novo where id = p_id
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'esse recado não existe mais');
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'mural_status', 'mural_notes', p_id::text,
          jsonb_build_object('status', v_novo));

  return jsonb_build_object('ok', true, 'status', v_novo);
end;
$$;

-- admin_mural_remover -> mural.arrumar
create or replace function public.admin_mural_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_nota public.mural_notes;
begin
  if not public.tem_permissao('mural.arrumar') then
    raise exception 'sem permissão pra cuidar do mural';
  end if;

  select * into v_nota from public.mural_notes where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  delete from public.mural_notes where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'mural_removido', 'mural_notes', p_id::text,
          jsonb_build_object('autor_nome', coalesce(v_nota.autor_nome, ''),
                             'texto', v_nota.texto));

  return jsonb_build_object('ok', true);
end;
$$;

-- admin_aviso_salvar -> recados.mexer
create or replace function public.admin_aviso_salvar(
  p_id         uuid,
  p_texto      text,
  p_emoji      text,
  p_link_url   text,
  p_link_label text,
  p_inicio     timestamptz,
  p_fim        timestamptz,
  p_prioridade integer,
  p_ativo      boolean
)
returns public.avisos_casa
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_texto text := btrim(coalesce(p_texto, ''));
  v_row   public.avisos_casa;
begin
  if not public.tem_permissao('recados.mexer') then
    raise exception 'sem permissão';
  end if;
  if char_length(v_texto) < 1 then
    raise exception 'o recado não pode ser vazio';
  end if;

  if p_id is null then
    insert into public.avisos_casa
      (texto, emoji, link_url, link_label, inicio_em, fim_em, prioridade, ativo, created_by)
    values
      (v_texto, nullif(btrim(coalesce(p_emoji, '')), ''),
       nullif(btrim(coalesce(p_link_url, '')), ''),
       nullif(btrim(coalesce(p_link_label, '')), ''),
       p_inicio, p_fim, coalesce(p_prioridade, 0), coalesce(p_ativo, true), v_uid)
    returning * into v_row;
  else
    update public.avisos_casa set
      texto      = v_texto,
      emoji      = nullif(btrim(coalesce(p_emoji, '')), ''),
      link_url   = nullif(btrim(coalesce(p_link_url, '')), ''),
      link_label = nullif(btrim(coalesce(p_link_label, '')), ''),
      inicio_em  = p_inicio,
      fim_em     = p_fim,
      prioridade = coalesce(p_prioridade, 0),
      ativo      = coalesce(p_ativo, true),
      updated_at = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'recado não encontrado';
    end if;
  end if;

  return v_row;
end;
$$;

-- admin_aviso_remover -> recados.arrumar
create or replace function public.admin_aviso_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('recados.arrumar') then
    raise exception 'sem permissão';
  end if;
  delete from public.avisos_casa where id = p_id;
  return true;
end;
$$;

-- admin_trilha_salvar -> trilha.mexer
create or replace function public.admin_trilha_salvar(
  p_id       uuid,
  p_nome     text,
  p_clima    text,
  p_url      text,
  p_ordem    integer,
  p_ativo    boolean,
  p_tocando  boolean
)
returns public.playlists_casa
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_url  text := btrim(coalesce(p_url, ''));
  v_toca boolean := coalesce(p_tocando, false);
  v_row  public.playlists_casa;
begin
  if not public.tem_permissao('trilha.mexer') then
    raise exception 'sem permissão';
  end if;
  if char_length(v_nome) < 1 then
    raise exception 'dá um nome pra playlist';
  end if;
  if char_length(v_url) < 1 then
    raise exception 'cola o link do Spotify';
  end if;

  -- Só uma toca por vez: zera as outras antes (o unique index reforça).
  if v_toca then
    update public.playlists_casa set tocando = false
     where tocando = true and (p_id is null or id <> p_id);
  end if;

  if p_id is null then
    insert into public.playlists_casa (nome, clima, spotify_url, ordem, ativo, tocando, created_by)
    values (v_nome, nullif(btrim(coalesce(p_clima, '')), ''), v_url,
            coalesce(p_ordem, 0), coalesce(p_ativo, true), v_toca, v_uid)
    returning * into v_row;
  else
    update public.playlists_casa set
      nome        = v_nome,
      clima       = nullif(btrim(coalesce(p_clima, '')), ''),
      spotify_url = v_url,
      ordem       = coalesce(p_ordem, 0),
      ativo       = coalesce(p_ativo, true),
      tocando     = v_toca,
      updated_at  = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'playlist não encontrada';
    end if;
  end if;

  return v_row;
end;
$$;

-- admin_trilha_remover -> trilha.arrumar
create or replace function public.admin_trilha_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('trilha.arrumar') then
    raise exception 'sem permissão';
  end if;
  delete from public.playlists_casa where id = p_id;
  return true;
end;
$$;

-- admin_evento_salvar -> agenda.mexer
create or replace function public.admin_evento_salvar(
  p_id        uuid,
  p_nome      text,
  p_descricao text,
  p_data      timestamptz,
  p_local     text,
  p_vagas     integer,
  p_ativo     boolean
)
returns public.events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome text := btrim(coalesce(p_nome, ''));
  v_row  public.events;
begin
  if not public.tem_permissao('agenda.mexer') then
    raise exception 'sem permissão';
  end if;
  if char_length(v_nome) < 1 then
    raise exception 'dá um nome pro encontro';
  end if;
  if p_vagas is not null and p_vagas < 0 then
    raise exception 'vagas não pode ser negativo';
  end if;

  if p_id is null then
    insert into public.events (nome, descricao, data, local, vagas, ativo, updated_at)
    values (v_nome, nullif(btrim(coalesce(p_descricao, '')), ''), p_data,
            nullif(btrim(coalesce(p_local, '')), ''), p_vagas,
            coalesce(p_ativo, true), now())
    returning * into v_row;
  else
    update public.events set
      nome       = v_nome,
      descricao  = nullif(btrim(coalesce(p_descricao, '')), ''),
      data       = p_data,
      local      = nullif(btrim(coalesce(p_local, '')), ''),
      vagas      = p_vagas,
      ativo      = coalesce(p_ativo, true),
      updated_at = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'encontro não encontrado';
    end if;
  end if;

  return v_row;
end;
$$;

-- admin_evento_remover -> agenda.arrumar
create or replace function public.admin_evento_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('agenda.arrumar') then
    raise exception 'sem permissão';
  end if;
  delete from public.events where id = p_id;
  return true;
end;
$$;

-- os eventos e o console --------------------------------------------------

-- admin_lead_evento_status -> leads.mexer
create or replace function public.admin_lead_evento_status(p_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_status text := btrim(coalesce(p_status, ''));
begin
  if not public.tem_permissao('leads.mexer') then
    raise exception 'sem permissão pra mexer nos pedidos de evento';
  end if;

  if v_status not in ('novo', 'atendido', 'arquivado') then
    raise exception 'status inválido';
  end if;

  update public.leads_evento
     set status       = v_status,
         atendido_em  = case when v_status = 'novo' then null else now() end,
         atendido_por = case when v_status = 'novo' then null else v_uid end
   where id = p_id;

  if not found then
    raise exception 'pedido não encontrado';
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'lead_evento_status', 'leads_evento', p_id::text,
          jsonb_build_object('status', v_status));

  return jsonb_build_object('ok', true, 'status', v_status);
end;
$$;

-- admin_buscar_pessoa -> equipe.mexer
create or replace function public.admin_buscar_pessoa(p_busca text)
returns table (
  id     uuid,
  nome   text,
  email  text,
  papel  text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('equipe.mexer') then
    raise exception 'sem permissão pra mexer na equipe';
  end if;
  if v_busca is null or length(v_busca) < 3 then
    return;
  end if;

  return query
    select p.id, coalesce(p.full_name, ''), coalesce(u.email::text, ''), p.role
    from public.profiles p
    left join auth.users u on u.id = p.id
    where p.full_name ilike '%' || v_busca || '%'
       or u.email     ilike '%' || v_busca || '%'
    order by p.full_name nulls last
    limit 20;
end;
$$;

-- o quadro de pautas: ler o combinado do dia é uma coisa, reorganizar o
-- quadro é outra, e apagar o que a equipe escreveu é uma terceira. As de
-- LEITURA (`admin_quadros_listar`, `admin_quadro_abrir`, `admin_pauta_ver`,
-- `admin_pauta_comentarios`, `admin_pautas_equipe`) não estão aqui: elas
-- continuam pedindo 'pautas', que agora quer dizer `pautas.ver`. -------------

-- admin_quadro_salvar -> pautas.mexer
create or replace function public.admin_quadro_salvar(
  p_id   uuid default null,
  p_nome text default null,
  p_cor  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_cor  text := coalesce(nullif(btrim(coalesce(p_cor, '')), ''), 'coral');
  v_id   uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nos quadros';
  end if;
  if char_length(v_nome) < 1 or char_length(v_nome) > 60 then
    return jsonb_build_object('ok', false, 'erro', 'dá um nome de até 60 letras pro quadro');
  end if;
  if v_cor not in ('neutro', 'coral', 'gold', 'green', 'olive', 'blue') then
    v_cor := 'coral';
  end if;

  if p_id is null then
    insert into public.pauta_quadros (nome, cor, ordem, criado_por)
    values (v_nome, v_cor,
            coalesce((select max(ordem) + 1 from public.pauta_quadros), 0),
            v_uid)
    returning id into v_id;

    -- Quadro nasce com um grupo, senão a primeira pauta não teria onde cair.
    insert into public.pauta_grupos (quadro_id, nome, cor, ordem)
    values (v_id, 'o dia a dia', 'neutro', 0);
  else
    update public.pauta_quadros
       set nome = v_nome, cor = v_cor, updated_at = now()
     where id = p_id
    returning id into v_id;
    if v_id is null then
      return jsonb_build_object('ok', false, 'erro', 'esse quadro não existe mais');
    end if;
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, case when p_id is null then 'quadro_criado' else 'quadro_editado' end,
          'pauta_quadros', v_id::text, jsonb_build_object('nome', v_nome));

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- admin_quadro_arquivar -> pautas.mexer
create or replace function public.admin_quadro_arquivar(p_id uuid, p_arquivar boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nos quadros';
  end if;
  update public.pauta_quadros set arquivado = coalesce(p_arquivar, true), updated_at = now()
   where id = p_id returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'esse quadro não existe mais');
  end if;
  return jsonb_build_object('ok', true, 'arquivado', coalesce(p_arquivar, true));
end;
$$;

-- admin_quadro_remover -> pautas.arrumar
create or replace function public.admin_quadro_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_quadro public.pauta_quadros;
  v_itens  bigint;
begin
  if not public.tem_permissao('pautas.arrumar') then
    raise exception 'sem permissão pra mexer nos quadros';
  end if;

  select * into v_quadro from public.pauta_quadros where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;
  if not (public.is_owner() or v_quadro.criado_por = v_uid) then
    return jsonb_build_object('ok', false, 'erro',
      'esse quadro é de quem criou. dá pra arquivar, apagar só quem criou ou o adm do Casa');
  end if;

  select count(*) into v_itens from public.pautas where quadro_id = p_id;
  if v_itens > 0 then
    return jsonb_build_object('ok', false, 'erro',
      'esse quadro ainda tem ' || v_itens || ' pauta(s) dentro. move ou apaga elas antes, ou arquiva o quadro');
  end if;

  delete from public.pauta_quadros where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'quadro_removido', 'pauta_quadros', p_id::text,
          jsonb_build_object('nome', v_quadro.nome));

  return jsonb_build_object('ok', true);
end;
$$;

-- admin_grupo_salvar -> pautas.mexer
create or replace function public.admin_grupo_salvar(
  p_id        uuid default null,
  p_quadro_id uuid default null,
  p_nome      text default null,
  p_cor       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_cor  text := coalesce(nullif(btrim(coalesce(p_cor, '')), ''), 'coral');
  v_id   uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nos grupos';
  end if;
  if char_length(v_nome) < 1 or char_length(v_nome) > 60 then
    return jsonb_build_object('ok', false, 'erro', 'dá um nome de até 60 letras pro grupo');
  end if;
  if v_cor not in ('neutro', 'coral', 'gold', 'green', 'olive', 'blue') then
    v_cor := 'coral';
  end if;

  if p_id is null then
    if p_quadro_id is null or not exists (select 1 from public.pauta_quadros where id = p_quadro_id) then
      return jsonb_build_object('ok', false, 'erro', 'esse quadro não existe mais');
    end if;
    insert into public.pauta_grupos (quadro_id, nome, cor, ordem)
    values (p_quadro_id, v_nome, v_cor,
            coalesce((select max(ordem) + 1 from public.pauta_grupos where quadro_id = p_quadro_id), 0))
    returning id into v_id;
  else
    update public.pauta_grupos set nome = v_nome, cor = v_cor where id = p_id
    returning id into v_id;
    if v_id is null then
      return jsonb_build_object('ok', false, 'erro', 'esse grupo não existe mais');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- admin_grupo_recolher -> pautas.mexer
create or replace function public.admin_grupo_recolher(p_id uuid, p_recolhido boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nos grupos';
  end if;
  update public.pauta_grupos set recolhido = coalesce(p_recolhido, true)
   where id = p_id returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'esse grupo não existe mais');
  end if;
  return jsonb_build_object('ok', true, 'recolhido', coalesce(p_recolhido, true));
end;
$$;

-- admin_grupo_remover -> pautas.arrumar
create or replace function public.admin_grupo_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_grupo public.pauta_grupos;
  v_itens bigint;
begin
  if not public.tem_permissao('pautas.arrumar') then
    raise exception 'sem permissão pra mexer nos grupos';
  end if;

  select * into v_grupo from public.pauta_grupos where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  select count(*) into v_itens from public.pautas where grupo_id = p_id;
  if v_itens > 0 then
    return jsonb_build_object('ok', false, 'erro',
      'esse grupo tem ' || v_itens || ' pauta(s) dentro. move elas pra outro grupo antes');
  end if;

  delete from public.pauta_grupos where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'grupo_removido', 'pauta_grupos', p_id::text,
          jsonb_build_object('nome', v_grupo.nome));

  return jsonb_build_object('ok', true);
end;
$$;

-- admin_pauta_salvar -> pautas.mexer
create or replace function public.admin_pauta_salvar(
  p_id          uuid,
  p_quadro_id   uuid,
  p_grupo_id    uuid,
  p_titulo      text,
  p_briefing    text,
  p_atribuido_a uuid,
  p_prazo       date,
  p_prioridade  text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_titulo text := btrim(coalesce(p_titulo, ''));
  v_prio   text := coalesce(nullif(btrim(coalesce(p_prioridade, '')), ''), 'normal');
  v_quadro uuid := p_quadro_id;
  v_grupo  uuid := p_grupo_id;
  v_id     uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;
  if char_length(v_titulo) < 1 or char_length(v_titulo) > 120 then
    return jsonb_build_object('ok', false, 'erro', 'a pauta precisa de um título de até 120 letras');
  end if;
  if v_prio not in ('baixa', 'normal', 'alta') then
    v_prio := 'normal';
  end if;
  if p_atribuido_a is not null
     and not exists (
       select 1 from public.profiles p
        where p.id = p_atribuido_a
          and (p.role = 'owner'
               or exists (select 1 from public.staff_permissions sp where sp.user_id = p.id))
     ) then
    return jsonb_build_object('ok', false, 'erro', 'essa pessoa não é da equipe do console');
  end if;

  if p_id is null then
    if v_quadro is null then
      select id into v_quadro from public.pauta_quadros where not arquivado order by ordem, created_at limit 1;
    end if;
    if v_quadro is null then
      return jsonb_build_object('ok', false, 'erro', 'cria um quadro antes de escrever a primeira pauta');
    end if;
    -- Grupo não informado (ou de outro quadro) cai no primeiro do quadro.
    if v_grupo is null or not exists (select 1 from public.pauta_grupos where id = v_grupo and quadro_id = v_quadro) then
      select id into v_grupo from public.pauta_grupos where quadro_id = v_quadro order by ordem, created_at limit 1;
    end if;

    insert into public.pautas (titulo, briefing, atribuido_a, prazo, prioridade, criado_por,
                               quadro_id, grupo_id, ordem)
    values (v_titulo, nullif(btrim(coalesce(p_briefing, '')), ''), p_atribuido_a, p_prazo, v_prio, v_uid,
            v_quadro, v_grupo,
            coalesce((select max(ordem) + 1 from public.pautas where grupo_id = v_grupo), 0))
    returning id into v_id;
  else
    update public.pautas
       set titulo      = v_titulo,
           briefing    = nullif(btrim(coalesce(p_briefing, '')), ''),
           atribuido_a = p_atribuido_a,
           prazo       = p_prazo,
           prioridade  = v_prio,
           grupo_id    = coalesce(
                           (select g.id from public.pauta_grupos g
                             where g.id = p_grupo_id and g.quadro_id = public.pautas.quadro_id),
                           grupo_id),
           updated_at  = now()
     where id = p_id
    returning id into v_id;

    if v_id is null then
      return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
    end if;
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, case when p_id is null then 'pauta_criada' else 'pauta_editada' end,
          'pautas', v_id::text, jsonb_build_object('titulo', v_titulo));

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- admin_pauta_celula -> pautas.mexer
create or replace function public.admin_pauta_celula(p_id uuid, p_campo text, p_valor text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_campo text := btrim(coalesce(p_campo, ''));
  v_valor text := nullif(btrim(coalesce(p_valor, '')), '');
  v_id    uuid;
  v_alvo  uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;

  if v_campo = 'status' then
    if v_valor is null or v_valor not in ('aberta', 'fazendo', 'travada', 'feita') then
      return jsonb_build_object('ok', false, 'erro', 'esse estado não existe no quadro');
    end if;
    update public.pautas
       set status        = v_valor,
           concluida_em  = case when v_valor = 'feita' then now() else null end,
           concluida_por = case when v_valor = 'feita' then v_uid else null end,
           updated_at    = now()
     where id = p_id returning id into v_id;

  elsif v_campo = 'prioridade' then
    if v_valor is null or v_valor not in ('baixa', 'normal', 'alta') then
      return jsonb_build_object('ok', false, 'erro', 'essa urgência não existe');
    end if;
    update public.pautas set prioridade = v_valor, updated_at = now()
     where id = p_id returning id into v_id;

  elsif v_campo = 'prazo' then
    update public.pautas set prazo = v_valor::date, updated_at = now()
     where id = p_id returning id into v_id;

  elsif v_campo = 'atribuido_a' then
    v_alvo := v_valor::uuid;
    if v_alvo is not null
       and not exists (
         select 1 from public.profiles p
          where p.id = v_alvo
            and (p.role = 'owner'
                 or exists (select 1 from public.staff_permissions sp where sp.user_id = p.id))
       ) then
      return jsonb_build_object('ok', false, 'erro', 'essa pessoa não é da equipe do console');
    end if;
    update public.pautas set atribuido_a = v_alvo, updated_at = now()
     where id = p_id returning id into v_id;

  elsif v_campo = 'grupo_id' then
    v_alvo := v_valor::uuid;
    if v_alvo is null or not exists (
         select 1 from public.pauta_grupos g
          join public.pautas p on p.quadro_id = g.quadro_id
         where g.id = v_alvo and p.id = p_id) then
      return jsonb_build_object('ok', false, 'erro', 'esse grupo não é deste quadro');
    end if;
    update public.pautas
       set grupo_id = v_alvo,
           ordem    = coalesce((select max(ordem) + 1 from public.pautas where grupo_id = v_alvo), 0),
           updated_at = now()
     where id = p_id returning id into v_id;

  else
    return jsonb_build_object('ok', false, 'erro', 'esse campo não se edita por aqui');
  end if;

  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;
  return jsonb_build_object('ok', true, 'campo', v_campo, 'valor', v_valor);
exception
  -- Data ruim e uuid ruim NÃO estouram no mesmo código: 'banana'::date é 22007
  -- (invalid_datetime_format) e 'banana'::uuid é 22P02 (invalid_text_representation).
  -- Sem os dois na lista, uma data digitada errada subia como erro cru do Postgres
  -- em vez do recado da casa.
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    return jsonb_build_object('ok', false, 'erro', 'esse valor não serve pra esse campo');
end;
$$;

-- admin_pauta_ordenar -> pautas.mexer
create or replace function public.admin_pauta_ordenar(p_id uuid, p_direcao text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_pauta   public.pautas;
  v_vizinho public.pautas;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;

  select * into v_pauta from public.pautas where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;

  if p_direcao = 'cima' then
    select * into v_vizinho from public.pautas
     where grupo_id is not distinct from v_pauta.grupo_id
       and quadro_id = v_pauta.quadro_id
       and (ordem, created_at) < (v_pauta.ordem, v_pauta.created_at)
     order by ordem desc, created_at desc limit 1 for update;
  elsif p_direcao = 'baixo' then
    select * into v_vizinho from public.pautas
     where grupo_id is not distinct from v_pauta.grupo_id
       and quadro_id = v_pauta.quadro_id
       and (ordem, created_at) > (v_pauta.ordem, v_pauta.created_at)
     order by ordem asc, created_at asc limit 1 for update;
  else
    return jsonb_build_object('ok', false, 'erro', 'só dá pra mover pra cima ou pra baixo');
  end if;

  if v_vizinho.id is null then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  -- Empate de `ordem` (todo mundo em 0, por exemplo) não trocaria nada só
  -- invertendo os valores; por isso a troca é feita com números distintos.
  update public.pautas set ordem = v_vizinho.ordem, updated_at = now() where id = v_pauta.id;
  update public.pautas set ordem = case when v_vizinho.ordem = v_pauta.ordem
                                        then case when p_direcao = 'cima' then v_pauta.ordem + 1
                                                  else v_pauta.ordem - 1 end
                                        else v_pauta.ordem end,
                           updated_at = now()
   where id = v_vizinho.id;

  return jsonb_build_object('ok', true);
end;
$$;

-- admin_pauta_status -> pautas.mexer
create or replace function public.admin_pauta_status(p_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_novo text := btrim(coalesce(p_status, ''));
  v_id   uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;
  if v_novo not in ('aberta', 'fazendo', 'feita') then
    return jsonb_build_object('ok', false, 'erro', 'esse estado não existe no quadro');
  end if;

  update public.pautas
     set status        = v_novo,
         concluida_em  = case when v_novo = 'feita' then now() else null end,
         concluida_por = case when v_novo = 'feita' then v_uid else null end,
         updated_at    = now()
   where id = p_id
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;

  return jsonb_build_object('ok', true, 'status', v_novo);
end;
$$;

-- admin_pauta_comentar -> pautas.mexer
create or replace function public.admin_pauta_comentar(p_pauta_id uuid, p_texto text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_texto text := btrim(coalesce(p_texto, ''));
  v_id    uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra comentar';
  end if;
  if char_length(v_texto) < 1 or char_length(v_texto) > 2000 then
    return jsonb_build_object('ok', false, 'erro', 'escreve o recado (até 2000 letras)');
  end if;
  if not exists (select 1 from public.pautas where id = p_pauta_id) then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;

  insert into public.pauta_updates (pauta_id, user_id, autor_nome, texto)
  values (p_pauta_id, v_uid,
          (select coalesce(full_name, '') from public.profiles where id = v_uid),
          v_texto)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- admin_pauta_remover -> pautas.arrumar
create or replace function public.admin_pauta_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_pauta public.pautas;
begin
  if not public.tem_permissao('pautas.arrumar') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;

  select * into v_pauta from public.pautas where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  if not (public.is_owner() or v_pauta.criado_por = v_uid) then
    return jsonb_build_object('ok', false, 'erro',
      'essa pauta é de quem escreveu. tu pode marcar como feita, apagar só quem escreveu ou o adm do Casa');
  end if;

  delete from public.pautas where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'pauta_removida', 'pautas', p_id::text,
          jsonb_build_object('titulo', v_pauta.titulo));

  return jsonb_build_object('ok', true);
end;
$$;

-- admin_pauta_comentario_remover -> pautas.arrumar
create or replace function public.admin_pauta_comentario_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_com public.pauta_updates;
begin
  if not public.tem_permissao('pautas.arrumar') then
    raise exception 'sem permissão pra mexer nos comentários';
  end if;
  select * into v_com from public.pauta_updates where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;
  if not (public.is_owner() or v_com.user_id = v_uid) then
    return jsonb_build_object('ok', false, 'erro', 'esse recado é de quem escreveu');
  end if;
  delete from public.pauta_updates where id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;

-- =============================================================================
-- 7. O console se olhando: catálogo, minhas permissões e a tela da equipe
-- =============================================================================

-- ---------------------------------------------------------------------------
-- admin_permissoes_catalogo — o dicionário inteiro, já agrupado, pra tela da
-- equipe desenhar seção por seção. Em `jsonb` de propósito: é leitura composta,
-- e `returns table` com uma dúzia de colunas é onde mora o erro de tipo que
-- derrubou cinco abas da 0017 até a 0042.
-- ---------------------------------------------------------------------------
create or replace function public.admin_permissoes_catalogo()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.tem_permissao('equipe.ver') then
    raise exception 'sem permissão pra ver o catálogo de permissões';
  end if;

  return coalesce((
    select jsonb_agg(s order by s->>'ordem')
      from (
        select jsonb_build_object(
                 'slug',      sec.slug,
                 'rotulo',    sec.rotulo,
                 'descricao', coalesce(sec.descricao, ''),
                 'ordem',     lpad(sec.ordem::text, 4, '0'),
                 'paginas',   coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'slug',      pag.slug,
                            'rotulo',    pag.rotulo,
                            'descricao', coalesce(pag.descricao, ''),
                            'aba',       pag.aba,
                            'acoes',     coalesce((
                              select jsonb_agg(jsonb_build_object(
                                       'slug',      perm.slug,
                                       'acao',      perm.acao,
                                       'nivel',     perm.nivel,
                                       'rotulo',    perm.rotulo,
                                       'descricao', coalesce(perm.descricao, ''))
                                       order by perm.nivel)
                                from public.permissoes perm
                               where perm.pagina_slug = pag.slug), '[]'::jsonb))
                            order by pag.ordem)
                     from public.permissao_paginas pag
                    where pag.secao_slug = sec.slug), '[]'::jsonb)
               ) as s
          from public.permissao_secoes sec
      ) t
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_minhas_permissoes — mesmo contrato da 0032, com duas diferenças:
--   • `permissoes` volta EXPANDIDA (quem tem `mural.arrumar` recebe também
--     `mural.mexer` e `mural.ver`). O front testa `pode('mural.ver')` pra
--     decidir se desenha a aba, e não deve ter que saber a regra da
--     hierarquia: a régua é do banco, e o banco entrega já resolvida;
--   • `alcance` vem legível, agrupado por seção e página, pra a tela "tua
--     conta" dizer o que a pessoa alcança sem precisar do catálogo inteiro
--     (que é da permissão `equipe.ver`, e nem todo mundo tem).
-- ---------------------------------------------------------------------------
create or replace function public.admin_minhas_permissoes()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_uid      uuid := auth.uid();
  v_prof     public.profiles;
  v_pendente boolean;
  v_tudo     boolean;
  v_slugs    text[];
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('console', false);
  end if;

  v_pendente := public.senha_inicial_pendente();
  v_tudo     := v_prof.role = 'owner' and not v_pendente;

  -- Os slugs que esta pessoa alcança de verdade, já com a hierarquia resolvida.
  if v_pendente then
    v_slugs := '{}';
  elsif v_tudo then
    select coalesce(array_agg(p.slug), '{}') into v_slugs from public.permissoes p;
  else
    select coalesce(array_agg(distinct alcancada.slug), '{}') into v_slugs
      from public.staff_permissions sp
      join public.permissoes tenho     on tenho.slug = sp.permissao
      join public.permissoes alcancada on alcancada.pagina_slug = tenho.pagina_slug
                                      and alcancada.nivel <= tenho.nivel
     where sp.user_id = v_uid;
  end if;

  return jsonb_build_object(
    'console',        public.pode_entrar_no_console() or (v_prof.master and v_pendente),
    'nome',           coalesce(v_prof.full_name, ''),
    'papel',          v_prof.role,
    'master',         v_prof.master,
    'senha_trocada',  not v_pendente,
    'permissoes',     to_jsonb(v_slugs),
    'alcance',        coalesce((
      select jsonb_agg(linha order by linha->>'ordem')
        from (
          select jsonb_build_object(
                   'secao',  sec.rotulo,
                   'pagina', pag.rotulo,
                   'ordem',  lpad(sec.ordem::text, 4, '0') || lpad(pag.ordem::text, 4, '0'),
                   'acoes',  jsonb_agg(perm.rotulo order by perm.nivel)
                 ) as linha
            from public.permissoes perm
            join public.permissao_paginas pag on pag.slug = perm.pagina_slug
            join public.permissao_secoes  sec on sec.slug = pag.secao_slug
           where perm.slug = any (v_slugs)
           group by sec.rotulo, pag.rotulo, sec.ordem, pag.ordem
        ) t), '[]'::jsonb),
    'tudo',           v_tudo
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_definir_permissoes — dá e tira, de uma pessoa por vez. A lista chega
-- inteira e substitui a anterior. Mudanças em relação à 0017:
--   • pede `equipe.mexer` (ver a equipe e mexer nela viraram coisas separadas);
--   • recusa slug que não está no catálogo, dizendo qual é (antes, um slug
--     errado batia num CHECK e voltava "violates check constraint");
--   • o audit_log guarda o ANTES e o DEPOIS. Num sistema de permissão, "quem
--     tirou o acesso da fulana?" é a pergunta que sempre aparece depois.
-- As travas contra escalada continuam: ninguém edita as próprias, o adm do Casa
-- e o master não têm permissão editável, e só o dono delega a página da equipe.
-- ---------------------------------------------------------------------------
create or replace function public.admin_definir_permissoes(
  p_user_id     uuid,
  p_permissoes  text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_alvo   public.profiles;
  v_lista  text[] := coalesce(p_permissoes, '{}');
  v_antes  text[];
  v_ruim   text;
begin
  if not public.tem_permissao('equipe.mexer') then
    raise exception 'sem permissão pra mexer na equipe';
  end if;

  if p_user_id = v_uid then
    raise exception 'não dá pra mudar as próprias permissões';
  end if;

  select * into v_alvo from public.profiles where id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'pessoa não encontrada');
  end if;

  if v_alvo.role = 'owner' or v_alvo.master then
    return jsonb_build_object('ok', false, 'erro', 'o adm do Casa já tem tudo, não há o que ajustar aqui');
  end if;

  -- Slug fora do catálogo para aqui, com nome e sobrenome.
  select perm into v_ruim
    from unnest(v_lista) as perm
   where not exists (select 1 from public.permissoes p where p.slug = perm)
   limit 1;
  if v_ruim is not null then
    return jsonb_build_object('ok', false, 'erro', 'essa permissão não existe: ' || v_ruim);
  end if;

  if exists (
    select 1 from public.permissoes p
     where p.slug = any (v_lista) and p.pagina_slug = 'equipe'
  ) and not public.is_owner() then
    return jsonb_build_object('ok', false, 'erro', 'só o adm do Casa pode delegar o cuidado da equipe');
  end if;

  select coalesce(array_agg(permissao order by permissao), '{}')
    into v_antes
    from public.staff_permissions where user_id = p_user_id;

  delete from public.staff_permissions
   where user_id = p_user_id
     and not (permissao = any (v_lista));

  insert into public.staff_permissions (user_id, permissao, granted_by)
  select p_user_id, perm, v_uid from unnest(v_lista) as perm
  on conflict (user_id, permissao) do nothing;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'permissoes_definidas', 'staff_permissions', p_user_id::text,
          jsonb_build_object('antes', to_jsonb(v_antes), 'depois', to_jsonb(v_lista)));

  return jsonb_build_object('ok', true, 'permissoes', to_jsonb(v_lista));
end;
$$;


-- =============================================================================
-- 8. As assinaturas — a página que faltava
-- -----------------------------------------------------------------------------
-- O clube é o principal benefício do site e o console era CEGO pra ele: quando
-- alguém ligava dizendo "paguei e não caiu", não havia tela nenhuma pra olhar.
-- Só leitura mais um conserto, e o conserto é de propósito o mais inofensivo
-- que existe: esticar o período já pago. Ele não cobra, não estorna e não
-- contradiz o Asaas (lá a assinatura segue no ciclo dela); só faz o benefício
-- durar mais deste lado. Pausar, retomar, subir e descer de plano continuam
-- sendo das Edge Functions, que falam com o gateway.
-- =============================================================================
create or replace function public.admin_assinaturas(
  p_busca  text default null,
  p_status text default null,
  p_limite int  default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('assinaturas.ver') then
    raise exception 'sem permissão pra ver as assinaturas';
  end if;

  return coalesce((
    select jsonb_agg(linha order by (linha->>'criada_em') desc)
      from (
        select jsonb_build_object(
                 'id',                 s.id,
                 'pessoa_id',          s.user_id,
                 'pessoa',             coalesce(pr.full_name, ''),
                 'email',              coalesce(u.email::text, ''),
                 'plano',              coalesce(t.nome, s.tier_slug),
                 'tier_slug',          s.tier_slug,
                 'status',             s.status,
                 'vale_ate',           s.current_period_end,
                 'vencida',            s.current_period_end is not null and s.current_period_end < now(),
                 'de_presente',        s.presente_id is not null,
                 'no_gateway',         s.asaas_subscription_id is not null,
                 'descida_agendada',   coalesce(td.nome, s.scheduled_downgrade_to),
                 'criada_em',          s.created_at
               ) as linha
          from public.subscriptions s
          left join public.profiles pr on pr.id   = s.user_id
          left join auth.users      u  on u.id    = s.user_id
          left join public.tiers    t  on t.slug  = s.tier_slug
          left join public.tiers    td on td.slug = s.scheduled_downgrade_to
         where (p_status is null or p_status = '' or s.status = p_status)
           and (
             v_busca is null
             or coalesce(pr.full_name, '') ilike '%' || v_busca || '%'
             or coalesce(u.email::text, '') ilike '%' || v_busca || '%'
           )
         order by s.created_at desc
         limit greatest(1, least(coalesce(p_limite, 200), 1000))
      ) t
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_assinatura_esticar — dias de cortesia no período já pago.
-- Nunca cobra e nunca encurta: se a data já passou, conta a partir de hoje.
-- Reespelha o tier no `profiles` quando a assinatura volta a conceder
-- benefício (a GUC é a mesma que o 0008 usa pro write server-side).
-- ---------------------------------------------------------------------------
create or replace function public.admin_assinatura_esticar(p_id uuid, p_dias integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_sub  public.subscriptions;
  v_dias integer := coalesce(p_dias, 0);
  v_novo timestamptz;
begin
  if not public.tem_permissao('assinaturas.arrumar') then
    raise exception 'sem permissão pra mexer em assinatura';
  end if;
  if v_dias < 1 or v_dias > 90 then
    return jsonb_build_object('ok', false, 'erro', 'escolhe de 1 a 90 dias');
  end if;

  select * into v_sub from public.subscriptions where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'assinatura não encontrada');
  end if;
  if v_sub.status = 'cancelada' then
    return jsonb_build_object('ok', false, 'erro',
      'essa assinatura foi encerrada, esticar aqui não devolve o plano');
  end if;

  v_novo := greatest(now(), coalesce(v_sub.current_period_end, now())) + make_interval(days => v_dias);

  update public.subscriptions
     set current_period_end = v_novo, updated_at = now()
   where id = p_id;

  -- Volta a valer? Então o cache do perfil tem que dizer a mesma coisa.
  if v_sub.status in ('ativa', 'pausada') then
    perform set_config('casa.trusted_points', 'on', true);
    update public.profiles set tier_slug = v_sub.tier_slug, updated_at = now()
     where id = v_sub.user_id;
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'assinatura_esticada', 'subscriptions', p_id::text,
          jsonb_build_object('dias', v_dias, 'de', v_sub.current_period_end, 'para', v_novo));

  return jsonb_build_object('ok', true, 'vale_ate', v_novo);
end;
$$;


-- =============================================================================
-- 9. Os pontos — a outra página que faltava
-- -----------------------------------------------------------------------------
-- O `points_ledger` é append-only e é a fonte da verdade do saldo. A casa não
-- tinha como OLHAR o extrato de ninguém, nem como consertar quando o webhook do
-- pagamento falhava e o ponto não caía. As duas coisas entram aqui, e o ajuste
-- é um LANÇAMENTO como qualquer outro: nada de `update` no saldo, que é cache.
-- =============================================================================
create or replace function public.admin_pontos_pessoas(
  p_busca  text default null,
  p_limite int  default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('pontos.ver') then
    raise exception 'sem permissão pra ver os pontos';
  end if;
  if v_busca is null or char_length(v_busca) < 3 then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(linha)
      from (
        select jsonb_build_object(
                 'id',     p.id,
                 'nome',   coalesce(p.full_name, ''),
                 'email',  coalesce(u.email::text, ''),
                 'saldo',  coalesce(p.points_balance, 0),
                 'plano',  coalesce(t.nome, '')
               ) as linha
          from public.profiles p
          left join auth.users u on u.id = p.id
          left join public.tiers t on t.slug = p.tier_slug
         where coalesce(p.full_name, '') ilike '%' || v_busca || '%'
            or coalesce(u.email::text, '') ilike '%' || v_busca || '%'
         order by p.full_name nulls last
         limit greatest(1, least(coalesce(p_limite, 30), 100))
      ) t
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_pontos_extrato(
  p_user_id uuid,
  p_limite  int default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_prof   public.profiles;
  v_email  text;
  v_ledger integer;
begin
  if not public.tem_permissao('pontos.ver') then
    raise exception 'sem permissão pra ver os pontos';
  end if;

  select * into v_prof from public.profiles where id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'pessoa não encontrada');
  end if;

  select coalesce(u.email::text, '') into v_email from auth.users u where u.id = p_user_id;
  select coalesce(sum(delta), 0)::integer into v_ledger
    from public.points_ledger where user_id = p_user_id;

  return jsonb_build_object(
    'ok',           true,
    'id',           v_prof.id,
    'nome',         coalesce(v_prof.full_name, ''),
    'email',        coalesce(v_email, ''),
    'plano',        coalesce((select t.nome from public.tiers t where t.slug = v_prof.tier_slug), ''),
    'saldo_cache',  coalesce(v_prof.points_balance, 0),
    'saldo_ledger', v_ledger,
    'lancamentos',  coalesce((
      select jsonb_agg(jsonb_build_object(
               'id',        l.id,
               'delta',     l.delta,
               'motivo',    l.motivo,
               'descricao', coalesce(l.descricao, ''),
               'ref_type',  coalesce(l.ref_type, ''),
               'quando',    l.created_at)
               order by l.created_at desc)
        from (
          select * from public.points_ledger
           where user_id = p_user_id
           order by created_at desc
           limit greatest(1, least(coalesce(p_limite, 100), 500))
        ) l), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_pontos_ajustar — o lançamento manual, com motivo obrigatório.
-- Pode ser negativo (tirar ponto que caiu errado) e o saldo PODE ficar negativo,
-- pelo mesmo motivo do estorno do webhook: a pessoa fica devendo, e o resgate
-- só volta a passar quando o saldo cobre. Teto de 5.000 por lançamento pra um
-- dedo escorregado no teclado não virar mil reais em mimo.
-- ---------------------------------------------------------------------------
create or replace function public.admin_pontos_ajustar(
  p_user_id uuid,
  p_delta   integer,
  p_motivo  text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_delta  integer := coalesce(p_delta, 0);
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_saldo  integer;
begin
  if not public.tem_permissao('pontos.arrumar') then
    raise exception 'sem permissão pra ajustar pontos';
  end if;
  if v_delta = 0 then
    return jsonb_build_object('ok', false, 'erro', 'diz quantos pontos, pra mais ou pra menos');
  end if;
  if abs(v_delta) > 5000 then
    return jsonb_build_object('ok', false, 'erro', 'um ajuste vai até 5.000 pontos de cada vez');
  end if;
  if char_length(v_motivo) < 3 then
    return jsonb_build_object('ok', false, 'erro', 'escreve o motivo, é o que explica esse lançamento depois');
  end if;
  if char_length(v_motivo) > 120 then
    v_motivo := left(v_motivo, 120);
  end if;

  if not exists (select 1 from public.profiles where id = p_user_id) then
    return jsonb_build_object('ok', false, 'erro', 'pessoa não encontrada');
  end if;

  insert into public.points_ledger (user_id, delta, motivo, descricao, ref_type, ref_id)
  values (p_user_id, v_delta, 'ajuste da casa', v_motivo, 'ajuste', gen_random_uuid()::text);

  select coalesce(sum(delta), 0)::integer into v_saldo
    from public.points_ledger where user_id = p_user_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'pontos_ajustados', 'points_ledger', p_user_id::text,
          jsonb_build_object('delta', v_delta, 'motivo', v_motivo, 'saldo', v_saldo));

  return jsonb_build_object('ok', true, 'delta', v_delta, 'saldo', v_saldo);
end;
$$;


-- =============================================================================
-- 10. Os consertos das outras páginas
-- =============================================================================

-- ---------------------------------------------------------------------------
-- admin_pedido_status — mudar o estado do pedido na mão.
-- A 0017 só sabia empurrar pra 'entregue', e sem volta: marcou errado, a fila
-- passava a mentir pra sempre. Aqui dá pra voltar. Duas portas ficam fechadas
-- de propósito: 'pendente' (pedido que nunca foi pago é assunto do gateway) e
-- 'estornado' (quem carimba isso é o webhook, quando o dinheiro volta).
-- ---------------------------------------------------------------------------
create or replace function public.admin_pedido_status(p_order_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_ord  public.orders;
  v_novo text := btrim(coalesce(p_status, ''));
begin
  if not public.tem_permissao('pedidos.arrumar') then
    raise exception 'sem permissão pra arrumar pedido';
  end if;
  if v_novo not in ('pago', 'preparando', 'pronto', 'entregue', 'cancelado') then
    return jsonb_build_object('ok', false, 'erro', 'esse estado não existe por aqui');
  end if;

  select * into v_ord from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'pedido não encontrado');
  end if;
  if v_ord.status = 'pendente' then
    return jsonb_build_object('ok', false, 'erro',
      'esse pedido ainda não foi pago, e quem confirma pagamento é o gateway');
  end if;
  if v_ord.status = 'estornado' then
    return jsonb_build_object('ok', false, 'erro',
      'esse pedido foi estornado, e isso vem do gateway, não daqui');
  end if;
  if v_ord.status = v_novo then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'status', v_novo);
  end if;

  update public.orders
     set status       = v_novo,
         entregue_em  = case when v_novo = 'entregue' then coalesce(entregue_em, now()) else null end,
         entregue_por = case when v_novo = 'entregue' then coalesce(entregue_por, v_uid) else null end,
         updated_at   = now()
   where id = p_order_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'pedido_status_arrumado', 'orders', p_order_id::text,
          jsonb_build_object('de', v_ord.status, 'para', v_novo));

  return jsonb_build_object('ok', true, 'status', v_novo);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_resgate_desfazer — o conserto que mais faltava.
-- Resgate errado (a pessoa clicou sem querer, ou a casa não tinha o mimo)
-- custava os pontos pra sempre, porque o ledger é append-only e ninguém tinha
-- como lançar a volta. Aqui a volta é OUTRO lançamento, positivo, idempotente
-- por (ref_type, ref_id): reenviar o pedido não devolve duas vezes. Se a
-- recompensa tinha estoque, ele volta; se tinha cupom, ele sai de circulação.
-- ---------------------------------------------------------------------------
create or replace function public.admin_resgate_desfazer(
  p_redemption_id uuid,
  p_motivo        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_red    public.redemptions;
  v_nome   text;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_ja     boolean;
  v_codigo text;
begin
  if not public.tem_permissao('resgates.arrumar') then
    raise exception 'sem permissão pra desfazer resgate';
  end if;

  -- Trava a linha da PESSOA antes da do resgate, a mesma ordem da
  -- `redeem_reward` (0013). Ordem única = ninguém trava ninguém.
  select * into v_red from public.redemptions where id = p_redemption_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'resgate não encontrado');
  end if;
  perform 1 from public.profiles where id = v_red.user_id for update;
  select * into v_red from public.redemptions where id = p_redemption_id for update;

  if v_red.status = 'cancelado' then
    return jsonb_build_object('ok', true, 'ja_estava', true);
  end if;

  select coalesce(rw.nome, 'recompensa') into v_nome
    from public.rewards_catalog rw where rw.id = v_red.reward_id;
  v_nome := coalesce(v_nome, 'recompensa');

  -- A devolução dos pontos. O índice único (ref_type, ref_id) da 0008 é quem
  -- garante que não devolve duas vezes.
  select exists (
    select 1 from public.points_ledger
     where ref_type = 'estorno_resgate' and ref_id = p_redemption_id::text
  ) into v_ja;

  if not v_ja and v_red.pontos_gastos > 0 then
    insert into public.points_ledger (user_id, delta, motivo, redemption_id, descricao, ref_type, ref_id)
    values (v_red.user_id, v_red.pontos_gastos, 'devolução de resgate', p_redemption_id,
            coalesce(v_motivo, v_nome), 'estorno_resgate', p_redemption_id::text);
  end if;

  -- Estoque volta pra vitrine.
  if v_red.reward_id is not null then
    update public.rewards_catalog
       set estoque = estoque + 1
     where id = v_red.reward_id and estoque is not null;
  end if;

  -- Cupom gerado por este resgate sai de circulação.
  delete from public.coupons where redemption_id = p_redemption_id
  returning codigo into v_codigo;

  update public.redemptions
     set status = 'cancelado', updated_at = now()
   where id = p_redemption_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'resgate_desfeito', 'redemptions', p_redemption_id::text,
          jsonb_build_object('pontos', v_red.pontos_gastos, 'recompensa', v_nome,
                             'motivo', coalesce(v_motivo, ''), 'cupom', coalesce(v_codigo, ''),
                             'pontos_ja_devolvidos', v_ja));

  return jsonb_build_object('ok', true, 'devolvidos', case when v_ja then 0 else v_red.pontos_gastos end);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_brinde_arrumar — o brunch de aniversário.
--   'desfazer'  o código voltou pra 'ativo' (a baixa foi no código errado)
--   'esticar'   mais 30 dias de validade (a pessoa não conseguiu vir a tempo)
-- ---------------------------------------------------------------------------
create or replace function public.admin_brinde_arrumar(p_id uuid, p_acao text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_acao   text := btrim(coalesce(p_acao, ''));
  v_brinde public.brindes_aniversario;
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_novo   date;
begin
  if not public.tem_permissao('aniversarios.arrumar') then
    raise exception 'sem permissão pra arrumar brinde';
  end if;
  if v_acao not in ('desfazer', 'esticar') then
    return jsonb_build_object('ok', false, 'erro', 'não conheço esse conserto');
  end if;

  select * into v_brinde from public.brindes_aniversario where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'brinde não encontrado');
  end if;

  if v_acao = 'desfazer' then
    if v_brinde.status <> 'usado' then
      return jsonb_build_object('ok', true, 'ja_estava', true);
    end if;
    update public.brindes_aniversario
       set status = 'ativo', usado_em = null, usado_por = null
     where id = p_id;

    insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
    values (v_uid, 'brinde_baixa_desfeita', 'brindes_aniversario', p_id::text,
            jsonb_build_object('codigo', v_brinde.codigo));

    return jsonb_build_object('ok', true, 'situacao', 'ativo');
  end if;

  v_novo := greatest(v_hoje, v_brinde.valido_ate) + 30;
  update public.brindes_aniversario set valido_ate = v_novo where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'brinde_esticado', 'brindes_aniversario', p_id::text,
          jsonb_build_object('codigo', v_brinde.codigo, 'de', v_brinde.valido_ate, 'para', v_novo));

  return jsonb_build_object('ok', true, 'valido_ate', to_char(v_novo, 'DD/MM'));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_presente_arrumar — os dois presentes que travam.
--   'gerar_codigo'  presente PAGO que ficou sem código (o webhook caiu entre o
--                   pagamento e a `marcar_presente_pago`). Sem isso, quem pagou
--                   ficava com um presente que não existe em lugar nenhum.
--   'cancelar'      presente PENDENTE que nunca fechou o checkout, pra sair da
--                   lista. Presente pago NÃO se cancela por aqui: o código já
--                   pode estar na mão de alguém.
-- ---------------------------------------------------------------------------
create or replace function public.admin_presente_arrumar(p_id uuid, p_acao text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_acao   text := btrim(coalesce(p_acao, ''));
  v_gift   public.gift_subscriptions;
  v_codigo text;
begin
  if not public.tem_permissao('presentes.arrumar') then
    raise exception 'sem permissão pra arrumar presente';
  end if;
  if v_acao not in ('gerar_codigo', 'cancelar') then
    return jsonb_build_object('ok', false, 'erro', 'não conheço esse conserto');
  end if;

  select * into v_gift from public.gift_subscriptions where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'presente não encontrado');
  end if;

  if v_acao = 'cancelar' then
    if v_gift.status = 'cancelado' then
      return jsonb_build_object('ok', true, 'ja_estava', true);
    end if;
    if v_gift.status <> 'pendente' then
      return jsonb_build_object('ok', false, 'erro',
        'esse presente já foi pago, e o código pode estar com alguém');
    end if;
    update public.gift_subscriptions set status = 'cancelado', updated_at = now() where id = p_id;

    insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
    values (v_uid, 'presente_cancelado', 'gift_subscriptions', p_id::text, '{}'::jsonb);

    return jsonb_build_object('ok', true, 'status', 'cancelado');
  end if;

  if v_gift.codigo is not null then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'codigo', v_gift.codigo);
  end if;
  if v_gift.status <> 'pago' then
    return jsonb_build_object('ok', false, 'erro',
      'só presente pago ganha código, e quem confirma o pagamento é o gateway');
  end if;

  loop
    v_codigo := 'CASA-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.gift_subscriptions where codigo = v_codigo);
  end loop;

  update public.gift_subscriptions set codigo = v_codigo, updated_at = now() where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'presente_codigo_gerado', 'gift_subscriptions', p_id::text,
          jsonb_build_object('codigo', v_codigo));

  return jsonb_build_object('ok', true, 'codigo', v_codigo);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_espera_remover — "me tira dessa lista".
-- O e-mail apagado NÃO vai pro audit_log: guardar o endereço num outro lugar
-- depois de a pessoa pedir pra sair é apagar da tela e manter na gaveta. Fica
-- só o domínio, que é o suficiente pra entender o que aconteceu.
-- ---------------------------------------------------------------------------
create or replace function public.admin_espera_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
begin
  if not public.tem_permissao('espera.arrumar') then
    raise exception 'sem permissão pra mexer na lista de espera';
  end if;

  delete from public.lista_espera where id = p_id returning email into v_email;
  if v_email is null then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'lista_espera_removida', 'lista_espera', p_id::text,
          jsonb_build_object('dominio', split_part(v_email, '@', 2)));

  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_lead_evento_remover — apagar um pedido de evento (a pessoa pediu, ou
-- é spam). Nome e telefone não vão pro audit_log, pelo mesmo motivo de cima.
-- ---------------------------------------------------------------------------
create or replace function public.admin_lead_evento_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_tipo text;
begin
  if not public.tem_permissao('leads.arrumar') then
    raise exception 'sem permissão pra apagar pedido de evento';
  end if;

  delete from public.leads_evento where id = p_id returning tipo into v_tipo;
  if v_tipo is null then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'lead_evento_removido', 'leads_evento', p_id::text,
          jsonb_build_object('tipo', v_tipo));

  return jsonb_build_object('ok', true);
end;
$$;


-- =============================================================================
-- 11. Grants — deslogado não alcança nada
-- =============================================================================
revoke all on function public.admin_permissoes_catalogo()                  from public, anon;
revoke all on function public.admin_assinaturas(text, text, int)           from public, anon;
revoke all on function public.admin_assinatura_esticar(uuid, integer)      from public, anon;
revoke all on function public.admin_pontos_pessoas(text, int)              from public, anon;
revoke all on function public.admin_pontos_extrato(uuid, int)              from public, anon;
revoke all on function public.admin_pontos_ajustar(uuid, integer, text)    from public, anon;
revoke all on function public.admin_pedido_status(uuid, text)              from public, anon;
revoke all on function public.admin_resgate_desfazer(uuid, text)           from public, anon;
revoke all on function public.admin_brinde_arrumar(uuid, text)             from public, anon;
revoke all on function public.admin_presente_arrumar(uuid, text)           from public, anon;
revoke all on function public.admin_espera_remover(uuid)                   from public, anon;
revoke all on function public.admin_lead_evento_remover(uuid)              from public, anon;

grant execute on function public.admin_permissoes_catalogo()               to authenticated;
grant execute on function public.admin_assinaturas(text, text, int)        to authenticated;
grant execute on function public.admin_assinatura_esticar(uuid, integer)   to authenticated;
grant execute on function public.admin_pontos_pessoas(text, int)           to authenticated;
grant execute on function public.admin_pontos_extrato(uuid, int)           to authenticated;
grant execute on function public.admin_pontos_ajustar(uuid, integer, text) to authenticated;
grant execute on function public.admin_pedido_status(uuid, text)           to authenticated;
grant execute on function public.admin_resgate_desfazer(uuid, text)        to authenticated;
grant execute on function public.admin_brinde_arrumar(uuid, text)          to authenticated;
grant execute on function public.admin_presente_arrumar(uuid, text)        to authenticated;
grant execute on function public.admin_espera_remover(uuid)                to authenticated;
grant execute on function public.admin_lead_evento_remover(uuid)           to authenticated;

-- As tabelas de catálogo: leitura pela RLS (quem entra no console), escrita
-- nenhuma. Sem grant de insert/update/delete pra ninguém.
grant select on public.permissao_secoes, public.permissao_paginas,
                public.permissoes, public.permissoes_legado to authenticated;



-- ===== 0048_casa_club.sql =====

-- =============================================================================
-- 0048_casa_club.sql — o clube vira uma assinatura só ☕
--
-- O PEDIDO (documento "Projeto CASA CLUB", ago/2026): em vez de quatro planos
-- pagos, UMA assinatura. "O membro não paga mais para pertencer mais: ele sobe
-- de categoria conforme o tempo de permanência no Clube."
--
-- O QUE MUDA DE SIGNIFICADO: os quatro nomes que já estão na tabela `tiers`
-- (Vizinho de Sempre, Frequentador, Gente do Casa, Alma do Casa) deixam de ser
-- PREÇO e passam a ser TEMPO DE CASA (0-3, 3-6, 6-12, 12+ meses). Os quatro
-- custam o mesmo, dão o mesmo desconto e o mesmo 1 ponto por R$1. O que muda de
-- um pro outro é só o reconhecimento de quem fica.
--
-- OS SLUGS NÃO MUDAM, e isso é decisão, não esquecimento: `bronze` é o Vizinho
-- de Sempre, `prata` o Frequentador, `ouro` o Gente do Casa e `diamante` o Alma
-- do Casa. O `tier_slug` está espalhado por mais de trinta pontos entre front,
-- Edge Functions e migrations, com FK vindo de `subscriptions`,
-- `gift_subscriptions` e `profiles`. Renomear pediria UPDATE em dado histórico
-- de produção pra ganhar só legibilidade interna, e o slug nunca aparece na
-- tela de ninguém.
--
-- POR QUE `vendavel` É COLUNA NOVA E NÃO O `ativo` QUE JÁ EXISTE: o
-- `getUserTierDiscount` (_shared/lib.ts) devolve tier_slug NULO quando o tier
-- está `ativo = false`, e o `creditPoints` dá ZERO ponto com slug nulo. Marcar
-- as três categorias superiores como inativas faria quem sobe de categoria
-- parar de pontuar e perder o desconto no mesmo instante em que a casa quis
-- agradecer a permanência. As quatro seguem `ativo = true`.
--
-- O RELÓGIO ACUMULA, NÃO CORRE NO CALENDÁRIO: quem ficou 4 meses, pausou 6 e
-- voltou, volta com 4 meses de casa, não com 10. Por isso o tempo é a UNIÃO dos
-- períodos das assinaturas da pessoa, e não a soma crua: presente resgatado
-- durante uma assinatura ativa contaria o mesmo mês duas vezes.
--
-- SEM CRON: quem promove é o `sincronizar_categoria`, chamado (a) pelo
-- asaas-webhook a cada pagamento de renovação, que é o único evento mensal que
-- o site já recebe de graça, e (b) pela leitura da tela do clube, que se
-- auto-cura se o webhook falhar.
--
-- AS CONQUISTAS NÃO PRECISARAM MUDAR: a `gente-do-casa` e a `alma-do-casa` já
-- tinham critério `{"type":"tier","slug":"ouro"|"diamante"}` desde a 0009.
-- Como a categoria agora mora no mesmo `tier_slug`, elas viram sozinhas o
-- carimbo de chegada na categoria, que é o que o documento pede.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. As duas colunas novas da `tiers`.
--    vendavel  → é esta a categoria que se compra (só a de entrada).
--    meses_min → o tempo de casa a partir do qual a categoria vale.
-- -----------------------------------------------------------------------------
alter table public.tiers add column if not exists vendavel  boolean not null default false;
alter table public.tiers add column if not exists meses_min integer not null default 0;

comment on column public.tiers.vendavel is
  'Categoria comprável. Só a de entrada. NÃO usar `ativo` pra isso: tier inativo zera desconto e pontos.';
comment on column public.tiers.meses_min is
  'Meses de casa (tempo ACUMULADO de assinatura) a partir dos quais esta categoria vale.';

-- Só pode haver UMA categoria vendável. Se um dia voltarem os planos pagos,
-- este índice é o que precisa cair primeiro, e é de propósito que ele avise.
create unique index if not exists idx_tiers_vendavel_unica
  on public.tiers ((true)) where vendavel;

-- -----------------------------------------------------------------------------
-- 2. As quatro categorias. Mesmo preço, mesmo desconto, mesmo 1 ponto por R$1.
--    As duas duplas de colunas (desconto_pct/pontos_multiplicador da 0001 e
--    discount_percent/points_multiplier da 0004) andam juntas: a 0004 criou a
--    segunda dupla e as Edge Functions leem dela, mas deixar a primeira
--    divergindo é armar uma pegadinha pro próximo que ler a tabela.
-- -----------------------------------------------------------------------------
update public.tiers set
  preco_centavos       = 4990,
  desconto_pct         = 10,
  discount_percent     = 10,
  pontos_multiplicador = 1.00,
  points_multiplier    = 1.00,
  ativo                = true,
  destaque             = false
where slug in ('bronze', 'prata', 'ouro', 'diamante');

update public.tiers set nome = 'Vizinho de Sempre', vendavel = true,  meses_min = 0,  ordem = 1 where slug = 'bronze';
update public.tiers set nome = 'Frequentador',      vendavel = false, meses_min = 3,  ordem = 2 where slug = 'prata';
update public.tiers set nome = 'Gente do Casa',     vendavel = false, meses_min = 6,  ordem = 3 where slug = 'ouro';
update public.tiers set nome = 'Alma do Casa',      vendavel = false, meses_min = 12, ordem = 4 where slug = 'diamante';

-- Qualquer tier fora dos quatro (nenhum hoje) fica explicitamente não-vendável,
-- pra ninguém comprar categoria por um slug esquecido.
update public.tiers set vendavel = false where slug not in ('bronze', 'prata', 'ouro', 'diamante');

-- -----------------------------------------------------------------------------
-- 3. dias_de_casa — o tempo ACUMULADO, pela UNIÃO dos períodos.
--
--    Cada assinatura cobre [created_at, current_period_end], cortado em now()
--    (tempo futuro não é tempo vivido). A soma crua contaria duas vezes o mês em
--    que um presente foi resgatado por cima de uma assinatura ativa, então os
--    períodos que se tocam viram uma ilha só antes de somar.
--
--    Assinatura 'cancelada' entra: o tempo já vivido não some quando o gateway
--    encerra. Pausa não conta (o período dela termina) e não zera nada.
-- -----------------------------------------------------------------------------
create or replace function public.dias_de_casa(p_user uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  with periodos as (
    select s.created_at as inicio,
           least(coalesce(s.current_period_end, s.created_at), now()) as fim
      from public.subscriptions s
     where s.user_id = p_user
       and s.status in ('ativa', 'pausada', 'cancelada')
  ),
  validos as (
    select inicio, fim from periodos where fim > inicio
  ),
  marcados as (
    -- 1 quando este período começa depois do fim de todos os anteriores (ilha nova).
    select inicio, fim,
           case
             when max(fim) over (
                    order by inicio, fim
                    rows between unbounded preceding and 1 preceding
                  ) >= inicio then 0
             else 1
           end as nova_ilha
      from validos
  ),
  ilhas as (
    select inicio, fim,
           sum(nova_ilha) over (order by inicio, fim rows unbounded preceding) as ilha
      from marcados
  ),
  unidos as (
    select min(inicio) as inicio, max(fim) as fim from ilhas group by ilha
  )
  select coalesce(floor(sum(extract(epoch from (fim - inicio))) / 86400)::integer, 0)
    from unidos;
$$;

-- Recebe user_id por parâmetro, então NÃO vai pro client (leria o tempo de casa
-- de qualquer pessoa). Quem serve o front é a `meu_clube`, que usa auth.uid().
revoke all on function public.dias_de_casa(uuid) from public, anon, authenticated;
grant execute on function public.dias_de_casa(uuid) to service_role;

-- Um mês = 30 dias. A Asaas renova em ciclo MONTHLY (~30,44 dias na média), então
-- o marco de 12 meses cai uns cinco dias antes. O arredondamento fica a favor de
-- quem fica, que é o lado certo pra errar.
create or replace function public.meses_de_casa(p_user uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select floor(public.dias_de_casa(p_user) / 30.0)::integer;
$$;

revoke all on function public.meses_de_casa(uuid) from public, anon, authenticated;
grant execute on function public.meses_de_casa(uuid) to service_role;

-- -----------------------------------------------------------------------------
-- 4. categoria_por_tempo — a categoria de maior `meses_min` que cabe no tempo.
-- -----------------------------------------------------------------------------
create or replace function public.categoria_por_tempo(p_meses integer)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select t.slug
    from public.tiers t
   where t.ativo = true
     and t.meses_min <= greatest(coalesce(p_meses, 0), 0)
   order by t.meses_min desc, t.ordem desc
   limit 1;
$$;

revoke all on function public.categoria_por_tempo(integer) from public, anon;
grant execute on function public.categoria_por_tempo(integer) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5. sincronizar_categoria — põe o `tier_slug` no lugar certo.
--
--    A categoria mora no `tier_slug` (e não só na tela do clube) porque header,
--    painel do avatar, cartão do /gente, perfil e console já leem esse campo:
--    escrevendo aqui, todos passam a mostrar a categoria certa sem mudar uma
--    linha. Se fosse derivada só na tela, o perfil diria "Vizinho de Sempre" pra
--    quem tem dois anos de casa.
--
--    Regra de quem TEM benefício vigente = a mesma do getEffectiveSubscription
--    das Edge Functions: 'ativa' sempre concede; 'pausada' concede enquanto o
--    período pago não venceu. Sem nenhuma que conceda, o tier é limpo (auto-cura,
--    igual à do lib.ts) — senão a categoria virava benefício vitalício de graça.
--
--    Só escreve quando há diferença, então chamar duas vezes seguidas é inócuo.
-- -----------------------------------------------------------------------------
create or replace function public.sincronizar_categoria(p_user uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub        record;
  v_meses      integer;
  v_alvo       text;
  v_tier_atual text;
  v_mudou      boolean := false;
begin
  if p_user is null then
    return null;
  end if;

  select s.id, s.tier_slug
    into v_sub
    from public.subscriptions s
   where s.user_id = p_user
     and s.status in ('ativa', 'pausada')
     and (s.status = 'ativa' or (s.current_period_end is not null and s.current_period_end > now()))
   order by s.current_period_end desc nulls last
   limit 1;

  select p.tier_slug into v_tier_atual from public.profiles p where p.id = p_user;

  -- Ninguém concedendo benefício agora: limpa o tier (auto-cura).
  if not found or v_sub.id is null then
    if v_tier_atual is not null then
      perform set_config('casa.trusted_points', 'on', true);
      update public.profiles set tier_slug = null where id = p_user;
    end if;
    return null;
  end if;

  v_meses := public.meses_de_casa(p_user);
  v_alvo  := public.categoria_por_tempo(v_meses);
  if v_alvo is null then
    return v_tier_atual;
  end if;

  if v_sub.tier_slug is distinct from v_alvo then
    update public.subscriptions set tier_slug = v_alvo, updated_at = now() where id = v_sub.id;
    v_mudou := true;
  end if;

  if v_tier_atual is distinct from v_alvo then
    -- A GUC libera a trigger prevent_points_tamper (0005/0008), que barra
    -- escrita de tier_slug vinda de sessão autenticada.
    perform set_config('casa.trusted_points', 'on', true);
    update public.profiles set tier_slug = v_alvo, updated_at = now() where id = p_user;
    v_mudou := true;
  end if;

  -- Subiu de categoria: a conquista do marco é avaliada na hora, senão o
  -- emblema só apareceria na próxima compra.
  if v_mudou then
    perform public.check_achievements(p_user);
    insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
    values (null, 'categoria_sincronizada', 'profiles', p_user::text,
            jsonb_build_object('de', v_tier_atual, 'para', v_alvo, 'meses', v_meses));
  end if;

  return v_alvo;
end;
$$;

revoke all on function public.sincronizar_categoria(uuid) from public, anon, authenticated;
grant execute on function public.sincronizar_categoria(uuid) to service_role;

-- -----------------------------------------------------------------------------
-- 6. meu_clube — tudo que a tela do clube precisa, numa viagem só.
--
--    Usa auth.uid(): o client nunca diz de quem é o clube, nem quanto tempo tem
--    de casa. Sincroniza a própria categoria antes de responder (auto-cura).
-- -----------------------------------------------------------------------------
create or replace function public.meu_clube()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_sub      record;
  v_dias     integer;
  v_meses    integer;
  v_slug     text;
  v_atual    record;
  v_proxima  record;
  v_saldo    integer;
begin
  if v_user is null then
    raise exception 'precisa estar logado pra ver o clube.';
  end if;

  v_slug := public.sincronizar_categoria(v_user);
  v_dias := public.dias_de_casa(v_user);
  v_meses := floor(v_dias / 30.0)::integer;

  select s.status, s.current_period_end, s.presente_id
    into v_sub
    from public.subscriptions s
   where s.user_id = v_user
     and s.status in ('ativa', 'pausada')
     and (s.status = 'ativa' or (s.current_period_end is not null and s.current_period_end > now()))
   order by s.current_period_end desc nulls last
   limit 1;

  select coalesce(points_balance, 0) into v_saldo from public.profiles where id = v_user;

  -- A categoria mostrada é a vigente quando há plano; sem plano, a que o tempo
  -- de casa já garante (fica de memória do que a pessoa foi, sem conceder nada).
  select t.slug, t.nome, t.meses_min, t.ordem
    into v_atual
    from public.tiers t
   where t.slug = coalesce(v_slug, public.categoria_por_tempo(v_meses));

  select t.slug, t.nome, t.meses_min
    into v_proxima
    from public.tiers t
   where t.ativo = true
     and t.meses_min > coalesce(v_atual.meses_min, 0)
   order by t.meses_min asc
   limit 1;

  return jsonb_build_object(
    'tem_plano',        v_slug is not null,
    'status',           v_sub.status,
    'ativo_ate',        v_sub.current_period_end,
    'eh_presente',      v_sub.presente_id is not null,
    'dias',             v_dias,
    'meses',            v_meses,
    'saldo',            coalesce(v_saldo, 0),
    'categoria',        case when v_atual.slug is null then null else jsonb_build_object(
                          'slug', v_atual.slug, 'nome', v_atual.nome, 'meses_min', v_atual.meses_min) end,
    'proxima',          case when v_proxima.slug is null then null else jsonb_build_object(
                          'slug', v_proxima.slug, 'nome', v_proxima.nome, 'meses_min', v_proxima.meses_min,
                          'dias_faltando', greatest(v_proxima.meses_min * 30 - v_dias, 0)) end,
    'categorias',       (select coalesce(jsonb_agg(jsonb_build_object(
                            'slug', t.slug, 'nome', t.nome, 'meses_min', t.meses_min,
                            'atingida', t.meses_min <= v_meses) order by t.meses_min), '[]'::jsonb)
                           from public.tiers t where t.ativo = true)
  );
end;
$$;

revoke all on function public.meu_clube() from public, anon;
grant execute on function public.meu_clube() to authenticated;



-- ===== 0049_preco_do_clube.sql =====

-- =============================================================================
-- 0049_preco_do_clube.sql — a assinatura do clube passa a R$88,90 💛
--
-- O PEDIDO (18/ago/2026, direto da casa): o valor da assinatura sobe de R$49,90
-- pra R$88,90. O R$49,90 da 0048 era o "valor estratégico inicial, a validar" que
-- o documento do CASA CLUB já marcava como provisório.
--
-- POR QUE É ARQUIVO NOVO E NÃO UMA EDIÇÃO DA 0048: migration aplicada é imutável
-- (a 0048 já rodou em produção em 18/ago). Mudança nova = arquivo novo.
--
-- AS QUATRO CATEGORIAS ANDAM JUNTAS. Elas custam o mesmo desde a 0048, porque a
-- categoria é tempo de casa e não preço. Deixar só a vendável subir criaria uma
-- escada de preço fantasma no banco: ninguém compra as outras três hoje, mas a
-- `create-checkout-session` lê `preco_centavos` do tier pra montar o valor do
-- presente e do checkout, e o dia em que alguma delas voltar a ser vendável ela
-- estaria com o preço velho.
--
-- O QUE ESTE ARQUIVO **NÃO** FAZ: mexer nas assinaturas que já existem no Asaas.
-- Lá o `value` de cada assinatura foi gravado no dia em que ela nasceu, e só muda
-- por `PUT /subscriptions/{id}`. Então quem já assina **segue pagando o valor
-- antigo** até alguém mudar no painel do Asaas, e isso é decisão da casa (mexer no
-- preço de assinatura viva é conversa com quem assinou, não migration). O preço
-- novo vale pra quem assinar de agora em diante, e pros presentes comprados daqui
-- pra frente.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente.
-- =============================================================================

update public.tiers
   set preco_centavos = 8890
 where slug in ('bronze', 'prata', 'ouro', 'diamante');



-- ===== 0050_brunches.sql =====

-- =============================================================================
-- 0050_brunches.sql — os dois brunches viram voucher de verdade 🥐
--
-- O PEDIDO (18/ago/2026): o platter brunch mensal do CASA CLUB deixa de ser
-- promessa de vitrine e vira resgate com código, no mesmo desenho do sistema de
-- pontos. E o brunch de ANIVERSÁRIO muda de régua: **não exige mais assinatura**
-- (quem faz aniversário ganha, sendo do clube ou não) e passa a ter uma janela
-- de **7 dias** pra pegar e usar.
--
-- OS DOIS SÃO A MESMA MECÂNICA, e é de propósito: a pessoa resgata na conta,
-- recebe um `CASA-XXXXXX`, mostra no balcão, o staff dá baixa no console. Quem
-- trabalha no salão aprende UMA coisa e serve as duas.
--
-- O QUE MUDA DE CADA UM:
--   • MENSAL   → perk de ASSINANTE (`tier_slug`), um por mês do calendário
--                (UNIQUE user+ano+mês). Não acumula: o de agosto morre em agosto,
--                senão dava pra juntar doze e sentar em dezembro.
--   • ANIVERSÁRIO → **de qualquer pessoa com conta**, um por ano, e só dentro dos
--                7 dias que começam no dia do aniversário. A 0025 dava o MÊS
--                inteiro e exigia plano; as duas coisas mudaram aqui.
--
-- POR QUE O MENSAL É TABELA NOVA E NÃO UMA COLUNA NA `brindes_aniversario`: a
-- chave natural dos dois é diferente (ano vs ano+mês), e enfiar os dois na mesma
-- tabela pediria um UNIQUE parcial por tipo mais um `mes` nulo pro aniversário.
-- Tabela irmã é mais simples de ler e o console junta as duas na leitura.
--
-- SEGURANÇA (ver CLAUDE.md › Segurança): tabela deny-by-default pro client (só
-- LÊ o próprio, e o staff com `aniversarios.ver` lê todos); escrita só pelas RPCs
-- SECURITY DEFINER, que **recomputam todas as travas no banco** (assinatura, mês,
-- janela, duplicidade). O front é conforto, não porteiro.
--
-- PERMISSÃO: reusa a página `aniversarios` do catálogo da 0047 (`.ver`/`.mexer`/
-- `.arrumar`). Não é permissão nova: quem confere brunch no balcão confere os
-- dois, e criar uma página nova pediria mexer no catálogo pra separar o que na
-- prática é o mesmo trabalho. A aba passa a se chamar "brunches".
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. aniversario_no_ano — a data do aniversário num ano qualquer.
--    Existe por causa do 29/02: `make_date(2027, 2, 29)` estoura em vez de
--    devolver nulo, então quem nasceu em ano bissexto perderia o brunde num ano
--    comum, com erro na cara. Cai pro 28/02.
-- -----------------------------------------------------------------------------
create or replace function public.aniversario_no_ano(p_nascimento date, p_ano integer)
returns date
language plpgsql
immutable
set search_path = public
as $$
declare
  v_mes integer := extract(month from p_nascimento)::int;
  v_dia integer := extract(day   from p_nascimento)::int;
begin
  if p_nascimento is null or p_ano is null then
    return null;
  end if;
  begin
    return make_date(p_ano, v_mes, v_dia);
  exception when others then
    return make_date(p_ano, v_mes, v_dia - 1); -- 29/02 em ano comum → 28/02
  end;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. brunches_mensais — o platter brunch de quem assina, um por mês.
-- -----------------------------------------------------------------------------
create table if not exists public.brunches_mensais (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  ano         integer not null,
  mes         integer not null check (mes between 1 and 12),
  codigo      text not null unique,             -- CASA-XXXXXX (mostra no balcão)
  valido_ate  date not null,
  status      text not null default 'ativo' check (status in ('ativo', 'usado')),
  usado_em    timestamptz,
  usado_por   uuid references public.profiles (id) on delete set null,
  criado_em   timestamptz not null default now(),
  unique (user_id, ano, mes)
);

create index if not exists idx_brunches_mensais_status
  on public.brunches_mensais (status, valido_ate);

alter table public.brunches_mensais enable row level security;

drop policy if exists brunches_mensais_select_own on public.brunches_mensais;
create policy brunches_mensais_select_own on public.brunches_mensais
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('aniversarios.ver'));

-- O SELECT do client passa pela policy acima; o grant de tabela é o que o
-- PostgREST exige ANTES de a RLS ser consultada. As tabelas anteriores contam
-- com o default privilege que o Supabase deixa armado no schema public, mas
-- escrever aqui tira a dependência de um ajuste de ambiente que não está em
-- migration nenhuma. Só SELECT: escrita continua sendo só pelas RPCs.
grant select on public.brunches_mensais to authenticated;

-- -----------------------------------------------------------------------------
-- 3. meu_brunch_mensal() → o estado do card do perfil. Só LÊ.
-- -----------------------------------------------------------------------------
create or replace function public.meu_brunch_mensal()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_prof  public.profiles;
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ano   integer := extract(year  from v_hoje)::int;
  v_mes   integer := extract(month from v_hoje)::int;
  v_b     public.brunches_mensais;
  v_sit   text := null;
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  select * into v_prof from public.profiles where id = v_uid;

  select * into v_b
    from public.brunches_mensais
   where user_id = v_uid and ano = v_ano and mes = v_mes;

  if found then
    v_sit := case when v_b.status = 'usado' then 'usado'
                  when v_b.valido_ate < v_hoje then 'expirado'
                  else 'ativo' end;
  end if;

  return jsonb_build_object(
    'assinante',   coalesce(v_prof.tier_slug is not null, false),
    'ja_resgatou', found,
    'codigo',      v_b.codigo,
    'valido_ate',  v_b.valido_ate,
    'situacao',    v_sit,
    'usado_em',    v_b.usado_em,
    'mes',         v_mes,
    'ano',         v_ano
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. resgatar_brunch_mensal() → reserva o brunch DESTE mês.
--    Validade: até o fim do mês, com piso de 7 dias. O piso existe pra quem
--    resgata no dia 30 não ganhar um voucher que vence amanhã; ele pode encostar
--    nos primeiros dias do mês seguinte, e tudo bem, aquele mês foi pago.
-- -----------------------------------------------------------------------------
create or replace function public.resgatar_brunch_mensal()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_prof   public.profiles;
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ano    integer := extract(year  from v_hoje)::int;
  v_mes    integer := extract(month from v_hoje)::int;
  v_fimmes date := (date_trunc('month', v_hoje)::date + interval '1 month - 1 day')::date;
  v_valido date := greatest(v_fimmes, v_hoje + 6);
  v_b      public.brunches_mensais;
  v_codigo text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'precisa estar logado');
  end if;

  -- Serializa os resgates do PRÓPRIO usuário (mesmo padrão do redeem_reward).
  perform 1 from public.profiles where id = v_uid for update;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'perfil não encontrado');
  end if;

  if v_prof.tier_slug is null then
    return jsonb_build_object('ok', false, 'precisa_assinar', true,
      'erro', 'o platter brunch do mês é de quem faz parte do clube 💛');
  end if;

  select * into v_b
    from public.brunches_mensais
   where user_id = v_uid and ano = v_ano and mes = v_mes;
  if found then
    return jsonb_build_object('ok', true, 'ja_tinha', true,
      'codigo', v_b.codigo, 'valido_ate', v_b.valido_ate, 'status', v_b.status);
  end if;

  loop
    v_codigo := 'CASA-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.brunches_mensais where codigo = v_codigo)
          and not exists (select 1 from public.brindes_aniversario where codigo = v_codigo);
  end loop;

  begin
    insert into public.brunches_mensais (user_id, ano, mes, codigo, valido_ate)
    values (v_uid, v_ano, v_mes, v_codigo, v_valido)
    returning * into v_b;
  exception when unique_violation then
    select * into v_b
      from public.brunches_mensais
     where user_id = v_uid and ano = v_ano and mes = v_mes;
    return jsonb_build_object('ok', true, 'ja_tinha', true,
      'codigo', v_b.codigo, 'valido_ate', v_b.valido_ate, 'status', v_b.status);
  end;

  return jsonb_build_object('ok', true, 'novo', true,
    'codigo', v_b.codigo, 'valido_ate', v_b.valido_ate);
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. meu_brinde_aniversario() — REESCRITA.
--    Some a régua de assinatura (aniversário é de todo mundo) e o "mês inteiro"
--    vira a JANELA DE 7 DIAS que começa no dia. Devolve as chaves antigas
--    (`eh_mes`, `assinante`) pra nada que já lê isso quebrar, mais as novas.
--
--    A janela é contada a partir do aniversário MAIS RECENTE, não do deste ano:
--    quem faz aniversário em 30/dez e entra em 2/jan ainda está dentro dos 7
--    dias, e o `ano` do brinde continua sendo o do aniversário.
-- -----------------------------------------------------------------------------
create or replace function public.meu_brinde_aniversario()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_prof   public.profiles;
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_aniv   date;
  v_fim    date;
  v_ano    integer;
  v_brinde public.brindes_aniversario;
  v_sit    text := null;
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('tem_data', false, 'assinante', false);
  end if;

  if v_prof.nascimento is null then
    return jsonb_build_object(
      'tem_data', false,
      'assinante', v_prof.tier_slug is not null,
      'eh_mes', false, 'eh_dia', false, 'na_janela', false, 'ja_resgatou', false);
  end if;

  -- O aniversário mais recente (o deste ano, ou o do ano passado se ainda não chegou).
  v_aniv := public.aniversario_no_ano(v_prof.nascimento, extract(year from v_hoje)::int);
  if v_aniv > v_hoje then
    v_aniv := public.aniversario_no_ano(v_prof.nascimento, extract(year from v_hoje)::int - 1);
  end if;
  v_fim := v_aniv + 6;                       -- o dia + 6 = os 7 dias
  v_ano := extract(year from v_aniv)::int;

  select * into v_brinde
    from public.brindes_aniversario
   where user_id = v_uid and ano = v_ano;

  if found then
    v_sit := case when v_brinde.status = 'usado' then 'usado'
                  when v_brinde.valido_ate < v_hoje then 'expirado'
                  else 'ativo' end;
  end if;

  return jsonb_build_object(
    'tem_data',    true,
    'assinante',   v_prof.tier_slug is not null,
    'eh_mes',      extract(month from v_prof.nascimento) = extract(month from v_hoje),
    'eh_dia',      v_aniv = v_hoje,
    'na_janela',   v_hoje between v_aniv and v_fim,
    'janela_ate',  v_fim,
    'aniversario', v_aniv,
    'ja_resgatou', found,
    'codigo',      v_brinde.codigo,
    'valido_ate',  v_brinde.valido_ate,
    'situacao',    v_sit,
    'usado_em',    v_brinde.usado_em
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. resgatar_brinde_aniversario() — REESCRITA.
--    Sem exigência de plano. Só dentro dos 7 dias. O código vale até o fim da
--    própria janela: são 7 dias pra pegar E usar, não 7 pra pegar e mais 30 pra
--    usar (que era o desenho antigo, do tempo em que a janela era o mês inteiro).
-- -----------------------------------------------------------------------------
create or replace function public.resgatar_brinde_aniversario()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_prof   public.profiles;
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_aniv   date;
  v_fim    date;
  v_ano    integer;
  v_brinde public.brindes_aniversario;
  v_codigo text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'precisa estar logado');
  end if;

  perform 1 from public.profiles where id = v_uid for update;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'perfil não encontrado');
  end if;

  if v_prof.nascimento is null then
    return jsonb_build_object('ok', false, 'precisa_data', true,
      'erro', 'conta pra gente teu aniversário no perfil, aí a gente comemora 🎂');
  end if;

  v_aniv := public.aniversario_no_ano(v_prof.nascimento, extract(year from v_hoje)::int);
  if v_aniv > v_hoje then
    v_aniv := public.aniversario_no_ano(v_prof.nascimento, extract(year from v_hoje)::int - 1);
  end if;
  v_fim := v_aniv + 6;
  v_ano := extract(year from v_aniv)::int;

  if v_hoje > v_fim then
    return jsonb_build_object('ok', false, 'fora_da_janela', true,
      'erro', 'a semana do teu aniversário já passou, fica pro ano que vem e a gente comemora dobrado 💛');
  end if;

  select * into v_brinde
    from public.brindes_aniversario
   where user_id = v_uid and ano = v_ano;
  if found then
    return jsonb_build_object('ok', true, 'ja_tinha', true,
      'codigo', v_brinde.codigo, 'valido_ate', v_brinde.valido_ate,
      'status', v_brinde.status);
  end if;

  loop
    v_codigo := 'CASA-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.brindes_aniversario where codigo = v_codigo)
          and not exists (select 1 from public.brunches_mensais where codigo = v_codigo);
  end loop;

  begin
    insert into public.brindes_aniversario (user_id, ano, codigo, valido_ate)
    values (v_uid, v_ano, v_codigo, v_fim)
    returning * into v_brinde;
  exception when unique_violation then
    select * into v_brinde
      from public.brindes_aniversario
     where user_id = v_uid and ano = v_ano;
    return jsonb_build_object('ok', true, 'ja_tinha', true,
      'codigo', v_brinde.codigo, 'valido_ate', v_brinde.valido_ate,
      'status', v_brinde.status);
  end;

  return jsonb_build_object('ok', true, 'novo', true,
    'codigo', v_brinde.codigo, 'valido_ate', v_brinde.valido_ate);
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. admin_brunches_listar — a aba do console, com os DOIS numa lista só.
--    `returns jsonb` de propósito: leitura composta em `returns table` é onde a
--    0042 se queimou (varchar declarado como text derruba a função inteira na
--    primeira chamada). Em jsonb essa classe de erro não existe.
-- -----------------------------------------------------------------------------
create or replace function public.admin_brunches_listar(
  p_busca  text default null,
  p_status text default null,
  p_tipo   text default null,           -- 'mensal' | 'aniversario' | null (os dois)
  p_limite integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
  v_lim   integer := greatest(1, least(coalesce(p_limite, 200), 500));
  v_itens jsonb;
begin
  if not public.tem_permissao('aniversarios.ver') then
    raise exception 'sem permissão pra ver os brunches';
  end if;

  with tudo as (
    select b.id, 'mensal'::text as tipo, b.criado_em, b.codigo, b.status, b.valido_ate,
           b.usado_em, b.usado_por, b.user_id,
           to_char(make_date(b.ano, b.mes, 1), 'MM/YYYY') as referencia
      from public.brunches_mensais b
    union all
    select a.id, 'aniversario'::text, a.criado_em, a.codigo, a.status, a.valido_ate,
           a.usado_em, a.usado_por, a.user_id,
           to_char(pr0.nascimento, 'DD/MM')
      from public.brindes_aniversario a
      left join public.profiles pr0 on pr0.id = a.user_id
  ),
  enriquecido as (
    select t.*,
           case when t.status = 'usado' then 'usado'
                when t.valido_ate < v_hoje then 'expirado'
                else 'ativo' end                       as situacao,
           coalesce(pr.apelido, pr.full_name, '')      as cliente_nome,
           coalesce(u.email, '')::text                 as cliente_email,
           coalesce(baixa.full_name, '')               as usado_por_nome
      from tudo t
      left join public.profiles pr    on pr.id    = t.user_id
      left join auth.users      u     on u.id     = t.user_id
      left join public.profiles baixa on baixa.id = t.usado_por
  )
  select coalesce(jsonb_agg(sub.x order by sub.criado_em desc), '[]'::jsonb)
    into v_itens
    from (
      select jsonb_build_object(
               'id',               e.id,
               'tipo',             e.tipo,
               'criado_em',        e.criado_em,
               'codigo',           e.codigo,
               'situacao',         e.situacao,
               'valido_ate_label', to_char(e.valido_ate, 'DD/MM'),
               'referencia',       e.referencia,
               'cliente_nome',     e.cliente_nome,
               'cliente_email',    e.cliente_email,
               'usado_em',         e.usado_em,
               'usado_por_nome',   e.usado_por_nome
             ) as x,
             e.criado_em
        from enriquecido e
       where (p_tipo is null or e.tipo = p_tipo)
         and (v_busca is null
              or e.codigo ilike '%' || v_busca || '%'
              or e.cliente_nome ilike '%' || v_busca || '%')
         and (p_status is null or e.situacao = p_status)
       order by e.criado_em desc
       limit v_lim
    ) sub;

  return jsonb_build_object('itens', v_itens);
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. admin_brunch_usar(tipo, id) — "brunch entregue", pros dois tipos.
-- -----------------------------------------------------------------------------
create or replace function public.admin_brunch_usar(p_tipo text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_codigo text;
  v_status text;
  v_valido date;
  v_usado  timestamptz;
begin
  if not public.tem_permissao('aniversarios.mexer') then
    raise exception 'sem permissão pra dar baixa em brunch';
  end if;
  if p_tipo not in ('mensal', 'aniversario') then
    return jsonb_build_object('ok', false, 'erro', 'não conheço esse tipo de brunch');
  end if;

  if p_tipo = 'mensal' then
    select codigo, status, valido_ate, usado_em into v_codigo, v_status, v_valido, v_usado
      from public.brunches_mensais where id = p_id for update;
  else
    select codigo, status, valido_ate, usado_em into v_codigo, v_status, v_valido, v_usado
      from public.brindes_aniversario where id = p_id for update;
  end if;

  if v_codigo is null then
    return jsonb_build_object('ok', false, 'erro', 'brunch não encontrado');
  end if;
  if v_status = 'usado' then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'usado_em', v_usado);
  end if;
  if v_valido < v_hoje then
    return jsonb_build_object('ok', false, 'erro',
      'esse código venceu em ' || to_char(v_valido, 'DD/MM'));
  end if;

  if p_tipo = 'mensal' then
    update public.brunches_mensais
       set status = 'usado', usado_em = now(), usado_por = v_uid where id = p_id;
  else
    update public.brindes_aniversario
       set status = 'usado', usado_em = now(), usado_por = v_uid where id = p_id;
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'brunch_usado',
          case when p_tipo = 'mensal' then 'brunches_mensais' else 'brindes_aniversario' end,
          p_id::text, jsonb_build_object('codigo', v_codigo, 'tipo', p_tipo));

  return jsonb_build_object('ok', true, 'usado_em', now());
end;
$$;

-- -----------------------------------------------------------------------------
-- 9. admin_brunch_arrumar(tipo, id, acao) — desfazer a baixa ou esticar a
--    validade, pros dois tipos. Mesmo desenho do `admin_brinde_arrumar` (0047),
--    que segue existindo e só serve o aniversário.
-- -----------------------------------------------------------------------------
create or replace function public.admin_brunch_arrumar(p_tipo text, p_id uuid, p_acao text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_acao   text := btrim(coalesce(p_acao, ''));
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_codigo text;
  v_status text;
  v_valido date;
  v_novo   date;
  v_tabela text;
begin
  if not public.tem_permissao('aniversarios.arrumar') then
    raise exception 'sem permissão pra arrumar brunch';
  end if;
  if p_tipo not in ('mensal', 'aniversario') then
    return jsonb_build_object('ok', false, 'erro', 'não conheço esse tipo de brunch');
  end if;
  if v_acao not in ('desfazer', 'esticar') then
    return jsonb_build_object('ok', false, 'erro', 'não conheço esse conserto');
  end if;

  v_tabela := case when p_tipo = 'mensal' then 'brunches_mensais' else 'brindes_aniversario' end;

  if p_tipo = 'mensal' then
    select codigo, status, valido_ate into v_codigo, v_status, v_valido
      from public.brunches_mensais where id = p_id for update;
  else
    select codigo, status, valido_ate into v_codigo, v_status, v_valido
      from public.brindes_aniversario where id = p_id for update;
  end if;

  if v_codigo is null then
    return jsonb_build_object('ok', false, 'erro', 'brunch não encontrado');
  end if;

  if v_acao = 'desfazer' then
    if v_status <> 'usado' then
      return jsonb_build_object('ok', true, 'ja_estava', true);
    end if;
    if p_tipo = 'mensal' then
      update public.brunches_mensais
         set status = 'ativo', usado_em = null, usado_por = null where id = p_id;
    else
      update public.brindes_aniversario
         set status = 'ativo', usado_em = null, usado_por = null where id = p_id;
    end if;
    insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
    values (v_uid, 'brunch_baixa_desfeita', v_tabela, p_id::text,
            jsonb_build_object('codigo', v_codigo, 'tipo', p_tipo));
    return jsonb_build_object('ok', true, 'situacao', 'ativo');
  end if;

  v_novo := greatest(v_hoje, v_valido) + 30;
  if p_tipo = 'mensal' then
    update public.brunches_mensais set valido_ate = v_novo where id = p_id;
  else
    update public.brindes_aniversario set valido_ate = v_novo where id = p_id;
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'brunch_esticado', v_tabela, p_id::text,
          jsonb_build_object('codigo', v_codigo, 'tipo', p_tipo, 'de', v_valido, 'para', v_novo));

  return jsonb_build_object('ok', true, 'valido_ate', to_char(v_novo, 'DD/MM'));
end;
$$;

-- -----------------------------------------------------------------------------
-- 10. Grants. Nada pra anon: brunch é de quem tem conta.
-- -----------------------------------------------------------------------------
revoke all on function public.aniversario_no_ano(date, integer)                from public, anon;
revoke all on function public.meu_brunch_mensal()                              from public, anon;
revoke all on function public.resgatar_brunch_mensal()                         from public, anon;
revoke all on function public.admin_brunches_listar(text, text, text, integer)  from public, anon;
revoke all on function public.admin_brunch_usar(text, uuid)                    from public, anon;
revoke all on function public.admin_brunch_arrumar(text, uuid, text)           from public, anon;

grant execute on function public.aniversario_no_ano(date, integer)             to authenticated, service_role;
grant execute on function public.meu_brunch_mensal()                           to authenticated;
grant execute on function public.resgatar_brunch_mensal()                      to authenticated;
grant execute on function public.admin_brunches_listar(text, text, text, integer) to authenticated;
grant execute on function public.admin_brunch_usar(text, uuid)                 to authenticated;
grant execute on function public.admin_brunch_arrumar(text, uuid, text)        to authenticated;



-- ===== 0051_nascimento_travado.sql =====

-- =============================================================================
-- 0051_nascimento_travado.sql — o aniversário entra no cadastro e não se troca 🎂
--
-- O PORQUÊ: a 0050 abriu o brunch de aniversário pra **qualquer pessoa com
-- conta**, plano ou não. Isso é bom pro cadastro e ruim pro caixa se a data for
-- editável: bastaria mudar o aniversário pra hoje, pegar o brunch, mudar de novo
-- no mês que vem. O UNIQUE `(user_id, ano)` segura um por ANO, mas não segura
-- quem move a data pra dentro da janela sempre que quer vir.
--
-- O QUE ESTE ARQUIVO FAZ:
--   1. `handle_new_user` passa a gravar `nascimento` do metadata do cadastro.
--   2. Trigger `prevent_nascimento_tamper`: depois de preenchida, a data **não
--      muda mais** por sessão de cliente. De nulo pra uma data ainda passa (as
--      contas que já existem precisam poder preencher uma vez), e o **owner**
--      passa sempre (é a saída pra um dígito trocado; hoje ela é pelo SQL
--      Editor, o console não tem campo pra isso).
--   3. Régua de sanidade na própria trigger: data no futuro ou mais de 120 anos
--      atrás é recusada. Sem isso, "01/01/0001" viraria aniversário legítimo.
--
-- POR QUE TRIGGER E NÃO RLS: a `profiles_update_self` (0002) libera UPDATE da
-- linha INTEIRA e RLS não restringe coluna. Mesmo desenho do
-- `prevent_points_tamper` (0008) e do `prevent_perfil_publico_tamper` (0033).
--
-- A GUC `casa.trusted_perfil` (0033) serve de bypass server-side, então qualquer
-- função SECURITY DEFINER que precise corrigir a data no futuro já tem por onde.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. handle_new_user — agora com o aniversário.
--    O parse é TOLERANTE de propósito: se vier lixo no metadata, a data fica
--    nula e a conta nasce assim mesmo. Derrubar um cadastro por causa de um
--    campo de mimo seria trocar uma pessoa nova por uma data de aniversário.
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nasc date := null;
  v_bruto text := nullif(btrim(coalesce(new.raw_user_meta_data->>'nascimento', '')), '');
begin
  if v_bruto is not null then
    begin
      v_nasc := v_bruto::date;
      -- Mesma régua da trigger: nada no futuro, nada de 300 anos atrás.
      if v_nasc > current_date or v_nasc < current_date - interval '120 years' then
        v_nasc := null;
      end if;
    exception when others then
      v_nasc := null;
    end;
  end if;

  insert into public.profiles (id, full_name, telefone, nascimento, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'telefone',
    v_nasc,
    'cliente'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. prevent_nascimento_tamper — a data é de escrever uma vez.
-- -----------------------------------------------------------------------------
create or replace function public.prevent_nascimento_tamper()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Caminho server-side confiável (mesma GUC do cantinho, 0033): libera.
  if coalesce(current_setting('casa.trusted_perfil', true), '') = 'on' then
    return new;
  end if;

  -- Sem sessão de cliente (service_role, triggers, functions): libera.
  if auth.uid() is null then
    return new;
  end if;

  -- O adm do Casa passa: é ele quem conserta um dígito trocado.
  if public.is_owner() then
    return new;
  end if;

  if new.nascimento is distinct from old.nascimento then
    -- Preencher pela primeira vez pode (conta antiga, que nasceu sem a data).
    if old.nascimento is not null then
      raise exception 'o aniversário é escrito uma vez só. se ficou errado, chama a gente 💛';
    end if;
    if new.nascimento is not null then
      if new.nascimento > current_date then
        raise exception 'essa data de aniversário ainda não chegou.';
      end if;
      if new.nascimento < current_date - interval '120 years' then
        raise exception 'essa data de aniversário não parece de gente que toma café.';
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prevent_nascimento_tamper on public.profiles;
create trigger trg_prevent_nascimento_tamper
  before update on public.profiles
  for each row execute function public.prevent_nascimento_tamper();



-- ===== 0052_aviso_lead_evento.sql =====

-- =============================================================================
-- 0052_aviso_lead_evento.sql — o pedido de evento toca o sino da casa 🔔
--
-- A 0040 resolveu o "o lead sobrevive ao canal": o pedido fica guardado mesmo
-- que a conversa do WhatsApp se perca. Ficou faltando o outro lado da mesma
-- moeda — ALGUÉM PRECISA SABER QUE ELE CHEGOU. Hoje o pedido cai na tabela e
-- espera alguém abrir o console e lembrar de olhar a aba "eventos". Quem pede
-- um evento está decidindo com outras casas ao mesmo tempo, e responder no dia
-- seguinte é responder depois de a pessoa já ter fechado com outro lugar.
--
-- Esta migration liga o INSERT da `leads_evento` a um aviso no Telegram da
-- equipe, passando pela Edge Function `avisar-lead-evento` (que também pede uma
-- leitura rápida do pedido pra uma API barata de IA antes de mandar).
--
-- POR QUE O GATILHO É O INSERT, E NÃO O FRONT:
--   • Chamar do navegador exigiria a chave do Telegram/Gemini no bundle, o que
--     as regras da casa proíbem (CLAUDE.md › Segurança).
--   • E o aviso morreria junto com a aba: quem preenche e fecha na hora é
--     exatamente o lead que a gente não pode perder.
--   O INSERT é o único momento em que um pedido virou pedido de verdade. Ele já
--   passou por toda a validação e pelo anti-flood de 30s da própria RPC, então
--   o freio do formulário é o freio do Telegram de graça: pedido repetido sem
--   querer não vira linha nova, e por isso também não vira ping repetido no
--   celular de quem atende.
--
-- O AVISO NUNCA PODE DERRUBAR O PEDIDO:
--   A /eventos tem uma regra que vale mais que o aviso: "o banco nunca barra a
--   pessoa" (o front já segue pro WhatsApp mesmo se a gravação falhar). Aqui é a
--   mesma coisa, um degrau abaixo: a trigger inteira roda dentro de um
--   `exception when others`, então extensão faltando, segredo não cadastrado ou
--   Telegram fora do ar viram um `warning` no log e nada mais. O lead entra do
--   mesmo jeito. Perder um aviso é ruim; perder o lead é pior.
--
-- ONDE MORAM OS SEGREDOS:
--   No **Vault** do Supabase, não neste arquivo e não numa tabela de config em
--   texto puro. A migration sobe sem saber a URL nem o token; enquanto os dois
--   não forem cadastrados, a trigger simplesmente não faz nada (nem erro). Os
--   dois comandos estão no rodapé deste arquivo e no README das functions.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP TRIGGER IF EXISTS).
-- =============================================================================

-- pg_net: o cliente HTTP assíncrono do Postgres. Ele ENFILEIRA a requisição e
-- devolve na hora, então a trigger não segura a transação esperando o Telegram
-- responder. E como a fila é uma tabela, um rollback do INSERT leva o aviso
-- junto: ninguém é avisado de um pedido que não existe.
create extension if not exists pg_net;

-- -----------------------------------------------------------------------------
-- Rastro: quando o aviso efetivamente saiu.
-- Existe pra responder "o sino tocou?" sem cavar o log da Edge Function. Fica
-- nulo enquanto o aviso não confirma, e é a própria function que carimba (com
-- service_role) depois que o Telegram aceita a mensagem.
-- -----------------------------------------------------------------------------
alter table public.leads_evento
  add column if not exists aviso_em timestamptz;

comment on column public.leads_evento.aviso_em is
  'Quando o aviso do Telegram saiu (carimbado pela Edge Function avisar-lead-evento). Nulo = não avisado.';

-- -----------------------------------------------------------------------------
-- aviso_lead_config() → (url, token) do Vault, ou nada.
--
-- Lê os dois segredos pelo nome. Se o Vault não existir, se os nomes não
-- estiverem cadastrados ou se qualquer coisa der errado na leitura, devolve
-- ZERO linhas em vez de estourar — é o que faz aplicar esta migration antes de
-- cadastrar os segredos ser seguro.
--
-- SECURITY DEFINER porque `vault.decrypted_secrets` não é legível por quem
-- chama a RPC (anon). E fora do alcance do client: sem grant pra anon nem pra
-- authenticated, ela só é chamável de dentro da trigger.
-- -----------------------------------------------------------------------------
create or replace function public.aviso_lead_config()
returns table (url text, token text)
language plpgsql
security definer
set search_path = public, vault, extensions
as $$
begin
  return query
    select
      max(case when s.name = 'casa_aviso_lead_url'   then s.decrypted_secret end)::text,
      max(case when s.name = 'casa_aviso_lead_token' then s.decrypted_secret end)::text
      from vault.decrypted_secrets s
     where s.name in ('casa_aviso_lead_url', 'casa_aviso_lead_token')
    having max(case when s.name = 'casa_aviso_lead_url'   then s.decrypted_secret end) is not null
       and max(case when s.name = 'casa_aviso_lead_token' then s.decrypted_secret end) is not null;
exception
  when others then
    -- Vault ausente/inacessível: sem aviso, sem barulho. Quem depende disto é a
    -- trigger, que já trata "não veio nada" como "não configurado ainda".
    return;
end;
$$;

revoke all on function public.aviso_lead_config() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- trg_avisar_lead_evento() — a trigger.
--
-- Monta o pedido inteiro em jsonb e joga na fila do pg_net. Manda o registro
-- COMPLETO de propósito: assim a Edge Function não precisa voltar ao banco pra
-- ler o que acabou de ser escrito, e o aviso continua saindo mesmo que a leitura
-- de volta fosse falhar.
--
-- O `exception when others` de fora é a peça mais importante do arquivo: a
-- partir daqui, qualquer coisa que der errado no caminho do aviso é um warning
-- no log do Postgres, nunca um erro na cara de quem está preenchendo o
-- formulário.
-- -----------------------------------------------------------------------------
create or replace function public.trg_avisar_lead_evento()
returns trigger
language plpgsql
security definer
set search_path = public, net, extensions
as $$
declare
  v_cfg   record;
  v_corpo jsonb;
begin
  select * into v_cfg from public.aviso_lead_config();

  -- Segredos ainda não cadastrados: o site funciona igual, só não avisa.
  if v_cfg.url is null or v_cfg.token is null then
    return new;
  end if;

  -- Teto de avisos por hora. A `registrar_lead_evento` é aberta a anon (quem
  -- pede evento raramente tem conta) e o anti-flood dela é POR CONTATO, então
  -- quem variar o telefone consegue gerar pedido à vontade. Isso já era verdade
  -- antes deste arquivo, só que ali o estrago parava na tabela; com o sino
  -- ligado, viraria o celular de quem atende tocando a noite inteira.
  -- Acima do teto o pedido ENTRA normalmente e aparece no console como sempre,
  -- só não vira ping. Vinte por hora é muito acima de um dia cheio de verdade.
  if (select count(*) from public.leads_evento
       where created_at > now() - interval '1 hour') > 20 then
    raise warning 'aviso de lead de evento segurado: mais de 20 pedidos na última hora (lead %)', new.id;
    return new;
  end if;

  v_corpo := jsonb_build_object(
    'lead', jsonb_build_object(
      'id',              new.id,
      'nome',            new.nome,
      'contato',         new.contato,
      'email',           new.email,
      'tipo',            new.tipo,
      'data_pretendida', new.data_pretendida,
      'pessoas',         new.pessoas,
      'mensagem',        new.mensagem,
      'origem',          new.origem,
      'created_at',      new.created_at
    )
  );

  perform net.http_post(
    url     := v_cfg.url,
    body    := v_corpo,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      -- Mesmo desenho do asaas-webhook: token compartilhado no header, que a
      -- function compara com o secret dela. Não é HMAC, e não precisa ser — os
      -- dois lados são nossos e o canal é HTTPS.
      'x-casa-token',  v_cfg.token
    ),
    -- Folgado de propósito: do outro lado a function fala com o Gemini e com o
    -- Telegram antes de responder (8s de teto cada). Com os 5s padrão, o pg_net
    -- registraria timeout num aviso que na verdade saiu, e a gente ficaria
    -- caçando um problema que não existe.
    timeout_milliseconds := 20000
  );

  return new;
exception
  when others then
    raise warning 'aviso de lead de evento não saiu (lead %): %', new.id, sqlerrm;
    return new;
end;
$$;

revoke all on function public.trg_avisar_lead_evento() from public, anon, authenticated;

drop trigger if exists avisar_lead_evento on public.leads_evento;
create trigger avisar_lead_evento
  after insert on public.leads_evento
  for each row
  execute function public.trg_avisar_lead_evento();

-- =============================================================================
-- DEPOIS DE APLICAR — os dois segredos do Vault (rodar UMA vez, com os valores
-- de verdade; NÃO versionar isto preenchido).
--
--   select vault.create_secret(
--     'https://<REF-DO-PROJETO>.supabase.co/functions/v1/avisar-lead-evento',
--     'casa_aviso_lead_url'
--   );
--   select vault.create_secret('<TOKEN-QUE-TU-ESCOLHER>', 'casa_aviso_lead_token');
--
-- Pra TROCAR um valor já cadastrado (o create_secret recusa nome repetido):
--   select vault.update_secret(
--     (select id from vault.secrets where name = 'casa_aviso_lead_token'),
--     '<TOKEN-NOVO>'
--   );
--
-- O mesmo token vai pro secret `LEAD_WEBHOOK_TOKEN` da Edge Function
-- (`npx supabase secrets set`). Passo a passo em supabase/functions/README.md.
--
-- CONFERIR que a ponte está de pé (deve devolver uma linha, com o token oculto):
--   select url, left(token, 4) || '…' as token from public.aviso_lead_config();
-- =============================================================================



-- ===== 0053_rastros.sql =====

-- =============================================================================
-- 0053_rastros.sql — por onde a pessoa andou, e onde ela largou 👣
--
-- O console sabia tudo sobre o que a casa VENDEU e nada sobre o que a pessoa
-- FEZ antes de comprar (ou de desistir). Dava pra ver o pedido pago e o mimo
-- resgatado; não dava pra responder as três perguntas que a casa faz quando
-- olha o site: em que tela a pessoa estava quando fechou a aba, que seção
-- ninguém toca, e quanta gente encheu o carrinho e foi embora.
--
-- O QUE ISTO GUARDA, E O QUE NÃO GUARDA:
--   Guarda a VISITA (uma aba aberta: por onde entrou, por onde saiu, quantos
--   cliques, se tinha carrinho) e os EVENTOS dela (clique e "vista" de seção).
--   NÃO guarda IP, não guarda user agent, não guarda o texto que a pessoa
--   digitou e não guarda o que ela leu — só o rótulo do que ela TOCOU e o nome
--   da seção que passou pelos olhos dela. O `user_id` entra só quando a pessoa
--   já está logada, e vem de `auth.uid()`, nunca do corpo da chamada: senão
--   qualquer um carimbaria a visita dele com o id de outra pessoa.
--
--   A "vista" de seção é a metade que faz a pergunta da casa ter resposta.
--   Seção fria com contagem de clique só aparece como AUSÊNCIA (zero cliques =
--   zero linhas = some do relatório), e o que a casa quer saber é justamente a
--   seção que TODO MUNDO VÊ e NINGUÉM TOCA. Sem a vista, "fria" e "ninguém
--   chegou até lá" são a mesma linha em branco, e são problemas opostos.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • As duas tabelas são DENY-BY-DEFAULT: RLS ligada e NENHUMA policy. O
--     client não lê nem escreve direto. Quem escreve é a `registrar_rastro`
--     (SECURITY DEFINER, aberta a anon — a maior parte de quem visita o site
--     não tem conta, e é justamente essa gente que a casa quer enxergar); quem
--     lê é o console, pelas duas `admin_rastros_*`.
--   • Endpoint público de escrita tem três freios, porque quem escreve aqui é
--     literalmente qualquer pessoa com a anon key (que está no bundle, como tem
--     que estar): no máximo 40 eventos por chamada, 400 por visita, e 400
--     visitas novas por hora. Passou do teto, a resposta continua `ok:true` e
--     nada é gravado — quem está navegando não tem nada com isso.
--   • Todo texto é aparado e truncado no BANCO, não no navegador: `pagina` só
--     entra se começar com "/" (senão vira 'outra'), e seção/alvo param em 80
--     caracteres. O console escapa tudo o que mostra, como sempre.
--
-- POR QUE A LIMPEZA É SORTEADA, E NÃO UM CRON:
--   Rastro é dado que cresce sozinho e envelhece rápido: ninguém vai perguntar
--   em março o que estava frio em setembro. Um `delete` a cada escrita seria
--   desperdício; um cron seria peça nova de infra pra uma linha de SQL. Então a
--   própria função sorteia: uma em cada cinquenta chamadas varre o que passou
--   de 180 dias (um semestre, que segura a sazonalidade do café). O `on delete
--   cascade` leva os eventos junto.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE).
-- =============================================================================

-- =============================================================================
-- 1. As tabelas
-- =============================================================================

-- A visita é uma ABA ABERTA, não uma pessoa: o id nasce no `sessionStorage` do
-- navegador e morre quando a aba fecha. Foi escolha, e é a escolha mais
-- privada das disponíveis: ninguém é seguido de um dia pro outro, e o mesmo
-- celular voltando amanhã conta como visita nova. Pro que a casa quer saber
-- ("onde essa navegação terminou"), a aba é a unidade certa.
create table if not exists public.rastro_visitas (
  id                 uuid primary key,
  criada_em          timestamptz not null default now(),
  vista_em           timestamptz not null default now(),
  user_id            uuid references auth.users (id) on delete set null,
  dispositivo        text check (dispositivo is null or dispositivo in ('celular', 'computador')),
  -- o HOST de onde a pessoa veio (google.com, instagram.com) ou 'direto'.
  -- Nunca a URL inteira: query string de rede social carrega id de anúncio e
  -- às vezes id de pessoa, e isso não é da conta da casa.
  origem             text check (origem is null or char_length(origem) <= 80),
  pagina_entrada     text not null,
  -- Onde a visita TERMINOU. É a pergunta que abriu esta migration: a última
  -- página, a última seção e o rótulo do último clique antes de fechar.
  pagina_saida       text,
  secao_saida        text,
  alvo_saida         text,
  cliques            integer not null default 0,
  paginas            integer not null default 1,
  -- Fotografia do carrinho no último pulso. É o que separa "passou pela loja"
  -- de "escolheu e desistiu", que são a mesma visita até aqui.
  carrinho_itens     integer not null default 0,
  carrinho_centavos  integer not null default 0,
  checkout_iniciado  boolean not null default false,
  comprou            boolean not null default false
);

create index if not exists idx_rastro_visitas_criada on public.rastro_visitas (criada_em desc);
create index if not exists idx_rastro_visitas_saida  on public.rastro_visitas (pagina_saida, secao_saida);

create table if not exists public.rastro_eventos (
  id         bigserial primary key,
  visita_id  uuid not null references public.rastro_visitas (id) on delete cascade,
  criado_em  timestamptz not null default now(),
  -- 'clique' = a pessoa TOCOU. 'vista' = a seção passou pelos olhos dela (meia
  -- seção na tela por um segundo). Uma por seção por carregamento de página.
  tipo       text not null check (tipo in ('clique', 'vista')),
  pagina     text not null,
  secao      text not null,
  alvo       text
);

create index if not exists idx_rastro_eventos_visita on public.rastro_eventos (visita_id);
create index if not exists idx_rastro_eventos_periodo on public.rastro_eventos (criado_em desc);
create index if not exists idx_rastro_eventos_secao on public.rastro_eventos (pagina, secao, tipo);

alter table public.rastro_visitas enable row level security;
alter table public.rastro_eventos enable row level security;

-- Nenhuma policy, de propósito: RLS ligada sem policy = ninguém passa pelo
-- PostgREST, nem anon nem logado. As portas são as três funções abaixo.


-- =============================================================================
-- 2. O catálogo de permissão (0047) ganha a página "os rastros"
-- -----------------------------------------------------------------------------
-- Permissão nova daqui pra frente é INSERT numa tabela de catálogo, não `alter
-- constraint` — é exatamente o que a 0047 comprou. A página entra na seção "o
-- dia a dia", ao lado do painel: é número do site inteiro, e é o tipo de coisa
-- que se olha no começo da semana.
--
-- Só existe o `ver`. Não há o que MEXER num rastro (ele é o que aconteceu) nem
-- o que ARRUMAR (a limpeza é por idade, sozinha). Inventar os três níveis aqui
-- seria enfeite, e o CLAUDE.md já diz o que a casa acha de permissão que não
-- abre porta nenhuma.
-- =============================================================================

insert into public.permissao_paginas (slug, secao_slug, rotulo, descricao, aba, ordem) values
  ('rastros', 'dia', 'os rastros', 'por onde a pessoa andou e onde ela largou o site', 'rastros', 30)
on conflict (slug) do update
  set secao_slug = excluded.secao_slug, rotulo = excluded.rotulo,
      descricao  = excluded.descricao,  aba    = excluded.aba, ordem = excluded.ordem;

insert into public.permissoes (slug, pagina_slug, acao, nivel, rotulo, descricao) values
  ('rastros.ver', 'rastros', 'ver', 1, 'enxergar', 'ler por onde a visita andou, onde ela terminou e que seção está fria')
on conflict (slug) do update
  set pagina_slug = excluded.pagina_slug, acao = excluded.acao, nivel = excluded.nivel,
      rotulo = excluded.rotulo, descricao = excluded.descricao;

-- Quem já enxerga os relatórios da loja passa a enxergar os rastros também: é a
-- mesma pergunta ("o que está funcionando?"), vista antes da venda em vez de
-- depois. Ninguém precisa ser reautorizado na mão por causa desta migration.
insert into public.staff_permissions (user_id, permissao)
  select sp.user_id, 'rastros.ver'
    from public.staff_permissions sp
   where sp.permissao = 'relatorios.ver'
on conflict do nothing;


-- =============================================================================
-- 3. Dois aparadores de texto
-- -----------------------------------------------------------------------------
-- Existem pra que a validação fique num lugar só: a mesma regra vale pro pulso
-- que vem do navegador da casa e pro que vem de um curl com a anon key.
-- =============================================================================

create or replace function public.rastro_texto(p_valor text, p_max integer)
returns text
language sql
immutable
as $$
  select nullif(left(btrim(coalesce(p_valor, '')), greatest(p_max, 1)), '');
$$;

-- Caminho de página. Só aceita o que parece caminho interno; qualquer outra
-- coisa (URL inteira, javascript:, lixo) vira 'outra' em vez de entrar.
create or replace function public.rastro_caminho(p_valor text)
returns text
language sql
immutable
as $$
  select coalesce(
    (select left(v, 120)
       from (select btrim(coalesce(p_valor, '')) as v) t
      where v like '/%' and v not like '//%'),
    'outra'
  );
$$;


-- =============================================================================
-- 4. registrar_rastro(jsonb) — a única porta de escrita
-- -----------------------------------------------------------------------------
-- Um parâmetro jsonb só, de propósito: o navegador manda isto no `pagehide`,
-- às vezes por `sendBeacon`, e um corpo único é o que sobrevive a esse caminho.
--
-- A resposta é sempre a mesma (`ok:true`), grave ou não. Quem está navegando
-- não tem nada a fazer com a resposta, e um erro visível ali seria o site
-- reclamando na cara de quem visita por causa de uma estatística da casa.
-- =============================================================================
create or replace function public.registrar_rastro(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_visita     uuid;
  v_pagina     text;
  v_eventos    jsonb := '[]'::jsonb;
  v_ja         integer := 0;
  v_limite     integer := 0;
  v_cliques    integer := 0;
  v_nova_pag   integer := 0;
  v_saida      jsonb;
  v_carrinho   jsonb;
begin
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then
    return jsonb_build_object('ok', true);
  end if;

  -- Id malformado não é erro pra quem navega: é pulso perdido, e ponto.
  begin
    v_visita := (p_dados->>'visita')::uuid;
  exception when others then
    return jsonb_build_object('ok', true);
  end;
  if v_visita is null then
    return jsonb_build_object('ok', true);
  end if;

  v_pagina := public.rastro_caminho(p_dados->>'pagina');

  if jsonb_typeof(p_dados->'eventos') = 'array' then
    v_eventos := p_dados->'eventos';
  end if;

  -- Teto por visita (400) e por chamada (40). Passou, o excedente é descartado
  -- em silêncio: a visita já disse o que tinha pra dizer.
  select count(*) into v_ja from public.rastro_eventos where visita_id = v_visita;
  v_limite := greatest(0, least(40, 400 - v_ja));

  select count(*) filter (where coalesce(e->>'tipo', 'clique') <> 'vista')
    into v_cliques
    from (
      select e from jsonb_array_elements(v_eventos) with ordinality as t(e, i)
       where t.i <= v_limite
    ) s;
  v_cliques := coalesce(v_cliques, 0);

  -- Teto global de visitas novas por hora. O anti-flood da 0040 é por contato;
  -- aqui não há contato nenhum, então o freio é a torneira inteira. Visita que
  -- JÁ existe segue escrevendo: quem está navegando de verdade não é cortado no
  -- meio por causa de uma enxurrada de fora.
  if not exists (select 1 from public.rastro_visitas where id = v_visita)
     and (select count(*) from public.rastro_visitas
           where criada_em > now() - interval '1 hour') >= 400 then
    return jsonb_build_object('ok', true);
  end if;

  if coalesce((p_dados->>'pagina_nova')::boolean, false) then
    v_nova_pag := 1;
  end if;

  v_saida    := case when jsonb_typeof(p_dados->'saida') = 'object' then p_dados->'saida' end;
  v_carrinho := case when jsonb_typeof(p_dados->'carrinho') = 'object' then p_dados->'carrinho' end;

  insert into public.rastro_visitas as v (
    id, user_id, dispositivo, origem, pagina_entrada,
    pagina_saida, secao_saida, alvo_saida,
    cliques, paginas, carrinho_itens, carrinho_centavos,
    checkout_iniciado, comprou, vista_em
  )
  values (
    v_visita,
    -- SEMPRE de auth.uid(): o corpo da chamada não diz quem é ninguém.
    auth.uid(),
    case when p_dados->>'dispositivo' in ('celular', 'computador') then p_dados->>'dispositivo' end,
    public.rastro_texto(p_dados->>'origem', 80),
    v_pagina,
    case when v_saida is not null then public.rastro_caminho(v_saida->>'pagina') end,
    case when v_saida is not null then public.rastro_texto(v_saida->>'secao', 80) end,
    case when v_saida is not null then public.rastro_texto(v_saida->>'alvo', 80) end,
    v_cliques,
    1,
    greatest(0, least(coalesce((v_carrinho->>'itens')::integer, 0), 999)),
    greatest(0, least(coalesce((v_carrinho->>'centavos')::integer, 0), 100000000)),
    coalesce((p_dados->>'checkout')::boolean, false),
    coalesce((p_dados->>'comprou')::boolean, false),
    now()
  )
  on conflict (id) do update set
    vista_em          = now(),
    -- A pessoa pode ter entrado logada no meio da visita. Uma vez carimbado,
    -- não se troca: a visita é de quem a começou como dono.
    user_id           = coalesce(v.user_id, excluded.user_id),
    -- Saída nova ganha da antiga (é o ÚLTIMO clique que interessa); pulso sem
    -- saída não apaga a que já estava lá.
    pagina_saida      = coalesce(excluded.pagina_saida, v.pagina_saida),
    secao_saida       = coalesce(excluded.secao_saida,  v.secao_saida),
    alvo_saida        = coalesce(excluded.alvo_saida,   v.alvo_saida),
    cliques           = v.cliques + excluded.cliques,
    paginas           = v.paginas + v_nova_pag,
    carrinho_itens    = case when v_carrinho is not null then excluded.carrinho_itens    else v.carrinho_itens    end,
    carrinho_centavos = case when v_carrinho is not null then excluded.carrinho_centavos else v.carrinho_centavos end,
    -- Marco não desliga: quem chegou no checkout chegou, mesmo que volte pra
    -- vitrine depois.
    checkout_iniciado = v.checkout_iniciado or excluded.checkout_iniciado,
    comprou           = v.comprou or excluded.comprou;

  if v_limite > 0 then
    insert into public.rastro_eventos (visita_id, tipo, pagina, secao, alvo)
      select
        v_visita,
        case when t.e->>'tipo' = 'vista' then 'vista' else 'clique' end,
        coalesce(nullif(public.rastro_caminho(t.e->>'pagina'), 'outra'), v_pagina),
        coalesce(public.rastro_texto(t.e->>'secao', 80), 'sem seção'),
        public.rastro_texto(t.e->>'alvo', 80)
        from jsonb_array_elements(v_eventos) with ordinality as t(e, i)
       where t.i <= v_limite
         and jsonb_typeof(t.e) = 'object';
  end if;

  -- A faxina sorteada (ver o cabeçalho). Uma em cada cinquenta chamadas.
  if random() < 0.02 then
    delete from public.rastro_visitas where criada_em < now() - interval '180 days';
  end if;

  return jsonb_build_object('ok', true);
end;
$$;


-- =============================================================================
-- 5. admin_rastros_resumo(dias) — a tela inteira numa viagem só
-- -----------------------------------------------------------------------------
-- `returns jsonb`, e não `returns table`, pelo mesmo motivo da 0045: uma
-- leitura composta (números + saídas + seções + funil) teria duas dúzias de
-- colunas declaradas pra errar, e foi um erro desses (varchar declarado como
-- text) que deixou cinco abas do console quebradas da 0017 até a 0042.
-- =============================================================================
create or replace function public.admin_rastros_resumo(p_dias integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_desde timestamptz;
  v_dias  integer := least(greatest(coalesce(p_dias, 30), 1), 365);
begin
  if not public.tem_permissao('rastros.ver') then
    raise exception 'sem permissão pra ver os rastros';
  end if;

  v_desde := now() - (v_dias || ' days')::interval;

  return jsonb_build_object(
    'dias', v_dias,

    'numeros', (
      select jsonb_build_object(
               'visitas',        count(*),
               'cliques',        coalesce(sum(v.cliques), 0),
               'sem_clique',     count(*) filter (where v.cliques = 0),
               'uma_pagina',     count(*) filter (where v.paginas <= 1),
               'no_celular',     count(*) filter (where v.dispositivo = 'celular'),
               'logadas',        count(*) filter (where v.user_id is not null),
               'com_carrinho',   count(*) filter (where v.carrinho_itens > 0),
               'compraram',      count(*) filter (where v.comprou)
             )
        from public.rastro_visitas v
       where v.criada_em >= v_desde),

    -- A resposta da pergunta que abriu a migration: onde a visita terminou.
    -- Sem `alvo_saida` = a pessoa saiu sem tocar em nada naquela página, e essa
    -- linha vale tanto quanto as outras (às vezes mais).
    'saidas', coalesce((
      -- O `order by` aparece DUAS vezes de propósito, aqui e nos dois blocos
      -- abaixo: o de dentro é quem escolhe QUAIS linhas o `limit` guarda, e o
      -- do `jsonb_agg` é quem garante a ORDEM dentro do array. Sem o segundo, a
      -- lista chega no console em ordem de varredura.
      select jsonb_agg(t order by t.visitas desc)
        from (
          select v.pagina_saida                            as pagina,
                 coalesce(v.secao_saida, 'sem seção')      as secao,
                 v.alvo_saida                              as alvo,
                 count(*)                                  as visitas,
                 count(*) filter (where v.carrinho_itens > 0) as com_carrinho
            from public.rastro_visitas v
           where v.criada_em >= v_desde
             and v.pagina_saida is not null
           group by 1, 2, 3
           order by count(*) desc
           limit 30
        ) t), '[]'::jsonb),

    -- O mapa de calor, e o coração do pedido: quantos OLHOS a seção recebeu
    -- contra quantos DEDOS. Ordenado da mais fria pra mais quente, porque é a
    -- fria que se veio ver. `fria` marca o que tem plateia (20 vistas ou mais)
    -- e quase nenhum toque (menos de 5%).
    'secoes', coalesce((
      select jsonb_agg(t order by t.fria desc, t.taxa asc nulls last, t.vistas desc)
        from (
          select e.pagina,
                 e.secao,
                 count(*) filter (where e.tipo = 'vista')  as vistas,
                 count(*) filter (where e.tipo = 'clique') as cliques,
                 case when count(*) filter (where e.tipo = 'vista') > 0
                      then round(
                             count(*) filter (where e.tipo = 'clique')::numeric
                             / count(*) filter (where e.tipo = 'vista'), 4)
                 end                                        as taxa,
                 (count(*) filter (where e.tipo = 'vista') >= 20
                  and count(*) filter (where e.tipo = 'clique')::numeric
                      < 0.05 * count(*) filter (where e.tipo = 'vista')) as fria
            from public.rastro_eventos e
           where e.criado_em >= v_desde
           group by 1, 2
          having count(*) filter (where e.tipo = 'vista') > 0
              or count(*) filter (where e.tipo = 'clique') > 0
           -- A ordem É o relatório: as marcadas como frias na frente, depois
           -- as de menor taxa. Seção com ZERO vista (taxa nula) vai pro FIM, e
           -- não pro começo: ela não é fria, ela é sem informação, e deixá-la
           -- liderar empurrava pra baixo justamente a seção com plateia e sem
           -- toque, que é a que a casa veio ver.
           order by 6 desc, 5 asc nulls last, 3 desc
           limit 60
        ) t), '[]'::jsonb),

    'paginas', coalesce((
      select jsonb_agg(t order by t.visitas desc)
        from (
          select e.pagina,
                 count(distinct e.visita_id)               as visitas,
                 count(*) filter (where e.tipo = 'clique') as cliques,
                 (select count(*) from public.rastro_visitas v2
                   where v2.criada_em >= v_desde and v2.pagina_saida = e.pagina) as saidas
            from public.rastro_eventos e
           where e.criado_em >= v_desde
           group by 1
           order by 2 desc
           limit 30
        ) t), '[]'::jsonb),

    -- O funil da loja. Cada degrau é um subconjunto do anterior, então a queda
    -- entre dois números É o lugar onde a compra morre.
    'loja', (
      select jsonb_build_object(
               'viram_loja', count(*) filter (
                 where exists (select 1 from public.rastro_eventos e
                                where e.visita_id = v.id and e.pagina like '/loja%')),
               'viram_produto', count(*) filter (
                 where exists (select 1 from public.rastro_eventos e
                                where e.visita_id = v.id and e.pagina like '/produto%')),
               'com_carrinho',      count(*) filter (where v.carrinho_itens > 0),
               'foram_ao_checkout', count(*) filter (where v.checkout_iniciado),
               'compraram',         count(*) filter (where v.comprou),
               'carrinho_frio_centavos', coalesce(
                 sum(v.carrinho_centavos) filter (where v.carrinho_itens > 0 and not v.comprou), 0)
             )
        from public.rastro_visitas v
       where v.criada_em >= v_desde)
  );
end;
$$;


-- =============================================================================
-- 6. admin_rastros_leads(dias, limite) — o carrinho frio COM nome e telefone
-- -----------------------------------------------------------------------------
-- Esta é a metade acionável do relatório: quem chegou a abrir o checkout e não
-- pagou. Sai de `orders` pendente/cancelada, que já existe desde a 0007 — a
-- `create-checkout-session` pré-cria o pedido antes de mandar a pessoa pro
-- Asaas, então o carrinho abandonado já estava guardado, só não tinha tela.
--
-- POR QUE A TRAVA AQUI É `pedidos.ver`, E NÃO `rastros.ver`:
--   Rastro é anônimo; isto tem nome, e-mail e telefone de quem comprou quase.
--   Deixar as duas coisas atrás da mesma chave faria "ver que seção está fria"
--   virar, de graça, "ler a agenda de contatos da loja". É a mesma regra que a
--   0044 seguiu com o mural: permissão de olhar uma coisa não é permissão de
--   olhar outra que por acaso mora ao lado.
-- =============================================================================
create or replace function public.admin_rastros_leads(
  p_dias   integer default 30,
  p_limite integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_dias timestamptz := now() - (least(greatest(coalesce(p_dias, 30), 1), 365) || ' days')::interval;
begin
  if not public.tem_permissao('pedidos.ver') then
    raise exception 'sem permissão pra ver os pedidos parados';
  end if;

  return coalesce((
    select jsonb_agg(t order by t.criado_em desc)
      from (
        select o.id,
               o.created_at                                    as criado_em,
               o.status,
               coalesce(o.entrega_nome, pr.full_name, '')       as nome,
               coalesce(u.email::text, '')                      as email,
               coalesce(o.entrega_telefone, pr.telefone, '')    as telefone,
               o.total_centavos,
               coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'nome', oi.nome_snapshot,
                          'variante', oi.variante_snapshot,
                          'qtd', oi.qtd)
                          order by oi.nome_snapshot)
                   from public.order_items oi where oi.order_id = o.id
               ), '[]'::jsonb)                                  as itens,
               -- Voltou depois? Se a pessoa comprou de novo em seguida, o
               -- pedido parado não é lead frio, é tentativa que deu errado e a
               -- casa não precisa ligar pra ela.
               exists (
                 select 1 from public.orders o2
                  where o2.user_id = o.user_id
                    and o2.status in ('pago', 'preparando', 'pronto', 'entregue')
                    and o2.created_at > o.created_at
               )                                                as voltou
          from public.orders o
          left join public.profiles pr on pr.id = o.user_id
          left join auth.users     u  on u.id  = o.user_id
         where o.origem = 'site'
           and o.status in ('pendente', 'cancelado')
           and o.created_at >= v_dias
         order by o.created_at desc
         limit greatest(1, least(coalesce(p_limite, 50), 200))
      ) t), '[]'::jsonb);
end;
$$;


-- =============================================================================
-- 7. Grants — quem alcança o quê
-- =============================================================================
revoke all on function public.rastro_texto(text, integer)   from public, anon, authenticated;
revoke all on function public.rastro_caminho(text)          from public, anon, authenticated;

revoke all on function public.registrar_rastro(jsonb)       from public;
-- Aberta a anon de propósito: a maior parte de quem visita o site não tem
-- conta, e é essa gente que a casa não enxergava.
grant execute on function public.registrar_rastro(jsonb)    to anon, authenticated;

revoke all on function public.admin_rastros_resumo(integer)          from public, anon;
grant execute on function public.admin_rastros_resumo(integer)       to authenticated;

revoke all on function public.admin_rastros_leads(integer, integer)  from public, anon;
grant execute on function public.admin_rastros_leads(integer, integer) to authenticated;



-- ===== 0054_fotos_do_site.sql =====

-- =============================================================================
-- 0054_fotos_do_site — a casa troca as fotos do site sem mexer no código
--
-- Até aqui toda foto do site era um `<img src="/fotos/…">` escrito no HTML, e
-- trocar qualquer uma delas era tarefa de programador: subir arquivo no repo,
-- mudar o caminho, buildar, deployar. Um café troca de foto quando a estação
-- muda, quando a fachada ganha toldo novo, quando o prato sai bonito — isso não
-- pode passar por deploy.
--
-- O DESENHO, em três peças:
--   • uma GALERIA (`fotos_galeria`) das fotos que a casa já subiu, que é o
--     acervo: subiu uma vez, usa em quantos lugares quiser, e ela continua ali
--     pra usar de novo no mês que vem;
--   • um LUGAR (`site_fotos`), uma linha por posição do site que hoje mostra
--     foto ("o 2º slide do hero da home", "o card do Brunch"), apontando pra
--     uma foto da galeria;
--   • a lista DOS LUGARES não mora aqui, e isso é decisão. Ela é um fato sobre
--     o HTML (que `<img>` existe em que página), então mora ao lado dele, no
--     `src/fotos-do-site.js`, que o site e o console importam. Duplicar a lista
--     no banco criaria a mesma divergência que o CLAUDE.md já conta na 0047: a
--     lista que a tela mostra deixando de ser a que vale.
--
-- O QUE SE GUARDA É O CAMINHO, NUNCA A URL. Se a coluna guardasse URL, alguém
-- com a permissão de mexer poderia apontar a foto do hero pra um servidor de
-- fora (um contador de acesso disfarçado de foto, uma imagem que troca depois
-- de aprovada). Guardando só o caminho do objeto no nosso bucket, quem monta o
-- endereço é o `getPublicUrl` do client, com o host vindo do env — não há URL
-- forjável passando por aqui.
--
-- Escrita: as RPCs abaixo, gated por `tem_permissao`. O ARQUIVO em si sobe pelo
-- Storage (não existe RPC que carregue bytes), e ali a tranca é a policy do
-- `storage.objects`, que pergunta pela PERMISSÃO e não pelo papel — é a lição
-- da 0044: `is_staff()` responde falso pra quem recebeu acesso pelo console, e
-- uma aba nova que confie nele nasce quebrada pra todo mundo menos o dono.
-- =============================================================================


-- =============================================================================
-- 1. O bucket
-- -----------------------------------------------------------------------------
-- Público na leitura, como o `avatares` da 0015 e pelo mesmo motivo: foto de
-- site aparece na tela o tempo todo e signed URL expira. 8 MB porque aqui entra
-- foto de hero em tela cheia, que é bem maior que um avatar; o limite mora no
-- BUCKET, não só no JS (confiança zero no client).
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'fotos-site',
  'fotos-site',
  true,
  8388608, -- 8 MB
  array['image/jpeg', 'image/png', 'image/webp', 'image/avif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Leitura pública: são as fotos do site, elas existem pra ser vistas.
drop policy if exists "fotos do site: qualquer um vê" on storage.objects;
create policy "fotos do site: qualquer um vê"
  on storage.objects for select
  using (bucket_id = 'fotos-site');

-- Escrita: quem tem a permissão de MEXER nas fotos. Note que quem pode subir
-- não pode apagar: apagar é do `arrumar`, porque some de todo lugar que usa.
drop policy if exists "fotos do site: quem mexe sobe" on storage.objects;
create policy "fotos do site: quem mexe sobe"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos-site' and public.tem_permissao('fotos.mexer'));

drop policy if exists "fotos do site: quem mexe troca" on storage.objects;
create policy "fotos do site: quem mexe troca"
  on storage.objects for update to authenticated
  using (bucket_id = 'fotos-site' and public.tem_permissao('fotos.mexer'))
  with check (bucket_id = 'fotos-site' and public.tem_permissao('fotos.mexer'));

drop policy if exists "fotos do site: quem arruma apaga" on storage.objects;
create policy "fotos do site: quem arruma apaga"
  on storage.objects for delete to authenticated
  using (bucket_id = 'fotos-site' and public.tem_permissao('fotos.arrumar'));


-- =============================================================================
-- 2. As duas tabelas
-- -----------------------------------------------------------------------------
-- As duas sobem deny-by-default: RLS ligada e NENHUMA policy. Nem anon nem
-- logado alcança pelo PostgREST; as portas são as funções da seção 4.
-- =============================================================================

-- O acervo. Uma linha por arquivo que a casa subiu.
create table if not exists public.fotos_galeria (
  id         uuid primary key default gen_random_uuid(),
  caminho    text not null unique,          -- o objeto no bucket, ex.: 2026/09/fachada-a1b2c3.jpg
  nome       text not null,                 -- como a casa chama essa foto
  alt        text,                           -- a descrição pra quem não enxerga
  bytes      bigint,
  tipo       text,
  enviada_em timestamptz not null default now(),
  enviada_por uuid references auth.users (id) on delete set null
);
create index if not exists idx_fotos_galeria_data on public.fotos_galeria (enviada_em desc);
alter table public.fotos_galeria enable row level security;

-- Os lugares ocupados. Uma linha SÓ pra posição que a casa trocou: lugar que
-- nunca foi mexido não tem linha, e o site mostra o que está no HTML. É o que
-- faz o "voltar ao padrão" ser um DELETE, e não um segundo caminho guardado.
create table if not exists public.site_fotos (
  slot           text primary key,
  caminho        text not null,
  alt            text,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references auth.users (id) on delete set null
);
alter table public.site_fotos enable row level security;


-- =============================================================================
-- 3. O catálogo de permissão (0047) ganha a página "as fotos"
-- -----------------------------------------------------------------------------
-- Permissão nova é INSERT no catálogo, não `alter constraint` — é o que a 0047
-- comprou. A página entra na seção "a casa", ao lado do recado do topo e da
-- trilha: é tudo o que a casa PUBLICA.
--
-- As três ações existem de verdade, e a linha entre elas é o estrago:
--   ver     — enxergar a galeria e saber que foto está em que lugar;
--   mexer   — subir foto nova, trocar a de um lugar e voltar um lugar pro
--             padrão (o do HTML). Nada disso perde arquivo;
--   arrumar — apagar uma foto do acervo, que some do Storage pra sempre.
--
-- SEM BACKFILL, de propósito. Estas são as fotos da fachada da casa na
-- internet: quem trocar uma delas troca a cara do site pra todo mundo na hora.
-- É poder novo, e poder novo se dá na mão (a mesma régua que a 0047 usou pro
-- `arrumar` de pedido, ponto, presente e assinatura). O dono já alcança tudo
-- pelo `role = 'owner'`, então ninguém fica sem porta enquanto isso.
-- =============================================================================

insert into public.permissao_paginas (slug, secao_slug, rotulo, descricao, aba, ordem) values
  ('fotos', 'casa', 'as fotos', 'as fotos que o site mostra, e o acervo delas', 'fotos', 50)
on conflict (slug) do update
  set secao_slug = excluded.secao_slug, rotulo = excluded.rotulo,
      descricao  = excluded.descricao,  aba    = excluded.aba, ordem = excluded.ordem;

insert into public.permissoes (slug, pagina_slug, acao, nivel, rotulo, descricao) values
  ('fotos.ver',     'fotos', 'ver',     1, 'enxergar', 'ver o acervo de fotos e que foto está em cada lugar do site'),
  ('fotos.mexer',   'fotos', 'mexer',   2, 'mexer',    'subir foto nova, trocar a foto de um lugar e voltar um lugar pro padrão'),
  ('fotos.arrumar', 'fotos', 'arrumar', 3, 'arrumar',  'apagar uma foto do acervo de vez')
on conflict (slug) do update
  set pagina_slug = excluded.pagina_slug, acao = excluded.acao, nivel = excluded.nivel,
      rotulo = excluded.rotulo, descricao = excluded.descricao;


-- =============================================================================
-- 4. As portas
-- =============================================================================

-- Aparador de caminho. O caminho é gerado pelo console, mas ele chega aqui pelo
-- corpo de uma chamada como qualquer outra coisa vinda de fora: só passa o que
-- parece caminho de objeto nosso, e '..' não passa nunca.
create or replace function public.foto_caminho_ok(p_valor text)
returns boolean
language sql
immutable
as $$
  select coalesce(
    p_valor ~ '^[a-z0-9][a-z0-9._/-]{2,180}$'
    and p_valor not like '%..%'
    and p_valor not like '%//%',
    false
  );
$$;

-- ---------------------------------------------------------------------------
-- A leitura do SITE. Pública (é o site aberto), e devolve só o que a página
-- precisa: o lugar, o caminho e a descrição. Quem trocou e quando fica de fora
-- — isso é da casa, não de quem visita.
-- ---------------------------------------------------------------------------
create or replace function public.fotos_do_site()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(jsonb_build_object('slot', f.slot, 'caminho', f.caminho, 'alt', f.alt)
              order by f.slot),
    '[]'::jsonb
  )
  from public.site_fotos f;
$$;

-- ---------------------------------------------------------------------------
-- A leitura do CONSOLE: o acervo inteiro mais os lugares já ocupados, numa
-- viagem só. `returns jsonb` e não `returns table` pelo mesmo motivo da 0045:
-- leitura composta em `returns table` é uma dúzia de colunas declaradas pra
-- errar, e foi um erro desses (varchar declarado como text) que deixou cinco
-- abas mortas da 0017 até a 0042.
-- ---------------------------------------------------------------------------
create or replace function public.admin_fotos_painel()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_galeria jsonb;
  v_lugares jsonb;
begin
  if not public.tem_permissao('fotos.ver') then
    raise exception 'sem permissão pra ver as fotos do site';
  end if;

  select coalesce(jsonb_agg(g order by g->>'enviada_em' desc), '[]'::jsonb)
    into v_galeria
    from (
      select jsonb_build_object(
               'id', f.id,
               'caminho', f.caminho,
               'nome', f.nome,
               'alt', f.alt,
               'bytes', f.bytes,
               'tipo', f.tipo,
               'enviada_em', f.enviada_em,
               'quem', p.full_name,
               'usos', (select count(*) from public.site_fotos s where s.caminho = f.caminho)
             ) as g
        from public.fotos_galeria f
        left join public.profiles p on p.id = f.enviada_por
    ) t;

  select coalesce(jsonb_agg(l order by l->>'slot'), '[]'::jsonb)
    into v_lugares
    from (
      select jsonb_build_object(
               'slot', s.slot,
               'caminho', s.caminho,
               'alt', s.alt,
               'atualizado_em', s.atualizado_em,
               'quem', p.full_name
             ) as l
        from public.site_fotos s
        left join public.profiles p on p.id = s.atualizado_por
    ) t;

  return jsonb_build_object('galeria', v_galeria, 'lugares', v_lugares);
end;
$$;

-- ---------------------------------------------------------------------------
-- Registrar no acervo a foto que ACABOU de subir pro Storage. O arquivo já
-- passou pela policy do bucket; aqui entra a ficha dele.
-- ---------------------------------------------------------------------------
create or replace function public.admin_foto_registrar(
  p_caminho text,
  p_nome    text,
  p_alt     text default null,
  p_bytes   bigint default null,
  p_tipo    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_nome text := nullif(btrim(coalesce(p_nome, '')), '');
  v_alt  text := nullif(btrim(coalesce(p_alt, '')), '');
  v_id   uuid;
begin
  if not public.tem_permissao('fotos.mexer') then
    raise exception 'sem permissão pra subir foto do site';
  end if;
  if not public.foto_caminho_ok(p_caminho) then
    raise exception 'esse caminho de arquivo não serve';
  end if;
  if v_nome is null then
    raise exception 'dá um nome pra foto, pra achar ela depois';
  end if;

  insert into public.fotos_galeria (caminho, nome, alt, bytes, tipo, enviada_por)
  values (p_caminho, left(v_nome, 80), left(v_alt, 220), p_bytes, left(nullif(btrim(coalesce(p_tipo, '')), ''), 40), v_uid)
  on conflict (caminho) do update
    set nome = excluded.nome, alt = excluded.alt
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Trocar a foto de UM lugar do site. O lugar chega como slug (o `slot` do
-- `fotos-do-site.js`) e a foto como id da galeria: assim não há caminho vindo
-- do client, só um id de linha que já existe.
-- ---------------------------------------------------------------------------
create or replace function public.admin_foto_definir(p_slot text, p_foto_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_slot    text := lower(btrim(coalesce(p_slot, '')));
  v_caminho text;
  v_alt     text;
  v_nome    text;
begin
  if not public.tem_permissao('fotos.mexer') then
    raise exception 'sem permissão pra trocar as fotos do site';
  end if;
  if v_slot !~ '^[a-z0-9][a-z0-9-]{1,59}$' then
    raise exception 'esse lugar do site não existe';
  end if;

  select caminho, alt, nome into v_caminho, v_alt, v_nome
    from public.fotos_galeria where id = p_foto_id;
  if v_caminho is null then
    raise exception 'essa foto não está mais no acervo';
  end if;

  insert into public.site_fotos (slot, caminho, alt, atualizado_em, atualizado_por)
  values (v_slot, v_caminho, v_alt, now(), v_uid)
  on conflict (slot) do update
    set caminho = excluded.caminho, alt = excluded.alt,
        atualizado_em = now(), atualizado_por = excluded.atualizado_por;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'foto_do_site_trocada', 'site_fotos', v_slot,
          jsonb_build_object('foto', v_nome, 'caminho', v_caminho));

  return jsonb_build_object('ok', true, 'slot', v_slot, 'caminho', v_caminho, 'alt', v_alt);
end;
$$;

-- ---------------------------------------------------------------------------
-- Voltar um lugar pro padrão: apaga a linha, e o site volta a mostrar a foto
-- que está no HTML. Nenhum arquivo é perdido.
-- ---------------------------------------------------------------------------
create or replace function public.admin_foto_soltar(p_slot text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_slot text := lower(btrim(coalesce(p_slot, '')));
  v_tinha text;
begin
  if not public.tem_permissao('fotos.mexer') then
    raise exception 'sem permissão pra trocar as fotos do site';
  end if;

  delete from public.site_fotos where slot = v_slot returning caminho into v_tinha;
  if v_tinha is null then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'foto_do_site_solta', 'site_fotos', v_slot,
          jsonb_build_object('caminho', v_tinha));

  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Apagar uma foto do acervo. Recusa enquanto ela estiver em algum lugar do
-- site: apagar por baixo deixaria o lugar apontando pra um arquivo que não
-- existe, e o site mostraria um quadro quebrado sem ninguém entender por quê.
-- Devolve o caminho pro console apagar o arquivo no Storage em seguida.
-- ---------------------------------------------------------------------------
create or replace function public.admin_foto_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_caminho text;
  v_nome    text;
  v_usos    integer;
begin
  if not public.tem_permissao('fotos.arrumar') then
    raise exception 'sem permissão pra apagar foto do acervo';
  end if;

  select caminho, nome into v_caminho, v_nome from public.fotos_galeria where id = p_id;
  if v_caminho is null then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  select count(*) into v_usos from public.site_fotos where caminho = v_caminho;
  if v_usos > 0 then
    raise exception 'essa foto está em % lugar(es) do site. tira ela de lá primeiro', v_usos;
  end if;

  delete from public.fotos_galeria where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'foto_do_acervo_apagada', 'fotos_galeria', p_id::text,
          jsonb_build_object('foto', v_nome, 'caminho', v_caminho));

  return jsonb_build_object('ok', true, 'caminho', v_caminho);
end;
$$;


-- =============================================================================
-- 5. Quem pode chamar o quê
-- -----------------------------------------------------------------------------
-- A leitura do site é a única aberta a `anon` (ela É o site). As `admin_*`
-- ficam só pra sessão logada, e lá dentro cada uma pergunta pela permissão.
-- =============================================================================

revoke all on function public.foto_caminho_ok(text) from public, anon, authenticated;

revoke all on function public.fotos_do_site() from public;
grant execute on function public.fotos_do_site() to anon, authenticated;

revoke all on function public.admin_fotos_painel() from public, anon;
grant execute on function public.admin_fotos_painel() to authenticated;

revoke all on function public.admin_foto_registrar(text, text, text, bigint, text) from public, anon;
grant execute on function public.admin_foto_registrar(text, text, text, bigint, text) to authenticated;

revoke all on function public.admin_foto_definir(text, uuid) from public, anon;
grant execute on function public.admin_foto_definir(text, uuid) to authenticated;

revoke all on function public.admin_foto_soltar(text) from public, anon;
grant execute on function public.admin_foto_soltar(text) to authenticated;

revoke all on function public.admin_foto_remover(uuid) from public, anon;
grant execute on function public.admin_foto_remover(uuid) to authenticated;



-- ===== 0055_tetos_e_repetido.sql =====

-- =============================================================================
-- 0055_tetos_e_repetido.sql — o que a auditoria dos dez commits achou no banco
--
-- Duas correções nas duas funções abertas a `anon`, que são as únicas portas de
-- escrita que qualquer pessoa da internet alcança com a chave do bundle. O
-- corpo das duas é o que já está no ar (extraído da 0040 e da 0053); só as
-- partes comentadas com "(0055)" mudam.
--
--   1. `registrar_rastro` ganha um teto GLOBAL de 20 mil eventos por hora, e o
--      contador de páginas da visita para de crescer sem fim. Os dois tetos da
--      0053 (400 visitas novas por hora, 400 eventos por visita) seguram cada
--      dimensão sozinha, mas se multiplicam: 160 mil linhas por hora era o
--      teto de verdade, e disso ninguém tinha se dado conta.
--
--   2. `registrar_lead_evento` passa a dizer `repetido: true` quando o
--      anti-flood de 30 segundos segura o pedido. A função continua NÃO criando
--      a linha; o que ela deixa de fazer é responder igualzinho a um pedido que
--      entrou. Desde que o WhatsApp saiu da /eventos (ago/2026), essa resposta
--      igual fazia a correção reenviada em menos de 30s sumir com um "anotado"
--      na tela. A página nova lê essa chave; a página velha não a lê e segue
--      funcionando como antes, então esta migration pode ser aplicada sozinha.
--
-- Nenhuma tabela, coluna, policy ou permissão muda. Nada aqui pede re-deploy de
-- Edge Function.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (CREATE OR REPLACE nas duas).
-- =============================================================================


-- =============================================================================
-- 1. registrar_rastro — teto global por hora, e paginas com fim
-- =============================================================================
create or replace function public.registrar_rastro(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_visita     uuid;
  v_pagina     text;
  v_eventos    jsonb := '[]'::jsonb;
  v_ja         integer := 0;
  v_limite     integer := 0;
  v_cliques    integer := 0;
  v_nova_pag   integer := 0;
  v_saida      jsonb;
  v_carrinho   jsonb;
begin
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then
    return jsonb_build_object('ok', true);
  end if;

  -- Id malformado não é erro pra quem navega: é pulso perdido, e ponto.
  begin
    v_visita := (p_dados->>'visita')::uuid;
  exception when others then
    return jsonb_build_object('ok', true);
  end;
  if v_visita is null then
    return jsonb_build_object('ok', true);
  end if;

  v_pagina := public.rastro_caminho(p_dados->>'pagina');

  if jsonb_typeof(p_dados->'eventos') = 'array' then
    v_eventos := p_dados->'eventos';
  end if;

  -- Teto por visita (400) e por chamada (40). Passou, o excedente é descartado
  -- em silêncio: a visita já disse o que tinha pra dizer.
  select count(*) into v_ja from public.rastro_eventos where visita_id = v_visita;
  v_limite := greatest(0, least(40, 400 - v_ja));

  -- Teto GLOBAL por hora (0055). Os dois tetos da 0053 seguram a quantidade de
  -- visitas e o tamanho de cada uma, mas eles se MULTIPLICAM: 400 visitas novas
  -- por hora vezes 400 eventos por visita são 160 mil linhas por hora, uns meio
  -- giga por dia, e o endpoint é aberto a anon com a chave que está no bundle.
  -- Vinte mil por hora é ordens de grandeza acima de um dia cheio de verdade num
  -- café, e é um número que a tabela aguenta. O `limit` por dentro faz a conta
  -- parar assim que alcança o teto, em vez de varrer a hora inteira.
  -- Vem ANTES do v_cliques de propósito: se zerasse o limite depois, a visita
  -- contaria clique que nunca virou linha, e o contador passaria a mentir.
  if v_limite > 0
     and (select count(*) from (
            select 1 from public.rastro_eventos
             where criado_em > now() - interval '1 hour'
             limit 20000) t) >= 20000 then
    v_limite := 0;
  end if;

  select count(*) filter (where coalesce(e->>'tipo', 'clique') <> 'vista')
    into v_cliques
    from (
      select e from jsonb_array_elements(v_eventos) with ordinality as t(e, i)
       where t.i <= v_limite
    ) s;
  v_cliques := coalesce(v_cliques, 0);

  -- Teto global de visitas novas por hora. O anti-flood da 0040 é por contato;
  -- aqui não há contato nenhum, então o freio é a torneira inteira. Visita que
  -- JÁ existe segue escrevendo: quem está navegando de verdade não é cortado no
  -- meio por causa de uma enxurrada de fora.
  if not exists (select 1 from public.rastro_visitas where id = v_visita)
     and (select count(*) from public.rastro_visitas
           where criada_em > now() - interval '1 hour') >= 400 then
    return jsonb_build_object('ok', true);
  end if;

  if coalesce((p_dados->>'pagina_nova')::boolean, false) then
    v_nova_pag := 1;
  end if;

  v_saida    := case when jsonb_typeof(p_dados->'saida') = 'object' then p_dados->'saida' end;
  v_carrinho := case when jsonb_typeof(p_dados->'carrinho') = 'object' then p_dados->'carrinho' end;

  insert into public.rastro_visitas as v (
    id, user_id, dispositivo, origem, pagina_entrada,
    pagina_saida, secao_saida, alvo_saida,
    cliques, paginas, carrinho_itens, carrinho_centavos,
    checkout_iniciado, comprou, vista_em
  )
  values (
    v_visita,
    -- SEMPRE de auth.uid(): o corpo da chamada não diz quem é ninguém.
    auth.uid(),
    case when p_dados->>'dispositivo' in ('celular', 'computador') then p_dados->>'dispositivo' end,
    public.rastro_texto(p_dados->>'origem', 80),
    v_pagina,
    case when v_saida is not null then public.rastro_caminho(v_saida->>'pagina') end,
    case when v_saida is not null then public.rastro_texto(v_saida->>'secao', 80) end,
    case when v_saida is not null then public.rastro_texto(v_saida->>'alvo', 80) end,
    v_cliques,
    1,
    greatest(0, least(coalesce((v_carrinho->>'itens')::integer, 0), 999)),
    greatest(0, least(coalesce((v_carrinho->>'centavos')::integer, 0), 100000000)),
    coalesce((p_dados->>'checkout')::boolean, false),
    coalesce((p_dados->>'comprou')::boolean, false),
    now()
  )
  on conflict (id) do update set
    vista_em          = now(),
    -- A pessoa pode ter entrado logada no meio da visita. Uma vez carimbado,
    -- não se troca: a visita é de quem a começou como dono.
    user_id           = coalesce(v.user_id, excluded.user_id),
    -- Saída nova ganha da antiga (é o ÚLTIMO clique que interessa); pulso sem
    -- saída não apaga a que já estava lá.
    pagina_saida      = coalesce(excluded.pagina_saida, v.pagina_saida),
    secao_saida       = coalesce(excluded.secao_saida,  v.secao_saida),
    alvo_saida        = coalesce(excluded.alvo_saida,   v.alvo_saida),
    cliques           = v.cliques + excluded.cliques,
    -- Com teto (0055): a visita que já existe não passa pelo freio horário, e
    -- nada impedia mil pulsos com `pagina_nova` inflando o "viram uma página
    -- só" do relatório. Quinhentas páginas numa aba só já é mais do que
    -- qualquer navegação real.
    paginas           = least(v.paginas + v_nova_pag, 500),
    carrinho_itens    = case when v_carrinho is not null then excluded.carrinho_itens    else v.carrinho_itens    end,
    carrinho_centavos = case when v_carrinho is not null then excluded.carrinho_centavos else v.carrinho_centavos end,
    -- Marco não desliga: quem chegou no checkout chegou, mesmo que volte pra
    -- vitrine depois.
    checkout_iniciado = v.checkout_iniciado or excluded.checkout_iniciado,
    comprou           = v.comprou or excluded.comprou;

  if v_limite > 0 then
    insert into public.rastro_eventos (visita_id, tipo, pagina, secao, alvo)
      select
        v_visita,
        case when t.e->>'tipo' = 'vista' then 'vista' else 'clique' end,
        coalesce(nullif(public.rastro_caminho(t.e->>'pagina'), 'outra'), v_pagina),
        coalesce(public.rastro_texto(t.e->>'secao', 80), 'sem seção'),
        public.rastro_texto(t.e->>'alvo', 80)
        from jsonb_array_elements(v_eventos) with ordinality as t(e, i)
       where t.i <= v_limite
         and jsonb_typeof(t.e) = 'object';
  end if;

  -- A faxina sorteada (ver o cabeçalho). Uma em cada cinquenta chamadas.
  if random() < 0.02 then
    delete from public.rastro_visitas where criada_em < now() - interval '180 days';
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

-- =============================================================================
-- 2. registrar_lead_evento — o repetido para de se passar por pedido novo
-- =============================================================================
create or replace function public.registrar_lead_evento(
  p_nome      text,
  p_contato   text,
  p_tipo      text,
  p_email     text default null,
  p_data      date default null,
  p_pessoas   int default null,
  p_mensagem  text default null,
  p_origem    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome     text := btrim(coalesce(p_nome, ''));
  v_contato  text := btrim(coalesce(p_contato, ''));
  v_tipo     text := btrim(coalesce(p_tipo, ''));
  v_email    text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_mensagem text := nullif(btrim(coalesce(p_mensagem, '')), '');
  v_origem   text := nullif(btrim(coalesce(p_origem, '')), '');
  v_id       uuid;
begin
  if char_length(v_nome) not between 2 and 80 then
    return jsonb_build_object('ok', false, 'erro', 'falta teu nome');
  end if;

  -- Precisa de dígito suficiente pra ser telefone; a máscara do site já entrega
  -- formatado, mas quem chama a função por fora não passa por ela.
  if char_length(v_contato) not between 8 and 40
     or char_length(regexp_replace(v_contato, '[^0-9]', '', 'g')) < 10 then
    return jsonb_build_object('ok', false, 'erro', 'esse telefone não parece completo');
  end if;

  if char_length(v_tipo) not between 2 and 40 then
    return jsonb_build_object('ok', false, 'erro', 'conta pra gente que tipo de evento é');
  end if;

  if v_email is not null
     and (char_length(v_email) not between 6 and 160
          or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then
    return jsonb_build_object('ok', false, 'erro', 'esse e-mail não parece completo');
  end if;

  if p_pessoas is not null and p_pessoas not between 1 and 500 then
    return jsonb_build_object('ok', false, 'erro', 'quantas pessoas, mais ou menos?');
  end if;

  if v_mensagem is not null then v_mensagem := left(v_mensagem, 600); end if;
  if v_origem   is not null then v_origem   := left(v_origem, 120);   end if;

  -- Anti-flood: mesmo contato de novo dentro de 30s não vira linha nova. A
  -- resposta é a mesma, porque pra quem está do outro lado é a mesma coisa
  -- (o pedido já entrou).
  if exists (
    select 1 from public.leads_evento
     where contato = v_contato
       and created_at > now() - interval '30 seconds'
  ) then
    -- `repetido` é novo (0055). Enquanto o WhatsApp era o canal, engolir isto em
    -- silêncio era inofensivo: a conversa ia junto e levava a versão certa. Sem
    -- ele, quem viu um erro no recado, corrigiu e reenviou dentro da janela lia
    -- "anotado" e ia embora achando que a casa tinha a correção, que na verdade
    -- se perdeu. A linha segue não sendo criada (o freio continua valendo); o
    -- que muda é que agora a página sabe disso e conta a verdade.
    return jsonb_build_object('ok', true, 'repetido', true);
  end if;

  insert into public.leads_evento (nome, contato, email, tipo, data_pretendida, pessoas, mensagem, origem, user_id)
  values (v_nome, v_contato, v_email, v_tipo, p_data, p_pessoas, v_mensagem, v_origem, auth.uid())
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- =============================================================================
-- 3. Grants — os mesmos de sempre, repetidos porque CREATE OR REPLACE não mexe
--    neles, mas deixar explícito é o que faz este arquivo se bastar.
-- =============================================================================
revoke all on function public.registrar_rastro(jsonb) from public;
grant execute on function public.registrar_rastro(jsonb) to anon, authenticated;

revoke all on function public.registrar_lead_evento(text, text, text, text, date, int, text, text) from public;
grant execute on function public.registrar_lead_evento(text, text, text, text, date, int, text, text) to anon, authenticated;



COMMIT;

