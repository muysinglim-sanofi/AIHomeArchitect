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
#
# Wave 5.4b — trimmed 382 → 195 chars. The trim audit found this section was
# being SILENTLY DROPPED by composer.py's _assemble_with_budget on Warm Modern
# and Bali Sanctuary V1 (totals 3554 / 3644 vs 3550 budget), meaning the
# load-bearing "Visible architecture stays recognizable: windows, openings,
# partitions, existing equipment" phrase was missing on those atmospheres.
# Removed three sentences whose content was already carried by `task`
# (per-room "SAME APARTMENT PHOTO-EDIT — preserve Living Room's geometry...
# Restyle only — transform surfaces, materials, lighting, atmosphere"):
#   * "premium photo-edit of THIS exact apartment, not a new apartment"
#   * "Apply luxury atmosphere to the photographed space without altering its architecture"
#   * "Decorate this photo — do not recompose"
# KEPT verbatim: the architecture-recognition reinforcement + the WOW aim.
# Net result: section now survives budget on all 10 atmospheres = uniform
# preservation authority parity.
_PHOTO_EDIT_WOW = (
    "TRANSFORMATION AMBITION — Visible architecture stays recognizable: "
    "windows, openings, partitions, existing equipment. "
    # Wave 5.5.2 (C1.b — wow-scope boundary embed): trimmed "WOW through:
    # materials, finishes, lighting quality, atmosphere conviction." (75 chars)
    # to a shorter scope statement ending with "— NOT geometry" (66 chars).
    # Net effect: -9 chars on the section (still ships within budget on all
    # 10 atmospheres) while adding a third boundary voice that scopes WOW
    # explicitly to aesthetic-only dimensions. Pairs with C2.b's task-level
    # definition for end-of-prompt reinforcement (task = head framing,
    # wow_directive = tail scope-limit). Rollback = revert the trailing
    # "WOW only..." sentence to "WOW through: materials, finishes, lighting
    # quality, atmosphere conviction."
    "WOW only through materials, lighting, atmosphere — NOT geometry."
)


def build_photo_edit_wow_directive() -> str:
    """
    Wave 4.6.1 — Photo-Edit WOW directive. ~195 chars (post Wave 5.4b trim).
    Photo-edit framing: edit the uploaded photo, apply atmosphere, preserve architecture.
    Replaces build_restyling_wow_directive() in FIRST_VISION Path D (DNA + non-DNA).
    Removes "furniture styling" signal that implied furniture composition authority.
    """
    return _PHOTO_EDIT_WOW


# Wave 5.5.3 (C3) — dedicated ATMOSPHERE DNA BOUNDARY section, P1 priority,
# positioned in the prompt AFTER the design_intel (DNA blocks) and BEFORE the
# remaining P4/P5 enrichment/wow sections. Provides a third boundary voice
# (head=task / middle=this section / tail=wow_directive) — the same
# multi-voice reinforcement pattern that Wave 4.6.2 used for openings
# preservation (OPENINGS ANCHOR + STRUCTURAL LOCK + ATMOSPHERE BOUNDARY).
#
# The position immediately after the DNA blocks is critical: the model has
# just parsed atmosphere DNA which may contain architectural_language
# conflicting with the photographed apartment ("Human-scaled rooms" Nordic,
# "premium urban" Warm Modern, "open-pavilion volumes" Bali on small apt).
# This counter-signal arrives RIGHT AFTER that DNA → arbitrates the conflict
# in favor of photo preservation.
#
# ~285 chars. P1 priority — never dropped by budget compression. Requires
# the FIRST_VISION budget bump 3550 → 3850 (still under hard ceiling 4000).
# Rollback = remove this constant + function + the composer.py registration.
_ATMOSPHERE_DNA_BOUNDARY = (
    "ATMOSPHERE DNA BOUNDARY — the DNA blocks above describe IDEAL "
    "materials, decor, lighting, and mood. They do NOT describe room "
    "scale, openings, ceilings, depth, or floor plan. Preserve the "
    "photographed apartment's geometry exactly regardless of the "
    "atmosphere's typical architectural character."
)


def build_atmosphere_dna_boundary() -> str:
    """
    Wave 5.5.3 (C3) — Atmosphere DNA Boundary directive. ~285 chars, P1.
    Placed immediately after design_intel in composer.py FIRST_VISION path,
    so the "DNA above" reference is correct. Multi-voice reinforcement with
    task-level (C2.b) and wow-level (C1.b) boundary signals from Wave 5.5.2.
    """
    return _ATMOSPHERE_DNA_BOUNDARY
