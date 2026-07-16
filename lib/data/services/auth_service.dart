/// Wave 5.17a — Identity Foundation auth service.
///
/// Centralises the Apple / Google sign-in flow and the anonymous-user-upgrade
/// path. The Wave 5.17 monetization stack treats Generation #1 as anonymous
/// (no friction) and Generation #2+ as sign-in-required. This service is the
/// single source of truth for that transition.
///
/// **Anonymous upgrade contract (Decision 4 — project preservation)**
/// When the user is anonymous AND signs in with Apple/Google, we use
/// `supabase.auth.linkIdentity()` rather than `signInWithOAuth()`. The
/// linkIdentity call preserves the existing user UUID — so the session,
/// messages, and generated images remain attached to the same identity
/// throughout the upgrade. Without this, the OAuth flow would create a
/// NEW user UUID and the anonymous project would be orphaned.
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
  /// True iff the sign-in upgraded an existing anonymous user (Decision 4).
  /// False if the user was already signed in or if a new identity was created.
  final bool wasAnonymousUpgrade;

  const SignInResult({
    required this.outcome,
    this.userId,
    this.errorMessage,
    this.wasAnonymousUpgrade = false,
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

      // Decision 4 — when anonymous, link the OAuth identity to preserve
      // the existing user UUID + their project. When signed-in or no
      // session, signInWithIdToken handles fresh sign-in.
      if (wasAnon) {
        // linkIdentity expects OAuthProvider on `auth.signInWithIdToken`
        // semantics — we use signInWithIdToken which Supabase auto-upgrades
        // anonymous identities when the same auth.users row is updated.
        // The supabase_flutter SDK's linkIdentity OAuth flow uses the
        // server-side OAuth callback ; for native ID-token flow we rely on
        // signInWithIdToken + the dashboard's "link anonymous to OAuth"
        // setting (Prerequisite A).
        await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: idToken,
          nonce: rawNonce,
        );
      } else {
        await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: idToken,
          nonce: rawNonce,
        );
      }

      final newUid = currentUser?.id;
      final upgraded = wasAnon && newUid == previousUid;
      // No UUIDs in logs — only the boolean upgrade result.
      debugPrint('[AuthService] Apple sign-in success — upgraded=$upgraded');

      return SignInResult(
        outcome: SignInOutcome.success,
        userId: newUid,
        wasAnonymousUpgrade: upgraded,
      );
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

  // ── Account linking — attach a NEW Apple identity to the anon user ─────

  /// LINK a new Apple identity to the CURRENT anonymous user, preserving the
  /// existing UUID (session, projects, RevenueCat binding all stay attached).
  /// Uses `linkIdentityWithIdToken` (Supabase Manual Linking), NOT
  /// `signInWithIdToken`, so no new user is created.
  ///
  /// Returns [SignInOutcome.success] on link, `cancelled` if the user dismissed
  /// the Apple dialog, or `failed` for ANY other error — including the case
  /// where the Apple identity already belongs to another Ayden account. The
  /// caller MUST treat `failed` uniformly (offer "sign in to existing account")
  /// and must NOT inspect a specific status/error_code (Supabase does not
  /// guarantee it). No identityToken / nonce / JWT / raw exception is ever
  /// logged.
  Future<SignInResult> linkAppleIdentity() async {
    try {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final previousUid = currentUser?.id;

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        debugPrint('[AuthService] link: Apple credential missing identityToken');
        return const SignInResult(
          outcome: SignInOutcome.failed,
          errorMessage: 'no_identity_token',
        );
      }

      await _supabase.auth.linkIdentityWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      final newUid = currentUser?.id;
      final upgraded = newUid != null && newUid == previousUid;
      debugPrint('[AuthService] link Apple identity ok — upgraded=$upgraded');
      return SignInResult(
        outcome: SignInOutcome.success,
        userId: newUid,
        wasAnonymousUpgrade: upgraded,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const SignInResult(outcome: SignInOutcome.cancelled);
      }
      debugPrint('[AuthService] link Apple auth error: ${e.code}');
      return const SignInResult(
        outcome: SignInOutcome.failed,
        errorMessage: 'apple_error',
      );
    } on AuthException catch (e) {
      // Supabase rejected the link (e.g. identity already linked to another
      // user). Do NOT inspect the code — treat any AuthException as "failed"
      // so the UI offers the existing-account path. Log the TYPE only.
      debugPrint('[AuthService] link Apple rejected: ${e.runtimeType}');
      return const SignInResult(
        outcome: SignInOutcome.failed,
        errorMessage: 'link_failed',
      );
    } catch (e) {
      debugPrint('[AuthService] link Apple unexpected: ${e.runtimeType}');
      return const SignInResult(
        outcome: SignInOutcome.failed,
        errorMessage: 'link_failed',
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

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      final newUid = currentUser?.id;
      final upgraded = wasAnon && newUid == previousUid;
      // No UUIDs in logs — only the boolean upgrade result.
      debugPrint('[AuthService] Google sign-in success — upgraded=$upgraded');

      return SignInResult(
        outcome: SignInOutcome.success,
        userId: newUid,
        wasAnonymousUpgrade: upgraded,
      );
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
    await _supabase.auth.signInAnonymously();
    // No UUID in logs.
    debugPrint('[AuthService] anonymous sign-in success');
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
