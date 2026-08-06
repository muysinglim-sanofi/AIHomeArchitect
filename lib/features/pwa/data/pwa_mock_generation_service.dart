/// The OFFLINE (`AYDEN_ENV=mock`) implementation of [PwaGenerationService].
///
/// It exists so the controller has exactly ONE code path: it always asks a
/// generation service and never branches on "is there a backend". The staging
/// runtime injects [PwaStagingGenerationService]; this one is injected only by
/// the explicitly isolated mock environment, where there is no backend, no
/// Storage and no network by design.
///
/// It is honest about what it is: the images it returns are BUNDLE ASSETS, and
/// it says so by returning `assets/...` paths. Every rendering and persistence
/// seam already distinguishes a bundle asset from a Storage path, so a mock
/// result can never be mistaken for a real render — and the staging assertions
/// that forbid a fixture as a result stay meaningful.
library;

import 'pwa_experience_repository.dart';
import 'pwa_generation_service.dart';

class PwaMockGenerationService implements PwaGenerationService {
  PwaMockGenerationService(this._repo);

  final PwaExperienceRepository _repo;

  /// Cycles the small pool of refine assets so successive refinements look
  /// distinct in the prototype (a documented mock limitation).
  int _refineIndex = 0;

  /// Replays are modelled here too, so double-click protection is exercised in
  /// the offline build and not only against staging.
  final Map<String, PwaGeneratedVision> _byIdempotencyKey = {};

  @override
  Future<PwaGeneratedVision> generate(PwaGenerationIntent intent) async {
    await _repo.simulateGeneration();
    final prior = _byIdempotencyKey[intent.idempotencyKey];
    if (prior != null) {
      return PwaGeneratedVision(
        imagePath: prior.imagePath,
        visionNumber: prior.visionNumber,
        replayed: true,
      );
    }
    final asset = intent.actionType == 'refine'
        ? _repo.refineVisionAsset(_refineIndex++)
        : _assetForAtmosphere(intent.atmosphereId);
    final made = PwaGeneratedVision(
      imagePath: asset,
      visionNumber: intent.visionNumber,
      replayed: false,
    );
    _byIdempotencyKey[intent.idempotencyKey] = made;
    return made;
  }

  String _assetForAtmosphere(String id) {
    final all = _repo.atmospheres();
    for (final a in all) {
      if (a.id == id) return a.visionAsset;
    }
    return all.first.visionAsset;
  }

  @override
  void dispose() {}
}
