import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';

/// Wave 4 — Design-System Spine.
///
/// The single progress-dot system. One canonical, subtly-animated indicator
/// that later replaces the two divergent copies (`_Dot` 24x7 in onboarding,
/// `_HeroProgressDot` 20x6 on home).
///
/// Implicitly animated (no controller) — the active dot eases wide; calm,
/// premium, reusable. This PR only introduces the widget; usages are not
/// migrated yet.
class AppDots extends StatelessWidget {
  final int count;
  final int index;
  final Color activeColor;
  final Color inactiveColor;
  final double activeWidth;
  final double dotSize;

  /// Optional — when provided, each dot becomes tappable and calls this with
  /// the dot index. The visible dot is unchanged; a transparent hit-target is
  /// added around it so the 6px dot is comfortably tappable (~40px zone).
  /// Omit it (default) to keep the indicator display-only (e.g. onboarding).
  final ValueChanged<int>? onDotTap;

  const AppDots({
    super.key,
    required this.count,
    required this.index,
    this.activeColor = AppColors.textPrimary,
    this.inactiveColor = AppColors.border,
    this.activeWidth = 22,
    this.dotSize = 6,
    this.onDotTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == index;
        final dot = AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? activeWidth : dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            color: active ? activeColor : inactiveColor,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
        );
        if (onDotTap == null) return dot;
        // Expand the tap target around the small dot without changing its look.
        return Semantics(
          button: true,
          selected: active,
          label: 'Slide ${i + 1} of $count',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onDotTap!(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: dot,
            ),
          ),
        );
      }),
    );
  }
}
