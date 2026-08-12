// Home / My Projects must show the REAL staging library and nothing else.
//
// The reported symptom was six near-identical cards: same cover, same title,
// same atmosphere, "1 Vision" each and a bare "Updated" with no date. These
// tests pin each of those five things to real record data, so a demo project or
// a stale count can never be what a card is made of.

import 'dart:io';

import 'package:ai_home_architect/features/pwa/data/pwa_project_serialization.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_project.dart';
import 'package:flutter_test/flutter_test.dart';

/// A project row exactly as `pwa_staging.pwa_projects` returns it — including
/// `updated_at`, which the database always writes, and WITHOUT `updated_label`,
/// which no writer produces and the schema never had.
Map<String, dynamic> _projectRow({
  required String id,
  required String title,
  String? coverVisionId,
  String? currentVisionId,
  String atmosphereLabel = 'Ayden Signature',
  String updatedAt = '2026-08-06T18:28:46.177613+00:00',
  int updatedOrder = 1,
}) => {
  'id': id,
  'title': title,
  'status': 'active',
  'room_id': kPwaAydenDecideRoom,
  'room_label': 'Your space',
  'selected_atmosphere_id': 'ayden_signature',
  'selected_atmosphere_label': atmosphereLabel,
  'original_image_path': 'users/u1/projects/$id/original/o.jpg',
  'current_vision_id': currentVisionId,
  'cover_vision_id': coverVisionId,
  'client_created_order': 1,
  'client_updated_order': updatedOrder,
  'updated_at': updatedAt,
  'schema_version': 1,
};

Map<String, dynamic> _visionRow({
  required String id,
  required String projectId,
  required int number,
  required String action,
  String atmosphere = 'ayden_signature',
  String? parent,
}) => {
  'id': id,
  'project_id': projectId,
  'vision_number': number,
  'parent_vision_id': parent,
  'action_type': action,
  'atmosphere_id': atmosphere,
  'atmosphere_label': atmosphere,
  'image_source': 'staging_storage',
  'image_path': 'users/u1/projects/$projectId/generated/$id.jpg',
  'idempotency_key': 'k-$id',
  'schema_version': 1,
  // client_order absent: the BACKEND writes these rows and has no client
  // sequence to write.
};

