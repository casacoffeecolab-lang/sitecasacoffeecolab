-- =============================================================================
-- 0047_permissoes_por_secao.sql — permissão por SEÇÃO do site e por AÇÃO 🔑
--
-- O PEDIDO: "um agrupamento de permissões por seção do site. exemplo: página de
-- vendas, algumas permissões de ação; página de resgate/presentes, permissões de
-- quem enxerga, de quem mexe, de quem arruma."
--
-- O QUE ESTAVA NO CAMINHO: a 0046 deu uma permissão por PÁGINA do console, e
-- isso resolveu o "quem enxerga o quê". Mas dentro de cada página continuava
-- tudo junto: quem recebia `mural` pra esconder um recado podia apagar a parede
-- inteira; quem recebia `leads` pra ler os pedidos de evento podia arquivar;
-- quem recebia `agenda` pra cadastrar um encontro podia apagar um encontro com
-- as presenças todas dentro. Ou seja: enxergar, mexer e arrumar eram a mesma
-- chave. E a fila de 19 permissões era uma lista plana, sem dizer de que parte
-- do SITE cada uma fala.
--
-- O DESENHO NOVO, em três camadas:
--
--   SEÇÃO   um pedaço do site (a loja, o clube, a casa, o cardápio, a gente,
--           os eventos, o dia a dia, o console). É por aqui que a tela da
--           equipe agrupa, então quem dá acesso raciocina "essa pessoa cuida
--           da loja", não "essa pessoa precisa das caixinhas 3, 7 e 12".
--   PÁGINA  uma tela do console dentro daquela seção (os pedidos, os resgates,
--           o mural…). É o que a 0046 chamava de permissão.
--   AÇÃO    o que a pessoa faz naquela página, em três níveis fixos:
--             ver      (1) enxergar
--             mexer    (2) o dia a dia da página: dar baixa, publicar, atender
--             arrumar  (3) o que desfaz, apaga ou mexe em ponto e código
--
-- O slug fica `<pagina>.<acao>` — `pedidos.ver`, `mural.arrumar`. Quem tem um
-- nível ALCANÇA os de baixo na MESMA página (arrumar > mexer > ver), então
-- ninguém fica podendo consertar uma tela que não pode abrir.
--
-- O whitelist deixou de ser um CHECK escrito à mão (que a 0043 e a 0046 já
-- tiveram que reescrever) e virou TABELA: `permissoes`, com FK vinda da
-- `staff_permissions`. Permissão nova daqui pra frente é INSERT numa tabela de
-- catálogo, não `alter constraint`.
--
-- O QUE MAIS ESTE ARQUIVO FAZ:
--   • O "arrumar" passa a EXISTIR: dez funções novas pros consertos que a casa
--     não tinha como fazer (devolver ponto de resgate errado, desfazer baixa de
--     pedido, gerar o código de presente que o webhook não gerou, esticar
--     validade de brunch, lançar ajuste de pontos, tirar e-mail da lista…).
--     Permissão que não abre porta nenhuma é enfeite; estas abrem.
--   • Duas páginas novas no console: **as assinaturas** e **os pontos**, que
--     eram justamente os dois benefícios sobre os quais a casa era cega.
--   • BACKFILL: quem já tinha a permissão da 0046 recebe a fila inteira do que
--     fazia. Ninguém perde nada na virada, e o "arrumar" (que é novidade) só
--     vai pra quem já podia apagar antes.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente.
-- =============================================================================


-- =============================================================================
-- 1. O catálogo: seção › página › ação
-- -----------------------------------------------------------------------------
-- Três tabelas de dicionário. Elas não guardam quem pode o quê (isso continua na
-- `staff_permissions`), guardam o que EXISTE pra poder. RLS ligada: quem lê é
-- quem já entra no console, e a tela da equipe lê pela RPC.
-- =============================================================================

create table if not exists public.permissao_secoes (
  slug       text primary key,
  rotulo     text not null,
  descricao  text,
  ordem      integer not null default 0
);

create table if not exists public.permissao_paginas (
  slug        text primary key,
  secao_slug  text not null references public.permissao_secoes (slug) on delete restrict,
  rotulo      text not null,
  descricao   text,
  -- o id da aba no console (`NAV` do admin.js). Nulo = permissão que não tem
  -- tela própria.
  aba         text,
  ordem       integer not null default 0
);

create table if not exists public.permissoes (
  slug         text primary key,
  pagina_slug  text not null references public.permissao_paginas (slug) on delete restrict,
  -- 'ver' | 'mexer' | 'arrumar'. O nível é o que faz a hierarquia funcionar.
  acao         text not null check (acao in ('ver', 'mexer', 'arrumar')),
  nivel        smallint not null check (nivel between 1 and 3),
  rotulo       text not null,
  descricao    text,
  unique (pagina_slug, acao)
);

-- A ponte de compatibilidade. As policies e as funções que este arquivo NÃO
-- reescreve continuam perguntando pelo slug velho da 0046 (`tem_permissao
-- ('favoritos')`), e a `permissao_canonica` traduz. Sem isto, aplicar a 0047
-- apagaria o acesso de todo mundo até a última função ser reescrita.
create table if not exists public.permissoes_legado (
  slug_velho  text primary key,
  slug_novo   text not null references public.permissoes (slug) on delete restrict
);

alter table public.permissao_secoes   enable row level security;
alter table public.permissao_paginas  enable row level security;
alter table public.permissoes         enable row level security;
alter table public.permissoes_legado  enable row level security;

-- Leitura pra quem entra no console (é dicionário, não dado de ninguém).
-- Escrita: nenhuma policy. O catálogo muda por migration, não por tela.
drop policy if exists permissao_secoes_select on public.permissao_secoes;
create policy permissao_secoes_select on public.permissao_secoes
  for select to authenticated using (public.pode_entrar_no_console());

drop policy if exists permissao_paginas_select on public.permissao_paginas;
create policy permissao_paginas_select on public.permissao_paginas
  for select to authenticated using (public.pode_entrar_no_console());

drop policy if exists permissoes_select on public.permissoes;
create policy permissoes_select on public.permissoes
  for select to authenticated using (public.pode_entrar_no_console());

drop policy if exists permissoes_legado_select on public.permissoes_legado;
create policy permissoes_legado_select on public.permissoes_legado
  for select to authenticated using (public.pode_entrar_no_console());


