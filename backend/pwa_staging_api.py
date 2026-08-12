"""PWA STAGING ADAPTER — a new ACCESS to the canonical engine, not a new engine.

What this module is
-------------------
The mobile `/generate` handler owns an orchestration the PWA staging project
cannot satisfy: `public.sessions`, `wallets`, `passes`, `generation_intents`.
Those tables do not exist in the staging project, and the credentials available
here cannot create them (the `pwa_staging` grants are scoped to `authenticated`,
so even the staging server key is denied USAGE on the schema).

So this adapter supplies PWA-shaped orchestration around the SAME engine:

    adapter  ->  prompt_engine.compose_generation_prompt   (the canonical composer)
             ->  main.openai.images.edit                   (the canonical client)
             ->  main.IMAGE_MODEL / get_active_profile()   (the canonical model + profile)

It is a second CALLER of those functions, never a copy of them. There is no
prompt text in this file, no provider construction, no image pipeline of its
own, and `main.py` / `prompt_engine/` are not modified by it. The mobile path is
untouched: this router is mounted by `run_pwa_staging.py` only.

Tenancy
-------
Every read and write against the staging project is performed AS THE USER, by
forwarding their Supabase JWT to PostgREST and Storage. The service key is never
used for PWA data. That makes the `pwa_staging` RLS policies a real second line
of defense: even a bug in the ownership checks below cannot reach another
tenant's rows. Ownership is still validated explicitly first — RLS is the net,
not the plan.
"""
from __future__ import annotations

import asyncio
import io
import logging
import os
import uuid

import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

# THE shared operational layer — the same module mobile /generate uses. Nothing
# about retries or post-payment safety is decided in this file.
from generation_resilience import (
    PaidResultLost,
    RetryPolicy,
    with_transport_retries,
)

log = logging.getLogger("aih")

# Tunables kept as module attributes so a test can shorten the backoff without
# touching the shared policy other callers depend on.
_TRANSPORT_ATTEMPTS = 3
_TRANSPORT_BACKOFF_S = 1.0

router = APIRouter(prefix="/pwa/staging", tags=["pwa-staging"])

_BUCKET = "pwa-staging-images"
_SCHEMA = "pwa_staging"
_STAGING_REF = "eedcahzekpgxvvfxufbk"
_PRODUCTION_REF = "vtxkciupyafukhdsgxgw"


def _supabase_url() -> str:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    # Fail closed on every request, not just at boot: a reload that re-pointed
    # the process at production must not be able to serve one PWA call.
    if _PRODUCTION_REF in url or _STAGING_REF not in url:
        raise HTTPException(
            status_code=500,
            detail={"error_code": "STAGING_MISCONFIGURED",
                    "user_message": "Staging is not configured correctly.",
                    "retryable": False},
        )
    return url


def _anon_key() -> str:
    # PostgREST requires an apikey alongside the user's bearer token. The
    # publishable key is the right one here — the user's JWT carries the identity.
    return os.environ.get("SUPABASE_PUBLISHABLE_KEY") or os.environ.get(
        "SUPABASE_SERVICE_ROLE_KEY", ""
    )


# ── single-flight (the in-process half of the mobile protocol) ───────────────
#
# Mobile guards a generation twice: an in-memory `_idem_inflight` set inside the
# handler, and an atomic DB claim (`claim_intent` on `public.generation_intents`).
# The staging project has neither that table nor a role allowed to create it —
# proven, see the report — so the DB half is unavailable here.
#
# The in-memory half is not: it is the same protocol, keyed the same way, and it
# is what actually stops a double-click, two concurrent submits, or a retry fired
# while the first render is still running from paying twice. The backend runs as
# ONE uvicorn process with no --reload (the canonical rule), so a single map
# covers every request this deployment can receive.
#
# Its limit is honest and stated: it does not survive a process restart.
_INFLIGHT: dict[str, "asyncio.Task"] = {}


def _flight_key(user_id: str, idempotency_key: str) -> str:
    return f"{user_id}:{idempotency_key}"


# ── durable claim (the DB half of the mobile protocol) ───────────────────────
#
# `pwa_staging.claim_generation` is an INSERT .. ON CONFLICT: for one logical
# operation Postgres elects exactly one winner, and it survives a restart, a
# second worker and a refresh — none of which the in-process map can cover.
#
# ERROR POLICY — deliberately the SAME as mobile's `claim_generation_intent`:
# FAIL-OPEN, logged at ERROR. Losing a user's generation because the claim
# table hiccupped is worse than the rare double it prevents, and a structural
# failure (table absent) shows up as an immediate flood of ERROR lines rather
# than a silent outage. The in-process single-flight still applies underneath,
# so a fail-open still covers the common double-click.
_CLAIM_RPC = "claim_generation"

# Incremented every time the durable claim was unavailable. A non-zero
# value means this process has been running WITHOUT the protection the
# lifecycle migration provides — surfaced on /health so it cannot pass
# unnoticed.
_CLAIM_FAIL_OPEN_COUNT = 0


class _Claim:
    __slots__ = ("won", "state", "result_vision_id", "error_code", "durable")

    def __init__(self, won: bool, state: str, result_vision_id=None,
                 error_code=None, durable: bool = True):
        self.won = won
        self.state = state
        self.result_vision_id = result_vision_id
        self.error_code = error_code
        # False when the durable layer was unavailable and we failed open.
        self.durable = durable


def _note_fail_open(why: str) -> None:
    global _CLAIM_FAIL_OPEN_COUNT
    _CLAIM_FAIL_OPEN_COUNT += 1
    log.error("[pwa-staging] [CLAIM] FAIL-OPEN (%d) — %s — the durable lifecycle "
              "is UNAVAILABLE; only the in-process guard applies. Apply "
              "supabase/staging/pwa/0004_pwa_generation_lifecycle.sql",
              _CLAIM_FAIL_OPEN_COUNT, why)


async def _claim_generation(client: httpx.AsyncClient, token: str,
                            body: "PwaGenerateRequest") -> _Claim:
    """Reserve this logical operation before anything is paid for."""
    try:
        r = await client.post(
            f"{_supabase_url()}/rest/v1/rpc/{_CLAIM_RPC}",
            json={
                "p_idempotency_key": body.idempotency_key,
                "p_project_id": body.project_id,
                "p_action_type": body.action_type,
                "p_parent_vision_id": body.parent_vision_id or None,
            },
            headers=_user_headers(token, write=True),
        )
        if r.status_code >= 300:
            _note_fail_open(f"rpc status={r.status_code}")
            return _Claim(True, "PROCESSING", durable=False)
        rows = r.json() or []
        row = rows[0] if isinstance(rows, list) and rows else rows
        if not isinstance(row, dict):
            _note_fail_open("unexpected rpc shape")
            return _Claim(True, "PROCESSING", durable=False)
        return _Claim(
            won=bool(row.get("won")),
            state=row.get("state") or "PROCESSING",
            result_vision_id=row.get("result_vision_id"),
            error_code=row.get("error_code"),
        )
    except Exception as exc:  # noqa: BLE001 — fail-open is the policy
        _note_fail_open(type(exc).__name__)
        return _Claim(True, "PROCESSING", durable=False)


async def _settle_claim(client: httpx.AsyncClient, token: str, key: str,
                        *, vision_id=None, error_code=None,
                        render_started: bool = False) -> None:
    """Close the claim. Best-effort: a settle that fails leaves a PROCESSING row
    which a later retry re-claims once it ages out — never a lost render."""
    fn = "complete_generation" if vision_id else "fail_generation"
    payload = ({"p_idempotency_key": key, "p_vision_id": vision_id}
               if vision_id else
               {"p_idempotency_key": key, "p_error_code": error_code or "UNKNOWN",
                "p_render_started": render_started})
    try:
        await client.post(f"{_supabase_url()}/rest/v1/rpc/{fn}",
                          json=payload, headers=_user_headers(token, write=True))
    except Exception as exc:  # noqa: BLE001
        log.warning("[pwa-staging] [CLAIM] settle (%s) failed: %s",
                    fn, type(exc).__name__)


class PwaGenerateRequest(BaseModel):
    """PWA-shaped intent. Structured facts only — the prompt is composed server
    side by the canonical composer, never sent from the browser."""

    project_id: str
    room_id: str = ""
    room_label: str
    atmosphere_id: str
    atmosphere_label: str
    original_image_path: str
    idempotency_key: str
    action_type: str = Field(default="initial")
    parent_vision_id: str = ""
    user_instruction: str = ""
    vision_number: int = 1
    ui_locale: str = "en"

    # Same semantics as mobile `POST /refine`: the advisor runs BEFORE any paid
    # call and can answer instead of generating. `confirm=true` is the user
    # having read that answer and chosen to continue anyway.
    confirm: bool = False


def _user_headers(token: str, *, write: bool = False) -> dict[str, str]:
    h = {
        "apikey": _anon_key(),
        "Authorization": f"Bearer {token}",
        "Accept-Profile": _SCHEMA,
    }
    if write:
        h["Content-Profile"] = _SCHEMA
        h["Prefer"] = "return=representation"
    return h


def _bearer(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=401,
            detail={"error_code": "MISSING_TOKEN",
                    "user_message": "Please reload the page.",
                    "retryable": False},
        )
    return authorization.split(" ", 1)[1].strip()


async def _verify_user(client: httpx.AsyncClient, token: str) -> str:
    """Resolve the caller server-side. The client's claim of who it is is never
    trusted — the id used for every subsequent check comes from GoTrue."""
    r = await client.get(
        f"{_supabase_url()}/auth/v1/user",
        headers={"apikey": _anon_key(), "Authorization": f"Bearer {token}"},
    )
    if r.status_code != 200:
        raise HTTPException(
            status_code=401,
            detail={"error_code": "SESSION_EXPIRED",
                    "user_message": "Your session expired. Reload to continue.",
                    "retryable": False},
        )
    uid = (r.json() or {}).get("id", "")
    if not uid:
        raise HTTPException(status_code=401, detail={"error_code": "SESSION_EXPIRED",
                                                     "user_message": "Session invalid.",
                                                     "retryable": False})
    return uid


def _assert_owned_path(path: str, user_id: str, project_id: str) -> None:
    """A Storage path is only acceptable if it is literally inside this user's
    and this project's folder. Forged prefixes and traversal both land here."""
    expected = f"users/{user_id}/projects/{project_id}/"
    if not path.startswith(expected) or ".." in path:
        log.warning("[pwa-staging] rejected storage path outside the caller's namespace")
        raise HTTPException(
            status_code=403,
            detail={"error_code": "PATH_FORBIDDEN",
                    "user_message": "That image does not belong to this project.",
                    "retryable": False},
        )


async def _load_project(client: httpx.AsyncClient, token: str, user_id: str,
                        project_id: str) -> dict:
    r = await client.get(
        f"{_supabase_url()}/rest/v1/pwa_projects",
        params={"id": f"eq.{project_id}", "select": "*", "limit": "1"},
        headers=_user_headers(token),
    )
    rows = r.json() if r.status_code == 200 else []
    if not rows:
        raise HTTPException(
            status_code=404,
            detail={"error_code": "PROJECT_NOT_FOUND",
                    "user_message": "This project could not be found.",
                    "retryable": False},
        )
    project = rows[0]
    # RLS already scoped the read; this is the explicit check on top of it.
    if project.get("owner_user_id") != user_id:
        raise HTTPException(
            status_code=403,
            detail={"error_code": "PROJECT_FORBIDDEN",
                    "user_message": "This project belongs to a different session.",
                    "retryable": False},
        )
    return project


