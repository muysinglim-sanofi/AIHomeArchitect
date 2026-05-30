# Wave 5.17b — Implementation Plan

**Status**: Plan only — no code written yet. Approval gate before implementation starts.
**Predecessor**: Wave 5.17a (Identity Foundation) — shipped, identity layer ready for quota enforcement.
**Funnel** (locked by product, 2026-05-30): Gen #1-3 free anonymous → Gen #4 paywall → sign-in inside paywall → subscription.

## What Wave 5.17b builds

1. **Remove the Wave 5.17a Gen #2 sign-in gate** (one atomic change with #3 below — no period where the app has no gating).
2. **`usage_log` table** in Supabase — per-user generation counter.
3. **Quota enforcement at Gen #4** in `backend/main.py` — HTTP 402 on exhaustion.
4. **`user_roles` table** in Supabase — admin role schema with SQL-grant workflow.
5. **IP rate limit** — defensive ceiling for anonymous abuse.
6. **Frontend 402 handler** — opens a paywall placeholder (real RevenueCat sheet lands in 5.17c).

## What Wave 5.17b explicitly does NOT build

- ❌ Phone OTP (deferred to Wave 6.x pending real-user data)
- ❌ RevenueCat integration (Wave 5.17c)
- ❌ Real subscription products / paywall UI (Wave 5.17c)
- ❌ Watermark (Wave 5.17d)
- ❌ Admin UI (manual SQL grants are sufficient through V1 launch)
- ❌ Promo code redemption endpoint (Wave 5.17e stretch)

---

## 1 — Database Schema Changes (Supabase)

Two new tables. Single migration file. Backwards-compatible (additive only).

### 1.1 — `usage_log`

```sql
CREATE TABLE public.usage_log (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id         uuid REFERENCES public.sessions(id) ON DELETE SET NULL,
  call_type          text NOT NULL CHECK (call_type IN ('generate')),
  status             text NOT NULL CHECK (status IN ('in_progress', 'success', 'failed')) DEFAULT 'in_progress',
  cost_usd_estimate  numeric(10, 4),
  request_id         text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  completed_at       timestamptz
);

CREATE INDEX usage_log_user_id_idx ON public.usage_log(user_id);
CREATE INDEX usage_log_user_status_idx ON public.usage_log(user_id, status) WHERE status != 'failed';
CREATE INDEX usage_log_created_at_idx ON public.usage_log(created_at DESC);

-- RLS: users can only see their own usage rows (parity with sessions/messages policies).
ALTER TABLE public.usage_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "usage_log: owner read"
  ON public.usage_log FOR SELECT
  USING (auth.uid() = user_id);
-- No insert/update/delete policy — service-role only (the FastAPI backend writes; the client never does).
```

**Why these indexes**:
- `usage_log_user_id_idx` — most common lookup at the quota gate.
- `usage_log_user_status_idx WHERE status != 'failed'` — partial index for the actual quota count query (cheap and tight).
- `usage_log_created_at_idx` — supports the IP rate limit's recent-window scan.

**Why `session_id ON DELETE SET NULL`** — preserves the usage record even if a user deletes a project. Cost was incurred ; the audit trail outlives the session.

**Why `status` column**:
- `'in_progress'` — INSERTed BEFORE the OpenAI call. Counts toward quota immediately (prevents parallel-request bypass).
- `'success'` — UPDATED to this on successful OpenAI return.
- `'failed'` — UPDATED to this when OpenAI returns an error we believe was un-billed (network timeout pre-API, 4xx validation errors before any token was processed). 'failed' rows do NOT count toward quota.

### 1.2 — `user_roles`

```sql
CREATE TABLE public.user_roles (
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role        text NOT NULL CHECK (role IN ('admin', 'beta_tester', 'support', 'premium')),
  granted_at  timestamptz NOT NULL DEFAULT now(),
  granted_by  uuid REFERENCES auth.users(id),
  expires_at  timestamptz,
  notes       text,
  PRIMARY KEY (user_id, role)
);

CREATE INDEX user_roles_user_id_idx ON public.user_roles(user_id);

-- RLS: users can read their own roles ; service-role writes only.
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_roles: owner read"
  ON public.user_roles FOR SELECT
  USING (auth.uid() = user_id);
```

**Why CHECK constraint on role names**: prevents typos at SQL-grant time. New roles require a migration to add to the CHECK list — deliberate friction for security.

