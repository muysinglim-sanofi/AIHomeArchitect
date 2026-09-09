# AYDEN STUDIO PWA — Cambodia auth (Facebook + phone + email fallback)
## Implementation report — 2026-09-08

Scope: the PWA (`c:/Projects/ayden-pwa-web`, branch `pwa-web-ios-alignment`)
and its Web backend (`c:/Projects/AIHomeArchitect`, branch `pwa-monetization`).
Target: STAGING / PREPROD only (`preprod.aydenstudio.com`, Fly
`ayden-api-staging`, Supabase `eedcahzekpgxvvfxufbk`). Production, native
iOS (`frontend/lib/**`, `frontend/ios/**`), ABA PayWay, Billing, RevenueCat:
untouched — proved in §19.

Start HEADs: PWA `94e6308`, backend `fcdd208` (tags
`auth-cambodia-start-pwa-2026-09-08`, `auth-cambodia-start-backend-2026-09-08`).
Final HEADs: PWA `951c0e1` (commits `6361edd`, `951c0e1`), backend `55301b7`
(+ this report's follow-up). Nothing pushed.

---

### 1. Architecture found

* **Guest-first, already.** Boot mints or restores an anonymous Supabase
  session before the first frame (`PwaStagingSupabaseClient.ensureSession`,
  `main_pwa.dart`). No wall anywhere; the account sheet opens only from
  Profile, the paywall and the header chip.
* **One identity service** (`lib/features/pwa/auth/pwa_auth_service.dart`)
  with two explicit journeys — `linkNewIdentity` (SECURE) and
  `signInExisting` (SIGN IN) — over ONE transport abstraction
  (`PwaVerificationChannel`), implemented for email OTP only
  (`pwa_email_otp_channel.dart`: `updateUser(email)` + `verifyOTP(emailChange)`
  for the link; `signInWithOtp(shouldCreateUser:false)` + `verifyOTP(email)`
  for the sign-in).
* **Upgrade-in-place is measured, not assumed.** The link journey preserves
  the user id; `backend/pwa_staging_identity_probe.py` proved it against the
  real project (B2/B5/B6) and the service reads the id before and after every
  verification.
* **Ownership key = `auth.uid()` everywhere.** Projects/visions/messages
  (`pwa_staging.*`, RLS on `auth.uid()`), Storage paths
  (`users/<uid>/projects/<pid>/…`, asserted server-side), entitlement and the
  ledger (`trial:<user_id>`, `pwa_staging_billing.py`), PayWay orders. No
  table, path or key uses the email.
* **Backend JWT verification** (`auth.py`) accepts anonymous and signed-in
  tokens; `CurrentUser.email` is `Optional[str]` and nothing in
  `pwa_staging_api.py` / `pwa_staging_billing.py` / `pwa_staging_payments.py`
  reads it. RLS assumes only `auth.uid()`.
* **Session persistence** is supabase_flutter's own (SharedPreferences-backed
  localStorage), PKCE flow by default; a reload restores the same user and
  `ensureSession` signs in anonymously ONLY when no session exists.
* **`user.email` assumptions found (3, all UI):** header chip label
  (`pwa_account_chip.dart:41` — an identified user with no email read as
  "Guest"), the sheet's footnote, and the Profile identity card (title,
  initial). All three are fixed (§12).
* **Staging project config at start** (`/auth/v1/settings`): anonymous ON,
  email ON, **phone OFF** (provider preset `twilio`, no credentials),
  **facebook OFF**. Manual linking: unknown without a PAT (not exposed
  publicly); required for `linkIdentity`.

### 2. Files inspected

