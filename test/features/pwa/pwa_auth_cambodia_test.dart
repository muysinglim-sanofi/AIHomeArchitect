/// CAMBODIA AUTH — Facebook + phone + email fallback. AUTH01–AUTH30.
///
/// The matrix from the 2026-09-08 brief, numbered as the brief numbers it.
/// (`pwa_auth_paywall_test.dart` carries an older AUTH01–16 series from the
/// August identity round; both files are kept, and their numbering is not the
/// same list.)
///
/// What is faked, and what is not
/// -------------------------------
/// The transports are faked: whether GoTrue preserves a user_id on
/// `updateUser` was measured against the real staging project
/// (`backend/pwa_staging_identity_probe.py`), and whether a stale
/// `phone_change` row catches a verification was reproduced at the database
/// (`backend/pwa_staging_auth_phone_test.py`, AUTH26.1–13). What is checked
/// HERE is that the app behaves correctly GIVEN each answer — including the
/// answers that must never be accepted.
///
/// Pure-Dart pieces (E.164, OAuth return parsing, the settings parser) are
/// tested as the functions they are.
library;

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_intro_gate.dart'
    show MemoryPwaSessionStore;
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_controller.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_service.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_email_otp_channel.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_oauth_gateway.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_phone_number.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_phone_otp_channel.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_verification_channel.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_translations.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_account_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, GoTrueClient;

// ── Test doubles ─────────────────────────────────────────────────────────────

/// The session, scripted. Projects and Spaces are modelled as maps keyed by
/// user id, because that is what RLS and the ledger do: nothing here can move
/// a row from one key to another except a test that does it on purpose.
class _World implements GoTrueSlice, GoTrueProfileSlice, GoTrueSessionGuard {
  _World({String userId = 'guest-A'}) : _id = userId {
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
  int signOuts = 0;
  final restored = <String>[];

  /// Per-user data. A LINK must leave these untouched; a SIGN IN must read
  /// the other user's, never copy.
  final projects = <String, List<String>>{
    'guest-A': ['p1', 'p2'],
    'user-B': ['b1'],
  };
  final spaces = <String, int>{'guest-A': 30, 'user-B': 5};

  List<String> get myProjects => projects[_id] ?? const [];
  int get mySpaces => spaces[_id] ?? 0;

  void attachEmail(String email) {
    _email = email;
    anonymous = false;
    _providers = [..._providers, 'email'];
  }

  void attachPhone(String e164) {
    _phone = e164;
    anonymous = false;
    _providers = [..._providers, 'phone'];
  }

  void attachFacebook(String name) {
    _name = name;
    anonymous = false;
    _providers = [..._providers, 'facebook'];
  }

  void becomeUser(String id,
      {String email = '', String phone = '', String name = '',
      List<String> providers = const ['email']}) {
    _id = id;
    _email = email;
    _phone = phone;
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
  Future<void> signOutLocal() async {
    signOuts++;
    hasSession = false;
  }

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
    // A refresh token names its user: `rt-<id>`.
    final id = refreshToken.replaceFirst('rt-', '');
    _id = id;
    _refresh = refreshToken;
    hasSession = true;
    if (id.startsWith('guest')) {
      anonymous = true;
      _email = '';
      _phone = '';
      _name = '';
      _providers = const [];
    }
  }
}

class _FakeChannel implements PwaVerificationChannel {
  _FakeChannel({
    this.kind = PwaVerificationKind.email,
    this.sendResult = const PwaVerificationResult.ok(),
    this.verifyResult = const PwaVerificationResult.ok(),
    this.onVerified,
  });

  @override
  final PwaVerificationKind kind;
  PwaVerificationResult sendResult;
  PwaVerificationResult verifyResult;
  final void Function()? onVerified;
  final calls = <String>[];

  /// How long a send takes. A real SMS request takes a few hundred ms, and
  /// the duplicate-tap tests need that window to exist.
  Duration sendDelay = Duration.zero;

  @override
  bool get isConfigured => true;

  @override
  bool looksValid(String d) => kind == PwaVerificationKind.phone
      ? PwaPhoneNumber.looksValid(d)
      : d.contains('@');

  @override
  Future<PwaVerificationResult> send(String d) async {
    calls.add('send:$d');
    if (sendDelay > Duration.zero) await Future<void>.delayed(sendDelay);
    return sendResult;
  }

  @override
  Future<PwaVerificationResult> verify(String d, String code) async {
    calls.add('verify:$d:$code');
    if (verifyResult.isOk) onVerified?.call();
    return verifyResult;
  }

  @override
  Future<PwaVerificationResult> resend(String d) async {
    calls.add('resend:$d');
    return sendResult;
  }
}

class _FakeOAuth implements PwaOAuthGateway {
  final calls = <String>[];
  Object? throwOnStart;

  @override
  Future<bool> startLink(PwaOAuthProviderKind p, {required String redirectTo}) async {
    calls.add('link:${p.name}:$redirectTo');
    if (throwOnStart != null) throw throwOnStart!;
    return true;
  }

