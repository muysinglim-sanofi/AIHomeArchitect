import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  // Test seam (null in production): drive auth events without Supabase.
  final Stream<AuthState>? _authStreamOverride;
  StreamSubscription<AuthState>? _authSub;

  PendingGenerationsNotifier({Stream<AuthState>? authStream})
      : _authStreamOverride = authStream,
        super(const {}) {
    // Guarded: Supabase may be uninitialised (tests) → no listener (pre-change
    // behaviour) instead of crashing at construction.
    Stream<AuthState>? stream = _authStreamOverride;
    if (stream == null) {
      try {
        stream = Supabase.instance.client.auth.onAuthStateChange;
      } catch (_) {
        stream = null;
      }
    }
    _authSub = stream?.listen(_onAuthEvent);
  }

  // Group 1 — when each in-flight generation STARTED, kept parallel to [state]
  // (app-scoped → survives the chat widget being disposed/recreated). Lets the
  // loading bubble resume its progress bar at the real elapsed fraction instead
  // of restarting from 0 on every rebuild. Not part of [state] so existing
  // `== GenerationLifecycle.x` readers stay untouched.
  final Map<String, DateTime> _startedAt = {};

  // Sign-out must not leak the old user's in-flight / ready-unseen badges into
  // the guest UI — drop ALL pending state (map + start timestamps).
  void _onAuthEvent(AuthState data) {
    if (data.event == AuthChangeEvent.signedOut) resetAll();
  }

  /// Drop every account-scoped pending entry + its start timestamp.
  void resetAll() {
    _startedAt.clear();
    if (mounted) state = const {};
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// When the in-flight generation for [sessionId] started, or null.
  DateTime? startedAt(String sessionId) => _startedAt[sessionId];

  void markInFlight(String sessionId) {
    if (sessionId.isEmpty || sessionId == 'new') return;
    _startedAt[sessionId] = DateTime.now();
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
    _startedAt.remove(sessionId);
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
