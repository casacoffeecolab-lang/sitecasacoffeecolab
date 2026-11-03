-- =============================================================================
-- 0048_casa_club.sql — o clube vira uma assinatura só ☕
--
-- O PEDIDO (documento "Projeto CASA CLUB", ago/2026): em vez de quatro planos
-- pagos, UMA assinatura. "O membro não paga mais para pertencer mais: ele sobe
-- de categoria conforme o tempo de permanência no Clube."
--
-- O QUE MUDA DE SIGNIFICADO: os quatro nomes que já estão na tabela `tiers`
-- (Vizinho de Sempre, Frequentador, Gente do Casa, Alma do Casa) deixam de ser
-- PREÇO e passam a ser TEMPO DE CASA (0-3, 3-6, 6-12, 12+ meses). Os quatro
-- custam o mesmo, dão o mesmo desconto e o mesmo 1 ponto por R$1. O que muda de
-- um pro outro é só o reconhecimento de quem fica.
--
-- OS SLUGS NÃO MUDAM, e isso é decisão, não esquecimento: `bronze` é o Vizinho
-- de Sempre, `prata` o Frequentador, `ouro` o Gente do Casa e `diamante` o Alma
-- do Casa. O `tier_slug` está espalhado por mais de trinta pontos entre front,
-- Edge Functions e migrations, com FK vindo de `subscriptions`,
-- `gift_subscriptions` e `profiles`. Renomear pediria UPDATE em dado histórico
-- de produção pra ganhar só legibilidade interna, e o slug nunca aparece na
-- tela de ninguém.
--
-- POR QUE `vendavel` É COLUNA NOVA E NÃO O `ativo` QUE JÁ EXISTE: o
-- `getUserTierDiscount` (_shared/lib.ts) devolve tier_slug NULO quando o tier
-- está `ativo = false`, e o `creditPoints` dá ZERO ponto com slug nulo. Marcar
-- as três categorias superiores como inativas faria quem sobe de categoria
-- parar de pontuar e perder o desconto no mesmo instante em que a casa quis
-- agradecer a permanência. As quatro seguem `ativo = true`.
--
-- O RELÓGIO ACUMULA, NÃO CORRE NO CALENDÁRIO: quem ficou 4 meses, pausou 6 e
-- voltou, volta com 4 meses de casa, não com 10. Por isso o tempo é a UNIÃO dos
-- períodos das assinaturas da pessoa, e não a soma crua: presente resgatado
-- durante uma assinatura ativa contaria o mesmo mês duas vezes.
--
-- SEM CRON: quem promove é o `sincronizar_categoria`, chamado (a) pelo
-- asaas-webhook a cada pagamento de renovação, que é o único evento mensal que
-- o site já recebe de graça, e (b) pela leitura da tela do clube, que se
-- auto-cura se o webhook falhar.
--
-- AS CONQUISTAS NÃO PRECISARAM MUDAR: a `gente-do-casa` e a `alma-do-casa` já
-- tinham critério `{"type":"tier","slug":"ouro"|"diamante"}` desde a 0009.
-- Como a categoria agora mora no mesmo `tier_slug`, elas viram sozinhas o
-- carimbo de chegada na categoria, que é o que o documento pede.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. As duas colunas novas da `tiers`.
--    vendavel  → é esta a categoria que se compra (só a de entrada).
--    meses_min → o tempo de casa a partir do qual a categoria vale.
-- -----------------------------------------------------------------------------
alter table public.tiers add column if not exists vendavel  boolean not null default false;
alter table public.tiers add column if not exists meses_min integer not null default 0;

comment on column public.tiers.vendavel is
  'Categoria comprável. Só a de entrada. NÃO usar `ativo` pra isso: tier inativo zera desconto e pontos.';
comment on column public.tiers.meses_min is
  'Meses de casa (tempo ACUMULADO de assinatura) a partir dos quais esta categoria vale.';

-- Só pode haver UMA categoria vendável. Se um dia voltarem os planos pagos,
-- este índice é o que precisa cair primeiro, e é de propósito que ele avise.
create unique index if not exists idx_tiers_vendavel_unica
  on public.tiers ((true)) where vendavel;

-- -----------------------------------------------------------------------------
-- 2. As quatro categorias. Mesmo preço, mesmo desconto, mesmo 1 ponto por R$1.
--    As duas duplas de colunas (desconto_pct/pontos_multiplicador da 0001 e
--    discount_percent/points_multiplier da 0004) andam juntas: a 0004 criou a
--    segunda dupla e as Edge Functions leem dela, mas deixar a primeira
--    divergindo é armar uma pegadinha pro próximo que ler a tabela.
-- -----------------------------------------------------------------------------
update public.tiers set
  preco_centavos       = 4990,
  desconto_pct         = 10,
  discount_percent     = 10,
  pontos_multiplicador = 1.00,
  points_multiplier    = 1.00,
  ativo                = true,
  destaque             = false
where slug in ('bronze', 'prata', 'ouro', 'diamante');