**Why `expires_at`**: supports "30-day trial admin access" for partner testers + future promo codes (Wave 5.17e). NULL = never expires.

**Why `granted_by`**: audit trail. Founder grants themselves admin → `granted_by = self`. Founder grants Alice admin → `granted_by = founder.id`.

**`'premium'` role**: included in the CHECK list now so Wave 5.17c's RevenueCat webhook can INSERT premium rows without a follow-up migration. Wave 5.17b will not check for `'premium'` (no purchase flow yet) ; quota check considers `'admin'` only.

### 1.3 — Migration delivery

**Method**: single SQL file `supabase/migrations/20260530_wave_5_17b_usage_quota.sql` containing both table creates + indexes + RLS + the founder admin grant.

**Application**: user pastes file content into Supabase Dashboard → SQL Editor → Run. **NOT** auto-applied — Supabase MCP isn't configured ; we do this by hand.

**Validation**: after applying, run `SELECT COUNT(*) FROM usage_log;` and `SELECT * FROM user_roles WHERE role='admin';` to confirm tables exist + founder grant landed.

---

## 2 — Backend Changes (FastAPI)

### 2.1 — New file: `backend/quota.py`

Encapsulates the quota state model + admin bypass logic. Keeps `main.py` thin.

```
quota.py
├── FREE_TIER_LIMIT = 3              # constant — # of free generations per user
├── async def get_quota_status(user_id) → QuotaStatus
│   ├── if user has 'admin' role → QuotaStatus(allowed=True, reason='admin_bypass')
│   ├── if has 'premium' role (active) → QuotaStatus(allowed=True, reason='premium')
│   ├── count usage_log rows for user_id where status != 'failed'
│   └── return QuotaStatus(allowed=count<3, used=count, limit=3)
├── async def reserve_generation(user_id, session_id, request_id) → reservation_id
│   └── INSERT usage_log(status='in_progress') RETURNING id
├── async def confirm_generation(reservation_id, cost_usd) → None
│   └── UPDATE usage_log SET status='success', cost_usd_estimate=?, completed_at=now() WHERE id=?
└── async def fail_generation(reservation_id) → None
    └── UPDATE usage_log SET status='failed', completed_at=now() WHERE id=?
```

**`QuotaStatus` dataclass**:
- `allowed: bool`
- `used: int`
- `limit: int`
- `reason: str` — `'within_quota'` | `'quota_exhausted'` | `'admin_bypass'` | `'premium'`

**Why reserve-then-confirm** (over insert-after-success):
- Closes the parallel-request abuse vector (anon user fires 10 simultaneous /generate calls → all 10 pass a count==0 quota check → 10 free generations).
- The reserve INSERT is a single statement, atomic against the quota count query that follows it.
- Cost: 2 DB writes per /generate instead of 1. Negligible at MVP scale.
- Trade-off accepted: a `'failed'` reservation row stays in the table forever (not deleted). Acceptable observability cost.

**Why bypass `'admin'` first**:
- Admin testing must work even if quota DB is offline (DB-down should not block founder testing).
- Single DB call to user_roles ; cached in a 60-second TTL in-process dict for the founder's session to avoid hot-path DB hits.

### 2.2 — `backend/main.py` — `/generate` insertion points

Existing structure (from Wave 5.17a):
```
@app.post("/generate")
async def generate(..., current_user: CurrentUser = Depends(get_current_user)):
    # session ownership validation (Wave 5.17a)
    # ... ~600 lines of generation logic ...
    response = await openai.images.edit(**edit_kwargs)   # line 1464
    # ... persistence ...
```

Wave 5.17b additions:
```
@app.post("/generate")
async def generate(..., current_user: CurrentUser = Depends(get_current_user)):
    # session ownership validation (existing 5.17a — unchanged)
    
    # NEW — IP rate limit (defensive ceiling)
    _check_ip_rate_limit(request.client.host, current_user)
    
    # NEW — quota gate
    quota = await get_quota_status(current_user.user_id)
    if not quota.allowed:
        raise HTTPException(402, detail={
            "error_code": "QUOTA_EXHAUSTED",
            "user_message": "You've used your free generations. Subscribe to continue.",
            "quota_used": quota.used,
            "quota_limit": quota.limit,
            "retryable": False,
        })
    
    # NEW — reserve before the paid call
    reservation_id = await reserve_generation(
        user_id=current_user.user_id,
        session_id=session_id,
        request_id=request_id,
    )
    
    try:
        # ... existing ~600 lines of generation logic ...
        response = await openai.images.edit(**edit_kwargs)
        # ... existing persistence ...
        
        # NEW — confirm on success (just before the existing final return)
        await confirm_generation(reservation_id, cost_usd=_estimated_cost)
    except Exception:
        # NEW — fail on error (catch-all that mirrors existing error path)
        await fail_generation(reservation_id)
        raise
```

