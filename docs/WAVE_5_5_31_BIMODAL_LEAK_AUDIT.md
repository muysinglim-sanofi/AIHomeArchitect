# Wave 5.5.31 — Bimodal Architecture Leak Audit

**Date :** 2026-05-25
**Type :** read-only audit (no code)
**Trigger :** User clarification 2026-05-25 — the intended philosophy has ALWAYS been bimodal-by-design : preserve = lock architecture / allow furnishing ; creative = allow architectural reinterpretation. Wave 5.5.30 audit misframed the problem ("WM canonical overlays" globally) when the real issue is **architectural content leaking from atmosphere DNAs into preserve mode** when it should only emit in creative mode.

**Strategic correction (from user) :**

> PRESERVE ≠ "do not add furnishing"
> PRESERVE = DO NOT alter the apartment architecture
>
> In preserve mode :
>   LOCKED : walls, windows, doors, openings, perspective, circulation, proportions, room volume, structural geometry, architectural layout
>   ALLOWED : TV, rugs, lighting, mirrors, buffet, bookshelf, plants, curtains, decoration, furnishing enrichment, inhabitation realism
>
> So : architecture-risk vocabulary should be REMOVED from preserve mode prompts.
> Furnishing semantics SHOULD SURVIVE in preserve mode.
>
> The current issue : some atmospheres LEAK architectural semantics into preserve mode.

**Scope :** Map all DNA emission paths, identify per-atmosphere leaks, propose fix mechanisms.

---

## 1. Executive summary

**3 key findings :**

1. **Wave 5.5.18 `build_dna_room_context_signal` BYPASSES `apply_bimodal` strips.** When extended to preserve mode (user-locked), it emits `room_specific_constraints` + `visible_transition_logic` RAW. These fields carry architectural directives ("open side to garden", "pavilion character", "continue into adjacent pavilion") for several atmospheres.

2. **Per-atmosphere leak severity :**
   - **CRITICAL : Bali Sanctuary** — pavilion identity + open side + pavilion continuity + pool area assumption emitted RAW in preserve. Empirical evidence : Wave 5.5.25 KO (full perspective change).
   - **MEDIUM : Tropical Escape** — softened "open side" wording + plant-focal mandate + "into terrace" continuity. Wave 5.5.25 fix was partial (preserve still emits "open side" conditional + terrace continuity).
   - **LOW-MEDIUM : Nature Retreat** — "single statement stone or timber wall" mandate.
   - **LOW : Soft Luxury** — symmetry mandate (Wave 5.5.25 rolled back ; load-bearing per empirical evidence).
   - **MINOR : Desert Luxe** — "desert architecture" in philosophy. Nordic Warmth — "human-scaled" in emotional_intent.
   - **NONE : Warm Modern, Dark Contemporary** — already clean (Reference Profile).
   - **OPT-OUT (identity) : Japandi Calm, Zen Retreat** — density caps + anti-decor are atmosphere identity, not leaks.

3. **2 viable fix mechanisms** :
   - **Option A (minimal)** : Extend `apply_bimodal` strips to operate on `build_dna_room_context_signal` output too. Per-atmosphere strip tables augmented with new architectural phrases.
   - **Option D (clean)** : Move architectural content OUT of `room_specific_constraints` INTO `architectural_language` (creative-only via inject_creative_revival). `room_specific_constraints` becomes preserve-safe by design.

**Recommended : Option A first** (quick + low risk) → if stable, evaluate Option D as longer-term cleanup.

---

## 2. Methodology

### 2.1 Emission paths mapped

| Path | Function | Mode behavior | Strip mechanism |
|---|---|---|---|
| **P1** | `build_dna_block(dna)` | Both modes | `apply_bimodal()` strips per atmosphere (preserve only) |
| **P2** | `build_dna_room_context_signal(dna, mode)` (Wave 5.5.18, extended to preserve) | preserve + creative | **NONE — RAW emission** |
| **P3** | `inject_creative_revival(text, atm, room, mode)` | creative only | N/A (creative permits architectural) |
| **P4** | `build_secondary_space_block(dna)` | Both modes (when secondary visible spaces) | **NONE — RAW emission** |
| **P5** | `geometry_attached_furnishing.build_furnishing_signal()` (Wave 5.5.16/19) | both modes (creative content + preserve silenced) | N/A (signal content is itself preserve-safe) |
| **P6** | `emotional_realism.build_emotional_realism_signal()` (Wave 5.5.15c) | creative only (preserve silenced) | N/A |

