# Full System Audit — Wave 4.5.2

**Version:** Wave 4.5.2  
**Date:** 2026-05-17  
**Purpose:** Complete architectural audit of the FIRST_VISION pipeline before further waves.  
**Scope:** Every active system — prompts, contracts, DNA, masks, vision analysis, retry, budget, realism, WOW, completeness.

---

## 1. Pipeline Architecture

```
User Upload (photo + atmosphere selection)
         │
         ▼
/generate endpoint (main.py)
         │
         ├─── [STEP 1] Image fetch (httpx, ~500ms-2s)
         │       └─ generation_image_url = original_url (V2+) or before_url (V1)
         │
         ├─── [STEP 2] Vision analysis (GPT-4o-mini, ~3-8s, $0.004)
         │       └─ room_description: ~200 chars structured output
         │
         ├─── [STEP 3] Resolve: let_ai_decide, surprise_me, secondary_spaces
         │
         ├─── [STEP 4] classify_edit_mode → FIRST_VISION / STYLE_REFINEMENT / LOCAL_EDIT / STRUCTURAL
         │       └─ + classify_transformation → FUNCTIONAL_REASSIGNMENT override
         │
         ├─── [STEP 5] compose_generation_prompt (composer.py)
         │       └─ FIRST_VISION path:
         │            task → contract → source → DNA → completeness → wow → realism
         │
         ├─── [STEP 6] Detect output size (aspect ratio preservation)
         │
         ├─── [STEP 7] Build structural mask (PIL, ~50ms, async)
         │       └─ Layer 1: perimeter gradient (18% border)
         │       └─ Layer 2: luminosity window detection
         │       └─ Layer 3: edge-density structural detection
         │
         ├─── [STEP 8] OpenAI images.edit (gpt-image-1, ~30-90s, $0.190)
         │       └─ quality=high, input_fidelity=high
         │       └─ retry loop: max 3 attempts (PROD), smart retry classifier
         │
         └─── [STEP 9] Supabase upload + return URL
```

---

## 2. System-by-System Audit

---

### SYSTEM 1 — `input_fidelity=high`

**Location:** `generation_profiles.py`, passed to `openai.images.edit()`  
**Size:** 0 prompt chars (API parameter)  
**Wave introduced:** PROD profile (always active)

**Exact role:**  
API-level instruction to gpt-image-1 to weight the source image heavily in conditioning.  
`input_fidelity=high` is OpenAI's strongest image-grounding signal — it tells the model to treat the uploaded photo as canonical spatial truth before any text instruction.

**Why introduced:**  
Was always active. Its explicit importance was understood after Wave 4.3.x analysis revealed that preservation contracts compensated for what this parameter was already doing.

**Does the problem still exist without it?**  
Yes. Without `input_fidelity=high`, the model treats the uploaded image as loose stylistic inspiration. All prompt preservation contracts become load-bearing without this.

**Costs:**  
- Prompt cost: 0 chars  
- Inference cost: priced into `quality=high` tier  
- Latency: none (API parameter)

**Impact:**  
- Quality: HIGH (primary quality driver)  
- Preservation: CRITICAL (strongest single preservation signal)  
- Latency: none  
- Retries: reduces retry rate (less reinvention = fewer quality failures)

**Classification: ESSENTIAL**

---

### SYSTEM 2 — `quality=high`

**Location:** `generation_profiles.py`, passed to `openai.images.edit()`  
**Size:** 0 prompt chars (API parameter)  
**Wave introduced:** PROD profile (always active)

**Exact role:**  
Selects the highest-quality generation tier for gpt-image-1. Controls rendering quality, photorealism, material fidelity.

**Does the problem still exist without it?**  
Yes. `quality=medium` or `quality=low` degrades material fidelity, lighting quality, and spatial coherence — exactly the premium quality we're selling.

**Costs:**  
- Cost: $0.190/image (high 1536x1024) vs $0.070 (medium) — 2.7× more expensive  
- Prompt: 0 chars

**Impact:**  
- Quality: CRITICAL (visual luxury + photorealism)  
- Preservation: indirect positive (higher-quality models follow instructions better)

**Classification: ESSENTIAL**

---

### SYSTEM 3 — Aspect-Ratio Output Size Detection

**Location:** `main.py::_detect_output_size()`  
**Size:** 0 prompt chars (runtime logic)  
**Wave introduced:** Early (Wave 4.x)

**Exact role:**  
Reads PIL dimensions of source image. Selects 1536x1024 (landscape), 1024x1536 (portrait), or 1024x1024 (square). Output format matches source format exactly.

