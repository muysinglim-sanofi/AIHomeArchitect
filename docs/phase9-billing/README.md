# Phase 9 — the web paywall, billing UX and account states

Preview: <https://ayden-studio--phase9-billing-3ark2zjh.web.app> (expires 2026-09-04)
Live staging and the Phase 1–8 previews are all **untouched**.

| file | what it shows |
|---|---|
| `00-free-vision-fr.png` | the free vision, spent on a real kitchen, on this build |
| `07-refusal-fr.png` | **the moment**: a real authoritative refusal → the paywall, and nothing else |
| `08-selected-bestvalue-fr.png` | the choice moves, and so does the CTA |
| `09-selected-starter-fr.png` | Starter selected |
| `10-no-loop-fr.png` | a cold reload afterwards — Home, no paywall, no banner |
| `11-profile-wallet-fr.png` | Profile saying the same thing as the paywall |
| `13-paywall-km.png` | Khmer |
| `14-paywall-desktop-km.png` | 1440 — a centred sheet, not a pricing page |
| `15-tablet-km.png` | 768 |
| `18-paywall-en.png` | English — the canonical ladder, in full |
| `19-payment-en.png` | the ABA hand-off, with its label finally visible |

All eleven are the deployed staging build against the public staging backend
and its canonical catalogue. The free vision in `00` was really spent and the
refusal in `07` was really issued by the Billing Engine. **No ABA payment was
fabricated**: `19` is a real sandbox order at "waiting for your payment", and
it was cancelled immediately afterwards.

---

## 1. Store-only products, removed by the SERVER's own rule

The catalogue endpoint already computes the eligibility — `store_only =` a row
carries an Apple/RevenueCat id, `web_enabled = khqr_enabled AND NOT store_only`
(`backend/pwa_staging_billing.py:435,464-465`) — and `PwaProduct` already
parsed both. Nothing named a sku, and nothing needed to.

What was wrong was the getter the paywall read. `productsForDisplay` **grouped**
rather than filtered: web packs first, App Store passes after, each with the
line "available in the mobile app". Honest, and still an advertisement for a
shop the reader is not standing in. Meanwhile `purchasableOnWeb`, which does
filter, was dead code with one test as its only caller.

* the paywall now renders `e.purchasableOnWeb`;
* `productsForDisplay` is deleted;
* the same rule is enforced twice more, independently: the CTA can only carry a
  pack from that list, and `resolve_web_product` refuses a store-only sku with
  409 `PRODUCT_NOT_WEB_SELLABLE` before any amount is resolved.

## 2. The amount is never the client's

The sheet displays `price_usd` and sends a **sku**.
`PwaPaymentController.start(String sku)` → `startCheckout(sku, attemptKey)` →
`POST /pwa/staging/payments/checkout`. There is no amount parameter anywhere on
that path; the server reads `products.price_usd` for the sku it is given.

`$79.99` and `40% OFF` are display only: `list_price_usd` lives in
`products.metadata`, the percentage is `round((1 − 47.99/79.99) × 100)`
computed for the label, and the struck price is rendered above the payable one
with a line through it so the number a person acts on is the one they will be
charged. A test asserts the strike-through decoration itself.

## 3. Product cards, and the black rectangles

The old row was read-only, with a Buy button per row — and every one of those
buttons rendered as an **empty black rectangle**. The cause: `FilledButton`
asks for a white foreground, but Flutter delivers that as a DefaultTextStyle,
and the child was `Text(l.payBuy, style: pwaSans(...))` whose default colour is
`pwaInk`. An explicit style on the child beats the button's foreground, so the
label was ink on ink. The icon looked right because an `Icon` DOES read the
foreground; only the text did not. The same bug had the ABA hand-off button
reading as a black slab with an arrow and no words.

Now: one card per pack, the whole card is the tap target, the selected one
carries a gold border, a gold tint and a **tick** (shape as well as colour), and
there is a single CTA that names the price of the selected pack. Both labels
state their colour explicitly, and a test walks every `Text` on the sheet
refusing an ink-coloured empty label.

## 4. One outcome, one surface

`_failGeneration` was the single failure funnel and wrote the generic error
fields **unconditionally**, then set `billingRefusal` on top. So a 402 produced
the correct paywall AND "Something went wrong. Try again." about a request that
had gone exactly as the ledger intended.

It now writes exactly one: a billing refusal writes only `billingRefusal`;
anything else writes only the error fields. (`copyWith` treats a null as
"unchanged", so this is done by clearing the whole outcome group first and
writing one surface back — passing nulls would have changed nothing.)

One neighbouring rule had to be made explicit rather than left to drift: the
watcher that re-reads entitlement after a generation tested `generationError !=
null` to mean "did not produce". With refusals no longer writing that field it
now tests both, and says why.

## 5. The pending generation, and the loop

**Root cause.** `localStorage['flutter.pwa_pending_generation_v1']` is written
before every generation and cleared after a successful one. On failure it was
stamped `failed` and KEPT — Retry needs the same idempotency key. A billing
refusal took that path like any other failure, so the record survived, boot
folded it back in, and the paywall and the banner returned on **every single
cold start**, for ever. Observed on the Phase 7 preview; reproduced at will.

