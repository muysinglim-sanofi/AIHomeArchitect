import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';

/// Wave 4 — Design-System Spine.
///
/// The single premium pill / label / badge primitive. Replaces (in later
/// waves, NOT here) the divergent copies scattered across screens:
/// `_OverlayPill`, `_SlideLabel`, `_CategoryPill`, `_SessionsBadge`, and
/// inline chips.
///
/// Deliberately restrained: no gamified sparkle, no loud gradient, no heavy
/// shadow — quiet confidence only. Two surfaces:
///   • light (default) — cream-on-ink-text, for light backgrounds
///   • dark            — ink-on-surface-text, for placing over imagery
///
/// This PR only introduces the widget; existing usages are not migrated.
class AppPill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool dark;
  final VoidCallback? onTap;

  const AppPill({
    super.key,
    required this.text,
    this.icon,
    this.dark = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = dark ? AppColors.surface : AppColors.textPrimary;

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.textPrimary.withAlpha(200)
            : AppColors.surface.withAlpha(230),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
          ),
        ],
      ),
    );

    if (onTap == null) return pill;
    return GestureDetector(onTap: onTap, child: pill);
  }
}
