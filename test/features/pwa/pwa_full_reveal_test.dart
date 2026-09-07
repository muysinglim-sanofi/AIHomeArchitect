/// Phase 6 — the Full Reveal.
///
/// This screen was rebuilt, not restyled, so these tests are mostly about what
/// is NO LONGER on it. The old surface led with a header bar, a metadata strip
/// and a VISION DETAILS panel carrying a paragraph and two stacked action rows;
/// the transformation was somewhere below all of it. Almost every one of those
/// words had already been said on the Result screen a tap earlier.
///
/// The other half is what a rebuild must not quietly take with it. Which
/// atmospheres exist, when a switch is allowed, that staging one costs nothing
/// and only confirming spends — none of that is this screen's to decide, and it
/// is asserted here precisely because a rebuild is where it would go missing.
library;

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_architect_screen.dart'
    show kPwaRenderAspect;
import 'package:ai_home_architect/features/pwa/presentation/pwa_architect_tokens.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_type.dart';
import 'package:ai_home_architect/shared/widgets/reveal_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

AydenImageSource _source() =>
    AydenImageSource(bytes: _png, filename: 'room.png', mimeType: 'image/png');

/// Generate for real, then open the Reveal the way the product does.
Future<ProviderContainer> _pumpReveal(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = ProviderContainer(overrides: [
    pwaRepositoryProvider.overrideWithValue(
      MockPwaExperienceRepository(workDelay: Duration.zero),
    ),
  ]);
  addTearDown(c.dispose);
  final n = c.read(pwaControllerProvider.notifier);
  n.newProject();
  n.setSource(_source(), origin: PwaImageOrigin.userUpload);
  n.selectRoom('living_room');
  n.selectEntryAtmosphere('warm_modern');
  await n.generateFirstVision();
  n.openReveal(c.read(pwaControllerProvider).currentVision!.versionId);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: true, size: size),
      child: UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: locale,
          supportedLocales: PwaL10n.supportedLocales,
          localizationsDelegates: const [
            PwaL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const PwaExperience(),
        ),
      ),
    ),
  );
  await tester.pump();
  // RevealHero arms an 800ms auto-sweep that outlives disposal.
  await tester.pump(const Duration(seconds: 2));
  return c;
}

