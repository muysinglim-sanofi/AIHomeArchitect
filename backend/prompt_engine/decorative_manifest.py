"""
Wave 6.1 — Decorative Foundation (pilot).

Two additive prompt signals for the FIRST_VISION + preserve path :

  build_decoration_anchor_rule(...)
    Universal safety rule. One sentence. Constrains decoration latitude so
    new lamps/art/throws/rugs/plants anchor on existing furniture/surfaces/
    walls — never invent floor-standing furniture in empty zones. Returns
    "" outside the pilot gate to keep production prompts byte-identical
    until the wave is rolled out.

  build_staging_manifest(...)
    Atmosphere + room-specific decorative density manifest. Premium
    hospitality vocabulary. Returns a compact ~600-char STAGING block when
    the pilot gate matches, "" otherwise.

Pilot gate (Wave 6.1) :
  atmosphere_id == "warm_modern"
  AND room_type    == "living_room"
  AND edit_mode    == FIRST_VISION
  AND generation_mode == "preserve"

If any condition fails, both helpers return "". The gate is intentionally
strict and explicit so a rollout means relaxing one constraint at a time
(e.g. add `soft_luxury` to the atmosphere whitelist) without rewriting
either helper.

Architectural safety :
  - additive only
  - no architecture vocabulary (no "wall", "partition", "opening", "niche",
    "ceiling", "circulation", "extension")
  - explicit "preserve all walls, openings, and floor plan unchanged"
    re-stated inside the manifest for redundancy with MODE_CONTRACT
  - all staged objects anchor on EXISTING furniture / surfaces / windows
  - no new furniture pieces (no new sofa, no new console, no new shelving)

Wave 6.1 is a pilot. Rollout to other atmospheres/rooms requires its own
bench + wave.
"""

from __future__ import annotations
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    # EditMode imports out of the composer/main modules — keep behind
    # TYPE_CHECKING to avoid circular imports at runtime.
    from edit_intent import EditMode  # type: ignore


# ── Pilot gate ────────────────────────────────────────────────────────────────

# Wave 6.1 kill-switch (2026-06-03 — set False after empirical 2/2 wall
# invention on WM-Living bench). Decoration delta was visible and positive,
# but the manifest dilutes structural preservation authority and the model
# invents wall sections to host the richer staging (TV-anchor drift, glass
# partition re-positioning). Flip back to True only after a revised
# manifest is benched safe — see TodoWrite / wave_6_1_regression memory.
_WAVE_61_ENABLED = False

_PILOT_ATMOSPHERE = "warm_modern"
_PILOT_ROOM = "living_room"


def _normalise_room(room_type: str) -> str:
    """
    Lowercase + strip + space/hyphen → underscore.

    The rest of the system normalises room_type via
    `atmosphere_dna._base._normalise_room` (which also resolves aliases
    against `_ROOM_ALIASES`). We keep this helper purely textual to avoid
    pulling that dependency for a 3-line normalisation. If the future
    rollout needs alias resolution (e.g. "lounge" → "living_room") we can
    import the canonical helper then.

    Initial Wave 6.1 ship missed this : `room_type` arrives from the
    Flutter client as "Living Room" (the display label), the gate
    compared it byte-for-byte against "living_room", so the pilot stayed
    dormant on every real generation. Empirical evidence : log line
    "atmosphere: warm_modern  room: Living Room" with prompt_chars=2611
    instead of the expected ~3810.
    """
    return (room_type or "").lower().strip().replace("-", "_").replace(" ", "_")


def _gate_matches(
    atmosphere_id: str,
    room_type: str,
    generation_mode: str,
    edit_mode_value: str,
) -> bool:
    """
    Return True iff every Wave 6.1 pilot condition is satisfied.

    `edit_mode_value` is the str value of the EditMode enum (".value" or
    ".name") so we can keep this module import-free of EditMode. The
    caller passes whichever string identifies FIRST_VISION. We match
    case-insensitively against the canonical name to stay robust.
    """
    if not _WAVE_61_ENABLED:
        return False
    if atmosphere_id != _PILOT_ATMOSPHERE:
        return False
    if _normalise_room(room_type) != _PILOT_ROOM:
        return False
    if (generation_mode or "").lower() != "preserve":
        return False
    em = (edit_mode_value or "").upper()
    if "FIRST_VISION" not in em:
        return False
    return True


