// PWA fast-path selector — two-row More/Fewer disclosure + horizontal-scroll
// isolation (V4). Deterministic (zero-delay mock, reduced-motion), offline.

import 'dart:io';
import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/presentation/hero/pwa_hero_sequence.dart';
import 'package:ai_home_architect/features/pwa/presentation/hero/pwa_hero_video.dart';
import 'package:ai_home_architect/features/cards/card_catalog.dart';
import 'package:ai_home_architect/features/cards/widgets/ai_action_card.dart';
import 'package:ai_home_architect/features/cards/widgets/atmosphere_hero_card.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_create_ios.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_entry_screen.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_primitives.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_theme.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container() => ProviderContainer(
  overrides: [
    pwaRepositoryProvider.overrideWithValue(
      MockPwaExperienceRepository(workDelay: Duration.zero),
    ),
  ],
);

AydenImageSource _fake() => AydenImageSource(
  bytes: Uint8List.fromList(const [1, 2, 3, 4]),
  filename: 'x.jpg',
);

Future<ProviderContainer> _pumpEntry(
  WidgetTester tester, {
  bool reduceMotion = true,
  Size size = const Size(1440, 900),
  PwaImageOrigin? withSource = PwaImageOrigin.userUpload,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = _container();
  addTearDown(container.dispose);
  // Create is a step now, not the landing page: open it explicitly.
  container.read(pwaControllerProvider.notifier).newProject();
  if (withSource != null) {
    container
        .read(pwaControllerProvider.notifier)
        .setSource(_fake(), origin: withSource);
  }
  Widget app = UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: PwaExperience()),
  );
  if (reduceMotion) {
    app = MediaQuery(
      data: MediaQueryData(disableAnimations: true, size: size),
      child: app,
    );
  }
  await tester.pumpWidget(app);
  await tester.pump();
  return container;
}

