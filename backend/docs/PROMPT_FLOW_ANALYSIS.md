# Prompt Flow Analysis — Wave 4.5.2

**Version:** Wave 4.5.2  
**Purpose:** Complete analysis of the FIRST_VISION prompt assembly — section ordering, actual sizes, redundancy analysis, and the path to a simpler architecture.

---

## Part 1: Complete FIRST_VISION Prompt Flow

### 1.1 Assembly Order (Current)

```
P1 ─── task          [~175 chars]  fidelity_layer.py::build_first_vision_task()
P1 ─── full_contract [~820 chars]  preservation.py::build_simplified_fv_contract()
P1 ─── source_space  [~200 chars]  "SOURCE SPACE: " + room_description (from GPT-4o-mini)
P2 ─── design_intel  [~939 chars]  atmosphere_dna::build_dna_block()
P5 ─── interior_completeness [~298 chars]  realism_layer.py::build_interior_completeness_rule()
P4 ─── scene_completion [~0 chars] empty on DNA paths; ~300 chars on non-DNA fallback
P4 ─── wow_directive [~326 chars]  wow_layer.py::build_restyling_wow_directive()
P5 ─── visible_spaces [0-200 chars] visible_space_logic.py
P5 ─── design_direction [0-300 chars] user instruction (V1: usually empty)
P3 ─── compact_realism [~133 chars] realism_layer.py::build_compact_realism_block()
```

**Notes:**  
- Sections joined with `\n` — one newline separator between sections  
- Empty sections omitted from output  
- Typical FIRST_VISION on DNA path: task + contract + source + DNA + completeness + wow + realism = 7 sections

### 1.2 Drop Order Under Budget Pressure

```
1. Drop P5: interior_completeness, visible_spaces, design_direction
2. Drop P4: scene_completion, wow_directive  ← QUALITY LOSS
3. Drop P3: compact_realism                 ← SERIOUS QUALITY LOSS
4. Drop P2: design_intel                    ← CATASTROPHIC
   (P1 never drops)
```

### 1.3 Budget Analysis by Atmosphere (200-char source description)

| Atmosphere | DNA Size | Total | Headroom | All sections survive? |
|-----------|---------|-------|----------|----------------------|
| Soft Luxury (living room) | ~939 chars | ~2905 | +645 | Yes |
| Dark Contemporary (living room) | ~996 chars | ~2962 | +588 | Yes |
| Japandi Calm (living room) | ~873 chars | ~2839 | +711 | Yes |
| Zen Retreat (living room) | ~823 chars | ~2789 | +761 | Yes |
| Budget (3550 chars) | — | — | — | — |

**With a 400-char source description:**

| Atmosphere | DNA Size | Total | Headroom |
|-----------|---------|-------|----------|
| Dark Contemporary | ~996 | ~3162 | +388 |
| Soft Luxury | ~939 | ~3105 | +445 |

**All sections still survive.** Budget pressure only becomes real at source descriptions > ~600 chars + large DNA (Dark Contemporary ~996 chars):

| Source length | Total (Dark Contemporary) | Headroom |
|--------------|--------------------------|----------|
| 200 chars | ~2962 | +588 |
| 400 chars | ~3162 | +388 |
| 600 chars | ~3362 | +188 |
| 700 chars | ~3462 | +88 |
| 800 chars | ~3562 | -12 → wow_directive drops |

**Conclusion:** At standard usage (GPT-4o-mini descriptions are ~150-250 chars), all sections survive for all 10 atmospheres. Budget pressure is not a real concern at current operating conditions.

---

## Part 2: Complete Rendered Prompt (Annotated)

**Atmosphere:** Soft Luxury Gold  
**Room:** living room  
**Source description:** ~200 chars from GPT-4o-mini

