"""
Generation Intent v1 — PR1 : observation pure.

Spec : docs/GENERATION_INTENT_V1_SPEC.md (§2 identité, §5 tables, §13 plan PR1).

Ce module donne une existence PERSISTÉE à l'intention de génération, en
OBSERVATION uniquement. Il n'enforce rien :

  • AUCUN claim, AUCUN court-circuit — le garde d'idempotence actuel
    (client_request_id, main.py) reste la clé active.
  • Toutes les fonctions observe_* sont BEST-EFFORT : elles avalent leurs
    erreurs (comme confirm/fail_generation dans quota.py) et ne peuvent
    JAMAIS faire échouer /generate.
  • Zéro impact DNA / preservation / fidelity / openai.images.edit.

Objectif : mesurer en prod, sur des lignes persistées, la gate-of-proof
(§2.2) et « 1 Intent / N Jobs » AVANT de basculer le claim en source de
vérité (PR2).

API
───
compute_intent_id(...)                 → IntentIdentity  (fonction PURE)
observe_intent_start(intent_id, ...)   → "NEW" | "DUP" | None
observe_job_start(intent_id, attempt)  → job_id (str) | None
observe_job_end(job_id, status, ...)   → None
observe_intent_end(intent_id, status)  → None
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import uuid
from dataclasses import dataclass
from typing import Any, Optional

log = logging.getLogger("generation_intent.observer")

# ── Compteurs d'issue du claim (PR2 — pilotage prod) ─────────────────────────
# In-memory (remis à zéro au redéploiement) : donne un snapshot LIVE via
# GET /internal/claim-stats. La métrique DURABLE reste le log `[CLAIM-OUTCOME]`
# (grep sur une semaine de logs Render survit aux restarts). Outcomes attendus :
#   won · running · replay · replay_no_payload · reclaim_won · failed_refused ·
#   fail_open
#
# RÈGLE OPS (décision user, 2026-07-02) — fail-open est OBSERVABLE, pas aveugle :
#   • fail_open == 0 durablement            → ne rien toucher.
#   • fail_open > 0 (surtout récurrent)     → INCIDENT : analyser, et si ça
#     persiste, basculer le wrapper en fail-CLOSED (lever 503, le frontend retry).
# Décision pilotée par la donnée, pas par la peur. Le résiduel de double via
# fail-open exige un hoquet claim-RPC + une concurrence même-intent SIMULTANÉS.
import collections  # noqa: E402
CLAIM_COUNTERS: "collections.Counter[str]" = collections.Counter()


def bump_claim(outcome: str) -> int:
    """Incrémente le compteur d'issue et renvoie le total courant (pour le log)."""
    CLAIM_COUNTERS[outcome] += 1
    return CLAIM_COUNTERS[outcome]


def _get_supa():
    """Lazy import to avoid a circular dependency at module load (mirrors quota.py)."""
    from main import supa  # noqa: PLC0415
    return supa


# ── Identité de l'Intent (fonction pure) ─────────────────────────────────────


@dataclass(frozen=True)
class IntentIdentity:
    """Résultat de compute_intent_id. `id` = l'intent_id déterministe.

    Les autres champs sont les composantes normalisées (utiles pour le log
    [INTENT-ID] existant et pour la colonne jsonb `intent`).
    """
    id: str
    src_sha1: str
    room: str
    atmosphere: str
    mode: str
    source_mode: str
    prompt_dir: str
    revision: str

    @property
    def action(self) -> str:
        # Format historique : "{mode}|{source_mode}|{prompt_dir}"
        return f"{self.mode}|{self.source_mode}|{self.prompt_dir}"

    @property
    def intent_dict(self) -> dict:
        # Colonne jsonb `intent` de generation_intents (§5.1).
        return {
            "room": self.room,
            "atmosphere": self.atmosphere,
            "mode": self.mode,
            "source_mode": self.source_mode,
            "src_sha1": self.src_sha1,
            "revision": self.revision,
        }


