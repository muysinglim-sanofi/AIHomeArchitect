#!/usr/bin/env bash
# ── AYDEN backend — CANONICAL perf-safe launch ────────────────────────────────
# The engine-wave flags below are the BENCHED config that produced the V1 renders
# the user validated (15/06) — small prompt (~3081 chars for WM Living). It is
# also the fast path empirically: an A/B on 2026-06-17 (same morning, matched
# prompt size) showed HEAD-benched == the 15/06 code (~28-31s openai), i.e. no
# code regression. Running WITHOUT these flags produces the verbose contract +
# structural-identity enumeration (~3500-3745 chars). NOTE: latency is dominated
# by OpenAI server load (identical prompt observed 26s..61s), so the size→latency
# link is NOT cleanly isolated (the big-prompt samples were evening/high-load).
# Regardless, keep these ON: it is the validated config and keeps the prompt lean.
#
# PERF CANARY: in each "[PERF SUMMARY]" line, prompt_chars for a WM Vision-1
# should be ~3081. If it climbs above ~3200, a flag is off or a verbose block
# crept back in (e.g. PRESERVE_FURNISH_SCOPE) → investigate before shipping.
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
# Ayden runtime flags — PINNED ON so a restart never silently disables them.
# (2026-06-23 incident: a run.sh restart WITHOUT AYDEN_DECIDE_FURNISH dropped
#  Ayden Decide room detection → AtmosphereDNA fell back to fallback_style_block
#  → empty/sparse V1 render. Proven via backend.log: the "Ayden vision pass"
#  stopped running after the restart. Render already sets these; this keeps the
#  local canonical launch in parity.)
#   AYDEN_DECIDE_FURNISH — Ayden Decide STAGE: detect + propagate room → per-atmosphere DNA
#   SURPRISE_VISION      — image-driven Surprise Me atmosphere
#   SWITCH_BLOCK_COMPACT — compact switch block (switch-only; keeps TV/room anchor under budget)
AYDEN_DECIDE_FURNISH=1 \
SURPRISE_VISION=1 \
SWITCH_BLOCK_COMPACT=1 \
BIMODAL_ENABLED=1 \
VISION_DETERMINISTIC=1 \
PROMPT_FURNITURE_FIX=1 \
PROMPT_CONTRACT_LIGHT=1 \
TRUST_PIXELS_V1=1 \
EDIT_FIDELITY_LOW=1 \
LOCAL_EDIT_QUALITY_MEDIUM=1 \
STYLE_REFINE_QUALITY_MEDIUM=1 \
STRUCT_FIDELITY_LOW=1 \
STRUCT_ID_CACHE=1 \
DNA_CLEANUP_V1=1 \
.venv/Scripts/python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000 >> logs/backend.log 2>&1
