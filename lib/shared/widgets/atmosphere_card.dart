import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/layout/adaptive_layout.dart';
import '../../core/models/atmosphere_style.dart';

class AtmosphereCard extends StatelessWidget {
  final AtmosphereStyle atmosphere;
  final bool selected;
  final VoidCallback onTap;

  const AtmosphereCard({
    super.key,
    required this.atmosphere,
    required this.selected,
    required this.onTap,
  });

  static const _cardBg = Color(0xFFFAF8F5);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(
            color: selected ? AppColors.accent : const Color(0xFFE5E1DB),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.20)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: selected ? 14 : 6,
              spreadRadius: selected ? 1 : 0,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        // Clip.antiAlias is the final visual safety net —
        // any content that escapes inner layout is trimmed here.
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (ctx, box) {
            final h = box.maxHeight;

            // ── Adaptive sizing from AppAdaptive ──────────────────────────────
            final iconD = AppAdaptive.cardIconDiameter(h);
            final iconR = iconD / 2;
            final imageH = h * AppAdaptive.cardImageRatio(h);
            final iconTextGap = AppAdaptive.cardIconTextGap(h);
            // Where the text column top begins (below icon center + gap).
            final textTop = imageH + iconR + iconTextGap;
            // Available vertical space for the text column.
            final textAvail = h - textTop;

            final showTagline = AppAdaptive.cardShowsTagline(h);
            final nameMaxLines = AppAdaptive.cardNameMaxLines(h);
            final taglineMaxLines = AppAdaptive.cardTaglineMaxLines(h);
            final nameFontSize = AppAdaptive.cardNameFontSize(h);
            final taglineFontSize = AppAdaptive.cardTaglineFontSize(h);
            final nameTaglineGap = AppAdaptive.cardNameTaglineGap(h);

            return Stack(
              // Clip.none: icon deliberately straddles image/text boundary.
              // The outer AnimatedContainer(Clip.antiAlias) is the visual fence.
              clipBehavior: Clip.none,
              children: [
                // ── Hero image ────────────────────────────────────────────────
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: imageH,
                  child: _AtmosphereHeroImage(atmosphere: atmosphere),
                ),

                // ── Cream text background ─────────────────────────────────────
                Positioned(
                  top: imageH,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: const ColoredBox(color: _cardBg),
                ),

                // ── Floating icon — centered on image/text boundary ───────────
                Positioned(
                  top: imageH - iconR,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _AtmosphereFloatingIcon(
                      atmosphere: atmosphere,
                      diameter: iconD,
                    ),
                  ),
                ),

                // ── Text column ───────────────────────────────────────────────
                // Primary strategy: adaptive — only renders what fits.
                // Defensive fallback: OverflowBox handles a11y font scaling
                // edge cases; outer Clip.antiAlias trims any visual bleed.
                Positioned(
                  top: textTop,
                  left: 6,
                  right: 6,
                  // Use all remaining space; OverflowBox handles the rest.
                  height: textAvail.clamp(0.0, double.infinity),
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    maxHeight: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          atmosphere.name,
                          textAlign: TextAlign.center,
                          maxLines: nameMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Lato',
                            fontWeight: FontWeight.w600,
                            fontSize: nameFontSize,
                            color: selected
                                ? AppColors.accent
                                : AppColors.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        if (showTagline) ...[
                          SizedBox(height: nameTaglineGap),
                          Text(
                            atmosphere.tagline,
                            textAlign: TextAlign.center,
                            maxLines: taglineMaxLines,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Lato',
                              fontSize: taglineFontSize,
                              color: AppColors.textTertiary,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Hero image — three-level fallback ─────────────────────────────────────────
// 1. heroImagePath  — local, assets/atmospheres/{id}.jpg
// 2. showcaseAsset  — local AI output (4 atmospheres have this)
// 3. fallbackImageUrl — Unsplash network (last resort)
// Shimmer placeholder while network loads; clean warm grey on complete failure.

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
    final showcase = atmosphere.showcaseAsset;
    final level2 = showcase != null
        ? _asset(showcase, onError: _net(atmosphere.fallbackImageUrl))
        : _net(atmosphere.fallbackImageUrl);
    return _asset(atmosphere.heroImagePath, onError: level2);
  }
}

// ── Floating icon ─────────────────────────────────────────────────────────────
// Diameter driven by AppAdaptive — scales with card height.
// Local PNG asset with Material icon fallback.

class _AtmosphereFloatingIcon extends StatelessWidget {
  final AtmosphereStyle atmosphere;
  final double diameter;
  const _AtmosphereFloatingIcon({
    required this.atmosphere,
    required this.diameter,
  });

  static const _bg = Color(0xFFFAF8F5);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _bg,
        border: Border.all(color: const Color(0xFFE0DCD6), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          atmosphere.iconImagePath,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(
            atmosphere.iconData,
            size: diameter * 0.50,
            color: const Color(0xFF8A8480),
          ),
        ),
      ),
    );
  }
}
