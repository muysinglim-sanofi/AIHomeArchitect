# PWA — Audit monétisation (identité / entitlement / anti-abus / ABA)

> **Statut : AUDIT — aucune ligne de code.** Document de décisions, à valider avant
> d'ouvrir une branche monétisation.
> **Date** : 2026-08-12 · **Base** : checkpoint `486da7f` (backend) / `2fee767` (PWA).
> **Portée** : ce qui existe déjà, ce qui manque, et les décisions qui doivent être
> prises **avant** d'écrire du code d'auth, de quota ou de paiement.

---

## 0 — Résultat en une page

**La question « où vit l'autorité de l'entitlement » a déjà une réponse écrite, et
ce n'est pas RevenueCat.** `docs/BILLING_ENGINE_SPEC.md` (2026-06-30) la pose
explicitement :

```
RevenueCat webhook (mobile)  ─┐
                              ├─→  Payment normalisé  ─→  Billing Engine
KHQR/Bakong callback (web)   ─┘
```

> « Le `Payment` est **agnostique du fournisseur**. »

L'autorité est le **Billing Engine** (ledger append-only + passes + projection
wallet). RevenueCat est **un adaptateur d'acquisition**, au même rang qu'ABA le
sera. La spec interdit même explicitement KHQR dans l'app mobile (§3.1.1 App
Store) et réserve le web comme « canal séparé, postérieur, qui alimente le
**même** Billing Engine ».

**Conséquence : il n'y a pas de troisième système à créer, ni de choix d'autorité
à faire. Il y a un adaptateur web à écrire dans une architecture déjà décidée.**

Les vraies inconnues sont ailleurs, et elles sont au nombre de trois :

| # | Inconnue | Nature | Bloquant pour |
|---|---|---|---|
| **D1** | Que vaut « un utilisateur » sur le Web ? | **Produit** | quota gratuit, anti-abus |
| **D2** | Le compte Web est-il le même objet que le Guest mobile figé ? | **Produit + technique** | cross-platform |
| **D3** | ABA est-il seulement accessible à Ayden Studio (compte marchand) ? | **Commercial** | tout le point 4 |

Aucune ne se résout en lisant du code. Elles se tranchent.

---

## 1 — Ce qui existe (vérifié)

### 1.1 — Côté mobile : un moteur de droits complet et livré

| Brique | Où | État |
|---|---|---|
| Ledger append-only, wallet-projection, passes, orders, products | `supabase/migrations/20260701…20260717` (9 migrations) | livré |
| `resolve_generation_access` — priorité `admin/premium > promo_unlimited > promo_limited > free(watermark) > blocked` | `backend/promo.py:131` | livré |
| `billing.reserve_decision` / `try_hold` (HOLD atomique, advisory-lock, pass-first puis free) / `apply_billing_for_intent_transition` | `backend/billing.py` | livré |
| Idempotence de la consommation = `intent_id` (Intent ≠ Job) | `docs/GENERATION_INTENT_V1_SPEC.md` | livré (PR0→PR4) |
| Acquisition RevenueCat → `grant_purchase`, `reconcile_pass_from_subscriber` (clé = `store_transaction_id`) | `backend/billing.py:694+` | livré |
| Trial / signup-bonus / claim Guest (`grant_trial`, `grant_signup_bonus`, `claim_guest_and_bonus`) | `backend/billing.py:404-511` | livré, derrière `account_system_enabled()` |

Les **trois points d'insertion** dans `/generate` et `/refine` (reserve → hold →
commit/release) sont déjà câblés côté mobile.

### 1.2 — Côté PWA : rien

Ce n'est pas une lacune accidentelle, c'est un choix documenté dans l'adaptateur :

> « staging has no wallet to consult »
> « Deliberately NOT watermarked: the free-tier mark is a monetisation decision
> owned by the mobile billing path »

Concrètement, le schéma `pwa_staging` **ne contient ni** `wallets`, **ni**
`passes`, **ni** `billing_ledger`, **ni** `generation_intents`. Le chemin
`/pwa/staging/generate` ne fait **aucun** appel billing : ni `reserve_decision`,
ni `try_hold`, ni watermark, ni compteur. Une génération PWA est aujourd'hui
**gratuite et illimitée**.

### 1.3 — Identité PWA aujourd'hui

