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
