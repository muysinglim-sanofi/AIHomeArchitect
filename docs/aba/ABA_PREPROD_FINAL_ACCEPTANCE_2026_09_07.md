# ABA PayWay — Acceptation finale PRÉPROD — 2026-09-07

**Statut : ABA PAYWAY PREPROD INTEGRATION = ACCEPTED / FROZEN.**

Périmètre : PWA web uniquement (`ayden-pwa-web`, branche `pwa-web-ios-alignment`),
API staging Fly `ayden-api-staging`, Supabase staging `eedcahzekpgxvvfxufbk`, PayWay
**sandbox**. Aucune production, aucun argent réel, aucun push, aucun code produit
modifié pendant la validation.

Ce qui est gelé (identité du déploiement) :

| Élément | Identité |
|---|---|
| PWA préprod (Firebase `ayden-studio-preprod`, canal live) | release 2026-09-06 15:30:33Z, `main.dart.js` SHA-256 `e551706e…`, 3 881 753 octets |
| API staging (Fly `ayden-api-staging`) | release **v10**, 2026-09-06 15:24:35Z |
| Arbres de travail | aucun fichier de `lib/`, `web/`, `test/`, `tool/` ni `backend/*.py` postérieur aux déploiements : le déployé = l'arbre sur disque |
| Dépôts | derniers commits 2026-08-28 (`e1161dd` PWA, `665485d` backend) ; **le travail plugin ABA est NON COMMITÉ** dans les deux dépôts (voir §L) |

