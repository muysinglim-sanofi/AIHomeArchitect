# ABA PayWay — KHQR sandbox rail for the Cambodia Web launch

> Phase `pwa-monetization`, 2026-08-18. Sandbox only. Nothing here touches
> production, mobile, or the creative engine.

This is the implementation note the brief asked for: the **official** protocol
contract, the decisions taken, what is proven, and the single external step that
is left.

---

## 0 — Status in one screen

| | |
|---|---|
| API surface | **QR API** (`generate-qr`) + **Check Transaction** (`check-transaction-2`) + pushback |
| Payment option | `abapay_khqr` — one call returns a KHQR string, a QR image **and** an ABA Mobile deeplink |
| Rail (`orders.provider`) | `khqr` — unchanged, no schema modification |
| Product sold | the existing web-sellable `CREDIT_PACK` rows (`pack_10/25/50/100`) |
| Grant path | the canonical `billing_grant_purchase` — no second entitlement system |
| Public callback | **not configured** → the adapter runs *poll-only*, which is correct, not degraded |
| Tests | 59 rail + 95 seam + 39 DB + 19 Flutter + 16 live probe, all green |
| Blocked | a real sandbox payment: credentials not yet in the ignored env file, and the egress IP is not whitelisted by ABA |

---

## 1 — The official protocol contract

Read from the **ABA PayWay Developer Suite** on 2026-08-18. Community
documentation was deliberately not used: `PWA_MONETIZATION_AUDIT` §4.2 had been
written from a community mirror and flagged itself as unverified. This section
supersedes it. Every line below is mirrored in the module docstring of
[`backend/payway.py`](../backend/payway.py) so the contract sits next to the code
that implements it.

### Base URLs — <https://developer.payway.com.kh/api-endpoints-984508m0>

```
sandbox     https://checkout-sandbox.payway.com.kh/
production  https://checkout.payway.com.kh/
```

> "You can only access the API from a domain or IP address that has been
> whitelisted by PayWay."

That applies to the **outbound** call, not only to the callback. It is why a
fresh merchant sees error code `6` before anything else works, and it is one half
of the external blocker in §8.

### QR API — <https://developer.payway.com.kh/qr-api-14530840e0>

`POST /api/payment-gateway/v1/payments/generate-qr`, `Content-Type: application/json`.

Required: `req_time`, `merchant_id`, `tran_id`, `payment_option`, `amount`,
`currency`, `lifetime`, `qr_image_template`, `hash`.
`payment_option ∈ {abapay_khqr, wechat, alipay}`; `amount` numeric, min 0.01 USD
/ 100 KHR; `lifetime` in **minutes**, min 3; `tran_id` max 20 characters.

Hash — `base64(hmac_sha512(concat, api_key))` over, **in this order**:

```
req_time, merchant_id, tran_id, amount, items, first_name, last_name, email,
phone, purchase_type, payment_option, callback_url, return_deeplink, currency,
custom_fields, return_params, payout, lifetime, qr_image_template
```

Absent optional fields contribute the **empty string** — the documented PHP
sample concatenates all nineteen unconditionally, with no null branch.

Response: `qrString`, `qrImage` (base64 PNG), `abapay_deeplink`, `app_store`,
`play_store`, `amount`, `currency`, `status{code,message,trace_id}`.
`status.code` `0` = success, `1` = wrong hash, **`6` = domain not whitelisted**,
**`403` = duplicate transaction**, `429` = rate limited.

### Check Transaction — <https://developer.payway.com.kh/check-transaction-14530826e0>

`POST /api/payment-gateway/v1/payments/check-transaction-2`, `application/json`.
Body `req_time`, `merchant_id`, `tran_id`, `hash`, where
`hash = base64(hmac_sha512(req_time + merchant_id + tran_id, api_key))`.

