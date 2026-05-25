# Wave 5.5.24 — Furnishing Intelligence + Architecture-Safe Placement Audit

**Date :** 2026-05-25
**Type :** read-only systematic DNA audit (no code changes)
**Scope :** 10 atmospheres × 5 essential rooms (living / bedroom / kitchen / bathroom / dining) = 50 cells × 6 DNA fields = 300 micro-checks
**Branch :** wave-5.5.23-validation-infra
**Trigger :** Following Wave 5.5.15→22 empirical chain, need systematic DNA audit before extending the Wave 5.5.21-22 fix pattern to remaining atmospheres.

---

## 1. Executive summary

### Core findings

1. **TV blockers : 5 atmospheres systematically block TV in living_room.** 4 already partially fixed (Warm Modern, Soft Luxury, Dark Contemporary, Nordic — Waves 5.5.21+22). 2 remain explicitly TV-blocked by design : **Zen** (`"no technology visible"`), **Nature Retreat bedroom** (`"no technology visible"`). 3 implicitly block via atmosphere identity : Japandi (philosophy), Tropical (plant-focal mandate), Bali (density limit).

2. **Rug essentially absent from DNA across the board.** Only **Nordic Warmth** explicitly mentions rugs (`"layered rugs permitted"` + sheepskin). The other 9 atmospheres have NO rug mention in living_room essentials. **Systematic gap.**

3. **Mirror essential MISSING from bathroom decor on 5 atmospheres :** Soft Luxury, Dark Contemporary, Nordic Warmth, Nature Retreat, Desert Luxe. Only Warm Modern + Japandi + Zen (one small mirror permitted) + Bali + Tropical explicitly mention mirror in bathroom decor_language.

4. **Wall-occupying decor competes with TV across atmospheres.** Vessel-on-shelf / large-artwork patterns appear in Soft Luxury (`"oversized ceramic vessel"`), Dark Contemporary (`"large-scale abstract artwork"`), Nature Retreat. Same root cause as the warm_modern vessel issue we fixed in Wave 5.5.21.

5. **Architectural directives in DNA can drive drift.** `"open side to terrace or garden"` (Tropical + Bali room_specific_constraints) implicitly INSTRUCTS the model to open walls / windows on apartments that don't have a terrace. **High preserve-mode risk.**

6. **Density-limit constraints** (`"maximum 2/3 decorative objects"`) compete with furnishing-richness goal in 4 atmospheres : Japandi (3), Zen (2), Desert Luxe (2), Bali (2+1plant). Some are legitimate atmosphere identity (Zen), others are tunable (Desert / Bali).

7. **Composition-authoritative wording** : Soft Luxury `"symmetry in furniture placement — not haphazard"` and Tropical/Bali `"open shelf mandatory"` are MANDATE-style language. Soft Luxury symmetry directly contradicts apartments with asymmetric architecture (preserve-mode danger).

8. **Zen Retreat is intentionally anti-furnishing.** All 5 essential rooms have STRONG anti-density / anti-decor rules. **Recommended : EXCLUDE Zen from any furnishing-richness wave.** It's a feature, not a bug.

### Headline numbers

- Atmospheres with usable furnishing potential (TV+rug+essentials work) post-audit-fixes : **6/10** (Warm Modern, Soft Luxury, Dark Contemporary, Nordic Warmth, Nature Retreat, Desert Luxe)
- Atmospheres where furnishing-richness conflicts with atmosphere identity : **4/10** (Japandi, Zen, Tropical, Bali — leave alone)
- DNA edits required for fix coverage : ~20-25 micro-edits (focal-wall expansion + decor competition + rug addition + mirror addition)
- Total estimated Wave 5.5.25+ implementation : ~2h code + standard bench

---

## 2. DNA contradiction audit table

Per (atmosphere, room) — only cells with detected contradictions shown.

### Living room

