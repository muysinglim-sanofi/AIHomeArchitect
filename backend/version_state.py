"""
Wave 4.7.3 — Architectural State Continuity & Version Source Selection.

Separates two concepts the system previously conflated:

  ARCHITECTURAL TRUTH  — the original uploaded photo + the persistent
                         ApartmentStructuralIdentity (Wave 4.7.2). Immutable
                         reference for windows / openings / partitions / depth.

  VISUAL/DESIGN SOURCE  — the image actually fed to images.edit. For V2+ this
                         is now the LATEST generated vision (design continuity),
                         NOT the original. Structural truth is still injected as
                         text so chaining from a generation does not lose the
                         apartment's architecture.

Pure state/string logic — NO model calls, NO provider SDK imports, NO runtime
escalation. Session state is client-held and round-tripped (same pattern as
`history`, `structural_identity`); the server stays stateless.
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, asdict, fields

# ── Source modes ──────────────────────────────────────────────────────────────

ORIGINAL = "ORIGINAL"
LATEST = "LATEST"
SPECIFIC_VERSION = "SPECIFIC_VERSION"
_VALID_MODES = {ORIGINAL, LATEST, SPECIFIC_VERSION}


# ── Version metadata (lightweight; Task 2) ───────────────────────────────────

@dataclass
class VersionRecord:
    version_id: str
    vision_number: int
    source_mode_used: str
    source_version_id_used: str
    source_image_url_used: str
    generated_image_url: str
    atmosphere: str
    user_request: str
    structural_permission: bool
    structural_identity_token: str


def new_version_id() -> str:
    """Stable, collision-resistant, client-opaque version id."""
    return "v_" + uuid.uuid4().hex[:12]


def parse_versions(raw: str) -> list[VersionRecord]:
    """Tolerant parse of the client-persisted versions list. Bad input -> []."""
    if not raw or not raw.strip():
        return []
    try:
        data = json.loads(raw)
    except (ValueError, TypeError):
        return []
    if not isinstance(data, list):
        return []
    allowed = {f.name for f in fields(VersionRecord)}
    out: list[VersionRecord] = []
    for d in data:
        if not isinstance(d, dict):
            continue
        c = {k: d.get(k) for k in allowed}
        try:
            out.append(VersionRecord(
                version_id=str(c.get("version_id") or ""),
                vision_number=int(c.get("vision_number") or 0),
                source_mode_used=str(c.get("source_mode_used") or ""),
                source_version_id_used=str(c.get("source_version_id_used") or ""),
                source_image_url_used=str(c.get("source_image_url_used") or ""),
                generated_image_url=str(c.get("generated_image_url") or ""),
                atmosphere=str(c.get("atmosphere") or ""),
                user_request=str(c.get("user_request") or ""),
                structural_permission=bool(c.get("structural_permission") or False),
                structural_identity_token=str(c.get("structural_identity_token") or ""),
            ))
        except (ValueError, TypeError):
            continue
    return out


def latest_atmosphere(versions: list[VersionRecord]) -> str:
    """The most-recently-recorded version's atmosphere label (reversed scan,
    skipping empties), or '' if the ledger has none.

    This is the LINEAR-chain case of `previous_atmosphere` (see below): on a
    straight V1→V2→V3 chain the tail IS the source being edited. For branching
    (continue-from-an-older-vision) the source is NOT the tail — use
    `atmosphere_for_version` keyed on the requested source_version_id instead.

    Why structural (not chat-text): the ledger always stores the RESOLVED
    atmosphere (VersionRecord.atmosphere = style_label), so it is language-proof
    and phrasing-proof — unlike the regex parse, which fails for AI-chosen
    atmospheres (Ayden Signature: greeting = "AI's choice", result message
    conversational)."""
    for v in reversed(versions):
        if v.atmosphere and v.atmosphere.strip():
            return v.atmosphere.strip()
    return ""


def atmosphere_for_version(versions: list[VersionRecord], version_id: str) -> str:
    """Atmosphere label of the record whose version_id == `version_id`, or ''
    if absent / not found.

    This is the SINGLE SOURCE OF TRUTH for "previous atmosphere" on a switch:
    the previous atmosphere is the atmosphere of the vision the new generation
    is edited FROM (the resolved source), NOT the most-recently-appended record.
    The two coincide on a linear chain but diverge under branching:

        V1(WM) → V2(Japandi) → V3(SoftLuxury)
        user "continue from V1" then switch → source = V1
            correct prev = Warm Modern (V1's atmosphere)
            tail would wrongly say Soft Luxury (V3)

    Caller passes the request's source_version_id (set only when the client
    pins a specific prior vision); on a linear LATEST switch this is empty and
    the caller falls back to latest_atmosphere(). VersionRecord already carries
    source_version_id_used (parent link), so deeper lineage walks are possible
    later without a schema change — not needed for direct-source prev."""
    vid = (version_id or "").strip()
    if not vid:
        return ""
    for v in versions:
        if v.version_id == vid:
            return (v.atmosphere or "").strip()
    return ""


def serialize_versions(versions: list[VersionRecord]) -> str:
    """Compact JSON for the client round-trip. Empty list -> ''."""
    if not versions:
        return ""
    return json.dumps([asdict(v) for v in versions],
                       separators=(",", ":"), ensure_ascii=False)


def version_to_dict(v: VersionRecord) -> dict:
    """Plain dict for the JSON response payload (provider-agnostic)."""
    return asdict(v)


# ── Source resolution (Task 3) ───────────────────────────────────────────────

@dataclass(frozen=True)
class ResolvedSource:
    image_url: str          # the URL images.edit will actually edit
    mode_requested: str     # raw client request (may be "")
    mode_resolved: str      # ORIGINAL | LATEST | SPECIFIC_VERSION
    source_type: str        # "original" | "latest" | "specific"
    source_version_id: str  # resolved specific id (or "")


def _latest_generated(versions: list[VersionRecord], before_image_url: str) -> str:
    """Most recent generated image: prefer the versions ledger, else the
    client-supplied latest display image."""
    for v in reversed(versions):
        if v.generated_image_url:
            return v.generated_image_url
    return before_image_url or ""


def resolve_source(
    *,
    source_mode: str,
    source_version_id: str,
    iteration: int,
    original_image_url: str,
    before_image_url: str,
    versions: list[VersionRecord],
) -> ResolvedSource:
    """
    Deterministic source-image selection.

      V1 (iteration <= 1)            -> ORIGINAL (never latest — regression #1)
      ORIGINAL                       -> original uploaded photo
      SPECIFIC_VERSION + valid id    -> that version's generated image
      LATEST / missing (iteration>1) -> latest generated image
      no generated image anywhere    -> fallback ORIGINAL

    Architectural truth (original_image_url / structural identity) is always
    kept available separately by the caller — never conflated with this.
    """
    req = (source_mode or "").strip().upper()
    if req not in _VALID_MODES:
        req = ""  # unknown/empty == missing (legacy clients, Task 6)

    raw = source_mode or ""

    # V1 is always the original photographed apartment.
    if iteration <= 1:
        return ResolvedSource(original_image_url or before_image_url,
                               raw, ORIGINAL, "original", "")

    # Explicit restart from the original.
    if req == ORIGINAL:
        return ResolvedSource(original_image_url or before_image_url,
                               raw, ORIGINAL, "original", "")

    # Explicit specific prior version.
    if req == SPECIFIC_VERSION:
        svid = (source_version_id or "").strip()
        match = next((v for v in versions
                      if v.version_id == svid and v.generated_image_url), None)
        if match:
            return ResolvedSource(match.generated_image_url, raw,
                                   SPECIFIC_VERSION, "specific", svid)
        # Unknown id -> fall through to LATEST (never crash — Task 6).

    # LATEST or missing (default for iteration > 1).
    latest = _latest_generated(versions, before_image_url)
    if latest:
        return ResolvedSource(latest, raw, LATEST, "latest", "")

    # No generated image exists anywhere -> fallback to the original.
    return ResolvedSource(original_image_url or before_image_url,
                           raw, ORIGINAL, "original", "")


# ── Concise source-continuity prompt wording (Task 5) ────────────────────────

_IDENTITY_AUTHORITY = (
    "The original apartment structural identity remains authoritative for "
    "windows, openings, partitions, depth, and apartment identity."
)
_CONTINUE = (
    "CONTINUE FROM CURRENT DESIGN — continue from the provided current design "
    "image; preserve its layout, furniture placement, and spatial composition "
    "unless explicitly asked to change them. " + _IDENTITY_AUTHORITY
)
_RESTART = (
    "RESTART FROM ORIGINAL — restart from the original photographed apartment; "
    "do not continue any prior generated design state. " + _IDENTITY_AUTHORITY
)


def build_source_continuity_clause(source_type: str, iteration: int) -> str:
    """
    Concise P1 continuity wording for V2+ (Task 5). "" for V1 (V1 edits the
    original — no "continue from current design" concept) and zero prompt cost.
    """
    if iteration <= 1:
        return ""
    if source_type in ("latest", "specific"):
        return _CONTINUE
    if source_type == "original":
        return _RESTART
    return ""