# ── Part A — Decoration anchor rule (universal safety) ───────────────────────

_DECORATION_ANCHOR_RULE = (
    "DECORATION ANCHORING — Decorative objects (lamps, art, vases, throws, "
    "rugs, plants, table-top styling) anchor on existing furniture, "
    "surfaces, and walls shown in the photo. Do not invent floor-standing "
    "furniture in empty zones."
)


def build_decoration_anchor_rule(
    atmosphere_id: str,
    room_type: str,
    generation_mode: str = "preserve",
    edit_mode_value: str = "",
) -> str:
    """
    Part A — universal safety rule for Wave 6.1 pilot.

    Returns the anchor rule string when the pilot gate matches, "" otherwise.
    """
    if not _gate_matches(atmosphere_id, room_type, generation_mode, edit_mode_value):
        return ""
    return _DECORATION_ANCHOR_RULE


# ── Part B — Staging manifest (atmosphere × room) ────────────────────────────

# Warm Modern + Living Room. Premium hospitality density without clutter.
# Every item is decorative (Tier 1/Tier 2 per the Wave 6.1 audit) — no new
# structural furniture, no architectural vocabulary.
_WM_LIVING_MANIFEST = (
    "STAGING (decorative layering only — preserve all walls, openings, "
    "floor plan, and existing furniture proportions exactly as in the "
    "photo). The Warm Modern living room reads complete and premium "
    "through layered decorative elements anchored on what is already "
    "visible : a pair of warm table lamps flanking the existing seating "
    "(on side tables or console if present, otherwise on the floor "
    "adjacent to the sofa); coffee-table styling with a tonal ceramic "
    "or travertine objet, a soft stack of art books, and one low vase "
    "with a single branch or stem; a soft wool rug in oat or camel "
    "grounding the seating footprint; floor-length warm linen curtains "
    "on existing windows; one large warm-toned artwork on an existing "
    "wall behind the sofa; a layered linen throw draped on the sofa and "
    "one or two tactile cushions in oat, camel, or warm brown; one "
    "sculptural potted plant (fig, olive, or rubber) placed adjacent to "
    "existing furniture, not in the middle of an empty floor zone. The "
    "result feels hospitality-grade and lived-in — never sparse, never "
    "over-decorated."
)


def build_staging_manifest(
    atmosphere_id: str,
    room_type: str,
    generation_mode: str = "preserve",
    edit_mode_value: str = "",
) -> str:
    """
    Part B — atmosphere + room staging manifest for Wave 6.1 pilot.

    Returns the manifest string when the pilot gate matches and a manifest
    is defined for (atmosphere_id, room_type), "" otherwise.

    Rollout path : add new (atmosphere_id, room_type) -> manifest entries
    to `_MANIFESTS` and relax `_gate_matches` if/when other atmospheres
    pass their own bench.
    """
    if not _gate_matches(atmosphere_id, room_type, generation_mode, edit_mode_value):
        return ""
    return _MANIFESTS.get((atmosphere_id, _normalise_room(room_type)), "")


_MANIFESTS: dict[tuple[str, str], str] = {
    ("warm_modern", "living_room"): _WM_LIVING_MANIFEST,
    # Future entries land here, one per (atmosphere, room) pilot wave.
}


# ── Introspection helpers (for tests + logs) ─────────────────────────────────

def pilot_keys() -> list[tuple[str, str]]:
    """Return every (atmosphere, room) currently covered by a manifest."""
    return list(_MANIFESTS.keys())


def anchor_rule_chars() -> int:
    """Char count of the anchor rule string — for budget diagnostics."""
    return len(_DECORATION_ANCHOR_RULE)


def manifest_chars(atmosphere_id: str, room_type: str) -> int:
    """Char count of a specific manifest (0 if unknown)."""
    return len(_MANIFESTS.get((atmosphere_id, room_type), ""))
