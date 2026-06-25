import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../core/feature_flags.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Structured error returned by the /generate endpoint.
class GenerationException implements Exception {
  final String errorCode;
  final String userMessage;
  final bool retryable;
  final String requestId;
  /// Wave 5.6b — true when the backend has already persisted this failure
  /// message to the Supabase messages table. The caller should SKIP its
  /// own insertMessage in that case to avoid duplicates. Defaults to false
  /// so older backends without the flag fall through to client-side write.
  final bool messagePersisted;

  /// Wave 5.17b — true iff the backend returned HTTP 402 QUOTA_EXHAUSTED.
  /// Callers (chat_screen) should branch on this : open the paywall sheet
  /// instead of showing a generic error toast.
  final bool quotaExhausted;
  final int? quotaUsed;
  final int? quotaLimit;

  /// Wave 5.17d — true iff the backend returned HTTP 402 FREE_TIER_RESTRICTED.
  /// Distinct from quotaExhausted (which means "you used all your free gens") :
  /// the user picked an out-of-scope room/atmosphere or delegated the choice
  /// (let_ai_decide / surprise_me) without being premium. Same paywall sheet,
  /// different subhead copy.
  final bool freeTierRestricted;
  /// One of 'room', 'atmosphere', 'delegated_choice', or '' when not set.
  /// Drives the paywall subhead copy in chat_screen.
  final String restrictedField;

  const GenerationException({
    required this.errorCode,
    required this.userMessage,
    required this.retryable,
    this.requestId = '',
    this.messagePersisted = false,
    this.quotaExhausted = false,
    this.quotaUsed,
    this.quotaLimit,
    this.freeTierRestricted = false,
    this.restrictedField = '',
  });

  @override
  String toString() => 'GenerationException($errorCode): $userMessage';
}

class GenerationService {
  late final Dio _dio;

