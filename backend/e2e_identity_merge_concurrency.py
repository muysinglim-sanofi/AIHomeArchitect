"""E2E concurrence — identity_claim_and_merge (Commit 2, Unified Identity).

Prouve ce qu'un unique script SQL en ROLLBACK ne peut pas prouver : deux appels
CONCURRENTS (2 connexions distinctes) sont sérialisés par l'advisory lock du RPC.

Scénarios :
  A. Même ticket, même B     → un seul merge_id, une seule ligne, même statut,
                               exactement une session déplacée.
  B. Deux tickets, même A→B  → un gagnant (merge réel) + un perdant
                               (conflict/duplicate_merge_attempt) dont
                               metadata.existing_merge_id == merge_id du gagnant,
                               exactement une session déplacée.

SÉCURITÉ — ne tourne QUE sur une base de TEST JETABLE, avec des comptes DÉDIÉS et VIERGES :
  export IDENTITY_TEST_DATABASE_URL="postgresql://…/staging_jetable"
  export IDENTITY_TEST_EXPECTED_HOST="<host EXACT attendu du DSN>"   # doit matcher
  export IDENTITY_TEST_A="<uuid utilisateur ANONYME staging, VIERGE>"
  export IDENTITY_TEST_B="<uuid utilisateur PERMANENT staging, VIERGE>"
  export IDENTITY_TEST_CONFIRM="THROWAWAY-STAGING"                   # confirmation forte
  python backend/e2e_identity_merge_concurrency.py

Refuse si : confirmation forte absente, host du DSN ≠ host attendu, ou A/B non vierges.
Le RPC COMMIT (les locks xact ne se prouvent qu'avec de vraies transactions concurrentes).
Le cleanup NE tourne JAMAIS si la garde de vacuité échoue, si aucune fixture n'a été créée,
ou tant qu'un thread RPC est encore vivant. Les connexions des workers bloqués sont annulées
(cancel) puis fermées avant tout cleanup. Il ne supprime que les IDs EXACTS qu'il a créés.
"""
from __future__ import annotations

import os
import sys
import threading
import uuid
from urllib.parse import urlparse

CONFIRM_PHRASE = "THROWAWAY-STAGING"
STMT_TIMEOUT = "15s"
BARRIER_TIMEOUT = 15.0   # s
JOIN_TIMEOUT = 45.0      # s (> STMT_TIMEOUT → un thread bloqué finit en erreur avant le join)
CANCEL_JOIN_TIMEOUT = 15.0  # s (re-join borné après cancel)

# Tables où A et B doivent être VIERGES avant le test.
_EMPTINESS = [
    ("account_state",          "user_id"),
    ("identity_merge_tickets", "from_user_id"),
    ("sessions",               "user_id"),
    ("usage_log",              "user_id"),
    ("generation_intents",     "user_id"),
    ("device_tokens",          "user_id"),
    ("promo_redemptions",      "user_id"),
    ("passes",                 "user_id"),
    ("ledger_entries",         "user_id"),
    ("orders",                 "user_id"),
]

try:
    import psycopg  # psycopg 3
    _V3 = True
except ImportError:  # pragma: no cover
    try:
        import psycopg2 as psycopg  # type: ignore
        _V3 = False
    except ImportError:
        print("ERREUR: installez psycopg (v3) ou psycopg2.", file=sys.stderr)
        sys.exit(2)


def _env(name: str) -> str:
    v = os.environ.get(name, "").strip()
    if not v:
        print(f"ERREUR: variable d'environnement manquante: {name}", file=sys.stderr)
        sys.exit(2)
    return v


def _connect(dsn: str):
    # connect_timeout borne l'ÉTABLISSEMENT de la connexion (statement_timeout n'agit qu'après).
    if _V3:
        conn = psycopg.connect(dsn, autocommit=True, connect_timeout=10)
    else:
        conn = psycopg.connect(dsn, connect_timeout=10)
        conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute(f"set statement_timeout = '{STMT_TIMEOUT}'")
    return conn


