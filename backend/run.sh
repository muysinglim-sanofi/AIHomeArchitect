#!/usr/bin/env bash
# ── AYDEN backend — CANONICAL perf-safe launch ────────────────────────────────
# The engine-wave flags below keep the V1 prompt SMALL (~3081 chars for WM Living)
# which is the fast path. Running WITHOUT them produces the verbose contract +
# structural-identity enumeration (~3500-3745 chars) → ~+20s on the gpt-image-1
# call (A/B confirmed 2026-06-17). NEVER launch the backend without these.
#
# PERF CANARY: in each "[PERF SUMMARY]" line, prompt_chars for a WM Vision-1
# should be ~3081. If it climbs above ~3200, something bloated the prompt → a
# flag is off or a verbose block crept back in. Investigate before shipping.
#
# Single process, NO --reload (Windows --reload orphans multiprocessing workers
# that serve stale DNA). Log is APPENDED (never overwrite — preserves history).
#
# Optional feature flags — export before calling, they are inherited by python:
#   MULTILINGUAL_NORMALIZE=1 ./run.sh     # FR/KM chat normalization (no V1 perf cost)
#   SWITCH_REDESIGN_PILOT=1  ./run.sh     # distinct atmosphere switches (switch-only)
# Do NOT set the engine-wave flags to 0, and do NOT add PRESERVE_FURNISH_SCOPE
# (rolled back — adds ~250 chars to V1 for no latency gain).

cd "$(dirname "$0")" || exit 1
echo "=== RESTART $(date) — canonical perf-safe launch ===" >> logs/backend.log
BIMODAL_ENABLED=1 \
VISION_DETERMINISTIC=1 \
PROMPT_FURNITURE_FIX=1 \
PROMPT_CONTRACT_LIGHT=1 \
TRUST_PIXELS_V1=1 \
EDIT_FIDELITY_LOW=1 \
LOCAL_EDIT_QUALITY_MEDIUM=1 \
DNA_CLEANUP_V1=1 \
.venv/Scripts/python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000 >> logs/backend.log 2>&1
