-- =============================================================================
-- 0030_avisos_reposicao.sql — "Volta pra vitrine" (avisa quando o produto voltar) 🔔
--
-- Puxa o gancho da lista de desejos (0029): quando um produto está esgotado /
-- fora da vitrine, em vez de um "esgotado" mudo, a pessoa toca em "me avisa
-- quando voltar" e deixa o interesse registrado. Quando a casa repõe, o front
-- mostra um "voltou 💛" na volta dela (sem e-mail por enquanto). Pro Casa, o
-- console mostra QUANTAS pessoas esperam cada produto voltar — o sinal mais
-- forte pra guiar a reposição.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Mesmo padrão do loja_desejos (0029): o produto é identificado pelo `slug`
--     da URL /produto; `produto_nome` é snapshot pro console. Registrar interesse
--     é aberto a qualquer pessoa logada (não é perk de assinante).
--   • Interesse de reposição é dado BENIGNO e por-usuário (não entra na lista de
--     tabelas sensíveis do security-check): a escrita é DIRETA pelo client via
--     RLS, sempre travada em `auth.uid()`. Cada um só lê/põe/tira o PRÓPRIO aviso.
--   • O console lê o agregado por uma RPC SECURITY DEFINER (RLS barraria a soma
--     entre usuários), gated por `tem_permissao('relatorios')` — é um relatório.
--     O nome exibido é o MAIS FREQUENTE por slug (resiliente a linha adulterada).
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

create table if not exists public.avisos_reposicao (
  user_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  produto_slug text not null check (char_length(btrim(produto_slug)) between 1 and 80),
  produto_nome text not null check (char_length(btrim(produto_nome)) between 1 and 160),
  created_at   timestamptz not null default now(),
  primary key (user_id, produto_slug)
);

create index if not exists idx_avisos_reposicao_slug on public.avisos_reposicao (produto_slug);

alter table public.avisos_reposicao enable row level security;

-- Cada um cuida só do próprio aviso. `default auth.uid()` preenche o dono, e a
-- policy confere — o client nunca registra em nome de outro.
drop policy if exists avisos_reposicao_select_own on public.avisos_reposicao;
create policy avisos_reposicao_select_own on public.avisos_reposicao
  for select to authenticated using (user_id = auth.uid());

drop policy if exists avisos_reposicao_insert_own on public.avisos_reposicao;
create policy avisos_reposicao_insert_own on public.avisos_reposicao
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists avisos_reposicao_delete_own on public.avisos_reposicao;
create policy avisos_reposicao_delete_own on public.avisos_reposicao
  for delete to authenticated using (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- admin_avisos_reposicao() → quem está esperando o quê. Owner ou 'relatorios'.
-- Agrega por slug; o nome exibido é o mais frequente daquele slug (defesa contra
-- um snapshot adulterado numa linha solta).
-- -----------------------------------------------------------------------------
create or replace function public.admin_avisos_reposicao()
returns table (
  produto_slug text,
  produto_nome text,
  esperando    bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra ver os avisos de reposição';
  end if;
  return query
    select
      a.produto_slug,
      (select a2.produto_nome
         from public.avisos_reposicao a2
        where a2.produto_slug = a.produto_slug
        group by a2.produto_nome
        order by count(*) desc, a2.produto_nome asc
        limit 1)                as produto_nome,
      count(*)::bigint          as esperando
    from public.avisos_reposicao a
    group by a.produto_slug
    order by count(*) desc, produto_nome asc;
end;
$$;

revoke all on function public.admin_avisos_reposicao() from public, anon;
grant execute on function public.admin_avisos_reposicao() to authenticated;
