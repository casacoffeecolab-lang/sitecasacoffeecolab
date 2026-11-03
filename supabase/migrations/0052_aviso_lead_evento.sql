-- =============================================================================
-- 0052_aviso_lead_evento.sql — o pedido de evento toca o sino da casa 🔔
--
-- A 0040 resolveu o "o lead sobrevive ao canal": o pedido fica guardado mesmo
-- que a conversa do WhatsApp se perca. Ficou faltando o outro lado da mesma
-- moeda — ALGUÉM PRECISA SABER QUE ELE CHEGOU. Hoje o pedido cai na tabela e
-- espera alguém abrir o console e lembrar de olhar a aba "eventos". Quem pede
-- um evento está decidindo com outras casas ao mesmo tempo, e responder no dia
-- seguinte é responder depois de a pessoa já ter fechado com outro lugar.
--
-- Esta migration liga o INSERT da `leads_evento` a um aviso no Telegram da
-- equipe, passando pela Edge Function `avisar-lead-evento` (que também pede uma
-- leitura rápida do pedido pra uma API barata de IA antes de mandar).
--
-- POR QUE O GATILHO É O INSERT, E NÃO O FRONT:
--   • Chamar do navegador exigiria a chave do Telegram/Gemini no bundle, o que
--     as regras da casa proíbem (CLAUDE.md › Segurança).
--   • E o aviso morreria junto com a aba: quem preenche e fecha na hora é
--     exatamente o lead que a gente não pode perder.
--   O INSERT é o único momento em que um pedido virou pedido de verdade. Ele já
--   passou por toda a validação e pelo anti-flood de 30s da própria RPC, então
--   o freio do formulário é o freio do Telegram de graça: pedido repetido sem
--   querer não vira linha nova, e por isso também não vira ping repetido no
--   celular de quem atende.
--
-- O AVISO NUNCA PODE DERRUBAR O PEDIDO:
--   A /eventos tem uma regra que vale mais que o aviso: "o banco nunca barra a
--   pessoa" (o front já segue pro WhatsApp mesmo se a gravação falhar). Aqui é a
--   mesma coisa, um degrau abaixo: a trigger inteira roda dentro de um
--   `exception when others`, então extensão faltando, segredo não cadastrado ou
--   Telegram fora do ar viram um `warning` no log e nada mais. O lead entra do
--   mesmo jeito. Perder um aviso é ruim; perder o lead é pior.
--
-- ONDE MORAM OS SEGREDOS:
--   No **Vault** do Supabase, não neste arquivo e não numa tabela de config em
--   texto puro. A migration sobe sem saber a URL nem o token; enquanto os dois
--   não forem cadastrados, a trigger simplesmente não faz nada (nem erro). Os
--   dois comandos estão no rodapé deste arquivo e no README das functions.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP TRIGGER IF EXISTS).
-- =============================================================================

-- pg_net: o cliente HTTP assíncrono do Postgres. Ele ENFILEIRA a requisição e
-- devolve na hora, então a trigger não segura a transação esperando o Telegram
-- responder. E como a fila é uma tabela, um rollback do INSERT leva o aviso
-- junto: ninguém é avisado de um pedido que não existe.
create extension if not exists pg_net;

-- -----------------------------------------------------------------------------
-- Rastro: quando o aviso efetivamente saiu.
-- Existe pra responder "o sino tocou?" sem cavar o log da Edge Function. Fica
-- nulo enquanto o aviso não confirma, e é a própria function que carimba (com
-- service_role) depois que o Telegram aceita a mensagem.
-- -----------------------------------------------------------------------------
alter table public.leads_evento
  add column if not exists aviso_em timestamptz;

comment on column public.leads_evento.aviso_em is
  'Quando o aviso do Telegram saiu (carimbado pela Edge Function avisar-lead-evento). Nulo = não avisado.';

-- -----------------------------------------------------------------------------
-- aviso_lead_config() → (url, token) do Vault, ou nada.
--
-- Lê os dois segredos pelo nome. Se o Vault não existir, se os nomes não
-- estiverem cadastrados ou se qualquer coisa der errado na leitura, devolve
-- ZERO linhas em vez de estourar — é o que faz aplicar esta migration antes de
-- cadastrar os segredos ser seguro.
--
-- SECURITY DEFINER porque `vault.decrypted_secrets` não é legível por quem
-- chama a RPC (anon). E fora do alcance do client: sem grant pra anon nem pra
-- authenticated, ela só é chamável de dentro da trigger.
-- -----------------------------------------------------------------------------
create or replace function public.aviso_lead_config()
returns table (url text, token text)
language plpgsql
security definer
set search_path = public, vault, extensions
as $$
begin
  return query
    select
      max(case when s.name = 'casa_aviso_lead_url'   then s.decrypted_secret end)::text,
      max(case when s.name = 'casa_aviso_lead_token' then s.decrypted_secret end)::text
      from vault.decrypted_secrets s
     where s.name in ('casa_aviso_lead_url', 'casa_aviso_lead_token')
    having max(case when s.name = 'casa_aviso_lead_url'   then s.decrypted_secret end) is not null
       and max(case when s.name = 'casa_aviso_lead_token' then s.decrypted_secret end) is not null;
