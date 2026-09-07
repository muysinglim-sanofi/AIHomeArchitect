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

import 'pwa_generation_service.dart'
    show
        PwaAdvisoryRaised,
        PwaAnswerRaised,
        PwaGenerationAdvisory,
        PwaGenerationProcessing;

/// A failure the UI can act on. Carries the backend's user-facing message when
/// there is one, so the screen never has to invent copy for a real error.
class PwaGenerationApiError implements Exception {
  const PwaGenerationApiError({
    required this.code,
    required this.userMessage,
    required this.retryable,
    this.billingState = '',
    this.paywall = false,
  });

  final String code;
  final String userMessage;
  final bool retryable;

  /// The finer billing semantic behind a `QUOTA_EXHAUSTED`: `FREE_EXHAUSTED`,
  /// `PASS_EXHAUSTED`, `PASS_REQUIRED`. Empty for every other error.
  ///
  /// Carried separately from [code] because the two answer different questions:
  /// `code` says what happened, `billingState` says which paywall to show. The
  /// UI translates both — neither string is ever rendered as-is.
  final String billingState;

  /// True when the backend refused for MONEY reasons. The one signal allowed to
  /// open the paywall, so a network blip can never be mistaken for a sale.
  final bool paywall;

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
    this.confirm = false,
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

  /// Skips the canonical advisor: the user read its objection and chose to
  /// continue. Same field, same meaning, as mobile's POST /refine.
  final bool confirm;

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
    'confirm': confirm,
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
    this.resolvedRoomType = '',
    this.resolvedAtmosphereId = '',
    this.resolvedAtmosphereLabel = '',
    this.lineageCustomized = false,
    this.changes = const [],
  });

  final String visionId;
  final int visionNumber;
  final String imagePath;
  final bool replayed;

  /// What the ENGINE decided, handed back so the browser adopts it instead of
  /// deciding anything itself.
  ///
  /// "Your space" and "Ayden Signature" are the two ways of saying "you
  /// choose"; one gpt-4o look at the photo turns them into a real room and a
  /// real atmosphere, and everything downstream — the advisor, the next refine,
  /// the next switch — has to hear that answer. Mobile returns the same three
  /// facts on every /generate and its client adopts them the same way.
  final String resolvedRoomType;
  final String resolvedAtmosphereId;
  final String resolvedAtmosphereLabel;

  /// Whether THIS branch now counts as customised. Cumulative along the branch,
  /// computed by the backend when the row is written.
  final bool lineageCustomized;

  /// The refine plan that was actually executed, echoed for the stateless
  /// verify second call. Mobile carries the identical echo.
  final List<Map<String, Object?>> changes;

  static PwaGenerationResult parse(Object? body) {
    if (body is! Map) {
      throw const PwaGenerationApiError(
        code: 'MALFORMED_RESPONSE',
        userMessage: 'Something went wrong creating your vision. Try again.',
        retryable: true,
      );
    }
    // The canonical advisor answered instead of rendering. This is checked
    // FIRST: an advisory has no vision_id, and reading it as a malformed
    // result would turn Ayden's objection into an error message.
    // Ayden answered instead of rendering: the line asked something rather
    // than instructing a change. Not a failure, and not a vision.
    if (body['status'] == 'answer') {
      throw PwaAnswerRaised((body['message'] as String?) ?? '');
    }
    if (body['status'] == 'advisory') {
      throw PwaAdvisoryRaised(
        PwaGenerationAdvisory(
          verdict: body['verdict'] as String? ?? 'yellow',
          message: (body['message'] as String? ?? '').trim(),
          flagged: [
            for (final f in (body['flagged'] as List? ?? const []))
              if (f is Map) f.cast<String, Object?>(),
          ],
        ),
      );
    }
    // A durable claim is held elsewhere and the render is still running. Not
    // a result and not an error: the only correct response is to keep waiting.
    if (body['status'] == 'processing') {
      throw PwaGenerationProcessing(body['idempotency_key'] as String? ?? '');
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
      resolvedRoomType: (body['resolved_room_type'] as String?) ?? '',
      resolvedAtmosphereId: (body['resolved_atmosphere_id'] as String?) ?? '',
      resolvedAtmosphereLabel:
          (body['resolved_atmosphere_label'] as String?) ?? '',
      lineageCustomized: body['lineage_customized'] == true,
      changes: [
        for (final c in (body['changes'] as List? ?? const []))
          if (c is Map) c.cast<String, Object?>(),
      ],
    );
  }
}

