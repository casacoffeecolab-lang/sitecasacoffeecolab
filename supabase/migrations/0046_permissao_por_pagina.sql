-- =============================================================================
-- 0046_permissao_por_pagina.sql — acesso página por página 🔑
--
-- O PEDIDO: "dar permissão customizada pra dar ou não dar acesso a certas
-- páginas e ações".
--
-- O QUE ESTAVA NO CAMINHO: o console tinha 8 permissões pra 19 abas, então
-- várias abas andavam grudadas. Quem recebia 'relatorios' pra ver o que a loja
-- vendeu levava junto a lista de e-mails do rodapé e os pedidos de evento (com
-- nome e telefone de quem pediu). Quem recebia 'resgates' pra entregar
-- recompensa no balcão levava junto os códigos dos presentes vendidos. E três
-- abas (recados, trilha, agenda) eram do dono e ponto: não havia como delegar
-- nem que a casa quisesse, porque as funções delas perguntavam `is_owner()`.
--
-- O QUE ESTE ARQUIVO FAZ:
--   1. Abre o whitelist de permissões (o CHECK fechado da 0017) pra 19 slugs,
--      um por aba, mais as ações.
--   2. Troca a trava de 21 funções: cada uma passa a pedir a permissão DA
--      PRÓPRIA PÁGINA. O corpo delas é idêntico ao que já estava no ar (foi
--      extraído da última versão de cada uma), só a linha da trava muda.
--   3. As três abas do dono deixam de perguntar `is_owner()` e passam a
--      perguntar `tem_permissao(...)`. **O dono não perde nada**: a
--      `tem_permissao` responde verdadeiro pra owner em qualquer slug (0017,
--      reforçada na 0032). O que muda é que agora dá pra DELEGAR.
--   4. BACKFILL: quem já tinha a permissão larga recebe as novas que saíram de
--      dentro dela, uma por uma. Ninguém perde acesso na virada, e daqui pra
--      frente a casa tira o que não quiser dar.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. O whitelist, agora com uma permissão por página.
--    O CHECK nasceu inline na 0017 e foi mexido pela 0043, então o nome dele
--    pode variar: acha pelo conteúdo, não pelo nome.
-- -----------------------------------------------------------------------------
do $$
declare
  v_nome text;
begin
  select con.conname into v_nome
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
   where nsp.nspname = 'public' and rel.relname = 'staff_permissions' and con.contype = 'c'
     and pg_get_constraintdef(con.oid) ilike '%dashboard%'
   limit 1;
  if v_nome is not null then
    execute format('alter table public.staff_permissions drop constraint %I', v_nome);
  end if;

  alter table public.staff_permissions
    add constraint staff_permissions_permissao_check
    check (permissao in (
      -- o dia a dia
      'dashboard', 'pautas',
      -- a loja e o balcão
      'pedidos', 'entregas', 'resgates', 'aniversarios', 'presentes',
      -- a gente
      'usuarios', 'mural', 'equipe',
      -- o que a casa lê
      'relatorios', 'favoritos', 'desejos', 'reposicao', 'lista_espera', 'leads',
      -- o que a casa publica
      'avisos', 'trilha', 'agenda'));
end $$;

-- -----------------------------------------------------------------------------
-- 2. Backfill: ninguém perde o que já tinha.
--    Quem tem a permissão larga ganha, explicitamente, as que saíram de dentro
--    dela. A partir daqui a casa pode tirar uma a uma.
-- -----------------------------------------------------------------------------
insert into public.staff_permissions (user_id, permissao, granted_by)
select sp.user_id, nova.permissao, sp.granted_by
  from public.staff_permissions sp
  join (values
          ('resgates',   'aniversarios'),
          ('resgates',   'presentes'),
          ('usuarios',   'mural'),
          ('relatorios', 'favoritos'),
          ('relatorios', 'desejos'),
          ('relatorios', 'reposicao'),
          ('relatorios', 'lista_espera'),
          ('relatorios', 'leads')
       ) as nova(de, permissao) on nova.de = sp.permissao
