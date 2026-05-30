# Monetization Readiness Audit — AIHomeArchitect

> **Audit scope**: identify the smallest production-ready monetization architecture we can build on top of the current MVP. **No code in this document, no implementation. Findings + recommendations only.**

**Audit date**: 2026-05-30
**Codebase commit**: `2093e5a` (post Wave 4.11e)
**Methodology**: 3 parallel codebase exploration agents (frontend auth, backend generation/session, dependencies) + this synthesis. Every claim cites a file + line number from the current commit.

---

## 1 — Current Architecture (evidence-based)

### Auth & identity
- **Anonymous Supabase auth only.** `Supabase.initialize(...)` runs at `frontend/lib/main.dart:21`. On first launch, `auth.signInAnonymously()` fires at `main.dart:30` and assigns a Supabase UUID.
- **No sign-in UI.** Searched `frontend/lib/` for `login / email / password / google / apple / oauth`: zero matches.
- **Identity persistence** = Supabase session stored in iOS Keychain / Android Keystore (managed by the `supabase_flutter` library — no custom hooks). **Reinstall clears it** → new anonymous user UUID → all prior projects orphaned.
- **"Sign Out"** button at `frontend/lib/features/profile/profile_screen.dart:142` returns the user to `/onboarding`; next app launch re-creates a fresh anonymous user.

### Generation flow
- **`/generate` endpoint** at `backend/main.py:832-850`. Accepts: `session_id, prompt, before_image_url, style_label, room_type, iteration` and other form params. **NO `user_id` parameter.**
- **Cost-sensitive call**: `await openai.images.edit(**edit_kwargs)` at `backend/main.py:1464`. Inside a retry loop (lines 1410-1563) with `profile.max_attempts` (PROD default = 3 → up to 3× cost per /generate POST).
- **Per-call cost**: $0.02-$0.19 depending on quality + size (per `backend/performance_observer.py:56-65`). Cost is logged for observability ONLY; never enforced (`"Cost estimates are for observability only — never used for billing"`, line 7).
- **Image persistence**: PNG → JPEG q=85 → uploaded to Supabase Storage bucket `"generated"` at `{session_id}/{timestamp}_{random}.jpg`, public URL returned (`backend/main.py:1614-1619`).
- **Message persistence**: `INSERT INTO messages` keyed by `session_id` (not `user_id`) at `backend/main.py:1803`.

### Session model
- A "session" = one design project (upload → atmosphere → multi-generation chat). `frontend/lib/data/models/project_model.dart`.
- **Local state** in SharedPreferences keyed `aih:session:{sessionId}` (`frontend/lib/core/services/session_persistence_service.dart:56`) — survives app restart, **cleared on reinstall**.
- **Remote state** in Supabase tables `sessions` + `messages` (schema at `supabase/schema.sql:10-38`), keyed by `user_id` + `id`. RLS policy at lines 99-116 restricts access to `auth.uid() = user_id`.

### Backend identity model
- The backend **does not authenticate users**. `/chat` and `/generate` accept any `session_id` and trust the client.
- All user-scoping happens via **Supabase Row-Level Security** at the database layer, NOT at the FastAPI layer.
- This means: if a `session_id` leaks or is guessable, the backend will happily generate images and write messages to it (the OpenAI call costs $0.02-$0.19; RLS only blocks the subsequent read).

### Monetization scaffolding (existing)
- `frontend/lib/features/sessions/buy_sessions_screen.dart` — UI mockup with hardcoded `'5'` available sessions (line 159), "Payment flow coming soon!" snackbar on the buy button (line 118). **Pure stub.**
- `backend/prompt_engine/product_knowledge.py` topic `billing` returns: *"Pricing details are being finalized for the Cambodia launch."* Placeholder copy.
- **Zero SDKs**: `pubspec.yaml` has no `in_app_purchase` / `purchases_flutter`. iOS `Info.plist` has no StoreKit declarations. Android `AndroidManifest.xml` has no `com.android.vending.BILLING`. Backend `requirements.txt` has no Stripe / RevenueCat. No `/webhook`, `/receipt`, `/subscription` endpoints exist.

---

## 2 — Authentication Risks