update public.tiers set nome = 'Vizinho de Sempre', vendavel = true,  meses_min = 0,  ordem = 1 where slug = 'bronze';
update public.tiers set nome = 'Frequentador',      vendavel = false, meses_min = 3,  ordem = 2 where slug = 'prata';
update public.tiers set nome = 'Gente do Casa',     vendavel = false, meses_min = 6,  ordem = 3 where slug = 'ouro';
update public.tiers set nome = 'Alma do Casa',      vendavel = false, meses_min = 12, ordem = 4 where slug = 'diamante';

-- Qualquer tier fora dos quatro (nenhum hoje) fica explicitamente não-vendável,
-- pra ninguém comprar categoria por um slug esquecido.
update public.tiers set vendavel = false where slug not in ('bronze', 'prata', 'ouro', 'diamante');

-- -----------------------------------------------------------------------------
-- 3. dias_de_casa — o tempo ACUMULADO, pela UNIÃO dos períodos.
--
--    Cada assinatura cobre [created_at, current_period_end], cortado em now()
--    (tempo futuro não é tempo vivido). A soma crua contaria duas vezes o mês em
--    que um presente foi resgatado por cima de uma assinatura ativa, então os
--    períodos que se tocam viram uma ilha só antes de somar.
--
--    Assinatura 'cancelada' entra: o tempo já vivido não some quando o gateway
--    encerra. Pausa não conta (o período dela termina) e não zera nada.
-- -----------------------------------------------------------------------------
create or replace function public.dias_de_casa(p_user uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  with periodos as (
    select s.created_at as inicio,
           least(coalesce(s.current_period_end, s.created_at), now()) as fim
      from public.subscriptions s
     where s.user_id = p_user
       and s.status in ('ativa', 'pausada', 'cancelada')
  ),
  validos as (
    select inicio, fim from periodos where fim > inicio
  ),
  marcados as (
    -- 1 quando este período começa depois do fim de todos os anteriores (ilha nova).
    select inicio, fim,
           case
             when max(fim) over (
                    order by inicio, fim
                    rows between unbounded preceding and 1 preceding
                  ) >= inicio then 0
             else 1
           end as nova_ilha
      from validos
  ),
  ilhas as (
    select inicio, fim,
           sum(nova_ilha) over (order by inicio, fim rows unbounded preceding) as ilha
      from marcados
  ),
  unidos as (
    select min(inicio) as inicio, max(fim) as fim from ilhas group by ilha
  )
  select coalesce(floor(sum(extract(epoch from (fim - inicio))) / 86400)::integer, 0)
    from unidos;
$$;

-- Recebe user_id por parâmetro, então NÃO vai pro client (leria o tempo de casa
-- de qualquer pessoa). Quem serve o front é a `meu_clube`, que usa auth.uid().
revoke all on function public.dias_de_casa(uuid) from public, anon, authenticated;
grant execute on function public.dias_de_casa(uuid) to service_role;

-- Um mês = 30 dias. A Asaas renova em ciclo MONTHLY (~30,44 dias na média), então
-- o marco de 12 meses cai uns cinco dias antes. O arredondamento fica a favor de
-- quem fica, que é o lado certo pra errar.
create or replace function public.meses_de_casa(p_user uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select floor(public.dias_de_casa(p_user) / 30.0)::integer;
$$;

revoke all on function public.meses_de_casa(uuid) from public, anon, authenticated;
grant execute on function public.meses_de_casa(uuid) to service_role;

-- -----------------------------------------------------------------------------
-- 4. categoria_por_tempo — a categoria de maior `meses_min` que cabe no tempo.
-- -----------------------------------------------------------------------------
create or replace function public.categoria_por_tempo(p_meses integer)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select t.slug
    from public.tiers t
   where t.ativo = true
     and t.meses_min <= greatest(coalesce(p_meses, 0), 0)
   order by t.meses_min desc, t.ordem desc
   limit 1;
$$;

revoke all on function public.categoria_por_tempo(integer) from public, anon;
grant execute on function public.categoria_por_tempo(integer) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5. sincronizar_categoria — põe o `tier_slug` no lugar certo.
--
--    A categoria mora no `tier_slug` (e não só na tela do clube) porque header,
--    painel do avatar, cartão do /gente, perfil e console já leem esse campo:
--    escrevendo aqui, todos passam a mostrar a categoria certa sem mudar uma
--    linha. Se fosse derivada só na tela, o perfil diria "Vizinho de Sempre" pra
--    quem tem dois anos de casa.
--
--    Regra de quem TEM benefício vigente = a mesma do getEffectiveSubscription
--    das Edge Functions: 'ativa' sempre concede; 'pausada' concede enquanto o
--    período pago não venceu. Sem nenhuma que conceda, o tier é limpo (auto-cura,
--    igual à do lib.ts) — senão a categoria virava benefício vitalício de graça.
--
--    Só escreve quando há diferença, então chamar duas vezes seguidas é inócuo.
-- -----------------------------------------------------------------------------
create or replace function public.sincronizar_categoria(p_user uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub        record;
  v_meses      integer;
  v_alvo       text;
  v_tier_atual text;
  v_mudou      boolean := false;
begin
  if p_user is null then
    return null;
  end if;

  select s.id, s.tier_slug
    into v_sub
    from public.subscriptions s
   where s.user_id = p_user
     and s.status in ('ativa', 'pausada')
     and (s.status = 'ativa' or (s.current_period_end is not null and s.current_period_end > now()))
   order by s.current_period_end desc nulls last
   limit 1;

  select p.tier_slug into v_tier_atual from public.profiles p where p.id = p_user;

  -- Ninguém concedendo benefício agora: limpa o tier (auto-cura).
  if not found or v_sub.id is null then
    if v_tier_atual is not null then
      perform set_config('casa.trusted_points', 'on', true);
      update public.profiles set tier_slug = null where id = p_user;
    end if;
    return null;
  end if;

  v_meses := public.meses_de_casa(p_user);
  v_alvo  := public.categoria_por_tempo(v_meses);
  if v_alvo is null then
    return v_tier_atual;
  end if;

  if v_sub.tier_slug is distinct from v_alvo then
    update public.subscriptions set tier_slug = v_alvo, updated_at = now() where id = v_sub.id;
    v_mudou := true;
  end if;

  if v_tier_atual is distinct from v_alvo then
    -- A GUC libera a trigger prevent_points_tamper (0005/0008), que barra
    -- escrita de tier_slug vinda de sessão autenticada.
    perform set_config('casa.trusted_points', 'on', true);
    update public.profiles set tier_slug = v_alvo, updated_at = now() where id = p_user;
    v_mudou := true;
  end if;

  -- Subiu de categoria: a conquista do marco é avaliada na hora, senão o
  -- emblema só apareceria na próxima compra.
  if v_mudou then
    perform public.check_achievements(p_user);
    insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
    values (null, 'categoria_sincronizada', 'profiles', p_user::text,
            jsonb_build_object('de', v_tier_atual, 'para', v_alvo, 'meses', v_meses));
  end if;

  return v_alvo;
end;
$$;

revoke all on function public.sincronizar_categoria(uuid) from public, anon, authenticated;
grant execute on function public.sincronizar_categoria(uuid) to service_role;

-- -----------------------------------------------------------------------------
-- 6. meu_clube — tudo que a tela do clube precisa, numa viagem só.
--
--    Usa auth.uid(): o client nunca diz de quem é o clube, nem quanto tempo tem
--    de casa. Sincroniza a própria categoria antes de responder (auto-cura).
-- -----------------------------------------------------------------------------
create or replace function public.meu_clube()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_sub      record;
  v_dias     integer;
  v_meses    integer;
  v_slug     text;
  v_atual    record;
  v_proxima  record;
  v_saldo    integer;
begin
  if v_user is null then
    raise exception 'precisa estar logado pra ver o clube.';
  end if;

  v_slug := public.sincronizar_categoria(v_user);
  v_dias := public.dias_de_casa(v_user);
  v_meses := floor(v_dias / 30.0)::integer;

  select s.status, s.current_period_end, s.presente_id
    into v_sub
    from public.subscriptions s
   where s.user_id = v_user
     and s.status in ('ativa', 'pausada')
     and (s.status = 'ativa' or (s.current_period_end is not null and s.current_period_end > now()))
   order by s.current_period_end desc nulls last
   limit 1;

  select coalesce(points_balance, 0) into v_saldo from public.profiles where id = v_user;

  -- A categoria mostrada é a vigente quando há plano; sem plano, a que o tempo
  -- de casa já garante (fica de memória do que a pessoa foi, sem conceder nada).
  select t.slug, t.nome, t.meses_min, t.ordem
    into v_atual
    from public.tiers t
   where t.slug = coalesce(v_slug, public.categoria_por_tempo(v_meses));

  select t.slug, t.nome, t.meses_min
    into v_proxima
    from public.tiers t
   where t.ativo = true
     and t.meses_min > coalesce(v_atual.meses_min, 0)
   order by t.meses_min asc
   limit 1;

  return jsonb_build_object(
    'tem_plano',        v_slug is not null,
    'status',           v_sub.status,
    'ativo_ate',        v_sub.current_period_end,
    'eh_presente',      v_sub.presente_id is not null,
    'dias',             v_dias,
    'meses',            v_meses,
    'saldo',            coalesce(v_saldo, 0),
    'categoria',        case when v_atual.slug is null then null else jsonb_build_object(
                          'slug', v_atual.slug, 'nome', v_atual.nome, 'meses_min', v_atual.meses_min) end,
    'proxima',          case when v_proxima.slug is null then null else jsonb_build_object(
                          'slug', v_proxima.slug, 'nome', v_proxima.nome, 'meses_min', v_proxima.meses_min,
                          'dias_faltando', greatest(v_proxima.meses_min * 30 - v_dias, 0)) end,
    'categorias',       (select coalesce(jsonb_agg(jsonb_build_object(
                            'slug', t.slug, 'nome', t.nome, 'meses_min', t.meses_min,
                            'atingida', t.meses_min <= v_meses) order by t.meses_min), '[]'::jsonb)
                           from public.tiers t where t.ativo = true)
  );
end;
$$;

revoke all on function public.meu_clube() from public, anon;
grant execute on function public.meu_clube() to authenticated;
