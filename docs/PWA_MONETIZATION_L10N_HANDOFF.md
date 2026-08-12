# PWA — Billing Engine + localization + Auth/Paywall : état et suite (2026-08-12)

> Suite de `PWA_PARITY_CLOSURE_HANDOFF.md` et de `PWA_MONETIZATION_AUDIT.md`.
> **PHASE A (Billing) : TERMINÉE ET VERTE.** **PHASE B (i18n) : FERMÉE.**
> **PHASE C (Auth + Paywall foundation) : LIVRÉE — voir §5.**

---

## 0 — Où est le code

| quoi | où | branche |
|---|---|---|
| backend + migration doc | `c:/Projects/AIHomeArchitect` | `pwa-monetization` (depuis `89809d6`) |
| app PWA + SQL staging | worktree `c:/Projects/ayden-pwa-web` | `pwa-monetization` (depuis `2fee767`) |
| mobile **GELÉ** | `c:/Projects/AIHomeArchitect/frontend` | detached `f3a6fa2` — **0 modification** |

`pwa-monetization` (backend) est créée depuis **HEAD `89809d6`** et non depuis
`4e3921a` comme l'écrivait le handoff précédent : `acdb1a7` (audit SQL) et
`89809d6` (handoff) n'existaient pas encore quand cette phrase a été écrite, et
partir de `4e3921a` les aurait perdus. Les trois commits d'audit sont dans
l'ancêtre de la branche (vérifié par `git merge-base --is-ancestor`).

Commits :

* `261871a` — `feat(pwa-billing): canonical Billing Engine enforcement on PWA staging` (backend)
* `032c329` — `feat(pwa-billing): canonical Billing Engine schema for the staging project` (worktree PWA)

Aucun `push`. Aucune opération destructive.

---

## 1 — PHASE A : ce qui est fait et prouvé

### Schéma

`supabase/staging/pwa/0006_billing_canonical.sql` — **appliqué** au projet
staging (`eedcahzekpgxvvfxufbk`), idempotent, une transaction, garde GUC.

Installé sous les **noms canoniques** : `sessions` (shell minimal), `user_roles`,
`promo_codes`/`promo_redemptions` + 3 RPC promo, `generation_intents`,
`products`/`orders`/`payments`/`passes`/`ledger_entries`/`wallets`,
`billing_reproject_wallet`, `billing_grant_purchase`, `billing_try_hold` (4-arg).

**Assemblé, pas rejoué** : plusieurs objets canoniques ont été redéfinis par une
migration ultérieure. Le fichier installe l'**état final**. Rejouer l'historique
aurait posé le `billing_try_hold` 3-arg (TRIAL codé en dur à 3) → **3 gratuites
par visiteur Web au lieu d'1**, sans qu'aucun test Python ne le voie.

`public.sessions` : dépendance **mesurée**, pas supposée — sur tout le périmètre
retenu la chaîne `sessions` apparaît **une seule fois**
(`generation_intents.session_id references public.sessions(id)`), la colonne est
nullable, le Web écrit toujours NULL. Donc `id uuid` + `created_at`, rien
d'autre, jamais écrite.

**Exclus volontairement** : `usage_log` (le compteur gratuit EST le bucket free
du ledger — §8.4), `generation_jobs`, les vues d'observabilité, `claim_intent`
mobile, les objets account-mode / RC-transfer. Ces exclusions sont **le marqueur
de production** de `pwa_staging_db.prove_target()` : le périmètre est tenu par
l'outillage, pas par la mémoire.

⚠️ L'ancien marqueur (`generation_intents`, `wallets`, `passes`) devait changer :
0006 les installe **par conception**, donc l'ancien test aurait refusé toute
migration suivante et aurait déclaré « ceci est la production » à propos du
projet qu'on venait de provisionner.

### Intégration

`backend/pwa_staging_billing.py` — la **couture**. Aucun solde n'y est calculé,
aucune ligne de ledger n'y est écrite. Elle possède **une** chose : la
correspondance entre une génération PWA et un Intent de facturation.

```
resolve_generation_access  -> le TIER
billing.reserve_decision   -> gate LECTURE SEULE, AVANT tout appel OpenAI
generation_intents         -> une ligne canonique, session_id = NULL
billing.try_hold           -> le droit atomique de générer
[rendu existant, INCHANGÉ]
observe_intent_end         -> COMMIT / RELEASE
```

`intent_id = "pwa:" + sha256(user_id + ":" + idempotency_key)[:32]` — fonction
pure, donc F5 / retry / restart / 8 requêtes concurrentes tombent sur **le même
intent et un seul débit**. `pwa_generation_claims` reste le single-flight du
**rendu** ; `generation_intents` porte l'idempotence de la **facturation**.

