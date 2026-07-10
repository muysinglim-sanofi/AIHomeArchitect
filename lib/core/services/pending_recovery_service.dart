import 'package:flutter/widgets.dart';

import '../../data/models/pending_generation.dart';
import '../../data/services/generation_service.dart';
import '../../data/services/status_service.dart';
import 'pending_generation_store.dart';

/// The action to take for one pending generation, given its backend probe.
enum RecoveryAction {
  /// Probe request FAILED (network/backend down) — do NOTHING; retry next sweep.
  skip,

  /// Backend has a TERMINAL intent (SUCCEEDED / FAILED) — the backend wins; drop
  /// the pending. Display/adoption of a SUCCEEDED result is handled by the
  /// per-session probe (_loadMessages) + homepage derive-from-backend adoption.
  clearOnly,

  /// Backend intent is RUNNING — the generation is still going server-side. KEEP
  /// the pending (garde-fou 1 : dernier filet si l'app meurt avant l'adoption) ;
  /// une sweep ultérieure re-sonde et résout sur la transition terminale. Ne
  /// déclenche JAMAIS de relaunch (réservé au no-intent confirmé) → aucun double
  /// POST.
  keepRunning,

  /// Backend confirms NO intent AND the pending is fresh — re-launch verbatim.
  relaunch,

  /// Backend confirms NO intent BUT the pending is older than [maxAgeMs] — drop
  /// it WITHOUT re-launching (a hours-old generation the user abandoned must not
  /// suddenly fire + cost money).
  dropStale,
}

/// PR2b Slice 3 — recovers generations the client INTENDED to send but that may
/// have been lost to a kill / sleep / network-drop before the /generate POST
/// landed. Sweeps the durable [PendingGenerationStore] at startup + app resume.
///
/// ⚠️ INVARIANT: the backend `generation_intents` table is the SOURCE OF TRUTH.
/// A pending only says "I intended to POST this". Every decision PROBES the
/// backend FIRST; if the pending and the backend disagree, THE BACKEND WINS. The
/// re-launch replays the EXACT stored tuple → the backend recomputes the SAME
/// deterministic intent_id → PR2a's atomic claim dedups (never a double OpenAI).
class PendingRecoveryService with WidgetsBindingObserver {
  PendingRecoveryService._();
  static final PendingRecoveryService instance = PendingRecoveryService._();

  /// Decided with the user (2026-07-03): a legitimate sleep/kill recovery happens
  /// within minutes; re-launching a generation intended > 2h ago would surprise
  /// the user and cost money → drop it instead.
  static const int maxAgeMs = 2 * 60 * 60 * 1000; // 2h

  bool _sweeping = false;                 // guard: no two concurrent sweeps
  bool _observerRegistered = false;
  final Set<String> _relaunching = {};    // guard: no two concurrent re-launches per session

