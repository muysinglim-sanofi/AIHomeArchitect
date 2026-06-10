/// AYDEN Part A — Reveal engine (A1, pure logic).
///
/// A single sampled output of the timeline at one instant: how far the reveal
/// has progressed and the current shared push-zoom. Consumed (later) by the
/// on-screen widget and the export renderer alike.
library;

class RevealFrame {
  /// Reveal progress: **0 = full BEFORE, 1 = full AFTER**.
  /// Bridges to the existing `RevealHero.fraction` via `fraction = 1 - progress`.
  final double progress;

  /// Shared push-zoom applied identically to BOTH layers (≥ 1.0). A crop of
  /// real pixels — never generated, so geometry is preserved.
  final double zoom;

  const RevealFrame({required this.progress, required this.zoom});

  @override
  bool operator ==(Object other) =>
      other is RevealFrame && other.progress == progress && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(progress, zoom);

  @override
  String toString() => 'RevealFrame(progress: $progress, zoom: $zoom)';
}
