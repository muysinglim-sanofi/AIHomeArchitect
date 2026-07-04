# Refine Engine V2 — Multi-change execution

> **Statut : BACKLOG · HORS-MVP · Moteur 2 uniquement.** Document fondateur (pas de code).
> Objectif : exécuter FIDÈLEMENT plusieurs modifications demandées dans un même
> message de refine, sans jamais toucher le Moteur 1 (gelé).

---

## 0 — Frontière d'architecture (RAPPEL — non négociable)
Cf. mémoire `two-engine-frozen-zone`. Le projet a **deux moteurs** :

```
V1  →  Vision générée  →  Chat Refine  →  Nouvelle vision
└────────── MOTEUR 1 (GELÉ) ──────────┘   └── MOTEUR 2 : ce document ──┘
```

**INTERDICTION ABSOLUE** dans ce chantier : V1 generation · V1 DNA · V1 prompt ·
Structural Identity · Architecture preservation · Atmosphere Switching (prompt +
pipeline) · MOBILE_MVP_BASELINE · **gpt-image-2 low config** · Preserve mode ·
tous les benchmarks V1 validés. Même si ça « semble » aider le refine.

---

## 1 — Promesse produit (le « pourquoi »)
Quand l'utilisateur écrit :
> « Move the TV. Rotate the sofa. Remove the table. »

il attend que **les TROIS** soient réalisés. C'est une **fonctionnalité fondamentale**
d'Ayden (« un vrai architecte exécute toutes tes demandes »), pas un bonus.

Règle produit : **« Everything explicitly requested MUST change ; everything not
explicitly requested MUST remain unchanged. »** (Preserve = protéger le non-demandé,
JAMAIS bloquer le demandé.)

---

## 2 — Ce qui est PROUVÉ (fondations de ce chantier)
Audit + bench PR0 (2026-07-04) :

1. **Pas un bug de routing / perte de texte / compactage.** Les instructions
   arrivent **verbatim** au prompt OpenAI sur LAYOUT/LOCAL (`(1)(2)(3)` via
   `edit_intent._split_changes`). `edit_block` est P1, jamais tronqué.
2. **Le wording du prompt N'A AUCUN EFFET.** Bench PR0 : 4 formulations (A actuel ·
   B « Mandatory + Locked » · C « success only if » · D « mandatory requirement »)
   × {gpt-image-2 **low**, **medium**} = **8 générations → toutes 1/3 appliqué**,
   même sous-ensemble (restyle réussi, remove + add ignorés). Reformuler « PRESERVE »
   en « LOCKED ELEMENTS », insister « ALL MUST be applied », etc. → **zéro gain**.
   Medium ne suit PAS mieux la checklist que low. **PR0 = succès : le prompt n'est
   PAS le levier.**
3. **La vraie cause = le modèle.** gpt-image-2 (low ET medium) **sous-applique les
   refines multi-changements** : il exécute le changement facile (restyle) et ignore
   les plus coûteux (remove, add), quelle que soit l'insistance du prompt.
4. **Contradiction preserve↔change dans le prompt actuel** (LAYOUT « move-only /
   every-other-unchanged » vs « remove » ; LOCAL « pixel-identical / don't-shift » vs
   « move ») — réelle, mais **secondaire** puisque le wording ne bouge pas le résultat.

Caveats bench : n=1 par version, 1 scénario (remove+restyle+add), scoring vision
gpt-4o-mini — mais 8 tirages indépendants sur le même 1/3 = signal fort.

---

## 3 — La vraie question (≠ prompt)
> **Comment exécuter N modifications avec un modèle qui n'en réalise naturellement qu'une ?**

C'est un problème d'**orchestration**, pas de rédaction. Le refine cesse d'être
« une phrase envoyée à GPT » et devient « **un moteur qui pilote GPT** ».

---

## 4 — Architecture cible proposée
```
User message
    ↓
Intent Parser        → extrait la liste structurée des changements
    ↓
Requested Changes[]  → [ {type:move, obj:TV, target:right wall},
                         {type:rotate, obj:sofa, target:face TV},
                         {type:remove, obj:dining table} ]
    ↓
Conflict Resolver    → détecte incompatibilités / dépendances / ordre
    ↓
Execution Planner    → décide la STRATÉGIE (voir §5)
    ↓
Image Executor       → 1..N appels images.edit (Moteur 2 isolé)
    ↓
Final Image (+ log par changement : appliqué O/N)
```
Bénéfices d'une représentation structurée (au-delà de l'exécution) : vérifier les
conflits, **compter** les changements, **logger** par-changement, **expliquer** les
modifs à l'user, **mesurer** la qualité (score « N/N appliqués »).

