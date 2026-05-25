"""
Composer V2 — Wave 5.2 clean prompt architecture rebuild.

Audit-driven rebuild of the prompt assembly. The frozen composer.py
remains the rollback baseline and is NEVER modified by this module.

The 5 conceptual sections (the audit's recommended hierarchy):

  [1] CORE SPATIAL CONTRACT      P1, always present, single unified block
                                  Absorbs: task + full_contract +
                                  openings_anchor + structural_negative_anchors.
                                  ~570-650 chars. Never drops.

  [2] SOURCE ARCHITECTURAL FACTS  P1, only when facts exist
                                  Absorbs: structural_identity clause +
                                  anchor_detector clause + per-opening
                                  enumeration. One enumerated block.
                                  ~50-400 chars depending on apartment complexity.

  [3] STYLE TRANSFORMATION       P2
                                  Absorbs: atmosphere DNA + a single
                                  "transformation ambition" line + (optionally)
                                  interior_completeness + natural enrichment.
                                  Prefixed with a "restyle existing elements"
                                  framing that reduces composition-authority drift.
                                  ~900 chars typical.

  [4] QUALITY FLOOR              P3
                                  compact_realism, unchanged.
                                  ~133 chars.

  [5] USER DIRECTION             P4
                                  Merges design_direction (V1) +
                                  refinement_memory + authorized_user_changes
                                  (V2+). One coherent user-intent block.
                                  0-400 chars.

  LOCAL_EDIT mode: delegated to the existing `build_local_edit_prompt`
  + compact_realism. It is a targeted-edit path that does NOT fit the
  global 5-section preservation model, and forcing it would only add
  noise. Identical to composer.py's LOCAL_EDIT behaviour.

The public API matches composer.py::compose_generation_prompt exactly so
main.py can flip via a single env-var dispatch (`COMPOSER_VERSION`).
"""

from __future__ import annotations

import logging
import re
from enum import Enum
from typing import Optional

# Read-only imports from frozen / shared modules. Nothing here is modified.
from .anchor_detector import detect_anchors
from .atmosphere_dna import (
    build_dna_block,
    build_dna_room_context_signal,  # Wave 5.5.18 — dormant DNA fields revival
    get_core,
    get_room_dna,
    label_to_atmosphere_id,
)
from .atmosphere_dna.bimodal_classifier import apply_bimodal, inject_creative_revival  # Wave 5.5.14c/d — no-op unless BIMODAL_ENABLED=1
# Wave 5.5.15c — trimmed retry of emotional_realism (see composer.py imports
# block for rationale). Same gate applies — BIMODAL_ENABLED unset → "".
from .emotional_realism import build_emotional_realism_signal
# Wave 5.5.16 — replaces Wave 5.5.15g safe_furnishing_intelligence.
# Same wiring rationale as composer.py (see imports there).
from .geometry_attached_furnishing import build_furnishing_signal
from .edit_intent import (
    EditMode,
    build_local_edit_prompt,
    build_style_refinement_header,
    build_structural_transformation_header,
    classify_edit_mode,
)
from .realism_layer import build_compact_realism_block
from .wow_layer import build_atmosphere_dna_boundary  # Wave 5.5.4 — propagation of C3 to V2+ path
from .refinement_memory import build_refinement_block, parse_history
from .style_dna import get_style
from .transformation_classifier import (
    TransformationType,
    classify_transformation,
)

log = logging.getLogger("aih")


# ── [1] CORE SPATIAL CONTRACT ────────────────────────────────────────────────
# ONE unified P1 block. Absorbs every preservation concept the old architecture
# spread across task / full_contract / openings_anchor /
# structural_negative_anchors. Single coherent voice — no defensive repetition,
# no forbidden-list spam. ~580 chars.

# Wave 5.5.14f — Core contract split into base + voice-#1 tail so preserve
# mode can drop the tail while creative + default paths keep the full string.
# The full _CORE_CONTRACT_V1 is preserved at module level for the validators
# that import it directly.
_CORE_CONTRACT_V1_BASE = (
    "SAME APARTMENT PHOTO-EDIT — apply the chosen atmosphere to THIS exact "
    "photographed apartment, not a new apartment. "
    "FROZEN: camera, perspective, room proportions, ceiling height, "
    "and the floor plan. "
    "STRUCTURAL — every photographed opening (windows, sliding doors, "
    "balcony access, glass partitions, archways, half-walls, and any "
    "opening visible through a partition into an adjacent or rear zone), "
    "multi-zone visibility, open-plan continuity, and spatial depth all "
    "stay exactly as photographed; none may be narrowed, enclosed, walled "
    "off, or converted into a wall surface. "
    "CHANGE ONLY: surfaces, materials, furniture footprint styling, "
    "lighting, textiles, colours, decor, atmosphere."
)

# Wave 5.5.4 (C2.b parallel) — head boundary clause propagated from
# composer.py task into composer_v2's CORE. Same proven phrasing as
# `build_first_vision_task`'s "Atmosphere = surfaces, materials,
# lighting, decor — never geometry" trailing definition. Ensures V2/V3
# pure switches (which route through composer_v2 5-section, not
# composer.py Path D) ALSO benefit from the head boundary voice.
# Wave 5.5.14f — dropped in preserve mode (DNA strip removes the conflict
# this voice exists to arbitrate).
_CORE_CONTRACT_V1_VOICE_TAIL = (
    " Atmosphere = these aesthetic dimensions — NEVER geometry."
)

_CORE_CONTRACT_V1 = _CORE_CONTRACT_V1_BASE + _CORE_CONTRACT_V1_VOICE_TAIL


