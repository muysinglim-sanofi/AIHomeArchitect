// Looking at a project must not change it.
//
// Written after a measured defect: opening project 67104a97 from Home and
// coming straight back moved its `updated_at` from 2026-08-06T16:23:29Z to
// 2026-08-07T10:50:09Z and incremented its revision, with no user edit at all.
// The card then jumped to the top of "Recently updated" — the library was
// telling the user they had changed something they had only read.
//
// The cause was not the database trigger, which is correct: it was the client
// issuing an UPDATE with identical values on every navigation. `bumpUpdated:
// false` never prevented it — that flag only holds the CLIENT counter still,
// and the server clock does not consult it.

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_route.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_persistence_repository.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_project.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts every DURABLE write. `saveProject` is the seam the incident went
/// through, so its call count is the whole measurement.
class _CountingStore implements PwaPersistenceRepository {
  final Map<String, PwaProjectSnapshot> rows = {};
  final List<String> writes = [];

  int get saves => writes.where((w) => w == 'saveProject').length;

  @override
  Future<void> saveProject(
    PwaProjectSnapshot project, {
    bool replaceOriginal = false,
  }) async {
    writes.add('saveProject');
    rows[project.projectId] = project;
  }

  @override
  Future<PwaOriginalUpload> prepareGeneration(
    PwaProjectSnapshot snapshot, {
    bool replaceOriginal = false,
  }) async {
    writes.add('prepareGeneration');
    const path = 'users/u1/projects/p1/original/o1.jpg';
    rows[snapshot.projectId] = snapshot.copyWith(originalImageAsset: path);
    return PwaOriginalUpload.forPath(snapshot.projectId, path);
  }

  @override
  Future<String> signedImageUrl(String path, int expiresInSeconds) async =>
      'https://signed.test/$path';

  @override
  Future<PwaInstallationIdentity> ensureInstallation() async =>
      const PwaInstallationIdentity('inst');

  @override
  Future<void> healthCheck() async {}

  @override
  Future<List<PwaProjectSnapshot>> loadLibrary() async => rows.values.toList();

  @override
  Future<PwaProjectSnapshot?> loadProject(String id) async => rows[id];

  @override
  Future<void> appendVision(String p, PwaVision v) async =>
      writes.add('appendVision');

  @override
  Future<void> appendMessage(String p, PwaMessage m) async =>
      writes.add('appendMessage');

  @override
  Future<void> updateCurrentVision(String p, String v) async =>
      writes.add('updateCurrentVision');

  @override
  Future<void> updateCoverVision(String p, String v) async =>
      writes.add('updateCoverVision');

  @override
  Future<void> renameProject(String p, String t) async =>
      writes.add('renameProject');

  @override
  Future<PwaProjectSnapshot> duplicateProject(String p) async => rows[p]!;

  @override
  Future<void> softDeleteProject(String p) async =>
      writes.add('softDeleteProject');

  @override
  Future<Uint8List?> loadOriginalBytes(PwaProjectSnapshot s) async =>
      // The staging adapter returns the REAL bytes here, and opening a project
      // rebuilds an AydenImageSource from them. That fresh object is what made
      // the replaced-photo check fire on a project nobody had edited.
      Uint8List.fromList(const [9, 9, 9]);
}

/// A project as the backend already holds it: three visions, current = cover =
/// the third — the exact shape of the project the incident was observed on.
PwaProjectSnapshot _storedProject({String id = 'p-stored'}) {
  PwaVision v(int n, String action, {String atmo = 'ayden_signature'}) =>
      PwaVision(
        versionId: 'v$n',
        projectId: id,
        visionNumber: n,
        title: 'Vision $n',
        atmosphereId: atmo,
        actionType: action == 'refine'
            ? PwaActionType.refine
            : action == 'switch'
            ? PwaActionType.switchAtmosphere
            : PwaActionType.signature,
        afterAsset: 'users/u1/projects/$id/generated/v$n.jpg',
        order: n,
        parentVersionId: n == 1 ? null : 'v${n - 1}',
        isCurrent: n == 3,
        remotePersisted: true,
      );
  return PwaProjectSnapshot(
    projectId: id,
    title: 'Open-plan Living Space',
    originalImageAsset: 'users/u1/projects/$id/original/o1.jpg',
    roomId: null,
    roomLabel: 'Your space',
    selectedAtmosphereId: 'japandi_calm',
    atmosphereLabel: 'Japandi Calm',
    visions: [
      v(1, 'initial'),
      v(2, 'refine'),
      v(3, 'switch', atmo: 'japandi_calm'),
    ],
    messages: const [],
    currentVisionId: 'v3',
    coverVisionId: 'v3',
    createdOrder: 10,
    updatedOrder: 10,
    updatedLabel: 'Yesterday',
    status: PwaProjectStatus.active,
  );
}

PwaController _controller(_CountingStore store, {PwaBootRestore? restore}) =>
    PwaController(
      MockPwaExperienceRepository(workDelay: Duration.zero, seedLibrary: false),
      generation: PwaFakeGenerationService(),
      pending: PwaMemoryPendingGenerationStore(),
      persistence: store,
      restore: restore,
    );

