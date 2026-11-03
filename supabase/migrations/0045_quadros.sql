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
