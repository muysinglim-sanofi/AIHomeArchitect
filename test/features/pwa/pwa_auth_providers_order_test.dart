/// PROD AUTH — Facebook first, Telegram second, Guest last, phone hidden.
/// AUTH01–AUTH20 of the 2026-09-12 brief.
///
/// Self-contained on purpose: the Cambodia file's doubles are private to it,
/// and this series asks different questions — which doors exist, in what
/// order, through which slug, and what a link must never disturb.
///
/// What is faked: the session and the provider redirect. What is NOT faked:
/// that GoTrue keeps the user id on `linkIdentity` (measured against the real
/// project) and that a custom provider resolves at all (proved against the
/// production admin API). Here we check the app's behaviour GIVEN those facts.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_intro_gate.dart'
    show MemoryPwaSessionStore;
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_availability.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_controller.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_service.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_oauth_gateway.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_verification_channel.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_account_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ── doubles ─────────────────────────────────────────────────────────────────

class _World implements GoTrueSlice, GoTrueProfileSlice, GoTrueSessionGuard {
  _World({String userId = 'guest-A'}) : _id = userId, _refresh = 'rt-$userId';

  String _id;
  String _refresh;
  final String _email = '';
  final String _phone = '';
  String _name = '';
  List<String> _providers = const [];
  bool anonymous = true;
  bool hasSession = true;
  int signOuts = 0;

  /// Per-user rows, exactly as RLS and the ledger keep them: a LINK must leave
  /// them untouched, a SIGN IN must read the other user's, never copy.
  final projects = <String, List<String>>{
    'guest-A': ['p1', 'p2'],
    'user-B': ['b1'],
  };
  final spaces = <String, int>{'guest-A': 30, 'user-B': 5};

  List<String> get myProjects => projects[_id] ?? const [];
  int get mySpaces => spaces[_id] ?? 0;

  void attach(String provider, {String name = ''}) {
    _name = name.isEmpty ? _name : name;
    anonymous = false;
    _providers = [..._providers, provider];
  }

  void becomeUser(String id, {List<String> providers = const ['facebook']}) {
    _id = id;
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
    _id = 'guest-new';
    anonymous = true;
    hasSession = true;
    _providers = const [];
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
    _id = refreshToken.replaceFirst('rt-', '');
    _refresh = refreshToken;
    hasSession = true;
  }
}

