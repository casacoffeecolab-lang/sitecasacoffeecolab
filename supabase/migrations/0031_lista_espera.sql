-- =============================================================================
-- 0031_lista_espera.sql — "avisa quando a loja abrir" (captura de e-mail) 💌
--
-- Quem passa pelo site e ainda não quer criar conta hoje não deixa rastro
-- nenhum: ou cadastra tudo, ou some. Um campinho no rodapé ("avisa quando a
-- loja abrir de vez") guarda só o e-mail, pra a casa chamar quando abrir.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • É a única tabela do projeto que o VISITANTE DESLOGADO escreve — é o ponto
--     dela. Por isso ela é insert-only pro client: existe policy de INSERT (anon
--     e authenticated) e NENHUMA de select/update/delete, então o deny-by-default
--     do RLS faz o resto. Ninguém, nem logado, LÊ esta tabela pelo client: quem
--     lê é o console, pela RPC abaixo.
--   • A policy repete no `with check` os mesmos limites do CHECK da coluna
--     (formato e tamanho do e-mail) — o client é quem manda o valor, então a
--     trava mora no banco.
--   • Sem user_id de propósito: a graça é justamente não exigir conta. O
--     `origem` guarda só o caminho da página onde a pessoa deixou o e-mail
--     (/home, /loja…), pra a casa saber de onde veio o interesse.
--   • UNIQUE no e-mail pra ninguém entrar duas vezes. O front manda com
--     `ignoreDuplicates` (INSERT … ON CONFLICT DO NOTHING), então repetir o
--     cadastro responde igual a cadastrar pela primeira vez — não dá pra usar a
--     resposta pra descobrir quem já está na lista.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS).
-- =============================================================================

create table if not exists public.lista_espera (
  id         uuid primary key default gen_random_uuid(),
  email      text not null unique
               check (char_length(email) between 6 and 160 and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  origem     text check (origem is null or char_length(origem) <= 120),
  created_at timestamptz not null default now()
);

create index if not exists idx_lista_espera_created on public.lista_espera (created_at desc);

alter table public.lista_espera enable row level security;

-- Só INSERT, e só o que passa pelos limites. Sem policy de select: nem anon nem
-- authenticated leem a lista (deny-by-default).
drop policy if exists lista_espera_insert_publico on public.lista_espera;
create policy lista_espera_insert_publico on public.lista_espera
  for insert to anon, authenticated
  with check (
    char_length(email) between 6 and 160
    and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    and (origem is null or char_length(origem) <= 120)
  );

-- -----------------------------------------------------------------------------
-- admin_lista_espera(limite) → quem está esperando o aviso. Owner ou 'relatorios'
-- (é relatório de interesse, mesma porta dos favoritos/desejos).
-- -----------------------------------------------------------------------------
create or replace function public.admin_lista_espera(p_limite int default 500)
returns table (
  id         uuid,
  email      text,
  origem     text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra ver a lista de espera';
  end if;
  return query
    select e.id, e.email, e.origem, e.created_at
      from public.lista_espera e
     order by e.created_at desc
     limit greatest(1, least(coalesce(p_limite, 500), 2000));
end;
$$;

revoke all on function public.admin_lista_espera(int) from public, anon;
grant execute on function public.admin_lista_espera(int) to authenticated;
