/// Batch 2 — deterministic, offline mock of the PWA experience.
///
/// Uses ONLY bundled assets and in-memory data. Never instantiates
/// GenerationService / SupabaseService / StatusService / RevenueCat, never
/// touches the network, never requires authentication. All copy is canned and
/// all timing goes through [workDelay] (Duration.zero in tests).
///
/// Asset note: the prototype pairs a real uploaded "before" (or a bundled
/// original) with bundled "after" room photos from assets/showcase/. Because no
/// real generation runs, refined visions reuse a small rotating pool of those
/// photos so lineage reads clearly — a documented mock limitation.
library;

import '../domain/pwa_models.dart';
import 'pwa_experience_repository.dart';

class MockPwaExperienceRepository implements PwaExperienceRepository {
  MockPwaExperienceRepository({this.workDelay = const Duration(seconds: 3)});

  @override
  final Duration workDelay;

  static const String _projectId = 'pwa-mock-project';

  @override
  PwaProject project() => const PwaProject(
        projectId: _projectId,
        originalAsset: 'assets/showcase/apartment_before.jpg',
        title: 'Your space',
      );

  @override
  List<PwaAtmosphere> atmospheres() => const [
        PwaAtmosphere(
          id: 'ayden_signature',
          name: 'Ayden Signature',
          asset: 'assets/atmospheres/ayden_signature.jpg',
          visionAsset: 'assets/showcase/apartment_after.jpg',
          isSignature: true,
        ),
        PwaAtmosphere(
          id: 'warm_modern',
          name: 'Warm Modern',
          asset: 'assets/cards/atmospheres/warm_modern.png',
          visionAsset: 'assets/showcase/living_after.jpg',
        ),
        PwaAtmosphere(
          id: 'soft_luxury',
          name: 'Soft Luxury',
          asset: 'assets/cards/atmospheres/soft_luxury.png',
          visionAsset: 'assets/showcase/villa_after.jpg',
        ),
        PwaAtmosphere(
          id: 'japandi_calm',
          name: 'Japandi Calm',
          asset: 'assets/cards/atmospheres/japandi_calm.png',
          visionAsset: 'assets/showcase/smallspace_after.jpg',
        ),
        PwaAtmosphere(
          id: 'nordic_warmth',
          name: 'Nordic Warmth',
          asset: 'assets/cards/atmospheres/nordic_warmth.png',
          visionAsset: 'assets/showcase/bathroom_after.jpg',
        ),
        PwaAtmosphere(
          id: 'tropical_escape',
          name: 'Tropical Escape',
          asset: 'assets/cards/atmospheres/tropical_escape.png',
          visionAsset: 'assets/showcase/facade_after.jpg',
        ),
      ];

  @override
  List<String> loadingSteps() => const [
        'Understanding your space',
        'Preserving the architecture',
        'Building the Ayden Signature',
        'Preparing your reveal',
      ];

  @override
  Future<void> simulateGeneration() =>
      workDelay == Duration.zero ? Future<void>.value() : Future.delayed(workDelay);

  @override
  String firstVisionIntro() =>
      'I created your first vision. I kept the room’s architecture and '
      'introduced warmer materials, softer lighting and a more refined '
      'balance — my signature direction. Explore the atmospheres below, or '
      'tell me what you’d like to change.';

  @override
  String switchIntro(PwaAtmosphere atmosphere) =>
      'Here is your space reimagined in ${atmosphere.name}. I preserved the '
      'layout and openings, and shifted the materials and mood to match.';

  @override
  String adviceResponse(String question) =>
      'Honestly, this direction is working well — the proportions feel calm and '
      'the materials read as intentional. If you want more warmth I’d lean into '
      'timber and a softer rug; for a lighter feel, I’d open the palette. Just '
      'say the word and I’ll apply it.';

  @override
  String refineAdvice(String instruction) =>
      'Good instinct. “$instruction” would suit this space — I’d keep the '
      'architecture intact and adjust the materials and lighting to get there. '
      'Want me to apply it as a new version?';

  @override
  String refineApplied(String instruction) =>
      'Done — I applied “$instruction” as a new version, branched from the one '
      'you were viewing. Your previous vision is preserved in your history.';

  static const List<String> _refinePool = [
    'assets/showcase/living_after.jpg',
    'assets/showcase/villa_after.jpg',
    'assets/showcase/smallspace_after.jpg',
  ];

  @override
  String refineVisionAsset(int refineIndex) =>
      _refinePool[refineIndex % _refinePool.length];
}
