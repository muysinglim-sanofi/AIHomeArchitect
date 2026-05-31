import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/pending_generations_provider.dart';
import '../../core/providers/premium_provider.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../data/mock/mock_projects.dart';
import '../../data/models/message_model.dart';
import '../../data/models/project_model.dart';
import '../../features/paywall/paywall_sheet.dart';
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

  /// Wave 5.6c — toast/snackbar shown when a generation completes (or fails)
  /// while the user is on the home screen. Calm, brief, dismissible.
  void _showCompletionSnackBar(BuildContext context, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isError
              ? 'A design generation failed — tap the session to see details.'
              : 'A design is ready — tap the session to view it.',
        ),
        backgroundColor:
            isError ? AppColors.error : AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Wave 5.6c — surface a snackbar transition when a generation completes
    // while the user is on the home screen. The badge on the session card
    // is the persistent visual; the snackbar is the immediate audible/
    // visible "your design is ready" beat.
    ref.listen<Map<String, GenerationLifecycle>>(
      pendingGenerationsProvider,
      (previous, next) {
        if (!mounted) return;
        for (final entry in next.entries) {
          final prevState = previous?[entry.key];
          final newState = entry.value;
          if (prevState == newState) continue;
          // Only fire for transitions INTO readyUnseen / errorUnseen
          // (i.e. completion). Don't fire on initial markInFlight.
          if (newState == GenerationLifecycle.readyUnseen &&
              prevState != GenerationLifecycle.readyUnseen) {
            _showCompletionSnackBar(context, isError: false);
          } else if (newState == GenerationLifecycle.errorUnseen &&
              prevState != GenerationLifecycle.errorUnseen) {
            _showCompletionSnackBar(context, isError: true);
          }
        }
      },
    );

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

  // Thin, calm top bar — Wave 5.17d.1 replaces the legacy "5 credits" pill
  // (which navigated to the now-removed BuySessionsScreen credit-pack
  // paywall) with a Premium-aware affordance :
  //   • Free users → gold "Premium" pill that opens PaywallSheet directly
  //   • Premium users → calm gold "Premium ✓" badge, non-routing
  // Non-interactive Interior/Exterior pills removed long ago.
  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final isPremium = ref.watch(premiumProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Flexible + ellipsis: the trailing controls grew (intro replay +
          // premium pill), so guard the wordmark against narrow devices /
          // long localized app names / large text scale (no row overflow).
          Flexible(
            child: Text(
              l10n.appName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Calm return-to-intro affordance — re-enters the FTUE
              // (route already exists; no router change). Quiet ghost
              // icon, never competes with the premium pill.
              _IntroReplayButton(
                onTap: () => context.push('/onboarding'),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (isPremium)
                const _PremiumActiveBadge()
              else
                AppPill(
                  text: 'Premium',
                  onTap: () => _openHomePaywall(context),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Wave 5.17d.1 — open the single canonical PaywallSheet from the home
  /// header. `PaywallTrigger.locked` keeps the copy generic (the user
  /// hasn't hit any specific lock yet — they tapped Premium directly).
  Future<void> _openHomePaywall(BuildContext context) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PaywallSheet(
        trigger: PaywallTrigger.locked,
      ),
    );
  }

  // Wave 4.10g (#1): vertical compression. The generic "Good afternoon"
  // greeting is removed entirely (SaaS-feel, zero emotional value, wasted
  // viewport); top spacing is tightened (header→headline lg→md, headline→
  // hero lg→md) so the editorial headline + image-led hero begin
  // significantly higher and the Continue Designing title clears the fold.
  Widget _buildHeroSection(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.md,
        AppSpacing.pagePadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(height: AppSpacing.md),
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
          // Wave 4.10g (#1): xl→lg so the Continue Designing title clears
          // the fold on standard viewports (still calm breathing, not dead
          // space).
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.lg,
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
          height: 214,
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
    // Wave 4.10g (#1): 0.42→0.45 — the hero is slightly more emotionally
    // dominant. The reclaimed top space (removed greeting + tightened
    // paddings) more than offsets this, so the Continue Designing title
    // still clears the fold and there is no overflow (CustomScrollView).
    final heroH =
        (MediaQuery.sizeOf(context).height * 0.45).clamp(260.0, 460.0);
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

class _ContinueCard extends ConsumerWidget {
  final ProjectModel project;
  const _ContinueCard({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewUrl = _latestVisionUrl(project);
    // "0 visions" reads as a broken/empty session — show a calm "Draft"
    // instead. Wave 4.7: progression-forward, real data only.
    // Wave 4.7: lead with real progression so the card reads as an evolving
    // architectural project over time (no fabricated naming — real
    // iterationCount + timestamp only).
    final meta = project.iterationCount > 0
        ? 'Vision ${project.iterationCount} · ${_timeAgo(project.lastUpdatedAt)}'
        : 'Draft · ${_timeAgo(project.lastUpdatedAt)}';

    // Wave 5.6c — watch the pending generations provider for this session
    // and surface a small badge on the image band if the session has a
    // result the user hasn't seen yet (inFlight, readyUnseen, errorUnseen).
    final pendingState = ref.watch(
      pendingGenerationsProvider.select((m) => m[project.id]),
    );

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
        // Fixed image band + flexible text region. The text sits in an
        // Expanded so the card total height is pinned to the strip height
        // (214) regardless of font scaling — no vertical overflow, no
        // clipped/hidden text (each line keeps maxLines + ellipsis).
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 120,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  previewUrl != null
                      ? CachedNetworkImage(
                          imageUrl: previewUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              Container(color: AppColors.shimmerBase),
                          errorWidget: (_, _, _) =>
                              Container(color: AppColors.shimmerBase),
                        )
                      : Container(color: AppColors.shimmerBase),
                  if (pendingState != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _PendingBadge(state: pendingState),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.title,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          project.style,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    Text(
                      meta,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

// Wave 5.6c — small badge rendered on the session card image band when a
// generation is in flight (or finished while the user was off-screen).
// Three visual states match the GenerationLifecycle enum:
//   inFlight     — small spinner dot ("generation still running")
//   readyUnseen  — accent dot ("result ready to view")
//   errorUnseen  — error dot ("failed; tap to see")
class _PendingBadge extends StatelessWidget {
  final GenerationLifecycle state;
  const _PendingBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case GenerationLifecycle.inFlight:
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withAlpha(200),
            shape: BoxShape.circle,
          ),
          child: const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.surface),
            ),
          ),
        );
      case GenerationLifecycle.readyUnseen:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 10, color: AppColors.surface),
              SizedBox(width: 4),
              Text(
                'Ready',
                style: TextStyle(
                  color: AppColors.surface,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      case GenerationLifecycle.errorUnseen:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.error,
            borderRadius: BorderRadius.circular(50),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 10, color: AppColors.surface),
              SizedBox(width: 4),
              Text(
                'Failed',
                style: TextStyle(
                  color: AppColors.surface,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
    }
  }
}

// Quiet "replay the intro" affordance. A bordered ghost icon (matches the
// calm AppPill language) — discoverable but never loud. Returns the user to
// the existing /onboarding route; no routing changes.
class _IntroReplayButton extends StatelessWidget {
  final VoidCallback onTap;
  const _IntroReplayButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Replay introduction',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(
            Icons.auto_stories_outlined,
            size: 17,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// Wave 5.17d.1 — Premium-active badge shown in the home header in place
// of the "Premium" CTA pill when the user already has an active premium
// entitlement. Non-interactive : the user already paid, no further
// action is needed from this surface (subscription management goes
// through the platform store, not through the app's chrome).
class _PremiumActiveBadge extends StatelessWidget {
  const _PremiumActiveBadge();

  static const _gold = Color(0xFFD6A85F);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _gold.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check_circle, color: _gold, size: 13),
          SizedBox(width: 5),
          Text(
            'Premium',
            style: TextStyle(
              color: _gold,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
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
