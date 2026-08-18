"""Apply a PWA STAGING migration — operator tooling, staging only.

Never imported by the API. It proves the target, sets the two guard GUCs the
migrations require, runs the file, and reports. The connection string is never
printed; only `host/database` appears in output.

Usage:  python pwa_staging_migrate.py <path-to.sql>
"""
from __future__ import annotations

import pathlib
import sys

from pwa_staging_db import prove_target, redacted, resolve_staging_url, staging_connection


def apply(path: pathlib.Path) -> int:
    sql = path.read_text(encoding="utf-8")

    url = resolve_staging_url()
    print(f"target      : {redacted(url)}")
    facts = prove_target()
    for k, v in facts.items():
        print(f"  {k} = {v}")

    # The decisive proof, asked of the server rather than of the string: only
    # the staging project has `pwa_staging`, and it must carry none of the
    # production tables.
    if not facts.get("pwa_staging_schema"):
        print("REFUSING: pwa_staging schema absent — this is not the PWA staging project.")
        return 2
    if facts.get("production_only_tables_present"):
        print("REFUSING: production-only tables present "
              f"({', '.join(facts['production_only_tables_present'])}) — "
              "this looks like production.")
        return 2
    # Not fatal, but never silent: this staging project is shared with the
    # unified-identity chantier, so tables the PWA phase deliberately did not
    # install can legitimately be here. See pwa_staging_db.prove_target.
    if facts.get("legacy_shared_tables_present"):
        print("  note: shared-project tables present "
              f"({', '.join(facts['legacy_shared_tables_present'])}) — "
              "expected, not a production signal.")

    print(f"\napplying    : {path.name}")
    with staging_connection(autocommit=True) as conn:
        with conn.cursor() as cur:
            # The migrations RAISE unless both are set. Session-level, before
            # the file's own BEGIN.
            cur.execute("set app.ayden_allow_staging_migrations = 'true'")
            cur.execute("set app.ayden_env = 'staging'")
        # The file manages its own transaction; psycopg passes it through.
        with conn.cursor() as cur:
            cur.execute(sql)
        for notice in conn.notices if hasattr(conn, "notices") else []:
            print("  notice:", notice.strip())
    print("applied OK")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        raise SystemExit(64)
    raise SystemExit(apply(pathlib.Path(sys.argv[1])))