| Atm | Contradiction | Severity | Status |
|---|---|---|---|
| warm_modern | TV-facing-row negation + vessel occupies wall + focal-wall excludes TV | HIGH | ✓ FIXED Wave 5.5.21 |
| soft_luxury | Focal element excludes TV + `"no visible TV above fireplace"` + vessel occupies wall + symmetry mandate | HIGH | ⚠️ PARTIALLY FIXED Wave 5.5.22 (TV constraints + neg_rule) ; vessel + symmetry still active |
| dark_contemporary | Focal-wall artwork-only + large-scale artwork in decor competes for wall | HIGH | ⚠️ PARTIALLY FIXED Wave 5.5.22 (constraint) ; artwork in decor still competes |
| nordic_warmth | Focal-point fireplace/wood-stove only | MEDIUM | ✓ FIXED Wave 5.5.22 |
| japandi_calm | Artwork + branch in decor occupy wall + max-3-objects density limit | MEDIUM | unfixed (atmosphere identity) |
| zen_retreat | `"no technology visible"` + `"zero wall decoration"` + max-2-furniture | CRITICAL but BY DESIGN | leave alone |
| nature_retreat | Plant-2-max + statement-wall-restriction | LOW | unfixed |
| desert_luxe | `"max 2 decorative objects"` density limit | LOW | unfixed |
| tropical_escape | `"plant as primary accent"` focal mandate + `"open side to terrace"` architectural directive | HIGH | unfixed |
| bali_sanctuary | `"open side to garden or pool"` architectural directive + `"max 2 objects + 1 plant"` density | HIGH | unfixed |

### Bedroom

| Atm | Contradiction | Severity | Status |
|---|---|---|---|
| warm_modern | "no TV directly facing bed unless wall-mounted" — soft block | LOW | TV partially permitted (wall-mounted) |
| japandi_calm | "no TV in bedroom" explicit | MEDIUM by design | leave alone |
| zen_retreat | "no bedside table — wall lantern only" + "no bedside lamp on table" + "no bedding layers" + "no headboard" | CRITICAL by design | leave alone |
| nature_retreat | "no technology visible" + "no wall art" | MEDIUM by design | leave alone |
| desert_luxe | "no artwork — wall left as plaster composition" | LOW | unfixed |

### Kitchen

| Atm | Contradiction | Severity | Status |
|---|---|---|---|
| japandi_calm | "all appliances hidden or flush-integrated" — hides essentials | LOW | atmosphere identity |
| zen_retreat | "no visible appliances" + "no decorative objects on countertop" | MEDIUM by design | leave alone |
| nature_retreat | "no stainless steel exposed appliances" | LOW | OK |
| tropical_escape | "open shelf mandatory" mandate | MEDIUM | unfixed (mandate language) |
| bali_sanctuary | Same "open shelf mandatory" mandate | MEDIUM | unfixed |

### Bathroom

| Atm | Contradiction / Gap | Severity | Status |
|---|---|---|---|
| soft_luxury | Mirror MISSING from decor_language | MEDIUM | unfixed |
| dark_contemporary | Mirror MISSING from decor_language | MEDIUM | unfixed |
| nordic_warmth | Mirror MISSING from decor_language ; "no chrome" hard rule | MEDIUM | unfixed |
| nature_retreat | Mirror MISSING from decor_language | MEDIUM | unfixed |
| desert_luxe | Mirror MISSING from decor_language | MEDIUM | unfixed |
| tropical_escape | "open or semi-open if villa allows" architectural directive | HIGH | unfixed (preserve risk) |
| bali_sanctuary | "open or semi-open shower — no full enclosure in pavilion" architectural directive | HIGH | unfixed (preserve risk) |
| zen_retreat | "no mirror — or one small mirror only" | LOW by design | leave alone |

### Dining room

| Atm | Contradiction | Severity | Status |
|---|---|---|---|
| zen_retreat | "no chairs — floor cushions only" | CRITICAL by design | leave alone |
| soft_luxury | "chairs identical in fabric and form — no mixing" | LOW | unfixed (style rule) |
| tropical_escape | "open side to terrace or garden if space allows" | MEDIUM (conditional) | unfixed |

---

## 3. Anti-placement vocabulary table

Words that BLOCK or RESTRICT specific furniture placement.

