# Wave 5.5.14a — Atmosphere DNA Architectural Bias Audit

**Date:** 2026-05-23
**Scope:** Read-only audit of `backend/prompt_engine/atmosphere_dna/` (10 atmosphere files + `_base.py` renderer)
**Status:** Audit findings only. No code changed. No refactor commitment.

---

## 0. TL;DR — Three findings that change the framing

### Finding A — 3 of 8 `AtmosphereCoreDNA` fields are dead code

| Field | Defined in 10 atmospheres | Read by any renderer | In generation prompt |
|---|---|---|---|
| `philosophy` | ✅ | ✅ `build_dna_block` | ✅ |
| `emotional_intent` | ✅ | ✅ `build_dna_block` | ✅ |
| `architectural_language` | ✅ | ❌ none | ❌ |
| `material_palette` (core) | ✅ | ⚠️ (room DNA palette is rendered, core palette is not) | ⚠️ |
| `lighting_behavior` (core) | ✅ | ⚠️ (room DNA lighting is rendered, core is not) | ⚠️ |
| `luxury_level` | ✅ | ✅ `build_dna_block` | ✅ |
| `forbidden_elements` | ✅ | ✅ `build_dna_block` (top 2 deduped) | ✅ |
| `atmosphere_keywords` | ✅ | ❌ none | ❌ |

And on `RoomAdaptationDNA` (9 fields × 130 room records):

| Field | Read by renderer | In generation prompt |
|---|---|---|
| `furniture_language` | ✅ (3 items) | ✅ |
| `material_palette` (room) | ✅ (3 items) | ✅ |
| `lighting_behavior` (room) | ✅ | ✅ |
| `decor_language` | ✅ (2 items) | ✅ |
| `realism_constraints` | ✅ (2 items) | ✅ |
| `room_specific_constraints` | ❌ none | ❌ |
| `visible_transition_logic` | ✅ but only in **secondary** block (~90 chars) | ⚠️ when visible |
| `negative_rules` | ✅ (3 items) | ✅ |
| `atmosphere_id`, `room_type` | ✅ (header) | ✅ |

**Implication:** The Wave 5.5a Calibration Matrix Principle #6 explicitly cites `architectural_language` as a conflict source (e.g. Nordic "Human-scaled rooms with pitched or low ceilings"). But that string **never reaches gpt-image-1**. So either:
- The Wave 5.5a memory's diagnosis was wrong about the *mechanism* (the field is dormant), OR
- The previous regression came from somewhere else (room-level rendered fields, or a now-rolled-back path).

**Verified by:** `grep ".architectural_language\|.atmosphere_keywords\|.room_specific_constraints" backend/` → zero matches. The only references in code are docstring comments.

### Finding B — The 3-voice boundary system (Wave 5.5.2/3/4) already enforces "atmosphere ≠ architecture"