/// What the canonical conversational turn answered.
///
/// [shouldGenerate] is the ONLY thing in the app permitted to authorise a paid
/// render from a typed line. It is not derived, inferred or second-guessed here:
/// it is the value the same `/chat` brain gives mobile.
class PwaChatTurn {
  const PwaChatTurn({
    required this.aiMessage,
    required this.shouldGenerate,
    this.suggestions = const [],
    this.intent = '',
  });

  /// Nothing was decided — answer with silence and, above all, do NOT generate.
  const PwaChatTurn.silent()
    : aiMessage = '',
      shouldGenerate = false,
      suggestions = const [],
      intent = 'unavailable';

  final String aiMessage;
  final bool shouldGenerate;
  final List<String> suggestions;
  final String intent;

  static PwaChatTurn parse(Map<String, Object?> body) => PwaChatTurn(
    aiMessage: ((body['ai_message'] as String?) ?? '').trim(),
    // `== true` and never a truthy cast: an absent or malformed field must read
    // as "do not spend", not as "spend".
    shouldGenerate: body['should_generate'] == true,
    suggestions: [
      for (final s in (body['suggestions'] as List? ?? const []))
        if (s is String && s.trim().isNotEmpty) s.trim(),
    ],
    intent: (body['intent'] as String?) ?? '',
  );
}

/// Where one logical generation has got to, read from the durable lifecycle.
///
/// PROCESSING is the state that used to be shown as a failure. It means the
/// backend holds the claim and is rendering — started by this tab, an earlier
/// one, or another worker — so the only correct response is to keep waiting.
class PwaGenerationStatus {
  const PwaGenerationStatus({
    required this.state,
    this.result,
    this.errorCode = '',
  });

  /// `COMPLETED` | `PROCESSING` | `FAILED` | `UNKNOWN`.
  ///
  /// UNKNOWN is deliberately distinct from FAILED: it means the backend has no
  /// record either way (nothing was ever claimed, or the durable lifecycle was
  /// unavailable and it failed open). Treating that as a failure would invent
  /// one.
  final String state;

  /// Present only on COMPLETED — the vision the winning caller produced.
  final PwaGenerationResult? result;

  final String errorCode;

  bool get isTerminal => state == 'COMPLETED' || state == 'FAILED';

  static PwaGenerationStatus parse(Object? body) {
    if (body is! Map) return const PwaGenerationStatus(state: 'UNKNOWN');
    final state = (body['state'] as String?) ?? 'UNKNOWN';
    if (state != 'COMPLETED') {
      return PwaGenerationStatus(
        state: state,
        errorCode: (body['error_code'] as String?) ?? '',
      );
    }
    return PwaGenerationStatus(
      state: state,
      result: PwaGenerationResult(
        visionId: (body['vision_id'] as String?) ?? '',
        visionNumber: (body['vision_number'] as num?)?.toInt() ?? 1,
        imagePath: (body['image_path'] as String?) ?? '',
        // It was NOT made by this call — that is exactly what makes it safe to
        // adopt without paying for a second one.
        replayed: true,
        resolvedRoomType: (body['resolved_room_type'] as String?) ?? '',
        resolvedAtmosphereId: (body['resolved_atmosphere_id'] as String?) ?? '',
        resolvedAtmosphereLabel:
            (body['resolved_atmosphere_label'] as String?) ?? '',
        lineageCustomized: body['lineage_customized'] == true,
      ),
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
    /// The path every Web API route hangs under: `/pwa/staging` for the
    /// staging deployment (the default, so nothing existing changes) and
    /// `/pwa` for production. It comes from `PwaEnvironment.apiPrefix`, which
    /// is the mirror of the backend's `pwa_target.py`.
    String apiPrefix = '/pwa/staging',
    Dio? dio,
  }) : _prefix = apiPrefix,
       _tokenProvider = tokenProvider,
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
  final String _prefix;
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
        '$_prefix/generate',
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

