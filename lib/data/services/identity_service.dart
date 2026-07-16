/// FT2-A — Unified Identity client (DORMANT).
///
/// Thin, backend-authoritative client over the four Unified-Identity endpoints.
/// It only sends the CURRENT Supabase JWT and renders the backend's verdict.
/// It NEVER decides new-account-vs-existing-account (that is the FT2-B spike,
/// which will use linkIdentityWithIdToken + verify the real error on our
/// Supabase version) and NEVER stores or logs a provider token or the JWT.
///
///   POST /identity/anon-init          → {eligible, reason}                (mark eligible)
///   POST /identity/claim-signup-bonus → {decision, reason, bonus_granted} (grant +2)
///   POST /identity/merge-ticket       → {ticket, expires_at}             (A starts a merge)
///   POST /identity/claim              → {status, merge_id}               (B claims A's ticket)
///
/// All four are flag-gated DORMANT server-side (404 not_found while their env
/// flags are OFF). This client is NOT wired to any auth / boot / UI flow in
/// FT2-A; it is a standalone tool for FT2-B/C to call later.
///
/// Mirrors the JWT-injection Dio convention of PromoService / StatusService
/// (own Dio, request-time Bearer, validateStatus < 500 to read error codes).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supplies the current bearer token (JWT) at REQUEST time. Injectable for
/// tests; the production default reads the live Supabase session so a token
/// refresh between two calls is picked up on the next request (never cached).
typedef IdentityAccessTokenProvider = String? Function();

/// Coarse backend-response classification shared by all Identity endpoints.
/// Deliberately does NOT interpret new-vs-existing account (FT2-B concern).
enum IdentityOutcome {
  /// 2xx — the backend accepted and returned a business result.
  success,

  /// 404 not_found — the endpoint's server flag is OFF (dormant). Expected in
  /// FT2-A; callers must treat this as "feature not active", never an error.
  featureDisabled,

  /// 403 identity_merged — this account was merged-closed; the caller must stop
  /// using it and re-establish identity.
  mergedIdentity,

  /// 5xx / network / 409 settlement_active — transient. All endpoints are
  /// idempotent, so a manual retry (or retry-on-next-boot) is safe.
  retryableFailure,

  /// Other 4xx (not_anonymous, both_users_premium, conflict, ticket_expired,
  /// ticket_invalid, validation…) — permanent for this attempt; do not retry.
  terminalFailure,
}

/// Reads the backend machine error code from FastAPI's `{detail:{error_code}}`.
/// Returns null for success bodies or unexpected shapes.
String? identityErrorCode(Object? data) {
  if (data is Map && data['detail'] is Map) {
    return (data['detail'] as Map)['error_code'] as String?;
  }
  return null;
}

/// PURE classifier: (HTTP status, body) → [IdentityOutcome]. No I/O — unit-tested
/// directly. Keeps every call site's error handling consistent.
IdentityOutcome classifyIdentityOutcome(int? statusCode, Object? data) {
  if (statusCode == null) {
    return IdentityOutcome.retryableFailure; // network / timeout
  }
  if (statusCode >= 200 && statusCode < 300) {
    return IdentityOutcome.success;
  }
  final code = identityErrorCode(data);
  if (statusCode == 404 && code == 'not_found') {
    return IdentityOutcome.featureDisabled;
  }
  if (statusCode == 403 && code == 'identity_merged') {
    return IdentityOutcome.mergedIdentity;
  }
  if (statusCode >= 500) {
    return IdentityOutcome.retryableFailure;
  }
  if (statusCode == 409 && code == 'settlement_active') {
    return IdentityOutcome.retryableFailure;
  }
  return IdentityOutcome.terminalFailure; // 400 / 409 / 410 / 422 / other 4xx
}

/// Bearer header value for a JWT, or null when the token is absent/empty (no
/// Authorization header is then sent). PURE — unit-tested.
String? bearerHeader(String? token) =>
    (token != null && token.isNotEmpty) ? 'Bearer $token' : null;

// ── Per-endpoint typed results (loss-less: carry the backend's own fields) ──

/// POST /identity/anon-init result. Success carries {eligible, reason}
/// (marked | already_eligible | already_granted | merged_closed |
/// not_anonymous | user_not_found).
class AnonInitResult {
  final IdentityOutcome outcome;
  final bool? eligible;
  final String? reason;
  final String? errorCode;
  const AnonInitResult({
    required this.outcome,
    this.eligible,
    this.reason,
    this.errorCode,
  });

