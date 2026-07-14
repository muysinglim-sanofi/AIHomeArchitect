"""
Unified Identity V1 — COMMIT 3a : orchestration backend de la fusion de comptes.

Couche MINCE au-dessus du RPC validé `public.identity_claim_and_merge`
(Commit 2) et du schéma dormant (Commit 1). Ce module fournit :

  1. `require_active_identity` — dépendance FastAPI commune : refuse d'agir
     sous une identité A FERMÉE (`account_state.merged_closed=true`).
     C'est la FRONTIÈRE DE SÉCURITÉ (la révocation Auth de A = Commit 3b,
     défense en profondeur). Aucune réécriture A→B, aucune traversée de
     `merged_into` : on refuse un compte fermé, on ne devine jamais.
  2. `POST /identity/merge-ticket` — authentifié par A (anonyme) : émet un
     ticket éphémère, ne stocke que son hash, renvoie le brut UNE fois.
  3. `POST /identity/claim` — authentifié par B (permanent) : hash + appel
     du RPC, `p_to_user` = JWT de B (jamais le corps), mapping stable.

Contraintes verrouillées (SPEC V2) :
  • Endpoints gated par IDENTITY_MERGE_ENDPOINTS_ENABLED (défaut false) —
    DORMANTS en prod jusqu'à la réconciliation billing du Commit 5.
  • Le garde `merged_closed` est INDÉPENDANT de ce flag et n'a AUCUN cache
    en V1 : une lecture `account_state` par requête ; erreur DB → 503.
  • Aucune révocation Auth, aucun scheduler, aucune transition `completed`
    ici (tout cela = Commit 3b).
  • Le ticket brut et son hash ne sont JAMAIS loggés.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import os
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from auth import CurrentUser, get_current_user

log = logging.getLogger("aih.identity")

identity_router = APIRouter(prefix="/identity", tags=["identity"])

TICKET_TTL_MINUTES = 5
_TICKET_MIN_LEN = 16
_TICKET_MAX_LEN = 256


def _get_supa():
    """Lazy import to avoid the circular dependency at module load."""
    from main import supa  # noqa: PLC0415
    return supa


def _merge_endpoints_enabled() -> bool:
    """Gate the two endpoints. Default OFF (dormant in prod until Commit 5)."""
    return os.environ.get("IDENTITY_MERGE_ENDPOINTS_ENABLED", "false").strip().lower() == "true"


def _hash_ticket(ticket: str) -> str:
    """Encodage EXACT du hash (identique création/claim) : sha256(UTF-8).hexdigest()."""
    return hashlib.sha256(ticket.encode("utf-8")).hexdigest()


# ── Garde d'identité active (dépendance commune) ─────────────────────────────

def _assert_active_identity(user_id: str) -> None:
    """Refuse un compte FERMÉ. Lecture `account_state` à CHAQUE requête (aucun
    cache en V1). merged_closed=true → 403 ; erreur DB → 503 (fail-closed).
    Ligne absente / merged_closed=false → passe. Jamais de réécriture A→B."""
    supa = _get_supa()
    try:
        res = (
            supa.table("account_state")
            .select("merged_closed")
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
        rows = getattr(res, "data", None) or []
    except Exception as exc:  # noqa: BLE001
        log.warning("[identity guard] account_state read failed user=%s err=%s",
                    user_id[:8], type(exc).__name__)
        raise HTTPException(
            status_code=503,
            detail={"error_code": "identity_check_unavailable",
                    "user_message": "Identity check temporarily unavailable."},
        )
    if rows and rows[0].get("merged_closed") is True:
        log.info("[identity guard] blocked merged_closed user=%s", user_id[:8])
        raise HTTPException(
            status_code=403,
            detail={"error_code": "identity_merged",
                    "user_message": "This account has been merged. Please sign in again."},
        )


def require_active_identity(
    current_user: CurrentUser = Depends(get_current_user),
) -> CurrentUser:
    """Dépendance commune (14 routes utilisateur + endpoints de fusion) : JWT
    vérifié (get_current_user, INTACT) + garde merged_closed. TOUJOURS active,
    indépendante des feature flags de fusion."""
    _assert_active_identity(current_user.user_id)
    return current_user


# ── Corps STRICT + gate ordonné (flag → JWT → garde) des endpoints de fusion ──

class ClaimBody(BaseModel):
    """Corps STRICT de /identity/claim : EXACTEMENT {"ticket": "..."}. Tout
    champ supplémentaire (to_user, from_user_id, p_to_user…) → 422 (extra
    interdit). Alphabet URL-safe uniquement (le jeton est `secrets.token_urlsafe`) :
    ni espace, ni tabulation, ni retour à la ligne. Aucun strip()."""
    model_config = ConfigDict(extra="forbid")
    ticket: str = Field(min_length=_TICKET_MIN_LEN, max_length=_TICKET_MAX_LEN,
                        pattern=r"^[A-Za-z0-9_-]+$")


def _require_merge_enabled() -> None:
    """Gate flag EN PREMIER (avant auth/garde/lecture account_state). Flag OFF
    → 404 immédiat : ni JWT requis, ni lecture DB."""
    if not _merge_endpoints_enabled():
        raise HTTPException(status_code=404,
                            detail={"error_code": "not_found", "user_message": "Not found."})


def merge_gate(
    _flag: None = Depends(_require_merge_enabled),                 # 1) flag → 404
    current_user: CurrentUser = Depends(require_active_identity),  # 2) JWT → 3) garde
) -> CurrentUser:
    """Dépendance des 2 endpoints de fusion. FastAPI résout les sous-dépendances
    DANS L'ORDRE de la signature → flag AVANT auth AVANT garde. Flag OFF ⇒ 404
    sans jamais atteindre l'auth ni la lecture `account_state`."""
    return current_user


