/// AUTH-TG-01..20 + TG-TRIAL-01..03 — one tap, one trip through Telegram.
///
/// THE DEFECT, from a real iPhone in production
/// --------------------------------------------
/// A guest tapped "Secure my account", chose Telegram, authorised — and Ayden
/// answered "Welcome back / Continue to my existing account", then sent them
/// back through Telegram a second time. The tester went round three times,
/// because nothing on screen said the first login had worked.
///
/// WHY IT CANNOT SIMPLY BE COLLAPSED, measured not assumed
/// -------------------------------------------------------
/// GoTrue v2.197.0 (production AND staging, probed 2026-09-16) accepts
/// `custom:telegram` on `POST /token?grant_type=id_token` — so an identity we
/// already hold a token for CAN be signed into with no redirect. But there is
/// no route that ATTACHES an identity from a token: `POST /user/identities` is
/// 404 and `/user/identities/{x}` answers only DELETE. A link always costs a
/// browser round trip. And the journey is chosen by the URL you leave on,
/// before anybody knows whether the Telegram account is already someone's.
///
/// So: one authorisation for every case is not on offer. One authorisation for
/// every case we can decide IN ADVANCE is, and that is what these tests pin.
/// The decision is made on what the guest would lose, read from the server.
///
/// THE TRIAL, which is the subtle part
/// -----------------------------------
/// A fresh guest's 3 Spaces are a PROJECTION, not a balance: production has no
/// trigger on `auth.users`, 96 accounts hold zero ledger rows, and
/// `_free_bucket_available` adds the trial only while no TRIAL row exists. So
/// abandoning a guest in that state orphans nothing — and the account it
/// becomes is projected the same 3 by the same rule. Three before, three
/// after, once. The moment anything HAS been materialised, the guest is no
/// longer empty and the link path is taken instead.
library;

import 'package:ai_home_architect/features/pwa/application/pwa_intro_gate.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_service.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_oauth_gateway.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_telegram_journey.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_verification_channel.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:io';

// ── doubles ──────────────────────────────────────────────────────────────────

/// A scripted GoTrue with per-user Spaces and projects, so a journey that
/// moved either would be visible.
class _World implements GoTrueSlice, GoTrueProfileSlice, GoTrueSessionGuard {
  _World({String userId = 'guest-G'}) : _id = userId {
    _refresh = 'rt-$_id';
  }

  String _id;
  String _name = '';
  List<String> _providers = const [];
  bool anonymous = true;
  bool hasSession = true;
  String _refresh = '';
  int anonymousSignIns = 0;

  /// Spaces per account. `user-U` has already spent its own trial.
  final spaces = <String, int>{'guest-G': 3, 'user-U': 0};
  final projects = <String, List<String>>{
    'guest-G': <String>[],
    'user-U': ['u1', 'u2'],
  };

  int get mySpaces => spaces[_id] ?? 0;
  List<String> get myProjects => projects[_id] ?? const [];

  /// GoTrue attaching the identity: one more provider, SAME user.
  void linkTelegram() {
    anonymous = false;
    _providers = [..._providers, 'custom:telegram'];
    _name = 'Mike';
  }

  /// GoTrue signing in as the identity's owner: a different user answers now.
  void signInAs(String id) {
    _id = id;
    _name = 'Mike';
    _providers = const ['custom:telegram'];
    anonymous = false;
    _refresh = 'rt-$id';
  }

  /// GoTrue creating a brand-new permanent user for an unused identity.
  void createdFresh(String id) {
    _id = id;
    _name = 'Mike';
    _providers = const ['custom:telegram'];
    anonymous = false;
    _refresh = 'rt-$id';
    // A new account has no ledger row either: the engine projects its trial.
    spaces.putIfAbsent(id, () => 3);
    projects.putIfAbsent(id, () => <String>[]);
  }

