import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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

double _heroHeight(BuildContext context) {
  final h = MediaQuery.sizeOf(context).height;
  return (h * 0.50).clamp(240.0, 470.0);
}

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
            height: _heroHeight(context),
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
                const _SpaceImage(url: 'assets/showcase/smallspace_after.jpg'),
                Positioned(
                  left: 0, top: 0, bottom: 0,
                  width: divX,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: width,
                      maxWidth: width,
                      child: const _SpaceImage(
                          url: 'assets/showcase/smallspace_before.jpg'),
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
                const Positioned(
                    top: 14, left: 14, child: AppPill(text: 'Before')),
                const Positioned(
                    top: 14, right: 14,
                    child: AppPill(text: 'AI Vision', dark: true)),
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
                  ? 'assets/showcase/villa_after.jpg'
                  : 'assets/showcase/villa_before.jpg',
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
                text: _showAfter ? 'After' : 'Before',
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
                  text: 'A little warmer. A little calmer.',
                  isUser: true,
                  visible: _showUser,
                ),
                const SizedBox(height: 6),
                _CaptionLine(
                  text: 'Same architecture — warmer light, softer materials.',
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
                            'Refining the space…',
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
                          atm.tagline,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color:
                                    AppColors.surface.withValues(alpha: 0.78),
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

        SizedBox(height: innerSpacing),

        // ── Atmosphere strip — shared AtmosphereCard V2 ─────────────────────
        SizedBox(
          height: stripH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pagePadding),
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

        // ── Title + subtitle — editorial display token ──────────────────────
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
                  widget.title,
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
                  widget.subtitle,
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
  }
}
