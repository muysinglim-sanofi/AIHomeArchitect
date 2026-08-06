/// The PWA's typed client for the staging generation backend.
///
/// One place that knows how to talk HTTP to the canonical engine. Widgets never
/// reach it — they call the controller, the controller calls a repository, the
/// repository calls this, and the BACKEND generates. Nothing here composes a
/// prompt or names a provider: the client transports structured intent
/// (project, room, atmosphere, instruction) and nothing else.
///
/// Secrets: this client holds a URL and forwards the user's own session token.
/// It never logs that token, and there is no provider key anywhere in the
/// browser — that is the entire reason generation is a server round-trip.
library;

import 'dart:async';

import 'package:dio/dio.dart';

/// A failure the UI can act on. Carries the backend's user-facing message when
/// there is one, so the screen never has to invent copy for a real error.
class PwaGenerationApiError implements Exception {
  const PwaGenerationApiError({
    required this.code,
    required this.userMessage,
    required this.retryable,
  });

  final String code;
  final String userMessage;
  final bool retryable;

  @override
  String toString() => 'PwaGenerationApiError($code, retryable: $retryable)';
}

/// What the client asks the backend to make. Structured facts only.
class PwaGenerationRequest {
  const PwaGenerationRequest({
    required this.projectId,
    required this.roomId,
    required this.roomLabel,
    required this.atmosphereId,
    required this.atmosphereLabel,
    required this.originalImagePath,
    required this.idempotencyKey,
    this.actionType = 'initial',
    this.parentVisionId = '',
    this.userInstruction = '',
    this.visionNumber = 1,
    this.uiLocale = 'en',
  });

  final String projectId;
  final String roomId;
  final String roomLabel;
  final String atmosphereId;
  final String atmosphereLabel;
  final String originalImagePath;

  /// Stable across every retry of the SAME logical generation, and different for
  /// a deliberate new one. The backend keys its replay on this, and the staging
  /// database enforces it with `unique (owner_user_id, idempotency_key)` — so a
  /// double-click cannot produce two images even if both requests arrive.
  final String idempotencyKey;

  final String actionType;
  final String parentVisionId;
  final String userInstruction;
  final int visionNumber;
  final String uiLocale;

  Map<String, dynamic> toJson() => {
    'project_id': projectId,
    'room_id': roomId,
    'room_label': roomLabel,
    'atmosphere_id': atmosphereId,
    'atmosphere_label': atmosphereLabel,
    'original_image_path': originalImagePath,
    'idempotency_key': idempotencyKey,
    'action_type': actionType,
    'parent_vision_id': parentVisionId,
    'user_instruction': userInstruction,
    'vision_number': visionNumber,
    'ui_locale': uiLocale,
  };
}

/// A completed generation. [replayed] is true when the backend recognised the
/// idempotency key and returned the existing vision instead of making a new one.
class PwaGenerationResult {
  const PwaGenerationResult({
    required this.visionId,
    required this.visionNumber,
    required this.imagePath,
    required this.replayed,
  });

  final String visionId;
  final int visionNumber;
  final String imagePath;
  final bool replayed;

  static PwaGenerationResult parse(Object? body) {
    if (body is! Map) {
      throw const PwaGenerationApiError(
        code: 'MALFORMED_RESPONSE',
        userMessage: 'Something went wrong creating your vision. Try again.',
        retryable: true,
      );
    }
    final id = body['vision_id'];
    final path = body['image_path'];
    if (id is! String || id.isEmpty || path is! String || path.isEmpty) {
      throw const PwaGenerationApiError(
        code: 'MALFORMED_RESPONSE',
        userMessage: 'Something went wrong creating your vision. Try again.',
        retryable: true,
      );
    }
    return PwaGenerationResult(
      visionId: id,
      visionNumber: (body['vision_number'] as num?)?.toInt() ?? 1,
      imagePath: path,
      replayed: body['replayed'] == true,
    );
  }
}