Méthode : preuves rejouées par cinq agents indépendants (preuve DB/PayWay, sémantique
des soldes, rejeu d'idempotence, régression UX, gates) puis recomptage indépendant et
contrôles sécurité effectués à la main. Autorité = base staging + Check Transaction
PayWay, jamais l'interface.

## A. Architecture

```
Navigateur (PWA Flutter web, preprod.aydenstudio.com)
  │  Buy (Wallet)
  ├─► POST /pwa/staging/payments/checkout/plugin ── API staging (Fly) ──► signe HMAC-SHA512
  │        ◄─ champs signés (req_time, merchant_id, tran_id, amount, …, hash)   (secret serveur seulement)
  │  pont JS `aydenAbaCheckout` : formulaire caché  target="aba_webservice"
  ├─► AbaPayway.checkout()  (plugin officiel checkout2-0.js, chargé depuis checkout.payway.com.kh)
  │        └─ le PLUGIN crée l'iframe `aba_webservice` et poste `purchase` vers PayWay sandbox
  │           mobile : sheet `bs.js` · bureau : `#aba-checkout.aba-checkout-desktop`
  │        ◄─ page KHQR hébergée par ABA (QR, montant, marchand)
  │  poll GET /pwa/staging/payments/order/{tran}  toutes les ~3–4 s
  └──────────────────────────────────────────────► verify_and_settle (serveur)
                                                     ├─ Check Transaction PayWay (AUTORITÉ)
                                                     ├─ APPROVED → billing_grant_purchase (RPC atomique, idempotent)
                                                     │              → order PAID + payment SUCCESS + pass + ledger GRANT + wallet
                                                     └─ vue publique → état `granted` → carte succès, Wallet/Profil
Pushback ABA signé (sonnette) et restore() au rechargement appellent le même verify_and_settle.
```

Règles gelées : le serveur signe, le navigateur poste ; Check Transaction seule autorité ;
un grant par transaction garanti côté serveur (garde d'état `pwa_staging_payments.py:720`
+ clés d'idempotence du RPC) ; Option B (QR serveur + modale compacte) dormante et
conservée ; aucune surface Ayden pendant le checkout.

## B. Flux plugin officiel ABA

1. Wallet → pack → Buy → `start(sku)` → `POST …/checkout/plugin` (`pwa_paywall.dart:513`).
2. Ligne rail `AWAITING_PAYMENT`, `checkout_mode=plugin`, `payment_option=abapay_khqr`
   (fail-closed 503 si autre valeur, `pwa_staging_payments.py:1008-1017`), lifetime 30 min,
   URLs de retour vides, loader `?hide-close=2`.
3. Pont JS (`web/index.html:62-97`) → `AbaPayway.checkout()` → iframe du plugin →
   `POST purchase` (302) → `GET /checkout/<token>` → page KHQR.
4. Poll ~3–4 s → Check Transaction serveur ; APPROVED → grant → `granted` → carte succès
   (watcher `pwa_experience.dart:134-165`), Wallet/Profil rafraîchis.
5. Fermeture sans payer : mobile = overlay ; bureau = ✕ → `confirm` → masqué. Ligne inline
   « Annuler ce paiement » → `POST …/cancel` → CANCELLED.

## C. Preuve du paiement sandbox réussi

Paiement effectué manuellement par le product owner (ABA Simulator, son téléphone,
utilisateur anonyme `…c0e5a0`). Seule transaction émise sur 3 h.

| Élément | Valeur (staging) |
|---|---|
| `tran_id` | `A245c9c2fb4d52444f9c` |
| Ligne rail | `GRANTED`, `checkout_mode=plugin`, `check_count=4`, `callback_count=1` (signature OK) |
| SKU / crédits | `pack_10` / 10 (product `2cad28ea-…`) |
| Montant | 4.99 USD, identique sur rail, order, payment et PayWay |
| `payment_option` | `abapay_khqr` (`fly.toml:94` + `GET /pwa/staging/payments/config` live) |
| Order canonique | `f5d5321e-684e-4ea5-bfba-9124b8506e3d`, **PAID**, provider `khqr`, clé `order:khqr:A245c9c2fb4d52444f9c` |
| Payment | `d55897bf-bdd4-4123-b76d-ad75ed77bf99`, **SUCCESS**, `provider_transaction_id` = tran |
| Ledger | **1** ligne GRANT (id 983), `available_delta +10`, clé `grant:order:<order_id>`, `pass_id 6ea16be1-…` |
| Pass | ACTIVE, `source_order_id` = order, `ends_at 2999-12-31` (pack = perpétuel) |
| Wallet | `available_credits 10`, `held 0`, `active_pass_id` = pass, `ledger_version 983` |
| Atomicité | payments.received_at = ledger.created_at = orders.updated_at = passes.created_at = wallets.updated_at = 09:02:23.473169Z (un seul RPC) |

Timing (horodatages base) :

| Étape | Instant (UTC) | Δ |
|---|---|---|
| Création (`created_at`) | 09:02:03.879 | — |
| Champs émis (`qr_issued_at`) | 09:02:04.063 | +0,18 s |
| Transaction PayWay (`transaction_date`, ICT) | 16:02:06 ≈ 09:02:06Z | ≈ +2 s (indice) |
| Pushback signé reçu | 09:02:21.855 | +17,8 s |
| APPROVED vu (`last_checked_at`, 4ᵉ check) | 09:02:22.526 | +18,6 s |
| Grant (ledger / order / payment / pass / wallet) | 09:02:23.473 | +0,95 s après APPROVED |
| `granted_at` | 09:02:23.530 | +19,65 s bout en bout |

Cadence de poll : 3 000 ms configurés (`pwa_staging_payments.py:400`), mesurée ~3,9 s ce
matin sur `check_count`. Instant du 1ᵉʳ check et espacement exact : **non prouvables** (non
persistés, buffer Fly limité) ; lecture la plus cohérente = 3 polls navigateur + 1 check
forcé par le pushback. Rafraîchissement client : observé par le PO (« 10 Spaces »), non
mesuré.

## D. Preuve Check Transaction APPROVED

`checktx.py A245c9c2fb4d52444f9c`, rejoué 3 fois de plus pendant la validation :
`envelope='00' 'Success!' payment_status='APPROVED' code=0 amount=4.99 USD`,
`found=True approved=True pending=False`. Prédicat `approved` = `payway.py:985-986`.

## E. Preuve du grant unique (idempotence)

Baseline et après-rejeu **identiques** : 1 order PAID, 1 payment SUCCESS, 1 GRANT +10,
`granted_at` inchangé, `check_count` 4 inchangé, `callback_count` 1 inchangé.

Rejeux effectués sur la ligne réelle :

| Rejeu | Résultat |
|---|---|
| `verify_and_settle(row)` ×3 (chemin poll / restore) | même ligne GRANTED, 0 Check Transaction réel, 0 `grant_purchase` (compteurs pass-through) |
| `verify_and_settle(row, force=True)` ×2 (chemin pushback / cancel) | idem |
| Check Transaction ×3 (lecture) | APPROVED code 0 à chaque fois |
| Pushback non signé ×2 (`POST …/payway/callback` avec seul `tran_id`) | **401 BAD_SIGNATURE** avant toute lecture/écriture ; signature non forgée |
| Recomptage indépendant (script distinct) | 1 GRANT, wallet 10, ledger_version 983 |

Garanties de code : garde d'état `if state == GRANTED: return row`
(`pwa_staging_payments.py:720-721`, avant rate-limit, Check Transaction et `_grant`) ;
`restore()` ne sélectionne que les états OPEN (`:258-271`) ; RPC `billing_grant_purchase`
avec order `on conflict (idempotency_key)`, payment `UNIQUE(provider, provider_transaction_id)`,
pass `UNIQUE(source_order_id)`, ledger `grant:order:<order_id>` `ON CONFLICT DO NOTHING`
(migration `20260709_billing_pr2b…sql:123-176`). Tests : ABA04/ABA10/ABA11/PLUGIN13/ABA18.
Le paiement réel a déjà exercé les deux chemins concurrents (pushback signé à 09:02:21.85 +
polls) → un seul grant.

Lacune assumée : la branche `already_processed` du RPC n'a pas été exercée à chaud sur cette
transaction (un appel direct écrirait `orders.updated_at`) ; couverte par lecture de code et
tests à moteur simulé.

## F. Soldes avant / après — explication autoritaire (1 vs 10)

| Question | Réponse prouvée |
|---|---|
| « 1 vision gratuite » avant achat | **Une projection, pas une ligne du ledger** : `_free_bucket_available` ajoute `effective_trial_credits()` = 1 (mode `ACCOUNT_SYSTEM_ENABLED=true`, `run_pwa_staging.py:131`) quand aucune ligne TRIAL n'existe **et** `project_trial=True` (`billing.py:343-345`). L'utilisateur `…f5cb4b` avait 0 ligne ledger, 0 wallet, 0 pass et `credits_available=1`. |
| Entitlement séparé des Spaces achetés ? | Oui : bucket free (`pass_id IS NULL` + trial projeté) ≠ bucket pass (Σ deltas du pass actif). La ligne TRIAL n'est **matérialisée** qu'au premier HOLD (RPC `billing_try_hold`, migration `20260717…sql:63-79`). |
| `credits_available` | `free_credits + pass_credits` (`billing.py:554`, `pwa_staging_billing.py:124`). |
| `pass_credits` | Σ `available_delta` des lignes du pass ACTIF (`billing.py:302-320`). |
| `free_remaining` | absent du corps `/pwa/staging/entitlement` (legacy `promo.py`, ne gate rien). |
| Ce que lit le Profil « VOS ESPACES » | `pwaWalletSentence` → toujours `creditsAvailable` (`pwa_profile_ios.dart:365-371`, `pwa_entitlement.dart:276`) ; « 1 vision gratuite » si ≤ 1 en état free, sinon « N Spaces restants ». |
| Solde avant achat (utilisateur neuf) | free 1 (projeté) + pass 0 = **1** |
| Grant acheté | **+10** sur un pass **perpétuel** (`ends_at 2999-12-31`) |
| Solde après achat | free **0** + pass **10** = **10** ; entitlement recalculé par les mêmes fonctions que la route : `access_source='pass'`, `has_active_pass=True`, `watermarked=False`, `credits_available=10` |
| Pourquoi 10 et non 11 | la projection du trial est conditionnée à l'absence de pass actif : `project_trial=(is_free and pass_id is None)` (`billing.py:551-552`, commentaire :548-550) ; le RPC SQL applique la même règle. Les sondes ABA15 attendent déjà `pass_credits == 10`. |

Conclusion : le « 10 Spaces » affiché est **correct au regard du code, du SQL, des sondes et
des données**. Observation produit (aucune modification) : la vision de bienvenue non
utilisée est de fait perdue à l'achat d'un pack perpétuel ; si le produit voulait
« 1 + 10 = 11 », il faudrait matérialiser le TRIAL avant le grant. Décision de sémantique →
B2.

## G. Fermer sans payer

Fait ce jour sur mobile (`A883bf3bbd1033a06317`) et sur bureau (`A2f03c07eefe8285e794`,
`A9503c856b1c453648ed`), rapport `ABA_POST_WHITELIST_RETEST_2026_09_07.md` §5 et §9 :

- seule surface visible = checkout ABA officiel, Wallet inchangé derrière ;
- fermeture → rail `AWAITING_PAYMENT`, ABA `00 PENDING`, **GRANT = 0** ;
- « Annuler ce paiement » → `CANCELLED`, commande CANCELLED, **GRANT = 0**, polling arrêté ;
- Wallet réutilisable, CTA actif, aucune modale Ayden dupliquée, aucun état bloqué,
  aucun trafic production ; le double `POST /cancel` vu dans un journal est un artefact du
  pilote de test (prouvé par un clic souris-seul → 1 POST).

Grant rows pour ces commandes non payées : **0 / 0 / 0**.

## H. NOT_CREATED (preuve existante, non régressée)

- 2026-09-05 : domaine non whitelisté → PayWay « Error Code 6 », Check Transaction
  `envelope 6 'tran_id not found'` → règle NOT_CREATED (au-delà de 30 s sur ligne plugin)
  → `FAILED/NOT_CREATED`, zéro grant, poll stoppé. Rapport `ABA_DOUBLE_MODAL_FIX_2026_09_05.md`.
- 2026-09-07 : jamais déclenchée à tort sur six transactions (dont le paiement réussi).
- Tests ERR01–ERR07 verts dans la suite seam (234 assertions) ; ERR02/03/05/06 côté PWA (58 tests).

## I. EXPIRED (preuve existante, non régressée)

- `A200c5a239fd27081140` : expiration paresseuse évaluée par `restore()` → EXPIRED, commande
  CANCELLED, zéro grant.
- `Ab5f73e6a390aa3e8b08` : expiration chronométrée en direct → EXPIRED à `expires_at` + 4 s
  après 452 checks, zéro grant, polling arrêté net. Rapport post-whitelist §6, captures P/Q.
- Le paiement réussi n'a rien changé au code : aucun fichier produit modifié depuis les
  déploiements ; tests d'expiration inclus dans les gates vertes.

## J. Plugin bureau (1440×900)

`#aba-checkout.aba-checkout-desktop` `display:block` z-index 99999, iframe `aba_webservice`
391×577 créée par le plugin (aucune iframe Ayden), sheet mobile `display:none`, aucun
`PwaPaymentSheet`, Wallet directement derrière, ABA KHQR seule méthode, popup utilisable ;
✕ → `confirm("Are you sure you want to close?")` → masqué **sans rechargement** ; annulation
→ CANCELLED, zéro grant. Deux cycles complets. Captures G = `M-desktop-1440-aba-checkout.png`
(Wallet + popup), `N-…after-close`, `O-…after-cancel`.

## K. Sécurité / isolation (état final vérifié)

| Contrôle | Résultat |
|---|---|
| Identifiants marchand backend-only | lus une fois dans `payway.py:262-263` depuis l'environnement ; `fly.toml` (staging) et `fly.prod.toml` ne contiennent aucun secret (clés listées : PORT, APP_ENV, PAYWAY_ENV/CALLBACK_URL/RETURN_BASE_URL/VIEW_TYPE/PAYMENT_OPTION/CURRENCY, PWA_ALLOWED_ORIGINS…) |
| Fichier d'env | `.env.pwa-staging.local` ignoré (`.gitignore:8`), non suivi ; seuls `.env.example` et `.env.pwa-staging.local.example` sont suivis |
| Bundle web (`build/web`, reconstruit) | 0 occurrence de `hmac`, `sha512`, `api_key`, `merchant_id` ; URL du plugin 1× dans `index.html` seulement ; aucune chaîne JWT ; le littéral `service_role` correspond au garde-fou client qui **refuse** une clé service-role (`pwa_environment.dart:419-421`) |
| Refs projet dans le bundle | staging et production coexistent comme constantes de sélection/garde par hôte (`pwa_environment.dart:34-111`) ; `ayden-build.json` = mode staging ; preuve réseau : aucun hôte de production contacté |
| `pwa_secret_scan.py` | PASS 11, LEAKS 0 (clé ABA absente de git, du bundle, des logs ; dotenv absent du bundle) |
| Check Transaction et grant côté serveur | unique chemin de grant `_grant` → `billing.grant_purchase` (`pwa_staging_payments.py:810,863-923`) ; le client ne poste que checkout/cancel et lit `GET …/order/{tran}` |
| « Success » du popup ne crédite rien | l'état `granted` provient uniquement de la vue publique serveur ; le pont JS ne fait qu'ouvrir le plugin |
| QR client | aucune lib QR dans `pubspec`/`lib` ; rendu serveur `render_khqr_png_b64` 1 seul site d'appel, dans `start_checkout` dormant (test QR07) |
| Production | jamais utilisée : scripts à garde staging-only, `PWA_ALLOWED_ORIGINS` préprod, sandbox PayWay |
| PIN / mot secret ABA Simulator | absent du dépôt et des rapports (grep PIN/secret word/passcode/OTP/password : seule occurrence = « pin » au sens « épinglé ») |
| Preuves dans le dépôt | `docs/aba/evidence/*.jsonl` (05/09) : 0 `hash`/`Authorization`/`access_token`/JWT ; contiennent des tokens de page checkout sandbox expirés (base64 statut+QR), pas des identifiants |

## L. Backlog production / B2 (rien de changé dans cette phase)

1. **Whitelist production ABA (contrainte dure)** : un seul domaine requête/paiement et un
   seul domaine callback. B2 doit choisir explicitement : (1) `app.aydenstudio.com` comme
   domaine de paiement, (2) `api.aydenstudio.com` comme domaine de callback. Pas de preview
   channels Firebase en production.
2. **Approbation tardive après expiration locale** : « Late provider approval after local
   expiry requires explicit reconciliation policy. » ABA répond encore `00 PENDING` après
   notre EXPIRED ; un pushback approuvé tardif n'est pas arbitré.
3. **TTL** : 30 min (`PAYWAY_QR_LIFETIME_MINUTES`) alors qu'ABA recommande 5–15 min et que sa
   page affiche « Session Expired » à ~5 min. Revue en configuration production, ne pas
   changer maintenant.
4. **Sémantique du trial à l'achat** : la vision de bienvenue non utilisée est perdue dès
   qu'un pass existe (10, pas 11). Décision produit à prendre avant lancement.
5. **Commit de gel** : un commit local `freeze(...)` par dépôt (PWA : branche
   `pwa-web-ios-alignment` ; backend : branche `pwa-monetization`) fige l'état accepté ;
   rien n'est poussé tant que le product owner ne l'a pas demandé. Hors de ces commits,
   volontairement : la chaîne « orientation » backend (`pwa_staging_api.py`, `refine/*`),
   la préparation production (`fly.prod.toml`, `run_pwa_prod.py`, `pwa_target_test.py`,
   migrations `2026090*`), et les captures à QR sandbox scannable (voir `shots/README.md`).
6. `fly.prod.toml` sans `PAYWAY_PAYMENT_OPTION` ni identifiants production (volontaire).
7. Observabilité : horodatage par Check Transaction non persisté ; buffer Fly court.
8. Balayage serveur des lignes ouvertes périmées (expiration paresseuse).
9. Cosmétique : « 10 spaces » en minuscule sur la carte pack EN (`pwa_translations.dart:280`) ;
   docstring périmée `pwa_staging_billing.py:408-414` ; résidu « Ce code a expiré » à la
   réouverture du Wallet.

## M. Index des captures et preuves

Note dépôt public : les captures qui montrent un QR KHQR sandbox **scannable** (il encode
les identifiants du compte marchand sandbox) sont conservées hors dépôt ; la liste exacte
est dans `docs/aba/shots/README.md`. Les autres captures ci-dessous sont commitées.

Captures mobile (390×844, UA iPhone), `docs/aba/shots/e2e/` :

| Fichier | Contenu |
|---|---|
| `A-wallet-mobile*.png`, `A2-wallet-10-selected.png` | Wallet, pack 10 sélectionné |
| `B-aba-checkout-mobile.png`, `B2-aba-checkout-tall.png` | Sheet ABA KHQR officielle (A) |
| `H-close-test-aba-sheet.png` → `I-…after-close` → `J-…after-cancel` | Fermer sans payer, annuler |
| `K-payment-aba-sheet.png` | QR officiel PayWay (A) |
| `L-aba-session-expired-5min.png`, `P-…`, `Q-…` | Session Expired ABA, expiration chronométrée |
| `E-wallet-after-expiry.png`, `F-sheet-before-close.png`, `G-after-close-no-pay.png` | états intermédiaires |

Captures bureau (1440×900) : `M-desktop-1440-aba-checkout.png` (G/H demandées),
`N-desktop-1440-after-close.png`, `O-desktop-1440-after-cancel.png`.

Preuves B (confirmation ABA Simulator), C (reçu ABA −4.99 USD), D (Success PayWay),
E (état succès Ayden), F (Profil « 10 Spaces ») : **observées et détenues par le product
owner** (paiement fait sur son téléphone) ; non jointes à cette session. À déposer dans
`docs/aba/shots/e2e/owner/` sans PIN ni identifiant visible. Leur équivalent autoritaire
est la base : wallet 10, pass ACTIVE, entitlement `credits_available=10`.

Preuves texte : `docs/aba/evidence/e2e_network_2026_09_07.txt` (réseau assaini, 4 journaux,
aucun hôte de production), `checkout.prod.js.pretty.txt`, `aba_official_sample.html`,
rapports `ABA_POST_WHITELIST_RETEST_2026_09_07.md`, `ABA_DOUBLE_MODAL_FIX_2026_09_05.md`,
`ABA_PLUGIN_PREPROD_2026_09_05.md`.

## N. Gates finales (toutes exit 0)

| Gate | Résultat |
|---|---|
| `flutter analyze` | 0 issue (Flutter 3.41.9) |
| `flutter test` | 1456 pass, 0 fail |
| `flutter test test/features/pwa/pwa_payment_test.dart` (pont plugin, DM/ERR/PAY) | 58 pass |
| `bash tool/build_pwa.sh staging` | OK, `build/web`, mode staging, dotenv retiré, aucun déploiement |
| `pwa_staging_payments_test.py` (seam) | 234 assertions |
| `payway_adapter_test.py` (rail) | 99 assertions |
| `pwa_staging_billing_contract_test.py` (contrat Billing, base staging réelle) | 115 checks, 0 failure |
| `pwa_staging_billing_test.py` (enforcement Billing) | 81 assertions |
| `pwa_staging_payway_db_test.py` (rail sur base staging réelle) | 39 checks, 0 failure |
| `pwa_secret_scan.py` (après build) | PASS 11, LEAKS 0 |

## O. Condition de gel

Toutes les vérifications requises passent. **ABA PAYWAY PREPROD INTEGRATION = ACCEPTED /
FROZEN.** Interdits jusqu'à approbation du product owner : démarrer B2, activer des
identifiants marchand production, changer les domaines production, changer le TTL, supprimer
le code Option B, modifier iOS natif, effectuer une nouvelle transaction sandbox payante.