Le gate est placé **au-dessus de l'advisor**, pas seulement au-dessus du rendu :
l'advisor est lui-même un appel gpt-4o payant.

### Free tier

D1 : **1 vision gratuite** par Guest Web anonyme, **même modèle, même quality,
même résolution, même prompt, mêmes règles de source** — seul le watermark
canonique diffère. Le levier est `ACCOUNT_SYSTEM_ENABLED=true` (posé par
`run_pwa_staging.py`), donc `billing.effective_trial_credits() == 1`, passé au
RPC via `p_trial_credits`. **Aucune constante PWA.**

### Deux défauts réels trouvés en écrivant les tests

1. **Un client PAYANT aurait été filigrané.** L'achat d'un pass n'écrit aucune
   ligne `user_roles` (côté mobile ce rôle vient d'un webhook RevenueCat
   séparé), donc le tier reste `free`. Le watermark suit désormais **le pass
   mesuré** autant que le rôle — la règle RC-PR3b : *rôle = features, pass =
   achat*. Épinglé par `BILL05`.
2. **`anon`/`authenticated` avaient TRUNCATE** sur chaque nouvelle table de
   `public` (RLS ne filtre pas TRUNCATE) et **PUBLIC avait EXECUTE** sur les RPC
   promo `SECURITY DEFINER`. Un jeton navigateur pouvait vider `wallets` ou
   s'accorder des générations illimitées. §11 de 0006 applique le durcissement
   canonique (20260707) réduit aux objets présents.

   ⚠️ **Le même trou reste ouvert en PRODUCTION** : `20260707_grants_hardening.sql`
   est dans le dépôt mais **non appliqué**, et il échouerait tel quel ici (il
   révoque sur `usage_log`, `generation_jobs` et 5 vues absentes). **À traiter
   hors de cette phase, sur production, avec le test `backend/sql/tests/`.**

### Preuves

| suite | résultat |
|---|---|
| `backend/pwa_staging_billing_contract_test.py` | **128 checks, 0 échec** (vraie DB staging) |
| `backend/pwa_staging_billing_test.py` | **81 assertions, 0 échec** (vraie DB + vrai ledger) |