# ── appel RPC concurrent : une connexion par thread, enregistrée pour cancel/close ────
_conn_lock = threading.Lock()


def _call_rpc(dsn: str, ticket: str, b: str, barrier: threading.Barrier,
              out: dict, key: str, conns: dict):
    conn = None
    try:
        conn = _connect(dsn)
        with _conn_lock:
            conns[key] = conn
        with conn.cursor() as cur:
            try:
                barrier.wait(timeout=BARRIER_TIMEOUT)
            except threading.BrokenBarrierError:
                out[key] = {"error": "barrier_timeout"}
                return
            cur.execute(
                "select merge_id, status, failure_code, metadata "
                "from public.identity_claim_and_merge(%s, %s)",
                (ticket, b),
            )
            mid, status, fc, meta = cur.fetchone()
            out[key] = {"merge_id": str(mid), "status": status,
                        "failure_code": fc, "metadata": meta or {}}
    except Exception as exc:  # noqa: BLE001
        out[key] = {"error": f"{type(exc).__name__}: {exc}"}
    finally:
        with _conn_lock:
            conns.pop(key, None)
        if conn is not None:
            try:
                conn.close()
            except Exception:  # noqa: BLE001
                pass


def _run_pair(dsn: str, b: str, t1: str, t2: str) -> dict:
    """Lance 2 workers NON-daemon. Si l'un reste vivant : cancel() sa connexion,
    re-join borné, fermeture ; s'il ne finit toujours pas → échec DUR, aucun cleanup."""
    barrier = threading.Barrier(2)
    out: dict = {}
    conns: dict = {}
    threads = [
        threading.Thread(target=_call_rpc, args=(dsn, t1, b, barrier, out, "r1", conns)),
        threading.Thread(target=_call_rpc, args=(dsn, t2, b, barrier, out, "r2", conns)),
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=JOIN_TIMEOUT)

    if any(t.is_alive() for t in threads):
        # annuler les requêtes des connexions encore actives
        with _conn_lock:
            for c in list(conns.values()):
                try:
                    c.cancel()
                except Exception:  # noqa: BLE001
                    pass
        for t in threads:
            t.join(timeout=CANCEL_JOIN_TIMEOUT)

    if any(t.is_alive() for t in threads):
        # fermeture forcée des connexions restantes puis dernier join
        with _conn_lock:
            for c in list(conns.values()):
                try:
                    c.close()
                except Exception:  # noqa: BLE001
                    pass
        for t in threads:
            t.join(timeout=CANCEL_JOIN_TIMEOUT)

    if any(t.is_alive() for t in threads):
        raise RuntimeError("workers RPC non terminés après cancel+close — abandon SANS cleanup")
    return out


# ── garde-fous + fixtures + cleanup (connexion privilégiée) ───────────────────

def _guard_or_die(dsn: str):
    if os.environ.get("IDENTITY_TEST_CONFIRM") != CONFIRM_PHRASE:
        print(f"REFUS: IDENTITY_TEST_CONFIRM doit valoir exactement '{CONFIRM_PHRASE}' "
              "(base JETABLE uniquement).", file=sys.stderr)
        sys.exit(2)
    expected = _env("IDENTITY_TEST_EXPECTED_HOST")
    host = (urlparse(dsn).hostname or "").strip()
    if host.lower() != expected.lower():
        print(f"REFUS: host du DSN ('{host}') ≠ IDENTITY_TEST_EXPECTED_HOST ('{expected}').",
              file=sys.stderr)
        sys.exit(2)


