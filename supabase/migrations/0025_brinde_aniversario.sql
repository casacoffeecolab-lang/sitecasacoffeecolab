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
