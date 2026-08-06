/// Batch 3.0 — staging persistence adapter (fail-closed skeleton).
///
/// This is the ARCHITECTURE SEAT for remote staging persistence. It is NOT
/// activated in this batch: no isolated staging project/credentials can be
/// proven safe here, so every operation fails CLOSED with a `configuration`
/// error rather than risk touching a real backend or silently falling back to
/// mock/production.
///
/// Activation (a later, credential-gated step) wires this adapter to the
/// approved isolated staging backend AFTER [PwaEnvironment.assertStagingTargetAllowed]
/// passes: it would translate the interface calls into scoped queries against
/// `pwa_installations` / `pwa_projects` / `pwa_visions` / `pwa_messages` using
/// [pwa_project_serialization], with the service-role key staying server-side
/// (§12). Deliberately imports NO supabase/http client so the offline build
/// carries zero remote surface until activation.
library;

import 'dart:typed_data';

import '../config/pwa_environment.dart';
import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';
import 'pwa_persistence_repository.dart';
import 'pwa_repository_error.dart';

class StagingPwaPersistenceRepository implements PwaPersistenceRepository {
  StagingPwaPersistenceRepository(this.environment)
    : assert(true, 'target is validated by PwaEnvironment.parse before use');

  final PwaEnvironment environment;

  Never _notActivated(String op) => throw PwaRepositoryError.configuration(
    'Remote staging persistence is not activated in this build (op: $op). '
    'It requires an approved isolated staging target and credentials.',
  );

  @override
  Future<PwaInstallationIdentity> ensureInstallation() async =>
      _notActivated('ensureInstallation');

  @override
  Future<void> healthCheck() async => _notActivated('healthCheck');

  @override
  Future<List<PwaProjectSnapshot>> loadLibrary() async =>
      _notActivated('loadLibrary');

  @override
  Future<PwaProjectSnapshot?> loadProject(String projectId) async =>
      _notActivated('loadProject');

  @override
  Future<void> saveProject(
    PwaProjectSnapshot project, {
    bool replaceOriginal = false,
  }) async => _notActivated('saveProject');

  @override
  Future<void> appendVision(String projectId, PwaVision vision) async =>
      _notActivated('appendVision');

  @override
  Future<void> appendMessage(String projectId, PwaMessage message) async =>
      _notActivated('appendMessage');

  @override
  Future<void> updateCurrentVision(String projectId, String visionId) async =>
      _notActivated('updateCurrentVision');

  @override
  Future<void> updateCoverVision(String projectId, String visionId) async =>
      _notActivated('updateCoverVision');

  @override
  Future<void> renameProject(String projectId, String title) async =>
      _notActivated('renameProject');

  @override
  Future<PwaProjectSnapshot> duplicateProject(String projectId) async =>
      _notActivated('duplicateProject');

  @override
  Future<void> softDeleteProject(String projectId) async =>
      _notActivated('softDeleteProject');

  @override
  Future<Uint8List?> loadOriginalBytes(PwaProjectSnapshot snapshot) async =>
      _notActivated('loadOriginalBytes');

  @override
  Future<PwaOriginalUpload> prepareGeneration(
    PwaProjectSnapshot snapshot, {
    bool replaceOriginal = false,
  }) async => _notActivated('prepareGeneration');

  @override
  Future<String> signedImageUrl(String path, int expiresInSeconds) async =>
      _notActivated('signedImageUrl');
}

/// Select the persistence adapter for [environment] WITHOUT ever silently
/// downgrading. Mock → offline adapter. Staging → the fail-closed staging
/// adapter (which requires explicit activation). Production → refused.
PwaPersistenceRepository pwaPersistenceRepositoryFor(
  PwaEnvironment environment, {
  required PwaPersistenceRepository mock,
}) {
  return switch (environment.environment) {
    AydenEnvironment.mock => mock,
    AydenEnvironment.staging => StagingPwaPersistenceRepository(environment),
    AydenEnvironment.production => throw const PwaRepositoryError.configuration(
      'Production persistence is not implemented (refusing).',
    ),
  };
}
