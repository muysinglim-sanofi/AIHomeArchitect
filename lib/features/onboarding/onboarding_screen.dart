import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/feature_flags.dart';
import '../cards/card_catalog.dart';
import '../cards/widgets/atmosphere_hero_card.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive_layout.dart';
import '../../core/models/atmosphere_style.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/scrim.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dots.dart';
import '../../shared/widgets/app_pill.dart';
import '../../shared/widgets/atmosphere_card.dart';

// ── Wave 4.2 — FTUE Premium Rework ────────────────────────────────────────────
// First real screen migration. Consumes the Wave 4 spine (AppDots / AppPill /
// AppScrim / AppTheme editorial tokens) + AtmosphereCard V2. Image-led,
// full-bleed, calm editorial hierarchy. Removed: local `_Dot`, `_OverlayPill`,
// the two duplicated *SlideLayout widgets, the second "Skip" affordance, and
// inline gradient duplication. Asset paths UNCHANGED (asset-content is a
// separate creative deliverable). l10n titles/subtitles unchanged (translation
// files are out of scope); only in-file hard-coded microcopy was rewritten to
// a calmer architectural-editorial tone. No backend / routing / generation
// changes. Slide behaviour (auto-sweep, chat loop, atmosphere cycle) preserved
// verbatim; navigation stays CTA/dots-reliable.

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  static const _slideCount = 3;

  void _next() {
    if (_page < _slideCount - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
      );
    } else {
      context.go('/home');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isLast = _page == _slideCount - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar — quiet brand wordmark + single dismissal ────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding, AppSpacing.sm,
                AppSpacing.pagePadding, 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.appName.toUpperCase(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2.0,
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/home'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 0),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      l10n.skip,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

            // ── Slides ───────────────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _RevealSlide(
                      title: l10n.onboarding1Title,
                      subtitle: l10n.onboarding1Sub),
                  _ChatDemoSlide(
                      title: l10n.onboarding2Title,
                      subtitle: l10n.onboarding2Sub),
                  _AtmosphereExplorerSlide(
                      title: l10n.onboarding3Title,
                      subtitle: l10n.onboarding3Sub),
                ],
              ),
            ),

            // ── Bottom nav — reliable CTA + shared dots ──────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding, AppSpacing.md,
                AppSpacing.pagePadding, AppSpacing.xl,
              ),
              child: Column(
                children: [
                  AppDots(count: _slideCount, index: _page),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: isLast ? l10n.getStarted : l10n.continueLabel,
                    icon: isLast ? null : Icons.arrow_forward,
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared slide shell ────────────────────────────────────────────────────────
// One image-led layout (replaces the two duplicated *SlideLayout widgets):
// full-bleed responsive hero + a calm editorial text block. Defensive against
// small-device overflow via Flexible + ellipsis (validated SE→Max).

class _SlideShell extends StatelessWidget {
  final Widget hero;
  final String title;
  final String subtitle;
  const _SlideShell({
    required this.hero,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Hero sized from the slide's AVAILABLE height (not the full screen) so
        // the fixed hero + spacing + text never overflow the PageView on short
        // devices or with taller scripts (Khmer). Fixes the FTUE overflow stripe.
        final heroH = (constraints.maxHeight * 0.60).clamp(200.0, 470.0);
        return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.sm),
        // Full-bleed hero — image dominates; only the lower corners soften so
        // it reads as one immersive editorial plate, not a card in UI.
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppSpacing.radiusHero),
          ),
          child: SizedBox(
            height: heroH,
            width: double.infinity,
            child: hero,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Flexible(
          fit: FlexFit.loose,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.displayEditorial(
                    fontSize: 32,
                    fontWeight: FontWeight.w500,
                    height: 1.12,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.6,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
        );
      },
    );
  }
}

// ── Shared image helper — local asset → network fallback (kept) ───────────────
// There is no shared image primitive yet; keep this local helper. Asset paths
// are intentionally unchanged in this PR.

