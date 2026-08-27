"""Launch the CANONICAL backend against the PWA STAGING project — local only.

Why this launcher exists
------------------------
`main.py` calls `load_dotenv(override=True)` at import time, and python-dotenv
resolves `.env` relative to that module — i.e. `backend/.env`, which points at
PRODUCTION. Exporting staging variables into the environment is therefore not
enough: `override=True` would overwrite them a few lines into the import.

So this launcher installs the staging file as the ONLY thing `load_dotenv` can
ever read, before `main` is imported. `main.py` itself is untouched, the mobile
launch path (`run.sh`) is untouched, and there is no second copy of the engine.

Fail-closed, in order:
  1. the staging secrets file must exist and be complete;
  2. SUPABASE_URL must carry the staging ref and must NOT carry the production
     ref — checked on the RESOLVED value, not on a filename;
  3. the same check runs AGAIN after `main` is imported, so a stray reload that
     re-pointed the process at production cannot reach `uvicorn.run`.

Usage:  python backend/run_pwa_staging.py
"""
from __future__ import annotations

import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
STAGING_ENV = HERE / '.env.pwa-staging.local'
PRODUCTION_ENV = HERE / '.env'

STAGING_REF = 'eedcahzekpgxvvfxufbk'
PRODUCTION_REF = 'vtxkciupyafukhdsgxgw'
REQUIRED = ('SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'OPENAI_API_KEY')


def _die(msg: str) -> None:
    # Never prints a value — only the name of what failed.
    print(f'REFUSING TO START: {msg}', file=sys.stderr)
    raise SystemExit(2)


def _parse(path: pathlib.Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in path.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, _, v = line.partition('=')
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def _assert_staging(url: str, where: str) -> None:
    if PRODUCTION_REF in url:
        _die(f'{where}: SUPABASE_URL points at the PRODUCTION project.')
    if STAGING_REF not in url:
        _die(f'{where}: SUPABASE_URL is not the authorized staging project '
             f'({STAGING_REF}).')


def main() -> None:
    # WHERE THE CONFIGURATION COMES FROM — a file locally, the environment in a
    # container, and never a mixture the operator did not intend.
    #
    # A deployed image must not carry `.env.pwa-staging.local`: baking secrets
    # into a layer is how they end up in a registry. On a host they arrive as
    # injected environment variables instead (`flyctl secrets set`), which is
    # the same values by a safer route.
    #
    # What does NOT relax is the fail-closed part. Both modes require the same
    # three variables, and both run `_assert_staging` on the RESOLVED value — so
    # a container pointed at production dies at boot exactly as a laptop would.
    if STAGING_ENV.exists():
        values = _parse(STAGING_ENV)
        source = STAGING_ENV.name
    else:
        values = {k: os.environ[k] for k in REQUIRED if os.environ.get(k)}
        source = 'the process environment'
        if not values:
            _die(f'{STAGING_ENV.name} does not exist and the environment '
                 f'carries none of {", ".join(REQUIRED)}.')

    missing = [k for k in REQUIRED if not values.get(k)]
    if missing:
        _die(f'{source} is missing values for: {", ".join(missing)}')

    _assert_staging(values['SUPABASE_URL'], source)
    print(f'[pwa-staging] config     : {source}')

    # 1) Seed the process environment from the staging file.
    for k, v in values.items():
        os.environ[k] = v

    # 1b) THE ENGINE'S OWN FLAGS — the same fourteen `run.sh` pins for mobile.
    #
    # They are not cosmetic: they decide whether Ayden Decide looks at the photo,
    # which prompt blocks are emitted, and the per-edit-mode quality and fidelity.
    # Running staging without them is running a different engine, and it showed —
    # the missing-television report of 2026-08-10 is the exact failure `run.sh`
    # already documents for a restart without AYDEN_DECIDE_FURNISH.
    #
    # Read from run.sh, never copied here: one list, one place to change it.
    sys.path.insert(0, str(HERE))
    from engine_flags import apply_canonical_flags  # noqa: PLC0415

    apply_canonical_flags(log=lambda m: print(f'[pwa-staging] {m}'))

    # 1c) THE FREE TIER IS ONE, and this is the canonical lever that says so.
    #
    # D1 (PWA_MONETIZATION_AUDIT §6bis): one free vision per anonymous Web
    # guest, full quality, watermarked. `ACCOUNT_SYSTEM_ENABLED` is the SERVER
    # authority for the trial amount — `billing.effective_trial_credits()`
    # returns 1 in ON-mode and 3 in OFF-mode, and passes it to the RPC as
    # `p_trial_credits`. Setting it here rather than inventing a PWA-only
    # constant is what keeps one billing brain: the same function answers for
    # both platforms, it just answers differently per deployment.
    #
    # ON is also what the Web IS, semantically: D2 chose upgrade-in-place
    # (anonymous -> linkIdentity, same user_id), which is account-mode with a
    # different upgrade mechanism, not a third identity model.
    #
    # Blast radius, checked rather than assumed: `account_system_enabled()` is
    # read in exactly two places — `effective_trial_credits()` (what we want)
    # and `identity._require_account_system_enabled`, which stops returning 404
    # for the /identity/* routes. Those routes read `account_state`, a table
    # this project deliberately does not have, and no PWA client calls them.
    # The flag is set AFTER the staging secrets so an operator can still
    # override it in `.env.pwa-staging.local` for a deliberate experiment.
    os.environ.setdefault('ACCOUNT_SYSTEM_ENABLED', 'true')
    print('[pwa-staging] ACCOUNT_SYSTEM_ENABLED='
          + os.environ['ACCOUNT_SYSTEM_ENABLED']
          + '  (Web free tier = 1 generation, D1)')

    # 2) Make the staging file the ONLY file load_dotenv can read. `main.py`
    #    does `from dotenv import load_dotenv` at ITS import time, so patching
    #    the module attribute here — before importing main — is what it binds.
    import dotenv  # noqa: PLC0415

    _real_load = dotenv.load_dotenv

    def _staging_only_load(*_args, **kwargs):  # noqa: ANN002, ANN003
        # No file in a container: the environment IS the configuration and has
        # already been seeded above. Returning False rather than pointing
        # `load_dotenv` at a path that does not exist keeps `main.py`'s
        # import-time call a no-op instead of a silent miss that could later be
        # mistaken for "the file was read and was empty".
        if not STAGING_ENV.exists():
            return False
        kwargs.pop('dotenv_path', None)
        kwargs['override'] = True
        return _real_load(str(STAGING_ENV), **kwargs)

    dotenv.load_dotenv = _staging_only_load
    if PRODUCTION_ENV.exists():
        print(f'[pwa-staging] {PRODUCTION_ENV.name} exists and is NOT loaded '
              f'(production config, deliberately bypassed).')

    # 3) Import the canonical app. No engine is copied, nothing is redefined.
    sys.path.insert(0, str(HERE))
    os.chdir(HERE)
    import main as canonical  # noqa: PLC0415

    # Say WHICH engine this process actually runs. COMPOSER_VERSION is read at
    # import time, and the line main.py logs for it is emitted before the file
    # handler exists — so its absence from backend.log proved nothing and cost a
    # round of doubt. An operator should be able to read the answer, not infer it.
    print('[pwa-staging] composer   : '
          + canonical.compose_generation_prompt.__module__)
    print('[pwa-staging] APP_ENV    : ' + os.environ.get('APP_ENV', '(unset)')
          + '   COMPOSER_VERSION: ' + os.environ.get('COMPOSER_VERSION', '(unset)'))

    # 4) Re-assert on the RESOLVED environment, after every import-time load.
    _assert_staging(os.environ.get('SUPABASE_URL', ''), 'resolved environment')

    # 5) Mount the PWA adapter. Done HERE, not in main.py, so the canonical app
    #    and the mobile launch path stay byte-identical.
    import pwa_staging_api  # noqa: PLC0415

    canonical.app.include_router(pwa_staging_api.router)
    print('[pwa-staging] adapter mounted at /pwa/staging')

    # 5b) The KHQR payment rail (ABA PayWay SANDBOX). Mounted here for the same
    #     reason as the adapter: `main.py` stays byte-identical and the mobile
    #     launch path gains no payment endpoint.
    #
    #     Absent credentials are a supported state, not an error. The router is
    #     always mounted so `/payments/config` can answer truthfully; every
    #     endpoint that would take money refuses with 503 until
    #     `PAYWAY_MERCHANT_ID` and `PAYWAY_API_KEY` are present in the ignored
    #     staging secrets file. Nothing below prints either value.
    import payway  # noqa: PLC0415
    import pwa_staging_payments  # noqa: PLC0415

    canonical.app.include_router(pwa_staging_payments.router)
    _pw = payway.redacted_config()
    if _pw.get('configured'):
        print(f'[pwa-staging] payments  : rail=khqr gateway=payway '
              f'env={_pw["environment"]} merchant=***{_pw["merchant_id_suffix"]} '
              f'callback={"configured" if _pw["callback_configured"] else "POLL-ONLY"} '
              f'signature={_pw["callback_signature"]}')
    else:
        print('[pwa-staging] payments  : NOT CONFIGURED — the paywall will say '
              'payments are not open (fill PAYWAY_* in .env.pwa-staging.local)')
    print(f'[pwa-staging] target project ref: {STAGING_REF} — verified')
    print(f'[pwa-staging] APP_ENV={os.environ.get("APP_ENV")} '
          f'BIMODAL_ENABLED={os.environ.get("BIMODAL_ENABLED")}')

    # 6) CORS — TIGHTENED HERE, not in main.py, and that placement is the point.
    #
    # `main.py` mounts CORSMiddleware with `allow_origins=["*"]` and
    # `allow_credentials=True`. That is the canonical app, shared with production
    # and with the mobile backend, and a native app does not do CORS at all — so
    # narrowing it there would change production's behaviour to fix a browser
    # problem production does not have. This launcher already owns every other
    # staging-only decision (which router is mounted, which env file is read), so
    # it owns this one too.
    #
    # A public staging origin makes this real rather than theoretical: once the
    # PWA is served from an https:// host, any page on the internet can attempt
    # a credentialed cross-origin call to this API. The allowlist is the answer,
    # and it is read from the environment so a new deployment host is a config
    # change and not a code change.
    origins = [o.strip() for o in
               os.environ.get('PWA_ALLOWED_ORIGINS', '').split(',') if o.strip()]
    if origins:
        from starlette.middleware.cors import CORSMiddleware  # noqa: PLC0415

        # Starlette applies middleware in reverse-add order, so this one wraps
        # the permissive stack from main.py and answers the preflight first.
        canonical.app.add_middleware(
            CORSMiddleware,
            allow_origins=origins,
            allow_credentials=True,
            allow_methods=['GET', 'POST', 'OPTIONS'],
            allow_headers=['Authorization', 'Content-Type'],
            max_age=600,
        )
        print(f'[pwa-staging] CORS      : {len(origins)} allowed origin(s) — '
              + ', '.join(origins))
    else:
        print('[pwa-staging] CORS      : no PWA_ALLOWED_ORIGINS set — the '
              'canonical permissive policy applies (local dev only)')

    import uvicorn  # noqa: PLC0415

    # WHERE THIS PROCESS LISTENS.
    #
    # Loopback locally, which is what every earlier phase assumed and what keeps
    # a developer machine from serving the internet by accident. A host that
    # sets PORT (Fly, Render, Cloud Run, Heroku) is telling us it terminates TLS
    # in front of us and routes to that port, and there 127.0.0.1 would make the
    # container look dead to the health check — so the presence of PORT, not a
    # flag we set ourselves, is what opens the bind.
    port = int(os.environ.get('PORT', '8000'))
    host = '0.0.0.0' if os.environ.get('PORT') else '127.0.0.1'  # noqa: S104
    print(f'[pwa-staging] listening  : {host}:{port}')

    # Single process, NO --reload (Windows --reload orphans workers that then
    # serve stale DNA — same rule as the canonical run.sh).
    uvicorn.run(canonical.app, host=host, port=port, log_level='info')


if __name__ == '__main__':
    main()
