# AYDEN STUDIO — Guest / Account / Premium Identity Model (reference spec)

> **Status: ARCHITECTURE VALIDÉE (référence figée).** Modèle d'implémentation :
> **PROBABLEMENT « Guest séparé »** (évidence code+config forte, non prouvé runtime).
> **Une seule inconnue restante : U4** — à confirmer par un smoke-test device (~5 min).
> Aucun code n'est écrit tant que U4 n'est pas confirmée. Ce document est la source de
> vérité du modèle d'identité ; il remplace le bricolage autour du comportement actuel.

_Dernière révision de conception : wave-4.9.3 / audit Guest-parking (2 workflows + sondes U1/U4/U5)._

---

## 1. Règles métier (FIGÉES)

1. Chaque appareil/navigateur conserve un **Guest local durable**.
2. À la connexion d'un compte, le **Guest local est PARQUÉ** (mis de côté), le compte est actif temporairement.
3. **Sign-in à un compte EXISTANT** = AUCUN transfert de crédit Guest, AUCUN bonus.
4. Au **Sign out**, le **Guest local exact est RESTAURÉ** (même `user_id`, même wallet, même historique).
5. Seule la **création réelle d'un nouveau compte** peut réclamer le solde Guest (1×) et accorder **+2** (1×).
6. Un Guest est réclamable **une seule fois** ; un compte réclame **un seul Guest à vie** ; un compte donné, connecté sur N appareils, n'absorbe **aucun** Guest supplémentaire et ne reçoit **aucun** +2 supplémentaire. Les Guests A/B/C restent attachés à leurs appareils.
7. Maximum initial : Guest non consommé **1 + 2 = 3** ; Guest consommé **0 + 2 = 2**.
8. Pas de cumul **Premium + Free** (autorité de génération = pass mesuré, cf. RC-PR3b).
9. Règles compatibles avec un futur PWA (le web n'est pas un target actuel — scaffold seul).

---

## 2. L'unique inconnue : U4 (verrou du modèle de création de compte)

**Question :** lors d'un `signInWithIdToken` avec un **Apple ID jamais utilisé**, depuis une session anonyme :

- **Résultat A — SÉPARÉ :** `newUid != guestUid` → un nouveau `user_id` est créé. Le Guest et le compte sont deux identités distinctes.
- **Résultat B — UPGRADE-IN-PLACE :** `newUid == guestUid` → l'anonyme est transformé en compte sur place.

**Évidence actuelle (code + config, forte mais NON runtime) → penche vers A (séparé) :**
- `signInWithApple` appelle un `signInWithIdToken` **nu, sans link** ; le `if(wasAnon)/else` appelle le **même** call identique [`auth_service.dart:119-138`]. Le code ne lie pas ; il « parie » sur un réglage dashboard « link anonymous to OAuth » (Prerequisite A) et **mesure** `upgraded = newUid == previousUid`.
- GoTrue `/settings` **n'expose aucun** tel réglage (`external_anonymous_users_enabled: null`). La voie standard de conversion d'un anon est `linkIdentity`, **pas** `signInWithIdToken`.
- Comportement Supabase standard pour `grant_type=id_token` avec un `sub` Apple neuf = **créer un user séparé**.
- `linkIdentityWithIdToken` (seul vrai upgrade-sur-place) est une méthode **différente**, utilisée par « Continue with Apple ».

**⚠️ Reste à PROUVER en runtime** (id_token Apple non productible hors device). **Smoke-test device (5 min) :** anon de test → `signInWithIdToken` (Apple ID neuf) → comparer `previousUid`/`newUid` + `is_anonymous` avant/après.

**Conséquence produit majeure du branchement :**
- **A (séparé)** : les DEUX parcours (create + sign-in-existing) gardent le Guest séparé, parqué, **restaurable**. Le modèle cible est **pleinement** satisfait.
- **B (in-place)** : à la **création**, le Guest **devient** le compte → il n'y a **pas** de Guest séparé à restaurer après une création ; « Sign out → Guest restauré » ne vaut alors que pour le **sign-in-existing**. Le create **consomme** le Guest (asymétrie à accepter côté produit).

---

## 3. Parking de session (Option 1 — recommandée)

Aujourd'hui : **une seule** case Keychain `sb_supabase_session` = un blob JSON (access + refresh token + user + expiry) [`keychain_local_storage.dart:44`]. Restaurée offline au boot par `setInitialSession` ; validation réseau du refresh ensuite (`recoverSession`/autoRefresh) qui **wipe** le slot si le serveur rejette.

**Ajout minimal (net-new) :** une **DEUXIÈME** case secure-storage `parked_guest_session`, distincte de `kSessionKey`.
- `park()` : capturer le JSON de `_currentSession` **au moment exact** du park (access+refresh+user_id+expiry).
- `restore()` : `recoverSession(parkedJson)` (ou `setSession(refreshToken)`) → même `user_id` ; `clear()` après restauration réussie.
- Échec (RT rejeté/expiré) : fallback = nouvel anon à **Free 0** (jamais de crash, jamais de double-crédit).

**Prouvé (sonde U1, cœur) :** un refresh token anonyme est **accepté** (HTTP 200), rend le **même** `user_id`, et **survit au rejeu** (pas de reuse-detection agressive) → ré-injection robuste. **Reste device-gated :** survie du RT parqué **après** un `signInWithIdToken` compte + `signOut(scope=local)`.

**Risque plateforme :** iOS **LOW** (Keychain `first_unlock_this_device`, survit à la désinstallation) · Android **MEDIUM** (EncryptedSharedPreferences/Keystore best-effort) · PWA **HIGH** (`flutter_secure_storage_web` = localStorage + clé AES en localStorage ; incognito/clear/ITP ~7 j) — **le web n'est pas un target actuel**.

---

## 4. Les trois parcours

### Parcours A — Guest (création ou restauration)
Boot : restaurer la session Keychain existante (même UUID) ; sinon minter un anon. **1 free max** (nouvelle règle). Historique/wallet/trial suivent le `user_id` automatiquement (clé `trial:<user_id>`, RLS par `user_id`).

### Parcours B — Create account (SEUL moment de claim)
**SI U4 = A (séparé) :** `park(guest)` → `signInWithIdToken` (Apple ID neuf) → compte **séparé** → **1 seule RPC** `claim_guest_and_bonus(account_id, guest_id)` (transfert + +2) → le Guest **reste parqué à 0**.
**SI U4 = B (in-place) :** `signInWithIdToken` upgrade l'anon sur place (Guest **devient** compte) → **AUCUN transfert** (le solde est déjà là) → accorder **UNIQUEMENT +2**, keyé `signup_bonus:<user_id>`, gardé par le flip `is_anonymous` (true→false, 1×). Pas de Guest séparé à parquer/restaurer côté création.

### Parcours C — Sign in existing
`park(guest)` → `signInWithIdToken` vers le compte existant (UUID change) → **AUCUN** claim, **AUCUN** bonus, **AUCUN** merge (règle 3). **Sign out** → `restore(guest parqué)`.

---

## 5. Modèle anti-abus atomique — TROIS clés, UNE RPC SQL

**Clés d'idempotence** (`ledger_entries.idempotency_key`, `UNIQUE`, upsert append-only) :
1. `guest_claim:<guest_id>` — un Guest réclamé **1 seule fois**.
2. `initial_guest_claim:<account_id>` — un compte réclame **1 seul Guest à vie** *(la clé décisive qui ferme l'attaque « compte X réclame Guest A puis B puis C »)*.
3. `signup_bonus:<account_id>` — **1 seul +2** par compte.

**UNE seule RPC SQL** `claim_guest_and_bonus(account_id, guest_id)` (calque de `billing_try_hold`) :
- `pg_advisory_xact_lock(hashtext(account_id))` **ET** `hashtext(guest_id)` (ordre trié anti-deadlock), tout dans **une** transaction.
- **Assertion de fraîcheur :** le compte a **ZÉRO** ligne ledger free-bucket (`pass_id IS NULL`) — sinon il a déjà généré → **over-credit** (rejeter).
- Chaque INSERT vérifié par **rowcount** + **RAISE/rollback** si conflit (JAMAIS un `DO NOTHING` silencieux qui écrirait le débit Guest sans le crédit compte).
- Réel « once-only » concurrent (2 appareils) = le lock advisory sérialise ; le 2ᵉ voit les clés posées → RAISE.

**Preuve « nouveau compte » (jamais un booléen client) :**
- **U4=A :** **ticket signé** émis à la session **Guest** avant OAuth = `{guest_id, nonce, issued_at, exp court}`, **HS256 avec un SECRET DÉDIÉ** (jamais `SUPABASE_JWT_SECRET` — Supabase signe ES256, risque alg-confusion [[wave_5_17c_jwks_es256]]) + `typ`/`aud` distincts (jamais rejouable comme JWT d'auth). Après OAuth : signature+exp valides ; `user courant == ticket.guest_id` ; **compte frais** (0 ligne free-bucket) ; pas de `initial_guest_claim:<account_id>` ; pas de `guest_claim:<guest_id>`. Le `guest_id` vient du **ticket signé**, jamais d'un param client brut → impossible de réclamer un AUTRE Guest.
- **U4=B :** preuve = **flip `is_anonymous`** (true à l'émission du ticket → false maintenant) sur le **même** user + pas de `signup_bonus:<user_id>`. (`created_at ≈ now` est FAUX ici : l'upgrade sur place garde le `created_at` de l'anon.)

---

## 6. Comptabilité ledger (prouvée contre la projection RÉELLE)

**Formule** [`billing.py:188-211`] : `free_bucket = max(0, Σ available_delta où pass_id IS NULL) + TRIAL_CREDITS si AUCUNE ligne entry_type='TRIAL'`.
Un `delta=0` **ne soustrait rien** ; il faut une **vraie écriture négative** + veiller au **+3 fantôme** sur le compte neuf (aucune ligne TRIAL → +TRIAL_CREDITS).

**Types autorisés (CHECK live) :** `GRANT, HOLD, COMMIT, RELEASE, REFUND, ADJUSTMENT, EXPIRE, TRIAL`. → `CLAIM_TRANSFER`/`SIGNUP_BONUS` **interdits** → réutiliser **ADJUSTMENT + TRIAL** + `reference_id` discriminant (`reference_type='PROMO'`).

### Modèle SÉPARÉ (U4=A), avec `TRIAL_CREDITS = 1`

**Scénario 1 — Guest non consommé (balance 1) :**
| Écriture | Guest (pass_id NULL) | Compte (pass_id NULL) |
|---|---|---|
| `grant_trial(guest)` (idempotent) matérialise | `TRIAL(+1, key=trial:G)` | — |
| `remaining = max(0, Σ) = 1` | | |
| débit Guest | `ADJUSTMENT(-1, key=guest_claim:G)` → Σ = 0 | — |
| crédit compte (= trial, **tue le +3 fantôme**) | — | `TRIAL(+1, key=initial_guest_claim:X)` |
| bonus | — | `ADJUSTMENT(+2, key=signup_bonus:X)` |
| **Projection** | **Guest = max(0,0)+0 = 0** ✓ | **Compte = max(0,3)+0 = 3** ✓ |

**Scénario 2 — Guest consommé (balance 0) :** `remaining = 0` → `ADJUSTMENT(-0, guest_claim:G)` (Guest reste 0) ; compte `TRIAL(+0, initial_guest_claim:X) + ADJUSTMENT(+2, signup_bonus:X)` → **Compte = 2** ✓.

> Le crédit compte est **`TRIAL`** (pas ADJUSTMENT) exprès : `trial_granted = any(entry_type=='TRIAL')` devient vrai → **supprime le +3 fantôme** et bloque un futur +3 réel. La **fraîcheur** (0 ligne free-bucket) garantit qu'aucun `trial:<account_id>(+3)` pré-claim ne s'ajoute (sinon over-credit).

### Modèle IN-PLACE (U4=B)
Pas de transfert (le Guest **est** le compte, même row, solde déjà présent). Une seule écriture : `ADJUSTMENT(+2, key=signup_bonus:<user_id>)` gardée par le flip `is_anonymous`. Compte = balance + 2. **Pas de restauration Guest après create.**

---

## 7. `TRIAL_CREDITS` — DEUX sources d'autorité à aligner

La nouvelle règle « 1 gratuit » impose de passer **3 → 1** aux **deux** endroits (sinon Guest 3 + 2 = 5) :
- Python : `billing.py:48` (`TRIAL_CREDITS = 3`).
- SQL : **hardcodé dans le RPC LIVE `billing_try_hold`** (`TRIAL', 3`) → nouvelle migration qui remplace le littéral.

---

## 8. Sign out / restore
- `signOut(scope=local)` sur le **compte** uniquement.
- `recoverSession(guest parqué)` → assert `currentUser.id == guest d'origine`.
- **RETIRER** `postSignoutMarkerPending` + `POST /identity/post-signout-guest` + `mark_trial_consumed(delta0)` : inutiles sous restauration et **activement nuisibles** (re-POST + gate Generate sur le Guest restauré). Forcer le flag à false au restore.
- Échec restauration → nouvel anon à **Free 0**.

---

## 9. Impact code — KEEP / CHANGE / RETIRE

| Pièce | Verdict | Note |
|---|---|---|
| `linkIdentityWithIdToken` (runLinkNewIdentity) | **RETIRE** | upgrade-sur-place détruit le Guest séparable |
| `signInWithApple`/`signInWithIdToken` | **CHANGE** | primitive d'activation compte ; **parker le Guest AVANT** |
| `runSignOut` | **CHANGE** | ne plus minter un anon → **restaurer** via recoverSession |
| `postSignoutMarkerPending` + `/identity/post-signout-guest` | **RETIRE** | mort/nuisible sous restauration |
| `claim-signup-bonus` (+2) | **KEEP mais À IMPLÉMENTER** | corps `grant_signup_bonus`/`mark_signup_eligible` **absents** (503) |
| merge/claim identity (`identity_claim_and_merge`) | **RETIRE (pour le claim)** | transfère le crédit + rend le Guest non-restaurable (viole 3/4) ; **coordonner** (collision billing) |
| Free-tier keying `trial:<user_id>` | **KEEP** | l'atout : restaurer le même UUID restaure wallet+trial ; **pas de device_id** |
| RLS / historique par `user_id` | **KEEP** | restauration même-UUID = historique intact |
| **4 patches P0** (paywall/reconcile/HOLD/copie Apple) | **KEEP — indépendants** | keyés rôles/store_tx/intent → **shippables séparément** |

---

## 10. Résiduels anti-abus (à ASSUMER — hors périmètre des 3 clés)
- **Farming de comptes** : les clés stoppent le re-claim d'un Guest, **pas** la création répétée de comptes (+2 par nouvelle identité). → cap **device/receipt/IP** (décision séparée).
- **HOLD in-flight** sur le Guest zéroté : un RELEASE tardif peut re-créditer ~1 → réclamer seulement hors intent en vol / tenir compte du held.
- **Collision `identity_claim_and_merge`** (existe en base) : ne pas déplacer les crédits deux fois.
- **Ticket** : HS256 **secret dédié**, `typ`/`aud` distincts (anti alg-confusion).

---

## 11. Plan d'implémentation ordonné (GATÉ sur U4)

0. **Smoke-test device U4 + U1-complet (~5 min)** → choisir la branche §4/§5/§6, supprimer l'autre.
1. `TRIAL_CREDITS` **3 → 1** (Python **et** migration SQL du RPC).
2. Implémenter le corps `grant_signup_bonus` (forme `grant_trial`) — **ne pas** juste activer le flag.
3. RPC atomique `claim_guest_and_bonus` (si U4=A) **ou** grant-+2-sur-flip (si U4=B).
4. Parking : 2ᵉ case secure-storage + `park()/restore()/clear()`.
5. Parcours Create-account (branche U4).
6. Parcours Sign-in-existing (park, pas de claim).
7. Sign out → restore (retirer le marqueur post-signout + son gate Generate).
8. Tests wallet E2E (valeurs projetées avant/après), concurrence 2 appareils, rejeu, restore-après-expiration.
9. Cap anti-farming de comptes.
10. Migration utilisateurs déjà liés : **none** (additif). Rollback : **feature flag OFF** (revient au mint-new-anon actuel).

---

## 12. État figé
```
Architecture cible :      VALIDÉE (référence)
Protection 3 clés :       VALIDÉE
Parking local :           CŒUR PROUVÉ (U1) ; scénario complet device-gated
Modèle d'implémentation : PROBABLEMENT Guest séparé (U4 non prouvé runtime)
Implémentation :          BLOQUÉE jusqu'à confirmation device U4 + intégration des 6 fixes
```

---

## 13. Implémentation livrée (2026-07-17) — les DEUX modes, derrière un flag

Le flag maître `FeatureFlags.accountSystemEnabled` (frontend) / `ACCOUNT_SYSTEM_ENABLED`
(backend, autorité serveur) sélectionne entre **deux variantes ENTIÈREMENT implémentées** :

- **OFF (lancement V1 stable)** — `effective_trial_credits()=3`, aucune UI compte
  (`profile_screen` masque `AccountSection`), endpoints ON en `404`, `billing_try_hold`
  appelé en 3-args (RPC prod inchangée). Comportement byte-identique au V1 actuel.
- **ON (Identity complet)** — `TRIAL=1` + bonus `+2` (max 3), Guest durable (park/restore),
  Create défensif (compte séparé), Sign-in-existing (sans claim), Sign-out restaure le Guest
  EXACT, jamais un nouvel anonyme.

**Code câblé (ne dépend d'aucune validation device pour EXISTER) :**
- Backend : `billing.effective_trial_credits/grant_signup_bonus/mark_signup_eligible/`
  `claim_guest_and_bonus`, `identity` ticket HS256 (`CLAIM_TICKET_SECRET`, jamais le JWT
  Supabase) + `/identity/claim-ticket` + `/identity/claim-guest-on-create` (gatés ON).
  Validé `validate_account_mode.py` 20/20, OFF non-régressé.
- Frontend : `account_link` (3 flows ON purs) + `account_section` (ON-EXCLUSIF, aucun handler
  merge) + `guest_parking` (2ᵉ slot Keychain) + `guest_restore_pending_provider` (gate
  anti-anon). Suite verte.

**Correction anti-anon (obligatoire, livrée) :** au sign-out, si un blob Guest parqué existe
mais que `recoverSession` échoue (réseau / refresh token indispo) → `SignOutRestoreResult`
`.restorePending` → `guestRestorePending` levé → génération/wallet BLOQUÉE + bandeau Retry ;
**jamais** de nouvel anonyme, aucun trial fantôme. Nouvel anon UNIQUEMENT si `hasParked()==false`
(storage réellement vide). Boot re-tente `recoverSession`.

### 13.1 Dépendances externes AVANT de flipper ON (pas du code — de la config/ops)
1. **RevenueCat dashboard → « Transfer behavior = Keep with original App User ID ».** Le code
   fait `Purchases.logIn(accountId)` au sign-in et `logIn(guestId)` au restore ; la SÉPARATION
   des entitlements Guest↔compte dépend de ce réglage dashboard. À vérifier en sandbox.
2. **Appliquer la migration `supabase/migrations/20260717_account_mode_trial_and_claim.sql`**
   (paramètre `billing_try_hold` en `p_trial_credits int default 3` — rétro-compatible, OFF
   inchangé ; + RPC atomique `claim_guest_and_bonus`). Sûre à tout moment, OBLIGATOIRE avant ON.
3. **Poser `CLAIM_TICKET_SECRET`** (secret dédié, ≠ `SUPABASE_JWT_SECRET`) sur Render.

### 13.2 Validations device résiduelles (n'invalident aucun code câblé)
- U4 runtime (compte réellement séparé du Guest) — l'architecture défensive rend le résultat
  moot (aucune session anon active au sign-in), à confirmer sur appareil.
- Apple / Google sign-in réels + RC sandbox (entitlements séparés) + park/restore Keychain réel.
```
Architecture :            VALIDÉE (référence)
Code (backend+front+UI) : CÂBLÉ + tests verts (OFF 3 / ON 1, correction anti-anon prouvée)
Reste avant ON :          config RC dashboard + migration + CLAIM_TICKET_SECRET + validations device
```

---

## 10. Variante WEB (PWA) — actée 2026-08-12

> Ajout au modèle figé, **pas une dérive**. Décision prise avec l'audit
> [`PWA_MONETIZATION_AUDIT.md`](PWA_MONETIZATION_AUDIT.md) §6bis (D2).

Sur le Web, l'identité anonyme est **upgradée sur place** :

```
anonyme Supabase ──(linkIdentity / updateUser + OTP)──▶ compte
        même user_id, même wallet, mêmes projets
```

**Pourquoi le Web diverge du mobile.** Le navigateur dispose de `linkIdentity`,
l'upgrade-sur-place officiel de Supabase — celui que §2 identifie comme « seul
vrai upgrade-sur-place » et que le mobile n'emprunte pas. Puisque le `user_id`
est conservé, il n'y a **rien à transférer** : ni parking, ni claim, ni
re-parent de pass, ni restore. Toute cette mécanique existe côté mobile pour
réparer une discontinuité d'identité que le Web n'a pas.

**Conséquences sur les 9 règles :**

| Règle | Web |
|---|---|
| 1 — Guest durable par navigateur | ✅ identique (l'anonyme EST le Guest) |
| 2 — parking à la connexion | **sans objet** : pas de seconde identité à parquer |
| 3 — sign-in existant = aucun transfert | **sans objet** : rien à transférer |
| 4 — restore au sign-out | **sans objet** ; se déconnecter d'un compte Web ne fait pas réapparaître un invité, il n'y en a jamais eu deux |
| 5 — création réclame le Guest 1× + accorde +2 | ✅ conservé — mais « réclamer » devient trivial (c'est le même utilisateur) ; **le +2 reste soumis au même claim-once** |
| 6 — claim-once / un Guest par compte à vie | ✅ conservé, porté par le même compteur |
| 7 — maximum initial 1+2 / 0+2 | ✅ conservé |
| 8 — pas de cumul Premium + Free | ✅ conservé (autorité = pass mesuré) |
| 9 — compatible PWA | ✅ c'est cette section |

**Ce qui n'est PAS autorisé par cette variante** : un troisième système
d'identité, un second moteur d'entitlement, ou un `user_id` Web distinct du
`user_id` porteur du pass. L'autorité reste le Billing Engine.

**Statut U4** : toujours ouvert côté mobile. Il ne conditionne plus le code Web —
seulement la formulation de cette section (convergence si U4 = B, variante
assumée si U4 = A).
