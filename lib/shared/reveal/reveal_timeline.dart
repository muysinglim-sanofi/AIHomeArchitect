/// AYDEN Part A — Reveal engine (A1, pure logic).
///
/// [RevealTimeline] is the **pure, deterministic keystone**: a single function
/// that maps a [RevealProfile] + elapsed time → a [RevealFrame]. No Flutter,
/// no state, no clock, no randomness — same inputs always yield the same frame.
///
/// Both the in-app [AnimationController] loop (via `RevealController`) and the
/// future server-side export renderer evaluate THIS function, which is what
/// guarantees the exported video reproduces the in-app animation.
library;

import 'reveal_frame.dart';
import 'reveal_profile.dart';

class RevealTimeline {
  const RevealTimeline._();

  /// Sample the [profile] at [elapsed] (measured from absolute t=0, i.e.
  /// including the profile's `startDelay`).
  static RevealFrame sample(RevealProfile profile, Duration elapsed) {
    final elapsedMs = elapsed.inMicroseconds / 1000.0;
    final delayMs = profile.startDelay.inMicroseconds / 1000.0;
    final local = elapsedMs - delayMs;

    return RevealFrame(
      progress: _sampleProgress(profile, local).clamp(0.0, 1.0).toDouble(),
      zoom: _sampleZoom(profile, local),
    );
  }

  static double _sampleProgress(RevealProfile p, double local) {
    final kfs = p.keyframes;
    if (local <= 0) return kfs.first.progress;

    final lastAtMs = kfs.last.at.inMicroseconds / 1000.0;
    if (local >= lastAtMs) return kfs.last.progress;

    for (var i = 0; i < kfs.length - 1; i++) {
      final a = kfs[i];
      final b = kfs[i + 1];
      final aMs = a.at.inMicroseconds / 1000.0;
      final bMs = b.at.inMicroseconds / 1000.0;
      if (local >= aMs && local < bMs) {
        final seg = bMs - aMs;
        if (seg <= 0) return b.progress;
        final f = (local - aMs) / seg;
        final eased = a.curveToNext.transform(f);
        return _lerp(a.progress, b.progress, eased);
      }
    }
    return kfs.last.progress;
  }

  static double _sampleZoom(RevealProfile p, double local) {
    if (p.zoomFrom == p.zoomTo) return p.zoomFrom;

    final lastAtMs = p.keyframes.last.at.inMicroseconds / 1000.0;
    if (local <= 0) return p.zoomFrom;
    if (local >= lastAtMs || lastAtMs <= 0) return p.zoomTo;

    final eased = p.zoomEasing.transform(local / lastAtMs);
    return _lerp(p.zoomFrom, p.zoomTo, eased);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
