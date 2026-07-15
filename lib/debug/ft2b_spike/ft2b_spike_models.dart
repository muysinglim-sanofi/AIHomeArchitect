/// FT2-B spike — PURE data models, guards & state machine.
///
/// All decision logic that must be trustworthy (phase ordering, protected-account
/// guard, UUID-preservation, session-preservation, report shape) lives here as
/// pure functions/classes so it can be unit-tested WITHOUT a device, network, or
/// Supabase. The device run only supplies the raw inputs.
library;

import 'ft2b_spike_sanitizer.dart';

/// Documented stack versions — embedded verbatim in the report so a device
/// result is unambiguous about what produced it. (Do NOT auto-detect at runtime;
/// these are asserted against the pinned pubspec.lock.)
const String kGotrueVersion = '2.20.0';
const String kSupabaseVersion = '2.10.6';
const String kSupabaseFlutterVersion = '2.12.4';

/// Protected PRODUCTION account. The spike refuses every phase if the isolated
/// session ever resolves to this UUID. It never should (separate Keychain key),
/// but this is a hard belt-and-braces guard.
const String kProtectedAccountId = '5d144b46-a439-4feb-8d3b-29c1f5e5cdc2';

/// Spike phase ordering. Phase C (collision) is reachable only AFTER Phase B
/// (new link) produced a permanent account AND a fresh anonymous user was
/// prepared — a device run cannot skip steps.
enum SpikePhase { start, anonReady, phaseBDone, phaseCPrepared, phaseCDone }

/// True iff [userId] is the protected production account.
bool isProtectedAccount(String? userId) =>
    userId != null && userId == kProtectedAccountId;

/// Phase B (link a NEW Apple identity) may run only from a fresh anonymous user.
bool canRunPhaseB(SpikePhase phase, {required bool isAnonymous}) =>
    phase == SpikePhase.anonReady && isAnonymous;

/// Preparing Phase C (sign out + new anon) requires Phase B to have completed.
bool canPreparePhaseC(SpikePhase phase) => phase == SpikePhase.phaseBDone;

/// Phase C (link the SAME Apple identity from a DIFFERENT anon) requires the
/// fresh-anon preparation to have run. This is the guard that blocks Phase C
/// before Phase B.
bool canRunPhaseC(SpikePhase phase) => phase == SpikePhase.phaseCPrepared;

/// Did the permanent UUID survive the Phase B upgrade (anon → permanent)?
bool uuidPreserved(String? before, String? after) =>
    before != null && after != null && before == after;

/// After a Phase C collision, is the caller's ORIGINAL session still active and
/// unchanged? True iff a session remains AND the active user is still the
/// pre-collision anon (i.e. the failed link did not mutate identity).
bool sessionPreserved({
  required bool hasSessionAfter,
  required String? anonIdBefore,
  required String? activeUserIdAfter,
}) =>
    hasSessionAfter &&
    anonIdBefore != null &&
    activeUserIdAfter != null &&
    anonIdBefore == activeUserIdAfter;

/// Sanitized capture of an auth failure. No raw token / nonce / JWT survives:
/// [message] is passed through [sanitizeText] at construction.
class SpikeAuthError {
  final String runtimeTypeName;

  /// gotrue exposes `statusCode` as a STRING (e.g. "422"), never an int.
  final String? statusCode;
  final String? code;
  final String sanitizedMessage;

  const SpikeAuthError({
    required this.runtimeTypeName,
    required this.statusCode,
    required this.code,
    required this.sanitizedMessage,
  });

  factory SpikeAuthError.from({
    required Object error,
    String? statusCode,
    String? code,
    String? message,
  }) => SpikeAuthError(
    runtimeTypeName: error.runtimeType.toString(),
    statusCode: statusCode,
    code: code,
    sanitizedMessage: sanitizeText(message),
  );

  Map<String, dynamic> toJson() => {
    'runtime_type': runtimeTypeName,
    'status_code': statusCode,
    'code': code,
    'sanitized_message': sanitizedMessage,
  };

  @override
  String toString() => 'SpikeAuthError(${toJson()})';
}

