# Roadmap v2 — Framework Integration

**Date :** 2026-05-25
**Type :** roadmap re-evaluation (no code changes)
**Trigger :** User locked the [FURNISHING_FRAMEWORK.md](FURNISHING_FRAMEWORK.md) 2026-05-25. All planned waves (5.5.26+) must align with the framework before implementation.
**Scope :** Re-evaluates the 4 remaining sub-waves proposed by Wave 5.5.24 audit (5.5.26, 5.5.27, 5.5.28, 5.5.29).

---

## 1. Updated roadmap

| Wave | Theme | Status | Framework alignment |
|---|---|---|---|
| **5.5.25** | Preserve-safety fixes (Tropical/Bali "open side" + Soft Luxury symmetry) | ✓ **SHIPPED** (commit b2a26de) | Preservation Rules (removed architectural directives that violated preservation) |
| **5.5.26** | Decor decongestion (Soft Luxury vessel + Dark Contemporary artwork) | 🟢 **READY** (re-validated against framework) | Placement Rules (TV needs free wall, decor was blocking) |
| **5.5.27** | Essentials gap fill — bathroom mirrors + living/bedroom rugs **MERGED FROM 5.5.27+5.5.28** | 🟢 **READY** (re-validated, merged) | Room Essentials (mirror + rug are essentials currently missing from DNA) |
| **5.5.28** | (merged into 5.5.27) | — | — |
| **5.5.29** | Density tunings (Desert + Bali "max 2 objects" → "3-4 considered") | 🟡 **OPTIONAL POLISH** (lower priority) | Room Essentials (slight headroom for decor enrichments) |

**No wave is paused or cancelled.** The framework re-evaluation confirms all 4 remaining sub-waves are legitimately framework-aligned.

---

## 2. Mapping table — waves vs framework dimensions

| Wave | Room Essentials | Furnishing Behaviors | Placement Rules | Fallback Logic | Preservation Rules |
|---|---|---|---|---|---|
| 5.5.25 (shipped) | — | — | — | — | ✓ **STRONG** — softened architectural directives to conditionals (Tropical / Bali open-side, Soft Luxury symmetry) |
| 5.5.26 (decor decongestion) | ✓ TV slot freed | ✓ TV aligns with seating | ✓ Decor moves from wall focal to floor | ✓ Vessel/artwork still present at floor if no wall TV | ✓ No preservation change |
| 5.5.27 (essentials gap fill) | ✓ **PRIMARY** — adds mirror (5 bathrooms) + rug (7 living + 7 bedroom) | ✓ Mirror above vanity ; rug anchors seating/bed | ✓ Anchored to existing vanity / seating footprint / bed | ✓ If no vanity / seating, no mirror / rug | ✓ No preservation change |
| 5.5.29 (density tunings) | ✓ Slight more decor allowance | — | — | — | ✓ No preservation change |

---

## 3. Risk analysis per wave

### Wave 5.5.26 — Decor decongestion

| Risk | Assessment |
|---|---|
| Wall invention | LOW — vessel/artwork move to floor, not removed from atmosphere identity |
| Atmosphere identity drift | LOW — Soft Luxury still has cushions/silk/marble ; Dark Contemporary still has dark sculptural decor |
| Char budget | NEUTRAL — vessel relocation is +5/-5 chars at most |
| Bench requirement | Standard creative bench (3 atms × 3 cells) — focus TV appearance rate post-change |

### Wave 5.5.27 — Essentials gap fill (merged rugs + mirrors)

| Risk | Assessment |
|---|---|
| Wall invention | LOW for rugs (floor element) ; LOW for mirrors if anchored to existing vanity |
| Mirror invention without vanity | LOW — DNA wording will say "above existing vanity" |
| Rug pattern conflicting with atmosphere | LOW — wording specifies neutral palette per atmosphere |
| Char budget | +50-100 chars per atmosphere ; tight atmospheres (Tropical creative +21) will drop dna_room_context first |
| Bench requirement | Standard creative bench (3 atms × 3 cells) for rugs ; smoke test for mirrors |

### Wave 5.5.29 — Density tunings

| Risk | Assessment |
|---|---|
| Atmosphere identity drift | LOW — Desert/Bali stay "considered" restrained |
| Furnishing pressure | LOW — slight relaxation, not removal of density limit |
| Char budget | NEUTRAL — replace 1 word, no length change |
| Bench requirement | Smoke test only (1 atm × 3 cells per atmosphere) |

### What's NOT planned (deliberately out of scope)