- **Anonyme Supabase** (`sb-<ref>-auth-token` en `localStorage`), un `user_id`
  par **profil navigateur**.
- Tenancy `installation_id` + RLS sur `owner_user_id` (schéma `pwa_staging`).
- Aucun parcours de création de compte, aucun sign-in, aucun lien vers une
  identité mobile.

### 1.4 — Le modèle d'identité figé prévoit déjà le Web

`docs/GUEST_ACCOUNT_IDENTITY_SPEC.md` — **référence figée**, 9 règles. La règle 9
dit littéralement : « Règles compatibles avec un futur PWA ». Les règles
structurantes pour nous :

- Guest **durable** par appareil/navigateur ; **parqué** à la connexion ;
  **restauré** au sign-out (même `user_id`, même wallet, même historique).
- Un Guest est réclamable **une seule fois** ; un compte réclame **un seul Guest
  à vie** ; +2 accordé **une seule fois**.
- Sign-in à un compte **existant** = aucun transfert, aucun bonus.
- **Pas de cumul Premium + Free** : l'autorité de génération est le **pass
  mesuré**.

⚠️ **Une inconnue reste ouverte dans cette spec : U4** — un `signInWithIdToken`
avec un Apple ID neuf depuis une session anonyme crée-t-il un `user_id` séparé
(A) ou transforme-t-il l'anonyme sur place (B) ? La spec dit qu'aucun code ne
doit être écrit tant que U4 n'est pas confirmée. **Sur le Web la question se pose
différemment et a une réponse propre** : Supabase expose `linkIdentity`, qui est
l'upgrade-sur-place officiel. C'est-à-dire que le Web peut **choisir**
délibérément le comportement B, alors que le mobile le subit. Voir D2.

---

## 2 — D1 : que vaut « un utilisateur » sur le Web ? *(décision produit)*

**Le problème, chiffré.** Aujourd'hui : navigation privée → nouveau profil →
nouvel anonyme Supabase → nouveau quota gratuit. Coût du contournement pour
l'utilisateur : **~5 secondes**. Coût pour nous : 1 render.

Aucun compteur serveur ne corrige ça, parce que le compteur est indexé sur un
`user_id` que le visiteur peut recréer à volonté. **Il faut d'abord décider ce
qu'on compte.**

### Options, avec leurs conséquences

| | Option | Friction visiteur | Efficacité anti-abus | Coût / risque |
|---|---|---|---|---|
| **A** | Ne rien faire — 1 gratuit par anonyme | nulle | nulle | coût OpenAI non borné ; un script peut boucler |
| **B** | Heuristiques serveur (IP + fingerprint navigateur) | nulle | moyenne, dégrade vite (VPN, mobile 4G partagé, cybercafé) | faux positifs = utilisateurs légitimes bloqués ; données perso à justifier |
| **C** | Compte obligatoire **avant** la génération gratuite | forte | forte | tue le funnel « 1 WOW gratuit » ; contraire à l'analyse marché Cambodge (§2.2 de `monetization_strategy_revision.md` : le compte se justifie **à la transaction**) |
| **D** | Génération gratuite **filigranée / basse résolution**, compte + paiement pour l'image propre | nulle | **contournement rendu sans intérêt** | coût OpenAI toujours payé à chaque bypass |
| **E** | OTP téléphone au **paywall** seulement, gratuit lié à l'anonyme | nulle avant paywall | borne l'abus au coût d'un numéro | coût OpenAI toujours payé |

### Ce que je recommande, et pourquoi

**D + E**, pas B.

- **D réutilise un mécanisme déjà pensé** : `resolve_generation_access` a déjà le
  tier `free(watermark)`. Le filigrane n'est pas une invention, c'est le
  comportement free existant que la PWA a délibérément désactivé. Il transforme
  la question « comment empêcher le bypass » en « pourquoi bypasser » : la
  deuxième est bien plus facile à gagner.
