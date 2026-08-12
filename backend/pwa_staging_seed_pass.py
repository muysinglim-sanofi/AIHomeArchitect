"""TEST-ONLY: seed a real staging Pass so the post-payment UX can be reviewed.

§12 of the brief asks for the post-payment experience to be exercised WITHOUT
faking a payment:

    Use the canonical Billing administrative/test seam to seed a real staging
    Pass. Do NOT build a fake "successful ABA payment" button. Keep test-only
    admin actions inaccessible from normal browser UI.

So this is a command-line script, run by a developer, holding the SERVICE-ROLE
key. Nothing in `lib/` can reach it, no route exposes it, and it is not imported
by the app. The browser cannot invoke it even in staging.

What it does is call the canonical acquisition RPC — the SAME one the RevenueCat
webhook calls today and the SAME one a future ABA callback will call:

    public.billing_grant_purchase(user, provider, tx, product, credits,
                                  duration_days, price, currency, expires, meta)

That means the Pass being reviewed is a REAL pass: real `passes` row, real
append-only ledger credit, real wallet projection, resolved by the same
`billing_try_hold` the render path uses. A hand-written wallet update would have
produced a screen that looks right and a system that is wrong.

Usage
-----
    cd backend
    python pwa_staging_seed_pass.py <user_id> [--product weekly_pass]
    python pwa_staging_seed_pass.py --latest-guest      # the newest anon user

The second form exists for the visual review: the browser mints an anonymous
user, and copying its id out of devtools is the only friction in the loop.
"""
from __future__ import annotations

import argparse
import pathlib
import sys
import uuid

HERE = pathlib.Path(__file__).resolve().parent
STAGING_REF = "eedcahzekpgxvvfxufbk"


def _refuse_unless_staging() -> None:
    """This script grants money. It runs against staging or it does not run."""
    from pwa_staging_db import resolve_staging_url  # noqa: PLC0415

    # `resolve_staging_url` already refuses production and anything that is not
    # the allow-listed ref, on the string it will really connect with. Calling
    # it here means the refusal happens before a single argument is read.
    if STAGING_REF not in resolve_staging_url():
        raise SystemExit("REFUSING: not the staging project")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("user_id", nargs="?", help="the Supabase user to grant to")
    ap.add_argument("--product", default="weekly_pass",
                    help="sku from public.products (default: weekly_pass)")
    ap.add_argument("--latest-guest", action="store_true",
                    help="grant to the most recently created anonymous user")
    ap.add_argument("--revoke", action="store_true",
                    help="expire the user's passes instead of granting one")
    args = ap.parse_args()

    _refuse_unless_staging()
    from pwa_staging_db import staging_connection  # noqa: PLC0415

    with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
        uid = args.user_id
        if args.latest_guest:
            cur.execute("select id, created_at from auth.users "
                        "where is_anonymous is true order by created_at desc limit 1")
            row = cur.fetchone()
            if not row:
                raise SystemExit("REFUSING: no anonymous user exists yet")
            uid = str(row[0])
            print(f"latest guest : {uid}  (created {row[1]})")
        if not uid:
            raise SystemExit("REFUSING: give a user_id or --latest-guest")

        if args.revoke:
            # Expiry, not deletion: the ledger is append-only by design, and a
            # revoked pass must leave the same trail a lapsed one does.
            # A pass is "active" to the canonical projection when its status is
            # ACTIVE and now() falls between starts_at and ends_at. Ending it is
            # therefore moving `ends_at` into the past, which is what a lapse is.
            cur.execute(
                "update public.passes set ends_at = now() - interval '1 minute', "
                "  updated_at = now() "
                "where user_id = %s::uuid and status = 'ACTIVE' "
                "  and now() between starts_at and ends_at", (uid,))
            print(f"expired {cur.rowcount} pass(es) for {uid}")
            cur.execute("select public.billing_reproject_wallet(%s::uuid)", (uid,))
            cur.execute("select available_credits from public.wallets "
                        "where user_id = %s::uuid", (uid,))
            got = cur.fetchone()
            print(f"wallet now   : {got[0] if got else 0}")
            return 0

        cur.execute(
            "select id, credits_granted, duration_days, price_usd, currency "
            "from public.products where sku = %s and active", (args.product,))
        product = cur.fetchone()
        if not product:
            raise SystemExit(f"REFUSING: no active product '{args.product}'")
        pid, credits, days, price, currency = product

        # A transaction id that is unique per grant, exactly as a provider's
        # would be. `billing_grant_purchase` keys idempotence on it, so re-running
        # this script tops up rather than silently doing nothing — and cannot
        # double-grant a single transaction.
        tx = f"staging-seed-{uuid.uuid4().hex[:12]}"
        # PROVIDER — a finding worth stating rather than working around.
        #
        # `orders_provider_check` and `payments_provider_check` allow exactly
        # ('revenuecat', 'khqr'). There is no 'aba', and no 'staging_seed'. So
        # wiring a new web payment provider is a MIGRATION plus an adapter, not
        # an adapter alone — the canonical schema has an opinion about who may
        # take money. The seed therefore books under 'khqr', the Cambodia rail
        # already sanctioned, and marks itself test_only in the metadata so the
        # row is never mistaken for a real sale.
        cur.execute(
            "select public.billing_grant_purchase("
            "  %s::uuid, 'khqr', %s, %s::uuid, %s, %s, %s, %s,"
            "  case when %s is null then null else now() + (%s || ' days')::interval end,"
            "  '{\"source\":\"pwa_staging_seed_pass\",\"test_only\":true}'::jsonb)",
            (uid, tx, pid, credits, days, price, currency, days, days))
        print(f"granted      : {args.product}  ({credits} credits"
              f"{f', {days}d' if days else ''}, {currency} {price})")
        print(f"transaction  : {tx}   provider=khqr (test_only metadata)")

        cur.execute("select available_credits from public.wallets "
                    "where user_id = %s::uuid", (uid,))
        wallet = cur.fetchone()
        cur.execute(
            "select count(*) from public.passes where user_id = %s::uuid "
            "  and status = 'ACTIVE' and now() between starts_at and ends_at",
            (uid,))
        active = cur.fetchone()[0]
        print(f"wallet now   : {wallet[0] if wallet else 0}")
        print(f"active passes: {active}")
        print("\nThe app reads this through GET /pwa/staging/entitlement. Reload "
              "the tab (or reopen the paywall) to see the post-payment state.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
