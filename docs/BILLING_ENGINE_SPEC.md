# Billing Engine — Spécification d'architecture (EPIC 1)

> **Statut** : SPEC — aucune ligne de code tant que ce document n'est pas validé.
> **Auteur** : conception conjointe (user + Claude Opus 4.8), méthode « architecture pro d'abord » (identique à Ayden Companion).
> **Date** : 2026-06-30
> **Portée** : le coffre-fort d'Ayden — déterminer à tout instant ce qu'un utilisateur a le droit de faire, à partir d'événements de paiement et de consommation, sans connaître aucun fournisseur de paiement en particulier.
> **V1 impact (pipeline image)** : **NONE**. Cet EPIC est de l'infra monétisation additive et isolée. Il ne touche ni la DNA, ni la preservation, ni la fidelity, ni le composer de prompt. Aucune modification du chemin `/generate` au-delà de **trois points d'insertion** (reserve / commit / release) clairement délimités.

---

## 0 — Position de ce document par rapport à l'existant

Ce document **supersède** le modèle d'« abonnement illimité » (`entitlement_tier` = `free`/`pro`) esquissé dans :

- [`docs/monetization_readiness_audit.md`](monetization_readiness_audit.md) (2026-05-30)
- [`docs/monetization_strategy_revision.md`](monetization_strategy_revision.md) (2026-05-30)

**Ce qui change** : on passe d'un modèle **abonnement illimité** (payer = générations infinies) à un modèle **Pass + quota mesuré** (payer = un nombre fini de générations dans une fenêtre de temps). La consommation est désormais **comptée même pour les utilisateurs payants**.

**Ce qui est réutilisé tel quel** (déjà livré ou déjà conçu) :

| Brique | Statut | Rôle dans le Billing Engine |
|---|---|---|
| Sign-in Apple/Google + identité Supabase persistante | **Livré** (Wave 5.17a) | `user_id` stable, survit au réinstall — socle de tout solde |
| JWT propagé sur `/generate` + vérif ES256/JWKS | **Livré** (Wave 5.17c, voir `wave_5_17c_jwks_es256`) | `user_id` de confiance au site de l'appel payant |
| Validation `session.user_id == jwt.user_id` | **Livré** | empêche le quota-bypass par forge de `session_id` |
| Table `user_roles` (admin / beta_tester / support) | **Conçue** (strategy_revision §5) | bypass admin/QA = pas de consommation de crédit |
| Promo codes (`promo_codes`, `promo_code_redemptions`) | **Conçue** (strategy_revision §6) | un code accorde un Pass ou des crédits via le ledger |
| RevenueCat comme couche IAP mobile | **Décidé** (`paywall_v2_art_direction`, `ayden_studio_strategy`) | source des `Payment` mobiles |

**Ce qui devient un PRÉREQUIS DUR non encore codé** :

