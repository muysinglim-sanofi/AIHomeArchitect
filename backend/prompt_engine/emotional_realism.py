"""
Wave 5.5.15c — Atmosphere Emotional Calibration (CREATIVE-MODE ONLY, per-atm).

ITERATION HISTORY:

  Wave 5.5.15b  — preserve + creative both got one 3-concept sentence
                  ("lived-in micro-layering" / "layered texture realism" /
                  "lived-in storytelling"). Bench result: 3/9 wall invention
                  in V1 preserve. ROLLED BACK.

  Wave 5.5.15b' — trimmed retry. Dropped surface-implying nouns. Preserve
                  kept "soft shadow falloff, restrained imperfections".
                  Bench: baseline = 0/9, with signal = 1/9. Still nudged
                  the model toward wall invention in preserve mode.

  Wave 5.5.15b'' (= shipped 5.5.15b) — preserve mode signal DROPPED
                  entirely. Creative-mode signal kept as ONE generic
                  sentence: "cinematic lighting depth, restrained
                  imperfections, atmospheric warmth around the existing
                  focal zone." Bench: 0/9 walls in preserve (baseline-
                  identical prompt), creative un-benched.

  Wave 5.5.15c  — current. Generic creative sentence replaced with a
                  per-atmosphere dict (10 atmospheres × 1 sentence each).
                  Same format, same suffix anchor, calibrated wording
                  per atmosphere identity from the calibration matrix.
                  Preserve mode stays silenced.

PURPOSE (Wave 5.5.15c)
======================

Calibrate the creative-mode emotional realism signal so each atmosphere
becomes emotionally recognizable / visually memorable / more emotionally
differentiated WITHOUT reintroducing any of the failure modes that doomed
the previous iterations:

  - NO architectural reinterpretation language
  - NO openness bias ("airy", "expansive", "grand", "open-plan", "seamless flow")
  - NO furnishing density vocabulary
  - NO showroom-target language ("hospitality-grade", "fully designed",
    "gallery-like", "fully layered")
  - NO surface-implication nouns ("layering", "texture", "imperfections"
    as standalone — only as adjective-softened atmosphere cues)
  - NO statement-wall / media-wall vocabulary
  - NO biophilic/sculptural ARCHITECTURE vocabulary (the nouns "biophilic
    architecture" / "sculptural architecture" are explicitly banned —
    "biophilic" alone is also avoided since it leans architectural)

The 10 sentences are sourced from the user-approved roadmap doc
(docs/WAVE_5_5_15_ROADMAP.md) and calibrated against:
  - the atmosphere knowledge base (memory/atmosphere_knowledge.md)
  - the Wave 5.5a calibration matrix (memory/wave_5_5a_calibration_matrix.md):
      * reference atmospheres (Bali / Tropical / Dark / Soft Luxury):
        sentences kept close to their existing identity — do not dilute
      * HIGH-priority targets (Japandi / Zen / Warm Modern): user's own
        descriptors integrated literally

STRICT FORMAT
=============

Every sentence follows:
  EMOTIONAL REALISM — <lighting>, <emotion>, <atmosphere> around the
  existing focal zone.

The "around the existing focal zone" suffix is an anti-invention anchor.
It points the signal at what is ALREADY in the photo, not at new
architectural elements to invent. Do NOT remove this suffix unless every
sentence is independently re-evaluated for invention risk.

SIZE BUDGET
===========

Per-atmosphere sentence: 108-130 chars (incl. trailing period).
Same envelope as the Wave 5.5.15b'' single creative sentence (123 chars).

Margin headroom per atmosphere (from validate_wave5514g_margins.py with
the previous single 123-char sentence):
  Tropical Escape creative : +13  ← P5 will drop on tight prompts
  Nordic Warmth creative   : +47  ← P5 will drop on tight prompts
  Others                   : +65 to +429

The signal is OPPORTUNISTIC by design — P5 priority drops it first when
budget is saturated. On tight atmospheres the signal silently disappears
rather than forcing higher-priority sections out.

ROLLBACK
========

Three independent paths:
  1. `unset BIMODAL_ENABLED` — function returns "" → byte-identical to
     pre-Wave-5.5.14 baseline.
  2. Revert this file to Wave 5.5.15b'' state (single generic creative
     sentence) — composer wiring unchanged.
  3. Revert the wiring in composer.py + composer_v2.py to drop the
     emotional_realism section entirely.

No cascading dependencies. No state. No side effects.
"""

