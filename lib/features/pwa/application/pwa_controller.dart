/// Batch 2 — the PWA state machine (Riverpod StateNotifier).
///
/// Owns the conversation, the branched version tree, the current selection and
/// the upload → loading → architect phase. It never imports GenerationService /
/// SupabaseService / StatusService / RevenueCat: a generation is asked of an
/// INJECTED [PwaGenerationService] and nothing else.
///
/// There is exactly one generation code path. The controller does not know, and
/// must not ask, whether a backend exists: staging injects the real service and
/// mock injects the offline one. What it does enforce is that a failed
/// generation stays a failure — no fixture is ever substituted for a render.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/media/ayden_image_source.dart';
import '../data/mock_pwa_experience_repository.dart';
import '../data/pwa_experience_repository.dart';
import '../data/pwa_generation_service.dart';
import '../data/pwa_image_url_resolver.dart';
import '../data/pwa_mock_generation_service.dart';
import '../data/pwa_pending_generation.dart';
import '../data/pwa_persistence_repository.dart';
import '../data/pwa_project_serialization.dart';
import '../data/pwa_repository_error.dart';
import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';
import 'pwa_route.dart';
import '../l10n/pwa_l10n.dart';
import '../../../core/providers/locale_provider.dart';

/// `entry` is the CREATE session (`/create`); `home` is the dashboard (`/`).
enum PwaPhase {
  home,
  entry,
  loading,
  architect,
  firstReveal,
  reveal,
  projects,
  profile,
}

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

/// The generation seam. The DEFAULT is the offline mock service, so a plain
/// build is the offline experience and nothing reaches a network by accident.
/// The staging boot overrides it with [PwaStagingGenerationService]; tests
/// override it with a fake. Widgets never read it — only the controller does.
final pwaGenerationServiceProvider = Provider<PwaGenerationService>(
  (ref) => PwaMockGenerationService(ref.watch(pwaRepositoryProvider)),
);

/// Where an in-flight generation is remembered across a reload. In-memory by
/// default (mock / tests keep nothing); the staging boot overrides it with the
/// `localStorage`-backed store.
final pwaPendingGenerationStoreProvider = Provider<PwaPendingGenerationStore>(
  (ref) => PwaMemoryPendingGenerationStore(),
);

/// Turns a private Storage path into a renderable URL. `null` offline, where
/// every image reference is a bundle asset and nothing needs signing.
final pwaImageUrlResolverProvider = Provider<PwaImageUrlResolver?>(
  (ref) => null,
);

final pwaControllerProvider = StateNotifierProvider<PwaController, PwaState>((
  ref,
) {
  return PwaController(
    ref.watch(pwaRepositoryProvider),
    generation: ref.watch(pwaGenerationServiceProvider),
    persistence: ref.watch(pwaPersistenceProvider),
    pending: ref.watch(pwaPendingGenerationStoreProvider),
    restore: ref.watch(pwaBootRestoreProvider),
    // READ, not watch: the controller must not be rebuilt (and the whole
    // conversation lost) because someone changed the interface language.
    localeCode: () => ref.read(localeProvider).languageCode,
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
    this.pending,
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

  /// A generation this browser had already asked for when it was reloaded.
  /// Non-null → the controller replays it with the SAME idempotency key, which
  /// returns the existing vision if the first request had in fact succeeded.
  final PwaPendingGeneration? pending;
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
        // With nothing durable to open, a project URL has to fall back to the
        // Hero. Profile does not: it depends on no project, so a person who
        // opens `/profile` before making anything lands on Profile — the same
        // rule `PwaRoute.normalize` already states for it.
        route: route == null
            ? null
            : (route.page == PwaPage.profile ? PwaRoute.profile : PwaRoute.home),
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
          (norm.page == PwaPage.draft ||
              norm.page == PwaPage.architect ||
              norm.page == PwaPage.reveal)) {
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

/// Fold a PENDING generation into a boot restore, making ITS project the active
/// session so the controller can replay it.
///
/// This is not a detail. A first-vision generation that failed leaves a project
/// with ZERO visions, and [pwaResolveBootRestore] deliberately hides those (Step
/// 6A): they are not displayable and never a valid URL target. So without this,
/// the pending record could never become active, the replay guard would refuse
/// every time, and a paid-for retry would be unreachable — which is exactly what
/// was observed after the 2026-08-06 incident.
///
/// The project is loaded EXPLICITLY by id, bypassing that filter, and only when
/// a pending record names it. Best-effort: if it cannot be loaded, the boot is
/// the one it would have been anyway.
Future<PwaBootRestore> pwaRestoreWithPending(
  PwaPersistenceRepository p,
  PwaBootRestore base,
  PwaPendingGeneration pending,
) async {
  // A SETTLED record is a note for later, not a destination. Once it stopped
  // being consumed by a replay it lives on indefinitely, and pulling its
  // project to the front on every boot would hijack the URL: refreshing on
  // /projects/{other}/architect landed on the failed project instead. If the
  // boot already has somewhere to be, that wins and the note simply waits.
  if (pending.failed &&
      base.active != null &&
      base.active!.projectId != pending.projectId) {
    return base;
  }
  if (base.active?.projectId == pending.projectId) {
    return PwaBootRestore(
      library: base.library,
      active: base.active,
      activeSource: base.activeSource,
      route: base.route,
      legacyHidden: base.legacyHidden,
      pending: pending,
    );
  }
  try {
    final target = await p.loadProject(pending.projectId);
    if (target == null) {
      // The row is gone: the record describes nothing and must not be replayed.
      return base;
    }
    return PwaBootRestore(
      library: base.library,
      active: target,
      activeSource: await pwaHydrateOriginal(p, target),
      // The URL stays whatever it was; the replay drives the screen from there.
      route: base.route,
      legacyHidden: base.legacyHidden,
      pending: pending,
    );
  } catch (_) {
    return base;
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
    this.refineContextVisionId,
    this.generationError,
    this.generationErrorCode,
    this.generationRetryable = false,
    this.billingRefusal = '',
    this.visionBrief = '',
  });

  final PwaPhase phase;
  final PwaProject project;
  final List<PwaAtmosphere> atmospheres;
  final AydenImageSource? source;
  final PwaImageOrigin? sourceOrigin;

  /// The free text this session was STARTED with — Create's Step 4, recorded
  /// once at submit so the Design Session can show the person their own words
  /// while Ayden works.
  ///
  /// It is a RECORD, not an editing surface: Step 4's `TextEditingController`
  /// remains the only place the text is typed, and this is written exactly
  /// once, by [generateFirstVision]. Empty when the step was skipped, which is
  /// the normal case. `_freshSession` resets it with everything else.
  ///
  /// The generation request does NOT read this — it takes the argument it was
  /// called with, and a retry replays the persisted `PwaPendingGeneration`,
  /// which has always carried `userInstruction`. So this field can never
  /// change what is sent.
  final String visionBrief;

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

  /// UI-only: the vision the user asked to refine, carried back from the Full
  /// Reveal so the conversation can say what it is about to change and focus the
  /// composer. Never persisted, never a message — the user writes their own.
  final String? refineContextVisionId;

  /// The user-facing message of the LAST generation failure, or null when the
  /// last attempt succeeded. A generation that fails produces this and nothing
  /// else: no vision, no cover, no fixture standing in for a render.
  final String? generationError;

  /// The SEMANTIC code behind [generationError].
  ///
  /// [generationError] is English and is written when the failure happens;
  /// this is what the UI actually renders, through
  /// `PwaL10n.errorForCode`. Keeping both means a person who switches
  /// language while an error is on screen sees it change with them, and a
  /// code this build has never heard of still shows the English sentence
  /// rather than nothing at all.
  final String? generationErrorCode;

  /// Whether that failure is worth retrying (a timeout, an unreachable backend)
  /// as opposed to terminal (an expired session, a forbidden project).
  final bool generationRetryable;

  /// The billing state named by the LAST refusal, or empty.
  ///
  /// Separate from [generationErrorCode] because it answers a different
  /// question: the code says a generation failed, this says WHICH paywall the
  /// Billing Engine's refusal calls for. Only the backend ever writes it — the
  /// browser keeps no counter of its own, so it cannot invent a paywall (§9).
  final String billingRefusal;

  /// The vision behind [refineContextVisionId], if it still exists.
  PwaVision? get refineContextVision => _byId(refineContextVisionId);

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
      case PwaPhase.home:
        return PwaRoute.home;
      case PwaPhase.projects:
        return PwaRoute.projects;
      case PwaPhase.profile:
        return PwaRoute.profile;
      case PwaPhase.architect:
        final v = previewVisionId;
        final vid = (v != null && v != currentVisionId) ? v : null;
        return PwaRoute(
          PwaPage.architect,
          projectId: project.projectId,
          visionId: vid,
        );
      case PwaPhase.reveal:
      case PwaPhase.firstReveal:
        // The Reveal always names the vision it is showing — that is the whole
        // point of the durable URL. `mode=first` marks the one-off unveiling.
        return PwaRoute(
          PwaPage.reveal,
          projectId: project.projectId,
          visionId: previewedVision?.versionId,
          firstLook: phase == PwaPhase.firstReveal,
        );
      case PwaPhase.loading:
      case PwaPhase.entry:
        // Step 6A — a pre-Generate creation session is `/create`: never a
        // durable `/projects/{id}/draft` URL (there is no durable project yet).
        return PwaRoute.create;
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
    String? refineContextVisionId,
    bool clearRefineContext = false,
    String? generationError,
    String? generationErrorCode,
    bool? generationRetryable,
    String? billingRefusal,
    bool clearGenerationError = false,
    String? visionBrief,
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
      refineContextVisionId: clearRefineContext
          ? null
          : (refineContextVisionId ?? this.refineContextVisionId),
      generationErrorCode: clearGenerationError
          ? null
          : (generationErrorCode ?? this.generationErrorCode),
      generationError: clearGenerationError
          ? null
          : (generationError ?? this.generationError),
      generationRetryable: clearGenerationError
          ? false
          : (generationRetryable ?? this.generationRetryable),
      billingRefusal: clearGenerationError
          ? ''
          : (billingRefusal ?? this.billingRefusal),
      visionBrief: clearSource ? '' : (visionBrief ?? this.visionBrief),
    );
  }
}

