# ABA merchant review — fix pass (2026-09-08) — PREPROD ONLY

Baseline: accepted freeze PWA `75d68eb` + backend `8ec120c` (untouched; this pass is new
commits on top). Scope: the four items of ABA's review feedback, the exact Check
Transaction answers, tests, preprod deploy. No B2, no production, no Billing change, no
change to the plugin architecture or to the settlement authority.

## What changed

| ABA item | Change | Where |
|---|---|---|
| 1. Payment option format | Official tile `ABA BANK.svg` (served as `web/aba/aba_khqr_payment_option.svg`, byte-identical), copy **ABA KHQR** / **Scan to pay with any banking app** (KM/FR translated faithfully, old "…that supports KHQR." removed). No chevron: informational row, Buy sole CTA. | `pwa_aba_marks.dart`, `pwa_translations.dart` |
| 2. Skip ABA success page | `skip_success_page=1` added to the signed Purchase fields the official plugin posts (24th and last hashed field; only on the plugin path). | backend `payway.py`, `pwa_staging_payments.py` |
| 3. Success header | Ayden's payment card no longer shows the ABA tile or "ABA KHQR" once the payment has an outcome (granted, and the other terminal states); shown while paying. | `pwa_payment_sheet.dart` `_Header` |
| 4. "We accept" in the footer | Official `abakhqr-we-accept.svg` (byte-identical) in a site footer at the foot of Home, Projects and Profile, caption "We accept" localised; removed from the bottom-nav Profile label; no duplicates, Wallet untouched. | new `pwa_site_footer.dart`, `pwa_nav_shell.dart`, `pwa_home_ios.dart`, `pwa_projects_ios.dart`, `pwa_profile_ios.dart` |
| 5. Generated marks retired | `web/aba/*.png` deleted; no Dart reference; provenance README kept. | `web/aba/`, `docs/aba/REJECTED_AI_GENERATED/README.md` |

Rendering: Flutter web cannot decode SVG with `Image.network` (measured), so `flutter_svg`
2.3.0 draws the files from the same same-origin URLs, through a status-checked loader
(`lib/features/pwa/data/pwa_mark_loader.dart`) that draws nothing on anything but a 200.
The tile's `<foreignObject>` blur is skipped by flutter_svg and is invisible anyway (under
the opaque fill); pixel comparison against Chrome's native rendering was identical.

## Live verification on preprod (2026-09-08, after deploy)

| Check | Mobile 390×844 (iPhone UA) | Desktop 1440×900 |
|---|---|---|
| Wallet row = official tile + "ABA KHQR" + exact subtitle | PASS (`B1` FR, `B2` EN) | PASS (`C3`) |
| Footer with official lockup, nav clean | PASS Home/Profile/Projects (`A1`, `A1b`, `A2`, `A2b`, `A3`) | PASS (`C1`, `C1b` scrolled, `C2`) |
| Buy → official plugin owns checkout (sheet / popup, iframe by plugin) | PASS (`D1`) | PASS (`D2`) |
| `skip_success_page=1` in the signed form posted by the plugin | PASS (DOM: `…, return_params, skip_success_page, hash, is_plugin_js`; value `1`) | PASS |
| PayWay accepts the new hash (Check Transaction finds the transaction) | PASS `Ae306a5e867764e30091` `00` PENDING | PASS `A23176c201300ddced75` `00` PENDING |
| Close without paying → zero grant; cancel → CANCELLED | PASS (`E1`) | PASS, ✕ → confirm → hidden, 1 document load (`E2`) |
| No old PNG requested; only the two SVGs | PASS (resource timing) | PASS |
| Ayden success card without ABA header | Widget test ABA09; **live: pending a real sandbox payment** | idem |

Deployed: preprod bundle `main.dart.js` sha256 `ebd2b850…` (Firebase site
`ayden-studio-preprod`), backend Fly `ayden-api-staging` release **v11**; `/config`
unchanged (sandbox, `abapay_khqr`).

