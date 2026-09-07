# ABA checkout iframe — security note

Preprod / sandbox only. No production deployment, no billing change, no PayWay
production work. Payment UX unchanged.

**One correction up front: the claim in the previous report — that the `sandbox`
attribute prevented ABA's page from rendering — is wrong.** It was a timing
artefact. Re-measured properly, the sandbox has been restored.

---

## 1. Iframe markup BEFORE

As first shipped (`pwa_aba_checkout_frame_web.dart`):

```dart
_frame = web.HTMLIFrameElement()
  ..src = url
  ..title = 'ABA PayWay'
  ..setAttribute('sandbox',
      'allow-scripts allow-forms allow-same-origin allow-popups')
  ..setAttribute('referrerpolicy', 'strict-origin-when-cross-origin')
  ..setAttribute('allow', 'payment')
  ..setAttribute('loading', 'eager');
_frame.style.setProperty('width', '100%');
_frame.style.setProperty('height', '100%');
_frame.style.setProperty('border', '0');
_frame.style.setProperty('background', '#ffffff');
```

Then, for a few hours on 2026-09-04 and on the false diagnosis below, the
`sandbox` line was deleted. That intermediate state is what the previous report
described. It is no longer what ships.

## 2. Iframe markup NOW

```dart
const _kFrameSandbox = <String>[
  'allow-scripts',
  'allow-same-origin',
  'allow-forms',
  'allow-popups',
];

_frame = web.HTMLIFrameElement()
  ..setAttribute('sandbox', _kFrameSandbox.join(' '))
  ..setAttribute('referrerpolicy', 'strict-origin-when-cross-origin')
  ..setAttribute('allow', 'payment')
  ..setAttribute('loading', 'eager')
  ..title = 'ABA PayWay'
  ..src = url;
```

`sandbox` is now set **before** `src`. On a detached element the order has no
effect today, but an iframe given a URL before its sandbox is one refactor away
from navigating unsandboxed, and that is not a bug anyone would see.

**Verified in the deployed artifact**, not only in source
(`GET https://ayden-studio-preprod.web.app/main.dart.js`, 3 876 821 bytes):

```js
q = document.createElement("iframe")
q.setAttribute("sandbox", B.b.bq(B.a4d," "))
q.setAttribute("referrerpolicy","strict-origin-when-cross-origin")
q.setAttribute("allow","payment")
q.setAttribute("loading","eager")
q.title = "ABA PayWay"
q.src = a
…
B.a4d = s(["allow-scripts","allow-same-origin","allow-forms","allow-popups"], t.s)
```

`allow-top-navigation`: **0 occurrences** in the deployed bundle.

And read back off the live running page (DOM, through the Flutter shadow root):

```
sandbox        : allow-scripts allow-same-origin allow-forms allow-popups
allow          : payment
referrerpolicy : strict-origin-when-cross-origin
loading        : eager
title          : ABA PayWay
size           : 340 x 558
src host       : checkout-sandbox.payway.com.kh
```

## 3. Which sandbox restriction broke PayWay — none of them

**The previous conclusion was unsound.** The evidence for it was a two-arm
comparison: with the sandbox the page showed only its static shell; without it,
after a reload, the page rendered. The confound is that the reload also bought
six more seconds, and ABA's page needs them.

Re-measured on preprod against a real sandbox transaction, each condition given
18–22 s and instrumented with Chrome's own log stream (`Log.entryAdded`,
`Runtime.consoleAPICalled`, `Runtime.exceptionThrown`):

| Condition | `sandbox` | Result |
| --- | --- | --- |
| **B** | `allow-scripts allow-forms allow-same-origin allow-popups` (the original) | **Full render.** KHQR header, merchant, 7.99 USD, the real QR, "Scan. Pay. Done.", totals, ABA footer |
| **E** | `allow-scripts allow-forms allow-popups` | **Shell only** — wordmark and footer, nothing built at runtime |
| **D** | `allow-scripts allow-same-origin` | **Full render** |

Every condition reported `loaded: true, errored: false` and **zero log
entries**. Chrome does not report this failure at all.

So:

* the original sandbox **did not** break ABA's page;
* the original blank frame was a page **caught mid-load**;
* the one token that does break it is **`allow-same-origin`** — without it the
  frame gets an opaque origin, loses cookies and storage, and the checkout
  session never initialises.

Condition E is *visually identical* to the failure that was misattributed to the
sandbox. That is precisely why the first inference looked sound, and why the
regression test in §6 exists.

## 4. No sandbox, or a reduced set?

**A reduced set.** Four tokens, listed in §2. Not "no sandbox" — that was true
for a few hours and is not true now.

## 5. Minimum permissions actually required

**Proven necessary** (condition D renders completely):

* `allow-scripts` — the page is entirely script-built
* `allow-same-origin` — proven by condition E