**Insertion line numbers** (post-Wave 5.17a current main.py):
- IP rate limit check: line ~858 (right after session ownership validation block)
- Quota gate: line ~860
- Reserve: line ~862 (one line before the existing OpenAI call ~line 1464 — but moved to right after quota check)
- Confirm: line ~1830 (right before the existing successful return)
- Fail: in a try/except wrapper around the OpenAI call

### 2.3 — IP rate limit module: `backend/rate_limit.py`

Defensive ceiling, not the primary gate. Simple in-memory per-worker dict.

```
rate_limit.py
├── _IP_BUCKET: dict[str, deque[float]]    # {ip_addr: [timestamps_unix]}
├── _MAX_GENS_PER_IP_PER_24H = 10
├── _WINDOW_SECONDS = 86400
└── def check_ip_rate_limit(ip: str, user: CurrentUser) → None:
    ├── # Skip for signed-in users (their quota is account-bound).
    ├── # IP limit only protects against anon-abuse.
    ├── if not user.is_anonymous: return
    ├── # Trim old timestamps from the bucket.
    ├── # If len(bucket) >= 10: raise 429.
    └── # Else: append now, return.
```

**Limitations** (documented + accepted):
- In-memory per-worker → uvicorn restart resets all buckets. Acceptable: bucket size is short-window anyway.
- Per-worker not per-cluster → 4 uvicorn workers = 40 gens/IP/day effective ceiling. Still useful.
- NAT/Mobile-tower shared IPs → real users behind shared IPs could legitimately exceed 10/day. Mitigation: bypass for signed-in users (where IP is irrelevant). For anonymous users, 10/day is generous (3 free gens per install, ~3 install/day = 9 < 10).
- Redis-backed cluster-wide limit is a Wave 5.17c+ option if abuse logs show real volume.

**Why include this if it's defensive?**: the audit (R5) flagged that 5.17a → 5.17b transition has a window with no quota gate. The IP limit is the stopgap that makes the 5.17b ship even-if-misconfigured safe.

### 2.4 — Auth header for IP rate limit & quota

Both new modules import `CurrentUser` from `auth.py` (shipped in 5.17a). No changes to `auth.py`. No new env vars beyond the existing `SUPABASE_JWT_SECRET`.

---

## 3 — Frontend Changes (Flutter)

### 3.1 — Remove the Gen #2 gate

**File**: `frontend/lib/features/chat/chat_screen.dart`
**Action**: delete the Wave 5.17a block (currently lines ~990-1030):
```dart
// DELETE THIS BLOCK in Wave 5.17b
if (newCount >= 2 && auth.isAnonymous) {
  final signedIn = await Navigator.of(context).push<bool>(...);
  if (signedIn != true) { ... }
}
```

**Why remove rather than disable**: the gate is dead code in Option B. Leaving it in (commented or feature-flagged) creates confusion. Clean removal is correct.

**Why atomic with the new gate**: this is the user-facing pivot. Until Wave 5.17b's quota gate AND paywall handler land in the same release, removing the 5.17a gate would mean ZERO friction (free generations forever). They must ship together.

### 3.2 — New 402 handler

**File**: `frontend/lib/data/services/generation_service.dart`
**Action**: extend `GenerationException` parsing to recognize the new 402 quota response:

```
// Existing GenerationException class gets a new field:
final bool quotaExhausted;     // true if backend returned 402 QUOTA_EXHAUSTED
final int? quotaUsed;
final int? quotaLimit;

// In the DioException handler:
if (e.response?.statusCode == 402 && data?['error_code'] == 'QUOTA_EXHAUSTED') {
  throw GenerationException(
    errorCode: 'QUOTA_EXHAUSTED',
    userMessage: data['user_message'],
    retryable: false,
    quotaExhausted: true,
    quotaUsed: data['quota_used'],
    quotaLimit: data['quota_limit'],
  );
}
```

### 3.3 — Placeholder paywall sheet

