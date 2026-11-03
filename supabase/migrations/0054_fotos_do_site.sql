-- =============================================================================
-- 0054_fotos_do_site — a casa troca as fotos do site sem mexer no código
--
-- Até aqui toda foto do site era um `<img src="/fotos/…">` escrito no HTML, e
-- trocar qualquer uma delas era tarefa de programador: subir arquivo no repo,
-- mudar o caminho, buildar, deployar. Um café troca de foto quando a estação
-- muda, quando a fachada ganha toldo novo, quando o prato sai bonito — isso não
-- pode passar por deploy.
--
-- O DESENHO, em três peças:
--   • uma GALERIA (`fotos_galeria`) das fotos que a casa já subiu, que é o
--     acervo: subiu uma vez, usa em quantos lugares quiser, e ela continua ali
--     pra usar de novo no mês que vem;
--   • um LUGAR (`site_fotos`), uma linha por posição do site que hoje mostra
--     foto ("o 2º slide do hero da home", "o card do Brunch"), apontando pra
--     uma foto da galeria;
--   • a lista DOS LUGARES não mora aqui, e isso é decisão. Ela é um fato sobre
--     o HTML (que `<img>` existe em que página), então mora ao lado dele, no
--     `src/fotos-do-site.js`, que o site e o console importam. Duplicar a lista
--     no banco criaria a mesma divergência que o CLAUDE.md já conta na 0047: a
--     lista que a tela mostra deixando de ser a que vale.
--
-- O QUE SE GUARDA É O CAMINHO, NUNCA A URL. Se a coluna guardasse URL, alguém
-- com a permissão de mexer poderia apontar a foto do hero pra um servidor de
-- fora (um contador de acesso disfarçado de foto, uma imagem que troca depois
-- de aprovada). Guardando só o caminho do objeto no nosso bucket, quem monta o
-- endereço é o `getPublicUrl` do client, com o host vindo do env — não há URL
-- forjável passando por aqui.
--
-- Escrita: as RPCs abaixo, gated por `tem_permissao`. O ARQUIVO em si sobe pelo
-- Storage (não existe RPC que carregue bytes), e ali a tranca é a policy do
-- `storage.objects`, que pergunta pela PERMISSÃO e não pelo papel — é a lição
-- da 0044: `is_staff()` responde falso pra quem recebeu acesso pelo console, e
-- uma aba nova que confie nele nasce quebrada pra todo mundo menos o dono.
-- =============================================================================


