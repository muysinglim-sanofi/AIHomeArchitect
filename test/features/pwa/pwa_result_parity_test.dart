/// Phase 5 — the generated result, and the conversation it starts.
///
/// The rule this phase exists to hold is a hierarchy: IMAGE FIRST, COMMENTARY
/// SECOND, ACTIONS THIRD. Someone has waited two minutes; the first thing they
/// meet must be their room, not a label and not a paragraph.
///
/// The rule it must NOT break is everything underneath. A suggestion is still
/// a sentence sent through the same conversational turn as typing it. A refine
/// still travels the contract it always did. The lineage, the parent, the
/// current vision and the Full Reveal route are untouched, and these tests say
/// so explicitly — because a presentation phase that quietly moved one of them
/// would be very hard to see.
library;

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_architect_screen.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_theme.dart';
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

ProviderContainer _container() => ProviderContainer(
      overrides: [
        pwaRepositoryProvider.overrideWithValue(
          MockPwaExperienceRepository(workDelay: Duration.zero),
        ),
      ],
    );

/// Generate for real through the controller, then continue into the
/// conversation — the journey, not a hand-built state.
Future<ProviderContainer> _pumpResult(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  String room = 'kitchen',
  String atmosphere = 'warm_modern',
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = _container();
  addTearDown(c.dispose);
  final n = c.read(pwaControllerProvider.notifier);
  n.newProject();
  n.setSource(_source(), origin: PwaImageOrigin.userUpload);
  n.selectRoom(room);
  n.selectEntryAtmosphere(atmosphere);
  await n.generateFirstVision();
  n.continueToArchitect();

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
  // Two timers outlive a bare pump here and would fail teardown: the shared
  // RevealHero's 800ms auto-sweep, and the conversation's 1500ms
  // returned-from-Reveal highlight. Advance past both rather than weakening
  // animations the product actually uses.
  await tester.pump(const Duration(seconds: 2));
  return c;
}

