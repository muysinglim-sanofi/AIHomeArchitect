import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/layout/adaptive_layout.dart';
import '../../core/models/atmosphere_style.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/scrim.dart';

/// Wave 4 — Task B: AtmosphereCard **V2** (shared image-led atmosphere system).
///
/// One unified, premium, editorial card reused by FTUE-3, New Design Session,
/// the Reveal strip and the Re-upload flow. Replaces the previous fractured
/// implementation:
///   • image now DOMINATES (full-bleed); typography is OVERLAID, not a panel
///   • typography routed through `AppTheme.atmosphereTitle()` — the hard-coded
///     'Lato' fracture is gone (one type system)
///   • removed: floating icon badge, cream text panel, all box shadows,
///     gamified "filter pill" feel
///   • selection is calm: a subtle inset accent border — it does NOT scream
///   • size-adaptive: `compact` vs `editorial` auto-derived from the available
///     box via `AppAdaptive.cardMode` so the tiny FTUE/Reveal strip cards
///     (~76–100 px) degrade gracefully and are never visually broken
///   • Wave 4.10d: the image fallback is now a robust 4-tier chain
///     (local hero → showcase → ftue local hero → network → shimmer) so
///     every atmosphere renders a real LOCAL image with no network
///     dependency, plus a deterministic ink legibility floor so the
///     overlaid name is always readable even on the shimmer/failure plate
///
/// Backward compatible: the primary constructor keeps the exact public shape
/// `AtmosphereCard({atmosphere, selected, onTap, key})` so all existing
/// callsites compile and render unchanged in structure (no screen migration in
/// this PR — screens consume the improved widget as-is). `dark` + `variant`
/// are optional with size-aware defaults.
///
/// `AtmosphereCard.custom(...)` provides the shared "describe your own" shell
/// NOW so Wave 4.3 can fold `_CustomAtmosphereCard` (currently private inside
/// upload_screen.dart — not modifiable in this PR) into this component later.
enum AtmosphereCardVariant { auto, editorial, compact }

class AtmosphereCard extends StatelessWidget {
  /// Null only for the `.custom` "describe your dream space" tile.
  final AtmosphereStyle? atmosphere;
  final bool selected;
  final VoidCallback onTap;
  final bool dark;
  final AtmosphereCardVariant variant;

  // Custom-tile payload (null for normal atmosphere cards).
  final String? _customLabel;
  final String? _customSublabel;

  const AtmosphereCard({
    super.key,
    required AtmosphereStyle this.atmosphere,
    required this.selected,
    required this.onTap,
    this.dark = false,
    this.variant = AtmosphereCardVariant.auto,
  })  : _customLabel = null,
        _customSublabel = null;

  /// Shared "describe your own" tile — same shell language as the atmosphere
  /// cards (no image; calm editorial surface; identical selection cue).
  /// Capability-now / fold-later: upload_screen's `_CustomAtmosphereCard`
  /// migrates onto this in Wave 4.3.
  const AtmosphereCard.custom({
    super.key,
    required String label,
    String? sublabel,
    required this.selected,
    required this.onTap,
    this.dark = true,
    this.variant = AtmosphereCardVariant.auto,
  })  : atmosphere = null,
        _customLabel = label,
        _customSublabel = sublabel;

  bool get _isCustom => atmosphere == null;

  bool _isCompact(double h) {
    switch (variant) {
      case AtmosphereCardVariant.compact:
        return true;
      case AtmosphereCardVariant.editorial:
        return false;
      case AtmosphereCardVariant.auto:
        return AppAdaptive.cardMode(h) == AtmCardMode.compact;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (ctx, box) {
          final h = box.maxHeight;
          final mode = AppAdaptive.cardMode(h);
          final compact = _isCompact(h);

          // Editorial type scale — calibrated for the OVERLAY (not a panel).
          final nameSize = switch (mode) {
            AtmCardMode.full => 18.0,
            AtmCardMode.semi => 15.0,
            AtmCardMode.compact => 12.5,
          };
          final showTagline =
              !compact && !_isCustom && AppAdaptive.cardShowsTagline(h);
          final nameMaxLines = AppAdaptive.cardNameMaxLines(h);
          final taglineMaxLines = AppAdaptive.cardTaglineMaxLines(h);

          final borderColor = selected
              ? AppColors.accent
              : (dark
                  ? Colors.white.withValues(alpha: 0.14)
                  : AppColors.border);

          // Text sits on a scrim/dark surface → light type for legibility.
          const onSurface = AppColors.surface;

          Widget textColumn() => Padding(
                padding: EdgeInsets.fromLTRB(
                    compact ? 8 : 10, 0, compact ? 8 : 10, compact ? 8 : 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isCustom ? _customLabel! : atmosphere!.name,
                      maxLines: nameMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.atmosphereTitle(
                        fontSize: nameSize,
                        fontWeight: FontWeight.w600,
                        color: onSurface,
                        height: 1.12,
                      ),
                    ),
                    if (showTagline || (_isCustom && _customSublabel != null)) ...[
                      const SizedBox(height: 2),
                      Text(
                        _isCustom
                            ? _customSublabel!
                            : atmosphere!.tagline,
                        maxLines: _isCustom ? 2 : taglineMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: onSurface.withValues(alpha: 0.78),
                              fontSize: mode == AtmCardMode.full ? 11 : 10,
                              height: 1.25,
                            ),
                      ),
                    ],
                  ],
                ),
              );

