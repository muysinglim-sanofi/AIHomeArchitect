/// The one object that drives a payment, and the one place that polls.
///
/// What it does
/// ------------
///   start()    ask the SERVER to open a payment for a canonical sku
///   _poll()    ask the SERVER what happened, until a terminal state
///   cancel()   close the attempt — after the server has re-verified it
///   restore()  re-join a payment already in progress (F5, second tab, restart)
///
/// What it deliberately does NOT do
/// --------------------------------
///   * talk to PayWay. There is no gateway URL, no merchant id and no signing
///     material anywhere in the browser.
///   * conclude anything. It never sets [PwaPaymentState.granted] itself; that
///     state only ever arrives in a server answer.
///   * run a success timer. A payment does not become paid because a countdown
///     finished, and this class has no code that could express that.
///
/// The poll, and why the cadence is the server's
/// ---------------------------------------------
/// The interval comes from `poll_interval_ms` in the answer, not from a constant
/// here, because the server is the one that knows what its own rate limit to
/// PayWay is. It stops on the FIRST terminal state — a settled payment is never
/// asked about again — and it stops when the sheet closes, so a dead screen
/// cannot keep a request loop alive.
///
/// Entitlement, once
/// -----------------
/// When (and only when) the server says GRANTED, the entitlement is re-read.
/// Not decremented, not incremented, not assumed: the ledger granted the
/// credits, and the app asks it what the balance now is. That single re-read is
/// what turns a paid payment into an unlocked Generate button.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/pwa_aba_plugin.dart';
import 'pwa_entitlement_controller.dart';
import 'pwa_payment.dart';

/// How this controller reaches the server. Functions rather than the Dio client
/// so tests drive it with literal maps and the widget layer imports no HTTP.
class PwaPaymentGateway {
  const PwaPaymentGateway({
    required this.startCheckout,
    required this.orderStatus,
    required this.openOrder,
    required this.cancelOrder,
    this.startPluginCheckout,
  });

  final Future<Map<String, Object?>> Function({
    required String sku,
    required String attemptKey,
  }) startCheckout;

  /// The plugin-path variant. Optional so existing fakes need not grow one;
  /// the controller only takes this path when a plugin is also present.
  final Future<Map<String, Object?>> Function({
    required String sku,
    required String attemptKey,
  })? startPluginCheckout;
  final Future<Map<String, Object?>> Function(String tranId) orderStatus;
  final Future<Map<String, Object?>> Function() openOrder;
  final Future<Map<String, Object?>> Function(String tranId) cancelOrder;
}

class PwaPaymentController extends StateNotifier<PwaPayment> {
  PwaPaymentController(this._gateway, this._onGranted, {PwaAbaPlugin? plugin})
      : _plugin = plugin,
        super(const PwaPayment.idle());

  final PwaPaymentGateway? _gateway;

  /// ABA's checkout plugin, when this build has one. With it, [start] takes
  /// the plugin path: the server signs, the plugin presents. Without it (tests,
  /// the mock build) the server-side path is used, exactly as before.
  final PwaAbaPlugin? _plugin;

  /// How the last plugin launch went. PRESENTATION only — it says whether
  /// ABA's popup was asked to open, never whether anything was paid.
  PwaAbaPluginLaunch? lastPluginLaunch;

  /// Called EXACTLY once per attempt, when the server says GRANTED.
  final Future<void> Function()? _onGranted;

  Timer? _timer;
  String _attemptKey = '';
  bool _granted = false;

  /// The attempt token for the purchase in progress. Exposed for tests and for
  /// the retry path; it is not a secret and it identifies nothing on its own.
  String get attemptKey => _attemptKey;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Begin paying for [sku].
  ///
  /// A fresh [attemptKey] is minted here and nowhere else, which is what makes
  /// "retry" and "start over" different operations: [retry] reuses it, [start]
  /// replaces it.
  Future<void> start(String sku) async {
    _attemptKey = const Uuid().v4();
    await _open(sku);
  }

  /// Try the SAME purchase again — same attempt, same PayWay transaction.
  ///
  /// Unless the server told us the transaction id is spent, in which case only
  /// a new attempt can work and pretending otherwise would earn a 403 from
  /// PayWay for every press.
  Future<void> retry(String sku) async {
    if (state.newAttemptRequired || _attemptKey.isEmpty) {
      return start(sku);
    }
    await _open(sku);
  }