**The exact authoritative condition.** The Billing Engine's refusal is a 402
carrying `error_code: QUOTA_EXHAUSTED`, `billing_state`, `paywall: "pass"`,
`retryable: false` and `render_started: false`
(`backend/pwa_staging_billing.py:143-177`). The client already parsed a
`paywall` flag (402 **and** the payload's own `paywall` key) but dropped it at
the service seam. It is threaded through now, and:

```dart
bool get isAuthoritativeBillingRefusal => paywall && isBillingRefusal && !retryable;
```

Only that clears the record. Everything else keeps it: a timeout, a 5xx, an
unparseable body, a cancelled request, `SESSION_EXPIRED` (not retryable, but
not a refusal either), and even a refusal the server marks retryable. The
asymmetry is deliberate — too eager and someone loses a retry for work they may
have paid for; too shy and the loop comes back — and all six directions are
pinned in `BILL05`.

`10-no-loop-fr.png` is that fix on staging: after a real refusal, a cold reload
lands on Home with the person's work, `pending: ABSENT`, no paywall, no banner.

## 6. Return from ABA PayWay

`WebPwaExternalLauncher` assigns `location.href` — deliberately, because a
custom scheme in a new tab leaves an empty tab behind on mobile. So paying
**replaces the page**: the tab that started the purchase is gone, its poll is
gone with it, and coming back is a cold boot. `PwaPaymentController.restore()`
was written for exactly this, documented as "called when the payment surface
opens", and had **no caller in production** — only two tests.

A `_PwaPaymentReturnWatcher` now asks once per boot. `GET /payments/open`
verifies the open attempt with PayWay before answering, so a payment made while
the browser was away is settled by the question itself; if it comes back
`verified` or `granted` the existing payment sheet is shown in that state and
the entitlement is re-read. An attempt still sitting at `awaitingPayment` opens
**nothing** — someone who chose not to pay must not be met by a payment sheet
on every visit, which is the same mistake the replayed pending record made.

The success state already existed and already avoided redisplaying the packs.
It gained the one thing §10 asks for that it lacked: the balance the account is
left holding, read from the entitlement and rendered only once the server has
answered — never the grant plus a remembered figure.

## 7. Wallet coherence

The paywall's balance badge showed `passCredits`; Profile showed
`creditsAvailable`. One account, one object, two numbers whenever a free credit
survived alongside a pass. Both now read `creditsAvailable`, the server's
`credits_available`. `11-profile-wallet-fr.png` and `07-refusal-fr.png` are the
same state described twice, in each surface's own words.

A free vision is still never called a Space — `pwaWalletSentence` switches on
the billing state, and a Space is a thing you buy.

---

## What was NOT touched

Backend, Billing Engine, ledger, wallet projection, `grant_purchase`, the ABA
Purchase API, PayWay verification, callbacks, idempotency, entitlement
semantics, free-tier semantics, RevenueCat, native iOS, the creative engine,
the generation contract, refine, project semantics. Prices and the catalogue
are unchanged — every number on screen is read from the server.

**A correction to the brief's wording, for the record:** there is no
`/payments/purchase` endpoint in this repo. The active rail is
`POST /pwa/staging/payments/checkout` → `GET …/order/{tranId}` (polling) →
`GET …/payments/open` (restore) → `POST …/order/{tranId}/cancel`. It is
unchanged by this phase. `generate-qr` is not reachable from the client and
cannot become so: an existing test scans all of `lib/` for `generate-qr`,
`check-transaction`, `payway_api_key`, `merchant_id`, `hmac` and `sha512`, and
fails if any appears.

`frontend/lib` and `frontend/ios` are untouched, so ABA remains unreachable
from native iOS by construction.

---

## Gate

* `flutter test` — **1275 passed, 0 failed** (+32 in `pwa_billing_ux_test.dart`;
  two existing tests migrated where the SHAPE of the answer changed, not the
  rule).
* `flutter analyze` — 2 issues, both pre-existing `info` lints in
  `pwa_i18n_test.dart`, a file this phase does not touch.
* `tool/build_pwa.sh staging` — clean.
* `backend/pwa_secret_scan.py` — **PASS 10, LEAKS 0**.
* Cache-control on the deployed channel: `main.dart.js` → `no-cache,
  must-revalidate` (the RELEASE-CRITICAL rule from Phase 3, still held).
* Deployed to the **phase9-billing** channel only.

### Two tests were migrated, and why

`PAYWAY16` asserted "a Buy button on exactly one row, and the store-only row
explains itself". Both halves changed shape: there is one CTA rather than a
button per row, and it is **disabled** rather than absent when no rail is open
(a person who cannot pay should see the offer and be told why); and the
store-only row is gone from the purchase surface rather than listed with an
excuse. The rule it protected — the SERVER decides whether a purchase can
complete — is asserted exactly as before.

`PAY08` asserted the display grouping of `productsForDisplay`. That getter no
longer exists; the assertion is now that `purchasableOnWeb` is the surface and
that the store-only row is still PARSED, because the client must be able to
know it exists.
