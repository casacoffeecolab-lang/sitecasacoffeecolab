-- =============================================================================
-- 0033_perfil_publico_trava.sql — o cantinho só liga pela porta da frente
--
-- O PROBLEMA (achado em auditoria de segurança):
--   A `definir_perfil_publico(ativar)` (0024) é a porta que exige plano vigente
--   (`tier_slug`) e gera um handle livre. Só que ela não era a ÚNICA porta: a
--   policy `profiles_update_self` (0002) libera UPDATE da linha inteira, e RLS
--   não sabe restringir coluna. Quem protege coluna aqui são triggers — e as que
--   existiam cobrem `role` (0001), `points_balance`/`tier_slug` (0005/0008) e
--   `master` (0017). As colunas da 0024 não tinham nenhuma.
--
--   Resultado: qualquer conta grátis mandava um PATCH direto no PostgREST
--     PATCH /rest/v1/profiles?id=eq.<próprio uid>
--     { "perfil_publico": true, "handle": "casa", "apelido": "Casa Coffee Colab" }
--   e publicava um cantinho sem nunca ter assinado — e, como `handle` é unique e
--   a RPC só escolhe slug livre, dava pra tomar de vez um nome cobiçado (o da
--   própria casa, o de alguém conhecido) numa página do domínio oficial.
--
-- A CORREÇÃO: uma trigger no mesmo formato do `prevent_points_tamper` (0008),
--   com a mesma mecânica de GUC transaction-local pro caminho confiável — a
--   `definir_perfil_publico` acende `casa.trusted_perfil` antes de escrever, e é
--   o único caminho que passa. (SECURITY DEFINER não troca o `auth.uid()`, então
--   a trigger não tem como distinguir a RPC do PATCH cru sem esse sinal.)
--
--   De quebra, a RPC passa a recusar um punhado de handles reservados: o slug sai
--   do apelido, que a pessoa escolhe, então sem isso um assinante ainda poderia
--   virar /gente/casa e falar como se fosse a casa.
--
-- O QUE NÃO MUDA: quem assinou, ligou o cantinho e depois saiu do plano continua
--   com a página no ar. Isso é comportamento de produto (a `perfil_publico(handle)`
--   nunca reconferiu o plano na leitura), não a falha — e derrubar página de gente
--   que pausou o plano é decisão de vocês, não de uma correção de segurança.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez,
-- DEPOIS da 0024_perfil_publico (é ela que cria as colunas e a RPC).
-- Idempotente (CREATE OR REPLACE / drop trigger if exists).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- prevent_perfil_publico_tamper — `perfil_publico` e `handle` só mudam pelo
-- caminho confiável. Mesmo desenho do prevent_points_tamper: GUC libera, cliente
-- autenticado que não é owner apanha.
-- -----------------------------------------------------------------------------
create or replace function public.prevent_perfil_publico_tamper()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Caminho confiável (definir_perfil_publico): libera.
  if coalesce(current_setting('casa.trusted_perfil', true), '') = 'on' then
    return new;
  end if;

  if auth.uid() is not null and not public.is_owner() then
    if new.perfil_publico is distinct from old.perfil_publico then
      raise exception 'o cantinho liga e desliga só pela tela do perfil (não pelo client).';
    end if;
    if new.handle is distinct from old.handle then
      raise exception 'o endereço do cantinho é gerado pelo servidor (não pelo client).';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prevent_perfil_publico_tamper on public.profiles;
create trigger trg_prevent_perfil_publico_tamper
  before update on public.profiles
  for each row execute function public.prevent_perfil_publico_tamper();

-- -----------------------------------------------------------------------------
-- definir_perfil_publico — mesma função da 0024, com duas mudanças:
--   • acende a GUC confiável antes de cada escrita (senão a trigger acima barra
--     a própria porta da frente);
--   • recusa handle reservado, caindo pro sufixo numerado (`casa-2`), pra ninguém
--     virar a casa por escolher o apelido certo.
-- -----------------------------------------------------------------------------
create or replace function public.definir_perfil_publico(p_ativar boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_prof   public.profiles;
  v_base   text;
  v_handle text;
  v_i      integer := 1;
  -- Nomes que falam pela casa (ou pela equipe) e não podem sair no sorteio do slug.
  v_reservados text[] := array[
    'casa', 'casacoffee', 'casacoffeecolab', 'casa-coffee', 'casa-coffee-colab',
    'admin', 'adm', 'equipe', 'staff', 'contato', 'atendimento', 'suporte',
    'oficial', 'loja', 'cardapio', 'planos', 'colab', 'conta', 'gente'
  ];
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'erro', 'não autenticado');
  end if;

  select * into v_prof from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'perfil não encontrado');
  end if;

  -- Desligar é sempre permitido; guarda o handle pra reativar na mesma URL.
  if not coalesce(p_ativar, false) then
    perform set_config('casa.trusted_perfil', 'on', true);
    update public.profiles set perfil_publico = false where id = v_uid;
    return jsonb_build_object('ok', true, 'ativo', false, 'handle', v_prof.handle);
  end if;

  -- Ligar é perk de assinante (mesma régua do Mural/pontos): precisa de plano vigente.
  if v_prof.tier_slug is null then
    return jsonb_build_object('ok', false, 'erro', 'o teu cantinho é um mimo de quem tem plano 💛', 'precisa_assinar', true);
  end if;

  v_handle := v_prof.handle;
  if v_handle is null then
    -- slug base: apelido → nome → 'amigo'. Tira acento comum, deixa a-z0-9 e hífen.
    v_base := lower(coalesce(nullif(btrim(v_prof.apelido), ''), nullif(btrim(v_prof.full_name), ''), 'amigo'));
    v_base := translate(v_base, 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn');
    v_base := btrim(regexp_replace(v_base, '[^a-z0-9]+', '-', 'g'), '-');
    if v_base = '' then v_base := 'amigo'; end if;
    v_handle := v_base;
    -- Reservado ou já tomado: tenta o próximo sufixo. ('casa' → 'casa-2')
    while v_handle = any (v_reservados)
       or exists (select 1 from public.profiles where handle = v_handle and id <> v_uid) loop
      v_i := v_i + 1;
      v_handle := v_base || '-' || v_i;
    end loop;
  end if;

  perform set_config('casa.trusted_perfil', 'on', true);
  update public.profiles set perfil_publico = true, handle = v_handle where id = v_uid;
  return jsonb_build_object('ok', true, 'ativo', true, 'handle', v_handle);
end;
$$;

revoke all on function public.definir_perfil_publico(boolean) from public, anon;
grant execute on function public.definir_perfil_publico(boolean) to authenticated;