- **E aligne la friction sur l'intention d'achat**, ce que l'analyse marché
  Cambodge recommande explicitement (le téléphone est la primitive d'identité
  locale, pas l'email).
- **B est écarté** : une empreinte device sur un marché à forte proportion de
  connexions mobiles partagées produit des faux positifs, et « bloquer un client
  qui paie » coûte plus cher qu'un render.

⚠️ **Aucune de ces options ne borne le coût OpenAI d'un attaquant scripté.** Si
c'est une préoccupation réelle, il faut un rate-limit par IP **en plus** — ce
n'est pas de l'anti-abus produit, c'est de la protection d'infrastructure, et ça
appartient au point 7 (production hardening), pas ici.

**À trancher :** D+E, ou autre chose. Tant que ce n'est pas tranché, **aucun
compteur ne doit être écrit**, parce que le schéma du compteur dépend de la
réponse.

---

## 3 — D2 : quel objet identité pour le Web ? *(décision produit + technique)*

Trois façons de brancher le Web sur le modèle figé :

| | Modèle | Ce que ça donne | Coût |
|---|---|---|---|
| **1** | Le navigateur **est** un Guest, au sens exact de la spec figée | cohérence totale avec mobile ; le +2 et le claim-once s'appliquent tels quels | il faut porter la mécanique park/restore côté Web |
| **2** | Le Web a son propre anonyme, relié au compte au moment du paiement via `linkIdentity` (upgrade **sur place**, `user_id` conservé) | le projet, le wallet et l'historique du visiteur survivent au paiement **sans transfert** ; règle 3 (« sign-in existant = aucun transfert ») devient sans objet parce qu'il n'y a rien à transférer | ce n'est pas le comportement mobile → deux sémantiques à documenter |
| **3** | Pas d'anonyme : compte dès l'entrée | simple | option C de D1, écartée |

**Recommandation : 2, avec une réserve.** `linkIdentity` conserve le `user_id`,
donc le paiement ne « perd » ni les projets ni le solde — ce qui supprime toute
la classe de bugs que le mobile a dû traiter (parking, restore, claim-once,
re-parent de pass). C'est plus simple **et** plus sûr côté argent.

**La réserve** : ça crée deux sémantiques (Web = upgrade sur place, mobile =
Guest séparé parqué). Ce n'est acceptable **que si** on l'écrit noir sur blanc
dans la spec figée comme une variante Web assumée, et non comme une dérive. Sinon
on obtient exactement le « troisième système » qu'on veut éviter.

**Dépendance :** cette décision et U4 se répondent. Si le smoke-test device
tranche U4 = B (upgrade en place), alors mobile et Web convergent naturellement
sur le modèle 2 et la question disparaît. **Le smoke-test U4 (5 min sur device)
devrait être fait avant de coder l'auth Web.**

---

## 4 — ABA : faisabilité et intégration *(depuis zéro)*

### 4.1 — Commercial (le vrai chemin critique)

Aucun compte marchand PayWay/KHQR n'est ouvert et aucun interlocuteur ABA n'est
confirmé. Ce qui est établi publiquement :

- Le produit s'appelle **ABA PayWay**, passerelle d'ABA Bank ; il couvre carte,
  **ABA Pay**, **KHQR**, WeChat Pay et Alipay, en KHR et USD.
- L'onboarding se fait en **contactant l'équipe onboarding PayWay** ; elle
  délivre un **Merchant ID** et une **API Key**. Ce n'est pas un self-service
  type Stripe.
- Un **sandbox** existe : inscription → clés de test envoyées par email.

**Inconnues commerciales à lever auprès d'ABA — elles conditionnent tout le
reste :**

1. Une entité **cambodgienne enregistrée** est-elle exigée (patente, TVA, compte
   ABA professionnel) ? Si Ayden Studio n'a pas encore d'entité KH, c'est le
   point bloquant n°1 et il est long.
2. Les **biens numériques / abonnements** sont-ils acceptés par leur politique
   marchand ? Beaucoup de passerelles locales sont pensées pour du e-commerce
   physique.
3. **Récurrence** : PayWay supporte-t-il un abonnement (tokenisation, débit
   récurrent) ou seulement du paiement unitaire ? Si c'est unitaire seulement,
   le produit Web doit être un **Pass ponctuel**, pas un abonnement — ce qui
   tombe bien, le Billing Engine est déjà un modèle **Pass + quota mesuré**.
4. Frais, délai de **settlement**, procédure de **remboursement**.
5. Devise de facturation et conversion (prix affiché USD ou KHR ?).

### 4.2 — Technique (ce qui est déjà connu et qui s'annonce sain)

| Aspect | Ce qu'on sait | Conséquence pour nous |
|---|---|---|
| Signature | **HMAC-SHA512** + API key, concaténation ordonnée des champs, résultat base64 | vérifiable serveur ; la clé ne doit jamais atteindre le navigateur |
| Création | `req_time, merchant_id, tran_id, amount, currency, payment_option (abapay_khqr), lifetime, hash` | `tran_id` = notre clé métier |
| Notification | **`callback_url`** poussée par PayWay | c'est **là** que l'entitlement est accordé, jamais dans le navigateur |
| Idempotence | **`tran_id` doit être unique — 403 « Duplicated Transaction ID »** | l'unicité est **imposée par ABA**, ce qui nous donne l'idempotence gratuitement si `tran_id` est déterministe |
| Vérification | une **Check Transaction API** existe | permet la réconciliation (l'équivalent de `reconcile_pass_from_subscriber`) |

**Ce que ça implique architecturalement — et c'est une bonne nouvelle :** le
couple `tran_id` unique + callback + check-transaction est **exactement** la
forme que le Billing Engine attend déjà de RevenueCat (`store_transaction_id`
comme clé, webhook comme source, reconcile comme filet). L'adaptateur ABA est
donc un **miroir** de l'adaptateur RC, pas une nouvelle mécanique.

⚠️ **Non vérifié** : la doc technique consultée est une doc communautaire
(`Joselay/aba-payway-docs`) et la page développeur officielle n'a pas répondu.
**Tout ce tableau doit être reconfirmé sur la doc officielle une fois le compte
sandbox obtenu.** Aucun code ne doit s'appuyer dessus avant.

---

## 5 — L'autorité cross-platform, concrètement

Rien à décider — la spec l'a fait. Ce qui reste à **écrire** :

```
ABA callback ──→ adaptateur ABA ──→ grant_purchase(source='aba', tran_id) ──┐
RevenueCat  ──→ adaptateur RC   ──→ grant_purchase(source='rc',  store_tx) ─┤
                                                                            ├→ ledger (append-only)
                                                                            └→ passes → wallet
                                                                                   ↓
                                          resolve_generation_access / try_hold  ← /generate PWA
```

Trois conditions pour que ça tienne :

1. ~~`grant_purchase` doit accepter une source non-RC.~~ **✅ Déjà vrai.** Sa
   signature (`backend/billing.py:747`) est
   `grant_purchase(user_id, provider, provider_transaction_id, store_product_id, …)` :
   `provider` est un paramètre explicite et `provider_transaction_id` est
   générique — la contrainte documentée est seulement que ce soit
   « le transaction_id du CYCLE ». `tran_id` d'ABA remplit exactement ce rôle.
   **Aucune modification de la fonction n'est nécessaire pour brancher ABA** ; il
   faut seulement mapper le produit web dans la table de `_resolve_product`.
2. **Le `user_id` doit être le même objet des deux côtés** → c'est D2.
3. **Le PWA doit appeler les trois points d'insertion** (reserve → hold →
   commit/release) que le mobile appelle déjà. C'est le seul vrai travail
   d'intégration côté génération, et il est borné : l'adaptateur PWA a déjà un
   `intent_id` équivalent (`idempotency_key` + `pwa_generation_claims`).

---

## 6 — Ordre de travail proposé

Conforme à celui validé, avec les dépendances rendues explicites :

| Étape | Dépend de | Note |
|---|---|---|
| 0. Smoke-test **U4** (5 min, device) | — | débloque la spec identité figée ; à faire avant l'auth |
| 1. Décider **D1** (anti-abus) et **D2** (objet identité) | U4 | **produit, pas code** |
| 2. Contact ABA — sandbox + réponses commerciales §4.1 | — | **peut démarrer en parallèle dès maintenant**, c'est le plus long |
| 3. Contrat entitlement Web : schéma billing dans le projet PWA, 3 points d'insertion | D2 | réutilise le Billing Engine, ne le duplique pas |
| 4. Auth Web + `linkIdentity` | D2 | |
| 5. Quota + paywall | D1, 3 | |
| 6. Adaptateur ABA | 2, 3 | dernier, parce qu'il est le plus contraint par l'extérieur |
| 7. E2E staging | tout | |

**Le point 2 est le chemin critique et ne dépend d'aucun code.** Il devrait
partir aujourd'hui.

---

## 6bis — DÉCISIONS ACTÉES (2026-08-12)

### D1 — ACTÉE : `D + E`, sans dégradation de qualité

> **1 WOW gratuit par Guest Web anonyme, QUALITÉ PLEINE + watermark Ayden Studio.
> Paywall ensuite. OTP à la création/upgrade du compte. Pas de fingerprint comme
> autorité. Rate-limit serveur en complément (infra, pas quota métier).**

Nuance retenue par rapport à l'option D telle qu'écrite : **pas de basse
résolution.** Le premier rendu reste le moment WOW ; seul le watermark distingue
le gratuit. Le tier `free(watermark)` de `resolve_generation_access` est réutilisé
tel quel.

### D2 — ACTÉE : modèle 2 (upgrade sur place)

> **Supabase anonymous → `linkIdentity` / `updateUser` → même `user_id`.**
> Projets, Visions, wallet et paiement restent attachés au même utilisateur.
> Retenu **quel que soit le résultat de U4** ; si U4 = A, le modèle 2 est inscrit
> comme **variante Web assumée** dans `GUEST_ACCOUNT_IDENTITY_SPEC.md`, sans
> recréer park/claim/re-parent dans un navigateur pour une symétrie artificielle.

**Conséquence : U4 ne bloque plus le code Web.** Il ne conditionne plus qu'une
formulation de documentation (convergence vs variante). Il reste à faire, mais la
Piste A peut démarrer sans lui.

### Vérifications faites en actant ces décisions

| Point | Résultat |
|---|---|
| `gotrue 2.20.0` (épinglé) expose l'upgrade sur place | ✅ `updateUser`, `signInWithOtp`, `verifyOTP`, `linkIdentityWithIdToken` |
| Projet staging : anonymes activés | ✅ `external.anonymous_users: true` |
| Projet staging : **canal OTP téléphone** | ❌ **`external.phone: false`** |
| Projet staging : email | ✅ `external.email: true` |
| Projet staging : Apple / Google / Facebook | ❌ tous à `false` |

### ⚠️ Blocage sur D1 : le canal OTP choisi n'existe pas encore

D1 spécifie « OTP à la création du compte ». Sur le projet staging, **le provider
téléphone est désactivé** et aucun fournisseur SMS n'est configuré. Activer l'OTP
téléphone suppose :

1. un contrat **fournisseur SMS** (Twilio / MessageBird / Vonage / Textlocal) —
   coût récurrent + délai de compte ;
2. une **délivrabilité SMS au Cambodge** à vérifier (routes internationales,
   sender ID, latence) — c'est un risque produit réel, pas une formalité ;
3. le même travail à refaire sur le futur projet **production** PWA.

**Options :**

| | Canal | Disponible aujourd'hui | Adéquation marché KH |
|---|---|---|---|
| **a** | **Email OTP / magic link** | ✅ immédiat | moyenne (§2.1 : faibles habitudes email) |
| **b** | **Téléphone OTP** | ❌ contrat SMS requis | forte (§2.2 : primitive d'identité locale) |
| **c** | Email d'abord, téléphone ajouté avant production | ✅ | permet de ne pas bloquer la Piste A |

**Recommandation : c.** Coder le paywall contre une **abstraction de canal**, pas
contre « phone ». L'OTP email débloque tout le développement et le E2E staging
immédiatement ; le canal téléphone devient un branchement de configuration une
fois le contrat SMS signé, sans réécrire le parcours.

À noter : **le contrat SMS est, comme ABA, un chemin critique commercial qui ne
dépend d'aucun code.** Il devrait être lancé en même temps.

---

## 7 — Ce que cet audit n'a pas vérifié

Honnêtement listé, pour ne pas être pris pour acquis :

- Que les 9 migrations billing sont **appliquées en production** (lues comme
  fichiers, pas interrogées sur la base).
- Le **RPC** `billing_grant_purchase` lui-même (la signature Python est
  agnostique et vérifiée ; le SQL derrière ne l'a pas été).
- La doc **officielle** ABA PayWay (§4.2 s'appuie sur une source communautaire).
- Les conditions marchand réelles d'ABA (§4.1 est une liste de questions, pas de
  réponses).
- Le statut juridique/fiscal d'Ayden Studio au Cambodge, qui conditionne §4.1.1.
