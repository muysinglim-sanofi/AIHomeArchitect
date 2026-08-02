# PWA staging persistence — foundation (Batch 3.0)

**Status: NOT ACTIVATED.** These files describe the isolated staging schema and
the safe way to bring it online later. Nothing here is auto-run, and the Flutter
app never executes migrations.

## Absolute rules

- Isolated schema `pwa_staging` in an **isolated staging Supabase project**. It
  creates its own tables and touches **no** production object.
- Never apply against the iOS production database.
- Never place a service-role key in Flutter or web assets.
- The client must **never** silently fall back to production or mock.

## Migration safety (§13)

`0001_pwa_staging_foundation.sql` fails **closed**. The whole migration runs in
**one transaction** and the guard `RAISE`s before any DDL, so if the required
GUCs are absent the transaction aborts and **nothing is created** — even if the
caller forgets `-v ON_ERROR_STOP=1`. It requires **two** explicit session GUCs:

```sql
set app.ayden_allow_staging_migrations = 'true';
set app.ayden_env = 'staging';
```

> DB-name checks are deliberately **not** used: on Supabase both staging and
> production databases are named `postgres`, so `current_database()` cannot
> distinguish them. The operator MUST verify the connection target is the
> isolated staging project before running.

Recommended manual run (staging only):

```bash
# Prove the target first — print host/project ref and confirm it is staging.
psql "$AYDEN_STAGING_DATABASE_URL" \
  -v ON_ERROR_STOP=1 \
  -c "set app.ayden_allow_staging_migrations = 'true';" \
  -c "set app.ayden_env = 'staging';" \
  -f supabase/staging/pwa/0001_pwa_staging_foundation.sql
```

Do **not** wire this into app startup or CI against production.

## Access-control model (§12) — pick ONE at activation

- **Option A (preferred): staging API facade.** The browser calls a staging-only
  backend endpoint; the service role stays server-side; a signed installation
  token is validated per request. RLS stays deny-all for anon.
- **Option B: staging anonymous auth.** A staging-only anonymous Supabase user;
  RLS policies key off a verified `installation_id` claim. Enable the commented
  policy templates in the SQL only after auth is wired.

RLS is enabled with **no permissive policy**, so the tables are deny-all until a
scoped policy is added deliberately.

## Client activation checklist (later, gated)

1. Provision an isolated staging Supabase project (separate from production).
2. Set `--dart-define`s (see `.env.pwa-staging.example`) with a **staging**
   Supabase URL that contains `staging` and is not on the production denylist —
   `PwaEnvironment.assertStagingTargetAllowed` enforces this at boot.
3. Run the migration manually (above).
4. Implement `StagingPwaPersistenceRepository` against the schema using
   `pwa_project_serialization`, keeping the service role server-side.
5. Add integration tests proving cross-installation isolation (two identities).
6. Only then flip staging on behind explicit product/tech approval.