  /// Where a generation has got to. A pure READ — no advisor, no parse, no
  /// provider — so it is safe to call every few seconds for as long as a render
  /// takes. Re-POSTing /generate would do the same job and re-run the refine
  /// parser, a real provider call, on every tick.
  ///
  /// Never throws: a poll that fails is "we don't know yet", and the caller's
  /// own deadline decides when to stop. Turning a dropped packet into a failure
  /// is precisely the bug this method exists to end.
  Future<PwaGenerationStatus> status(String idempotencyKey) async {
    if (_disposed) return const PwaGenerationStatus(state: 'UNKNOWN');
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      return const PwaGenerationStatus(state: 'UNKNOWN');
    }
    try {
      final res = await _dio.get<Object?>(
        '$_prefix/generation/${Uri.encodeComponent(idempotencyKey)}',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final code = res.statusCode ?? 0;
      if (code < 200 || code >= 300) {
        return const PwaGenerationStatus(state: 'UNKNOWN');
      }
      return PwaGenerationStatus.parse(res.data);
    } catch (_) {
      return const PwaGenerationStatus(state: 'UNKNOWN');
    }
  }

  /// The conversational turn. Free (no image), and the ONLY thing allowed to
  /// decide that a typed line is worth a render.
  ///
  /// Fails CLOSED: an unreachable backend answers `shouldGenerate == false`, so
  /// a dropped packet costs a sentence rather than a generation.
  Future<PwaChatTurn> chat({
    required String projectId,
    required String message,
    String uiLocale = 'en',
  }) async {
    if (_disposed) return const PwaChatTurn.silent();
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) return const PwaChatTurn.silent();
    try {
      final res = await _dio.post<Object?>(
        '$_prefix/chat',
        data: {
          'project_id': projectId,
          'message': message,
          'ui_locale': uiLocale,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      final code = res.statusCode ?? 0;
      if (code < 200 || code >= 300 || res.data is! Map) {
        return const PwaChatTurn.silent();
      }
      return PwaChatTurn.parse((res.data! as Map).cast<String, Object?>());
    } catch (_) {
      return const PwaChatTurn.silent();
    }
  }

  /// The stateless verify SECOND call — free, and never on the critical path.
  ///
  /// Mobile fires it after the image is already on screen and shows a report
  /// only when the verdict is `incomplete`. Every failure degrades to
  /// `unavailable`, which the UI renders as silence.
  Future<Map<String, Object?>> verifyRefine({
    required String projectId,
    required String beforePath,
    required String afterPath,
    required List<Map<String, Object?>> changes,
  }) async {
    const silent = <String, Object?>{'verification': 'unavailable'};
    if (_disposed || changes.isEmpty) return silent;
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) return silent;
    try {
      final res = await _dio.post<Object?>(
        '$_prefix/refine/verify',
        data: {
          'project_id': projectId,
          'before_path': beforePath,
          'after_path': afterPath,
          'changes': changes,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      final code = res.statusCode ?? 0;
      if (code < 200 || code >= 300 || res.data is! Map) return silent;
      return (res.data! as Map).cast<String, Object?>();
    } catch (_) {
      // The verify never blocks the image already shown (fail-open, honest).
      return silent;
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
    final billing = payload?['billing_state'];
    return PwaGenerationApiError(
      code: code is String && code.isNotEmpty ? code : 'HTTP_$status',
      userMessage: message is String && message.isNotEmpty
          ? message
          : 'Something went wrong creating your vision. Try again.',
      // A 5xx with no explicit verdict is worth retrying; a 4xx is not.
      retryable: retryable is bool ? retryable : status >= 500,
      billingState: billing is String ? billing : '',
      // 402 is the billing seam's own status, and `paywall` is the field the
      // backend sets when it refuses for money. Both are required: no other
      // failure may open a paywall.
      paywall: status == 402 && payload?['paywall'] != null,
    );
  }

  /// What this user may do, according to the BILLING ENGINE. A read.
  ///
  /// The paywall is driven by this and never by a local counter: the browser
  /// does not know what a free generation costs, whether a pass is active, or
  /// what a purchase granted — the ledger does. Returns null when the answer is
  /// unknown (offline, session gone), which the UI renders as "loading", not as
  /// "blocked" and not as "allowed".
  Future<Map<String, Object?>?> entitlement() async {
    if (_disposed) return null;
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) return null;
    try {
      final res = await _dio.get<Object?>(
        '$_prefix/entitlement',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final code = res.statusCode ?? 0;
      if (code < 200 || code >= 300 || res.data is! Map) return null;
      return (res.data! as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  // ── PAYMENTS (KHQR / ABA PayWay) ───────────────────────────────────────────
  //
  // Four reads and two writes, and NONE of them talks to PayWay. The browser
  // holds no merchant id, no api key and no signing material; it asks Ayden,
  // Ayden asks PayWay. That is not a convenience — a credential in a web bundle
  // is a credential published.
  //
  // These methods deliberately return the RAW body, failures included, instead
  // of throwing. A payment surface has to render "the gateway refused", "this
  // expired" and "we could not reach the server" as distinct, translated
  // states; collapsing them into an exception would lose exactly the
  // distinctions the person needs. The backend speaks a machine vocabulary
  // (`error_code`, `payment_state`, `reason`) and the client translates it.

  /// Ask the SERVER to open a payment for [sku]. The only two things the
  /// browser gets to say.
  ///
  /// [attemptKey] is stable for one purchase ATTEMPT: reusing it after a
  /// refresh, a retry or a dropped response converges on the same PayWay
  /// transaction, and a person who taps "try again" gets a new one.
  Future<Map<String, Object?>> startCheckout({
    required String sku,
    required String attemptKey,
  }) => _payment('POST', '$_prefix/payments/checkout',
      body: {'sku': sku, 'attempt_key': attemptKey});

  /// The ACTIVE Web checkout since 2026-09-05: ask the server to open a
  /// payment and hand back the SIGNED fields for ABA's own plugin to post.
  ///
  /// Same two inputs as [startCheckout], same authority. The answer carries a
  /// `plugin` object — a form action and a map of fields — which this client
  /// relays to the plugin bridge without reading a single key of it.
  Future<Map<String, Object?>> startPluginCheckout({
    required String sku,
    required String attemptKey,
  }) => _payment('POST', '$_prefix/payments/checkout/plugin',
      body: {'sku': sku, 'attempt_key': attemptKey});

  /// The server's view of one payment. THE polling endpoint — it re-verifies
  /// with PayWay server-side, so this is how the browser learns it was paid.
  Future<Map<String, Object?>> orderStatus(String tranId) => _payment(
      'GET', '$_prefix/payments/order/${Uri.encodeComponent(tranId)}');

  /// The payment still in progress for this person, if any. Asked at boot: an
  /// F5 or a second tab restores the sheet from the SERVER, so nothing about a
  /// payment is ever kept in browser storage.
  Future<Map<String, Object?>> openOrder() =>
      _payment('GET', '$_prefix/payments/open');

  /// The person closed the sheet. Cancels the ATTEMPT — the server verifies
  /// first, so money that arrived a moment ago still wins.
  Future<Map<String, Object?>> cancelOrder(String tranId) => _payment(
      'POST',
      '$_prefix/payments/order/${Uri.encodeComponent(tranId)}/cancel');

  Future<Map<String, Object?>> _payment(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (_disposed) {
      return const {'ok': false, 'error_code': 'CANCELLED', 'retryable': true};
    }
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      return const {'ok': false, 'error_code': 'MISSING_TOKEN', 'retryable': false};
    }
    final options = Options(
      headers: {'Authorization': 'Bearer $token'},
      receiveTimeout: const Duration(seconds: 30),
    );
    try {
      final res = method == 'GET'
          ? await _dio.get<Object?>(path, options: options)
          : await _dio.post<Object?>(path, data: body ?? const {}, options: options);
      final code = res.statusCode ?? 0;
      final data = res.data;
      final map = data is Map
          ? data.cast<String, Object?>()
          : <String, Object?>{};
      if (code >= 200 && code < 300) return {'ok': true, ...map};
      // FastAPI wraps a raised HTTPException detail; unwrap it so the caller
      // sees the same shape whether the backend raised or returned.
      final detail = map['detail'];
      return {
        'ok': false,
        'http_status': code,
        ...(detail is Map ? detail.cast<String, Object?>() : map),
      };
    } catch (_) {
      // Unreachable is NOT refused. A payment in flight must survive a dropped
      // packet, and the next poll asks again.
      return const {'ok': false, 'error_code': 'UNREACHABLE', 'retryable': true};
    }
  }
}