---

## 5 — Stratégies d'orchestration à explorer (choix d'archi, à bencher)
Aucune n'est tranchée. Chacune a son propre Phase-0-style bench.
- **A. Génération séquentielle** : 1 edit par changement, chaîné (remove → recolor →
  add). Chaque edit isolé, le modèle sait le faire. **Risques (déjà observés)** :
  **drift** (gpt-image-2 low régénère la scène → 3 edits chaînés dérivent ;
  medium préserve mieux), **coût ×N**, **latence ×N**.
- **B. Regroupement intelligent** : grouper les changements **compatibles** en un
  seul appel (ex. 2 déplacements), séparer les incompatibles (remove seul). Réduit N.
- **C. Autre orchestration** (masques par région, edit local ciblé, best-of-N +
  scoring vision qui garde la sortie la plus complète, etc.).

**Prochain pas quand ce chantier ouvrira** : bencher **A séquentiel** (drift low vs
medium, coût, latence, % changements appliqués) sur les 6 cas de référence — même
méthode disciplinée que PR0 (mesure avant décision).

---

## 6 — Cas de référence (6)
1. Move TV to right wall + rotate sofa to face it.
2. Remove dining table + add large rug + add curtains.
3. Break/open a wall + keep kitchen layout.
4. Add partition wall + move bed.
5. Make room warmer + replace chandelier + add plants.
6. Put sofa in front of TV + preserve window view.

---

## 7 — Interdictions (rappel)
Toute proposition touchant V1 / Switch / DNA / Architecture engine / Preserve engine
/ Structural identity / Prompt V1 → **refusée**, même si elle améliore le refine.
Le chantier **s'arrête au refine** (Moteur 2).

---

## 9 — ARCHITECTURE PRODUIT DÉFINITIVE (VALIDÉE user 2026-07-04) — à implémenter
Le benchmark (17/20 complets, structure 5/5, 0 drift identité) a prouvé la **FAISABILITÉ**
technique du multi-change orchestré. **MAIS le séquentiel-par-défaut est REJETÉ** : il violait
le contrat fondateur d'Ayden.

> **CONTRAT NON NÉGOCIABLE : 1 action utilisateur = 1 génération = 1 image affichée.
> Aucune génération cachée. AUCUN retry automatique. Retry uniquement sur décision explicite
> de l'utilisateur.** Moteur 2 uniquement.

### Flux
```
Message
  → 1. PARSER            → Change[] typés { type, object, detail, raw }
  → 2. NORMALIZER        → instruction crisp par changement (désambiguïse "Move")
  → 2.5 CONFLICT RESOLVER → résout les incohérences inter-changements (remove X + add-sur-X…)
  → 3. SMART PLANNER     → ExecutionStrategy (aujourd'hui : UN prompt combiné, tous les changements)
  → 4. UNE GÉNÉRATION GPT-Image (config refine, low)   ← la SEULE consommée par défaut
  → 5. AFFICHER TOUJOURS l'image                        ← elle appartient à l'user
  → 6. VERIFY (invisible, GRATUIT — vision gpt-4o-mini, PAS une génération) → 3 états :
        ├─ VERIFIED                 → ✅ terminé (aucun rapport, image seule)
        ├─ INCOMPLETE               → rapport Applied/Missing + décision user
        └─ VERIFICATION_UNAVAILABLE → « Ayden couldn't automatically verify this result »
                                       (JAMAIS « tout appliqué ») ; image montrée ; retry = tout
             Applied            Still missing
             ✓ Flowers          □ Move TV
             ✓ Champagne
             [ Keep this version ]   [ Retry missing changes · uses 1 AI generation ]
  → 7. RETRY (OPT-IN) → SI l'user clique : le pipeline SÉQUENTIEL du benchmark s'active,
       UNIQUEMENT sur les changements manquants, +1 crédit consenti, chaque image montrée.
```

