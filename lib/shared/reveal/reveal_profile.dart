/// AYDEN Part A — Reveal engine (A1, pure logic).
///
/// Declarative, serializable description of a reveal animation. **Data, not
/// code paths** — the same engine plays every profile, and the export renderer
/// consumes the serialized form. Adding a profile never branches the engine.
///
/// Progress space: **0 = full BEFORE, 1 = full AFTER**
/// (`RevealHero.fraction = 1 - progress`).
library;

import 'reveal_easing.dart';

/// One point on the progress timeline. [at] is measured from the END of
/// [RevealProfile.startDelay]; [curveToNext] eases the segment to the next key.
class RevealKeyframe {
  final Duration at;
  final double progress;
  final RevealEasing curveToNext;

  const RevealKeyframe({
    required this.at,
    required this.progress,
    this.curveToNext = RevealEasing.easeInOutCubic,
  });

  Map<String, dynamic> toJson() => {
        'atMs': at.inMicroseconds / 1000.0,
        'progress': progress,
        'curveToNext': curveToNext.toJson(),
      };

  factory RevealKeyframe.fromJson(Map<String, dynamic> json) => RevealKeyframe(
        at: Duration(microseconds: ((json['atMs'] as num) * 1000).round()),
        progress: (json['progress'] as num).toDouble(),
        curveToNext:
            RevealEasing.fromJson(json['curveToNext'] as Map<String, dynamic>),
      );
}

/// Magnetic-snap behaviour on manual-drag release (applied in phase A4).
/// Targets are in **progress** space.
class SnapConfig {
  final List<double> targets;
  final double threshold;
  final Duration duration;
  final RevealEasing easing;

  const SnapConfig({
    required this.targets,
    this.threshold = 0.05,
    this.duration = const Duration(milliseconds: 180),
    this.easing = RevealEasing.easeOutCubic,
  });

  /// Pure: the **nearest** target within [threshold] of [progress], or null if
  /// the release is outside every attractor (assistance, not a constraint).
  double? resolve(double progress) {
    double? best;
    var bestDist = threshold;
    for (final t in targets) {
      final d = (progress - t).abs();
      if (d < bestDist) {
        bestDist = d;
        best = t;
      }
    }
    return best;
  }

  Map<String, dynamic> toJson() => {
        'targets': targets,
        'threshold': threshold,
        'durationMs': duration.inMicroseconds / 1000.0,
        'easing': easing.toJson(),
      };

  factory SnapConfig.fromJson(Map<String, dynamic> json) => SnapConfig(
        targets: (json['targets'] as List)
            .map((e) => (e as num).toDouble())
            .toList(),
        threshold: (json['threshold'] as num).toDouble(),
        duration:
            Duration(microseconds: ((json['durationMs'] as num) * 1000).round()),
        easing: RevealEasing.fromJson(json['easing'] as Map<String, dynamic>),
      );
}

class RevealProfile {
  final String id;

  /// Delay before the keyframe timeline starts (progress holds at the first
  /// keyframe during this window).
  final Duration startDelay;

  /// Ordered keyframes (first `at` should be `Duration.zero`).
  final List<RevealKeyframe> keyframes;

  /// Shared push-zoom, ramped across the post-delay window via [zoomEasing].
  final double zoomFrom;
  final double zoomTo;
  final RevealEasing zoomEasing;

  /// Soft-edge width of the sweep, as a fraction of width (0 = hard edge).
  final double feather;

  final bool loop;

  /// Manual-release snap; null = no snap.
  final SnapConfig? snap;

  const RevealProfile({
    required this.id,
    required this.startDelay,
    required this.keyframes,
    this.zoomFrom = 1.0,
    this.zoomTo = 1.0,
    this.zoomEasing = RevealEasing.easeInOutCubic,
    this.feather = 0.0,
    this.loop = false,
    this.snap,
  });

