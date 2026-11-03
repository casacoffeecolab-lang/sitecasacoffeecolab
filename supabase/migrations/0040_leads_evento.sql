-- =============================================================================
-- 0040_leads_evento.sql — "faz teu evento aqui" (pedidos de festa/encontro) 🎉
--
-- O Casa se define como café-casa de ENCONTROS, e quem quer alugar o espaço pra
-- um aniversário, um workshop ou uma reunião só tinha um caminho: descobrir o
-- telefone no rodapé e começar a conversa do zero, sem dizer quando, pra quantos
-- nem do quê. A página /eventos coleta isso num formulário e leva a pessoa pro
-- WhatsApp da casa com a mensagem já escrita.
--
-- POR QUE O PEDIDO TAMBÉM FICA GUARDADO AQUI:
--   O WhatsApp é o canal, não o arquivo. Se a pessoa preenche e não aperta
--   enviar, se o link não abre no aparelho dela, ou se a conversa se perde em
--   trinta mensagens novas, o pedido evapora. Gravar ANTES de mandar pro
--   WhatsApp faz o lead sobreviver ao canal: o console mostra todos, do mais
--   recente pro mais antigo, com um botão de "já falei com essa pessoa".
--
-- MODELAGEM / SEGURANÇA (ver CLAUDE.md › Segurança):
--   • Tabela DENY-BY-DEFAULT: RLS ligada e NENHUMA policy. O client não lê nem
--     escreve direto. Quem escreve é a `registrar_lead_evento` (SECURITY
--     DEFINER, aberta a anon porque quem pede evento normalmente nem tem conta);
--     quem lê é o console, pela `admin_leads_evento`.
--     É diferente da 0031, que nasceu com policy de INSERT pro client e precisou
--     da 0034 pra tirar. Aqui já nasce pela porta certa.
--   • O dado É pessoal (nome + telefone + o que a pessoa quer comemorar), então
--     não entra na turma dos "benignos" (favoritos, desejos) que o client
--     escreve direto. Nada de INSERT do lado de fora.
--   • Anti-flood de 30s pelo mesmo contato, no corpo da função: endpoint público
--     de escrita sem freio é convite pra encher a tabela. Repetição dentro da
--     janela responde `ok:true` e não grava, que é o mesmo que a pessoa vê ao
--     apertar duas vezes sem querer.
--   • `user_id` guarda quem estava logado, se estava. É opcional de propósito:
--     exigir conta pra pedir um orçamento afastaria justamente quem ainda não é
--     de casa.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE).
-- =============================================================================

