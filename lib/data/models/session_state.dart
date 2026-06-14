import 'dart:convert';

/// Wave 4.10g — Persistent Design Session Stabilization
///
/// `SessionState` is the **persistable snapshot** of an in-progress design
/// session — the conversational + architectural continuity that must survive:
///
///   • cold app restart (process kill / system memory pressure)
///   • hot reload (development; usually preserves state but not guaranteed)
///   • session restore (user navigates Home → reopens an existing project)
///   • browser refresh (web target)
///
/// Without this snapshot, the V2/V3/V4 generation pipeline silently degrades:
/// the backend Wave 4.7.2/4.7.3 protocol expects `structural_identity` and
/// `versions` to round-trip from V1 forward. When those reset to `''` on app
/// restart, the backend sees `present=False source=none` → architectural
/// anchors absent → V2+ hallucinates walls, drops kitchens, restructures the
/// facade. Wave 5.5.12 recovery on the backend re-captures from the original
/// image bytes, but the user-perceived cost (latency + occasional drift) is
/// real. Frontend persistence eliminates the recovery path entirely on the
/// happy flow.
///
/// ## What is persisted
///
/// Protocol round-trip fields (CRITICAL — drives V2+ generation quality):
///   • [structuralIdentity] — JSON token captured at V1 by the backend's
///     `_capture_structural_text`, then round-tripped on every subsequent
///     /generate call.
///   • [versions] — JSON-encoded version ledger (parent-child lineage,
///     timestamps, atmosphere per version, source URLs).
///   • [generationSourceUrl] — editing-chain URL (V2 edits V1's output,
///     V3 edits V2's output, etc.). Reset to original on REBOOT_FRESH.
///   • [iterationCount] — next vision's iteration number.
///
/// Conversational continuity fields (drives UX restore feel):
///   • [currentRoomType] — last selected room type.
///   • [currentStyle] — last selected atmosphere label.
///   • [letAiDecide] / [surpriseMe] — initial intent flags (V1-only
///     semantics but kept for accurate restore of the title chip / greeting).
///   • [pendingDescription] — free-text description from upload screen.
///
/// ## What is NOT persisted here
///
///   • Messages — persisted independently by SupabaseService.insertMessage.
///   • Per-session UI state (scroll offset, reveal slider position, compare
///     mode) — out of scope for Wave 4.10g Phase 1; tracked for follow-up.
///   • Per-vision UI state (currently selected variant in a future
///     multi-candidate flow) — Wave 5 territory.
///
/// ## Schema versioning
///
/// [schemaVersion] is stored alongside the payload so future migrations
/// (adding/renaming fields, reshaping the lineage graph) can detect old
/// snapshots and degrade gracefully instead of crashing.
///
/// ## Mutability
///
/// Immutable + [copyWith] for safe Riverpod-style updates. JSON serialization
/// is symmetric: `SessionState.fromJson(s.toJson())` round-trips losslessly.
class SessionState {
  /// Bump this any time the persisted shape changes. [fromJson] is expected
  /// to handle older versions defensively (or return null to trigger a
  /// fresh capture flow).
  static const int currentSchemaVersion = 1;

  /// The schema version this snapshot was written with. Used by the loader
  /// to decide whether the snapshot is consumable as-is, needs migration,
  /// or must be discarded.
  final int schemaVersion;

  // ── Protocol round-trip fields ────────────────────────────────────────────

  /// Wave 4.7.2 token — JSON-serialized architectural identity captured at V1.
  /// Empty string means "no capture yet"; backend will run fresh capture.
  final String structuralIdentity;

  /// Wave 4.7.3 ledger — JSON-encoded list of VersionRecord entries.
  /// Preserves V1→V2→V3 lineage, branch sources, atmosphere per version.
  /// Empty string means "no versions yet" (V1 is the first generation).
  final String versions;

  /// Wave 4.6.0 editing-chain URL — points to the LATEST output. V2 will
  /// edit this image; V3 will edit V2's output, etc. Null = use original
  /// upload (V1 or REBOOT_FRESH path).
  final String? generationSourceUrl;

  /// BUG A fix — one-shot branch pin. When the user taps "Continue this vision"
  /// on a vision, this holds that vision's `version_id` so the NEXT /generate
  /// sends source_mode=SPECIFIC_VERSION (the backend's resolve_source ignores
  /// the source URL — it needs the version id). Consumed (cleared) after that
  /// generation; persisted so a branch survives a reload before generating.
  final String? branchSourceVersionId;

  /// Next vision's iteration number (1-indexed). V1 = 1, V2 = 2, etc.
  final int iterationCount;

  // ── Conversational continuity fields ──────────────────────────────────────

  /// Last selected room type. Empty when AI-Decide was active at V1.
  final String currentRoomType;

  /// Last selected atmosphere label (UI display string).
  final String currentStyle;

  /// Wave 4.8.5 — true if V1 was generated with "Let AI decide the room"
  /// flag. Kept for accurate restore of greeting + UI chips.
  final bool letAiDecide;

