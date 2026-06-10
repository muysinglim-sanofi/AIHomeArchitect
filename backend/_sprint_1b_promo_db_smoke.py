"""Sprint 1B — live RPC smoke test against Supabase (create→redeem→consume→cleanup).

Confirms the SQL functions are applied and the Python wrappers work end-to-end.
Writes a throwaway code + a fake-user redemption, then DELETES the code
(cascade removes the redemption). Run: python _sprint_1b_promo_db_smoke.py
"""
import asyncio
import os
import uuid

from supabase import create_client

import promo


def _load_env(path=".env"):
    if not os.path.exists(path):
        return
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


_load_env()
supa = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])

PASS = 0
FAIL = 0


def check(name, cond, got=None):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  (got={got})")


async def main():
    user = str(uuid.uuid4())
    code = f"TEST-{uuid.uuid4().hex[:6].upper()}"
    code_id = None
    print(f"Sprint 1B — live RPC smoke (user={user[:8]} code={code})")
    try:
        # create a limited code: 2 generations, max 5 redemptions
        row = await promo.create_promo_code(
            created_by=user, code=code, type_="limited_generations",
            generation_limit=2, max_redemptions=5, expires_at=None,
            campaign="SMOKE", note="db smoke", supa=supa,
        )
        code_id = row.get("id")
        check("create_promo_code", bool(code_id) and row.get("redeemed_count") == 0, row)

        acc = await promo.get_promo_access(user, supa=supa)
        check("get_promo_access (pre-redeem)",
              acc == {"unlimited_active": False, "limited_remaining": 0, "active_campaign": None}, acc)

        r = await promo.redeem_promo(user, code.lower(), supa=supa)  # lower → tests case-insensitive
        check("redeem ok + type", r.get("ok") and r.get("type") == "limited_generations", r)

        acc = await promo.get_promo_access(user, supa=supa)
        check("get_promo_access (post-redeem) remaining=2",
              acc["limited_remaining"] == 2 and acc["active_campaign"] == "SMOKE", acc)

        r2 = await promo.redeem_promo(user, code, supa=supa)
        check("redeem again -> already_redeemed",
              (not r2.get("ok")) and r2.get("error") == "already_redeemed", r2)

        c1 = await promo.consume_promo_generation(user, supa=supa)
        check("consume #1 -> remaining 1", c1.get("ok") and c1.get("remaining") == 1, c1)
        c2 = await promo.consume_promo_generation(user, supa=supa)
        check("consume #2 -> remaining 0", c2.get("ok") and c2.get("remaining") == 0, c2)
        c3 = await promo.consume_promo_generation(user, supa=supa)
        check("consume #3 -> exhausted",
              (not c3.get("ok")) and c3.get("error") == "no_promo_generations", c3)

        acc = await promo.get_promo_access(user, supa=supa)
        check("get_promo_access (exhausted) remaining=0", acc["limited_remaining"] == 0, acc)

        bad = await promo.redeem_promo(user, "NOPE-NOPE-NOPE", supa=supa)
        check("redeem invalid -> invalid_code",
              (not bad.get("ok")) and bad.get("error") == "invalid_code", bad)

        # inactive code path
        await promo.set_promo_active(code_id, False, supa=supa)
        user2 = str(uuid.uuid4())
        inact = await promo.redeem_promo(user2, code, supa=supa)
        check("redeem inactive -> inactive_code",
              (not inact.get("ok")) and inact.get("error") == "inactive_code", inact)
    finally:
        if code_id:
            await asyncio.to_thread(
                lambda: supa.table("promo_codes").delete().eq("id", code_id).execute()
            )
            print("  cleanup: test code deleted (cascade removed redemptions)")

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
