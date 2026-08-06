"""PWA STAGING ADAPTER — a new ACCESS to the canonical engine, not a new engine.

What this module is
-------------------
The mobile `/generate` handler owns an orchestration the PWA staging project
cannot satisfy: `public.sessions`, `wallets`, `passes`, `generation_intents`.
Those tables do not exist in the staging project and creating them needs DDL
access this environment does not have.

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

import io
import logging
import os
import uuid

import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

log = logging.getLogger("aih")

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


async def _download_original(client: httpx.AsyncClient, token: str, path: str) -> bytes:
    r = await client.get(
        f"{_supabase_url()}/storage/v1/object/{_BUCKET}/{path}",
        headers={"apikey": _anon_key(), "Authorization": f"Bearer {token}"},
    )
    if r.status_code != 200 or not r.content:
        raise HTTPException(
            status_code=502,
            detail={"error_code": "SOURCE_FETCH_FAILED",
                    "user_message": "Couldn't load your photo. Try again.",
                    "retryable": True},
        )
    return r.content


async def _upload_generated(client: httpx.AsyncClient, token: str, path: str,
                            data: bytes) -> None:
    r = await client.post(
        f"{_supabase_url()}/storage/v1/object/{_BUCKET}/{path}",
        headers={"apikey": _anon_key(), "Authorization": f"Bearer {token}",
                 "Content-Type": "image/jpeg"},
        content=data,
    )
    if r.status_code >= 300:
        log.error("[pwa-staging] generated upload failed status=%s", r.status_code)
        raise HTTPException(
            status_code=502,
            detail={"error_code": "RESULT_SAVE_FAILED",
                    "user_message": "Your vision was created but could not be saved. Try again.",
                    "retryable": True},
        )


async def _run_canonical_engine(*, image_bytes: bytes, room_label: str,
                                atmosphere_label: str, atmosphere_id: str,
                                user_instruction: str, iteration: int) -> bytes:
    """THE canonical engine. Every symbol below is imported from the modules the
    mobile `/generate` already uses — same composer, same DNA, same provider,
    same profile. Nothing here decides prompt content."""
    import main as canonical  # already imported by the launcher
    from generation_profiles import get_active_profile
    from prompt_engine import compose_generation_prompt

    profile = get_active_profile()
    design_prompt = compose_generation_prompt(
        style_label=atmosphere_label,
        room_type=room_label,
        room_description="",
        user_instruction=user_instruction,
        iteration=iteration,
        history=[],
        compact_prompts=profile.compact_prompts,
    )
    output_size = profile.size_override or canonical._detect_output_size(image_bytes)

    img_file = io.BytesIO(image_bytes)
    img_file.name = "source.jpg"
    kwargs = {
        "model": canonical.IMAGE_MODEL,
        "image": img_file,
        "prompt": design_prompt,
        "size": output_size,
        "quality": dict(profile.quality_overrides).get(atmosphere_id, profile.quality),
        "n": 1,
    }
    log.info("[pwa-staging] canonical engine — model=%s size=%s quality=%s prompt_chars=%d",
             kwargs["model"], output_size, kwargs["quality"], len(design_prompt))
    response = await canonical.openai.images.edit(**kwargs)
    import base64

    b64 = response.data[0].b64_json
    if not b64:
        raise HTTPException(
            status_code=502,
            detail={"error_code": "EMPTY_RESULT",
                    "user_message": "The engine returned no image. Try again.",
                    "retryable": True},
        )
    return _reencode_jpeg(base64.b64decode(b64))


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
    return {"status": "ok", "target": "staging", "project_ref": _STAGING_REF}


@router.post("/generate")
async def pwa_generate(
    body: PwaGenerateRequest,
    authorization: str | None = Header(default=None),
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

        original = await _download_original(client, token, body.original_image_path)
        generated = await _run_canonical_engine(
            image_bytes=original,
            room_label=body.room_label or project.get("room_label", ""),
            atmosphere_label=body.atmosphere_label,
            atmosphere_id=body.atmosphere_id,
            user_instruction=body.user_instruction,
            iteration=body.vision_number,
        )

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
            "atmosphere_id": body.atmosphere_id,
            "atmosphere_label": body.atmosphere_label,
            "image_source": "staging_storage",
            "image_path": image_path,
            "idempotency_key": body.idempotency_key,
        }
        r = await client.post(f"{_supabase_url()}/rest/v1/pwa_visions",
                              json=row, headers=_user_headers(token, write=True))
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
            log.error("[pwa-staging] vision insert failed status=%s", r.status_code)
            raise HTTPException(
                status_code=502,
                detail={"error_code": "PERSIST_FAILED",
                        "user_message": "Your vision could not be saved. Try again.",
                        "retryable": True},
            )

        await client.patch(
            f"{_supabase_url()}/rest/v1/pwa_projects",
            params={"id": f"eq.{body.project_id}"},
            json={"current_vision_id": vision_id,
                  "cover_vision_id": project.get("cover_vision_id") or vision_id,
                  "status": "active"},
            headers=_user_headers(token, write=True),
        )

        log.info("[pwa-staging] vision %s persisted for project %s",
                 vision_id[:8], body.project_id[:8])
        return {"status": "completed", "replayed": False, "vision_id": vision_id,
                "vision_number": body.vision_number, "image_path": image_path}
