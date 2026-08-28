# Phase 8 — Profile

Preview: <https://ayden-studio--phase8-profile-be3xwuji.web.app> (expires 2026-09-04)
Live staging and the Phase 1–7 previews are all **untouched**.

| file | what it shows |
|---|---|
| `01-profile-guest-fr.png` | the screen — a real staging Guest, French |
| `02-save-your-work-fr.png` | the CTA opening the **existing** account sheet |
| `03-language-fr.png` | the language row opening the selector |
| `04-profile-guest-en.png` | English |
| `05-profile-guest-km.png` | Khmer |
| `06-langsheet-check.png` | the selector, fully open — each language in its own language |
| `07-guide-km.png` | "See how it works" replaying the existing cinematic |
| `08-profile-desktop-km.png` | 1440 — a centred column, not an account dashboard |
| `09-deeplink-km.png` | `/profile` opened cold, by URL, by a first-time visitor |

All nine are the deployed staging build against the public staging backend.

**The one state not photographed: VERIFIED.** Reaching it means receiving a real
six-digit code at a real inbox, which this session has no access to. It is
covered by tests instead — `PROF02` walks the real service and controller
through `beginLink` → `submitCode` and asserts what the card then shows, that
the email appears, that the Save-your-work CTA disappears, that sign-out is
offered and calls the existing path, and that the user id is never printed.

---

## The iOS Profile, mapped

`lib/features/profile/profile_screen.dart` + `account_section.dart`, read
row by row.

### A — same on web (built)

| iOS | PWA |
|---|---|
| `profileTitle`, `headlineLarge` | same string, same role (`PwaType.screenTitle`) |
| identity row: 64pt circle, name, second line | same geometry; **web identity**, see B |
| `settingsAccount` / `settingsSupport` headers | same strings, 12/w600/+1 |
| `_SettingsCard`: surface, r16, hairline, `ListTile`, divider indent 54 | reproduced |
| Language row → sheet, each language in its own language, gold tick | reproduced, on the web's own locale notifier |

### B — same intent, web behaviour

| iOS | PWA | why it differs |
|---|---|---|
| name/email from Supabase `user_metadata` via mobile's `ProfileService` | **Guest** or the verified **email** | the web identity is anonymous-or-email-verified; there is no web name store |
| `_PremiumStatusCard` keyed on `access_source` (admin/pass/promo/restore_required/free) → Premium Center or paywall | wallet row keyed on `PwaBillingState` → the existing web paywall | same idea, different discriminator: the web reads `pwaEntitlementProvider`, and there is no Apple subscription to manage |
| `AccountSection`: Continue with Apple, sign out, merge | **Save your work** (email code) and **Sign out** | Apple is native; the web's identity path is the email OTP the product already ships |
| Help Center FAQ sheet | **See how it works** — the existing hero cinematic | see "The guide" below |
| sign-out behind `FeatureFlags.signInEnabled` (off) | shown when, and only when, there is an identity to leave | the web account system is not flagged off |

### C — native-only, deliberately absent

Restore Purchases · the Premium Center / Manage plan · App Store subscription
state (`passRenewsAt`, `passExpiresAt`) · `restore_required` and its RevenueCat
round trip · push-notification toggles · Rate the App · the Apple sign-in
button · the admin section (`meStatus.isAdmin`, a backend field the web client
does not fetch).

A test asserts these by name: no rendered text on Profile may contain "apple",
"restore", "app store", "subscription", "manage plan", "notification" or
"rate ". Re-adding one is a failing test, not a review comment.

### Omitted, and why — not native, just not real here

* **Edit Profile** (first name / last name / email). It writes mobile's
  `ProfileService` into Supabase `user_metadata`; there is no web equivalent
  and the brief is explicit about not inventing editable fields. A test asserts
  Profile contains no `TextField` at all.
* **The redesign count.** iOS reads `generationsSucceeded` from `/me/status`.
  The web client does not fetch that endpoint, and counting local projects
  would be a different number wearing the same label.
* **The build marker.** `kBuildTag` is `'GI · PR2b-slice3 · 2026-07-03d'` — a
  MOBILE build id. On the web it would identify the wrong thing.
* **Privacy / About sheets.** Static content that exists only in the mobile
  screen. Real destinations, but this phase is Profile parity, not a legal
  surface; flagged for the account/paywall phase which owns that copy.

---

## Every path it uses already existed