exception
  when others then
    -- Vault ausente/inacessível: sem aviso, sem barulho. Quem depende disto é a
    -- trigger, que já trata "não veio nada" como "não configurado ainda".
    return;
end;
$$;

revoke all on function public.aviso_lead_config() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- trg_avisar_lead_evento() — a trigger.
--
-- Monta o pedido inteiro em jsonb e joga na fila do pg_net. Manda o registro
-- COMPLETO de propósito: assim a Edge Function não precisa voltar ao banco pra
-- ler o que acabou de ser escrito, e o aviso continua saindo mesmo que a leitura
-- de volta fosse falhar.
--
-- O `exception when others` de fora é a peça mais importante do arquivo: a
-- partir daqui, qualquer coisa que der errado no caminho do aviso é um warning
-- no log do Postgres, nunca um erro na cara de quem está preenchendo o
-- formulário.
-- -----------------------------------------------------------------------------
create or replace function public.trg_avisar_lead_evento()
returns trigger
language plpgsql
security definer
set search_path = public, net, extensions
as $$
declare
  v_cfg   record;
  v_corpo jsonb;
begin
  select * into v_cfg from public.aviso_lead_config();

  -- Segredos ainda não cadastrados: o site funciona igual, só não avisa.
  if v_cfg.url is null or v_cfg.token is null then
    return new;
  end if;

  -- Teto de avisos por hora. A `registrar_lead_evento` é aberta a anon (quem
  -- pede evento raramente tem conta) e o anti-flood dela é POR CONTATO, então
  -- quem variar o telefone consegue gerar pedido à vontade. Isso já era verdade
  -- antes deste arquivo, só que ali o estrago parava na tabela; com o sino
  -- ligado, viraria o celular de quem atende tocando a noite inteira.
  -- Acima do teto o pedido ENTRA normalmente e aparece no console como sempre,
  -- só não vira ping. Vinte por hora é muito acima de um dia cheio de verdade.
  if (select count(*) from public.leads_evento
       where created_at > now() - interval '1 hour') > 20 then
    raise warning 'aviso de lead de evento segurado: mais de 20 pedidos na última hora (lead %)', new.id;
    return new;
  end if;

  v_corpo := jsonb_build_object(
    'lead', jsonb_build_object(
      'id',              new.id,
      'nome',            new.nome,
      'contato',         new.contato,
      'email',           new.email,
      'tipo',            new.tipo,
      'data_pretendida', new.data_pretendida,
      'pessoas',         new.pessoas,
      'mensagem',        new.mensagem,
      'origem',          new.origem,
      'created_at',      new.created_at
    )
  );

  perform net.http_post(
    url     := v_cfg.url,
    body    := v_corpo,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      -- Mesmo desenho do asaas-webhook: token compartilhado no header, que a
      -- function compara com o secret dela. Não é HMAC, e não precisa ser — os
      -- dois lados são nossos e o canal é HTTPS.
      'x-casa-token',  v_cfg.token
    ),
    -- Folgado de propósito: do outro lado a function fala com o Gemini e com o
    -- Telegram antes de responder (8s de teto cada). Com os 5s padrão, o pg_net
    -- registraria timeout num aviso que na verdade saiu, e a gente ficaria
    -- caçando um problema que não existe.
    timeout_milliseconds := 20000
  );

  return new;
exception
  when others then
    raise warning 'aviso de lead de evento não saiu (lead %): %', new.id, sqlerrm;
    return new;
end;
$$;

revoke all on function public.trg_avisar_lead_evento() from public, anon, authenticated;

drop trigger if exists avisar_lead_evento on public.leads_evento;
create trigger avisar_lead_evento
  after insert on public.leads_evento
  for each row
  execute function public.trg_avisar_lead_evento();

-- =============================================================================
-- DEPOIS DE APLICAR — os dois segredos do Vault (rodar UMA vez, com os valores
-- de verdade; NÃO versionar isto preenchido).
--
--   select vault.create_secret(
--     'https://<REF-DO-PROJETO>.supabase.co/functions/v1/avisar-lead-evento',
--     'casa_aviso_lead_url'
--   );
--   select vault.create_secret('<TOKEN-QUE-TU-ESCOLHER>', 'casa_aviso_lead_token');
--
-- Pra TROCAR um valor já cadastrado (o create_secret recusa nome repetido):
--   select vault.update_secret(
--     (select id from vault.secrets where name = 'casa_aviso_lead_token'),
--     '<TOKEN-NOVO>'
--   );
--
-- O mesmo token vai pro secret `LEAD_WEBHOOK_TOKEN` da Edge Function
-- (`npx supabase secrets set`). Passo a passo em supabase/functions/README.md.
--
-- CONFERIR que a ponte está de pé (deve devolver uma linha, com o token oculto):
--   select url, left(token, 4) || '…' as token from public.aviso_lead_config();
-- =============================================================================