```
╔══════════════════════════════════════════════════════════════╗
║  [TASK — P1, 175 chars]                                      ║
╠══════════════════════════════════════════════════════════════╣
SAME APARTMENT — apply Soft Luxury Gold atmosphere.
The photo defines spatial truth: reproduce this living room's
geometry, camera, windows, openings, and depth exactly.
Then transform all surfaces, materials, and light.

╔══════════════════════════════════════════════════════════════╗
║  [CONTRACT Tier 1.5 — P1, 820 chars]                        ║
╠══════════════════════════════════════════════════════════════╣
CAMERA LOCK — FROZEN: camera position, focal length, vanishing
points, horizon line. Room proportions, spatial depth, and all
structural lines are fixed. Output must look like a photograph
of the SAME apartment, preserving its architectural identity.
DO NOT reinterpret geometry. DO NOT redesign architecture.
STRUCTURAL LOCK — FORBIDDEN: windows (positions, frames,
unblocked, natural light visible), doors, walls, ceiling
height, floor plan, structural columns.
CHANGE ONLY: surfaces, materials, furniture, lighting, textiles,
colours, atmosphere. ATMOSPHERE BOUNDARY — geometry, openings,
and topology override atmosphere. Atmosphere is applied last.
Any perspective or geometry change is a failure.
ROOM LOCK: preserve TV wall or fireplace position, sofa zone,
all window orientations, open-floor-to-furnished ratio.

╔══════════════════════════════════════════════════════════════╗
║  [SOURCE SPACE — P1, ~214 chars]                             ║
╠══════════════════════════════════════════════════════════════╣
SOURCE SPACE: Living room with two large west-facing windows,
eye-level single-point perspective, medium spatial depth.
No columns. Standard ceiling height. Visible hallway through
doorway. Oak engineered wood floor throughout.

╔══════════════════════════════════════════════════════════════╗
║  [ATMOSPHERE DNA — P2, ~939 chars]                           ║
╠══════════════════════════════════════════════════════════════╣
ATMOSPHERE (Soft Luxury): Refined hospitality luxury
emphasizing softness, elegance, tactile richness, and timeless
sophistication. — Indulgent, serene, tactile, quietly opulent,
feminine-refined, sensorially rich. [Rosewood / Aman / luxury suite]
ROOM (Living Room): fluted ivory plaster walls, honed cream
marble floor, brushed champagne metal accents.
LIGHT: Concealed perimeter cove + silk shade floor lamps;
warm evening tone, no ceiling spotlights.
ATMOSPHERE STYLE (restyle existing elements): deep curved
bouclé sofa in ivory or blush; honed marble coffee table on
brushed brass base; barrel-back cashmere armchairs;
oversized ceramic vessel with dried pampas or lunaria;
layered silk and bouclé cushions in cream and blush.
REALISM: sofa sized to room — not oversized for space;
marble floor with correct 3–5 mm grout lines.
AVOID: no jewel-tone colour pops, no gold leaf or metallic
wallpaper, no asymmetric art gallery wall, no visible TV
above fireplace, Bling luxury, crystal chandelier clichés.

╔══════════════════════════════════════════════════════════════╗
║  [INTERIOR COMPLETENESS — P5, 298 chars]                     ║
╠══════════════════════════════════════════════════════════════╣
INTERIOR COMPLETENESS: The space must feel fully designed and
emotionally inhabited — never sparse, empty, under-furnished,
or minimally staged. Every major functional zone should feel
intentionally completed with layered furniture, lighting, decor,
textile richness, and hospitality-grade styling.

╔══════════════════════════════════════════════════════════════╗
║  [WOW DIRECTIVE — P4, 326 chars]                             ║
╠══════════════════════════════════════════════════════════════╣
TRANSFORMATION AMBITION — premium restyling of THIS exact
apartment photo, not a new apartment. Visible architecture
stays recognizable: windows, openings, partitions, existing
equipment. WOW through: materials, finishes, lighting quality,
furniture styling, atmosphere conviction.
Decorate this photo — do not recompose it.

╔══════════════════════════════════════════════════════════════╗
║  [COMPACT REALISM — P3, 133 chars]                           ║
╠══════════════════════════════════════════════════════════════╣
NOT a CGI render. DSLR real estate photograph quality.
Real materials, natural light physics, no plastic surfaces,
no render feeling.

TOTAL: ~2905 chars (budget: 3550)
```

---

## Part 3: Redundancy Analysis

### 3.1 Concept Repetition Map

The following core ideas appear multiple times across sections:

**Concept: "Same physical apartment / do not generate a new one"**
```
TASK:       "SAME APARTMENT — apply... The photo defines spatial truth"
CONTRACT:   "Output must look like a photograph of the SAME apartment"
CONTRACT:   "DO NOT redesign architecture"
WOW:        "THIS exact apartment photo, not a new apartment"
WOW:        "Decorate this photo — do not recompose it"
```
5 repetitions. The first (task) and last (WOW "Decorate this photo") are the most unique in phrasing. The others echo.

**Concept: "Windows and openings must be preserved"**
```
TASK:       "reproduce this living room's... openings... exactly"
CONTRACT:   "STRUCTURAL LOCK — FORBIDDEN: windows (positions, frames,
             unblocked, natural light visible)"
WOW:        "Visible architecture stays recognizable: windows, openings,
             partitions, existing equipment"
```
3 repetitions.

