-- =============================================================================
-- 0053_rastros.sql — por onde a pessoa andou, e onde ela largou 👣
--
-- O console sabia tudo sobre o que a casa VENDEU e nada sobre o que a pessoa
-- FEZ antes de comprar (ou de desistir). Dava pra ver o pedido pago e o mimo
-- resgatado; não dava pra responder as três perguntas que a casa faz quando
-- olha o site: em que tela a pessoa estava quando fechou a aba, que seção
-- ninguém toca, e quanta gente encheu o carrinho e foi embora.
--
-- O QUE ISTO GUARDA, E O QUE NÃO GUARDA:
--   Guarda a VISITA (uma aba aberta: por onde entrou, por onde saiu, quantos
--   cliques, se tinha carrinho) e os EVENTOS dela (clique e "vista" de seção).
--   NÃO guarda IP, não guarda user agent, não guarda o texto que a pessoa
--   digitou e não guarda o que ela leu — só o rótulo do que ela TOCOU e o nome
--   da seção que passou pelos olhos dela. O `user_id` entra só quando a pessoa
--   já está logada, e vem de `auth.uid()`, nunca do corpo da chamada: senão
--   qualquer um carimbaria a visita dele com o id de outra pessoa.
--
--   A "vista" de seção é a metade que faz a pergunta da casa ter resposta.
--   Seção fria com contagem de clique só aparece como AUSÊNCIA (zero cliques =
--   zero linhas = some do relatório), e o que a casa quer saber é justamente a
--   seção que TODO MUNDO VÊ e NINGUÉM TOCA. Sem a vista, "fria" e "ninguém
--   chegou até lá" são a mesma linha em branco, e são problemas opostos.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • As duas tabelas são DENY-BY-DEFAULT: RLS ligada e NENHUMA policy. O
--     client não lê nem escreve direto. Quem escreve é a `registrar_rastro`
--     (SECURITY DEFINER, aberta a anon — a maior parte de quem visita o site
--     não tem conta, e é justamente essa gente que a casa quer enxergar); quem
--     lê é o console, pelas duas `admin_rastros_*`.
--   • Endpoint público de escrita tem três freios, porque quem escreve aqui é
--     literalmente qualquer pessoa com a anon key (que está no bundle, como tem
--     que estar): no máximo 40 eventos por chamada, 400 por visita, e 400
--     visitas novas por hora. Passou do teto, a resposta continua `ok:true` e
--     nada é gravado — quem está navegando não tem nada com isso.
--   • Todo texto é aparado e truncado no BANCO, não no navegador: `pagina` só
--     entra se começar com "/" (senão vira 'outra'), e seção/alvo param em 80
--     caracteres. O console escapa tudo o que mostra, como sempre.
--
-- POR QUE A LIMPEZA É SORTEADA, E NÃO UM CRON:
--   Rastro é dado que cresce sozinho e envelhece rápido: ninguém vai perguntar
--   em março o que estava frio em setembro. Um `delete` a cada escrita seria
--   desperdício; um cron seria peça nova de infra pra uma linha de SQL. Então a
--   própria função sorteia: uma em cada cinquenta chamadas varre o que passou
--   de 180 dias (um semestre, que segura a sazonalidade do café). O `on delete
--   cascade` leva os eventos junto.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE).
-- =============================================================================

-- =============================================================================
-- 1. As tabelas
-- =============================================================================

-- A visita é uma ABA ABERTA, não uma pessoa: o id nasce no `sessionStorage` do
-- navegador e morre quando a aba fecha. Foi escolha, e é a escolha mais
-- privada das disponíveis: ninguém é seguido de um dia pro outro, e o mesmo
-- celular voltando amanhã conta como visita nova. Pro que a casa quer saber
-- ("onde essa navegação terminou"), a aba é a unidade certa.
create table if not exists public.rastro_visitas (
  id                 uuid primary key,
  criada_em          timestamptz not null default now(),
  vista_em           timestamptz not null default now(),
  user_id            uuid references auth.users (id) on delete set null,
  dispositivo        text check (dispositivo is null or dispositivo in ('celular', 'computador')),
  -- o HOST de onde a pessoa veio (google.com, instagram.com) ou 'direto'.
  -- Nunca a URL inteira: query string de rede social carrega id de anúncio e
  -- às vezes id de pessoa, e isso não é da conta da casa.
  origem             text check (origem is null or char_length(origem) <= 80),
  pagina_entrada     text not null,
  -- Onde a visita TERMINOU. É a pergunta que abriu esta migration: a última
  -- página, a última seção e o rótulo do último clique antes de fechar.
  pagina_saida       text,
  secao_saida        text,
  alvo_saida         text,
  cliques            integer not null default 0,
  paginas            integer not null default 1,
  -- Fotografia do carrinho no último pulso. É o que separa "passou pela loja"
  -- de "escolheu e desistiu", que são a mesma visita até aqui.
  carrinho_itens     integer not null default 0,
  carrinho_centavos  integer not null default 0,
  checkout_iniciado  boolean not null default false,
  comprou            boolean not null default false
);