class PwaController extends StateNotifier<PwaState> {

  /// How this controller learns the current language.
  ///
  /// A `StateNotifier` has neither a BuildContext nor a `ref`, and giving it a
  /// second copy of the copy would be exactly the duplication the l10n layer
  /// exists to prevent. So the PROVIDER injects a reader over the SAME
  /// `localeProvider` the app root watches, and a chip written here is always
  /// the same language as a label written in a widget.
  ///
  /// The default is English, which is what a directly-constructed controller
  /// (every existing test) got before this parameter existed — so no test had
  /// to change and none silently started depending on a locale.
  final String Function() _localeCode;

  static String _englishOnly() => 'en';

  PwaL10n get _l10n => pwaL10nFor(Locale(_localeCode()));

  PwaController(
    this._repo, {
    required PwaGenerationService generation,
    required PwaPendingGenerationStore pending,
    PwaPersistenceRepository? persistence,
    PwaBootRestore? restore,
    String Function()? localeCode,
  }) : _generation = generation,
       _pending = pending,
       _persistence = persistence,
       _localeCode = localeCode ?? _englishOnly,
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
      // The restored project is, by definition, what the backend already holds.
      final active = r.active;
      if (active != null) _adoptPersisted(active, r.activeSource);
    }
    // A generation was in flight when the tab was reloaded. Replaying it with
    // the same key is what makes the refresh free: the backend returns the
    // vision it already made rather than making (and charging for) a second.
    //
    // Two records do NOT mean that, and neither may be replayed on its own:
    //   • one that already FAILED — the answer is known and the person was told;
    //   • one too OLD to still be running — a live record is a couple of minutes
    //     old at most, so one from yesterday describes something long finished.
    // Both would start a brand-new paid render nobody asked for, again on the
    // next reload and the one after that. Observed 2026-08-08: reopening the
    // site began rendering immediately, from a record a failure had left behind
    // the previous evening. So the failure is put back on screen instead, and
    // only the Retry button — an explicit act — runs it again.
    final p = r?.pending;
    if (p == null) return;
    if (!p.isReplayableAt(DateTime.now())) {
      Future<void>.microtask(() async {
        if (!mounted || state.activeProjectId != p.projectId) return;
        await _failGeneration(_lastAttemptFailed);
      });
      return;
    }
    Future<void>.microtask(() => _replayPending(p));
  }

  /// What a boot can honestly say about an attempt that failed in an earlier
  /// session: it did not finish, and it can be tried again. Nothing about
  /// whether the engine had started — that was said at the time, and guessing
  /// now would be worse than saying less.
  static const PwaGenerationFailure _lastAttemptFailed = PwaGenerationFailure(
    code: 'LAST_ATTEMPT_FAILED',
    userMessage: "Ayden couldn't complete this vision. You can try again.",
    retryable: true,
  );

  /// Choose the FIRST-frame screen from the durable restore (§ boot order):
  /// no project → Hero; Draft → entry/Fast-Path (photo + cinematic skipped);
  /// active project → Ayden Architect. Pure + synchronous so nothing flashes.
  static PwaState _initialState(
    PwaExperienceRepository repo,
    PwaBootRestore? restore,
  ) {
    final base = PwaState(
      // The dashboard is the front door now; Create is a deliberate step.
      phase: PwaPhase.home,
      project: repo.project(),
      atmospheres: repo.atmospheres(),
      selectedAtmosphereId: 'ayden_signature',
      library: restore?.library ?? repo.listProjects(),
    );
    final active = restore?.active;
    if (active == null) {
      // No durable project, but the URL may still name another top-level page.
      if (restore?.route?.page == PwaPage.projects) {
        return base.copyWith(phase: PwaPhase.projects);
      }
      if (restore?.route?.page == PwaPage.create) {
        return base.copyWith(phase: PwaPhase.entry);
      }
      if (restore?.route?.page == PwaPage.profile) {
        return base.copyWith(phase: PwaPhase.profile);
      }
      return base; // Home
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
    final isReveal = restore.route?.page == PwaPage.reveal;
    final isFirstLook = isReveal && (restore.route?.firstLook ?? false);
    final routeVision = restore.route?.visionId;
    final validRouteVision =
        routeVision != null &&
        active.visions.any((v) => v.versionId == routeVision);
    // Architect carries `?vision=` only for a NON-current vision; the Reveal
    // always shows exactly the vision its URL names (normalize already proved it
    // belongs to THIS project).
    final preview = isReveal
        ? (validRouteVision ? routeVision : active.currentVisionId)
        : ((validRouteVision && routeVision != active.currentVisionId)
              ? routeVision
              : null);
    return base.copyWith(
      phase: isFirstLook
          ? PwaPhase.firstReveal
          : (isReveal ? PwaPhase.reveal : PwaPhase.architect),
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

  /// The ONLY way a vision image comes into existence. Injected; never
  /// constructed here, never bypassed, never substituted on failure.
  final PwaGenerationService _generation;

  /// Remembers an in-flight generation so a reload can replay it idempotently.
  final PwaPendingGenerationStore _pending;

  /// Durable store (staging) or `null` (mock). The controller's single write
  /// seam is [_syncActiveProject] → [_persistRemote]; reads stay on [_repo].
  final PwaPersistenceRepository? _persistence;

  /// Everything the durable row would contain, as of the last time this client
  /// KNOWS the backend and the session agreed — either because a save succeeded
  /// or because the project was just loaded from the backend.
  ///
  /// Its whole purpose is to answer "would this save change anything?". Looking
  /// at a project is not editing it, but the save seam is called on every
  /// navigation (openLibrary, returnToStudio, newProject), and each call used to
  /// issue an UPDATE. The row's own trigger then stamped `updated_at`, so simply
  /// opening a project moved it to the top of "Recently updated" and bumped its
  /// revision. `bumpUpdated: false` never prevented that — it only held the
  /// CLIENT counter still, and the server clock does not read it.
  String? _persistedSignature;

  /// The identity of a snapshot as the DATABASE would store it.
  ///
  /// Covers exactly the columns [pwaRecordsFromSnapshot] writes, plus the child
  /// ids — so a new vision, a new message, a rename, a cover change or a
  /// deliberate freshness bump all register as different, while re-opening an
  /// unchanged project does not. Deliberately NOT the in-memory source bytes:
  /// a replaced photo is signalled separately, by `replaceOriginal`.
  static String _signatureOf(PwaProjectSnapshot s) => [
    s.projectId,
    s.title,
    s.status.name,
    s.roomId ?? '',
    s.roomLabel,
    s.selectedAtmosphereId ?? '',
    s.atmosphereLabel,
    s.originalImageAsset,
    s.currentVisionId ?? '',
    s.coverVisionId ?? '',
    '${s.createdOrder}',
    '${s.updatedOrder}',
    for (final v in s.visions) v.versionId,
    for (final m in s.messages) m.id,
  ].join('\u0000'); // a separator no field value can contain

  /// The idempotency key of the generation currently being attempted. Kept
  /// across a RETRY of the same logical generation (so the backend recognises
  /// it as one operation) and dropped once it succeeds — a deliberate second
  /// generation must be a new key, or it would silently replay the first.
  String? _activeGenerationKey;

  /// Serialises durable saves so rapid mutations persist IN ORDER, never
  /// concurrently — the simplest local ordering (no queue/stream/state machine).
  Future<void> _saveChain = Future.value();

  /// Set when the NEXT url reconciliation must replace the current history entry
  /// instead of pushing a new one. Purely a navigation concern — it changes no
  /// persistence, no lifecycle, no state.
  bool _replaceNextNav = false;

  /// Read-and-clear, called by the URL sync layer.
  bool consumeReplaceNav() {
    final v = _replaceNextNav;
    _replaceNextNav = false;
    return v;
  }

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

  // ── Real generation ─────────────────────────────────────────────────────────

  /// Make the project GENERATABLE and report where its original photo lives.
  ///
  /// This is the step that turns a local creation session into something a
  /// backend can act on: the project row must exist and the photo must be a
  /// private Storage object the backend is allowed to read. Offline there is
  /// neither, so the bundle asset is reported unchanged.
  Future<PwaOriginalUpload> _prepareOriginal() async {
    final p = _persistence;
    if (p == null) {
      return PwaOriginalUpload.forPath(
        state.project.projectId,
        state.project.originalAsset,
      );
    }
    final src = state.source;
    // Only a genuine Replace-photo re-uploads: a retry of the same generation
    // reuses the object already in Storage.
    final replace = src != null && !identical(src, _persistedSource);
    final upload = await p.prepareGeneration(
      _activeSnapshot(bumpUpdated: false),
      replaceOriginal: replace,
    );
    _persistedSource = src;
    // Adopt the durable path as the session's original, so the in-memory project
    // describes itself exactly as the stored row does — before and after a
    // refresh — and the Before pane has something to resolve if the bytes are
    // ever absent.
    if (mounted && state.project.originalAsset != upload.originalStoragePath) {
      state = state.copyWith(
        project: PwaProject(
          projectId: state.project.projectId,
          originalAsset: upload.originalStoragePath,
          title: state.project.title,
        ),
      );
    }
    return upload;
  }

  /// Describe one generation completely enough to reissue it verbatim.
  PwaPendingGeneration _pendingFor({
    required String idempotencyKey,
    required PwaActionType actionType,
    required String atmosphereId,
    required String originalStoragePath,
    required int visionNumber,
    String parentVisionId = '',
    String userInstruction = '',
    bool confirm = false,
  }) {
    final atmo = _atmosphere(atmosphereId);
    return PwaPendingGeneration(
      projectId: state.project.projectId,
      idempotencyKey: idempotencyKey,
      actionType: pwaActionToDb(actionType),
      roomId: state.selectedRoomId ?? '',
      roomLabel: _repo.roomLabel(state.selectedRoomId),
      atmosphereId: atmo.id,
      atmosphereLabel: atmo.name,
      originalStoragePath: originalStoragePath,
      visionNumber: visionNumber,
      parentVisionId: parentVisionId,
      userInstruction: userInstruction,
      confirm: confirm,
    );
  }

  /// Record the intent, then run it. The record is written BEFORE the call —
  /// that ordering is the whole point: a tab closed mid-render leaves behind the
  /// key that makes the next boot's replay free.
  Future<PwaGeneratedVision> _execute(PwaPendingGeneration p) async {
    // Stamped as leaving NOW — which also takes a settled record back up, so a
    // tab closed during THIS attempt is still replayed for free on the next
    // boot, and one left behind yesterday is not.
    await _pending.write(p.startingAt(DateTime.now()));
    PwaGeneratedVision made;
    try {
      made = await _generation.generate(
        PwaGenerationIntent(
          projectId: p.projectId,
          roomId: p.roomId,
          roomLabel: p.roomLabel,
          atmosphereId: p.atmosphereId,
          atmosphereLabel: p.atmosphereLabel,
          originalImagePath: p.originalStoragePath,
          idempotencyKey: p.idempotencyKey,
          visionNumber: p.visionNumber,
          actionType: p.actionType,
          parentVisionId: p.parentVisionId,
          userInstruction: p.userInstruction,
          confirm: p.confirm,
          // Carried for the advisor's reply, which is conversational text.
          // The generation prompt itself is composed server-side and never
          // sees this value.
          uiLocale: _localeCode(),
        ),
      );
    } on PwaGenerationProcessing catch (held) {
      // NOT a failure. The backend holds a durable claim for this exact
      // operation and is rendering it — started by this tab, an earlier one, or
      // another worker. Showing an error here told the user their generation had
      // gone wrong while the render they had already paid for was still running,
      // and invited them to fire a second one.
      //
      // Mobile's answer to the same 202 is to keep the loading bubble and attach
      // to the reconciliation poll (chat_screen.dart, PR2b Slice 1). This is
      // that attach.
      made = await _awaitHeldGeneration(held.idempotencyKey.isEmpty
          ? p.idempotencyKey
          : held.idempotencyKey);
    }
    await _pending.clear();
    return made;
  }

  /// How long a claim held elsewhere is waited on before the app gives up and
  /// lets the person decide. A real first vision measured 115-125 s; the ceiling
  /// is generous because the alternative — declaring failure early — is what
  /// buys a second paid render.
  static const Duration _kHeldGenerationCeiling = Duration(minutes: 6);
  static const Duration _kHeldGenerationPoll = Duration(seconds: 3);

  /// Wait for a generation somebody else is running, and adopt ITS result.
  ///
  /// Never starts a render, never re-POSTs `/generate` (which would re-run the
  /// refine parser — a real provider call — on every tick). Purely a read of the
  /// durable lifecycle until it settles.
  Future<PwaGeneratedVision> _awaitHeldGeneration(String key) async {
    final deadline = DateTime.now().add(_kHeldGenerationCeiling);
    var unknowns = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_kHeldGenerationPoll);
      if (!mounted) {
        throw const PwaGenerationFailure(
          code: 'CANCELLED',
          userMessage: 'That request was cancelled.',
          retryable: true,
        );
      }
      final s = await _generation.status(key);
      switch (s.state) {
        case 'COMPLETED':
          final v = s.vision;
          if (v != null) return v;
          // COMPLETED with no image is not something to render. Fall through to
          // the same honest failure as any other unusable answer.
          throw const PwaGenerationFailure(
            code: 'MALFORMED_RESPONSE',
            userMessage:
                'Something went wrong creating your vision. Try again.',
            retryable: true,
          );
        case 'FAILED':
          throw PwaGenerationFailure(
            code: s.errorCode.isEmpty ? 'GENERATION_FAILED' : s.errorCode,
            userMessage:
                'This vision could not be completed. You can try again.',
            retryable: true,
          );
        case 'UNKNOWN':
          // The backend has no record either way. A single blip is a dropped
          // packet, not a verdict; a sustained absence means there is nothing
          // to wait for. Neither is worth inventing a failure over on the first
          // tick.
          if (++unknowns >= 5) {
            throw const PwaGenerationFailure(
              code: 'GENERATION_LOST',
              userMessage:
                  "Ayden couldn't find that generation. You can try again.",
              retryable: true,
            );
          }
        default:
          unknowns = 0; // PROCESSING — still running, keep waiting.
      }
    }
    throw const PwaGenerationFailure(
      code: 'TIMEOUT',
      userMessage: 'This is taking longer than expected. Try again.',
      retryable: true,
    );
  }

  /// Everything that can go wrong before the engine is reached — an upload that
  /// fails, a row that cannot be written — reaches the UI as the same kind of
  /// failure as an engine error, because to the person waiting it is one.
  PwaGenerationFailure _asFailure(Object e) {
    if (e is PwaGenerationFailure) return e;
    if (e is PwaGenerationProcessing) {
      // Should be unreachable: `_execute` attaches to the held generation and
      // waits for it rather than letting this escape. Kept as the last resort
      // for a caller that bypasses `_execute` — and worded so the person waits
      // instead of firing a second paid render.
      return const PwaGenerationFailure(
        code: 'PROCESSING',
        userMessage:
            'Ayden is still working on this one. '
            'Give it a moment, then try again.',
        retryable: true,
      );
    }
    if (e is PwaRepositoryError) {
      return PwaGenerationFailure(
        code: e.kind.name,
        userMessage: switch (e.kind) {
          PwaErrorKind.unauthorized =>
            'Your session expired. Reload the page to continue.',
          PwaErrorKind.storage => "Your photo couldn't be uploaded. Try again.",
          PwaErrorKind.configuration =>
            'This build cannot reach a generation backend.',
          _ => "Your vision couldn't be prepared. Try again.",
        },
        retryable:
            e.kind != PwaErrorKind.unauthorized &&
            e.kind != PwaErrorKind.configuration,
      );
    }
    return const PwaGenerationFailure(
      code: 'UNKNOWN',
      userMessage: 'Something went wrong. Try again.',
      retryable: true,
    );
  }

  /// Adopt what the ENGINE decided.
  ///
  /// "Ayden Decide" and "Ayden Signature" are answered by one look at the photo,
  /// server side, and the answer is what keys the per-room DNA. The app used to
  /// keep describing the space as "Your space" for ever, so every later turn —
  /// the advisor, a refine, a switch — was told a placeholder instead of a room.
  ///
  /// Mobile's rule, verbatim: adopt ONLY when nothing was chosen
  /// (`if (returnedRoom.isNotEmpty && _currentRoomType.trim().isEmpty)`), so an
  /// explicit pick is never overridden. Nothing here decides what the room is;
  /// it copies the decision down.
  ///
  /// Returns the atmosphere id the vision should be recorded under. "Ayden
  /// Signature" is a meta-choice, not an atmosphere: stored as-is it made the
  /// session disagree with its own database row the moment the page was
  /// reloaded, and offered the user a "switch" to the atmosphere they were
  /// already in.
  String _adoptResolved(PwaGeneratedVision made, String requested) {
    final roomId = _roomIdForResolved(made.resolvedRoomType);
    if (roomId != null && state.selectedRoomId == null) {
      state = state.copyWith(selectedRoomId: roomId);
    }
    final resolved = made.resolvedAtmosphereId.trim();
    if (resolved.isEmpty || resolved == requested) return requested;
    // Only an atmosphere this build can actually show. An unknown id would fall
    // back to the first card and silently mislabel the vision.
    return state.atmospheres.any((a) => a.id == resolved) ? resolved : requested;
  }

  /// Map the engine's canonical room onto this app's room catalogue.
  ///
  /// Presentation only — the same job mobile's `RoomTypeImages.enLabelForId`
  /// does for the app header. Returns null when the engine named a room this
  /// catalogue does not offer (an exterior it can stage, for instance), and the
  /// selection is then left alone rather than forced onto a wrong card.
  static String? _roomIdForResolved(String resolved) {
    final key = resolved.trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), '');
    if (key.isEmpty) return null;
    for (final entry in _kResolvedRoomIds.entries) {
      if (entry.key == key) return entry.value;
    }
    return null;
  }

  /// Canonical engine room → this catalogue's card id. Keys are normalised
  /// (lower-case, separators stripped) so `living_room`, `Living Room` and
  /// `livingRoom` all land on the same card.
  static const Map<String, String> _kResolvedRoomIds = {
    'livingroom': 'livingRoom',
    'masterbedroom': 'masterBedroom',
    'bedroom': 'bedroom',
    'kitchen': 'kitchen',
    'bathroom': 'bathroom',
    'office': 'homeOffice',
    'homeoffice': 'homeOffice',
    'diningroom': 'diningRoom',
    'kidsroom': 'kidsRoom',
    'terrace': 'terrace',
    'balcony': 'balcony',
    'garden': 'garden',
  };

  /// Build the domain vision for a completed generation.
  ///
  /// The IMAGE is whatever the service produced — a Storage path in staging, a
  /// bundle asset offline — and never anything this method chose. When the
  /// backend persisted the row it also owns the id, so the client adopts it
  /// rather than minting a second identity for the same vision.
  PwaVision _visionFrom(
    PwaGeneratedVision made, {
    required PwaActionType actionType,
    required String atmosphereId,
    required String title,
    required int visionNumber,
    String? parentVersionId,
    String? sourceMessageId,
    String instruction = '',
  }) => PwaVision(
    versionId: made.backendVisionId ?? _nextId('v'),
    projectId: state.project.projectId,
    visionNumber: visionNumber,
    title: title,
    atmosphereId: atmosphereId,
    actionType: actionType,
    afterAsset: made.imagePath,
    order: _nextOrder(),
    parentVersionId: parentVersionId,
    sourceMessageId: sourceMessageId,
    instruction: instruction,
    isCurrent: true,
    remotePersisted: made.backendVisionId != null,
  );

  /// Surface a failure without inventing anything: the loading placeholder is
  /// removed, no vision is created, no cover changes, and the outcome is shown.
  ///
  /// ONE SURFACE PER OUTCOME
  ///
  /// A refusal for money is not an error, it is an answer — and the paywall
  /// states it completely: which state the ledger is in, what a pack costs, how
  /// to buy one. Setting the generic error fields as well put a second,
  /// vaguer sentence on top of it ("Something went wrong. Try again.") for a
  /// request that did not go wrong and must not be tried again unchanged. So a
  /// billing refusal writes ONLY [billingRefusal]; every other failure writes
  /// only the error fields. Nothing writes both.
  ///
  /// WHAT HAPPENS TO THE RECORDED INTENT
  ///
  /// Normally it is stamped as settled and kept: Retry needs the same
  /// idempotency key, and a later boot reads it as "already answered" and
  /// leaves the decision to the person.
  ///
  /// An AUTHORITATIVE billing refusal is the one case where keeping it is
  /// wrong. The backend refused on its 402 seam, declared the attempt
  /// non-retryable, and reported `render_started: false` — no work exists, no
  /// money moved, and replaying the same key can only ever be refused again.
  /// Kept, the record re-raised the paywall on every single cold start, for
  /// ever. It is discarded, and only in that exact case.
  Future<void> _failGeneration(
    PwaGenerationFailure f, {
    String? removeMessageId,
  }) async {
    final billing = f.isBillingRefusal;
    // `copyWith` reads a null as "unchanged", so the error fields cannot be
    // blanked by passing null. Clear the whole outcome group first, then write
    // back exactly one surface.
    state = state.copyWith(
      generating: false,
      messages: removeMessageId == null
          ? state.messages
          : [
              for (final m in state.messages)
                if (m.id != removeMessageId) m,
            ],
      clearGenerationError: true,
    );
    state = billing
        ? state.copyWith(
            // Only a refusal for money sets this, so nothing but the Billing
            // Engine can put a paywall on screen.
            billingRefusal:
                f.billingState.isEmpty ? 'FREE_EXHAUSTED' : f.billingState,
          )
        : state.copyWith(
            generationError: f.userMessage,
            generationErrorCode: f.code,
            generationRetryable: f.retryable,
          );
    if (f.isAuthoritativeBillingRefusal) {
      await _pending.clear();
      return;
    }
    final p = await _pending.read();
    if (p != null && !p.failed) await _pending.write(p.asFailed());
  }

  /// Dismiss a generation error (the user chose to move on).
  void clearGenerationError() =>
      state = state.copyWith(clearGenerationError: true);

  /// Re-run the generation that just failed, with the SAME idempotency key, so
  /// the backend treats it as one operation and can never charge twice.
  Future<void> retryGeneration() async {
    if (state.generating) return;
    final p = await _pending.read();
    if (p == null) return;
    await _replayPending(p);
  }

  /// Run (or re-run) a recorded generation and fold its result into the
  /// session. Shared by the retry button and the after-reload resume, so both
  /// converge on exactly one vision.
  Future<void> _replayPending(PwaPendingGeneration p) async {
    if (!mounted || state.generating) return;
    if (state.activeProjectId != p.projectId) return;
    // Already reconciled (the reload restored the vision the backend made) —
    // nothing to replay, and the record is stale.
    if (state.versions.any((v) => v.visionNumber == p.visionNumber)) {
      await _pending.clear();
      return;
    }
    final isFirst = state.versions.isEmpty;
    // A retry inside the conversation must SHOW that it restarted. The failure
    // banner removed the original placeholder, so without putting one back the
    // retry ran for two silent minutes and read, correctly, as a dead button.
    final loadingMsg = isFirst
        ? null
        : PwaMessage(
            id: _nextId('m'),
            role: PwaRole.ayden,
            kind: PwaMessageKind.loading,
            // A retry says what it is retrying, exactly as the first attempt did.
            workingKind:
                pwaActionFromDb(p.actionType) == PwaActionType.switchAtmosphere
                ? PwaWorkKind.switchAtmosphere
                : PwaWorkKind.refine,
            workingSubject: p.atmosphereLabel,
          );
    state = state.copyWith(
      generating: true,
      phase: isFirst ? PwaPhase.loading : state.phase,
      clearGenerationError: true,
      messages: loadingMsg == null
          ? state.messages
          : [...state.messages, loadingMsg],
    );
    final PwaGeneratedVision made;
    try {
      made = await _execute(p);
    } catch (e) {
      if (!mounted) return;
      await _failGeneration(_asFailure(e), removeMessageId: loadingMsg?.id);
      if (isFirst) state = state.copyWith(phase: PwaPhase.entry);
      return;
    }
    if (!mounted) return;
    _activeGenerationKey = null;
    final action = pwaActionFromDb(p.actionType);
    // Capture what `_adoptResolved` decided instead of discarding it: Ayden's
    // opening line names the direction, and on a delegated Signature the
    // resolved atmosphere is the only one worth naming. Called exactly once,
    // as before — it mutates `selectedRoomId`, so a second call would be a
    // second write.
    final resolvedAtmo = _atmosphere(_adoptResolved(made, p.atmosphereId));
    final v = _visionFrom(
      made,
      actionType: action,
      atmosphereId: p.atmosphereId,
      title: action == PwaActionType.refine
          ? p.userInstruction
          : p.atmosphereLabel,
      visionNumber: p.visionNumber,
      parentVersionId: p.parentVisionId.isEmpty ? null : p.parentVisionId,
      instruction: p.userInstruction,
    );
    final reveal = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.ayden,
      kind: PwaMessageKind.reveal,
      text: switch (action) {
        // The atmosphere the ENGINE resolved — `chosen`, not what was asked
        // for. On a delegated "Ayden Signature" the two differ, and naming the
        // delegation back at the person says nothing about their room.
        PwaActionType.signature => _l10n.firstVisionIntro(resolvedAtmo.name),
        PwaActionType.refine => _repo.refineApplied(p.userInstruction),
        PwaActionType.switchAtmosphere => _repo.switchIntro(
          _atmosphere(p.atmosphereId),
        ),
      },
      visionId: v.versionId,
    );
    if (isFirst) {
      await _settleFirstVision(v, reveal, p.atmosphereId);
    } else {
      _commitNewVision(
        v,
        // Swap the retry's placeholder for the reveal, exactly as the original
        // attempt would have — never leaving a stale "creating…" behind it.
        replaceLoadingId: loadingMsg?.id ?? '',
        revealMsg: reveal,
        atmosphereId: p.atmosphereId,
      );
      // A refine that arrives through RETRY is the same vision as one that
      // arrived first time, so it earns the same free second look. Mobile has no
      // counterpart to compare against — it deliberately never replays a refine
      // (chat_screen.dart skips the pending write for refineV2), so a failed
      // refine there simply stays lost. Recovering it and then withholding the
      // "still missing" report would make THIS path quietly weaker than the
      // direct one, for no reason.
      if (action == PwaActionType.refine) {
        final parent = _visionById(p.parentVisionId);
        unawaited(_kickoffVerify(
          beforePath: parent?.afterAsset ?? '',
          afterPath: made.imagePath,
          changes: made.changes,
          visionId: v.versionId,
        ));
      }
    }
  }

  PwaVision? _visionById(String id) {
    for (final v in state.versions) {
      if (v.versionId == id) return v;
    }
    return null;
  }

  // ── Entry (continuous scroll) ───────────────────────────────────────────────

  void setSource(
    AydenImageSource src, {
    PwaImageOrigin origin = PwaImageOrigin.userUpload,
  }) {
    // A different photo is a different generation: the previous attempt's key
    // must not be reused, or the backend would replay a render of the old one.
    _activeGenerationKey = null;
    state = state.copyWith(
      source: src,
      sourceOrigin: origin,
      clearGenerationError: true,
    );
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

  /// The primary action: one photo, one click → the first REAL vision. The
  /// image comes from the engine; nothing is revealed until it exists and is
  /// durably stored.
  ///
  /// [userInstruction] is the optional free-text brief of Create's Step 4 —
  /// the SAME field mobile's upload screen sends as `desc`, and the same
  /// `user_instruction` the request contract has always carried. It is a
  /// one-shot input for THIS generation, not session state: mobile keeps it in
  /// a local `TextEditingController` and so does the web, which is why it
  /// arrives as an argument rather than as a new field on [PwaState].
  ///
  /// Empty is the normal case — Step 4 is skippable, and an empty string is
  /// exactly what every caller sent before this parameter existed.
  Future<void> generateFirstVision({String userInstruction = ''}) async {
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
    // Set synchronously, BEFORE the first await: a second tap finds `generating`
    // already true and returns, so one click is one upload and one generation.
    state = state.copyWith(
      phase: PwaPhase.loading,
      generating: true,
      clearGenerationError: true,
      // Recorded for the Design Session to show, in the same synchronous write
      // that starts the generation — so the session can never render a beat
      // before it knows what it was asked for.
      visionBrief: userInstruction.trim(),
    );
    final atmosphereId = state.selectedAtmosphereId ?? 'ayden_signature';
    // Kept across a retry of THIS generation, minted fresh for a new one.
    final key = _activeGenerationKey ??= const Uuid().v4();

    final PwaGeneratedVision made;
    try {
      // §Generate 2-4 — the durable project row and the original photo in
      // private Storage FIRST (the backend downloads that exact path and
      // refuses anything outside the caller's namespace), then the engine.
      final upload = await _prepareOriginal();
      made = await _execute(
        _pendingFor(
          idempotencyKey: key,
          actionType: PwaActionType.signature,
          atmosphereId: atmosphereId,
          originalStoragePath: upload.originalStoragePath,
          visionNumber: 1,
          // Trimmed, and empty when skipped — mobile's own rule (`desc` is
          // only sent when non-empty), so a blank Step 4 produces byte-for-byte
          // the request the web already sent.
          userInstruction: userInstruction.trim(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // §Failure — stay on Create with the photo, Room and Atmosphere intact
      // and the real error visible. No vision, no card, no fixture. The pending
      // record survives, so Retry reuses the same key.
      await _failGeneration(_asFailure(e));
      state = state.copyWith(phase: PwaPhase.entry);
      return;
    }
    if (!mounted) return;
    _activeGenerationKey = null;
    // The engine has now answered both delegated questions. Adopt its answers
    // BEFORE the vision is built, so the row this session shows and the row the
    // database holds are the same row.
    final chosen = _atmosphere(_adoptResolved(made, atmosphereId));
    final v1 = _visionFrom(
      made,
      actionType: PwaActionType.signature,
      atmosphereId: chosen.id,
      title: chosen.name,
      visionNumber: 1,
    );
    final intro = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.ayden,
      kind: PwaMessageKind.reveal,
      text: _l10n.firstVisionIntro(chosen.name),
      visionId: v1.versionId,
      chips: [
        _l10n.chipWhatDoYouThink,
        _l10n.chipWarmer,
        _l10n.chipMoreLight,
        // Room-NEUTRAL. These four sit under every result, and "Open the
        // kitchen" under a terrace or a bathroom was a suggestion the person
        // could tap and pay for. All four still travel the same road —
        // `sendUserText` → the canonical turn — so nothing about what a
        // suggestion CAN do has changed; only whether it makes sense to offer.
        _l10n.chipCalmer,
      ],
    );
    await _settleFirstVision(v1, intro, chosen.id);
  }

  /// §Generate 5-10 — commit the first vision, persist the project, and only
  /// then unveil it. The phase STAYS `loading` across the durable save, so the
  /// First Reveal is reached by a real success and never by a timer.
  Future<void> _settleFirstVision(
    PwaVision v1,
    PwaMessage intro,
    String atmosphereId,
  ) async {
    state = state.copyWith(
      versions: [v1],
      currentVisionId: v1.versionId,
      selectedAtmosphereId: atmosphereId,
      messages: [...state.messages, intro],
      generating: true,
    );
    _syncActiveProject();
    await _saveChain;
    if (!mounted) return;
    if (state.saveState == PwaSaveState.error) {
      // §Failure — persistence failed: undo the in-memory exposure and remain on
      // Create (source/Room/Atmosphere preserved) with the error visible. No
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
        generationError: 'Your vision could not be saved. Try again.',
        generationErrorCode: 'SAVE_FAILED',
        generationRetryable: true,
      );
      return;
    }
    // §Generate 9-10 — the project is saved and listed; now UNVEIL it. The
    // first vision earns a full-screen moment before the conversation starts.
    // It REPLACES `/create` in history, so Back from the project returns Home
    // and never to a Create still holding the photo that just became a project.
    _replaceNextNav = true;
    state = state.copyWith(
      phase: PwaPhase.firstReveal,
      previewVisionId: v1.versionId,
      generating: false,
    );
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
      text: _l10n.switchTo(atmo.name),
    );
    final loadingMsg = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.ayden,
      kind: PwaMessageKind.loading,
      // Named, because the person just asked for THIS atmosphere and a switch
      // takes about two minutes. "Switching to Japandi Calm" is the difference
      // between a page that is working and a page that looks stuck.
      workingKind: PwaWorkKind.switchAtmosphere,
      workingSubject: atmo.name,
    );
    state = state.copyWith(
      generating: true,
      clearPending: true,
      selectedAtmosphereId: atmosphereId,
      messages: [...state.messages, userMsg, loadingMsg],
      clearGenerationError: true,
    );
    final key = _activeGenerationKey ??= const Uuid().v4();

    // A switch is a REAL generation, not a relabel: the engine renders the same
    // space in the new atmosphere and returns a new image.
    final PwaGeneratedVision made;
    try {
      final upload = await _prepareOriginal();
      made = await _execute(
        _pendingFor(
          idempotencyKey: key,
          actionType: PwaActionType.switchAtmosphere,
          atmosphereId: atmosphereId,
          originalStoragePath: upload.originalStoragePath,
          visionNumber: state.versions.length + 1,
          parentVisionId: parent.versionId,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await _failGeneration(_asFailure(e), removeMessageId: loadingMsg.id);
      return;
    }
    if (!mounted) return;
    _activeGenerationKey = null;
    _adoptResolved(made, atmosphereId);

    final v = _visionFrom(
      made,
      actionType: PwaActionType.switchAtmosphere,
      atmosphereId: atmosphereId,
      title: atmo.name,
      visionNumber: state.versions.length + 1,
      parentVersionId: parent.versionId,
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

  /// A typed line goes STRAIGHT to the canonical pipeline.
  ///
  /// It used to be classified here — a local keyword heuristic decided
  /// advice-vs-refine and a canned string answered "I'd keep the architecture
  /// intact… Want me to apply it?". That produced two contradictions at once: a
  /// promise that contradicted the instruction, and a question asked while the
  /// generation was already running underneath.
  ///
  /// The decision now belongs to `refine.parser` + `refine.advisor` on the
  /// backend — the same modules mobile uses. This method only posts the user's
  /// words and lets [applyRefine] carry the answer back.
  void sendUserText(String raw) {
    final text = raw.trim();
    if (text.isEmpty || state.generating) return;
    unawaited(_converse(text));
  }

  /// A typed line, judged by the canonical conversational brain BEFORE anything
  /// can be spent on it.
  ///
  /// This used to go straight to [applyRefine], and the real smoke showed what
  /// that costs: "what do you think of this space?" became a paid render and a
  /// permanent Vision titled with the question — which then polluted the
  /// customisation memory every later switch reads.
  ///
  /// The old defence was the refine parser returning no changes. Measured, it
  /// does not: asked directly, `refine.parser` returns a `modify` change for
  /// "what do you think?", for "what do you think of this space?" and for "how
  /// does this room feel to you?". Reading an instruction is its job; deciding
  /// whether a sentence IS one is not.
  ///
  /// Mobile asks a different question first (`POST /chat` → `should_generate`),
  /// and so does this. Nothing local participates in that decision — not a
  /// keyword, not a question mark, not the chip's own text. There is exactly one
  /// brain, and money is only spent when it says so.
  Future<void> _converse(String text) async {
    final userMsg = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.user,
      kind: PwaMessageKind.text,
      text: text,
    );
    final thinking = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.ayden,
      kind: PwaMessageKind.loading,
      // A conversational turn is seconds, not minutes — one honest line, and no
      // phase list pretending a render is under way.
      workingKind: PwaWorkKind.conversation,
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg, thinking],
      clearGenerationError: true,
    );

    // §23 — the ONE language signal, through the canonical mechanism.
    //
    // The adapter forwards `ui_locale` to `main.chat`, which is the SAME
    // function the mobile route calls and which localizes Ayden's reply with
    // `localize_reply`. There is no second translation pass here and none is
    // wanted: the conversational answer comes back in the user's language
    // because the canonical turn was told what it is.
    //
    // This changes what Ayden SAYS. It does not change what Ayden DRAWS: the
    // image prompt is composed server-side by the frozen composer, in English,
    // from structured facts — the locale never reaches it.
    final turn = await _generation.chat(
      projectId: state.project.projectId,
      message: text,
      uiLocale: _localeCode(),
    );
    if (!mounted) return;
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id != thinking.id) m,
      ],
    );

    if (turn.shouldGenerate) {
      // A real edit. From here the already-aligned canonical path takes over —
      // parse, advise, render — with the user's own words, unaltered.
      await applyRefine(text);
      return;
    }

    // A conversation. No claim, no render, no Vision, and nothing added to the
    // lineage the next switch will read.
    final reply = turn.aiMessage.trim();
    state = state.copyWith(
      messages: [
        ...state.messages,
        PwaMessage(
          id: _nextId('m'),
          role: PwaRole.ayden,
          kind: PwaMessageKind.text,
          // `reply` is Ayden's OWN answer and is already in the user's
          // language: the adapter forwards `ui_locale` to the canonical chat
          // turn, which localizes it through `localize_reply`. Only the
          // UI-owned fallback — shown when the canonical turn said nothing at
          // all — is translated here.
          text: reply.isEmpty ? _l10n.noChangeUnderstood : reply,
          chips: turn.suggestions,
        ),
      ],
    );
    // Persist the conversation only; `bumpUpdated: false` so merely talking does
    // not re-sort the library as though the design had changed.
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
  Future<void> applyRefine(String instruction, {bool confirm = false}) async {
    if (state.generating) return;
    final parent = state.sourceVision;
    if (parent == null) return;
    final loadingMsg = PwaMessage(
      id: _nextId('m'),
      role: PwaRole.ayden,
      kind: PwaMessageKind.loading,
      workingKind: PwaWorkKind.refine,
    );
    state = state.copyWith(
      generating: true,
      messages: [...state.messages, loadingMsg],
      clearGenerationError: true,
    );
    final key = _activeGenerationKey ??= const Uuid().v4();

    // The instruction is carried as a structured fact; the engine composes the
    // prompt. The parent vision is named so the backend can verify it belongs
    // to this project before branching from it.
    final PwaGeneratedVision made;
    try {
      final upload = await _prepareOriginal();
      made = await _execute(
        _pendingFor(
          idempotencyKey: key,
          actionType: PwaActionType.refine,
          atmosphereId: parent.atmosphereId,
          originalStoragePath: upload.originalStoragePath,
          visionNumber: state.versions.length + 1,
          parentVisionId: parent.versionId,
          userInstruction: instruction,
          confirm: confirm,
        ),
      );
    } on PwaAnswerRaised catch (answered) {
      // Words, not a render. The conversation continues and nothing was billed.
      if (!mounted) return;
      _activeGenerationKey = null;
      await _pending.clear();
      state = state.copyWith(
        generating: false,
        messages: [
          for (final m in state.messages)
            if (m.id != loadingMsg.id) m,
          PwaMessage(
            id: _nextId('m'),
            role: PwaRole.ayden,
            kind: PwaMessageKind.text,
            text: answered.message,
          ),
        ],
      );
      if (state.versions.isNotEmpty) _syncActiveProject(bumpUpdated: false);
      return;
    } on PwaAdvisoryRaised catch (raised) {
      if (!mounted) return;
      // Ayden objected. That is an ANSWER, not a failure: no vision, no error
      // banner, and the words are the canonical advisor's — never composed here.
      // The instruction is kept on the message so "Continue anyway" can resend
      // it with confirm, exactly as mobile's Continue-anyway does.
      _activeGenerationKey = null;
      await _pending.clear();
      state = state.copyWith(
        generating: false,
        messages: [
          for (final m in state.messages)
            if (m.id != loadingMsg.id) m,
          PwaMessage(
            id: _nextId('m'),
            role: PwaRole.ayden,
            kind: PwaMessageKind.text,
            text: raised.advisory.message,
            pendingRefine: instruction,
            advisoryVerdict: raised.advisory.verdict,
            chips: [_l10n.continueAnyway],
          ),
        ],
      );
      if (state.versions.isNotEmpty) _syncActiveProject(bumpUpdated: false);
      return;
    } catch (e) {
      if (!mounted) return;
      await _failGeneration(_asFailure(e), removeMessageId: loadingMsg.id);
      return;
    }
    if (!mounted) return;
    _activeGenerationKey = null;
    _adoptResolved(made, parent.atmosphereId);

    final v = _visionFrom(
      made,
      actionType: PwaActionType.refine,
      atmosphereId: parent.atmosphereId,
      title: instruction,
      visionNumber: state.versions.length + 1,
      parentVersionId: parent.versionId,
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
    // The image is on screen. NOW ask whether the edit actually landed — a free
    // second look, after the fact, exactly where mobile puts it
    // (`unawaited(_kickoffRefineVerify(mySeq))`). It renders nothing unless the
    // verdict is `incomplete`, so a working refine stays silent.
    unawaited(_kickoffVerify(
      beforePath: parent.afterAsset,
      afterPath: made.imagePath,
      changes: made.changes,
      visionId: v.versionId,
    ));
  }

  /// The verify SECOND call (§14) — free, asynchronous, and never blocking.
  ///
  /// Fail-open by construction: the service already returns null for `verified`
  /// and `unavailable`, so the only thing that ever reaches the conversation is
  /// a KNOWN incomplete result, with the instructions that did not land.
  Future<void> _kickoffVerify({
    required String beforePath,
    required String afterPath,
    required List<Map<String, Object?>> changes,
    required String visionId,
  }) async {
    if (changes.isEmpty || afterPath.isEmpty || beforePath.isEmpty) return;
    final PwaRefineVerification? verdict;
    try {
      verdict = await _generation.verify(
        projectId: state.project.projectId,
        beforePath: beforePath,
        afterPath: afterPath,
        changes: changes,
      );
    } catch (_) {
      return; // a verify NEVER disturbs the image already shown
    }
    if (verdict == null || !mounted) return;
    // Superseded: another generation has landed since, so this report is about
    // a vision the person has already moved past.
    if (state.currentVisionId != visionId) return;
    state = state.copyWith(
      messages: [
        ...state.messages,
        PwaMessage(
          id: _nextId('m'),
          role: PwaRole.ayden,
          kind: PwaMessageKind.text,
          text: verdict.report,
          // The unapplied instruction is carried so a retry is one tap and
          // targets exactly what is missing — mobile's `missingRaws`.
          pendingRefine: verdict.missing.isEmpty ? null : verdict.missing.first,
          chips: verdict.missing.isEmpty ? const [] : const ['Try again'],
        ),
      ],
    );
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

  /// Open the Full Reveal for [versionId] — the secondary, exploration-only
  /// view. Creates nothing, changes no lineage; a vision that does not belong to
  /// the open project is ignored rather than silently swapped for another.
  void openReveal(String versionId) {
    if (!state.versions.any((v) => v.versionId == versionId)) return;
    state = state.copyWith(
      phase: PwaPhase.reveal,
      previewVisionId: versionId,
      clearPending: true,
    );
  }

  /// Leave the Full Reveal and return to the conversation. [focusVisionId] keeps
  /// the reveal's vision selected so the caller can scroll to its message. A
  /// plain return carries no refinement intent.
  void backToConversation({String? focusVisionId}) {
    final keep = focusVisionId ?? state.previewVisionId;
    state = state.copyWith(
      phase: PwaPhase.architect,
      previewVisionId: keep,
      clearPending: true,
      clearRefineContext: true,
    );
  }

  /// "Refine with Ayden" — return to the conversation ABOUT [versionId], with
  /// the composer ready. It sends nothing: the user writes the actual request,
  /// and can drop the context without touching the vision.
  void startRefineContext(String versionId) {
    if (!state.versions.any((v) => v.versionId == versionId)) return;
    state = state.copyWith(
      phase: PwaPhase.architect,
      previewVisionId: versionId,
      refineContextVisionId: versionId,
      clearPending: true,
    );
  }

  /// "Continue with Ayden" — leave the one-off unveiling for the conversation.
  /// The First Reveal is transient: it REPLACES itself in history, so Back from
  /// the Architect goes Home rather than back to a moment already lived.
  void continueToArchitect() {
    if (state.phase != PwaPhase.firstReveal) return;
    _replaceNextNav = true;
    state = state.copyWith(phase: PwaPhase.architect, clearPreview: true);
  }

  /// Drop the refinement context. Creates nothing, changes no vision.
  void clearRefineContext() => state = state.copyWith(clearRefineContext: true);

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

  /// A brand-new local session on [phase]: no photo, Ayden Decide + Ayden
  /// Signature restored, no visions, no chat. The durable library is untouched —
  /// this only clears what lives in memory before Generate.
  PwaState _freshSession(PwaPhase phase) {
    // A new session is a new generation: never inherit the previous key, or the
    // backend would replay the old project's render for the new one.
    _activeGenerationKey = null;
    // A brand-new project has no durable row yet, so nothing is agreed.
    _persistedSignature = null;
    return PwaState(
      phase: phase,
      project: _descriptor(_repo.createDraftProject()),
      atmospheres: state.atmospheres,
      selectedAtmosphereId: 'ayden_signature',
      library: _repo.listProjects(),
      librarySort: state.librarySort,
      librarySearch: state.librarySearch,
    );
  }

  /// "Back home" — the dashboard. Any in-progress creation session is dropped
  /// (it was never durable); saved projects are of course untouched.
  void returnToStudio() {
    if (state.versions.isNotEmpty) _syncActiveProject(bumpUpdated: false);
    state = _freshSession(PwaPhase.home);
  }

  /// Open the Home dashboard. Alias of [returnToStudio] for call sites that
  /// read better as "go home".
  void openHome() => returnToStudio();

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
  /// The ACTIVE session as a snapshot. Pure — it reads state and the working
  /// library and writes nothing, so both the durable save seam and the
  /// pre-generation upload describe the same project the same way.
  PwaProjectSnapshot _activeSnapshot({required bool bumpUpdated}) {
    final isDraft = state.versions.isEmpty;
    final existing = _repo.openProject(state.project.projectId);
    final atmoId =
        state.currentVision?.atmosphereId ??
        state.selectedAtmosphereId ??
        'ayden_signature';
    return PwaProjectSnapshot(
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
      // The TIMESTAMP has to survive this rebuild, because it is what the card
      // localises. Dropping it left the active project falling back to
      // `updatedLabel` — a stored English sentence — so a French reader saw
      // "Updated 4 minutes ago" under their own render. `now` when this write
      // is the one bumping the freshness (it is true, and it is what the
      // database will store), the previous value otherwise.
      updatedAt: bumpUpdated ? DateTime.now() : existing?.updatedAt,
      updatedLabel: bumpUpdated
          ? 'Updated today'
          : (existing?.updatedLabel ?? 'Updated today'),
      status: isDraft ? PwaProjectStatus.draft : PwaProjectStatus.active,
      source: state.source,
    );
  }

  void _syncActiveProject({bool bumpUpdated = true}) {
    final isDraft = state.versions.isEmpty;
    // Step 6A — a zero-Vision creation is a LOCAL session, NOT a durable Project:
    // no row, no Storage upload, no My Projects card until Generate commits the
    // first Vision. (Photo/Room/Atmosphere edits still call here but no-op for a
    // Draft; a generated project persists normally, incl. Replace-photo.)
    if (isDraft) return;
    final snapshot = _activeSnapshot(bumpUpdated: bumpUpdated);
    _repo.saveProject(snapshot); // in-memory working library (UI reads this)
    state = state.copyWith(library: _repo.listProjects());
    // The single durable write seam (staging only): non-destructive saveProject.
    // Step 5 — flag a replaced original ONLY when the photo actually changed, so
    // Rename/Room/Atmosphere never re-upload; mark it persisted on success so a
    // retry of the SAME source does not re-upload.
    final src = state.source;
    final replaceOriginal = src != null && !identical(src, _persistedSource);

    // Nothing to write. Opening a project, returning Home or restoring a route
    // all land here, and an UPDATE with identical values is not free: the row's
    // trigger re-stamps `updated_at`, which reorders the library and tells the
    // user they changed something they only looked at.
    final signature = _signatureOf(snapshot);
    if (!replaceOriginal && signature == _persistedSignature) return;

    _enqueueDurable((p) async {
      await p.saveProject(snapshot, replaceOriginal: replaceOriginal);
      _persistedSource = src;
      _persistedSignature = signature;
    });
  }

  /// Adopt [s] — and the photo it was restored with — as the state the backend
  /// already holds.
  ///
  /// Called wherever a project ARRIVES from the durable store: boot restore,
  /// opening from the library, opening a Draft. Two things must be adopted, and
  /// missing either one still writes:
  ///
  ///  * the SIGNATURE, or the first navigation decides the session diverged and
  ///    re-writes a row that was already correct;
  ///  * the SOURCE, because hydration builds a NEW [AydenImageSource] from the
  ///    stored bytes. The replaced-photo check is by object identity, so a
  ///    freshly hydrated original looks like a photo the user had just swapped
  ///    in — which re-uploaded it AND forced the write past the guard.
  void _adoptPersisted(PwaProjectSnapshot s, [AydenImageSource? source]) {
    _persistedSignature = _signatureOf(s);
    if (source != null) _persistedSource = source;
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

  /// Open Profile. Same shape as [openLibrary] — it persists an in-progress
  /// project first, because leaving the studio by the bottom navigation must
  /// never be the thing that loses work — and then simply changes phase.
  ///
  /// It reads no identity, no entitlement and no account state: those live in
  /// their own providers and the screen watches them directly. This method
  /// exists so the tab is a real destination rather than a modal.
  void openProfile() {
    if (state.versions.isNotEmpty) _syncActiveProject(bumpUpdated: false);
    state = state.copyWith(
      phase: PwaPhase.profile,
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
    // Opening a project is a read. Adopting its stored shape AND its hydrated
    // photo here is what keeps the next navigation from writing a row that is
    // already correct — and from re-uploading an original it just downloaded.
    _adoptPersisted(s, source);
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
    // Always a genuinely empty Create: the previous photo, Room and Atmosphere
    // never leak into the next project.
    state = _freshSession(PwaPhase.entry);
  }

  /// §7 — apply a durable route to the state (Back/Forward + boot). Idempotent;
  /// re-applying the current route is a no-op. NEVER pushes the URL — the sync
  /// layer does that, loop-guarded. Assumes [route] is already normalized.
  void applyRoute(PwaRoute route) {
    switch (route.page) {
      case PwaPage.home:
        // '/' is the dashboard, and it drops any half-finished creation session
        // so Back can never restore a Create still holding the last photo.
        state = _freshSession(PwaPhase.home);
      case PwaPage.create:
        // A create URL always opens an EMPTY creation session unless one is
        // already in progress on screen (a reconcile must not wipe it).
        if (state.phase != PwaPhase.entry) {
          state = _freshSession(PwaPhase.entry);
        }
      case PwaPage.projects:
        if (state.phase != PwaPhase.projects) openLibrary();
      case PwaPage.profile:
        if (state.phase != PwaPhase.profile) openProfile();
      case PwaPage.reveal:
        final rid = route.projectId;
        final rv = route.visionId;
        if (rid == null || rv == null) return;
        if (state.activeProjectId == rid && state.versions.isNotEmpty) {
          if (route.firstLook) {
            if (state.versions.any((v) => v.versionId == rv)) {
              state = state.copyWith(
                phase: PwaPhase.firstReveal,
                previewVisionId: rv,
                clearPending: true,
              );
            }
            return;
          }
          openReveal(rv);
          return;
        }
        // Different project → load it (hydrates the original), then settle the
        // Reveal on the named vision.
        openProject(rid, previewVisionId: rv).then((_) {
          if (!mounted || state.activeProjectId != rid) return;
          if (route.firstLook) {
            state = state.copyWith(
              phase: PwaPhase.firstReveal,
              previewVisionId: rv,
            );
          } else {
            openReveal(rv);
          }
        });
      case PwaPage.architect:
        final id = route.projectId;
        if (id == null) return;
        // Coming back from the Reveal of the SAME project is a phase change, not
        // a reload — never re-hydrate and never push a second history entry.
        if (state.activeProjectId == id && state.phase == PwaPhase.reveal) {
          final v = route.visionId;
          state = state.copyWith(
            phase: PwaPhase.architect,
            previewVisionId: v,
            clearPreview: v == null,
            clearPending: true,
          );
          return;
        }
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
    _adoptPersisted(s, s.source);
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