**Why critical:**  
Forcing 1024x1024 on a landscape room compresses or distorts room proportions. The model may correct for this distortion by recomposing the space. A 1536x1024 source room output as 1024x1536 would flip the room proportions entirely.

**Classification: ESSENTIAL**

---

### SYSTEM 4 — Structural Mask (mask_generator.py)

**Location:** `mask_generator.py`, called in `main.py::build_structural_mask()`  
**Size:** 0 prompt chars (binary image sent to API)  
**Wave introduced:** Wave 4.4.0 (rewrite); mask system from earlier wave

**Exact role:**  
Generates a RGBA mask image (same dimensions as source) where:
- `alpha=0` (transparent) → model edits freely  
- `alpha>0` (opaque) → model preserves this region  

Three layers combined with max-protection:
1. **Perimeter gradient**: outer 18% of image (walls, corners, window frames near edges)
2. **Luminosity window detection**: bright zones (daylight windows, skylights)
3. **Edge-density detection**: structural lines (walls, door frames, partitions)

Applied only for FIRST_VISION and STYLE_REFINEMENT. Skipped for LOCAL_EDIT and STRUCTURAL_TRANSFORMATION.

**Why introduced:**  
Prompt-only preservation left the model free to reinterpret window positions and structural geometry. The mask works at pixel level, independent of the model's semantic understanding of the prompt.

**Does the problem still exist without it?**  
Uncertain. With `input_fidelity=high` + `SAME APARTMENT` task framing + Tier 1.5 contract, the mask provides a redundant safety layer. However, the mask directly constrains pixel modifications — it is orthogonal to semantic prompt instructions. The combination of both is expected to be stronger than either alone.

**Real cost:**  
- Payload: +30-100KB (PNG mask, compressed, same as source dimensions)  
- Latency: ~50ms PIL (runs async, non-blocking)  
- Total payload with mask: ~850KB-1.9MB per request (image dominates)

**Uncertainty:**  
It is unknown from available data whether the mask measurably improves preservation beyond `input_fidelity=high`. PROD data would be needed to isolate the effect.

**Classification: USEFUL (unverified independent contribution; likely additive)**

---

### SYSTEM 5 — Vision Analysis (GPT-4o-mini)

**Location:** `main.py` Step 4  
**Size:** ~200 chars output, injected as SOURCE SPACE (P1) and fed to anchor_detector  
**Wave introduced:** Wave 4.x

**Exact role:**  
Calls GPT-4o-mini with `detail=high` to produce a structured 4-sentence room description:
- Room type and function
- Window count, positions, floor-to-ceiling vs standard
- Camera angle (eye-level / slightly high / slightly low)
- Perspective (single vs two-point vanishing)
- Spatial depth (shallow / medium / deep)
- Ceiling type
- Key structural anchors (columns, island, fireplace wall)

This output is used for:
1. `source_space` section in prompt (P1 — never dropped)
2. `detect_anchors()` input → potential anchor clause in STYLE_REFINEMENT
3. `classify_room()` (let_ai_decide)
4. `surprise_me()` (atmosphere selection)

**Current prompt injected:**
```
SOURCE SPACE: [~200 char structured description of the room]
```

**Why introduced:**  
To ground the generation prompt in actual photo geometry rather than user-provided description. The vision analysis creates factual structural anchors (window count, perspective type) that text-only prompts cannot know.

**Does the problem still exist without it?**  
The anchor detector only fires for STYLE_REFINEMENT (V2+), so for FIRST_VISION, the primary use is the `source_space` section. Without this, `source_space` would be empty and the model would have less spatial grounding from the prompt side. However, `input_fidelity=high` provides stronger spatial grounding at the API level.

**Costs:**  
- Latency: 3-8s (significant — runs before mask and OpenAI call)  
- Cost: $0.004/call (~2% of image cost)  
- Prompt: ~200 chars in `source_space` (P1 — always present)

**Concern:**  
The GPT-4o-mini description is a simplified, textual summary of the room. It loses spatial precision (e.g., "window on left wall" vs the actual pixel location). The model reading "large window on the left wall" doesn't get the same constraint as `input_fidelity=high` + mask seeing the actual pixel distribution. **The text description may provide limited marginal benefit for FIRST_VISION spatial preservation** beyond what the image itself provides. The latency cost (~5s avg) is relatively high for this benefit.

**Classification: USEFUL for STYLE_REFINEMENT (anchor detection); MARGINAL for FIRST_VISION spatial preservation (3-8s latency cost may not be justified)**

