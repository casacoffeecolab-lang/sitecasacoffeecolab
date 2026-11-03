-- =============================================================================
-- 0034_lista_espera_rpc.sql — a lista de espera para de responder quem já entrou
--
-- O PROBLEMA (achado em auditoria de segurança):
--   A 0031 fecha a LEITURA direito: `lista_espera` tem policy de INSERT e nenhuma
--   de SELECT, então ninguém lê a lista pelo client. A promessa era que repetir um
--   e-mail respondesse igual a entrar pela primeira vez, pro formulário não virar
--   sonda de "fulano se inscreveu?". Só que quem garantia isso era o CLIENT: o
--   `ignoreDuplicates: true` do `app.js` vira o header `Prefer:
--   resolution=ignore-duplicates`. Quem não manda esse header recebe 201 pra
--   e-mail novo e 409 (`23505`) pra e-mail já cadastrado — com a anon key, sem
--   conta nenhuma. Com uma lista de endereços na mão, dá pra descobrir exatamente
--   quem se inscreveu. Era o único canal de leitura que o desenho queria fechar.
--
-- A CORREÇÃO: tirar o INSERT da mão do client e passar por uma RPC que faz o
--   `on conflict do nothing` POR DENTRO e devolve SEMPRE a mesma coisa. A
--   diferença entre e-mail novo e repetido deixa de existir do lado de fora, não
--   importa que header o chamador mande. Os mesmos limites da 0031 (formato e
--   tamanho) continuam valendo, agora no corpo da função.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez,
-- DEPOIS da 0031_lista_espera. Idempotente.
-- =============================================================================

-- Sem policy de INSERT, sem policy de SELECT: a tabela fica deny-by-default pro
-- client. Quem escreve é a RPC abaixo (SECURITY DEFINER), quem lê é a
-- admin_lista_espera (0031, gated por tem_permissao('relatorios')).
drop policy if exists lista_espera_insert_publico on public.lista_espera;

-- -----------------------------------------------------------------------------
-- entrar_na_lista_espera(email, origem) → jsonb {ok:true} | {ok:false, erro}
-- Resposta CONSTANTE pra e-mail novo e pra e-mail repetido: é isso que impede o
-- formulário de virar sonda. O único `ok:false` é e-mail malformado, que o
-- chamador já sabe (ele digitou) e não conta nada sobre a lista.
-- -----------------------------------------------------------------------------
create or replace function public.entrar_na_lista_espera(p_email text, p_origem text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email  text := lower(btrim(coalesce(p_email, '')));
  v_origem text := nullif(btrim(coalesce(p_origem, '')), '');
begin
  if char_length(v_email) not between 6 and 160
     or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    return jsonb_build_object('ok', false, 'erro', 'esse e-mail não parece completo');
  end if;

  if v_origem is not null then
    v_origem := left(v_origem, 120);
  end if;

  insert into public.lista_espera (email, origem)
  values (v_email, v_origem)
  on conflict (email) do nothing;

  -- Repetido ou novo, a mesma resposta. Pra quem está do outro lado da tela é a
  -- mesma coisa mesmo: já está na lista.
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.entrar_na_lista_espera(text, text) from public;
grant execute on function public.entrar_na_lista_espera(text, text) to anon, authenticated;