PWA: `lib/main_pwa.dart`, `lib/features/pwa/auth/*`,
`presentation/pwa_account_sheet.dart`, `pwa_account_chip.dart`,
`pwa_profile_ios.dart`, `pwa_paywall.dart` (identity line only),
`data/pwa_staging_supabase_client.dart`, `data/pwa_web_navigation.dart`,
`data/pwa_generation_api.dart`, `data/supabase_pwa_persistence_repository.dart`,
`application/pwa_route.dart`, `application/pwa_url_bridge.dart`,
`application/pwa_intro_gate.dart`, `config/pwa_environment.dart`,
`l10n/pwa_l10n.dart`, `l10n/pwa_translations.dart`, `tool/build_pwa.sh`,
`tool/deploy_pwa.sh`, `supabase/staging/pwa/0001…0009`, and the tests
`pwa_auth_paywall_test.dart`, `pwa_profile_parity_test.dart`,
`pwa_round4_profile_test.dart`, `pwa_round2_visual_test.dart`.
SDK sources (pinned): gotrue 2.20.0 (`linkIdentity`, `getLinkIdentityUrl`,
`getSessionFromUrl`, `verifyOTP`, `resend`, `setSession`, `ErrorCode`),
supabase_flutter 2.12.4 (`SupabaseAuth.initialize`, `_handleDeeplink`,
`linkIdentity`, `signInWithOAuth`).
Backend: `auth.py`, `identity.py` (mobile only), `pwa_staging_api.py`,
`pwa_staging_billing.py`, `pwa_target.py`, `pwa_staging_db.py`,
`pwa_staging_migrate.py`, `run_pwa_staging.py`, `run_pwa_prod.py`,
`pwa_staging_auth_email.py`, `pwa_staging_identity_probe.py`.
GoTrue (supabase/auth master, fetched 2026-09-08): `internal/api/external.go`,
`identity.go`, `verify.go`, `user.go`, `phone.go`, `mail.go`,
`provider/facebook.go`, `models/user.go`, `conf/configuration.go`.
Supabase docs: identity linking, anonymous sign-ins, phone login, error
codes, Facebook login, custom OAuth providers, Send SMS hook, the
troubleshooting article on `updateUser({phone})` linking to the wrong user,
and the Management API OpenAPI (`/v1-json`, auth config field names).

### 3. Files changed

PWA — new:
`lib/features/pwa/auth/pwa_phone_number.dart` (E.164, masking),
`pwa_auth_availability.dart` (providers from `/auth/v1/settings`),
`pwa_phone_otp_channel.dart` (phone transport, both journeys, prepare step),
`pwa_oauth_gateway.dart` (Facebook via `linkIdentity` / `signInWithOAuth`,
the hand-off, the return parser and error taxonomy),
`supabase/staging/pwa/0010_auth_phone_change_release.sql`,
`test/features/pwa/pwa_auth_cambodia_test.dart` (AUTH01–30 + UI01–08).
PWA — modified: `pwa_auth_service.dart`, `pwa_auth_controller.dart`,
`pwa_verification_channel.dart` (5 new failure kinds),
`pwa_account_sheet.dart` (chooser, phone step, cooldown, forks, OAuth
outcome), `pwa_account_chip.dart`, `pwa_profile_ios.dart` (identity card,
"Sign-in methods", OAuth landing), `pwa_generation_api.dart`
(`preparePhoneLink`), `pwa_web_navigation.dart` (`webPwaOrigin`,
`webPwaBootUri`), `pwa_l10n.dart`, `pwa_translations.dart` (43 keys × 3),
`main_pwa.dart` (boot wiring), and four existing test files updated to the new
copy/contract (§15).
Backend — new: `backend/pwa_staging_auth_api.py` (`POST …/auth/phone/prepare`),
`backend/pwa_staging_auth_cambodia.py` (Management API verify/apply),
`backend/pwa_staging_auth_phone_test.py` (AUTH26 at the database),
`docs/auth/*` (this report, the Meta checklist).
Backend — modified: `run_pwa_staging.py`, `run_pwa_prod.py` (mount the auth
router). `pwa_staging_api.py` carries a PRE-EXISTING uncommitted WIP
(`pwa_target` refactor + refine orientation log) that was left as found and
is not part of this work.

### 4. Guest UID lifecycle

Boot → `Supabase.initialize` restores a persisted session → `ensureSession`
signs in anonymously only if none → `auth.uid()` = the Guest, durable across
reloads. SECURE (email/phone/Facebook) keeps that uid. SIGN IN replaces the
session with the existing account's; the Guest's rows stay under the Guest's
uid (nothing moves, nothing is deleted). Sign out drops the session and mints
a NEW Guest (a new uid, its own free bucket resolved by the server). No
`device_id` exists anywhere.

### 5. LINK vs SIGN IN — explicit state

`PwaAuthJourney { linkNewIdentity, signInExisting }` is set by the service at
the moment a journey starts and carried on every state; the sheet never
infers it. For Facebook the journey is written to `sessionStorage`
(`PwaAuthHandoff`, with the uid and project ids BEFORE leaving) and read back
at boot, so the redirect cannot lose the intent. Wire-level:

