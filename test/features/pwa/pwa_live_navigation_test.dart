// Batch 3.4b — the state↔route contract that drives live URL sync (LIVE01-12).
//   • canonicalRoute: the durable URL each state maps to (LIVE01-07).
//   • applyRoute: applying a URL back onto the controller (LIVE08-12).
// Pure/controller-level (no browser); the widget-level push/pop wiring is in
// pwa_navigation_widget_test.dart.

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_route.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_mock_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:flutter_test/flutter_test.dart';

AydenImageSource _source() => AydenImageSource(
  bytes: Uint8List.fromList(const [1, 2, 3]),
  filename: 'room.jpg',
  mimeType: 'image/jpeg',
);

PwaVision _vision(String id, String projectId, int n) => PwaVision(
  versionId: id,
  projectId: projectId,
  visionNumber: n,
  title: 'v$n',
  atmosphereId: 'ayden_signature',
  actionType: PwaActionType.signature,
  afterAsset: 'assets/x.jpg',
  order: n,
);

PwaState _state({
  required PwaPhase phase,
  String projectId = 'p1',
  AydenImageSource? source,
  List<PwaVision> versions = const [],
  String? currentVisionId,
  String? previewVisionId,
}) => PwaState(
  phase: phase,
  project: PwaProject(
    projectId: projectId,
    originalAsset: 'assets/x.jpg',
    title: 'P',
  ),
  atmospheres: const [],
  source: source,
  versions: versions,
  currentVisionId: currentVisionId,
  previewVisionId: previewVisionId,
);

PwaController _controller() {
  final repo = MockPwaExperienceRepository(workDelay: Duration.zero);
  return PwaController(
    repo,
    generation: PwaMockGenerationService(repo),
    pending: PwaMemoryPendingGenerationStore(),
  );
}

void main() {
  group('canonicalRoute (LIVE01-07)', () {
    test('LIVE01: an empty creation session → /create', () {
      expect(_state(phase: PwaPhase.entry).canonicalRoute, PwaRoute.create);
    });

    test('LIVE01b: the dashboard → /', () {
      expect(_state(phase: PwaPhase.home).canonicalRoute, PwaRoute.home);
    });

    test(
      'LIVE02: a photo without a vision stays on /create (Step 6A: a pre-Generate creation is NOT a durable Draft URL)',
      () {
        final r = _state(
          phase: PwaPhase.entry,
          source: _source(),
        ).canonicalRoute;
        expect(r.page, PwaPage.create);
      },
    );

    test('LIVE03: architect → /projects/:id/architect (no vision query)', () {
      final r = _state(
        phase: PwaPhase.architect,
        versions: [_vision('v1', 'p1', 1)],
        currentVisionId: 'v1',
      ).canonicalRoute;
      expect(r.page, PwaPage.architect);
      expect(r.projectId, 'p1');
      expect(r.visionId, isNull);
    });

    test('LIVE04: previewing a NON-current vision adds ?vision=', () {
      final r = _state(
        phase: PwaPhase.architect,
        versions: [_vision('v1', 'p1', 1), _vision('v2', 'p1', 2)],
        currentVisionId: 'v2',
        previewVisionId: 'v1',
      ).canonicalRoute;
      expect(r.visionId, 'v1');
      expect(r.location, '/projects/p1/architect?vision=v1');
    });

    test('LIVE05: previewing the CURRENT vision omits the query', () {
      final r = _state(
        phase: PwaPhase.architect,
        versions: [_vision('v2', 'p1', 2)],
        currentVisionId: 'v2',
        previewVisionId: 'v2',
      ).canonicalRoute;
      expect(r.visionId, isNull);
    });

    test('LIVE06: My Projects → /projects', () {
      expect(
        _state(phase: PwaPhase.projects).canonicalRoute,
        PwaRoute.projects,
      );
    });

    test(
      'LIVE07: a session whose first vision is still being made stays on '
      '/create (no durable project URL until it settles)',
      () {
        // The phase is now the Architect from the moment Generate is tapped —
        // the work happens inside the session — but there is no saved project
        // to name until the first vision lands, so the ADDRESS must not claim
        // one. Step 6A, held through the flow change.
        final r = _state(phase: PwaPhase.architect).canonicalRoute;
        expect(r.page, PwaPage.create);
      },
    );

    test('LIVE07b: …and becomes the project URL as soon as it has a vision',
        () {
      final r = _state(
        phase: PwaPhase.architect,
        versions: [_vision('v1', 'p1', 1)],
        currentVisionId: 'v1',
      ).canonicalRoute;
      expect(r.page, PwaPage.architect);
      expect(r.location, '/projects/p1/architect');
    });
  });

  group('applyRoute (LIVE08-12)', () {
    test('LIVE08: applyRoute(projects) → My Projects', () {
      final c = _controller();
      c.applyRoute(PwaRoute.projects);
      expect(c.state.phase, PwaPhase.projects);
      expect(c.state.canonicalRoute, PwaRoute.projects);
    });

    test('LIVE09: applyRoute(home) → the dashboard, session dropped', () {
      final c = _controller();
      c.openLibrary();
      c.applyRoute(PwaRoute.home);
      expect(c.state.phase, PwaPhase.home);
      expect(c.state.source, isNull);
      expect(c.state.canonicalRoute, PwaRoute.home);
    });

    test('LIVE09b: applyRoute(create) opens an EMPTY Create', () {
      final c = _controller();
      c.applyRoute(PwaRoute.create);
      expect(c.state.phase, PwaPhase.entry);
      expect(c.state.source, isNull);
      expect(c.state.canonicalRoute, PwaRoute.create);
    });

    test('LIVE10: applyRoute(architect,id) opens THAT project', () {
      final c = _controller();
      c.openLibrary();
      final p = c.state.library.firstWhere((x) => x.visions.isNotEmpty);
      c.applyRoute(PwaRoute(PwaPage.architect, projectId: p.projectId));
      expect(c.state.phase, PwaPhase.architect);
      expect(c.state.activeProjectId, p.projectId);
    });

    test('LIVE11: applyRoute with a valid ?vision= restores that preview', () {
      final c = _controller();
      c.openLibrary();
      final p = c.state.library.firstWhere((x) => x.visions.length >= 2);
      final older = p.visions.first.versionId; // current is the last
      c.applyRoute(
        PwaRoute(PwaPage.architect, projectId: p.projectId, visionId: older),
      );
      expect(c.state.previewVisionId, older);
      expect(c.state.canonicalRoute.visionId, older);
    });

    test('LIVE12: applyRoute is idempotent (re-applying is stable)', () {
      final c = _controller();
      c.applyRoute(PwaRoute.projects);
      c.applyRoute(PwaRoute.projects);
      expect(c.state.phase, PwaPhase.projects);
      final p = c.state.library.firstWhere((x) => x.visions.isNotEmpty);
      final route = PwaRoute(PwaPage.architect, projectId: p.projectId);
      c.applyRoute(route);
      c.applyRoute(route);
      expect(c.state.phase, PwaPhase.architect);
      expect(c.state.activeProjectId, p.projectId);
    });
  });
}