on conflict (user_id, permissao) do nothing;

-- -----------------------------------------------------------------------------
-- 3. As 21 funções, com a trava da própria página.
--    Corpo idêntico ao que estava no ar; só a linha do `if not public...` muda.
--    `create or replace` preserva os grants que cada uma já tinha.
-- -----------------------------------------------------------------------------

-- admin_brindes_listar → pede 'aniversarios'
create or replace function public.admin_brindes_listar(
  p_busca  text default null,
  p_status text default null,
  p_limite integer default 200
)
returns table (
  id                uuid,
  criado_em         timestamptz,
  codigo            text,
  situacao          text,
  valido_ate_label  text,
  aniversario       text,
  cliente_nome      text,
  cliente_email     text,
  usado_em          timestamptz,
  usado_por_nome    text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not public.tem_permissao('aniversarios') then
    raise exception 'sem permissão pra ver os brindes';
  end if;

  return query
    select
      b.id,
      b.criado_em,
      b.codigo,
      case when b.status = 'usado' then 'usado'
           when b.valido_ate < v_hoje then 'expirado'
           else 'ativo' end                        as situacao,
      to_char(b.valido_ate, 'DD/MM')               as valido_ate_label,
      to_char(pr.nascimento, 'DD/MM')              as aniversario,
      coalesce(pr.apelido, pr.full_name, '')       as cliente_nome,
      coalesce(u.email::text, '')                  as cliente_email,
      b.usado_em,
      coalesce(baixa.full_name, '')                as usado_por_nome
    from public.brindes_aniversario b
    left join public.profiles pr    on pr.id = b.user_id
    left join auth.users      u     on u.id  = b.user_id
    left join public.profiles baixa on baixa.id = b.usado_por
    where (v_busca is null
           or b.codigo ilike '%' || v_busca || '%'
           or pr.full_name ilike '%' || v_busca || '%'
           or pr.apelido ilike '%' || v_busca || '%')
      and (
        p_status is null
        or (p_status = 'usado'    and b.status = 'usado')
        or (p_status = 'ativo'    and b.status = 'ativo' and b.valido_ate >= v_hoje)
        or (p_status = 'expirado' and b.status = 'ativo' and b.valido_ate <  v_hoje)
      )
    order by b.criado_em desc
    limit greatest(1, least(coalesce(p_limite, 200), 500));
end;
$$;

-- admin_brinde_usar → pede 'aniversarios'
create or replace function public.admin_brinde_usar(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_brinde public.brindes_aniversario;
begin
  if not public.tem_permissao('aniversarios') then
    raise exception 'sem permissão pra dar baixa em brinde';
  end if;

  select * into v_brinde from public.brindes_aniversario where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'brinde não encontrado');
  end if;

  if v_brinde.status = 'usado' then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'usado_em', v_brinde.usado_em);
  end if;

  if v_brinde.valido_ate < v_hoje then
    return jsonb_build_object('ok', false, 'erro',
      'esse código venceu em ' || to_char(v_brinde.valido_ate, 'DD/MM'));
  end if;

  update public.brindes_aniversario
     set status = 'usado', usado_em = now(), usado_por = v_uid
   where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'brinde_aniversario_usado', 'brindes_aniversario', p_id::text,
          jsonb_build_object('codigo', v_brinde.codigo));

  return jsonb_build_object('ok', true, 'usado_em', now());
end;
$$;