| Topic | Why not |
|---|---|
| Japandi / Zen essentials richer | Atmosphere identity = spareness ; adding rugs/TVs violates atmosphere character (anti-pillar) |
| Nature Retreat bedroom TV | "no technology visible" is biophilic identity (anti-pillar) |
| `"open shelf mandatory"` Tropical/Bali kitchen | Low-priority cosmetic ; doesn't affect essentials |
| Fully revisit all 130 DNA cells | Excessive scope ; 50 essential cells already audited Wave 5.5.24 |

---

## 4. Which waves should proceed

**Ready to proceed (in this order) :**

1. **Wave 5.5.26 — Decor decongestion** (2 edits, 30 min code, standard bench)
   - Fixes Soft Luxury / Dark Contemporary residual blockers from Wave 5.5.22 that didn't fully unblock TV
   - Highest leverage : completes the Wave 5.5.21+22 TV-unblock work

2. **Wave 5.5.27 — Essentials gap fill (merged rugs + mirrors)** (~12 edits, 1h code, standard bench)
   - Closes the most-systematic essentials gap (rug missing in 7/10 atmospheres, mirror missing in 5/10 bathrooms)
   - Largest scope ; biggest user-visible improvement

3. **Wave 5.5.29 — Density tunings** (2 edits, 15 min code, smoke test)
   - Marginal polish ; ship only if 5.5.26+5.5.27 benches succeed
   - Skip if user prioritizes other waves

---

## 5. Which waves should pause

**None.** Framework re-evaluation confirms all 4 remaining sub-waves are legitimate.

---

## 6. Which waves should merge

**Wave 5.5.27 + 5.5.28 → MERGED as Wave 5.5.27 "Essentials gap fill".**

Rationale :
- Both fill essentials gaps (rug for living/bedroom, mirror for bathroom)
- Same root cause (DNA never had them)
- Same risk profile (LOW)
- Same Wave 5.5.23 protocol (standard bench)
- Merging reduces ceremony : 1 plan doc, 1 bench, 1 commit vs 2 of each

Total scope merged Wave 5.5.27 : 5 bathroom mirrors + 7 living rugs + 7 bedroom rugs = **19 DNA edits**. Still manageable.

---

## 7. Which waves should split

**Wave 5.5.27 — possible phased split** (optional, recommended if user wants more bench data) :

- **Wave 5.5.27a** : Living room rugs (7 atmospheres, 7 edits) — most tested room type
- **Wave 5.5.27b** : Bathroom mirrors (5 atmospheres, 5 edits) — less benched
- **Wave 5.5.27c** : Bedroom rugs (7 atmospheres, 7 edits) — least benched

Justification : if Wave 5.5.27a bench reveals rug-related drift, we catch it before applying same pattern to bathroom/bedroom.

**Decision** : ship as single Wave 5.5.27 unless user prefers phased.

---

## 8. New recommended implementation order

```
[ALREADY DONE]
└── Wave 5.5.25 — Preserve-safety (commit b2a26de)
    └── Bench preserve : Tropical + Bali + Soft Luxury (user pending)
        ├── If 0/9 walls : proceed
        └── If ≥1 wall : revert + diagnose

[NEXT]
├── Wave 5.5.26 — Decor decongestion (estimated 1h total)
│   ├── 2 DNA edits : soft_luxury.py vessel + dark_contemporary.py artwork
│   ├── Bench creative : Soft Luxury + Dark Contemporary + Warm Modern (control)
│   │   └── Focus : TV appearance rate
│   └── Pass → ship
│
├── Wave 5.5.27 — Essentials gap fill (estimated 2h total)
│   ├── 19 DNA edits : 5 bathroom mirrors + 7 living rugs + 7 bedroom rugs
│   ├── Bench creative : 3 atms × 3 cells (rug appearance + 0 preservation violations)
│   └── Pass → ship
│
└── Wave 5.5.29 — Density tunings (estimated 30 min total) [OPTIONAL]
    ├── 2 DNA edits : Desert + Bali density limit relaxation
    ├── Bench smoke : 1 atm × 3 cells each
    └── Pass → ship
```

**Total estimated work :** ~3-4h code + ~30 cells of bench (~$3-4 OpenAI cost) for the entire remaining roadmap.

---

## 9. Impact on preserve mode

| Wave | Preserve mode impact |
|---|---|
| 5.5.25 (shipped) | ✓ **POSITIVE** — directly fixes preserve-mode architectural drift risk |
| 5.5.26 (decor decongestion) | ✓ NEUTRAL — decor changes affect both modes equally ; preserve safety improves slightly (less wall-occupying decor → less conflict) |
| 5.5.27 (rugs + mirrors) | ⚠️ **MIXED** — rugs at floor level = LOW risk ; mirrors above vanity = LOW risk if anchored. **Requires preserve bench gate** |
| 5.5.29 (density) | ✓ NEUTRAL — density limit relaxation doesn't change preservation |

