"""PWA staging — the PAYWAY RAIL against the REAL database.

Why this file exists next to `pwa_staging_payments_test.py`
-----------------------------------------------------------
That test fakes Postgres, so it can prove the seam's logic and nothing about the
schema. This one fakes nothing: it opens a connection to the staging project and
asks the database itself. It is the only place that can answer the questions the
whole design rests on —

    can `billing_grant_purchase` grant a CREDIT_PACK at all?   (it could not,
        before 0007 — `ends_at` is NOT NULL and a pack has no duration)
    do TWO packs accumulate, or does the second hide the first?
    does a pack make `has_active_pass` true, so a paying customer's render is
        not watermarked?
    does `billing_try_hold` debit the pack bucket rather than the free one?
    is the perpetual branch really unreachable from the RevenueCat path?
    does `payway_claim` elect exactly one caller, and recover an abandoned one?
    can an `authenticated` role write a payment state?  (it must not)

Residue, stated rather than discovered later: every probe identity created here
is PERMANENT once it has ledger rows — the append-only trigger blocks the
cascade delete, which is correct and is asserted by the billing contract test
(DB14). Probes are named `payway-<8hex>@contract.invalid` so they are countable.

Run:  cd backend && PYTHONPATH=. python pwa_staging_payway_db_test.py
"""
from __future__ import annotations

import pathlib
import sys
import time
import uuid

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):  # pragma: no cover
        pass

from pwa_staging_db import prove_target, redacted, resolve_staging_url, staging_connection  # noqa: E402

_CHECKS = 0
_FAILURES: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    global _CHECKS
    _CHECKS += 1
    if not ok:
        _FAILURES.append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else f'  {detail}'}")


def section(title: str) -> None:
    print(f"\n── {title} " + "─" * max(0, 66 - len(title)))


def _user(cur, tag: str) -> str:
    uid = str(uuid.uuid4())
    cur.execute(
        "insert into auth.users (id, instance_id, aud, role, email, "
        "created_at, updated_at, is_anonymous) values "
        "(%s, '00000000-0000-0000-0000-000000000000', 'authenticated', "
        "'authenticated', %s, now(), now(), true)",
        (uid, f"payway-{uid[:8]}@contract.invalid"))
    del tag
    return uid


