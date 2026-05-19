import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Wave 4 — Design-System Spine.
///
/// Shared image-legibility scrim. One lightweight gradient overlay that later
/// replaces the inline `LinearGradient` copies in onboarding / home / reveal
/// (and provides the legibility layer the reveal title currently lacks).
///
/// Drop into a `Stack` (it is `Positioned.fill`-friendly via the parent).
/// Non-interactive by design (`IgnorePointer`) so it never blocks the
/// slider / canvas gestures beneath it. This PR only introduces the widget.
enum ScrimEdge { top, bottom }

class AppScrim extends StatelessWidget {
  final ScrimEdge edge;

  /// Peak opacity of the scrim colour at the anchored edge (0.0–1.0).
  final double opacity;

  /// Scrim colour (defaults to the app ink so it reads as depth, not haze).
  final Color color;

  /// Fraction of the height the gradient spans from the anchored edge.
  final double extent;

  const AppScrim({
    super.key,
    this.edge = ScrimEdge.bottom,
    this.opacity = 0.6,
    this.color = AppColors.textPrimary,
    this.extent = 0.45,
  });

  @override
  Widget build(BuildContext context) {
    final solid = color.withValues(alpha: opacity.clamp(0.0, 1.0));
    final isTop = edge == ScrimEdge.top;

    final gradient = LinearGradient(
      begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
      end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
      colors: [solid, Colors.transparent],
      stops: [0.0, extent.clamp(0.0, 1.0)],
    );

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: const SizedBox.expand(),
      ),
    );
  }
}
