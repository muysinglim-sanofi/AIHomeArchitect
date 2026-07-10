# RC-PR3b — Enforcement du pass mesuré (le rôle premium n'est plus l'autorité de génération)

**Décision produit (2026-07-10, Option A validée) :**

```
premium role      = features premium SEULEMENT (all rooms/styles, HD, no watermark, refine…)
pass actif        = droit de générer X spaces (weekly=30, annual=300), mesuré
admin             = illimité réel
promo unlimited   = illimité réel
```

Un acheteur weekly/annual ne doit **JAMAIS** être en illimité, et l'afficheur (profil)
et l'enforcement doivent lire **la même source** : le bucket wallet du pass actif.

## Le trou corrigé (avant RC-PR3b)

`/generate` a une seule porte : `billing.reserve_decision`. Elle faisait
`if not is_free → allow (bypass)`. Or un rôle premium ⇒ `tier="premium"` ⇒
`consumes_free_quota=False` ⇒ **bypass illimité**. Le pass était débité (RC-PR3a)
mais **ne bloquait jamais** → illimité + désynchro possible sous 0.

## Règle RC-PR3b

`reserve_decision(user_id, is_free, tier)` — après le résolveur d'accès :

| Cas | Décision |
|---|---|
| `is_free=True` (free) | inchangé (bucket free + TRIAL, RC-PR2b) |
| `tier ∈ {admin, promo_unlimited, promo_limited}` | `allow` (bypass — illimité réel, ou promo métré par le resolver) |
| `tier=premium` **+ pass actif** | **gate sur le bucket du pass** : `allow = Σ(available_delta où pass_id=actif) ≥ 1` ; sinon `deny reason=pass_exhausted` |
| `tier=premium` **sans pass actif** (ni admin/promo) | **état incohérent** → `log.error` + `deny reason=no_active_pass` (JAMAIS unlimited silencieux) |

- **Source unique** : le gate lit `Σ ledger_entries.available_delta où pass_id = pass actif`
  = exactement ce que `billing_reproject_wallet` projette en `wallet.available_credits`
  (lu par `/me/status` → profil). Display == enforcement.
- **Aucune gen ne démarre à 0** : le gate est PRE-HOLD (avant le claim), lecture seule.
- **FAIL-OPEN** sur hoquet DB (fiabilité > double rare) : un payant n'est jamais bloqué
  par une erreur de lecture (`reason=fail_open`).

## Débit (RC-PR3a — inchangé)

`apply_billing_for_intent_transition(is_free=False)` : si pass actif → HOLD(−1)/COMMIT(0)/
RELEASE(+1) scoppés au `pass_id`. Succès = −1, échec = net 0. Bucket free pré-achat
(pass_id NULL) n'entame jamais le pass. **On ne touche pas.**

## /refine

Ajout d'un gate `reserve_decision` **avant** `_run_generation` (même source que /generate) :
un pass à 0 ne peut pas refine non plus. Le **débit** refine reste OFF (Phase 1) — la
question « refine consomme-t-il un space ? » est un point produit séparé.

## /purchases/sync & webhook

- **Webhook** `INITIAL_PURCHASE`/`RENEWAL` → pass + GRANT + rôle premium (features). `EXPIRATION`
  → révoque le rôle (déjà en place). Inchangé.
- **`/purchases/sync`** grant le rôle (features) mais **ne peut pas** créer un GRANT/pass sans
  `transaction_id` fiable du cycle → il **loggue clairement** `active subscription but no
  measurable pass` (à réconcilier via webhook/restore). Pas de GRANT arbitraire.
- Conséquence enforcement : un compte « rôle premium sans pass » (ex. sync-sans-webhook) tombe
  dans le cas *incohérent* → `deny` (pas unlimited). Le webhook/restore réconcilie le pass.

## États d'unlimited RÉEL

Seuls **admin** et **promo_unlimited** restent illimités. Un compte de test/legacy voulu
illimité doit être **admin** (ou promo_unlimited), pas un rôle `premium` nu.

## Acceptance

- Weekly actif 30 spaces → gen OK → 29 (affichage + enforcement).
- Wallet pass = 0 → gen **bloquée avant OpenAI**, paywall (`error_code=QUOTA_EXHAUSTED`,
  `reason=pass_exhausted`, `paywall=pass`).
- Refine à 0 → bloqué.
- Admin / promo_unlimited → illimité.
- Free → free x3 → paywall (inchangé).
- Bucket free négatif pré-achat ne réduit pas le pass (RC-PR2b).
- Rôle premium sans pass → deny + log error (jamais unlimited silencieux).
- Restore Purchase → pass mesuré ou log incohérence, jamais unlimited.

## Hors-scope v1 (points produits séparés)

- Refine qui **consomme** un space (aujourd'hui : gate à 0 mais pas de débit).
- Réconciliation d'un pass **depuis `/purchases/sync`** (aujourd'hui : log only ; le webhook crée le pass).
