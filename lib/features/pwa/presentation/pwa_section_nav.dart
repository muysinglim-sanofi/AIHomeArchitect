/// Batch 2.2 V5 — centralized, viewport-aware section navigation (§14).
///
/// One reusable mechanism for every in-page scroll target (hero CTA → upload
/// showroom, photo upload → post-upload fast path, Back to Studio → the right
/// section). It measures the target RenderBox AFTER layout, accounts for the
/// pinned/sticky header extent, and computes a CLAMPED scroll offset that either
/// centres the section (when it fits below the header) or top-aligns it with a
/// controlled margin (when it is taller than the viewport). No arbitrary
/// `Future.delayed` timing guesses — it runs on the post-layout frame, with a
/// per-controller dedupe token so stale requests are cancelled.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

final Map<ScrollController, int> _navTokens = {};

/// Scroll [controller] so the widget behind [key] is framed below a sticky
/// header of [stickyExtent] px. Centres it when it fits, else top-aligns it with
/// [topMargin]. [animate] false does an instant jump (used on a fresh mount so
/// Back-to-Studio never lands on an empty offset). Safe to call before layout —
/// it reschedules onto the next frame and no-ops if the target/controller is
/// gone or superseded by a newer request.
Future<void> pwaScrollToSection(
  ScrollController controller,
  GlobalKey key, {
  required double stickyExtent,
  double topMargin = 16,
  bool animate = true,
  Duration duration = const Duration(milliseconds: 600),
}) async {
  final token = (_navTokens[controller] ?? 0) + 1;
  _navTokens[controller] = token;

  Future<void> run() async {
    // Superseded by a newer navigation request → abandon.
    if (_navTokens[controller] != token) return;
    final ctx = key.currentContext;
    if (ctx == null || !controller.hasClients) return;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (viewport == null) return;

    final position = controller.position;
    final revealTop = viewport.getOffsetToReveal(ro, 0.0).offset;
    final vpH = position.viewportDimension;
    final targetH = ro.size.height;
    final availH = (vpH - stickyExtent).clamp(1.0, vpH);

    final double delta = targetH <= availH
        ? stickyExtent +
              (availH - targetH) /
                  2 // centre in the area below header
        : stickyExtent + topMargin; // taller than viewport → top-align + margin

    final target = (revealTop - delta).clamp(0.0, position.maxScrollExtent);

    if (animate) {
      await controller.animateTo(
        target,
        duration: duration,
        curve: Curves.easeInOutCubic,
      );
    } else {
      controller.jumpTo(target);
    }
  }

  // Run after the target has been laid out for this frame.
  final binding = WidgetsBinding.instance;
  if (binding.schedulerPhase == SchedulerPhase.idle) {
    await run();
  } else {
    binding.addPostFrameCallback((_) => run());
  }
}

/// P0 — scroll [controller] so the REAL visible composition behind [contentKey]
/// (the logo + copy + upload block, NOT the outer viewport-height section) is
/// framed correctly under a sticky header of [headerExtent] px.
///
/// It measures the block's ACTUAL on-screen top (`localToGlobal`) and height,
/// then computes the scroll delta directly — never `getOffsetToReveal`, which on
/// a pinned-header viewport already offsets by the header and, combined with a
/// section that also reserves the header internally, double-counts it. When the
/// block fits comfortably it is centred in the area below the header; when it is
/// nearly as tall as (or taller than) that area it is top-aligned [gap] px below
/// the header. Exactly one animation runs; stale requests are cancelled via the
/// per-controller token; it waits for a non-zero laid-out size (a few frames, no
/// time-based delays) before scrolling.
Future<void> pwaScrollToVisualContent(
  ScrollController controller,
  GlobalKey contentKey, {
  required double headerExtent,
  double gap = 24,
  double topAlignThreshold = 0.86,
  bool animate = true,
  Duration duration = const Duration(milliseconds: 420),
}) async {
  final token = (_navTokens[controller] ?? 0) + 1;
  _navTokens[controller] = token;

  bool tryScroll() {
    final ctx = contentKey.currentContext;
    if (ctx == null || !controller.hasClients) return false;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize || ro.size.height <= 1) return false;
    final position = controller.position;
    final vpH = position.viewportDimension;
    if (vpH <= 0) return false;
    final blockTop = ro.localToGlobal(Offset.zero).dy;
    final blockH = ro.size.height;
    final availH = (vpH - headerExtent).clamp(1.0, vpH);
    // Fits → centre below the header; tall → top-align a controlled gap down.
    final desiredTop = blockH >= availH * topAlignThreshold
        ? headerExtent + gap
        : headerExtent + (availH - blockH) / 2;
    final delta = blockTop - desiredTop;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (animate) {
      controller.animateTo(
        target,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    } else {
      controller.jumpTo(target);
    }
    return true;
  }

  final binding = WidgetsBinding.instance;
  // Wait for the block to reach a final, non-zero size — a few frames at most —
  // then perform exactly ONE scroll. No sleeps; stale requests bail out.
  for (var i = 0; i < 10; i++) {
    if (_navTokens[controller] != token) return; // superseded → stop
    if (binding.schedulerPhase != SchedulerPhase.idle) {
      await binding.endOfFrame;
      if (_navTokens[controller] != token) return;
    }
    if (tryScroll()) return;
    await binding.endOfFrame;
  }
}
