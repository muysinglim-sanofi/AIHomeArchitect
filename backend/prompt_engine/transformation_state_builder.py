"""
transformation_state_builder.py — Wave 3.4.1 transformation state extraction.

Converts raw user instructions into clean, grammatical text for:
  - Vision captions (short, human-readable result messages)
  - Prompt injection (clean instructions without raw user fragments)

Prevents malformed user text from polluting prompts and captions.
The frozen composer.py is never touched — this layer wraps above it.

Two core functions:
  build_vision_caption()     — clean caption for the vision result message
  build_clean_instruction()  — clean instruction text for prompt injection
"""

from __future__ import annotations
import re
from .transformation_classifier import TransformationType


# ── Text cleaning helpers ─────────────────────────────────────────────────────

_LEADING_JUNK = re.compile(
    r"^(and|but|or|also|then|so|now|well|okay|ok|please|can\s+you|could\s+you|"
    r"would\s+you|i\s+want\s+(you\s+to\s+)?|i\s+need\s+you\s+to\s+|"
    r"i\s+would\s+like\s+(you\s+to\s+)?)[,\s]*",
    re.IGNORECASE,
)
_DOUBLE_SPACE = re.compile(r"\s{2,}")
_TRAILING_PUNCT = re.compile(r"[,;:]+$")
# Strip relative/subordinate clauses that produce malformed caption fragments
# e.g. "show me the room where there is a 2 chairs" → strips "where there is..."
_RELATIVE_CLAUSE = re.compile(
    r"\s+(?:where|when|because|which|that|who|whose|whom)\s+.+$",
    re.IGNORECASE,
)


def _clean_text(text: str, max_len: int = 70) -> str:
    """Clean raw instruction text for safe use in captions and prompts."""
    if not text:
        return ""
    text = text.strip()
    text = _LEADING_JUNK.sub("", text)
    text = _RELATIVE_CLAUSE.sub("", text)
    text = _DOUBLE_SPACE.sub(" ", text).strip()
    text = _TRAILING_PUNCT.sub("", text).strip()
    if len(text) > max_len:
        truncated = text[:max_len]
        last_space = truncated.rfind(" ")
        if last_space > max_len // 2:
            truncated = truncated[:last_space]
        text = truncated
    if text:
        text = text[0].upper() + text[1:]
    return text


# ── Caption templates ─────────────────────────────────────────────────────────

_CAPTIONS_EN: dict[TransformationType, str] = {
    TransformationType.ATMOSPHERE_SWITCH:       "Vision {n} — {atm} interpretation applied, same layout.",
    TransformationType.FUNCTIONAL_REASSIGNMENT: "Vision {n} — zone reassigned, structure preserved.",
    TransformationType.STRUCTURAL_CHANGE:       "Vision {n} — architectural edit applied.",
    TransformationType.LAYOUT_REINTERPRETATION: "Vision {n} — layout reinterpreted, shell unchanged.",
}

_CAPTIONS_FR: dict[TransformationType, str] = {
    TransformationType.ATMOSPHERE_SWITCH:       "Vision {n} — interprétation {atm} appliquée, même disposition.",
    TransformationType.FUNCTIONAL_REASSIGNMENT: "Vision {n} — zones réaffectées, architecture préservée.",
    TransformationType.STRUCTURAL_CHANGE:       "Vision {n} — modification architecturale appliquée.",
    TransformationType.LAYOUT_REINTERPRETATION: "Vision {n} — disposition réinterprétée, coque inchangée.",
}


def build_vision_caption(
    user_instruction: str,
    transformation_type: TransformationType,
    iteration: int,
    atmosphere_id: str = "",
    language: str = "en",
) -> str:
    """
    Generate a clean, grammatical caption for a vision result.

    Uses type-specific templates to prevent raw user fragments from
    appearing in captions. Falls back to cleaned instruction text only
    for STYLE_REFINEMENT and OBJECT_EDIT (inherently instruction-specific).
    """
    atm_label = atmosphere_id.replace("_", " ").title() if atmosphere_id else ""
    templates = _CAPTIONS_FR if language == "fr" else _CAPTIONS_EN

    template = templates.get(transformation_type)
    if template:
        return template.format(n=iteration, atm=atm_label or "new")

    # STYLE_REFINEMENT, OBJECT_EDIT, UNKNOWN — use cleaned instruction
    clean = _clean_text(user_instruction, max_len=65)
    if not clean:
        if language == "fr":
            return f"Vision {iteration} — direction affinée."
        return f"Vision {iteration} — direction refined."

    # Lowercase first char for mid-sentence insertion
    body = clean[0].lower() + clean[1:]
    return f"Vision {iteration} — {body}."


# ── Instruction cleaning ──────────────────────────────────────────────────────

_FUNC_ZONE_RE = re.compile(
    r"\b(make|turn|convert|use|repurpose|transform)\b.{0,40}\b(into|as|a)\b",
    re.IGNORECASE,
)


def build_clean_instruction(
    user_instruction: str,
    transformation_type: TransformationType,
) -> str:
    """
    Return a cleaned version of the user instruction for prompt injection.

    For FUNCTIONAL_REASSIGNMENT: appends explicit zone preservation language
    to prevent the model from collapsing or merging zones.
    For others: returns lightly cleaned text (spatial addendum handles the rest).
    """
    if not user_instruction.strip():
        return ""

    cleaned = _DOUBLE_SPACE.sub(" ", user_instruction.strip())

    if transformation_type == TransformationType.FUNCTIONAL_REASSIGNMENT:
        return (
            f"{cleaned} "
            "Preserve BOTH the source zone and the target zone — do not merge or "
            "collapse them. Each zone must remain spatially distinct, visually readable, "
            "and must LOOK like it genuinely serves its new function. "
            "All architectural elements (walls, openings, windows) remain fixed in position."
        )

    return cleaned
