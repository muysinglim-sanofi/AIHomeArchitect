# PWA — Billing Engine + localization : état et suite (2026-08-12)

> Suite de `PWA_PARITY_CLOSURE_HANDOFF.md` et de `PWA_MONETIZATION_AUDIT.md`.
> **PHASE A (Billing) : TERMINÉE ET VERTE.** **PHASE B (i18n) : fondation
> complète + surfaces principales converties ; reste la revue visuelle et le
> passage final.**

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

### Ce qui a été vu, et ce qui ne l'a pas été

**VU en navigateur** : Home KM/EN/FR (1400 px), Home KM et FR (390 px), Create
en KM, le sélecteur, la persistance de la locale après rechargement complet.

**PAS VU faute d'un projet sous le guest courant** (localStorage vidé pendant
l'enquête police → nouvel anonyme → bibliothèque vide) : **Architect, Full
Reveal, My Projects, l'état de chargement et les états billing en KM et FR**.
Ces surfaces ont été vues **en anglais** en début de session avec les nouvelles
chaînes. Elles sont couvertes par `I18N05-10` et `I18N18`, mais **une revue
visuelle KM/FR de ces quatre écrans reste à faire** — il suffit de créer un
projet (1 génération gratuite) et de refaire la boucle.

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
