/// Riverpod wiring for identity. Thin on purpose: every rule lives in
/// [PwaAuthService], so a widget cannot accidentally become the place where the
/// identity spec is decided.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pwa_auth_service.dart';

class PwaAuthController extends StateNotifier<PwaAuthState> {
  PwaAuthController(this._service)
      : super(_service?.currentState() ??
            const PwaAuthState(stage: PwaAuthStage.guest));

  /// Null in mock/offline builds: there is no Supabase there, and an auth UI
  /// that pretended otherwise would be a lie the demo tells.
  final PwaAuthService? _service;

  bool get isAvailable => _service != null && _service.canVerify;

  bool looksValid(String destination) =>
      _service?.looksValid(destination) ?? false;

  Future<void> beginLink(String destination) =>
      _run(() => _service!.beginLinkIdentity(destination));

  Future<void> beginSignIn(String destination) =>
      _run(() => _service!.beginSignInExisting(destination));

  Future<void> submitCode(String destination, String code) =>
      _run(() => _service!.submitCode(destination, code));

  Future<void> resend(String destination) =>
      _run(() => _service!.resendCode(destination));

  Future<void> signOut() => _run(() => _service!.signOut());

  void cancel() {
    final s = _service;
    if (s == null || !mounted) return;
    state = s.cancel();
  }

  /// Re-read the session. Called after a refresh so the UI reflects who the
  /// browser actually is rather than who it was when the notifier was built.
  void sync() {
    final s = _service;
    if (s == null || !mounted) return;
    state = s.currentState();
  }

  Future<void> _run(Future<PwaAuthState> Function() op) async {
    if (_service == null || !mounted) return;
    state = state.copyWith(busy: true, failure: null);
    final next = await op();
    if (!mounted) return;
    state = next.copyWith(busy: false);
  }
}

/// The identity service, or null offline. Overridden in `main_pwa.dart` for
/// staging — the same pattern as the generation service and the entitlement
/// reader, so no widget ever constructs one.
final pwaAuthServiceProvider = Provider<PwaAuthService?>((ref) => null);

final pwaAuthProvider =
    StateNotifierProvider<PwaAuthController, PwaAuthState>((ref) {
  return PwaAuthController(ref.watch(pwaAuthServiceProvider));
});