async def _existing_vision(client: httpx.AsyncClient, token: str,
                           idempotency_key: str) -> dict | None:
    """Idempotency is owned by the database: `pwa_visions` carries
    `unique (owner_user_id, idempotency_key)`. A replay returns the first
    result instead of generating (and paying for) a second image."""
    r = await client.get(
        f"{_supabase_url()}/rest/v1/pwa_visions",
        params={"idempotency_key": f"eq.{idempotency_key}", "select": "*", "limit": "1"},
        headers=_user_headers(token),
    )
    rows = r.json() if r.status_code == 200 else []
    return rows[0] if rows else None


# Resilience is NOT implemented here. `generation_resilience` owns the retry and
# post-payment save policy for the whole backend — mobile `/generate` Step 7 uses
# the same module — so there is exactly one copy of that algorithm to reason
# about. This adapter only says WHICH exceptions are transient for its client
# (httpx) and WHICH typed error the user should see when a stage gives up.
_RETRY_ON = (httpx.TransportError,)


async def _resilient(op, *, what: str, on_failure: HTTPException):
    """Bridge the shared policy onto this adapter's error envelope.

    The shared layer raises [PaidResultLost] with the stage that failed; the PWA
    contract speaks `HTTPException(detail={error_code, user_message, retryable})`.
    Translating here is the entire PWA-specific part.
    """
    try:
        return await with_transport_retries(
            op, stage=what, retry_on=_RETRY_ON,
            policy=RetryPolicy(attempts=_TRANSPORT_ATTEMPTS,
                               backoff_s=_TRANSPORT_BACKOFF_S),
        )
    except PaidResultLost as lost:
        raise on_failure from lost.cause


_SOURCE_FETCH_FAILED = HTTPException(
    status_code=502,
    detail={"error_code": "SOURCE_FETCH_FAILED",
            "user_message": "Couldn't load your photo. Try again.",
            "retryable": True,
            # The photo is fetched BEFORE the engine: nothing was paid for yet.
            "render_started": False},
)

_RESULT_SAVE_FAILED = HTTPException(
    status_code=502,
    detail={"error_code": "RESULT_SAVE_FAILED",
            "user_message": "Your vision was created but could not be saved. Try again.",
            "retryable": True,
            # The render completed and WAS billed. Saying otherwise would be a lie.
            "render_started": True},
)

_PERSIST_FAILED = HTTPException(
    status_code=502,
    detail={"error_code": "PERSIST_FAILED",
            "user_message": "Your vision could not be saved. Try again.",
            "retryable": True,
            "render_started": True},
)

# The provider answered, and its answer was "no". Retrying changes nothing.
_ENGINE_REJECTED = HTTPException(
    status_code=502,
    detail={"error_code": "ENGINE_REJECTED",
            "user_message": "Ayden couldn't work with this request. "
                            "Try a different photo or a different wording.",
            "retryable": False,
            "render_started": False},
)

_ENGINE_UNAVAILABLE = HTTPException(
    status_code=502,
    detail={"error_code": "ENGINE_UNAVAILABLE",
            "user_message": "Ayden couldn't reach the design engine. "
                            "Nothing was charged — try again in a moment.",
            "retryable": True},
)


def _render_started(exc: BaseException) -> bool:
    """Did the PAID request actually leave this machine?

    This is the single most consequential question in the whole adapter,
    because it decides whether the user may be told nothing was charged.

    A connect / DNS / TLS failure happens BEFORE a single byte of the request is
    sent: the provider never saw it, so nothing can have been billed.

    "Server disconnected without sending a response" is the opposite. The
    request — the image, the prompt, everything — was transmitted in full, and
    the connection then died while waiting. The provider may well have accepted
    and started it. On 2026-08-07 a real first generation failed exactly this
    way after 61 s, and the old code called it "nothing was charged".

    Both arrive as the SDK's APIConnectionError, so the cause chain is what
    separates them.
    """
    seen: list[BaseException] = []
    cur: BaseException | None = exc
    while cur is not None and cur not in seen:
        seen.append(cur)
        name = type(cur).__name__
        # Sent, then lost → we CANNOT claim it was free.
        if name in ("RemoteProtocolError", "ReadTimeout", "ReadError",
                    "IncompleteRead", "APITimeoutError"):
            return True
        # Never sent → provably free.
        if name in ("ConnectError", "ConnectTimeout", "ConnectionRefusedError",
                    "gaierror", "SSLError", "SSLCertVerificationError"):
            return False
        cur = cur.__cause__ or cur.__context__
    # Unknown shape: assume the worst rather than promise a refund.
    return True


_ENGINE_NO_RESPONSE = HTTPException(
    status_code=502,
    detail={"error_code": "ENGINE_NO_RESPONSE",
            # Deliberately says NOTHING about billing: the request reached the
            # provider and we do not know whether it was processed.
            "user_message": "Ayden couldn't complete this vision. "
                            "You can try again.",
            "retryable": True,
            "render_started": True},
)


def _is_connection_failure(exc: BaseException) -> bool:
    """True when [exc] means the provider could not be reached or did not answer.

    Classified by type NAME rather than by importing the SDK, so this adapter
    keeps zero provider surface (see the isolation tests).
    """
    if isinstance(exc, httpx.TransportError):
        return True
    name = type(exc).__name__
    return name.endswith((
        # never sent
        "ConnectError", "ConnectionError", "ConnectTimeout", "SSLError",
        # sent, then lost
        "APITimeoutError", "TimeoutException", "ReadTimeout", "ReadError",
        "ProtocolError",
    ))


async def _download_original(client: httpx.AsyncClient, token: str, path: str) -> bytes:
    r = await _resilient(
        lambda: client.get(
            f"{_supabase_url()}/storage/v1/object/{_BUCKET}/{path}",
            headers={"apikey": _anon_key(), "Authorization": f"Bearer {token}"},
        ),
        what="download original",
        on_failure=_SOURCE_FETCH_FAILED,
    )
    if r.status_code != 200 or not r.content:
        raise _SOURCE_FETCH_FAILED
    return r.content


async def _upload_generated(client: httpx.AsyncClient, token: str, path: str,
                            data: bytes) -> None:
    r = await _resilient(
        lambda: client.post(
            f"{_supabase_url()}/storage/v1/object/{_BUCKET}/{path}",
            headers={"apikey": _anon_key(), "Authorization": f"Bearer {token}",
                     "Content-Type": "image/jpeg"},
            content=data,
        ),
        what="upload generated",
        on_failure=_RESULT_SAVE_FAILED,
    )
    if r.status_code >= 300:
        # The BODY, not just the status. Storage answers 4xx for a dozen
        # different reasons — a duplicate object, a policy refusal, a rejected
        # mime, a size cap — and they are not the same problem. On 2026-08-11 a
        # paid refine was lost to a bare "status=400" that named none of them,
        # and diagnosing it meant reproducing the whole generation. Bounded, and
        # it is Storage's own error text: no token and no key can appear here.
        try:
            why = r.content[:300].decode("utf-8", "replace")
        except Exception:  # noqa: BLE001
            why = "(unreadable body)"
        log.error("[pwa-staging] generated upload failed status=%s body=%s",
                  r.status_code, why)
        raise _RESULT_SAVE_FAILED



# ── the room Ayden actually resolved ─────────────────────────────────────────
#
# "Your space" is not a room. When the person delegates the choice, ONE gpt-4o
# look at the photo turns it into `living_room`, and THAT is what keys the
# per-room DNA. Mobile returns it (`"room_type": room_type`) and the client
# persists it into the session, so every later turn — the advisor, a refine, a
# switch — is told which room it is talking about.
#
# The PWA had nowhere to put it: the browser kept sending "Your space" for ever,
# and the advisor judged "make the sofa white" with `room_type=None`. The room is
# now written on the vision row AND, when it was delegated, onto the project —
# so a refresh, a Home reopen and a second tab all agree, and Flutter never has
# to invent it.
#
# `_LET_AYDEN_ROOM` (the delegation vocabulary) is defined further down with the
# Ayden Decide block it belongs to and is read at CALL time, so there is one set
# and no copy of it here.


def _room_display(canonical: str) -> str:
    """`living_room` -> `Living Room`. The same convention this file already uses
    for a resolved atmosphere, and the same EN labels mobile persists (the room
    the frontend re-sends is always the canonical EN label, never a localised
    one — see the Room Type i18n contract)."""
    return " ".join(w for w in canonical.replace("_", " ").split()).title()


def _effective_room(body: "PwaGenerateRequest", project: dict,
                    lineage_room: str = "") -> str:
    """What this turn should call the room.

    An explicit choice always wins — resolving over the top of it would override
    the person. Only a delegated room looks anywhere else, and then it prefers
    what THIS branch already resolved before falling back to the project.
    """
    asked = (body.room_label or "").strip()
    if asked and asked.lower() not in _LET_AYDEN_ROOM:
        return asked
    branch = (lineage_room or "").strip()
    if branch:
        return branch
    stored = str(project.get("room_label") or "").strip()
    if stored and stored.lower() not in _LET_AYDEN_ROOM:
        return stored
    resolved = str(project.get("resolved_room_type") or "").strip()
    return _room_display(resolved) if resolved else asked


async def _converse(body: "PwaGenerateRequest", room_label: str = "") -> str:
    """Ayden's own words for a line that asks rather than instructs.

    `generate_chat_response` is the function mobile speaks with (main.py:2645);
    the text is never composed here. A failure costs the sentence, never the
    turn — the caller still gets something to show.
    """
    from prompt_engine import classify_intent, generate_chat_response

    try:
        verdict = classify_intent(body.user_instruction, 2)
        return str(generate_chat_response(
            user_message=body.user_instruction,
            atmosphere_id=body.atmosphere_id or "",
            room_type=room_label or body.room_label or "",
            sub_intent=verdict.sub_intent,
            secondary_spaces=[],
            refinement_state=None,
        ))
    except Exception as exc:  # noqa: BLE001
        log.warning("[pwa-staging] chat reply failed (%s)", type(exc).__name__)
        return ("I didn't catch a change to make there — tell me what you'd "
                "like different and I'll take care of it.")


