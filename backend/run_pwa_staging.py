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
    if not STAGING_ENV.exists():
        _die(f'{STAGING_ENV.name} does not exist.')

    values = _parse(STAGING_ENV)
    missing = [k for k in REQUIRED if not values.get(k)]
    if missing:
        _die(f'{STAGING_ENV.name} is missing values for: {", ".join(missing)}')

    _assert_staging(values['SUPABASE_URL'], 'staging secrets file')

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

    # 2) Make the staging file the ONLY file load_dotenv can read. `main.py`
    #    does `from dotenv import load_dotenv` at ITS import time, so patching
    #    the module attribute here — before importing main — is what it binds.
    import dotenv  # noqa: PLC0415

    _real_load = dotenv.load_dotenv

    def _staging_only_load(*_args, **kwargs):  # noqa: ANN002, ANN003
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
    print(f'[pwa-staging] target project ref: {STAGING_REF} — verified')
    print(f'[pwa-staging] APP_ENV={os.environ.get("APP_ENV")} '
          f'BIMODAL_ENABLED={os.environ.get("BIMODAL_ENABLED")}')

    import uvicorn  # noqa: PLC0415

    # Single process, NO --reload (Windows --reload orphans workers that then
    # serve stale DNA — same rule as the canonical run.sh).
    uvicorn.run(canonical.app, host='127.0.0.1', port=8000, log_level='info')


if __name__ == '__main__':
    main()
