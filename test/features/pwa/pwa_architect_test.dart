// Ayden Architect (chat-first) + Full Reveal widget tests. Deterministic
// (zero-delay mock), offline.
//
// The product rule these tests encode is ONE SCREEN = ONE MAIN PURPOSE:
//   • `/architect` is the conversation. It holds messages and vision cards, and
//     nothing else — no Before/After canvas, no atmosphere rail, no vision
//     stepper. Those all moved to the Reveal.
//   • `/reveal` is exploration. It holds the Before/After, the details panel,
//     the atmosphere rail and the vision stepper — and never a second chat.
//
// Note: the widget-test font renders text far wider than the production font, so
// a conversation that fits one viewport in a browser overflows here. Tests
// therefore scroll targets into view rather than assuming a single fold.

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_architect_screen.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_theme.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_render_aspect.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_render_canvas.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_brand.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_widgets.dart';
import 'package:ai_home_architect/shared/widgets/reveal_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';

AydenImageSource _fake() => AydenImageSource(
  bytes: Uint8List.fromList(const [1, 2, 3, 4]),
  filename: 'room.jpg',
);

const _headerKey = ValueKey('av7-global-header');
const _feedKey = ValueKey('av7-chat-feed');
const _revealHeaderKey = ValueKey('pwa-reveal-header');

Future<ProviderContainer> _pumpArchitect(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      pwaRepositoryProvider.overrideWithValue(
        MockPwaExperienceRepository(workDelay: Duration.zero),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PwaExperience()),
    ),
  );
  final c = container.read(pwaControllerProvider.notifier);
  c.setSource(_fake());
  await c.generateFirstVision();
  // Generate now unveils the first vision full-screen; these tests are about
  // what comes after, so step through it exactly as a user would.
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  return container;
}

Finder _feed() => find
    .descendant(of: find.byKey(_feedKey), matching: find.byType(Scrollable))
    .first;

/// Scroll [target] into view down the conversation, then settle.
Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    220.0,
    scrollable: _feed(),
    maxScrolls: 60,
  );
  await tester.pumpAndSettle();
}

Future<void> _addSecondVision(WidgetTester tester, ProviderContainer c) async {
  final ctl = c.read(pwaControllerProvider.notifier);
  ctl.stageAtmosphere('soft_luxury');
  await ctl.applyAtmosphere();
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
}

/// Move to the Full Reveal for the current vision and drain its sweep timers.
Future<void> _openReveal(WidgetTester tester, ProviderContainer c) async {
  final id = c.read(pwaControllerProvider).currentVision!.versionId;
  c.read(pwaControllerProvider.notifier).openReveal(id);
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
}

/// Generate a first vision WITHOUT stepping past the unveiling.
Future<ProviderContainer> _pumpFirstReveal(
  WidgetTester tester,
  Size size,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      pwaRepositoryProvider.overrideWithValue(
        MockPwaExperienceRepository(workDelay: Duration.zero),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PwaExperience()),
    ),
  );
  final c = container.read(pwaControllerProvider.notifier);
  c.setSource(_fake());
  await c.generateFirstVision();
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  return container;
}

