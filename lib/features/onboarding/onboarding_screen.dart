import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive_layout.dart';
import '../../core/models/atmosphere_style.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/atmosphere_card.dart';

// ── Root screen ───────────────────────────────────────────────────────────────

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
            // ── Top bar ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding, AppSpacing.sm,
                AppSpacing.pagePadding, 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.appName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textTertiary,
                        ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/home'),
                    child: Text(
                      l10n.skip,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textTertiary),
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
                  _RevealSlide(title: l10n.onboarding1Title, subtitle: l10n.onboarding1Sub),
                  _ChatDemoSlide(title: l10n.onboarding2Title, subtitle: l10n.onboarding2Sub),
                  _AtmosphereExplorerSlide(title: l10n.onboarding3Title, subtitle: l10n.onboarding3Sub),
                ],
              ),
            ),

            // ── Bottom nav ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding, 0,
                AppSpacing.pagePadding, AppSpacing.xl,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slideCount,
                      (i) => _Dot(active: i == _page),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: isLast ? l10n.getStarted : l10n.continueLabel,
                    icon: isLast ? null : Icons.arrow_forward,
                    onPressed: _next,
                  ),
                  if (!isLast) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: () => context.go('/home'),
                      child: Text(
                        l10n.skipForNow,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dot indicator ─────────────────────────────────────────────────────────────

class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 24 : 7,
      height: 7,
      decoration: BoxDecoration(
        color: active ? AppColors.textPrimary : AppColors.border,
        borderRadius: BorderRadius.circular(50),
      ),
    );
  }
}

// ── Shared overlay pill ───────────────────────────────────────────────────────

class _OverlayPill extends StatelessWidget {
  final String text;
  final bool dark;
  const _OverlayPill({super.key, required this.text, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.textPrimary.withAlpha(200)
            : AppColors.surface.withAlpha(230),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: dark ? AppColors.surface : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
      ),
    );
  }
}

// ── Shared image helper — three-level fallback ────────────────────────────────
// 1. url            — primary local asset (e.g. assets/atmospheres/ftue/ftue_x.jpg)
// 2. secondaryAsset — optional secondary local asset (only used outside FTUE hero)
// 3. networkFallback — network URL (Unsplash) — last resort
// Shimmer shown while network loads; clean grey on full failure.
//
// IMPORTANT: The FTUE atmosphere hero (Screen 3) uses a TWO-level chain only:
//   ftueHeroImagePath → fallbackImageUrl (Unsplash)
// The showcaseAsset level is intentionally skipped for the FTUE hero — showcase
// assets show different spaces, which would violate the same-baseline-space
// transformation principle that is the core product proposition of Screen 3.

class _SpaceImage extends StatelessWidget {
  final String url;
  final String? networkFallback;

  const _SpaceImage({
    super.key,
    required this.url,
    this.networkFallback,
  });

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
// SCREEN 1 — Cinematic reveal slider
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
  // fraction: proportion of width showing the "before" (Original) on the left.
  // 0.0 = full AI Vision, 1.0 = full Original — matches _CompareView in before_after_screen.
  double _fraction = 0.12;
  bool _userInteracted = false;

  late final AnimationController _sweepCtrl;
  late final Animation<double> _sweepAnim;

  @override
  void initState() {
    super.initState();
    // Start mostly AI Vision (0.12) → reveal Original (0.75) → settle mid (0.42)
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
      TweenSequenceItem(
        tween: ConstantTween(0.75),
        weight: 12,
      ),
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

  // Matches _CompareView: dragging right increases fraction → reveals more Original.
  void _onDragUpdate(DragUpdateDetails d, double width) {
    setState(() {
      _fraction = (_fraction + d.delta.dx / width).clamp(0.02, 0.98);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _RevealSlideLayout(
      title: widget.title,
      subtitle: widget.subtitle,
      visual: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final divX = _fraction * width;

          return GestureDetector(
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // AI Vision — full base layer (right side dominant initially)
                const _SpaceImage(url: 'assets/showcase/smallspace_after.jpg'),

                // Original — clipped to divX pixels from the left
                Positioned(
                  left: 0, top: 0, bottom: 0,
                  width: divX,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: width,
                      maxWidth: width,
                      child: const _SpaceImage(
                        url: 'assets/showcase/smallspace_before.jpg',
                      ),
                    ),
                  ),
                ),

                // Divider line
                Positioned(
                  left: divX - 1, top: 0, bottom: 0, width: 2,
                  child: Container(color: Colors.white.withAlpha(230)),
                ),

                // Handle
                Positioned(
                  left: divX - 20, top: 0, bottom: 0, width: 40,
                  child: Center(
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(60),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chevron_left, size: 14, color: Color(0xFF1A1A1A)),
                          Icon(Icons.chevron_right, size: 14, color: Color(0xFF1A1A1A)),
                        ],
                      ),
                    ),
                  ),
                ),