AydenImageSource _source() => AydenImageSource(
  bytes: Uint8List.fromList(const [1, 2, 3]),
  filename: 'room.jpg',
  mimeType: 'image/jpeg',
);

void main() {
  group('reading a project writes nothing', () {
    late _CountingStore store;
    late PwaController c;

    setUp(() {
      store = _CountingStore();
      final stored = _storedProject();
      store.rows[stored.projectId] = stored;
      c = _controller(
        store,
        restore: PwaBootRestore(library: [stored], active: stored),
      );
      store.writes.clear(); // ignore anything the boot itself did
    });

    test('RO01: opening a project issues NO durable write', () async {
      await c.openProject('p-stored');
      await pumpEventQueue();
      expect(c.state.versions, hasLength(3));
      expect(store.saves, 0, reason: 'opening is reading');
    });

    test('RO02: open → back Home issues NO durable write', () async {
      await c.openProject('p-stored');
      c.returnToStudio();
      await pumpEventQueue();
      expect(store.saves, 0);
    });

    test('RO03: opening My Projects issues NO durable write', () async {
      await c.openProject('p-stored');
      c.openLibrary();
      await pumpEventQueue();
      expect(store.saves, 0);
    });

    test('RO04: the Full Reveal and back issue NO durable write', () async {
      await c.openProject('p-stored');
      c.openReveal('v2');
      c.backToConversation();
      c.previewVision('v1');
      c.clearPreview();
      await pumpEventQueue();
      expect(store.saves, 0, reason: 'previewing changes no stored field');
    });

    test('RO05: a whole navigation loop stays silent', () async {
      // The exact sequence that moved updated_at in staging.
      await c.openProject('p-stored');
      c.openReveal('v3');
      c.backToConversation();
      c.returnToStudio();
      c.openLibrary();
      await c.openProject('p-stored');
      c.returnToStudio();
      await pumpEventQueue();
      expect(store.saves, 0);
      expect(store.writes, isEmpty, reason: 'no durable call of ANY kind');
    });

    test('RO07: opening a project whose photo is REHYDRATED still writes '
        'nothing', () async {
      // The regression that survived the first fix. Staging downloads the
      // original and builds a new AydenImageSource from it; identity-based
      // change detection then read that as "the user replaced the photo",
      // which both re-uploaded the image and pushed the write past the guard.
      await c.openProject('p-stored');
      expect(
        c.state.source,
        isNotNull,
        reason: 'the original must actually have been rehydrated',
      );
      c.returnToStudio();
      await pumpEventQueue();
      expect(store.saves, 0);
      expect(
        store.writes.where((w) => w == 'prepareGeneration'),
        isEmpty,
        reason: 'a rehydrated original is never re-uploaded',
      );
    });

    test('RO06: a route restore issues NO durable write', () async {
      c.applyRoute(const PwaRoute(PwaPage.architect, projectId: 'p-stored'));
      await pumpEventQueue();
      c.applyRoute(PwaRoute.home);
      await pumpEventQueue();
      expect(store.saves, 0);
    });
  });

  group('a real change still writes', () {
    late _CountingStore store;
    late PwaController c;

    setUp(() {
      store = _CountingStore();
      final stored = _storedProject();
      store.rows[stored.projectId] = stored;
      c = _controller(
        store,
        restore: PwaBootRestore(library: [stored], active: stored),
      );
      store.writes.clear();
    });

    test('RO10: setting a different current vision writes', () async {
      await c.openProject('p-stored');
      c.setCurrentVision('v1');
      await pumpEventQueue();
      // setCurrentVision alone does not sync; the next real sync must carry it.
      c.sendUserText('what do you think?');
      await pumpEventQueue();
      expect(store.saves, greaterThan(0));
    });

    test('RO11: a new message writes', () async {
      await c.openProject('p-stored');
      c.sendUserText('make it warmer');
      await pumpEventQueue();
      expect(store.saves, 1, reason: 'the conversation grew');
    });

    test('RO12: a refine that produces a vision writes', () async {
      await c.openProject('p-stored');
      await c.applyRefine('warmer lighting');
      await pumpEventQueue();
      expect(c.state.versions, hasLength(4));
      expect(store.saves, greaterThan(0));
    });

    test('RO13: an atmosphere switch that produces a vision writes', () async {
      await c.openProject('p-stored');
      c.stageAtmosphere('soft_luxury');
      await c.applyAtmosphere();
      await pumpEventQueue();
      expect(c.state.versions, hasLength(4));
      expect(store.saves, greaterThan(0));
    });

    test('RO14: a rename writes', () async {
      await c.openProject('p-stored');
      store.writes.clear();
      c.renameProject('p-stored', 'Garden Studio');
      await pumpEventQueue();
      expect(store.writes, contains('renameProject'));
    });

    test('RO15: the first vision of a NEW project writes', () async {
      c.newProject();
      c.setSource(_source());
      await c.generateFirstVision();
      await pumpEventQueue();
      expect(c.state.versions, hasLength(1));
      expect(store.saves, greaterThan(0));
    });

    test('RO16: after a real write, reading again is silent again', () async {
      await c.openProject('p-stored');
      c.sendUserText('make it warmer');
      await pumpEventQueue();
      final afterEdit = store.saves;
      expect(afterEdit, greaterThan(0));

      c.returnToStudio();
      c.openLibrary();
      await c.openProject('p-stored');
      c.returnToStudio();
      await pumpEventQueue();
      expect(
        store.saves,
        afterEdit,
        reason: 'the edit persisted once; reading it back writes nothing',
      );
    });
  });

  group('a failed refine can be retried', () {
    late _CountingStore store;
    late PwaController c;
    late PwaFakeGenerationService gen;

    setUp(() async {
      store = _CountingStore();
      final stored = _storedProject();
      store.rows[stored.projectId] = stored;
      gen = PwaFakeGenerationService();
      c = PwaController(
        MockPwaExperienceRepository(
          workDelay: Duration.zero,
          seedLibrary: false,
        ),
        generation: gen,
        pending: PwaMemoryPendingGenerationStore(),
        persistence: store,
        restore: PwaBootRestore(library: [stored], active: stored),
      );
      await c.openProject('p-stored');
    });

    test(
      'RETRY01: a failed refine leaves a retryable error and NO vision',
      () async {
        gen.failure = const PwaGenerationFailure(
          code: 'ENGINE_UNAVAILABLE',
          userMessage: "Ayden couldn't reach the design engine.",
          retryable: true,
        );
        await c.applyRefine('break the wall on the right and add a kitchen');
        await pumpEventQueue();

        expect(
          c.state.versions,
          hasLength(3),
          reason: 'no vision was invented',
        );
        expect(c.state.generationError, isNotNull);
        expect(c.state.generationRetryable, isTrue);
        expect(c.state.generating, isFalse);
        // The placeholder is gone: a failure must not leave "creating…" behind.
        expect(
          c.state.messages.where((m) => m.kind == PwaMessageKind.loading),
          isEmpty,
        );
      },
    );

    test('RETRY02: Try again re-runs the SAME logical generation', () async {
      gen.failure = const PwaGenerationFailure(
        code: 'ENGINE_UNAVAILABLE',
        userMessage: "Ayden couldn't reach the design engine.",
        retryable: true,
      );
      const instruction = 'break the wall on the right and add a kitchen';
      await c.applyRefine(instruction);
      await pumpEventQueue();
      final firstCall = gen.calls.single;

      gen.failure = null; // the engine comes back
      await c.retryGeneration();
      await pumpEventQueue();

      expect(gen.calls, hasLength(2), reason: 'the retry actually ran');
      final retryCall = gen.calls.last;
      expect(retryCall.idempotencyKey, firstCall.idempotencyKey);
      expect(retryCall.userInstruction, instruction);
      expect(retryCall.parentVisionId, firstCall.parentVisionId);
      expect(retryCall.actionType, 'refine');
      expect(retryCall.projectId, 'p-stored');

      expect(c.state.versions, hasLength(4), reason: 'Vision 4 exists');
      expect(c.state.versions.last.instruction, instruction);
      expect(c.state.generationError, isNull);
    });

    test('RETRY03: the retry SHOWS that it restarted', () async {
      // The button was wired all along; what made it read as dead was two
      // silent minutes with nothing in the conversation.
      gen.failure = const PwaGenerationFailure(
        code: 'ENGINE_UNAVAILABLE',
        userMessage: 'x',
        retryable: true,
      );
      await c.applyRefine('make the sofa white');
      await pumpEventQueue();
      expect(
        c.state.messages.where((m) => m.kind == PwaMessageKind.loading),
        isEmpty,
      );

      gen.delay = const Duration(milliseconds: 50);
      gen.failure = null;
      final running = c.retryGeneration();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        c.state.messages.where((m) => m.kind == PwaMessageKind.loading),
        hasLength(1),
        reason: 'the conversation shows work in progress',
      );
      expect(c.state.generating, isTrue);

      await running;
      await pumpEventQueue();
      // …and the placeholder is replaced by the reveal, never left behind.
      expect(
        c.state.messages.where((m) => m.kind == PwaMessageKind.loading),
        isEmpty,
      );
      expect(c.state.versions, hasLength(4));
    });

    test('RETRY04: a completed result is adopted, never regenerated', () async {
      const instruction = 'add a kitchen island';
      await c.applyRefine(instruction);
      await pumpEventQueue();
      expect(c.state.versions, hasLength(4));
      final callsAfterSuccess = gen.calls.length;

      // Nothing is pending any more, so a stray retry does nothing at all.
      await c.retryGeneration();
      await pumpEventQueue();
      expect(
        gen.calls,
        hasLength(callsAfterSuccess),
        reason: 'no second render',
      );
      expect(c.state.versions, hasLength(4), reason: 'no duplicate vision');
    });
  });
}
