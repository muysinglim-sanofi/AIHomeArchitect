import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/session_provider.dart';
import '../../data/mock/mock_projects.dart';
import '../../data/models/message_model.dart';
import '../../data/models/project_model.dart';
import '../../shared/widgets/app_button.dart';

String _timeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  return '${diff.inDays}d ago';
}

String? _latestVisionUrl(ProjectModel project) {
  for (final msg in project.messages.reversed) {
    if (msg.type == MessageType.imageResult && msg.result != null) {
      return msg.result!.afterImageUrl;
    }
  }
  return project.afterImageUrl ?? project.beforeImageUrl;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  String _greeting(AppLocalizations l10n) {
    final h = DateTime.now().hour;
    if (h < 12) return l10n.homeGreetingMorning;
    if (h < 18) return l10n.homeGreetingAfternoon;
    return l10n.homeGreetingEvening;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context, l10n)),
                SliverToBoxAdapter(child: _buildHeroSection(context, l10n)),
                SliverToBoxAdapter(child: _buildContinueSection(context, l10n)),
                SliverToBoxAdapter(child: _buildCTA(context, l10n)),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.lg,
        AppSpacing.pagePadding,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _CategoryPill(label: l10n.homeCategoryInterior),
                const SizedBox(width: 6),
                _CategoryPill(label: l10n.homeCategoryExterior),
              ],
            ),
          ),
          _SessionsBadge(onTap: () => context.push('/sessions')),
        ],
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.lg,
        AppSpacing.pagePadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _greeting(l10n),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.homeHeadline,
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  height: 1.1,
                  letterSpacing: -1.5,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.homeSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _HeroCarousel(),
        ],
      ),
    );
  }

  Widget _buildCTA(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.lg,
        AppSpacing.pagePadding,
        0,
      ),
      child: AppButton(
        label: l10n.newDesignSession,
        icon: Icons.add,
        onPressed: () => context.push('/upload'),
      ),
    );
  }

  Widget _buildContinueSection(BuildContext context, AppLocalizations l10n) {
    final sessions = ref.watch(sessionProvider);
    if (sessions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.xl,
            AppSpacing.pagePadding,
            AppSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.continueDesigning, style: Theme.of(context).textTheme.titleLarge),
              GestureDetector(
                onTap: () => context.go('/projects'),
                child: Text(
                  l10n.seeAll,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 185,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _ContinueCard(project: sessions[index]),
          ),
        ),
      ],
    );
  }
}

// ── Hero carousel ─────────────────────────────────────────────────────────────

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel();

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      final next = (_currentPage + 1) % featuredShowcase.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: featuredShowcase.length,
              onPageChanged: (i) {
                _timer?.cancel();
                setState(() => _currentPage = i);
                _startTimer();
              },
              itemBuilder: (_, index) => _HeroSlide(
                key: ValueKey(featuredShowcase[index].id),
                project: featuredShowcase[index],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            featuredShowcase.length,
            (i) => _HeroProgressDot(active: i == _currentPage),
          ),
        ),
      ],
    );
  }
}

class _HeroProgressDot extends StatelessWidget {
  final bool active;
  const _HeroProgressDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: active ? 20 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? AppColors.textPrimary : AppColors.border,
        borderRadius: BorderRadius.circular(50),
      ),
    );
  }
}

// ── Hero slide ────────────────────────────────────────────────────────────────

class _HeroSlide extends StatefulWidget {
  final ProjectModel project;
  const _HeroSlide({super.key, required this.project});

  @override
  State<_HeroSlide> createState() => _HeroSlideState();
}

