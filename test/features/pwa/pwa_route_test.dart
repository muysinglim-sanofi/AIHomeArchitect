// Batch 3.4 — pure route-model logic (parse / location / normalize). Widget-
// level F5/back-forward restoration is covered in pwa_router_widget tests.

import 'package:ai_home_architect/features/pwa/application/pwa_route.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_project.dart';
import 'package:flutter_test/flutter_test.dart';

PwaProjectSnapshot _project(String id, {int visions = 0, String? visionId}) {
  final list = [
    for (var i = 0; i < visions; i++)
      PwaVision(
        versionId: (i == 0 && visionId != null) ? visionId : '$id-v${i + 1}',
        projectId: id,
        visionNumber: i + 1,
        title: 'v',
        atmosphereId: 'ayden_signature',
        actionType: PwaActionType.signature,
        afterAsset: 'assets/x.jpg',
        order: i + 1,
      ),
  ];
  return PwaProjectSnapshot(
    projectId: id,
    title: 'P',
    originalImageAsset: 'assets/x.jpg',
    roomId: null,
    roomLabel: '',
    selectedAtmosphereId: 'ayden_signature',
    atmosphereLabel: '',
    visions: list,
    messages: const [],
    currentVisionId: list.isEmpty ? null : list.last.versionId,
    createdOrder: 1,
    updatedOrder: 1,
    updatedLabel: '',
    status: visions == 0 ? PwaProjectStatus.draft : PwaProjectStatus.active,
  );
}