-- admin_presentes → pede 'presentes'
create or replace function public.admin_presentes(
  p_busca  text default null,
  p_status text default null,
  p_limite int default 300
)
returns table (
  id                 uuid,
  tier_slug          text,
  tier_nome          text,
  valor_centavos     integer,
  codigo             text,
  status             text,
  comprador_nome     text,
  comprador_email    text,
  resgatado_por_nome text,
  resgatado_em       timestamptz,
  created_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('presentes') then
    raise exception 'sem permissão pra ver os presentes';
  end if;

  return query
    select
      g.id,
      g.tier_slug,
      coalesce(t.nome, g.tier_slug)      as tier_nome,
      g.valor_centavos,
      g.codigo,
      g.status,
      coalesce(pc.full_name, '')         as comprador_nome,
      coalesce(uc.email::text, '')       as comprador_email,
      coalesce(pr.full_name, '')         as resgatado_por_nome,
      g.resgatado_em,
      g.created_at
      from public.gift_subscriptions g
      left join public.tiers      t  on t.slug = g.tier_slug
      left join public.profiles   pc on pc.id  = g.comprador_id
      left join auth.users        uc on uc.id  = g.comprador_id
      left join public.profiles   pr on pr.id  = g.resgatado_por
     where (p_status is null or p_status = '' or g.status = p_status)
       and (
         v_busca is null
         or g.codigo ilike '%' || v_busca || '%'
         or coalesce(pc.full_name, '') ilike '%' || v_busca || '%'
         or coalesce(uc.email::text, '') ilike '%' || v_busca || '%'
         or coalesce(pr.full_name, '') ilike '%' || v_busca || '%'
       )
     order by g.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 2000));
end;
$$;

-- admin_mural_listar → pede 'mural'
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
  if not public.tem_permissao('mural') then
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

-- admin_mural_status → pede 'mural'
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
  if not public.tem_permissao('mural') then
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

-- admin_mural_remover → pede 'mural'
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
  if not public.tem_permissao('mural') then
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

-- admin_cardapio_favoritos → pede 'favoritos'
create or replace function public.admin_cardapio_favoritos()
returns table (
  item_slug  text,
  item_nome  text,
  favoritos  bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('favoritos') then
    raise exception 'sem permissão pra ver os favoritos';
  end if;
  return query
    select
      f.item_slug,
      (select f2.item_nome
         from public.cardapio_favoritos f2
        where f2.item_slug = f.item_slug
        group by f2.item_nome
        order by count(*) desc, f2.item_nome asc
        limit 1)                as item_nome,
      count(*)::bigint          as favoritos
    from public.cardapio_favoritos f
    group by f.item_slug
    order by count(*) desc, item_nome asc;
end;
$$;

-- admin_loja_desejos → pede 'desejos'
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
  if not public.tem_permissao('desejos') then
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

-- admin_avisos_reposicao → pede 'reposicao'
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
  if not public.tem_permissao('reposicao') then
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

-- admin_lista_espera → pede 'lista_espera'
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
  if not public.tem_permissao('lista_espera') then
    raise exception 'sem permissão pra ver a lista de espera';
  end if;
  return query
    select e.id, e.email, e.origem, e.created_at
      from public.lista_espera e
     order by e.created_at desc
     limit greatest(1, least(coalesce(p_limite, 500), 2000));
end;
$$;

-- admin_leads_evento → pede 'leads'
create or replace function public.admin_leads_evento(
  p_busca  text default null,
  p_status text default null,
  p_limite int default 300
)
returns table (
  id              uuid,
  nome            text,
  contato         text,
  email           text,
  tipo            text,
  data_pretendida date,
  pessoas         int,
  mensagem        text,
  origem          text,
  status          text,
  created_at      timestamptz,
  atendido_em     timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('leads') then
    raise exception 'sem permissão pra ver os pedidos de evento';
  end if;

  return query
    select l.id, l.nome, l.contato, l.email, l.tipo, l.data_pretendida, l.pessoas,
           l.mensagem, l.origem, l.status, l.created_at, l.atendido_em
      from public.leads_evento l
     where (p_status is null or p_status = '' or l.status = p_status)
       and (
         v_busca is null
         or l.nome ilike '%' || v_busca || '%'
         or l.contato ilike '%' || v_busca || '%'
         or coalesce(l.email, '') ilike '%' || v_busca || '%'
         or l.tipo ilike '%' || v_busca || '%'
       )
     order by l.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 2000));
end;
$$;

