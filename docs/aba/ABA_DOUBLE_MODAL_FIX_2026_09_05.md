# One checkout surface — the plugin's

Preprod / sandbox only. No production, no real payment, no native iOS, no
Billing change, no PayWay integration change.

**Preprod:** https://preprod.aydenstudio.com

## 1. Why Ayden's sheet opened before PayWay — the exact reason

`showPwaPaymentSheetFor` (in `pwa_payment_sheet.dart`) did two things in
sequence: `ref.read(pwaPaymentProvider.notifier).start(product.sku)` and then
`showDialog(...)`. On the plugin path `start()` hands the signed fields to
ABA's plugin, which opens its popup; the `showDialog` that followed put
Ayden's card ("secure checkout is open… waiting… 29:49… cancel") underneath
it. Two surfaces, by construction, every time.

## 2. The change

On the plugin path the Wallet's Buy now calls **`start(sku)` and nothing else**.
`showPwaPaymentSheet` is not reached; `PwaPaymentSheet` is not mounted. The
Wallet stays where it is and is what sits behind ABA's popup.

Payment *state* continues exactly as before — order, tran_id, poll, Check
Transaction, grant, idempotency — and surfaces on the Wallet as **one quiet
line under Buy** (`_PaymentInline`):

| State | Under the CTA | Buy |
| --- | --- | --- |
| PREPARING (`starting`/`created`) | spinner · "Preparing your payment…" | disabled |
| PAYWAY_OPEN / VALID_PENDING (`awaitingPayment`) | spinner · "Checking your payment with ABA PayWay…" · *Cancel this payment* | disabled |
| `paidPendingVerification` / `verified` | spinner · "Confirming…" | disabled |
| APPROVED (`granted`) | — the Wallet **pops itself**; the existing success card is shown by the payment-return watcher | — |
| FAILED · **NOT_CREATED** | "ABA PayWay could not start the payment. Please try again." | **enabled** (new attempt) |
| FAILED (other) / EXPIRED / UNREACHABLE | the existing short reason | enabled |
| CANCELLED | nothing — back to the Wallet | enabled |

No countdown. No "waiting for your payment". No modal. The popup says what is
open; Check Transaction says what happened.

The server-side path (no plugin) is untouched and still opens the sheet — that
is how every existing widget test drives it.

## 3. NOT_CREATED — the state the phone found missing

Error 6 ("Requested Domain is not in whitelist") is answered by PayWay
*before* any transaction exists, and Check Transaction then says
`tran_id not found`. Until now the row sat in AWAITING for the full lifetime.

`verify_and_settle` now handles a **not-found** answer explicitly, on the
plugin path only:

* inside a **30 s grace window** from the moment the fields were issued, it is
  treated as a race (the browser may still be submitting the form) — recorded,
  and the row stays AWAITING;
* beyond it, the row becomes **FAILED / `NOT_CREATED`** — terminal, zero grant,
  poll stops. A new Buy is a new attempt.

Why 30 s: the plugin submits the form ~1–2 s after the fields are issued and
PayWay creates the transaction on that POST, before any scanning; Error 6 was
measured arriving in the same second. The server-side Purchase path is left
alone — there this process saw PayWay accept the purchase, so a later
not-found is an anomaly to log, not a state to conclude.

## 4. Live proof — iPhone UA, `preprod.aydenstudio.com`

**B — after Buy** (`shots/dm/B-plugin-open.png`): ABA's bottom sheet, and
behind it **the Wallet** — hero, "Continuer à créer", the packs dimmed. No
Ayden payment sheet. DOM at that moment: `#aba_checkout_sheet display:flex`,
exactly one iframe (`aba_webservice`, inside `#aba_checkout_app`, `allow="payment *"`),
form `target=aba_webservice`, `payment_option=abapay_khqr`,
`is_plugin_js=true`.

**D — after tapping OK on Error 6** (`shots/dm/D-after-close.png`): the Wallet.
The log records **one** top-level navigation for the whole session — the
plugin's mobile close is a drawer dismissal, not a `location.reload()`.

**D2 — ~40 s later** (`shots/dm/D2-not-created.png`): the Wallet, with
"ABA PayWay n'a pas pu démarrer le paiement. Veuillez réessayer." under an
**enabled** Buy. Nothing waiting, nothing counting down.

**D0 — a bonus** (`shots/dm/D0-restored-orphan-not-created.png`): at boot,
`restore()` picked up the orphaned plugin order from the previous session; the
deployed backend settled it as NOT_CREATED within seconds and the Wallet showed
the same one-line outcome.

