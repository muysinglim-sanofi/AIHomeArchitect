import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/session_provider.dart';
import '../../data/mock/mock_projects.dart';
import '../../data/models/message_model.dart';
import '../../core/layout/adaptive_layout.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_pill.dart';
import '../../shared/widgets/atmosphere_card.dart';
import '../../shared/widgets/reveal_canvas.dart';
import '../../shared/widgets/reveal_hero.dart';

// ── Wave 4.5 + 4.4 — Hybrid Reveal V2 + Fullscreen Cinematic Viewer ───────────
// The emotional-climax migration. The local compare (_CompareView) is replaced
// by the shared RevealHero inside the immersive RevealCanvas (ambient backdrop
// kills the letterbox-void P0). Adds hold-to-original (long-press) and a
// cinematic immersive tap-toggle (controls fade → pure image → tap back).
// Gestures are separated by recognizer + region so nothing traps.
//
// Preserved verbatim (non-regression): the wave-4.8.3 reveal-source
// resolution + fallback + debug log; _loadImageAspectRatio (now feeds
// RevealCanvas.focalAspectRatio); the context.pop(_selectedAtmosphere)
// contract chat depends on; Save (no-op snackbar — making it real is Wave
// 4.9, out of scope); Share (real); back navigation; mock/featured fallback.
// No backend / routing / session / generation changes.

class BeforeAfterScreen extends ConsumerStatefulWidget {
  final String projectId;
  // GeneratedResult passed as Object? so the router doesn't need a direct import.
  final Object? resultExtra;
  const BeforeAfterScreen(
      {super.key, required this.projectId, this.resultExtra});

  @override
  ConsumerState<BeforeAfterScreen> createState() => _BeforeAfterScreenState();
}