**New file**: `frontend/lib/features/paywall/paywall_sheet.dart`

A simple Material `showModalBottomSheet`-style component. NO real subscription logic in Wave 5.17b — just :
- Headline: "Continue with unlimited generations"
- Subhead: "You've used your 3 free visions. Subscribe to keep exploring."
- Two buttons:
  - "Sign in and subscribe" → pushes the existing `SignInScreen` (Wave 5.17a) ; on success returns to paywall (which in 5.17b just dismisses ; 5.17c will then trigger purchase flow).
  - "Maybe later" → dismisses, returns user to chat.

**Why a placeholder**: Wave 5.17c is the real paywall (RevenueCat-rendered). Wave 5.17b needs SOMETHING to show on 402 so the funnel is testable end-to-end without RevenueCat.

### 3.4 — Hook the 402 handler in `chat_screen.dart`

**File**: `frontend/lib/features/chat/chat_screen.dart`
**Action**: in the existing `try { await GenerationService().generate(...) } on GenerationException catch (e) { ... }` block (around line 1180), add a branch:

```dart
on GenerationException catch (e) {
  if (e.quotaExhausted == true) {
    // Wave 5.17b — paywall sheet appears instead of error toast
    setState(() {
      _messages.removeWhere((m) => m.id.startsWith('loading_'));
      _isGenerating = false;
    });
    final subscribed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PaywallSheet(),
    );
    // 5.17b: subscribed always returns false (no RevenueCat yet).
    // 5.17c: on successful purchase, retry the /generate call.
    return;
  }
  // ... existing error handling ...
}
```

### 3.5 — Profile screen — voluntary sign-in entry

**File**: `frontend/lib/features/profile/profile_screen.dart`
**Action**: add a "Sign In" entry above the existing "Sign Out" item, visible ONLY when `AuthService().isAnonymous == true`.

```dart
if (auth.isAnonymous) ...[
  _SettingItem(
    icon: Icons.login,
    label: 'Sign In',
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignInScreen(
        headline: 'Restore your account',
        subhead: 'Sign in to restore your subscription or sync your projects.',
      )),
    ),
  ),
],
```

**Why**: in Option B, sign-in is normally tied to purchase. But existing premium users on a new device need a way to sign in voluntarily to restore their subscription. This entry is the only path until Wave 5.17c adds "Restore Purchases" to the paywall.

---

## 4 — Wave 5.17a Code That Becomes Dormant

**`frontend/lib/data/services/auth_service.dart`** — `signInWithApple()`, `signInWithGoogle()`, `signOut()`, `signInAnonymouslyIfNeeded()` all stay. Triggered now from the paywall sheet (and from the new profile-screen voluntary sign-in), not from the Gen #2 gate.

**`frontend/lib/features/auth/sign_in_screen.dart`** — unchanged. Headline/subhead props let it adapt copy per context (paywall vs profile vs future use).

**`backend/auth.py`** — unchanged. JWT validation continues to accept both anonymous and signed-in tokens.

**Backend session ownership check** in `main.py` — unchanged. Still fires before the OpenAI call.

**Conclusion**: 100% of Wave 5.17a code remains live. The pivot is purely a relocation of WHERE sign-in is offered.

---

## 5 — Phased Implementation (~6 days estimated)

### Phase A — Database (0.5 day)
1. Author `supabase/migrations/20260530_wave_5_17b_usage_quota.sql`.
2. Apply via Supabase Dashboard SQL Editor.
3. Insert founder admin grant: `INSERT INTO user_roles(user_id, role, granted_by, notes) VALUES (<founder-uuid>, 'admin', <founder-uuid>, 'Self-grant for founder testing — 2026-05-30');`.
4. Validation: query both tables, confirm empty (except for the admin row).

**Output**: 1 SQL file, applied to Supabase, validated.

### Phase B — Backend quota module (1 day)
1. Create `backend/quota.py` with `get_quota_status`, `reserve_generation`, `confirm_generation`, `fail_generation`.
2. Create `backend/rate_limit.py` with `check_ip_rate_limit`.
3. Modify `backend/main.py` `/generate` to add the 5 insertion points (see §2.2).
4. Smoke test (unit, no real OpenAI calls):
   - User with 0 generations → quota.allowed = True
   - User with 3 generations → quota.allowed = False
   - User with admin role → quota.allowed = True regardless of count
   - User with 3 'success' + 1 'failed' → quota.allowed = False (3 counts)
   - User with 1 'in_progress' + 2 'success' → quota.allowed = False (3 counts — closes the parallel-request race)
   - IP rate limit: 10 anon calls → 11th raises 429
   - IP rate limit: signed-in user → no limit applied