**Not required to render, kept anyway:**

* `allow-forms`, `allow-popups`

They are kept because rendering the QR is not the whole payment. The completion
path — the payer scans, their bank confirms, ABA's page reacts — cannot be
exercised in sandbox without making a real payment, so I cannot show that
dropping them is safe. A render test that does not reach a code path proves
nothing about that code path. **Candidate for removal if ABA confirms their KHQR
flow posts no form and opens no new context.**

## 6. Per capability

| Capability | Granted | Required | Evidence |
| --- | --- | --- | --- |
| `allow-scripts` | yes | yes | page is script-built |
| `allow-same-origin` | yes | **proven yes** | condition E → shell only |
| `allow-forms` | yes | unproven | not needed to render; completion path untestable |
| `allow-popups` | yes | unproven | same |
| `allow-top-navigation` | **no** | **must stay denied** | it would let ABA's page unload the Flutter app, destroying the Wallet and the payment poll — the exact defect the embedded checkout removes |
| `allow-top-navigation-by-user-activation` | no | — | never requested |
| `allow-modals`, `allow-downloads`, `allow-pointer-lock`, `allow-presentation`, `allow-popups-to-escape-sandbox`, `allow-orientation-lock`, `allow-storage-access-by-user-activation` | no | — | never requested |

Pinned by test `ABA06` in `test/features/pwa/pwa_payment_test.dart`: asserts the
four tokens are present, that the eight above are absent, and that `sandbox` is
set before `src`.

## 7. Current `allow` attribute

`allow="payment"` — a Permissions-Policy delegation of the Payment Request API.
It grants no data access and reads nothing.

**It has no proof of necessity.** With `PAYWAY_PAYMENT_OPTION=abapay_khqr` the
embedded page is a QR, and Payment Request is not in play. See §9.

## 8. CSP and frame restrictions on our side

**Measured on the live origin**, not read from config
(`curl -sSI https://ayden-studio-preprod.web.app/`):

| Header | Value |
| --- | --- |
| `Content-Security-Policy` | **absent** |
| `Permissions-Policy` | **absent** |
| `Cross-Origin-Embedder-Policy` / `-Opener-` / `-Resource-` | **absent** |
| `X-Frame-Options` | `SAMEORIGIN` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `X-Content-Type-Options` | `nosniff` |
| `Strict-Transport-Security` | `max-age=31556926; includeSubDomains; preload` (added by Firebase, not by us) |

Three consequences:

* There is **no `frame-src`**, so no header-level policy of ours restricts what
  the page may embed. The only outbound restriction is the element's own
  `sandbox`.
* `X-Frame-Options: SAMEORIGIN` is **inbound only** — it says who may embed
  *our* page. Reading it as a restriction on what we embed would be the central
  misreading of this file.
* `COEP: require-corp` is **not set**, so the "COEP blocked the frame"
  hypothesis is eliminated by absence, not by argument.

The service worker cannot interfere: the deployed
`flutter_service_worker.js` is Flutter's self-destruct stub — an `install`
(`skipWaiting`) and an `activate` (`unregister`), with **no `fetch` listener at
all**. A service worker would not see a cross-origin frame navigation regardless.

The backend is not on this path: Firebase Hosting serves the document, not the
API, and CORS governs fetch/XHR, not framing.

## 9. Unnecessary capabilities

One candidate, and it is not the sandbox: **`allow="payment"`**.

Under KHQR-only the embedded page never invokes the Payment Request API, so the
delegation is unused. It is narrow — it permits a call, it exposes no data — and
removing it would silently break a card flow if `PAYWAY_PAYMENT_OPTION` were
ever unpinned. **Not removed. Awaiting your instruction**, since the brief says
do not alter behaviour without evidence, and I have no evidence either way about
ABA's completion path.

Everything else was reduced: the sandbox is back, and it withholds the one
capability that matters.

---

# Confirmations requested

### ✅ The checkout URL is server-returned

Proven, single write-site, no client construction anywhere:

* `pwa_payment.dart:255` — `checkoutUrl: (body['checkout_url'] as String?) ?? ''`
  is the **only** assignment to `checkoutUrl` in all of `lib/`
* `pwa_payment_sheet.dart:394` — the only construction of `_AbaCheckout`, from
  `payment.checkoutUrl`
* `pwa_aba_checkout_frame_web.dart` — `..src = url`, verbatim, no concatenation,
  no template, no fallback. The only other write is `about:blank` on teardown
* server side: `pwa_staging_payments.py:504` stores what `payway.purchase()`
  returned; `payway.py:849-850` takes it from PayWay's 302 `Location`, or
  `:873-882` from `checkout_qr_url` in the JSON body, against a **hardcoded**
  host constant

In the compiled bundle the src is not even a constant: `q.src=a`, a function
parameter.