| Pattern | Atmospheres affected | Effect | Recommended action |
|---|---|---|---|
| `"no technology visible"` | Zen living + bedroom, Nature bedroom | Blocks TV entirely | Leave (atmosphere identity for Zen/Nature) |
| `"no TV in bedroom"` | Japandi bedroom | Explicit TV block | Leave (Japandi identity) |
| `"no TV directly facing bed"` | Warm Modern bedroom | Permits wall-mounted only | OK (already softer) |
| `"no visible TV above fireplace"` | Soft Luxury living | Explicit fireplace+TV conflict | ✓ FIXED Wave 5.5.22 |
| `"single focal element — X or Y"` (no TV in list) | Multiple living rooms | Implicit TV exclusion | Fix per Wave 5.5.21+22 pattern when wanted |
| `"maximum N decorative objects"` | Japandi (3), Zen (2), Desert (2), Bali (2+1) | Density limit caps furnishing | Tunable for Desert/Bali ; leave Japandi/Zen |
| `"single statement [wall/element/focal]"` | Nordic, Nature, Desert | Restricts to ONE focal element | Tunable wording |
| `"symmetry in furniture placement — not haphazard"` | Soft Luxury living | Composition mandate | RISKY for asymmetric apartments — recommend trim |
| `"open shelf mandatory"` | Tropical + Bali kitchen | Mandate language | Soften to "open shelf preferred" |
| `"open side to terrace/garden"` | Tropical + Bali living + bathroom | Architectural directive | CRITICAL — drop or condition explicitly |
| `"no chairs — floor cushions only"` | Zen dining | Anti-essential | Leave (Zen identity) |
| `"no bedside table"` | Zen bedroom | Anti-essential | Leave (Zen identity) |
| `"all appliances hidden"` | Japandi kitchen | Anti-essential | Leave (Japandi identity) |

---

## 4. Spatial pressure vocabulary table

Composition-authoritative / architecture-altering wording detected in DNA.

| Pattern | Where found | Risk | Action |
|---|---|---|---|
| `"open side to terrace or garden"` | Tropical living + Bali living | CRITICAL — pushes architecture change | Drop or rephrase as "where existing open side allows" |
| `"open side to garden or pool — pavilion character"` | Bali living | CRITICAL — pavilion is architecturally specific | Same — condition on existing |
| `"open or semi-open shower — no full enclosure"` | Tropical + Bali bathroom | HIGH — forces architectural change | Same |
| `"single statement stone or timber wall — not all four walls"` | Nature Retreat living | MEDIUM — could lead to wall material change | Wording is constraint (NOT all four) so OK ; verify no drift in bench |
| `"symmetry in furniture placement — not haphazard"` | Soft Luxury living | HIGH — could overwrite photo's asymmetric layout | Drop or soften to "considered furniture placement" |
| `"four-poster bed as room's defining element"` | Bali bedroom | MEDIUM — could replace existing bed | Soften to "four-poster preferred where space allows" |
| `"plant as living room's primary accent"` | Tropical living | MEDIUM — could compete with photo's existing focal | OK if plant added without removing existing |

### Hard-banned vocabulary CHECK across ALL DNA

Scanned for `expansive` / `airy` / `grand` / `open-plan` / `seamless` / `immersive` / `gallery-like` / `fully designed` / `hospitality-grade` / `media wall` / `statement wall` :

**Result : NO banned vocabulary found in any DNA field.** Previous waves cleaned this up. ✓

---

## 5. Anti-TV / Anti-rug conflict table

### Anti-TV per atmosphere living_room

| Atm | TV explicit block | TV implicit block | Status |
|---|---|---|---|
| warm_modern | NONE | NONE | ✓ permitted Wave 5.5.21 |
| japandi_calm | NONE | atmosphere bias + decor competition | leave alone |
| zen_retreat | `"no technology visible"` | full anti-decor philosophy | leave alone |
| soft_luxury | NONE (Wave 5.5.22 fix) | vessel still competes | partial — see §7 |
| dark_contemporary | NONE | artwork in decor competes | partial — see §7 |
| nordic_warmth | NONE (Wave 5.5.22 fix) | NONE | ✓ permitted |
| nature_retreat | NONE | NONE explicit but bedroom blocks TV | OK |
| desert_luxe | NONE | density limit (max 2 objects) | OK if wanted |
| tropical_escape | NONE | plant-focal mandate competes | partial — see §7 |
| bali_sanctuary | NONE | density limit | OK if wanted |

### Anti-rug per atmosphere living_room