class _SpaceImage extends StatelessWidget {
  final String url;
  final String? networkFallback;

  const _SpaceImage({super.key, required this.url, this.networkFallback});

  static const _placeholder = Color(0xFFE8E5E0);

  Widget _net(String networkUrl) => CachedNetworkImage(
        imageUrl: networkUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, _) => const ColoredBox(color: _placeholder),
        errorWidget: (_, _, _) => const ColoredBox(color: _placeholder),
      );

  @override
  Widget build(BuildContext context) {
    final fallback = networkFallback != null
        ? _net(networkFallback!)
        : const ColoredBox(color: _placeholder);

    return Image.asset(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 1 — Cinematic reveal slider (mechanic preserved; presentation reworked)
// ─────────────────────────────────────────────────────────────────────────────

class _RevealSlide extends StatefulWidget {
  final String title;
  final String subtitle;
  const _RevealSlide({required this.title, required this.subtitle});

  @override
  State<_RevealSlide> createState() => _RevealSlideState();
}

class _RevealSlideState extends State<_RevealSlide>
    with SingleTickerProviderStateMixin {
  double _fraction = 0.12;
  bool _userInteracted = false;

  late final AnimationController _sweepCtrl;
  late final Animation<double> _sweepAnim;

  @override
  void initState() {
    super.initState();
    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _sweepAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.12, end: 0.75)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 50,
      ),
      TweenSequenceItem(tween: ConstantTween(0.75), weight: 12),
      TweenSequenceItem(
        tween: Tween(begin: 0.75, end: 0.42)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 38,
      ),
    ]).animate(_sweepCtrl);

    _sweepAnim.addListener(() {
      if (!_userInteracted && mounted) {
        setState(() => _fraction = _sweepAnim.value);
      }
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && !_userInteracted) _sweepCtrl.forward();
    });
  }

  @override
  void dispose() {
    _sweepCtrl.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _sweepCtrl.stop();
    _userInteracted = true;
  }

  void _onDragUpdate(DragUpdateDetails d, double width) {
    setState(() {
      _fraction = (_fraction + d.delta.dx / width).clamp(0.02, 0.98);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SlideShell(
      title: widget.title,
      subtitle: widget.subtitle,
      hero: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final divX = _fraction * width;

          return GestureDetector(
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const _SpaceImage(url: 'assets/showcase/facade_after.jpg'),
                Positioned(
                  left: 0, top: 0, bottom: 0,
                  width: divX,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: width,
                      maxWidth: width,
                      child: const _SpaceImage(
                          url: 'assets/showcase/facade_before.jpg'),
                    ),
                  ),
                ),
                // Calm top scrim — keeps the labels legible on any render
                // without darkening the architecture (shared AppScrim).
                const Positioned.fill(
                  child: AppScrim(
                    edge: ScrimEdge.top,
                    opacity: 0.26,
                    extent: 0.30,
                  ),
                ),
                Positioned(
                  left: divX - 1, top: 0, bottom: 0, width: 2,
                  child: Container(color: Colors.white.withValues(alpha: 0.9)),
                ),
                Positioned(
                  left: divX - 20, top: 0, bottom: 0, width: 40,
                  child: const Center(child: _RevealHandle()),
                ),
                Positioned(
                    top: 14, left: 14,
                    child: AppPill(text: context.l10n.ftueBefore)),
                Positioned(
                    top: 14, right: 14,
                    child: AppPill(text: context.l10n.ftueAiVision, dark: true)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Slider handle — shadowless (spine baseline); a clean ring, not a lifted chip.
class _RevealHandle extends StatelessWidget {
  const _RevealHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chevron_left, size: 14, color: Color(0xFF1A1A1A)),
          Icon(Icons.chevron_right, size: 14, color: Color(0xFF1A1A1A)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 2 — Conversational architect demo (loop preserved; presentation calmed)
// ─────────────────────────────────────────────────────────────────────────────

const _d1UserIn = 0;
const _d2AiIn = 900;
const _d3Spinner = 1900;
const _d4Image = 3100;
const _d6Clear = 6400;
const _d7Reset = 7200;

class _ChatDemoSlide extends StatefulWidget {
  final String title;
  final String subtitle;
  const _ChatDemoSlide({required this.title, required this.subtitle});

  @override
  State<_ChatDemoSlide> createState() => _ChatDemoSlideState();
}

class _ChatDemoSlideState extends State<_ChatDemoSlide> {
  bool _showAfter = false;
  bool _showUser = false;
  bool _showAi = false;
  bool _showSpinner = false;

  Timer? _t;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 600), _runLoop);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _at(int ms, VoidCallback fn) {
    _t = Timer(Duration(milliseconds: ms), () { if (mounted) fn(); });
  }

  void _runLoop() {
    setState(() {
      _showAfter = false; _showUser = false;
      _showAi = false; _showSpinner = false;
    });
    _at(_d1UserIn,  () => setState(() => _showUser = true));
    _at(_d2AiIn,    () => setState(() => _showAi = true));
    _at(_d3Spinner, () => setState(() => _showSpinner = true));
    _at(_d4Image,   () => setState(() { _showAfter = true; _showSpinner = false; }));
    _at(_d6Clear,   () => setState(() { _showUser = false; _showAi = false; }));
    _at(_d7Reset,   _runLoop);
  }

  @override
  Widget build(BuildContext context) {
    return _SlideShell(
      title: widget.title,
      subtitle: widget.subtitle,
      hero: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 750),
            child: _SpaceImage(
              key: ValueKey(_showAfter),
              url: _showAfter
                  ? 'assets/showcase/living_after.jpg'
                  : 'assets/showcase/living_before.jpg',
            ),
          ),
          // Calmer bottom scrim — the architecture leads; captions read over
          // a gentle gradient instead of a heavy 82% blackout.
          const Positioned.fill(
            child: AppScrim(
              edge: ScrimEdge.bottom,
              opacity: 0.5,
              extent: 0.6,
            ),
          ),
          Positioned(
            top: 14, left: 14,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: AppPill(
                key: ValueKey(_showAfter),
                text: _showAfter
                    ? context.l10n.ftueAfter
                    : context.l10n.ftueBefore,
              ),
            ),
          ),
          // Conversation as cinematic caption — two calm lines, no avatar
          // chrome, premium architectural tone.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CaptionLine(
                  text: context.l10n.ftueDemoUser,
                  isUser: true,
                  visible: _showUser,
                ),
                const SizedBox(height: 6),
                _CaptionLine(
                  text: context.l10n.ftueDemoAi,
                  isUser: false,
                  visible: _showAi,
                ),
                const SizedBox(height: 8),
                AnimatedOpacity(
                  opacity: _showSpinner ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.92),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusPill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 10, height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: AppColors.surface,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            context.l10n.ftueDemoRefining,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.surface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// A single conversational caption line — editorial, restrained, avatar-free.
class _CaptionLine extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool visible;
  const _CaptionLine({
    required this.text,
    required this.isUser,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isUser
                ? AppColors.surface.withValues(alpha: 0.92)
                : AppColors.textPrimary.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isUser ? AppColors.textPrimary : AppColors.surface,
                  fontSize: 12,
                  height: 1.4,
                ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 3 — Atmosphere explorer (consumes AtmosphereCard V2; editorial hero)
// ─────────────────────────────────────────────────────────────────────────────

class _AtmosphereExplorerSlide extends StatefulWidget {
  final String title;
  final String subtitle;
  const _AtmosphereExplorerSlide(
      {required this.title, required this.subtitle});

  @override
  State<_AtmosphereExplorerSlide> createState() =>
      _AtmosphereExplorerSlideState();
}

class _AtmosphereExplorerSlideState extends State<_AtmosphereExplorerSlide> {
  int _selected = 0;
  bool _userInteracted = false;
  Timer? _cycleTimer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), _startCycle);
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    super.dispose();
  }

  void _startCycle() {
    _cycleTimer?.cancel();
    _cycleTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!_userInteracted && mounted) {
        setState(() => _selected = (_selected + 1) % kAtmospheresOrdered.length);
      }
    });
  }

  void _select(int index) {
    _cycleTimer?.cancel();
    _userInteracted = true;
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final atm = kAtmospheresOrdered[_selected];
      final screenH = MediaQuery.sizeOf(context).height;

      // Wave 4.10j (FTUE 3 FINAL hero-dominance correction):
      //   Previous 4.10i still left hero/cards too balanced (304/180 on
      //   Pixel 6 = 47.5%/28% of PageView). User intent: hero must EMOTIONALLY
      //   dominate (55-60% of PageView region) and cards must feel like
      //   secondary preview strip, NOT a featured gallery.
      //
      //   Changes vs 4.10i:
      //     - Strip height: 190/180/155 → 130/120/110 (significant reduction)
      //       Cards now in AtmCardMode.semi (115-160), still above original
      //       FTUE compact mode (100) — premium feel preserved via taller
      //       images (63% ratio) and tagline visible (1 line).
      //     - Card width: 142/132/120 → 110/100/95 (smaller per the
      //       "cards SECONDARY" principle; 3-3.5 cards visible like a calm
      //       horizontal preview strip)
      //     - Hero ceiling: 0.62 → 0.65 (more room for cinematic dominance
      //       on tall devices)
      //     - Title reservation: 88 → 80 (1 tightening; preserves 2-line
      //       layout for "Infinite architectural\ndirections.")
      //     - Title spacings: preserved at 20-28 (per user spec — good)
      //
      //   Budget on Pixel 6 (~890 screen, ~640 avail):
      //     - reserved = 8 + 22 + 80 + 22 + 130 + 16 = 278
      //     - hero raw = 640 - 278 = 362 (vs 304 in 4.10i — +58px, +19%)
      //     - hero clamped to [168, 0.65*890=579] = 362
      //     - hero / avail = 56.6% ✓ in 55-60% target
      //     - hero / strip ratio = 362/130 = 2.78 (was 1.69) — hero
      //       emotionally dominant, not just numerically larger
      //
      //   Cards on Pixel 6 (110 wide × 130 tall, semi mode):
      //     - Image ratio 63% → image 110 × 82 (vertical 1.34)
      //     - Name 11px visible, tagline 1 line visible
      //     - 3.4 cards visible → calm horizontal preview, not gallery
      //     - Still LARGER than original FTUE (92×100, +60% surface)
      final viewportW = MediaQuery.sizeOf(context).width;

      // Strip height — significantly reduced to restore hero dominance.
      // AtmCardMode.semi (115-160) preserves tagline visibility while letting
      // hero own the upper half of the screen.
      final double stripHFinal;
      if (screenH >= 812) {
        stripHFinal = 130.0;
      } else if (screenH >= 700) {
        stripHFinal = 120.0;
      } else if (screenH >= 600) {
        stripHFinal = 110.0;
      } else {
        // Very small phone (SE 1st gen / 5s): keep AppAdaptive (90)
        stripHFinal = AppAdaptive.ftueCardStripHeight(screenH);
      }

      // Card width — sized so cards feel like calm preview strip, not
      // featured gallery cards. Aspect ratio with strip height stays
      // vertical (≈1.2-1.34) so cards still look editorial.
      //   Pixel 6 (412 viewport, 380 useful): 110 × 130 → ~3.4 cards visible
      //   iPhone 14 (393): 100 × 120 → ~3.4 cards visible
      //   Small Android (360): 95 × 110 → ~3.2 cards visible
      final double cardWFinal;
      if (viewportW >= 400) {
        cardWFinal = 110.0;
      } else if (viewportW >= 370) {
        cardWFinal = 100.0;
      } else if (viewportW >= 340) {
        cardWFinal = 95.0;
      } else {
        cardWFinal = AppAdaptive.ftueCardWidth(screenH);
      }

      // Spacings — order is Hero → Strip → Title (Wave 4.10k layout reorder).
      // Naming reflects the new sequence: heroToStripSpacing (above strip),
      // stripToTitleSpacing (above title).
      final heroToStripSpacing =
          AppAdaptive.ftueInnerSpacing(screenH).clamp(20.0, 28.0).toDouble();
      final stripToTitleSpacing =
          AppAdaptive.ftueTitleSpacing(screenH).clamp(20.0, 28.0).toDouble();

      // Title block reservation: 2-line title (~72) + sm gap (8) + 1-line
      // subtitle (~22) ≈ 102. Subtitle re-added Wave 4.10l as a calm gray
      // editorial tagline below the title (per user spec).
      const titleReserve = 102.0;
      final reserved = AppSpacing.sm +
          heroToStripSpacing +
          stripHFinal +
          stripToTitleSpacing +
          titleReserve +
          AppSpacing.md;
      final avail = constraints.maxHeight;
      final raw = avail.isFinite ? (avail - reserved) : (screenH * 0.52);
      // Wave 4.10k: hero ceiling at 0.70 (cinematic dominance on tall
      // devices, no measurable visual improvement at 0.80 on standard
      // phones — raw was already under the lower ceiling). Floor 168.
      final heroCeil = (screenH * 0.70) < 168.0 ? 168.0 : (screenH * 0.70);
      final heroH = raw.clamp(168.0, heroCeil).toDouble();

      return SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: AppSpacing.sm),

            // ── Editorial hero — full-bleed, name set in the atmosphere type ────
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppSpacing.radiusHero),
              ),
              child: SizedBox(
                height: heroH,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      child: _SpaceImage(
                        key: ValueKey(atm.id),
                        url: atm.ftueHeroImagePath,
                        networkFallback: atm.fallbackImageUrl,
                      ),
                    ),
                    const Positioned.fill(
                      child: AppScrim(
                        edge: ScrimEdge.bottom,
                        opacity: 0.6,
                        extent: 0.55,
                      ),
                    ),
                    Positioned(
                      left: 16, right: 16, bottom: 14,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Column(
                          key: ValueKey(atm.name),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              atm.name,
                              style: AppTheme.atmosphereTitle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: AppColors.surface,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.l10n.atmosphereTagline(atm.id),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.surface
                                        .withValues(alpha: 0.78),
                                    fontSize: 11,
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

            // ── Atmosphere strip — shared AtmosphereCard V2 ─────────────────
            // Wave 4.10k: order restored to Hero → Strip → Title. Cards now
            // sit directly under the hero as a calm horizontal preview strip;
            // the editorial title closes the slide at the bottom.
            SizedBox(height: heroToStripSpacing),
            SizedBox(
              height: stripHFinal,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pagePadding),
                itemCount: kAtmospheresOrdered.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final a = kAtmospheresOrdered[i];
                  return SizedBox(
                    width: cardWFinal,
                    child: FeatureFlags.newDesignCards
                        ? AtmosphereHeroCard(
                            compact: true,
                            name: a.name,
                            subtitle: context.l10n.atmosphereSubtitle(a.id),
                            asset: kAtmosphereCardById[a.id]?.asset ??
                                'assets/cards/atmospheres/${a.id}.png',
                            selected: _selected == i,
                            onTap: () => _select(i),
                          )
                        : AtmosphereCard(
                            atmosphere: a,
                            selected: _selected == i,
                            onTap: () => _select(i),
                          ),
                  );
                },
              ),
            ),

            // ── Editorial title + tagline — centered, closes the slide ──────
            // Wave 4.10k: title at the bottom under the strip.
            // Wave 4.10l: re-added subtitle ("Every atmosphere is a complete
            // redesign.") as a calm gray editorial tagline below the title
            // — smaller font, textSecondary color, classic editorial cadence.
            SizedBox(height: stripToTitleSpacing),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTheme.displayEditorial(
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      height: 1.12,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      );
    });
  }
}
