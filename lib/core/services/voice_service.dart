import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
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
  Future<void> start({
    required ValueChanged<String> onPartial,
    required ValueChanged<String> onFinal,
    VoidCallback? onStop,
    ValueChanged<VoiceErrorKind>? onError,
    String? localeId,
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
    // Phase 4 — resolve the requested locale to one the device actually
    // supports (or null = device default) so e.g. Khmer degrades gracefully.
    _activeLocale = await _resolveLocale(localeId);
    try {
      await _stt.listen(
        onResult: (result) {
          final words = result.recognizedWords;
          if (result.finalResult) {
            _onFinal?.call(words);
          } else {
            _onPartial?.call(words);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        localeId: _activeLocale,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
      _isListening = true;
    } catch (_) {
      _isListening = false;
      _onError?.call(VoiceErrorKind.failed);
      _onStop?.call();
    }
  }

  /// User-initiated stop. The current partial becomes the final result
  /// (via the plugin's own onResult flow). No-op if not listening.
  Future<void> stop() async {
    if (!_isListening) return;
    try {
      await _stt.stop();
    } catch (_) {/* swallow — _handleStatus will still resolve state */}
    // `_handleStatus` flips _isListening false + fires onStop when the
    // platform confirms; we do NOT mutate _isListening here to keep one
    // source of truth (avoids racing the platform).
  }

  /// Discard the current session without finalising the transcript.
  Future<void> cancel() async {
    if (!_isListening) return;
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
    } else if (status == 'notListening' || status == 'done') {
      if (_isListening) {
        _isListening = false;
        _onStop?.call();
      }
    }
  }

  void _handleError(SpeechRecognitionError err) {
    _isListening = false;
    final mapped = _classifyError(err);
    _onError?.call(mapped);
    _onStop?.call();
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