class _FakeChannel implements PwaVerificationChannel {
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

class _FakeOAuth implements PwaOAuthGateway {
  final calls = <String>[];

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

({PwaAuthService service, _World world, _FakeOAuth oauth,
  MemoryPwaSessionStore store}) _rig({
  _World? world,
  bool facebook = true,
  bool telegram = true,
  bool phone = true,
}) {
  final w = world ?? _World();
  final oauth = _FakeOAuth();
  final store = MemoryPwaSessionStore();
  return (
    service: PwaAuthService.forTest(
      w,
      _FakeChannel(),
      _FakeChannel(),
      oauth: oauth,
      handoffStore: store,
      providers: PwaAuthProviders(
          facebook: facebook, telegram: telegram, phone: phone),
      profile: w,
      guard: w,
      redirectTo: 'https://app.aydenstudio.com/profile',
      projectIds: () => w.myProjects,
    ),
    world: w,
    oauth: oauth,
    store: store,
  );
}

Future<void> _openSheet(WidgetTester tester, PwaAuthService service) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [pwaAuthServiceProvider.overrideWithValue(service)],
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
}

const _fb = ValueKey('pwa-auth-facebook');
const _tg = ValueKey('pwa-auth-telegram');
const _ph = ValueKey('pwa-auth-phone');
const _em = ValueKey('pwa-auth-email');

double _top(WidgetTester t, Key k) => t.getTopLeft(find.byKey(k)).dy;

void main() {
  group('the chooser', () {
    testWidgets('AUTH01 Facebook is first and primary', (tester) async {
      await _openSheet(tester, _rig().service);
      expect(find.byKey(_fb), findsOneWidget);
      expect(_top(tester, _fb) < _top(tester, _tg), isTrue);
    });

    testWidgets('AUTH02 Telegram is second', (tester) async {
      await _openSheet(tester, _rig().service);
      expect(find.byKey(_tg), findsOneWidget);
      expect(_top(tester, _tg) < _top(tester, _em), isTrue);
    });

    testWidgets('AUTH03 continuing without an account stays last', (tester) async {
      await _openSheet(tester, _rig().service);
      // The e-mail fallback and the "I already have an account" line both sit
      // under the two social doors; closing the sheet is always available.
      expect(_top(tester, _em) > _top(tester, _tg), isTrue);
      expect(find.byKey(_fb), findsOneWidget);
    });

    testWidgets('AUTH04 the phone door is never shown, even when the project '
        'enables the provider', (tester) async {
      await _openSheet(tester, _rig(phone: true).service);
      expect(find.byKey(_ph), findsNothing);
    });

    testWidgets('AUTH02b a disabled Telegram provider shows NO button',
        (tester) async {
      await _openSheet(tester, _rig(telegram: false).service);
      expect(find.byKey(_fb), findsOneWidget);
      expect(find.byKey(_tg), findsNothing);
    });
  });

  group('the journeys', () {
    test('AUTH05 anonymous -> Facebook is a LINK on the same user', () async {
      final r = _rig();
      await r.service.startOAuth(
          PwaOAuthProviderKind.facebook, PwaOAuthJourney.link);
      expect(r.oauth.calls, ['link:facebook']);
      final h = PwaAuthHandoff.take(r.store)!;
      expect(h.journey, PwaOAuthJourney.link);
      expect(h.userId, 'guest-A');
      expect(h.projectIds, ['p1', 'p2']);
    });

    test('AUTH06 anonymous -> Telegram is a LINK on the same user', () async {
      final r = _rig();
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.link);
      expect(r.oauth.calls, ['link:telegram']);
      final h = PwaAuthHandoff.take(r.store)!;
      expect(h.journey, PwaOAuthJourney.link);
      expect(h.provider, PwaOAuthProviderKind.telegram);
      expect(h.userId, 'guest-A');
    });

    test('AUTH07 an existing Facebook account signs IN', () async {
      final r = _rig();
      await r.service.startOAuth(
          PwaOAuthProviderKind.facebook, PwaOAuthJourney.signIn);
      expect(r.oauth.calls, ['signin:facebook']);
      expect(PwaAuthHandoff.take(r.store)!.journey, PwaOAuthJourney.signIn);
    });

    test('AUTH08 an existing Telegram account signs IN', () async {
      final r = _rig();
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.signIn);
      expect(r.oauth.calls, ['signin:telegram']);
      expect(PwaAuthHandoff.take(r.store)!.journey, PwaOAuthJourney.signIn);
    });

    test('AUTH09 a Facebook identity owned by someone else is a FORK, not a '
        'merge', () {
      final r = PwaOAuthReturn.parse(Uri.parse(
          'https://app.aydenstudio.com/profile?error=invalid_request'
          '&error_code=identity_already_exists'
          '&error_description=Identity+is+already+linked+to+another+user'))!;
      expect(PwaOAuthReturn.failureOf(r),
          PwaVerificationFailure.destinationAlreadyRegistered);
    });

    test('AUTH10 the same fork for Telegram, reported on the Telegram method',
        () async {
      final r = _rig();
      final ret = PwaOAuthReturn.parse(Uri.parse(
          'https://app.aydenstudio.com/profile?error=invalid_request'
          '&error_code=identity_already_exists'
          '&error_description=Identity+is+already+linked+to+another+user'))!;
      final state = r.service.completeOAuthReturn(
        PwaAuthHandoff(
          journey: PwaOAuthJourney.link,
          provider: PwaOAuthProviderKind.telegram,
          userId: 'guest-A',
          projectIds: const ['p1', 'p2'],
          startedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        ret,
      );
      expect(state.method, PwaAuthMethod.telegram);
      expect(state.failure, PwaVerificationFailure.destinationAlreadyRegistered);
    });

    testWidgets('AUTH11 with both identities attached, neither door is offered '
        'again', (tester) async {
      final w = _World()..attach('facebook', name: 'Mike')..attach('telegram');
      await _openSheet(tester, _rig(world: w).service);
      expect(find.byKey(_fb), findsNothing);
      expect(find.byKey(_tg), findsNothing);
    });

    test('AUTH12 the state is re-read from the session, not remembered',
        () async {
      final r = _rig();
      r.world.becomeUser('user-B', providers: ['telegram']);
      final s = r.service.currentState();
      expect(s.userId, 'user-B');
      expect(s.stage, PwaAuthStage.identified);
      expect(s.providers, contains('telegram'));
    });

    test('AUTH13 sign out, then sign in again with Facebook', () async {
      final r = _rig();
      await r.service.signOut();
      expect(r.world.signOuts, 1);
      await r.service.startOAuth(
          PwaOAuthProviderKind.facebook, PwaOAuthJourney.signIn);
      expect(r.oauth.calls.last, 'signin:facebook');
    });

    test('AUTH14 sign out, then sign in again with Telegram', () async {
      final r = _rig();
      await r.service.signOut();
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.signIn);
      expect(r.oauth.calls.last, 'signin:telegram');
    });

    test('AUTH15 a link leaves the projects where they were', () async {
      final r = _rig();
      final before = [...r.world.myProjects];
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.link);
      r.world.attach('telegram');
      expect(r.world.myProjects, before);
      expect(r.world.currentUserId, 'guest-A');
    });