### Composants
1. **Parser** — message → liste typée (move/add/remove/replace/modify/structure).
   **LLM gpt-4o-mini + fallback déterministe** (`edit_intent._split_changes`).
2. **Normalizer** — réécrit chaque changement en instruction non ambiguë, surtout **Move**
   (« move the TV » → « move the TV to the opposite wall »).
2.5. **Conflict Resolver** — résout les incohérences inter-changements (remove X + add-sur-X, etc.).
   → détail **§12.1**.
3. **Smart Planner** — émet une **ExecutionStrategy** (aujourd'hui : UN prompt combiné optimal,
   tous les changements). Seam d'extension → **§12.3**.
4. **1 Génération** — `images.edit`, config refine **gpt-image-2 low** (P1). **N'appelle JAMAIS
   le composer V1 / DNA / preserve.** Toujours **1 seul appel** par défaut.
5. **Afficher toujours** — l'image est montrée quoi qu'il arrive (transparence : toute gen
   consommée appartient à l'user).
6. **Verify — GRATUIT & invisible** — vision gpt-4o-mini (~$0.0001, **PAS une génération** →
   c'est ce qui permet la transparence sans casser « 1 action = 1 gen »). **3 états** (VERIFIED /
   INCOMPLETE / VERIFICATION_UNAVAILABLE — jamais « tout appliqué » en cas d'échec, **§12.2**). 3 scores :
   - `applied` par changement · `identity_preserved` (**cadrage/caméra IGNORÉS**, drift composition = OK)
   - `naturalness` — si artefact visible → **message DOUX (P4)** : « Ayden noticed this version
     may need refinement. » (jamais de jargon technique).
   - **Structure : vérif durcie** (mur réel vs simple recomposition).
   - Rapport affiché **uniquement si incomplet (P3)** ; si tout OK → rien, image seule.
7. **Retry — OPT-IN uniquement (P2)** — un seul bouton **« Retry missing changes · uses 1 AI
   generation »**. Au clic : le **pipeline séquentiel du benchmark** s'active, appliqué **aux
   seuls changements manquants**, chaque image **montrée**, **+1 crédit consenti**. **JAMAIS de
   retry automatique. JAMAIS de génération cachée.**

### Le benchmark = moteur de RETRY (pas le défaut)
La séquentielle validée (17/20, structure 5/5) n'est PAS jetée : elle est **réservée au clic
Retry**, là où l'user a explicitement accepté le coût. **Défaut = 1 gen ; Retry = pipeline intelligent.**

### Facturation (le contrat, câblé-désactivé — D4)
1 refine = **1 crédit** (reserve→commit). Retry = **+1 crédit consenti d'avance** (le bouton le
dit). **Zéro crédit caché** ↔ chaque crédit = une image montrée. Hook **CÂBLÉ mais DÉSACTIVÉ**
(no-op) tant que Billing enforce n'est pas branché. Cf. [[billing_engine_v1_direction]].

### Intégration (isolation dure — D2 ; D-a/D-b/D-c VALIDÉS user 2026-07-04)
**Nouvel endpoint `/refine` isolé** : NE touche JAMAIS `/generate` V1 ni le composer.
- **D-a — Frontière par INTENTION, pas par nombre de changements.** `/generate` = **créer une
  nouvelle vision** ; `/refine` = **modifier une vision existante**. **TOUTE** modification d'une
  image existante passe par `/refine`, qu'il y ait **1 ou N** changements (Add TV · Move TV ·
  Move TV + Flowers · Remove table → tous `/refine`). Le frontend ne compte pas les changements
  (« je veux raffiner cette image ») ; **le backend décide** (Advisor, Planner, retry…).
- **D-b — Contrat de réponse UNIQUE** (un seul endpoint, un seul schéma), discriminé par `status` :
  ```
  status = "advisory"   → { status, advice:{overall, message, flagged[]}, echo:{changes, room_type} }
                          (AUCUNE image — YELLOW/RED ; l'user relance en confirmant)
  status = "completed"  → { status, image_url, report|null, verification, missing[], mode, conflicts[] }
                          (GREEN → 1 génération faite, image montrée)
  status = "error"      → { status, error }
  ```
  Relance **stateless** : le frontend renvoie les `changes` (echo) avec `confirm=true` pour passer
  outre un advisory, ou les `missing` pour un retry — le backend ne garde pas d'état de session refine.