**Output**: 2 new backend files, ~250 lines of code, smoke tests pass.

### Phase C — Frontend 402 handler + paywall placeholder (1.5 days)
1. Extend `GenerationException` in `generation_service.dart`.
2. Create `frontend/lib/features/paywall/paywall_sheet.dart`.
3. Hook 402 handler in `chat_screen.dart`.
4. Smoke test against backend:
   - Anonymous user × 3 generations → all succeed
   - 4th generation attempt → backend returns 402 → frontend opens paywall sheet
   - Tap "Maybe later" → dismisses cleanly
   - Tap "Sign in" → opens existing SignInScreen → on success returns to paywall

**Output**: 1 new file, ~3 file modifications, end-to-end 402 path proven.

### Phase D — Gen #2 gate removal + sign-in entry on profile (0.5 day)
1. Delete the Gen #2 gate block in `chat_screen.dart`.
2. Add voluntary sign-in entry in `profile_screen.dart`.
3. Smoke test:
   - Anonymous user generates 1, 2, 3 with NO sign-in prompt at Gen #2 (regression of 5.17a behavior — intentional).
   - Profile screen: anon user sees "Sign In" entry, signed-in user does not.

**Output**: ~3 file modifications.

### Phase E — Validation harness + deliverable (1.5 days)
1. Build a Python validation harness `backend/_wave_5_17b_validation.py`:
   - 10 scenarios covering quota states, race conditions, admin bypass, IP limit, session ownership
2. Manual end-to-end test via live HTTP probes (existing pattern from Wave 4.11):
   - Anon JWT × 3 generations → success
   - 4th → 402
   - Sign-in mid-funnel (voluntary from profile) → quota count preserved (same UUID)
   - Admin role granted via SQL → infinite generations
3. Write `backend/wave_5_17b_validation.md`:
   - Implementation summary
   - SQL schema diff
   - Pass/fail matrix
   - Risks remaining
   - Recommendation (READY TO SHIP / NEEDS ADJUSTMENT)

**Output**: validation harness + 1 deliverable .md.

### Phase F — Wave 5.17b commit + push (0.5 day)
1. Stage and commit as single Wave 5.17b commit.
2. Push to origin.
3. Update `docs/user_mental_model.md` with any observations surfaced during validation.

**Output**: 1 commit, pushed.

### Total: ~5.5 days of focused engineering

---