-- admin_lead_evento_status → pede 'leads'
create or replace function public.admin_lead_evento_status(p_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_status text := btrim(coalesce(p_status, ''));
begin
  if not public.tem_permissao('leads') then
    raise exception 'sem permissão pra mexer nos pedidos de evento';
  end if;

  if v_status not in ('novo', 'atendido', 'arquivado') then
    raise exception 'status inválido';
  end if;

  update public.leads_evento
     set status       = v_status,
         atendido_em  = case when v_status = 'novo' then null else now() end,
         atendido_por = case when v_status = 'novo' then null else v_uid end
   where id = p_id;

  if not found then
    raise exception 'pedido não encontrado';
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'lead_evento_status', 'leads_evento', p_id::text,
          jsonb_build_object('status', v_status));

  return jsonb_build_object('ok', true, 'status', v_status);
end;
$$;

-- admin_avisos_listar → pede 'avisos'
create or replace function public.admin_avisos_listar()
returns setof public.avisos_casa
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('avisos') then
    raise exception 'sem permissão';
  end if;
  return query
    select * from public.avisos_casa
    order by ativo desc, prioridade desc, created_at desc;
end;
$$;

-- admin_aviso_salvar → pede 'avisos'
create or replace function public.admin_aviso_salvar(
  p_id         uuid,
  p_texto      text,
  p_emoji      text,
  p_link_url   text,
  p_link_label text,
  p_inicio     timestamptz,
  p_fim        timestamptz,
  p_prioridade integer,
  p_ativo      boolean
)
returns public.avisos_casa
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_texto text := btrim(coalesce(p_texto, ''));
  v_row   public.avisos_casa;
begin
  if not public.tem_permissao('avisos') then
    raise exception 'sem permissão';
  end if;
  if char_length(v_texto) < 1 then
    raise exception 'o recado não pode ser vazio';
  end if;

  if p_id is null then
    insert into public.avisos_casa
      (texto, emoji, link_url, link_label, inicio_em, fim_em, prioridade, ativo, created_by)
    values
      (v_texto, nullif(btrim(coalesce(p_emoji, '')), ''),
       nullif(btrim(coalesce(p_link_url, '')), ''),
       nullif(btrim(coalesce(p_link_label, '')), ''),
       p_inicio, p_fim, coalesce(p_prioridade, 0), coalesce(p_ativo, true), v_uid)
    returning * into v_row;
  else
    update public.avisos_casa set
      texto      = v_texto,
      emoji      = nullif(btrim(coalesce(p_emoji, '')), ''),
      link_url   = nullif(btrim(coalesce(p_link_url, '')), ''),
      link_label = nullif(btrim(coalesce(p_link_label, '')), ''),
      inicio_em  = p_inicio,
      fim_em     = p_fim,
      prioridade = coalesce(p_prioridade, 0),
      ativo      = coalesce(p_ativo, true),
      updated_at = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'recado não encontrado';
    end if;
  end if;

  return v_row;
end;
$$;

-- admin_aviso_remover → pede 'avisos'
create or replace function public.admin_aviso_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('avisos') then
    raise exception 'sem permissão';
  end if;
  delete from public.avisos_casa where id = p_id;
  return true;
end;
$$;

-- admin_trilha_listar → pede 'trilha'
create or replace function public.admin_trilha_listar()
returns setof public.playlists_casa
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('trilha') then
    raise exception 'sem permissão';
  end if;
  return query
    select * from public.playlists_casa
    order by ativo desc, ordem asc, created_at asc;
end;
$$;

-- admin_trilha_salvar → pede 'trilha'
create or replace function public.admin_trilha_salvar(
  p_id       uuid,
  p_nome     text,
  p_clima    text,
  p_url      text,
  p_ordem    integer,
  p_ativo    boolean,
  p_tocando  boolean
)
returns public.playlists_casa
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_url  text := btrim(coalesce(p_url, ''));
  v_toca boolean := coalesce(p_tocando, false);
  v_row  public.playlists_casa;