- **D-c — UX advisory SIMPLIFIÉE (jamais de modification implicite de la requête)** :
  - 🟢 GREEN → rien, génération directe.
  - 🟡 YELLOW → « This may be difficult to achieve. Try anyway? » · boutons **[Continue]** / **[Edit request]**.
  - 🔴 RED → « As your architect, I don't recommend… » (+ alternative) · boutons **[Continue anyway]** / **[Edit request]**.
  - **« Do the sensible ones » SUPPRIMÉ** : l'app ne droppe JAMAIS un changement en douce. L'user
    reste **maître de sa requête** : soit il continue (TOUT, y compris le risqué), soit il édite.
- Frontend = appel + UI (advisory card OU image + rapport ✅/□ + boutons Keep / Retry) — pas moteur.

### QA — Golden Benchmark (régression permanente)
Les **20 scénarios** (`qa_refine_benchmark.py`) = **golden benchmark**, rejoués à CHAQUE
modification du moteur Refine ; le taux (complets N/N + % changements + 0 drift identité +
naturalness) **ne doit jamais baisser**.

### Décisions VALIDÉES (user)
- **P1** génération par défaut = **low** (medium = Premium futur).
- **P2** Retry = **« Retry all missing »** (1 bouton, séquentiel derrière sur les seuls manquants).
- **P3** rapport Verify **visible seulement si incomplet** (Applied ✓ / Still missing □).
- **P4** Naturalness = message **doux** (« may need refinement »), pas de jargon.
- **D2** endpoint `/refine` isolé · **D4** billing câblé-désactivé.

### Ordre d'implémentation (composant par composant, golden-bench vert avant chaque commit)
Parser → Normalizer → Smart Planner → 1-gen executor + affichage → Verify (gratuit) + rapport →
Retry engine (séquentiel opt-in) → Billing hook (désactivé) → Frontend (UI + boutons Keep/Retry).

## 10 — Smart Planner (design FIGÉ, validé user 2026-07-04)
### Rôle
Cerveau d'orchestration. **Ne touche pas aux images.** `Change[] → ExecutionPlan`
(ordre + groupement + stratégie retry). **Le défaut est TOUJOURS 1 génération** (contrat) :
le Planner ne splitte pas le défaut ; son analyse sert à ORDONNER le prompt, PRÉDIRE si
1 gen suffira, et PILOTER le retry.

### Entrée / Sortie
- **In** : `Change[]` (Parser) + contexte `{mode: default|retry, missing: Change[] (si retry)}`.
- **Out** : `ExecutionPlan` = `ordered_changes` · `compatibility` (par-changement :
  `combinable|isolate`) · `default_prompt_spec` (le prompt combiné unique, ordonné) · `retry_policy=R1`.

### Matrice de compatibilité (VALIDÉE, ancrée benchmark)
| Type | 1-gen (bench) | Classe |
|---|---|---|
| ADD · REMOVE · MODIFY | 3/3 · 3/3 · ok | **combinable** |
| REPLACE | 2/3 | **combinable, à surveiller** (masse principale) |
| MOVE | **1/3** — les moves se concurrencent | **isolate** (≤ 1 move fiable/gen) + **emphase** |
| STRUCTURE | 5/5 solo — recompose le canevas | **isolate / EN PREMIER** |

### Ordre du prompt (VALIDÉ)
```
STRUCTURE → REMOVE → REPLACE → ADD → MODIFY → MOVE
```
STRUCTURE d'abord (change le canevas, les meubles s'éditent ensuite dessus) · **REPLACE avant
ADD/MODIFY** (remplacer une masse principale — canapé/table — avant les ajouts décoratifs) ·
**MOVE en dernier + mis en emphase** (le plus fragile).

### Retry policy = R1 (VALIDÉ ; R2 rejeté)
**1 clic = 1 génération = 1 crédit = 1 image affichée.** Refine initial = 1 gen (tous les
changements). Incomplet → rapport Applied/Missing. « Retry missing changes » = **1 gen CIBLÉE
sur les seuls manquants** (prompt focalisé → meilleure réussite). Encore incomplet → nouveau
rapport → l'user re-décide. Le « séquentiel » émerge **entre les clics** (chaque clic cible
moins de changements). **JAMAIS 1 clic = N crédits.**