**Critical :** Wave 5.5.27 MUST include preserve-mode bench, not just creative. Mirrors are a new noun in preserve-mode prompts ; per Wave 5.5.15→22 history, new nouns in preserve are HIGH RISK until proven safe.

---

## 10. Suggested benchmark strategy per wave

### Wave 5.5.26 — Decor decongestion

- **Tier :** Standard (3 atms × 1 photo × creative × 3 cells = 9 cells)
- **Atmospheres :** Soft Luxury, Dark Contemporary (the 2 fixed) + Warm Modern (control, already-fixed Wave 5.5.21)
- **Photo :** `tests/golden_inputs/primary_living_room.jpg`
- **Pass criteria :**
  - TV appears in ≥5/9 cells (improvement vs pre-Wave-5.5.26 rate)
  - 0/9 wall invention
  - 0/9 media wall invention
  - Vessel/artwork still present in cell (atmosphere identity OK) — at floor level not wall
- **Compare against :** Wave 5.5.22 bench (last known TV appearance rate)

### Wave 5.5.27 — Essentials gap fill

- **Tier :** Standard creative + Smoke preserve
- **Atmospheres :**
  - Creative bench : 3 atms × 3 cells (Warm Modern + Soft Luxury + Dark Contemporary living + bathroom + bedroom = 27 cells)
  - **Preserve smoke for MIRRORS specifically — MANDATORY NO EXCEPTIONS (user-locked 2026-05-25)** : 3 atms × 3 cells bathroom preserve = 9 cells
  - Preserve smoke for rugs : 2 atms × 3 cells living preserve = 6 cells
- **Photo :** `tests/golden_inputs/primary_living_room.jpg` for living/bedroom ; need photos for bathroom (could use existing if applicable)
- **Pass criteria :**
  - Rug appears in ≥6/9 living + ≥4/9 bedroom cells (improvement)
  - Mirror appears in ≥2/3 bathroom cells (improvement)
  - **0 wall invention (preserve mode critical — IMMEDIATE ROLLBACK if any)**
  - **0 fake depth / fake opening from mirrors (mirror-specific watch)**
  - 0 floor pattern change (rugs ANCHOR, don't recompose)

**MIRROR SPECIAL DISCIPLINE :** Per user lock 2026-05-25 + VOCABULARY_LESSONS.md, mirrors are MEDIUM/HIGH preserve-risk. The bathroom preserve smoke bench is MANDATORY before ship. Even if creative bench passes, preserve must pass independently. NO EXCEPTIONS.

**Phased split recommended for mirror rollout :**
1. First : rugs only (living + bedroom) — proven safer pattern
2. Bench rugs → if 0 preserve violation, proceed
3. Then : mirrors (bathrooms) — separate sub-wave with dedicated preserve bench
4. If mirror bench shows ANY depth/opening simulation → IMMEDIATE ROLLBACK, no debate

### Wave 5.5.29 — Density tunings

- **Tier :** Smoke (1 atm × 3 cells each = 6 cells)
- **Atmospheres :** Desert Luxe + Bali Sanctuary, creative mode
- **Pass criteria :** decor variety increases slightly (subjective) ; 0/6 preservation violation

---

## Framework alignment summary

**All 4 remaining sub-waves pass framework alignment :**

| Wave | Essentials | Behaviors | Placement | Fallback | Preservation |
|---|---|---|---|---|---|
| 5.5.26 | ✓ | ✓ | ✓ | ✓ | ✓ |
| 5.5.27 | ✓ | ✓ | ✓ | ✓ | ✓ (with bench gate) |
| 5.5.29 | ✓ | ✓ | ✓ | ✓ | ✓ |

No wave needs redesign. Framework re-evaluation = confirms the audit recommendations.

---

## Recommendation

**Proceed in order : 5.5.25 bench validate → 5.5.26 ship+bench → 5.5.27 ship+bench → 5.5.29 ship (optional).**

Each wave gets its own plan doc (per [WAVE_PLANNING_TEMPLATE.md](WAVE_PLANNING_TEMPLATE.md)) with the framework alignment section filled in.

Total estimated remaining work : **~3-4h code + ~30-40 bench cells**.

After Wave 5.5.29 (or earlier if user satisfied) : evaluate whether prompt engineering ceiling has been reached. If yes → planning starts for Wave 6.0 (Path C hybrid, per Wave 5.5.17b competitor audit).
