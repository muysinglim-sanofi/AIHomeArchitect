// Batch 3.0 — serialization round-trips (§33) + offline persistence contract
// (§34/§35/§37) via the mock adapter, plus staging fail-closed (§32).

import 'package:ai_home_architect/features/pwa/config/pwa_environment.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_persistence_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_project_serialization.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_repository_error.dart';
import 'package:ai_home_architect/features/pwa/data/staging_pwa_persistence_repository.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_project.dart';
import 'package:flutter_test/flutter_test.dart';

PwaProjectSnapshot _sample() {
  const v1 = PwaVision(
    versionId: 'p-v1',
    projectId: 'p',
    visionNumber: 1,
    title: 'Ayden Signature',
    atmosphereId: 'ayden_signature',
    actionType: PwaActionType.signature,
    afterAsset: 'assets/showcase/living_after.jpg',
    order: 1,
  );
  const v2 = PwaVision(
    versionId: 'p-v2',
    projectId: 'p',
    visionNumber: 2,
    title: 'Make it warmer',
    atmosphereId: 'ayden_signature',
    actionType: PwaActionType.refine,
    afterAsset: 'assets/showcase/villa_after.jpg',
    order: 2,
    parentVersionId: 'p-v1',
    sourceMessageId: 'p-mu1',
    instruction: 'Make it warmer',
    isCurrent: true,
  );
  const m1 = PwaMessage(
    id: 'p-ma0',
    role: PwaRole.ayden,
    kind: PwaMessageKind.reveal,
    text: 'intro',
    visionId: 'p-v1',
    chips: ['What do you think?', 'Make it warmer'],
  );
  const mu1 = PwaMessage(
    id: 'p-mu1',
    role: PwaRole.user,
    kind: PwaMessageKind.text,
    text: 'Make it warmer',
  );
  const m2 = PwaMessage(
    id: 'p-ma1',
    role: PwaRole.ayden,
    kind: PwaMessageKind.text,
    text: 'good instinct',
    pendingRefine: 'Make it warmer',
    chips: ['Apply this change'],
  );
  const m3 = PwaMessage(
    id: 'p-ma2',
    role: PwaRole.ayden,
    kind: PwaMessageKind.reveal,
    text: 'done',
    visionId: 'p-v2',
  );
  return const PwaProjectSnapshot(
    projectId: 'p',
    title: 'Living Room Concept',
    originalImageAsset: 'assets/showcase/living_before.jpg',
    roomId: 'livingRoom',
    roomLabel: 'Living Room',
    selectedAtmosphereId: 'ayden_signature',
    atmosphereLabel: 'Ayden Signature',
    visions: [v1, v2],
    messages: [m1, mu1, m2, m3],
    currentVisionId: 'p-v2',
    coverVisionId: 'p-v2',
    createdOrder: 10,
    updatedOrder: 50,
    updatedLabel: 'Updated today',
    status: PwaProjectStatus.active,
  );
}

PwaProjectSnapshot _roundTrip(PwaProjectSnapshot s) {
  final r = pwaRecordsFromSnapshot(s, installationId: 'inst-1');
  return pwaSnapshotFromRecords(
    project: r.project,
    visions: r.visions,
    messages: r.messages,
  );
}

