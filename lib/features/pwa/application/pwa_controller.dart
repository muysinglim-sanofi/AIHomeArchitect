/// Batch 2 — the PWA prototype state machine (Riverpod StateNotifier).
///
/// Owns the conversation, the branched version tree, the current selection and
/// the upload → loading → architect phase. Drives the mocked repository only —
/// it never imports GenerationService / SupabaseService / StatusService /
/// RevenueCat. Deterministic: ids come from an internal counter, timing from
/// the repository's injectable delay, so it is fully unit-testable.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/media/ayden_image_source.dart';
import '../data/mock_pwa_experience_repository.dart';
import '../data/pwa_experience_repository.dart';
import '../data/pwa_persistence_repository.dart';
import '../domain/pwa_intent.dart';
import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';
import 'pwa_route.dart';

enum PwaPhase { entry, loading, architect, projects }

/// Where the current source image came from. Governs mock honesty: only the
/// bundled example may claim a known room type; an arbitrary user upload must
/// NOT be labelled (the real backend will detect it later).
enum PwaImageOrigin { bundledExample, userUpload }

/// Injectable repository. Overridden in tests with a zero-delay mock.
final pwaRepositoryProvider = Provider<PwaExperienceRepository>(
  (ref) => MockPwaExperienceRepository(),
);

/// Durable persistence. `null` in mock / tests (fully offline — the experience
/// repository IS the store). In staging, the app boot overrides this with the
/// isolated Supabase adapter (§7). The controller stays identical either way.
final pwaPersistenceProvider = Provider<PwaPersistenceRepository?>(
  (ref) => null,
);

/// Boot-time durable restore (staging only): the library + last-active project
/// + its downloaded original photo, computed in `main._bootPwaStaging` BEFORE
/// runApp so the controller opens on the correct screen at the FIRST frame (no
/// cinematic flash). `null` in mock / tests → normal Hero entry.
final pwaBootRestoreProvider = Provider<PwaBootRestore?>((ref) => null);

final pwaControllerProvider = StateNotifierProvider<PwaController, PwaState>((
  ref,
) {
  return PwaController(
    ref.watch(pwaRepositoryProvider),
    persistence: ref.watch(pwaPersistenceProvider),
    restore: ref.watch(pwaBootRestoreProvider),
  );
});

/// Everything needed to open the PWA on the right screen after a hard refresh,
/// resolved durably before the first frame. A plain data holder — no engine.
class PwaBootRestore {
  const PwaBootRestore({
    required this.library,
    this.active,
    this.activeSource,
    this.route,
    this.legacyHidden = 0,
  });

  /// All non-deleted projects (already loaded) to seed the working library.
  final List<PwaProjectSnapshot> library;

  /// The last-active project to reopen (Draft or active), or null → Hero.
  final PwaProjectSnapshot? active;

  /// The restored original photo for [active] (null for a bundle asset / none).
  final AydenImageSource? activeSource;

  /// The normalized durable route this boot resolves to (§5). Drives the
  /// first-frame screen AND the URL the address bar is normalized to. Null →
  /// legacy most-recent restore (no URL context, e.g. mock/tests).
  final PwaRoute? route;

  /// Step 6A — how many legacy zero-Vision rows were excluded from this boot's
  /// library (hidden, not deleted). For diagnostics / the manual-review report.
  final int legacyHidden;
}

/// Find a project by id in an already-loaded list (no `package:collection`).
PwaProjectSnapshot? pwaFindProject(List<PwaProjectSnapshot> lib, String id) {
  for (final p in lib) {
    if (p.projectId == id) return p;
  }
  return null;
}

/// Resolve the durable boot restore (§5 boot order): restore the anonymous
/// session, load the library, pick the most-recently-updated non-deleted project
/// as the last-active one, and fetch its original photo bytes. Best-effort — any
/// failure yields an EMPTY restore (Hero), never blocks boot. Shared by main's
/// staging boot AND the boot tests so both exercise the SAME routing decision.
Future<PwaBootRestore> pwaResolveBootRestore(
  PwaPersistenceRepository p, {
  PwaRoute? route,
}) async {
  try {
    await p.ensureInstallation(); // restore or create the anonymous session
    final allRows = await p.loadLibrary();
    // Step 6A — exclude LEGACY zero-Vision rows (from the former upload-time
    // behaviour): they are never displayable, never a boot-active project, and
    // never a valid URL target. NOT deleted — only hidden. `legacyHidden` is
    // surfaced so the app/report can state how many were hidden this session.
    final library = allRows.where((x) => x.visions.isNotEmpty).toList();
    final legacyHidden = allRows.length - library.length;
    if (library.isEmpty) {
      return PwaBootRestore(
        library: const [],
        route: route == null ? null : PwaRoute.home,
        legacyHidden: legacyHidden,
      );
    }

    // §5 — the URL is the primary authority. When it names a project route we
    // open THAT project; `updatedOrder` is only the fallback when there is no
    // URL context (mock/tests → route == null) or the URL is not a project.
    PwaProjectSnapshot? active;
    PwaRoute? resolved;
    if (route == null) {
      final sorted = [...library]
        ..sort((a, b) => b.updatedOrder.compareTo(a.updatedOrder));
      active = sorted.first;
    } else {
      final norm = PwaRoute.normalize(
        route,
        lookup: (id) => pwaFindProject(library, id),
        libraryEmpty: library.isEmpty,
      );
      resolved = norm;
      if (norm.projectId != null &&
          (norm.page == PwaPage.draft || norm.page == PwaPage.architect)) {
        active = pwaFindProject(library, norm.projectId!);
      }
      // home / projects → no active project (Hero / My Projects).
    }

    // Rebuild the original photo via the SHARED hydration seam (also used by
    // in-app openProject) so boot-from-URL and card-open install byte-identical
    // sources. Best-effort — a Draft without it still restores (upload UI).
    final source = active == null ? null : await pwaHydrateOriginal(p, active);
    return PwaBootRestore(
      library: library,
      active: active,
      activeSource: source,
      route: resolved,
      legacyHidden: legacyHidden,
    );
  } catch (_) {
    return PwaBootRestore(
      library: const [],
      route: route == null ? null : PwaRoute.home,
    );
  }
}

