// The three CLIENT halves of mobile→PWA parity that a backend test cannot see.
//
// Each one is a decision the browser was making on its own, and each was found
// the expensive way — by a person running the app:
//
//   PROC — a generation the backend was still rendering was shown as a failure,
//          which invited a second paid render for one request.
//   ROOM — "Ayden Decide" was resolved server side and the answer thrown away,
//          so every later turn kept talking about "Your space".
//   VER  — the free verify second call did not exist, so a refine that only
//          half-landed was presented as if it had fully landed.
//
// These assert BEHAVIOUR through the controller, not source text.

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:flutter_test/flutter_test.dart';

AydenImageSource _source() => AydenImageSource(
  bytes: Uint8List.fromList(const [1, 2, 3]),
  filename: 'room.jpg',
  mimeType: 'image/jpeg',
);

/// A service that answers PROCESSING on the FIRST generate — exactly what the
/// adapter returns when the durable claim is held elsewhere — and then reports
/// the winner's result through the lifecycle poll.
class _HeldService implements PwaGenerationService {
  _HeldService({this.processingTicks = 2, this.thenState = 'COMPLETED'});

  /// How many polls answer PROCESSING before the terminal one.
  int processingTicks;
  String thenState;

  int generateCalls = 0;
  int statusCalls = 0;

  static const winner = PwaGeneratedVision(
    imagePath: 'users/u1/projects/p1/generated/winner.jpg',
    visionNumber: 1,
    replayed: true,
    backendVisionId: 'winner',
    resolvedRoomType: 'living_room',
    resolvedAtmosphereId: 'japandi_calm',
    resolvedAtmosphereLabel: 'Japandi Calm',
  );

  @override
  Future<PwaGeneratedVision> generate(PwaGenerationIntent intent) async {
    generateCalls++;
    throw const PwaGenerationProcessing('held-key');
  }

  /// This rig only exercises the LIFECYCLE, which is reached from
  /// `generateFirstVision` / the retry path — never through the chat gate. It
  /// still answers, so the seam is complete.
  @override
  Future<PwaChatTurn> chat({
    required String projectId,
    required String message,
    String uiLocale = 'en',
  }) async => const PwaChatTurn(aiMessage: '', shouldGenerate: true);

  @override
  Future<PwaGenerationLifecycle> status(String idempotencyKey) async {
    statusCalls++;
    if (statusCalls <= processingTicks) {
      return const PwaGenerationLifecycle(state: 'PROCESSING');
    }
    return switch (thenState) {
      'COMPLETED' => const PwaGenerationLifecycle(
        state: 'COMPLETED',
        vision: winner,
      ),
      'FAILED' => const PwaGenerationLifecycle(
        state: 'FAILED',
        errorCode: 'ENGINE_REJECTED',
      ),
      _ => const PwaGenerationLifecycle(state: 'UNKNOWN'),
    };
  }

  @override
  Future<PwaRefineVerification?> verify({
    required String projectId,
    required String beforePath,
    required String afterPath,
    required List<Map<String, Object?>> changes,
  }) async => null;

  @override
  void dispose() {}
}

PwaController _controller(PwaGenerationService gen) => PwaController(
  MockPwaExperienceRepository(workDelay: Duration.zero, seedLibrary: false),
  generation: gen,
  pending: PwaMemoryPendingGenerationStore(),
);