  factory AnonInitResult.from(int? statusCode, Object? data) {
    final o = classifyIdentityOutcome(statusCode, data);
    if (o == IdentityOutcome.success && data is Map) {
      return AnonInitResult(
        outcome: o,
        eligible: data['eligible'] == true,
        reason: data['reason'] as String?,
      );
    }
    return AnonInitResult(outcome: o, errorCode: identityErrorCode(data));
  }
}

/// POST /identity/claim-signup-bonus result. Success carries {decision,
/// bonus_granted} (granted | already_entitled | already_processed |
/// merged_closed | not_eligible). Idempotent: already_* is a success.
class SignupBonusResult {
  final IdentityOutcome outcome;
  final String? decision;
  final int? bonusGranted;
  final String? reason;
  final String? errorCode;
  const SignupBonusResult({
    required this.outcome,
    this.decision,
    this.bonusGranted,
    this.reason,
    this.errorCode,
  });

  bool get isGranted => decision == 'granted';
  bool get isAlready =>
      decision == 'already_processed' || decision == 'already_entitled';

  factory SignupBonusResult.from(int? statusCode, Object? data) {
    final o = classifyIdentityOutcome(statusCode, data);
    if (o == IdentityOutcome.success && data is Map) {
      return SignupBonusResult(
        outcome: o,
        decision: data['decision'] as String?,
        bonusGranted: (data['bonus_granted'] as num?)?.toInt(),
        reason: data['reason'] as String?,
      );
    }
    return SignupBonusResult(outcome: o, errorCode: identityErrorCode(data));
  }
}

/// POST /identity/merge-ticket result. Success carries the raw {ticket} (once)
/// + {expires_at}. The raw ticket is a short-lived secret — never logged.
class MergeTicketResult {
  final IdentityOutcome outcome;
  final String? ticket;
  final String? expiresAt;
  final String? errorCode;
  const MergeTicketResult({
    required this.outcome,
    this.ticket,
    this.expiresAt,
    this.errorCode,
  });

  factory MergeTicketResult.from(int? statusCode, Object? data) {
    final o = classifyIdentityOutcome(statusCode, data);
    if (o == IdentityOutcome.success && data is Map) {
      return MergeTicketResult(
        outcome: o,
        ticket: data['ticket'] as String?,
        expiresAt: data['expires_at'] as String?,
      );
    }
    return MergeTicketResult(outcome: o, errorCode: identityErrorCode(data));
  }
}

/// POST /identity/claim result. Success carries {status, merge_id}
/// (completed | revocation_pending | identity_merge_pending | billing_pending).
class ClaimResult {
  final IdentityOutcome outcome;
  final String? status;
  final String? mergeId;
  final String? errorCode;

  /// Diagnostic id the backend attaches to a 409 `conflict` detail
  /// (`existing_merge_id`). Carried loss-lessly for a future manual-review UX;
  /// the dormant FT2-A client never acts on it.
  final String? existingMergeId;
  const ClaimResult({
    required this.outcome,
    this.status,
    this.mergeId,
    this.errorCode,
    this.existingMergeId,
  });

  factory ClaimResult.from(int? statusCode, Object? data) {
    final o = classifyIdentityOutcome(statusCode, data);
    if (o == IdentityOutcome.success && data is Map) {
      return ClaimResult(
        outcome: o,
        status: data['status'] as String?,
        mergeId: data['merge_id']?.toString(),
      );
    }
    final detail = (data is Map && data['detail'] is Map)
        ? data['detail'] as Map
        : null;
    return ClaimResult(
      outcome: o,
      errorCode: identityErrorCode(data),
      existingMergeId: detail?['existing_merge_id']?.toString(),
    );
  }
}

/// Dormant Identity client. Never throws (returns typed results); never retries
/// automatically (endpoints are idempotent → callers retry manually / on boot).
class IdentityService {
  late final Dio _dio;
  final IdentityAccessTokenProvider _tokenProvider;

