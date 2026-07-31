/// Batch 2.1 — official Ayden Studio logo widgets.
///
/// Uses the EXACT official raster (assets/branding/app_icon_1024_black.png —
/// gold compass + white AYDEN on black, verified byte-identical to the owner's
/// reference). Never redrawn, never re-typed as text, never re-vectorised.
/// Registered already via the assets/branding/ folder in pubspec.
library;

import 'package:flutter/material.dart';

import 'pwa_theme.dart';

/// The official brand raster (compass + white AYDEN on solid black). Used in the
/// compact dark header badge.
const String kAydenLogoOfficial = 'assets/branding/app_icon_1024_black.png';

/// Transparent hero logo DERIVED from the official raster (tool/gen_ayden_logo)
/// — the solid background made transparent, the mark itself untouched. Composits
/// cleanly over the cinematic room (no black square).
const String kAydenLogoHero = 'assets/branding/ayden_logo_hero.png';

/// Cinematic hero logo — the TRANSPARENT mark composited into the scene (not a
/// posed square). [reveal] (0→1) draws it in top→bottom through an architectural
/// mask with a soft gold glow — no bounce, no fake replacement mark.
class PwaHeroLogo extends StatelessWidget {
  const PwaHeroLogo({super.key, required this.reveal, this.size = 150});

  final double reveal; // 0..1
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = reveal.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft gold light behind the mark, growing with the reveal.
          Opacity(
            opacity: (r * 0.5).clamp(0.0, 0.5),
            child: Container(
              width: size * 0.9,
              height: size * 0.9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    pwaGold.withValues(alpha: 0.35),
                    pwaGold.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Architectural top→bottom wipe of the official logo.
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Colors.white, Colors.white, Colors.transparent],
              stops: [0.0, r, (r + 0.02).clamp(0.0, 1.0)],
            ).createShader(rect),
            child: Image.asset(
              kAydenLogoHero,
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact official mark for product headers (ivory surfaces): the official
/// logo shown inside a small dark rounded tile (its native black background),
/// so no substitute icon or text wordmark is invented.
class PwaLogoBadge extends StatelessWidget {
  const PwaLogoBadge({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.10),
      decoration: BoxDecoration(
        color: pwaBlack,
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: pwaGold.withValues(alpha: 0.35)),
      ),
      child: Image.asset(
        kAydenLogoOfficial,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}
