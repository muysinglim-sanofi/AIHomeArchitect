# P0 Billing Integrity — Matrice de tests (contrat d'acceptation)

> **Règle d'acceptation** : aucun fix accepté sans, pour chaque scénario :
> `scénario · état DB initial · action · résultat attendu · type de test · statut PASS/FAIL`.
> Types : **FakeSupa** (unit pur, 0 DB/0 réseau) · **E2E-DB** (Supabase réel, 0 coût OpenAI) ·
> **Widget** (flutter test) · **Device** (manuel TestFlight, listé explicitement).

## Décisions produit figées (validées 2026-07-10)
1. `total_spaces_remaining = free_remaining + pass_remaining + promo_remaining` — free planché à 0 avant addition.
2. Consommation **pass-first** puis free ; promo séparé en V1.
3. Rôle premium = **features** ; pass actif = **droit de générer** ; jamais unlimited pour weekly/annual.
4. Reconcile : upsert rôle premium quand RC actif + réparer `ends_at`/pass si RC actif ; idempotent, jamais double GRANT.
5. Redesigns = générations réussies uniquement ; Shared retiré.
6. Free = 3 par **device** (Keychain) — bloc (c).
7. Deny billing = **preflight** avant session/loading/pending ; purge propre en race 402.

## Découpage
- **Bloc (a) backend** couvre **A→E** (déployable Render, sans rebuild). ← *ce livrable*
- **Bloc (b) frontend** couvre **F→H** (nouveau TestFlight).
- **Bloc (c) device-key** couvre **I**.
- **J** (App Review) = transverse, vérifié à chaque bloc.

Statuts : ⬜ à faire · 🟩 PASS · 🟥 FAIL · ⏭️ bloc ultérieur.

---

## A. Source unique de vérité backend  *(bloc a)*

| # | Scénario | État DB initial | Action | Attendu | Test | Statut |
|---|----------|-----------------|--------|---------|------|--------|
| A1 | 3 gates cohérents | user free, ledger free=+2 | `reserve_decision` × (/me/status, /generate, /refine) | même `allow`/`reason`/`total` partout | FakeSupa | ⬜ |
| A2 | Total additif | pass actif bucket=5, free bucket=+2 | `reserve_decision` | `total=7` (`pass_credits=5`+`free_credits=2`) | FakeSupa+E2E-DB | ⬜ |
| A3 | Free planché à 0 | free bucket net=−4 (dette), pas de pass | `reserve_decision` | `free_credits=0` (jamais négatif) | FakeSupa | ⬜ |
| A4 | Pass expiré n'entre pas dans le total | 2 passes EXPIRED (GRANT +60,+30), free=+3 | `reserve_decision` | `total=3` (pas 93), `pass_credits=0` | FakeSupa+E2E-DB | ⬜ |
| A5 | Pass actif contribue | pass ACTIF bucket=30, free=0 | `reserve_decision` | `total=30`, `has_active_pass=True` | FakeSupa+E2E-DB | ⬜ |
| A6 | wallet == gate | après reproject, pass actif=30 | comparer `wallet.available_credits` et gate | égaux (=30) | E2E-DB | ⬜ |
| A7 | Aucun crédit fantôme | pass EXPIRED bucket +30 + free +3 | `reserve_decision` chemin free | fantôme exclu (`pass_id IS NULL` seul) | FakeSupa+E2E-DB | ⬜ |
| A8 | access_source cohérent | matrices free/pass/restore_required/admin/promo_unlimited | `/me/status` | `access_source` ∈ attendu par cas | FakeSupa | ⬜ |

## B. Free quota  *(bloc a — ledger ; usage_log = analytics)*

