-- =============================================================================
-- 0043_pautas.sql — o quadro de pautas da equipe 📋
--
-- O console sabia tudo sobre o que a CASA vende e nada sobre o que a EQUIPE
-- combina. O que a turma tinha que fazer no dia vivia em bilhete no balcão e em
-- conversa de grupo, que é onde combinado some. Isto é o quadro: a casa escreve
-- a pauta (título + briefing), diz pra quem é e até quando, e quem trabalha
-- move o cartão até "feita".
--
-- PERMISSÃO NOVA ('pautas'), e por que ela precisa existir:
--   O whitelist de permissões do console é fechado por CHECK (0017), então
--   permissão nova pede migration — é exatamente o que este arquivo faz. As
--   outras abas puderam reusar 'relatorios' ou 'resgates' porque eram leitura
--   do mesmo tipo. Aqui não dá: o quadro é o único lugar do console onde quem
--   NÃO cuida do dinheiro nem do cadastro precisa entrar. Enfiar a pauta em
--   'relatorios' daria, junto, a lista de e-mails e o que a casa vendeu.
--
-- QUEM PODE O QUÊ (a régua toda mora no banco, não na tela):
--   • ver o quadro, criar, editar e mover cartão → tem_permissao('pautas');
--   • APAGAR → só quem criou a pauta, ou o adm do Casa. Briefing é combinado
--     escrito: quem escreveu pode voltar atrás, os outros não apagam por cima.
--   Escrita direta pelo client não existe: RLS ligada e nenhuma policy
--   (deny-by-default), tudo pelas RPCs abaixo. É a mesma porta da 0040.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. A permissão nova entra no whitelist fechado da 0017.
--    O CHECK nasceu inline na coluna, então o nome dele é o que o Postgres dá
--    (staff_permissions_permissao_check). Procurar pelo conteúdo em vez de
--    confiar no nome deixa isto seguro mesmo se o banco tiver outro rótulo.
-- -----------------------------------------------------------------------------
do $$
declare
  v_nome text;
begin
  select con.conname into v_nome
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
   where nsp.nspname = 'public'
     and rel.relname = 'staff_permissions'
     and con.contype = 'c'
     and pg_get_constraintdef(con.oid) ilike '%dashboard%'
   limit 1;

  if v_nome is not null then
    execute format('alter table public.staff_permissions drop constraint %I', v_nome);
  end if;

  alter table public.staff_permissions
    add constraint staff_permissions_permissao_check
    check (permissao in (
      'dashboard', 'pedidos', 'entregas', 'resgates',
      'usuarios', 'relatorios', 'equipe', 'pautas'));
end $$;

