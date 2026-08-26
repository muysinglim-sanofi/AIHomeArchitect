-- ============================================================================
-- AYDEN STUDIO PWA — ABA PayWay: the CHECKOUT belongs to ABA
-- 0008 — additive, IDEMPOTENT.  Schema: pwa_staging.  STAGING ONLY.
-- ----------------------------------------------------------------------------
-- WHY THIS FILE EXISTS
--
--   ABA confirmed in writing on 2026-08-19:
--
--     "For website app or native app integration please use this endpoint to
--      match the guidelines"  ->  /api/payment-gateway/v1/payments/purchase
--
--   0007 was built on `generate-qr`, which hands back a KHQR and leaves AYDEN to
--   draw the checkout. That worked, and it is not what ABA's guideline asks for:
--   the payment screen is theirs. `purchase` answers with a URL on PayWay's own
--   domain, and the browser goes there.
--
--   So one thing changes about what we store: a payment attempt now has a PLACE
--   TO PAY (`checkout_url`) rather than only a code to render. Everything else —
--   the state machine, the amounts resolved server-side, the idempotency key,
--   the verification columns — is unchanged, because none of it depended on
--   which acquisition endpoint issued the transaction.
--
-- WHAT THIS DOES NOT DO
--
--   * It does not drop the QR columns. `qr_string` / `deeplink` are still
--     populated in the `abapay_khqr_deeplink` mode, and a transaction issued by
--     0007's `generate-qr` path must keep rendering after this runs. Dropping a
--     column to express "we moved on" would break exactly the rows that prove
--     the move was safe.
--   * It does not touch `public.*`. The Billing Engine is untouched: PayWay is a
--     rail, `orders.provider` is still 'khqr', and nothing about the grant path
--     changes because the checkout moved.
-- ============================================================================

-- ── the place to pay ────────────────────────────────────────────────────────
-- PayWay's own checkout, on PayWay's own domain. Not a secret: it is where we
-- send the customer, it is single-use, and it identifies a transaction that is
-- already scoped to one user by `payway_transactions.user_id`.
alter table pwa_staging.payway_transactions
  add column if not exists checkout_url text;

-- HOW PayWay answered, so a support question is readable without a log dive:
--   'redirect' — HTTP 302, Location: the checkout   (hosted_view / popup)
--   'json'     — HTTP 200, checkout_qr_url          (abapay_khqr_deeplink)
--   'qr'       — issued by the DEPRECATED generate-qr path (0007 rows)
alter table pwa_staging.payway_transactions
  add column if not exists checkout_mode text;

comment on column pwa_staging.payway_transactions.checkout_url is
  'PayWay-hosted checkout URL from /payments/purchase. The browser is sent here; '
  'Ayden never renders ABA''s payment screen itself.';
comment on column pwa_staging.payway_transactions.checkout_mode is
  'redirect | json | qr — which shape the gateway answered with. qr = 0007 legacy.';

-- Rows that predate this migration were issued by `generate-qr`. Naming them is
-- what keeps "has no checkout_url" from looking like a bug in a new row.
update pwa_staging.payway_transactions
   set checkout_mode = 'qr'
 where checkout_mode is null
   and qr_string is not null;

-- ── grants ──────────────────────────────────────────────────────────────────
-- Unchanged in substance; repeated because a new column inherits nothing. The
-- service role is the only writer, and the browser reads through the API, never
-- through PostgREST.
grant select, insert, update on pwa_staging.payway_transactions to service_role;
