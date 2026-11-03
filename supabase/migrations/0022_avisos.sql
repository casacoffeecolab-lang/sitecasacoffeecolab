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
