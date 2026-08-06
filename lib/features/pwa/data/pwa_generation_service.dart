/// The single seam between the PWA and a real generation.
///
/// There is exactly ONE implementation in the staging runtime — the one that
/// calls the canonical engine. The fake exists for tests and for the explicitly
/// isolated mock environment; it can never be reached by accident, because the
/// staging boot injects the real service and nothing falls back.
///
/// The rule this file exists to enforce: **a failed generation is a failure**.
/// No fixture is ever substituted for a render the engine did not produce, and
/// no bundled atmosphere asset is ever promoted to "your vision".
library;

import 'pwa_generation_api.dart';

/// What a generation produced: a Storage PATH, never a signed URL.
///
/// The path is the durable source of truth; a signed URL is minted from it at
/// render time and allowed to expire. Persisting the URL instead would give
/// every project a silent expiry date.
class PwaGeneratedVision {
  const PwaGeneratedVision({
    required this.imagePath,
    required this.visionNumber,
    required this.replayed,
    this.backendVisionId,
  });

  final String imagePath;
  final int visionNumber;

  /// True when the backend recognised the idempotency key and returned the
  /// existing vision rather than generating (and charging for) a second one.
  final bool replayed;

  /// The id the backend persisted. Kept so a resumed session can be reconciled
  /// against the server's row rather than guessed at.
  final String? backendVisionId;
}

/// A generation failure the UI can present and act on.
class PwaGenerationFailure implements Exception {
  const PwaGenerationFailure({
    required this.code,
    required this.userMessage,
    required this.retryable,
  });

  final String code;
  final String userMessage;
  final bool retryable;

  @override
  String toString() => 'PwaGenerationFailure($code, retryable: $retryable)';
}

/// What the app asks for. Structured intent only — the engine owns the prompt.
class PwaGenerationIntent {
  const PwaGenerationIntent({
    required this.projectId,
    required this.roomId,
    required this.roomLabel,
    required this.atmosphereId,
    required this.atmosphereLabel,
    required this.originalImagePath,
    required this.idempotencyKey,
    required this.visionNumber,
    this.actionType = 'initial',
    this.parentVisionId = '',
    this.userInstruction = '',
  });

  final String projectId;
  final String roomId;
  final String roomLabel;
  final String atmosphereId;
  final String atmosphereLabel;
  final String originalImagePath;
  final String idempotencyKey;
  final int visionNumber;
  final String actionType;
  final String parentVisionId;
  final String userInstruction;
}

abstract class PwaGenerationService {
  /// Runs one generation to completion. Throws [PwaGenerationFailure] on any
  /// failure — it never returns a placeholder result.
  Future<PwaGeneratedVision> generate(PwaGenerationIntent intent);

  void dispose();
}

/// The staging runtime implementation: a thin translation onto the typed API
/// client, which talks to the canonical engine.
class PwaStagingGenerationService implements PwaGenerationService {
  PwaStagingGenerationService(this._api);

  final PwaGenerationApi _api;

  @override
  Future<PwaGeneratedVision> generate(PwaGenerationIntent intent) async {
    try {
      final r = await _api.generate(
        PwaGenerationRequest(
          projectId: intent.projectId,
          roomId: intent.roomId,
          roomLabel: intent.roomLabel,
          atmosphereId: intent.atmosphereId,
          atmosphereLabel: intent.atmosphereLabel,
          originalImagePath: intent.originalImagePath,
          idempotencyKey: intent.idempotencyKey,
          actionType: intent.actionType,
          parentVisionId: intent.parentVisionId,
          userInstruction: intent.userInstruction,
          visionNumber: intent.visionNumber,
        ),
      );
      return PwaGeneratedVision(
        imagePath: r.imagePath,
        visionNumber: r.visionNumber,
        replayed: r.replayed,
        backendVisionId: r.visionId,
      );
    } on PwaGenerationApiError catch (e) {
      // Mapped, not swallowed: the UI shows a real error and offers Retry.
      throw PwaGenerationFailure(
        code: e.code,
        userMessage: e.userMessage,
        retryable: e.retryable,
      );
    }
  }

  @override
  void dispose() => _api.dispose();
}

/// Deterministic fake — TESTS AND THE ISOLATED MOCK ENVIRONMENT ONLY.
///
/// Deliberately returns a path under the same `users/.../generated/` convention
/// rather than a bundle asset, so a test can tell a fake render from a fixture
/// and the "no fixture as a result" assertions stay meaningful.
class PwaFakeGenerationService implements PwaGenerationService {
  PwaFakeGenerationService({this.failure, this.delay = Duration.zero});

  /// When set, every call fails with it — how error paths are exercised.
  /// Mutable so a test can succeed first and then fail, which is the sequence
  /// that matters: a failure AFTER a real vision must not disturb it.
  PwaGenerationFailure? failure;
  final Duration delay;

  final List<PwaGenerationIntent> calls = <PwaGenerationIntent>[];
  final Map<String, PwaGeneratedVision> _byIdempotencyKey = {};

  @override
  Future<PwaGeneratedVision> generate(PwaGenerationIntent intent) async {
    calls.add(intent);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final f = failure;
    if (f != null) throw f;
    // Mirrors the backend's contract: the same key never generates twice.
    final prior = _byIdempotencyKey[intent.idempotencyKey];
    if (prior != null) {
      return PwaGeneratedVision(
        imagePath: prior.imagePath,
        visionNumber: prior.visionNumber,
        replayed: true,
        backendVisionId: prior.backendVisionId,
      );
    }
    final id = 'fake-${_byIdempotencyKey.length + 1}';
    final made = PwaGeneratedVision(
      imagePath:
          'users/fake-uid/projects/${intent.projectId}/generated/$id.jpg',
      visionNumber: intent.visionNumber,
      replayed: false,
      backendVisionId: id,
    );
    _byIdempotencyKey[intent.idempotencyKey] = made;
    return made;
  }

  /// How many DISTINCT generations actually happened (replays excluded). The
  /// number a double-click test asserts on.
  int get generatedCount => _byIdempotencyKey.length;

  @override
  void dispose() {}
}
