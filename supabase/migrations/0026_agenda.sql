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