void main() {
  group('parse', () {
    test(
      '/ → Home',
      () => expect(PwaRoute.parse(Uri.parse('/')).page, PwaPage.home),
    );
    test('/projects → Projects', () {
      expect(PwaRoute.parse(Uri.parse('/projects')).page, PwaPage.projects);
    });
    test('/projects/:id/draft → Draft with id', () {
      final r = PwaRoute.parse(Uri.parse('/projects/abc/draft'));
      expect(r.page, PwaPage.draft);
      expect(r.projectId, 'abc');
    });
    test('/projects/:id/architect(+?vision) → Architect with ids', () {
      final r = PwaRoute.parse(Uri.parse('/projects/abc/architect?vision=v9'));
      expect(r.page, PwaPage.architect);
      expect(r.projectId, 'abc');
      expect(r.visionId, 'v9');
    });
    test('architect without vision query → null visionId', () {
      expect(
        PwaRoute.parse(Uri.parse('/projects/abc/architect')).visionId,
        isNull,
      );
    });
    test('unknown top-level → Home', () {
      expect(PwaRoute.parse(Uri.parse('/whatever')).page, PwaPage.home);
    });
    test('malformed under /projects → Projects', () {
      expect(
        PwaRoute.parse(Uri.parse('/projects/abc/foo')).page,
        PwaPage.projects,
      );
      expect(PwaRoute.parse(Uri.parse('/projects/abc')).page, PwaPage.projects);
    });
  });

  group('location round-trips', () {
    for (final r in [
      PwaRoute.home,
      PwaRoute.projects,
      const PwaRoute(PwaPage.draft, projectId: 'abc'),
      const PwaRoute(PwaPage.architect, projectId: 'abc'),
      const PwaRoute(PwaPage.architect, projectId: 'abc', visionId: 'v9'),
    ]) {
      test('${r.location} parses back to itself', () {
        expect(PwaRoute.parse(Uri.parse(r.location)), r);
      });
    }
  });

  group('normalize (§5 fallback)', () {
    test('ROUTE08: unknown id + non-empty library → Projects', () {
      final r = PwaRoute.normalize(
        const PwaRoute(PwaPage.architect, projectId: 'ghost'),
        lookup: (_) => null,
        libraryEmpty: false,
      );
      expect(r.page, PwaPage.projects);
    });
    test('ROUTE09: unknown id + empty library → Home', () {
      final r = PwaRoute.normalize(
        const PwaRoute(PwaPage.draft, projectId: 'ghost'),
        lookup: (_) => null,
        libraryEmpty: true,
      );
      expect(r.page, PwaPage.home);
    });
    test('ROUTE11: Draft URL for a project WITH visions → Architect', () {
      final p = _project('p1', visions: 2);
      final r = PwaRoute.normalize(
        const PwaRoute(PwaPage.draft, projectId: 'p1'),
        lookup: (id) => id == 'p1' ? p : null,
        libraryEmpty: false,
      );
      expect(r.page, PwaPage.architect);
      expect(r.projectId, 'p1');
    });
    test('ROUTE12: Architect URL for a zero-vision Draft → Draft', () {
      final p = _project('p2', visions: 0);
      final r = PwaRoute.normalize(
        const PwaRoute(PwaPage.architect, projectId: 'p2'),
        lookup: (id) => id == 'p2' ? p : null,
        libraryEmpty: false,
      );
      expect(r.page, PwaPage.draft);
    });
    test('ROUTE06: valid vision query is kept', () {
      final p = _project('p3', visions: 1, visionId: 'keepme');
      final r = PwaRoute.normalize(
        const PwaRoute(PwaPage.architect, projectId: 'p3', visionId: 'keepme'),
        lookup: (id) => id == 'p3' ? p : null,
        libraryEmpty: false,
      );
      expect(r.visionId, 'keepme');
    });
    test('ROUTE07: invalid vision query falls back to no selection', () {
      final p = _project('p4', visions: 1);
      final r = PwaRoute.normalize(
        const PwaRoute(PwaPage.architect, projectId: 'p4', visionId: 'ghost'),
        lookup: (id) => id == 'p4' ? p : null,
        libraryEmpty: false,
      );
      expect(r.page, PwaPage.architect);
      expect(r.visionId, isNull);
    });
  });

  // ── Reveal: a durable URL for ONE vision of ONE project ────────────────────
  group('reveal route', () {
    test('REVEAL01: parses /projects/:id/reveal?vision=:v', () {
      final r = PwaRoute.parse(Uri.parse('/projects/p1/reveal?vision=v9'));
      expect(r.page, PwaPage.reveal);
      expect(r.projectId, 'p1');
      expect(r.visionId, 'v9');
    });

    test('REVEAL02: location round-trips', () {
      const r = PwaRoute(PwaPage.reveal, projectId: 'p1', visionId: 'v9');
      expect(r.location, '/projects/p1/reveal?vision=v9');
      expect(PwaRoute.parse(Uri.parse(r.location)), r);
    });

    test('REVEAL03: a valid vision of THIS project is kept', () {
      final p = _project('p1', visions: 2, visionId: 'vA');
      final out = PwaRoute.normalize(
        const PwaRoute(PwaPage.reveal, projectId: 'p1', visionId: 'vA'),
        lookup: (id) => id == 'p1' ? p : null,
        libraryEmpty: false,
      );
      expect(out.page, PwaPage.reveal);
      expect(out.visionId, 'vA');
    });

    test('REVEAL04: an unknown vision falls back to the conversation — never '
        'silently to another vision', () {
      final p = _project('p1', visions: 2, visionId: 'vA');
      final out = PwaRoute.normalize(
        const PwaRoute(PwaPage.reveal, projectId: 'p1', visionId: 'ghost'),
        lookup: (id) => id == 'p1' ? p : null,
        libraryEmpty: false,
      );
      expect(out.page, PwaPage.architect);
      expect(out.projectId, 'p1');
      expect(out.visionId, isNull);
    });

    test('REVEAL05: a vision belonging to ANOTHER project is refused', () {
      final p1 = _project('p1', visions: 1, visionId: 'vA');
      final p2 = _project('p2', visions: 1, visionId: 'vB');
      final out = PwaRoute.normalize(
        // vB exists — but not in p1.
        const PwaRoute(PwaPage.reveal, projectId: 'p1', visionId: 'vB'),
        lookup: (id) => id == 'p1' ? p1 : (id == 'p2' ? p2 : null),
        libraryEmpty: false,
      );
      expect(out.page, PwaPage.architect);
      expect(out.projectId, 'p1');
    });

    test('REVEAL06: reveal with no query at all → the conversation', () {
      final p = _project('p1', visions: 1, visionId: 'vA');
      final out = PwaRoute.normalize(
        const PwaRoute(PwaPage.reveal, projectId: 'p1'),
        lookup: (id) => id == 'p1' ? p : null,
        libraryEmpty: false,
      );
      expect(out.page, PwaPage.architect);
    });

    test('REVEAL07: reveal on a zero-vision draft → the Draft', () {
      final p = _project('p1');
      final out = PwaRoute.normalize(
        const PwaRoute(PwaPage.reveal, projectId: 'p1', visionId: 'vA'),
        lookup: (id) => id == 'p1' ? p : null,
        libraryEmpty: false,
      );
      expect(out.page, PwaPage.draft);
    });

    test('REVEAL08: unknown project → library, never another project', () {
      final out = PwaRoute.normalize(
        const PwaRoute(PwaPage.reveal, projectId: 'nope', visionId: 'v'),
        lookup: (_) => null,
        libraryEmpty: false,
      );
      expect(out, PwaRoute.projects);
    });
  });

  // ── mode=first is a presentation mode of the SAME vision ──────────────────
  group('first-look reveal mode', () {
    test('FIRST01: parses and round-trips &mode=first', () {
      final r = PwaRoute.parse(
        Uri.parse('/projects/p1/reveal?vision=v9&mode=first'),
      );
      expect(r.page, PwaPage.reveal);
      expect(r.visionId, 'v9');
      expect(r.firstLook, isTrue);
      expect(r.location, '/projects/p1/reveal?vision=v9&mode=first');
      expect(PwaRoute.parse(Uri.parse(r.location)), r);
    });

    test('FIRST02: a plain reveal URL is NOT the first look', () {
      final r = PwaRoute.parse(Uri.parse('/projects/p1/reveal?vision=v9'));
      expect(r.firstLook, isFalse);
      expect(r.location, '/projects/p1/reveal?vision=v9');
      // The two modes are distinct routes for history purposes.
      expect(
        r,
        isNot(
          const PwaRoute(
            PwaPage.reveal,
            projectId: 'p1',
            visionId: 'v9',
            firstLook: true,
          ),
        ),
      );
    });

    test('FIRST03: a valid first-look survives normalization', () {
      final p = _project('p1', visions: 1, visionId: 'vA');
      final out = PwaRoute.normalize(
        const PwaRoute(
          PwaPage.reveal,
          projectId: 'p1',
          visionId: 'vA',
          firstLook: true,
        ),
        lookup: (id) => id == 'p1' ? p : null,
        libraryEmpty: false,
      );
      expect(out.page, PwaPage.reveal);
      expect(out.firstLook, isTrue);
    });

    test('FIRST04: an unknown vision falls back to the conversation, never to '
        'another vision', () {
      final p = _project('p1', visions: 2, visionId: 'vA');
      final out = PwaRoute.normalize(
        const PwaRoute(
          PwaPage.reveal,
          projectId: 'p1',
          visionId: 'ghost',
          firstLook: true,
        ),
        lookup: (id) => id == 'p1' ? p : null,
        libraryEmpty: false,
      );
      expect(out.page, PwaPage.architect);
      expect(out.firstLook, isFalse);
      expect(out.visionId, isNull);
    });

    test('FIRST05: a vision from ANOTHER project is refused', () {
      final p1 = _project('p1', visions: 1, visionId: 'vA');
      final p2 = _project('p2', visions: 1, visionId: 'vB');
      final out = PwaRoute.normalize(
        const PwaRoute(
          PwaPage.reveal,
          projectId: 'p1',
          visionId: 'vB',
          firstLook: true,
        ),
        lookup: (id) => id == 'p1' ? p1 : (id == 'p2' ? p2 : null),
        libraryEmpty: false,
      );
      expect(out.page, PwaPage.architect);
      expect(out.projectId, 'p1');
    });
  });
}