---

### SYSTEM 6 — Task Framing (`fidelity_layer.py`)

**Location:** `prompt_engine/fidelity_layer.py::build_first_vision_task()`  
**Size:** ~175-220 chars (P1 — never dropped)  
**Wave introduced:** Wave 4.3.3

**Exact current text (SL living room):**
```
SAME APARTMENT — apply Soft Luxury Gold atmosphere. 
The photo defines spatial truth: reproduce this living room's geometry, 
camera, windows, openings, and depth exactly. 
Then transform all surfaces, materials, and light.
```

**Why introduced:**  
The old "REDESIGN — this room as a X interior" task framing gave implicit permission for spatial reinvention. "REDESIGN" as first token established an architectural creative frame. Replacing it with "SAME APARTMENT — apply {atmosphere}" changed the model's opening mental model from "redesign" to "restyle."

**Does the problem still exist?**  
Partially. "reproduce this living room's geometry... exactly" is still reconstruction-language rather than restyling-language. The phrase "The photo defines spatial truth" correctly positions the photo as dominant. "Then transform all surfaces, materials, and light" is the restyling instruction.

**Assessment:**  
"SAME APARTMENT" is clearly the most important two-word signal. The rest of the task text reinforces it. However, "reproduce... geometry... exactly. Then transform..." still frames FIRST_VISION as a two-step reconstruction+transformation, rather than "apply atmosphere directly to the photo." This may be unnecessarily complex framing for what should be: "restyle this photo."

**Redundancy:**  
- "geometry, camera, windows, openings, and depth exactly" — also stated in Tier 1.5 contract (CAMERA LOCK, STRUCTURAL LOCK)
- "transform all surfaces, materials, and light" — also stated in contract (CHANGE ONLY:)

**Classification: ESSENTIAL (SAME APARTMENT first-token framing); PARTIALLY REDUNDANT (the elaboration overlaps contract)**

---

### SYSTEM 7 — Tier 1.5 Structural Contract (`preservation.py::build_simplified_fv_contract`)

**Location:** `prompt_engine/preservation.py`  
**Size:** ~700-820 chars (P1 — never dropped)  
**Wave introduced:** Wave 4.5.0 (replaces Tier 1 ~1550 chars)

**Exact current text (living room):**
```
CAMERA LOCK — FROZEN: camera position, focal length, vanishing points, horizon line. 
Room proportions, spatial depth, and all structural lines are fixed. 
Output must look like a photograph of the SAME apartment, preserving its architectural identity. 
DO NOT reinterpret geometry. DO NOT redesign architecture. 
STRUCTURAL LOCK — FORBIDDEN: windows (positions, frames, unblocked, natural light visible), 
doors, walls, ceiling height, floor plan, structural columns. 
CHANGE ONLY: surfaces, materials, furniture, lighting, textiles, colours, atmosphere. 
ATMOSPHERE BOUNDARY — geometry, openings, and topology override atmosphere. 
Atmosphere is applied last. Any perspective or geometry change is a failure.
ROOM LOCK: preserve TV wall or fireplace position, sofa zone, all window orientations, 
open-floor-to-furnished ratio.
```

**Why introduced:**  
Wave 4.5.0 simplification of the original Tier 1 (~1550 chars). The original had _CAMERA_LOCK, _STRUCTURAL_LOCK, _TRANSFORMATION_SCOPE, _ATMOSPHERE_BOUNDARY stacked in order — many of these restated the same constraints with different words.

**Internal redundancy analysis:**
- "camera position, focal length, vanishing points, horizon line" — TASK already says "reproduce... camera... exactly"
- "STRUCTURAL LOCK — FORBIDDEN: windows... doors... walls..." — TASK already says "reproduce... openings... exactly"  
- "CHANGE ONLY: surfaces, materials, furniture, lighting..." — TASK already says "transform all surfaces, materials, and light"
- "Any perspective or geometry change is a failure" — TASK says "reproduce... geometry... exactly"

**Assessment:**  
The contract repeats the task framing with more technical vocabulary. Whether this is genuine reinforcement or redundant repetition depends on whether more specific vocabulary (vanishing points, focal length, FORBIDDEN list) meaningfully constrains the model beyond what "SAME APARTMENT" + `input_fidelity=high` already provide.

**ROOM LOCK concern:**  
"preserve TV wall or fireplace position, sofa zone..." — this instructs the model about the uploaded room's features using assumptions. If the room has no TV wall or fireplace, this note still refers to those specific elements. It is a generic room-type instruction, not grounded in the actual uploaded photo.

