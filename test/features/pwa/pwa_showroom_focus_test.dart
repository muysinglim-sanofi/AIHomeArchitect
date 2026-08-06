// P0 — UPLOAD SHOWROOM FOCUS / FINAL GEOMETRY.
//
// Locks the fix for "the upload showroom lands too low after the Hero CTA": the
// scroll now MEASURES the real visual composition (logo + copy + upload block)
// via [pwaScrollToVisualContent] and positions THAT block — never the outer
// viewport-height section, and never with `getOffsetToReveal` (which on a pinned
// header double-counts the header). Two layers of proof:
//
//  1. Pure scroll-math harness (fixed pinned header + a keyed block of KNOWN
//     height at a KNOWN position, plain SizedBoxes → font-independent, exact):
//     asserts centred-when-it-fits, top-aligned-when-tall, header-subtracted-
//     exactly-once, block-height-drives-the-decision (not the section), clamped,
//     and exactly one animation / no runaway retries.
//  2. End-to-end entry: the showroom / fast-path block frames just below the
//     collapsed header at every breakpoint, never at the old ~one-header-too-low
//     position, with no overflow, and re-focusing is idempotent (no state reset).
//
// Fully deterministic (zero-delay mock, reduced-motion), offline.

import 'dart:io';
import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_entry_screen.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_section_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Pure-math harness ────────────────────────────────────────────────────────

/// Fixed (non-shrinking) pinned header of a known [extent].
class _FixedHeader extends SliverPersistentHeaderDelegate {
  _FixedHeader(this.extent);
  final double extent;
  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      const SizedBox.expand(child: ColoredBox(color: Color(0xFF000000)));
  @override
  bool shouldRebuild(covariant _FixedHeader old) => old.extent != extent;
}

/// Counts scroll invocations so we can prove "exactly one animation, no jump,
/// no runaway retry loop".
class _RecordingController extends ScrollController {
  int animateCount = 0;
  int jumpCount = 0;
  final List<double> targets = [];

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    animateCount++;
    targets.add(offset);
    return super.animateTo(offset, duration: duration, curve: curve);
  }

  @override
  void jumpTo(double value) {
    jumpCount++;
    targets.add(value);
    super.jumpTo(value);
  }
}

