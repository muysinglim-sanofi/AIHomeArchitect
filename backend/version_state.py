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
from typing import Optional

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
    # β (2026-06-22) — cumulative lineage state for REBOOT_FRESH vs REBOOT_CUSTOMIZED.
    # True  = this version's lineage contains ≥1 spatial edit (object/layout/
    #         functional/structural) → an atmosphere switch must preserve it.
    # False = pristine lineage (only first-vision + switches + refinements).
    # None  = pre-β record (field never written) → readers MUST fall back to the
    #         legacy history scan; NEVER coerce None→False (would create unsafe
    #         REBOOT_FRESH that re-sources V1 and drops the user's spatial work).
    lineage_customized: Optional[bool] = None


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
                # β — strict tri-state: keep True/False as-is, anything else
                # (absent / null / malformed) → None (= pre-β, legacy fallback).
                # NEVER coerce to False.
                lineage_customized=(c.get("lineage_customized")
                                    if isinstance(c.get("lineage_customized"), bool)
                                    else None),
            ))
        except (ValueError, TypeError):
            continue
    return out


# ── Source-record identification (SINGLE definition; shared by the previous-
# atmosphere detection — axis C — and the lineage_customized flag — axis β) ────
# The "source record" is the version a new generation is edited FROM:
#   • a client-pinned prior vision (branch / continue-from-vision) → by id,
#   • else the linear chain tail (LATEST).
# Both axes call these; no parallel source logic, no lineage walk.

def record_for_version(
    versions: list[VersionRecord], version_id: str
) -> Optional[VersionRecord]:
    """The record whose version_id == `version_id`, or None if absent/unknown."""
    vid = (version_id or "").strip()
    if not vid:
        return None
    for v in versions:
        if v.version_id == vid:
            return v
    return None


def latest_record(versions: list[VersionRecord]) -> Optional[VersionRecord]:
    """The most-recently-recorded version that actually produced an image
    (reversed scan), or None. This is the LATEST/linear source."""
    for v in reversed(versions):
        if v.generated_image_url:
            return v
    return None


def latest_atmosphere(versions: list[VersionRecord]) -> str:
    """Convenience: atmosphere label of the linear chain tail (or '')."""
    r = latest_record(versions)
    return (r.atmosphere or "").strip() if r else ""


def atmosphere_for_version(versions: list[VersionRecord], version_id: str) -> str:
    """Convenience: atmosphere label of a specific version (or '')."""
    r = record_for_version(versions, version_id)
    return (r.atmosphere or "").strip() if r else ""


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