begin
  if not public.tem_permissao('trilha') then
    raise exception 'sem permissão';
  end if;
  if char_length(v_nome) < 1 then
    raise exception 'dá um nome pra playlist';
  end if;
  if char_length(v_url) < 1 then
    raise exception 'cola o link do Spotify';
  end if;

  -- Só uma toca por vez: zera as outras antes (o unique index reforça).
  if v_toca then
    update public.playlists_casa set tocando = false
     where tocando = true and (p_id is null or id <> p_id);
  end if;

  if p_id is null then
    insert into public.playlists_casa (nome, clima, spotify_url, ordem, ativo, tocando, created_by)
    values (v_nome, nullif(btrim(coalesce(p_clima, '')), ''), v_url,
            coalesce(p_ordem, 0), coalesce(p_ativo, true), v_toca, v_uid)
    returning * into v_row;
  else
    update public.playlists_casa set
      nome        = v_nome,
      clima       = nullif(btrim(coalesce(p_clima, '')), ''),
      spotify_url = v_url,
      ordem       = coalesce(p_ordem, 0),
      ativo       = coalesce(p_ativo, true),
      tocando     = v_toca,
      updated_at  = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'playlist não encontrada';
    end if;
  end if;

  return v_row;
end;
$$;

-- admin_trilha_remover → pede 'trilha'
create or replace function public.admin_trilha_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('trilha') then
    raise exception 'sem permissão';
  end if;
  delete from public.playlists_casa where id = p_id;
  return true;
end;
$$;

-- admin_eventos_listar → pede 'agenda'
create or replace function public.admin_eventos_listar()
returns table (
  id           uuid,
  nome         text,
  descricao    text,
  data         timestamptz,
  local        text,
  vagas        integer,
  ativo        boolean,
  confirmados  bigint,
  created_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('agenda') then
    raise exception 'sem permissão';
  end if;
  return query
    select e.id, e.nome, e.descricao, e.data, e.local, e.vagas, e.ativo,
           (select count(*) from public.event_rsvps r where r.event_id = e.id) as confirmados,
           e.created_at
    from public.events e
    order by e.data desc nulls last, e.created_at desc;
end;
$$;

-- admin_evento_salvar → pede 'agenda'
create or replace function public.admin_evento_salvar(
  p_id        uuid,
  p_nome      text,
  p_descricao text,
  p_data      timestamptz,
  p_local     text,
  p_vagas     integer,
  p_ativo     boolean
)
returns public.events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome text := btrim(coalesce(p_nome, ''));
  v_row  public.events;
begin
  if not public.tem_permissao('agenda') then
    raise exception 'sem permissão';
  end if;
  if char_length(v_nome) < 1 then
    raise exception 'dá um nome pro encontro';
  end if;
  if p_vagas is not null and p_vagas < 0 then
    raise exception 'vagas não pode ser negativo';
  end if;

  if p_id is null then
    insert into public.events (nome, descricao, data, local, vagas, ativo, updated_at)
    values (v_nome, nullif(btrim(coalesce(p_descricao, '')), ''), p_data,
            nullif(btrim(coalesce(p_local, '')), ''), p_vagas,
            coalesce(p_ativo, true), now())
    returning * into v_row;
  else
    update public.events set
      nome       = v_nome,
      descricao  = nullif(btrim(coalesce(p_descricao, '')), ''),
      data       = p_data,
      local      = nullif(btrim(coalesce(p_local, '')), ''),
      vagas      = p_vagas,
      ativo      = coalesce(p_ativo, true),
      updated_at = now()
    where id = p_id
    returning * into v_row;
    if v_row.id is null then
      raise exception 'encontro não encontrado';
    end if;
  end if;

  return v_row;
end;
$$;

-- admin_evento_remover → pede 'agenda'
create or replace function public.admin_evento_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('agenda') then
    raise exception 'sem permissão';
  end if;
  delete from public.events where id = p_id;
  return true;
end;
$$;
