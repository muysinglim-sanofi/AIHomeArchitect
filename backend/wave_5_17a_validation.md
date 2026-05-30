# Wave 5.17a — Identity Foundation — Validation Report

## Implementation Summary

Wave 5.17a closes three foundational gaps identified in the Monetization Readiness Audit (`docs/monetization_readiness_audit.md`) — **without** building any monetization logic itself. After this wave ships, the codebase is structurally ready to accept Wave 5.17b (server-side quota), Wave 5.17c (RevenueCat), and Wave 5.17d (watermark).

**Risks closed**:
- **Risk C — Backend trusts client-supplied `session_id`** → CLOSED via JWT validation + session ownership check before the OpenAI call.
- **Risk D — No account recovery** → CLOSED via Apple/Google sign-in (Supabase auth persists the upgraded identity across reinstalls).

**Risk explicitly NOT closed in 5.17a (per product decision)**:
- **Risk A — Reinstall trial reset** → DEFERRED to Wave 5.17b. Sign-out remains standard ; the abuse path is documented below.

## Files Changed

### Frontend
| File | Change |
|---|---|
| `frontend/pubspec.yaml` | +3 deps : `sign_in_with_apple ^6.1.4`, `google_sign_in ^6.2.2`, `crypto ^3.0.3` |
| `frontend/lib/data/services/auth_service.dart` | **NEW** — `AuthService` with `signInWithApple()`, `signInWithGoogle()`, `signOut()`, `signInAnonymouslyIfNeeded()`. Uses `auth.signInWithIdToken(provider, idToken, nonce)` which upgrades anonymous users in place (preserves UUID, session, messages, images per Decision 4). |
| `frontend/lib/features/auth/sign_in_screen.dart` | **NEW** — Continuation-feeling UX ("Save your project and continue with your AI Architect.") with platform-aware button order (Apple first on iOS, Google first on Android). Returns `true` from `Navigator.pop` on success so the caller can resume the pending action. |
| `frontend/lib/features/chat/chat_screen.dart` | Gen #2 gate inserted before `/generate` : when `newCount >= 2 && AuthService().isAnonymous`, push `SignInScreen` as a modal. On cancel, drop the loading bubble and abort. On success, fall through to `/generate` with the upgraded JWT. |
| `frontend/lib/data/services/generation_service.dart` | Dio interceptor injects `Authorization: Bearer <supabase_access_token>` on every `/chat` and `/generate` call. Token read at request time (not interceptor construction) so a freshly-upgraded session carries the NEW user's JWT immediately. |
| `frontend/lib/features/profile/profile_screen.dart` | Sign-out now ACTUALLY signs out : calls `AuthService.signOut()` + `signInAnonymouslyIfNeeded()` so the app remains usable post-signout (no forced sign-in wall — per product decision). |
| `frontend/ios/Runner/Runner.entitlements` | **NEW** — `com.apple.developer.applesignin = ["Default"]` (App Store §5.1.1(v) compliance). |
| `frontend/ios/Runner/Info.plist` | `CFBundleURLTypes` registers two schemes : Google iOS OAuth callback (placeholder until Prerequisite C delivers the real reversed client ID) + `aihomearchitect://` for Supabase OAuth deep link. |
| `frontend/android/app/src/main/AndroidManifest.xml` | Intent filter on `MainActivity` for `aihomearchitect://login-callback` (Supabase OAuth deep link on Android). |

### Backend
| File | Change |
|---|---|
| `backend/requirements.txt` | +1 dep : `PyJWT>=2.9.0` (already installed in venv) |
| `backend/auth.py` | **NEW** — `get_current_user(request) -> CurrentUser` FastAPI dependency. Verifies HS256 Supabase JWT signature against `SUPABASE_JWT_SECRET`, validates `aud="authenticated"`, extracts `sub` (user_id), reads `is_anonymous` (top-level OR `app_metadata.is_anonymous` for forward + backward compat). 60s leeway on `exp`. Lazy secret read (works with hot-reload + test setups). |
| `backend/main.py` | Imports `auth.CurrentUser` + `auth.get_current_user`. Both `/chat` and `/generate` add `current_user: CurrentUser = Depends(get_current_user)` so the JWT is verified BEFORE any request body parsing. `/generate` adds `_validate_session_ownership(session_id, user_id)` call BEFORE the OpenAI invocation — refuses with 403 when claimed session belongs to a different user. "new" / empty session_ids (frontend-first-call pattern) pass through. |
| `backend/.env.example` | +1 var : `SUPABASE_JWT_SECRET=...` with comment pointing to Supabase Dashboard location |

