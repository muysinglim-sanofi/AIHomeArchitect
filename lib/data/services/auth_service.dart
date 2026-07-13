/// Wave 5.17a — Identity Foundation auth service.
///
/// Centralises the Apple / Google sign-in flow and the anonymous-user-upgrade
/// path. The Wave 5.17 monetization stack treats Generation #1 as anonymous
/// (no friction) and Generation #2+ as sign-in-required. This service is the
/// single source of truth for that transition.
///
/// **Anonymous upgrade contract (project preservation)**
/// When the user is anonymous AND signs in with Apple/Google, we call
/// `supabase.auth.linkIdentityWithIdToken()` (NOT `signInWithIdToken()`) —
/// the native ID-token LINK that attaches the OAuth identity to the CURRENT
/// anonymous user, preserving its UUID (so session/messages/images stay
/// attached). Requires "Enable Manual Linking" in the Supabase dashboard.
/// If the OAuth identity ALREADY belongs to another account, the LINK fails;
/// we then sign into that existing account (B) and return `mergeRequired`
/// with `previousAnonUid` = A, for the (future) atomic merge flow.
///
/// Sign-out behaviour is intentionally STANDARD : it clears the Supabase
/// session. Wave 5.17a does not implement a device-lock-on-signout defense
/// (per product decision 2026-05-30) ; the abuse path
/// (anon → sign-in → gen → sign-out → fresh anon → gen) is documented and
/// will be addressed by server-side quota enforcement in Wave 5.17b.
library;

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of a sign-in attempt.
enum SignInOutcome {
  success,           // signed in (or upgraded from anon) — user is authenticated
  cancelled,         // user cancelled the native dialog
  failed,            // any other error (network, provider config, etc.)
}

class SignInResult {
  final SignInOutcome outcome;
  final String? userId;
  final String? errorMessage;
  /// True iff the anonymous UUID was PRESERVED via linkIdentityWithIdToken
  /// (LINK path succeeded). False otherwise.
  final bool wasAnonymousUpgrade;
  /// True iff the anonymous user could NOT be linked because the OAuth identity
  /// already belongs to a DIFFERENT account (B) → we signed into B and the
  /// anonymous activity (A) must be MERGED into B by the (future) merge flow.
  final bool mergeRequired;
  /// The anonymous UUID (A) captured BEFORE sign-in — set only when
  /// [mergeRequired], so the merge-ticket flow can reference it. Never a token.
  final String? previousAnonUid;

  const SignInResult({
    required this.outcome,
    this.userId,
    this.errorMessage,
    this.wasAnonymousUpgrade = false,
    this.mergeRequired = false,
    this.previousAnonUid,
  });
}

class AuthService {
  final SupabaseClient _supabase;

  AuthService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  /// Currently authenticated user (anonymous or signed-in). Returns null
  /// only if Supabase auth has been signed out and not re-initialised.
  User? get currentUser => _supabase.auth.currentUser;

  /// True iff the active session is an anonymous one.
  /// Supabase tags anonymous sessions with `is_anonymous == true` on the
  /// user record (and the JWT's app_metadata).
  bool get isAnonymous {
    final user = currentUser;
    if (user == null) return false;
    return user.isAnonymous == true;
  }

  /// True iff the user has signed in with Apple or Google. False for
  /// anonymous users and for the "no session" case.
  bool get isSignedIn => currentUser != null && !isAnonymous;

  /// Active Supabase JWT for the current session (anonymous OR signed-in).
  /// Returned as a raw Bearer token, ready for the `Authorization` header
  /// on backend calls. Null if no session is active.
  String? get accessToken => _supabase.auth.currentSession?.accessToken;

  // ── Anonymous-upgrade-aware Apple Sign-In ──────────────────────────────

