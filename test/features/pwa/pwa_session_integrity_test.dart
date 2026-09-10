// SESSION / VISION INTEGRITY — a generation belongs to the project that asked.
//
// Staging, 2026-09-10 (Mike Lim, project 440a715e): a switch to Soft Luxury was
// started as Vision 2; the person went to Profile, then Home. The render came
// back into the session on screen by then — a fresh Create whose placeholder
// photo is a showcase condo — and became "Vision 1" of a project nobody made
// (c0ee05e9), while 440a715e kept a spinner that nothing could end: the
// navigation had stored the `loading` bubble as a `generation_status` row.
// Reopening 440a715e from that stale copy and switching again sent an ordinal
// the database already held; the insert was refused, the claim settled
// COMPLETED and a Space charged for a vision that exists nowhere (b7fe1dea),
// and every later switch named that phantom as its parent (PARENT_FORBIDDEN).
//
// These tests drive the controller exactly the way the person did — start a
// render, navigate while it runs, come back — with a service whose renders
// finish only when the test says so.

import 'dart:async';
import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_persistence_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_project_serialization.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_project.dart';
import 'package:flutter_test/flutter_test.dart';

AydenImageSource _photo(int n) => AydenImageSource(
  bytes: Uint8List.fromList([n, n, n]),
  filename: 'room$n.jpg',
  mimeType: 'image/jpeg',
);

class _Open {
  _Open(this.intent, this.completer);
  final PwaGenerationIntent intent;
  final Completer<PwaGeneratedVision> completer;
}

/// A generation service whose renders finish only when the test says so.
class _Gate implements PwaGenerationService {
  /// [idBase] keeps ids unique across two rigs sharing a store (a reload):
  /// the backend's ids are UUIDs and never repeat.
  _Gate({int idBase = 0}) : _made = idBase;

  final List<PwaGenerationIntent> calls = [];
  final List<_Open> open = [];
  final Map<String, PwaGeneratedVision> byKey = {};
  final List<PwaGenerationLifecycle> lifecycle = [];
  int statusCalls = 0;
  int _made;

  /// When set, `chat` waits for it — lets a test navigate mid-turn.
  Completer<PwaChatTurn>? chatGate;

  @override
  Future<PwaGeneratedVision> generate(PwaGenerationIntent intent) {
    calls.add(intent);
    final prior = byKey[intent.idempotencyKey];
    if (prior != null) {
      return Future.value(
        PwaGeneratedVision(
          imagePath: prior.imagePath,
          visionNumber: prior.visionNumber,
          replayed: true,
          backendVisionId: prior.backendVisionId,
        ),
      );
    }
    final c = Completer<PwaGeneratedVision>();
    open.add(_Open(intent, c));
    return c.future;
  }

  /// Finish the oldest open render. [storedAs] is the ordinal the BACKEND
  /// chose; [persisted] false is the "image made, row not written" answer.
  PwaGeneratedVision finishNext({int? storedAs, bool persisted = true}) {
    final o = open.removeAt(0);
    final id = 'srv-${++_made}';
    final v = PwaGeneratedVision(
      imagePath: 'users/u1/projects/${o.intent.projectId}/generated/$id.jpg',
      visionNumber: storedAs ?? o.intent.visionNumber,
      replayed: false,
      backendVisionId: id,
      persisted: persisted,
    );
    byKey[o.intent.idempotencyKey] = v;
    o.completer.complete(v);
    return v;
  }

  void failNext(PwaGenerationFailure f) =>
      open.removeAt(0).completer.completeError(f);

  @override
  Future<PwaGenerationLifecycle> status(String idempotencyKey) async {
    statusCalls++;
    if (lifecycle.isNotEmpty) return lifecycle.removeAt(0);
    final prior = byKey[idempotencyKey];
    return prior == null
        ? const PwaGenerationLifecycle(state: 'UNKNOWN')
        : PwaGenerationLifecycle(state: 'COMPLETED', vision: prior);
  }