  /// Production call site uses `IdentityService()` — byte-identical behaviour to
  /// before the seam: a fresh Dio (dotenv baseUrl, 15s timeouts, validateStatus
  /// < 500) + the live Supabase session token, read at request time.
  ///
  /// The three optional parameters are a TEST seam only (no production caller
  /// passes them): [dio] lets a test install a fake `HttpClientAdapter` and
  /// observe the real request (URL / method / body / Authorization) without a
  /// network; [accessTokenProvider] supplies a fake token so the interceptor
  /// runs without a live Supabase; [baseUrl] overrides the dotenv base. None of
  /// them changes the default production path.
  IdentityService({
    Dio? dio,
    IdentityAccessTokenProvider? accessTokenProvider,
    String? baseUrl,
  }) : _tokenProvider = accessTokenProvider ?? _defaultAccessToken {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl:
                baseUrl ??
                dotenv.env['API_BASE_URL'] ??
                'http://localhost:8000',
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
            // Accept 4xx so we can read the backend error_code instead of throwing.
            validateStatus: (s) => s != null && s < 500,
          ),
        );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Recomputed on EVERY request → a token refresh between calls is seen.
          final h = bearerHeader(_tokenProvider());
          if (h != null) options.headers['Authorization'] = h;
          handler.next(options);
        },
      ),
    );
  }

  /// Default provider: the live Supabase session's access token (may be null
  /// before an anonymous session exists). Read lazily, per request.
  static String? _defaultAccessToken() =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  /// POST /identity/anon-init — mark the current anonymous user signup-eligible.
  /// Idempotent; intended to run once at first anonymous boot AND safe to retry.
  Future<AnonInitResult> anonInit() async {
    try {
      final r = await _dio.post('/identity/anon-init');
      return AnonInitResult.from(r.statusCode, r.data);
    } catch (e) {
      // Log the TYPE only — never the exception body (may carry URL/headers).
      debugPrint('[IdentityService] anon-init failed: ${e.runtimeType}');
      return const AnonInitResult(
        outcome: IdentityOutcome.retryableFailure,
        errorCode: 'network',
      );
    }
  }

  /// POST /identity/claim-signup-bonus — grant +2 after a real new account.
  /// Idempotent (already_processed / already_entitled).
  Future<SignupBonusResult> claimSignupBonus() async {
    try {
      final r = await _dio.post('/identity/claim-signup-bonus');
      return SignupBonusResult.from(r.statusCode, r.data);
    } catch (e) {
      debugPrint(
        '[IdentityService] claim-signup-bonus failed: ${e.runtimeType}',
      );
      return const SignupBonusResult(
        outcome: IdentityOutcome.retryableFailure,
        errorCode: 'network',
      );
    }
  }

  /// POST /identity/merge-ticket — (A, anonymous) start a merge; returns the raw
  /// ticket ONCE. Caller must hand it to B out-of-band and never persist/log it.
  Future<MergeTicketResult> createMergeTicket() async {
    try {
      final r = await _dio.post('/identity/merge-ticket');
      return MergeTicketResult.from(r.statusCode, r.data);
    } catch (e) {
      debugPrint('[IdentityService] merge-ticket failed: ${e.runtimeType}');
      return const MergeTicketResult(
        outcome: IdentityOutcome.retryableFailure,
        errorCode: 'network',
      );
    }
  }

  /// POST /identity/claim — (B, permanent) claim A's merge ticket. Body {ticket}.
  Future<ClaimResult> claimExistingIdentity(String ticket) async {
    try {
      final r = await _dio.post('/identity/claim', data: {'ticket': ticket});
      return ClaimResult.from(r.statusCode, r.data);
    } catch (e) {
      debugPrint('[IdentityService] claim failed: ${e.runtimeType}');
      return const ClaimResult(
        outcome: IdentityOutcome.retryableFailure,
        errorCode: 'network',
      );
    }
  }

  /// POST /identity/post-signout-guest — mark the FRESH anon (created by the
  /// sign-out flow) as trial-consumed so the backend grants it NO new free tier.
  /// Idempotent server-side (same `trial:<user_id>` key). Returns true on a 2xx,
  /// false otherwise (the caller retries). No token/UUID is ever logged.
  Future<bool> postSignoutGuest() async {
    try {
      final r = await _dio.post('/identity/post-signout-guest');
      final s = r.statusCode ?? 0;
      return s >= 200 && s < 300;
    } catch (e) {
      debugPrint('[IdentityService] post-signout-guest failed: ${e.runtimeType}');
      return false;
    }
  }
}
