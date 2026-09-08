"""Launch the CANONICAL backend as the Ayden Studio WEB PRODUCTION API.

The sibling of `run_pwa_staging.py`, and deliberately NOT a copy of it. The two
differ in the one place that matters — where configuration may come from:

    staging      a gitignored file on a developer machine, or the environment
    production   the environment ONLY

A production secret must never be readable from a file inside the image or the
repository, so this launcher refuses to read one. On Fly the values arrive as
`flyctl secrets`, i.e. as process environment, and `main.py`'s
`load_dotenv(override=True)` is a no-op because `.dockerignore` keeps every
`.env*` out of the image. If a `.env` file were ever present next to `main.py`
in a production container, that file would silently win — so this launcher
checks for it and refuses to start.

Fail closed, in order:
  1. `PWA_TARGET` must be `production` (nothing here is the default);
  2. no `.env` file may exist beside `main.py`;
  3. the required variables must be present in the environment;
  4. `SUPABASE_URL` must carry the PRODUCTION project ref and must NOT carry
     the staging one — `pwa_target.assert_url_matches`, not a local copy;
  5. the same check runs AGAIN after `main` is imported, so an import-time load
     that re-pointed the process cannot reach `uvicorn.run`;
  6. CORS must be an explicit allowlist — a production browser API with the
     canonical permissive policy is refused rather than served.

What it does NOT do: touch `main.py`, touch the mobile launch path, copy the
engine, or mount anything the staging launcher does not mount. The routers it
mounts take their own prefix, schema and bucket from `pwa_target`.

Usage (container):  python backend/run_pwa_prod.py
"""
from __future__ import annotations

import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
DOTENV = HERE / '.env'
STAGING_ENV = HERE / '.env.pwa-staging.local'

#: Everything the canonical engine and the Web adapter need. Names only.
REQUIRED = ('SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'OPENAI_API_KEY',
            'SUPABASE_PUBLISHABLE_KEY')


def _die(msg: str) -> None:
    # Never prints a value — only the name of what failed.
    print(f'REFUSING TO START: {msg}', file=sys.stderr)
    raise SystemExit(2)