  /// Apple Sign-In with anonymous-user upgrade. When the current user is
  /// anonymous, links the Apple identity to the existing UUID via
  /// `linkIdentity()`. When the user is already signed in or has no
  /// session, falls back to `signInWithOAuth()`.
  Future<SignInResult> signInWithApple() async {
    try {
      // Apple requires a nonce ; Supabase passes it through to verify the
      // identity token returned by Apple. Hash the nonce to SHA-256 for
      // the AppleID request ; pass the raw nonce to Supabase.
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        debugPrint('[AuthService] Apple credential missing identityToken');
        return const SignInResult(
          outcome: SignInOutcome.failed,
          errorMessage: 'Apple sign-in returned no identity token',
        );
      }

      final wasAnon = isAnonymous;
      final previousUid = currentUser?.id;

      if (wasAnon) {
        // Unified Identity — convert the anonymous user by LINKING the Apple
        // identity to the CURRENT (anonymous) user via linkIdentityWithIdToken
        // (requires "Enable Manual Linking" in Supabase). Success → UUID PRESERVED
        // (enforced by the invariants below). ONLY the error code
        // 'identity_already_exists' means the Apple identity already belongs to
        // another account → then, and ONLY then, we sign into that account (B) and
        // flag MERGE_REQUIRED. Any OTHER AuthException (manual_linking_disabled,
        // provider_disabled, bad_jwt, timeout…) is a real failure → rethrow; never
        // a silent fallback that would misclassify a config error as a merge and
        // orphan the anonymous project A.
        //
        // QA-1 observation only. `previousAnonUid` is NOT sufficient authorization
        // for a merge. Production requires a server-issued one-time merge ticket
        // created WHILE the anonymous session A is still active (after
        // signInWithIdToken(B), A's JWT is no longer the current session).
        try {
          await _supabase.auth.linkIdentityWithIdToken(
            provider: OAuthProvider.apple,
            idToken: idToken,
            nonce: rawNonce,
          );
          // Refresh so the next backend JWT reflects the PERMANENT status (Ayden
          // keys on the `is_anonymous` claim — never continue on the old anon JWT).
          await _supabase.auth.refreshSession();
          final linkedUser = currentUser;
          final newUid = linkedUser?.id;
          if (newUid == null || newUid != previousUid) {
            throw StateError('Identity link invariant violated: anonymous UUID '
                'changed ($previousUid → $newUid).');
          }
          if (linkedUser?.isAnonymous == true) {
            throw StateError('Identity linked but user still anonymous after '
                'session refresh.');
          }
          debugPrint('[AuthService][LINK] provider=apple preserved uid=$newUid');
          return SignInResult(
            outcome: SignInOutcome.success,
            userId: newUid,
            wasAnonymousUpgrade: true,
          );
        } on AuthException catch (e) {
          if (e.code != 'identity_already_exists') {
            debugPrint('[AuthService][LINK_FAILED] provider=apple code=${e.code}');
            rethrow; // real failure (config/credential) → NOT a merge
          }
          // Apple identity already attached to another account B → sign into B.
          // QA-1: LOG MERGE_REQUIRED only; NO data of A is moved (no merge backend).
          debugPrint('[AuthService][LINK] provider=apple identity_already_exists '
              '→ signing into existing account (MERGE path)');
          await _supabase.auth.signInWithIdToken(
            provider: OAuthProvider.apple,
            idToken: idToken,
            nonce: rawNonce,
          );
          final newUid = currentUser?.id;
          if (newUid == null || newUid == previousUid) {
            throw StateError('Merge-path invariant violated: expected a '
                'different existing account (got $newUid for anon $previousUid).');
          }
          debugPrint('[AuthService][MERGE_REQUIRED] provider=apple '
              'from_anon=$previousUid to=$newUid');
          return SignInResult(
            outcome: SignInOutcome.success,
            userId: newUid,
            mergeRequired: true,
            previousAnonUid: previousUid,
          );
        }
      }

      // Already signed-in or no session → plain sign-in (no anon UUID to keep).
      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      final newUid = currentUser?.id;
      debugPrint('[AuthService] Apple sign-in (non-anon) — new_uid=$newUid');
      return SignInResult(outcome: SignInOutcome.success, userId: newUid);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const SignInResult(outcome: SignInOutcome.cancelled);
      }
      debugPrint('[AuthService] Apple sign-in error: ${e.code} ${e.message}');
      return SignInResult(
        outcome: SignInOutcome.failed,
        errorMessage: e.message,
      );
    } catch (e) {
      debugPrint('[AuthService] Apple sign-in unexpected error: $e');
      return SignInResult(
        outcome: SignInOutcome.failed,
        errorMessage: e.toString(),
      );
    }
  }

  // ── Anonymous-upgrade-aware Google Sign-In ─────────────────────────────

  Future<SignInResult> signInWithGoogle() async {
    try {
      // GoogleSignIn must be configured with the WEB OAuth client ID
      // (NOT the iOS/Android one) so Supabase can verify the ID token.
      // The iOS/Android client IDs are auto-resolved from
      // GoogleService-Info.plist / google-services.json at link time.
      final googleSignIn = GoogleSignIn(
        serverClientId: const String.fromEnvironment(
          'GOOGLE_WEB_CLIENT_ID',
          defaultValue: '',
        ),
        scopes: ['email', 'profile'],
      );

      final account = await googleSignIn.signIn();
      if (account == null) {
        return const SignInResult(outcome: SignInOutcome.cancelled);
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;
      final accessToken = auth.accessToken;
      if (idToken == null) {
        debugPrint('[AuthService] Google credential missing idToken');
        return const SignInResult(
          outcome: SignInOutcome.failed,
          errorMessage: 'Google sign-in returned no ID token',
        );
      }

      final wasAnon = isAnonymous;
      final previousUid = currentUser?.id;

      if (wasAnon) {
        // Google LINK — linkIdentityWithIdToken needs the idToken AND the
        // accessToken. Success → UUID preserved (invariants enforced below).
        // ONLY 'identity_already_exists' → sign into the existing account (B) and
        // flag MERGE_REQUIRED. Any other AuthException → rethrow (never a silent
        // fallback). QA-1 observation only: `previousAnonUid` is NOT merge
        // authorization; production needs a server-issued merge ticket created
        // while the anonymous session A is still active.
        try {
          await _supabase.auth.linkIdentityWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
            accessToken: accessToken,
          );
          await _supabase.auth.refreshSession();
          final linkedUser = currentUser;
          final newUid = linkedUser?.id;
          if (newUid == null || newUid != previousUid) {
            throw StateError('Identity link invariant violated: anonymous UUID '
                'changed ($previousUid → $newUid).');
          }
          if (linkedUser?.isAnonymous == true) {
            throw StateError('Identity linked but user still anonymous after '
                'session refresh.');
          }
          debugPrint('[AuthService][LINK] provider=google preserved uid=$newUid');
          return SignInResult(
            outcome: SignInOutcome.success,
            userId: newUid,
            wasAnonymousUpgrade: true,
          );
        } on AuthException catch (e) {
          if (e.code != 'identity_already_exists') {
            debugPrint('[AuthService][LINK_FAILED] provider=google code=${e.code}');
            rethrow; // real failure (config/credential) → NOT a merge
          }
          debugPrint('[AuthService][LINK] provider=google identity_already_exists '
              '→ signing into existing account (MERGE path)');
          await _supabase.auth.signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
            accessToken: accessToken,
          );
          final newUid = currentUser?.id;
          if (newUid == null || newUid == previousUid) {
            throw StateError('Merge-path invariant violated: expected a '
                'different existing account (got $newUid for anon $previousUid).');
          }
          debugPrint('[AuthService][MERGE_REQUIRED] provider=google '
              'from_anon=$previousUid to=$newUid');
          return SignInResult(
            outcome: SignInOutcome.success,
            userId: newUid,
            mergeRequired: true,
            previousAnonUid: previousUid,
          );
        }
      }

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      final newUid = currentUser?.id;
      debugPrint('[AuthService] Google sign-in (non-anon) — new_uid=$newUid');
      return SignInResult(outcome: SignInOutcome.success, userId: newUid);
    } catch (e) {
      debugPrint('[AuthService] Google sign-in unexpected error: $e');
      return SignInResult(
        outcome: SignInOutcome.failed,
        errorMessage: e.toString(),
      );
    }
  }

  // ── Sign-out ────────────────────────────────────────────────────────────

  /// Standard sign-out. Clears the Supabase session. No device-level lock
  /// is applied — the abuse path (sign out → fresh anon → reuse free
  /// generation) is intentionally left for Wave 5.17b's server-side quota
  /// enforcement to address, NOT for the identity layer.
  ///
  /// After sign-out, the app falls back to its existing onboarding /
  /// anonymous flow at next launch (see `main.dart`).
  Future<void> signOut() async {
    debugPrint('[AuthService] sign-out requested — clearing session');
    await _supabase.auth.signOut();
  }

  /// Restore an anonymous session if none is currently active. Idempotent :
  /// when the user already has any session (anonymous or signed-in), this
  /// is a no-op.
  ///
  /// Called from two sites :
  ///   1. After explicit sign-out (profile_screen.dart) — so the app
  ///      remains usable without an immediate sign-in wall.
  ///   2. main.dart at app launch — same logic, idempotent, gives a
  ///      single source of truth for "I want SOME session, please".
  ///
  /// Throws AuthException on failure ; caller decides whether to surface.
  Future<void> signInAnonymouslyIfNeeded() async {
    if (_supabase.auth.currentSession != null) return;
    debugPrint('[AuthService] no session active — signing in anonymously');
    final res = await _supabase.auth.signInAnonymously();
    debugPrint(
      '[AuthService] anonymous sign-in success — user_id: ${res.user?.id}',
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Generate a cryptographically random nonce for Apple Sign-In replay
  /// protection. 32-byte base64url-encoded string.
  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
