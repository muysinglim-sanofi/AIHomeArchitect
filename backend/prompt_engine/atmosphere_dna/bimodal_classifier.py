"""
Wave 5.5.14b.1 — Bimodal classifier (Preserve vs Creative mode).

Provides surgical strip of architectural-bias phrases from the rendered DNA
prompt block, leaving decoration-only content for Preserve mode.

This module is the **technical artifact** of the per-atmosphere classification
documented in `docs/WAVE_5_5_14a_BIMODAL_CLASSIFICATION.md`. Each (search,
replace) pair below has a direct corresponding entry in that audit's
🔴 ARCHITECTURE column for its atmosphere.

## Why string replacement, not regex

The DNA data files are static and `build_dna_block` is deterministic — the
rendered text for a given (atmosphere, room) pair is byte-stable across runs.
This means simple `str.replace` is reliable; regex is unnecessary complexity
that would only obscure the per-phrase intent.

## Usage (future wave 5.5.14c will call this)

    from .bimodal_classifier import strip_architecture_tokens

    dna_text = build_dna_block(dna_obj)
    if mode == "preserve":
        dna_text = strip_architecture_tokens(dna_text, atmosphere_id)

## Conservative scope

This first version strips only the **HIGH-confidence** architectural phrases
identified in the audit (philosophy directives, emotional_intent spatial
words, opening-pressure realism clauses, "open side to garden" directives).

🟨 borderline items ("breathable" Japandi, "human-scaled" Nordic, "sculptural"
Desert) are included but commented-out — Wave 5.5.14e benchmark will reveal
whether they need stripping or can stay.

## Safety

- Unknown atmosphere_id → text returned unchanged.
- Empty text → returned unchanged.
- Each strip is idempotent (running twice = same result as once).
- Strips never introduce new vocabulary; only delete or substitute.
- Whitespace cleanup at the end normalises any double-spaces created.

## Rollback

Delete this module + remove import sites. Preserve mode would then emit
identical prompts to Creative mode (i.e. today's behaviour). Zero state
impact.
"""

from __future__ import annotations
import os
import re


# ── Feature flag ──────────────────────────────────────────────────────────────
#
# Wave 5.5.14c — bimodal composer wiring is **disabled by default** until the
# Preserve benchmark (Wave 5.5.14e) validates that stripped DNA + full
# preservation stack ≥ today's baseline quality. To enable locally:
#
#     export BIMODAL_ENABLED=1   (Linux / macOS / WSL)
#     $env:BIMODAL_ENABLED = "1" (Windows PowerShell)
#
# When unset (or "0" / "false" / "no"), `apply_bimodal()` returns the input
# text unchanged → composer behaviour byte-identical to Wave 4.10g baseline.
_BIMODAL_ENABLED_ENV = "BIMODAL_ENABLED"


def is_bimodal_enabled() -> bool:
    """True iff the BIMODAL_ENABLED env var is set to a truthy value."""
    val = os.environ.get(_BIMODAL_ENABLED_ENV, "").strip().lower()
    return val in ("1", "true", "yes", "on")


def is_preserve_mode_active(mode: str) -> bool:
    """True iff the bimodal flag is set AND the request is in preserve mode.

    Single source of truth for "should the bimodal Preserve path apply".
    Used by:
      - apply_bimodal()                                  → strip DNA tokens
      - fidelity_layer.build_first_vision_task()         → drop voice #1 tail
      - wow_layer.build_photo_edit_wow_directive()       → drop voice #4 tail
      - composer.py / composer_v2.py assembly            → drop voice #3 section

    By centralising the activation logic here, switching the flag off
    instantly reverts every site to the baseline output — there is exactly
    ONE gate to flip in an incident.
    """
    return is_bimodal_enabled() and mode == "preserve"


