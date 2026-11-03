-- =============================================================================
-- 0024_perfil_publico.sql — "Meu cantinho" 🏡
--
-- Um cartãozinho público e OPCIONAL do assinante em /gente/{handle}: só o essencial
-- e gentil — apelido, "meu café de sempre", o plano, há quanto tempo é da casa, a
-- foto e os recados que deixou no Mural. Dá rosto à comunidade SEM expor nada
-- sensível: e-mail, telefone, pontos, endereço e nome real ficam DE FORA.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Opt-in explícito: `profiles.perfil_publico` (default false). Ninguém aparece
--     sem ligar. O `handle` (slug único da URL) é gerado ao ligar e fica estável.
--   • A exposição pública NÃO é RLS na `profiles` (arriscado — abriria a linha
--     inteira). É uma RPC `perfil_publico(handle)` SECURITY DEFINER que devolve um
--     jsonb com EXATAMENTE os campos seguros (hand-picked), só pra quem optou.
--     e-mail/telefone/pontos/endereço nunca entram no payload.
--   • Ligar/desligar: RPC `definir_perfil_publico(ativar)` usa auth.uid() (o client
--     nunca diz de quem é) e exige ser assinante (perk de assinante, como o Mural).
--   • Os recados vêm do Mural (já público os 'aprovado'); o payload injeta os do dono.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (add column if not exists / CREATE OR REPLACE).
-- =============================================================================

alter table public.profiles add column if not exists perfil_publico boolean not null default false;
alter table public.profiles add column if not exists handle text unique;

-- -----------------------------------------------------------------------------
-- definir_perfil_publico(ativar) → jsonb {ok, ativo, handle} | {ok:false, erro}
-- O dono (auth.uid) liga/desliga o próprio cantinho. Ao ligar, garante um handle
-- único e estável (slug do apelido/nome). Exige assinatura vigente (tier_slug).
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
    while exists (select 1 from public.profiles where handle = v_handle and id <> v_uid) loop
      v_i := v_i + 1;
      v_handle := v_base || '-' || v_i;
    end loop;
  end if;

  update public.profiles set perfil_publico = true, handle = v_handle where id = v_uid;
  return jsonb_build_object('ok', true, 'ativo', true, 'handle', v_handle);
end;
$$;

revoke all on function public.definir_perfil_publico(boolean) from public, anon;
grant execute on function public.definir_perfil_publico(boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- perfil_publico(handle) → jsonb (payload seguro) | null
-- Leitura PÚBLICA (anon) do cantinho de quem optou. SÓ campos seguros. Devolve
-- null se o handle não existe ou o perfil não é público.
-- -----------------------------------------------------------------------------
create or replace function public.perfil_publico(p_handle text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prof   public.profiles;
  v_tier   text;
  v_nome   text;
  v_recados jsonb;
begin
  select * into v_prof
    from public.profiles
   where lower(handle) = lower(btrim(coalesce(p_handle, ''))) and perfil_publico = true;
  if not found then
    return null;
  end if;

  select nome into v_tier from public.tiers where slug = v_prof.tier_slug;

  -- Nome de exibição: apelido, senão o PRIMEIRO nome (nunca o nome completo real).
  v_nome := nullif(btrim(v_prof.apelido), '');
  if v_nome is null then
    v_nome := split_part(btrim(coalesce(v_prof.full_name, '')), ' ', 1);
  end if;
  if v_nome is null or v_nome = '' then v_nome := 'alguém do Casa'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('texto', m.texto, 'created_at', m.created_at)
                            order by m.created_at desc), '[]'::jsonb)
    into v_recados
    from public.mural_notes m
   where m.user_id = v_prof.id and m.status = 'aprovado';

  return jsonb_build_object(
    'nome',         v_nome,
    'avatar_url',   v_prof.avatar_url,
    'tier_slug',    v_prof.tier_slug,
    'tier_nome',    v_tier,
    'membro_desde', v_prof.created_at,
    'cafe_metodo',  v_prof.cafe_metodo,
    'cafe_torra',   v_prof.cafe_torra,
    'cafe_leite',   v_prof.cafe_leite,
    'cafe_horario', v_prof.cafe_horario,
    'recados',      v_recados
  );
end;
$$;

revoke all on function public.perfil_publico(text) from public;
grant execute on function public.perfil_publico(text) to anon, authenticated;
