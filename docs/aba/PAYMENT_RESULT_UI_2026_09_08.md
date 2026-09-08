# Payment result cards — Ayden's verdict UI (2026-09-08) — PWA only

Baseline: PWA `d0c672a` (ABA review fixes, validated live) on top of the freeze `75d68eb`.
This pass changes ONLY the card Ayden shows once a payment has a verdict. Nothing about
the checkout moves: official ABA plugin, `skip_success_page=1`, Check Transaction
authority, single grant, official ABA assets and footer, no ABA header on the result —
all unchanged. Backend untouched.

## What changed

| Before (rejected) | After (approved template) |
|---|---|
| White iOS-style bottom card: "You are all set", "10 spaces are on your account", balance pill, "Start a new design", "Maybe later" | Near-black Ayden card with a subtle gold edge: gold outlined check · **Payment successful** · **{n} spaces added to your wallet** · **Purchase summary** ({pack} · ${amount} / New balance · {balance} spaces) · **[ Continue ]** |
| Failure / cancel / expiry: no card on the plugin path (inline line only) | Near-black card with a red edge: red outlined X · **Payment failed / cancelled** · **No credits were added** · "Your wallet remains unchanged. You can return safely or retry the payment when ready." · **[ Try again ]** |

Files: new `lib/features/pwa/presentation/pwa_payment_result.dart` (the card, the verdict
mapping, the colours); `pwa_payment_sheet.dart` (routes verdicts to the card, near-black
frame for confirming + verdict states, `PwaPaymentExit { paid, none }`); `pwa_experience.dart`
(the return watcher now opens the card on terminal failures too, never on pending states);
l10n: 8 new keys in EN/KM/FR, 4 retired keys (`pwaPayDoneTitle`, `pwaPayDoneBody`,
`pwaPayStartDesigning`, `pwaPayMaybeLater`).

## State safety (unchanged authority)

- Success card only for `PwaPaymentState.granted` — written by the server after Check
  Transaction APPROVED and the single Billing grant.
- Failure card only for the terminal `failed`, `cancelled`, `expired` states. Nothing is shown
  for `awaitingPayment`, `paidPendingVerification`, `verified`, `unreachable`, `unavailable`:
  while PayWay may legitimately say PENDING there is no verdict (RESULT07 pins the mapping).
- No Billing, grant, polling or PayWay-request change. `Continue` resets the attempt and
  closes the card as `paid`; `Try again` closes the card and re-opens the SAME purchase
  beneath it (the controller's existing `retry`, which starts a fresh attempt when the
  server said the transaction id is spent).
- A verdict never traps the person: the failure card's only action is `Try again`, and
  someone who cancelled on purpose must be able to "return safely" — a tap outside the card
  or Escape closes a verdict (`none`, nothing paid). The confirming card (money moving,
  grant seconds away) cannot be dismissed from outside (`PopScope`). RESULT12 pins both.

## Dynamic values

- Pack line and amount: the server's echo of the ORDER (`payment.credits`,
  `payment.amountLabel`) — pack_10 → "10 spaces / $4.99", pack_30 → "30 spaces / $7.99",
  pack_300 → "300 spaces / $47.99" (RESULT01 ×3).
- New balance: read from the entitlement AFTER a refresh triggered by the card itself
  (collapsing with the controller's own refresh on GRANTED); a dash until that answer
  arrives, never the pack added to a remembered figure (RESULT05: server 25, pack 10 →
  card says 25; RESULT06: dash until the re-read completes).

## Tests (payment suite 78; whole suite 1478 → see gates)

RESULT01 (×3 packs) · RESULT02 (failed / cancelled / expired) · RESULT03 (retired copy gone
from every locale and the sheet, no balance pill) · RESULT04 (no ABA / PayWay / KHQR, no
method mark, no close glyph: one action) · RESULT05 · RESULT06 · RESULT07 (verdict mapping +
watcher) · RESULT08 (Continue → `paid`, attempt reset) · RESULT09 (Try again → card closed,
same purchase re-opened) · RESULT10 (near-black surface, gold / red edge) · RESULT11 (no
overflow at 390×844 and 1440×900 in en/km/fr) · RESULT12 (verdicts dismissible from outside,
confirming card not). Updated: PAYWAY15/17/23/24, ABA07, ABA09.

## Visual validation without a payment

`lib/dev/pwa_payment_result_preview.dart` is a review harness (not referenced by
`main_pwa.dart`, built separately into `build/preview`): the production `PwaPaymentSheet`
behind `showPwaPaymentReturn`, driven by a fake gateway answering the requested terminal
state and a fake entitlement answering the balance. Captures in
`docs/aba/shots/result-2026-09-08/` at 390×844 and 1440×900: pack_10 / pack_30 / pack_300
success, failed, cancelled (and expired).

## Deploy

PWA preprod only, after green gates. Backend not deployed, production untouched.