| Atm | Rug status | Action |
|---|---|---|
| warm_modern | ABSENT from DNA | Add rug suggestion if wanted |
| japandi_calm | CONDITIONAL — `"solid neutral rug or no rug — no pattern"` | OK ; conservative permission |
| zen_retreat | ABSENT (`"no plants"` etc. anti-decor) | Leave |
| soft_luxury | ABSENT from DNA | Add rug if wanted |
| dark_contemporary | ABSENT from DNA | Add rug if wanted |
| nordic_warmth | **EXPLICIT — `"layered rugs permitted — wool flatweave under pile"`** | ✓ rug native |
| nature_retreat | ABSENT from DNA | Add rug if wanted |
| desert_luxe | ABSENT from DNA | Add rug if wanted |
| tropical_escape | ABSENT from DNA | Add rug if wanted |
| bali_sanctuary | ABSENT from DNA (only "handwoven textile at floor-level" in furniture_language) | Could clarify |

**Rug systematic gap : 7/10 atmospheres have NO rug in DNA.** Only Nordic explicitly permits rugs. This is a STRUCTURAL deficit.

---

## 6. Safe rewrite proposals

### High-priority fixes (recommended for Wave 5.5.25 ship)

#### Soft Luxury living_room

| Field | Before | After | Reason |
|---|---|---|---|
| `decor_language[0]` | `"oversized ceramic vessel with dried pampas or lunaria"` | `"floor-level ceramic vessel with dried pampas or lunaria"` | Moves vessel from wall-focal area to floor level (no TV competition) |
| `room_specific_constraints[1]` | `"symmetry in furniture placement — not haphazard"` | `"considered furniture placement that respects the photographed layout"` | Drops symmetry mandate (preserve-risk for asymmetric apartments) |

#### Dark Contemporary living_room

| Field | Before | After | Reason |
|---|---|---|---|
| `decor_language[0]` | `"large-scale abstract artwork in dark or muted tones"` | `"sculptural ceramic vessel in dark or metallic finish, floor-level"` | Removes artwork from decor (already permitted as focal-wall option via room_specific_constraints — no need to mandate as decor) |

#### Tropical Escape living_room

| Field | Before | After | Reason |
|---|---|---|---|
| `room_specific_constraints[0]` | `"open side to terrace or garden — tropical villa character"` | `"where the photographed apartment shows an open side to terrace or garden, emphasize that opening"` | Conditional ; removes architectural directive that would otherwise instruct model to open walls |
| `room_specific_constraints[1]` | `"plant as living room's primary accent — one large specimen"` | `"a large tropical plant may anchor the room as a primary natural accent"` | Permissive (`"may anchor"`) instead of mandate (`"plant as primary accent"`) — allows TV to coexist |

#### Bali Sanctuary living_room

| Field | Before | After | Reason |
|---|---|---|---|
| `room_specific_constraints[0]` | `"open side to garden or pool — pavilion character"` | `"where the photographed apartment shows an open side, preserve and emphasize that connection"` | Conditional — eliminates architectural drift risk |

#### Bali Sanctuary bathroom

| Field | Before | After | Reason |
|---|---|---|---|
| `room_specific_constraints[0]` | `"open or semi-open shower — no full enclosure in pavilion bathroom"` | `"if the photographed bathroom is open-pavilion style, preserve the open shower ; otherwise respect the existing enclosure"` | Conditional — eliminates wall-modification directive |

#### Tropical Escape bathroom

| Field | Before | After | Reason |
|---|---|---|---|
| `room_specific_constraints[1]` | `"open or semi-open if villa allows"` | `"if the photographed bathroom is open-villa style, preserve openness"` | Conditional |

### Medium-priority fixes (Wave 5.5.26+)

#### Add mirror to bathroom decor_language

Currently missing from : Soft Luxury, Dark Contemporary, Nordic Warmth, Nature Retreat, Desert Luxe.

| Atm | Proposed mirror addition (add to decor_language) |
|---|---|
| soft_luxury | `"single mirror in brushed champagne brass frame above vanity"` |
| dark_contemporary | `"single dark-framed mirror above floating vanity"` |
| nordic_warmth | `"simple round mirror above vanity in matte nickel or pine frame"` |
| nature_retreat | `"reclaimed timber-framed mirror above vanity"` |
| desert_luxe | `"hammered brass-framed mirror above basin"` |

#### Add rug to living_room (where atmosphere allows)

