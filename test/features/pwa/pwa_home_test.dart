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
const _newSessionKey = ValueKey('pwa-home-new-session');
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
  // The Home hero is a `RevealHero`, and its auto-sweep arms a
  // `Future.delayed(800ms)` that outlives disposal — the framework then fails
  // the test with "A Timer is still pending". That delay lives in the SHARED,
  // FROZEN reveal widget (iOS uses the identical one), so the test advances
  // past it rather than the product weakening its own animation for a harness.
  await tester.pump(const Duration(seconds: 1));
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

    testWidgets("it opens on the person's OWN most recent work", (
      tester,
    ) async {
      // REVERSED DELIBERATELY. This used to assert the opposite — a stock
      // brand hero, and explicitly NO featured slot. iOS parity changed the
      // product decision: a returning customer should see the room they were
      // working on, not a stranger's apartment. The assertion is kept just as
      // strong, pointing the other way.
      final (c, _) = await _pump(tester);
      final visible = c.read(pwaControllerProvider).visibleProjects;
      expect(visible, isNotEmpty);

      expect(find.byKey(const ValueKey('pwa-home-hero')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-home-featured')), findsOneWidget);
      // The showcase fallback must NOT be used when real work exists.
      expect(find.byKey(const ValueKey('pwa-home-showcase')), findsNothing);

      // The hero is that project — its room and atmosphere, not a slogan.
      final top = visible.first;
      expect(find.text('${top.roomLabel} · ${top.atmosphereLabel}'),
          findsOneWidget);
      expect(find.text(top.title), findsOneWidget);
    });

    testWidgets('the hero IS the continuation — no duplicate grid', (
      tester,
    ) async {
      // REVERSED DELIBERATELY. The old Home carried three competing blocks:
      // a stock hero with two CTAs, a "Continue designing" grid, and a second
      // full-width "New project" panel. Two said the same thing and the third
      // duplicated Projects. Tapping the Featured Vision now reopens that
      // project, so the grid has no job left.
      final (c, _) = await _pump(tester);
      final visible = c.read(pwaControllerProvider).visibleProjects;
      expect(visible.length, greaterThan(1));

      expect(find.byKey(const ValueKey('pwa-home-continue')), findsNothing);
      expect(find.text('CONTINUE DESIGNING'), findsNothing);

      // Deduplication still holds where it matters — the hero leads with the
      // most recent, and it appears exactly once.
      final ids = visible.map((p) => p.projectId).toList();
      expect(ids.toSet().length, ids.length);
      expect(find.text(visible.first.title), findsOneWidget);
      // A second project's title must NOT also be on Home: that was the grid.
      expect(find.text(visible[1].title), findsNothing);
    });

    testWidgets('the dashboard is not the library: the NAV links out', (
      tester,
    ) async {
      // The "See all" link is gone with the grid it captioned. Projects is now
      // a permanent destination in the bottom navigation — a stronger
      // affordance than a text link that only existed when history did.
      final (c, bridge) = await _pump(tester);

      // The invariant the old test really protected: a Featured Vision is only
      // ever built from a project that genuinely has a cover of its own.
      final featured = c.read(pwaControllerProvider).visibleProjects.first;
      expect(featured.visions, isNotEmpty);
      expect(featured.coverVision, isNotNull);
      expect(featured.coverVision!.projectId, featured.projectId);

      expect(find.byKey(_viewAllKey), findsNothing);
      await tester.tap(find.text('Projects'));
      await tester.pump();
      expect(c.read(pwaControllerProvider).phase, PwaPhase.projects);
      expect(bridge.current().path, '/projects');
    });

    testWidgets('with no project it falls back to the shared showcase', (
      tester,
    ) async {
      await _pump(tester, seed: false);
      expect(find.byKey(const ValueKey('pwa-home-hero')), findsOneWidget);
      // The SAME curated list iOS's own hero uses — a genuine before/after
      // pair, not two unrelated photographs.
      expect(find.byKey(const ValueKey('pwa-home-showcase')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-home-featured')), findsNothing);
      // Still no section pretending there is history.
      expect(find.byKey(const ValueKey('pwa-home-continue')), findsNothing);
      expect(find.text('CONTINUE DESIGNING'), findsNothing);
    });

    testWidgets('opening a card goes straight to that project conversation', (
      tester,
    ) async {
      final (c, bridge) = await _pump(tester);
      final target = c.read(pwaControllerProvider).visibleProjects.first;
      // The Featured Vision IS the way back into the work — tapping the hero
      // reopens that project. This is what replaced the Continue grid.
      await tester.tap(find.byKey(const ValueKey('pwa-home-featured')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.architect);
      expect(s.activeProjectId, target.projectId);
      expect(bridge.current().path, '/projects/${target.projectId}/architect');
    });

    // ONE entry point, not three. The old Home offered New Project from the
    // top bar, from inside the hero, AND from a closing block — three controls
    // for one action, which is what made the page feel like a dashboard. iOS
    // has a single sticky CTA above the nav, and so does this now.
    testWidgets('New Design Session is the one way in, and it is empty', (
      tester,
    ) async {
      final (c, bridge) = await _pump(tester);

      expect(find.byKey(_newSessionKey), findsOneWidget);
      // The retired duplicates must not come back.
      expect(find.byKey(const ValueKey('pwa-hero-new-project')), findsNothing);
      expect(find.byKey(const ValueKey('pwa-home-new-project-large')),
          findsNothing);

      await tester.tap(find.byKey(_newSessionKey));
      await tester.pumpAndSettle();
      expect(c.read(pwaControllerProvider).phase, PwaPhase.entry);
      expect(c.read(pwaControllerProvider).hasSource, isFalse);
      expect(bridge.current().path, '/create');
    });
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
      // Re-mounting Home arms a fresh hero auto-sweep; drain it (see _pump).
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(_newSessionKey));
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
      // Landing on Home arms the hero auto-sweep; drain it (see _pump).
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('history after Generate', () {
    testWidgets('Back from a new project returns Home, never to a filled '
        'Create', (tester) async {
      final (c, bridge) = await _pump(tester, seed: false);
      final ctl = c.read(pwaControllerProvider.notifier);

      await tester.tap(find.byKey(_newSessionKey));
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
      await tester.pump(const Duration(seconds: 1)); // hero sweep, see _pump
      // The hero caption is "<room> · <atmosphere>", so a placeholder room
      // would now be MORE visible than before, not less.
      expect(find.textContaining('Your space'), findsNothing);
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
      await tester.pump(const Duration(seconds: 1)); // hero sweep, see _pump
      expect(c.read(pwaControllerProvider).visibleProjects, hasLength(1));
      // ONE project is enough to earn the real hero — the showcase fallback
      // is only for someone with nothing of their own.
      expect(find.byKey(const ValueKey('pwa-home-hero')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-home-featured')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-home-showcase')), findsNothing);
      // And the page is still complete: headline, hero, the single CTA, nav.
      expect(find.byKey(_newSessionKey), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-home-continue')), findsNothing);
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

    testWidgets('the hero cinematic is RETIRED from Home — recorded, not lost', (
      tester,
    ) async {
      // A DELIBERATE CONSEQUENCE, pinned so it cannot be forgotten.
      //
      // "See how it works" replayed `PwaHeroSequence` — a video that lived in
      // the Home hero. Phase 2 gives that slot to the Featured Vision, which
      // the approved brief requires, so the cinematic has nowhere left to
      // play. The gate, the sequence and the video widgets are all still in
      // the tree (`pwa_intro_gate.dart`, `hero/`) and still unit-tested above;
      // only the Home entry point is gone.
      //
      // This is a product loss awaiting a decision on where an explainer
      // should live — not an oversight. If it comes back as a header action or
      // its own route, replace this test with one that exercises it.
      final (c, bridge) = await _pump(tester);
      expect(find.byKey(const ValueKey('pwa-replay-intro')), findsNothing);
      expect(find.text('See how it works'), findsNothing);

      // What must remain true either way: Home is immediate, nothing covers
      // the page, and the library is untouched by rendering it.
      expect(c.read(pwaControllerProvider).phase, PwaPhase.home);
      expect(bridge.current().path, '/');
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
