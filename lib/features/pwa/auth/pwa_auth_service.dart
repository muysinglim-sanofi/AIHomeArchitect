/// The PWA identity service. Two journeys, never silently merged.
///
/// It exists so that the frozen identity spec is enforced in ONE place instead
/// of being re-derived by every screen:
///
///   docs/GUEST_ACCOUNT_IDENTITY_SPEC.md — Guest is durable, a claim happens
///   once, and signing in to an EXISTING account transfers nothing.
///
/// The Web answer to that spec's open question U4 is measured, not assumed:
/// `backend/pwa_staging_identity_probe.py` proved against the real staging
/// project that attaching an email to an anonymous user PRESERVES the user_id
/// (B2), that the session minted while anonymous still resolves to it (B5) and
/// that the account stops being anonymous (B6). That is D2 — upgrade-in-place —
/// and it is why [linkIdentity] has no migration step: there is nothing to move.
///
/// What this service refuses to do
/// -------------------------------
///   * It never turns "this email already has an account" into a sign-in on its
///     own. That is a different identity with different entitlements; the
///     person chooses it explicitly ([beginSignInExisting]).
///   * It never copies free quota, ledger rows, passes or projects between
///     users. Rule 3 of the spec: an existing account keeps exactly what it
///     already had. The Guest's free generation is not a transferable asset.
///   * It never claims a bonus. There is no claim in the Web flow at all — the
///     bonus economics belong to the mobile spec and are not reimplemented here.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pwa_email_otp_channel.dart';
import 'pwa_verification_channel.dart';

/// Where the person is in the funnel. The UI renders from this and nothing else.
enum PwaAuthStage {
  /// An anonymous Guest. Fully able to create; no identity attached.
  guest,

  /// A destination has been submitted and a code is expected.
  awaitingCode,

  /// An identity is attached (or an existing account is signed in).
  identified,
}

/// Which journey a verification in flight belongs to. Exposed so the UI can say
/// something TRUE on the code screen — "we kept your work" vs "you're switching
/// accounts" are not the same promise.
enum PwaAuthJourney { none, linkNewIdentity, signInExisting }

class PwaAuthState {
  const PwaAuthState({
    required this.stage,
    this.journey = PwaAuthJourney.none,
    this.destination = '',
    this.email = '',
    this.userId = '',
    this.isAnonymous = true,
    this.failure,
    this.busy = false,
    this.identityPreserved = false,
    this.switchedAccount = false,
  });

  final PwaAuthStage stage;
  final PwaAuthJourney journey;

  /// The address a code was sent to. Shown back so the person can spot a typo.
  final String destination;

  /// The address actually attached to the account, once verified.
  final String email;
  final String userId;
  final bool isAnonymous;

  /// The last failure, or null. Translated by the localisation layer.
  final PwaVerificationFailure? failure;
  final bool busy;

  /// True after a link that kept the SAME user_id — the honest basis for
  /// telling someone their work survived.
  final bool identityPreserved;

  /// True after signing in to a DIFFERENT existing account. The UI uses this to
  /// stop promising that the Guest's work came along, because it did not.
  final bool switchedAccount;

  bool get isIdentified => stage == PwaAuthStage.identified;

  PwaAuthState copyWith({
    PwaAuthStage? stage,
    PwaAuthJourney? journey,
    String? destination,
    String? email,
    String? userId,
    bool? isAnonymous,
    Object? failure = _unset,
    bool? busy,
    bool? identityPreserved,
    bool? switchedAccount,
  }) =>
      PwaAuthState(
        stage: stage ?? this.stage,
        journey: journey ?? this.journey,
        destination: destination ?? this.destination,
        email: email ?? this.email,
        userId: userId ?? this.userId,
        isAnonymous: isAnonymous ?? this.isAnonymous,
        failure: failure == _unset
            ? this.failure
            : failure as PwaVerificationFailure?,
        busy: busy ?? this.busy,
        identityPreserved: identityPreserved ?? this.identityPreserved,
        switchedAccount: switchedAccount ?? this.switchedAccount,
      );

