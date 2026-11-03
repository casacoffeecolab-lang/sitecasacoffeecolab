-- =============================================================================
-- 0032_senha_inicial_master.sql — a senha inicial do adm master trava o console
--
-- O PROBLEMA (achado em auditoria de segurança):
--   O `scripts/criar-adm-master.mjs` criava a conta do adm master com uma senha
--   combinada, e a obrigação de trocá-la no primeiro acesso existia SÓ na tela
--   (`src/admin.js`). No banco, `senha_alterada_em` era apenas LIDA pra montar o
--   JSON da tela — nenhuma função de papel consultava ela. Ou seja: quem soubesse
--   a senha inicial fazia login direto no endpoint do Auth (a anon key e a URL do
--   projeto estão no bundle público, como têm que estar), recebia um JWT de owner
--   e chamava `admin_usuarios`, `admin_pedidos`, `admin_definir_permissoes` por
--   fora da tela, sem nunca ver o formulário de troca. Pior: `is_staff()` inclui
--   o owner, e a policy `profiles_select` (0002) usa `is_staff()`, então dava pra
--   ler a `profiles` inteira (nome, e-mail, telefone) direto pelo PostgREST.
--
-- A CORREÇÃO, em duas metades:
--   1. O script passa a sortear uma senha aleatória por execução (nada de senha
--      combinada no repo) — ver `scripts/criar-adm-master.mjs`.
--   2. Esta migration move a trava pro BANCO, que é o único lugar onde ela vale.
--
-- COMO A TRAVA SABE QUE A SENHA AINDA É A INICIAL:
--   Não pelo carimbo `senha_alterada_em` — ele é gravado por uma RPC que o próprio
--   invasor poderia chamar, e aí a trava se desarmaria sozinha. A gente guarda o
--   HASH da senha inicial (`profiles.senha_inicial_hash`, copiado de
--   `auth.users.encrypted_password`) e compara com o hash de agora. Enquanto forem
--   iguais, a senha NÃO mudou, ponto — não há RPC que minta sobre isso. Trocar a
--   senha de verdade, pelo Auth, é o único jeito de destravar, e o destravamento é
--   automático (o hash muda). Guardar o hash não é guardar a senha: é o mesmo
--   bcrypt que o Auth já guarda, e ele fica numa coluna que o client não lê
--   (a `profiles` só é legível pelo dono e pelo staff).
--
-- O QUE FICA TRAVADO: todas as funções de papel (`is_owner`, `is_staff`,
--   `is_gerente_or_owner`, `tem_permissao`, `pode_entrar_no_console`) respondem
--   FALSO enquanto a senha inicial estiver de pé. Como as policies de RLS e o
--   corpo de cada `admin_*` chamam essas funções, a conta fica sem privilégio
--   nenhum em lugar nenhum — só a própria linha do `profiles`, como qualquer
--   cliente. O `admin_minhas_permissoes` continua respondendo `console: true` de
--   propósito, senão o console diria "esse balcão não é teu" e a pessoa não teria
--   por onde trocar a senha.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Depende da 0017_admin (colunas `master` / `senha_alterada_em`).
-- Idempotente (add column if not exists / CREATE OR REPLACE).
-- =============================================================================

alter table public.profiles add column if not exists senha_inicial_hash text;

-- Backfill pra quem já tem o master criado: se ele NUNCA trocou a senha
-- (`senha_alterada_em is null`), o hash de agora É o da senha inicial — grava e a
-- trava já vale pra deployments existentes. Quem já trocou fica com a coluna null
-- (nada a travar).
update public.profiles p
   set senha_inicial_hash = u.encrypted_password
  from auth.users u
 where u.id = p.id
   and p.master
   and p.senha_alterada_em is null
   and p.senha_inicial_hash is null;

-- -----------------------------------------------------------------------------
-- senha_inicial_pendente() — true enquanto o master não trocou a senha de fato.
-- Compara o hash guardado com o hash atual do Auth: só a troca real desarma.
-- Vale só pro master (o `handle_new_user` não preenche `senha_alterada_em`, então
-- sem o gate de `master` todo funcionário promovido a partir de conta de cliente
-- cairia aqui e perderia o acesso sem motivo).
-- -----------------------------------------------------------------------------
create or replace function public.senha_inicial_pendente()
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select exists (
    select 1
      from public.profiles p
      join auth.users u on u.id = p.id
     where p.id = auth.uid()
       and p.master
       and p.senha_inicial_hash is not null
       and u.encrypted_password = p.senha_inicial_hash
  );
$$;

