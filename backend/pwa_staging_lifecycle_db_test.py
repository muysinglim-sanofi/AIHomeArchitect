"""Durable generation lifecycle — against the REAL staging Postgres.

Everything here runs the actual `pwa_staging.claim_generation` /
`complete_generation` / `fail_generation` functions, under the actual RLS
policies, as an actual `authenticated` role. No fake claim table: the point is
to prove that Postgres — not a Python dictionary — elects one winner, and that
the decision outlives any single backend process.

No provider call is made. The expensive creative step is never involved: what
is measured is who is ALLOWED to make it.

Rows are created under throwaway user ids and deleted at the end. No user
project, vision or account is read, altered or removed.

Run:  PYTHONIOENCODING=utf-8 python pwa_staging_lifecycle_db_test.py
"""
from __future__ import annotations

import uuid

from pwa_staging_db import redacted, resolve_staging_url, staging_connection

_passed: list[str] = []
_failed: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (_passed if ok else _failed).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else f'  {detail}'}")


# ── acting as a real authenticated user ─────────────────────────────────────


def _as_user(cur, user_id: str) -> None:
    """Become `authenticated` with this uid, the way PostgREST does.

    `auth.uid()` reads the `sub` claim, so setting the claims and the role is
    what makes the RLS policies and the SECURITY INVOKER functions behave
    exactly as they will for a real browser session.
    """
    cur.execute("select set_config('request.jwt.claims', %s, true)",
                (f'{{"sub":"{user_id}","role":"authenticated"}}',))
    cur.execute("set local role authenticated")


def _claim(cur, user_id: str, key: str, project: str,
           action: str = "initial", parent=None):
    _as_user(cur, user_id)
    cur.execute(
        "select won, state, result_vision_id, error_code "
        "from pwa_staging.claim_generation(%s, %s, %s, %s)",
        (key, project, action, parent),
    )
    return cur.fetchone()