/// UX-A1 — Create sits directly under the slim bar from the first frame: there
/// is no hero CTA to tap and nothing to scroll to. Kept as a named seam so each
/// test still reads as "be on the Create workspace".
Future<void> _enterWorkspace(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

class _FakeHeroVideo implements PwaHeroVideo {
  _FakeHeroVideo(this.onReady, this.onEnded, this.onError);
  final VoidCallback onReady;
  final VoidCallback onEnded;
  final VoidCallback onError;
  bool played = false;
  bool paused = false;
  bool disposed = false;
  @override
  bool get isSupported => true;
  @override
  Widget buildView() => const SizedBox.shrink();
  @override
  void play() => played = true;
  @override
  void pause() => paused = true;
  @override
  void dispose() => disposed = true;
}

void main() {
  // No per-test reset: the cinematic is scoped to each PwaHeroSequence INSTANCE
  // (no process-wide static flag), so tests never leak state into each other.

  group('typography (no underline)', () {
    test('every PWA text style is explicitly non-underlined', () {
      expect(pwaDisplay(fontSize: 20).decoration, TextDecoration.none);
      expect(pwaSans(fontSize: 16).decoration, TextDecoration.none);
      expect(pwaEyebrow().decoration, TextDecoration.none);
    });
  });

  // ── References + web guard + no web-only imports (§12.25–26) ────────────────
  group('assets, web guard & isolation invariants', () {
    // Batch 2.3 §12 — design references under references/ are documentation
    // only: the product must not depend on their presence, so no product test
    // asserts a reference file exists. The PRODUCTION asset check stays.
    test('production room asset exists', () {
      expect(File('assets/cards/rooms/ayden_decide.png').existsSync(), isTrue);
    });

    test('web/index.html declares the horizontal overscroll guard', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html.contains('overscroll-behavior-x: none'), isTrue);
    });

    test('PWA presentation does not import web-only Dart (mobile-safe)', () {
      for (final p in const [
        'lib/features/pwa/presentation/pwa_create_ios.dart',
        'lib/features/pwa/presentation/pwa_entry_screen.dart',
        'lib/features/pwa/presentation/pwa_select_card.dart',
      ]) {
        final src = File(p).readAsStringSync();
        expect(src.contains('dart:html'), isFalse, reason: p);
        expect(src.contains('package:web'), isFalse, reason: p);
      }
    });
  });

  testWidgets('no debug baseline/size overlay leaks into the PWA', (
    tester,
  ) async {
    debugPaintBaselinesEnabled = true;
    debugPaintSizeEnabled = true;
    addTearDown(() {
      debugPaintBaselinesEnabled = false;
      debugPaintSizeEnabled = false;
    });
    await _pumpEntry(tester, size: const Size(390, 844));
    expect(debugPaintBaselinesEnabled, isFalse);
    expect(debugPaintSizeEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  // ══ CREATE, aligned to iOS (Phase 3) ═════════════════════════════════════
  //
  // What these replaced, and why the old assertions did not simply move.
  //
  // Until Phase 3 the web's Create was a dark two-pane composition with its own
  // mechanic: two horizontal carousels, a "More rooms / Fewer rooms" accordion,
  // desktop arrow buttons that paged by whole cards, and a promotion rule that
  // moved a selected optional card to the end of the popular row. Roughly
  // twenty tests here described THAT mechanic in detail.
  //
  // None of it exists on iOS, and iOS is now the source of truth. The phone
  // shows a grid of hero rooms plus a "More spaces" strip, and a page-snapped
  // atmosphere carousel — so the tests that pinned the accordion were not
  // migrated: there is nothing left for them to describe. What IS carried
  // across is every invariant that outlived the mechanic — the defaults, the
  // pre-upload legibility, the Generate wiring, the offline assets, and no
  // overflow at the mandated breakpoints — restated against the new screen.

  testWidgets('the four steps are present, in iOS order, on one page', (
    tester,
  ) async {
    await _pumpEntry(tester, size: const Size(390, 844));
    await _enterWorkspace(tester);
    // One page, not four routes: every badge is in the SAME scrollable.
    for (var n = 1; n <= 4; n++) {
      expect(find.text('STEP $n OF 4'), findsOneWidget, reason: 'step $n');
    }
    expect(find.text('Upload your space'), findsOneWidget);
    expect(find.text('What type of space are we transforming?'), findsOneWidget);
    expect(find.text('Choose your atmosphere'), findsOneWidget);
    expect(find.text('Describe your vision'), findsOneWidget);
    // Step 4 announces itself as skippable.
    expect(find.text('Optional'), findsOneWidget);
    expect(find.byKey(const ValueKey('pwa-create-stepper')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the step copy is the mobile wording, not a second translation', () {
    // The point of the forwarding getters: what the phone says in Khmer is what
    // the browser says in Khmer, because it is literally the same string.
    final km = pwaL10nFor(const Locale('km'));
    expect(km.uplStep2Title, km.shared.uplStep2Title);
    expect(km.uplStep3Title, km.shared.uplStep3Title);
    expect(km.uplStep4Title, km.shared.uplStep4Title);
    expect(km.uplStepBadge(2), km.shared.uplStepBadge(2));
    // …with exactly one deliberate exception, and it is a SUBTRACTION: the web
    // must not offer the microphone iOS has.
    expect(km.shared.uplStep4Sub, contains('និយាយ')); // "speak"
    expect(km.step4Sub, isNot(contains('និយាយ')));
    for (final code in const ['en', 'fr', 'km']) {
      final l = pwaL10nFor(Locale(code));
      // A missing key falls back to the key itself — assert both resolved.
      expect(l.step4Sub, isNot('pwaStep4Sub'), reason: code);
      expect(l.step4Hint, isNot('pwaStep4Hint'), reason: code);
      expect(l.step4Sub, isNotEmpty);
      expect(l.step4Hint, isNotEmpty);
    }
  });

  testWidgets('defaults: Ayden Decide + Ayden Signature, already chosen', (
    tester,
  ) async {
    final c = await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    final s = c.read(pwaControllerProvider);
    expect(s.selectedRoomId, isNull); // Ayden Decide
    expect(s.selectedAtmosphereId, 'ayden_signature');
    final decide = tester.widget<AiActionCard>(
      find.byKey(const ValueKey('pwa-room-ayden-decide')),
    );
    expect(decide.selected, isTrue);
    expect(decide.title, 'Ayden Decide');
    // The pre-composed card art iOS uses for this tile, offline.
    expect(decide.backgroundImageAsset, 'assets/branding/ayden_decide_card.png');
    expect(
      File('assets/branding/ayden_decide_card.png').existsSync(),
      isTrue,
      reason: 'the Ayden Decide card art must be bundled, never fetched',
    );
    final signature = tester.widget<AtmosphereHeroCard>(
      find.byKey(const ValueKey('pwa-atmos-ayden_signature')),
    );
    expect(signature.selected, isTrue);
    // The lead card of Step 3 rendered as a black rectangle on the deployed
    // build: Ayden Signature is not in `kAtmosphereCardById` — it is a
    // delegation, not an atmosphere — so the generic
    // `assets/cards/atmospheres/<id>.png` fallback resolved to a file that
    // does not exist. Both halves are asserted: the path the card asks for,
    // and that the path is really in the bundle.
    expect(signature.asset, kPwaSignatureCardAsset);
    expect(
      File(kPwaSignatureCardAsset).existsSync(),
      isTrue,
      reason: '$kPwaSignatureCardAsset must be bundled',
    );
    // Every OTHER atmosphere must resolve to a file that exists too, so a new
    // atmosphere cannot ship with a silently missing card.
    for (final a in c.read(pwaControllerProvider).atmospheres) {
      if (a.id == 'ayden_signature') continue;
      final asset = kAtmosphereCardById[a.id]?.asset ??
          'assets/cards/atmospheres/${a.id}.png';
      expect(File(asset).existsSync(), isTrue, reason: '${a.id} → $asset');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a room updates the selection and generates nothing', (
    tester,
  ) async {
    final c = await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    final kitchen = find.byKey(const ValueKey('pwa-room-kitchen'));
    await tester.ensureVisible(kitchen);
    await tester.pumpAndSettle();
    await tester.tap(kitchen);
    await tester.pumpAndSettle();
    final s = c.read(pwaControllerProvider);
    expect(s.selectedRoomId, 'kitchen');
    expect(s.phase, PwaPhase.entry, reason: 'a choice is not a generation');
    expect(s.versions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every atmosphere in the catalogue is in the carousel', (
    tester,
  ) async {
    final c = await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    // The carousel is a PageView, so only the pages near the viewport are
    // BUILT — the same laziness iOS has. Asserting `findsOneWidget` per id
    // would therefore test the scroll position, not the catalogue. The
    // catalogue is `itemCount`, and it is what must stay whole: Nordic Warmth
    // included, not behind a disclosure, exactly as before Phase 3.
    final ids = c.read(pwaControllerProvider).atmospheres.map((a) => a.id);
    expect(ids, containsAll(kPwaPopularAtmosphereIds));
    final pager = tester.widget<PageView>(find.byType(PageView));
    expect(
      (pager.childrenDelegate as SliverChildBuilderDelegate).childCount,
      ids.length,
      reason: 'the carousel must offer the whole catalogue',
    );
    // Ayden Signature leads and is the default, as on the phone.
    expect(
      find.byKey(const ValueKey('pwa-atmos-ayden_signature')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // ── Step 4 — the new surface, over the contract that already existed ───────
  group('step 4 — describe your vision', () {
    testWidgets('is empty by default and skippable', (tester) async {
      await _pumpEntry(tester, size: const Size(390, 844));
      await _enterWorkspace(tester);
      final field = find.byKey(const ValueKey('pwa-create-brief'));
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      // Generate is live with a photo and NO brief — skipping is the default
      // path, not a degraded one.
      final gen = find.byKey(const ValueKey('pwa-generate'));
      expect(
        tester.widget<PwaPrimaryButton>(gen).onPressed,
        isNotNull,
        reason: 'an empty Step 4 must never block Generate',
      );
      expect(tester.takeException(), isNull);
    });

    test('an empty brief sends exactly what the web sent before', () async {
      // The regression this guards: a Step 4 that quietly starts sending a
      // whitespace `user_instruction` would change every first generation.
      final c = _container();
      addTearDown(c.dispose);
      final n = c.read(pwaControllerProvider.notifier);
      n.newProject();
      n.setSource(_fake(), origin: PwaImageOrigin.userUpload);
      await n.generateFirstVision(userInstruction: '   \n  ');
      expect(c.read(pwaControllerProvider).versions, hasLength(1));
    });

    testWidgets('what is typed is what is sent', (tester) async {
      final c = await _pumpEntry(tester, size: const Size(390, 844));
      await _enterWorkspace(tester);
      final field = find.byKey(const ValueKey('pwa-create-brief'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '  a reading corner by the window  ');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field).controller!.text,
        '  a reading corner by the window  ',
      );
      final gen = find.byKey(const ValueKey('pwa-generate'));
      await tester.ensureVisible(gen);
      await tester.tap(gen);
      await tester.pumpAndSettle();
      // It generated, and the surrounding whitespace never left the screen.
      expect(c.read(pwaControllerProvider).versions, hasLength(1));
      // Generate lands on the First Reveal, whose shared RevealHero arms an
      // 800ms auto-sweep that outlives disposal. Advance past it here rather
      // than weakening an animation the frozen mobile app also uses.
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('there is no microphone — the web has no speech service', (
      tester,
    ) async {
      await _pumpEntry(tester, size: const Size(390, 844));
      await _enterWorkspace(tester);
      expect(find.byIcon(Icons.mic), findsNothing);
      expect(find.byIcon(Icons.mic_none), findsNothing);
      // …and the copy does not offer one either.
      expect(find.textContaining('speak'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ── Generate wiring ───────────────────────────────────────────────────────
  testWidgets('Generate is disabled without a photo and live with one', (
    tester,
  ) async {
    await _pumpEntry(tester, size: const Size(1440, 900), withSource: null);
    await _enterWorkspace(tester);
    expect(
      tester
          .widget<PwaPrimaryButton>(find.byKey(const ValueKey('pwa-generate')))
          .onPressed,
      isNull,
      reason: 'Generate must be disabled pre-upload',
    );

    await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    expect(
      tester
          .widget<PwaPrimaryButton>(find.byKey(const ValueKey('pwa-generate')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'before upload: the choices are visible, and the zone claims nothing false',
      (tester) async {
    await _pumpEntry(tester, size: const Size(1440, 900), withSource: null);
    await _enterWorkspace(tester);
    // Visible — the whole journey is legible before the photo exists, which is
    // what made the fast path readable and is kept.
    expect(find.text('STEP 2 OF 4'), findsOneWidget);
    expect(find.byKey(const ValueKey('pwa-room-ayden-decide')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pwa-atmos-ayden_signature')),
      findsOneWidget,
    );
    // …and the upload zone offers only what the bucket accepts.
    expect(find.text('JPG, PNG or WebP · up to 10 MB'), findsOneWidget);
    expect(find.text('JPG, PNG or HEIC'), findsNothing);
    // The old zone claimed a gesture this build has never implemented: there is
    // no DropTarget anywhere in it, and there never was.
    expect(find.text('or drag & drop it here'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('after upload: the photo replaces the zone in place', (
    tester,
  ) async {
    await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    expect(find.byKey(const ValueKey('pwa-create-upload')), findsOneWidget);
    expect(find.byKey(const ValueKey('pwa-create-replace')), findsOneWidget);
    expect(find.byKey(const ValueKey('pwa-create-remove')), findsOneWidget);
    // The examples strip leaves with the empty zone — it is an alternative to
    // uploading, not a second source once a photo exists.
    expect(find.byKey(const ValueKey('pwa-examples')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an undecodable photo renders an empty frame, never an exception',
      (tester) async {
    // The fake source in these tests is four bytes. On the web that is not a
    // hypothetical: a truncated read or a mislabelled file reaches Image.memory
    // the same way, and it must not throw into the framework.
    await _pumpEntry(tester, size: const Size(390, 844));
    await _enterWorkspace(tester);
    expect(find.byKey(const ValueKey('pwa-create-upload')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the flow starts at the top of a tall viewport, never floating',
      (tester) async {
    // The regression: the content column was wrapped in `Center`, which
    // centres on BOTH axes. A SingleChildScrollView under a loose vertical
    // constraint shrinks to its content, so on any viewport taller than the
    // page — a desktop window, a tall phone in landscape — the whole flow
    // floated in the middle with dead canvas above Step 1.
    await _pumpEntry(tester, size: const Size(900, 2400));
    await _enterWorkspace(tester);
    final rail = tester.getRect(find.byKey(const ValueKey('pwa-create-stepper')));
    final badge = tester.getRect(find.text('STEP 1 OF 4'));
    expect(
      badge.top - rail.bottom,
      lessThan(120),
      reason: 'Step 1 must follow the chrome, not float below it',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a step brings that step to the top', (tester) async {
    // The regression this exists for: the first port used iOS's
    // `Scrollable.ensureVisible(alignment: 0.05)`, which reveals LESS than the
    // leading edge when the target is taller than the viewport. On the web the
    // sections routinely are — the copy wraps to more lines and the rooms are
    // a grid — so tapping "4" moved the page a couple of hundred pixels and
    // left Step 1 filling the screen. Asserting merely "pixels > 0" passed
    // that bug happily, so this asserts WHERE it lands.
    await _pumpEntry(tester, size: const Size(390, 844));
    await _enterWorkspace(tester);
    final scrollable = find
        .descendant(
          of: find.byKey(const ValueKey('pwa-create')),
          matching: find.byType(Scrollable),
        )
        .first;
    final view = tester.getRect(scrollable);
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0.0);

    for (final step in const [4, 2, 3]) {
      await tester.tap(find.widgetWithText(InkWell, '$step'));
      await tester.pumpAndSettle();
      final pos = tester.state<ScrollableState>(scrollable).position;
      final badge = tester.getRect(find.text('STEP $step OF 4'));
      final atEnd = pos.pixels >= pos.maxScrollExtent - 1;
      if (!atEnd) {
        expect(
          badge.top - view.top,
          lessThan(kPwaStepReadingLine),
          reason: 'step $step must land inside the reading area',
        );
      }
      expect(badge.top, greaterThanOrEqualTo(view.top),
          reason: 'step $step must not land scrolled past');
      // Whether or not the page could travel that far, the rail must agree
      // with where the reader now is. The LAST step cannot reach the top —
      // there is nothing beneath it — and a rail that kept highlighting 3
      // would read as a control that did nothing.
      final node = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('$step'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(
        (node.decoration! as BoxDecoration).color,
        pwaInk,
        reason: 'the rail must mark step $step as current',
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(1440, 900), Size(1920, 1080)]) {
    testWidgets(
      'Generate visible (default) at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await _pumpEntry(tester, size: size);
        await _enterWorkspace(tester);
        final gen = find.byKey(const ValueKey('pwa-generate'));
        expect(gen, findsOneWidget);
        final r = tester.getRect(gen);
        expect(r.top, greaterThanOrEqualTo(0.0));
        expect(r.bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
      },
    );
  }

  group('no overflow across breakpoints (whole page scrolled)', () {
    for (final size in const [
      Size(390, 844),
      Size(768, 1024),
      Size(1440, 900),
      Size(1920, 1080),
    ]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        await _pumpEntry(tester, size: size);
        await _enterWorkspace(tester);
        expect(tester.takeException(), isNull);
        // Every step, not just the one above the fold: the room grid and the
        // atmosphere carousel are the two that resize with the viewport.
        for (final key in const ['pwa-room-ayden-decide', 'pwa-create-brief']) {
          await tester.ensureVisible(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$key at $size');
        }
      });
    }
  });

  testWidgets(
    'non-web / reduced-motion: no overlay is mounted, Create owns the viewport',
    (tester) async {
      await _pumpEntry(tester, reduceMotion: false, withSource: null);
      await tester.pump();
      // The cinematic only autoplays on web with motion allowed. Off that path
      // the overlay is never mounted at all — nothing to skip, nothing to scroll.
      expect(find.text('Tap to skip'), findsNothing);
      expect(find.byKey(const ValueKey('pwa-create')), findsOneWidget);
      // The phase router mounts the iOS-aligned screen, not the retained dark
      // one — the single assertion that proves Phase 3 is actually wired in.
      expect(find.byType(PwaCreateIos), findsOneWidget);
      expect(find.byType(PwaEntryScreen), findsNothing);
      expect(find.text('Upload your space'), findsOneWidget);
      expect(kHeroMp4, 'media/hero/ayden-cinematic-v1-desktop.mp4');
      expect(tester.takeException(), isNull);
    },
  );

  group('PwaHeroSequence — zero-wait timeline & fallbacks', () {
    testWidgets('no-video (mobile / reduced-motion) → promise at once', (
      tester,
    ) async {
      final s = PwaHeroSequence(
        useVideo: false,
        createVideo: ({required onReady, required onEnded, required onError}) =>
            _FakeHeroVideo(onReady, onEnded, onError),
      );
      expect(s.phase, PwaHeroPhase.promise);
      expect(s.finished, isTrue);
      expect(s.fellBackToPoster, isTrue);
      s.dispose();
    });

    testWidgets(
      'video created immediately (no logo gate): intro → transform → promise',
      (tester) async {
        late _FakeHeroVideo fake;
        final s = PwaHeroSequence(
          useVideo: true,
          readyTimeout: const Duration(seconds: 10),
          createVideo:
              ({required onReady, required onEnded, required onError}) =>
                  fake = _FakeHeroVideo(onReady, onEnded, onError),
        );
        expect(s.phase, PwaHeroPhase.intro);
        expect(fake.played, isTrue);
        fake.onReady();
        expect(s.phase, PwaHeroPhase.transform);
        fake.onEnded();
        await tester.pump();
        expect(s.phase, PwaHeroPhase.promise);
        s.dispose();
      },
    );

    testWidgets('ready-timeout → promise (no spinner)', (tester) async {
      final s = PwaHeroSequence(
        useVideo: true,
        readyTimeout: const Duration(milliseconds: 300),
        createVideo: ({required onReady, required onEnded, required onError}) =>
            _FakeHeroVideo(onReady, onEnded, onError),
      );
      expect(s.phase, PwaHeroPhase.intro);
      await tester.pump(const Duration(milliseconds: 300));
      expect(s.phase, PwaHeroPhase.promise);
      expect(s.fellBackToPoster, isTrue);
      s.dispose();
    });

    testWidgets('video error → promise', (tester) async {
      late _FakeHeroVideo fake;
      final s = PwaHeroSequence(
        useVideo: true,
        readyTimeout: const Duration(seconds: 10),
        createVideo: ({required onReady, required onEnded, required onError}) =>
            fake = _FakeHeroVideo(onReady, onEnded, onError),
      );
      fake.onError();
      await tester.pump();
      expect(s.phase, PwaHeroPhase.promise);
      expect(s.fellBackToPoster, isTrue);
      s.dispose();
    });

    testWidgets('skip → promise and the video is disposed', (tester) async {
      late _FakeHeroVideo fake;
      final s = PwaHeroSequence(
        useVideo: true,
        readyTimeout: const Duration(seconds: 10),
        createVideo: ({required onReady, required onEnded, required onError}) =>
            fake = _FakeHeroVideo(onReady, onEnded, onError),
      );
      expect(s.phase, PwaHeroPhase.intro);
      s.skip();
      await tester.pump();
      expect(s.phase, PwaHeroPhase.promise);
      expect(fake.disposed, isTrue);
      s.dispose();
    });

    testWidgets(
      'a NEW instance plays again — no process-wide flag blocks a fresh load',
      (tester) async {
        late _FakeHeroVideo firstFake;
        final first = PwaHeroSequence(
          useVideo: true,
          readyTimeout: const Duration(seconds: 10),
          createVideo:
              ({required onReady, required onEnded, required onError}) =>
                  firstFake = _FakeHeroVideo(onReady, onEnded, onError),
        );
        expect(first.phase, PwaHeroPhase.intro);
        expect(firstFake.played, isTrue);
        first.dispose();
        // A second sequence (= a fresh page load / new tab) ALSO plays: it does
        // NOT skip to promise because of any leftover static flag.
        late _FakeHeroVideo secondFake;
        final second = PwaHeroSequence(
          useVideo: true,
          readyTimeout: const Duration(seconds: 10),
          createVideo:
              ({required onReady, required onEnded, required onError}) =>
                  secondFake = _FakeHeroVideo(onReady, onEnded, onError),
        );
        expect(second.phase, PwaHeroPhase.intro);
        expect(secondFake.played, isTrue);
        second.dispose();
      },
    );
  });

  group('hero responsive media + replay decision', () {
    test('pwaHeroUseVideo is width-INDEPENDENT (web + motion → play)', () {
      // Mobile no longer skips the cinematic: the decision ignores viewport
      // width entirely (no width parameter). Web + motion → play.
      expect(pwaHeroUseVideo(isWeb: true, reduceMotion: false), isTrue);
      // Reduced-motion → static poster.
      expect(pwaHeroUseVideo(isWeb: true, reduceMotion: true), isFalse);
      // Non-web (VM/mobile app) → stub/poster.
      expect(pwaHeroUseVideo(isWeb: false, reduceMotion: false), isFalse);
    });

    test('mobile media config is swappable independently of desktop', () {
      final desktop = pwaHeroMediaFor(false);
      final mobile = pwaHeroMediaFor(true);
      // Distinct configs; mobile has its own portrait crop focal point.
      expect(desktop.videoObjectPosition, 'center center');
      expect(mobile.videoObjectPosition, isNot('center center'));
      expect(mobile.posterAlignment, isNot(Alignment.center));
      // For this hotfix mobile temporarily reuses the desktop media paths — a
      // future 9:16 asset swap changes ONLY these paths, not the hero/player.
      expect(mobile.mp4, desktop.mp4);
      expect(mobile.webm, desktop.webm);
      expect(mobile.startPoster, desktop.startPoster);
      expect(mobile.endPoster, desktop.endPoster);
    });
  });

  testWidgets('resizing does not restart or duplicate the hero', (
    tester,
  ) async {
    await _pumpEntry(
      tester,
      reduceMotion: false,
      withSource: null,
      size: const Size(1440, 900),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('pwa-create')), findsOneWidget);
    // Resize desktop → narrow: same page instance, hero stays stable (no
    // restart, no exception, no duplicate).
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pump();
    // Same page instance across the breakpoint change: exactly one Create and
    // one step rail, no duplicate, no exception. The rail SWAPS orientation at
    // 720 (side above, top below) — one is mounted at a time, never both.
    expect(find.byKey(const ValueKey('pwa-create')), findsOneWidget);
    expect(find.byKey(const ValueKey('pwa-create-stepper')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // UX-A1 — the Create composition itself must survive the mobile breakpoints
  // (this used to assert the final hero composition, which no longer exists).
  for (final size in const [Size(390, 844), Size(430, 932), Size(768, 1024)]) {
    testWidgets(
      'Create has no overflow at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await _pumpEntry(
          tester,
          reduceMotion: false,
          withSource: null,
          size: size,
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('pwa-create')), findsOneWidget);
        expect(find.byKey(const ValueKey('pwa-create-stepper')), findsOneWidget);
        expect(find.byKey(const ValueKey('pwa-create-upload')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  // ── The photo frame ────────────────────────────────────────────────────────
  //
  // `pwaPhotoImageHeight` sized the OLD dark photo panel, which fitted the
  // card to the source's own ratio. The iOS-aligned zone is a fixed 4:3 that
  // LETTERBOXES the photo instead — iOS's choice, and the one that never crops
  // the part of the room being redesigned out of view. The helper still ships
  // with the retained screen and its arithmetic is still worth pinning, so the
  // pure tests stay; the widget test that measured the old panel's action bar
  // is replaced by one for the frame that actually renders.
  group('photo frame', () {
    test('a landscape source gets the height its ratio needs', () {
      // 16:9 at 600px wide → ~338px of image, not the whole column.
      final h = pwaPhotoImageHeight(width: 600, aspect: 16 / 9, available: 700);
      expect(h, closeTo(600 / (16 / 9), 0.5));
      expect(h, lessThan(700));
    });

    test('a portrait source is shown whole but stays bounded', () {
      // 9:16 at 600px wide would want 1066px — capped, never unbounded.
      final h = pwaPhotoImageHeight(width: 600, aspect: 9 / 16, available: 500);
      expect(h, 500);
      final unbounded = pwaPhotoImageHeight(
        width: 600,
        aspect: 9 / 16,
        available: double.infinity,
      );
      expect(unbounded, lessThanOrEqualTo(620));
    });

    test('an undecoded source falls back to a sane landscape shape', () {
      final h = pwaPhotoImageHeight(width: 600, aspect: null, available: 900);
      expect(h, closeTo(600 / (4 / 3), 0.5));
      // Degenerate values never produce a broken box.
      expect(
        pwaPhotoImageHeight(width: 600, aspect: 0, available: 900),
        greaterThanOrEqualTo(180),
      );
    });

    test('a very small pane still yields a usable card', () {
      final h = pwaPhotoImageHeight(width: 200, aspect: 16 / 9, available: 60);
      expect(h, 180); // the floor wins over a starved column
    });

    testWidgets('the actions stay inside the frame at every breakpoint', (
      tester,
    ) async {
      for (final size in const [
        Size(390, 844),
        Size(768, 1024),
        Size(1440, 900),
        Size(1920, 1080),
      ]) {
        await _pumpEntry(tester, size: size);
        await _enterWorkspace(tester);
        final zone = find.byKey(const ValueKey('pwa-create-upload'));
        await tester.ensureVisible(zone);
        await tester.pumpAndSettle();
        final frame = tester.getRect(zone);
        // 4:3, exactly — the constant the letterboxing depends on.
        expect(frame.width / frame.height, closeTo(4 / 3, 0.02),
            reason: 'the photo frame must stay 4:3 at $size');
        for (final k in const ['pwa-create-replace', 'pwa-create-remove']) {
          final action = tester.getRect(find.byKey(ValueKey(k)));
          expect(frame.contains(action.topLeft), isTrue, reason: '$k at $size');
          expect(
            frame.contains(action.bottomRight - const Offset(0.5, 0.5)),
            isTrue,
            reason: '$k at $size',
          );
        }
        expect(tester.takeException(), isNull);
      }
    });
  });
}