  @override
  Future<bool> startSignIn(PwaOAuthProviderKind p,
      {required String redirectTo}) async {
    calls.add('signin:${p.name}:$redirectTo');
    if (throwOnStart != null) throw throwOnStart!;
    return true;
  }
}

/// A full service: email + phone + Facebook, over one scripted world.
({PwaAuthService service, _World world, _FakeChannel phoneLink,
  _FakeChannel phoneSignIn, _FakeChannel emailLink, _FakeChannel emailSignIn,
  _FakeOAuth oauth, MemoryPwaSessionStore store}) _rig({
  _World? world,
  PwaVerificationResult phoneLinkSend = const PwaVerificationResult.ok(),
  PwaVerificationResult phoneLinkVerify = const PwaVerificationResult.ok(),
  PwaVerificationResult emailLinkSend = const PwaVerificationResult.ok(),
  void Function()? onPhoneLinked,
  void Function()? onPhoneSignedIn,
  void Function()? onEmailLinked,
  void Function()? onEmailSignedIn,
  bool facebook = true,
  bool phone = true,
}) {
  final w = world ?? _World();
  final phoneLink = _FakeChannel(
      kind: PwaVerificationKind.phone,
      sendResult: phoneLinkSend,
      verifyResult: phoneLinkVerify,
      onVerified: onPhoneLinked ?? () => w.attachPhone('+85512345678'));
  final phoneSignIn = _FakeChannel(
      kind: PwaVerificationKind.phone,
      onVerified: onPhoneSignedIn ??
          () => w.becomeUser('user-B', phone: '+85512345678', providers: ['phone']));
  final emailLink = _FakeChannel(
      sendResult: emailLinkSend,
      onVerified: onEmailLinked ?? () => w.attachEmail('me@example.com'));
  final emailSignIn = _FakeChannel(
      onVerified: onEmailSignedIn ??
          () => w.becomeUser('user-B', email: 'b@example.com'));
  final oauth = _FakeOAuth();
  final store = MemoryPwaSessionStore();
  final s = PwaAuthService.forTest(
    w,
    emailLink,
    emailSignIn,
    phoneLink: phone ? phoneLink : null,
    phoneSignIn: phone ? phoneSignIn : null,
    oauth: facebook ? oauth : null,
    handoffStore: store,
    providers: PwaAuthProviders(facebook: facebook, phone: phone),
    profile: w,
    guard: w,
    redirectTo: 'https://preprod.aydenstudio.com/profile',
    projectIds: () => w.myProjects,
  );
  return (
    service: s,
    world: w,
    phoneLink: phoneLink,
    phoneSignIn: phoneSignIn,
    emailLink: emailLink,
    emailSignIn: emailSignIn,
    oauth: oauth,
    store: store,
  );
}

Widget _app(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('km'), Locale('fr')],
        home: child,
      ),
    );

