import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/mock/mock_projects.dart';
import '../../data/models/project_model.dart';

class BeforeAfterScreen extends StatefulWidget {
  final String projectId;
  const BeforeAfterScreen({super.key, required this.projectId});

  @override
  State<BeforeAfterScreen> createState() => _BeforeAfterScreenState();
}

class _BeforeAfterScreenState extends State<BeforeAfterScreen> with TickerProviderStateMixin {
  double _sliderValue = 0.5;

  late final AnimationController _entryController;
  late final AnimationController _revealController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _revealAnim;

  late final ProjectModel project;

  @override
  void initState() {
    super.initState();
    project = widget.projectId.startsWith('featured')
        ? featuredShowcase.firstWhere(
            (p) => p.id == widget.projectId,
            orElse: () => featuredShowcase.first,
          )
        : mockProjects.firstWhere(
            (p) => p.id == widget.projectId,
            orElse: () => mockProjects.first,
          );

    _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);

    _revealController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _revealAnim = Tween<double>(begin: 1.0, end: 0.5).animate(
      CurvedAnimation(parent: _revealController, curve: Curves.easeInOutCubic),
    );

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _revealController.forward().then((_) {
          if (mounted) setState(() => _sliderValue = 0.5);
        });
      }
    });

    _revealController.addListener(() {
      if (mounted) setState(() => _sliderValue = _revealAnim.value);
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
                project.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.surface),
              ),
              Text(
                '${project.style} · ${project.roomType}',
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
              child: _CompareView(project: project, slider: _sliderValue),
            ),
            Container(
              color: AppColors.textPrimary,
              padding: const EdgeInsets.fromLTRB(AppSpacing.pagePadding, AppSpacing.md, AppSpacing.pagePadding, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      _RevealLabel(text: l10n.beforeLabel, visible: _sliderValue > 0.15),
                      const Spacer(),
                      _RevealLabel(text: l10n.afterLabel, dark: false, visible: _sliderValue < 0.95),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      thumbColor: AppColors.surface,
                      activeTrackColor: AppColors.surface.withAlpha(80),
                      inactiveTrackColor: AppColors.surface.withAlpha(30),
                      overlayColor: AppColors.surface.withAlpha(20),
                      trackHeight: 2,
                    ),
                    child: Slider(
                      value: _sliderValue,
                      onChanged: (v) => setState(() => _sliderValue = v),
                    ),
                  ),
                  Text(
                    l10n.dragToReveal,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.surface.withAlpha(100),
                          fontSize: 11,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
            Container(
              color: AppColors.textPrimary,
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                0,
                AppSpacing.pagePadding,
                AppSpacing.md + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _DarkButton(
                          label: l10n.saveResult,
                          icon: Icons.bookmark_outline,
                          onPressed: () => _showSnack(context, 'Saved to your transformations.'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _DarkButton(
                          label: l10n.shareResult,
                          icon: Icons.ios_share,
                          filled: true,
                          onPressed: () => Share.share(
                            'Check out my AI home transformation — ${project.roomType} in ${project.style} style!',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: Text(
                      '↺  ${l10n.newVariation}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.surface.withAlpha(140),
                          ),
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

class _CompareView extends StatelessWidget {
  final ProjectModel project;
  final double slider;
  const _CompareView({required this.project, required this.slider});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            _Img(url: project.afterImageUrl ?? project.beforeImageUrl),
            ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: slider,
                child: SizedBox(
                  width: w,
                  child: _Img(url: project.beforeImageUrl),
                ),
              ),
            ),
            Positioned(
              left: w * slider - 1,
              top: 0,
              bottom: 0,
              width: 2,
              child: Container(color: AppColors.surface),
            ),
            Positioned(
              left: w * slider - 20,
              top: 0,
              bottom: 0,
              width: 40,
              child: Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(60),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.unfold_more, size: 20, color: AppColors.textPrimary),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Img extends StatelessWidget {
  final String? url;
  const _Img({this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null) return Container(color: AppColors.shimmerBase);
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, _) => Container(color: AppColors.shimmerBase),
      errorWidget: (_, _, _) => Container(color: AppColors.shimmerBase),
    );
  }
}

// ── Reveal labels ─────────────────────────────────────────────────────────────

class _RevealLabel extends StatelessWidget {
  final String text;
  final bool dark;
  final bool visible;
  const _RevealLabel({required this.text, this.dark = true, required this.visible});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: dark
              ? AppColors.surface.withAlpha(220)
              : AppColors.textPrimary.withAlpha(180),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: dark ? AppColors.textPrimary : AppColors.surface,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                fontSize: 11,
              ),
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
            Icon(icon, size: 16, color: filled ? AppColors.surface : AppColors.surface.withAlpha(200)),
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
