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
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/revenuecat_service.dart';
import '../../data/services/status_service.dart';

class MeStatusNotifier extends StateNotifier<MeStatus?> {
  MeStatusNotifier() : super(null) {
    // Boot: seed the last CONFIRMED entitled snapshot from disk first (so a
    // previously-unlocked user — premium / promo-unlimited / promo-limited —
    // starts UNLOCKED instead of flickering to locked while /me/status is in
    // flight on cold start), then fetch live + reconcile RC.
    _bootstrap();
    _authSub = Supabase.instance.client.auth.onAuthStateChange
        .listen(_onAuthEvent);
    _premiumSub =
        RevenuecatService.instance.premiumStream.listen(_onPremiumSignal);
  }

  /// Test-only — construit un notifier SANS bootstrap ni souscriptions (aucun accès
  /// Supabase/RevenueCat). Permet les widget-tests du Premium Center. Additif : le
  /// constructeur de production reste inchangé.
  @visibleForTesting
  MeStatusNotifier.forTest(super.initial);

  // Persisted last-confirmed ENTITLED status (premium || hasActivePromo). Mirror
  // of accessProvider's admin cache: it only ever holds an entitled snapshot, so
  // seeding it can only GRANT, never lock; an explicit free/blocked answer (or
  // sign-out) CLEARS it. Backend stays authoritative for real generations, so an
  // over-optimistic UI can never bypass an actual gate.
  static const String _kCacheKey = 'me_status_entitled';

  // Lazy : construit à la 1ʳᵉ utilisation seulement (le constructeur `.forTest` ne l'utilise
  // jamais → pas d'accès dotenv/réseau en widget-test).
  late final StatusService _svc = StatusService();
  // Nullables : le constructeur `.forTest` ne souscrit pas (dispose reste null-safe).
  StreamSubscription? _authSub;
  StreamSubscription? _premiumSub;
  // Last-wins guard (same rationale as accessProvider): a transient failed
  // refresh on resume must never overwrite a good status out of order.
  int _seq = 0;
  // True once a live backend response set the state this session, so a late
  // cache seed can't override the live answer.
  bool _resolved = false;

  void _onAuthEvent(AuthState data) {
    // Sign-out clears the entitlement (promo/quota) of the previous user.
    if (data.event == AuthChangeEvent.signedOut) {
      _seq++; // invalidate any in-flight refresh
      _resolved = true;
      if (mounted) state = null;
      _clearCache();
      return;
    }
    refresh();
  }

  Future<void> _bootstrap() async {
    await _seedFromCache();
    if (RevenuecatService.instance.isPremium) {
      await _svc.syncPurchases();
    }
    await refresh();
  }

  // Optimistic cold-start seed. The cache only ever holds an entitled snapshot,
  // so this can only unlock. Guards prevent it from overriding a live answer.
  Future<void> _seedFromCache() async {
    try {
      final raw =
          (await SharedPreferences.getInstance()).getString(_kCacheKey);
      if (raw == null || raw.isEmpty) return;
      if (_resolved || state != null) return; // live answer already arrived
      final m = MeStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (mounted && !_resolved && state == null) state = m;
    } catch (_) {/* corrupt/absent cache → ignore, live fetch will set it */}
  }

  // Fired on purchase, restore, or any CustomerInfo change. When RC says
  // premium, reconcile the backend first, then refresh the displayed status.
  Future<void> _onPremiumSignal(bool isPremium) async {
    if (isPremium) {
      await _svc.syncPurchases();
    }
    await refresh();
  }

  /// Re-fetch GET /me/status. On error, KEEP the previous state (graceful —
  /// incl. the seeded cache, so a no-JWT cold-start fetch can't lock an
  /// entitled user). Last-wins: a stale/superseded refresh result is dropped.
  Future<void> refresh() async {
    final mySeq = ++_seq;
    final s = await _svc.fetchStatus();
    if (!mounted || mySeq != _seq) return; // superseded → ignore
    if (s == null) return; // error → keep prior (seeded) state
    _resolved = true;
    state = s;
    _persist(s); // re-cache if entitled, clear on a confirmed downgrade
  }

  // Cache the snapshot ONLY while entitled; a confirmed free/blocked status
  // clears it so the next cold start won't seed a stale unlock.
  Future<void> _persist(MeStatus s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (s.isPremium || s.hasActivePromo) {
        await prefs.setString(_kCacheKey, jsonEncode(s.toJson()));
      } else {
        await prefs.remove(_kCacheKey);
      }
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_kCacheKey);
    } catch (_) {}
  }

  /// Test-only — pilote l'état comme le ferait un refresh backend (widget-tests).
  @visibleForTesting
  void debugSetStatus(MeStatus? s) => state = s;

  @override
  void dispose() {
    _authSub?.cancel();
    _premiumSub?.cancel();
    super.dispose();
  }
}

/// Latest backend status, or null while unknown (loading / error → render
/// nothing, never block the app).
final meStatusProvider =
    StateNotifierProvider<MeStatusNotifier, MeStatus?>(
  (ref) => MeStatusNotifier(),
);
