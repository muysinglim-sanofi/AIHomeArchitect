"""
WOW directive — Wave 4.3.1: First Vision Rebalancing.

Strengthens FIRST_VISION transformation ambition, editorial energy, and
apartment architecture continuity. Replaces dream_micro and dream_addendum
on the FIRST_VISION path only.

PRODUCT RULE (absolute — applies to FIRST_VISION and ATMOSPHERE_SWITCH):
  Unless the user explicitly requests structural/layout changes in chat,
  the apartment architecture must remain recognizable and preserved:
    - windows, walls, openings
    - glass partitions / verrières
    - balcony access
    - kitchen visibility
    - TV / major equipment identity
    - circulation logic, spatial openness, room relationships

  WOW comes from: materials, lighting, furniture, atmosphere, editorial
  direction, hospitality feel, composition, decor refinement.
  NOT from: inventing a new apartment, changing topology, deleting
  visible elements, collapsing spatial openness.

  Intentionally lighter than Tier 3.5 (ATMOSPHERE_SWITCH):
  - No "TOPOLOGY LOCKED" or zone-count freeze
  - No multi-zone visibility lock
  - No anchor clause injection
  FIRST_VISION keeps full transformation freedom within the real apartment.

STYLE_REFINEMENT continues to use dream_micro (DNA paths) or dream_addendum
(non-DNA paths) unchanged — preservation intelligence (Wave 4.3.0) unaffected.

Target: ~259 chars.
"""

_WOW_DIRECTIVE = (
    "TRANSFORMATION AMBITION — editorial redesign of THIS apartment, not a new one. "
    "Visible architecture stays recognizable: windows, openings, partitions, equipment. "
    "WOW: materials, lighting, furniture, atmosphere — not reinvention. "
    "Transform the character fully."
)

# Wave 4.5.1 — Premium Restyling Overlay: photo is the dominant source of truth.
# Reduces "editorial redesign" and "Transform the character fully" framing that
# caused the model to recompose rather than restyle the uploaded apartment.
_RESTYLING_WOW = (
    "TRANSFORMATION AMBITION — premium restyling of THIS exact apartment photo, not a new apartment. "
    "Visible architecture stays recognizable: windows, openings, partitions, existing equipment. "
    "WOW through: materials, finishes, lighting quality, furniture styling, atmosphere conviction. "
    "Decorate this photo — do not recompose it."
)


def build_first_vision_wow_directive() -> str:
    """
    Transformation ambition + architecture continuity directive for FIRST_VISION. ~259 chars.
    Replaces dream_micro and dream_addendum in the FIRST_VISION path only.
    Lighter than Tier 3.5: no topology lock, no zone-count freeze.
    """
    return _WOW_DIRECTIVE


def build_restyling_wow_directive() -> str:
    """
    Wave 4.5.1 — Premium Restyling Overlay WOW directive. ~326 chars.
    Photo-first framing: restyle the uploaded apartment, do not recompose.
    FROZEN from Wave 4.5.1 — backward compat for validate_wave451.py.
    Superseded in FIRST_VISION by build_photo_edit_wow_directive() (Wave 4.6.1).
    """
    return _RESTYLING_WOW


# Wave 4.6.1 — Photo-Edit WOW directive.
# Removes "furniture styling" signal; adds explicit "photo edit" framing.
# Reduces residual reconstruction authority from "premium restyling" language.
_PHOTO_EDIT_WOW = (
    "TRANSFORMATION AMBITION — premium photo-edit of THIS exact apartment, not a new apartment. "
    "Apply luxury atmosphere to the photographed space without altering its architecture. "
    "Visible architecture stays recognizable: windows, openings, partitions, existing equipment. "
    "WOW through: materials, finishes, lighting quality, atmosphere conviction. "
    "Decorate this photo — do not recompose."
)


def build_photo_edit_wow_directive() -> str:
    """
    Wave 4.6.1 — Photo-Edit WOW directive. ~379 chars.
    Photo-edit framing: edit the uploaded photo, apply atmosphere, preserve architecture.
    Replaces build_restyling_wow_directive() in FIRST_VISION Path D (DNA + non-DNA).
    Removes "furniture styling" signal that implied furniture composition authority.
    """
    return _PHOTO_EDIT_WOW