### Risk A — Reinstall = new user. **CRITICAL.**
Anonymous Supabase auth is stored in platform-private storage which iOS/Android clear on app uninstall. A user can:
1. Use 3 free generations.
2. Uninstall the app.
3. Reinstall.
4. Get assigned a fresh anonymous UUID.
5. Use 3 more free generations.
6. Repeat indefinitely.

**Cost exposure per abuse cycle**: 3 × $0.19 = **$0.57 per abuse cycle** at max quality. With high-volume abuse, an unprotected free trial is uneconomic.

### Risk B — Device-switch = new user.
A user on iPhone A cannot resume their projects on iPhone B. Not strictly a monetization risk, but pushing users to "real accounts" (Apple/Google) solves both this and Risk A simultaneously.

### Risk C — Backend trusts client-supplied `session_id`.
`/generate` does no ownership validation. If a `session_id` is leaked (e.g., screenshot, shared URL), an attacker can generate on someone else's session. Today this is cosmetic (RLS blocks reads); **with monetization, this becomes a quota-bypass vector** unless quotas are user-scoped on the SERVER side, not session-scoped.

### Risk D — No account recovery.
Without email or Apple/Google sign-in, a user who reinstalls cannot recover purchased entitlements either. This is the SAME mechanism as Risk A but inverted: a paying user loses their subscription, leading to refund requests and chargebacks.

