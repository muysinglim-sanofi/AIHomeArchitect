# PATCH 3 — Re-parent d'un pass entre identités : DESIGN CORRIGÉ (2026-07-17)

## 0. Statut
**INERTE. NE PAS ACTIVER.** Flag `BILLING_REPARENT_ENABLED` = **OFF** (défaut). Migration
`20260717_billing_reparent_pass.sql` **NON appliquée**. Aucune donnée modifiée. Ce document + le
code + les tests constituent la *reconception* demandée ; l'activation reste bloquée jusqu'à la
capture RC (§5) et un GO explicite.

## 1. Problème (RCA prouvé)
Après une divergence d'identité Supabase (sign-out → nouvel anon, reinstall…), le pass d'un
abonnement reste parenté à l'ancienne identité (clé de grant `order:provider:tx` **user-agnostique**,
jamais re-parentée). PATCH 2 refuse (à raison) qu'une autre identité l'utilise → **abo Apple actif
mais wallet 0**.

## 2. Le défaut du PATCH 3 initial (corrigé ici)
La v1 autorisait le re-parent sur le seul signal « entitlement RC actif sur le user courant ».
**Insuffisant** : avec RevenueCat « Transfer to new App User ID », un Restore peut transférer le reçu
Apple vers *n'importe quelle* identité → le RPC aurait déplacé le wallet automatiquement, y compris
**Guest→Account** ou **Account→Guest** (merge implicite interdit en mode ON).

## 3. Règle d'autorisation corrigée
Re-parent autorisé **⟺ DEUX conditions cumulatives** (fail-closed) :

1. **Transfert RC explicitement PROUVÉ côté serveur** — une ligne `rc_pass_transfers` (event RC
   `TRANSFER`, old→new App User ID) existe pour ce couple. *Un entitlement actif ne suffit pas.*
2. **Parenté Guest → Guest UNIQUEMENT** — les deux identités sont anonymes (`auth.users.is_anonymous`).

### Table de décision (implémentée dans `billing.reparent_authorized`, testée)
| from | to | mode | transfert RC prouvé | Résultat | raison |
|---|---|---|---|---|---|
| Guest | Guest | OFF | oui | ✅ AUTORISÉ | `off_guest_to_guest` |
| Guest | Guest | ON | oui | ✅ AUTORISÉ | `on_guest_to_guest` |
| Guest | **Account** | ON | oui | ❌ INTERDIT | `on_guest_to_account` (login) |
| **Account** | Guest | ON | oui | ❌ INTERDIT | `on_account_to_guest` (sign-out) |
| **Account** | **Account** | ON | oui | ❌ INTERDIT | `on_account_to_account` (merge) |
| Guest | Guest | * | **non** | ❌ REFUS | `no_authorized_rc_transfer` |
| None | * | * | oui | ❌ REFUS | `identity_kind_unknown` (fail-closed) |

**Séparation des modes** : la règle `is_anonymous(both)` subsume les flows — `CREATE_ACCOUNT`,
`SIGN_IN_EXISTING`, `SIGN_OUT` produisent tous une transition Guest↔Account → jamais Guest↔Guest →
**jamais** ce transfert.

## 4. Composants serveur
| Composant | Rôle | État |
|---|---|---|
| `billing.reparent_authorized(...)` | DÉCISION pure (table §3) | ✅ codé + testé (10/10) |
| `billing._is_anonymous` / RPC `is_user_anonymous` | type d'identité (Guest/Account) | ✅ codé · RPC dans migration (non appliquée) |
| `billing._has_authorized_rc_transfer` / table `rc_pass_transfers` | preuve serveur du TRANSFER | ✅ lecture codée (fail-closed) · **webhook d'écriture À FAIRE** (§5) |
| `billing.reparent_pass_to_current` / RPC `billing_reparent_pass` | EXÉCUTION atomique (déplace, idempotent, reprojette) | ✅ codé + testé |
| reconcile (intégration) | flag + autorisation → exécution, sinon `restore_required` | ✅ codé + testé (23/23) |

Garanties (testées) : **anti-vol** (sans entitlement actif → `free` ; sans transfert prouvé → refus) ·
**anti-double-grant** (le RPC DÉPLACE, ne crédite jamais ; idempotent) · **anti-merge** (pass + son
ledger seuls ; jamais identité/chat/images/bucket free) · **fail-safe** (toute erreur → `restore_required`).

## 5. Capture RC OBLIGATOIRE avant finalisation (forensic, sans mutation)
Sur le build OFF `f3a6fa2`, régler **uniquement** le comportement RESTORE SANDBOX RC sur
« Transfer to new App User ID », faire un Restore, et **capturer** (RC dashboard / webhook logs) :
`old App User ID`, `new App User ID`, event **TRANSFER**, `aliases`, `original_app_user_id`,
`active entitlement`, `store_transaction_id`. Puis **contrôler le résultat backend sans mutation**.

Cette capture **fige les champs exacts** de `rc_pass_transfers` et le mapping du webhook (event
`TRANSFER` → insertion). *Sans cette capture, `_has_authorized_rc_transfer` reste false → re-parent
refusé.* C'est volontaire.

## 6. Tests obligatoires — TOUS VERTS
`validate_reparent_authorization.py` (10/10) + section PATCH 3 de `validate_reconcile_pass.py` :
- Guest A → Guest B (reinstall OFF) : **autorisé**.
- Guest Premium → Account (login ON) : **interdit**.
- Account Premium → Guest (sign-out ON) : **interdit**.
- Account A → Account B : **interdit**.
- Restore répété : **aucun double grant** (RPC déplace, idempotent).
- Transaction RC différente : **aucun transfert** (pas de preuve → refus).
- Entitlement actif sans relation serveur autorisée : **refus**.
- + fail-closed (identité inconnue) · flag OFF (PATCH 2 strict) · fail-safe (RPC échoue).

## 7. Reste à faire (après GO + capture §5)
1. Webhook RC : sur event `TRANSFER`, écrire `rc_pass_transfers` (champs figés par §5), idempotent
   sur `rc_event_id`.
2. Appliquer la migration `20260717_billing_reparent_pass.sql`.
3. Décider + régler le « Transfer behavior » RC (guest-only : *Transfer to new* ; cible ON : à
   arbitrer — le re-parent Account est de toute façon refusé côté serveur).
4. `BILLING_REPARENT_ENABLED=true` + Restore observé (contrôle DB avant/après).

**PATCH 2 n'est jamais reverté** (le fail-safe s'y rabat). Inutile pour le lancement OFF.
