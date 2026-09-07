// The Flutter WIRING of real generation: the controller asks the injected
// service, uses what it returns, and never falls back to a bundled fixture.
//
// The API client, the service seam and the URL resolver are proven in
// pwa_generation_api_test / pwa_generation_service_test. What is proven HERE is
// everything between them and the screen: that the upload reports its path back,
// that the path reaches the request, that the returned path becomes the vision,
// that a failure produces no vision at all, that a reload replays instead of
// regenerating, and that no widget renders a Storage path as an asset.

import 'dart:io';
import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_image_url_resolver.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_persistence_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_project_serialization.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_repository_error.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_project.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_stored_image.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ── fakes ────────────────────────────────────────────────────────────────────

AydenImageSource _source([List<int> bytes = const [1, 2, 3]]) =>
    AydenImageSource(
      bytes: Uint8List.fromList(bytes),
      filename: 'room.jpg',
      mimeType: 'image/jpeg',
    );

/// Stands in for the staging adapter. It behaves like the real one where it
/// matters here: the ORIGINAL is uploaded once and its canonical path is
/// reported back, a retry reuses it, and rows the backend wrote are not
/// re-appended locally.
class _FakeStore implements PwaPersistenceRepository {
  final Map<String, PwaProjectSnapshot> rows = {};
  final List<String> calls = [];
  int uploads = 0;
  bool failPrepare = false;

  @override
  Future<PwaOriginalUpload> prepareGeneration(
    PwaProjectSnapshot snapshot, {
    bool replaceOriginal = false,
  }) async {
    calls.add('prepareGeneration');
    if (failPrepare) {
      failPrepare = false;
      throw const PwaRepositoryError(PwaErrorKind.storage, 'upload boom');
    }
    final prior = rows[snapshot.projectId];
    final priorPath = prior?.originalImageAsset;
    final reusable =
        priorPath != null &&
        pwaImageSourceForPath(priorPath) == PwaImageSourceKind.stagingStorage &&
        !replaceOriginal;
    final path = reusable
        ? priorPath
        : () {
            uploads++;
            return 'users/u1/projects/${snapshot.projectId}/original/o$uploads.jpg';
          }();
    rows[snapshot.projectId] = snapshot.copyWith(originalImageAsset: path);
    return PwaOriginalUpload.forPath(snapshot.projectId, path);
  }

  @override
  Future<String> signedImageUrl(String path, int expiresInSeconds) async {
    calls.add('sign:$path');
    return 'https://signed.test/$path';
  }

  @override
  Future<void> saveProject(
    PwaProjectSnapshot project, {
    bool replaceOriginal = false,
  }) async {
    calls.add('saveProject');
    final prior = rows[project.projectId];
    rows[project.projectId] = prior == null
        ? project
        : project.copyWith(originalImageAsset: prior.originalImageAsset);
  }

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
  Future<void> appendVision(String p, PwaVision v) async {}

  @override
  Future<void> appendMessage(String p, PwaMessage m) async {}

  @override
  Future<void> updateCurrentVision(String p, String v) async {}

  @override
  Future<void> updateCoverVision(String p, String v) async {}

  @override
  Future<void> renameProject(String p, String t) async {}

  @override
  Future<PwaProjectSnapshot> duplicateProject(String p) async => rows[p]!;

  @override
  Future<void> softDeleteProject(String p) async => rows.remove(p);

  @override
  Future<Uint8List?> loadOriginalBytes(PwaProjectSnapshot s) async => null;
}

class _Rig {
  _Rig({PwaGenerationFailure? failure, PwaBootRestore? restore})
    : store = _FakeStore(),
      generation = PwaFakeGenerationService(failure: failure),
      pending = PwaMemoryPendingGenerationStore() {
    controller = PwaController(
      MockPwaExperienceRepository(workDelay: Duration.zero, seedLibrary: false),
      generation: generation,
      pending: pending,
      persistence: store,
      restore: restore,
    );
  }

  final _FakeStore store;
  final PwaFakeGenerationService generation;
  final PwaMemoryPendingGenerationStore pending;
  late final PwaController controller;

  PwaState get state => controller.state;
}

Future<_Rig> _generated() async {
  final rig = _Rig();
  rig.controller.selectRoom('living_room');
  rig.controller.setSource(_source());
  await rig.controller.generateFirstVision();
  return rig;
}

bool _isStoragePath(String p) => pwaIsStoragePath(p);

PwaProjectSnapshot _emptyProject(String id) => PwaProjectSnapshot(
  projectId: id,
  title: 'Open-plan Living Space',
  originalImageAsset: 'users/u1/projects/$id/original/o1.jpg',
  roomId: null,
  roomLabel: 'Your space',
  selectedAtmosphereId: 'ayden_signature',
  atmosphereLabel: 'Ayden Signature',
  visions: const [],
  messages: const [],
  currentVisionId: null,
  createdOrder: 1,
  updatedOrder: 1,
  updatedLabel: '',
  status: PwaProjectStatus.draft,
);

