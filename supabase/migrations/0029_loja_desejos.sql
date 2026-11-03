-- =============================================================================
-- 0029_loja_desejos.sql — "Ficou pra depois" (lista de desejos da loja) 🔖
--
-- O irmão do "teus favoritos" do cardápio (0027), agora na loja: um coração em
-- cada produto SALVA pra depois sem botar no carrinho. Uma tirinha "ficou pra
-- depois" no topo da /loja (e um espelho no /conta/perfil) reúne o que a pessoa
-- guardou, tirando o atrito do "gostei mas agora não". De quebra, o Casa vê no
-- console a demanda represada por produto.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • O catálogo é um mock no client (PRODUTOS no app.js), então o produto é
--     identificado por um `produto_slug` estável (o mesmo slug da URL /produto);
--     o `produto_nome` é um snapshot pro console. Guardar é aberto a QUALQUER
--     pessoa logada (não é perk de assinante) — quanto mais gente guarda, mais
--     sinal pra casa.
--   • Desejo é dado BENIGNO e por-usuário (não entra na lista de tabelas
--     sensíveis do security-check): a escrita é DIRETA pelo client via RLS,
--     sempre travada em `auth.uid()` (o default preenche o dono; a policy
--     confere). Cada um só lê/guarda/tira o PRÓPRIO desejo.
--   • O console lê o agregado por uma RPC SECURITY DEFINER (RLS barraria a soma
--     entre usuários), gated por `tem_permissao('relatorios')` — é um relatório.
--     Pra não confiar cegamente no nome que o client mandou, o agregado usa o
--     nome MAIS FREQUENTE por slug (resiliente a uma linha adulterada; o console
--     ainda escapa tudo).
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

create table if not exists public.loja_desejos (
  user_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  produto_slug text not null check (char_length(btrim(produto_slug)) between 1 and 80),
  produto_nome text not null check (char_length(btrim(produto_nome)) between 1 and 160),
  created_at   timestamptz not null default now(),
  primary key (user_id, produto_slug)
);

create index if not exists idx_loja_desejos_slug on public.loja_desejos (produto_slug);

alter table public.loja_desejos enable row level security;

-- Cada um cuida só do próprio desejo. `default auth.uid()` preenche o dono, e a
-- policy confere — o client nunca guarda em nome de outro.
drop policy if exists loja_desejos_select_own on public.loja_desejos;
create policy loja_desejos_select_own on public.loja_desejos
  for select to authenticated using (user_id = auth.uid());

drop policy if exists loja_desejos_insert_own on public.loja_desejos;
create policy loja_desejos_insert_own on public.loja_desejos
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists loja_desejos_delete_own on public.loja_desejos;
create policy loja_desejos_delete_own on public.loja_desejos
  for delete to authenticated using (user_id = auth.uid());

-- -----------------------------------------------------------------------------
-- admin_loja_desejos() → o que a casa mais quer. Owner ou 'relatorios'.
-- Agrega por slug; o nome exibido é o mais frequente daquele slug (defesa contra
-- um snapshot adulterado numa linha solta).
-- -----------------------------------------------------------------------------
create or replace function public.admin_loja_desejos()
returns table (
  produto_slug text,
  produto_nome text,
  desejos      bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra ver os desejos';
  end if;
  return query
    select
      d.produto_slug,
      (select d2.produto_nome
         from public.loja_desejos d2
        where d2.produto_slug = d.produto_slug
        group by d2.produto_nome
        order by count(*) desc, d2.produto_nome asc
        limit 1)                as produto_nome,
      count(*)::bigint          as desejos
    from public.loja_desejos d
    group by d.produto_slug
    order by count(*) desc, produto_nome asc;
end;
$$;

revoke all on function public.admin_loja_desejos() from public, anon;
grant execute on function public.admin_loja_desejos() to authenticated;
