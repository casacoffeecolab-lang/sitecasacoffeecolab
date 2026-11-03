-- =============================================================================
-- 0051_nascimento_travado.sql — o aniversário entra no cadastro e não se troca 🎂
--
-- O PORQUÊ: a 0050 abriu o brunch de aniversário pra **qualquer pessoa com
-- conta**, plano ou não. Isso é bom pro cadastro e ruim pro caixa se a data for
-- editável: bastaria mudar o aniversário pra hoje, pegar o brunch, mudar de novo
-- no mês que vem. O UNIQUE `(user_id, ano)` segura um por ANO, mas não segura
-- quem move a data pra dentro da janela sempre que quer vir.
--
-- O QUE ESTE ARQUIVO FAZ:
--   1. `handle_new_user` passa a gravar `nascimento` do metadata do cadastro.
--   2. Trigger `prevent_nascimento_tamper`: depois de preenchida, a data **não
--      muda mais** por sessão de cliente. De nulo pra uma data ainda passa (as
--      contas que já existem precisam poder preencher uma vez), e o **owner**
--      passa sempre (é a saída pra um dígito trocado; hoje ela é pelo SQL
--      Editor, o console não tem campo pra isso).
--   3. Régua de sanidade na própria trigger: data no futuro ou mais de 120 anos
--      atrás é recusada. Sem isso, "01/01/0001" viraria aniversário legítimo.
--
-- POR QUE TRIGGER E NÃO RLS: a `profiles_update_self` (0002) libera UPDATE da
-- linha INTEIRA e RLS não restringe coluna. Mesmo desenho do
-- `prevent_points_tamper` (0008) e do `prevent_perfil_publico_tamper` (0033).
--
-- A GUC `casa.trusted_perfil` (0033) serve de bypass server-side, então qualquer
-- função SECURITY DEFINER que precise corrigir a data no futuro já tem por onde.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. handle_new_user — agora com o aniversário.
--    O parse é TOLERANTE de propósito: se vier lixo no metadata, a data fica
--    nula e a conta nasce assim mesmo. Derrubar um cadastro por causa de um
--    campo de mimo seria trocar uma pessoa nova por uma data de aniversário.
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nasc date := null;
  v_bruto text := nullif(btrim(coalesce(new.raw_user_meta_data->>'nascimento', '')), '');
begin
  if v_bruto is not null then
    begin
      v_nasc := v_bruto::date;
      -- Mesma régua da trigger: nada no futuro, nada de 300 anos atrás.
      if v_nasc > current_date or v_nasc < current_date - interval '120 years' then
        v_nasc := null;
      end if;
    exception when others then
      v_nasc := null;
    end;
  end if;

  insert into public.profiles (id, full_name, telefone, nascimento, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'telefone',
    v_nasc,
    'cliente'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. prevent_nascimento_tamper — a data é de escrever uma vez.
-- -----------------------------------------------------------------------------
create or replace function public.prevent_nascimento_tamper()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Caminho server-side confiável (mesma GUC do cantinho, 0033): libera.
  if coalesce(current_setting('casa.trusted_perfil', true), '') = 'on' then
    return new;
  end if;

  -- Sem sessão de cliente (service_role, triggers, functions): libera.
  if auth.uid() is null then
    return new;
  end if;

  -- O adm do Casa passa: é ele quem conserta um dígito trocado.
  if public.is_owner() then
    return new;
  end if;

  if new.nascimento is distinct from old.nascimento then
    -- Preencher pela primeira vez pode (conta antiga, que nasceu sem a data).
    if old.nascimento is not null then
      raise exception 'o aniversário é escrito uma vez só. se ficou errado, chama a gente 💛';
    end if;
    if new.nascimento is not null then
      if new.nascimento > current_date then
        raise exception 'essa data de aniversário ainda não chegou.';
      end if;
      if new.nascimento < current_date - interval '120 years' then
        raise exception 'essa data de aniversário não parece de gente que toma café.';
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prevent_nascimento_tamper on public.profiles;
create trigger trg_prevent_nascimento_tamper
  before update on public.profiles
  for each row execute function public.prevent_nascimento_tamper();
