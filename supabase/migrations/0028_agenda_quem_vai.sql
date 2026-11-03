-- =============================================================================
-- 0028_agenda_quem_vai.sql — "Quem vai" nos encontros 👋
--
-- A agenda (0026) já conta os confirmados; o "meu cantinho" (0024) já dá rosto
-- público a quem quer. Isto junta os dois: cada encontro passa a mostrar os
-- ROSTINHOS de quem vai — mas SÓ de quem ligou o perfil público. Todo o resto
-- continua contado de forma anônima, exatamente como antes.
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Privacidade por construção: só entram no payload os RSVPs de quem tem
--     `perfil_publico = true`. Quem não optou nunca aparece — só soma na contagem.
--   • O payload é CURADO (handle, nome de exibição, avatar) — os mesmos campos já
--     públicos pelo `perfil_publico()` e pela página `/gente/{handle}`. Nada novo é
--     exposto; e-mail/telefone/nome real completo continuam de fora.
--   • Só reescreve a função de LEITURA `agenda_proximos` (adiciona a coluna
--     `vao_publicos`). Nenhuma tabela nova, nenhuma permissão nova.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (DROP FUNCTION IF EXISTS + CREATE).
-- =============================================================================

-- Adicionar uma coluna ao retorno muda a assinatura → precisa dropar e recriar
-- (CREATE OR REPLACE não troca o tipo de retorno de uma função que devolve TABLE).
drop function if exists public.agenda_proximos();

create function public.agenda_proximos()
returns table (
  id            uuid,
  nome          text,
  descricao     text,
  data          timestamptz,
  local         text,
  vagas         integer,
  confirmados   bigint,
  eu_vou        boolean,
  lotado        boolean,
  vao_publicos  jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    e.id, e.nome, e.descricao, e.data, e.local, e.vagas,
    coalesce(c.n, 0)                                     as confirmados,
    (auth.uid() is not null and r.user_id is not null)   as eu_vou,
    (e.vagas is not null and coalesce(c.n, 0) >= e.vagas) as lotado,
    -- Só os presentes com perfil público (handle, nome de exibição, avatar).
    -- Quem não optou nunca entra aqui — mas continua contado em `confirmados`.
    coalesce((
      select jsonb_agg(sub.obj order by sub.ord)
      from (
        select
          jsonb_build_object(
            'handle',     p.handle,
            'nome',       coalesce(
                            nullif(btrim(p.apelido), ''),
                            nullif(split_part(btrim(coalesce(p.full_name, '')), ' ', 1), ''),
                            'alguém do Casa'),
            'avatar_url', p.avatar_url
          )        as obj,
          rr.created_at as ord
        from public.event_rsvps rr
        join public.profiles p on p.id = rr.user_id
        where rr.event_id = e.id
          and p.perfil_publico = true
          and p.handle is not null
        order by rr.created_at asc
        limit 12
      ) sub
    ), '[]'::jsonb)                                      as vao_publicos
  from public.events e
  left join lateral (
    select count(*) as n from public.event_rsvps rc where rc.event_id = e.id
  ) c on true
  left join public.event_rsvps r
    on r.event_id = e.id and r.user_id = auth.uid()
  where e.ativo
    and (e.data is null or e.data >= now() - interval '4 hours')
  order by e.data asc nulls last, e.created_at asc
  limit 12;
$$;

revoke all on function public.agenda_proximos() from public;
grant execute on function public.agenda_proximos() to anon, authenticated;