async def _refine_advisory(body: "PwaGenerateRequest", room_label: str = "") -> tuple:
    """Run the canonical advisor. Returns `(advisory | None, changes)`.

    The parsed changes come back with the verdict so the render executes the
    plan that was judged. Parsing twice meant the advisor blessed one reading of
    the sentence and the engine carried out another — the LLM parser is not
    required to answer identically twice.

    The decision is NOT taken here and NOT taken in Flutter: `refine.parser` and
    `refine.advisor` are the same modules mobile `POST /refine` calls, in the
    same order, with the same client. This function only translates their answer
    into the PWA's response shape.

    `confirm=true` skips it — the user has read the objection and chosen to
    continue, exactly as mobile's "Continue anyway".
    """
    if body.confirm:
        return None, None
    import main as canonical  # already imported by the launcher
    from refine.advisor import advise, build_advisory_message
    from refine.parser import parse_changes

    changes = await parse_changes(body.user_instruction, client=canonical.openai)
    if not changes:
        # No change in the sentence — so it is a QUESTION, and a question is
        # answered, not rendered and not rejected. This is the cheapest correct
        # gate: the refine parser already reads every line before anything is
        # paid for, and unlike an intent classifier it cannot mistake a real
        # instruction for chatter and block it. "What do you think?" is a chip
        # the app itself offers; it used to come back as an error.
        log.info("[pwa-staging] no change parsed — answering instead of rendering")
        return {"status": "answer",
                "message": await _converse(body, room_label),
                "render_started": False}, None
    # The RESOLVED room, not the browser's placeholder. `advise` is room-aware —
    # what is safe to change in a kitchen is not what is safe on a terrace — and
    # it was being handed None on every project where the person let Ayden
    # decide, i.e. the default.
    advice = await advise(changes, (room_label or body.room_label) or None,
                          client=canonical.openai)
    if advice.overall.value == "green":
        return None, changes

    log.info("[pwa-staging] advisor verdict=%s changes=%d — NO render",
             advice.overall.value, len(changes))
    return {
        "status": "advisory",
        "verdict": advice.overall.value,
        "message": build_advisory_message(advice),
        "flagged": [
            {"raw": a.change.raw, "verdict": a.verdict.value,
             "reason": a.reason, "alternative": a.alternative}
            for a in advice.flagged
        ],
        # Nothing was attempted, so nothing could have been billed.
        "render_started": False,
    }, changes


async def _run_canonical_refine(*, image_bytes: bytes, mime: str,
                                user_instruction: str, changes=None) -> tuple:
    """THE canonical REFINE engine — the same modules mobile `POST /refine` uses.

    Why this branch has to exist
    ----------------------------
    A refine was previously composed by `compose_generation_prompt`, the FIRST
    VISION composer, whose contract opens with "Reproduce the photographed
    architecture exactly — every wall, opening, door, window ... Add nothing,
    remove nothing ... do not invent walls, doors or partitions".

    That is the correct contract for a first render and the exact opposite of
    what a refine is for. "break the wall on the right and add a kitchen with
    its island" was therefore sent to the model with an instruction forbidding
    it — the engine was told to refuse the very edit it was asked to make.

    `refine.*` is pure: it takes the provider client, the bytes and the message,
    and imports nothing from Supabase, the session tables or the wallet. So the
    PWA reuses it verbatim rather than growing a second refine semantics.
    """
    import main as canonical  # already imported by the launcher
    from refine.engine import prepare as refine_prepare
    from refine.engine import refine_generate
    from refine.normalizer import normalize_changes
    from refine.parser import parse_changes

    # The advisor already read this sentence and judged THAT reading.
    # Reading it again could execute a different one — the parser is an
    # LLM and is not obliged to answer identically twice. Re-parse only
    # when nobody parsed it yet (confirm=true skips the advisor).
    changes = changes if changes else await parse_changes(user_instruction, client=canonical.openai)
    if not changes:
        raise HTTPException(
            status_code=422,
            detail={"error_code": "EMPTY_REQUEST",
                    "user_message": "I couldn't read a change to make — "
                                    "could you rephrase?",
                    "retryable": False},
        )
    # Same order as the mobile handler: normalize once, then plan once.
    normalize_changes(changes)
    prepared = refine_prepare(changes)
    log.info("[pwa-staging] canonical refine — changes=%d types=%s strategy=%s",
             len(prepared.ordered_changes),
             ",".join(sorted({c.type for c in prepared.ordered_changes})),
             prepared.plan.strategy.kind)
    result = await refine_generate(canonical.openai, image_bytes, mime, changes)
    # The ORDERED plan is returned, not the raw parse: it is what was actually
    # executed, so it is what the stateless verify must be asked about. Mobile
    # echoes exactly this (`prepared.ordered_changes`, main.py:5489).
    return _reencode_jpeg(result.image), list(prepared.ordered_changes)


# ── the recipe is the MODEL's, not the profile's ─────────────────────────────
#
# Measured 2026-08-10 on a real PWA session: 116 s of provider time where mobile
# takes ~40 s end to end, and a living room rendered without its television.
#
# Cause: this adapter read `profile.quality` and got "high", while mobile
# OVERRIDES the profile for gpt-image-2 (main.py, "gpt-image-2 migration
# 2026-06-29"): the model rejects `input_fidelity` and was benched at
# quality="low" — "-84 % coût", frozen on every path, medium explicitly rejected
# at x2.7. Reading the profile therefore produced a recipe nobody ever benched,
# six times the cost and four times the wait, for a different image.
#
# The per-atmosphere `quality_overrides` are gpt-image-1 tuning; mobile bypasses
# them for gpt-image-2 too, so they only apply to the older model here as well.
_MODEL_LOCKED_QUALITY = {"gpt-image-2": "low"}


def _locked_quality(model: str, profile, atmosphere_id: str) -> str:
    """What mobile would send for this model — never a recipe of our own."""
    for prefix, quality in _MODEL_LOCKED_QUALITY.items():
        if model.startswith(prefix):
            return quality
    return dict(profile.quality_overrides).get(atmosphere_id, profile.quality)


# `input_fidelity` is deliberately absent from the call: gpt-image-2 rejects it,
# and mobile pops it for exactly that reason. Do not add it back per-model
# without reading main.py's `_fidelity_override` block first.


# ── how the result travels back, not what it is ─────────────────────────────
#
# A first vision needs ~110 s of provider time and, unstreamed, the connection
# carries NOT ONE BYTE during it. Measured on this network path (2026-08-07):
# an unstreamed response is cut at 61 s — reproduced on /chat/completions as
# well as /images/edits, and on HTTP/1.1 as well as HTTP/2, so it is neither the
# endpoint nor the protocol. The SAME request streamed ran 139 s untouched.
# Whoever holds the stopwatch — a VPN hop, a proxy, a CDN edge, a corporate
# firewall — the rule is the same everywhere: a silent socket is a socket
# somebody may reclaim. Asking for the answer as a stream means bytes start
# flowing in seconds and no idle timer ever arms.
#
# This is TRANSPORT ONLY. Model, prompt, size, quality, input_fidelity and the
# profile are untouched, so the final image is the same image; the completed
# event carries exactly the `b64_json` the unstreamed call returns. Mobile's
# `main.py` is deliberately NOT changed: it runs on Render, where no such
# ceiling has ever been observed, and the image engine is frozen.
#
# How many partial frames. The cut is an IDLE timer BETWEEN bytes (~61 s), and
# every byte restarts it: measured 2026-08-08, one frame moved the cut from 61 s
# to 79 s and no further, because it landed early and left another 61 s of
# silence behind it. Three were needed for a ~110 s render.
#
# At the model's own quality="low" a render is ~25-30 s, so the whole call fits
# inside one gap and a single mid-flight frame is ample insurance for anything up
# to roughly two minutes. Partial frames are billed as extra image output tokens,
# so asking for three we no longer need would be paying for nothing.
#
# No switch guards this. It is one way of fetching one image, not a behaviour to
# choose between at runtime; if it ever needs undoing, git is the undo.
_PARTIAL_IMAGES = 1


async def _edit_streamed(client, kwargs: dict) -> str | None:
    """Run the edit as a stream and return the FINAL image's base64.

    Partial frames are drained and dropped: they exist to keep bytes on the
    wire, never to be shown. Only `image_edit.completed` is a result.
    """
    stream = await client.images.edit(**kwargs, stream=True,
                                      partial_images=_PARTIAL_IMAGES)
    final: str | None = None
    partials = 0
    async for event in stream:
        kind = getattr(event, "type", "")
        if kind == "image_edit.partial_image":
            partials += 1
        elif kind == "image_edit.completed":
            final = event.b64_json
    log.info("[pwa-staging] streamed edit — %d partial frame(s) kept the "
             "connection alive, final=%s", partials, "yes" if final else "no")
    return final


# ── what the photo actually shows ────────────────────────────────────────────
#
# Mobile opens a first vision by describing the room to itself — window count and
# positions, camera angle, perspective, depth, ceiling, structural anchors — and
# feeds that description to the composer. The PWA sent an empty string, so every
# first vision was composed blind to the space it was about to redesign.
#
# The wording below is mobile's, character for character. It is duplicated rather
# than imported because it lives inside the frozen `/generate` handler and not in
# a module; a test reads main.py and fails the moment the two differ, so the copy
# cannot drift silently. Move it to a shared module and this comment goes away.
_ROOM_ANALYSIS_PROMPT = (
    "Analyze this room for an architectural interior photographer. "
    "Provide a structured description covering: "
    "(1) Room type and primary function. "
    "(2) Window count, approximate positions (left/center/right/back wall), "
    "and whether they are floor-to-ceiling or standard height. "
    "(3) Camera angle: eye-level, slightly high, or slightly low. "
    "(4) Perspective: single vanishing point (straight-on) or two-point (corner view). "
    "(5) Visible spatial depth: shallow (flat wall), medium, or deep (visible secondary spaces). "
    "(6) Ceiling: flat, vaulted, exposed beams, or height impression (low/normal/high). "
    "(7) Key structural anchors: any columns, open doorways, kitchen island, fireplace wall. "
    "Be factual and concise \u2014 this is used as generation guidance, not prose description. "
    "Max 4 sentences."
)


async def _describe_room(image_bytes: bytes, profile, iteration: int) -> str:
    """The composer's `room_description`. Non-fatal by contract, like mobile's.

    Only asked for when the composer will actually use it. Measured 2026-08-10
    on the canonical flags: the `source_space` section is 0 characters at
    iteration 1 — `TRUST_PIXELS_V1` tells the engine to read the photo rather
    than a description of it — and 85 from iteration 2. Mobile computes it every
    time and lets the composer discard it on a first vision; the prompt is
    identical either way, so this simply does not buy the call that gets thrown
    away.
    """
    if iteration <= 1:
        return ""
    if not getattr(profile, "vision_analysis_fv", False):
        log.info("[pwa-staging] vision analysis SKIPPED (profile=%s)",
                 getattr(profile, "name", "?"))
        return ""
    import base64

    import main as canonical  # already imported by the launcher

    try:
        b64 = base64.b64encode(image_bytes).decode()
        answer = await canonical.openai.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{
                "role": "user",
                "content": [
                    {"type": "image_url",
                     "image_url": {"url": f"data:image/jpeg;base64,{b64}",
                                   "detail": "high"}},
                    {"type": "text", "text": _ROOM_ANALYSIS_PROMPT},
                ],
            }],
            max_tokens=220,
        )
        text = (answer.choices[0].message.content or "").strip()
        log.info("[pwa-staging] room: %s", text[:160])
        return text
    except Exception as exc:  # noqa: BLE001 — never lose a generation over this
        log.warning("[pwa-staging] vision analysis failed (non-fatal): %s",
                    type(exc).__name__)
        return ""