  /// Register the app-level resume observer ONCE (call at boot). Sweeps whenever
  /// the app returns to the foreground — the core sleep/return recovery trigger.
  void registerResumeSweep() {
    if (_observerRegistered) return;
    _observerRegistered = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire-and-forget; sweep() self-guards against overlap.
      sweep(reason: 'resume');
    }
  }

  /// PURE decision — no I/O. Given a pending, its backend probe (the
  /// /v1/intents/latest map, or null on a FAILED request), and the current time.
  /// Backend-first: probe null → skip ; intent exists → clearOnly ; no intent →
  /// relaunch (fresh) / dropStale (too old).
  static RecoveryAction decide({
    required PendingGeneration pending,
    required Map<String, dynamic>? probe,
    required int nowMs,
  }) {
    if (probe == null) return RecoveryAction.skip; // request failed — never act blind
    final hasIntent = probe['intent_id'] != null;
    if (hasIntent) {
      // Garde-fou 1 — ne PAS effacer le pending tant que la gen tourne (RUNNING) :
      // c'est le dernier filet si l'app meurt avant l'adoption. On ne clear qu'au
      // terminal (SUCCEEDED/FAILED). Un intent RUNNING ne déclenche jamais de
      // relaunch (réservé au no-intent confirmé) → aucun double POST.
      final status = probe['status'] as String?;
      if (status == 'RUNNING') return RecoveryAction.keepRunning;
      return RecoveryAction.clearOnly; // terminal → backend gagne
    }
    final ageMs = nowMs - pending.createdAtMs;
    if (ageMs > maxAgeMs) return RecoveryAction.dropStale;
    return RecoveryAction.relaunch;
  }

  /// Sweep every durable pending. Idempotent + overlap-guarded. Non-fatal.
  /// [gen]/[store]/[nowMs] are injectable for tests (default to the real deps).
  Future<void> sweep({
    String reason = 'unknown',
    GenerationService? gen,
    PendingGenerationStore? store,
    int? nowMs,
  }) async {
    if (_sweeping) {
      debugPrint('[Recovery] sweep($reason) skipped — already running');
      return;
    }
    _sweeping = true;
    try {
      final s = store ?? await PendingGenerationStore.create();
      final pendings = await s.loadAll();
      if (pendings.isEmpty) return;
      debugPrint('[Recovery] sweep($reason) — ${pendings.length} pending');
      final g = gen ?? GenerationService();
      final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      for (final p in pendings) {
        await _resolveOne(p, s, g, now);
      }
    } catch (e) {
      debugPrint('[Recovery] sweep($reason) failed (non-fatal): $e');
    } finally {
      _sweeping = false;
    }
  }

  Future<void> _resolveOne(
    PendingGeneration p,
    PendingGenerationStore store,
    GenerationService gen,
    int nowMs,
  ) async {
    final probe = await gen.getLatestIntent(p.sessionId);
    switch (decide(pending: p, probe: probe, nowMs: nowMs)) {
      case RecoveryAction.skip:
        debugPrint('[Recovery] ${p.sessionId} probe failed → skip (retry next sweep)');
        return;
      case RecoveryAction.clearOnly:
        debugPrint('[Recovery] ${p.sessionId} intent terminal (backend wins) → clear pending');
        await store.clear(p.sessionId);
        return;
      case RecoveryAction.keepRunning:
        debugPrint('[Recovery] ${p.sessionId} intent RUNNING → KEEP pending '
            '(backend still generating; adoption/clear on terminal)');
        return; // garde-fou 1 : ne PAS clear — filet de récupération conservé
      case RecoveryAction.dropStale:
        final ageH = ((nowMs - p.createdAtMs) / 3600000).toStringAsFixed(1);
        debugPrint('[Recovery] ${p.sessionId} age=${ageH}h > 2h, no intent → DROP (not re-launched)');
        await store.clear(p.sessionId);
        return;
      case RecoveryAction.relaunch:
        // P0 (2026-07-10) — ne JAMAIS re-POST une génération que le billing refuserait
        // (no_active_pass / pass_exhausted / quota). Sinon l'user voit une "génération
        // qui se relance toute seule" en revenant dans la session. On vérifie la
        // capacité réelle AVANT de re-POST ; refus → DROP le pending, aucun re-POST.
        if (!await _canGenerate()) {
          debugPrint('[Recovery] ${p.sessionId} billing refuse la génération '
              '→ DROP (aucun re-POST, pas de replay)');
          await store.clear(p.sessionId);
          return;
        }
        await _relaunch(p, store, gen);
        return;
    }
  }

  /// P0 — capacité de génération réelle côté backend (même autorité que le gate),
  /// pour ne pas re-POST un pending que /generate refuserait (billing). FAIL-OPEN :
  /// sur erreur /me/status, on laisse _relaunch décider (il clear sur le 402 structuré).
  Future<bool> _canGenerate() async {
    try {
      final st = await StatusService().fetchStatus();
      return st?.canGenerate ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _relaunch(
    PendingGeneration p,
    PendingGenerationStore store,
    GenerationService gen,
  ) async {
    if (_relaunching.contains(p.sessionId)) {
      debugPrint('[Recovery] ${p.sessionId} already re-launching → skip');
      return;
    }
    _relaunching.add(p.sessionId);
    debugPrint('[Recovery] ${p.sessionId} no intent, fresh → RE-LAUNCH verbatim '
        '(same tuple → same intent_id → claim dedups)');
    try {
      // Replay the EXACT stored tuple. `generationTrigger` is overridden to
      // 'resume' for observability ONLY — it is NOT part of the intent_id
      // (backend identity = user:session:src:iter:room:mode|source_mode|prompt:
      // atmo:revision), so the re-launch is verbatim in IDENTITY.
      await gen.generate(
        sessionId: p.sessionId,
        prompt: p.prompt,
        beforeImageUrl: p.beforeImageUrl,
        styleLabel: p.styleLabel,
        roomType: p.roomType,
        roomTypeId: p.roomTypeId,
        atmosphereId: p.atmosphereId,
        iteration: p.iteration,
        history: p.history,
        originalImageUrl: p.originalImageUrl,
        clientRequestId: p.clientRequestId,
        letAiDecide: p.letAiDecide,
        surpriseMe: p.surpriseMe,
        structuralIdentity: p.structuralIdentity,
        versions: p.versions,
        generationMode: p.generationMode,
        sourceMode: p.sourceMode,
        sourceVersionId: p.sourceVersionId,
        uiLocale: p.uiLocale,
        generationTrigger: 'resume',
        generationAttempt: p.generationAttempt,
      );
      // NON-throwing return = the backend was REACHED and answered a terminal:
      // image / 202 running / failed-map / replay. The intention is resolved (the
      // backend owns the Intent) → drop the pending. On success the backend wrote
      // the image_result message (Wave 5.6) so it shows on next open.
      debugPrint('[Recovery] ${p.sessionId} re-launch reached backend (terminal) → clear pending');
      await store.clear(p.sessionId);
    } on GenerationException catch (e) {
      // Backend RESPONDED with a STRUCTURED error (402 paywall/quota, 403, or a
      // definitive failure). It was REACHED and answered → clear: re-launching
      // won't change a rejection, and keeping would loop on every sweep. (If the
      // response came after the claim, an Intent already exists → backend owns it.)
      debugPrint('[Recovery] ${p.sessionId} re-launch structured response '
          '(${e.errorCode}) → clear pending');
      await store.clear(p.sessionId);
    } catch (e) {
      // Transport / network / timeout (DioException with no structured body): NO
      // backend confirmation → KEEP the pending (the last recovery net) for the
      // next sweep, which re-probes and resolves. Never lose it here.
      debugPrint('[Recovery] ${p.sessionId} re-launch transport error → KEEP pending: $e');
    } finally {
      _relaunching.remove(p.sessionId);
    }
  }
}