# Wave 5.5.14d — Creative CORE for V2/V3 paths. Mirrors preservation.py's
# _SAME_APARTMENT_CREATIVE but tuned to composer_v2's 5-section structure
# (no leading "PHOTO-EDIT" framing — the SAME SPACE REIMAGINED verb is the
# whole framing). Trades the "FROZEN" / "STRUCTURAL — none may be narrowed,
# enclosed, walled off" rigidity for "vantage preferred" + "spatial
# recognizability" — full architectural latitude with anti-random-room
# anchoring (camera + multi-zone legibility).
_CORE_CONTRACT_CREATIVE = (
    "SAME SPACE REIMAGINED — apply the chosen atmosphere as a full "
    "architectural concept on this photographed space, not a different "
    "room. CAMERA VANTAGE preferred — keep the same viewpoint and "
    "approximate focal feel so the result reads as a transformation OF "
    "this space. SPATIAL RECOGNIZABILITY — multi-zone presence and the "
    "dominant opening's relationship to the room should remain legible "
    "even when their exact form is reinterpreted. The atmosphere may "
    "evolve openings, ceiling treatment, partition language, and material "
    "structure to express its architectural character fully."
)


def _core_contract_v1_for_mode(generation_mode: str) -> str:
    """Wave 5.5.14d — three-way selection on the V2/V3 CORE contract.

    - Creative mode (BIMODAL_ENABLED=1 + creative): returns the
      _CORE_CONTRACT_CREATIVE variant (soft vantage, full latitude).
    - Preserve mode (BIMODAL_ENABLED=1 + preserve): returns the base
      contract WITHOUT the C2.b head-boundary tail (voice #1 dropped per
      Wave 5.5.14f).
    - Default (flag off / unknown mode): returns the full Wave 5.5.4
      contract → byte-identical to pre-5.5.14d.
    """
    from .atmosphere_dna.bimodal_classifier import (
        is_creative_mode_active,
        is_preserve_mode_active,
    )
    if is_creative_mode_active(generation_mode):
        return _CORE_CONTRACT_CREATIVE
    if is_preserve_mode_active(generation_mode):
        return _CORE_CONTRACT_V1_BASE
    return _CORE_CONTRACT_V1

# V2+ preamble (Wave 4.7.3 source-continuity intent, integrated cleanly).
_CORE_PREAMBLE_V2 = (
    "Continue evolving the current vision of the same apartment — "
    "preserve every architectural fact from the original photograph."
)


# ── [3] STYLE TRANSFORMATION — prefix that reduces composition-authority pull ─
# Sits immediately before the DNA block to re-frame DNA's furniture lists as
# RE-STYLING the existing footprint rather than placing new architecture.
# Light touch — DNA itself is frozen and unchanged. Wave 5.2 tight form.
_STYLE_PREFIX = (
    "STYLE TRANSFORMATION — re-surface the photographed architecture and "
    "restyle its existing furniture footprint. The DNA below is "
    "material / lighting / decor language, not architectural instructions."
)

# Wave 5.2c — transformation-permissive STYLE prefix for V2/V3 atmosphere
# SWITCHES only. Replaces the conservative V1 prefix when the user explicitly
# switches to a different atmosphere (Soft Luxury → Japandi etc.). Resolves
# the over-preservation that made V2/V3 atmosphere switches feel like
# Instagram filters on the previous vision. ARCHITECTURE stays frozen
# (CORE block is unchanged); only the STYLING IDENTITY layer is permitted
# to be fully replaced.
_STYLE_PREFIX_ATMOSPHERE_SWITCH = (
    "STYLE TRANSFORMATION — atmosphere SWITCH on the same photographed "
    "apartment. Fully replace the previous vision's styling identity "
    "(furniture silhouette, decor density, material palette, lighting "
    "language) with the new atmosphere's identity from the DNA below. "
    "Only the photographed architecture and spatial relationships stay "
    "exactly as captured."
)

# Single short "transformation ambition" line — replaces the larger
# `wow_directive` block when STYLE is assembled (no separate P4 wow section).
#
# Wave 5.5.4 (C1.b parallel) — tail boundary clause propagated from
# composer.py's `_PHOTO_EDIT_WOW` ("WOW only through materials, lighting,
# atmosphere — NOT geometry") into composer_v2's AMBITION. Ensures V2/V3
# pure switches get the tail boundary voice equivalent to V1.
# Wave 5.5.14f — base + voice-#4 split so preserve mode can drop the tail.
_TRANSFORMATION_AMBITION_BASE = (
    "AMBITION — premium hospitality-grade restyling. "
    "Decorate this photo; do not recompose it."
)
_TRANSFORMATION_AMBITION_VOICE_TAIL = (
    " WOW only through materials, lighting, atmosphere — NOT geometry."
)
_TRANSFORMATION_AMBITION = (
    _TRANSFORMATION_AMBITION_BASE + _TRANSFORMATION_AMBITION_VOICE_TAIL
)


def _transformation_ambition_for_mode(generation_mode: str) -> str:
    """Wave 5.5.14f / Wave 5.5.14i — drop the C1.b tail ('WOW only through
    materials, lighting, atmosphere — NOT geometry') in BOTH bimodal modes.

    - Preserve (5.5.14f): DNA stripped → tail is defensive prose redundant.
    - Creative (5.5.14i): tail contradicts the SAME SPACE REIMAGINED +
      ARCHITECTURAL MEMORY + revived dormant DNA fields → must drop.

    Default (BIMODAL_ENABLED unset): full Wave 5.5.4 string → byte-identical
    baseline."""
    from .atmosphere_dna.bimodal_classifier import is_preserve_mode_active
    if is_preserve_mode_active(generation_mode):
        return _TRANSFORMATION_AMBITION_BASE
    return _TRANSFORMATION_AMBITION

# Wave 5.2c — greeting-pattern regex used to extract the V1 atmosphere label
# from the chat history. Pattern source: chat_screen.dart initial AI message
# ("Your space is ready. Generating your first <Atmosphere> vision now.").
# Conservative: returns "" when nothing matches (no switch detected).
_GREETING_ATMOS_RE = re.compile(
    r"[Gg]enerating your first\s+(.+?)\s+vision",
)

