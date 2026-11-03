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
