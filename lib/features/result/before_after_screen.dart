import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/mock/mock_projects.dart';
import '../../data/models/message_model.dart';
import '../../core/layout/adaptive_layout.dart';
import '../../shared/widgets/atmosphere_card.dart';

class BeforeAfterScreen extends StatefulWidget {
  final String projectId;
  // GeneratedResult passed as Object? so the router doesn't need a direct import.
  final Object? resultExtra;
  const BeforeAfterScreen({super.key, required this.projectId, this.resultExtra});

  @override
  State<BeforeAfterScreen> createState() => _BeforeAfterScreenState();
}

class _BeforeAfterScreenState extends State<BeforeAfterScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;

  String? _beforeUrl;
  String? _afterUrl;
  String _title = '';
  String _subtitle = '';
  String? _selectedAtmosphere;

  double? _imageAspectRatio;
  ImageStream? _sizeStream;
  ImageStreamListener? _sizeListener;

  @override
  void initState() {
    super.initState();
    _entryController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
          ..forward();
    _fadeAnim = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);

    final extra = widget.resultExtra;
    if (extra is GeneratedResult) {
      final after = extra.afterImageUrl.isNotEmpty ? extra.afterImageUrl : null;
      final beforeRaw =
          extra.beforeImageUrl.isNotEmpty ? extra.beforeImageUrl : null;
      // Deterministic fallback rules — never a broken/empty/inconsistent
      // slider. The reveal is shown ONLY when there is a distinct before
      // image; otherwise it is intentionally hidden (single full-bleed
      // after image), which is the safe degraded state for legacy/corrupted
      // rows persisted before the per-step source fix.
      final before = (beforeRaw != null && beforeRaw != after) ? beforeRaw : null;
      final mode = before != null
          ? 'pair'
          : (beforeRaw == null ? 'fallback_no_source' : 'fallback_same_pair');
      debugPrint('[Reveal] full-reveal resolve — mode=$mode '
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
  }

  void _loadImageAspectRatio() {
    final url = _afterUrl;
    if (url == null || url.isEmpty) return;
    final ImageProvider provider = url.startsWith('assets/')
        ? AssetImage(url) as ImageProvider
        : NetworkImage(url);
    _sizeListener = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _imageAspectRatio = info.image.width / info.image.height);
      }
      _sizeStream?.removeListener(_sizeListener!);
    });
    _sizeStream = provider.resolve(ImageConfiguration.empty);
    _sizeStream!.addListener(_sizeListener!);
  }

  @override
  void dispose() {
    if (_sizeListener != null) _sizeStream?.removeListener(_sizeListener!);
    _entryController.dispose();
    super.dispose();
  }

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
              color: AppColors.surface.withAlpha(220),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, size: 18, color: AppColors.textPrimary),
          ),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.surface),
              ),
              if (_subtitle.isNotEmpty)
                Text(
                  _subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.surface.withAlpha(160),
                      ),
                ),
            ],
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final ratio = _imageAspectRatio;
                  if (ratio != null) {
                    final naturalH = constraints.maxWidth / ratio;
                    if (naturalH <= constraints.maxHeight) {
                      // Landscape / square: honour intrinsic ratio, centre vertically.
                      return Center(
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: naturalH,
                          child: _CompareView(beforeUrl: _beforeUrl, afterUrl: _afterUrl),
                        ),
                      );
                    }
                  }
                  // Portrait or ratio unknown: fill the available space.
                  return _CompareView(beforeUrl: _beforeUrl, afterUrl: _afterUrl);
                },
              ),
            ),
            Container(
              color: AppColors.textPrimary,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding, AppSpacing.md,
                      AppSpacing.pagePadding, 0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _DarkButton(
                            label: l10n.saveResult,
                            icon: Icons.bookmark_outline,
                            onPressed: () =>
                                _showSnack(context, 'Saved to your transformations.'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _DarkButton(
                            label: l10n.shareResult,
                            icon: Icons.ios_share,
                            filled: true,
                            onPressed: () => Share.share(
                              'Check out my AI home transformation — $_title!',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
                    child: Text(
                      'Explore another atmosphere',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.surface.withAlpha(140),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            letterSpacing: 0.4,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: AppAdaptive.revealStripHeight(screenH),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
                      itemCount: AppLocalizations.atmospheres.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final a = AppLocalizations.atmospheres[i];
                        return SizedBox(
                          width: AppAdaptive.revealCardWidth(screenH),
                          child: AtmosphereCard(
                            atmosphere: a,
                            selected: _selectedAtmosphere == a.name,
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
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.pagePadding, 10,
                              AppSpacing.pagePadding, 0,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => context.pop(_selectedAtmosphere),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: AppColors.surface,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  'Generate $_selectedAtmosphere',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(color: AppColors.surface),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  SizedBox(
                    height: AppSpacing.md + MediaQuery.of(context).padding.bottom,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.accentDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

// ── Compare view ──────────────────────────────────────────────────────────────

class _CompareView extends StatefulWidget {
  final String? beforeUrl;
  final String? afterUrl;
  const _CompareView({required this.beforeUrl, required this.afterUrl});

  @override
  State<_CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends State<_CompareView> with SingleTickerProviderStateMixin {
  // 0.30 = 70% "after" visible — AI result is the dominant first impression.
  double _sliderFraction = 0.30;
  bool _userHasInteracted = false;

  late final AnimationController _hintCtrl;
  late final Animation<double> _hintAnim;

  @override
  void initState() {
    super.initState();
    _hintCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    // Sweeps to 0.65 (shows more "before"), then reverses back to 0.30.
    _hintAnim = Tween<double>(begin: 0.30, end: 0.65)
        .animate(CurvedAnimation(parent: _hintCtrl, curve: Curves.easeInOutCubic));
    _hintAnim.addListener(() {
      if (mounted) setState(() => _sliderFraction = _hintAnim.value);
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && !_userHasInteracted) {
        _hintCtrl.forward().then((_) {
          if (mounted && !_userHasInteracted) _hintCtrl.reverse();
        });
      }
    });
  }

  @override
  void dispose() {
    _hintCtrl.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _hintCtrl.stop();
    _userHasInteracted = true;
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    final updated = _sliderFraction + details.delta.dx / width;
    setState(() => _sliderFraction = updated.clamp(0.02, 0.98));
  }

  @override
  Widget build(BuildContext context) {
    final hasBefore = widget.beforeUrl != null && widget.beforeUrl!.isNotEmpty;

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
              // After image — AI result (full-bleed base layer)
              _RevealImage(url: widget.afterUrl),

              // Before image — Positioned so StackFit.expand tight constraints
              // don't affect it; OverflowBox renders at full width inside the clip.
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
                      child: _RevealImage(url: widget.beforeUrl),
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
                  child: Container(color: Colors.white.withAlpha(220)),
                ),

              // Handle centred on divider
              if (hasBefore)
                Positioned(
                  left: sliderX - 20,
                  top: 0,
                  bottom: 0,
                  width: 40,
                  child: Center(
                    child: Container(
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
                    ),
                  ),
                ),

              // "Before" pill — top left. Generic on purpose: the before
              // image is the original upload for V1 but the previous vision
              // for V2+, so "Before" stays accurate across the whole chain.
              if (hasBefore)
                const Positioned(
                  top: 14,
                  left: 14,
                  child: _CompareLabel(text: 'Before'),
                ),

              // "AI Vision" pill — top right
              const Positioned(
                top: 14,
                right: 14,
                child: _CompareLabel(text: 'AI Vision', dark: true),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Image widget — handles local assets and network URLs ──────────────────────

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
        errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.shimmerBase),
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

// ── Overlay label pill ────────────────────────────────────────────────────────

class _CompareLabel extends StatelessWidget {
  final String text;
  final bool dark;
  const _CompareLabel({required this.text, this.dark = false});

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

// ── Dark action button ────────────────────────────────────────────────────────

class _DarkButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;
  const _DarkButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: filled ? AppColors.accent : AppColors.surface.withAlpha(15),
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          border: Border.all(
            color: filled ? AppColors.accent : AppColors.surface.withAlpha(40),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: filled ? AppColors.surface : AppColors.surface.withAlpha(200)),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: filled ? AppColors.surface : AppColors.surface.withAlpha(200),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
