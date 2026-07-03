import 'dart:convert';

/// PR2b Slice 2 — a DURABLE record of a generation the client INTENDED to send.
///
/// ══════════════════════════════════════════════════════════════════════════
/// ARCHITECTURAL INVARIANT — DO NOT VIOLATE
/// ══════════════════════════════════════════════════════════════════════════
/// This is a TECHNICAL RECOVERY layer, NOT a source of truth. The single source
/// of truth for generation state is the BACKEND `generation_intents` table.
///
/// A [PendingGeneration] only asserts: "I intended to POST this /generate."
/// It is RECOVERY information, never BUSINESS information.
///
/// If this local record and the backend ever disagree, **THE BACKEND ALWAYS
/// WINS.** Slice 3 probes `generation_intents` FIRST and only re-launches when
/// the backend has NO intent for this session. The pending is then cleared.
/// Never derive quota, billing, or UI truth from a pending — only "should I
/// re-attach / re-launch this intended generation?".
/// ══════════════════════════════════════════════════════════════════════════
///
/// Persisted under key `aih:pending:{sessionId}` (one per session — a session
/// has at most one in-flight generation at a time). Written BEFORE the network
/// POST so a crash/kill mid-POST still leaves the intention recoverable; cleared
/// on a definitive terminal (success / structured failure). A transport error
/// does NOT clear it (the backend may have succeeded — Slice 3 resolves it).
class PendingGeneration {
  /// Bump when the persisted shape changes; [fromJson] rejects unknown versions
  /// (returns null upstream) so a stale snapshot is ignored rather than misread.
  static const int schemaVersion = 1;

  final String sessionId;

  /// Epoch ms when the intention was recorded. NOT used for replay — kept for
  /// OBSERVABILITY (a pending 18h old = something broke) and future expiry.
  final int createdAtMs;

  // ── Tuple 1:1 with GenerationService.generate() — REPLAYED VERBATIM ────────
  // Never recomputed / reconstructed: Slice 3 re-POSTs these exact params so the
  // backend recomputes the SAME deterministic intent_id (and the atomic claim
  // dedups). Keep this list in lockstep with generate()'s signature.
  final String prompt;
  final String beforeImageUrl;
  final String styleLabel;
  final String roomType;
  final String roomTypeId;
  final String atmosphereId;
  final int iteration;
  final String history;
  final String originalImageUrl;
  final String clientRequestId;
  final bool letAiDecide;
  final bool surpriseMe;
  final String structuralIdentity;
  final String versions;
  final String generationMode;
  final String sourceMode;
  final String sourceVersionId;
  final String uiLocale;
  final String generationTrigger;
  final int generationAttempt;

  const PendingGeneration({
    required this.sessionId,
    required this.createdAtMs,
    required this.prompt,
    required this.beforeImageUrl,
    required this.styleLabel,
    required this.roomType,
    required this.roomTypeId,
    required this.atmosphereId,
    required this.iteration,
    required this.history,
    required this.originalImageUrl,
    required this.clientRequestId,
    required this.letAiDecide,
    required this.surpriseMe,
    required this.structuralIdentity,
    required this.versions,
    required this.generationMode,
    required this.sourceMode,
    required this.sourceVersionId,
    required this.uiLocale,
    required this.generationTrigger,
    required this.generationAttempt,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'sessionId': sessionId,
        'createdAtMs': createdAtMs,
        'prompt': prompt,
        'beforeImageUrl': beforeImageUrl,
        'styleLabel': styleLabel,
        'roomType': roomType,
        'roomTypeId': roomTypeId,
        'atmosphereId': atmosphereId,
        'iteration': iteration,
        'history': history,
        'originalImageUrl': originalImageUrl,
        'clientRequestId': clientRequestId,
        'letAiDecide': letAiDecide,
        'surpriseMe': surpriseMe,
        'structuralIdentity': structuralIdentity,
        'versions': versions,
        'generationMode': generationMode,
        'sourceMode': sourceMode,
        'sourceVersionId': sourceVersionId,
        'uiLocale': uiLocale,
        'generationTrigger': generationTrigger,
        'generationAttempt': generationAttempt,
      };

  /// Returns null for an unrecognised schema version or a malformed map, so a
  /// stale/corrupt snapshot is IGNORED (recovery skipped) rather than misread.
  static PendingGeneration? fromJson(Map<String, dynamic> j) {
    if (j['schemaVersion'] != schemaVersion) return null;
    try {
      return PendingGeneration(
        sessionId: j['sessionId'] as String,
        createdAtMs: (j['createdAtMs'] as num).toInt(),
        prompt: (j['prompt'] as String?) ?? '',
        beforeImageUrl: (j['beforeImageUrl'] as String?) ?? '',
        styleLabel: (j['styleLabel'] as String?) ?? '',
        roomType: (j['roomType'] as String?) ?? '',
        roomTypeId: (j['roomTypeId'] as String?) ?? '',
        atmosphereId: (j['atmosphereId'] as String?) ?? '',
        iteration: (j['iteration'] as num?)?.toInt() ?? 1,
        history: (j['history'] as String?) ?? '',
        originalImageUrl: (j['originalImageUrl'] as String?) ?? '',
        clientRequestId: (j['clientRequestId'] as String?) ?? '',
        letAiDecide: (j['letAiDecide'] as bool?) ?? false,
        surpriseMe: (j['surpriseMe'] as bool?) ?? false,
        structuralIdentity: (j['structuralIdentity'] as String?) ?? '',
        versions: (j['versions'] as String?) ?? '',
        generationMode: (j['generationMode'] as String?) ?? 'preserve',
        sourceMode: (j['sourceMode'] as String?) ?? '',
        sourceVersionId: (j['sourceVersionId'] as String?) ?? '',
        uiLocale: (j['uiLocale'] as String?) ?? 'en',
        generationTrigger: (j['generationTrigger'] as String?) ?? 'resume',
        generationAttempt: (j['generationAttempt'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  String toJsonString() => jsonEncode(toJson());

  static PendingGeneration? fromJsonString(String s) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return fromJson(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }
}
