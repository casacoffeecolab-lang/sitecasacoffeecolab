-- =============================================================================
-- Casa Coffee Colab — scripts/check-rls.sql
-- Verificação de RLS no banco AO VIVO. Rode no SQL Editor do Supabase depois de
-- aplicar as migrations. Dois blocos:
--   A) PROVA AUTOMÁTICA (read-only): falha com RAISE se algo estiver errado.
--   B) TESTE NEGATIVO como anon (opcional): confirma na marra que anon é barrado.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A) PROVA AUTOMÁTICA — não altera nada. Se passar, imprime "RLS OK".
--    Falha se: (1) alguma tabela public sem RLS; (2) policy sensível exposta a
--    anon/PUBLIC. (polroles = {0} significa PUBLIC/todos os papéis.)
-- -----------------------------------------------------------------------------
do $$
declare
  v_bad text;
  v_sensiveis text[] := array[
    'profiles', 'audit_log', 'subscriptions', 'orders', 'order_items',
    'points_ledger', 'redemptions', 'user_achievements',
    'coupons', 'pos_webhook_events', 'unclaimed_points'
  ];
begin
  -- (1) Toda tabela de public precisa de RLS habilitada.
  select string_agg(c.relname, ', ' order by c.relname) into v_bad
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  if v_bad is not null then
    raise exception 'RLS FAIL: tabelas sem RLS habilitada: %', v_bad;
  end if;

  -- (2) Nenhuma policy nas tabelas sensíveis pode alcançar anon ou PUBLIC.
  select string_agg(distinct c.relname || '.' || p.polname, ', ') into v_bad
  from pg_policy p
  join pg_class c on c.oid = p.polrelid
  where c.relname = any (v_sensiveis)
    and (
      p.polroles = array[0::oid]  -- PUBLIC (todos os papéis, incl. anon)
      or exists (
        select 1 from pg_roles r
        where r.oid = any (p.polroles) and r.rolname = 'anon'
      )
    );
  if v_bad is not null then
    raise exception 'RLS FAIL: policy sensível exposta a anon/PUBLIC: %', v_bad;
  end if;

  raise notice 'RLS OK: todas as tabelas de public com RLS e nenhuma policy sensível exposta a anon/PUBLIC.';
end $$;

-- Panorama (rode e confira à vista): RLS por tabela.
select c.relname as tabela, c.relrowsecurity as rls_on
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;

-- Panorama: policies por tabela (nome, comando, papéis).
select c.relname as tabela,
       p.polname as policy,
       case p.polcmd when 'r' then 'select' when 'a' then 'insert'
                     when 'w' then 'update' when 'd' then 'delete' else 'all' end as comando,
       coalesce(
         (select string_agg(r.rolname, ',') from pg_roles r where r.oid = any (p.polroles)),
         'PUBLIC'
       ) as papeis
from pg_policy p
join pg_class c on c.oid = p.polrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
order by c.relname, p.polname;

-- -----------------------------------------------------------------------------
-- B) TESTE NEGATIVO como anon (opcional, roda em transação e faz ROLLBACK).
--    Se qualquer INSERT abaixo NÃO falhar, o bloco lança 'RLS FAIL'.
--    Esperado: os dois inserts são barrados; o select de unclaimed volta 0.
-- -----------------------------------------------------------------------------
begin;
  set local role anon;

  -- anon não pode LER unclaimed_points: RLS devolve 0 linhas (ou nega o acesso).
  do $$
  declare n int;
  begin
    begin
      select count(*) into n from public.unclaimed_points;
    exception
      when insufficient_privilege then n := 0;  -- acesso negado também é "barrado"
    end;
    if n <> 0 then
      raise exception 'RLS FAIL: anon leu % linha(s) de unclaimed_points (esperado 0)', n;
    end if;
  end $$;

  -- anon não pode INSERIR em unclaimed_points.
  do $$
  begin
    begin
      insert into public.unclaimed_points (identifier_type, identifier_value, pontos, origem)
      values ('email', '__rls_test__@casa', 1, '__rls_test__');
      raise exception 'RLS FAIL: anon conseguiu inserir em unclaimed_points';
    exception
      when insufficient_privilege then null;  -- esperado (42501)
    end;
  end $$;

  -- anon não pode INSERIR em pos_webhook_events.
  do $$
  begin
    begin
      insert into public.pos_webhook_events (external_transaction_id, payload)
      values ('__rls_test__', '{}'::jsonb);
      raise exception 'RLS FAIL: anon conseguiu inserir em pos_webhook_events';
    exception
      when insufficient_privilege then null;  -- esperado (42501)
    end;
  end $$;

  reset role;
rollback;  -- nada é persistido

-- Se chegou até aqui sem erro, os testes negativos passaram.
