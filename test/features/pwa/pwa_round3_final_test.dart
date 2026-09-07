// Round 3 — the last three phone findings, pinned.
//
//   SEL — the Full Reveal rail highlighted the CURRENT vision's atmosphere
//         while the bar beneath it said "Soft Luxury selected". One tick, two
//         states. The tick now follows the PENDING choice while one exists.
//   CAN — a portrait render made the whole card a 2:3 strip. iOS never lets
//         the picture be the frame: a fixed canvas (`_GeneratedImageCard`,
//         `before_after_screen`) with the picture CONTAINed inside at its own
//         ratio over a blurred continuation of itself. `pwa_render_canvas.dart`.
//   HOME — the Home hero was `visibleProjects.first`, so the last generated
//         room replaced the approved Before/After. The hero is the curated
//         showcase; the person's work is Continue Designing.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/data/mock/mock_projects.dart'
    show featuredShowcase;
import 'package:ai_home_architect/features/cards/widgets/atmosphere_hero_card.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_render_aspect.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_render_canvas.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_reveal_screen.dart';
import 'package:ai_home_architect/shared/widgets/reveal_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png(int w, int h) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF8899AA),
  );
  final img = await rec.endRecording().toImage(w, h);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
}

AydenImageSource _source(Uint8List bytes) =>
    AydenImageSource(bytes: bytes, filename: 'room.png', mimeType: 'image/png');

Widget _app(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        supportedLocales: PwaL10n.supportedLocales,
        localizationsDelegates: const [
          PwaL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const PwaExperience(),
      ),
    );

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A Warm Modern first vision, opened in its Full Reveal, on a 390x844 phone.
/// [renderAspect] declares the render's shape ahead of its decode.
/// [fakeGen] counts generation calls (the SEL tests); without it the mock
/// repository renders a bundle asset, which is resolvable, so the canvas has
/// a real provider to blur (the CAN tests).
Future<(ProviderContainer, PwaFakeGenerationService, PwaRenderAspects)>
    _pumpReveal(WidgetTester tester,
        {double? renderAspect,
        Size size = const Size(390, 844),
        bool fakeGen = true}) async {
  _size(tester, size);
  final png = (await tester.runAsync(() => _png(20, 30)))!;
  final gen = PwaFakeGenerationService();
  final aspects = PwaRenderAspects();
  final c = ProviderContainer(overrides: [
    pwaRepositoryProvider.overrideWithValue(
      MockPwaExperienceRepository(workDelay: Duration.zero, seedLibrary: false),
    ),
    if (fakeGen) pwaGenerationServiceProvider.overrideWithValue(gen),
    if (fakeGen)
      pwaPendingGenerationStoreProvider
          .overrideWithValue(PwaMemoryPendingGenerationStore()),
    pwaRenderAspectsProvider.overrideWith((ref) => aspects),
  ]);
  addTearDown(c.dispose);
  final n = c.read(pwaControllerProvider.notifier);
  n.newProject();
  n.setSource(_source(png), origin: PwaImageOrigin.userUpload);
  n.selectRoom('living_room');
  n.selectEntryAtmosphere('warm_modern');
  await n.generateFirstVision();
  gen.calls.clear();
  final vision = c.read(pwaControllerProvider).currentVision!;
  if (renderAspect != null) {
    aspects.record(vision.afterAsset, (renderAspect * 1000).round(), 1000);
  }
  n.openReveal(vision.versionId);
  await tester.pumpWidget(_app(c));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return (c, gen, aspects);
}

/// The rail builds only what is on screen; on a 390 phone Soft Luxury is not.
/// The selection tests are about STATE, not geometry, so they run in a window
/// wide enough that every card is built.
const Size _wide = Size(1200, 900);

bool _isSelected(WidgetTester tester, String atmosphereId) => tester
    .widget<AtmosphereHeroCard>(
        find.byKey(ValueKey('pwa-reveal-atmo-$atmosphereId')))
    .selected;

Rect _cardRect(WidgetTester tester, String atmosphereId) =>
    tester.getRect(find.byKey(ValueKey('pwa-reveal-atmo-$atmosphereId')));