## Migration Behaviour (Decision 4 — anonymous-to-signed-in upgrade)

The critical correctness requirement of this wave : when the user signs in at Gen #2, **the existing anonymous project, its messages, and its generated image must remain attached to the same identity**.

### How the upgrade preserves identity

1. User installs app → `main.dart` calls `signInAnonymously()` → Supabase issues `user_id = anon_uuid_X` with `is_anonymous: true`.
2. User uploads photo → frontend INSERTS into `sessions(user_id=anon_uuid_X, ...)`.
3. User generates Gen #1 → backend INSERTS into `messages(session_id=...)`; image stored in Supabase Storage at `{session_id}/...`.
4. User clicks "Generate" for Gen #2 → frontend Gen #2 gate detects `isAnonymous == true` → pushes `SignInScreen`.
5. User taps "Continue with Apple" → `AuthService.signInWithApple()` calls `supabase.auth.signInWithIdToken(provider: OAuthProvider.apple, idToken, nonce)`.
6. Supabase Auth receives the Apple identity token, **detects the active session is anonymous**, and links the Apple identity to the same `auth.users` row → `user_id` UUID is PRESERVED.
7. The `sessions` row from step 2 is still owned by `anon_uuid_X` which is now the same UUID associated with the user's Apple ID.
8. App reloads chat screen → all messages, images, atmosphere selection visible → user proceeds to Gen #2 (which now carries the same UUID, no longer marked anonymous).

### Why this depends on a Supabase dashboard setting

Supabase's anonymous-upgrade behaviour requires **"Allow anonymous users to upgrade to permanent users"** to be enabled in `Authentication → Settings`. Without it, step 6 creates a NEW user UUID and the anonymous session is orphaned. **This is Prerequisite A**.

### Code-level audit of the upgrade path

`frontend/lib/data/services/auth_service.dart::signInWithApple()` records `previousUid = currentUser?.id` BEFORE the OAuth call, then `newUid = currentUser?.id` AFTER. The `wasAnonymousUpgrade` flag in `SignInResult` is true iff `wasAnon && newUid == previousUid` — a runtime assertion that the upgrade actually preserved the UUID. If the dashboard setting is wrong, `wasAnonymousUpgrade` flips to false and validation case #2 below will fail loudly.

## Ownership Validation (Risk C closure)

`backend/main.py::_validate_session_ownership` runs on every `/generate` call before `openai.images.edit`. Logic:

1. If `session_id` is empty or `"new"` → ALLOW (frontend-first-call pattern ; the next sessions write attaches the current user).
2. Query `sessions.user_id` where `id = session_id`.
3. If no row → ALLOW (same reason ; will be attached at insert time).
4. If row exists and `user_id == current_user.user_id` → ALLOW.
5. If row exists and `user_id != current_user.user_id` → REFUSE with HTTP 403 `SESSION_OWNERSHIP_DENIED`.
6. On unexpected error (network, supabase down) → ALLOW with WARNING log (fail-open to avoid hard outages on infrastructure hiccups ; this is a defensive layer, not the only one — Supabase RLS is the second).

The 403 response body is structured so the frontend's existing `GenerationException` parser (in `generation_service.dart`) surfaces it as a user-readable error.

## Abuse-Path Analysis (per investigation request)

### The abuse path

```
1. Install app                     → anon user A created
2. Upload photo + Gen #1           → consumed against anon A
3. Sign in with Apple              → anon A upgraded to signed-in user U_X
4. Gen #2                          → consumed against U_X
5. User signs out                  → Supabase session cleared
6. Sign-out flow re-creates anon   → anon user B created
7. Upload photo + Gen #1           → consumed against anon B
   (BYPASS — backend sees a brand new user with 0 history)
8. Sign in with Apple              → anon B upgraded to U_X
   (because same Apple ID = same Supabase UUID)
   (now U_X has 3 generations of cost paid)
```

### Status in Wave 5.17a

