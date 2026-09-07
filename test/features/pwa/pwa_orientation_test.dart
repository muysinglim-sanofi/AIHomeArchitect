// A portrait photo stays portrait — through the request, the asset, the chat
// and the Full Reveal.
//
// Round 3, phone review: "a source room photo is PORTRAIT; after generation
// Ayden returns a LANDSCAPE result". The bucket disagreed — that project's
// original is 720×1280 and its render 1024×1536, both portrait — and the
// engine's rule (`_detect_output_size`) is orientation-preserving on every
// path the web uses. What was landscape was the FRAME: `AspectRatio(3 / 2)`
// around a `BoxFit.cover` image, on the result card and on the Full Reveal.
//
// The fix is iOS's own mechanism: the frame takes the decoded render's
// `width / height`. These tests pin that, the landscape case that must not
// move, and the geometry rule the Full Reveal derives from it.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
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

/// A real PNG of [w]×[h], made by the engine under test rather than typed in.
Future<Uint8List> _png(int w, int h) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF8899AA),
  );
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

AydenImageSource _source(Uint8List bytes) => AydenImageSource(
      bytes: bytes,
      filename: 'room.png',
      mimeType: 'image/png',
    );

/// The reveal, pumped with a hand on the aspect cache so a render can be
/// declared portrait BEFORE the screen lays out — as the decode would.
Future<(ProviderContainer, PwaRenderAspects)> _pumpReveal(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double? renderAspect,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Encoding a PNG and decoding an image are REAL async work; under the test
  // binding's fake clock they never complete unless run through `runAsync`.
  final png = (await tester.runAsync(() => _png(20, 30)))!;
  final aspects = PwaRenderAspects();
  final c = ProviderContainer(overrides: [
    pwaRepositoryProvider.overrideWithValue(
      MockPwaExperienceRepository(workDelay: Duration.zero),
    ),
    pwaRenderAspectsProvider.overrideWith((ref) => aspects),
  ]);
  addTearDown(c.dispose);
  final n = c.read(pwaControllerProvider.notifier);
  n.newProject();
  n.setSource(_source(png), origin: PwaImageOrigin.userUpload);
  n.selectRoom('living_room');
  n.selectEntryAtmosphere('warm_modern');
  await n.generateFirstVision();
  final vision = c.read(pwaControllerProvider).currentVision!;
  if (renderAspect != null) {
    aspects.record(vision.afterAsset, (renderAspect * 1000).round(), 1000);
  }
  n.openReveal(vision.versionId);

  await tester.pumpWidget(
    UncontrolledProviderScope(
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
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return (c, aspects);
}

void main() {
  group('ORI  the aspect cache', () {
    test('ORI01: unmeasured is the engine\'s landscape; measured is itself',
        () {
      final a = PwaRenderAspects();
      expect(pwaAspectOf(a.state, 'x'), kPwaRenderAspect);
      a.record('x', 1024, 1536);
      expect(pwaAspectOf(a.state, 'x'), closeTo(2 / 3, 1e-9));
      a.record('y', 1536, 1024);
      expect(pwaAspectOf(a.state, 'y'), closeTo(3 / 2, 1e-9));
      // Garbage is ignored, and an unchanged value does not churn the state.
      final before = a.state;
      a.record('', 1, 1);
      a.record('x', 0, 10);
      a.record('x', 1024, 1536);
      expect(identical(a.state, before), isTrue);
    });

    testWidgets('ORI02: an in-memory portrait photo is measured as portrait',
        (tester) async {
      final bytes = (await tester.runAsync(() => _png(20, 30)))!;
      final aspects = PwaRenderAspects();
      await tester.runAsync(() async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            pwaRenderAspectsProvider.overrideWith((ref) => aspects)
          ],
          child: MaterialApp(
            home: Center(
              child: SizedBox(
                width: 100,
                height: 100,
                child: PwaMemoryImage(bytes: bytes, aspectKey: 'p'),
              ),
            ),
          ),
        ));
        // The decode is real async; give it real time, then let the microtask
        // that records it run.
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();
      expect(aspects.state['p'], closeTo(20 / 30, 1e-9));
      expect(tester.takeException(), isNull);
    });
  });

  group('ORI  the Full Reveal hero rule', () {
    const chrome = kPwaRevealChromeH;
    const foot = kPwaRevealFootH;

    test('ORI03: the block is the iOS fixed image block, not the render', () {
      // iOS: (screenH * 0.50).clamp(340, 500) - 34.
      expect(pwaRevealBlockHeight(800), 366);
      expect(pwaRevealBlockHeight(900), 416);
      expect(pwaRevealBlockHeight(1200), 466);
      expect(pwaRevealBlockHeight(500), 306);
    });

    test('ORI04: on a phone the rail and the slot bound it — same for any '
        'orientation', () {
      // 390x844 phone, 800-tall box: 366 + 48 + 34 = 448 > 374 available.
      for (final aspect in [2 / 3, 3 / 2, 1.0]) {
        final h = pwaRevealHeroHeight(
          blockH: pwaRevealBlockHeight(800),
          available: 374,
          chromeH: chrome,
          footH: foot,
        );
        expect(h, 374, reason: 'aspect $aspect plays no part in the block');
      }
      // The render inside that block is contained at its own ratio: a
      // portrait render is 292 tall and ~195 wide, a landscape one 366 wide
      // and 244 tall — both whole, both centred on the blurred matte.
      final block = Size(366, 374 - chrome - foot);
      final portrait = PwaRenderCanvas.innerRect(block, 2 / 3).size;
      expect(portrait.height, closeTo(292, 0.01));
      expect(portrait.width, closeTo(194.67, 0.01));
      final landscape = PwaRenderCanvas.innerRect(block, 3 / 2).size;
      expect(landscape.width, closeTo(366, 0.01));
      expect(landscape.height, closeTo(244, 0.01));
      final square = PwaRenderCanvas.innerRect(block, 1).size;
      expect(square.width, closeTo(292, 0.01));
      expect(square.height, closeTo(292, 0.01));
    });

    test('ORI05: clamped to what is available, floored at 160', () {
      expect(
        pwaRevealHeroHeight(
            blockH: 466, available: 612, chromeH: chrome, footH: foot),
        466 + chrome + foot,
      );
      expect(
        pwaRevealHeroHeight(
            blockH: 466, available: 100, chromeH: chrome, footH: foot),
        160,
      );
    });
  });

  group('ORI  the surfaces follow the render', () {
    testWidgets('ORI06: a portrait render is framed portrait in the Full Reveal',
        (tester) async {
      final (c, _) = await _pumpReveal(tester, renderAspect: 2 / 3);
      final frame = find
          .descendant(
            of: find.byKey(const ValueKey('pwa-full-reveal')),
            matching: find.byType(AspectRatio),
          )
          .first;
      expect(tester.widget<AspectRatio>(frame).aspectRatio, closeTo(2 / 3, 1e-3));
      final r = tester.getRect(frame);
      expect(r.height, greaterThan(r.width), reason: 'portrait, not 3:2');
      expect(r.width / r.height, closeTo(2 / 3, 0.01));
      // The slider IS the inner frame: the compare gesture lives on the
      // picture, and the matte around it belongs to the canvas.
      final hero = tester.getRect(find.byType(RevealHero));
      expect(hero.height, closeTo(r.height, 1));
      expect(hero.width, closeTo(r.width, 1));
      expect(r.height, greaterThanOrEqualTo(250),
          reason: 'a portrait render is not a thumbnail');
      // And the canvas is WIDER than the picture: iOS's block, not a strip.
      final canvas = tester.getRect(
          find.byKey(ValueKey('full-reveal-canvas-${c.read(pwaControllerProvider).currentVision!.versionId}')));
      expect(canvas.width, greaterThan(r.width + 100));
      expect(canvas.height, closeTo(r.height, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ORI07: a landscape render keeps the Round 3 geometry',
        (tester) async {
      await _pumpReveal(tester, renderAspect: 3 / 2);
      final frame = find
          .descendant(
            of: find.byKey(const ValueKey('pwa-full-reveal')),
            matching: find.byType(AspectRatio),
          )
          .first;
      final r = tester.getRect(frame);
      expect(r.width / r.height, closeTo(3 / 2, 0.01));
      expect(r.width, closeTo(366, 1), reason: '390 - 2 x 12 frame');
      expect(r.height, closeTo(244, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ORI08: the result card in the conversation is portrait too',
        (tester) async {
      final (c, aspects) = await _pumpReveal(tester, renderAspect: 2 / 3);
      c.read(pwaControllerProvider.notifier).backToConversation();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // The mock's render is a landscape bundle asset, and by now its own
      // decode has been recorded over the seed. Re-declare the render
      // portrait — which is what a real 1024x1536 decode would record — and
      // the card must follow on the next frame.
      final after = c.read(pwaControllerProvider).currentVision!.afterAsset;
      aspects.record(after, 1024, 1536);
      await tester.pump();
      final frame = find
          .descendant(
            of: find.byKey(const ValueKey('pwa-result-vision')),
            matching: find.byType(AspectRatio),
          )
          .first;
      expect(tester.widget<AspectRatio>(frame).aspectRatio, closeTo(2 / 3, 1e-3));
      final r = tester.getRect(frame);
      expect(r.height, greaterThan(r.width));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ORI09: the photo being worked on is framed at ITS shape',
        (tester) async {
      // 20x30 source: the working card measures it and frames it 2:3 while
      // the first vision is made — not cropped to the landscape default.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = ProviderContainer(overrides: [
        pwaRepositoryProvider.overrideWithValue(
          MockPwaExperienceRepository(workDelay: const Duration(minutes: 5)),
        ),
      ]);
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      n.newProject();
      final png = (await tester.runAsync(() => _png(20, 30)))!;
      n.setSource(_source(png), origin: PwaImageOrigin.userUpload);
      n.selectRoom('living_room');
      n.selectEntryAtmosphere('warm_modern');
      unawaited(n.generateFirstVision());
      await tester.pumpWidget(
        UncontrolledProviderScope(
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
        ),
      );
      await tester.pump();
      await tester.pump();
      final working = find.byKey(const ValueKey('pwa-working-source'));
      expect(working, findsOneWidget);
      // The card is on screen now; its decode is real async work, so give it
      // real time, then let the recording microtask and a rebuild run.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump();
      await tester.pump();
      expect(c.read(pwaRenderAspectsProvider)[kPwaSourceAspectKey],
          closeTo(2 / 3, 1e-3),
          reason: 'the source decode was recorded: '
              '${c.read(pwaRenderAspectsProvider)}');
      final frame = find.ancestor(of: working, matching: find.byType(AspectRatio)).first;
      expect(tester.widget<AspectRatio>(frame).aspectRatio, closeTo(2 / 3, 1e-3));
      expect(c.read(pwaControllerProvider).generating, isTrue);
      expect(tester.takeException(), isNull);
      // Let the held generation's timer fire so nothing outlives the test.
      await tester.pump(const Duration(minutes: 6));
    });
  });
}