class _HeroSlideState extends State<_HeroSlide>
    with SingleTickerProviderStateMixin {
  // Fraction of the slide occupied by the "before" image on the left.
  // 0.30 = 70% after visible — AI result is the dominant first impression.
  double _sliderFraction = 0.30;
  bool _userHasInteracted = false;

  late final AnimationController _hintCtrl;
  late final Animation<double> _hintAnim;

  @override
  void initState() {
    super.initState();
    _hintCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    // Sweeps to 0.65 (revealing more "before"), then reverses back to 0.30.
    // Users see: the AI result → the original → back to the AI result.
    _hintAnim = Tween<double>(begin: 0.30, end: 0.65)
        .animate(CurvedAnimation(parent: _hintCtrl, curve: Curves.easeInOutCubic));
    _hintAnim.addListener(_onHintTick);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && !_userHasInteracted) {
        debugPrint('[Slider] hint start — before=${widget.project.beforeImageUrl} '
            'after=${widget.project.afterImageUrl} '
            'same=${widget.project.beforeImageUrl == widget.project.afterImageUrl}');
        _hintCtrl.forward().then((_) {
          if (mounted && !_userHasInteracted) _hintCtrl.reverse();
        });
      }
    });
  }

  void _onHintTick() {
    if (mounted) setState(() => _sliderFraction = _hintAnim.value);
  }

  @override
  void dispose() {
    _hintAnim.removeListener(_onHintTick);
    _hintCtrl.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    if (!_userHasInteracted) {
      _hintCtrl.stop();
      _userHasInteracted = true;
    }
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    final updated = _sliderFraction + details.delta.dx / width;
    final clamped = updated.clamp(0.02, 0.98);
    debugPrint('[Slider] drag: fraction=${clamped.toStringAsFixed(3)} '
        'clipPx=${(clamped * width).toStringAsFixed(0)}/${width.toStringAsFixed(0)}');
    setState(() => _sliderFraction = clamped);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasBefore = widget.project.beforeImageUrl != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final sliderX = _sliderFraction * width;

        return GestureDetector(
          onHorizontalDragStart: hasBefore ? _onDragStart : null,
          onHorizontalDragUpdate: hasBefore ? (d) => _onDragUpdate(d, width) : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // After image — full-bleed background (AI-designed result)
              _ShowcaseImage(path: widget.project.afterImageUrl ?? widget.project.beforeImageUrl),

              // Before image — Positioned so StackFit.expand doesn't impose tight
              // constraints, then OverflowBox lets the image render at full width
              // so ClipRect reveals only the left sliderX pixels.
              if (hasBefore)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: sliderX,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: width,
                      maxWidth: width,
                      child: _ShowcaseImage(path: widget.project.beforeImageUrl),
                    ),
                  ),
                ),

              // Subtle top/bottom vignette
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.textPrimary.withAlpha(50),
                        Colors.transparent,
                        AppColors.textPrimary.withAlpha(60),
                      ],
                      stops: const [0.0, 0.38, 1.0],
                    ),
                  ),
                ),
              ),

              // Divider line
              if (hasBefore)
                Positioned(
                  left: sliderX - 1,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: Container(
                    color: Colors.white.withAlpha(220),
                    foregroundDecoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(30),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),

              // Drag handle centred on the divider
              if (hasBefore)
                Positioned(
                  left: sliderX - 20,
                  top: 0,
                  bottom: 0,
                  width: 40,
                  child: const Center(child: _CompareHandle()),
                ),

              // "Original" pill — top left
              if (hasBefore)
                const Positioned(
                  top: 14,
                  left: 14,
                  child: _SlideLabel(text: 'Original'),
                ),

              // Style / AI vision pill — top right
              Positioned(
                top: 14,
                right: 14,
                child: _SlideLabel(text: widget.project.style, dark: true),
              ),

              // Bottom gradient bar — title only, style already shown above
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 36, 14, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        AppColors.textPrimary.withAlpha(210),
                        AppColors.textPrimary.withAlpha(80),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.featuredVision,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.surface.withAlpha(160),
                              letterSpacing: 0.3,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.project.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppColors.surface,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Compare handle ────────────────────────────────────────────────────────────

class _CompareHandle extends StatelessWidget {
  const _CompareHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(55),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chevron_left, size: 15, color: Color(0xFF1A1A1A)),
          Icon(Icons.chevron_right, size: 15, color: Color(0xFF1A1A1A)),
        ],
      ),
    );
  }
}

// ── Slide label ───────────────────────────────────────────────────────────────

class _SlideLabel extends StatelessWidget {
  final String text;
  final bool dark;
  const _SlideLabel({required this.text, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.textPrimary.withAlpha(190)
            : AppColors.surface.withAlpha(220),
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

// ── Continue card ─────────────────────────────────────────────────────────────

class _ContinueCard extends StatelessWidget {
  final ProjectModel project;
  const _ContinueCard({required this.project});

  @override
  Widget build(BuildContext context) {
    final previewUrl = _latestVisionUrl(project);
    final l10n = context.l10n;
    return _TapScaleWidget(
      onTap: () => context.push('/chat/${project.id}'),
      child: Container(
        width: 158,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 108,
              width: double.infinity,
              child: previewUrl != null
                  ? CachedNetworkImage(
                      imageUrl: previewUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: AppColors.shimmerBase),
                      errorWidget: (_, _, _) => Container(color: AppColors.shimmerBase),
                    )
                  : Container(color: AppColors.shimmerBase),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    project.style,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_timeAgo(project.lastUpdatedAt)} · ${l10n.visionCount(project.iterationCount)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 10,
                        ),
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

// ── Small components ──────────────────────────────────────────────────────────

class _CategoryPill extends StatelessWidget {
  final String label;
  const _CategoryPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
      ),
    );
  }
}

class _SessionsBadge extends StatelessWidget {
  final VoidCallback onTap;
  const _SessionsBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accentLight,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 14, color: AppColors.accentDark),
            const SizedBox(width: 5),
            Text(
              '5',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.accentDark,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}


class _ShowcaseImage extends StatelessWidget {
  final String? path;
  const _ShowcaseImage({this.path});

  @override
  Widget build(BuildContext context) {
    if (path == null) return const ColoredBox(color: AppColors.shimmerBase);
    return Image.asset(
      path!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.shimmerBase),
    );
  }
}

class _TapScaleWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _TapScaleWidget({required this.child, required this.onTap});

  @override
  State<_TapScaleWidget> createState() => _TapScaleWidgetState();
}

class _TapScaleWidgetState extends State<_TapScaleWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
