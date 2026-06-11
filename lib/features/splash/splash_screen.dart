import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/l10n/app_localizations.dart';
import '../../shared/branding/ayden_brand.dart';

/// Sprint 2A — calm, premium, architectural splash. Warm-ivory canvas, the full
/// AYDEN logo sitting slightly above centre, a close subtitle, and an ultra-thin
/// gold progress line around the lower third. No spinner, no gradients.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) context.go('/onboarding');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    // Clean logo (compass + AYDEN + STUDIO only — assistant row & sub-icons
    // cropped out), halo-trimmed so it fills the box → reads large.
    final logoWidth = (w * 0.64).clamp(215.0, 340.0);
    final logoTop = h * 0.30;
    final loadingTop = h * 0.79;

    return Scaffold(
      backgroundColor: AppColors.brandIvory,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Stack(
            children: [
              // ── Logo block — larger, slightly above centre ──
              Positioned(
                top: logoTop,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Image.asset(
                      'assets/branding/ayden_logo_gold_studio.png',
                      width: logoWidth,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      // Clean typographic fallback if the PNG is missing.
                      errorBuilder: (_, _, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AydenMark(gold: true, size: logoWidth * 0.5),
                          const SizedBox(height: 18),
                          const AydenWordmark(onDark: false),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      l10n.brandSignature.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.montserrat(
                        fontSize: 11,
                        letterSpacing: 3.2,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Loading — around the lower third (connected, not bottom) ──
              Positioned(
                top: loadingTop,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    const BrandProgressLine(width: 78),
                    const SizedBox(height: 16),
                    Text(
                      l10n.brandDesigningSpace,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textSecondary.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
