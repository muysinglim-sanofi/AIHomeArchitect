import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';

class GenerationLoadingScreen extends StatefulWidget {
  const GenerationLoadingScreen({super.key});

  @override
  State<GenerationLoadingScreen> createState() => _GenerationLoadingScreenState();
}

class _GenerationLoadingScreenState extends State<GenerationLoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _progressController;
  late final Animation<double> _pulseAnim;

  late List<String> _steps;
  int _stepIndex = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..forward();

    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) context.pushReplacement('/result/1');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = context.l10n;
    _steps = [
      'Analyzing spatial balance…',
      'Understanding your lighting flow…',
      'Exploring warmer material palettes…',
      'Refining architectural atmosphere…',
      l10n.generatingSubtitle,
    ];
    _cycleSteps();
  }

  void _cycleSteps() async {
    for (var i = 1; i < _steps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 1600));
      if (!mounted) return;
      setState(() => _stepIndex = i);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            children: [
              const Spacer(),
              _PulsingCanvas(animation: _pulseAnim),
              const SizedBox(height: AppSpacing.xxxl),
              Text(
                l10n.generatingTitle,
                style: AppTheme.displayEditorial(
                  fontSize: 30,
                  fontWeight: FontWeight.w500,
                  height: 1.12,
                  letterSpacing: -0.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              // Non-stacking transition (consistent with Wave 4.9 §4): the
              // outgoing step vanishes immediately, only the incoming fades
              // in — no double-text overlap, fixed height = no jitter.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 360),
                switchInCurve: Curves.easeOut,
                switchOutCurve: const Threshold(0),
                layoutBuilder: (cur, _) => cur ?? const SizedBox.shrink(),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: SizedBox(
                  key: ValueKey(_stepIndex),
                  height: 22,
                  child: Center(
                    child: Text(
                      _steps.isNotEmpty ? _steps[_stepIndex] : '',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              AnimatedBuilder(
                animation: _progressController,
                builder: (context, _) => Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progressController.value,
                        backgroundColor: AppColors.border,
                        color: AppColors.textPrimary,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${(_progressController.value * 100).toInt()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingCanvas extends StatelessWidget {
  final Animation<double> animation;
  const _PulsingCanvas({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      // Calm architectural pulse — a soft breathing surface, no gamified
      // sparkle icon (premium, abstract).
      builder: (context, _) => Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusHero),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(AppColors.accentLight, AppColors.shimmerBase,
                  animation.value)!,
              Color.lerp(AppColors.shimmerBase, AppColors.accentLight,
                  animation.value)!,
            ],
          ),
        ),
      ),
    );
  }
}