/// The SINGLE original-photo hydration seam: rebuild the in-memory
/// [AydenImageSource] for [snapshot] from durable Storage. Shared by boot
/// restore AND in-app `openProject`, so both install byte-identical originals.
/// Best-effort: returns null for a bundle-asset original or on any load error.
Future<AydenImageSource?> pwaHydrateOriginal(
  PwaPersistenceRepository p,
  PwaProjectSnapshot snapshot,
) async {
  try {
    final bytes = await p.loadOriginalBytes(snapshot);
    if (bytes == null) return null;
    return AydenImageSource(
      bytes: bytes,
      filename: snapshot.originalImageAsset.split('/').last,
      mimeType: pwaMimeForImagePath(snapshot.originalImageAsset),
    );
  } catch (_) {
    return null;
  }
}

/// MIME from an image path extension (jpeg default).
String? pwaMimeForImagePath(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

/// Discreet durability indicator for the active session (§5). `idle` in mock
/// (no backend); `saving`/`saved`/`error` reflect the staging save seam.
enum PwaSaveState { idle, saving, saved, error }

class PwaState {
  const PwaState({
    required this.phase,
    required this.project,
    required this.atmospheres,
    this.source,
    this.sourceOrigin,
    this.selectedRoomId,
    this.messages = const [],
    this.versions = const [],
    this.currentVisionId,
    this.previewVisionId,
    this.sourceVisionId,
    this.pendingAtmosphereId,
    this.selectedAtmosphereId,
    this.generating = false,
    this.returningToStudio = false,
    this.library = const [],
    this.librarySort = PwaProjectSort.recentlyUpdated,
    this.librarySearch = '',
    this.saveState = PwaSaveState.idle,
    this.activeTitleOverride,
  });

  final PwaPhase phase;
  final PwaProject project;
  final List<PwaAtmosphere> atmospheres;
  final AydenImageSource? source;
  final PwaImageOrigin? sourceOrigin;

  /// Pre-generation room choice on the fast path. null = Ayden auto-detect.
  final String? selectedRoomId;
  final List<PwaMessage> messages;
  final List<PwaVision> versions;

  /// The accepted "current" vision (canonical).
  final String? currentVisionId;

  /// A version being PREVIEWED in the Full Reveal (filmstrip click). View-only:
  /// it does not change the current vision. null → the current vision is shown.
  final String? previewVisionId;

  /// One-shot parent override for the NEXT confirmed generation (set by
  /// "Continue from this vision"). null → the next child branches off current.
  final String? sourceVisionId;

  /// A staged atmosphere awaiting confirmation (§13). null → nothing pending.
  final String? pendingAtmosphereId;
  final String? selectedAtmosphereId;
  final bool generating;

  /// Transient signal for the entry screen: set by [PwaController.returnToStudio]
  /// so the freshly-mounted entry screen jumps to the correct preserved section
  /// (§11). Consumed (cleared) once acted on — never persisted.
  final bool returningToStudio;

  /// Batch 2.3 — the My Projects library (a mirror of the repository store, so
  /// the UI rebuilds on every mutation) and its deterministic view state.
  final List<PwaProjectSnapshot> library;
  final PwaProjectSort librarySort;
  final String librarySearch;

  /// Durability status of the active session (staging only; `idle` in mock).
  final PwaSaveState saveState;

  /// A user-set title for the ACTIVE session. Null until the user renames the
  /// active project/Draft; then it pins the name (shown on the Draft card and
  /// used as the persisted title, surviving Room/Atmosphere changes and refresh).
  final String? activeTitleOverride;

  /// The id of the project currently loaded in the active session.
  String get activeProjectId => project.projectId;

  /// The durable browser route this state maps to (§6). Home vs Draft inside the
  /// single `entry` phase is decided by whether a photo is active: a photo with
  /// no vision is the Draft Fast Path; otherwise the Hero (Home). Architect
  /// carries the previewed vision as `?vision=` only when it differs from the
  /// current one. Transient `loading` (first-vision generation) keeps the Draft
  /// URL until the vision lands and the phase becomes Architect.
  PwaRoute get canonicalRoute {
    switch (phase) {
      case PwaPhase.projects:
        return PwaRoute.projects;
      case PwaPhase.architect:
        final v = previewVisionId;
        final vid = (v != null && v != currentVisionId) ? v : null;
        return PwaRoute(
          PwaPage.architect,
          projectId: project.projectId,
          visionId: vid,
        );
      case PwaPhase.loading:
      case PwaPhase.entry:
        // Step 6A — a pre-Generate creation session is Home/Create: never a
        // durable `/projects/{id}/draft` URL (there is no durable project yet).
        return PwaRoute.home;
    }
  }

  /// §4 — the active session as a DRAFT card: a photo has been uploaded but no
  /// vision generated yet. Synthetic (never stored); the library shows it on top
  /// with a "Draft" badge and "Continue setup", no fake vision count. Its cover
  /// is the uploaded photo. Null once a vision exists or before any upload.
  PwaProjectSnapshot? get activeDraft {
    if (versions.isNotEmpty || source == null) return null;
    final atmoId = selectedAtmosphereId ?? 'ayden_signature';
    final atmo = atmospheres.firstWhere(
      (a) => a.id == atmoId,
      orElse: () => atmospheres.first,
    );
    return PwaProjectSnapshot(
      projectId: project.projectId,
      // Placeholder until the user renames the Draft; a rename pins the name via
      // activeTitleOverride and it shows here (and survives F5).
      title: activeTitleOverride ?? 'Untitled Space',
      originalImageAsset: project.originalAsset,
      roomId: selectedRoomId,
      roomLabel: '', // resolved for display in the draft card
      selectedAtmosphereId: atmo.id,
      atmosphereLabel: atmo.name,
      visions: const [],
      messages: const [],
      currentVisionId: null,
      createdOrder: 0,
      updatedOrder: 0,
      updatedLabel: '',
      status: PwaProjectStatus.draft,
      source: source,
    );
  }

  /// Library filtered by [librarySearch] then sorted by [librarySort]. When the
  /// synthetic active-draft card is shown (not searching), its persisted twin is
  /// hidden from the grid so a Draft never appears twice (§ point 2).
  List<PwaProjectSnapshot> get visibleProjects {
    // Step 6A — My Projects shows only USABLE generated projects: at least one
    // Vision AND a project-owned cover. Legacy zero-Vision rows (from the former
    // upload-time behaviour) are hidden here at the domain seam (never a visual
    // if in the card). They are NOT deleted — only excluded from display.
    final usable = library.where(
      (p) => p.visions.isNotEmpty && p.coverVision != null,
    );
    final base = PwaProjectSnapshot.search(usable.toList(), librarySearch);
    return PwaProjectSnapshot.sortedBy(base, librarySort);
  }

  bool get hasSource => source != null;
  int get versionCount => versions.length;

  PwaVision? _byId(String? id) {
    if (id == null) return null;
    for (final v in versions) {
      if (v.versionId == id) return v;
    }
    return null;
  }

  PwaVision? get currentVision =>
      _byId(currentVisionId) ?? (versions.isEmpty ? null : versions.last);

  /// The vision shown in the Full Reveal (a previewed older version, else the
  /// current one).
  PwaVision? get previewedVision => _byId(previewVisionId) ?? currentVision;

  /// True when previewing a version that is NOT the current one.
  bool get isPreviewingOther =>
      previewVisionId != null && previewVisionId != currentVisionId;

  /// The parent for the next confirmed generation (an explicit "continue-from"
  /// source, else the current vision).
  PwaVision? get sourceVision => _byId(sourceVisionId) ?? currentVision;

  /// Versions in chronological order (oldest first).
  List<PwaVision> get versionsChronological {
    final list = [...versions]..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// Index of the vision shown in the Full Reveal within [versionsChronological]
  /// (−1 when there are none). Drives the "Vision N of M" counter + prev/next.
  int get previewedIndex {
    final id = previewedVision?.versionId;
    if (id == null) return -1;
    return versionsChronological.indexWhere((v) => v.versionId == id);
  }

  /// Whether an older / newer vision exists to step to from the previewed one.
  bool get hasPreviousVision => previewedIndex > 0;
  bool get hasNextVision {
    final i = previewedIndex;
    return i >= 0 && i < versionCount - 1;
  }

  /// The reveal message id that introduced [versionId] (for "Find in chat").
  /// null when the version has no in-conversation reveal message.
  String? revealMessageIdForVersion(String versionId) {
    for (final m in messages) {
      if (m.kind == PwaMessageKind.reveal && m.visionId == versionId) {
        return m.id;
      }
    }
    return null;
  }

  PwaState copyWith({
    PwaPhase? phase,
    PwaProject? project,
    AydenImageSource? source,
    PwaImageOrigin? sourceOrigin,
    String? selectedRoomId,
    bool clearRoom = false,
    bool clearSource = false,
    List<PwaMessage>? messages,
    List<PwaVision>? versions,
    String? currentVisionId,
    String? previewVisionId,
    bool clearPreview = false,
    String? sourceVisionId,
    bool clearSourceVision = false,
    String? pendingAtmosphereId,
    bool clearPending = false,
    String? selectedAtmosphereId,
    bool? generating,
    bool? returningToStudio,
    List<PwaProjectSnapshot>? library,
    PwaProjectSort? librarySort,
    String? librarySearch,
    PwaSaveState? saveState,
    String? activeTitleOverride,
    bool clearTitleOverride = false,
  }) {
    return PwaState(
      phase: phase ?? this.phase,
      project: project ?? this.project,
      atmospheres: atmospheres,
      source: clearSource ? null : (source ?? this.source),
      sourceOrigin: clearSource ? null : (sourceOrigin ?? this.sourceOrigin),
      selectedRoomId: (clearSource || clearRoom)
          ? null
          : (selectedRoomId ?? this.selectedRoomId),
      messages: messages ?? this.messages,
      versions: versions ?? this.versions,
      currentVisionId: currentVisionId ?? this.currentVisionId,
      previewVisionId: clearPreview
          ? null
          : (previewVisionId ?? this.previewVisionId),
      sourceVisionId: clearSourceVision
          ? null
          : (sourceVisionId ?? this.sourceVisionId),
      pendingAtmosphereId: clearPending
          ? null
          : (pendingAtmosphereId ?? this.pendingAtmosphereId),
      selectedAtmosphereId: selectedAtmosphereId ?? this.selectedAtmosphereId,
      generating: generating ?? this.generating,
      returningToStudio: returningToStudio ?? this.returningToStudio,
      library: library ?? this.library,
      librarySort: librarySort ?? this.librarySort,
      librarySearch: librarySearch ?? this.librarySearch,
      saveState: saveState ?? this.saveState,
      activeTitleOverride: clearTitleOverride
          ? null
          : (activeTitleOverride ?? this.activeTitleOverride),
    );
  }
}

class PwaController extends StateNotifier<PwaState> {
  PwaController(
    this._repo, {
    PwaPersistenceRepository? persistence,
    PwaBootRestore? restore,
  }) : _persistence = persistence,
       super(_initialState(_repo, restore)) {
    // The first-frame screen was already chosen from `restore` (no async
    // flash). Seed the in-memory working library so My Projects + open/duplicate
    // see the same rows. Mock stays fully offline (restore == null).
    final r = restore;
    if (r != null) {
      for (final s in r.library) {
        _repo.saveProject(s);
      }
      state = state.copyWith(library: _repo.listProjects());
    }
  }

  /// Choose the FIRST-frame screen from the durable restore (§ boot order):
  /// no project → Hero; Draft → entry/Fast-Path (photo + cinematic skipped);
  /// active project → Ayden Architect. Pure + synchronous so nothing flashes.
  static PwaState _initialState(
    PwaExperienceRepository repo,
    PwaBootRestore? restore,
  ) {
    final base = PwaState(
      phase: PwaPhase.entry,
      project: repo.project(),
      atmospheres: repo.atmospheres(),
      selectedAtmosphereId: 'ayden_signature',
      library: restore?.library ?? repo.listProjects(),
    );
    final active = restore?.active;
    if (active == null) {
      // No durable project, but the URL may still name My Projects (§5).
      if (restore?.route?.page == PwaPage.projects) {
        return base.copyWith(phase: PwaPhase.projects);
      }
      return base; // Hero
    }
    final descriptor = PwaProject(
      projectId: active.projectId,
      originalAsset: active.originalImageAsset,
      title: active.title,
    );
    final atmo = active.selectedAtmosphereId ?? 'ayden_signature';
    final source = restore!.activeSource;
    final origin = source != null ? PwaImageOrigin.userUpload : null;
    if (active.visions.isEmpty) {
      // Draft → resume the Fast Path; returningToStudio skips the cinematic.
      // Pin the title ONLY if the user renamed it (title != the Room-based
      // default) — otherwise leave it null so the card reads "Untitled Space"
      // and the name keeps tracking the Room, matching pre-refresh behaviour.
      final renamed = active.title != _titleForRoom(repo, active.roomId);
      return base.copyWith(
        project: descriptor,
        source: source,
        sourceOrigin: origin,
        selectedRoomId: active.roomId,
        selectedAtmosphereId: atmo,
        returningToStudio: true,
        activeTitleOverride: renamed ? active.title : null,
      );
    }
    // Active project (has Visions) → Ayden Architect. If the URL carried a valid
    // `?vision=` for a NON-current vision, restore that preview (§6).
    final routeVision = restore.route?.visionId;
    final preview =
        (routeVision != null &&
            routeVision != active.currentVisionId &&
            active.visions.any((v) => v.versionId == routeVision))
        ? routeVision
        : null;
    return base.copyWith(
      phase: PwaPhase.architect,
      project: descriptor,
      source: source,
      sourceOrigin: origin,
      selectedRoomId: active.roomId,
      messages: active.messages,
      versions: active.visions,
      currentVisionId: active.currentVisionId,
      previewVisionId: preview,
      selectedAtmosphereId: atmo,
      activeTitleOverride: active.title,
    );
  }

  final PwaExperienceRepository _repo;

  /// Durable store (staging) or `null` (mock). The controller's single write
  /// seam is [_syncActiveProject] → [_persistRemote]; reads stay on [_repo].
  final PwaPersistenceRepository? _persistence;

  /// Serialises durable saves so rapid mutations persist IN ORDER, never
  /// concurrently — the simplest local ordering (no queue/stream/state machine).
  Future<void> _saveChain = Future.value();

  /// Step 5 — the [AydenImageSource] whose bytes are DURABLY persisted as the
  /// project's original. Compared by object identity: only a real Replace-photo
  /// (setSource installs a NEW source object) flags a re-upload, so Rename /
  /// Room / Atmosphere saves (which reuse the same object) upload zero originals.
  /// Set only after the durable save succeeds, so a failed upload re-uploads on
  /// retry. Never assigned in mock (no durable chain).
  AydenImageSource? _persistedSource;

  // Real UUIDs (id / idempotency_key are uuid columns in staging). The same
  // UUID is created once and reused on retry — no derived/remote id.
  String _nextId(String prefix) => const Uuid().v4();
  int _nextOrder() => state.versions.isEmpty
      ? 1
      : (state.versions.map((v) => v.order).reduce((a, b) => a > b ? a : b) +
            1);

  PwaAtmosphere _atmosphere(String id) => state.atmospheres.firstWhere(
    (a) => a.id == id,
    orElse: () => state.atmospheres.first,
  );

  /// Concise pre-confirmation copy for the confirmation cards (§12/§13).
  String switchProposalText(String atmosphereId) =>
      _repo.switchProposal(_atmosphere(atmosphereId));
  String refineSummaryText(String instruction) =>
      _repo.refineSummary(instruction);

  // ── Entry (continuous scroll) ───────────────────────────────────────────────

  void setSource(
    AydenImageSource src, {
    PwaImageOrigin origin = PwaImageOrigin.userUpload,
  }) {
    state = state.copyWith(source: src, sourceOrigin: origin);
    _syncActiveProject(bumpUpdated: false); // persist the Draft on upload
  }

  void removeSource() => state = state.copyWith(clearSource: true);

  /// Fast-path ROOM choice — pure selection, NO generation / version / backend.
  /// null returns to Ayden auto-detect.
  void selectRoom(String? roomId) {
    state = roomId == null
        ? state.copyWith(clearRoom: true)
        : state.copyWith(selectedRoomId: roomId);
    _syncActiveProject(
      bumpUpdated: false,
    ); // update the Draft (no-op pre-upload)
  }

  /// Fast-path ATMOSPHERE choice — pure selection, NO generation / version.
  void selectEntryAtmosphere(String atmosphereId) {
    state = state.copyWith(selectedAtmosphereId: atmosphereId);
    _syncActiveProject(
      bumpUpdated: false,
    ); // update the Draft (no-op pre-upload)
  }

  /// The primary action: one photo, one click → the first Ayden Signature
  /// vision, shown as the first rich message in the conversation.
  Future<void> generateFirstVision() async {
    if (state.generating) return;
    // Returning from "Back to Studio" (versions already exist) → resume the
    // Architect instead of duplicating the first vision.
    if (state.versions.isNotEmpty) {
      state = state.copyWith(phase: PwaPhase.architect);
      return;
    }
    // §Generate 1 — validate the local creation session (Room may be Ayden
    // Decide / null; Atmosphere defaults to Ayden Signature). A photo is required.
    if (state.source == null) return;
    state = state.copyWith(phase: PwaPhase.loading, generating: true);
    await _repo.simulateGeneration();
    final chosen = _atmosphere(state.selectedAtmosphereId ?? 'ayden_signature');
    final v1 = PwaVision(
      versionId: _nextId('v'),
      projectId: state.project.projectId,
      visionNumber: 1,
      title: chosen.name,
      atmosphereId: chosen.id,
      actionType: PwaActionType.signature,
      afterAsset: chosen.visionAsset,
      order: _nextOrder(),
      isCurrent: true,
    );
    final intro = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.ayden,
      kind: PwaMessageKind.reveal,
      text: _repo.firstVisionIntro(),
      visionId: v1.versionId,
      chips: const [
        'What do you think?',
        'Make it warmer',
        'More natural light',
        'Open the kitchen',
      ],
    );
    // §Generate 2-8 — the creation becomes a Project now: commit the first Vision
    // into state (phase STAYS loading, so Architect is NOT revealed yet), then
    // durably persist (upload original + create row + Vision + current/cover) and
    // AWAIT the save chain BEFORE settling. Exactly ONE project is created.
    state = state.copyWith(
      versions: [v1],
      currentVisionId: v1.versionId,
      selectedAtmosphereId: chosen.id,
      messages: [intro],
    );
    _syncActiveProject();
    await _saveChain;
    if (state.saveState == PwaSaveState.error) {
      // §Failure — persistence failed: undo the in-memory exposure and remain on
      // Create (source/Room/Atmosphere preserved) with the save error visible. No
      // Architect, no My Projects card.
      _repo.deleteProject(state.project.projectId);
      state = PwaState(
        phase: PwaPhase.entry,
        project: state.project,
        atmospheres: state.atmospheres,
        source: state.source,
        sourceOrigin: state.sourceOrigin,
        selectedRoomId: state.selectedRoomId,
        selectedAtmosphereId: state.selectedAtmosphereId,
        library: _repo.listProjects(),
        librarySort: state.librarySort,
        librarySearch: state.librarySearch,
        saveState: PwaSaveState.error,
      );
      return;
    }
    // §Generate 9-10 — reveal Architect (the project is now visible in My Projects).
    state = state.copyWith(phase: PwaPhase.architect, generating: false);
  }

  // ── In-architect actions ────────────────────────────────────────────────

  /// SWITCH_ATMOSPHERE step 1 (§13) — STAGE an atmosphere for confirmation.
  /// Selecting the current atmosphere (or the already-pending one) clears the
  /// pending state. NO version, NO conversation message on selection alone.
  void stageAtmosphere(String atmosphereId) {
    if (state.generating) return;
    final currentAtmo = state.sourceVision?.atmosphereId;
    if (atmosphereId == currentAtmo ||
        atmosphereId == state.pendingAtmosphereId) {
      cancelPendingAtmosphere();
      return;
    }
    state = state.copyWith(
      pendingAtmosphereId: atmosphereId,
      selectedAtmosphereId: atmosphereId,
    );
  }

  /// SWITCH_ATMOSPHERE — clear the staged atmosphere (Cancel).
  void cancelPendingAtmosphere() {
    state = state.copyWith(
      clearPending: true,
      selectedAtmosphereId: state.sourceVision?.atmosphereId,
    );
  }

  /// SWITCH_ATMOSPHERE step 2 (§13) — CONFIRM: create exactly one child vision
  /// from the source vision, storing the chosen atmosphere. Future cost: 1 Space
  /// (informational only — NO wallet/ledger/debit in this mock).
  Future<void> applyAtmosphere() async {
    if (state.generating) return;
    final atmosphereId = state.pendingAtmosphereId;
    final parent = state.sourceVision;
    if (atmosphereId == null || parent == null) return;
    final atmo = _atmosphere(atmosphereId);

    final userMsg = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.user,
      kind: PwaMessageKind.text,
      text: 'Switch to ${atmo.name}',
    );
    final loadingMsg = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.ayden,
      kind: PwaMessageKind.loading,
    );
    state = state.copyWith(
      generating: true,
      clearPending: true,
      selectedAtmosphereId: atmosphereId,
      messages: [...state.messages, userMsg, loadingMsg],
    );
    await _repo.simulateGeneration();

    final v = _newVision(
      parent: parent,
      atmosphereId: atmosphereId,
      actionType: PwaActionType.switchAtmosphere,
      afterAsset: atmo.visionAsset,
      title: atmo.name,
      sourceMessageId: userMsg.id,
    );
    final aydenMsg = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.ayden,
      kind: PwaMessageKind.reveal,
      text: _repo.switchIntro(atmo),
      visionId: v.versionId,
    );
    _commitNewVision(
      v,
      replaceLoadingId: loadingMsg.id,
      revealMsg: aydenMsg,
      atmosphereId: atmosphereId,
    );
  }

  /// A typed line → ADVICE (text only, no version) or REFINE (advice + an
  /// "Apply this change" offer).
  void sendUserText(String raw) {
    final text = raw.trim();
    if (text.isEmpty || state.generating) return;
    final intent = classifyTextIntent(text);
    final userMsg = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.user,
      kind: PwaMessageKind.text,
      text: text,
    );
    final PwaMessage aydenMsg;
    if (intent == PwaIntent.advice) {
      aydenMsg = PwaMessage(
        id: _nextId('m'),
        role: PwaRole.ayden,
        kind: PwaMessageKind.text,
        text: _repo.adviceResponse(text),
      );
    } else {
      // REFINE (and SWITCH-as-text) → advice preface + Apply action. No version
      // is created until the user explicitly applies it.
      aydenMsg = PwaMessage(
        id: _nextId('m'),
        role: PwaRole.ayden,
        kind: PwaMessageKind.text,
        text: _repo.refineAdvice(text),
        pendingRefine: text,
        chips: const ['Apply this change'],
      );
    }
    state = state.copyWith(messages: [...state.messages, userMsg, aydenMsg]);
    // §12 — advice/refine talk updates the conversation but never a vision;
    // persist the chat so it is restored on resume, without reordering.
    if (state.versions.isNotEmpty) _syncActiveProject(bumpUpdated: false);
  }

  /// REFINE cancel (§12) — dismiss a pending "Apply this change" offer without
  /// creating any version (keeps the advice text, drops the action).
  void dismissRefine(String messageId) {
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id == messageId)
            PwaMessage(
              id: m.id,
              role: m.role,
              kind: m.kind,
              text: m.text,
              visionId: m.visionId,
            )
          else
            m,
      ],
    );
  }

  /// REFINE apply (§12) — creates exactly one child vision from the SOURCE
  /// vision. Future cost: 1 Space (informational only — NO debit in this mock).
  Future<void> applyRefine(String instruction) async {
    if (state.generating) return;
    final parent = state.sourceVision;
    if (parent == null) return;
    final loadingMsg = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.ayden,
      kind: PwaMessageKind.loading,
    );
    state = state.copyWith(
      generating: true,
      messages: [...state.messages, loadingMsg],
    );
    await _repo.simulateGeneration();

    final refineIndex = state.versions
        .where((v) => v.actionType == PwaActionType.refine)
        .length;
    final v = _newVision(
      parent: parent,
      atmosphereId: parent.atmosphereId,
      actionType: PwaActionType.refine,
      afterAsset: _repo.refineVisionAsset(refineIndex),
      title: instruction,
      instruction: instruction,
    );
    final aydenMsg = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.ayden,
      kind: PwaMessageKind.reveal,
      text: _repo.refineApplied(instruction),
      visionId: v.versionId,
    );
    _commitNewVision(v, replaceLoadingId: loadingMsg.id, revealMsg: aydenMsg);
  }

  // ── Version navigation & lineage ──────────────────────────────────────────

  /// §15 — PREVIEW an older version in the Full Reveal (filmstrip click). Does
  /// NOT change the current vision, delete or overwrite anything.
  void previewVision(String versionId) {
    if (!state.versions.any((v) => v.versionId == versionId)) return;
    state = state.copyWith(previewVisionId: versionId);
  }

  /// Stop previewing → back to the current vision in the Full Reveal.
  void clearPreview() => state = state.copyWith(clearPreview: true);

  /// V7 — step the Full Reveal to the previous / next existing vision in
  /// chronological order (global + chat "Vision N of M" arrows). PREVIEW only:
  /// creates no version, never changes the current vision or lineage. No-op at
  /// the ends.
  void previewPrevious() {
    final chrono = state.versionsChronological;
    final i = state.previewedIndex;
    if (i <= 0 || chrono.isEmpty) return;
    previewVision(chrono[i - 1].versionId);
  }

  void previewNext() {
    final chrono = state.versionsChronological;
    final i = state.previewedIndex;
    if (i < 0 || i >= chrono.length - 1) return;
    previewVision(chrono[i + 1].versionId);
  }

  /// §16 SET AS CURRENT — updates which existing version is current. Creates NO
  /// version and does not alter lineage; clears any preview/continue-from state.
  void setCurrentVision(String versionId) {
    if (!state.versions.any((v) => v.versionId == versionId)) return;
    final target = state.versions.firstWhere((v) => v.versionId == versionId);
    state = state.copyWith(
      currentVisionId: versionId,
      clearPreview: true,
      clearSourceVision: true,
      selectedAtmosphereId: target.atmosphereId,
      versions: [
        for (final v in state.versions)
          v.copyWith(isCurrent: v.versionId == versionId),
      ],
    );
  }

  /// §16 CONTINUE FROM THIS VISION — sets [versionId] as the parent context for
  /// the NEXT confirmed Refine/Atmosphere action (the future child's
  /// parentVersionId). Creates nothing immediately; shows the vision and drops a
  /// clear conversation marker. Does NOT change which version is "current".
  void continueFromVision(String versionId) {
    final v = _find(versionId);
    if (v == null) return;
    final marker = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.ayden,
      kind: PwaMessageKind.text,
      text:
          'Continuing from Vision ${v.visionNumber}. '
          'Your next change will branch from it.',
    );
    state = state.copyWith(
      sourceVisionId: versionId,
      previewVisionId: versionId,
      selectedAtmosphereId: v.atmosphereId,
      messages: [...state.messages, marker],
    );
  }

  /// §26 — "Back home": return to the Studio HERO (offset 0) while preserving
  /// photo, room, atmosphere, project, versions and conversation. The
  /// [returningToStudio] flag tells the freshly-mounted entry screen to land on
  /// the hero without replaying the cinematic (skip → promise); the Hero CTA
  /// then resumes the preserved Fast Path.
  void returnToStudio() => state = state.copyWith(
    phase: PwaPhase.entry,
    clearPreview: true,
    clearPending: true,
    returningToStudio: true,
  );

  /// Consumed by the entry screen once it has repositioned after a return.
  void consumeReturnToStudio() {
    if (state.returningToStudio) {
      state = state.copyWith(returningToStudio: false);
    }
  }

  PwaVision? _find(String versionId) {
    for (final v in state.versions) {
      if (v.versionId == versionId) return v;
    }
    return null;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  PwaVision _newVision({
    required PwaVision parent,
    required String atmosphereId,
    required PwaActionType actionType,
    required String afterAsset,
    required String title,
    String? sourceMessageId,
    String instruction = '',
  }) {
    return PwaVision(
      versionId: _nextId('v'),
      projectId: state.project.projectId,
      visionNumber: state.versions.length + 1,
      title: title,
      atmosphereId: atmosphereId,
      actionType: actionType,
      afterAsset: afterAsset,
      order: _nextOrder(),
      parentVersionId: parent.versionId,
      sourceMessageId: sourceMessageId,
      instruction: instruction,
      isCurrent: true,
    );
  }

  void _commitNewVision(
    PwaVision v, {
    required String replaceLoadingId,
    required PwaMessage revealMsg,
    String? atmosphereId,
  }) {
    final versions = [
      for (final old in state.versions) old.copyWith(isCurrent: false),
      v,
    ];
    final messages = [
      for (final m in state.messages)
        if (m.id != replaceLoadingId) m,
      revealMsg,
    ];
    state = state.copyWith(
      generating: false,
      versions: versions,
      currentVisionId: v.versionId,
      // The new child becomes the current AND the source for the next linear
      // change; any one-shot preview / continue-from override is consumed.
      clearPreview: true,
      clearSourceVision: true,
      clearPending: true,
      selectedAtmosphereId: atmosphereId ?? state.selectedAtmosphereId,
      messages: messages,
    );
    // §12 — a Refine / Atmosphere vision updates the project (count, cover,
    // freshness) and re-sorts it to the top of "Recently updated".
    _syncActiveProject();
  }

  // ── My Projects library (Batch 2.3) ───────────────────────────────────────

  PwaProject _descriptor(PwaProjectSnapshot s) => PwaProject(
    projectId: s.projectId,
    originalAsset: s.originalImageAsset,
    title: s.title,
  );

  /// Meaningful default title once a project has its first vision (§4/§12):
  /// Room-based ("Living Room Concept") — or a descriptive space name when the
  /// room was left to Ayden Decide. Never the ambiguous "New Space".
  String _defaultTitle() => _titleForRoom(_repo, state.selectedRoomId);

  /// The auto-derived Room-based title (shared by [_defaultTitle] and the boot
  /// restore, so both agree on what an un-renamed name looks like).
  static String _titleForRoom(PwaExperienceRepository repo, String? roomId) {
    final label = repo.roomLabel(roomId);
    return label == 'Your space' ? 'Open-plan Living Space' : '$label Concept';
  }

  /// Snapshot the ACTIVE session into the library (upsert). Persists once a
  /// photo is uploaded — a Draft (no Vision yet) is a real, durable project so
  /// it survives a refresh (§ point 2); a project with Visions is `active`.
  /// No-op before any upload. [bumpUpdated] re-stamps the freshness/ordering.
  void _syncActiveProject({bool bumpUpdated = true}) {
    final isDraft = state.versions.isEmpty;
    // Step 6A — a zero-Vision creation is a LOCAL session, NOT a durable Project:
    // no row, no Storage upload, no My Projects card until Generate commits the
    // first Vision. (Photo/Room/Atmosphere edits still call here but no-op for a
    // Draft; a generated project persists normally, incl. Replace-photo.)
    if (isDraft) return;
    final existing = _repo.openProject(state.project.projectId);
    final atmoId =
        state.currentVision?.atmosphereId ??
        state.selectedAtmosphereId ??
        'ayden_signature';
    final snapshot = PwaProjectSnapshot(
      projectId: state.project.projectId,
      // A Draft's name tracks the current Room until renamed; a real project's
      // title is fixed at its first Vision (then changed only via rename).
      title: isDraft
          ? (state.activeTitleOverride ?? _defaultTitle())
          : (existing?.title ?? _defaultTitle()),
      originalImageAsset: state.project.originalAsset,
      roomId: state.selectedRoomId,
      roomLabel: _repo.roomLabel(state.selectedRoomId),
      selectedAtmosphereId: atmoId,
      atmosphereLabel: _atmosphere(atmoId).name,
      visions: state.versions,
      messages: state.messages,
      currentVisionId: state.currentVisionId, // null while a Draft
      coverVisionId: state.currentVisionId, // null while a Draft
      createdOrder: existing?.createdOrder ?? _repo.nextLibraryOrder(),
      updatedOrder: bumpUpdated
          ? _repo.nextLibraryOrder()
          : (existing?.updatedOrder ?? _repo.nextLibraryOrder()),
      updatedLabel: bumpUpdated
          ? 'Updated today'
          : (existing?.updatedLabel ?? 'Updated today'),
      status: isDraft ? PwaProjectStatus.draft : PwaProjectStatus.active,
      source: state.source,
    );
    _repo.saveProject(snapshot); // in-memory working library (UI reads this)
    state = state.copyWith(library: _repo.listProjects());
    // The single durable write seam (staging only): non-destructive saveProject.
    // Step 5 — flag a replaced original ONLY when the photo actually changed, so
    // Rename/Room/Atmosphere never re-upload; mark it persisted on success so a
    // retry of the SAME source does not re-upload.
    final src = state.source;
    final replaceOriginal = src != null && !identical(src, _persistedSource);
    _enqueueDurable((p) async {
      await p.saveProject(snapshot, replaceOriginal: replaceOriginal);
      _persistedSource = src;
    });
  }

  /// Serialises every durable side-effect through [_saveChain] so they apply IN
  /// ORDER, never concurrently, and surfaces a discreet Saving/Saved/Error. A
  /// failure is surfaced (not hidden) and does NOT block the next operation —
  /// the next [_syncActiveProject] resends the full current snapshot. The
  /// simplest local ordering: a single Future tail, no queue/stream/engine.
  /// No-op in mock (`_persistence == null`).
  void _enqueueDurable(Future<void> Function(PwaPersistenceRepository) op) {
    final p = _persistence;
    if (p == null) return;
    if (mounted) state = state.copyWith(saveState: PwaSaveState.saving);
    _saveChain = _saveChain
        .then((_) => op(p))
        .then((_) {
          if (mounted) state = state.copyWith(saveState: PwaSaveState.saved);
        })
        .catchError((Object _) {
          if (mounted) state = state.copyWith(saveState: PwaSaveState.error);
        });
  }

  /// Open the My Projects library (persists the in-progress project first).
  void openLibrary() {
    if (state.versions.isNotEmpty) _syncActiveProject(bumpUpdated: false);
    state = state.copyWith(
      phase: PwaPhase.projects,
      clearPreview: true,
      clearPending: true,
      library: _repo.listProjects(),
    );
  }

  /// RESUME a saved project — restore its photo, Room, Atmosphere, every Vision,
  /// the current Vision and the full conversation, and land in the Architect.
  /// Creates NO vision and starts NO generation.
  Future<void> openProject(String projectId, {String? previewVisionId}) async {
    final s = _repo.openProject(projectId);
    if (s == null) return;
    // §8 — a persisted zero-Vision Draft opens on the Fast Path, NEVER in the
    // Architect (which dereferences `previewedVision!` and would crash). Restores
    // its photo/Room/Atmosphere/title with versions empty and no current/preview
    // Vision (the getters enforce currentVision==previewedVision==null).
    if (s.visions.isEmpty) {
      _openDraftState(s);
      return;
    }
    // BEFORE-CARD fix — a generated project opened from My Projects carries NO
    // in-memory original: the working library came from `loadLibrary`, which
    // never fetches bytes (only boot-from-URL hydrated them, which is why the
    // Before pane was blank until F5). Rehydrate the EXACT original via the same
    // seam as boot and AWAIT it BEFORE settling Architect, so the first Architect
    // frame already has the Before. No phase/URL change while awaiting → the
    // settle is atomic and keeps a single /architect history entry.
    var source = s.source;
    final p = _persistence;
    if (source == null && p != null) {
      // Hydrate from Storage; returns null for a bundle-asset original, whose
      // Before then falls back to the (working) bundle Image.asset.
      source = await pwaHydrateOriginal(p, s);
    }
    _settleArchitect(s, source, previewVisionId);
  }

  /// Emit the settled Architect state for [s] with its already-hydrated [source]
  /// (never emitted before hydration completes, so the Before is present on the
  /// FIRST frame). Applies a valid non-current [previewVisionId] (`?vision=`).
  void _settleArchitect(
    PwaProjectSnapshot s,
    AydenImageSource? source,
    String? previewVisionId,
  ) {
    final preview =
        (previewVisionId != null &&
            previewVisionId != s.currentVisionId &&
            s.visions.any((v) => v.versionId == previewVisionId))
        ? previewVisionId
        : null;
    state = PwaState(
      phase: PwaPhase.architect,
      project: _descriptor(s),
      atmospheres: state.atmospheres,
      source: source,
      sourceOrigin: source != null ? PwaImageOrigin.userUpload : null,
      selectedRoomId: s.roomId,
      messages: s.messages,
      versions: s.visions,
      currentVisionId: s.currentVisionId,
      previewVisionId: preview,
      selectedAtmosphereId: s.selectedAtmosphereId ?? 'ayden_signature',
      generating: false,
      library: _repo.listProjects(),
      librarySort: state.librarySort,
      librarySearch: state.librarySearch,
      activeTitleOverride: s.title, // adopt the opened project's name
    );
  }

  /// NEW PROJECT — persist the current project (if any), then start a fresh
  /// draft: clear the photo, reset Room to Ayden Decide and Atmosphere to Ayden
  /// Signature, clear Visions/chat, and land on the Hero. Saved projects survive.
  void newProject() {
    if (state.versions.isNotEmpty) _syncActiveProject(bumpUpdated: false);
    // A fresh Draft auto-titles from its Room: no override (fresh PwaState).
    final draft = _repo.createDraftProject();
    state = PwaState(
      phase: PwaPhase.entry,
      project: _descriptor(draft),
      atmospheres: state.atmospheres,
      selectedAtmosphereId: 'ayden_signature',
      generating: false,
      returningToStudio: true, // land on the Hero, no cinematic replay
      library: _repo.listProjects(),
      librarySort: state.librarySort,
      librarySearch: state.librarySearch,
    );
  }

  /// §7 — apply a durable route to the state (Back/Forward + boot). Idempotent;
  /// re-applying the current route is a no-op. NEVER pushes the URL — the sync
  /// layer does that, loop-guarded. Assumes [route] is already normalized.
  void applyRoute(PwaRoute route) {
    switch (route.page) {
      case PwaPage.home:
        // '/' is a clean Hero: reset the active session (persisted projects stay
        // in the library). Distinct from returnToStudio, which preserves state.
        state = PwaState(
          phase: PwaPhase.entry,
          project: _repo.project(),
          atmospheres: state.atmospheres,
          selectedAtmosphereId: 'ayden_signature',
          returningToStudio: true,
          library: _repo.listProjects(),
          librarySort: state.librarySort,
          librarySearch: state.librarySearch,
        );
      case PwaPage.projects:
        if (state.phase != PwaPhase.projects) openLibrary();
      case PwaPage.architect:
        final id = route.projectId;
        if (id == null) return;
        if (state.phase != PwaPhase.architect || state.activeProjectId != id) {
          // Reopen (hydrates the original + applies ?vision after settling).
          openProject(id, previewVisionId: route.visionId);
        } else {
          // Already open → just apply the ?vision selection.
          final v = route.visionId;
          if (v != null &&
              v != state.currentVisionId &&
              state.versions.any((x) => x.versionId == v)) {
            previewVision(v);
          } else if (state.previewVisionId != null) {
            state = state.copyWith(clearPreview: true);
          }
        }
      case PwaPage.draft:
        final id = route.projectId;
        if (id == null) return;
        if (state.activeProjectId == id &&
            state.phase == PwaPhase.entry &&
            state.versions.isEmpty) {
          return;
        }
        final s = _repo.openProject(id);
        if (s == null) return;
        if (s.visions.isNotEmpty) {
          openProject(id);
        } else {
          _openDraftState(s);
        }
    }
  }

  /// Load a Draft snapshot into the entry / Fast-Path state (no cinematic).
  void _openDraftState(PwaProjectSnapshot s) {
    state = PwaState(
      phase: PwaPhase.entry,
      project: _descriptor(s),
      atmospheres: state.atmospheres,
      source: s.source,
      sourceOrigin: s.source != null ? PwaImageOrigin.userUpload : null,
      selectedRoomId: s.roomId,
      selectedAtmosphereId: s.selectedAtmosphereId ?? 'ayden_signature',
      library: _repo.listProjects(),
      librarySort: state.librarySort,
      librarySearch: state.librarySearch,
      activeTitleOverride: s.title != _titleForRoom(_repo, s.roomId)
          ? s.title
          : null,
    );
  }

  void renameProject(String projectId, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    _repo.renameProject(projectId, t);
    // Keep the active session's title in step if it is the one being renamed;
    // pin it so a Draft's later Room/Atmosphere change can't overwrite the name.
    final isActive = projectId == state.project.projectId;
    final project = isActive
        ? PwaProject(
            projectId: projectId,
            originalAsset: state.project.originalAsset,
            title: t,
          )
        : state.project;
    state = state.copyWith(
      project: project,
      library: _repo.listProjects(),
      // Pin the active Draft/project name so a later Room/Atmosphere change or a
      // refresh can't overwrite it.
      activeTitleOverride: isActive ? t : state.activeTitleOverride,
    );
    _enqueueDurable((p) => p.renameProject(projectId, t)); // durable rename
  }

  /// Duplicate a project. In mock (offline) this is the instant in-memory copy.
  /// In staging the RPC `deep_duplicate_project` is authoritative: we adopt the
  /// UUID it returns IMMEDIATELY (§ point 1) — the copy carries ONE id across the
  /// controller, the local library, Supabase and every later action, and stays
  /// identical after a refresh. No id mapper, no temporary local id, no refresh
  /// needed to converge.
  Future<PwaProjectSnapshot?> duplicateProject(String projectId) async {
    final p = _persistence;
    if (p == null) {
      final dup = _repo.duplicateProject(projectId); // instant local copy
      state = state.copyWith(library: _repo.listProjects());
      return dup;
    }
    if (mounted) state = state.copyWith(saveState: PwaSaveState.saving);
    // Run AFTER any pending saves so the source is durably present first.
    final op = _saveChain.then((_) => p.duplicateProject(projectId));
    _saveChain = op.then((_) {}, onError: (_) {}); // keep the chain alive
    try {
      final copy = await op; // snapshot with the RPC's authoritative UUID
      _repo.saveProject(copy); // adopt that same UUID locally — no refresh
      if (mounted) {
        state = state.copyWith(
          library: _repo.listProjects(),
          saveState: PwaSaveState.saved,
        );
      }
      return copy;
    } catch (_) {
      if (mounted) state = state.copyWith(saveState: PwaSaveState.error);
      return null;
    }
  }

  void deleteProject(String projectId) {
    _repo.deleteProject(projectId); // instant local removal
    state = state.copyWith(library: _repo.listProjects());
    _enqueueDurable(
      (p) => p.softDeleteProject(projectId),
    ); // durable soft-delete
  }

  void setLibrarySort(PwaProjectSort order) =>
      state = state.copyWith(librarySort: order);

  void setLibrarySearch(String query) =>
      state = state.copyWith(librarySearch: query);
}