  /// Total playable duration (delay + last keyframe time).
  Duration get total => startDelay + keyframes.last.at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'startDelayMs': startDelay.inMicroseconds / 1000.0,
        'keyframes': keyframes.map((k) => k.toJson()).toList(),
        'zoomFrom': zoomFrom,
        'zoomTo': zoomTo,
        'zoomEasing': zoomEasing.toJson(),
        'feather': feather,
        'loop': loop,
        'snap': snap?.toJson(),
      };

  factory RevealProfile.fromJson(Map<String, dynamic> json) => RevealProfile(
        id: json['id'] as String,
        startDelay: Duration(
            microseconds: ((json['startDelayMs'] as num) * 1000).round()),
        keyframes: (json['keyframes'] as List)
            .map((e) => RevealKeyframe.fromJson(e as Map<String, dynamic>))
            .toList(),
        zoomFrom: (json['zoomFrom'] as num).toDouble(),
        zoomTo: (json['zoomTo'] as num).toDouble(),
        zoomEasing:
            RevealEasing.fromJson(json['zoomEasing'] as Map<String, dynamic>),
        feather: (json['feather'] as num).toDouble(),
        loop: json['loop'] as bool,
        snap: json['snap'] == null
            ? null
            : SnapConfig.fromJson(json['snap'] as Map<String, dynamic>),
      );

  // ── Presets ────────────────────────────────────────────────────────────

  /// Part A default: hold BEFORE → soft sweep → settle on AFTER (~5.5s).
  static const RevealProfile cinematic = RevealProfile(
    id: 'cinematic',
    startDelay: Duration(milliseconds: 300),
    keyframes: [
      RevealKeyframe(at: Duration.zero, progress: 0.0, curveToNext: RevealEasing.linear),
      RevealKeyframe(at: Duration(milliseconds: 1200), progress: 0.0),
      RevealKeyframe(at: Duration(milliseconds: 3000), progress: 1.0, curveToNext: RevealEasing.linear),
      RevealKeyframe(at: Duration(milliseconds: 5500), progress: 1.0),
    ],
    zoomFrom: 1.0,
    zoomTo: 1.05,
    feather: 0.06,
    snap: SnapConfig(targets: [0.0, 0.5, 1.0], threshold: 0.06),
  );

  /// Exact reproduction of the existing `RevealHero` auto-sweep
  /// (fraction 0.30→0.66→0.42 over 2800ms after an 800ms delay), expressed in
  /// progress space (`progress = 1 - fraction`). Hard edge, no zoom.
  static const RevealProfile compareTease = RevealProfile(
    id: 'compareTease',
    startDelay: Duration(milliseconds: 800),
    keyframes: [
      RevealKeyframe(at: Duration.zero, progress: 0.70),
      RevealKeyframe(at: Duration(milliseconds: 1400), progress: 0.34, curveToNext: RevealEasing.linear),
      RevealKeyframe(at: Duration(milliseconds: 1736), progress: 0.34),
      RevealKeyframe(at: Duration(milliseconds: 2800), progress: 0.58),
    ],
    snap: SnapConfig(targets: [0.98, 0.5, 0.02]),
  );

  /// Reels/TikTok-optimised: faster hook, payoff early (~4s).
  static const RevealProfile social = RevealProfile(
    id: 'social',
    startDelay: Duration(milliseconds: 200),
    keyframes: [
      RevealKeyframe(at: Duration.zero, progress: 0.0, curveToNext: RevealEasing.linear),
      RevealKeyframe(at: Duration(milliseconds: 600), progress: 0.0),
      RevealKeyframe(at: Duration(milliseconds: 1800), progress: 1.0, curveToNext: RevealEasing.linear),
      RevealKeyframe(at: Duration(milliseconds: 4000), progress: 1.0),
    ],
    zoomFrom: 1.0,
    zoomTo: 1.03,
    feather: 0.06,
    loop: true,
  );

  /// App Store preview: clear before→after by ~3s (~5s total).
  static const RevealProfile appStore = RevealProfile(
    id: 'appStore',
    startDelay: Duration(milliseconds: 300),
    keyframes: [
      RevealKeyframe(at: Duration.zero, progress: 0.0, curveToNext: RevealEasing.linear),
      RevealKeyframe(at: Duration(milliseconds: 1000), progress: 0.0),
      RevealKeyframe(at: Duration(milliseconds: 3000), progress: 1.0, curveToNext: RevealEasing.linear),
      RevealKeyframe(at: Duration(milliseconds: 5000), progress: 1.0),
    ],
    zoomFrom: 1.0,
    zoomTo: 1.02,
    feather: 0.05,
  );

  /// Fast preview / thumbnail generation.
  static const RevealProfile fast = RevealProfile(
    id: 'fast',
    startDelay: Duration.zero,
    keyframes: [
      RevealKeyframe(at: Duration.zero, progress: 0.0),
      RevealKeyframe(at: Duration(milliseconds: 900), progress: 1.0),
    ],
    feather: 0.04,
  );

  /// All presets, keyed by id (for export-spec round-trips / lookups).
  static const Map<String, RevealProfile> presets = {
    'cinematic': cinematic,
    'compareTease': compareTease,
    'social': social,
    'appStore': appStore,
    'fast': fast,
  };
}