def main() -> None:
    sys.path.insert(0, str(HERE))
    os.chdir(HERE)

    import pwa_target  # noqa: PLC0415

    # 1) This launcher is production, and says so before anything else reads
    #    the environment. It does not DEFAULT to production: an operator who
    #    forgot the variable gets a refusal, not a surprise.
    if (os.environ.get('PWA_TARGET') or '').strip().lower() != pwa_target.PRODUCTION:
        _die('PWA_TARGET=production is required to run the production Web API '
             '(got %r).' % os.environ.get('PWA_TARGET'))

    # 2) No file may out-vote the environment here.
    for path, what in ((DOTENV, 'backend/.env'),
                       (STAGING_ENV, 'backend/.env.pwa-staging.local')):
        if path.exists():
            _die(f'{what} exists in a PRODUCTION container. `main.py` calls '
                 f'load_dotenv(override=True), so that file would silently '
                 f'replace the injected secrets. Remove it from the image.')

    # 3) Presence, before anything is dialled.
    missing = [k for k in REQUIRED if not os.environ.get(k)]
    if missing:
        _die('the environment is missing: ' + ', '.join(missing)
             + '. Set them with `flyctl secrets set` — never in a file.')

    # 4) The project this process is allowed to touch, checked both ways.
    try:
        target = pwa_target.assert_url_matches(os.environ.get('SUPABASE_URL', ''),
                                               where='process environment')
    except pwa_target.PwaTargetError as exc:
        _die(str(exc))

    # The engine configuration the benches were run with. Absent, the process
    # would serve a recipe nobody validated (the 2026-08-10 lesson).
    os.environ.setdefault('APP_ENV', 'production')
    if os.environ.get('BIMODAL_ENABLED') != '1':
        _die('BIMODAL_ENABLED=1 is required — without it this process serves an '
             'engine configuration that was never benched.')

    print(f'[pwa-prod] target     : {target.name} '
          f'({target.project_ref}) schema={target.schema} bucket={target.bucket}')

    # 5) Import the canonical app. No engine is copied, nothing is redefined.
    import main as canonical  # noqa: PLC0415

    print('[pwa-prod] composer   : '
          + canonical.compose_generation_prompt.__module__)
    print('[pwa-prod] APP_ENV    : ' + os.environ.get('APP_ENV', '(unset)')
          + '   COMPOSER_VERSION: ' + os.environ.get('COMPOSER_VERSION', '(unset)'))

    # 6) Re-assert on the RESOLVED environment, after every import-time load.
    try:
        pwa_target.assert_url_matches(os.environ.get('SUPABASE_URL', ''),
                                      where='resolved environment')
    except pwa_target.PwaTargetError as exc:
        _die(str(exc))

    # 7) Mount the Web adapter and the payment rail. Same modules as staging;
    #    their prefix, schema and bucket come from `pwa_target`.
    import payway  # noqa: PLC0415
    import pwa_staging_api as pwa_api  # noqa: PLC0415
    import pwa_staging_auth_api as pwa_auth  # noqa: PLC0415
    import pwa_staging_payments as pwa_payments  # noqa: PLC0415

    canonical.app.include_router(pwa_api.router)
    # Phone-link PREPARE (Cambodia auth). Answers 503 until the production
    # project carries migration 0010's function; the client fails open to its
    # own user-id guard on any non-2xx.
    canonical.app.include_router(pwa_auth.router)
    canonical.app.include_router(pwa_payments.router)
    print(f'[pwa-prod] adapter    : mounted at {target.prefix}')

    _pw = payway.redacted_config()
    if _pw.get('configured'):
        print(f'[pwa-prod] payments   : rail=khqr gateway=payway '
              f'env={_pw["environment"]} merchant=***{_pw["merchant_id_suffix"]} '
              f'callback={"configured" if _pw["callback_configured"] else "POLL-ONLY"} '
              f'signature={_pw["callback_signature"]}')
        if _pw.get('environment') != 'production':
            print('[pwa-prod] payments   : WARNING — the gateway is not the '
                  'production one; purchases will not move real money.')
    else:
        print('[pwa-prod] payments   : NOT CONFIGURED — the paywall will say '
              'payments are not open.')

    # 8) CORS. In staging an absent allowlist falls back to the canonical
    #    permissive policy, which is acceptable for loopback development. In
    #    production it is not: `allow_origins=["*"]` with credentials on a
    #    public browser API is exactly the hole the allowlist exists to close.
    origins = [o.strip() for o in
               os.environ.get('PWA_ALLOWED_ORIGINS', '').split(',') if o.strip()]
    origin_regex = os.environ.get('PWA_ALLOWED_ORIGIN_REGEX', '').strip()
    if not origins:
        _die('PWA_ALLOWED_ORIGINS is required in production — refusing to serve '
             'a browser API under the canonical permissive CORS policy.')

    from starlette.middleware.cors import CORSMiddleware  # noqa: PLC0415

    # Starlette applies middleware in reverse-add order, so this one wraps the
    # permissive stack from main.py and answers the preflight first.
    canonical.app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_origin_regex=origin_regex or None,
        allow_credentials=True,
        allow_methods=['GET', 'POST', 'OPTIONS'],
        allow_headers=['Authorization', 'Content-Type'],
        max_age=600,
    )
    print(f'[pwa-prod] CORS       : {len(origins)} allowed origin(s) — '
          + ', '.join(origins)
          + (f'  + regex {origin_regex}' if origin_regex else ''))

    import uvicorn  # noqa: PLC0415

    port = int(os.environ.get('PORT', '8080'))
    host = '0.0.0.0' if os.environ.get('PORT') else '127.0.0.1'  # noqa: S104
    print(f'[pwa-prod] listening  : {host}:{port}')
    uvicorn.run(canonical.app, host=host, port=port, log_level='info')


if __name__ == '__main__':
    main()
