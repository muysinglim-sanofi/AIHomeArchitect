# Wave 5.5.17a — DNA Decoration Restoration Audit

**Date :** 2026-05-24
**Type :** read-only research audit (no code)
**Trigger :** Wave 5.5.16 furnishing wave failed to deliver visible decoration value despite shipping geometry-attached signals. Hypothesis : DNA furniture vocabulary stripped by Wave 4.6.0/4.6.1/4.7.1 R2 is the root cause — the model has no "what to render" to instantiate Wave 5.5.16's "where to attach" patterns.

## Executive Summary

**Major finding:** Two DNA fields with concrete furniture/room semantics — `room_specific_constraints` and `visible_transition_logic` — are **DEFINED in all 130 RoomAdaptationDNA entries but NEVER EMITTED in the prompt**. They are dead code, identical failure mode to the Wave 5.5.14a DNA Audit dead-field finding (which addressed `architectural_language` + `atmosphere_keywords` via bimodal creative revival, but missed these 2).

**Recommendation : Wave 5.5.18 — DNA Dormant Field Revival (Phase 1 of DNA Restoration)**. Re-emit these 2 dormant fields with safety wording. Estimated effort : 30 min code, ~150 char prompt impact, low risk. Combined with Wave 5.5.16 geometry-attachment (currently silenced on preserve), this restores furniture semantic without re-creating the Wave 4.2.5 INTERIOR_COMPLETENESS trap.

Secondary finding : `_ROOM_ELEMENTS` dict in `dream_scene_completion.py` (containing literal furniture lists like "sofa grouping, coffee table, area rug, floor or table lamps, curtains or blinds, TV wall or art focal point") exists as **dead code** — `build_scene_completion` no longer reads it. Resurrection on DNA path is more risky than option 1 but could be a Phase 2.

## 1. Catalog of Wave 4.6.0 → 4.7.1 R2 historical restrictions

### 1.1 Wave 4.6.0 (DNA stripping)

**Change** : `furniture_language` field in atmosphere DNA reformulated from named pieces to abstract material/texture descriptions.

**Before (pre-4.6.0)** : `"deep curved bouclé sofa in ivory"` — names the piece (sofa) + material (bouclé) + color (ivory).

**After (current)** : `"bouclé in oat or camel — warm curved tactile richness"` — material + tone + abstract texture quality. **NO mention of sofa/chair/coffee table/lamp anywhere in field.**

**Why shipped** : prevented model from REPLACING uploaded furniture pieces. "Photo-first" philosophy — restyle what's there, don't substitute.