-- =============================================================================
-- 2. O seed do catálogo — as 8 seções, as 20 páginas, as 43 ações
-- -----------------------------------------------------------------------------
-- A seção é um pedaço do SITE, não uma gaveta do console: é assim que a casa
-- pensa quando decide quem cuida do quê ("fulana cuida da loja", "beltrano
-- cuida do clube").
-- =============================================================================

insert into public.permissao_secoes (slug, rotulo, descricao, ordem) values
  ('dia',      'o dia a dia',   'por onde o turno começa',                              10),
  ('loja',     'a loja',        'o que a casa vende pela internet',                     20),
  ('clube',    'o clube',       'assinatura, pontos, presentes e os mimos de quem é de casa', 30),
  ('cardapio', 'o cardápio',    'o que sai da cozinha e do balcão',                     40),
  ('casa',     'a casa',        'o que a casa publica e o que a turma escreve',         50),
  ('gente',    'a gente',       'quem passa por aqui',                                  60),
  ('eventos',  'os eventos',    'quem quer fazer o evento dele aqui',                   70),
  ('console',  'o console',     'quem entra por esta porta',                            80)
on conflict (slug) do update
  set rotulo = excluded.rotulo, descricao = excluded.descricao, ordem = excluded.ordem;

insert into public.permissao_paginas (slug, secao_slug, rotulo, descricao, aba, ordem) values
  ('painel',       'dia',      'o painel',            'os números do dia',                              'painel',       10),
  ('pautas',       'dia',      'o quadro de pautas',  'o que a casa combinou pra hoje',                 'pautas',       20),

  ('pedidos',      'loja',     'os pedidos',          'a fila de compras da loja',                      'pedidos',      10),
  ('relatorios',   'loja',     'os relatórios',       'o que vendeu e o que saiu por pontos',           'relatorios',   20),
  ('desejos',      'loja',     'ficou pra depois',    'o que a casa mais quer',                         'desejos',      30),
  ('reposicao',    'loja',     'quem espera voltar',  'produto esgotado com fila',                      'esperando',    40),

  ('assinaturas',  'clube',    'as assinaturas',      'quem assina, em que plano e até quando vale',    'assinaturas',  10),
  ('pontos',       'clube',    'os pontos',           'o saldo e o extrato de cada pessoa',             'pontos',       20),
  ('resgates',     'clube',    'os resgates',         'as recompensas trocadas por pontos',             'resgates',     30),
  ('presentes',    'clube',    'os presentes',        'os planos dados de presente',                    'presentes',    40),
  ('aniversarios', 'clube',    'os aniversários',     'o brunch de quem faz aniversário no mês',        'aniversarios', 50),

  ('favoritos',    'cardapio', 'os favoritos',        'o que a casa mais ama',                          'favoritos',    10),

  ('mural',        'casa',     'o mural',             'a parede de recados do /o-casa',                 'mural',        10),
  ('recados',      'casa',     'o recado do topo',    'a tarja que acende no site',                     'recados',      20),
  ('trilha',       'casa',     'a trilha',            'as playlists da home',                           'trilha',       30),
  ('agenda',       'casa',     'a agenda',            'os encontros que a casa promove',                'agenda',       40),

  ('pessoas',      'gente',    'as pessoas',          'quem já passou por aqui',                        'pessoas',      10),
  ('espera',       'gente',    'a lista de espera',   'os e-mails deixados no rodapé',                  'espera',       20),

  ('leads',        'eventos',  'os pedidos de evento','quem quer fazer evento aqui',                    'leads',        10),

  ('equipe',       'console',  'a equipe',            'quem entra no console e alcança o quê',          'equipe',       10)
on conflict (slug) do update
  set secao_slug = excluded.secao_slug, rotulo = excluded.rotulo,
      descricao  = excluded.descricao,  aba    = excluded.aba, ordem = excluded.ordem;

insert into public.permissoes (slug, pagina_slug, acao, nivel, rotulo, descricao) values
  -- o dia a dia -------------------------------------------------------------
  ('painel.ver',        'painel',       'ver',     1, 'enxergar', 'abrir o painel e ler os números do dia'),

  ('pautas.ver',        'pautas',       'ver',     1, 'enxergar', 'ler os quadros, as pautas e os comentários'),
  ('pautas.mexer',      'pautas',       'mexer',   2, 'mexer',    'criar, editar, mover e comentar'),
  ('pautas.arrumar',    'pautas',       'arrumar', 3, 'arrumar',  'apagar pauta, quadro, grupo ou comentário'),

  -- a loja -------------------------------------------------------------------
  ('pedidos.ver',       'pedidos',      'ver',     1, 'enxergar', 'ver a fila de compras e o que tem dentro'),
  ('pedidos.mexer',     'pedidos',      'mexer',   2, 'mexer',    'dar baixa: confirmar entregue ou retirado'),
  ('pedidos.arrumar',   'pedidos',      'arrumar', 3, 'arrumar',  'mudar o estado do pedido na mão, inclusive desfazer uma baixa'),

  ('relatorios.ver',    'relatorios',   'ver',     1, 'enxergar', 'ler o que vendeu e o que saiu por pontos'),
  ('desejos.ver',       'desejos',      'ver',     1, 'enxergar', 'ver o que a casa mais quer'),
  ('reposicao.ver',     'reposicao',    'ver',     1, 'enxergar', 'ver quem espera cada produto voltar'),

  -- o clube ------------------------------------------------------------------
  ('assinaturas.ver',   'assinaturas',  'ver',     1, 'enxergar', 'ver quem assina, o plano e até quando vale'),
  ('assinaturas.arrumar','assinaturas', 'arrumar', 3, 'arrumar',  'esticar o período já pago, de cortesia'),

  ('pontos.ver',        'pontos',       'ver',     1, 'enxergar', 'ver o saldo e o extrato de cada pessoa'),
  ('pontos.arrumar',    'pontos',       'arrumar', 3, 'arrumar',  'lançar um ajuste de pontos, sempre com motivo'),

  ('resgates.ver',      'resgates',     'ver',     1, 'enxergar', 'ver as recompensas trocadas por pontos'),
  ('resgates.mexer',    'resgates',     'mexer',   2, 'mexer',    'dar baixa: entregar a recompensa em mãos'),
  ('resgates.arrumar',  'resgates',     'arrumar', 3, 'arrumar',  'desfazer o resgate e devolver os pontos'),

  ('presentes.ver',     'presentes',    'ver',     1, 'enxergar', 'ver os presentes vendidos, com o código'),
  ('presentes.arrumar', 'presentes',    'arrumar', 3, 'arrumar',  'gerar o código que faltou, ou cancelar um presente parado'),

  ('aniversarios.ver',  'aniversarios', 'ver',     1, 'enxergar', 'ver os brunches reservados'),
  ('aniversarios.mexer','aniversarios', 'mexer',   2, 'mexer',    'dar baixa: brunch entregue'),
  ('aniversarios.arrumar','aniversarios','arrumar',3, 'arrumar',  'desfazer a baixa ou esticar a validade do código'),

  -- o cardápio ---------------------------------------------------------------
  ('favoritos.ver',     'favoritos',    'ver',     1, 'enxergar', 'ver o ranking do cardápio'),

  -- a casa -------------------------------------------------------------------
  ('mural.ver',         'mural',        'ver',     1, 'enxergar', 'ler a parede inteira, inclusive o que está escondido'),
  ('mural.mexer',       'mural',        'mexer',   2, 'mexer',    'esconder um recado, e devolver pra parede'),
  ('mural.arrumar',     'mural',        'arrumar', 3, 'arrumar',  'apagar recado de vez'),

  ('recados.ver',       'recados',      'ver',     1, 'enxergar', 'ler os recados escritos e agendados'),
  ('recados.mexer',     'recados',      'mexer',   2, 'mexer',    'escrever, agendar e ligar ou desligar'),
  ('recados.arrumar',   'recados',      'arrumar', 3, 'arrumar',  'apagar um recado'),

  ('trilha.ver',        'trilha',       'ver',     1, 'enxergar', 'ver as playlists da casa'),
  ('trilha.mexer',      'trilha',       'mexer',   2, 'mexer',    'cadastrar, editar e escolher a que está tocando'),
  ('trilha.arrumar',    'trilha',       'arrumar', 3, 'arrumar',  'tirar uma playlist da trilha'),

  ('agenda.ver',        'agenda',       'ver',     1, 'enxergar', 'ver os encontros e quantos confirmaram'),
  ('agenda.mexer',      'agenda',       'mexer',   2, 'mexer',    'criar e editar encontro'),
  ('agenda.arrumar',    'agenda',       'arrumar', 3, 'arrumar',  'apagar encontro, que leva as presenças junto'),

  -- a gente ------------------------------------------------------------------
  ('pessoas.ver',       'pessoas',      'ver',     1, 'enxergar', 'ver quem já passou por aqui, com plano e pontos'),

  ('espera.ver',        'espera',       'ver',     1, 'enxergar', 'ler os e-mails deixados no rodapé'),
  ('espera.arrumar',    'espera',       'arrumar', 3, 'arrumar',  'tirar um e-mail da lista, a pedido de quem deixou'),

  -- os eventos ---------------------------------------------------------------
  ('leads.ver',         'leads',        'ver',     1, 'enxergar', 'ler os pedidos de evento, com nome e telefone'),
  ('leads.mexer',       'leads',        'mexer',   2, 'mexer',    'marcar já falei, e arquivar'),
  ('leads.arrumar',     'leads',        'arrumar', 3, 'arrumar',  'apagar o pedido de vez'),

  -- o console ----------------------------------------------------------------
  ('equipe.ver',        'equipe',       'ver',     1, 'enxergar', 'ver quem está no console e o que cada um alcança'),
  ('equipe.mexer',      'equipe',       'mexer',   2, 'mexer',    'dar e tirar permissões')
on conflict (slug) do update
  set pagina_slug = excluded.pagina_slug, acao = excluded.acao, nivel = excluded.nivel,
      rotulo = excluded.rotulo, descricao = excluded.descricao;

-- O de-para dos slugs da 0046. Cada slug velho aponta pro nível de LEITURA da
-- página: as funções que este arquivo não reescreve são todas de leitura, e a
-- única de escrita que ficou (`admin_marcar_entregue`, que pergunta por
-- 'entregas') aponta pro `pedidos.mexer`, que é exatamente o que ela sempre foi.
insert into public.permissoes_legado (slug_velho, slug_novo) values
  ('dashboard',    'painel.ver'),
  ('pautas',       'pautas.ver'),
  ('pedidos',      'pedidos.ver'),
  ('entregas',     'pedidos.mexer'),
  ('resgates',     'resgates.ver'),
  ('aniversarios', 'aniversarios.ver'),
  ('presentes',    'presentes.ver'),
  ('usuarios',     'pessoas.ver'),
  ('mural',        'mural.ver'),
  ('equipe',       'equipe.ver'),
  ('relatorios',   'relatorios.ver'),
  ('favoritos',    'favoritos.ver'),
  ('desejos',      'desejos.ver'),
  ('reposicao',    'reposicao.ver'),
  ('lista_espera', 'espera.ver'),
  ('leads',        'leads.ver'),
  ('avisos',       'recados.ver'),
  ('trilha',       'trilha.ver'),
  ('agenda',       'agenda.ver')
on conflict (slug_velho) do update set slug_novo = excluded.slug_novo;


-- =============================================================================
-- 3. permissao_canonica + tem_permissao — a régua
-- -----------------------------------------------------------------------------
-- `permissao_canonica` traduz o slug velho e devolve o novo. Slug que não existe
-- em lugar nenhum volta como veio, não casa com o catálogo, e a resposta é
-- "não pode": deny-by-default de graça.
--
-- `tem_permissao` ganhou a hierarquia: quem tem `mural.arrumar` responde
-- verdadeiro pra `mural.mexer` e pra `mural.ver`, porque são a mesma PÁGINA e
-- o nível é maior. A comparação é sempre dentro da página, nunca entre páginas.
-- O resto continua igual à 0032: owner tem tudo, e a senha inicial pendente
-- zera qualquer privilégio.
-- =============================================================================
create or replace function public.permissao_canonica(p_perm text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.slug from public.permissoes p where p.slug = p_perm),
    (select l.slug_novo from public.permissoes_legado l where l.slug_velho = p_perm),
    p_perm
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
        select 1
          from public.staff_permissions sp
          join public.permissoes tenho on tenho.slug = sp.permissao
          join public.permissoes quero on quero.slug = public.permissao_canonica(p_perm)
         where sp.user_id = auth.uid()
           and tenho.pagina_slug = quero.pagina_slug
           and tenho.nivel >= quero.nivel
      )
    )
    and not public.senha_inicial_pendente(),
    false
  );