### Interaction avec le Normalizer
1. **Planner** décide l'ordre + la compatibilité + le mode (default/retry).
2. **Normalizer** produit, pour chaque changement, **une instruction crisp** — utilisée en
   **par-changement** (gens ciblées / retry) ET assemblée en **combiné** (défaut).
3. **Planner** assemble le prompt final (changements normalisés, ordonnés) + la clause **Locked elements**.
→ Le Normalizer doit donc fournir les **deux formes** ; son design découle de ce Planner.

## 11 — Normalizer (design FIGÉ, validé user 2026-07-04)
**Rôle** : `Change → change.normalized` (str) — une **instruction single-edit crisp**. Valeur =
donner au modèle une **CIBLE/SCOPE concret** (pas de l'emphase seule — PR0). **UNE seule forme**
sert les deux usages (retry par-changement ET item de checklist combiné ; le Planner l'enveloppe).

**N1 — 100% DÉTERMINISTE** (pas de LLM ici : prévisible, testable, stable ; pas besoin de l'image).

### Règles par type (VALIDÉES)
| Type | normalized |
|---|---|
| **MOVE** sans cible | « Reposition <obj> **onto a different wall, clearly away from its current spot** » (**N2**) |
| **MOVE** rotate sans cible | « Rotate <obj> **to face the opposite direction** » |
| **MOVE** avec cible | garde la cible (« Reposition the TV onto the right wall ») |
| **REMOVE** | « **Completely remove** <obj>**, leaving that floor area empty** » (**N3**, contre-préservation) |
| **REPLACE** | « Replace … **in the same position** » (**N3**, garde la masse) |
| **ADD** sans lieu | placement par objet : flowers/books/décor → « **on the coffee table or main visible surface** » · rug → « on the floor under the main seating » · plant → « in a corner » · lamp → « in a corner / on a side surface » · art/mirror → « on the main wall » · curtains → « on the window » · défaut → « on the coffee table or main visible surface » |
| **ADD** avec lieu | conservé tel quel |
| **MODIFY** | expansion courante (warmer/darker/brighter → palette/lighting) ; sinon conservé |
| **STRUCTURE** | expansion (« open the kitchen » → « …by removing the dividing wall, keeping the units in place ») ; sinon conservé |

### Ne fait PAS
Pas de regroupement/ordre (Planner) · pas de clause Locked (Planner) · juste 1 changement → 1 instruction claire.

## 12 — Ajustements post-build (VALIDÉS user 2026-07-04, LIVRÉS + testés)
Trois corrections d'architecture apportées après revue du moteur backend (composants isolés,
Moteur 2 ; aucun contact V1/composer/DNA/preserve).

### 12.1 — Conflict Resolver (nouveau composant : Normalizer → **Conflict Resolver** → Planner)
`refine/conflict.py`. Le smoke a prouvé que le conflit n'est **PAS rare** : « remove coffee
table + add flowers » faisait écrire « add flowers **on the coffee table** ». On résout ces
incohérences **au niveau du pipeline**, plus jamais en cas particulier. 100 % déterministe, idempotent.
| Règle | Conflit | Résolution |
|---|---|---|
| **R-A / R-E** | REMOVE/REPLACE/STRUCTURE-remove **X** + ADD *sur X* | re-placer l'ADD (surface neutre ; « on a remaining wall » si mur supprimé) |
| **R-B** | REMOVE **X** + MOVE **X** | droppe le MOVE (pas de fantôme déplacé) |
| **R-C** | MOVE **X**→A + MOVE **X**→B | garde le dernier |
| **R-D** | REPLACE **X** *(in the same position)* + MOVE **X** | retire « in the same position » |
Sortie : `(changes nettoyés, conflicts: list[str])` → `RefineOutcome.conflicts` (log/transparence).

### 12.2 — Verify à **3 états** (fin du « fail-open menteur »)
`refine/verify.py`. Sur échec de vérif, on ne prétend **PLUS** « tout appliqué ».
| `VerifyStatus` | Sens | Rapport |
|---|---|---|
| **VERIFIED** | tout appliqué | None (image seule, P3) |
| **INCOMPLETE** | vérif OK, certains manquent | Applied ✓ / Still missing □ |
| **VERIFICATION_UNAVAILABLE** | la vérif a échoué | « Ayden couldn't automatically verify this result. » |
- Un changement **non confirmé** (vision tronquée) est compté **MANQUANT**, jamais « appliqué ».
- `complete = (status == VERIFIED et pas de souci naturalness)` → UNAVAILABLE ⇒ jamais complet.
- `RefineOutcome.retry_targets` : manquants (INCOMPLETE) · **tous** (UNAVAILABLE — on ignore ce qui manque) · rien (VERIFIED).

### 12.3 — Planner → **ExecutionStrategy** (seam d'extension)
`refine/planner.py`. Le Planner sort une **ExecutionStrategy**, pas juste un prompt. Comportement
identique aujourd'hui (`STRATEGY_COMBINED_EDIT` = 1 gen, checklist + Locked), mais la porte reste
ouverte **sans re-refactorer** : `full_redesign` (« make it a luxury villa »), `atmosphere_switch`
(« transform into Japandi » → route vers le switch existant), `sequential_forced`. Points d'extension :
`_choose_strategy()` (décision) + `engine._execute_strategy()` (exécution, branche sur `strategy.kind`).
`ExecutionPlan.combined_prompt` conservé (property → `strategy.prompt`) pour compat.

## 13 — Request Advisor (design FIGÉ, validé user 2026-07-04)
**Philosophie** : Ayden **conseille avant de dépenser**. L'Advisor ne génère pas ; il juge la
*plausibilité* d'une demande **vis-à-vis de la pièce**, en amont, pour ne pas gaspiller une
génération sur l'impossible et incarner l'**architecte**. Complémentaire du Verify (a priori
gratuit/sémantique ≠ a posteriori post-gen). Moteur 2 pur (jamais V1/composer/DNA/preserve).

### Placement (VALIDÉ D4)
```
Parser → ★ REQUEST ADVISOR ★ → Normalizer → Conflict Resolver → Planner → Executor → Verify
```
L'Advisor gate **avant** de normaliser/optimiser ce qui pourrait être bloqué.
**In** : `Change[]` (Parser) + **`room_type`** (métadonnée session, EN canonique — [[room_type_i18n_contract]]).
**Out** : verdict **par changement** + verdict global + message architecte (voix Ayden — [[ayden_companion_direction]]).

### Verdicts (3) — VALIDÉS
| Verdict | Définition | UX | Génération |
|---|---|---|---|
| 🟢 **GREEN** | plausible (op sur existant, ou add de décor courant) | aucune friction | **immédiate** |
| 🟡 **YELLOW** | faisable mais **ambitieux/incertain** | court message + **[Try anyway]** — **pause légère (D2)** | après confirmation |
| 🔴 **RED** | **absurde pour cette pièce** (véhicule/piscine/outdoor en intérieur) | posture architecte + **alternative** + **[Add anyway]** | seulement si override |

**Anti-paternalisme (dur)** : défaut = GREEN (dans le doute → GREEN) · **RED rare, jamais un mur**
(toujours *pourquoi* + *alternative* + **override D1**) · YELLOW = heads-up, jamais un refus.
**Message mixte** : verdict **par changement** ; jamais bloquer tout à cause d'un seul RED →
[Do the sensible ones] / [Try everything] / [Adjust].

### Architecture MVP = **L1 + L2** (L3 Vision = V3 — VALIDÉ D3)
Tiered. La plupart des edits ne paient **rien** (fast-path L1).

**L1 — Règles déterministes (pré-filtre, $0, ~0 ms).** Sortie : `GREEN | RED | ESCALATE`.
- **GREEN direct (skip LLM)** si **chaque** changement est :
  - `type ∈ {move, remove, modify, replace}` (opère sur de l'existant → toujours plausible), **ou**
  - `type == add` **et** l'objet ∈ **`UNIVERSAL_DECOR`** :
    `flowers, plant, tree(potted), lamp, floor lamp, rug, carpet, cushion(s), pillow(s), throw,
     blanket, art, artwork, painting, mirror, frame, picture, poster, candle(s), vase, books,
     clock, curtains, drapes, blinds, shelf, shelves, stool, pouf, side table, coffee table,
     plant pot, tray, bowl`.
- **RED direct (backstop, même si LLM down)** si la pièce est **INTÉRIEURE** et un `add`/`structure`
  vise **`ABSURD_INTERIOR`** :
    `car, ferrari, lamborghini, truck, van, motorcycle, boat, yacht, ship, canoe, airplane, plane,
     jet, helicopter, tank, swimming pool, pool, pond, lake, waterfall, beach, horse, elephant,
     cow, dinosaur, garage, building, mountain, forest`.
  (Pièces **EXTÉRIEURES** — terrace/pool/garden/balcony/patio/driveway/facade — n'appliquent PAS
   ce set : une voiture sur une allée, une piscine sur une terrasse = plausibles → ESCALATE/GREEN.)
- **sinon → ESCALATE** (add d'objet non-trivial, structure non-évidente).
- `INTERIOR_ROOMS` = bathroom, bedroom, kitchen, living room, dining room, office, hallway,
  kids room, laundry, closet, entryway. `EXTERIOR_ROOMS` = terrace, pool, garden, balcony,
  patio, driveway, facade, backyard.

**L2 — LLM texte gpt-4o-mini (sur ESCALATE seulement, ~$0.0001, ~0,5 s). PAS de Vision.**
Prompt (par changement escaladé) :
```
SYSTEM: You are Ayden, a pragmatic interior architect. Judge whether a requested change can
plausibly be realized in the given ROOM via a photo edit. Verdict = GREEN (normal/plausible),
YELLOW (possible but ambitious or spatially uncertain), or RED (physically absurd for this room).
Be GENEROUS: default GREEN; reserve RED only for things that cannot sensibly exist in this room
(vehicles, pools, large outdoor elements inside an interior). For YELLOW/RED give ONE short
architect sentence; for RED also give a concrete alternative. JSON only:
{"verdict":"GREEN|YELLOW|RED","reason":"","alternative":""}
USER: Room: {room_type}
Requested change: {change.raw}
```
Fail-open : erreur/JSON invalide L2 → **GREEN** (on ne bloque jamais sur une panne de conseil).

**L3 — Vision (V3, différée).** Ne sert QUE les YELLOW **spatiaux** (« add TV mais aucun mur »),
déjà rattrapés par le Verify post-gen + pressentis par `predicted_partial`. Hors MVP.

### Agrégation & sortie
- `Verdict` enum GREEN/YELLOW/RED ; `ChangeAdvice{change, verdict, reason, alternative, source}` ;
  `AdviceResult{advices}` avec `overall` = pire verdict, `green_changes`, `blocked/uncertain`.
- **overall GREEN** → poursuite normale (Normalizer…). **YELLOW/RED** → réponse `status:"advisory"`
  **sans image** (message + `flagged[]`) ; l'user relance en **confirmant TOUTE la requête**
  (`confirm=true`) ou édite. **Pas de proceed partiel** (D-c : « Do the sensible ones » supprimé —
  jamais de drop implicite ; `green_changes` reste calculé pour la donnée mais n'alimente PAS de bouton).
- Impact **Composant 8** : géré par le **contrat de réponse unique** (`status:"advisory"|"completed"`, §9 D-b).

### Décisions VALIDÉES (user 2026-07-04)
**D1** RED override = oui ([Continue anyway]) · **D2** YELLOW = pause légère (Continue/Edit) · **D3**
MVP = L1+L2, Vision plus tard · **D4** placement Parser → Advisor → Normalizer · **D-a** tout refine
d'une image existante → `/refine` · **D-b** contrat réponse unique (`status`) · **D-c** UX advisory
simplifiée [Continue]/[Edit request], jamais de drop implicite.

## 8 — Décision de séquencement (mise à jour user 2026-07-04)
- **PR0 (wording) : CLOS, succès négatif** — le prompt n'est pas le levier.
- **HOTFIX Refine V2 : À CONSTRUIRE MAINTENANT** — profiter du blocage administratif Apple
  (~2 j) pour rendre Refine excellent avant reprise de la monétisation. Ordre : §9 figé (fait) →
  implémenter composant par composant → golden benchmark vert. Reprise monétisation (RC-PR1)
  dès les 4 Product IDs prêts, sans perte de temps.
- **Aucune autre grosse fonctionnalité en parallèle.**
