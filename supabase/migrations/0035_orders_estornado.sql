-- =============================================================================
-- 0035_orders_estornado.sql — um pedido estornado precisa saber que foi estornado
--
-- O PROBLEMA (achado em auditoria de segurança):
--   O `asaas-webhook` já estorna os pontos de uma ASSINATURA quando o pagamento é
--   devolvido ou vira chargeback — a defesa está lá, com o ataque descrito no
--   próprio comentário: pagar, ganhar pontos, resgatar a recompensa e pedir
--   chargeback. Só que o estorno procura o crédito por `ref_type='subscription'`
--   e `ref_id=payment.id`, e a LOJA credita por `ref_type='order'` /
--   `ref_id=order.id`. Nenhuma compra de loja era alcançada.
--
--   Além dos pontos, o pedido continuava `pago` — ou seja, seguia na fila de quem
--   vai separar e entregar, com o dinheiro já devolvido.
--
--   O `status` da 0001 não tinha como dizer isso: 'cancelado' é o pedido que nunca
--   foi pago (checkout expirou), e usar ele pra um pedido que foi pago e devolvido
--   apagaria a diferença entre as duas coisas no histórico e nos relatórios.
--
-- A CORREÇÃO: mais um estado, 'estornado'. O webhook passa a usá-lo (ver
--   `supabase/functions/asaas-webhook/index.ts`) junto com o lançamento negativo
--   no ledger.
--
-- APLICAR: rodar este arquivo inteiro no SQL Editor do Supabase, uma vez.
-- Idempotente (derruba o CHECK antigo pelo nome que estiver lá e recria).
-- =============================================================================

do $$
declare
  v_nome text;
begin
  select con.conname into v_nome
    from pg_constraint con
    join pg_class      rel on rel.oid = con.conrelid
    join pg_namespace  nsp on nsp.oid = rel.relnamespace
   where nsp.nspname = 'public'
     and rel.relname = 'orders'
     and con.contype = 'c'
     and pg_get_constraintdef(con.oid) ilike '%status%'
   limit 1;

  if v_nome is not null then
    execute format('alter table public.orders drop constraint %I', v_nome);
  end if;
end $$;

alter table public.orders
  add constraint orders_status_check
  check (status in ('pendente', 'pago', 'preparando', 'pronto', 'entregue', 'cancelado', 'estornado'));
