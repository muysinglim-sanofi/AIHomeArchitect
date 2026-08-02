/// Batch 2 — the PWA prototype state machine (Riverpod StateNotifier).
///
/// Owns the conversation, the branched version tree, the current selection and
/// the upload → loading → architect phase. Drives the mocked repository only —
/// it never imports GenerationService / SupabaseService / StatusService /
/// RevenueCat. Deterministic: ids come from an internal counter, timing from
/// the repository's injectable delay, so it is fully unit-testable.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/ayden_image_source.dart';
import '../data/mock_pwa_experience_repository.dart';
import '../data/pwa_experience_repository.dart';
import '../domain/pwa_intent.dart';
import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';

enum PwaPhase { entry, loading, architect, projects }

/// Where the current source image came from. Governs mock honesty: only the
/// bundled example may claim a known room type; an arbitrary user upload must
/// NOT be labelled (the real backend will detect it later).
enum PwaImageOrigin { bundledExample, userUpload }

/// Injectable repository. Overridden in tests with a zero-delay mock.
final pwaRepositoryProvider = Provider<PwaExperienceRepository>(
  (ref) => MockPwaExperienceRepository(),
);

final pwaControllerProvider = StateNotifierProvider<PwaController, PwaState>((
  ref,
) {
  return PwaController(ref.watch(pwaRepositoryProvider));
});

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

  /// The id of the project currently loaded in the active session.
  String get activeProjectId => project.projectId;

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
      title: 'Untitled Space',
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

  /// Library filtered by [librarySearch] then sorted by [librarySort].
  List<PwaProjectSnapshot> get visibleProjects => PwaProjectSnapshot.sortedBy(
    PwaProjectSnapshot.search(library, librarySearch),
    librarySort,
  );

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
    );
  }
}

class PwaController extends StateNotifier<PwaState> {
  PwaController(this._repo)
    : super(
        PwaState(
          phase: PwaPhase.entry,
          project: _repo.project(),
          atmospheres: _repo.atmospheres(),
          selectedAtmosphereId: 'ayden_signature', // Ayden's default direction
          library: _repo.listProjects(), // seeded My Projects library
        ),
      );

  final PwaExperienceRepository _repo;
  int _seq = 0;

  String _nextId(String prefix) => '$prefix${++_seq}';
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
  }) => state = state.copyWith(source: src, sourceOrigin: origin);

  void removeSource() => state = state.copyWith(clearSource: true);

  /// Fast-path ROOM choice — pure selection, NO generation / version / backend.
  /// null returns to Ayden auto-detect.
  void selectRoom(String? roomId) => state = roomId == null
      ? state.copyWith(clearRoom: true)
      : state.copyWith(selectedRoomId: roomId);

  /// Fast-path ATMOSPHERE choice — pure selection, NO generation / version.
  void selectEntryAtmosphere(String atmosphereId) =>
      state = state.copyWith(selectedAtmosphereId: atmosphereId);

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
    state = state.copyWith(phase: PwaPhase.loading, generating: true);
    await _repo.simulateGeneration();
    // Honour the fast-path selection (defaults to Ayden Signature).
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
    state = state.copyWith(
      phase: PwaPhase.architect,
      generating: false,
      versions: [v1],
      currentVisionId: v1.versionId,
      selectedAtmosphereId: chosen.id,
      messages: [intro],
    );
    // §12 — the draft becomes a real, listed project on its first vision.
    _syncActiveProject();
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
  String _defaultTitle() {
    final label = _repo.roomLabel(state.selectedRoomId);
    return label == 'Your space' ? 'Open-plan Living Space' : '$label Concept';
  }

  /// Snapshot the ACTIVE session into the library (upsert). No-op until the
  /// project has earned its first vision. [bumpUpdated] re-stamps the freshness
  /// / ordering (true for a new vision, false for chat-only or a passive sync).
  void _syncActiveProject({bool bumpUpdated = true}) {
    if (state.versions.isEmpty) return;
    final existing = _repo.openProject(state.project.projectId);
    final atmoId =
        state.currentVision?.atmosphereId ??
        state.selectedAtmosphereId ??
        'ayden_signature';
    final snapshot = PwaProjectSnapshot(
      projectId: state.project.projectId,
      title: existing?.title ?? _defaultTitle(),
      originalImageAsset: state.project.originalAsset,
      roomId: state.selectedRoomId,
      roomLabel: _repo.roomLabel(state.selectedRoomId),
      selectedAtmosphereId: atmoId,
      atmosphereLabel: _atmosphere(atmoId).name,
      visions: state.versions,
      messages: state.messages,
      currentVisionId: state.currentVisionId,
      coverVisionId: state.currentVisionId,
      createdOrder: existing?.createdOrder ?? _repo.nextLibraryOrder(),
      updatedOrder: bumpUpdated
          ? _repo.nextLibraryOrder()
          : (existing?.updatedOrder ?? _repo.nextLibraryOrder()),
      updatedLabel: bumpUpdated
          ? 'Updated today'
          : (existing?.updatedLabel ?? 'Updated today'),
      status: PwaProjectStatus.active,
      source: state.source,
    );
    _repo.saveProject(snapshot);
    state = state.copyWith(library: _repo.listProjects());
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
  void openProject(String projectId) {
    final s = _repo.openProject(projectId);
    if (s == null) return;
    state = PwaState(
      phase: PwaPhase.architect,
      project: _descriptor(s),
      atmospheres: state.atmospheres,
      source: s.source,
      sourceOrigin: s.source != null ? PwaImageOrigin.userUpload : null,
      selectedRoomId: s.roomId,
      messages: s.messages,
      versions: s.visions,
      currentVisionId: s.currentVisionId,
      selectedAtmosphereId: s.selectedAtmosphereId ?? 'ayden_signature',
      generating: false,
      library: _repo.listProjects(),
      librarySort: state.librarySort,
      librarySearch: state.librarySearch,
    );
  }

  /// NEW PROJECT — persist the current project (if any), then start a fresh
  /// draft: clear the photo, reset Room to Ayden Decide and Atmosphere to Ayden
  /// Signature, clear Visions/chat, and land on the Hero. Saved projects survive.
  void newProject() {
    if (state.versions.isNotEmpty) _syncActiveProject(bumpUpdated: false);
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

  void renameProject(String projectId, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    _repo.renameProject(projectId, t);
    // Keep the active session's title in step if it is the one being renamed.
    final project = projectId == state.project.projectId
        ? PwaProject(
            projectId: projectId,
            originalAsset: state.project.originalAsset,
            title: t,
          )
        : state.project;
    state = state.copyWith(project: project, library: _repo.listProjects());
  }

  PwaProjectSnapshot? duplicateProject(String projectId) {
    final dup = _repo.duplicateProject(projectId);
    state = state.copyWith(library: _repo.listProjects());
    return dup;
  }

  void deleteProject(String projectId) {
    _repo.deleteProject(projectId);
    state = state.copyWith(library: _repo.listProjects());
  }

  void setLibrarySort(PwaProjectSort order) =>
      state = state.copyWith(librarySort: order);

  void setLibrarySearch(String query) =>
      state = state.copyWith(librarySearch: query);
}
