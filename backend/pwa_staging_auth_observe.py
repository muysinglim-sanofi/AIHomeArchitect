"""LIVE AUTH OBSERVATION — what a staging user owns, before and after a link.

Read-only. Prints, for one Supabase user id (or for the most recently active
users), exactly the four facts the FB-LIVE / PHONE-LIVE matrix turns on:

    identity     is_anonymous, email, phone, app_metadata.providers, identities
    projects     how many, and their ids
    visions      how many
    entitlement  the ledger's answer (free bucket + pass credits)

Nothing here writes. It exists so a live test can be judged on measured rows
rather than on what a screen appeared to say.

Usage
    python pwa_staging_auth_observe.py <uid>            one user
    python pwa_staging_auth_observe.py <uid> <uid> ...  several (A and B)
    python pwa_staging_auth_observe.py --recent 5       the 5 newest users
"""
from __future__ import annotations

import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from pwa_staging_db import redacted, resolve_staging_url, staging_connection  # noqa: E402


def observe(cur, uid: str) -> None:
    cur.execute("""
        select id, is_anonymous, email, phone, created_at,
               coalesce(raw_app_meta_data->>'providers', '[]'),
               coalesce(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', '')
          from auth.users where id = %s""", (uid,))
    row = cur.fetchone()
    if not row:
        print(f"  {uid}  -> NO SUCH USER")
        return
    _id, anon, email, phone, created, providers, name = row
    cur.execute("select provider, created_at from auth.identities where user_id = %s order by created_at", (uid,))
    idents = cur.fetchall()
    cur.execute("""select id, title, status from pwa_staging.pwa_projects
                    where owner_user_id = %s and deleted_at is null
                    order by created_at""", (uid,))
    prows = cur.fetchall()
    projects = [f"{str(r[0])[:8]}…({r[2]})" for r in prows]
    cur.execute("select count(*) from pwa_staging.pwa_visions where owner_user_id = %s", (uid,))
    visions = cur.fetchone()[0]

    print(f"  uid            {uid}")
    print(f"  is_anonymous   {anon}")
    print(f"  email          {email or '(none)'}")
    print(f"  phone          {'+' + phone if phone else '(none)'}")
    print(f"  display name   {name or '(none)'}")
    print(f"  providers      {providers}")
    print(f"  identities     {', '.join(f'{p}@{c:%Y-%m-%d %H:%M}' for p, c in idents) or '(none)'}")
    print(f"  projects       {len(projects)}  {projects}")
    print(f"  visions        {visions}")

    # The wallet/ledger, if the Billing Engine tables are present.
    try:
        cur.execute("""select coalesce(sum(available_delta),0) from public.ledger_entries
                        where user_id = %s and pass_id is null""", (uid,))
        free_delta = cur.fetchone()[0]
        cur.execute("select count(*) from public.ledger_entries where user_id = %s and entry_type='TRIAL'", (uid,))
        trials = cur.fetchone()[0]
        cur.execute("select count(*) from public.passes where user_id = %s and status = 'ACTIVE'", (uid,))
        n_pass = cur.fetchone()[0]
        # Pass credits live in the LEDGER (pass-scoped rows), not on the pass:
        # `passes` carries no balance column — the ledger is the authority.
        cur.execute("""select coalesce(sum(available_delta),0) from public.ledger_entries
                        where user_id = %s and pass_id is not null""", (uid,))
        pass_credits = cur.fetchone()[0]
        print(f"  ledger         free_delta={free_delta}  trial_rows={trials}  "
              f"active_passes={n_pass}  pass_credits={pass_credits}")
    except Exception as exc:  # noqa: BLE001 — billing tables are optional here
        print(f"  ledger         (unavailable: {type(exc).__name__})")


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    url = resolve_staging_url()
    print(f"target : {redacted(url)}  (STAGING, read-only)\n")
    with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
        if args[0] == "--recent":
            n = int(args[1]) if len(args) > 1 else 5
            cur.execute("select id from auth.users order by created_at desc limit %s", (n,))
            uids = [str(r[0]) for r in cur.fetchall()]
        else:
            uids = args
        for i, uid in enumerate(uids):
            if i:
                print()
            observe(cur, uid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
