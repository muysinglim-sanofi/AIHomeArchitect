# Wave 5.5.27 — Essentials Gap Fill (Rugs + Mirrors)

**Date :** 2026-05-25
**Lead :** muysi
**Branch :** wave-5.5.23-validation-infra
**Predecessor :** Wave 5.5.26 (decor decongestion) PASS confirmed by user

## 1. Hypothesis

Adding rug and mirror essentials to atmospheres where they are missing from DNA will close the most-systematic essentials gaps identified by Wave 5.5.24 audit, improving inhabitation realism without triggering preservation regressions.

Mirrors are MEDIUM/HIGH preserve-risk (locked 2026-05-25) — phased rollout : rugs first (safer), mirrors second (separate preserve smoke bench MANDATORY).

## 2. Expected outcome (quantified)

- **Rug appearance rate ≥ 6/9** on bench cells (living room creative)
- **Mirror appearance rate ≥ 2/3** on bathroom creative cells
- **0/N wall invention** preserve mode (CRITICAL)
- **0/N fake depth / opening simulation from mirrors** (mirror-specific watch)
- Atmosphere identity preserved per atmosphere

## 3. Decision rule

Per locked discipline 2026-05-25 :
- **Ship phase :** essentials appear at target rate AND 0/N preservation violation
- **Iterate phase :** essentials appear at target but minor identity drift → trim wording
- **Rollback phase :** ANY preservation violation → immediate revert, no debate

## 4. Bench tier (phased)

### Phase 3a — Rugs (ship first, safer)
- [x] Standard creative : 3 atms × 1 photo × creative × 3 cells = 9 cells
- [x] Smoke preserve : 2 atms × 1 photo × preserve × 3 cells = 6 cells
- Atmospheres : Warm Modern + Soft Luxury + Dark Contemporary
- Total : 15 cells, ~$1.50, ~20 min

### Phase 3b — Mirrors (ship after rugs PASS)
- [x] Standard creative bathroom : 3 atms × 3 cells = 9 cells
- [x] **MANDATORY** Smoke preserve bathroom : 3 atms × 3 cells = 9 cells (NO EXCEPTIONS per discipline)
- Atmospheres : Soft Luxury + Nordic Warmth + Nature Retreat (cross-section of risks)
- Total : 18 cells, ~$1.80, ~25 min

Total Wave 5.5.27 : ~33 bench cells (~$3.30, ~45 min)

## 5. Framework alignment

1. **Room Essentials addressed :**
   - Rug : living + bedroom essential, missing from 6/10 atmospheres
   - Mirror : bathroom essential, missing from 7/10 atmospheres
2. **Furnishing Behaviors respected :**
   - Rug anchors seating footprint (living) / at bedside (bedroom)
   - Mirror anchors above existing vanity
3. **Placement Rules respected :** all additions anchored to existing geometry (seating / bed / vanity)
4. **Fallback Logic :** if no seating cluster / no bed / no vanity in source → essential skipped, no invention
5. **Preservation Rules untouched :** edits affect decor_language only, not constraints or architectural fields

## 6. Risk acknowledgement

1. **Mirrors are MEDIUM/HIGH preserve-risk** (user-locked 2026-05-25). Mandatory preserve smoke bench. NO EXCEPTIONS.
2. **Rugs at floor-level are LOW preserve-risk** but still affect both modes via decor_language emission.
3. **Phased rollout** : rugs first allows isolating any regression to one variable class.
4. **Wave 5.5.25 rollback discipline applies** : surgical revert per atmosphere if needed.

## 7. Rollback plan

Single commit per phase. `git revert HEAD` instant.

Per-atmosphere surgical revert : `git checkout HEAD~1 -- backend/prompt_engine/atmosphere_dna/<file>.py`.

---

## Phase 1 — DNA Audit Results

### RUGS — atmospheres needing addition

After scanning DNA furniture_language + decor_language across 7 candidate atmospheres × 2 rooms (living + bedroom) :

| Atm | Living room rug | Bedroom rug |
|---|---|---|
| warm_modern | ❌ ADD | ❌ ADD |
| soft_luxury | ❌ ADD (textile = upholstery not rug) | ❌ ADD |
| dark_contemporary | ❌ ADD (velvet = upholstery not rug) | ❌ ADD |
| nature_retreat | ⚠️ "jute organic textural depth" — clarify | ✓ already has "jute or wool textile — natural floor-level warmth" (SKIP) |
| desert_luxe | ❌ ADD (camel textile throw is on sofa not floor) | ❌ ADD |
| tropical_escape | ❌ ADD | ❌ ADD |
| bali_sanctuary | ✓ already has "handwoven textile — artisan floor-level warmth" (SKIP) | ✓ same pattern (SKIP) |
| nordic_warmth | ✓ already has rug permission + sheepskin | SKIP |
| japandi_calm | ⚠️ conditional permission only | SKIP (atmosphere identity) |
| zen_retreat | ❌ anti-rug philosophy | SKIP (atmosphere identity) |

**11 rug additions needed** (counted : 6 living + 5 bedroom = 11).

### MIRRORS — atmospheres needing addition

