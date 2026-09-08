/// AUTH01-AUTH15 + PAY01-PAY10 — identity and the paywall.
///
/// What these tests are actually defending
/// ---------------------------------------
/// Two invariants, both of which fail silently if nobody checks them:
///
///   1. The two identity journeys stay separate. Attaching a NEW identity keeps
///      the user; signing in to an EXISTING account replaces them and brings
///      NOTHING across. Every accidental merge in this space looks like a
///      convenience while it is being written and like lost work or a free
///      upgrade afterwards.
///
///   2. The paywall is a projection of SERVER state. No local counter, no
///      inferred "you have used your one", no paywall opened by a timeout.
///
/// The transport is faked here on purpose. Whether GoTrue preserves a user_id is
/// not a question a widget test can answer, and pretending otherwise would be
/// worse than not testing it — so it was answered against the REAL staging
/// project first (`backend/pwa_staging_identity_probe.py`, 12/12) and what is
/// checked here is that the app behaves correctly GIVEN each answer, including
/// the answer the probe says should never happen.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/core/providers/locale_provider.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_controller.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_service.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_email_otp_channel.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_verification_channel.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement_controller.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_translations.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_account_sheet.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_paywall.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_theme.dart'
    show pwaSurface;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

// ── Test doubles ─────────────────────────────────────────────────────────────

/// A verification transport with no network. Scripted outcomes, and a log of
/// what it was asked to do — which is how "the app did not silently start the
/// other journey" becomes checkable rather than assumed.
class _FakeChannel implements PwaVerificationChannel {
  _FakeChannel({
    this.sendResult = const PwaVerificationResult.ok(),
    this.verifyResult = const PwaVerificationResult.ok(),
    this.onVerified,
  });

  PwaVerificationResult sendResult;
  PwaVerificationResult verifyResult;

  /// What the transport does to the session when the code checks out. Called
  /// DURING verify, because that is when a real one changes who you are — and
  /// the service reads the user id either side of exactly that moment.
  final void Function()? onVerified;

  final calls = <String>[];

  @override
  PwaVerificationKind get kind => PwaVerificationKind.email;

  @override
  bool get isConfigured => true;

  @override
  bool looksValid(String destination) => destination.contains('@');

  @override
  Future<PwaVerificationResult> send(String destination) async {
    calls.add('send:$destination');
    return sendResult;
  }

  @override
  Future<PwaVerificationResult> verify(String destination, String code) async {
    calls.add('verify:$destination:$code');
    if (verifyResult.isOk) onVerified?.call();
    return verifyResult;
  }

  @override
  Future<PwaVerificationResult> resend(String destination) async {
    calls.add('resend:$destination');
    return sendResult;
  }
}

/// The narrow slice of GoTrue the service touches. Not a mock of the SDK — a
/// stand-in for the session, so identity transitions can be scripted.
class _FakeAuth implements GoTrueSlice {
  _FakeAuth({String userId = 'u-guest', this.anonymous = true, String email = ''})
      : _id = userId,
        _email = email;

  String _id;
  String _email;
  bool anonymous;
  bool hasSession = true;
  int anonymousSignIns = 0;
  int signOuts = 0;

  /// What the transport does to the identity when a verification succeeds.
  void becomeIdentified(String email) {
    _email = email;
    anonymous = false;
  }

  void becomeDifferentUser(String id, String email) {
    _id = id;
    _email = email;
    anonymous = false;
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
    _id = 'u-guest-$anonymousSignIns';
    _email = '';
    anonymous = true;
    hasSession = true;
  }

