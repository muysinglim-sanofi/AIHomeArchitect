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
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_brand.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_widgets.dart';
import 'package:ai_home_architect/shared/widgets/reveal_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  c.continueToArchitect();
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

    testWidgets('desktop shows one warm workspace holding the whole chat', (
      tester,
    ) async {
      const size = Size(1920, 1080);
      await _pumpArchitect(tester, size);
      final shell = find.byKey(const ValueKey('av7-glass-chat-shell'));
      expect(shell, findsOneWidget);
      final r = tester.getRect(shell);
      expect(r.width, lessThanOrEqualTo(1120));
      // The header, the thread and the composer all live INSIDE that surface —
      // no band running across the window.
      expect(
        find.descendant(
          of: shell,
          matching: find.byKey(const ValueKey('av7-conversation-header')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: shell, matching: find.byKey(_feedKey)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: shell, matching: find.byType(TextField)),
        findsOneWidget,
      );
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

    testWidgets('vision card carries its three actions', (tester) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      await _reveal(tester, find.text('View full reveal'));
      expect(find.text('View full reveal'), findsOneWidget);
      expect(find.text('Refine this'), findsOneWidget);
      expect(find.text('Try another atmosphere'), findsOneWidget);
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

    testWidgets('View full reveal moves to the Reveal for that vision', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      final id = c.read(pwaControllerProvider).currentVision!.versionId;
      await _reveal(tester, find.text('View full reveal'));
      await tester.tap(find.text('View full reveal').first);
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
    testWidgets('shows the Before/After, metadata, details and atmospheres', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      await _openReveal(tester, c);
      expect(find.byKey(_revealHeaderKey), findsOneWidget);
      expect(find.byType(PwaRevealCard), findsOneWidget);
      expect(find.byType(RevealHero), findsOneWidget);
      expect(find.text('Before'), findsOneWidget);
      expect(find.text('After'), findsOneWidget);
      expect(find.text('VISION DETAILS'), findsOneWidget);
      expect(find.text('ATMOSPHERES'), findsOneWidget);
      expect(find.textContaining('Vision 1 of'), findsOneWidget);
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
      expect(find.text('Refine with Ayden'), findsOneWidget);

      await tester.tap(find.text('Refine with Ayden'));
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
      await tester.tap(find.text('Refine with Ayden'));
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

    testWidgets('Try another atmosphere stays in the Reveal', (tester) async {
      final c = await _pumpArchitect(tester, const Size(1440, 900));
      await _openReveal(tester, c);
      await tester.tap(find.text('Try another atmosphere'));
      await tester.pumpAndSettle();
      // It reveals the rail; it does NOT go back to the conversation.
      expect(c.read(pwaControllerProvider).phase, PwaPhase.reveal);
      expect(find.text('ATMOSPHERES'), findsOneWidget);
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
      // Target the rail's own card (semantics labels need an explicit
      // ensureSemantics handle, and the name alone is not unique on screen).
      final card = find.descendant(
        of: find.byKey(const ValueKey('pwa-reveal-atmospheres')),
        matching: find.text('Soft Luxury'),
      );
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Soft Luxury selected'), findsOneWidget);
      expect(find.text('Create vision'), findsOneWidget);
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
          expect(find.byKey(_revealHeaderKey), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // ── The desktop chat must LOOK like a conversation ──────────────────────────
  group('desktop chat identity', () {
    test('the workspace is LIGHT warm glass, not a brown panel', () {
      // The desktop plate follows the narrow window: white-ivory and clearly
      // translucent. A dark brown plate read as a tinted panel — that is the
      // regression this guards against, in both directions at once.
      expect(kPwaGlassTop.r, greaterThan(0.90));
      expect(kPwaGlassTop.g, greaterThan(0.90));
      expect(kPwaGlassBottom.r, greaterThan(0.85));
      // Warm, not clinical white: red must stay ahead of blue.
      expect(kPwaGlassTop.b, lessThan(kPwaGlassTop.r));
      expect(kPwaGlassBottom.b, lessThan(kPwaGlassBottom.r));
      // Still glass, not paper: opacity — not blur — is what hides a room.
      expect(kPwaDesktopGlassTopAlpha, lessThanOrEqualTo(0.18));
      expect(kPwaDesktopGlassBottomAlpha, lessThanOrEqualTo(0.10));
      // Ink for the surfaces that carry their own fill (field, pills, cards).
      expect(kPwaOnPlate.r, lessThan(0.25));
      expect(kPwaOnPlateSoft.r, lessThan(0.25));
    });

    test('the narrow-window accent stays dark and separate from the plate', () {
      // Mobile / tablet sit straight on the cream veil, so their pills and
      // composer carry their own contrast. Lightening desktop must never reach
      // them — different constants, enforced here.
      expect(kPwaWarmAccent.r, lessThan(0.20));
      expect(kPwaOnGlass.r, greaterThan(0.85));
    });

    testWidgets('a real Warm Modern room sits behind the conversation', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      final backdrop = tester.widgetList<Image>(find.byType(Image)).where((i) {
        final p = i.image;
        return p is AssetImage && p.assetName.contains('ftue_warm_modern');
      });
      expect(
        backdrop,
        isNotEmpty,
        reason: 'the chat backdrop must use the Warm Modern living room asset',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the header announces Ayden, not a gallery caption', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      final header = find.byKey(const ValueKey('av7-conversation-header'));
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text('AYDEN ARCHITECT')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the render is the payoff: big, and never letterboxed', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      final card = find.byKey(const ValueKey('av7-vision-expand'));
      await _reveal(tester, card);
      final image = tester.getRect(
        find
            .descendant(
              of: find.byKey(_feedKey),
              matching: find.byType(AspectRatio),
            )
            .first,
      );
      // Nearly the whole conversation column, and tall enough to land as a
      // result rather than a thumbnail.
      expect(image.width, greaterThanOrEqualTo(760));
      expect(image.width, lessThanOrEqualTo(kPwaVisionMaxWidth + 1));
      expect(image.height, greaterThanOrEqualTo(400));
      expect(image.height, lessThanOrEqualTo(kPwaVisionMaxHeight + 1));
      // `cover` fills the frame, so a landscape render is never boxed between
      // two charcoal bands. Uncropped viewing is the Full Reveal's job.
      final rendered = tester.widgetList<Image>(
        find.descendant(of: find.byKey(_feedKey), matching: find.byType(Image)),
      );
      expect(rendered.any((i) => i.fit == BoxFit.cover), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one Ayden turn = one avatar, render included', (tester) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      // The first turn holds the greeting, the render and the suggestions; if
      // they were separate blocks the avatar would repeat.
      await _reveal(tester, find.text('What would you like to change?'));
      expect(find.byKey(const ValueKey('av7-vision-expand')), findsOneWidget);
      expect(find.text('View full reveal'), findsOneWidget);
      expect(find.byType(PwaLogoBadge), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the composer belongs to the same plate as the thread', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      final shell = find.byKey(const ValueKey('av7-glass-chat-shell'));
      final shellRect = tester.getRect(shell);
      final field = tester.getRect(find.byType(TextField));
      expect(field.left, greaterThanOrEqualTo(shellRect.left - 1));
      expect(field.right, lessThanOrEqualTo(shellRect.right + 1));
      expect(field.bottom, lessThanOrEqualTo(shellRect.bottom + 1));
      expect(tester.takeException(), isNull);
    });

    for (final size in const [
      Size(1440, 900),
      Size(1536, 864),
      Size(1920, 1080),
    ]) {
      testWidgets(
        'no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pumpArchitect(tester, size);
          expect(
            find.byKey(const ValueKey('av7-glass-chat-shell')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    // Below 1200 the glass plate must not appear at all: the narrow window
    // keeps the flowing column it was designed with.
    for (final size in const [
      Size(390, 844),
      Size(430, 932),
      Size(768, 1024),
    ]) {
      testWidgets(
        'no glass plate at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pumpArchitect(tester, size);
          expect(
            find.byKey(const ValueKey('av7-glass-chat-shell')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // ── The first vision earns a moment of its own ─────────────────────────────
  group('First Reveal', () {
    testWidgets('Generate unveils the vision full-screen, already saved', (
      tester,
    ) async {
      final c = await _pumpFirstReveal(tester, const Size(1440, 900));
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.firstReveal);
      expect(find.byKey(const ValueKey('pwa-first-reveal')), findsOneWidget);
      // The project is durable BEFORE the unveiling — this is a presentation
      // state, not a step in the save chain.
      expect(s.versions, hasLength(1));
      expect(
        s.visibleProjects.any((p) => p.projectId == s.activeProjectId),
        isTrue,
      );
      expect(s.previewedVision!.versionId, s.currentVision!.versionId);
      expect(
        s.canonicalRoute.location,
        '/projects/${s.project.projectId}/reveal'
        '?vision=${s.currentVision!.versionId}&mode=first',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('it holds ONE action and nothing else', (tester) async {
      await _pumpFirstReveal(tester, const Size(1440, 900));
      expect(
        find.byKey(const ValueKey('pwa-first-reveal-continue')),
        findsOneWidget,
      );
      expect(find.text('Continue with Ayden'), findsOneWidget);
      // No details panel, no rail, no conversation, no refine, no composer.
      expect(find.text('VISION DETAILS'), findsNothing);
      expect(find.text('ATMOSPHERES'), findsNothing);
      expect(find.text('Refine with Ayden'), findsNothing);
      expect(find.text('Refine this'), findsNothing);
      expect(find.text('Try another atmosphere'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(_feedKey), findsNothing);
      expect(find.textContaining(' of '), findsNothing);
      // …but the reveal engine itself is there.
      expect(find.byType(PwaRevealCard), findsOneWidget);
      expect(find.byType(RevealHero), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Continue with Ayden hands over to the conversation', (
      tester,
    ) async {
      final c = await _pumpFirstReveal(tester, const Size(1440, 900));
      await tester.tap(find.byKey(const ValueKey('pwa-first-reveal-continue')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.architect);
      expect(find.byKey(_feedKey), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-first-reveal')), findsNothing);
      expect(tester.takeException(), isNull);
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
        'no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pumpFirstReveal(tester, size);
          expect(
            find.byKey(const ValueKey('pwa-first-reveal-continue')),
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

      final cardY = tester.getTopLeft(find.text('View full reveal')).dy;
      final bubbleY = tester.getTopLeft(find.text(text)).dy;
      final guidanceY = tester
          .getTopLeft(find.text('What would you like to change?'))
          .dy;

      // You have just generated an image: the image is what you see first.
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
      expect(find.text('View full reveal'), findsOneWidget);
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

  // ── The plate is glass, and the room is behind it ─────────────────────────
  group('real translucency', () {
    test('no layer is thick enough to hide the room', () {
      // The ceilings that made the difference. Blur was never the problem —
      // at 0.44 the plate was a milky rectangle however hard it was blurred.
      expect(kPwaDesktopGlassTopAlpha, lessThanOrEqualTo(0.18));
      expect(kPwaDesktopGlassBottomAlpha, lessThanOrEqualTo(0.10));
      expect(kPwaDesktopBackdropVeilAlpha, lessThanOrEqualTo(0.07));
      // The salon must still read as a salon: sofa, lamps, shelves, depth.
      expect(kPwaDesktopBackdropBlur, lessThanOrEqualTo(6));
      expect(kPwaBackdropBlur, lessThanOrEqualTo(8));
    });

    testWidgets('the room, the glass, the feed and the composer are layered '
        'as designed', (tester) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      final backdrop = find.byKey(const ValueKey('av7-warm-modern-backdrop'));
      final shell = find.byKey(const ValueKey('av7-glass-chat-shell'));
      expect(backdrop, findsWidgets);
      expect(shell, findsOneWidget);
      expect(
        find.byKey(const ValueKey('av7-integrated-composer')),
        findsOneWidget,
      );

      // The Warm Modern photo is the bottom layer…
      final room = tester.widgetList<Image>(find.byType(Image)).where((i) {
        final prov = i.image;
        return prov is AssetImage &&
            prov.assetName.contains('ftue_warm_modern');
      });
      expect(room, isNotEmpty);

      // …and the plate really refracts it rather than painting over it.
      expect(
        find.descendant(of: shell, matching: find.byType(BackdropFilter)),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the feed and the composer wrapper paint nothing', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      expect(
        tester
            .widget<ColoredBox>(find.byKey(const ValueKey('av7-chat-feed')))
            .color,
        Colors.transparent,
      );
      expect(
        tester
            .widget<ColoredBox>(
              find.byKey(const ValueKey('av7-integrated-composer')),
            )
            .color,
        Colors.transparent,
      );
      // The field itself carries a fill so the text stays readable.
      expect(find.byType(TextField), findsOneWidget);
    });

    // ── The structural guarantee, not a colour preference ────────────────────
    // A single leftover opaque fill between the photo and the plate cancels the
    // whole effect, so each layer of the desktop path is asserted by hand.
    testWidgets('nothing opaque sits between the room and the glass', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1440, 900));

      // 1. The Scaffold paints nothing.
      final scaffold = tester.widgetList<Scaffold>(find.byType(Scaffold)).last;
      expect(scaffold.backgroundColor, Colors.transparent);

      // 2. The image is painted BELOW the plate, inside the same Stack.
      final root = find.ancestor(
        of: find.byKey(const ValueKey('av7-warm-modern-backdrop')),
        matching: find.byType(Stack),
      );
      expect(root, findsWidgets);
      expect(
        find.descendant(
          of: root.first,
          matching: find.byKey(const ValueKey('av7-glass-chat-shell')),
        ),
        findsOneWidget,
      );

      // 3. The plate refracts rather than covers, and its Material paints
      //    nothing — MaterialType.transparency, not a colour.
      final shell = find.byKey(const ValueKey('av7-glass-chat-shell'));
      expect(
        find.descendant(of: shell, matching: find.byType(BackdropFilter)),
        findsWidgets,
      );
      final material = tester
          .widgetList<Material>(
            find.descendant(of: shell, matching: find.byType(Material)),
          )
          .first;
      expect(material.type, MaterialType.transparency);
      expect(material.color, isNull);

      // 4. No broad fill anywhere between the Stack and the plate. Measured,
      //    not counted: a 1px hairline at 0.22 is trim, a 900x600 box at 0.22
      //    is the panel this pass removed. Only area makes a layer a cover.
      final between = find.descendant(
        of: root.first,
        matching: find.byType(ColoredBox),
      );
      for (final element in between.evaluate()) {
        final box = element.widget as ColoredBox;
        final size = element.size ?? Size.zero;
        final covers = size.width > 200 && size.height > 24;
        if (!covers) continue;
        expect(
          box.color.a,
          lessThanOrEqualTo(0.20),
          reason:
              'a ${size.width.round()}x${size.height.round()} ColoredBox '
              '(${box.color}) is covering the room',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the plate carries no brown gradient any more', (tester) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      final decorated = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('av7-glass-chat-shell')),
          matching: find.byType(DecoratedBox),
        ),
      );
      final gradients = decorated
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.gradient)
          .whereType<LinearGradient>();
      expect(gradients, isNotEmpty);
      for (final g in gradients) {
        for (final c in g.colors) {
          // Ivory, not taupe: every stop stays bright, warm and thin.
          expect(c.r, greaterThan(0.90));
          expect(c.g, greaterThan(0.85));
          expect(c.b, lessThan(c.r));
          expect(c.a, lessThanOrEqualTo(0.18));
        }
      }
    });

    // The chrome is shared verbatim between the two layouts, so the surface —
    // not the widget — has to decide the ink. Both directions are asserted:
    // lightening desktop must not reach the narrow window.
    testWidgets('the desktop composer writes dark ink on a light field', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1440, 900));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style!.color, kPwaOnPlate);
      final fill = field.decoration!.fillColor!;
      expect(fill.r, greaterThan(0.90));
      expect(fill.a, lessThan(0.80)); // still translucent, not a white slab
    });

    testWidgets('the narrow window keeps its light ink on a dark field', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(390, 844));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style!.color, kPwaOnGlass);
      expect(field.decoration!.fillColor!.r, lessThan(0.25));
    });

    // Bare text has no surface of its own, and at 0.18 the plate reads as "the
    // room, dimmed" rather than as paper — so it takes LIGHT ink on both
    // layouts. Only what carries a fill gets dark ink.
    testWidgets('text with no surface of its own stays light on both layouts', (
      tester,
    ) async {
      Color guidanceInk() => tester
          .widget<Text>(find.text('What would you like to change?'))
          .style!
          .color!;

      await _pumpArchitect(tester, const Size(1440, 900));
      expect(guidanceInk(), kPwaOnGlass);

      await _pumpArchitect(tester, const Size(390, 844));
      expect(guidanceInk(), kPwaOnGlass);
    });
  });
}