def _verify_users_and_empty(cur, a: str, b: str):
    """Lève SystemExit si A/B invalides ou NON vierges. N'écrit rien."""
    cur.execute("select is_anonymous from auth.users where id = %s", (a,))
    r = cur.fetchone()
    if not r or r[0] is not True:
        raise SystemExit("A doit exister et être anonyme (is_anonymous=true)")
    cur.execute("select is_anonymous from auth.users where id = %s", (b,))
    r = cur.fetchone()
    if not r or r[0] is True:
        raise SystemExit("B doit exister et être permanent (is_anonymous=false)")
    for table, col in _EMPTINESS:
        cur.execute(f"select count(*) from public.{table} where {col} in (%s, %s)", (a, b))
        if cur.fetchone()[0]:
            raise SystemExit(f"A/B non vierges : lignes dans public.{table} — "
                             "utilise des comptes staging DÉDIÉS et vides")
    cur.execute(
        "select count(*) from public.identity_merges "
        "where from_user_id in (%s,%s) or to_user_id in (%s,%s)", (a, b, a, b))
    if cur.fetchone()[0]:
        raise SystemExit("A/B non vierges : lignes existantes dans identity_merges")


def _mk_session(cur, a: str, title: str) -> str:
    cur.execute(
        "insert into public.sessions(user_id, title) values (%s, %s) returning id", (a, title))
    return str(cur.fetchone()[0])


def _mk_ticket(cur, a: str, ticket: str):
    cur.execute(
        "insert into public.identity_merge_tickets(ticket_hash, from_user_id, expires_at) "
        "values (%s, %s, now() + interval '15 min')", (ticket, a))


def _cleanup(cur, a: str, b: str, tickets: list[str], session_ids: list[str]):
    """Supprime UNIQUEMENT ce que cette exécution a créé (IDs exacts)."""
    if tickets:
        cur.execute("delete from public.identity_merges where ticket_hash = any(%s)", (tickets,))
        cur.execute("delete from public.identity_merge_tickets where ticket_hash = any(%s)", (tickets,))
    if session_ids:
        cur.execute("delete from public.sessions where id = any(%s::uuid[])", (session_ids,))
    # A ET B : la garde de vacuité a prouvé qu'ils n'avaient AUCUNE ligne account_state avant.
    cur.execute("delete from public.account_state where user_id in (%s, %s)", (a, b))