void main() {
  group('SEL  the rail highlights the pending choice', () {
    testWidgets('SEL01: at rest, the current atmosphere is the one highlighted',
        (tester) async {
      final (c, _, _) = await _pumpReveal(tester, size: _wide);
      expect(c.read(pwaControllerProvider).currentVision!.atmosphereId,
          'warm_modern');
      expect(c.read(pwaControllerProvider).pendingAtmosphereId, isNull);
      expect(_isSelected(tester, 'warm_modern'), isTrue);
      expect(_isSelected(tester, 'ayden_signature'), isFalse);
    });

    testWidgets(
        'SEL02: tapping Soft Luxury moves the highlight to it — and off '
        'Warm Modern — before anything is generated', (tester) async {
      final (c, gen, _) = await _pumpReveal(tester, size: _wide);
      final l = pwaL10nFor(const Locale('en'));
      final warmBefore = _cardRect(tester, 'warm_modern');

      final soft = find.byKey(const ValueKey('pwa-reveal-atmo-soft_luxury'));
      await tester.tap(soft);
      await tester.pump();

      final s = c.read(pwaControllerProvider);
      expect(s.pendingAtmosphereId, 'soft_luxury');
      expect(s.currentVision!.atmosphereId, 'warm_modern',
          reason: 'the CURRENT vision is untouched by staging');
      // The three surfaces read ONE state now.
      expect(_isSelected(tester, 'soft_luxury'), isTrue);
      expect(_isSelected(tester, 'warm_modern'), isFalse);
      expect(find.text(l.atmosphereSelected('Soft Luxury')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-reveal-create')), findsOneWidget);
      expect(gen.calls, isEmpty, reason: 'staging generates nothing');
      // Selection does not move the rail.
      expect(_cardRect(tester, 'warm_modern').size, warmBefore.size);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SEL03: Cancel clears the choice and the highlight returns',
        (tester) async {
      final (c, gen, _) = await _pumpReveal(tester, size: _wide);
      c.read(pwaControllerProvider.notifier).stageAtmosphere('soft_luxury');
      await tester.pump();
      expect(_isSelected(tester, 'soft_luxury'), isTrue);
      expect(_isSelected(tester, 'warm_modern'), isFalse);

      c.read(pwaControllerProvider.notifier).cancelPendingAtmosphere();
      await tester.pump();
      expect(c.read(pwaControllerProvider).pendingAtmosphereId, isNull);
      expect(_isSelected(tester, 'warm_modern'), isTrue);
      expect(_isSelected(tester, 'soft_luxury'), isFalse);
      expect(gen.calls, isEmpty);
    });

    testWidgets(
        'SEL04: Create Vision generates the PENDING atmosphere, exactly once, '
        'and the new vision carries it', (tester) async {
      final (c, gen, _) = await _pumpReveal(tester, size: _wide);
      final n = c.read(pwaControllerProvider.notifier);
      n.stageAtmosphere('soft_luxury');
      await tester.pump();
      expect(_isSelected(tester, 'soft_luxury'), isTrue);

      await n.applyAtmosphere();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(gen.calls, hasLength(1));
      expect(gen.calls.single.atmosphereId, 'soft_luxury');
      final s = c.read(pwaControllerProvider);
      expect(s.versions, hasLength(2));
      expect(s.currentVision!.atmosphereId, 'soft_luxury');
      expect(s.pendingAtmosphereId, isNull);
      expect(s.phase, PwaPhase.architect,
          reason: 'the reveal is left the moment Create is confirmed');
    });

    testWidgets('SEL05: back in the reveal, the NEW current is highlighted',
        (tester) async {
      final (c, _, _) = await _pumpReveal(tester, size: _wide);
      final n = c.read(pwaControllerProvider.notifier);
      n.stageAtmosphere('soft_luxury');
      await n.applyAtmosphere();
      n.openReveal(c.read(pwaControllerProvider).currentVision!.versionId);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_isSelected(tester, 'soft_luxury'), isTrue);
      expect(_isSelected(tester, 'warm_modern'), isFalse);
    });
  });

  group('CAN  the iOS canvas around a measured render', () {
    // The canvas RULE, on real pixels of every orientation. `PwaCanvasSurface`
    // is what both the result card and the Full Reveal draw; the aspect it is
    // given is the decoded one in production (pwa_render_aspect.dart).
    Future<(Rect, Rect)> pumpSurface(
      WidgetTester tester, {
      required Size outer,
      required (int, int) pixels,
      required PwaCanvasStyle style,
    }) async {
      final bytes = (await tester.runAsync(() => _png(pixels.$1, pixels.$2)))!;
      final aspect = pixels.$1 / pixels.$2;
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: outer.width,
            height: outer.height,
            child: PwaCanvasSurface(
              key: const ValueKey('surface'),
              ambient: MemoryImage(bytes),
              aspect: aspect,
              style: style,
              child: Image(image: MemoryImage(bytes), fit: BoxFit.cover),
            ),
          ),
        ),
      ));
      await tester.pump();
      final canvas = tester.getRect(find.byKey(const ValueKey('surface')));
      final inner = tester.getRect(find.byType(AspectRatio));
      return (canvas, inner);
    }

    for (final (label, px) in [
      ('portrait 1024x1536', (1024, 1536)),
      ('landscape 1536x1024', (1536, 1024)),
      ('square 1024x1024', (1024, 1024)),
    ]) {
      for (final style in PwaCanvasStyle.values) {
        testWidgets('CAN01 $label on the ${style.name} canvas: contained, '
            'centred, whole, with the matte behind', (tester) async {
          const outer = Size(366, 336); // the phone reveal block
          final (canvas, inner) = await pumpSurface(tester,
              outer: outer, pixels: px, style: style);
          final aspect = px.$1 / px.$2;
          // The OUTER surface is exactly what it was given: the render's
          // orientation never resizes it.
          expect(canvas.size, outer);
          // The INNER frame is the largest box of the render's ratio inside.
          final want = PwaRenderCanvas.innerRect(outer, aspect);
          expect(inner.width, closeTo(want.width, 0.5));
          expect(inner.height, closeTo(want.height, 0.5));
          expect(inner.width / inner.height, closeTo(aspect, 0.01));
          expect(inner.center.dx, closeTo(canvas.center.dx, 0.5));
          expect(inner.center.dy, closeTo(canvas.center.dy, 0.5));
          expect(inner.width, lessThanOrEqualTo(canvas.width + 0.5));
          expect(inner.height, lessThanOrEqualTo(canvas.height + 0.5));
          // Never a 3:2 frame around it.
          expect(tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
              closeTo(aspect, 1e-9));
          // The matte: a blurred layer beneath, in both styles.
          expect(find.byType(ImageFiltered), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('CAN02: portrait leaves a matte on both sides; landscape a '
        'matte above and below; square both', (tester) async {
      const outer = Size(366, 336);
      final (_, portrait) = await pumpSurface(tester,
          outer: outer, pixels: (1024, 1536), style: PwaCanvasStyle.reveal);
      expect(portrait.height, closeTo(336, 0.5));
      expect(portrait.width, closeTo(224, 0.5));
      expect(366 - portrait.width, greaterThan(100));
      final (_, landscape) = await pumpSurface(tester,
          outer: outer, pixels: (1536, 1024), style: PwaCanvasStyle.reveal);
      expect(landscape.width, closeTo(366, 0.5));
      expect(landscape.height, closeTo(244, 0.5));
      final (_, square) = await pumpSurface(tester,
          outer: outer, pixels: (1024, 1024), style: PwaCanvasStyle.reveal);
      expect(square.width, closeTo(336, 0.5));
      expect(square.height, closeTo(336, 0.5));
    });

    // End to end, with the aspect the mock render REALLY has (it is measured
    // off its decode, and the truth always wins over a seed).
    testWidgets('CAN03: the Full Reveal block is iOS\'s and does not follow '
        'the render; the slider is the contained picture', (tester) async {
      final (c, _, aspects) = await _pumpReveal(tester, fakeGen: false);
      // The bundle asset decodes as real async work; give it real time, then
      // let the recording microtask and a relayout run.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final vision = c.read(pwaControllerProvider).currentVision!;
      final measured = aspects.state[vision.afterAsset];
      expect(measured, isNotNull, reason: 'the render was measured');
      final canvasFinder =
          find.byKey(ValueKey('full-reveal-canvas-${vision.versionId}'));
      final canvas = tester.getRect(canvasFinder);
      final frame = find
          .descendant(of: canvasFinder, matching: find.byType(AspectRatio))
          .first;
      final inner = tester.getRect(frame);
      expect(canvas.width, closeTo(366, 1));
      final box = tester.getSize(find.byKey(const ValueKey('pwa-full-reveal')));
      final available = box.height -
          (kPwaRevealSectionHeaderH +
              pwaRevealStripHeight(box.height, box.width) +
              kPwaRevealSlotH +
              kPwaRevealSlotPadV);
      final heroH = pwaRevealHeroHeight(
        blockH: [pwaRevealBlockHeight(box.height), 366 / measured!]
            .reduce((a, b) => a > b ? a : b),
        available: available,
        chromeH: kPwaRevealChromeH,
        footH: kPwaRevealFootH,
      );
      expect(canvas.height,
          closeTo(heroH - kPwaRevealChromeH - kPwaRevealFootH, 1));
      final want = PwaRenderCanvas.innerRect(canvas.size, measured);
      expect(inner.width, closeTo(want.width, 1));
      expect(inner.height, closeTo(want.height, 1));
      expect(inner.center.dx, closeTo(canvas.center.dx, 1));
      expect(inner.center.dy, closeTo(canvas.center.dy, 1));
      expect(canvas.height, greaterThan(inner.height + 20),
          reason: 'a landscape render sits on the block with matte above '
              'and below — the block is not the render');
      expect(
        find.descendant(of: canvasFinder, matching: find.byType(ImageFiltered)),
        findsOneWidget,
      );
      final hero = tester.getRect(find.byType(RevealHero));
      expect(hero.width, closeTo(inner.width, 1));
      expect(hero.height, closeTo(inner.height, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('CAN04: the chat result card is iOS\'s canvas: fixed height, '
        'contained picture, expand control on the canvas corner, caption below',
        (tester) async {
      final (c, _, aspects) = await _pumpReveal(tester, fakeGen: false);
      c.read(pwaControllerProvider.notifier).backToConversation();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final vision = c.read(pwaControllerProvider).currentVision!;
      final measured = aspects.state[vision.afterAsset]!;
      final canvasFinder =
          find.byKey(ValueKey('vision-canvas-${vision.versionId}'));
      final canvas = tester.getRect(canvasFinder);
      final screen = MediaQuery.sizeOf(tester.element(canvasFinder));
      expect(canvas.height, closeTo(pwaRenderCanvasHeight(screen), 1));
      expect(canvas.width, greaterThan(300));
      final frame = find
          .descendant(of: canvasFinder, matching: find.byType(AspectRatio))
          .first;
      final inner = tester.getRect(frame);
      expect(tester.widget<AspectRatio>(frame).aspectRatio,
          closeTo(measured, 1e-6));
      final want = PwaRenderCanvas.innerRect(canvas.size, measured);
      expect(inner.width, closeTo(want.width, 1));
      expect(inner.height, closeTo(want.height, 1));
      expect(inner.center.dx, closeTo(canvas.center.dx, 1));
      expect(inner.center.dy, closeTo(canvas.center.dy, 1));
      // The expand control sits on the OUTER canvas's top-right corner.
      final icons = find.descendant(
          of: find.byKey(const ValueKey('pwa-result-vision')),
          matching: find.byType(Icon));
      final corner = tester
          .widgetList(icons)
          .indexed
          .map((e) => tester.getRect(icons.at(e.$1)))
          .where((r) => r.top < canvas.top + 48 && r.right > canvas.right - 48)
          .toList();
      expect(corner, isNotEmpty, reason: 'expand icon on the canvas corner');
      // The caption stays under the canvas.
      final caption = tester.getTopLeft(find.textContaining('Vision 1'));
      expect(caption.dy, greaterThanOrEqualTo(canvas.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('CAN05: a portrait photo frames the WORKING card portrait on the '
        'same canvas height — no 3:2 flash, no jump on arrival',
        (tester) async {
      _size(tester, const Size(390, 844));
      final png = (await tester.runAsync(() => _png(20, 30)))!;
      final c = ProviderContainer(overrides: [
        pwaRepositoryProvider.overrideWithValue(
          MockPwaExperienceRepository(workDelay: const Duration(minutes: 5)),
        ),
      ]);
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      n.newProject();
      n.setSource(_source(png), origin: PwaImageOrigin.userUpload);
      n.selectRoom('living_room');
      n.selectEntryAtmosphere('warm_modern');
      // ignore: unawaited_futures
      n.generateFirstVision();
      await tester.pumpWidget(_app(c));
      await tester.pump();
      await tester.pump();
      final working = find.byKey(const ValueKey('pwa-working-source'));
      expect(working, findsOneWidget);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump();
      await tester.pump();
      final frame =
          find.ancestor(of: working, matching: find.byType(AspectRatio)).first;
      expect(tester.widget<AspectRatio>(frame).aspectRatio, closeTo(2 / 3, 1e-3));
      // The working canvas has the result canvas's height already.
      final screen = MediaQuery.sizeOf(tester.element(working));
      final inner = tester.getRect(frame);
      expect(inner.height, closeTo(pwaRenderCanvasHeight(screen), 1));
      await tester.pump(const Duration(minutes: 6));
    });
  });

  group('HOME  the hero is curated; the work is Continue Designing', () {
    Future<ProviderContainer> pumpHome(WidgetTester tester) async {
      _size(tester, const Size(900, 1500));
      final c = ProviderContainer(overrides: [
        pwaRepositoryProvider.overrideWithValue(
          MockPwaExperienceRepository(workDelay: Duration.zero, seedLibrary: false),
        ),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(c));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return c;
    }

    testWidgets('HOME01: generating a project and coming Back leaves the hero '
        'untouched; the project appears in Continue Designing',
        (tester) async {
      final c = await pumpHome(tester);
      expect(find.byKey(const ValueKey('pwa-home-showcase')), findsOneWidget);
      expect(find.text(featuredShowcase.first.title), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-home-recent')), findsNothing);

      final n = c.read(pwaControllerProvider.notifier);
      n.newProject();
      n.setSource(_source(Uint8List.fromList(const [1, 2, 3])));
      n.selectRoom('bedroom');
      n.selectEntryAtmosphere('warm_modern');
      await n.generateFirstVision();
      await tester.pump();
      n.openHome();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final projects = c.read(pwaControllerProvider).visibleProjects;
      expect(projects, hasLength(1));
      // Hero: the same curated showcase.
      expect(find.byKey(const ValueKey('pwa-home-showcase')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-home-featured')), findsNothing);
      expect(find.text(featuredShowcase.first.title), findsOneWidget);
      // Continue Designing: the Bedroom.
      expect(find.byKey(const ValueKey('pwa-home-recent')), findsOneWidget);
      expect(
        find.byKey(ValueKey('pwa-home-recent-${projects.first.projectId}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('HOME02: a second project reorders the rail, not the hero',
        (tester) async {
      final c = await pumpHome(tester);
      final n = c.read(pwaControllerProvider.notifier);
      for (final room in ['bedroom', 'kitchen']) {
        n.newProject();
        n.setSource(_source(Uint8List.fromList(const [1, 2, 3])));
        n.selectRoom(room);
        n.selectEntryAtmosphere('warm_modern');
        await n.generateFirstVision();
        await tester.pump();
        n.openHome();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(const ValueKey('pwa-home-showcase')), findsOneWidget);
        expect(find.text(featuredShowcase.first.title), findsOneWidget);
      }
      final projects = c.read(pwaControllerProvider).visibleProjects;
      expect(projects, hasLength(2));
      final rail = tester.widget<ListView>(
          find.byKey(const ValueKey('pwa-home-recent-rail')));
      expect(rail.semanticChildCount, 2);
      expect(
        find.byKey(ValueKey('pwa-home-recent-${projects.first.projectId}')),
        findsOneWidget,
      );
    });

    testWidgets('HOME03: hydrating a library (sign in / sign out) reorders '
        'Continue Designing and never the hero', (tester) async {
      final c = await pumpHome(tester);
      final n = c.read(pwaControllerProvider.notifier);
      n.newProject();
      n.setSource(_source(Uint8List.fromList(const [1, 2, 3])));
      n.selectRoom('bedroom');
      n.selectEntryAtmosphere('warm_modern');
      await n.generateFirstVision();
      await tester.pump();
      // The identity seam every sign-in / sign-out goes through.
      await n.reloadForIdentity();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(c.read(pwaControllerProvider).phase, PwaPhase.home);
      expect(find.byKey(const ValueKey('pwa-home-showcase')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-home-featured')), findsNothing);
      expect(find.text(featuredShowcase.first.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
