# Wave Planning Template

**Wave 5.5.23 — validation infrastructure.**

Before starting code on ANY new wave, copy this template into a wave-specific planning doc (e.g. `docs/WAVE_5_5_24_PLAN.md`) and fill it in. ~15 minutes. Forces clarity, prevents the "code now, think later" trap.

---

# Wave X.Y.Z — <Theme>

**Date :** YYYY-MM-DD
**Lead :** <user>
**Branch :** wave-X.Y.Z-<slug>

## 1. Hypothesis

What do we believe will improve and why ? Be specific.

> Example : "Adding 'a television on existing wall geometry' to the creative
> furnishing signal will produce visible TVs in living room renders for at
> least 50% of cells, without triggering wall invention because the geometry
> anchor pins TV to existing walls."

## 2. Expected outcome (quantified)

What does success look like in numbers ?

> Example :
> - TV appearance rate ≥ 5/9 on Warm Modern + Soft Luxury + Nordic Warmth creative
> - 0/9 wall invention across all 9 cells
> - 0/9 media wall invention
> - Other furniture (sofa, coffee table, lamps) remains correct

## 3. Decision rule

What thresholds trigger ship / iterate / rollback ?

> Example :
> - Ship : TV ≥ 5/9 AND wall invention = 0/9
> - Iterate : TV 2-4/9 AND wall invention = 0/9 (try further wording trim)
> - Rollback : wall invention ≥ 1/9 OR TV = 0/9

## 4. Bench tier

Per Wave 5.5.23 protocol, choose ONE :

- [ ] **Smoke test** : 1 atm × 1 photo × 1 mode × 3 cells (~$0.30, ~3 min)
- [ ] **Standard bench** : 3 atms × 1 photo × 1 mode × 3 cells (~$1, ~10 min)
- [ ] **Ship gate** : 10 atms × 3 photos × 2 modes × 3 cells (~$30, ~3 hours)

Rule : start at the lowest meaningful tier. Escalate only if it passes.

## 5. Prompt diff inspector — pre-bench review

Before bench, run :

```powershell
python tools/prompt_diff.py --before HEAD~1
```

Paste the relevant additions / suppressions here :

> Example :
> - **Nouns added** : `television` (1 instance, geometry-anchored)
> - **Nouns removed** : `oversized ceramic vessel`
> - **Spatial adjectives added** : (none)
> - **Focal semantics added** : `fireplace, artwork, or a television`
> - **Continuity semantics added** : (none)
> - **Negations removed** : `"not TV-facing row"`, `"no visible TV above fireplace"`

Cross-reference each token against `docs/VOCABULARY_LESSONS.md`. Flag any UNTESTED tokens for extra scrutiny in bench.

## 6. Risk acknowledgement

What could go wrong that we know about ?

> Example :
> - "geometry-attached" wording was 2-3/10 walls in Wave 5.5.16 preserve. We are creative-only here so should be OK
> - DNA edit on warm_modern is the first time we modify atmospheric DNA — could affect other rooms (mitigated : edit scoped to living_room only)

## 7. Rollback plan

How do we revert if bench fails ?

> Example :
> 1. `git revert HEAD` (single commit) → instant rollback to pre-wave state
> 2. OR : set `_FURNISHING_CREATIVE_BY_ROOM["living_room"]` to previous wording
> 3. OR : `unset BIMODAL_ENABLED` (production-wide kill switch)

## 8. Post-bench update

After bench :

- Update this doc with actual outcome vs expected
- Append observed lessons to `docs/VOCABULARY_LESSONS.md`
- Update todo : ship / iterate / rollback
- Commit with concise message referencing this plan

---

## Why fill this in BEFORE coding ?

- Forces hypothesis articulation (catches "I don't actually know what I'm trying to prove" early)
- Decision rule prevents goal-shifting after results arrive
- Bench tier selection prevents over-spending on low-value changes
- Diff inspector pre-review surfaces unintended suppressions
- Rollback plan ensures safety net is ready before risk is taken

## Why this is not a gate

This template is a discipline aid, not a permission system. You can skip it for trivial changes (typo fixes, doc updates, comment edits) — but for any prompt-engine code or DNA edit, fill it in. ~15 min investment saves hours of "why did this regress ?" debugging later.
