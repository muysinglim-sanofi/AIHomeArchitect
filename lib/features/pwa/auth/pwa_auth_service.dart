/// The PWA identity service. Two journeys, three transports, never silently
/// merged.
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
/// and it is why the link journeys have no migration step: there is nothing
/// to move. Phone takes the SAME GoTrue path (`updateUser`), and Facebook goes
/// through `link_identity`, which carries the current user's id in the flow
/// state (`LinkingTargetID`) — same user by construction.
///
/// The two INTENTS are explicit state, not something inferred from a screen:
///
///   [PwaAuthJourney.linkNewIdentity]  SECURE MY ACCOUNT — attach a new
///                                     identity to the user the browser IS.
///   [PwaAuthJourney.signInExisting]   SIGN IN — become the user who owns an
///                                     identity that already exists.
///
/// What this service refuses to do
/// -------------------------------
///   * It never turns "this identity already has an account" into a sign-in on
///     its own. That is a different user with different entitlements; the
///     person chooses it explicitly.
///   * It never copies free quota, ledger rows, passes or projects between
///     users. Rule 3 of the spec: an existing account keeps exactly what it
///     already had. The Guest's free generation is not a transferable asset.
///   * It never accepts a LINK that came back as a different user. The user id
///     is read before and after every verification; a mismatch restores the
///     previous session and is reported as a failure, not shown as a success.
///   * It never claims a bonus. There is no claim in the Web flow at all.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/pwa_intro_gate.dart' show PwaSessionStore;
import 'pwa_auth_availability.dart';
import 'pwa_email_otp_channel.dart';
import 'pwa_oauth_gateway.dart';
import 'pwa_phone_number.dart';
import 'pwa_phone_otp_channel.dart';
import 'pwa_verification_channel.dart';

export 'pwa_auth_availability.dart' show PwaAuthProviders;
export 'pwa_oauth_gateway.dart'
    show PwaOAuthJourney, PwaOAuthProviderKind, PwaAuthHandoff, PwaOAuthReturn;

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

/// The transport a journey rides on. The UI labels fields and picks keyboards
/// from it; it never branches on a vendor.
enum PwaAuthMethod { email, phone, facebook }

class PwaAuthState {
  const PwaAuthState({
    required this.stage,
    this.journey = PwaAuthJourney.none,
    this.method = PwaAuthMethod.email,
    this.destination = '',
    this.email = '',
    this.phone = '',
    this.displayName = '',
    this.providers = const <String>[],
    this.userId = '',
    this.isAnonymous = true,
    this.failure,
    this.busy = false,
    this.identityPreserved = false,
    this.switchedAccount = false,
    this.oauthPending = false,
  });

  final PwaAuthStage stage;
  final PwaAuthJourney journey;
  final PwaAuthMethod method;

  /// The address or number a code was sent to. Shown back so a typo is visible.
  final String destination;

  /// The identities actually attached, once verified. ANY of them may be
  /// empty: a Facebook-only account has no email, a phone-only account has
  /// neither email nor name. Nothing downstream may require one of them.
  final String email;
  final String phone;
  final String displayName;

  /// GoTrue's `app_metadata.providers`: `facebook`, `phone`, `email`.
  final List<String> providers;
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

  /// A provider round-trip just landed and its outcome has not been shown yet.
  /// The Profile opens the account sheet on it; the sheet clears it.
  final bool oauthPending;

  bool get isIdentified => stage == PwaAuthStage.identified;

  bool hasProvider(String p) => providers.contains(p);

  /// How the account is "connected", for the profile card. Facebook first
  /// because it carries a name; phone next; email last.
  PwaAuthMethod? get connectedVia {
    if (hasProvider('facebook')) return PwaAuthMethod.facebook;
    if (hasProvider('phone') || phone.isNotEmpty) return PwaAuthMethod.phone;
    if (hasProvider('email') || email.isNotEmpty) return PwaAuthMethod.email;
    return null;
  }