Response: `payment_status_code` (**0 APPROVED / PRE-AUTH**, 2 PENDING,
3 DECLINED, 4 REFUNDED, 7 CANCELLED), `payment_status`, `total_amount`,
`original_amount`, `payment_amount`, `payment_currency`, `apv`, `refund_amount`,
`discount_amount`, `transaction_date`, `status{code,message,tran_id}`.
`status.code` `00` = success, `5` invalid hash, `6` not found, `8` invalid
merchant, `11` server error, `429` rate limit. Rate limit 600 rps; PayWay asks
that you *"stop checking once a result is returned"*. Only transactions younger
than **7 days** are visible.

### Pushback — <https://developer.payway.com.kh/ecommerce-checkout-3158159f0>

The callback endpoint *"shall accept the HTTP POST method"* and
*"Content-Type: application/json"*. Body:

```json
{"tran_id": "...", "apv": "832865", "status": "0", "return_params": "...", "merchant_ref": ""}
```

Signature in the **`X_PAYWAY_HMAC_SHA512`** header (over the wire:
`X-PayWay-Hmac-Sha512`). Verify by sorting the body fields by key **ascending**,
concatenating the values, `hmac_sha512` with the api key, base64, and comparing
with `hash_equals()`.

### What the documentation does **not** settle

The QR API page documents `callback_url` but not the signature of the pushback it
sends; the Ecommerce Checkout page documents the signature. Rather than guess
which one the sandbox uses for a KHQR transaction, the adapter is built so the
answer does not matter — see §4.

---

## 2 — Why the QR API, and not Ecommerce Checkout

Both would work. The QR API is the smaller correct integration for a
Cambodia-first PWA, and the evidence is in its own response:

* **one call, both devices.** `qrString` + `qrImage` serve a desktop scan;
  `abapay_deeplink` serves a phone. Ecommerce Checkout returns an **HTML page**
  we would have to host, frame or redirect to, and then find our way back from.
* **no hosted page to style, translate or trust.** The payment surface stays
  inside Ayden, in Khmer, French and English, with our own states.
* **no redirect to misread.** Checkout's `continue_success_url` invites the
  browser to conclude something. The QR API has no such affordance, which suits a
  design where only the server may conclude.
* **`lifetime` is ours.** The QR expires on a deadline we set and store, so the
  expiry a person sees is the expiry the ledger believes.

The PWA renders the two orderings from one response, on the breakpoint the app
already owns (`pwaFormFactorForWidth`):

| | first | second |
|---|---|---|
| desktop | KHQR, large and central | (deeplink shown but secondary) |
| phone | **Open ABA Mobile** | KHQR, for a non-ABA bank app |

Asking someone to scan a code with the phone that is displaying it is the classic
mobile web-payment failure; the deeplink exists precisely to avoid it.

---

## 3 — What is sold, and who decides

**V1 sells the existing web-sellable credit packs.** No new SKU, no new price, no
new pack size. The catalogue already distinguishes them:

| sku | type | credits | duration | price | store id | web |
|---|---|---|---|---|---|---|
| `pack_10` | CREDIT_PACK | 10 | — | $1.99 | none | ✅ |
| `pack_25` | CREDIT_PACK | 25 | — | $3.99 | none | ✅ |
| `pack_50` | CREDIT_PACK | 50 | — | $6.99 | none | ✅ |
| `pack_100` | CREDIT_PACK | 100 | — | $11.99 | none | ✅ |
| `weekly_pass` | PASS | 30 | 7 d | $7.99 | Apple/RC | ❌ mobile only |
| `annual_pass` | PASS | 300 | 365 d | $79.99 | Apple/RC | ❌ mobile only |

Recurring ABA subscriptions are a **future phase**, once Merchant Acquisition
confirms them for Ayden Studio. Nothing in this work assumes them.

The browser sends **two fields**: `sku` and `attempt_key`. Price, currency,
credits and entitlement are read from `public.products` by the server. This is
not "validated input" — those fields *do not exist* on the request model, and
`extra='forbid'` turns an attempt to add them into a 422 rather than a silently
ignored key.

---

## 4 — The grant rule

> A pushback is a **doorbell**, never a receipt.