| Dépendance | Statut | Pourquoi bloquant |
|---|---|---|
| **Generation Intent v1** (`intent_id` déterministe + persisté, voir [`GENERATION_INTENT_V1_SPEC.md`](GENERATION_INTENT_V1_SPEC.md)) | ✅ **LIVRÉ (PR0→PR4)** 2026-07-01 — hooks `observe_intent_start/end` + réconciliation `reconcile_once()` en prod | la clé d'idempotence de la consommation de crédit EST l'`intent_id` (l'**Intent**, pas le **Job**/exécution technique). Les points de branchement billing existent déjà (voir §4.0). |

---

## 1 — Décisions plateforme paiement *(décision figée)*

### 1.1 — Règle de plateforme

| Plateforme | Fournisseur autorisé | Interdit |
|---|---|---|
| **iOS (app)** | Apple IAP **via RevenueCat** | KHQR/Bakong en paiement direct in-app pour crédits numériques → **rejet App Store §3.1.1** |
| **Android (app)** | Google Play Billing **via RevenueCat** | idem |
| **Web / parcours hors-app** | KHQR / Bakong (ABA) | — |

**Principe** : le contenu numérique consommé dans l'app (les générations) **doit** passer par l'IAP de la plateforme. KHQR reste **dans la vision** mais **jamais dans l'app mobile** tant qu'on est distribué via App Store / Play Store. Le parcours web/KHQR pour le Cambodge est un canal séparé, postérieur, qui alimente le **même** Billing Engine.

### 1.2 — Conséquence architecturale

Le `Payment` est **agnostique du fournisseur**. Il entre dans l'Engine par l'un de deux adaptateurs :

```
RevenueCat webhook (mobile)  ─┐
                              ├─→  Payment normalisé  ─→  Billing Engine
KHQR/Bakong callback (web)   ─┘
```

L'Engine ne connaît ni Apple, ni Google, ni KHQR. Il reçoit un `Payment` normalisé `{order_id, provider, provider_transaction_id, status, amount, currency, raw_payload}` et applique **la même** logique en aval.

### 1.3 — Limite de configurabilité (recadrage MVP)

Le prix réel sur mobile **n'est pas le nôtre** : Apple/Google imposent leurs paliers et prélèvent 15–30 %. Donc :

- ✅ **Configurable en DB** : `product_id`, durée, crédits, mapping fournisseur, `metadata` (hook promo/pays).
- ❌ **PAS de moteur** de pricing multi-pays / promo en V1 (over-engineering + écrasé par les paliers IAP). On garde seulement le *hook* `metadata` JSON pour l'ajouter plus tard sans migration lourde.

Le `price_usd` stocké en DB est **indicatif/affichage** ; la vérité de prix mobile vit chez Apple/Google.

---

## 2 — Modèle Pass × Crédits *(décision figée)*

### 2.1 — Le modèle retenu : « Pass + quota »

| Produit | Prix (réf.) | Durée | Crédits (générations) |
|---|---:|---:|---:|
| **Weekly Pass** | 7,99 $ | 7 jours | 60 |
| **Annual Pass** | 79,00 $ | 365 jours | 300 |
| Pack 10 | 1,99 $ | — | +10 |
| Pack 25 | 3,99 $ | — | +25 |
| Pack 50 | 6,99 $ | — | +50 |
| Pack 100 | 11,99 $ | — | +100 |

> **Note de prix (figé 2026-07-01)** : l'Annual à **79 $ / 300 générations** est figé pour cette spec. Il n'est volontairement **pas** l'équivalent annualisé du Weekly (60/sem × 52 ≈ 3120) : le Weekly cible un usage **intensif court**, l'Annual un usage **longue durée mais moins intensif**. `price_usd` reste **indicatif** ; la vérité de prix mobile vient des paliers stores (probablement 79,99 $). (Confirme la valeur 79 $ ; annule la parenthèse 44 $ précédente.)

### 2.2 — Règles du modèle *(figées)*

1. **Un Pass = fenêtre de temps + quota de générations.** Le Pass accorde son quota par une écriture `GRANT` au ledger, scoppée au Pass.
2. **Les packs ajoutent des générations UNIQUEMENT si un Pass actif existe.** Un pack acheté hors Pass actif est **refusé à l'achat** (côté catalogue : packs masqués sans Pass actif ; côté backend : rejet).
3. **Pass actif mais crédits = 0** → l'utilisateur doit acheter un pack (ou attendre/renouveler). Pas de génération.
4. **Pas de Pass actif** → pas d'achat de pack seul en V1.

### 2.3 — Le gate de génération

```
Génération demandée  (room, design_mode, atmosphere, user_id, intent_id)
        │
        ▼
 Admin / beta_tester ?  ──oui──→  ALLOW (bypass, aucune consommation)   [user_roles]
        │ non
        ▼
 Quota d'essai gratuit restant (TRIAL > 0) ?
        │ oui
        ▼
 Demande DANS le périmètre gratuit ? (voir 2.5)  ──non──→  DENY 402  (paywall : acheter un Pass)
        │ oui
        ▼ (essai valide)  ─→  RESERVE 1 crédit TRIAL (HOLD)  →  Generate
        │
        │ (TRIAL == 0)
        ▼
 Pass actif ?  ──non──→  DENY 402  (paywall : acheter un Pass)   [reason=pass]
        │ oui
        ▼
 Crédits disponibles > 0 ?  ──non──→  DENY 402  (acheter un pack)   [reason=pack]
        │ oui
        ▼
 RESERVE 1 crédit (HOLD)  →  Generate
```

> **Note** : sous Pass actif, le périmètre gratuit (2.5) **ne s'applique plus** — un user payant accède à toutes les rooms/atmosphères. Le périmètre 2.5 ne contraint **que** les générations d'essai.

### 2.4 — Décisions du modèle *(FIGÉES 2026-06-30)*

- **OD-1 — Free tier / essai. ✅ FIGÉE.**
  Essai gratuit = **3 générations** (`TRIAL` grant, distinct des Pass, placé **avant** le check Pass dans le gate 2.3).
  - **Rattachement** : par **compte** dès que l'utilisateur est signé. Avant sign-in, on autorise l'expérience anon/device pour l'UX, mais **le quota final est rattaché au compte dès connexion** (anti-reset par réinstallation — voir 2.6).
  - **Périmètre** : les 3 générations sont limitées au périmètre gratuit défini en **2.5**. Toute room/atmosphère hors périmètre → paywall (402), **sans** consommer de crédit d'essai.

- **OD-2 — Report des crédits au renouvellement. ✅ FIGÉE.**
  **Pas de report.** Chaque Pass a son propre quota. Les crédits d'un pack **expirent avec le Pass actif au moment de l'achat** (scope `pass_id` sur le `GRANT`). Au renouvellement, on repart sur le quota propre du nouveau Pass (`EXPIRE(-reste)` de l'ancien, voir R7).

- **OD-3 — Remboursement / chargeback. ✅ FIGÉE.**
  Écriture `REFUND` négative + `Pass` → `CANCELLED`. Le solde **peut devenir négatif** (assumé, tracé). **Aucune génération possible tant que solde ≤ 0 OU qu'il n'y a pas de Pass actif.**

### 2.5 — Périmètre du free trial *(FIGÉ 2026-06-30)*

Pendant l'essai gratuit, les 3 générations sont utilisables **uniquement** sur :

```
Living Room   +   Eden Design (mode)   +   [ Edenature | Warm Modern | Japanese ]
```

| Dimension | Valeur gratuite | Hors périmètre → |
|---|---|---|
| **Room** | Living Room uniquement | toute autre room → paywall (402) |
| **Design / mode** | Eden Design uniquement | tout autre mode → paywall (402) |
| **Atmosphère** | Edenature · Warm Modern · Japanese | toute autre atmosphère → paywall (402) |

Règle produit : une demande d'essai hors `Living Room + Eden Design + {Edenature|Warm Modern|Japanese}` déclenche le paywall **avant** toute réservation de crédit (aucun crédit d'essai consommé pour un refus de périmètre).

> **TODO mapping (implémentation)** : les libellés ci-dessus sont des **noms d'affichage** (rebrand AYDEN Studio). Le gate doit comparer des **IDs canoniques EN** du moteur, jamais les labels localisés (contrainte `room_type_i18n_contract` — router le label localisé droppe le bloc DNA). Avant code : figer la table label→ID (`Eden Design` → `<design_mode_id>`, `Edenature` → `<atmosphere_id>`, `Warm Modern` → `warm_modern`, `Japanese` → `japandi_calm` ?). À reconcilier aussi avec `backend/free_tier.py::FREE_ATMOSPHERES` et `frontend/.../free_tier.dart` (qui valaient `{warm_modern, japandi_calm}` au 2026-06-08) — drift = 402 mismatch.

### 2.6 — Anti-reset de l'essai *(conséquence d'OD-1)*

Le quota d'essai étant **par-compte une fois signé**, le `TRIAL` grant est keyé par `user_id` (compte Supabase persistant, survit au réinstall). L'expérience anon pré-sign-in peut afficher la 1ʳᵉ génération, mais la **comptabilisation définitive** des 3 crédits d'essai se fait sur le compte à la connexion (l'anonymous-upgrade Supabase préserve l'UUID — pas de double-octroi). Empêche le cycle « désinstaller → réinstaller → 3 nouveaux gratuits ».

---

## 3 — Dépendance Generation Intent v1 / idempotence *(prérequis dur)*

### 3.1 — Pourquoi c'est bloquant

La cause racine du double-billing (voir `generation_job_v1_direction`) est qu'**une génération n'a pas d'existence propre** : deux gates (frontend recrée, backend ré-accepte) peuvent produire deux débits pour un seul acte. Le Billing Engine **ne peut pas** être idempotent si la chose qu'il facture n'a pas d'identité stable.

➡️ **L'`intent_id` déterministe + persisté de Generation Intent v1 est la clé d'idempotence de la consommation.** Il doit exister **avant** que le Billing Engine consomme un crédit. On facture l'**Intent** (l'intention), jamais le **Job** (la tentative technique) : 1 Intent = au plus 1 débit, quel que soit le nombre de Jobs.