  /// Wave 4.8.5 — true if V1 was generated with "Surprise me" flag.
  final bool surpriseMe;

  /// V1-only free-text description from upload screen.
  final String? pendingDescription;

  /// Wave 5.5.14b — Bimodal intent. One of:
  ///   "preserve" — strip architecture from atmosphere DNA, keep full
  ///                preservation stack. Default for new sessions.
  ///   "creative" — full DNA (incl. architecture), relaxed preservation.
  /// Persisted as the LAST-USED mode so reopen restores the UI toggle;
  /// passed per /generate request (per-generation binding lets V1 be
  /// Preserve and V2 be Creative within the same session).
  final String generationMode;

  const SessionState({
    this.schemaVersion = currentSchemaVersion,
    this.structuralIdentity = '',
    this.versions = '',
    this.generationSourceUrl,
    this.branchSourceVersionId,
    this.iterationCount = 0,
    this.currentRoomType = '',
    this.currentStyle = '',
    this.letAiDecide = false,
    this.surpriseMe = false,
    this.pendingDescription,
    this.generationMode = 'preserve',
  });

  /// Empty / fresh state — used when no snapshot is available.
  factory SessionState.empty() => const SessionState();

  /// Tolerant parse: malformed JSON, missing fields, or schema mismatch
  /// return null (caller decides whether to fall back to empty or trigger
  /// a fresh capture). Returns a valid state on best-effort field matching
  /// when the schema version is recognized.
  static SessionState? fromJsonString(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SessionState.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  factory SessionState.fromJson(Map<String, dynamic> json) {
    // Schema-version check — if we don't recognize the format, return empty
    // (safer than misinterpreting fields). Future migrations slot in here.
    final v = json['schemaVersion'];
    if (v is! int || v < 1 || v > currentSchemaVersion) {
      return SessionState.empty();
    }
    return SessionState(
      schemaVersion: v,
      structuralIdentity: (json['structuralIdentity'] as String?) ?? '',
      versions: (json['versions'] as String?) ?? '',
      generationSourceUrl: json['generationSourceUrl'] as String?,
      branchSourceVersionId: json['branchSourceVersionId'] as String?,
      iterationCount: (json['iterationCount'] as int?) ?? 0,
      currentRoomType: (json['currentRoomType'] as String?) ?? '',
      currentStyle: (json['currentStyle'] as String?) ?? '',
      letAiDecide: (json['letAiDecide'] as bool?) ?? false,
      surpriseMe: (json['surpriseMe'] as bool?) ?? false,
      pendingDescription: json['pendingDescription'] as String?,
      // Wave 5.5.14b — older snapshots without this field default to
      // "preserve" (today's behaviour); no migration needed.
      generationMode: (json['generationMode'] as String?) ?? 'preserve',
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'structuralIdentity': structuralIdentity,
        'versions': versions,
        'generationSourceUrl': generationSourceUrl,
        'branchSourceVersionId': branchSourceVersionId,
        'iterationCount': iterationCount,
        'currentRoomType': currentRoomType,
        'currentStyle': currentStyle,
        'letAiDecide': letAiDecide,
        'surpriseMe': surpriseMe,
        'pendingDescription': pendingDescription,
        'generationMode': generationMode,
      };

  String toJsonString() => jsonEncode(toJson());

  SessionState copyWith({
    String? structuralIdentity,
    String? versions,
    String? generationSourceUrl,
    bool clearGenerationSourceUrl = false,
    String? branchSourceVersionId,
    bool clearBranchSourceVersionId = false,
    int? iterationCount,
    String? currentRoomType,
    String? currentStyle,
    bool? letAiDecide,
    bool? surpriseMe,
    String? pendingDescription,
    bool clearPendingDescription = false,
    String? generationMode,
  }) =>
      SessionState(
        schemaVersion: currentSchemaVersion,
        structuralIdentity: structuralIdentity ?? this.structuralIdentity,
        versions: versions ?? this.versions,
        generationSourceUrl: clearGenerationSourceUrl
            ? null
            : (generationSourceUrl ?? this.generationSourceUrl),
        branchSourceVersionId: clearBranchSourceVersionId
            ? null
            : (branchSourceVersionId ?? this.branchSourceVersionId),
        iterationCount: iterationCount ?? this.iterationCount,
        currentRoomType: currentRoomType ?? this.currentRoomType,
        currentStyle: currentStyle ?? this.currentStyle,
        letAiDecide: letAiDecide ?? this.letAiDecide,
        surpriseMe: surpriseMe ?? this.surpriseMe,
        pendingDescription: clearPendingDescription
            ? null
            : (pendingDescription ?? this.pendingDescription),
        generationMode: generationMode ?? this.generationMode,
      );

  /// True if this snapshot carries enough protocol state to round-trip a
  /// V2+ generation without backend re-capture. Used by hydration code to
  /// decide whether to trust the snapshot or invalidate it.
  bool get hasProtocolTokens =>
      structuralIdentity.isNotEmpty && iterationCount > 0;
}