def compute_intent_id(
    *,
    user_id: str,
    session_id: str,
    source_version_id: str,
    original_image_url: str,
    before_image_url: str,
    iteration: int,
    room_type_id: str,
    room_type: str,
    atmosphere_id: str,
    style_label: str,
    prompt: str,
    generation_mode: str,
    source_mode: str,
    generation_attempt: str,
    let_ai_decide: bool,
    surprise_me_flag: bool,
) -> IntentIdentity:
    """Calcule l'intent_id déterministe (backend-authoritative, spec §3).

    ⚠️ Réplique À L'IDENTIQUE l'ancien calcul [INTENT-ID] de main.py
    (composition, ordre des champs, défauts, troncatures) — le hash DOIT
    rester byte-identique pour préserver la gate-of-proof (§2.2). Ne PAS
    « améliorer » la recette ici sans re-valider la gate-of-proof en prod.
    """
    src_ref = (source_version_id or original_image_url or before_image_url or "").strip()
    src_sha1 = hashlib.sha1(src_ref.encode("utf-8")).hexdigest()[:12] if src_ref else "(nosrc)"

    atmosphere = (
        "let-decide" if let_ai_decide
        else "surprise" if surprise_me_flag
        else (atmosphere_id or style_label or "(none)").strip()
    )
    room = "let-decide" if let_ai_decide else (room_type_id or room_type or "(none)").strip()

    prompt_dir = (
        hashlib.sha1(prompt.encode("utf-8")).hexdigest()[:8]
        if (prompt or "").strip() else "noprompt"
    )
    mode = generation_mode or "preserve"
    src_mode = source_mode or "default"
    revision = (generation_attempt or "0").strip()

    raw = (
        f"{user_id}:{session_id}:{src_sha1}:{iteration}:"
        f"{room}:{mode}|{src_mode}|{prompt_dir}:{atmosphere}:{revision}"
    )
    intent_id = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:12]

    return IntentIdentity(
        id=intent_id,
        src_sha1=src_sha1,
        room=room,
        atmosphere=atmosphere,
        mode=mode,
        source_mode=src_mode,
        prompt_dir=prompt_dir,
        revision=revision,
    )


# ── Observation (best-effort — ne lève jamais) ───────────────────────────────


def _session_uuid_or_none(session_id: Optional[str]) -> Optional[str]:
    # Comme quota.reserve_generation : 'new'/'' (non-uuid) → NULL en base.
    return session_id if session_id and session_id not in ("new", "") else None


async def observe_intent_start(
    *,
    intent_id: str,
    user_id: str,
    session_id: Optional[str],
    iteration: int,
    intent: dict,
    client_request_id: str,
    supa=None,
) -> Optional[str]:
    """Upsert generation_intents (status=RUNNING) en ON CONFLICT DO NOTHING.

    Renvoie "NEW" (première observation de cet intent_id) ou "DUP" (déjà vu
    — c'est la PREUVE directe de GATE 2 : un duplicata qui, aujourd'hui,
    serait masqué par le garde d'idempotence). Best-effort → None si erreur.

    N'ENFORCE RIEN : l'appelant continue exactement comme aujourd'hui,
    qu'on renvoie NEW ou DUP.
    """
    supa = supa or _get_supa()
    row = {
        "intent_id": intent_id,
        "user_id": user_id,
        "session_id": _session_uuid_or_none(session_id),
        "iteration": iteration,
        "status": "RUNNING",
        "intent": intent,
        "client_request_id": client_request_id,
        "started_at": "now()",
    }
    try:
        result = await asyncio.to_thread(
            lambda: supa.table("generation_intents")
            .upsert(row, on_conflict="intent_id", ignore_duplicates=True)
            .execute()
        )
        # ignore_duplicates : data non-vide = ligne insérée (NEW) ;
        # data vide = conflit ignoré (DUP).
        is_new = bool(getattr(result, "data", None))
        verdict = "NEW" if is_new else "DUP"
        if not is_new:
            # DUP — la MÊME intention est refirée (preuve GATE 2). Incrément
            # ATOMIQUE de fire_count sur la ligne existante (RPC — un simple
            # UPDATE SET x=x+1, non exprimable via PostgREST) pour que %DUP soit
            # une métrique SQL de premier ordre. Best-effort : n'affecte rien.
            try:
                await asyncio.to_thread(
                    lambda: supa.rpc(
                        "increment_intent_fire", {"p_intent_id": intent_id}
                    ).execute()
                )
            except Exception as inc_exc:
                log.warning(
                    "[INTENT-OBS] fire_count increment failed (swallowed) "
                    "intent_id=%s err=%s: %s",
                    intent_id, type(inc_exc).__name__, inc_exc,
                )
        log.info(
            "[INTENT-OBS] intent_start intent_id=%s result=%s user=%s session=%s iter=%s",
            intent_id, verdict, user_id[:8], session_id or "(none)", iteration,
        )
        # NB (Billing PR2b) : le RUNNING/HOLD n'est PLUS émis ici. Le claim atomique
        # (main.py) a remplacé observe_intent_start (aucun appelant) ; le HOLD est
        # posé sur le chemin winner de /generate, gated par is_free (D-e).
        return verdict
    except Exception as exc:
        log.warning(
            "[INTENT-OBS] intent_start FAILED (swallowed) intent_id=%s err=%s: %s",
            intent_id, type(exc).__name__, exc,
        )
        return None