def should_drop_boundary_voices(mode: str) -> bool:
    """True iff the bimodal flag is set, REGARDLESS of mode.

    Wave 5.5.14i — the 4-voice 'atmosphere = decoration, never geometry'
    boundary stack made sense in the pre-bimodal single-track world: it
    arbitrated the DNA-vs-photo conflict when the DNA carried architectural
    language. In the bimodal redesign, both Preserve and Creative paths
    have replaced that arbitration with mode-specific framing:

      - Preserve: DNA architectural tokens stripped (apply_bimodal),
        so the boundary voices are redundant defensive prose against a
        threat that no longer exists.

      - Creative: SAME SPACE REIMAGINED task framing + soft contract +
        ARCHITECTURAL MEMORY + revived dormant DNA fields all grant the
        atmosphere full architectural latitude. Voice #3 ('Preserve the
        photographed apartment's geometry exactly') and voice #4 ('WOW
        only through materials... NOT geometry') DIRECTLY CONTRADICT the
        rest of the creative-mode prompt, ankylosing the model.

    Drop voices 3 and 4 in BOTH bimodal modes. Voice 2 (ATMOSPHERE
    BOUNDARY inside _SAME_APARTMENT_V2) stays in preserve as a single
    arbiter; in creative the entire _SAME_APARTMENT_V2 is replaced by the
    soft _SAME_APARTMENT_CREATIVE, so voice 2 is implicitly absent there
    too. Voice 1 (task tail) is already absent in creative (REIMAGINED
    framing replaces the PHOTO-EDIT task entirely) and absent in preserve
    (Wave 5.5.14f trims the PHOTO-EDIT task tail).

    Default (BIMODAL_ENABLED unset): returns False → all 4 voices ship
    intact, prompt byte-identical to Wave 4.10g baseline.
    """
    return is_bimodal_enabled()


def is_creative_mode_active(mode: str) -> bool:
    """True iff the bimodal flag is set AND the request is in creative mode.

    Single source of truth for the Creative composer path (Wave 5.5.14d).
    Used by:
      - preservation.build_simplified_fv_contract()      → soft CAMERA, drop STRUCTURAL LOCK
      - fidelity_layer.build_first_vision_task()         → creative framing variant
      - fidelity_layer.build_openings_anchor()           → dropped entirely
      - structural_identity.render_clause()              → soft "may be reinterpreted"
      - structural_identity.render_negative_anchors()    → dropped entirely
      - composer assembly                                → inject_creative_revival on DNA
      - inject_creative_revival()                        → revive dead DNA fields

    SAFETY: when the flag is unset (default production), creative requests
    fall through to the baseline (full preservation stack), so a
    misclassified mode value cannot accidentally weaken architectural
    preservation in prod.
    """
    return is_bimodal_enabled() and mode == "creative"


def inject_creative_revival(
    text: str,
    atmosphere_id: str,
    room_type: str,
    mode: str,
) -> str:
    """In creative mode (BIMODAL_ENABLED=1 + mode == 'creative'), append the
    dormant DNA fields that the standard renderer does NOT emit:

      - core.architectural_language  (e.g. Bali "Open-pavilion volumes…")
      - core.atmosphere_keywords     (identity keywords list)
      - dna.room_specific_constraints (e.g. "open side to garden")

    These fields exist in every atmosphere DNA but are never read by the
    `build_dna_block` renderer — they are "dead fields" the bimodal audit
    surfaced. In Creative mode we revive them as a CREATIVE EXPRESSION
    appendix block so the model has full architectural latitude for the
    atmosphere's true character.

    No-op when:
      - BIMODAL_ENABLED is unset / falsy
      - mode != 'creative'
      - text is empty
      - atmosphere_id is unknown or the DNA isn't registered for the room

    Returned text always begins with `text` exactly as passed in; revival
    content is appended after a newline so the caller can use the result
    interchangeably with the original block.
    """
    if not is_creative_mode_active(mode):
        return text
    if not text:
        return text
    # Lazy import to avoid circular deps at module load (bimodal_classifier
    # lives INSIDE atmosphere_dna; its siblings populate the registry on
    # import).
    from . import get_core, get_room_dna
    core = get_core(atmosphere_id)
    room_dna = get_room_dna(atmosphere_id, room_type)
    # Wave 5.5.14g — atmosphere_keywords injection deliberately SKIPPED.
    # Reason: per the budget-margin diagnostic (validate_wave5514g_margins.py),
    # injecting all 3 dormant fields pushed Tropical Escape creative to +47
    # margin and Desert Luxe creative to +15 — too tight for a real user
    # description. Keywords are the least-value dormant field (largely
    # redundant with material_palette concrete terms like "volcanic stone"
    # or "tadelakt"). Skipping them saves ~85-100 chars per atmosphere and
    # keeps all creative-mode margins comfortably above the 50-char safety
    # threshold. The two HIGH-value dormant fields (architectural_language
    # and room_specific_constraints) are still revived — those are what
    # give Bali "open-pavilion" character, Tropical "open-plan dissolving
    # boundaries", and similar architectural latitude language.
    extras: list[str] = []
    if core is not None and core.architectural_language:
        extras.append(
            "ARCHITECTURAL CHARACTER (creative latitude): "
            + core.architectural_language
        )
    if room_dna is not None and room_dna.room_specific_constraints:
        constraints = "; ".join(room_dna.room_specific_constraints)
        extras.append("ROOM EXPRESSION: " + constraints + ".")
    if not extras:
        return text
    return text + "\n" + "\n".join(extras)


