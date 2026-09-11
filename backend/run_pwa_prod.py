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


#: `main.py`'s startup work that belongs to the MOBILE backend. It already runs
#: against this same production database, from Render, with the mobile code. A
#: second copy here would race it with a different version of that code — the
#: reconciliation worker settles generation intents and billing holds. This
#: process serves the Web routes and starts none of it.
_MOBILE_STARTUP = ('_start_reconciliation_worker', '_verify_claim_functions_deployed')


def _strip_mobile_startup(app) -> list:
    """Remove the mobile backend's startup work from THIS process. Fail closed:
    if `main.py` no longer registers them under these names, refuse to start
    rather than guess what would now run against the shared database."""
    handlers = list(app.router.on_startup)
    names = [getattr(h, '__name__', '') for h in handlers]
    missing = [n for n in _MOBILE_STARTUP if n not in names]
    if missing:
        _die('main.py no longer registers ' + ', '.join(missing) + ' at startup — '
             'review what this process would run against the shared production '
             'database before starting it.')
    app.router.on_startup[:] = [h for h in handlers
                                if getattr(h, '__name__', '') not in _MOBILE_STARTUP]
    return [getattr(h, '__name__', '') for h in app.router.on_startup]


class _WebRoutesOnly:
    """ASGI gate: this process answers under the Web prefix, and nowhere else.

    `main.app` also carries the mobile API (`/generate`, `/refine`, `/chat`,
    `/webhooks/revenuecat`, `/admin/*`, `/internal/*`). The mobile backend
    serves those; here they would be a second, differently-versioned door onto
    the same production data. Each `closed` entry is refused with everything
    under it — `{prefix}/engine` (the staging diagnostic that publishes the
    engine's configuration) and `{prefix}/staging`.
    """

    def __init__(self, app, prefix: str, closed: tuple = ()):
        self.app = app
        self.prefix = prefix.rstrip('/')
        self.closed = tuple(c.rstrip('/') for c in closed)

    def allows(self, path: str) -> bool:
        under = path == self.prefix or path.startswith(self.prefix + '/')
        shut = any(path == c or path.startswith(c + '/') for c in self.closed)
        return under and not shut

    async def __call__(self, scope, receive, send):
        if scope['type'] == 'http' and not self.allows(scope.get('path', '')):
            body = b'{"detail":"Not Found"}'
            await send({'type': 'http.response.start', 'status': 404,
                        'headers': [(b'content-type', b'application/json'),
                                    (b'content-length', str(len(body)).encode())]})
            await send({'type': 'http.response.body', 'body': body})
            return
        if scope['type'] == 'websocket' and not self.allows(scope.get('path', '')):
            await send({'type': 'websocket.close', 'code': 1008})
            return
        await self.app(scope, receive, send)


#: The Web GENERATION surface. Closed in production until the Web launch itself
#: (`PWA_PROD_GENERATION_OPEN=1`): its tables (`pwa_projects`, `pwa_visions`,
#: the generation claims) do not exist in the production project yet, and it
#: spends Spaces on the shared ledger. The payment-validation phase needs none of it.
_GENERATION_PATHS = ('/generate', '/chat', '/refine', '/generation')


def _closed_paths(prefix: str) -> tuple:
    closed = [prefix + '/engine', prefix + '/staging']
    if os.environ.get('PWA_PROD_GENERATION_OPEN', '').strip() != '1':
        closed += [prefix + p for p in _GENERATION_PATHS]
    return tuple(closed)


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

    # 7b) None of the mobile backend's background work in this process.
    left = _strip_mobile_startup(canonical.app)
    print('[pwa-prod] mobile     : reconciliation worker + claim probe NOT started '
          '(the mobile backend owns them); startup left: ' + (', '.join(left) or 'none'))

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

    # 9) Added LAST, so it is the outermost layer: nothing outside the Web
    #    prefix is answered by this process, and the diagnostic is closed.
    closed = _closed_paths(target.prefix)
    canonical.app.add_middleware(_WebRoutesOnly, prefix=target.prefix, closed=closed)
    print(f'[pwa-prod] routes     : {target.prefix}/* only; closed: ' + ', '.join(closed))

    import uvicorn  # noqa: PLC0415

    port = int(os.environ.get('PORT', '8080'))
    host = '0.0.0.0' if os.environ.get('PORT') else '127.0.0.1'  # noqa: S104
    print(f'[pwa-prod] listening  : {host}:{port}')
    uvicorn.run(canonical.app, host=host, port=port, log_level='info')


if __name__ == '__main__':
    main()
