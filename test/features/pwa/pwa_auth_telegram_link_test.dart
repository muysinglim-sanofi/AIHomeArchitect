/// AUTH01-AUTH16 — Telegram as a door, and "Save my designs" as a LINK.
///
/// THE DEFECT THIS FILE WAS OPENED FOR (production, 2026-09-15)
/// ------------------------------------------------------------
/// Telegram had been implemented, enabled and used: a real human completed a
/// Telegram login in production, and that account exists. Yet the product
/// never once said so. Its profile showed no "Connected with Telegram", its
/// sign-in methods card listed only an e-mail it does not have, and a
/// successful Telegram return was recorded as a Facebook one.
///
/// The cause is one string. GoTrue stores a CUSTOM OIDC provider under its
/// full identifier — production's account carries
/// `app_metadata.providers == ["custom:telegram"]` — while every question the
/// app asked was `hasProvider('telegram')`. Every one of them answered no.
///
/// WHAT IS PROVED HERE, AND WHAT IS NOT
/// ------------------------------------
/// These tests own the CLIENT's half: which door is offered, which GoTrue call
/// each journey makes, and what the app concludes from a return. Whether
/// GoTrue itself keeps the user id across `linkIdentity` is the SERVER's half;
/// it was proved against the real project in
/// `backend/pwa_staging_identity_probe.py` and is not re-litigated by a fake.
/// The link between the two halves — that the client asks for a link at all,
/// rather than a sign-in — is exactly what AUTH05 pins.
library;

import 'package:ai_home_architect/features/pwa/application/pwa_intro_gate.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_availability.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_service.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_oauth_gateway.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_verification_channel.dart';
import 'package:flutter_test/flutter_test.dart';

// ── doubles ──────────────────────────────────────────────────────────────────

/// A scripted GoTrue. Providers are stored the way the REAL project stores
/// them — `custom:telegram`, prefix included — because a double that wrote
/// `telegram` would have hidden the entire defect.
class _World implements GoTrueSlice, GoTrueProfileSlice, GoTrueSessionGuard {
  _World({String userId = 'guest-X'}) : _id = userId {
    _refresh = 'rt-$_id';
  }

  String _id;
  String _email = '';
  String _phone = '';
  String _name = '';
  List<String> _providers = const [];
  bool anonymous = true;
  bool hasSession = true;
  String _refresh = '';
  int anonymousSignIns = 0;
  final restored = <String>[];

  /// Per-user data. A LINK must leave these untouched.
  final projects = <String, List<String>>{
    'guest-X': ['p1', 'p2'],
    'user-Y': ['y1'],
  };
  final spaces = <String, int>{'guest-X': 3, 'user-Y': 11};

  List<String> get myProjects => projects[_id] ?? const [];
  int get mySpaces => spaces[_id] ?? 0;

  /// What GoTrue does on a successful LINK: one more identity, same user.
  void attachTelegram(String name) {
    _name = name;
    anonymous = false;
    _providers = [..._providers, 'custom:telegram'];
  }

  /// What a SIGN IN does: a different user answers from now on.
  void becomeUser(String id,
      {String name = '', List<String> providers = const ['custom:telegram']}) {
    _id = id;
    _name = name;
    _providers = providers;
    anonymous = false;
    _refresh = 'rt-$id';
  }

  @override
  String? get currentUserId => hasSession ? _id : null;
  @override
  String get currentEmail => _email;
  @override
  bool get isAnonymous => anonymous;
  @override
  bool get hasCurrentSession => hasSession;
  @override
  Future<void> signInAnonymously() async {
    anonymousSignIns++;
    _id = 'guest-${anonymousSignIns + 1}';
    _email = '';
    _phone = '';
    _name = '';
    _providers = const [];
    anonymous = true;
    hasSession = true;
    _refresh = 'rt-$_id';
  }

  @override
  Future<void> signOutLocal() async => hasSession = false;
  @override
  String get currentPhone => _phone;
  @override
  String get displayName => _name;
  @override
  List<String> get providers => _providers;
  @override
  String get currentRefreshToken => _refresh;
  @override
  Future<void> restore(String refreshToken) async {
    restored.add(refreshToken);
    _id = refreshToken.replaceFirst('rt-', '');
    _refresh = refreshToken;
    hasSession = true;
  }
}