# ── Ayden Decide / Ayden Signature have to actually decide ───────────────────
#
# Measured 2026-08-10: a living room came back with no television, and the trace
# said why twice over —
#     room='Your space'  atmosphere_id=ayden_signature
#     dna_matched=False  path=fallback_style_block   dna_room_context: 0
#
# "Your space" and "Ayden Signature" are not a room and an atmosphere. They are
# the two ways of saying "you choose". Sent verbatim to the composer they key
# nothing, so the per-room DNA was dropped whole — furniture language, room
# constraints, and the TV anchor with them. Mobile's own comment on the block
# that fixed this for the app: "Before: Ayden Decide kept room_type='' -> DNA
# dropped -> weak atmosphere + drifting TV."
#
# So the choice is made the way mobile makes it, by CALLING the same functions:
#   * `main._classify_ayden`  — ONE gpt-4o look at the photo, room + atmosphere;
#   * `prompt_engine.rank_atmospheres` / `surprise_me` / `SIGNATURE_ATMOSPHERES`
#     — the same acceptance rule and the same curated fallback table;
#   * `label_to_atmosphere_id` — the same label→id mapping.
# Nothing here decides anything those modules do not already decide. One vision
# call serves both answers, as its docstring intends.
_LET_AYDEN_ROOM = {"your space", "ayden decide", ""}
_LET_AYDEN_ATMOSPHERE = {"ayden signature", ""}

# Mobile's floor for accepting the AI's atmosphere pick (main.py: base_compat).
_SIGNATURE_COMPAT_FLOOR = 0.45


class _Decided:
    __slots__ = ("room_type", "atmosphere_id", "atmosphere_label", "stage_room",
                 "resolved_room")

    def __init__(self, room_type: str, atmosphere_id: str, atmosphere_label: str,
                 stage_room: str = "", resolved_room: str = ""):
        self.room_type = room_type
        self.atmosphere_id = atmosphere_id
        self.atmosphere_label = atmosphere_label
        # Non-empty → the preserve contract is swapped for the furnish contract.
        self.stage_room = stage_room
        # The canonical id Ayden READ from the photo (living_room, pool_area),
        # and empty when the person named the room themselves. Kept apart from
        # `room_type` because only a room Ayden resolved may be written back
        # onto the project — overwriting an explicit choice is not a fix.
        self.resolved_room = resolved_room


async def _ayden_decide(image_bytes: bytes, room_label: str,
                        atmosphere_label: str, iteration: int = 1) -> _Decided:
    """Turn "you choose" into a real room and a real atmosphere.

    Whatever the person chose explicitly is never second-guessed. Anything that
    fails falls back to the label we were given, which is the old behaviour — a
    weaker prompt, never a lost generation.
    """
    import main as canonical  # already imported by the launcher
    from prompt_engine import rank_atmospheres, surprise_me
    from prompt_engine.atmosphere_dna import label_to_atmosphere_id
    from prompt_engine.atmosphere_recommender import SIGNATURE_ATMOSPHERES

    wants_room = room_label.strip().lower() in _LET_AYDEN_ROOM
    wants_atmo = atmosphere_label.strip().lower() in _LET_AYDEN_ATMOSPHERE
    decided = _Decided(room_label, label_to_atmosphere_id(atmosphere_label),
                       atmosphere_label)

    seen: dict = {}
    if wants_room or wants_atmo:
        try:
            seen = await canonical._classify_ayden(image_bytes) or {}
        except Exception as exc:  # noqa: BLE001 — never lose a generation over this
            log.warning("[pwa-staging] Ayden vision failed (%s) — keeping the "
                        "labels as sent", type(exc).__name__)
            seen = {}

    if wants_room and seen.get("room"):
        decided.room_type = seen["room"]
        decided.resolved_room = seen["room"]
        log.info("[pwa-staging] Ayden Decide: room=%r conf=%s → keys the per-room "
                 "DNA (furniture language, room constraints, TV anchor)",
                 decided.room_type, seen.get("confidence"))
    elif wants_room:
        log.info("[pwa-staging] Ayden Decide: room unread — keeping %r", room_label)

    # STAGE MODE — the reason an empty room comes back empty.
    #
    # "Preserve" means "restyle the furniture that is there". Shown an EMPTY
    # room it has nothing to restyle, so the render stays bare. Mobile swaps the
    # contract for a furnish one when Ayden Decide read the room itself — and
    # only then, because staging a room the person explicitly named would
    # override their choice.
    #
    # The exterior gate is mobile's own (RCA 2026-07-08): an interior misread as
    # an exterior would otherwise trigger a destructive exterior staging, so an
    # uncorroborated exterior is refused, and only validated exterior rooms
    # (pool_area, terrace) may stage at all.
    if wants_room and iteration == 1 and seen.get("room"):
        if os.environ.get("AYDEN_DECIDE_FURNISH", "0") == "1":
            room = seen["room"]
            gated, reason = canonical.resolve_stage_exterior(
                room, seen.get("confidence", "low"), "", 0.0,
                canonical._EXTERIOR_ROOMS)
            if reason:
                log.info("[pwa-staging] Ayden safety gate: %s", reason)
                room = gated
            if room:
                from prompt_engine.preservation import is_exterior_stage_room

                exterior = room in canonical._EXTERIOR_ROOMS
                if not exterior or is_exterior_stage_room(room):
                    decided.stage_room = room
                else:
                    log.info("[pwa-staging] exterior %r → PRESERVE (STAGE skipped)",
                             room)
        else:
            log.info("[pwa-staging] AYDEN_DECIDE_FURNISH is off — no staging")

    # A room the person NAMED can be just as empty as one Ayden read. Mobile
    # stages those too (main.py:3891-3899, SPECIFIC_ROOM_STAGE default "1"); the
    # PWA only ever staged the delegated case, so naming "Living Room" on a bare
    # room asked the engine to restyle furniture that was not there. Measured on
    # exteriors before this: Garden 3372, Terrace 3785, Balcony 3290 — all
    # PRESERVE. Same maps, same membership test, same kill-switch.
    if (not decided.stage_room and not wants_room and iteration == 1
            and decided.room_type
            and os.environ.get("SPECIFIC_ROOM_STAGE", "1") == "1"):
        from prompt_engine.preservation import is_exterior_stage_room

        key = "_".join(decided.room_type.strip().lower().split())
        key = canonical._SPECIFIC_STAGE_MAP.get(key, key)
        if key in canonical._SPECIFIC_STAGE_ROOMS or is_exterior_stage_room(key):
            decided.stage_room = key
            log.info("[pwa-staging] SpecificStage room=%r → stage_room=%s",
                     decided.room_type, key)
        else:
            log.info("[pwa-staging] SpecificStage skipped — unsupported room %r",
                     decided.room_type)

    if not wants_atmo:
        return decided

    # Mobile's acceptance rule, verbatim in effect: the AI's pick is used only if
    # it is one of the validated Signature atmospheres, is not low-confidence,
    # and is not a poor fit for the room. Otherwise the curated table decides,
    # itself restricted to the same validated set.
    room_for_atmo = decided.room_type if decided.room_type not in _LET_AYDEN_ROOM else ""
    chosen = ""
    ai_atmo = seen.get("atmosphere") or ""
    if ai_atmo:
        score = dict(rank_atmospheres(room_for_atmo)).get(ai_atmo, 0.0)
        in_signature = ai_atmo in SIGNATURE_ATMOSPHERES
        if in_signature and seen.get("confidence") != "low" and score >= _SIGNATURE_COMPAT_FLOOR:
            chosen = ai_atmo
            log.info("[pwa-staging] Ayden Signature: ai=%s conf=%s compat=%.2f → "
                     "SELECTED", ai_atmo, seen.get("confidence"), score)
        else:
            log.info("[pwa-staging] Ayden Signature: ai=%s in_signature=%s "
                     "compat=%.2f → curated table decides",
                     ai_atmo, in_signature, score)
    if not chosen:
        try:
            chosen = surprise_me(room_type=room_for_atmo, vision_description="",
                                 user_prompt="", only=list(SIGNATURE_ATMOSPHERES))
        except Exception as exc:  # noqa: BLE001
            log.warning("[pwa-staging] Ayden Signature table failed (%s) — "
                        "keeping %r", type(exc).__name__, atmosphere_label)
            return decided
    if chosen:
        decided.atmosphere_id = chosen
        decided.atmosphere_label = chosen.replace("_", " ").title()
        log.info("[pwa-staging] Ayden Signature → %s (%s) — the DNA now has an "
                 "atmosphere to key on", decided.atmosphere_label, decided.atmosphere_id)
    return decided


async def _run_canonical_engine(*, image_bytes: bytes, room_label: str,
                                atmosphere_label: str, atmosphere_id: str,
                                user_instruction: str, iteration: int,
                                prev_atmosphere_id: str = "",
                                lineage_customized: bool | None = None,
                                history: list | None = None,
                                ) -> tuple[bytes, "_Decided"]:
    """THE canonical engine. Every symbol below is imported from the modules the
    mobile `/generate` already uses — same composer, same DNA, same provider,
    same profile. Nothing here decides prompt content.

    Returns the image AND what was decided, because "Ayden Signature" and "Your
    space" are resolved in here and the row that records this vision has to say
    which atmosphere and which room were actually used. Storing the meta-choice
    instead was a real defect: the next switch then read `ayden_signature` as its
    previous atmosphere, which is not an atmosphere at all.
    """
    import main as canonical  # already imported by the launcher
    from generation_profiles import get_active_profile

    # THE composer mobile resolved, not the package default.
    #
    # `from prompt_engine import compose_generation_prompt` binds the FROZEN v1
    # composer unconditionally: main.py's COMPOSER_VERSION=v2 rebind only
    # replaces the symbol in main's OWN globals. Importing from the package gave
    # this adapter a different composer from the one mobile runs — no switch
    # awareness, no REBOOT_FRESH header, and `prev_atmosphere_id` /
    # `lineage_customized` accepted and then ignored. Reading main's attribute
    # follows whatever mobile resolved, today and after any future rebind.
    compose_generation_prompt = canonical.compose_generation_prompt

    profile = get_active_profile()
    decided = await _ayden_decide(image_bytes, room_label, atmosphere_label,
                                  iteration)
    atmosphere_id = decided.atmosphere_id
    design_prompt = compose_generation_prompt(
        style_label=decided.atmosphere_label,
        room_type=decided.room_type,
        room_description=await _describe_room(image_bytes, profile, iteration),
        user_instruction=user_instruction,
        iteration=iteration,
        # The conversation, rebuilt from this BRANCH's rows (`_history_from`).
        #
        # It was `[]`, and that emptied the one thing a customised switch is for.
        # The composer's REBOOT_CUSTOMIZED path calls
        # `_filter_history_to_customizations(history)` and hands the result to
        # `_build_user_block` as `refinement_history_override`, so an empty list
        # means "this person has changed nothing" and the switch silently
        # discarded every spatial edit they had made — a moved TV, an added bed —
        # while still being labelled CUSTOMIZED.
        #
        # The filtering stays entirely in the composer, exactly where mobile put
        # it: what is passed here is the raw branch, unjudged.
        history=history or [],
        compact_prompts=profile.compact_prompts,
        # The lineage the composer needs to tell a switch from an iteration. The
        # PWA has always had these in its vision rows; it simply never sent them,
        # so a switch was composed as if nothing came before it.
        prev_atmosphere_id=prev_atmosphere_id,
        lineage_customized=lineage_customized,
    )
    # NOTE on editorial realism: composer_v2 owns that decision. It hands a first
    # vision back to the frozen composer with the flag OFF (composer_v2.py:1020),
    # which is precisely what stops the realism block from pushing the prompt over
    # budget and evicting `dna_room_context` — the section carrying the room's
    # furniture language and the TV anchor. Passing it from here is neither
    # possible nor needed; binding the right composer is what fixed it.
    if decided.stage_room:
        from prompt_engine.preservation import apply_stage_mode

        design_prompt, staged = apply_stage_mode(
            design_prompt, room_label=decided.stage_room,
            atmosphere_label=decided.atmosphere_label,
            atmosphere_id=atmosphere_id,
        )
        log.info("[pwa-staging] STAGE MODE %s (room=%s)",
                 "applied" if staged else "NO-OP (no preserve contract found)",
                 decided.stage_room)
    output_size = profile.size_override or canonical._detect_output_size(image_bytes)

    img_file = io.BytesIO(image_bytes)
    img_file.name = "source.jpg"
    kwargs = {
        "model": canonical.IMAGE_MODEL,
        "image": img_file,
        "prompt": design_prompt,
        "size": output_size,
        "quality": _locked_quality(canonical.IMAGE_MODEL, profile, atmosphere_id),
        "n": 1,
    }
    log.info("[pwa-staging] canonical engine — model=%s size=%s quality=%s "
             "prompt_chars=%d",
             kwargs["model"], output_size, kwargs["quality"], len(design_prompt))
    try:
        b64 = await _edit_streamed(canonical.openai, kwargs)
    except Exception as exc:  # noqa: BLE001 — re-raised unless it is a connect failure
        # The provider READ the request and refused it (content policy, bad
        # image). Nothing was rendered and nothing will be: offering "try again"
        # invites the person to pay the same 30 seconds for the same refusal.
        # Mobile treats it as terminal and refunds (main.py:4686-4713).
        if type(exc).__name__ == "BadRequestError":
            log.error("[pwa-staging] engine REFUSED the request: %s",
                      type(exc).__name__)
            raise _ENGINE_REJECTED from exc
        if _is_connection_failure(exc):
            started = _render_started(exc)
            log.error("[pwa-staging] engine unreachable: %s (request_sent=%s)",
                      type(exc).__name__, started)
            # NEVER retried here: a call that may have reached the provider must
            # not be repeated blindly.
            raise (_ENGINE_NO_RESPONSE if started else _ENGINE_UNAVAILABLE) from exc
        raise
    import base64

    if not b64:
        raise HTTPException(
            status_code=502,
            detail={"error_code": "EMPTY_RESULT",
                    "user_message": "The engine returned no image. Try again.",
                    "retryable": True},
        )
    return _reencode_jpeg(base64.b64decode(b64)), decided