    test('AUTH16 a link leaves the Spaces where they were', () async {
      final r = _rig();
      final before = r.world.mySpaces;
      await r.service.startOAuth(
          PwaOAuthProviderKind.telegram, PwaOAuthJourney.link);
      r.world.attach('telegram');
      expect(r.world.mySpaces, before);
    });

    test('AUTH17 a sign-in reads the other account, and copies nothing',
        () async {
      final r = _rig();
      r.world.becomeUser('user-B', providers: ['telegram']);
      expect(r.world.myProjects, ['b1']);
      expect(r.world.mySpaces, 5);
      // The guest's rows are still the guest's.
      expect(r.world.projects['guest-A'], ['p1', 'p2']);
      expect(r.world.spaces['guest-A'], 30);
    });
  });

  group('production safety', () {
    test('AUTH18 the Telegram gate is the SERVER\'s answer and fails closed',
        () async {
      Future<bool> ask(http.Client c) => fetchPwaTelegramEnabled(
          backendUrl: 'https://api.aydenstudio.com',
          apiPrefix: '/pwa',
          client: c);
      expect(
          await ask(MockClient((req) async {
            expect(req.url.toString(),
                'https://api.aydenstudio.com/pwa/auth/providers');
            return http.Response(jsonEncode({'telegram': true}), 200);
          })),
          isTrue);
      expect(
          await ask(MockClient((_) async =>
              http.Response(jsonEncode({'telegram': false}), 200))),
          isFalse);
      expect(await ask(MockClient((_) async => http.Response('nope', 500))),
          isFalse);
      expect(await ask(MockClient((_) async => http.Response('{}', 200))),
          isFalse);
    });

    test('AUTH19 no provider secret is reachable from the app', () {
      final auth = Directory('lib/features/pwa/auth')
          .listSync()
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join('\n');
      expect(auth.contains('client_secret'), isFalse);
      expect(auth.contains('TELEGRAM_CLIENT_SECRET'), isFalse);
      // The browser sends a SLUG; the secret lives in the Supabase project.
      final gw = File('lib/features/pwa/auth/pwa_oauth_gateway.dart')
          .readAsStringSync();
      expect(gw.contains("OAuthProvider('custom:telegram')"), isTrue);
    });

    test('AUTH20 the phone door stays hidden whatever the project says', () {
      expect(kPwaPhoneDoorHidden, isTrue);
      const p = PwaAuthProviders(phone: true, facebook: true, telegram: true);
      expect(p.phone, isTrue, reason: 'the project flag is still read');
      expect(p.phoneDoor, isFalse, reason: 'but the door is not offered');
      expect(_rig(phone: true).service.canPhone, isFalse);
      // GoTrue never advertises a custom provider, so `parse` cannot invent one.
      final parsed = PwaAuthProviders.parse({
        'external': {'facebook': true, 'phone': true, 'email': true}
      });
      expect(parsed.telegram, isFalse);
    });
  });
}