| Atm | Proposed rug addition |
|---|---|
| warm_modern | Add to decor_language : `"soft wool rug in oat or camel within seating footprint"` |
| soft_luxury | `"soft silk-blend rug in cream or blush within seating footprint"` |
| dark_contemporary | `"deep-pile rug in charcoal or dark tonal within seating footprint"` |
| nature_retreat | `"natural jute or wool rug within seating footprint"` |
| desert_luxe | `"woven cotton or raw wool rug in sand tones within seating footprint"` |
| tropical_escape | `"woven jute or natural fiber rug within seating footprint"` |
| bali_sanctuary | Already has handwoven textile in furniture_language ; could clarify : `"handwoven natural-fiber rug within seating footprint"` |

#### Tunable density limits (where atmosphere permits)

| Atm | Current | Proposed | Reason |
|---|---|---|---|
| desert_luxe | `"max 2 decorative objects"` | `"3-4 considered decorative objects"` | Slightly more allowance ; preserves desert restraint |
| bali_sanctuary | `"max 2 objects + 1 plant"` | `"3-4 considered objects including 1 plant"` | Same |

### Hands-off : atmospheres where furnishing-richness fights identity

| Atm | Why hands-off |
|---|---|
| japandi_calm | Spareness IS the identity. Adding TV / more decor degrades atmosphere |
| zen_retreat | Anti-furniture philosophy is core. Editing = atmosphere destruction |
| nature_retreat bedroom | "no technology visible" is biophilic intent ; respect |

---

## 7. Room-by-room furnishing recommendations

### Living room — universal additions where atmosphere allows

- **TV** : 6 atmospheres ready (Warm Modern ✓, Soft Luxury ✓, Dark Contemporary ✓, Nordic ✓, Nature Retreat, Desert Luxe). Skip Japandi, Zen, Tropical (plant-focal), Bali (density)
- **Rug** : Add to 7 atmospheres (skip Japandi conditional permission, Zen, Bali already handwoven)
- **Coffee table** : already in geometry_attached_furnishing signal Wave 5.5.16, no DNA edit needed
- **Side lighting** : already in geometry_attached_furnishing signal

### Bedroom — focus on rug + bedside lighting where missing

- **Rug at bedside** : 7 atmospheres missing (Warm Modern, Soft Luxury, Dark Contemporary, Nature Retreat, Desert Luxe, Tropical, Bali). Add via decor_language
- **Bedside lighting** : present in 8/10 DNAs (zen, japandi exceptions are identity)
- **Curtains** : present in most

### Kitchen — minimal changes needed

- DNA already covers cabinetry, countertop, accessories well across all 10 atmospheres
- Drop `"open shelf mandatory"` mandate language in Tropical + Bali kitchen (soften to "preferred")

### Bathroom — add mirror to 5 atmospheres

See §6 medium-priority list

### Dining room — no major changes

DNA already comprehensive across atmospheres

---

## 8. Preserve-risk analysis

| Risk pattern | Atmospheres | Severity | Action |
|---|---|---|---|
| Architectural directives ("open side to terrace") | Tropical living + bathroom, Bali living + bathroom | CRITICAL | Convert to conditional wording (§6 fixes) |
| Symmetry mandate vs asymmetric apartments | Soft Luxury living | HIGH | Drop or soften (§6 fixes) |
| Wall-occupying decor competing for focal area | Soft Luxury, Dark Contemporary, Nature Retreat | MEDIUM | Move decor away from wall focal area (§6 fixes) |
| Density limits competing with furnishing-richness | Desert, Bali | LOW | Tunable (§6 medium-priority) |
| Plant-focal mandate vs other furniture | Tropical | MEDIUM | Soften from mandate to permissive (§6 fixes) |

**Critical preserve insight :** The Tropical + Bali `"open side to terrace/garden"` directives are the **biggest preserve-mode architectural drift risk** across the entire DNA. If a user uploads an indoor-only apartment in Tropical mode, the model has explicit instruction to OPEN a side to a non-existent terrace → wall modification.

---

## 9. Char budget analysis

Estimated char delta per atmosphere if all recommended fixes ship :

