# AIHomeArchitect Benchmark Protocol

**Version:** Wave 4.4.1  
**Purpose:** Repeatable manual evaluation of fidelity vs. transformation quality trade-offs.

---

## When to Run

Run after every wave that changes:
- Prompt architecture (budgets, priorities, section text)
- Mask system (mask_generator.py, ENABLE_STRUCTURAL_MASK)
- Realism or WOW layers (realism_layer.py, wow_layer.py)
- Atmosphere DNA blocks (atmosphere_dna/*.py)

Run on a PROD backend (real OpenAI calls, PROD profile, input_fidelity=high).  
Never run in DEV mode (compact_prompts=True) for benchmark sessions.

---

## Reference Benchmark Apartment

Use the same apartment across all benchmark sessions for consistent comparison.  
The reference space has properties that stress-test the system's hardest challenges:

**Benchmark specs:**
- Bay windows (wide, asymmetric — tests window position preservation)
- Glass partition separating zones (tests interior structural element survival)
- Diagonal spatial depth (tests camera/perspective lock)
- Multi-zone visibility (balcony access + living zone simultaneously visible)
- Exposed ceiling / high ceiling (tests ceiling geometry lock)

**Log to check:**
```
[Mask] generated WxH NNNbytes perimeter_edge=Npx layers=perimeter+luminosity+edge
[Prompt Budget] mode=FIRST_VISION budget=3550 actual=NNN compression_applied=... removed_sections=...
```

**Required log state:**
- `compression_applied=False` or `removed_sections=[]` — ideal, no content dropped
- If `compression_applied=True`: check WHICH sections dropped. wow_directive must NOT drop.

---

## Scoring Dimensions

Score each dimension 1–5. Half-scores allowed (e.g., 3.5).

### A. Architecture Fidelity

Does the output look like the SAME PHYSICAL APARTMENT?

| Score | Meaning |
|-------|---------|
| 5 | Identical geometry: windows, partitions, camera, proportions all match source |
| 4 | Near-identical: minor perspective shift or one element slightly repositioned |
| 3 | Recognizable but noticeable drift: window sizes changed, depth altered |
| 2 | Same style but different apartment: clear layout or camera change |
| 1 | Different apartment entirely: layout, topology, perspective reinvented |

**Observe:** bay window positions and proportions, glass partition location, balcony
opening, diagonal depth cue, camera height and viewing angle.

---

### B. WOW Transformation

Does the output produce an aspirational "I want this" reaction?

| Score | Meaning |
|-------|---------|
| 5 | Jaw-dropping: premium magazine quality, emotionally powerful, aspirational |
| 4 | Clearly elevated: strong atmosphere, premium materials, memorable |
| 3 | Competent redesign: style applied correctly but lacks emotional energy |
| 2 | Weak transformation: surface recolor feel, no editorial vision |
| 1 | Failed: generic or indistinguishable from a basic photo filter |

**Observe:** material richness, lighting drama, editorial composition, atmosphere conviction.

---

### C. Realism

Does the output look like a real photograph (not CGI or a render)?

| Score | Meaning |
|-------|---------|
| 5 | Indistinguishable from a luxury real estate photograph |
| 4 | Very photorealistic: minor CGI tells visible only on close inspection |
| 3 | Photorealistic overall but some render-feeling surfaces |
| 2 | Clearly CGI: plastic materials, harsh lighting, or over-processed look |
| 1 | Obvious AI render: artifacts, merged geometry, synthetic materials |

**Observe:** material depth (wood grain, stone veining, textile weave), shadow
physics, light falloff from windows, human scale of furniture.

---

### D. Atmosphere Strength

Does the output clearly express the intended atmosphere?

| Score | Meaning |
|-------|---------|
| 5 | Unmistakable: style immediately identifiable, DNA fully expressed |
| 4 | Strong: atmosphere clearly communicated, minor ambiguity at periphery |
| 3 | Recognizable: core atmosphere present but diluted or inconsistent |
| 2 | Vague: hints of the style but feels generic or mixed |
| 1 | Wrong: different atmosphere applied, or style completely lost |

**Observe:** material palette consistency, lighting character, furniture language,
emotional tone (calm vs. dramatic vs. warm etc.).

---

### E. Completeness

Does the space feel fully designed and inhabited?

| Score | Meaning |
|-------|---------|
| 5 | Fully staged: every zone has layered furniture, decor, and lighting |
| 4 | Well-staged: complete feel with minor sparse areas |
| 3 | Partially staged: some zones feel empty or under-furnished |
| 2 | Minimally staged: large empty areas, furniture catalogue-sparse |
| 1 | Empty or broken staging: no decor, phantom furniture, missing zones |

**Observe:** whether all visible functional zones are furnished, textile richness,
decor layer, whether existing equipment (TV, fixtures) is preserved or replaced.

---

## Composite Score

```
Composite = (A × 0.30) + (B × 0.25) + (C × 0.20) + (D × 0.15) + (E × 0.10)
```

Weights reflect the product contract: fidelity + wow are the primary deliverables;
realism and atmosphere are supporting quality signals; completeness is a nicety.

**Pass thresholds:**

| Grade | Composite | Meaning |
|-------|-----------|---------|
| SHIP | >= 4.0 | Production-ready |
| ACCEPTABLE | 3.5–3.9 | Ship with caveats noted |
| NEEDS WORK | 3.0–3.4 | Wave regression or specific failure mode |
| BLOCKED | < 3.0 | Do not ship; architectural failure |

---

## Session Template

For each benchmark render, record:

```
Date:
Wave:
Atmosphere:
Room type:
Source description (first 100 chars):

Scores:
  A. Architecture Fidelity: ___ / 5
  B. WOW Transformation:    ___ / 5
  C. Realism:               ___ / 5
  D. Atmosphere Strength:   ___ / 5
  E. Completeness:          ___ / 5

Composite: ___ / 5

Log excerpt:
  compression_applied: ___
  removed_sections: ___
  mask generated: ___

Observations:
  Architecture wins:
  Architecture failures:
  WOW wins:
  WOW failures:
  Other notes:
```

---

## Baseline Targets by Wave

| Wave | Min A | Min B | Min Composite | Key Improvement |
|------|-------|-------|---------------|-----------------|
| 4.3.3 | 3.5 | 3.0 | 3.3 | SAME APARTMENT reconstruction framing |
| 4.4.0 | 4.0 | 3.0 | 3.5 | Structural mask enabled; geometry preserved |
| 4.4.1 | 4.0 | 4.0 | 4.0 | wow_directive survives for all DNA sizes |

---

## Fidelity vs. WOW Balance Monitor

After each session, plot (A, B) coordinates to track balance:

- Target zone: A >= 4.0 AND B >= 4.0 (upper-right quadrant)  
- "Photoshop recolor" failure: A >= 4.5 but B < 3.0 (high fidelity, no WOW)
- "Fake apartment" failure: A < 3.0 but B >= 4.0 (great WOW, wrong apartment)

The equilibrium goal is keeping BOTH scores in the 4.0+ range simultaneously.
