# Meta / Facebook Login — exact non-production setup (staging / preprod)

Everything the code needs from outside the repository, in the order it is
needed. Nothing here is production: the app is a **development-mode** Meta
app pointed at the **staging** Supabase project and **preprod.aydenstudio.com**.

The PWA reads which providers exist from the project at boot
(`/auth/v1/settings`). The moment Facebook is switched on in Supabase, the
"Continue with Facebook" door appears on preprod — **no rebuild, no redeploy**.

---

## A. Meta for Developers — the app

1. https://developers.facebook.com → **My Apps** → **Create App**.
   * Use case: **Authenticate and request data from users with Facebook Login**
     (the "Consumer" / "Other → Consumer" type on older UIs).
   * App name: `Ayden Studio (staging)`. Contact email: yours.
2. **Add product → Facebook Login → Set up** — skip the Quickstart, go to
   **Facebook Login → Settings** in the left sidebar.
3. **Valid OAuth Redirect URIs** — exactly one, Supabase's callback for the
   STAGING project:

   ```
   https://eedcahzekpgxvvfxufbk.supabase.co/auth/v1/callback
   ```

   (Client OAuth Login: ON. Web OAuth Login: ON. Enforce HTTPS: ON.
   Login with the JavaScript SDK: OFF — not used.)
4. **App settings → Basic**:
   * **App Domains**: `preprod.aydenstudio.com` and `supabase.co`.
   * **Privacy Policy URL**: `https://aydenstudio.com/privacy`
     (the published policy the PWA already links to).
   * **Terms of Service URL**: `https://aydenstudio.com/terms`.
   * **User data deletion**: a URL or instructions — Meta requires one to go
     live; for dev mode a "Data deletion instructions URL" pointing at the
     privacy page is accepted.
   * **Category**: Lifestyle (or Utility & Productivity).
   * Add a **Website** platform: Site URL `https://preprod.aydenstudio.com`.
   * Copy the **App ID** and the **App Secret** (Show).
5. **App Review → Permissions and Features**: `public_profile` and `email`
   must show **Ready for testing** (they are granted by default to a new app;
   nothing to request). No other permission is used.
6. **App Roles → Roles**: add every tester as **Tester** (they must accept the
   invitation in their Facebook account). While the app is in **Development
   mode**, ONLY admins/developers/testers can log in — this is the
   non-production gate and is what we want for staging.
7. **App Roles → Test Users**: create 2–3 test users. At least one with
   **no email** is the launch-critical case (see §D).

**App Review / going live** — not needed for staging. For production launch,
switch the app to **Live** mode; `public_profile` + `email` are standard
access and do not require a review submission. Business verification is
required only for advanced access, which this product does not use.

## B. Supabase (STAGING project `eedcahzekpgxvvfxufbk`) — Dashboard

Authentication → Sign In / Providers:

* **Facebook**: enable. Paste **App ID** → *Facebook client ID*, **App Secret**
  → *Facebook client secret*. **Email optional: ON** (this is
  `external_facebook_email_optional`; without it a Facebook account that
  shares no email cannot sign in — GoTrue refuses with "Error getting user
  email from external provider").
* **Anonymous sign-ins**: keep ON (already on).

Authentication → Settings (General):

* **Allow manual linking: ON** (`security_manual_linking_enabled`). Required by
  `linkIdentity()`; without it the link attempt fails with
  `manual_linking_disabled` before leaving the page.

Authentication → URL Configuration → **Redirect URLs** — add:

```
https://preprod.aydenstudio.com/**
https://ayden-studio-preprod.web.app/**
```

(The PWA sends `redirect_to = <origin>/profile`; GoTrue only honours a
`redirect_to` that matches this list, otherwise it falls back to the Site URL.)

**Or, with a personal access token** (`SUPABASE_ACCESS_TOKEN=sbp_…` in
`backend/.env.pwa-staging.local`, plus `FACEBOOK_CLIENT_ID=` and
`FACEBOOK_CLIENT_SECRET=` lines), all of the above in one command:

```
cd backend && python pwa_staging_auth_cambodia.py           # verify, no writes
cd backend && python pwa_staging_auth_cambodia.py --apply   # write it
```

The secret file is git-ignored and the script never prints a credential.

## C. Nothing goes in the frontend

The App Secret lives only in the Supabase project config (server side). The
PWA bundle holds the Supabase **publishable** key only; the OAuth exchange
runs on Supabase's callback, never in the browser.

## D. What to test once B is done (5 minutes, on preprod)

1. Fresh private window → preprod → Profile → **Secure my account** →
   **Continue with Facebook** with a NEW test user (never used on Ayden) →
   back on Profile: the sheet says *Your work is saved*, the card shows the
   Facebook name and *Connected with Facebook*, projects unchanged,
   Spaces unchanged. (AUTH04 / AUTH09 / AUTH10 live.)
2. Same window → Sign out → **Sign in → Continue with Facebook** with that
   same user → *You're signed in*, its projects and Spaces come back.
   (AUTH20 / AUTH11 live.)
3. Fresh private window (a new guest) → **Secure my account → Facebook** with
   the user from step 1 → *Welcome back — This Facebook account already has
   an Ayden account* → **Continue to my existing account** → signed in as
   that account; the new guest keeps its own (empty) work. (AUTH07 live.)
4. Close Facebook's dialog instead of authorising → back on the chooser with
   *Facebook sign-in was cancelled*. (AUTH18 live.)
5. **The no-email case** (launch-critical): a test user with no email, or a
   real account that declines the email permission in Facebook's dialog:
   * as a NEW guest, **Secure my account → Facebook** → expected with today's
     GoTrue: *Facebook didn't share an email address, so it can't be attached
     to this account* (the link path requires an email, see the
     implementation report §7) → the guest is untouched and phone still works;
   * **Sign in → Facebook** with that user → a NEW email-less account is
     created and signed in (`email_optional` in effect).
   Record which of the two shapes GoTrue produced; the report carries both as
   UNVERIFIED until this run.