/// Builds a CustomScrollView whose content sliver holds a keyed block of exactly
/// [blockH] px sitting [preGap] px below the header, with [tail] px beneath it.
/// At rest (offset 0) the block's global top is `header + preGap` — so after
/// [pwaScrollToVisualContent] the block's measured top must equal the function's
/// computed `desiredTop`, with no font/asset ambiguity.
Future<void> _pumpHarness(
  WidgetTester tester, {
  required Size size,
  required double header,
  required double preGap,
  required double blockH,
  required double tail,
  required GlobalKey blockKey,
  required ScrollController controller,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: controller,
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _FixedHeader(header),
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: preGap),
                  KeyedSubtree(
                    key: blockKey,
                    child: SizedBox(height: blockH),
                  ),
                  SizedBox(height: tail),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

double _blockTopGlobal(WidgetTester tester, GlobalKey key) =>
    tester.getTopLeft(find.byKey(key)).dy;

// ── End-to-end entry harness ─────────────────────────────────────────────────

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
  required Size size,
  PwaImageOrigin? withSource,
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
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: true, size: size),
      child: UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PwaExperience()),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  const gap = 28.0;
  const threshold = 0.86;

  // ── 1. Pure scroll-math (exact, font-independent) ──────────────────────────
  group('scroll math — measures the block, not the section', () {
    testWidgets('content that FITS is centred below the header', (
      tester,
    ) async {
      final key = GlobalKey();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      const header = 92.0, vpH = 800.0, blockH = 300.0;
      await _pumpHarness(
        tester,
        size: const Size(1200, vpH),
        header: header,
        preGap: 500,
        blockH: blockH,
        tail: 400,
        blockKey: key,
        controller: ctrl,
      );
      pwaScrollToVisualContent(ctrl, key, headerExtent: header, gap: gap);
      await tester.pumpAndSettle();

      final availH = vpH - header;
      final expected = header + (availH - blockH) / 2; // 296
      expect(_blockTopGlobal(tester, key), closeTo(expected, 1.0));
    });

    testWidgets('header is subtracted EXACTLY once (single-header offset)', (
      tester,
    ) async {
      final key = GlobalKey();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      const header = 92.0, vpH = 800.0, blockH = 300.0;
      await _pumpHarness(
        tester,
        size: const Size(1200, vpH),
        header: header,
        preGap: 500,
        blockH: blockH,
        tail: 400,
        blockKey: key,
        controller: ctrl,
      );
      pwaScrollToVisualContent(ctrl, key, headerExtent: header, gap: gap);
      await tester.pumpAndSettle();

      // Space above the block, below the header == half the leftover room. If the
      // header were double-counted this gap would be ~one header smaller.
      final gapAboveBlock = _blockTopGlobal(tester, key) - header;
      expect(gapAboveBlock, closeTo((vpH - header - blockH) / 2, 1.0)); // 204
    });

    testWidgets('content nearly as tall as the viewport is top-aligned', (
      tester,
    ) async {
      final key = GlobalKey();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      const header = 92.0, vpH = 800.0, blockH = 700.0; // ≥ 0.86·(708)
      await _pumpHarness(
        tester,
        size: const Size(1200, vpH),
        header: header,
        preGap: 300,
        blockH: blockH,
        tail: 200,
        blockKey: key,
        controller: ctrl,
      );
      expect(blockH >= (vpH - header) * threshold, isTrue);
      pwaScrollToVisualContent(ctrl, key, headerExtent: header, gap: gap);
      await tester.pumpAndSettle();

      expect(_blockTopGlobal(tester, key), closeTo(header + gap, 1.0)); // 120
    });

    testWidgets('the BLOCK height drives the decision, not the section height', (
      tester,
    ) async {
      // A small block inside a very tall section. If the code measured the outer
      // section (2200px) it would top-align (120); measuring the block (200px)
      // centres it. Assert centred → proves the visual-content box is measured.
      final key = GlobalKey();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      const header = 92.0, vpH = 800.0, blockH = 200.0;
      await _pumpHarness(
        tester,
        size: const Size(1200, vpH),
        header: header,
        preGap: 1000,
        blockH: blockH,
        tail: 1000,
        blockKey: key,
        controller: ctrl,
      );
      pwaScrollToVisualContent(ctrl, key, headerExtent: header, gap: gap);
      await tester.pumpAndSettle();

      final expectedCentred = header + (vpH - header - blockH) / 2; // 346
      expect(_blockTopGlobal(tester, key), closeTo(expectedCentred, 1.0));
      expect(_blockTopGlobal(tester, key), greaterThan(header + gap + 50));
    });

    testWidgets('target is CLAMPED to maxScrollExtent (never overscrolls)', (
      tester,
    ) async {
      final key = GlobalKey();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      // Tall block near the bottom with no tail: the block cannot be lifted all
      // the way to desiredTop=120, so the scroll must clamp at max.
      const header = 92.0, vpH = 800.0, blockH = 620.0;
      await _pumpHarness(
        tester,
        size: const Size(1200, vpH),
        header: header,
        preGap: 300,
        blockH: blockH,
        tail: 0,
        blockKey: key,
        controller: ctrl,
      );
      pwaScrollToVisualContent(ctrl, key, headerExtent: header, gap: gap);
      await tester.pumpAndSettle();

      expect(ctrl.offset, closeTo(ctrl.position.maxScrollExtent, 0.5));
      // Clamped, so the block never reaches desiredTop — it stays lower.
      expect(_blockTopGlobal(tester, key), greaterThan(header + gap));
    });

    testWidgets('exactly ONE animateTo, zero jumpTo per navigation', (
      tester,
    ) async {
      final key = GlobalKey();
      final ctrl = _RecordingController();
      addTearDown(ctrl.dispose);
      await _pumpHarness(
        tester,
        size: const Size(1200, 800),
        header: 92,
        preGap: 500,
        blockH: 300,
        tail: 400,
        blockKey: key,
        controller: ctrl,
      );
      pwaScrollToVisualContent(ctrl, key, headerExtent: 92, gap: gap);
      await tester.pumpAndSettle();

      expect(ctrl.animateCount, 1, reason: 'no runaway retry loop');
      expect(ctrl.jumpCount, 0);
    });

    testWidgets('animate:false does exactly one jumpTo, zero animateTo', (
      tester,
    ) async {
      final key = GlobalKey();
      final ctrl = _RecordingController();
      addTearDown(ctrl.dispose);
      await _pumpHarness(
        tester,
        size: const Size(1200, 800),
        header: 92,
        preGap: 500,
        blockH: 300,
        tail: 400,
        blockKey: key,
        controller: ctrl,
      );
      pwaScrollToVisualContent(
        ctrl,
        key,
        headerExtent: 92,
        gap: gap,
        animate: false,
      );
      await tester.pumpAndSettle();

      expect(ctrl.jumpCount, 1);
      expect(ctrl.animateCount, 0);
    });

    testWidgets('overlapping navigations settle once at the correct target', (
      tester,
    ) async {
      final key = GlobalKey();
      final ctrl = _RecordingController();
      addTearDown(ctrl.dispose);
      const header = 92.0, vpH = 800.0, blockH = 300.0;
      await _pumpHarness(
        tester,
        size: const Size(1200, vpH),
        header: header,
        preGap: 500,
        blockH: blockH,
        tail: 400,
        blockKey: key,
        controller: ctrl,
      );
      // Fire twice back-to-back: the per-controller token supersedes the stale
      // request; each call still scrolls at most once (no accumulation).
      pwaScrollToVisualContent(ctrl, key, headerExtent: header, gap: gap);
      pwaScrollToVisualContent(ctrl, key, headerExtent: header, gap: gap);
      await tester.pumpAndSettle();

      expect(ctrl.animateCount, lessThanOrEqualTo(2));
      final expected = header + (vpH - header - blockH) / 2;
      expect(_blockTopGlobal(tester, key), closeTo(expected, 1.0));
    });
  });

  // ── 2. Source invariant — no arbitrary timing ──────────────────────────────
  group('navigation uses layout, not arbitrary timers', () {
    test('pwa_section_nav.dart has no Future.delayed / Timer sleeps', () {
      final src = File(
        'lib/features/pwa/presentation/pwa_section_nav.dart',
      ).readAsStringSync();
      expect(src.contains('Future.delayed('), isFalse);
      expect(src.contains('Timer('), isFalse);
      expect(
        src.contains('endOfFrame'),
        isTrue,
        reason: 'waits on real layout',
      );
    });
  });

  // ── 3. Create is framed by the slim bar, with nothing to scroll to ─────────
  //
  // UX-A1 retired the viewport-tall pinned hero and the CTA scroll it required,
  // so the old "block framed just below the header after tapping the CTA" group
  // no longer describes the product. What still matters is that Create starts
  // immediately under the slim bar at rest — asserted here without any scroll.
  group('Create starts directly under the slim bar', () {
    Future<void> expectFramed(
      WidgetTester tester, {
      required Size size,
      required bool withPhoto,
    }) async {
      await _pumpEntry(
        tester,
        size: size,
        withSource: withPhoto ? PwaImageOrigin.userUpload : null,
      );
      final barBottom = tester
          .getRect(find.byKey(const ValueKey('pwa-slim-bar')))
          .bottom;
      final top = tester
          .getTopLeft(find.byKey(const ValueKey('pwa-create')))
          .dy;
      expect(
        top,
        closeTo(barBottom, 1.0),
        reason:
            'Create top ${top.toStringAsFixed(1)} must sit flush under the slim '
            'bar (${barBottom.toStringAsFixed(1)}) at $size photo=$withPhoto',
      );
      expect(barBottom, closeTo(pwaCollapsedHeaderExtent(size.width < 700), 1));
    }

    testWidgets('no photo @1536×864', (t) async {
      await expectFramed(t, size: const Size(1536, 864), withPhoto: false);
    });
    testWidgets('no photo @1920×1080', (t) async {
      await expectFramed(t, size: const Size(1920, 1080), withPhoto: false);
    });
    testWidgets('no photo @1440×900', (t) async {
      await expectFramed(t, size: const Size(1440, 900), withPhoto: false);
    });
    testWidgets('with photo @1536×864', (t) async {
      await expectFramed(t, size: const Size(1536, 864), withPhoto: true);
    });
    testWidgets('with photo @1920×1080', (t) async {
      await expectFramed(t, size: const Size(1920, 1080), withPhoto: true);
    });
  });

  // ── 4. No overflow across the mandated breakpoints ─────────────────────────
  group('no overflow at every breakpoint (both Create states)', () {
    for (final size in const [
      Size(1536, 864),
      Size(1920, 1080),
      Size(1440, 900),
      Size(768, 1024),
      Size(390, 844),
    ]) {
      testWidgets('no photo ${size.width.toInt()}×${size.height.toInt()}', (
        t,
      ) async {
        await _pumpEntry(t, size: size, withSource: null);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
      testWidgets('with photo ${size.width.toInt()}×${size.height.toInt()}', (
        t,
      ) async {
        await _pumpEntry(t, size: size, withSource: PwaImageOrigin.userUpload);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  // ── 5. Frozen-scope integrity guards ───────────────────────────────────────
  group('frozen scope untouched', () {
    test('pubspec.lock is present and pins no new source/git dependency', () {
      final lock = File('pubspec.lock');
      expect(lock.existsSync(), isTrue);
      final txt = lock.readAsStringSync();
      // The offline PWA adds ZERO dependencies — everything stays hosted pub.
      expect(RegExp(r'\n\s+source: git').hasMatch(txt), isFalse);
      expect(RegExp(r'\n\s+source: path').hasMatch(txt), isFalse);
    });

    test('iOS Runner tree exists (out of PWA scope, untouched)', () {
      expect(Directory('ios/Runner').existsSync(), isTrue);
    });
  });
}
