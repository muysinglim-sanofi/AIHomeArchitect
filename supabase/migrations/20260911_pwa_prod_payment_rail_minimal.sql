-- ============================================================================
-- 20260911_pwa_prod_payment_rail_minimal — the SMALLEST production footprint
-- for the FIRST ABA PayWay payment. NOT APPLIED. Owner approval required.
--
-- Creates ONLY what the payment rail reads and writes (pwa_staging_payments.py):
--   schema pwa                                    (namespace for the rail)
--   table  pwa.payway_transactions                (the rail's record, keyed by tran_id)
--   func   pwa.payway_claim(...)                  (single-flight claim of a tran_id)
--   3 indexes, 1 trigger (updated_at), 3 FKs, RLS + 1 own-row SELECT policy, grants
--
-- NOT created (not needed to take, verify and credit one payment): pwa_projects,
-- pwa_visions, pwa_messages, pwa_installations, pwa_generation_claims, the
-- generation RPCs, the pwa-images bucket and its storage policies, any product.
--
-- Every statement below is copied from 20260904_pwa_production_schema.sql
-- (lines 73, 284-329, 431-472, 478, 484, 621-629, 726-738, 822-843, 926-932,
-- 1052-1053, 1084-1085, 1111-1112) — a reviewed transform of the staging dump.
--
-- Touches iOS-used objects? It READS/REFERENCES, never alters: FKs to
-- public.orders / public.products / auth.users, and the updated_at trigger
-- executes the existing public.billing_set_updated_at(). No public.* row, no
-- public.* definition, no auth.* or storage.* change.
--
-- ALSO REQUIRED (not SQL, owner action in the Dashboard): add `pwa` to
-- Settings -> API -> Exposed schemas, because the backend reads the rail through
-- PostgREST with `.schema('pwa')`. Adding a schema leaves `public` unchanged.
--
-- CONSEQUENCE FOR LATER: 20260904_pwa_production_schema.sql refuses to run when
-- `pwa` exists. The full Web launch must apply a version of it WITHOUT these
-- rail objects (or roll this back first while no paid row exists).
--
-- Rollback: backend/sql/rollback/20260911_pwa_prod_payment_rail_minimal_rollback.sql
-- ============================================================================

begin;

set local check_function_bodies = off;

do $guard$
begin
  if exists (select 1 from pg_namespace where nspname = 'pwa') then
    raise exception 'Schema "pwa" already exists. Review before re-running.';
  end if;
  if to_regclass('public.orders') is null or to_regclass('public.products') is null then
    raise exception 'public.orders / public.products are missing.';
  end if;
  if to_regprocedure('public.billing_set_updated_at()') is null then
    raise exception 'public.billing_set_updated_at() is missing.';
  end if;
end
$guard$;

CREATE SCHEMA pwa;

CREATE FUNCTION pwa.payway_claim(p_tran_id text, p_user_id uuid, p_sku text, p_product_id uuid, p_credits integer, p_duration_days integer, p_amount numeric, p_currency text, p_order_idempotency_key text, p_attempt_key text, p_expires_at timestamp with time zone) RETURNS TABLE(won boolean, state text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pwa', 'public'
    AS $$
declare
  -- Longer than the adapter's 20 s PayWay timeout, so an in-flight generate-qr
  -- is never overtaken; short enough that a crashed process does not strand a
  -- person on a screen with no QR.
  v_stale      constant interval := interval '45 seconds';
  v_claimed_at timestamptz;
begin
  insert into pwa.payway_transactions
    (tran_id, user_id, sku, product_id, credits, duration_days, amount,
     currency, order_idempotency_key, attempt_key, expires_at)
  values
    (p_tran_id, p_user_id, p_sku, p_product_id, p_credits, p_duration_days,
     p_amount, p_currency, p_order_idempotency_key, p_attempt_key, p_expires_at)
  on conflict (tran_id) do nothing
  returning true, payway_transactions.state
  into won, state;

  if won then
    return next;
    return;
  end if;

  -- Someone holds it. Lock the row before deciding, so two retries of the same
  -- QR-less attempt cannot both conclude they may call PayWay.
  select t.state, t.claimed_at into state, v_claimed_at
    from pwa.payway_transactions t
   where t.tran_id = p_tran_id
   for update;

  if state = 'CREATED' and now() - v_claimed_at > v_stale then
    -- Abandoned before anything payable existed. Take it over, and say so, so
    -- the NEXT concurrent caller sees a fresh claim rather than a stale one.
    update pwa.payway_transactions
       set claimed_at = now()
     where tran_id = p_tran_id;
    won := true;
  else
    won := false;
  end if;
  return next;
end;
$$;

CREATE TABLE pwa.payway_transactions (
    tran_id text NOT NULL,
    user_id uuid NOT NULL,
    sku text NOT NULL,
    product_id uuid NOT NULL,
    credits integer NOT NULL,
    duration_days integer,
    amount numeric(10,2) NOT NULL,
    currency text NOT NULL,
    order_idempotency_key text NOT NULL,
    attempt_key text NOT NULL,
    state text DEFAULT 'CREATED'::text NOT NULL,
    qr_string text,
    qr_image text,
    deeplink text,
    app_store text,
    play_store text,
    expires_at timestamp with time zone NOT NULL,
    qr_issued_at timestamp with time zone,
    callback_received_at timestamp with time zone,
    callback_signature_ok boolean,
    callback_count integer DEFAULT 0 NOT NULL,
    last_checked_at timestamp with time zone,
    check_count integer DEFAULT 0 NOT NULL,
    payment_status text,
    payment_status_code integer,
    approval_code text,
    paid_amount numeric(10,2),
    paid_currency text,
    granted_order_id uuid,
    granted_at timestamp with time zone,
    failure_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    claimed_at timestamp with time zone DEFAULT now() NOT NULL,
    checkout_url text,
    checkout_mode text,
    CONSTRAINT payway_transactions_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT payway_transactions_credits_check CHECK ((credits > 0)),
    CONSTRAINT payway_transactions_currency_check CHECK ((currency = ANY (ARRAY['USD'::text, 'KHR'::text]))),
    CONSTRAINT payway_transactions_state_check CHECK ((state = ANY (ARRAY['CREATED'::text, 'AWAITING_PAYMENT'::text, 'PAID_PENDING_VERIFICATION'::text, 'VERIFIED'::text, 'GRANTED'::text, 'FAILED'::text, 'EXPIRED'::text, 'CANCELLED'::text])))
);

COMMENT ON COLUMN pwa.payway_transactions.checkout_url IS 'PayWay-hosted checkout URL from /payments/purchase. The browser is sent here; Ayden never renders ABA''s payment screen itself.';

COMMENT ON COLUMN pwa.payway_transactions.checkout_mode IS 'redirect | json | qr — which shape the gateway answered with. qr = 0007 legacy.';

ALTER TABLE ONLY pwa.payway_transactions
    ADD CONSTRAINT payway_transactions_order_idempotency_key_key UNIQUE (order_idempotency_key);

ALTER TABLE ONLY pwa.payway_transactions
    ADD CONSTRAINT payway_transactions_pkey PRIMARY KEY (tran_id);

ALTER TABLE ONLY pwa.payway_transactions
    ADD CONSTRAINT payway_transactions_granted_order_id_fkey FOREIGN KEY (granted_order_id) REFERENCES public.orders(id) ON DELETE SET NULL;

ALTER TABLE ONLY pwa.payway_transactions
    ADD CONSTRAINT payway_transactions_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);

ALTER TABLE ONLY pwa.payway_transactions
    ADD CONSTRAINT payway_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX payway_transactions_attempt_uidx ON pwa.payway_transactions USING btree (user_id, sku, attempt_key);

CREATE INDEX payway_transactions_open_idx ON pwa.payway_transactions USING btree (user_id, created_at DESC) WHERE (state = ANY (ARRAY['CREATED'::text, 'AWAITING_PAYMENT'::text, 'PAID_PENDING_VERIFICATION'::text, 'VERIFIED'::text]));

CREATE INDEX payway_transactions_sweep_idx ON pwa.payway_transactions USING btree (expires_at) WHERE (state = ANY (ARRAY['CREATED'::text, 'AWAITING_PAYMENT'::text]));

CREATE TRIGGER trg_payway_transactions_updated_at BEFORE UPDATE ON pwa.payway_transactions FOR EACH ROW EXECUTE FUNCTION public.billing_set_updated_at();

CREATE POLICY payway_own_select ON pwa.payway_transactions FOR SELECT TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));

ALTER TABLE pwa.payway_transactions ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA pwa TO authenticated;

GRANT USAGE ON SCHEMA pwa TO service_role;

REVOKE ALL ON FUNCTION pwa.payway_claim(p_tran_id text, p_user_id uuid, p_sku text, p_product_id uuid, p_credits integer, p_duration_days integer, p_amount numeric, p_currency text, p_order_idempotency_key text, p_attempt_key text, p_expires_at timestamp with time zone) FROM PUBLIC;

GRANT ALL ON FUNCTION pwa.payway_claim(p_tran_id text, p_user_id uuid, p_sku text, p_product_id uuid, p_credits integer, p_duration_days integer, p_amount numeric, p_currency text, p_order_idempotency_key text, p_attempt_key text, p_expires_at timestamp with time zone) TO service_role;

GRANT SELECT ON TABLE pwa.payway_transactions TO authenticated;

GRANT ALL ON TABLE pwa.payway_transactions TO service_role;

commit;