**Network** (`evidence/netlog-iphoneUA-double-modal.jsonl`, secrets never
logged):

```
POST  200  ayden-api-staging.fly.dev/pwa/staging/payments/checkout/plugin      top
POST  200  checkout-sandbox.payway.com.kh/api/payment-gateway/v1/payments/purchase   iframe
GET   200  checkout-sandbox.payway.com.kh/checkout/…  (PayWay's Error-6 page)       iframe
GET   200  …/payments/order/Aabcee55b16ba0fbcd11   ×8, then none                      top
top-level navigations: 1 · exceptions: 0 · production hosts: 0
```

Eight polls at 3 s ≈ the grace window; then the terminal answer and silence.

## 5. State machine

```
BEFORE (plugin path)                        AFTER (plugin path)
Buy → start() → PwaPaymentSheet opens       Buy → start() → nothing opens
     → plugin popup opens on top                → plugin popup opens over the WALLET
Error 6 → close → sheet still there,        Error 6 → close → Wallet
  "waiting… 29:49" for 30 min                 → ≤30 s → FAILED/NOT_CREATED → one line, Buy live
APPROVED → sheet shows success              APPROVED → Wallet pops; success card via watcher
```

## 6. Files changed

| File | |
| --- | --- |
| `lib/features/pwa/presentation/pwa_paywall.dart` | Buy calls `start()` only on the plugin path; `ref.listen` pops the Wallet on `granted`; `_PaymentInline` |
| `lib/features/pwa/presentation/pwa_experience.dart` | the success watcher re-arms per attempt (was once per session) |
| `lib/features/pwa/l10n/pwa_translations.dart`, `pwa_l10n.dart` | `pwaPayInlineChecking`, `pwaPayInlineCancel`, `pwaPayFailedNotCreated` (EN/KM/FR); `payFailedBody('NOT_CREATED')` |
| `backend/pwa_staging_payments.py` | `_NOT_CREATED_GRACE`; the not-found branch in `verify_and_settle` |
| `backend/pwa_staging_payments_test.py` | ERR01–ERR07 |
| `test/features/pwa/pwa_payment_test.dart` | DM01–DM06, ERR02/03/05/06, PAY02/PAY03 |

Unchanged: the plugin bridge, `index.html`, the signed-form endpoint,
`pwa_qr.py` (dormant), `PwaPaymentSheet` itself (still the success card and
the server-side path's sheet), prices, Billing, grant, TTL (30 min).

## 7. Tests

* **DM01/02/03** — Buy launches the plugin once and `PwaPaymentSheet`/`Dialog` are absent; the packs and CTA are still there; the only addition is the inline line.
* **DM04** — the inline line, not a card: `payPluginOpen` and `payWaiting` absent.
* **DM05/06** — no `HTMLIFrameElement`/`HtmlElementView`/`createElement('iframe')` in the Wallet, sheet, controller or bridge; the form targets `aba_webservice`.
* **ERR02/03/05/06** (client) — after a FAILED/NOT_CREATED poll: no waiting text, no `mm:ss`, inline line gone, error line present, `PwaPaymentSheet` absent, **no further poll for 10 s**, Buy enabled, plugin launched once.
* **ERR01–07** (server) — within grace stays AWAITING; past grace FAILED/NOT_CREATED, public view terminal with reason, zero grants, no re-check, canonical order not PENDING; **not applied** to the server-side path.
* **PAY02** — cancel → no line, no error, no sheet. **PAY03** — GRANTED pops the Wallet (hosted in a real modal route), plugin launched once.
* Authority unchanged, still pinned by PLUGIN13 (APPROVED grants exactly once) and ABA14 (declined grants zero).

## 8. Gates

| | |
| --- | --- |
| `flutter analyze` | 0 issues |
| `flutter test` | **1456** pass |
| `pwa_staging_payments_test.py` | **234** assertions |
| `payway_adapter_test.py` | **99** assertions |
| `pwa_secret_scan.py` | 11 PASS, 0 LEAKS |
| build staging · deploy preprod · deploy Fly staging | exit 0 |

## 9. Scope

`frontend/lib` 0 · `frontend/ios` 0 · native iOS NO · RevenueCat NO · Billing
NO · custom QR NO (dormant, untouched) · plugin NO · production Supabase /
PayWay / Firebase NO · real money NO.

## STOP

Waiting for real-phone review and for ABA to whitelist
`preprod.aydenstudio.com`. Until then every Buy ends in Error 6 → NOT_CREATED
→ the Wallet, by design.