# Wave 5.5.1b — additional patterns for previous-atmosphere detection.
# Fixes the bug where switching back to a previously-used atmosphere (e.g.
# V1 Nordic → V2 Tropical → V3 Nordic) was misclassified as INCREMENTAL
# because the only signal was the V1 greeting which always pointed to the
# V1 atmosphere. New extractors cover the two reliable atmosphere-mention
# signals that appear later in chat history:
#   1. User switch commands (frontend sends "switch to <Atmosphere>" as the
#      user_instruction when the user taps an atmosphere card in the reveal
#      screen, which gets persisted into chat history as a user message)
#   2. V1 result message (composer.py compose_result_message → "Here's your
#      <style_name> transformation — Vision 1.")
# Both feed into _previous_atmosphere_id_from_history's backward walk so
# the MOST RECENT atmosphere mention wins, not the first one.
_USER_SWITCH_EXTRACT_RE = re.compile(
    r"\b(?:switch|change|try|go)\s+(?:to|with)\s+([^.!?,\n]+?)(?:[.!?,]|\n|$)",
    re.IGNORECASE,
)
# Wave 5.5.5 — frontend atmosphere-card tap from reveal screen sends
# `_exploreDirection` overridePrompt: "Redesign this space in the <X> style."
# (cf. chat_screen.dart:366). This phrasing was NOT matched by
# _USER_SWITCH_EXTRACT_RE (which requires switch|change|try|go + to|with),
# causing the previous-atmosphere detection to fall back to the V1 greeting
# → V3 of same atmo as V1 (e.g. V1 Warm → V2 Japandi → V3 Warm) was
# misclassified as INCREMENTAL instead of REBOOT_FRESH, with main.py keeping
# source_mode=LATEST (= V2 Japandi render). Visible symptom: V3 looks like
# Japandi-tinted Warm Modern, not fresh Warm Modern on original photo.
_USER_REDESIGN_EXTRACT_RE = re.compile(
    r"\b(?:redesign|restyle|reimagine)\s+(?:this|the)\s+(?:space|room|place)\s+in\s+(?:the|a)\s+(.+?)\s+style",
    re.IGNORECASE,
)
_V1_RESULT_ATMOS_RE = re.compile(r"Here's your\s+(.+?)\s+transformation")


# ── Section builders ─────────────────────────────────────────────────────────


# Wave 5.2c — parse "ARCHITECTURAL ANCHORS — LOCKED: a; b; c. Preserve…"
# to extract the anchor list, so we can detect whether every anchor it
# enumerates is already present (verbatim) in the STRUCTURAL_IDENTITY clause.
_ANCHOR_LIST_RE = re.compile(r"LOCKED:\s*(.+?)\.\s", re.S)


def _extract_anchor_items(anchor_clause: str) -> list[str]:
    if not anchor_clause:
        return []
    m = _ANCHOR_LIST_RE.search(anchor_clause)
    if not m:
        return []
    return [a.strip() for a in m.group(1).split(";") if a.strip()]


def _anchors_fully_in_si(anchor_clause: str, si_clause: str) -> bool:
    """True iff every anchor in the clause already appears as a substring of
    the structural_identity clause. Conservative: when no anchors are parseable,
    returns True (nothing to add). Case-insensitive comparison."""
    items = _extract_anchor_items(anchor_clause)
    if not items:
        return True
    si_low = si_clause.lower()
    return all(item.lower() in si_low for item in items)


def _build_source_facts(
    structural_identity_clause: str,
    anchor_clause: str,
) -> str:
    """
    [2] SOURCE ARCHITECTURAL FACTS — concrete enumeration of THIS apartment's
    architectural anchors.

    Inputs are already pre-rendered text (from main.py / detect_anchors). The
    section merges both signal sources into ONE enumerated block. When neither
    has content, the section is omitted entirely (zero prompt cost).

    Architecture-only by construction — both upstream renderers are
    leak-guarded against atmosphere / decor / furniture vocabulary.

    Wave 5.2c: if every anchor in the anchor_detector clause already appears
    in the STRUCTURAL_IDENTITY clause, the anchors clause is fully redundant
    and is dropped (eliminates the "glass partition; partition; spatial
    depth" duplicate of facts already in the SI prefix). When anchor_detector
    finds at least one unique anchor, the clause is kept as-is.
    """
    si = (structural_identity_clause or "").strip()
    ac = (anchor_clause or "").strip()
    if not si and not ac:
        return ""
    if si and ac and _anchors_fully_in_si(ac, si):
        ac = ""
    parts = []
    if si:
        parts.append(si)
    if ac:
        parts.append(ac)
    return "\n".join(parts)


# Wave 5.2c — atmosphere-switch detection + local switch-header builder.
# Replaces the frozen build_style_refinement_header's "incremental evolution
# only / do not reimagine or replace the design" wording WHEN the refinement
# is an explicit atmosphere switch (Soft Luxury → Japandi). Detection is
# conservative: only fires when iteration > 1 AND a previous atmosphere can
# be unambiguously extracted from chat history AND it differs from the
# current style_label's atmosphere_id. Incremental refinements ("make it
# warmer", "more plants") never trigger.

def _try_resolve_atmosphere_id(raw_label: str) -> str:
    """Helper: normalize a captured label string to a registered atmosphere
    id, or return '' if the normalized id is not in the core registry.
    The registry guard prevents false positives from user phrases like
    'switch to a warmer palette' which would normalize but never match a
    real atmosphere."""
    try:
        atm_id = label_to_atmosphere_id(raw_label.strip())
    except Exception:  # pragma: no cover — never trust upstream input
        return ""
    if get_core(atm_id) is not None:
        return atm_id
    return ""