  static const Object _unset = Object();
}

/// The narrow slice of the session this service actually uses.
///
/// Four reads and two writes — that is the whole dependency. Naming it means the
/// identity RULES can be exercised without a network, and it documents exactly
/// how much of GoTrue this layer is coupled to: an SDK upgrade that changes
/// anything outside these six members cannot reach the rules.
abstract class GoTrueSlice {
  String? get currentUserId;
  String get currentEmail;
  bool get isAnonymous;
  bool get hasCurrentSession;
  Future<void> signInAnonymously();
  Future<void> signOutLocal();
}

/// The real slice, over the pinned SDK. The only place the service touches it.
class SupabaseGoTrueSlice implements GoTrueSlice {
  const SupabaseGoTrueSlice(this.client);

  final GoTrueClient client;

  @override
  String? get currentUserId => client.currentUser?.id;

  @override
  String get currentEmail => client.currentUser?.email ?? '';

  /// Authoritative and non-nullable in gotrue 2.20.0 — the flag the identity
  /// probe watched flip (B3/B6), so it is read rather than inferred from
  /// whether an email happens to be present.
  @override
  bool get isAnonymous => client.currentUser?.isAnonymous ?? true;

  @override
  bool get hasCurrentSession => client.currentSession != null;

  @override
  Future<void> signInAnonymously() => client.signInAnonymously();

  @override
  Future<void> signOutLocal() => client.signOut(scope: SignOutScope.local);
}

class PwaAuthService {
  PwaAuthService({
    required GoTrueClient auth,
    PwaVerificationChannel? linkChannel,
    PwaVerificationChannel? signInChannel,
  })  : _auth = SupabaseGoTrueSlice(auth),
        _link = linkChannel ?? PwaEmailOtpChannel.linkNewIdentity(auth),
        _signIn = signInChannel ?? PwaEmailOtpChannel.signInExisting(auth);

  /// Same service, scripted session and transports. The identity RULES are what
  /// this exercises; whether GoTrue preserves a user_id was answered against
  /// the real staging project (`backend/pwa_staging_identity_probe.py`).
  @visibleForTesting
  PwaAuthService.forTest(
      this._auth, PwaVerificationChannel link, PwaVerificationChannel signIn)
      : _link = link,
        _signIn = signIn;

  final GoTrueSlice _auth;
  final PwaVerificationChannel _link;
  final PwaVerificationChannel _signIn;

  /// Whichever journey is currently in flight. Null between journeys.
  PwaVerificationChannel? _active;

  /// What the transport needs from the person: an address, or a number later.
  PwaVerificationKind get verificationKind => _link.kind;

  bool get canVerify => _link.isConfigured;

  bool looksValid(String destination) => _link.looksValid(destination);

  /// The state implied by the CURRENT session. Read at boot and after every
  /// journey, so the source of truth is the session — not a local flag that can
  /// drift from it across a refresh.
  PwaAuthState currentState() {
    final id = _auth.currentUserId;
    if (id == null) {
      return const PwaAuthState(stage: PwaAuthStage.guest);
    }
    final anon = _auth.isAnonymous;
    return PwaAuthState(
      stage: anon ? PwaAuthStage.guest : PwaAuthStage.identified,
      userId: id,
      email: _auth.currentEmail,
      isAnonymous: anon,
    );
  }

  // ── Journey A: attach a NEW identity to THIS user ─────────────────────────

  /// Send a code that will attach [destination] to the current user.
  ///
  /// Returns a state carrying [PwaVerificationFailure.destinationAlreadyRegistered]
  /// when the address belongs to someone already. That is a STOP, not a
  /// fallback: the UI offers the sign-in journey, and the person picks.
  Future<PwaAuthState> beginLinkIdentity(String destination) async {
    if (!_auth.hasCurrentSession) {
      // The Web funnel always has an anonymous session by this point; if it
      // does not, minting one here is correct and keeps the upgrade in place.
      await _auth.signInAnonymously();
    }
    return _begin(_link, PwaAuthJourney.linkNewIdentity, destination);
  }

