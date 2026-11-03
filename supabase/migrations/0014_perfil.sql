-- =============================================================================
-- 0014_perfil — os campos que faltavam no perfil da conta.
--
-- Repaginação de /conta/perfil (handoff de design): identidade (apelido,
-- aniversário), preferências de café, endereço de entrega da assinatura e
-- preferências de aviso. Tudo mora em `profiles` — é 1:1 com a pessoa, não
-- tem cardinalidade própria, e assim continua valendo a policy que já existe
-- (`profiles_update_self`: o dono edita a PRÓPRIA linha, RLS garante).
--
-- CPF NÃO entra aqui de propósito: o CPF é coletado na página hospedada do
-- Asaas, a gente não guarda. Menos dado sensível no banco, menos superfície.
--
-- A trigger `prevent_points_tamper` (0008) segue blindando points_balance e
-- tier_slug contra escrita do client; as colunas abaixo são livres pro dono.
--
-- Idempotente (add column if not exists). Não mexe em nada anterior.
-- =============================================================================

-- ── identidade ───────────────────────────────────────────────────────────────
alter table public.profiles add column if not exists apelido    text;
alter table public.profiles add column if not exists nascimento date;

-- ── preferências de café (o barista dá uma olhada antes de moer) ─────────────
alter table public.profiles add column if not exists cafe_metodo     text;
alter table public.profiles add column if not exists cafe_torra      text;
alter table public.profiles add column if not exists cafe_leite      text;
alter table public.profiles add column if not exists cafe_restricoes text;
alter table public.profiles add column if not exists cafe_horario    text;

-- ── endereço de entrega da assinatura ────────────────────────────────────────
alter table public.profiles add column if not exists end_cep         text;
alter table public.profiles add column if not exists end_rua         text;
alter table public.profiles add column if not exists end_numero      text;
alter table public.profiles add column if not exists end_complemento text;
alter table public.profiles add column if not exists end_bairro      text;
alter table public.profiles add column if not exists end_cidade      text;
alter table public.profiles add column if not exists end_uf          text;

-- ── avisos (a gente fala pouco, e só do que importa) ─────────────────────────
-- jsonb com os cinco canais. Default = o que o desenho mostra ligado.
alter table public.profiles add column if not exists avisos jsonb
  not null default '{"lotes":true,"pontos":true,"cobranca":true,"eventos":false,"whats":true}'::jsonb;

-- =============================================================================
-- CHECKs — o client é livre pra mandar o que quiser, o banco é quem decide o
-- que é válido. Valores nulos passam (campo em branco é um estado legítimo).
-- =============================================================================
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_cafe_metodo_check') then
    alter table public.profiles add constraint profiles_cafe_metodo_check
      check (cafe_metodo is null or cafe_metodo in ('coado','prensa','aeropress','espresso','moka'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'profiles_cafe_torra_check') then
    alter table public.profiles add constraint profiles_cafe_torra_check
      check (cafe_torra is null or cafe_torra in ('clara','media','escura'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'profiles_cafe_leite_check') then
    alter table public.profiles add constraint profiles_cafe_leite_check
      check (cafe_leite is null or cafe_leite in ('puro','integral','vegetal','tanto'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'profiles_cafe_horario_check') then
    alter table public.profiles add constraint profiles_cafe_horario_check
      check (cafe_horario is null or cafe_horario in ('manha','almoco','tarde','fim'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'profiles_end_uf_check') then
    alter table public.profiles add constraint profiles_end_uf_check
      check (end_uf is null or end_uf ~ '^[A-Z]{2}$');
  end if;

  -- Aniversário no passado (e num intervalo humano) — barra typo tipo 2205.
  if not exists (select 1 from pg_constraint where conname = 'profiles_nascimento_check') then
    alter table public.profiles add constraint profiles_nascimento_check
      check (nascimento is null or (nascimento < current_date and nascimento > date '1900-01-01'));
  end if;
end $$;

-- =============================================================================
-- Documentação das colunas (aparece no painel do Supabase).
-- =============================================================================
comment on column public.profiles.apelido    is 'como a pessoa prefere ser chamada no balcão';
comment on column public.profiles.nascimento is 'aniversário — no dia tem café por nossa conta';
comment on column public.profiles.avisos     is 'canais de aviso: lotes, pontos, cobranca, eventos, whats (booleans)';
