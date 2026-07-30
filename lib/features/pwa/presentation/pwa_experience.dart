/// Batch 2 — the PWA prototype entry widget (web route '/pwa').
///
/// Switches on the controller phase: upload → cinematic loading → Ayden
/// Architect. Inherits the app-wide AppTheme.light (ivory/charcoal/gold) from
/// the existing MaterialApp. Additive and web-only; the mobile route tree never
/// reaches this widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import 'pwa_architect_screen.dart';
import 'pwa_loading_screen.dart';
import 'pwa_upload_screen.dart';

class PwaExperience extends ConsumerWidget {
  const PwaExperience({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(pwaControllerProvider.select((s) => s.phase));
    return switch (phase) {
      PwaPhase.upload => const PwaUploadScreen(),
      PwaPhase.loading => const PwaLoadingScreen(),
      PwaPhase.architect => const PwaArchitectScreen(),
    };
  }
}
