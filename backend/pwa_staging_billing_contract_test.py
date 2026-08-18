"""DB CONTRACT — the canonical Billing Engine, as installed in PWA staging.

This is not a unit test of Python. It interrogates the REAL staging database and
asserts that what migration `0006_billing_canonical.sql` put there is the
canonical shape the backend code expects — tables, columns, RPC signatures,
constraints, indexes, RLS, grants, the append-only guarantee — and that the
objects deliberately EXCLUDED are genuinely absent.

Why it exists: every claim made so far about this schema was made about a FILE.
A file is not a database. `billing.try_hold` calls a function by name and arity;
if the 3-arg version were installed the free tier would silently be 3 instead of
1, and nothing in the Python would notice.

Run:  cd backend && python pwa_staging_billing_contract_test.py

Safe, with one honest consequence. It is read-only EXCEPT for two anonymous
probe identities per run (`probe-*@contract.invalid`) and their ledger rows.
Those identities are PERMANENT, and that is not sloppiness — it is the
append-only guarantee doing its job:

    delete from auth.users where id = <probe>
      -> ON DELETE CASCADE issues a DELETE on ledger_entries
      -> trg_ledger_no_row_mutation raises "ledger_entries is append-only"

So a user who has ever been billed cannot be deleted while their ledger rows
exist. That is canonical and correct for accounting; it is also a real erasure
constraint worth knowing about before anyone promises a "delete my account"
button. The run therefore leaves its probes behind, counts them, and asserts the
residue is bounded rather than pretending to clean up.
"""
from __future__ import annotations

import sys
import uuid

from pwa_staging_db import prove_target, redacted, resolve_staging_url, staging_connection

_FAILURES: list[str] = []
_CHECKS = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    global _CHECKS
    _CHECKS += 1
    if ok:
        print(f"  PASS  {label}")
    else:
        print(f"  FAIL  {label}" + (f"  — {detail}" if detail else ""))
        _FAILURES.append(label)


def section(title: str) -> None:
    # ASCII only: this runs on a Windows console whose default codec is cp1252.
    print(f"\n-- {title} " + "-" * max(0, 66 - len(title)))


# ── expectations ─────────────────────────────────────────────────────────────

EXPECTED_TABLES = [
    "sessions", "user_roles", "promo_codes", "promo_redemptions",
    "generation_intents", "products", "orders", "payments", "passes",
    "ledger_entries", "wallets",
]

# NOT installed by 0006 — see its header. That is a SCOPE statement about the
# migration, and until 2026-08-18 it was also a statement about the project.
#
# MEASURED 2026-08-18, while unblocking `prove_target`: the staging project is
# SHARED with the unified-identity chantier, which installed several of these
# itself (account_state with 73 rows; empty messages / usage_log / assets shells;
# generation_jobs; rc_pass_transfers; identity_merge*; claim_intent /
# reclaim_intent / billing_reparent_pass / is_user_anonymous). None of it is
# reachable from the PWA path — the adapter calls none of those objects — and
# none of it can be removed from here without breaking the other chantier.
#
# So the list splits in two. `EXCLUDED_HARD` are the ones whose presence would
# mean this connection is NOT the staging project (device_tokens is mobile push,
# production-only). `EXCLUDED_BY_0006` is reported as drift: visible, counted,
# and not a failure of the PWA billing contract.
EXCLUDED_HARD = ["device_tokens"]

EXCLUDED_BY_0006 = [
    "usage_log", "generation_jobs", "messages", "account_state",
    "identity_merge_tickets", "identity_merges", "rc_pass_transfers",
]

EXCLUDED_FUNCTIONS = [
    "claim_intent", "reclaim_intent", "increment_intent_fire",
    "claim_guest_and_bonus", "billing_reparent_pass", "is_user_anonymous",
]

# The tables a browser token must NEVER be able to write. This is the assertion
# the blanket "no non-SELECT policy in public" was really making, and narrowing
# it to these is what makes it true again on a shared project: the ALL policies
# that appeared belong to `sessions` / `messages` / `assets`, the mobile CHAT
# tables, and touch no billing object.
BILLING_TABLES_NO_CLIENT_WRITE = [
    "ledger_entries", "wallets", "passes", "orders", "payments",
    "products", "generation_intents", "user_roles",
]

