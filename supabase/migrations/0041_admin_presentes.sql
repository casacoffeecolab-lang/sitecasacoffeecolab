-- =============================================================================
-- 0041_admin_presentes.sql — a casa enxerga os presentes vendidos 🎁
--
-- A `gift_select_own` (0019) deixa ler só quem é parte do presente: o comprador
-- e quem resgatou. Isso está certo pro site, mas deixava a CASA cega: ninguém
-- da equipe conseguia responder "quantos presentes foram vendidos esse mês?"
-- nem "esse código aqui é válido?" sem abrir o SQL Editor.
--
-- QUAL PERMISSÃO, E POR QUÊ 'resgates':
--   O código do presente é um título ao portador — quem tem o texto resgata um
--   mês de plano. Então isto não podia cair na permissão mais larga do console.
--   'resgates' é quem já entrega recompensa em mãos e dá baixa nela: mesmo nível
--   de confiança, mesma natureza de trabalho, e nenhuma permissão nova (o
--   whitelist do 0017 é fechado por CHECK, criar uma pediria outra migration).
--
-- O QUE NÃO SAI DAQUI:
--   A `mensagem` (o bilhete que o comprador escreveu pra quem ganha) NÃO entra
--   no retorno. É recado de uma pessoa pra outra, não tem uso operacional
--   nenhum, e ler correspondência alheia não vira função de balcão.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (CREATE OR REPLACE).
-- =============================================================================

create or replace function public.admin_presentes(
  p_busca  text default null,
  p_status text default null,
  p_limite int default 300
)
returns table (
  id                 uuid,
  tier_slug          text,
  tier_nome          text,
  valor_centavos     integer,
  codigo             text,
  status             text,
  comprador_nome     text,
  comprador_email    text,
  resgatado_por_nome text,
  resgatado_em       timestamptz,
  created_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('resgates') then
    raise exception 'sem permissão pra ver os presentes';
  end if;

  return query
    select
      g.id,
      g.tier_slug,
      coalesce(t.nome, g.tier_slug)      as tier_nome,
      g.valor_centavos,
      g.codigo,
      g.status,
      coalesce(pc.full_name, '')         as comprador_nome,
      coalesce(uc.email::text, '')       as comprador_email,
      coalesce(pr.full_name, '')         as resgatado_por_nome,
      g.resgatado_em,
      g.created_at
      from public.gift_subscriptions g
      left join public.tiers      t  on t.slug = g.tier_slug
      left join public.profiles   pc on pc.id  = g.comprador_id
      left join auth.users        uc on uc.id  = g.comprador_id
      left join public.profiles   pr on pr.id  = g.resgatado_por
     where (p_status is null or p_status = '' or g.status = p_status)
       and (
         v_busca is null
         or g.codigo ilike '%' || v_busca || '%'
         or coalesce(pc.full_name, '') ilike '%' || v_busca || '%'
         or coalesce(uc.email::text, '') ilike '%' || v_busca || '%'
         or coalesce(pr.full_name, '') ilike '%' || v_busca || '%'
       )
     order by g.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 2000));
end;
$$;

revoke all on function public.admin_presentes(text, text, int) from public, anon;
grant execute on function public.admin_presentes(text, text, int) to authenticated;