| Atm | Living changes | Bedroom changes | Bathroom changes | Estimated total delta |
|---|---|---|---|---|
| warm_modern | +rug (~50 chars) | +rug (~40) | 0 | +90 |
| soft_luxury | -vessel rewrite (~+15) + symmetry rewrite (~+30) + rug (~50) | +rug (~40) | +mirror (~50) | +185 |
| dark_contemporary | -artwork→vessel (~0) + rug (~50) | +rug (~40) | +mirror (~45) | +135 |
| nordic_warmth | 0 | already has sheepskin | +mirror (~55) | +55 |
| nature_retreat | +rug (~45) | (skip — no tech) | +mirror (~45) | +90 |
| desert_luxe | +rug (~50) + density (~+5) | 0 | +mirror (~45) | +100 |
| tropical_escape | architectural rewrite (~+30) + plant softer (~+10) + rug (~45) | 0 | architectural rewrite (~+25) | +110 |
| bali_sanctuary | architectural rewrite (~+30) + density (~+5) | 0 | architectural rewrite (~+30) | +65 |

**Net impact :** all atmospheres stay within budget (margins are 200-400+ chars on non-tight atmospheres). Tightest atmospheres (Tropical/Nordic creative already at +13/+47 margin) will see dna_room_context drop on tightest prompts, but the changes themselves don't break budget.

**Bimodal gate :** all changes are in DNA which gets stripped on preserve mode via apply_bimodal. So the new content only fires on creative + default modes. Preserve mode unaffected.

Actually CORRECTION : edits to `decor_language` and `room_specific_constraints` DO affect both preserve and creative (apply_bimodal only strips architectural_language and atmosphere-related words, not these fields). Need careful preserve bench gate.

---

## 10. Recommended implementation order

### Wave 5.5.25 — Preserve-safety fixes (CRITICAL)

Ship first because they fix existing preserve-drift risks :

1. Tropical + Bali "open side" directives → conditional
2. Soft Luxury symmetry mandate → soften
3. Bench preserve mode immediately after

Estimated effort : 4 DNA edits, 30 min code + 15 min bench

### Wave 5.5.26 — Decor decongestion (HIGH priority for TV)

Fix wall-competing decor on already-TV-unblocked atmospheres :

1. Soft Luxury vessel → floor-level
2. Dark Contemporary artwork → floor-level vessel
3. Bench creative mode (TV appearance test)

Estimated effort : 2 DNA edits, 30 min code + 15 min bench

### Wave 5.5.27 — Mirror additions (MEDIUM)

Add mirror to 5 bathroom DNAs : Soft Luxury, Dark Contemporary, Nordic, Nature Retreat, Desert Luxe.

Estimated effort : 5 DNA edits, 20 min code + ad-hoc visual check

### Wave 5.5.28 — Rug additions (MEDIUM)

Add rug to 7 living_room DNAs + 7 bedroom DNAs.

Estimated effort : 14 DNA edits, 30 min code + standard bench

### Wave 5.5.29 — Density tunings (LOW)

Desert Luxe + Bali Sanctuary density limit relaxation.

Estimated effort : 2 DNA edits, 15 min + smoke test

### NOT recommended

- Japandi / Zen / Nature Retreat bedroom : leave atmosphere identity intact
- `"open shelf mandatory"` Tropical/Bali kitchen : low-priority cosmetic

---

## 11. Risk ranking per atmosphere

### Architecture drift risk (preserve mode primary)

| Atm | Risk score | Cause |
|---|---|---|
| Tropical Escape | **HIGH** | "open side to terrace" directive on indoor apartments → wall modification |
| Bali Sanctuary | **HIGH** | "open side to garden/pool" + "open shower" architectural directives |
| Soft Luxury | **MEDIUM** | "symmetry" mandate vs asymmetric apartments |
| Nature Retreat | **MEDIUM** | "single statement stone/timber wall" could lead to material change |
| Others | LOW | mostly atmosphere/material discipline, not architectural |

### Furnishing-edit risk (creative mode primary)

| Atm | Risk score | Cause |
|---|---|---|
| Japandi Calm | **HIGH if forced** | Furnishing-richness directly conflicts with sparse Japandi identity |
| Zen Retreat | **CRITICAL if forced** | Atmosphere IS anti-furnishing — any edit breaks identity |
| Nature Retreat | **MEDIUM** | Plant + stone identity could compete with rich furnishing |
| Bali Sanctuary | **MEDIUM** | Pavilion + spiritual aesthetic could resist Western furnishing |
| Warm Modern / Soft Luxury / Dark Contemporary / Nordic / Desert / Tropical | LOW | Identity tolerates richer furnishing |

---

## 12. Suggested benchmark strategy

Per Wave 5.5.23 protocol :

### Wave 5.5.25 (preserve-safety) bench