**Concept: "Camera is frozen"**
```
TASK:       "reproduce this living room's... camera... exactly"
CONTRACT:   "CAMERA LOCK — FROZEN: camera position, focal length,
             vanishing points, horizon line"
```
2 repetitions.

**Concept: "Transform surfaces/materials/atmosphere only"**
```
TASK:       "transform all surfaces, materials, and light"
CONTRACT:   "CHANGE ONLY: surfaces, materials, furniture, lighting,
             textiles, colours, atmosphere"
DNA:        "ATMOSPHERE STYLE (restyle existing elements): ..."
```
3 repetitions.

**Estimated redundant text: ~500-600 chars (~17-21% of total)**

### 3.2 What Is Actually Unique Per Section

| Section | Unique contribution | Redundant with |
|---------|--------------------|-----------------|
| TASK | "SAME APARTMENT" opening — first-token mental model; "The photo defines spatial truth" | contract (CAMERA LOCK, DO NOT redesign) |
| CONTRACT | Technical vocabulary (focal length, vanishing points, FORBIDDEN list); ROOM LOCK specifics | task framing |
| SOURCE SPACE | Actual room description (window count, perspective type, floor material) | nothing |
| DNA ATMOSPHERE line | Philosophy, emotional intent, luxury benchmark | nothing |
| DNA ROOM materials | Specific material palette (fluted ivory plaster, honed marble floor) | nothing |
| DNA LIGHT | Specific lighting behavior | nothing |
| DNA furniture list | Specific pieces (bouclé sofa, marble coffee table) | CONTRADICTS photo-first |
| DNA REALISM | Scaling constraints | nothing |
| DNA AVOID | Failure modes for this atmosphere | nothing |
| INTERIOR COMPLETENESS | "never sparse, under-furnished" | DNA (already furnishes); CONTRADICTS photo-first |
| WOW | "WOW through: materials, finishes, lighting quality" (quality ambition signal); "Decorate this photo" | contract, task |
| COMPACT REALISM | "NOT a CGI render. DSLR." (photographic rendering instruction) | nothing |

---

## Part 4: The Minimal Viable FIRST_VISION Prompt

**Hypothesis:** What is the minimum prompt that achieves the product goal?

```
[1] SAME APARTMENT — apply {atmosphere} to this photo.
    Restyle the surfaces, materials, lighting, and atmosphere.
    Do not recompose. Do not add rooms. Do not generate a new apartment.
    (~120 chars)

[2] STRUCTURAL LOCK — FROZEN: camera, perspective, walls, windows,
    doors, ceiling, floor plan. Output = photograph of the same physical space.
    (~150 chars)

[3] SOURCE SPACE: {room_description from vision analysis}
    (~200 chars)

[4] {DNA block — atmosphere + room-specific materials, lighting, REALISM, AVOID}
    (~939 chars)

[5] NOT a CGI render. DSLR real estate photograph quality.
    Real materials, natural light physics.
    (~133 chars)

TOTAL: ~1542 chars vs current ~2905 (47% reduction)
```

**What this minimal prompt removes vs current:**
- Contract (CAMERA LOCK, STRUCTURAL LOCK, ROOM LOCK): ~820 chars
  - Hypothesis: `input_fidelity=high` + structural mask + task framing handle this
- Interior completeness: ~298 chars
  - Hypothesis: DNA handles furnishing
- WOW directive: ~326 chars
  - Hypothesis: DNA handles quality ambition

**Risk:** The WOW directive's "TRANSFORMATION AMBITION" and "materials, finishes, lighting quality, atmosphere conviction" may be driving premium quality signals that are not covered by DNA. Removing it without PROD testing could reduce ambition and produce technically correct but aesthetically flat outputs.

**Recommended path:** Not a single-step reduction. Measure incrementally.

---

## Part 5: Historical Evolution Summary

