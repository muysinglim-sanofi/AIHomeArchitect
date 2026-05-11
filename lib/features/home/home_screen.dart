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
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
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
              itemCount: featuredShowcase.length,
              onPageChanged: (i) {
                _timer?.cancel();
                setState(() => _currentPage = i);
                _startTimer();
              },
              itemBuilder: (_, index) => _HeroSlide(
                project: featuredShowcase[index],
                isAiSlide: index == 0,
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
  final bool isAiSlide;
  const _HeroSlide({required this.project, this.isAiSlide = false});

  @override
  State<_HeroSlide> createState() => _HeroSlideState();
}

class _HeroSlideState extends State<_HeroSlide> with TickerProviderStateMixin {
  late final AnimationController _revealController;
  late final Animation<double> _revealAnim;
  late final AnimationController _zoomController;
  late final Animation<double> _zoomAnim;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _revealAnim = Tween<double>(begin: 1.0, end: 0.33).animate(
      CurvedAnimation(
        parent: _revealController,
        curve: const Interval(0.15, 1.0, curve: Curves.easeInOutCubic),
      ),
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _revealController.forward();
    });

    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
    _zoomAnim = Tween<double>(begin: 1.0, end: 1.05)
        .animate(CurvedAnimation(parent: _zoomController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _revealController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _TapScaleWidget(
      onTap: () => context.push('/result/${widget.project.id}'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _revealAnim,
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                AnimatedBuilder(
                  animation: _zoomAnim,
                  builder: (_, child) =>
                      Transform.scale(scale: _zoomAnim.value, child: child),
                  child: _NetImage(
                    url: widget.project.afterImageUrl ?? widget.project.beforeImageUrl,
                  ),
                ),
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: _revealAnim.value,
                    child: _NetImage(url: widget.project.beforeImageUrl),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: _RevealLabel(text: l10n.beforeLabel),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: _RevealLabel(text: l10n.afterLabel, dark: true),
          ),
          if (widget.isAiSlide) Positioned.fill(child: _AiThinkingOverlay()),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 32, 14, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppColors.textPrimary.withAlpha(230),
                    AppColors.textPrimary.withAlpha(100),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withAlpha(25),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: AppColors.surface.withAlpha(50)),
                    ),
                    child: Text(
                      widget.project.style,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.surface,
                            fontWeight: FontWeight.w500,
                          ),
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

// ── AI thinking overlay (slide 0 only) ───────────────────────────────────────

class _AiThinkingOverlay extends StatefulWidget {
  @override
  State<_AiThinkingOverlay> createState() => _AiThinkingOverlayState();
}

class _AiThinkingOverlayState extends State<_AiThinkingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _userFade;
  late final Animation<double> _aiFade;
  late final Animation<double> _genFade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _userFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
    );
    _aiFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.33, 0.6, curve: Curves.easeOut),
    );
    _genFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
    );
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 58),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FadeTransition(
            opacity: _userFade,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface.withAlpha(230),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  'Warm natural materials, tropical feel',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                      ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FadeTransition(
            opacity: _aiFade,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withAlpha(210),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(14),
                  ),
                ),
                child: Text(
                  'Exploring textures and evening atmosphere…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.surface,
                        fontSize: 11,
                      ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          FadeTransition(
            opacity: _genFade,
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
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.surface,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Generating your vision…',
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

class _RevealLabel extends StatelessWidget {
  final String text;
  final bool dark;
  const _RevealLabel({required this.text, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.textPrimary.withAlpha(200)
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

class _NetImage extends StatelessWidget {
  final String? url;
  const _NetImage({this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null) return Container(color: AppColors.shimmerBase);
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(color: AppColors.shimmerBase),
      errorWidget: (_, _, _) => Container(color: AppColors.shimmerBase),
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
