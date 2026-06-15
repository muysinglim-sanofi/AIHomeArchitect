/// Sprint 1 — backend premium + quota status provider (UI signal + reconcile).
///
/// Holds the latest [MeStatus] from GET /me/status for display (remaining free
/// generations, premium state). It ALSO drives purchase reconciliation:
/// whenever RevenueCat reports premium (purchase / restore / already-premium at
/// boot), it calls POST /purchases/sync so a delayed/missed webhook can't leave
/// a paying user free server-side — then refreshes the status.
///
/// Strictly additive: backend stays authoritative, the RevenueCat SDK stays a
/// pure UI signal, and every call is graceful (errors keep the prior state).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/revenuecat_service.dart';
import '../../data/services/status_service.dart';

class MeStatusNotifier extends StateNotifier<MeStatus?> {
  MeStatusNotifier() : super(null) {
    // Boot: fetch status, and if RC already reports premium, reconcile the
    // backend in case the webhook lagged (broadcast stream won't replay).
    _bootstrap();
    _authSub = Supabase.instance.client.auth.onAuthStateChange
        .listen(_onAuthEvent);
    _premiumSub =
        RevenuecatService.instance.premiumStream.listen(_onPremiumSignal);
  }

  final StatusService _svc = StatusService();
  late final StreamSubscription _authSub;
  late final StreamSubscription _premiumSub;
  // Last-wins guard (same rationale as accessProvider): a transient failed
  // refresh on resume must never overwrite a good status out of order.
  int _seq = 0;

  void _onAuthEvent(AuthState data) {
    // Sign-out clears the entitlement (promo/quota) of the previous user.
    if (data.event == AuthChangeEvent.signedOut) {
      _seq++; // invalidate any in-flight refresh
      if (mounted) state = null;
      return;
    }
    refresh();
  }

  Future<void> _bootstrap() async {
    if (RevenuecatService.instance.isPremium) {
      await _svc.syncPurchases();
    }
    await refresh();
  }

  // Fired on purchase, restore, or any CustomerInfo change. When RC says
  // premium, reconcile the backend first, then refresh the displayed status.
  Future<void> _onPremiumSignal(bool isPremium) async {
    if (isPremium) {
      await _svc.syncPurchases();
    }
    await refresh();
  }

  /// Re-fetch GET /me/status. On error, KEEP the previous state (graceful).
  /// Last-wins: a stale/superseded refresh result is dropped.
  Future<void> refresh() async {
    final mySeq = ++_seq;
    final s = await _svc.fetchStatus();
    if (!mounted || mySeq != _seq) return; // superseded → ignore
    if (s != null) state = s; // keep prior on null (graceful)
  }

  @override
  void dispose() {
    _authSub.cancel();
    _premiumSub.cancel();
    super.dispose();
  }
}

/// Latest backend status, or null while unknown (loading / error → render
/// nothing, never block the app).
final meStatusProvider =
    StateNotifierProvider<MeStatusNotifier, MeStatus?>(
  (ref) => MeStatusNotifier(),
);