# ── Mapping statut/erreur RPC → réponse API stable ───────────────────────────

def _map_rpc_row(row: dict):
    """RPC = ROW (merge_id, status, failure_code, metadata). Statuts succès →
    JSONResponse 200/202 ; statuts métier négatifs → HTTPException 409 ;
    statut inconnu → 503 générique. Aucun message Postgres brut renvoyé."""
    status_ = row.get("status")
    merge_id = row.get("merge_id")
    failure_code = row.get("failure_code")
    metadata = row.get("metadata") or {}

    if status_ in ("completed", "revocation_pending"):
        # 200 (et non 202) : l'effet demandé — données sous B + A bloqué par le
        # garde — est COMPLET et synchrone au retour ; la révocation Auth (3b)
        # est interne et non actionnable par le client → rien à poller.
        return JSONResponse(status_code=200, content={"status": status_, "merge_id": str(merge_id)})
    if status_ == "data_merged":
        # Déplacement fait, finalisation en cours (réplay idempotent d'une ligne
        # intermédiaire — Commit 2 §18) → 202, en attente de finalisation.
        return JSONResponse(status_code=202,
                            content={"status": "identity_merge_pending", "merge_id": str(merge_id)})
    if status_ == "billing_reconciliation_pending":
        # 202 : réellement incomplet (réconciliation financière = Commit 5).
        return JSONResponse(status_code=202,
                            content={"status": "billing_pending", "merge_id": str(merge_id)})
    if status_ == "waiting_for_settlement":
        raise HTTPException(status_code=409,
                            detail={"error_code": "settlement_active",
                                    "user_message": "Please retry in a moment."})
    if status_ == "billing_conflict_manual_review":
        raise HTTPException(status_code=409,
                            detail={"error_code": "both_users_premium",
                                    "user_message": "This merge needs manual review."})
    if status_ == "abandoned":
        # Tentative antérieure abandonnée (terminal, non bloquant → nouveau ticket possible).
        raise HTTPException(status_code=409,
                            detail={"error_code": "identity_merge_abandoned",
                                    "user_message": "This merge was cancelled. Please start again."})
    if status_ == "conflict":
        detail = {"error_code": failure_code or "conflict",
                  "user_message": "This merge could not be completed."}
        existing = metadata.get("existing_merge_id")
        if existing:
            detail["existing_merge_id"] = str(existing)
        raise HTTPException(status_code=409, detail=detail)
    if status_ == "failed":
        # Échec terminal d'une tentative antérieure (réplay idempotent — §18).
        raise HTTPException(status_code=503,
                            detail={"error_code": "identity_merge_failed",
                                    "user_message": "Merge failed. Please try again."})

    log.warning("[identity] claim unexpected status=%r", status_)
    raise HTTPException(status_code=503,
                        detail={"error_code": "identity_merge_unavailable",
                                "user_message": "Merge failed. Please try again."})


