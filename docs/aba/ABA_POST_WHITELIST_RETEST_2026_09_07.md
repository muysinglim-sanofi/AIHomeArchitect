# ABA PayWay — retest bout en bout après whitelist — PRÉPROD / SANDBOX

Date : 2026-09-07 (UTC). Périmètre : validation uniquement. Aucune modification de
comportement produit, de sémantique Billing, de prix, de production.

Environnement : `https://preprod.aydenstudio.com` (Firebase `ayden-studio-preprod`),
API `ayden-api-staging.fly.dev` (Fly `ayden-api-staging`), Supabase staging
`eedcahzekpgxvvfxufbk`, PayWay **sandbox** (`checkout-sandbox.payway.com.kh`),
plugin officiel `https://checkout.payway.com.kh/plugins/checkout2-0.js?hide-close=2`,
`payment_option=abapay_khqr`.

Deux navigateurs pilotés par CDP, chacun avec son propre profil (donc son propre
utilisateur anonyme Supabase) :

| Instance | UA | Viewport | Utilisateur | Solde initial |
|---|---|---|---|---|
| Mobile | iPhone (iOS 17.5) | 390×844 | `…f5cb4b` | `credits_available: 1` |
| Bureau | Windows / Chrome 152 | 1440×900 | `…a242eb` | 1 vision gratuite |

## 1. Whitelist — Error Code 6 résolu

| Avant (2026-09-05) | Après (2026-09-07) |
|---|---|
| POST `purchase` depuis le navigateur → « Requested Domain is not in whitelist » [Error Code 6] | POST `purchase` (iframe du plugin) → 302 → `GET /checkout/<token>` 200 → sheet/popup KHQR « Ayden Studio 4.99 USD » |
| Check Transaction : `envelope=6 'tran_id not found'` | Check Transaction : `envelope='00' 'Success!' payment_status='PENDING' code=2 amount=4.99` |

## 2. Transactions de ce tour (toutes sandbox, pack_10 = 10 Spaces, 4.99 USD)

| tran_id | Instance | Rôle | Création (UTC) | Check Transaction ABA | État final rail | Commande | GRANT |
|---|---|---|---|---|---|---|---|
| `A200c5a239fd27081140` | mobile | 1ʳᵉ création post-whitelist, laissée expirer | ~05:5x | `00` PENDING code 2 | **EXPIRED** (via `restore()` au rechargement) | CANCELLED | 0 |
| `A883bf3bbd1033a06317` | mobile | §8 fermer sans payer, puis « Annuler ce paiement » | 06:22:49 | `00` PENDING code 2 (avant et après fermeture) | **CANCELLED** | CANCELLED | 0 |
| `Ab5f73e6a390aa3e8b08` | mobile | QR transmis au product owner, non scanné ; expiration chronométrée en direct | 06:25:59 | `00` PENDING code 2 (même après notre expiration) | **EXPIRED** à 06:56:03 (navigateur pollant, 452 checks) | CANCELLED | 0 |
| `A2f03c07eefe8285e794` | bureau | §12 popup bureau, ✕ puis « Annuler ce paiement » | 06:35:38 | `00` PENDING code 2 | **CANCELLED** | CANCELLED | 0 |
| `A9503c856b1c453648ed` | bureau | §12 second cycle, annulation souris-seule | 06:39:13 | `00` PENDING code 2 | **CANCELLED** | CANCELLED | 0 |

