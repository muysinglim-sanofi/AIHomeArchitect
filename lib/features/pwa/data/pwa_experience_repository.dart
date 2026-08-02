/// Batch 2 — abstraction over the PWA prototype's data + mocked "generation".
///
/// Deliberately narrow so the presentation layer never touches GenerationService,
/// SupabaseService, StatusService or RevenueCat. The only implementation in this
/// batch is [MockPwaExperienceRepository] (local assets + in-memory, deterministic).
library;

import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';

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

  /// Concise PRE-confirmation description for a staged atmosphere change
  /// (§13 pending card, shown before the user confirms — no version yet).
  String switchProposal(PwaAtmosphere atmosphere);

  /// Concise PRE-confirmation summary for a staged refine (§12 confirm card).
  String refineSummary(String instruction);

  /// Canned text-only advice for an opinion question (no version created).
  String adviceResponse(String question);

  /// Canned advice preface for a refine request (before "Apply this change").
  String refineAdvice(String instruction);

  /// Canned confirmation after a refine is applied (a child vision is created).
  String refineApplied(String instruction);

  /// Deterministic mocked "after" image for the Nth refine (cycles a small pool
  /// so refined versions look distinct in the prototype).
  String refineVisionAsset(int refineIndex);

  // ── My Projects library (Batch 2.3) — in-memory, offline ─────────────────

  /// All saved projects (a copy of the current in-memory store).
  List<PwaProjectSnapshot> listProjects();

  /// The snapshot for [projectId], or null if it no longer exists.
  PwaProjectSnapshot? openProject(String projectId);

  /// A fresh empty draft project (a new id, no visions, no chat). NOT added to
  /// the listed library until it earns its first vision.
  PwaProjectSnapshot createDraftProject();

  /// Upsert [project] into the store (matched by projectId).
  void saveProject(PwaProjectSnapshot project);

  /// Rename the stored project (no-op if the title is blank or unknown id).
  void renameProject(String projectId, String title);

  /// Deep-copy [projectId] into a new independent project ("… Copy", new id),
  /// stored and returned. null if the source id is unknown.
  PwaProjectSnapshot? duplicateProject(String projectId);

  /// Remove [projectId] from the store (only that project).
  void deleteProject(String projectId);

  /// Client-side filtered view (title / room / atmosphere), deterministic.
  List<PwaProjectSnapshot> searchProjects(String query);

  /// Client-side sorted view, deterministic.
  List<PwaProjectSnapshot> sortProjects(PwaProjectSort order);

  /// Display label for a fast-path room id (null / unknown → "Your space").
  String roomLabel(String? roomId);

  /// Monotonic ordering key for a library mutation (deterministic; no clock).
  int nextLibraryOrder();
}