| row | path |
|---|---|
| Save your work | `showPwaAccountSheet` → `PwaAuthController.beginLink` / `submitCode` → `PwaEntitlementController.onIdentityChanged`. The same two calls the account chip makes. |
| Sign out | `PwaAuthController.signOut` → `onIdentityChanged`. Session semantics, guest behaviour and project ownership untouched. |
| Wallet | `pwaEntitlementProvider` (the frontend's copy of the backend's answer) → `showPwaPaywall`. No local arithmetic; `loading` renders **nothing** rather than a reassuring zero. |
| Language | `LocaleNotifier.setLocale` → `ui_locale`, the same preference the top-bar switcher and the mobile app write. One store, a second door. |
| Guide | `PwaHeroSequence` + `createPwaHeroVideo`, mounted with the hero's own copy. |
| The tab | `PwaPhase.profile` → `/profile`, through the same `canonicalRoute` / `applyRoute` pair Home and Projects use. |

**Identity states are the web's.** A Guest is a working user with real
projects, so the card names them and explains where the work lives; it never
implies an account. Nothing is created by opening Profile — a test asserts the
verification channel is not touched. `signInEnabled`, UID semantics and the
anonymous→verified upgrade are untouched.

---

## The guide, and why it is not iOS's onboarding

iOS's `OnboardingScreen` drives `context.go('/home')` into the **mobile**
router — a route that does not exist in the mock target and means something
else entirely in the web app. Mounting it would have been parity in appearance
and a bug in behaviour.

What the PWA actually has is the hero cinematic: an empty room becoming a Warm
Modern interior, `PwaHeroSequence` + `PwaHeroVideo`, retired from Home in
Phase 2 when the Featured Vision took the hero slot, kept and pinned by a test.
The guide sheet replays exactly that, with the hero's own approved subline, as
often as anyone likes. Reduced motion, an unsupported video, an error or a slow
file all resolve to the finished frame — it never spins and never blocks.

Home is not touched, and does not regain a "See how it works" block.

---

## Defects found and fixed

**A free Guest was told they held paid Spaces.** The first wallet row read the
counters and printed "1 Spaces restants" — true arithmetic, wrong sentence. A
Space is a thing you buy; this person has a free vision. The row is now a
`switch` over `PwaBillingState`, the backend's own discriminator, in the same
shape iOS's card takes off `access_source` — so a new billing state is a
compile error rather than a blank line in front of a paying customer. Both the
sentence and the exhaustiveness are tested.

**`/profile` bounced to `/`.** Two causes, one symptom, both found by opening
the URL rather than by reading the code. The boot resolver forces any route
back to the Hero when the durable library is empty — right for a project URL,
wrong for Profile, which depends on no project (`PwaRoute.normalize` already
said so). And the initial state built from that restore knew `/projects` and
`/create` but not `/profile`, so even once the route survived, the first frame
was Home and the URL sync scope rewrote the address back to `/`. Both are
fixed and both are tested; project routes still fall back exactly as before.

**A build with no verification channel offered a step it could not take.** The
Guest card explained "add an email so your projects follow you" even where no
code can be sent and no button is drawn. It now says who you are and promises
nothing.

---

## Corrected: a defect that was not one

The language sheet looked clipped in the staging browser — the third language
below the fold. It is not: **an occluded Chrome tab freezes the frame ticker**,
so the sheet was photographed mid-slide. `Page.bringToFront` alone does not
resume it; `Page.setWebLifecycleState: active` plus
`Emulation.setFocusEmulationEnabled` do, and `cdp.mjs shot` now does all three
before every capture. `06-langsheet-check.png` is the sheet fully open.

`isScrollControlled: true` was added while that diagnosis was wrong. It is
kept — on its own merits, and the comment in the code now says so: the sheet
should take its natural height rather than the 9/16 cap, so a fourth language
or a short viewport cannot clip a row. The reachability test is likewise kept
and labelled as an invariant, not a regression guard: it does **not** fail
without the flag, and pretending otherwise would be worse than not having it.

---

## Gate

* `flutter test` — **1247 passed, 0 failed** (+36 Profile parity tests; one
  Phase 1 test inverted, see below).
* `flutter analyze` — 2 issues, both pre-existing `info` lints in
  `pwa_i18n_test.dart` (622, 654), a file this phase does not touch.
* `tool/build_pwa.sh staging` — clean.
* `backend/pwa_secret_scan.py` — **PASS 10, LEAKS 0**.
* Deployed to the **phase8-profile** channel only. (`hosting:channel:deploy`
  prints a generic "Deploy complete / Hosting URL" block that reads like a
  production deploy and is not one — see the Phase 7 README.)

**One earlier test inverted.** `FOUND05` asserted "Profile is visible but INERT
until its screen exists", which was correct in Phase 1 and is now false. It is
replaced by two: all three destinations report, and a host that passes
`enabled: {profile: false}` still gets an inert tab — the escape hatch the
original was really protecting.

---

## Out of scope, still open

Unchanged from the Phase 7 report and deliberately untouched here: the
singular/plural "1 redesigns"; `pending_generation_v1` surviving a billing
refusal and being replayed on every boot; the paywall + generic error banner
duplication; app-store products in the web paywall; Home's unbounded desktop
width.

Profile links to the wallet and does not redesign the paywall.