  // ── Journey B: sign in to an EXISTING account ─────────────────────────────

  /// Send a code for an account that already exists.
  ///
  /// Nothing from the Guest comes with it. No quota, no ledger, no pass, no
  /// projects. The account is found exactly as it was left.
  Future<PwaAuthState> beginSignInExisting(String destination) =>
      _begin(_signIn, PwaAuthJourney.signInExisting, destination);

  Future<PwaAuthState> _begin(
      PwaVerificationChannel channel, PwaAuthJourney journey, String dest) async {
    _active = channel;
    final res = await channel.send(dest);
    if (!res.isOk) {
      return currentState().copyWith(
        stage: PwaAuthStage.guest,
        journey: journey,
        destination: dest.trim(),
        failure: res.failure,
      );
    }
    return currentState().copyWith(
      stage: PwaAuthStage.awaitingCode,
      journey: journey,
      destination: dest.trim(),
      failure: null,
    );
  }

  /// Check the code and finish whichever journey is in flight.
  Future<PwaAuthState> submitCode(String destination, String code) async {
    final channel = _active;
    if (channel == null) {
      return currentState().copyWith(
          failure: PwaVerificationFailure.unknown, stage: PwaAuthStage.guest);
    }
    final journey = channel == _link
        ? PwaAuthJourney.linkNewIdentity
        : PwaAuthJourney.signInExisting;

    // Captured BEFORE the call: the only way to state, as a fact rather than a
    // hope, whether the person is still the same user afterwards.
    final before = _auth.currentUserId ?? '';

    final res = await channel.verify(destination, code);
    if (!res.isOk) {
      return currentState().copyWith(
        stage: PwaAuthStage.awaitingCode,
        journey: journey,
        destination: destination.trim(),
        failure: res.failure,
      );
    }

    final after = _auth.currentUserId ?? '';
    final preserved = before.isNotEmpty && after == before;
    _active = null;

    return currentState().copyWith(
      stage: PwaAuthStage.identified,
      journey: journey,
      destination: destination.trim(),
      failure: null,
      // Measured, not assumed — even on the link journey, which the probe says
      // preserves the id. If it ever stopped doing so, the UI would stop
      // claiming it did.
      identityPreserved: preserved,
      switchedAccount: !preserved,
    );
  }

  Future<PwaAuthState> resendCode(String destination) async {
    final channel = _active;
    if (channel == null) {
      return currentState().copyWith(failure: PwaVerificationFailure.unknown);
    }
    final res = await channel.resend(destination);
    return currentState().copyWith(
      stage: PwaAuthStage.awaitingCode,
      destination: destination.trim(),
      failure: res.isOk ? null : res.failure,
    );
  }

  /// Abandon a verification in flight without changing who the person is.
  PwaAuthState cancel() {
    _active = null;
    return currentState();
  }

  /// Leave the account. A NEW anonymous Guest is minted immediately, because a
  /// PWA with no session cannot browse or generate at all — signing out must
  /// not strand someone on a dead page.
  ///
  /// That new Guest is a NEW user_id with its own free bucket. Whether it gets
  /// a free generation is the Billing Engine's answer, not this file's: the
  /// server resolves entitlement per user, and anti-abuse belongs there.
  Future<PwaAuthState> signOut() async {
    _active = null;
    try {
      await _auth.signOutLocal();
    } catch (_) {
      // A failed sign-out must still land somewhere coherent.
    }
    try {
      await _auth.signInAnonymously();
    } catch (_) {
      return const PwaAuthState(stage: PwaAuthStage.guest);
    }
    return currentState();
  }
}
