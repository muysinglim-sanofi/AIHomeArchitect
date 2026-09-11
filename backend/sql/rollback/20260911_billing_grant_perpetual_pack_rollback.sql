-- ============================================================================
-- ROLLBACK of 20260911_billing_grant_perpetual_pack. NOT APPLIED.
--
-- Restores the production definition of public.billing_grant_purchase exactly
-- as it was read on 2026-09-11 (md5 b42b47cb68773f11b02875d685d4e2f9) and verifies it.
-- public.billing_perpetual_ends_at() is LEFT in place on purpose: passes already
-- granted as perpetual carry its value (a date), nothing else references it,
-- and removing it is optional (commented below).
-- After this rollback, a perpetual pack can no longer be granted (it fails as
-- before) — do not roll back while the Web rail is open for sale.
-- ============================================================================

begin;

CREATE OR REPLACE FUNCTION public.billing_grant_purchase(p_user_id uuid, p_provider text, p_provider_transaction_id text, p_product_id uuid, p_credits integer, p_duration_days integer, p_amount numeric, p_currency text, p_ends_at timestamp with time zone, p_raw_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$

declare

  v_order_id uuid; v_pass_id uuid; v_payment_new boolean := false; v_grant_new boolean := false;

  v_order_key text := 'order:' || p_provider || ':' || p_provider_transaction_id;

  v_grant_key text; v_ends_at timestamptz; v_available int;

begin

  v_ends_at := coalesce(p_ends_at, now() + make_interval(days => p_duration_days));



  insert into public.orders (user_id, product_id, status, provider, amount, currency, idempotency_key)

  values (p_user_id, p_product_id, 'PAID', p_provider, p_amount, coalesce(p_currency,'USD'), v_order_key)

  on conflict (idempotency_key) do update set status='PAID', updated_at=now()

  returning id into v_order_id;



  v_grant_key := 'grant:order:' || v_order_id::text;



  insert into public.payments (order_id, provider, provider_transaction_id, status, amount, currency, raw_payload)

  values (v_order_id, p_provider, p_provider_transaction_id, 'SUCCESS', p_amount, p_currency, p_raw_payload)

  on conflict (provider, provider_transaction_id) do nothing;

  v_payment_new := found;



  insert into public.passes (user_id, product_id, source_order_id, starts_at, ends_at, status)

  values (p_user_id, p_product_id, v_order_id, now(), v_ends_at, 'ACTIVE')

  on conflict (source_order_id) do nothing;

  select id into v_pass_id from public.passes where source_order_id = v_order_id;



  insert into public.ledger_entries

    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)

  values (p_user_id, 'GRANT', p_credits, v_pass_id, 'ORDER', v_order_id::text, v_grant_key)

  on conflict (idempotency_key) do nothing;

  v_grant_new := found;



  perform public.billing_reproject_wallet(p_user_id);   -- projection PASS-AWARE

  select available_credits into v_available from public.wallets where user_id = p_user_id;



  return jsonb_build_object(

    'ok', true,

    'status', case when v_grant_new then 'granted' else 'already_processed' end,

    'order_id', v_order_id, 'pass_id', v_pass_id, 'payment_new', v_payment_new,

    'credited', v_grant_new,

    'credits', case when v_grant_new then p_credits else 0 end,

    'available_credits', v_available);

end; $function$;

do $check$
begin
  if md5(pg_get_functiondef('public.billing_grant_purchase(uuid,text,text,uuid,integer,integer,numeric,text,timestamptz,jsonb)'::regprocedure)) <> 'b42b47cb68773f11b02875d685d4e2f9' then
    raise exception 'restore did not reproduce the original definition - aborting.';
  end if;
end
$check$;

-- drop function if exists public.billing_perpetual_ends_at();

commit;