  Future<void> _open(String sku) async {
    final gateway = _gateway;
    if (gateway == null) {
      state = const PwaPayment(state: PwaPaymentState.unavailable);
      return;
    }
    _timer?.cancel();
    _granted = false;
    lastPluginLaunch = null;
    state = const PwaPayment.starting();

    final plugin = _plugin;
    final viaPlugin = plugin != null &&
        plugin.isSupported &&
        gateway.startPluginCheckout != null;
    final body = viaPlugin
        ? await gateway.startPluginCheckout!(sku: sku, attemptKey: _attemptKey)
        : await gateway.startCheckout(sku: sku, attemptKey: _attemptKey);
    if (!mounted) return;
    _apply(PwaPayment.parse(body));

    // Hand the SIGNED fields to ABA's plugin, once, and only for a fresh
    // payment: a rejoin comes back without them, because PayWay accepts one
    // Purchase per tran_id and the client that rejoins is already polling.
    // Nothing about the launch feeds back into payment state — the poll
    // scheduled by `_apply` is what will learn whether money moved.
    if (viaPlugin) {
      final handoff = _pluginHandoff(body);
      if (handoff != null) {
        lastPluginLaunch = plugin.launch(
          formAction: handoff.action,
          fields: handoff.fields,
        );
      }
    }
  }

  /// The plugin handoff, if the server sent one. Keys are relayed, not read.
  static ({String action, Map<String, String> fields})? _pluginHandoff(
    Map<String, Object?> body,
  ) {
    final raw = body['plugin'];
    if (raw is! Map) return null;
    final action = raw['form_action'];
    final fields = raw['fields'];
    if (action is! String || action.isEmpty || fields is! Map) return null;
    return (
      action: action,
      fields: {
        for (final e in fields.entries) e.key.toString(): e.value.toString(),
      },
    );
  }

  /// Re-join whatever is already in progress for this person.
  ///
  /// Called when the payment surface opens. The SERVER remembers the attempt,
  /// so an F5, a second tab and a backend restart all land here and get the
  /// same live QR back — and nothing about a payment is ever written to browser
  /// storage, where it could go stale or be edited.
  Future<void> restore() async {
    final gateway = _gateway;
    if (gateway == null) return;
    final body = await gateway.openOrder();
    if (!mounted) return;
    final restored = PwaPayment.parse(body);
    if (restored.state == PwaPaymentState.idle) return;
    // The attempt key is not recoverable from the server (it never leaves the
    // browser that minted it) and it is not needed: a restored attempt is
    // driven by its tran_id, and "try again" starts a fresh one.
    _apply(restored);
  }

  /// The person closed the sheet.
  ///
  /// The server verifies before cancelling, so a payment that landed a second
  /// ago is granted rather than thrown away. That round trip is the whole point
  /// — a local `state = cancelled` would be the fastest way to lose a sale.
  Future<void> cancel() async {
    final gateway = _gateway;
    final tranId = state.tranId;
    _timer?.cancel();
    if (gateway == null || tranId.isEmpty || state.isTerminal) {
      if (mounted) state = const PwaPayment.idle();
      return;
    }
    final body = await gateway.cancelOrder(tranId);
    if (!mounted) return;
    _apply(PwaPayment.parse(body));
  }

  /// Forget the attempt without touching the server. For closing a sheet whose
  /// payment is already finished.
  void reset() {
    _timer?.cancel();
    if (mounted) state = const PwaPayment.idle();
  }

  void _apply(PwaPayment next) {
    // An unreachable poll must not erase a live QR. The person is still looking
    // at it, it is still payable, and the network will come back — so keep the
    // last real answer and let the next tick correct it.
    if (next.state == PwaPaymentState.unreachable && state.isPayable) {
      _schedule(state.pollIntervalMs);
      return;
    }
    state = next;
    if (next.state == PwaPaymentState.granted && !_granted) {
      _granted = true;
      unawaited(_onGranted?.call() ?? Future<void>.value());
    }
    if (next.isPolling) {
      _schedule(next.pollIntervalMs);
    } else {
      _timer?.cancel();
    }
  }

  void _schedule(int intervalMs) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: intervalMs.clamp(1000, 15000)), _poll);
  }

  Future<void> _poll() async {
    final gateway = _gateway;
    final tranId = state.tranId;
    if (gateway == null || tranId.isEmpty || !state.isPolling) return;
    final body = await gateway.orderStatus(tranId);
    if (!mounted) return;
    _apply(PwaPayment.parse(body));
  }
}

/// How the app reaches the payment endpoints. Null in mock/offline builds —
/// overridden in `main_pwa.dart` for staging, exactly like the generation
/// service and the entitlement reader.
final pwaPaymentGatewayProvider = Provider<PwaPaymentGateway?>((ref) => null);

final pwaPaymentProvider =
    StateNotifierProvider<PwaPaymentController, PwaPayment>((ref) {
  return PwaPaymentController(
    ref.watch(pwaPaymentGatewayProvider),
    // The ONE side effect of a successful payment: ask the Billing Engine what
    // this person may now do. Nothing here computes a new balance.
    () => ref.read(pwaEntitlementProvider.notifier).refresh(),
    plugin: ref.watch(pwaAbaPluginProvider),
  );
});
