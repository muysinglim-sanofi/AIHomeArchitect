# Runtime Isolation Matrix — Wave 4.7.0

## Purpose

A scientific runtime-feature isolation test. After the 4.6.x waves made the prompt
architecture coherent (SAME APARTMENT PHOTO-EDIT, openings_anchor, material-only DNA),
several historical OpenAI/runtime features may now be unnecessary "band-aids" that
compensated for earlier prompt instability.

This matrix identifies which runtime features are **actually required** versus which
became historical assumptions, using **measurable evidence, not assumptions**.

> **Critical rule:** every runtime feature must justify its latency cost, retry cost,
> generation-stability cost, and visual benefit with measurable evidence.

## Methodology

- **One variable per step.** Each step changes exactly one runtime variable versus the
  previous validated step. All other variables stay identical.
- **Manual visual PROD validation gate.** After each step the user visually inspects
  fidelity, realism, premium feeling, atmosphere quality, and architecture preservation
  on real PROD generations. No next step begins until the user explicitly approves.
- **Prompt is frozen.** This wave is RUNTIME ISOLATION ONLY. Prompts, DNA philosophy,
  preservation philosophy, openings_anchor, and V1/V2/V3 structure are NOT modified in
  any step.
- **Profile-driven.** All isolation happens through `generation_profiles.py`. No
  scattered `APP_ENV` branching in `main.py`. Activate via `APP_ENV=mobile_mvp_baseline`.

## Variables under isolation

| Variable        | Historical (PROD) | Baseline (Step 1) | Controlled by                         |
|-----------------|-------------------|-------------------|---------------------------------------|
| quality         | `high`            | `medium`          | `profile.quality`                     |
| input_fidelity  | `high`            | **omitted**       | `profile.input_fidelity = None`       |
| size            | aspect-matched    | `1024x1024`       | `profile.size_override`               |
| mask            | on                | off               | `profile.use_mask`                    |
| max_attempts    | `3`               | `1`               | `profile.max_attempts`                |
| vision_analysis | on                | off (FIRST_VISION)| `profile.vision_analysis_fv`          |

Kept identical across all steps: full 4.6.2 prompt architecture
(`compact_prompts=False`), SAME APARTMENT PHOTO-EDIT philosophy, `openings_anchor`,
material-only DNA, `compact_realism`, structural preservation wording.

## Planned matrix

| Step   | Name                  | Change vs previous validated step      | Status              |
|--------|-----------------------|----------------------------------------|---------------------|
| Step 1  | `mobile_mvp_baseline` | Naked baseline — all features OFF, size forced 1024x1024 | superseded by 1B |
| Step 1B | `mobile_mvp_baseline` | Aspect-ratio correction ONLY: size 1024x1024 → aspect-matched | **ACTIVE** |
| Step 2 | + input_fidelity      | Add ONLY `input_fidelity="high"`        | planned (not built) |
| Step 3 | + size                | Increase ONLY image size (aspect-match) | planned (not built) |
| Step 4 | + mask                | Enable ONLY `use_mask=True`             | planned (not built) |
| Step 5 | + quality             | Enable ONLY `quality="high"`            | planned (not built) |

Each future step modifies exactly one variable, preserves all others identical, and
waits for visual validation before proceeding. `max_attempts` and FIRST_VISION
`vision_analysis` are deliberately left at the lean baseline unless evidence later
shows a step needs them.

## Current active step

**Step 1B — `mobile_mvp_baseline`** (aspect-ratio correction).

Step 1 manual visual validation showed the forced square output was recomposing
landscape sources: reduced bay-window width, altered opening proportions, invented
wall, normalized/compressed framing. Step 1B isolates ONLY the output aspect ratio:
`size_override` `1024x1024` → `None`, routing through the PROD-tested
`_detect_output_size()` (landscape → 1536x1024, portrait → 1024x1536, square →
1024x1024). This is NOT Step 2 — `input_fidelity` stays omitted.

```
quality          = "medium"
input_fidelity   = None          # parameter omitted entirely from images.edit
size             = aspect-matched (size_override=None; Step 1B — was forced 1024x1024)
mask             = off           # use_mask = False
max_attempts     = 1
vision_analysis  = off for FIRST_VISION (iteration == 1)
compact_prompts  = False         # full 4.6.2 prompt architecture KEPT
```

Why disabling FIRST_VISION vision analysis is prompt-neutral: Wave 4.6.1 removed
`SOURCE_SPACE` from the FIRST_VISION prompt. `room_description` (the vision-analysis
output) is therefore already unused in the FV prompt. Skipping it removes one
GPT-4o-mini call with zero change to the generated FV prompt text.

## Measurement strategy

Per generation the backend already emits structured evidence:

- `[PERF] stage=vision_analysis duration_ms=...` — vision call latency (≈0 when skipped)
- `[PERF] stage=mask_generation duration_ms=...` — mask latency (absent when skipped)
- `[PERF] payload_estimate total_bytes=...` — request payload size
- `[OpenAI Attempt n/N] succeeded in Xs` — generation latency + attempt count
- `[Generation Cost] mode=... quality=... input_fidelity=... size=...` — cost inputs
- `_timer.log_summary(...)` — total pipeline duration + estimated cost

For each step, capture from real PROD runs:

1. **Latency:** total pipeline duration; vision + mask + openai stage breakdown.
2. **Cost:** `estimate_cost_usd` output (quality × size × attempts × vision_calls).
3. **Retry behaviour:** attempt count distribution over a sample.
4. **Visual quality (manual):** fidelity, realism, premium feel, atmosphere quality,
   architecture/openings preservation — scored by the user on PROD images.

A feature is judged **required** only if removing it measurably degrades visual
quality at PROD on the benchmark apartment; otherwise it is a removable band-aid.

## Expected Step 1 deltas (vs PROD, to be confirmed by manual validation)

- Vision analysis call removed for FIRST_VISION → −1 GPT-4o-mini call, lower latency.
- `max_attempts` 3 → 1 → worst-case API calls per request 3 → 1.
- `quality` high → medium and forced 1024x1024 → lower image-generation cost & latency.
- `input_fidelity` omitted + mask off → smaller payload, faster generation.
- Risk to validate visually: architecture/openings fidelity without mask + fidelity
  parameter; premium feel at `quality=medium`.
