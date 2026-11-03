-- =============================================================================
-- 0036_mural_e_cantinho_estritos.sql — os dois apertos que a auditoria apontou
--
-- Nenhum dos dois era buraco alcançável pelo cliente comum: eles ficaram de fora
-- da leva 0032–0035 porque mexiam em comportamento de produto, não em falha. Com
-- o site ainda em teste, o custo de apertar agora é zero e o desenho fica honesto.
--
-- (a) MURAL — o staff podia REESCREVER o recado, não só ocultar.
--     A policy `mural_update_staff` (0020) libera UPDATE da linha inteira pra quem
--     é `is_staff()`, e RLS não sabe restringir coluna. A intenção declarada ali
--     ("staff altera status (ex.: ocultar)") não era o que o banco garantia: dava
--     pra trocar o `texto` e até o `user_id`, ou seja, pôr na parede uma frase que
--     a pessoa não escreveu, assinada com o nome dela. Não era escalada (staff só
--     o owner concede), mas é poder que ninguém pediu.
--     → Trigger que barra mudança em `texto`, `autor_nome` e `user_id` vinda de
--       sessão logada. Moderar (mexer no `status`) segue liberado, e a
--       `postar-mural` não é afetada: ela escreve com service_role, onde
--       `auth.uid()` é nulo. Mesmo desenho dos outros guardas de coluna do projeto
--       (prevent_points_tamper, prevent_perfil_publico_tamper).
--
-- (b) CANTINHO — a leitura pública não reconferia o plano.
--     A `perfil_publico(handle)` (0024) só olhava a flag `perfil_publico`. Quem
--     assinou, ligou o cantinho e depois saiu do plano continuava com a página no
--     ar pra sempre. Ligar é perk de assinante; ficar no ar também deveria ser.
--     → A leitura passa a exigir `tier_slug` — a MESMA régua que a
--       `definir_perfil_publico` usa pra deixar ligar. Quem pausa o plano some da
--       vitrine e VOLTA sozinho quando reassina: a flag e o handle continuam
--       guardados na linha, nada é apagado. Handle não é perdido nem reciclado.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez, DEPOIS
-- da 0020_mural e da 0024_perfil_publico. Idempotente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (a) o recado do mural não se reescreve
-- -----------------------------------------------------------------------------
create or replace function public.prevent_mural_content_tamper()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Sessão logada (staff moderando pelo console): só o status pode mudar.
  -- service_role (a postar-mural) tem auth.uid() nulo e passa direto.
  if auth.uid() is not null then
    if new.texto is distinct from old.texto then
      raise exception 'o texto do recado não se reescreve — dá pra ocultar, não pra trocar as palavras.';
    end if;
    if new.autor_nome is distinct from old.autor_nome then
      raise exception 'o nome de quem escreveu o recado não se troca.';
    end if;
    if new.user_id is distinct from old.user_id then
      raise exception 'o recado não muda de dono.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_mural_content_tamper on public.mural_notes;
create trigger trg_prevent_mural_content_tamper
  before update on public.mural_notes
  for each row execute function public.prevent_mural_content_tamper();

-- -----------------------------------------------------------------------------
-- (b) o cantinho fica no ar enquanto o plano estiver de pé
-- Mesma função da 0024, com `tier_slug is not null` na busca. O resto é idêntico.
-- -----------------------------------------------------------------------------
create or replace function public.perfil_publico(p_handle text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prof    public.profiles;
  v_tier    text;
  v_nome    text;
  v_recados jsonb;
begin
  select * into v_prof
    from public.profiles
   where lower(handle) = lower(btrim(coalesce(p_handle, '')))
     and perfil_publico = true
     and tier_slug is not null;   -- perk de assinante também na leitura
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