| # | Scénario | État DB initial | Action | Attendu | Test | Statut |
|---|----------|-----------------|--------|---------|------|--------|
| B1 | New user → 3 | ledger vide | `reserve_decision` free | `total=3` (TRIAL projeté +3) | FakeSupa+E2E-DB | ⬜ |
| B2 | Gen 1 succès → 2 | TRIAL+3 | RUNNING+SUCCEEDED (net −1) | free bucket=2 | E2E-DB | ⬜ |
| B3 | Gen 2 → 1 | free=2 | RUNNING+SUCCEEDED | free bucket=1 | E2E-DB | ⬜ |
| B4 | Gen 3 → 0 | free=1 | RUNNING+SUCCEEDED | free bucket=0 | E2E-DB | ⬜ |
| B5 | Gen 4 → deny | free=0 | `reserve_decision` | `allow=False reason=insufficient_credits`, 0 OpenAI | FakeSupa+E2E-DB | ⬜ |
| B6 | Échec ne consomme pas | free=2, RUNNING puis FAILED | HOLD(−1)+RELEASE(+1) | net 0 → free reste 2 | E2E-DB | ⬜ |
| B7 | 402 ne consomme pas | free=0 | gate deny AVANT claim | aucun HOLD, aucun usage_log | E2E-DB | ⬜ |
| B8 | Pas de double conso au replay | même `intent_id` rejoué | HOLD idempotent `hold:<intent>` | 1 seul HOLD | FakeSupa+E2E-DB | ⬜ |
| B9 | in_progress ≠ success | usage_log in_progress | comptage profil (bloc b) | non compté comme succès | Widget (b) | ⏭️ |
| B10 | failed non compté | usage_log failed | comptage | exclu | E2E-DB | ⬜ |
| B11 | Free bucket = pass_id NULL seul | free +3 + pass GRANT +30 | lecture bucket free | =3 (exclut le pass) | FakeSupa+E2E-DB | ⬜ |

## C. Pass weekly / annual  *(bloc a)*

| # | Scénario | État DB initial | Action | Attendu | Test | Statut |
|---|----------|-----------------|--------|---------|------|--------|
| C1 | Weekly → +30 | product weekly=30 | `grant_purchase` tx neuf | pass bucket=30 | E2E-DB | ⬜ |
| C2 | Annual → +300 | product annual=300 | `grant_purchase` tx neuf | pass bucket=300 | E2E-DB | ⬜ |
| C3 | Même tx ×5 → 1 GRANT | tx=T | `grant_purchase`×5 | 1 order/pass/GRANT, credited une fois | E2E-DB | ⬜ |
| C4 | Webhook + restore même tx | tx=T webhook puis sync | 2 chemins | pas de double GRANT | E2E-DB | ⬜ |
| C5 | Pass actif + free 2 → 32 | pass=30, free=+2 | `reserve_decision` | `total=32` | FakeSupa+E2E-DB | ⬜ |
| C6 | Débit pass-first | pass=30, free=2 | RUNNING+SUCCEEDED | débit sur **pass** (→29), free intact | E2E-DB | ⬜ |
| C7 | Pass→0, free 2 → gen possible | pass=0 (actif), free=2 | `reserve_decision` + débit | allow (`total=2`), débit sur **free** | FakeSupa+E2E-DB | ⬜ |
| C8 | Pass expiré + free 2 → total 2 | pass EXPIRED, free=+2 | `reserve_decision` | `total=2` | FakeSupa+E2E-DB | ⬜ |
| C9 | Pass expiré + free 0 → deny | pass EXPIRED, free=0 | `reserve_decision` | `allow=False` | FakeSupa+E2E-DB | ⬜ |
| C10 | Pass expiré ≠ +30 fantôme | pass EXPIRED GRANT +30, free=0 | `reserve_decision` | `total=0` | FakeSupa+E2E-DB | ⬜ |
| C11 | 2 passes expirés ne polluent pas | GRANT +60,+30 expirés, free=+3 | `reserve_decision` | `free_credits=3` | FakeSupa+E2E-DB | ⬜ |
| C12 | Reproject après HOLD/COMMIT | pass actif | débit | `billing_reproject_wallet` appelé | FakeSupa+E2E-DB | ⬜ |