  @override
  Future<PwaChatTurn> chat({
    required String projectId,
    required String message,
    String uiLocale = 'en',
    List<Map<String, String>> history = const [],
    String pendingInstruction = '',
  }) async {
    final g = chatGate;
    if (g != null) return g.future;
    return const PwaChatTurn(aiMessage: '', shouldGenerate: true);
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

/// The durable store, as the staging adapter behaves where it matters: the
/// original is uploaded once under ITS project, and every save is kept.
class _Store implements PwaPersistenceRepository {
  final Map<String, PwaProjectSnapshot> rows = {};
  final List<PwaProjectSnapshot> saves = [];
  int uploads = 0;

  /// When set, `prepareGeneration` waits for it — the upload window.
  Completer<void>? prepareGate;

  @override
  Future<PwaOriginalUpload> prepareGeneration(
    PwaProjectSnapshot snapshot, {
    bool replaceOriginal = false,
  }) async {
    final g = prepareGate;
    if (g != null) await g.future;
    final prior = rows[snapshot.projectId]?.originalImageAsset;
    final reusable =
        prior != null &&
        pwaImageSourceForPath(prior) == PwaImageSourceKind.stagingStorage &&
        !replaceOriginal;
    final path = reusable
        ? prior
        : 'users/u1/projects/${snapshot.projectId}/original/o${++uploads}.jpg';
    rows[snapshot.projectId] = snapshot.copyWith(originalImageAsset: path);
    return PwaOriginalUpload.forPath(snapshot.projectId, path);
  }

  @override
  Future<void> saveProject(
    PwaProjectSnapshot project, {
    bool replaceOriginal = false,
  }) async {
    saves.add(project);
    final prior = rows[project.projectId];
    rows[project.projectId] = prior == null
        ? project
        : project.copyWith(originalImageAsset: prior.originalImageAsset);
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
  _Rig({PwaBootRestore? restore, _Store? store, _Gate? gen})
    : store = store ?? _Store(),
      gen = gen ?? _Gate(),
      pending = PwaMemoryPendingGenerationStore(),
      repo = MockPwaExperienceRepository(
        workDelay: Duration.zero,
        seedLibrary: false,
      ) {
    c = PwaController(
      repo,
      generation: this.gen,
      pending: pending,
      persistence: this.store,
      restore: restore,
    );
  }

  final _Store store;
  final _Gate gen;
  final PwaMemoryPendingGenerationStore pending;
  final MockPwaExperienceRepository repo;
  late final PwaController c;

  PwaState get s => c.state;

  /// A new project with its first vision. Returns its id.
  Future<String> project(int photo, {String room = 'bedroom'}) async {
    c.newProject();
    c.setSource(_photo(photo));
    c.selectRoom(room);
    final f = c.generateFirstVision();
    await pumpEventQueue();
    gen.finishNext();
    await f;
    await pumpEventQueue();
    return s.project.projectId;
  }

  /// Start a switch in the open project. The caller pumps the event queue so
  /// the request reaches the engine before it navigates.
  Future<void> startSwitch(String atmosphereId) {
    c.stageAtmosphere(atmosphereId);
    return c.applyAtmosphere();
  }

  PwaProjectSnapshot saved(String id) => repo.openProject(id)!;
}

bool _anyLoading(Iterable<PwaMessage> ms) =>
    ms.any((m) => m.kind == PwaMessageKind.loading);

const _boom = PwaGenerationFailure(
  code: 'ENGINE_REJECTED',
  userMessage: 'nope',
  retryable: true,
);

void main() {
  group('a generation lands in the project that asked for it', () {
    test('LIN01: Profile → Home during a switch — V2 lands in ITS project, '
        'no new session, no new V1', () async {
      final r = _Rig();
      final a = await r.project(1);
      final originalA = r.saved(a).originalImageAsset;
      final v1 = r.saved(a).visions.single;

      final sw = r.startSwitch('soft_luxury');

      await pumpEventQueue();
      expect(r.gen.open, hasLength(1));
      r.c.openProfile();
      r.c.returnToStudio();
      final draft = r.s.project.projectId;
      expect(draft, isNot(a));

      r.gen.finishNext();
      await sw;
      await pumpEventQueue();

      // The session on screen is exactly what it was: an empty Home.
      expect(r.s.project.projectId, draft);
      expect(r.s.versions, isEmpty, reason: 'no "Vision 1" in a new session');
      expect(r.s.generating, isFalse);
      // The project that asked has its Vision 2.
      final got = r.saved(a);
      expect(got.visions, hasLength(2));
      final v2 = got.visions.last;
      expect(v2.visionNumber, 2);
      expect(v2.parentVersionId, v1.versionId);
      expect(v2.atmosphereId, 'soft_luxury');
      expect(v2.projectId, a);
      expect(got.currentVisionId, v2.versionId);
      expect(got.originalImageAsset, originalA, reason: 'its own photo');
      expect(_anyLoading(got.messages), isFalse, reason: 'no zombie spinner');
      expect(
        got.messages.where((m) => m.visionId == v2.versionId),
        hasLength(1),
        reason: 'one reveal for one vision',
      );
      // …durably, and nowhere else.
      expect(r.store.rows[a]!.visions, hasLength(2));
      expect(r.store.rows.containsKey(draft), isFalse,
          reason: 'the fresh Create never became a project');
      expect(r.s.library.map((p) => p.projectId), [a]);
      expect(await r.pending.read(), isNull);
    });

    test('LIN02: opening ANOTHER project mid-render leaves it untouched', () async {
      final r = _Rig();
      final a = await r.project(1);
      final b = await r.project(2);
      final bOriginal = r.saved(b).originalImageAsset;
      await r.c.openProject(a);
      final sw = r.startSwitch('japandi_calm');
      await pumpEventQueue();
      await r.c.openProject(b);
      final bMessages = r.s.messages.length;

      r.gen.finishNext();
      await sw;
      await pumpEventQueue();

      expect(r.s.project.projectId, b);
      expect(r.s.versions, hasLength(1));
      expect(r.s.messages, hasLength(bMessages));
      expect(r.s.project.originalAsset, bOriginal);
      expect(r.saved(b).visions, hasLength(1));
      expect(r.saved(a).visions, hasLength(2));
      expect(r.saved(a).visions.last.atmosphereId, 'japandi_calm');
    });

    test('LIN03: coming back while it renders shows ITS wait, then its result',
        () async {
      final r = _Rig();
      final a = await r.project(1);
      final sw = r.startSwitch('soft_luxury');
      await pumpEventQueue();
      final loadingId = r.s.messages.last.id;
      r.c.returnToStudio();
      await r.c.openProject(a);

      expect(r.s.project.projectId, a);
      expect(r.s.generating, isTrue, reason: 'still rendering');
      expect(r.s.messages.last.id, loadingId, reason: 'the same bubble');
      expect(r.s.messages.last.workingKind, PwaWorkKind.switchAtmosphere);
      expect(
        r.s.messages.where((m) => m.role == PwaRole.user),
        hasLength(1),
        reason: 'the request, once',
      );
      // Nothing can start a second render underneath it.
      r.c.stageAtmosphere('japandi_calm');
      await r.c.applyAtmosphere();
      expect(r.gen.calls, hasLength(2), reason: 'V1 + this switch, no third');

      r.gen.finishNext();
      await sw;
      await pumpEventQueue();
      expect(r.s.generating, isFalse);
      expect(r.s.versions, hasLength(2));
      expect(_anyLoading(r.s.messages), isFalse);
      expect(r.s.messages.last.visionId, r.s.versions.last.versionId);
    });

    test('LIN04: the upload window — navigating before the photo is prepared '
        'still sends THIS project and THIS photo', () async {
      final r = _Rig();
      final a = await r.project(1);
      final b = await r.project(2);
      final aPath = r.saved(a).originalImageAsset;
      final bPath = r.saved(b).originalImageAsset;
      await r.c.openProject(a);
      r.store.prepareGate = Completer<void>();
      r.c.stageAtmosphere('soft_luxury');
      final sw = r.c.applyAtmosphere();
      await pumpEventQueue();
      await r.c.openProject(b);
      r.store.prepareGate!.complete();
      r.store.prepareGate = null;
      await pumpEventQueue();

      final sent = r.gen.calls.last;
      expect(sent.projectId, a);
      expect(sent.originalImagePath, aPath);
      expect(r.s.project.projectId, b);
      expect(r.s.project.originalAsset, bPath,
          reason: "B never shows A's photo");
      r.gen.finishNext();
      await sw;
      await pumpEventQueue();
      expect(r.saved(a).visions, hasLength(2));
      expect(r.s.project.originalAsset, bPath);
    });

    test('LIN05: a FIRST vision that finishes after the person left becomes '
        'its own project, with its own photo', () async {
      final r = _Rig();
      r.c.setSource(_photo(7));
      final f = r.c.generateFirstVision();
      await pumpEventQueue();
      final owner = r.gen.calls.single.projectId;
      r.c.returnToStudio();
      final home = r.s.project.projectId;
      r.gen.finishNext();
      await f;
      await pumpEventQueue();

      expect(r.s.project.projectId, home);
      expect(r.s.versions, isEmpty);
      final got = r.saved(owner);
      expect(got.visions, hasLength(1));
      expect(got.visions.single.visionNumber, 1);
      expect(pwaImageSourceForPath(got.originalImageAsset),
          PwaImageSourceKind.stagingStorage,
          reason: 'the uploaded photo, never a bundle placeholder');
      expect(got.originalImageAsset, contains('/projects/$owner/original/'));
      expect(r.store.rows[owner]!.visions, hasLength(1));
      expect(r.s.library.map((p) => p.projectId), [owner]);
    });
  });

  group('exactly one terminal state, surfaced where it happened', () {
    test('LIN06: a failure while elsewhere is shown in ITS project, not here',
        () async {
      final r = _Rig();
      final a = await r.project(1);
      final b = await r.project(2);
      await r.c.openProject(a);
      final sw = r.startSwitch('soft_luxury');
      await pumpEventQueue();
      final key = r.gen.calls.last.idempotencyKey;
      await r.c.openProject(b);
      r.gen.failNext(_boom);
      await sw;
      await pumpEventQueue();

      expect(r.s.generationError, isNull, reason: 'not B\'s failure');
      final rec = await r.pending.read();
      expect(rec?.idempotencyKey, key);
      expect(rec?.failed, isTrue, reason: 'settled, kept for Retry');

      await r.c.openProject(a);
      expect(r.s.generationErrorCode, 'ENGINE_REJECTED');
      expect(r.s.generationRetryable, isTrue);
      expect(r.s.generating, isFalse);
      expect(_anyLoading(r.s.messages), isFalse, reason: 'no zombie spinner');
      expect(r.s.versions, hasLength(1), reason: 'nothing invented');

      // Retry is the same operation — same key, one vision.
      final retry = r.c.retryGeneration();
      await pumpEventQueue();
      expect(r.gen.calls.last.idempotencyKey, key);
      r.gen.finishNext();
      await retry;
      expect(r.s.versions, hasLength(2));
      expect(await r.pending.read(), isNull);
    });

    test('LIN07: deleting the project while it renders does not bring it back',
        () async {
      final r = _Rig();
      final a = await r.project(1);
      final sw = r.startSwitch('soft_luxury');
      await pumpEventQueue();
      r.c.returnToStudio();
      r.c.deleteProject(a);
      await pumpEventQueue();
      r.gen.finishNext();
      await sw;
      await pumpEventQueue();
      expect(r.repo.openProject(a), isNull);
      expect(r.store.rows.containsKey(a), isFalse);
      expect(r.s.library, isEmpty);
    });

    test('LIN08: a chat turn answered after the person left never renders '
        'in the project they moved to', () async {
      final r = _Rig();
      final a = await r.project(1);
      final b = await r.project(2);
      await r.c.openProject(a);
      r.gen.chatGate = Completer<PwaChatTurn>();
      r.c.sendUserText('make it warmer');
      await pumpEventQueue();
      await r.c.openProject(b);
      r.gen.chatGate!.complete(
        const PwaChatTurn(aiMessage: '', shouldGenerate: true),
      );
      await pumpEventQueue();
      expect(r.gen.calls, hasLength(2), reason: 'the two first visions only');
      expect(r.s.project.projectId, b);
      expect(r.s.generating, isFalse);
      expect(r.s.versions, hasLength(1));
    });
  });

  group('the backend owns the ordinal', () {
    test('LIN09: the stored number is the one shown', () async {
      final r = _Rig();
      await r.project(1);
      final sw = r.startSwitch('soft_luxury');
      await pumpEventQueue();
      expect(r.gen.calls.last.visionNumber, 2, reason: 'what is asked');
      r.gen.finishNext(storedAs: 3);
      await sw;
      expect(r.s.versions.last.visionNumber, 3, reason: 'what is stored');
    });

    test('LIN10: the number asked is one past the highest, never the count',
        () async {
      final r = _Rig();
      await r.project(1);
      var sw = r.startSwitch('soft_luxury');
      await pumpEventQueue();
      r.gen.finishNext(storedAs: 4); // e.g. 2 and 3 landed elsewhere
      await sw;
      sw = r.startSwitch('japandi_calm');
      await pumpEventQueue();
      expect(r.gen.calls.last.visionNumber, 5);
      r.gen.finishNext();
      await sw;
    });

    test('LIN11: an image whose row the backend could not write is the '
        "CLIENT's to store — never a phantom", () async {
      final r = _Rig();
      await r.project(1);
      final sw = r.startSwitch('soft_luxury');
      await pumpEventQueue();
      r.gen.finishNext(persisted: false);
      await sw;
      expect(r.s.versions.last.remotePersisted, isFalse);
      expect(r.s.versions.first.remotePersisted, isTrue);
    });
  });

  group('idempotency: one selection is one request', () {
    test('LIN12: rapid taps start ONE switch', () async {
      final r = _Rig();
      await r.project(1);
      r.c.stageAtmosphere('soft_luxury');
      final f1 = r.c.applyAtmosphere();
      final f2 = r.c.applyAtmosphere();
      final f3 = r.c.applyAtmosphere();
      await pumpEventQueue();
      expect(r.gen.calls, hasLength(2), reason: 'V1 + one switch');
      r.gen.finishNext();
      await Future.wait([f1, f2, f3]);
      expect(r.s.versions, hasLength(2));
      expect(r.s.messages.where((m) => m.role == PwaRole.user), hasLength(1));
    });

    test('LIN13: a key is one intent — a retry reuses it, a different choice '
        'never does', () async {
      final r = _Rig();
      await r.project(1);
      var sw = r.startSwitch('soft_luxury');
      await pumpEventQueue();
      final k1 = r.gen.calls.last.idempotencyKey;
      r.gen.failNext(_boom);
      await sw;

      sw = r.startSwitch('soft_luxury');

      await pumpEventQueue();
      expect(r.gen.calls.last.idempotencyKey, k1, reason: 'same intent');
      r.gen.failNext(_boom);
      await sw;

      sw = r.startSwitch('japandi_calm');

      await pumpEventQueue();
      expect(r.gen.calls.last.idempotencyKey, isNot(k1),
          reason: 'a different choice is a different operation');
      r.gen.finishNext();
      await sw;
      expect(r.s.versions.last.atmosphereId, 'japandi_calm');
    });

    test('LIN14: one render at a time — a second project waits its turn',
        () async {
      final r = _Rig();
      final a = await r.project(1);
      final b = await r.project(2);
      await r.c.openProject(a);
      final sw = r.startSwitch('soft_luxury');
      await pumpEventQueue();
      await r.c.openProject(b);
      r.c.stageAtmosphere('japandi_calm');
      await r.c.applyAtmosphere();
      expect(r.gen.calls, hasLength(3), reason: 'no second render in B');
      expect(r.s.generationErrorCode, 'BUSY_ELSEWHERE');
      expect(r.s.generating, isFalse);
      expect(r.s.versions, hasLength(1));

      // …and a Create waits too, before it even opens a session.
      r.c.newProject();
      r.c.setSource(_photo(9));
      await r.c.generateFirstVision();
      expect(r.gen.calls, hasLength(3));
      expect(r.s.phase, PwaPhase.entry);
      expect(r.s.generationErrorCode, 'BUSY_ELSEWHERE');

      r.gen.finishNext();
      await sw;
      await r.c.openProject(b);
      final sw2 = r.startSwitch('japandi_calm');
      await pumpEventQueue();
      expect(r.gen.calls, hasLength(4), reason: 'free again');
      r.gen.finishNext();
      await sw2;
      expect(r.saved(b).visions, hasLength(2));
    });
  });

  group('V1 → V5 in one session', () {
    test('LIN15: sequential ordinals, a clean lineage, one job each', () async {
      final r = _Rig();
      final a = await r.project(1);
      const atmos = ['soft_luxury', 'japandi_calm', 'nordic_warmth', 'warm_modern'];
      for (final atmo in atmos) {
        final parent = r.s.currentVisionId;
        final sw = r.startSwitch(atmo);
        await pumpEventQueue();
        expect(r.gen.open, hasLength(1));
        r.gen.finishNext();
        await sw;
        await pumpEventQueue();
        expect(r.s.versions.last.parentVersionId, parent);
        expect(r.s.versions.last.atmosphereId, atmo);
        expect(await r.pending.read(), isNull);
      }
      expect(r.s.project.projectId, a);
      expect(r.s.versions.map((v) => v.visionNumber), [1, 2, 3, 4, 5]);
      expect(r.gen.calls, hasLength(5));
      expect(r.gen.calls.map((c) => c.idempotencyKey).toSet(), hasLength(5));
      expect(r.gen.calls.map((c) => c.projectId).toSet(), {a});
      expect(_anyLoading(r.s.messages), isFalse);
      expect(r.s.library, hasLength(1));
      expect(r.store.rows[a]!.visions, hasLength(5));
    });
  });

  group('cross-session integrity: A, B, C', () {
    test('LIN16: navigation and a reload never mix originals, ids or ordinals',
        () async {
      final r = _Rig();
      final a = await r.project(1, room: 'bedroom');
      final b = await r.project(2, room: 'livingRoom');
      final c = await r.project(3, room: 'kitchen');
      final originals = {
        for (final id in [a, b, c]) id: r.saved(id).originalImageAsset,
      };
      expect(originals.values.toSet(), hasLength(3));

      await r.c.openProject(a);
      final sw = r.startSwitch('soft_luxury');
      await pumpEventQueue();
      await r.c.openProject(b);
      expect(r.s.project.originalAsset, originals[b]);
      await r.c.openProject(c);
      expect(r.s.project.originalAsset, originals[c]);
      r.c.returnToStudio();
      await r.c.openProject(a);
      expect(r.s.generating, isTrue);
      expect(r.s.project.originalAsset, originals[a]);
      await r.c.openProject(b);
      r.gen.finishNext();
      await sw;
      await pumpEventQueue();

      void checkAll(String when, Map<String, PwaProjectSnapshot> by) {
        expect(by.keys.toSet(), {a, b, c}, reason: '$when: no extra project');
        for (final id in [a, b, c]) {
          expect(by[id]!.originalImageAsset, originals[id], reason: when);
          expect(by[id]!.visions.every((v) => v.projectId == id), isTrue,
              reason: '$when: every vision is its project\'s');
          expect(_anyLoading(by[id]!.messages), isFalse, reason: when);
        }
        expect(by[a]!.visions.map((v) => v.visionNumber), [1, 2]);
        expect(by[b]!.visions, hasLength(1));
        expect(by[c]!.visions, hasLength(1));
        final ids = [for (final p in by.values) ...p.visions.map((v) => v.versionId)];
        expect(ids.toSet(), hasLength(ids.length), reason: '$when: unique ids');
      }

      checkAll('in memory', {for (final p in r.s.library) p.projectId: p});
      checkAll('durable', r.store.rows);

      // A reload, from the durable rows alone.
      final restore = await pwaResolveBootRestore(r.store);
      final again = _Rig(restore: restore, store: r.store);
      await pumpEventQueue();
      checkAll('after reload', {for (final p in again.s.library) p.projectId: p});
    });
  });

  group('a restore reconciles by asking, never by guessing', () {
    PwaPendingGeneration record(String projectId, {int ageMinutes = 1}) =>
        PwaPendingGeneration(
          projectId: projectId,
          idempotencyKey: 'k-restore',
          actionType: 'switch_atmosphere',
          roomId: 'bedroom',
          roomLabel: 'Bedroom',
          atmosphereId: 'soft_luxury',
          atmosphereLabel: 'Soft Luxury',
          originalStoragePath: 'users/u1/projects/$projectId/original/o1.jpg',
          visionNumber: 2,
          parentVisionId: 'srv-1',
          startedAtMs: DateTime.now()
              .subtract(Duration(minutes: ageMinutes))
              .millisecondsSinceEpoch,
        );

    Future<(_Rig, String)> reboot(
      PwaGenerationLifecycle? answer, {
      int ageMinutes = 1,
      List<PwaGenerationLifecycle> then = const [],
    }) async {
      final first = _Rig();
      final a = await first.project(1);
      final gen = _Gate(idBase: 100);
      if (answer != null) gen.lifecycle.add(answer);
      gen.lifecycle.addAll(then);
      final restore = await pwaRestoreWithPending(
        first.store,
        await pwaResolveBootRestore(first.store),
        record(a, ageMinutes: ageMinutes),
      );
      final r = _Rig(restore: restore, store: first.store, gen: gen);
      return (r, a);
    }

    const done = PwaGeneratedVision(
      imagePath: 'users/u1/projects/x/generated/made-while-away.jpg',
      visionNumber: 2,
      replayed: true,
      backendVisionId: 'made-while-away',
    );

    test('LIN17: COMPLETED while the page was gone → adopted, no request',
        () async {
      final (r, a) = await reboot(
        // Even an OLD record: the backend says it finished, so it did.
        const PwaGenerationLifecycle(state: 'COMPLETED', vision: done),
        ageMinutes: 60,
      );
      await pumpEventQueue();
      expect(r.gen.calls, isEmpty, reason: 'nothing re-sent, nothing charged');
      expect(r.s.project.projectId, a);
      expect(r.s.versions.map((v) => v.versionId), ['srv-1', 'made-while-away']);
      expect(r.s.generationError, isNull,
          reason: 'a vision that was made is never reported lost');
      expect(r.s.generating, isFalse);
    });

    test('LIN18: still PROCESSING → waited for, never re-POSTed', () async {
      final (r, _) = await reboot(
        const PwaGenerationLifecycle(state: 'PROCESSING'),
        then: const [PwaGenerationLifecycle(state: 'COMPLETED', vision: done)],
      );
      await pumpEventQueue();
      expect(r.s.generating, isTrue);
      expect(_anyLoading(r.s.messages), isTrue);
      await Future<void>.delayed(const Duration(seconds: 4));
      await pumpEventQueue();
      expect(r.gen.calls, isEmpty);
      expect(r.s.versions.last.versionId, 'made-while-away');
      expect(r.s.generating, isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('LIN19: FAILED → said, with Retry — never re-run on its own', () async {
      final (r, _) = await reboot(
        const PwaGenerationLifecycle(state: 'FAILED', errorCode: 'ENGINE_REJECTED'),
      );
      await pumpEventQueue();
      expect(r.gen.calls, isEmpty, reason: 'no render nobody asked for');
      expect(r.s.generationErrorCode, 'ENGINE_REJECTED');
      expect(r.s.generationRetryable, isTrue);
      expect(r.s.versions, hasLength(1));
    });

    test('LIN20: UNKNOWN and recent → the person\'s own request is sent, once',
        () async {
      final (r, _) = await reboot(null);
      await pumpEventQueue();
      expect(r.gen.calls, hasLength(1));
      expect(r.gen.calls.single.idempotencyKey, 'k-restore');
      r.gen.finishNext();
      await pumpEventQueue();
      expect(r.s.versions, hasLength(2));
    });
  });

  group('durable hygiene', () {
    test('LIN21: a navigation mid-render never stores the loading bubble',
        () async {
      final r = _Rig();
      final a = await r.project(1);
      final sw = r.startSwitch('soft_luxury');
      await pumpEventQueue();
      r.c.openProfile();
      r.c.openLibrary();
      await pumpEventQueue();
      expect(r.store.saves.where((s) => s.projectId == a).every(
            (s) => !_anyLoading(s.messages),
          ), isTrue);
      expect(_anyLoading(r.saved(a).messages), isFalse);
      // The request itself IS kept: it is what the person did.
      expect(
        r.saved(a).messages.where((m) => m.role == PwaRole.user),
        hasLength(1),
      );
      r.gen.finishNext();
      await sw;
    });

    test('LIN22: records never carry a loading bubble; a stored one is never '
        'restored', () {
      final snap = PwaProjectSnapshot(
        projectId: 'p',
        title: 'T',
        originalImageAsset: 'users/u/projects/p/original/o.jpg',
        roomId: null,
        roomLabel: 'Your space',
        selectedAtmosphereId: 'ayden_signature',
        atmosphereLabel: 'Ayden Signature',
        visions: const [],
        messages: const [
          PwaMessage(id: 'm1', role: PwaRole.ayden, kind: PwaMessageKind.text, text: 'a'),
          PwaMessage(id: 'z', role: PwaRole.ayden, kind: PwaMessageKind.loading),
          PwaMessage(id: 'm2', role: PwaRole.user, kind: PwaMessageKind.text, text: 'b'),
        ],
        currentVisionId: null,
        createdOrder: 1,
        updatedOrder: 1,
        updatedLabel: '',
        status: PwaProjectStatus.draft,
      );
      final rec = pwaRecordsFromSnapshot(snap, installationId: 'i');
      expect(rec.messages.map((m) => m['id']), ['m1', 'm2']);
      expect(rec.messages.map((m) => m['client_order']), [0, 1]);

      Map<String, dynamic> row(String id, String type, int order) => {
        'id': id,
        'project_id': 'p',
        'role': 'assistant',
        'message_type': type,
        'text_content': 'x',
        'client_order': order,
        'schema_version': 1,
      };
      final back = pwaSnapshotFromRecords(
        project: {
          'id': 'p',
          'title': 'T',
          'status': 'active',
          'room_id': 'living_room',
          'room_label': 'Living Room',
          'selected_atmosphere_id': 'ayden_signature',
          'selected_atmosphere_label': 'Ayden Signature',
          'original_image_path': 'users/u/projects/p/original/o.jpg',
          'client_created_order': 1,
          'client_updated_order': 1,
          'schema_version': 1,
        },
        visions: const [],
        messages: [
          row('a', 'text', 0),
          row('zombie', 'generation_status', 1),
          row('b', 'text', 2),
        ],
      );
      expect(back.messages.map((m) => m.id), ['a', 'b']);
      expect(_anyLoading(back.messages), isFalse);
    });

    test('LIN23: a stored message keeps its order; new ones go after all '
        'stored, legacy spinner rows included', () {
      final out = pwaWithStableClientOrder(
        [
          {'id': 'm1', 'client_order': 0},
          {'id': 'm2', 'client_order': 1},
          {'id': 'm3', 'client_order': 2},
          {'id': 'm4', 'client_order': 3},
        ],
        [
          {'id': 'm1', 'client_order': 0},
          {'id': 'zombie', 'client_order': 2},
          {'id': 'm2', 'client_order': 1},
        ],
      );
      expect(out.map((r) => r['client_order']), [0, 1, 3, 4]);
    });
  });
}
