-- =============================================================================
-- 0016_sessoes
-- -----------------------------------------------------------------------------
-- "sair de todos os aparelhos" vira "aparelhos conectados": a pessoa VÊ a lista
-- de onde a conta dela está aberta (nome do aparelho + endereço de IP + quando
-- foi visto) e escolhe o que encerrar, em vez de derrubar tudo no escuro.
--
-- Por que precisa de migration: as sessões vivem em `auth.sessions`, tabela
-- INTERNA do GoTrue. O schema `auth` NÃO é exposto pelo PostgREST, então o
-- client não consegue lê-la de jeito nenhum — nem com RLS, nem com policy. E o
-- supabase-js só oferece `signOut({ scope: 'global' })`, que é justamente o
-- tudo-ou-nada que a gente está trocando. O caminho é uma função SECURITY
-- DEFINER no schema `public`, que lê o `auth.sessions` por dentro e devolve
-- SÓ as linhas do próprio usuário.
--
-- Confiança zero no client, do mesmo jeito que no resto do projeto:
--   • o dono é sempre `auth.uid()`, lido do JWT no servidor — nunca um id que
--     o client mandou. Passar o id de outra pessoa não devolve nem apaga nada.
--   • "esta é a sessão atual" também vem do JWT (claim `session_id`), então
--     "sair dos outros aparelhos" não consegue ser enganado a manter o aparelho
--     errado (ou a derrubar o próprio e deixar o invasor dentro).
--   • as três funções são revogadas de `anon`/`public` e concedidas só a
--     `authenticated`. Deslogado não enxerga nada.
--   • `search_path` fixo (padrão das SECURITY DEFINER do projeto).
--
-- Apagar a linha de `auth.sessions` é o que de fato desconecta: os refresh
-- tokens daquela sessão morrem junto (a gente apaga explicitamente antes, pra
-- não depender do ON DELETE do GoTrue), então o aparelho não consegue mais
-- renovar. O access token que ele já tem na mão continua valendo até expirar
-- sozinho — é o MESMO comportamento do `signOut({ scope:'global' })` do
-- Supabase, que também não revoga JWT já emitido.
--
-- Idempotente (CREATE OR REPLACE) e autocontida. Não mexe em nada anterior.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- minhas_sessoes() — a lista pra tela.
-- Devolve o user_agent cru (quem transforma em "Chrome no Windows" é o front) e
-- o IP como texto. Só sessões vivas (`not_after` no futuro ou nulo), da mais
-- recente pra mais antiga.
-- -----------------------------------------------------------------------------
create or replace function public.minhas_sessoes()
returns table (
  id         uuid,
  aparelho   text,
  endereco   text,
  criada_em  timestamptz,
  vista_em   timestamptz,
  atual      boolean
)
language sql
security definer
stable
set search_path = public, auth, pg_temp
as $$
  select
    s.id,
    coalesce(s.user_agent, '')                          as aparelho,
    coalesce(host(s.ip), '')                            as endereco,
    s.created_at                                        as criada_em,
    coalesce(s.updated_at, s.created_at)                as vista_em,
    s.id is not distinct from nullif(
      current_setting('request.jwt.claims', true)::jsonb ->> 'session_id', ''
    )::uuid                                             as atual
  from auth.sessions s
  where s.user_id = auth.uid()
    and (s.not_after is null or s.not_after > now())
  order by coalesce(s.updated_at, s.created_at) desc;
$$;

-- -----------------------------------------------------------------------------
-- encerrar_sessao(uuid) — desconecta UM aparelho.
-- O `and user_id = auth.uid()` é a trava: id de terceiro simplesmente não casa
-- e a função devolve false, sem vazar se aquela sessão existe.
-- -----------------------------------------------------------------------------
create or replace function public.encerrar_sessao(p_session_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_n   integer;
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  delete from auth.refresh_tokens rt
   where rt.session_id = p_session_id
     and exists (
       select 1 from auth.sessions s
        where s.id = p_session_id and s.user_id = v_uid
     );

  delete from auth.sessions s
   where s.id = p_session_id
     and s.user_id = v_uid;

  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$$;

-- -----------------------------------------------------------------------------
-- encerrar_outras_sessoes() — desconecta todos MENOS este aparelho.
-- Qual é "este" vem do JWT, não do client. Se por algum motivo a claim
-- `session_id` não vier, a gente NÃO derruba nada (melhor não fazer do que
-- deslogar a pessoa do próprio aparelho por engano).
-- -----------------------------------------------------------------------------
create or replace function public.encerrar_outras_sessoes()
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_atual  uuid;
  v_n      integer;
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  v_atual := nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'session_id', '')::uuid;
  if v_atual is null then
    return 0;
  end if;

  delete from auth.refresh_tokens rt
   where rt.session_id in (
     select s.id from auth.sessions s
      where s.user_id = v_uid and s.id <> v_atual
   );

  delete from auth.sessions s
   where s.user_id = v_uid
     and s.id <> v_atual;

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- -----------------------------------------------------------------------------
-- Permissões: deslogado não enxerga nem encerra nada.
-- -----------------------------------------------------------------------------
revoke all on function public.minhas_sessoes()            from public, anon;
revoke all on function public.encerrar_sessao(uuid)       from public, anon;
revoke all on function public.encerrar_outras_sessoes()   from public, anon;

grant execute on function public.minhas_sessoes()          to authenticated;
grant execute on function public.encerrar_sessao(uuid)     to authenticated;
grant execute on function public.encerrar_outras_sessoes() to authenticated;
