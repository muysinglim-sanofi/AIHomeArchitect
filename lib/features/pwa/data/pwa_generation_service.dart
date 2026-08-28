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

// The conversational verdict is part of THIS seam's contract — every caller of
// the service needs the type, and none of them should have to reach past it into
// the HTTP client to get it.
export 'pwa_generation_api.dart' show PwaChatTurn;

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
    this.resolvedRoomType = '',
    this.resolvedAtmosphereId = '',
    this.resolvedAtmosphereLabel = '',
    this.lineageCustomized = false,
    this.changes = const [],
  });

  final String imagePath;
  final int visionNumber;

  /// True when the backend recognised the idempotency key and returned the
  /// existing vision rather than generating (and charging for) a second one.
  final bool replayed;

  /// The id the backend persisted. Kept so a resumed session can be reconciled
  /// against the server's row rather than guessed at.
  final String? backendVisionId;

  /// What the ENGINE resolved. A delegated room and "Ayden Signature" are
  /// answered once, by one look at the photo, and the app adopts that answer
  /// rather than continuing to describe the space as "Your space".
  final String resolvedRoomType;
  final String resolvedAtmosphereId;
  final String resolvedAtmosphereLabel;

  /// Whether this branch now carries real user customisations.
  final bool lineageCustomized;

  /// The executed refine plan, carried for the stateless verify second call.
  final List<Map<String, Object?>> changes;
}

/// The canonical advisor answered INSTEAD of generating.
///
/// Not a failure and not a result: Ayden objecting, decided by the same
/// `refine.advisor` mobile uses. Nothing was rendered, nothing was charged, and
/// the user chooses to rephrase or continue anyway.
///
/// It is a distinct type so the two outcomes cannot be confused. Before it, the
/// PWA decided locally whether to ask a question — and asked one while a
/// generation was already running underneath.
class PwaGenerationAdvisory {
  const PwaGenerationAdvisory({
    required this.verdict,
    required this.message,
    this.flagged = const [],
  });

  /// `yellow` (ambiguous — "try anyway?") or `red` (advised against).
  final String verdict;

  /// Ayden's words, built by the canonical advisor. Never composed here.
  final String message;

  /// The individual changes that were flagged.
  final List<Map<String, Object?>> flagged;
}

/// Raised when the backend answered with an advisory. Carried as an exception
/// so a caller that only knows how to await a vision cannot silently mistake an
/// objection for a result.
/// Ayden replied in words. The line was a question, so nothing was rendered
/// and nothing was billed — the conversation simply continues.
class PwaAnswerRaised implements Exception {
  const PwaAnswerRaised(this.message);

  final String message;

  @override
  String toString() => 'PwaAnswerRaised';
}

class PwaAdvisoryRaised implements Exception {
  const PwaAdvisoryRaised(this.advisory);
  final PwaGenerationAdvisory advisory;

  @override
  String toString() => 'PwaAdvisoryRaised(${advisory.verdict})';
}

/// The backend holds a durable claim for this operation and is still rendering
/// it — started by this tab, an earlier tab, or another worker.
///
/// It is NOT a failure: nothing is wrong, and starting a second render would
/// pay twice for one request. The caller keeps waiting.
class PwaGenerationProcessing implements Exception {
  const PwaGenerationProcessing(this.idempotencyKey);
  final String idempotencyKey;

  @override
  String toString() => 'PwaGenerationProcessing($idempotencyKey)';
}

/// A generation failure the UI can present and act on.
class PwaGenerationFailure implements Exception {
  const PwaGenerationFailure({
    required this.code,
    required this.userMessage,
    required this.retryable,
    this.billingState = '',
    this.paywall = false,
  });

  final String code;
  final String userMessage;
  final bool retryable;

  /// `FREE_EXHAUSTED` | `PASS_EXHAUSTED` | `PASS_REQUIRED` when the backend
  /// refused for MONEY, and empty otherwise. Carried all the way to the UI so
  /// the paywall opens on the state the Billing Engine named — never on a guess
  /// the client made from a counter it kept itself.
  final String billingState;

  /// The backend answered on its OWN billing seam: a 402 carrying `paywall`.
  /// Narrower than [isBillingRefusal], which also accepts a bare
  /// `QUOTA_EXHAUSTED` code from anywhere.
  final bool paywall;

  /// Whether this failure is the one thing allowed to open a paywall. A timeout
  /// or an unreachable backend must never look like a sale.
  bool get isBillingRefusal =>
      code == 'QUOTA_EXHAUSTED' || billingState.isNotEmpty;

