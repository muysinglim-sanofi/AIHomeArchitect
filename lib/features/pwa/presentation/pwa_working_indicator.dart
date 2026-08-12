/// The "Ayden is working" state, wherever a generation is running.
///
/// It exists because a real render takes about two minutes, and the previous
/// placeholder was one static line for the whole of it — indistinguishable from
/// a frozen page.
///
/// The one rule that matters here: **this widget cannot finish anything.** Its
/// timer moves text and pixels and nothing else. It creates no vision, marks no
/// completion, triggers no navigation and never decides that a generation
/// succeeded. The backend's answer is the only thing that ends it, and the only
/// thing that ends it is the caller removing this widget from the tree.
///
/// There is deliberately no percentage: a progress bar over an unknown duration
/// is a guess presented as a measurement, and it reads as broken the moment it
/// reaches the end while the work continues.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/pwa_models.dart' show PwaWorkKind;
import 'pwa_widgets.dart';

/// The qualitative phases shown while a vision is produced.
///
/// They describe what is genuinely happening, in order, and the last one is
/// open-ended on purpose: whatever the real duration, the copy never claims the
/// work is nearly over.
const List<String> kPwaRefinePhases = [
  'Understanding your change',
  'Reworking the layout',
  'Designing your new space',
  'Finishing your vision',
];

const List<String> kPwaFirstVisionPhases = [
  'Preparing your photo',
  'Understanding your space',
  'Creating your vision',
  'Finishing the details',
];

const List<String> kPwaAtmospherePhases = [
  'Reading the room',
  'Shifting the materials',
  'Relighting the space',
  'Finishing your vision',
];

/// A conversational turn is seconds, not minutes: one honest line, and no phase
/// list implying a render is under way.
const List<String> kPwaConversationPhases = ['Thinking'];

/// The words for a wait, chosen from what the turn said it was doing.
///
/// THE single place the copy of a wait is decided. The controller sends intent
/// (`PwaWorkKind`) and a subject; everything a person reads is resolved here, so
/// a new kind of work cannot quietly grow its own parallel loading text.
///
/// A switch is the one case where the first line can name what is being waited
/// for, and that is the difference between "something is happening" and "my
/// request was understood".
List<String> pwaWorkingPhasesFor(PwaWorkKind kind, [String subject = '']) {
  switch (kind) {
    case PwaWorkKind.conversation:
      return kPwaConversationPhases;
    case PwaWorkKind.firstVision:
      return kPwaFirstVisionPhases;
    case PwaWorkKind.refine:
      return kPwaRefinePhases;
    case PwaWorkKind.switchAtmosphere:
      final name = subject.trim();
      if (name.isEmpty) return kPwaAtmospherePhases;
      return <String>[
        'Switching to $name',
        'Reworking the materials and atmosphere',
        'Designing your new space',
        'Finishing your vision',
      ];
  }
}

/// How long each phase is shown before the next. The last phase persists until
/// the real result arrives, however long that takes.
const Duration kPwaPhaseDuration = Duration(seconds: 14);

class PwaWorkingIndicator extends StatefulWidget {
  const PwaWorkingIndicator({
    super.key,
    this.phases = kPwaRefinePhases,
    this.foreground = Colors.white,
  });

  final List<String> phases;

  /// The ink for the status line, chosen by whoever owns the surface.
  ///
  /// This used to be a bool that defaulted to "on dark", and the only place that
  /// mounts this widget is a NEAR-WHITE chat bubble (`av7Surface` #FFFDFC). The
  /// result was white text on white: the phase copy and the ellipsis were both
  /// invisible and the whole working state read as a single gold dot in an empty
  /// bubble — exactly the "did it freeze?" moment this component exists to
  /// prevent. A colour is now passed explicitly, so a surface cannot silently
  /// disagree with its own text again.
  final Color foreground;

  @override
  State<PwaWorkingIndicator> createState() => _PwaWorkingIndicatorState();
}

class _PwaWorkingIndicatorState extends State<PwaWorkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _phaseTimer;
  int _phase = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    // Advances the COPY only. It stops at the last phase and never fires an
    // action — see the note at the top of this file.
    _phaseTimer = Timer.periodic(kPwaPhaseDuration, (t) {
      if (!mounted) return;
      if (_phase >= widget.phases.length - 1) {
        t.cancel();
        return;
      }
      setState(() => _phase++);
    });
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.phases.isEmpty
        ? 'Working'
        : widget.phases[_phase.clamp(0, widget.phases.length - 1)];
    final fg = widget.foreground;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A slow breathing dot: motion that says "alive" without implying a
        // measurable amount of remaining work.
        FadeTransition(
          opacity: Tween<double>(begin: 0.35, end: 1).animate(
            CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
          ),
          child: Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: kPwaGold,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // The phase change is a cross-fade, so the line never "jumps".
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          child: Text(
            label,
            key: ValueKey(label),
            style: TextStyle(
              fontSize: 13.5,
              height: 1.35,
              color: fg.withValues(alpha: 0.82),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _AnimatedEllipsis(controller: _pulse, color: fg.withValues(alpha: 0.55)),
      ],
    );
  }
}

/// Three dots that fill in turn — the smallest possible "still going" signal.
class _AnimatedEllipsis extends StatelessWidget {
  const _AnimatedEllipsis({required this.controller, required this.color});

  final AnimationController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final active = (controller.value * 3).floor().clamp(0, 2);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: i <= active ? 1 : 0.25),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