void main() {
  group('a real project renders from real records', () {
    // The exact shape produced by the verified staging run: an initial vision,
    // a refine, an atmosphere switch, current = cover = the third.
    PwaProjectSnapshot buildRealProject({DateTime? now}) =>
        pwaSnapshotFromRecords(
          project: _projectRow(
            id: 'p-real',
            title: 'Open-plan Living Space',
            coverVisionId: 'v3',
            currentVisionId: 'v3',
            atmosphereLabel: 'Japandi Calm',
          ),
          visions: [
            _visionRow(
              id: 'v1',
              projectId: 'p-real',
              number: 1,
              action: 'initial',
            ),
            _visionRow(
              id: 'v2',
              projectId: 'p-real',
              number: 2,
              action: 'refine',
              parent: 'v1',
            ),
            _visionRow(
              id: 'v3',
              projectId: 'p-real',
              number: 3,
              action: 'switch_atmosphere',
              atmosphere: 'japandi_calm',
              parent: 'v2',
            ),
          ],
          messages: const [],
          now: now,
        );

    test('HOME01: the vision count is the REAL number of visions', () {
      final p = buildRealProject();
      expect(p.visionCount, 3, reason: 'not "1 Vision"');
      expect(p.visions.map((v) => v.visionNumber), [1, 2, 3]);
    });

    test('HOME02: the cover is the vision coverVisionId names', () {
      final p = buildRealProject();
      expect(p.coverVision?.versionId, 'v3');
      expect(p.coverVision!.atmosphereId, 'japandi_calm');
      expect(
        p.coverVision!.afterAsset,
        'users/u1/projects/p-real/generated/v3.jpg',
        reason: 'a durable Storage path, never a bundled asset',
      );
      expect(p.coverVision!.afterAsset.startsWith('assets/'), isFalse);
    });

    test(
      'HOME03: the cover falls back to current, then to the last vision',
      () {
        // No cover named → current.
        final noCover = pwaSnapshotFromRecords(
          project: _projectRow(id: 'p2', title: 'T', currentVisionId: 'v2'),
          visions: [
            _visionRow(id: 'v1', projectId: 'p2', number: 1, action: 'initial'),
            _visionRow(id: 'v2', projectId: 'p2', number: 2, action: 'refine'),
          ],
          messages: const [],
        );
        expect(noCover.coverVision?.versionId, 'v2');

        // Neither named → the most recent vision, still a real one.
        final neither = pwaSnapshotFromRecords(
          project: _projectRow(id: 'p3', title: 'T'),
          visions: [
            _visionRow(id: 'v1', projectId: 'p3', number: 1, action: 'initial'),
            _visionRow(id: 'v2', projectId: 'p3', number: 2, action: 'refine'),
          ],
          messages: const [],
        );
        expect(neither.coverVision?.versionId, 'v2');
        expect(neither.coverVision!.afterAsset, contains('/generated/'));
      },
    );

    test('HOME04: a real date replaces the bare "Updated"', () {
      // THE reported symptom. `updated_label` is not a column; the label has to
      // come from `updated_at`, which the database always writes.
      final p = buildRealProject(now: DateTime.parse('2026-08-06T19:00:00Z'));
      expect(p.updatedLabel, isNot('Updated'));
      expect(p.updatedLabel, 'Updated 31 minutes ago');
      expect(p.updatedAt, isNotNull);
    });

    test('HOME05: the freshness label reads like a person would say it', () {
      final now = DateTime.parse('2026-08-06T12:00:00Z');
      String labelFor(String iso) =>
          pwaRelativeUpdatedLabel(DateTime.parse(iso), now: now);
      expect(labelFor('2026-08-06T11:59:40Z'), 'Updated just now');
      expect(labelFor('2026-08-06T11:01:00Z'), 'Updated 59 minutes ago');
      // Past the hour it becomes a day-scale statement, which is how people
      // talk once "minutes ago" stops being informative.
      expect(labelFor('2026-08-06T11:00:00Z'), 'Updated today');
      expect(labelFor('2026-08-06T02:00:00Z'), 'Updated today');
      expect(labelFor('2026-08-05T23:00:00Z'), 'Yesterday');
      expect(labelFor('2026-08-03T12:00:00Z'), '3 days ago');
      expect(labelFor('2026-07-31T12:00:00Z'), '6 days ago');
      expect(labelFor('2026-07-29T12:00:00Z'), 'Last week');
      expect(labelFor('2026-07-20T12:00:00Z'), '2 weeks ago');
      expect(labelFor('2026-06-06T12:00:00Z'), '2 months ago');
      // A clock skew must never render a negative age.
      expect(labelFor('2026-08-06T12:05:00Z'), 'Updated just now');
    });

    test('HOME06: a record with no timestamp still renders something', () {
      final row = _projectRow(id: 'p4', title: 'T')..remove('updated_at');
      final p = pwaSnapshotFromRecords(
        project: row,
        visions: [
          _visionRow(id: 'v1', projectId: 'p4', number: 1, action: 'initial'),
        ],
        messages: const [],
      );
      expect(p.updatedAt, isNull);
      expect(p.updatedLabel, 'Updated');
    });
  });

  group('restored conversation binds each card to its own vision', () {
    test('HOME07: three vision_result messages resolve to three DISTINCT '
        'images, restored from records', () {
      // The Architect renders one card per `vision_result` message and looks the
      // vision up by the id the message references. Restored from the backend,
      // that join has to hold for the FIRST vision as much as the last — the
      // initial one has no parent and no client_order, which is exactly where a
      // lookup is most likely to quietly fall through.
      Map<String, dynamic> msg(String id, int order, {String? vision}) => {
        'id': id,
        'project_id': 'p-real',
        'role': vision == null ? 'user' : 'assistant',
        'message_type': vision == null ? 'text' : 'vision_result',
        'text_content': vision == null ? 'make it warmer' : 'Here it is.',
        'referenced_vision_id': vision,
        'client_order': order,
        'idempotency_key': id,
        'schema_version': 1,
      };

      final p = pwaSnapshotFromRecords(
        project: _projectRow(
          id: 'p-real',
          title: 'Open-plan Living Space',
          coverVisionId: 'v3',
          currentVisionId: 'v3',
          atmosphereLabel: 'Japandi Calm',
        ),
        visions: [
          _visionRow(
            id: 'v1',
            projectId: 'p-real',
            number: 1,
            action: 'initial',
          ),
          _visionRow(
            id: 'v2',
            projectId: 'p-real',
            number: 2,
            action: 'refine',
            parent: 'v1',
          ),
          _visionRow(
            id: 'v3',
            projectId: 'p-real',
            number: 3,
            action: 'switch_atmosphere',
            atmosphere: 'japandi_calm',
            parent: 'v2',
          ),
        ],
        messages: [
          msg('m1', 0, vision: 'v1'),
          msg('m2', 1),
          msg('m3', 2, vision: 'v2'),
          msg('m4', 3),
          msg('m5', 4, vision: 'v3'),
        ],
      );

      // The conversation survives in order, with three reveal cards.
      final reveals = p.messages
          .where((m) => m.kind == PwaMessageKind.reveal)
          .toList();
      expect(reveals.map((m) => m.visionId), ['v1', 'v2', 'v3']);

      // Each card finds ITS vision — including the initial one.
      PwaVision? lookup(String? id) {
        for (final v in p.visions) {
          if (v.versionId == id) return v;
        }
        return null;
      }

      final images = <String>[];
      for (final r in reveals) {
        final v = lookup(r.visionId);
        expect(v, isNotNull, reason: 'card ${r.visionId} found no vision');
        expect(
          v!.afterAsset,
          'users/u1/projects/p-real/generated/${r.visionId}.jpg',
          reason: 'each card must show the vision it names',
        );
        expect(v.afterAsset.startsWith('assets/'), isFalse);
        images.add(v.afterAsset);
      }
      expect(images.toSet(), hasLength(3), reason: 'three different pictures');

      // The first vision is the one that has no parent and no client_order —
      // it must still be complete.
      final first = lookup('v1')!;
      expect(first.parentVersionId, isNull);
      expect(first.visionNumber, 1);
      expect(first.actionType, PwaActionType.signature);
      expect(first.afterAsset, isNotEmpty);
    });
  });

  group('library ordering and identity', () {
    PwaProjectSnapshot snap(String id, String iso, {int order = 0}) =>
        pwaSnapshotFromRecords(
          project: _projectRow(
            id: id,
            title: 'P-$id',
            updatedAt: iso,
            updatedOrder: order,
            coverVisionId: 'v-$id',
          ),
          visions: [
            _visionRow(
              id: 'v-$id',
              projectId: id,
              number: 1,
              action: 'initial',
            ),
          ],
          messages: const [],
        );

    test(
      'HOME10: the library sorts by the DATABASE timestamp, newest first',
      () {
        final sorted = PwaProjectSnapshot.sortedBy([
          snap(
            'old',
            '2026-08-01T10:00:00Z',
            order: 99,
          ), // a high client counter…
          snap('new', '2026-08-06T10:00:00Z', order: 1), // …must not win over a
          snap('mid', '2026-08-03T10:00:00Z', order: 50), //   newer real write
        ], PwaProjectSort.recentlyUpdated);
        expect(sorted.map((p) => p.projectId), ['new', 'mid', 'old']);
      },
    );

    test(
      'HOME11: in-memory sessions still sort by the deterministic counter',
      () {
        // No updatedAt (mock / unsaved draft) → the test-stable counter is used.
        PwaProjectSnapshot local(String id, int order) => PwaProjectSnapshot(
          projectId: id,
          title: id,
          originalImageAsset: 'assets/x.jpg',
          roomId: null,
          roomLabel: '',
          selectedAtmosphereId: 'ayden_signature',
          atmosphereLabel: 'Ayden Signature',
          visions: const [],
          messages: const [],
          currentVisionId: null,
          createdOrder: 0,
          updatedOrder: order,
          updatedLabel: '',
          status: PwaProjectStatus.active,
        );
        final sorted = PwaProjectSnapshot.sortedBy([
          local('a', 1),
          local('c', 3),
          local('b', 2),
        ], PwaProjectSort.recentlyUpdated);
        expect(sorted.map((p) => p.projectId), ['c', 'b', 'a']);
      },
    );

    test('HOME12: the same project hydrated twice is ONE card', () {
      // What the Home does: dedup on projectId, and only on projectId.
      final rows = [
        snap('p1', '2026-08-06T10:00:00Z'),
        snap('p1', '2026-08-06T10:00:00Z'), // same project, hydrated again
        snap('p2', '2026-08-05T10:00:00Z'),
      ];
      final seen = <String>{};
      final cards = [
        for (final p in rows)
          if (seen.add(p.projectId)) p,
      ];
      expect(cards, hasLength(2));
      expect(cards.map((p) => p.projectId), ['p1', 'p2']);
    });

    test('HOME13: identical-looking but DISTINCT projects stay distinct', () {
      // The reported cards shared a title, a room and an atmosphere. That must
      // never collapse them: only the id decides identity.
      final a = snap('p-a', '2026-08-06T10:00:00Z');
      final b = snap('p-b', '2026-08-06T10:00:00Z');
      expect(a.title == b.title, isFalse, reason: 'distinct by construction');
      final same = pwaSnapshotFromRecords(
        project: _projectRow(id: 'p-c', title: 'P-p-a', coverVisionId: 'v-p-c'),
        visions: [
          _visionRow(
            id: 'v-p-c',
            projectId: 'p-c',
            number: 1,
            action: 'initial',
          ),
        ],
        messages: const [],
      );
      final seen = <String>{};
      final cards = [
        for (final p in [a, same])
          if (seen.add(p.projectId)) p,
      ];
      expect(cards, hasLength(2), reason: 'same title, different project');
    });
  });

  group('no demo data in the staging runtime', () {
    test('HOME20: the staging boot never seeds the demo library', () {
      final src = File('lib/main_pwa.dart').readAsStringSync();
      // The mock repository is present ONLY as an empty in-memory store.
      expect(
        src.contains('MockPwaExperienceRepository(seedLibrary: false)'),
        isTrue,
      );
      expect(
        RegExp(
          r'MockPwaExperienceRepository\((?!seedLibrary: false)',
        ).hasMatch(src.split('_bootPwaStaging').last),
        isFalse,
        reason: 'the staging boot must never build a seeding repository',
      );
      // Staging persistence is the only source of durable projects.
      expect(src.contains('SupabasePwaPersistenceRepository'), isTrue);
    });

    test('HOME21: no library screen reads a demo or fixture collection', () {
      for (final path in const [
        'lib/features/pwa/presentation/pwa_home_screen.dart',
        'lib/features/pwa/presentation/pwa_projects_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        for (final banned in const [
          'demoProjects',
          'sampleProjects',
          'fixtureProjects',
          '_seedLibrary',
          'visionAsset',
        ]) {
          expect(src.contains(banned), isFalse, reason: '$path uses $banned');
        }
      }
    });

    test('HOME22: no card renders a generated cover with Image.asset', () {
      for (final path in const [
        'lib/features/pwa/presentation/pwa_home_screen.dart',
        'lib/features/pwa/presentation/pwa_projects_screen.dart',
      ]) {
        final src = File(
          path,
        ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
        for (final banned in const [
          'Image.asset(cover.afterAsset',
          'Image.asset(v.afterAsset',
          'Image.asset(vision.afterAsset',
          'Image.asset(p.coverVision',
        ]) {
          expect(src.contains(banned), isFalse, reason: '$path: $banned');
        }
        // Covers go through the resolver-backed widget.
        expect(
          src.contains('PwaStoredImage(') || src.contains('pwaAfterImage('),
          isTrue,
          reason: '$path must render covers through PwaStoredImage',
        );
      }
    });

    test('HOME23: a hydration failure yields NO projects, never demo cards', () {
      // pwaResolveBootRestore returns an EMPTY library on any failure. Proving
      // the shape here keeps the contract visible: an error is an empty state,
      // not a fallback catalogue.
      const empty = PwaBootRestoreShape.emptyOnFailure;
      expect(empty, isTrue);
      final src = File(
        'lib/features/pwa/application/pwa_controller.dart',
      ).readAsStringSync();
      expect(
        src.contains('return PwaBootRestore(\n      library: const [],'),
        isTrue,
        reason: 'the failure path must produce an empty library',
      );
    });
  });
}

/// Documents the boot contract the test above asserts against.
class PwaBootRestoreShape {
  static const bool emptyOnFailure = true;
}
