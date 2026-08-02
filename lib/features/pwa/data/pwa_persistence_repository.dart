/// Batch 3.0 — the persistence abstraction (§14).
///
/// Presentation → Controller/Application → PwaPersistenceRepository → Adapter.
/// Widgets never touch Supabase/HTTP. Two adapters exist:
///   • [MockPwaPersistenceRepository] — offline, deterministic, round-trips the
///     serialization layer in memory (no network).
///   • [StagingPwaPersistenceRepository] — staging persistence, fail-closed,
///     never falls back to production or mock.
///
/// Every operation returns domain data or throws a [PwaRepositoryError].
library;

import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';

/// Staging tenancy identity (§5). An opaque, random, STAGING-ONLY installation
/// id. NOT authentication and NOT cross-device — it only scopes staging data.
class PwaInstallationIdentity {
  const PwaInstallationIdentity(this.installationId);
  final String installationId;
}

abstract class PwaPersistenceRepository {
  /// Load (or lazily create) the staging tenancy identity for this browser.
  Future<PwaInstallationIdentity> ensureInstallation();

  /// Cheap reachability/permission probe. Throws a typed error when unavailable
  /// so hydration can render a non-destructive retry state (§15).
  Future<void> healthCheck();

  /// All non-deleted projects for this installation.
  Future<List<PwaProjectSnapshot>> loadLibrary();

  /// A single project's full graph, or null if unknown / soft-deleted.
  Future<PwaProjectSnapshot?> loadProject(String projectId);

  /// Idempotent upsert of a project's FULL graph, keyed by projectId (§16).
  Future<void> saveProject(PwaProjectSnapshot project);

  /// Append-only vision write. Never overwrites an existing vision.
  Future<void> appendVision(String projectId, PwaVision vision);

  /// Append-only message write, preserving chronology.
  Future<void> appendMessage(String projectId, PwaMessage message);

  Future<void> updateCurrentVision(String projectId, String visionId);
  Future<void> updateCoverVision(String projectId, String visionId);

  Future<void> renameProject(String projectId, String title);

  /// Deep, fully-independent duplicate (§9-11). Returns the new project.
  Future<PwaProjectSnapshot> duplicateProject(String projectId);

  /// Soft delete — hidden from [loadLibrary], not physically purged (§16).
  Future<void> softDeleteProject(String projectId);
}
