# AIHomeArchitect — Master Context

> **For future Claude sessions.** Read this file first. It describes what this product is, how it is built, and what has been implemented. All architectural decisions in this file are intentional and must be respected.

---

## Product Overview

**AIHomeArchitect** is an AI architectural companion — not an image filter or Pinterest generator.

The product experience is a **persistent, conversational redesign loop**:

1. User uploads a photo of their space
2. GPT-4o-mini analyzes the architecture (room type, features, light, structure)
3. User selects an atmosphere — or AI selects one (Surprise Me / Let AI Decide)
4. AI redesigns the space while **preserving all geometry and camera angle**
5. User converses with the AI architect to refine iteratively
6. Each iteration builds on the last — memory is cumulative, not reset

**Core philosophy:**
- **Preservation-first**: architecture is never altered — walls, windows, ceilings, footprint are locked
- **Realism-first**: results must look like architectural photography, not CGI renders
- **Luxury hospitality inspiration**: the quality benchmark is boutique hotel / Architectural Digest
- **Emotionally believable design**: atmosphere must feel real, not AI-generated fantasy

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter (iOS + Android) |
| Backend | FastAPI (Python) |
| Database / Storage | Supabase (Postgres + object storage) |
| Image generation | OpenAI `gpt-image-1` (images.edit endpoint) |
| Vision analysis | OpenAI `gpt-4o-mini` (image description) |
| Deployment | Backend: Python server; Frontend: Flutter mobile |

---

## Backend Architecture — Prompt Engine

The backend's sole job is to construct a high-quality, budget-aware prompt and call `gpt-image-1`. All intelligence lives in the prompt engine.

### Pipeline (in execution order)

```
/generate endpoint
  │
  ├── 1. Fetch source image
  ├── 2. GPT-4o-mini vision analysis → room_description
  ├── 3. Parse conversation history → RefinementState
  ├── 4. Resolve room type (user selection OR Let AI Decide classifier)
  ├── 5. Resolve atmosphere (user selection OR Surprise Me recommender)
  ├── 6. compose_generation_prompt() → final prompt string
  │       ├── classify_edit_mode() → route to correct path
  │       ├── build_structural_contract() → camera + geometry lock
  │       ├── _design_intelligence_block() → atmosphere DNA OR style fallback
  │       ├── build_visible_spaces_block() → secondary room DNA
  │       ├── build_refinement_block() → accumulated conversation directions
  │       └── build_realism_block() → quality floor (trim zone)
  ├── 7. Call gpt-image-1 images.edit
  └── 8. Upload result to Supabase Storage → return URL
```

### Prompt routing — four paths

| Iteration | User intent | Path | Style DNA included |
|-----------|------------|------|--------------------|
| 1 | Any | FIRST_VISION — full redesign | Yes |
| 2+ | Object/color/placement change | LOCAL_EDIT — surgical edit | **No** — omitting DNA prevents full scene regeneration |
| 2+ | Atmospheric shift | STYLE_REFINEMENT | Yes |
| 2+ | Architectural change | STRUCTURAL_TRANSFORMATION | Yes |

### Prompt budget (hard cap: 3800 chars)

| Section | Approximate size |
|---------|-----------------|
| Task header | ~60 chars |
| Structural contract | ~1200 chars |
| Source space (vision) | ~100 chars |
| Primary DNA block | ~850–1000 chars |
| Secondary visible spaces (max 2) | ~240 chars |
| Refinement memory | ~100–200 chars |
| Realism layer | ~500 chars — **trim zone** |

The realism layer is placed last because it is boilerplate that survives truncation worst. Core design content is never truncated.

---

## Atmosphere DNA System (Two-Tier)

The most important architectural decision in the backend.

### Tier 1 — AtmosphereCoreDNA (one per atmosphere)
Shared identity. Injected once per prompt as the ATMOSPHERE line.
Fields: `philosophy`, `emotional_intent`, `architectural_language`, `material_palette`, `lighting_behavior`, `luxury_level`, `forbidden_elements`, `atmosphere_keywords`

### Tier 2 — RoomAdaptationDNA (13 per atmosphere = 130 total)
Room-specific behaviour only. Never re-states atmosphere identity.
Fields: `furniture_language`, `material_palette`, `lighting_behavior`, `decor_language`, `realism_constraints`, `room_specific_constraints`, `visible_transition_logic`, `negative_rules`

