-- ============================================================================
-- AYDEN STUDIO PWA — ABA PAYWAY (KHQR) SANDBOX RAIL
-- 0007 — additive, IDEMPOTENT.  Schemas: pwa_staging + public.  STAGING ONLY.
-- ----------------------------------------------------------------------------
-- WHY THIS FILE EXISTS
--
--   0006 installed the canonical Billing Engine and left ONE thing missing: a
--   way for money to arrive. `payment_provider_id()` returned 'none', the
--   paywall said so honestly, and the four web credit packs in `products` had
--   no rail. This file adds the rail, and nothing else.
--
--   It creates NO second entitlement system. Credits still appear exactly one
--   way — `public.billing_grant_purchase` — and this file's own table holds the
--   PayWay-specific facts that the canonical model has no column for (a KHQR
--   string, an ABA deeplink, a QR expiry, the last Check Transaction answer).
--   The MONEY object remains `public.orders`; see §1's note on the shared
--   idempotency key, which is what keeps it a single row rather than two.
--
-- WHAT IT CREATES
--   §1  table    pwa_staging.payway_transactions      — the rail's own record
--   §2  RLS      owner may READ; only service_role writes
--   §3  function pwa_staging.payway_claim(...)        — the atomic attempt claim
--   §4  function public.billing_perpetual_ends_at()   — the PERPETUAL sentinel
--   §5  function public.billing_grant_purchase(...)   — ADDITIVE redefinition:
--                                                       perpetual (credit-pack)
--                                                       grants, which the
--                                                       canonical version could
--                                                       not represent at all
--
-- WHAT IT NEVER DOES
--   * touch `public.orders`' provider CHECK — the KHQR rail is already a legal
--     value there (`check (provider in ('revenuecat', 'khqr'))`, 0006 §5), and
--     the brief is explicit that provider is the ACQUISITION RAIL, not the
--     gateway brand. Nothing named 'aba' or 'aba_payway' appears in this file.
--   * change `billing_try_hold`, `billing_reproject_wallet`, the ledger's
--     append-only trigger, or any consumption path.
--   * hold a secret. The merchant id and api key live only in
--     `backend/.env.pwa-staging.local`, which is gitignored.
--   * touch production. The guard below refuses unless the operator has proved
--     the target.
--
-- ── §5, STATED PLAINLY: WHY THE CANONICAL RPC HAD TO GROW ───────────────────
--
--   MEASURED, not assumed. `products` carries four CREDIT_PACK rows
--   (pack_10/25/50/100) with `duration_days IS NULL`. Feeding one of them to
--   the canonical `billing_grant_purchase` does this:
--
--       v_ends_at := coalesce(p_ends_at, now() + make_interval(days => NULL))
--                  = coalesce(NULL, NULL) = NULL
--       insert into public.passes (... ends_at ...) values (... NULL ...)
--       ERROR:  null value in column "ends_at" violates not-null constraint
--
--   So the canonical engine has never been able to grant a credit pack. It was
--   written for RevenueCat, where every product is a dated subscription. The
--   Cambodian Web launch sells exactly the products it cannot grant.
--
--   Three shapes were considered and two rejected:
--
--   (a) pass the pack a dated window from the adapter (no SQL change).
--       REJECTED — `billing_reproject_wallet` and `billing_try_hold` both pick
--       ONE active pass, `order by ends_at desc limit 1`. Buy pack_10 today and
--       pack_25 tomorrow and the second pass wins; the first pack's unspent
--       credits stop being counted. A person would pay twice and see one
--       balance. That is a silent loss of paid credits, and no amount of
--       adapter code can fix it from outside the projection.
--
--   (b) write the pack's GRANT into the unscoped bucket (`pass_id IS NULL`),
--       which `billing_reproject_wallet` sums unconditionally and which
--       therefore accumulates correctly.
--       REJECTED — that bucket is the FREE/TRIAL bucket. `has_active_pass`
--       would stay false, and `pwa_staging_billing.open_gate` derives the
--       watermark from exactly that signal: a paying customer would receive
--       watermarked images. It also collapses "granted a trial" and "bought
--       credits" into one number, which the RC_PR3B vocabulary exists to keep
--       apart.
--
--   (c) ADOPTED — a PERPETUAL pass. A product with no duration grants into a
--       pass whose `ends_at` is the sentinel below, and a user has at most ONE
--       of them: a second pack's GRANT attaches to the pass the first pack
--       created. Consequences, all of them the ones we want:
--         * packs ACCUMULATE (one bucket, summed by the existing projection);
--         * `has_active_pass` is true    -> no watermark on a paid render;
--         * `access_source` is 'pass'    -> the RC_PR3B vocabulary holds;
--         * `billing_try_hold` is pass-first -> the debit lands on the bucket
--           the projection displays, with no change to the RPC.
--       Nothing in the RevenueCat path can enter this branch: it is guarded on
--       `p_duration_days IS NULL AND p_ends_at IS NULL`, and every RC product
--       (weekly 7, annual 365) carries a duration.
--
--   KNOWN INTERACTION, recorded rather than hidden: a user holding BOTH a
--   perpetual pack and a dated RevenueCat pass has only the perpetual one
--   counted, because the sentinel sorts above every real date. That cannot
--   happen on the Cambodian Web launch (no RevenueCat on the Web, no KHQR on
--   mobile) and is listed as a pre-production item rather than solved here —
--   solving it means teaching the projection to sum several buckets, which is a
--   change to the consumption path and belongs to its own reviewed phase.
--
-- SAFETY
--   ONE transaction; the guard RAISEs before any DDL. Replayable.
--
--     set app.ayden_allow_staging_migrations = 'true';
--     set app.ayden_env = 'staging';
--
--   The operator MUST verify the connection target is project ref
--   eedcahzekpgxvvfxufbk before running.
-- ============================================================================