          // ── Background layer ──────────────────────────────────────────────
          // Atmosphere card → full-bleed photo + bottom scrim.
          // Custom tile    → calm solid editorial surface (no image).
          final Widget background = _isCustom
              ? const ColoredBox(color: AppColors.textPrimary)
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    _AtmosphereHeroImage(atmosphere: atmosphere!),
                    const AppScrim(
                      edge: ScrimEdge.bottom,
                      opacity: 0.62,
                      extent: 0.62,
                    ),
                  ],
                );

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
              border: Border.all(
                color: borderColor,
                width: selected ? 2 : 1,
              ),
            ),
            // No boxShadow — depth comes from the image + scrim + type only.
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                background,
                // Legibility floor (Wave 4.10d): a deterministic ink ramp in
                // the lower band, present regardless of which image tier
                // resolved. On a real photo it stacks imperceptibly with the
                // atmospheric AppScrim; on the shimmer/failure plate it is the
                // sole anchor, so the overlaid name is ALWAYS legible (no more
                // light-grey "floating text"). Image cards only — the custom
                // tile is already a solid ink surface.
                if (!_isCustom)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.55, 1.0],
                        colors: [
                          AppColors.textPrimary.withValues(alpha: 0.0),
                          AppColors.textPrimary.withValues(alpha: 0.58),
                        ],
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: textColumn(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Hero image — four-level fallback (Wave 4.10d) ─────────────────────────────
// 1. heroImagePath    — local, assets/atmospheres/{id}.jpg (none ship yet)
// 2. showcaseAsset    — local AI output (only 4 atmospheres have this)
// 3. ftueHeroImagePath — local, assets/atmospheres/ftue/ftue_{id}.jpg
//                        (ALL 10 ship → guarantees a real local image with
//                        zero network dependency; this is the reliability fix)
// 4. fallbackImageUrl — Unsplash network (last resort)
// Shimmer placeholder while network loads; warm grey on complete failure
// (paired with a deterministic ink legibility floor in the card Stack so the
// name is always legible even in that worst case).
// Rendered FULL-BLEED (image-led) instead of in a top 65% slot.
class _AtmosphereHeroImage extends StatelessWidget {
  final AtmosphereStyle atmosphere;
  const _AtmosphereHeroImage({required this.atmosphere});

  static const _shimmer = Color(0xFFE8E5E0);

  Widget _net(String url) => CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, _) => const ColoredBox(color: _shimmer),
        errorWidget: (_, _, _) => const ColoredBox(color: _shimmer),
      );

  Widget _asset(String path, {Widget? onError}) => Image.asset(
        path,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => onError ?? const ColoredBox(color: _shimmer),
      );

  @override
  Widget build(BuildContext context) {
    // Built bottom-up so the chain reads exactly:
    //   heroImagePath → showcaseAsset → ftueHeroImagePath → network → shimmer
    final network = _net(atmosphere.fallbackImageUrl);
    // New reliable local tier: all 10 ftue heroes ship, so this resolves
    // locally for every atmosphere — no card is blank when offline / when an
    // Unsplash URL is dead. (Public data/contract unchanged: ftueHeroImagePath
    // is already on AtmosphereStyle; only the card chooses to use it here.)
    final ftueTier =
        _asset(atmosphere.ftueHeroImagePath, onError: network);
    final showcase = atmosphere.showcaseAsset;
    final showcaseTier = showcase != null
        ? _asset(showcase, onError: ftueTier)
        : ftueTier;
    return _asset(atmosphere.heroImagePath, onError: showcaseTier);
  }
}