/// Phase B — link a NEW Apple identity to the anonymous user.
class PhaseBResult {
  final String? anonymousIdBefore;
  final String? userIdAfter;
  final bool uuidPreserved;
  final bool isAnonymousAfter;
  final List<String> identitiesAfter; // provider names only
  final String? authEvent;
  final bool linkSucceeded;
  final SpikeAuthError? error;

  const PhaseBResult({
    required this.anonymousIdBefore,
    required this.userIdAfter,
    required this.uuidPreserved,
    required this.isAnonymousAfter,
    required this.identitiesAfter,
    required this.authEvent,
    required this.linkSucceeded,
    required this.error,
  });

  Map<String, dynamic> toJson() => {
    'anonymous_id_before': anonymousIdBefore,
    'user_id_after': userIdAfter,
    'uuid_preserved': uuidPreserved,
    'is_anonymous_after': isAnonymousAfter,
    'identities_after': identitiesAfter,
    'auth_event': authEvent,
    'link_succeeded': linkSucceeded,
    'error': error?.toJson(),
  };

  @override
  String toString() => 'PhaseBResult(${toJson()})';
}

/// Phase C — link the SAME Apple identity from a DIFFERENT anon (collision).
class PhaseCResult {
  final String? collisionAnonIdBefore;
  final bool linkSucceeded;
  final SpikeAuthError? error;
  final String? activeUserIdAfter;
  final bool activeSessionPreserved;
  final bool isAnonymousAfter;
  final List<String> identitiesAfter;

  const PhaseCResult({
    required this.collisionAnonIdBefore,
    required this.linkSucceeded,
    required this.error,
    required this.activeUserIdAfter,
    required this.activeSessionPreserved,
    required this.isAnonymousAfter,
    required this.identitiesAfter,
  });

  Map<String, dynamic> toJson() => {
    'collision_anon_id_before': collisionAnonIdBefore,
    'link_succeeded': linkSucceeded,
    'error': error?.toJson(),
    'active_user_id_after': activeUserIdAfter,
    'active_session_preserved': activeSessionPreserved,
    'is_anonymous_after': isAnonymousAfter,
    'identities_after': identitiesAfter,
  };

  @override
  String toString() => 'PhaseCResult(${toJson()})';
}

/// "Verify existing-account sign-in" — prove the Apple identity belongs to the
/// Phase B permanent account (uses signInWithIdToken, NOT link).
class VerifySignInResult {
  final String? signedInUserId;
  final String? phaseBPermanentId;
  final bool matchesPhaseB;
  final SpikeAuthError? error;

  const VerifySignInResult({
    required this.signedInUserId,
    required this.phaseBPermanentId,
    required this.matchesPhaseB,
    required this.error,
  });

  Map<String, dynamic> toJson() => {
    'signed_in_user_id': signedInUserId,
    'phase_b_permanent_id': phaseBPermanentId,
    'matches_phase_b': matchesPhaseB,
    'error': error?.toJson(),
  };

  @override
  String toString() => 'VerifySignInResult(${toJson()})';
}

/// Aggregated, copyable report. `toSanitizedJson()` contains ONLY: test UUIDs,
/// booleans, provider names, runtime type, status code, error code, sanitized
/// messages, timestamps, and documented versions — never a token/nonce/JWT.
class SpikeReport {
  final String? testUserId;
  final PhaseBResult? phaseB;
  final PhaseCResult? phaseC;
  final VerifySignInResult? verify;
  final String capturedAtIso;

  const SpikeReport({
    required this.testUserId,
    required this.phaseB,
    required this.phaseC,
    required this.verify,
    required this.capturedAtIso,
  });

  Map<String, dynamic> toSanitizedJson() => {
    'spike': 'ft2b_apple_identity_link',
    'versions': {
      'gotrue': kGotrueVersion,
      'supabase': kSupabaseVersion,
      'supabase_flutter': kSupabaseFlutterVersion,
    },
    'test_user_id': testUserId,
    'captured_at': capturedAtIso,
    'phase_b': phaseB?.toJson(),
    'phase_c': phaseC?.toJson(),
    'verify': verify?.toJson(),
  };
}
