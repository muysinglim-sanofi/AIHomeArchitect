# Wave 5.5.15 Roadmap — Emotional Realism Family

**Locked 2026-05-24** by user. Source of truth for the Wave 5.5.15 sub-wave sequence. Sub-waves b→g chain incrementally; each must pass benchmark gate before next ships.

All waves bimodal-gated (`BIMODAL_ENABLED=1`). Default prod = byte-identical to Wave 5.5.14.

---

## Status snapshot

| Wave | Theme | Status | Commit |
|---|---|---|---|
| 5.5.15a | Room Completeness Architecture Safety Audit | ✅ shipped | `fe9d18d` |
| **5.5.15b** | **Emotional Realism MVP** | ✅ **shipped (creative-only after iteration b→c→d)** | `60635dc` |
| 5.5.15c | Atmosphere Emotional Calibration | 🟢 **NEXT** | — |
| 5.5.15d | Texture & Material Realism | ⬜ planned | — |
| 5.5.15e | Natural Enrichment Refinement | ⬜ planned | — |
| 5.5.15f | Focal Hierarchy Intelligence | ⬜ planned | — |
| 5.5.15g | Furnishing Safety Layer | ⬜ planned | — |

---

## Wave 5.5.15b — Emotional Realism MVP — ✅ SHIPPED

Originally specified with 3 concepts:
- lived-in micro-layering
- lighting/shadow realism
- realistic imperfections

**Empirical iteration** (commit `60635dc` is the final form):
- **b** (initial): all 3 concepts in both preserve+creative → **3/9 wall invention in V1 preserve** (Warm M #1, Japandi #1, Japandi #3 + rear window suppressed). ROLLED BACK.
- **c** (trim): dropped "lived-in micro-layering" + "layered texture realism". Preserve kept "soft shadow falloff, restrained imperfections" → **1/9 walls vs 0/9 baseline**. Still nudged the model toward wall invention.
- **d** (final): preserve mode SILENCED entirely (returns ""). Creative kept "cinematic lighting depth + restrained imperfections + atmospheric warmth around the existing focal zone".

**Lesson:** Any noun with surface-implication ("layering", "texture", "imperfections" even softened) costs architectural fidelity in preserve mode. Empirically: baseline = 0/9 walls, any non-empty preserve signal ≥ 1/9 walls.

**Architecture established:** `backend/prompt_engine/emotional_realism.py` + byte-exact validator + frozen baseline → discipline gate for all subsequent richness signals.

---

## Wave 5.5.15c — Atmosphere Emotional Calibration — NEXT

**Goals:** emotional depth, atmosphere distinctiveness, premium feel, cinematic realism.

Each atmosphere becomes:
- emotionally recognizable
- visually memorable
- more premium
- more emotionally differentiated

**Concrete examples (user-specified):**
- **Warm Modern** — richer warm glow, tactile comfort, emotional coziness
- **Nordic** — airy calm, soft daylight realism, elegant minimal warmth
- **Japandi** — restraint, silence, meditative realism

**Implementation shape:**
Replace single generic creative-mode sentence in `emotional_realism.py` with a dictionary `{atmosphere_id: creative_sentence}` covering all 10 atmospheres. Same module, same P5 priority, same bimodal gate. Per-atmosphere sentence respects the calibration matrix (reference atmospheres stay pure, calibration targets get the most attention).

**Hard constraints (locked):**
- ❌ NO architectural reinterpretation language
- ❌ NO openness bias ("expansive", "open up")
- ❌ NO spatial expansion vocabulary
- ❌ Preserve mode stays silenced (do NOT re-introduce a signal there)
- ❌ NO surface-implying nouns ("layering", "texture", "imperfections" as standalone)

**Acceptance:**
- Byte-exact validation passes (each cell diff = exactly its atmosphere's sentence)
- 10-atmosphere creative-mode bench shows differentiation (subjective: "I can tell which is which without the label")
- 0/N wall invention regression on V1 preserve (preserve untouched)

---

## Wave 5.5.15d — Texture & Material Realism

**Goals:** material richness, tactile realism, premium perception.

**Focus:** wood realism, textile realism, stone/travertine realism, imperfect material behavior, reflection realism, surface micro-variation.

**Why safe:** emotional enrichment, minimal spatial pressure.

**Open design question:** does this layer atop the per-atmosphere creative sentence from 15c, or replace it? Decision after 15c benchmark.

---

## Wave 5.5.15e — Natural Enrichment Refinement

**Goals:** subtle life, organic realism, decorative asymmetry.

**Focus:** plants, soft decor, restrained object realism, believable object placement, anti-showroom styling.

**Hard constraints:**
- ❌ NO furnishing mandates
- ✅ ONLY opportunistic enrichment, subtle layering

**Note:** this is NOT the audit doc's 5.5.15e (which proposed dropping `_NATURAL_ENRICHMENT`). User's 15e is additive enrichment, not subtractive consolidation.

---

## Wave 5.5.15f — Focal Hierarchy Intelligence

**Goals:** visual hierarchy, emotional focal points, cinematic composition.

**Focus:** soft focal anchoring, composition balance, emotional eye guidance.

**Hard constraints:**
- ❌ NO media wall generation
- ❌ NO architectural focal restructuring
- ❌ NO layout pressure

---

## Wave 5.5.15g — Furnishing Safety Layer

**Goals:** SAFE furnishing enrichment + room-type furnishing intelligence WITHOUT spatial pressure or architecture drift.

**SAFE concepts only:** cushions, throws, small decor, subtle wall art, lamps, texture layering.

**Hard constraints:**
- ❌ NO mandatory furniture lists
- ❌ NO density targets
- ❌ NO room completion pressure

---

## Cross-cutting rules (from Wave 5.5.15a audit, still binding)

1. PERMISSIVE wording only ("if naturally compatible", "when space allows", "opportunistic") — never "must / never / every / all"
2. NO zone enumeration
3. NO showroom-target language ("hospitality-grade", "fully designed", "complete the room")
4. EXPLICIT "secondary to architecture" guard in the same sentence
5. BIMODAL_ENABLED-gated for rollback safety
6. BENCHMARKED before ship — not "looks better on one photo"

## Sequencing protocol

- Each sub-wave gets its own commit
- Each sub-wave gets a 10-atmosphere creative bench gate
- V1 preserve bench every 2 sub-waves to detect regression (preserve must stay 0/N)
- Byte-exact validator updated for each new module / signal

## Rollback

`unset BIMODAL_ENABLED` reverts the entire family instantly to Wave 5.5.14 baseline.
