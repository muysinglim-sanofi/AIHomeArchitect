/// Batch 2 / 2.1 — the PWA prototype entry widget (web route '/pwa').
///
/// Switches on the controller phase: a single continuous vertical ENTRY
/// experience (cinematic hero → upload showroom → Ayden Decide → Ayden Signature
/// → Generate) → cinematic loading → Ayden Architect. Additive and web-only; the
/// mobile route tree never reaches this widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import 'pwa_architect_screen.dart';
import 'pwa_entry_screen.dart';
import 'pwa_home_screen.dart';
import 'pwa_loading_screen.dart';
import 'pwa_projects_screen.dart';
import 'pwa_first_reveal_screen.dart';
import 'pwa_reveal_screen.dart';

class PwaExperience extends ConsumerWidget {
  const PwaExperience({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(pwaControllerProvider.select((s) => s.phase));
    return switch (phase) {
      PwaPhase.home => const PwaHomeScreen(),
      PwaPhase.entry => const PwaEntryScreen(),
      PwaPhase.loading => const PwaLoadingScreen(),
      PwaPhase.architect => const PwaArchitectScreen(),
      PwaPhase.firstReveal => const PwaFirstRevealScreen(),
      PwaPhase.reveal => const PwaRevealScreen(),
      PwaPhase.projects => const PwaProjectsScreen(),
    };
  }
}