def _previous_atmosphere_id_from_history(history: Optional[list]) -> str:
    """Extract the MOST RECENT atmosphere id from the chat history.

    Wave 5.5.1b — fixes the "switch back to V1 atmosphere" bug. Walks
    history BACKWARDS (most recent first) and matches three signals:

      1. User switch commands ("switch to <Atmosphere>"): the most reliable
         signal in V2+ because V2+ AI result messages rarely re-mention the
         target atmosphere by name (see [composer.py:705-767]).
      2. V1 result message ("Here's your <X> transformation — Vision 1.").
      3. V1 greeting ("Generating your first <X> vision now.").

    All matches go through _try_resolve_atmosphere_id, which both normalizes
    the label to an atmosphere_id AND validates it against the core registry
    — preventing false positives from non-atmosphere user phrases that happen
    to follow "switch to ...".

    Returns '' when nothing parseable. Returning '' makes the upstream
    _detect_atmosphere_switch fall back to "no switch", which preserves
    pre-fix behaviour on edge cases."""
    if not history:
        return ""
    for msg in reversed(history):  # MOST RECENT first (Wave 5.5.1b)
        if not isinstance(msg, dict):
            continue
        content = str(msg.get("content", ""))
        role = msg.get("role")

        # Signal 1 — user switch command (V2+ trigger). Two patterns:
        #   _USER_SWITCH_EXTRACT_RE — explicit "switch to <X>" style
        #   _USER_REDESIGN_EXTRACT_RE — frontend atmosphere-card phrasing
        #     "Redesign this space in the <X> style." (Wave 5.5.5)
        if role == "user":
            m = (
                _USER_SWITCH_EXTRACT_RE.search(content)
                or _USER_REDESIGN_EXTRACT_RE.search(content)
            )
            if m:
                atm_id = _try_resolve_atmosphere_id(m.group(1))
                if atm_id:
                    return atm_id

        # Signal 2 + 3 — AI greeting or V1 result message
        if role == "ai":
            m = _GREETING_ATMOS_RE.search(content) or _V1_RESULT_ATMOS_RE.search(content)
            if m:
                atm_id = _try_resolve_atmosphere_id(m.group(1))
                if atm_id:
                    return atm_id

    return ""


def _detect_atmosphere_switch(
    history: Optional[list],
    current_atmosphere_id: str,
    iteration: int,
) -> tuple[bool, str]:
    """Return (is_switch, prev_atmosphere_id)."""
    if iteration <= 1:
        return False, ""
    prev_id = _previous_atmosphere_id_from_history(history)
    if prev_id and prev_id != current_atmosphere_id:
        return True, prev_id
    return False, ""


def _build_switch_header(
    prev_atmosphere_id: str,
    new_atmosphere_label: str,
    room_type: str,
) -> str:
    """Short contradiction-free header for atmosphere-switch V2/V3. Replaces
    the frozen build_style_refinement_header (which says 'incremental
    evolution only — do not reimagine or replace the design') — those words
    are genuinely wrong for an explicit atmosphere switch."""
    prev = (prev_atmosphere_id.replace("_", " ").title()
            if prev_atmosphere_id else "the previous atmosphere")
    room = (room_type or "space").strip()
    return (
        f"ATMOSPHERE SWITCH — same apartment, replacing the previous {prev} "
        f"styling of this {room} with {new_atmosphere_label}. Fresh "
        f"atmospheric identity; same photographed architecture."
    )


# ── Wave 5.3 — Switch-As-Fresh-V1 strategy resolution ───────────────────────
#
# Wave 5.2c established that the PROMPT correctly authorizes atmosphere
# replacement on V2+ switches. But the IMAGE INPUT to openai.images.edit
# remained the previous-vision render (source_mode=LATEST by default),
# which bakes the previous atmosphere's furniture identity into the pixel
# input the model treats as canonical. The Wave 5.2d audit identified the
# fix: on a PURE atmosphere switch (no user customizations in history),
# the request should use the ORIGINAL upload as source (acting like a
# fresh V1 in the new atmosphere). On a CUSTOMIZED atmosphere switch
# (user has added bed / moved TV / etc.), the LATEST render must be
# preserved so customizations survive the switch.
#
# This module exposes the detection used at TWO sites:
#   • here in composer_v2 — to filter refinement_memory accordingly
#   • in main.py — to override source_mode just before image fetch
#
# Helpers are exported with public names (no underscore prefix) for clean
# import from main.py. The private originals stay for backward compat.


class _SwitchStrategy(str, Enum):
    """Three behavioural modes for V2+ refinement requests."""
    INCREMENTAL = "INCREMENTAL"           # "make it warmer" — Wave 5.2 default
    REBOOT_FRESH = "REBOOT_FRESH"         # pure atmosphere switch, no prior customizations
    REBOOT_CUSTOMIZED = "REBOOT_CUSTOMIZED"  # atmosphere switch on customized state


# Transformations that count as a real user customization (must persist
# across an atmosphere switch). Anything NOT in this set is treated as
# atmosphere-only and is allowed to be reset by the switch.
# Note: TransformationType has no LOCAL_EDIT value (that's an EditMode,
# handled at a different routing layer). The five values below + the
# conservative UNKNOWN fallback fully cover the user-customization space.
_CUSTOMIZATION_TRANSFORMATIONS = frozenset({
    TransformationType.OBJECT_EDIT,
    TransformationType.FUNCTIONAL_REASSIGNMENT,
    TransformationType.STRUCTURAL_CHANGE,
    TransformationType.LAYOUT_REINTERPRETATION,
    TransformationType.UNKNOWN,  # CONSERVATIVE — never silently lose unclassified user intent
})


def is_customization_transformation(ttype: TransformationType) -> bool:
    """True if a refinement is a real spatial customization (vs atmosphere-
    only). Conservative: UNKNOWN → treated as customization so we never
    risk losing user intent we can't classify."""
    return ttype in _CUSTOMIZATION_TRANSFORMATIONS


def _iter_user_messages(history: Optional[list]) -> list[str]:
    """Yield non-empty user-message contents from the chat history."""
    out: list[str] = []
    if not history:
        return out
    for msg in history:
        if not isinstance(msg, dict):
            continue
        if msg.get("role") != "user":
            continue
        content = str(msg.get("content", "")).strip()
        if content:
            out.append(content)
    return out


def detect_history_customizations(history: Optional[list]) -> bool:
    """Walk chat history; True if ANY past user instruction classifies as a
    real customization. Iteration argument to classify_transformation is
    irrelevant for the classifications we care about — we pass 2 as a safe
    "V2+" default."""
    for text in _iter_user_messages(history):
        ttype = classify_transformation(text, 2)
        if is_customization_transformation(ttype):
            return True
    return False


def detect_atmosphere_switch(
    history: Optional[list],
    current_atmosphere_id: str,
    iteration: int,
) -> tuple[bool, str]:
    """Public alias for the existing private detector (re-used by main.py)."""
    return _detect_atmosphere_switch(history, current_atmosphere_id, iteration)