$$;

revoke all on function public.permissao_canonica(text) from public, anon;
grant execute on function public.permissao_canonica(text) to authenticated;


-- =============================================================================
-- 4. staff_permissions — do CHECK escrito à mão pro catálogo
-- -----------------------------------------------------------------------------
-- A ordem aqui é a coisa mais frágil do arquivo, e cada passo só funciona
-- depois do anterior:
--   1º o CHECK da 0046 SAI. Enquanto ele estiver lá, `pedidos.ver` é um valor
--      proibido e o backfill morre na primeira linha (a lista dele é a dos
--      slugs velhos);
--   2º o backfill entra, com as linhas novas ao lado das velhas;
--   3º as velhas saem;
--   4º só então o FK entra. Se ele viesse antes, as linhas da 0046 (que não
--      existem no catálogo novo) barrariam a própria migration.
-- =============================================================================

-- 4a. O CHECK sai (acha pelo conteúdo: o nome mudou entre 0017, 0043 e 0046).
do $$
declare
  v_nome text;
begin
  for v_nome in
    select con.conname
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace nsp on nsp.oid = rel.relnamespace
     where nsp.nspname = 'public' and rel.relname = 'staff_permissions'
       and con.contype = 'c'
       and pg_get_constraintdef(con.oid) ilike '%dashboard%'
  loop
    execute format('alter table public.staff_permissions drop constraint %I', v_nome);
  end loop;
end $$;

-- 4b. Backfill. Cada slug da 0046 vira a FILA do que aquela pessoa já fazia.
--     `mural`, `avisos`, `trilha` e `agenda` levam o 'arrumar' junto porque
--     apagar já estava dentro delas; `resgates`, `aniversarios` e `leads` param
--     no 'mexer' (dar baixa e atender já dava, desfazer é novidade); e o
--     'arrumar' de pedido, ponto, presente e assinatura não vai pra ninguém
--     automaticamente: é poder novo, e poder novo se dá na mão.
insert into public.staff_permissions (user_id, permissao, granted_by, created_at)
select sp.user_id, novo.permissao, sp.granted_by, sp.created_at
  from public.staff_permissions sp
  join (values
          ('dashboard',    'painel.ver'),
          ('pautas',       'pautas.ver'),
          ('pautas',       'pautas.mexer'),
          ('pautas',       'pautas.arrumar'),
          ('pedidos',      'pedidos.ver'),
          ('entregas',     'pedidos.mexer'),
          ('resgates',     'resgates.ver'),
          ('resgates',     'resgates.mexer'),
          ('aniversarios', 'aniversarios.ver'),
          ('aniversarios', 'aniversarios.mexer'),
          ('presentes',    'presentes.ver'),
          ('usuarios',     'pessoas.ver'),
          ('mural',        'mural.ver'),
          ('mural',        'mural.mexer'),
          ('mural',        'mural.arrumar'),
          ('equipe',       'equipe.ver'),
          ('equipe',       'equipe.mexer'),
          ('relatorios',   'relatorios.ver'),
          ('favoritos',    'favoritos.ver'),
          ('desejos',      'desejos.ver'),
          ('reposicao',    'reposicao.ver'),
          ('lista_espera', 'espera.ver'),
          ('leads',        'leads.ver'),
          ('leads',        'leads.mexer'),
          ('avisos',       'recados.ver'),
          ('avisos',       'recados.mexer'),
          ('avisos',       'recados.arrumar'),
          ('trilha',       'trilha.ver'),
          ('trilha',       'trilha.mexer'),
          ('trilha',       'trilha.arrumar'),
          ('agenda',       'agenda.ver'),
          ('agenda',       'agenda.mexer'),
          ('agenda',       'agenda.arrumar')
       ) as novo(velho, permissao) on novo.velho = sp.permissao
on conflict (user_id, permissao) do nothing;

-- 4c. As linhas velhas saem (o que elas davam já foi entregue acima).
delete from public.staff_permissions sp
 where exists (select 1 from public.permissoes_legado l where l.slug_velho = sp.permissao);

-- 4d. O FK entra. Daqui pra frente o catálogo é o whitelist, e permissão nova é
--     INSERT numa tabela, não `alter constraint`.
do $$
begin
  if not exists (
    select 1 from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace nsp on nsp.oid = rel.relnamespace
     where nsp.nspname = 'public' and rel.relname = 'staff_permissions'
       and con.conname = 'staff_permissions_permissao_fkey'
  ) then
    alter table public.staff_permissions
      add constraint staff_permissions_permissao_fkey
      foreign key (permissao) references public.permissoes (slug) on delete restrict;
  end if;
end $$;


-- =============================================================================
-- 5. As policies passam a falar a língua nova
-- -----------------------------------------------------------------------------
-- Elas funcionariam pela ponte da `permissao_canonica`, mas a RLS é a camada que
-- não pode depender de tradução: é ela que o PostgREST abre direto. Duas
-- ganham dono novo de propósito:
--   • `brindes_aniversario` perguntava por 'resgates' desde a 0025 (antes de os
--     aniversários terem página própria) e agora pergunta pela dela;
--   • `points_ledger` perguntava por 'relatorios' e passa a perguntar por
--     `pontos.ver`, que é a página nova do extrato. Quem cuida de relatório de
--     venda não precisa do extrato de pontos de cada pessoa.
-- O `= auth.uid()` de cada uma continua igual: ninguém perde o próprio dado.
-- =============================================================================
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.tem_permissao('pessoas.ver'));

drop policy if exists subscriptions_select_own on public.subscriptions;
create policy subscriptions_select_own on public.subscriptions
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('assinaturas.ver'));

drop policy if exists orders_select_own on public.orders;
create policy orders_select_own on public.orders
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('pedidos.ver'));

drop policy if exists order_items_select_own on public.order_items;
create policy order_items_select_own on public.order_items
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and (o.user_id = auth.uid() or public.tem_permissao('pedidos.ver'))
    )
  );

drop policy if exists points_ledger_select_own on public.points_ledger;
create policy points_ledger_select_own on public.points_ledger
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('pontos.ver'));

drop policy if exists redemptions_select_own on public.redemptions;
create policy redemptions_select_own on public.redemptions
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('resgates.ver'));

drop policy if exists user_achievements_select_own on public.user_achievements;
create policy user_achievements_select_own on public.user_achievements
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('pessoas.ver'));

drop policy if exists brindes_select_own on public.brindes_aniversario;
create policy brindes_select_own on public.brindes_aniversario
  for select to authenticated
  using (user_id = auth.uid() or public.tem_permissao('aniversarios.ver'));


-- =============================================================================
-- 6. As funções que precisavam SEPARAR ver de mexer
-- -----------------------------------------------------------------------------
-- Só entram aqui as que mudam de nível. Todas as outras (as de leitura, e a
-- `admin_marcar_entregue`, que sempre pediu 'entregas') seguem intactas: o slug
-- antigo delas atravessa a `permissao_canonica` e cai no lugar certo.
--
-- O corpo de cada uma é IDÊNTICO ao que já estava no ar (extraído da última
-- migration que a definiu); muda a linha da trava e mais nada. `create or
-- replace` preserva os grants.
-- =============================================================================

-- a loja e o clube: dar baixa deixou de ser a mesma chave de enxergar ----

-- admin_marcar_resgate_usado -> resgates.mexer
create or replace function public.admin_marcar_resgate_usado(p_redemption_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_red public.redemptions;
begin
  if not public.tem_permissao('resgates.mexer') then
    raise exception 'sem permissão pra dar baixa em resgate';
  end if;

  select * into v_red from public.redemptions where id = p_redemption_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'resgate não encontrado');
  end if;

  if v_red.status = 'usado' then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'usado_em', v_red.usado_em);
  end if;

  if v_red.status not in ('solicitado', 'aprovado') then
    return jsonb_build_object('ok', false, 'erro', 'esse resgate já foi ' || v_red.status);
  end if;

  update public.redemptions
     set status = 'usado', usado_em = now(), usado_por = v_uid, updated_at = now()
   where id = p_redemption_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'resgate_usado', 'redemptions', p_redemption_id::text,
          jsonb_build_object('pontos', v_red.pontos_gastos));

  return jsonb_build_object('ok', true, 'usado_em', now());
end;
$$;

-- admin_brinde_usar -> aniversarios.mexer
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
  if not public.tem_permissao('aniversarios.mexer') then
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

-- a casa: moderar (reversível) e apagar (não) viraram chaves diferentes --

-- admin_mural_status -> mural.mexer
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
  if not public.tem_permissao('mural.mexer') then
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

-- admin_mural_remover -> mural.arrumar
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
  if not public.tem_permissao('mural.arrumar') then
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

-- admin_aviso_salvar -> recados.mexer
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
  if not public.tem_permissao('recados.mexer') then
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

-- admin_aviso_remover -> recados.arrumar
create or replace function public.admin_aviso_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('recados.arrumar') then
    raise exception 'sem permissão';
  end if;
  delete from public.avisos_casa where id = p_id;
  return true;
