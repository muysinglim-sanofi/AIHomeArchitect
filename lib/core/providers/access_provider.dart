/// Wave 5.18 — Admin role provider for Developer Validation Mode.
///
/// Exposes a single boolean — true iff the authenticated user has the
/// 'admin' role in the backend `user_roles` table. Combine with the
/// existing `premiumProvider` for UI gating :
///
///     final hasFullAccess =
///         ref.watch(premiumProvider) || ref.watch(accessProvider);
///
/// Backend is the single source of truth (no RevenueCat custom entitlement,
/// no JWT claim, no local override). Granting admin = manual INSERT in
/// `user_roles` (expires_at NULL for permanent).
///
/// Why a SEPARATE provider from premiumProvider :
///   premiumProvider is reactive (RC SDK pushes purchase events instantly).
///   accessProvider is polled (HTTP /me/access on boot + auth events).
///   Merging the two would force a stale window after purchase ; keeping
///   them separate lets each signal update at its own granularity.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/access_service.dart';

class AccessNotifier extends StateNotifier<bool> {
  AccessNotifier() : super(false) {
    _refresh();
    _authSub = Supabase
        .instance.client.auth.onAuthStateChange.listen(_onAuthEvent);
  }

  final AccessService _service = AccessService();
  late final StreamSubscription _authSub;
  // Last-wins guard: each refresh captures a sequence number; a result is
  // applied only if it's still the latest. Stops an out-of-order transient
  // failure (resolving after a good fetch) from clobbering admin=true.
  int _seq = 0;

  void _onAuthEvent(AuthState data) {
    // Sign-out is the ONLY event that revokes admin in the UI. Everything else
    // (tokenRefreshed, initialSession, signedIn, userUpdated) does a guarded
    // refresh that never downgrades on a transient error — the bug was a
    // resume-time token-rotation 401 flipping admin off until a cold start.
    if (data.event == AuthChangeEvent.signedOut) {
      _seq++; // invalidate any in-flight refresh so it can't re-grant
      if (mounted) state = false;
      return;
    }
    _refresh();
  }

  Future<void> _refresh() async {
    final mySeq = ++_seq;
    final isAdmin = await _service.fetchIsAdmin();
    if (!mounted || mySeq != _seq) return; // superseded → ignore
    if (isAdmin == null) return; // unknown (error / no token) → KEEP last state
    state = isAdmin; // only an explicit backend response flips the flag
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }
}

/// True iff the authenticated user has the 'admin' role on the backend.
///
/// Watch this alongside `premiumProvider` to gate atmosphere/room/feature
/// cards. Never use it alone — premium subscribers should also see the
/// unlocked UI, and they are tracked separately via the RC SDK.
final accessProvider = StateNotifierProvider<AccessNotifier, bool>(
  (ref) => AccessNotifier(),
);
