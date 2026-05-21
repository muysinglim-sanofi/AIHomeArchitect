# Structural Drift Measurement Protocol

**Goal**: measure how often gpt-image-1 preserves the architectural facts of your benchmark apartment across the 10 registered atmospheres, using V1 (FIRST_VISION) only.

**Why V1 only**: V1 = composer.py Path D, the same code path V2/V3 pure switches use via Wave 5.4a Edit A. So V1 drift is a clean proxy for "fresh atmosphere on original photo" drift across all REBOOT_FRESH cases.

**Why 2 runs per atmosphere**: gpt-image-1 is non-deterministic. Two samples per atmosphere distinguishes systematic drift (same feature drifts both runs) from stochastic drift (one drifts, one doesn't).

**Expected time**: ~5 min generation × 20 = ~100 min wall clock; ~20 min of YOUR attention (rest is OpenAI wait). Scoring: ~15 min.

---

## Setup (5 min)

1. Make sure the backend is restarted with the current code state (Wave 5.4a Edit A active, Edit B reverted).
2. Open Flutter app on emulator.
3. Upload your benchmark complex apartment photo.
4. Keep the source photo open in a second window so you can visually compare to each generated output.

## Generation procedure (~100 min, mostly waiting)

For each of the 10 atmospheres below, run **TWO V1 generations**:

1. Start a fresh session (back to home, new "New Design" project, upload the same photo)
2. Select the atmosphere → V1 is generated automatically
3. Screenshot the result (full image, not the chat thumbnail)
4. Save as `<atmosphere>_run<1|2>.png` in a folder
5. Back, new session, repeat for run 2

Atmospheres (in order):
1. Warm Modern
2. Japandi Calm
3. Soft Luxury
4. Zen Retreat
5. Nordic Warmth
6. Dark Contemporary
7. Nature Retreat
8. Desert Luxe
9. Bali Sanctuary
10. Tropical Escape

## Scoring (~15 min)

Open `STRUCTURAL_DRIFT_SCORECARD.md` (next file). For each generated image, mark each of the 9 features with one of:

- **2** = Preserved correctly (within ~5% of original)
- **1** = Partially preserved (recognizable but altered: rétréci, déplacé, déformé, partiellement masqué)
- **0** = Lost or fundamentally wrong (effaced, replaced, moved to a different wall)

## Feature definitions (with your benchmark apartment in mind)

| # | Feature | Pass criterion (= 2) | Partial (= 1) | Fail (= 0) |
|---|---|---|---|---|
| 1 | **Sliding door — presence + wall** | Floor-to-ceiling on LEFT wall | Present but height/position off | Not on left wall / not floor-to-ceiling |
| 2 | **Sliding door — width** | Full opening width preserved | Narrowed by 10-30% | Narrowed >30% or replaced by smaller window |
| 3 | **Glass partition — presence + frame** | Present on right, black-framed | Present but framing altered | Replaced by solid wall or gone |
| 4 | **Visible kitchen behind partition** | Dark cabinet edge visible on far right behind partition | Hint of kitchen but altered | Replaced by decorative shelf / wall / nothing |
| 5 | **Window in rear room** | Visible through partition | Hinted but altered | Erased or replaced |
| 6 | **Ceiling — diagonal on upper-left** | Diagonal slope preserved | Slightly aplati | Completely flat ceiling |
| 7 | **Floor pattern (herringbone direction)** | Herringbone direction preserved | Herringbone present, wrong direction | Different pattern entirely |
| 8 | **Vanishing point / perspective** | Same eye-level center perspective | Slight skew | Different camera angle |
| 9 | **Spatial depth (room volume)** | Room reads as deep + wide | Slightly compressed | Visibly smaller / cramped |

## Aggregation

Once the scorecard is filled, run:

```
python docs/structural_drift_aggregate.py
```

It reads the markdown scorecard and outputs:
- Preservation rate per feature (% of cases scored ≥ 1)
- Per-atmosphere drift composite
- Overall drift rate (mean of all features × cases)
- Systematic drift detection (features that drift in BOTH runs of an atmosphere)
- Stochastic drift detection (features that drift in only one of two runs)

## Decision matrix

Based on the aggregated **overall preservation score**:

| Score | Interpretation | Recommended next step |
|---|---|---|
| > 85% | High preservation already | Don't ship Option 1 — diminishing returns |
| 70-85% | Moderate preservation | Option 1 likely worth 3-4 days dev |
| 50-70% | Significant drift | Option 1 mandatory; consider Option 2 (GPU) for higher tiers |
| < 50% | Severe drift | Option 1 alone may not be sufficient; segmentation needed |

---

## Optional: a third run if you see surprising results

If the per-atmosphere composite varies wildly between run 1 and run 2 for some atmosphere, do a run 3 for that atmosphere. Three samples will tell you if it's systematic (consistent low score across 3) or stochastic (one outlier run).