### ✅ The iframe URL cannot be replaced by arbitrary client input

Holds, on three independent layers:

* the browser sends exactly `{sku, attempt_key}` to open a checkout
  (`pwa_generation_api.dart:606-609`); the request model is Pydantic
  `extra='forbid'`
* `sku` is resolved against the server's own catalogue; `attempt_key` is a
  locally minted UUID that is SHA-256-digested into `tran_id` and never echoed
  into a URL; the `Origin` header is bounded by an exact allowlist plus an
  anchored regex and feeds only the return/cancel URLs
* the row is **not writable by the browser**:
  `grant select on pwa_staging.payway_transactions to authenticated` /
  `grant all … to service_role`, RLS enabled with an own-row SELECT policy
  (`supabase/staging/pwa/0007_payway_sandbox.sql:274-304`)

No query parameter, route, browser storage or typed text reaches the value.

### ❌ Only expected PayWay origins may be embedded — **NOT ENFORCED**

This is the one confirmation I cannot give, and softening it would be the wrong
service.

There is **no origin validation of `checkout_url` at any layer**: not on the
server before storing, not on the client before assigning `iframe.src`, not
before `window.open`. No allowlist, no `startsWith`, no host check, no CSP
`frame-src`.

What actually holds is a **provenance** argument, not a **validation** one: the
string has exactly one producer, and that producer is a TLS response from a
hardcoded host. That is strong, but it is not the same guarantee.

Two concrete residual paths:

1. **A relative `Location` would resolve against our own origin.**
   `payway.py:844-851` stores the header verbatim with no absolute-URL check.
2. Anything holding the `service_role` key could write any origin into the row,
   and nothing downstream would notice.

**Recommendation — server side, not client side.** A client-side allowlist is
actively forbidden by the existing guard `PAY09`, which fails the build if the
string `checkout.payway` appears anywhere in `lib/` (and rightly: a gateway
hostname in a web bundle is half a client that signs its own requests). The
hostname constants already live in `payway.py:100-102`. The check belongs there,
next to where the URL is received: reject a `checkout_url` whose scheme is not
`https` or whose host is not the configured PayWay base. Roughly ten lines, one
test. **Not implemented — holding for your go-ahead**, since it changes
behaviour in the rejection case.

### ✅ No merchant secret exists client-side

No PayWay API key, no merchant id, no signing material — measured, not assumed:

* `PAYWAY_API_KEY` / `PAYWAY_MERCHANT_ID` appear in **none** of the 134 files of
  the build artifact, nor in any commit of either repo's history
* the deployed `main.dart.js` contains **0** occurrences of `api_key`, `hmac`,
  `sha512`, `checkout-sandbox`, `checkout.payway`, `generate-qr`,
  `check-transaction-2`, `payment-gateway`, `PAYWAY_`
* the 19 hits for `payway` are one iframe `title` and 18 localised UI strings
* the only HMAC-SHA512 primitive is `payway.py:449-457`, keyed from server
  environment only (`payway.py:263`); **no Dart code signs anything** — 0 hits
  for `hmac`/`sha512` in `lib/` and in the bundle
* the browser's four payment calls all target Ayden, never the gateway
* `hash` is stripped before every log line and `__repr__` redacts the key

**Two precisions, because "secret" and "identifier" are different things:**

1. The browser *does* hold credentials — the Supabase **publishable** key
   (public by design, guarded at build time against an `sb_secret_*` value) and
   a Supabase session JWT. Neither is a gateway credential.
2. The `checkout_url` token base64-decodes in the browser to PayWay's own
   payload, which contains the **KHQR string** (including the merchant's ABA
   account identifier) and the merchant display name. This is not a leak: a KHQR
   payload is public by construction — it is the code anyone is invited to scan
   — and it contains no signing material. I decoded a live token to confirm
   exactly what is in it.

---

## Two findings outside the questions asked

**1. The KHQR-only pin is staging-only.** `backend/fly.toml` sets
`PAYWAY_PAYMENT_OPTION = "abapay_khqr"`; `backend/fly.prod.toml` has no such
line, so it would default to empty and PayWay would draw its own chooser —
including Credit/Debit Card. **Not changed** (no PayWay production work), but it
must be set before production or the production checkout will contradict the
approved deck.

**2. The token TTL constant is stale.** `payway.py:160` records
`CHECKOUT_TOKEN_TTL_S = 180`, measured 2026-08-19. A token minted today under
`abapay_khqr` reports `"expire_in_sec": "300"`. The direction is safe — we call
a link stale before PayWay does — but the constant no longer matches the
gateway.

## Gates

`flutter analyze` clean · `flutter test` **1434 pass** (was 1433; `ABA06` added)
· deployed bundle verified to carry the sandbox · payment UX unchanged.
