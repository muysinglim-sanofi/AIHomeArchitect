# POST-BUILD — Plan séquencé : Optimisation prompt + Bugs

**Statut : 🔒 GELÉ. Rien ci-dessous n'est shippé.** Plan d'exécution pour la vague *post-TestFlight*.
**Objectif :** réduire la longueur du prompt **sans** régression architecture/murs/structure, **en préservant la richesse déco**.
**Sources :** logs réels (6 payloads OpenAI du bench 2026-06-12) · mémoire `post_build_prompt_optimization.md` · freeze `docs/FREEZE_CONTRACT.md`.

---

## Règles globales (non négociables)
1. **Un flag par étape. Un bench par étape. Jamais de bundle.** (anti patch-accumulation — un moteur à 61.5% PASS ; si ça régresse en lot, rien n'est attribuable.)
2. **Tropical = exception** sur tout ce qui dépend du pixel-anchor : il tourne `fidelity=LOW` (intentionnel, main.py:2461-2465) → le **texte du contrat est son seul garde-fou** → NE PAS l'alléger.
3. **Ne jamais toucher** : `structural_identity` comme garde-fou hérité (on le *fiabilise*, on ne l'affaiblit pas) · `TEMPORAL CONTINUITY` · l'**identité DNA** (matériaux/palette/hero/AVOID = richesse + différenciation).
4. **gpt-image-1 ≠ LLM de raisonnement** : privilégier noms concrets > méta-instructions. Les étapes « headers/priorité » sont testées sans attente forte.

## Protocole de bench (commun à toutes les étapes) — cf. `benchmark_methodology_v2`
- Sources **Type A+** (canoniques), **1 source de référence par room_type**.
- **Lancer backend `BIMODAL_ENABLED=1`, sans `--reload`, log en append.**
- Gates PASS (les 5) : **`walls=0`** · **ouvertures préservées** (fenêtres/baies/portes) · **token structurel propagé** sur switch · **nb d'objets déco inchangé** (anti-appauvrissement) · **naturalness ≥ 4/5**.
- Comparatif **A/B flag off vs on**, même source, même seed image si possible.
- Mesure secondaire : **Δ longueur prompt** (objectif) + **latence** (info, pas un gate — gpt-image-1 domine à 70-80%).

---

# PHASE 0 — Le bug d'abord (racine de la dérive archi)

### 0.1 — `temperature=0` sur la capture vision **[BUG #1, priorité absolue]**
- **Flag :** `VISION_DETERMINISTIC`
- **Fichier :** `backend/main.py:500` — appel `openai.chat.completions.create(model="gpt-4o", …)` dans `_capture_structural_text` (et le 2ᵉ appel jumeau du `safe_union_merge`, main.py:~1894-1895).
- **Change :**
  ```python
  resp = await openai.chat.completions.create(
      model="gpt-4o",
      temperature=0,          # ← AJOUT : lecture déterministe (défaut actuel = 1.0)
      seed=42,                # ← AJOUT (best-effort, gpt-4o honore seed partiellement)
      messages=[...],
  )
  ```
- **Bench spécifique :** lire **5× la même photo** → `fact_count` et features (porte/cloison/plafond) **stables** (variance ≈ 0). Avant : 6 lectures = 6 tokens.
- **Risque :** très bas (capture vision, hors moteur image gelé). **Revert :** retirer les 2 lignes.
- **Confiance localisation :** ✅ vérifiée.

### 0.2 — (option) Token canonique unique par photo source
- **Flag :** `STRUCTID_CANONICAL_CACHE`
- **Idée :** capturer `structural_identity` **une seule fois** par photo uploadée, le réutiliser sur toutes les atmosphères/switches de cette source (au lieu de relire à chaque V1).
- **Où :** persister le token à l'upload (Supabase session) et le réinjecter ; main.py round-trippe déjà un `structural_identity` Form param (L1462) → étendre.
- **Bench :** 5 atmosphères, même photo → **token byte-identique** sur les 5.
- **Risque :** moyen (état/round-trip). **Faire seulement si 0.1 ne suffit pas.**
- **Confiance :** 🟡 design à confirmer (chemin d'upload).

---

# PHASE 1 — Trims sûrs & partagés (atmosphère-indépendants)

### 1.1 — Corriger la contradiction meuble
- **Flag :** `PROMPT_FURNITURE_FIX`
- **Fichier :** `backend/prompt_engine/preservation.py:~348-349` (`_PRESERVE_MODE_CONTRACT`).
- **Change :**
  ```
  AVANT : "Redesign only through materials, furniture, lighting, decor, textiles, colours, and atmosphere styling."
  APRÈS : "Restyle only through materials, lighting, decor, textiles, colours and atmosphere — on the existing furniture (same pieces, same footprint)."
  ```
- **Portée :** V1 **et** switch, toutes atmosphères.
- **Bench :** `naturalness≥4` **+ nb objets déco inchangé** (ne pas sur-verrouiller → appauvrir). Vérifier que le mobilier reste re-stylé (pas figé brut).
- **Risque :** moyen. **Revert :** restaurer la phrase.
- **Confiance localisation :** 🟡 (ligne ~348 d'après mémoire — confirmer à l'ouverture).

### 1.2 — Contrat-light V1 (hard-lock openings + stop répétitions) — *intègre #3 externe*
- **Flag :** `PROMPT_CONTRACT_LIGHT`
- **Fichiers :** `preservation.py` (`build_mode_contract` + nouveau `_PRESERVE_MODE_CONTRACT_LIGHT`) · `composer.py:~987` (passe `pixel_anchored`).
- **Change :**
  1. Nouveau bloc léger :
     ```
     STRUCTURE — Windows, glass openings and exterior connections are immutable
     structural anchors; walls, doors, ceiling and proportions stay exactly as
     photographed. Highest priority: preserve structure before any styling.
     ```
     (≈ 270 ch — remplace les ~650 ch de la moitié « ouvertures », garde TEMPORAL séparé.)
  2. `build_mode_contract(..., pixel_anchored: bool)` ; renvoie le LIGHT si `pixel_anchored` sinon le complet.
  3. `composer.py` : `pixel_anchored = (edit_mode == EditMode.FIRST_VISION and fidelity_high)`.
- **⚠️ Exclusions :** **Tropical** (LOW) + **tous les switches** (LOW) → gardent le contrat complet.
- **Note :** absorbe aussi #6 (phrase priorité) et une partie de #2/#3 (formulation affirmative « anchors »).
- **Bench :** `walls=0` **strict** sur 4 atmos high (WM/SL/Japandi/Nordic), comparé au contrat complet. Δ longueur ≈ −370 ch.
- **Risque :** moyen-élevé (c'est LE garde-fou archi). **Revert :** `pixel_anchored=False` partout.
- **Confiance :** ✅ composer.py:987 vérifié · 🟡 signature `build_mode_contract` à confirmer.

### 1.3 — Dédupe boilerplate partagé (rideaux + TV)
- **Flag :** `PROMPT_DEDUP_SHARED`
- **Fichiers :** builder DNA room (`composer.py` `dna_room_context` / `atmosphere_dna/*`) — chaînes répétées sur les 6.
- **Change :**
  ```
  Rideaux : "…clearly framing each existing window, drawn open with the glass left
             fully clear — never covering, narrowing or blocking it, never on a glass
             partition"  →  "framing each window, drawn open, glass clear"
  TV      : retirer "never a new wall or by converting glazing into a wall"
             (4ᵉ redite de l'anti-mur, déjà couverte par le contrat)
  Garder 1× : "never floating in the room" / "only if that wall is solid and free, else omit"
  ```
- **Bench :** `walls=0` + ouvertures préservées (vérifier que retirer la redite TV ne ré-ouvre pas l'invention de mur).
- **Risque :** moyen. **Revert :** restaurer les chaînes.
- **Confiance :** 🟡 fichiers DNA exacts à confirmer.

### 1.4 — (cheap, ROI incertain) Headers hiérarchiques + phrase priorité — *#1 + #6 externes*
- **Flag :** `PROMPT_HEADERS`
- **Change :** préfixer les sections existantes par `[STRUCTURE] [SPATIAL] [ATMOSPHERE] [DECOR] [LIGHTING] [AVOID]`.
- **Bench :** A/B `walls=0` + naturalness ; **garder seulement si gain mesurable** (image-model, bénéfice non garanti).
- **Risque :** bas. **Revert :** retirer les headers. *(Peut tourner dans le même bench que 1.2.)*

---

# PHASE 2 — Touche le DNA / la capture (bench strict, par-atmosphère)

### 2.1 — `structural_identity` format **blueprint** — *#4 externe (paire avec 0.1)*
- **Flag :** `STRUCTID_BLUEPRINT`
- **Fichiers :** prompt vision `main.py:~507` (buckets) **+ parser** `prompt_engine/structural_identity.py` (`extract_from_description` matche un vocabulaire EXACT → doit suivre le nouveau format) + `render_clause`.
- **Change (cible) :** rendu mécanique plutôt que littéraire :
  ```
  LEFT: full-height sliding glass opening | RIGHT: solid wall, narrow doorway, no glazing
  CEILING: flat white | DEPTH: open-plan volume | FACADE: additional windows
  ```
- **Bench :** variance ≈ 0 sur relectures (combiné 0.1) + `walls=0` + ouvertures préservées + propagation switch.
- **Risque :** moyen-élevé (token hérité + parser couplé). **Revert :** restaurer prompt vision + parser.
- **Confiance :** ✅ emplacements connus · effort réel (2 fichiers couplés).

### 2.2 — Nettoyage adjectifs faibles → objets concrets — *#5 externe (le + solide)*
- **Flag :** `DNA_ADJECTIVE_TRIM`
- **Fichiers :** `atmosphere_dna/*` ligne *mood* de chaque atmosphère.
- **Change :** max **2 adjectifs mood**, le reste en objets concrets. Ex. SL : `Indulgent, serene, tactile, elegant luminous luxury, feminine-refined…` → `serene luxury — honed cream marble, layered cashmere, warm indirect cove light`.
- **⚠️ Garder l'identité/différenciation** : ne pas vider le DNA, juste dé-bruiter.
- **Bench :** `naturalness≥4` **+ différenciation préservée** (les 5 restent visuellement distinctes) **+ nb déco inchangé**.
- **Risque :** moyen (cœur qualité gelé). **Revert :** restaurer les lignes mood. **Par-atmo, une à la fois.**

### 2.3 — Figer le mur TV **[BUG #2]**
- **Flag :** `TV_WALL_PIN`
- **Fichier :** builder `dna_room_context` — clause TV.
- **Change :** lier la TV au mur nommé dans `structural_identity` (ou porter « TV-wall » dans la lignée) au lieu de « on an existing wall » (libre).
- **Bench :** même photo, 5 atmos → **TV sur le même mur** partout (consistance « même appartement »).
- **Risque :** moyen. **Revert :** restaurer la clause libre.

### 2.4 — (test ciblé) Négatif → affirmatif — *#2 externe*
- **Flag :** `PROMPT_AFFIRMATIVE`
- **Change :** sur **UN** bloc seulement : `Do not add/remove/resize/relocate architectural elements` → `All architectural elements remain in their exact original position and proportions`.
- **Bench :** `walls=0` A/B. Si neutre/négatif → **ne pas généraliser**.
- **Risque :** moyen (nos négatifs marchent à 61.5%). **Revert :** restaurer.

---

# PHASE 3 — Seulement si Phases 0-2 stables

### 3.1 — Cap **hero AU SOL** (PAS « 1 hero ») — *#7 externe corrigé*
- **Flag :** `HERO_FLOOR_CAP`
- **Justification :** Wave 6.2a — les objets **au sol** (grandes plantes, meubles surdimensionnés) font « pousser les murs ». ⚠️ « 1 hero par catégorie » **annulerait** l'enrichissement déco Waves 6.13/6.14 → **interdit**.
- **Change :** limiter les **items hero au sol** (1 grande plante sol max + pas de meuble surdimensionné), **garder riche la déco de surface** (coussins, throw, art mural, objets de table).
- **Bench :** `walls=0` **+ nb objets déco surface inchangé** (anti-appauvrissement) + naturalness.
- **Risque :** élevé (frontière enrichissement/dérive). **Revert :** restaurer le DNA.

### 3.2 — Dédupe DNA agressive (par-atmo, spécifique)
- **Flag :** `DNA_DEDUP_DEEP`
- **Change :** Japandi `let negative space breathe` (dup) ; SL `champagne brass` ×2→1 + hero `olive **ou** fig`→1 ; Nordic `wool flatweave under pile` ×2→1 + `daylight warmth` ×3→1 ; WM `oat or camel` ×5→affiner + `brass echo` dup ; `existing`×7→~4 partout.
- **Bench :** `naturalness≥4` + différenciation + nb déco inchangé. **Une atmosphère à la fois.**
- **Risque :** élevé. **Revert :** par atmosphère.

---

## Récap séquencement
| Phase | Étapes | Risque | Gain longueur | Nature |
|---|---|---|---|---|
| **0** | 0.1 temperature=0 · (0.2 cache) | très bas | 0 | **bug archi #1** |
| **1** | 1.1 meuble · 1.2 contrat-light · 1.3 dédupe rideaux/TV · 1.4 headers | bas→moyen | ~−370 + dédupe | partagé, sûr |
| **2** | 2.1 blueprint · 2.2 adjectifs · 2.3 TV-pin(bug#2) · 2.4 affirmatif | moyen→élevé | −165..−300/atmo | DNA/capture |
| **3** | 3.1 hero-sol · 3.2 dédupe DNA profonde | élevé | + | si stable |

**Gain longueur réaliste total : ~12-18%** (le « levier réalisme » de la 1ʳᵉ analyse a été retiré — EDITORIAL/PHOTOGRAPHIC ne sont pas envoyés en prod).

## Mapping des 7 propositions externes
| # ext | Intégré en | Verdict |
|---|---|---|
| 1 headers | 1.4 | 🟡 test, ROI incertain |
| 2 affirmatif | 2.4 | ⚠️ test 1 bloc |
| 3 hard-lock openings | 1.2 | ✅ adopté |
| 4 blueprint struct_id | 2.1 | ✅✅ fort (+ parser) |
| 5 adjectifs | 2.2 | ✅ le + solide |
| 6 priorité | 1.2/1.4 | 🟡 marginal |
| 7 hero cap | 3.1 | 🔴→corrigé « hero au sol » |

## Bugs (rappel)
- **BUG #1** `structural_identity` non-déterministe (`temperature` jamais défini = 1.0) → **0.1**.
- **BUG #2** mur TV non figé (`on an existing wall`, libre) → **2.3**.
- *Non-bugs vérifiés :* Tropical V1=LOW (intentionnel, main.py:2461-2465) · editorial/photographic off V1 (intentionnel, composer_v2.py:980).
