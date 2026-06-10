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
            # Wave 5.21d (2026-06-02) — capture the wall position when gpt-4o
            # reports it. The capture prompt at main.py:496-502 instructs the
            # model to "state the wall (left/right/back)" but the parser
            # previously dropped that signal, leaving the gpt-image-1 prompt
            # without a spatial anchor for the primary opening. The position
            # search is bounded to the SAME sentence/bucket as the key
            # (stops at the next period or newline) so a position belonging
            # to a downstream bucket (interior_door, fixed_built_in, AC,
            # etc.) cannot bleed into the dominant_opening clause.
            position = ""
            key_pos = low.find(key)
            if key_pos >= 0:
                tail = low[key_pos:]
                boundary = re.search(r"[.\n]", tail)
                end = boundary.start() if boundary else len(tail)
                bucket_neighborhood = tail[:end]
                pos_match = re.search(
                    r"\b(left|right|back|front)\s+wall\b",
                    bucket_neighborhood,
                )
                if pos_match:
                    position = f" on the {pos_match.group(1)} wall"
            dominant = (
                f"{qualifier}{key} as the apartment's primary opening{position}"
            )
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
        matched = md.group().strip().lower()
        # Wave 5.25 (2026-06-03) — empirical bench V1 WM (8 generations,
        # same source photo) showed 100% correlation between gpt-4o
        # capturing "diagonal X" (depth / perspective / view / line /
        # axis / composition) and wall invention on the V1 render. Root
        # cause : the word "diagonal" reads as a GEOMETRIC DIRECTIVE to
        # gpt-image-1 (render with diagonal architecture), not as a
        # neutral depth descriptor — and the model "completes" the
        # diagonality by inventing a partition/wall.
        # Fix : normalize any "diagonal X" capture to the neutral
        # "spatial depth defining the spatial volume" wording. Same
        # concept (room has depth), zero geometric ambiguity.
        # Trade-off : we lose the "diagonal" qualifier nuance, but on
        # this benchmark photo it was a faux-ami descriptor — empirical
        # output was worse with it kept (2/8 walls) than normalized
        # (target 0/8). Universal fix, no atmosphere-specific gating.
        if matched.startswith("diagonal"):
            depth = "spatial depth defining the spatial volume"
        else:
            depth = f"{matched} defining the spatial volume"
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
    # Wave 6.13d (C1, 2026-06-05) — tolerate a closing label-quote after "door".
    # gpt-4o frequently emits the door as a quoted label, e.g.
    #   "(4) Interior door — 'wooden door' visible on the left wall."
    # The closing quote after "door" previously blocked the (visible)? and
    # (on the … wall)? groups, so the door's WALL POSITION was DROPPED entirely
    # (door shipped as a bare "fixed wall feature" with no anchor → the model
    # was free to relocate it → observed right-drift on WM kitchen). The optional
    # ['’‘"] consumes that quote so the position is recovered; stray quotes are
    # scrubbed from the emitted clause. Purely additive — unquoted captures and
    # already-anchored doors stay byte-identical (proven by the 6.13d snapshot).
    _door_specific = re.search(
        r"\b(two|three|multiple)?\s*"
        r"(wooden|painted)\s+door[s]?['’‘\"]?"
        r"(\s+visible)?"
        r"(\s+on\s+the\s+(upper[\s-])?(left|right|back|front)(\s+wall)?)?",
        text, re.IGNORECASE,
    )
    if _door_specific:
        interior_door = (
            re.sub(r"['’‘\"]", "", _door_specific.group(0)).strip().lower()
            + " as a fixed wall feature"
        )
    else:
        _door_generic = re.search(
            r"\b(two|three|multiple)?\s*"
            r"interior\s+door[s]?['’‘\"]?"
            r"(\s+visible)?"
            r"(\s+on\s+the\s+(upper[\s-])?(left|right|back|front)(\s+wall)?)?",
            text, re.IGNORECASE,
        )
        if _door_generic:
            interior_door = (
                re.sub(r"['’‘\"]", "", _door_generic.group(0)).strip().lower()
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
        # Wave 5.20 (2026-06-01) — Prompt Authority Consolidation.
        # Compacted prefix/suffix while preserving the DESCRIPTIVE framing
        # anchor ("this apartment's photographed facts") from Wave 4.7.2.
        # Parenthetical instructions keep all preservation negations
        # ("do not normalize, narrow, or restyle"). V3 suffix unchanged
        # — "explicitly" is a critical V3 anchor for permitted structural
        # changes and must not be softened.
        prefix = ("STRUCTURAL IDENTITY — this apartment's photographed "
                  "facts (reproduce exactly, do not normalize, narrow, "
                  "or restyle): ")
        suffix = ". Existing structural facts — not design choices."
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
    # Wave 5.20 (2026-06-01) — Prompt Authority Consolidation.
    # Trimmed redundancies with the mode_contract preamble (lives in
    # preservation.py) which already says "blocked, replaced by a wall
    # surface" (covers "Do not insert walls between them"), "doors stay
    # exact" (covers Wave 5.19 "interior doors"), and "Do not add,
    # remove, resize, relocate, reinterpret, or redesign" (covers
    # "relocate, remove"). What stays here is the UNIQUE negative
    # topology framing ("open space, NOT walls" + facade-restructuring
    # ban) and the Wave 5.19 fixed-features list MINUS interior_door.
    "Photographed openings/glass are open space, NOT walls — do not "
    "compartmentalize the open facade or close glass continuity. "
    "The applied treatment must adapt to the photographed architecture "
    "and must not restructure the facade. "
    # Wave 5.19 (2026-06-01) — fixed-features preservation rule.
    # Covers the Structural Capture fields interior_door, fixed_built_in,
    # vertical_circulation, ceiling_signature, fixed_appliance.
    # Wave 5.20 (2026-06-01) Option β — interior_doors INTENTIONALLY kept
    # in the fixed-features list despite preamble coverage of "doors stay
    # exact". Rationale : multi-layer redundancy on door preservation
    # (Wave 5.19 was a dedicated wave for this single feature). In the
    # corner case where gpt-4o capture misses a visible door (partially
    # occluded, painted to match wall, marginal in frame), the preamble's
    # single-word "doors" mention becomes the only protection. Keeping
    # the explicit NEG_CORE enumeration provides a second emphatic layer
    # that survives capture failure. Net savings : 16 chars sacrificed
    # to preserve door authority — favorable trade-off.
    "Photographed fixed features (interior doors, built-ins, staircases, "
    "exposed beams, wall-mounted fixtures) stay in place — do not cover "
    "or convert into wall surface."
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


# ── Wave 5.24 — Safe Union Merge (parallel structural capture) ────────────────
#
# Empirical correlation analysis on 16 V1 captures (2026-06-03) revealed :
#
#   3 facts captured → 40% wall invention rate
#   4 facts captured → 20%
#   5+ facts        → 0%
#
# Root cause : gpt-4o structural capture is stochastic in WHICH features it
# notices on a given image. Same photo → 3 facts in one call, 5 in another.
# Sparse captures leave gpt-image-1 under-constrained → it invents walls to
# "complete" the architecture (especially around the TV anchor).
#
# Wave 5.24 fix : run 2 full captures in parallel (via asyncio.gather in
# main.py), parse each independently, then merge with SAFE UNION semantics —
# additive on complementary facts, conflict-safe on contradictions.
#
# Field-merge policy :
#   • Both empty       → empty
#   • One empty        → take the non-empty (additive enrichment)
#   • Both identical   → keep (no-op)
#   • Both different :
#     - POSITION-bearing fields (dominant_opening, interior_door, etc.) →
#       check if they differ only in " on the X wall" suffix. If yes, strip
#       the position and keep the base description. If the base differs too,
#       drop entirely (real contradiction).
#     - Other fields → drop entirely (safer than picking a wrong fact).
#
# Principle : missing fact > wrong fact. Never let a contradictory spatial
# claim reach gpt-image-1.

# Fields that may legitimately contain " on the X wall" / " on the right"
# position suffixes captured by the parser. These get the strip-on-conflict
# treatment ; other fields drop entirely on disagreement.
_POSITION_BEARING_FIELDS = frozenset({
    "dominant_opening",
    "interior_door",
    "kitchen_visibility",
    "fixed_appliance",
    "vertical_circulation",
    "surface_transition",
    "fixed_built_in",
})

# Strip " on the (left|right|back|front)[ wall]" + the upper-* variants the
# interior_door extractor produces (Wave 5.21d).
_POSITION_STRIP_RE = re.compile(
    r"\s+on the\s+(?:upper[\s-]?)?(?:left|right|back|front)(?:\s+wall)?\b",
    flags=re.IGNORECASE,
)


def _strip_position(s: str) -> str:
    """Remove the trailing position phrase (if any) and tidy whitespace."""
    return _POSITION_STRIP_RE.sub("", s).strip().rstrip(",").rstrip(";")


def safe_union_merge(
    a: ApartmentStructuralIdentity,
    b: ApartmentStructuralIdentity,
) -> tuple[ApartmentStructuralIdentity, dict[str, str]]:
    """Wave 5.24 — safe-union merge of two parsed structural identities.

    Returns (merged_identity, per-field-decisions). Decisions :
      - 'identical'                  : both captures agreed (or both empty)
      - 'additive_a' / 'additive_b'  : one had the fact, the other empty
      - 'contradict_position_stripped': same base description, different
                                        position suffix → kept base, dropped
                                        position (safer than wrong direction
                                        — applies to SPATIAL info only)
      - 'kept_a_longer'              : non-empty disagreement → kept the
                                        longer / first-capture variant
                                        (preserves at least one descriptor —
                                        empirical learning : dropping a fact
                                        causes MORE wall invention than
                                        keeping a slightly-imperfect one)

    Wave 5.24 (post first-empirical-fix 2026-06-03 12:45) : the original
    "drop on disagreement" policy regressed wall invention rate from 3/8
    to 6/8 on SL bench. Root cause : non-spatial disagreements (e.g.,
    'spatial depth' vs 'open-plan' on room_depth_type) were treated like
    real contradictions and the field was dropped — gpt-image-1 received
    LESS architectural context than from a single capture. New policy
    only strips POSITION on position-bearing fields with same base ;
    every other disagreement keeps the longer descriptor.
    """
    from dataclasses import fields as dc_fields, replace

    merged_values: dict[str, str] = {}
    decisions: dict[str, str] = {}

    for f in dc_fields(a):
        a_val = (getattr(a, f.name, "") or "").strip()
        b_val = (getattr(b, f.name, "") or "").strip()

        if not a_val and not b_val:
            merged_values[f.name] = ""
            decisions[f.name] = "identical"
            continue

        if a_val == b_val:
            merged_values[f.name] = a_val
            decisions[f.name] = "identical"
            continue

        if not a_val:
            merged_values[f.name] = b_val
            decisions[f.name] = "additive_b"
            continue

        if not b_val:
            merged_values[f.name] = a_val
            decisions[f.name] = "additive_a"
            continue

        # Both non-empty and different.
        # Position-bearing fields : try to strip the conflicting position
        # (LEFT vs RIGHT is the high-risk pattern — missing > wrong here).
        if f.name in _POSITION_BEARING_FIELDS:
            a_base = _strip_position(a_val)
            b_base = _strip_position(b_val)
            if a_base and a_base == b_base:
                merged_values[f.name] = a_base
                decisions[f.name] = "contradict_position_stripped"
                continue

        # Different base content OR non-position-bearing field disagreement.
        # Wave 5.24 fix : DO NOT drop. Keep the longer descriptor — it
        # usually carries more detail, and any fact is better than nothing
        # for gpt-image-1's architectural grounding (empirical : 3 facts =
        # 40% wall invention, 5+ facts = 0%).
        chosen = a_val if len(a_val) >= len(b_val) else b_val
        merged_values[f.name] = chosen
        decisions[f.name] = "kept_a_longer" if chosen is a_val else "kept_b_longer"

    return replace(a, **merged_values), decisions
