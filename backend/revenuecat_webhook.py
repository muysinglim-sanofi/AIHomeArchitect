"""
Wave 5.17d — RevenueCat webhook receiver.

POST /webhooks/revenuecat — invoked by RevenueCat on every subscription
lifecycle event (purchase, renewal, cancellation, expiration, …). The
endpoint :

  1. Verifies the request is genuinely from RevenueCat by comparing
     the `Authorization` header against a shared secret stored in
     REVENUECAT_WEBHOOK_AUTH. Uses `secrets.compare_digest` to avoid
     timing-side-channel leaks.

  2. Parses the JSON payload and dispatches on `event.type`. Granting
     events (INITIAL_PURCHASE, RENEWAL, UNCANCELLATION, PRODUCT_CHANGE,
     NON_RENEWING_PURCHASE) UPSERT a row into `public.user_roles` with
     role='premium' and expires_at = event.expiration_at_ms (when
     provided). Revoking events (EXPIRATION) clear the expiry to
     `now()` so the next quota check sees the user as non-premium.
     CANCELLATION leaves expires_at intact — the user keeps premium
     until the subscription period ends (RC sends EXPIRATION later).

  3. Returns 200 ALWAYS on a verified, parseable event — even when we
     skip (unknown type, no matching entitlement). RevenueCat retries
     on non-2xx, so any 4xx/5xx forces redundant deliveries. Errors
     are logged ; the response is still 200 unless the signature is
     wrong (401) or the body is unparseable (400).

  4. Idempotency : the operation is an UPSERT keyed on
     (user_id, role). Duplicate deliveries produce no double-row.

Configuration (operational, NOT in code) :
  - Set REVENUECAT_WEBHOOK_AUTH in backend/.env to a strong random
    string (e.g. `openssl rand -hex 32`).
  - In RevenueCat dashboard → Integrations → Webhooks, set the
    Authorization Header Value to the SAME string.
  - Set the webhook URL to `https://<your-backend>/webhooks/revenuecat`.

Premium entitlement contract :
  We trust the `entitlement_ids` array sent by RC. The standard V1
  entitlement is `premium` ; events that don't reference it are
  ignored (logged at debug). Future entitlements (e.g. `pro`, `family`)
  can be added without code change by extending `_GRANTING_EVENTS`
  and the role mapping below.
"""
from __future__ import annotations
import logging
import os
import secrets
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException, Request, status

log = logging.getLogger("aih.revenuecat")


# ── Configuration ───────────────────────────────────────────────────────────

# The single entitlement we honour in V1. Anything else in the event's
# `entitlement_ids` is logged but not acted on.
PREMIUM_ENTITLEMENT = "premium"

# Event types that GRANT or EXTEND a premium entitlement. The webhook
# UPSERTs `user_roles(role='premium')` with the event's expiration
# timestamp for every type below.
_GRANTING_EVENTS = frozenset({
    "INITIAL_PURCHASE",
    "RENEWAL",
    "UNCANCELLATION",
    "PRODUCT_CHANGE",
    "NON_RENEWING_PURCHASE",
    "TRANSFER",
})

# RC-PR2 — event types that also CREDIT the wallet (Payment/Order/Pass +
# ledger GRANT) IN ADDITION to the premium role (dual-write). Strictly the two
# real acquisition events ; UNCANCELLATION/PRODUCT_CHANGE/NON_RENEWING/TRANSFER
# keep the premium-role write only (special semantics, out of RC-PR2 scope).
_CREDIT_GRANTING_EVENTS = frozenset({
    "INITIAL_PURCHASE",
    "RENEWAL",
})

# Event types that EXPIRE an entitlement. RC sends `expiration_at_ms`
# in the past for these — we update the row so has_admin_role returns
# False on the next check.
_REVOKING_EVENTS = frozenset({
    "EXPIRATION",
})

# Event types we observe but do not act on. CANCELLATION leaves the
# row intact ; the EXPIRATION event arrives at period-end and revokes.
# BILLING_ISSUE is informational (RC manages the grace period).
_OBSERVED_ONLY = frozenset({
    "CANCELLATION",
    "BILLING_ISSUE",
    "SUBSCRIBER_ALIAS",
})


def _get_webhook_auth() -> str:
    """Read the shared secret lazily so test setups can set the env var
    after importing the module."""
    return os.environ.get("REVENUECAT_WEBHOOK_AUTH", "")


def _get_supa():
    """Lazy import to avoid circular dependency at module load."""
    from main import supa  # noqa: PLC0415
    return supa


# ── Public API ──────────────────────────────────────────────────────────────

router = APIRouter(prefix="/webhooks", tags=["webhooks"])