### 3.2 — Pattern reserve → commit → release

Toute génération suit un cycle à 3 temps, **chacun idempotent par `generation_intent_id`** :

```
1. RESERVE   ledger += HOLD(-1, ref=intent_id, key="hold:<intent_id>")
             └─ ne réussit que si available_balance ≥ 1 (le gate)
                  │
2. Generate (≈70–80 s, peut échouer)
                  │
   ┌──────────────┴───────────────┐
3a. succès                      3b. échec
    COMMIT(ref=intent_id,          RELEASE(+1, ref=intent_id,
            key="commit:<intent_id>")          key="release:<intent_id>")
    → le hold devient consommé     → le crédit réservé est rendu
```

**Garanties** :

- **Intent relancé même `intent_id`** → `HOLD` existe déjà → no-op → **pas de double-débit**.
- **Deux callbacks** (provider ou pipeline) → seconde écriture rejetée par contrainte d'unicité sur `idempotency_key` → no-op.
- **Génération échouée** → `RELEASE` → crédit rendu, l'utilisateur ne paie pas un échec.
- **Génération perdue** (ni commit ni release) → réconciliation auto-release après timeout (voir §8).

### 3.3 — Machine d'état du hold

Un `HOLD` pour un `intent_id` donné est terminé par **exactement un** de `COMMIT` | `RELEASE`, **une seule fois** :

```
            ┌─────────┐  commit  ┌───────────┐
  (aucun) → │  HELD   │ ───────→ │ COMMITTED │  (terminal)
            └─────────┘          └───────────┘
                 │ release
                 ▼
            ┌───────────┐
            │ RELEASED  │  (terminal)
            └───────────┘
```

Règle dure : une fois en état terminal, toute nouvelle écriture terminale pour ce `intent_id` est rejetée (idempotence applicative **+** contrainte DB).

---