```
Wave 4.1     Initial system. Single large preservation block. No DNA. No mask.
             Problem: "REDESIGN" verb, geometric drift, fake-apartment feeling.

Wave 4.2.x   Three-tier contract system (Tier 1/2/3). Budget system. DNA layer introduced.
             compact_realism, scene_completion. Mask system (slow version).
             Problem: mask blocked event loop. Budget still too tight.

Wave 4.3.0   TOPOLOGY LOCKED in STYLE_REFINEMENT. Anchor detector. Atmosphere switch contract.
             Problem: FIRST_VISION task framing still using "REDESIGN" verb.

Wave 4.3.1   WOW directive introduced. "TRANSFORMATION AMBITION" vocabulary.
             "editorial redesign" framing (later revised).
             Problem: wow_directive dropped under budget pressure for large DNA.

Wave 4.3.2   Smart retry system (retry_classifier). max_retries=0.
             Problem: still dropping wow_directive.

Wave 4.3.3   Reconstruction-first task framing. "SAME APARTMENT — apply {atm}."
             "The photo defines spatial truth." 
             Problem: budget still tight, wow still dropping for large DNA.

Wave 4.4.0   Mask rewrite (PIL + async run_in_executor). ~50ms vs 2-5s.
             Problem: wow still dropping.

Wave 4.4.1   Budget raised 3350→3550. compact_realism replaces medium_realism.
             interior_completeness moved to P5.
             Problem: system increasingly complex; model still "reconstructing."

Wave 4.4.2   Performance instrumentation (PipelineTimer, [PERF] logs).
             Problem: "architectural reconstruction" framing still dominant.

Wave 4.5.0   Tier 1.5 simplified contract (~820 chars vs ~1550). Product philosophy docs.
             Problem: WOW directive still using "editorial redesign" framing.

Wave 4.5.1   Restyling WOW directive. DNA STYLE key → ATMOSPHERE STYLE (restyle existing).
             Problem: fundamental DNA furniture list tension still unresolved.

Wave 4.5.2   This audit. Analysis only.
```

**Key insight from history:**  
Each wave added a corrective layer without removing what it replaced. The system grew from ~3 prompt sections to 10 sections. The underlying image API signals (`input_fidelity=high`, quality, aspect ratio, mask) were always present but underweighted in the mental model. The prompt architecture accumulated because prompt-side solutions are visible and controllable, while API-side signals are opaque.

---

## Part 6: The Vision for Wave 4.6+

### 6.1 Ideal FIRST_VISION Prompt Architecture

```
[1] TASK (P1, ~80-120 chars)
    "SAME APARTMENT — apply {atm} to this photo. Restyle surfaces,
    materials, lighting, atmosphere. Do not recompose."

[2] STRUCTURAL CONSTRAINT (P1, ~200-300 chars)
    Minimal vocabulary: camera, windows, walls, topology locked.
    Remove: ROOM LOCK (not photo-grounded), excessive FORBIDDEN list.

[3] SOURCE SPACE (P1, ~100-200 chars)
    Vision analysis output, trimmed to structural anchors only.

[4] DNA — MATERIALS + LIGHTING + REALISM + AVOID (P2, ~600-700 chars)
    Remove: specific furniture_language pieces.
    Replace with: material/texture vocabulary ("bouclé-upholstered seating
    in warm ivory tones" vs "deep curved bouclé sofa in ivory or blush").

[5] COMPACT REALISM (P3, ~133 chars)
    Unchanged — essential.

[6] QUALITY AMBITION (P4, ~150 chars) — simplified WOW
    "WOW through: materials, lighting quality, atmosphere conviction.
    Photographic quality at editorial level."

TOTAL TARGET: ~1300-1600 chars (55-45% reduction from current ~2905)
```

### 6.2 DNA Architecture Evolution

**Current DNA furniture_language (composition authority):**
```
"deep curved bouclé sofa in ivory or blush; 
 honed marble coffee table on brushed brass base; 
 barrel-back cashmere armchairs"
```

**Target DNA furniture_language (restyling authority):**
```
"bouclé upholstery in ivory or blush tones; 
 stone or marble surface on the central table; 
 cashmere or mohair textile seating in soft curves"
```