| intent | email | phone | Facebook |
|---|---|---|---|
| SECURE | `PUT /user {email}` → `verify emailChange` | `PUT /user {phone}` → `verify phone_change` | `GET /user/identities/authorize` (`linkIdentity`, target = current uid) |
| SIGN IN | `POST /otp {email, create_user:false}` → `verify email` | `POST /otp {phone, create_user:false}` → `verify sms` | `GET /authorize` (`signInWithOAuth`) |

A collision on SECURE (`email_exists` / `phone_exists` /
`identity_already_exists` "…to another user") is a STOP that renders
*Welcome back — This X already has an Ayden account — [Continue to my
existing account]*; only that tap starts the SIGN IN. No merge exists in the
client, and no transfer of quota, ledger rows, passes or projects (AUTH22).

### 6. Facebook implementation

* Doors appear only when the project says `external.facebook == true`
  (`PwaAuthProviders`, read at boot, fails closed to email only).
* SECURE → `linkIdentity(OAuthProvider.facebook, redirectTo: <origin>/profile)`;
  SIGN IN → `signInWithOAuth(...)`. Both are full-page redirects (PKCE; the
  verifier is persisted by supabase_flutter). Manual linking must be ON.
* Return: the boot code reads the URL (query AND fragment — GoTrue mirrors
  `error`, `error_code`, `error_description` into both, `redirectErrors`) and
  the hand-off, then `PwaAuthService.completeOAuthReturn` measures: same uid
  → *Your work is saved* (identityPreserved); different uid on SIGN IN →
  *You're signed in* (switchedAccount). Profile opens the sheet once on
  landing (`oauthPending`), the sheet clears it on close.
* Error taxonomy (`PwaOAuthReturn.failureOf`, AUTH24): `identity_already_exists`
  + "another user" → fork; `identity_already_exists` alone (already on THIS
  account) → not an error; `error=access_denied` without a GoTrue code →
  cancelled; "user email from external provider" / `email_not_confirmed`
  "Unverified email with facebook" → providerNoEmail; `manual_linking_disabled`,
  `provider_disabled`, `bad_oauth_*`, `flow_state_*`, `oauth_provider_not_supported`
  → providerRefused; a pre-redirect `AuthException` is mapped the same way.
* Display name from `user_metadata.full_name|name`; the Facebook identity
  appears in `app_metadata.providers` → "Connected with Facebook", tick in
  "Sign-in methods".
* **Status: implementation DONE; real staging test NOT run** — the project
  has no Facebook credentials and no PAT (§17).

### 7. Facebook without email — result: PARTIAL, launch-relevant

Evidence (GoTrue master, 2026-09-08):

* `provider/facebook.go`: scopes are hard-coded `email` (+ configured extras),
  profile read `/me?fields=email,first_name,last_name,name,picture`; when
  Facebook returns no email, `Emails` is simply empty.
* `external.go:184`: `if len(userData.Emails) == 0 && !emailOptional → 500
  "Error getting user email from external provider"`. `emailOptional` comes
  from the provider's config (`conf/configuration.go:66`,
  `email_optional`), and the hosted Management API exposes it as
  **`external_facebook_email_optional`** (confirmed in `/v1-json`). So the
  built-in Facebook provider DOES support email-less users — **for
  sign-in/creation** (`createAccountFromExternalIdentity:409` handles the
  no-email case). A custom OAuth2 provider is NOT needed.
* `identity.go` `linkIdentityToUser`: on the LINK path, when the target user
  has no email (a Guest, or a phone-only account) GoTrue promotes an email
  from the identities, and if the new identity's email is not verified
  (`EmailVerified` stays false when there is no email at all) it calls
  `sendConfirmation` and returns `email_not_confirmed` — the identity row is
  committed (`CommitWithError`) but the user stays anonymous. **So "Guest A +
  Facebook-without-email" cannot be attached to A by GoTrue today.** This is
  a GoTrue limitation, not a configuration.

Product answer implemented, without any of the forbidden workarounds (no
fake email, no Facebook name/email as key, no manual `auth.users` rows, no
merge):

* SIGN IN with an email-less Facebook account: **supported** once
  `external_facebook_email_optional=true` (a new, email-less Ayden account is
  created and owned by its uid; phone/email can be added afterwards).
* SECURE Guest A with an email-less Facebook: **refused honestly** —
  `providerNoEmail` → *Facebook didn't share an email address, so it can't be
  attached to this account. Use your phone number to secure it instead.* The
  Guest is untouched; phone (and email) still secure A. A retry after the
  half-committed identity reads "Identity is already linked" (same user) and
  is not shown as a stranger's collision.
