"""Sprint 1B — access-resolver validation (no DB, no env).

Monkeypatches the 4 entitlement lookups (has_admin_role / is_admin_role /
get_promo_access / get_quota_status) and asserts resolve_generation_access()
returns the correct tier + watermark/scope/quota/consume flags for every
priority scenario. Run: python _sprint_1b_promo_validation.py
"""
import asyncio
import promo

PASS = 0
FAIL = 0


def check(name, cond):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}")


class _Q:  # QuotaStatus stub
    def __init__(self, limit, used):
        self.limit, self.used = limit, used
        self.allowed = used < limit
        self.reason = "stub"


def setup(*, admin=False, premium=False, unl=False, lim=0, free_used=0, free_limit=3):
    full = admin or premium

    async def _has(u, supa=None):
        return full

    async def _adm(u, supa=None):
        return admin

    async def _pro(u, supa=None):
        return {"unlimited_active": unl, "limited_remaining": lim,
                "active_campaign": "CAMPAIGN" if (unl or lim) else None}

    async def _q(u, supa=None):
        return _Q(free_limit, free_used)

    promo.has_admin_role = _has
    promo.is_admin_role = _adm
    promo.get_promo_access = _pro
    promo.get_quota_status = _q


async def resolve():
    # supa=object() so the resolver never calls _get_supa() (-> would import main)
    return await promo.resolve_generation_access("user", supa=object())


async def main():
    print("Sprint 1B — access resolver")

    setup(admin=True)
    d = await resolve()
    check("admin -> tier", d.tier == "admin")
    check("admin -> clean+unlimited+bypass, no ledger/consume",
          d.clean_watermark and d.can_generate and d.bypass_scope
          and not d.consumes_free_quota and not d.consume_promo_on_success)

    setup(premium=True)
    d = await resolve()
    check("premium -> tier+clean", d.tier == "premium" and d.clean_watermark
          and d.bypass_scope and not d.consumes_free_quota)

    setup(unl=True, free_used=3)  # free exhausted but unlimited promo active
    d = await resolve()
    check("promo_unlimited -> tier", d.tier == "promo_unlimited")
    check("promo_unlimited -> clean+bypass, no consume",
          d.clean_watermark and d.can_generate and d.bypass_scope
          and not d.consume_promo_on_success and not d.consumes_free_quota)

    setup(lim=25, free_used=3)  # free exhausted, 25 promo gens
    d = await resolve()
    check("promo_limited -> tier", d.tier == "promo_limited")
    check("promo_limited -> clean+bypass+CONSUME, no free ledger",
          d.clean_watermark and d.can_generate and d.bypass_scope
          and d.consume_promo_on_success and not d.consumes_free_quota)
    check("promo_limited -> remaining surfaced", d.promo_generations_remaining == 25)

    setup(free_used=1, free_limit=3)
    d = await resolve()
    check("free -> tier+WATERMARK+scoped+ledger",
          d.tier == "free" and not d.clean_watermark and d.can_generate
          and not d.bypass_scope and d.consumes_free_quota
          and not d.consume_promo_on_success)
    check("free -> remaining=2", d.free_remaining == 2)

    setup(free_used=3, free_limit=3)  # nothing left anywhere
    d = await resolve()
    check("blocked -> cannot generate", d.tier == "blocked" and not d.can_generate)

    # ── priority ordering ──
    setup(admin=True, unl=True, lim=25)
    d = await resolve()
    check("priority: admin beats promo", d.tier == "admin")

    setup(unl=True, lim=25)
    d = await resolve()
    check("priority: unlimited beats limited",
          d.tier == "promo_unlimited" and not d.consume_promo_on_success)

    setup(premium=True, lim=25)
    d = await resolve()
    check("priority: premium beats promo", d.tier == "premium")

    # ── watermark matrix (the security-critical mapping) ──
    setup(free_used=0)
    d = await resolve()
    check("watermark: free -> watermark (clean=False)", d.clean_watermark is False)
    setup(lim=5)
    d = await resolve()
    check("watermark: promo_limited -> clean", d.clean_watermark is True)
    setup(unl=True)
    d = await resolve()
    check("watermark: promo_unlimited -> clean", d.clean_watermark is True)

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