-- =============================================================================
-- 1. O bucket
-- -----------------------------------------------------------------------------
-- Público na leitura, como o `avatares` da 0015 e pelo mesmo motivo: foto de
-- site aparece na tela o tempo todo e signed URL expira. 8 MB porque aqui entra
-- foto de hero em tela cheia, que é bem maior que um avatar; o limite mora no
-- BUCKET, não só no JS (confiança zero no client).
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'fotos-site',
  'fotos-site',
  true,
  8388608, -- 8 MB
  array['image/jpeg', 'image/png', 'image/webp', 'image/avif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Leitura pública: são as fotos do site, elas existem pra ser vistas.
drop policy if exists "fotos do site: qualquer um vê" on storage.objects;
create policy "fotos do site: qualquer um vê"
  on storage.objects for select
  using (bucket_id = 'fotos-site');

-- Escrita: quem tem a permissão de MEXER nas fotos. Note que quem pode subir
-- não pode apagar: apagar é do `arrumar`, porque some de todo lugar que usa.
drop policy if exists "fotos do site: quem mexe sobe" on storage.objects;
create policy "fotos do site: quem mexe sobe"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos-site' and public.tem_permissao('fotos.mexer'));

drop policy if exists "fotos do site: quem mexe troca" on storage.objects;
create policy "fotos do site: quem mexe troca"
  on storage.objects for update to authenticated
  using (bucket_id = 'fotos-site' and public.tem_permissao('fotos.mexer'))
  with check (bucket_id = 'fotos-site' and public.tem_permissao('fotos.mexer'));

drop policy if exists "fotos do site: quem arruma apaga" on storage.objects;
create policy "fotos do site: quem arruma apaga"
  on storage.objects for delete to authenticated
  using (bucket_id = 'fotos-site' and public.tem_permissao('fotos.arrumar'));


-- =============================================================================
-- 2. As duas tabelas
-- -----------------------------------------------------------------------------
-- As duas sobem deny-by-default: RLS ligada e NENHUMA policy. Nem anon nem
-- logado alcança pelo PostgREST; as portas são as funções da seção 4.
-- =============================================================================

-- O acervo. Uma linha por arquivo que a casa subiu.
create table if not exists public.fotos_galeria (
  id         uuid primary key default gen_random_uuid(),
  caminho    text not null unique,          -- o objeto no bucket, ex.: 2026/09/fachada-a1b2c3.jpg
  nome       text not null,                 -- como a casa chama essa foto
  alt        text,                           -- a descrição pra quem não enxerga
  bytes      bigint,
  tipo       text,
  enviada_em timestamptz not null default now(),
  enviada_por uuid references auth.users (id) on delete set null
);
create index if not exists idx_fotos_galeria_data on public.fotos_galeria (enviada_em desc);
alter table public.fotos_galeria enable row level security;

-- Os lugares ocupados. Uma linha SÓ pra posição que a casa trocou: lugar que
-- nunca foi mexido não tem linha, e o site mostra o que está no HTML. É o que
-- faz o "voltar ao padrão" ser um DELETE, e não um segundo caminho guardado.
create table if not exists public.site_fotos (
  slot           text primary key,
  caminho        text not null,
  alt            text,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references auth.users (id) on delete set null
);
alter table public.site_fotos enable row level security;


-- =============================================================================
-- 3. O catálogo de permissão (0047) ganha a página "as fotos"
-- -----------------------------------------------------------------------------
-- Permissão nova é INSERT no catálogo, não `alter constraint` — é o que a 0047
-- comprou. A página entra na seção "a casa", ao lado do recado do topo e da
-- trilha: é tudo o que a casa PUBLICA.
--
-- As três ações existem de verdade, e a linha entre elas é o estrago:
--   ver     — enxergar a galeria e saber que foto está em que lugar;
--   mexer   — subir foto nova, trocar a de um lugar e voltar um lugar pro
--             padrão (o do HTML). Nada disso perde arquivo;
--   arrumar — apagar uma foto do acervo, que some do Storage pra sempre.
--
-- SEM BACKFILL, de propósito. Estas são as fotos da fachada da casa na
-- internet: quem trocar uma delas troca a cara do site pra todo mundo na hora.
-- É poder novo, e poder novo se dá na mão (a mesma régua que a 0047 usou pro
-- `arrumar` de pedido, ponto, presente e assinatura). O dono já alcança tudo
-- pelo `role = 'owner'`, então ninguém fica sem porta enquanto isso.
-- =============================================================================

insert into public.permissao_paginas (slug, secao_slug, rotulo, descricao, aba, ordem) values
  ('fotos', 'casa', 'as fotos', 'as fotos que o site mostra, e o acervo delas', 'fotos', 50)
on conflict (slug) do update
  set secao_slug = excluded.secao_slug, rotulo = excluded.rotulo,
      descricao  = excluded.descricao,  aba    = excluded.aba, ordem = excluded.ordem;

insert into public.permissoes (slug, pagina_slug, acao, nivel, rotulo, descricao) values
  ('fotos.ver',     'fotos', 'ver',     1, 'enxergar', 'ver o acervo de fotos e que foto está em cada lugar do site'),
  ('fotos.mexer',   'fotos', 'mexer',   2, 'mexer',    'subir foto nova, trocar a foto de um lugar e voltar um lugar pro padrão'),
  ('fotos.arrumar', 'fotos', 'arrumar', 3, 'arrumar',  'apagar uma foto do acervo de vez')
on conflict (slug) do update
  set pagina_slug = excluded.pagina_slug, acao = excluded.acao, nivel = excluded.nivel,
      rotulo = excluded.rotulo, descricao = excluded.descricao;


-- =============================================================================
-- 4. As portas
-- =============================================================================

-- Aparador de caminho. O caminho é gerado pelo console, mas ele chega aqui pelo
-- corpo de uma chamada como qualquer outra coisa vinda de fora: só passa o que
-- parece caminho de objeto nosso, e '..' não passa nunca.
create or replace function public.foto_caminho_ok(p_valor text)
returns boolean
language sql
immutable
as $$
  select coalesce(
    p_valor ~ '^[a-z0-9][a-z0-9._/-]{2,180}$'
    and p_valor not like '%..%'
    and p_valor not like '%//%',
    false
  );
$$;

-- ---------------------------------------------------------------------------
-- A leitura do SITE. Pública (é o site aberto), e devolve só o que a página
-- precisa: o lugar, o caminho e a descrição. Quem trocou e quando fica de fora
-- — isso é da casa, não de quem visita.
-- ---------------------------------------------------------------------------
create or replace function public.fotos_do_site()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(jsonb_build_object('slot', f.slot, 'caminho', f.caminho, 'alt', f.alt)
              order by f.slot),
    '[]'::jsonb
  )
  from public.site_fotos f;