**Side effect (today's diagnosis)** : the prompt no longer tells the model "this room typically has X furniture items". On under-furnished uploads (most user photos), the model has no signal to populate the room. → Fade outputs.

**Reversibility today** : risky. Restoring named pieces could re-trigger furniture substitution on rich uploads. But the existing fields `realism_constraints`, `room_specific_constraints`, and `decor_language` ALREADY contain named pieces ("sofa", "bed", "TV", "pendant", "console") — they just aren't all emitted.

### 1.2 Wave 4.6.0 (non-DNA path)

**Change** : `_style_block` function's "Furniture — <piece>, <piece>" segment removed (composer.py:374-403). Non-DNA fallback no longer emits furniture vocabulary.

**Why shipped** : same as 1.1 — composition authority caused furniture replacement on the non-DNA path.

**Side effect** : non-DNA path now ships pure material vocabulary, same problem as DNA path.

**Reversibility** : low priority — non-DNA path is fallback only. Most production traffic hits DNA path.

### 1.3 Wave 4.6.0 + 4.7.1 R2 (`_scene_completion` neutralization)

**Change** : `build_scene_completion(room_type, atmosphere_id)` in `dream_scene_completion.py` no longer reads `_ROOM_ELEMENTS` dict. Current implementation :
```python
def build_scene_completion(room_type, atmosphere_id):
    quality = _ATMOSPHERE_QUALITY.get(atmosphere_id, _DEFAULT_QUALITY)
    return f"QUALITY: {quality}. {_DREAM_FACTOR}"
```

The dict `_ROOM_ELEMENTS` still exists with literal furniture lists per room :
- living_room : `"sofa grouping, coffee table, area rug, floor or table lamps, curtains or blinds, TV wall or art focal point, decorative objects, plants"`
- bedroom : `"bed with layered linen and pillows, bedside tables with lamps, floor-length curtains, soft rug, art above headboard"`
- kitchen : `"countertop styling, pendant lights, quality tap fitting, integrated appliances, herbs or small plant"`
- bathroom : `"layered towels, bath mat, mirror with flanking light, plant or greenery, toiletries tastefully arranged"`
- dining_room : `"dining table set with placemats, chairs, chandelier or pendant directly above, sideboard or feature art wall"`
- home_office, balcony, terrace, exterior covered

**Note** : `_room_elements(room_type)` helper still exists, also unused.

**Why shipped** : composition-authoritative spatial-completion pressure ("include sofa grouping..." was read as imperative).

**Reversibility** : moderate-to-high risk. Resurrection without rewording = identical to Wave 4.2.5 trap. Resurrection with permissive wording ("a typical living room may show...") = could work but requires bench gate.

### 1.4 Wave 4.7.1 R2 (`_INTERIOR_COMPLETENESS_RULE` removal)

**Change** : `build_interior_completeness_rule()` constant kept in `realism_layer.py:90-95` but no longer called from composer FIRST_VISION path. Both DNA and non-DNA paths : `completeness = ""`.

**Toxic original wording** :
> "INTERIOR COMPLETENESS: The space must feel fully designed and emotionally inhabited — never sparse, empty, under-furnished, or minimally staged. Every major functional zone should feel intentionally completed with layered furniture, lighting, decor, textile richness, and hospitality-grade styling."

**Why shipped** : 3 toxic phrases triggered global composition solving → wall invention :
1. "must feel fully designed" → authority claim
2. "Every major functional zone" → zone enumeration
3. "hospitality-grade styling" → showroom target

**Reversibility** : **NEVER bring this back as-is**. The brand is poisoned by history. Any furniture/completeness signal must avoid these 3 phrase patterns (constraint from Wave 5.5.15a audit).

### 1.5 Wave 4.6.1 (PHOTO-EDIT framing)

**Change** : `build_first_vision_task` reframed from "reproduce... Then transform" → "PHOTO-EDIT — apply ... aesthetic overlay only". Plus `build_photo_edit_wow_directive` replaced `build_restyling_wow_directive` (removed "furniture styling" signal).

**Reversibility** : DO NOT touch. This is load-bearing preservation framing that contributed to Wave 5.5.4+5.5.6's preservation success (9/9 walls preserved). Reverting would lose the preservation gains.

## 2. What's actually emitted today — the prompt audit

### 2.1 DNA path — `build_dna_block` source code

```python
style_items = (dna.furniture_language[:3] + dna.decor_language[:2])
style = "; ".join(style_items)
real = "; ".join(dna.realism_constraints[:2])
room_avoid = dna.negative_rules[:3]
```

Emits :
- `ATMOSPHERE` line : philosophy + emotional_intent + luxury_level
- `ROOM` line : 3 material_palette + lighting_behavior + 3 furniture_language + 2 decor_language + 2 realism_constraints + 3 negative_rules

### 2.2 DNA fields NEVER emitted today

| Field | Sample content (warm_modern living_room) | Status |
|---|---|---|
| `room_specific_constraints` | `["seating in conversation grouping, not TV-facing row", "single clear focal wall — fireplace or artwork, not both"]` | **DEAD** |
| `visible_transition_logic` | `"oak floor and warm plaster continue into adjacent rooms; brass accents echo through visible kitchen or hallway"` | **DEAD** |

**`room_specific_constraints` contains explicit furniture/room semantics** : mentions TV, fireplace, focal wall, conversation grouping — all things the model SHOULD know about a living room.

**`visible_transition_logic` contains kitchen + hallway continuity** — directly relevant to the kitchen-suppression failure mode we observed in Wave 5.5.16 preserve bench.

### 2.3 DNA fields with hidden furniture vocabulary

`realism_constraints` typically contains named pieces. Examples :
- warm_modern living_room : `["sofa at residential scale — not model-set proportions", "furniture legs visible and grounded on floor"]`
- warm_modern master_bedroom : `["bed at correct height — not floating too high", "bedding draped naturally, not hotel-stiff"]`
- warm_modern kitchen : `["cabinet doors at correct residential height, not commercial scale", "island proportioned for kitchen footprint"]`

These ARE emitted (top 2). But they're framed as REALISM constraints ("at correct scale"), not as inclusions. The model parses them as "if there is a sofa, make it scale-correct" not "include a sofa".

### 2.4 `decor_language` IS emitted

Top 2 are emitted via `style_items`. Contains some pieces :
- warm_modern living_room : `["oversized ceramic vessel on floating oak shelf", "floor-length warm linen curtains"]`
- warm_modern master_bedroom : `["layered warm linen and boucle bedding", "single framed artwork centred above headboard"]`

These ARE emitted but are SECONDARY decor (vessel, curtains, art), not primary furniture (sofa, table, TV).

## 3. Safe relaxation options (ranked by risk/reward)

### Option A — Revive `room_specific_constraints` (LOW RISK, HIGH SIGNAL)

**Change** : Modify `build_dna_block` to append `room_specific_constraints[:2]` as a new section, e.g. labeled `CONTEXT:` or `ROOM SEMANTIC:`.

**Why low risk** :
- Field content is already worded as constraints (not mandates) : "seating in conversation grouping" / "no TV directly facing bed"
- Wording is naturally permissive ("X is preferred over Y" patterns)
- No "must / never / every" authority language
- Pre-existing in DNA, just dormant — not a new vocabulary

**Why high signal** :
- Concrete furniture nouns appear (TV, fireplace, focal wall, conversation seating)
- Per-room semantics ALREADY tuned by atmosphere DNA authors
- Same data revived for `architectural_language` (Wave 5.5.14d creative revival) without regression

**Estimated char impact** : +60-150 chars per prompt (room-dependent).

**Bench protocol** :
1. Enable for creative mode only first (lowest risk path)
2. 9 V1 creative cells × 3 atmospheres × 1 room (living_room)
3. Pass criteria : 0/9 wall invention + visible new furniture variety (TV, focal wall, conversation seating mentioned)
4. If pass : enable for preserve mode, bench separately
5. If pass on both : extend to 4 other room types

**Estimated effort** : 30 min code (one-line append in `build_dna_block`) + bench gate.

### Option B — Revive `visible_transition_logic` (LOW RISK, KITCHEN-SPECIFIC SIGNAL)

**Change** : Same pattern as Option A — append `visible_transition_logic` as a new emitted section in `build_dna_block`.

**Why** : This field SPECIFICALLY addresses adjacent-room continuity (kitchen visibility, hallway flow). Directly counters the Wave 5.5.16 kitchen-suppression failure we observed.

**Sample content** :
- warm_modern living_room : `"oak floor and warm plaster continue into adjacent rooms; brass accents echo through visible kitchen or hallway"`
- japandi_calm living_room (need to check) : similar continuity logic

**Estimated char impact** : +80-130 chars per prompt.

**Bench protocol** : Same as Option A. Specifically watch kitchen visibility continuity on Warm Modern / Japandi benches that previously showed kitchen suppression.

**Estimated effort** : 30 min code + bench gate. Can be combined with Option A in same wave.

### Option C — Resurrect `_ROOM_ELEMENTS` dict (MODERATE RISK, HIGH SIGNAL)

**Change** : Modify `build_scene_completion()` to emit `_ROOM_ELEMENTS` content with permissive wording. Wire into DNA path (currently only non-DNA path calls build_scene_completion).

**Sample emission for living_room** :
> "SCENE — a living room may include sofa grouping, coffee table, area rug, floor or table lamps, curtains or blinds, TV wall or art focal point, decorative objects, plants — where existing geometry naturally supports them."

**Why moderate risk** :
- Literal furniture enumeration ("sofa grouping, coffee table, area rug, floor or table lamps, curtains or blinds, TV wall...")
- "TV wall" especially risky — explicit wall keyword
- Even with "may include" softener, ~10 named pieces is large surface area

**Why high signal** :
- Most directly maps to the user's perceived deficit ("only sofa, no TV, no table")

**Estimated char impact** : +200-300 chars per prompt (largest impact).

**Bench protocol** :
1. Creative mode ONLY (do not ship preserve)
2. Living_room only Phase 1
3. Replace "TV wall or art focal point" with "TV/media presence" (no wall keyword) per Wave 5.5.16 lesson
4. 9 cells × 3 atmospheres pass criteria : 0/9 media walls invented + visible furniture variety

**Estimated effort** : 1h code (composer wiring + safety wording rewrite) + heavy bench.

### Option D — Loosen `furniture_language` field to re-include piece names (HIGH RISK)

**Change** : Edit each of the 130 RoomAdaptationDNA `furniture_language` lists to add piece names back. E.g. `"bouclé in oat or camel — warm curved tactile richness"` → `"bouclé sofa in oat or camel — warm curved tactile richness"`.

**Why high risk** :
- 130 DNA entries to edit — high blast radius
- Reverses the original Wave 4.6.0 intention without strong evidence it's safe today
- Risk of furniture REPLACEMENT (not just addition) on rich uploads
- Per-atmosphere tuning required (Bali sofa ≠ Warm Modern sofa)

**Why deferred to last** : not necessary if Option A + B already address the deficit via `room_specific_constraints` + `visible_transition_logic` which mention TV/seating/console naturally.

**Estimated effort** : 3-4h code (130 edits) + heavy bench × 10 atmospheres × 13 rooms. Don't start without evidence Options A+B+C are insufficient.

## 4. Recommendation : Wave 5.5.18 — DNA Dormant Field Revival

**Ship Option A + Option B combined** in a new Wave 5.5.18 :
- Edit `build_dna_block` in `_base.py` to emit `room_specific_constraints` and `visible_transition_logic` as new sections
- Bimodal-gated (BIMODAL_ENABLED=1) for safety rollback
- Phased rollout : creative only first → bench → preserve if passes
- Keep Wave 5.5.16 preserve silenced until Wave 5.5.18 bench data informs decision

**Skip Option C and D** unless A+B prove insufficient (bench would tell us in 1-2 sessions).

**Combined char impact** : +140-280 chars per prompt. Same envelope as Wave 5.5.16. P5 priority drops gracefully on tight atmospheres.

**Expected effect** :
- Concrete furniture nouns reappear in prompt (TV, sofa, seating, fireplace, focal wall, console, pendant) via `room_specific_constraints`
- Kitchen continuity reinforced via `visible_transition_logic` (addresses Wave 5.5.16 kitchen-suppression failure)
- Wave 5.5.16 geometry-attached signal becomes the SAFETY RAIL for these reactivated DNA fields (architecture preservation continues)

## 5. What NOT to do

Per Wave 5.5.15a audit constraint #1 (still binding) :
- ❌ NEVER restore `_INTERIOR_COMPLETENESS_RULE` (3 toxic phrases : "must feel fully designed" / "every major functional zone" / "hospitality-grade styling")
- ❌ NEVER add literal lists like "TV wall, media center, statement wall" — wall keywords trigger wall invention
- ❌ NEVER add "completeness" / "fully equipped" / "designer-staged" vocabulary

## 6. Bench protocol (gating Wave 5.5.18)

**Pre-bench baseline** : current state (Wave 5.5.16 with preserve silenced).

**Post-Wave 5.5.18 bench** (creative mode first) :
- 1 reference apartment × 3 atmospheres (Warm Modern + Japandi + Nordic) × 3 generations = 9 cells
- Pass criteria :
  1. Wall invention : 0/9 (must equal current creative baseline)
  2. Furniture variety : ≥2/9 cells show new furniture beyond sofa (TV, coffee table, lamps, console, etc.)
  3. Kitchen visibility : where applicable, kitchen behind partition stays as kitchen (not converted to seating zone)
- If pass : extend to preserve mode + 4 other rooms (bedroom, kitchen, bathroom, dining_room)
- If fail : rollback Wave 5.5.18, restart audit with deeper diagnosis

## 7. Rollback

Same pattern as Wave 5.5.14/15/16 family :
1. `unset BIMODAL_ENABLED` reverts everything
2. Set `_FURNISHING_PRESERVE_BY_ROOM = {}` (already done) keeps current safe state
3. Revert the `build_dna_block` edit removes Wave 5.5.18 contribution

## 8. Linked

- [docs/WAVE_5_5_15a_ROOM_COMPLETENESS_ARCHITECTURE_SAFETY_AUDIT.md](WAVE_5_5_15a_ROOM_COMPLETENESS_ARCHITECTURE_SAFETY_AUDIT.md) — historical INTERIOR_COMPLETENESS trap analysis (binding constraints)
- [memory/wave_5_5_14a_dna_audit.md](../C:/Users/muysi/.claude/projects/c--Projects-AIHomeArchitect/memory/wave_5_5_14a_dna_audit.md) — original dead-field finding (covered architectural_language + atmosphere_keywords; this audit completes it with room_specific_constraints + visible_transition_logic)
- [memory/wave_5_5a_calibration_matrix.md](../C:/Users/muysi/.claude/projects/c--Projects-AIHomeArchitect/memory/wave_5_5a_calibration_matrix.md) — atmosphere borrowing rules (matters if Option D considered)
- [docs/WAVE_5_5_15_ROADMAP.md](WAVE_5_5_15_ROADMAP.md) — current wave roadmap (will be superseded if Wave 5.5.18 ships first)
