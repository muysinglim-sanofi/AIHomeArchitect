/// AYDEN Part A — Reveal engine (A1, pure logic).
///
/// [RevealEasing] is a **pure-Dart** cubic-Bézier easing — deliberately NOT
/// Flutter's `Curve`. Two reasons:
///   1. it keeps the whole timeline import-free of Flutter, so it is unit
///      testable in isolation;
///   2. it is **serializable** (`toJson`), so the future server-side export
///      renderer (ffmpeg) can reproduce the exact same easing → this class is
///      the *parity contract* between the in-app animation and the export.
///
/// Cubic-Bézier coordinates match Flutter's `Cubic` presets so that, once
/// `compareTease` is wired into the existing `RevealHero` (phase A3), the
/// animation is identical to today's `Curves.easeInOutCubic` tween.
library;

class RevealEasing {
  /// Control-point coordinates of a CSS-style cubic-Bézier from (0,0)→(1,1).
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  /// Linear short-circuit (`y == x`). A plain Bézier (0,0,1,1) is a
  /// smoothstep, not a line, so linear is modelled explicitly.
  final bool isLinear;

  const RevealEasing.cubic(this.x1, this.y1, this.x2, this.y2)
      : isLinear = false;

  const RevealEasing._linear()
      : x1 = 0,
        y1 = 0,
        x2 = 1,
        y2 = 1,
        isLinear = true;

  /// Identity easing (`transform(t) == t`).
  static const RevealEasing linear = RevealEasing._linear();

  /// Matches Flutter `Curves.easeInOutCubic` — used by the existing auto-sweep.
  static const RevealEasing easeInOutCubic =
      RevealEasing.cubic(0.645, 0.045, 0.355, 1.0);

  /// Matches Flutter `Curves.easeOutCubic` — used by the manual-release snap.
  static const RevealEasing easeOutCubic =
      RevealEasing.cubic(0.215, 0.61, 0.355, 1.0);

  /// Maps a normalised time `t ∈ [0,1]` to an eased value `∈ [0,1]`.
  ///
  /// Pure bisection on the Bézier x-parameter, then evaluate y. Deterministic;
  /// converges to far below any visual tolerance.
  double transform(double t) {
    final x = t.clamp(0.0, 1.0).toDouble();
    if (isLinear || x == 0.0 || x == 1.0) return x;

    var lo = 0.0;
    var hi = 1.0;
    var s = x;
    for (var i = 0; i < 64; i++) {
      final xs = _bezier(x1, x2, s);
      final diff = xs - x;
      if (diff.abs() < 1e-9) break;
      if (diff > 0) {
        hi = s;
      } else {
        lo = s;
      }
      s = (lo + hi) / 2;
    }
    return _bezier(y1, y2, s).clamp(0.0, 1.0).toDouble();
  }

  /// 1-D cubic-Bézier with anchors at 0 and 1 and controls [c1], [c2].
  static double _bezier(double c1, double c2, double s) {
    final u = 1 - s;
    return 3 * c1 * u * u * s + 3 * c2 * u * s * s + s * s * s;
  }

  Map<String, dynamic> toJson() =>
      isLinear ? {'linear': true} : {'cubic': [x1, y1, x2, y2]};

  factory RevealEasing.fromJson(Map<String, dynamic> json) {
    if (json['linear'] == true) return RevealEasing.linear;
    final c = (json['cubic'] as List).map((e) => (e as num).toDouble()).toList();
    return RevealEasing.cubic(c[0], c[1], c[2], c[3]);
  }

  @override
  bool operator ==(Object other) =>
      other is RevealEasing &&
      other.isLinear == isLinear &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2;

  @override
  int get hashCode => Object.hash(isLinear, x1, y1, x2, y2);
}
