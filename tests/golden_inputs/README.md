# Golden Benchmark Inputs

**Wave 5.5.23 — Validation Infrastructure**

This directory holds the **fixed reference photos** used for ALL bench protocols going forward. Locking the input photos eliminates a major source of variance between waves and makes drift detection reliable.

## Purpose

Before Wave 5.5.23, each bench used whatever apartment photo was convenient at the time. This made A/B comparison across waves noisy — was the regression caused by the wave change or by the new photo's quirks?

Locking 3 reference photos solves this:
- A/B comparisons are apples-to-apples
- "Did Wave X cause regression Y?" becomes answerable
- Bench artifacts (rendered outputs) accumulate per-photo over time → visible drift history

## The 3 reference photos

Place these 3 JPEG/PNG files in this directory:

### 1. `primary_living_room.jpg`
The standard test apartment used for most benches in Wave 5.5.14+. Living room with:
- Wide floor-to-ceiling window dominating the rear/left wall
- Open kitchen visible on the left through a glass partition
- Sofa + coffee table in the foreground

This is the *baseline* — most regression bugs surface here first.

### 2. `difficult_asymmetric_room.jpg`
A room with intentionally asymmetric architecture:
- Non-rectangular floor plan, or
- Multiple ceiling heights, or
- Sloped wall / pitched ceiling, or
- Window placement that breaks visual symmetry

Tests the "symmetry cleanup" failure mode where the model normalizes irregular geometry.

### 3. `kitchen_continuity_room.jpg`
A room where kitchen visibility through an opening is the load-bearing test signal:
- Living room with kitchen visible through doorway/partition/half-wall
- Kitchen elements (counter, appliances, cabinets) clearly visible in the rear

Tests the "kitchen suppression" failure mode (Wave 5.5.10c, Wave 5.5.16 preserve regression).

## How to add the photos

```powershell
# From the user's photo library, copy 3 JPEG/PNG files
Copy-Item C:\path\to\your\living_room.jpg tests\golden_inputs\primary_living_room.jpg
Copy-Item C:\path\to\your\asymmetric_room.jpg tests\golden_inputs\difficult_asymmetric_room.jpg
Copy-Item C:\path\to\your\kitchen_view.jpg tests\golden_inputs\kitchen_continuity_room.jpg
```

Commit them to the repo (they are small JPEGs, well within Git limits).

## Bench protocol per photo

Each wave bench should run **3 generations per (photo × atmosphere × mode) cell**.

Minimum smoke test : `primary_living_room.jpg × 1 atm × 1 mode × 3 cells = 3 generations`.
Standard bench : `primary_living_room.jpg × 3 atms × 1 mode × 3 cells = 9 generations`.
Ship gate : all 3 photos × 10 atms × 2 modes × 3 cells = 180 generations.

**NEVER bench with n=1** — single-image results are statistical noise.

## Artifacts directory

Rendered bench outputs should be saved in `tests/golden_outputs/<wave_id>/<photo>_<atm>_<mode>_<cell>.png` so future waves can A/B-compare against past waves visually.

## Why locked photos matter

Empirical evidence from Wave 5.5.15→22 chain :
- Wave 5.5.15c bench used Warm Modern + Japandi + Nordic on photo A → results X
- Wave 5.5.16 bench used same atmospheres on photo B → results Y
- Was the difference caused by the wave change OR the photo difference ? **Unknown.**

With locked photos : the variable is isolated to the wave change. Bench outcomes become decision-grade.
