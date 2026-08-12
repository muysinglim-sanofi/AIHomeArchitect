/// The app's single holder of BILLING state, read from the server.
///
/// Everything that wants to know whether this person may generate, whether the
/// next image is watermarked, or which paywall to show, reads this. Nothing
/// counts generations locally — see `pwa_entitlement.dart` for why that rule
/// exists and what it prevents.
///
/// Refresh policy, deliberately narrow
/// -----------------------------------
///   * at boot, once;
///   * after a generation SUCCEEDS (a credit was spent);
///   * after a 402 (applied immediately from the refusal itself — the server
///     already told us, so waiting for a round trip would just make the paywall
///     arrive late);
///   * after an identity changes (a different user has different entitlement);
///   * when the person asks (pull-to-refresh / "I already paid").
///
/// Not on a timer, and not on every rebuild: entitlement changes when something
/// happens, and polling it would spend a request per tick to learn nothing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pwa_entitlement.dart';

/// How this controller reads entitlement. A function, not the Dio client, so
/// tests drive it with a literal map and the widget layer never imports the API.
typedef PwaEntitlementReader = Future<Map<String, Object?>?> Function();

class PwaEntitlementController extends StateNotifier<PwaEntitlement> {
  PwaEntitlementController(this._read) : super(const PwaEntitlement.loading());

  final PwaEntitlementReader? _read;

  /// True once a real answer (or a real failure) has replaced [loading].
  bool get isResolved => state.isKnown;

  /// Ask the server. Safe to call repeatedly; concurrent calls collapse.
  Future<void> refresh() async {
    final read = _read;
    if (read == null) {
      // Offline / mock builds have no billing backend. `unavailable` fails OPEN
      // so the demo still generates, and no fake entitlement is invented.
      if (mounted) state = const PwaEntitlement.unavailable();
      return;
    }
    if (_inFlight != null) return _inFlight;
    final future = _refresh(read);
    _inFlight = future;
    try {
      await future;
    } finally {
      _inFlight = null;
    }
  }

  Future<void>? _inFlight;

  Future<void> _refresh(PwaEntitlementReader read) async {
    final body = await read();
    if (!mounted) return;
    state = PwaEntitlement.parse(body);
  }

  /// The server just refused a generation for money. Believe it at once.
  ///
  /// The refusal IS billing news of record: `billing_try_hold` said no, under a
  /// per-user advisory lock, after reading the ledger. Re-asking would return
  /// the same answer one round trip later.
  void applyRefusal(String billingState) {
    if (!mounted || billingState.isEmpty) return;
    state = state.afterRefusal(billingState);
  }

  /// A generation completed, so a credit moved. Re-read rather than decrement:
  /// the ledger is the authority and a local `-1` would drift from it the first
  /// time a retry, a release or a second tab got involved.
  Future<void> onGenerationSettled() => refresh();

  /// The person is now a different user (linked an identity, signed in, signed
  /// out). Their entitlement is not the previous user's.
  Future<void> onIdentityChanged() async {
    if (mounted) state = const PwaEntitlement.loading();
    await refresh();
  }
}

/// How the app reads entitlement. Null in mock/offline builds — overridden in
/// `main_pwa.dart` for staging, exactly like the generation service.
final pwaEntitlementReaderProvider = Provider<PwaEntitlementReader?>(
  (ref) => null,
);

final pwaEntitlementProvider =
    StateNotifierProvider<PwaEntitlementController, PwaEntitlement>((ref) {
  final controller =
      PwaEntitlementController(ref.watch(pwaEntitlementReaderProvider));
  // One read at construction. The screens that need it are built after this,
  // and none of them may block on it — `loading` is a state they all render.
  controller.refresh();
  return controller;
});