### Rendered output (two-line format)
```
ATMOSPHERE (Warm Modern): [philosophy] — [emotional_intent]. [luxury_level]
ROOM (Living Room): [materials]. LIGHT: [lighting]. STYLE: [furniture+decor]. REALISM: [constraints]. AVOID: [negatives].
```

### Registration
```python
register_core(AtmosphereCoreDNA(...))   # one per atmosphere
register(RoomAdaptationDNA(...))        # one per room per atmosphere
```

Lookup: `get_room_dna(atmosphere_id, room_type)` → falls back to `_style_block()` if no DNA registered.

---

## The 10 Atmospheres

| ID | Display Name | Luxury Benchmark |
|----|-------------|-----------------|
| `warm_modern` | Warm Modern | Boutique hotel / premium urban residence |
| `japandi_calm` | Japandi Calm | Quiet luxury boutique hospitality |
| `soft_luxury` | Soft Luxury | Rosewood / Aman / luxury suite |
| `zen_retreat` | Zen Retreat | Private Japanese retreat |
| `nordic_warmth` | Nordic Warmth | Premium Scandinavian retreat |
| `dark_contemporary` | Dark Contemporary | Contemporary penthouse luxury |
| `nature_retreat` | Nature Retreat | Luxury eco retreat |
| `desert_luxe` | Desert Luxe | Dubai penthouse / Aman desert resort |
| `bali_sanctuary` | Bali Sanctuary | Luxury Bali resort villa |
| `tropical_escape` | Tropical Escape | Contemporary tropical villa |

---

## Supported Room Types (V1 — 13 total)

```
living_room    master_bedroom    kitchen         bathroom
home_office    dining_room       entrance_hall   facade
garden         pool_area         terrace         balcony
driveway
```

Room normalisation handles aliases: "bedroom" → `master_bedroom`, "ensuite" → `bathroom`, "lounge" → `living_room`, etc.

**Do not add room types without updating:** DNA files (130 entries), room_classifier signals, atmosphere_recommender compat matrix.

---

## Intelligence Systems

### Room Classifier (`room_classifier.py`)
Deterministic keyword-scoring. No ML.
- Primary signals score 1.0, secondary signals score 0.3
- Falls back to `living_room` when no signals detected
- Also infers secondary visible spaces from visibility triggers ("visible", "through", "open plan with", etc.)
- Caps secondary spaces at 2

### Surprise Me Recommender (`atmosphere_recommender.py`)
Curated compatibility matrix — not random.
- `_BASE_COMPAT`: per-room-type base scores for all 10 atmospheres
- `_SIGNAL_BONUSES`: architectural/material/light signal bonuses applied from vision description
- Returns highest-scoring atmosphere for the room context

### Visible Spaces (`visible_space_logic.py`)
Injects secondary room DNA into the prompt for multi-space scene coherence.
- Calls `get_room_dna(atmosphere_id, secondary_room)` for each secondary room
- Renders using `build_secondary_space_block()` → `VISIBLE {ROOM}: {mat_hint}; {transition_logic}.`
- Capped at 2 secondary rooms (budget constraint)

### Refinement Memory (`refinement_memory.py`)
Stateless — rebuilt from history JSON on every request.
Categories: `KEEP`, `ADD`, `ENHANCE`, `REMOVE`, `DIRECTION`.
No backend session state required.

### Edit Intent Classifier (`edit_intent.py`)
Routes iteration 2+ to correct prompt path.
Modes: `LOCAL_EDIT`, `STYLE_REFINEMENT`, `STRUCTURAL_TRANSFORMATION`
Local edit deliberately omits style DNA to prevent full-scene regeneration.

### Preservation Layer (`preservation.py`)
Injects camera lock + structural contract + transformation scope.
Position 2 in prompt — before any style instructions.
Never modified per room type (universal architectural contract).

### Realism Layer (`realism_layer.py`)
Quality floor appended last to every prompt path.
Benchmarks: Architectural Digest / Wallpaper*.
Trim zone — truncated first when prompt approaches 3800-char cap.

---

## Implementation Status