* **UNVERIFIED live** until Facebook is configured on staging (checklist §D.5
  in `META_FACEBOOK_SETUP_CHECKLIST_2026_09_08.md`). Both shapes are handled
  by the code either way.

### 8. Phone implementation

* `PwaPhoneNumber.normalize` → E.164 (`+85512345678`), Cambodia `+855` by
  default, trunk `0` dropped, `00` → `+`, Khmer digits accepted, explicit `+`
  or `00` keeps the typed country; 8–15 digits, no leading zero. Masking
  `+855 •• ••• 5678` (fixed shape). The E.164 string is what GoTrue stores
  (without `+`); the uid remains the only account key.
* Sheet: dial-code field (`+855` preset, editable) + number field
  (`TextInputType.phone`, autofill telephone) → Continue → 6-digit code
  (`AutofillHints.oneTimeCode`) → Verify; *Use a different number*; resend
  with a 60 s client cooldown mirroring `sms_max_frequency`; *Codes expire
  after a few minutes.*
* SECURE → prepare (§9) → `updateUser(phone)` → `verifyOTP(phoneChange)`;
  SIGN IN → `signInWithOtp(phone, shouldCreateUser:false)` → `verifyOTP(sms)`.
  Error taxonomy (AUTH25): `phone_exists` → fork; `validation_failed` /
  `user_not_found` / signups disabled → invalid number; `over_sms_send_rate_limit`
  / `over_request_rate_limit` / 429 → rate limited; `sms_send_failed` /
  `phone_provider_disabled` → unavailable; `otp_expired` / 403 → wrong code.
* **Status: implementation DONE; real OTP test NOT run** — phone provider is
  OFF on staging, no Twilio credentials, no test OTPs (§17).

### 9. `phone_change` risk — understood, reproduced, mitigated

**The exact risk (primary evidence).** `verify.go`:
`case phoneChangeVerification: user, err = models.FindUserByPhoneChangeAndAudience(conn, params.Phone, aud)`
→ `models/user.go:1205` `findUser(tx, "instance_id = ? and phone_change = ? and aud = ? and is_sso_user = false").First(obj)`.
The user is resolved by NUMBER, not by session; `phone_change` is not
unique; `.First()` is planner order. With a real SMS token the wrong row's
token does not match → the honest person gets `otp_expired`. With a project
**test OTP** the match is by number alone (`verify.go:754` returns the
found user before any token comparison) → **the returned session is the
stale row's user**. Supabase's troubleshooting article says the same and
recommends application-level cleanup of stale `phone_change` values.

**Is staging exposed?** Yes, structurally (any project is). Reproduced
against the real staging database (`backend/pwa_staging_auth_phone_test.py`):
two disposable users A (stale, 20 min) and B (live, 30 s) with the same
`phone_change`; GoTrue's own predicate returned both rows and its `First()`
resolved to **A (STALE)** — AUTH26.1, run 2026-09-08.

**Mitigation (two independent defences, both shipped):**

1. **Server-side release, before every link.** Migration
   `0010_auth_phone_change_release.sql` installs
   `pwa_staging.auth_phone_change_release(p_phone, p_caller, p_grace_seconds)`
   — SECURITY DEFINER, `service_role` only (anon/authenticated revoked and
   asserted). It clears every `phone_change` older than the grace period
   (project-wide; those tokens are already dead by `isOtpValid`) and reports
   how many OTHER users still hold this number inside the window. It never
   touches `phone`, a live attempt, or the caller's own row. The backend
   endpoint `POST /pwa/staging/auth/phone/prepare` (caller resolved from the
   JWT via `/auth/v1/user`, service key never leaves the server, grace 600 s,
   `PWA_PHONE_CHANGE_GRACE_S`) calls it; the phone channel calls the endpoint
   before `updateUser` and **refuses to start** while `contested > 0`
   (*A verification for this number is still in progress…*). Applied to
   staging 2026-09-08 (`pwa_staging_migrate.py`, "0010 OK").
   AUTH26.1–13 at the database: **13/13 PASS**. Endpoint end-to-end with a
   real anonymous session: 200 `{cleared:0, contested:0, grace_seconds:600}`.
