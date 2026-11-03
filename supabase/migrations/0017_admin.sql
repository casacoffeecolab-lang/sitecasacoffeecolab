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
