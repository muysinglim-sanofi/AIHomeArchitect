import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../data/mock/mock_projects.dart';
import '../../data/models/message_model.dart';
import '../../data/models/project_model.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dots.dart';
import '../../shared/widgets/app_pill.dart';
import '../../shared/widgets/reveal_hero.dart';
import '../../shared/widgets/sticky_action_bar.dart';

// ── Wave 4.1 — Homepage UX Optimization ───────────────────────────────────────
// Image-led, calm, action-forward. Consumes the Wave 4 spine (RevealHero /
// StickyActionBar / AppDots / AppPill / editorial type). Fixes the two P0s:
// (1) image is now the visual lead (compact editorial header above a prominent
//     RevealHero carousel — not a 40px headline dominating a small 16:9 card);
// (2) the primary CTA is a persistent StickyActionBar that sits ABOVE the
//     MainShell bottom nav and can never fall below the fold.
// Removed local: _HeroSlide, _CompareHandle, _SlideLabel, _HeroProgressDot,
// _CategoryPill (non-interactive), _SessionsBadge (gamified). No backend /
// routing / sessionProvider / generation changes.

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

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
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
        .animate(CurvedAnimation(
            parent: _entryController, curve: Curves.easeOutCubic));
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
        child: Column(
          children: [
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeader(context, l10n)),
                      SliverToBoxAdapter(
                          child: _buildHeroSection(context, l10n)),
                      SliverToBoxAdapter(
                          child: _buildContinueSection(context, l10n)),
                      const SliverToBoxAdapter(
                          child: SizedBox(height: AppSpacing.lg)),
                    ],
                  ),
                ),
              ),
            ),
            // Persistent CTA — sits directly above the MainShell bottom nav.
            // removeBottom strips the duplicate safe-area inset (MainShell's
            // nav already provides it) so there is no gap / overlap.
            MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: StickyActionBar(
                primary: AppButton(
                  label: l10n.newDesignSession,
                  icon: Icons.add,
                  onPressed: () => context.push('/upload'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Thin, calm top bar — gamified sparkle badge replaced by a quiet credits
  // pill that PRESERVES the /sessions navigation. Non-interactive Interior/
  // Exterior pills removed (they did nothing).
  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.md,
        AppSpacing.pagePadding,
        0,
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
          AppPill(
            text: '5 credits',
            onTap: () => context.push('/sessions'),
          ),
        ],
      ),
    );
  }

  // Compact editorial header → prominent image-led hero. The 40px display
  // headline is reduced to a calm editorial line and the marketing subtitle
  // is dropped (less vertical waste); the transformation is now the lead.
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.displayEditorial(
              fontSize: 27,
              fontWeight: FontWeight.w500,
              height: 1.12,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _HeroCarousel(),
        ],
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
              Text(l10n.continueDesigning,
                  style: Theme.of(context).textTheme.titleLarge),
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
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pagePadding),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) =>
                _ContinueCard(project: sessions[index]),
          ),
        ),
      ],
    );
  }
}

// ── Hero carousel — multi-item wrapper; each page is a shared RevealHero ───────

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
    final heroH =
        (MediaQuery.sizeOf(context).height * 0.42).clamp(260.0, 460.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusHero),
          child: SizedBox(
            height: heroH,
            width: double.infinity,
            child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: featuredShowcase.length,
              onPageChanged: (i) {
                _timer?.cancel();
                setState(() => _currentPage = i);
                _startTimer();
              },
              itemBuilder: (_, index) {
                final p = featuredShowcase[index];
                return RevealHero(
                  key: ValueKey(p.id),
                  afterImage: _ShowcaseImage(
                      path: p.afterImageUrl ?? p.beforeImageUrl),
                  beforeImage: p.beforeImageUrl != null
                      ? _ShowcaseImage(path: p.beforeImageUrl)
                      : null,
                  initialFraction: 0.30,
                  autoSweep: true,
                  dragMode: RevealDragMode.handle,
                  beforeLabel: 'Original',
                  afterLabel: p.style,
                  overlay: _HeroOverlay(title: p.title, label: context.l10n.featuredVision),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        AppDots(count: featuredShowcase.length, index: _currentPage),
      ],
    );
  }
}

// Editorial caption for the hero — title + small eyebrow over the scrim.
class _HeroOverlay extends StatelessWidget {
  final String title;
  final String label;
  const _HeroOverlay({required this.title, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 36, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.surface.withValues(alpha: 0.65),
                  letterSpacing: 0.3,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.atmosphereTitle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: AppColors.surface,
              height: 1.1,
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
    // "0 visions" reads as a broken/empty session — show a calm "Draft"
    // instead. (The real session-naming/version surfacing is Wave 4.7.)
    final meta = project.iterationCount > 0
        ? '${_timeAgo(project.lastUpdatedAt)} · ${l10n.visionCount(project.iterationCount)}'
        : '${_timeAgo(project.lastUpdatedAt)} · Draft';

    return _TapScaleWidget(
      onTap: () => context.push('/chat/${project.id}'),
      child: Container(
        width: 168,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 124,
              width: double.infinity,
              child: previewUrl != null
                  ? CachedNetworkImage(
                      imageUrl: previewUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: AppColors.shimmerBase),
                      errorWidget: (_, _, _) =>
                          Container(color: AppColors.shimmerBase),
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
                    meta,
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

// ── Local helpers (kept) ──────────────────────────────────────────────────────

class _ShowcaseImage extends StatelessWidget {
  final String? path;
  const _ShowcaseImage({this.path});

  @override
  Widget build(BuildContext context) {
    if (path == null) return const ColoredBox(color: AppColors.shimmerBase);
    return Image.asset(
      path!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
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
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
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
