# ABA PayWay official JS plugin — preprod integration

Preprod / sandbox only. No production, no real payment, no native iOS.

**Status: implemented, deployed to preprod, and BLOCKED by ABA at the last
step — PayWay refuses the purchase with `Error Code 6: Requested Domain is not
in whitelist`.** Everything on Ayden's side is proven live; the one remaining
action is ABA's.

---

## 0. What ABA's plugin actually does — read, not assumed

`https://checkout.payway.com.kh/plugins/checkout2-0.js` (1 008 bytes) is a
loader. It pulls `bs.js` (the mobile bottom sheet), `bridge.js` (a WebView
bridge for the ABA app's mini-app mode) and, after 1 s, `checkout.prod.js`
(32 KB, the plugin proper). Facts that shaped the implementation, each from
that source:

| Fact | Where | Consequence |
| --- | --- | --- |
| `AbaPayway.checkout()` submits `#aba_merchant_request` into an `<iframe name="aba_webservice">` it creates | `initPlugin`, ~L1133 / L1270 | `target="aba_webservice"` on the form is the iframe's **name** — that is its exact role |
| Desktop → `#aba-checkout.aba-checkout-desktop`, iframe 264 px growing to 595; mobile (UA regex) → `bs.js` sheet, iframe 416 px | `_abaCheckoutIsMobile()` L478, `initPlugin` | Mobile/desktop is decided by **user agent**, not viewport |
| It appends `is_plugin_js=true` to the form itself | `checkout()` L777 | Proof the plugin ran, visible in the DOM |
| Recognises `payment_option === 'abapay_khqr'` | L793 | Sizes the sheet 500 px for KHQR — the value ABA named for websites |
| Close ✕ → `confirm()` → `cancel_url` ? `location.href` : `hide-close==='2'` ? hide : **`location.reload()`** | `closeCheckout` L1317 | Load the loader with `?hide-close=2` and send **no** `cancel_url`, or every close reloads the app |
| Success → `merchantUrl` message → `''` ? close in place : `location.href` | `window.onmessage` L1600 | Send **no** `continue_success_url` → popup closes in place, Wallet and poll survive |
| `const AbaPayway = new AbaPay()` at top level | L1474 | **Not a `window` property.** Only the bare identifier resolves. Measured live: `typeof AbaPayway → "object"`, window property → `undefined` |
| `view_type` is not in the official form and not among the 24 hashed fields | ABA sample; `PURCHASE_HASH_FIELDS` | Omitted on the plugin path |

ABA's own sample (developer.payway.com.kh, verbatim): a `<form method="POST"
target="aba_webservice" id="aba_merchant_request" action=".../purchase">` of
hidden inputs — `hash, tran_id, amount, merchant_id, req_time, payment_option,
currency, …` — and a submit handler calling `AbaPayway.checkout()`.

## 1. Architecture

```
Wallet · Buy
  → POST ayden-api-staging /pwa/staging/payments/checkout/plugin   {sku, attempt_key}
  ← { ...public_view, plugin: { form_action, fields{ req_time, merchant_id, tran_id,
                                  amount, type, currency, lifetime, payment_gate,
                                  payment_option, return_url, return_params, hash } } }
  → Dart relays the OPAQUE map to window.aydenAbaCheckout(action, fieldsJson)
  → bridge builds #aba_merchant_request (DOM API, .value) → AbaPayway.checkout()
  → PLUGIN creates <iframe name=aba_webservice>, appends is_plugin_js, submits
  → PayWay renders inside its own iframe/sheet
  → poll GET /payments/order/{tran_id} every 3 s → server → Check Transaction
  → APPROVED → canonical Billing grant → entitlement refresh
```

The server SIGNS and never posts; the browser POSTS and never signs. The api
key is read only in `payway.load_config` on the server. The browser receives
`merchant_id` (an identifier) and `hash` (a signature *output* over these
specific fields) — exactly what ABA's sample places in hidden inputs.

## 2. Files changed

**Backend (staging)**

| File | |
| --- | --- |
| `backend/pwa_staging_payments.py` | `plugin_form_fields`, `start_plugin_checkout`, route `POST /checkout/plugin`; constants `PLUGIN_PAYMENT_OPTION`, `CHECKOUT_MODE_PLUGIN` |
| `backend/fly.toml` | `PAYWAY_PAYMENT_OPTION = "abapay_khqr"` (from `abapay_khqr_deeplink`) |
| `backend/pwa_secret_scan.py` | `BUNDLE_ALLOWED_VERBATIM` — the one plugin URL, struck out before the needles; everything else on that host still fails the scan |
| `backend/pwa_staging_payments_test.py` | PLUGIN01–13 |

**PWA**

| File | |
| --- | --- |
| `web/index.html` | the plugin include with `?hide-close=2`; the `aydenAbaCheckout` bridge |
| `lib/features/pwa/data/pwa_aba_plugin.dart` (+ `_web`, `_stub`) | **new** — interface, js_interop call, no-op |
| `lib/features/pwa/data/pwa_generation_api.dart` | `startPluginCheckout` |
| `lib/features/pwa/billing/pwa_payment_controller.dart` | takes the plugin path when a plugin is present; relays the handoff; `lastPluginLaunch` |
| `lib/features/pwa/billing/pwa_payment.dart` | `kPwaCheckoutModePlugin`; `isPayable` / `needsFreshCheckout` mode-aware (**a real bug**: an empty `checkout_url` read as "link expired") |
| `lib/features/pwa/presentation/pwa_payment_sheet.dart` | plugin mode renders a status card — no QR, no deeplink, no instructions |
| `lib/features/pwa/l10n/pwa_translations.dart`, `pwa_l10n.dart` | `pwaPayPluginOpen`, EN/KM/FR |
| `lib/main_pwa.dart` | wires `startPluginCheckout` and `createPwaAbaPlugin()` |
| `test/features/pwa/pwa_payment_test.dart` | PLG01–06 |

**Untouched, dormant (per §2):** `backend/pwa_qr.py`, `_QrPanel`,
`_OpenAbaMobileButton`, `POST /checkout`. None is reachable from Buy when the
plugin is wired — PLG01 asserts the legacy endpoint is not called, PLG04 that
none of the custom pieces render.

## 3. Live proof — preprod, `https://preprod.aydenstudio.com`

### DOM after Buy (desktop UA)

```
form#aba_merchant_request  method=post  target=aba_webservice
  action=checkout-sandbox.payway.com.kh/api/payment-gateway/v1/payments/purchase
  fields: req_time merchant_id tran_id amount type currency lifetime payment_gate
          payment_option return_url return_params hash  + is_plugin_js=true (plugin's)
  payment_option=abapay_khqr
#aba-checkout  class=aba-checkout-desktop  z-index=99999  children=1
iframe#aba_webservice  name=aba_webservice  allow="payment *"  391×395  (plugin's)
body.overflowY=hidden
```

### DOM after Buy (iPhone UA)

```
#aba_checkout_sheet  display=flex          ← bs.js bottom sheet
iframe#aba_webservice  inside #aba_checkout_app  390×402
form.target=aba_webservice  payment_option=abapay_khqr
```

Both plugin branches exercised. **Zero iframes created by Ayden code.**

### Network (CDP `Network.*`, secrets never logged)

| Request | Status | Frame |
| --- | --- | --- |
| `GET checkout.payway.com.kh/plugins/checkout2-0.js` `bs.js` `bridge.js` `checkout.prod.js` | 200 ×4 | top |
| `POST ayden-api-staging.fly.dev/pwa/staging/payments/checkout/plugin` | 200 | top |
| **`POST checkout-sandbox.payway.com.kh/api/payment-gateway/v1/payments/purchase`** | 200 | **iframe** |
| `GET checkout-sandbox.payway.com.kh/checkout/eyJzdGF0dXMi…` (PayWay's result page) | 200 | iframe |
| `GET ayden-api-staging.fly.dev/pwa/staging/payments/order/{tran_id}` | 200 | top (poll) |
| production hosts (`api.aydenstudio.com`, prod Supabase, Render, `checkout.payway.com.kh/api`) | **0 requests** | — |
| page exceptions | **0** | — |

Hosts seen: preprod.aydenstudio.com, ayden-api-staging.fly.dev,
checkout.payway.com.kh (plugin only), checkout-sandbox.payway.com.kh,
eedcahzekpgxvvfxufbk.supabase.co (staging), fonts.gstatic.com,
google-analytics.com (the plugin's own), accounts.google.com (sign-in).

### What PayWay rendered

**"Unable to process — Requested Domain is not in whitelist. [Error Code: 6]
[Order ID: Afba23325f94251d686b]"** — identically in the desktop modal and the
mobile sheet. Check Transaction for that id: `envelope=6 'tran_id not found'`
— PayWay rejected the purchase before creating a transaction.

Screenshots: `shots/plugin/D-plugin-popup-desktopUA.png`,
`shots/plugin/D-plugin-sheet-mobile.png`, `shots/plugin/C-wallet-mobile-before.png`.

## 4. The blocker, precisely

Until today the Purchase call left **Fly** (no browser origin). Now it leaves
the browser at **`preprod.aydenstudio.com`**, and PayWay checks that domain
against the sandbox merchant's whitelist. It is not there.

**Action for ABA:** whitelist the initiating domain(s) on the sandbox
merchant — `preprod.aydenstudio.com` at minimum, `ayden-studio-preprod.web.app`
if the technical URL is to work too. The pushback `return_url`
(`ayden-api-staging.fly.dev`) is a different main domain as well; ABA's own
note says it must be whitelisted. **No return URL** (`continue_success_url`,
`cancel_url`) is sent on this path, so no browser-return whitelist arises.

Nothing on our side can or should work around this.

## 5. What happens to a blocked order

The row stays `AWAITING_PAYMENT`, the poll runs every 3 s, Check Transaction
answers "not found", and at the transaction lifetime the seam marks it
`EXPIRED` — zero grant, retry available. Existing behaviour; consistent with
ABA's "end within the lifetime" guidance.

## 6. Polling and lifetime — audit (§17–18)

| | Current | ABA guidance |
| --- | --- | --- |
| First Check Transaction | ~3 s after start (`poll_interval_ms: 3000`, scheduled on the start answer) | ~3 s ✅ |
| Interval | 3 s (server-set, client clamps 1–15 s) | 3–5 s ✅ |
| Stop | first terminal state, or sheet closed | APPROVED / lifetime ✅ |
| **Transaction lifetime** | **30 min** — `PAYWAY_QR_LIFETIME_MINUTES`, default 30, floor 3 (`payway.py:320-325`) | **5–15 min** ⚠️ |
| Max polling | until `expires_at` = lifetime | — |

Not changed (§18): the lifetime is a configuration value and 30 → 15 is a
one-line env change once ABA confirms the number they want.

## 7. Security

* api key: `payway.py:263` only, server env — **not** in the handoff (PLUGIN05)
* HMAC-SHA512: `payway.py:449-457`, server only; 0 hits for `hmac`/`sha512` in `lib/` and the bundle
* browser sends `{sku, attempt_key}`, Pydantic `extra='forbid'`; amount from the catalogue (PLUGIN10)
* the plugin form is built from a server map; Dart names no field (PLG06 bans the field names in the bridge and controller)
* `merchant_id` / `hash` in the browser = ABA's published integration; neither signs anything
* grant only via `verify_and_settle` → Check Transaction → Billing, once (PLUGIN13); popup open/close/callbacks never touch state (PLG05, ABA07)
* secret scan: 11 PASS, 0 leaks; plugin include allowed verbatim, everything else on that host still banned

## 8. Gates

| | |
| --- | --- |
| `flutter analyze` | 0 issues |
| `flutter test` | **1451** pass (full run); payment suite re-run green after the last edit |
| `pwa_staging_payments_test.py` | **224** assertions |
| `payway_adapter_test.py` | **99** assertions |
| `pwa_secret_scan.py` | 11 PASS, 0 LEAKS |
| build staging · deploy preprod | exit 0 |

## 9. Scope

`frontend/lib` 0 · `frontend/ios` 0 · RevenueCat NO · native iOS NO · Billing
semantics NO · creative engine NO · production Supabase / PayWay / Firebase NO
· real money NO.

## 10. Not done, and why

* **Desktop 1440×900 Wallet + popup screenshot.** The CDP driver cannot open
  the Wallet at a desktop viewport (a pre-existing input-emulation limit). The
  desktop *plugin branch* is nonetheless proven: with a desktop UA the plugin
  built `.aba-checkout-desktop`, whatever the viewport.
* **Success / failed states live.** Unreachable until ABA whitelists the
  domain — no transaction can be created. Covered by PLUGIN13 and the
  unchanged `verify_and_settle` path.
* **Real-phone review.** Awaiting, per the brief.

## STOP

Waiting for ABA to whitelist `preprod.aydenstudio.com` on the sandbox
merchant, then real-phone review. Option B code stays dormant and unreferenced
until the plugin path is validated end to end.