2. **Client-side guard on every LINK verification.** The uid AND refresh
   token are captured before `verifyOTP`; if the uid differs afterwards the
   previous session is restored (`setSession(refreshToken)`) and the result
   is `identityMismatch` — never `identified`, never "your work is saved"
   (AUTH26a, AUTH04 of the August series updated to this contract).

**Config recommendation** (in `pwa_staging_auth_cambodia.py --apply`):
`sms_otp_exp=300`, `sms_max_frequency=60`, `sms_otp_length=6`; keep
`sms_otp_exp` ≤ the 600 s grace so the release never touches a live token.
**Residual:** a stale row younger than the grace period blocks the number
for at most 10 minutes (reported, never gambled). The end-to-end wrong-session
run needs the provider ON + a test OTP: **UNVERIFIED live**, mitigated by
design and by the DB-level reproduction.

### 10. SMS provider / config result

Decision: **Twilio (Programmable Messaging via a Messaging Service SID)**,
the project's own preset and the provider with documented Cambodia routes.
Configuration lives in the project (Management API fields
`sms_provider=twilio`, `sms_twilio_account_sid`, `sms_twilio_auth_token`,
`sms_twilio_message_service_sid`, `external_phone_enabled=true`) and is
written by `pwa_staging_auth_cambodia.py --apply` from the ignored secret
file (`TWILIO_*` lines) — or by hand in the dashboard. **Test OTPs**
(`sms_test_otp="+855…=123456"`, `sms_test_otp_valid_until`) let QA verify
the whole phone flow with no SMS sent; GoTrue skips the provider for those
numbers (`phone.go:81`). The **Send SMS Hook** (`hook_send_sms_uri`) is the
fallback if Twilio delivery to Smart/Cellcard/Metfone proves poor: it
replaces the built-in send with a call to our Fly backend, which can then
use any Cambodian gateway; not built, because there is no delivery
measurement yet to justify it.
Status: **SMS provider = pending** (no credentials). **CARRIER DELIVERY =
UNVERIFIED** for Smart, Cellcard, Metfone — a documentation claim is not a
delivery proof.

### 11. Session persistence

Unchanged mechanism (supabase_flutter localStorage, PKCE, auto-refresh).
Facebook: the code exchange during `Supabase.initialize` persists the new
session before the first frame; the hand-off is taken (read + cleared) so a
later reload cannot re-announce it. `bootState()` consumes the return once.
AUTH20 (service level) PASS; live reload after Facebook/phone: UNVERIFIED
(providers off).

### 12. Email optionality

`PwaAuthState` now carries `email`, `phone`, `displayName`, `providers` (all
may be empty) and derives `identityLabel` (name → email → masked phone) and
`connectedVia`. Chip, sheet footnote, Profile card and the new "Sign-in
methods" card render from those; nothing requires `email`. Backend: nothing
reads `CurrentUser.email` on the Web paths (grep, §1). AUTH12a/b/c, AUTH29 PASS.

### 13. Projects safety

Ownership is `auth.uid()` (RLS + storage path assertion). LINK keeps the uid
→ same rows (AUTH09); SIGN IN reads the other uid's rows and leaves the
Guest's in place (AUTH11, AUTH22). The Facebook hand-off records the project
ids before leaving for an after-the-fact comparison. The sheet re-hydrates
entitlement on every success and the library only when the user changed
(`pwaHydrateForIdentity`, unchanged).

### 14. Spaces safety

Billing semantics untouched. Entitlement is re-read from the server on every
identity change; the client holds no wallet, no counter, and no auth event
grants (AUTH10, AUTH28). PayWay/billing suites re-run green (§15).

### 15. Test results

Commands and outcomes (2026-09-08):

