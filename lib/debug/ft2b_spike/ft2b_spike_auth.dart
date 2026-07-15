/// FT2-B spike — the DEVICE-ONLY auth actions.
///
/// Reuses the reference app's exact Apple recipe (rawNonce → SHA-256 → Apple
/// credential with the HASHED nonce → identityToken → Supabase with the RAW
/// nonce) but WITHOUT importing auth_service.dart. Every call goes through the
/// ISOLATED Supabase client (spike Keychain key), captures the real server
/// verdict into the pure models, and NEVER logs a token/nonce/JWT.
///
/// This file is integration-only (real Apple + Supabase); it is deliberately
/// thin, and the trustworthy logic it relies on is the PURE code in
/// ft2b_spike_models.dart / ft2b_spike_sanitizer.dart (which ARE unit-tested).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ft2b_spike_models.dart';
import 'ft2b_spike_sanitizer.dart';

/// Immutable snapshot of the isolated session, for read-only display.
class SpikeAuthSnapshot {
  final String? userId;
  final bool isAnonymous;
  final bool hasSession;
  final List<String> identities;

  const SpikeAuthSnapshot({
    required this.userId,
    required this.isAnonymous,
    required this.hasSession,
    required this.identities,
  });
}

class _AppleCredential {
  final String idToken;
  final String rawNonce;
  const _AppleCredential({required this.idToken, required this.rawNonce});
}

