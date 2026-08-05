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
}