## 6 — Risks & Mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Gen #2 gate removal lands but quota gate doesn't fire (race during deploy) | CRITICAL | Atomic ship — both changes in the same commit. Backend deploy precedes frontend deploy (so 402 is available before frontend stops sending sign-in gate). Even if frontend deploys first by mistake, anon users get 3 free gens and HTTP 402 catches them at #4. |
| R2 | Reservation row leaks (in_progress forever) on backend crash mid-generation | LOW | Add scheduled job in 5.17c to mark in_progress rows older than 10 minutes as 'failed'. For 5.17b, accept the data residue — affects quota count negligibly. |
| R3 | Admin role lookup adds DB query to every /generate | LOW | Cache user_roles lookup for 60 seconds per user_id in-process. Founder testing is high-frequency on a single user_id — cache amortizes the DB hit. |
| R4 | IP rate limit blocks legitimate users behind shared NAT | LOW-MED | Anon users behind NAT can still get 10 gens/24h before hitting the limit. If real users complain, increase to 20 or skip the limit entirely (it's defensive, not load-bearing). |
| R5 | usage_log table grows unbounded | LOW | At 1K gens/day, the table grows ~30K rows/month — trivial. Add retention job in 5.18+ if needed (e.g., archive rows > 1 year). |
| R6 | Anonymous user signs in mid-funnel (voluntary from profile) → quota count semantics | LOW | Anon UUID preserved via Wave 5.17a upgrade flow → usage_log rows stay attached to same UUID → user's count is preserved. No bug, just need to validate in Phase E. |
| R7 | Cost spike from a viral abuse pattern before IP limit catches it | MED | The 3-gen-per-IP-per-cycle exposure is bounded by Apple/Google account creation friction on payment side. IP limit catches casual abuse. Apple DeviceCheck / Play Integrity in 5.17c if needed. |
| R8 | Founder forgets to grant themselves admin and gets paywalled during testing | LOW | Document the admin SQL grant in the Wave 5.17b PR description AND in the README. Founder runs it ONCE in Phase A. |
| R9 | Paywall sheet placeholder is confusing because "Sign in" doesn't actually subscribe | LOW | Copy in the paywall sheet must be explicit: "Subscription coming soon. Sign in now to be ready." Better wait for 5.17c if launch is imminent — but the funnel needs 402 handling for testing. |
| R10 | Race between IP limit check and quota check | LOW | Order is: IP check → quota check → reserve. Each is independent. Worst case: a user hits IP limit AFTER passing quota → reservation was already inserted → they consumed quota but didn't get the generation. Mitigation: reserve AFTER both checks. Adjust insertion order in Phase B. |

---

## 7 — Open Questions Before Code Starts

These are the only decisions I need confirmed before Phase A begins. If you say "go" without addressing them, I'll proceed with the defaults shown.

| # | Question | Default if not answered |
|---|---|---|
| Q1 | **FREE_TIER_LIMIT value**: 3 generations is the recommendation. Confirm? | 3 |
| Q2 | **IP rate limit threshold**: 10 gens/IP/24h for anon users only. Confirm? | 10/24h |
| Q3 | **Founder Supabase user_id**: needed for the admin grant SQL. Can you grab it from Supabase Dashboard → Auth → Users? (Or skip the auto-grant — I'll output the SQL with `<FOUNDER_USER_ID>` placeholder for you to fill in.) | Placeholder in SQL |
| Q4 | **Reserve-then-confirm vs simple insert-after-success**: I recommend reserve-then-confirm for race safety. Confirm? | Reserve-then-confirm |
| Q5 | **Paywall sheet copy**: do you want specific wording, or is "You've used your 3 free visions. Subscribe to keep exploring." acceptable as placeholder? | The proposed copy |
| Q6 | **Cambodia l10n for paywall placeholder**: should the placeholder sheet have FR / KM translations, or English-only until 5.17e? | English-only |

---

## 8 — Definition of Done

Wave 5.17b is READY TO SHIP when:

- [ ] Migration applied to Supabase, `usage_log` + `user_roles` tables exist
- [ ] Founder has admin role (verified via SQL query)
- [ ] `backend/quota.py` + `backend/rate_limit.py` exist with the API described
- [ ] `/generate` enforces quota AT THE BACKEND (HTTP 402 on exhaustion)
- [ ] `/generate` enforces IP rate limit for anonymous users only
- [ ] Reservation rows correctly transition in_progress → success/failed
- [ ] Wave 5.17a Gen #2 sign-in gate is removed from `chat_screen.dart`
- [ ] Frontend 402 handler opens the paywall placeholder
- [ ] Profile screen has voluntary sign-in entry for anonymous users
- [ ] Validation harness passes 10/10 scenarios
- [ ] Backend `wave_5_17b_validation.md` deliverable produced with explicit READY TO SHIP recommendation
- [ ] Commit pushed to origin

---

## 9 — What Wave 5.17c will build on top

For visibility, the next wave (NOT in scope of this plan, but designed to fit):

- `purchases_flutter` (RevenueCat) SDK integration
- iOS StoreKit capability + Android BILLING permission
- Real paywall sheet replacing the 5.17b placeholder
- `/webhooks/revenuecat` endpoint → updates `user_roles` table (sets role='premium' on INITIAL_PURCHASE, deletes on CANCELLATION)
- "Restore Purchases" button on paywall
- Quota check already respects `'premium'` role (CHECK constraint was pre-emptively added in 5.17b)

**No backward-incompatible changes to 5.17b required.** The premium tier just becomes "another way to bypass quota" — same mechanism as admin.

---

## Final Recommendation

# Plan READY for implementation

Pending answers (or default acceptance) to the 6 Open Questions in §7. Once those are settled, I can proceed with Phase A (database migration) immediately. The full Wave 5.17b is ~5.5 days of focused engineering, mostly backend (Phase B, ~1 day) and validation (Phase E, ~1.5 days).

No new architectural concepts introduced — everything builds on the Wave 5.17a identity foundation. No new SDKs. No code outside of 2 new backend modules + 1 new frontend file + 4 file modifications.

Awaiting authorization on the 6 Open Questions to start Phase A.