- **Tier :** Standard (3 atmospheres × 1 photo × preserve × 3 cells = 9 cells)
- **Atmospheres :** Tropical Escape, Bali Sanctuary, Soft Luxury (the 3 with detected preserve risks)
- **Photo :** `primary_living_room.jpg`
- **Pass criteria :** 0/9 wall invention + 0/9 architectural modification (no opened sides where none existed)
- **Fail action :** revert immediately

### Wave 5.5.26 (decor decongestion) bench

- **Tier :** Standard
- **Atmospheres :** Soft Luxury, Dark Contemporary, Warm Modern (control)
- **Mode :** creative (TV appearance test)
- **Pass criteria :** TV appears in ≥4/9 cells, 0/9 media wall, 0/9 wall invention
- **Compare against pre-Wave-5.5.26 creative renders** of same atmosphere×photo

### Wave 5.5.27 (mirror) bench

- **Tier :** Smoke (1 atm × 3 cells)
- **Atmosphere :** Soft Luxury bathroom
- **Pass criteria :** mirror appears + no wall change

### Wave 5.5.28 (rug) bench

- **Tier :** Standard creative
- **Atmospheres :** Warm Modern, Soft Luxury, Dark Contemporary
- **Pass criteria :** rug appears in ≥6/9 cells, 0/9 wall invention, 0/9 floor pattern change

### Wave 5.5.29 (density) bench

- **Tier :** Smoke
- **Atmospheres :** Desert + Bali (1 cell each)

### Long-term : ship gate on all 4 atmospheres

After Wave 5.5.25-29 ship, run full ship-gate bench (10 atms × 3 photos × 2 modes × 3 cells = 180 cells) to confirm no atmosphere regression.

---

## 13. Hidden traps detected

1. **`apply_bimodal` does NOT strip decor_language / room_specific_constraints** — preserve mode receives the full DNA decor + constraints. My fix #2 above (move vessel to floor) DOES affect preserve mode. Need preserve bench gate.

2. **`inject_creative_revival` ALSO emits `room_specific_constraints`** in creative mode (Wave 5.5.14d). So a constraint edit fires TWICE in creative mode (once via build_dna_block, once via inject_creative_revival). Already documented in Wave 5.5.17a audit. Not a blocker but a redundancy to know.

3. **`negative_rules` are emitted in `build_dna_block` AVOID section on BOTH modes.** So adding a negative_rule like "no visible TV above fireplace" affects preserve too. Already cleaned for Soft Luxury Wave 5.5.22.

4. **The new geometry_attached_furnishing signal (Wave 5.5.19+22) lists TV as `"a television on existing wall geometry"`.** If we edit DNA to ALSO push for TV, the signal density compounds. Watch for over-pressure on tight atmospheres.

5. **`visible_transition_logic` is emitted via Wave 5.5.18 dna_room_context** — this can include kitchen continuity references. Editing visible_transition_logic affects both modes via dna_room_context signal. Don't add architectural directives there.

6. **The byte-exact validator (validate_byteexact_5515b.py) becomes harder to interpret post-multi-wave** — it compares baseline (Wave-5.5.15b state) vs current. DNA edits drift the baseline more each wave. Consider deprecating in favor of prompt_diff.py.

---

## 14. Mandatory before any Wave 5.5.25+

Per Wave 5.5.23 protocol :

1. Copy `docs/WAVE_PLANNING_TEMPLATE.md` to `docs/WAVE_5_5_X_PLAN.md` for each sub-wave
2. Run `python tools/prompt_diff.py --before HEAD` before each bench
3. Append observed lessons to `docs/VOCABULARY_LESSONS.md` after each bench
4. Use the locked `tests/golden_inputs/*.jpg` for all benches

---

## 15. Bottom-line recommendation

**Ship Wave 5.5.25 (preserve-safety) first.** The Tropical + Bali "open side" directives are the biggest unmitigated architectural drift risk in the entire DNA. Fixing them is pure win — no atmosphere identity harm + significant preserve safety improvement.

**Then assess Wave 5.5.26-28 based on user priorities.** TV / rug / mirror gaps are real but quality-of-life improvements, not safety fixes.

**Leave Japandi / Zen / Nature bedroom alone.** Their anti-furnishing constraints are atmosphere identity, not bugs.

**Expected total work for Waves 5.5.25-29 :** ~3-4h code + ~30 cells of bench (mix of smoke + standard).