revoke all on function public.senha_inicial_pendente() from public, anon;
grant execute on function public.senha_inicial_pendente() to authenticated;

-- -----------------------------------------------------------------------------
-- As funções de papel, agora com a trava. Corpo idêntico ao original (0001/0017),
-- só acrescido do `and not public.senha_inicial_pendente()`.
-- -----------------------------------------------------------------------------
create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.profiles where id = auth.uid()) = 'owner'
    and not public.senha_inicial_pendente(),
    false
  );
$$;

create or replace function public.is_gerente_or_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.profiles where id = auth.uid()) in ('gerente', 'owner')
    and not public.senha_inicial_pendente(),
    false
  );
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.profiles where id = auth.uid()) in ('staff', 'gerente', 'owner')
    and not public.senha_inicial_pendente(),
    false
  );
$$;

create or replace function public.tem_permissao(p_perm text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      (select role from public.profiles where id = auth.uid()) = 'owner'
      or exists (
        select 1 from public.staff_permissions
         where user_id = auth.uid() and permissao = p_perm
      )
    )
    and not public.senha_inicial_pendente(),
    false
  );
$$;

create or replace function public.pode_entrar_no_console()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      (select role from public.profiles where id = auth.uid()) = 'owner'
      or exists (select 1 from public.staff_permissions where user_id = auth.uid())
    )
    and not public.senha_inicial_pendente(),
    false
  );
$$;

-- -----------------------------------------------------------------------------
-- admin_senha_alterada — agora CONFERE antes de carimbar. Se o hash continua o
-- mesmo, a senha não mudou e a função recusa (era exatamente por aqui que dava
-- pra desarmar a tela sem trocar nada). Ao confirmar a troca, apaga o hash
-- guardado: a trava é uma porta de mão única.
-- -----------------------------------------------------------------------------
create or replace function public.admin_senha_alterada()
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_uid           uuid := auth.uid();
  v_hash_inicial  text;
  v_hash_atual    text;
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  select p.senha_inicial_hash, u.encrypted_password
    into v_hash_inicial, v_hash_atual
    from public.profiles p
    join auth.users u on u.id = p.id
   where p.id = v_uid;

  if v_hash_inicial is not null and v_hash_atual = v_hash_inicial then
    return jsonb_build_object('ok', false, 'erro', 'a senha ainda é a inicial, escolhe uma nova antes');
  end if;

  update public.profiles
     set senha_alterada_em = now(), senha_inicial_hash = null, updated_at = now()
   where id = v_uid;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'senha_alterada', 'profiles', v_uid::text, '{}'::jsonb);

  return jsonb_build_object('ok', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_minhas_permissoes — o console precisa ENTRAR pra mostrar o formulário de
-- troca, então `console` continua true pro master travado (é a única tela que ele
-- alcança; toda RPC de dado está barrada pelas funções de papel acima). E
-- `senha_trocada` passa a vir da checagem viva do hash, não do carimbo.
-- -----------------------------------------------------------------------------
create or replace function public.admin_minhas_permissoes()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_uid      uuid := auth.uid();
  v_prof     public.profiles;
  v_pendente boolean;
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('console', false);
  end if;

  v_pendente := public.senha_inicial_pendente();

  return jsonb_build_object(
    'console',        public.pode_entrar_no_console() or (v_prof.master and v_pendente),
    'nome',           coalesce(v_prof.full_name, ''),
    'papel',          v_prof.role,
    'master',         v_prof.master,
    'senha_trocada',  not v_pendente,
    'permissoes',     coalesce(
                        (select jsonb_agg(permissao order by permissao)
                           from public.staff_permissions where user_id = v_uid),
                        '[]'::jsonb),
    'tudo',           v_prof.role = 'owner' and not v_pendente
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- registrar_senha_inicial(user_id) — o script de criação chama isto logo depois
-- de criar/repor a senha, pra guardar o hash inicial. O schema `auth` não é
-- exposto pelo PostgREST, então o script (que tem service_role) não consegue ler
-- `encrypted_password` sozinho. Só service_role executa.
-- -----------------------------------------------------------------------------
create or replace function public.registrar_senha_inicial(p_user_id uuid)
returns void
language sql
security definer
set search_path = public, auth, pg_temp
as $$
  update public.profiles p
     set senha_inicial_hash = u.encrypted_password,
         senha_alterada_em  = null,
         updated_at         = now()
    from auth.users u
   where u.id = p.id and p.id = p_user_id;
$$;

revoke all on function public.registrar_senha_inicial(uuid) from public, anon, authenticated;
grant execute on function public.registrar_senha_inicial(uuid) to service_role;
