"""Wave 5.17c — Live confirmation probes.

Runs three checks against the live Supabase project before commit/push :
  A. usage_log has the expected 3 success rows for the test user
  B. Founder admin grant is present (idempotent insert)
  C. quota.has_admin_role() returns True after cache reset

This script uses the same service-role client construction as main.py so
network/credentials behave identically to production.
"""
import asyncio
import os
import sys
from pathlib import Path

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

# Load backend/.env into os.environ before importing the supabase client.
ENV_PATH = Path(__file__).with_name('.env')
if ENV_PATH.exists():
    for line in ENV_PATH.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        os.environ.setdefault(k.strip(), v.strip())

from supabase import create_client

TEST_USER = '49f2ed8f-577a-45ce-894c-a9dafb272fb7'


def main():
    supa = create_client(
        os.environ['SUPABASE_URL'],
        os.environ['SUPABASE_SERVICE_ROLE_KEY'],
    )

    print('═' * 78)
    print('Wave 5.17c — Live Confirmation Probes')
    print('═' * 78)

    # ── A. usage_log success rows ───────────────────────────────────────────
    print('\n[A] usage_log success rows for test user')
    res = (
        supa.table('usage_log')
        .select('id, status, call_type, created_at, completed_at, request_id, cost_usd_estimate')
        .eq('user_id', TEST_USER)
        .order('created_at', desc=True)
        .execute()
    )
    rows = res.data or []
    success_rows = [r for r in rows if r['status'] == 'success']
    failed_rows = [r for r in rows if r['status'] == 'failed']
    in_progress_rows = [r for r in rows if r['status'] == 'in_progress']
    print(f'  total rows         : {len(rows)}')
    print(f'  status=success     : {len(success_rows)}')
    print(f'  status=failed      : {len(failed_rows)}')
    print(f'  status=in_progress : {len(in_progress_rows)}')
    for r in success_rows[:5]:
        print(
            f'    - {r["created_at"][:19]}  req={r["request_id"][:16]}…  cost=${r.get("cost_usd_estimate") or 0:.4f}'
        )
    A_ok = len(success_rows) >= 3
    print(f'  → A : {"✅ PASS" if A_ok else "❌ FAIL"}  (expected ≥3 success rows)')

    # ── B. Founder admin grant ──────────────────────────────────────────────
    print('\n[B] Founder admin grant (idempotent)')
    # First, look up the existing rows so we can report what was there.
    pre = (
        supa.table('user_roles')
        .select('user_id, role, granted_at, expires_at')
        .eq('user_id', TEST_USER)
        .eq('role', 'admin')
        .execute()
    )
    pre_rows = pre.data or []
    print(f'  rows before insert : {len(pre_rows)}')

    # Apply the grant — idempotent via primary key (user_id, role).
    try:
        supa.table('user_roles').upsert(
            {
                'user_id': TEST_USER,
                'role': 'admin',
                'granted_by': TEST_USER,
                'notes': 'Founder self-grant — Wave 5.17c',
            },
            on_conflict='user_id,role',
        ).execute()
    except Exception as exc:
        print(f'  upsert error : {exc}')

    post = (
        supa.table('user_roles')
        .select('user_id, role, granted_at, expires_at, notes')
        .eq('user_id', TEST_USER)
        .eq('role', 'admin')
        .execute()
    )
    post_rows = post.data or []
    print(f'  rows after insert  : {len(post_rows)}')
    for r in post_rows:
        print(f'    - role={r["role"]}  granted_at={r["granted_at"][:19]}  expires_at={r.get("expires_at")}')
    B_ok = len(post_rows) == 1
    print(f'  → B : {"✅ PASS" if B_ok else "❌ FAIL"}  (expected exactly 1 admin grant)')

    # ── C. quota.has_admin_role bypass works ────────────────────────────────
    print('\n[C] quota.has_admin_role() resolves admin bypass')
    # Import quota here AFTER env is set, with our service-role supa client.
    from quota import has_admin_role, get_quota_status, _clear_role_cache

    async def run():
        _clear_role_cache()
        is_admin = await has_admin_role(TEST_USER, supa=supa)
        print(f'  has_admin_role(TEST_USER) = {is_admin}')
        status = await get_quota_status(TEST_USER, supa=supa)
        print(f'  get_quota_status.allowed  = {status.allowed}')
        print(f'  get_quota_status.reason   = {status.reason}')
        print(f'  get_quota_status.used     = {status.used}')
        return is_admin and status.allowed and status.reason == 'admin_bypass'

    C_ok = asyncio.run(run())
    print(f'  → C : {"✅ PASS" if C_ok else "❌ FAIL"}  (expected admin_bypass reason)')

    # ── Summary ─────────────────────────────────────────────────────────────
    print()
    print('═' * 78)
    print('Summary')
    print('═' * 78)
    print(f'  A. usage_log ≥3 success rows : {"✅" if A_ok else "❌"}')
    print(f'  B. Founder admin grant       : {"✅" if B_ok else "❌"}')
    print(f'  C. Admin bypass active       : {"✅" if C_ok else "❌"}')
    overall = A_ok and B_ok and C_ok
    print()
    print(f'  OVERALL : {"✅ READY TO COMMIT" if overall else "❌ HOLD — fix above before push"}')
    sys.exit(0 if overall else 1)


if __name__ == '__main__':
    main()
