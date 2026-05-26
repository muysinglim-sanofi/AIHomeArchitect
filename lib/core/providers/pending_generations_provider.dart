import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wave 5.6c — Foreground in-app notification state for in-flight generations.
///
/// Tracks the lifecycle of /generate calls so the UI can surface a result-
/// ready signal on screens OTHER than the chat screen (home, projects list)
/// when a user navigated away during generation.
///
/// Lifecycle:
///   inFlight   — /generate await in progress (set on _startGeneration)
///   readyUnseen — completed successfully while user was off-screen
///   errorUnseen — failed while user was off-screen
///
/// When the user is ON the chat screen during completion, the existing
/// mounted-aware result handler renders the image inline and the provider
/// stays cleared. Only when `!mounted` at the moment of completion do we
/// flag the session as `readyUnseen` / `errorUnseen` for cross-screen
/// notification.
///
/// `clear(sessionId)` is called when the user re-opens the chat for that
/// session (so the badge disappears).
enum GenerationLifecycle {
  inFlight,
  readyUnseen,
  errorUnseen,
}

class PendingGenerationsNotifier
    extends StateNotifier<Map<String, GenerationLifecycle>> {
  PendingGenerationsNotifier() : super(const {});

  void markInFlight(String sessionId) {
    if (sessionId.isEmpty || sessionId == 'new') return;
    state = {...state, sessionId: GenerationLifecycle.inFlight};
  }

  void markReadyUnseen(String sessionId) {
    if (sessionId.isEmpty || sessionId == 'new') return;
    state = {...state, sessionId: GenerationLifecycle.readyUnseen};
  }

  void markErrorUnseen(String sessionId) {
    if (sessionId.isEmpty || sessionId == 'new') return;
    state = {...state, sessionId: GenerationLifecycle.errorUnseen};
  }

  void clear(String sessionId) {
    if (!state.containsKey(sessionId)) return;
    final next = {...state};
    next.remove(sessionId);
    state = next;
  }
}

final pendingGenerationsProvider = StateNotifierProvider<
    PendingGenerationsNotifier,
    Map<String, GenerationLifecycle>>(
  (ref) => PendingGenerationsNotifier(),
);