## 4 — Data model

> Toutes les tables vivent dans Supabase/Postgres. RLS : un utilisateur ne lit que ses propres lignes (`auth.uid() = user_id`) ; les écritures de ledger/paiement passent par le **service role** uniquement (jamais le client).

### 4.0 — Modèle d'événements *(à lire AVANT les tables)*

**Principe** : le Billing est **orienté événements**, pas orienté tables. Et ce n'est pas une métaphore ici — c'est littéral :

> **`ledger_entries` (§4.5) EST le journal d'événements du domaine crédit** (append-only : une ligne = un événement — `GRANT` / `HOLD` / `COMMIT` / `RELEASE` / `REFUND` / `EXPIRE` / `TRIAL`). Le **`Wallet` (§4.7) est une projection** de ce journal (rejouable). Les autres tables (`orders`, `payments`, `passes`) sont l'**état persisté** des événements d'acquisition. Si les événements sont bons, les tables en sont la **conséquence**.

#### Catalogue d'événements

**Groupe A — Acquisition** (le user obtient des droits) :

| Événement | Déclencheur | Conséquence persistée |
|---|---|---|
| `PurchaseCompleted` | webhook RevenueCat / callback KHQR | `Payment` inséré (idempotent `provider_transaction_id`) · `Order` → `PAID` |
| `PassGranted` | traitement d'un Payment produit=`PASS` | `Pass` créé (`starts_at`/`ends_at`) |
| `CreditsGranted` | traitement Payment (`PASS` ou `CREDIT_PACK`) | ledger **`GRANT(+credits)`** (scoppé `pass_id`) |
| `TrialGranted` | 1ʳᵉ éligibilité free-tier (OD-1) | ledger **`TRIAL(+3)`** |

**Groupe B — Consommation** (ancrée sur le **lifecycle Intent déjà construit**) :

| Événement | Hook **concret** (livré) | Conséquence ledger |
|---|---|---|
| `IntentStarted` | `observe_intent_start` (le claim, [intent_observer.py](../backend/intent_observer.py)) | `reserve` → **`HOLD(-1)`** (échoue si solde insuffisant → **402** avant OpenAI) |
| `IntentSucceeded` | `observe_intent_end(SUCCEEDED)` **OU** repair PR4 ([intent_reconciliation.py](../backend/intent_reconciliation.py)) | `commit` → **`COMMIT`** |
| `IntentFailed` | `observe_intent_end(FAILED/_TERMINAL)` **OU** timeout-fail PR4 | `release` → **`RELEASE(+1)`** |

**Groupe C — Corrections** :

| Événement | Déclencheur | Conséquence |
|---|---|---|
| `RefundReceived` | webhook refund provider | ledger **`REFUND(-x)`** + `Pass` → `CANCELLED` |
| `PassExpired` | sweep expiry (worker) | ledger **`EXPIRE(-reste)`** + `Pass` → `EXPIRED` |

#### Les deux flux

```
FLUX 1 — Acquisition (paiement → droits)
  PurchaseCompleted → PassGranted → CreditsGranted → (Wallet reprojection)

FLUX 2 — Consommation (génération, ancré Intent)
  IntentStarted ── reserve → HOLD(-1) ──┐
                                        │  (solde < 1 → 402, pas de génération)
                                        ▼
                                  [ openai.images.edit ]
                                        │
                        ┌───────────────┴───────────────┐
                  IntentSucceeded                   IntentFailed
                   commit → COMMIT                  release → RELEASE(+1)
```

#### 🔑 Point d'intégration critique (conséquence directe de PR4)

Les effets billing sont pilotés par les **transitions Intent** — qui sont émises à **deux endroits** dans le code livré, pas un seul :

1. **Chemin nominal** : `observe_intent_start` / `observe_intent_end` dans `/generate`.
2. **Réconciliation (PR4)** : `reconcile_once()` transitionne aussi des Intents (**repair → SUCCEEDED**, **timeout → FAILED**).

➡️ **Le Billing doit se brancher aux DEUX.** Un Intent réparé par PR4 (image livrée mais client tué avant `observe_intent_end`) **doit `commit`** le crédit — sinon une génération réussie ne serait jamais facturée. Un timeout-fail **doit `release`**. C'est exactement pourquoi PR4 devait exister **avant** le Billing : il ferme le trou où un débit serait perdu ou orphelin. La logique billing sera donc une fonction pure `apply_billing_for_intent_transition(intent_id, new_status)` appelée par **les deux** émetteurs, idempotente par `intent_id` (clé ledger `hold:/commit:/release:<intent_id>`).

#### Conséquence pour la suite

