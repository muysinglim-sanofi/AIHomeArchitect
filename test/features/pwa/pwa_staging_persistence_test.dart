// Phase D — staging persistence wiring + the four targeted corrections.
// Verified WITHOUT a live backend: a stateful in-memory fake stands in for the
// Supabase adapter, and the idempotency logic + session decision are pure and
// unit-tested directly. Deterministic, zero-delay, no network.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_route.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_persistence_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_project_serialization.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_repository_error.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_staging_supabase_client.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

AydenImageSource _fakeSource() => AydenImageSource(
  bytes: Uint8List.fromList(const [1, 2, 3]),
  filename: 'room.jpg',
  mimeType: 'image/jpeg',
);

/// A fresh source with DISTINCT content — a NEW object each call, so the
/// controller's identity-based change detection sees a genuine replacement.
AydenImageSource _srcOf(List<int> bytes) => AydenImageSource(
  bytes: Uint8List.fromList(bytes),
  filename: 'p.jpg',
  mimeType: 'image/jpeg',
);

/// A durably-persisted GENERATED project (one Vision) whose original bytes [a]
/// live in Storage. Returns its id. Used to reproduce the card-open Before pane.
Future<String> _genPersisted(_FakePersistence fake, List<int> a) async {
  final c = _controller(persistence: fake);
  await pumpEventQueue();
  c.selectRoom('living_room');
  c.setSource(_srcOf(a));
  await c.generateFirstVision();
  await pumpEventQueue();
  return c.state.project.projectId;
}

