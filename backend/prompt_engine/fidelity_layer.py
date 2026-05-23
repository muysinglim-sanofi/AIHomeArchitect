"""
Wave 4.3.3 — Spatial Reconstruction Mandate.

ROOT CAUSE (diagnosed from PROD):
  The old task header "REDESIGN — this {room} as a {style} interior" established
  architectural reinvention as the model's dominant frame. Symptoms observed:
    - bay windows moved or resized
    - openings changed
    - TV zone relocated
    - spatial depth altered
    - room proportions drifted
    - fake-apartment feeling

  Root cause: "REDESIGN" as the opening verb gives implicit permission to reinterpret
  spatial geometry. The Tier 1 structural contract is correct and comprehensive —
  but it reads as a prohibition list rather than a reconstruction mandate. The model
  treats the real photo as stylistic inspiration, not as spatial truth.

  STYLE_REFINEMENT preserves architecture better because it starts from an
  AI-generated image (strong visual continuity). FIRST_VISION starts from a real
  photo where the model exercises more creative latitude.

FIX: Reconstruction-first mental model encoded in the task header.

  Two-phase framing: (1) reproduce spatial geometry from the photo exactly,
  then (2) apply atmosphere transformation.

  "SAME APARTMENT — apply {atmosphere}" establishes spatial identity before
  any transformation signal. "The photo defines spatial truth" is explicit
  image-grounding language — geometry, camera, windows, openings, and depth
  are facts to reproduce, not design decisions to make.

SCOPE:
  build_first_vision_task() replaces the inline task f-string in composer.py
  for the FIRST_VISION path only. All other paths unchanged:
    - STYLE_REFINEMENT: uses build_atmosphere_switch_contract() (Tier 3.5)
    - STRUCTURAL_TRANSFORMATION: uses build_structural_evolution_contract()
    - LOCAL_EDIT: uses build_local_edit_prompt()

WOW PRESERVATION:
  This wave does NOT weaken the WOW directive. build_first_vision_wow_directive()
  (wow_layer.py, Wave 4.3.1) is unchanged. The reconstruction mandate and the
  WOW directive work together:
    - Task: "reproduce spatial truth, then transform atmosphere"
    - WOW: "transform character fully via materials, lighting, atmosphere"
    - Contract: "CAMERA LOCK, STRUCTURAL LOCK, DO NOT reinterpret geometry"

BUDGET:
  New task header: ~165-220 chars (depending on dna_name + room_ctx length).
  Old task header: ~100-130 chars.
  Net addition: ~99 chars at P1 (never dropped).
  FIRST_VISION budget raised: 3250 → 3350 to compensate.

LIMITATION (RESOLVED in Wave 4.4.1):
  Soft Luxury · Gold living room DNA (~939 chars) was large enough that
  wow_directive did not fit at budget 3350. Wave 4.4.1 resolved this by:
    (1) raising budget to 3550 (+200 chars)
    (2) switching FIRST_VISION realism to compact block (-192 chars)
    (3) moving interior_completeness to P5 (drops before wow)
  wow_directive now survives for SL living room with descriptions up to ~400 chars.
"""


# Wave 4.6.2 — Openings Fidelity Directive.
# ROOT CAUSE: model still normalizes/simplifies bay windows and irregular openings
# even with CAMERA LOCK and STRUCTURAL LOCK in place. Those constraints address
# camera perspective and structural elements broadly; the model exercises creative
# latitude on opening proportions specifically — treating them as "design decisions"
# rather than photographed facts.
# FIX: explicit anchor that names openings as photographed non-negotiables.
# Injected at P1 in FIRST_VISION immediately after full_contract. ~197 chars.
_OPENINGS_ANCHOR = (
    "OPENINGS ANCHOR — Bay windows and openings are photographed facts, not design decisions. "
    "Do not resize, narrow, simplify, or standardize any opening. "
    "Preserve exact proportions from the uploaded photo."
)