void main() {
  // ── Architect is the conversation, and only the conversation ───────────────
  group('Architect chat-first', () {
    testWidgets('no Before/After canvas, no atmosphere rail, no stepper', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      // The reveal engine is absent from the conversation entirely.
      expect(find.byType(PwaRevealCard), findsNothing);
      expect(find.byType(RevealHero), findsNothing);
      // The atmosphere rail lives on the Reveal now.
      expect(find.text('ATMOSPHERE'), findsNothing);
      expect(find.text('ATMOSPHERES'), findsNothing);
      // And there is exactly zero vision stepper on this screen.
      expect(find.textContaining('Vision 1 of'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('header keeps Back home + My Projects, drops the counter', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      expect(find.byKey(_headerKey), findsOneWidget);
      expect(find.text('AYDEN STUDIO'), findsOneWidget);
      expect(find.text('Back home'), findsOneWidget);
      expect(find.byKey(const ValueKey('av7-projects-button')), findsOneWidget);
      expect(find.textContaining(' of '), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop keeps the whole chat on one reading measure', (
      tester,
    ) async {
      // This used to assert that a glass PLATE contained the header, the
      // thread and the composer. The plate is gone with the photograph it
      // floated on; what it was really protecting — that the three share one
      // left edge instead of drifting apart across a wide window — is what is
      // asserted now.
      await _pumpArchitect(tester, const Size(1920, 1080));
      final header = tester.getRect(
        find.byKey(const ValueKey('av7-conversation-header')),
      );
      final feed = tester.getRect(find.byKey(_feedKey));
      final field = tester.getRect(find.byType(TextField));
      expect(header.left, closeTo(feed.left, 1));
      expect(header.width, lessThanOrEqualTo(kPwaChatColumnMax + 1));
      expect(feed.width, lessThanOrEqualTo(kPwaChatColumnMax + 1));
      expect(field.left, greaterThanOrEqualTo(feed.left - 40));
      expect(field.right, lessThanOrEqualTo(feed.right + 40));
      expect(tester.takeException(), isNull);
    });

    testWidgets('every vision carries a visible expand affordance', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      final id = c.read(pwaControllerProvider).currentVision!.versionId;
      final expand = find.byKey(const ValueKey('av7-vision-expand'));
      await _reveal(tester, expand);
      expect(expand, findsOneWidget);
      // A comfortable touch target, and the SAME destination as the image and
      // the button.
      expect(tester.getSize(expand).width, greaterThanOrEqualTo(40));
      await tester.tap(expand);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.reveal);
      expect(s.previewedVision!.versionId, id);
      expect(tester.takeException(), isNull);
    });

    testWidgets('conversation column is centred and capped for reading', (
      tester,
    ) async {
      const size = Size(1920, 1080);
      await _pumpArchitect(tester, size);
      final feed = tester.getRect(find.byKey(_feedKey));
      expect(feed.width, lessThanOrEqualTo(kPwaChatColumnMax + 1));
      // Centred: equal gutters either side.
      expect(feed.left, closeTo(size.width - feed.right, 2.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('user messages align right, Ayden aligns left', (tester) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      c.read(pwaControllerProvider.notifier).sendUserText('Move the sofa left');
      await tester.pump();
      // Bounded pumps rather than pumpAndSettle: while a generation runs the
      // working indicator animates continuously by design, so there is never a
      // settled frame to wait for.
      await tester.pump(const Duration(seconds: 3));
      final user = find.text('Move the sofa left');
      await _reveal(tester, user);
      final feed = tester.getRect(find.byKey(_feedKey));
      final userRect = tester.getRect(user);
      expect(userRect.right, greaterThan(feed.center.dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a second vision appends a second card chronologically', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      await _reveal(tester, find.textContaining('Vision 1 · '));
      await _addSecondVision(tester, c);
      await tester.pumpAndSettle();
      await _reveal(tester, find.textContaining('Vision 2 · '));
      expect(find.textContaining('Vision 2 · '), findsOneWidget);
      expect(c.read(pwaControllerProvider).versions, hasLength(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the expand control moves to the Reveal for that vision', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      final id = c.read(pwaControllerProvider).currentVision!.versionId;
      final expand = find.byKey(const ValueKey('av7-vision-expand'));
      await _reveal(tester, expand);
      await tester.tap(expand.first);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.reveal);
      expect(s.previewedVision!.versionId, id);
      expect(
        s.canonicalRoute.location,
        '/projects/${s.project.projectId}/reveal?vision=$id',
      );
      // No version was created by looking at one.
      expect(s.versions, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a typed instruction executes — no local confirmation step', (
      tester,
    ) async {
      // The browser no longer decides advice-vs-refine, and no longer composes
      // "Want me to apply it?". A line goes to the canonical pipeline, and the
      // verdict (execute or object) comes back from it.
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      final ctl = c.read(pwaControllerProvider.notifier);

      ctl.sendUserText('Make the sofa darker');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      expect(
        c.read(pwaControllerProvider).versions,
        hasLength(2),
        reason: 'the instruction ran',
      );
      expect(find.text('Apply this change?'), findsNothing);
      expect(find.textContaining('Want me to apply'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('composer is present and sends', (tester) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Hello Ayden');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(
        c
            .read(pwaControllerProvider)
            .messages
            .any((m) => m.text == 'Hello Ayden'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    for (final size in const [
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
      Size(1920, 1080),
    ]) {
      testWidgets(
        'no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pumpArchitect(tester, size);
          expect(find.byKey(_feedKey), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // ── The Full Reveal owns exploration ───────────────────────────────────────
  group('Full Reveal', () {
    testWidgets('it SHOWS: the transformation, and almost nothing else', (
      tester,
    ) async {
      // PHASE 6 rebuild. This used to assert the presence of a VISION DETAILS
      // panel and an ATMOSPHERES eyebrow above a metadata strip — a reading
      // surface with a picture on it. Nearly all of that text had already been
      // said on the Result screen a tap earlier.
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      await _openReveal(tester, c);
      final l = pwaL10nFor(const Locale('en'));

      // The transformation, and both sides named. The "after" label is the
      // RESOLVED atmosphere, not a generic word.
      expect(find.byType(RevealHero), findsOneWidget);
      expect(find.text(l.beforeLabel), findsOneWidget);
      expect(find.text('Warm Modern'), findsWidgets);

      // The editorial structure is gone.
      expect(find.text('VISION DETAILS'), findsNothing);
      expect(find.text(l.visionDetails.toUpperCase()), findsNothing);
      expect(find.textContaining('Created'), findsNothing);

      // And the Result's paragraph is NOT repeated here.
      expect(find.textContaining('direction is in'), findsNothing);

      // What is left: the alternatives, and one action.
      expect(find.text(l.exploreOtherAtmospheres), findsOneWidget);
      // iOS carries this as the top-left pencil, not a foot pill.
      expect(find.byKey(const ValueKey('pwa-reveal-edit')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the render is uncropped, at the shape the engine returns', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(390, 844)).then(
        (c) => _openReveal(tester, c),
      );
      final frame = find
          .descendant(
            of: find.byKey(const ValueKey('pwa-full-reveal')),
            matching: find.byType(AspectRatio),
          )
          .first;
      // "The shape the engine returns" is no longer a constant: it is the
      // decoded render's own width / height, recorded by the image that shows
      // it (a portrait photo comes back portrait — Round 3, phone review).
      // The mock's render is a bundle asset; whatever its shape, the frame
      // takes exactly that shape.
      final c = tester
          .element(find.byType(PwaExperience))
          .findAncestorWidgetOfExactType<UncontrolledProviderScope>()!
          .container;
      final after = c.read(pwaControllerProvider).currentVision!.afterAsset;
      final measured = c.read(pwaRenderAspectsProvider)[after];
      expect(measured, isNotNull, reason: 'the render has been measured');
      expect(tester.widget<AspectRatio>(frame).aspectRatio, measured);
      final r = tester.getRect(frame);
      expect(r.width / r.height, closeTo(measured!, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the transformation dominates the screen', (tester) async {
      const size = Size(390, 844);
      final c = await _pumpArchitect(tester, size);
      await _openReveal(tester, c);
      // The hero block is the largest thing on the screen, and the atmospheres
      // sit below it rather than beside a panel.
      final hero = tester.getRect(find.byType(RevealHero));
      expect(hero.width, greaterThan(size.width * 0.8));
      final rail =
          tester.getRect(find.byKey(const ValueKey('pwa-reveal-atmospheres')));
      expect(hero.bottom, lessThanOrEqualTo(rail.top + 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('holds no second conversation', (tester) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      await _openReveal(tester, c);
      // No composer, no chat feed — exploration only.
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(_feedKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Back to conversation returns to the Architect', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      await _openReveal(tester, c);
      await tester.tap(find.byKey(const ValueKey('pwa-back-to-conversation')));
      await tester.pump();
      await tester.pumpAndSettle();
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.architect);
      expect(find.byKey(_feedKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Refine with Ayden returns to the chat WITH the vision as '
        'context, and sends nothing', (tester) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      final id = c.read(pwaControllerProvider).currentVision!.versionId;
      final msgsBefore = c.read(pwaControllerProvider).messages.length;
      await _openReveal(tester, c);
      // The plain-return duplicate is gone: only the header goes back.
      expect(find.text('Open in conversation'), findsNothing);
      expect(find.text('Refine this vision'), findsNothing);
      expect(find.byKey(const ValueKey('pwa-reveal-edit')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pwa-reveal-edit')));
      await tester.pump();
      await tester.pumpAndSettle();

      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.architect);
      expect(s.refineContextVisionId, id);
      // No fabricated message on the user's behalf.
      expect(s.messages.length, msgsBefore);
      expect(find.byKey(const ValueKey('av7-refine-context')), findsOneWidget);
      expect(find.textContaining('Refining Vision'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the refinement context can be dropped without touching the '
        'vision', (tester) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      final versions = c.read(pwaControllerProvider).versions.length;
      await _openReveal(tester, c);
      await tester.tap(find.byKey(const ValueKey('pwa-reveal-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('av7-refine-context-cancel')));
      await tester.pumpAndSettle();
      final s = c.read(pwaControllerProvider);
      expect(s.refineContextVisionId, isNull);
      expect(find.byKey(const ValueKey('av7-refine-context')), findsNothing);
      expect(s.versions.length, versions);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Back to conversation carries no refinement intent', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      await _openReveal(tester, c);
      await tester.tap(find.byKey(const ValueKey('pwa-back-to-conversation')));
      await tester.pumpAndSettle();
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.architect);
      expect(s.refineContextVisionId, isNull);
      expect(find.byKey(const ValueKey('av7-refine-context')), findsNothing);
    });

    testWidgets('the atmospheres are always visible — nothing to reveal', (
      tester,
    ) async {
      // There used to be a "Try another atmosphere" row inside the details
      // panel whose whole job was to scroll the rail into view. The rail is
      // the second half of the screen now, so the action it existed for has
      // nothing left to do.
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      await _openReveal(tester, c);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.tryAnotherAtmosphere), findsNothing);
      expect(
        find.byKey(const ValueKey('pwa-reveal-atmospheres')),
        findsOneWidget,
      );
      expect(c.read(pwaControllerProvider).phase, PwaPhase.reveal);
      expect(tester.takeException(), isNull);
    });

    testWidgets('prev/next step visions and create nothing', (tester) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      await _addSecondVision(tester, c);
      await _openReveal(tester, c);
      expect(find.textContaining('Vision 2 of 2'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(_revealHeaderKey),
          matching: find.byIcon(Icons.chevron_left_rounded),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('Vision 1 of 2'), findsOneWidget);
      expect(c.read(pwaControllerProvider).versions, hasLength(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('atmosphere selection stages a pending bar, creates nothing', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      await _openReveal(tester, c);
      // Targeted by KEY. The rail now uses iOS's own AtmosphereHeroCard, whose
      // name is one of several Texts it composes and which a horizontal
      // ListView may not have built yet — a label is not a handle.
      final card = find.byKey(const ValueKey('pwa-reveal-atmo-soft_luxury'));
      // The rail is a lazy horizontal ListView holding cards ~86% of the
      // viewport wide, so a card three along has not been built yet —
      // `ensureVisible` needs an element that exists. Scroll to it the way a
      // person would.
      await tester.scrollUntilVisible(
        card,
        240,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('pwa-reveal-atmospheres')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Soft Luxury selected'), findsOneWidget);
      expect(find.text('Create vision'), findsOneWidget);
      // Staging alone must not have touched the session's atmosphere history.
      expect(c.read(pwaControllerProvider).pendingAtmosphereId, 'soft_luxury');
      expect(c.read(pwaControllerProvider).versions, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    for (final size in const [
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
      Size(1920, 1080),
    ]) {
      testWidgets(
        'no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
              final c = await _pumpArchitect(tester, size);
          await _openReveal(tester, c);
          expect(find.byKey(const ValueKey('pwa-full-reveal')), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // ── The desktop chat must LOOK like a conversation ──────────────────────────
  // ── The result, and the room it is shown in (Phase 5) ─────────────────────
  //
  // What this replaced. The conversation used to float on a photograph: a
  // blurred Warm Modern living room filled the window, a warm-ivory veil lay
  // over it, and on desktop a sheet of translucent glass carried the thread.
  // Roughly twenty tests here measured that surface — the plate's two gradient
  // stops, its alpha ceilings, its blur, the backdrop veil, and which ink each
  // side of it demanded.
  //
  // None of it exists. The person has just generated a picture of THEIR room,
  // and the app was showing them somebody else's behind it; the backdrop went,
  // and every number describing it went with it. Those tests were not migrated
  // because there is nothing left for them to describe. What replaces them is
  // the rule the phase actually has to hold: the render is the biggest thing on
  // the screen, it is shown whole, and it comes first.
  group('the result leads', () {
    testWidgets('there is no photograph behind the conversation',
        (tester) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      final decorative = tester.widgetList<Image>(find.byType(Image)).where((i) {
        final provider = i.image;
        return provider is AssetImage &&
            provider.assetName.contains('ftue_warm_modern');
      });
      expect(
        decorative,
        isEmpty,
        reason: 'the only photograph on this screen is the render',
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the canvas is the product canvas, not a dark shell',
        (tester) async {
      await _pumpArchitect(tester, const Size(390, 844));
      final scaffold = tester.widget<Scaffold>(
        find.byKey(const ValueKey('pwa-design-session-result')),
      );
      expect(scaffold.backgroundColor, pwaCanvas);
      expect(scaffold.backgroundColor, isNot(Colors.black));
      expect(scaffold.backgroundColor, isNot(Colors.transparent));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the render is the payoff: big, and shown WHOLE',
        (tester) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      await _reveal(tester, find.byKey(const ValueKey('av7-vision-expand')));
      final frame = find
          .descendant(
            of: find.byKey(_feedKey),
            matching: find.byType(AspectRatio),
          )
          .first;
      final rect = tester.getRect(frame);
      // THE CROP. The frame is the shape the render ACTUALLY has — measured
      // off its decode, as iOS's result card measures it — so the `cover`
      // inside it fills exactly and cuts nothing. A 16:9 frame took a tenth
      // off the top and bottom of a landscape render; a fixed 3:2 took a third
      // off the top and bottom of a portrait one (Round 3, phone review).
      final c = tester
          .element(find.byType(PwaExperience))
          .findAncestorWidgetOfExactType<UncontrolledProviderScope>()!
          .container;
      final after = c.read(pwaControllerProvider).currentVision!.afterAsset;
      final measured = c.read(pwaRenderAspectsProvider)[after]!;
      expect(tester.widget<AspectRatio>(frame).aspectRatio, measured);
      expect(rect.width / rect.height, closeTo(measured, 0.01));
      // As big as that shape allows inside iOS's canvas: the OUTER card is
      // `(screenH * 0.52).clamp(280, 560)` tall and the column wide; the
      // INNER frame is the largest box of the render's ratio that fits it.
      final vision = c.read(pwaControllerProvider).currentVision!;
      final canvasFinder =
          find.byKey(ValueKey('vision-canvas-${vision.versionId}'));
      final canvas = tester.getRect(canvasFinder);
      // `setSurfaceSize` does not change `MediaQuery.sizeOf`; read the size
      // the widget itself saw, as iOS's formula does.
      final screen = MediaQuery.sizeOf(tester.element(canvasFinder));
      expect(canvas.height, closeTo(pwaRenderCanvasHeight(screen), 1));
      expect(canvas.width, greaterThanOrEqualTo(760));
      final inner = PwaRenderCanvas.innerRect(canvas.size, measured);
      expect(rect.width, closeTo(inner.width, 1));
      expect(rect.height, closeTo(inner.height, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the image comes before the words', (tester) async {
      // IMAGE FIRST, COMMENTARY SECOND. The model order is asserted in "first
      // turn order" below; this is the geometry, which is what the person
      // actually experiences.
      await _pumpArchitect(tester, const Size(390, 844));
      final image = tester.getRect(
        find.byKey(const ValueKey('pwa-result-vision')),
      );
      // Ayden's opening line — located by its own words rather than by a
      // private widget type, so the assertion survives a re-composition.
      final commentary = tester.getRect(
        find.textContaining('direction is in').first,
      );
      expect(
        image.top,
        lessThan(commentary.top),
        reason: 'the render must not be preceded by a paragraph',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the caption sits under the render, never above it',
        (tester) async {
      await _pumpArchitect(tester, const Size(390, 844));
      final image = tester.getRect(
        find.byKey(const ValueKey('pwa-result-vision')),
      );
      final caption = tester.getRect(find.textContaining('Vision 1').first);
      expect(caption.top, greaterThan(image.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('one Ayden turn = one avatar, render included', (tester) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      await _reveal(tester, find.text('What would you like to change?'));
      expect(find.byKey(const ValueKey('av7-vision-expand')), findsOneWidget);
      expect(find.byType(PwaLogoBadge), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CHAT01: the vision carries no action row at all',
        (tester) async {
      // iOS removed this row in Wave 5.13 and never brought it back: "the
      // image itself is now the primary interaction (tap = reveal)". Each pill
      // duplicated something the session already does — the render opens the
      // Reveal, the composer IS the refine interface, and atmospheres are
      // explored in the Reveal — so the row competed with the conversation.
      await _pumpArchitect(tester, const Size(1440, 900));
      await _reveal(tester, find.text('What would you like to change?'));
      for (final code in const ['en', 'fr', 'km']) {
        final l = pwaL10nFor(Locale(code));
        expect(find.text(l.viewFullReveal), findsNothing, reason: code);
        expect(find.text(l.refineThis), findsNothing, reason: code);
        expect(find.text(l.tryAnotherAtmosphere), findsNothing, reason: code);
      }
      // …and it was not replaced by another toolbar: the only affordance on
      // the render is the expand control, and the render itself.
      expect(find.byKey(const ValueKey('av7-vision-expand')), findsOneWidget);
      // The composer is still there, because that is where a refine is typed.
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the composer sits inside the reading column', (tester) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      final feed = tester.getRect(find.byKey(_feedKey));
      final field = tester.getRect(find.byType(TextField));
      expect(field.left, greaterThanOrEqualTo(feed.left - 40));
      expect(field.right, lessThanOrEqualTo(feed.right + 40));
      expect(field.top, greaterThanOrEqualTo(feed.top));
      expect(tester.takeException(), isNull);
    });

    for (final size in const [
      Size(390, 844),
      Size(430, 932),
      Size(768, 1024),
      Size(1440, 900),
      Size(1920, 1080),
    ]) {
      testWidgets(
        'no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pumpArchitect(tester, size);
          expect(
            find.byKey(const ValueKey('pwa-design-session-result')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });


  // ── The Design Session is the container ────────────────────────────────────
  //
  // SESS01-04. Generate used to open a full-screen loading page, then a
  // full-screen unveiling with one "Continue with Ayden" button, and only then
  // the conversation. Three screens for one act. iOS has always done this in
  // ONE: the loading is a bubble in the thread and the render replaces it in
  // place. These tests hold that shape — including the two screens' absence,
  // which is what stops them growing back.
  group('generation happens INSIDE the session', () {
    testWidgets('SESS01: Generate lands in the session, already saved', (
      tester,
    ) async {
      final c = await _pumpFirstReveal(tester, const Size(1440, 900));
      final s = c.read(pwaControllerProvider);
      // The conversation, not a product screen with a door out of it.
      expect(s.phase, PwaPhase.architect);
      expect(find.byKey(_feedKey), findsOneWidget);
      // The render is IN the thread.
      expect(find.byKey(const ValueKey('pwa-result-vision')), findsOneWidget);
      // The project is durable by the time the session settles.
      expect(s.versions, hasLength(1));
      expect(
        s.visibleProjects.any((p) => p.projectId == s.activeProjectId),
        isTrue,
      );
      // …and the URL is the session's own, not a `mode=first` presentation.
      expect(
        s.canonicalRoute.location,
        '/projects/${s.project.projectId}/architect',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('SESS02: there is no continuation step to take', (
      tester,
    ) async {
      await _pumpFirstReveal(tester, const Size(1440, 900));
      // The unveiling and its single action are gone, not hidden.
      expect(find.byKey(const ValueKey('pwa-first-reveal')), findsNothing);
      expect(
        find.byKey(const ValueKey('pwa-first-reveal-continue')),
        findsNothing,
      );
      expect(find.text('Continue with Ayden'), findsNothing);
      // What IS there is the conversation: a composer to type the next
      // instruction into, under the render.
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SESS03: exactly ONE generation request was made', (
      tester,
    ) async {
      // The old flow crossed two screen boundaries between the tap and the
      // result; collapsing them must not make the session ask twice.
      final c = await _pumpFirstReveal(tester, const Size(1440, 900));
      await tester.pump(const Duration(seconds: 3));
      final s = c.read(pwaControllerProvider);
      expect(s.versions, hasLength(1));
      expect(s.versions.single.visionNumber, 1);
      // …and nothing is still running.
      expect(s.generating, isFalse);
      expect(
        s.messages.where((m) => m.kind == PwaMessageKind.loading),
        isEmpty,
        reason: 'the loading bubble is REPLACED by the render, never left',
      );
    });

    testWidgets('a refinement never re-opens the unveiling', (tester) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      final ctl = c.read(pwaControllerProvider.notifier);
      // Executes straight away now: the confirmation card belonged to the local
      // decision that the canonical advisor has taken over.
      ctl.sendUserText('Make the sofa darker');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(c.read(pwaControllerProvider).phase, PwaPhase.architect);
      expect(c.read(pwaControllerProvider).versions, hasLength(2));
      expect(find.byKey(const ValueKey('pwa-first-reveal')), findsNothing);
    });

    testWidgets('a new atmosphere never re-opens the unveiling', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      await _addSecondVision(tester, c);
      await tester.pumpAndSettle();
      expect(c.read(pwaControllerProvider).phase, PwaPhase.architect);
      expect(c.read(pwaControllerProvider).versions, hasLength(2));
      expect(find.byKey(const ValueKey('pwa-first-reveal')), findsNothing);
    });

    testWidgets('reopening a saved project never re-opens the unveiling', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      final ctl = c.read(pwaControllerProvider.notifier);
      final id = c.read(pwaControllerProvider).activeProjectId;
      ctl.openLibrary();
      await tester.pump();
      await ctl.openProject(id);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(c.read(pwaControllerProvider).phase, PwaPhase.architect);
      expect(find.byKey(const ValueKey('pwa-first-reveal')), findsNothing);
    });

    for (final size in const [
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
      Size(1920, 1080),
    ]) {
      testWidgets(
        'SESS04: the settled session fits at '
        '${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pumpFirstReveal(tester, size);
          expect(find.byKey(_feedKey), findsOneWidget);
          expect(
            find.byKey(const ValueKey('pwa-result-vision')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // ── The image greets you, then Ayden speaks ────────────────────────────────
  group('first turn order', () {
    testWidgets('the first Vision is built BEFORE Ayden comments on it', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      final text = c
          .read(pwaControllerProvider)
          .messages
          .firstWhere((m) => m.kind == PwaMessageKind.reveal)
          .text;

      // Anchored on the RENDER, not on an action label. The pills used to sit
      // between the image and Ayden's line and stood in for the image's
      // position; Phase 5 moved them below the commentary, which is the whole
      // point — so the proxy had to become the thing itself.
      final cardY =
          tester.getTopLeft(find.byKey(const ValueKey('pwa-result-vision'))).dy;
      final bubbleY = tester.getTopLeft(find.text(text)).dy;
      final guidanceY = tester
          .getTopLeft(find.text('What would you like to change?'))
          .dy;

      // You have just generated an image: the image is what you see first,
      // then what Ayden says about it, then the invitation to say something
      // back. The action row that used to sit between the last two is gone.
      expect(cardY, lessThan(bubbleY));
      expect(bubbleY, lessThan(guidanceY));
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing is duplicated by the re-ordering', (tester) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      final text = c
          .read(pwaControllerProvider)
          .messages
          .firstWhere((m) => m.kind == PwaMessageKind.reveal)
          .text;
      expect(find.byKey(const ValueKey('av7-vision-expand')), findsOneWidget);
      expect(find.text(text), findsOneWidget);
      expect(find.text('What would you like to change?'), findsOneWidget);
    });

    testWidgets('later visions stay chronological: Ayden answers, then shows', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      final before = [
        for (final m in c.read(pwaControllerProvider).messages) m.id,
      ];
      await _addSecondVision(tester, c);
      await tester.pumpAndSettle();

      final msgs = c.read(pwaControllerProvider).messages;
      // The STORED chronology is untouched and only appended to — the new order
      // is a presentation choice, never a persistence one.
      expect([for (final m in msgs.take(before.length)) m.id], equals(before));
      final second = msgs.lastWhere((m) => m.kind == PwaMessageKind.reveal);
      await _reveal(tester, find.text(second.text));
      final bubbleY = tester.getTopLeft(find.text(second.text)).dy;
      final cardY = tester.getTopLeft(find.textContaining('Vision 2 · ')).dy;
      expect(bubbleY, lessThan(cardY));
      expect(tester.takeException(), isNull);
    });
  });

}