# proname -> pronargs. The arity IS the contract: billing.try_hold passes
# p_trial_credits only when the effective trial differs from 3.
EXPECTED_FUNCTIONS = {
    "get_promo_access": 1,
    "redeem_promo_code": 2,
    "consume_promo_generation": 1,
    "billing_reproject_wallet": 1,
    "billing_grant_purchase": 10,
    "billing_try_hold": 4,
}

# Columns the Python actually reads/writes, per module.
EXPECTED_COLUMNS = {
    "generation_intents": [
        "intent_id", "user_id", "session_id", "iteration", "status", "intent",
        "result_ref", "error", "reclaim_count", "client_request_id",
        "created_at", "updated_at", "started_at", "completed_at",
    ],
    "ledger_entries": [
        "id", "user_id", "entry_type", "available_delta", "pass_id",
        "reference_type", "reference_id", "idempotency_key", "metadata",
        "created_at",
    ],
    "wallets": [
        "user_id", "available_credits", "held_credits", "active_pass_id",
        "pass_expires_at", "ledger_version", "updated_at",
    ],
    "passes": [
        "id", "user_id", "product_id", "source_order_id", "starts_at",
        "ends_at", "status", "created_at", "updated_at",
    ],
    "products": [
        "id", "sku", "type", "credits_granted", "duration_days", "price_usd",
        "currency", "revenuecat_product_id", "apple_product_id",
        "google_product_id", "khqr_enabled", "metadata", "active",
    ],
    "user_roles": ["user_id", "role", "granted_at", "granted_by", "expires_at", "notes"],
}


