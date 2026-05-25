# Wave 5.5.26 — Decor Decongestion

**Date :** 2026-05-25
**Lead :** muysi
**Branch :** wave-5.5.23-validation-infra

## 1. Hypothesis

Replacing wall-competing decor items in Soft Luxury and Dark Contemporary living_room DNA will free the wall focal area for TV placement. This addresses the residual TV-appearance gap left by Wave 5.5.22 even though room_specific_constraints already permit TV.

## 2. Expected outcome (quantified)

- TV appearance rate increases in creative bench (vs Wave 5.5.22 baseline) on Soft Luxury + Dark Contemporary living_room
- 0/N wall invention (per locked discipline)
- 0/N media wall invention
- Atmosphere identity preserved (Soft Luxury still hospitality + Dark Contemporary still moody)

## 3. Decision rule

- **Ship :** TV appearance ≥ 4/9 cells AND 0/9 wall invention AND 0/9 preserve regression
- **Iterate :** TV unchanged but 0/N regression → try alternative decor wording
- **Rollback :** ANY preserve regression OR ≥1 wall invention → revert immediately, no debate

## 4. Bench tier

- [x] **Standard creative** : 3 atms × 1 photo × creative × 3 cells = 9 cells (~$1, ~10 min)
- [x] **Smoke preserve** : Soft Luxury preserve × 3 cells = 3 cells (~$0.30, ~3 min)

Total : 12 cells.

Justification : Wave 5.5.25 rollback proved that even seemingly-safe DNA edits can cause preserve regression. Smoke preserve on Soft Luxury (the higher-risk of the two — vessel relocation) is mandatory. Dark Contemporary preserve not bench-required because the artwork-removal pattern is removal-of-noun, not constraint-change — historically safer pattern.

## 5. Framework alignment

1. **Room Essentials addressed :** TV is a living_room essential. Wall focal must be free for TV placement. Decor congestion was blocking it.
2. **Furnishing Behaviors respected :** "television naturally aligns with seating arrangement" + "if no suitable wall exists, allow low TV console" — decor decongestion enables the ideal placement (wall-mounted)
3. **Placement Rules respected :** decor moved to floor-level / sofa-level anchoring (vessel near sofa, throw on sofa) — still attached to existing geometry, never to invented surfaces
4. **Fallback Logic :** vessel/throw still present in atmosphere even if model can't ideal-place them. No essential removed
5. **Preservation Rules untouched :** edits are within decor_language only. No change to room_specific_constraints, negative_rules, or architectural fields

## 6. Risk acknowledgement

Known risks (informed by Wave 5.5.25 rollback) :

1. **DNA edits affect preserve mode too** — decor_language is emitted in build_dna_block (both modes). The Soft Luxury vessel change goes into preserve prompts as well. Mandatory preserve smoke bench.
2. **Removing artwork from Dark Contemporary decor might subtly weaken atmosphere identity** — moody character partially relies on dark large-scale art. Mitigation : replace with dark velvet throw instead of pure removal.
3. **"Floor-level" wording might be interpreted weirdly by gpt-image-1** — could lead to vessel on floor (good) or vessel artificially sized down (acceptable).

## 7. Rollback plan

Single commit → `git revert HEAD` instant. Per locked discipline : ANY preserve regression = immediate rollback, no debate.

If only 1 atmosphere regresses (e.g. Soft Luxury OK + Dark Contemporary KO), surgical revert : `git checkout HEAD~1 -- backend/prompt_engine/atmosphere_dna/<file>.py` per atmosphere.

## 8. Post-bench update

To be filled after bench.

---

## Specific edits planned (2 total)

### Edit 1 — Soft Luxury living_room
```python
# Before
decor_language=[
    "oversized ceramic vessel with dried pampas or lunaria",  # ← "oversized" implies wall-shelf / focal placement
    "layered silk and bouclé cushions in cream and blush"
]

# After
decor_language=[
    "floor-level ceramic vessel with dried pampas or lunaria",  # ← floor-anchored, no wall competition
    "layered silk and bouclé cushions in cream and blush"
]
```

### Edit 2 — Dark Contemporary living_room
```python
# Before
decor_language=[
    "large-scale abstract artwork in dark or muted tones",  # ← occupies wall focal, blocks TV
    "single sculptural ceramic vessel in dark or metallic finish"
]

# After (replace artwork with sofa-anchored throw, keep vessel)
decor_language=[
    "deep dark velvet throw layered on the sofa",  # ← sofa-anchored, no wall competition, preserves moody atmosphere
    "single sculptural ceramic vessel in dark or metallic finish"
]
```

**Rationale for not pure-removing artwork :** Wave 5.5.25 rollback showed that "removing something for safety" can lose protective discipline. Replacing artwork with another atmosphere-coherent decor (dark velvet throw) preserves Dark Contemporary identity while freeing wall focal.
