"""
Wave 5.5.15d — Emotional Realism (CREATIVE-MODE ONLY).

ITERATION HISTORY (kept for context — this is the third pass):

  Wave 5.5.15b  — preserve + creative both got a 3-concept sentence
                  ("lived-in micro-layering" / "layered texture realism" /
                  "lived-in storytelling"). Bench result: 3/9 wall invention
                  in V1 preserve. ROLLED BACK.

  Wave 5.5.15c  — trimmed retry. Dropped surface-implying nouns. Preserve
                  kept "soft shadow falloff, restrained imperfections".
                  Bench result: baseline (no signal) = 0/9, with signal =
                  1/9. Even the trimmed signal still nudges the model
                  toward wall invention in preserve mode.

  Wave 5.5.15d  — final form. Preserve-mode signal DROPPED entirely.
                  Creative-mode signal kept. See PURPOSE below.

PURPOSE
=======

Address the "AI showroom / emotionally flat / too clean" perception of
Wave 5.5.14 creative-mode outputs ONLY. Preserve mode is left untouched
because:

  - Preserve mode's contract is architecturally sacred — every signal that
    touches surfaces costs wall invention even when the wording is
    atmosphere-only. Empirical: baseline = 0/9 walls, Wave 5.5.15c
    minimum signal = 1/9 walls.
  - Creative mode already authorizes architectural reinterpretation
    (REIMAGINED + ARCHITECTURAL MEMORY) so a cinematic-lighting signal
    cannot break a contract that doesn't exist there.

NO furniture mandates. NO room-completeness checklist. NO "must / never /
every" authority. NO showroom target. Architecture stays sacred.

DESIGN CONTRACT
===============

Each rule below maps to a constraint derived from the Wave 4.2.5 failure
post-mortem (see docs/WAVE_5_5_15a_ROOM_COMPLETENESS_ARCHITECTURE_SAFETY_AUDIT.md
Section 3.4):

  1. Permissive wording only (no "must / never / every / all") ✓
  2. No zone enumeration ✓ (no list of "every functional zone")
  3. No showroom target ✓ (no "hospitality / fully designed / staged")
  4. Secondary to architecture ✓ (P5 priority + drops first under budget)
  5. BIMODAL_ENABLED-gated ✓ (returns "" without flag → byte-identical to baseline)
  6. Benchmarked before ship ✓ (validate_byteexact_5515b.py)

SIZE BUDGET
===========

Strict Phase 1 caps:
  Preserve : 92 chars (target ≤ 75 + safety margin from wording)
  Creative : 130 chars (target ≤ 120 + safety margin)

Both sentences fit within current margin headroom on every atmosphere:
  - Preserve worst case (Soft Luxury V1): +253 margin → +92 = +161 OK
  - Creative worst case (Dark Contemporary V1): +34 margin → +130 = -96 OVERFLOW

Mitigation: P5 priority drops the signal first when budget is saturated.
On tight atmospheres in creative mode, the signal silently disappears
rather than overflow. The signal is OPPORTUNISTIC by design.

ROLLBACK
========

Trivial. Three independent paths:
  1. `unset BIMODAL_ENABLED` — function returns "" → byte-identical to today.
  2. Delete this file + unwire from composer.py + composer_v2.py.
  3. `git revert <commit-15b>`.

No cascading dependencies. No state. No side effects.
"""

from __future__ import annotations

from .atmosphere_dna.bimodal_classifier import is_bimodal_enabled


# Wave 5.5.15d — Preserve mode sentence removed entirely.
# Wave 5.5.15c (with "soft shadow falloff, restrained imperfections") still
# caused 1/9 wall invention vs 0/9 baseline. "imperfections" as a noun
# (even softened by "restrained") carries surface-variation implication
# that the model satisfies by adding wall surfaces. Empirically: ANY
# preserve-mode emotional signal costs architectural fidelity, and the
# emotional-richness gain on preserve mode is small enough that the
# trade is not worth it.
#
# Constant kept (set to "") so any external import doesn't break, but
# build_emotional_realism_signal("preserve") now returns "" — composer
# section is filtered out by the budget system → byte-identical baseline.
_EMOTIONAL_REALISM_PRESERVE = ""


# Wave 5.5.15c — Creative mode sentence. 117 chars.
# Wave 5.5.15b had "layered texture realism" + "lived-in storytelling".
# "Layered texture" is the same surface-implication risk as preserve's
# "micro-layering". "Lived-in storytelling" is borderline (storytelling
# is narrative not surface, but lived-in could imply usage marks on
# imagined surfaces).
# Concepts kept (safer): cinematic lighting depth + restrained imperfections
# + atmospheric warmth + focal-zone anchor (anti-invention guard).
# Concepts dropped: "layered texture realism", "lived-in storytelling".
_EMOTIONAL_REALISM_CREATIVE = (
    "EMOTIONAL REALISM — cinematic lighting depth, restrained imperfections, "
    "atmospheric warmth around the existing focal zone."
)


def build_emotional_realism_signal(generation_mode: str = "preserve") -> str:
    """Wave 5.5.15d — return the per-mode emotional realism sentence.

    Returns "" (no-op) when:
      - BIMODAL_ENABLED env var is unset / falsy (production safety
        invariant — same gate as the rest of Wave 5.5.14)
      - generation_mode == "preserve" (Wave 5.5.15d: preserve mode
        permanently silenced; see module docstring for the empirical
        evidence chain b → c → d)
      - generation_mode is unknown (treated as "no signal")

    Returns the creative sentence when mode == "creative" + flag ON.

    Composer wiring: P5 priority. Drops first under budget pressure
    (on tight atmospheres in creative mode, ~130 chars may overflow
    available margin; P5 ensures graceful no-op instead of forcing
    higher-priority sections out).
    """
    if not is_bimodal_enabled():
        return ""
    if generation_mode == "creative":
        return _EMOTIONAL_REALISM_CREATIVE
    return ""  # preserve mode + unknown modes → silenced (Wave 5.5.15d)
