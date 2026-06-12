import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/l10n/app_localizations.dart';
import '../../shared/branding/ayden_brand.dart';

/// CHANTIER E (v2) — premium architectural splash, faithful to the AYDEN
/// "AFTER" reference: the light beige arch scene full-bleed, the gold compass
/// mark + a centred AYDEN · STUDIO wordmark, and a fine gold progress line with
/// "Designing your dream space…" near the bottom.
///
/// The backdrop is LIGHT, so the wordmark reads in dark ink (not white) and the
/// only scrim is a soft warm wash at the very bottom for loader legibility — the
/// luminous scene is otherwise left untouched.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;

  // Warm ivory — the canvas behind the photo (and the fallback if the backdrop
  // asset is ever missing).
  static const Color _ivory = Color(0xFFEDE4D8);

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
    final w = MediaQuery.sizeOf(context).width;

    final markSize = (w * 0.34).clamp(120.0, 150.0);
    final aydenSize = (w * 0.105).clamp(34.0, 44.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light backdrop ⇒ dark status-bar icons.
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _ivory,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Architectural backdrop (full-bleed, behind the status bar) ──
            Image.asset(
              'assets/images/splash/splash_background.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => const ColoredBox(color: _ivory),
            ),
            // ── Soft warm wash at the very bottom (loader legibility only) ──
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [Color(0x66100B06), Color(0x00100B06)],
                    stops: [0.0, 0.34],
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: _fadeAnim,
              child: SafeArea(
                child: Stack(
                  children: [
                    // ── Logo block — centred (vertically + horizontally) ──
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AydenMark(gold: true, size: markSize),
                          const SizedBox(height: 22),
                          _Wordmark(aydenSize: aydenSize),
                          const SizedBox(height: 20),
                          Text(
                            l10n.brandSignature.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.montserrat(
                              fontSize: 11,
                              letterSpacing: 3.2,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF8C7E66),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Loading — near the bottom, in brand gold ──
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 44),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const BrandProgressLine(width: 96),
                            const SizedBox(height: 16),
                            Text(
                              l10n.brandDesigningSpace,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                letterSpacing: 0.3,
                                color:
                                    AppColors.brandGold.withValues(alpha: 0.95),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AYDEN (dark ink) + STUDIO (gold, with a thin gold rule on each side), per the
/// reference. Kept local to the splash because the shared [AydenWordmark] has no
/// flanking rules and uses on-dark tones — this surface is light.
class _Wordmark extends StatelessWidget {
  final double aydenSize;
  const _Wordmark({required this.aydenSize});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'AYDEN',
          style: GoogleFonts.montserrat(
            color: AppColors.textPrimary,
            fontSize: aydenSize,
            fontWeight: FontWeight.w300,
            letterSpacing: aydenSize * 0.24,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _goldRule(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'STUDIO',
                style: GoogleFonts.montserrat(
                  color: AppColors.brandGold,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 6,
                ),
              ),
            ),
            _goldRule(),
          ],
        ),
      ],
    );
  }

  Widget _goldRule() => Container(
        width: 26,
        height: 1,
        color: AppColors.brandGold.withValues(alpha: 0.85),
      );
}