Future<void> _openSheet(WidgetTester tester, PwaAuthService service,
    {bool signIn = false, PwaAuthMethod? method}) async {
  await tester.pumpWidget(_app(
    Builder(
      builder: (context) => TextButton(
        onPressed: () => showPwaAccountSheet(context, signIn: signIn, method: method),
        child: const Text('open'),
      ),
    ),
    overrides: [pwaAuthServiceProvider.overrideWithValue(service)],
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

PwaOAuthReturn _ret(String url) => PwaOAuthReturn.parse(Uri.parse(url))!;

PwaAuthHandoff _handoff(PwaOAuthJourney j, {String userId = 'guest-A'}) =>
    PwaAuthHandoff(
      journey: j,
      provider: PwaOAuthProviderKind.facebook,
      userId: userId,
      projectIds: const ['p1', 'p2'],
      startedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

void main() {
  final l = pwaL10nFor(const Locale('en'));

  group('AUTH01–02  guest first', () {
    test('AUTH01 a fresh visitor is a Guest with no wall and no identity', () {
      final r = _rig();
      final s = r.service.currentState();
      expect(s.stage, PwaAuthStage.guest);
      expect(s.isAnonymous, isTrue);
      expect(s.email, isEmpty);
      expect(s.phone, isEmpty);
      expect(s.identityLabel, isEmpty);
      // Nothing was sent, nothing was started, by merely looking.
      expect(r.phoneLink.calls, isEmpty);
      expect(r.emailLink.calls, isEmpty);
      expect(r.oauth.calls, isEmpty);
    });

    test('AUTH02 the guest session persists: no second anonymous user is minted '
        'while one exists', () async {
      final r = _rig();
      await r.service.beginLinkIdentity('me@example.com');
      await r.service.beginPhoneLink('012 345 678');
      expect(r.world.anonymousSignIns, 0);
      expect(r.world.currentUserId, 'guest-A');
    });
  });

  group('AUTH03–05  SECURE MY ACCOUNT keeps the same user', () {
    test('AUTH03 Guest A + new email → UID A preserved', () async {
      final r = _rig();
      await r.service.beginLinkIdentity('me@example.com');
      final s = await r.service.submitCode('me@example.com', '123456');
      expect(s.stage, PwaAuthStage.identified);
      expect(s.userId, 'guest-A');
      expect(s.identityPreserved, isTrue);
      expect(s.switchedAccount, isFalse);
      expect(s.email, 'me@example.com');
      expect(s.method, PwaAuthMethod.email);
    });

    test('AUTH04 Guest A + new Facebook → UID A preserved (measured on return)',
        () {
      final r = _rig();
      // What the page finds after GoTrue linked the identity and the SDK
      // exchanged the code: same user, no longer anonymous, facebook attached.
      r.world.attachFacebook('Mike');
      final s = r.service.completeOAuthReturn(
          _handoff(PwaOAuthJourney.link), _ret('https://x/profile?code=abc'));
      expect(s.stage, PwaAuthStage.identified);
      expect(s.userId, 'guest-A');
      expect(s.identityPreserved, isTrue);
      expect(s.switchedAccount, isFalse);
      expect(s.method, PwaAuthMethod.facebook);
      expect(s.displayName, 'Mike');
      expect(s.oauthPending, isTrue);
    });

    test('AUTH05 Guest A + new phone → UID A preserved', () async {
      final r = _rig();
      final before = r.world.currentUserId;
      await r.service.beginPhoneLink('012 345 678');
      final s = await r.service.submitCode('+85512345678', '123456');
      expect(s.stage, PwaAuthStage.identified);
      expect(s.userId, before);
      expect(s.identityPreserved, isTrue);
      expect(s.phone, '+85512345678');
      expect(s.method, PwaAuthMethod.phone);
      // The transport was handed E.164, never the local format.
      expect(r.phoneLink.calls.first, 'send:+85512345678');
    });
  });

  group('AUTH06–08  an EXISTING account is a fork, then a real sign-in', () {
    test('AUTH06 Guest A + existing email B → the link STOPS; sign-in is a '
        'separate, chosen journey; no merge', () async {
      final r = _rig(
          emailLinkSend: const PwaVerificationResult.failed(
              PwaVerificationFailure.destinationAlreadyRegistered));
      final fork = await r.service.beginLinkIdentity('b@example.com');
      expect(fork.failure, PwaVerificationFailure.destinationAlreadyRegistered);
      expect(fork.stage, PwaAuthStage.guest);
      expect(r.emailSignIn.calls, isEmpty, reason: 'never started on its own');

      await r.service.beginSignInExisting('b@example.com');
      final s = await r.service.submitCode('b@example.com', '654321');
      expect(s.stage, PwaAuthStage.identified);
      expect(s.userId, 'user-B');
      expect(s.switchedAccount, isTrue);
      expect(s.identityPreserved, isFalse);
      // A's rows are still A's. Nothing moved.
      expect(r.world.projects['guest-A'], ['p1', 'p2']);
      expect(r.world.spaces['guest-A'], 30);
    });

    test('AUTH07 Guest A + existing Facebook B → "Welcome back" fork, then a '
        'real sign-in; no merge', () async {
      final r = _rig();
      // GoTrue's collision on the LINK path, as it lands in the URL.
      final fork = r.service.completeOAuthReturn(
        _handoff(PwaOAuthJourney.link),
        _ret('https://x/profile?error=server_error'
            '&error_code=identity_already_exists'
            '&error_description=Identity+is+already+linked+to+another+user'),
      );
      expect(fork.failure, PwaVerificationFailure.destinationAlreadyRegistered);
      expect(fork.method, PwaAuthMethod.facebook);
      expect(fork.stage, PwaAuthStage.guest);
      expect(fork.userId, 'guest-A');
      expect(r.oauth.calls, isEmpty, reason: 'nothing started by itself');

      // The person chooses. Only now does a SIGN-IN leave the page.
      await r.service.startFacebook(PwaOAuthJourney.signIn);
      expect(r.oauth.calls, ['signin:facebook:https://preprod.aydenstudio.com/profile']);
      final h = PwaAuthHandoff.take(r.store)!;
      expect(h.journey, PwaOAuthJourney.signIn);
      expect(h.userId, 'guest-A');

      // …and comes back as B.
      r.world.becomeUser('user-B', name: 'Mike', providers: ['facebook']);
      final s = r.service.completeOAuthReturn(h, _ret('https://x/profile?code=zz'));
      expect(s.userId, 'user-B');
      expect(s.switchedAccount, isTrue);
      expect(s.identityPreserved, isFalse);
      expect(r.world.projects['guest-A'], ['p1', 'p2']);
    });

    test('AUTH08 Guest A + existing phone B → fork, then a real phone sign-in; '
        'no merge', () async {
      final r = _rig(
          phoneLinkSend: const PwaVerificationResult.failed(
              PwaVerificationFailure.destinationAlreadyRegistered));
      final fork = await r.service.beginPhoneLink('+85512345678');
      expect(fork.failure, PwaVerificationFailure.destinationAlreadyRegistered);
      expect(fork.method, PwaAuthMethod.phone);
      expect(r.phoneSignIn.calls, isEmpty);

      await r.service.beginPhoneSignIn('+85512345678');
      final s = await r.service.submitCode('+85512345678', '111222');
      expect(s.userId, 'user-B');
      expect(s.switchedAccount, isTrue);
      expect(r.world.projects['guest-A'], ['p1', 'p2']);
      expect(r.world.spaces['guest-A'], 30);
    });
  });

  group('AUTH09–11  projects and Spaces', () {
    test('AUTH09 projects are preserved across a link (same key before/after)',
        () async {
      final r = _rig();
      final before = List.of(r.world.myProjects);
      await r.service.beginPhoneLink('012345678');
      final s = await r.service.submitCode('+85512345678', '123456');
      expect(s.userId, 'guest-A');
      expect(r.world.myProjects, before);
      expect(r.world.projects.keys, containsAll(['guest-A', 'user-B']));
    });

    test('AUTH10 Spaces are preserved across a link: same balance, no second '
        'wallet, no transfer', () async {
      final r = _rig();
      expect(r.world.mySpaces, 30);
      await r.service.beginLinkIdentity('me@example.com');
      await r.service.submitCode('me@example.com', '123456');
      expect(r.world.mySpaces, 30);
      expect(r.world.spaces.length, 2, reason: 'no wallet was created');
      expect(r.world.spaces['user-B'], 5);
    });

    test('AUTH11 signing in to B shows ONLY B\'s projects and Spaces', () async {
      final r = _rig();
      await r.service.beginSignInExisting('b@example.com');
      await r.service.submitCode('b@example.com', '654321');
      expect(r.world.myProjects, ['b1']);
      expect(r.world.mySpaces, 5);
      expect(r.world.projects['guest-A'], ['p1', 'p2'], reason: 'A intact');
    });
  });

  group('AUTH12  email is optional everywhere', () {
    test('AUTH12a a phone-only account has a label, a method, and no email',
        () {
      final r = _rig();
      r.world.attachPhone('+85512345678');
      final s = r.service.currentState();
      expect(s.stage, PwaAuthStage.identified);
      expect(s.email, isEmpty);
      expect(s.identityLabel, '+855 •• ••• 5678');
      expect(s.connectedVia, PwaAuthMethod.phone);
    });

    test('AUTH12b a Facebook-only account shows its name, no email', () {
      final r = _rig();
      r.world.attachFacebook('Mike');
      final s = r.service.currentState();
      expect(s.email, isEmpty);
      expect(s.identityLabel, 'Mike');
      expect(s.connectedVia, PwaAuthMethod.facebook);
    });

    testWidgets('AUTH12c the sheet renders an identified account with '
        'email == null without crashing', (tester) async {
      final r = _rig();
      r.world.attachPhone('+85512345678');
      await _openSheet(tester, r.service, method: PwaAuthMethod.email);
      expect(tester.takeException(), isNull);
    });
  });

  group('AUTH13–14  phone numbers', () {
    test('AUTH13 E.164 normalisation, Cambodia first', () {
      expect(PwaPhoneNumber.normalize('012 345 678'), '+85512345678');
      expect(PwaPhoneNumber.normalize('12345678'), '+85512345678');
      expect(PwaPhoneNumber.normalize('096-123-4567'), '+855961234567');
      expect(PwaPhoneNumber.normalize('+855 12 345 678'), '+85512345678');
      expect(PwaPhoneNumber.normalize('0085512345678'), '+85512345678');
      // International numbers keep their own country.
      expect(PwaPhoneNumber.normalize('+33 6 12 34 56 78'), '+33612345678');
      expect(PwaPhoneNumber.normalize('0612345678', dialCode: '+33'),
          '+33612345678');
      expect(PwaPhoneNumber.normalize('+1 (415) 555-2671'), '+14155552671');
      // Khmer digits from a Khmer keyboard.
      expect(PwaPhoneNumber.normalize('០១២៣៤៥៦៧៨'), '+85512345678');
    });

    test('AUTH13b masking keeps the country and the last four', () {
      expect(PwaPhoneNumber.mask('+85512345678'), '+855 •• ••• 5678');
      expect(PwaPhoneNumber.mask('+33612345678'), '+33 •• ••• 5678');
      expect(PwaPhoneNumber.dialCodeOf('+85512345678'), '+855');
      expect(PwaPhoneNumber.dialCodeOf('+85612345678'), '+856');
    });

    test('AUTH14 an invalid phone is refused before anything is sent', () async {
      for (final bad in ['', '12', 'abc', '+', '+0123456789', '+1234567890123456']) {
        expect(PwaPhoneNumber.normalize(bad), isNull, reason: bad);
      }
      final r = _rig();
      final s = await r.service.beginPhoneLink('12');
      expect(s.failure, PwaVerificationFailure.invalidDestination);
      expect(s.method, PwaAuthMethod.phone);
      expect(r.phoneLink.calls, isEmpty);
    });
  });

  group('AUTH15–17  codes', () {
    test('AUTH15 a wrong code keeps the person on the code step, same user',
        () async {
      final r = _rig(
          phoneLinkVerify: const PwaVerificationResult.failed(
              PwaVerificationFailure.invalidCode));
      await r.service.beginPhoneLink('012345678');
      final s = await r.service.submitCode('+85512345678', '000000');
      expect(s.stage, PwaAuthStage.awaitingCode);
      expect(s.failure, PwaVerificationFailure.invalidCode);
      expect(s.userId, 'guest-A');
      expect(r.world.isAnonymous, isTrue);
    });

    test('AUTH16 an expired code is an invalid code, retryable in place', () {
      final res = PwaPhoneOtpChannel.translateForTest(const AuthException(
          'Token has expired or is invalid',
          statusCode: '403',
          code: 'otp_expired'));
      expect(res.failure, PwaVerificationFailure.invalidCode);
    });

    test('AUTH17 resend goes to the SAME channel and journey; GoTrue\'s send '
        'cadence reads as rate-limited, not failure', () async {
      final r = _rig();
      await r.service.beginPhoneLink('012345678');
      final s = await r.service.resendCode('+85512345678');
      expect(s.stage, PwaAuthStage.awaitingCode);
      expect(r.phoneLink.calls, ['send:+85512345678', 'resend:+85512345678']);
      expect(r.phoneSignIn.calls, isEmpty);

      final res = PwaPhoneOtpChannel.translateForTest(const AuthException(
          'For security purposes, you can only request this after 47 seconds.',
          statusCode: '429',
          code: 'over_sms_send_rate_limit'));
      expect(res.failure, PwaVerificationFailure.rateLimited);
    });

    testWidgets('AUTH17b the sheet holds a resend cooldown after a send',
        (tester) async {
      final r = _rig();
      await _openSheet(tester, r.service, method: PwaAuthMethod.phone);
      await tester.enterText(
          find.byKey(const ValueKey('pwa-auth-phone-field')), '012345678');
      await tester.pump();
      await tester.tap(find.text(l.authContinue));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-auth-code')), findsOneWidget);
      final resend = tester.widget<TextButton>(
          find.byKey(const ValueKey('pwa-auth-resend')));
      expect(resend.onPressed, isNull, reason: 'cooling down');
      expect(find.textContaining('60'), findsOneWidget);
      // Nothing more was sent by rendering the countdown.
      expect(r.phoneLink.calls, ['send:+85512345678']);
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      final after = tester.widget<TextButton>(
          find.byKey(const ValueKey('pwa-auth-resend')));
      expect(after.onPressed, isNotNull);
    });
  });

  group('AUTH18–19  Facebook errors are told apart', () {
    test('AUTH18 a cancel at Facebook is a cancel, not a collision', () {
      final r = _rig();
      final s = r.service.completeOAuthReturn(
        _handoff(PwaOAuthJourney.link),
        _ret('https://x/profile#error=access_denied'
            '&error_description=Permissions+error&sb='),
      );
      expect(s.failure, PwaVerificationFailure.cancelled);
      expect(s.stage, PwaAuthStage.guest);
      expect(s.userId, 'guest-A', reason: 'still the same guest');
    });

    test('AUTH19 a configuration / provider failure is a refusal, not a '
        'collision — before and after the redirect', () async {
      final after = _rig().service.completeOAuthReturn(
        _handoff(PwaOAuthJourney.link),
        _ret('https://x/profile?error=server_error&error_code=bad_oauth_state'
            '&error_description=OAuth+state+is+invalid'),
      );
      expect(after.failure, PwaVerificationFailure.providerRefused);

      final r = _rig();
      r.oauth.throwOnStart = const AuthException(
          'Manual linking is disabled',
          statusCode: '400',
          code: 'manual_linking_disabled');
      final before = await r.service.startFacebook(PwaOAuthJourney.link);
      expect(before.failure, PwaVerificationFailure.providerRefused);
      expect(before.stage, PwaAuthStage.guest);
      // The hand-off was withdrawn: nothing for a later reload to misread.
      expect(PwaAuthHandoff.take(r.store), isNull);
    });
  });

  group('AUTH20–21  session', () {
    test('AUTH20 a reload restores the SAME user: the boot state is the '
        'session, not a flag', () {
      final r = _rig();
      r.world.attachPhone('+85512345678');
      // A "reload" is a brand-new service over the same persisted session.
      final again = PwaAuthService.forTest(r.world, _FakeChannel(), _FakeChannel(),
          profile: r.world);
      final s = again.bootState();
      expect(s.stage, PwaAuthStage.identified);
      expect(s.userId, 'guest-A');
      expect(s.phone, '+85512345678');
      expect(s.oauthPending, isFalse);
      expect(r.world.anonymousSignIns, 0, reason: 'no second guest minted');
    });

    test('AUTH21 explicit sign-out drops the session and mints a NEW guest; '
        'the account\'s cloud data is untouched', () async {
      final r = _rig();
      await r.service.beginSignInExisting('b@example.com');
      await r.service.submitCode('b@example.com', '654321');
      expect(r.world.currentUserId, 'user-B');
      final s = await r.service.signOut();
      expect(r.world.signOuts, 1);
      expect(s.stage, PwaAuthStage.guest);
      expect(s.isAnonymous, isTrue);
      expect(s.userId, isNot('user-B'));
      expect(r.world.projects['user-B'], ['b1']);
      expect(r.world.spaces['user-B'], 5);
    });
  });

  group('AUTH22–25  no merge, regressions, error taxonomy', () {
    test('AUTH22 nothing in the client ever merges: every collision is a '
        'STOP, every sign-in is explicit', () async {
      final r = _rig(
          emailLinkSend: const PwaVerificationResult.failed(
              PwaVerificationFailure.destinationAlreadyRegistered),
          phoneLinkSend: const PwaVerificationResult.failed(
              PwaVerificationFailure.destinationAlreadyRegistered));
      await r.service.beginLinkIdentity('b@example.com');
      await r.service.beginPhoneLink('+85512345678');
      r.service.completeOAuthReturn(
          _handoff(PwaOAuthJourney.link),
          _ret('https://x/p?error_code=identity_already_exists'
              '&error_description=Identity+is+already+linked+to+another+user'));
      expect(r.emailSignIn.calls, isEmpty);
      expect(r.phoneSignIn.calls, isEmpty);
      expect(r.oauth.calls, isEmpty);
      expect(r.world.currentUserId, 'guest-A');
      expect(r.world.projects['guest-A'], ['p1', 'p2']);
    });

    test('AUTH23 the existing email OTP journey is unchanged: updateUser + '
        'emailChange on link, otp(shouldCreateUser:false) + email on sign-in',
        () async {
      // The channel's own mapping, as before.
      expect(
          PwaEmailOtpChannel.translateForTest(const AuthException('x',
                  statusCode: '422', code: 'email_exists'))
              .failure,
          PwaVerificationFailure.destinationAlreadyRegistered);
      final r = _rig(facebook: false, phone: false);
      expect(r.service.providers.hasPrimaryChoice, isFalse);
      await r.service.beginLinkIdentity('me@example.com');
      final s = await r.service.submitCode('me@example.com', '123456');
      expect(s.identityPreserved, isTrue);
      expect(r.emailLink.calls, ['send:me@example.com', 'verify:me@example.com:123456']);
    });

    test('AUTH24 Facebook error codes: collision vs same-account vs cancel vs '
        'no-email vs config', () {
      PwaVerificationFailure? f(String url) => PwaOAuthReturn.failureOf(_ret(url));
      expect(
          f('https://x/p?error_code=identity_already_exists'
              '&error_description=Identity+is+already+linked+to+another+user'),
          PwaVerificationFailure.destinationAlreadyRegistered);
      // Already on THIS account (a retry after a half-finished link): not a
      // stranger's account, and not an error to show as one.
      expect(
          f('https://x/p?error_code=identity_already_exists'
              '&error_description=Identity+is+already+linked'),
          isNull);
      expect(f('https://x/p#error=access_denied&error_description=Permissions+error'),
          PwaVerificationFailure.cancelled);
      expect(
          f('https://x/p?error=server_error&error_description='
              'Error+getting+user+email+from+external+provider'),
          PwaVerificationFailure.providerNoEmail);
      expect(
          f('https://x/p?error_code=email_not_confirmed&error_description='
              'Unverified+email+with+facebook'),
          PwaVerificationFailure.providerNoEmail);
      expect(f('https://x/p?error_code=manual_linking_disabled'),
          PwaVerificationFailure.providerRefused);
      expect(f('https://x/p?error_code=provider_disabled'),
          PwaVerificationFailure.providerRefused);
      expect(f('https://x/p?error_code=bad_oauth_callback'),
          PwaVerificationFailure.providerRefused);
      // A URL with no trace of a round-trip is not a return at all.
      expect(PwaOAuthReturn.parse(Uri.parse('https://x/profile')), isNull);
      expect(PwaOAuthReturn.parse(Uri.parse('https://x/profile?code=abc'))!.hasCode,
          isTrue);
    });

    test('AUTH25 phone collision is `phone_exists`, told apart from every '
        'other refusal', () {
      PwaVerificationFailure? t(String code, {String status = '422', String msg = ''}) =>
          PwaPhoneOtpChannel.translateForTest(
                  AuthException(msg, statusCode: status, code: code))
              .failure;
      expect(t('phone_exists'), PwaVerificationFailure.destinationAlreadyRegistered);
      expect(t('validation_failed', status: '400', msg: 'Invalid phone number format'),
          PwaVerificationFailure.invalidDestination);
      expect(t('user_not_found', status: '422'),
          PwaVerificationFailure.invalidDestination);
      expect(t('sms_send_failed', status: '500'),
          PwaVerificationFailure.unavailable);
      expect(t('phone_provider_disabled', status: '422'),
          PwaVerificationFailure.unavailable);
      expect(t('over_sms_send_rate_limit', status: '429'),
          PwaVerificationFailure.rateLimited);
      expect(t('otp_expired', status: '403'), PwaVerificationFailure.invalidCode);
    });
  });

  group('AUTH26  stale phone_change can never attach to the wrong user', () {
    test('AUTH26a a LINK that came back as a DIFFERENT user is refused, the '
        'previous session is restored, nothing is claimed', () async {
      final r = _rig(onPhoneLinked: () {});
      // The transport "succeeds" but, as GoTrue can when a stale row wins the
      // lookup, hands back the OTHER user's session.
      final ch = r.phoneLink;
      ch.verifyResult = const PwaVerificationResult.ok();
      final rogue = _FakeChannel(
          kind: PwaVerificationKind.phone,
          onVerified: () => r.world.becomeUser('stale-Z', phone: '+85512345678',
              providers: ['phone']));
      final s0 = PwaAuthService.forTest(r.world, r.emailLink, r.emailSignIn,
          phoneLink: rogue, phoneSignIn: r.phoneSignIn, profile: r.world, guard: r.world);
      await s0.beginPhoneLink('+85512345678');
      final s = await s0.submitCode('+85512345678', '123456');
      expect(s.failure, PwaVerificationFailure.identityMismatch);
      expect(s.stage, isNot(PwaAuthStage.identified));
      expect(s.identityPreserved, isFalse);
      expect(s.switchedAccount, isFalse);
      // The guard put A back.
      expect(r.world.restored, ['rt-guest-A']);
      expect(r.world.currentUserId, 'guest-A');
      expect(r.world.isAnonymous, isTrue);
    });

    test('AUTH26b a contested number (a live attempt on another account) '
        'refuses to START the link, so no code is ever sent', () async {
      final r = _rig(
          phoneLinkSend: const PwaVerificationResult.failed(
              PwaVerificationFailure.destinationContested));
      final s = await r.service.beginPhoneLink('+85512345678');
      expect(s.failure, PwaVerificationFailure.destinationContested);
      expect(s.stage, PwaAuthStage.guest);
      expect(r.world.currentUserId, 'guest-A');
    });

    test('AUTH26c the real channel asks the backend to release stale rows '
        'BEFORE requesting an SMS, and stops on `contested`', () async {
      // Exercised through the prepare seam; the GoTrue call itself is not
      // reached because prepare reports a live holder.
      final prepared = <String>[];
      // A GoTrueClient is required by the constructor but never touched on
      // this path; a bogus one proves it.
      final ch = PwaPhoneOtpChannel.linkNewIdentity(
        _neverUsedClient(),
        prepare: (e164) async {
          prepared.add(e164);
          return const PwaPhonePrepareResult(ok: true, contested: 1, cleared: 3);
        },
      );
      final res = await ch.send('012 345 678');
      expect(prepared, ['+85512345678']);
      expect(res.failure, PwaVerificationFailure.destinationContested);
    });
  });

  group('AUTH27–28  taps and grants', () {
    testWidgets('AUTH27 rapid duplicate taps send ONE code', (tester) async {
      final r = _rig();
      r.phoneLink.sendDelay = const Duration(milliseconds: 400);
      await _openSheet(tester, r.service, method: PwaAuthMethod.phone);
      await tester.enterText(
          find.byKey(const ValueKey('pwa-auth-phone-field')), '012345678');
      await tester.pump();
      final btn = find.text(l.authContinue);
      await tester.tap(btn);
      await tester.tap(btn, warnIfMissed: false);
      await tester.tap(btn, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(r.phoneLink.calls.where((c) => c.startsWith('send:')).length, 1);
      expect(find.byKey(const ValueKey('pwa-auth-code')), findsOneWidget);
    });

    test('AUTH27b the controller drops a second call while one is in flight',
        () async {
      final r = _rig();
      final container = ProviderContainer(overrides: [
        pwaAuthServiceProvider.overrideWithValue(r.service),
      ]);
      addTearDown(container.dispose);
      final c = container.read(pwaAuthProvider.notifier);
      final f1 = c.beginPhoneLink('012345678');
      final f2 = c.beginPhoneLink('012345678');
      await Future.wait([f1, f2]);
      expect(r.phoneLink.calls, ['send:+85512345678']);
    });

    test('AUTH28 no auth event grants anything: the client holds no wallet, '
        'no counter, and a link changes no balance', () async {
      final r = _rig();
      final before = Map.of(r.world.spaces);
      await r.service.beginPhoneLink('012345678');
      await r.service.submitCode('+85512345678', '123456');
      r.world.attachFacebook('Mike');
      r.service.completeOAuthReturn(
          _handoff(PwaOAuthJourney.link), _ret('https://x/p?code=1'));
      await r.service.signOut();
      expect(r.world.spaces, before);
    });
  });

  group('AUTH29–30  no email assumption, ABA untouched', () {
    test('AUTH29 core authenticated paths compile and run with email == null',
        () {
      final r = _rig();
      r.world.attachFacebook('');
      final s = r.service.currentState();
      expect(s.stage, PwaAuthStage.identified);
      expect(s.identityLabel, isEmpty);
      expect(s.connectedVia, PwaAuthMethod.facebook);
      // The label falls back to the saved-state line, never to "Guest".
      expect(l.accountLinkedTitle, isNotEmpty);
    });

    test('AUTH29b every locale carries the whole Cambodia auth vocabulary', () {
      const required = [
        'pwaAuthSecureTitle', 'pwaAuthSecureBody', 'pwaAuthContinueFacebook',
        'pwaAuthContinuePhone', 'pwaAuthUseEmail', 'pwaAuthPhoneTitle',
        'pwaAuthPhoneLabel', 'pwaAuthContinue', 'pwaAuthPhoneCodeBody',
        'pwaAuthResendIn', 'pwaAuthWelcomeBack', 'pwaAuthExistsFacebook',
        'pwaAuthExistsPhone', 'pwaAuthExistsEmail', 'pwaAuthContinueExisting',
        'pwaAuthErrInvalidPhone', 'pwaAuthErrContested', 'pwaAuthErrMismatch',
        'pwaAuthErrCancelled', 'pwaAuthErrNoEmail', 'pwaAuthErrProvider',
        'pwaAuthConnectedFacebook', 'pwaAuthConnectedPhone',
        'pwaAuthConnectedEmail', 'pwaAuthMethodsTitle', 'pwaAuthAdd',
        'pwaAuthGuestBody', 'pwaAuthSecureCta',
      ];
      for (final dict in [pwaEnTranslations, pwaKmTranslations, pwaFrTranslations]) {
        for (final key in required) {
          expect(dict.containsKey(key), isTrue, reason: 'missing $key');
          expect(dict[key]!.trim(), isNotEmpty, reason: 'empty $key');
        }
      }
      // Khmer is Khmer, not English left in place.
      expect(pwaKmTranslations['pwaAuthSecureTitle'], matches(RegExp('[ក-៿]')));
      expect(pwaFrTranslations['pwaAuthContinuePhone'], contains('téléphone'));
    });

    test('AUTH30 the settings parser fails CLOSED to email only', () {
      expect(PwaAuthProviders.parse(null), PwaAuthProviders.emailOnly);
      expect(PwaAuthProviders.parse({'external': 'nope'}).facebook, isFalse);
      final p = PwaAuthProviders.parse({
        'external': {'facebook': true, 'phone': false, 'email': true}
      });
      expect(p.facebook, isTrue);
      expect(p.phone, isFalse);
      expect(p.hasPrimaryChoice, isTrue);
      expect(PwaAuthProviders.emailOnly.hasPrimaryChoice, isFalse);
    });
  });

  // ── The sheet: Facebook + phone dominant, email secondary ─────────────────

  group('UI  the account sheet', () {
    testWidgets('UI01 with Facebook and phone on, the chooser leads with them '
        'and email is a text link below "or"', (tester) async {
      final r = _rig();
      await _openSheet(tester, r.service);
      expect(find.text(l.authSecureTitle), findsOneWidget);
      expect(find.text(l.authSecureBody), findsOneWidget);
      final fb = find.byKey(const ValueKey('pwa-auth-facebook'));
      final ph = find.byKey(const ValueKey('pwa-auth-phone'));
      final em = find.byKey(const ValueKey('pwa-auth-email'));
      expect(fb, findsOneWidget);
      expect(ph, findsOneWidget);
      expect(em, findsOneWidget);
      expect(find.text(l.authOr), findsOneWidget);
      // Order, as geometry.
      expect(tester.getTopLeft(ph).dy, greaterThan(tester.getTopLeft(fb).dy));
      expect(tester.getTopLeft(em).dy, greaterThan(tester.getTopLeft(ph).dy));
      // The primary is a filled pill, the email door is a text button.
      expect(find.descendant(of: fb, matching: find.byType(FilledButton)),
          findsOneWidget);
      expect(tester.widget(em), isA<TextButton>());
      expect(tester.takeException(), isNull);
    });

    testWidgets('UI02 with email only, the sheet opens on the address field '
        '(the pre-Cambodia screen, unchanged)', (tester) async {
      final r = _rig(facebook: false, phone: false);
      await _openSheet(tester, r.service);
      expect(find.text(l.accountTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-auth-facebook')), findsNothing);
      expect(find.byKey(const ValueKey('pwa-auth-phone')), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('UI03 Facebook tap leaves for the LINK endpoint, with the '
        'hand-off written first', (tester) async {
      final r = _rig();
      await _openSheet(tester, r.service);
      await tester.tap(find.byKey(const ValueKey('pwa-auth-facebook')));
      // The page is now "leaving": a spinner that never settles, on purpose.
      await tester.pump();
      await tester.pump();
      expect(r.oauth.calls, ['link:facebook:https://preprod.aydenstudio.com/profile']);
      expect(find.text(l.authFacebookLeaving), findsOneWidget);
      final h = PwaAuthHandoff.take(r.store)!;
      expect(h.journey, PwaOAuthJourney.link);
      expect(h.userId, 'guest-A');
      expect(h.projectIds, ['p1', 'p2']);
    });

    testWidgets('UI04 opened on SIGN IN, Facebook leaves for the sign-in '
        'endpoint', (tester) async {
      final r = _rig();
      await _openSheet(tester, r.service, signIn: true);
      expect(find.text(l.accountSignInTitle), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pwa-auth-facebook')));
      await tester.pump();
      await tester.pump();
      expect(r.oauth.calls, ['signin:facebook:https://preprod.aydenstudio.com/profile']);
    });

    testWidgets('UI05 phone: +855 by default, a code screen, then the '
        'account is settled', (tester) async {
      final r = _rig();
      await _openSheet(tester, r.service);
      await tester.tap(find.byKey(const ValueKey('pwa-auth-phone')));
      await tester.pumpAndSettle();
      final dial = tester.widget<TextField>(find.byKey(const ValueKey('pwa-auth-dial')));
      expect(dial.controller!.text, '+855');
      await tester.enterText(
          find.byKey(const ValueKey('pwa-auth-phone-field')), '012 345 678');
      await tester.pump();
      await tester.tap(find.text(l.authContinue));
      await tester.pumpAndSettle();
      expect(find.text(l.accountCodeTitle), findsOneWidget);
      expect(find.text(l.authPhoneCodeBody('+85512345678')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('pwa-auth-code')), '123456');
      await tester.tap(find.text(l.accountVerify));
      await tester.pumpAndSettle();
      expect(r.world.currentUserId, 'guest-A');
      expect(r.world.currentPhone, '+85512345678');
      expect(tester.takeException(), isNull);
    });

    testWidgets('UI06 the Facebook "Welcome back" fork offers ONE explicit '
        'action, and starts nothing by itself', (tester) async {
      final r = _rig();
      final container = ProviderContainer(overrides: [
        pwaAuthServiceProvider.overrideWithValue(r.service),
      ]);
      addTearDown(container.dispose);
      container.read(pwaAuthProvider.notifier).applyOAuthReturn(
          _handoff(PwaOAuthJourney.link),
          _ret('https://x/p?error_code=identity_already_exists'
              '&error_description=Identity+is+already+linked+to+another+user'));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('km'), Locale('fr')],
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPwaAccountSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(l.authWelcomeBack), findsOneWidget);
      expect(find.text(l.authExistsFacebook), findsOneWidget);
      expect(find.text(l.accountExistsBody), findsOneWidget);
      expect(r.oauth.calls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('pwa-auth-continue-existing')));
      await tester.pump();
      await tester.pump();
      expect(r.oauth.calls, ['signin:facebook:https://preprod.aydenstudio.com/profile']);
    });

    testWidgets('UI07 a cancelled Facebook round-trip lands back on the '
        'chooser with a quiet line, not an error screen', (tester) async {
      final r = _rig();
      final container = ProviderContainer(overrides: [
        pwaAuthServiceProvider.overrideWithValue(r.service),
      ]);
      addTearDown(container.dispose);
      container.read(pwaAuthProvider.notifier).applyOAuthReturn(
          _handoff(PwaOAuthJourney.link),
          _ret('https://x/p#error=access_denied&error_description=denied'));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: _app(Builder(
          builder: (context) => TextButton(
            onPressed: () => showPwaAccountSheet(context),
            child: const Text('open'),
          ),
        )),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pwa-auth-facebook')), findsOneWidget);
      expect(find.text(l.verificationFailure(PwaVerificationFailure.cancelled)),
          findsOneWidget);
      // Closing the sheet consumes the outcome: it is shown once.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(container.read(pwaAuthProvider).oauthPending, isFalse);
    });

    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      testWidgets('UI08 the chooser and the phone step hold at '
          '${size.width.toInt()}×${size.height.toInt()} in every language',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        for (final code in const ['en', 'km', 'fr']) {
          final r = _rig();
          await tester.pumpWidget(ProviderScope(
            overrides: [pwaAuthServiceProvider.overrideWithValue(r.service)],
            child: MaterialApp(
              locale: Locale(code),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en'), Locale('km'), Locale('fr')],
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showPwaAccountSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'chooser $code');
          // The sheet is never wider than a dialog on a monitor: its doors
          // (which fill the sheet's width) are capped, whatever the window.
          final door = tester.getSize(find.byKey(const ValueKey('pwa-auth-facebook')));
          expect(door.width, lessThanOrEqualTo(560), reason: '$code $size');
          await tester.tap(find.byKey(const ValueKey('pwa-auth-phone')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'phone $code');
          await tester.enterText(
              find.byKey(const ValueKey('pwa-auth-phone-field')), '012345678');
          await tester.pump();
          await tester.tap(find.text(pwaL10nFor(Locale(code)).authContinue));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'code $code');
          // Back out cleanly for the next language.
          await tester.tapAt(const Offset(5, 5));
          await tester.pumpAndSettle();
        }
      });
    }
  });
}

/// A GoTrueClient that must never be reached. The phone channel's prepare
/// step runs BEFORE any GoTrue call, and this proves it.
_NeverClient _neverUsedClient() => _NeverClient();

class _NeverClient implements GoTrueClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('GoTrue must not be reached: ${invocation.memberName}');
}