| System | Status |
|--------|--------|
| Wave 1 — core redesign pipeline | Complete |
| Wave 2 — conversation + refinement memory | Complete |
| Atmosphere DNA (130 entries) | Complete and validated |
| Room classifier (Let AI Decide) | Complete and validated |
| Surprise Me recommender | Complete and validated |
| Visible spaces (multi-space coherence) | Complete and validated |
| Wave 2.5 — Architect Conversation Layer | Complete |
| Wave 4.2.5 — Error Handling Overhaul | Complete and validated |
| Wave 4.2.6 — DEV/PROD Profiles + Cost Protection | Complete and validated |
| Wave 4.2.7 — Smart Retry System | Complete and validated |
| Mini Wave — Conversation Orchestration Fix | Complete and validated |
| Wave 4.3.0 — Preservation Intelligence | **Next** |

**Validation baseline:** 238 automated checks, all passing. See `CURRENT_WAVE.md` for per-wave detail.

### Wave 4.2.x — What Was Added

**`generation_profiles.py`** — Frozen dataclass `GenerationProfile` with DEV and PROD presets.
Routes via `APP_ENV` in `.env`. DEV: quality=low, size=1024×1024, max_attempts=1, compact_prompts=True.
PROD: quality=high, size=auto, max_attempts=3, compact_prompts=False.

**`retry_classifier.py`** — `classify_for_retry(exc) → RetryDecision`. Classifies exceptions as
TRANSIENT (retry), NON_TRANSIENT (raise immediately, save budget), or UNKNOWN (retry with monitoring).
Non-transient failures exit the retry loop at first attempt. Handles OpenAI SDK, httpx, and standard Python errors.

**`prompt_engine/intent_classifier.py`** — `classify_intent(msg, iteration) → IntentClassification`.
Deterministic pattern matching for GENERATE / CONVERSATION / MIXED intent. Iteration 1 always GENERATE.
Added `_EXPLICIT_GENERATE` signal: "generate", "go ahead", "let's see", "do it", "ok try", "vas-y", etc.

**`main.py`** — Updated retry loop to use `classify_for_retry()`. NON_TRANSIENT failures exit with
`retryable=False` immediately. UNKNOWN treated as transient with `[RetryClassifier] UNCLASSIFIED` log.
`/chat` endpoint uses `classify_intent()` to gate generation — `should_generate` flag in response.

---

## Critical Constraints

- **Prompt hard cap: 3800 chars.** Never increase. Leave headroom below OpenAI's 4000-char limit.
- **Realism layer is the trim zone.** Place it last in all prompt paths.
- **No duplicated atmosphere blocks.** The ATMOSPHERE line appears once and only once per prompt.
- **LOCAL_EDIT omits all style DNA.** This is intentional — including DNA causes full scene regeneration.
- **Structural contract before style.** Constraints must be read before transformation instructions.
- **Room DNA inherits, never repeats.** RoomAdaptationDNA must not re-state atmosphere philosophy.

---

## Key Files Reference

```
backend/
  main.py                              — FastAPI endpoints, request handling, retry loop
  generation_profiles.py               — DEV/PROD GenerationProfile frozen dataclass
  retry_classifier.py                  — classify_for_retry() — TRANSIENT/NON_TRANSIENT/UNKNOWN
  KNOWN_LIMITATIONS.md                 — L1–L4 intentionally deferred limitations
  prompt_engine/
    composer.py                        — Prompt assembly, routing logic
    intent_classifier.py               — classify_intent() — GENERATE/CONVERSATION/MIXED
    atmosphere_dna/
      _base.py                         — DNA dataclasses, registries, renderers
      {atmosphere_id}.py (×10)         — DNA data for each atmosphere
    room_classifier.py                 — Let AI Decide
    atmosphere_recommender.py          — Surprise Me
    visible_space_logic.py             — Secondary room injection
    refinement_memory.py               — Conversation history parsing
    edit_intent.py                     — Edit mode classification
    preservation.py                    — Structural contract
    realism_layer.py                   — Quality floor
    room_intelligence.py               — Legacy room context (fallback only)
    style_dna.py                       — Legacy style DNA (fallback only)
  validate_wave425.py                  — Error handling validator (57 checks)
  validate_wave426.py                  — DEV/PROD profiles validator (65 checks)
  validate_wave427.py                  — Smart retry validator (63 checks)
  validate_wave_conv_fix.py            — Conversation orchestration validator (53 checks)
docs/
  MASTER_CONTEXT.md                    — This file
  CURRENT_WAVE.md                      — Active sprint + freeze checkpoint
  FREEZE_CONTRACT.md                   — Frozen systems (Wave 3 + Wave 4.2.x)
  VALIDATION_PROTOCOL.md               — DEV vs PROD testing rules, MVP hierarchy
  VISION.md                            — Product philosophy
```