def apply_bimodal(text: str, atmosphere_id: str, mode: str) -> str:
    """Conditionally apply bimodal strip to a rendered DNA block.

    No-op when:
      - BIMODAL_ENABLED env var is unset / falsy (default — production
        invariant: prompt byte-identical to today)
      - mode == "creative" (Creative mode keeps full DNA, incl. architecture)
      - text is empty
      - atmosphere_id has no strips registered (e.g. warm_modern, soft_luxury)

    Applied when:
      - BIMODAL_ENABLED truthy AND mode == "preserve" → strip_architecture_tokens
    """
    if not is_preserve_mode_active(mode):
        return text
    return strip_architecture_tokens(text, atmosphere_id)


# ── Per-atmosphere strip table ────────────────────────────────────────────────
#
# Each entry is a list of (search_substring, replacement) tuples. Applied in
# order — earlier entries can prepare the text for later ones if needed.
#
# Sources: docs/WAVE_5_5_14a_BIMODAL_CLASSIFICATION.md sections 1–10.
# 🔴 = HIGH bias (strip in preserve mode).
# 🟨 = borderline (kept for now; benchmark will decide).

_STRIPS: dict[str, list[tuple[str, str]]] = {
    # 1. Tropical Escape — rank 1 most architecturally-loaded
    "tropical_escape": [
        # philosophy: 🔴 "Open-air" is the only shipping atmosphere with a direct
        # topology word in its philosophy.
        ("Open-air tropical living", "Tropical living"),
        # emotional_intent: 🟨 "breezy" is mild — included but easy to revert.
        ("Breezy, ", ""),
        (", breezy", ""),
        # Bathroom negative_rules: 🔴 anti-closing pressure.
        ("no closed cabinet-heavy bathroom", "no cabinet-heavy styling"),
        # Dining negative_rules: 🔴 anti-closing.
        ("no enclosed dining room feel", "no heavy dining feel"),
        # Facade decor_language: 🔴 "architectural facade element" is an
        # architectural callout, not a decorative one.
        (
            "louvred shutters as architectural facade element",
            "louvred shutters as facade rhythm element",
        ),
        # Wave 5.5.32 — room_context leaks via build_dna_room_context_signal.
        # Kitchen room_specific_constraints: 🔴 "no upper cabinets to ceiling"
        # is a direct topology directive on existing cabinetry.
        (" — no upper cabinets to ceiling", ""),
        # Facade room_specific_constraints: 🔴 "facade identity" pushes
        # whole-facade redesign.
        (" — facade identity", ""),
    ],
    # 2. Desert Luxe — rank 2, MEDIUM bias
    "desert_luxe": [
        # emotional_intent: 🔴 "sculptural" and "monumental" are spatial words.
        ("Sculptural, ", ""),
        (", sculptural", ""),
        ("monumental, ", ""),
        (", monumental", ""),
        # philosophy: 🟨 "desert architecture and sculptural calm" — leave for
        # now; "desert architecture" is identity-defining; "sculptural calm"
        # is mostly emotional. Benchmark will decide.
        # Bathroom furniture_language: 🔴 wet-room topology.
        (
            "full tadelakt wet room — walls and floor continuous",
            "tadelakt wet room finish — walls and floor",
        ),
    ],
    # 5. Japandi Calm — rank 5, MEDIUM bias
    "japandi_calm": [
        # emotional_intent: 🟨 "breathable" — mild spatial cue.
        (", breathable", ""),
        ("breathable, ", ""),
        # Living realism_constraints: 🔴 main offender — "empty floor space
        # is deliberate, not absent" pushes openness on cramped apartments.
        ("; empty floor space is deliberate, not absent", ""),
        ("empty floor space is deliberate, not absent; ", ""),
    ],
    # 6. Warm Modern — rank 6, LOW bias (no strips needed in shipped fields).
    "warm_modern": [],
    # 7. Soft Luxury — rank 7, LOW (matrix reference — DO NOT DILUTE; no
    # shipping-field strips needed).
    "soft_luxury": [],
    # 8. Dark Contemporary — rank 8, LOW (matrix reference).
    "dark_contemporary": [
        # philosophy: 🟨 metaphor "Architectural sophistication" — soften.
        ("Architectural sophistication", "Sophistication"),
        # emotional_intent: 🟨 "architecturally confident".
        (", architecturally confident", ""),
        ("architecturally confident, ", ""),
    ],
    # 9. Nature Retreat — rank 9, LOW
    "nature_retreat": [
        # philosophy: 🟨 "architectural realism" borderline. Source text reads
        # "Biophilic calm integrated with architectural realism and earthy
        # luxury" — drop the "architectural realism and " segment.
        ("architectural realism and ", ""),
        # Wave 5.5.32 — room_context leaks via build_dna_room_context_signal.
        # Living room_specific_constraints strip removed Wave 5.5.37 — the
        # source DNA no longer contains "single statement stone or timber
        # wall — not all four walls" (replaced by the standardized TV
        # anchor pattern). Strip is now a no-op, removed for clarity.
        # Bedroom room_specific_constraints: 🔴 "clay plaster wall as
        # composition" pushes wall material change.
        (" — clay plaster wall as composition", ""),
        # Bathroom room_specific_constraints: 🔴 "single stone throughout"
        # pushes wholesale surface override.
        (
            "single stone throughout — no tile mixing",
            "stone palette consistent — no busy tile pattern",
        ),
        # Pool area room_specific_constraints: 🟨 deck-material directive.
        (
            "natural material deck only — no artificial surface",
            "natural material deck palette",
        ),
    ],
    # 10. Nordic Warmth — Wave 5.5.34b upgraded to MEDIUM bias after
    # bench 2026-05-25 showed partition wall + bedroom invention in
    # preserve mode. Root cause: "human-scaled" in emotional_intent
    # implies room subdivision into intimate volumes.
    "nordic_warmth": [
        # emotional_intent: 🔴 "human-scaled" pushes the model to subdivide
        # a larger living area into smaller "human-scaled" rooms. Bench
        # 2026-05-25 confirmed: model added a glass partition + invented
        # a bedroom zone on the right side.
        (", human-scaled", ""),
        ("human-scaled, ", ""),
    ],
}