Couvre BILL01→BILL11 + Initial / Switch / Refine / Refine structural + watermark
mesuré sur les **pixels** + non-régression moteur (les kwargs de rendu d'une
génération gratuite et d'une payante ne diffèrent que par `watermark`).

### Trois faits à connaître avant de conclure quoi que ce soit

* **`usage_log` absente ⇒ un `log.warning` par génération.** C'est le fail-open
  canonique de `count_active_usage`, et le message est *vrai* : le compteur
  legacy n'est pas là, par décision. Ne pas « corriger » en installant
  `usage_log`.
* **Un user qui a des lignes de ledger ne peut plus être supprimé** : le
  `ON DELETE CASCADE` déclenche un DELETE que le trigger append-only refuse.
  Canonique et correct pour la comptabilité — mais c'est une **contrainte
  d'effacement réelle** à connaître avant de promettre un bouton « supprimer mon
  compte ». Épinglé par `DB14`.
* **Anomalie canonique assumée** : un intent qui échoue (RELEASE) puis réussit au
  retry donne HOLD−RELEASE+COMMIT = net 0. C'est la projection directe de
  `billing._decide`, documentée dans `billing.py`, favorable à l'utilisateur.
  **Ne pas inventer de compensation ici** — ce serait forker le cerveau billing.

### Relance

Backend PWA : `python backend/run_pwa_staging.py` (mono-process, **sans
`--reload`**). Le launcher pose maintenant `ACCOUNT_SYSTEM_ENABLED=true` →
**restart obligatoire** après ce changement.

---

## 2 — PHASE B : fondation complète, sweep principal fait

### Architecture retenue

**Une seule** surface de localisation PWA : `PwaL10n`
(`lib/features/pwa/l10n/pwa_l10n.dart`), accédée par `context.pwaL10n` et, hors
widget, par `pwaL10nFor(locale)`.

Elle résout en deux temps :

1. clés **PWA-only** → `pwa_translations.dart` (177 clés × km/en/fr) ;
2. sinon → **`AppLocalizations` de mobile**, inchangée (424 clés approuvées).

**Aucune chaîne mobile n'a été retraduite.** Le dictionnaire mobile est monté
tel quel (même delegate, mêmes `supportedLocales`), et les getters de reprise de
`PwaL10n` y renvoient. Vocabulaire repris : Vision/ទស្សនៈ, Original,
Redesigns/redesign, espace/ទីកន្លែង, ambiance/បរិយាកាស, filigrane/ស្លាក​ទឹក, les
noms de pièces, les taglines d'atmosphère.

Les **noms d'atmosphère restent en anglais** dans les trois langues — décision
produit mobile explicite (`app_localizations.dart`), préservée et testée.

### Résolution de la langue

`LocaleNotifier` prend un `deviceLocale` **optionnel** :

* mobile n'en passe pas → comportement **byte-identique** (persisté, sinon EN) ;
* la PWA passe `navigator.languages` via un override dans `main_pwa.dart` →
  choix explicite > choix persisté > langue du navigateur > EN.

Même clé de stockage (`ui_locale`), même ensemble supporté : **une seule
préférence**, pas une copie Web. L'indice navigateur n'est **pas** persisté.
Pas de géolocalisation IP.

### Sélecteur

`PwaLanguageSwitcher` — chaque langue écrite **dans cette langue**
(ភាសាខ្មែរ / English / Français), présent dans la barre supérieure. Il ne peut
pas atteindre le contrôleur ni le service de génération (vérifié en test sur la
source).

### Surfaces converties

Home · Create/Entry · Architect · Full Reveal · Projects · Versions sheet ·
Loading/Working indicator · bandeau d'erreur · chips et messages du contrôleur ·
états billing.

**≈160 substitutions** appliquées mécaniquement avec report des non-matchs.

### Chat / advisor (§23)

Le mécanisme canonique existait déjà et n'était **pas branché** : `ui_locale`
traversait `PwaGenerationApi` avec un défaut `'en'` que personne ne surchargeait.
Le contrôleur passe maintenant `ref.read(localeProvider).languageCode` à
`chat()` **et** à `generate()`. Côté serveur, `pwa_chat` appelle `main.chat` qui
localise via `localize_reply` — **aucun second passage de traduction**, aucun
prompt image touché.

### Codes métier, mots côté client (§24)

Le backend renvoie `error_code` canonique (`QUOTA_EXHAUSTED`) **plus** un
`billing_state` fin (`FREE_EXHAUSTED` / `PASS_REQUIRED` / `PASS_EXHAUSTED` /
`BILLING_UNAVAILABLE`). `PwaControllerState` porte désormais
`generationErrorCode` à côté du message anglais, et le bandeau traduit **le
code** — donc un changement de langue pendant qu'une erreur est affichée la fait
changer aussi. Aucune décision billing ne dépend de la locale.

### Tests

`test/features/pwa/pwa_i18n_test.dart` — I18N01→I18N18, dont :

* complétude structurelle des 3 dictionnaires + **égalité des placeholders** ;
* changement immédiat / persistance / F5 / navigation ;
* hiérarchie de résolution (4 cas) + « l'indice navigateur n'est pas persisté » ;
* ids canoniques identiques dans les 3 locales, jamais des clés de traduction ;
* **I18N14/15** : un changement de langue n'écrit que `ui_locale` ;
* **I18N18** : scan de la SOURCE — aucune chaîne de présentation anglaise
  résiduelle hors liste blanche justifiée.

---

## 3 — CE QUI RESTE (ordre conseillé)

1. **Faire passer `flutter analyze` + la suite Flutter complète.** Le sweep a
   été appliqué par substitution : attendre des `const` à retirer et quelques
   sites où `context` n'est pas dans le scope. `I18N18` liste précisément ce qui
   reste à convertir — s'en servir comme liste de travail.
2. **Revue visuelle 3 langues** (KM → EN → FR : Home → Create → Architect →
   Full Reveal → Projects), desktop / tablette / mobile.
   ⚠️ **Piège connu** : onglet caché ⇒ pas de rAF ⇒ le canvas ne repeint pas.
   Forcer un RESIZE avant chaque capture (`cdp.mjs metrics …`), cf.
   `PWA_PARITY_CLOSURE_HANDOFF.md` « Driving the browser ».
3. **⚠️ POLICE KHMÈRE — à vérifier en premier.** Le thème PWA ne charge
   **aucune** police et `pwaDisableRemoteFonts()` coupe google_fonts. Sur
   CanvasKit, les glyphes khmers dépendent du **fallback Noto téléchargé par
   Flutter depuis `fonts.gstatic.com`**. À confirmer visuellement : si des tofu
   apparaissent, les options honnêtes sont (a) renderer HTML (polices système),
   (b) embarquer Noto Sans Khmer — ce que §25 décourage. **Ne pas conclure sans
   avoir regardé.**
4. **Écrans Billing côté UI** : les états `billing_state` sont traduits mais
   aucun écran ne les affiche encore (pas de paywall — c'est la phase suivante).
5. ~~`flutter build web`~~ — **FAIT, vert** : `√ Built build/web` en 145 s,
   bundle 3,68 Mo (contre 3,15 Mo avant : les ~530 Ko de plus sont les trois
   dictionnaires). Toujours avec
   `--release -t lib/main_pwa.dart --dart-define-from-file=.env.pwa-staging.json`
   — **jamais** un `flutter build web` nu (il construirait l'entrypoint mobile
   par-dessus le bundle PWA).

   ⚠️ **Piège de vérification** (m'a fait crier au loup une fois) : chercher
   `ភPHASA` ou `Retour à l'accueil` dans `main.dart.js` renvoie **0**. dart2js
   échappe tout le non-ASCII (`\xe9`, `\u1797`) — les glyphes bruts n'existent
   pas dans le bundle. Les vrais compteurs, mesurés :
   `\xe9` → 434 · `\u17` → 14 424 · `\u1797` → 92. Les trois dictionnaires
   sont bien embarqués. **Chercher la forme échappée, pas le glyphe.**

   Cela ne dit RIEN de la police : que les chaînes soient dans le bundle ne
   prouve pas que CanvasKit sache les dessiner. Le point 3 reste ouvert.

---

## 3bis — REVUE VISUELLE FAITE (2026-08-12) — police + 3 langues

**Rien de ce qui suit n'a été trouvé par un test.** C'est le point de la revue.

### Police khmère — RÉSOLU, mais pas comme prévu

Le renderer est **CanvasKit** (vérifié : un seul `<canvas>` dans le shadow root
de `flt-glass-pane`, `flt-scene-host`, aucun `flt-paragraph`). Il n'utilise pas
les polices système. Flutter télécharge un fallback Noto depuis
`fonts.gstatic.com` — observé pour `notosanssymbols` et `roboto`.

Ça marche, et ça marche **trop tard** : le menu de langue a d'abord peint
ភាសាខ្មែរ en **neuf tofus**, puis s'est corrigé une fois le téléchargement
arrivé. Sur un CDN bloqué ou lent, il ne se corrige jamais.

⚠️ **Piège qui m'a fait crier au loup deux fois** :
1. la 1ʳᵉ capture montrait des tofus — c'était la frame AVANT le download ;
2. bloquer `fonts.gstatic.com` en entier casse **aussi le latin**, parce que
   **Roboto (la police primaire de Flutter Web) vient du même CDN**. Ne jamais
   conclure « le khmer est cassé » depuis ce test-là.

**Fix** : `web/fonts/NotoSansKhmer-Regular.ttf` (114 Ko, SIL OFL 1.1, licence
dans la table `name` de la police), chargé par `FontLoader` avant `runApp`,
enregistré en **fallback** (jamais en famille primaire → latin inchangé).
`web/` n'entre JAMAIS dans le bundle iOS/Android et `pubspec.yaml` n'est pas
touché — c'est tout l'intérêt, le dépôt est partagé avec le mobile gelé.

Le fallback devait aussi être posé **au niveau du thème** : `PopupMenuItem`,
dialogs et autres surfaces en overlay installent leur PROPRE `DefaultTextStyle`
depuis `theme.textTheme`, qui **remplace** l'ambiant. La page était correcte
pendant que le menu restait en tofu.

### Trois autres défauts trouvés à l'œil

* **Noms de pièces en anglais** en khmer et en français. Corrigé : affichage via
  le vocabulaire mobile approuvé, **valeur ROUTÉE inchangée** (label EN
  canonique — la DNA par pièce est keyée dessus). En anglais la carte lit
  maintenant « Master Bedroom » (mot mobile) au lieu de « Bedroom ».
* **Letter-spacing 2.1-2.4 sur les eyebrows** : élégant en latin, il **écarte
  les clusters khmers**. Collapse à 0 en khmer (`pwaTracking`).
* **Dates relatives anglaises** dans une UI française (« 2 days ago ») : elles
  étaient pré-rendues à la désérialisation. Formatées depuis `updatedAt` au
  moment de l'affichage.

Sélecteur de langue ajouté dans **toutes** les barres (il n'était que sur Home).

### Ce qui a été vu (mise à jour — génération réelle en khmer)

Une génération RÉELLE a été lancée en khmer sur le staging (1 vision gratuite
consommée, enforcement billing exercé pour de vrai).

**VU en navigateur, en khmer** : Home · Create (vide ET avec photo) · **écran de
chargement** · **First Reveal** (ដើម / ទស្សនៈ / បន្តជាមួយ Ayden) · **Architect**
(chrome, 4 chips, placeholder, disclaimer) · **My Projects**.
**VU en anglais et en français** : Home (1400 px et 390 px).
**VU** : sélecteur de langue, persistance de la locale après rechargement.

Deux défauts trouvés là et corrigés (commit `45adfa8`) : la phase de chargement
plein écran était en anglais (`repo.loadingSteps()` — liste SÉPARÉE de celle de
l'indicateur de l'architect), et **la première phrase d'Ayden** était en anglais
(`firstVisionIntro`, UI-owned, ne passe pas par `localize_reply`).

### ✅ FERMÉ — revue EN et FR faite (2026-08-12, 2ᵉ passe)

`PwaProjectSort` est corrigé : les quatre libellés passent par
`PwaL10n.sortLabel`, la clé manquante `pwaSortRecentlyUpdated` est ajoutée en
km/en/fr. `PwaProjectSort.label` reste à côté de l'enum comme repli anglais —
**les valeurs de l'enum et la sémantique de tri ne changent pas**. Vérifié à
l'écran : FR « Récemment mis à jour », EN « Recently updated ».

**Parcouru en navigateur** : My Projects et Architect en **anglais** et en
**français** (1400 px), Architect FR en **390 px** (les libellés longs
« Voir la révélation complète » / « Essayer une autre ambiance » tiennent, les
chips passent sur deux lignes, aucun débordement). Le khmer avait été parcouru
à la passe précédente sur une génération réelle. Aucune image payante
supplémentaire n'a été consommée.

Les dates relatives sont localisées partout (« Mis à jour il y a 58 min »,
« Updated 56 min ago », « ធ្វើបច្ចុប្បន្នភាព 14 នាទីមុន »).

### CE QUI RESTE ANGLAIS, ET POURQUOI C'EST VOULU

1. **Données PERSISTÉES** : titre de projet, `roomLabel` résolu, et la phrase
   d'intro d'Ayden sont écrits DANS le projet à sa création. Un projet créé
   avant un changement de langue garde sa langue d'origine. Réécrire une
   conversation stockée parce que la locale change serait pire.
2. **Noms d'atmosphère** (Warm Modern, Soft Luxury…) : décision produit mobile,
   anglais sur toutes les plateformes.

### ⚠️ ITEM INFRA PRÉ-PRODUCTION (hors périmètre i18n)

**Toute l'app dépend de `gstatic.com`** — Roboto ET le wasm CanvasKit — pas
seulement le khmer (le khmer est désormais local). Bloquer `fonts.gstatic.com`
met TOUTE l'interface en tofu, latin compris. À trancher avant un lancement
Cambodge. **Ce n'est pas un bloquant pour Auth/Paywall.**

Rappel : `20260707_grants_hardening` reste **non appliqué en production**.

---

## 4 — INVARIANTS À NE PAS CASSER

* **Mobile `frontend/` reste à `f3a6fa2`** — 0 fichier modifié.
* **Moteur créatif gelé** : aucun changement composer / Refine / Switch / Stage /
  structure. Le billing s'enroule autour de `_generate_claimed`, jamais dedans —
  et un test le prouve en diffant les kwargs de rendu.
* **Pas de second cerveau** : ni billing, ni identité, ni traduction. Une clé
  qui existe côté mobile se **réutilise**.
* **Les ids ne se traduisent jamais** : `living_room`, `warm_modern`,
  `switch_atmosphere`, `refine`, `QUOTA_EXHAUSTED`, `kPwaGenericRoomLabel`
  (sentinelle comparée à des données stockées).
* **Production intouchée** : aucun deploy, aucune migration, aucun accès DB prod.
* **Un seul modèle d'identité** : celui du spec gelé, complété par la mesure D2
  (upgrade-in-place). Les deux parcours restent SÉPARÉS — attacher une identité
  n'est pas se connecter, et se connecter ne transfère RIEN. Pas de troisième
  modèle, pas de migration de données comme contournement.
* **Le client ne décide jamais de l'argent** : pas de compteur local, pas de
  paywall ouvert par un timeout, pas de champ du corps de requête qui achète
  quoi que ce soit. Le ledger tranche, le serveur refuse.
* **Aucun code de paiement spéculatif** : le seam existe, l'implémentation
  n'existe pas, et le paywall le dit.

---

## 5 — PHASE C : AUTH + PAYWALL FOUNDATION (2026-08-12)

### 5.1 La question qui devait être répondue AVANT d'écrire une seule vue

Le spec identité gelé laissait une inconnue (U4) : convertir une session
anonyme en compte réel produit-il le **MÊME** `user_id` (upgrade-in-place) ou un
nouveau ? Sur mobile elle était inrépondable sans device (il faut un vrai
`id_token` Apple). Sur le Web la question est répondable, et elle l'a été
**contre le vrai projet staging** avant toute UI :

    backend/pwa_staging_identity_probe.py      PASS 12 / FAIL 0

* **B2 — `uid_after == uid_before`.** L'attachement d'une identité PRÉSERVE le
  `user_id`. C'est **D2**, mesuré, plus supposé.
* **B5/B6** — la session ouverte alors qu'on était anonyme continue de résoudre
  vers ce même utilisateur, et le compte cesse d'être anonyme.
* **D1/D2** — un e-mail déjà pris se refuse avec un code machine :
  `422 email_exists`. Le second visiteur reste intact et anonyme (**D3**).
* **C1** — le transport client (`updateUser(email)`) est joignable. Le projet
  utilise le **SMTP intégré** de Supabase, dont le quota d'envoi est petit :
  quand il est épuisé l'API répond `429 over_email_send_rate_limit`. **C'est
  une limite d'ENVOI, pas un refus de l'opération d'identité** — l'UI le dit
  comme tel (« trop de codes envoyés »), et un vrai SMTP la supprime.

Conséquence directe sur le code : `beginLinkIdentity` n'a **aucune** étape de
migration, parce qu'il n'y a rien à déplacer. Projets, lignes de ledger et
toutes les policies RLS sont clés sur ce même id.

### 5.2 Les deux parcours, jamais fusionnés

| | attacher une NOUVELLE identité | se connecter à un compte EXISTANT |
|---|---|---|
| transport | `updateUser(email)` + OTP `emailChange` | `signInWithOtp(shouldCreateUser:false)` + OTP `email` |
| `user_id` | **conservé** | **change** |
| ce qui suit | tout (rien ne bouge) | **rien** — pas de quota, pas de ledger, pas de pass, pas de projets |

`PwaEmailOtpChannel.linkNewIdentity` s'ARRÊTE sur `email_exists` et remonte
`destinationAlreadyRegistered`. Ce n'est pas une erreur, c'est une bifurcation :
l'écran l'explique et **la personne choisit**. Aucun basculement implicite —
AUTH05 vérifie que l'autre canal n'a reçu aucun appel.

`identityPreserved` / `switchedAccount` sont **mesurés** (id lu avant et après
`verifyOTP`), jamais déduits du parcours : si GoTrue cessait un jour de
préserver l'id, l'UI cesserait de promettre que le travail a suivi (AUTH04).

### 5.3 Le paywall lit un ÉTAT SERVEUR, jamais un compteur

Nouvel endpoint : `GET /pwa/staging/entitlement` → `can_generate`,
`billing_state`, `tier`, `access_source`, `watermarked`, les trois compteurs,
le catalogue et le seam de paiement. `PwaEntitlement` en fait 8 états, dont les
deux qu'on oublie toujours : **on n'a pas encore demandé** (`loading`) et **on a
demandé sans obtenir de réponse** (`billingError`, qui **échoue OUVERT** — le
serveur refuse de toute façon, et bloquer un client payant sur un paquet perdu
serait pire).

Un 402 est appliqué **immédiatement** (`applyRefusal`) : le refus EST la
nouvelle billing de référence, `billing_try_hold` ayant déjà tranché sous verrou
consultatif. Attendre un aller-retour ferait arriver le paywall en retard.

**Seul un refus de facturation ouvre un paywall** (`isBillingRefusal`) — un
timeout ou un backend injoignable ne doit jamais ressembler à une vente.

### 5.4 §10 / §11 — ce que le catalogue canonique dit vraiment

Lu, pas inventé (`GET /pwa/staging/entitlement` sur staging réel) :

* `pack_10 / 25 / 50 / 100` — CREDIT_PACK, `khqr_enabled`, **aucun** id store →
  `web_enabled: true`.
* `weekly_pass` (30 crédits / 7 j / $7.99) et `annual_pass` (300 / 365 j /
  $79.99) — **PASS portant des ids Apple/RevenueCat** → `store_only: true`. Le
  Web ne peut pas les vendre ; le paywall le dit (« Disponible dans
  l'application mobile ») au lieu de sous-entendre un checkout inexistant.

**Découverte à ne pas perdre** : `orders_provider_check` et
`payments_provider_check` n'autorisent que `('revenuecat', 'khqr')`. **Il n'y a
pas d'`aba`.** Brancher un provider web n'est donc pas « un adaptateur » : c'est
**une migration + un adaptateur**. Le schéma canonique a un avis sur qui peut
encaisser.

Aucun code ABA n'a été écrit (§11) : `PwaPaymentProvider` est une interface, et
la seule implémentation, `PwaUnconfiguredPaymentProvider`, répond honnêtement
« pas disponible ». Le serveur possède la vérité (`payment.provider` /
`payment.configured`), pas le navigateur. PAY09 relit le fichier source pour
qu'aucune bonne intention n'y glisse du code de paiement écrit d'après des docs
communautaires.

### 5.5 §12 — post-paiement sans faux paiement

`backend/pwa_staging_seed_pass.py` (CLI, service-role, **inaccessible depuis le
navigateur**) appelle la RPC canonique `billing_grant_purchase` — celle du
webhook RevenueCat et du futur callback ABA. Le pass obtenu est **réel** : ligne
`passes`, crédit append-only, projection wallet, résolu par le même
`billing_try_hold` que le rendu. Mesuré : `wallet 30`, `active passes 1`.
`--revoke` fait expirer (`ends_at` dans le passé), il ne supprime rien : le
ledger est append-only par construction.

Détail appris en le faisant : un pass est « actif » pour la projection
canonique quand `status = 'ACTIVE'` **et** `now() between starts_at and
ends_at`. Il n'y a pas de colonne `expires_at` ni `credits_remaining` sur
`public.passes` — les crédits vivent dans le ledger, pas sur le pass.

### 5.6 §17 — prouver qu'on ne peut pas générer sans payer

    backend/pwa_staging_enforcement_probe.py   PASS 22 / FAIL 0

Contre le backend qui tourne, en HTTP réel, avec une vraie identité Supabase :

* **ENF01/02/03** — sans token, avec un token forgé : refusé. L'entitlement
  aussi.
* **ENF06/07** — une fois le crédit gratuit dépensé : `402 QUOTA_EXHAUSTED`,
  `billing_state: FREE_EXHAUSTED`, `render_started: false`.
* **ENF08** — huit mensonges différents dans le corps de la requête (tier
  premium, pass actif, solde, `access_source`, `watermark:false`,
  `billing_state`, `user_id`, `intent_id`) : **huit refus**. Le corps n'est pas
  une entrée de la décision ; le ledger l'est.
* **ENF10** — se réclamer d'un autre `user_id` ne change rien : le serveur lit
  le JWT.
* **ENF11** — la route de lecture n'invente ni état ni image.

**Ordre des refus, constaté** : propriété du projet (`PROJECT_NOT_FOUND`) puis
namespace Storage (`PATH_FORBIDDEN`) **avant** la facturation. Les deux sont des
refus ; la sonde lève les deux premières objections précisément pour pouvoir
mesurer la troisième.

### 5.7 Où vivent les nouvelles pièces

| rôle | fichier |
|---|---|
| abstraction de vérification (transport-agnostique) | `lib/features/pwa/auth/pwa_verification_channel.dart` |
| adaptateur EMAIL OTP (seul fichier qui connaît GoTrue) | `lib/features/pwa/auth/pwa_email_otp_channel.dart` |
| règles d'identité, un seul endroit | `lib/features/pwa/auth/pwa_auth_service.dart` |
| état billing structuré | `lib/features/pwa/billing/pwa_entitlement.dart` |
| lecture serveur + politique de refresh | `lib/features/pwa/billing/pwa_entitlement_controller.dart` |
| seam de paiement (volontairement vide) | `lib/features/pwa/billing/pwa_payment_provider.dart` |
| paywall | `lib/features/pwa/presentation/pwa_paywall.dart` |
| feuille compte | `lib/features/pwa/presentation/pwa_account_sheet.dart` |
| puce compte (jamais une barrière, §8) | `lib/features/pwa/presentation/pwa_account_chip.dart` |
| endpoint + catalogue + seam serveur | `backend/pwa_staging_api.py`, `backend/pwa_staging_billing.py` |

### 5.8 Tests

| suite | résultat |
|---|---|
| `pwa_staging_billing_contract_test.py` (contrat DB) | **128 checks, 0 échec** |
| `pwa_staging_billing_test.py` (enforcement billing) | **81 assertions, vertes** |
| `pwa_staging_adapter_test.py` (parité adaptateur) | **278 assertions, vertes** |
| `pwa_staging_identity_probe.py` (identité, staging réel) | **12/12** |
| `pwa_staging_enforcement_probe.py` (§17) | **22/22** |
| `pwa_auth_paywall_test.dart` (AUTH01-15 + PAY01-11) | **26 tests** |
| suite Flutter complète | **1071 tests, 0 échec** |
| `flutter analyze lib` | **No issues found** |
| `flutter build web --release` (staging) | **vert** |

### 5.8bis REVUE VISUELLE — ce qui a VRAIMENT été vu dans un navigateur

Dit précisément, parce que « revue faite » sans périmètre ne vaut rien.

**Vu, capturé, dans le vrai build staging servi sur `127.0.0.1:8104` :**

* **EN / desktop 1400×1000 — feuille compte** : titre, corps, champ e-mail,
  « Send code » (désactivé tant que l'adresse est vide, ce qui est correct),
  et « Sign in to that account ». Rien de coupé, rien qui déborde.
* **EN / desktop — PAYWALL, avec de vraies données** : « Your free vision is
  used », l'encart « Payments are not open yet », le catalogue canonique
  (10/25/50/100 spaces à $1.99/$3.99/$6.99/$11.99), le weekly pass à $7.99
  marqué « Available in the mobile app », **et aucun bouton d'achat**.
* **KM / desktop — écran d'accueil complet en khmer** : barre supérieure,
  héros, CTA, carte projet, dates relatives. **Aucun tofu.** La police
  embarquée fait son travail hors ligne.

**Défaut trouvé et corrigé pendant cette revue** : le serveur trie le
catalogue par prix, ce qui plaçait le pass mobile-only à $7.99 ENTRE les packs
web à $6.99 et $11.99 — une échelle de prix avec un trou dedans.
`productsForDisplay` groupe désormais « ce que le web peut vendre » avant
« ce qu'il ne peut pas ». Test : PAY08.

**NON obtenu en navigateur** : les captures KM/FR des DEUX nouvelles feuilles.
Le pilotage par coordonnées a fini par dériver (Chrome accumule les overrides
`setDeviceMetricsOverride` et finit par composer des tuiles répétées), et la
position de la puce compte change avec la locale parce que les libellés
voisins n'ont pas la même largeur. **Ce n'est pas un défaut du produit ; c'est
la limite de l'outillage de cette session.** Ce qui couvre malgré tout les
trois langues sur ces surfaces :

* **PAY10** monte le vrai `PwaPaywallSheet` en km / en / fr et vérifie les
  chaînes exactes (titre d'état, encart paiement, prix) **et** l'absence de
  bouton d'achat ;
* **PAY11** vérifie que les trois dictionnaires portent tout le vocabulaire
  paywall + compte ;
* **I18N01-18** (phase B, déjà fermée) verrouille la complétude structurelle
  et l'absence d'anglais résiduel dans les surfaces auditées.

Pour finir la revue à l'œil en KM/FR : redémarrer Chrome (override propre),
`localStorage.setItem('flutter.ui_locale', '"km"')`, recharger, puis cliquer
la puce compte à la main. C'est cinq minutes de souris, pas du code.

### 5.9 Piloter le navigateur : deux pièges mesurés

En plus du piège rAF déjà documenté (onglet non redimensionné ⇒ pas de repaint) :

0. **Chrome dérive.** Après beaucoup d'`Emulation.setDeviceMetricsOverride`
   successifs, le compositeur finit par renvoyer des captures en tuiles
   répétées et une largeur qui n'est plus celle demandée. Symptôme : la capture
   ne ressemble à AUCUN état de l'app. Remède : `clearDeviceMetricsOverride`,
   ou un onglet neuf. Ne pas conclure « bug de layout » sur une telle image.
1. **Il n'y a pas de DOM adressable.** Flutter ne construit l'arbre sémantique
   qu'après un geste qu'il accepte comme signal d'accessibilité ; un `.click()`
   synthétique sur le `flt-semantics-placeholder` (1×1, hors écran) n'en est pas
   un. La revue clique donc des **coordonnées mesurées** et vérifie par capture.
2. **La position d'un contrôle dépend de la LOCALE** : la barre supérieure est
   alignée à droite, donc la puce compte se déplace selon la largeur des
   libellés khmers ou français. Une coordonnée codée en dur ne marche que pour
   la langue où elle a été mesurée.
3. **Le premier appui après une navigation ne touche aucun widget** — il est
   consommé par la prise de focus du canvas. Toute interaction doit être envoyée
   **deux fois**, la capture suivant la seconde.

### 5.10 Ce qui reste ouvert, nommément

1. **Aucun provider de paiement.** C'est l'état correct aujourd'hui, pas un
   trou : le paywall affiche « les paiements ne sont pas encore ouverts ». Pour
   ouvrir : migration du CHECK provider + adaptateur `PwaPaymentProvider` +
   `PWA_PAYMENT_PROVIDER` côté serveur. **Rien à changer dans les widgets.**
2. **SMTP staging** — quota intégré épuisé ⇒ `429` sur l'envoi. Configurer un
   vrai expéditeur pour tester un OTP de bout en bout dans un navigateur.
3. **PHONE OTP** — `PwaVerificationChannel` existe pour ça ; le Cambodge le
   voudra. Écrire un second adaptateur, ne toucher à aucune vue.
4. `20260707_grants_hardening` reste **non appliqué en production**.
