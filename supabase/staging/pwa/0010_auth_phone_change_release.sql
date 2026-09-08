-- ============================================================================
-- AYDEN STUDIO PWA — phone linking: releasing STALE `auth.users.phone_change`
-- 0010 — additive, IDEMPOTENT.  Schema: pwa_staging.  STAGING ONLY.
-- ----------------------------------------------------------------------------
-- WHY THIS FILE EXISTS
--
--   GoTrue verifies a `phone_change` OTP by looking the user up BY NUMBER, not
--   by session:
--
--     internal/api/verify.go
--       case phoneChangeVerification:
--         user, err = models.FindUserByPhoneChangeAndAudience(conn, params.Phone, aud)
--     internal/models/user.go
--       findUser(tx, "instance_id = ? and phone_change = ? and aud = ? …").First(obj)
--
--   `phone_change` carries no uniqueness. Two accounts that each started to
--   attach the same number — one of them abandoned — both hold it, and the
--   verification resolves to whichever row the planner returns FIRST. With a
--   real SMS OTP the stale row's token does not match and the honest person is
--   refused (`otp_expired`); with a project TEST OTP (`sms_test_otp`) the match
--   is by number alone (`verify.go:754`) and the SESSION RETURNED IS THE STALE
--   ROW'S USER. Supabase documents this and recommends application-level
--   cleanup of stale `phone_change` values (troubleshooting article
--   "auth.updateUser({ phone }): phone linked to incorrect user ID").
--
--   This file is that cleanup, as ONE function the backend calls right before
--   `updateUser({phone})`:
--
--     1. every `phone_change` older than the grace period is cleared,
--        project-wide (those tokens are already dead: `isOtpValid` refuses
--        anything past `sms_otp_exp`);
--     2. the caller is told how many OTHER users still hold this exact number
--        inside the grace period (`contested`). The client refuses to start a
--        link while that count is non-zero, and asks the person to retry in a
--        few minutes, rather than gamble on row order.
--
--   The client keeps its own guard on top: the user id is read before and
--   after `verifyOTP`, and a link that came back as a different user restores
--   the previous session and is reported as a failure. Two independent
--   defences, because the failure mode is "the wrong account gets a phone".
--
-- WHAT THIS DOES NOT DO
--
--   * It never touches `phone` (the verified column, which IS unique), never
--     touches a row inside the grace period, and never touches the CALLER's
--     own row — `updateUser` overwrites that one itself.
--   * It is not reachable by `anon` or `authenticated`. SECURITY DEFINER, owned
--     by postgres, executable by `service_role` only; the backend calls it with
--     the service key it already holds. The browser holds no such key.
--   * It does not read or write `public.*`, the Billing Engine, or PayWay.
--
-- HOW TO APPLY (operator, from a verified staging connection):
--       SET app.ayden_allow_staging_migrations = 'true';
--       SET app.ayden_env = 'staging';
--   or  python backend/pwa_staging_migrate.py supabase/staging/pwa/0010_auth_phone_change_release.sql
-- ============================================================================

begin;

do $guard$
begin
  if coalesce(current_setting('app.ayden_allow_staging_migrations', true), 'false') <> 'true' then
    raise exception
      'Refusing PWA staging migration: app.ayden_allow_staging_migrations is not true (fail closed).';
  end if;
  if coalesce(current_setting('app.ayden_env', true), '') <> 'staging' then
    raise exception
      'Refusing PWA staging migration: app.ayden_env is not staging (fail closed).';
  end if;
  if not exists (select 1 from pg_namespace where nspname = 'pwa_staging') then
    raise exception
      'Refusing: schema pwa_staging is absent — this is not the PWA staging project.';
  end if;
end
$guard$;

-- ----------------------------------------------------------------------------
-- auth_phone_change_release(p_phone, p_caller, p_grace_seconds)
--   p_phone          E.164 WITHOUT the '+', exactly as GoTrue stores it
--                    (`formatPhoneNumber` strips '+' and spaces).
--   p_caller         the user about to call updateUser — never cleared here.
--   p_grace_seconds  rows whose phone_change_sent_at is older than this are
--                    dead by GoTrue's own rule and are released.
-- Returns one row: cleared (project-wide), contested (this number, other
-- users, still inside the grace period).
-- ----------------------------------------------------------------------------
create or replace function pwa_staging.auth_phone_change_release(
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

comment on function pwa_staging.auth_phone_change_release(text, uuid, integer) is
  'Releases expired auth.users.phone_change rows (project-wide) and reports live '
  'holders of one number on other users. Called by the Web backend before '
  'updateUser({phone}). service_role only.';

-- The browser must never reach this. Only the backend's service key may.
revoke all on function pwa_staging.auth_phone_change_release(text, uuid, integer) from public;
revoke all on function pwa_staging.auth_phone_change_release(text, uuid, integer) from anon;
revoke all on function pwa_staging.auth_phone_change_release(text, uuid, integer) from authenticated;
grant execute on function pwa_staging.auth_phone_change_release(text, uuid, integer) to service_role;

-- ----------------------------------------------------------------------------
-- Self-check: the function exists, is SECURITY DEFINER, and anon/authenticated
-- cannot execute it.
-- ----------------------------------------------------------------------------
do $check$
declare
  v_secdef boolean;
begin
  select p.prosecdef into v_secdef
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'pwa_staging' and p.proname = 'auth_phone_change_release';
  if v_secdef is distinct from true then
    raise exception '0010: auth_phone_change_release is not SECURITY DEFINER';
  end if;
  if has_function_privilege('anon', 'pwa_staging.auth_phone_change_release(text, uuid, integer)', 'execute') then
    raise exception '0010: anon can execute auth_phone_change_release';
  end if;
  if has_function_privilege('authenticated', 'pwa_staging.auth_phone_change_release(text, uuid, integer)', 'execute') then
    raise exception '0010: authenticated can execute auth_phone_change_release';
  end if;
  if not has_function_privilege('service_role', 'pwa_staging.auth_phone_change_release(text, uuid, integer)', 'execute') then
    raise exception '0010: service_role cannot execute auth_phone_change_release';
  end if;
  raise notice '0010 OK: auth_phone_change_release installed (service_role only)';
end
$check$;

commit;