$$;

-- ---------------------------------------------------------------------------
-- A leitura do CONSOLE: o acervo inteiro mais os lugares já ocupados, numa
-- viagem só. `returns jsonb` e não `returns table` pelo mesmo motivo da 0045:
-- leitura composta em `returns table` é uma dúzia de colunas declaradas pra
-- errar, e foi um erro desses (varchar declarado como text) que deixou cinco
-- abas mortas da 0017 até a 0042.
-- ---------------------------------------------------------------------------
create or replace function public.admin_fotos_painel()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_galeria jsonb;
  v_lugares jsonb;
begin
  if not public.tem_permissao('fotos.ver') then
    raise exception 'sem permissão pra ver as fotos do site';
  end if;

  select coalesce(jsonb_agg(g order by g->>'enviada_em' desc), '[]'::jsonb)
    into v_galeria
    from (
      select jsonb_build_object(
               'id', f.id,
               'caminho', f.caminho,
               'nome', f.nome,
               'alt', f.alt,
               'bytes', f.bytes,
               'tipo', f.tipo,
               'enviada_em', f.enviada_em,
               'quem', p.full_name,
               'usos', (select count(*) from public.site_fotos s where s.caminho = f.caminho)
             ) as g
        from public.fotos_galeria f
        left join public.profiles p on p.id = f.enviada_por
    ) t;

  select coalesce(jsonb_agg(l order by l->>'slot'), '[]'::jsonb)
    into v_lugares
    from (
      select jsonb_build_object(
               'slot', s.slot,
               'caminho', s.caminho,
               'alt', s.alt,
               'atualizado_em', s.atualizado_em,
               'quem', p.full_name
             ) as l
        from public.site_fotos s
        left join public.profiles p on p.id = s.atualizado_por
    ) t;

  return jsonb_build_object('galeria', v_galeria, 'lugares', v_lugares);
end;
$$;