  @override
  Future<void> signOutLocal() async {
    signOuts++;
    hasSession = false;
  }
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

PwaEntitlement _ent(Map<String, Object?> body) => PwaEntitlement.parse(body);

void main() {
  // ── AUTH: the two journeys ─────────────────────────────────────────────────

  group('AUTH — identity', () {
    test('AUTH01 a fresh visitor is a Guest, with no identity and no gate',
        () {
      final auth = _FakeAuth();
      final s = PwaAuthService.forTest(auth, _FakeChannel(), _FakeChannel());
      final state = s.currentState();
      expect(state.stage, PwaAuthStage.guest);
      expect(state.isAnonymous, isTrue);
      expect(state.email, isEmpty);
    });

    test('AUTH02 linking sends a code and waits — it does not sign anyone in',
        () async {
      final auth = _FakeAuth();
      final link = _FakeChannel();
      final s = PwaAuthService.forTest(auth, link, _FakeChannel());
      final state = await s.beginLinkIdentity('me@example.com');
      expect(state.stage, PwaAuthStage.awaitingCode);
      expect(state.journey, PwaAuthJourney.linkNewIdentity);
      expect(link.calls, ['send:me@example.com']);
      // Still a Guest until the code is verified.
      expect(auth.isAnonymous, isTrue);
    });

    test('AUTH03 UPGRADE-IN-PLACE: verifying keeps the SAME user', () async {
      final auth = _FakeAuth(userId: 'u-42');
      // The identity attaches DURING verification, keeping the same id — which
      // is what the probe measured against the real project (B2/B5/B6).
      final link = _FakeChannel(
          onVerified: () => auth.becomeIdentified('me@example.com'));
      final s = PwaAuthService.forTest(auth, link, _FakeChannel());
      await s.beginLinkIdentity('me@example.com');
      final state = await s.submitCode('me@example.com', '123456');

      expect(state.stage, PwaAuthStage.identified);
      expect(state.userId, 'u-42');
      expect(state.identityPreserved, isTrue,
          reason: 'same user_id before and after — nothing to migrate');
      expect(state.switchedAccount, isFalse);
    });

    test(
        'AUTH04 if the id CHANGED on the link journey, the app stops claiming '
        'the work came along', () async {
      // The probe says this cannot happen. If it ever did, the UI must not keep
      // promising "your work is saved" — so the promise is derived from the
      // measurement, not from the journey.
      // Cambodia auth (2026-09-08) hardened this further: a LINK that came
      // back as a different user is not a success of any kind. It is refused
      // as `identityMismatch`, the previous session is restored, and nothing
      // is claimed — see AUTH26 in pwa_auth_cambodia_test.dart.
      final auth = _FakeAuth(userId: 'u-42');
      final link = _FakeChannel(
          onVerified: () => auth.becomeDifferentUser('u-99', 'me@example.com'));
      final s = PwaAuthService.forTest(auth, link, _FakeChannel());
      await s.beginLinkIdentity('me@example.com');
      final state = await s.submitCode('me@example.com', '123456');

      expect(state.identityPreserved, isFalse);
      expect(state.switchedAccount, isFalse);
      expect(state.stage, isNot(PwaAuthStage.identified));
      expect(state.failure, PwaVerificationFailure.identityMismatch);
    });

    test(
        'AUTH05 an email that already has an account STOPS the link journey; '
        'it does not fall through to sign-in', () async {
      final auth = _FakeAuth();
      final link = _FakeChannel(
        sendResult: const PwaVerificationResult.failed(
            PwaVerificationFailure.destinationAlreadyRegistered),
      );
      final signIn = _FakeChannel();
      final s = PwaAuthService.forTest(auth, link, signIn);

      final state = await s.beginLinkIdentity('taken@example.com');
      expect(state.failure, PwaVerificationFailure.destinationAlreadyRegistered);
      expect(state.stage, PwaAuthStage.guest);
      // THE assertion: the other journey was never started on its own.
      expect(signIn.calls, isEmpty,
          reason: 'switching journeys is the person\'s decision, not a fallback');
      expect(auth.isAnonymous, isTrue);
    });

    test('AUTH06 sign-in to an existing account is a DIFFERENT user', () async {
      final auth = _FakeAuth(userId: 'u-guest');
      final signIn = _FakeChannel(
          onVerified: () =>
              auth.becomeDifferentUser('u-existing', 'other@example.com'));
      final s = PwaAuthService.forTest(auth, _FakeChannel(), signIn);

      await s.beginSignInExisting('other@example.com');
      final state = await s.submitCode('other@example.com', '123456');

      expect(state.stage, PwaAuthStage.identified);
      expect(state.userId, 'u-existing');
      expect(state.switchedAccount, isTrue);
      expect(state.identityPreserved, isFalse);
      expect(signIn.calls.first, 'send:other@example.com');
    });

    test(
        'AUTH07 nothing in the client transfers quota, credits or projects '
        'between users', () {
      // A structural check, deliberately over the SOURCE: the identity layer
      // must contain no migration, no copy, no claim. A test that only asserted
      // behaviour would pass while someone added one.
      const banned = [
        'transferCredits',
        'migrateProjects',
        'copyLedger',
        'claimBonus',
        'mergeAccounts',
      ];
      for (final file in [
        'lib/features/pwa/auth/pwa_auth_service.dart',
        'lib/features/pwa/auth/pwa_email_otp_channel.dart',
        'lib/features/pwa/auth/pwa_auth_controller.dart',
      ]) {
        final src = _read(file);
        for (final term in banned) {
          expect(src.contains(term), isFalse,
              reason: '$file must not $term — rule 3 of the frozen spec');
        }
      }
    });

    test('AUTH08 a wrong code keeps the person on the code step', () async {
      final auth = _FakeAuth();
      final link = _FakeChannel(
        verifyResult: const PwaVerificationResult.failed(
            PwaVerificationFailure.invalidCode),
      );
      final s = PwaAuthService.forTest(auth, link, _FakeChannel());
      await s.beginLinkIdentity('me@example.com');
      final state = await s.submitCode('me@example.com', '000000');

      expect(state.stage, PwaAuthStage.awaitingCode);
      expect(state.failure, PwaVerificationFailure.invalidCode);
      expect(auth.isAnonymous, isTrue);
    });

    test('AUTH09 a send-quota refusal is reported as rate-limited, not failure',
        () {
      // Staging's built-in SMTP answers 429 `over_email_send_rate_limit`. That
      // is a DELIVERY limit; the identity operation was not refused, and the
      // copy must not tell the person their address was rejected.
      final r = PwaEmailOtpChannel.translateForTest(const AuthException(
          'email rate limit exceeded',
          statusCode: '429',
          code: 'over_email_send_rate_limit'));
      expect(r.failure, PwaVerificationFailure.rateLimited);
    });

    test('AUTH10 `email_exists` maps to the journey fork, never to an error',
        () {
      final r = PwaEmailOtpChannel.translateForTest(const AuthException(
          'A user with this email address has already been registered',
          statusCode: '422',
          code: 'email_exists'));
      expect(r.failure, PwaVerificationFailure.destinationAlreadyRegistered);
    });

    test('AUTH11 an expired OTP is an invalid code, and is retryable in place',
        () {
      final r = PwaEmailOtpChannel.translateForTest(const AuthException(
          'Token has expired or is invalid',
          statusCode: '403',
          code: 'otp_expired'));
      expect(r.failure, PwaVerificationFailure.invalidCode);
    });

    test('AUTH12 signing out mints a NEW Guest rather than stranding the tab',
        () async {
      final auth = _FakeAuth(userId: 'u-real', anonymous: false,
          email: 'me@example.com');
      final s = PwaAuthService.forTest(auth, _FakeChannel(), _FakeChannel());
      final state = await s.signOut();

      expect(auth.signOuts, 1);
      expect(auth.anonymousSignIns, 1);
      expect(state.stage, PwaAuthStage.guest);
      expect(state.isAnonymous, isTrue);
      expect(state.userId, isNot('u-real'),
          reason: 'a new Guest is a new user with its own entitlement');
    });

    testWidgets('AUTH13 the account sheet asks for an address, then a code',
        (tester) async {
      final auth = _FakeAuth();
      final link = _FakeChannel();
      final service = PwaAuthService.forTest(auth, link, _FakeChannel());
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPwaAccountSheet(context),
            child: const Text('open'),
          ),
        ),
        overrides: [pwaAuthServiceProvider.overrideWithValue(service)],
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.accountTitle), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'me@example.com');
      await tester.pump();
      await tester.tap(find.text(l.accountSend));
      await tester.pumpAndSettle();

      expect(find.text(l.accountCodeTitle), findsOneWidget);
      expect(link.calls, contains('send:me@example.com'));
    });

    testWidgets(
        'AUTH14 the "already registered" screen offers a CHOICE, and shows '
        'that guest work does not come across', (tester) async {
      final service = PwaAuthService.forTest(
        _FakeAuth(),
        _FakeChannel(
          sendResult: const PwaVerificationResult.failed(
              PwaVerificationFailure.destinationAlreadyRegistered),
        ),
        _FakeChannel(),
      );
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPwaAccountSheet(context),
            child: const Text('open'),
          ),
        ),
        overrides: [pwaAuthServiceProvider.overrideWithValue(service)],
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l = pwaL10nFor(const Locale('en'));
      await tester.enterText(find.byType(TextField).first, 'taken@example.com');
      await tester.pump();
      await tester.tap(find.text(l.accountSend));
      await tester.pumpAndSettle();

      // Cambodia auth: the fork reads "Welcome back" for every method, names
      // the method, keeps the rule that guest work stays put, and offers the
      // sign-in as ONE explicit action.
      expect(find.text(l.authWelcomeBack), findsOneWidget);
      expect(find.text(l.authExistsEmail), findsOneWidget);
      expect(find.text(l.accountExistsBody), findsOneWidget);
      expect(find.text(l.authContinueExisting), findsOneWidget);
      expect(find.text(l.accountChangeEmail), findsOneWidget);
    });

    testWidgets(
        'AUTH16 the primary action stays LEGIBLE once it is enabled',
        (tester) async {
      // Found by the Khmer visual review, and it is a whole class of bug: an
      // explicit TextStyle beats a button's `foregroundColor`, and `pwaSans`
      // carries `pwaInk` by default — so a label written the obvious way paints
      // near-black on the black pill. The English review missed it because the
      // button it photographed was DISABLED.
      //
      // Asserted as CONTRAST rather than as a specific colour, so it keeps
      // holding when someone restyles the button.
      final service = PwaAuthService.forTest(
          _FakeAuth(), _FakeChannel(), _FakeChannel());
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPwaAccountSheet(context),
            child: const Text('open'),
          ),
        ),
        overrides: [pwaAuthServiceProvider.overrideWithValue(service)],
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Enabled only once the address looks usable.
      await tester.enterText(find.byType(TextField).first, 'me@example.com');
      await tester.pumpAndSettle();

      double contrastOfPrimary({required bool disabled}) {
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        final label = tester.widget<Text>(find.descendant(
            of: find.byType(FilledButton), matching: find.byType(Text)));
        final states = disabled
            ? <WidgetState>{WidgetState.disabled}
            : <WidgetState>{};
        // The disabled pill is translucent black over the sheet's ivory, so the
        // comparison has to be against what is actually PAINTED, not against a
        // colour with an alpha channel.
        final raw = button.style!.backgroundColor!.resolve(states)!;
        final bg = Color.alphaBlend(raw, pwaSurface);
        final fg = label.style?.color
            ?? button.style!.foregroundColor!.resolve(states)!;
        return _contrast(bg, fg);
      }

      expect(contrastOfPrimary(disabled: false), greaterThanOrEqualTo(4.5),
          reason: 'the ENABLED primary label must be readable on the black pill');

      // And the other half, which the first version of this fix broke: a light
      // label on the pale disabled pill is just as unreadable as a dark one on
      // the black pill. One fixed colour cannot serve both states.
      await tester.enterText(find.byType(TextField).first, 'nonsense');
      await tester.pumpAndSettle();
      expect(contrastOfPrimary(disabled: true), greaterThanOrEqualTo(4.5),
          reason: 'the DISABLED primary label must be readable on the pale pill');
    });

    testWidgets('AUTH15 with no auth service the sheet says so, honestly',
        (tester) async {
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPwaAccountSheet(context),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(pwaL10nFor(const Locale('en')).authUnavailable),
          findsOneWidget);
    });
  });

  // ── PAY: the paywall is a projection of server state ───────────────────────

  group('PAY — paywall', () {
    test('PAY01 a fresh Guest reads as ONE free vision, watermarked', () {
      final e = _ent({
        'can_generate': true,
        'access_source': 'free',
        'tier': 'free',
        'free_credits': 1,
        'credits_available': 1,
        'watermarked': true,
      });
      expect(e.state, PwaBillingState.freeAvailable);
      expect(e.canGenerate, isTrue);
      expect(e.watermarked, isTrue);
      expect(e.requiresPurchase, isFalse);
    });

    test('PAY02 a refusal with no credits is the paywall state', () {
      final e = _ent({
        'can_generate': false,
        'billing_state': 'FREE_EXHAUSTED',
        'free_credits': 0,
        'credits_available': 0,
      });
      expect(e.state, PwaBillingState.freeExhausted);
      expect(e.requiresPurchase, isTrue);
    });

    test('PAY03 an active pass generates clean, and is not a paywall', () {
      final e = _ent({
        'can_generate': true,
        'access_source': 'pass',
        'has_active_pass': true,
        'pass_credits': 28,
        'credits_available': 28,
        'watermarked': false,
      });
      expect(e.state, PwaBillingState.passActive);
      expect(e.watermarked, isFalse);
      expect(e.requiresPurchase, isFalse);
    });

    test('PAY04 premium ROLE with no measured pass is PASS_REQUIRED, not empty',
        () {
      // RC-PR3b: the role is features, the pass is the generation. Telling a
      // paying customer "you have no credits" would be the wrong sentence.
      final e = _ent({
        'can_generate': false,
        'billing_state': 'PASS_REQUIRED',
        'tier': 'premium',
        'has_active_pass': false,
      });
      expect(e.state, PwaBillingState.passRequired);
      expect(e.requiresPurchase, isTrue);
    });

    test('PAY05 no answer is `loading`; a failed answer is `billingError` '
        'that FAILS OPEN', () {
      expect(const PwaEntitlement.loading().state, PwaBillingState.loading);
      expect(const PwaEntitlement.loading().isKnown, isFalse);

      final unknown = PwaEntitlement.parse(null);
      expect(unknown.state, PwaBillingState.billingError);
      expect(unknown.canGenerate, isTrue,
          reason: 'the SERVER refuses; a dropped packet must not lock out a '
              'paying customer');
      expect(unknown.requiresPurchase, isFalse);
    });

    test('PAY06 a 402 refusal is applied at once, without a second round trip',
        () {
      final c = PwaEntitlementController(null);
      c.state = _ent({
        'can_generate': true,
        'access_source': 'free',
        'free_credits': 1,
      });
      c.applyRefusal('FREE_EXHAUSTED');
      expect(c.state.state, PwaBillingState.freeExhausted);
      expect(c.state.canGenerate, isFalse);
    });

    test('PAY07 only a BILLING refusal can open a paywall', () {
      const quota = PwaGenerationFailure(
        code: 'QUOTA_EXHAUSTED',
        userMessage: '',
        retryable: false,
        billingState: 'FREE_EXHAUSTED',
      );
      const timeout = PwaGenerationFailure(
          code: 'TIMEOUT', userMessage: '', retryable: true);
      const unreachable = PwaGenerationFailure(
          code: 'BACKEND_UNREACHABLE', userMessage: '', retryable: true);

      expect(quota.isBillingRefusal, isTrue);
      expect(timeout.isBillingRefusal, isFalse);
      expect(unreachable.isBillingRefusal, isFalse);
    });

    test('PAY08 the catalogue is READ, and store-only rows are marked as such',
        () {
      // The canonical rows measured against real staging: credit packs carry no
      // store id and are KHQR-eligible; the two subscription passes are Apple /
      // RevenueCat products and cannot be sold on the web (§10).
      final e = _ent({
        'can_generate': false,
        'billing_state': 'FREE_EXHAUSTED',
        'products': [
          {
            'sku': 'pack_10',
            'type': 'CREDIT_PACK',
            'credits': 10,
            'price_usd': 1.99,
            'currency': 'USD',
            'store_only': false,
            'web_enabled': true,
          },
          {
            'sku': 'weekly_pass',
            'type': 'PASS',
            'credits': 30,
            'duration_days': 7,
            'price_usd': 7.99,
            'currency': 'USD',
            'store_only': true,
            'web_enabled': false,
          },
        ],
      });
      expect(e.products.length, 2);
      expect(e.products.first.credits, 10);
      expect(e.products.last.storeOnly, isTrue);
      // The store-only row is PARSED — the client must be able to tell that it
      // exists, and the server's `store_only` is how — but it is not
      // merchandise here. Phase 9: the purchase surface is exactly
      // `purchasableOnWeb`, and `productsForDisplay`, which grouped the App
      // Store passes to the bottom of the same list rather than removing them,
      // is gone.
      expect(e.purchasableOnWeb.map((p) => p.sku), ['pack_10']);
    });

    test('PAY09 the client holds NO gateway credential and speaks NO gateway '
        'protocol', () {
      final e = _ent({
        'can_generate': false,
        'billing_state': 'FREE_EXHAUSTED',
        'payment': {'provider': 'none', 'configured': false},
      });
      expect(e.paymentConfigured, isFalse,
          reason: 'the SERVER decides whether a purchase can complete');

      // 2026-08-18 — this assertion changed shape with the KHQR rail, and the
      // reason matters. It used to guard `pwa_payment_provider.dart`, a
      // client-side abstraction for a checkout that did not exist; that file is
      // gone, because the answer turned out to be that the browser needs NO
      // provider abstraction at all. It sends a sku, the server does the rest.
      //
      // So the check moved from one file to the WHOLE of `lib/`, and from
      // "no production-like code" to the thing that actually matters: no
      // credential and no signing material can ever be in a web bundle, because
      // a credential in a bundle is a credential published.
      final banned = [
        'payway_api_key',
        'payway_merchant',
        'merchant_id',
        'hmac',
        'sha512',
        'checkout-sandbox.payway',
        'checkout.payway',
        'generate-qr',
        'check-transaction',
      ];
      final offenders = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final src = file.readAsStringSync().toLowerCase();
        for (final term in banned) {
          if (src.contains(term)) offenders.add('${file.path}: $term');
        }
      }
      expect(offenders, isEmpty,
          reason: 'the browser must never hold a gateway credential or sign a '
              'gateway request');
    });

    testWidgets('PAY10 the paywall renders the refused state in all three '
        'languages, with no purchase button', (tester) async {
      for (final code in ['km', 'en', 'fr']) {
        final controller = PwaEntitlementController(() async => {
              'can_generate': false,
              'billing_state': 'FREE_EXHAUSTED',
              'payment': {'provider': 'none', 'configured': false},
              'products': [
                {
                  'sku': 'pack_10',
                  'type': 'CREDIT_PACK',
                  'credits': 10,
                  'price_usd': 1.99,
                  'currency': 'USD',
                  'store_only': false,
                  'web_enabled': true,
                },
              ],
            });
        await controller.refresh();

        await tester.pumpWidget(ProviderScope(
          overrides: [
            pwaEntitlementProvider.overrideWith((ref) => controller),
            localeProvider.overrideWith(
                (ref) => LocaleNotifier(deviceLocale: code)),
          ],
          child: MaterialApp(
            locale: Locale(code),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('km'), Locale('fr')],
            home: const Scaffold(body: PwaPaywallSheet()),
          ),
        ));
        await tester.pumpAndSettle();

        final l = pwaL10nFor(Locale(code));
        expect(find.text(l.paywallFreeUsedTitle), findsOneWidget,
            reason: 'locale $code');
        expect(find.text(l.paywallUnavailableTitle), findsOneWidget,
            reason: 'locale $code — the honest "you cannot buy here yet"');
        // The price is a fact from the catalogue; there is no way to pay it.
        expect(find.text('\$1.99'), findsOneWidget, reason: 'locale $code');
        expect(find.byType(FilledButton), findsNothing,
            reason: 'locale $code — no Buy button while no provider exists');
      }
    });

    test('PAY11 every locale carries the whole paywall + account vocabulary',
        () {
      const required = [
        'pwaPaywallFreeUsedTitle',
        'pwaPaywallPassRequiredTitle',
        'pwaPaywallUnavailableTitle',
        'pwaPaywallStoreOnly',
        'pwaAccountTitle',
        'pwaAccountExistsTitle',
        'pwaAccountSwitchedTitle',
        'pwaAuthErrRateLimited',
      ];
      for (final dict in [pwaEnTranslations, pwaKmTranslations,
        pwaFrTranslations]) {
        for (final key in required) {
          expect(dict.containsKey(key), isTrue, reason: 'missing $key');
          expect(dict[key]!.trim(), isNotEmpty, reason: 'empty $key');
        }
      }
    });
  });
}

/// WCAG relative-luminance contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }
  final l1 = lum(a), l2 = lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

String _read(String relative) {
  final f = File(relative);
  expect(f.existsSync(), isTrue, reason: 'missing $relative');
  return f.readAsStringSync();
}