async def observe_job_start(intent_id: str, attempt_no: int, *, supa=None) -> Optional[str]:
    """Insert une ligne generation_jobs (status=RUNNING) pour cette tentative.

    Renvoie le job_id (uuid) pour clôture ultérieure, ou None si erreur /
    conflit (ex. duplicata sur (intent_id, attempt_no) — évidence, avalée).
    """
    supa = supa or _get_supa()
    job_id = str(uuid.uuid4())
    try:
        await asyncio.to_thread(
            lambda: supa.table("generation_jobs")
            .insert({
                "job_id": job_id,
                "intent_id": intent_id,
                "attempt_no": attempt_no,
                "status": "RUNNING",
                "started_at": "now()",
            })
            .execute()
        )
        log.info(
            "[INTENT-OBS] job_start intent_id=%s attempt=%d job=%s",
            intent_id, attempt_no, job_id,
        )
        return job_id
    except Exception as exc:
        log.warning(
            "[INTENT-OBS] job_start FAILED (swallowed) intent_id=%s attempt=%d err=%s: %s",
            intent_id, attempt_no, type(exc).__name__, exc,
        )
        return None


async def observe_job_end(
    job_id: Optional[str],
    status: str,
    *,
    error_type: Optional[str] = None,
    cost_usd_estimate: Optional[float] = None,
    openai_request_id: Optional[str] = None,
    supa=None,
) -> None:
    """UPDATE generation_jobs (status terminal SUCCEEDED|FAILED). Best-effort."""
    if not job_id:
        return
    supa = supa or _get_supa()
    patch: dict[str, Any] = {"status": status, "ended_at": "now()"}
    if error_type is not None:
        patch["error_type"] = error_type
    if cost_usd_estimate is not None:
        patch["cost_usd_estimate"] = cost_usd_estimate
    if openai_request_id is not None:
        patch["openai_request_id"] = openai_request_id
    try:
        await asyncio.to_thread(
            lambda: supa.table("generation_jobs")
            .update(patch).eq("job_id", job_id).execute()
        )
        log.info("[INTENT-OBS] job_end job=%s status=%s error_type=%s", job_id, status, error_type)
    except Exception as exc:
        log.warning(
            "[INTENT-OBS] job_end FAILED (swallowed) job=%s err=%s: %s",
            job_id, type(exc).__name__, exc,
        )


