import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/room_type_images.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/pending_generations_provider.dart';
import '../../core/providers/premium_provider.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../data/mock/mock_projects.dart';
import '../../data/models/message_model.dart';
import '../../data/models/project_model.dart';
import '../../data/services/generation_service.dart';
import '../../features/paywall/paywall_sheet.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dots.dart';
import '../../shared/widgets/app_pill.dart';
import '../../shared/widgets/reveal_hero.dart';
import '../../shared/widgets/sticky_action_bar.dart';
import 'home_adoption.dart';

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

  // Homepage in-flight reconcile — derive the card spinner from the BACKEND
  // (source of truth), not just the app-scoped RAM flag. A generation that
  // completes while the user is NOT in its chat leaves pendingGenerations=
  // inFlight forever (the chat's own reconcile was disposed), so the card would
  // spin indefinitely. This poller clears such STALE flags against the latest
  // Intent. It never SETS inFlight (that stays the chat's job) — it only clears.
  Timer? _pendingReconcileTimer;
  // Grace set: an id seen in-flight for the FIRST time is skipped one cycle, so
  // a just-started generation (whose Intent row the backend may not have written
  // yet → getLatestIntent would still return the PREVIOUS terminal Intent) is
  // never wrongly cleared. We only clear from the second observation on.
  final Set<String> _reconcileSeen = {};
  // One-shot : l'adoption de lancement (_deriveRecentFromBackend) doit tourner dès
  // que sessionProvider est peuplé. _load() est async → au post-frame la liste peut
  // être vide (early-return) ; un ref.listen relance alors la dérivation quand elle
  // se peuple. Ce flag garantit UNE seule dérivation de lancement (les ticks live
  // restent gérés par le poller _reconcilePending).
  bool _derivedOnce = false;
  // M-C : garde anti-intent-périmé. getLatestIntent renvoie le DERNIER intent par
  // created_at ; sur une re-génération, le nouvel intent RUNNING peut ne pas être
  // encore écrit → le poll verrait le terminal PRÉCÉDENT. On n'agit sur un markError
  // qu'après avoir observé RUNNING pour cette gen (adopt reste protégé par l'égalité
  // preview==after ; clearSpinner est bénin).
  final Set<String> _seenRunning = {};
  // Snackbar : true pendant la dérivation de lancement → on pose le badge "Ready"
  // sans empiler de toasts (ceux-ci sont réservés aux complétions live du poll).
  bool _derivingInitial = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // On (re)launch the RAM flags are gone → detect gens still RUNNING on the
      // backend whose flag was lost on kill, then reconcile stale ones.
      _deriveRecentFromBackend();
      _reconcilePending();
    });
    _pendingReconcileTimer = Timer.periodic(
        const Duration(seconds: 6), (_) => _reconcilePending());
  }

  @override
  void dispose() {
    _pendingReconcileTimer?.cancel();
    _entryController.dispose();
    super.dispose();
  }

  /// Clear STALE in-flight flags by deriving the truth from the latest Intent.
  /// Best-effort; only clears (never sets) inFlight. Runs while any session is
  /// flagged in-flight; a one-cycle grace avoids clearing a just-started gen.
  Future<void> _reconcilePending() async {
    if (!mounted) return;
    final pending = ref.read(pendingGenerationsProvider);
    final inFlightIds = <String>[
      for (final e in pending.entries)
        if (e.value == GenerationLifecycle.inFlight) e.key,
    ];
    // Stop tracking ids that are no longer in flight.
    _reconcileSeen.removeWhere((id) => !inFlightIds.contains(id));
    _seenRunning.removeWhere((id) => !inFlightIds.contains(id));
    if (inFlightIds.isEmpty) return;
    final svc = GenerationService();
    for (final id in inFlightIds) {
      // First observation → grace (skip one cycle) so the backend has time to
      // write a just-started generation's Intent row.
      if (_reconcileSeen.add(id)) continue;
      try {
        final probe = await svc.getLatestIntent(id);
        if (!mounted) return;
        // Mémorise avoir vu CETTE gen RUNNING (garde M-C ci-dessous).
        if (probe?['status'] == 'RUNNING') _seenRunning.add(id);
        // Fix "adopt completed generations" — une gen qui se termine hors-session
        // laisse sa donnée côté backend mais la carte garde son ancien preview.
        // Sur un terminal SUCCEEDED + after_image_url, on ADOPTE l'image (au lieu de
        // simplement nettoyer le spinner → la carte retombait sur la source).
        // RUNNING ou probe indisponible → on laisse le spinner. Décision pure +
        // applier I/O (mutualisé avec _deriveRecentFromBackend).
        final sessions = ref.read(sessionProvider);
        final idx = sessions.indexWhere((p) => p.id == id);
        final preview = idx >= 0 ? sessions[idx].afterImageUrl : null;
        final decision =
            decideHomeAdoption(probe: probe, currentPreview: preview);
        // M-C : ne pas poser un badge "Failed" sur un intent potentiellement PÉRIMÉ
        // (le terminal du dernier intent alors qu'une nouvelle gen démarre). On
        // exige d'avoir observé RUNNING pour cette gen avant d'agir sur markError.
        if (decision.action == HomeAdoptionAction.markError &&
            !_seenRunning.contains(id)) {
          continue;
        }
        _applyHomeAdoption(id, decision, inFlightContext: true);
      } catch (_) {
        // best-effort — a failed probe never clears a live spinner
      }
    }
  }

  /// Applique la décision d'adoption (I/O : état mémoire + DB). Mutualisé par les
  /// deux chemins. [inFlightContext] = true quand l'appel vient du poller de
  /// spinner (_reconcilePending) : on nettoie/mute le spinner ; false au lancement
  /// (_deriveRecentFromBackend) : on peut (re)poser un spinner RUNNING mais on ne
  /// (re)flague jamais une erreur/clear d'une vieille session à chaque lancement.
  void _applyHomeAdoption(String sessionId, HomeAdoptionDecision d,
      {required bool inFlightContext}) {
    if (!mounted) return;
    // Mutations d'état déléguées à la fonction libre TESTABLE (fige la couture).
    applyAdoptionToNotifiers(
      sessions: ref.read(sessionProvider.notifier),
      pending: ref.read(pendingGenerationsProvider.notifier),
      sessionId: sessionId,
      decision: d,
      inFlightContext: inFlightContext,
      currentLifecycle: ref.read(pendingGenerationsProvider)[sessionId],
    );
    if (d.action == HomeAdoptionAction.adopt) {
      debugPrint('[Home] adopted completed vision session=$sessionId');
    }
    // Grace-set : dès qu'un terminal est résolu, l'id n'a plus à être re-sondé.
    if (d.action == HomeAdoptionAction.adopt ||
        d.action == HomeAdoptionAction.markError ||
        d.action == HomeAdoptionAction.clearSpinner) {
      _reconcileSeen.remove(sessionId);
    }
  }

  /// On (re)launch, the RAM in-flight flags are gone — so a generation that was
  /// running when the app was KILLED leaves the homepage with NO spinner even
  /// though the gen is still going server-side. DERIVE the truth from the backend
  /// for the most recent sessions and re-mark inFlight the ones whose latest
  /// Intent is still RUNNING. Only SETS here (clearing stays in _reconcilePending);
  /// a RUNNING status is authoritative, so there is no false-positive risk.
  Future<void> _deriveRecentFromBackend() async {
    if (!mounted || _derivedOnce) return;
    final sessions = ref.read(sessionProvider);
    if (sessions.isEmpty) return; // pas encore chargées → relancé via ref.listen
    _derivedOnce = true;          // one-shot (pas de re-dérivation à chaque rebuild)
    _derivingInitial = true;      // #7 : badge "Ready" sans empiler de snackbars
    final recent = [...sessions]
      ..sort((a, b) => b.lastUpdatedAt.compareTo(a.lastUpdatedAt));
    // Deux populations à sonder au lancement (les flags RAM sont perdus) :
    //  • récemment actives (< 10 min) → détecter un intent RUNNING pour (re)poser le
    //    spinner (comportement historique) ;
    //  • SANS preview locale → candidates à une gen terminée hors-session : la donnée
    //    existe côté backend (image + message + result_ref) mais la carte retombe sur
    //    la source → ADOPTER. Couvre kill app / autre appareil / heures plus tard.
    // Borné à 6 probes → ~0 sur un lancement normal (les récentes ont déjà une
    // preview et sont donc ignorées).
    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    final svc = GenerationService();
    var probed = 0;
    try {
      for (final p in recent) {
        if (probed >= 6) break;
        final recentlyActive = p.lastUpdatedAt.isAfter(cutoff);
        final previewLess = (p.afterImageUrl ?? '').isEmpty;
        if (!recentlyActive && !previewLess) continue;
        probed++;
        try {
          final probe = await svc.getLatestIntent(p.id);
          if (!mounted) return;
          final decision =
              decideHomeAdoption(probe: probe, currentPreview: p.afterImageUrl);
          _applyHomeAdoption(p.id, decision, inFlightContext: false);
        } catch (_) {
          // best-effort
        }
      }
    } finally {
      _derivingInitial = false; // fin de la fenêtre "pas de snackbar"
    }
  }

  /// Wave 5.6c — toast/snackbar shown when a generation completes (or fails)
  /// while the user is on the home screen. Calm, brief, dismissible.
  void _showCompletionSnackBar(BuildContext context, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isError
              ? context.l10n.homeDesignFailed
              : context.l10n.homeDesignReady,
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
        // M-B / #7 : ne toaster QUE si l'accueil est la route visible (pas quand
        // l'utilisateur est dans le chat, derrière la route poussée) ET pas pendant
        // la dérivation de lancement (le badge sur la carte suffit ; évite les
        // toasts empilés / une snackbar sur un écran non regardé). Le badge, lui,
        // se met à jour dans tous les cas.
        final onHome = ModalRoute.of(context)?.isCurrent ?? false;
        if (!onHome || _derivingInitial) return;
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

    // Fix "adopt completed generations" — _load() est async : au post-frame la
    // liste de sessions peut être vide (→ la dérivation de lancement early-return).
    // Dès qu'elle se peuple, relancer UNE fois pour adopter une gen terminée
    // hors-session (ex. générée puis app fermée avant l'adoption).
    ref.listen<List<ProjectModel>>(sessionProvider, (prev, next) {
      if (!_derivedOnce && next.isNotEmpty) {
        _deriveRecentFromBackend();
      }
    });

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
            // CHANTIER F #18 — livelier, smoother Continue Designing scroll:
            // elastic bouncing physics (consistent iOS↔Android) instead of the
            // flat Android clamp. The page padding already peeks the next card.
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
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
        AppDots(
          count: featuredShowcase.length,
          index: _currentPage,
          // Tap a dot to jump to that showcase. animateToPage fires
          // onPageChanged, which updates the active dot AND resets the
          // auto-advance timer — same path as the timer itself.
          onDotTap: (i) => _pageController.animateToPage(
            i,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic,
          ),
        ),
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

    // CHANTIER D (premium pass) — full-bleed image + warm-dark cinematic scrim
    // + overlaid meta, mirroring the Redesigns ProjectCard so the home strip
    // and the Projects grid read as one consistent premium system (was: fixed
    // image band on top + flat text block below).
    // Display-only: localize the room via displayLabel (stored value stays EN).
    final title = project.roomType.isNotEmpty
        ? RoomTypeImages.displayLabel(context.l10n, project.roomType)
        : project.title;

    return _TapScaleWidget(
      onTap: () => context.push('/chat/${project.id}'),
      child: Container(
        width: 168,
        decoration: BoxDecoration(
          color: AppColors.shimmerBase,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Full-bleed preview ──
            if (previewUrl != null)
              CachedNetworkImage(
                imageUrl: previewUrl,
                memCacheWidth: 400, // startup perf — card is 168px wide; decode
                                    // at 400 instead of the 1536px source
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    const ColoredBox(color: AppColors.shimmerBase),
                errorWidget: (_, _, _) =>
                    const ColoredBox(color: AppColors.shimmerBase),
              )
            else
              const ColoredBox(
                color: AppColors.shimmerBase,
                child: Center(
                  child: Icon(Icons.image_outlined,
                      color: AppColors.textTertiary, size: 28),
                ),
              ),
            // ── Warm-dark cinematic scrim ──
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment(0, -0.05),
                    colors: [Color(0xE60C0906), Color(0x000C0906)],
                  ),
                ),
              ),
            ),
            // ── Pending generation badge (functional, unchanged) ──
            if (pendingState != null)
              Positioned(
                top: 8,
                right: 8,
                child: _PendingBadge(state: pendingState),
              ),
            // ── Overlaid meta ──
            Positioned(
              left: 11,
              right: 11,
              bottom: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                  if (project.style.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      project.style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
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
