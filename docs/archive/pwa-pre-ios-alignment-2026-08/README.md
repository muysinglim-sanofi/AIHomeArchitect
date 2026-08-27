# PWA staging — the last complete state BEFORE the iOS UX/UI alignment

Captured 2026-08-27, from the **live public deployment**, not from a local run.

---

## What is archived, and where

| | |
|---|---|
| Backend source | branch `archive/pwa-staging-before-ios-alignment` · tag `pwa-staging-pre-ios-alignment-2026-08` → **`e5e4926`** |
| PWA source | branch `archive/pwa-web-staging-before-ios-alignment` · tag `pwa-web-staging-pre-ios-alignment-2026-08` → **`c50a28e`** |
| Deployed PWA | Firebase Hosting `live`, released **2026-08-27 17:34:13** → <https://ayden-studio.web.app> |
| Frozen copy of that exact bundle | <https://ayden-studio--pre-ios-alignment-2026-08-knges3e0.web.app> (preview channel, **expires 2026-09-26**) |
| Deployed backend | Fly.io `ayden-api-staging` **release v2**, image `ayden-api-staging:deployment-01M11WAZAMMH51ZYZ6EB85AVPK` → <https://ayden-api-staging.fly.dev> |
| Screenshots | this directory (17 PNGs) |
| Capture driver | `cdp.mjs` in this directory |

### ⚠️ Two disjoint histories, one shared remote

The backend repo and the PWA repo (a worktree of the `frontend` submodule) BOTH
push to `github.com/muysinglim-sanofi/AIHomeArchitect`, and their histories share
no commit. `refs/heads/pwa-monetization` on that remote is the **backend**
branch. That is why the two archives use **different ref names** — pushing both
under one name would have replaced one history with the other.

---

## Restore procedure

### Source

```bash
# backend
git -C C:/Projects/AIHomeArchitect fetch origin
git -C C:/Projects/AIHomeArchitect checkout pwa-staging-pre-ios-alignment-2026-08

# PWA (frontend repo / worktree)
git -C C:/Projects/ayden-pwa-web fetch origin
git -C C:/Projects/ayden-pwa-web checkout pwa-web-staging-pre-ios-alignment-2026-08
```

### Redeploy the backend exactly as it ran

```bash
cd C:/Projects/AIHomeArchitect/backend
flyctl deploy -a ayden-api-staging --remote-only
```

Secrets are NOT in git. They live in Fly's secret store (8 of them) and are
re-settable from `backend/.env.pwa-staging.local`, which is gitignored. If that
file is ever lost, the values must come from Supabase / OpenAI / ABA again.

Rolling back without rebuilding:

```bash
flyctl releases -a ayden-api-staging          # find the version
flyctl deploy -a ayden-api-staging --image registry.fly.io/ayden-api-staging:deployment-01M11WAZAMMH51ZYZ6EB85AVPK
```

### Redeploy the PWA exactly as it was built

**The entrypoint matters.** `lib/main.dart` is the MOBILE app and boots the
production stack; building it compiles fine and is wrong. The PWA is
`lib/main_pwa.dart`.

```bash
cd C:/Projects/ayden-pwa-web
flutter build web --release -t lib/main_pwa.dart \
  --dart-define=AYDEN_ENV=staging \
  --dart-define=AYDEN_STAGING_SUPABASE_URL=https://eedcahzekpgxvvfxufbk.supabase.co \
  --dart-define=AYDEN_STAGING_PROJECT_REF=eedcahzekpgxvvfxufbk \
  --dart-define=AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY=<SUPABASE_PUBLISHABLE_KEY from backend/.env.pwa-staging.local> \
  --dart-define=AYDEN_STAGING_BACKEND_URL=https://ayden-api-staging.fly.dev
firebase deploy --only hosting --project ayden-studio
```

Rolling back Hosting without rebuilding: the Firebase console keeps every
release under Hosting → Release history → "Rollback". The frozen preview
channel above also serves the exact bundle until it expires.

---

## The environment this state ran against

```
Supabase   eedcahzekpgxvvfxufbk           STAGING
PayWay     checkout-sandbox.payway.com.kh SANDBOX
           acquisition = /payments/purchase
           callback_configured = true
Catalogue  pack_10  10 spaces  $4.99   badge starter
           pack_30  30 spaces  $7.99   badge popular
           pack_300 300 spaces $47.99  badge best_value, list $79.99, 40% off
           no unlimited product
Mobile     submodule pinned f3a6fa2, untouched
```

---

## The screenshots

Captured at 390×844 @2x (iPhone-ish) unless noted, against the live site, in
English. Some are taller viewports so a whole scrolling page fits one image.

| file | screen |
|---|---|
| `01-home.png` | Home |
| `02-create-step1-upload.png` | Create — top of page (upload) |
| `02b-create-full-page.png` | Create — **whole page**, 390×2100 |
| `03-create-photo-chosen.png` | Create — after picking the example photo |
| `04-room-atmosphere-selected.png` | Create — room + atmosphere selected states |
| `05-loading.png` | Generation loading ("Preparing your photo") |
| `05-loading-t30.png` | The moment the first reveal appears |
| `06-first-reveal.png` | First Reveal (full-bleed before/after) |
| `07-design-session.png` | Design Session / "DESIGN WORKSPACE" |
| `08-full-reveal.png` | Full Reveal |
| `09-projects.png`, `09b-projects-tall.png` | Projects |
| `10-account-menu.png` | Account chip menu |
| `11-paywall.png`, `11b-paywall-tall.png` | Paywall (10/30/300 + the two mobile-only rows) |
| `12-home-desktop.png` | Home at 1440×900 |
| `13-projects-desktop.png` | Projects at 1440×900 |

### How they were taken

`cdp.mjs` (kept here) drives Chrome over the DevTools Protocol on port 9222.

**The trap it exists for**, which cost a previous session two phantom bugs: a
Chrome tab reports `visibilityState === "hidden"` even when focused, Flutter Web
drives every frame from `requestAnimationFrame`, and rAF is throttled there — so
the route changes and the canvas does **not** repaint. A screenshot then shows a
stale scene and looks exactly like a broken app. `shot` forces a 1px resize
before every capture, which relayouts outside rAF.

```bash
chrome.exe --remote-debugging-port=9222 --user-data-dir=<tmp> https://ayden-studio.web.app
node cdp.mjs shot out.png 390 844 2 mobile
node cdp.mjs click <cssX> <cssY> [waitMs]
node cdp.mjs nav <url> [waitMs]
node cdp.mjs eval "<js>"
```

Screenshot px → CSS px: divide by the dpr argument (2 for the mobile captures).