/// A LEGACY zero-Vision row (from the former upload-time behaviour), injected
/// directly into the backend to prove Step 6A hides/normalizes it safely.
PwaProjectSnapshot _legacyDraftRow(String id) => PwaProjectSnapshot(
  projectId: id,
  title: 'Legacy',
  originalImageAsset: 'users/test/projects/$id/original/o.jpg',
  roomId: 'living_room',
  roomLabel: 'Living Room',
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

/// Stateful in-memory backend standing in for the Supabase adapter. Stores full
/// snapshots by id (like the real rows), records every call in order, and can be
/// told to fail the next saveProject to exercise the error path.
class _FakePersistence implements PwaPersistenceRepository {
  final Map<String, PwaProjectSnapshot> store = {};
  final Map<String, Uint8List> storageBytes = {}; // projectId → original bytes
  final List<String> calls = [];
  bool failNextSave = false;

  /// Step 5 — fail the NEXT original upload (a replace) BEFORE the row is
  /// touched, to prove the old durable path/bytes stay authoritative (§6/§8).
  bool failNextUpload = false;
  int uploads = 0; // count of original uploads (first + each replacement)
  int _objSeq = 0;

  /// If set, the NEXT saveProject blocks on this until the test completes it —
  /// lets a test prove Generate AWAITS the pending replacement save (§5/§7).
  Completer<void>? gateNextSave;

  /// If set, the NEXT loadOriginalBytes blocks on this — lets a test prove card
  /// open AWAITS hydration before settling Architect (BEFORECARD05).
  Completer<void>? gateNextLoad;

  @override
  Future<PwaInstallationIdentity> ensureInstallation() async {
    calls.add('ensureInstallation');
    return const PwaInstallationIdentity('inst-test');
  }

  @override
  Future<void> healthCheck() async => calls.add('healthCheck');

  /// Rows-only view: round-trip through records so the returned snapshot carries
  /// NO original bytes — exactly like the deployed adapter (bytes live in Storage
  /// and are fetched on demand via loadOriginalBytes, never on the row).
  PwaProjectSnapshot _row(PwaProjectSnapshot s) {
    final rec = pwaRecordsFromSnapshot(s, installationId: 'inst-test');
    return pwaSnapshotFromRecords(
      project: rec.project,
      visions: rec.visions,
      messages: rec.messages,
    );
  }

  @override
  Future<List<PwaProjectSnapshot>> loadLibrary() async {
    calls.add('loadLibrary');
    return store.values.map(_row).toList();
  }

  @override
  Future<PwaProjectSnapshot?> loadProject(String projectId) async {
    calls.add('loadProject:$projectId');
    final s = store[projectId];
    return s == null ? null : _row(s);
  }

  // NOT NULL columns in the deployed 0002 schema. Enforced below so a
  // serialization regression (e.g. a null room_id) FAILS here like the real DB.
  static const _notNullCols = [
    'title',
    'status',
    'room_id',
    'room_label',
    'selected_atmosphere_id',
    'selected_atmosphere_label',
  ];

  @override
  Future<void> saveProject(
    PwaProjectSnapshot project, {
    bool replaceOriginal = false,
  }) async {
    calls.add('saveProject:${project.projectId}');
    final gate = gateNextSave;
    if (gate != null) {
      gateNextSave = null;
      await gate.future; // block until the test releases this save
    }
    if (failNextSave) {
      failNextSave = false;
      throw const PwaRepositoryError(PwaErrorKind.network, 'boom');
    }
    // Round-trip through the REAL serialization + enforce the schema's NOT NULL
    // columns, so this fake rejects exactly what the deployed adapter would.
    final rec = pwaRecordsFromSnapshot(project, installationId: 'inst-test');
    for (final col in _notNullCols) {
      if (rec.project[col] == null) {
        throw PwaRepositoryError(
          PwaErrorKind.validation,
          'NOT NULL violation on "$col" (deployed schema forbids it).',
        );
      }
    }
    store[project.projectId] = _withStorage(project, replaceOriginal);
  }

  /// Mirror the deployed adapter's Storage behaviour: the FIRST save with bytes,
  /// or an explicit [replaceOriginal], uploads to a NEW collision-free owned path
  /// FIRST (throwing before the row write if the upload fails), then points the
  /// row at it; any other save keeps the existing immutable path.
  PwaProjectSnapshot _withStorage(PwaProjectSnapshot p, bool replaceOriginal) {
    final isNew = !store.containsKey(p.projectId);
    if (p.source != null && (isNew || replaceOriginal)) {
      if (failNextUpload) {
        failNextUpload = false;
        // Upload failed → row untouched: prior path/bytes stay authoritative.
        throw const PwaRepositoryError(PwaErrorKind.network, 'upload boom');
      }
      uploads++;
      storageBytes[p.projectId] = p.source!.bytes; // new authoritative bytes
      final obj = isNew ? 'o' : 'r${++_objSeq}';
      return p.copyWith(
        originalImageAsset:
            'users/test/projects/${p.projectId}/original/$obj.jpg',
      );
    }
    final prior = store[p.projectId];
    return prior != null
        ? p.copyWith(originalImageAsset: prior.originalImageAsset)
        : p;
  }

  @override
  Future<void> appendVision(String projectId, PwaVision vision) async =>
      calls.add('appendVision');

  @override
  Future<void> appendMessage(String projectId, PwaMessage message) async =>
      calls.add('appendMessage');

  @override
  Future<void> updateCurrentVision(String projectId, String visionId) async =>
      calls.add('updateCurrentVision');

  @override
  Future<void> updateCoverVision(String projectId, String visionId) async =>
      calls.add('updateCoverVision');

  @override
  Future<void> renameProject(String projectId, String title) async {
    calls.add('renameProject:$projectId:$title');
    final s = store[projectId];
    if (s == null) {
      throw PwaRepositoryError.notFound('Project "$projectId" not found.');
    }
    store[projectId] = s.copyWith(title: title);
  }

  @override
  Future<PwaProjectSnapshot> duplicateProject(String projectId) async {
    calls.add('duplicateProject:$projectId');
    final src = store[projectId];
    if (src == null) {
      throw const PwaRepositoryError.notFound('no source');
    }
    // Server-side deep copy: the RPC mints the authoritative UUID.
    final newId = const Uuid().v4();
    final copy = PwaProjectSnapshot(
      projectId: newId,
      title: '${src.title} Copy',
      originalImageAsset: src.originalImageAsset,
      roomId: src.roomId,
      roomLabel: src.roomLabel,
      selectedAtmosphereId: src.selectedAtmosphereId,
      atmosphereLabel: src.atmosphereLabel,
      visions: src.visions,
      messages: src.messages,
      currentVisionId: src.currentVisionId,
      coverVisionId: src.coverVisionId,
      createdOrder: src.createdOrder,
      updatedOrder: src.updatedOrder,
      updatedLabel: src.updatedLabel,
      status: src.status,
      source: src.source,
    );
    store[newId] = copy;
    return copy;
  }

  @override
  Future<void> softDeleteProject(String projectId) async {
    calls.add('softDeleteProject:$projectId');
    store.remove(projectId);
  }

  @override
  Future<Uint8List?> loadOriginalBytes(PwaProjectSnapshot snapshot) async {
    calls.add('loadOriginalBytes:${snapshot.projectId}');
    final gate = gateNextLoad;
    if (gate != null) {
      gateNextLoad = null;
      await gate.future; // block until the test releases hydration
    }
    if (pwaImageSourceForPath(snapshot.originalImageAsset) ==
        PwaImageSourceKind.bundle) {
      return null; // a bundle asset has no Storage object
    }
    return storageBytes[snapshot.projectId];
  }
}

PwaController _controller({PwaPersistenceRepository? persistence}) =>
    PwaController(
      MockPwaExperienceRepository(workDelay: Duration.zero),
      persistence: persistence,
    );

/// Reproduce the FULL staging boot: run the real [pwaResolveBootRestore] against
/// the fake, then construct the controller with that restore — exactly what
/// `main._bootPwaStaging` does. This is the boot the routing tests exercise.
Future<PwaController> _boot(_FakePersistence fake) async {
  final restore = await pwaResolveBootRestore(fake);
  return PwaController(
    // Staging uses a NON-seeding repo — the library is durable-only.
    MockPwaExperienceRepository(workDelay: Duration.zero, seedLibrary: false),
    persistence: fake,
    restore: restore,
  );
}

/// Same as [_boot] but boots FROM a durable URL route — exactly what
/// `main._bootPwaStaging` does when the browser opens a deep link / after F5.
Future<PwaController> _bootRoute(_FakePersistence fake, PwaRoute route) async {
  final restore = await pwaResolveBootRestore(fake, route: route);
  return PwaController(
    MockPwaExperienceRepository(workDelay: Duration.zero, seedLibrary: false),
    persistence: fake,
    restore: restore,
  );
}

/// A durable ACTIVE project (one Vision) with an explicit updatedOrder, so a test
/// can make one project "most-recent" and prove the URL still wins.
PwaProjectSnapshot _activeSnap(String id, int order) => PwaProjectSnapshot(
  projectId: id,
  title: 'P-$id',
  originalImageAsset: 'users/t/$id/original/o.jpg',
  roomId: 'living_room',
  roomLabel: 'Living Room',
  selectedAtmosphereId: 'ayden_signature',
  atmosphereLabel: 'Ayden Signature',
  visions: [
    PwaVision(
      versionId: '$id-v1',
      projectId: id,
      visionNumber: 1,
      title: 'v1',
      atmosphereId: 'ayden_signature',
      actionType: PwaActionType.signature,
      afterAsset: 'assets/x.jpg',
      order: 1,
    ),
  ],
  messages: const [],
  currentVisionId: '$id-v1',
  createdOrder: order,
  updatedOrder: order,
  updatedLabel: '',
  status: PwaProjectStatus.active,
);

Future<PwaController> _generated({
  PwaPersistenceRepository? persistence,
}) async {
  final c = _controller(persistence: persistence);
  await pumpEventQueue(); // let hydration (if any) settle first
  c.setSource(_fakeSource());
  await c.generateFirstVision();
  await pumpEventQueue(); // let the durable save chain drain
  return c;
}

Map<String, dynamic> _visionRow(
  String id, {
  String image = 'a.jpg',
  String? key,
}) => {
  'id': id,
  'project_id': 'P',
  'idempotency_key': key ?? id,
  'vision_number': 1,
  'parent_vision_id': null,
  'action_type': 'initial',
  'atmosphere_id': 'ayden_signature',
  'image_path': image,
  'source_message_id': null,
  'client_order': 0,
};

Matcher _conflict() => throwsA(
  isA<PwaRepositoryError>().having(
    (e) => e.kind,
    'kind',
    PwaErrorKind.conflict,
  ),
);

void main() {
  group('UUID minting (id / idempotency_key are uuid columns)', () {
    test('mock seed + draft project ids are v4 UUIDs', () {
      final repo = MockPwaExperienceRepository(workDelay: Duration.zero);
      expect(repo.project().projectId, matches(_uuidV4));
      expect(repo.createDraftProject().projectId, matches(_uuidV4));
    });

    test('generated vision + message ids are v4 UUIDs', () async {
      final c = await _generated();
      expect(c.state.currentVision!.versionId, matches(_uuidV4));
      expect(c.state.messages.first.id, matches(_uuidV4));
    });
  });

  group('Single save seam (staging)', () {
    test(
      'generateFirstVision persists the active project, marks Saved',
      () async {
        final fake = _FakePersistence();
        final c = await _generated(persistence: fake);
        final id = c.state.project.projectId;
        expect(fake.store[id], isNotNull);
        expect(fake.store[id]!.status, PwaProjectStatus.active);
        expect(fake.store[id]!.visions, hasLength(1));
        expect(c.state.saveState, PwaSaveState.saved);
      },
    );

    test('saves apply IN ORDER (serialised chain, never concurrent)', () async {
      final fake = _FakePersistence();
      final c = await _generated(persistence: fake);
      final id = c.state.project.projectId;
      c.renameProject(id, 'Renamed A');
      c.renameProject(id, 'Renamed B');
      await pumpEventQueue();
      final renames = fake.calls.where((x) => x.startsWith('renameProject'));
      expect(renames, [
        'renameProject:$id:Renamed A',
        'renameProject:$id:Renamed B',
      ]);
      expect(fake.store[id]!.title, 'Renamed B');
    });

    test(
      'a failed save surfaces Error and does NOT block the next save',
      () async {
        final fake = _FakePersistence();
        final c = await _generated(persistence: fake);
        fake.failNextSave = true;
        c.openLibrary(); // triggers _syncActiveProject → saveProject (fails once)
        await pumpEventQueue();
        expect(c.state.saveState, PwaSaveState.error);
        c.openLibrary(); // next save still runs
        await pumpEventQueue();
        expect(c.state.saveState, PwaSaveState.saved);
      },
    );
  });

  group('§1 — duplicate adopts ONE authoritative UUID', () {
    test(
      'the RPC UUID is visible in session AND identical after refresh',
      () async {
        final fake = _FakePersistence();
        final c = await _generated(persistence: fake);
        final srcId = c.state.project.projectId;

        final copy = await c.duplicateProject(srcId);
        expect(copy, isNotNull);
        final copyId = copy!.projectId;
        expect(copyId, isNot(srcId));
        expect(copyId, matches(_uuidV4));

        // In-session: the library card carries EXACTLY the RPC id (no temp id).
        expect(
          c.state.library.where((p) => p.projectId == copyId),
          hasLength(1),
        );
        expect(c.state.saveState, PwaSaveState.saved);

        // After refresh: a fresh boot restores the SAME id — it converged
        // without waiting for the refresh, and stays identical across it.
        final c2 = await _boot(fake);
        expect(
          c2.state.library.where((p) => p.projectId == copyId),
          hasLength(1),
        );
      },
    );
  });

  group('LIFECYCLE — no durable project before Generate (Step 6A)', () {
    test('LIFECYCLE01: uploading a photo creates NO durable project', () async {
      final fake = _FakePersistence();
      final c = _controller(persistence: fake);
      await pumpEventQueue();
      c.setSource(_srcOf(const [1, 1, 1]));
      await pumpEventQueue();
      expect(fake.store, isEmpty);
      expect(fake.calls.where((x) => x.startsWith('saveProject')), isEmpty);
      expect(fake.storageBytes, isEmpty); // no Storage upload
    });

    test(
      'LIFECYCLE02: Room/Atmosphere changes before Generate create NO durable project',
      () async {
        final fake = _FakePersistence();
        final c = _controller(persistence: fake);
        await pumpEventQueue();
        c.setSource(_srcOf(const [1, 1, 1]));
        c.selectRoom('living_room');
        c.selectEntryAtmosphere('soft_luxury');
        await pumpEventQueue();
        expect(fake.store, isEmpty);
        expect(fake.calls.where((x) => x.startsWith('saveProject')), isEmpty);
      },
    );

    test(
      'LIFECYCLE03: the pre-Generate state creates NO My Projects card',
      () async {
        final fake = _FakePersistence();
        final c = _controller(persistence: fake);
        await pumpEventQueue();
        c.setSource(_srcOf(const [1, 1, 1]));
        await pumpEventQueue();
        final c2 = await _boot(fake); // F5
        expect(c2.state.visibleProjects, isEmpty);
      },
    );

    test('LIFECYCLE04: Generate creates EXACTLY one project', () async {
      final fake = _FakePersistence();
      final id = await _genPersisted(fake, const [2, 2, 2]);
      expect(fake.store.keys.toList(), [id]);
      expect(fake.store.length, 1);
    });

    test(
      'LIFECYCLE05: the created project receives the EXACT selected bytes + Room + Atmosphere',
      () async {
        final fake = _FakePersistence();
        final c = _controller(persistence: fake);
        await pumpEventQueue();
        c.selectRoom('living_room');
        c.selectEntryAtmosphere('soft_luxury');
        c.setSource(_srcOf(const [1, 1, 1]));
        c.setSource(_srcOf(const [2, 2, 2])); // pre-Generate replace
        await c.generateFirstVision();
        await pumpEventQueue();
        final id = c.state.project.projectId;
        expect(fake.storageBytes[id], orderedEquals(const [2, 2, 2]));
        expect(fake.store[id]!.roomId, 'living_room');
        expect(fake.store[id]!.selectedAtmosphereId, 'soft_luxury');
        expect(fake.store[id]!.visions, hasLength(1));
      },
    );

    test(
      'LIFECYCLE06: the project becomes visible only AFTER its first Vision',
      () async {
        final fake = _FakePersistence();
        final c = _controller(persistence: fake);
        await pumpEventQueue();
        c.selectRoom('living_room');
        c.setSource(_srcOf(const [1, 1, 1]));
        await pumpEventQueue();
        expect(fake.store, isEmpty); // not yet
        await c.generateFirstVision();
        await pumpEventQueue();
        expect(fake.store.length, 1);
        final c2 = await _boot(fake);
        expect(c2.state.visibleProjects, hasLength(1));
      },
    );

    test(
      'LIFECYCLE07: a generation failure exposes NO zero-Vision card',
      () async {
        final fake = _FakePersistence();
        final c = _controller(persistence: fake);
        await pumpEventQueue();
        c.selectRoom('living_room');
        c.setSource(_srcOf(const [1, 1, 1]));
        fake.failNextSave = true; // durable INSERT fails
        await c.generateFirstVision();
        await pumpEventQueue();
        expect(c.state.phase, PwaPhase.entry); // stayed on Create
        expect(c.state.saveState, PwaSaveState.error);
        final c2 = await _boot(fake);
        expect(c2.state.visibleProjects, isEmpty); // no zero-Vision card
      },
    );

    test(
      'LIFECYCLE08: legacy zero-Vision rows are EXCLUDED from My Projects',
      () async {
        final fake = _FakePersistence();
        final genId = await _genPersisted(fake, const [3, 3, 3]);
        fake.store['legacy-1'] = _legacyDraftRow('legacy-1');
        final c = await _boot(fake);
        expect(c.state.visibleProjects.map((p) => p.projectId).toList(), [
          genId,
        ]);
      },
    );

    test(
      'LIFECYCLE09: direct navigation to a legacy zero-Vision row falls back safely',
      () async {
        // Library has a generated project → legacy URL normalizes to /projects.
        final fake = _FakePersistence();
        await _genPersisted(fake, const [3, 3, 3]);
        fake.store['legacy-1'] = _legacyDraftRow('legacy-1');
        final c = await _bootRoute(
          fake,
          const PwaRoute(PwaPage.architect, projectId: 'legacy-1'),
        );
        expect(c.state.phase, PwaPhase.projects);
        // Otherwise-empty library → legacy URL normalizes to Home.
        final fake2 = _FakePersistence();
        fake2.store['legacy-2'] = _legacyDraftRow('legacy-2');
        final c2 = await _bootRoute(
          fake2,
          const PwaRoute(PwaPage.architect, projectId: 'legacy-2'),
        );
        expect(c2.state.phase, PwaPhase.entry);
      },
    );

    test(
      'LIFECYCLE10: a generated project opens with correct Before/After and survives F5',
      () async {
        final fake = _FakePersistence();
        final id = await _genPersisted(fake, const [4, 4, 4]);
        final c = await _bootRoute(
          fake,
          PwaRoute(PwaPage.architect, projectId: id),
        );
        expect(c.state.phase, PwaPhase.architect);
        expect(c.state.source!.bytes, orderedEquals(const [4, 4, 4])); // Before
        expect(c.state.versions, hasLength(1)); // After
      },
    );

    test(
      'LIFECYCLE11: Replace photo on an existing generated project remains durable',
      () async {
        final fake = _FakePersistence();
        final id = await _genPersisted(fake, const [1, 1, 1]);
        final c = await _bootRoute(
          fake,
          PwaRoute(PwaPage.architect, projectId: id),
        );
        c.setSource(
          _srcOf(const [9, 9, 9]),
        ); // replace on the generated project
        await pumpEventQueue();
        final reloaded = await fake.loadOriginalBytes(fake.store[id]!);
        expect(reloaded, orderedEquals(const [9, 9, 9]));
      },
    );
  });

  group('§3 — native session persistence (decision logic)', () {
    test('sign in only when no session; reuse an existing one', () {
      expect(PwaStagingSupabaseClient.needsAnonymousSignIn(null), isTrue);
      final session = Session.fromJson({
        'access_token': 'x',
        'token_type': 'bearer',
        'refresh_token': 'r',
        'expires_in': 3600,
        'user': {
          'id': 'u1',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'aud': 'authenticated',
          'created_at': '2020-01-01T00:00:00.000Z',
        },
      });
      expect(session, isNotNull);
      expect(PwaStagingSupabaseClient.needsAnonymousSignIn(session), isFalse);
    });
  });

  group('§4 — idempotent append without blind ignore', () {
    test('identical retry inserts nothing (idempotent success)', () {
      final row = _visionRow('11111111-1111-4111-8111-111111111111');
      final toInsert = planIdempotentAppend(
        localRows: [row],
        existingRows: [row],
        immutableKeys: kPwaVisionImmutableKeys,
        op: 'vision',
      );
      expect(toInsert, isEmpty);
    });

    test('genuinely new row is inserted', () {
      final toInsert = planIdempotentAppend(
        localRows: [_visionRow('22222222-2222-4222-8222-222222222222')],
        existingRows: [_visionRow('11111111-1111-4111-8111-111111111111')],
        immutableKeys: kPwaVisionImmutableKeys,
        op: 'vision',
      );
      expect(toInsert.map((r) => r['id']), [
        '22222222-2222-4222-8222-222222222222',
      ]);
    });

    test('same UUID with different content → conflict', () {
      expect(
        () => planIdempotentAppend(
          localRows: [
            _visionRow(
              '11111111-1111-4111-8111-111111111111',
              image: 'NEW.jpg',
            ),
          ],
          existingRows: [
            _visionRow(
              '11111111-1111-4111-8111-111111111111',
              image: 'OLD.jpg',
            ),
          ],
          immutableKeys: kPwaVisionImmutableKeys,
          op: 'vision',
        ),
        _conflict(),
      );
    });

    test('idempotency_key reused by a different id → conflict', () {
      expect(
        () => planIdempotentAppend(
          localRows: [
            _visionRow(
              '22222222-2222-4222-8222-222222222222',
              key: '11111111-1111-4111-8111-111111111111',
            ),
          ],
          existingRows: [_visionRow('11111111-1111-4111-8111-111111111111')],
          immutableKeys: kPwaVisionImmutableKeys,
          op: 'vision',
        ),
        _conflict(),
      );
    });

    test('the adapter NEVER uses a blind ignoreDuplicates', () {
      final src = File(
        'lib/features/pwa/data/supabase_pwa_persistence_repository.dart',
      ).readAsStringSync();
      expect(
        src.contains('ignoreDuplicates'),
        isFalse,
        reason:
            'every child insert must verify via planIdempotentAppend (the '
            'saveProject seam AND appendVision/appendMessage), never blind-ignore',
      );
    });
  });

  group('Boot routing — the FIRST screen follows durable state (full boot)', () {
    // Build a durable Draft (upload + optional Room/Atmosphere/rename), no Vision.
    Future<_FakePersistence> fakeWithDraft({
      String? room,
      String? atmo,
      String? rename,
    }) async {
      final fake = _FakePersistence();
      final c = _controller(persistence: fake);
      c.setSource(_fakeSource());
      if (room != null) c.selectRoom(room);
      if (atmo != null) c.selectEntryAtmosphere(atmo);
      if (rename != null) c.renameProject(c.state.project.projectId, rename);
      await pumpEventQueue(); // drain the durable save chain
      return fake;
    }

    Future<_FakePersistence> fakeWithActive() async {
      final fake = _FakePersistence();
      final c = _controller(persistence: fake);
      c.setSource(_fakeSource());
      await c.generateFirstVision();
      await pumpEventQueue();
      return fake;
    }

    // A GENERATED (durable) project with optional Room/Atmosphere/rename — the
    // Step 6A replacement for the former durable-Draft fixtures.
    Future<_FakePersistence> fakeWithActiveMeta({
      String? room,
      String? atmo,
      String? rename,
    }) async {
      final fake = _FakePersistence();
      final c = _controller(persistence: fake);
      if (room != null) c.selectRoom(room);
      if (atmo != null) c.selectEntryAtmosphere(atmo);
      c.setSource(_fakeSource());
      await c.generateFirstVision();
      if (rename != null) c.renameProject(c.state.project.projectId, rename);
      await pumpEventQueue();
      return fake;
    }

    test('1. no durable project → Hero (entry, no photo)', () async {
      final c = await _boot(_FakePersistence());
      expect(c.state.phase, PwaPhase.entry);
      expect(c.state.hasSource, isFalse);
      expect(c.state.versions, isEmpty);
    });

    test(
      '2. Step 6A: a pre-Generate creation does NOT survive refresh → clean Home',
      () async {
        final fake = await fakeWithDraft(
          room: 'living_room',
          atmo: 'soft_luxury',
        );
        expect(fake.store, isEmpty); // nothing durable before Generate
        final c = await _boot(fake);
        expect(c.state.phase, PwaPhase.entry); // clean Create/Home
        expect(c.state.hasSource, isFalse); // no phantom photo restored
        expect(c.state.versions, isEmpty);
      },
    );

    test('2b. staging boot library has NO mock seeds (durable-only)', () async {
      final fake = await fakeWithActive();
      final c = await _boot(fake);
      expect(
        c.state.library,
        hasLength(1),
      ); // the one durable generated project
      expect(
        c.state.library.every((p) => !p.projectId.startsWith('seed-')),
        isTrue,
      );
    });

    test('2c. restore keeps the order counter monotonic (no inversion)', () {
      final repo = MockPwaExperienceRepository(
        workDelay: Duration.zero,
        seedLibrary: false,
      );
      // A restored project carries a HIGH prior-session order.
      final restored = repo.createDraftProject().copyWith(
        createdOrder: 500,
        updatedOrder: 500,
      );
      repo.saveProject(restored);
      // The next order must exceed it, so "most recently updated" stays correct.
      expect(repo.nextLibraryOrder(), greaterThan(500));
    });

    test(
      '3. renamed generated project → title restored after refresh',
      () async {
        final fake = await fakeWithActiveMeta(rename: 'My Project');
        final c = await _boot(fake);
        expect(c.state.activeTitleOverride, 'My Project');
      },
    );

    test(
      '4. generated project keeps Room and Atmosphere after refresh',
      () async {
        final fake = await fakeWithActiveMeta(
          room: 'kitchen',
          atmo: 'japandi_calm',
        );
        final c = await _boot(fake);
        expect(c.state.selectedRoomId, 'kitchen');
        expect(c.state.selectedAtmosphereId, 'japandi_calm');
      },
    );

    test('5. active project with a Vision → Architect after refresh', () async {
      final fake = await fakeWithActive();
      final c = await _boot(fake);
      expect(c.state.phase, PwaPhase.architect);
      expect(c.state.versions, isNotEmpty);
      expect(c.state.currentVisionId, isNotNull);
    });

    test('6. last project deleted → safe fallback (Hero, no crash)', () async {
      final fake = await fakeWithActive();
      final id = fake.store.keys.first;
      await fake.softDeleteProject(id);
      final c = await _boot(fake);
      expect(c.state.phase, PwaPhase.entry);
      expect(c.state.library.where((p) => p.projectId == id), isEmpty);
    });

    test(
      '7. a pre-Generate creation leaves NO durable row (nothing to duplicate on refresh)',
      () async {
        final fake = await fakeWithDraft();
        expect(fake.store, isEmpty);
        final c = await _boot(fake);
        expect(fake.store, isEmpty);
        expect(c.state.visibleProjects, isEmpty);
      },
    );

    test('8. boot restores the session — no new anonymous user', () async {
      final fake = await fakeWithDraft();
      fake.calls.clear();
      await _boot(fake);
      expect(fake.calls, contains('ensureInstallation'));
      // §3 proves the client reuses an existing session (no second user).
      expect(PwaStagingSupabaseClient.needsAnonymousSignIn(null), isTrue);
    });

    test('9. mock stays offline — boot restore is a no-op', () {
      final c = _controller(); // no persistence, no restore
      expect(c.state.phase, PwaPhase.entry);
      expect(c.state.saveState, PwaSaveState.idle);
    });
  });

  group('Boot-from-URL — the URL is the primary authority (§5)', () {
    _FakePersistence twoActive() {
      final fake = _FakePersistence();
      fake.store['proj-A'] = _activeSnap('proj-A', 100); // most-recent
      fake.store['proj-B'] = _activeSnap('proj-B', 50); // older
      return fake;
    }

    test(
      'URL names project B → boots B even though A is most-recent',
      () async {
        final c = await _bootRoute(
          twoActive(),
          const PwaRoute(PwaPage.architect, projectId: 'proj-B'),
        );
        expect(c.state.phase, PwaPhase.architect);
        expect(c.state.activeProjectId, 'proj-B'); // URL beats updatedOrder
      },
    );

    test(
      'route == null (no URL context) → legacy most-recent restore',
      () async {
        final c = await _boot(twoActive());
        expect(c.state.activeProjectId, 'proj-A'); // highest updatedOrder
      },
    );

    test('URL "/" → Hero even with durable projects present', () async {
      final c = await _bootRoute(twoActive(), PwaRoute.home);
      expect(c.state.phase, PwaPhase.entry);
      expect(c.state.hasSource, isFalse);
    });

    test('URL "/projects" → My Projects', () async {
      final c = await _bootRoute(twoActive(), PwaRoute.projects);
      expect(c.state.phase, PwaPhase.projects);
      expect(c.state.library, hasLength(2));
    });

    test('URL names an unknown id (non-empty library) → My Projects', () async {
      final c = await _bootRoute(
        twoActive(),
        const PwaRoute(PwaPage.architect, projectId: 'ghost'),
      );
      expect(c.state.phase, PwaPhase.projects);
    });

    test(
      'Draft URL for a project WITH visions normalizes → Architect',
      () async {
        final c = await _bootRoute(
          twoActive(),
          const PwaRoute(PwaPage.draft, projectId: 'proj-A'),
        );
        expect(c.state.phase, PwaPhase.architect);
        expect(c.state.activeProjectId, 'proj-A');
      },
    );

    test('empty library + any URL → Hero (never crashes)', () async {
      final c = await _bootRoute(
        _FakePersistence(),
        const PwaRoute(PwaPage.architect, projectId: 'proj-A'),
      );
      expect(c.state.phase, PwaPhase.entry);
      expect(c.state.library, isEmpty);
    });
  });

  group('Mock stays fully offline (persistence == null)', () {
    test('no durable calls; saveState never leaves idle', () async {
      final c = await _generated(persistence: null);
      expect(c.state.versions, hasLength(1));
      expect(c.state.saveState, PwaSaveState.idle);
    });
  });

  group('Serialization conformance with the deployed 0002 schema', () {
    PwaProjectSnapshot snapshotWithChild() {
      const vid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      const mid = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
      return PwaProjectSnapshot(
        projectId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        title: 'Conformance',
        originalImageAsset: 'assets/showcase/room.jpg',
        roomId: 'living_room',
        roomLabel: 'Living Room',
        selectedAtmosphereId: 'ayden_signature',
        atmosphereLabel: 'Ayden Signature',
        visions: const [
          PwaVision(
            versionId: vid,
            projectId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
            visionNumber: 1,
            title: 'Vision 1',
            atmosphereId: 'ayden_signature',
            actionType: PwaActionType.signature,
            afterAsset: 'assets/showcase/after.jpg',
            order: 0,
            isCurrent: true,
          ),
        ],
        messages: const [
          PwaMessage(
            id: mid,
            role: PwaRole.ayden,
            kind: PwaMessageKind.reveal,
            text: 'Here is your vision',
            visionId: vid,
          ),
        ],
        currentVisionId: vid,
        coverVisionId: vid,
        createdOrder: 1,
        updatedOrder: 2,
        updatedLabel: 'Updated',
        status: PwaProjectStatus.active,
      );
    }

    test('idempotency_key == the entity own UUID; no phantom columns', () {
      final r = pwaRecordsFromSnapshot(
        snapshotWithChild(),
        installationId: 'inst-1',
      );
      final vision = r.visions.single;
      expect(vision['idempotency_key'], vision['id']);
      expect(vision.containsKey('installation_id'), isFalse);

      final message = r.messages.single;
      expect(message['idempotency_key'], message['id']);
      expect(message.containsKey('installation_id'), isFalse);

      expect(r.project['installation_id'], 'inst-1');
      expect(r.project.containsKey('updated_label'), isFalse);
      expect(r.project.containsKey('owner_user_id'), isFalse);
    });

    test('null room + null atmosphere → NOT NULL columns satisfied', () {
      // The deployed schema declares room_id AND selected_atmosphere_id NOT NULL;
      // a Draft uploaded before any Room/Atmosphere choice has both null. Both
      // must serialise non-null; room_id round-trips back to null, the atmosphere
      // defaults (app treats null == signature default) with no read remap.
      const draft = PwaProjectSnapshot(
        projectId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        title: 'Open-plan Living Space',
        originalImageAsset: 'assets/showcase/room.jpg',
        roomId: null, // Ayden Decide
        roomLabel: 'Your space',
        selectedAtmosphereId: null, // no explicit atmosphere yet
        atmosphereLabel: 'Ayden Signature',
        visions: [],
        messages: [],
        currentVisionId: null,
        coverVisionId: null,
        createdOrder: 1,
        updatedOrder: 1,
        updatedLabel: 'Updated',
        status: PwaProjectStatus.draft,
      );
      final r = pwaRecordsFromSnapshot(draft, installationId: 'inst-1');
      expect(r.project['room_id'], kPwaAydenDecideRoom); // NOT NULL satisfied
      expect(r.project['selected_atmosphere_id'], kPwaDefaultAtmosphere);
      expect(r.project['selected_atmosphere_id'], isNotNull);
      final back = pwaSnapshotFromRecords(
        project: r.project,
        visions: r.visions,
        messages: r.messages,
      );
      expect(back.roomId, isNull); // restored to Ayden Decide
      expect(back.selectedAtmosphereId, kPwaDefaultAtmosphere); // real default
      expect(back.status, PwaProjectStatus.draft);
    });

    test('records → snapshot round-trip preserves the graph', () {
      final r = pwaRecordsFromSnapshot(
        snapshotWithChild(),
        installationId: 'inst-1',
      );
      final back = pwaSnapshotFromRecords(
        project: r.project,
        visions: r.visions,
        messages: r.messages,
      );
      expect(back.projectId, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
      expect(
        back.visions.single.versionId,
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      );
      expect(back.messages.single.id, 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
      expect(back.currentVisionId, back.visions.single.versionId);
    });
  });

  group('BEFORECARD — card-open hydrates the original before Architect', () {
    test(
      'BEFORECARD01: opening a generated project from My Projects installs its exact original bytes',
      () async {
        final fake = _FakePersistence();
        final id = await _genPersisted(fake, const [7, 7, 7]);
        // Fresh session on My Projects — _repo has the library WITHOUT bytes
        // (exactly the staging card-open situation the defect occurred in).
        final c = await _bootRoute(fake, const PwaRoute(PwaPage.projects));
        expect(c.state.phase, PwaPhase.projects);
        await c.openProject(id);
        expect(c.state.phase, PwaPhase.architect);
        expect(c.state.activeProjectId, id);
        expect(c.state.source, isNotNull);
        expect(c.state.source!.bytes, orderedEquals(const [7, 7, 7]));
      },
    );

    test(
      'BEFORECARD02: the first settled Architect state after card open has source != null',
      () async {
        final fake = _FakePersistence();
        final id = await _genPersisted(fake, const [3, 3, 3]);
        final c = await _bootRoute(fake, const PwaRoute(PwaPage.projects));
        await c.openProject(id);
        expect(c.state.phase, PwaPhase.architect);
        expect(c.state.source, isNotNull); // never a blank Before
      },
    );

    test(
      'BEFORECARD03: card open and F5 boot produce equivalent project/source/vision',
      () async {
        final fake = _FakePersistence();
        final id = await _genPersisted(fake, const [8, 8, 8]);
        final booted = await _bootRoute(
          fake,
          PwaRoute(PwaPage.architect, projectId: id),
        );
        final carded = await _bootRoute(fake, const PwaRoute(PwaPage.projects));
        await carded.openProject(id);
        expect(carded.state.activeProjectId, booted.state.activeProjectId);
        expect(carded.state.currentVisionId, booted.state.currentVisionId);
        expect(carded.state.versions.length, booted.state.versions.length);
        expect(carded.state.source!.bytes, booted.state.source!.bytes);
      },
    );

    test(
      'BEFORECARD04: Project A cannot receive Project B’s original bytes',
      () async {
        final fake = _FakePersistence();
        final idA = await _genPersisted(fake, const [1, 1, 1]);
        final idB = await _genPersisted(fake, const [2, 2, 2]);
        expect(idA, isNot(idB));
        final c = await _bootRoute(fake, const PwaRoute(PwaPage.projects));
        await c.openProject(idA);
        expect(c.state.activeProjectId, idA);
        expect(c.state.source!.bytes, orderedEquals(const [1, 1, 1]));
        expect(c.state.source!.bytes, isNot(orderedEquals(const [2, 2, 2])));
      },
    );

    test(
      'BEFORECARD05: the Architect view is NOT emitted before original hydration completes',
      () async {
        final fake = _FakePersistence();
        final id = await _genPersisted(fake, const [9, 9, 9]);
        final c = await _bootRoute(fake, const PwaRoute(PwaPage.projects));
        final gate = Completer<void>();
        fake.gateNextLoad = gate; // block hydration
        final open = c.openProject(id);
        await pumpEventQueue();
        expect(
          c.state.phase,
          PwaPhase.projects,
        ); // not settled before Before loads
        gate.complete();
        await open;
        expect(c.state.phase, PwaPhase.architect);
        expect(c.state.source, isNotNull); // settled WITH the original
      },
    );
  });
}
