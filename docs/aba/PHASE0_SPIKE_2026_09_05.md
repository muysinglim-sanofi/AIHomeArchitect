# Phase 0 — evidence spike

Read-only with respect to the deployment. `fly.toml` unchanged, nothing
redeployed, no production touched, no payment made. Two sandbox transactions
were opened to compare the two documented response shapes.

**Result: OPTION B.** The official hosted checkout has no compact layout at any
tested width, and PayWay does hand back the official KHQR payload and ABA Mobile
deeplink as first-level fields.

---

## A. The official hosted page at real iframe viewport widths

Method: the `<iframe>` element is given **exactly** the width under test. No
`transform: scale`, no zoom, no cropping, no CSS injected into ABA's page. The
host page is 40 px wider than the frame so horizontal overflow is visible rather
than clipped by the window. Sandbox as shipped
(`allow-scripts allow-same-origin allow-forms allow-popups`).

Screenshots: `shots/phase0/`.

| Width | Layout mode | QR visible | Left instruction column | ABA footer | Horizontal overflow | Suitable for approved modal |
| --- | --- | --- | --- | --- | --- | --- |
| **340 px** | desktop 2-column | partial — right third of the QR card cut off | yes, heavily wrapped (8 lines for step 1) | yes, address + illustration | yes | **NO** |
| **360 px** | desktop 2-column | partial — right edge cut off | yes, identical wrapping | yes | yes | **NO** |
| **390 px** | desktop 2-column | partial — right edge cut off | yes, identical wrapping | yes | yes | **NO** |
| **420 px** | desktop 2-column | yes, complete | yes, identical wrapping | yes | no | **NO** |

**There is no mobile breakpoint.** The composition is byte-for-byte the same at
all four widths — `ABA' PAYWAY` header band, merchant tile, "Scan. Pay. Done."
instruction column, KHQR card, Subtotal/TOTAL block, ABA Bank footer with postal
address and background illustration. Only the QR clipping changes. Rendered
height is ~1180 CSS px at every width.

Even at 420 px, where nothing is clipped, this is a full web page, not the
approved modal. Making it look like the approved modal would require scaling,
cropping or DOM manipulation — all three explicitly forbidden.

**`checkout_qr_url` was tested too**, because its token carries
`render_qr_page: 1` and looked like a possible compact QR page. It is not: at
340 px and 390 px it renders the identical desktop composition
(`shots/phase0/B-qrpage-*.png`).

## B. What the Purchase API actually returns

Two sandbox transactions, one per option, raw envelope inspected.

### `payment_option=abapay_khqr` — what is deployed today

```
HTTP 302, no content-type, no body.
```