  /// The refusal is AUTHORITATIVE: the Billing Engine refused, said so on its
  /// own 402 seam, and stated the attempt is not retryable. Its payload also
  /// carries `render_started: false` — nothing was made, so there is nothing to
  /// recover and no charge to protect.
  ///
  /// This is the ONLY condition under which a recorded generation may be
  /// discarded rather than kept for retry. A timeout, a 5xx, an unparseable
  /// body or a cancelled request are all `retryable` or carry no `paywall`, and
  /// every one of them keeps its record: the person may already have paid for
  /// work the backend is still holding.
  bool get isAuthoritativeBillingRefusal =>
      paywall && isBillingRefusal && !retryable;

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
    this.confirm = false,
    this.uiLocale = 'en',
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

  /// The user has read the advisor's objection and asked to proceed anyway.
  /// Mirrors mobile's `confirm` on POST /refine.
  final bool confirm;

  /// The language Ayden should ANSWER in — 'en' | 'fr' | 'km'.
  ///
  /// It reaches the canonical `localize_reply` and decides the wording of the
  /// advisor's reply, exactly as mobile's own `ui_locale` does. It never
  /// reaches the image prompt: that is composed server-side, in English, from
  /// structured facts, by the frozen composer. A locale can change what Ayden
  /// SAYS; it can never change what Ayden DRAWS.
  final String uiLocale;
}

abstract class PwaGenerationService {
  /// Runs one generation to completion. Throws [PwaGenerationFailure] on any
  /// failure — it never returns a placeholder result.
  Future<PwaGeneratedVision> generate(PwaGenerationIntent intent);

  /// Ask the canonical conversational brain what this line is.
  ///
  /// This is the gate in front of every typed message and every chip. Nothing in
  /// the app may decide that a sentence deserves a paid render — only the answer
  /// returned here. Never throws: an unreachable backend answers
  /// `shouldGenerate == false`.
  Future<PwaChatTurn> chat({
    required String projectId,
    required String message,
    String uiLocale = 'en',
  });

  /// Where a generation this app already started has got to. Free, read-only,
  /// and never throwing: an unreachable backend answers `UNKNOWN`, which means
  /// "ask again", not "it failed".
  Future<PwaGenerationLifecycle> status(String idempotencyKey);

  /// The verify SECOND call. Free, non-blocking, and silent unless the verdict
  /// is `incomplete`. Returns `null` when there is nothing to say.
  Future<PwaRefineVerification?> verify({
    required String projectId,
    required String beforePath,
    required String afterPath,
    required List<Map<String, Object?>> changes,
  });

  void dispose();
}

/// The durable lifecycle's answer about one logical generation.
class PwaGenerationLifecycle {
  const PwaGenerationLifecycle({
    required this.state,
    this.vision,
    this.errorCode = '',
  });

  /// `COMPLETED` | `PROCESSING` | `FAILED` | `UNKNOWN`.
  final String state;

  /// The winner's result — present only on COMPLETED.
  final PwaGeneratedVision? vision;

  final String errorCode;
}

/// What the free second look concluded. Only ever surfaced when [incomplete].
class PwaRefineVerification {
  const PwaRefineVerification({
    required this.report,
    required this.missing,
  });

  final String report;