### 2.2 What `build_dna_block` (P1) emits per (atm, room)

Composed of :
- `core.philosophy` + `core.emotional_intent` + `core.luxury_level`
- `dna.material_palette[:3]`
- `dna.lighting_behavior`
- `dna.furniture_language[:3]` + `dna.decor_language[:2]` (as "ATMOSPHERE STYLE")
- `dna.realism_constraints[:2]`
- `dna.negative_rules[:3]` + `core.forbidden_elements[:2]` (as "AVOID")

**`apply_bimodal` strips** per atmosphere phrases listed in `_STRIPS` dict (`bimodal_classifier.py`). Operates on the rendered string output of `build_dna_block`. **Idempotent string replacement.**

### 2.3 What `build_dna_room_context_signal` (P2) emits per (atm, room)

Composed of :
- `dna.room_specific_constraints[:2]` (as "ROOM CONTEXT")
- `dna.visible_transition_logic` (as "VISIBLE CONTINUITY")

**No strip applied.** Raw emission both modes.

### 2.4 What `build_secondary_space_block` (P4) emits per secondary visible room

Composed of :
- `dna.material_palette[:2]` + `dna.visible_transition_logic`

**No strip applied.** Raw emission both modes.

---

## 3. Per-atmosphere leak audit

Below : full preserve-mode content emitted per atmosphere (living_room), with leak markers.

### 3.1 Warm Modern — REFERENCE PROFILE

**P1 (build_dna_block) post apply_bimodal :**
- philosophy + emotional_intent : style only ✓
- material_palette : "European oak floor, warm sand plaster walls, travertine slab surfaces" — style ✓
- furniture_language : material/texture ✓
- decor_language : "floor-length warm linen curtains; soft wool rug in oat or camel within the seating footprint" — geometry-anchored ✓
- realism_constraints : "sofa at residential scale; furniture legs visible and grounded on floor" — scale-grounding ✓
- negative_rules : style only ✓

**P2 (dna_room_context) raw :**
- room_specific_constraints : "seating in conversation grouping; single clear focal wall — fireplace, artwork, or a television" — structural ✓
- visible_transition_logic : "oak floor and warm plaster continue into adjacent rooms; brass accents echo through visible kitchen or hallway" — continuity ✓

**Architectural leaks : NONE.** ✓ REFERENCE.

### 3.2 Soft Luxury

**P1 :** all style (palette, marble, brass) ✓
**P2 :**
- ✓ "seating centred on focal element — fireplace, art wall, or a television" — structural
- ⚠️ **"symmetry in furniture placement — not haphazard"** — composition mandate (load-bearing per Wave 5.5.25 rollback)
- ✓ visible_transition_logic continuity

**Architectural leaks : 1 (symmetry mandate)**
**Action : softer not drop** — Wave 5.5.25 rollback proved dropping creates wall invention. Anchor to "where the photographed apartment allows".

### 3.3 Dark Contemporary

**P1 :** all style/sculptural in emotional_intent (already stripped) ✓
**P2 :**
- ✓ "artwork or a television as single focal wall — not gallery cluster" — structural (post Wave 5.5.22)
- ✓ "balanced dark-to-warm lighting ratio — not pure darkness" — lighting style
- ✓ visible_transition_logic continuity

**Architectural leaks : NONE.** ✓ Already WM-aligned.

### 3.4 Nordic Warmth

**P1 :**
- emotional_intent : "Cozy, hygge, warm, intimate, **human-scaled**, reassuring, softly joyful" — "human-scaled" is mild spatial cue (commented as borderline in apply_bimodal strip table, currently NOT stripped)
- otherwise style ✓
**P2 :**
- ✓ "layered rugs permitted — wool flatweave under pile"
- ✓ "fireplace, wood stove, or a television as focal point if present" — structural ✓
- ✓ visible_transition_logic continuity

**Architectural leaks : MINOR (human-scaled in emotional_intent)**
**Action : optional — add to apply_bimodal strip table or leave (borderline)**

### 3.5 Nature Retreat