async def get_latest_intent_for_session(
    *,
    user_id: str,
    session_id: str,
    supa=None,
) -> Optional[dict]:
    """PR3 — LECTURE SEULE. Renvoie l'état du dernier Intent (par `created_at`)
    pour `(user, session)` : `{intent_id, status, iteration, has_result}`, ou
    None. Permet au frontend de se ré-attacher à une génération en cours après
    un kill d'app (il n'a peut-être jamais reçu l'`intent_id`). Aucune écriture,
    aucun claim, aucun OpenAI. Best-effort → None si erreur.
    """
    supa = supa or _get_supa()
    sid = _session_uuid_or_none(session_id)
    if sid is None:
        return None
    try:
        result = await asyncio.to_thread(
            lambda: supa.table("generation_intents")
            .select("intent_id, status, iteration, result_ref")
            .eq("user_id", user_id)
            .eq("session_id", sid)
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
        rows = getattr(result, "data", None) or []
        if not rows:
            return None
        row = rows[0]
        _status = row.get("status")
        _rr = row.get("result_ref")
        # Fix "adopt completed generations" — expose l'URL de l'image générée
        # (LECTURE SEULE, additif) pour que l'accueil ADOPTE une gen terminée
        # hors-session (le résultat existe côté backend mais la carte retombe sur
        # la source). UNE colonne result_ref, DEUX formes : V1 /generate stocke le
        # payload complet (clé after_image_url) ; /refine stocke generated_image_url.
        # Gaté sur SUCCEEDED : on n'expose l'URL qu'au terminal succès (jamais un
        # result_ref mi-vol écrit avant la transition, cf. fenêtres de crash refine).
        _after = ""
        if _status == "SUCCEEDED" and isinstance(_rr, dict):
            _after = _rr.get("after_image_url") or _rr.get("generated_image_url") or ""
        # Repli LECTURE SEULE : un intent V1 réparé par le worker de réconciliation
        # atteint SUCCEEDED SANS result_ref (le repair n'écrit que le statut) —
        # l'image existe pourtant (message image_result persisté, Wave 5.6). On la
        # récupère depuis le dernier image_result de la session pour rester adoptable.
        # Toujours read-only (SELECT), aucune génération, aucune écriture.
        if _status == "SUCCEEDED" and not _after:
            try:
                _msg = await asyncio.to_thread(
                    lambda: supa.table("messages")
                    .select("after_image_url")
                    .eq("session_id", sid)
                    .eq("message_type", "image_result")
                    .order("created_at", desc=True)
                    .limit(1)
                    .execute()
                )
                _mrows = getattr(_msg, "data", None) or []
                if _mrows:
                    _after = _mrows[0].get("after_image_url") or ""
            except Exception:
                pass  # best-effort : sans URL la carte reste simplement sur la source
        return {
            "intent_id": row.get("intent_id"),
            "status": _status,
            "iteration": row.get("iteration"),
            "has_result": _rr is not None,
            "after_image_url": _after,
        }
    except Exception as exc:
        log.warning(
            "[INTENT-OBS] get_latest failed (swallowed) session=%s err=%s: %s",
            session_id, type(exc).__name__, exc,
        )
        return None


async def get_intent_by_id(
    *,
    user_id: str,
    intent_id: str,
    supa=None,
) -> Optional[dict]:
    """Phase 1 (Generation Orchestrator) — LECTURE SEULE par id, pour la récupération
    unifiée (GET /v1/intents/by-id/{id}). Le backend est service-role (RLS bypassée),
    donc on filtre EXPLICITEMENT sur user_id → jamais l'intent d'autrui. Renvoie
    `{intent_id, status, iteration, has_result, result_ref}` ou None. Best-effort."""
    supa = supa or _get_supa()
    if not intent_id:
        return None
    try:
        result = await asyncio.to_thread(
            lambda: supa.table("generation_intents")
            .select("intent_id, status, iteration, result_ref")
            .eq("intent_id", intent_id)
            .eq("user_id", user_id)          # owner check EXPLICITE (pas seulement la RLS)
            .limit(1)
            .execute()
        )
        rows = getattr(result, "data", None) or []
        if not rows:
            return None
        row = rows[0]
        return {
            "intent_id": row.get("intent_id"),
            "status": row.get("status"),
            "iteration": row.get("iteration"),
            "has_result": row.get("result_ref") is not None,
            "result_ref": row.get("result_ref"),   # métadonnées compactes durables
        }
    except Exception as exc:
        log.warning(
            "[INTENT-OBS] get_by_id failed (swallowed) intent=%s err=%s: %s",
            intent_id, type(exc).__name__, exc,
        )
        return None


@dataclass(frozen=True)
class ClaimResult:
    won: bool
    status: Optional[str] = None
    result_ref: Optional[dict] = None
    reclaim_count: int = 0


async def claim_generation_intent(
    *, intent_id: str, user_id: str, session_id: Optional[str], iteration: int,
    intent: dict, client_request_id: str, supa=None,
) -> ClaimResult:
    """PR2 — ATOMIC CLAIM (load-bearing). Appelle la fonction DB `claim_intent`
    (INSERT ON CONFLICT). won=True → CE process exécute OpenAI ; won=False →
    l'intent existe (status/result_ref renvoyés pour brancher).

    POLITIQUE D'ERREUR (choisie explicitement — pas un `except: pass` aveugle) :

      Catégorie d'échec              Comportement       Justification
      ─────────────────────────────  ─────────────────  ──────────────────────────
      Transitoire (timeout réseau,   FAIL-OPEN (won)    Un double exigerait CETTE
      DB momentanément indispo,      + log ERROR        erreur rare ET un doublon
      rollback de transaction)                          concurrent SIMULTANÉS →
                                                        négligeable. Perdre la gen
                                                        de l'user sur un hoquet DB
                                                        serait pire.
      Structurel (fonction absente   FAIL-OPEN (won)    Affecte TOUTE requête → pic
      PGRST202, mauvais args,        + log ERROR        immédiat de logs ERROR +
      bug de code)                                      détecté au boot par le
                                                        deploy-guard startup. Fail-
                                                        CLOSED ici = panne totale
                                                        sur une erreur de déploiement.

    Dans les DEUX cas on FAIL-OPEN (priorité : ne jamais perdre la génération de
    l'utilisateur), MAIS on log au niveau ERROR avec le marqueur `[CLAIM] FAIL-OPEN`
    → alertable et comptable en prod (≠ swallow silencieux). L'anti-double reste
    garanti dès que la DB répond ; un FAIL-OPEN est un événement anormal, tracé.
    """
    supa = supa or _get_supa()
    sid = _session_uuid_or_none(session_id)
    try:
        res = await asyncio.to_thread(
            lambda: supa.rpc("claim_intent", {
                "p_intent_id": intent_id,
                "p_user_id": user_id,
                "p_session_id": sid,
                "p_iteration": iteration,
                "p_intent": intent,
                "p_client_request_id": client_request_id,
            }).execute()
        )
        rows = getattr(res, "data", None) or []
        if not rows:
            # Réponse vide inattendue (la fonction renvoie TOUJOURS 1 ligne) →
            # anomalie structurelle → FAIL-OPEN tracé.
            _n = bump_claim("fail_open")
            log.error("[CLAIM-OUTCOME] outcome=fail_open total=%d intent=%s — empty RPC "
                      "result (function contract broken?)", _n, intent_id)
            return ClaimResult(won=True, status="RUNNING")
        r = rows[0]
        return ClaimResult(
            won=bool(r.get("won")), status=r.get("status"),
            result_ref=r.get("result_ref"), reclaim_count=int(r.get("reclaim_count") or 0),
        )
    except Exception as exc:
        _n = bump_claim("fail_open")
        log.error("[CLAIM-OUTCOME] outcome=fail_open total=%d intent=%s — claim RPC raised "
                  "%s: %s (anti-double bypassed for THIS request only)",
                  _n, intent_id, type(exc).__name__, exc)
        return ClaimResult(won=True, status="RUNNING")


async def reclaim_generation_intent(
    *, intent_id: str, max_reclaims: int, supa=None,
) -> ClaimResult:
    """PR2 — re-claim d'un intent FAILED (retry délibéré, borné). won=True si la
    transition FAILED→RUNNING a eu lieu. FAILED_TERMINAL jamais re-claim."""
    supa = supa or _get_supa()
    try:
        res = await asyncio.to_thread(
            lambda: supa.rpc("reclaim_intent", {
                "p_intent_id": intent_id, "p_max": max_reclaims,
            }).execute()
        )
        rows = getattr(res, "data", None) or []
        if not rows:
            return ClaimResult(won=False)
        r = rows[0]
        return ClaimResult(won=bool(r.get("won")), reclaim_count=int(r.get("reclaim_count") or 0))
    except Exception as exc:
        log.warning("[CLAIM] reclaim RPC failed intent=%s err=%s", intent_id, exc)
        return ClaimResult(won=False)


async def observe_intent_end(
    intent_id: str,
    status: str,
    *,
    result_ref: Optional[dict] = None,
    error: Optional[dict] = None,
    is_free: bool = True,
    supa=None,
) -> bool:
    """UPDATE generation_intents vers un état terminal
    (SUCCEEDED | FAILED | FAILED_TERMINAL). `updated_at` est posé par le
    trigger DB. Best-effort — ne bloque jamais /generate.

    RENVOIE bool : True si l'UPDATE a été exécuté (le lifecycle terminal EST persisté),
    False si l'écriture a échoué. L'orchestrateur exige un SUCCEEDED strict (ne répond
    'completed' que si True) ; /generate ignore le retour (comportement inchangé).
    """
    supa = supa or _get_supa()
    patch: dict[str, Any] = {"status": status, "completed_at": "now()"}
    if result_ref is not None:
        patch["result_ref"] = result_ref
    if error is not None:
        patch["error"] = error

    def _run():
        q = supa.table("generation_intents").update(patch).eq("intent_id", intent_id)
        # Transition idempotente / safe-race : SUCCEEDED GAGNE toujours. Un
        # statut d'échec (FAILED / FAILED_TERMINAL) ne doit JAMAIS écraser un
        # SUCCEEDED qui aurait gagné une course de duplicata concurrent (le
        # user a bien eu son image). SUCCEEDED lui-même n'a pas de garde (un
        # succès ultérieur gagne légitimement sur un FAILED antérieur).
        if status != "SUCCEEDED":
            q = q.neq("status", "SUCCEEDED")
        return q.execute()

    _ok = False
    try:
        _res = await asyncio.to_thread(_run)
        # STRICT : True seulement si une ligne a RÉELLEMENT transité (PostgREST
        # renvoie les lignes modifiées dans .data). Un execute() sans exception mais
        # 0 ligne (intent absent / filtre non-matché / déjà transité) ≠ persisté.
        _ok = bool(getattr(_res, "data", None))
        log.info("[INTENT-OBS] intent_end intent_id=%s status=%s rows=%d",
                 intent_id, status, len(getattr(_res, "data", None) or []))
    except Exception as exc:
        log.warning(
            "[INTENT-OBS] intent_end FAILED (swallowed) intent_id=%s err=%s: %s",
            intent_id, type(exc).__name__, exc,
        )
    # STRICT SUCCEEDED : si 0 ligne modifiée, un read-back de contrôle peut confirmer
    # que l'intent est DÉJÀ SUCCEEDED avec un result_ref (course concurrente / config
    # de représentation minimale) → alors seulement on considère persisté.
    if status == "SUCCEEDED" and not _ok:
        try:
            _rb = await asyncio.to_thread(
                lambda: supa.table("generation_intents").select("status, result_ref")
                .eq("intent_id", intent_id).limit(1).execute())
            _row = (getattr(_rb, "data", None) or [None])[0] or {}
            _ok = (_row.get("status") == "SUCCEEDED" and _row.get("result_ref") is not None)
        except Exception:  # noqa: BLE001
            _ok = False
    # Billing PR1 — commit (SUCCEEDED) / release (FAILED*) on terminal transition.
    # Idempotent, best-effort, NO gate. user_id + the release-guard status are
    # read inside apply_billing from generation_intents.
    try:
        import billing  # noqa: PLC0415
        await billing.apply_billing_for_intent_transition(
            intent_id=intent_id, new_status=status, is_free=is_free, supa=supa)
    except Exception as bexc:
        log.warning("[BILLING] terminal hook failed (swallowed) intent=%s err=%s: %s",
                    intent_id, type(bexc).__name__, bexc)
    return _ok


async def count_succeeded_intents(user_id: str, *, supa=None) -> int:
    """P0 bloc (b) — nombre de générations RÉUSSIES du user (V1 + refine + switch + reupload) :
    COUNT(generation_intents WHERE user_id AND status='SUCCEEDED'). intent_id = PK déterministe
    → 1 par génération logique, insensible aux retries/replays (le winner-path n'est pas ré-exécuté ;
    un re-UPDATE frappe la MÊME ligne PK). Source de "Redesigns" (le comptage de SESSIONS sous-comptait
    les refines : N refines dans 1 session = 1 seule session avec image). Best-effort LECTURE SEULE, fail-open → 0."""
    supa = supa or _get_supa()
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("generation_intents")
            .select("intent_id", count="exact")
            .eq("user_id", user_id).eq("status", "SUCCEEDED").execute())
        return getattr(res, "count", None) or 0
    except Exception as exc:  # noqa: BLE001 — best-effort, ne casse jamais /me/status
        log.warning("[INTENT-OBS] count_succeeded failed user=%s err=%s", user_id[:8], exc)
        return 0


