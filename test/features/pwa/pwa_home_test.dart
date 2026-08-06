// The Home dashboard — `/` is the front door, Create is a deliberate step.
//
// These tests encode the two rules the dashboard exists to enforce:
//   • it shows only projects a user can actually open (the same filter the full
//     library uses), so a legacy zero-vision row can never surface as a black
//     card;
//   • starting something new always opens an EMPTY Create, and generating from
//     it replaces `/create` in history — so browser Back returns Home, never to
//     a Create still holding the photo that has just become a project.
//
// Deterministic: in-memory history bridge + offline mock repo, no browser.

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_route.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_url_bridge.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_home_screen.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_mock_app.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_url_sync_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _homeKey = ValueKey('pwa-home');
const _createKey = ValueKey('pwa-create');
const _emptyKey = ValueKey('pwa-home-empty');
const _newProjectKey = ValueKey('pwa-home-new-project');
const _viewAllKey = ValueKey('pwa-home-view-all');

AydenImageSource _fake() => AydenImageSource(
  bytes: Uint8List.fromList(const [1, 2, 3, 4]),
  filename: 'room.jpg',
);

Future<(ProviderContainer, FakePwaUrlBridge)> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  bool seed = true,
  String at = '/',
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final bridge = FakePwaUrlBridge(at);
  final container = ProviderContainer(
    overrides: [
      pwaRepositoryProvider.overrideWithValue(
        MockPwaExperienceRepository(
          workDelay: Duration.zero,
          seedLibrary: seed,
        ),
      ),
      pwaUrlBridgeProvider.overrideWithValue(bridge),
      // The real boot resolves the URL BEFORE the first frame (main_pwa does
      // this); reproduce that here so a direct URL is honoured.
      if (at != '/')
        pwaBootRestoreProvider.overrideWithValue(
          PwaBootRestore(
            library: const [],
            route: PwaRoute.parse(Uri.parse(at)),
          ),
        ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const PwaUrlSyncScope(child: PwaMockApp()),
    ),
  );
  await tester.pump();
  return (container, bridge);
}

