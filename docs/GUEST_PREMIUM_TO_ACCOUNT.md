# Guest Premium → Account — Architecture (comportement attendu)

## 0. Statut & périmètre
- **AUCUN CODE, AUCUNE ACTIVATION.** Document de **décision produit**.
- Billing v1 **GELÉ** · PATCH 3 **OFF** · migration re-parent **non appliquée**.
- **Objectif** : définir précisément le comportement quand un **Guest possédant un abonnement actif** :
  (a) **crée un compte** (CREATE_ACCOUNT), ou (b) **se connecte à un compte existant** (SIGN_IN_EXISTING).
- **3 modèles comparés à égalité**, sans conclusion posée d'avance → recommandation raisonnée.

## 1. Le scénario (prouvé sur données réelles, pas hypothétique)
Guest `16325f0d` achète le Weekly (tx `…6964544`) → l'utilisateur se connecte au compte `5d144b46` → l'entitlement RevenueCat **suit** l'identité courante (« Transfer to new App User ID », validé sandbox) **mais le PASS backend reste sur le Guest**. Résultat observé : le compte a le **rôle premium sans pass utilisable** (wallet 0, `restore_required`). *(Ce cas précis s'est auto-résolu au renouvellement suivant — nouvelle tx émise sous le compte — mais la question produit demeure : que doit-il se passer AU MOMENT de la transition ?)*

**Invariants techniques (valent pour les 3 modèles) :**
- Clé de grant = `order:provider:tx`, **GLOBALE (par transaction)** → un pass ne peut JAMAIS être re-grant pour la même tx ⇒ **anti-double-grant natif**.
- Un pass appartient à **un** `user_id` (`passes.user_id`) ; le wallet est projeté par `user_id`.
- RC « Transfer to new » déplace l'**entitlement** vers l'identité courante ; le backend **ne re-parente pas** automatiquement (PATCH 2).
- `auth.users.is_anonymous` distingue **Guest** (true) d'**Account** (false).
- `/me/status` est désormais **cohérent** dans l'état intermédiaire (Fix B : premium sans pass possédé → `restore_required` + `needs_restore=true`).

## 2. Les trois modèles

**Modèle 1 — Aucun transfert.** Premium + wallet **restent sur le Guest** ; le compte connecté n'en bénéficie pas.

**Modèle 2 — Claim explicite.** L'utilisateur **confirme** le rattachement du Premium Guest au compte. Preuve serveur, idempotence, anti-vol, rollback.

**Modèle 3 — Transfert auto limité à CREATE_ACCOUNT.** Auto **uniquement** quand le compte est **créé depuis le Guest courant**. **Interdit** SIGN_IN_EXISTING, sign-out, Account↔Account.

## 3. Comparaison objective (12 dimensions)