  @override
  String? get currentUserId => hasSession ? _id : null;
  @override
  String get currentEmail => '';
  @override
  bool get isAnonymous => anonymous;
  @override
  bool get hasCurrentSession => hasSession;
  @override
  Future<void> signInAnonymously() async {
    anonymousSignIns++;
    _id = 'guest-${anonymousSignIns + 1}';
    _name = '';
    _providers = const [];
    anonymous = true;
    hasSession = true;
    _refresh = 'rt-$_id';
    spaces.putIfAbsent(_id, () => 3);
    projects.putIfAbsent(_id, () => <String>[]);
  }

  @override
  Future<void> signOutLocal() async => hasSession = false;
  @override
  String get currentPhone => '';
  @override
  String get displayName => _name;
  @override
  List<String> get providers => _providers;
  @override
  String get currentRefreshToken => _refresh;
  @override
  Future<void> restore(String refreshToken) async {
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

/// COUNTS provider authorisations. That count is the product requirement.
class _Gateway implements PwaOAuthGateway {
  final calls = <String>[];

  int get authorisations => calls.length;

  @override
  Future<bool> startLink(PwaOAuthProviderKind p,
      {required String redirectTo}) async {
    calls.add('link:${p.name}');
    return true;
  }

  @override
  Future<bool> startSignIn(PwaOAuthProviderKind p,
      {required String redirectTo}) async {
    calls.add('signin:${p.name}');
    return true;
  }
}

({PwaAuthService service, _World world, _Gateway gw, MemoryPwaSessionStore store})
    _rig({_World? world}) {
  final w = world ?? _World();
  final gw = _Gateway();
  final store = MemoryPwaSessionStore();
  final s = PwaAuthService.forTest(
    w,
    _Channel(),
    _Channel(),
    oauth: gw,
    handoffStore: store,
    providers: const PwaAuthProviders(telegram: true, facebook: true),
    profile: w,
    guard: w,
    redirectTo: 'https://app.aydenstudio.com/profile',
    projectIds: () => w.myProjects,
  );
  return (service: s, world: w, gw: gw, store: store);
}

PwaOAuthReturn _ok() => PwaOAuthReturn.parse(Uri.parse('https://x/?code=abc'))!;
PwaOAuthReturn _collision() => PwaOAuthReturn.parse(Uri.parse(
    'https://x/?error=invalid_request&error_code=identity_already_exists'
    '&error_description=${Uri.encodeComponent("Identity is already linked to another user")}'))!;
PwaOAuthReturn _cancelled() => PwaOAuthReturn.parse(
    Uri.parse('https://x/?error=access_denied&error_description=cancelled'))!;

/// The footprint of a guest carrying nothing: the entitlement and the library
/// have both ANSWERED, and what they answered is a full, untouched trial.
const _virgin = PwaGuestFootprint(
  entitlementKnown: true,
  libraryRestored: true,
  projects: 0,
  visions: 0,
  freeCredits: 3,
  passCredits: 0,
  creditsAvailable: 3,
  hasActivePass: false,
);

/// The same guest, with work.
const _withWork = PwaGuestFootprint(
  entitlementKnown: true,
  libraryRestored: true,
  projects: 2,
  visions: 3,
  freeCredits: 1,
  passCredits: 0,
  creditsAvailable: 1,
  hasActivePass: false,
);

/// One tap, resolved and started. Returns how many authorisations it cost.
Future<int> _tapTelegram(
  ({PwaAuthService service, _World world, _Gateway gw, MemoryPwaSessionStore store}) r, {
  required PwaGuestFootprint footprint,
  bool userAskedSignIn = false,
}) async {
  final journey = pwaTelegramJourneyFor(
    isAnonymous: r.world.isAnonymous,
    userAskedSignIn: userAskedSignIn,
    footprint: footprint,
  );
  await r.service.startOAuth(PwaOAuthProviderKind.telegram, journey);
  return r.gw.authorisations;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  group('THE COUNT  how many times a person visits Telegram', () {
    test('AUTH-TG-01/11 fresh guest + unused identity -> EXACTLY 1', () async {
      final r = _rig();
      final n = await _tapTelegram(r, footprint: _virgin);
      expect(n, 1, reason: 'one tap, one authorisation');

      // GoTrue creates the permanent account for an unused identity.
      final handoff = PwaAuthHandoff.take(r.store)!;
      r.world.createdFresh('user-N');
      final after = r.service.completeOAuthReturn(handoff, _ok());

      expect(r.gw.authorisations, 1, reason: 'and no second one, ever');
      expect(after.isIdentified, isTrue);
      expect(after.hasProvider('telegram'), isTrue);
    });

    test('AUTH-TG-04/11 fresh EMPTY guest + identity owned by U -> EXACTLY 1',
        () async {
      final r = _rig();
      final n = await _tapTelegram(r, footprint: _virgin);
      expect(n, 1);
      expect(r.gw.calls, ['signin:telegram'],
          reason: 'the sign-in door: a guest with nothing cannot lose anything, '
              'and this is the door that resolves a collision in one trip');

      final handoff = PwaAuthHandoff.take(r.store)!;
      r.world.signInAs('user-U');
      final after = r.service.completeOAuthReturn(handoff, _ok());

      expect(r.gw.authorisations, 1,
          reason: 'THE defect: this used to cost two');
      expect(r.world.currentUserId, 'user-U');
      expect(after.switchedAccount, isTrue);
      expect(after.method, PwaAuthMethod.telegram);
    });

    test('AUTH-TG-15 signed out, then Telegram -> EXACTLY 1', () async {
      final r = _rig();
      await r.service.signOut();
      final n = await _tapTelegram(r,
          footprint: PwaGuestFootprint.unknown, userAskedSignIn: true);
      expect(n, 1);
      expect(r.gw.calls, ['signin:telegram']);
    });

    test('AUTH-TG-02 guest WITH work + unused identity -> EXACTLY 1, linked',
        () async {
      final w = _World();
      w.projects['guest-G'] = ['p1', 'p2'];
      final r = _rig(world: w);
      final n = await _tapTelegram(r, footprint: _withWork);
      expect(n, 1);
      expect(r.gw.calls, ['link:telegram'], reason: 'their work must follow');

      final handoff = PwaAuthHandoff.take(r.store)!;
      final before = w.currentUserId;
      w.linkTelegram();
      final after = r.service.completeOAuthReturn(handoff, _ok());

      expect(w.currentUserId, before, reason: 'AUTH-TG-01: same UID');
      expect(after.identityPreserved, isTrue);
      expect(after.switchedAccount, isFalse);
      expect(r.gw.authorisations, 1);
    });

    test('the irreducible case costs 2, and ONLY that case', () async {
      final w = _World();
      w.projects['guest-G'] = ['p1', 'p2'];
      final r = _rig(world: w);
      await _tapTelegram(r, footprint: _withWork);
      expect(r.gw.authorisations, 1);

      // GoTrue refuses: the identity is somebody else's. The authorisation is
      // spent and no session was issued — there is nothing left to use.
      final handoff = PwaAuthHandoff.take(r.store)!;
      final fork = r.service.completeOAuthReturn(handoff, _collision());
      expect(fork.failure, PwaVerificationFailure.destinationAlreadyRegistered);
      expect(r.gw.authorisations, 1, reason: 'the fork starts nothing by itself');

      // Only an explicit choice starts the second one.
      await r.service
          .startOAuth(PwaOAuthProviderKind.telegram, PwaOAuthJourney.signIn);
      expect(r.gw.authorisations, 2);
      expect(r.gw.calls, ['link:telegram', 'signin:telegram']);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('THE DECISION  fail closed, on the server\'s answers only', () {
    test('a virgin guest is the ONLY anonymous case that signs in', () {
      expect(
          pwaTelegramJourneyFor(
              isAnonymous: true, userAskedSignIn: false, footprint: _virgin),
          PwaOAuthJourney.signIn);
      expect(
          pwaTelegramJourneyFor(
              isAnonymous: true, userAskedSignIn: false, footprint: _withWork),
          PwaOAuthJourney.link);
    });

    test('AUTH-TG-19b every doubt resolves to LINK', () {
      // Each clause broken on its own. None may reach the sign-in door.
      final doubts = <String, PwaGuestFootprint>{
        'entitlement not read yet': PwaGuestFootprint.unknown,
        'entitlement still loading': const PwaGuestFootprint(
            entitlementKnown: false, libraryRestored: true, projects: 0,
            visions: 0, freeCredits: 3, passCredits: 0, creditsAvailable: 3,
            hasActivePass: false),
        'library not restored yet': const PwaGuestFootprint(
            entitlementKnown: true, libraryRestored: false, projects: 0,
            visions: 0, freeCredits: 3, passCredits: 0, creditsAvailable: 3,
            hasActivePass: false),
        'has a project': const PwaGuestFootprint(
            entitlementKnown: true, libraryRestored: true, projects: 1,
            visions: 0, freeCredits: 3, passCredits: 0, creditsAvailable: 3,
            hasActivePass: false),
        'has a vision': const PwaGuestFootprint(
            entitlementKnown: true, libraryRestored: true, projects: 0,
            visions: 1, freeCredits: 3, passCredits: 0, creditsAvailable: 3,
            hasActivePass: false),
        'holds a pass': const PwaGuestFootprint(
            entitlementKnown: true, libraryRestored: true, projects: 0,
            visions: 0, freeCredits: 3, passCredits: 0, creditsAvailable: 3,
            hasActivePass: true),
        'holds paid credits': const PwaGuestFootprint(
            entitlementKnown: true, libraryRestored: true, projects: 0,
            visions: 0, freeCredits: 3, passCredits: 10, creditsAvailable: 13,
            hasActivePass: false),
        'wallet does not add up': const PwaGuestFootprint(
            entitlementKnown: true, libraryRestored: true, projects: 0,
            visions: 0, freeCredits: 3, passCredits: 0, creditsAvailable: 7,
            hasActivePass: false),
        'nothing left to spend': const PwaGuestFootprint(
            entitlementKnown: true, libraryRestored: true, projects: 0,
            visions: 0, freeCredits: 0, passCredits: 0, creditsAvailable: 0,
            hasActivePass: false),
      };
      doubts.forEach((why, f) {
        expect(f.nothingToLose, isFalse, reason: why);
        expect(
            pwaTelegramJourneyFor(
                isAnonymous: true, userAskedSignIn: false, footprint: f),
            PwaOAuthJourney.link,
            reason: '$why must take the door that loses nothing');
      });
    });

    test('an account that is already somebody\'s only ever LINKS', () {
      // Adding Telegram to an identified account must not sign them out of it.
      expect(
          pwaTelegramJourneyFor(
              isAnonymous: false, userAskedSignIn: false, footprint: _virgin),
          PwaOAuthJourney.link);
    });

    test('the person\'s own word wins', () {
      expect(
          pwaTelegramJourneyFor(
              isAnonymous: true, userAskedSignIn: true, footprint: _withWork),
          PwaOAuthJourney.signIn,
          reason: 'they tapped "already have an account"');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('TRIAL  three before, three after, once', () {
    test('TG-TRIAL-01 a virgin guest keeps exactly its trial', () async {
      final r = _rig();
      expect(r.world.mySpaces, 3);
      await _tapTelegram(r, footprint: _virgin);
      final handoff = PwaAuthHandoff.take(r.store)!;
      r.world.createdFresh('user-N');
      r.service.completeOAuthReturn(handoff, _ok());

      expect(r.world.mySpaces, 3,
          reason: 'no loss: the engine projects the trial for the new account '
              'exactly as it did for the guest');
      expect(r.world.spaces['guest-G'], 3,
          reason: 'and the guest it left behind is UNREACHABLE — no session '
              'can ever return to an abandoned anonymous user, so its '
              'projection is not a second spendable trial');
      expect(r.gw.authorisations, 1);
    });

    test('TG-TRIAL-02 the same Telegram always lands on the same account',
        () async {
      // Sign out, come back as a new guest, use the SAME Telegram.
      final r = _rig();
      await r.service.signOut();
      expect(r.world.isAnonymous, isTrue);

      await _tapTelegram(r, footprint: _virgin);
      final handoff = PwaAuthHandoff.take(r.store)!;
      r.world.signInAs('user-U');
      r.service.completeOAuthReturn(handoff, _ok());

      expect(r.world.currentUserId, 'user-U');
      expect(r.world.mySpaces, 0,
          reason: 'U spent its trial long ago and does NOT get another: the '
              'identity resolves to the same account every time, so no '
              'number of fresh guests multiplies a trial');
    });

    test('TG-TRIAL-03 signing in moves nothing — not credits, not projects',
        () async {
      final r = _rig();
      final guestSpacesBefore = r.world.spaces['guest-G'];
      final uSpacesBefore = r.world.spaces['user-U'];
      final uProjectsBefore = [...r.world.projects['user-U']!];

      await _tapTelegram(r, footprint: _virgin);
      final handoff = PwaAuthHandoff.take(r.store)!;
      r.world.signInAs('user-U');
      r.service.completeOAuthReturn(handoff, _ok());

      expect(r.world.spaces['user-U'], uSpacesBefore,
          reason: 'U does not receive the guest\'s 3, and its own trial is '
              'not reset');
      expect(r.world.spaces['guest-G'], guestSpacesBefore);
      expect(r.world.projects['user-U'], uProjectsBefore);
      expect(r.world.myProjects, uProjectsBefore);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('SAFETY  nothing that was guaranteed stopped being guaranteed', () {
    test('AUTH-TG-05..09 a collision moves NOTHING on either side', () async {
      final w = _World();
      w.projects['guest-G'] = ['p1', 'p2'];
      w.spaces['guest-G'] = 1;
      final r = _rig(world: w);
      await _tapTelegram(r, footprint: _withWork);
      final handoff = PwaAuthHandoff.take(r.store)!;
      final after = r.service.completeOAuthReturn(handoff, _collision());

      expect(after.failure, PwaVerificationFailure.destinationAlreadyRegistered);
      expect(w.currentUserId, 'guest-G', reason: 'AUTH-TG-05: no merge');
      expect(w.projects['guest-G'], ['p1', 'p2'], reason: 'AUTH-TG-06');
      expect(w.projects['user-U'], ['u1', 'u2'], reason: 'AUTH-TG-07');
      expect(w.spaces['guest-G'], 1, reason: 'AUTH-TG-08');
      expect(w.spaces['user-U'], 0, reason: 'AUTH-TG-09');
      expect(after.switchedAccount, isFalse);
    });

    test('AUTH-TG-10 an existing account\'s paid Spaces survive a sign-in',
        () async {
      final w = _World();
      w.spaces['user-U'] = 10; // a purchased pack
      final r = _rig(world: w);
      await _tapTelegram(r, footprint: _virgin);
      final handoff = PwaAuthHandoff.take(r.store)!;
      w.signInAs('user-U');
      r.service.completeOAuthReturn(handoff, _ok());
      expect(w.spaces['user-U'], 10);
      expect(w.myProjects, ['u1', 'u2']);
    });

    test('AUTH-TG-12/13 cancel and failure mutate nothing', () async {
      for (final ret in [_cancelled(), _collision()]) {
        final w = _World();
        w.projects['guest-G'] = ['p1'];
        final r = _rig(world: w);
        await _tapTelegram(r, footprint: _withWork);
        final handoff = PwaAuthHandoff.take(r.store)!;
        final before = w.currentUserId;
        r.service.completeOAuthReturn(handoff, ret);
        expect(w.currentUserId, before);
        expect(w.projects['guest-G'], ['p1']);
        expect(w.spaces['guest-G'], 3);
        expect(w.spaces['user-U'], 0);
      }
    });

    test('AUTH-TG-14 a cold start with no hand-off concludes nothing', () {
      final r = _rig();
      r.world.linkTelegram();
      final s = r.service.completeOAuthReturn(null, _ok());
      expect(s.switchedAccount, isFalse);
      expect(s.identityPreserved, isFalse);
      expect(r.world.currentUserId, 'guest-G');
      expect(r.world.mySpaces, 3);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('SCOPE  Facebook and the SDK were not touched', () {
    final sheet = File(
      'lib/features/pwa/presentation/pwa_account_sheet.dart',
    ).readAsStringSync();

    test('AUTH-TG-20 Facebook still uses the journey its own screen asks for',
        () {
      expect(
          sheet.contains(
              'startFacebook(signIn: _signInMode)'),
          isTrue,
          reason: 'no opportunistic refactor: Facebook is functionally '
              'unchanged, and the resolver is Telegram-only');
      // The resolver must not be reachable from the Facebook handler.
      final fbBlock = sheet.substring(sheet.indexOf('Future<void> _facebook()'),
          sheet.indexOf('Future<void> _telegram()'));
      expect(fbBlock.contains('pwaTelegramJourneyFor'), isFalse);
    });

    test('AUTH-TG-19 state and PKCE stay the SDK\'s job', () {
      // Nothing in the auth layer may hand-build an OAuth parameter: state,
      // the code challenge and the verifier are supabase_flutter's, and a
      // home-made one would be a CSRF hole.
      for (final f in Directory('lib/features/pwa/auth')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        for (final forbidden in const [
          'code_challenge',
          'code_verifier',
          'response_type=',
          '&state=',
          '?state=',
        ]) {
          expect(src.contains(forbidden), isFalse,
              reason: '${f.path} must not build OAuth parameters by hand');
        }
      }
      // And the two doors are still the SDK's own calls.
      final gw = File('lib/features/pwa/auth/pwa_oauth_gateway.dart')
          .readAsStringSync();
      expect(gw.contains('_auth.linkIdentity('), isTrue);
      expect(gw.contains('_auth.signInWithOAuth('), isTrue);
    });

    test('AUTH-TG-16/17/18 the purchase guard, ABA and roles are untouched here',
        () {
      // This change is auth-only. Asserted on what the CODE reaches for, not
      // on words in prose — the file explains the trial projection, so it says
      // "ledger" on purpose. What it must never do is import billing or call a
      // payment route.
      final journey = File(
        'lib/features/pwa/auth/pwa_telegram_journey.dart',
      ).readAsStringSync();
      final imports = RegExp(r'^import .*;$', multiLine: true)
          .allMatches(journey)
          .map((m) => m.group(0)!)
          .toList();
      expect(imports, ["import 'pwa_oauth_gateway.dart' show PwaOAuthJourney;"],
          reason: 'one import, and it is the journey enum');
      for (final forbidden in const [
        'payments/',
        'checkout',
        'ACCOUNT_REQUIRED',
        'billing_',
        'pwaEntitlementProvider',
        'user_roles',
      ]) {
        expect(journey.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('the collision screen speaks about DATA, in every language', () {
      for (final locale in const [Locale('en'), Locale('km'), Locale('fr')]) {
        final l = pwaL10nFor(locale);
        expect(l.authTgExistsTitle.trim(), isNotEmpty, reason: '$locale');
        expect(l.authTgExistsBody(2).trim(), isNotEmpty, reason: '$locale');
        expect(l.authTgExistsBody(2), contains('2'),
            reason: '$locale: it names how much stays behind');
        expect(l.authTgExistsBodyNoneIsDistinct, isTrue, reason: '$locale');
        expect(l.authTgExistsNotice.trim(), isNotEmpty, reason: '$locale');
        expect(l.authTgExistsPrimary.trim(), isNotEmpty, reason: '$locale');
        // And it must not fall through to the key, nor borrow the old words.
        expect(l.authTgExistsTitle, isNot(contains('pwaAuth')));
        expect(l.authTgExistsTitle, isNot(equals(l.authWelcomeBack)));
      }
    });
  });
}

extension on PwaL10n {
  /// The zero case is its own sentence, not the plural with a 0 in it.
  bool get authTgExistsBodyNoneIsDistinct =>
      authTgExistsBody(0) != authTgExistsBody(1);
}
