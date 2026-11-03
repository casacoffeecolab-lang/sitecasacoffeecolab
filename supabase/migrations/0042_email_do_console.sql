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
