# Prompt System Simplification Audit

**Version:** Wave 4.5.0  
**Purpose:** Classify every prompt layer and document Wave 4.5.0 changes.

---

## Audit Classification Legend

| Label | Meaning |
|-------|---------|
| KEEP | Correct, non-redundant, load-bearing — do not touch |
| SIMPLIFY | Too verbose or defensively written — reduce without changing vocabulary |
| MERGE | Overlaps with another layer — combine into one |
| REMOVE | Obsolete or superseded — safe to delete |
| DEFER | Good candidate for future simplification — needs measurement first |

---

## Layer-by-Layer Audit

### 1. Task Framing (`fidelity_layer.py` — `build_first_vision_task`)

**Current size:** ~200 chars  
**Classification: KEEP**

The "SAME APARTMENT — apply {name}" framing is the correct mental model anchor.
It establishes spatial truth before any transformation signal. Wave 4.3.3 insight:
the opening verb matters more than any subsequent constraint.

No change in Wave 4.5.0.

---

### 2. Structural Contract Tier 1 (`build_structural_contract`) — FIRST_VISION

**Current size:** ~1550 chars (living room)  
**Classification: SIMPLIFY → IMPLEMENTED as Tier 1.5**

**Redundancy identified:**
- `_CAMERA_LOCK` (~280 chars): "camera position, height, viewing angle, perspective, focal length, vanishing points, horizon line. Room proportions, spatial depth, and all structural lines are fixed. This space already exists physically — DO NOT reinterpret geometry, DO NOT redesign architecture, or shift perspective. Output must look like a photograph of the SAME apartment with new surfaces, preserving its architectural identity. Any geometry or perspective change is a failure."
- `_STRUCTURAL_LOCK` (~340 chars): seven-point FORBIDDEN list
- `_TRANSFORMATION_SCOPE` (~180 chars): "CHANGE ONLY: floor/wall/ceiling finishes; furniture; lighting; textiles; decorative objects..."
- `_ROOM_STRUCTURAL` (~120 chars): room-specific preservation note
- `_ATMOSPHERE_BOUNDARY` (~280 chars): five-point priority order

**Redundancy analysis:**
- _CAMERA_LOCK and _ATMOSPHERE_BOUNDARY both say "camera > atmosphere" — duplicate
- _STRUCTURAL_LOCK lists 7 items; _TRANSFORMATION_SCOPE inverts the same list — mirror duplication
- _ATMOSPHERE_BOUNDARY five-point priority list is redundant given the explicit LOCKED/FORBIDDEN above
- Total defensive repetition: ~400-500 chars that say the same things twice

**Action (Wave 4.5.0):** Added `build_simplified_fv_contract()` (Tier 1.5, ~820 chars).
All required vocabulary preserved. Redundant prose removed.

**Savings:** ~730 chars per FIRST_VISION prompt (~47% reduction in contract size).

Note: Old constants (`_CAMERA_LOCK`, `_STRUCTURAL_LOCK`, etc.) preserved unchanged for
backward compatibility with early validator suites.

---

### 3. Structural Contract Tier 2 (`build_structural_evolution_contract`) — STRUCTURAL_TRANSFORMATION

**Current size:** ~650 chars  
**Classification: KEEP**

Already compact. Uses `_CAMERA_LOCK_COMPACT` (Wave 4.2.4). Appropriate for structural
mode where some constraint relaxation is intentional.

No change in Wave 4.5.0.

---

### 4. Atmosphere Switch Contract Tier 3.5 (`build_atmosphere_switch_contract`) — STYLE_REFINEMENT

**Current size:** ~515-870 chars (with room note + anchor clause)  
**Classification: KEEP for now / DEFER simplification**

"SAME APARTMENT — ATMOSPHERE SWITCH" + TOPOLOGY LOCKED is load-bearing for V2+.
Topology lock prevents the most common V2+ failure (collapsing multi-zone layouts
when switching atmospheres). Anchor clause adds zero cost when no anchors detected.

Candidate for future simplification (Wave 4.6+) once PROD data confirms the
topology lock is or isn't needed for standard V2+ scenarios.

---

### 5. WOW Directive (`wow_layer.py` — `build_first_vision_wow_directive`)