create index if not exists idx_rastro_visitas_criada on public.rastro_visitas (criada_em desc);
create index if not exists idx_rastro_visitas_saida  on public.rastro_visitas (pagina_saida, secao_saida);

create table if not exists public.rastro_eventos (
  id         bigserial primary key,
  visita_id  uuid not null references public.rastro_visitas (id) on delete cascade,
  criado_em  timestamptz not null default now(),
  -- 'clique' = a pessoa TOCOU. 'vista' = a seção passou pelos olhos dela (meia
  -- seção na tela por um segundo). Uma por seção por carregamento de página.
  tipo       text not null check (tipo in ('clique', 'vista')),
  pagina     text not null,
  secao      text not null,
  alvo       text
);

create index if not exists idx_rastro_eventos_visita on public.rastro_eventos (visita_id);
create index if not exists idx_rastro_eventos_periodo on public.rastro_eventos (criado_em desc);
create index if not exists idx_rastro_eventos_secao on public.rastro_eventos (pagina, secao, tipo);

alter table public.rastro_visitas enable row level security;
alter table public.rastro_eventos enable row level security;

-- Nenhuma policy, de propósito: RLS ligada sem policy = ninguém passa pelo
-- PostgREST, nem anon nem logado. As portas são as três funções abaixo.


-- =============================================================================
-- 2. O catálogo de permissão (0047) ganha a página "os rastros"
-- -----------------------------------------------------------------------------
-- Permissão nova daqui pra frente é INSERT numa tabela de catálogo, não `alter
-- constraint` — é exatamente o que a 0047 comprou. A página entra na seção "o
-- dia a dia", ao lado do painel: é número do site inteiro, e é o tipo de coisa
-- que se olha no começo da semana.
--
-- Só existe o `ver`. Não há o que MEXER num rastro (ele é o que aconteceu) nem
-- o que ARRUMAR (a limpeza é por idade, sozinha). Inventar os três níveis aqui
-- seria enfeite, e o CLAUDE.md já diz o que a casa acha de permissão que não
-- abre porta nenhuma.
-- =============================================================================

insert into public.permissao_paginas (slug, secao_slug, rotulo, descricao, aba, ordem) values
  ('rastros', 'dia', 'os rastros', 'por onde a pessoa andou e onde ela largou o site', 'rastros', 30)
on conflict (slug) do update
  set secao_slug = excluded.secao_slug, rotulo = excluded.rotulo,
      descricao  = excluded.descricao,  aba    = excluded.aba, ordem = excluded.ordem;

insert into public.permissoes (slug, pagina_slug, acao, nivel, rotulo, descricao) values
  ('rastros.ver', 'rastros', 'ver', 1, 'enxergar', 'ler por onde a visita andou, onde ela terminou e que seção está fria')
on conflict (slug) do update
  set pagina_slug = excluded.pagina_slug, acao = excluded.acao, nivel = excluded.nivel,
      rotulo = excluded.rotulo, descricao = excluded.descricao;

-- Quem já enxerga os relatórios da loja passa a enxergar os rastros também: é a
-- mesma pergunta ("o que está funcionando?"), vista antes da venda em vez de
-- depois. Ninguém precisa ser reautorizado na mão por causa desta migration.
insert into public.staff_permissions (user_id, permissao)
  select sp.user_id, 'rastros.ver'
    from public.staff_permissions sp
   where sp.permissao = 'relatorios.ver'
on conflict do nothing;