| command | result |
|---|---|
| `flutter analyze` (PWA) | 0 issues |
| `flutter test test/features/pwa/pwa_auth_cambodia_test.dart` | 47 tests, all passed (AUTH01–30, UI01–08) |
| `flutter test` (whole PWA suite, final run) | **1528 tests, all passed** (exit 0) |
| `python backend/pwa_secret_scan.py` (bundle + logs, windowed read) | PASS 11 / LEAKS 0 / INCONCLUSIVE 0 |
| `python backend/pwa_staging_auth_phone_test.py` (staging DB, AUTH26) | PASS 13 / FAIL 0 |
| endpoint `/pwa/staging/auth/phone/prepare` with a real anonymous JWT | 200 `{cleared:0, contested:0}` |
| `python backend/pwa_staging_identity_probe.py` (AUTH23, email OTP) | PASS 11 / FAIL 1 — the failing step is the probe's own `@aydenstudio.dev` test address, which GoTrue now refuses as `email_address_invalid`; re-run by hand with `example.com` → `429 over_email_send_rate_limit` (staging's built-in SMTP quota, the documented pre-existing state). The identity operation is accepted; email OTP is unchanged. |
| `PYTHONPATH=. python backend/payway_adapter_test.py` | ALL PASS (102 assertions) |
| `PYTHONPATH=. .venv/Scripts/python backend/pwa_staging_payments_test.py` | ALL PASS (240 assertions) |
| `PYTHONPATH=. .venv/Scripts/python backend/pwa_staging_payway_db_test.py` | CHECKS 39 / FAILURES 0 |
| `PYTHONPATH=. python backend/pwa_target_test.py` | ALL PASS |

Existing tests updated to the new contract: `pwa_auth_paywall_test.dart`
AUTH04 (a link that changed the uid is now `identityMismatch`, not
"switched"), AUTH14 (the fork reads *Welcome back* + *Continue to my existing
account*); `pwa_round4_profile_test.dart` PROF10/11 and
`pwa_profile_parity_test.dart` PROF02 (Profile card = label + "Connected
with…", CTA = *Secure my account*), PROF06 (scroll before tapping the guide
row); `pwa_round2_visual_test.dart` AUTH12 (profile may read `authSecureCta`).

Two pre-existing tests were adjusted for the new copy during the full run:
`pwa_i18n_test.dart` (the brand noun "Facebook" is identical in every
language, added to the allow-list; the phone hint now differs per locale)
and `pwa_round3_hydration_test.dart` (the sheet's success branch is still the
settling state; the source assertion now anchors on the branch itself).

### 16. Visual results

Preprod: deployed (`tool/deploy_pwa.sh --preprod`), and the served
`main.dart.js` / `ayden-build.json` / `version.json` hash-match the local
`build/web` byte for byte. Live captures on preprod (mobile 390×844, EN):
`docs/auth-cambodia/shots/live-m-profile-guest.png` — the Guest card
(*Guest / Your designs are saved on this device.*), the *Secure my account*
primary, the *Already use Ayden Studio? Sign in* line, then Spaces and the
settings rows, nav bar intact. `live-m-sheet-email-only.png` — the sheet
opened live from *Secure my account*: with Facebook and phone OFF on the
staging project it is the email-only one (unchanged since August), no
console error (`docs/round3-final/cdp_tap_console.mjs` listens while
tapping). `live-d-profile-guest.png` — the same Profile at 1440×900 in
French (*Sécuriser mon compte*). Note for the next operator: the driver's
`click` command left this button pressed without lifting the pointer on
the live page; a plain touchStart/touchEnd (the helper above) works.

The Cambodia sheet itself was captured from the review harness
(`lib/dev/pwa_auth_sheet_preview.dart`, the production widget over a
scripted service), `docs/auth-cambodia/shots/`:

* `m-chooser-{en,km,fr}.png` — *Secure your Ayden account*; Facebook (filled
  pill + glyph) above Phone (outlined pill), *or*, *Use email instead*,
  returning-user line. No overflow in Khmer or French.
* `m-signin-{en,km,fr}.png` — the same doors under *Sign in*.
* `m-phone-{en,km,fr}.png` — `+855` code chip + number field, Continue
  disabled until the number parses, *Choose another way*.
* `m-email-*.png` — the address field with the way back to the chooser.
* `m-welcome-facebook-*.png` — *Welcome back / This Facebook account already
  has an Ayden account. / Sign in to it instead. Your guest work stays…* and
  the single *Continue to my existing account* action.
* `m-cancelled-*.png`, `m-noemail-*.png` — back on the chooser with the quiet
  line under the doors.
* `d-*-{en,km}.png` — 1440×900: the sheet is centred and capped at 560 px.

Keyboard/safe-area: the sheet pads by `viewInsets.bottom` and scrolls;
`autofillHints` are set for email, telephone and one-time code.

### 16bis. FACEBOOK STAGING ACTIVATION — real, 2026-09-09

Credentials supplied into the ignored secret file (`SUPABASE_ACCESS_TOKEN`,
`FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`); Meta app created, callback
`https://eedcahzekpgxvvfxufbk.supabase.co/auth/v1/callback` validated,
`public_profile` + `email` ready for testing, app in **Development mode**.
No value was printed, logged, diffed or committed at any point: every tool
run went through a redactor that replaces each secret-file value in stdout.

