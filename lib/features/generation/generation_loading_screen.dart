import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';

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
                style: Theme.of(context).textTheme.displayMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  _steps.isNotEmpty ? _steps[_stepIndex] : '',
                  key: ValueKey(_stepIndex),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
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
      builder: (context, _) => Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(AppColors.accentLight, AppColors.shimmerBase, animation.value)!,
              Color.lerp(AppColors.shimmerBase, AppColors.accentLight, animation.value)!,
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.auto_awesome,
            size: 56 + (8 * animation.value),
            color: AppColors.accentDark.withAlpha((180 + 75 * animation.value).toInt()),
          ),
        ),
      ),
    );
  }
}
