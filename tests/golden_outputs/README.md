# Golden Benchmark Outputs

**Wave 5.5.23 — Validation Infrastructure**

This directory accumulates **rendered outputs** from bench protocols, organized by wave.

## Naming convention

```
tests/golden_outputs/
├── wave_5_5_22/
│   ├── primary_living_room__warm_modern__creative__01.png
│   ├── primary_living_room__warm_modern__creative__02.png
│   ├── primary_living_room__warm_modern__creative__03.png
│   ├── primary_living_room__japandi_calm__creative__01.png
│   └── ...
├── wave_5_5_23/
│   └── ...
```

Format : `<photo>__<atmosphere_id>__<mode>__<cell_number>.png`

## Why preserve outputs

- **A/B comparison across waves** — was Wave X better than Wave Y on the same input ?
- **Drift detection over time** — does Warm Modern preserve still produce the same outputs at Wave 6.0 as it did at Wave 5.5.22 ?
- **Regression evidence** — when a future bench shows wall invention, can we point to the LAST clean run for comparison ?

## Storage

PNGs at gpt-image-1 quality are ~1-3 MB each. A full ship-gate bench (180 cells) = ~300-500 MB.

Recommendation : commit outputs from ship-gate benches only. Smoke / standard bench outputs can stay local for triage but don't need long-term storage.

`.gitignore` exception : keep `tests/golden_outputs/wave_*/` tracked. Skip `tests/golden_outputs/local/` for ad-hoc experiments.