**One defect found and fixed in the ACTIVATION TOOLING (not product code).**
The first dry-run answered `403` on every Management API call, including
`/v1/organizations`. Classified before touching anything, with three
controlled requests on the same token:

| request | result |
|---|---|
| default `Python-urllib/3.x` UA + token | `403 error code: 1010` |
| browser UA + token | `200`, projects listed |
| browser UA, no token | `401 {"message":"Unauthorized"}` |

`api.supabase.com` sits behind Cloudflare, whose rule bans the urllib
signature; `error code: 1010` is a browser-signature block, not an auth
failure. The token was valid throughout. No configuration can change
urllib's User-Agent, so `pwa_staging_auth_cambodia.py` now sends one, with
the measurement recorded beside it. Product code untouched.

**Dry-run, then apply.** The dry-run also revealed that `uri_allow_list` was
**empty**: no production URL could be lost, and every OAuth `redirect_to`
would have fallen back to `site_url = http://localhost:3000`. Deltas
written, staging project only:

| key | before | after |
|---|---|---|
| `external_facebook_enabled` | false | **true** |
| `external_facebook_client_id` / `_secret` | absent | **set** |
| `external_facebook_email_optional` | false | **true** (reviewed, section 7) |
| `security_manual_linking_enabled` | false | **true** (`linkIdentity` needs it) |
| `uri_allow_list` | *(empty)* | the two preprod globs |
| `sms_otp_exp` | 60 | 300 |
| `sms_max_frequency` | 5 | 60 |
| `external_phone_enabled` | false | **false** (untouched, no Twilio values) |
| `external_email_enabled`, `external_anonymous_users_enabled` | true | **true** (untouched) |
| `sms_provider`, `site_url`, captcha | unchanged | unchanged |

`PATCH /v1/projects/eedcahzekpgxvvfxufbk/config/auth -> 200`. The two SMS
timing values are inert while the phone provider is off; they are the
reviewed staging values, written once rather than in a second pass.

**Verified independently of the script.**

* Management API read-back: facebook true, email_optional true, phone false,
  email true, anonymous true, manual linking true, both preprod globs
  present, client id and secret present, twilio absent.
* Public `/auth/v1/settings`: facebook True, phone False, email True,
  anonymous True. That is what the PWA reads at boot.
* **Production `vtxkciupyafukhdsgxgw`, read-only GET:** facebook false,
  phone false, allow list empty. Untouched. The only write in the whole
  session was the single staging PATCH above.
* **Both OAuth endpoints answer, with no Facebook login needed:**
  `GET /auth/v1/authorize?provider=facebook&redirect_to=<preprod>/profile`
  answers `302` to `www.facebook.com/dialog/oauth` with client_id,
  `scope=email`, `redirect_uri` = the Supabase callback and a `state`.
  `GET /auth/v1/user/identities/authorize?provider=facebook` on a REAL
  anonymous session answers `200` with the same Facebook URL, which is the
  positive proof that manual linking is effective: it would answer
  `manual_linking_disabled` otherwise. The probe user was deleted.
* **No rebuild needed, proved by hash:** preprod still serves
  `main.dart.js` sha256 prefix `3b814acd79dd6a52`, byte-identical to the
  local `build/web`. The Facebook door appeared from configuration alone.
* **Live on preprod** (`docs/auth-cambodia/shots/live-fb-02-chooser.png`,
  390x844, FR): the chooser reads *Securisez votre compte Ayden* then
  **Continuer avec Facebook** (filled pill and glyph), then *ou*, then
  *Utiliser un e-mail*, then the returning-user line. **No phone button**,
  exactly as the provider state dictates.
* **Real departure to Facebook**: tapping the button navigated the live
  browser to `www.facebook.com/login.php` for our Meta app. The link
  journey mints its URL and leaves, for real.
* **FB-LIVE-07 (abandon) PASSED live**: uid before departure
  `253f7fa6-3380-4d0c-88aa-3c621687462d` (anonymous); returning to
  `/profile` without completing Facebook left the **same uid**, still
  anonymous, and the hand-off had been consumed and cleared. No corruption,
  no second account, nothing claimed.

