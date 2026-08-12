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

  /// Offline there is no canonical brain to ask, and inventing one here is the
  /// exact heuristic this architecture forbids. The offline build therefore
  /// keeps its prototype behaviour — every typed line is treated as an edit —
  /// which is honest because nothing offline can be billed. The STAGING service
  /// is the only one that talks to a backend, and it is the only one that gates.
  @override
  Future<PwaChatTurn> chat({
    required String projectId,
    required String message,
    String uiLocale = 'en',
  }) async => const PwaChatTurn(aiMessage: '', shouldGenerate: true);

  /// Offline there is no durable lifecycle to consult — the render never left
  /// this process, so the map above IS the record. Reporting COMPLETED for a
  /// key it holds keeps the controller's attach path identical in both
  /// environments; anything else is UNKNOWN, never an invented failure.
  @override
  Future<PwaGenerationLifecycle> status(String idempotencyKey) async {
    final prior = _byIdempotencyKey[idempotencyKey];
    return prior == null
        ? const PwaGenerationLifecycle(state: 'UNKNOWN')
        : PwaGenerationLifecycle(state: 'COMPLETED', vision: prior);
  }

  /// The verify second call is a real provider look at two real images. Offline
  /// there are neither, and inventing a verdict would be exactly the kind of
  /// fixture-as-a-result this module refuses. Silence is the honest answer, and
  /// silence is also what `verified` and `unavailable` produce on staging.
  @override
  Future<PwaRefineVerification?> verify({
    required String projectId,
    required String beforePath,
    required String afterPath,
    required List<Map<String, Object?>> changes,
  }) async => null;

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
