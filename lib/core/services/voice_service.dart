import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Wave 4.8 — the centralized voice-capability layer.
///
/// One implementation, used by every dictation surface (chat input bar AND
/// the upload description field), so the conversational experience is
/// consistent and there is ZERO duplicated dictation logic across screens.
///
/// Wraps the real native `speech_to_text` plugin (on-device / platform STT
/// — never fake) behind a small, callback-based API the UI can drive without
/// knowing anything about the plugin. Each surface instantiates its own
/// `VoiceService` (lightweight) so lifecycles are isolated; the *capability*
/// is centralized here, the *instance* is per-surface.
///
/// Semantics:
///   • partials → live in-place transcription (the consumer updates its
///     `TextEditingController` so the user sees words appear),
///   • final    → the resolved transcript (same callback shape; consumer can
///     dedupe by replacing the controller with `prefix + final`),
///   • stop     → user (or platform timeout / silence-pause) ended a session,
///   • errors   → mapped to a small `VoiceErrorKind` enum so UIs render a
///     calm, specific state (never a stuck mic).
///
/// Edge cases honored:
///   • permission denied                 → onError(permissionDenied) + stop
///   • STT unavailable on this device    → start() refuses, onError(unavailable)
///   • platform auto-stops on silence    → onStop fires (we observe 'done' /
///                                         'notListening' status)
///   • user toggles mic rapidly          → start() is a no-op while listening,
///                                         stop() is a no-op while idle
///   • screen disposed mid-dictation     → consumer calls dispose() → cancel
class VoiceService {
  VoiceService();

  final SpeechToText _stt = SpeechToText();

  // ── Internal state ─────────────────────────────────────────────────────
  bool _initializing = false;
  bool _initialized = false;
  bool _available = false;
  bool _isListening = false;

  // ── Continuous mode (Option A) ───────────────────────────────────────────
  // When true, the session survives engine self-stops (silence / OS time cap)
  // by auto-restarting until the user manually stops. Partials feed a PREVIEW
  // only; final segments accumulate in [_segments] and are committed once at
  // the real end (manual stop or permanent error).
  bool _continuous = false;
  bool _manualStop = false;
  bool _restarting = false;
  bool _sawSpeechThisSession = false;
  final List<String> _segments = <String>[];
  String _livePartial = '';
  DateTime? _sessionStart;
  int _emptyRestarts = 0;

  // Hard safety bounds so a forgotten or broken session can't run forever.
  static const Duration _maxSession = Duration(minutes: 5);
  static const int _maxEmptyRestarts = 20;

  // Active session callbacks (rebound on every start()).
  ValueChanged<String>? _onPartial;
  ValueChanged<String>? _onFinal;
  VoidCallback? _onStop;
  ValueChanged<VoiceErrorKind>? _onError;

  // Locale chosen for the current/last session. The plugin falls back to the
  // device default when null — premium safe default for an international app.
  String? _activeLocale;

  // Cache of the device's supported STT locale ids (resolved once after init).
  List<String>? _availableLocaleIds;

  /// Phase 4 — map a UI language code (en|fr|km) to its preferred STT locale id.
  /// The actual availability is resolved per-device in [_resolveLocale]; this is
  /// only the preference.
  static String sttLocaleForLanguage(String code) {
    switch (code) {
      case 'fr':
        return 'fr_FR';
      case 'km':
        return 'km_KH';
      default:
        return 'en_US';
    }
  }