Les tables ci-dessous (§4.1–4.7) ne sont que la **matérialisation** de ce modèle : `products` (ce qui peut être acquis), `orders`/`payments` (Flux 1 entrant), `passes` (droit temporel), **`ledger_entries` (le journal d'événements lui-même)**, `wallets` (sa projection). On les lit désormais comme *« quel événement écrit/lit cette table ? »*.

---

### 4.1 — `products` *(catalogue — configurable)*

| Colonne | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `sku` | text UNIQUE | `weekly_pass`, `annual_pass`, `pack_10`… |
| `type` | text | `PASS` \| `CREDIT_PACK` |
| `credits_granted` | int | 60, 300, 10, 25, 50, 100 |
| `duration_days` | int NULL | 7, 365 ; NULL pour les packs |
| `price_usd` | numeric | **indicatif** (vérité de prix mobile = stores) |
| `currency` | text | `USD` (défaut) |
| `revenuecat_product_id` | text NULL | mapping IAP |
| `apple_product_id` | text NULL | |
| `google_product_id` | text NULL | |
| `khqr_enabled` | bool | autorisé sur le canal web |
| `metadata` | jsonb | hook promo/pays — **non interprété en V1** |
| `active` | bool | |

### 4.2 — `orders`

| Colonne | Type | Notes |
|---|---|---|
| `id` | uuid PK | exposé comme `ORDER-AAAA-NNNNNN` |
| `user_id` | uuid FK | indexé |
| `product_id` | uuid FK | |
| `status` | text | `PENDING` \| `PAID` \| `FAILED` \| `CANCELLED` \| `REFUNDED` |
| `provider` | text | `revenuecat` \| `khqr` |
| `amount` / `currency` | numeric / text | montant attendu |
| `idempotency_key` | text UNIQUE | dédup création d'ordre |
| `created_at` / `updated_at` | timestamptz | |

### 4.3 — `payments`

| Colonne | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `order_id` | uuid FK | |
| `provider` | text | `revenuecat` \| `khqr` |
| `provider_transaction_id` | text | id transaction côté fournisseur |
| `status` | text | `SUCCESS` \| `FAILED` \| `PENDING` \| `REFUNDED` |
| `raw_payload` | jsonb | payload brut (audit) |
| `received_at` | timestamptz | |
| | | **UNIQUE (`provider`, `provider_transaction_id`)** ← clé d'idempotence paiement |

### 4.4 — `passes`

| Colonne | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid FK | indexé |
| `product_id` | uuid FK | quel Pass |
| `source_order_id` | uuid FK | traçabilité |
| `starts_at` / `ends_at` | timestamptz | fenêtre de validité |
| `status` | text | `ACTIVE` \| `EXPIRED` \| `CANCELLED` |
| | | « actif » dérivé = `status=ACTIVE AND now() BETWEEN starts_at AND ends_at` |

### 4.5 — `ledger_entries` *(cœur — append-only)*

| Colonne | Type | Notes |
|---|---|---|
| `id` | bigint PK (séquence ordonnée) | l'ordre = la vérité |
| `user_id` | uuid FK | indexé |
| `entry_type` | text | `GRANT` \| `HOLD` \| `COMMIT` \| `RELEASE` \| `REFUND` \| `ADJUSTMENT` \| `EXPIRE` \| `TRIAL` |
| `available_delta` | int | effet sur le solde disponible (voir 4.6) |
| `pass_id` | uuid NULL | crédit scoppé à un Pass (expire avec lui) |
| `reference_type` | text | `ORDER` \| `GENERATION_JOB` \| `ADMIN` \| `PROMO` |
| `reference_id` | text | `order_id` ou `generation_intent_id`… |
| `idempotency_key` | text UNIQUE | **anti-doublon dur (contrainte DB)** |
| `created_at` | timestamptz | |
| `metadata` | jsonb | |

**Immutabilité** : aucun `UPDATE`/`DELETE`. Pas de droit `UPDATE/DELETE` accordé même au service role sur cette table (corrections = écriture compensatoire). Règle 3 des principes (« aucun crédit supprimé »).

### 4.6 — Sémantique de `available_delta`

| `entry_type` | `available_delta` | Sens |
|---|---:|---|
| `GRANT` | `+credits` | Pass ou pack accorde des crédits |
| `TRIAL` | `+N` | quota d'essai gratuit (OD-1) |
| `HOLD` | `-1` | réservation d'une génération |
| `RELEASE` | `+1` | annulation d'une réservation (échec) |
| `COMMIT` | `0` | finalisation (le `-1` a déjà eu lieu au `HOLD`) |
| `EXPIRE` | `-reste` | Pass expiré → solde restant remis à zéro |
| `REFUND` | `-x` | remboursement (peut rendre le solde négatif) |
| `ADJUSTMENT` | `±x` | correction support, tracée |

```
available_balance(user) = Σ available_delta de toutes ses écritures
held(user)              = #HOLD − #RELEASE − #COMMIT   (réservations en cours)
consumed(user)          = #COMMIT                       (générations réussies)
```

### 4.7 — `wallets` *(vue matérialisée — cache recalculable)*

| Colonne | Type | Notes |
|---|---|---|
| `user_id` | uuid PK | |
| `available_credits` | int | cache |
| `held_credits` | int | cache |
| `active_pass_id` | uuid NULL | |
| `pass_expires_at` | timestamptz NULL | |
| `ledger_version` | bigint | dernier `ledger_entries.id` appliqué |
| `updated_at` | timestamptz | |

> **Le Wallet n'est PAS la source de vérité.** C'est un cache, **toujours recalculable** par rejeu du ledger. La réconciliation (§8) le compare au ledger et alerte sur dérive. Le gate de génération lit le Wallet (rapide), mais le `HOLD` s'écrit avec une vérification atomique contre le ledger pour éviter les courses.

---

## 5 — Règles métier

**R1 — Le paiement n'accorde jamais directement des crédits.** Il crée une transaction (`Payment`) ; l'Engine la traite ensuite. Ajouter un fournisseur ne change rien à l'aval.

**R2 — Tout mouvement est enregistré.** Jamais `credits = 48` ; toujours une suite d'écritures. Le solde est **toujours explicable**.

**R3 — Aucun crédit n'est supprimé.** Append-only. Remboursement/correction = écriture compensatoire, jamais un `DELETE`.

**R4 — Toute génération suit le gate §2.3** : admin → essai → Pass actif → crédits > 0 → reserve.

**R5 — Tout est idempotent.** Paiement (UNIQUE `provider_transaction_id`) **et** consommation (UNIQUE `idempotency_key` dérivé du `generation_intent_id`). Un second appel ne fait rien.

**R6 — Traitement d'un `Payment` `SUCCESS`** (idempotent par `order_id`) :
- produit `PASS` → créer `Pass` (`starts_at=now`, `ends_at=now+duration`) + `GRANT(credits, pass_id)`.
- produit `CREDIT_PACK` → exiger un Pass actif → `GRANT(credits, pass_id=active_pass)` (hérite de l'expiration du Pass). Sinon : refus (ne devrait pas arriver, packs masqués sans Pass).

**R7 — Expiration de Pass** : sweep périodique → `status=EXPIRED` + `EXPIRE(-reste)` pour les crédits scoppés à ce Pass.

**R8 — Bypass admin/QA** (`user_roles` ∈ {admin, beta_tester}) : ALLOW sans `HOLD`/`COMMIT` (aucune consommation), mais log d'observabilité.

**R9 — Promo** : un code accorde soit un `Pass` (R6 produit PASS) soit un `GRANT(type=PROMO)`, via le ledger. Réutilise `promo_codes` / `promo_code_redemptions` (strategy_revision §6).

---

## 6 — API

> Les endpoints publics sont sous JWT (sauf webhooks, authentifiés par signature). Les opérations reserve/commit/release **ne sont pas** publiques : ce sont des appels **internes** du pipeline de génération.

### 6.1 — Public (JWT)

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/v1/billing/catalog` | produits **filtrés par plateforme** (mobile → IAP ; web → KHQR) ; packs masqués sans Pass actif |
| `GET` | `/v1/billing/wallet` | Wallet courant `{available, held, active_pass, expires_at}` |
| `POST` | `/v1/billing/orders` | (web KHQR) crée un `Order PENDING` + renvoie le payload KHQR |
| `GET` | `/v1/billing/ledger` | (support/debug) écritures paginées de l'utilisateur |

### 6.2 — Webhooks (signature, pas JWT)

| Méthode | Route | Rôle |
|---|---|---|
| `POST` | `/v1/webhooks/revenuecat` | événements RevenueCat (`INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `BILLING_ISSUE`, `EXPIRATION`, `REFUND`) → `Payment` normalisé |
| `POST` | `/v1/webhooks/khqr` | callback Bakong/KHQR → `Payment` normalisé |

### 6.3 — Contrat interne (appelé par le pipeline `/generate`)

```
billing.reserve(user_id, generation_intent_id) -> {ok} | {error: "insufficient_credits"} | {error: "no_active_pass"}
billing.commit(generation_intent_id)           -> idempotent
billing.release(generation_intent_id)          -> idempotent
```

Intégration `/generate` (3 points d'insertion, rien d'autre ne change) :

```
1. (existant) valider JWT → user_id ; valider session.user_id == user_id
2. (NEW) r = billing.reserve(user_id, intent_id)
         si r.error → HTTP 402 {detail, reason, paywall: "pass"|"pack"}
3. (existant) openai.images.edit(...)           ← le cœur, INTOUCHÉ
4. (NEW) succès → billing.commit(intent_id)
         échec  → billing.release(intent_id)
```

---

## 7 — Workflows de paiement

### 7.1 — Achat mobile (RevenueCat — source de vérité backend)

```
App: tap Buy → RevenueCat SDK → feuille Apple/Google → paiement
RevenueCat valide le reçu → webhook → backend
backend /v1/webhooks/revenuecat:
   1. vérifier la signature
   2. upsert Order (idempotent) + insert Payment (UNIQUE provider_transaction_id)
   3. Engine traite (R6) → Pass + GRANT  /  ou GRANT pack
   4. recalcul Wallet
App: l'entitlement client RevenueCat débloque l'UX immédiatement (indice UX),
     mais le backend (ledger) reste la vérité.
```

### 7.2 — Achat web (KHQR / Bakong)

```
Web: choisir produit → POST /v1/billing/orders → Order PENDING + QR KHQR
User: paie via app bancaire
Bakong callback → /v1/webhooks/khqr → Payment (idempotent) → Engine (R6)
Fallback: polling Bakong sur les Orders PENDING (réconciliation §8) si le callback est manqué
```

### 7.3 — Consommation (génération)

Voir §3.2 (reserve → generate → commit/release), clé = `generation_intent_id`.

---

## 8 — Erreurs et réconciliation

### 8.1 — Cas d'erreur

| Cas | Traitement |
|---|---|
| Webhook livré 2× | idempotent (UNIQUE `provider_transaction_id`) → no-op |
| `Payment` pour un `Order` inconnu | log + quarantaine, ne crédite pas ; réconciliation enquête |
| Pack sans Pass actif | refusé à l'achat (catalogue) + rejet backend (R6) |
| Remboursement / chargeback | `REFUND` (négatif) + `Pass` → `CANCELLED` (OD-3) |
| Génération échoue après `HOLD` | `RELEASE` → crédit rendu |
| Génération perdue (ni commit ni release) | auto-`RELEASE` par réconciliation après timeout |
| Crédits insuffisants | 402 `reason=pack` (Pass actif) ou `reason=pass` (pas de Pass) |
| Pass expire **pendant** une génération en vol | le `HOLD` posé alors que le Pass était valide → `COMMIT` autorisé (on ne pénalise pas l'in-flight) |
| Dérive Wallet vs ledger | recalcul depuis le ledger + alerte |

### 8.2 — Workers de réconciliation

1. **Orphan payments** — `Payment SUCCESS` sans `Pass`/`GRANT` → re-traiter (R6).
2. **Stuck orders** — `Order PENDING` > N min → poll provider ; payé → compléter, sinon `EXPIRE`.
3. **Stuck holds** — `HOLD` sans terminal après timeout (Intent crashé/perdu) → auto-`RELEASE` (lié au lifecycle Generation Intent v1).
4. **Wallet drift** — recalcul périodique Wallet ↔ ledger, alerte si écart.
5. **Pass expiry sweep** — `passes` échus → `EXPIRED` + `EXPIRE(-reste)` (R7).

---

## 9 — Tests d'acceptation *(Given / When / Then)*

**AT-1 — Achat Pass crédite le quota.**
Given un user sans Pass · When `Payment SUCCESS` pour `weekly_pass` · Then `Pass ACTIVE` 7 j + `GRANT(+60)` + `wallet.available == 60`.

**AT-2 — Idempotence paiement.**
Given le webhook `weekly_pass` déjà traité · When le même `provider_transaction_id` est rejoué · Then aucune nouvelle écriture, `available` inchangé.

**AT-3 — Idempotence consommation (job relancé).**
Given une génération `job=J` ayant déjà posé `HOLD` · When `reserve(user, J)` est rappelé · Then no-op, un seul `-1` au total.

**AT-4 — Échec de génération rend le crédit.**
Given `HOLD(-1, J)` · When la génération échoue → `release(J)` · Then `available` revenu à sa valeur d'avant, `held == 0`.

**AT-5 — Double callback (commit + commit).**
Given `COMMIT(J)` déjà écrit · When `commit(J)` rappelé · Then no-op (UNIQUE `commit:J`).

**AT-6 — Pack sans Pass refusé.**
Given user sans Pass actif · When achat `pack_25` · Then refus, aucun `GRANT`.

**AT-7 — Crédits = 0 sous Pass actif.**
Given Pass actif, `available == 0` · When génération · Then 402 `reason=pack`.

**AT-8 — Pas de Pass.**
Given aucun Pass actif, essai épuisé · When génération · Then 402 `reason=pass`.

**AT-9 — Bypass admin sans consommation.**
Given `user_roles=admin` · When génération · Then ALLOW, **aucune** écriture ledger.

**AT-10 — Expiration de Pass remet le quota à zéro.**
Given Pass expiré avec 12 crédits restants · When sweep · Then `EXPIRE(-12)` + `Pass EXPIRED` + `available == 0`.

**AT-11 — Remboursement.**
Given Pass actif + 60 crédits · When `REFUND` provider · Then `Pass CANCELLED` + `REFUND` négatif, génération bloquée.

**AT-12 — Wallet recalculable.**
Given une suite d'écritures · When on vide le Wallet et on rejoue le ledger · Then Wallet reconstruit à l'identique (`ledger_version` cohérent).

**AT-13 — Course sur le dernier crédit.**
Given `available == 1`, deux `reserve` concurrents (jobs différents) · When exécutés en parallèle · Then exactement **un** `HOLD` réussit, l'autre 402.

**AT-14 — Free trial dans le périmètre.**
Given `TRIAL == 3`, demande `Living Room + Eden Design + Warm Modern` · When génération · Then ALLOW, `HOLD` sur crédit TRIAL, `TRIAL` restant == 2.

**AT-15 — Free trial hors périmètre (aucun crédit consommé).**
Given `TRIAL == 3`, demande `Bedroom` (ou atmosphère non gratuite) · When génération · Then 402 `reason=pass`, **`TRIAL` reste == 3** (refus de périmètre avant toute réservation).

**AT-16 — Trial rattaché au compte (anti-reset).**
Given un anon ayant consommé 2 crédits TRIAL puis se signant (anonymous-upgrade, même UUID) · When il génère · Then `TRIAL` restant == 1 (pas de ré-octroi de 3) ; un réinstall + nouveau sign-in sur le même compte → toujours le même compteur.

---

## 10 — Sécurité

| # | Surface | Mesure |
|---|---|---|
| S1 | Webhooks | **Vérification de signature** obligatoire (RevenueCat signing, Bakong). Réutiliser la discipline JWKS/ES256 (`wave_5_17c_jwks_es256`) — ne jamais faire confiance à un callback brut. |
| S2 | Idempotence | Contraintes **DB** `UNIQUE` (pas seulement logique applicative) : `payments(provider, provider_transaction_id)`, `ledger_entries(idempotency_key)`. |
| S3 | Entitlement | **Serveur = vérité.** Jamais croire un client « je suis premium » ; l'entitlement RevenueCat côté client n'est qu'un **indice UX**. Le gate lit le ledger/Wallet backend. |
| S4 | Immutabilité ledger | Aucun `UPDATE`/`DELETE` (droits DB révoqués). Corrections par écriture compensatoire. |
| S5 | Autorisation | RLS : un user ne lit que **son** Wallet/ledger. Écritures via service role uniquement. |
| S6 | Quota-bypass | `user_id` de confiance au site `/generate` (JWT ES256) + `session.user_id == jwt.user_id` (déjà livré). Le quota est **par-user serveur**, jamais par-session client. |
| S7 | Rejeu | Protection anti-rejeu sur les callbacks (timestamp + signature + dédup `provider_transaction_id`). |
| S8 | Rate limiting | Sur `/v1/billing/orders` et les webhooks. |
| S9 | Données sensibles | Stocker `provider_transaction_id` + payload minimal ; **jamais** de données carte (gérées par le fournisseur). |
| S10 | Audit | Chaque écriture = `reference` + `idempotency_key` + timestamp + payload fournisseur. Toute opération est rejouable et explicable. |

---

## 11 — Récapitulatif des décisions *(toutes FIGÉES 2026-06-30)*

| ID | Sujet | Décision figée |
|---|---|---|
| **OD-1** | Essai gratuit | 3 générations, `TRIAL` grant par-**compte** (anon pré-sign-in mais quota rattaché au compte à la connexion), avant le check Pass, **borné au périmètre 2.5** |
| **OD-1b** | Périmètre du free trial | `Living Room` + `Eden Design` + `{Edenature \| Warm Modern \| Japanese}` ; tout le reste → paywall sans consommer de crédit |
| **OD-2** | Report des crédits au renouvellement | **Pas de report** ; pack expire avec le Pass actif à l'achat ; renouvellement = quota propre neuf |
| **OD-3** | Remboursement / chargeback | `REFUND` négatif + `Pass CANCELLED` ; solde négatif autorisé ; aucune génération si solde ≤ 0 ou pas de Pass actif |

---

## 12 — Ordre d'implémentation *(figé 2026-06-30)*

| # | Chantier | Pourquoi cet ordre | Statut |
|---|---|---|---|
| 1 | **Generation Intent v1** (`intent_id` déterministe + persisté, [`GENERATION_INTENT_V1_SPEC.md`](GENERATION_INTENT_V1_SPEC.md)) | Prérequis dur §3 — la clé d'idempotence de la consommation | ✅ **LIVRÉ (PR0→PR4)** 2026-07-01 |
| 2 | **Billing Engine** (data model §4 + ledger + reserve/commit/release + webhooks normalisés) | Le coffre-fort lui-même, une fois l'`intent_id` disponible | Cette spec |
| 3 | **RevenueCat mobile** (SDK + `/v1/webhooks/revenuecat` + catalogue IAP) | Premier canal de paiement réel (mobile-first) | À faire |
| 4 | **UX wallet / paywall** (affichage solde, Pass, expiration ; paywall sur 402 `reason=pass\|pack`) | S'appuie sur le Wallet (§4.7) + les 402 du gate | À faire |
| 5 | **KHQR web** (canal hors-app + `/v1/webhooks/khqr`) | Plus tard — n'impacte pas la review App Store ; même Engine en aval | Différé |

---

*Spec rédigée par Claude Opus 4.8 (1M). Aucun code, aucun commit — référence unique pour l'implémentation du Billing Engine. Prérequis dur : Generation Intent v1 (`intent_id`). Décisions OD-1/2/3 + périmètre free trial + ordre d'implémentation figés le 2026-06-30.*