class Ft2bSpikeAuth {
  Ft2bSpikeAuth({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client {
    _sub = _client.auth.onAuthStateChange.listen((state) {
      _lastEvent = state.event.name;
    });
  }

  final SupabaseClient _client;
  StreamSubscription<AuthState>? _sub;
  String? _lastEvent;

  GoTrueClient get _auth => _client.auth;

  void dispose() {
    _sub?.cancel();
  }

  // ── Read-only state ────────────────────────────────────────────────────────

  SpikeAuthSnapshot snapshot() {
    final user = _auth.currentUser;
    return SpikeAuthSnapshot(
      userId: user?.id,
      isAnonymous: user?.isAnonymous ?? false,
      hasSession: _auth.currentSession != null,
      identities: _providerNames(user),
    );
  }

  static List<String> _providerNames(User? user) =>
      user?.identities?.map((i) => i.provider).toList() ?? const <String>[];

  // ── Apple recipe (own copy — no auth_service.dart import) ──────────────────

  static String _generateRawNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _sha256Hex(String s) =>
      sha256.convert(utf8.encode(s)).toString();

  Future<_AppleCredential> _getAppleCredential() async {
    final rawNonce = _generateRawNonce();
    final hashedNonce = _sha256Hex(rawNonce);
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce, // Apple gets the HASH
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw StateError('Apple credential returned no identityToken');
    }
    return _AppleCredential(idToken: idToken, rawNonce: rawNonce);
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Create the isolated anonymous user if none exists. Returns its UUID.
  Future<String?> ensureAnonymous() async {
    if (_auth.currentSession == null) {
      await _auth.signInAnonymously();
    }
    return _auth.currentUser?.id;
  }

  /// Phase B — link a NEW Apple identity. Success is only a HYPOTHESIS; the
  /// method records whatever actually happens.
  Future<PhaseBResult> linkNewAppleIdentity() async {
    final anonBefore = _auth.currentUser?.id;
    try {
      final cred = await _getAppleCredential();
      _lastEvent = null;
      await _auth.linkIdentityWithIdToken(
        provider: OAuthProvider.apple,
        idToken: cred.idToken,
        nonce: cred.rawNonce, // Supabase gets the RAW nonce
      );
      final after = _auth.currentUser;
      return PhaseBResult(
        anonymousIdBefore: anonBefore,
        userIdAfter: after?.id,
        uuidPreserved: uuidPreserved(anonBefore, after?.id),
        isAnonymousAfter: after?.isAnonymous ?? false,
        identitiesAfter: _providerNames(after),
        authEvent: _lastEvent,
        linkSucceeded: true,
        error: null,
      );
    } on AuthException catch (e) {
      _logStep('phase-b', e);
      return PhaseBResult(
        anonymousIdBefore: anonBefore,
        userIdAfter: _auth.currentUser?.id,
        uuidPreserved: false,
        isAnonymousAfter: _auth.currentUser?.isAnonymous ?? false,
        identitiesAfter: _providerNames(_auth.currentUser),
        authEvent: _lastEvent,
        linkSucceeded: false,
        error: SpikeAuthError.from(
          error: e,
          statusCode: e.statusCode,
          code: e.code,
          message: e.message,
        ),
      );
    } catch (e) {
      _logStep('phase-b', e);
      return PhaseBResult(
        anonymousIdBefore: anonBefore,
        userIdAfter: _auth.currentUser?.id,
        uuidPreserved: false,
        isAnonymousAfter: _auth.currentUser?.isAnonymous ?? false,
        identitiesAfter: _providerNames(_auth.currentUser),
        authEvent: _lastEvent,
        linkSucceeded: false,
        error: SpikeAuthError.from(error: e, message: e.toString()),
      );
    }
  }

  /// Prepare Phase C: sign out (LOCAL only) and create a fresh anonymous user.
  /// Never deletes any Auth user or DB row. Returns the new anon UUID.
  Future<String?> prepareNewAnonymous() async {
    await _auth.signOut(scope: SignOutScope.local);
    await _auth.signInAnonymously();
    return _auth.currentUser?.id;
  }

  /// Phase C — link the SAME Apple identity from a DIFFERENT anon. Captures the
  /// real result and confirms the original session survived the failure.
  Future<PhaseCResult> linkSameAppleIdentity() async {
    final anonBefore = _auth.currentUser?.id;
    try {
      final cred = await _getAppleCredential();
      await _auth.linkIdentityWithIdToken(
        provider: OAuthProvider.apple,
        idToken: cred.idToken,
        nonce: cred.rawNonce,
      );
      // If we reach here the link unexpectedly SUCCEEDED — record it truthfully.
      final after = _auth.currentUser;
      return PhaseCResult(
        collisionAnonIdBefore: anonBefore,
        linkSucceeded: true,
        error: null,
        activeUserIdAfter: after?.id,
        activeSessionPreserved: sessionPreserved(
          hasSessionAfter: _auth.currentSession != null,
          anonIdBefore: anonBefore,
          activeUserIdAfter: after?.id,
        ),
        isAnonymousAfter: after?.isAnonymous ?? false,
        identitiesAfter: _providerNames(after),
      );
    } on AuthException catch (e) {
      _logStep('phase-c', e);
      final after = _auth.currentUser;
      return PhaseCResult(
        collisionAnonIdBefore: anonBefore,
        linkSucceeded: false,
        error: SpikeAuthError.from(
          error: e,
          statusCode: e.statusCode,
          code: e.code,
          message: e.message,
        ),
        activeUserIdAfter: after?.id,
        activeSessionPreserved: sessionPreserved(
          hasSessionAfter: _auth.currentSession != null,
          anonIdBefore: anonBefore,
          activeUserIdAfter: after?.id,
        ),
        isAnonymousAfter: after?.isAnonymous ?? false,
        identitiesAfter: _providerNames(after),
      );
    } catch (e) {
      _logStep('phase-c', e);
      final after = _auth.currentUser;
      return PhaseCResult(
        collisionAnonIdBefore: anonBefore,
        linkSucceeded: false,
        error: SpikeAuthError.from(error: e, message: e.toString()),
        activeUserIdAfter: after?.id,
        activeSessionPreserved: sessionPreserved(
          hasSessionAfter: _auth.currentSession != null,
          anonIdBefore: anonBefore,
          activeUserIdAfter: after?.id,
        ),
        isAnonymousAfter: after?.isAnonymous ?? false,
        identitiesAfter: _providerNames(after),
      );
    }
  }

  /// "Verify existing-account sign-in": prove the Apple identity belongs to the
  /// Phase B permanent account. Uses signInWithIdToken (NOT link). No backend
  /// Identity merge is triggered.
  Future<VerifySignInResult> verifyExistingSignIn(String? phaseBId) async {
    try {
      final cred = await _getAppleCredential();
      await _auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: cred.idToken,
        nonce: cred.rawNonce,
      );
      final signedId = _auth.currentUser?.id;
      return VerifySignInResult(
        signedInUserId: signedId,
        phaseBPermanentId: phaseBId,
        matchesPhaseB:
            signedId != null && phaseBId != null && signedId == phaseBId,
        error: null,
      );
    } on AuthException catch (e) {
      _logStep('verify', e);
      return VerifySignInResult(
        signedInUserId: _auth.currentUser?.id,
        phaseBPermanentId: phaseBId,
        matchesPhaseB: false,
        error: SpikeAuthError.from(
          error: e,
          statusCode: e.statusCode,
          code: e.code,
          message: e.message,
        ),
      );
    } catch (e) {
      _logStep('verify', e);
      return VerifySignInResult(
        signedInUserId: _auth.currentUser?.id,
        phaseBPermanentId: phaseBId,
        matchesPhaseB: false,
        error: SpikeAuthError.from(error: e, message: e.toString()),
      );
    }
  }

  /// Log ONLY step + type + sanitized fields. NEVER debugPrint(e) / print(e).
  void _logStep(String step, Object error) {
    String? statusCode;
    String? code;
    String? message;
    if (error is AuthException) {
      statusCode = error.statusCode;
      code = error.code;
      message = error.message;
    } else {
      message = error.toString();
    }
    debugPrint(
      '[FT2B-spike/$step] ${error.runtimeType} '
      'status=$statusCode code=$code msg=${sanitizeText(message)}',
    );
  }
}