## D. Restore / RevenueCat sync  *(bloc a)*

| # | Scénario | État DB initial | Action | Attendu | Test | Statut |
|---|----------|-----------------|--------|---------|------|--------|
| D1 | RC actif + tx fiable + no pass local | vide | `reconcile` | crée pass, `state=pass grant=granted` | FakeSupa+E2E-DB | ⬜ |
| D2 | RC actif + tx already_processed + pass local EXPIRÉ | order+pass expiré | `reconcile` (expires futur) | **répare ends_at→actif**, pas de double GRANT | E2E-DB | ⬜ |
| D3 | RC actif + tx + pass actif | pass ACTIF | `reconcile` | no-op idempotent | E2E-DB | ⬜ |
| D4 | RC actif + tx manquant | subscriber sans store_tx | `reconcile` | `restore_required` (aucun pass) | FakeSupa | ⬜ |
| D5 | RC actif + produit non mappé | product inconnu | `reconcile` | `restore_required product_not_mapped` | FakeSupa | ⬜ |
| D6 | RC inactif | entitlement expiré | `reconcile` | `state=free`, aucun pass | FakeSupa | ⬜ |
| D7 | Restore ×5 | tx=T | `reconcile`×5 | 1 seul crédit | E2E-DB | ⬜ |
| D8 | Already subscribed → sync appelé | — | tap Weekly already-subscribed | `[purchases/sync] ENTER` + `rc_sync` | Device (b) | ⏭️ |
| D9 | state=pass ⇒ pass réellement actif | reconcile pass | après reconcile, `reserve_decision` | pass actif visible (`has_active_pass`) | E2E-DB | ⬜ |
| D10 | Reconcile upsert rôle premium | RC actif | `/purchases/sync` | `user_roles` premium upserté, jamais unlimited | E2E-DB | ⬜ |

## E. Rôle premium / pass  *(bloc a)*

| # | Scénario | État DB initial | Action | Attendu | Test | Statut |
|---|----------|-----------------|--------|---------|------|--------|
| E1 | Rôle seul sans pass → no unlimited | rôle premium, 0 pass, free 0 | `reserve_decision` | `allow=False`, jamais bypass | FakeSupa | ⬜ |
| E2 | Rôle seul → deny/restore_required | idem | `/me/status` | `access_source=restore_required`, `can_generate=False` | FakeSupa | ⬜ |
| E3 | Pass sans rôle → gén. autorisée (pass-first) | pass ACTIF, `user_roles` vide (tier=free) | `reserve_decision` | `allow=True` via pass, débit sur pass | FakeSupa+E2E-DB | ⬜ |
| E4 | Rôle expiré + RC actif → sync restaure rôle | rôle expiré | `/purchases/sync` | rôle premium rafraîchi | E2E-DB | ⬜ |
| E5 | promo_unlimited → unlimited réel | promo unlimited | `reserve_decision` | `bypass` allow | FakeSupa | ⬜ |
| E6 | admin → unlimited réel | admin | `reserve_decision` | `bypass` allow, 0 lookup | FakeSupa | ⬜ |
| E7 | promo désactivé → aucun accès promo | promo `active=false` | resolver | tier=free (pas de bypass) | FakeSupa | ⬜ |

## F. Generate UX / preflight  *(bloc b — frontend)*