void main() {
  // ── injection ─────────────────────────────────────────────────────────────
  group('injection', () {
    test(
      'GEN01: the controller generates through the INJECTED service',
      () async {
        final rig = await _generated();
        expect(rig.generation.calls, hasLength(1));
        expect(rig.state.versions, hasLength(1));
      },
    );

    test('GEN02: the staging boot injects the REAL service, not a mock', () {
      final src = File('lib/main_pwa.dart').readAsStringSync();
      expect(src.contains('PwaStagingGenerationService('), isTrue);
      expect(
        src.contains('pwaGenerationServiceProvider.overrideWithValue'),
        isTrue,
      );
      expect(
        src.contains('pwaImageUrlResolverProvider.overrideWithValue'),
        isTrue,
      );
      expect(
        src.contains('pwaPendingGenerationStoreProvider.overrideWithValue'),
        isTrue,
      );
      // The offline service must never be constructed by the staging boot.
      expect(src.contains('PwaMockGenerationService('), isFalse);
    });

    test('GEN03: no widget builds a generation service or reads the env', () {
      for (final path
          in Directory('lib/features/pwa/presentation')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final src = path.readAsStringSync();
        expect(
          src.contains('PwaStagingGenerationService('),
          isFalse,
          reason: path.path,
        );
        expect(src.contains('PwaGenerationApi('), isFalse, reason: path.path);
        expect(src.contains('PwaEnvironment'), isFalse, reason: path.path);
      }
    });
  });

  // ── first generation ──────────────────────────────────────────────────────
  group('first generation', () {
    test(
      'GEN10: the upload reports its path and THAT path is generated from',
      () async {
        final rig = await _generated();
        final intent = rig.generation.calls.single;
        final id = rig.state.project.projectId;
        expect(
          intent.originalImagePath,
          'users/u1/projects/$id/original/o1.jpg',
        );
        expect(rig.store.uploads, 1);
      },
    );

    test(
      'GEN11: the vision image is the engine result, never a fixture',
      () async {
        final rig = await _generated();
        final v = rig.state.versions.single;
        expect(_isStoragePath(v.afterAsset), isTrue);
        expect(v.afterAsset.startsWith('assets/'), isFalse);
        expect(v.afterAsset, contains('/generated/'));
      },
    );

    test('GEN12: current and cover both point at the real vision', () async {
      final rig = await _generated();
      final v = rig.state.versions.single;
      expect(rig.state.currentVisionId, v.versionId);
      final row = rig.store.rows[rig.state.project.projectId]!;
      expect(row.coverVision?.versionId, v.versionId);
      expect(_isStoragePath(row.coverVision!.afterAsset), isTrue);
    });

    test('GEN13: a double click produces ONE generation', () async {
      final rig = _Rig();
      rig.controller.setSource(_source());
      final a = rig.controller.generateFirstVision();
      final b = rig.controller.generateFirstVision(); // second tap, same frame
      await Future.wait([a, b]);
      expect(rig.generation.generatedCount, 1);
      expect(rig.state.versions, hasLength(1));
      expect(rig.store.uploads, 1);
    });

    test(
      'GEN14: a failure yields NO vision, no card, and a visible error',
      () async {
        final rig = _Rig(
          failure: const PwaGenerationFailure(
            code: 'TIMEOUT',
            userMessage: 'This is taking longer than expected. Try again.',
            retryable: true,
          ),
        );
        rig.controller.setSource(_source());
        await rig.controller.generateFirstVision();
        expect(rig.state.versions, isEmpty);
        expect(rig.state.currentVisionId, isNull);
        expect(rig.state.library, isEmpty);
        expect(rig.state.phase, PwaPhase.entry);
        expect(rig.state.source, isNotNull, reason: 'the photo is kept');
        expect(rig.state.generationError, contains('taking longer'));
        expect(rig.state.generationRetryable, isTrue);
      },
    );

    test('GEN15: retry reuses the SAME key and never re-uploads', () async {
      final rig = _Rig(
        failure: const PwaGenerationFailure(
          code: 'BACKEND_UNREACHABLE',
          userMessage: 'nope',
          retryable: true,
        ),
      );
      rig.controller.setSource(_source());
      await rig.controller.generateFirstVision();
      final firstKey = rig.generation.calls.single.idempotencyKey;

      await rig.controller.retryGeneration();
      expect(rig.generation.calls, hasLength(2));
      expect(rig.generation.calls[1].idempotencyKey, firstKey);
      expect(
        rig.store.uploads,
        1,
        reason: 'the original is reused, not re-sent',
      );
    });

    test(
      'GEN16: an upload failure is a real error, not a silent fixture',
      () async {
        final rig = _Rig();
        rig.store.failPrepare = true;
        rig.controller.setSource(_source());
        await rig.controller.generateFirstVision();
        expect(rig.generation.calls, isEmpty, reason: 'nothing was generated');
        expect(rig.state.versions, isEmpty);
        expect(rig.state.generationError, isNotNull);
      },
    );

    test('GEN17: a new photo starts a NEW generation, not a replay', () async {
      final rig = _Rig(
        failure: const PwaGenerationFailure(
          code: 'TIMEOUT',
          userMessage: 'nope',
          retryable: true,
        ),
      );
      rig.controller.setSource(_source(const [1]));
      await rig.controller.generateFirstVision();
      final firstKey = rig.generation.calls.single.idempotencyKey;
      rig.controller.setSource(_source(const [2, 2]));
      await rig.controller.generateFirstVision();
      expect(rig.generation.calls[1].idempotencyKey, isNot(firstKey));
      expect(rig.state.generationError, isNotNull);
    });
  });

  // ── refinement ────────────────────────────────────────────────────────────
  group('refinement', () {
    test('GEN20: the parent and the instruction reach the engine', () async {
      final rig = await _generated();
      final parent = rig.state.versions.single;
      await rig.controller.applyRefine('warmer lighting');
      final intent = rig.generation.calls.last;
      expect(intent.actionType, 'refine');
      expect(intent.parentVisionId, parent.versionId);
      expect(intent.userInstruction, 'warmer lighting');
      expect(intent.visionNumber, 2);
    });

    test('GEN21: a child vision with a NEW real image is appended', () async {
      final rig = await _generated();
      final first = rig.state.versions.single;
      await rig.controller.applyRefine('warmer lighting');
      expect(rig.state.versions, hasLength(2));
      final child = rig.state.versions.last;
      expect(child.parentVersionId, first.versionId);
      expect(child.projectId, first.projectId);
      expect(_isStoragePath(child.afterAsset), isTrue);
      expect(child.afterAsset, isNot(first.afterAsset));
      expect(rig.state.currentVisionId, child.versionId);
      // Append-only: the previous vision is untouched and still present.
      expect(rig.state.versions.first.afterAsset, first.afterAsset);
    });

    test(
      'GEN22: a failed refine leaves the conversation and lineage intact',
      () async {
        final rig = await _generated();
        final before = rig.state.versions.single;
        final messagesBefore = rig.state.messages.length;
        rig.generation.failure = const PwaGenerationFailure(
          code: 'TIMEOUT',
          userMessage: 'took too long',
          retryable: true,
        );
        await rig.controller.applyRefine('warmer lighting');
        expect(rig.state.versions, hasLength(1));
        expect(rig.state.versions.single.afterAsset, before.afterAsset);
        expect(rig.state.currentVisionId, before.versionId);
        expect(rig.state.generationError, 'took too long');
        // The loading placeholder is gone — no permanent spinner in the chat.
        expect(
          rig.state.messages.where((m) => m.kind == PwaMessageKind.loading),
          isEmpty,
        );
        expect(rig.state.messages.length, messagesBefore);
      },
    );
  });

  // ── atmosphere ────────────────────────────────────────────────────────────
  group('atmosphere', () {
    test('GEN30: a switch is a real generation, not a relabel', () async {
      final rig = await _generated();
      final first = rig.state.versions.single;
      rig.controller.stageAtmosphere('japandi_calm');
      await rig.controller.applyAtmosphere();

      final intent = rig.generation.calls.last;
      expect(intent.actionType, 'switch_atmosphere');
      expect(intent.atmosphereId, 'japandi_calm');
      expect(intent.parentVisionId, first.versionId);

      final child = rig.state.versions.last;
      expect(rig.state.versions, hasLength(2));
      expect(child.atmosphereId, 'japandi_calm');
      expect(_isStoragePath(child.afterAsset), isTrue);
      expect(
        child.afterAsset,
        isNot(first.afterAsset),
        reason: 'a new atmosphere must produce a NEW image',
      );
    });

    test('GEN31: the chat order is user → generating → Ayden → vision', () async {
      final rig = await _generated();
      final before = rig.state.messages.length;
      rig.controller.stageAtmosphere('warm_modern');
      final run = rig.controller.applyAtmosphere();
      // While it runs, the user's line and the placeholder are both present.
      expect(rig.state.messages[before].role, PwaRole.user);
      expect(rig.state.messages[before + 1].kind, PwaMessageKind.loading);
      await run;
      // Once it lands, the placeholder is replaced by the reveal of the vision.
      final reveal = rig.state.messages.last;
      expect(reveal.kind, PwaMessageKind.reveal);
      expect(reveal.visionId, rig.state.versions.last.versionId);
      expect(
        rig.state.messages.where((m) => m.kind == PwaMessageKind.loading),
        isEmpty,
      );
    });
  });

  // ── "Before" is the image this vision was made FROM ───────────────────────
  group('full reveal lineage', () {
    PwaVision mkVision(String id, {String? parent, int n = 1}) => PwaVision(
      versionId: id,
      projectId: 'p1',
      visionNumber: n,
      order: n,
      title: 'v$n',
      atmosphereId: 'warm_modern',
      afterAsset: 'users/u1/projects/p1/generated/$id.jpg',
      actionType: n == 1 ? PwaActionType.signature : PwaActionType.refine,
      parentVersionId: parent,
    );

    const project = PwaProject(
      projectId: 'p1',
      title: 'Open-plan Living Space',
      originalAsset: 'users/u1/projects/p1/original/photo.jpg',
    );

    test('REVEAL01: a first vision compares against the uploaded photo', () {
      final v1 = mkVision('v1');
      expect(pwaBeforeReference(v1, [v1], project), project.originalAsset);
    });

    test('REVEAL02: a refine compares against the vision it refined', () {
      // Reported 2026-08-10: the Full Reveal of a second vision still showed
      // the original empty room, so the slider answered "what did the room look
      // like before you started?" instead of "what did this change do?".
      final v1 = mkVision('v1');
      final v2 = mkVision('v2', parent: 'v1', n: 2);
      expect(pwaBeforeReference(v2, [v1, v2], project), v1.afterAsset);
    });

    test('REVEAL03: a third vision compares against the second, not the first',
        () {
      final v1 = mkVision('v1');
      final v2 = mkVision('v2', parent: 'v1', n: 2);
      final v3 = mkVision('v3', parent: 'v2', n: 3);
      expect(pwaBeforeReference(v3, [v1, v2, v3], project), v2.afterAsset);
    });

    test('REVEAL04: a branch compares against ITS parent, not the latest', () {
      // Two children of v1: each must face v1, whichever was made last.
      final v1 = mkVision('v1');
      final v2 = mkVision('v2', parent: 'v1', n: 2);
      final v3 = mkVision('v3', parent: 'v1', n: 3);
      expect(pwaBeforeReference(v3, [v1, v2, v3], project), v1.afterAsset);
    });

    test('REVEAL05: an unresolvable parent falls back to the photo, never to '
        'nothing', () {
      final orphan = mkVision('v9', parent: 'gone', n: 2);
      expect(pwaBeforeReference(orphan, [orphan], project), project.originalAsset);
    });

    test('REVEAL06: the in-memory photo is only used where the photo IS the '
        'before', () {
      // The freshly-picked bytes are the original. Putting them opposite a
      // refinement would show the empty room again — the very bug.
      final src = File('lib/features/pwa/presentation/pwa_widgets.dart')
          .readAsStringSync();
      expect(src.contains('final isOriginal = reference == project.originalAsset;'),
          isTrue);
      expect(src.contains('if (source != null && isOriginal)'), isTrue);
    });

    test('REVEAL07: every reveal surface is given the lineage', () {
      // The First Reveal was the third such surface. It is deleted: the first
      // vision now arrives in the session like every other, so there is no
      // one-off unveiling left to hand a lineage to.
      for (final path in [
        'lib/features/pwa/presentation/pwa_reveal_screen.dart',
        'lib/features/pwa/presentation/pwa_versions_sheet.dart',
      ]) {
        expect(File(path).readAsStringSync().contains('versions: state.versions'),
            isTrue, reason: path);
      }
    });
  });

  // ── reload / resume ───────────────────────────────────────────────────────
  group('resume after reload', () {
    test('GEN40: the intent is recorded BEFORE the request', () async {
      final rig = _Rig();
      rig.controller.setSource(_source());
      await rig.controller.generateFirstVision();
      expect(rig.pending.writes, hasLength(1));
      expect(
        rig.pending.writes.single.idempotencyKey,
        rig.generation.calls.single.idempotencyKey,
      );
    });

    test('GEN41: a completed generation leaves nothing pending', () async {
      final rig = await _generated();
      expect(await rig.pending.read(), isNull);
    });

    test(
      'GEN42: a failed generation leaves the record for the replay',
      () async {
        final rig = _Rig(
          failure: const PwaGenerationFailure(
            code: 'TIMEOUT',
            userMessage: 'nope',
            retryable: true,
          ),
        );
        rig.controller.setSource(_source());
        await rig.controller.generateFirstVision();
        final left = await rig.pending.read();
        expect(left, isNotNull);
        expect(
          left!.idempotencyKey,
          rig.generation.calls.single.idempotencyKey,
        );
      },
    );

    test(
      'GEN43: a reload replays with the same key and yields ONE vision',
      () async {
        // A project row exists (the pre-generation upload wrote it) but has no
        // vision — exactly the state a tab refreshed mid-render comes back to.
        final rig = _Rig();
        rig.controller.setSource(_source());
        await rig.controller.generateFirstVision();
        final projectId = rig.state.project.projectId;
        final key = rig.generation.calls.single.idempotencyKey;
        final originalPath = rig.generation.calls.single.originalImagePath;

        // Reboot against the SAME backend with the record still pending.
        final rebooted = _Rig(
          restore: PwaBootRestore(
            library: const [],
            active: rig.store.rows[projectId]!.copyWith(visions: const []),
            route: null,
            pending: PwaPendingGeneration(
              projectId: projectId,
              idempotencyKey: key,
              actionType: 'initial',
              roomId: '',
              roomLabel: 'Your space',
              atmosphereId: 'ayden_signature',
              atmosphereLabel: 'Ayden Signature',
              originalStoragePath: originalPath,
              visionNumber: 1,
              // Seconds old — the tab was refreshed while the render ran, which
              // is the only situation a boot may replay on its own.
              startedAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
        );
        await pumpEventQueue();
        expect(rebooted.generation.calls, hasLength(1));
        expect(rebooted.generation.calls.single.idempotencyKey, key);
        expect(rebooted.state.versions, hasLength(1));
        expect(await rebooted.pending.read(), isNull);
      },
    );

    test(
      'GEN44: a reload that already has the vision does NOT replay',
      () async {
        final rig = await _generated();
        final projectId = rig.state.project.projectId;
        final restored = rig.store.rows[projectId]!;
        final rebooted = _Rig(
          restore: PwaBootRestore(
            library: [restored],
            active: restored,
            pending: PwaPendingGeneration(
              projectId: projectId,
              idempotencyKey: 'stale-key',
              actionType: 'initial',
              roomId: '',
              roomLabel: '',
              atmosphereId: 'ayden_signature',
              atmosphereLabel: 'Ayden Signature',
              originalStoragePath: restored.originalImageAsset,
              visionNumber: 1,
            ),
          ),
        );
        await pumpEventQueue();
        expect(rebooted.generation.calls, isEmpty);
        expect(rebooted.state.versions, hasLength(1));
        expect(await rebooted.pending.read(), isNull);
      },
    );

    test('GEN46: backend-authored rows deserialize without a client_order', () {
      // Exactly the rows the staging adapter writes: it inserts the vision
      // itself and never sets `client_order`, because it has no client sequence
      // to set. Reading that column as required made every refresh after a real
      // generation open on an empty Home.
      Map<String, dynamic> vision(int n, String? parent) => {
        'id': 'v$n',
        'project_id': 'p1',
        'vision_number': n,
        'parent_vision_id': parent,
        'action_type': n == 1 ? 'initial' : 'refine',
        'atmosphere_id': 'ayden_signature',
        'atmosphere_label': 'Ayden Signature',
        'image_source': 'staging_storage',
        'image_path': 'users/u/projects/p1/generated/v$n.jpg',
        'idempotency_key': 'k$n',
        'schema_version': 1,
        // client_order deliberately ABSENT — the backend does not write it.
      };
      final snap = pwaSnapshotFromRecords(
        project: {
          'id': 'p1',
          'title': 'Open-plan Living Space',
          'status': 'active',
          'room_id': 'living_room',
          'room_label': 'Living Room',
          'selected_atmosphere_id': 'ayden_signature',
          'selected_atmosphere_label': 'Ayden Signature',
          'original_image_path': 'users/u/projects/p1/original/o.jpg',
          'current_vision_id': 'v3',
          'cover_vision_id': 'v3',
          'client_created_order': 1,
          'client_updated_order': 2,
          'schema_version': 1,
        },
        visions: [vision(3, 'v2'), vision(1, null), vision(2, 'v1')],
        messages: const [],
      );
      // Ordered by vision_number, lineage intact, cover resolvable.
      expect(snap.visions.map((v) => v.visionNumber), [1, 2, 3]);
      expect(snap.visions.map((v) => v.order), [1, 2, 3]);
      expect(snap.visions.last.parentVersionId, 'v2');
      expect(snap.coverVision?.versionId, 'v3');
      expect(snap.coverVision!.afterAsset, contains('/generated/v3.jpg'));
      // And they are known to already exist remotely, so no save re-appends them.
      expect(snap.visions.every((v) => v.remotePersisted), isTrue);
    });

    test(
      'GEN47: a pending record REACHES the controller even for a 0-vision project',
      () async {
        // Observed after the 2026-08-06 incident: the failed generation left a
        // project with no vision. pwaResolveBootRestore hides those (Step 6A),
        // so it could never become the active session, the replay guard refused
        // every time, and the paid retry was unreachable from a reloaded tab.
        final store = _FakeStore();
        final failed = PwaProjectSnapshot(
          projectId: 'p-failed',
          title: 'Open-plan Living Space',
          originalImageAsset: 'users/u1/projects/p-failed/original/o1.jpg',
          roomId: null,
          roomLabel: 'Your space',
          selectedAtmosphereId: 'ayden_signature',
          atmosphereLabel: 'Ayden Signature',
          visions: const [],
          messages: const [],
          currentVisionId: null,
          createdOrder: 1,
          updatedOrder: 1,
          updatedLabel: '',
          status: PwaProjectStatus.draft,
        );
        store.rows['p-failed'] = failed;

        final pending = PwaPendingGeneration(
          projectId: 'p-failed',
          idempotencyKey: 'the-original-key',
          actionType: 'initial',
          roomId: '',
          roomLabel: 'Your space',
          atmosphereId: 'ayden_signature',
          atmosphereLabel: 'Ayden Signature',
          originalStoragePath: 'users/u1/projects/p-failed/original/o1.jpg',
          visionNumber: 1,
          startedAtMs: DateTime.now().millisecondsSinceEpoch,
        );

        // The boot the app actually performs: the library hides the row…
        final base = await pwaResolveBootRestore(store);
        expect(base.active, isNull, reason: 'Step 6A hides a 0-vision project');

        // …and folding the pending record in is what makes it reachable.
        final restore = await pwaRestoreWithPending(store, base, pending);
        expect(restore.active?.projectId, 'p-failed');
        expect(restore.pending?.idempotencyKey, 'the-original-key');

        final rig = _Rig(restore: restore);
        await pumpEventQueue();
        expect(rig.generation.calls, hasLength(1));
        expect(rig.generation.calls.single.idempotencyKey, 'the-original-key');
        expect(
          rig.generation.calls.single.originalImagePath,
          'users/u1/projects/p-failed/original/o1.jpg',
          reason: 'the original is reused, never re-uploaded',
        );
        expect(rig.state.versions, hasLength(1));
        expect(rig.state.activeProjectId, 'p-failed');
        expect(await rig.pending.read(), isNull);
      },
    );

    test(
      'GEN48: a pending record naming a vanished project is not replayed',
      () async {
        final store = _FakeStore();
        const orphan = PwaPendingGeneration(
          projectId: 'gone',
          idempotencyKey: 'k',
          actionType: 'initial',
          roomId: '',
          roomLabel: '',
          atmosphereId: 'ayden_signature',
          atmosphereLabel: 'Ayden Signature',
          originalStoragePath: 'users/u1/projects/gone/original/o.jpg',
          visionNumber: 1,
        );
        final base = await pwaResolveBootRestore(store);
        final restore = await pwaRestoreWithPending(store, base, orphan);
        expect(restore.pending, isNull, reason: 'nothing to replay');

        final rig = _Rig(restore: restore);
        await pumpEventQueue();
        expect(rig.generation.calls, isEmpty);
      },
    );

    // ── a settled failure must never re-render by itself ────────────────────
    //
    // Found by the 2026-08-07 real staging smoke. The initial generation failed;
    // the record was kept so Retry could reuse the key — and the boot replay,
    // which cannot tell "unknown" from "already answered", restarted a real
    // ~2-minute paid render on the next page load. Nobody asked for it, and it
    // would have happened again on every reload for as long as the failure did.
    test(
      'GEN70: a failed generation SETTLES the record instead of leaving it live',
      () async {
        final rig = _Rig(
          failure: const PwaGenerationFailure(
            code: 'ENGINE_NO_RESPONSE',
            userMessage: 'nope',
            retryable: true,
          ),
        );
        rig.controller.setSource(_source());
        await rig.controller.generateFirstVision();
        final left = await rig.pending.read();
        expect(left, isNotNull, reason: 'Retry still needs the same key');
        expect(left!.failed, isTrue);
      },
    );

    test('GEN71: a boot with a SETTLED record renders nothing', () async {
      final store = _FakeStore();
      store.rows['p-failed'] = PwaProjectSnapshot(
        projectId: 'p-failed',
        title: 'Open-plan Living Space',
        originalImageAsset: 'users/u1/projects/p-failed/original/o1.jpg',
        roomId: null,
        roomLabel: 'Your space',
        selectedAtmosphereId: 'ayden_signature',
        atmosphereLabel: 'Ayden Signature',
        visions: const [],
        messages: const [],
        currentVisionId: null,
        createdOrder: 1,
        updatedOrder: 1,
        updatedLabel: '',
        status: PwaProjectStatus.draft,
      );
      const settled = PwaPendingGeneration(
        projectId: 'p-failed',
        idempotencyKey: 'the-original-key',
        actionType: 'initial',
        roomId: '',
        roomLabel: 'Your space',
        atmosphereId: 'ayden_signature',
        atmosphereLabel: 'Ayden Signature',
        originalStoragePath: 'users/u1/projects/p-failed/original/o1.jpg',
        visionNumber: 1,
        failed: true,
      );
      final base = await pwaResolveBootRestore(store);
      final restore = await pwaRestoreWithPending(store, base, settled);
      final rig = _Rig(restore: restore);
      await pumpEventQueue();

      expect(
        rig.generation.calls,
        isEmpty,
        reason: 'a reload must not buy a render the user did not ask for',
      );
      expect(rig.state.versions, isEmpty);
      // …but the person is told where they stand, and can act.
      expect(rig.state.generationError, isNotNull);
      expect(rig.state.generationRetryable, isTrue);
      expect(rig.state.generating, isFalse);
    });

    test('GEN72: reloading twice still renders nothing', () async {
      final store = _FakeStore();
      store.rows['p-failed'] = PwaProjectSnapshot(
        projectId: 'p-failed',
        title: 'Open-plan Living Space',
        originalImageAsset: 'users/u1/projects/p-failed/original/o1.jpg',
        roomId: null,
        roomLabel: 'Your space',
        selectedAtmosphereId: 'ayden_signature',
        atmosphereLabel: 'Ayden Signature',
        visions: const [],
        messages: const [],
        currentVisionId: null,
        createdOrder: 1,
        updatedOrder: 1,
        updatedLabel: '',
        status: PwaProjectStatus.draft,
      );
      const settled = PwaPendingGeneration(
        projectId: 'p-failed',
        idempotencyKey: 'k',
        actionType: 'initial',
        roomId: '',
        roomLabel: 'Your space',
        atmosphereId: 'ayden_signature',
        atmosphereLabel: 'Ayden Signature',
        originalStoragePath: 'users/u1/projects/p-failed/original/o1.jpg',
        visionNumber: 1,
        failed: true,
      );
      final base = await pwaResolveBootRestore(store);
      for (var reload = 0; reload < 2; reload++) {
        final restore = await pwaRestoreWithPending(store, base, settled);
        final rig = _Rig(restore: restore);
        await pumpEventQueue();
        expect(rig.generation.calls, isEmpty, reason: 'reload #$reload');
      }
    });

    test(
      'GEN73: Retry — an explicit act — DOES run the settled record again',
      () async {
        final rig = _Rig(
          failure: const PwaGenerationFailure(
            code: 'ENGINE_NO_RESPONSE',
            userMessage: 'nope',
            retryable: true,
          ),
        );
        rig.controller.setSource(_source());
        await rig.controller.generateFirstVision();
        final key = rig.generation.calls.single.idempotencyKey;
        expect((await rig.pending.read())!.failed, isTrue);

        rig.generation.failure = null; // the engine is reachable again
        await rig.controller.retryGeneration();

        expect(rig.generation.calls, hasLength(2));
        expect(
          rig.generation.calls.last.idempotencyKey,
          key,
          reason: 'one operation, one possible charge',
        );
        expect(rig.state.versions, hasLength(1));
        expect(await rig.pending.read(), isNull);
      },
    );

    test('GEN74: a retry in flight is live again, not settled', () async {
      final rig = _Rig(
        failure: const PwaGenerationFailure(
          code: 'ENGINE_NO_RESPONSE',
          userMessage: 'nope',
          retryable: true,
        ),
      );
      rig.controller.setSource(_source());
      await rig.controller.generateFirstVision();
      rig.generation.failure = null;
      await rig.controller.retryGeneration();
      // The record written when the retry STARTED is the one a tab closed
      // mid-render would come back to: it must be replayable, not settled.
      expect(rig.pending.writes.last.failed, isFalse);
    });

    test(
      'GEN75: a settled record does not hijack a project the URL named',
      () async {
        final store = _FakeStore();
        // Where the person actually is: a project with a vision, deep-linked.
        store.rows['p-open'] = PwaProjectSnapshot(
          projectId: 'p-open',
          title: 'Open-plan Living Space',
          originalImageAsset: 'users/u1/projects/p-open/original/o.jpg',
          roomId: null,
          roomLabel: 'Your space',
          selectedAtmosphereId: 'japandi_calm',
          atmosphereLabel: 'Japandi Calm',
          visions: [
            const PwaVision(
              versionId: 'v1',
              projectId: 'p-open',
              visionNumber: 1,
              order: 1,
              title: 'Japandi Calm',
              atmosphereId: 'japandi_calm',
              afterAsset: 'users/u1/projects/p-open/generated/v1.jpg',
              actionType: PwaActionType.signature,
              isCurrent: true,
              remotePersisted: true,
            ),
          ],
          messages: const [],
          currentVisionId: 'v1',
          createdOrder: 1,
          updatedOrder: 1,
          updatedLabel: '',
          status: PwaProjectStatus.active,
        );
        // …and an old failure on a DIFFERENT project, settled long ago.
        store.rows['p-failed'] = PwaProjectSnapshot(
          projectId: 'p-failed',
          title: 'Open-plan Living Space',
          originalImageAsset: 'users/u1/projects/p-failed/original/o.jpg',
          roomId: null,
          roomLabel: 'Your space',
          selectedAtmosphereId: 'ayden_signature',
          atmosphereLabel: 'Ayden Signature',
          visions: const [],
          messages: const [],
          currentVisionId: null,
          createdOrder: 2,
          updatedOrder: 2,
          updatedLabel: '',
          status: PwaProjectStatus.draft,
        );
        const settled = PwaPendingGeneration(
          projectId: 'p-failed',
          idempotencyKey: 'k',
          actionType: 'initial',
          roomId: '',
          roomLabel: 'Your space',
          atmosphereId: 'ayden_signature',
          atmosphereLabel: 'Ayden Signature',
          originalStoragePath: 'users/u1/projects/p-failed/original/o.jpg',
          visionNumber: 1,
          failed: true,
        );

        final base = await pwaResolveBootRestore(store);
        expect(base.active?.projectId, 'p-open');
        final restore = await pwaRestoreWithPending(store, base, settled);
        expect(
          restore.active?.projectId,
          'p-open',
          reason: 'an F5 must land where the URL said, not on an old failure',
        );
        expect(restore.pending, isNull);

        final rig = _Rig(restore: restore);
        await pumpEventQueue();
        expect(rig.generation.calls, isEmpty);
        expect(rig.state.activeProjectId, 'p-open');
      },
    );

    // ── a record too old to be running must not render either ───────────────
    //
    // Reported 2026-08-08: reopening the site started a generation immediately.
    // The record had been left behind by a failure the PREVIOUS EVENING and was
    // written before `failed` existed, so it read as live and the boot bought a
    // fresh ~100 s render nobody asked for. Age is the second half of the
    // answer: a live record is minutes old, never a day.
    test('GEN76: a record older than the replay window is not replayed', () async {
      final store = _FakeStore();
      store.rows['p-old'] = _emptyProject('p-old');
      final stale = PwaPendingGeneration(
        projectId: 'p-old',
        idempotencyKey: 'k',
        actionType: 'initial',
        roomId: '',
        roomLabel: 'Your space',
        atmosphereId: 'ayden_signature',
        atmosphereLabel: 'Ayden Signature',
        originalStoragePath: 'users/u1/projects/p-old/original/o1.jpg',
        visionNumber: 1,
        startedAtMs: DateTime.now()
            .subtract(const Duration(hours: 20))
            .millisecondsSinceEpoch,
      );
      final base = await pwaResolveBootRestore(store);
      final restore = await pwaRestoreWithPending(store, base, stale);
      final rig = _Rig(restore: restore);
      await pumpEventQueue();

      expect(rig.generation.calls, isEmpty);
      expect(rig.state.generationError, isNotNull);
      expect(rig.state.generationRetryable, isTrue);
    });

    test('GEN77: a record with NO timestamp is treated as old', () async {
      // Everything written before this field existed. Indistinguishable from a
      // live one by content — and it is exactly what caused the incident.
      final store = _FakeStore();
      store.rows['p-legacy'] = _emptyProject('p-legacy');
      const legacy = PwaPendingGeneration(
        projectId: 'p-legacy',
        idempotencyKey: 'k',
        actionType: 'initial',
        roomId: '',
        roomLabel: 'Your space',
        atmosphereId: 'ayden_signature',
        atmosphereLabel: 'Ayden Signature',
        originalStoragePath: 'users/u1/projects/p-legacy/original/o1.jpg',
        visionNumber: 1,
      );
      expect(legacy.startedAtMs, 0);
      final base = await pwaResolveBootRestore(store);
      final restore = await pwaRestoreWithPending(store, base, legacy);
      final rig = _Rig(restore: restore);
      await pumpEventQueue();
      expect(rig.generation.calls, isEmpty);
    });

    test('GEN78: a record from a minute ago IS replayed — free, by design', () async {
      final store = _FakeStore();
      store.rows['p-live'] = _emptyProject('p-live');
      final live = PwaPendingGeneration(
        projectId: 'p-live',
        idempotencyKey: 'still-running',
        actionType: 'initial',
        roomId: '',
        roomLabel: 'Your space',
        atmosphereId: 'ayden_signature',
        atmosphereLabel: 'Ayden Signature',
        originalStoragePath: 'users/u1/projects/p-live/original/o1.jpg',
        visionNumber: 1,
        startedAtMs: DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      );
      final base = await pwaResolveBootRestore(store);
      final restore = await pwaRestoreWithPending(store, base, live);
      final rig = _Rig(restore: restore);
      await pumpEventQueue();

      expect(rig.generation.calls, hasLength(1));
      expect(rig.generation.calls.single.idempotencyKey, 'still-running');
      expect(rig.state.versions, hasLength(1));
    });

    test('GEN79: the window is where the backend stops protecting a replay', () {
      // Not a taste: `claim_generation` releases a PROCESSING claim after
      // fifteen minutes, and past that a replay is charged for real.
      expect(PwaPendingGeneration.replayWindow, const Duration(minutes: 15));
      final now = DateTime.now();
      PwaPendingGeneration at(Duration ago) => PwaPendingGeneration(
        projectId: 'p',
        idempotencyKey: 'k',
        actionType: 'initial',
        roomId: '',
        roomLabel: '',
        atmosphereId: 'ayden_signature',
        atmosphereLabel: 'Ayden Signature',
        originalStoragePath: 'users/u1/projects/p/original/o.jpg',
        visionNumber: 1,
        startedAtMs: now.subtract(ago).millisecondsSinceEpoch,
      );
      expect(at(const Duration(minutes: 14)).isReplayableAt(now), isTrue);
      expect(at(const Duration(minutes: 16)).isReplayableAt(now), isFalse);
      // A failure inside the window is still off limits: age is a second gate,
      // never a way around the first.
      expect(at(const Duration(minutes: 1)).asFailed().isReplayableAt(now), isFalse);
      // And a clock that jumped backwards must not resurrect anything.
      expect(at(const Duration(minutes: -5)).isReplayableAt(now), isFalse);
    });

    test('GEN45: a pending record round-trips through its serialization', () {
      const p = PwaPendingGeneration(
        projectId: 'p1',
        idempotencyKey: 'k1',
        actionType: 'refine',
        roomId: 'living_room',
        roomLabel: 'Living Room',
        atmosphereId: 'japandi_calm',
        atmosphereLabel: 'Japandi Calm',
        originalStoragePath: 'users/u/projects/p1/original/o.jpg',
        visionNumber: 3,
        parentVisionId: 'v2',
        userInstruction: 'warmer',
      );
      final back = PwaPendingGeneration.tryParse(p.toJson())!;
      expect(back.projectId, p.projectId);
      expect(back.idempotencyKey, p.idempotencyKey);
      expect(back.actionType, p.actionType);
      expect(back.parentVisionId, 'v2');
      expect(back.userInstruction, 'warmer');
      expect(back.visionNumber, 3);
      expect(back.failed, isFalse);
      expect(PwaPendingGeneration.tryParse(p.asFailed().toJson())!.failed, isTrue);
      expect(p.asFailed().asActive().failed, isFalse);
      expect(p.asFailed().idempotencyKey, p.idempotencyKey);
      // A record we cannot describe is a record we must not replay.
      expect(PwaPendingGeneration.tryParse({'project_id': 'p1'}), isNull);
      expect(PwaPendingGeneration.tryParse('nonsense'), isNull);
    });
  });

  // ── rendering private images ──────────────────────────────────────────────
  group('rendering', () {
    Future<void> pumpStored(
      WidgetTester tester,
      String reference, {
      PwaImageUrlResolver? resolver,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [pwaImageUrlResolverProvider.overrideWithValue(resolver)],
          child: MaterialApp(
            home: SizedBox(
              width: 80,
              height: 80,
              child: PwaStoredImage(
                reference: reference,
                placeholderColor: const Color(0xFF101010),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('GEN50: a bundle asset renders as an asset, unsigned', (
      tester,
    ) async {
      var signed = 0;
      final resolver = PwaImageUrlResolver(
        signer: (p, ttl) async {
          signed++;
          return 'x';
        },
      );
      await pumpStored(
        tester,
        'assets/showcase/apartment_after.jpg',
        resolver: resolver,
      );
      expect(find.byType(Image), findsOneWidget);
      expect(signed, 0);
    });

    testWidgets('GEN51: a Storage path is signed and rendered from network', (
      tester,
    ) async {
      final asked = <String>[];
      final resolver = PwaImageUrlResolver(
        signer: (p, ttl) async {
          asked.add(p);
          return 'https://signed.test/$p';
        },
      );
      const path = 'users/u1/projects/p1/generated/v1.jpg';
      await pumpStored(tester, path, resolver: resolver);
      await tester.pump();
      expect(asked.first, path, reason: 'the durable path is what gets signed');
      // Whatever is on screen is the signed URL — never an AssetImage, at any
      // point in the resolve / re-sign cycle.
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        expect(image.image, isA<NetworkImage>());
        expect((image.image as NetworkImage).url, 'https://signed.test/$path');
      }
    });

    testWidgets('GEN52: with no resolver a Storage path renders NO image', (
      tester,
    ) async {
      await pumpStored(
        tester,
        'users/u1/projects/p1/generated/v1.jpg',
        resolver: null,
      );
      await tester.pump();
      // A placeholder, never a bundled photo of someone else's room.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets(
      'GEN53: a failed load re-signs exactly once and never falls back',
      (tester) async {
        final minted = <String>[];
        final resolver = PwaImageUrlResolver(
          signer: (p, ttl) async {
            minted.add(p);
            return 'https://signed.test/$p#${minted.length}';
          },
        );
        const path = 'users/u1/projects/p1/generated/v1.jpg';
        await pumpStored(tester, path, resolver: resolver);
        await tester.pump();
        // There is no network in a widget test, so the fetch fails for real —
        // which is precisely the expired-signature path. The widget drops the
        // cached URL and re-signs the SAME durable path.
        expect(minted, [path, path]);

        // And then it STOPS: a genuinely missing object must not spin forever.
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(minted, hasLength(2));
        // Never an asset: a room that could not be loaded stays a placeholder.
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          expect(image.image, isA<NetworkImage>());
        }
      },
    );
  });

  // ── static guards ─────────────────────────────────────────────────────────
  group('no fixture can come back', () {
    const runtimeSources = [
      'lib/features/pwa/application/pwa_controller.dart',
      'lib/features/pwa/presentation/pwa_widgets.dart',
      'lib/features/pwa/presentation/pwa_architect_screen.dart',
      'lib/features/pwa/presentation/pwa_home_screen.dart',
      'lib/features/pwa/presentation/pwa_versions_sheet.dart',
      'lib/features/pwa/presentation/pwa_projects_screen.dart',
      'lib/features/pwa/presentation/pwa_reveal_screen.dart',
    ];

    test('GEN60: no runtime path simulates a generation', () {
      for (final path in runtimeSources) {
        expect(
          File(path).readAsStringSync().contains('simulateGeneration('),
          isFalse,
          reason: '$path still simulates a generation',
        );
      }
    });

    test('GEN61: no runtime path promotes an atmosphere asset to a vision', () {
      for (final path in runtimeSources) {
        expect(
          File(path).readAsStringSync().contains('visionAsset'),
          isFalse,
          reason: '$path uses a bundled atmosphere asset as a result',
        );
      }
    });

    test('GEN62: no widget renders a vision with Image.asset', () {
      for (final path in runtimeSources) {
        final src = File(
          path,
        ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
        expect(
          src.contains('Image.asset(vision.afterAsset'),
          isFalse,
          reason: path,
        );
        expect(src.contains('Image.asset(v.afterAsset'), isFalse, reason: path);
        expect(
          src.contains('Image.asset(cover.afterAsset'),
          isFalse,
          reason: path,
        );
      }
    });

    test(
      'GEN63: the only simulateGeneration caller is the offline service',
      () {
        final callers =
            Directory('lib')
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart'))
                .where(
                  (f) => f.readAsStringSync().contains('simulateGeneration('),
                )
                .map((f) => f.path.replaceAll(r'\', '/'))
                .toList()
              ..sort();
        expect(callers, [
          // the declaration…
          'lib/features/pwa/data/mock_pwa_experience_repository.dart',
          // …the interface…
          'lib/features/pwa/data/pwa_experience_repository.dart',
          // …and the one service that is only ever injected offline.
          'lib/features/pwa/data/pwa_mock_generation_service.dart',
        ]);
      },
    );
  });
}
