"""
Wave 5.17d.1 — Free-tier scope restriction.

Free (non-premium) users may generate ONLY :
  - room_type_id ∈ FREE_ROOMS       (Living Room only)
  - atmosphere_id ∈ FREE_ATMOSPHERES (Warm Modern + Japandi Calm — 2026-06-08)

Re-pivot from D1 lock (2026-05-30) : Nordic Warmth + Soft Luxury →
Warm Modern + Nordic Warmth. Soft Luxury moves to the premium teaser
set ; Warm Modern is the universal default starter style.

This module owns the policy. The /generate endpoint imports
`check_restrictions` and calls it AFTER quota OK but BEFORE the
OpenAI reservation. Premium / admin users bypass entirely via the
existing `has_admin_role` check (no separate code path).

Why ids and not labels :
  The Flutter client sends both the localized human label (room_type,
  style_label) and the canonical machine id (room_type_id,
  atmosphere_id). The label drifts with locale ("Living Room" vs the
  Khmer translation) and with marketing tweaks ("Tropical Escape ·
  Vision 1"). The id is stable. We gate on the id ; the labels remain
  free-form for the prompt engine.

The canonical id catalogue mirrors the frontend single source of truth :
  - rooms      : frontend/lib/core/constants/room_type_images.dart
                  (interiorIds + exteriorIds)
  - atmospheres : frontend/lib/core/models/atmosphere_style.dart
                  (kAtmospheres[i].id)

Sync test : `backend/_wave_5_17b_validation.py::S9` ensures the lists
agree on the free pair. The full catalogue is enumerated below for
reference + future drift detection.
"""
from __future__ import annotations
import logging
import os
from typing import Optional

from fastapi import HTTPException, status

from quota import has_admin_role

log = logging.getLogger("aih.free_tier")


# ── Free-tier scope ─────────────────────────────────────────────────────────

# Canonical room ids (mirrors frontend RoomTypeImages.interiorIds[0]).
FREE_ROOMS = ("livingRoom",)

# Canonical atmosphere ids (mirrors frontend AtmosphereStyle.id).
# 2026-06-08 — free pair changed to Warm Modern + Japandi Calm
# (Nordic Warmth moved to premium; tied to the card-redesign popularity order).
FREE_ATMOSPHERES = ("warm_modern", "japandi_calm")


# Reference catalogue for drift detection and operator clarity. Not used
# at runtime — the check below relies only on `in FREE_*` membership.
_ALL_ROOM_IDS = (
    "livingRoom", "masterBedroom", "kitchen", "bathroom",
    "homeOffice", "diningRoom", "entranceHall",
    "houseFacade", "garden", "poolArea", "terrace", "balcony", "driveway",
)
_ALL_ATMOSPHERE_IDS = (
    "tropical_escape", "warm_modern", "japandi_calm", "soft_luxury",
    "nordic_warmth",
)


# ── Public API ──────────────────────────────────────────────────────────────


async def check_restrictions(
    *,
    user_id: str,
    room_type_id: str,
    atmosphere_id: str,
    let_ai_decide: bool,
    surprise_me: bool,
    supa=None,
) -> None:
    """
    Block non-premium users from out-of-scope generations.

    Raises HTTPException(402, detail={...}) when blocked ; returns None
    when allowed. Admin and premium roles bypass entirely (delegated to
    `quota.has_admin_role` so the bypass surface stays consistent across
    quota + free-tier modules).

    The 402 detail mirrors the QUOTA_EXHAUSTED shape so the Flutter
    chat_screen can route both to the same paywall sheet ; the
    `error_code` field discriminates copy + analytics.
    """
    if await has_admin_role(user_id, supa=supa):
        return

    # #8 (2026-06-19) — Ayden Decide (let_ai_decide) is FREE when
    # AYDEN_DECIDE_FREE is on (default): it delegates only the ROOM, and the
    # atmosphere free-check + quota below still gate the generation, so it can
    # never be a paid-feature bypass. Surprise Me stays premium (it delegates the
    # ATMOSPHERE → could pick a premium style). AYDEN_DECIDE_FREE=0 restores the
    # old lock (instant rollback).
    _ayden_decide_free = os.environ.get("AYDEN_DECIDE_FREE", "1") != "0"
    # AYDEN_SIGNATURE_FREE (default off): make Ayden Signature (surprise_me) FREE
    # for everyone AND let its AI pick ANY atmosphere (incl. premium ones). The
    # lock then lives ONLY on EXPLICIT atmosphere choice (the membership test
    # below) — Signature becomes a free teaser/funnel: a free user tastes a premium
    # style via the AI, then pays to pick that style directly. AYDEN_SIGNATURE_FREE=0
    # restores the old lock (surprise_me premium).
    _signature_free = os.environ.get("AYDEN_SIGNATURE_FREE", "0") == "1"
    # A free user may not DELEGATE the atmosphere via surprise_me UNLESS Signature
    # is free; let_ai_decide (room only) is allowed when its flag is on. Without a
    # gate, delegation could pass an empty room_type_id and slip past the room test
    # — so for a free let_ai_decide we SKIP the room check (room is delegated).
    if (surprise_me and not _signature_free) or (let_ai_decide and not _ayden_decide_free):
        log.info(
            "[Wave 5.17d] free-tier blocked — user=%s reason=delegated_choice "
            "(let_ai_decide=%s surprise_me=%s)",
            user_id, let_ai_decide, surprise_me,
        )
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail={
                "error_code": "FREE_TIER_RESTRICTED",
                "user_message": (
                    "Let AI Decide and Surprise Me are part of premium. "
                    "Pick Living Room with Warm Modern or Nordic Warmth "
                    "to keep exploring for free."
                ),
                "restricted_field": "delegated_choice",
                "retryable": False,
                "request_id": "",
            },
        )

    if not (let_ai_decide and _ayden_decide_free) and room_type_id not in FREE_ROOMS:
        log.info(
            "[Wave 5.17d] free-tier blocked — user=%s reason=room "
            "received=%r allowed=%s",
            user_id, room_type_id, list(FREE_ROOMS),
        )
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail={
                "error_code": "FREE_TIER_RESTRICTED",
                "user_message": (
                    "Premium unlocks every room. The free tier transforms "
                    "Living Rooms only."
                ),
                "restricted_field": "room",
                "received_id": room_type_id,
                "allowed_ids": list(FREE_ROOMS),
                "retryable": False,
                "request_id": "",
            },
        )

    # Skip the atmosphere lock when Ayden Signature is free + delegated: the AI
    # picks the atmosphere, intentionally free (funnel). The lock stays for an
    # EXPLICIT atmosphere choice (surprise_me=False).
    if not (surprise_me and _signature_free) and atmosphere_id not in FREE_ATMOSPHERES:
        log.info(
            "[Wave 5.17d] free-tier blocked — user=%s reason=atmosphere "
            "received=%r allowed=%s",
            user_id, atmosphere_id, list(FREE_ATMOSPHERES),
        )
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail={
                "error_code": "FREE_TIER_RESTRICTED",
                "user_message": (
                    "Premium unlocks every atmosphere. The free tier offers "
                    "Warm Modern and Nordic Warmth."
                ),
                "restricted_field": "atmosphere",
                "received_id": atmosphere_id,
                "allowed_ids": list(FREE_ATMOSPHERES),
                "retryable": False,
                "request_id": "",
            },
        )

    log.info(
        "[Wave 5.17d] free-tier OK — user=%s room=%s atmosphere=%s",
        user_id, room_type_id, atmosphere_id,
    )