**Current size:** ~259 chars  
**Classification: KEEP**

The transformation ambition directive is load-bearing for premium V1 quality.
Text is frozen by validator suite checks (exact vocabulary required).

Minor redundancy: "Visible architecture stays recognizable: windows, openings, partitions"
overlaps with the contract's STRUCTURAL LOCK. However, this overlap is intentional —
the WOW directive re-grounds the model in architecture after the transformation ambition
signal, preventing the model from conflating "editorial redesign" with "new apartment."

No change in Wave 4.5.0.

---

### 6. Atmosphere DNA (`atmosphere_dna/`)

**Current size:** ~823-996 chars per atmosphere+room  
**Classification: KEEP**

DNA blocks are the primary creative intelligence layer. They drive:
- Atmosphere character expression
- Room-specific material and furniture language
- Lighting behavior for the atmosphere
- Premium quality floor

DNA blocks are NOT about preservation — they are about transformation quality.
Never compress DNA blocks. The size variation (823-996 chars) reflects genuine
content differences between atmospheres.

No change in Wave 4.5.0.

---

### 7. Compact Realism Block (`build_compact_realism_block`)

**Current size:** ~133 chars  
**Classification: KEEP**

The anti-CGI vocabulary floor. "NOT a CGI render. DSLR real estate photograph quality.
Real materials, natural light physics, no plastic surfaces, no render feeling."
Non-negotiable. Survives even under maximum budget pressure.

No change in Wave 4.5.0.

---

### 8. Medium Realism Block (`build_medium_realism_block`)

**Current size:** ~310 chars  
**Classification: DEFER**

Not used in the active path since Wave 4.4.1 switched FIRST_VISION to compact_realism.
Preserved as a fallback. Could be removed if Wave 4.5.0 simplification proves stable
and the compact block is sufficient.

No change in Wave 4.5.0. Evaluate removal at Wave 4.6.

---

### 9. Full Realism Block (`build_realism_block`)

**Current size:** ~995 chars  
**Classification: DEFER / REMOVE**

No longer used in any active path since Wave 4.2.4. The compact realism block covers
the critical vocabulary. The full block added ~860 chars of extended prose with
diminishing returns.

Candidate for removal at Wave 4.6 after confirming compact_realism is sufficient.

---

### 10. Interior Completeness Rule (`build_interior_completeness_rule`)

**Current size:** ~298 chars  
**Classification: KEEP at P5 / Monitor**

"INTERIOR COMPLETENESS: The space must feel fully designed and emotionally inhabited..."

Was dropping at P5 for large-DNA atmospheres (e.g., Soft Luxury) in Wave 4.4.1 with
the old contract. With Wave 4.5.0 simplified contract, it now survives for all
atmospheres at standard source descriptions.

The message is valid but somewhat covered by atmosphere DNA (which specifies furniture,
decor, styling for each room). Could be merged into compact_realism in a future wave.

P5 priority remains appropriate — it's a nicety compared to wow_directive.

No change in Wave 4.5.0.

---

### 11. Anchor Detector (`anchor_detector.py`)

**Current size:** ~0-185 chars (zero cost when no anchors)  
**Classification: KEEP**

Deterministic text matching, no API calls, no latency impact. Only adds to the prompt
when architectural anchors (glass partitions, multi-zone layouts, specific openings) are
detected in the vision analysis. Clause size is hard-capped.

The most efficient targeted enrichment in the system. Keep as-is.

No change in Wave 4.5.0.

---

### 12. Dream Scene Completion (`build_scene_completion`)

**Current size:** ~280-380 chars  
**Classification: KEEP (non-DNA path only)**

Used only in FIRST_VISION for atmospheres without room-specific DNA (rare fallback).
When DNA is registered, this is completely replaced by the DNA block. Not a redundancy
concern since it's only active on the fallback path.

No change in Wave 4.5.0.

---

### 13. Dream Micro Layer (`build_dream_micro_layer`)

**Current size:** ~78 chars  
**Classification: KEEP (STYLE_REFINEMENT DNA path)**

"Layered lighting, complete furnishing composition, emotionally warm atmosphere."
Used in STYLE_REFINEMENT to assert warm livability beyond what the DNA materials
and furniture description provides. Small footprint, genuine value.

No change in Wave 4.5.0.

