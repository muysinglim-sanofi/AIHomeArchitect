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
        # And production's own tables must NOT be here.
        #
        # 2026-08-12 — the marker set CHANGED, and the reason matters. It used to
        # be ('generation_intents', 'wallets', 'passes'), which was a correct
        # negative marker for exactly as long as the staging project had no
        # Billing Engine. Migration 0006 installs those three BY DESIGN (one
        # billing brain, canonical names — PWA_MONETIZATION_AUDIT §8.5), so the
        # old set would have started refusing every later migration and, worse,
        # would have read "this is production" about the project we had just
        # provisioned on purpose.
        #
        # The replacements are the tables production owns that this project is
        # committed NEVER to have (§8.5 "hors périmètre" + mobile-only chat and
        # push): `usage_log` (legacy free-quota ledger, superseded by the ledger
        # free bucket), `messages` (mobile chat), `account_state` (identity /
        # account-mode) and `device_tokens` (mobile push). None of them can
        # appear here without someone having pointed this tooling at the wrong
        # database — which is precisely what the check is for.
        cur.execute("""
            select count(*) from information_schema.tables
             where table_schema = 'public'
               and table_name in ('usage_log', 'messages',
                                  'account_state', 'device_tokens')
        """)
        facts["production_tables_present"] = cur.fetchone()[0]
    return facts