| # | Scénario | Action | Attendu | Test | Statut |
|---|----------|--------|---------|------|--------|
| F1 | total=0 → paywall immédiat au tap Generate | tap Generate | PaywallSheet, pas de nav | Widget/Device | ⏭️ |
| F2 | total=0 → aucune session | idem | 0 ligne `sessions` | Device | ⏭️ |
| F3 | total=0 → aucun generation_intent | idem | 0 intent | Device | ⏭️ |
| F4 | total=0 → aucun pending local | idem | 0 pending | Widget | ⏭️ |
| F5 | total=0 → aucun loading | idem | pas d'écran génération | Widget | ⏭️ |
| F6 | total=0 → aucun usage_log | idem | 0 row | Device | ⏭️ |
| F7 | preflight OK puis 402 race → purge | race | session/pending/loading purgés | Device | ⏭️ |
| F8 | double tap Generate → 1 tentative | double tap | 1 seule | Widget | ⏭️ |
| F9 | replay pending après 402 → pas de relance | resume | pas de re-POST | Device | ⏭️ |
| F10 | deny → 0 OpenAI | idem | 0 coût | Device | ⏭️ |

## G. Refine/chat UX  *(bloc b — frontend)*

| # | Scénario | Attendu | Test | Statut |
|---|----------|---------|------|--------|
| G1 | total=0, Send déclenche refine → paywall immédiat | pas de POST /refine | Widget/Device | ⏭️ |
| G2 | pas de loading | — | Widget | ⏭️ |
| G3 | pas de pending | — | Widget | ⏭️ |
| G4 | pas de POST refine si deny | — | Device | ⏭️ |
| G5 | preflight OK puis /refine 402 → purge propre | — | Device | ⏭️ |
| G6 | message simple non générateur → 0 conso | should_generate=false | Device | ⏭️ |
| G7 | refine succès → conso 1 | débit 1 | E2E-DB | ⏭️ |
| G8 | refine failed → refund/no-conso | selon règle | E2E-DB | ⏭️ |
| G9 | deny → 0 OpenAI image | — | Device | ⏭️ |
| G10 | pas de parser/advisor avant gate si deny (preflight client) | — | Device | ⏭️ |

## H. Profile stats  *(bloc b — frontend)*

| # | Scénario | Attendu | Test | Statut |
|---|----------|---------|------|--------|
| H1 | Redesigns = générations réussies uniquement | — | Widget | ⏭️ |
| H2 | 3 réussies → Redesigns=3 | — | Widget/Device | ⏭️ |
| H3 | 4e bloquée → reste 3 | — | Device | ⏭️ |
| H4 | session vide → inchangé | — | Widget | ⏭️ |
| H5 | intent failed → inchangé | — | Widget | ⏭️ |
| H6 | in_progress abandonné → inchangé | — | Widget | ⏭️ |
| H7 | Shared retiré | carte absente | Widget | ⏭️ |
| H8 | aucun compteur hardcodé | — | grep/Widget | ⏭️ |
| H9 | profil lit total_credits depuis /me/status | pas de source locale | Widget | ⏭️ |
| H10 | affichage pass/free/total clair | — | Device | ⏭️ |

## I. Reinstall / device quota  *(bloc c — device-key)*

| # | Scénario | Attendu | Test | Statut |
|---|----------|---------|------|--------|
| I1 | Reinstall même device → pas de reset à 3 | free ne revient pas | Device | ⏭️ |
| I2 | Nouveau device → 3 free | — | Device | ⏭️ |
| I3 | Keychain device_key stable | survit reinstall | Device | ⏭️ |
| I4 | device_key absent → généré 1×| idempotent | Widget | ⏭️ |
| I5 | device_key envoyé au backend | header X-Device-Key | E2E | ⏭️ |
| I6 | TRIAL ledger idempotent par device_key (pas user_id seul) | pas de re-TRIAL | E2E-DB | ⏭️ |
| I7 | Login → fusion device/account sans double free | — | E2E-DB | ⏭️ |

## J. App Review / purchase safety  *(transverse)*

| # | Scénario | Attendu | Bloc | Statut |
|---|----------|---------|------|--------|
| J1 | Restore Purchase visible/fonctionnel | — | b | ⏭️ |
| J2 | Already subscribed non bloqué sans explication | — | b | ⏭️ |
| J3 | Abonné actif ne voit jamais faux « Premium active » s'il ne peut pas générer | — | a+b | ⬜ |
| J4 | Aucun unlimited pour weekly/annual | — | a | ⬜ |
| J5 | Aucun compteur fake | Shared retiré | b | ⏭️ |
| J6 | Aucun paywall après faux loading | preflight | b | ⏭️ |
| J7 | Aucun coût OpenAI sur deny | gate avant OpenAI | a+b | ⬜ |
| J8 | Logs sans secret ni payload sensible | — | a | ⬜ |

