-- =============================================================================
-- 0018 — Assinatura 'pendente' + trava por delta na permissão 'equipe'
--
-- Duas correções independentes que vieram da mesma varredura de bugs. Ficam no
-- mesmo arquivo porque são pequenas e entram juntas na mesma leva.
--
--  (a) subscriptions.status ganha o valor 'pendente'. A create-checkout-session
--      passou a pré-marcar a assinatura ANTES de mandar a pessoa pro checkout
--      hospedado do Asaas — é essa linha que a delete-account consulta pra não
--      apagar uma conta no exato intervalo entre o cartão ser cobrado e o
--      CHECKOUT_PAID chegar (senão sobra uma recorrência órfã cobrando alguém
--      que já não existe aqui). Sem ampliar o CHECK da 0001, esse insert bate
--      na constraint e a trava nunca protege ninguém.
--
--  (b) admin_definir_permissoes passa a comparar o DELTA da permissão 'equipe'
--      em vez do simples "veio na lista". Ver o bloco lá embaixo.
--
-- Idempotente: dá pra rodar mais de uma vez sem estrago.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- (a) subscriptions.status aceita 'pendente'
--
-- A CHECK da 0001 foi declarada inline na coluna, então quem nomeou foi o
-- Postgres. Em vez de chutar o nome padrão, a gente descobre qual é a CHECK que
-- fala de `status` e derruba essa — assim a migration não quebra se o nome
-- gerado for outro.
--
-- Nada de dado existente muda: 'pendente' é um valor NOVO, os quatro antigos
-- continuam válidos. E ele NÃO concede benefício: getEffectiveSubscription só
-- olha ('ativa','pausada'), então uma linha pendente não vira plano de graça.
-- ---------------------------------------------------------------------------
do $$
declare
  v_nome text;
begin
  select con.conname
    into v_nome
    from pg_constraint con
    join pg_class      rel on rel.oid = con.conrelid
    join pg_namespace  nsp on nsp.oid = rel.relnamespace
   where nsp.nspname = 'public'
     and rel.relname = 'subscriptions'
     and con.contype = 'c'
     and pg_get_constraintdef(con.oid) ilike '%status%'
   limit 1;

  if v_nome is not null then
    execute format('alter table public.subscriptions drop constraint %I', v_nome);
  end if;
end $$;

alter table public.subscriptions
  add constraint subscriptions_status_check
  check (status in ('trial', 'pendente', 'ativa', 'pausada', 'cancelada'));

-- ---------------------------------------------------------------------------
-- (b) admin_definir_permissoes — trava da 'equipe' por DELTA
--
-- A versão da 0017 barrava quando 'equipe' aparecia na lista que chegou. Só que
-- a lista é o estado COMPLETO das permissões da pessoa (o que não vem, sai), e
-- o console manda de volta tudo que está marcado — inclusive os checkboxes que
-- ele mesmo desabilitou. Isso dava dois erros de lado opostos:
--
--   • FALSO POSITIVO — um gestor de equipe (não-owner) mexendo em QUALQUER
--     outra permissão de alguém que JÁ tinha 'equipe' via a lista chegar com
--     'equipe' dentro e levava "só o adm do Casa pode delegar...", sem estar
--     tentando delegar nada. A tela travava por completo pra essa pessoa.
--
--   • FALSO NEGATIVO — TIRAR a 'equipe' de alguém passava batido, porque aí
--     'equipe' justamente NÃO vem na lista. Ou seja: conceder era protegido,
--     revogar não. Um funcionário podia derrubar o gestor de equipe.
--
-- A comparação certa é a mudança: se a pessoa tinha 'equipe' e continua tendo
-- (ou não tinha e segue sem), não há nada a proteger — passa. Se o estado da
-- 'equipe' MUDA, nos dois sentidos, aí sim só o owner.
--
-- O resto da função é idêntico à 0017 (create or replace exige o corpo inteiro).
-- ---------------------------------------------------------------------------
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