**P1 :**
- material_palette : "rough-cut stone accent wall" — implicit wall-material mandate
- realism_constraints : "stone wall texture visible — not flat CGI" — texture mandate
- negative_rules : "no plant collection overload" — density anti (not architectural)
**P2 :**
- ⚠️ **"single statement stone or timber wall — not all four walls"** — WALL-MATERIAL MANDATE (architectural directive)
- ⚠️ "planting: maximum 2 large statement plants" — density cap (not architectural)
- ✓ visible_transition_logic continuity

**Architectural leaks : 1 (statement wall mandate)**
**Action : strip "single statement stone or timber wall — not all four walls" in preserve via apply_bimodal extension**

### 3.6 Desert Luxe

**P1 :**
- philosophy : "Middle Eastern contemporary luxury inspired by **desert architecture** and sculptural calm" — "desert architecture" is mild leak (sculptural already stripped)
- otherwise material/style ✓
**P2 :**
- ✓ "no pattern on walls — tadelakt is the texture" — wall texture, OK
- ✓ "maximum 2 decorative objects in room" — density cap (not architectural)
- ✓ visible_transition_logic continuity

**Architectural leaks : MINOR ("desert architecture" in philosophy)**
**Action : optional — strip "desert architecture" → "desert sensibility" or similar**

### 3.7 Tropical Escape

**P1 :**
- material_palette : "louvred timber panels or shutters" — material OK
- furniture_language : "louvred timber" — material OK
- negative_rules : "no enclosed dining room feel" stripped for dining ; living negative_rules style OK
**P2 :**
- ⚠️ "where the photographed apartment shows an open side to terrace or garden, preserve and emphasize that opening" — Wave 5.5.25 ✓ softened **STILL contains "open side"** as architectural concept
- ⚠️ **"plant as living room's primary accent — one large specimen"** — FOCAL MANDATE (architectural in spirit)
- ⚠️ visible_transition_logic : "white walls and concrete floor continue **into terrace**" — assumes terrace exists (apply_bimodal does NOT operate on dna_room_context output)

**Architectural leaks : 2-3 (softened "open side" still architectural, plant-focal mandate, terrace continuity assumption)**
**Action :**
- Wave 5.5.25 fix kept ✓ for now (Tropical bench passed it)
- Strip "plant as primary accent" mandate via apply_bimodal extension OR move to architectural_language (creative-only)
- Visible_transition_logic preserve : strip "into terrace" / replace with neutral "into adjacent space"

### 3.8 Bali Sanctuary — CRITICAL LEAK

**P1 :**
- philosophy + emotional_intent : style ✓
- material_palette : "volcanic grey stone or polished terrazzo floor, reclaimed teak joinery, handwoven cotton or linen upholstery" — "ceiling structure" already stripped ✓
- furniture_language : "open-air or semi-open wet room in volcanic stone" stripped for bathroom ✓

**P2 (dna_room_context — RAW, NOT stripped) :**
- 🚨 **"open side to garden or pool — pavilion character"** — Wave 5.5.25 rolled back, FULL architectural directive
- ⚠️ "maximum 2 decorative objects plus one plant" — density cap
- 🚨 visible_transition_logic : **"volcanic stone floor and teak ceiling continue into adjacent pavilion; stone palette echoes through visible pool area"** — apply_bimodal HAS strip for "continue into adjacent pavilion" → "continue into adjacent space" + "open living pavilion" → "open living space", but **these strips ONLY operate on build_dna_block output, NOT on dna_room_context output**

**Architectural leaks : MAJOR (4 distinct leaks)**

**Evidence :** Wave 5.5.25 KO (full perspective change). This is **THE smoking gun** — `room_specific_constraints` raw emission of "pavilion character" + `visible_transition_logic` raw emission of "adjacent pavilion" + "visible pool area" combine to fully reframe the scene. Bali Wave 5.5.25 rollback restored the architectural mandate but the leak vector (Wave 5.5.18 raw emission) was never addressed.

**Action :**
- HIGHEST PRIORITY fix
- Strip "open side to garden or pool — pavilion character" in preserve via apply_bimodal extension OR move to architectural_language
- Strip "continue into adjacent pavilion" + "visible pool area" in dna_room_context preserve emission (apply existing apply_bimodal strips to P2 output)
- Density cap "max 2 + plant" : LOW priority, atmosphere identity

### 3.9 Japandi Calm — OPT-OUT (audited for completeness)

