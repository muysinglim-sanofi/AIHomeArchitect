/// Batch 2 — cinematic mock loading. Elegant, deterministic, no backend.
///
/// Runs a single forward AnimationController (test-safe — it settles, unlike a
/// repeating one) and derives the progressive status line from it. The actual
/// transition to Ayden Architect is driven by the controller's injectable
/// delay, not by this screen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../application/pwa_controller.dart';
import 'pwa_widgets.dart';

class PwaLoadingScreen extends ConsumerStatefulWidget {
  const PwaLoadingScreen({super.key});

  @override
  ConsumerState<PwaLoadingScreen> createState() => _PwaLoadingScreenState();
}

class _PwaLoadingScreenState extends ConsumerState<PwaLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = ref.read(pwaRepositoryProvider).loadingSteps();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final v = _ctrl.value;
            final stepIndex = (v * steps.length).floor().clamp(0, steps.length - 1);
            final pulse = 1 + 0.07 * math.sin(v * math.pi * 6);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: pulse,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kPwaGold.withValues(alpha: 0.12),
                      border: Border.all(color: kPwaGold.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(Icons.architecture, color: kPwaGold, size: 34),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  steps[stepIndex],
                  key: ValueKey('loading-step-$stepIndex'),
                  style: pwaSerif(fontSize: 20, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 4,
                      backgroundColor: AppColors.border,
                      valueColor: const AlwaysStoppedAnimation(kPwaGold),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
