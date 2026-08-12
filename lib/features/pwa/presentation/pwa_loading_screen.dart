/// The wait while a real vision is rendered.
///
/// A generation measures around two minutes end to end — upload, engine, store,
/// persist, resolve. This screen covers ALL of it and says nothing it cannot
/// know: there is no percentage, because no progress is reported, and a bar
/// that fills in 2.6 s in front of a 2-minute wait is a lie that gets found out
/// at second three.
///
/// What it does show is where the work is: a qualitative step that advances on
/// a slow cadence, and an indeterminate motion so the page never looks frozen.
/// The screen NEVER decides when the wait ends — the controller leaves this
/// phase when the vision actually exists and is stored.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../application/pwa_controller.dart';
import 'pwa_widgets.dart';
import '../l10n/pwa_l10n.dart';

class PwaLoadingScreen extends ConsumerStatefulWidget {
  const PwaLoadingScreen({super.key});

  @override
  ConsumerState<PwaLoadingScreen> createState() => _PwaLoadingScreenState();
}

class _PwaLoadingScreenState extends ConsumerState<PwaLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _warmed = false;

  /// How long each step is shown. Four steps at this cadence describe roughly
  /// the first two minutes; the last one then HOLDS for as long as the render
  /// actually takes. The steps narrate the work — they never predict its end.
  static const Duration _stepDuration = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    // One breathing cycle, repeated: indeterminate by construction, because the
    // backend reports no progress to be determinate about. Total elapsed time
    // comes from the same ticker, so there is no second timer to leak.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_warmed) return;
    _warmed = true;
    // Warm-decode the NEW Before photo during this already-awaited loading
    // window so Ayden Architect's FIRST frame paints the user's replaced photo
    // immediately — never an After-only frame (the After is a bundled, already-
    // cached per-atmosphere asset that would otherwise dominate for the frames
    // it takes Image.memory(newBytes) to decode). Reuses existing state.source;
    // adds no state, no save path, no UX change.
    final src = ref.read(pwaControllerProvider).source;
    if (src != null) {
      precacheImage(MemoryImage(src.bytes), context, onError: (_, _) {});
    }
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
            // The step follows real elapsed time and STOPS at the last one, so a
            // slow render keeps saying "finishing the details" instead of
            // looping back to "understanding your space".
            final elapsed = _ctrl.lastElapsedDuration ?? Duration.zero;
            final stepIndex =
                (elapsed.inMilliseconds ~/ _stepDuration.inMilliseconds).clamp(
                  0,
                  steps.length - 1,
                );
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
                      border: Border.all(
                        color: kPwaGold.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Icon(
                      Icons.architecture,
                      color: kPwaGold,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  steps[stepIndex],
                  key: ValueKey('loading-step-$stepIndex'),
                  style: pwaSerif(fontSize: 20, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
                Text(
                  context.pwaL10n.usuallyACoupleOfMinutes,
                  key: const ValueKey('loading-duration-note'),
                  style: pwaSerif(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 18),
                // A travelling highlight, NOT a progress bar: it says "still
                // working", which is the only thing that is actually known.
                SizedBox(
                  width: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: 4,
                      child: ColoredBox(
                        color: AppColors.border,
                        child: Align(
                          alignment: Alignment(-1 + 2 * v, 0),
                          child: const FractionallySizedBox(
                            widthFactor: 0.34,
                            heightFactor: 1,
                            child: ColoredBox(color: kPwaGold),
                          ),
                        ),
                      ),
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