  /// The one line that names the account to its owner. Never the user id.
  /// A phone is masked; an email is shown; a Facebook name is shown as is.
  String get identityLabel {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (email.isNotEmpty) return email;
    if (phone.isNotEmpty) return PwaPhoneNumber.mask(phone);
    return '';
  }

  PwaAuthState copyWith({
    PwaAuthStage? stage,
    PwaAuthJourney? journey,
    PwaAuthMethod? method,
    String? destination,
    String? email,
    String? phone,
    String? displayName,
    List<String>? providers,
    String? userId,
    bool? isAnonymous,
    Object? failure = _unset,
    bool? busy,
    bool? identityPreserved,
    bool? switchedAccount,
    bool? oauthPending,
  }) =>
      PwaAuthState(
        stage: stage ?? this.stage,
        journey: journey ?? this.journey,
        method: method ?? this.method,
        destination: destination ?? this.destination,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        displayName: displayName ?? this.displayName,
        providers: providers ?? this.providers,
        userId: userId ?? this.userId,
        isAnonymous: isAnonymous ?? this.isAnonymous,
        failure: failure == _unset
            ? this.failure
            : failure as PwaVerificationFailure?,
        busy: busy ?? this.busy,
        identityPreserved: identityPreserved ?? this.identityPreserved,
        switchedAccount: switchedAccount ?? this.switchedAccount,
        oauthPending: oauthPending ?? this.oauthPending,
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

/// What the profile shows beyond the email: the phone, the provider's name,
/// and which providers are attached. Separate from [GoTrueSlice] so the
/// existing fakes keep compiling; null means "email only", which is what
/// every screen assumed before this round.
abstract class GoTrueProfileSlice {
  String get currentPhone;
  String get displayName;
  List<String> get providers;
}

class SupabaseGoTrueProfileSlice implements GoTrueProfileSlice {
  const SupabaseGoTrueProfileSlice(this.client);

  final GoTrueClient client;

  @override
  String get currentPhone {
    final p = client.currentUser?.phone ?? '';
    // GoTrue stores the number without its `+`; give it back as E.164.
    if (p.isEmpty) return '';
    return p.startsWith('+') ? p : '+$p';
  }

  @override
  String get displayName {
    final m = client.currentUser?.userMetadata ?? const {};
    for (final k in const ['full_name', 'name', 'preferred_username']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  @override
  List<String> get providers {
    final u = client.currentUser;
    if (u == null) return const [];
    final raw = u.appMetadata['providers'];
    if (raw is List) return raw.whereType<String>().toList();
    final ids = u.identities;
    if (ids != null) return ids.map((i) => i.provider).toList();
    final p = u.appMetadata['provider'];
    return p is String ? [p] : const [];
  }
}

/// The guard around a verification: the refresh token BEFORE, and the means to
/// put it back. Used only when a link came back as a different user — which
/// GoTrue's own resolution of `phone_change` by number makes possible.
abstract class GoTrueSessionGuard {
  String get currentRefreshToken;
  Future<void> restore(String refreshToken);
}

class SupabaseGoTrueSessionGuard implements GoTrueSessionGuard {
  const SupabaseGoTrueSessionGuard(this.client);

  final GoTrueClient client;

  @override
  String get currentRefreshToken => client.currentSession?.refreshToken ?? '';

  @override
  Future<void> restore(String refreshToken) async {
    if (refreshToken.isEmpty) return;
    await client.setSession(refreshToken);
  }
}

class PwaAuthService {
  PwaAuthService({
    required GoTrueClient auth,
    PwaVerificationChannel? linkChannel,
    PwaVerificationChannel? signInChannel,
    PwaVerificationChannel? phoneLinkChannel,
    PwaVerificationChannel? phoneSignInChannel,
    PwaOAuthGateway? oauth,
    PwaSessionStore? handoffStore,
    PwaAuthProviders providers = PwaAuthProviders.emailOnly,
    String oauthRedirectTo = '',
    List<String> Function()? projectIds,
    PwaAuthHandoff? bootHandoff,
    PwaOAuthReturn? bootReturn,
  })  : _bootHandoff = bootHandoff,
        _bootReturn = bootReturn,
        _auth = SupabaseGoTrueSlice(auth),
        _profile = SupabaseGoTrueProfileSlice(auth),
        _guard = SupabaseGoTrueSessionGuard(auth),
        _link = linkChannel ?? PwaEmailOtpChannel.linkNewIdentity(auth),
        _signIn = signInChannel ?? PwaEmailOtpChannel.signInExisting(auth),
        _phoneLink = phoneLinkChannel ??
            (providers.phone
                ? PwaPhoneOtpChannel.linkNewIdentity(auth)
                : null),
        _phoneSignIn = phoneSignInChannel ??
            (providers.phone ? PwaPhoneOtpChannel.signInExisting(auth) : null),
        _oauth = oauth ?? (providers.facebook
            ? SupabasePwaOAuthGateway(auth)
            : null),
        _handoffStore = handoffStore,
        _providers = providers,
        _redirectTo = oauthRedirectTo,
        _projectIds = projectIds ?? (() => const <String>[]);

  /// Same service, scripted session and transports. The identity RULES are what
  /// this exercises; whether GoTrue preserves a user_id was answered against
  /// the real staging project (`backend/pwa_staging_identity_probe.py`).
  @visibleForTesting
  PwaAuthService.forTest(
    this._auth,
    PwaVerificationChannel link,
    PwaVerificationChannel signIn, {
    PwaVerificationChannel? phoneLink,
    PwaVerificationChannel? phoneSignIn,
    PwaOAuthGateway? oauth,
    PwaSessionStore? handoffStore,
    PwaAuthProviders? providers,
    GoTrueProfileSlice? profile,
    GoTrueSessionGuard? guard,
    String redirectTo = 'https://test.invalid/profile',
    List<String> Function()? projectIds,
    PwaAuthHandoff? bootHandoff,
    PwaOAuthReturn? bootReturn,
  })  : _bootHandoff = bootHandoff,
        _bootReturn = bootReturn,
        _link = link,
        _signIn = signIn,
        _phoneLink = phoneLink,
        _phoneSignIn = phoneSignIn,
        _oauth = oauth,
        _handoffStore = handoffStore,
        _providers = providers ??
            PwaAuthProviders(
                facebook: oauth != null, phone: phoneLink != null),
        _profile = profile,
        _guard = guard,
        _redirectTo = redirectTo,
        _projectIds = projectIds ?? (() => const <String>[]);

  final GoTrueSlice _auth;
  final GoTrueProfileSlice? _profile;
  final GoTrueSessionGuard? _guard;
  final PwaVerificationChannel _link;
  final PwaVerificationChannel _signIn;
  final PwaVerificationChannel? _phoneLink;
  final PwaVerificationChannel? _phoneSignIn;
  final PwaOAuthGateway? _oauth;
  final PwaSessionStore? _handoffStore;
  final PwaAuthProviders _providers;
  final String _redirectTo;
  final List<String> Function() _projectIds;

  /// Whichever journey is currently in flight. Null between journeys.
  PwaVerificationChannel? _active;
  PwaAuthJourney _activeJourney = PwaAuthJourney.none;

  /// What the boot code found in the URL and in the session store. Consumed
  /// by the FIRST [bootState] read, so a controller rebuilt later does not
  /// re-announce a round-trip that was already shown.
  PwaAuthHandoff? _bootHandoff;
  PwaOAuthReturn? _bootReturn;

  /// The state the controller starts from. Normally [currentState]; when the
  /// page booted at the end of a provider round-trip, the measured outcome.
  PwaAuthState bootState() {
    final h = _bootHandoff;
    final r = _bootReturn;
    _bootHandoff = null;
    _bootReturn = null;
    if (h == null || r == null) return currentState();
    return completeOAuthReturn(h, r);
  }

  /// What this deployment can offer. Read at boot from the project itself.
  PwaAuthProviders get providers => _providers;

  bool get canPhone => _providers.phone && _phoneLink != null;
  bool get canFacebook =>
      _providers.facebook && _oauth != null && _handoffStore != null;

  /// What the email transport needs from the person.
  PwaVerificationKind get verificationKind => _link.kind;

  bool get canVerify => _link.isConfigured;

  bool looksValid(String destination) => _link.looksValid(destination);

  bool looksValidPhone(String destination) =>
      _phoneLink?.looksValid(destination) ?? false;

  /// The state implied by the CURRENT session. Read at boot and after every
  /// journey, so the source of truth is the session — not a local flag that can
  /// drift from it across a refresh.
  PwaAuthState currentState() {
    final id = _auth.currentUserId;
    if (id == null) {
      return const PwaAuthState(stage: PwaAuthStage.guest);
    }
    final anon = _auth.isAnonymous;
    final p = _profile;
    return PwaAuthState(
      stage: anon ? PwaAuthStage.guest : PwaAuthStage.identified,
      userId: id,
      email: _auth.currentEmail,
      phone: p?.currentPhone ?? '',
      displayName: p?.displayName ?? '',
      providers: p?.providers ?? const [],
      isAnonymous: anon,
    );
  }

  // ── Journey A: attach a NEW identity to THIS user ─────────────────────────

  /// Send a code that will attach [destination] (an email) to the current user.
  ///
  /// Returns a state carrying [PwaVerificationFailure.destinationAlreadyRegistered]
  /// when the address belongs to someone already. That is a STOP, not a
  /// fallback: the UI offers the sign-in journey, and the person picks.
  Future<PwaAuthState> beginLinkIdentity(String destination) async {
    await _ensureSession();
    return _begin(_link, PwaAuthJourney.linkNewIdentity, PwaAuthMethod.email,
        destination);
  }

  /// The same journey, by SMS. The number is normalised to E.164 first; what
  /// GoTrue receives is `+85512345678`, never a local format.
  Future<PwaAuthState> beginPhoneLink(String destination) async {
    final ch = _phoneLink;
    if (ch == null) return _refused(PwaAuthMethod.phone, destination);
    await _ensureSession();
    final e164 = PwaPhoneNumber.normalize(destination);
    if (e164 == null) {
      return currentState().copyWith(
        stage: PwaAuthStage.guest,
        journey: PwaAuthJourney.linkNewIdentity,
        method: PwaAuthMethod.phone,
        destination: destination.trim(),
        failure: PwaVerificationFailure.invalidDestination,
      );
    }
    return _begin(ch, PwaAuthJourney.linkNewIdentity, PwaAuthMethod.phone, e164);
  }

  // ── Journey B: sign in to an EXISTING account ─────────────────────────────

  /// Send a code for an account that already exists.
  ///
  /// Nothing from the Guest comes with it. No quota, no ledger, no pass, no
  /// projects. The account is found exactly as it was left.
  Future<PwaAuthState> beginSignInExisting(String destination) => _begin(
      _signIn, PwaAuthJourney.signInExisting, PwaAuthMethod.email, destination);

  Future<PwaAuthState> beginPhoneSignIn(String destination) async {
    final ch = _phoneSignIn;
    if (ch == null) return _refused(PwaAuthMethod.phone, destination);
    final e164 = PwaPhoneNumber.normalize(destination);
    if (e164 == null) {
      return currentState().copyWith(
        stage: PwaAuthStage.guest,
        journey: PwaAuthJourney.signInExisting,
        method: PwaAuthMethod.phone,
        destination: destination.trim(),
        failure: PwaVerificationFailure.invalidDestination,
      );
    }
    return _begin(ch, PwaAuthJourney.signInExisting, PwaAuthMethod.phone, e164);
  }

  Future<void> _ensureSession() async {
    if (!_auth.hasCurrentSession) {
      // The Web funnel always has an anonymous session by this point; if it
      // does not, minting one here is correct and keeps the upgrade in place.
      await _auth.signInAnonymously();
    }
  }

  PwaAuthState _refused(PwaAuthMethod method, String dest) =>
      currentState().copyWith(
        stage: PwaAuthStage.guest,
        method: method,
        destination: dest.trim(),
        failure: PwaVerificationFailure.providerRefused,
      );

  Future<PwaAuthState> _begin(PwaVerificationChannel channel,
      PwaAuthJourney journey, PwaAuthMethod method, String dest) async {
    _active = channel;
    _activeJourney = journey;
    final res = await channel.send(dest);
    if (!res.isOk) {
      return currentState().copyWith(
        stage: PwaAuthStage.guest,
        journey: journey,
        method: method,
        destination: dest.trim(),
        failure: res.failure,
      );
    }
    return currentState().copyWith(
      stage: PwaAuthStage.awaitingCode,
      journey: journey,
      method: method,
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
    final journey = _activeJourney;
    final method = channel.kind == PwaVerificationKind.phone
        ? PwaAuthMethod.phone
        : PwaAuthMethod.email;

    // Captured BEFORE the call: the only way to state, as a fact rather than a
    // hope, whether the person is still the same user afterwards. The refresh
    // token is captured for the same reason — it is the way back.
    final before = _auth.currentUserId ?? '';
    final refreshBefore = _guard?.currentRefreshToken ?? '';

    final res = await channel.verify(destination, code);
    if (!res.isOk) {
      return currentState().copyWith(
        stage: PwaAuthStage.awaitingCode,
        journey: journey,
        method: method,
        destination: destination.trim(),
        failure: res.failure,
      );
    }

    final after = _auth.currentUserId ?? '';
    final preserved = before.isNotEmpty && after == before;

    if (journey == PwaAuthJourney.linkNewIdentity && !preserved) {
      // A LINK that changed who we are is never a success. GoTrue resolves a
      // `phone_change` verification by number (`FindUserByPhoneChangeAndAudience`)
      // so a stale row on another account can, in principle, answer to this
      // code. Put the previous session back and say so. Nothing was moved:
      // the other account's row is what verified, and it keeps its own data.
      try {
        await _guard?.restore(refreshBefore);
      } catch (_) {
        // If the old session cannot be restored the browser holds the OTHER
        // user's session, which is still not a link — it is reported below
        // and the person is not told their work was saved.
      }
      _active = null;
      _activeJourney = PwaAuthJourney.none;
      return currentState().copyWith(
        stage: PwaAuthStage.guest,
        journey: journey,
        method: method,
        destination: destination.trim(),
        failure: PwaVerificationFailure.identityMismatch,
        identityPreserved: false,
        switchedAccount: false,
      );
    }

    _active = null;
    _activeJourney = PwaAuthJourney.none;

    return currentState().copyWith(
      stage: PwaAuthStage.identified,
      journey: journey,
      method: method,
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
      journey: _activeJourney,
      method: channel.kind == PwaVerificationKind.phone
          ? PwaAuthMethod.phone
          : PwaAuthMethod.email,
      destination: destination.trim(),
      failure: res.isOk ? null : res.failure,
    );
  }

  /// Abandon a verification in flight without changing who the person is.
  PwaAuthState cancel() {
    _active = null;
    _activeJourney = PwaAuthJourney.none;
    return currentState();
  }

  // ── Journey A/B by Facebook: a full-page round-trip ───────────────────────

  /// Leave for Facebook. On the LINK journey the current user is the target;
  /// on SIGN IN, whichever account owns the Facebook identity becomes the
  /// session. Either way, what was true before leaving is written down
  /// ([PwaAuthHandoff]) so [completeOAuthReturn] can measure, not guess.
  ///
  /// The returned state is only meaningful when the navigation did NOT
  /// happen (a refusal before the redirect). When it did, the page is gone.
  Future<PwaAuthState> startFacebook(PwaOAuthJourney journey) async {
    final gw = _oauth;
    final store = _handoffStore;
    if (gw == null || store == null || !_providers.facebook) {
      return _refused(PwaAuthMethod.facebook, '');
    }
    if (journey == PwaOAuthJourney.link) await _ensureSession();
    final before = _auth.currentUserId ?? '';
    PwaAuthHandoff(
      journey: journey,
      provider: PwaOAuthProviderKind.facebook,
      userId: before,
      projectIds: _projectIds(),
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
    ).save(store);
    try {
      final launched = journey == PwaOAuthJourney.link
          ? await gw.startLink(PwaOAuthProviderKind.facebook,
              redirectTo: _redirectTo)
          : await gw.startSignIn(PwaOAuthProviderKind.facebook,
              redirectTo: _redirectTo);
      if (!launched) {
        // The URL was minted but the browser did not go. Not a collision,
        // not a cancel: the door is simply shut right now.
        PwaAuthHandoff.take(store);
        return currentState().copyWith(
          stage: PwaAuthStage.guest,
          journey: journey == PwaOAuthJourney.link
              ? PwaAuthJourney.linkNewIdentity
              : PwaAuthJourney.signInExisting,
          method: PwaAuthMethod.facebook,
          failure: PwaVerificationFailure.providerRefused,
        );
      }
    } catch (e) {
      // Refused before leaving: nothing to come back to, so the hand-off is
      // withdrawn — a later unrelated reload must not read it.
      PwaAuthHandoff.take(store);
      return currentState().copyWith(
        stage: PwaAuthStage.guest,
        journey: journey == PwaOAuthJourney.link
            ? PwaAuthJourney.linkNewIdentity
            : PwaAuthJourney.signInExisting,
        method: PwaAuthMethod.facebook,
        failure: PwaOAuthReturn.failureOfException(e),
      );
    }
    return currentState().copyWith(
      journey: journey == PwaOAuthJourney.link
          ? PwaAuthJourney.linkNewIdentity
          : PwaAuthJourney.signInExisting,
      method: PwaAuthMethod.facebook,
      busy: true,
    );
  }

  /// The page came back. Combine what was written before leaving with what
  /// the URL says, and answer the same question a code answers: same user?
  ///
  /// A return WITHOUT a hand-off is not explained by anything this service
  /// did, so it claims nothing: the state is simply what the session is.
  PwaAuthState completeOAuthReturn(
      PwaAuthHandoff? handoff, PwaOAuthReturn? ret,
      {int? nowMs}) {
    final base = currentState();
    if (ret == null || handoff == null) return base;
    if (!handoff.isFresh(nowMs ?? DateTime.now().millisecondsSinceEpoch)) {
      return base;
    }
    final journey = handoff.journey == PwaOAuthJourney.link
        ? PwaAuthJourney.linkNewIdentity
        : PwaAuthJourney.signInExisting;

    final failure = PwaOAuthReturn.failureOf(ret);
    if (ret.isError && failure != null) {
      return base.copyWith(
        stage: base.isIdentified ? PwaAuthStage.identified : PwaAuthStage.guest,
        journey: journey,
        method: PwaAuthMethod.facebook,
        failure: failure,
        oauthPending: true,
      );
    }

    final after = base.userId;
    final preserved = after.isNotEmpty && after == handoff.userId;
    if (!base.isIdentified) {
      // A `?code=` that did not yield a signed-in user: the exchange failed
      // (a used or expired flow state) or the SDK could not persist it.
      return base.copyWith(
        journey: journey,
        method: PwaAuthMethod.facebook,
        failure: PwaVerificationFailure.providerRefused,
        oauthPending: true,
      );
    }
    return base.copyWith(
      stage: PwaAuthStage.identified,
      journey: journey,
      method: PwaAuthMethod.facebook,
      failure: null,
      identityPreserved: preserved,
      switchedAccount: !preserved,
      oauthPending: true,
    );
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
    _activeJourney = PwaAuthJourney.none;
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