def _reencode_jpeg(raw: bytes) -> bytes:
    """The canonical Step-6b output pipeline: gpt-image-* returns 2-3 MB of PNG,
    which is a poor thing to push through Storage and back down to a browser.
    Same recipe as the mobile path — q=85, optimize, progressive, alpha flattened
    onto white — so the PWA serves the same bytes-per-render the mobile app does.

    Deliberately NOT watermarked: the free-tier mark is a monetisation decision
    owned by the mobile billing path, and staging has no wallet to consult."""
    from PIL import Image as PilImage

    try:
        with PilImage.open(io.BytesIO(raw)) as src:
            if src.mode in ("RGBA", "LA", "P"):
                rgba = src.convert("RGBA")
                flat = PilImage.new("RGB", src.size, (255, 255, 255))
                flat.paste(rgba, mask=rgba.split()[-1])
                src = flat
            elif src.mode != "RGB":
                src = src.convert("RGB")
            buf = io.BytesIO()
            src.save(buf, format="JPEG", quality=85, optimize=True, progressive=True)
            out = buf.getvalue()
        log.info("[pwa-staging] re-encoded %d -> %d bytes (%.2fx, JPEG q=85)",
                 len(raw), len(out), len(raw) / max(len(out), 1))
        return out
    except Exception as exc:  # noqa: BLE001
        # A re-encode failure must not lose a paid-for render: ship the original
        # bytes rather than failing the generation.
        log.warning("[pwa-staging] JPEG re-encode failed (%s) — storing raw bytes",
                    type(exc).__name__)
        return raw


@router.get("/health")
async def pwa_health() -> dict:
    """Confirms the adapter is mounted AND pointed at staging — without ever
    echoing a URL or a key."""
    _supabase_url()
    return {
        "status": "ok",
        "target": "staging",
        "project_ref": _STAGING_REF,
        # False the moment a claim has had to fail open — a deployment without
        # the durable lifecycle must not look identical to one with it.
        "durable_lifecycle": _CLAIM_FAIL_OPEN_COUNT == 0,
        "claim_fail_open_count": _CLAIM_FAIL_OPEN_COUNT,
    }



# ── what engine is ACTUALLY running ──────────────────────────────────────────
#
# Every parity claim made about this deployment so far has been made about
# SOURCE — which composer the code binds, which flags `run.sh` pins. Source is
# not what renders an image. A process started before a flag was added, or with
# an operator's own export in the environment, runs a different engine while
# every test still passes.
#
# So this asks the LIVE process. Nothing here maintains a list: the flag names
# come from `engine_flags.canonical_flags()`, which reads `run.sh`, and the
# values come from the canonical modules themselves. Adding a flag to `run.sh`
# adds it here with no second edit — and no environment variable outside that
# repo-defined key set can ever be echoed, which is what keeps a secret out of
# the answer.
#
# Staging only: this router is mounted by `run_pwa_staging.py` and by nothing
# else, so neither mobile nor production gains an endpoint.
@router.get("/engine")
async def pwa_engine_identity() -> dict:
    """The EFFECTIVE generation runtime, as this process would use it."""
    import main as canonical  # already imported by the launcher
    from engine_flags import canonical_flags
    from generation_profiles import get_active_profile

    profile = get_active_profile()
    composer = canonical.compose_generation_prompt
    return {
        # Which composer main RESOLVED — the adapter reads this same attribute,
        # so a mismatch here is a mismatch in the render.
        "composer": f"{composer.__module__}.{composer.__name__}",
        "composer_version": os.environ.get("COMPOSER_VERSION", "v1"),
        "app_env": os.environ.get("APP_ENV", ""),
        "profile": {
            "name": profile.name,
            "quality": profile.quality,
            "quality_overrides": dict(profile.quality_overrides),
            "input_fidelity": profile.input_fidelity or "",
            "size_override": profile.size_override or "",
            "compact_prompts": profile.compact_prompts,
            "use_mask": profile.use_mask,
            "vision_analysis_fv": profile.vision_analysis_fv,
            "max_attempts": profile.max_attempts,
        },
        "model": canonical.IMAGE_MODEL,
        # What the adapter would actually SEND — the model-locked recipe, not
        # the profile's, because that is the difference that cost 116 s and a
        # missing television.
        "effective_quality": _locked_quality(canonical.IMAGE_MODEL, profile, ""),
        "input_fidelity_sent": False,  # gpt-image-2 rejects it; mobile pops it too
        # Only the keys `run.sh` itself pins. A name absent from run.sh cannot
        # appear, so this cannot become a way to read the environment.
        "flags": {name: os.environ.get(name, "") for name in canonical_flags()},
    }


# ── PROCESSING is not a failure ──────────────────────────────────────────────
#
# When the durable claim is held elsewhere, `/generate` answers
# `{"status": "processing"}`. The browser turned that into a red banner —
# "Ayden is still working on this one, try again" — while a paid render it had
# ALREADY started was running underneath. Mobile does the opposite and says so
# in as many words (chat_screen.dart, PR2b Slice 1):
#
#     202 — another process owns this intent. No crash, no error, no re-fire:
#     keep the loading bubble and attach to the reconciliation poll so the
#     winner's image renders here.
#
# This endpoint is that reconciliation poll. It is a pure READ — no advisor, no
# parse, no provider, nothing billable — so a client may call it every few
# seconds for as long as a render takes. Re-POSTing `/generate` would have done
# the same job and re-run the refine parser (a real gpt-4o call) on every tick.
@router.get("/generation/{idempotency_key}")
async def pwa_generation_status(
    idempotency_key: str,
    authorization: str | None = Header(default=None),
) -> dict:
    """Where one logical generation has got to. Read-only, free, idempotent.

    The VISION ROW is the authority: if it exists the operation completed, no
    matter what the claim says (a settle can fail after the row is written —
    that is deliberate, see `_settle_claim`). The claim is consulted only when
    there is no row yet, to tell "still rendering" from "failed".
    """
    token = _bearer(authorization)
    async with httpx.AsyncClient(timeout=httpx.Timeout(30.0, connect=10.0)) as client:
        await _verify_user(client, token)

        row = await _existing_vision(client, token, idempotency_key)
        if row:
            return {"state": "COMPLETED", "vision_id": row["id"],
                    "vision_number": row["vision_number"],
                    "image_path": row["image_path"],
                    "resolved_room_type": row.get("room_label") or "",
                    "resolved_atmosphere_id": row.get("atmosphere_id") or "",
                    "resolved_atmosphere_label": row.get("atmosphere_label") or "",
                    "lineage_customized": bool(row.get("lineage_customized"))}

        r = await client.get(
            f"{_supabase_url()}/rest/v1/pwa_generation_claims",
            params={"idempotency_key": f"eq.{idempotency_key}",
                    "select": "state,error_code,render_started", "limit": "1"},
            headers=_user_headers(token),
        )
        rows = r.json() if r.status_code == 200 else []
        if not isinstance(rows, list) or not rows:
            # No row and no claim. Either it was never started, or the durable
            # lifecycle was unavailable and this process failed open. Saying
            # UNKNOWN rather than FAILED is the honest answer: the caller keeps
            # its own timeout instead of being told a render died.
            return {"state": "UNKNOWN"}
        claim = rows[0]
        state = str(claim.get("state") or "PROCESSING")
        return {"state": state,
                "error_code": claim.get("error_code") or "",
                "render_started": bool(claim.get("render_started"))}


class PwaChatRequest(BaseModel):
    """One typed line, before anything is decided about it."""

    project_id: str
    message: str
    ui_locale: str = "en"