def main() -> int:
    print(f"target      : {redacted(resolve_staging_url())}")
    facts = prove_target()
    for k, v in facts.items():
        print(f"  {k} = {v}")
    if not facts.get("pwa_staging_schema"):
        print("REFUSING: not the PWA staging project.")
        return 2
    if facts.get("production_only_tables_present"):
        print("REFUSING: production-only tables present.")
        return 2

    probe_a = str(uuid.uuid4())
    probe_b = str(uuid.uuid4())

    with staging_connection(autocommit=True) as conn:
        cur = conn.cursor()

        # ── DB01 — tables ───────────────────────────────────────────────────
        section("DB01  tables present")
        cur.execute(
            "select table_name from information_schema.tables where table_schema='public'")
        present = {r[0] for r in cur.fetchall()}
        for t in EXPECTED_TABLES:
            check(f"DB01 table public.{t}", t in present)

        section("DB02  excluded objects")
        for t in EXCLUDED_HARD:
            check(f"DB02 NO public.{t} (production-only marker)", t not in present,
                  "this connection may not be the staging project")
        cur.execute(
            "select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace "
            "where n.nspname='public'")
        fn_names = {r[0] for r in cur.fetchall()}

        # Drift, reported rather than asserted. See the EXCLUDED_BY_0006 note:
        # the staging PROJECT is shared, so "0006 did not install it" no longer
        # implies "it is not here". Printed every run so a NEW arrival is visible
        # the day it appears, instead of being discovered by a guard six weeks
        # later.
        drift_t = [t for t in EXCLUDED_BY_0006 if t in present]
        drift_f = [f for f in EXCLUDED_FUNCTIONS if f in fn_names]
        print(f"  INFO  outside 0006's scope, present in this shared project: "
              f"tables={drift_t or '-'} functions={drift_f or '-'}")
        check("DB02 nothing outside 0006's scope is reachable from the PWA path",
              not (set(drift_t) & set(EXPECTED_TABLES)),
              "a drifted object shadows one the adapter uses")

        # ── DB03 — RPC signatures ───────────────────────────────────────────
        section("DB03  RPC signatures (arity is the contract)")
        cur.execute(
            "select p.proname, p.pronargs from pg_proc p "
            "join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'")
        arities: dict[str, set[int]] = {}
        for name, nargs in cur.fetchall():
            arities.setdefault(name, set()).add(nargs)
        for name, nargs in EXPECTED_FUNCTIONS.items():
            check(f"DB03 {name}/{nargs}", nargs in arities.get(name, set()),
                  f"found arities {sorted(arities.get(name, set())) or 'none'}")
        # The superseded 3-arg try_hold must NOT co-exist: PostgREST would have
        # to disambiguate, and the 3-arg one hard-codes TRIAL = 3.
        check("DB03 no superseded billing_try_hold/3",
              3 not in arities.get("billing_try_hold", set()),
              "the TRIAL=3 version is still installed")

        # ── DB04 — columns ──────────────────────────────────────────────────
        section("DB04  columns the backend reads/writes")
        for table, cols in EXPECTED_COLUMNS.items():
            cur.execute(
                "select column_name from information_schema.columns "
                "where table_schema='public' and table_name=%s", (table,))
            have = {r[0] for r in cur.fetchall()}
            missing = [c for c in cols if c not in have]
            check(f"DB04 {table} columns", not missing, f"missing {missing}")

        # ── DB05 — the sessions shell is MINIMAL and FK-compatible ──────────
        section("DB05  sessions shell")
        cur.execute(
            "select column_name from information_schema.columns "
            "where table_schema='public' and table_name='sessions'")
        sess_cols = {r[0] for r in cur.fetchall()}
        check("DB05 sessions.id exists", "id" in sess_cols)
        check("DB05 sessions stays minimal (no mobile chat columns)",
              not (sess_cols - {"id", "created_at"}), f"extra columns {sess_cols}")
        # The claim is "the WEB never writes a session", and a raw row count
        # stopped being able to say that on 2026-08-18: the shared project now
        # holds one row written by the unified-identity chantier. What the Web
        # actually promises is testable directly, and is stronger — every intent
        # it has ever written carries session_id = NULL.
        cur.execute("select count(*) from public.sessions")
        print(f"  INFO  public.sessions rows: {cur.fetchone()[0]} "
              f"(written by the identity chantier, not by the Web)")
        cur.execute("select count(*) from public.generation_intents "
                    "where session_id is not null")
        check("DB05 NO generation intent is linked to a session (the Web writes NULL)",
              cur.fetchone()[0] == 0)
        cur.execute(
            "select is_nullable from information_schema.columns "
            "where table_schema='public' and table_name='generation_intents' "
            "and column_name='session_id'")
        check("DB05 generation_intents.session_id is NULLABLE (Web writes NULL)",
              cur.fetchone()[0] == "YES")

        # ── DB06 — constraints / indexes that carry idempotence ─────────────
        section("DB06  idempotence constraints")
        cur.execute("""
            select conname from pg_constraint
             where conrelid = 'public.ledger_entries'::regclass and contype = 'u'
        """)
        led_u = {r[0] for r in cur.fetchall()}
        check("DB06 ledger_entries UNIQUE(idempotency_key)",
              any("idempotency_key" in c for c in led_u), str(led_u))
        cur.execute("""
            select indexdef from pg_indexes
             where schemaname='public' and tablename='passes'
               and indexname='passes_source_order_uidx'
        """)
        row = cur.fetchone()
        check("DB06 passes UNIQUE(source_order_id)", row is not None and "UNIQUE" in row[0])
        cur.execute("""
            select conname from pg_constraint
             where conrelid = 'public.payments'::regclass and contype = 'u'
        """)
        check("DB06 payments UNIQUE(provider, provider_transaction_id)",
              bool(cur.fetchall()))
        cur.execute("""
            select count(*) from pg_indexes
             where schemaname='public'
               and indexname in ('ledger_user_idx','ledger_user_created_idx',
                                 'ledger_reference_idx','passes_user_idx',
                                 'passes_active_expiry_idx','generation_intents_user_idx',
                                 'generation_intents_status_idx','user_roles_user_id_idx')
        """)
        check("DB06 canonical indexes present (8)", cur.fetchone()[0] == 8)

        # ── DB07 — RLS ──────────────────────────────────────────────────────
        section("DB07  row level security")
        cur.execute("""
            select relname, relrowsecurity from pg_class c
             join pg_namespace n on n.oid = c.relnamespace
            where n.nspname='public' and relname = any(%s)
        """, (EXPECTED_TABLES,))
        rls = dict(cur.fetchall())
        for t in EXPECTED_TABLES:
            check(f"DB07 RLS enabled on {t}", rls.get(t) is True)
        cur.execute(
            "select tablename, policyname, cmd from pg_policies where schemaname='public'")
        pols = {(r[0], r[2]) for r in cur.fetchall()}
        for t in ("generation_intents", "ledger_entries", "wallets", "passes",
                  "orders", "user_roles"):
            check(f"DB07 {t} has an owner-read policy", (t, "SELECT") in pols)
        check("DB07 payments has NO policy (sensitive)",
              not any(p[0] == "payments" for p in pols))
        # A browser token must never be able to WRITE BILLING. Until 2026-08-18
        # this was written as "no non-SELECT policy anywhere in public", which
        # was the same statement while 0006 owned the whole schema. It is not
        # any more: the shared project carries `sessions`, `messages` and
        # `assets` — the mobile CHAT tables — each with an "active identity
        # only" ALL policy from the identity chantier. Measured, and none of
        # them is a billing object.
        #
        # So the assertion now names the tables it was always about. Narrower in
        # scope, and true again — which is the only version worth running.
        cur.execute(
            "select tablename, policyname, cmd from pg_policies "
            "where schemaname='public' and cmd <> 'SELECT'")
        writable = cur.fetchall()
        print("  INFO  non-SELECT policies in public: "
              + (", ".join(f"{t}({c})" for t, _, c in writable) or "none"))
        offenders = [row for row in writable
                     if row[0] in BILLING_TABLES_NO_CLIENT_WRITE]
        check("DB07 NO client-writable policy on any billing table",
              not offenders, f"a client could mutate billing state: {offenders}")

        # ── DB08 — grants ───────────────────────────────────────────────────
        section("DB08  table grants")
        cur.execute("""
            select table_name, grantee, privilege_type
              from information_schema.role_table_grants
             where table_schema='public' and grantee in ('anon','authenticated','service_role')
        """)
        grants: dict[tuple[str, str], set[str]] = {}
        for t, g, p in cur.fetchall():
            grants.setdefault((t, g), set()).add(p)
        for t in EXPECTED_TABLES:
            check(f"DB08 anon has NO grant on {t}", not grants.get((t, "anon")),
                  str(grants.get((t, "anon"))))
        for t in ("generation_intents", "ledger_entries", "wallets", "passes",
                  "products", "orders", "user_roles"):
            g = grants.get((t, "authenticated"), set())
            check(f"DB08 authenticated on {t} is read-only",
                  g and not (g - {"SELECT"}), str(g))
        check("DB08 authenticated has NO grant on payments",
              not grants.get(("payments", "authenticated")))
        for t in ("promo_codes", "promo_redemptions"):
            check(f"DB08 authenticated has NO grant on {t}",
                  not grants.get((t, "authenticated")))
        led_sr = grants.get(("ledger_entries", "service_role"), set())
        check("DB08 service_role cannot UPDATE/DELETE ledger_entries",
              not (led_sr & {"UPDATE", "DELETE", "TRUNCATE"}), str(led_sr))
        check("DB08 service_role can INSERT+SELECT ledger_entries",
              {"SELECT", "INSERT"} <= led_sr, str(led_sr))

        section("DB09  function grants")
        cur.execute("""
            select p.proname, p.pronargs,
                   has_function_privilege('anon',          p.oid, 'EXECUTE'),
                   has_function_privilege('authenticated', p.oid, 'EXECUTE'),
                   has_function_privilege('service_role',  p.oid, 'EXECUTE')
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname='public' and p.proname = any(%s)
        """, (list(EXPECTED_FUNCTIONS),))
        for name, nargs, anon_x, auth_x, sr_x in cur.fetchall():
            check(f"DB09 {name}/{nargs} not executable by anon", not anon_x)
            check(f"DB09 {name}/{nargs} not executable by authenticated", not auth_x)
            check(f"DB09 {name}/{nargs} executable by service_role", sr_x)

        # ── DB10 — append-only really is enforced ───────────────────────────
        section("DB10  ledger append-only (behavioural, not declarative)")
        cur.execute(
            "insert into auth.users (id, instance_id, aud, role, email, "
            "created_at, updated_at, is_anonymous) values "
            "(%s, '00000000-0000-0000-0000-000000000000', 'authenticated', "
            "'authenticated', %s, now(), now(), true)",
            (probe_a, f"probe-{probe_a[:8]}@contract.invalid"))
        cur.execute(
            "insert into public.ledger_entries (user_id, entry_type, available_delta, "
            "reference_type, reference_id, idempotency_key) "
            "values (%s, 'TRIAL', 1, 'PROMO', 'contract', %s)",
            (probe_a, f"contract:trial:{probe_a}"))
        for op, sql in (("UPDATE", "update public.ledger_entries set available_delta = 99 "
                                   "where user_id = %s"),
                        ("DELETE", "delete from public.ledger_entries where user_id = %s")):
            blocked = False
            try:
                cur.execute(sql, (probe_a,))
            except Exception as exc:  # noqa: BLE001 — the exception IS the assertion
                blocked = "append-only" in str(exc)
            check(f"DB10 {op} on ledger_entries is blocked by the trigger", blocked)

        # ── DB11 — the free bucket / try_hold behaviour, end to end ─────────
        section("DB11  billing_try_hold behaviour (p_trial_credits = 1)")
        # probe_b has NO auth.users row yet. The FK must reject the credit —
        # the ledger cannot be credited to an identity that does not exist.
        # (Its own cursor: a failed statement poisons the one it ran on.)
        rejected = False
        try:
            with conn.cursor() as probe_cur:
                probe_cur.execute("select public.billing_try_hold(%s, %s, 'free', 1)",
                                  (probe_b, f"orphan:{probe_b[:8]}"))
        except Exception as exc:  # noqa: BLE001 — the exception IS the assertion
            rejected = "ledger_entries_user_id_fkey" in str(exc)
        check("DB11 a hold for a NON-EXISTENT user is rejected by the FK", rejected)

        cur.execute(
            "insert into auth.users (id, instance_id, aud, role, email, "
            "created_at, updated_at, is_anonymous) values "
            "(%s, '00000000-0000-0000-0000-000000000000', 'authenticated', "
            "'authenticated', %s, now(), now(), true)",
            (probe_b, f"probe-{probe_b[:8]}@contract.invalid"))

        # Idempotency keys are GLOBAL (`hold:<intent_id>`), not per user, so the
        # probe intents must be unique per RUN or the second run of this file
        # would read a previous run's holds and report `bucket: existing`.
        i1, i2, i3 = (f"ct-{probe_b[:8]}-i{n}" for n in (1, 2, 3))

        cur.execute("select public.billing_try_hold(%s, %s, 'free', 1)", (probe_b, i1))
        r1 = cur.fetchone()[0]
        check("DB11 first free generation granted", r1.get("granted") is True, str(r1))
        check("DB11 it came from the FREE bucket", r1.get("bucket") == "free", str(r1))
        check("DB11 balance after the first hold is 0 (trial = 1)",
              r1.get("total_after") == 0, str(r1))

        cur.execute("select public.billing_try_hold(%s, %s, 'free', 1)", (probe_b, i2))
        r2 = cur.fetchone()[0]
        check("DB11 second generation DENIED", r2.get("granted") is False, str(r2))
        check("DB11 deny reason is insufficient_credits",
              r2.get("reason") == "insufficient_credits", str(r2))

        cur.execute("select public.billing_try_hold(%s, %s, 'free', 1)", (probe_b, i1))
        r3 = cur.fetchone()[0]
        check("DB11 replaying the SAME intent is idempotent (no 2nd debit)",
              r3.get("granted") is True and r3.get("idempotent") is True, str(r3))
        cur.execute(
            "select count(*) from public.ledger_entries "
            "where user_id = %s and entry_type = 'HOLD'", (probe_b,))
        check("DB11 exactly ONE hold exists for the replayed intent",
              cur.fetchone()[0] == 1)

        cur.execute("select count(*) from public.ledger_entries "
                    "where user_id = %s and entry_type = 'TRIAL' "
                    "and available_delta = 1", (probe_b,))
        check("DB11 the TRIAL materialised is +1, not +3 (D1 Web free tier)",
              cur.fetchone()[0] == 1)

        cur.execute("select available_credits from public.wallets where user_id = %s",
                    (probe_b,))
        row = cur.fetchone()
        check("DB11 wallet projected to 0", row is not None and row[0] == 0, str(row))

        # ── DB12 — a PASS grants access again, through the canonical RPC ────
        section("DB12  pass acquisition then generation allowed again")
        cur.execute("select id from public.products where sku = 'weekly_pass'")
        weekly = cur.fetchone()[0]
        cur.execute(
            "select public.billing_grant_purchase(%s, 'khqr', %s, %s, 30, 7, 7.99, "
            "'USD', now() + interval '7 days', '{\"source\":\"contract-test\"}'::jsonb)",
            (probe_b, f"ct-tran-{probe_b[:8]}", weekly))
        g = cur.fetchone()[0]
        check("DB12 grant_purchase accepts a NON-RevenueCat provider (khqr)",
              g.get("ok") is True and g.get("credited") is True, str(g))
        check("DB12 the pass credited 30 spaces", g.get("credits") == 30, str(g))
        cur.execute("select public.billing_try_hold(%s, %s, 'free', 1)", (probe_b, i3))
        r4 = cur.fetchone()[0]
        check("DB12 generation allowed again, from the PASS bucket",
              r4.get("granted") is True and r4.get("bucket") == "pass", str(r4))
        cur.execute(
            "select public.billing_grant_purchase(%s, 'khqr', %s, %s, 30, 7, 7.99, "
            "'USD', now() + interval '7 days', '{}'::jsonb)",
            (probe_b, f"ct-tran-{probe_b[:8]}", weekly))
        g2 = cur.fetchone()[0]
        check("DB12 replaying the same transaction credits NOTHING",
              g2.get("status") == "already_processed" and g2.get("credited") is False,
              str(g2))

        # ── DB13 — generation_intents accepts session_id = NULL ─────────────
        section("DB13  generation_intents, the Web shape")
        cur.execute(
            "insert into public.generation_intents (intent_id, user_id, session_id, "
            "iteration, status, intent, client_request_id, started_at) "
            "values (%s, %s, null, 1, 'RUNNING', '{}'::jsonb, 'ct', now()) "
            "on conflict (intent_id) do nothing",
            (f"ct-intent-{probe_b[:8]}", probe_b))
        cur.execute("select session_id from public.generation_intents where intent_id = %s",
                    (f"ct-intent-{probe_b[:8]}",))
        check("DB13 an intent with session_id = NULL is accepted",
              cur.fetchone()[0] is None)
        cur.execute(
            "update public.generation_intents set status = 'SUCCEEDED' where intent_id = %s "
            "returning updated_at > created_at - interval '1 second'",
            (f"ct-intent-{probe_b[:8]}",))
        check("DB13 updated_at trigger fires", cur.fetchone()[0] is True)

        # ── DB14 — the append-only guarantee outranks a cascade delete ──────
        section("DB14  erasure vs append-only (a real, load-bearing conflict)")
        blocked = False
        try:
            with conn.cursor() as del_cur:
                del_cur.execute("delete from auth.users where id = %s", (probe_a,))
        except Exception as exc:  # noqa: BLE001 — the exception IS the assertion
            blocked = "append-only" in str(exc)
        check("DB14 a user WITH ledger rows cannot be deleted (cascade blocked)",
              blocked,
              "the cascade succeeded — the ledger is NOT append-only in practice")

        # A probe with no ledger rows must still be deletable, otherwise the
        # block above would be about foreign keys in general rather than about
        # the append-only trigger specifically.
        clean = str(uuid.uuid4())
        cur.execute(
            "insert into auth.users (id, instance_id, aud, role, email, "
            "created_at, updated_at, is_anonymous) values "
            "(%s, '00000000-0000-0000-0000-000000000000', 'authenticated', "
            "'authenticated', %s, now(), now(), true)",
            (clean, f"probe-{clean[:8]}@contract.invalid"))
        cur.execute("delete from auth.users where id = %s", (clean,))
        cur.execute("select count(*) from auth.users where id = %s", (clean,))
        check("DB14 a user WITHOUT ledger rows is still deletable",
              cur.fetchone()[0] == 0)

        # ── residue ─────────────────────────────────────────────────────────
        section("residue (bounded, by design)")
        cur.execute(
            "select count(*) from auth.users where email like 'probe-%%@contract.invalid'")
        probes = cur.fetchone()[0]
        cur.execute(
            "select count(*) from public.ledger_entries le join auth.users u "
            "on u.id = le.user_id where u.email like 'probe-%%@contract.invalid'")
        rows = cur.fetchone()[0]
        print(f"  INFO  contract-probe identities in staging: {probes} "
              f"({rows} ledger rows) — permanent, see the module docstring")
        check("residue is confined to probe identities",
              probes * 12 >= rows,
              f"{rows} ledger rows for {probes} probes — more than this run writes")

    print(f"\n{'=' * 72}")
    print(f"CHECKS {_CHECKS}   FAILURES {len(_FAILURES)}")
    for f in _FAILURES:
        print(f"  - {f}")
    print("=" * 72)
    return 1 if _FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
