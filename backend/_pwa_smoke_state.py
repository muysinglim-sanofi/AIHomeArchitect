"""Read the staging lineage back exactly as the ENGINE sees it — smoke tooling.

Not a test and not imported by anything: it answers, for one project, the same
questions the adapter answers on the next generation, so a real smoke can be
checked against the database rather than against the screen alone.

Usage:  PYTHONPATH=. python _pwa_smoke_state.py [project_id]
        (no argument → the most recently created project)
"""
from __future__ import annotations

import sys

from pwa_staging_db import staging_connection

PROJECT_COLS = ("id", "title", "status", "room_id", "room_label",
                "resolved_room_type", "selected_atmosphere_id",
                "current_vision_id", "cover_vision_id", "original_image_path")

VISION_COLS = ("id", "vision_number", "action_type", "parent_vision_id",
               "atmosphere_id", "atmosphere_label", "room_label",
               "lineage_customized", "prompt_text", "image_path")


def main() -> int:
    with staging_connection() as conn, conn.cursor() as cur:
        if len(sys.argv) > 1:
            pid = sys.argv[1]
        else:
            cur.execute("select id from pwa_staging.pwa_projects "
                        "order by created_at desc limit 1")
            row = cur.fetchone()
            if not row:
                print("no projects")
                return 1
            pid = row[0]

        cur.execute(
            f"select {', '.join(PROJECT_COLS)} from pwa_staging.pwa_projects "
            "where id = %s", (pid,))
        p = cur.fetchone()
        print("PROJECT")
        for k, v in zip(PROJECT_COLS, p):
            print(f"  {k:24} = {v}")

        cur.execute(
            f"select {', '.join(VISION_COLS)} from pwa_staging.pwa_visions "
            "where project_id = %s order by vision_number", (pid,))
        # psycopg returns uuid objects; the adapter helpers compare ids as
        # strings (PostgREST hands it JSON), so normalise once here rather
        # than teaching the helpers about a driver they never see.
        rows = [tuple(str(v) if k in ("id", "parent_vision_id") and v is not None else v
                      for k, v in zip(VISION_COLS, r)) for r in cur.fetchall()]
        print(f"\nVISIONS ({len(rows)})")
        by_id = {r[0]: r for r in rows}
        for r in rows:
            d = dict(zip(VISION_COLS, r))
            parent = by_id.get(d["parent_vision_id"])
            print(f"  V{d['vision_number']}  {d['id'][:8]}  "
                  f"action={d['action_type']:<18} "
                  f"parent={'V' + str(parent[1]) if parent else '(none)':<8} "
                  f"atmo={d['atmosphere_id']:<16} "
                  f"room={d['room_label'] or '(none)':<14} "
                  f"customized={d['lineage_customized']}")
            if d["prompt_text"]:
                print(f"        prompt: {d['prompt_text'][:80]}")

        # The BRANCH history the composer would receive for a child of the tip,
        # rebuilt with the adapter's own helpers so this cannot drift from it.
        sys.path.insert(0, ".")
        from pwa_staging_api import _ancestry, _customized_from, _history_from

        raw = [dict(zip(VISION_COLS, r)) for r in rows]
        if raw:
            tip = raw[-1]["id"]
            chain = _ancestry(raw, tip)
            print(f"\nAS THE ENGINE WOULD SEE A CHILD OF V{raw[-1]['vision_number']}")
            print(f"  ancestry     = {[c['vision_number'] for c in chain]}")
            print(f"  customized   = {_customized_from(raw[-1], chain, raw)}")
            print(f"  history      = {[h['content'][:40] for h in _history_from(chain)]}")

        cur.execute(
            "select idempotency_key, state, error_code, render_started "
            "from pwa_staging.pwa_generation_claims where project_id = %s "
            "order by created_at", (pid,))
        claims = cur.fetchall()
        print(f"\nCLAIMS ({len(claims)})")
        for k, state, err, started in claims:
            print(f"  {k[:8]}  {state:<11} error={err or '-':<20} render_started={started}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