The current prompt (visible in tonight's V2/V3 log `21:06:14` + `21:10:36`) carries:
- C2.b head voice: `"Atmosphere = surfaces, materials, lighting, decor — never geometry"`
- C3 dedicated section: `"ATMOSPHERE DNA BOUNDARY — the DNA blocks above describe IDEAL materials... They do NOT describe room scale, openings, ceilings, depth"`
- C1.b tail voice: `"WOW only through materials, lighting, atmosphere — NOT geometry"`

These three voices structurally implement **Wave 5.5.14a STEP 4** ("Atmospheres NEVER alter architecture unless explicitly requested"). The principle is already in production, measured at 100% "good or better" hit-rate, 0/9 phantom walls on the complex benchmark apartment.

### Finding C — Where genuine architectural bias still leaks into the prompt

Despite the 3-voice boundary, residual architectural-suspect content **does** appear in rendered fields, mostly via:

1. **`philosophy` core field** (1 sentence per atmosphere, always emitted as `ATMOSPHERE (X): {philosophy} — {emotional_intent}.`)
2. **`furniture_language` first item** (often phrased "low at 40–45 cm" — a height/scale directive that can override photographed bed/sofa heights)
3. **`visible_transition_logic`** (when secondary rooms are visible — phrases like "open side to garden", "pavilion character", "indoor-outdoor flow")
4. **`negative_rules` reactive form** (e.g. "no closed cabinet-heavy bathroom", "no enclosed dining room feel" → implies the model should *open up* the space if currently closed)

These are concrete and addressable. The dead fields are not.

---

## 1. What this audit covers (and what it does NOT cover)

**Covers:**
- Per-atmosphere classification of every phrase that reaches the generation prompt
- Inventory of "architectural-suspect" tokens (geometry/scale/openness/topology)
- Inventory of "decorative-safe" tokens (materials/lighting/decor/textures/colours)
- Severity score per atmosphere (residual bias risk after Wave 5.5.4 boundary system)

**Does NOT cover:**
- Code changes (read-only deliverable per user instruction)
- Refactor commitment (the freeze contract forbids editing these files without explicit exception)
- Surprise Me path analysis (no separate Creative Architect engine exists; "Surprise Me" today = recommender picking an atmosphere, same composer downstream)
- Frontend, persistence, reveal, conversational routing (out of scope)

---

## 2. Methodology

For each of 10 atmospheres, I extracted only the fields that **actually reach `gpt-image-1`**:

```
ATMOSPHERE ({name}): {philosophy} — {emotional_intent}. [{luxury_level}]
ROOM ({room}): {material_palette[:3]}. LIGHT: {lighting_behavior}
  ATMOSPHERE STYLE (restyle existing elements): {furniture_language[:3] + decor_language[:2]}.
  REALISM: {realism_constraints[:2]}. AVOID: {negative_rules[:3] + core_forbidden[:2]}.
```

Then for each phrase I asked: **does this describe geometry/scale/topology/openness/proportion, or does it describe surface/material/light/decor?**

Classification key:
- 🟥 **HIGH bias** — direct geometry/topology directive (e.g. "open-pavilion volumes", "high ceilings", "open side to garden")
- 🟧 **MEDIUM bias** — scale or proportion directive (e.g. "low at 40–45 cm", "monolithic mass", "generous proportions")
- 🟨 **LOW bias** — borderline metaphor that could read as spatial (e.g. "spacious", "airy", "breathable")
- 🟩 **SAFE** — material/lighting/decor/colour/texture (e.g. "travertine", "warm linen", "amber glass pendant")

---

## 3. Per-atmosphere analysis (rendered content only)

### 3.1 Warm Modern

**Core fields rendered:**
- `philosophy`: *"Warm contemporary luxury rooted in emotional comfort, hospitality, softness, and believable urban premium living."* — 🟩 mostly emotional/quality. No geometry directive.
- `emotional_intent`: *"Comforting, refined, welcoming, calm, premium, elegant but livable."* — 🟩 fully emotional.
- `luxury_level`: *"Boutique hotel / premium urban residence"* — 🟩 reference quality only.
- `forbidden_elements` (top 2): *"Cold minimalism, sterile white interiors"* — 🟨 "sterile" can read as spatial-empty signal but framed as negative.

**Room field samples (Living Room):**
- `furniture_language`: bouclé / travertine / linen — 🟩 all decorative.
- `material_palette`: oak floor / sand plaster / travertine — 🟩 surface materials.
- `lighting_behavior`: "Concealed ceiling cove + tungsten-glow table lamps" — 🟩 lighting only.
- `realism_constraints`: "sofa at residential scale", "furniture legs visible and grounded" — 🟩 scale guard, but **anti-bias** (prevents model from oversizing).
- `negative_rules`: "no cold grey palette, no chrome, no matching 3-piece suite" — 🟩 decorative.

**Suspect found:** None in core. Room-level "single clear focal wall — fireplace or artwork, not both" (`room_specific_constraints`) is dead code so it doesn't ship.

**Severity:** 🟩 LOW. Warm Modern's identity is essentially decorative+emotional. **Don't touch.**

---

### 3.2 Japandi Calm

**Core fields rendered:**
- `philosophy`: *"Japanese restraint blended with Scandinavian softness and emotional calm."* — 🟩 fully decorative-emotional.
- `emotional_intent`: *"Still, serene, grounded, quietly refined, breathable, unhurried."* — 🟨 "breathable" reads slightly spatial but contextually emotional.
- `forbidden_elements`: "Empty sterile minimalism, sci-fi white spaces" — 🟩 anti-bias (prevents over-emptying).

**Room field samples (Living Room):**
- `furniture_language`: linen / ceramic / rush — 🟩 decorative.
- `lighting_behavior`: "Paper lantern pendant + concealed warm floor slot" — 🟩 lighting only.
- `realism_constraints`: "sofa low enough to feel grounded — 40–45 cm seat height", **"empty floor space is deliberate, not absent"** — 🟧 the second clause is a topology directive: it tells the model that visible empty floor IS the design, which can push the model to enlarge negative space and over-simplify.
- `negative_rules`: "no cluttered surfaces, no patterned textiles, no warm-orange wood tones, **no cold grey minimalism**" — 🟩 mostly decorative; last item is anti-bias for openness drift.

**Suspect found:** `realism_constraints` "empty floor space is deliberate, not absent" — addresses Japandi's wabi-sabi but on a small/cramped apartment can push the model to widen the room to expose floor. Matches the calibration matrix HIGH priority "cramped Japandi failure" observation.

**Severity:** 🟧 MEDIUM. Decorative+emotional core is clean. The risk is in **one realism clause** that doubles as a topology directive. Single-line tunable.

---

### 3.3 Soft Luxury

**Core fields rendered:**
- `philosophy`: *"Refined hospitality luxury emphasizing softness, elegance, tactile richness, and timeless sophistication."* — 🟩 fully decorative.
- `emotional_intent`: *"Indulgent, serene, tactile, quietly opulent, feminine-refined, sensorially rich."* — 🟩 emotional.
- `forbidden_elements`: "Bling luxury, crystal chandelier clichés" — 🟩 anti-decorative-failure.

**Room field samples (Living Room):**
- `furniture_language`: bouclé / honed marble / cashmere — 🟩 decorative.
- `realism_constraints`: "sofa sized to room", "marble floor with correct 3–5 mm grout lines" — 🟩 anti-bias scale.
- `negative_rules`: "no jewel-tone colour pops, no gold leaf, no asymmetric art gallery wall" — 🟩 decorative.

**Note on dead field:** Core `architectural_language` says *"Curved forms and soft volumes, layered textured surfaces, and silk-to-stone material transitions in generous proportions."* — "generous proportions" IS a topology directive but **does not ship**. If we ever decide to ship the field, this would be HIGH bias.

**Severity:** 🟩 LOW. Reference atmosphere per matrix. Material-driven identity. **Don't touch.**

---

### 3.4 Zen Retreat

**Core fields rendered:**
- `philosophy`: *"Meditative architectural silence and visual restraint."* — 🟨 "architectural silence" is metaphorical but signals "empty volume".
- `emotional_intent`: *"Meditative, still, contemplative, restorative, emptied, deeply calm."* — 🟧 "emptied" is a direct emptiness instruction.
- `lighting_behavior` (core): *"Near-darkness punctuated by single warm shafts"* — 🟩 lighting only (room version has same character).
- `forbidden_elements`: "Decor clutter, fake spa styling, yoga studio clichés, ultra modern tech minimalism, over-styled emptiness" — 🟩 anti-cliché.

**Room field samples (Living Room):**
- `realism_constraints`: "furniture low enough to feel floored — 35–40 cm seats", **"floor space dominant — furniture minimal"** — 🟧 second clause = topology directive (large empty floor area).
- `negative_rules`: "no throw pillows or cushion styling, no plants, no wall art, no technology visible" — 🟩 decorative restraint.

**Where Zen leaks architectural bias:**
- Core `emotional_intent` "emptied" → model interprets as spatial emptying.
- Living room `realism_constraints` "floor space dominant" → enlargement pressure.
- Matrix HIGH priority Zen target noted: "improve openness + lighting authority; avoid dark/cramped outputs" — this means Zen **needs** some spatial directive on small rooms, so neutering ALL spatial language could backfire.

**Severity:** 🟧 MEDIUM. Zen's identity is genuinely spatial (emptiness is a feature). Carefully reducing topology-direct words without erasing the core emptiness signal is a balance act. Single-atmosphere pilot candidate.

---

### 3.5 Nordic Warmth

**Core fields rendered:**
- `philosophy`: *"Scandinavian comfort, warmth, coziness, and emotional softness."* — 🟩 fully emotional.
- `emotional_intent`: *"Cozy, hygge, warm, intimate, human-scaled, reassuring, softly joyful."* — 🟨 "human-scaled" is the only borderline word (emotional but implies a scale judgement).
- `forbidden_elements`: "Cold Ikea minimalism, ultra modern sharpness, excessive black accents, industrial rawness, high-gloss surfaces" — 🟩 decorative anti-failure.

**Dead but worth noting:** Core `architectural_language` = *"Human-scaled rooms with pitched or low ceilings, natural birch and pine, layered wool and sheepskin in a white-to-warm-oat palette."* — Matrix Principle #6 cited this as the source of "rooms compressed, walls inserted" regression in Wave 5.5.1. **But this field never ships.** Either the regression came from elsewhere (a now-rolled-back composer path) or the diagnosis was incorrect.

**Room field samples (Living Room):**
- `furniture_language`: wool / birch / sheepskin — 🟩 decorative.
- `realism_constraints`: "sofa at normal residential height — 45 cm", "candleholders at varied heights" — 🟩 anti-bias scale.
- `room_specific_constraints` (dead): "fireplace or wood stove as focal point if present" — fine.

**Severity:** 🟩 LOW (in current rendered form). Matrix concerns about Nordic "human-scaled / pitched ceilings" do NOT ship.

---

### 3.6 Dark Contemporary

**Core fields rendered:**
- `philosophy`: *"Architectural sophistication through depth, contrast, material richness, and restraint."* — 🟨 "architectural sophistication" is the only borderline phrase; "depth" reads visual not spatial in context.
- `emotional_intent`: *"Dramatic, sophisticated, powerful, sensory, moody but refined, architecturally confident."* — 🟨 "architecturally confident" is mild bias.
- `forbidden_elements`: "Nightclub atmosphere, cyberpunk lighting, black void interiors, aggressive contrast, horror-dark rooms" — 🟩 anti-cliché.

**Room field samples (Living Room):**
- `realism_constraints`: "sofa sized correctly — not modelling-scale oversized" — 🟩 anti-bias.
- `negative_rules`: "no all-black room, no neon, no chrome, **no grey rather than charcoal**" — 🟩 decorative discipline.

**Severity:** 🟩 LOW. Matrix reference atmosphere. Identity is material+light contrast, not geometry. **Don't touch.**

---

### 3.7 Nature Retreat

**Core fields rendered:**
- `philosophy`: *"Biophilic calm integrated with architectural realism and earthy luxury."* — 🟨 "architectural realism" is borderline — could be read as "make the room look architecturally real" or as a topology word.
- `emotional_intent`: *"Grounded, alive, restorative, earthy, connected to nature, quietly luxurious."* — 🟩 emotional.
- `forbidden_elements`: "Fake jungle overload, plant spam, tropical theme park aesthetics, synthetic or artificial materials, sterile minimalism" — 🟩.

**Room field samples (Living Room):**
- `furniture_language`: undyed linen / stone / rattan — 🟩 decorative.
- `realism_constraints`: "sofa at residential scale", "stone wall texture visible — not flat CGI" — 🟩 anti-bias.

**Severity:** 🟩 LOW.

---

### 3.8 Desert Luxe

**Core fields rendered:**
- `philosophy`: *"Middle Eastern contemporary luxury inspired by desert architecture and sculptural calm."* — 🟨 "desert architecture" + "sculptural calm" — leans architectural-aspirational. Lower risk than expected because `material_palette` is so distinctive (tadelakt, sandstone) that the model anchors on material.
- `emotional_intent`: *"Sculptural, warm, monumental, serene, sun-bleached, timelessly opulent."* — 🟧 "sculptural" and "monumental" are spatial words. **MEDIUM bias**.
- `forbidden_elements`: "Theme park Morocco, excessive ornamentation, oversaturated orange, arabesque pattern overuse, fake gold" — 🟩.

**Room field samples (Living Room):**
- `furniture_language`: cotton/leather / sandstone / carved wood — 🟩 decorative.
- `realism_constraints`: "sofa low — 40–45 cm — correct desert floor culture scale" — 🟧 dictates seat height; small rooms with existing higher seating may get re-scaled.

**Severity:** 🟧 MEDIUM. "Monumental" and "sculptural" in emotional_intent are the main vector. Matrix marks Desert Luxe as LOW priority (under-tested), so any tuning waits on real benchmark data.

---

### 3.9 Bali Sanctuary

**Core fields rendered:**
- `philosophy`: *"Luxury tropical sanctuary inspired by refined Balinese hospitality."* — 🟨 "sanctuary" emotionally spatial but mild.
- `emotional_intent`: *"Sacred, immersive, lush, warm, ceremonially refined, deeply restful."* — 🟩 emotional.
- `forbidden_elements`: "Tiki bar aesthetics, beach resort kitsch, bamboo overuse, fake tropical props, tourist souvenir styling" — 🟩 anti-cliché.

**Dead but worth flagging:** Core `architectural_language` = *"Open-pavilion volumes with alang-alang or timber ceilings, volcanic stone, tropical timber, and indoor-outdoor dissolving boundaries."* — this is the **most architecturally-loaded** description across all 10 atmospheres ("open-pavilion volumes", "dissolving boundaries"). It does **not ship**.

**Room field samples (Living Room):**
- `room_specific_constraints` (dead): **"open side to garden or pool — pavilion character"** — would be HIGH bias if shipped (direct topology directive). Does not ship.
- `visible_transition_logic`: "volcanic stone floor and teak ceiling continue into adjacent pavilion; stone palette echoes through visible pool area" — ships in secondary space block when a second room is visible. The word "pavilion" recurs through visible-transition strings.
- `negative_rules`: "no bamboo furniture, no bright tropical colour, no tourist ornament" — 🟩.

**Severity:** 🟧 MEDIUM (but cautioned). Bali is the **openness reference** per matrix — borrowing source for Japandi/Zen on openness. Identity IS partly spatial (pavilion). If we ever start shipping `architectural_language`, Bali becomes 🟥 HIGH. As-is, the leakage is via `visible_transition_logic` "pavilion" repetition. Matrix flags Bali as **DO NOT DILUTE**.

---

### 3.10 Tropical Escape

**Core fields rendered:**
- `philosophy`: *"Open-air tropical living with relaxed contemporary luxury."* — 🟧 "open-air" is a direct topology word. **MEDIUM-HIGH bias.**
- `emotional_intent`: *"Breezy, alive, relaxed-luxurious, sun-soaked, carefree but refined, vibrant-calm."* — 🟨 "breezy" mildly spatial; mostly emotional.
- `forbidden_elements`: "Beach clichés, fake resort styling, overdecorated tropical kitsch, bamboo overuse, nautical or coastal motifs" — 🟩.

**Dead but worth flagging:** Core `architectural_language` = *"Open-plan volumes dissolving into landscape, tropical timber and whitewash, with a contemporary residential ease."* — "open-plan volumes dissolving into landscape" = HIGH bias. Not shipped.

**Room field samples (Living Room):**
- `room_specific_constraints` (dead): "open side to terrace or garden — tropical villa character" — would be HIGH if shipped.
- `visible_transition_logic`: "white walls and concrete floor continue into terrace; rattan furniture palette echoes outdoor seating" — mostly material continuity. 🟨 "into terrace" implies an opening.
- `negative_rules` (Living Room): "no overly lush plant collection" — 🟩. (Bathroom): **"no closed cabinet-heavy bathroom"** — 🟧 reactive opening pressure.
- `room_specific_constraints` (dead, Bathroom): "open or semi-open if villa allows" — high bias if shipped.

**Severity:** 🟧 MEDIUM (rendered). Tropical's `philosophy` first 2 words ("Open-air") are the only ROCK-ON architectural directive currently shipping in any atmosphere's philosophy field. Other 9 atmospheres have decorative/emotional philosophies. Matrix flags Tropical as **DO NOT DILUTE** (continuity reference).

---

## 4. Cross-atmosphere token inventory

### 4.1 Architectural-suspect tokens currently shipping in prompts

| Phrase | Where it ships | Atmospheres | Severity |
|---|---|---|---|
| "Open-air" | `philosophy` | Tropical Escape | 🟧 |
| "open-pavilion / pavilion" | `visible_transition_logic` | Bali Sanctuary | 🟧 |
| "indoor-outdoor / dissolving boundaries" | dead `architectural_language` | Bali, Tropical | ❌ not shipped |
| "human-scaled / pitched ceilings" | dead `architectural_language` | Nordic | ❌ not shipped |
| "generous proportions / monolithic / sculptural" | `emotional_intent` (Desert) | Desert Luxe | 🟧 |
| "architectural silence / architecturally confident" | `philosophy` (Zen) / `emotional_intent` (Dark) | Zen, Dark | 🟨 |
| "floor space dominant / empty floor is deliberate" | `realism_constraints` | Zen, Japandi | 🟧 |
| "no closed / no enclosed" | `negative_rules` (Tropical bathroom + dining) | Tropical | 🟧 reactive opening pressure |
| "open side to garden / open side to terrace" | dead `room_specific_constraints` | Bali, Tropical, Nordic terrace | ❌ not shipped |
| "low at 35–45 cm" | `furniture_language` / `realism_constraints` | Japandi, Bali, Zen, Desert | 🟧 height directive |

### 4.2 Decorative-safe tokens (all atmospheres)

The vast majority of rendered content falls here:
- All `material_palette` entries (oak, travertine, linen, marble, tadelakt, volcanic stone, ash, slate, concrete, cotton, rattan, brass, bronze, etc.)
- All `lighting_behavior` entries (concealed coves, candle lanterns, amber pendants, etc.)
- All `decor_language` entries (vessels, candles, single artwork, dried botanicals, etc.)
- Most `furniture_language` items (sofas, beds, chairs, tables described by material/colour)
- Most `negative_rules` (no chrome, no white tile, no pattern, etc.)
- All `forbidden_elements` (anti-clichés)
- All `emotional_intent` EXCEPT Desert ("monumental/sculptural") and slight bias in Nordic ("human-scaled"), Zen ("emptied")

---

## 5. Severity ranking (residual architectural bias risk, with Wave 5.5.4 boundary system active)

| Rank | Atmosphere | Severity | Where the leakage is | Recommended action |
|---|---|---|---|---|
| 1 | **Tropical Escape** | 🟧 MED-HIGH | `philosophy` "Open-air" + bathroom `negative_rules` "no closed/enclosed" | Single-line tuning. But: matrix reference atmosphere — careful. |
| 2 | **Zen Retreat** | 🟧 MEDIUM | `emotional_intent` "emptied" + `realism_constraints` "floor space dominant" | Pilot candidate. Risk: stripping emptiness signal kills Zen identity. |
| 3 | **Bali Sanctuary** | 🟧 MEDIUM | `visible_transition_logic` "pavilion" recurrence | DO NOT TOUCH per matrix. Borrowing source. |
| 4 | **Desert Luxe** | 🟧 MEDIUM | `emotional_intent` "monumental, sculptural" | Defer per matrix (under-tested). |
| 5 | **Japandi Calm** | 🟧 MEDIUM | `realism_constraints` "empty floor space deliberate" | HIGH priority calibration target per matrix. Tunable. |
| 6 | **Warm Modern** | 🟩 LOW | None significant | Don't touch (user's favourite per matrix). |
| 7 | **Soft Luxury** | 🟩 LOW | None (rendered) | Reference atmosphere. Don't touch. |
| 8 | **Dark Contemporary** | 🟩 LOW | "architecturally confident" mildly metaphorical | Reference atmosphere. Don't touch. |
| 9 | **Nature Retreat** | 🟩 LOW | "architectural realism" borderline | Don't touch. |
| 10 | **Nordic Warmth** | 🟩 LOW | None (rendered — the suspect field is dead) | Don't touch. |