class _Channel implements PwaVerificationChannel {
  @override
  PwaVerificationKind get kind => PwaVerificationKind.email;
  @override
  bool get isConfigured => true;
  @override
  bool looksValid(String d) => d.contains('@');
  @override
  Future<PwaVerificationResult> send(String d) async =>
      const PwaVerificationResult.ok();
  @override
  Future<PwaVerificationResult> verify(String d, String c) async =>
      const PwaVerificationResult.ok();
  @override
  Future<PwaVerificationResult> resend(String d) async =>
      const PwaVerificationResult.ok();
}

/// Records WHICH GoTrue call each journey makes. That distinction is the whole
/// product requirement: a link must never be an ordinary login.
class _Gateway implements PwaOAuthGateway {
  final calls = <String>[];
  String lastRedirect = '';

  @override
  Future<bool> startLink(PwaOAuthProviderKind p,
      {required String redirectTo}) async {
    calls.add('link:${p.name}');
    lastRedirect = redirectTo;
    return true;
  }

  @override
  Future<bool> startSignIn(PwaOAuthProviderKind p,
      {required String redirectTo}) async {
    calls.add('signin:${p.name}');
    lastRedirect = redirectTo;
    return true;
  }
}

const _providersOn = PwaAuthProviders(telegram: true);

({PwaAuthService service, _World world, _Gateway gw, MemoryPwaSessionStore store})
    _rig({_World? world, PwaAuthProviders providers = _providersOn}) {
  final w = world ?? _World();
  final gw = _Gateway();
  final store = MemoryPwaSessionStore();
  final s = PwaAuthService.forTest(
    w,
    _Channel(),
    _Channel(),
    oauth: gw,
    handoffStore: store,
    providers: providers,
    profile: w,
    guard: w,
    redirectTo: 'https://app.aydenstudio.com/profile',
    projectIds: () => w.myProjects,
  );
  return (service: s, world: w, gw: gw, store: store);
}

