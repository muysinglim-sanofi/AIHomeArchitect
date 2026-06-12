import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';

// Wave 4 — Design-System Spine: `onImage` + `dark` added so every CTA in the
// app can route through ONE button (replacing _DarkButton / _CardAction / raw
// ElevatedButtons in later waves). Existing variants are byte-unchanged; new
// variants reuse the same radius/padding language (no app-wide redesign here).
enum AppButtonVariant { primary, secondary, ghost, accent, onImage, dark }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool fullWidth;
  final bool loading;
  final IconData? icon;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.fullWidth = true,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
              Text(label),
            ],
          );

    Widget button;
    switch (variant) {
      case AppButtonVariant.primary:
        button = ElevatedButton(
          onPressed: loading ? null : onPressed,
          // CHANTIER C — clearer disabled state. The theme default reads as a
          // near-invisible flat grey ("broken?"); a muted-but-present accent
          // says "not ready yet" while keeping a premium feel.
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.32),
            disabledForegroundColor: AppColors.surface.withValues(alpha: 0.85),
          ),
          child: child,
        );
      case AppButtonVariant.secondary:
        button = OutlinedButton(onPressed: loading ? null : onPressed, child: child);
      case AppButtonVariant.ghost:
        button = TextButton(
          onPressed: loading ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            ),
          ),
          child: child,
        );
      case AppButtonVariant.accent:
        button = ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.surface,
            disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.32),
            disabledForegroundColor: AppColors.surface.withValues(alpha: 0.85),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            ),
          ),
          child: child,
        );
      // Solid light CTA for dark / non-image surfaces (e.g. reveal bottom bar).
      // High-contrast cream-on-ink so it reads on the dark scaffold.
      case AppButtonVariant.dark:
        button = ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
            ),
          ),
          child: child,
        );
      // CTA placed over imagery — near-solid ink keeps affordance while
      // hinting "over media"; pairs with the scrim system.
      case AppButtonVariant.onImage:
        button = ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.textPrimary.withAlpha(235),
            foregroundColor: AppColors.surface,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
            ),
          ),
          child: child,
        );
    }

    if (fullWidth) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}