void main() {
  group('the dashboard is the front door', () {
    testWidgets('`/` shows the Home, not the Create screen', (tester) async {
      final (c, bridge) = await _pump(tester);
      expect(find.byKey(_homeKey), findsOneWidget);
      expect(find.byKey(_createKey), findsNothing);
      expect(c.read(pwaControllerProvider).phase, PwaPhase.home);
      expect(bridge.current().path, '/');
    });

    testWidgets('it opens on the brand promise, not on a project', (
      tester,
    ) async {
      await _pump(tester);
      // The hero sells what Ayden does; it never shows someone's last project.
      expect(find.byKey(const ValueKey('pwa-home-hero')), findsOneWidget);
      expect(find.textContaining('Your home.'), findsOneWidget);
      expect(find.text('See how it works'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pwa-hero-new-project')),
        findsOneWidget,
      );
      // …and there is no "featured" slot competing with the list below it.
      expect(find.byKey(const ValueKey('pwa-home-featured')), findsNothing);
    });

    testWidgets('projects appear once, in one flat list', (tester) async {
      final (c, _) = await _pump(tester);
      final visible = c.read(pwaControllerProvider).visibleProjects;
      expect(visible.length, greaterThan(1));
      expect(find.byKey(const ValueKey('pwa-home-continue')), findsOneWidget);
      expect(find.text('CONTINUE DESIGNING'), findsOneWidget);
      // No project id twice, and the most recent one leads.
      final ids = visible.map((p) => p.projectId).toList();
      expect(ids.toSet().length, ids.length);
      expect(find.text(visible.first.title), findsOneWidget);
    });

    testWidgets('the dashboard is not the library: it caps and links out', (
      tester,
    ) async {
      final (c, bridge) = await _pump(tester);
      final shown = c
          .read(pwaControllerProvider)
          .visibleProjects
          .take(kPwaHomeProjectCount);
      for (final p in shown) {
        expect(p.visions, isNotEmpty);
        expect(p.coverVision, isNotNull);
        expect(p.coverVision!.projectId, p.projectId);
      }
      await tester.ensureVisible(find.byKey(_viewAllKey));
      await tester.tap(find.byKey(_viewAllKey));
      await tester.pump();
      expect(c.read(pwaControllerProvider).phase, PwaPhase.projects);
      expect(bridge.current().path, '/projects');
    });

    testWidgets('with no project it shows the promise and one way in', (
      tester,
    ) async {
      await _pump(tester, seed: false);
      expect(find.byKey(const ValueKey('pwa-home-hero')), findsOneWidget);
      expect(find.byKey(_emptyKey), findsOneWidget);
      expect(find.text('Create your first vision'), findsOneWidget);
      // No empty "Continue designing" section pretending there is history.
      expect(find.byKey(const ValueKey('pwa-home-continue')), findsNothing);
      expect(find.text('CONTINUE DESIGNING'), findsNothing);
    });

    testWidgets('opening a card goes straight to that project conversation', (
      tester,
    ) async {
      final (c, bridge) = await _pump(tester);
      final target = c.read(pwaControllerProvider).visibleProjects.first;
      // The list sits below the hero: bring it into view like a user would.
      await tester.ensureVisible(find.text(target.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(target.title));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.architect);
      expect(s.activeProjectId, target.projectId);
      expect(bridge.current().path, '/projects/${target.projectId}/architect');
    });

    // One test per entry point: re-pumping a second app into the same tester
    // reuses the sync-scope State, which would keep the first history bridge.
    for (final entry in const [
      ('the top bar', ValueKey('pwa-home-new-project')),
      ('the hero', ValueKey('pwa-hero-new-project')),
      ('the closing block', ValueKey('pwa-home-new-project-large')),
    ]) {
      testWidgets('New Project from ${entry.$1} opens an empty Create', (
        tester,
      ) async {
        final (c, bridge) = await _pump(tester);
        await tester.ensureVisible(find.byKey(entry.$2));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(entry.$2));
        await tester.pumpAndSettle();
        expect(c.read(pwaControllerProvider).phase, PwaPhase.entry);
        expect(c.read(pwaControllerProvider).hasSource, isFalse);
        expect(bridge.current().path, '/create');
      });
    }
  });

  group('New Project always opens an empty Create', () {
    testWidgets('it navigates to /create with nothing carried over', (
      tester,
    ) async {
      final (c, bridge) = await _pump(tester);
      final ctl = c.read(pwaControllerProvider.notifier);
      // Dirty a previous creation session first.
      ctl.newProject();
      ctl.setSource(_fake());
      ctl.selectRoom('kitchen');
      await tester.pump();
      expect(c.read(pwaControllerProvider).hasSource, isTrue);

      ctl.openHome();
      await tester.pump();
      await tester.tap(find.byKey(_newProjectKey).first);
      await tester.pump();

      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.entry);
      expect(find.byKey(_createKey), findsOneWidget);
      expect(s.hasSource, isFalse);
      expect(s.selectedRoomId, isNull); // Ayden Decide
      expect(s.selectedAtmosphereId, 'ayden_signature');
      expect(bridge.current().path, '/create');
    });

    testWidgets('a direct /create URL opens an empty Create', (tester) async {
      final (c, _) = await _pump(tester, at: '/create');
      expect(c.read(pwaControllerProvider).phase, PwaPhase.entry);
      expect(c.read(pwaControllerProvider).hasSource, isFalse);
      expect(find.byKey(_createKey), findsOneWidget);
    });

    testWidgets('Create offers the way back home', (tester) async {
      final (c, bridge) = await _pump(tester, at: '/create');
      await tester.tap(find.byKey(const ValueKey('pwa-create-home')));
      await tester.pump();
      expect(c.read(pwaControllerProvider).phase, PwaPhase.home);
      expect(bridge.current().path, '/');
    });
  });

  group('history after Generate', () {
    testWidgets('Back from a new project returns Home, never to a filled '
        'Create', (tester) async {
      final (c, bridge) = await _pump(tester, seed: false);
      final ctl = c.read(pwaControllerProvider.notifier);

      await tester.tap(find.byKey(_newProjectKey).first);
      await tester.pump();
      expect(bridge.current().path, '/create');

      ctl.setSource(_fake());
      await ctl.generateFirstVision();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      final id = c.read(pwaControllerProvider).activeProjectId;
      // Generate unveils the vision first, replacing /create in history…
      expect(bridge.current().path, '/projects/$id/reveal');
      expect(bridge.current().queryParameters['mode'], 'first');
      // …then Continue supersedes the unveiling with the conversation.
      ctl.continueToArchitect();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(bridge.current().path, '/projects/$id/architect');
      expect(bridge.ops, contains('replace:/projects/$id/architect'));

      bridge.back();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(bridge.current().path, '/');
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.home);
      expect(s.hasSource, isFalse, reason: 'Back must not restore the photo');
      // The generated project survived and is listed on the dashboard.
      expect(s.visibleProjects.any((p) => p.projectId == id), isTrue);
    });
  });

  group('route model', () {
    test('HOME01: `/` parses and round-trips', () {
      expect(PwaRoute.parse(Uri.parse('/')), PwaRoute.home);
      expect(PwaRoute.home.location, '/');
    });

    test('HOME02: `/create` parses and round-trips', () {
      expect(PwaRoute.parse(Uri.parse('/create')), PwaRoute.create);
      expect(PwaRoute.create.location, '/create');
    });

    test('HOME03: create needs no durable library to be valid', () {
      final out = PwaRoute.normalize(
        PwaRoute.create,
        lookup: (_) => null,
        libraryEmpty: true,
      );
      expect(out, PwaRoute.create);
    });
  });

  group('composition', () {
    testWidgets('the generic placeholder room label is never shown', (
      tester,
    ) async {
      final (c, _) = await _pump(tester, seed: false);
      final ctl = c.read(pwaControllerProvider.notifier);
      ctl.newProject();
      ctl.setSource(_fake()); // no Room chosen → repository says "Your space"
      await ctl.generateFirstVision();
      ctl.continueToArchitect();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      ctl.openHome();
      await tester.pumpAndSettle();
      // Exact match only: the hero legitimately reads "Your home. Reimagined."
      expect(find.text('Your space'), findsNothing);
    });

    testWidgets('a single project still gets the full page structure', (
      tester,
    ) async {
      final (c, _) = await _pump(tester, seed: false);
      final ctl = c.read(pwaControllerProvider.notifier);
      ctl.newProject();
      ctl.setSource(_fake());
      await ctl.generateFirstVision();
      ctl.continueToArchitect();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      ctl.openHome();
      await tester.pumpAndSettle();
      expect(c.read(pwaControllerProvider).visibleProjects, hasLength(1));
      expect(find.byKey(const ValueKey('pwa-home-hero')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-home-continue')), findsOneWidget);
      // The closing CTA is the "new" block now, not the empty state.
      expect(find.byKey(const ValueKey('pwa-home-new-block')), findsOneWidget);
      expect(find.byKey(_emptyKey), findsNothing);
    });

    for (final size in const [
      Size(1440, 900),
      Size(1536, 864),
      Size(1920, 1080),
      Size(768, 1024),
      Size(390, 844),
    ]) {
      testWidgets(
        'no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pump(tester, size: size);
          expect(find.byKey(_homeKey), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // ── The full-screen cinematic ────────────────────────────────────────────
  group('intro overlay', () {
    test('it plays once per tab, only where video can actually play', () {
      // First normal arrival on a real browser with motion allowed.
      expect(
        pwaShouldPlayIntro(isWeb: true, reduceMotion: false, gateAllows: true),
        isTrue,
      );
      // F5 in the same tab: the gate has the marker, so no replay.
      expect(
        pwaShouldPlayIntro(isWeb: true, reduceMotion: false, gateAllows: false),
        isFalse,
      );
      // Reduced motion and non-web never autoplay.
      expect(
        pwaShouldPlayIntro(isWeb: true, reduceMotion: true, gateAllows: true),
        isFalse,
      );
      expect(
        pwaShouldPlayIntro(isWeb: false, reduceMotion: false, gateAllows: true),
        isFalse,
      );
    });

    testWidgets('there is no full-screen cinematic — the Home is immediate', (
      tester,
    ) async {
      await _pump(tester);
      // Opening or refreshing '/' shows the dashboard straight away; the
      // transformation plays inside the hero, never over the page.
      expect(find.byKey(_homeKey), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-home-hero')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-intro-skip')), findsNothing);
      expect(find.text('Tap to skip'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"See how it works" replays in the hero, on the same page', (
      tester,
    ) async {
      final (c, bridge) = await _pump(tester);
      final before = c.read(pwaControllerProvider).library.length;
      await tester.tap(find.byKey(const ValueKey('pwa-replay-intro')));
      await tester.pumpAndSettle();
      expect(c.read(pwaControllerProvider).phase, PwaPhase.home);
      expect(c.read(pwaControllerProvider).library, hasLength(before));
      expect(bridge.current().path, '/');
      // The hero is still there and nothing ever covered the page.
      expect(find.byKey(const ValueKey('pwa-home-hero')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-intro-skip')), findsNothing);
    });

    for (final at in const ['/create', '/projects']) {
      testWidgets('a direct $at URL is never gated by the cinematic', (
        tester,
      ) async {
        await _pump(tester, at: at);
        expect(find.byKey(_homeKey), findsNothing);
        expect(find.text('Tap to skip'), findsNothing);
      });
    }
  });
}
