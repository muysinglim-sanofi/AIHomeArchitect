-- ============================================================================
-- 20260911_billing_grant_perpetual_pack — OPTION A. NOT APPLIED.
-- Owner approval required: this replaces a function RevenueCat grants use.
--
-- Makes public.billing_grant_purchase able to grant a PERPETUAL credit pack
-- (duration_days IS NULL AND ends_at IS NULL), which today fails on
-- public.passes.ends_at NOT NULL. The new definition is the one DEPLOYED and
-- validated on staging (migration 0007 §4-§5), verbatim.
--
-- For every call that SUCCEEDS today the new definition is the same logic: the
-- only new branch is guarded by `p_duration_days is null and p_ends_at is null`,
-- a combination that currently raises. RevenueCat products carry a duration.
-- Measured in a rolled-back staging transaction (tests 1-4, 2026-09-11).
--
-- Guard: refuses to run unless the live definition is EXACTLY the one reviewed
-- (md5 of pg_get_functiondef = b42b47cb68773f11b02875d685d4e2f9).
-- Rollback: backend/sql/rollback/20260911_billing_grant_perpetual_pack_rollback.sql
-- ============================================================================

begin;

do $guard$
begin
  if md5(pg_get_functiondef('public.billing_grant_purchase(uuid,text,text,uuid,integer,integer,numeric,text,timestamptz,jsonb)'::regprocedure)) <> 'b42b47cb68773f11b02875d685d4e2f9' then
    raise exception 'public.billing_grant_purchase is not the definition this migration was reviewed against.';
  end if;
end
$guard$;

CREATE OR REPLACE FUNCTION public.billing_perpetual_ends_at()
 RETURNS timestamp with time zone
 LANGUAGE sql
 IMMUTABLE
AS $function$ select timestamptz '2999-12-31 00:00:00+00' $function$;

grant execute on function public.billing_perpetual_ends_at() to service_role;

CREATE OR REPLACE FUNCTION public.billing_grant_purchase(p_user_id uuid, p_provider text, p_provider_transaction_id text, p_product_id uuid, p_credits integer, p_duration_days integer, p_amount numeric, p_currency text, p_ends_at timestamp with time zone, p_raw_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_order_id     uuid;
  v_pass_id      uuid;
  v_payment_new  boolean := false;
  v_grant_new    boolean := false;
  v_order_key    text := 'order:' || p_provider || ':' || p_provider_transaction_id;
  v_grant_key    text;
  v_ends_at      timestamptz;
  v_available    int;
  -- NEW — a product with neither a duration nor an explicit window is a
  -- PERPETUAL one (the CREDIT_PACK rows). No RevenueCat product can be: they
  -- all carry duration_days.
  v_perpetual    boolean := (p_duration_days is null and p_ends_at is null);
begin
  if v_perpetual then
    v_ends_at := public.billing_perpetual_ends_at();
  else
    v_ends_at := coalesce(p_ends_at, now() + make_interval(days => p_duration_days));
  end if;

  insert into public.orders
    (user_id, product_id, status, provider, amount, currency, idempotency_key)
  values
    (p_user_id, p_product_id, 'PAID', p_provider, p_amount, coalesce(p_currency, 'USD'), v_order_key)
  on conflict (idempotency_key) do update
    set status = 'PAID', updated_at = now()
  returning id into v_order_id;

  v_grant_key := 'grant:order:' || v_order_id::text;

  insert into public.payments
    (order_id, provider, provider_transaction_id, status, amount, currency, raw_payload)
  values
    (v_order_id, p_provider, p_provider_transaction_id, 'SUCCESS', p_amount, p_currency, p_raw_payload)
  on conflict (provider, provider_transaction_id) do nothing;
  v_payment_new := found;

  -- NEW — a perpetual grant joins the user's EXISTING perpetual pass when there
  -- is one, so several credit packs accumulate in a single bucket instead of
  -- each creating a pass that hides the last.
  if v_perpetual then
    select id into v_pass_id
      from public.passes
     where user_id = p_user_id
       and status = 'ACTIVE'
       and ends_at = public.billing_perpetual_ends_at()
     order by created_at
     limit 1;
  end if;

  if v_pass_id is null then
    insert into public.passes
      (user_id, product_id, source_order_id, starts_at, ends_at, status)
    values
      (p_user_id, p_product_id, v_order_id, now(), v_ends_at, 'ACTIVE')
    on conflict (source_order_id) do nothing;
    select id into v_pass_id from public.passes where source_order_id = v_order_id;
  end if;

  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
  values
    (p_user_id, 'GRANT', p_credits, v_pass_id, 'ORDER', v_order_id::text, v_grant_key)
  on conflict (idempotency_key) do nothing;
  v_grant_new := found;

  perform public.billing_reproject_wallet(p_user_id);
  select available_credits into v_available
    from public.wallets where user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'status', case when v_grant_new then 'granted' else 'already_processed' end,
    'order_id', v_order_id,
    'pass_id', v_pass_id,
    'payment_new', v_payment_new,
    'credited', v_grant_new,
    'credits', case when v_grant_new then p_credits else 0 end,
    'available_credits', v_available
  );
end;
$function$;

commit;
