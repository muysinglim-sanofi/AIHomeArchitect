# Wave 5.5.25 — Preserve-Safety DNA Edits

**Date :** 2026-05-25
**Lead :** muysi
**Branch :** wave-5.5.23-validation-infra (will merge to wave-4.9.3 after bench validation)

## 1. Hypothesis

Removing 3 architectural directives from DNA (Tropical + Bali "open side to terrace/garden/pool" + Bali "open shower") and 1 composition mandate (Soft Luxury "symmetry") will eliminate the biggest unmitigated preserve-mode architectural drift risks identified by Wave 5.5.24 audit (Section 8). No atmosphere identity harm expected because edits only soften mandates to conditionals.

## 2. Expected outcome (quantified)

- **0/9 wall invention** on preserve bench across Tropical Escape + Bali Sanctuary + Soft Luxury living_room
- **0/N architectural opening invention** (no new windows / openings / removed walls where none existed in source photo)
- Tropical / Bali atmosphere identity preserved : visually still tropical / Balinese
- Soft Luxury still reads as luxurious (symmetry mandate softening should not undo hospitality character)
- Visible benefit : on apartments WITHOUT terrace, model no longer adds openings to non-existent ones

## 3. Decision rule

- **Ship :** 0/9 wall invention AND atmosphere identity preserved subjectively
- **Iterate :** 1/9 wall invention OR identity drift on 1 atmosphere → trim further
- **Rollback :** ≥2/9 wall invention OR identity loss on ≥2 atmospheres

## 4. Bench tier

- [ ] Smoke test (1 atm × 3 cells)
- [x] **Standard bench** : 3 atms × 1 photo × preserve × 3 cells = 9 cells (~$1, ~10 min)
- [ ] Ship gate (full 10 atms)

Justification : these are preserve-safety fixes, so preserve-only bench. 3 atms = the 3 affected. Same photo (primary_living_room.jpg) for consistency. Creative mode unaffected by these edits since constraints are room_specific (apply to both modes).

## 5. Prompt diff inspector — pre-bench review

To be filled in after edits + tool run.

## 6. Risk acknowledgement

Known risks :

1. **DNA edits affect BOTH preserve and creative modes** (room_specific_constraints not stripped by apply_bimodal). Per Wave 5.5.24 audit Section 13 trap #1. → If creative mode shows TV-appearance regression or atmosphere identity drift, that's a side effect.

2. **Tropical/Bali identity is partially defined by "pavilion" architecture.** Softening from mandate to conditional could weaken atmosphere recognizability on indoor apartments. Acceptable trade-off if preserve safety improves.

3. **Soft Luxury symmetry was a stylistic choice.** Dropping might make Soft Luxury feel less "designed". Acceptable if architecture preserved.

## 7. Rollback plan

1. Single commit per sub-wave → `git revert HEAD` restores prior state instantly
2. Each DNA edit is in a separate atmosphere file → can revert one file selectively
3. `unset BIMODAL_ENABLED` is the always-available kill switch

## 8. Post-bench update

To be filled in after bench.

---

## Specific edits planned (5 total)

### Edit 1 — Tropical Escape living_room
```python
# Before
room_specific_constraints=[
    "open side to terrace or garden — tropical villa character",  # ← architectural directive
    "plant as living room's primary accent — one large specimen",
]

# After (only first item changed)
room_specific_constraints=[
    "where the photographed apartment shows an open side to terrace or garden, preserve and emphasize that opening",  # ← conditional
    "plant as living room's primary accent — one large specimen",
]
```

### Edit 2 — Tropical Escape bathroom
```python
# Before
room_specific_constraints=[
    "white or near-white throughout — light and airy",
    "open or semi-open if villa allows",  # ← architectural directive
]

# After (only second item changed)
room_specific_constraints=[
    "white or near-white throughout — light and airy",
    "if the photographed bathroom is open-villa style, preserve openness",  # ← conditional
]
```

### Edit 3 — Bali Sanctuary living_room
```python
# Before
room_specific_constraints=[
    "open side to garden or pool — pavilion character",  # ← architectural directive
    "maximum 2 decorative objects plus one plant",
]

# After (only first item changed)
room_specific_constraints=[
    "where the photographed apartment shows an open side to garden or pool, preserve and emphasize that connection",  # ← conditional
    "maximum 2 decorative objects plus one plant",
]
```

### Edit 4 — Bali Sanctuary bathroom
```python
# Before
room_specific_constraints=[
    "open or semi-open shower — no full enclosure in pavilion bathroom",  # ← architectural directive
    "all fixtures in aged brass — single finish",
]

# After (only first item changed)
room_specific_constraints=[
    "if the photographed bathroom is open-pavilion style, preserve the open shower ; otherwise respect the existing enclosure",  # ← conditional
    "all fixtures in aged brass — single finish",
]
```

### Edit 5 — Soft Luxury living_room
```python
# Before (already partially fixed Wave 5.5.22)
room_specific_constraints=[
    "seating centred on focal element — fireplace, art wall, or a television",
    "symmetry in furniture placement — not haphazard",  # ← composition mandate
]

# After (only second item changed)
room_specific_constraints=[
    "seating centred on focal element — fireplace, art wall, or a television",
    "considered furniture placement that respects the photographed layout",  # ← respect-preserve
]
```