# ── the conversational turn ──────────────────────────────────────────────────
#
# THE defect this closes (found by the real smoke, 2026-08-11): every typed line
# went straight to the refine pipeline, so a QUESTION bought an image.
#
#     "what do you think of this space?"  ->  parse_changes -> 1 change (modify)
#                                         ->  advisor green
#                                         ->  a paid render, and a permanent
#                                             Vision titled with the question
#
# The adapter did have a gate — "no change parsed => answer" — but it is the
# WRONG gate, and measurement says so: asked directly, the canonical
# `refine.parser` returns a `modify` change for all three of
# "what do you think?", "what do you think of this space?" and "how does this
# room feel to you?". The parser's job is to read an instruction, not to decide
# whether a sentence is one.
#
# Mobile never asks it that question. It has a conversational turn FIRST
# (chat_screen.dart `_send`): `POST /chat` answers, and only `should_generate`
# lets a generation follow. That decision is a long canonical chain — Wave 4.11d
# generation dominance, the meta-intent and out-of-scope branches, the quota
# gate, `classify_intent`, the PR3 opinion-question downgrade, confirmation
# resolution, ambiguity, MIXED — and the ONE thing this adapter must not do is
# have an opinion about any of it.
#
# So it does not reimplement the chain: it CALLS `main.chat`, the same async
# function the mobile route calls, with the same arguments. FastAPI's
# `Depends(require_active_identity)` only runs through the router, so passing
# `current_user` explicitly bypasses it and nothing else changes. One brain, two
# callers — the rule this whole adapter is built on.
@router.post("/chat")
async def pwa_chat(
    body: PwaChatRequest,
    authorization: str | None = Header(default=None),
) -> dict:
    """Ayden's answer, and whether this line is worth an image.

    Fails CLOSED: anything unexpected answers conversationally and does NOT
    authorise a render. A bug here must cost a sentence, never money.
    """
    token = _bearer(authorization)
    async with httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=10.0)) as client:
        user_id = await _verify_user(client, token)
        project = await _load_project(client, token, user_id, body.project_id)

        r = await client.get(
            f"{_supabase_url()}/rest/v1/pwa_visions",
            params={"project_id": f"eq.{body.project_id}",
                    "select": "id,vision_number,action_type,image_path,atmosphere_id,"
                              "atmosphere_label,parent_vision_id,prompt_text,"
                              "lineage_customized,room_label",
                    "order": "vision_number.asc"},
            headers=_user_headers(token),
        )
        rows = r.json() if r.status_code == 200 else []
        rows = rows if isinstance(rows, list) else []

    tip = rows[-1] if rows else None
    # The same branch history the composer receives, so the conversation and the
    # render reason about one lineage.
    chain = _ancestry(rows, str(tip.get("id"))) if tip else []
    room = _effective_room(
        PwaGenerateRequest(project_id=body.project_id, room_label="",
                           atmosphere_id="", atmosphere_label="",
                           original_image_path="", idempotency_key=""),
        project,
        next((str(v.get("room_label") or "").strip()
              for v in reversed(chain) if str(v.get("room_label") or "").strip()), ""),
    )

    import json as _json

    import main as canonical  # already imported by the launcher
    from auth import CurrentUser

    try:
        answer = await canonical.chat(
            session_id=body.project_id,
            message=body.message,
            # Mobile sends the atmosphere LABEL it is currently showing.
            style_label=str((tip or {}).get("atmosphere_label")
                            or project.get("selected_atmosphere_label") or ""),
            room_type=room,
            # Mobile sends the iteration this line would PRODUCE. At 1 the
            # canonical classifier short-circuits to GENERATE ("there is nothing
            # to chat about yet"), which is why a project with no vision must
            # still count as 1 and not 0.
            iteration=len(rows) + 1,
            history=_json.dumps(_history_from(chain)),
            secondary_spaces="",
            ui_locale=body.ui_locale or "en",
            has_vision="1" if rows else "0",
            generation_in_progress="0",
            # Deliberately empty: the PWA holds Storage PATHS, and minting a
            # signed URL here would spend a round-trip on a field the canonical
            # turn carries as a situational fact rather than opens.
            current_image_url="",
            displayed_version_id=str((tip or {}).get("id") or ""),
            original_image_url="",
            current_user=CurrentUser(user_id=user_id, is_anonymous=True),
        )
    except Exception as exc:  # noqa: BLE001 — fail CLOSED, never toward spending
        # The one canonical branch that reaches production-only tables is the
        # quota question ("how many do I have left"), which this tenancy has no
        # wallet to answer. It — and any other surprise — must land here as a
        # conversational non-answer, never as an authorisation to render.
        log.warning("[pwa-staging] canonical chat failed (%s) — answering "
                    "without authorising a render", type(exc).__name__)
        return {"ai_message": "I didn't quite catch that — tell me what you'd "
                              "like to change and I'll take care of it.",
                "should_generate": False, "suggestions": [],
                "intent": "unavailable", "sub_intent": "unavailable"}

    answer = answer if isinstance(answer, dict) else {}
    should = bool(answer.get("should_generate"))
    log.info("[pwa-staging] chat — intent=%s/%s should_generate=%s room=%s iter=%d",
             answer.get("intent"), answer.get("sub_intent"), should, room,
             len(rows) + 1)
    return {
        "ai_message": str(answer.get("ai_message") or ""),
        "should_generate": should,
        "suggestions": [str(s) for s in (answer.get("suggestions") or [])],
        "intent": str(answer.get("intent") or ""),
        "sub_intent": str(answer.get("sub_intent") or ""),
    }


class PwaVerifyRequest(BaseModel):
    """Stateless, exactly like mobile's: the caller carries the data."""

    project_id: str
    before_path: str
    after_path: str
    changes: list = Field(default_factory=list)


# ── the verify SECOND call ───────────────────────────────────────────────────
#
# Mobile runs it AFTER the image is on screen, never before, and never blocking
# (`unawaited(_kickoffRefineVerify(mySeq))`, chat_screen.dart:2600). It is free —
# one gpt-4o-mini look, not a generation — and it is SILENT unless the verdict is
# `incomplete`, which is the only state where what is missing is actually known:
#
#     verified    → image seule (P3), rien.
#     unavailable → rien du tout (pas de bulle, pas de spinner).
#
# It changes no advisor state, gates nothing, and a failure degrades to
# `unavailable` rather than to an error. Those are the properties being matched;
# the endpoint exists here rather than reusing `POST /refine/verify` because
# that one authenticates against the PRODUCTION identity tables, which this
# tenancy does not have. The MODULE that answers is the same one.
@router.post("/refine/verify")
async def pwa_refine_verify(
    body: PwaVerifyRequest,
    authorization: str | None = Header(default=None),
) -> dict:
    """`verified | incomplete | unavailable` + report + missing[]. Never raises
    into the caller's face: every failure is `unavailable`, which the client
    renders as silence."""
    token = _bearer(authorization)
    unavailable = {"verification": "unavailable",
                   "report": "Ayden couldn't automatically verify this result.",
                   "missing": []}
    try:
        parsed = [_change_from_dict(d) for d in body.changes if isinstance(d, dict)]
    except Exception:  # noqa: BLE001
        parsed = []
    if not parsed:
        return unavailable

    try:
        import main as canonical  # already imported by the launcher
        from refine.verify import build_report, missing_changes
        from refine.verify import verify as refine_verify

        async with httpx.AsyncClient(timeout=httpx.Timeout(60.0, connect=10.0)) as client:
            user_id = await _verify_user(client, token)
            _assert_owned_path(body.before_path, user_id, body.project_id)
            _assert_owned_path(body.after_path, user_id, body.project_id)
            before = await _download_original(client, token, body.before_path)
            after = await _download_original(client, token, body.after_path)

        result = await refine_verify(canonical.openai, before, "image/jpeg",
                                     after, parsed)
        return {
            "verification": result.status.value,
            # `build_report` returns None when there is nothing worth saying.
            # Normalised to "" because the client's rule is "empty report → stay
            # silent", and null and "" must not mean two different things.
            "report": build_report(result, parsed) or "",
            "missing": [_change_to_dict(c) for c in missing_changes(result, parsed)],
            "identity_preserved": result.identity_preserved,
            "needs_refinement": result.needs_refinement,
        }
    except HTTPException:
        # A forged path is still a refusal — verify is fail-open about the
        # PROVIDER, not about tenancy.
        raise
    except Exception as exc:  # noqa: BLE001 — verify never blocks a shown image
        log.warning("[pwa-staging] verify failed (non-blocking): %s",
                    type(exc).__name__)
        return unavailable


@router.post("/generate")
async def pwa_generate(
    body: PwaGenerateRequest,
    authorization: str | None = Header(default=None),
) -> dict:
    """The public entry point. Its only job beyond delegating is to guarantee
    that this endpoint ALWAYS answers.

    An exception escaping a handler ends the request without a response, and a
    client cannot tell that apart from a backend that is down — which is exactly
    how a Storage outage came to be reported to a user as "check your
    connection". Whatever fails, the caller gets a typed, honest payload.
    """
    # Single-flight: one logical operation, one render. A second caller with the
    # same key does not start a second generation — it awaits the first and
    # receives its answer. This is what protects a double-click, two concurrent
    # submits, and a retry fired while the first render is still running.
    key = _flight_key(_bearer(authorization)[-24:], body.idempotency_key)
    running = _INFLIGHT.get(key)
    if running is not None and not running.done():
        log.info("[pwa-staging] single-flight — joining the in-flight generation")
        return await asyncio.shield(running)

    task = asyncio.ensure_future(_guarded(body, authorization))
    _INFLIGHT[key] = task
    try:
        return await task
    finally:
        if _INFLIGHT.get(key) is task:
            _INFLIGHT.pop(key, None)


async def _guarded(
    body: PwaGenerateRequest,
    authorization: str | None,
) -> dict:
    try:
        return await _generate(body, authorization)
    except HTTPException:
        raise  # already typed and deliberate
    except Exception as exc:  # noqa: BLE001 — the invariant IS "always answer"
        # Deliberately a catch-all. Narrowing it to httpx let a provider-SDK
        # connect failure escape on 2026-08-06 and killed the connection, which
        # the app could only report as "check your connection". Anything that
        # reaches here is a bug or an outage; either way the caller gets a typed
        # payload and the type is logged for us, not for them.
        # No attempt to guess WHICH dependency failed here: the engine call and
        # each Storage stage already raise their own typed error at the point
        # where the answer is actually known. Guessing at this distance would
        # produce a confident, wrong message — the exact failure mode being
        # fixed. This is the honest fallback for everything else.
        log.error("[pwa-staging] unhandled %s reached the handler",
                  type(exc).__name__, exc_info=exc)
        raise HTTPException(
            status_code=502,
            detail={"error_code": "UNKNOWN_FAILURE",
                    # Deliberately says nothing about billing. We do not know
                    # here whether the paid call started, and claiming "nothing
                    # was charged" on a guess is how a user is told their vision
                    # is free when it was not.
                    "user_message": "Ayden couldn't complete this vision. "
                                    "You can try again.",
                    "retryable": True,
                    "render_started": None},
        ) from exc


