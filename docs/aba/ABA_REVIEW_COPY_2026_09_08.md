# ABA review, round 2 (2026-09-08) — provider copy removed, "Payment method" titled — PWA only

Baseline: PWA `4bb513c` (result cards) on top of `d0c672a` / `3230dd2` (round 1) and the
freeze `75d68eb`. Two UI-only commits, one per ABA remark. Nothing about the checkout moves:
official plugin, `skip_success_page=1`, Check Transaction authority, single grant, official
assets, footer, result cards, prices, Billing — all unchanged. Backend untouched, not deployed.

## Remark 1 — "remove all those message… there is no requirement UI related to ABA PayWay"

The sentence ABA pointed at, under Buy on the Wallet:

> Payment is handled by ABA PayWay, on ABA's own secure page.

is removed entirely (key `pwaPaywallSecureNote` retired in EN/KM/FR, getter and widget gone).
Every other sentence of Ayden's that named the provider was then made provider-neutral. Status
feedback is kept; only the provider's name leaves it.

| Key | Before (EN) | After (EN) | Where |
|---|---|---|---|
| `pwaPaywallSecureNote` | Payment is handled by ABA PayWay, on ABA's own secure page. | *(removed)* | Wallet, under Buy |
| `pwaPayInlineChecking` | Checking your payment with ABA PayWay… | Checking your payment… | Wallet, inline line while the plugin is open |
| `pwaPayFailedNotCreated` | ABA PayWay could not start the payment. Please try again. | Payment could not start. Please try again. | Wallet, inline error (NOT_CREATED) |
| `pwaPayConfirmingBody` | Your bank has told us. We are checking with ABA before adding your spaces. | Your bank has told us. We are confirming the payment before adding your spaces. | confirming card |
| `pwaPayPluginOpen` | ABA PayWay's secure checkout is open. Finish there — this will update by itself. | The secure checkout is open. Finish there — this will update by itself. | sheet body behind the plugin (not reached on the live path) |
| `pwaPayContinueToAba` | Continue to ABA PayWay | Continue to payment | dormant light path |
| `pwaPayLinkExpiredBody` | ABA payment links are only valid for a few minutes… | Payment links are only valid for a few minutes… | dormant light path |
| `pwaPayScanBody` | Open ABA Mobile — or any Cambodian bank app that reads KHQR — and scan this code. | Open any Cambodian bank app that reads KHQR and scan this code. | dormant light path |
| `pwaPayTitle`, `pwaPayOpenInNewTab`, `pwaPayHandoffBodyDesktop`, `pwaPayHandoffBodyPhone`, `pwaPayReturnTitle`, `pwaPayReturnBody` | "Pay with ABA PayWay", "Open ABA PayWay in a new tab", "…on ABA PayWay's own page below…", "We are confirming this with ABA…" | *(removed — no widget used them)* | — |

KM and FR carry the same edits (FR `pwaPayPluginOpen` says "cet écran", never "carte": ABA03
bans every other payment-method noun, "carte" included).

### What still says ABA, and why

| Text | Why it stays |
|---|---|
| **ABA KHQR** on the Wallet's payment-option card | The payment method's own name, on ABA's official tile (`aba_khqr_payment_option.svg`), in the format ABA asked for in round 1. |
| **Scan to pay with any banking app** | ABA's own description line for that option (localised, unchanged). |
| **We accept** + official `abakhqr-we-accept.svg` in the site footer | ABA's acceptance mark, requested in round 1. |
| **Open ABA Mobile** (`pwaPayOpenAba`) | The label of a deeplink button that opens that app — on the dormant light path only; never rendered on the plugin path. |
| Text inside ABA's checkout (the plugin's popup / sheet) | ABA's UI, not Ayden's. |

Nothing else in the three dictionaries contains "PayWay", and "ABA" appears in no sentence of
ours (ABA04 scans every value of every locale; DM07 reads the Wallet as rendered, before Buy and
while the payment is being checked).

## Remark 2 — "Payment method" above the ABA KHQR card

A section title, directly above the card, in the sheet's quiet secondary tone
(`pwaSans 12.5 / w600 / #C8B99B`, 8 px above the card, left edges aligned), key
`pwa-paywall-method-title`. The card itself is untouched (tile, "ABA KHQR", subtitle).

| Locale | Copy |
|---|---|
| EN | Payment method |
| FR | Moyen de paiement |
| KM | មធ្យោបាយ​ទូទាត់ |

Existing key `pwaPayMethodTitle` (present in all three dictionaries since round 1, unused until
now). No second heading: `find.text('Payment method')` is exactly one widget on the Wallet
(WAL04), and nothing renders between the title and the card.

## Tests

- New: **ABA04** (rewritten: retired keys absent, no "PayWay" in any value, "ABA" only inside
  "ABA KHQR" / "ABA Mobile", the two live lines word for word, getter and widget gone),
  **DM07** (Wallet as rendered: no provider prose before Buy and while checking; method named
  once), **WAL04** (title exact, once, directly above the card, left-aligned, card unchanged,
  FR/KM localised).
- Updated: PAYWAY17, PAYWAY24, ABA03 (surfaces list now includes the live lines), ABA05,
  BILL07, I18N18 allow-list (`'ABA PayWay'` removed), the light-path QR panel test.

Gates: see the two commit messages (analyze 0, full suite green, payment suite green, staging
build OK, secret scan PASS).

## Visual validation (preprod, after deploy — bundle `49818b1f…`, served hash verified)

`docs/aba/shots/copy-2026-09-08/` (Wallet opened from Profile → "Your spaces"):

| File | What it shows |
|---|---|
| `01-wallet-mobile-390x844.png` (EN) | "Payment method" → official ABA KHQR card → Buy · $7.99 → identity lines. Nothing under Buy. |
| `02-wallet-mobile-tall-390x1400.png` (EN) | The whole sheet, unscrolled, same order. |
| `03-wallet-desktop-1440x900.png` (FR) | "Moyen de paiement" → card with the FR subtitle → Acheter. |
| `04-wallet-desktop-1440x900-scrolled.png` (FR) | Under Acheter: identity lines, "Pas maintenant" — no sentence. |
| `05-wallet-desktop-checking-inline.png` (FR) | After Buy and after closing ABA's popup: "Vérification de votre paiement… · Annuler ce paiement" — the status line, provider-neutral. Checkout confirmed working (plugin popup opened with ABA's own "ABA KHQR" sheet). |
| `06-wallet-desktop-cancelled-card.png` (FR) | After the inline cancel: the unchanged verdict card ("Paiement échoué / annulé", "Aucun crédit n'a été ajouté", Réessayer); Buy live again, no inline line. |
| `00-profile-*.png` | The Profile pages the Wallet was opened from; footer "We accept" unchanged. |

The two captures taken while ABA's popup was open show a scannable sandbox KHQR and are kept
out of the repository (`docs/aba/shots/README.md`). The one sandbox transaction created for
this check was cancelled through the existing server-verified cancel; no money, no grant.

## Deploy

PWA preprod only (`tool/deploy_pwa.sh --preprod`), after green gates. Backend not deployed.
Production untouched. No push.