-- ---------------------------------------------------------------------------
-- Registrar no acervo a foto que ACABOU de subir pro Storage. O arquivo já
-- passou pela policy do bucket; aqui entra a ficha dele.
-- ---------------------------------------------------------------------------
create or replace function public.admin_foto_registrar(
  p_caminho text,
  p_nome    text,
  p_alt     text default null,
  p_bytes   bigint default null,
  p_tipo    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_nome text := nullif(btrim(coalesce(p_nome, '')), '');
  v_alt  text := nullif(btrim(coalesce(p_alt, '')), '');
  v_id   uuid;
begin
  if not public.tem_permissao('fotos.mexer') then
    raise exception 'sem permissão pra subir foto do site';
  end if;
  if not public.foto_caminho_ok(p_caminho) then
    raise exception 'esse caminho de arquivo não serve';
  end if;
  if v_nome is null then
    raise exception 'dá um nome pra foto, pra achar ela depois';
  end if;

  insert into public.fotos_galeria (caminho, nome, alt, bytes, tipo, enviada_por)
  values (p_caminho, left(v_nome, 80), left(v_alt, 220), p_bytes, left(nullif(btrim(coalesce(p_tipo, '')), ''), 40), v_uid)
  on conflict (caminho) do update
    set nome = excluded.nome, alt = excluded.alt
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Trocar a foto de UM lugar do site. O lugar chega como slug (o `slot` do
-- `fotos-do-site.js`) e a foto como id da galeria: assim não há caminho vindo
-- do client, só um id de linha que já existe.
-- ---------------------------------------------------------------------------
create or replace function public.admin_foto_definir(p_slot text, p_foto_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_slot    text := lower(btrim(coalesce(p_slot, '')));
  v_caminho text;
  v_alt     text;
  v_nome    text;
begin
  if not public.tem_permissao('fotos.mexer') then
    raise exception 'sem permissão pra trocar as fotos do site';
  end if;
  if v_slot !~ '^[a-z0-9][a-z0-9-]{1,59}$' then
    raise exception 'esse lugar do site não existe';
  end if;

  select caminho, alt, nome into v_caminho, v_alt, v_nome
    from public.fotos_galeria where id = p_foto_id;
  if v_caminho is null then
    raise exception 'essa foto não está mais no acervo';
  end if;

  insert into public.site_fotos (slot, caminho, alt, atualizado_em, atualizado_por)
  values (v_slot, v_caminho, v_alt, now(), v_uid)
  on conflict (slot) do update
    set caminho = excluded.caminho, alt = excluded.alt,
        atualizado_em = now(), atualizado_por = excluded.atualizado_por;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'foto_do_site_trocada', 'site_fotos', v_slot,
          jsonb_build_object('foto', v_nome, 'caminho', v_caminho));

  return jsonb_build_object('ok', true, 'slot', v_slot, 'caminho', v_caminho, 'alt', v_alt);
end;
$$;

-- ---------------------------------------------------------------------------
-- Voltar um lugar pro padrão: apaga a linha, e o site volta a mostrar a foto
-- que está no HTML. Nenhum arquivo é perdido.
-- ---------------------------------------------------------------------------
create or replace function public.admin_foto_soltar(p_slot text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_slot text := lower(btrim(coalesce(p_slot, '')));
  v_tinha text;
begin
  if not public.tem_permissao('fotos.mexer') then
    raise exception 'sem permissão pra trocar as fotos do site';
  end if;

  delete from public.site_fotos where slot = v_slot returning caminho into v_tinha;
  if v_tinha is null then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'foto_do_site_solta', 'site_fotos', v_slot,
          jsonb_build_object('caminho', v_tinha));

  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Apagar uma foto do acervo. Recusa enquanto ela estiver em algum lugar do
-- site: apagar por baixo deixaria o lugar apontando pra um arquivo que não
-- existe, e o site mostraria um quadro quebrado sem ninguém entender por quê.
-- Devolve o caminho pro console apagar o arquivo no Storage em seguida.
-- ---------------------------------------------------------------------------
create or replace function public.admin_foto_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_caminho text;
  v_nome    text;
  v_usos    integer;
begin
  if not public.tem_permissao('fotos.arrumar') then
    raise exception 'sem permissão pra apagar foto do acervo';
  end if;

  select caminho, nome into v_caminho, v_nome from public.fotos_galeria where id = p_id;
  if v_caminho is null then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  select count(*) into v_usos from public.site_fotos where caminho = v_caminho;
  if v_usos > 0 then
    raise exception 'essa foto está em % lugar(es) do site. tira ela de lá primeiro', v_usos;
  end if;

  delete from public.fotos_galeria where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'foto_do_acervo_apagada', 'fotos_galeria', p_id::text,
          jsonb_build_object('foto', v_nome, 'caminho', v_caminho));

  return jsonb_build_object('ok', true, 'caminho', v_caminho);
end;
$$;


-- =============================================================================
-- 5. Quem pode chamar o quê
-- -----------------------------------------------------------------------------
-- A leitura do site é a única aberta a `anon` (ela É o site). As `admin_*`
-- ficam só pra sessão logada, e lá dentro cada uma pergunta pela permissão.
-- =============================================================================

revoke all on function public.foto_caminho_ok(text) from public, anon, authenticated;

revoke all on function public.fotos_do_site() from public;
grant execute on function public.fotos_do_site() to anon, authenticated;

revoke all on function public.admin_fotos_painel() from public, anon;
grant execute on function public.admin_fotos_painel() to authenticated;

revoke all on function public.admin_foto_registrar(text, text, text, bigint, text) from public, anon;
grant execute on function public.admin_foto_registrar(text, text, text, bigint, text) to authenticated;

revoke all on function public.admin_foto_definir(text, uuid) from public, anon;
grant execute on function public.admin_foto_definir(text, uuid) to authenticated;

revoke all on function public.admin_foto_soltar(text) from public, anon;
grant execute on function public.admin_foto_soltar(text) to authenticated;

revoke all on function public.admin_foto_remover(uuid) from public, anon;
grant execute on function public.admin_foto_remover(uuid) to authenticated;