PwaOAuthReturn _ok() => PwaOAuthReturn.parse(Uri.parse('https://x/?code=abc'))!;
PwaOAuthReturn _err(String code, String desc) => PwaOAuthReturn.parse(
    Uri.parse('https://x/?error=invalid_request&error_code=$code'
        '&error_description=${Uri.encodeComponent(desc)}'))!;

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  group('DOORS  what a person is offered', () {
    test('AUTH01 a fresh guest is a usable account, offered nothing it has',
        () {
      final r = _rig();
      final s = r.service.currentState();
      expect(s.isIdentified, isFalse);
      expect(r.world.currentUserId, 'guest-X');
      expect(s.providers, isEmpty, reason: 'nothing attached yet');
      expect(r.service.canTelegram, isTrue);
    });

    test('AUTH02/AUTH03 Telegram is a door on BOTH journeys when the server '
        'says it is enabled', () {
      final r = _rig();
      // `canTelegram` is what both the sign-in chooser and the save-my-designs
      // chooser read; the journey is a parameter of the tap, not of the door.
      expect(r.service.canTelegram, isTrue);
      expect(_providersOn.hasPrimaryChoice, isTrue,
          reason: 'with a social door the sheet opens on the CHOOSER, not on '
              'the e-mail field');

      // And it disappears when the backend gate says no — a button that leads
      // to a refusal is worse than no button.
      final off = _rig(providers: const PwaAuthProviders());
      expect(off.service.canTelegram, isFalse);
      expect(const PwaAuthProviders().hasPrimaryChoice, isFalse);
    });

    test('AUTH15 the phone door stays hidden', () {
      expect(kPwaPhoneDoorHidden, isTrue);
      const withPhone = PwaAuthProviders(phone: true, telegram: true);
      expect(withPhone.phoneDoor, isFalse,
          reason: 'the transport survives; the door does not');
      final r = _rig(providers: withPhone);
      expect(r.service.canPhone, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('THE STRING  custom:telegram is how GoTrue writes it down', () {
    test('AUTH09 an attached Telegram identity is RECOGNISED', () {
      final r = _rig();
      r.world.attachTelegram('Mike');
      final s = r.service.currentState();
      expect(s.providers, ['custom:telegram'],
          reason: 'the real shape, read from production');
      expect(s.hasProvider('telegram'), isTrue,
          reason: 'THE defect: this answered false, so nothing knew');
      expect(s.hasProvider('custom:telegram'), isTrue,
          reason: 'the full identifier must work too');
      expect(s.hasProvider('facebook'), isFalse);
      expect(s.hasProvider('email'), isFalse);
    });

    test('AUTH09b the profile can finally say HOW the person is connected', () {
      final r = _rig();
      r.world.attachTelegram('Mike');
      expect(r.service.currentState().connectedVia, PwaAuthMethod.telegram,
          reason: 'a Telegram-only account answered null: no line, no icon');
    });

    test('a guest still answers null, and e-mail still wins when it is all '
        'there is', () {
      final r = _rig();
      expect(r.service.currentState().connectedVia, isNull);
      final w = _World();
      w._providers = const ['email'];
      w.anonymous = false;
      final r2 = _rig(world: w);
      expect(r2.service.currentState().connectedVia, PwaAuthMethod.email);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('LINK  save my designs attaches, it does not log in', () {
    test('AUTH05 the LINK journey calls linkIdentity — never signInWithOAuth',
        () async {
      final r = _rig();
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.link);
      expect(r.gw.calls, ['link:telegram'],
          reason: 'linkIdentity carries LinkingTargetID, so GoTrue attaches '
              'the identity to THIS user instead of switching to another');
    });

    test('AUTH05b the same UUID before and after is what the app CONCLUDES',
        () async {
      final r = _rig();
      final before = r.world.currentUserId;
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.link);
      final handoff = PwaAuthHandoff.take(r.store)!;
      expect(handoff.userId, before);
      expect(handoff.journey, PwaOAuthJourney.link);
      expect(handoff.provider, PwaOAuthProviderKind.telegram);

      // GoTrue attaches the identity; the user id does not move.
      r.world.attachTelegram('Mike');
      final after = r.service.completeOAuthReturn(handoff, _ok());

      expect(r.world.currentUserId, before, reason: 'AUTH05: still X');
      expect(after.identityPreserved, isTrue);
      expect(after.switchedAccount, isFalse,
          reason: 'nothing to migrate, nothing to merge');
      expect(after.journey, PwaAuthJourney.linkNewIdentity);
      expect(after.method, PwaAuthMethod.telegram,
          reason: 'the SUCCESS branch said `facebook` outright');
    });

    test('AUTH06 projects are the same rows, because the owner is the same',
        () async {
      final r = _rig();
      final before = [...r.world.myProjects];
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.link);
      final handoff = PwaAuthHandoff.take(r.store)!;
      expect(handoff.projectIds, before,
          reason: 'written down BEFORE leaving, to be checked after');
      r.world.attachTelegram('Mike');
      r.service.completeOAuthReturn(handoff, _ok());
      expect(r.world.myProjects, before);
    });

    test('AUTH07/AUTH08 credits, ledger and entitlement are untouched',
        () async {
      // They are keyed by user id, and the user id did not move. The client
      // has no credit arithmetic to get wrong: it re-READS entitlement from
      // the Billing Engine and never computes a balance.
      final r = _rig();
      final spacesBefore = r.world.mySpaces;
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.link);
      final handoff = PwaAuthHandoff.take(r.store)!;
      r.world.attachTelegram('Mike');
      final after = r.service.completeOAuthReturn(handoff, _ok());
      expect(after.switchedAccount, isFalse);
      expect(r.world.mySpaces, spacesBefore);
      expect(r.world.spaces['user-Y'], 11,
          reason: 'and no other account was touched either');
    });

    test('AUTH10 a cold start claims NOTHING it cannot account for', () {
      final r = _rig();
      r.world.attachTelegram('Mike');
      // No hand-off in this tab: the state is simply what the session is.
      final s = r.service.completeOAuthReturn(null, _ok());
      expect(s.switchedAccount, isFalse);
      expect(s.identityPreserved, isFalse);
      expect(r.world.currentUserId, 'guest-X', reason: 'same UUID, same data');
      expect(s.hasProvider('telegram'), isTrue);
    });

    test('AUTH13 a replayed callback cannot link twice', () async {
      final r = _rig();
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.link);
      expect(PwaAuthHandoff.take(r.store), isNotNull);
      // `take` CONSUMES it: a second boot on the same URL finds nothing and
      // therefore concludes nothing.
      expect(PwaAuthHandoff.take(r.store), isNull);

      // A hand-off too old to belong to this return is also refused.
      final stale = PwaAuthHandoff(
        journey: PwaOAuthJourney.link,
        provider: PwaOAuthProviderKind.telegram,
        userId: 'guest-X',
        projectIds: const [],
        startedAtMs: 0,
      );
      final s = r.service.completeOAuthReturn(stale, _ok(),
          nowMs: DateTime.now().millisecondsSinceEpoch);
      expect(s.switchedAccount, isFalse);
      expect(s.identityPreserved, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('SIGN IN  a returning account is retrieved, not rebuilt', () {
    test('AUTH04 the SIGN-IN journey calls signInWithOAuth', () async {
      final r = _rig();
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.signIn);
      expect(r.gw.calls, ['signin:telegram']);
    });

    test('AUTH04b it lands on the account that owns the identity', () async {
      final r = _rig();
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.signIn);
      final handoff = PwaAuthHandoff.take(r.store)!;
      // GoTrue signs the browser in as the OWNER of that Telegram identity.
      r.world.becomeUser('user-Y', name: 'Mike');
      final after = r.service.completeOAuthReturn(handoff, _ok());

      expect(r.world.currentUserId, 'user-Y');
      expect(after.switchedAccount, isTrue,
          reason: 'expected on this journey — and stated, so the UI can say so');
      expect(after.journey, PwaAuthJourney.signInExisting);
      expect(after.method, PwaAuthMethod.telegram);
      expect(r.world.myProjects, ['y1'], reason: 'that account owns its own');
      expect(r.world.projects['guest-X'], ['p1', 'p2'],
          reason: 'the guest rows STAY where they are — no migration');
    });

    test('AUTH11 sign out, then back in with Telegram, returns to the account',
        () async {
      final w = _World();
      final r = _rig(world: w);
      w.attachTelegram('Mike');
      final linked = w.currentUserId;

      await r.service.signOut();
      expect(w.currentUserId, isNot(linked), reason: 'a NEW guest, by design');
      expect(w.isAnonymous, isTrue);

      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.signIn);
      final handoff = PwaAuthHandoff.take(r.store)!;
      w.becomeUser(linked!, name: 'Mike');
      final after = r.service.completeOAuthReturn(handoff, _ok());

      expect(w.currentUserId, linked, reason: 'same UUID, same data');
      expect(after.isIdentified, isTrue);
      expect(after.hasProvider('telegram'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('CONFLICT  an identity that belongs to someone else', () {
    test('AUTH12 is a FORK the person resolves — never a silent merge', () {
      final r = _rig();
      final before = r.world.currentUserId;
      final handoff = PwaAuthHandoff(
        journey: PwaOAuthJourney.link,
        provider: PwaOAuthProviderKind.telegram,
        userId: before!,
        projectIds: const ['p1', 'p2'],
        startedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      final after = r.service.completeOAuthReturn(
          handoff,
          _err('identity_already_exists',
              'Identity is already linked to another user'));

      expect(after.failure, PwaVerificationFailure.destinationAlreadyRegistered,
          reason: 'the sheet renders this as "Welcome back", with a choice');
      expect(after.method, PwaAuthMethod.telegram,
          reason: 'the right account named in the sentence');
      // Nothing moved. Not the session, not the projects, not the Spaces.
      expect(r.world.currentUserId, before);
      expect(r.world.myProjects, ['p1', 'p2']);
      expect(r.world.spaces['guest-X'], 3);
      expect(r.world.spaces['user-Y'], 11);
      expect(after.switchedAccount, isFalse);
    });

    test('AUTH12b "already linked to YOU" is not a collision', () {
      final ret = _err('identity_already_exists', 'Identity is already linked');
      expect(PwaOAuthReturn.failureOf(ret), isNull,
          reason: 'a retry after a half-finished link is a success told twice');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('ROUTING  the way back', () {
    test('AUTH14 the return URL is the page origin, which /kh normalises',
        () async {
      // `oauthRedirectTo` is built from `window.location.origin`, so preview,
      // preprod and live each come back to themselves. Production serves the
      // app shell for every path (Hosting rewrites `**` -> /index.html) and the
      // URL bridge re-writes the location under the compiled route prefix —
      // measured live: https://app.aydenstudio.com/profile lands on /kh/profile.
      final r = _rig();
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.link);
      expect(r.gw.lastRedirect, 'https://app.aydenstudio.com/profile');
      // A return is recognised from the BOOT url, query or fragment.
      expect(PwaOAuthReturn.parse(Uri.parse('https://app.aydenstudio.com/profile?code=x')),
          isNotNull);
      expect(PwaOAuthReturn.parse(Uri.parse('https://app.aydenstudio.com/kh/profile#error=access_denied')),
          isNotNull);
      expect(PwaOAuthReturn.parse(Uri.parse('https://app.aydenstudio.com/kh')),
          isNull, reason: 'an ordinary visit claims nothing');
    });
  });
}