async def _generate(
    body: PwaGenerateRequest,
    authorization: str | None,
) -> dict:
    token = _bearer(authorization)

    async with httpx.AsyncClient(timeout=httpx.Timeout(300.0, connect=10.0)) as client:
        user_id = await _verify_user(client, token)

        # Replay before anything expensive: a double-click, a retry or an F5
        # must never produce a second image or a second row.
        prior = await _existing_vision(client, token, body.idempotency_key)
        if prior:
            log.info("[pwa-staging] idempotent replay — returning the existing vision")
            return {"status": "completed", "replayed": True,
                    "vision_id": prior["id"], "vision_number": prior["vision_number"],
                    "image_path": prior["image_path"]}

        project = await _load_project(client, token, user_id, body.project_id)
        _assert_owned_path(body.original_image_path, user_id, body.project_id)

        if body.parent_vision_id:
            r = await client.get(
                f"{_supabase_url()}/rest/v1/pwa_visions",
                params={"id": f"eq.{body.parent_vision_id}",
                        "project_id": f"eq.{body.project_id}",
                        "select": "id", "limit": "1"},
                headers=_user_headers(token),
            )
            if not (r.status_code == 200 and r.json()):
                raise HTTPException(
                    status_code=403,
                    detail={"error_code": "PARENT_FORBIDDEN",
                            "user_message": "That vision does not belong to this project.",
                            "retryable": False},
                )

        # Only a refine is parsed and judged; every other action reaches the
        # engine with nothing pre-read.
        parsed_changes = None

        # ── The advisor answers BEFORE anything is paid for ──────────────────
        # Same order and same modules as mobile: parse, then advise. A non-green
        # verdict is an ANSWER, not a render — the endpoint returns it and stops.
        # This is what makes "Want me to apply it?" and a running generation
        # mutually exclusive: only one of the two can ever leave this function.
        if body.action_type == "refine":
            if not body.user_instruction.strip():
                # A refine with nothing to apply is a malformed request, not a
                # re-render. Falling through would quietly hand it to the
                # first-vision composer and bill a render nobody asked for.
                raise HTTPException(
                    status_code=422,
                    detail={"error_code": "EMPTY_REQUEST",
                            "user_message": "I couldn't read a change to make — "
                                            "could you rephrase?",
                            "retryable": False,
                            "render_started": False},
                )
            # The advisor is told which room this is. `_effective_room` reads the
            # project's persisted answer, so a delegated room stops being "Your
            # space" the moment Ayden has resolved it once.
            advisory, parsed_changes = await _refine_advisory(
                body, _effective_room(body, project))
            if advisory is not None:
                return advisory

        # ── Reserve the operation BEFORE anything is paid for ───────────────
        # Everything above this line is a read. From here on a provider call
        # becomes possible, so the claim is taken first: exactly one caller may
        # proceed, and that decision survives a restart because Postgres — not
        # this process's memory — makes it.
        claim = await _claim_generation(client, token, body)
        if not claim.won:
            if claim.state == "COMPLETED" and claim.result_vision_id:
                log.info("[pwa-staging] durable claim COMPLETED — returning the "
                         "existing vision, no render")
                prior_done = await _existing_vision(client, token,
                                                    body.idempotency_key)
                if prior_done:
                    return {"status": "completed", "replayed": True,
                            "vision_id": prior_done["id"],
                            "vision_number": prior_done["vision_number"],
                            "image_path": prior_done["image_path"]}
            # Someone else holds it and is still rendering. The caller is told
            # to keep waiting rather than being handed a second paid render.
            log.info("[pwa-staging] durable claim held elsewhere (state=%s) — "
                     "no second render", claim.state)
            return {"status": "processing", "replayed": False,
                    "idempotency_key": body.idempotency_key,
                    "render_started": True}

        # From here the claim is HELD. Anything that goes wrong must release it,
        # or this operation can never be retried.
        try:
            return await _generate_claimed(client, token, body, project,
                                           user_id, parsed_changes)
        except HTTPException as http_exc:
            detail = http_exc.detail if isinstance(http_exc.detail, dict) else {}
            await _settle_claim(
                client, token, body.idempotency_key,
                error_code=str(detail.get("error_code") or "UNKNOWN_FAILURE"),
                render_started=bool(detail.get("render_started")),
            )
            raise
        except BaseException:
            # Includes cancellation: a client that disconnects must not leave a
            # claim wedged for the next attempt.
            await _settle_claim(client, token, body.idempotency_key,
                                error_code="UNKNOWN_FAILURE", render_started=True)
            raise


# ── which image the engine actually edits, and what came before it ───────────
#
# THE defect this closes (found 2026-08-08 by the real staging smoke): every
# generation — first vision, switch AND refine — was handed the uploaded photo.
# So "make the bedding white" did not whiten the bedding of the vision on
# screen; it re-edited the empty room and returned a bare bedroom with a white
# bed. Refinements could never accumulate, because each one started over.
#
# Mobile decides this server-side, from the history, and so does this. The rule
# is mobile's (main.py, Wave 5.3 switch-source override), not a new one:
#
#   refine  -> the vision being refined. You edit what you are looking at.
#   switch  -> V1 when the lineage is a pure chain of atmospheres; the vision
#              being switched once the person has refined something.
#   initial -> the original photo.
#
# The switch rule is mobile's Wave 5.21, and it is worth stating exactly because
# reading the wrong thing here is what produced the 2026-08-10 regression: a
# switch was sent the ORIGINAL PHOTO, so the engine was asked to "restyle the
# existing furniture" of an EMPTY room. It came back rebuilt — television gone,
# orientation drifted. The stale comment above that block in main.py still says
# "override source_mode to ORIGINAL"; the code below it does not:
#
#     source_mode = "SPECIFIC_VERSION"; source_version_id = _v1.version_id
#     "[Wave5.21-EXPERIMENT] ... source pinned to V1 - cascade-free anchor"
#
# V1 is the clean architectural reference, one cascade step from the photo, and
# it is furnished — which is what makes "restyle the existing furniture" mean
# something. Switching from LATEST instead would compound quality decay across a
# long atmosphere-shopping session; switching from the photo restyles nothing.
# The customized branch keeps LATEST, verbatim: "source_mode kept as LATEST
# (preserve user changes)".
#
# The same read also answers what the composer needs to know about the lineage.
# The client keeps sending `original_image_path`; it never chooses the source.

# ── the lineage is a BRANCH, never a bag of rows ─────────────────────────────
#
# THE defect this closes (2026-08-11): "has the person customised anything?" was
# answered by scanning EVERY vision in the project —
#
#     customized = any(v["action_type"] == "refine" for v in rows)
#
# — so on
#
#     V1
#     ├── V2 refine ── V3 refine
#     └── (user goes back to V1 and switches atmosphere)
#
# the new branch inherited a customisation that happened on a DIFFERENT branch.
# It was then composed REBOOT_CUSTOMIZED, sourced from the vision being switched
# instead of V1, and carried refinement memory belonging to a lineage the person
# had deliberately left.
#
# Mobile does not scan. It reads ONE record — the SOURCE the generation is
# edited from — and that record carries a flag computed cumulatively when it was
# WRITTEN (main.py "β (2026-06-22): cumulative lineage_customized"):
#
#     /generate : new = source.lineage_customized OR is_spatial_edit(this)
#     /refine   : new = true            (refine/orchestrator_adapter.py:90)
#
# O(1) at read time, correct across branches by construction. `pwa_visions`
# now carries the same column (migration 0005), and the walk below exists only
# for rows written before it — where NULL means "unknown", never "no".


def _ancestry(rows: list, leaf_id: str) -> list[dict]:
    """The branch from the root down to [leaf_id], oldest first.

    Only the visions this one actually descends from. A sibling branch is not an
    ancestor and must not be visible here — that is the whole point.
    """
    by_id = {str(v.get("id")): v for v in rows if v.get("id")}
    chain: list[dict] = []
    seen: set[str] = set()
    cur = by_id.get(str(leaf_id))
    while cur is not None and str(cur.get("id")) not in seen:
        seen.add(str(cur.get("id")))
        chain.append(cur)
        parent_id = cur.get("parent_vision_id")
        cur = by_id.get(str(parent_id)) if parent_id else None
    chain.reverse()
    return chain


def _customized_from(parent: dict, chain: list[dict], rows: list) -> bool:
    """The SOURCE record's verdict, exactly as mobile reads it.

    Three tiers, in mobile's own order of authority:

    1. The STORED flag. Written cumulatively along the branch, so it is O(1) and
       correct across branches by construction. This is what mobile reads
       (`_src_record.lineage_customized`) and it wins whenever it exists.

    2. No stored flag (a row written before migration 0005), but the branch can
       still be reconstructed from `parent_vision_id` → walk the ANCESTRY. A
       sibling branch is not an ancestor, so it cannot contaminate.

    3. No stored flag AND no link to walk → the LEGACY project-wide scan.
       Deliberately the coarse answer, and deliberately not `False`: mobile's
       own comment on the identical fallback is "never silently FRESH". Being
       told your sofa survived a switch when it did not is worse than a switch
       that is more conservative than it needed to be.
    """
    stored = parent.get("lineage_customized")
    if stored is not None:
        return bool(stored)
    linked = bool(parent.get("parent_vision_id")) or parent.get("vision_number") == 1
    if linked:
        return any(v.get("action_type") == "refine" for v in chain)
    log.info("[pwa-staging] lineage: parent %s carries neither a stored flag nor "
             "a parent link — falling back to the legacy project scan (never "
             "silently FRESH)", parent.get("id"))
    return any(v.get("action_type") == "refine" for v in rows)


def _is_spatial(action_type: str, instruction: str, iteration: int) -> bool:
    """Does THIS generation physically change the space?

    Mobile's answer, obtained from mobile's own classifier rather than restated
    here:
      * a refine is a spatial edit by contract — `refine/orchestrator_adapter`
        writes `lineage_customized=True` on every refine version, unconditionally;
      * anything else is classified by `classify_transformation` and judged by
        `is_spatial_edit`, the same pair `/generate` uses. A first vision and an
        atmosphere switch are not spatial; an instruction that moves or adds
        something is.
    """
    if action_type == "refine":
        return True
    text = (instruction or "").strip()
    if not text:
        return False
    try:
        from prompt_engine.composer_v2 import is_spatial_edit
        from prompt_engine.transformation_classifier import classify_transformation

        return bool(is_spatial_edit(classify_transformation(text, iteration)))
    except Exception as exc:  # noqa: BLE001 — never lose a generation over this
        log.warning("[pwa-staging] spatial classification failed (%s) — "
                    "treating as non-spatial", type(exc).__name__)
        return False


def _history_from(chain: list[dict]) -> list[dict]:
    """The chat history the composer expects, rebuilt from the durable record.

    Mobile sends the conversation itself: every text message, `{role, content}`,
    oldest first (chat_screen.dart `contextMessages`). The composer then does ALL
    the filtering — `_filter_history_to_customizations` keeps only the user lines
    that classify as real spatial customisations on REBOOT_CUSTOMIZED, and
    `suppress_refinement_memory` drops the lot on REBOOT_FRESH.

    The PWA's equivalent of "what the user asked for" is the instruction that
    produced each vision, and it is already stored per row. Rebuilding the list
    HERE, from the branch, is what keeps the filtering where mobile put it: in
    the composer. Nothing in Flutter decides what counts as a customisation.

    Only ancestors are included — a refine on a sibling branch is not part of
    this lineage's memory.
    """
    out: list[dict] = []
    for v in chain:
        text = str(v.get("prompt_text") or "").strip()
        if text:
            out.append({"role": "user", "content": text})
    return out


class _Lineage:
    """What the project's own vision rows say about where this generation comes
    from. One read, every answer."""

    __slots__ = ("source_path", "prev_atmosphere_id", "customized", "history",
                 "resolved_room", "chain")

    def __init__(self, source_path: str, prev_atmosphere_id: str = "",
                 customized: bool | None = None, history: list | None = None,
                 resolved_room: str = "", chain: list | None = None):
        self.source_path = source_path
        # The atmosphere of the vision being branched from. The composer uses it
        # to tell a real atmosphere SWITCH from another pass at the same one; sent
        # empty, every switch looked like a first attempt.
        self.prev_atmosphere_id = prev_atmosphere_id
        # Has the person made real changes in THIS branch? A refine is a change.
        # None means "unknown, fall back to the legacy history scan" — never a
        # silent "no".
        self.customized = customized
        # The conversation, rebuilt from the branch. [] is not "empty history" by
        # accident here: on a pure switch the composer suppresses memory anyway.
        self.history = history or []
        # The room the parent vision was actually rendered as.
        self.resolved_room = resolved_room
        # The branch itself, oldest first — used to compute the new row's flag.
        self.chain = chain or []