**First-level fields available: NONE.** The only thing returned is the
`Location` header. `qr_string`, `download_qr`, the amount and the expiry all
exist, but exclusively **inside the opaque base64 checkout token**, which
`payway.py:156-159` deliberately refuses to parse ("that blob is opaque,
undocumented, and not a contract"). Confirmed by decoding one by hand:
`qr_string` (229 chars), `download_qr` (245 chars), `expire_in_sec: "300"`,
`payment_options: {abapay_khqr: {label: "ABA KHQR"}}`,
`step: "abapay_khqr_request_qr"`, `transaction_summary`, `merchant`, plus two
opaque blobs (`token`, `aba_data`).

### `payment_option=abapay_khqr_deeplink`

```
HTTP 200, application/json
```

| Field | Value |
| --- | --- |
| `qr_string` | `str[229]` — the official EMV KHQR payload, `00020101021230510016abaakhppxxx@abaa…` |
| `abapay_deeplink` | `str[278]` — `abamobilebank://ababank.com?type=payway&qrcode=…` |
| `checkout_qr_url` | `str[2809]` — the hosted page (same desktop layout, see §A) |
| `description` | `"success"` |
| `status` | `{version: v3, code: "00", message: "Success!", tran_id, lang, trace_id}` |

`payway.purchase()` already reads four of the five; only `description` is
unread.

### What is NOT obtainable

**A certified QR image.** `download_qr` — ABA's own endpoint that returns the
QR as an image — exists only inside the opaque token, never as a first-level
field, on either option. The v1 `generate-qr` API does return a certified
`qr_image`, and the adapter for it still exists (`payway.py:921-955`, no
caller), but ABA's 2026-08-19 guideline directed us off that endpoint.

### Two measured differences that matter

1. **The hosted page's own label changes.** Under `abapay_khqr` the token says
   `payment_options: {"abapay_khqr": {"label": "ABA KHQR"}}`. Under
   `abapay_khqr_deeplink` it says `{"abapay": {"label": "ABA Pay"}}`. The
   transaction is still KHQR in both cases (same `qr_string` shape, same
   `step: abapay_khqr_request_qr`) — but anyone who opened the hosted page under
   the deeplink option would read "ABA Pay".
2. **The token TTL halves**, `expire_in_sec` 300 → 180.

Both are consequences of the option, not of our code, and both are manageable
because under Option B the hosted page is never shown.

## C. Option

### ❌ Option A — official responsive PayWay view

**Not available.** The official hosted checkout has no compact or mobile layout
at 340/360/390/420 px. It cannot be made to match the approved modal without
scaling, cropping or DOM manipulation.

### ✅ Option B — official QR/data composition — **RECOMMENDED**

PayWay officially hands back, as documented first-level fields, everything the
approved modal needs:

| Approved modal element | Source |
| --- | --- |
| Title "ABA KHQR" | our own copy |
| Amount `$7.99` | **our server**, from the catalogue — already authoritative |
| QR | `qr_string`, the official EMV KHQR payload, unmodified |
| "Scan with ABA Mobile or any KHQR banking app" | our own copy |
| "Open in ABA Mobile" | `abapay_deeplink`, official |
| Close X | our own chrome |

Nothing is fabricated: the payload is ABA's, the amount is the server's, the
transaction is the real `tran_id`.

**The one thing ABA must accept**, and it should be asked explicitly rather than
assumed: **the QR pixels would be rendered by us from ABA's payload**, because
ABA does not expose a certified QR image on this rail. This is the documented
purpose of `qr_string` and is what merchant SDKs normally do — but it is ABA's
call, not ours. If ABA declines, the fallback is for ABA to re-authorise
`generate-qr`, whose adapter is already written and which returns their
certified image.

### Option C

Not needed — unless ABA declines self-rendered QR pixels, in which case C is
exactly the one question above.

## Recommended implementation

**Render the QR server-side, not client-side.** The server already receives
`qr_string`, already stores it, and already has a `qr_image` column and a client
field (`PwaPayment.qrImage`) that the Purchase rail never populates. Encoding
the payload to a PNG on the server and filling that existing field means:

* **no new third-party dependency in the browser** on a payment surface
  (`pubspec.yaml` has no QR encoder today, and adding one to the client is the
  larger risk);
* the existing `_QrPanel` widget renders unchanged;
* one auditable encoding site instead of one per client.

The client change then reduces to *presentation only*: replace the tall sheet
with the compact modal, drop the duplicated Ayden checkout chrome, and gate on
`qrString`/`qrImage` instead of embedding a page.

## Estimated files to change

**Backend (staging only) — 3**

| File | Change |
| --- | --- |
| `backend/fly.toml` | `PAYWAY_PAYMENT_OPTION` → `abapay_khqr_deeplink` (1 line) |
| `backend/pwa_staging_payments.py` | encode `qr_string` → PNG into the existing `qr_image` field (~15 lines) |
| `backend/pwa_staging_payments_test.py` | assert the encode is deterministic and the payload is unmodified |

**PWA — 6**

| File | Change |
| --- | --- |
| `lib/features/pwa/presentation/pwa_payment_sheet.dart` | the compact modal; remove the embedded frame, the duplicated header, the long paragraph, the separate waiting block, the new-tab CTA |
| `lib/features/pwa/presentation/pwa_aba_checkout_frame*.dart` (3 files) | no longer used by the modal — keep or delete, to decide |
| `lib/features/pwa/presentation/pwa_nav_shell.dart` | the "We accept" lockup integrated inside `PwaBottomNav`, under the Profile item — **one shared container, so Home / Projects / Profile all inherit it and no standalone strip is created anywhere** |
| `lib/features/pwa/presentation/pwa_aba_marks.dart` | point the two constants at the authorised PNGs; drop the type-only fallback |
| `lib/features/pwa/presentation/pwa_home_ios.dart`, `pwa_profile_ios.dart` | **remove** the standalone strips added yesterday — this is the rejected pattern |
| `lib/features/pwa/l10n/pwa_translations.dart` + `pwa_l10n.dart` | modal copy, EN/FR/KM |
| `test/features/pwa/pwa_payment_test.dart` | footer-in-nav assertions, modal assertions, no-standalone-strip assertion |

Roughly 9 files, one of them a one-line config change.

## Assets

* `web/aba/we_accept_aba_khqr.png` — 2172×724, RGBA, 3:1 — the footer lockup,
  used as one single image (not text + pill)
* `web/aba/aba_khqr_logo.png` — 1254×1254, RGBA, 1:1 — the compact payment-method
  mark in the Wallet row

Both restored from quarantine on your explicit authorisation for this preprod
review; the provenance record is kept at
`docs/aba/REJECTED_AI_GENERATED/README.md` and should be re-read before any
production use.

## STOP

No UI implemented. No deployment. Awaiting your go-ahead on Option B, and on the
one question for ABA: **may Ayden render the QR from the `qr_string` PayWay
returns, or should ABA re-authorise `generate-qr` so their certified image is
used?**