@router.post("/revenuecat", status_code=200)
async def revenuecat_webhook(request: Request) -> dict:
    """RevenueCat webhook receiver. See module docstring for the full
    contract. Returns `{"ok": True, "action": "...", "user_id": "..."}`
    on success ; raises HTTPException(401) on signature mismatch and
    HTTPException(400) on unparseable body."""

    # ── 1. Auth ────────────────────────────────────────────────────────────
    expected = _get_webhook_auth()
    if not expected:
        log.warning("[Wave 5.17d webhook] reject=backend_misconfigured (REVENUECAT_WEBHOOK_AUTH empty)")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="backend_misconfigured",
        )
    received = (
        request.headers.get("Authorization")
        or request.headers.get("authorization")
        or ""
    )
    if not received or not secrets.compare_digest(received, expected):
        log.warning("[Wave 5.17d webhook] reject=invalid_signature header_present=%s",
                    bool(received))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid_signature",
        )

    # ── 2. Parse ───────────────────────────────────────────────────────────
    try:
        payload = await request.json()
    except Exception as exc:
        log.warning("[Wave 5.17d webhook] reject=invalid_body err=%s", exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="invalid_body",
        )

    event = payload.get("event") if isinstance(payload, dict) else None
    if not isinstance(event, dict):
        log.warning("[Wave 5.17d webhook] reject=missing_event payload_keys=%s",
                    list(payload.keys()) if isinstance(payload, dict) else type(payload).__name__)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="missing_event",
        )

    event_type = event.get("type") or ""
    event_id = event.get("id") or ""
    app_user_id = event.get("app_user_id") or ""
    entitlement_ids = event.get("entitlement_ids") or []
    expiration_at_ms = event.get("expiration_at_ms")  # may be None

    log.info(
        "[Wave 5.17d webhook] receive type=%s event_id=%s user=%s entitlements=%s",
        event_type, event_id, app_user_id, entitlement_ids,
    )

    # ── 3. Routing ─────────────────────────────────────────────────────────
    if not app_user_id:
        # Event without a user id (e.g. SUBSCRIBER_ALIAS sometimes) — we
        # acknowledge and skip. RC retries are wasteful here ; 200 is the
        # right contract.
        return {"ok": True, "action": "skipped", "reason": "no_user_id"}

    if PREMIUM_ENTITLEMENT not in entitlement_ids and event_type != "EXPIRATION":
        # Some non-premium entitlement we don't recognise. EXPIRATION
        # events also sometimes drop the entitlement_ids — we still
        # process them, gated below on event_type.
        log.info(
            "[Wave 5.17d webhook] skip — premium not in entitlements user=%s ents=%s",
            app_user_id, entitlement_ids,
        )
        return {"ok": True, "action": "skipped", "reason": "no_premium_entitlement"}

    supa = _get_supa()

    if event_type in _GRANTING_EVENTS:
        expires_iso = _ms_to_iso(expiration_at_ms)
        # (1) Autorité actuelle CONSERVÉE (dual-write RC-PR2, ne rien retirer).
        await _upsert_premium(
            supa=supa,
            user_id=app_user_id,
            expires_at_iso=expires_iso,
            event_type=event_type,
            event_id=event_id,
        )
        # (2) RC-PR2 — crédite le wallet EN PLUS, sur les vrais achats. Peut lever
        #     HTTPException(500) → non-2xx → RevenueCat retente (retry-safe car
        #     grant_purchase est idempotent). _upsert_premium ci-dessus est déjà
        #     idempotent, donc le retry ne double rien.
        grant_info = None
        if event_type in _CREDIT_GRANTING_EVENTS:
            grant_info = await _dual_write_grant(
                supa=supa, event=event, user_id=app_user_id, expires_iso=expires_iso,
            )
        return {
            "ok": True,
            "action": "premium_granted",
            "user_id": app_user_id,
            "expires_at": expires_iso,
            "grant": grant_info,
        }

    if event_type in _REVOKING_EVENTS:
        # Expire the role immediately. We do NOT delete the row : keeping
        # historical premium grants is useful for analytics and for the
        # has_admin_role expiration check (it compares expires_at to now).
        revoked_iso = _ms_to_iso(expiration_at_ms) or _now_iso()
        await _expire_premium(
            supa=supa,
            user_id=app_user_id,
            expires_at_iso=revoked_iso,
            event_type=event_type,
            event_id=event_id,
        )
        return {
            "ok": True,
            "action": "premium_revoked",
            "user_id": app_user_id,
            "expires_at": revoked_iso,
        }

    if event_type in _OBSERVED_ONLY:
        # No-op — premium stays active until the natural EXPIRATION fires.
        return {"ok": True, "action": "noop", "type": event_type}

    log.info("[Wave 5.17d webhook] unknown event type=%s — acknowledged", event_type)
    return {"ok": True, "action": "skipped", "reason": "unknown_event_type"}


# ── Internal helpers ────────────────────────────────────────────────────────

import asyncio  # noqa: E402  — used by the awaitable helpers below