```
browser  --sku--------------->  Ayden      (server resolves price + credits)
Ayden    --signed generate-qr-> PayWay     (api key never leaves the server)
person   --scans / taps------>  ABA
PayWay   --pushback---------->  Ayden      OPTIONAL, and never believed
Ayden    --check-transaction-> PayWay      THE authority
Ayden    --grant_purchase----> Billing Engine -> ledger -> pass -> wallet
browser  --poll-------------->  Ayden      learns from the ledger, never from a redirect
```

Two consequences worth stating:

1. **The adapter is correct with no public callback.** The grant is driven by a
   call *we* make outbound, so a deployment PayWay cannot reach still completes a
   payment — it just learns about it when it asks instead of when it is told. A
   public callback makes it faster, not correct. (This is also why §8's missing
   HTTPS hostname is a production blocker rather than an E2E one.)
2. **Forging a callback buys nothing.** The handler reads no amount, no currency,
   no product and no user from the body — it does not even consult the body's
   `status` field. A signed pushback for an unknown `tran_id` is rejected; a
   signed pushback for a known one triggers a Check Transaction and nothing else.

Signature policy: `PAYWAY_CALLBACK_SIGNATURE_MODE=required` (default) rejects an
absent or wrong `X-PayWay-Hmac-Sha512` with 401. `optional` accepts an unsigned
pushback **as a trigger only** — it still grants nothing without Check
Transaction. That escape hatch exists because the QR API page does not document
the pushback signature; it must never be used in production.

---

## 5 — Identity, idempotency and the state machine

```
tran_id = 'A' + sha256(f"payway:{user}:{sku}:{attempt}")[:19]     ≤ 20 chars
        -> orders.idempotency_key = 'order:khqr:<tran_id>'
        -> payments (provider='khqr', provider_transaction_id=tran_id)
        -> ledger GRANT keyed 'grant:order:<order_id>'
```

Deterministic and user-scoped, so a double-click, an F5, a dropped response, a
backend restart and a second tab all recompute the **same** id and hit the same
row. A *new* purchase attempt is a new `attempt_key`, chosen by the person
tapping "try again" — never by a retry.

**The order is one row, not two.** The adapter creates the canonical order
`PENDING` under exactly the key `billing_grant_purchase` will use, so the grant
`ON CONFLICT` *updates* it to `PAID` instead of inserting a second one.

Rail states live in `pwa_staging.payway_transactions`; money states stay in
`public.orders`:

| rail state | meaning | order |
|---|---|---|
| `CREATED` | claimed, no QR yet | PENDING |
| `AWAITING_PAYMENT` | QR live | PENDING |
| `PAID_PENDING_VERIFICATION` | pushback seen, unverified | PENDING |
| `VERIFIED` | Check Transaction APPROVED | PENDING |
| `GRANTED` | ledger GRANT written | **PAID** |
| `FAILED` | declined / amount mismatch / gateway refused | FAILED |
| `EXPIRED` | QR lifetime over, unpaid | CANCELLED |
| `CANCELLED` | the person closed the sheet | CANCELLED |

Three refusals worth naming, all measured in the tests:

* **amount / currency mismatch** → `FAILED`, no grant, reason recorded. PayWay
  says money moved, but not the money we asked for.
* **transient grant failure** → stays `VERIFIED`, not `FAILED`. Marking a
  verified payment failed is the one reliable way to actually lose a paid credit.
* **cancel** → verifies first. Money that landed a second ago wins over the tap.

---

## 6 — The one canonical change, and why it was unavoidable

`billing_grant_purchase` **could not grant a credit pack at all** before this
work. A pack has `duration_days IS NULL`, so:

```
v_ends_at := coalesce(p_ends_at, now() + make_interval(days => NULL)) = NULL
insert into public.passes (... ends_at ...) values (... NULL ...)
ERROR:  null value in column "ends_at" violates not-null constraint
```

The engine was written for RevenueCat, where every product is a dated
subscription. The Cambodian Web launch sells exactly the products it cannot
grant. Three shapes were considered:

* **(a) give the pack a dated window from the adapter** (no SQL change) —
  *rejected*. The projection picks ONE active pass, `order by ends_at desc`. Buy
  `pack_10` today and `pack_25` tomorrow and the first pack's unspent credits
  stop being counted. Paid credits silently lost.
* **(b) grant into the unscoped bucket** (`pass_id IS NULL`), which accumulates —
  *rejected*. That is the FREE/TRIAL bucket. `has_active_pass` would stay false
  and the watermark rule reads exactly that signal, so a paying customer would
  get watermarked images.
* **(c) a PERPETUAL pass** — **adopted**. A product with no duration and no
  explicit window grants into a pass whose `ends_at` is a sentinel
  (`2999-12-31`, finite so every client's date parser survives it), and a second
  pack's GRANT joins the pass the first created.

Result: packs accumulate, `has_active_pass` is true (no watermark),
`access_source = 'pass'`, and `billing_try_hold` debits the bucket the projection
displays — all with no change to the consumption path. The branch is guarded on
`p_duration_days IS NULL AND p_ends_at IS NULL`, which **no RevenueCat product
can reach** (weekly = 7, annual = 365); `PWDB07` proves it against the database.

Also additive, in `billing._resolve_product`: match on `sku` as well as
`revenuecat_product_id` / `apple_product_id`. A web product has neither store id
by construction — that absence is what makes it web-sellable — so its canonical
identifier is its sku. Without it, a KHQR payment could be taken and never
credited.

### Known interaction, recorded not hidden

A user holding **both** a perpetual pack and a dated RevenueCat pass has only the
perpetual one counted, because the sentinel sorts above every real date. That
cannot happen on the Cambodian Web launch (no RevenueCat on the Web, no KHQR on
mobile). Solving it means teaching the projection to sum several buckets — a
change to the consumption path, and its own reviewed phase. Listed in §9.

---

## 7 — What was found on the way

Three defects that were already there, surfaced by running rather than reading:

1. **`prove_target` had decayed.** Its "this is not production" marker was the
   absence of `usage_log` / `messages` / `account_state` / `device_tokens`. Three
   of the four are now present — the staging project is **shared** with the
   unified-identity chantier, which installed them. The guard was refusing every
   migration. The refusal now rests on the two facts that cannot decay (the
   connection string carries the staging ref; `pwa_staging` exists in no other
   project) plus `device_tokens` as one cheap negative marker; the rest is
   reported as drift. `usage_log` is harmless here — `resolve_generation_access`
   only reads it for a legacy display figure and it gates nothing.
2. **`service_role` had no `USAGE` on `pwa_staging`.** Table grants existed;
   schema usage did not, because every previous caller in that schema was the
   *browser*, holding a user token. The payment rail is the first thing the
   **server** owns there, so it was the first thing to hit the gap — as a 500,
   not an empty result. Granted in `0007`.
3. **A blanket RLS assertion had become false.** `DB07 no non-SELECT policy
   anywhere in public` now fails, because the shared project carries `sessions`,
   `messages` and `assets` — the mobile *chat* tables — each with an
   "active identity only" ALL policy. Measured: **no billing table** has one. The
   assertion now names the tables it was always about, which is narrower in scope
   and true again.

And one designed-then-measured fix: five concurrent submits all read
`state = 'CREATED'` — the state the first one is still working in — and all five
called `generate-qr`, collecting four PayWay 403s for one double-click. The claim
now distinguishes *abandoned* from *unfinished* with a 45-second staleness
window, longer than the adapter's 20-second gateway timeout.

---

## 8 — The external blocker

Everything that does not need ABA is built, tested and green. Two things are
outside this repository, and they are different in kind:

### Blocks the sandbox E2E — needed now

1. **Sandbox credentials in the ignored file.** `backend/.env.pwa-staging.local`
   already carries the two empty lines; fill them from the credentials ABA
   emailed. The file is gitignored (`.gitignore:8`), verified by
   `pwa_secret_scan.py`.

   > A file named `aba.png` is sitting in `~/Downloads`. It was **not opened** —
   > if it holds the credentials, copy them into the env file directly. They must
   > not pass through a chat transcript.

2. **Whitelisting.** PayWay only answers a request *"from a domain or IP address
   that has been whitelisted"*. The sandbox merchant profile needs this machine's
   public egress IP, or ABA's onboarding contact needs to add it. Symptom if
   missing: `generate-qr` returns `status.code = 6`, and
   `pwa_staging_payway_e2e.py` says so explicitly.

Then, one command, no code change:

```
cd backend
python run_pwa_staging.py                   # restart: it reads the env at boot
PYTHONPATH=. python pwa_staging_payway_e2e.py
```

It opens a real sandbox transaction, prints the KHQR string and the ABA Mobile
deeplink, waits up to 180 s for the sandbox payment, then verifies, grants and
checks the entitlement — reporting `BLOCKED`, never `PASS`, if the QR goes
unpaid.

### Does **not** block the sandbox E2E — needed before production

3. **A stable public HTTPS callback host.** Audited read-only: there is none. The
   PWA staging backend runs on `127.0.0.1:8000`, and `kStagingBackendOriginAllowlist`
   contains only loopback origins; the sole stable HTTPS host in the codebase is
   `api.aydenstudio.com`, which is **production** and is on the PWA's denylist.

   The adapter treats this correctly rather than pretending: with
   `PAYWAY_CALLBACK_URL` empty it runs **poll-only** and never sends a
   `callback_url`, and it *refuses* a loopback callback URL at configuration
   time — a callback that silently never arrives is worse than none.

   A disposable tunnel was deliberately not used: PayWay whitelists a hostname,
   and a hostname that changes every restart makes the whitelist meaningless.
   What is needed is a stable staging subdomain (e.g.
   `https://staging-api.aydenstudio.com/pwa/staging/payments/payway/callback`)
   pointed at a staging deployment with its own Billing Engine and no production
   data.

---

## 9 — Before production (record, do not execute)

- [ ] `20260707_grants_hardening` applied to production
- [ ] production PWA schema / migration plan, including the perpetual-pass
      redefinition of `billing_grant_purchase` and the `sku` match in
      `_resolve_product`
- [ ] production PayWay credentials (separate merchant, separate key)
- [ ] production domain / IP whitelist with ABA
- [ ] stable production HTTPS callback + `PAYWAY_CALLBACK_SIGNATURE_MODE=required`
- [ ] `PAYWAY_ENV=production` — currently **refused by `payway.load_config`**, by
      design; lifting that refusal is a reviewed change, not a config edit
- [ ] production Auth delivery choice (SMTP rate limiting is a separate,
      unrelated staging issue)
- [ ] cross-rail pass interaction (§6) if mobile and web purchases can ever meet
- [ ] a sweep for `AWAITING_PAYMENT` rows past `expires_at` (today they expire on
      the next poll; an abandoned tab leaves a PENDING order until someone looks)
- [ ] final security review
- [ ] final live smoke with one controlled real payment

---

## 10 — Where everything is

| | |
|---|---|
| rail (protocol only) | `backend/payway.py` |
| seam (product, state, grant) | `backend/pwa_staging_payments.py` |
| schema + perpetual grant | `ayden-pwa-web/supabase/staging/pwa/0007_payway_sandbox.sql` |
| client model + controller | `ayden-pwa-web/lib/features/pwa/billing/pwa_payment*.dart` |
| payment surface | `ayden-pwa-web/lib/features/pwa/presentation/pwa_payment_sheet.dart` |
| rail contract tests | `backend/payway_adapter_test.py` (59) |
| seam tests | `backend/pwa_staging_payments_test.py` (95) |
| DB contract | `backend/pwa_staging_payway_db_test.py` (39) |
| live probe | `backend/pwa_staging_payway_e2e.py` (16 pass / 8 blocked) |
| Flutter | `ayden-pwa-web/test/features/pwa/pwa_payment_test.dart` (19) |
| secret scan | `backend/pwa_secret_scan.py` |