-- -----------------------------------------------------------------------------
-- 2. A tabela.
--    `atribuido_a` nulo = pauta da casa inteira (o recado que vale pra todo
--    mundo, tipo "sexta a gente abre 7h"). ON DELETE SET NULL nos três vínculos
--    de pessoa: conta que sai da casa não leva a pauta junto, e o histórico do
--    que foi combinado continua de pé.
-- -----------------------------------------------------------------------------
create table if not exists public.pautas (
  id            uuid primary key default gen_random_uuid(),
  titulo        text not null check (char_length(btrim(titulo)) between 1 and 120),
  briefing      text check (briefing is null or char_length(briefing) <= 4000),
  atribuido_a   uuid references public.profiles (id) on delete set null,
  prazo         date,
  prioridade    text not null default 'normal' check (prioridade in ('baixa', 'normal', 'alta')),
  status        text not null default 'aberta' check (status in ('aberta', 'fazendo', 'feita')),
  criado_por    uuid references public.profiles (id) on delete set null,
  concluida_em  timestamptz,
  concluida_por uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_pautas_status    on public.pautas (status, created_at desc);
create index if not exists idx_pautas_atribuido on public.pautas (atribuido_a, status);

-- Deny-by-default: RLS ligada e NENHUMA policy. O client não lê nem escreve
-- direto; quem fala com a tabela são as funções abaixo, que checam a permissão.
alter table public.pautas enable row level security;

-- -----------------------------------------------------------------------------
-- 3. admin_pautas_listar — o quadro inteiro.
--    Devolve o nome de quem recebeu, de quem escreveu e de quem concluiu, pra a
--    tela não precisar de uma segunda consulta em `profiles` (que a RLS de lá
--    nem permitiria pra terceiros).
-- -----------------------------------------------------------------------------
create or replace function public.admin_pautas_listar(
  p_status  text default null,
  p_de_quem uuid default null,
  p_busca   text default null,
  p_limite  int  default 300
)
returns table (
  id                 uuid,
  titulo             text,
  briefing           text,
  atribuido_a        uuid,
  atribuido_nome     text,
  prazo              date,
  prioridade         text,
  status             text,
  criado_por         uuid,
  criado_por_nome    text,
  concluida_em       timestamptz,
  concluida_por_nome text,
  created_at         timestamptz,
  updated_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra ver as pautas';
  end if;

  return query
    select
      p.id,
      p.titulo,
      p.briefing,
      p.atribuido_a,
      coalesce(pa.full_name, '')  as atribuido_nome,
      p.prazo,
      p.prioridade,
      p.status,
      p.criado_por,
      coalesce(pc.full_name, '')  as criado_por_nome,
      p.concluida_em,
      coalesce(pf.full_name, '')  as concluida_por_nome,
      p.created_at,
      p.updated_at
      from public.pautas p
      left join public.profiles pa on pa.id = p.atribuido_a
      left join public.profiles pc on pc.id = p.criado_por
      left join public.profiles pf on pf.id = p.concluida_por
     where (p_status is null or p_status = '' or p.status = p_status)
       and (p_de_quem is null or p.atribuido_a = p_de_quem)
       and (
         v_busca is null
         or p.titulo ilike '%' || v_busca || '%'
         or coalesce(p.briefing, '') ilike '%' || v_busca || '%'
         or coalesce(pa.full_name, '') ilike '%' || v_busca || '%'
       )
     order by
       case p.status when 'fazendo' then 0 when 'aberta' then 1 else 2 end,
       case p.prioridade when 'alta' then 0 when 'normal' then 1 else 2 end,
       p.prazo asc nulls last,
       p.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 1000));
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. admin_pautas_equipe — quem pode receber uma pauta.
--    Existe pra o campo "pra quem" do formulário. NÃO é a `admin_equipe`: aquela
--    pede a permissão 'equipe' (quem manda no acesso dos outros) e devolve
--    e-mail. Aqui basta id + nome, e a régua é a mesma do quadro.
-- -----------------------------------------------------------------------------
create or replace function public.admin_pautas_equipe()
returns table (id uuid, nome text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra ver a equipe';
  end if;

  return query
    select p.id, coalesce(nullif(btrim(p.full_name), ''), 'sem nome') as nome
      from public.profiles p
     where p.role = 'owner'
        or exists (select 1 from public.staff_permissions sp where sp.user_id = p.id)
     order by p.role = 'owner' desc, p.full_name nulls last;
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. admin_pauta_salvar — cria (p_id null) ou edita.
--    O status NÃO vem por aqui: quem move cartão é a `admin_pauta_status`, pra
--    "salvar uma edição" nunca desfazer sem querer o andamento que alguém deu.
-- -----------------------------------------------------------------------------
create or replace function public.admin_pauta_salvar(
  p_id          uuid,
  p_titulo      text,
  p_briefing    text,
  p_atribuido_a uuid,
  p_prazo       date,
  p_prioridade  text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_titulo text := btrim(coalesce(p_titulo, ''));
  v_prio   text := coalesce(nullif(btrim(coalesce(p_prioridade, '')), ''), 'normal');
  v_id     uuid;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;
  if char_length(v_titulo) < 1 or char_length(v_titulo) > 120 then
    return jsonb_build_object('ok', false, 'erro', 'a pauta precisa de um título de até 120 letras');
  end if;
  if v_prio not in ('baixa', 'normal', 'alta') then
    v_prio := 'normal';
  end if;
  -- Só dá pra atribuir a quem entra no console: pauta pra cliente não existe.
  if p_atribuido_a is not null
     and not exists (
       select 1 from public.profiles p
        where p.id = p_atribuido_a
          and (p.role = 'owner'
               or exists (select 1 from public.staff_permissions sp where sp.user_id = p.id))
     ) then
    return jsonb_build_object('ok', false, 'erro', 'essa pessoa não é da equipe do console');
  end if;

  if p_id is null then
    insert into public.pautas (titulo, briefing, atribuido_a, prazo, prioridade, criado_por)
    values (v_titulo, nullif(btrim(coalesce(p_briefing, '')), ''), p_atribuido_a, p_prazo, v_prio, v_uid)
    returning id into v_id;
  else
    update public.pautas
       set titulo      = v_titulo,
           briefing    = nullif(btrim(coalesce(p_briefing, '')), ''),
           atribuido_a = p_atribuido_a,
           prazo       = p_prazo,
           prioridade  = v_prio,
           updated_at  = now()
     where id = p_id
    returning id into v_id;

    if v_id is null then
      return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
    end if;
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, case when p_id is null then 'pauta_criada' else 'pauta_editada' end,
          'pautas', v_id::text, jsonb_build_object('titulo', v_titulo));

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. admin_pauta_status — mover o cartão.
--    Idempotente: mandar o status que já está não é erro. Ao virar 'feita'
--    carimba quem concluiu e quando; ao voltar, limpa o carimbo (senão o quadro
--    contaria como entregue algo que voltou pra fila).
-- -----------------------------------------------------------------------------
create or replace function public.admin_pauta_status(p_id uuid, p_status text)
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
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;
  if v_novo not in ('aberta', 'fazendo', 'feita') then
    return jsonb_build_object('ok', false, 'erro', 'esse estado não existe no quadro');
  end if;

  update public.pautas
     set status        = v_novo,
         concluida_em  = case when v_novo = 'feita' then now() else null end,
         concluida_por = case when v_novo = 'feita' then v_uid else null end,
         updated_at    = now()
   where id = p_id
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;

  return jsonb_build_object('ok', true, 'status', v_novo);
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. admin_pauta_remover — só quem escreveu, ou o adm do Casa.
--    Quem não pode apagar ainda pode marcar como feita: nada fica preso.
-- -----------------------------------------------------------------------------
create or replace function public.admin_pauta_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_pauta public.pautas;
begin
  if not public.tem_permissao('pautas') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;

  select * into v_pauta from public.pautas where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  if not (public.is_owner() or v_pauta.criado_por = v_uid) then
    return jsonb_build_object('ok', false, 'erro',
      'essa pauta é de quem escreveu. tu pode marcar como feita, apagar só quem escreveu ou o adm do Casa');
  end if;

  delete from public.pautas where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'pauta_removida', 'pautas', p_id::text,
          jsonb_build_object('titulo', v_pauta.titulo));

  return jsonb_build_object('ok', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. Permissões das funções. Deslogado (anon) não alcança nada.
-- -----------------------------------------------------------------------------
revoke all on function public.admin_pautas_listar(text, uuid, text, int)          from public, anon;
revoke all on function public.admin_pautas_equipe()                               from public, anon;
revoke all on function public.admin_pauta_salvar(uuid, text, text, uuid, date, text) from public, anon;
revoke all on function public.admin_pauta_status(uuid, text)                      from public, anon;
revoke all on function public.admin_pauta_remover(uuid)                           from public, anon;

grant execute on function public.admin_pautas_listar(text, uuid, text, int)          to authenticated;
grant execute on function public.admin_pautas_equipe()                               to authenticated;
grant execute on function public.admin_pauta_salvar(uuid, text, text, uuid, date, text) to authenticated;
grant execute on function public.admin_pauta_status(uuid, text)                      to authenticated;
grant execute on function public.admin_pauta_remover(uuid)                           to authenticated;