async def _dual_write_grant(*, supa, event: dict, user_id: str, expires_iso: Optional[str]) -> dict:
    """RC-PR2 — crédite le wallet (Payment/Order/Pass + ledger GRANT) en plus du
    rôle premium. Politique STRICTE (chemin argent) :
      • pas de skip muet : product non mappé → HTTPException(500) (RC retente,
        l'anomalie est visible dashboard + logs) ;
      • pas de fail-open : toute erreur RPC → HTTPException(500) (RC retente ;
        grant_purchase est idempotent donc le retry est sûr) ;
      • SANDBOX crédite normalement (décision RC-PR2) — l'environment est tracé
        dans payment.raw_payload (on passe l'event complet).
    """
    import billing  # noqa: PLC0415 — lazy (évite tout cycle d'import au chargement)

    product_id = event.get("product_id") or ""
    transaction_id = event.get("transaction_id") or ""
    environment = event.get("environment") or ""

    if not product_id or not transaction_id:
        # Champs indispensables absents : LOUD (jamais un skip silencieux). Un
        # retry ne les fera pas apparaître → on n'impose pas de boucle non-2xx.
        log.warning(
            "[RC-PR2] grant SKIPPED (missing fields, loud) user=%s product_id=%r tx=%r env=%s",
            user_id, product_id, transaction_id, environment or "-",
        )
        return {"credited": False, "reason": "missing_fields",
                "product_id": product_id or None, "transaction_id": transaction_id or None}

    try:
        result = await billing.grant_purchase(
            user_id=user_id,
            provider="revenuecat",
            provider_transaction_id=transaction_id,   # transaction_id DU CYCLE
            store_product_id=product_id,
            amount=event.get("price"),
            currency=event.get("currency"),
            ends_at_iso=expires_iso,                  # autorité = RC expiration
            raw_payload=event,                        # environment vit ici (audit)
            supa=supa,
        )
    except billing.ProductNotMapped as exc:
        log.error(
            "[RC-PR2] product NOT mapped → non-2xx (RC retry) user=%s product_id=%s env=%s",
            user_id, exc.store_product_id, environment or "-",
        )
        raise HTTPException(status_code=500, detail="product_not_mapped")
    except Exception as exc:  # noqa: BLE001 — chemin argent : PAS de fail-open
        log.error(
            "[RC-PR2] grant_purchase FAILED → non-2xx (RC retry) user=%s tx=%s err=%s: %s",
            user_id, transaction_id, type(exc).__name__, exc,
        )
        raise HTTPException(status_code=500, detail="grant_failed")

    log.info(
        "[RC-PR2] grant OK user=%s tx=%s status=%s credited=%s credits=%d env=%s",
        user_id, transaction_id, result.status, result.credited, result.credits, environment or "-",
    )
    return {
        "credited": result.credited,
        "status": result.status,
        "credits": result.credits,
        "order_id": result.order_id,
        "pass_id": result.pass_id,
        "environment": environment or None,
    }


async def _upsert_premium(
    *,
    supa,
    user_id: str,
    expires_at_iso: Optional[str],
    event_type: str,
    event_id: str,
) -> None:
    """Insert or update the (user_id, 'premium') row in user_roles. The
    primary key is (user_id, role) so upsert is naturally idempotent
    across RC retries.

    Also invalidates the in-process role cache so the next quota check
    sees the new row immediately instead of waiting up to 60 s."""
    row = {
        "user_id": user_id,
        "role": "premium",
        "granted_by": user_id,
        "expires_at": expires_at_iso,
        "notes": f"RevenueCat {event_type} event_id={event_id}",
    }
    try:
        await asyncio.to_thread(
            lambda: supa.table("user_roles")
            .upsert(row, on_conflict="user_id,role")
            .execute()
        )
    except Exception as exc:
        log.error(
            "[Wave 5.17d webhook] upsert FAILED user=%s err=%s",
            user_id, exc,
        )
        raise

    from quota import _clear_role_cache  # noqa: PLC0415
    _clear_role_cache()
    log.info(
        "[Wave 5.17d webhook] premium granted user=%s expires_at=%s type=%s",
        user_id, expires_at_iso, event_type,
    )


async def _expire_premium(
    *,
    supa,
    user_id: str,
    expires_at_iso: str,
    event_type: str,
    event_id: str,
) -> None:
    """Update the existing premium row's expires_at to a past timestamp.
    If no row exists (rare — EXPIRATION arriving before INITIAL_PURCHASE
    is processed) we still UPSERT, so analytics retain a record of the
    lifecycle."""
    row = {
        "user_id": user_id,
        "role": "premium",
        "granted_by": user_id,
        "expires_at": expires_at_iso,
        "notes": f"RevenueCat {event_type} event_id={event_id}",
    }
    try:
        await asyncio.to_thread(
            lambda: supa.table("user_roles")
            .upsert(row, on_conflict="user_id,role")
            .execute()
        )
    except Exception as exc:
        log.error(
            "[Wave 5.17d webhook] expire UPSERT FAILED user=%s err=%s",
            user_id, exc,
        )
        raise

    from quota import _clear_role_cache  # noqa: PLC0415
    _clear_role_cache()
    log.info(
        "[Wave 5.17d webhook] premium revoked user=%s expires_at=%s type=%s",
        user_id, expires_at_iso, event_type,
    )


def _ms_to_iso(ms: Optional[int]) -> Optional[str]:
    """RevenueCat's `expiration_at_ms` is milliseconds since epoch.
    Convert to ISO-8601 UTC for the Supabase `timestamptz` column."""
    if ms is None:
        return None
    try:
        return datetime.fromtimestamp(int(ms) / 1000, tz=timezone.utc).isoformat()
    except (TypeError, ValueError):
        return None


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