def main() -> int:  # noqa: PLR0915 — one linear narrative reads better than ten helpers
    print(f"target      : {redacted(resolve_staging_url())}")
    facts = prove_target()
    for key, value in facts.items():
        print(f"  {key} = {value}")
    if not facts.get("pwa_staging_schema"):
        print("REFUSING: not the PWA staging project.")
        return 2
    if facts.get("production_only_tables_present"):
        print("REFUSING: production-only tables present.")
        return 2

    run = uuid.uuid4().hex[:8]

    with staging_connection(autocommit=True) as conn:
        cur = conn.cursor()

        # ── PWDB01 — the objects 0007 promised ──────────────────────────────
        section("PWDB01  the rail's schema")
        cur.execute("""
            select count(*) from information_schema.tables
             where table_schema = 'pwa_staging' and table_name = 'payway_transactions'
        """)
        check("PWDB01 pwa_staging.payway_transactions exists", cur.fetchone()[0] == 1)

        cur.execute("""
            select column_name from information_schema.columns
             where table_schema = 'pwa_staging' and table_name = 'payway_transactions'
        """)
        columns = {r[0] for r in cur.fetchall()}
        required = {"tran_id", "user_id", "sku", "product_id", "credits", "amount",
                    "currency", "order_idempotency_key", "attempt_key", "state",
                    "qr_string", "qr_image", "deeplink", "expires_at", "claimed_at",
                    "callback_received_at", "callback_signature_ok", "last_checked_at",
                    "payment_status_code", "approval_code", "paid_amount",
                    "granted_order_id", "granted_at", "failure_reason"}
        check("PWDB01 every column the seam writes is present",
              required <= columns, str(sorted(required - columns)))

        cur.execute("""
            select indexname from pg_indexes
             where schemaname = 'pwa_staging' and tablename = 'payway_transactions'
        """)
        indexes = {r[0] for r in cur.fetchall()}
        check("PWDB01 (user, sku, attempt) is UNIQUE — one attempt, one transaction",
              "payway_transactions_attempt_uidx" in indexes, str(sorted(indexes)))

        cur.execute("select relrowsecurity from pg_class "
                    "where oid = 'pwa_staging.payway_transactions'::regclass")
        check("PWDB01 RLS is enabled on the rail table", cur.fetchone()[0] is True)

        cur.execute("""
            select cmd from pg_policies
             where schemaname = 'pwa_staging' and tablename = 'payway_transactions'
        """)
        cmds = sorted(r[0] for r in cur.fetchall())
        check("PWDB01 the only policy is a SELECT for the owner — no client writes",
              cmds == ["SELECT"], str(cmds))

        cur.execute("""
            select has_table_privilege('authenticated', 'pwa_staging.payway_transactions', p)
              from unnest(array['INSERT','UPDATE','DELETE']) p
        """)
        check("PWDB01 `authenticated` has no write grant on payment state",
              not any(r[0] for r in cur.fetchall()))

        cur.execute("select public.billing_perpetual_ends_at()")
        sentinel = cur.fetchone()[0]
        check("PWDB01 the perpetual sentinel is a finite, parseable far-future date",
              sentinel.year == 2999, str(sentinel))

        # ── PWDB02 — the claim elects exactly one caller ────────────────────
        section("PWDB02  payway_claim")
        payer = _user(cur, "payer")
        cur.execute("select id, price_usd, credits_granted, duration_days "
                    "from public.products where sku = 'pack_10'")
        pack_id, pack_price, pack_credits, pack_duration = cur.fetchone()
        check("PWDB02 pack_10 is a PERPETUAL product (no duration)",
              pack_duration is None, str(pack_duration))

        tran = f"A{run}pwdb02claim"[:20]
        args = (tran, payer, "pack_10", pack_id, pack_credits, pack_duration,
                pack_price, "USD", f"order:khqr:{tran}", f"att-{run}-1")
        cur.execute(
            "select * from pwa_staging.payway_claim(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"
            "now() + interval '30 minutes')", args)
        won, state = cur.fetchone()
        check("PWDB02 the first caller WINS the claim", won is True and state == "CREATED",
              f"{won} {state}")

        cur.execute(
            "select * from pwa_staging.payway_claim(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"
            "now() + interval '30 minutes')", args)
        won2, _ = cur.fetchone()
        check("PWDB02 a second caller LOSES while the claim is fresh — "
              "no duplicate generate-qr, no PayWay 403", won2 is False)

        cur.execute("update pwa_staging.payway_transactions "
                    "set claimed_at = now() - interval '2 minutes' where tran_id = %s",
                    (tran,))
        cur.execute(
            "select * from pwa_staging.payway_claim(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"
            "now() + interval '30 minutes')", args)
        won3, _ = cur.fetchone()
        check("PWDB02 an ABANDONED claim (no QR, stale) is recoverable", won3 is True)

        cur.execute("update pwa_staging.payway_transactions "
                    "set state = 'AWAITING_PAYMENT' where tran_id = %s", (tran,))
        cur.execute(
            "select * from pwa_staging.payway_claim(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"
            "now() + interval '30 minutes')", args)
        won4, state4 = cur.fetchone()
        check("PWDB02 a LIVE QR is never re-issued",
              won4 is False and state4 == "AWAITING_PAYMENT", f"{won4} {state4}")

        cur.execute("select count(*) from pwa_staging.payway_transactions "
                    "where user_id = %s", (payer,))
        check("PWDB02 four claims produced ONE row", cur.fetchone()[0] == 1)

        blocked = False
        try:
            with conn.cursor() as bad:
                bad.execute(
                    "select * from pwa_staging.payway_claim(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"
                    "now() + interval '30 minutes')",
                    (f"A{run}dup", payer, "pack_10", pack_id, pack_credits,
                     pack_duration, pack_price, "USD",
                     f"order:khqr:{tran}", f"att-{run}-2"))
        except Exception as exc:  # noqa: BLE001 — the exception IS the assertion
            blocked = "order_idempotency_key" in str(exc)
        check("PWDB02 two transactions cannot share one order key", blocked)

        # ── PWDB03 — the grant the canonical engine could NOT do before ─────
        section("PWDB03  a CREDIT_PACK grant (impossible before 0007)")
        tx1 = f"A{run}pack1"
        cur.execute(
            "select public.billing_grant_purchase(%s, 'khqr', %s, %s, %s, %s, %s, "
            "'USD', null, %s::jsonb)",
            (payer, tx1, pack_id, pack_credits, pack_duration, pack_price,
             '{"rail":"khqr","gateway":"payway","environment":"sandbox"}'))
        g1 = cur.fetchone()[0]
        check("PWDB03 a credit pack is GRANTED",
              g1.get("ok") is True and g1.get("credited") is True, str(g1))
        check(f"PWDB03 it credited exactly {pack_credits} spaces",
              g1.get("credits") == pack_credits, str(g1))

        cur.execute("select status, provider, amount, currency, idempotency_key "
                    "from public.orders where idempotency_key = %s",
                    (f"order:khqr:{tx1}",))
        order = cur.fetchone()
        check("PWDB03 ONE canonical order, PAID, on the khqr RAIL",
              order is not None and order[0] == "PAID" and order[1] == "khqr", str(order))

        cur.execute("select provider, provider_transaction_id, status from public.payments "
                    "where provider_transaction_id = %s", (tx1,))
        payment = cur.fetchone()
        check("PWDB03 a payment row records the PayWay transaction id",
              payment == ("khqr", tx1, "SUCCESS"), str(payment))

        cur.execute("select ends_at, status from public.passes "
                    "where user_id = %s order by created_at", (payer,))
        passes = cur.fetchall()
        check("PWDB03 exactly ONE pass was created", len(passes) == 1, str(passes))
        check("PWDB03 the pack's pass is PERPETUAL",
              passes[0][0] == sentinel and passes[0][1] == "ACTIVE", str(passes[0]))

        cur.execute("select available_credits, active_pass_id from public.wallets "
                    "where user_id = %s", (payer,))
        wallet = cur.fetchone()
        check("PWDB03 the wallet shows the purchased credits",
              wallet is not None and wallet[0] == pack_credits, str(wallet))
        check("PWDB03 the wallet names an ACTIVE pass — so the render is NOT watermarked",
              wallet[1] is not None, str(wallet))

        # ── PWDB04 — replay ─────────────────────────────────────────────────
        section("PWDB04  the same transaction, granted again")
        cur.execute(
            "select public.billing_grant_purchase(%s, 'khqr', %s, %s, %s, %s, %s, "
            "'USD', null, '{}'::jsonb)",
            (payer, tx1, pack_id, pack_credits, pack_duration, pack_price))
        g1b = cur.fetchone()[0]
        check("PWDB04 a replay credits NOTHING",
              g1b.get("status") == "already_processed" and g1b.get("credited") is False,
              str(g1b))
        cur.execute("select available_credits from public.wallets where user_id = %s",
                    (payer,))
        check("PWDB04 the balance did not move", cur.fetchone()[0] == pack_credits)
        cur.execute("select count(*) from public.ledger_entries "
                    "where user_id = %s and entry_type = 'GRANT'", (payer,))
        check("PWDB04 exactly ONE GRANT row exists", cur.fetchone()[0] == 1)

        # ── PWDB05 — the accumulation the design was chosen for ─────────────
        section("PWDB05  a SECOND pack accumulates instead of hiding the first")
        cur.execute("select id, price_usd, credits_granted from public.products "
                    "where sku = 'pack_25'")
        pack25_id, pack25_price, pack25_credits = cur.fetchone()
        tx2 = f"A{run}pack2"
        # A different second, so `order by ends_at desc` cannot be what saves us:
        # both passes would carry the SAME sentinel and the projection would have
        # to pick one. It must not create a second pass at all.
        time.sleep(1)
        cur.execute(
            "select public.billing_grant_purchase(%s, 'khqr', %s, %s, %s, null, %s, "
            "'USD', null, '{}'::jsonb)",
            (payer, tx2, pack25_id, pack25_credits, pack25_price))
        g2 = cur.fetchone()[0]
        check("PWDB05 the second pack is granted", g2.get("credited") is True, str(g2))

        cur.execute("select count(*) from public.passes where user_id = %s", (payer,))
        check("PWDB05 STILL exactly one pass — the second grant joined the first",
              cur.fetchone()[0] == 1)
        check("PWDB05 both grants landed on the SAME pass",
              g2.get("pass_id") == g1.get("pass_id"),
              f"{g1.get('pass_id')} vs {g2.get('pass_id')}")

        cur.execute("select available_credits from public.wallets where user_id = %s",
                    (payer,))
        total = cur.fetchone()[0]
        check(f"PWDB05 the balance is the SUM ({pack_credits}+{pack25_credits})",
              total == pack_credits + pack25_credits, str(total))

        # ── PWDB06 — the pack is spendable, from the PACK bucket ────────────
        section("PWDB06  billing_try_hold spends the pack")
        intent = f"payway-{run}-i1"
        cur.execute("select public.billing_try_hold(%s, %s, 'free', 1)", (payer, intent))
        hold = cur.fetchone()[0]
        check("PWDB06 generation is allowed", hold.get("granted") is True, str(hold))
        check("PWDB06 the debit hit the PASS bucket, not the free one",
              hold.get("bucket") == "pass", str(hold))
        check("PWDB06 the debited pass is the perpetual one",
              hold.get("pass_id") == g1.get("pass_id"), str(hold))
        cur.execute("select available_credits from public.wallets where user_id = %s",
                    (payer,))
        check("PWDB06 the balance dropped by exactly one",
              cur.fetchone()[0] == total - 1)

        cur.execute("select public.billing_try_hold(%s, %s, 'free', 1)", (payer, intent))
        check("PWDB06 replaying the same intent does not debit twice",
              cur.fetchone()[0].get("idempotent") is True)

        # ── PWDB07 — the RevenueCat path is untouched ───────────────────────
        section("PWDB07  the perpetual branch is unreachable from a dated product")
        rc = _user(cur, "rc")
        cur.execute("select id, credits_granted from public.products where sku = 'weekly_pass'")
        weekly_id, weekly_credits = cur.fetchone()
        cur.execute(
            "select public.billing_grant_purchase(%s, 'revenuecat', %s, %s, %s, 7, 7.99, "
            "'USD', now() + interval '7 days', '{}'::jsonb)",
            (rc, f"rc-{run}", weekly_id, weekly_credits))
        grc = cur.fetchone()[0]
        check("PWDB07 a dated RevenueCat purchase still grants", grc.get("credited") is True,
              str(grc))
        cur.execute("select ends_at from public.passes where user_id = %s", (rc,))
        rc_ends = cur.fetchone()[0]
        check("PWDB07 its pass keeps a REAL seven-day window, not the sentinel",
              rc_ends != sentinel and rc_ends.year < 2100, str(rc_ends))

        # And a dated product with an explicit window is also untouched.
        cur.execute(
            "select public.billing_grant_purchase(%s, 'revenuecat', %s, %s, %s, null, 7.99, "
            "'USD', now() + interval '30 days', '{}'::jsonb)",
            (rc, f"rc-{run}-explicit", weekly_id, weekly_credits))
        cur.execute("select count(*) from public.passes where user_id = %s and ends_at = %s",
                    (rc, sentinel))
        check("PWDB07 an EXPLICIT ends_at also bypasses the perpetual branch",
              cur.fetchone()[0] == 0)

        # ── PWDB08 — the rail row and the order really are one purchase ─────
        section("PWDB08  the rail row maps onto the canonical order")
        cur.execute("""
            select t.order_idempotency_key, o.id, o.status
              from pwa_staging.payway_transactions t
              left join public.orders o on o.idempotency_key = t.order_idempotency_key
             where t.tran_id = %s
        """, (tran,))
        mapping = cur.fetchone()
        check("PWDB08 the rail row stores the key the engine will use",
              mapping[0] == f"order:khqr:{tran}", str(mapping))

        cur.execute("select count(*) from public.orders where user_id = %s", (payer,))
        check("PWDB08 two purchases produced exactly two orders",
              cur.fetchone()[0] == 2, "an order was duplicated")

        # ── residue ─────────────────────────────────────────────────────────
        section("residue (bounded, by design)")
        cur.execute("select count(*) from auth.users "
                    "where email like 'payway-%%@contract.invalid'")
        print(f"  INFO  payway probe identities in staging: {cur.fetchone()[0]} "
              f"— permanent once they hold ledger rows (see the docstring)")

    print(f"\n{'=' * 72}")
    print(f"CHECKS {_CHECKS}   FAILURES {len(_FAILURES)}")
    for name in _FAILURES:
        print(f"  - {name}")
    print("=" * 72)
    return 1 if _FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
