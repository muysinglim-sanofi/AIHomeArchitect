# Feature Classification — Wave 4.5.2

**Version:** Wave 4.5.2  
**Purpose:** One-line classification of every system with rationale and recommended action.  
**Classes:** ESSENTIAL · USEFUL · REDUNDANT · HISTORICAL · CONTRADICTORY · TOO_EXPENSIVE · POTENTIALLY_HARMFUL

---

## Classification Legend

| Class | Meaning |
|-------|---------|
| **ESSENTIAL** | Cannot be removed without measurable quality or fidelity regression |
| **USEFUL** | Provides real value; removal would degrade performance but not catastrophically |
| **REDUNDANT** | Duplicates information already present in another layer; net contribution near zero |
| **HISTORICAL** | Existed to solve a problem that is now solved by a better system; no longer needed |
| **CONTRADICTORY** | Sends a signal that conflicts with another layer's signal |
| **TOO_EXPENSIVE** | Cost (latency, tokens, API cost) disproportionate to benefit |
| **POTENTIALLY_HARMFUL** | Could actively degrade fidelity or cause undesired model behavior |

---

## API Parameters (Zero Prompt Cost)

| Feature | Classification | Rationale | Action |
|---------|---------------|-----------|--------|
| `input_fidelity=high` | **ESSENTIAL** | Strongest single fidelity signal. All preservation contracts compensate for its absence. | Keep forever |
| `quality=high` | **ESSENTIAL** | Primary quality mechanism. Luxury product requires premium rendering. | Keep forever |
| `model=gpt-image-1` | **ESSENTIAL** | Only model supporting `input_fidelity`. | Keep |
| Aspect-ratio output size detection | **ESSENTIAL** | Room proportions cannot distort. Wrong output size physically destroys spatial fidelity. | Keep |
| `max_retries=0` (SDK-level) | **ESSENTIAL** | Without this: 9 API calls per request max. Cost and latency uncontrolled. | Keep forever |

---

## Infrastructure Systems

| Feature | Classification | Rationale | Action |
|---------|---------------|-----------|--------|
| Structural mask (perimeter + window + edge) | **USEFUL** | Pixel-level geometric constraint orthogonal to prompt. Adds ~50ms. Contribution not PROD-isolated. | Keep; measure impact at Wave 4.6 |
| Mask async run_in_executor | **ESSENTIAL** | Without this: event loop blocked 2-5s (root cause of Wave 4.2 RemoteProtocolError). | Keep forever |
| retry_classifier.py | **ESSENTIAL** | Distinguishes transient (retry) from non-transient (surface immediately). Prevents wasted retries. | Keep |
| Generation profiles (dev/prod) | **ESSENTIAL** | DEV profile: $0.020/image vs $0.190 PROD. Without it, iterative dev becomes extremely expensive. | Keep |
| PipelineTimer / performance_observer.py | **USEFUL** | Observability: stage timing, cost estimation, PROD latency analysis. | Keep |

---

## Pipeline Steps

| Feature | Classification | Rationale | Action |
|---------|---------------|-----------|--------|
| Image fetch from URL | **ESSENTIAL** | Required. | Keep |
| Vision analysis (GPT-4o-mini, 3-8s) | **USEFUL** for SR path; **REDUNDANT** for FIRST_VISION | Anchor detection (SR) is valuable. Source_space section adds ~200 chars P1. For FV, `input_fidelity=high` provides stronger spatial grounding than the text description. | Measure: is source_space section in FIRST_VISION providing meaningful benefit beyond input_fidelity? |
| classify_edit_mode | **ESSENTIAL** | Routes to correct prompt path. Wrong path = catastrophic quality failure. | Keep |
| classify_transformation (Wave 3.4.1) | **USEFUL** | Elevates LOCAL_EDIT to STRUCTURAL_TRANSFORMATION for functional reassignment. Prevents wrong path routing. | Keep |
| Surprise Me / Let AI Decide | **USEFUL** | Product features, not quality systems. | Keep |
| secondary_spaces / visible_space_logic | **USEFUL** | Handles multi-zone scenes. Low cost (0-200 chars). Fires only when needed. | Keep |

---

## Prompt Sections — FIRST_VISION Path