def resolve_switch_strategy(
    history: Optional[list],
    current_atmosphere_id: str,
    iteration: int,
) -> tuple[_SwitchStrategy, str, bool]:
    """Single resolver. Returns (strategy, prev_atmosphere_id, has_customizations).

    INCREMENTAL          — not an atmosphere switch (same atmosphere or V1)
    REBOOT_FRESH         — atmosphere switch AND no customizations in history
    REBOOT_CUSTOMIZED    — atmosphere switch AND at least one customization in history
    """
    is_switch, prev_id = _detect_atmosphere_switch(
        history, current_atmosphere_id, iteration,
    )
    if not is_switch:
        return _SwitchStrategy.INCREMENTAL, "", False
    has_custom = detect_history_customizations(history)
    if has_custom:
        return _SwitchStrategy.REBOOT_CUSTOMIZED, prev_id, True
    return _SwitchStrategy.REBOOT_FRESH, prev_id, False


def _filter_history_to_customizations(
    history: Optional[list],
) -> list[dict]:
    """Return a new history list containing ONLY user messages that are
    real customizations (and ALL AI messages — preserved so the greeting
    pattern + ordering stay intact for any downstream consumer that scans
    them). Used only on REBOOT_CUSTOMIZED to ensure refinement_memory
    carries forward the user's spatial changes (added bed, moved TV) but
    NOT atmosphere-only tweaks ('warmer', 'softer lighting') that belong
    to the previous atmosphere."""
    if not history:
        return []
    out: list[dict] = []
    for msg in history:
        if not isinstance(msg, dict):
            continue
        role = msg.get("role")
        if role == "user":
            content = str(msg.get("content", "")).strip()
            if not content:
                continue
            ttype = classify_transformation(content, 2)
            if is_customization_transformation(ttype):
                out.append(msg)
        else:
            # Keep AI messages verbatim (the V1 greeting carries the
            # previous-atmosphere signal; downstream code may scan).
            out.append(msg)
    return out


def _build_style_block(
    atmosphere_id: str,
    room_type: str,
    style_label: str,
    compact_prompts: bool,
    is_atmosphere_switch: bool = False,
    generation_mode: str = "preserve",  # Wave 5.5.14c — bimodal hook
) -> str:
    """
    [3] STYLE TRANSFORMATION — DNA + the consolidated quality / ambition signal.

    Wave 5.2c: when an explicit atmosphere switch is detected, the prefix
    swaps to a transformation-permissive variant that EXPLICITLY allows
    replacing the previous vision's styling identity (furniture silhouette,
    decor density, material palette, lighting). The DNA and the CORE/FACTS
    blocks are unchanged. For V1 and incremental V2+ refinements, the
    conservative V1 prefix is used as before.

    DEV (compact_prompts=True): drop the ambition line, keep DNA only.
    PROD: full block.
    """
    dna_obj = get_room_dna(atmosphere_id, room_type)
    if dna_obj is None:
        # No room-specific DNA registered: fall back to the atmosphere label
        # for a minimum non-empty style signal. Same behaviour as the
        # composer.py non-DNA fallback at this layer.
        dna_text = f"ATMOSPHERE: {style_label}."
    else:
        # Wave 5.5.14c — apply_bimodal is a no-op unless BIMODAL_ENABLED env
        # var truthy AND generation_mode == "preserve". Default = byte-
        # identical to pre-5.5.14c output.
        dna_text = build_dna_block(dna_obj)
        dna_text = apply_bimodal(dna_text, atmosphere_id, generation_mode)
        # Wave 5.5.14d — creative-mode revival of dormant DNA fields.
        dna_text = inject_creative_revival(
            dna_text, atmosphere_id, room_type, generation_mode
        )

    prefix = (
        _STYLE_PREFIX_ATMOSPHERE_SWITCH
        if is_atmosphere_switch
        else _STYLE_PREFIX
    )
    if compact_prompts:
        return f"{prefix}\n{dna_text}"
    # Wave 5.5.14f — AMBITION tail (voice #4) drops in preserve mode.
    ambition = _transformation_ambition_for_mode(generation_mode)
    return f"{prefix}\n{dna_text}\n{ambition}"


def _build_user_block(
    user_instruction: str,
    iteration: int,
    history: Optional[list],
    authorized_user_changes: str,
    refinement_history_override: Optional[list] = None,
    suppress_refinement_memory: bool = False,
) -> str:
    """
    [5] USER DIRECTION — one coherent user-intent block.

    Merges design_direction (V1) + refinement_memory (V2+) +
    authorized_user_changes (V2+ P1.5). All are architecture-respecting by
    design; this block expresses USER intent, separated from the architectural
    truth in [1] / [2].

    Wave 5.3 — atmosphere-switch memory filter:
      * suppress_refinement_memory=True  → drop refinement_memory entirely
        (REBOOT_FRESH: new atmosphere starts clean).
      * refinement_history_override=list → use this list for refinement
        memory instead of the raw history (REBOOT_CUSTOMIZED: only the
        customization items survive the switch; atmosphere-only refinements
        from the previous atmosphere are filtered out).
      * Neither set                     → V1/INCREMENTAL behaviour, byte-
        identical to pre-Wave-5.3.
    """
    pieces: list[str] = []

    instruction = (user_instruction or "").strip()
    if instruction:
        # Cap at 300 chars to match the existing design_direction policy.
        pieces.append(f"USER DIRECTION: {instruction[:300]}")

    # V2+ refinement memory (only meaningful at iteration > 1).
    if iteration > 1 and not suppress_refinement_memory:
        eff_history = (refinement_history_override
                       if refinement_history_override is not None
                       else history)
        if eff_history is not None:
            refinement_state = parse_history(eff_history, iteration)
            refinement_text = build_refinement_block(refinement_state, iteration)
            if refinement_text and refinement_text.strip():
                pieces.append(refinement_text.strip())

    # V2+ authorized user changes (already pre-rendered, V2+ only).
    auc = (authorized_user_changes or "").strip()
    if auc:
        pieces.append(auc)

    return "\n".join(pieces)


