# ABA KHQR — final preprod implementation

Option B. Compact Wallet modal. Acceptance mark integrated in the bottom
navigation. Preprod / sandbox only, no production touched, no real payment.

**Preprod:** https://ayden-studio-preprod.web.app · https://preprod.aydenstudio.com

---

## 1. What was wrong, and what is corrected

| Rejected | Now |
| --- | --- |
| ABA's full desktop checkout page inside a 0.90-height bottom sheet | A ~400 px white card, centred, sized by its content, over a Wallet that is still legible |
| A standalone full-width "We accept" strip inserted above the nav on Home and Profile | One placement, inside `PwaBottomNav`, under Profile — every screen with the bar inherits it |
| Ayden text + a hairline pill standing in for the marks | The supplied artwork, as one image |
| Duplicated checkout chrome: pack header, paragraph, waiting block, external-tab CTA | Method, amount, QR, one line of instruction, ABA Mobile |

## 2. Payment option

| | |
| --- | --- |
| Previous | `PAYWAY_PAYMENT_OPTION = "abapay_khqr"` — HTTP 302, `Location` only, no first-level fields |
| **New** | `PAYWAY_PAYMENT_OPTION = "abapay_khqr_deeplink"` — HTTP 200 JSON |

`backend/fly.toml`, staging app only. `fly.prod.toml` untouched.

## 3. PayWay response fields used

Measured on the sandbox, every first-level field the 200 JSON returns:

| Field | Used for |
| --- | --- |
| `qr_string` (229 chars) | **the QR** — encoded byte-for-byte, never parsed |
| `abapay_deeplink` (278 chars) | **"Open in ABA Mobile"** — verbatim, never constructed |
| `checkout_qr_url` | stored; shown only on the no-QR fallback rail |
| `status` | `tran_id`, `trace_id` for support |
| `description` | unread |

Not obtainable on this rail: a certified QR **image**. `download_qr` exists only
inside the opaque checkout token, which `payway.py` refuses to parse.

## 4. QR rendering

**Mechanism:** `segno` 1.6.6 — pure Python, no C extension, deterministic —
server-side in `backend/pwa_qr.py`, called from exactly one place.

**Authorisation:** approved by the **product owner / user**. ABA has not
separately confirmed a renderer, and this document does not claim they have.

**Proof the payload is unchanged** (live sandbox transaction, 2026-09-05):

```
payload length   : 229 chars
payload prefix   : '00020101021230510016abaakhppxxx@ab'
payload suffix   : 'hase6304BBEF'
PNG magic        : b'\x89PNG\r\n\x1a\n'
deterministic    : True
payload-sensitive: True     (one character changed -> different symbol)
unmodified       : True     (rendered string == PayWay's field)
deeplink scheme  : abamobilebank
```

**Deliberately plain:** black modules, white ground, four-module quiet zone,
error level M. No logo in the centre, no rounded cells, no colour.

**Storage / delivery:** rendered once in `start_checkout`, stored in the
existing `qr_image` column on the order row, served by `public_view` to the
owner of that order. No route renders a caller-supplied payload — pinned by
tests QR07–QR10, which also assert the renderer module contains none of the
vocabulary of a payload *builder* (`crc`, `emv`, `tag_`, `split`, `replace`).

## 5. Files changed

**Backend (staging)**

| File | |
| --- | --- |
| `backend/pwa_qr.py` | **new** — the renderer, 1 public function |
| `backend/pwa_staging_payments.py` | renders the QR at the one place the payload arrives |
| `backend/fly.toml` | the payment option |
| `backend/requirements.txt` | `segno>=1.6.1` |
| `backend/pwa_staging_payments_test.py` | QR01–QR14, and the fake now answers in the shipped shape |

**PWA**

| File | |
| --- | --- |
| `lib/features/pwa/presentation/pwa_aba_marks.dart` | rewritten — the supplied artwork, `PwaAcceptMark` + `PwaAbaMethodMark` + `PwaAbaMethodRow` |
| `lib/features/pwa/presentation/pwa_nav_shell.dart` | **the acceptance mark, under Profile, inside `PwaBottomNav`** |
| `lib/features/pwa/presentation/pwa_payment_sheet.dart` | the compact dialog; iframe and duplicated chrome removed |
| `lib/features/pwa/presentation/pwa_home_ios.dart` | rejected strip **removed** |
| `lib/features/pwa/presentation/pwa_profile_ios.dart` | rejected strip **removed** |
| `lib/features/pwa/presentation/pwa_paywall.dart` | rejected strip **removed** |
| `lib/features/pwa/l10n/pwa_translations.dart`, `pwa_l10n.dart` | `pwaPayClose`, EN/KM/FR |
| `test/features/pwa/pwa_payment_test.dart` | ABA01–ABA08, NAV01–NAV05, PAYWAY13/14 realigned |
| `test/features/pwa/pwa_projects_parity_test.dart` | PROJ04 narrowed to project imagery |
| `web/aba/*.png` | the two supplied assets |

**Deleted:** `pwa_aba_checkout_frame.dart` / `_stub.dart` / `_web.dart` — the
embedded-checkout boundary, now unreachable. Its measurement survives in
`PHASE0_SPIKE_2026_09_05.md` and in the `fly.toml` comment.

## 6. Where the footer integration lives

