"""The production Web launcher: what it serves, what it starts, what it runs.

Offline. Builds a throwaway FastAPI app with the shapes `main.app` has and
applies the launcher's OWN helpers to it — the helpers are what production runs.

    backend/.venv/Scripts/python.exe pwa_prod_launcher_test.py
"""
import pathlib
import sys

from fastapi import FastAPI
from fastapi.testclient import TestClient

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import run_pwa_prod as launcher  # noqa: E402

passed: list = []
failed: list = []


def check(label: str, ok: bool, detail: str = '') -> None:
    (passed if ok else failed).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else '  ' + detail}")


MOBILE = ('/generate', '/refine', '/refine/verify', '/chat', '/webhooks/revenuecat',
          '/admin/promo-codes', '/internal/reconcile', '/health', '/me/status')
WEB_OPEN = ('/pwa/health', '/pwa/payments/config', '/pwa/payments/payway/callback',
            '/pwa/payments/checkout', '/pwa/payments/order/abc', '/pwa/entitlement',
            '/pwa/auth/phone/prepare')
WEB_SHUT = ('/pwa/engine', '/pwa/staging/health', '/pwa/staging/payments/config',
            '/pwa/generate', '/pwa/chat', '/pwa/refine/verify', '/pwa/generation/k1')


def fake_main():
    app = FastAPI()
    ran: list = []

    @app.on_event('startup')
    async def _start_reconciliation_worker():
        ran.append('reconcile')

    @app.on_event('startup')
    async def _verify_claim_functions_deployed():
        ran.append('probe')

    @app.on_event('startup')
    async def _other_startup():
        ran.append('other')

    for p in MOBILE + WEB_OPEN + WEB_SHUT:
        app.add_api_route(p, (lambda p=p: {'path': p}), methods=['GET', 'POST'])
    return app, ran


print('\n== the production Web launcher ==')
app, ran = fake_main()
left = launcher._strip_mobile_startup(app)
check('LAUNCH01 the mobile reconciliation worker and claim probe are removed, '
      'nothing else is', left == ['_other_startup'], str(left))
import os  # noqa: E402

os.environ.pop('PWA_PROD_GENERATION_OPEN', None)
app.add_middleware(launcher._WebRoutesOnly, prefix='/pwa',
                   closed=launcher._closed_paths('/pwa'))
with TestClient(app) as client:
    check('LAUNCH02 and they never run in this process', ran == ['other'], str(ran))
    for p in MOBILE:
        check(f'LAUNCH03 mobile route {p} is not served here',
              client.post(p).status_code == 404 and client.get(p).status_code == 404)
    for p in WEB_OPEN:
        check(f'LAUNCH04 Web route {p} is served', client.get(p).status_code == 200)
    for p in WEB_SHUT:
        check(f'LAUNCH05 {p} is closed in production', client.get(p).status_code == 404)

bare = FastAPI()
try:
    launcher._strip_mobile_startup(bare)
    stopped = False
except SystemExit:
    stopped = True
check('LAUNCH06 a main.py that no longer registers the worker stops the launch '
      '(fail closed, never a guess)', stopped)

main_src = (HERE / 'main.py').read_text(encoding='utf-8')
check('LAUNCH07 main.py still registers the two names the launcher removes',
      'async def _start_reconciliation_worker' in main_src
      and 'async def _verify_claim_functions_deployed' in main_src)

prod_toml = (HERE / 'fly.prod.toml').read_text(encoding='utf-8')
stg_toml = (HERE / 'fly.toml').read_text(encoding='utf-8')
docker = (HERE / 'Dockerfile').read_text(encoding='utf-8')
src = (HERE / 'run_pwa_prod.py').read_text(encoding='utf-8')
check('LAUNCH08 the production app runs run_pwa_prod.py',
      'app = "python run_pwa_prod.py"' in prod_toml and 'processes = ["app"]' in prod_toml)
check('LAUNCH09 staging is untouched: fly.toml has no process override and the '
      'image still starts the staging launcher',
      '[processes]' not in stg_toml and 'CMD ["python", "run_pwa_staging.py"]' in docker)
check('LAUNCH10 the production app is ayden-api, PWA_TARGET=production, PayWay production',
      'app = "ayden-api"' in prod_toml and 'PWA_TARGET = "production"' in prod_toml
      and 'PAYWAY_ENV = "production"' in prod_toml
      and 'https://api.aydenstudio.com/pwa/payments/payway/callback' in prod_toml)
check('LAUNCH11 main() applies both gates',
      '_strip_mobile_startup(canonical.app)' in src and '_WebRoutesOnly' in src
      and 'closed = _closed_paths(target.prefix)' in src)
os.environ['PWA_PROD_GENERATION_OPEN'] = '1'
reopened = launcher._closed_paths('/pwa')
os.environ.pop('PWA_PROD_GENERATION_OPEN', None)
check('LAUNCH12 the generation surface reopens only by explicit decision, '
      'and engine/staging stay closed even then',
      reopened == ('/pwa/engine', '/pwa/staging'), str(reopened))

print(f"\n{'ALL PASS' if not failed else 'FAILED'} ({len(passed)} passed, {len(failed)} failed)")
raise SystemExit(1 if failed else 0)
