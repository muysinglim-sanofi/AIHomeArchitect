/// Riverpod wiring for identity. Thin on purpose: every rule lives in
/// [PwaAuthService], so a widget cannot accidentally become the place where the
/// identity spec is decided.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pwa_auth_service.dart';

class PwaAuthController extends StateNotifier<PwaAuthState> {
  PwaAuthController(this._service)
      : super(_service?.bootState() ??
            const PwaAuthState(stage: PwaAuthStage.guest));

  /// Null in mock/offline builds: there is no Supabase there, and an auth UI
  /// that pretended otherwise would be a lie the demo tells.
  final PwaAuthService? _service;

  bool get isAvailable => _service != null && _service.canVerify;

  /// What this deployment can offer beyond email. Read from the project at
  /// boot; false everywhere in mock and in tests that do not say otherwise.
  PwaAuthProviders get providers =>
      _service?.providers ?? PwaAuthProviders.emailOnly;
  bool get canPhone => _service?.canPhone ?? false;
  bool get canFacebook => _service?.canFacebook ?? false;

  bool looksValid(String destination) =>
      _service?.looksValid(destination) ?? false;

  bool looksValidPhone(String destination) =>
      _service?.looksValidPhone(destination) ?? false;

  Future<void> beginLink(String destination) =>
      _run(() => _service!.beginLinkIdentity(destination));

  Future<void> beginSignIn(String destination) =>
      _run(() => _service!.beginSignInExisting(destination));

  Future<void> beginPhoneLink(String destination) =>
      _run(() => _service!.beginPhoneLink(destination));

  Future<void> beginPhoneSignIn(String destination) =>
      _run(() => _service!.beginPhoneSignIn(destination));

  /// Leave for Facebook. `signIn` selects the journey EXPLICITLY — the two
  /// are different GoTrue endpoints, and nothing here infers one from the
  /// other. On the Web the page navigates away; the state is only read back
  /// when the redirect was refused before it happened.
  Future<void> startFacebook({required bool signIn}) => _run(() =>
      _service!.startFacebook(
          signIn ? PwaOAuthJourney.signIn : PwaOAuthJourney.link));

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

  /// The boot code found a provider round-trip in the URL. Show its outcome
  /// once (the sheet reads `oauthPending`) and no more than once.
  void applyOAuthReturn(PwaAuthHandoff? handoff, PwaOAuthReturn? ret) {
    final s = _service;
    if (s == null || !mounted) return;
    state = s.completeOAuthReturn(handoff, ret);
  }

  /// The outcome has been shown. Keep everything else about the state.
  void consumeOAuthOutcome() {
    if (!mounted || !state.oauthPending) return;
    state = state.copyWith(oauthPending: false, failure: null);
  }

  Future<void> _run(Future<PwaAuthState> Function() op) async {
    if (_service == null || !mounted) return;
    // A second tap while the first is still in flight is the same intent
    // twice, and would send a second SMS. Dropped, not queued.
    if (state.busy) return;
    state = state.copyWith(busy: true, failure: null);
    final next = await op();
    if (!mounted) return;
    // `busy` is kept only when the service says so — the Facebook redirect,
    // where the page is about to leave and the buttons must stay dead.
    state = next.busy ? next : next.copyWith(busy: false);
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