| Section | Priority | Typical Size | Classification | Rationale | Action |
|---------|----------|-------------|----------------|-----------|--------|
| Task (SAME APARTMENT — apply {atm}) | P1 | ~175 chars | **ESSENTIAL** | Opening token mental model. Most important two words in the entire prompt. | Keep; consider simplifying elaboration |
| Tier 1.5 contract (build_simplified_fv_contract) | P1 | ~820 chars | **USEFUL** | Vocabulary alignment. Partially redundant with task framing. Still valuable as explicit forbidden list. | Consider further simplification at Wave 4.6 |
| Source space (from vision analysis) | P1 | ~200-400 chars | **USEFUL** | Room grounding. Never dropped (P1). Feeds from vision analysis. Value proportional to description accuracy. | Keep; reduce max_tokens from 220 to ~120 to cut vision analysis latency |
| Design Intel — DNA block | P2 | ~823-996 chars | **ESSENTIAL** | Primary creative quality driver. Without DNA, outputs are generic. | Keep; consider separating furniture list from materials/lighting |
| Interior completeness | P5 | ~298 chars | **REDUNDANT/CONTRADICTORY** | DNA already specifies furnishing. "Never sparse" conflicts with minimally furnished uploads. | Remove from FIRST_VISION path; keep for non-DNA fallback only |
| Scene completion (non-DNA fallback) | P4 | ~280-380 chars | **POTENTIALLY_HARMFUL** | "COMPLETE THE SCENE: include sofa grouping..." instructs object addition. Conflicts with photo-first philosophy. | Rewrite: remove element checklist; keep quality/atmosphere note only |
| WOW directive (restyling, Wave 4.5.1) | P4 | ~326 chars | **USEFUL** | Unique quality ambition signal. Partially redundant on preservation. "Decorate this photo" is load-bearing. | Keep; consider removing redundant preservation phrases |
| compact_realism | P3 | ~133 chars | **ESSENTIAL** | Anti-CGI quality floor. "NOT a CGI render. DSLR." are the highest-ROI chars in the prompt. | Keep forever |
| design_direction (user instruction) | P5 | 0-300 chars | **USEFUL** | User's explicit direction for V1. Rare for FIRST_VISION but valid. | Keep at P5 |

---

## Prompt Sections — STYLE_REFINEMENT Path

| Section | Priority | Typical Size | Classification | Rationale | Action |
|---------|----------|-------------|----------------|-----------|--------|
| SR header (SAME APARTMENT CONTINUATION) | P1 | ~300 chars | **ESSENTIAL** | Establishes continuation frame. | Keep |
| Atmosphere switch contract (Tier 3.5) | P1 | ~515-870 chars | **ESSENTIAL** | TOPOLOGY LOCKED prevents most common V2+ failure. Anchor clause fires only when needed. | Keep; candidate for 15-20% trim at Wave 4.6 |
| Source space | P1 | ~200 chars | **USEFUL** | Same analysis as FV path. | Keep |
| Design Intel | P2 | ~823-996 chars | **ESSENTIAL** | Drives atmosphere quality. | Keep |
| dream_micro (DNA path) | P4 | ~78 chars | **REDUNDANT** | "Layered lighting, complete furnishing composition" — DNA already specifies this. | Remove; DNA covers this |
| dream_addendum (non-DNA path) | P4 | ~90-130 chars | **USEFUL** | Quality aspiration for fallback path only. | Keep for non-DNA |
| visible_spaces | P5 | ~90-200 chars | **USEFUL** | Multi-zone atmosphere coherence. Fires only when needed. | Keep |
| refinement_memory | P5 | 0-400 chars | **USEFUL** | Remembers user preferences across iterations. Unique to this system. | Keep |
| compact_realism | P3 | ~133 chars | **ESSENTIAL** | Same as FIRST_VISION. | Keep |

---

## Preserved-But-Unused Systems (HISTORICAL)

These exist in code for validator backward compatibility only:

| System | Classification | Reason Preserved | Safe to Remove At |
|--------|---------------|-----------------|-------------------|
| `build_structural_contract()` + Tier 1 constants | **HISTORICAL** | validate_wave425–433 import directly | Wave 4.6 (update validators) |
| `build_continuation_contract()` | **HISTORICAL** | Replaced by atmosphere_switch_contract (Wave 4.3.0) | Wave 4.6 |
| `build_realism_block()` (full, ~995 chars) | **HISTORICAL** | Replaced by compact_realism (Wave 4.2.4) | Wave 4.6 |
| `build_medium_realism_block()` (~310 chars) | **HISTORICAL** | Replaced by compact in FV path (Wave 4.4.1) | Wave 4.6 |
| `build_first_vision_wow_directive()` + `_WOW_DIRECTIVE` | **HISTORICAL** | Replaced by build_restyling_wow_directive (Wave 4.5.1) | Wave 4.6 (update validators) |

---

## The Core Contradictions

### Contradiction 1: DNA furniture list vs photo-first philosophy

| Layer | Signal |
|-------|--------|
| WOW directive | "Decorate this photo — do not recompose it." |
| DNA furniture_language | "deep curved bouclé sofa in ivory or blush; honed marble coffee table on brushed brass base; barrel-back cashmere armchairs" |

**Impact:** When uploaded furniture differs from DNA furniture, model must choose. Specific piece names in DNA may cause replacement rather than restyling.

**Resolution options:**  
A. Change furniture_language to material/texture language ("bouclé-upholstered seating in warm ivory tones; stone or marble surface table")  
B. Add explicit instruction: "Apply these materials and atmosphere to the existing furniture — do not replace or relocate it"  
C. Separate DNA into two tiers: realism_dna (always inject) and composition_dna (only inject if no upload)

---

### Contradiction 2: interior_completeness vs sparse uploads

| Layer | Signal |
|-------|--------|
| interior_completeness | "never sparse, empty, under-furnished, or minimally staged" |
| Photo-first philosophy | Uploaded photo IS the truth — if it's sparse, preserve that |

**Impact:** Minimally furnished uploads may be over-furnished in output.

**Resolution:** Remove interior_completeness from FIRST_VISION (DNA handles richness for DNA-registered rooms). Keep only for non-DNA fallback.

---

### Contradiction 3: scene_completion vs photo-first

| Layer | Signal |
|-------|--------|
| build_scene_completion | "COMPLETE THE SCENE: include sofa grouping, coffee table, area rug, floor lamps..." |
| Photo-first philosophy | Preserve what's in the photo |

**Impact:** Most direct composition-override instruction in the system. Fortunately only fires on non-DNA paths.

**Resolution:** Replace element checklist with atmosphere quality note only. Remove "include [specific furniture]" instruction.

---

## Priority Recommendation for Future Waves

### Highest impact / lowest risk:
1. Remove `interior_completeness` from FIRST_VISION DNA path (REDUNDANT + CONTRADICTORY)
2. Rewrite `build_scene_completion` non-DNA fallback (remove element checklist; keep quality note)
3. Remove `dream_micro` from STYLE_REFINEMENT DNA path (REDUNDANT with DNA)

### Medium impact:
4. Change DNA `furniture_language` from specific pieces to material/texture vocabulary
5. Simplify task framing: remove reconstruction elaboration, keep "SAME APARTMENT — apply {atm} to this photo"
6. Reduce vision analysis max_tokens (220 → 100): cuts latency 1-3s with minimal info loss
7. Simplify Tier 1.5 contract further: remove ROOM LOCK (not grounded in actual photo)

### Lower priority:
8. Measure mask contribution independently (A/B test: mask vs no-mask with `input_fidelity=high`)
9. Remove all HISTORICAL frozen functions after updating validators (Wave 4.6)
10. Measure source_space contribution to FV quality: does ~200-char text description add value beyond input_fidelity=high?

---

## What NOT to Touch

| System | Reason |
|--------|--------|
| `input_fidelity=high` | Single most important signal — its removal would require rebuilding all preservation layers |
| `quality=high` | Premium product requirement |
| `SAME APARTMENT` as first task token | Mental model anchor — opening verb matters |
| DNA materials, lighting, AVOID sections | Primary creative quality driver — never compress |
| compact_realism ("NOT a CGI render. DSLR.") | Highest ROI chars in prompt — anti-CGI floor |
| max_retries=0 | Cost protection — removal = uncontrolled API spend |
| retry_classifier | Correct retry behavior — removal = retry on all failures |
| aspect_ratio detection | Room proportion preservation |
| Budget/priority system | Budget management — removal = unpredictable prompt overflow |