Autorité = Check Transaction ABA + ledger (`orders`, `ledger_entries` GRANT), jamais
l'UI. Aucune ligne `payments`, aucune ligne GRANT n'existe pour ces deux utilisateurs
au moment de la rédaction (`ledger_check.py` : « user's last GRANT rows (any order): 0 »).

## 3. Preuve « transaction créée » (§3 de la demande)

Pour `A883bf3bbd1033a06317`, dans l'ordre :

1. `POST /pwa/staging/payments/checkout/plugin` → 200 (le serveur signe, aucun secret côté navigateur ; champs : `req_time, merchant_id, tran_id, amount, type, currency, lifetime, payment_gate, payment_option=abapay_khqr, return_url, return_params, hash` + `is_plugin_js=true` ajouté par le plugin).
2. `AbaPayway.checkout()` → iframe `aba_webservice` (390×577, `allow="payment *"`), parent `#aba_checkout_app`, sheet mobile `display:flex`.
3. Iframe : `POST checkout-sandbox…/api/payment-gateway/v1/payments/purchase` → 302 → `GET /checkout/<token>` 200.
4. Ligne rail `AWAITING_PAYMENT`, `checkout_mode=plugin`, `expires_at = +30 min`.
5. Check Transaction : `envelope='00' payment_status='PENDING' code=2 amount=4.99`.

Preuve réseau assainie : `evidence/e2e_network_2026_09_07.txt` (méthode/hôte/chemin/frame/statut ; pas de corps, pas d'en-têtes, tokens masqués ; **aucun hôte de production** dans les quatre journaux).

## 4. Cadence de polling (Check Transaction mandatory)

Le journal réseau n'a pas d'horodatage ; la cadence est mesurée sur `check_count`
(chaque poll frontend déclenche un Check Transaction serveur) :

| Fenêtre (tran `A883…`) | Δ checks | Δ temps | Période |
|---|---|---|---|
| 06:23:36 → 06:24:40 | 12 → 28 | 63,4 s | 3,96 s |
| 06:24:40 → 06:25:15 | 28 → 37 | 35,7 s | 3,97 s |

Conforme à la consigne ABA (~3 s puis 3–5 s). Le poll s'arrête sur état terminal
(36 polls au total pour `A883…`, aucun après l'annulation).

## 5. §8 — Fermer sans payer (mobile)

Séquence réelle (captures `H-close-test-aba-sheet.png` → `I-close-test-after-close.png` → `J-close-test-after-cancel.png`) :

1. Wallet → 10 Spaces → Buy → **seule** surface visible = sheet ABA officielle ; Wallet inchangé derrière (pas de modale Ayden).
2. Tap sur l'overlay → la sheet glisse hors écran ; Wallet intact, CTA grisé, ligne inline « Vérification de votre paiement avec ABA PayWay… » + lien « Annuler ce paiement ».
3. Autorité après fermeture : rail `AWAITING_PAYMENT`, ABA `00 PENDING`, **GRANT = 0**.
4. Tap « Annuler ce paiement » → `POST …/order/<tran>/cancel` 200 → rail **CANCELLED**, commande CANCELLED, **GRANT = 0**, polling arrêté.
5. Wallet à nouveau utilisable : CTA « Acheter · $4.99 » actif, plus de ligne inline.

Le journal montre parfois **deux** `POST …/cancel` pour un seul geste. **PREUVE que
c'est le harnais, pas le produit** : le pilote CDP envoie souris **et** touch pour un
« click » ; avec un clic souris-seul (second cycle bureau) le compteur passe de 2 à 3,
soit exactement un POST. Le contrôleur n'émet qu'un appel par `cancel()` et l'API n'a
aucun retry (`pwa_payment_controller.dart`, `pwa_generation_api.dart`). Le serveur est
idempotent (une seule transition CANCELLED) — un double-tap réel serait donc inoffensif.

## 6. §9 — Chemin échoué/expiré

Reproduit sans simulateur : `A200c5a239fd27081140` laissée sans scan au-delà de
`expires_at`. Constat : **l'expiration est paresseuse** — la ligne reste
`AWAITING_PAYMENT` tant qu'aucun `verify_and_settle` n'est appelé (navigateur mort =
plus de poll). Au rechargement, `restore()` l'a évaluée → **EXPIRED**, commande
CANCELLED, 0 GRANT. Pas de grant fantôme, pas d'état bloqué côté Wallet.
Aucune modification demandée ; à garder pour B2 (un balayage serveur des lignes
ouvertes périmées serait un ajout, pas une correction).

**Expiration chronométrée en direct** (`Ab5f73e6a390aa3e8b08`, navigateur vivant qui
pollait) : émission 06:25:59 → `EXPIRED` à 06:56:03, soit `expires_at` + 4 s, après
452 Check Transaction ; commande CANCELLED, 0 GRANT. Le polling s'arrête net : le
compteur de requêtes `GET …/order/<tran>` du journal reste figé (434) sur trois relevés
après l'expiration. Côté Wallet : la sheet ABA (« Session Expired ») reste affichée
tant que la personne ne la ferme pas ; dessous, CTA actif et ligne inline « Ce code a
expiré » (captures `P-…`, `Q-…`).

Constat pour B2 : **ABA répond encore `00 PENDING` après notre expiration** (sa propre
durée de vie n'est pas alignée sur la nôtre). Un paiement scanné tardivement sur un QR
que nous considérons expiré arriverait par pushback ; ce cas « paiement après
expiration » doit être arbitré dans B2 (rembourser, créditer, ou aligner les durées).
Rien de changé ici.

## 7. §10 — Faux positif NOT_CREATED (30 s)

`A200…` : à +68 s toujours `AWAITING_PAYMENT` avec Check Transaction `00 PENDING` ;
`A883…`, `Ab5f…`, `A2f0…`, `A950…` : idem à +60 s et au-delà. La règle NOT_CREATED
(envelope 6 au-delà de 30 s) ne s'est **jamais** déclenchée depuis la whitelist.
Aucun faux positif.

## 8. Captures

Mobile (390×844, UA iPhone) :

| Fichier | Contenu |
|---|---|
| `shots/e2e/G-after-close-no-pay.png` | Profil, « Acheter des Spaces » (état de départ) |
| `shots/e2e/H-close-test-aba-sheet.png` | Sheet ABA KHQR officielle au-dessus du Wallet |
| `shots/e2e/I-close-test-after-close.png` | Wallet derrière, intact, après fermeture sans payer |
| `shots/e2e/J-close-test-after-cancel.png` | Wallet après « Annuler ce paiement », CTA actif |
| `shots/e2e/K-payment-aba-sheet.png` | QR du paiement `Ab5f…` transmis pour le scan |
| `shots/e2e/L-aba-session-expired-5min.png` | Page hébergée ABA à ~5 min : « Session Expired / Try Again » |
| `shots/e2e/P-mobile-after-timed-expiry.png` | À 06:56, après EXPIRED côté rail : sheet ABA toujours affichée |
| `shots/e2e/Q-mobile-wallet-after-timed-expiry.png` | Sheet fermée : Wallet actif, ligne « Ce code a expiré » |
| _à compléter_ | carte succès + Wallet mis à jour après scan |

Bureau (1440×900, Chrome Windows) :

| Fichier | Contenu |
|---|---|
| `shots/e2e/M-desktop-1440-aba-checkout.png` | Popup ABA centré (`aba-checkout-desktop`) au-dessus du Wallet |
| `shots/e2e/N-desktop-1440-after-close.png` | Wallet intact après ✕ + confirm, sans rechargement |
| `shots/e2e/O-desktop-1440-after-cancel.png` | Wallet après « Annuler ce paiement », CTA actif |

## 9. §12 — Bureau 1440×900 (fait, seconde instance Chrome)

Preuve DOM après Buy : `pluginLoaded=true`, formulaire `target=aba_webservice`,
`payment_option=abapay_khqr`, `is_plugin_js=true`, hash présent ;
`#aba-checkout.aba-checkout-desktop` `display:block`, `z-index 99999`, iframe
`aba_webservice` 391×577 `allow="payment *"` ; sheet mobile `display:none` ;
`body overflow-y: hidden` pendant le popup.

Fermeture ✕ : `confirm("Are you sure you want to close?")` → accepté → conteneur
`display:none`, iframe détruite, `overflow-y` restauré, **1 seul chargement de
document** avant comme après (pas de `location.reload()`, effet de `hide-close=2`).
Puis « Annuler ce paiement » → CANCELLED, 0 GRANT. Deux cycles complets
(`A2f0…`, `A950…`).

## 10. Gates (rejouées en début de tour, inchangées)

| Gate | Résultat |
|---|---|
| `flutter analyze` | 0 issue |
| `flutter test` | 1456 pass |
| seam `pwa_staging_payments_test.py` | 234 assertions |
| rail `payway_adapter_test.py` | 99 assertions |
| `flutter build web` | OK |
| `pwa_secret_scan.py` | 11 PASS, 0 LEAKS (seule URL verbatim autorisée : le loader du plugin) |

Aucun fichier produit modifié pendant ce tour (seuls le pilote CDP
`docs/round3-final/cdp.mjs`, la documentation et les preuves ont changé).

## 11. Note de production ABA — contrainte B2, rien changé

ABA (Telegram) : « In production we can whitelist one request/payment domain and one
callback domain ». Conséquence à intégrer dans B2, **sans action maintenant** :

- un seul domaine d'où le navigateur poste `purchase` → `app.aydenstudio.com` (pas de
  preview channels Firebase en prod, pas de `*.web.app`) ;
- un seul domaine de callback (pushback) → `api.aydenstudio.com` ;
- préprod et prod ne peuvent pas partager les mêmes identifiants marchand (les
  whitelists diffèrent) : `fly.prod.toml` n'a toujours pas `PAYWAY_PAYMENT_OPTION`
  (signalé, non modifié).

## 12. Autres observations (aucune action)

- **Page hébergée ABA : « Session Expired » après ~5 min** alors que notre transaction
  vit 30 min (`PAYWAY_QR_LIFETIME_MINUTES`) et reste PENDING chez ABA. « Try Again »
  réaffiche le QR de la **même** transaction (aucune nouvelle ligne rail, Check
  Transaction identique). Un utilisateur lent voit donc cet écran ABA, pas un écran
  Ayden ; comportement cohérent, à documenter pour le support.
- Résidu UX : après une transaction EXPIRED, rouvrir le Wallet affiche encore
  « Ce code a expiré » sous le CTA jusqu'au prochain Buy. Le CTA reste actif, le nouveau
  Buy repart de zéro. À arbitrer plus tard, pas un bloqueur.
- La page hébergée PayWay charge `google-analytics` / `googletagmanager` dans
  l'iframe (côté ABA, hors de notre contrôle).

## 13. Ce qui n'a PAS été fait

- B2 non démarré ; identifiants production non activés ; aucun `git push`.
- Aucune modification de `frontend/lib/**`, `frontend/ios/**`, production, DNS.
- Paiement sandbox : le QR transmis (`Ab5f…`) n'a pas été scanné et a expiré à 06:56.
  **Le scan humain reste à faire** : un nouveau Buy (10 Spaces) émet une nouvelle
  transaction en quelques secondes ; le QR de la page ABA expire toutes les ~5 min
  (Try Again le réaffiche), la transaction vit 30 min.
