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
import re  # Wave 5.19 — per-bucket extractors use re.search for vocabulary matching
from dataclasses import dataclass, asdict, fields

from .anchor_detector import _PARTITION, _DEPTH, _OPENING  # deterministic regexes


# ── Identity object ───────────────────────────────────────────────────────────

@dataclass(frozen=True)
class ApartmentStructuralIdentity:
    """
    Lightweight, architecture-ONLY identity of the uploaded apartment.
    Every field is a short factual phrase or "" (absent). No atmosphere,
    no decor, no furniture, no emotion, no premium language — ever.

    Wave 5.19 (2026-06-01) — Structural Capture Enrichment :
    6 new fields added to capture architectural features previously
    invisible to the parser (interior doors, built-ins, staircases,
    ceiling signatures, surface transitions, fixed wall fixtures).
    Backward compat : older tokens (6-field) load cleanly via from_token
    which filters by `fields(ApartmentStructuralIdentity)` — the 6 new
    fields default to "" when absent from JSON.
    """
    # ── Original Wave 4.7.2 ───────────────────────────────────────────
    dominant_opening: str = ""        # e.g. "wide full-height bay window dominating the rear wall"
    opening_layout: str = ""          # e.g. "secondary window pair on the left"
    glass_partition: str = ""         # e.g. "black-framed glass partition separating the living zone"
    room_depth_type: str = ""         # e.g. "deep diagonal perspective toward the kitchen"
    kitchen_visibility: str = ""      # e.g. "open kitchen visible on the right"
    anchor_relationships: str = ""    # e.g. "bay window centred between partition and kitchen opening"
    # ── Wave 5.19 — Structural Capture Enrichment ─────────────────────
    interior_door: str = ""           # e.g. "wooden door visible on the back-left wall"
    fixed_built_in: str = ""          # e.g. "fireplace alcove on the right wall"
    vertical_circulation: str = ""    # e.g. "open staircase visible on the right"
    ceiling_signature: str = ""       # e.g. "exposed wooden beam parallel to the back wall"
    surface_transition: str = ""      # e.g. "raised step into the rear zone"
    fixed_appliance: str = ""         # e.g. "wall-mounted AC unit on the upper-left wall"

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
    # Wave 5.13g+ (2026-05-27) — added "sliding glass door" and "patio door"
    # to the recognised vocabulary. gpt-4o correctly classifies the benchmark
    # apartment's primary opening as a sliding glass door (verified via raw
    # capture log), but the previous whitelist dropped that classification →
    # dominant_opening was missing from PHOTO FACTS for every preserve-mode
    # session, leaving the model without a back-wall anchor and triggering
    # wall invention on strong-identity atmospheres (SL/Nordic/Desert).
    # Door types listed FIRST so they win over "glass" sub-matches.
    dominant = ""
    for key in (
        "sliding glass door", "patio door",
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

    # ── Wave 5.19 — Structural Capture Enrichment extractors ─────────────────
    # Each extractor matches the EXACT vocabulary asked from gpt-4o in
    # main.py::_capture_structural_text. Hallucinations that don't match
    # the vocabulary are filtered out silently (parser deterministic guard).
    # Wording is preserved in present-tense fact form so the downstream
    # STRUCTURAL IDENTITY clause reads naturally.

    # (1) Interior door — wooden/painted (non-glass). Position preserved.
    # EXCLUDES sliding/patio/glazed doors — those go to dominant_opening.
    # Two-tier search : prefer specific material+position matches over the
    # generic "interior door" label (gpt-4o bucket prefix "(4) Interior
    # door —" matches before the rich phrasing if we don't prioritize).
    interior_door = ""
    _door_specific = re.search(
        r"\b(two|three|multiple)?\s*"
        r"(wooden|painted)\s+door[s]?"
        r"(\s+visible)?"
        r"(\s+on\s+the\s+(upper[\s-])?(left|right|back|front)(\s+wall)?)?",
        text, re.IGNORECASE,
    )
    if _door_specific:
        interior_door = (
            _door_specific.group(0).strip().lower()
            + " as a fixed wall feature"
        )
    else:
        _door_generic = re.search(
            r"\b(two|three|multiple)?\s*"
            r"interior\s+door[s]?"
            r"(\s+visible)?"
            r"(\s+on\s+the\s+(upper[\s-])?(left|right|back|front)(\s+wall)?)?",
            text, re.IGNORECASE,
        )
        if _door_generic:
            interior_door = (
                _door_generic.group(0).strip().lower()
                + " as a fixed wall feature"
            )

    # (2) Fixed built-in — fireplace / alcove / niche / built-in cabinetry / island.
    built_in = ""
    for key in (
        "fireplace", "kitchen island", "floating cabinetry",
        "recessed shelving", "built-in shelving", "built-in",
        "alcove", "niche", "mantel", "hearth", "bookshelf",
    ):
        if key in low:
            _bi_pat = re.search(
                rf"\b{re.escape(key)}\b"
                rf"(\s+on\s+the\s+(upper[\s-])?(left|right|back)(\s+wall)?)?",
                text, re.IGNORECASE,
            )
            if _bi_pat:
                built_in = (
                    _bi_pat.group(0).strip().lower()
                    + " as a fixed architectural feature"
                )
                break

    # (3) Vertical circulation — staircase / mezzanine / loft.
    stair = ""
    for key in (
        "spiral stair", "floating stair", "open staircase",
        "staircase", "mezzanine", "loft level", "gallery floor",
        "gallery level",
    ):
        if key in low:
            _st_pat = re.search(
                rf"\b{re.escape(key)}\b"
                rf"(\s+(visible|on)\s+the\s+(left|right|back|center))?",
                text, re.IGNORECASE,
            )
            if _st_pat:
                stair = (
                    _st_pat.group(0).strip().lower()
                    + " as a fixed circulation feature"
                )
                break

    # (4) Ceiling signature — exposed beams, vaulted, cathedral, raised/lowered.
    ceiling_sig = ""
    _ceil_pat = re.search(
        r"\b("
        r"exposed\s+(wooden|timber|steel|concrete|wood)?\s*beam[s]?"
        r"|vaulted\s+ceiling"
        r"|cathedral\s+ceiling"
        r"|(raised|lowered)\s+ceiling(\s+section)?"
        r")\b",
        text, re.IGNORECASE,
    )
    if _ceil_pat:
        ceiling_sig = (
            _ceil_pat.group(0).strip().lower()
            + " defining the ceiling signature"
        )

    # (5) Surface transition — threshold / step / level change. Avoid
    # material names (e.g. "marble") which trigger the _BANNED_SUBSTR
    # leak guard ; describe BOUNDARIES instead.
    surface_trans = ""
    _surf_pat = re.search(
        r"\b("
        r"raised\s+step(\s+into\s+\w+\s+zone)?"
        r"|floor\s+level\s+change"
        r"|step\s+(up|down)\s+(into|to)\s+\w+"
        r"|split\s+level"
        r"|threshold\s+(at|between)\s+the\s+\w+"
        r"|material\s+change\s+at\s+the\s+\w+\s+threshold"
        r")\b",
        text, re.IGNORECASE,
    )
    if _surf_pat:
        surface_trans = (
            _surf_pat.group(0).strip().lower()
            + " marking the spatial boundary"
        )

    # (6) Fixed appliance — AC unit / radiator / wall heater.
    # Only when explicitly stated in raw_text. Position preserved if present.
    appliance = ""
    _app_pat = re.search(
        r"\b("
        r"(wall[-\s]mounted\s+)?ac\s+unit"
        r"|air\s+conditioner"
        r"|vertical\s+radiator"
        r"|wall\s+heater"
        r"|wall[-\s]mounted\s+(tv\s+bracket|mount)"
        r")\b"
        r"(\s+on\s+the\s+(upper[\s-])?(left|right|back)(\s+wall)?)?",
        text, re.IGNORECASE,
    )
    if _app_pat:
        appliance = (
            _app_pat.group(0).strip().lower()
            + " as a fixed wall fixture"
        )

    identity = ApartmentStructuralIdentity(
        # Original Wave 4.7.2
        dominant_opening=_clean(dominant),
        opening_layout=_clean(layout),
        glass_partition=_clean(partition),
        room_depth_type=_clean(depth),
        kitchen_visibility=_clean(kitchen),
        anchor_relationships=_clean(rel),
        # Wave 5.19 — Structural Capture Enrichment
        interior_door=_clean(interior_door),
        fixed_built_in=_clean(built_in),
        vertical_circulation=_clean(stair),
        ceiling_signature=_clean(ceiling_sig),
        surface_transition=_clean(surface_trans),
        fixed_appliance=_clean(appliance),
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
#
# Wave 5.19 (2026-06-01) — Structural Capture Enrichment ordering :
# new fields interleaved by preservation criticality.
#   • interior_door right after dominant_opening : porte oubliée = pire
#     regression observée (cf. Nordic 21:11:29 baseline) → priorité haute.
#   • fixed_built_in + vertical_circulation : architectural anchors lourds
#     qui définissent l'identité de la pièce.
#   • ceiling_signature : visible mais moins critique pour la
#     reconnaissance immédiate.
#   • surface_transition + fixed_appliance : last-resort, droppés en
#     premier si la clause sature.
_RENDER_ORDER = (
    "dominant_opening",          # critical — never drops
    "interior_door",             # Wave 5.19 — door preservation high prio
    "glass_partition",
    "fixed_built_in",            # Wave 5.19
    "vertical_circulation",      # Wave 5.19
    "room_depth_type",
    "ceiling_signature",         # Wave 5.19
    "opening_layout",
    "kitchen_visibility",
    "surface_transition",        # Wave 5.19 — droppable
    "fixed_appliance",           # Wave 5.19 — droppable
    "anchor_relationships",
)
# Wave 5.5.10b (2026-05-21) — raised 360 → 460.
# Wave 5.19 (2026-06-01) — raised 460 → 600 to accommodate the 6 new
# Structural Capture fields without forcing immediate trim. Net budget
# impact on STYLE_REFINEMENT prompts : +140 chars worst case. Empirically
# all live prompts stay under 4500 chars (well below gpt-image-1's effective
# ceiling). Rollback = revert to 460 ; new fields then drop first per
# _RENDER_ORDER without breaking the existing identity.
_MAX_CLAUSE_CHARS = 600


def render_clause(
    identity: ApartmentStructuralIdentity,
    mode: str = "V1",
    generation_mode: str = "preserve",
) -> str:
    """
    Render the persistent identity as a concise P1 declarative-facts clause.

    DESCRIPTIVE FACTS, never generation instructions ("this apartment already
    contains ..." NOT "generate a bay window ..."). For V3 a single clause
    permits change ONLY for the explicitly requested structural edit.
    Returns "" when no identity is present (graceful — zero prompt cost).

    Wave 5.5.14d — `generation_mode` softens the clause in creative mode
    (BIMODAL_ENABLED=1 + creative). The prefix changes from "reproduce them
    exactly" → "these are the starting points, may be reinterpreted
    creatively", and the suffix from "structural truths, not design choices"
    → "an architectural reference, not a constraint". The facts themselves
    stay (so the model has architectural memory of the space) but the
    surrounding language no longer forbids creative evolution.

    Default + preserve paths return the original Wave 4.7.2 string
    byte-for-byte (the function signature gains a keyword arg with a
    backward-compatible default).
    """
    if not identity or not identity.is_present:
        return ""

    # Lazy import — structural_identity sits alongside atmosphere_dna; do
    # not cross-trigger the registry at module load.
    from .atmosphere_dna.bimodal_classifier import is_creative_mode_active
    creative = is_creative_mode_active(generation_mode)

    facts = [getattr(identity, name) for name in _RENDER_ORDER if getattr(identity, name)]
    if creative:
        prefix = (
            "ARCHITECTURAL MEMORY — this space contains these photographed "
            "architectural facts as creative starting points; they may be "
            "reinterpreted to express the atmosphere's character: "
        )
        suffix = (
            ". Use them as an architectural reference, not as constraints."
        )
    else:
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
    "architecture and must not restructure the facade. "
    # Wave 5.19 (2026-06-01) — fixed-features preservation rule.
    # Covers the new Structural Capture fields (interior_door,
    # fixed_built_in, vertical_circulation, ceiling_signature,
    # fixed_appliance) which describe closed/solid architectural
    # elements that the open-space rule above does not protect.
    "Photographed fixed architectural features (interior doors, "
    "built-ins, staircases, exposed beams, wall-mounted fixtures) "
    "must remain in place — do not relocate, remove, cover, or "
    "convert them into wall surface."
)
# Wave 5.5.x : 450 chars ceiling.
# Wave 5.19 : raised 450 → 600 to fit the extended NEG_CORE (~440 chars
# of body + section header). The two-sentence structure (openings rule
# + fixed features rule) is intentional — single concatenation kept the
# emit/skip logic and the leak-guard machinery unchanged.
_NEG_MAX_SECTION = 600


def render_negative_anchors(
    identity: ApartmentStructuralIdentity,
    generation_mode: str = "preserve",
) -> str:
    """
    Wave 4.7.4 — STRUCTURAL NEGATIVE ANCHORS section (P1, V1/V2/V3).

    A single compact "open space is NOT a wall" topology rule, emitted only when
    a persistent identity exists (Task 6 — "" / zero cost on a no-anchor
    apartment). Architecture-only and leak-guarded; never re-lists individual
    openings (structural_identity owns the positive enumeration), so it adds
    negative topology protection without bloat, redundancy, or contradiction.

    Wave 5.5.14d — In creative mode (BIMODAL_ENABLED=1 + creative), the
    negative anchors block is dropped entirely. Creative mode explicitly
    allows the atmosphere to convert glass into walls or vice versa (e.g.
    Bali "open-pavilion" reinterpretation). Default + preserve paths keep
    the original Wave 4.7.4 behaviour.
    """
    if not identity or not identity.is_present:
        return ""
    from .atmosphere_dna.bimodal_classifier import is_creative_mode_active
    if is_creative_mode_active(generation_mode):
        return ""
    section = "STRUCTURAL NEGATIVE ANCHORS — " + _NEG_CORE
    if _leaks(section):  # defence in depth (the fixed text is architecture-only)
        return ""
    return section[:_NEG_MAX_SECTION]


def _leaks(text: str) -> bool:
    """True if any banned (non-architectural) vocab is present."""
    low = text.lower()
    return any(b in low for b in _BANNED_SUBSTR)