### What changes are required for subscriptions
| Change | Required for | Effort |
|---|---|---|
| Add Apple / Google sign-in (mandatory before generation #1, OR soft-walled after free trial) | Risk A, Risk D | Medium |
| Pass `user_id` from frontend to `/chat` and `/generate` (via JWT in `Authorization` header) | Risk C | Small |
| Backend validates `user_id == sessions.user_id` BEFORE the OpenAI call | Risk C | Small |
| Persist user identity beyond app install (Supabase + sign-in token survives reinstall) | Risk A, Risk D | Comes free with Apple/Google sign-in |

---

## 3 — Usage Tracking Design

### Where to count generations
Three candidate locations:

| Location | File:line | Pros | Cons |
|---|---|---|---|
| Frontend Generate button | `chat_screen.dart` | Instant feedback | **Trivially defeatable** by API replay |
| Backend `/generate` entry | `backend/main.py:832` | Pre-cost validation | Counts attempts not successes |
| **Backend just BEFORE `openai.images.edit`** | `backend/main.py:1464` | **Counts paid calls** | Slightly later in flow — minimal latency |
| Backend POST-generation persistence | `backend/main.py:1803` | Counts successful generations | If decremented AFTER success, fails-open on errors |

**Recommendation**: Decrement quota at `main.py:1464` *(right before the OpenAI call)*, then increment a `usage_log` row AFTER success persistence at `main.py:1803`. This pattern (reserve-then-confirm) prevents both double-charge and free-on-error.

### Where to store usage
**New Supabase table** `usage_log`:

| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK auth.users | Indexed |
| session_id | uuid FK sessions | Indexed |
| call_type | text | `generate` \| `chat` (chat is free for now) |
| cost_usd_estimate | numeric | From `performance_observer.py` |
| created_at | timestamptz | Default `now()` |

Plus a derived view `user_quota` (`user_id`, `generations_this_month`, `generations_lifetime`) for fast read at quota-check time.

### Where to enforce quotas
At `backend/main.py:1462` (one line before the OpenAI call), call `check_quota(user_id) → raise HTTPException(402, "Out of quota — see paywall")`. This is the **only place** quota enforcement makes economic sense (every other location either over-counts or under-counts cost).

Cache the user's remaining quota in Redis (or in-memory dict with 60s TTL) — DB query on every generate is OK at MVP scale (~100 RPM) but precomputing on subscription change is cheap defense.

---

## 4 — Subscription Readiness

### Current state
| Item | Status |
|---|---|
| Flutter `in_app_purchase` package | **ABSENT** |
| Flutter `purchases_flutter` (RevenueCat) | **ABSENT** |
| iOS StoreKit capability in `Info.plist` / entitlements | **ABSENT** |
| Android `com.android.vending.BILLING` permission | **ABSENT** |
| Backend Stripe / RevenueCat / receipt validation SDK | **ABSENT** |
| `/webhook` or `/receipt` endpoint in `backend/main.py` | **ABSENT** |
| Product IDs (`com.aihomearchitect.subscription.*`) | **ABSENT in entire codebase** |

**Verdict**: Greenfield. No partial integration to untangle, no SDK conflicts.

### Recommendation: **RevenueCat**

Two viable paths:

| Path | Effort | Pro | Con |
|---|---|---|---|
| **A. Native StoreKit 2 (iOS) + Google Play Billing (Android)** | 2-3 weeks | No third-party fee | Two codepaths, you maintain receipt validation server-side |
| **B. RevenueCat** | 3-5 days | Single SDK both platforms; webhooks + dashboards built-in; free tier supports first 10K MRR | $399/mo at scale (after $2.5K MTR free tier) |

**Recommend Path B (RevenueCat)** for V1 launch. Reasons:
- 5-day integration vs 2-3 weeks for native — earlier revenue capture
- Webhooks → backend can update `users.entitlement_tier` without parsing Apple receipts
- Cambodia launch friendly: handles Khmer Riel pricing if you ever localize (Apple App Store does this natively too)
- Migration to native later is straightforward (entitlement state already lives in your DB, RevenueCat just stops syncing)

**Free tier** (RevenueCat): up to $2,500 MTR — covers the first ~250 paying users at $9.99/mo. **Sufficient for first 6 months post-launch.**

### What needs to ship
1. `purchases_flutter: ^7.x` in `pubspec.yaml`.
2. iOS `Info.plist` StoreKit declarations + `Runner.entitlements` file (currently missing — confirmed by codebase audit).
3. Android `AndroidManifest.xml` BILLING permission + `play_billing_library` Gradle dep.
4. Backend `/webhooks/revenuecat` endpoint (Webhook URL configured in RC dashboard). On `INITIAL_PURCHASE` / `RENEWAL` / `CANCELLATION`, update `users.entitlement_tier` column.
5. App Store Connect + Google Play Console: product IDs (`monthly`, `annual`) + RC dashboard entitlement mapping.

---

## 5 — Watermark Strategy

### Backend watermark (recommended)

**Where**: `backend/main.py:1575-1599` (the JPEG re-encoding step, right before upload to Supabase Storage at line 1614).

After `Pillow` re-encodes the OpenAI PNG to JPEG q=85, composite a watermark layer (`Pillow.Image.alpha_composite`) **conditional on the user's entitlement tier**:
- `tier == 'free'` → composite "AIHomeArchitect" wordmark in bottom-right corner at ~12% opacity.
- `tier == 'paid'` → no watermark.

**Pros**:
- Cannot be bypassed by screenshot before render (the watermark IS the file).
- Free-tier user shares the image → wordmark appears in their share → organic growth signal.
- Removal-on-upgrade is trivial: the next `/generate` call after upgrade returns a clean image.
- Existing images (free-tier-rendered) stay watermarked retroactively — no historical re-encoding required.

**Cons**:
- Backend latency +50-100 ms for the composite step.
- Free users with creative Photoshop skills can crop/remove (acceptable — the deterrent is friction, not cryptographic protection).

### Frontend watermark (NOT recommended)

Renders a watermark `Stack` overlay on top of the result image in `chat_screen.dart`. **Defeatable by**: screenshot the screen, share that. **Worse**: defeatable by any developer who reads the public Supabase Storage URL directly.

### Image persistence implications
- Supabase Storage bucket `generated` is currently **public**. Watermarked images served from public URLs → fine for free tier.
- For paid tier going forward, consider switching to **signed URLs with 24-hour expiry** so the file URL isn't infinitely shareable. NOT required for V1.

---

## 6 — Free Trial Recommendation

### Evaluation of stated options

**Option A — 3 free generations**
- Pros: simple to count, simple to communicate, low friction
- Cons: trivially defeatable by reinstall (Risk A) → unbounded cost if abuse goes viral
- Abuse resistance: **near zero** without account linking
- Conversion lever: only 3 attempts — high pressure but may feel rushed
- Implementation: ~1 day backend + ~2 days frontend paywall

**Option B — 1 room + 2 atmospheres**
- Pros: more generous, shows multi-atmosphere range
- Cons: "1 room" semantics fragile — what if user uploads → discards → uploads again? Counts as 1 or 2 rooms?
- Abuse resistance: same as Option A unless account linking added
- Conversion lever: more generous → may delay purchase decision
- Implementation: ~3-4 days (room-completion state machine, atmosphere counter, edge cases)

### Recommended: Option C — **2 free generations BEHIND mandatory Apple/Google sign-in**

The mandatory sign-in BEFORE generation #1 is the most important architectural decision in the entire monetization layer.

**Rationale**:
- **Eliminates Risk A entirely.** Apple ID / Google account is the same across reinstalls. Trial reset requires the user to create a new Apple/Google account — high friction, statistically negligible.
- **Cost exposure per abusive user**: 2 × $0.19 = **$0.38 max**. Affordable even if abuse is 10× normal rate.
- **2 generations is enough to show value**: V1 + 1 refinement = the core product loop. Any user who doesn't convert after seeing those two outputs isn't going to.
- **Mandatory sign-in adds friction up-front, removes friction downstream**: no "save your work?" anxiety, no abandoned projects.

### Trade-offs to surface
- Mandatory sign-in increases FTUE abandonment rate. Industry benchmarks: ~15-25% drop-off at hard sign-in walls.
- Mitigations: Apple ID is one tap on iOS (cheapest sign-in in any market), Google sign-in is one tap on Android. Provide BOTH on each platform.
- **Don't** offer email-only sign-in for V1 — adds a Supabase Auth email confirmation flow which is its own friction stack.

### Implementation complexity
| Phase | Effort |
|---|---|
| Apple Sign-In SDK + UI screen | 1 day |
| Google Sign-In SDK + UI screen | 1 day |
| Backend `user_id` propagation from JWT | 0.5 day |
| Quota table + check at generate | 1 day |
| Paywall sheet on quota exhaustion | 1.5 days |
| **Total** | **~5 days** for trial + quota infrastructure |

### Alternative if mandatory sign-in is rejected by product
**Soft-walled hybrid**: 1 anonymous generation as "preview", mandatory sign-in BEFORE generation #2. Captures the surprise-and-delight first-vision moment with zero friction, then walls. Lower initial abandonment but reintroduces partial Risk A exposure (1 generation × $0.19 = $0.19 per uninstall/reinstall cycle — acceptable).

---

## 7 — Proposed Wave 5.17 Roadmap (Monetization Foundation)

**Goal**: smallest production-ready monetization layer, shippable in ~3 weeks of focused work.

### Wave 5.17a — Account foundation (~5 days)
- Add Apple Sign-In + Google Sign-In to Flutter
- Replace `signInAnonymously()` with a sign-in gate on first launch
- Add `users.entitlement_tier` column to Supabase `auth.users` metadata (default `free`)
- Pass JWT in `Authorization` header on every `/chat` and `/generate` call
- Backend validates JWT signature + extracts `user_id`
- Backend enforces `session.user_id == jwt.user_id` BEFORE the OpenAI call

### Wave 5.17b — Quota + usage telemetry (~3 days)
- Create `usage_log` table (schema in §3 above)
- Create `user_quota` view (current month + lifetime counts)
- Add `check_quota(user_id, tier)` call at `backend/main.py:1462` (one line before OpenAI)
- On quota exhaustion: return HTTP 402 with `{"detail": "out_of_quota", "tier": "free", "upgrade_url": "..."}`
- Frontend catches 402 → opens paywall sheet

### Wave 5.17c — RevenueCat integration (~5 days)
- `purchases_flutter` in pubspec
- iOS StoreKit capability, Android BILLING permission
- App Store Connect + Google Play Console product setup (`monthly $9.99`, `annual $79.99` for example — pricing TBD)
- RevenueCat dashboard: entitlements `pro`, products linked
- Frontend paywall sheet calls RC `Purchases.purchasePackage(...)`
- Backend `/webhooks/revenuecat` endpoint updates `users.entitlement_tier` on `INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `BILLING_ISSUE`, `EXPIRATION`

### Wave 5.17d — Free-tier watermark (~2 days)
- Backend composites watermark in JPEG encode step (`backend/main.py:1575-1599`)
- Conditional on `users.entitlement_tier == 'free'`
- Watermark asset (PNG transparent) in `backend/assets/watermark.png`

### Wave 5.17e — Launch polish (~3 days)
- "Restore Purchases" button on paywall (RevenueCat one-liner)
- Receipt validation hardening (RevenueCat handles, but verify webhook auth signature)
- Paywall A/B test wiring (skip for V1 — defer)
- Update `product_knowledge.py` billing topic with real pricing + cancellation copy
- Cambodia-specific: localize prices to KHR via App Store regional pricing tier

**Total: ~18 days of focused engineering.** Adds 5 new Supabase tables/columns, 1 new backend endpoint, 3 new frontend screens (sign-in, paywall, restore), 1 SDK integration.

---

## 8 — Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **Reinstall trial reset** | CRITICAL | Mandatory Apple/Google sign-in (Wave 5.17a). Without this, every other layer of monetization is bypassable. |
| **Session ID forgery** | HIGH | Pass JWT + validate `session.user_id == jwt.user_id` at `main.py:1462`. Without this, quota is per-session not per-user, defeatable by spawning sessions. |
| **No usage telemetry** | HIGH | `usage_log` table (Wave 5.17b). Without this, you can't even DEBUG monetization issues, let alone enforce quotas. |
| **Free-tier abuse via shared accounts** | MEDIUM | Mandatory sign-in + 2-3 free generations only. Sharing an Apple ID is high friction for the abuser. |
| **Watermark removal via Photoshop** | LOW | Accept this. The watermark deters casual sharing, not determined removal. |
| **Apple App Store rejection (V1)** | LOW-MEDIUM | Make sure paywall offers "Restore Purchases" + lists subscription terms + auto-renewal + cancellation copy per App Store Review Guideline §3.1.2. Standard RevenueCat boilerplate covers this. |
| **Cambodia market pricing sensitivity** | MEDIUM | Use App Store regional pricing tiers (tier 1 in Cambodia ≈ $1 USD-equivalent in KHR). Localize the paywall copy via existing l10n system (`frontend/lib/core/l10n/translations/km.dart`). |
| **Cost spike from a viral abuser before sign-in lands** | HIGH if not addressed | If sign-in can't ship before public launch, add CRUDE rate limit at backend (10 generations / IP / 24h) as temporary defense. |
| **RevenueCat webhook auth bypass** | MEDIUM | Verify RC webhook signatures on `/webhooks/revenuecat`. Standard practice, ~30 lines of code. |
| **Refund handling** | MEDIUM | On RC `CANCELLATION` or `BILLING_ISSUE` webhook, immediately downgrade `entitlement_tier`. No grace period for V1 — add later if churn data justifies. |

---

## 9 — Recommended Architecture (the smallest production-ready system)

```
┌──────────────────────────────────────────────────────────────────────────┐
│  FLUTTER FRONTEND                                                        │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │ 1st launch                                                         │ │
│  │   → Sign-In Screen (Apple ID + Google) — MANDATORY                 │ │
│  │   → On success: Supabase Auth (replacing signInAnonymously)        │ │
│  │   → JWT cached in iOS Keychain / Android Keystore                  │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │ Every /generate or /chat call:                                     │ │
│  │   → Authorization: Bearer <supabase_jwt>                           │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │ On HTTP 402 from /generate:                                        │ │
│  │   → Paywall sheet (RevenueCat-rendered)                            │ │
│  │   → Purchase → RC SDK → Apple/Google billing → RC webhook          │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  FASTAPI BACKEND                                                         │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │ /generate:                                                         │ │
│  │   1. Validate JWT signature → extract user_id                      │ │
│  │   2. Validate session.user_id == user_id  (NEW)                    │ │
│  │   3. check_quota(user_id, tier)  (NEW)                             │ │
│  │       → if exhausted: raise 402                                    │ │
│  │   4. openai.images.edit(...)                                       │ │
│  │   5. composite_watermark_if_free(jpeg, tier)  (NEW)                │ │
│  │   6. upload to Supabase Storage                                    │ │
│  │   7. INSERT INTO usage_log (NEW)                                   │ │
│  │   8. INSERT INTO messages                                          │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │ /webhooks/revenuecat:  (NEW)                                       │ │
│  │   - verify webhook signature                                       │ │
│  │   - INITIAL_PURCHASE / RENEWAL → users.entitlement_tier = 'pro'    │ │
│  │   - CANCELLATION / EXPIRATION → 'free'                             │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  SUPABASE                                                                │
│   - auth.users (existing) + entitlement_tier column (NEW)                │
│   - sessions (existing)                                                  │
│   - messages (existing)                                                  │
│   - usage_log (NEW) — user_id, session_id, call_type, cost, created_at  │
│   - Storage bucket: generated (existing)                                 │
└──────────────────────────────────────────────────────────────────────────┘
```

### Summary of additions
- **3 new database objects**: `usage_log` table, `user_quota` view, `entitlement_tier` column on auth.users
- **1 new backend endpoint**: `/webhooks/revenuecat`
- **3 backend insertion points** in `main.py /generate`: quota check (line 1462), watermark conditional (line 1575), usage_log INSERT (line 1803)
- **3 new frontend screens**: Sign-In, Paywall, Restore Purchases
- **2 new SDKs**: `purchases_flutter`, `sign_in_with_apple` / `google_sign_in`
- **Zero changes to**: prompt engine, atmosphere DNA, refinement memory, Wave 4.11 intelligence stack

---

## Final Recommendation

# ARCHITECTURE CHANGES REQUIRED FIRST

### Justification

The MVP cannot support subscriptions in its current form. Three foundational gaps must be closed BEFORE any paywall/quota/trial logic ships:

1. **User identity must survive reinstall.** Current anonymous-only auth means any free trial is bypassable in <60 seconds (uninstall → reinstall). This is not a polish issue — it's the load-bearing assumption every other monetization piece depends on. **Requires Apple/Google sign-in (Wave 5.17a).**

2. **Backend must know who the user is at the OpenAI call site.** Today `/generate` accepts any `session_id` and trusts the client. Quota enforcement is only meaningful if it's user-scoped at the server side, before the paid call. **Requires JWT propagation + session-ownership validation (Wave 5.17a).**

3. **Usage telemetry must exist.** No table records "user X generated N images". Without this, quotas have nothing to check against and you can't debug monetization issues. **Requires `usage_log` table + quota view (Wave 5.17b).**

### Why this is good news

These three changes are **small, well-scoped, and shippable in ~8 days** (Wave 5.17a + b combined). After they land, the remaining monetization scope (RevenueCat integration, watermark, paywall UX) is straightforward SDK plumbing — another ~10 days.

**Total to first paid subscription**: ~3 weeks of engineering, properly sequenced.

The dependencies are zero-conflict: no partial SDK integrations to untangle, no abandoned billing code to remove, no API contracts to break. The MVP is structurally ready to ACCEPT monetization once the auth + telemetry foundations are in place.

### Suggested commit cadence

| Wave | Scope | Days | Ship-blocking? |
|---|---|---|---|
| 5.17a | Apple/Google sign-in + JWT propagation | 5 | YES — without this no other layer is safe |
| 5.17b | Quota + usage_log + 402 handling | 3 | YES — without this paywall can't gate |
| 5.17c | RevenueCat integration | 5 | YES — without this no revenue |
| 5.17d | Free-tier watermark | 2 | NO — can ship after launch |
| 5.17e | Restore purchases + receipts + l10n | 3 | YES for App Store approval |

**Order matters**: a-b-c-e is the minimum-viable launch sequence. d (watermark) is optional and can land in Wave 5.18.

### Open questions for product before Wave 5.17 starts

1. **Subscription pricing**: $9.99/mo? $4.99/mo? Cambodia regional pricing tier?
2. **Trial generations**: 2 (recommended) vs 3 vs 5?
3. **Mandatory sign-in vs soft-walled** (1 anonymous generation then sign-in)?
4. **Family sharing**: enable in App Store Connect? (Apple recommends; doubles user reach but requires receipt parsing changes)
5. **Free tier in perpetuity?** (e.g., free users keep 2 lifetime generations forever — good for product virality) **vs** trial-then-paywall-or-nothing?

These are product/business decisions, not architectural decisions. Wave 5.17 can start once 1, 2, 3 are answered.

---

*Audit performed by: Claude Opus 4.7 + 3 parallel exploration agents.
Codebase commit: `2093e5a` (post Wave 4.11e).
No code modified. No commits. No implementation. Audit only.*
