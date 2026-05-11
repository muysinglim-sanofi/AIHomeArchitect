import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../shared/widgets/app_button.dart';

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
        duration: const Duration(milliseconds: 400),
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

    final slides = [
      _Slide(
        title: l10n.onboarding1Title,
        subtitle: l10n.onboarding1Sub,
        imageUrl: 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800',
        tags: [l10n.homeCategoryInterior, l10n.homeCategoryExterior, l10n.uploadHint.split(',').first],
      ),
      _Slide(
        title: l10n.onboarding2Title,
        subtitle: l10n.onboarding2Sub,
        imageUrl: 'https://images.unsplash.com/photo-1582268611958-ebfd161ef9cf?w=800',
        tags: [l10n.garden, l10n.terrace, l10n.poolArea],
        isAiSlide: true,
      ),
      _Slide(
        title: l10n.onboarding3Title,
        subtitle: l10n.onboarding3Sub,
        imageUrl: 'https://images.unsplash.com/photo-1600566753190-17f0baa2a6c3?w=800',
        tags: [l10n.beforeLabel, l10n.afterLabel, l10n.shareResult],
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.sm,
                AppSpacing.pagePadding,
                0,
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
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slideCount,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) => _SlideView(slide: slides[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                0,
                AppSpacing.pagePadding,
                AppSpacing.xl,
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

class _Slide {
  final String title;
  final String subtitle;
  final String imageUrl;
  final List<String> tags;
  final bool isAiSlide;
  const _Slide({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.tags,
    this.isAiSlide = false,
  });
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),
          Container(
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius * 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: slide.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: AppColors.shimmerBase),
                  errorWidget: (_, _, _) => Container(color: AppColors.shimmerBase),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.textPrimary.withAlpha(180),
                      ],
                      stops: const [0.4, 1.0],
                    ),
                  ),
                ),
                if (slide.isAiSlide)
                  Positioned.fill(child: _AiSlideOverlay())
                else
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Wrap(
                      spacing: 6,
                      children: slide.tags
                          .map((tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface.withAlpha(220),
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: Text(
                                  tag,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            slide.title,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(height: 1.15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            slide.subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.65,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

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

// ── AI slide overlay (onboarding slide 1) ─────────────────────────────────────

class _AiSlideOverlay extends StatefulWidget {
  @override
  State<_AiSlideOverlay> createState() => _AiSlideOverlayState();
}

class _AiSlideOverlayState extends State<_AiSlideOverlay>
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
    Future.delayed(const Duration(milliseconds: 600), () {
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 52),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
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
                  'I want a tropical modern vibe with warm lighting.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                      ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
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
                  'Exploring natural textures and evening atmosphere…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.surface,
                        fontSize: 11,
                      ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
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