  /// Resolve a requested locale id against what the device actually supports:
  /// exact match → same-language match (e.g. km_KH → any km_*) → null (device
  /// default). Khmer STT is frequently absent, so the graceful null fallback
  /// keeps the mic working in the device default rather than failing.
  Future<String?> _resolveLocale(String? requested) async {
    if (requested == null || requested.isEmpty) return null;
    try {
      _availableLocaleIds ??=
          (await _stt.locales()).map((l) => l.localeId).toList();
    } catch (_) {
      return requested; // can't enumerate → trust caller (plugin self-falls-back)
    }
    final ids = _availableLocaleIds!;
    String norm(String s) => s.replaceAll('-', '_').toLowerCase();
    final want = norm(requested);
    for (final id in ids) {
      if (norm(id) == want) return id;
    }
    final lang = want.split('_').first;
    for (final id in ids) {
      if (norm(id).split('_').first == lang) return id;
    }
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] locale "$requested" unsupported → device default');
    }
    return null;
  }

  // ── Public state ───────────────────────────────────────────────────────

  /// True once `initialize()` has confirmed real STT is available on this
  /// device with permission. UIs should hide the mic when this is false.
  bool get isAvailable => _available;

  /// True while a dictation session is active (between `start()` and either
  /// the user stopping or the platform auto-stopping on silence/timeout).
  bool get isListening => _isListening;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Idempotent. Resolves permission + native availability ONCE. Safe to
  /// call eagerly from `initState()` (does not begin listening).
  Future<bool> initialize() async {
    if (_initialized) return _available;
    if (_initializing) {
      // Another caller is already initializing — short-spin via a poll loop
      // is unnecessary; just return current best-known value.
      return _available;
    }
    _initializing = true;
    try {
      _available = await _stt.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
      );
    } catch (_) {
      _available = false;
    }
    _initialized = true;
    _initializing = false;
    return _available;
  }

  /// Begin a dictation session. No-op if already listening (rapid-toggle
  /// safety). Lazily initializes on first call. The consumer is expected to
  /// update its own `TextEditingController` from [onPartial]/[onFinal] —
  /// VoiceService deliberately does NOT touch UI state.
  /// [continuous] (Option A) — keep listening through pauses and OS self-stops
  /// via auto-restart, accumulate final segments, and deliver them ONCE at the
  /// real end. In continuous mode the callbacks change meaning :
  ///   • [onPartial] → live PREVIEW string (accumulated segments + current
  ///     partial). The consumer must NOT write this into its controller — it
  ///     is a throwaway preview.
  ///   • [onFinal]   → the committed full transcript, fired ONCE when the user
  ///     stops (or on a permanent error). The consumer commits this.
  /// In legacy mode (continuous=false) the original semantics are preserved
  /// (partials live, per-session finals).
  Future<void> start({
    required ValueChanged<String> onPartial,
    required ValueChanged<String> onFinal,
    VoidCallback? onStop,
    ValueChanged<VoiceErrorKind>? onError,
    String? localeId,
    bool continuous = false,
  }) async {
    if (_isListening) return;
    if (!_initialized) {
      await initialize();
    }
    if (!_available) {
      onError?.call(VoiceErrorKind.unavailable);
      return;
    }
    _onPartial = onPartial;
    _onFinal = onFinal;
    _onStop = onStop;
    _onError = onError;
    // Reset continuous-session state.
    _continuous = continuous;
    _manualStop = false;
    _restarting = false;
    _sawSpeechThisSession = false;
    _segments.clear();
    _livePartial = '';
    _emptyRestarts = 0;
    _sessionStart = DateTime.now();
    // Phase 4 — resolve the requested locale to one the device actually
    // supports (or null = device default) so e.g. Khmer degrades gracefully.
    _activeLocale = await _resolveLocale(localeId);
    try {
      await _listen();
      _isListening = true;
    } catch (_) {
      _isListening = false;
      _onError?.call(VoiceErrorKind.failed);
      _onStop?.call();
    }
  }

  /// The raw `_stt.listen` call — shared by [start] and the auto-restart loop.
  /// In continuous mode [cancelOnError] is OFF so a benign silence error does
  /// not tear the session down (we drive restarts from status/error handlers).
  Future<void> _listen() async {
    await _stt.listen(
      onResult: _handleResult,
      listenFor: _continuous ? _maxSession : const Duration(seconds: 30),
      pauseFor: _continuous
          ? const Duration(seconds: 30)
          : const Duration(seconds: 3),
      localeId: _activeLocale,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: !_continuous,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  void _handleResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords;
    if (!_continuous) {
      // Legacy: partials live, per-session finals.
      if (result.finalResult) {
        _onFinal?.call(words);
      } else {
        _onPartial?.call(words);
      }
      return;
    }
    // Continuous: accumulate finals, partial is preview-only.
    if (words.trim().isNotEmpty) _sawSpeechThisSession = true;
    if (result.finalResult) {
      final w = words.trim();
      if (w.isNotEmpty && (_segments.isEmpty || _segments.last != w)) {
        _segments.add(w);
      }
      _livePartial = '';
    } else {
      _livePartial = words;
    }
    _onPartial?.call(_previewText());
  }

  // Preview = accumulated final segments + the current (uncommitted) partial.
  String _previewText() {
    final parts = <String>[
      ..._segments,
      if (_livePartial.trim().isNotEmpty) _livePartial.trim(),
    ];
    return parts.join(' ');
  }

  // Re-open a listening session after an engine self-stop, unless the user
  // stopped manually or a safety bound was hit. A short delay lets the
  // platform settle (avoids a stuck recognizer on Android).
  void _scheduleRestart() {
    if (_restarting) return;
    _restarting = true;
    _emptyRestarts = _sawSpeechThisSession ? 0 : _emptyRestarts + 1;
    _sawSpeechThisSession = false;
    Future.delayed(const Duration(milliseconds: 150), () async {
      if (!_continuous || _manualStop || !_isListening) {
        _restarting = false;
        return;
      }
      try {
        await _listen();
      } catch (_) {
        _restarting = false;
        _finalize();
        return;
      }
      _restarting = false;
    });
  }

  // Real end of a continuous session: fold any leftover partial, commit the
  // accumulated transcript via [onFinal], then [onStop]. Idempotent-ish: guarded
  // by callers checking _isListening.
  void _finalize() {
    _isListening = false;
    if (_continuous) {
      final tail = _livePartial.trim();
      if (tail.isNotEmpty && (_segments.isEmpty || _segments.last != tail)) {
        _segments.add(tail);
      }
      _livePartial = '';
      _onFinal?.call(_segments.join(' ').trim());
    }
    _onStop?.call();
  }

  /// User-initiated stop. The current partial becomes the final result
  /// (via the plugin's own onResult flow). No-op if not listening.
  Future<void> stop() async {
    if (!_isListening) return;
    // Mark the stop as user-initiated FIRST so the auto-restart loop and the
    // status handler know not to re-open the session.
    _manualStop = true;
    try {
      await _stt.stop();
    } catch (_) {/* swallow — _handleStatus will still resolve state */}
    // `_handleStatus` flips _isListening false + fires onStop/onFinal when the
    // platform confirms; we do NOT mutate _isListening here to keep one
    // source of truth (avoids racing the platform).
  }

  /// Discard the current session without finalising the transcript.
  Future<void> cancel() async {
    if (!_isListening) return;
    _manualStop = true; // prevent the continuous auto-restart loop
    try {
      await _stt.cancel();
    } catch (_) {/* swallow */}
  }

  /// Call from the consumer's `dispose()`. Idempotent.
  void dispose() {
    _onPartial = null;
    _onFinal = null;
    _onStop = null;
    _onError = null;
    _manualStop = true; // stop any pending auto-restart
    try {
      _stt.cancel();
    } catch (_) {/* swallow */}
    _isListening = false;
  }

  // ── Plugin callbacks ───────────────────────────────────────────────────

  void _handleStatus(String status) {
    // Plugin emits: 'listening', 'notListening', 'done'.
    if (status == 'listening') {
      _isListening = true;
      return;
    }
    if (status != 'notListening' && status != 'done') return;
    if (!_isListening) return;
    // Continuous: the engine self-stopped (silence / OS time cap). Re-open
    // unless the user stopped manually or a safety bound was hit.
    if (_continuous && !_manualStop) {
      final elapsed = _sessionStart == null
          ? Duration.zero
          : DateTime.now().difference(_sessionStart!);
      if (elapsed < _maxSession && _emptyRestarts < _maxEmptyRestarts) {
        _scheduleRestart();
        return;
      }
      if (kDebugMode) {
        debugPrint('[VoiceService] continuous end '
            '(elapsed=$elapsed emptyRestarts=$_emptyRestarts)');
      }
    }
    _finalize();
  }

  void _handleError(SpeechRecognitionError err) {
    final mapped = _classifyError(err);
    // Continuous: a benign silence/no-speech error is NOT a real end — keep the
    // session alive via an auto-restart (the user hasn't stopped).
    if (_continuous &&
        !_manualStop &&
        _isListening &&
        mapped == VoiceErrorKind.silence &&
        !err.permanent) {
      if (kDebugMode) {
        debugPrint('[VoiceService] benign silence in continuous → restart');
      }
      _scheduleRestart();
      return;
    }
    _onError?.call(mapped);
    if (_continuous) {
      // Commit what we have so far so a mid-session error never loses words.
      if (_isListening) _finalize();
    } else {
      _isListening = false;
      _onStop?.call();
    }
    if (kDebugMode) {
      debugPrint(
          '[VoiceService] error mapped=$mapped permanent=${err.permanent} '
          'msg=${err.errorMsg}');
    }
  }

  VoiceErrorKind _classifyError(SpeechRecognitionError err) {
    final msg = err.errorMsg.toLowerCase();
    if (msg.contains('not-allowed') ||
        msg.contains('permission') ||
        msg.contains('denied')) {
      return VoiceErrorKind.permissionDenied;
    }
    if (msg.contains('no-speech') || msg.contains('speech-timeout')) {
      // Silence timeouts aren't real errors; UIs should treat them like a
      // clean stop. Reported as `silence` so the UI can keep its language
      // calm ("No speech detected" — never a red banner).
      return VoiceErrorKind.silence;
    }
    return VoiceErrorKind.failed;
  }
}

/// Calm, specific failure modes — every state has a non-broken UI affordance.
enum VoiceErrorKind {
  /// Native STT not available on this device (e.g. Android 10 without the
  /// Google app, or no SpeechRecognizer service installed). UI: hide mic.
  unavailable,

  /// User declined the microphone (or speech recognition on iOS) prompt.
  /// UI: surface a brief, calm hint; never auto-retry the system prompt.
  permissionDenied,

  /// Platform reported silence / no-speech timeout — a benign, non-error
  /// stop. UI: just exit the listening state.
  silence,

  /// Anything else (network on cloud STT, plugin failure, etc.). UI: brief
  /// calm hint, no loud banner.
  failed,
}
