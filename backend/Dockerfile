# ============================================================================
# AYDEN STUDIO — PWA STAGING backend, containerised.
# ----------------------------------------------------------------------------
# STAGING ONLY. This image runs `run_pwa_staging.py`, which refuses to start
# unless SUPABASE_URL resolves to the authorized staging project — so an image
# handed the production URL dies at boot rather than serving it.
#
# It carries NO secrets. `.env.pwa-staging.local` is excluded by .dockerignore
# and the launcher reads the process environment when the file is absent; the
# host injects the three required values (`flyctl secrets set`). Baking them
# into a layer would put them in a registry, which is a different problem from
# the one a .gitignore solves.
#
# The entrypoint is the SAME launcher used locally. There is no container-only
# code path, so what is tested on a laptop is what runs on the host — including
# the fourteen engine flags it pins and the staging-project assertion it makes
# twice.
# ============================================================================
FROM python:3.10-slim

# Pillow needs libjpeg/zlib at runtime; the slim image ships neither. Installed
# before the requirements layer so a dependency bump does not re-run apt.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libjpeg62-turbo zlib1g curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Requirements first: this layer is cached until requirements.txt itself moves.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Then the source. .dockerignore keeps 2.7 GB of logs, benchmarks and the local
# virtualenv out of the build context.
COPY . .

# Documentation only — the launcher binds whatever PORT the host injects, and
# binds loopback when it injects none.
ENV PORT=8080
EXPOSE 8080

# Unbuffered so the platform's log tail shows the boot assertions as they run
# rather than after the first flush.
ENV PYTHONUNBUFFERED=1

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/pwa/staging/health" || exit 1

CMD ["python", "run_pwa_staging.py"]
