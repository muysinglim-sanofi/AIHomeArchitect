-- ============================================================================
-- 20260911_pwa_prod_auth_phone_change_release — PRODUCTION version of the PWA
-- staging migration 0010, in schema `pwa`.
--
-- WHY IT IS REQUIRED. GoTrue verifies a `phone_change` OTP by looking the user
-- up BY NUMBER (`verify.go` -> `FindUserByPhoneChangeAndAudience`), and
-- `auth.users.phone_change` is not unique. An abandoned attempt on another
-- account can answer a later verification of the same number: the honest
-- person is refused. The Web backend therefore calls this function right
-- before the browser's `updateUser({phone})` (`POST /pwa/auth/phone/prepare`,
-- `pwa_staging_auth_api.py`): it clears expired attempts and reports live
-- holders of the number on OTHER users, so the client can ask the person to
-- retry instead of gambling on row order.
--
-- WITHOUT IT the route answers 503 `PHONE_PREPARE_UNAVAILABLE`; the client
-- then proceeds under its own user-id guard only (it loses the early warning,
-- and stale rows are never released).
--
-- BODY: byte-for-byte the staging function, schema renamed. It writes ONLY
-- auth.users.phone_change / phone_change_token / phone_change_sent_at, and
-- only on rows whose attempt is older than the grace period (dead by GoTrue's
-- own rule), never the caller's row, never the verified `phone`, never a row
-- inside the grace period. No public.*, no billing, no PayWay. The native app
-- does not use phone auth (0 phone identities in production, 2026-09-11).
--
-- SECURITY DEFINER, executable by service_role ONLY (the Web backend's key).
-- anon and authenticated cannot reach it.
--
-- Idempotent (create or replace). Rollback:
--   backend/sql/rollback/20260911_pwa_prod_auth_phone_change_release_rollback.sql
-- Test: backend/sql/tests/pwa_prod_auth_phone_change_release_test.sql
-- ============================================================================

begin;

do $guard$
begin
  if not exists (select 1 from pg_namespace where nspname = 'pwa') then
    raise exception 'Schema "pwa" is missing - this is not the PWA production project.';
  end if;
  if exists (select 1 from pg_namespace where nspname = 'pwa_staging') then
    raise exception 'Schema "pwa_staging" exists here - refusing: this looks like STAGING.';
  end if;
end
$guard$;

create or replace function pwa.auth_phone_change_release(
  p_phone         text,
  p_caller        uuid,
  p_grace_seconds integer default 600
)
returns table (cleared integer, contested integer)
language plpgsql
security definer
set search_path = pg_catalog, public
as $fn$
declare
  v_phone    text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_grace    interval := make_interval(secs => greatest(coalesce(p_grace_seconds, 600), 60));
  v_cleared  integer := 0;
  v_contest  integer := 0;
begin
  -- 1. Release every expired attempt, whoever started it. A token older than
  --    the OTP window can never verify (verify.go isOtpValid), so clearing the
  --    row removes only the ambiguity, never a live verification.
  with dead as (
    update auth.users u
       set phone_change         = '',
           phone_change_token   = '',
           phone_change_sent_at = null
     where coalesce(u.phone_change, '') <> ''
       and u.phone_change_sent_at is not null
       and u.phone_change_sent_at < now() - v_grace
       and u.id is distinct from p_caller
    returning 1
  )
  select count(*) into v_cleared from dead;

  -- 2. What is left for THIS number on OTHER users is a live attempt. It is
  --    reported, not touched: clearing it would let anyone cancel a stranger's
  --    in-flight verification by typing their number.
  if v_phone <> '' then
    select count(*) into v_contest
      from auth.users u
     where u.phone_change = v_phone
       and u.id is distinct from p_caller;
  end if;

  cleared   := v_cleared;
  contested := v_contest;
  return next;
end
$fn$;

comment on function pwa.auth_phone_change_release(text, uuid, integer) is
  'Releases expired auth.users.phone_change rows (project-wide) and reports live '
  'holders of one number on other users. Called by the Web backend before '
  'updateUser({phone}). service_role only.';

revoke all on function pwa.auth_phone_change_release(text, uuid, integer) from public;
revoke all on function pwa.auth_phone_change_release(text, uuid, integer) from anon;
revoke all on function pwa.auth_phone_change_release(text, uuid, integer) from authenticated;
grant execute on function pwa.auth_phone_change_release(text, uuid, integer) to service_role;

do $check$
begin
  if (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'pwa' and p.proname = 'auth_phone_change_release') is distinct from true then
    raise exception 'auth_phone_change_release is not SECURITY DEFINER';
  end if;
  if has_function_privilege('anon', 'pwa.auth_phone_change_release(text, uuid, integer)', 'execute')
     or has_function_privilege('authenticated', 'pwa.auth_phone_change_release(text, uuid, integer)', 'execute') then
    raise exception 'anon/authenticated can execute auth_phone_change_release';
  end if;
  if not has_function_privilege('service_role', 'pwa.auth_phone_change_release(text, uuid, integer)', 'execute') then
    raise exception 'service_role cannot execute auth_phone_change_release';
  end if;
end
$check$;

commit;

notify pgrst, 'reload schema';