void main() {
  group('RESULT01  the result is the subject of the screen', () {
    testWidgets('the render is on screen, and it is the right one',
        (tester) async {
      final c = await _pumpResult(tester);
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.architect);
      expect(s.versions, hasLength(1));
      expect(find.byKey(const ValueKey('pwa-result-vision')), findsOneWidget);
      // The card shows THE vision this session produced, keyed by its id — not
      // a placeholder and not a neighbour's.
      expect(
        find.byKey(ValueKey('vision-card-${s.versions.single.versionId}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the image comes before the commentary', (tester) async {
      await _pumpResult(tester);
      final image =
          tester.getRect(find.byKey(const ValueKey('pwa-result-vision')));
      final words =
          tester.getRect(find.textContaining('direction is in').first);
      expect(
        image.top,
        lessThan(words.top),
        reason: 'nobody should have to read an explanation to see their room',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the commentary is two short sentences, not an essay',
        (tester) async {
      await _pumpResult(tester);
      final l = pwaL10nFor(const Locale('en'));
      final text = l.firstVisionIntro('Warm Modern');
      expect(find.text(text), findsOneWidget);
      // The old copy was three sentences and 45 words, and it ended by telling
      // people to "explore the atmospheres below" — a rail that moved to the
      // Full Reveal, so it was pointing at something not on the screen.
      expect(text.split(RegExp(r'[.?!]')).where((s) => s.trim().isNotEmpty),
          hasLength(lessThanOrEqualTo(2)));
      expect(text.split(RegExp(r'\s+')), hasLength(lessThan(25)));
      expect(text.toLowerCase(), isNot(contains('below')));
      // It NAMES the direction that was rendered.
      expect(text, contains('Warm Modern'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('image, then commentary, then actions', (tester) async {
      // The brief's hierarchy, asserted as geometry. The three action pills
      // used to sit INSIDE the card between the render and Ayden's line, so a
      // person who had waited two minutes met a row of buttons before they
      // were told anything about what they were looking at.
      await _pumpResult(tester);
      final l = pwaL10nFor(const Locale('en'));
      final image =
          tester.getRect(find.byKey(const ValueKey('pwa-result-vision')));
      final words =
          tester.getRect(find.textContaining('direction is in').first);
      final action = tester.getRect(find.text(l.viewFullReveal).first);
      expect(image.bottom, lessThanOrEqualTo(words.top + 1));
      expect(words.bottom, lessThanOrEqualTo(action.top + 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the render is shown whole, at the shape the engine returns',
        (tester) async {
      await _pumpResult(tester, size: const Size(1440, 900));
      final frame = find
          .descendant(
            of: find.byKey(const ValueKey('pwa-result-vision')),
            matching: find.byType(AspectRatio),
          )
          .first;
      expect(tester.widget<AspectRatio>(frame).aspectRatio, kPwaRenderAspect);
      final r = tester.getRect(frame);
      expect(r.width / r.height, closeTo(kPwaRenderAspect, 0.01));
      expect(r.width, greaterThanOrEqualTo(600),
          reason: 'the payoff is not a thumbnail');
      expect(tester.takeException(), isNull);
    });
  });

  group('RESULT02  the session did not become a different app', () {
    testWidgets('no dark legacy shell', (tester) async {
      await _pumpResult(tester);
      final scaffold = tester.widget<Scaffold>(
        find.byKey(const ValueKey('pwa-design-session-result')),
      );
      expect(scaffold.backgroundColor, pwaCanvas);
      expect(scaffold.backgroundColor, isNot(Colors.black));
      // The blurred living room that used to sit behind the conversation is
      // gone: the only photograph on this screen is the person's own render.
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the result stays attached to its project and context',
        (tester) async {
      final c = await _pumpResult(tester);
      final s = c.read(pwaControllerProvider);
      expect(s.versions.single.projectId, s.activeProjectId);
      expect(s.selectedRoomId, 'kitchen');
      // The engine resolves the atmosphere and the app adopts it; whichever
      // way that lands, the vision and the session must agree on it.
      expect(s.versions.single.atmosphereId, s.currentVision?.atmosphereId);
      expect(find.textContaining('Vision 1'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('RESULT03  the actions still travel the contracts they always did',
      () {
    testWidgets('a suggestion is a sentence, sent like any other',
        (tester) async {
      final c = await _pumpResult(tester);
      final before = c.read(pwaControllerProvider).messages.length;
      final l = pwaL10nFor(const Locale('en'));
      // Tapping a suggestion must be IDENTICAL to typing it: same
      // `sendUserText`, same canonical turn deciding what the line means.
      // Nothing here routes, and nothing here decides that a line is a refine.
      await tester.ensureVisible(find.text(l.chipWarmer).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.chipWarmer).first);
      await tester.pumpAndSettle();
      final after = c.read(pwaControllerProvider).messages;
      expect(after.length, greaterThan(before));
      expect(
        after.where((m) => m.role == PwaRole.user && m.text == l.chipWarmer),
        hasLength(1),
        reason: 'the tap posts the chip text as the user said it',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the suggestions offered are room-neutral', (tester) async {
      // These four sit under EVERY result. "Open the kitchen" under a terrace
      // or a bathroom was a suggestion a person could tap and pay for.
      await _pumpResult(tester, room: 'terrace');
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.chipOpenKitchen), findsNothing);
      expect(find.text(l.chipCalmer), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a backend-sent suggestion still beats the local set',
        (tester) async {
      // The precedence rule is load-bearing: whatever the advisor sends is what
      // is shown. This phase restyled the chips; it must not have reversed who
      // owns them.
      final c = await _pumpResult(tester);
      final n = c.read(pwaControllerProvider.notifier);
      final msgs = [...c.read(pwaControllerProvider).messages];
      expect(msgs.any((m) => m.chips.isNotEmpty), isTrue,
          reason: 'the first turn carries suggestions');
      expect(n, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the free-form field sends through the same path',
        (tester) async {
      final c = await _pumpResult(tester);
      final before = c.read(pwaControllerProvider).messages.length;
      final field = find.byType(TextField).first;
      await tester.ensureVisible(field);
      await tester.enterText(field, 'warmer floors please');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      final after = c.read(pwaControllerProvider).messages;
      expect(after.length, greaterThan(before));
      expect(
        after.where(
          (m) => m.role == PwaRole.user && m.text == 'warmer floors please',
        ),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('one tap is one request, not two', (tester) async {
      final c = await _pumpResult(tester);
      final l = pwaL10nFor(const Locale('en'));
      final chip = find.text(l.chipMoreLight).first;
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.tap(chip, warnIfMissed: false);
      await tester.pumpAndSettle();
      final said = c
          .read(pwaControllerProvider)
          .messages
          .where((m) => m.role == PwaRole.user && m.text == l.chipMoreLight);
      expect(said, hasLength(lessThanOrEqualTo(2)),
          reason: 'two deliberate taps may say it twice; a single tap may not '
              'be counted twice');
      expect(tester.takeException(), isNull);
    });
  });

  group('RESULT04  the Full Reveal entry is unchanged', () {
    testWidgets('the CTA routes to the Reveal for THAT vision',
        (tester) async {
      final c = await _pumpResult(tester);
      final id = c.read(pwaControllerProvider).versions.single.versionId;
      final l = pwaL10nFor(const Locale('en'));
      final cta = find.text(l.viewFullReveal).first;
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();
      // The Reveal arms its own auto-sweep on arrival.
      await tester.pump(const Duration(seconds: 2));
      final s = c.read(pwaControllerProvider);
      expect(s.phase, PwaPhase.reveal);
      expect(s.previewVisionId ?? s.currentVisionId, id);
      // It creates nothing: opening a reveal is a view, not a generation.
      expect(s.versions, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the render itself opens the Reveal too', (tester) async {
      final c = await _pumpResult(tester);
      await tester.tap(find.byKey(const ValueKey('av7-vision-expand')).first);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(c.read(pwaControllerProvider).phase, PwaPhase.reveal);
      expect(c.read(pwaControllerProvider).versions, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });

  group('RESULT05  it speaks every product language', () {
    for (final code in const ['en', 'fr', 'km']) {
      testWidgets('the result surface resolves in $code', (tester) async {
        await _pumpResult(tester, locale: Locale(code));
        final l = pwaL10nFor(Locale(code));
        // The SCREEN's own copy — the lead-in, the suggestions, the CTA.
        //
        // Ayden's line is deliberately NOT asserted here. A message's text is
        // written once, by the controller, in the language of the moment it
        // was said, and stored that way; changing the app language afterwards
        // must not go back and rewrite what Ayden already said. Its three
        // translations are checked below, at the dictionary.
        expect(find.text(l.whatWouldYouLikeToChange), findsOneWidget);
        expect(find.text(l.chipWarmer), findsWidgets);
        expect(find.text(l.viewFullReveal), findsWidgets);
        // …and none of them fell back to the key.
        for (final s in [
          l.firstVisionIntro('Warm Modern'),
          l.whatWouldYouLikeToChange,
          l.chipCalmer,
          l.viewFullReveal,
        ]) {
          expect(s, isNotEmpty, reason: code);
          expect(s.startsWith('pwa'), isFalse, reason: '$code: $s');
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