  GenerationService() {
    _dio = Dio(BaseOptions(
      baseUrl: dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000',
      connectTimeout: const Duration(seconds: 180),
      // #4 — raise the RESPONSE wait above the backend worst case. The backend
      // can legitimately run up to max_attempts × 180s (prod=3 → ~540s); a 180s
      // client timeout fired WHILE the backend was still working, surfacing an
      // error/retry that produced a DUPLICATE generation. 600s lets the slow-but-
      // valid generation land instead of racing it. (genLifecycleV2 rollback.)
      receiveTimeout: Duration(seconds: FeatureFlags.genLifecycleV2 ? 600 : 180),
      sendTimeout: const Duration(seconds: 180),
    ));

    // Wave 5.17a — JWT propagation. Inject the active Supabase access
    // token (anonymous OR signed-in) on every backend request. The
    // backend's `get_current_user` dependency verifies the JWT signature
    // and extracts `user_id` (sub claim) for session-ownership checks
    // before the OpenAI call. Without this header, the backend returns
    // 401 on /chat and /generate.
    //
    // The token is read at request-time (not interceptor-construction
    // time) so a freshly-upgraded session — e.g. immediately after the
    // Gen #2 sign-in — carries the NEW user's JWT, not the stale
    // anonymous one.
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = Supabase.instance.client.auth.currentSession?.accessToken;
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  /// Calls FastAPI /chat for intent classification and architect response.
  /// Returns { ai_message, suggestions, should_generate, intent, sub_intent }.
  Future<Map<String, dynamic>> chat({
    required String sessionId,
    required String message,
    required String styleLabel,
    String roomType = '',
    int iteration = 1,
    String history = '',
    String secondarySpaces = '[]',
    String uiLocale = 'en', // Phase 1 — authoritative reply language
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/chat',
      data: FormData.fromMap({
        'session_id': sessionId,
        'message': message,
        'style_label': styleLabel,
        'room_type': roomType,
        'iteration': iteration.toString(),
        'history': history,
        'secondary_spaces': secondarySpaces,
        'ui_locale': uiLocale,
      }),
    );
    return res.data!;
  }

  /// Calls FastAPI /generate and returns the result map:
  /// { after_image_url, thumbnail_url, ai_message, suggestions, request_id }
  ///
  /// [originalImageUrl]: the V1 uploaded source image URL. When provided on
  /// V2+ calls, the backend uses it as the structural anchor for images.edit,
  /// preserving original geometry across all iterations instead of drifting
  /// through increasingly AI-interpreted sources.
  ///
  /// [clientRequestId]: idempotency key generated by the caller. Logged by
  /// the backend and returned in success/error responses for reconciliation.
  ///
  /// Throws [GenerationException] when the backend returns a structured error.
  /// [letAiDecide]: Wave 4.8.5 — sends the real `let_ai_decide` semantic flag
  /// so the backend infers the primary room type from the image
  /// (`classify_room`) instead of trusting an explicit/empty `roomType`.
  /// [surpriseMe]: sends the real `surprise_me_flag` so the backend selects
  /// the best-fitting atmosphere (`surprise_me`) and overrides `style_label`
  /// internally. Neither is ever a fake "AI Decide"/"Surprise Me" string —
  /// the free-text architectural direction flows through [prompt] (→ the
  /// composer's existing design-direction / refinement path).
  Future<Map<String, dynamic>> generate({
    required String sessionId,
    required String prompt,
    required String beforeImageUrl,
    required String styleLabel,
    String roomType = '',
    // Wave 5.17d — canonical (locale-stable) ids for the backend free-tier
    // scope check. Default empty for callers that don't provide them ; the
    // backend then treats the request as out-of-scope and returns 402
    // unless the user is premium.
    String roomTypeId = '',
    String atmosphereId = '',
    int iteration = 1,
    String history = '',
    String originalImageUrl = '',
    String clientRequestId = '',
    bool letAiDecide = false,
    bool surpriseMe = false,
    String structuralIdentity = '',
    String versions = '',
    String generationMode = 'preserve', // Wave 5.5.14c — bimodal intent
    String sourceMode = '',        // BUG A fix — '' | ORIGINAL | LATEST | SPECIFIC_VERSION
    String sourceVersionId = '',   // BUG A fix — target version_id when sourceMode=SPECIFIC_VERSION
    String uiLocale = 'en',        // Phase 1 — authoritative reply language (NOT the generation prompt)
    String generationTrigger = 'unknown', // P0 dup-fix — trigger source for [RETRY-PROOF] (auto|button|switch|chat|resume)
    int generationAttempt = 0,     // P0 dup-fix — bumped only on intentional regenerate → backend content-key carve-out
  }) async {
    // Wave 5.13c perf diag — measure client-side click→response latency.
    // Pairs with the backend `[PERF SUMMARY] request_id=...` line via
    // clientRequestId, and with the frontend `[Wave 5.12d] image card
    // loaded in Xms` log (post-response image decode). Together they
    // give the full click→pixel timeline.
    final sw = Stopwatch()..start();
    debugPrint(
      '[PerfGen] click→POST /generate  request_id=$clientRequestId  '
      'iteration=$iteration  style=$styleLabel  mode=$generationMode',
    );
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/generate',
        data: FormData.fromMap({
          'session_id': sessionId,
          'prompt': prompt,
          'before_image_url': beforeImageUrl,
          'style_label': styleLabel,
          'room_type': roomType,
          // Wave 5.17d — canonical ids drive the free-tier scope check.
          'room_type_id': roomTypeId,
          'atmosphere_id': atmosphereId,
          'iteration': iteration.toString(),
          'history': history,
          'original_image_url': originalImageUrl,
          'client_request_id': clientRequestId,
          'let_ai_decide': letAiDecide.toString(),
          'surprise_me_flag': surpriseMe.toString(),
          'structural_identity': structuralIdentity,
          'versions': versions,
          'generation_mode': generationMode,
          // BUG A fix — let "Continue this vision" actually rebranch the backend
          // source (resolve_source ignores before_image_url; it needs source_mode
          // + source_version_id). Empty => backend keeps its V2+ LATEST default.
          'source_mode': sourceMode,
          'source_version_id': sourceVersionId,
          'ui_locale': uiLocale,
          'generation_trigger': generationTrigger,
          'generation_attempt': generationAttempt.toString(),
        }),
      );
      sw.stop();
      debugPrint(
        '[PerfGen] response OK in ${sw.elapsedMilliseconds}ms  '
        'request_id=$clientRequestId',
      );
      return res.data!;
    } on DioException catch (e) {
      sw.stop();
      debugPrint(
        '[PerfGen] response ERROR in ${sw.elapsedMilliseconds}ms  '
        'request_id=$clientRequestId  type=${e.type.name}  '
        'status=${e.response?.statusCode}',
      );
      final data = e.response?.data;
      if (data is Map) {
        // Two response shapes co-exist :
        //   1. Legacy `GenerationError` handler — flat keys at top level
        //      ({ error_code, user_message, retryable, request_id, ... }).
        //   2. FastAPI HTTPException (Wave 5.17a 403, Wave 5.17b 402) —
        //      keys nested under `detail`
        //      ({ detail: { error_code, user_message, ... } }).
        // Normalise to a single payload map.
        final Map payload = (data['detail'] is Map)
            ? data['detail'] as Map
            : data;
        final errorCode = (payload['error_code'] as String?) ?? 'UNKNOWN';
        final userMessage = (payload['user_message'] as String?) ?? 'Generation failed.';
        final retryable = (payload['retryable'] as bool?) ?? true;
        final requestId = (payload['request_id'] as String?) ?? '';
        final messagePersisted = (payload['message_persisted'] as bool?) ?? false;
        // Wave 5.17b — quota exhaustion flag (used all N free gens).
        final quotaExhausted = errorCode == 'QUOTA_EXHAUSTED';
        // Wave 5.17d — free-tier scope rejection (out-of-scope room /
        // atmosphere / delegated choice). Both error codes map to a 402,
        // both open the same paywall sheet ; the subhead differs.
        final freeTierRestricted = errorCode == 'FREE_TIER_RESTRICTED';
        final quotaUsed = (payload['quota_used'] as int?);
        final quotaLimit = (payload['quota_limit'] as int?);
        final restrictedField =
            (payload['restricted_field'] as String?) ?? '';
        throw GenerationException(
          errorCode: errorCode,
          userMessage: userMessage,
          retryable: retryable,
          requestId: requestId,
          messagePersisted: messagePersisted,
          quotaExhausted: quotaExhausted,
          quotaUsed: quotaUsed,
          quotaLimit: quotaLimit,
          freeTierRestricted: freeTierRestricted,
          restrictedField: restrictedField,
        );
      }
      rethrow;
    }
  }
}
