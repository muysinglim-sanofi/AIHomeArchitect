"""
Persistent Apartment Structural Identity — Wave 4.7.2.

PROBLEM (diagnosed in Wave 4.7.1):
  Under mobile_mvp_baseline, vision_analysis_fv=False -> room_description="" for
  V1 -> detect_anchors("") returns empty -> the Wave 4.7.1 architectural anchor
  system is INERT for FIRST_VISION on the profile we actively test. V1 runs on
  generic abstract preservation wording with zero concrete structural facts, so
  the model regresses the bay window toward its aesthetic prior.

SOLUTION:
  Capture the apartment's architectural identity ONCE (at V1 / session creation),
  persist it (client round-trip token — same pattern as `history` and
  `original_image_url`), and inject it deterministically into V1/V2/V3 forever.
  This converts text control from generic -> specific WITHOUT per-generation
  vision analysis and WITHOUT any runtime-heavy or provider-locked machinery.

PROVIDER-AGNOSTIC BY DESIGN:
  This module contains NO model calls and NO provider SDK imports. It is:
    - a frozen dataclass of architecture-only facts
    - a deterministic text -> identity parser (reuses anchor_detector regexes)
    - a concise declarative renderer
    - a tiny JSON serialize/deserialize for session persistence
  The one-time capture (which may use a vision model as a text source) lives in
  the runtime layer (main.py) and feeds its short text through this module's
  deterministic parser. Swapping providers = swapping that single function.

TASK 6 (no generation-authority leak):
  Identity describes ONLY what already exists architecturally. A defensive
  sanitiser drops any candidate fact containing atmosphere / decor / furniture /
  emotional / premium vocabulary, so the identity can never become implicit
  scene-generation, styling, or redesign authority.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, asdict, fields

from .anchor_detector import _PARTITION, _DEPTH, _OPENING  # deterministic regexes


# ── Identity object ───────────────────────────────────────────────────────────

@dataclass(frozen=True)
class ApartmentStructuralIdentity:
    """
    Lightweight, architecture-ONLY identity of the uploaded apartment.
    Every field is a short factual phrase or "" (absent). No atmosphere,
    no decor, no furniture, no emotion, no premium language — ever.
    """
    dominant_opening: str = ""        # e.g. "wide full-height bay window dominating the rear wall"
    opening_layout: str = ""          # e.g. "secondary window pair on the left"
    glass_partition: str = ""         # e.g. "black-framed glass partition separating the living zone"
    room_depth_type: str = ""         # e.g. "deep diagonal perspective toward the kitchen"
    kitchen_visibility: str = ""      # e.g. "open kitchen visible on the right"
    anchor_relationships: str = ""    # e.g. "bay window centred between partition and kitchen opening"

    @property
    def is_present(self) -> bool:
        return any(getattr(self, f.name) for f in fields(self))

    @property
    def fact_count(self) -> int:
        return sum(1 for f in fields(self) if getattr(self, f.name))


EMPTY_IDENTITY = ApartmentStructuralIdentity()


# ── Task 6: generation-authority leak guard ──────────────────────────────────
# Any candidate fact containing one of these is dropped. Identity must remain
# purely architectural — never styling / atmosphere / furniture / emotion.
_BANNED_SUBSTR = (
    "luxury", "premium", "warm", "cozy", "cosy", "elegant", "aspiration",
    "atmosphere", "mood", "ambience", "ambiance", "style", "restyle",
    "redesign", "reimagine", "generate", "compose", "decor", "decorate",
    "furnish", "furniture", "sofa", "armchair", "couch", "cushion", "rug",
    "lamp", "lighting", "plant", "textile", "velvet", "marble", "bouclé",
    "boucle", "wow", "hospitality", "designer", "opulent", "sophisticat",
)


def _clean(text: str) -> str:
    """Normalise whitespace; drop the fact entirely if it carries banned vocab."""
    if not text:
        return ""
    t = " ".join(str(text).split()).strip().strip(".,;|")
    if not t:
        return ""
    low = t.lower()
    if any(b in low for b in _BANNED_SUBSTR):
        return ""  # leak guard: architectural facts only
    return t[:90]  # per-fact hard cap (Task 5: no bloat)


# ── Deterministic text -> identity (provider-agnostic, zero model) ───────────

def extract_from_description(room_description: str) -> ApartmentStructuralIdentity:
    """
    Build an ApartmentStructuralIdentity from any structural text using the
    SAME deterministic regexes anchor_detector uses. No model call. Returns
    EMPTY_IDENTITY when nothing architectural is detected.
    """
    if not room_description or not room_description.strip():
        return EMPTY_IDENTITY

    text = room_description.strip()
    low = text.lower()

    # Dominant opening — prefer the strongest, most identity-defining opening.
    dominant = ""
    for key in (
        "bay window", "panoramic window", "floor-to-ceiling window",
        "corner window", "glazed wall", "glazed facade", "picture window",
    ):
        if key in low:
            qualifier = ""
            for q in ("wide", "large", "tall", "full-height", "dominant", "dominating"):
                if q in low:
                    qualifier = q + " "
                    break
            dominant = f"{qualifier}{key} as the apartment's primary opening"
            break
    if not dominant:
        m = _OPENING.search(text)
        if m:
            dominant = f"{m.group().strip().lower()} as a primary opening"

    # Opening layout — Wave 4.7.5b: express RELATIONSHIP/CONTINUITY, not bare
    # position. The old "a secondary window pair on the left" stated only where
    # the secondary opening was, so the model treated it as a compositionally
    # optional element and dropped it. Length-neutral rewording (~±1 char, zero
    # V1 budget impact even at Soft Luxury's 6-char headroom) that binds the
    # secondary opening to the SAME continuous open facade as the primary one.
    layout = ""
    if "pair" in low or "two windows" in low or "two large windows" in low:
        layout = "secondary opening, same open facade"
    elif "windows" in low and ("left" in low or "right" in low):
        layout = "more windows on the same open facade"

    # Glass partition.
    partition = ""
    mp = _PARTITION.search(text)
    if mp:
        partition = f"{mp.group().strip().lower()} as a fixed structural divider"

    # Room depth type.
    depth = ""
    md = _DEPTH.search(text)
    if md:
        depth = f"{md.group().strip().lower()} defining the spatial volume"
    elif "open-plan" in low or "open plan" in low or "open concept" in low:
        depth = "open-plan spatial volume"

    # Kitchen visibility.
    kitchen = ""
    if "kitchen" in low and ("visible" in low or "open kitchen" in low or "connected" in low):
        side = ("on the right" if "right" in low else
                "on the left" if "left" in low else "")
        kitchen = f"open kitchen visible {side}".strip()

    # Anchor relationship — only assert when two strong anchors co-exist.
    rel = ""
    if dominant and partition:
        rel = "the primary opening and the glass divider hold fixed relative positions"
    elif dominant and kitchen:
        rel = "the primary opening and the kitchen opening hold fixed relative positions"

    identity = ApartmentStructuralIdentity(
        dominant_opening=_clean(dominant),
        opening_layout=_clean(layout),
        glass_partition=_clean(partition),
        room_depth_type=_clean(depth),
        kitchen_visibility=_clean(kitchen),
        anchor_relationships=_clean(rel),
    )
    return identity if identity.is_present else EMPTY_IDENTITY


# ── Session persistence (client round-trip token) ────────────────────────────

def to_token(identity: ApartmentStructuralIdentity) -> str:
    """Compact JSON token persisted client-side and echoed back on V2/V3/V4."""
    if not identity or not identity.is_present:
        return ""
    return json.dumps(asdict(identity), separators=(",", ":"), ensure_ascii=False)


def from_token(token: str) -> ApartmentStructuralIdentity:
    """Parse a persisted token. Tolerant: malformed/empty -> EMPTY_IDENTITY."""
    if not token or not token.strip():
        return EMPTY_IDENTITY
    try:
        data = json.loads(token)
        if not isinstance(data, dict):
            return EMPTY_IDENTITY
        allowed = {f.name for f in fields(ApartmentStructuralIdentity)}
        # Re-sanitise on the way in (defence in depth — never trust the wire).
        clean = {k: _clean(str(v)) for k, v in data.items() if k in allowed}
        identity = ApartmentStructuralIdentity(**clean)
        return identity if identity.is_present else EMPTY_IDENTITY
    except (ValueError, TypeError):
        return EMPTY_IDENTITY


# ── Concise declarative renderer (Task 3 / 5 / 6) ────────────────────────────

# Priority order for trimming when over the char cap (least identity-defining
# dropped first). The dominant opening is NEVER dropped.
_RENDER_ORDER = (
    "dominant_opening",
    "glass_partition",
    "room_depth_type",
    "opening_layout",
    "kitchen_visibility",
    "anchor_relationships",
)
# Wave 5.5.10b (2026-05-21) — raised 360 → 460 so the clause can render 4
# parser-captured facts simultaneously (dominant_opening + glass_partition +
# room_depth_type + kitchen_visibility). Before the bump, Wave 5.5.10's new
# dominant_opening capture (e.g. "large floor-to-ceiling sliding glass door...")
# was filling the 360-char budget and pushing kitchen_visibility OUT of the
# rendered clause — a regression on the user's #1 concern (kitchen preservation).
# anchor_relationships (the 5th fact) still drops at this budget level since
# it's redundant with the implicit pairing of dominant+partition in adjacent
# facts. Trade-off: composer.py V1 prompt grows by ~80-100 chars, which may
# cause visible_spaces (P5) or natural_enrichment (P4) to drop on tight
# atmospheres. Kitchen is preserved in STRUCTURAL_IDENTITY (P1, never drops)
# regardless. Rollback = revert to 360.
_MAX_CLAUSE_CHARS = 460


def render_clause(identity: ApartmentStructuralIdentity, mode: str = "V1") -> str:
    """
    Render the persistent identity as a concise P1 declarative-facts clause.

    DESCRIPTIVE FACTS, never generation instructions ("this apartment already
    contains ..." NOT "generate a bay window ..."). For V3 a single clause
    permits change ONLY for the explicitly requested structural edit.
    Returns "" when no identity is present (graceful — zero prompt cost).
    """
    if not identity or not identity.is_present:
        return ""

    facts = [getattr(identity, name) for name in _RENDER_ORDER if getattr(identity, name)]
    prefix = ("STRUCTURAL IDENTITY — this apartment already contains these "
              "architectural facts; reproduce them exactly, do not normalize, "
              "narrow, or restyle them: ")
    suffix = ". These are existing structural truths, not design choices."
    if mode == "V3":
        suffix += " Only the explicitly requested structural change may alter them."

    body = "; ".join(facts)
    clause = prefix + body + suffix
    while len(clause) > _MAX_CLAUSE_CHARS and len(facts) > 1:
        facts = facts[:-1]  # drop least identity-defining fact
        body = "; ".join(facts)
        clause = prefix + body + suffix
    return clause if len(clause) <= _MAX_CLAUSE_CHARS else (prefix + facts[0] + suffix)


# ── Structural NEGATIVE anchors (Wave 4.7.4) ─────────────────────────────────
#
# Positive preservation ("preserve the openings") leaves residual ambiguity:
# the model still randomly walls-off the bay window, compartmentalises the open
# facade, or converts glass continuity into decorative wall planes — especially
# under wall-symmetry-leaning atmospheres (Warm Modern / Soft Luxury).
#
# Negative anchors declare, in topology terms, what must NOT become a wall.
# Architecture-only, leak-guarded (reuses _clean / _BANNED_SUBSTR), compact.
# Derived ONLY from the persistent identity — never atmosphere/decor/furniture.

# One compact clause group. Deliberately does NOT re-enumerate each opening
# (structural_identity already does — avoids redundancy/contradiction and keeps
# the tight STYLE_REFINEMENT budget intact). Covers every observed failure mode:
# walling-off an opening, compartmentalising the open facade, glass->wall, and
# atmosphere-driven facade restructuring (Task 4).
# NOTE: Task 4 (prevent atmosphere-driven facade restructuring) is expressed
# WITHOUT the words "atmosphere"/"styling"/"aesthetic" so it stays within
# Task 7's architecture-only purity and passes the strict _leaks guard.
_NEG_CORE = (
    "Photographed openings/glass are open space, NOT walls. Do not insert "
    "walls between them, compartmentalize the open facade, or close glass "
    "continuity. The applied treatment must adapt to the photographed "
    "architecture and must not restructure the facade."
)
_NEG_MAX_SECTION = 450  # Task 5 hard ceiling


def render_negative_anchors(identity: ApartmentStructuralIdentity) -> str:
    """
    Wave 4.7.4 — STRUCTURAL NEGATIVE ANCHORS section (P1, V1/V2/V3).

    A single compact "open space is NOT a wall" topology rule, emitted only when
    a persistent identity exists (Task 6 — "" / zero cost on a no-anchor
    apartment). Architecture-only and leak-guarded; never re-lists individual
    openings (structural_identity owns the positive enumeration), so it adds
    negative topology protection without bloat, redundancy, or contradiction.
    """
    if not identity or not identity.is_present:
        return ""
    section = "STRUCTURAL NEGATIVE ANCHORS — " + _NEG_CORE
    if _leaks(section):  # defence in depth (the fixed text is architecture-only)
        return ""
    return section[:_NEG_MAX_SECTION]


def _leaks(text: str) -> bool:
    """True if any banned (non-architectural) vocab is present."""
    low = text.lower()
    return any(b in low for b in _BANNED_SUBSTR)
