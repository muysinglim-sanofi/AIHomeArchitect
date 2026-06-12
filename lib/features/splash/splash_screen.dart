import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/l10n/app_localizations.dart';
import '../../shared/branding/ayden_brand.dart';

/// CHANTIER E — premium architectural splash. A warm, full-bleed architectural
/// backdrop with a warm-depth scrim, the gold compass-house mark + white AYDEN ·
/// gold STUDIO wordmark slightly above centre, and a gold progress line with the
/// "Designing your dream space…" line in brand gold around the lower third.
/// (Was an empty ivory canvas — too flat / not premium.)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;

  // Warm near-black — the canvas behind the photo (and the fallback if the
  // backdrop asset is ever missing). Matches the native launch screen colour.
  static const Color _warmDark = Color(0xFF1A1512);

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

    final markSize = (w * 0.30).clamp(108.0, 168.0);

    return Scaffold(
      backgroundColor: _warmDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Warm architectural backdrop (full-bleed, behind the status bar).
          // Swap for a dedicated splash background asset later if desired.
          Image.asset(
            'assets/showcase/living_after.jpg',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => const ColoredBox(color: _warmDark),
          ),
          // ── Warm-depth scrim: darker at top & bottom for legibility, soft in
          // the middle so the room keeps its light and atmosphere.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xD9140F09), // warm dark top
                  Color(0x59140F09), // soft middle (room breathes)
                  Color(0xF2100B06), // deep warm bottom
                ],
                stops: [0.0, 0.44, 1.0],
              ),
            ),
          ),
          FadeTransition(
            opacity: _fadeAnim,
            child: SafeArea(
              child: Stack(
                children: [
                  // ── Logo block — slightly above centre ──
                  Positioned(
                    top: h * 0.27,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        AydenMark(gold: true, size: markSize),
                        const SizedBox(height: 20),
                        const AydenWordmark(onDark: true, scale: 1.12),
                        const SizedBox(height: 22),
                        Text(
                          l10n.brandSignature.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(
                            fontSize: 11,
                            letterSpacing: 3.4,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.58),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Loading — lower third, in brand gold ──
                  Positioned(
                    top: h * 0.79,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        const BrandProgressLine(width: 96),
                        const SizedBox(height: 16),
                        Text(
                          l10n.brandDesigningSpace,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            letterSpacing: 0.3,
                            color: AppColors.brandGold.withValues(alpha: 0.92),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
