# Freeze Contract — Intelligence Foundation

> **This file is authoritative.** Any proposed modification to a frozen system must stop here, explain the justification, and wait for explicit user approval before proceeding.

---

## Status

**Wave 3 systems** — Frozen as of Wave 3 completion. Validated by `validate_intelligence.py`.  
**Wave 4.2.x systems** — Frozen as of 2026-05-16 (stabilization checkpoint). Validated by `validate_wave425.py` + `validate_wave426.py` + `validate_wave427.py` + `validate_wave_conv_fix.py` (238 checks, all passing).

---

## Frozen Systems

### 1. Two-Tier Atmosphere DNA Architecture
| File | Frozen scope |
|------|-------------|
| `backend/prompt_engine/atmosphere_dna/_base.py` | `AtmosphereCoreDNA`, `RoomAdaptationDNA` dataclasses; `_CORE_REGISTRY`, `_ADAPTATION_REGISTRY`; `register_core()`, `register()`, `get_core()`, `get_room_dna()`; `build_dna_block()`, `build_secondary_space_block()`; `_normalise_room()`, `label_to_atmosphere_id()` |
| `backend/prompt_engine/atmosphere_dna/__init__.py` | Export list |
| `backend/prompt_engine/atmosphere_dna/warm_modern.py` | DNA data |
| `backend/prompt_engine/atmosphere_dna/japandi_calm.py` | DNA data |
| `backend/prompt_engine/atmosphere_dna/soft_luxury.py` | DNA data |
| `backend/prompt_engine/atmosphere_dna/zen_retreat.py` | DNA data |
| `backend/prompt_engine/atmosphere_dna/nordic_warmth.py` | DNA data |
| `backend/prompt_engine/atmosphere_dna/dark_contemporary.py` | DNA data |
| `backend/prompt_engine/atmosphere_dna/nature_retreat.py` | DNA data |
| `backend/prompt_engine/atmosphere_dna/desert_luxe.py` | DNA data |
| `backend/prompt_engine/atmosphere_dna/bali_sanctuary.py` | DNA data |
| `backend/prompt_engine/atmosphere_dna/tropical_escape.py` | DNA data |

### 2. Room Classifier
| File | Frozen scope |
|------|-------------|
| `backend/prompt_engine/room_classifier.py` | `_ROOM_SIGNALS`, `_VISIBILITY_TRIGGERS`, `classify_room()`, `_detect_secondary_spaces()`, `RoomClassification` dataclass |

### 3. Surprise Me Recommender
| File | Frozen scope |
|------|-------------|
| `backend/prompt_engine/atmosphere_recommender.py` | `_BASE_COMPAT`, `_DEFAULT_COMPAT`, `_SIGNAL_BONUSES`, `rank_atmospheres()`, `surprise_me()` |

### 4. Visible Spaces / Multi-Space Logic
| File | Frozen scope |
|------|-------------|
| `backend/prompt_engine/visible_space_logic.py` | `build_visible_spaces_block()` |

### 5. Prompt Composition Strategy
| File | Frozen scope |
|------|-------------|
| `backend/prompt_engine/composer.py` | Routing logic (four paths), `_design_intelligence_block()`, `compose_generation_prompt()`, `_MAX_CHARS = 3800` |

---

## Frozen Systems — Wave 4.2.x (added 2026-05-16)

### 6. Generation Profiles
| File | Frozen scope |
|------|-------------|
| `backend/generation_profiles.py` | `GenerationProfile` frozen dataclass; `_PROFILES` dict; `get_active_profile()`; DEV and PROD preset values |

### 7. Retry Classifier
| File | Frozen scope |
|------|-------------|
| `backend/retry_classifier.py` | `RetryVerdict` enum; `RetryDecision` frozen dataclass; `classify_for_retry()`; all classification rules and reason strings |

### 8. Intent Classifier
| File | Frozen scope |
|------|-------------|
| `backend/prompt_engine/intent_classifier.py` | All `_SIGNAL` regex patterns; `classify_intent()` routing logic; `ConversationIntent` and `SubIntent` enums; `_EXPLICIT_GENERATE` pattern |

---

## Rules

### FORBIDDEN — No exceptions without explicit user approval

**Wave 3 systems:**
- Refactoring any frozen module (even "cleanup" refactors)
- Renaming frozen files, classes, functions, or fields
- Changing `AtmosphereCoreDNA` or `RoomAdaptationDNA` field names or types
- Adding or removing fields from frozen dataclasses
- Rewriting classifier scoring logic in `room_classifier.py`
- Changing compatibility scores in `atmosphere_recommender.py`
- Changing the `build_dna_block()` two-line output format
- Changing the prompt routing logic in `composer.py`
- Increasing `_MAX_CHARS` above 3800
- Changing secondary space injection rules or the 2-room cap
- Changing registration architecture (`register_core` / `register` pattern)

**Wave 4.2.x systems:**
- Changing DEV or PROD preset values in `generation_profiles.py` without a named wave
- Adding new verdict types or reclassifying existing exception types in `retry_classifier.py`
- Changing `RetryDecision` field names or `RetryVerdict` enum values
- Changing `_EXPLICIT_GENERATE` or other signal patterns in `intent_classifier.py` without a named wave
- Changing intent routing priority order in `classify_intent()`
- Changing reason strings in `retry_classifier.py` (they appear in logs and future metrics)

### ALLOWED — No approval needed

- Bug fixes for demonstrably broken behaviour
- Adding `log.info()` / `log.debug()` statements
- Adding new tests (new test files only, not modifying existing logic)
- Importing these modules from new layers (reading their outputs, not changing them)
- Adding new atmospheres or room types **in a dedicated wave** (requires updating DNA files, classifier, and recommender — must be scoped explicitly)

---

## Protocol for Proposed Changes

If a task appears to require modifying a frozen system:

1. **STOP.** Do not edit the file.
2. State clearly: _"This change requires modifying [frozen file], which is under freeze contract."_
3. Explain WHY the change is necessary and what the minimum-viable modification would be.
4. Wait for explicit user instruction before proceeding.

**This applies even if the change seems trivial.** A field rename in `RoomAdaptationDNA` silently breaks all 130 DNA registration calls. A scoring change in `atmosphere_recommender.py` changes every Surprise Me result. Small changes in frozen systems have wide blast radius.

---

## Why These Systems Are Frozen

The intelligence foundation was designed, implemented, validated, and stress-tested as a complete unit:
- 130 DNA entries across 10 atmospheres × 13 rooms — all validated
- Prompt composition verified at every path (LOCAL_EDIT, STYLE_REFINEMENT, STRUCTURAL_TRANSFORMATION, FIRST_VISION)
- Prompt budget verified: all cases stay ≤ 3800 chars
- No crashes, no missing DNA, no duplicate atmosphere blocks confirmed by `validate_intelligence.py`

Modifying these systems without a specific bug to fix is a regression risk with no upside.