| Dimension | M1 · Aucun transfert | M2 · Claim explicite | M3 · Auto sur CREATE_ACCOUNT |
|---|---|---|---|
| **Bénéfices UX** | Aucun ; « j'ai payé mais mon compte n'a rien » | Clair + honnête (« rattacher votre abonnement ? ») ; couvre CREATE **et** SIGN_IN | Fluide sur CREATE (0 friction) ; **ne couvre pas** SIGN_IN_EXISTING |
| **Risques sécurité** | Minimal (rien ne bouge) | Faible **si** gardé (confirmation + preuve serveur) | Moyen : **automatique/silencieux** (intent implicite) ; borné par « CREATE depuis le guest courant » |
| **Double grant** | Nul | Nul (on **déplace**, idempotent per-tx) | Nul (idem) |
| **RevenueCat** | Divergence RC↔backend (entitlement transféré, pass non) | Le claim **réconcilie** backend ↔ RC | RC transfère à la création ; l'auto-claim aligne le pass |
| **Propriété pass/wallet** | Guest ; compte = rôle sans pass | Compte après claim ; Guest vidé | Compte après create ; Guest vidé |
| **Historique projets** | Restent sur le Guest (compte vide) | **Décision séparée** : claim pass-only OU pass+historique | Idem (le create peut porter l'historique) |
| **Après sign-out** | Retour Guest → premium là | Compte garde le premium ; sign-out → Guest frais sans premium | Idem M2 |
| **Changement d'appareil** | ❌ Guest anonyme = device-local → premium **perdu** | ✅ Compte durable → premium suit la connexion | ✅ idem |
| **Récup. réinstallation** | ❌ Guest anonyme perdu au reinstall → **premium perdu** | ✅ reconnexion compte → premium restauré | ✅ idem |
| **Compat OFF** | Moot (guest-only ; mais reinstall perd le premium) | Moot (pas de compte en OFF) | Moot (pas de CREATE en OFF) |
| **Compat ON** | ❌ contredit « compte = foyer durable du premium » | ✅ **est** le mécanisme ON | ✅ optimise le sous-cas CREATE |
| **Complexité impl.** | La plus faible (ne rien faire) | Moyenne-haute (UI confirm + RPC claim + RC + rollback) | Moyenne (scopé CREATE + mêmes gardes, sans UI) |
| **Tests E2E** | Minimal | claim OK / déjà-claimé / abo expiré au claim / rollback / anti-vol | CREATE transfère · SIGN_IN non · sign-out non · Account↔Account non · idempotence · anti-vol |

## 4. Synthèse

### Recommandation principale
**Modèle 2 (claim explicite) comme mécanisme général**, l'auto-claim de type Modèle 3 restant une **option d'ergonomie ultérieure** (surface automatique du claim au moment du CREATE), **jamais** un transfert silencieux non gardé.

### Raisons (adossées aux dimensions)
1. **Durabilité du premium** — seuls M2/M3 rendent le premium **résistant** au changement d'appareil et à la réinstallation. M1 rend un abonnement **payant** fragile (perdu au reinstall) : rédhibitoire.
2. **Couverture** — M2 couvre **CREATE_ACCOUNT ET SIGN_IN_EXISTING** ; M3 ne couvre **que** CREATE (un utilisateur qui a acheté en guest puis réinstalle et **se reconnecte** ne serait pas servi par M3 seul).
3. **Intent & sécurité** — la **confirmation explicite** de M2 supprime le risque d'un transfert automatique non voulu (faiblesse de M3), tout en restant clair pour l'utilisateur.
4. **Réconciliation déterministe** — le claim aligne backend ↔ RC en un point unique, gardé, idempotent.

### Alternatives rejetées
- **M1 (aucun transfert)** — rejeté : premium device-fragile + UX « payé pour rien » sur le compte ; incompatible avec la promesse « compte = premium durable ».
- **M3 seul (auto CREATE uniquement)** — rejeté **comme mécanisme unique** : transfert silencieux (intent implicite) + ne couvre pas SIGN_IN_EXISTING. **Retenu uniquement** comme raccourci UX **au-dessus** de M2 (l'auto-claim sur CREATE = confirmation implicite du « je crée mon compte depuis ce guest premium »).

### Conditions de sécurité INDISPENSABLES (tout modèle avec transfert)
1. **Preuve serveur de propriété** — le guest possède réellement l'abo actif (entitlement RC + tx/`app_user_id` du guest). **Jamais** de confiance au client.
2. **Idempotence per-transaction** — le pass **se déplace** (jamais un 2ᵉ GRANT pour la même tx) ⇒ zéro double-grant / double-crédit.
3. **Anti-vol** — seul l'abo **de la même personne** (preuve RC : `original_app_user_id` / event TRANSFER) est claimable ; jamais un abo que l'identité courante ne possède pas légitimement.
4. **Une seule fois + rollback** — claim idempotent (re-claim = no-op) ; en cas d'échec, le Guest **conserve** son pass (aucune perte).
5. **Pas de merge implicite d'identité** — seul le **pass** (premium) bouge ; l'historique/projets est une **décision explicite séparée** ; Guest et Account restent des identités distinctes côté `auth`.
6. **`/me/status` cohérent** dans chaque état intermédiaire (déjà acquis : Fix B).
7. **Alignement RevenueCat** — le réglage « Transfer behavior » doit être cohérent avec le modèle retenu (guest-only : *Transfer to new* ; le claim gère le rattachement au compte).

### Décision d'implémentation
**Reportée** (produit). Ce document ne prescrit ni code ni activation. Quand une implémentation sera décidée : elle réutilisera les briques déjà écrites mais **inertes** (autorisation `reparent_authorized`, table `rc_pass_transfers`, webhook TRANSFER, RPC `billing_reparent_pass`), sous flag, avec validation device — cf. `docs/PATCH3_REPARENT_REDESIGN.md`.