| Atm | Bathroom mirror | Vanity present (anchor) ? |
|---|---|---|
| soft_luxury | ❌ ADD | ✓ floating vanity in fluted ivory lacquer |
| dark_contemporary | ❌ ADD | ✓ floating dark stone vanity |
| nordic_warmth | ❌ ADD | ✓ white-painted timber vanity |
| nature_retreat | ❌ ADD | ✓ floating reclaimed timber vanity |
| desert_luxe | ❌ ADD | ✓ hammered brass basin on stone slab |
| bali_sanctuary | ❌ ADD | ✓ carved teak vanity |
| tropical_escape | ❌ ADD | ✓ simple timber vanity |
| warm_modern | ✓ already has "single warm-framed mirror in brass or oak" | SKIP |
| japandi_calm | ⚠️ minimal-spare (atmosphere identity) | SKIP |
| zen_retreat | ⚠️ "no mirror — or one small mirror only" (atmosphere identity) | SKIP |

**7 mirror additions needed** (revises Wave 5.5.24 audit which said 5 — Bali + Tropical also missing).

### Total edits

**18 edits** (11 rugs + 7 mirrors) across 7 unique atmosphere files.

---

## Phase 2 — Proposed Rewrites (FOR USER REVIEW)

### Rugs — 11 wordings (add to decor_language)

| Atm | Room | Proposed addition |
|---|---|---|
| warm_modern | living_room | `"soft wool rug in oat or camel within the seating footprint"` |
| warm_modern | master_bedroom | `"soft wool rug at the bedside in oat or camel"` |
| soft_luxury | living_room | `"plush silk-blend rug in cream or blush within the seating footprint"` |
| soft_luxury | master_bedroom | `"soft cashmere or wool rug at the bedside in cream or champagne"` |
| dark_contemporary | living_room | `"deep-pile rug in charcoal or dark tonal within the seating footprint"` |
| dark_contemporary | master_bedroom | `"deep-pile rug at the bedside in charcoal or dark tonal"` |
| nature_retreat | living_room | `"natural jute rug within the seating footprint"` (clarifies existing "jute textural depth") |
| desert_luxe | living_room | `"woven raw-cotton or camel-tone rug within the seating footprint"` |
| desert_luxe | master_bedroom | `"woven cotton rug at the bedside in sand tones"` |
| tropical_escape | living_room | `"natural jute or sisal rug within the seating footprint"` |
| tropical_escape | master_bedroom | `"simple jute or sisal rug at the bedside"` |

### Mirrors — 7 wordings (add to decor_language)

All anchored to existing vanity. Fallback : if no vanity in source photo → mirror naturally skipped by model.

| Atm | Proposed addition |
|---|---|
| soft_luxury | `"single mirror in brushed champagne brass frame above the floating vanity"` |
| dark_contemporary | `"single dark-framed mirror above the floating vanity"` |
| nordic_warmth | `"simple round mirror in matte nickel or pine frame above the white-painted vanity"` |
| nature_retreat | `"reclaimed timber-framed mirror above the floating vanity"` |
| desert_luxe | `"hammered brass-framed mirror above the basin"` |
| bali_sanctuary | `"carved teak-framed mirror above the carved teak vanity"` |
| tropical_escape | `"simple timber-framed mirror above the white-basin vanity"` |

### Wording principles applied

1. **Each rug anchored** to seating footprint (living) or bedside (bedroom)
2. **Each mirror anchored** to existing vanity (per atmosphere's existing vanity material)
3. **Materials per atmosphere identity** — wool/cashmere for warm hospitality, deep-pile/charcoal for moody, jute for natural, hammered brass for desert, carved teak for Bali, etc.
4. **Lean phrasing** (one item, anchor + material/color) — aligns with WM reference profile
5. **No spatial/composition mandates** — purely additive decor, model places where geometry allows
6. **Fallback implicit** — anchor wording ("above the floating vanity", "within the seating footprint") naturally fails-silent if anchor missing in source

### Char budget impact

| Atm | Total chars added | Impact |
|---|---|---|
| warm_modern | ~50 + 40 = 90 | Margin +123 → +33 LOW after |
| soft_luxury | ~55 + 50 + 60 (mirror) = 165 | Plenty of margin |
| dark_contemporary | ~55 + 50 + 50 = 155 | Plenty of margin |
| nordic_warmth | 80 (mirror only) | Plenty |
| nature_retreat | ~45 + 60 = 105 | OK |
| desert_luxe | ~55 + 50 + 50 = 155 | OK |
| tropical_escape | ~50 + 45 + 60 = 155 | Tight (creative +21 before, now +negative possibly — dna_room_context will drop first) |
| bali_sanctuary | 65 (mirror only) | OK |

**Tight atmospheres :** Tropical creative is the only one that risks signal drops. Acceptable trade-off (rug/mirror more important than dna_room_context on tight prompts).

---

## Phase 3a — Rugs ship + bench (after user approval of Phase 2)

To execute :
1. 11 DNA edits per Phase 2 wordings
2. Prompt diff inspector
3. Bimodal regression + margin check
4. Restart backend
5. User bench 15 cells (9 creative + 6 preserve smoke)
6. If PASS → proceed to Phase 3b. If FAIL → surgical revert per atmosphere

## Phase 3b — Mirrors ship + bench (after Phase 3a PASS)

To execute :
1. 7 DNA edits per Phase 2 wordings
2. Prompt diff inspector
3. Bimodal regression
4. Restart backend
5. User bench 18 cells (9 creative + 9 preserve mandatory)
6. **Mirror-specific watch :** fake depth, window-like reflection, perspective drift, opening invention
7. If ANY mirror-as-opening behavior → immediate rollback, no debate

---

## Awaiting user

**Review Phase 2 proposed wordings.** Adjust if needed. Then green-light Phase 3a (rugs ship).