---

### 14. Continuation Contract Tier 3 (`build_continuation_contract`)

**Current size:** ~530 chars  
**Classification: DEFER / REMOVE**

Not used in the active STYLE_REFINEMENT path since Wave 4.3.0 replaced it with
`build_atmosphere_switch_contract()` (Tier 3.5). Preserved for backward compatibility.
Candidate for removal at Wave 4.6.

---

### 15. Vision Analysis Usage (GPT-4o-mini, `main.py`)

**Cost:** ~$0.004/call, ~3-8s latency  
**Classification: DEFER optimization**

The room_description informs:
- anchor_detector (structured anchor detection)
- source_space section in prompts

Optimization candidates (deferred, need PROD data):
- Skip for STYLE_REFINEMENT if room_description from V1 is cached
- Reduce max_tokens (220 → 100) — may lose structural detail

No change in Wave 4.5.0.

---

## Wave 4.5.0 Changes Summary

| Layer | Before | After | Saving |
|-------|--------|-------|--------|
| FIRST_VISION contract | Tier 1 (~1550 chars) | Tier 1.5 (~820 chars) | ~730 chars |
| All other layers | unchanged | unchanged | 0 |

---

## Estimated Impact

### Prompt Size Reduction (FIRST_VISION, 200-char source)

| Atmosphere | Before (chars) | After (chars) | Reduction |
|-----------|---------------|--------------|-----------|
| Soft Luxury (living room) | 3315 | 2908 | -407 (12%) |
| Dark Contemporary (living room) | 3393 | 2970 | -423 (12%) |
| Zen Retreat (living room) | 3270 | 2847 | -423 (13%) |
| Japandi Calm (living room) | 3310 | 2880 | -430 (13%) |

Note: Interior_completeness now survives in all scenarios (was dropping before).
Effective quality gain: interior_completeness content returned to prompts.

### Payload Reduction

prompt reduction: ~730 bytes per FIRST_VISION call  
image + mask dominates payload (800KB-1.8MB); prompt is 0.03-0.05% of payload  
**Payload reduction: negligible (<0.1%)**

### Latency Impact

At OpenAI tokenization rate: ~730 chars ≈ ~180 tokens fewer  
Estimated impact: <1 second on OpenAI side  
**Latency reduction: negligible for individual calls**

Primary latency benefit: less budget pressure → no section drops → better quality →
lower retry rate. If simplified contract reduces retries by even 5%, that's
meaningful latency reduction (retries add 60-90s each).

### Retry Impact

Before: wow_directive dropped for large-DNA atmospheres with long source descriptions.
After: All sections survive at standard source lengths. wow_directive is preserved for
source descriptions up to ~600 chars for the largest DNA (Dark Contemporary ~996 chars).

**Expected: minor reduction in retry-triggering quality failures.**

---

## Future Simplification Candidates (Wave 4.6+)

Priority order:

1. **Remove `build_realism_block()`** — unused since Wave 4.2.4
2. **Remove `build_continuation_contract()`** — unused since Wave 4.3.0
3. **Simplify `build_atmosphere_switch_contract()`** — good candidate for 15-20% trim
4. **Remove `build_medium_realism_block()`** — unused since Wave 4.4.1
5. **Integrate interior_completeness into compact_realism** — one fewer section
6. **Simplify vision analysis prompt** — reduce max_tokens from 220 to ~120
7. **Simplify wow_directive** — remove "Visible architecture stays recognizable" (covered by contract)

---

## Red Lines (Do Not Touch)

The following must never be simplified, removed, or weakened:

| System | Reason |
|--------|--------|
| `input_fidelity=high` | Primary fidelity mechanism — API level |
| `quality=high` | Primary quality mechanism — API level |
| Structural mask (ENABLE_STRUCTURAL_MASK) | Pixel-level perimeter protection |
| Aspect-ratio output size | Room proportion preservation |
| SAME APARTMENT task framing | Mental model anchor — opening verb matters |
| atmosphere DNA blocks | Creative intelligence — premium quality driver |
| compact_realism block | Anti-CGI quality floor |
| max_retries=0 | Prevents uncontrolled cost amplification |
| TOPOLOGY LOCKED (SR path) | V2+ multi-zone identity lock |
