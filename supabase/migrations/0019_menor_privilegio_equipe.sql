-- =============================================================================
-- 0019 — Menor privilégio na delegação de permissões da equipe
--
-- Fecha uma escalada de privilégio no admin_definir_permissoes (0017/0018): um
-- gestor de equipe (não-owner, com a permissão 'equipe') conseguia CONCEDER a
-- terceiros permissões que ele mesmo NÃO tinha — inclusive 'usuarios' (todo o
-- cadastro/PII) e 'relatorios' (financeiro) — e depois logar na conta que ele
-- mesmo elevou. As travas anteriores só cobriam: ator tem 'equipe', alvo não é
-- owner/master, e mudança na permissão 'equipe' (só owner). Faltava exigir que o
-- ator já possua a permissão que está concedendo.
--
-- REGRA NOVA: quem não é owner só pode CONCEDER permissões que ele mesmo tem. A
-- checagem é sobre o DELTA (o que está sendo ADICIONADO): p_permissoes é o estado
-- COMPLETO desejado, então uma permissão que o alvo JÁ tinha e continua tendo não
-- conta como concessão nova (senão um gestor sem 'relatorios' não conseguiria
-- mexer em nada de quem já tem 'relatorios'). 'equipe' segue governada só pela
-- trava por delta (só owner concede/revoga). Owner (inclui o master) concede tudo.
--
-- create or replace exige o corpo INTEIRO — o resto é idêntico à 0018.
-- Idempotente. Append-only: não edita a 0018.
-- =============================================================================
create or replace function public.admin_definir_permissoes(
  p_user_id     uuid,
  p_permissoes  text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid          uuid := auth.uid();
  v_alvo         public.profiles;
  v_lista        text[] := coalesce(p_permissoes, '{}');
  v_tinha_equipe boolean;
  v_tera_equipe  boolean;
begin
  if not public.tem_permissao('equipe') then
    raise exception 'sem permissão pra mexer na equipe';
  end if;

  if p_user_id = v_uid then
    raise exception 'não dá pra mudar as próprias permissões';
  end if;

  select * into v_alvo from public.profiles where id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'pessoa não encontrada');
  end if;

  if v_alvo.role = 'owner' or v_alvo.master then
    return jsonb_build_object('ok', false, 'erro', 'o adm do Casa já tem tudo — não há o que ajustar aqui');
  end if;

  -- A trava por delta: compara o que a pessoa TEM com o que vai ficar.
  v_tinha_equipe := exists (
    select 1 from public.staff_permissions
     where user_id = p_user_id and permissao = 'equipe'
  );
  v_tera_equipe := 'equipe' = any (v_lista);

  if v_tinha_equipe is distinct from v_tera_equipe and not public.is_owner() then
    return jsonb_build_object(
      'ok', false,
      'erro', 'só o adm do Casa mexe em quem cuida da equipe'
    );
  end if;

  -- MENOR PRIVILÉGIO: quem não é owner só CONCEDE o que ele mesmo tem. Barra se
  -- alguma permissão da lista (a) não é 'equipe' (já tratada acima), (b) o alvo
  -- ainda NÃO tinha (é concessão nova) e (c) o ATOR não possui. Assim, adicionar
  -- 'usuarios'/'relatorios'/etc que o gestor não tem é recusado; manter o que o
  -- alvo já tinha, ou revogar, segue passando.
  if not public.is_owner() then
    if exists (
      select 1
        from unnest(v_lista) as perm
       where perm <> 'equipe'
         and not exists (
               select 1 from public.staff_permissions
                where user_id = p_user_id and permissao = perm)
         and not exists (
               select 1 from public.staff_permissions
                where user_id = v_uid and permissao = perm)
    ) then
      return jsonb_build_object(
        'ok', false,
        'erro', 'tu só pode dar acessos que tu mesmo tem'
      );
    end if;
  end if;

  delete from public.staff_permissions
   where user_id = p_user_id
     and not (permissao = any (v_lista));

  insert into public.staff_permissions (user_id, permissao, granted_by)
  select p_user_id, perm, v_uid from unnest(v_lista) as perm
  on conflict (user_id, permissao) do nothing;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'permissoes_definidas', 'staff_permissions', p_user_id::text,
          jsonb_build_object('permissoes', to_jsonb(v_lista)));

  return jsonb_build_object('ok', true, 'permissoes', to_jsonb(v_lista));
end;
$$;