def _raise_rpc_exception(exc: Exception):
    """RAISE Postgres (P0001) / erreur PostgREST → code fixe. Le string-match
    est INTERNE ; jamais str(exc) renvoyé au client."""
    m = str(exc).lower()
    if "ticket_expired" in m:
        raise HTTPException(status_code=410,
                            detail={"error_code": "ticket_expired",
                                    "user_message": "This merge link has expired."})
    if ("ticket_not_found" in m or "ticket_source_changed" in m or "ticket_consumed" in m):
        raise HTTPException(status_code=404,
                            detail={"error_code": "ticket_invalid",
                                    "user_message": "Invalid or already-used merge link."})
    if ("pgrst202" in m or "could not find the function" in m
            or "does not exist" in m or "schema cache" in m):
        raise HTTPException(status_code=503,
                            detail={"error_code": "identity_rpc_unavailable",
                                    "user_message": "Merge is temporarily unavailable."})
    log.warning("[identity] claim unknown RPC error type=%s", type(exc).__name__)
    raise HTTPException(status_code=503,
                        detail={"error_code": "identity_merge_unavailable",
                                "user_message": "Merge failed. Please try again."})


# ── Endpoints ────────────────────────────────────────────────────────────────

@identity_router.post("/merge-ticket")
async def create_merge_ticket(
    current_user: CurrentUser = Depends(merge_gate),  # flag → JWT → garde
):
    """Auth = A. A doit être ANONYME et ACTIF (garde). Crée un ticket neuf,
    stocke UNIQUEMENT le hash, renvoie le brut une seule fois. Aucune
    invalidation des anciens tickets (ils expirent seuls)."""
    if not current_user.is_anonymous:
        raise HTTPException(status_code=400,
                            detail={"error_code": "not_anonymous",
                                    "user_message": "Only a guest account can start a merge."})

    token = secrets.token_urlsafe(32)
    ticket_hash = _hash_ticket(token)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=TICKET_TTL_MINUTES)
    supa = _get_supa()
    try:
        await asyncio.to_thread(
            lambda: supa.table("identity_merge_tickets").insert({
                "ticket_hash": ticket_hash,
                "from_user_id": current_user.user_id,  # SOURCE = JWT de A, jamais le corps
                "expires_at": expires_at.isoformat(),
            }).execute()
        )
    except Exception as exc:  # noqa: BLE001
        log.warning("[identity] merge-ticket insert failed user=%s err=%s",
                    current_user.user_id[:8], type(exc).__name__)
        raise HTTPException(status_code=503,
                            detail={"error_code": "identity_merge_unavailable",
                                    "user_message": "Could not start merge. Please try again."})

    log.info("[identity] merge-ticket created user=%s ttl=%dm", current_user.user_id[:8], TICKET_TTL_MINUTES)
    return {"ticket": token, "expires_at": expires_at.isoformat()}  # brut renvoyé UNE fois


@identity_router.post("/claim")
async def claim_merge(
    body: ClaimBody,                                   # corps STRICT (extra interdit)
    current_user: CurrentUser = Depends(merge_gate),   # flag → JWT → garde
):
    """Auth = B. Corps STRICT {"ticket": "..."} (ClaimBody : tout autre champ
    → 422). `p_to_user` = JWT de B (jamais le corps). Ne déclenche AUCUNE
    révocation (Commit 3b)."""
    ticket_hash = _hash_ticket(body.ticket)
    supa = _get_supa()
    try:
        res = await asyncio.to_thread(
            lambda: supa.rpc("identity_claim_and_merge", {
                "p_ticket_hash": ticket_hash,
                "p_to_user": current_user.user_id,  # CIBLE = JWT de B, jamais le corps
            }).execute()
        )
        rows = getattr(res, "data", None) or []
    except Exception as exc:  # noqa: BLE001
        _raise_rpc_exception(exc)
        return  # unreachable (｡_raise_ always raises) — satisfait l'analyseur

    if not rows:
        log.warning("[identity] claim RPC returned no row user=%s", current_user.user_id[:8])
        raise HTTPException(status_code=503,
                            detail={"error_code": "identity_merge_unavailable",
                                    "user_message": "Merge failed. Please try again."})
    log.info("[identity] claim user=%s status=%s", current_user.user_id[:8], rows[0].get("status"))
    return _map_rpc_row(rows[0])