/// Supplies the current session token. Async because a session can be renewed
/// between two generations, and a stale token is an error the user shouldn't see.
typedef PwaTokenProvider = Future<String?> Function();

/// A real render measured 115-125 s against the live engine. The client must
/// outlast it by a wide margin: giving up early invents a failure for a
/// generation that is about to land, and the user has already paid for it.
const Duration kPwaGenerateReceiveTimeout = Duration(minutes: 6);

class PwaGenerationApi {
  PwaGenerationApi({
    required String baseUrl,
    required PwaTokenProvider tokenProvider,
    Dio? dio,
  }) : _tokenProvider = tokenProvider,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: kPwaGenerateReceiveTimeout,
               sendTimeout: const Duration(minutes: 2),
               // Non-2xx is handled below as data, not as a thrown surprise.
               validateStatus: (_) => true,
               responseType: ResponseType.json,
             ),
           );

  final Dio _dio;
  final PwaTokenProvider _tokenProvider;
  final _inFlight = <CancelToken>[];
  bool _disposed = false;

  /// Cancels everything still in flight. Called when the owning object goes
  /// away, so a completed request can never write into a dead controller.
  void dispose() {
    _disposed = true;
    for (final t in _inFlight) {
      if (!t.isCancelled) t.cancel('disposed');
    }
    _inFlight.clear();
  }

  Future<PwaGenerationResult> generate(PwaGenerationRequest request) async {
    if (_disposed) {
      throw const PwaGenerationApiError(
        code: 'CANCELLED',
        userMessage: 'That request was cancelled.',
        retryable: true,
      );
    }
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const PwaGenerationApiError(
        code: 'SESSION_EXPIRED',
        userMessage: 'Your session expired. Reload the page to continue.',
        retryable: false,
      );
    }

    final cancel = CancelToken();
    _inFlight.add(cancel);
    try {
      final res = await _dio.post<Object?>(
        '/pwa/staging/generate',
        data: request.toJson(),
        cancelToken: cancel,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final status = res.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        return PwaGenerationResult.parse(res.data);
      }
      throw _errorFrom(status, res.data);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw const PwaGenerationApiError(
          code: 'CANCELLED',
          userMessage: 'That request was cancelled.',
          retryable: true,
        );
      }
      // Deliberately does not echo `e.message`: it can contain the request
      // headers, and those carry the session token.
      throw switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.connectionError => const PwaGenerationApiError(
          code: 'BACKEND_UNREACHABLE',
          userMessage:
              "Can't reach Ayden right now. Check your connection and try again.",
          retryable: true,
        ),
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => const PwaGenerationApiError(
          code: 'TIMEOUT',
          userMessage: 'This is taking longer than expected. Try again.',
          retryable: true,
        ),
        _ => const PwaGenerationApiError(
          code: 'NETWORK_ERROR',
          userMessage: 'Something went wrong. Try again.',
          retryable: true,
        ),
      };
    } finally {
      _inFlight.remove(cancel);
    }
  }

  /// Backend errors arrive either flat or nested under `detail` (FastAPI's
  /// HTTPException shape). Both are normalised to one payload.
  PwaGenerationApiError _errorFrom(int status, Object? body) {
    Map<Object?, Object?>? payload;
    if (body is Map) {
      payload = body['detail'] is Map
          ? (body['detail'] as Map).cast<Object?, Object?>()
          : body.cast<Object?, Object?>();
    }
    final code = payload?['error_code'];
    final message = payload?['user_message'];
    final retryable = payload?['retryable'];
    return PwaGenerationApiError(
      code: code is String && code.isNotEmpty ? code : 'HTTP_$status',
      userMessage: message is String && message.isNotEmpty
          ? message
          : 'Something went wrong creating your vision. Try again.',
      // A 5xx with no explicit verdict is worth retrying; a 4xx is not.
      retryable: retryable is bool ? retryable : status >= 500,
    );
  }
}
