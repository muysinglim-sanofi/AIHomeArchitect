/// Batch 2 — abstraction over the PWA prototype's data + mocked "generation".
///
/// Deliberately narrow so the presentation layer never touches GenerationService,
/// SupabaseService, StatusService or RevenueCat. The only implementation in this
/// batch is [MockPwaExperienceRepository] (local assets + in-memory, deterministic).
library;

import '../domain/pwa_models.dart';

abstract class PwaExperienceRepository {
  /// The mocked project (uploaded room → design session).
  PwaProject project();

  /// Ordered atmosphere selector (Ayden Signature first).
  List<PwaAtmosphere> atmospheres();

  /// Progressive cinematic-loading status lines.
  List<String> loadingSteps();

  /// The deterministic delay a mocked generation takes. Injectable so tests use
  /// Duration.zero and never sleep in real time.
  Duration get workDelay;

  /// Simulate the async "generation" work (no network) using [workDelay].
  Future<void> simulateGeneration();

  /// Canned Ayden copy — the first-vision introduction (shown with the Reveal).
  String firstVisionIntro();

  /// Canned Ayden copy for an atmosphere switch.
  String switchIntro(PwaAtmosphere atmosphere);

  /// Canned text-only advice for an opinion question (no version created).
  String adviceResponse(String question);

  /// Canned advice preface for a refine request (before "Apply this change").
  String refineAdvice(String instruction);

  /// Canned confirmation after a refine is applied (a child vision is created).
  String refineApplied(String instruction);

  /// Deterministic mocked "after" image for the Nth refine (cycles a small pool
  /// so refined versions look distinct in the prototype).
  String refineVisionAsset(int refineIndex);
}
