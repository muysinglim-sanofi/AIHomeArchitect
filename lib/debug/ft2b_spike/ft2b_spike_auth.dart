/// FT2-B spike — the DEVICE-ONLY auth actions.
///
/// Reuses the reference app's exact Apple recipe (rawNonce → SHA-256 → Apple
/// credential with the HASHED nonce → identityToken → Supabase with the RAW
/// nonce) but WITHOUT importing auth_service.dart. Every call goes through the
/// ISOLATED Supabase client (spike Keychain key), captures the real server
/// verdict into the pure models, and NEVER logs a token/nonce/JWT.
///
/// SAME-ACCOUNT GUARD: the Apple `sub` is read LOCALLY from each identity token
/// payload (Phase C fails BEFORE the identity is attached to the user, so it
/// cannot be read from `currentUser.identities`). The raw sub is held IN MEMORY
/// ONLY (never logged/persisted/reported). Phase C refuses to call Supabase
/// unless its sub equals Phase B's — so an accidental different Apple ID can
/// never be mistaken for a collision.
///
/// This file is integration-only (real Apple + Supabase); the trustworthy logic
/// it relies on is the PURE code in ft2b_spike_models.dart / _sanitizer.dart /
/// _jwt.dart (which ARE unit-tested).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ft2b_spike_jwt.dart';
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

  // Phase B Apple claims — IN-MEMORY ONLY. NEVER logged/persisted/reported.
  String? _appleSubB;
  List<String>? _appleAudB;

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
  /// method records whatever actually happens. Captures the Apple sub/aud
  /// locally (sub kept in memory only) for the Phase C same-account guard.
  Future<PhaseBResult> linkNewAppleIdentity() async {
    final anonBefore = _auth.currentUser?.id;
    AppleTokenClaims? claims;
    try {
      final cred = await _getAppleCredential();
      claims = decodeAppleIdentityTokenClaims(cred.idToken);
      _appleSubB = claims?.sub; // in-memory only
      _appleAudB = claims?.aud;
      _lastEvent = null;
      await _auth.linkIdentityWithIdToken(
        provider: OAuthProvider.apple,
        idToken: cred.idToken,
        nonce: cred.rawNonce, // Supabase gets the RAW nonce
      );
      return _buildPhaseB(
        after: _auth.currentUser,
        anonBefore: anonBefore,
        claims: claims,
        linkSucceeded: true,
        error: null,
      );
    } on AuthException catch (e) {
      _logStep('phase-b', e);
      return _buildPhaseB(
        after: _auth.currentUser,
        anonBefore: anonBefore,
        claims: claims,
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
      return _buildPhaseB(
        after: _auth.currentUser,
        anonBefore: anonBefore,
        claims: claims,
        linkSucceeded: false,
        error: SpikeAuthError.from(error: e, message: e.toString()),
      );
    }
  }

  PhaseBResult _buildPhaseB({
    required User? after,
    required String? anonBefore,
    required AppleTokenClaims? claims,
    required bool linkSucceeded,
    required SpikeAuthError? error,
  }) => PhaseBResult(
    anonymousIdBefore: anonBefore,
    userIdAfter: after?.id,
    uuidPreserved: linkSucceeded ? uuidPreserved(anonBefore, after?.id) : false,
    isAnonymousAfter: after?.isAnonymous ?? false,
    identitiesAfter: _providerNames(after),
    authEvent: _lastEvent,
    linkSucceeded: linkSucceeded,
    error: error,
    appleSubPresent: claims?.hasSub ?? false,
    appleAud: claims?.aud ?? const [],
    appleAudMatchesExpected: claims?.audContains(kExpectedSpikeAud) ?? false,
  );

  /// Prepare Phase C: sign out (LOCAL only) and create a fresh anonymous user.
  /// Never deletes any Auth user or DB row. Returns the new anon UUID.
  Future<String?> prepareNewAnonymous() async {
    await _auth.signOut(scope: SignOutScope.local);
    await _auth.signInAnonymously();
    return _auth.currentUser?.id;
  }

  /// Phase C — link the SAME Apple identity from a DIFFERENT anon. The Apple
  /// sub is decoded locally FIRST; if it is absent or differs from Phase B, the
  /// method REFUSES to call Supabase (no second Apple account is ever linked)
  /// and records `invalid_reason`. Only on a confirmed same-sub does it attempt
  /// the link and capture the REAL result — never assuming the error.
  Future<PhaseCResult> linkSameAppleIdentity() async {
    final anonBefore = _auth.currentUser?.id;

    _AppleCredential cred;
    try {
      cred = await _getAppleCredential();
    } catch (e) {
      _logStep('phase-c', e);
      return _buildPhaseC(
        anonBefore: anonBefore,
        claims: null,
        subSame: false,
        linkAttempted: false,
        linkSucceeded: false,
        invalidReason: 'apple_credential_failed',
        error: SpikeAuthError.from(error: e, message: e.toString()),
        after: _auth.currentUser,
      );
    }

    final claims = decodeAppleIdentityTokenClaims(cred.idToken);
    final subC = claims?.sub;
    final subPresentC = claims?.hasSub ?? false;
    final subSame = _appleSubB != null && subC != null && _appleSubB == subC;

    // GUARD §7 — same Apple account required before touching Supabase.
    if (_appleSubB == null || !subPresentC || !subSame) {
      final reason = _appleSubB == null
          ? 'phase_b_sub_missing'
          : (!subPresentC ? 'apple_sub_absent' : 'different_apple_identity');
      return _buildPhaseC(
        anonBefore: anonBefore,
        claims: claims,
        subSame: subSame,
        linkAttempted: false,
        linkSucceeded: false,
        invalidReason: reason,
        error: null,
        after: _auth.currentUser,
      );
    }

    // Confirmed same Apple sub → attempt the link, capture the real outcome.
    try {
      await _auth.linkIdentityWithIdToken(
        provider: OAuthProvider.apple,
        idToken: cred.idToken,
        nonce: cred.rawNonce,
      );
      return _buildPhaseC(
        anonBefore: anonBefore,
        claims: claims,
        subSame: true,
        linkAttempted: true,
        linkSucceeded: true, // unexpected — recorded truthfully
        invalidReason: null,
        error: null,
        after: _auth.currentUser,
      );
    } on AuthException catch (e) {
      _logStep('phase-c', e);
      return _buildPhaseC(
        anonBefore: anonBefore,
        claims: claims,
        subSame: true,
        linkAttempted: true,
        linkSucceeded: false,
        invalidReason: null,
        error: SpikeAuthError.from(
          error: e,
          statusCode: e.statusCode,
          code: e.code,
          message: e.message,
        ),
        after: _auth.currentUser,
      );
    } catch (e) {
      _logStep('phase-c', e);
      return _buildPhaseC(
        anonBefore: anonBefore,
        claims: claims,
        subSame: true,
        linkAttempted: true,
        linkSucceeded: false,
        invalidReason: null,
        error: SpikeAuthError.from(error: e, message: e.toString()),
        after: _auth.currentUser,
      );
    }
  }

  PhaseCResult _buildPhaseC({
    required String? anonBefore,
    required AppleTokenClaims? claims,
    required bool subSame,
    required bool linkAttempted,
    required bool linkSucceeded,
    required String? invalidReason,
    required SpikeAuthError? error,
    required User? after,
  }) => PhaseCResult(
    collisionAnonIdBefore: anonBefore,
    linkAttempted: linkAttempted,
    linkSucceeded: linkSucceeded,
    invalidReason: invalidReason,
    error: error,
    activeUserIdAfter: after?.id,
    activeSessionPreserved: sessionPreserved(
      hasSessionAfter: _auth.currentSession != null,
      anonIdBefore: anonBefore,
      activeUserIdAfter: after?.id,
    ),
    isAnonymousAfter: after?.isAnonymous ?? false,
    identitiesAfter: _providerNames(after),
    appleSubPresent: claims?.hasSub ?? false,
    appleSubSameBC: subSame,
    appleAud: claims?.aud ?? const [],
    appleAudMatchesExpected: claims?.audContains(kExpectedSpikeAud) ?? false,
    appleAudSameBC: _audSameBC(claims),
  );

  bool _audSameBC(AppleTokenClaims? claimsC) {
    final b = _appleAudB;
    final c = claimsC?.aud;
    if (b == null || c == null || b.length != c.length) {
      return false;
    }
    final bs = b.toSet();
    final cs = c.toSet();
    return bs.containsAll(cs) && cs.containsAll(bs);
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