begin;

-- ── Guard (fail closed) ─────────────────────────────────────────────────────
do $guard$
begin
  if coalesce(current_setting('app.ayden_allow_staging_migrations', true), 'false') <> 'true' then
    raise exception
      'Refusing PWA staging migration 0007: app.ayden_allow_staging_migrations is not true (fail closed).';
  end if;
  if coalesce(current_setting('app.ayden_env', true), '') <> 'staging' then
    raise exception
      'Refusing PWA staging migration 0007: app.ayden_env is not ''staging'' (fail closed). Verify the connection target is the isolated staging project (ref eedcahzekpgxvvfxufbk).';
  end if;
  if not exists (select 1 from pg_namespace where nspname = 'pwa_staging') then
    raise exception
      'Refusing PWA staging migration 0007: schema pwa_staging does not exist. Apply 0002 first.';
  end if;
  if not exists (select 1 from information_schema.tables
                  where table_schema = 'public' and table_name = 'products') then
    raise exception
      'Refusing PWA staging migration 0007: the Billing Engine is absent. Apply 0006 first.';
  end if;
end
$guard$;


-- ════════════════════════════════════════════════════════════════════════════
-- §1 — pwa_staging.payway_transactions
-- ════════════════════════════════════════════════════════════════════════════
-- ONE ROW PER PAYMENT ATTEMPT, keyed by the `tran_id` PayWay itself keys on.
--
-- THE SHARED IDEMPOTENCY KEY, and why there is only one order row
--
--   `billing_grant_purchase` creates its own order with
--       idempotency_key = 'order:' || provider || ':' || provider_transaction_id
--   and `on conflict (idempotency_key) do update set status = 'PAID'`.
--
--   So the adapter creates its PENDING order under EXACTLY that key. The grant
--   then UPDATES that row to PAID instead of inserting a second one. One
--   purchase, one order, one row that moves PENDING -> PAID — and the canonical
--   order status is the money state machine, not a copy of it.
--
--   `order_idempotency_key` is stored here so that mapping is a fact on the row
--   rather than a convention two files have to agree on.
--
-- THE RICHER STATES, and where they live
--
--   `public.orders.status` has five values (PENDING/PAID/FAILED/CANCELLED/
--   REFUNDED) and they are the MONEY states. The rail has finer ones — a QR was
--   issued, a pushback arrived but has not been verified, Check Transaction
--   approved it but the grant has not run yet. Those are RAIL states and live
--   in `state` below. They never contradict the order: every terminal rail
--   state has exactly one order status it implies, and GRANTED is the only one
--   that implies PAID.
create table if not exists pwa_staging.payway_transactions (
  -- PayWay's own key, max 20 chars, unique per merchant FOREVER. Deterministic
  -- from (user, sku, attempt) — see `pwa_staging_payments.tran_id_for`.
  tran_id                text        primary key,
  user_id                uuid        not null references auth.users(id) on delete cascade,

  -- What the SERVER resolved from the canonical catalogue. The browser sends a
  -- sku and nothing else; every figure below is read from `public.products`, so
  -- a tampered request cannot change what is charged or what is granted.
  sku                    text        not null,
  product_id             uuid        not null references public.products(id),
  credits                int         not null check (credits > 0),
  duration_days          int,
  amount                 numeric(10, 2) not null check (amount > 0),
  currency               text        not null check (currency in ('USD', 'KHR')),

  -- 'order:khqr:<tran_id>' — the key `billing_grant_purchase` will use.
  order_idempotency_key  text        not null unique,
  -- The client's own "this is a new attempt" token. Same token = same tran_id =
  -- same QR; a NEW token is how a person deliberately starts over.
  attempt_key            text        not null,

  state                  text        not null default 'CREATED'
                                     check (state in (
                                       'CREATED',                  -- claimed, no QR yet
                                       'AWAITING_PAYMENT',         -- QR issued, live
                                       'PAID_PENDING_VERIFICATION',-- pushback seen, unverified
                                       'VERIFIED',                 -- Check Transaction: APPROVED
                                       'GRANTED',                  -- ledger GRANT written
                                       'FAILED',
                                       'EXPIRED',
                                       'CANCELLED')),

  -- What PayWay handed back. None of it is secret: it is the payment request a
  -- payer scans or taps, which is why it may reach the browser.
  qr_string              text,
  qr_image               text,        -- base64 PNG, exactly as PayWay returns it
  deeplink               text,        -- abapay_deeplink -> opens ABA Mobile
  app_store              text,
  play_store             text,

  expires_at             timestamptz not null,
  qr_issued_at           timestamptz,
  -- When someone last took responsibility for calling generate-qr. Not the same
  -- as `created_at`: a QR-less attempt may be re-claimed, and this is what makes
  -- "re-claimable" mean "abandoned" rather than "in flight". See §3.
  claimed_at             timestamptz not null default now(),

  -- Pushback forensics. `callback_signature_ok` is stored so a rejected
  -- notification is visible afterwards instead of only in a log line.
  callback_received_at   timestamptz,
  callback_signature_ok  boolean,
  callback_count         int         not null default 0,

  -- The last answer from Check Transaction — the only thing allowed to justify
  -- a grant.
  last_checked_at        timestamptz,
  check_count            int         not null default 0,
  payment_status         text,
  payment_status_code    int,
  approval_code          text,
  paid_amount            numeric(10, 2),
  paid_currency          text,

  granted_order_id       uuid        references public.orders(id) on delete set null,
  granted_at             timestamptz,
  -- A machine code, never a message: 'AMOUNT_MISMATCH', 'CURRENCY_MISMATCH',
  -- 'DECLINED', 'QR_REFUSED', 'DUPLICATE_TRAN_ID'. The client translates it.
  failure_reason         text,

  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

-- Replay safety: `create table if not exists` above does nothing on a database
-- that already has the table, so a column added after the first apply needs its
-- own statement. Idempotent, and cheap on an empty table.
alter table pwa_staging.payway_transactions
  add column if not exists claimed_at timestamptz not null default now();

-- One attempt token, one transaction. This is what makes a double-click, an F5
-- and a reconnect converge on the SAME PayWay transaction instead of three.
create unique index if not exists payway_transactions_attempt_uidx
  on pwa_staging.payway_transactions (user_id, sku, attempt_key);

-- "Does this person have a payment in progress?" — the query the PWA asks on
-- load so a refresh restores the sheet without the browser storing anything.
create index if not exists payway_transactions_open_idx
  on pwa_staging.payway_transactions (user_id, created_at desc)
  where state in ('CREATED', 'AWAITING_PAYMENT', 'PAID_PENDING_VERIFICATION', 'VERIFIED');

create index if not exists payway_transactions_sweep_idx
  on pwa_staging.payway_transactions (expires_at)
  where state in ('CREATED', 'AWAITING_PAYMENT');

drop trigger if exists trg_payway_transactions_updated_at on pwa_staging.payway_transactions;
create trigger trg_payway_transactions_updated_at
  before update on pwa_staging.payway_transactions
  for each row execute function public.billing_set_updated_at();


-- ════════════════════════════════════════════════════════════════════════════
-- §2 — RLS: the owner may READ, and nobody but service_role may WRITE
-- ════════════════════════════════════════════════════════════════════════════
-- The browser never writes a payment state — that is the whole point of the
-- design — so there is deliberately no insert/update/delete policy for
-- `authenticated`. service_role bypasses RLS and is the only writer.
--
-- Read is granted to the owner because it costs nothing and makes support and
-- debugging possible without a service key. Nothing readable here is a secret:
-- the QR is a payment request, and the amount is what the person is being asked
-- to pay.
alter table pwa_staging.payway_transactions enable row level security;

do $policies$
begin
  if not exists (select 1 from pg_policies
                 where schemaname = 'pwa_staging'
                   and tablename = 'payway_transactions'
                   and policyname = 'payway_own_select') then
    create policy payway_own_select on pwa_staging.payway_transactions
      for select to authenticated using (user_id = (select auth.uid()));
  end if;
end
$policies$;

-- USAGE ON THE SCHEMA, and why this line exists at all.
--
-- MEASURED, on the live staging project: `service_role` had every table
-- privilege on this table and still could not read a row —
--
--     postgrest.exceptions.APIError:
--       {'message': 'permission denied for schema pwa_staging', 'code': '42501'}
--
-- because 0002 and 0004 granted `usage on schema pwa_staging` to `authenticated`
-- and to nobody else. Until now that was invisible: every existing pwa_staging
-- caller is the BROWSER, holding a user token, and service_role never had to
-- enter this schema. The payment rail is the first thing the SERVER owns here,
-- so it is the first thing to hit the gap. Table grants do not imply schema
-- usage, and a missing `usage` fails as a 500 rather than as an empty result.
grant usage   on schema pwa_staging to service_role;
grant select  on pwa_staging.payway_transactions to authenticated;
grant all     on pwa_staging.payway_transactions to service_role;


-- ════════════════════════════════════════════════════════════════════════════
-- §3 — pwa_staging.payway_claim: one attempt, one caller, one PayWay call
-- ════════════════════════════════════════════════════════════════════════════
-- Returns `won = true` to EXACTLY ONE caller for a given tran_id. The winner is
-- the only one that may call generate-qr, so a double-click cannot create two
-- PayWay transactions — and even if it somehow did, PayWay's own 403 on a
-- duplicate tran_id is the second net.
--
-- A row still in CREATED (claimed, but no QR came back — a timeout, a crash
-- between the claim and the answer) is RE-claimable ONCE THE CLAIM IS STALE.
-- The staleness window matters and was measured, not guessed: without it, five
-- simultaneous submits all read `state = 'CREATED'` — the state the FIRST one is
-- still working in — and all five call generate-qr. Four of them earn PayWay's
-- 403 "duplicate transaction", and the person sees a failure caused entirely by
-- their own double-click.
--
-- So "re-claimable" means ABANDONED, not "not finished yet": `claimed_at` must
-- be older than the window below, which is deliberately longer than the adapter's
-- 20-second PayWay timeout so an in-flight call is never overtaken.
--
-- A row that has ever reached any other state is never re-claimable: re-issuing
-- a QR for a transaction PayWay already knows would earn a 403, and re-issuing
-- for one already paid would be a second charge.
create or replace function pwa_staging.payway_claim(
  p_tran_id               text,
  p_user_id               uuid,
  p_sku                   text,
  p_product_id            uuid,
  p_credits               int,
  p_duration_days         int,
  p_amount                numeric,
  p_currency              text,
  p_order_idempotency_key text,
  p_attempt_key           text,
  p_expires_at            timestamptz
)
returns table (won boolean, state text)
language plpgsql
security definer
set search_path = pwa_staging, public
as $$
declare
  -- Longer than the adapter's 20 s PayWay timeout, so an in-flight generate-qr
  -- is never overtaken; short enough that a crashed process does not strand a
  -- person on a screen with no QR.
  v_stale      constant interval := interval '45 seconds';
  v_claimed_at timestamptz;
begin
  insert into pwa_staging.payway_transactions
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
    from pwa_staging.payway_transactions t
   where t.tran_id = p_tran_id
   for update;

  if state = 'CREATED' and now() - v_claimed_at > v_stale then
    -- Abandoned before anything payable existed. Take it over, and say so, so
    -- the NEXT concurrent caller sees a fresh claim rather than a stale one.
    update pwa_staging.payway_transactions
       set claimed_at = now()
     where tran_id = p_tran_id;
    won := true;
  else
    won := false;
  end if;
  return next;
end;
$$;

revoke all on function pwa_staging.payway_claim(
  text, uuid, text, uuid, int, int, numeric, text, text, text, timestamptz) from public;
grant execute on function pwa_staging.payway_claim(
  text, uuid, text, uuid, int, int, numeric, text, text, text, timestamptz) to service_role;


-- ════════════════════════════════════════════════════════════════════════════
-- §4 — the PERPETUAL sentinel
-- ════════════════════════════════════════════════════════════════════════════
-- A finite far-future timestamp, NOT `'infinity'::timestamptz`, and the reason
-- is a client one: `infinity` serialises as the string "infinity" through
-- PostgREST, and every date parser downstream — Dart's `DateTime.parse`
-- included — throws on it. A date in the year 2999 sorts above every real pass,
-- reads unambiguously to a human scanning the table, and parses everywhere.
create or replace function public.billing_perpetual_ends_at()
returns timestamptz
language sql
immutable
as $$ select timestamptz '2999-12-31 00:00:00+00' $$;

grant execute on function public.billing_perpetual_ends_at() to service_role;


-- ════════════════════════════════════════════════════════════════════════════
-- §5 — billing_grant_purchase, ADDITIVE: perpetual (credit-pack) grants
-- ════════════════════════════════════════════════════════════════════════════
-- Byte-for-byte the 0006 §8 body, plus the two guarded blocks marked NEW. The
-- rationale is at the head of this file. Signature, return shape, idempotency
-- keys and every dated-product code path are unchanged.
create or replace function public.billing_grant_purchase(
  p_user_id                 uuid,
  p_provider                text,
  p_provider_transaction_id text,
  p_product_id              uuid,
  p_credits                 int,
  p_duration_days           int,
  p_amount                  numeric,
  p_currency                text,
  p_ends_at                 timestamptz,
  p_raw_payload             jsonb
) returns jsonb
language plpgsql
as $$
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
$$;

grant execute on function public.billing_grant_purchase(
  uuid, text, text, uuid, int, int, numeric, text, timestamptz, jsonb
) to service_role;

commit;
