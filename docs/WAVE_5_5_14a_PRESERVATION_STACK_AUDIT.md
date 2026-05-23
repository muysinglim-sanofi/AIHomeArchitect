# Wave 5.5.14a — Preservation Stack Mini-Audit

**Date:** 2026-05-23
**Purpose:** Map every preservation layer currently shipping in the V1 FIRST_VISION prompt, categorize them (generic / per-room / per-atmosphere / per-photo), and identify what becomes redundant or contradictory once architectural bias is stripped from atmosphere DNA per the bimodal plan.
**Companion docs:** [WAVE_5_5_14a_DNA_AUDIT.md](WAVE_5_5_14a_DNA_AUDIT.md), [WAVE_5_5_14a_BIMODAL_CLASSIFICATION.md](WAVE_5_5_14a_BIMODAL_CLASSIFICATION.md).

---

## 0. TL;DR

The current preservation stack ships **5 distinct "atmosphere ≠ architecture" voices** (added across Waves 4.5/4.6/5.5.2/5.5.3/5.5.4) plus **4 architecture-defense voices** (CAMERA LOCK, STRUCTURAL LOCK, STRUCTURAL IDENTITY, OPENINGS ANCHOR).

Once the bimodal DNA strip removes architectural directives from atmospheres, **3 of the 5 "atmosphere ≠ architecture" voices become defensive prose against a threat that no longer exists**. They can be dropped from preservation mode without loss of preservation strength — they're only there to arbitrate DNA-vs-photo conflict, and the conflict source goes away.

The 4 architecture-defense voices remain load-bearing because they defend against **gpt-image-1's own internal bias** (the model "improves" architecture even when no DNA says to). These stay.

**Net effect in preservation mode:** ~770 chars freed per prompt (≈ 20% of current ~3500 char V1 prompt). Frees budget for visible-space block and per-room nuance currently dropped on tight atmospheres.

In **creative mode** (Surprise Me), the user's framing says: drop all preservation vocabulary. So the stack collapses to bare minimum (or zero).

---

## 1. Current preservation inventory (V1 FIRST_VISION prompt assembly)

Tonight's V2 log (21:06:14, Japandi Calm Living Room) ships these blocks in P1 order:

| # | Block | Source | Approx chars | What it says |
|---|---|---|---|---|
| 1 | `task` | [fidelity_layer.py:89](backend/prompt_engine/fidelity_layer.py#L89) — `build_first_vision_task` | ~250 | "SAME APARTMENT PHOTO-EDIT — apply {atm} as aesthetic overlay only. The photo defines geometry: preserve this {room}'s camera, windows, openings, depth exactly. Atmosphere = surfaces, materials, lighting, decor — never geometry." |
| 2 | `_SAME_APARTMENT_V2` | [preservation.py:237](backend/prompt_engine/preservation.py#L237) — `build_simplified_fv_contract` | ~693 | CAMERA LOCK + STRUCTURAL LOCK + CHANGE ONLY + ATMOSPHERE BOUNDARY (head) |
| 3 | `OPENINGS_ANCHOR` | [fidelity_layer.py:72](backend/prompt_engine/fidelity_layer.py#L72) | ~197 | "Bay windows and openings are photographed facts, not design decisions. Do not resize, narrow, simplify, or standardize any opening." |
| 4 | `STRUCTURAL IDENTITY` | [structural_identity.py:234](backend/prompt_engine/structural_identity.py#L234) — `render_clause` | up to 460 | Dynamic per-photo facts captured by mini at V1: dominant_opening, glass_partition, room_depth_type, kitchen_visibility |
| 5 | `STRUCTURAL NEGATIVE ANCHORS` | [structural_identity.py:282](backend/prompt_engine/structural_identity.py#L282) | up to 450 | "Photographed openings/glass are open space, NOT walls. Do not insert walls between them, compartmentalize the open facade, or close glass continuity." |
| 6 | `design_intel` | [atmosphere_dna/_base.py:205](backend/prompt_engine/atmosphere_dna/_base.py#L205) — `build_dna_block` | ~700-900 | ATMOSPHERE block + ROOM block (the DNA itself) |
| 7 | `_ATMOSPHERE_DNA_BOUNDARY` | [wow_layer.py:134](backend/prompt_engine/wow_layer.py#L134) | ~285 | "The DNA blocks above describe IDEAL materials, decor, lighting, and mood. They do NOT describe room scale, openings, ceilings, depth, or floor plan." (middle voice) |
| 8 | `_PHOTO_EDIT_WOW` | [wow_layer.py:90](backend/prompt_engine/wow_layer.py#L90) | ~195 | "TRANSFORMATION AMBITION — Visible architecture stays recognizable: windows, openings, partitions, existing equipment. WOW only through materials, lighting, atmosphere — NOT geometry." (tail voice) |
| 9 | `realism / enrichment` | [realism_layer.py](backend/prompt_engine/realism_layer.py) | ~130-300 | NATURAL ENRICHMENT + NOT a CGI render |

**Total:** ~3500 chars (matches tonight's `prompt_chars=3492-3532` log).

---

## 2. Categorization

### 🌐 GENERIC (atmosphere-independent, room-independent — same text every prompt)

| Block | Always emitted? |
|---|---|
| CAMERA LOCK | Yes (in `_SAME_APARTMENT_V2`) |
| STRUCTURAL LOCK | Yes (in `_SAME_APARTMENT_V2`) |
| CHANGE ONLY | Yes (in `_SAME_APARTMENT_V2`) |
| ATMOSPHERE BOUNDARY (head, voice #1) | Yes (in `_SAME_APARTMENT_V2`) |
| OPENINGS ANCHOR | Yes |
| Task-level boundary embed (head, voice #2, C2.b) | Yes (in `task` since Wave 5.5.2) |
| ATMOSPHERE DNA BOUNDARY (middle, voice #3, C3) | Yes (Wave 5.5.3) |
| TRANSFORMATION AMBITION + tail boundary (tail, voice #4, C1.b) | Yes |
| NATURAL ENRICHMENT | Yes |
| NOT a CGI render | Yes |

### 🏠 PER-ROOM (room-specific text)

| Block | Status |
|---|---|
| `_ROOM_STRUCTURAL` (ROOM LOCK per room: living, bedroom, kitchen, bathroom, etc.) | **DEAD since Wave 4.6.0** — removed from `_SAME_APARTMENT_V2`. Code still exists in [preservation.py:70](backend/prompt_engine/preservation.py#L70) but not called from FIRST_VISION path. |
| `task` room substitution | Variable only — same structure, just inserts `{room}` token. Not a separate rule. |

→ **Currently zero per-room preservation rules ship in V1 FIRST_VISION.** Wave 4.6.0 removed ROOM LOCK because the phrases assumed furniture features (TV wall, fireplace) not grounded in the actual photo. Result: V1 has no room-specific topology lock today.

### 🎨 PER-ATMOSPHERE (atmosphere-specific preservation)

| Block | Source | Status |
|---|---|---|
| `_ZEN_LIGHTING_DISCIPLINE` | [transformation_classifier.py](backend/prompt_engine/transformation_classifier.py) — per matrix Principle #6 | Atmosphere-specific addendum for Zen (reinforces lighting realism). Single-atmosphere only. |
| (none others) | — | No other per-atmosphere preservation rules ship. The DNA's `forbidden_elements` and `negative_rules` are atmosphere-specific decoration discipline, not preservation. |

→ **Currently ~1 per-atmosphere preservation addendum** (Zen lighting). Minimal scope.

### 📸 PER-PHOTO (dynamic, captured at V1, round-tripped)

| Block | Source |
|---|---|
| `STRUCTURAL IDENTITY` body (4 facts max) | `render_clause(identity)` — content varies per uploaded photo, captured by mini at V1, persisted via [SessionState](frontend/lib/data/models/session_state.dart) and re-injected on V2+. Wave 5.5.12 recovery rebuilds from original image if frontend token lost. |
| `STRUCTURAL NEGATIVE ANCHORS` emission gate | Only emits when STRUCTURAL IDENTITY is present (avoids zero-cost prompts on no-anchor photos). |

→ **Per-photo dynamic preservation = 4 architectural facts + 1 generic negative anchor section.** This is the heaviest single contributor to preservation: up to ~910 chars (460 identity + 450 negative anchors).

---

## 3. Redundancy that EXISTS TODAY (independent of bimodal plan)

Pre-existing audit `backend/docs/FULL_SYSTEM_AUDIT.md` already flagged some redundancies (predates Waves 5.5.2/3/4 boundary voices). Current rendered prompt has the following overlap:

### 3.1 "Atmosphere ≠ architecture" repeated 4× across the prompt

| Voice | Source | Phrasing |
|---|---|---|
| #1 (in `task`, C2.b head) | `build_first_vision_task` | "Atmosphere = surfaces, materials, lighting, decor — never geometry" |
| #2 (in `_SAME_APARTMENT_V2`) | `build_simplified_fv_contract` | "ATMOSPHERE BOUNDARY — geometry, openings, and topology override atmosphere. Atmosphere is applied last. Any perspective or geometry change is a failure." |
| #3 (middle, C3) | `build_atmosphere_dna_boundary` | "ATMOSPHERE DNA BOUNDARY — the DNA blocks above describe IDEAL materials, decor, lighting, and mood. They do NOT describe room scale, openings, ceilings, depth, or floor plan." |
| #4 (tail, C1.b) | `_PHOTO_EDIT_WOW` | "WOW only through materials, lighting, atmosphere — NOT geometry" |

All four say the same thing. The 4-voice stack was built incrementally (Wave 4.5 + 5.5.2 + 5.5.3) because each individual voice was insufficient on some atmosphere; the multi-voice pattern empirically worked.

**Today's measured outcome:** 100% "good or better" hit-rate. The 4 voices DO work. But cumulatively they cost ~480 chars saying the same boundary.

### 3.2 "Windows / openings must be preserved" repeated 4×

| Voice | Source |
|---|---|
| `task` | "preserve this {room}'s camera, windows, openings, depth exactly" |
| `_SAME_APARTMENT_V2` (STRUCTURAL LOCK) | "windows (positions, frames, unblocked, natural light visible), doors" |
| `OPENINGS ANCHOR` | "Bay windows and openings are photographed facts, not design decisions. Do not resize, narrow, simplify, or standardize any opening." |
| `_PHOTO_EDIT_WOW` | "Visible architecture stays recognizable: windows, openings, partitions, existing equipment" |

Three voices is established preservation pattern (matrix Principle #6 confirms multi-voice works). Four may be one too many.

### 3.3 "DO NOT redesign / reinterpret architecture" repeated 3×

| Voice | Source |
|---|---|
| `task` | "preserve this {room}'s... geometry... exactly" |
| `_SAME_APARTMENT_V2` (CAMERA LOCK) | "DO NOT reinterpret geometry. DO NOT redesign architecture." |
| `_PHOTO_EDIT_WOW` | "Visible architecture stays recognizable" |

---

## 4. NEW redundancy created by the bimodal DNA strip

This is the user's concern: **"once we remove architectural biases from atmospheres, do some preservation layers become useless?"**

Answer: **Yes — 3 of the 4 "atmosphere ≠ architecture" voices.**

The 4 voices exist because the DNA blocks contained phrases like:
- Tropical "Open-air" (philosophy)
- Bali "open-pavilion" (visible_transition_logic)
- Zen "emptied", "floor space dominant"
- Japandi "empty floor space is deliberate"

These contradicted the photo's actual architecture. The boundary voices were the counter-signal.

**If preservation mode strips those phrases from the DNA** (per the bimodal classification):
- Voice #1 (task C2.b "Atmosphere = surfaces, materials..."): can drop. The DNA is no longer claiming architectural authority.
- Voice #3 (middle C3 "The DNA blocks above describe IDEAL materials..."): can drop. There's no architectural language in the DNA to flag.
- Voice #4 (tail C1.b "WOW only through materials..."): can drop. The "WOW" target is already implicit in the (decoration-only) DNA.

**Voice #2 (ATMOSPHERE BOUNDARY in `_SAME_APARTMENT_V2`) stays** — it's part of the structural contract block that also carries CAMERA LOCK + STRUCTURAL LOCK + CHANGE ONLY. Keeping that block intact preserves the load-bearing vocabulary. The "ATMOSPHERE BOUNDARY" sentence within it is light (~120 chars) and serves as the single remaining boundary voice.

**Net char saving in preservation mode:**
- Drop task suffix "Atmosphere = surfaces, materials, lighting, decor — never geometry": ~75 chars
- Drop `_ATMOSPHERE_DNA_BOUNDARY` entirely: ~285 chars
- Drop tail half of `_PHOTO_EDIT_WOW` "WOW only through materials, lighting, atmosphere — NOT geometry": ~75 chars
- **Total: ~435 chars freed**

(Conservative — could save more if we also trim CAMERA LOCK's "DO NOT reinterpret geometry. DO NOT redesign architecture" given the task already says it.)

### What survives in preservation mode (load-bearing against MODEL bias, not DNA bias)

| Block | Why it stays |
|---|---|
| CAMERA LOCK | Defends against gpt-image-1's own perspective drift. Independent of DNA content. |
| STRUCTURAL LOCK | Lists categories (windows/doors/walls/ceiling/floor plan/columns). Model-level discipline. |
| CHANGE ONLY | Tells model the scope of allowed change. Independent of DNA. |
| OPENINGS ANCHOR | Defends against bay-window normalization. Model-level. |
| STRUCTURAL IDENTITY | Photo-specific facts. The most concrete signal. |
| STRUCTURAL NEGATIVE ANCHORS | "Openings are not walls." Photo-specific topology defense. |
| NATURAL ENRICHMENT | Quality signal, not preservation. Keep for output quality. |
| NOT a CGI render | Realism signal. Keep — most cost-effective in the stack. |

---

## 5. Contradictions identified

### 5.1 Hard contradiction (today, even without bimodal): ROOM LOCK is documented but disabled

`_ROOM_STRUCTURAL` in [preservation.py:70](backend/prompt_engine/preservation.py#L70) defines per-room locks for living room, bedroom, kitchen, bathroom, dining room, home office, facade, exterior, balcony, terrace. But Wave 4.6.0 removed the call site from FIRST_VISION's `_SAME_APARTMENT_V2`. So:
- The data is there
- The function `_room_note()` still works
- It's only called from Tier 1 (`build_structural_contract`) and Tier 2 (`build_structural_evolution_contract`) — both legacy paths
- Tier 1.5 (`build_simplified_fv_contract`, the actually-shipping path) doesn't call it

**Consequence:** Per-room preservation is **non-existent in V1 today**. If you wanted "kitchen workflow triangle preserved" or "bed wall alignment preserved" — none of those rules ship. This is also a candidate for cleanup (rename to `_unused_ROOM_STRUCTURAL` or delete), independent of the bimodal plan.

### 5.2 Soft contradiction: STRUCTURAL LOCK says "doors locked" but STRUCTURAL IDENTITY parser ignores doors

`_STRUCTURAL_LOCK` lists "doors" as forbidden to change. But [structural_identity.py:113](backend/prompt_engine/structural_identity.py#L113) `extract_from_description` only loops over window/opening keywords (bay window, panoramic window, floor-to-ceiling window, corner window, glazed wall, glazed facade, picture window). Per memory `mini_door_classification_resistance.md`, gpt-4o-mini also refuses to classify sliding doors as anything but "window". So:
- STRUCTURAL LOCK preserves doors in vocabulary
- STRUCTURAL IDENTITY never captures door-specific facts (mini bias + parser scope)

Doors are protected by generic STRUCTURAL LOCK but never given the concrete per-photo anchoring that windows get. This isn't a bimodal-related issue, just an existing gap.

### 5.3 Bimodal contradiction (after strip): "preserve openings" vs "open-pavilion architecture"

If preservation mode strips Bali's "open-pavilion" from `visible_transition_logic` AND keeps OPENINGS ANCHOR + STRUCTURAL LOCK, the result is **clean** — no contradiction. The DNA stops asking for architectural openness; the preservation stack continues protecting the photographed openings (whether they're large or small). This is the desired state.

But in **creative mode**, if Bali's "open-pavilion" is revived AND OPENINGS ANCHOR + STRUCTURAL LOCK remain active, the prompt would contradict itself: "create a pavilion volume" vs "preserve the photographed openings exactly". The user's framing resolves this: in creative mode, drop preservation vocabulary entirely. So no contradiction by construction.

---

## 6. Simplification possible after bimodal strip

### Preservation mode — proposed stack composition

```
1. task (trimmed)         — "SAME APARTMENT PHOTO-EDIT — apply {atm}. Preserve this {room}'s camera, windows, openings, depth exactly."
                            (~150 chars; drop the C2.b boundary tail "Atmosphere = surfaces…")
2. _SAME_APARTMENT_V2     — KEEP (CAMERA LOCK + STRUCTURAL LOCK + CHANGE ONLY + ATMOSPHERE BOUNDARY)
3. OPENINGS_ANCHOR        — KEEP
4. STRUCTURAL IDENTITY    — KEEP
5. STRUCTURAL NEG ANCHORS — KEEP
6. design_intel (stripped) — DECORATION-ONLY DNA per bimodal classification
   (DROP _ATMOSPHERE_DNA_BOUNDARY — no architectural DNA to arbitrate)
7. _PHOTO_EDIT_WOW (trimmed) — "TRANSFORMATION AMBITION — Visible architecture stays recognizable."
                              (~95 chars; drop the C1.b boundary tail)
8. NATURAL ENRICHMENT     — KEEP
9. NOT a CGI              — KEEP
```

**Estimated total:** ~2700-3000 chars (vs current ~3500). Budget headroom: ~500-800 chars.

### Creative mode — proposed stack composition

```
1. task (creative variant) — "SURPRISE ME — apply {atm} with creative architectural latitude. This is an exploratory redesign."
                              (~130 chars; no "preserve…exactly" language)
2. (no _SAME_APARTMENT_V2)
3. (no OPENINGS_ANCHOR)
4. STRUCTURAL IDENTITY    — OPTIONAL: keep for soft grounding, or drop entirely per user framing
5. (no STRUCTURAL NEG ANCHORS)
6. design_intel (FULL)    — Revived dead fields: architectural_language + room_specific_constraints + atmosphere_keywords
7. (no _ATMOSPHERE_DNA_BOUNDARY)
8. _PHOTO_EDIT_WOW (creative variant) — "Bold transformation. Atmosphere expressed at architectural level."
9. NATURAL ENRICHMENT     — KEEP (quality)
10. NOT a CGI             — KEEP (quality)
```

**Estimated total:** ~2200-2500 chars. Smaller because preservation stack is gone. The dead-field revival adds back ~400 chars but the boundary voices drop saves more.

---

## 7. What this audit does NOT recommend

To stay focused (anti-empilement):

1. ❌ **Don't rewrite CAMERA LOCK / STRUCTURAL LOCK.** They work. They defend against model-internal bias, not DNA conflict. Keep them byte-identical.
2. ❌ **Don't add new per-room preservation rules.** ROOM LOCK was tried and removed (Wave 4.6.0) because the assumed features (TV wall, sofa zone) weren't grounded in the actual photo. STRUCTURAL IDENTITY's photo-specific facts are the correct level of per-room precision.
3. ❌ **Don't add new per-atmosphere preservation rules.** Each atmosphere having its own preservation addendum would re-create exactly the conflict the bimodal plan resolves. Atmospheres own DECORATION; the preservation stack owns ARCHITECTURE.
4. ❌ **Don't merge STRUCTURAL IDENTITY into the generic CAMERA LOCK.** They serve different purposes: CAMERA LOCK is generic vocabulary discipline; STRUCTURAL IDENTITY is photo-specific concrete facts. Both load-bearing.
5. ❌ **Don't simplify NATURAL ENRICHMENT or NOT-a-CGI.** They're quality signals, not preservation. Keep as-is.

---

## 8. Concrete simplification list (preservation mode, ranked by safety)

| # | Change | Saving | Risk | Justification |
|---|---|---|---|---|
| 1 | Drop `_ATMOSPHERE_DNA_BOUNDARY` (Wave 5.5.3 C3 middle voice) | ~285 chars | LOW once DNA strip is in place. Without the strip = HIGH risk regression. | The whole section says "DNA describes ideals, not architecture". If DNA contains no architecture, the section is empty defensive prose. |
| 2 | Trim `_PHOTO_EDIT_WOW` tail "WOW only through materials, lighting, atmosphere — NOT geometry" | ~75 chars | LOW once DNA strip is in place. | Same logic — voice exists to counter architectural DNA. |
| 3 | Trim task suffix "Atmosphere = surfaces, materials, lighting, decor — never geometry" | ~75 chars | LOW once DNA strip is in place. | Same logic — voice #1 of the 4-voice arbitration. |
| 4 | Delete dead `_ROOM_STRUCTURAL` constants in [preservation.py:70](backend/prompt_engine/preservation.py#L70) | 0 char saving in prompt (already dead) | NONE | Code cleanup. Predates Wave 5.5.14a. |
| 5 | Trim `_SAME_APARTMENT_V2`'s "DO NOT reinterpret geometry. DO NOT redesign architecture." | ~70 chars | MEDIUM. The task already says "preserve geometry exactly" — but CAMERA LOCK is validator-checked vocabulary, breaking it requires regression review. | Vocabulary duplicate of task. |

**Combined #1+#2+#3 saving: ~435 chars in preservation mode.** Frees budget for visible_spaces (P5) and natural_enrichment (P4) that currently drop on Soft Luxury / Warm Modern with their longer DNA blocks (matrix Principle #6).

---

## 9. Implementation order recommendation

If the user proceeds with the bimodal redesign, the right order is:

1. **First** — implement the DNA architecture strip (per bimodal classification). This is what enables the simplifications below.
2. **Second** — drop simplifications #1, #2, #3 in preservation mode (the 3 redundant boundary voices). Keep them as no-op in creative mode anyway.
3. **Third** — implement the creative mode path (new composer routing, revive dead fields, drop preservation stack per user framing).
4. **Fourth** — measure: preservation-mode V1 quality must remain ≥ baseline (today's 100% benchmark). Creative-mode V1 quality on a new "Surprise Me" benchmark set.
5. **Fifth** — cleanup `_ROOM_STRUCTURAL` dead code (separate refactor PR, freeze exception).

**Do NOT** implement #2 before #1. Dropping boundary voices while DNA still carries architectural language = high regression risk (the matrix data shows phantom walls coming back).

---

## 10. Open questions for the user

1. **Voice #4 stays?** Voice #2 (the `ATMOSPHERE BOUNDARY` clause inside `_SAME_APARTMENT_V2`) stays in preservation mode. Confirm this is the right one to keep (vs. say, voice #4 in tail which is more recent and shorter).

2. **STRUCTURAL IDENTITY in creative mode?** Your framing says "drop preservation vocabulary in creative mode". STRUCTURAL IDENTITY is technically per-photo descriptive facts, not "preservation vocabulary" — but its presence does anchor the model to the photo. Option A: drop entirely in creative mode (full creative latitude). Option B: keep but reframe (e.g. "These architectural facts may be reinterpreted creatively"). I lean B for safety, but it's your call.

3. **Per-atmosphere preservation tunings (Zen lighting)?** `_ZEN_LIGHTING_DISCIPLINE` is the only existing per-atmosphere preservation addendum. Should it survive the bimodal split (kept in preservation mode for Zen) or migrate to the Zen DNA's decoration tokens?

4. **Trigger for creative mode?** Today Surprise Me = the recommender picks an atmosphere. Mapping that to "creative composer mode" needs a UX decision: ALL Surprise Me = creative, or offer "Surprise Me · Preserve" vs "Surprise Me · Bold"?

---

*End of preservation stack mini-audit. Cross-references: [WAVE_5_5_14a_DNA_AUDIT.md](WAVE_5_5_14a_DNA_AUDIT.md) (diagnostic), [WAVE_5_5_14a_BIMODAL_CLASSIFICATION.md](WAVE_5_5_14a_BIMODAL_CLASSIFICATION.md) (per-atmosphere arch/dec split), [backend/docs/FULL_SYSTEM_AUDIT.md](backend/docs/FULL_SYSTEM_AUDIT.md) (Wave 4.5 era audit — predates current stack). No code modified.*