end;
$$;

-- admin_trilha_salvar -> trilha.mexer
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
  if not public.tem_permissao('trilha.mexer') then
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

-- admin_trilha_remover -> trilha.arrumar
create or replace function public.admin_trilha_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('trilha.arrumar') then
    raise exception 'sem permissão';
  end if;
  delete from public.playlists_casa where id = p_id;
  return true;
end;
$$;

-- admin_evento_salvar -> agenda.mexer
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
  if not public.tem_permissao('agenda.mexer') then
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

-- admin_evento_remover -> agenda.arrumar
create or replace function public.admin_evento_remover(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.tem_permissao('agenda.arrumar') then
    raise exception 'sem permissão';
  end if;
  delete from public.events where id = p_id;
  return true;
end;
$$;

-- os eventos e o console --------------------------------------------------

-- admin_lead_evento_status -> leads.mexer
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
  if not public.tem_permissao('leads.mexer') then
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

-- admin_buscar_pessoa -> equipe.mexer
create or replace function public.admin_buscar_pessoa(p_busca text)
returns table (
  id     uuid,
  nome   text,
  email  text,
  papel  text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('equipe.mexer') then
    raise exception 'sem permissão pra mexer na equipe';
  end if;
  if v_busca is null or length(v_busca) < 3 then
    return;
  end if;

  return query
    select p.id, coalesce(p.full_name, ''), coalesce(u.email::text, ''), p.role
    from public.profiles p
    left join auth.users u on u.id = p.id
    where p.full_name ilike '%' || v_busca || '%'
       or u.email     ilike '%' || v_busca || '%'
    order by p.full_name nulls last
    limit 20;
end;
$$;

-- o quadro de pautas: ler o combinado do dia é uma coisa, reorganizar o
-- quadro é outra, e apagar o que a equipe escreveu é uma terceira. As de
-- LEITURA (`admin_quadros_listar`, `admin_quadro_abrir`, `admin_pauta_ver`,
-- `admin_pauta_comentarios`, `admin_pautas_equipe`) não estão aqui: elas
-- continuam pedindo 'pautas', que agora quer dizer `pautas.ver`. -------------

-- admin_quadro_salvar -> pautas.mexer
create or replace function public.admin_quadro_salvar(
  p_id   uuid default null,
  p_nome text default null,
  p_cor  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_cor  text := coalesce(nullif(btrim(coalesce(p_cor, '')), ''), 'coral');
  v_id   uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nos quadros';
  end if;
  if char_length(v_nome) < 1 or char_length(v_nome) > 60 then
    return jsonb_build_object('ok', false, 'erro', 'dá um nome de até 60 letras pro quadro');
  end if;
  if v_cor not in ('neutro', 'coral', 'gold', 'green', 'olive', 'blue') then
    v_cor := 'coral';
  end if;

  if p_id is null then
    insert into public.pauta_quadros (nome, cor, ordem, criado_por)
    values (v_nome, v_cor,
            coalesce((select max(ordem) + 1 from public.pauta_quadros), 0),
            v_uid)
    returning id into v_id;

    -- Quadro nasce com um grupo, senão a primeira pauta não teria onde cair.
    insert into public.pauta_grupos (quadro_id, nome, cor, ordem)
    values (v_id, 'o dia a dia', 'neutro', 0);
  else
    update public.pauta_quadros
       set nome = v_nome, cor = v_cor, updated_at = now()
     where id = p_id
    returning id into v_id;
    if v_id is null then
      return jsonb_build_object('ok', false, 'erro', 'esse quadro não existe mais');
    end if;
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, case when p_id is null then 'quadro_criado' else 'quadro_editado' end,
          'pauta_quadros', v_id::text, jsonb_build_object('nome', v_nome));

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- admin_quadro_arquivar -> pautas.mexer
create or replace function public.admin_quadro_arquivar(p_id uuid, p_arquivar boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nos quadros';
  end if;
  update public.pauta_quadros set arquivado = coalesce(p_arquivar, true), updated_at = now()
   where id = p_id returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'esse quadro não existe mais');
  end if;
  return jsonb_build_object('ok', true, 'arquivado', coalesce(p_arquivar, true));
end;
$$;

-- admin_quadro_remover -> pautas.arrumar
create or replace function public.admin_quadro_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_quadro public.pauta_quadros;
  v_itens  bigint;
begin
  if not public.tem_permissao('pautas.arrumar') then
    raise exception 'sem permissão pra mexer nos quadros';
  end if;

  select * into v_quadro from public.pauta_quadros where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;
  if not (public.is_owner() or v_quadro.criado_por = v_uid) then
    return jsonb_build_object('ok', false, 'erro',
      'esse quadro é de quem criou. dá pra arquivar, apagar só quem criou ou o adm do Casa');
  end if;

  select count(*) into v_itens from public.pautas where quadro_id = p_id;
  if v_itens > 0 then
    return jsonb_build_object('ok', false, 'erro',
      'esse quadro ainda tem ' || v_itens || ' pauta(s) dentro. move ou apaga elas antes, ou arquiva o quadro');
  end if;

  delete from public.pauta_quadros where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'quadro_removido', 'pauta_quadros', p_id::text,
          jsonb_build_object('nome', v_quadro.nome));

  return jsonb_build_object('ok', true);
end;
$$;

-- admin_grupo_salvar -> pautas.mexer
create or replace function public.admin_grupo_salvar(
  p_id        uuid default null,
  p_quadro_id uuid default null,
  p_nome      text default null,
  p_cor       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_nome text := btrim(coalesce(p_nome, ''));
  v_cor  text := coalesce(nullif(btrim(coalesce(p_cor, '')), ''), 'coral');
  v_id   uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nos grupos';
  end if;
  if char_length(v_nome) < 1 or char_length(v_nome) > 60 then
    return jsonb_build_object('ok', false, 'erro', 'dá um nome de até 60 letras pro grupo');
  end if;
  if v_cor not in ('neutro', 'coral', 'gold', 'green', 'olive', 'blue') then
    v_cor := 'coral';
  end if;

  if p_id is null then
    if p_quadro_id is null or not exists (select 1 from public.pauta_quadros where id = p_quadro_id) then
      return jsonb_build_object('ok', false, 'erro', 'esse quadro não existe mais');
    end if;
    insert into public.pauta_grupos (quadro_id, nome, cor, ordem)
    values (p_quadro_id, v_nome, v_cor,
            coalesce((select max(ordem) + 1 from public.pauta_grupos where quadro_id = p_quadro_id), 0))
    returning id into v_id;
  else
    update public.pauta_grupos set nome = v_nome, cor = v_cor where id = p_id
    returning id into v_id;
    if v_id is null then
      return jsonb_build_object('ok', false, 'erro', 'esse grupo não existe mais');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- admin_grupo_recolher -> pautas.mexer
create or replace function public.admin_grupo_recolher(p_id uuid, p_recolhido boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nos grupos';
  end if;
  update public.pauta_grupos set recolhido = coalesce(p_recolhido, true)
   where id = p_id returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'esse grupo não existe mais');
  end if;
  return jsonb_build_object('ok', true, 'recolhido', coalesce(p_recolhido, true));
end;
$$;

-- admin_grupo_remover -> pautas.arrumar
create or replace function public.admin_grupo_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_grupo public.pauta_grupos;
  v_itens bigint;
begin
  if not public.tem_permissao('pautas.arrumar') then
    raise exception 'sem permissão pra mexer nos grupos';
  end if;

  select * into v_grupo from public.pauta_grupos where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  select count(*) into v_itens from public.pautas where grupo_id = p_id;
  if v_itens > 0 then
    return jsonb_build_object('ok', false, 'erro',
      'esse grupo tem ' || v_itens || ' pauta(s) dentro. move elas pra outro grupo antes');
  end if;

  delete from public.pauta_grupos where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'grupo_removido', 'pauta_grupos', p_id::text,
          jsonb_build_object('nome', v_grupo.nome));

  return jsonb_build_object('ok', true);
end;
$$;

-- admin_pauta_salvar -> pautas.mexer
create or replace function public.admin_pauta_salvar(
  p_id          uuid,
  p_quadro_id   uuid,
  p_grupo_id    uuid,
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
  v_quadro uuid := p_quadro_id;
  v_grupo  uuid := p_grupo_id;
  v_id     uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;
  if char_length(v_titulo) < 1 or char_length(v_titulo) > 120 then
    return jsonb_build_object('ok', false, 'erro', 'a pauta precisa de um título de até 120 letras');
  end if;
  if v_prio not in ('baixa', 'normal', 'alta') then
    v_prio := 'normal';
  end if;
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
    if v_quadro is null then
      select id into v_quadro from public.pauta_quadros where not arquivado order by ordem, created_at limit 1;
    end if;
    if v_quadro is null then
      return jsonb_build_object('ok', false, 'erro', 'cria um quadro antes de escrever a primeira pauta');
    end if;
    -- Grupo não informado (ou de outro quadro) cai no primeiro do quadro.
    if v_grupo is null or not exists (select 1 from public.pauta_grupos where id = v_grupo and quadro_id = v_quadro) then
      select id into v_grupo from public.pauta_grupos where quadro_id = v_quadro order by ordem, created_at limit 1;
    end if;

    insert into public.pautas (titulo, briefing, atribuido_a, prazo, prioridade, criado_por,
                               quadro_id, grupo_id, ordem)
    values (v_titulo, nullif(btrim(coalesce(p_briefing, '')), ''), p_atribuido_a, p_prazo, v_prio, v_uid,
            v_quadro, v_grupo,
            coalesce((select max(ordem) + 1 from public.pautas where grupo_id = v_grupo), 0))
    returning id into v_id;
  else
    update public.pautas
       set titulo      = v_titulo,
           briefing    = nullif(btrim(coalesce(p_briefing, '')), ''),
           atribuido_a = p_atribuido_a,
           prazo       = p_prazo,
           prioridade  = v_prio,
           grupo_id    = coalesce(
                           (select g.id from public.pauta_grupos g
                             where g.id = p_grupo_id and g.quadro_id = public.pautas.quadro_id),
                           grupo_id),
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

-- admin_pauta_celula -> pautas.mexer
create or replace function public.admin_pauta_celula(p_id uuid, p_campo text, p_valor text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_campo text := btrim(coalesce(p_campo, ''));
  v_valor text := nullif(btrim(coalesce(p_valor, '')), '');
  v_id    uuid;
  v_alvo  uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;

  if v_campo = 'status' then
    if v_valor is null or v_valor not in ('aberta', 'fazendo', 'travada', 'feita') then
      return jsonb_build_object('ok', false, 'erro', 'esse estado não existe no quadro');
    end if;
    update public.pautas
       set status        = v_valor,
           concluida_em  = case when v_valor = 'feita' then now() else null end,
           concluida_por = case when v_valor = 'feita' then v_uid else null end,
           updated_at    = now()
     where id = p_id returning id into v_id;

  elsif v_campo = 'prioridade' then
    if v_valor is null or v_valor not in ('baixa', 'normal', 'alta') then
      return jsonb_build_object('ok', false, 'erro', 'essa urgência não existe');
    end if;
    update public.pautas set prioridade = v_valor, updated_at = now()
     where id = p_id returning id into v_id;

  elsif v_campo = 'prazo' then
    update public.pautas set prazo = v_valor::date, updated_at = now()
     where id = p_id returning id into v_id;

  elsif v_campo = 'atribuido_a' then
    v_alvo := v_valor::uuid;
    if v_alvo is not null
       and not exists (
         select 1 from public.profiles p
          where p.id = v_alvo
            and (p.role = 'owner'
                 or exists (select 1 from public.staff_permissions sp where sp.user_id = p.id))
       ) then
      return jsonb_build_object('ok', false, 'erro', 'essa pessoa não é da equipe do console');
    end if;
    update public.pautas set atribuido_a = v_alvo, updated_at = now()
     where id = p_id returning id into v_id;

  elsif v_campo = 'grupo_id' then
    v_alvo := v_valor::uuid;
    if v_alvo is null or not exists (
         select 1 from public.pauta_grupos g
          join public.pautas p on p.quadro_id = g.quadro_id
         where g.id = v_alvo and p.id = p_id) then
      return jsonb_build_object('ok', false, 'erro', 'esse grupo não é deste quadro');
    end if;
    update public.pautas
       set grupo_id = v_alvo,
           ordem    = coalesce((select max(ordem) + 1 from public.pautas where grupo_id = v_alvo), 0),
           updated_at = now()
     where id = p_id returning id into v_id;

  else
    return jsonb_build_object('ok', false, 'erro', 'esse campo não se edita por aqui');
  end if;

  if v_id is null then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;
  return jsonb_build_object('ok', true, 'campo', v_campo, 'valor', v_valor);
exception
  -- Data ruim e uuid ruim NÃO estouram no mesmo código: 'banana'::date é 22007
  -- (invalid_datetime_format) e 'banana'::uuid é 22P02 (invalid_text_representation).
  -- Sem os dois na lista, uma data digitada errada subia como erro cru do Postgres
  -- em vez do recado da casa.
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    return jsonb_build_object('ok', false, 'erro', 'esse valor não serve pra esse campo');
end;
$$;

-- admin_pauta_ordenar -> pautas.mexer
create or replace function public.admin_pauta_ordenar(p_id uuid, p_direcao text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_pauta   public.pautas;
  v_vizinho public.pautas;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra mexer nas pautas';
  end if;

  select * into v_pauta from public.pautas where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;

  if p_direcao = 'cima' then
    select * into v_vizinho from public.pautas
     where grupo_id is not distinct from v_pauta.grupo_id
       and quadro_id = v_pauta.quadro_id
       and (ordem, created_at) < (v_pauta.ordem, v_pauta.created_at)
     order by ordem desc, created_at desc limit 1 for update;
  elsif p_direcao = 'baixo' then
    select * into v_vizinho from public.pautas
     where grupo_id is not distinct from v_pauta.grupo_id
       and quadro_id = v_pauta.quadro_id
       and (ordem, created_at) > (v_pauta.ordem, v_pauta.created_at)
     order by ordem asc, created_at asc limit 1 for update;
  else
    return jsonb_build_object('ok', false, 'erro', 'só dá pra mover pra cima ou pra baixo');
  end if;

  if v_vizinho.id is null then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  -- Empate de `ordem` (todo mundo em 0, por exemplo) não trocaria nada só
  -- invertendo os valores; por isso a troca é feita com números distintos.
  update public.pautas set ordem = v_vizinho.ordem, updated_at = now() where id = v_pauta.id;
  update public.pautas set ordem = case when v_vizinho.ordem = v_pauta.ordem
                                        then case when p_direcao = 'cima' then v_pauta.ordem + 1
                                                  else v_pauta.ordem - 1 end
                                        else v_pauta.ordem end,
                           updated_at = now()
   where id = v_vizinho.id;

  return jsonb_build_object('ok', true);
end;
$$;

-- admin_pauta_status -> pautas.mexer
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
  if not public.tem_permissao('pautas.mexer') then
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

-- admin_pauta_comentar -> pautas.mexer
create or replace function public.admin_pauta_comentar(p_pauta_id uuid, p_texto text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_texto text := btrim(coalesce(p_texto, ''));
  v_id    uuid;
begin
  if not public.tem_permissao('pautas.mexer') then
    raise exception 'sem permissão pra comentar';
  end if;
  if char_length(v_texto) < 1 or char_length(v_texto) > 2000 then
    return jsonb_build_object('ok', false, 'erro', 'escreve o recado (até 2000 letras)');
  end if;
  if not exists (select 1 from public.pautas where id = p_pauta_id) then
    return jsonb_build_object('ok', false, 'erro', 'essa pauta não existe mais');
  end if;

  insert into public.pauta_updates (pauta_id, user_id, autor_nome, texto)
  values (p_pauta_id, v_uid,
          (select coalesce(full_name, '') from public.profiles where id = v_uid),
          v_texto)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- admin_pauta_remover -> pautas.arrumar
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
  if not public.tem_permissao('pautas.arrumar') then
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

-- admin_pauta_comentario_remover -> pautas.arrumar
create or replace function public.admin_pauta_comentario_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_com public.pauta_updates;
begin
  if not public.tem_permissao('pautas.arrumar') then
    raise exception 'sem permissão pra mexer nos comentários';
  end if;
  select * into v_com from public.pauta_updates where id = p_id;
  if not found then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;
  if not (public.is_owner() or v_com.user_id = v_uid) then
    return jsonb_build_object('ok', false, 'erro', 'esse recado é de quem escreveu');
  end if;
  delete from public.pauta_updates where id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;

-- =============================================================================
-- 7. O console se olhando: catálogo, minhas permissões e a tela da equipe
-- =============================================================================

-- ---------------------------------------------------------------------------
-- admin_permissoes_catalogo — o dicionário inteiro, já agrupado, pra tela da
-- equipe desenhar seção por seção. Em `jsonb` de propósito: é leitura composta,
-- e `returns table` com uma dúzia de colunas é onde mora o erro de tipo que
-- derrubou cinco abas da 0017 até a 0042.
-- ---------------------------------------------------------------------------
create or replace function public.admin_permissoes_catalogo()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.tem_permissao('equipe.ver') then
    raise exception 'sem permissão pra ver o catálogo de permissões';
  end if;

  return coalesce((
    select jsonb_agg(s order by s->>'ordem')
      from (
        select jsonb_build_object(
                 'slug',      sec.slug,
                 'rotulo',    sec.rotulo,
                 'descricao', coalesce(sec.descricao, ''),
                 'ordem',     lpad(sec.ordem::text, 4, '0'),
                 'paginas',   coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'slug',      pag.slug,
                            'rotulo',    pag.rotulo,
                            'descricao', coalesce(pag.descricao, ''),
                            'aba',       pag.aba,
                            'acoes',     coalesce((
                              select jsonb_agg(jsonb_build_object(
                                       'slug',      perm.slug,
                                       'acao',      perm.acao,
                                       'nivel',     perm.nivel,
                                       'rotulo',    perm.rotulo,
                                       'descricao', coalesce(perm.descricao, ''))
                                       order by perm.nivel)
                                from public.permissoes perm
                               where perm.pagina_slug = pag.slug), '[]'::jsonb))
                            order by pag.ordem)
                     from public.permissao_paginas pag
                    where pag.secao_slug = sec.slug), '[]'::jsonb)
               ) as s
          from public.permissao_secoes sec
      ) t
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_minhas_permissoes — mesmo contrato da 0032, com duas diferenças:
--   • `permissoes` volta EXPANDIDA (quem tem `mural.arrumar` recebe também
--     `mural.mexer` e `mural.ver`). O front testa `pode('mural.ver')` pra
--     decidir se desenha a aba, e não deve ter que saber a regra da
--     hierarquia: a régua é do banco, e o banco entrega já resolvida;
--   • `alcance` vem legível, agrupado por seção e página, pra a tela "tua
--     conta" dizer o que a pessoa alcança sem precisar do catálogo inteiro
--     (que é da permissão `equipe.ver`, e nem todo mundo tem).
-- ---------------------------------------------------------------------------
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
  v_tudo     boolean;
  v_slugs    text[];
begin
  if v_uid is null then
    raise exception 'precisa estar logado';
  end if;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('console', false);
  end if;

  v_pendente := public.senha_inicial_pendente();
  v_tudo     := v_prof.role = 'owner' and not v_pendente;

  -- Os slugs que esta pessoa alcança de verdade, já com a hierarquia resolvida.
  if v_pendente then
    v_slugs := '{}';
  elsif v_tudo then
    select coalesce(array_agg(p.slug), '{}') into v_slugs from public.permissoes p;
  else
    select coalesce(array_agg(distinct alcancada.slug), '{}') into v_slugs
      from public.staff_permissions sp
      join public.permissoes tenho     on tenho.slug = sp.permissao
      join public.permissoes alcancada on alcancada.pagina_slug = tenho.pagina_slug
                                      and alcancada.nivel <= tenho.nivel
     where sp.user_id = v_uid;
  end if;

  return jsonb_build_object(
    'console',        public.pode_entrar_no_console() or (v_prof.master and v_pendente),
    'nome',           coalesce(v_prof.full_name, ''),
    'papel',          v_prof.role,
    'master',         v_prof.master,
    'senha_trocada',  not v_pendente,
    'permissoes',     to_jsonb(v_slugs),
    'alcance',        coalesce((
      select jsonb_agg(linha order by linha->>'ordem')
        from (
          select jsonb_build_object(
                   'secao',  sec.rotulo,
                   'pagina', pag.rotulo,
                   'ordem',  lpad(sec.ordem::text, 4, '0') || lpad(pag.ordem::text, 4, '0'),
                   'acoes',  jsonb_agg(perm.rotulo order by perm.nivel)
                 ) as linha
            from public.permissoes perm
            join public.permissao_paginas pag on pag.slug = perm.pagina_slug
            join public.permissao_secoes  sec on sec.slug = pag.secao_slug
           where perm.slug = any (v_slugs)
           group by sec.rotulo, pag.rotulo, sec.ordem, pag.ordem
        ) t), '[]'::jsonb),
    'tudo',           v_tudo
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_definir_permissoes — dá e tira, de uma pessoa por vez. A lista chega
-- inteira e substitui a anterior. Mudanças em relação à 0017:
--   • pede `equipe.mexer` (ver a equipe e mexer nela viraram coisas separadas);
--   • recusa slug que não está no catálogo, dizendo qual é (antes, um slug
--     errado batia num CHECK e voltava "violates check constraint");
--   • o audit_log guarda o ANTES e o DEPOIS. Num sistema de permissão, "quem
--     tirou o acesso da fulana?" é a pergunta que sempre aparece depois.
-- As travas contra escalada continuam: ninguém edita as próprias, o adm do Casa
-- e o master não têm permissão editável, e só o dono delega a página da equipe.
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
  v_uid    uuid := auth.uid();
  v_alvo   public.profiles;
  v_lista  text[] := coalesce(p_permissoes, '{}');
  v_antes  text[];
  v_ruim   text;
begin
  if not public.tem_permissao('equipe.mexer') then
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
    return jsonb_build_object('ok', false, 'erro', 'o adm do Casa já tem tudo, não há o que ajustar aqui');
  end if;

  -- Slug fora do catálogo para aqui, com nome e sobrenome.
  select perm into v_ruim
    from unnest(v_lista) as perm
   where not exists (select 1 from public.permissoes p where p.slug = perm)
   limit 1;
  if v_ruim is not null then
    return jsonb_build_object('ok', false, 'erro', 'essa permissão não existe: ' || v_ruim);
  end if;

  if exists (
    select 1 from public.permissoes p
     where p.slug = any (v_lista) and p.pagina_slug = 'equipe'
  ) and not public.is_owner() then
    return jsonb_build_object('ok', false, 'erro', 'só o adm do Casa pode delegar o cuidado da equipe');
  end if;

  select coalesce(array_agg(permissao order by permissao), '{}')
    into v_antes
    from public.staff_permissions where user_id = p_user_id;

  delete from public.staff_permissions
   where user_id = p_user_id
     and not (permissao = any (v_lista));

  insert into public.staff_permissions (user_id, permissao, granted_by)
  select p_user_id, perm, v_uid from unnest(v_lista) as perm
  on conflict (user_id, permissao) do nothing;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'permissoes_definidas', 'staff_permissions', p_user_id::text,
          jsonb_build_object('antes', to_jsonb(v_antes), 'depois', to_jsonb(v_lista)));

  return jsonb_build_object('ok', true, 'permissoes', to_jsonb(v_lista));
end;
$$;


-- =============================================================================
-- 8. As assinaturas — a página que faltava
-- -----------------------------------------------------------------------------
-- O clube é o principal benefício do site e o console era CEGO pra ele: quando
-- alguém ligava dizendo "paguei e não caiu", não havia tela nenhuma pra olhar.
-- Só leitura mais um conserto, e o conserto é de propósito o mais inofensivo
-- que existe: esticar o período já pago. Ele não cobra, não estorna e não
-- contradiz o Asaas (lá a assinatura segue no ciclo dela); só faz o benefício
-- durar mais deste lado. Pausar, retomar, subir e descer de plano continuam
-- sendo das Edge Functions, que falam com o gateway.
-- =============================================================================
create or replace function public.admin_assinaturas(
  p_busca  text default null,
  p_status text default null,
  p_limite int  default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('assinaturas.ver') then
    raise exception 'sem permissão pra ver as assinaturas';
  end if;

  return coalesce((
    select jsonb_agg(linha order by (linha->>'criada_em') desc)
      from (
        select jsonb_build_object(
                 'id',                 s.id,
                 'pessoa_id',          s.user_id,
                 'pessoa',             coalesce(pr.full_name, ''),
                 'email',              coalesce(u.email::text, ''),
                 'plano',              coalesce(t.nome, s.tier_slug),
                 'tier_slug',          s.tier_slug,
                 'status',             s.status,
                 'vale_ate',           s.current_period_end,
                 'vencida',            s.current_period_end is not null and s.current_period_end < now(),
                 'de_presente',        s.presente_id is not null,
                 'no_gateway',         s.asaas_subscription_id is not null,
                 'descida_agendada',   coalesce(td.nome, s.scheduled_downgrade_to),
                 'criada_em',          s.created_at
               ) as linha
          from public.subscriptions s
          left join public.profiles pr on pr.id   = s.user_id
          left join auth.users      u  on u.id    = s.user_id
          left join public.tiers    t  on t.slug  = s.tier_slug
          left join public.tiers    td on td.slug = s.scheduled_downgrade_to
         where (p_status is null or p_status = '' or s.status = p_status)
           and (
             v_busca is null
             or coalesce(pr.full_name, '') ilike '%' || v_busca || '%'
             or coalesce(u.email::text, '') ilike '%' || v_busca || '%'
           )
         order by s.created_at desc
         limit greatest(1, least(coalesce(p_limite, 200), 1000))
      ) t
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_assinatura_esticar — dias de cortesia no período já pago.
-- Nunca cobra e nunca encurta: se a data já passou, conta a partir de hoje.
-- Reespelha o tier no `profiles` quando a assinatura volta a conceder
-- benefício (a GUC é a mesma que o 0008 usa pro write server-side).
-- ---------------------------------------------------------------------------
create or replace function public.admin_assinatura_esticar(p_id uuid, p_dias integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_sub  public.subscriptions;
  v_dias integer := coalesce(p_dias, 0);
  v_novo timestamptz;
begin
  if not public.tem_permissao('assinaturas.arrumar') then
    raise exception 'sem permissão pra mexer em assinatura';
  end if;
  if v_dias < 1 or v_dias > 90 then
    return jsonb_build_object('ok', false, 'erro', 'escolhe de 1 a 90 dias');
  end if;

  select * into v_sub from public.subscriptions where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'assinatura não encontrada');
  end if;
  if v_sub.status = 'cancelada' then
    return jsonb_build_object('ok', false, 'erro',
      'essa assinatura foi encerrada, esticar aqui não devolve o plano');
  end if;

  v_novo := greatest(now(), coalesce(v_sub.current_period_end, now())) + make_interval(days => v_dias);

  update public.subscriptions
     set current_period_end = v_novo, updated_at = now()
   where id = p_id;

  -- Volta a valer? Então o cache do perfil tem que dizer a mesma coisa.
  if v_sub.status in ('ativa', 'pausada') then
    perform set_config('casa.trusted_points', 'on', true);
    update public.profiles set tier_slug = v_sub.tier_slug, updated_at = now()
     where id = v_sub.user_id;
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'assinatura_esticada', 'subscriptions', p_id::text,
          jsonb_build_object('dias', v_dias, 'de', v_sub.current_period_end, 'para', v_novo));

  return jsonb_build_object('ok', true, 'vale_ate', v_novo);
end;
$$;


-- =============================================================================
-- 9. Os pontos — a outra página que faltava
-- -----------------------------------------------------------------------------
-- O `points_ledger` é append-only e é a fonte da verdade do saldo. A casa não
-- tinha como OLHAR o extrato de ninguém, nem como consertar quando o webhook do
-- pagamento falhava e o ponto não caía. As duas coisas entram aqui, e o ajuste
-- é um LANÇAMENTO como qualquer outro: nada de `update` no saldo, que é cache.
-- =============================================================================
create or replace function public.admin_pontos_pessoas(
  p_busca  text default null,
  p_limite int  default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('pontos.ver') then
    raise exception 'sem permissão pra ver os pontos';
  end if;
  if v_busca is null or char_length(v_busca) < 3 then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(linha)
      from (
        select jsonb_build_object(
                 'id',     p.id,
                 'nome',   coalesce(p.full_name, ''),
                 'email',  coalesce(u.email::text, ''),
                 'saldo',  coalesce(p.points_balance, 0),
                 'plano',  coalesce(t.nome, '')
               ) as linha
          from public.profiles p
          left join auth.users u on u.id = p.id
          left join public.tiers t on t.slug = p.tier_slug
         where coalesce(p.full_name, '') ilike '%' || v_busca || '%'
            or coalesce(u.email::text, '') ilike '%' || v_busca || '%'
         order by p.full_name nulls last
         limit greatest(1, least(coalesce(p_limite, 30), 100))
      ) t
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_pontos_extrato(
  p_user_id uuid,
  p_limite  int default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_prof   public.profiles;
  v_email  text;
  v_ledger integer;
begin
  if not public.tem_permissao('pontos.ver') then
    raise exception 'sem permissão pra ver os pontos';
  end if;

  select * into v_prof from public.profiles where id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'pessoa não encontrada');
  end if;

  select coalesce(u.email::text, '') into v_email from auth.users u where u.id = p_user_id;
  select coalesce(sum(delta), 0)::integer into v_ledger
    from public.points_ledger where user_id = p_user_id;

  return jsonb_build_object(
    'ok',           true,
    'id',           v_prof.id,
    'nome',         coalesce(v_prof.full_name, ''),
    'email',        coalesce(v_email, ''),
    'plano',        coalesce((select t.nome from public.tiers t where t.slug = v_prof.tier_slug), ''),
    'saldo_cache',  coalesce(v_prof.points_balance, 0),
    'saldo_ledger', v_ledger,
    'lancamentos',  coalesce((
      select jsonb_agg(jsonb_build_object(
               'id',        l.id,
               'delta',     l.delta,
               'motivo',    l.motivo,
               'descricao', coalesce(l.descricao, ''),
               'ref_type',  coalesce(l.ref_type, ''),
               'quando',    l.created_at)
               order by l.created_at desc)
        from (
          select * from public.points_ledger
           where user_id = p_user_id
           order by created_at desc
           limit greatest(1, least(coalesce(p_limite, 100), 500))
        ) l), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_pontos_ajustar — o lançamento manual, com motivo obrigatório.
-- Pode ser negativo (tirar ponto que caiu errado) e o saldo PODE ficar negativo,
-- pelo mesmo motivo do estorno do webhook: a pessoa fica devendo, e o resgate
-- só volta a passar quando o saldo cobre. Teto de 5.000 por lançamento pra um
-- dedo escorregado no teclado não virar mil reais em mimo.
-- ---------------------------------------------------------------------------
create or replace function public.admin_pontos_ajustar(
  p_user_id uuid,
  p_delta   integer,
  p_motivo  text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_delta  integer := coalesce(p_delta, 0);
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_saldo  integer;
begin
  if not public.tem_permissao('pontos.arrumar') then
    raise exception 'sem permissão pra ajustar pontos';
  end if;
  if v_delta = 0 then
    return jsonb_build_object('ok', false, 'erro', 'diz quantos pontos, pra mais ou pra menos');
  end if;
  if abs(v_delta) > 5000 then
    return jsonb_build_object('ok', false, 'erro', 'um ajuste vai até 5.000 pontos de cada vez');
  end if;
  if char_length(v_motivo) < 3 then
    return jsonb_build_object('ok', false, 'erro', 'escreve o motivo, é o que explica esse lançamento depois');
  end if;
  if char_length(v_motivo) > 120 then
    v_motivo := left(v_motivo, 120);
  end if;

  if not exists (select 1 from public.profiles where id = p_user_id) then
    return jsonb_build_object('ok', false, 'erro', 'pessoa não encontrada');
  end if;

  insert into public.points_ledger (user_id, delta, motivo, descricao, ref_type, ref_id)
  values (p_user_id, v_delta, 'ajuste da casa', v_motivo, 'ajuste', gen_random_uuid()::text);

  select coalesce(sum(delta), 0)::integer into v_saldo
    from public.points_ledger where user_id = p_user_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'pontos_ajustados', 'points_ledger', p_user_id::text,
          jsonb_build_object('delta', v_delta, 'motivo', v_motivo, 'saldo', v_saldo));

  return jsonb_build_object('ok', true, 'delta', v_delta, 'saldo', v_saldo);
end;
$$;


-- =============================================================================
-- 10. Os consertos das outras páginas
-- =============================================================================

-- ---------------------------------------------------------------------------
-- admin_pedido_status — mudar o estado do pedido na mão.
-- A 0017 só sabia empurrar pra 'entregue', e sem volta: marcou errado, a fila
-- passava a mentir pra sempre. Aqui dá pra voltar. Duas portas ficam fechadas
-- de propósito: 'pendente' (pedido que nunca foi pago é assunto do gateway) e
-- 'estornado' (quem carimba isso é o webhook, quando o dinheiro volta).
-- ---------------------------------------------------------------------------
create or replace function public.admin_pedido_status(p_order_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_ord  public.orders;
  v_novo text := btrim(coalesce(p_status, ''));
begin
  if not public.tem_permissao('pedidos.arrumar') then
    raise exception 'sem permissão pra arrumar pedido';
  end if;
  if v_novo not in ('pago', 'preparando', 'pronto', 'entregue', 'cancelado') then
    return jsonb_build_object('ok', false, 'erro', 'esse estado não existe por aqui');
  end if;

  select * into v_ord from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'pedido não encontrado');
  end if;
  if v_ord.status = 'pendente' then
    return jsonb_build_object('ok', false, 'erro',
      'esse pedido ainda não foi pago, e quem confirma pagamento é o gateway');
  end if;
  if v_ord.status = 'estornado' then
    return jsonb_build_object('ok', false, 'erro',
      'esse pedido foi estornado, e isso vem do gateway, não daqui');
  end if;
  if v_ord.status = v_novo then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'status', v_novo);
  end if;

  update public.orders
     set status       = v_novo,
         entregue_em  = case when v_novo = 'entregue' then coalesce(entregue_em, now()) else null end,
         entregue_por = case when v_novo = 'entregue' then coalesce(entregue_por, v_uid) else null end,
         updated_at   = now()
   where id = p_order_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'pedido_status_arrumado', 'orders', p_order_id::text,
          jsonb_build_object('de', v_ord.status, 'para', v_novo));

  return jsonb_build_object('ok', true, 'status', v_novo);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_resgate_desfazer — o conserto que mais faltava.
-- Resgate errado (a pessoa clicou sem querer, ou a casa não tinha o mimo)
-- custava os pontos pra sempre, porque o ledger é append-only e ninguém tinha
-- como lançar a volta. Aqui a volta é OUTRO lançamento, positivo, idempotente
-- por (ref_type, ref_id): reenviar o pedido não devolve duas vezes. Se a
-- recompensa tinha estoque, ele volta; se tinha cupom, ele sai de circulação.
-- ---------------------------------------------------------------------------
create or replace function public.admin_resgate_desfazer(
  p_redemption_id uuid,
  p_motivo        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_red    public.redemptions;
  v_nome   text;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_ja     boolean;
  v_codigo text;
begin
  if not public.tem_permissao('resgates.arrumar') then
    raise exception 'sem permissão pra desfazer resgate';
  end if;

  -- Trava a linha da PESSOA antes da do resgate, a mesma ordem da
  -- `redeem_reward` (0013). Ordem única = ninguém trava ninguém.
  select * into v_red from public.redemptions where id = p_redemption_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'resgate não encontrado');
  end if;
  perform 1 from public.profiles where id = v_red.user_id for update;
  select * into v_red from public.redemptions where id = p_redemption_id for update;

  if v_red.status = 'cancelado' then
    return jsonb_build_object('ok', true, 'ja_estava', true);
  end if;

  select coalesce(rw.nome, 'recompensa') into v_nome
    from public.rewards_catalog rw where rw.id = v_red.reward_id;
  v_nome := coalesce(v_nome, 'recompensa');

  -- A devolução dos pontos. O índice único (ref_type, ref_id) da 0008 é quem
  -- garante que não devolve duas vezes.
  select exists (
    select 1 from public.points_ledger
     where ref_type = 'estorno_resgate' and ref_id = p_redemption_id::text
  ) into v_ja;

  if not v_ja and v_red.pontos_gastos > 0 then
    insert into public.points_ledger (user_id, delta, motivo, redemption_id, descricao, ref_type, ref_id)
    values (v_red.user_id, v_red.pontos_gastos, 'devolução de resgate', p_redemption_id,
            coalesce(v_motivo, v_nome), 'estorno_resgate', p_redemption_id::text);
  end if;

  -- Estoque volta pra vitrine.
  if v_red.reward_id is not null then
    update public.rewards_catalog
       set estoque = estoque + 1
     where id = v_red.reward_id and estoque is not null;
  end if;

  -- Cupom gerado por este resgate sai de circulação.
  delete from public.coupons where redemption_id = p_redemption_id
  returning codigo into v_codigo;

  update public.redemptions
     set status = 'cancelado', updated_at = now()
   where id = p_redemption_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'resgate_desfeito', 'redemptions', p_redemption_id::text,
          jsonb_build_object('pontos', v_red.pontos_gastos, 'recompensa', v_nome,
                             'motivo', coalesce(v_motivo, ''), 'cupom', coalesce(v_codigo, ''),
                             'pontos_ja_devolvidos', v_ja));

  return jsonb_build_object('ok', true, 'devolvidos', case when v_ja then 0 else v_red.pontos_gastos end);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_brinde_arrumar — o brunch de aniversário.
--   'desfazer'  o código voltou pra 'ativo' (a baixa foi no código errado)
--   'esticar'   mais 30 dias de validade (a pessoa não conseguiu vir a tempo)
-- ---------------------------------------------------------------------------
create or replace function public.admin_brinde_arrumar(p_id uuid, p_acao text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_acao   text := btrim(coalesce(p_acao, ''));
  v_brinde public.brindes_aniversario;
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_novo   date;
begin
  if not public.tem_permissao('aniversarios.arrumar') then
    raise exception 'sem permissão pra arrumar brinde';
  end if;
  if v_acao not in ('desfazer', 'esticar') then
    return jsonb_build_object('ok', false, 'erro', 'não conheço esse conserto');
  end if;

  select * into v_brinde from public.brindes_aniversario where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'brinde não encontrado');
  end if;

  if v_acao = 'desfazer' then
    if v_brinde.status <> 'usado' then
      return jsonb_build_object('ok', true, 'ja_estava', true);
    end if;
    update public.brindes_aniversario
       set status = 'ativo', usado_em = null, usado_por = null
     where id = p_id;

    insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
    values (v_uid, 'brinde_baixa_desfeita', 'brindes_aniversario', p_id::text,
            jsonb_build_object('codigo', v_brinde.codigo));

    return jsonb_build_object('ok', true, 'situacao', 'ativo');
  end if;

  v_novo := greatest(v_hoje, v_brinde.valido_ate) + 30;
  update public.brindes_aniversario set valido_ate = v_novo where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'brinde_esticado', 'brindes_aniversario', p_id::text,
          jsonb_build_object('codigo', v_brinde.codigo, 'de', v_brinde.valido_ate, 'para', v_novo));

  return jsonb_build_object('ok', true, 'valido_ate', to_char(v_novo, 'DD/MM'));
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_presente_arrumar — os dois presentes que travam.
--   'gerar_codigo'  presente PAGO que ficou sem código (o webhook caiu entre o
--                   pagamento e a `marcar_presente_pago`). Sem isso, quem pagou
--                   ficava com um presente que não existe em lugar nenhum.
--   'cancelar'      presente PENDENTE que nunca fechou o checkout, pra sair da
--                   lista. Presente pago NÃO se cancela por aqui: o código já
--                   pode estar na mão de alguém.
-- ---------------------------------------------------------------------------
create or replace function public.admin_presente_arrumar(p_id uuid, p_acao text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_acao   text := btrim(coalesce(p_acao, ''));
  v_gift   public.gift_subscriptions;
  v_codigo text;
begin
  if not public.tem_permissao('presentes.arrumar') then
    raise exception 'sem permissão pra arrumar presente';
  end if;
  if v_acao not in ('gerar_codigo', 'cancelar') then
    return jsonb_build_object('ok', false, 'erro', 'não conheço esse conserto');
  end if;

  select * into v_gift from public.gift_subscriptions where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'presente não encontrado');
  end if;

  if v_acao = 'cancelar' then
    if v_gift.status = 'cancelado' then
      return jsonb_build_object('ok', true, 'ja_estava', true);
    end if;
    if v_gift.status <> 'pendente' then
      return jsonb_build_object('ok', false, 'erro',
        'esse presente já foi pago, e o código pode estar com alguém');
    end if;
    update public.gift_subscriptions set status = 'cancelado', updated_at = now() where id = p_id;

    insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
    values (v_uid, 'presente_cancelado', 'gift_subscriptions', p_id::text, '{}'::jsonb);

    return jsonb_build_object('ok', true, 'status', 'cancelado');
  end if;

  if v_gift.codigo is not null then
    return jsonb_build_object('ok', true, 'ja_estava', true, 'codigo', v_gift.codigo);
  end if;
  if v_gift.status <> 'pago' then
    return jsonb_build_object('ok', false, 'erro',
      'só presente pago ganha código, e quem confirma o pagamento é o gateway');
  end if;

  loop
    v_codigo := 'CASA-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.gift_subscriptions where codigo = v_codigo);
  end loop;

  update public.gift_subscriptions set codigo = v_codigo, updated_at = now() where id = p_id;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'presente_codigo_gerado', 'gift_subscriptions', p_id::text,
          jsonb_build_object('codigo', v_codigo));

  return jsonb_build_object('ok', true, 'codigo', v_codigo);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_espera_remover — "me tira dessa lista".
-- O e-mail apagado NÃO vai pro audit_log: guardar o endereço num outro lugar
-- depois de a pessoa pedir pra sair é apagar da tela e manter na gaveta. Fica
-- só o domínio, que é o suficiente pra entender o que aconteceu.
-- ---------------------------------------------------------------------------
create or replace function public.admin_espera_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
begin
  if not public.tem_permissao('espera.arrumar') then
    raise exception 'sem permissão pra mexer na lista de espera';
  end if;

  delete from public.lista_espera where id = p_id returning email into v_email;
  if v_email is null then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'lista_espera_removida', 'lista_espera', p_id::text,
          jsonb_build_object('dominio', split_part(v_email, '@', 2)));

  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- admin_lead_evento_remover — apagar um pedido de evento (a pessoa pediu, ou
-- é spam). Nome e telefone não vão pro audit_log, pelo mesmo motivo de cima.
-- ---------------------------------------------------------------------------
create or replace function public.admin_lead_evento_remover(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_tipo text;
begin
  if not public.tem_permissao('leads.arrumar') then
    raise exception 'sem permissão pra apagar pedido de evento';
  end if;

  delete from public.leads_evento where id = p_id returning tipo into v_tipo;
  if v_tipo is null then
    return jsonb_build_object('ok', true, 'ja_era', true);
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'lead_evento_removido', 'leads_evento', p_id::text,
          jsonb_build_object('tipo', v_tipo));

  return jsonb_build_object('ok', true);
end;
$$;


-- =============================================================================
-- 11. Grants — deslogado não alcança nada
-- =============================================================================
revoke all on function public.admin_permissoes_catalogo()                  from public, anon;
revoke all on function public.admin_assinaturas(text, text, int)           from public, anon;
revoke all on function public.admin_assinatura_esticar(uuid, integer)      from public, anon;
revoke all on function public.admin_pontos_pessoas(text, int)              from public, anon;
revoke all on function public.admin_pontos_extrato(uuid, int)              from public, anon;
revoke all on function public.admin_pontos_ajustar(uuid, integer, text)    from public, anon;
revoke all on function public.admin_pedido_status(uuid, text)              from public, anon;
revoke all on function public.admin_resgate_desfazer(uuid, text)           from public, anon;
revoke all on function public.admin_brinde_arrumar(uuid, text)             from public, anon;
revoke all on function public.admin_presente_arrumar(uuid, text)           from public, anon;
revoke all on function public.admin_espera_remover(uuid)                   from public, anon;
revoke all on function public.admin_lead_evento_remover(uuid)              from public, anon;

grant execute on function public.admin_permissoes_catalogo()               to authenticated;
grant execute on function public.admin_assinaturas(text, text, int)        to authenticated;
grant execute on function public.admin_assinatura_esticar(uuid, integer)   to authenticated;
grant execute on function public.admin_pontos_pessoas(text, int)           to authenticated;
grant execute on function public.admin_pontos_extrato(uuid, int)           to authenticated;
grant execute on function public.admin_pontos_ajustar(uuid, integer, text) to authenticated;
grant execute on function public.admin_pedido_status(uuid, text)           to authenticated;
grant execute on function public.admin_resgate_desfazer(uuid, text)        to authenticated;
grant execute on function public.admin_brinde_arrumar(uuid, text)          to authenticated;
grant execute on function public.admin_presente_arrumar(uuid, text)        to authenticated;
grant execute on function public.admin_espera_remover(uuid)                to authenticated;
grant execute on function public.admin_lead_evento_remover(uuid)           to authenticated;

-- As tabelas de catálogo: leitura pela RLS (quem entra no console), escrita
-- nenhuma. Sem grant de insert/update/delete pra ninguém.
grant select on public.permissao_secoes, public.permissao_paginas,
                public.permissoes, public.permissoes_legado to authenticated;
