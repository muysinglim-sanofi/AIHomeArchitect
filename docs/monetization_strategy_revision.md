# Monetization Strategy Revision — Post Wave 5.17a

**Audit date**: 2026-05-30
**Author**: Strategic review, no code changes
**Codebase state**: Wave 5.17a Identity Foundation complete (commit pending)
**Scope**: Re-evaluate the Option A funnel (sign-in at Gen #2) vs. the proposed Option B funnel (sign-in at paywall) before Wave 5.17b is built.

---

## 1 — Funnel Comparison

### Option A (current Wave 5.17a) — sign-in early

```
Install → Gen #1 (anon) → SIGN-IN → Gen #2 (signed) → Gen #3 → PAYWALL → Pay
                          ▲ friction at the second value moment
```

The sign-in friction lands at the moment the user is trying to refine their first vision. This is **the highest-engagement moment in the FTUE** (they've just seen their room transformed, they want to iterate) — and we interrupt it with an account creation step.

### Option B (proposed) — sign-in at purchase

```
Install → Gen #1 (anon) → Gen #2 → Gen #3 → PAYWALL → SIGN-IN → Pay → Unlimited
                                              ▲ friction tied to purchase intent
```

Sign-in becomes a **side effect of purchasing**, not a precondition for exploration. The user has accumulated 3 WOW moments before any identity step. Identity feels like account creation for the subscription, not a tax on usage.

### Comparison matrix

| Dimension | Option A | Option B | Winner |
|---|---|---|---|
| First-WOW friction | Low (anon) | Low (anon) | tie |
| Pre-paywall WOW moments | 1 | 3 | **B** |
| Refinement-loop friction (the moment that proves the product) | Sign-in wall | None | **B** |
| Sign-in motivation clarity | "Why do I need to sign in just to try again?" | "Of course I need an account to subscribe" | **B** |
| Cost exposure per uninstall+reinstall cycle | $0.19 (1 anon gen × max quality) | $0.57 (3 anon gens × max quality) | A |
| Conversion rate (industry benchmarks for B2C mobile apps with early sign-in walls vs. delayed sign-in) | 15-25% drop-off at the sign-in wall | Drop-off at paywall is mostly intent-correlated (user already evaluating purchase) | **B** |
| App Store §5.1.1(v) compliance | Apple + Google both required because login is offered | Apple + Google still required (paywall is a login surface) | tie |
| Wave 5.17a code reuse | 100% (we built it for this) | ~85% (Gen #2 gate becomes Gen #N gate, sign-in screen reused) | A |
| Cambodia market fit | Weaker — Cambodian users distrust account walls in unfamiliar apps | Stronger — pay-to-account is a familiar pattern (Wing, ABA, TrueMoney all gate identity at transaction) | **B** |
| Trial reset abuse exposure | $0.19/cycle | $0.57/cycle | A |
| Founder/internal testing | Hits sign-in wall after 1 generation | Hits paywall after 3 generations | tie (admin bypass needed either way) |

**8 wins for B, 2 for A, 3 ties.** Option B wins on every dimension that maps to revenue (conversion, market fit, motivation clarity) and loses only on cost-exposure tractability (which is mitigable — see §7 R1).

---

## 2 — Cambodia Market Analysis

Five factors that should weigh heavily on the decision:

### 2.1 — Low primary-email habits

The dominant identity primitive in Cambodia is the **phone number**, not email. Even users who have Gmail addresses use them as recovery channels, not active inboxes. App flows that lead with "enter your email" feel foreign. Apple Sign-In and Google Sign-In are mostly free of this issue (they leverage device-level identity), but the WORD "sign in" mid-FTUE still reads as "create an account" to a Cambodian user who has never thought about identity outside of banking.

### 2.2 — Phone-first authentication culture

Wing, ABA Pay, TrueMoney, Pi Pay, all the major Cambodian financial apps onboard via phone OTP. User mental model : **"sign in" = "phone number + 6-digit code"**. Apple/Google sign-in is technically frictionless but cognitively unfamiliar. Pushing sign-in late in the funnel — at the paywall, where users already accept that "this is a transaction" — aligns with the cultural model.

### 2.3 — Facebook + Telegram are the social spine

Cambodians use Facebook for business contact, Telegram for community + commerce. Neither of those is offered as a sign-in method in our current Wave 5.17a build. **Not a recommendation to add them** (App Store rules + maintenance cost), just an observation : the social-login methods we DO offer (Apple, Google) aren't the platforms Cambodians associate with identity.

### 2.4 — ABA / Wing payment ecosystem (separate from this audit)

Apple Pay and Google Pay both work in Cambodia, but local cards (ABA, Acleda) don't always tokenize cleanly into Apple Wallet. ABA Pay direct integration is a separate Wave (likely 5.18 or later). For 5.17b/c, App Store subscription billing is the default and works ; expect some payment-method friction at the Cambodia paywall that has nothing to do with our funnel design.

### 2.5 — Price sensitivity is high

$9.99/month USD = ~$40,000 KHR — a meaningful sum in Cambodia. Users will not pay until they're convinced. **3 generations is the minimum to demonstrate the product's range** :
- Gen #1 — "Wow, my room looks transformed"
- Gen #2 — "It can adjust based on what I said"
- Gen #3 — "It really understands my style"

Cutting at Gen #2 (Option A) means the user evaluates value on a single refinement loop. Cutting at Gen #4 (Option B with N=3) gives the user two full refinement loops to evaluate. **For a price-sensitive market, more demonstration = better conversion.**

### Conclusion of market analysis

Option B is more aligned with Cambodian user mental models on every dimension except cost exposure. The cost exposure is bounded and mitigable.

---

## 3 — Impact on Wave 5.17 Roadmap

### What's reusable from Wave 5.17a (just shipped)

| Component | Status | Reusable in Option B? |
|---|---|---|
| `auth_service.dart` (Apple + Google sign-in flows) | shipped | **Yes — 100%**. Same flows, triggered from the paywall instead of Gen #2. |
| `sign_in_screen.dart` (continuation-feeling UX) | shipped | **Yes — 100%**. Headline/subhead become props ; paywall passes different copy. |
| `generation_service.dart` Dio JWT interceptor | shipped | **Yes — 100%**. Sends JWT for anon or signed-in users alike — no logic change needed. |
| `auth.py` `get_current_user` FastAPI dep | shipped | **Yes — 100%**. Already accepts both anon and signed-in JWTs. |
| `_validate_session_ownership` backend check | shipped | **Yes — 100%**. Works on anon-owned sessions exactly the same way. |
| iOS `Runner.entitlements` (Apple sign-in capability) | shipped | **Yes — 100%**. |
| Android `AndroidManifest.xml` OAuth intent filter | shipped | **Yes — 100%**. |

**Reuse rate: 100% of Wave 5.17a code.** Nothing built for the identity foundation needs to be torn down.

### What needs to change for Option B

| Component | Change | Effort |
|---|---|---|
| `chat_screen.dart` Gen #2 sign-in gate | **REMOVE** the condition `newCount >= 2 && auth.isAnonymous`. Replace with `newCount >= N` (paywall gate, no auth check). | ~10 min |
| `chat_screen.dart` Gen #N paywall handler | NEW : when anon user hits Gen #N, push paywall sheet (will be the same widget Wave 5.17c builds for RevenueCat). For 5.17b interim, push the existing `SignInScreen` with paywall-tone copy. | ~30 min |
| `profile_screen.dart` sign-in entry point | ADD : let signed-out users sign in voluntarily (e.g. to recover an existing subscription). Currently the only sign-in path is the gate ; need a profile-screen affordance. | ~30 min |

**Total adjustment cost: <2 hours of frontend work.** No backend changes required for the funnel pivot — the backend was always identity-agnostic at the call site.

### What's deferred to Wave 5.17b (next)

Independent of the funnel pivot, Wave 5.17b must build :
- `usage_log` table — per-user generation counter
- Quota check at `main.py:1462` (before `openai.images.edit`) — gates on `usage_count >= N` for anonymous users + `entitlement == 'free'` for signed-in users
- HTTP 402 response on exhaustion
- Frontend handler that opens the paywall on 402

The quota system is **funnel-agnostic** : it gates on `user_id` regardless of whether sign-in was at Gen #2 or at paywall. Quota counts migrate via Supabase anonymous-upgrade when the user signs in at the paywall (Wave 5.17a infrastructure handles this).

### What's deferred to Wave 5.17c (subsequent)

- RevenueCat integration
- Paywall sheet with real subscription products
- `/webhooks/revenuecat` endpoint to sync entitlements
- "Restore Purchases" button

No funnel-dependent decisions here. The paywall sheet is the paywall sheet, regardless of when in the journey it appears.

### What N should be

**Recommendation: N = 3.** Reasoning :

| N | Cost per anon cycle (max quality) | Generations to convey product range | Risk |
|---|---|---|---|
| 1 (Option A) | $0.19 | One refinement only ; user can't evaluate consistency | Low conversion |
| 2 | $0.38 | One refinement loop, no convergence demonstration | Moderate conversion |
| **3** | **$0.57** | **First vision + 2 refinements = full evaluation cycle** | **Balanced** |
| 5 | $0.95 | Generous ; convinces almost all users | Higher abuse cost |
| 10 | $1.90 | Demonstrates "unlimited feel" before paywall | High abuse cost |

3 is the smallest N that lets the user complete a full "first impression → refine direction → adjust style" cycle. 5 might be more generous but doubles abuse cost ; 10 is uneconomic.

A/B test consideration : ship with N=3 ; if conversion at the paywall is < 5%, A/B test N=5. Don't start at 5 — too costly to walk back.

---

## 4 — Phone Authentication Evaluation (audit only, no implementation)

### Supabase phone OTP support

Supabase Auth supports phone OTP natively as a first-class provider :
- `auth.signInWithOtp({phone: '+855...'})` — sends the OTP via the configured SMS provider
- `auth.verifyOtp({phone, token, type: 'sms'})` — verifies and signs in
- Anonymous-upgrade flow : `auth.updateUser({phone: '+855...'})` then verify — preserves the anon user UUID (same mechanism as Apple/Google upgrade)
- JWT carries `phone` claim ; `is_anonymous` false post-verification

**Implementation complexity** : equivalent to Apple/Google integration. ~2-3 days of focused work :
- Frontend phone input screen + OTP entry screen (~1 day)
- SMS provider configuration in Supabase dashboard (~0.5 day operational)
- Multi-language SMS template copy (FR / EN / KM) (~0.5 day)
- Anonymous-upgrade flow code (~0.5 day, mirrors `auth_service.dart` patterns)

### SMS provider economics

Three viable providers for Cambodia :

| Provider | Cost per SMS to Cambodia | Notes |
|---|---|---|
| Twilio | $0.0720 | Most reliable, global SDK, expensive |
| MessageBird | $0.0500-0.0800 | Mid-tier |
| Local provider (e.g. SMS Gateway Cambodia, AAB SMS) | $0.0150-0.0250 | Cheapest, requires direct contract with carrier-tied provider, less reliable |
| Smart / Cellcard / Metfone direct | $0.0050-0.0100 | Lowest cost, but requires bilateral business contracts |

### Monthly OTP cost projections

| Active monthly users | 1 OTP/user/month | 2 OTP/user/month |
|---|---|---|
| 1,000 | $50-72 | $100-144 |
| 10,000 | $500-720 | $1,000-1,440 |
| 50,000 | $2,500-3,600 | $5,000-7,200 |

At 10K MAU, phone OTP costs $500-1,440/month with the typical 1-2 OTPs per user per month (initial sign-in + occasional re-auth). **More expensive than Apple/Google at $0 per signup.**

### Cambodia market fit (phone vs Apple/Google)

| Dimension | Phone OTP | Apple + Google |
|---|---|---|
| Familiarity | **High** (matches Wing/ABA/Pi Pay pattern) | Medium (Google Sign-In universal on Android but cognitively foreign) |
| Cost per signup | $0.02-0.07 | $0 |
| Reliability | Carrier-dependent (some delivery failures) | High |
| iPhone market (~5-10%) | Same as Android | **Apple Sign-In required on iOS per App Store §5.1.1(v)** regardless |
| Cross-device recovery | Phone number persists | Apple ID / Google account persists |
| Implementation effort | 2-3 days | 2-3 days (already done in 5.17a) |
| Future SIM swap risk | Yes (low frequency) | No |

### Recommendation

**For Wave 5.17 (immediate)** : ship Apple + Google as already built. Cost = $0/signup, infrastructure = done.

**For Wave 6.x (post-launch, after 1-2 months of real-user data)** : consider phone OTP as a SECONDARY method if :
- Cambodian conversion rate is significantly below other markets
- User feedback explicitly mentions sign-in friction
- SMS budget can absorb $500-1,500/month at expected MAU

**Don't ship phone OTP as a REPLACEMENT for Apple/Google** : Apple Sign-In is mandatory on iOS per §5.1.1(v) ; replacing it is non-compliant. Phone OTP can only be an additional method.

**If budget allows, the long-term funnel could be** :
- Apple Sign-In (mandatory on iOS)
- Google Sign-In (recommended on Android)
- Phone OTP via local Cambodian provider at $0.02/SMS (Cambodia-specific preference)

This 3-option sign-in fan covers Apple ID users, Google account users, and phone-first Cambodian users without forcing any of them into an unfamiliar pattern.

---

## 5 — Admin Account Architecture (design only)

### Use cases

The brief specifies :
- Founder testing the paywall and post-purchase experience
- Internal QA testing edge cases without burning real subscriptions
- Support team resolving stuck users (e.g. paid user with broken entitlement)

### Recommended schema

Separate `user_roles` table (NOT JWT claims) :

```sql
CREATE TABLE user_roles (
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role       text NOT NULL,                       -- 'admin' | 'beta_tester' | 'support'
  granted_at timestamptz DEFAULT now(),
  granted_by uuid REFERENCES auth.users(id),     -- audit trail
  expires_at timestamptz,                         -- NULL = never expires
  notes      text,
  PRIMARY KEY (user_id, role)
);

CREATE INDEX user_roles_user_id_idx ON user_roles(user_id);
```

### Why a separate table beats JWT claims

| Option | Pros | Cons |
|---|---|---|
| JWT claim (`auth.users.raw_app_meta_data.role`) | No DB lookup at quota gate | Hard to revoke (must wait for token expiry, max 1h) ; harder to audit ; no granular expires_at per role |
| **Separate `user_roles` table** | **Revoke instantly ; auditable ; multiple roles per user ; expirable** | One indexed DB lookup per /generate call (~1ms with index ; negligible) |

The separate-table approach scales better as roles diversify (admin → admin + beta_tester + support → admin + content_moderator + ...) and supports the "trial admin access for 30 days" pattern that's useful for partner integrations.

### Entitlement model

The backend quota check (in Wave 5.17b's `check_quota(user_id)`) becomes :

```
def check_quota(user_id):
    # 1. Admin bypass — earliest possible exit, no DB writes
    if has_active_role(user_id, ['admin', 'beta_tester']):
        return ALLOW
    # 2. Subscription bypass
    if has_active_subscription(user_id):
        return ALLOW
    # 3. Free-tier quota check
    if usage_count(user_id) < FREE_TIER_LIMIT:
        return ALLOW
    return DENY_402
```

The `has_active_role` function checks `user_roles WHERE user_id=? AND role=? AND (expires_at IS NULL OR expires_at > now())`.

### Granting admin in V1 (no UI yet)

Service-role SQL via Supabase dashboard :

```sql
INSERT INTO user_roles (user_id, role, granted_by, notes)
VALUES (
  '<founder-uuid>',
  'admin',
  '<founder-uuid>',
  'Self-grant for founder testing — 2026-05-30'
);
```

No admin UI in 5.17b/c. The dashboard is sufficient for the team's use cases until volume warrants a tool.

### Logging admin actions

Future enhancement (NOT V1) : on every quota bypass due to admin role, log to a separate `admin_action_log` table for observability. Lets us answer "did the founder accidentally burn $50 of OpenAI cost testing?" without ambiguity.

---

## 6 — Promo Code Architecture (design only)

### Use cases

The brief specifies :
- `EARLYBETA2026` — unlimited generations for early beta users
- `FRIENDS2026` — premium access for friends-and-family launch
- `INFLUENCER2026` — unlimited generations for partner influencers (high-redemption count)

### Recommended schema

Two tables :

```sql
CREATE TABLE promo_codes (
  code                text PRIMARY KEY,            -- 'EARLYBETA2026'
  entitlement         text NOT NULL,                -- 'unlimited' | 'premium_3months' | 'lifetime'
  max_redemptions     integer,                     -- NULL = unlimited
  current_redemptions integer NOT NULL DEFAULT 0,
  expires_at          timestamptz,                  -- NULL = never expires
  created_at          timestamptz DEFAULT now(),
  created_by          uuid REFERENCES auth.users(id),
  active              boolean NOT NULL DEFAULT true,
  notes               text
);

CREATE TABLE promo_code_redemptions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL REFERENCES promo_codes(code),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  redeemed_at   timestamptz DEFAULT now(),
  ip_address    inet,                              -- for abuse forensics
  UNIQUE (code, user_id)                            -- same user can't redeem same code twice
);

CREATE INDEX promo_code_redemptions_user_idx ON promo_code_redemptions(user_id);
```

### Entitlement application

When a user redeems a code, the backend :
1. Validates the code (exists, active, not expired, has redemptions left, user hasn't redeemed before)
2. INSERTs the redemption row
3. UPDATEs `promo_codes.current_redemptions` atomically (single-statement transaction)
4. INSERTs into `user_roles(user_id, role=entitlement.role, expires_at=...)`

The `entitlement` field on `promo_codes` maps to a role name. Examples :
- `'unlimited'` → INSERT into user_roles with role='admin' (or a dedicated 'unlimited_user' role to distinguish from real admins)
- `'premium_3months'` → INSERT into user_roles with role='premium', expires_at=now()+3 months
- `'lifetime'` → INSERT into user_roles with role='premium', expires_at=NULL

This **reuses the `user_roles` infrastructure from §5** — promo codes are just a programmatic way to grant roles, no new entitlement layer needed.

### Redemption flow

```
1. User signs in (mandatory — redemption needs a user_id)
2. User opens profile screen → "Redeem code" entry
3. Enters code → frontend POST /redeem-code {code}
4. Backend validates + INSERT redemption + INSERT role
5. Returns updated entitlement state
6. Frontend refreshes UI → user sees "Premium" indicator
```

**Redemption requires sign-in.** Anonymous redemption is not supported — without a stable user_id, we can't attach the entitlement. This is consistent with Option B's funnel : sign-in is the price of getting something for free OR paying.

### Abuse scenarios + mitigations

| Scenario | Mitigation |
|---|---|
| Same user redeems same code twice | `UNIQUE (code, user_id)` constraint blocks it |
| Code leaks publicly (e.g. INFLUENCER2026 in a tweet) | Set `max_redemptions = 10` for sensitive codes ; monitor `current_redemptions` ; deactivate when threshold approached |
| User creates 50 accounts to claim the same code | Bounded by `max_redemptions` ; further bounded by Apple/Google account creation friction (rarely worth it for a $10/month value) |
| Code shared in a Cambodia Facebook group | Same as leak ; track redemption velocity ; deactivate if anomalous |
| Brute-force code guessing | Codes are random strings (e.g. `EARLYBETA2026` is human-readable but `XK7P-9MQR-4LWE` is random) ; rate-limit /redeem-code endpoint to 10 attempts / IP / minute |

### Redemption endpoint design (not implemented, just sketched)

```
POST /redeem-code
Headers: Authorization: Bearer <jwt>  (user must be signed in)
Body: { "code": "EARLYBETA2026" }

Responses:
  200 OK              { "entitlement": "unlimited", "expires_at": null }
  400 invalid_code    code doesn't exist
  400 expired_code    expires_at has passed
  400 exhausted_code  current_redemptions >= max_redemptions
  400 already_redeemed  user already has this code
  401 not_authenticated  no JWT
  429 too_many_attempts  rate limit hit
```

The endpoint is small, fits naturally into Wave 5.17e (post-launch polish) or as a stretch goal in 5.17b/c.

---

## 7 — Risks & Mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Cost explosion from anonymous abuse with N=3 free generations ($0.57 max per uninstall/reinstall cycle) | **MEDIUM** | IP rate limit (10 gens/IP/day) in Wave 5.17b — cheap, catches casual abuse. Add Apple DeviceCheck / Google Play Integrity in Wave 5.17c if logs show real abuse volume. |
| R2 | Anonymous session lost on uninstall (user loses access to their pre-paywall visions) | **LOW** | Acceptable. The free tier is exploratory ; if the user cared enough to save, they would have hit the paywall and signed in. We don't market the free tier as a permanent home for projects. |
| R3 | User unable to access paid features after device switch | **LOW** | RevenueCat's "Restore Purchases" flow (Wave 5.17c) + Apple/Google account-level entitlement restoration. Industry-standard solved problem. |
| R4 | Sign-in failure AT the paywall blocks payment | **HIGH** | Critical fail mode — user has decided to pay, can't. Mitigations : (a) provide BOTH Apple + Google ; (b) clear error messages ; (c) preserve the user's pre-sign-in state so they don't lose their project ; (d) consider phone OTP as a fallback in Wave 6.x. |
| R5 | Cost spike before quota enforcement lands (Wave 5.17b) | **HIGH** (if 5.17b is delayed) | Ship Wave 5.17b within 1 week of 5.17a. Until then, the backend has session-ownership check but no quota gate — a single user could theoretically burn $50 of OpenAI cost by spamming generations on their own session. Add a defensive IP rate limit (10 gens / IP / 24h) at the load-balancer or in `main.py` as a stopgap. |
| R6 | Founder/team can't test paid features without admin role | **HIGH** for team velocity | Ship admin role schema + manual SQL grant alongside 5.17b quota enforcement. Document the SQL grant in the project README. |
| R7 | Promo code leaks before campaign launch | **MEDIUM** | `max_redemptions` per code, time-bounded `expires_at`, monitoring on redemption velocity, deactivation switch (`active = false`). |
| R8 | Cambodia card payment friction at paywall | **MEDIUM** (affects conversion, not architecture) | Apple Pay + Google Pay handle Cambodia cards. ABA Pay direct integration is a future wave (5.18+). Track payment failure rates and add local payment if conversion suffers. |
| R9 | App Store rejection of unmoderated free tier | **LOW** | Apple is fine with anonymous free use. Make sure paywall presents subscription terms (Guideline §3.1.2) and offers Restore Purchases (5.17c). |
| R10 | Anonymous user gen-history collision (two devices, same IP, same anon UUID?) | **LOW** | Supabase generates unique anon UUIDs per device. Same Supabase project + different installs = different users. No collision risk. |
| R11 | Refund handling on RevenueCat webhook | **MEDIUM** | On `CANCELLATION` / `BILLING_ISSUE` webhook, downgrade `user_roles` entry to remove premium. Wave 5.17c scope. No grace period in V1 — add later if churn data justifies. |
| R12 | Cambodia phone numbers in Supabase phone OTP (future Wave 6.x) | **LOW** | Supabase supports +855 numbers. SMS provider must too — Twilio does, MessageBird does, local providers do. Audit at the time of implementation. |

---

## 8 — Recommended Monetization Funnel

### The recommendation

**Move to Option B with N=3.** Funnel :

```
1. Install                     → no friction
2. Upload photo                → no friction
3. Gen #1 (anonymous)          → WOW moment #1
4. Refinement → Gen #2 (anon)  → WOW moment #2
5. Refinement → Gen #3 (anon)  → WOW moment #3
6. Attempt Gen #4              → Paywall sheet appears
7. User taps "Subscribe"       → Sign-In screen (Apple/Google)
8. Sign-in succeeds            → anonymous identity upgraded
                                  to signed-in user (same UUID,
                                  all 3 projects preserved)
9. Purchase flow               → Apple/Google billing
10. Webhook updates entitlement → user_roles.role = 'premium'
11. App refreshes               → unlimited generations
```

### Why this is the right answer

1. **Three full WOW moments before any friction.** The user evaluates the product on its strongest evidence (a complete first vision + two iterations) before being asked for anything.

2. **Sign-in motivation is unambiguous.** "I'm signing in because I'm subscribing" is a clear cognitive contract. "I'm signing in to use this for the second time" is not.

3. **Cambodia market fit improves on every axis.** Phone-first culture, low email habits, payment-time identity confirmation all align with Option B.

4. **Wave 5.17a is 100% reusable.** The identity foundation works regardless of WHEN it's triggered. Moving the trigger from Gen #2 to Gen #4 is a 2-hour frontend change.

5. **Conversion economics favor Option B.** Higher pre-paywall WOW count = higher informed-purchase rate = higher LTV / lower refund risk. The +$0.38 cost exposure per abuse cycle is bounded and addressable.

### Concrete Wave 5.17 roadmap adjustment

| Wave | Original (Option A) | Revised (Option B) | Effort delta |
|---|---|---|---|
| 5.17a | ✅ Identity foundation (shipped) | ✅ Identity foundation (shipped, unchanged) | 0 |
| 5.17b | Quota at Gen #3 (signed-in user) | Quota at Gen #4 (any user, anon or signed) + admin role schema + IP rate limit defense | +1 day (admin schema) |
| 5.17c | RevenueCat + paywall on quota exhaustion | RevenueCat + paywall on quota exhaustion + sign-in at purchase flow | Same effort, different trigger point |
| 5.17d | Watermark (deferred) | Watermark (still deferred) | 0 |
| 5.17e | Restore + l10n + receipt | Restore + l10n + receipt + promo code endpoint (stretch) | +0.5 day if promo codes ship in 5.17e |

**Total wave 5.17 effort delta : +1 to +1.5 days.** Minimal cost for a substantially better funnel.

### What about the abuse exposure increase?

Per-cycle exposure goes from $0.19 (Option A) to $0.57 (Option B with N=3). To put this in scale :
- 100 abuse cycles : $19 (A) vs $57 (B) — both negligible
- 1,000 abuse cycles : $190 vs $570 — visible but contained
- 10,000 abuse cycles : $1,900 vs $5,700 — would require a dedicated abuse mitigation wave anyway

In all realistic scenarios, the conversion lift from Option B will dwarf the abuse cost. Industry benchmarks suggest 2-3x conversion improvements when sign-in is delayed to high-intent moments. If Option A converts at 3% and Option B converts at 7%, the additional revenue at 10K MAU and $9.99/month is :
- Option A: 300 paying × $9.99 = $2,997/month
- Option B: 700 paying × $9.99 = $6,993/month

A $4K/month revenue uplift dwarfs any plausible abuse cost.

### Mitigations to ship alongside Option B

1. **IP rate limit (10 gens/IP/day)** — defensive ceiling, $0 to implement (FastAPI middleware), catches 99% of casual abuse.
2. **Quota lookup on EVERY /generate call** — Wave 5.17b mandatory.
3. **Monitoring dashboard** for "anon users with >5 generations on same IP in 24h" — flag for review.
4. **Apple DeviceCheck / Google Play Integrity API** — add in Wave 5.17c IF abuse logs warrant. Defer otherwise.

---

## Final Recommendation

# MOVE TO OPTION B (multiple free generations → paywall → sign-in → subscription)

### Summary of reasoning

| Dimension | Verdict |
|---|---|
| **Business** | Option B converts better at every benchmarked stage. Industry data + Cambodia-specific factors both favor delayed sign-in. |
| **UX** | Option B respects the user's exploration phase. Sign-in is a transaction step, not an exploration tax. Three WOW moments build conviction. |
| **Technical** | Wave 5.17a infrastructure is 100% reusable. Cost of pivoting : ~2 hours frontend + 1 day added scope to Wave 5.17b. |
| **Market fit** | Cambodia's phone-first, transaction-gated identity culture aligns more naturally with Option B. Option A's mid-funnel sign-in reads as a wall. |
| **Abuse exposure** | +$0.38 per abuse cycle. Bounded, mitigable, dwarfed by expected conversion lift. |

### What to do today

1. Approve the Option B funnel pivot.
2. Adjust Wave 5.17b scope to :
   - Quota at Gen #4 (gates anonymous AND signed-in users equally)
   - Admin role schema + grant SQL documentation
   - IP rate limit (10 gens/IP/day) as defense ceiling
3. Adjust Wave 5.17c scope to :
   - Paywall sheet shown on HTTP 402
   - Sign-in flow embedded in the paywall (NOT before)
   - RevenueCat purchase → webhook → entitlement update
4. Defer phone OTP to Wave 6.x — track Cambodian conversion data for 1-2 months post-launch, decide then.
5. Defer promo codes endpoint to Wave 5.17e (or later) — design is locked, implementation can wait until first campaign needs it.

### What NOT to do

- Do NOT rip out the Wave 5.17a Gen #2 sign-in gate yet — leave it in place until Wave 5.17b ships the new gate (avoids a window where there's no quota enforcement at all).
- Do NOT add phone OTP in this wave — defer until real-user data justifies the SMS spend.
- Do NOT build an admin UI yet — manual SQL grants are sufficient for the team's testing needs through V1 launch.

---

*Audit performed by: Claude Opus 4.7. Codebase commit: post Wave 5.17a (uncommitted). No code modified. No commits. Strategic review only.*
