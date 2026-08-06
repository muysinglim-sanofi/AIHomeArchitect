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

import 'package:uuid/uuid.dart';

import '../domain/pwa_models.dart';
import '../domain/pwa_project.dart';
import 'pwa_experience_repository.dart';

class MockPwaExperienceRepository implements PwaExperienceRepository {
  MockPwaExperienceRepository({
    this.workDelay = const Duration(seconds: 3),
    this.seedLibrary = true,
  });

  @override
  final Duration workDelay;

  /// Seed the demo library with bundled showcase projects. TRUE for the offline
  /// mock; FALSE in staging, where the library is restored from the durable
  /// backend only (never mixed with fake seeds).
  final bool seedLibrary;

  // Real UUID so the seed project persists to the uuid `id` column in staging.
  final String _projectId = const Uuid().v4();

  @override
  PwaProject project() => PwaProject(
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
      descriptor: 'Warm · Timeless · Balanced',
      isSignature: true,
    ),
    PwaAtmosphere(
      id: 'warm_modern',
      name: 'Warm Modern',
      asset: 'assets/cards/atmospheres/warm_modern.png',
      visionAsset: 'assets/showcase/living_after.jpg',
      descriptor: 'Cozy · Inviting · Sophisticated',
    ),
    PwaAtmosphere(
      id: 'soft_luxury',
      name: 'Soft Luxury',
      asset: 'assets/cards/atmospheres/soft_luxury.png',
      visionAsset: 'assets/showcase/villa_after.jpg',
      descriptor: 'Refined · Elegant · Serene',
    ),
    PwaAtmosphere(
      id: 'japandi_calm',
      name: 'Japandi Calm',
      asset: 'assets/cards/atmospheres/japandi_calm.png',
      visionAsset: 'assets/showcase/smallspace_after.jpg',
      descriptor: 'Minimal · Natural · Peaceful',
    ),
    PwaAtmosphere(
      id: 'nordic_warmth',
      name: 'Nordic Warmth',
      asset: 'assets/cards/atmospheres/nordic_warmth.png',
      visionAsset: 'assets/showcase/bathroom_after.jpg',
      descriptor: 'Bright · Organic · Airy',
    ),
    PwaAtmosphere(
      id: 'tropical_escape',
      name: 'Tropical Escape',
      asset: 'assets/cards/atmospheres/tropical_escape.png',
      visionAsset: 'assets/showcase/facade_after.jpg',
      descriptor: 'Lush · Relaxed · Vibrant',
    ),
  ];

  /// The four stages a real generation actually goes through: the photo is
  /// uploaded, the engine reads the space, it renders, and the result is stored
  /// and resolved. Qualitative on purpose — the backend reports no progress, so
  /// naming the stage is the most that can honestly be said.
  @override
  List<String> loadingSteps() => const [
    'Preparing your photo',
    'Understanding your space',
    'Creating your vision',
    'Finishing the details',
  ];

  @override
  Future<void> simulateGeneration() => workDelay == Duration.zero
      ? Future<void>.value()
      : Future.delayed(workDelay);

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
  String switchProposal(PwaAtmosphere atmosphere) =>
      'A ${atmosphere.name} direction — same architecture and layout, with '
      'materials, palette and light reworked to match the mood.';

  @override
  String refineSummary(String instruction) =>
      'Apply “$instruction” while keeping the architecture intact — adjusting '
      'the materials and lighting to get there.';

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

  // ── My Projects library (Batch 2.3) — in-memory, offline ─────────────────

  List<PwaProjectSnapshot>? _store;
  int _projSeq = 0;
  // Starts above every seed order so freshly created/updated projects always
  // sort as the most recent.
  int _orderSeq = 100;

  List<PwaProjectSnapshot> get _projects =>
      _store ??= (seedLibrary ? _seedLibrary() : <PwaProjectSnapshot>[]);

  static const Map<String, String> _roomLabels = {
    'livingRoom': 'Living Room',
    'masterBedroom': 'Master Bedroom',
    'bedroom': 'Bedroom',
    'kitchen': 'Kitchen',
    'bathroom': 'Bathroom',
    'homeOffice': 'Home Office',
    'diningRoom': 'Dining Room',
    'kidsRoom': 'Kids Room',
    'terrace': 'Terrace',
    'balcony': 'Balcony',
    'garden': 'Garden',
  };

  @override
  String roomLabel(String? roomId) =>
      roomId == null ? 'Your space' : (_roomLabels[roomId] ?? 'Your space');

  @override
  int nextLibraryOrder() => ++_orderSeq;

  @override
  List<PwaProjectSnapshot> listProjects() => [..._projects];

  @override
  PwaProjectSnapshot? openProject(String projectId) {
    for (final p in _projects) {
      if (p.projectId == projectId) return p;
    }
    return null;
  }

  @override
  PwaProjectSnapshot createDraftProject() {
    final o = nextLibraryOrder();
    return PwaProjectSnapshot(
      projectId: const Uuid().v4(),
      title: 'Untitled project',
      originalImageAsset: 'assets/showcase/apartment_before.jpg',
      roomId: null,
      roomLabel: 'Your space',
      selectedAtmosphereId: 'ayden_signature',
      atmosphereLabel: 'Ayden Signature',
      visions: const [],
      messages: const [],
      currentVisionId: null,
      createdOrder: o,
      updatedOrder: o,
      updatedLabel: 'New draft',
      status: PwaProjectStatus.draft,
    );
  }

  @override
  void saveProject(PwaProjectSnapshot project) {
    // Keep the order counter monotonic across restored projects (whose orders
    // come from a prior session) so nextLibraryOrder() never re-bases BELOW them
    // and "most recently updated" stays correct after a refresh.
    if (project.createdOrder > _orderSeq) _orderSeq = project.createdOrder;
    if (project.updatedOrder > _orderSeq) _orderSeq = project.updatedOrder;
    final i = _projects.indexWhere((e) => e.projectId == project.projectId);
    if (i >= 0) {
      _projects[i] = project;
    } else {
      _projects.add(project);
    }
  }

  @override
  void renameProject(String projectId, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    final i = _projects.indexWhere((e) => e.projectId == projectId);
    if (i < 0) return;
    _projects[i] = _projects[i].copyWith(title: t);
  }

  /// P0 deep duplication — a fully INDEPENDENT project graph. Every versionId
  /// and messageId is reallocated, `Vision.projectId` becomes the new id, and
  /// every cross-reference (parent lineage, sourceMessageId, message→vision,
  /// current/cover) is remapped through explicit id maps. No source business
  /// identifier survives (only image asset paths + user-visible copied content),
  /// and no mutable collection is shared, so edits never leak either way.
  @override
  PwaProjectSnapshot? duplicateProject(String projectId) {
    final src = openProject(projectId);
    if (src == null) return null;
    final newId = 'copy-${++_projSeq}';

    // 1/2/3 — allocate the new id and build old→new maps.
    final versionIdMap = <String, String>{
      for (var i = 0; i < src.visions.length; i++)
        src.visions[i].versionId: '$newId-v${i + 1}',
    };
    final messageIdMap = <String, String>{
      for (var i = 0; i < src.messages.length; i++)
        src.messages[i].id: '$newId-m${i + 1}',
    };

    // 4 — copy every Vision, remapping projectId / lineage / sourceMessageId.
    final visions = <PwaVision>[
      for (final v in src.visions)
        PwaVision(
          versionId: versionIdMap[v.versionId]!,
          projectId: newId,
          visionNumber: v.visionNumber,
          title: v.title,
          atmosphereId: v.atmosphereId,
          actionType: v.actionType,
          afterAsset: v.afterAsset,
          order: v.order,
          parentVersionId: v.parentVersionId == null
              ? null
              : versionIdMap[v.parentVersionId],
          sourceMessageId: v.sourceMessageId == null
              ? null
              : messageIdMap[v.sourceMessageId],
          instruction: v.instruction,
          isCurrent: v.isCurrent,
        ),
    ];

    // 5 — copy every message, remapping id + message→vision reference.
    final messages = <PwaMessage>[
      for (final m in src.messages)
        PwaMessage(
          id: messageIdMap[m.id]!,
          role: m.role,
          kind: m.kind,
          text: m.text,
          visionId: m.visionId == null ? null : versionIdMap[m.visionId],
          chips: List<String>.unmodifiable(m.chips),
          pendingRefine: m.pendingRefine,
        ),
    ];

    final o = nextLibraryOrder();
    // 6/7 — remap current/cover and freeze independent collections.
    final dup = PwaProjectSnapshot(
      projectId: newId,
      title: _uniqueCopyTitle(src.title),
      originalImageAsset: src.originalImageAsset,
      roomId: src.roomId,
      roomLabel: src.roomLabel,
      selectedAtmosphereId: src.selectedAtmosphereId,
      atmosphereLabel: src.atmosphereLabel,
      visions: List<PwaVision>.unmodifiable(visions),
      messages: List<PwaMessage>.unmodifiable(messages),
      currentVisionId: src.currentVisionId == null
          ? null
          : versionIdMap[src.currentVisionId],
      coverVisionId: src.coverVisionId == null
          ? null
          : versionIdMap[src.coverVisionId],
      createdOrder: o,
      updatedOrder: o,
      updatedLabel: 'Updated just now',
      status: src.status,
      source: src.source,
    );
    _projects.add(dup);
    return dup;
  }

  /// Deterministic, collision-free copy title: `root Copy`, then ` Copy 2`,
  /// ` Copy 3`… stripping any existing ` Copy N` suffix first so duplicating a
  /// copy never produces `… Copy Copy`.
  String _uniqueCopyTitle(String sourceTitle) {
    final root = sourceTitle.replaceFirst(RegExp(r' Copy(?: \d+)?$'), '');
    final existing = _projects.map((p) => p.title).toSet();
    if (!existing.contains('$root Copy')) return '$root Copy';
    var n = 2;
    while (existing.contains('$root Copy $n')) {
      n++;
    }
    return '$root Copy $n';
  }

  @override
  void deleteProject(String projectId) =>
      _projects.removeWhere((e) => e.projectId == projectId);

  @override
  List<PwaProjectSnapshot> searchProjects(String query) =>
      PwaProjectSnapshot.search(_projects, query);

  @override
  List<PwaProjectSnapshot> sortProjects(PwaProjectSort order) =>
      PwaProjectSnapshot.sortedBy(_projects, order);

  // ── Seed content for visual review (existing local assets only) ───────────

  // Each project has ONE distinct, room-coherent cover (existing local assets),
  // shared by its visions so the card, Full Reveal and history stay consistent
  // and the library reads like a real portfolio (no repeated covers).
  List<PwaProjectSnapshot> _seedLibrary() => [
    _buildSeed(
      id: 'seed-living',
      title: 'Living Room Concept',
      roomId: 'livingRoom',
      roomLabel: 'Living Room',
      atmosphereId: 'ayden_signature',
      atmosphereLabel: 'Ayden Signature',
      beforeAsset: 'assets/showcase/living_before.jpg',
      cover: 'assets/showcase/living_after.jpg', // warm furnished living room
      visionSpecs: const [
        ['signature', 'Ayden Signature'],
        ['refine', 'Make it warmer'],
        ['refine', 'More natural light'],
      ],
      createdOrder: 10,
      updatedOrder: 50,
      updatedLabel: 'Updated today',
    ),
    _buildSeed(
      id: 'seed-bedroom',
      title: 'Bedroom Retreat',
      roomId: 'masterBedroom',
      roomLabel: 'Master Bedroom',
      atmosphereId: 'soft_luxury',
      atmosphereLabel: 'Soft Luxury',
      beforeAsset: 'assets/examples/bedroom.jpg',
      cover: 'assets/showcase/smallspace_after.jpg', // private suite w/ bed
      visionSpecs: const [
        ['signature', 'Soft Luxury'],
        ['refine', 'Warmer bedding'],
      ],
      createdOrder: 20,
      updatedOrder: 40,
      updatedLabel: 'Yesterday',
    ),
    _buildSeed(
      id: 'seed-kitchen',
      title: 'Kitchen Transformation',
      roomId: 'kitchen',
      roomLabel: 'Kitchen',
      atmosphereId: 'warm_modern',
      atmosphereLabel: 'Warm Modern',
      beforeAsset: 'assets/examples/kitchen.jpg',
      cover: 'assets/showcase/apartment_after.jpg', // open-plan kitchen
      visionSpecs: const [
        ['signature', 'Warm Modern'],
        ['refine', 'Open the island'],
        ['refine', 'Brighter counters'],
        ['refine', 'Add warm timber'],
      ],
      createdOrder: 30,
      updatedOrder: 30,
      updatedLabel: '3 days ago',
    ),
    _buildSeed(
      id: 'seed-terrace',
      title: 'Terrace Escape',
      roomId: 'terrace',
      roomLabel: 'Terrace',
      atmosphereId: 'tropical_escape',
      atmosphereLabel: 'Tropical Escape',
      beforeAsset: 'assets/showcase/villa_before.jpg',
      cover:
          'assets/showcase/villa_after.jpg', // pool / garden / outdoor living
      visionSpecs: const [
        ['signature', 'Tropical Escape'],
        ['switch', 'Tropical Escape'],
      ],
      createdOrder: 5,
      updatedOrder: 20,
      updatedLabel: 'Last week',
    ),
    _buildSeed(
      id: 'seed-office',
      title: 'Home Office',
      roomId: 'homeOffice',
      roomLabel: 'Home Office',
      atmosphereId: 'japandi_calm',
      atmosphereLabel: 'Japandi Calm',
      beforeAsset: 'assets/showcase/smallspace_before.jpg',
      // No dedicated office/desk asset exists in the repo → the most coherent
      // calm NEUTRAL interior (never an exterior). Documented mock limitation.
      cover: 'assets/atmospheres/ftue/ftue_nordic_warmth.jpg',
      visionSpecs: const [
        ['signature', 'Japandi Calm'],
      ],
      createdOrder: 2,
      updatedOrder: 10,
      updatedLabel: '2 weeks ago',
    ),
  ];

  PwaProjectSnapshot _buildSeed({
    required String id,
    required String title,
    required String? roomId,
    required String roomLabel,
    required String atmosphereId,
    required String atmosphereLabel,
    required String beforeAsset,
    required String cover,
    required List<List<String>> visionSpecs,
    required int createdOrder,
    required int updatedOrder,
    required String updatedLabel,
  }) {
    final visions = <PwaVision>[];
    final messages = <PwaMessage>[];
    String? parentId;
    for (var i = 0; i < visionSpecs.length; i++) {
      final action = visionSpecs[i][0];
      final label = visionSpecs[i][1];
      final actionType = switch (action) {
        'refine' => PwaActionType.refine,
        'switch' => PwaActionType.switchAtmosphere,
        _ => PwaActionType.signature,
      };
      final vId = '$id-v${i + 1}';
      final isLast = i == visionSpecs.length - 1;
      visions.add(
        PwaVision(
          versionId: vId,
          projectId: id,
          visionNumber: i + 1,
          title: label,
          atmosphereId: atmosphereId,
          actionType: actionType,
          afterAsset: cover,
          order: i + 1,
          parentVersionId: parentId,
          instruction: actionType == PwaActionType.refine ? label : '',
          isCurrent: isLast,
        ),
      );
      if (i > 0) {
        messages.add(
          PwaMessage(
            id: '$id-mu$i',
            role: PwaRole.user,
            kind: PwaMessageKind.text,
            text: actionType == PwaActionType.refine
                ? label
                : 'Switch to $atmosphereLabel',
          ),
        );
      }
      messages.add(
        PwaMessage(
          id: '$id-ma$i',
          role: PwaRole.ayden,
          kind: PwaMessageKind.reveal,
          text: i == 0
              ? firstVisionIntro()
              : (actionType == PwaActionType.refine
                    ? refineApplied(label)
                    : 'Here is your space reimagined in $atmosphereLabel.'),
          visionId: vId,
        ),
      );
      parentId = vId;
    }
    final current = visions.last;
    return PwaProjectSnapshot(
      projectId: id,
      title: title,
      originalImageAsset: beforeAsset,
      roomId: roomId,
      roomLabel: roomLabel,
      selectedAtmosphereId: atmosphereId,
      atmosphereLabel: atmosphereLabel,
      visions: visions,
      messages: messages,
      currentVisionId: current.versionId,
      coverVisionId: current.versionId,
      createdOrder: createdOrder,
      updatedOrder: updatedOrder,
      updatedLabel: updatedLabel,
      status: PwaProjectStatus.active,
    );
  }
}