---

## 6. Three actionable directions (in increasing risk)

These are **proposals only** — no commitment to implement.

### Direction A — "Dead Field Audit" cleanup (LOWEST RISK)
- Remove or formally deprecate `architectural_language`, `atmosphere_keywords`, `room_specific_constraints` from the DNA dataclass to eliminate confusion and align documentation with reality.
- **Why:** These fields exist, get reviewed in matrix memos, but never affect output. Confusing for future audits.
- **Risk:** Requires freeze-contract exception (dataclass change), even though semantically a no-op. Could just rename to `_unused_*` as documentation.
- **Effort:** ~10 lines.
- **Wave 5.5.14a goal alignment:** Indirect — removes a false signal that misled prior tuning attempts.

### Direction B — Single-atmosphere pilot: Tropical Escape `philosophy` rephrasing (MEDIUM RISK)
- Replace `philosophy: "Open-air tropical living..."` with `philosophy: "Relaxed contemporary tropical luxury — sun-warmed materials and breezy interiors."` (same identity, "Open-air" removed as direct topology cue).
- **Why:** Highest-ranking shipping bias; isolated to one string; rollback trivial (git revert one line).
- **Risk:** Tropical is a matrix reference atmosphere. Identity dilution risk = real. Requires benchmark on at least one tropical photo before ship.
- **Effort:** 1 line + benchmark.
- **Wave 5.5.14a goal alignment:** Direct.

