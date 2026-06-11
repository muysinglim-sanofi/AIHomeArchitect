/// Sprint 2A — AYDEN brand system (shared, reused across splash, generation
/// loading, and the paywall). All elements are TYPOGRAPHIC placeholders until
/// the real PNGs land in `assets/branding/` — swap the mark for an Image.asset
/// then; nothing else changes.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';

/// AYDEN · STUDIO typographic wordmark (Montserrat). `onDark` flips the AYDEN
/// tone for light vs dark surfaces; STUDIO is always brand gold.
class AydenWordmark extends StatelessWidget {
  final bool onDark;
  final double scale;
  const AydenWordmark({super.key, this.onDark = true, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final aydenColor =
        onDark ? Colors.white.withValues(alpha: 0.92) : AppColors.textPrimary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'AYDEN',
          style: GoogleFonts.montserrat(
            color: aydenColor,
            fontSize: 26 * scale,
            fontWeight: FontWeight.w300,
            letterSpacing: 9 * scale,
          ),
        ),
        SizedBox(height: 4 * scale),
        Text(
          'STUDIO',
          style: GoogleFonts.montserrat(
            color: AppColors.brandGold,
            fontSize: 11 * scale,
            fontWeight: FontWeight.w500,
            letterSpacing: 7 * scale,
          ),
        ),
      ],
    );
  }
}

/// AYDEN compass brand mark (real asset). `gold` picks the gold variant (dark
/// surfaces) vs the black variant (light surfaces). Falls back to a drafting
/// glyph if the asset is ever missing, so a packaging slip never crashes a
/// brand surface.
class AydenMark extends StatelessWidget {
  final double size;
  final bool gold;
  const AydenMark({super.key, this.size = 64, this.gold = true});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      gold
          ? 'assets/branding/ayden_compass_gold.png'
          : 'assets/branding/ayden_compass_black.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => Icon(
        Icons.architecture,
        size: size,
        color: gold ? AppColors.brandGold : AppColors.textPrimary,
      ),
    );
  }
}

/// Ultra-thin, slow, elegant gold progress line (indeterminate). Replaces any
/// circular/Cupertino spinner on brand surfaces. Very subtle by design.
class BrandProgressLine extends StatelessWidget {
  final double width;
  final Color? trackColor;
  const BrandProgressLine({super.key, this.width = 120, this.trackColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          minHeight: 2,
          backgroundColor:
              trackColor ?? AppColors.brandGold.withValues(alpha: 0.14),
          valueColor:
              AlwaysStoppedAnimation<Color>(AppColors.brandGold.withValues(alpha: 0.85)),
        ),
      ),
    );
  }
}