**P1 :** philosophy/emotional_intent + materials = identity (spareness)
**P2 :**
- "maximum 3 decorative objects in room" — density (identity, not architectural)
- "solid neutral rug or no rug — no pattern" — conditional rug (identity)
- visible_transition_logic continuity OK

**Architectural leaks : NONE (identity-defining density isn't an architectural leak per se).**

### 3.10 Zen Retreat — OPT-OUT (audited for completeness)

**P1 :** anti-decor + anti-furniture (Zen identity)
**P2 :**
- "maximum 2 furniture pieces in room" + "zero wall decoration" — identity
- visible_transition_logic OK

**Architectural leaks : NONE (Zen identity).**

---

## 4. Leak summary table

| Atm | Leak severity | Sources | Fix priority |
|---|---|---|---|
| **Bali Sanctuary** | **CRITICAL** | room_specific_constraints "pavilion" + visible_transition_logic "pavilion/pool" + apply_bimodal strips bypass | **#1 fix priority** |
| **Tropical Escape** | MEDIUM | room_specific_constraints "open side" + "plant-focal" + visible_transition "into terrace" | #2 |
| **Nature Retreat** | LOW-MEDIUM | room_specific_constraints "single statement stone or timber wall" | #3 |
| **Soft Luxury** | LOW | room_specific_constraints "symmetry" (load-bearing per Wave 5.5.25 — careful fix) | #4 |
| **Desert Luxe** | MINOR | core.philosophy "desert architecture" | #5 |
| **Nordic Warmth** | MINOR | core.emotional_intent "human-scaled" | #6 |
| Warm Modern | NONE | — | reference |
| Dark Contemporary | NONE | — | reference (post Wave 5.5.22) |
| Japandi Calm | n/a (opt-out) | density+identity | leave |
| Zen Retreat | n/a (opt-out) | anti-decor+identity | leave |

---

## 5. Fix mechanism options

### Option A — Extend `apply_bimodal` to operate on `build_dna_room_context_signal` output

**Mechanism :**
- Modify `build_dna_room_context_signal()` to call `apply_bimodal()` on its output when `mode == "preserve"`
- Extend per-atmosphere strip tables in `_STRIPS` to include the new architectural phrases from `room_specific_constraints` + `visible_transition_logic`

**Pros :**
- Minimal code change (1 line in `build_dna_room_context_signal` + per-atm strip additions)
- Reuses existing infrastructure
- Idempotent string replacement (safe)
- Preserves atmosphere identity in creative mode (architectural content survives via inject_creative_revival)

**Cons :**
- String-replacement-based : depends on exact phrase matches (brittle if DNA wording changes)
- Per-atmosphere strip table grows : 6-8 new entries
- Some leaks (like "plant as primary accent" Tropical) require careful phrasing of replacement

**Estimated effort :** ~30 min code + ~15 min validation + bench.

### Option B — DNA field metadata

**Mechanism :**
- Add per-field metadata flag : `preserve_safe : bool` per item in `room_specific_constraints`
- build_dna_room_context filters items based on mode + flag

**Pros :**
- More structural, less brittle than string replacement
- Per-field control

**Cons :**
- Requires DNA model change (RoomAdaptationDNA field schema)
- More invasive across all DNAs
- New abstraction to maintain

**Estimated effort :** ~3-4h code + DNA refactor.

### Option C — Two DNA fields per (room, mode)

**Mechanism :**
- Split `room_specific_constraints` → `room_specific_constraints_preserve` + `room_specific_constraints_creative`
- Each emits only in its mode

**Pros :**
- Clean separation
- No string-replacement brittleness

**Cons :**
- 130 cells × duplicate fields = doubled DNA volume
- Schema change
- Maintenance burden

**Estimated effort :** ~6-8h (full DNA migration).

### Option D — Move architectural content OUT of `room_specific_constraints` INTO `architectural_language`

**Mechanism :**
- Per-atmosphere DNA edit : take architectural items from `room_specific_constraints` ("open side to garden — pavilion character") and move into `core.architectural_language`
- `architectural_language` is creative-only (via `inject_creative_revival`) — naturally bimodal-safe
- `room_specific_constraints` becomes furnishing-only

**Pros :**
- Cleanest semantic fit (architectural directives belong in `architectural_language`)
- No new mechanism — uses existing bimodal infrastructure
- DNA structure becomes self-documenting (architectural content lives where it belongs)

**Cons :**
- Per-atmosphere DNA edits required
- `core.architectural_language` is per-atmosphere (not per-room) — room-specific architectural directives need a different home
- Some content may need to stay in `room_specific_constraints` if not strictly architectural

**Estimated effort :** ~2-3h (per-atmosphere edits) + bench.

### Recommended : Option A (quick fix) + Option D (longer-term cleanup)

**Phased approach :**

1. **Wave 5.5.32 — Option A : Extend apply_bimodal to P2** (this fixes the immediate Bali + Tropical + Nature Retreat leaks, minimal risk)
2. **After Wave 5.5.32 bench validates** : decide on Option D as long-term cleanup (move architectural to architectural_language field)
3. Option B / C deferred unless A+D prove insufficient

---

## 6. Strip table extensions needed for Option A

For each atmosphere, additional strips to add to `_STRIPS[atmosphere_id]` (applied to dna_room_context output) :

### Bali Sanctuary — additions

```python
# room_specific_constraints living
("open side to garden or pool — pavilion character", "respect the photographed layout"),
# visible_transition_logic living (already partial via existing strips, need new entries for dna_room_context output context)
# Existing "continue into adjacent pavilion" → "continue into adjacent space" already covers if applied to P2 output
# Need to add:
("through visible pool area", "through adjacent spaces"),
# bathroom — already in current strips ("open-air or semi-open wet room" stripped)
# room_specific_constraints bathroom
("open or semi-open shower — no full enclosure in pavilion bathroom", "respect the photographed bathroom layout"),
```

### Tropical Escape — additions

```python
# room_specific_constraints living
("plant as living room's primary accent — one large specimen", "tropical greenery enriches the room"),
# visible_transition_logic living
("continue into terrace", "continue into adjacent spaces"),
# room_specific_constraints already addresses "open side" via Wave 5.5.25 softening — softened wording is in DNA, no further strip needed
```

### Nature Retreat — additions

```python
# room_specific_constraints living
("single statement stone or timber wall — not all four walls", "respect the photographed wall materials"),
```

### Soft Luxury — special case

Symmetry mandate is LOAD-BEARING per Wave 5.5.25 empirical evidence. Cannot just strip.
**Recommended :** anchor it via DNA edit (not strip) :
```python
# Replace in soft_luxury.py DNA directly (not via apply_bimodal):
# OLD : "symmetry in furniture placement — not haphazard"
# NEW : "considered furniture placement that respects the photographed layout, with symmetry where the apartment naturally allows it"
```

### Desert Luxe — optional minor

```python
# core.philosophy
("desert architecture", "desert sensibility"),
```

### Nordic Warmth — optional minor

```python
# core.emotional_intent
(", human-scaled", ""),
("human-scaled, ", ""),
```

---

## 7. Implementation mechanism for Option A — code change

Single-line addition to `build_dna_room_context_signal` in `_base.py` :

```python
def build_dna_room_context_signal(dna, generation_mode):
    if not is_bimodal_enabled(): return ""
    if generation_mode not in ("preserve", "creative"): return ""
    if dna is None: return ""
    text = build_dna_room_context(dna)
    # Wave 5.5.32 — apply bimodal strip on preserve mode (was bypassed pre-fix)
    if generation_mode == "preserve":
        from .bimodal_classifier import apply_bimodal
        text = apply_bimodal(text, dna.atmosphere_id, generation_mode)
    return text
```

This single addition routes the dna_room_context output through the existing strip mechanism for preserve mode. Combined with per-atmosphere strip table additions (Section 6), eliminates the architectural leaks.

**Same fix needed for `build_secondary_space_block`** (P4 emission path) :
```python
def build_secondary_space_block(dna):
    # ... existing emission ...
    text = f"VISIBLE {room_name}: {mat_hint}; {dna.visible_transition_logic}."
    # Wave 5.5.32 — strip in preserve mode
    # NOTE: build_secondary_space_block doesn't currently receive mode arg
    # Refactor: add mode parameter, plumb through callers
    return text
```

P4 fix requires plumbing `mode` argument through callers (composer.py + composer_v2.py). Slightly more invasive than P2 fix.

---

## 8. Recommended implementation order (after this audit)

### Wave 5.5.32 — Apply bimodal strip to dna_room_context (P2 path)

- Code : ~10-line change in `_base.py` `build_dna_room_context_signal`
- Data : ~6-8 per-atmosphere strip entries added to `_STRIPS` dict
- Soft Luxury : DNA edit (not strip) for symmetry anchoring
- Bench tier : Standard preserve (3 atms × 3 cells × preserve)
- **Atmospheres priority order :** Bali (CRITICAL) → Tropical (MEDIUM) → Nature Retreat (LOW-MEDIUM) → Soft Luxury (special — DNA edit, not strip)
- Discipline : ANY preserve regression = immediate rollback

### Wave 5.5.33 — Plumb mode through `build_secondary_space_block` (P4 path)

- Code : Add `mode` parameter to `build_secondary_space_block` + apply bimodal strip in preserve
- Update composer.py + composer_v2.py callers to pass mode
- Bench tier : Smoke preserve with secondary spaces enabled

### Wave 5.5.34 (optional, longer-term) — Option D : Move architectural content to architectural_language

- Per-atmosphere DNA refactor (Bali + Tropical + Nature + Soft Luxury where applicable)
- Architectural content lives in `architectural_language` (creative-only)
- `room_specific_constraints` becomes furnishing-only
- No new mechanism needed (uses existing bimodal infrastructure)
- Bench tier : Standard creative + smoke preserve

### Out of scope

- Japandi/Zen DNA changes (opt-out, identity)
- Warm Modern / Dark Contemporary changes (no leaks)
- Decor/furnishing wave-style additions (not part of leak fix)

---

## 9. Strategic correction to Wave 5.5.30 audit

**Wave 5.5.30 deliverables that are now superseded :**

- ❌ Deliverable 10 "WM-derived atmospheres architecture" (overlays globally) → REPLACED by bimodal leak fix (Wave 5.5.32+) per user-corrected philosophy
- ❌ Migration sequence Wave 5.5.31-37 (atmosphere-by-atmosphere "alignment to WM rules") → REPLACED by leak-fix-first then optional further alignment

**Wave 5.5.30 deliverables that REMAIN valid :**

- ✓ The 10 canonical rules — still useful as preserve-safety checklist
- ✓ Empirical observation that WM is the reference
- ✓ Per-atmosphere risk ranking (used in this audit)
- ✓ Japandi/Zen opt-out
- ✓ The diagnosis of `architectural_language` as the #1 dangerous field — but in CREATIVE mode (the user-clarified philosophy) this is INTENDED behavior, not a bug

**New corrected philosophy lock :**

```
preserve = architecture LOCK + furnishing ALLOW
creative = architecture LATITUDE + furnishing ALLOW (full identity expression)

bimodal infrastructure design:
  build_dna_block + apply_bimodal       → P1, mode-aware ✓
  build_dna_room_context_signal         → P2, currently RAW preserve = LEAK
  inject_creative_revival                → P3, creative-only ✓
  build_secondary_space_block            → P4, currently RAW = potential leak
  geometry_attached_furnishing           → P5, mode-aware ✓
  emotional_realism                      → P6, mode-aware ✓
```

**Fix vector :** Close the P2 + P4 leaks. Then preserve mode = WM-quality on all atmospheres (per identity).

---

## 10. What's NOT proposed

- ❌ Removing atmosphere identity (architectural content stays in creative mode via existing inject_creative_revival)
- ❌ Refactoring `build_dna_block` or other core infrastructure
- ❌ Changing bimodal opt-in (BIMODAL_ENABLED env flag stays)
- ❌ Forced derivation of Japandi/Zen (opt-out per user)
- ❌ Wave 5.5.30 migration sequence (5.5.31 → 5.5.37 atmosphere-by-atmosphere "WM alignment") — superseded by this leak-fix approach

## 11. What IS proposed

- ✓ Single mechanism fix : extend `apply_bimodal` to operate on `dna_room_context` output (Option A)
- ✓ Per-atmosphere strip table additions (~6-8 new entries) for the identified leaks
- ✓ Special-case Soft Luxury : DNA edit (not strip) for symmetry — anchor instead of remove
- ✓ Wave 5.5.32 ships P2 fix ; Wave 5.5.33 ships P4 fix
- ✓ Optional Wave 5.5.34 longer-term cleanup (Option D : architectural content → architectural_language field)

**This audit is the strategic foundation for Wave 5.5.32+.** No code yet. User decides if/when to start.