### Direction C — Reactive negative_rules normalization across affected atmospheres (HIGHER RISK)
- Audit and rewrite `negative_rules` phrases that imply spatial openings, e.g.:
  - `"no closed cabinet-heavy bathroom"` → `"no cabinet-heavy styling"` (drop spatial cue)
  - `"no enclosed dining room feel"` → `"no dark heavy dining feel"` (drop spatial cue)
  - `"empty floor space is deliberate, not absent"` → constrained to room types where it doesn't override architecture (e.g. remove from `living_room` for Japandi where the apartment may already be small)
- **Why:** These reactive phrases were added to prevent the model from styling against the atmosphere's spirit, but on cramped apartments they push the model to open up architecture.
- **Risk:** Each negative rule was added for a reason; removing them may bring back other failure modes (kitchen cabinet-heavy bathroom feel, etc.).
- **Effort:** 5–15 lines across multiple files.
- **Wave 5.5.14a goal alignment:** Direct, but more invasive.

---

## 7. Surprise Me distinction analysis

**Finding:** There is no separate "Creative Architect Engine" today. "Surprise Me" is:
1. `frontend` sends a flag indicating Surprise Me was selected.
2. `backend/prompt_engine/atmosphere_recommender.py` picks an atmosphere from a curated subset (this file is FROZEN).
3. From then on, **the same composer.py / composer_v2.py path runs** with the same preservation stack and the same 3-voice boundary system.