## Live end-to-end with a real sandbox payment (2026-09-08, `Ad0b4f40c21180850350`)

The product owner scanned the KHQR issued from the driven mobile browser (iPhone UA,
`skip_success_page=1` in the posted form). Observed and recorded:

| Step | Result |
|---|---|
| PayWay | Check Transaction `00` **APPROVED** code 0, 4.99 USD |
| Settlement | 1 order PAID, 1 payment SUCCESS, **exactly 1 GRANT +10**, user total 1 GRANT; recount minutes later unchanged |
| Entitlement (same guest) | before `credits_available 1 / pass 0 / free` → after `credits_available 10 / pass_credits 10 / access_source pass / watermarked false` |
| ABA success page | **skipped**: the sheet slid away on its own (`aria-hidden=true`), no ABA "Success" screen |
| SPA | **no reload, no navigation** (single `navigate` entry, 1071 s since load) — so the sandbox merchant profile has no "Success URL for Web Continuation"; production must match (asked in the ABA message) |
| Ayden | the paywall closed and the success card appeared once, **without ABA KHQR header** (`F1`, `F2`); Profile reads "10 spaces left" (`F3`); footer present; no duplicate success screen, no stuck overlay |

Timing (rail row, UTC): QR issued 08:32:38.9 → signed pushback received 08:35:15.5
(`callback_count 1`, signature OK) → forced Check Transaction 08:35:16.3 (37th check) →
ledger GRANT 08:35:16.9 → `granted_at` 08:35:17.0. Pushback to grant: 1.5 s; the browser
read GRANTED on its next poll and showed the success card.

## Tests and gates (all exit 0)

| Gate | Result |
|---|---|
| `flutter analyze` | 0 issues |
| `flutter test` | 1463 pass (was 1456) |
| `flutter test …/pwa_payment_test.dart` | 62 pass (ABA09/10, WAL03, NAV01–07 rewritten, ABA-REVIEW-04) |
| `bash tool/build_pwa.sh staging` | OK; `build/web/aba` = the two SVGs only |
| `pwa_secret_scan.py` | PASS 11 / LEAKS 0 |
| `payway_adapter_test.py` | 102 (ABA-REVIEW-05: literal "1", last in hash, absent by default) |
| `pwa_staging_payments_test.py` | 240 (ABA-REVIEW-05 form field; ABA-REVIEW-11 cadence pinned) |
| Billing suites | 81 / 115 / 39, 0 failures |
| `pwa_target_test.py` | pass |

Test-id map: 01/02 WAL03 · 03 NAV02 + FOOT01 (Home/Projects/Profile) · 04 ABA-REVIEW-04 ·
05 PLG01 + rail/seam ABA-REVIEW-05 · 06 PLG/DM groups · 07 backend ABA10/ABA11/PLUGIN13 +
PAY03 · 08 ABA09 · 09 DM/PAY03 · 10 PAY02 + backend cancel + live · 11 seam ABA-REVIEW-11 ·
12 secret scan + staging-only guards.

## Check Transaction answers

See `ABA_REVIEW_RESPONSE_2026_09_08.md` (A–J with code locations, and the message).

## Evidence index

`docs/aba/shots/review-2026-09-08/`: `A1`, `A1b`, `A2`, `A2b`, `A3` (footers, mobile FR/EN),
`B1`, `B2` (Wallet format FR/EN), `C1`, `C1b`, `C2`, `C3` (desktop), `E1`, `E2` (after
close/cancel). `D1` (mobile plugin sheet) and `D2` (desktop popup) show a scannable sandbox
KHQR and are kept out of the repository, like the earlier ones (`docs/aba/shots/README.md`).

## Notes

- Cosmetic, pre-existing: the English pack cards read "10 spaces" (lowercase); untouched.
- The desktop Home footer sits just below the fold at 900 px and is reached by a short
  scroll (`C1b`); the pinned "New design session" button is unaffected.