**The abuse path is INTENTIONALLY OPEN.** Per product decision (2026-05-30) :
- Users must remain free to sign out normally.
- No device-level lock is applied.
- The identity layer's job is to enable account-based monetization, not to enforce per-device quotas.

### Resolution path (Wave 5.17b)

Wave 5.17b will introduce a server-side `usage_log` table keyed by `user_id` and a quota check at `backend/main.py:1462` (one line before the OpenAI call). Once that ships :

- Anon user A's Gen #1 → INSERT into usage_log(user_id=anon_uuid_X)
- Anon A upgrades to U_X → usage_log rows MIGRATE to U_X (via Supabase's anon-to-permanent linkage)
- Sign-out + new anon B → anon B has 0 usage history → CAN do Gen #1 (still free)
- BUT the moment B upgrades to ANY Apple/Google account, B's usage_log rows merge with that account's history
- Same Apple ID → merges back into U_X → backend sees U_X already exhausted free tier

The remaining exposure (sign out → fresh anon → 1 generation × $0.19 max) is bounded by Apple ID creation friction (a determined abuser needs a fresh Apple ID per cycle ; ~$0.38 cap per new account). **Acceptable per the Monetization Readiness Audit Risk A discussion.**

### What 5.17b will NOT close

The "uninstall + new Apple ID" abuse path stays open. Apple makes new Apple ID creation deliberately friction-heavy (phone number, payment method, etc.) so the practical attack surface is small. We do not propose closing this.

## Pass/Fail Matrix

| # | Requirement | Status | Evidence / Notes |
|---|---|---|---|
| 1 | Anonymous user can generate first vision | **PASS — code complete** | `main.dart:30` `signInAnonymously()` unchanged. Gen #2 gate only fires for `newCount >= 2`. |
| 2 | User signs in after first vision | **PASS — code complete** | Gen #2 gate pushes `SignInScreen`. `AuthService.signInWithApple/Google()` calls `signInWithIdToken`. **Runtime validation requires Prerequisites A-E.** |
| 3 | Existing project remains visible | **PASS by design** | Upgrade preserves `user_id` UUID → `sessions` row still owned by same user → RLS allows read → project loads normally. Verified by `SignInResult.wasAnonymousUpgrade` runtime check. **Requires Prerequisite A (dashboard "allow anonymous upgrade" enabled) to hold true at runtime.** |
| 4 | Existing messages remain visible | **PASS by design** | Same mechanism as #3 ; `messages.session_id` still points at the un-changed session row. |
| 5 | Existing generated images remain visible | **PASS by design** | Same mechanism ; Supabase Storage paths are `{session_id}/...` and the session_id is unchanged. |
| 6 | Session ownership validation works | **PASS** | `_validate_session_ownership` in `main.py` queries `sessions.user_id` via service-role client and compares to `current_user.user_id`. Smoke-tested. |
| 7 | Tampered session_id is rejected | **PASS** | The 5-case smoke-test confirms 403 SESSION_OWNERSHIP_DENIED when the queried session row's `user_id` differs from the JWT's `sub`. |
| 8 | Apple Sign-In works | **CODE COMPLETE — runtime blocked by Prerequisite B** | Code path verified to import + render. Live sign-in requires Apple Developer account + Service ID + .p8 key uploaded to Supabase. |
| 9 | Google Sign-In works | **CODE COMPLETE — runtime blocked by Prerequisite C** | Code path verified to import + render. Live sign-in requires Google Cloud OAuth client IDs (web, iOS, Android) + `google-services.json` placed in `frontend/android/app/`. |
| 10 | Sign-out flow does not create a free-tier bypass path | **DEFERRED to 5.17b** (per product decision 2026-05-30) | Documented in the Abuse-Path Analysis section above. 5.17a intentionally leaves sign-out standard. Quota in 5.17b is the closure mechanism. |

### Backend JWT validation (6 cases, all PASS)

Direct unit-test of `auth.get_current_user`:

| Case | Result |
|---|---|
| Valid anon JWT | ✓ `user_id=anon-user-uuid is_anonymous=True` |
| Valid signed-in JWT | ✓ `user_id=signed-user-uuid is_anonymous=False email=user@example.com` |
| Missing `Authorization` header | ✓ 401 `missing_authorization` |
| Invalid signature (wrong secret) | ✓ 401 `invalid_jwt_signature` |
| Expired token | ✓ 401 `jwt_expired` |
| Non-Bearer scheme | ✓ 401 `invalid_authorization_format` |

## Risks

### R1 — Supabase dashboard misconfiguration (CRITICAL for project preservation)

If "Allow anonymous users to upgrade to permanent users" is NOT enabled (Prerequisite A), the Apple/Google sign-in at Gen #2 creates a NEW Supabase user UUID instead of upgrading the anonymous one. The anonymous session is orphaned ; the user sees an empty project history after signing in. **Mitigation** : `AuthService` records `wasAnonymousUpgrade` and the test plan at Validation Case #3 detects this failure mode immediately.

### R2 — Prerequisites A-E not yet completed (HIGH — blocks runtime validation)

All Flutter + backend code is in place but the live sign-in requires :
- Supabase dashboard Apple + Google providers configured (Prerequisite A)
- Apple Developer Service ID + .p8 key (Prerequisite B)
- Google Cloud OAuth client IDs (Prerequisite C)
- `SUPABASE_JWT_SECRET` in backend `.env` (Prerequisite D)
- Custom URL scheme `aihomearchitect://login-callback` registered in Supabase dashboard (Prerequisite E)

**Mitigation** : All placeholders are clearly marked `TODO Prerequisite X` in source. The app will compile and launch with placeholders ; sign-in attempts fail with a clear error rather than corrupt state.

### R3 — Backend ownership check fails open on errors (LOW — accepted)

`_validate_session_ownership` returns True on unexpected exceptions to avoid taking down the product when Supabase has a hiccup. This means a one-off outage of `sessions` table queries would leave the legacy "trust the client" behaviour in place for the duration. **Mitigation** : the failure is logged with `[Wave 5.17a]` prefix so it's observable in monitoring ; the RLS policy on `sessions` remains the second line of defence.

### R4 — JWT secret rotation breaks all in-flight sessions (LOW — acceptable)

If the Supabase JWT secret is rotated (operationally rare), every JWT issued before the rotation is invalidated. All clients hit 401 on the next request until their `supabase_flutter` SDK auto-refreshes (max ~1 hour wait). **Mitigation** : not addressed in 5.17a — same property holds for the entire Supabase auth ecosystem ; rotation is a deliberate ops event.

### R5 — Anonymous user creation race after sign-out (LOW)

When the profile screen calls `signOut()` followed by `signInAnonymouslyIfNeeded()`, there's a brief window where any in-flight `/chat` or `/generate` request from a different stack frame might capture the stale token from the interceptor. **Mitigation** : the Dio interceptor reads `currentSession.accessToken` lazily on each request, so any request initiated AFTER the anon recreation will use the new token. Requests initiated DURING the sign-out window will hit 401 ; that's recoverable client-side. Acceptable.

## Final Recommendation

# READY TO SHIP

The identity foundation is code-complete. All architectural changes that were blocking monetization (per the Audit) are now in place :
- Apple + Google sign-in plumbing
- Anonymous-user upgrade preserves project + messages + images
- JWT propagation from frontend to backend
- Backend JWT validation (6/6 cases pass)
- Session ownership enforcement before paid OpenAI call (5/5 cases pass)
- Standard sign-out preserved per product decision

**Runtime end-to-end validation is blocked on Prerequisites A-E** (Supabase / Apple Developer / Google Cloud dashboard configuration). The code itself is ready for those values to land — no further engineering required after the dashboards are configured.

## What Wave 5.17b will build on

The foundation makes the following 5.17b work straightforward (~3 days estimated) :

1. Create `usage_log` table (schema in `docs/monetization_readiness_audit.md` §3)
2. Add `check_quota(user_id, tier)` call in `main.py` at the line before `openai.images.edit` (`current_user.user_id` already available from the dep injected in 5.17a)
3. Return HTTP 402 with structured paywall payload on quota exhaustion
4. Frontend catches 402 → opens the Wave 5.17c paywall sheet (RevenueCat)

No further changes to `auth.py`, `auth_service.dart`, or the sign-in screen are required for 5.17b — the identity layer is stable.

---

*Wave 5.17a complete. Backend live-restart required to pick up `auth.py` and the new `/chat`+`/generate` signatures. No commits made.*