async def get_intent_result_ref(intent_id: str, *, supa=None) -> Optional[dict]:
    """Lit le result_ref durable d'un intent (source de vérité du get-or-create refine).
    None si absent/erreur. Best-effort, LECTURE SEULE."""
    supa = supa or _get_supa()
    if not intent_id:
        return None
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("generation_intents").select("result_ref")
            .eq("intent_id", intent_id).limit(1).execute())
        rows = getattr(res, "data", None) or []
        return (rows[0].get("result_ref") if rows else None) or None
    except Exception as exc:
        log.warning("[INTENT-OBS] get_result_ref failed intent=%s err=%s: %s",
                    intent_id, type(exc).__name__, exc)
        return None


async def set_intent_result_ref(intent_id: str, result_ref: dict, *, supa=None) -> bool:
    """Écrit le result_ref durable AVANT la transition SUCCEEDED (statut INCHANGÉ) →
    si le flip SUCCEEDED crashe, le reconcile finalise depuis ce result_ref.

    STRICT : renvoie True seulement si une ligne a été modifiée, OU si un read-back
    confirme que le result_ref (par result_version_id) est bien enregistré."""
    supa = supa or _get_supa()
    if not intent_id or result_ref is None:
        return False
    try:
        _res = await asyncio.to_thread(
            lambda: supa.table("generation_intents").update({"result_ref": result_ref})
            .eq("intent_id", intent_id).execute())
        if getattr(_res, "data", None):
            return True
    except Exception as exc:
        log.warning("[INTENT-OBS] set_result_ref failed intent=%s err=%s: %s",
                    intent_id, type(exc).__name__, exc)
        return False
    # 0 ligne (ou représentation minimale) → read-back de contrôle
    try:
        _rb = await asyncio.to_thread(
            lambda: supa.table("generation_intents").select("result_ref")
            .eq("intent_id", intent_id).limit(1).execute())
        _cur = (getattr(_rb, "data", None) or [None])[0] or {}
        _rr = _cur.get("result_ref") or {}
        return _rr.get("result_version_id") == result_ref.get("result_version_id")
    except Exception:  # noqa: BLE001
        return False
