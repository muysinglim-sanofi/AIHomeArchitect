# Official ABA artwork — as supplied

Received from ABA's merchant-review team on 2026-09-08, in the review feedback
for `https://preprod.aydenstudio.com`. Kept here byte for byte; the served
copies under `web/aba/` are identical (checked by hash in the test suite).

| File here | Served as | What it is |
|---|---|---|
| `ABA BANK.svg` (40×40) | `web/aba/aba_khqr_payment_option.svg` | ABA's payment-option tile — shown beside "ABA KHQR" in the Wallet |
| `abakhqr-we-accept.svg` (72×20) | `web/aba/abakhqr-we-accept.svg` | The "We accept" lockup (ABA tile + KHQR tile, no words) — shown in the site footer |

ABA's reference for the payment option reads:

```
ABA KHQR
Scan to pay with any banking app
```

These files supersede the generated PNG stand-ins that were authorised for the
first preprod review only (`docs/aba/REJECTED_AI_GENERATED/README.md`). Do not
edit, recolour, or redraw them; if ABA supplies new artwork, replace the files.
