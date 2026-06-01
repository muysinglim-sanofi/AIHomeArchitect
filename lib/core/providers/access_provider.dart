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
    // Re-fetch on every auth lifecycle event (sign-in, sign-out, token
    // refresh, anonymous→signed-in upgrade). The admin row in user_roles
    // is keyed by user_id, which may change across these transitions.
    _authSub = Supabase
        .instance.client.auth.onAuthStateChange.listen((_) => _refresh());
  }

  final AccessService _service = AccessService();
  late final StreamSubscription _authSub;

  Future<void> _refresh() async {
    final isAdmin = await _service.fetchIsAdmin();
    if (mounted) state = isAdmin;
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
