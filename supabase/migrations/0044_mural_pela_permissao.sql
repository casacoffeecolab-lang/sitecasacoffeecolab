-- =============================================================================
-- 0044_mural_pela_permissao.sql — a aba do mural passa a valer pra equipe 🧹
--
-- O BURACO: a aba "mural" do console é a única que escreve DIRETO pela RLS, e as
-- policies da 0020 falam em `is_staff()`, que é `profiles.role in (staff,
-- gerente, owner)`. Só que o console NUNCA troca o papel de ninguém: a
-- `admin_definir_permissoes` (0017) grava em `staff_permissions` e sai, de
-- propósito — o princípio da casa é "cargo não abre porta, permissão abre".
--
-- Resultado prático: quem recebe a permissão 'usuarios' pelo console vê a aba,
-- lê os recados aprovados (essa leitura é pública) e **não consegue nada mais**:
-- os escondidos não aparecem, "esconder" e "apagar" batem na RLS. A aba
-- funcionava só pro adm do Casa, que é o único com role='owner'. Isso não
-- aparecia enquanto a casa era de uma pessoa só.
--
-- A CORREÇÃO, na porta certa: a moderação passa a ser três funções gated por
-- `tem_permissao('usuarios')`, como TODAS as outras abas. Nada de promover
-- ninguém a staff pra destravar — promover abriria junto, pela RLS, toda tabela
-- que confia em `is_staff()` (pedidos, resgates, brindes), e permissão de
-- moderar mural não é permissão de ler o caixa.
--
-- O que NÃO muda: as policies da 0020 continuam de pé (o autor segue apagando o
-- próprio recado no /o-casa, o staff de verdade segue enxergando tudo), e a
-- trigger da 0036 continua impedindo QUALQUER UM de reescrever `texto`,
-- `autor_nome` e `user_id` — daqui também. Dá pra esconder e apagar, nunca pra
-- pôr na parede uma frase que a pessoa não escreveu.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (CREATE OR REPLACE).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- admin_mural_listar — a parede inteira, inclusive o que está escondido.
-- -----------------------------------------------------------------------------
create or replace function public.admin_mural_listar(
  p_busca  text default null,
  p_status text default null,
  p_limite int  default 300
)
returns table (
  id         uuid,
  autor_nome text,
  texto      text,
  status     text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('usuarios') then
    raise exception 'sem permissão pra cuidar do mural';
  end if;

  return query
    select m.id, coalesce(m.autor_nome, ''), m.texto, m.status, m.created_at
      from public.mural_notes m
     where (p_status is null or p_status = '' or m.status = p_status)
       and (
         v_busca is null
         or m.texto ilike '%' || v_busca || '%'
         or coalesce(m.autor_nome, '') ilike '%' || v_busca || '%'
       )
     order by m.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 1000));
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_mural_status — esconder e devolver pra parede. Idempotente.
-- Mexe SÓ no status: o texto e o nome de quem escreveu não passam por aqui, e a
-- trigger da 0036 barraria de qualquer jeito.
-- -----------------------------------------------------------------------------
create or replace function public.admin_mural_status(p_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_novo text := btrim(coalesce(p_status, ''));
  v_id   uuid;
begin
  if not public.tem_permissao('usuarios') then
    raise exception 'sem permissão pra cuidar do mural';
  end if;
  if v_novo not in ('aprovado', 'oculto') then
    return jsonb_build_object('ok', false, 'erro', 'esse estado não existe no mural');
  end if;

  update public.mural_notes set status = v_novo where id = p_id
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'esse recado não existe mais');
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'mural_status', 'mural_notes', p_id::text,
          jsonb_build_object('status', v_novo));

  return jsonb_build_object('ok', true, 'status', v_novo);
end;
$$;

-- -----------------------------------------------------------------------------
-- admin_mural_remover — o caminho sem volta, registrado no audit_log.
-- Guarda o texto no registro: apagar da parede não pode apagar também a memória
-- de que alguém apagou, e o que era.
-- -----------------------------------------------------------------------------
create or replace function public.admin_mural_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_nota public.mural_notes;
begin
  if not public.tem_permissao('usuarios') then
    raise exception 'sem permissão pra cuidar do mural';
  end if;

  select * into v_nota from public.mural_notes where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  delete from public.mural_notes where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'mural_removido', 'mural_notes', p_id::text,
          jsonb_build_object('autor_nome', coalesce(v_nota.autor_nome, ''),
                             'texto', v_nota.texto));

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_mural_listar(text, text, int) from public, anon;
revoke all on function public.admin_mural_status(uuid, text)      from public, anon;
revoke all on function public.admin_mural_remover(uuid)           from public, anon;

grant execute on function public.admin_mural_listar(text, text, int) to authenticated;
grant execute on function public.admin_mural_status(uuid, text)      to authenticated;
grant execute on function public.admin_mural_remover(uuid)           to authenticated;
