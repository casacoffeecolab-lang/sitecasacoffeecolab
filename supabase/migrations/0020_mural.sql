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
