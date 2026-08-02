// PWA fast-path selector — two-row More/Fewer disclosure + horizontal-scroll
// isolation (V4). Deterministic (zero-delay mock, reduced-motion), offline.

import 'dart:io';
import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/presentation/hero/pwa_hero_sequence.dart';
import 'package:ai_home_architect/features/pwa/presentation/hero/pwa_hero_video.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_entry_screen.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_select_card.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_theme.dart';
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

Future<void> _enterWorkspace(WidgetTester tester) async {
  await tester.tap(find.text('Upload your room'));
  await tester.pumpAndSettle();
}

double _pageOffset(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

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

  // ── Role-keyed finders (robust: never anchored to a card that scrolls away).
  Finder carousel(String key) => find.byKey(ValueKey(key));
  Finder rowScroll(String key) => find
      .descendant(of: carousel(key), matching: find.byType(Scrollable))
      .first;
  Finder cardByTitle(String title) =>
      find.byWidgetPredicate((w) => w is PwaSelectCard && w.title == title);
  double rowPixels(WidgetTester t, String key) =>
      t.state<ScrollableState>(rowScroll(key)).position.pixels;

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

  // ── DEFAULT / regression (§12.29) ───────────────────────────────────────────
  testWidgets('DEFAULT post-upload layout — one row per level, preselected', (
    tester,
  ) async {
    final c = await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    expect(find.text('1. ROOM'), findsOneWidget);
    expect(find.text('2. ATMOSPHERE'), findsOneWidget);
    // ROOM has optional rooms → a More toggle. ATMOSPHERE shows its whole
    // catalog (incl. Nordic Warmth) → no More toggle (nothing more to reveal).
    expect(find.text('More rooms'), findsOneWidget);
    expect(find.text('More atmospheres'), findsNothing);
    expect(find.text('Generate my vision'), findsOneWidget);
    expect(
      find.text('First vision free · No account required'),
      findsOneWidget,
    );
    // Exactly one popular row per level; no optional (second) row yet.
    expect(carousel('room-popular'), findsOneWidget);
    expect(carousel('atmos-popular'), findsOneWidget);
    expect(carousel('room-optional'), findsNothing);
    expect(carousel('atmos-optional'), findsNothing);
    // Ayden Decide + Ayden Signature preselected, full labels.
    expect(find.text('Ayden Decide'), findsOneWidget);
    expect(find.text('AYDEN DECIDE'), findsNothing);
    expect(
      tester.widget<PwaSelectCard>(cardByTitle('Ayden Decide')).selected,
      isTrue,
    );
    final s = c.read(pwaControllerProvider);
    expect(s.selectedRoomId, isNull);
    expect(s.selectedAtmosphereId, 'ayden_signature');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ayden Decide uses the mandated ayden_decide.png asset', (
    tester,
  ) async {
    await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    final decide = tester.widget<PwaSelectCard>(cardByTitle('Ayden Decide'));
    expect(decide.asset, 'assets/cards/rooms/ayden_decide.png');
    expect(decide.subtitle, 'Auto-detect');
    expect(tester.takeException(), isNull);
  });

  // ── ROOM second-row disclosure (§12.1–8) ────────────────────────────────────
  testWidgets(
    'More rooms reveals a SECOND row; Fewer hides it; selection kept',
    (tester) async {
      final c = await _pumpEntry(tester, size: const Size(1440, 900));
      await _enterWorkspace(tester);
      // §1 default: one row.
      expect(carousel('room-optional'), findsNothing);
      // §2 More rooms → exactly one second row.
      await tester.tap(find.text('More rooms'));
      await tester.pumpAndSettle();
      expect(find.text('Fewer rooms'), findsOneWidget);
      expect(carousel('room-optional'), findsOneWidget);
      // §3 popular row still present & unchanged (Ayden Decide first).
      expect(carousel('room-popular'), findsOneWidget);
      expect(
        find.descendant(
          of: carousel('room-popular'),
          matching: find.text('Ayden Decide'),
        ),
        findsOneWidget,
      );
      // §4 optional cards ONLY in the second row (Dining Room here).
      expect(
        find.descendant(
          of: carousel('room-optional'),
          matching: find.text('Dining Room'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: carousel('room-popular'),
          matching: find.text('Dining Room'),
        ),
        findsNothing,
      );
      // §5 no Wrap/grid in either row.
      expect(
        find.descendant(
          of: carousel('room-popular'),
          matching: find.byType(Wrap),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: carousel('room-optional'),
          matching: find.byType(Wrap),
        ),
        findsNothing,
      );
      // Select the optional Dining Room (no generation). The Fast-Path editorial
      // intro can push the selectors into their scroll area, so bring the card
      // into view first (behaviour unchanged, position robustness only).
      final diningOptional = find.descendant(
        of: carousel('room-optional'),
        matching: find.text('Dining Room'),
      );
      await tester.ensureVisible(diningOptional);
      await tester.pumpAndSettle();
      await tester.tap(diningOptional);
      await tester.pumpAndSettle();
      expect(c.read(pwaControllerProvider).selectedRoomId, 'diningRoom');
      expect(c.read(pwaControllerProvider).phase, PwaPhase.entry);
      expect(c.read(pwaControllerProvider).versions, isEmpty);
      // §6 Fewer rooms hides the second row.
      await tester.ensureVisible(find.text('Fewer rooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fewer rooms'));
      await tester.pumpAndSettle();
      expect(carousel('room-optional'), findsNothing);
      // §7 selection survives collapse …
      expect(c.read(pwaControllerProvider).selectedRoomId, 'diningRoom');
      // §8 … and the selected optional card is PROMOTED into the popular row.
      expect(
        find.descendant(
          of: carousel('room-popular'),
          matching: find.text('Dining Room'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  // ── ATMOSPHERE catalogue: all visible incl. Nordic Warmth (single row) ──────
  testWidgets(
    'ATMOSPHERE shows the whole catalogue (incl. Nordic Warmth) in one row',
    (tester) async {
      final c = await _pumpEntry(tester, size: const Size(1440, 900));
      await _enterWorkspace(tester);
      // No More/Fewer toggle, no second row for ATMOSPHERE (whole catalogue fits
      // in the single popular row).
      expect(find.text('More atmospheres'), findsNothing);
      expect(find.text('Fewer atmospheres'), findsNothing);
      expect(carousel('atmos-optional'), findsNothing);
      // Ayden Signature still preselected by default.
      expect(
        c.read(pwaControllerProvider).selectedAtmosphereId,
        'ayden_signature',
      );
      // Every atmosphere lives in the SINGLE popular row — Nordic Warmth
      // included (reachable by scrolling that row).
      for (final name in const [
        'Ayden Signature',
        'Warm Modern',
        'Soft Luxury',
        'Japandi Calm',
        'Tropical Escape',
        'Nordic Warmth',
      ]) {
        await tester.scrollUntilVisible(
          find.descendant(
            of: carousel('atmos-popular'),
            matching: find.text(name),
          ),
          200,
          scrollable: rowScroll('atmos-popular'),
        );
        expect(
          find.descendant(
            of: carousel('atmos-popular'),
            matching: find.text(name),
          ),
          findsOneWidget,
          reason: name,
        );
      }
      // Selecting Nordic Warmth works and does not generate.
      await tester.tap(find.text('Nordic Warmth'));
      await tester.pumpAndSettle();
      expect(
        c.read(pwaControllerProvider).selectedAtmosphereId,
        'nordic_warmth',
      );
      expect(c.read(pwaControllerProvider).versions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  // ── Scroll isolation (§12.16–21) ────────────────────────────────────────────
  testWidgets('independent controllers; rows scroll independently', (
    tester,
  ) async {
    await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    await tester.tap(find.text('More rooms'));
    await tester.pumpAndSettle();
    // The three live rows (ROOM has a popular + optional row; ATMOSPHERE has a
    // single popular row), each with its own controller.
    for (final k in const ['room-popular', 'room-optional', 'atmos-popular']) {
      expect(carousel(k), findsOneWidget, reason: k);
    }
    expect(carousel('atmos-optional'), findsNothing);
    // §17/§18 scrolling ROOM popular moves ONLY that row.
    final beforeRoomOpt = rowPixels(tester, 'room-optional');
    final beforeAtmosPop = rowPixels(tester, 'atmos-popular');
    await tester.drag(rowScroll('room-popular'), const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(rowPixels(tester, 'room-popular'), greaterThan(0));
    expect(
      rowPixels(tester, 'room-optional'),
      moreOrLessEquals(beforeRoomOpt, epsilon: 0.5),
    );
    expect(
      rowPixels(tester, 'atmos-popular'),
      moreOrLessEquals(beforeAtmosPop, epsilon: 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal scroll does not move the vertical page (§19)', (
    tester,
  ) async {
    await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    final page = _pageOffset(tester);
    await tester.drag(rowScroll('room-popular'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(rowPixels(tester, 'room-popular'), greaterThan(0)); // row moved
    expect(
      _pageOffset(tester),
      moreOrLessEquals(page, epsilon: 0.5),
    ); // page did not
    expect(find.byType(PwaEntryScreen), findsOneWidget); // §24 no route change
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical drag still scrolls the page (§20, mobile)', (
    tester,
  ) async {
    await _pumpEntry(tester, size: const Size(390, 844));
    await _enterWorkspace(tester);
    final before = _pageOffset(tester);
    // A vertical drag over the workspace scrolls the PAGE (not a horizontal row).
    // Drag the editorial title (a page-level element) so the gesture cannot be
    // absorbed by a card row.
    await tester.drag(
      find.text('Shape your space with Ayden.'),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(_pageOffset(tester), greaterThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanding More preserves horizontal offsets (§21)', (
    tester,
  ) async {
    await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    await tester.drag(rowScroll('room-popular'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    final before = rowPixels(tester, 'room-popular');
    expect(before, greaterThan(0));
    await tester.tap(find.text('More rooms'));
    await tester.pumpAndSettle();
    expect(
      rowPixels(tester, 'room-popular'),
      moreOrLessEquals(before, epsilon: 1),
    );
    expect(tester.takeException(), isNull);
  });

  // ── Arrows land on whole-card increments (§12.22) ───────────────────────────
  testWidgets('desktop arrow moves in whole-card increments', (tester) async {
    await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    await tester.tap(find.text('More rooms'));
    await tester.pumpAndSettle();
    final rightArrow = find
        .descendant(
          of: carousel('room-optional'),
          matching: find.byIcon(Icons.chevron_right_rounded),
        )
        .first;
    expect(rightArrow, findsOneWidget);
    await tester.tap(rightArrow);
    await tester.pumpAndSettle();
    const extent = kPwaCardW + 12;
    final offset = rowPixels(tester, 'room-optional');
    final max = tester
        .state<ScrollableState>(rowScroll('room-optional'))
        .position
        .maxScrollExtent;
    final onBoundary =
        (offset / extent - (offset / extent).round()).abs() < 0.02;
    final atEnd = (offset - max).abs() < 1.0;
    expect(offset, greaterThan(0));
    expect(onBoundary || atEnd, isTrue, reason: 'offset=$offset max=$max');
    expect(tester.takeException(), isNull);
  });

  // ── Selecting a clipped card reveals it minimally (§12.23) ──────────────────
  testWidgets('selecting a clipped optional card reveals it fully', (
    tester,
  ) async {
    final c = await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    await tester.tap(find.text('More rooms'));
    await tester.pumpAndSettle();
    // Scroll the optional row to its END (builds the last card), then step back
    // in small increments until Driveway is MODERATELY clipped at the right edge
    // (30..80px past, left well on-screen so its left half is tappable).
    await tester.drag(rowScroll('room-optional'), const Offset(-4000, 0));
    await tester.pumpAndSettle();
    final view = tester.getRect(rowScroll('room-optional'));
    final card = cardByTitle('Driveway'); // last optional room card
    expect(card, findsOneWidget);
    var clipped = false;
    for (var i = 0; i < 40 && !clipped; i++) {
      final r = tester.getRect(card);
      if (r.right > view.right + 30 &&
          r.right < view.right + 80 &&
          r.left > view.left + 44) {
        clipped = true;
        break;
      }
      await tester.drag(rowScroll('room-optional'), const Offset(20, 0));
      await tester.pump();
    }
    expect(clipped, isTrue, reason: 'failed to clip Driveway moderately');
    final pre = tester.getRect(card);
    final tapX = ((pre.left + view.right) / 2)
        .clamp(view.left + 44, view.right - 44)
        .toDouble();
    await tester.tapAt(Offset(tapX, view.top + 18));
    await tester.pumpAndSettle();
    expect(c.read(pwaControllerProvider).selectedRoomId, 'driveway');
    final r = tester.getRect(card);
    expect(r.right, lessThanOrEqualTo(view.right + 1)); // now fully visible
    expect(r.left, greaterThanOrEqualTo(view.left - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('first popular card is not clipped at rest', (tester) async {
    await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    final view = tester.getRect(rowScroll('room-popular'));
    final first = tester.getRect(cardByTitle('Ayden Decide'));
    expect(first.left, greaterThanOrEqualTo(view.left - 1));
    expect(first.right, lessThanOrEqualTo(view.right + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('card labels are never ellipsized (scaled to fit)', (
    tester,
  ) async {
    await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    for (final label in const [
      'Ayden Decide',
      'Living Room',
      'Ayden Signature',
    ]) {
      final t = find.text(label).first;
      expect(t, findsOneWidget);
      expect(tester.widget<Text>(t).overflow, isNot(TextOverflow.ellipsis));
      expect(
        find.ancestor(of: t, matching: find.byType(FittedBox)),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  // ── Selection does not generate ─────────────────────────────────────────────
  testWidgets('selecting a popular card updates selection, no generate', (
    tester,
  ) async {
    final c = await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    // Bring each card into view first (the editorial intro can push the
    // selectors into their scroll area; selection behaviour is unchanged).
    await tester.ensureVisible(find.text('Bedroom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bedroom'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Warm Modern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warm Modern'));
    await tester.pumpAndSettle();
    final s = c.read(pwaControllerProvider);
    expect(s.selectedRoomId, 'masterBedroom');
    expect(s.selectedAtmosphereId, 'warm_modern');
    expect(s.phase, PwaPhase.entry);
    expect(s.versions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  // ── Fast-Path editorial introduction (§4/§6) ────────────────────────────────
  testWidgets(
    'Fast Path shows the editorial introduction + selection summary',
    (tester) async {
      final c = await _pumpEntry(tester, size: const Size(1440, 900));
      await _enterWorkspace(tester);
      // §4 — editorial intro + readiness indicators explaining the defaults.
      expect(find.text('CREATE YOUR FIRST VISION'), findsOneWidget);
      expect(find.text('Shape your space with Ayden.'), findsOneWidget);
      expect(find.text('Photo ready'), findsOneWidget);
      expect(find.text('Ayden Decide active'), findsOneWidget);
      // §6 — one-line selection summary above Generate.
      expect(
        find.textContaining('Ayden will create your first vision using'),
        findsOneWidget,
      );
      // Defaults intact; no generation from the editorial band.
      expect(
        c.read(pwaControllerProvider).selectedAtmosphereId,
        'ayden_signature',
      );
      expect(c.read(pwaControllerProvider).versions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  // ── Generate wiring (§12.30) ────────────────────────────────────────────────
  testWidgets('Generate button is present and wired', (tester) async {
    await _pumpEntry(tester, size: const Size(1440, 900));
    await _enterWorkspace(tester);
    final btn = find.widgetWithText(InkWell, 'Generate my vision');
    expect(btn, findsOneWidget);
    expect(tester.widget<InkWell>(btn).onTap, isNotNull);
    expect(tester.takeException(), isNull);
  });

  test(
    'generateFirstVision transitions entry → architect (offline mock)',
    () async {
      final c = _container();
      addTearDown(c.dispose);
      c
          .read(pwaControllerProvider.notifier)
          .setSource(_fake(), origin: PwaImageOrigin.userUpload);
      expect(c.read(pwaControllerProvider).phase, PwaPhase.entry);
      await c.read(pwaControllerProvider.notifier).generateFirstVision();
      expect(c.read(pwaControllerProvider).phase, PwaPhase.architect);
      expect(c.read(pwaControllerProvider).versions, hasLength(1));
    },
  );

  // ── Before-upload + hero regression (§12.27–28) ─────────────────────────────
  testWidgets('CTA scrolls to the workspace (no page swap)', (tester) async {
    await _pumpEntry(tester, size: const Size(390, 844));
    expect(_pageOffset(tester), 0.0);
    await tester.tap(find.text('Upload your room'));
    await tester.pumpAndSettle();
    expect(_pageOffset(tester), greaterThan(0.0));
    expect(find.byType(PwaEntryScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('upload screen (before-upload) copy unchanged', (tester) async {
    await _pumpEntry(tester, size: const Size(1440, 900), withSource: null);
    await _enterWorkspace(tester);
    expect(find.text('YOUR SPACE'), findsOneWidget);
    expect(find.text('Show Ayden\nyour room.'), findsOneWidget);
    expect(find.text('One clear photo is enough.'), findsOneWidget);
    expect(find.text('Drop your photo here'), findsOneWidget);
    expect(find.text('JPG, PNG or HEIC'), findsOneWidget);
    expect(find.text('Try an example'), findsOneWidget);
    expect(find.text('First vision free'), findsOneWidget);
    expect(find.text('THE STUDIO'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(1440, 900), Size(1920, 1080)]) {
    testWidgets(
      'Generate visible (default) at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await _pumpEntry(tester, size: size);
        await _enterWorkspace(tester);
        final gen = find.text('Generate my vision');
        expect(gen, findsOneWidget);
        final r = tester.getRect(gen);
        expect(r.top, greaterThanOrEqualTo(0.0));
        expect(r.bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
      },
    );
  }

  group('no overflow across breakpoints (ROOM second row expanded)', () {
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
        await tester.ensureVisible(find.text('More rooms'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('More rooms'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // ROOM second row present; ATMOSPHERE has none (single-row catalogue).
        expect(carousel('room-optional'), findsOneWidget);
        expect(carousel('atmos-optional'), findsNothing);
      });
    }
  });

  testWidgets(
    'non-web / reduced-motion hero falls straight to the final promise + CTA',
    (tester) async {
      await _pumpEntry(tester, reduceMotion: false, withSource: null);
      await tester.pump();
      expect(find.text('Your home.'), findsOneWidget);
      expect(find.text('Reimagined.'), findsOneWidget);
      expect(find.text('Upload your room'), findsOneWidget);
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
    expect(find.text('Your home.'), findsOneWidget);
    // Resize desktop → narrow: same page instance, hero stays stable (no
    // restart, no exception, no duplicate).
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pump();
    expect(find.text('Your home.'), findsOneWidget);
    expect(find.text('Upload your room'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Mobile final hero composition — no overflow, CTA + copy present.
  for (final size in const [Size(390, 844), Size(430, 932), Size(768, 1024)]) {
    testWidgets(
      'mobile hero final state has no overflow at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        // reduceMotion:false + non-web (VM) → poster fallback = the final promise
        // composition, which is what a mobile viewer sees while the video loads.
        await _pumpEntry(
          tester,
          reduceMotion: false,
          withSource: null,
          size: size,
        );
        await tester.pump();
        expect(find.text('Your home.'), findsOneWidget);
        expect(find.text('Reimagined.'), findsOneWidget);
        expect(find.text('Upload your room'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
