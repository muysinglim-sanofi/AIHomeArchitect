# Captures ABA — ce qui est dans le dépôt et ce qui ne l'est pas

Toutes les captures de ce dossier sont des écrans Ayden Studio ou des écrans PayWay
**sandbox**, pris par le pilote CDP (`docs/round3-final/cdp.mjs`). Aucune ne montre de
PIN, de mot secret, d'écran de connexion, de numéro de téléphone ni d'adresse e-mail
(revue image par image le 2026-09-07 avant le commit de gel).

## Conservées hors dépôt (public)

Les captures suivantes affichent un **QR KHQR sandbox complet et scannable**. Un KHQR
encode les identifiants du compte marchand sandbox (et, pour les captures du 05/09, le
nom marchand alors enregistré chez ABA). Elles restent sur le poste du product owner et
dans les archives de revue ; les rapports qui les citent restent valables, la carte KHQR,
le nom « Ayden Studio » et le montant étant décrits dans le texte.

| Fichier | Rapport qui le cite |
|---|---|
| `E-modal.png` | `ABA_UI_PREPROD_2026_09_04.md` |
| `e2e/B-aba-checkout-mobile.png`, `e2e/B2-aba-checkout-tall.png` | `ABA_POST_WHITELIST_RETEST_2026_09_07.md` |
| `e2e/H-close-test-aba-sheet.png`, `e2e/K-payment-aba-sheet.png`, `e2e/M-desktop-1440-aba-checkout.png` | `ABA_POST_WHITELIST_RETEST_2026_09_07.md`, `ABA_PREPROD_FINAL_ACCEPTANCE_2026_09_07.md` |
| `final/H-wallet-mobile-modal.png`, `final/I-modal-closed.png` | `ABA_FINAL_IMPLEMENTATION_2026_09_05.md` |
| `phase0/A-khqr-340.png`, `A-khqr-360.png`, `A-khqr-390.png`, `A-khqr-420.png`, `B-qrpage-340.png`, `B-qrpage-390.png` | `PHASE0_SPIKE_2026_09_05.md` |
| `phone/E-wallet-modal.png` | (non citée) |
| `../../preprod/iframe-khqr-only.png` | `REJECTED_AI_GENERATED/README.md` |
| `review-2026-09-08/D1-mobile-plugin-sheet.png`, `review-2026-09-08/D2-desktop-plugin-popup.png` | `ABA_REVIEW_FIX_2026_09_08.md` |

Également hors dépôt : les journaux CDP bruts `evidence/netlog-*.jsonl` (URLs de session
checkout sandbox), remplacés par `evidence/e2e_network_2026_09_07.txt` (assaini), et les
copies de code tiers ABA (`checkout.prod.js.pretty.txt`, `aba_official_sample.html`).

## Marques ABA / KHQR

Depuis le 2026-09-08, `web/aba/` ne contient plus que les deux SVG **officiels** fournis
par ABA lors de la revue marchand (copies pristines dans `docs/aba/official/`). Les
rendus générés utilisés pour la première revue préprod ont été retirés de l'UI active ;
leur historique reste dans `REJECTED_AI_GENERATED/README.md`. Les captures antérieures
au 2026-09-08 montrent donc l'ancienne marque.

## Revue ABA round 2 (2026-09-08) — copie PayWay retirée, libellé « Payment method »

Hors dépôt : les deux captures desktop prises pendant que le popup ABA était ouvert
(QR KHQR sandbox scannable, transaction annulée ensuite). Les captures conservées dans
`shots/copy-2026-09-08/` (Wallet mobile/desktop, ligne d'état, carte de verdict) ne
contiennent aucun QR.