                // Labels
                const Positioned(top: 12, left: 12, child: _OverlayPill(text: 'Original')),
                const Positioned(top: 12, right: 12, child: _OverlayPill(text: 'AI Vision', dark: true)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Separate layout widget so Screen 1 visual fills full width (no horizontal padding on visual).
class _RevealSlideLayout extends StatelessWidget {
  final Widget visual;
  final String title;
  final String subtitle;
  const _RevealSlideLayout({
    required this.visual,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius * 2),
            child: SizedBox(height: 300, width: double.infinity, child: visual),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(height: 1.15),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.65,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 2 — Conversational AI architect demo
// Uses villa_before → villa_after to show a REAL refinement of the same space.
// ─────────────────────────────────────────────────────────────────────────────

// Loop timing (ms)
const _d1UserIn  = 0;
const _d2AiIn    = 900;
const _d3Spinner = 1900;
const _d4Image   = 3100; // crossfade to "after"
const _d6Clear   = 6400; // fade bubbles
const _d7Reset   = 7200; // back to "before", restart

class _ChatDemoSlide extends StatefulWidget {
  final String title;
  final String subtitle;
  const _ChatDemoSlide({required this.title, required this.subtitle});

  @override
  State<_ChatDemoSlide> createState() => _ChatDemoSlideState();
}

class _ChatDemoSlideState extends State<_ChatDemoSlide> {
  bool _showAfter  = false;
  bool _showUser   = false;
  bool _showAi     = false;
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
    // Reset to "before" state
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
    return _ChatSlideLayout(
      title: widget.title,
      subtitle: widget.subtitle,
      visual: Stack(
        fit: StackFit.expand,
        children: [
          // Background crossfades between villa_before and villa_after
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 750),
            child: _SpaceImage(
              key: ValueKey(_showAfter),
              url: _showAfter
                  ? 'assets/showcase/villa_after.jpg'
                  : 'assets/showcase/villa_before.jpg',
            ),
          ),

          // Dark gradient — keeps bubbles readable over any image
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.textPrimary.withAlpha(210),
                ],
                stops: const [0.25, 1.0],
              ),
            ),
          ),

          // "Original Space" / "Refined Warm Version" label
          Positioned(
            top: 12, left: 12,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _OverlayPill(
                key: ValueKey(_showAfter),
                text: _showAfter ? 'Refined Warm Version' : 'Original Space',
              ),
            ),
          ),

          // Chat bubbles
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ChatBubble(
                  text: 'Make it warmer and more inviting.',
                  isUser: true,
                  visible: _showUser,
                ),
                const SizedBox(height: 6),
                _ChatBubble(
                  text: 'Preserving the structure while adding warm lighting, natural materials and a more inviting atmosphere.',
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(230),
                        borderRadius: BorderRadius.circular(50),
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
                            'Applying your vision…',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

class _ChatSlideLayout extends StatelessWidget {
  final Widget visual;
  final String title;
  final String subtitle;
  const _ChatSlideLayout({
    required this.visual,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius * 2),
            child: SizedBox(height: 300, width: double.infinity, child: visual),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(height: 1.15),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.65,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool visible;
  const _ChatBubble({
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isUser) ...[
              Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(
                  color: AppColors.textPrimary, shape: BoxShape.circle,
                ),
                child: const Icon(Icons.architecture, color: AppColors.background, size: 11),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.65,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isUser
                      ? AppColors.surface.withAlpha(235)
                      : AppColors.textPrimary.withAlpha(220),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(isUser ? 14 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 14),
                  ),
                ),
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isUser ? AppColors.textPrimary : AppColors.surface,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 3 — Atmosphere explorer
// Shows the SAME space (AI-generated architectural outputs) in multiple directions.
// Hero crossfades; cards auto-cycle. All images are real architectural outputs.
// ─────────────────────────────────────────────────────────────────────────────

class _AtmosphereExplorerSlide extends StatefulWidget {
  final String title;
  final String subtitle;
  const _AtmosphereExplorerSlide({required this.title, required this.subtitle});

  @override
  State<_AtmosphereExplorerSlide> createState() => _AtmosphereExplorerSlideState();
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
        setState(() => _selected = (_selected + 1) % kAtmospheres.length);
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
    final atm = kAtmospheres[_selected];
    final screenH = MediaQuery.sizeOf(context).height;
    final heroH = AppAdaptive.ftueHeroHeight(screenH);
    final stripH = AppAdaptive.ftueCardStripHeight(screenH);
    final cardW = AppAdaptive.ftueCardWidth(screenH);
    final innerSpacing = AppAdaptive.ftueInnerSpacing(screenH);
    final titleSpacing = AppAdaptive.ftueTitleSpacing(screenH);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),

        // ── Hero image ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius * 2),
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
                      // showcaseAsset excluded: shows different spaces —
                      // violates the same-baseline-space product principle.
                      networkFallback: atm.fallbackImageUrl,
                    ),
                  ),
                  // Bottom gradient + name overlay
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 40, 14, 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.textPrimary.withAlpha(210),
                          ],
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Column(
                          key: ValueKey(atm.name),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              atm.name,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: AppColors.surface,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            Text(
                              atm.tagline,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.surface.withAlpha(175),
                                    fontSize: 11,
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
          ),
        ),

        SizedBox(height: innerSpacing),

        // ── Atmosphere card strip ─────────────────────────────────────────────
        SizedBox(
          height: stripH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
            itemCount: kAtmospheres.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final a = kAtmospheres[i];
              return SizedBox(
                width: cardW,
                child: AtmosphereCard(
                  atmosphere: a,
                  selected: _selected == i,
                  onTap: () => _select(i),
                ),
              );
            },
          ),
        ),

        SizedBox(height: titleSpacing),

        // ── Title + subtitle ──────────────────────────────────────────────────
        // Flexible(loose): takes whatever space remains after fixed children;
        // prevents parent Column overflow on small screens (e.g. iPhone SE).
        Flexible(
          fit: FlexFit.loose,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(height: 1.15),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  widget.subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.65,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

