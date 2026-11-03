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