def main() -> int:
    url = resolve_staging_url()
    print(f"target: {redacted(url)}")
    print("(no provider call is made anywhere in this file)\n")

    user_a = str(uuid.uuid4())
    user_b = str(uuid.uuid4())
    project = str(uuid.uuid4())
    created_keys: list[str] = []

    def k(name: str) -> str:
        key = f"dblife-{name}-{uuid.uuid4().hex[:8]}"
        created_keys.append(key)
        return key

    try:
        # DBLIFE01 — a fresh claim wins and is PROCESSING.
        with staging_connection() as conn:
            with conn.cursor() as cur:
                key = k("01")
                won, state, res, err = _claim(cur, user_a, key, project)
                check("DBLIFE01: a new claim wins and is PROCESSING",
                      won is True and state == "PROCESSING", f"{won}/{state}")
            conn.commit()

        # DBLIFE02 — two INDEPENDENT connections, same identity: one winner.
        key = k("02")
        with staging_connection() as c1, staging_connection() as c2:
            with c1.cursor() as cur1:
                w1, s1, _, _ = _claim(cur1, user_a, key, project)
            c1.commit()
            with c2.cursor() as cur2:
                w2, s2, _, _ = _claim(cur2, user_a, key, project)
            c2.commit()
            check("DBLIFE02: two independent callers -> exactly one winner",
                  [w1, w2].count(True) == 1, f"{w1}/{w2}")
            check("DBLIFE03: the loser is told PROCESSING, so it must not render",
                  s2 == "PROCESSING" and w2 is False, f"{w2}/{s2}")

        # DBLIFE04 — once COMPLETED, a duplicate recovers the result.
        key = k("04")
        vision = str(uuid.uuid4())
        with staging_connection() as conn:
            with conn.cursor() as cur:
                _claim(cur, user_a, key, project)
                _as_user(cur, user_a)
                cur.execute("select pwa_staging.complete_generation(%s, %s)",
                            (key, vision))
            conn.commit()
        with staging_connection() as conn:  # a different connection entirely
            with conn.cursor() as cur:
                won, state, res, err = _claim(cur, user_a, key, project)
            conn.commit()
        check("DBLIFE04: a COMPLETED duplicate does NOT win",
              won is False and state == "COMPLETED", f"{won}/{state}")
        check("DBLIFE04: it recovers the existing result",
              str(res) == vision, f"{res}")

        # DBLIFE05 — a FAILED claim is retryable.
        key = k("05")
        with staging_connection() as conn:
            with conn.cursor() as cur:
                _claim(cur, user_a, key, project)
                _as_user(cur, user_a)
                cur.execute(
                    "select pwa_staging.fail_generation(%s, %s, %s)",
                    (key, "ENGINE_UNAVAILABLE", False))
            conn.commit()
        with staging_connection() as conn:
            with conn.cursor() as cur:
                won, state, _, err = _claim(cur, user_a, key, project)
            conn.commit()
        check("DBLIFE05: a FAILED claim is re-claimable",
              won is True and state == "PROCESSING", f"{won}/{state}")
        check("DBLIFE05: the previous error is cleared", err is None, f"{err}")

        # DBLIFE06/13 — restart-equivalent: nothing in memory, only the row.
        key = k("06")
        with staging_connection() as conn:
            with conn.cursor() as cur:
                _claim(cur, user_a, key, project)
            conn.commit()
        # A brand-new process would start with an empty map; the ONLY thing
        # carried over is the database row.
        with staging_connection() as conn:
            with conn.cursor() as cur:
                won, state, _, _ = _claim(cur, user_a, key, project)
            conn.commit()
        check("DBLIFE06/13: after a restart the claim still blocks a second render",
              won is False and state == "PROCESSING", f"{won}/{state}")

        # DBLIFE07 — an F5 replay is the same shape: same key, new connection.
        key = k("07")
        with staging_connection() as conn:
            with conn.cursor() as cur:
                _claim(cur, user_a, key, project)
            conn.commit()
        with staging_connection() as conn:
            with conn.cursor() as cur:
                won, _, _, _ = _claim(cur, user_a, key, project)
            conn.commit()
        check("DBLIFE07: an F5 replay cannot start a second render", won is False)

        # DBLIFE10 — ownership isolation: user B cannot see or take user A's claim.
        key = k("10")
        with staging_connection() as conn:
            with conn.cursor() as cur:
                _claim(cur, user_a, key, project)
            conn.commit()
        with staging_connection() as conn:
            with conn.cursor() as cur:
                _as_user(cur, user_b)
                cur.execute(
                    "select count(*) from pwa_staging.pwa_generation_claims "
                    "where idempotency_key = %s", (key,))
                visible = cur.fetchone()[0]
                # B claiming the same KEY gets its OWN row — never A's.
                won_b, state_b, _, _ = _claim(cur, user_b, key, project)
            conn.commit()
        check("DBLIFE10: another user cannot SEE the claim", visible == 0, f"{visible}")
        check("DBLIFE10: another user gets its own independent claim",
              won_b is True, f"{won_b}")

        # DBLIFE11 — a different identity is independent.
        with staging_connection() as conn:
            with conn.cursor() as cur:
                won, _, _, _ = _claim(cur, user_a, k("11"), project)
            conn.commit()
        check("DBLIFE11: a different idempotency identity wins independently",
              won is True)

        # DBLIFE12 — three concurrent connections, one winner. Real contention:
        # all three claim before any commits.
        # Three real HTTP requests = three threads, each with its own connection
        # and its own short transaction that COMMITS — which is what lets the
        # losers observe the winner's row instead of blocking on it forever.
        key = k("12")
        import threading  # noqa: PLC0415

        import psycopg  # noqa: PLC0415

        url = resolve_staging_url()
        barrier = threading.Barrier(3)
        results: list[bool] = []
        lock = threading.Lock()

        def one_caller() -> None:
            with psycopg.connect(url, connect_timeout=20) as c:
                with c.cursor() as cur:
                    barrier.wait(timeout=20)  # start together
                    won, _, _, _ = _claim(cur, user_a, key, project)
                c.commit()
            with lock:
                results.append(won)

        threads = [threading.Thread(target=one_caller) for _ in range(3)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=45)

        check("DBLIFE12: three concurrent callers -> exactly ONE render allowed",
              results.count(True) == 1 and len(results) == 3, f"{results}")

    finally:
        # Remove ONLY the rows this file created.
        with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
            cur.execute(
                "delete from pwa_staging.pwa_generation_claims "
                "where owner_user_id = any(%s)", ([user_a, user_b],))
            print(f"\ncleanup: {cur.rowcount} technical claim rows removed "
                  f"(no user data touched)")

    print(f"\n{'=' * 60}")
    if _failed:
        print(f"ECHECS: {len(_failed)} / {len(_passed) + len(_failed)}")
        for f in _failed:
            print(f"  - {f}")
        return 1
    print(f"TOUS LES TESTS PASSENT ({len(_passed)} assertions, DB reelle)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