The difference: first version prescribes specific pieces (model may replace what's in the photo). Second version prescribes material/texture/form qualities the model can apply to whatever is already in the photo.

### 6.3 What the "Ideal System" Gets Right

The ideal system rests on:

1. **API-level**: `input_fidelity=high` + `quality=high` + aspect ratio (zero prompt cost)
2. **Pixel-level**: structural mask (zero prompt cost)
3. **Semantic anchor**: "SAME APARTMENT" + "Restyle, do not recompose" (minimal prompt cost)
4. **Creative intelligence**: DNA materials, lighting, REALISM, AVOID (essential, irreducible)
5. **Quality floor**: compact_realism (essential, minimal)
6. **Quality ambition**: simplified WOW (useful, can be minimal)

**Total sustainable prompt cost:** ~1300-1600 chars  
**Current prompt cost:** ~2905 chars  
**Reduction opportunity:** ~45-55%

### 6.4 What Remains Uncertain

1. **Mask independent contribution**: With `input_fidelity=high`, does the mask provide measurable additional preservation? Needs A/B test.
2. **Vision analysis ROI**: Does the ~200-char SOURCE SPACE text description provide meaningful FIRST_VISION preservation beyond `input_fidelity=high`? If not, removing vision analysis saves 3-8s latency per request.
3. **WOW directive's unique role**: Does "TRANSFORMATION AMBITION" drive meaningfully higher transformation quality in rendered outputs? Or does DNA + quality=high already provide sufficient quality signaling? Needs blind scoring of outputs with/without WOW directive.
4. **DNA furniture list tension**: How often does the model replace vs restyle uploaded furniture when specific pieces are listed? This requires PROD output analysis.

---

## Part 7: Inference Cost Model

| Stage | Cost | Latency | Notes |
|-------|------|---------|-------|
| Image fetch | ~$0 | 500-2000ms | Network only |
| Vision analysis (GPT-4o-mini) | $0.004 | 3000-8000ms | Per-request fixed cost |
| Prompt composition | ~$0 | ~2ms | Pure CPU |
| Mask generation | ~$0 | ~50ms | PIL, async |
| OpenAI images.edit (attempt 1) | $0.190 (high, 1536x1024) | 30000-90000ms | Dominates |
| Supabase upload | ~$0 | 300-1500ms | Network |
| **Total PROD (no retry)** | **~$0.194** | **~35-100s** | |
| **Total PROD (with 1 retry)** | **~$0.388** | **~70-190s** | Doubles cost + latency |

**Vision analysis = 2% of cost, 4-8% of latency.**  
The 3-8s vision analysis latency is proportionally significant at the low end of OpenAI latency (~35s total), less significant at the high end (~100s). Reducing max_tokens from 220 to ~100 could cut vision analysis latency to ~2-4s with minimal information loss for structural anchor detection.

**Retry is the dominant cost and latency risk:**  
One retry doubles total cost from $0.194 → $0.388 and total latency from ~50s → ~100s. Any change that reduces retry rate has compounding benefit: fewer retries = lower latency + lower cost + better user experience.

**How retries currently trigger:**  
- Technical failures (TRANSIENT): network errors, timeouts, server errors → correctly retried
- Quality failures: currently NOT a retry signal (by design)
- Content policy (BadRequestError): NOT retried (non-transient)
- The retry system currently ignores prompt-quality as a signal, which is correct — the system cannot distinguish "output looks wrong" from "output violates policy" without AI evaluation of the generated image

---

## Part 8: Analysis Summary

### What the Audit Found

**1. The API-level signals are the dominant preservation mechanism.**  
`input_fidelity=high` + `quality=high` + aspect ratio do more for preservation than any prompt section. The prompt provides vocabulary alignment and creative direction on top of these.

**2. The prompt has ~18% redundancy.**  
~500-600 chars of the ~2905-char FIRST_VISION prompt restate the same three concepts (same apartment, frozen geometry, restyle only). This redundancy does not necessarily hurt quality, but it reduces budget headroom and cognitive focus for the model.

**3. DNA is the hardest-to-replace system.**  
Atmosphere DNA drives atmosphere-specific quality in a way no other system can replicate. The material palette, lighting behavior, REALISM constraints, and AVOID rules are all load-bearing. The furniture_language specificity is the one area with a genuine tension.

**4. The vision analysis is useful but potentially overpriced.**  
$0.004 and 3-8s latency for a 200-char room description. The primary value is the anchor detector (STYLE_REFINEMENT path). The value for FIRST_VISION source_space is harder to isolate from `input_fidelity=high`.

**5. The three historical preservation layers (Tier 1 constants, old WOW, old realism) should be cleaned up at Wave 4.6.**  
They add code complexity and validator coupling without contributing to runtime quality.

**6. Two genuine contradictions exist:**  
- DNA furniture list vs "Decorate this photo — do not recompose"  
- interior_completeness vs minimally furnished uploads  
These are the most likely remaining causes of "AI apartment" feeling in outputs.

**7. The budget system is not under real pressure at current usage.**  
With 200-400 char source descriptions and current DNA sizes, all sections survive with 388-711 chars of headroom. Budget pressure was a problem in Wave 4.4.0 and before; it is not a problem now.