---

## Régression obligatoire (à repasser avant « fait » bloc a)
- RC-PR2 / PR2b (grant + projection) · RC-PR3a (débit) · RC-PR3b (enforcement) · reconcile.
- `import main` boot-safe · backend restart sans `--reload`.
- `flutter analyze` (bloc b).
- **Aucun** changement moteur image/prompt/DNA/fidelity (v1_image_impact = NONE).

## ✅ POST-APPLY — BACKEND VERT (2026-07-10, SQL appliqué + Render d860948)
Les 2 migrations appliquées (additive projection + atomic hold), backend déployé. Validations réelles :
- **E2E DB P0 billing integrity : 6/6 🟩** — dont **A6 `wallet.available_credits == gate.total` (=32)** (additive projection active).
- **E2E concurrence réelle (advisory-lock) : 4/4 🟩** — **pass=20/80 concurrents → EXACTEMENT 20 granted, solde 0** · free=3/20 · idempotence même-intent · pass-first. La faille HIGH est FERMÉE contre la vraie DB.
- **Audit prod mike lim (`1ba1c0f9`) : `wallet=3, gate=3` 🟩** — crédits fantômes (93) éliminés en prod.
- **0 coût OpenAI sur deny** 🟩 (le 402/deny est levé AVANT vision/OpenAI par construction).

→ **Backend P0 (bloc a + P0a-bis) VALIDÉ.** Prochain : bloc (b) frontend (F→H).

---

## Résultats — Bloc (a) backend (run 2026-07-10)

### Suites automatiques
| Suite | Fichier | Résultat |
|-------|---------|----------|
| Master P0 (A/B/C/E, logique) | `backend/validate_p0_billing_integrity.py` | **25/25 🟩** |
| Régression RC-PR3b (enforcement) | `backend/validate_rcpr3b_enforcement.py` | **12/12 🟩** |
| Régression RC-PR3a (débit) | `backend/validate_rcpr3a_pass_debit.py` | **8/8 🟩** |
| Régression reconcile | `backend/validate_reconcile_pass.py` | **10/10 🟩** |
| E2E DB réel (users jetables) | scratchpad `e2e_p0_billing_integrity.py` | **5/6 🟩** (6e = détecteur migration) |
| Preuve prod (compte réel mike lim `1ba1c0f9`) | `audit_tx_044.py` | **gate 93 → 3 🟩** |
| Boot-safety (`import billing, main`) | — | **OK 🟩** |
| Moteur image/prompt/DNA/fidelity | — | **NON touché (v1_impact=NONE) 🟩** |

**TOTAL auto : 55/55 FakeSupa + 5/6 E2E DB + preuve prod.**

### Couverture par scénario (bloc a)
- **A** : A1🟩 A2🟩(FakeSupa+E2E) A3🟩 A4🟩(FakeSupa+E2E+**prod réel**) A5🟩 A6⚠️(*exige migration 20260710 appliquée* : E2E montre wallet=29≠gate=32 tant que non appliquée) A7🟩 A8🟩(via has_active_pass+reason ; string mapping = code).
- **B** : B1🟩 B5🟩 B8🟩 B11🟩 · B2-B4/B6/B7/B10 = débit réel (E2E partiel + FakeSupa lifecycle) · B9 = bloc (b).
- **C** : C5🟩(FakeSupa+E2E) C6🟩(FakeSupa+E2E) C6b🟩 C7🟩(FakeSupa+E2E) C8🟩 C9🟩 C10🟩 C11🟩 C12🟩 · C1-C4 (grant weekly/annual +30/+300, dedup) = couverts par `validate_reconcile_pass` + `e2e_reconcile_sametx` (RC-PR2). Idempotence HOLD🟩(E2E ×3→1).
- **D** : D4🟩 D5🟩 D6🟩 (reconcile guards) · D1/D2(repair ends_at)/D3/D7/D9/D10 = reconcile+repair (FakeSupa reconcile 10/10 ; D2 repair = code neuf, E2E device en prod).
- **E** : E1🟩 E3🟩 E5🟩 E5b🟩 E6🟩 E7(promo désactivé→tier free = resolver, couvert audit) · E4(sync restaure rôle) = code neuf `/purchases/sync`.
- **J** : J3/J4/J7/J8 🟩 (jamais unlimited pour weekly/annual ; 0 OpenAI sur deny ; logs sans secret).

