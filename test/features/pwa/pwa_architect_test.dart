// Batch 2.2 V7 — Ayden Architect (final pixel-spec) widget tests. Deterministic
// (zero-delay mock), offline. Covers the chat chronology as version history, the
// full-width vision cards, atmosphere rail + pending bar, global/chat vision
// navigation (preview only), the dark/ivory geometry, and responsive layouts.
//
// Note: the widget-test font (Ahem) renders text far wider than the production
// font, so a conversation that fits one viewport in the browser overflows here.
// Tests therefore scroll targets into view rather than assuming a single fold —
// this exercises real scrolling, not a font artefact.

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
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
const _chatKey = ValueKey('av7-chat-panel');

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
  await tester.pump();
  await tester.pump(
    const Duration(seconds: 3),
  ); // drain reveal auto-sweep timers
  return container;
}

/// The primary vertical scrollable: the desktop chat list, else the stacked feed.
Finder _feed() {
  final inPanel = find.descendant(
    of: find.byKey(_chatKey),
    matching: find.byType(Scrollable),
  );
  return inPanel.evaluate().isNotEmpty
      ? inPanel.first
      : find.byType(Scrollable).first;
}

/// Scroll [target] into view (down the conversation), then settle.
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

void main() {
  // ── §37 desktop geometry ────────────────────────────────────────────────────
  group('desktop geometry (§37)', () {
    testWidgets('global header is 72px; chat panel width 440–520', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1536, 864));
      expect(tester.getSize(find.byKey(_headerKey)).height, 72);
      final chatW = tester.getSize(find.byKey(_chatKey)).width;
      expect(chatW, greaterThanOrEqualTo(440));
      expect(chatW, lessThanOrEqualTo(520));
    });

    testWidgets('left design canvas keeps ≥ 64% of the width', (tester) async {
      await _pumpArchitect(tester, const Size(1536, 864));
      final chatW = tester.getSize(find.byKey(_chatKey)).width;
      expect(1536 - chatW, greaterThanOrEqualTo(1536 * 0.64));
    });

    for (final size in const [
      Size(1280, 800),
      Size(1440, 900),
      Size(1536, 864),
      Size(1920, 1080),
    ]) {
      testWidgets(
        'reveal height 470–620 & no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pumpArchitect(tester, size);
          final h = tester.getSize(find.byType(RevealHero).first).height;
          expect(h, greaterThanOrEqualTo(470));
          expect(h, lessThanOrEqualTo(620));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('full-screen button sits clear of the After label', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1536, 864));
      final reveal = tester.getRect(find.byType(RevealHero).first);
      final fs = tester.getRect(find.byIcon(Icons.fullscreen).first).center;
      expect(fs.dy, greaterThan(reveal.center.dy)); // lower half
    });
  });

  // ── §35 — no separate Versions UI ───────────────────────────────────────────
  group('no Versions column / filmstrip / sheet (§35, §14)', () {
    testWidgets('no VERSIONS section, no View all, no filmstrip', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1536, 864));
      await _addSecondVision(tester, c);
      expect(find.text('VERSIONS'), findsNothing);
      expect(find.text('View all'), findsNothing);
      expect(find.byType(PwaVersionFilmstrip), findsNothing);
      expect(find.text('Your visions'), findsNothing);
      expect(find.byIcon(Icons.attach_file), findsNothing);
      expect(find.byIcon(Icons.notifications_none), findsNothing);
    });
  });

  // ── §5/§6 header + brand ────────────────────────────────────────────────────
  group('global header (§5)', () {
    testWidgets('Studio brand + Back home + Vision counter', (tester) async {
      await _pumpArchitect(tester, const Size(1536, 864));
      expect(find.text('AYDEN STUDIO'), findsOneWidget);
      expect(find.text('DESIGN WORKSPACE'), findsOneWidget);
      expect(find.text('Back home'), findsOneWidget);
      expect(find.text('Vision 1 of 1'), findsWidgets); // global + chat pill
      expect(tester.takeException(), isNull);
    });
  });

  // ── §12/§13 chat panel ──────────────────────────────────────────────────────
  group('chat panel (§12–§13)', () {
    testWidgets('ivory panel, Ayden Architect header + nav pill', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1536, 864));
      expect(find.text('AYDEN ARCHITECT'), findsOneWidget);
      expect(find.text('Your design conversation'), findsOneWidget);
      final panel = tester.widget<Container>(find.byKey(_chatKey));
      expect(
        (panel.decoration as BoxDecoration).color,
        const Color(0xFFF7F3EE),
      );
    });

    testWidgets('composer + disclaimer present; no attachment icon', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1536, 864));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Ask Ayden anything…'), findsOneWidget);
      expect(
        find.text('Ayden can make mistakes. Always review design details.'),
        findsOneWidget,
      );
    });

    testWidgets('user message aligns right, Ayden aligns left', (tester) async {
      final c = await _pumpArchitect(tester, const Size(1536, 864));
      // A unique advice question (not one of the quick-action chips) so the
      // finders resolve to exactly one widget each.
      c
          .read(pwaControllerProvider.notifier)
          .sendUserText('Does this feel right?');
      await tester.pump();
      final adviceFinder = find.textContaining(
        'this direction is working well',
      );
      await _reveal(tester, adviceFinder);
      final userRect = tester.getRect(find.text('Does this feel right?'));
      final adviceRect = tester.getRect(adviceFinder);
      expect(
        adviceRect.left,
        lessThan(userRect.left),
      ); // Ayden left, user right
    });
  });

  // ── §18 vision cards in the chat ────────────────────────────────────────────
  group('vision result cards (§18–§19)', () {
    testWidgets('Vision 1 shows a full-width card + Currently in workspace', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1536, 864));
      expect(find.text('Vision 1 · Ayden Signature'), findsOneWidget);
      expect(find.text('Currently in workspace'), findsOneWidget);
      // §19 — default quick actions under the current vision.
      await _reveal(tester, find.text('Make it warmer'));
      expect(find.text('Make it warmer'), findsOneWidget);
      expect(find.text('More natural light'), findsOneWidget);
    });

    testWidgets('a second vision appends a second card chronologically', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1536, 864));
      await _addSecondVision(tester, c);
      expect(c.read(pwaControllerProvider).versions, hasLength(2));
      await _reveal(tester, find.text('Vision 2 · Soft Luxury'));
      expect(find.text('Vision 2 · Soft Luxury'), findsOneWidget);
      expect(find.text('Currently in workspace'), findsOneWidget);
    });

    testWidgets('tapping a vision card previews it (no version created)', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1536, 864));
      // The (visible) Vision 1 card — tapping previews it and creates nothing.
      final card = find.text('Vision 1 · Ayden Signature');
      await tester.ensureVisible(card);
      await tester.pump();
      await tester.tap(card);
      await tester.pump();
      final s = c.read(pwaControllerProvider);
      expect(s.previewedVision!.visionNumber, 1);
      expect(s.versions, hasLength(1)); // no new version
    });
  });

  // ── §10/§22 canonical vision image ──────────────────────────────────────────
  group('canonical vision image (§10/§22)', () {
    testWidgets('the same afterAsset drives the reveal and the chat card', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1536, 864));
      final v1 = c.read(pwaControllerProvider).currentVision!;
      final assets = tester
          .widgetList<Image>(find.byType(Image))
          .map((im) => im.image)
          .whereType<AssetImage>()
          .map((a) => a.assetName)
          .toList();
      // v1.afterAsset feeds BOTH the Full-Reveal After image and the chat card.
      expect(
        assets.where((a) => a == v1.afterAsset).length,
        greaterThanOrEqualTo(2),
      );
    });
  });

  // ── §11–§19 mobile Vision → Full Reveal ─────────────────────────────────────
  group('mobile Vision → Full Reveal (§12/§14/§19)', () {
    testWidgets(
      'desktop cards carry NO Full-Reveal affordance (reveal is beside)',
      (tester) async {
        await _pumpArchitect(tester, const Size(1536, 864));
        expect(find.text('View in Full Reveal'), findsNothing);
        expect(find.text('Currently in Full Reveal'), findsNothing);
      },
    );

    testWidgets(
      'mobile card shows the affordance; tapping it previews (no version)',
      (tester) async {
        final c = await _pumpArchitect(tester, const Size(390, 844));
        // The single current vision's card is the one shown in the Full Reveal.
        expect(find.text('Currently in Full Reveal'), findsWidgets);
        final card = find.text('Vision 1 · Ayden Signature');
        await tester.ensureVisible(card);
        await tester.pump();
        await tester.tap(card, warnIfMissed: false);
        await tester.pump(
          const Duration(seconds: 3),
        ); // drain scroll + sweep timers
        final s = c.read(pwaControllerProvider);
        expect(s.previewedVision!.visionNumber, 1);
        expect(
          s.versions,
          hasLength(1),
        ); // preview only — no version, no lineage change
      },
    );
  });

  // ── §5/§13/§25 vision navigation (preview only) ─────────────────────────────
  group('vision navigation previews, never creates (§25)', () {
    testWidgets('prev/next arrows step visions and update counter', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1536, 864));
      await _addSecondVision(tester, c); // now Vision 2 of 2
      expect(find.text('Vision 2 of 2'), findsWidgets);
      // The global previous arrow lives in the always-visible header.
      await tester.tap(find.byIcon(Icons.chevron_left_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final s = c.read(pwaControllerProvider);
      expect(s.previewedVision!.visionNumber, 1);
      expect(s.versions, hasLength(2)); // preview only
      expect(find.text('Vision 1 of 2'), findsWidgets);
    });
  });

  // ── §10/§11 atmosphere ──────────────────────────────────────────────────────
  group('atmosphere rail + pending bar (§10–§11)', () {
    testWidgets('six atmospheres with descriptors, signature selected', (
      tester,
    ) async {
      await _pumpArchitect(tester, const Size(1536, 864));
      expect(find.text('ATMOSPHERE'), findsOneWidget);
      for (final n in const [
        'Ayden Signature',
        'Warm Modern',
        'Soft Luxury',
        'Japandi Calm',
        'Nordic Warmth',
        'Tropical Escape',
      ]) {
        expect(find.text(n), findsWidgets);
      }
      expect(find.text('Warm · Timeless · Balanced'), findsOneWidget);
    });

    testWidgets('selecting an atmosphere shows the pending bar (no version)', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1536, 864));
      final card = find.text('Japandi Calm').first;
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pump();
      expect(find.text('Japandi Calm selected'), findsOneWidget);
      expect(find.textContaining('Uses 1 Space'), findsOneWidget);
      expect(find.textContaining('Creates Vision 2'), findsOneWidget);
      expect(c.read(pwaControllerProvider).versions, hasLength(1));
    });

    testWidgets('Cancel clears pending; Create makes one child', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(1536, 864));
      final card = find.text('Japandi Calm').first;
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pump();
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      await tester.ensureVisible(cancel);
      await tester.pump();
      await tester.tap(cancel);
      await tester.pump();
      expect(find.text('Japandi Calm selected'), findsNothing);

      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pump();
      final create = find.widgetWithText(FilledButton, 'Create vision');
      await tester.ensureVisible(create);
      await tester.pump();
      await tester.tap(create);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      final s = c.read(pwaControllerProvider);
      expect(s.versions, hasLength(2));
      expect(s.currentVision!.atmosphereId, 'japandi_calm');
    });
  });

  // ── §21 refine confirmation in chat ─────────────────────────────────────────
  group('refine confirmation lives in the chat (§21)', () {
    testWidgets('typed change → confirm card → one child', (tester) async {
      final c = await _pumpArchitect(tester, const Size(1536, 864));
      await tester.enterText(find.byType(TextField), 'Make it warmer');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      final confirm = find.text('Apply this change?');
      await _reveal(tester, confirm);
      expect(confirm, findsOneWidget);
      expect(c.read(pwaControllerProvider).versions, hasLength(1));
      final create = find.widgetWithText(FilledButton, 'Create vision');
      await tester.ensureVisible(create);
      await tester.pump();
      await tester.tap(create);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      final s = c.read(pwaControllerProvider);
      expect(s.versions, hasLength(2));
      expect(s.currentVision!.actionType.name, 'refine');
      // The confirm card is CONSUMED — it cannot be re-fired into a duplicate.
      expect(find.text('Apply this change?'), findsNothing);
      expect(s.messages.every((m) => m.pendingRefine == null), isTrue);
    });

    testWidgets('advice is text-only (no version, no confirm)', (tester) async {
      final c = await _pumpArchitect(tester, const Size(1536, 864));
      await tester.enterText(find.byType(TextField), 'What do you think?');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      expect(find.text('Apply this change?'), findsNothing);
      expect(c.read(pwaControllerProvider).versions, hasLength(1));
    });
  });

  // ── §8 full screen ──────────────────────────────────────────────────────────
  testWidgets('full-screen reveal opens and Escape closes it (§8)', (
    tester,
  ) async {
    await _pumpArchitect(tester, const Size(1536, 864));
    await tester.tap(find.byIcon(Icons.fullscreen).first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('Full Reveal shows Before and After labels (§8)', (tester) async {
    await _pumpArchitect(tester, const Size(1536, 864));
    expect(find.text('Before'), findsWidgets);
    expect(find.text('After'), findsWidgets);
  });

  // ── §28/§29 responsive stacked ──────────────────────────────────────────────
  group('responsive stacked (§28–§29)', () {
    for (final size in const [
      Size(390, 844), // mobile
      Size(430, 932), // mobile
      Size(768, 1024), // tablet
      Size(1024, 768), // tablet
    ]) {
      testWidgets(
        'single feed, no split, no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pumpArchitect(tester, size);
          // No desktop chat panel on stacked layouts.
          expect(find.byKey(_chatKey), findsNothing);
          // Full Reveal is present as the first rich item.
          expect(find.byType(RevealHero), findsOneWidget);
          // Composer reachable.
          expect(find.byType(TextField), findsOneWidget);
          // Atmospheres present in the feed (scroll to them).
          await _reveal(tester, find.text('ATMOSPHERE'));
          expect(find.text('ATMOSPHERE'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('pending bar does not overflow on narrow mobile (§11)', (
      tester,
    ) async {
      final c = await _pumpArchitect(tester, const Size(360, 780));
      c.read(pwaControllerProvider.notifier).stageAtmosphere('japandi_calm');
      await tester.pump();
      // The pending bar renders in the feed and stacks its buttons — no overflow.
      expect(find.text('Japandi Calm selected'), findsWidgets);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile composer sends advice (text only)', (tester) async {
      final c = await _pumpArchitect(tester, const Size(390, 844));
      await tester.enterText(find.byType(TextField), 'What do you think?');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      final s = c.read(pwaControllerProvider);
      expect(s.messages.last.role.name, 'ayden');
      expect(s.versions, hasLength(1));
    });
  });
}
