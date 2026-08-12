"""The engine's runtime flags — ONE source, read by every launcher.

Why this exists
---------------
`run.sh` is the canonical mobile launch, and it pins fourteen flags before
starting uvicorn. They are not decorations: they select which prompt blocks are
emitted, whether Ayden Decide looks at the photo at all, and the per-edit-mode
quality and fidelity. Two backends with the same code and different flags render
differently — and nothing anywhere says so.

That is not hypothetical. `run.sh` itself records the incident:

    2026-06-23 — a run.sh restart WITHOUT AYDEN_DECIDE_FURNISH dropped Ayden
    Decide room detection → AtmosphereDNA fell back to fallback_style_block
    → empty/sparse V1 render.

It happened again, silently, to the PWA: `run_pwa_staging.py` set none of them,
so for weeks the staging engine ran with thirteen of the fourteen off. The
symptom reported on 2026-08-10 — a living room with no television, a weak first
vision — is that same line, word for word.

The fix is not to copy the list. A copy drifts, and a drifted copy is exactly
what caused this. `run.sh` stays the single source and this module READS it, so
adding a flag there reaches every launcher with no second edit and no second
place to forget.

Never overrides anything already in the environment: an operator who exported a
flag deliberately keeps it.
"""
from __future__ import annotations

import os
import pathlib
import re

CANONICAL_LAUNCHER = pathlib.Path(__file__).resolve().parent / "run.sh"

# `NAME=VALUE \` — the shell's own way of prefixing a command with environment.
# Anchored at the start of a line so a mention inside a comment is not a flag.
_PINNED = re.compile(r"^([A-Z][A-Z0-9_]*)=([^\s\\]+)\s*\\\s*$", re.MULTILINE)


def canonical_flags() -> dict[str, str]:
    """Every flag `run.sh` pins, in the order it pins them."""
    if not CANONICAL_LAUNCHER.exists():
        return {}
    text = CANONICAL_LAUNCHER.read_text(encoding="utf-8")
    # Only the prefix block matters — stop at the interpreter invocation, so a
    # trailing example in a comment below it can never be mistaken for a flag.
    head = text.split("python.exe", 1)[0]
    return {name: value for name, value in _PINNED.findall(head)}


def apply_canonical_flags(*, log=None) -> dict[str, str]:
    """Put the canonical flags into this process's environment.

    Returns what was applied, so a launcher can print it and an operator can see
    at a glance which engine they are actually running.
    """
    applied: dict[str, str] = {}
    for name, value in canonical_flags().items():
        if name in os.environ:
            continue  # a deliberate export wins
        os.environ[name] = value
        applied[name] = value
    if log is not None:
        if applied:
            log(f"engine flags (from run.sh): {', '.join(sorted(applied))}")
        else:
            log("engine flags: none applied (all already set)")
    return applied