void main() {
  group('serialization round-trip (§33)', () {
    test('11/12. project fields survive round-trip', () {
      final b = _roundTrip(_sample());
      expect(b.projectId, 'p');
      expect(b.title, 'Living Room Concept');
      expect(b.status, PwaProjectStatus.active);
      expect(b.roomId, 'livingRoom');
      expect(b.roomLabel, 'Living Room');
      expect(b.atmosphereLabel, 'Ayden Signature');
      expect(b.originalImageAsset, 'assets/showcase/living_before.jpg');
      expect(b.createdOrder, 10);
      expect(b.updatedOrder, 50);
    });

    test('13. Vision lineage survives round-trip', () {
      final b = _roundTrip(_sample());
      expect(b.visions.length, 2);
      final v2 = b.visions.firstWhere((v) => v.versionId == 'p-v2');
      expect(v2.parentVersionId, 'p-v1');
      expect(v2.sourceMessageId, 'p-mu1');
      expect(v2.instruction, 'Make it warmer');
      expect(v2.actionType, PwaActionType.refine);
    });

    test('14. message chronology + refs survive round-trip', () {
      final b = _roundTrip(_sample());
      expect(b.messages.map((m) => m.id).toList(), [
        'p-ma0',
        'p-mu1',
        'p-ma1',
        'p-ma2',
      ]);
      expect(b.messages.first.visionId, 'p-v1');
      expect(b.messages.first.chips, contains('Make it warmer'));
      expect(b.messages[2].pendingRefine, 'Make it warmer');
      expect(b.messages.last.visionId, 'p-v2');
      // Enum mappings must survive too: reveal↔vision_result, ayden↔assistant,
      // user↔user, text↔text (regression guard for the message-kind/role maps).
      expect(b.messages.first.kind, PwaMessageKind.reveal);
      expect(b.messages.first.role, PwaRole.ayden);
      expect(b.messages[1].role, PwaRole.user);
      expect(b.messages[1].kind, PwaMessageKind.text);
      expect(b.messages[2].kind, PwaMessageKind.text);
      expect(b.messages.last.kind, PwaMessageKind.reveal);
    });

    test('15/16. current + cover vision survive round-trip', () {
      final b = _roundTrip(_sample());
      expect(b.currentVisionId, 'p-v2');
      expect(b.coverVisionId, 'p-v2');
      expect(
        b.visions.firstWhere((v) => v.versionId == 'p-v2').isCurrent,
        isTrue,
      );
      expect(
        b.visions.firstWhere((v) => v.versionId == 'p-v1').isCurrent,
        isFalse,
      );
    });

    test('17. draft status survives round-trip', () {
      final draft = _sample().copyWith(status: PwaProjectStatus.draft);
      expect(_roundTrip(draft).status, PwaProjectStatus.draft);
    });

    test('18. image source kind maps bundle vs staging_storage', () {
      expect(pwaImageSourceForPath('assets/x.jpg'), PwaImageSourceKind.bundle);
      expect(
        pwaImageSourceForPath('installations/i/p/original/x.jpg'),
        PwaImageSourceKind.stagingStorage,
      );
    });

    test(
      '19/20/21. malformed / unknown enum / bad schema raise controlled errors',
      () {
        final r = pwaRecordsFromSnapshot(_sample(), installationId: 'i');
        // missing required title
        final noTitle = {...r.project}..remove('title');
        expect(
          () => pwaSnapshotFromRecords(
            project: noTitle,
            visions: r.visions,
            messages: r.messages,
          ),
          throwsA(isA<PwaRepositoryError>()),
        );
        // unknown enum
        expect(
          () => pwaActionFromDb('bogus'),
          throwsA(isA<PwaRepositoryError>()),
        );
        // unsupported schema_version
        final future = {...r.project, 'schema_version': 99};
        expect(
          () => pwaSnapshotFromRecords(
            project: future,
            visions: r.visions,
            messages: r.messages,
          ),
          throwsA(isA<PwaRepositoryError>()),
        );
      },
    );

    test('22. deserialized collections are immutable', () {
      final b = _roundTrip(_sample());
      expect(() => b.visions.add(b.visions.first), throwsUnsupportedError);
      expect(() => b.messages.add(b.messages.first), throwsUnsupportedError);
    });
  });

  group('mock persistence adapter (§34/§35/§37 offline)', () {
    late MockPwaPersistenceRepository repo;
    setUp(() => repo = MockPwaPersistenceRepository());

    test('23/28. save then reload restores the project graph', () async {
      await repo.saveProject(_sample());
      final loaded = await repo.loadProject('p');
      expect(loaded, isNotNull);
      expect(loaded!.visions.length, 2);
      expect(loaded.messages.length, 4);
      expect((await repo.loadLibrary()).length, 1);
    });

    test('42/43/48. appendVision is append-only and idempotent', () async {
      await repo.saveProject(_sample());
      const v3 = PwaVision(
        versionId: 'p-v3',
        projectId: 'p',
        visionNumber: 3,
        title: 'Brighter',
        atmosphereId: 'ayden_signature',
        actionType: PwaActionType.refine,
        afterAsset: 'assets/showcase/smallspace_after.jpg',
        order: 3,
        parentVersionId: 'p-v2',
      );
      await repo.appendVision('p', v3);
      expect((await repo.loadProject('p'))!.visions.length, 3);
      await repo.appendVision('p', v3); // retry — no duplicate
      final after = await repo.loadProject('p');
      expect(after!.visions.length, 3);
      expect(after.currentVisionId, 'p-v3'); // §49 current updates
      expect(after.coverVisionId, 'p-v3'); // §50 cover updates
      // previous visions unchanged (§48)
      expect(after.visions.any((v) => v.versionId == 'p-v1'), isTrue);
    });

    test('41. appendMessage preserves chronology, no vision created', () async {
      await repo.saveProject(_sample());
      const advice = PwaMessage(
        id: 'p-ma9',
        role: PwaRole.ayden,
        kind: PwaMessageKind.text,
        text: 'looks calm',
      );
      await repo.appendMessage('p', advice);
      final after = await repo.loadProject('p');
      expect(after!.messages.length, 5);
      expect(after.messages.last.id, 'p-ma9');
      expect(after.visions.length, 2); // unchanged
      // Retry with the same message id must NOT duplicate (idempotent append).
      await repo.appendMessage('p', advice);
      expect((await repo.loadProject('p'))!.messages.length, 5);
    });

    test('32. rename persists', () async {
      await repo.saveProject(_sample());
      await repo.renameProject('p', 'My Space');
      expect((await repo.loadProject('p'))!.title, 'My Space');
    });

    test('35/36. deep duplicate persists independently', () async {
      await repo.saveProject(_sample());
      final dup = await repo.duplicateProject('p');
      expect(dup.projectId, isNot('p'));
      expect((await repo.loadLibrary()).length, 2);
      // fully independent ids + lineage
      expect(
        dup.visions.every((v) => v.versionId.startsWith(dup.projectId)),
        isTrue,
      );
      expect(dup.visions.every((v) => v.projectId == dup.projectId), isTrue);
      final child = dup.visions.firstWhere((v) => v.parentVersionId != null);
      expect(child.parentVersionId, dup.visions.first.versionId);
    });

    test(
      '33/34. soft delete hides the project and blocks normal open',
      () async {
        await repo.saveProject(_sample());
        await repo.softDeleteProject('p');
        expect(await repo.loadProject('p'), isNull);
        expect(
          (await repo.loadLibrary()).any((x) => x.projectId == 'p'),
          isFalse,
        );
      },
    );

    test('validation: empty title rejected', () async {
      final bad = _sample().copyWith(title: '   ');
      expect(() => repo.saveProject(bad), throwsA(isA<PwaRepositoryError>()));
    });
  });

  group('staging adapter fail-closed (§32)', () {
    PwaEnvironment stagingEnv() => PwaEnvironment.parse({
      'AYDEN_ENV': 'staging',
      'AYDEN_STAGING_SUPABASE_URL': 'https://eedcahzekpgxvvfxufbk.supabase.co',
      'AYDEN_STAGING_PROJECT_REF': kStagingProjectRef,
      'AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY':
          'sb_publishable_TEST_placeholder_not_a_real_key',
    });

    test(
      'every op throws a configuration error (never touches a backend)',
      () async {
        final s = StagingPwaPersistenceRepository(stagingEnv());
        Future<void> expectConfig(Future<void> Function() op) async {
          try {
            await op();
            fail('expected a configuration error');
          } on PwaRepositoryError catch (e) {
            expect(e.kind, PwaErrorKind.configuration);
          }
        }

        await expectConfig(() => s.healthCheck());
        await expectConfig(() => s.loadLibrary());
        await expectConfig(() => s.saveProject(_sample()));
      },
    );

    test(
      'selector: mock env → mock adapter; staging env → staging adapter',
      () {
        final mock = MockPwaPersistenceRepository();
        final m = pwaPersistenceRepositoryFor(
          PwaEnvironment.parse({'AYDEN_ENV': 'mock'}),
          mock: mock,
        );
        expect(identical(m, mock), isTrue);
        final s = pwaPersistenceRepositoryFor(stagingEnv(), mock: mock);
        expect(s, isA<StagingPwaPersistenceRepository>());
      },
    );
  });
}