# ── Mode-aware CORE assembly ─────────────────────────────────────────────────


def _build_core(
    iteration: int,
    edit_mode: EditMode,
    generation_mode: str = "preserve",
) -> str:
    """
    [1] CORE SPATIAL CONTRACT — V1 base, with optional V2+ preamble.

    For STRUCTURAL_TRANSFORMATION (an explicit user-requested architectural
    change), the core still ENUMERATES every photographed opening as
    structural — but a permission sentence allows the SPECIFIC requested
    structural edit to alter them (only that one edit). This mirrors
    composer.py's V3 mode handling but keeps the CORE coherent.

    Wave 5.5.14f — when preserve mode is active (BIMODAL_ENABLED=1 + mode==
    "preserve"), the C2.b head boundary voice ("Atmosphere = these aesthetic
    dimensions — NEVER geometry") is dropped because the DNA itself no longer
    carries architectural language to arbitrate against.
    """
    contract = _core_contract_v1_for_mode(generation_mode)
    core = contract
    if iteration > 1:
        if edit_mode == EditMode.STRUCTURAL_TRANSFORMATION:
            core = (
                _CORE_PREAMBLE_V2
                + " "
                + contract
                + " Only the explicitly requested structural change may "
                "alter the architectural facts; every other architectural "
                "anchor remains frozen."
            )
        else:
            core = _CORE_PREAMBLE_V2 + " " + contract
    return core


# ── Public API ───────────────────────────────────────────────────────────────