async def _load_lineage(client: httpx.AsyncClient, token: str,
                        body: "PwaGenerateRequest", user_id: str) -> _Lineage:
    """Read the project's visions ONCE and derive everything that depends on them."""
    if body.action_type not in ("refine", "switch_atmosphere") or not body.parent_vision_id:
        return _Lineage(body.original_image_path)

    r = await client.get(
        f"{_supabase_url()}/rest/v1/pwa_visions",
        params={"project_id": f"eq.{body.project_id}",
                "select": "id,vision_number,action_type,image_path,atmosphere_id,"
                          "parent_vision_id,prompt_text,lineage_customized,room_label"},
        headers=_user_headers(token),
    )
    rows = r.json() if r.status_code == 200 else []
    if not isinstance(rows, list) or not rows:
        return _Lineage(body.original_image_path)

    parent = next((v for v in rows if v.get("id") == body.parent_vision_id), None)
    if not parent or not parent.get("image_path"):
        # The named parent is not in this project (RLS already scoped the read),
        # so it is not something this caller may branch from.
        return _Lineage(body.original_image_path)

    # The BRANCH this generation belongs to — not the project.
    chain = _ancestry(rows, body.parent_vision_id)
    customized = _customized_from(parent, chain, rows)
    history = _history_from(chain)
    resolved_room = next(
        (str(v.get("room_label") or "").strip()
         for v in reversed(chain) if str(v.get("room_label") or "").strip()), "")
    prev_atmo = str(parent.get("atmosphere_id") or "")
    chosen = parent

    if body.action_type == "switch_atmosphere" and not customized:
        # Mobile scans the ledger REVERSED so a mid-session re-upload, whose
        # fresh vision is ALSO number 1, pins the lineage the person is actually
        # in rather than the first one ever made.
        v1 = next((v for v in reversed(rows)
                   if v.get("vision_number") == 1 and v.get("image_path")), None)
        if v1:
            chosen = v1
        else:
            # Mobile's own fallback when the V1 entry is missing: LATEST, i.e.
            # the vision being switched. Never the photo.
            log.info("[pwa-staging] switch: no V1 row — falling back to the "
                     "vision being switched")

    path = str(chosen["image_path"])
    # Same guard as the client-supplied path: the row came from an RLS-scoped
    # read, and it is still checked before a byte is fetched.
    _assert_owned_path(path, user_id, body.project_id)
    log.info("[pwa-staging] source for %s = vision %s (%s) \u2014 "
             "prev_atmosphere=%s customized=%s (branch=%d rows, history=%d) "
             "room=%s",
             body.action_type, chosen.get("vision_number"), chosen.get("id"),
             prev_atmo or "(none)", customized, len(chain), len(history),
             resolved_room or "(none)")
    return _Lineage(path, prev_atmo, customized, history, resolved_room, chain)


async def _resolve_source_path(client: httpx.AsyncClient, token: str,
                               body: "PwaGenerateRequest", user_id: str) -> str:
    """Just the source image — kept as its own name because that is how it reads
    at the call site and in the tests that pin the rule."""
    return (await _load_lineage(client, token, body, user_id)).source_path


async def _generate_claimed(
    client: httpx.AsyncClient,
    token: str,
    body: PwaGenerateRequest,
    project: dict,
    user_id: str,
    changes=None,
) -> dict:
    """The paid half, with the durable claim already held by this caller."""
    if True:
        lineage = await _load_lineage(client, token, body, user_id)
        original = await _download_original(client, token, lineage.source_path)

        # A REFINE edits the vision the user is looking at, under the refine
        # contract. A first vision and an atmosphere switch re-render the source
        # under the preserve contract. Sending the first through the second is
        # what made a structural edit impossible; the two are now routed apart,
        # each to the module mobile already uses for it.
        decided = None
        # The room this turn is about — an explicit choice, else whatever Ayden
        # resolved earlier in this branch or on this project. Never "Your space"
        # once it has been answered.
        room_label = _effective_room(body, project, lineage.resolved_room)
        applied_changes = changes
        if body.action_type == "refine" and body.user_instruction.strip():
            generated, applied_changes = await _run_canonical_refine(
                image_bytes=original,
                mime="image/jpeg",
                user_instruction=body.user_instruction,
                changes=changes,
            )
        else:
            generated, decided = await _run_canonical_engine(
                image_bytes=original,
                room_label=room_label,
                atmosphere_label=body.atmosphere_label,
                atmosphere_id=body.atmosphere_id,
                user_instruction=body.user_instruction,
                iteration=body.vision_number,
                prev_atmosphere_id=lineage.prev_atmosphere_id,
                lineage_customized=lineage.customized,
                history=lineage.history,
            )

        # What the ENGINE used, as a label. A room Ayden READ comes back as a
        # canonical id (`living_room`) and is displayed the way mobile displays
        # it; a room the person named is already a label and is kept verbatim.
        used_room = (_room_display(decided.resolved_room)
                     if decided and decided.resolved_room else room_label)
        # β — cumulative along THIS branch, computed at write exactly as mobile
        # does, so the read stays O(1) and a sibling branch stays isolated.
        new_customized = bool(lineage.customized) or _is_spatial(
            body.action_type, body.user_instruction, body.vision_number)

        vision_id = str(uuid.uuid4())
        image_path = (f"users/{user_id}/projects/{body.project_id}"
                      f"/generated/{vision_id}.jpg")
        await _upload_generated(client, token, image_path, generated)

        row = {
            "id": vision_id,
            "project_id": body.project_id,
            "owner_user_id": user_id,
            "vision_number": body.vision_number,
            "parent_vision_id": body.parent_vision_id or None,
            "action_type": body.action_type,
            "prompt_text": body.user_instruction or None,
            # What was actually used, not what the browser asked for. A refine
            # keeps its parent's atmosphere (it does not choose one), so the
            # client's value is right there and wrong nowhere else.
            "atmosphere_id": decided.atmosphere_id if decided else body.atmosphere_id,
            "atmosphere_label": (decided.atmosphere_label if decided
                                 else body.atmosphere_label),
            "image_source": "staging_storage",
            "image_path": image_path,
            "idempotency_key": body.idempotency_key,
            # The branch's own verdict, and the room the engine actually keyed
            # its DNA on. Both are read back by the NEXT generation on this
            # branch, so they are facts about this vision and not about the
            # project — which is precisely why scanning the project was wrong.
            "lineage_customized": new_customized,
            "room_label": used_room or None,
        }
        # The image is in Storage now, so this row is the last thing standing
        # between a paid render and an orphan file: retry the transport.
        r = await _resilient(
            lambda: client.post(f"{_supabase_url()}/rest/v1/pwa_visions",
                                json=row, headers=_user_headers(token, write=True)),
            what="insert vision",
            on_failure=_PERSIST_FAILED,
        )
        if r.status_code == 409:
            # Lost a concurrent race on the idempotency key — the winner's row is
            # the answer. The image just produced is discarded, never a 2nd vision.
            winner = await _existing_vision(client, token, body.idempotency_key)
            if winner:
                return {"status": "completed", "replayed": True,
                        "vision_id": winner["id"],
                        "vision_number": winner["vision_number"],
                        "image_path": winner["image_path"]}
        if r.status_code >= 300:
            # The image EXISTS and has been paid for. Failing the request here
            # would tell the person their vision is gone while it sits in
            # Storage, and would settle the claim FAILED so a retry buys a second
            # one. Mobile answers 200 with `message_persisted:false` and lets the
            # client carry the row (main.py:5113-5131); the same applies here.
            log.error("[pwa-staging] vision insert failed status=%s — returning "
                      "the image anyway, row not persisted", r.status_code)
            await _settle_claim(client, token, body.idempotency_key,
                                vision_id=vision_id)
            return {"status": "completed", "persisted": False,
                    "vision_id": vision_id, "vision_number": body.vision_number,
                    "image_path": image_path,
                    **_resolved_echo(decided, used_room, new_customized,
                                     applied_changes)}

        patch = {"current_vision_id": vision_id,
                 "cover_vision_id": project.get("cover_vision_id") or vision_id,
                 "status": "active"}
        # The resolved room, promoted to the PROJECT — but only when the person
        # delegated it. Mobile's rule verbatim ("Only when we had no room
        # (delegated) → never overrides an explicit pick", chat_screen.dart).
        # This is what makes the answer survive an F5 with no tab open to
        # remember it, and what stops the next turn from asking about "Your
        # space" again.
        asked = (body.room_label or "").strip().lower()
        if (decided and decided.resolved_room
                and (not asked or asked in _LET_AYDEN_ROOM)
                and not str(project.get("resolved_room_type") or "").strip()):
            patch["resolved_room_type"] = decided.resolved_room
            patch["room_label"] = _room_display(decided.resolved_room)
            patch["room_id"] = decided.resolved_room
            log.info("[pwa-staging] project room resolved → %s (was delegated)",
                     decided.resolved_room)
        await client.patch(
            f"{_supabase_url()}/rest/v1/pwa_projects",
            params={"id": f"eq.{body.project_id}"},
            json=patch,
            headers=_user_headers(token, write=True),
        )

        await _settle_claim(client, token, body.idempotency_key,
                            vision_id=vision_id)
        log.info("[pwa-staging] vision %s persisted for project %s",
                 vision_id[:8], body.project_id[:8])
        return {"status": "completed", "replayed": False, "vision_id": vision_id,
                "vision_number": body.vision_number, "image_path": image_path,
                **_resolved_echo(decided, used_room, new_customized,
                                 applied_changes)}


def _resolved_echo(decided, used_room: str, customized: bool,
                   changes=None) -> dict:
    """What the engine DECIDED, handed back to the client.

    Mobile answers the same three questions on every `/generate`
    (`room_type`, the version ledger's atmosphere, and the version record) and
    the client adopts them — which is how a delegated room and "Ayden Signature"
    stop being placeholders after the first render. Sending them makes the
    browser a reader of the engine's decisions rather than a second decider.

    `changes` is the refine echo, carried for the STATELESS verify second call —
    mobile's `result['changes']` (chat_screen.dart:2318), passed straight back to
    `/refine/verify`. Nothing re-parses the sentence to obtain it.
    """
    echo: dict = {
        "resolved_room_type": used_room or "",
        "lineage_customized": customized,
    }
    if decided is not None:
        echo["resolved_atmosphere_id"] = decided.atmosphere_id
        echo["resolved_atmosphere_label"] = decided.atmosphere_label
        echo["stage_applied"] = bool(decided.stage_room)
        # True only when Ayden READ the room from the photo. The client uses it
        # the way mobile does — adopt when nothing was chosen, never override an
        # explicit pick.
        echo["room_was_delegated"] = bool(decided.resolved_room)
    if changes:
        echo["changes"] = [_change_to_dict(c) for c in changes]
    return echo


def _change_to_dict(change) -> dict:
    """One parsed change as JSON — mobile's OWN serializer, not a second one.

    `main._refine_change_to_dict` is what `POST /refine` echoes and what
    `POST /refine/verify` reads back. Retyping those five fields here would
    create a shape that drifts the first time one is added; calling it cannot."""
    import main as canonical  # already imported by the launcher

    return canonical._refine_change_to_dict(change)


def _change_from_dict(d: dict):
    """The inverse, same reasoning — `main._refine_change_from_dict`."""
    import main as canonical  # already imported by the launcher

    return canonical._refine_change_from_dict(d)