void main() {
  group('REVEAL01  it shows the real pair', () {
    testWidgets('the before is the lineage before, the after is this vision',
        (tester) async {
      final c = await _pumpReveal(tester);
      final s = c.read(pwaControllerProvider);
      final vision = s.previewedVision!;
      expect(vision.versionId, s.currentVision!.versionId);

      final hero = tester.widget<RevealHero>(find.byType(RevealHero));
      expect(hero.beforeImage, isNotNull,
          reason: 'a comparison needs both sides');
      // The pair is built by the canonical resolvers, not by picking two
      // assets that happen to be nearby: for a first vision the "before" is
      // the person's own upload, and on a later vision it is the parent render.
      expect(hero.afterImage, isNotNull);
      expect(s.source, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('both sides are named, and the result side names the DIRECTION',
        (tester) async {
      await _pumpReveal(tester);
      final l = pwaL10nFor(const Locale('en'));
      final hero = tester.widget<RevealHero>(find.byType(RevealHero));
      expect(hero.showLabels, isTrue);
      expect(hero.beforeLabel, l.beforeLabel);
      // Not a generic "Vision": the atmosphere that was actually rendered.
      expect(hero.afterLabel, 'Warm Modern');
      expect(find.text(l.beforeLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('it opens with the result dominant, then invites the drag',
        (tester) async {
      await _pumpReveal(tester);
      final hero = tester.widget<RevealHero>(find.byType(RevealHero));
      // 0.30 ⇒ 70% of the frame is the AI result at rest. Someone arriving
      // should see what was made, not what they started with.
      expect(hero.initialFraction, 0.30);
      expect(hero.autoSweep, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the whole surface takes the drag — this page does not scroll',
        (tester) async {
      await _pumpReveal(tester);
      final hero = tester.widget<RevealHero>(find.byType(RevealHero));
      // Everywhere else the handle alone is draggable so it cannot fight a
      // scrolling page. This screen has no vertical scroll, which is exactly
      // the condition the shared widget documents for surface mode.
      expect(hero.dragMode, RevealDragMode.surface);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pwa-full-reveal')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
        reason: 'a vertical scroll here would fight the compare gesture',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('dragging moves the divider', (tester) async {
      await _pumpReveal(tester);
      final hero = find.byType(RevealHero);
      final centre = tester.getCenter(hero);
      // A real horizontal drag across the render, and nothing about the
      // session may change because of it: comparing is looking, not making.
      await tester.dragFrom(centre, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wide window gets a BIGGER comparison, not a bigger halo',
        (tester) async {
      // iOS's 0.50-of-the-screen rule is a phone rule. Applied literally on a
      // desktop it left a small render adrift in a large blurred matte — the
      // opposite of the larger comparison surface a wide window should buy.
      await _pumpReveal(tester, size: const Size(390, 844));
      final phone = tester.getRect(find.byType(RevealHero)).width;
      await _pumpReveal(tester, size: const Size(1440, 900));
      final desktop = tester.getRect(find.byType(RevealHero)).width;
      expect(desktop, greaterThan(phone * 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the render is NOT cropped', (tester) async {
      await _pumpReveal(tester);
      final frame = find
          .descendant(
            of: find.byKey(const ValueKey('pwa-full-reveal')),
            matching: find.byType(AspectRatio),
          )
          .first;
      // The screen is called Full Reveal. Cropping it here would be the one
      // place the name is a lie.
      expect(tester.widget<AspectRatio>(frame).aspectRatio, kPwaRenderAspect);
      final r = tester.getRect(frame);
      expect(r.width / r.height, closeTo(kPwaRenderAspect, 0.01));
      expect(tester.takeException(), isNull);
    });
  });

  group('REVEAL02  the prose is gone', () {
    testWidgets('no vision-details block, no metadata strip', (tester) async {
      await _pumpReveal(tester);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.visionDetails), findsNothing);
      expect(find.text(l.visionDetails.toUpperCase()), findsNothing);
      expect(find.text(l.createdJustNow), findsNothing);
      expect(find.text('ATMOSPHERES'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the Result's paragraph is not repeated here", (tester) async {
      final c = await _pumpReveal(tester);
      // The exact sentence Ayden said on the Result screen. Saying it twice is
      // the "bla bla" this rebuild exists to remove.
      final said = c
          .read(pwaControllerProvider)
          .messages
          .firstWhere((m) => m.kind == PwaMessageKind.reveal)
          .text;
      expect(said, isNotEmpty);
      expect(find.text(said), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('what text remains is short and countable', (tester) async {
      await _pumpReveal(tester);
      // Every string on the screen, and none of them is a paragraph. The old
      // details panel carried a 40-word note; the ceiling here is a label.
      final texts = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(const ValueKey('pwa-full-reveal')),
            matching: find.byType(Text),
          ))
          .map((t) => t.data ?? '')
          .where((t) => t.trim().isNotEmpty)
          .toList();
      expect(texts, isNotEmpty);
      for (final t in texts) {
        expect(
          t.split(RegExp(r'\s+')).length,
          lessThanOrEqualTo(8),
          reason: 'the Full Reveal shows; it does not explain: "$t"',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('there is no second conversation', (tester) async {
      await _pumpReveal(tester);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('REVEAL03  explore other atmospheres', () {
    testWidgets('the section is present, and it is the second half',
        (tester) async {
      await _pumpReveal(tester);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.exploreOtherAtmospheres), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pwa-reveal-atmospheres')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('it offers the canonical catalogue, in order', (tester) async {
      final c = await _pumpReveal(tester);
      final ids = c.read(pwaControllerProvider).atmospheres.map((a) => a.id);
      expect(ids, isNotEmpty);
      final view = tester.widget<ListView>(
        find.byKey(const ValueKey('pwa-reveal-atmospheres')),
      );
      // Which atmospheres exist is NOT this screen's decision: it renders the
      // session's list, whole and in order.
      //
      // `ListView.separated` interleaves separators, so its delegate holds
      // `2n - 1` children for n cards. Stated rather than hard-coded, so this
      // reads as arithmetic instead of a magic number.
      expect(
        (view.childrenDelegate as SliverChildBuilderDelegate).childCount,
        ids.length * 2 - 1,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap STAGES — it does not generate', (tester) async {
      final c = await _pumpReveal(tester);
      final before = c.read(pwaControllerProvider).versions.length;
      final card = find.byKey(const ValueKey('pwa-reveal-atmo-soft_luxury'));
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
      await tester.pumpAndSettle();

      final s = c.read(pwaControllerProvider);
      // THE CONTRACT, unchanged: staging records a choice and spends nothing.
      // Only the confirmation below creates a vision.
      expect(s.pendingAtmosphereId, 'soft_luxury');
      expect(s.versions, hasLength(before));
      expect(s.generating, isFalse);
      expect(find.byKey(const ValueKey('pwa-reveal-pending')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-reveal-create')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the confirmation states the cost before it is paid',
        (tester) async {
      final c = await _pumpReveal(tester);
      final card = find.byKey(const ValueKey('pwa-reveal-atmo-soft_luxury'));
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
      await tester.pumpAndSettle();
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.atmosphereSelected('Soft Luxury')), findsOneWidget);
      expect(find.textContaining(l.usesOneSpace), findsOneWidget);
      // …and it can be dropped without spending anything.
      await tester.tap(find.text(l.cancel));
      await tester.pumpAndSettle();
      expect(c.read(pwaControllerProvider).pendingAtmosphereId, isNull);
      expect(c.read(pwaControllerProvider).versions, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });

  // ── The rail is a rail, and it does not move ──────────────────────────────
  //
  // REVEAL08-11. On the phone the atmosphere cards were about 310dp wide —
  // roughly 80% of the screen — because the carousel sat in an `Expanded` and
  // took whatever height the hero left over. And SELECTING one visibly
  // reflowed the whole strip: the action slot below rendered `SizedBox.shrink`
  // when idle and a two-line confirmation when a card was tapped, and that
  // ~90dp swing came straight out of the Expanded above it, resizing every
  // card in the rail.
  //
  // Both are geometry, and both are now held as arithmetic: the strip has a
  // ceiling, and the slot has a reserve. Neither depends on a screenshot.
  group('REVEAL08  the atmosphere rail is stable and browsable', () {
    /// Every card's rect, keyed by atmosphere id.
    Map<String, Rect> cardRects(WidgetTester tester, ProviderContainer c) {
      final out = <String, Rect>{};
      for (final a in c.read(pwaControllerProvider).atmospheres) {
        final f = find.byKey(ValueKey('pwa-reveal-atmo-${a.id}'));
        if (f.evaluate().isNotEmpty) out[a.id] = tester.getRect(f.first);
      }
      return out;
    }

    testWidgets('REVEAL08: selecting one does not resize ANY of them',
        (tester) async {
      final c = await _pumpReveal(tester, size: const Size(390, 844));
      final before = cardRects(tester, c);
      expect(before, isNotEmpty);

      final card = find.byKey(const ValueKey('pwa-reveal-atmo-soft_luxury'));
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
      await tester.pumpAndSettle();
      // The confirmation is up — the state that used to shrink the rail.
      expect(find.byKey(const ValueKey('pwa-reveal-pending')), findsOneWidget);

      final after = cardRects(tester, c);
      for (final id in before.keys) {
        if (!after.containsKey(id)) continue;
        expect(after[id]!.width, closeTo(before[id]!.width, 0.5),
            reason: '$id changed WIDTH when another card was selected');
        expect(after[id]!.height, closeTo(before[id]!.height, 0.5),
            reason: '$id changed HEIGHT when another card was selected');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('REVEAL09: the selected card is marked, not enlarged',
        (tester) async {
      await _pumpReveal(tester, size: const Size(390, 844));
      final card = find.byKey(const ValueKey('pwa-reveal-atmo-soft_luxury'));
      await tester.scrollUntilVisible(
        card,
        240,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('pwa-reveal-atmospheres')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      final was = tester.getRect(card.first);
      await tester.tap(card);
      await tester.pumpAndSettle();
      final now = tester.getRect(
          find.byKey(const ValueKey('pwa-reveal-atmo-soft_luxury')).first);
      // iOS marks selection with a border and a ring, never with size
      // (`atmosphere_card.dart`: `width: selected ? 2 : 1`).
      expect(now.width, closeTo(was.width, 0.5));
      expect(now.height, closeTo(was.height, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('REVEAL10: several directions are browsable at once',
        (tester) async {
      final c = await _pumpReveal(tester, size: const Size(390, 844));
      final cards = cardRects(tester, c);
      expect(cards, isNotEmpty);
      final w = cards.values.first.width;
      // iOS's OWN size for this rail, re-derived in Round 3 from the shipped
      // `before_after_screen.dart` rather than from a CHANGELOG line: the card
      // is `(strip * 1.35).clamp(170, screenW * 0.86)`, which on a 390dp phone
      // is the 0.86 ceiling — 335 wide, 221 tall. Round 2 had shrunk it to 178
      // x 108, less than half the native card, which is the "too narrow /
      // visually compressed" the phone review reported.
      expect(w, closeTo(390 * 0.86, 1.0),
          reason: 'the native rail fills 86% of the screen, by iOS clamp');
      final h = cards.values.first.height;
      expect(h, closeTo(221.0, 2.0), reason: 'and 0.82 of the strip');
      // Every card the same size — that IS the rail.
      for (final r in cards.values) {
        expect(r.width, closeTo(w, 0.5));
      }
      // …and it scrolls horizontally, so the rest are reachable.
      // The key sits ON the ListView, not around it.
      final rail = tester.widget<ListView>(
          find.byKey(const ValueKey('pwa-reveal-atmospheres')));
      expect(rail.scrollDirection, Axis.horizontal);
      expect(tester.takeException(), isNull);
    });

    testWidgets('REVEAL11: the rail geometry is identical in both states, at '
        'every phone size', (tester) async {
      for (final size in const [Size(390, 844), Size(430, 932)]) {
        final c = await _pumpReveal(tester, size: size);
        final before = cardRects(tester, c);
        c.read(pwaControllerProvider.notifier).stageAtmosphere('soft_luxury');
        await tester.pumpAndSettle();
        final after = cardRects(tester, c);
        for (final id in before.keys) {
          if (!after.containsKey(id)) continue;
          expect(after[id], before[id], reason: '$size / $id moved or resized');
        }
        // Staging still spends nothing, which is the semantic this geometry
        // work was not allowed to touch.
        expect(c.read(pwaControllerProvider).versions, hasLength(1));
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });
  });

  group('REVEAL04  the way out, and the way on', () {
    testWidgets('back returns to the conversation and carries no intent',
        (tester) async {
      final c = await _pumpReveal(tester);
      await tester.tap(find.byKey(const ValueKey('pwa-back-to-conversation')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.architect);
      expect(s.refineContextVisionId, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('EDIT carries THIS vision back to the conversation',
        (tester) async {
      // Same capability, iOS's own place: the top-left pencil, right of Back
      // ("Wave 4.9.3 — 'Refine in chat' pencil… Top-LEFT, right of Back").
      final c = await _pumpReveal(tester);
      final id = c.read(pwaControllerProvider).previewedVision!.versionId;
      final msgs = c.read(pwaControllerProvider).messages.length;
      await tester.tap(find.byKey(const ValueKey('pwa-reveal-edit')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.architect);
      expect(s.refineContextVisionId, id);
      // It says nothing on the person's behalf and generates nothing.
      expect(s.messages, hasLength(msgs));
      expect(s.versions, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('REPLAY re-runs the presentation and spends nothing',
        (tester) async {
      final c = await _pumpReveal(tester);
      final before = c.read(pwaControllerProvider);
      final msgs = before.messages.length;
      await tester.tap(find.byKey(const ValueKey('pwa-reveal-replay')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      final s = c.read(pwaControllerProvider);
      // Presentation only: iOS's replay "re-triggers the cinematic reveal in
      // place". No request, no version, no message, no Space.
      expect(s.versions, hasLength(before.versions.length));
      expect(s.messages, hasLength(msgs));
      expect(s.generating, isFalse);
      expect(s.phase, PwaPhase.reveal);
      expect(s.pendingAtmosphereId, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SHARE is offered, and shares nothing private',
        (tester) async {
      await _pumpReveal(tester);
      expect(find.byKey(const ValueKey('pwa-reveal-share')), findsOneWidget);
      // iOS shares TEXT. The render's URL is a signed, expiring Storage link
      // scoped to one account, and handing that to a share sheet would hand
      // out a credential with a lifetime — so the text names the vision and
      // carries no link at all.
      final l = pwaL10nFor(const Locale('en'));
      final text = l.shareVisionText('Soft Luxury');
      expect(text, contains('Soft Luxury'));
      expect(text, isNot(contains('http')));
      expect(text, isNot(contains('token')));
    });

    testWidgets('the vision navigator appears only when there is somewhere '
        'to go', (tester) async {
      await _pumpReveal(tester);
      // One vision: a navigator that can never move is chrome for its own sake.
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(
        find.byKey(const ValueKey('pwa-back-to-conversation')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('REVEAL05  it holds together, and it speaks', () {
    for (final size in const [
      Size(390, 844),
      Size(430, 932),
      Size(768, 1024),
      Size(1440, 900),
      Size(1920, 1080),
      Size(390, 640), // a short window: the hero must yield, not overflow
    ]) {
      testWidgets(
        'no overflow at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await _pumpReveal(tester, size: size);
          expect(
            find.byKey(const ValueKey('pwa-full-reveal')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('pwa-reveal-atmospheres')),
            findsOneWidget,
            reason: 'the atmospheres must survive a short window at $size',
          );
          expect(tester.takeException(), isNull, reason: '$size');
        },
      );
    }

    for (final code in const ['en', 'fr', 'km']) {
      testWidgets('the surface resolves in $code', (tester) async {
        await _pumpReveal(tester, locale: Locale(code));
        final l = pwaL10nFor(Locale(code));
        for (final s in [
          l.exploreOtherAtmospheres,
          // The chrome's tooltips — the actions are iOS's floating circles
          // now, so their words live in a tooltip rather than on a pill.
          l.refineWithAyden,
          l.replayReveal,
          l.shareVision,
          l.shareVisionText('Soft Luxury'),
          l.beforeLabel,
          l.shared.dragToReveal,
        ]) {
          expect(s, isNotEmpty, reason: code);
          expect(s.startsWith('pwa'), isFalse, reason: '$code: $s');
        }
        expect(l.shareVisionText('Soft Luxury'), contains('Soft Luxury'),
            reason: '$code: the vision must be named in the share text');
        expect(find.text(l.exploreOtherAtmospheres), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('REVEAL06  the typography correction', () {
    test('av7Sans names the bundled Inter, and never fetches it', () {
      // It set only a fallback chain and no family, so every screen still
      // using it rendered in the platform's default sans while the rest of the
      // product had been on Inter since Phase 1.
      final s = av7Sans(fontSize: 14);
      expect(s.fontFamily, kPwaTextFamily);
      expect(s.fontFamily, 'Inter');
      // The fallback chain is intact — Khmer still resolves through it.
      expect(s.fontFamilyFallback, contains(kPwaKhmerFamilyName));
    });

    test('av7Eyebrow does too, and keeps its Khmer tracking rule', () {
      final s = av7Eyebrow();
      expect(s.fontFamily, kPwaTextFamily);
      expect(s.fontFamilyFallback, contains(kPwaKhmerFamilyName));
    });

    testWidgets('the Full Reveal actually renders in Inter', (tester) async {
      await _pumpReveal(tester);
      final l = pwaL10nFor(const Locale('en'));
      final header = tester.widget<Text>(find.text(l.exploreOtherAtmospheres));
      expect(header.style?.fontFamily, kPwaTextFamily);
      expect(tester.takeException(), isNull);
    });
  });
}