from __future__ import annotations

from .atmosphere_dna.bimodal_classifier import is_bimodal_enabled


# Wave 5.5.15d-equivalent — preserve mode permanently silenced.
# Kept as named constant so external imports don't break.
_EMOTIONAL_REALISM_PRESERVE = ""


# Wave 5.5.15c — per-atmosphere creative-mode sentences.
# Keys must match the atmosphere_id values produced by
# atmosphere_dna.label_to_atmosphere_id (snake_case ids).
#
# Each sentence follows the strict format:
#   EMOTIONAL REALISM — <lighting>, <emotion>, <atmosphere> around the
#   existing focal zone.
#
# Wording is the user-approved set (2026-05-24).
_EMOTIONAL_REALISM_CREATIVE_BY_ATM: dict[str, str] = {
    "tropical_escape": (
        "EMOTIONAL REALISM — humid golden-hour warmth, barefoot vacation "
        "calm, sun-filtered atmosphere around the existing focal zone."
    ),
    # Wave 5.13b — Warm Modern daylight recalibration (2026-05-31).
    # Removed "golden-hour glow" + "warm ambient depth" — they were the
    # primary creative-mode drivers of dark / hotel-at-night outputs.
    # New sentence keeps warm + premium + residential anchors while
    # leading with daytime brightness.
    "warm_modern": (
        "EMOTIONAL REALISM — bright warm daylight, premium residential "
        "calm, inviting daytime warmth around the existing focal zone."
    ),
    "soft_luxury": (
        "EMOTIONAL REALISM — refined ambient depth, soft luminous calm, "
        "cinematic atmospheric warmth around the existing focal zone."
    ),
    "japandi_calm": (
        "EMOTIONAL REALISM — quiet diffused daylight, deliberate "
        "restraint, meditative stillness around the existing focal zone."
    ),
    "nature_retreat": (
        "EMOTIONAL REALISM — soft forest-filtered light, calm organic "
        "stillness, natural ambient warmth around the existing focal zone."
    ),
    "desert_luxe": (
        "EMOTIONAL REALISM — warm desert glow, sunset-toned calm, dry "
        "atmospheric depth around the existing focal zone."
    ),
    "nordic_warmth": (
        "EMOTIONAL REALISM — soft northern daylight, restrained minimal "
        "warmth, elegant atmospheric calm around the existing focal zone."
    ),
}


# Fallback for unknown atmosphere_ids — same shape as the per-atmosphere
# sentences. Useful when label_to_atmosphere_id returns an id not in the
# dict (custom labels, future atmospheres added without a corresponding
# emotional sentence). Keeps the signal active rather than silently
# disappearing; identical to the Wave 5.5.15b'' shipped sentence.
_EMOTIONAL_REALISM_CREATIVE_FALLBACK = (
    "EMOTIONAL REALISM — cinematic lighting depth, restrained "
    "imperfections, atmospheric warmth around the existing focal zone."
)


def build_emotional_realism_signal(
    generation_mode: str = "preserve",
    atmosphere_id: str = "",
) -> str:
    """Wave 5.5.15c — return the per-atmosphere creative emotional sentence.

    Returns "" (no-op) when:
      - BIMODAL_ENABLED env var is unset / falsy (production safety
        invariant — same gate as the rest of Wave 5.5.14)
      - generation_mode == "preserve" (Wave 5.5.15b'': preserve mode
        permanently silenced; see module docstring for empirical chain)
      - generation_mode is unknown (treated as "no signal")

    Returns the per-atmosphere creative sentence when mode == "creative"
    + flag ON + atmosphere_id is in the dict.

    Falls back to the Wave 5.5.15b'' generic creative sentence when the
    atmosphere_id is missing or unknown — keeps the signal active for
    custom/future labels rather than silently dropping it.

    Composer wiring: P5 priority. Drops first under budget pressure
    (on tight atmospheres in creative mode, ~110-130 chars may overflow
    available margin; P5 ensures graceful no-op instead of forcing
    higher-priority sections out).
    """
    if not is_bimodal_enabled():
        return ""
    if generation_mode != "creative":
        # preserve mode + unknown modes → silenced
        return ""
    if atmosphere_id and atmosphere_id in _EMOTIONAL_REALISM_CREATIVE_BY_ATM:
        return _EMOTIONAL_REALISM_CREATIVE_BY_ATM[atmosphere_id]
    return _EMOTIONAL_REALISM_CREATIVE_FALLBACK
