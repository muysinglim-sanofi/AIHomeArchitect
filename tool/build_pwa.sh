#!/usr/bin/env bash
# THE canonical PWA web build. Use this, not `flutter build web`.
#
# WHY THIS SCRIPT EXISTS
#
# `flutter build web` with no `-t` builds `lib/main.dart`. That is the MOBILE
# entrypoint: it boots the production stack and imports no PWA code at all. It
# compiles cleanly and produces a `build/web` that looks plausible — which is
# exactly what makes it dangerous, and it has already been deployed once by
# mistake in this branch.
#
# So the correct command is the short one, and the wrong one is now hard to run
# by accident.
#
#   ./tool/build_pwa.sh staging     # public staging (Fly API, staging Supabase)
#   ./tool/build_pwa.sh mock        # fully offline, no backend, no Supabase
#
# Secrets: the staging publishable key is READ from
# backend/.env.pwa-staging.local (gitignored) and never printed. It is a
# publishable key by design — the client is meant to hold it — but there is no
# reason to echo it into a terminal or a CI log either.
set -euo pipefail

MODE="${1:-staging}"
ENTRY="lib/main_pwa.dart"
ENV_FILE="${AYDEN_ENV_FILE:-../AIHomeArchitect/backend/.env.pwa-staging.local}"

cd "$(dirname "$0")/.."

if [[ ! -f "$ENTRY" ]]; then
  echo "REFUSING: $ENTRY not found — are you in the PWA repo?" >&2
  exit 2
fi

# The guard, stated as a check rather than as a comment: if lib/main.dart ever
# starts importing PWA code, the two entrypoints have merged and this script's
# whole premise is gone.
# Match an IMPORT, not any mention: main.dart's own docstring says it imports
# no PWA code, and a substring grep flagged that sentence as the violation it
# was describing.
if grep -Eq "^\s*import\s+['\"][^'\"]*features/pwa" lib/main.dart 2>/dev/null; then
  echo "REFUSING: lib/main.dart now imports PWA code. The mobile and web" >&2
  echo "entrypoints are supposed to be disjoint; fix that before building." >&2
  exit 2
fi

# `pubspec.yaml` declares `.env` as a Flutter asset for the MOBILE app, so every
# web build copies it into `build/web/assets/.env` — where a static host then
# serves it at a guessable URL. It currently holds placeholders, and it would
# start holding real values the day someone fills it in locally.
#
# Stripped HERE rather than only in a Hosting ignore rule: the ignore rule is
# one deploy target's opinion, this is the artefact itself. Removing the entry
# from pubspec is not an option — that file is shared with the frozen mobile app
# and the mobile app loads it at runtime.
strip_dotenv() {
  local n=0 f
  for f in build/web/assets/.env build/web/assets/.env.*; do
    [[ -e "$f" ]] || continue
    rm -f "$f"
    n=$((n + 1))
  done
  if [[ $n -gt 0 ]]; then
    echo "==> stripped $n dotenv file(s) from the bundle"
  fi
}

case "$MODE" in
  mock)
    echo "==> PWA build: MOCK (offline, no backend)"
    flutter build web --release -t "$ENTRY" \
      --dart-define=AYDEN_ENV=mock
    strip_dotenv
    ;;
  staging)
    if [[ ! -f "$ENV_FILE" ]]; then
      echo "REFUSING: $ENV_FILE not found." >&2
      echo "Set AYDEN_ENV_FILE, or build with: $0 mock" >&2
      exit 2
    fi
    KEY="$(grep -E '^SUPABASE_PUBLISHABLE_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"'"'"' \r')"
    if [[ -z "$KEY" ]]; then
      echo "REFUSING: SUPABASE_PUBLISHABLE_KEY is empty in $ENV_FILE" >&2
      exit 2
    fi
    echo "==> PWA build: STAGING"
    echo "    entrypoint : $ENTRY"
    echo "    supabase   : eedcahzekpgxvvfxufbk (staging)"
    echo "    api        : https://ayden-api-staging.fly.dev"
    flutter build web --release -t "$ENTRY" \
      --dart-define=AYDEN_ENV=staging \
      --dart-define=AYDEN_STAGING_SUPABASE_URL=https://eedcahzekpgxvvfxufbk.supabase.co \
      --dart-define=AYDEN_STAGING_PROJECT_REF=eedcahzekpgxvvfxufbk \
      --dart-define=AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY="$KEY" \
      --dart-define=AYDEN_STAGING_BACKEND_URL=https://ayden-api-staging.fly.dev
    strip_dotenv
    ;;
  *)
    echo "usage: $0 [staging|mock]" >&2
    exit 2
    ;;
esac

# The marker the DEPLOY guard reads (tool/verify_pwa_build.mjs, wired into
# firebase.json's predeploy). Written last, so it can only exist if the build
# above actually finished. It holds no secret.
cat > build/web/ayden-build.json <<JSON
{
  "entrypoint": "$ENTRY",
  "mode": "$MODE",
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
echo "==> build marker written (entrypoint $ENTRY, mode $MODE)"