def compose_generation_prompt(
    style_label: str,
    room_type: str,
    room_description: str,
    user_instruction: str,
    iteration: int,
    history: list[dict],
    secondary_visible_spaces: list[str] | None = None,
    compact_prompts: bool = False,
    structural_identity: str = "",
    source_continuity: str = "",
    structural_negative_anchors: str = "",
    authorized_user_changes: str = "",
    generation_mode: str = "preserve",  # Wave 5.5.14c — bimodal intent. Forwarded into _build_style_block / _v1_compose. No-op unless BIMODAL_ENABLED env var truthy.
) -> str:
    """
    Drop-in replacement for composer.py::compose_generation_prompt.

    Signature is identical so main.py can swap composers via a single
    env-var dispatch. The returned prompt follows the 5-section
    architecture above.

    `structural_negative_anchors` is accepted for signature compat — its
    concept is absorbed into the CORE SPATIAL CONTRACT block (the whole
    point of consolidation), so it is intentionally NOT re-emitted as a
    separate section here. Same for `source_continuity` (folded into the
    V2+ CORE preamble) and `structural_identity` (folded into [2] SOURCE
    ARCHITECTURAL FACTS).
    """
    atmosphere_id = label_to_atmosphere_id(style_label)
    edit_mode = classify_edit_mode(user_instruction, iteration)
    log.info(
        "[ComposerV2] edit_mode=%s  atmosphere=%s  room=%s  iteration=%d  "
        "compact=%s",
        edit_mode.value, atmosphere_id, room_type or "(none)", iteration,
        compact_prompts,
    )

    # ── Wave 5.3.1 — V1 (FIRST_VISION) delegation to frozen composer.py ──────
    # Wave 5.2's clean rebuild deleted ~1100 chars of opening-preservation
    # authority on the V1 path (OPENINGS ANCHOR, STRUCTURAL NEGATIVE ANCHORS as
    # a dedicated block, ATMOSPHERE BOUNDARY clause, wow_directive opening
    # list, natural enrichment, visible-spaces continuity). The P0 audit
    # confirmed this is the cause of the observed V1 fidelity regression after
    # composer_v2 activation (model inserting walls between adjacent openings).
    #
    # composer.py is the long-validated V1 baseline and the FROZEN rollback
    # target — consumed read-only here, no freeze-contract violation.
    #
    # Wave 5.3 switch detection and main.py's source_mode=ORIGINAL override
    # both short-circuit on iteration <= 1, so this delegation does NOT alter
    # any V2/V3 behaviour. V2+ still flows through the 5-section architecture
    # and the atmosphere-switch reboot strategy below.
    if iteration == 1:
        from .composer import compose_generation_prompt as _v1_compose
        log.info(
            "[ComposerV2] iteration=1 → delegating V1 to frozen composer.py"
        )
        return _v1_compose(
            style_label, room_type, room_description, user_instruction,
            iteration, history, secondary_visible_spaces, compact_prompts,
            structural_identity, source_continuity, structural_negative_anchors,
            authorized_user_changes,
            generation_mode,  # Wave 5.5.14c — forward bimodal intent
        )

    # ── LOCAL_EDIT — delegate to the existing targeted-edit path ─────────────
    # LOCAL_EDIT does not fit the 5-section global-preservation model and
    # forcing it would only add noise. Same behaviour as composer.py.
    if edit_mode == EditMode.LOCAL_EDIT:
        dna = get_style(style_label)
        edit_block = build_local_edit_prompt(
            user_instruction=user_instruction,
            style_name=dna.name,
            room_type=room_type,
            room_description=room_description,
        )
        prompt = f"{edit_block}\n{build_compact_realism_block()}"
        log.info("[ComposerV2] mode=LOCAL_EDIT  size=%d  sections=2", len(prompt))
        return prompt

    # ── Wave 5.2c — detect explicit atmosphere switch on V2+ STYLE_REFINEMENT.
    # When detected: (a) STYLE prefix swaps to the transformation-permissive
    # variant, and (b) the conservative "incremental evolution only" header
    # is replaced by a short switch-specific header (resolves the audit's
    # contradictory-authority finding). Incremental refinements ("make it
    # warmer", "more cozy") are NOT switches — they keep the conservative
    # prefix + the standard SR header.
    #
    # Wave 5.3 — the same detection also resolves a finer switch_strategy
    # used below to filter refinement_memory (REBOOT_FRESH drops it all;
    # REBOOT_CUSTOMIZED keeps only customization items). main.py uses the
    # same resolver to decide whether to override source_mode to ORIGINAL.
    switch_strategy, prev_atmosphere_id, _has_customizations = (
        resolve_switch_strategy(history, atmosphere_id, iteration)
    )
    is_atmosphere_switch = switch_strategy != _SwitchStrategy.INCREMENTAL
    if is_atmosphere_switch:
        log.info(
            "[ComposerV2] atmosphere SWITCH detected — strategy=%s "
            "prev=%s new=%s customizations=%s",
            switch_strategy.value, prev_atmosphere_id, atmosphere_id,
            _has_customizations,
        )

    # ── Wave 5.5.6 — REBOOT_FRESH delegation to composer.py Path D ───────────
    # Product contract: V2/V3 pure atmosphere switches on the original photo
    # must behave identically to a true V1 fresh generation of the target
    # atmosphere. Wave 5.3 already aligned the source image (REBOOT_FRESH →
    # source_mode=ORIGINAL in main.py). Wave 5.5.4 propagated the 3 boundary
    # voices to composer_v2 5-section — but empirical visual evaluation
    # (2026-05-21) showed V1 still significantly better than V2/V3 on
    # complex apartments (6/9 V1 preserved visible kitchen vs 0/9 V2/V3;
    # Nordic + Warm Modern V1 clearly superior; only Japandi reached parity).
    #
    # ROOT CAUSE: composer.py Path D has 11 named P1 preservation blocks
    # (task + full_contract + OPENINGS_ANCHOR + STRUCTURAL_IDENTITY +
    # NEGATIVE_ANCHORS + ARCHITECTURAL_ANCHORS LOCKED + ...). composer_v2's
    # 5-section path consolidates these into a single CORE paragraph + has
    # `_STYLE_PREFIX_ATMOSPHERE_SWITCH` which grants the model permission
    # to "Fully replace the previous vision's styling identity" — fine for
    # evolving from a previous render, but on a FRESH start from the original
    # photo, this aggressive license outweighs the boundary voices and lets
    # the model erase peripheral elements (visible kitchen, depth, etc.).
    #
    # FIX: for REBOOT_FRESH only, delegate to composer.py Path D with
    # sanitized inputs. V2/V3 pure switches become byte-identical to a V1
    # fresh emission of the target atmosphere.
    #
    # Sanitization rationale:
    #   user_instruction → ""  the meta-text "switch to <X>" or "Redesign
    #                          this space in the <X> style" is the routing
    #                          signal, not a design direction; emitting as
    #                          "DESIGN DIRECTION:" would pollute the prompt
    #   history          → []  REBOOT_FRESH means no customizations to carry
    #   iteration        → 1   composer.py FIRST_VISION requires iter==1
    #   source_continuity      → "" (V1 has no continuity preamble)
    #   authorized_user_changes→ "" (no AUC on pure switches)
    #   structural_identity / structural_negative_anchors: preserved verbatim
    #                          (derived from the ORIGINAL photo and equally
    #                          truthful for V1 fresh and pure switches).
    #
    # NOT affected by this branch:
    #   * INCREMENTAL ("make it warmer") → keeps composer_v2 5-section
    #     + the 3 propagated boundary voices (Wave 5.5.4) below
    #   * REBOOT_CUSTOMIZED → keeps composer_v2 5-section + filtered memory
    #   * LOCAL_EDIT, STRUCTURAL_TRANSFORMATION → handled by earlier branches
    #   * Wave 5.3 source_mode=ORIGINAL override in main.py — unchanged
    #     (still fires because the resolver still classifies pure switches
    #     as REBOOT_FRESH; only the prompt-build step short-circuits here)
    #   * Wave 5.5.4 boundary voices in composer_v2 — stay active for
    #     INCREMENTAL + REBOOT_CUSTOMIZED paths
    #
    # This re-implements what Wave 5.4a Edit A shipped → rolled back (based
    # on misread emulator timeline) → re-validated 2026-05-21 by empirical
    # V1 vs V2/V3 comparison. See Strategic Principle #7 (revised) in
    # wave_5_5a_calibration_matrix.md.
    if switch_strategy == _SwitchStrategy.REBOOT_FRESH:
        from .composer import compose_generation_prompt as _v1_compose
        log.info(
            "[ComposerV2] REBOOT_FRESH → delegating to frozen composer.py "
            "Path D (Wave 5.5.6 — V1=V2/V3 parity on pure switches; "
            "history sanitized; iteration forced to 1; "
            "Wave 5.5.14h — user_instruction now preserved → DESIGN DIRECTION "
            "block emitted in composer.py with the actual switch instruction "
            "(e.g. 'Redesign this space in the Japandi style.'))"
        )
        return _v1_compose(
            style_label, room_type, room_description,
            # Wave 5.5.14h — user_instruction NO LONGER sanitized. Backend
            # bench (2026-05-24) showed V1 prompts produce 4/6 kitchen
            # preservation vs V2/V3's 2/6 — the missing DESIGN DIRECTION block
            # (consequence of the old `""` sanitization) was the only diff.
            # SAFETY: classify_edit_mode(any_text, iteration=1) → FIRST_VISION
            # unconditionally (edit_intent.py:82), so passing the real
            # instruction cannot accidentally route to STYLE_REFINEMENT or
            # LOCAL_EDIT. Tested: 4/4 trigger paths in chat_screen.dart send
            # non-empty user_instruction (atmosphere card tap → "Redesign in
            # <style>"; typed input → the typed text; V1 fallback path is
            # composer.py direct, not this delegation).
            user_instruction,
            1,                                  # iteration forced for FIRST_VISION
            [],                                 # history empty — no memory carry
            secondary_visible_spaces, compact_prompts,
            structural_identity,
            "",                                 # source_continuity (V1 has none)
            structural_negative_anchors,
            "",                                 # authorized_user_changes (none)
            generation_mode,                    # Wave 5.5.14c — forward bimodal intent
        )

    # ── 5-section architecture: FV / SR / STRUCTURAL ─────────────────────────
    # [1] CORE SPATIAL CONTRACT — single unified block (V2+ preamble when iter>1).
    core = _build_core(iteration, edit_mode, generation_mode)

    # [2] SOURCE ARCHITECTURAL FACTS — only when facts exist (zero cost when empty).
    anchor_profile = detect_anchors(room_description)
    if anchor_profile.anchors:
        log.info(
            "[ComposerV2] anchors detected: %s", list(anchor_profile.anchors),
        )
    source_facts = _build_source_facts(structural_identity, anchor_profile.clause)

    # [3] STYLE TRANSFORMATION — DNA + ambition (compact-trimmed in DEV).
    # Wave 5.2c: pass is_atmosphere_switch so the prefix swaps to the
    # transformation-permissive variant when applicable.
    style_block = _build_style_block(
        atmosphere_id=atmosphere_id,
        room_type=room_type,
        style_label=style_label,
        compact_prompts=compact_prompts,
        is_atmosphere_switch=is_atmosphere_switch,
        generation_mode=generation_mode,  # Wave 5.5.14c — forward bimodal intent
    )

    # [4] QUALITY FLOOR — anti-CGI vocabulary. Untouched.
    quality_floor = build_compact_realism_block()

    # [5] USER DIRECTION — merged user-intent block.
    # Wave 5.3 — filter refinement_memory by switch_strategy:
    #   * REBOOT_FRESH      — drop refinement_memory entirely (new atmosphere
    #     starts clean; old "warmer Tropical" tweaks don't belong to Japandi)
    #   * REBOOT_CUSTOMIZED — keep only customization items in memory; drop
    #     atmosphere-only tweaks tied to the previous atmosphere
    #   * INCREMENTAL       — unchanged behaviour
    if switch_strategy == _SwitchStrategy.REBOOT_FRESH:
        user_block = _build_user_block(
            user_instruction=user_instruction,
            iteration=iteration,
            history=history,
            authorized_user_changes=authorized_user_changes,
            suppress_refinement_memory=True,
        )
    elif switch_strategy == _SwitchStrategy.REBOOT_CUSTOMIZED:
        filtered_history = _filter_history_to_customizations(history)
        user_block = _build_user_block(
            user_instruction=user_instruction,
            iteration=iteration,
            history=history,
            authorized_user_changes=authorized_user_changes,
            refinement_history_override=filtered_history,
        )
    else:
        user_block = _build_user_block(
            user_instruction=user_instruction,
            iteration=iteration,
            history=history,
            authorized_user_changes=authorized_user_changes,
        )

    # For STYLE_REFINEMENT / STRUCTURAL_TRANSFORMATION, also prepend the
    # mode-appropriate header. Wave 5.2c: on atmosphere switches, the frozen
    # `build_style_refinement_header`'s "incremental evolution only — do not
    # reimagine or replace the design" wording is REPLACED by a short local
    # switch header (no frozen-module edit). On incremental refinements the
    # standard SR header is preserved verbatim.
    header = ""
    if edit_mode == EditMode.STYLE_REFINEMENT and iteration > 1:
        if is_atmosphere_switch:
            header = _build_switch_header(
                prev_atmosphere_id,
                get_style(style_label).name,
                room_type,
            )
        else:
            dna = get_style(style_label)
            header = build_style_refinement_header(
                user_instruction, dna.name, room_type,
            )
    elif edit_mode == EditMode.STRUCTURAL_TRANSFORMATION and iteration > 1:
        dna = get_style(style_label)
        header = build_structural_transformation_header(
            user_instruction, dna.name, room_type,
        )

    # Assemble. Each non-empty section separated by ONE blank line.
    # Wave 5.5.4 — atmosphere_dna_boundary inserted AFTER style_transformation
    # (which contains the DNA blocks) so the "DNA blocks above" reference in
    # the boundary clause is correct. Parallel to composer.py's placement
    # immediately after design_intel in Path D. Completes the 3-voice
    # boundary stack on V2/V3 paths (core C2.b head + this C3 middle +
    # AMBITION C1.b tail inside style_transformation).
    # Wave 5.5.14f / Wave 5.5.14i — voice #3 dropped in BOTH bimodal modes
    # (BIMODAL_ENABLED=1). Preserve: DNA stripped → defensive prose against
    # a non-existent conflict. Creative: section says 'Preserve geometry
    # exactly' which contradicts the SAME SPACE REIMAGINED framing earlier
    # in the V2 5-section prompt → ankylosed creative latitude.
    from .atmosphere_dna.bimodal_classifier import is_preserve_mode_active
    dna_boundary = (
        "" if is_preserve_mode_active(generation_mode)
        else build_atmosphere_dna_boundary()
    )

    # Wave 5.5.18 — revive dormant DNA fields (creative-only via signal gate).
    # Wave 5.5.32 — gate through apply_bimodal so per-atmosphere strips
    # neutralise architectural directives that previously bypassed.
    v2_room_dna = get_room_dna(atmosphere_id, room_type)
    dna_context_v2 = build_dna_room_context_signal(v2_room_dna, generation_mode)
    dna_context_v2 = apply_bimodal(dna_context_v2, atmosphere_id, generation_mode)

    sections: list[tuple[str, str]] = [
        ("header", header),
        ("core_contract", core),
        ("source_facts", source_facts),
        ("style_transformation", style_block),
        ("dna_room_context", dna_context_v2),  # Wave 5.5.18 — dormant fields revival
        ("atmosphere_dna_boundary", dna_boundary),
        ("quality_floor", quality_floor),
        ("user_direction", user_block),
        # Wave 5.5.15c — per-atmosphere creative emotional signal.
        # No priority system in composer_v2 5-section path → if budget
        # overflow becomes an issue, drop here. Bimodal-gated +
        # preserve-mode silenced internally.
        ("emotional_realism", build_emotional_realism_signal(generation_mode, atmosphere_id)),
        # Wave 5.5.16 — geometry-attached furnishing semantics (5 rooms × 2
        # modes). Empty string for unmapped rooms or flag-off paths.
        ("geometry_attached_furnishing", build_furnishing_signal(generation_mode, room_type)),
    ]
    present = [(name, txt) for name, txt in sections if txt and txt.strip()]
    prompt = "\n\n".join(txt for _, txt in present)

    log.info(
        "[ComposerV2] mode=%s  size=%d  sections=%d  present=%s",
        edit_mode.value, len(prompt), len(present),
        [name for name, _ in present],
    )
    return prompt