create table if not exists public.leads_evento (
  id              uuid primary key default gen_random_uuid(),
  nome            text not null check (char_length(nome) between 2 and 80),
  -- O telefone chega formatado pela máscara do site ((51) 99999-9999). Guardar o
  -- texto como a pessoa vê é a mesma escolha do profiles.telefone.
  contato         text not null check (char_length(contato) between 8 and 40),
  email           text check (
                    email is null
                    or (char_length(email) between 6 and 160
                        and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
                  ),
  -- Tipo é texto livre limitado, não CHECK com lista: a casa vai inventar tipo
  -- de evento novo antes de a gente escrever outra migration, e o console escapa
  -- tudo o que mostra.
  tipo            text not null check (char_length(tipo) between 2 and 40),
  data_pretendida date,
  pessoas         int check (pessoas is null or pessoas between 1 and 500),
  mensagem        text check (mensagem is null or char_length(mensagem) <= 600),
  origem          text check (origem is null or char_length(origem) <= 120),
  status          text not null default 'novo' check (status in ('novo', 'atendido', 'arquivado')),
  user_id         uuid references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  atendido_em     timestamptz,
  atendido_por    uuid references auth.users (id) on delete set null
);

create index if not exists idx_leads_evento_created on public.leads_evento (created_at desc);
create index if not exists idx_leads_evento_status on public.leads_evento (status, created_at desc);

alter table public.leads_evento enable row level security;

-- Nenhuma policy, de propósito: RLS ligada sem policy = ninguém passa pelo
-- PostgREST, nem anon nem logado. As duas portas são as funções abaixo.

-- -----------------------------------------------------------------------------
-- registrar_lead_evento(...) → jsonb {ok:true} | {ok:false, erro}
-- Aberta a anon: quem quer fazer um evento aqui raramente já tem conta.
-- O `ok:false` só acontece em campo malformado, que quem digitou já sabe.
-- -----------------------------------------------------------------------------
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
    return jsonb_build_object('ok', true);
  end if;

  insert into public.leads_evento (nome, contato, email, tipo, data_pretendida, pessoas, mensagem, origem, user_id)
  values (v_nome, v_contato, v_email, v_tipo, p_data, p_pessoas, v_mensagem, v_origem, auth.uid())
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

revoke all on function public.registrar_lead_evento(text, text, text, text, date, int, text, text) from public;
grant execute on function public.registrar_lead_evento(text, text, text, text, date, int, text, text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- admin_leads_evento(busca, status, limite) → a fila de pedidos de evento.
-- Mesma porta dos outros relatórios de interesse (favoritos, desejos, lista de
-- espera): 'relatorios'. Não precisou de permissão nova, e ainda bem — o
-- whitelist de permissões é fechado por CHECK na 0017, então permissão nova
-- pediria outra migration só pra isso.
-- -----------------------------------------------------------------------------
create or replace function public.admin_leads_evento(
  p_busca  text default null,
  p_status text default null,
  p_limite int default 300
)
returns table (
  id              uuid,
  nome            text,
  contato         text,
  email           text,
  tipo            text,
  data_pretendida date,
  pessoas         int,
  mensagem        text,
  origem          text,
  status          text,
  created_at      timestamptz,
  atendido_em     timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra ver os pedidos de evento';
  end if;

  return query
    select l.id, l.nome, l.contato, l.email, l.tipo, l.data_pretendida, l.pessoas,
           l.mensagem, l.origem, l.status, l.created_at, l.atendido_em
      from public.leads_evento l
     where (p_status is null or p_status = '' or l.status = p_status)
       and (
         v_busca is null
         or l.nome ilike '%' || v_busca || '%'
         or l.contato ilike '%' || v_busca || '%'
         or coalesce(l.email, '') ilike '%' || v_busca || '%'
         or l.tipo ilike '%' || v_busca || '%'
       )
     order by l.created_at desc
     limit greatest(1, least(coalesce(p_limite, 300), 2000));
end;
$$;

revoke all on function public.admin_leads_evento(text, text, int) from public, anon;
grant execute on function public.admin_leads_evento(text, text, int) to authenticated;

-- -----------------------------------------------------------------------------
-- admin_lead_evento_status(id, status) → marca "já falei" / "arquivado" / volta
-- pra "novo". Uma lista de pedidos sem onde riscar o que já foi atendido vira
-- uma pilha que só cresce.
-- -----------------------------------------------------------------------------
create or replace function public.admin_lead_evento_status(p_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_status text := btrim(coalesce(p_status, ''));
begin
  if not public.tem_permissao('relatorios') then
    raise exception 'sem permissão pra mexer nos pedidos de evento';
  end if;

  if v_status not in ('novo', 'atendido', 'arquivado') then
    raise exception 'status inválido';
  end if;

  update public.leads_evento
     set status       = v_status,
         atendido_em  = case when v_status = 'novo' then null else now() end,
         atendido_por = case when v_status = 'novo' then null else v_uid end
   where id = p_id;

  if not found then
    raise exception 'pedido não encontrado';
  end if;

  insert into public.audit_log (actor_id, action, entity, entity_id, detalhe)
  values (v_uid, 'lead_evento_status', 'leads_evento', p_id::text,
          jsonb_build_object('status', v_status));

  return jsonb_build_object('ok', true, 'status', v_status);
end;
$$;

revoke all on function public.admin_lead_evento_status(uuid, text) from public, anon;
grant execute on function public.admin_lead_evento_status(uuid, text) to authenticated;
