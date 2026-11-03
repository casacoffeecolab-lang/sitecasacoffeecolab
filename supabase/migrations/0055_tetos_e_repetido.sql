-- =============================================================================
-- 0055_tetos_e_repetido.sql — o que a auditoria dos dez commits achou no banco
--
-- Duas correções nas duas funções abertas a `anon`, que são as únicas portas de
-- escrita que qualquer pessoa da internet alcança com a chave do bundle. O
-- corpo das duas é o que já está no ar (extraído da 0040 e da 0053); só as
-- partes comentadas com "(0055)" mudam.
--
--   1. `registrar_rastro` ganha um teto GLOBAL de 20 mil eventos por hora, e o
--      contador de páginas da visita para de crescer sem fim. Os dois tetos da
--      0053 (400 visitas novas por hora, 400 eventos por visita) seguram cada
--      dimensão sozinha, mas se multiplicam: 160 mil linhas por hora era o
--      teto de verdade, e disso ninguém tinha se dado conta.
--
--   2. `registrar_lead_evento` passa a dizer `repetido: true` quando o
--      anti-flood de 30 segundos segura o pedido. A função continua NÃO criando
--      a linha; o que ela deixa de fazer é responder igualzinho a um pedido que
--      entrou. Desde que o WhatsApp saiu da /eventos (ago/2026), essa resposta
--      igual fazia a correção reenviada em menos de 30s sumir com um "anotado"
--      na tela. A página nova lê essa chave; a página velha não a lê e segue
--      funcionando como antes, então esta migration pode ser aplicada sozinha.
--
-- Nenhuma tabela, coluna, policy ou permissão muda. Nada aqui pede re-deploy de
-- Edge Function.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (CREATE OR REPLACE nas duas).
-- =============================================================================


-- =============================================================================
-- 1. registrar_rastro — teto global por hora, e paginas com fim
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

  -- Teto GLOBAL por hora (0055). Os dois tetos da 0053 seguram a quantidade de
  -- visitas e o tamanho de cada uma, mas eles se MULTIPLICAM: 400 visitas novas
  -- por hora vezes 400 eventos por visita são 160 mil linhas por hora, uns meio
  -- giga por dia, e o endpoint é aberto a anon com a chave que está no bundle.
  -- Vinte mil por hora é ordens de grandeza acima de um dia cheio de verdade num
  -- café, e é um número que a tabela aguenta. O `limit` por dentro faz a conta
  -- parar assim que alcança o teto, em vez de varrer a hora inteira.
  -- Vem ANTES do v_cliques de propósito: se zerasse o limite depois, a visita
  -- contaria clique que nunca virou linha, e o contador passaria a mentir.
  if v_limite > 0
     and (select count(*) from (
            select 1 from public.rastro_eventos
             where criado_em > now() - interval '1 hour'
             limit 20000) t) >= 20000 then
    v_limite := 0;
  end if;

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
    -- Com teto (0055): a visita que já existe não passa pelo freio horário, e
    -- nada impedia mil pulsos com `pagina_nova` inflando o "viram uma página
    -- só" do relatório. Quinhentas páginas numa aba só já é mais do que
    -- qualquer navegação real.
    paginas           = least(v.paginas + v_nova_pag, 500),
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
-- 2. registrar_lead_evento — o repetido para de se passar por pedido novo
-- =============================================================================
create or replace function public.registrar_lead_evento(
  p_nome      text,
  p_contato   text,
  p_tipo      text,
  p_email     text default null,
  p_data      date default null,
  p_pessoas   int default null,
  p_mensagem  text default null,
  p_origem    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome     text := btrim(coalesce(p_nome, ''));
  v_contato  text := btrim(coalesce(p_contato, ''));
  v_tipo     text := btrim(coalesce(p_tipo, ''));
  v_email    text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_mensagem text := nullif(btrim(coalesce(p_mensagem, '')), '');
  v_origem   text := nullif(btrim(coalesce(p_origem, '')), '');
  v_id       uuid;
begin
  if char_length(v_nome) not between 2 and 80 then
    return jsonb_build_object('ok', false, 'erro', 'falta teu nome');
  end if;

  -- Precisa de dígito suficiente pra ser telefone; a máscara do site já entrega
  -- formatado, mas quem chama a função por fora não passa por ela.
  if char_length(v_contato) not between 8 and 40
     or char_length(regexp_replace(v_contato, '[^0-9]', '', 'g')) < 10 then
    return jsonb_build_object('ok', false, 'erro', 'esse telefone não parece completo');
  end if;

  if char_length(v_tipo) not between 2 and 40 then
    return jsonb_build_object('ok', false, 'erro', 'conta pra gente que tipo de evento é');
  end if;

  if v_email is not null
     and (char_length(v_email) not between 6 and 160
          or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then
    return jsonb_build_object('ok', false, 'erro', 'esse e-mail não parece completo');
  end if;

  if p_pessoas is not null and p_pessoas not between 1 and 500 then
    return jsonb_build_object('ok', false, 'erro', 'quantas pessoas, mais ou menos?');
  end if;

  if v_mensagem is not null then v_mensagem := left(v_mensagem, 600); end if;
  if v_origem   is not null then v_origem   := left(v_origem, 120);   end if;

  -- Anti-flood: mesmo contato de novo dentro de 30s não vira linha nova. A
  -- resposta é a mesma, porque pra quem está do outro lado é a mesma coisa
  -- (o pedido já entrou).
  if exists (
    select 1 from public.leads_evento
     where contato = v_contato
       and created_at > now() - interval '30 seconds'
  ) then
    -- `repetido` é novo (0055). Enquanto o WhatsApp era o canal, engolir isto em
    -- silêncio era inofensivo: a conversa ia junto e levava a versão certa. Sem
    -- ele, quem viu um erro no recado, corrigiu e reenviou dentro da janela lia
    -- "anotado" e ia embora achando que a casa tinha a correção, que na verdade
    -- se perdeu. A linha segue não sendo criada (o freio continua valendo); o
    -- que muda é que agora a página sabe disso e conta a verdade.
    return jsonb_build_object('ok', true, 'repetido', true);
  end if;

  insert into public.leads_evento (nome, contato, email, tipo, data_pretendida, pessoas, mensagem, origem, user_id)
  values (v_nome, v_contato, v_email, v_tipo, p_data, p_pessoas, v_mensagem, v_origem, auth.uid())
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- =============================================================================
-- 3. Grants — os mesmos de sempre, repetidos porque CREATE OR REPLACE não mexe
--    neles, mas deixar explícito é o que faz este arquivo se bastar.
-- =============================================================================
revoke all on function public.registrar_rastro(jsonb) from public;
grant execute on function public.registrar_rastro(jsonb) to anon, authenticated;

revoke all on function public.registrar_lead_evento(text, text, text, text, date, int, text, text) from public;
grant execute on function public.registrar_lead_evento(text, text, text, text, date, int, text, text) to anon, authenticated;