def main() -> int:
    dsn = _env("IDENTITY_TEST_DATABASE_URL")
    a = _env("IDENTITY_TEST_A")
    b = _env("IDENTITY_TEST_B")
    _guard_or_die(dsn)

    run_tag = f"__identity_e2e_{uuid.uuid4().hex[:8]}__"
    admin = _connect(dsn)
    failures: list[str] = []
    guard_passed = False
    fixtures_started = False
    stuck = False
    tickets: list[str] = []
    session_ids: list[str] = []
    try:
        with admin.cursor() as cur:
            _verify_users_and_empty(cur, a, b)   # lève SystemExit si non vierges → PAS de cleanup
        guard_passed = True

        # ── Scénario A : même ticket ──────────────────────────────────────────
        ta = f"e2e-same-{uuid.uuid4().hex[:8]}"
        tickets.append(ta)
        fixtures_started = True
        with admin.cursor() as cur:
            sa_sid = _mk_session(cur, a, run_tag)
            session_ids.append(sa_sid)
            _mk_ticket(cur, a, ta)
        out = _run_pair(dsn, b, ta, ta)
        r1, r2 = out.get("r1", {}), out.get("r2", {})
        with admin.cursor() as cur:
            cur.execute("select count(*) from public.identity_merges where ticket_hash = %s", (ta,))
            n_rows = cur.fetchone()[0]
            cur.execute("select count(*) from public.sessions where user_id = %s and title = %s",
                        (b, run_tag))
            n_moved = cur.fetchone()[0]
        if "error" in r1 or "error" in r2:
            failures.append(f"A: erreur inattendue r1={r1} r2={r2}")
        elif r1.get("merge_id") != r2.get("merge_id"):
            failures.append(f"A: merge_id différents r1={r1} r2={r2}")
        elif r1.get("status") != r2.get("status"):
            failures.append(f"A: statuts différents r1={r1} r2={r2}")
        elif n_rows != 1:
            failures.append(f"A: {n_rows} lignes identity_merges (attendu 1)")
        elif n_moved != 1:
            failures.append(f"A: {n_moved} sessions déplacées (attendu 1)")
        else:
            print(f"Scénario A OK — merge_id={r1['merge_id']} status={r1['status']} · 1 ligne · 1 session")

        # ── ISOLATION : nettoyer le scénario A puis reprouver la vacuité AVANT B ──────
        # (A a réellement fusionné : ligne bloquante + A fermé. Sans cleanup, les 2 appels de B
        #  trouveraient ce merge bloquant et retourneraient tous deux duplicate_merge_attempt.)
        with admin.cursor() as cur:
            _cleanup(cur, a, b, [ta], [sa_sid])
        session_ids.remove(sa_sid)  # déjà supprimée
        tickets.remove(ta)
        with admin.cursor() as cur:
            _verify_users_and_empty(cur, a, b)   # prouve que A/B sont redevenus vierges

        # ── Scénario B : deux tickets, même A→B ───────────────────────────────
        t1 = f"e2e-t1-{uuid.uuid4().hex[:8]}"
        t2 = f"e2e-t2-{uuid.uuid4().hex[:8]}"
        tickets += [t1, t2]
        with admin.cursor() as cur:
            sb_sid = _mk_session(cur, a, run_tag)
            session_ids.append(sb_sid)
            _mk_ticket(cur, a, t1)
            _mk_ticket(cur, a, t2)
        out = _run_pair(dsn, b, t1, t2)
        r1, r2 = out.get("r1", {}), out.get("r2", {})
        winners = [r for r in (r1, r2)
                   if r.get("status") in ("revocation_pending", "billing_reconciliation_pending")]
        dups = [r for r in (r1, r2) if r.get("failure_code") == "duplicate_merge_attempt"]
        with admin.cursor() as cur:
            cur.execute("select count(*) from public.sessions where user_id = %s and title = %s",
                        (b, run_tag))
            n_moved = cur.fetchone()[0]   # A ayant été nettoyé : EXACTEMENT 1 attendu
        if "error" in r1 or "error" in r2:
            failures.append(f"B: erreur inattendue r1={r1} r2={r2}")
        elif len(winners) != 1 or len(dups) != 1:
            failures.append(f"B: attendu 1 gagnant + 1 duplicate, r1={r1} r2={r2}")
        elif str(dups[0].get("metadata", {}).get("existing_merge_id")) != winners[0]["merge_id"]:
            failures.append(f"B: existing_merge_id ({dups[0].get('metadata')}) ≠ gagnant "
                            f"({winners[0]['merge_id']})")
        elif n_moved != 1:
            failures.append(f"B: {n_moved} sessions déplacées (attendu exactement 1)")
        else:
            print(f"Scénario B OK — gagnant={winners[0]['status']} · perdant=duplicate_merge_attempt "
                  f"(existing_merge_id={winners[0]['merge_id']}) · 1 session déplacée")
    except RuntimeError as exc:
        stuck = True
        failures.append(f"CONCURRENCE BLOQUÉE: {exc}")
    finally:
        # cleanup UNIQUEMENT si la garde a réussi, des fixtures ont été créées, et aucun thread n'est bloqué
        if guard_passed and fixtures_started and not stuck:
            try:
                with admin.cursor() as cur:
                    _cleanup(cur, a, b, tickets, session_ids)
            except Exception as exc:  # noqa: BLE001
                print(f"AVERTISSEMENT: cleanup final partiel: {exc}", file=sys.stderr)
        elif stuck:
            print("CLEANUP IGNORÉ (thread bloqué) — jeter/réinitialiser la base de test manuellement.",
                  file=sys.stderr)
        else:
            print("CLEANUP IGNORÉ (garde échouée / aucune fixture) — aucune donnée touchée.",
                  file=sys.stderr)
        admin.close()

    if failures:
        print("\nÉCHECS :", file=sys.stderr)
        for f in failures:
            print("  - " + f, file=sys.stderr)
        return 1
    print("\nTOUS LES SCÉNARIOS DE CONCURRENCE PASSENT.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