**Implication for Wave 5.5.14a STEP 6:** A "Surprise Me allows more creativity" mode would be **new functionality**, not just a DNA refactor. It would require:
- New composer path or a `surprise_me=True` flag propagated through composer.py
- A separate prompt assembly that downweights the boundary voices
- Tests to ensure default path stays unaffected

This is **not part of "audit only"** scope. If the user wants this, it would be Wave 5.5.15 or a separate experimental wave with its own design + freeze exception.

---

## 8. What the audit did NOT find

To be honest about scope:

- **No evidence in the DNA itself** of "spatial openness expansion", "geometry cleanup", "symmetry enhancement", "modernized spatial composition" beyond what's listed in Section 4.1. The strong Wave 5.5.14a STEP 1 vocabulary ("simplification bias", "modernization bias") may overestimate what's actually shipping. Most of those concepts live in `architectural_language` and `room_specific_constraints` — both **dead fields**.
- **No evidence** of "architectural idealization language" reaching the prompt outside the 10 items in Section 4.1.
- **No evidence** that the prompt currently lacks the global rule "Atmospheres NEVER alter architecture" — the 3-voice boundary (Wave 5.5.4) already encodes it, and tonight's V2/V3 logs confirm it ships.

If the user has observed regressions despite this baseline, the cause is more likely to be:
- gpt-image-1 model-level interpretation (cf. Wave 5.5.1 lesson: "intimate" → compressed)
- A specific photo where the boundary voices were drowned out by the atmosphere DNA volume (rare — measured 100% on benchmark)
- Surprise Me path (uncurated atmosphere choice on a photo that doesn't fit)

A useful follow-up: **the user shares the specific photo+atmosphere combo where regression was observed**, and we benchmark that one case before refactoring 10 atmospheres.

---

## 9. Recommendation

**Strict recommendation if the user wants action this week:**

1. **Direction A first** (Dead Field Audit): 10-line cleanup of confusing dormant fields. Low risk, prevents future tuning waves from chasing red herrings. Freeze exception needed (dataclass change).

2. **Direction B as opt-in pilot** (Tropical philosophy): only with a real benchmark photo, only on user authorization, with `git revert` as rollback.

3. **Do NOT proceed to Direction C** (negative_rules sweep) without specific regression evidence from the user — the reactive rules were added for documented reasons.

4. **Defer Surprise Me redesign** to a separate wave with its own scope (new composer path, not DNA).

**Strict recommendation if no concrete regression case exists:**

- Hold. The system measures 100% hit-rate. The proposed refactor risks regressing reference atmospheres for a problem that may have been solved by Wave 5.5.4 already.

---

## 10. Rollback strategy

For any direction taken:
- Each change is ≤ 5 lines per atmosphere (matrix Principle #4)
- Git-revert-able single commit per atmosphere
- Benchmark required: at least 1 photo × touched atmosphere + 2 neighbours
- Rollback trigger: any neighbour scores drop, or touched atmosphere loses identity recognition

---

## 11. Open questions for the user

1. **What concrete photo/result motivated this wave?** Without that, the audit cannot validate the premise.
2. **Direction A, B, both, or none?** Each has different freeze-contract implications.
3. **Surprise Me redesign**: is this a real product need or theoretical? It's a separate wave's worth of work.
4. **Are the matrix "reference atmospheres" (Bali, Tropical, Dark, Soft Luxury) still untouchable**, or does this wave grant a one-time exception? If exception, which?

---

*End of audit. No code modified. 3 files in `backend/prompt_engine/atmosphere_dna/` read; renderer `_base.py` confirmed as sole DNA-to-prompt path. Wave 5.5a Calibration Matrix and Freeze Contract: Intelligence Foundation memories consulted and cross-referenced.*