**A driving trap worth recording** (it cost two false negatives before it was
classified): a Chrome launched behind the terminal is *occluded*, and a
Flutter Web page there still paints for screenshots but **drops every
input**. Two taps on the account button appeared to do nothing, with zero JS
errors. The control that settled it: a tap on the unrelated **Language** row
was equally inert, so the fault was the environment, not the auth code.
`Emulation.setFocusEmulationEnabled` fixes it and both taps then worked
first time.

**Observation tool for the live matrix**:
`backend/pwa_staging_auth_observe.py` (read-only) prints, per uid,
`is_anonymous`, email, phone, display name, `app_metadata.providers`, the
`auth.identities` rows, the project ids, the vision count and the ledger
figures. Guest A before any link: anonymous, no identity, 0 projects,
0 visions, ledger empty.

**Remaining FB-LIVE tests need a human Facebook login** as a Meta tester,
namely 01 through 06 and 08. Everything a machine can verify without those
credentials is green above.

### 17. External setup remaining (Mike only)

1. **Meta app** — `docs/auth/META_FACEBOOK_SETUP_CHECKLIST_2026_09_08.md`
   (App ID/Secret, callback `https://eedcahzekpgxvvfxufbk.supabase.co/auth/v1/callback`,
   app domain `preprod.aydenstudio.com`, dev mode + testers, one test user
   without email).
2. **Supabase staging config** — either the dashboard steps in the checklist
   §B, or add to `backend/.env.pwa-staging.local`:
   `SUPABASE_ACCESS_TOKEN=sbp_…`, `FACEBOOK_CLIENT_ID=`, `FACEBOOK_CLIENT_SECRET=`,
   `TWILIO_ACCOUNT_SID=`, `TWILIO_AUTH_TOKEN=`, `TWILIO_MESSAGE_SERVICE_SID=`,
   `SMS_TEST_OTP=+855XXXXXXXX=123456`, then
   `python backend/pwa_staging_auth_cambodia.py --apply`. It sets manual
   linking, Facebook (+ email optional), phone/Twilio, OTP 6 / 300 s / 60 s,
   30 SMS/h, test OTPs, and the preprod redirect URLs.
3. **Twilio** — an account with a Messaging Service that has a Cambodia-capable
   sender (alphanumeric sender IDs are not accepted by all KH carriers; a
   long-code/number-based sender is the safe start). Then one real SMS to a
   Smart, a Cellcard and a Metfone SIM.
4. **Backend redeploy on Fly** (`ayden-api-staging`) so
   `/pwa/staging/auth/phone/prepare` is live: `cd backend && flyctl deploy`
   (this machine is not logged into Fly). Until then the client fails open to
   its own uid guard (it only loses the early "please wait" warning).
5. Optional but recommended before launch: CAPTCHA (Turnstile) on the
   project for anonymous sign-ins and OTP requests
   (`security_captcha_enabled`); the client does not yet pass a captcha token
   and would need a small addition when it is switched on.

### 18. Known limitations

* Facebook-without-email cannot be ATTACHED to an existing account (GoTrue
  link path, §7); it can sign in / create one.
* Adding an EMAIL to an account that already has one is not offered (GoTrue's
  secure email change is a two-address confirmation this product does not run).
* Unlinking a method is deliberately absent (a recovery method removed by a
  tap is an account lost by a tap).
* A stale `phone_change` younger than 10 minutes blocks that number for the
  remainder of the window (reported to the person, never gambled).
* No CAPTCHA token is sent yet (§17.5).
* The mock (offline) build has no providers and shows the email-only sheet.

### 19. Launch blockers

None in code. Everything below is external configuration or a live
measurement that only credentials make possible:
Facebook credentials + manual linking + email optional (§17.1–2); phone
provider + test OTPs (§17.2–3); carrier delivery (§17.3); Fly redeploy
(§17.4). Facebook-without-email LINK is a documented GoTrue limitation with a
safe product path, not a blocker.

**Repo safety.** Production Supabase/Firebase/PayWay: not touched. Native
iOS: not touched (`git diff --name-only` in both repos lists no `frontend/`
path). ABA/payment code: not touched (no `payway*`, `*payments*`,
`*billing*`, `pwa_aba_*`, paywall or wallet source in either diff; the
payment suites re-run green). Frozen zones intact.

### 20. Exact next action

Mike: run the Meta checklist §A–B (or fill the secret file and run
`pwa_staging_auth_cambodia.py --apply`), `flyctl deploy` the staging API,
then the 5-minute live script in the checklist §D and the phone run with a
test OTP. Everything else is in place on preprod.
