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

enum PwaPhase { upload, loading, architect }

/// Injectable repository. Overridden in tests with a zero-delay mock.
final pwaRepositoryProvider = Provider<PwaExperienceRepository>(
  (ref) => MockPwaExperienceRepository(),
);

final pwaControllerProvider =
    StateNotifierProvider<PwaController, PwaState>((ref) {
  return PwaController(ref.watch(pwaRepositoryProvider));
});

class PwaState {
  const PwaState({
    required this.phase,
    required this.project,
    required this.atmospheres,
    this.source,
    this.messages = const [],
    this.versions = const [],
    this.currentVisionId,
    this.selectedAtmosphereId,
    this.generating = false,
  });

  final PwaPhase phase;
  final PwaProject project;
  final List<PwaAtmosphere> atmospheres;
  final AydenImageSource? source;
  final List<PwaMessage> messages;
  final List<PwaVision> versions;
  final String? currentVisionId;
  final String? selectedAtmosphereId;
  final bool generating;

  bool get hasSource => source != null;
  int get versionCount => versions.length;

  PwaVision? get currentVision {
    for (final v in versions) {
      if (v.versionId == currentVisionId) return v;
    }
    return versions.isEmpty ? null : versions.last;
  }

  /// Versions in chronological order (oldest first).
  List<PwaVision> get versionsChronological {
    final list = [...versions]..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  PwaState copyWith({
    PwaPhase? phase,
    AydenImageSource? source,
    bool clearSource = false,
    List<PwaMessage>? messages,
    List<PwaVision>? versions,
    String? currentVisionId,
    String? selectedAtmosphereId,
    bool? generating,
  }) {
    return PwaState(
      phase: phase ?? this.phase,
      project: project,
      atmospheres: atmospheres,
      source: clearSource ? null : (source ?? this.source),
      messages: messages ?? this.messages,
      versions: versions ?? this.versions,
      currentVisionId: currentVisionId ?? this.currentVisionId,
      selectedAtmosphereId: selectedAtmosphereId ?? this.selectedAtmosphereId,
      generating: generating ?? this.generating,
    );
  }
}

class PwaController extends StateNotifier<PwaState> {
  PwaController(this._repo)
      : super(PwaState(
          phase: PwaPhase.upload,
          project: _repo.project(),
          atmospheres: _repo.atmospheres(),
        ));

  final PwaExperienceRepository _repo;
  int _seq = 0;

  String _nextId(String prefix) => '$prefix${++_seq}';
  int _nextOrder() =>
      state.versions.isEmpty ? 1 : (state.versions.map((v) => v.order).reduce((a, b) => a > b ? a : b) + 1);

  PwaAtmosphere _atmosphere(String id) =>
      state.atmospheres.firstWhere((a) => a.id == id,
          orElse: () => state.atmospheres.first);

  // ── Upload phase ──────────────────────────────────────────────────────────

  void setSource(AydenImageSource src) =>
      state = state.copyWith(source: src);

  void removeSource() => state = state.copyWith(clearSource: true);

  /// The primary action: one photo, one click → the first Ayden Signature
  /// vision, shown as the first rich message in the conversation.
  Future<void> generateFirstVision() async {
    if (state.generating) return;
    state = state.copyWith(phase: PwaPhase.loading, generating: true);
    await _repo.simulateGeneration();
    final signature = _atmosphere('ayden_signature');
    final v1 = PwaVision(
      versionId: _nextId('v'),
      projectId: state.project.projectId,
      visionNumber: 1,
      title: 'Ayden Signature',
      atmosphereId: signature.id,
      actionType: PwaActionType.signature,
      afterAsset: signature.visionAsset,
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
      selectedAtmosphereId: signature.id,
      messages: [intro],
    );
  }

  // ── In-architect actions ────────────────────────────────────────────────

  /// SWITCH_ATMOSPHERE — tapping an atmosphere creates a new child vision from
  /// the current one and inserts it into the conversation.
  Future<void> selectAtmosphere(String atmosphereId) async {
    if (state.generating) return;
    if (atmosphereId == state.currentVision?.atmosphereId) return;
    final parent = state.currentVision;
    if (parent == null) return;
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
    _commitNewVision(v,
        replaceLoadingId: loadingMsg.id, revealMsg: aydenMsg, atmosphereId: atmosphereId);
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
  }

  /// REFINE apply — creates a child vision from the current one.
  Future<void> applyRefine(String instruction) async {
    if (state.generating) return;
    final parent = state.currentVision;
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

    final refineIndex =
        state.versions.where((v) => v.actionType == PwaActionType.refine).length;
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

  // ── Version navigation ────────────────────────────────────────────────────

  /// Set the current vision without a chat message (desktop selection).
  void setCurrentVision(String versionId) {
    if (!state.versions.any((v) => v.versionId == versionId)) return;
    final target = state.versions.firstWhere((v) => v.versionId == versionId);
    state = state.copyWith(
      currentVisionId: versionId,
      selectedAtmosphereId: target.atmosphereId,
      versions: [
        for (final v in state.versions) v.copyWith(isCurrent: v.versionId == versionId),
      ],
    );
  }

  /// Continue from an older vision: makes it current AND drops a clear
  /// conversation marker so the next generation branches from it.
  void continueFromVision(String versionId) {
    if (!state.versions.any((v) => v.versionId == versionId)) return;
    setCurrentVision(versionId);
    final v = state.versions.firstWhere((x) => x.versionId == versionId);
    final marker = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.ayden,
      kind: PwaMessageKind.text,
      text: 'You are now continuing from Vision ${v.visionNumber}.',
    );
    state = state.copyWith(messages: [...state.messages, marker]);
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
      selectedAtmosphereId: atmosphereId ?? state.selectedAtmosphereId,
      messages: messages,
    );
  }
}