-- =============================================================================
-- 3. Dois aparadores de texto
-- -----------------------------------------------------------------------------
-- Existem pra que a validação fique num lugar só: a mesma regra vale pro pulso
-- que vem do navegador da casa e pro que vem de um curl com a anon key.
-- =============================================================================

create or replace function public.rastro_texto(p_valor text, p_max integer)
returns text
language sql
immutable
as $$
  select nullif(left(btrim(coalesce(p_valor, '')), greatest(p_max, 1)), '');
$$;

-- Caminho de página. Só aceita o que parece caminho interno; qualquer outra
-- coisa (URL inteira, javascript:, lixo) vira 'outra' em vez de entrar.
create or replace function public.rastro_caminho(p_valor text)
returns text
language sql
immutable
as $$
  select coalesce(
    (select left(v, 120)
       from (select btrim(coalesce(p_valor, '')) as v) t
      where v like '/%' and v not like '//%'),
    'outra'
  );
$$;


-- =============================================================================
-- 4. registrar_rastro(jsonb) — a única porta de escrita
-- -----------------------------------------------------------------------------
-- Um parâmetro jsonb só, de propósito: o navegador manda isto no `pagehide`,
-- às vezes por `sendBeacon`, e um corpo único é o que sobrevive a esse caminho.
--
-- A resposta é sempre a mesma (`ok:true`), grave ou não. Quem está navegando
-- não tem nada a fazer com a resposta, e um erro visível ali seria o site
-- reclamando na cara de quem visita por causa de uma estatística da casa.
-- =============================================================================
create or replace function public.registrar_rastro(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_visita     uuid;
  v_pagina     text;
  v_eventos    jsonb := '[]'::jsonb;
  v_ja         integer := 0;
  v_limite     integer := 0;
  v_cliques    integer := 0;
  v_nova_pag   integer := 0;
  v_saida      jsonb;
  v_carrinho   jsonb;
begin
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then
    return jsonb_build_object('ok', true);
  end if;

  -- Id malformado não é erro pra quem navega: é pulso perdido, e ponto.
  begin
    v_visita := (p_dados->>'visita')::uuid;
  exception when others then
    return jsonb_build_object('ok', true);
  end;
  if v_visita is null then
    return jsonb_build_object('ok', true);
  end if;

  v_pagina := public.rastro_caminho(p_dados->>'pagina');

  if jsonb_typeof(p_dados->'eventos') = 'array' then
    v_eventos := p_dados->'eventos';
  end if;

  -- Teto por visita (400) e por chamada (40). Passou, o excedente é descartado
  -- em silêncio: a visita já disse o que tinha pra dizer.
  select count(*) into v_ja from public.rastro_eventos where visita_id = v_visita;
  v_limite := greatest(0, least(40, 400 - v_ja));

  select count(*) filter (where coalesce(e->>'tipo', 'clique') <> 'vista')
    into v_cliques
    from (
      select e from jsonb_array_elements(v_eventos) with ordinality as t(e, i)
       where t.i <= v_limite
    ) s;
  v_cliques := coalesce(v_cliques, 0);

  -- Teto global de visitas novas por hora. O anti-flood da 0040 é por contato;
  -- aqui não há contato nenhum, então o freio é a torneira inteira. Visita que
  -- JÁ existe segue escrevendo: quem está navegando de verdade não é cortado no
  -- meio por causa de uma enxurrada de fora.
  if not exists (select 1 from public.rastro_visitas where id = v_visita)
     and (select count(*) from public.rastro_visitas
           where criada_em > now() - interval '1 hour') >= 400 then
    return jsonb_build_object('ok', true);
  end if;

  if coalesce((p_dados->>'pagina_nova')::boolean, false) then
    v_nova_pag := 1;
  end if;

  v_saida    := case when jsonb_typeof(p_dados->'saida') = 'object' then p_dados->'saida' end;
  v_carrinho := case when jsonb_typeof(p_dados->'carrinho') = 'object' then p_dados->'carrinho' end;

  insert into public.rastro_visitas as v (
    id, user_id, dispositivo, origem, pagina_entrada,
    pagina_saida, secao_saida, alvo_saida,
    cliques, paginas, carrinho_itens, carrinho_centavos,
    checkout_iniciado, comprou, vista_em
  )
  values (
    v_visita,
    -- SEMPRE de auth.uid(): o corpo da chamada não diz quem é ninguém.
    auth.uid(),
    case when p_dados->>'dispositivo' in ('celular', 'computador') then p_dados->>'dispositivo' end,
    public.rastro_texto(p_dados->>'origem', 80),
    v_pagina,
    case when v_saida is not null then public.rastro_caminho(v_saida->>'pagina') end,
    case when v_saida is not null then public.rastro_texto(v_saida->>'secao', 80) end,
    case when v_saida is not null then public.rastro_texto(v_saida->>'alvo', 80) end,
    v_cliques,
    1,
    greatest(0, least(coalesce((v_carrinho->>'itens')::integer, 0), 999)),
    greatest(0, least(coalesce((v_carrinho->>'centavos')::integer, 0), 100000000)),
    coalesce((p_dados->>'checkout')::boolean, false),
    coalesce((p_dados->>'comprou')::boolean, false),
    now()
  )
  on conflict (id) do update set
    vista_em          = now(),
    -- A pessoa pode ter entrado logada no meio da visita. Uma vez carimbado,
    -- não se troca: a visita é de quem a começou como dono.
    user_id           = coalesce(v.user_id, excluded.user_id),
    -- Saída nova ganha da antiga (é o ÚLTIMO clique que interessa); pulso sem
    -- saída não apaga a que já estava lá.
    pagina_saida      = coalesce(excluded.pagina_saida, v.pagina_saida),
    secao_saida       = coalesce(excluded.secao_saida,  v.secao_saida),
    alvo_saida        = coalesce(excluded.alvo_saida,   v.alvo_saida),
    cliques           = v.cliques + excluded.cliques,
    paginas           = v.paginas + v_nova_pag,
    carrinho_itens    = case when v_carrinho is not null then excluded.carrinho_itens    else v.carrinho_itens    end,
    carrinho_centavos = case when v_carrinho is not null then excluded.carrinho_centavos else v.carrinho_centavos end,
    -- Marco não desliga: quem chegou no checkout chegou, mesmo que volte pra
    -- vitrine depois.
    checkout_iniciado = v.checkout_iniciado or excluded.checkout_iniciado,
    comprou           = v.comprou or excluded.comprou;

  if v_limite > 0 then
    insert into public.rastro_eventos (visita_id, tipo, pagina, secao, alvo)
      select
        v_visita,
        case when t.e->>'tipo' = 'vista' then 'vista' else 'clique' end,
        coalesce(nullif(public.rastro_caminho(t.e->>'pagina'), 'outra'), v_pagina),
        coalesce(public.rastro_texto(t.e->>'secao', 80), 'sem seção'),
        public.rastro_texto(t.e->>'alvo', 80)
        from jsonb_array_elements(v_eventos) with ordinality as t(e, i)
       where t.i <= v_limite
         and jsonb_typeof(t.e) = 'object';
  end if;

  -- A faxina sorteada (ver o cabeçalho). Uma em cada cinquenta chamadas.
  if random() < 0.02 then
    delete from public.rastro_visitas where criada_em < now() - interval '180 days';
  end if;

  return jsonb_build_object('ok', true);
end;
$$;


-- =============================================================================
-- 5. admin_rastros_resumo(dias) — a tela inteira numa viagem só
-- -----------------------------------------------------------------------------
-- `returns jsonb`, e não `returns table`, pelo mesmo motivo da 0045: uma
-- leitura composta (números + saídas + seções + funil) teria duas dúzias de
-- colunas declaradas pra errar, e foi um erro desses (varchar declarado como
-- text) que deixou cinco abas do console quebradas da 0017 até a 0042.
-- =============================================================================
create or replace function public.admin_rastros_resumo(p_dias integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_desde timestamptz;
  v_dias  integer := least(greatest(coalesce(p_dias, 30), 1), 365);
begin
  if not public.tem_permissao('rastros.ver') then
    raise exception 'sem permissão pra ver os rastros';
  end if;

  v_desde := now() - (v_dias || ' days')::interval;

  return jsonb_build_object(
    'dias', v_dias,

    'numeros', (
      select jsonb_build_object(
               'visitas',        count(*),
               'cliques',        coalesce(sum(v.cliques), 0),
               'sem_clique',     count(*) filter (where v.cliques = 0),
               'uma_pagina',     count(*) filter (where v.paginas <= 1),
               'no_celular',     count(*) filter (where v.dispositivo = 'celular'),
               'logadas',        count(*) filter (where v.user_id is not null),
               'com_carrinho',   count(*) filter (where v.carrinho_itens > 0),
               'compraram',      count(*) filter (where v.comprou)
             )
        from public.rastro_visitas v
       where v.criada_em >= v_desde),

    -- A resposta da pergunta que abriu a migration: onde a visita terminou.
    -- Sem `alvo_saida` = a pessoa saiu sem tocar em nada naquela página, e essa
    -- linha vale tanto quanto as outras (às vezes mais).
    'saidas', coalesce((
      -- O `order by` aparece DUAS vezes de propósito, aqui e nos dois blocos
      -- abaixo: o de dentro é quem escolhe QUAIS linhas o `limit` guarda, e o
      -- do `jsonb_agg` é quem garante a ORDEM dentro do array. Sem o segundo, a
      -- lista chega no console em ordem de varredura.
      select jsonb_agg(t order by t.visitas desc)
        from (
          select v.pagina_saida                            as pagina,
                 coalesce(v.secao_saida, 'sem seção')      as secao,
                 v.alvo_saida                              as alvo,
                 count(*)                                  as visitas,
                 count(*) filter (where v.carrinho_itens > 0) as com_carrinho
            from public.rastro_visitas v
           where v.criada_em >= v_desde
             and v.pagina_saida is not null
           group by 1, 2, 3
           order by count(*) desc
           limit 30
        ) t), '[]'::jsonb),

    -- O mapa de calor, e o coração do pedido: quantos OLHOS a seção recebeu
    -- contra quantos DEDOS. Ordenado da mais fria pra mais quente, porque é a
    -- fria que se veio ver. `fria` marca o que tem plateia (20 vistas ou mais)
    -- e quase nenhum toque (menos de 5%).
    'secoes', coalesce((
      select jsonb_agg(t order by t.fria desc, t.taxa asc nulls last, t.vistas desc)
        from (
          select e.pagina,
                 e.secao,
                 count(*) filter (where e.tipo = 'vista')  as vistas,
                 count(*) filter (where e.tipo = 'clique') as cliques,
                 case when count(*) filter (where e.tipo = 'vista') > 0
                      then round(
                             count(*) filter (where e.tipo = 'clique')::numeric
                             / count(*) filter (where e.tipo = 'vista'), 4)
                 end                                        as taxa,
                 (count(*) filter (where e.tipo = 'vista') >= 20
                  and count(*) filter (where e.tipo = 'clique')::numeric
                      < 0.05 * count(*) filter (where e.tipo = 'vista')) as fria
            from public.rastro_eventos e
           where e.criado_em >= v_desde
           group by 1, 2
          having count(*) filter (where e.tipo = 'vista') > 0
              or count(*) filter (where e.tipo = 'clique') > 0
           -- A ordem É o relatório: as marcadas como frias na frente, depois
           -- as de menor taxa. Seção com ZERO vista (taxa nula) vai pro FIM, e
           -- não pro começo: ela não é fria, ela é sem informação, e deixá-la
           -- liderar empurrava pra baixo justamente a seção com plateia e sem
           -- toque, que é a que a casa veio ver.
           order by 6 desc, 5 asc nulls last, 3 desc
           limit 60
        ) t), '[]'::jsonb),

    'paginas', coalesce((
      select jsonb_agg(t order by t.visitas desc)
        from (
          select e.pagina,
                 count(distinct e.visita_id)               as visitas,
                 count(*) filter (where e.tipo = 'clique') as cliques,
                 (select count(*) from public.rastro_visitas v2
                   where v2.criada_em >= v_desde and v2.pagina_saida = e.pagina) as saidas
            from public.rastro_eventos e
           where e.criado_em >= v_desde
           group by 1
           order by 2 desc
           limit 30
        ) t), '[]'::jsonb),

    -- O funil da loja. Cada degrau é um subconjunto do anterior, então a queda
    -- entre dois números É o lugar onde a compra morre.
    'loja', (
      select jsonb_build_object(
               'viram_loja', count(*) filter (
                 where exists (select 1 from public.rastro_eventos e
                                where e.visita_id = v.id and e.pagina like '/loja%')),
               'viram_produto', count(*) filter (
                 where exists (select 1 from public.rastro_eventos e
                                where e.visita_id = v.id and e.pagina like '/produto%')),
               'com_carrinho',      count(*) filter (where v.carrinho_itens > 0),
               'foram_ao_checkout', count(*) filter (where v.checkout_iniciado),
               'compraram',         count(*) filter (where v.comprou),
               'carrinho_frio_centavos', coalesce(
                 sum(v.carrinho_centavos) filter (where v.carrinho_itens > 0 and not v.comprou), 0)
             )
        from public.rastro_visitas v
       where v.criada_em >= v_desde)
  );
end;
$$;


-- =============================================================================
-- 6. admin_rastros_leads(dias, limite) — o carrinho frio COM nome e telefone
-- -----------------------------------------------------------------------------
-- Esta é a metade acionável do relatório: quem chegou a abrir o checkout e não
-- pagou. Sai de `orders` pendente/cancelada, que já existe desde a 0007 — a
-- `create-checkout-session` pré-cria o pedido antes de mandar a pessoa pro
-- Asaas, então o carrinho abandonado já estava guardado, só não tinha tela.
--
-- POR QUE A TRAVA AQUI É `pedidos.ver`, E NÃO `rastros.ver`:
--   Rastro é anônimo; isto tem nome, e-mail e telefone de quem comprou quase.
--   Deixar as duas coisas atrás da mesma chave faria "ver que seção está fria"
--   virar, de graça, "ler a agenda de contatos da loja". É a mesma regra que a
--   0044 seguiu com o mural: permissão de olhar uma coisa não é permissão de
--   olhar outra que por acaso mora ao lado.
-- =============================================================================
create or replace function public.admin_rastros_leads(
  p_dias   integer default 30,
  p_limite integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_dias timestamptz := now() - (least(greatest(coalesce(p_dias, 30), 1), 365) || ' days')::interval;
begin
  if not public.tem_permissao('pedidos.ver') then
    raise exception 'sem permissão pra ver os pedidos parados';
  end if;

  return coalesce((
    select jsonb_agg(t order by t.criado_em desc)
      from (
        select o.id,
               o.created_at                                    as criado_em,
               o.status,
               coalesce(o.entrega_nome, pr.full_name, '')       as nome,
               coalesce(u.email::text, '')                      as email,
               coalesce(o.entrega_telefone, pr.telefone, '')    as telefone,
               o.total_centavos,
               coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'nome', oi.nome_snapshot,
                          'variante', oi.variante_snapshot,
                          'qtd', oi.qtd)
                          order by oi.nome_snapshot)
                   from public.order_items oi where oi.order_id = o.id
               ), '[]'::jsonb)                                  as itens,
               -- Voltou depois? Se a pessoa comprou de novo em seguida, o
               -- pedido parado não é lead frio, é tentativa que deu errado e a
               -- casa não precisa ligar pra ela.
               exists (
                 select 1 from public.orders o2
                  where o2.user_id = o.user_id
                    and o2.status in ('pago', 'preparando', 'pronto', 'entregue')
                    and o2.created_at > o.created_at
               )                                                as voltou
          from public.orders o
          left join public.profiles pr on pr.id = o.user_id
          left join auth.users     u  on u.id  = o.user_id
         where o.origem = 'site'
           and o.status in ('pendente', 'cancelado')
           and o.created_at >= v_dias
         order by o.created_at desc
         limit greatest(1, least(coalesce(p_limite, 50), 200))
      ) t), '[]'::jsonb);
end;
$$;


-- =============================================================================
-- 7. Grants — quem alcança o quê
-- =============================================================================
revoke all on function public.rastro_texto(text, integer)   from public, anon, authenticated;
revoke all on function public.rastro_caminho(text)          from public, anon, authenticated;

revoke all on function public.registrar_rastro(jsonb)       from public;
-- Aberta a anon de propósito: a maior parte de quem visita o site não tem
-- conta, e é essa gente que a casa não enxergava.
grant execute on function public.registrar_rastro(jsonb)    to anon, authenticated;

revoke all on function public.admin_rastros_resumo(integer)          from public, anon;
grant execute on function public.admin_rastros_resumo(integer)       to authenticated;

revoke all on function public.admin_rastros_leads(integer, integer)  from public, anon;
grant execute on function public.admin_rastros_leads(integer, integer) to authenticated;