class _BeforeAfterScreenState extends ConsumerState<BeforeAfterScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;

  String? _beforeUrl;
  String? _afterUrl;
  String _title = '';
  String _subtitle = '';
  String? _selectedAtmosphere;

  // Cinematic immersive mode (controls fade away → pure image). Hybrid: tap
  // toggles; back is always reachable (AppBar leading chip stays).
  bool _immersive = false;
  // While the user holds, the original is shown full-bleed (temporary
  // override — NOT a second compare system).
  bool _holdingOriginal = false;

  double? _imageAspectRatio;
  ImageStream? _sizeStream;
  ImageStreamListener? _sizeListener;

  // Wave 4.10e (#2): the ORIGINAL's own intrinsic ratio, resolved
  // independently of the generated image's ratio, for the hold-to-original
  // overlay (true photographed proportions, not a cover-cropped expansion).
  double? _beforeAspectRatio;
  ImageStream? _beforeSizeStream;
  ImageStreamListener? _beforeSizeListener;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);

    final extra = widget.resultExtra;
    if (extra is GeneratedResult) {
      final after = extra.afterImageUrl.isNotEmpty ? extra.afterImageUrl : null;
      final beforeRaw =
          extra.beforeImageUrl.isNotEmpty ? extra.beforeImageUrl : null;
      // Wave 4.10e (#3, P0): the reveal "original" must ALWAYS be the very
      // first user-uploaded photo — never the previous generated vision that
      // chat's V2/V3 chaining passes as extra.beforeImageUrl. The initial
      // upload is held immutably on the session row (ProjectModel
      // .beforeImageUrl — set once at createSession, never mutated). Resolve
      // it authoritatively by projectId; fall back to extra.beforeImageUrl
      // ONLY when there is no session match / it is null (featured · mock ·
      // deep-link · legacy · no persisted upload). The generation source
      // (_afterUrl) is untouched — generation may keep chaining from the
      // latest vision; reveal-original vs generation-source are different
      // concepts.
      final sessionOriginal = _sessionOriginalUrl();
      final originalCandidate = sessionOriginal ?? beforeRaw;
      // Deterministic fallback rules — never a broken/empty/inconsistent
      // slider. The reveal is shown ONLY when there is a distinct original
      // image; otherwise it is intentionally hidden (single full-bleed
      // after image), the safe degraded state for legacy/corrupted rows.
      final before = (originalCandidate != null && originalCandidate != after)
          ? originalCandidate
          : null;
      final src = sessionOriginal != null ? 'session' : 'extra';
      final mode = before != null
          ? 'pair'
          : (originalCandidate == null
              ? 'fallback_no_source'
              : 'fallback_same_pair');
      debugPrint('[Reveal] full-reveal resolve — mode=$mode src=$src '
          'before=$before after=$after');
      _beforeUrl = before;
      _afterUrl = after;
      _title = extra.styleLabel;
      _subtitle = '';
    } else {
      // Fallback: mock / featured data (showcase usage)
      final project = widget.projectId.startsWith('featured')
          ? featuredShowcase.firstWhere(
              (p) => p.id == widget.projectId,
              orElse: () => featuredShowcase.first,
            )
          : mockProjects.firstWhere(
              (p) => p.id == widget.projectId,
              orElse: () => mockProjects.first,
            );
      _beforeUrl = project.beforeImageUrl;
      _afterUrl = project.afterImageUrl;
      _title = project.title;
      _subtitle = '${project.style} · ${project.roomType}';
    }
    _loadImageAspectRatio();
    _loadBeforeAspectRatio();
  }

  // Wave 4.10e (#3): authoritative initial-upload URL for this project from
  // session state. ProjectModel.beforeImageUrl is set once at createSession
  // and never mutated (only afterImageUrl/title/messages change), so it is a
  // reliable source of the very first uploaded photo. Null ⇒ the caller
  // falls back to the GeneratedResult's before (featured · mock · deep-link ·
  // legacy · session with no persisted upload) — an honest fallback, never a
  // fabricated original.
  String? _sessionOriginalUrl() {
    for (final p in ref.read(sessionProvider)) {
      if (p.id == widget.projectId) {
        final b = p.beforeImageUrl;
        return (b != null && b.isNotEmpty) ? b : null;
      }
    }
    return null;
  }

  // Wave 4.10e (#2): resolve the ORIGINAL's true intrinsic ratio using the
  // exact same mechanism as _loadImageAspectRatio for the generated image,
  // so the hold-to-original overlay shows the real photographed proportions
  // (landscape stays landscape, portrait stays portrait) instead of a
  // cover-cropped vertical expansion.
  void _loadBeforeAspectRatio() {
    final url = _beforeUrl;
    if (url == null || url.isEmpty) return;
    final ImageProvider provider = url.startsWith('assets/')
        ? AssetImage(url) as ImageProvider
        : CachedNetworkImageProvider(url);
    _beforeSizeListener = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() =>
            _beforeAspectRatio = info.image.width / info.image.height);
      }
      _beforeSizeStream?.removeListener(_beforeSizeListener!);
    });
    _beforeSizeStream = provider.resolve(ImageConfiguration.empty);
    _beforeSizeStream!.addListener(_beforeSizeListener!);
  }

  void _loadImageAspectRatio() {
    final url = _afterUrl;
    if (url == null || url.isEmpty) return;
    // Wave 4.10b (#5): resolve the ratio from the SAME cached provider the
    // RevealHero/RevealCanvas actually display (CachedNetworkImage), not a
    // separate NetworkImage. This makes _imageAspectRatio resolve reliably
    // and quickly → RevealCanvas centres at the true ratio (no forced
    // portrait crop of landscape renders), with a single decode.
    final ImageProvider provider = url.startsWith('assets/')
        ? AssetImage(url) as ImageProvider
        : CachedNetworkImageProvider(url);
    _sizeListener = ImageStreamListener((info, _) {
      if (mounted) {
        setState(
            () => _imageAspectRatio = info.image.width / info.image.height);
      }
      _sizeStream?.removeListener(_sizeListener!);
    });
    _sizeStream = provider.resolve(ImageConfiguration.empty);
    _sizeStream!.addListener(_sizeListener!);
  }

  @override
  void dispose() {
    if (_sizeListener != null) _sizeStream?.removeListener(_sizeListener!);
    if (_beforeSizeListener != null) {
      _beforeSizeStream?.removeListener(_beforeSizeListener!);
    }
    _entryController.dispose();
    super.dispose();
  }

  // Ambient backdrop provider — same image the focal after-image uses, so it
  // decodes once (shared cache) per RevealCanvas guidance.
  ImageProvider? get _ambientProvider {
    final url = _afterUrl;
    if (url == null || url.isEmpty) return null;
    return url.startsWith('assets/')
        ? AssetImage(url)
        : CachedNetworkImageProvider(url);
  }

  bool get _hasBefore => _beforeUrl != null && _beforeUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenH = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: AppColors.textPrimary,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.86),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back,
                size: 18, color: AppColors.textPrimary),
          ),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        // Title hidden in immersive mode so the image fully dominates.
        title: _immersive
            ? null
            : FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: AppColors.surface),
                    ),
                    if (_subtitle.isNotEmpty)
                      Text(
                        _subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.surface.withValues(alpha: 0.62),
                            ),
                      ),
                  ],
                ),
              ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RevealCanvas(
              ambientImage: _ambientProvider,
              // Centres the result at its intrinsic ratio over the ambient
              // backdrop — eliminates the black letterbox void (e.g. a
              // landscape render on a portrait phone). Null while loading →
              // RevealHero fills (still no void: ink + ambient base).
              focalAspectRatio: _imageAspectRatio,
              topScrim: true,
              bottomScrim: !_immersive,
              // Softer than the 0.6/0.5 default: tighten the gradient toward
              // the bottom edge (where the controls actually sit) so a dim
              // evening render is no longer murky through its lower half,
              // while the controls keep enough backing for legibility.
              bottomScrimOpacity: 0.55,
              bottomScrimExtent: 0.38,
              bottomOverlay:
                  _immersive ? null : _buildControls(context, l10n, screenH),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Tap toggles cinematic immersive mode.
                onTap: () => setState(() => _immersive = !_immersive),
                // Hold = temporary original override (only if a before exists).
                onLongPressStart: _hasBefore
                    ? (_) => setState(() => _holdingOriginal = true)
                    : null,
                onLongPressEnd: _hasBefore
                    ? (_) => setState(() => _holdingOriginal = false)
                    : null,
                child: RevealHero(
                  afterImage: _RevealImage(url: _afterUrl),
                  beforeImage:
                      _hasBefore ? _RevealImage(url: _beforeUrl) : null,
                  initialFraction: 0.30,
                  autoSweep: true,
                  // handle-mode: drag is confined to the handle strip, so the
                  // surface tap/long-press never conflicts with the compare.
                  dragMode: RevealDragMode.handle,
                  beforeLabel: _immersive ? null : 'Before',
                  afterLabel: _immersive ? null : 'AI Vision',
                  showLabels: !_immersive,
                ),
              ),
            ),

            // Hold-to-original overlay — fades in over everything while held.
            // IgnorePointer so it never disturbs the active long-press.
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _holdingOriginal ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: _holdingOriginal
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: AppColors.textPrimary),
                          // Wave 4.10e (#2): the ORIGINAL is shown at its true
                          // photographed proportions, centred over the
                          // intentional ink base (RevealCanvas's ink-base
                          // philosophy — never a harsh void). No forced
                          // vertical/cover expansion. Falls back to the prior
                          // cover fill until the intrinsic ratio resolves, so
                          // the overlay is never blank. The RevealHero compare
                          // wipe is intentionally NOT changed (shared-frame
                          // honest comparison — confirmed decision A).
                          Center(
                            child: _beforeAspectRatio != null
                                ? AspectRatio(
                                    aspectRatio: _beforeAspectRatio!,
                                    child: _RevealImage(url: _beforeUrl),
                                  )
                                : _RevealImage(url: _beforeUrl),
                          ),
                          const Positioned(
                            top: 60,
                            left: 16,
                            child: AppPill(text: 'Original'),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Calm, secondary controls — actions no longer compete with the image.
  Widget _buildControls(
      BuildContext context, AppLocalizations l10n, double screenH) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.md,
        AppSpacing.pagePadding,
        AppSpacing.md + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wave 4.10b (#6): make the hold-to-original gesture discoverable —
          // a calm hint (only when a distinct original exists).
          if (_hasBefore) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_outlined,
                    size: 13,
                    color: AppColors.surface.withValues(alpha: 0.55)),
                const SizedBox(width: 6),
                Text(
                  'Press & hold to see the original',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.surface.withValues(alpha: 0.55),
                        fontSize: 11,
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          // Secondary action — a single real, quiet pill. The no-op Save
          // affordance was removed (no storage backend — Wave-4.9 parity);
          // no dead premium actions remain.
          Row(
            children: [
              AppPill(
                text: l10n.shareResult,
                icon: Icons.ios_share,
                dark: true,
                onTap: () => Share.share(
                  'Check out my AI home transformation — $_title!',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Explore another direction',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.surface.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.4,
                ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: AppAdaptive.revealStripHeight(screenH),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.zero,
              itemCount: AppLocalizations.atmospheres.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final a = AppLocalizations.atmospheres[i];
                return SizedBox(
                  width: AppAdaptive.revealCardWidth(screenH),
                  child: AtmosphereCard(
                    atmosphere: a,
                    selected: _selectedAtmosphere == a.name,
                    dark: true,
                    onTap: () => setState(() {
                      _selectedAtmosphere =
                          _selectedAtmosphere == a.name ? null : a.name;
                    }),
                  ),
                );
              },
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: _selectedAtmosphere != null
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: AppButton(
                      label: 'Generate $_selectedAtmosphere',
                      variant: AppButtonVariant.accent,
                      // Contract preserved: chat awaits this pop value and
                      // triggers _exploreDirection(selectedStyle).
                      onPressed: () => context.pop(_selectedAtmosphere),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

}

// ── Image widget — handles local assets and network URLs (kept) ───────────────

class _RevealImage extends StatelessWidget {
  final String? url;
  const _RevealImage({this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const ColoredBox(color: AppColors.shimmerBase);
    }
    if (url!.startsWith('assets/')) {
      return Image.asset(
        url!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) =>
            const ColoredBox(color: AppColors.shimmerBase),
      );
    }
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, _) => const ColoredBox(color: AppColors.shimmerBase),
      errorWidget: (_, _, _) => const ColoredBox(color: AppColors.shimmerBase),
    );
  }
}