  /// The instructions that did NOT land, for a targeted retry.
  final List<String> missing;
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
          confirm: intent.confirm,
          uiLocale: intent.uiLocale,
        ),
      );
      return _vision(r);
    } on PwaGenerationApiError catch (e) {
      // Mapped, not swallowed: the UI shows a real error and offers Retry.
      throw PwaGenerationFailure(
        code: e.code,
        userMessage: e.userMessage,
        retryable: e.retryable,
        billingState: e.billingState,
        // Carried, not dropped: it is the difference between "the Billing
        // Engine refused" and "something said QUOTA_EXHAUSTED".
        paywall: e.paywall,
      );
    }
  }

  static PwaGeneratedVision _vision(PwaGenerationResult r) => PwaGeneratedVision(
    imagePath: r.imagePath,
    visionNumber: r.visionNumber,
    replayed: r.replayed,
    backendVisionId: r.visionId,
    resolvedRoomType: r.resolvedRoomType,
    resolvedAtmosphereId: r.resolvedAtmosphereId,
    resolvedAtmosphereLabel: r.resolvedAtmosphereLabel,
    lineageCustomized: r.lineageCustomized,
    changes: r.changes,
  );

  @override
  Future<PwaChatTurn> chat({
    required String projectId,
    required String message,
    String uiLocale = 'en',
  }) => _api.chat(projectId: projectId, message: message, uiLocale: uiLocale);

  @override
  Future<PwaGenerationLifecycle> status(String idempotencyKey) async {
    final s = await _api.status(idempotencyKey);
    final r = s.result;
    return PwaGenerationLifecycle(
      state: s.state,
      vision: r == null || r.imagePath.isEmpty ? null : _vision(r),
      errorCode: s.errorCode,
    );
  }

  @override
  Future<PwaRefineVerification?> verify({
    required String projectId,
    required String beforePath,
    required String afterPath,
    required List<Map<String, Object?>> changes,
  }) async {
    final res = await _api.verifyRefine(
      projectId: projectId,
      beforePath: beforePath,
      afterPath: afterPath,
      changes: changes,
    );
    // SILENCE except `incomplete` — mobile's rule, verbatim. It is the only
    // verdict where what is missing is actually known, so the only one where a
    // report and a targeted retry are legitimate. `verified` shows the image
    // alone; `unavailable` shows nothing at all.
    if (res['verification'] != 'incomplete') return null;
    final report = ((res['report'] as String?) ?? '').trim();
    if (report.isEmpty) return null;
    final seen = <String>{};
    final missing = <String>[];
    for (final m in (res['missing'] as List? ?? const [])) {
      if (m is! Map) continue;
      final raw = ((m['raw'] as String?)?.trim().isNotEmpty ?? false)
          ? (m['raw'] as String).trim()
          : ((m['normalized'] as String?)?.trim() ?? '');
      if (raw.isNotEmpty && seen.add(raw)) missing.add(raw);
    }
    return PwaRefineVerification(report: report, missing: missing);
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
  Duration delay;

  /// When set, the NEXT non-confirmed call answers with this advisory instead
  /// of rendering — the canonical advisor's behaviour, faked at the seam.
  PwaGenerationAdvisory? advisory;

  /// What the engine "resolved". Lets a test prove the app ADOPTS the backend's
  /// answer rather than keeping its own placeholder.
  String resolvedRoomType = '';
  String resolvedAtmosphereId = '';
  String resolvedAtmosphereLabel = '';

  /// Scripted lifecycle answers, consumed one per [status] call. When it runs
  /// out, the recorded generation (if any) is reported COMPLETED — which is
  /// what really happens once the winner's row lands.
  final List<PwaGenerationLifecycle> lifecycle = <PwaGenerationLifecycle>[];
  int statusCalls = 0;

  /// The verify verdict to hand back, or null for silence (the common case).
  PwaRefineVerification? verification;
  int verifyCalls = 0;

  /// What the canonical conversational turn answers.
  ///
  /// Defaults to "generate", because that is what the real brain says for the
  /// edit sentences the generation tests are actually about ("make the sofa
  /// darker", "open the wall"). A test about a CONVERSATION sets it to false
  /// explicitly, which is also the honest shape: whether a line generates is a
  /// backend verdict, so a test must state which verdict it is exercising.
  ///
  /// The product's fail-closed behaviour does NOT live here — it lives in
  /// `PwaChatTurn.silent()` and in the `== true` parse, both separately guarded.
  PwaChatTurn chatTurn = const PwaChatTurn(
    aiMessage: '',
    shouldGenerate: true,
  );
  final List<String> chatCalls = <String>[];

  final List<PwaGenerationIntent> calls = <PwaGenerationIntent>[];
  final Map<String, PwaGeneratedVision> _byIdempotencyKey = {};

  @override
  Future<PwaChatTurn> chat({
    required String projectId,
    required String message,
    String uiLocale = 'en',
  }) async {
    chatCalls.add(message);
    return chatTurn;
  }

  @override
  Future<PwaGenerationLifecycle> status(String idempotencyKey) async {
    statusCalls++;
    if (lifecycle.isNotEmpty) return lifecycle.removeAt(0);
    final prior = _byIdempotencyKey[idempotencyKey];
    return prior == null
        ? const PwaGenerationLifecycle(state: 'UNKNOWN')
        : PwaGenerationLifecycle(state: 'COMPLETED', vision: prior);
  }

  @override
  Future<PwaRefineVerification?> verify({
    required String projectId,
    required String beforePath,
    required String afterPath,
    required List<Map<String, Object?>> changes,
  }) async {
    verifyCalls++;
    return verification;
  }

  @override
  Future<PwaGeneratedVision> generate(PwaGenerationIntent intent) async {
    calls.add(intent);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final a = advisory;
    if (a != null && !intent.confirm) throw PwaAdvisoryRaised(a);
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
      resolvedRoomType: resolvedRoomType,
      resolvedAtmosphereId: resolvedAtmosphereId,
      resolvedAtmosphereLabel: resolvedAtmosphereLabel,
      changes: intent.actionType == 'refine' && intent.userInstruction.isNotEmpty
          ? [
              {
                'type': 'modify',
                'object': '',
                'detail': '',
                'raw': intent.userInstruction,
                'normalized': intent.userInstruction,
              },
            ]
          : const [],
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
