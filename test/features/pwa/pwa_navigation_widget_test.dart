// Batch 3.4b — live URL sync + Replay-intro control at the widget level.
//   • state → browser URL (push), and Back/Forward → state (LIVE / HISTORY);
//   • the "Replay intro" control on the final hero (INTRO06/07/09).
// Deterministic: an in-memory history bridge + the offline mock repo, no browser.

import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_intro_gate.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_url_bridge.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_mock_app.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_url_sync_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _replayKey = ValueKey('pwa-replay-intro');

Future<(ProviderContainer, FakePwaUrlBridge)> _pump(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  PwaIntroGate? gate,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final bridge = FakePwaUrlBridge('/');
  final container = ProviderContainer(
    overrides: [
      pwaRepositoryProvider.overrideWithValue(
        MockPwaExperienceRepository(workDelay: Duration.zero),
      ),
      pwaUrlBridgeProvider.overrideWithValue(bridge),
      if (gate != null) pwaIntroGateProvider.overrideWithValue(gate),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const PwaUrlSyncScope(child: PwaMockApp()),
    ),
  );
  await tester.pump(); // first frame + post-frame URL normalization
  return (container, bridge);
}

void main() {
  testWidgets('LIVE: opening My Projects pushes /projects', (tester) async {
    final (container, bridge) = await _pump(tester);
    container.read(pwaControllerProvider.notifier).openLibrary();
    await tester.pump();
    expect(bridge.current().path, '/projects');
    expect(bridge.ops, contains('push:/projects'));
  });

  testWidgets('LIVE: opening a project pushes its architect URL', (
    tester,
  ) async {
    final (container, bridge) = await _pump(tester);
    final c = container.read(pwaControllerProvider.notifier);
    c.openLibrary();
    await tester.pump();
    final p = container
        .read(pwaControllerProvider)
        .library
        .firstWhere((x) => x.visions.isNotEmpty);
    c.openProject(p.projectId);
    await tester.pump();
    expect(bridge.current().path, '/projects/${p.projectId}/architect');
    expect(bridge.ops.last, 'push:/projects/${p.projectId}/architect');
    await tester.pump(const Duration(seconds: 3)); // drain reveal sweep timers
  });

  testWidgets('HISTORY: Back applies the previous URL to the controller', (
    tester,
  ) async {
    final (container, bridge) = await _pump(tester);
    final c = container.read(pwaControllerProvider.notifier);
    c.openLibrary();
    await tester.pump();
    final p = container
        .read(pwaControllerProvider)
        .library
        .firstWhere((x) => x.visions.isNotEmpty);
    c.openProject(p.projectId);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3)); // drain reveal sweep timers
    // Browser Back → popstate → applyRoute → back to My Projects.
    bridge.back();
    await tester.pump();
    expect(container.read(pwaControllerProvider).phase, PwaPhase.projects);
    expect(bridge.current().path, '/projects');
  });

  testWidgets('HISTORY: no runaway push loop on Back (idempotent)', (
    tester,
  ) async {
    final (container, bridge) = await _pump(tester);
    final c = container.read(pwaControllerProvider.notifier);
    c.openLibrary();
    await tester.pump();
    final before = bridge.ops.length;
    bridge.back(); // → '/', applyRoute(home)
    await tester.pump();
    await tester.pump();
    // Back must not trigger a fresh push of the same location (loop guard).
    expect(
      bridge.ops.where((o) => o.startsWith('push:/projects')),
      hasLength(1),
    );
    expect(bridge.ops.length, lessThanOrEqualTo(before + 1));
  });

  testWidgets(
    'REGRESSION sync-loop-1: Back to My Projects is not a trap (second Back reaches Home)',
    (tester) async {
      final (container, bridge) = await _pump(tester);
      final c = container.read(pwaControllerProvider.notifier);
      c.openLibrary();
      await tester.pump();
      final p = container
          .read(pwaControllerProvider)
          .library
          .firstWhere((x) => x.visions.isNotEmpty);
      c.openProject(p.projectId); // has visions → openLibrary later saves first
      await tester.pump();
      await tester.pump(const Duration(seconds: 3)); // drain reveal timers
      // history: [/, /projects, /projects/<id>/architect]
      final opsBefore = bridge.ops.length;
      bridge.back(); // → /projects
      await tester.pump();
      expect(container.read(pwaControllerProvider).phase, PwaPhase.projects);
      // The intermediate `architect` state during openLibrary must NOT drive the
      // URL: no push/replace of the architect route may occur on this Back.
      final newOps = bridge.ops.sublist(opsBefore);
      expect(
        newOps.where((o) => o.contains('architect')),
        isEmpty,
        reason: 'Back must not touch the architect URL: $newOps',
      );
      // Second Back must reach Home — not bounce back into the project.
      bridge.back();
      await tester.pump();
      expect(container.read(pwaControllerProvider).phase, PwaPhase.home);
      expect(bridge.current().path, '/');
    },
  );

  testWidgets(
    'REGRESSION canonical-roundtrip-1: Back onto a now-current ?vision drops the stale query',
    (tester) async {
      final (container, bridge) = await _pump(tester);
      final c = container.read(pwaControllerProvider.notifier);
      c.openLibrary();
      await tester.pump();
      final p = container
          .read(pwaControllerProvider)
          .library
          .firstWhere((x) => x.visions.length >= 2);
      c.openProject(p.projectId);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      final older = p.visions.first.versionId; // non-current
      c.previewVision(older);
      await tester.pump();
      expect(bridge.current().queryParameters['vision'], older);
      c.setCurrentVision(older); // now `older` is the current vision
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(bridge.current().query, isEmpty);
      // Back → popstate to ?vision=older (now == current) → applyRoute is a no-op,
      // but the reconcile must still drop the stale query the state no longer maps to.
      bridge.back();
      await tester.pump();
      expect(
        bridge.current().query,
        isEmpty,
        reason: 'stale ?vision must reconcile away: ${bridge.current()}',
      );
    },
  );

  testWidgets('INTRO06: the dashboard offers a "See how it works" control', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 400)); // settle opacity
    expect(find.byKey(_replayKey), findsOneWidget);
    expect(find.text('See how it works'), findsOneWidget);
  });

  testWidgets('INTRO07: tapping Replay stays on Home and keeps projects', (
    tester,
  ) async {
    final (container, bridge) = await _pump(tester);
    await tester.pump(const Duration(milliseconds: 400));
    final libBefore = container.read(pwaControllerProvider).library.length;
    await tester.tap(find.byKey(_replayKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(pwaControllerProvider).phase, PwaPhase.home);
    expect(container.read(pwaControllerProvider).library, hasLength(libBefore));
    expect(bridge.current().path, '/'); // never leaves Home
    // Repeatable — a second replay must not throw.
    await tester.tap(find.byKey(_replayKey));
    await tester.pump();
    expect(find.byKey(_replayKey), findsOneWidget);
  });

  testWidgets('INTRO09: Replay does NOT clear the once-per-tab marker', (
    tester,
  ) async {
    final store = MemoryPwaSessionStore()
      ..write(
        PwaIntroGate.kMarkerKey,
        '1',
      ); // marker already present (post-first-play)
    final gate = PwaIntroGate(store);
    await _pump(tester, gate: gate);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(_replayKey));
    await tester.pump();
    // The explicit replay must leave the marker intact → next boot won't autoplay.
    expect(store.read(PwaIntroGate.kMarkerKey), isNotNull);
    expect(gate.shouldAutoplay(), isFalse);
  });
}
