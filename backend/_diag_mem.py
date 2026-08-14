"""Diagnostics mémoire et image — observabilité PURE, aucun changement de comportement.

POURQUOI PAS psutil. Il n'est pas installé, et l'ajouter à requirements.txt pour
un diagnostic ferait porter à la PRODUCTION une dépendance dont elle n'a pas
besoin. La RSS est lisible sans aucune dépendance :
  • Linux (Render)  : /proc/self/statm, champ 2 (pages résidentes) × page size ;
  • Windows (local) : GetProcessMemoryInfo via ctypes (psapi/kernel32).
Les deux plateformes comptent la même chose — la mémoire physique réellement
occupée par le process, c'est-à-dire la grandeur que Render compare à ses 512 Mo.

GATING. Rien ne s'exécute si AYDEN_MEM_DIAG n'est pas armé. Par défaut le flag
suit l'environnement de déploiement : ON hors production, OFF en production, et
un réglage explicite gagne toujours. Un checkpoint désarmé coûte un test booléen.

CE QUI N'EST JAMAIS JOURNALISÉ : aucun octet d'image, aucune URL, aucune URL
signée, aucune clé, aucune donnée personnelle. Uniquement des tailles, des
dimensions et des statistiques.
"""
from __future__ import annotations

import logging
import os

log = logging.getLogger("aih")

_PAGE_SIZE = 4096


def diag_enabled() -> bool:
    """ON hors production, OFF en production ; AYDEN_MEM_DIAG force les deux sens."""
    explicit = os.environ.get("AYDEN_MEM_DIAG", "").strip().lower()
    if explicit in ("1", "true", "yes", "on"):
        return True
    if explicit in ("0", "false", "no", "off"):
        return False
    return (os.environ.get("AYDEN_DEPLOY_ENV") or "production").strip().lower() != "production"


def _rss_bytes_linux() -> int:
    try:
        with open("/proc/self/statm", "r") as fh:
            return int(fh.read().split()[1]) * _PAGE_SIZE
    except Exception:
        return 0


def _rss_bytes_windows() -> int:
    try:
        import ctypes
        from ctypes import wintypes

        class _PMC(ctypes.Structure):
            _fields_ = [
                ("cb", wintypes.DWORD),
                ("PageFaultCount", wintypes.DWORD),
                ("PeakWorkingSetSize", ctypes.c_size_t),
                ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t),
                ("PeakPagefileUsage", ctypes.c_size_t),
            ]

        counters = _PMC()
        counters.cb = ctypes.sizeof(_PMC)
        handle = ctypes.windll.kernel32.GetCurrentProcess()
        if not ctypes.windll.psapi.GetProcessMemoryInfo(
            handle, ctypes.byref(counters), counters.cb
        ):
            return 0
        return int(counters.WorkingSetSize)
    except Exception:
        return 0


def rss_mb() -> float:
    """RSS du process en Mo. 0.0 si la plateforme ne répond pas — jamais une exception."""
    raw = _rss_bytes_linux() or _rss_bytes_windows()
    return round(raw / (1024 * 1024), 1) if raw else 0.0


def mem_checkpoint(stage: str, route: str = "", **extra) -> None:
    """Une ligne [MEM]. Ne lève JAMAIS : un diagnostic ne doit pas casser une génération."""
    if not diag_enabled():
        return
    try:
        tail = "".join(f" {k}={v}" for k, v in extra.items() if v is not None)
        log.info(
            "[MEM] route=%s stage=%s rss_mb=%s%s",
            route or "-", stage, rss_mb(), tail,
        )
    except Exception:
        pass


def image_stats(image_bytes: bytes, label: str, route: str = "") -> dict:
    """Décode et mesure une image de sortie — SANS jamais journaliser son contenu.

    Répond à la question de l'issue 10 : le backend reçoit-il/enregistre-t-il une
    image réellement noire, ou l'asset est-il normal et l'affichage fautif ?

    `near_black_pct` est calculé sur une vignette 64×64 en niveaux de gris : le
    coût est constant (~1 ms) quelle que soit la résolution d'entrée, et la
    statistique reste fidèle pour détecter un cadre uniformément sombre.

    Retourne toujours un dict, jamais d'exception.
    """
    out = {"decode": "skipped", "bytes": len(image_bytes or b"")}
    if not diag_enabled():
        return out
    try:
        import io

        from PIL import Image as _Pil

        with _Pil.open(io.BytesIO(image_bytes)) as img:
            out["width"], out["height"] = img.size
            out["mode"] = img.mode
            thumb = img.convert("L").resize((64, 64))
            pixels = list(thumb.getdata())
            total = len(pixels) or 1
            out["mean_luma"] = round(sum(pixels) / total, 1)
            out["near_black_pct"] = round(
                100.0 * sum(1 for p in pixels if p <= 8) / total, 1
            )
            out["decode"] = "ok"
    except Exception as exc:
        out["decode"] = "FAILED"
        out["error"] = type(exc).__name__
    try:
        log.info(
            "[IMAGE-VALIDATION] route=%s label=%s decode=%s bytes=%s "
            "width=%s height=%s mode=%s mean_luma=%s near_black_pct=%s%s",
            route or "-", label, out.get("decode"), out.get("bytes"),
            out.get("width"), out.get("height"), out.get("mode"),
            out.get("mean_luma"), out.get("near_black_pct"),
            f" error={out['error']}" if out.get("error") else "",
        )
        # Signal fort, pour que le cas ne se perde pas dans le bruit : une sortie
        # quasi entièrement noire est presque certainement le symptôme rapporté.
        if out.get("decode") == "ok" and out.get("near_black_pct", 0) >= 95.0:
            log.error(
                "[IMAGE-VALIDATION] route=%s label=%s SUSPECT: near_black_pct=%s "
                "mean_luma=%s — sortie quasi noire",
                route or "-", label, out.get("near_black_pct"), out.get("mean_luma"),
            )
    except Exception:
        pass
    return out
