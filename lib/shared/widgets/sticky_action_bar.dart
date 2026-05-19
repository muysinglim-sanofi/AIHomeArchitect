import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';

/// Wave 4 — Design-System Spine.
///
/// The single bottom-anchored CTA region. Codifies the pattern `upload_screen`
/// already gets right (a non-scrolling Container with a hairline top border +
/// safe-area padding) so later waves can fix the screens that get it wrong
/// (Home CTA below the fold, Re-upload CTA below the fold).
///
/// Deliberately flat: a hairline divider, no Material elevation / drop shadow
/// (consistent with the shadowless-chrome baseline). Safe-area aware.
///
/// Compose freely: pass a `primary` CTA (typically an `AppButton`) and an
/// optional quiet `secondary` action rendered beneath it. This PR only
/// introduces the widget; no screen adopts it yet.
class StickyActionBar extends StatelessWidget {
  final Widget primary;
  final Widget? secondary;
  final Color background;

  const StickyActionBar({
    super.key,
    required this.primary,
    this.secondary,
    this.background = AppColors.background,
  });

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.md,
        AppSpacing.pagePadding,
        AppSpacing.md + safeBottom,
      ),
      decoration: BoxDecoration(
        color: background,
        border: const Border(
          top: BorderSide(color: AppColors.borderLight),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          primary,
          if (secondary != null) ...[
            const SizedBox(height: AppSpacing.sm),
            secondary!,
          ],
        ],
      ),
    );
  }
}
