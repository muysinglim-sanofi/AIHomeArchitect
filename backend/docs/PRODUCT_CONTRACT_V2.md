# AIHomeArchitect — Product Contract V2

**Version:** Wave 4.5.0  
**Purpose:** Defines the real product philosophy after Wave 4.3–4.4 learning.

---

## Core Insight

The system became progressively more complex because it was compensating for a
misunderstanding: the model interpreted "REDESIGN" as permission to reinvent
architecture. This triggered many corrective layers — topology locks, anchor
detectors, multiple contracts, reconstruction framing, preservation stacking.

**These layers helped us learn. But the core product requirement is simpler.**

The real fidelity mechanisms are:
- `input_fidelity=high` — strong image grounding at API level
- Structural mask — perimeter and window protection at pixel level
- `SAME APARTMENT` task framing — correct mental model from the first token
- Aspect-ratio preservation — room proportions cannot distort

The prompt contract provides vocabulary alignment, not defensive repetition.
**Clearer is more trustworthy to the model than louder.**

---

## Mode 1: FIRST_VISION

**What the user sees:** Upload a room photo. Select an atmosphere. See the vision.

**What the system must do:**

```
SAME APARTMENT
SAME ARCHITECTURE
SAME WALLS
SAME WINDOWS
SAME OPENINGS
SAME CAMERA
SAME SPATIAL DEPTH
SAME ROOM STRUCTURE

ONLY:
  transform atmosphere
  improve materials
  improve furniture
  improve lighting
  improve styling
  complete the room beautifully
```

**This is NOT an architectural redesign system by default.**

The output must look like a photograph of the **same physical space** with
new surfaces, materials, lighting, and atmosphere. Not a different apartment
in the same style.

---

## Mode 2: ATMOSPHERE SWITCH (Vision 2+)

**What the user sees:** Already has Vision 1. Selects a different atmosphere.

**Even stricter than FIRST_VISION.**

```
SAME APARTMENT
SAME ARCHITECTURE
SAME FURNITURE (layout, forms, composition)
SAME EQUIPMENT (TV, kitchen, fixtures)
SAME CAMERA AND COMPOSITION
SAME ROOM LAYOUT
SAME SPATIAL IDENTITY

ONLY atmosphere changes:
  colors
  materials
  textiles
  mood
  lighting tone
  decorative identity
```

Vision 2 is fundamentally: **SAME DESIGN + DIFFERENT ATMOSPHERE.**

Not a redesign. The spatial identity established in Vision 1 is a contract.

---

## Mode 3: STRUCTURAL CHANGES (AI Companion)

**Structural and layout creativity is only unlocked by explicit user request:**

- "move the sofa"
- "remove that wall"
- "add an island"
- "relocate the TV"
- "change the layout"
- "enlarge the space"
- "make this corner a reading nook"

Only the AI Companion structural mode allows this. Standard generation never
reinterprets spatial geometry without an explicit instruction.

---

## The Prompt Philosophy

**Old philosophy (defensive, contradictory):**
> "CAMERA LOCK — FROZEN: camera position, height, viewing angle, perspective, focal length,
> vanishing points, and horizon line. Room proportions, spatial depth, and all structural
> lines are fixed. This space already exists physically — DO NOT reinterpret geometry,
> DO NOT redesign architecture, or shift perspective. Output must look like a photograph
> of the SAME apartment with new surfaces, preserving its architectural identity. Any
> geometry or perspective change is a failure. STRUCTURAL LOCK — FORBIDDEN: windows —
> positions, sizes, frames; must remain unblocked, natural light visible. Doors, balcony
> access, and exterior thresholds... [continues for 1500+ chars]"

**New philosophy (clear, natural, aligned):**
> "CAMERA LOCK — FROZEN: camera position, focal length, vanishing points, horizon line.
> Room proportions, spatial depth, and all structural lines are fixed. Output must look
> like a photograph of the SAME apartment, preserving its architectural identity.
> DO NOT reinterpret geometry. DO NOT redesign architecture.
> STRUCTURAL LOCK — FORBIDDEN: windows (positions, frames, unblocked, natural light
> visible), doors, walls, ceiling height, floor plan, structural columns.
> CHANGE ONLY: surfaces, materials, furniture, lighting, textiles, colours, atmosphere.
> ATMOSPHERE BOUNDARY — geometry, openings, and topology override atmosphere.
> Atmosphere is applied last. Any perspective or geometry change is a failure."

**Result:** Same vocabulary, 47% fewer characters, no contradictions.

---

## What Actually Drives Fidelity

Priority order (highest to lowest impact):

1. **`input_fidelity=high`** — API-level image conditioning. The single biggest lever.
2. **Structural mask** — Pixel-level perimeter, window, and edge protection.
3. **SAME APARTMENT task framing** — Establishes the correct mental model before any transformation instruction.
4. **Aspect-ratio output size** — Room proportions cannot distort because the output format matches the source.
5. **Prompt vocabulary** — CAMERA LOCK, STRUCTURAL LOCK, ATMOSPHERE BOUNDARY provide explicit vocabulary alignment.

Heavy defensive prompt layering was compensating for the absence of #1–4. With all five mechanisms active, the prompt contract can be concise and clear.

---

## What Atmosphere DNA Does

The DNA blocks are NOT about preservation — they are about:

- **Character definition**: what makes this atmosphere unmistakably itself
- **Material specification**: exact surfaces, textures, finishes
- **Lighting behavior**: how light interacts with this atmosphere's surfaces
- **Room-specific adaptation**: how the atmosphere expresses in this room type
- **Quality floor**: what counts as a successful transformation for this atmosphere

DNA blocks are the primary creative intelligence layer. They should never be
compressed or cut — they carry the premium transformation quality.

---

## What WOW Means

WOW comes from:
- Luxurious materials that are physically correct and tactilely believable
- Lighting that has drama, depth, and photographic quality
- Furniture that is premium in scale, form, and placement
- Atmosphere that is unmistakably expressed — not a generic room in a style

WOW does NOT come from:
- Inventing a new apartment
- Changing topology or spatial structure
- Deleting visible elements
- Collapsing spatial openness
- Architectural creativity

The apartment is fixed. The transformation ambition is in surfaces, light, and atmosphere.

---

## Contract Summary by Mode

| Mode | Contract | Key constraint |
|------|----------|----------------|
| FIRST_VISION | Tier 1.5 (~820 chars) | SAME APARTMENT, no topology change |
| STYLE_REFINEMENT | Tier 3.5 (~515-870 chars) | TOPOLOGY LOCKED, atmosphere change only |
| STRUCTURAL_TRANSFORMATION | Tier 2 (~650 chars) | Explicit change allowed, geometry otherwise locked |
| LOCAL_EDIT | None (direct edit) | Surgical — no redesign language |