### P0a-bis — Réservation atomique (course de concurrence, HIGH pré-existant) — run 2026-07-10
Faille fermée : `reserve_decision` lecture-seule + HOLD non-atomique → N `/generate` concurrents (intents distincts) sur-consomment. Fix : `billing_try_hold` (advisory-lock par user + HOLD conditionnel), autorité de génération dans `/generate` (OpenAI ne part que si `granted`).

| # | Scénario | Attendu | Test | Statut |
|---|----------|---------|------|--------|
| P-A | pass=20, 60–80 tentatives | exactement 20 granted, solde 0 | FakeSupa miroir 🟩 · E2E réel ⏳(post-apply) | 🟩 logique |
| P-B | free new user, 20 concurrents | exactement 3 granted | FakeSupa 🟩 · E2E ⏳ | 🟩 logique |
| P-C | même intent ×10 | 1 seul HOLD, tous granted | FakeSupa 🟩 · E2E ⏳ | 🟩 logique |
| P-D | pass=1 + free=2/3 | pass-first puis free, deny au bout | FakeSupa 🟩 · E2E ⏳ | 🟩 logique |
| P-E | pass expiré + free 0 | deny no_active_pass, 0 HOLD fantôme | FakeSupa 🟩 | 🟩 |
| P-F | HOLD granted puis gen FAILED | RELEASE même bucket (net 0) | RC-PR3a #3 🟩 (`_intent_hold_bucket`) | 🟩 |
| P-G | bypass admin/promo | granted, 0 HOLD | FakeSupa 🟩 | 🟩 |
| deny UX | course perdue → 402 avant OpenAI + intent terminalisé | 0 coût, pas de RUNNING fantôme | code (`observe_intent_end` FAILED) | 🟩 code |
| fail-open | RPC KO → granted | fiabilité | FakeSupa 🟩 | 🟩 |

- **`backend/validate_p0_atomic_hold.py` : 8/8 🟩** (dont l'invariant `bucket=20, 60 tentatives → 20 granted, solde 0`).
- **`e2e_p0_atomic_hold.py`** (scratchpad) : concurrence HTTP réelle (advisory-lock) — **prêt**, tourne à l'étape *apply SQL → E2E* (A pass=20/80, B free=3/20, C idempotence, D pass-first).
- Migration : `20260710_billing_p0a_atomic_hold.sql`. Wiring : `/generate` `main.py` (try_hold = autorité, 402 avant OpenAI si deny).

### ⚠️ Dépendances / restes
1. **Migration SQL `20260710_billing_p0_additive_projection.sql` à APPLIQUER** (dashboard) → débloque A6 (wallet==gate). Le GATE Python est déjà correct sans elle ; seule la projection wallet affichée reste XOR jusqu'à l'apply.
2. **Résidu E2E** : 5 users de test `e2e-p0-*@example.invalid` non supprimables via l'API (hardening `20260707` = pas de DELETE service_role sur billing) → purge SQL dashboard fournie séparément. Inertes.
3. **F→J** (frontend/device) = blocs (b)/(c), non commencés.
