"""Direct Postgres access to the PWA STAGING project — operator tooling.

Why this exists
---------------
`0002`/`0003` were applied by hand through the SQL Editor. That is fine once,
and unworkable as a habit: every schema step then needs a human, and the code
that depends on it cannot be verified against the real database.

This module is the small, auditable seam that lets migrations be applied and
verified from here. It is NOT imported by the API: nothing in the request path
touches it, and the connection string never leaves this process.

Safety
------
The target is proved before the caller gets a connection, and proved against
the SAME string that will be used — not a separate check that could drift:

  * the URL must carry the authorized staging project ref;
  * it must NOT carry the production ref;
  * `backend/.env` (production) is never read;
  * the resolved host is re-checked after parsing.

Any doubt raises before a cursor exists. Nothing here prints a password, and
`redacted()` is what goes into logs and reports.
"""
from __future__ import annotations

import pathlib
import re
from contextlib import contextmanager

STAGING_REF = "eedcahzekpgxvvfxufbk"
PRODUCTION_REF = "vtxkciupyafukhdsgxgw"

_ENV = pathlib.Path(__file__).resolve().parent / ".env.pwa-staging.local"
_VAR = "AYDEN_STAGING_DATABASE_URL"


class NotStaging(RuntimeError):
    """The connection target could not be proved to be the staging project."""


def _read_url() -> str:
    if not _ENV.exists():
        raise NotStaging(f"{_ENV.name} is missing.")
    for line in _ENV.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith(_VAR) and "=" in line:
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise NotStaging(f"{_VAR} is not set in {_ENV.name}.")


def redacted(url: str) -> str:
    """Host and database only — safe for logs, reports and test output."""
    host = re.search(r"@([^:/?]+)", url)
    db = re.search(r"/([^/?]+)(\?|$)", url)
    return f"{host.group(1) if host else '?'}/{db.group(1) if db else '?'}"


# Supabase serves direct connections (`db.<ref>.supabase.co`) over IPv6 only.
# This machine has no IPv6 route, so that host does not even resolve. The
# pooler is the IPv4 path; it identifies the project in the USERNAME rather
# than the hostname, which is why the ref check below accepts either.
_POOLER_HOST = "aws-0-ap-northeast-1.pooler.supabase.com"
_POOLER_PORT = 5432


def _to_pooler(url: str) -> str:
    """Rewrite a direct URL onto the pooler, preserving the credential."""
    import urllib.parse

    p = urllib.parse.urlparse(url)
    pw = urllib.parse.quote(p.password or "", safe="")
    return (f"postgresql://postgres.{STAGING_REF}:{pw}"
            f"@{_POOLER_HOST}:{_POOLER_PORT}/postgres?sslmode=require")


def resolve_staging_url() -> str:
    """Return a usable staging URL, or raise before anything touches a database.

    The ref must be present and the production ref absent — checked on the
    string that will actually be dialled, after any rewrite, so the guard can
    never be bypassed by the rewrite itself.
    """
    url = _read_url()
    if PRODUCTION_REF in url:
        raise NotStaging("the URL carries the PRODUCTION project ref — refusing.")
    if STAGING_REF not in url:
        raise NotStaging("the URL does not carry the authorized staging ref — refusing.")

    host = re.search(r"@([^:/?]+)", url)
    if host and STAGING_REF not in host.group(1):
        raise NotStaging("the HOST is not the staging project — refusing.")

    import socket

    try:  # direct host, when the network can reach it
        socket.getaddrinfo(host.group(1) if host else "", _POOLER_PORT)
        final = url
    except OSError:
        final = _to_pooler(url)

    # Re-assert on the string that will really be used.
    if PRODUCTION_REF in final or STAGING_REF not in final:
        raise NotStaging("the resolved connection is not the staging project — refusing.")
    return final


@contextmanager
def staging_connection(*, autocommit: bool = False):
    """A connection to staging, or nothing at all."""
    import psycopg  # noqa: PLC0415 — operator tooling only

    url = resolve_staging_url()
    with psycopg.connect(url, autocommit=autocommit, connect_timeout=20) as conn:
        yield conn


def prove_target() -> dict:
    """Ask the database itself who it is. Belt and braces: the URL said staging,
    now the server has to agree."""
    facts: dict[str, object] = {}
    with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
        cur.execute("select current_database(), current_user, version()")
        db, user, version = cur.fetchone()
        facts["database"] = db
        facts["user"] = user
        facts["postgres"] = version.split(" on ")[0]
        # The decisive one: `pwa_staging` exists ONLY in the staging project.
        cur.execute("select exists (select 1 from pg_namespace where nspname = 'pwa_staging')")
        facts["pwa_staging_schema"] = cur.fetchone()[0]
        # And a table production owns must NOT be here.
        #
        # 2026-08-12 — the marker set CHANGED once already: it used to be
        # ('generation_intents', 'wallets', 'passes'), a correct negative marker
        # for exactly as long as the staging project had no Billing Engine.
        # Migration 0006 installs those three BY DESIGN, so the old set would
        # have started reading "this is production" about the project we had
        # just provisioned on purpose. It was replaced with
        # ('usage_log', 'messages', 'account_state', 'device_tokens').
        #
        # 2026-08-18 — it broke for the SAME reason, and this is the measurement
        # rather than the story. Asked of the staging database today:
        #
        #     account_state  present, 73 rows
        #     messages       present,  0 rows
        #     usage_log      present,  0 rows
        #     device_tokens  absent
        #
        # Three of the four markers are present, so `pwa_staging_migrate` was
        # refusing every migration. They are not evidence of production: this
        # staging project is SHARED with the unified-identity work, which
        # installed `account_state` (and the empty `messages` / `usage_log`
        # shells that come with it). `usage_log` in particular is harmless here
        # — `resolve_generation_access` only READS it for a legacy display
        # figure and it gates nothing (promo.py: "`free_remaining` (usage_log)
        # reste calculé pour l'AFFICHAGE legacy … mais ne gate plus rien ici").
        #
        # The lesson is that a negative marker over a shared project decays. So
        # the REFUSAL now rests on the two facts that cannot decay:
        #
        #   1. the connection string carries the staging project ref and not the
        #      production one — enforced in `resolve_staging_url`, on the exact
        #      string that will be dialled;
        #   2. the schema `pwa_staging` exists, and it exists in NO other
        #      project — checked above, and checked by the caller.
        #
        # `device_tokens` (mobile push, production-only, and nothing in the Web
        # chantier can create it) is kept as one cheap negative marker. The rest
        # are reported as information, so a surprise is still visible without
        # being fatal.
        cur.execute("""
            select table_name from information_schema.tables
             where table_schema = 'public'
               and table_name in ('usage_log', 'messages',
                                  'account_state', 'device_tokens')
             order by table_name
        """)
        present = [r[0] for r in cur.fetchall()]
        facts["production_only_tables_present"] = [
            t for t in present if t == "device_tokens"]
        facts["legacy_shared_tables_present"] = [
            t for t in present if t != "device_tokens"]
    return facts