void main() {
  // ── PROCESSING is a state, not a failure ──────────────────────────────────
  group('a generation held by the backend is waited for, never failed', () {
    test(
      'PROC-C01: PROCESSING produces NO error banner and NO second generate',
      () async {
        final gen = _HeldService();
        final c = _controller(gen);
        c.setSource(_source());
        await c.generateFirstVision();

        expect(
          c.state.generationError,
          isNull,
          reason: 'the render is running; there is nothing to apologise for',
        );
        expect(
          gen.generateCalls,
          1,
          reason: 'a second generate is a second paid render',
        );
        expect(gen.statusCalls, greaterThan(1));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test('PROC-C02: the winner\'s vision is adopted, not regenerated', () async {
      final gen = _HeldService();
      final c = _controller(gen);
      c.setSource(_source());
      await c.generateFirstVision();

      expect(c.state.versions, hasLength(1));
      expect(c.state.versions.single.versionId, 'winner');
      expect(c.state.versions.single.afterAsset, _HeldService.winner.imagePath);
      expect(c.state.generating, isFalse);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test(
      'PROC-C03: a claim that really did fail still surfaces as a failure',
      () async {
        final gen = _HeldService(thenState: 'FAILED');
        final c = _controller(gen);
        c.setSource(_source());
        await c.generateFirstVision();

        expect(c.state.generationError, isNotNull);
        expect(c.state.versions, isEmpty);
        expect(
          c.state.phase,
          PwaPhase.entry,
          reason: 'a real failure returns to Create with the photo intact',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'PROC-C04: a backend that knows nothing is not treated as a failure on '
      'the first tick — it is retried before any verdict',
      () async {
        final gen = _HeldService(processingTicks: 0, thenState: 'UNKNOWN');
        final c = _controller(gen);
        c.setSource(_source());
        await c.generateFirstVision();

        expect(
          gen.statusCalls,
          greaterThanOrEqualTo(5),
          reason: 'one missing answer is a dropped packet, not a verdict',
        );
        expect(c.state.generationError, isNotNull);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });

  // ── the resolved room is adopted, never re-invented ───────────────────────
  group('the engine resolves the delegated choices; the app adopts them', () {
    test('ROOM-C01: a delegated room adopts what Ayden read from the photo', () async {
      final gen = PwaFakeGenerationService()
        ..resolvedRoomType = 'living_room'
        ..resolvedAtmosphereId = 'japandi_calm'
        ..resolvedAtmosphereLabel = 'Japandi Calm';
      final c = _controller(gen);
      c.setSource(_source());
      expect(c.state.selectedRoomId, isNull, reason: 'delegated');
      await c.generateFirstVision();

      expect(c.state.selectedRoomId, 'livingRoom');
    });

    test('ROOM-C02: an EXPLICIT room is never overridden', () async {
      final gen = PwaFakeGenerationService()..resolvedRoomType = 'living_room';
      final c = _controller(gen);
      c.selectRoom('kitchen');
      c.setSource(_source());
      await c.generateFirstVision();

      expect(
        c.state.selectedRoomId,
        'kitchen',
        reason: "resolving over the person's own choice is not a fix",
      );
    });

    test(
      'ROOM-C03: a room this build has no card for leaves the selection alone',
      () async {
        final gen = PwaFakeGenerationService()..resolvedRoomType = 'pool_area';
        final c = _controller(gen);
        c.setSource(_source());
        await c.generateFirstVision();

        expect(c.state.selectedRoomId, isNull);
      },
    );

    test(
      'ATMO-C01: "Ayden Signature" is replaced by the atmosphere actually used',
      () async {
        final gen = PwaFakeGenerationService()
          ..resolvedAtmosphereId = 'japandi_calm'
          ..resolvedAtmosphereLabel = 'Japandi Calm';
        final c = _controller(gen);
        c.setSource(_source());
        await c.generateFirstVision();

        expect(c.state.versions.single.atmosphereId, 'japandi_calm');
        expect(
          c.state.selectedAtmosphereId,
          'japandi_calm',
          reason:
              'the meta-choice is not an atmosphere; storing it made the next '
              'switch read `ayden_signature` as its previous atmosphere',
        );
      },
    );

    test('ATMO-C02: an unknown atmosphere id is refused, not shown', () async {
      final gen = PwaFakeGenerationService()
        ..resolvedAtmosphereId = 'not_an_atmosphere';
      final c = _controller(gen);
      c.setSource(_source());
      await c.generateFirstVision();

      expect(c.state.versions.single.atmosphereId, 'ayden_signature');
    });
  });

  // ── verify: a free second look, silent unless something is missing ────────
  group('the refine verify second call', () {
    Future<PwaController> refined(PwaFakeGenerationService gen) async {
      final c = _controller(gen);
      c.selectRoom('livingRoom');
      c.setSource(_source());
      await c.generateFirstVision();
      await c.applyRefine('make the sofa white');
      return c;
    }

    test('VER-C01: it runs AFTER the vision exists, never before', () async {
      final gen = PwaFakeGenerationService();
      final c = await refined(gen);
      expect(c.state.versions, hasLength(2));
      expect(gen.verifyCalls, 1);
    });

    test('VER-C02: a silent verdict adds nothing to the conversation', () async {
      final gen = PwaFakeGenerationService(); // verification == null
      final c = await refined(gen);
      expect(
        c.state.messages.where((m) => m.text.contains('Still missing')),
        isEmpty,
      );
      expect(c.state.generationError, isNull);
    });

    test('VER-C03: `incomplete` adds ONE report with a targeted retry', () async {
      final gen = PwaFakeGenerationService()
        ..verification = const PwaRefineVerification(
          report: 'Applied: white sofa. Still missing: the floor lamp.',
          missing: ['add a floor lamp'],
        );
      final c = await refined(gen);
      await Future<void>.delayed(Duration.zero);

      final reports = c.state.messages
          .where((m) => m.text.contains('Still missing'))
          .toList();
      expect(reports, hasLength(1));
      expect(reports.single.pendingRefine, 'add a floor lamp');
      expect(reports.single.chips, ['Try again']);
    });

    test('VER-C04: the report never creates a vision or an error', () async {
      final gen = PwaFakeGenerationService()
        ..verification = const PwaRefineVerification(
          report: 'Still missing: the floor lamp.',
          missing: ['add a floor lamp'],
        );
      final c = await refined(gen);
      await Future<void>.delayed(Duration.zero);

      expect(c.state.versions, hasLength(2), reason: 'V1 + the refine only');
      expect(c.state.generationError, isNull);
      expect(c.state.generating, isFalse);
    });

    test(
      'VER-C05: no verify is fired for a switch or a first vision — it is a '
      'REFINE contract',
      () async {
        final gen = PwaFakeGenerationService();
        final c = _controller(gen);
        c.setSource(_source());
        await c.generateFirstVision();
        c.stageAtmosphere('japandi_calm');
        await c.applyAtmosphere();

        expect(gen.verifyCalls, 0);
      },
    );
  });
}