def build_openings_anchor(generation_mode: str = "preserve") -> str:
    """
    Wave 4.6.2 — Openings fidelity directive. ~197 chars.
    Targets the residual failure mode: model normalizes bay windows even with
    CAMERA LOCK + STRUCTURAL LOCK. Injected at P1 in FIRST_VISION only.
    Light addition — does not restructure the preservation contract.

    Wave 5.5.14d — In creative mode (BIMODAL_ENABLED=1 + generation_mode==
    "creative"), the anchor is dropped entirely. Creative explicitly allows
    the atmosphere to reinterpret openings — keeping the anchor would
    contradict the mode. Returns "" so the budget assembler filters it out
    of the prompt. Default + preserve paths keep the full anchor.
    """
    from .atmosphere_dna.bimodal_classifier import is_creative_mode_active
    if is_creative_mode_active(generation_mode):
        return ""
    return _OPENINGS_ANCHOR


def build_first_vision_task(
    dna_name: str,
    room_ctx: str,
    generation_mode: str = "preserve",
) -> str:
    """
    Photo-edit task framing for FIRST_VISION. ~165-250 chars.

    Wave 4.6.1: changed from "SAME APARTMENT — apply" to "SAME APARTMENT PHOTO-EDIT — apply".
    "PHOTO-EDIT" signals that this is a photo editing operation, not an architectural
    reconstruction or scene generation. Eliminates residual reconstruction authority.

    Wave 4.6.0: changed from reconstruction framing to restyling framing.
    "reproduce... exactly. Then transform" → "preserve... Restyle only — transform"
    Removes implicit license to recompose; keeps photo as dominant source of truth.

    Wave 5.5.2 (C2.b — task-level DNA boundary embed): the framing now
    explicitly defines atmosphere as "aesthetic overlay only" and embeds the
    boundary definition ("Atmosphere = surfaces, materials, lighting, decor
    — never geometry") to disambiguate the DNA architectural_language fields
    (e.g. Nordic "Human-scaled rooms", Bali "open-pavilion volumes") that
    can otherwise conflict with the photographed apartment's actual scale.

    Wave 5.5.14f (Preserve mode only): the boundary-embed tail is dropped
    because the atmosphere DNA itself has been stripped of architectural
    language by `bimodal_classifier.apply_bimodal`. The counter-signal exists
    only to arbitrate a DNA-vs-photo conflict that no longer exists in the
    preserve path. Net: ~75 chars freed. Creative mode and the default
    (BIMODAL_ENABLED unset) path are unchanged — byte-identical baseline.

    Still satisfies all Wave 4.3.3 vocabulary requirements:
      SAME APARTMENT, spatial truth, geometry, camera, windows, openings, depth, transform.

    room_ctx: space-prefixed room string (" living room", " bedroom") or "" if unspecified.
    """
    from .atmosphere_dna.bimodal_classifier import (
        is_creative_mode_active,
        is_preserve_mode_active,
    )

    space = room_ctx if room_ctx else " space"

    # Wave 5.5.14d — Creative-mode task framing. Replaces "SAME APARTMENT
    # PHOTO-EDIT" (a restyling-only verb) with a reimagining frame that
    # invites architectural latitude while keeping the SAME SPACE anchor
    # so the model doesn't drift to "a different room".
    if is_creative_mode_active(generation_mode):
        return (
            f"SAME SPACE REIMAGINED — apply {dna_name} as a full "
            f"architectural concept on this{space}. The photographed room "
            f"is the starting point; the atmosphere may evolve openings, "
            f"ceiling treatment, and material structure. Keep the camera "
            f"vantage so the result reads as a transformation OF this space."
        )

    head = (
        f"SAME APARTMENT PHOTO-EDIT — apply {dna_name} as aesthetic overlay only. "
        f"The photo defines geometry: preserve this{space}'s camera, windows, "
        f"openings, depth exactly."
    )
    if is_preserve_mode_active(generation_mode):
        return head
    return (
        head
        + " Atmosphere = surfaces, materials, lighting, decor — never geometry."
    )
