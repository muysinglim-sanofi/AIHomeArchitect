#!/usr/bin/env bash
# AYDEN Studio — Codespaces / devcontainer bootstrap.
# Installs backend deps, seeds the .env templates, and (best-effort) the
# Flutter SDK for analyze/test. Secrets are NOT in git — fill them after.
set -uo pipefail

echo "▶ Backend Python deps…"
pip install -r backend/requirements.txt || echo "  (pip install had issues — re-run manually)"

echo "▶ .env templates (fill in your REAL secrets after setup)…"
[ -f backend/.env ]  || cp backend/.env.example  backend/.env  || true
[ -f frontend/.env ] || cp frontend/.env.example frontend/.env || true

echo "▶ Flutter SDK (optional — for 'flutter test' / 'dart analyze')…"
if [ ! -x "$HOME/flutter/bin/flutter" ]; then
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter" \
    || echo "  (Flutter clone skipped — backend work still fully available)"
fi
export PATH="$PATH:$HOME/flutter/bin"
if command -v flutter >/dev/null 2>&1; then
  ( cd frontend && flutter pub get ) || true
fi

cat <<'DONE'

✅ Setup done.

NEXT:
  1. Fill backend/.env + frontend/.env with your real keys (Supabase / OpenAI / RevenueCat).
  2. Backend:  cd backend && BIMODAL_ENABLED=1 uvicorn main:app --reload --port 8000
  3. Tests:    (cd backend && python _sprint_1b_promo_validation.py)
               (cd frontend && flutter test)   # needs the Flutter SDK above

Note: the live Flutter app cannot be previewed from a phone (no emulator).
Editing code + running the backend + running tests all work here.
DONE