def strip_architecture_tokens(text: str, atmosphere_id: str) -> str:
    """Strip architectural-bias phrases from `text` for the given atmosphere.

    Returns decoration-only content suitable for Preserve mode prompt
    assembly. Idempotent and safe — unknown atmosphere or empty input
    returns `text` unchanged.

    Args:
        text: The rendered DNA block (e.g. output of `build_dna_block`).
        atmosphere_id: e.g. "tropical_escape", "japandi_calm".

    Returns:
        Stripped text. Whitespace normalised (no double-spaces, no orphan
        punctuation introduced by the strips).
    """
    if not text:
        return text
    strips = _STRIPS.get(atmosphere_id)
    if not strips:
        return text

    out = text
    for search, repl in strips:
        out = out.replace(search, repl)

    # Cleanup: collapse double whitespace, fix orphan punctuation a strip
    # might have created (e.g. "..,  ," → ".").
    out = re.sub(r"[ \t]{2,}", " ", out)
    out = re.sub(r"\s+([.,;])", r"\1", out)  # space before punctuation
    out = re.sub(r"([.,;])\1+", r"\1", out)  # duplicated punctuation
    return out


def architecture_token_count(atmosphere_id: str) -> int:
    """Diagnostic — how many strips are defined for an atmosphere.

    Useful for tests and for logging "how aggressive is Preserve mode for
    this atmosphere". 0 = clean atmosphere (no strips needed in shipping
    fields). Higher = more architectural surface to strip.
    """
    return len(_STRIPS.get(atmosphere_id, []))


# ── Atmospheres covered (sanity check on module load) ─────────────────────────

_EXPECTED_ATMOSPHERES = frozenset({
    "tropical_escape", "desert_luxe",
    "japandi_calm", "warm_modern", "soft_luxury", "dark_contemporary",
    "nature_retreat", "nordic_warmth",
})


def _self_check() -> None:
    """Module-load sanity check — all 10 atmospheres registered."""
    missing = _EXPECTED_ATMOSPHERES - _STRIPS.keys()
    extra = _STRIPS.keys() - _EXPECTED_ATMOSPHERES
    assert not missing, f"bimodal_classifier missing atmospheres: {missing}"
    assert not extra, f"bimodal_classifier unknown atmospheres: {extra}"


_self_check()