**Classification: USEFUL (vocabulary alignment with the model's training on these terms); PARTIALLY REDUNDANT (with task framing)**

---

### SYSTEM 8 — Atmosphere DNA (`atmosphere_dna/`)

**Location:** `prompt_engine/atmosphere_dna/`, rendered by `build_dna_block()`  
**Size:** ~823-996 chars per atmosphere+room (P2 — dropped only if forced)  
**Wave introduced:** Wave 4.1/4.2 era

**Exact current output (Soft Luxury living room):**
```
ATMOSPHERE (Soft Luxury): Refined hospitality luxury emphasizing softness, elegance, 
tactile richness, and timeless sophistication. — Indulgent, serene, tactile, quietly 
opulent, feminine-refined, sensorially rich. [Rosewood / Aman / luxury suite]
ROOM (Living Room): fluted ivory plaster walls, honed cream marble floor, brushed 
champagne metal accents. LIGHT: Concealed perimeter cove + silk shade floor lamps; 
warm evening tone, no ceiling spotlights. ATMOSPHERE STYLE (restyle existing elements): 
deep curved bouclé sofa in ivory or blush; honed marble coffee table on brushed brass base; 
barrel-back cashmere armchairs; oversized ceramic vessel with dried pampas or lunaria; 
layered silk and bouclé cushions in cream and blush. REALISM: sofa sized to room — not 
oversized for space; marble floor with correct 3–5 mm grout lines. 
AVOID: no jewel-tone colour pops, no gold leaf or metallic wallpaper, no asymmetric art 
gallery wall, no visible TV above fireplace, Bling luxury, crystal chandelier clichés.
```

**Why introduced:**  
To drive premium atmosphere transformation quality. Generic style names ("Japandi," "Soft Luxury") gave the model insufficient information about what materials, lighting, and furniture vocabulary to use. DNA blocks encode curator-level design knowledge that produces unmistakably authentic atmospheres.

**Genuine contribution:**  
DNA is the primary creative intelligence layer. Without DNA, generated outputs converge toward generic "luxury apartment" regardless of atmosphere. DNA is what makes a Soft Luxury room look genuinely different from a Japandi room.

**Critical tension:**  
The `furniture_language` list: "deep curved bouclé sofa in ivory or blush; honed marble coffee table on brushed brass base; barrel-back cashmere armchairs" — these are specific piece descriptions. When the uploaded photo has different furniture, the model faces: 

> "Decorate this photo — do not recompose it" (WOW directive)  
> vs.  
> "ATMOSPHERE STYLE (restyle existing elements): deep curved bouclé sofa in ivory or blush" (DNA)

The DNA says "restyle existing elements" (after Wave 4.5.1) but still lists specific pieces. A model that is uncertain may default to placing the specified pieces rather than restyling what's there.

**Lighting_behavior:** Specific and load-bearing. "Concealed perimeter cove + silk shade floor lamps; warm evening tone, no ceiling spotlights" is rich creative guidance that does not conflict with photo preservation.

**Material_palette, REALISM, AVOID:** These sections describe surfaces and constraints, not spatial composition — they are safe and do not conflict with photo preservation.

**Classification:**  
- ATMOSPHERE line: ESSENTIAL  
- Material palette: ESSENTIAL  
- Lighting behavior: ESSENTIAL  
- REALISM constraints: ESSENTIAL  
- AVOID rules: ESSENTIAL  
- ATMOSPHERE STYLE furniture list: USEFUL but creates tension with photo-first philosophy

---

### SYSTEM 9 — Restyling WOW Directive (`wow_layer.py::build_restyling_wow_directive`)

**Location:** `prompt_engine/wow_layer.py`  
**Size:** ~326 chars (P4 — drops if budget tight)  
**Wave introduced:** Wave 4.5.1 (replaces `_WOW_DIRECTIVE` in FIRST_VISION path)

**Exact current text:**
```
TRANSFORMATION AMBITION — premium restyling of THIS exact apartment photo, not a new apartment. 
Visible architecture stays recognizable: windows, openings, partitions, existing equipment. 
WOW through: materials, finishes, lighting quality, furniture styling, atmosphere conviction. 
Decorate this photo — do not recompose it.
```

**Why introduced:**  
Wave 4.3.1 identified that FIRST_VISION prompts without transformation ambition produced flat, low-quality outputs. The WOW directive signals the quality target. Wave 4.5.1 changed the framing from "editorial redesign" to "premium restyling" to reduce recomposition.

**Redundancy:**  
- "THIS exact apartment photo, not a new apartment" — task says "SAME APARTMENT", contract says "DO NOT redesign architecture"
- "Visible architecture stays recognizable: windows, openings, partitions" — contract STRUCTURAL LOCK already forbids changing these
- "Decorate this photo — do not recompose it" — unique framing, not duplicated elsewhere

**Unique contribution:**  
"WOW through: materials, finishes, lighting quality, furniture styling, atmosphere conviction" — this is the only section that explicitly signals the QUALITY TARGET. Without it, the model knows what to preserve and what to change, but not how much ambition to apply to the transformation.

**P4 priority concern:**  
At P4, this section drops under budget pressure. It is the section that drives transformation quality — dropping it may produce technically correct but aesthetically flat outputs.

**Classification: USEFUL to ESSENTIAL (quality ambition signal); PARTIALLY REDUNDANT (preservation vocabulary)**

---

### SYSTEM 10 — Compact Realism Block (`realism_layer.py::build_compact_realism_block`)

**Location:** `prompt_engine/realism_layer.py`  
**Size:** ~133 chars (P3 — drops after P5 and P4)  
**Wave introduced:** Wave 4.2.x (compact variant)

**Exact current text:**
```
NOT a CGI render. DSLR real estate photograph quality. 
Real materials, natural light physics, no plastic surfaces, no render feeling.
```

**Why introduced:**  
Without explicit anti-CGI vocabulary, gpt-image-1 defaults toward a synthetic render aesthetic — plastic surfaces, artificial lighting, over-sharpened materials. These words directly map to model training vocabulary that triggers photographic realism.

**Does the problem still exist?**  
Yes. "NOT a CGI render. DSLR real estate photograph quality." are the two most cost-effective quality signals in the entire prompt. They are not redundant with any other section.

**Classification: ESSENTIAL**

---

### SYSTEM 11 — Interior Completeness Rule (`realism_layer.py::build_interior_completeness_rule`)

**Location:** `prompt_engine/realism_layer.py`  
**Size:** ~298 chars (P5 — drops first)  
**Wave introduced:** Wave 4.2.5

**Exact current text:**
```
INTERIOR COMPLETENESS: The space must feel fully designed and emotionally inhabited — 
never sparse, empty, under-furnished, or minimally staged. 
Every major functional zone should feel intentionally completed with layered furniture, 
lighting, decor, textile richness, and hospitality-grade styling.
```

**Why introduced:**  
Early PROD outputs were generating sparse, emptily-staged rooms. The model was correctly preserving architecture but not adding atmosphere and furnishing.

**Redundancy with DNA:**  
The DNA block for every registered atmosphere+room already specifies exact furniture, lighting, and decor. Soft Luxury living room: "deep curved bouclé sofa in ivory or blush; honed marble coffee table; barrel-back cashmere armchairs; oversized ceramic vessel; layered silk and bouclé cushions" — this is a richly furnished output specification.

**Tension with photo-first philosophy:**  
"Never sparse, empty, under-furnished" — if the uploaded room IS intentionally minimal (e.g., a sparsely furnished home), this instruction pushes toward over-furnishing it. It may conflict with preserving what's actually in the photo.

**Current survival rate:**  
With the Wave 4.5.0 simplified contract, interior_completeness survives for all atmospheres at standard source descriptions. It drops at P5 only when budget is very tight.

**Assessment:**  
For DNA paths (which cover 100% of registered atmospheres for common rooms), DNA already handles completeness. interior_completeness is a safety net for non-DNA paths and for model tendency toward sparse outputs. However, it may be counter-productive when the uploaded room is minimally furnished by intent.

**Classification: REDUNDANT on DNA paths; USEFUL on non-DNA fallback paths; POTENTIALLY HARMFUL for minimally furnished uploads**

---

### SYSTEM 12 — Budget / Priority Compression (`composer.py::_assemble_with_budget`)

**Location:** `prompt_engine/composer.py`  
**Size:** 0 chars (runtime logic)  
**Wave introduced:** Wave 4.2.4

**Exact logic:**  
```
Priority: P5 → P4 → P3 → P2 (never P1)
For each priority level: drop lowest-priority non-empty section until under budget
```

**Section priority table:**
| Section | Priority | Size (typical) |
|---------|----------|----------------|
| task | P1 | ~175 chars |
| full_contract | P1 | ~820 chars |
| source_space | P1 | ~214 chars |
| design_intel (DNA) | P2 | ~939 chars |
| compact_realism | P3 | ~133 chars |
| wow_directive | P4 | ~326 chars |
| interior_completeness | P5 | ~298 chars |
| visible_spaces | P5 | ~90-200 chars |
| design_direction | P5 | 0-300 chars |

**Budget:** 3550 chars (FIRST_VISION)

**Current headroom analysis (200-char source, SL living room):**
```
task:                ~175 chars
full_contract:       ~820 chars
source_space:        ~214 chars
design_intel:        ~939 chars
interior_completeness: ~298 chars
wow_directive:       ~326 chars
compact_realism:     ~133 chars
─────────────────────────────────
Total (all sections): ~2905 chars
Budget:               3550 chars
Headroom:             ~645 chars
```

**Assessment:**  
At 200-char source descriptions, all sections survive. Budget pressure begins when source descriptions exceed ~400-600 chars or when DNA is large AND source description is long.

**Classification: ESSENTIAL (prevents prompt budget overruns)**

---

### SYSTEM 13 — Retry System (`retry_classifier.py` + `max_retries=0`)

**Location:** `retry_classifier.py`, `main.py` retry loop  
**Size:** 0 prompt chars (runtime logic)

**Exact role:**  
- `max_retries=0`: disables OpenAI SDK's internal retry (prevents 3 × SDK retries × 3 max_attempts = 9 API calls)  
- `retry_classifier.py`: classifies exceptions as TRANSIENT / NON_TRANSIENT / UNKNOWN  
- Retry loop: up to 3 attempts (PROD), smart decision per failure

**Classification: ESSENTIAL**

---

### SYSTEM 14 — Anchor Detector (`anchor_detector.py`)

**Location:** `prompt_engine/anchor_detector.py`, used in STYLE_REFINEMENT only  
**Size:** 0-185 chars (added to SR contract when anchors detected)  
**Wave introduced:** Wave 4.3.0

**Used in FIRST_VISION?** No. Anchor detection fires only on STYLE_REFINEMENT (V2+).

**Exact role:**  
Deterministic regex scan of `room_description` for: glass partitions, multi-zone layouts, depth cues, special openings (floor-to-ceiling, bay windows, bi-fold doors), structural elements (columns, exposed beams, spiral stairs). If anchors found, injects: "ARCHITECTURAL ANCHORS — LOCKED: [list]. Preserve these unchanged."

**Why introduced:**  
V2+ atmosphere switches were collapsing multi-zone layouts (kitchen+living merged into single zone). The anchor clause forces explicit preservation of detected spatial features.

**Assessment:**  
Zero cost when no anchors detected (single-zone rooms). Highly targeted when anchors fire. The problem it solves (collapsing multi-zone layouts) is real and distinct from other preservation layers.

**Classification: USEFUL to ESSENTIAL for STYLE_REFINEMENT (V2+); NOT USED in FIRST_VISION**

---

### SYSTEM 15 — Build Scene Completion (`dream_scene_completion.py`)

**Location:** `prompt_engine/dream_scene_completion.py`  
**Size:** ~280-380 chars (P4 — non-DNA path only)  
**Wave introduced:** Wave 4.2.3

**Used in FIRST_VISION?** Only when no room DNA is registered (rare fallback).  
**When does this fire?** For atmospheres or room types without registered DNA.

**Exact text (living room, soft_luxury, fallback):**
```
COMPLETE THE SCENE: include sofa grouping, coffee table, area rug, floor or table lamps, 
curtains or blinds, TV wall or art focal point, decorative objects, plants. 
QUALITY: plush, premium, effortlessly elegant — every surface tactile and warm. 
Every zone inhabited, every surface considered. Premium and emotionally desirable — warm, lived-in, aspirational.
```

**Critical observation:**  
"COMPLETE THE SCENE: include sofa grouping, coffee table..." — this directly instructs the model to ADD specific furniture. This is the **most direct conflict** with the "Decorate this photo — do not recompose it" philosophy. However, it is only used on the fallback path (no registered DNA), which in practice means it fires when the atmosphere has no room-specific DNA registered. Since all 10 atmospheres × living room are registered, this fallback almost never fires for living rooms.

**Classification: POTENTIALLY HARMFUL on non-DNA fallback (instructs furniture addition); HISTORICAL (DNA eliminated the need for it on primary paths)**

---

### SYSTEM 16 — Generation Profiles (`generation_profiles.py`)

**Location:** `generation_profiles.py`  
**Wave introduced:** Wave 4.2.6

**Profiles:**
| Profile | quality | input_fidelity | size | max_attempts | compact_prompts |
|---------|---------|----------------|------|-------------|-----------------|
| DEV | low | low | 1024x1024 | 1 | True |
| PROD | high | high | auto | 3 | False |

**Classification: ESSENTIAL (cost protection in DEV; quality/resilience in PROD)**

---

### SYSTEM 17 — Frozen / Unused Systems

These exist in code but are NOT called in active paths:

| System | File | Preserved For | Should Remove? |
|--------|------|--------------|----------------|
| `build_structural_contract()` (Tier 1) | preservation.py | validator backward compat | Wave 4.6 |
| `_CAMERA_LOCK`, `_STRUCTURAL_LOCK`, `_TRANSFORMATION_SCOPE`, `_ATMOSPHERE_BOUNDARY` constants | preservation.py | validator backward compat | Wave 4.6 |
| `build_continuation_contract()` (Tier 3) | preservation.py | validator backward compat | Wave 4.6 |
| `build_realism_block()` (full, ~995 chars) | realism_layer.py | backward compat | Wave 4.6 |
| `build_medium_realism_block()` (~310 chars) | realism_layer.py | backward compat | Wave 4.6 |
| `build_first_vision_wow_directive()` | wow_layer.py | validator backward compat | Wave 4.6 |
| `_WOW_DIRECTIVE` constant | wow_layer.py | validator backward compat | Wave 4.6 |
| `build_dream_micro_layer()` | dream_scene_completion.py | STYLE_REFINEMENT DNA path | Currently active in SR |
| `build_dream_addendum()` | dream_scene_completion.py | STYLE_REFINEMENT non-DNA | Active in SR |

---

## 3. The Fundamental Tension

The current FIRST_VISION prompt contains two philosophically opposed signal types:

**Type A — Photo-preservation signals:**
- `input_fidelity=high` (strongest)
- Structural mask (pixel-level)
- "SAME APARTMENT" task framing
- CAMERA LOCK / STRUCTURAL LOCK (vocabulary)
- "Decorate this photo — do not recompose it" (WOW directive)

**Type B — Composition-override signals:**
- DNA `furniture_language` (specific pieces: "deep curved bouclé sofa in ivory or blush")
- `interior_completeness` ("never sparse, empty, under-furnished")
- `build_scene_completion` fallback ("COMPLETE THE SCENE: include sofa grouping, coffee table...")
- ROOM LOCK in contract ("preserve sofa zone" — assumes specific elements exist)

When Type A and Type B conflict, the model makes a judgment call. The more specific Type B signals are, the more the model may privilege them over the softer photo-preservation signals.

**The real design question:**
> Should atmosphere DNA specify **furniture pieces** (composition authority) or **material and lighting vocabulary** (restyling authority)?

A "Soft Luxury" living room can be expressed through:
- **Composition approach:** "place a bouclé sofa and marble coffee table"  
- **Restyling approach:** "reupholster existing seating in bouclé, surface the existing table in marble, warm the lighting to concealed cove"

The current system is between these — it says "ATMOSPHERE STYLE (restyle existing elements):" but then lists specific pieces. The ambiguity is the core tension.

---

## 4. FIRST_VISION Prompt: Complete Current Example

**Input:** Soft Luxury Gold, living room, 200-char source description, no secondary spaces

```
[TASK — P1, ~175 chars]
SAME APARTMENT — apply Soft Luxury Gold atmosphere. The photo defines spatial truth: 
reproduce this living room's geometry, camera, windows, openings, and depth exactly. 
Then transform all surfaces, materials, and light.

[CONTRACT — P1, ~820 chars]
CAMERA LOCK — FROZEN: camera position, focal length, vanishing points, horizon line. 
Room proportions, spatial depth, and all structural lines are fixed. Output must look 
like a photograph of the SAME apartment, preserving its architectural identity. 
DO NOT reinterpret geometry. DO NOT redesign architecture. STRUCTURAL LOCK — FORBIDDEN: 
windows (positions, frames, unblocked, natural light visible), doors, walls, ceiling 
height, floor plan, structural columns. CHANGE ONLY: surfaces, materials, furniture, 
lighting, textiles, colours, atmosphere. ATMOSPHERE BOUNDARY — geometry, openings, and 
topology override atmosphere. Atmosphere is applied last. Any perspective or geometry 
change is a failure. ROOM LOCK: preserve TV wall or fireplace position, sofa zone, 
all window orientations, open-floor-to-furnished ratio.

[SOURCE SPACE — P1, ~214 chars]
SOURCE SPACE: Living room with large west-facing windows, eye-level single-point perspective, 
medium spatial depth. No structural columns. Standard ceiling height. Visible kitchen 
through doorway. Oak hardwood floor.

[DNA — P2, ~939 chars]
ATMOSPHERE (Soft Luxury): Refined hospitality luxury emphasizing softness, elegance, 
tactile richness, and timeless sophistication. — Indulgent, serene, tactile, quietly 
opulent, feminine-refined, sensorially rich. [Rosewood / Aman / luxury suite]
ROOM (Living Room): fluted ivory plaster walls, honed cream marble floor, brushed 
champagne metal accents. LIGHT: Concealed perimeter cove + silk shade floor lamps; 
warm evening tone, no ceiling spotlights. ATMOSPHERE STYLE (restyle existing elements): 
deep curved bouclé sofa in ivory or blush; honed marble coffee table on brushed brass 
base; barrel-back cashmere armchairs; oversized ceramic vessel with dried pampas or 
lunaria; layered silk and bouclé cushions in cream and blush. REALISM: sofa sized to 
room — not oversized for space; marble floor with correct 3–5 mm grout lines. 
AVOID: no jewel-tone colour pops, no gold leaf or metallic wallpaper, no asymmetric 
art gallery wall, no visible TV above fireplace, Bling luxury, crystal chandelier clichés.

[INTERIOR COMPLETENESS — P5, ~298 chars]
INTERIOR COMPLETENESS: The space must feel fully designed and emotionally inhabited — 
never sparse, empty, under-furnished, or minimally staged. Every major functional zone 
should feel intentionally completed with layered furniture, lighting, decor, textile 
richness, and hospitality-grade styling.

[WOW DIRECTIVE — P4, ~326 chars]
TRANSFORMATION AMBITION — premium restyling of THIS exact apartment photo, not a new 
apartment. Visible architecture stays recognizable: windows, openings, partitions, 
existing equipment. WOW through: materials, finishes, lighting quality, furniture 
styling, atmosphere conviction. Decorate this photo — do not recompose it.

[COMPACT REALISM — P3, ~133 chars]
NOT a CGI render. DSLR real estate photograph quality. Real materials, natural light 
physics, no plastic surfaces, no render feeling.
```

**Total: ~2905 chars (budget: 3550, headroom: 645 chars)**

---

## 5. Redundancy Map

The following concepts appear multiple times in the prompt:

| Concept | Appearances | Locations |
|---------|-------------|-----------|
| SAME APARTMENT / same physical space | 4 | task, contract, WOW directive × 2 |
| Do NOT redesign / not a new apartment | 4 | task ("reproduce"), contract (DO NOT redesign), contract (geometry=failure), WOW (not a new apartment) |
| Windows/openings must be preserved | 3 | task ("openings"), contract (STRUCTURAL LOCK: windows), WOW (Visible architecture: windows, openings) |
| Transform surfaces/materials/light ONLY | 3 | task ("transform all surfaces"), contract (CHANGE ONLY:), DNA (ATMOSPHERE STYLE) |
| Camera is frozen | 2 | task ("camera"), contract (CAMERA LOCK) |

**Estimated redundant chars:** ~500-600 of the ~2905 total (~18%) repeat the same three concepts.

---

## 6. Summary Scores by System

| System | Chars | Essential | Drop Risk | Conflict |
|--------|-------|-----------|-----------|---------|
| input_fidelity=high | 0 | ★★★★★ | none | none |
| quality=high | 0 | ★★★★★ | none | none |
| Aspect ratio detection | 0 | ★★★★★ | none | none |
| Structural mask | 0 | ★★★★☆ | none | minor (cost) |
| Vision analysis | 0 | ★★★☆☆ | none | latency |
| Task framing | ~175 | ★★★★★ | never | partial dup |
| Tier 1.5 contract | ~820 | ★★★☆☆ | never | dups task |
| Atmosphere DNA (materials/lighting) | ~500 | ★★★★★ | P2 | none |
| Atmosphere DNA (furniture list) | ~280 | ★★★☆☆ | P2 | photo-first tension |
| Restyling WOW directive | ~326 | ★★★★☆ | P4 | partial dup |
| Compact realism | ~133 | ★★★★★ | P3 | none |
| Interior completeness | ~298 | ★★☆☆☆ | P5 | photo-first tension |
| Budget/priority system | 0 | ★★★★★ | none | none |
| Retry system | 0 | ★★★★★ | none | none |