`lib/features/pwa/presentation/pwa_nav_shell.dart`, inside `PwaBottomNav`.

The `Row` is top-aligned and the Profile cell becomes a two-child `Column`: the
nav item, then `PwaAcceptMark(height: 30)`. One placement — asserted by NAV03,
which fails if `PwaAcceptMark` appears in Home, Profile, the Wallet, the Design
Session or the Reveal, and which counts exactly one occurrence in the shell.

Because `PwaNavShell` is mounted only by Home, Projects and Profile, the
immersive screens inherit nothing. Verified: `pwa_architect_screen.dart`,
`pwa_reveal_screen.dart` and `pwa_create_ios.dart` reference neither
`PwaBottomNav` nor `PwaNavShell`. No artificial bar was added to them.

## 7. Assets

| | |
| --- | --- |
| Acceptance mark | `web/aba/we_accept_aba_khqr.png` — 2172×724, artwork bounds 1994×617 (3.23:1), used as ONE image at 30 px height |
| Payment method | `web/aba/aba_khqr_logo.png` — 1254×1254, at 34 px in the Wallet row and 26 px in the modal header |

Fetched same-origin by relative URL, not compiled into the bundle: ABA can send
replacement artwork and it swaps with a redeploy, no Dart change.

## 8. Modal dimensions

| | |
| --- | --- |
| Desktop | `min(viewport − 32, 400)` wide; height content-driven, capped at `viewport − 48` |
| Mobile | same rule — 358 px at 390 px viewport, 16 px each side |
| Scrim | `black @ 38 %`, no blur |
| Presentation | `showDialog`, centred. `showModalBottomSheet` is asserted absent |

## 9. Payment authority — unchanged

Browser → Ayden backend → PayWay sandbox. Check Transaction authoritative;
canonical Billing grant. No grant from the QR being displayed, the modal being
closed, a browser return, a query parameter, client state, or the deeplink
opening. Idempotency, single-flight and tran_id lifecycle untouched.

**Security**

* `qr_string` is written server-side only, from PayWay's response, on the order row
* the browser cannot supply a payload — the client sends `{sku, attempt_key}`, Pydantic `extra='forbid'`
* the amount is resolved from the catalogue server-side
* no merchant credential in the bundle — secret scan 11 PASS, 0 leaks
* HMAC signing remains `payway.py:449-457`, server env keyed
* **no iframe anywhere in the app** — verified on the live page: `{"iframes":[],"imgTags":0}`

## 10. Comparison with the approved flow

| Element | Approved | Implementation | Match |
| --- | --- | --- | --- |
| Wallet visible behind | yes | yes — hero, packs, method row, CTA all legible | ✅ |
| Modal width | compact card | 358 px at 390 vp | ✅ |
| Overlay | subtle dim | 38 %, no blur | ✅ |
| Title | ABA KHQR | ABA KHQR + supplied mark | ✅ |
| Close X | top right | top right, every state | ✅ |
| Amount | prominent | `10 Spaces` / **$4.99** | ✅ |
| QR | real, centred | real, server-rendered from ABA's payload | ✅ |
| Instruction | scan with any banking app | one line, EN/KM/FR | ✅ |
| ABA Mobile CTA | present | ABA's own deeplink | ✅ |
| External page chrome | none | none — no iframe, no ABA footer, no instruction column | ✅ |
| Bottom footer | integrated | inside `PwaBottomNav`, under Profile | ✅ |
| QR centre badge | ABA badge in the deck | **plain QR** — deliberate: no logo may be embedded | ⚠️ stated |

## 11. Gates

| | |
| --- | --- |
| `flutter analyze` | 0 issues — exit 0 |
| `flutter test` | **1441 passed** — exit 0 |
| `backend/pwa_staging_payments_test.py` | **192 assertions** — exit 0 |
| `backend/payway_adapter_test.py` | **99 assertions** — exit 0 |
| `backend/pwa_secret_scan.py` | 11 PASS, 0 leaks — exit 0 |
| `./tool/build_pwa.sh staging` | built, dotenv stripped — exit 0 |
| `./tool/deploy_pwa.sh --preprod` | preprod only, live untouched — exit 0 |

## 12. Screenshots — `shots/final/`

`A-home-desktop` · `B-home-mobile` · `D-profile-mobile` · `E-wallet-desktop` ·
`G-wallet-mobile` · `H-wallet-mobile-modal` · `I-modal-closed`

**Not captured this pass:** the desktop Wallet with the modal open. The CDP
driver could not open the Wallet sheet at the desktop viewport — `E-wallet-desktop.png`
shows Profile, not the Wallet. The mobile pair (`G` / `H`) is the ABA-facing
artefact and is correct; the desktop pair needs a manual capture.

## 13. Scope

| | |
| --- | --- |
| `frontend/lib` diff | **0** |
| `frontend/ios` diff | **0** |
| Creative engine changed | NO |
| Billing semantics changed | NO |
| Grant semantics changed | NO |
| RevenueCat changed | NO |
| PayWay signing changed | NO |
| Production Supabase touched | NO |
| Production PayWay touched | NO |
| Production Firebase touched | NO |
| Production | NO |
| Real payment | NO |
| QR rendering authorisation | **APPROVED BY PRODUCT OWNER / USER** |
