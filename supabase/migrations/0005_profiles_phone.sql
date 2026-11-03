-- =============================================================================
-- Casa Coffee Colab — 0005_profiles_phone.sql
-- Auth (Fase 2): guarda o telefone no profiles e blinda os campos de fidelidade.
--
-- APPEND-ONLY e IMUTÁVEL (0001–0004 já aplicadas). Idempotente:
-- ADD COLUMN IF NOT EXISTS / CREATE OR REPLACE / drop trigger if exists.
-- NÃO renomeia nada. Nomes canônicos travados (tabelas tiers/partners, papéis
-- cliente/staff/gerente/owner). Ver CLAUDE.md › Segurança + Migrations.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- profiles.telefone — coletado no cadastro (raw_user_meta_data 'telefone').
-- (E-mail NÃO fica aqui: vive em auth.users; o perfil lê da sessão.)
-- (CPF NÃO fica aqui: decisão registrada — o Stripe coleta/guarda o CPF.)
-- -----------------------------------------------------------------------------
alter table public.profiles add column if not exists telefone text;

-- -----------------------------------------------------------------------------
-- handle_new_user — agora também popula o telefone no signup.
-- CREATE OR REPLACE atualiza o corpo; a trigger on_auth_user_created (0001)
-- continua apontando pra esta função (não precisa recriar a trigger).
-- SECURITY DEFINER + search_path fixo (mesma postura da 0001).
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, telefone, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'telefone',
    'cliente'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- prevent_points_tamper — confiança zero no client.
-- A policy profiles_update_self (0002) deixa o cliente editar a PRÓPRIA linha,
-- mas sem restrição de coluna ele poderia tentar mexer em points_balance /
-- tier_slug (adicionados na 0004). Pontos e plano são gravados SÓ server-side
-- (Edge Function/service_role, que roda sem auth.uid()) ou pelo owner.
-- Defesa em profundidade, no mesmo espírito da trigger prevent_role_change.
-- -----------------------------------------------------------------------------
create or replace function public.prevent_points_tamper()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Sessão autenticada que NÃO é owner: barra qualquer mudança nesses campos.
  -- service_role (auth.uid() null) e owner passam.
  if auth.uid() is not null and not public.is_owner() then
    if new.points_balance is distinct from old.points_balance then
      raise exception 'points_balance é gravado só server-side (não pelo client).';
    end if;
    if new.tier_slug is distinct from old.tier_slug then
      raise exception 'tier_slug é gravado só server-side (não pelo client).';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_points_tamper on public.profiles;
create trigger trg_prevent_points_tamper
  before update on public.profiles
  for each row execute function public.prevent_points_tamper();
