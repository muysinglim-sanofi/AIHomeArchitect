/// PAYWAY01-PAYWAY16 — the KHQR payment surface.
///
/// The one thing these tests exist to defend
/// -----------------------------------------
/// A browser cannot know it was paid. Every other assertion here is a
/// consequence of that: there is no client-side transition into
/// [PwaPaymentState.granted], no timer that concludes, no reading of a returning
/// app, and no "I have paid" button that unlocks anything. The tests below try
/// each of those in turn and check that nothing happens.
///
/// The transport is faked, and the fake is scriptable rather than fixed, so the
/// SEQUENCES a real payment goes through — awaiting → pushback seen → verified →
/// granted, or awaiting → expired — are what is exercised, not a single frame.
/// What a widget test cannot answer (does PayWay really sign like that, is the
/// grant really idempotent) is answered against the real gateway protocol and
/// the real Postgres in `backend/payway_adapter_test.py`,
/// `backend/pwa_staging_payments_test.py` and
/// `backend/pwa_staging_payway_db_test.py`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/core/providers/locale_provider.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement_controller.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_payment.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_payment_controller.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_external_launcher.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_translations.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_payment_sheet.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_paywall.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Test doubles ─────────────────────────────────────────────────────────────

/// A 1×1 transparent PNG, so `Image.memory` has something real to decode.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

Map<String, Object?> _server({
  required String state,
  String tranId = 'A0123456789abcdef012',
  int credits = 10,
  double amount = 1.99,
  String checkoutUrl =
      'https://checkout-sandbox.payway.com.kh/eyJzdGVwIjoicGF5bWVudCJ9',
  bool checkoutStale = false,
  String qr = '',
  String deeplink = '',
  String failureReason = '',
  String? expiresAt,
}) => {
      'ok': true,
      'tran_id': tranId,
      'state': state,
      'terminal': const {'GRANTED', 'FAILED', 'EXPIRED', 'CANCELLED'}
          .contains(state),
      'sku': 'pack_10',
      'credits': credits,
      'amount': amount,
      'currency': 'USD',
      'checkout_url': checkoutUrl,
      'checkout_mode': 'redirect',
      'checkout_stale': checkoutStale,
      'qr_string': qr,
      'qr_image': qr.isEmpty ? '' : _pngBase64,
      'deeplink': deeplink,
      'expires_at': expiresAt ??
          DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
      'failure_reason': failureReason,
      'poll_interval_ms': 1000,
    };

/// A scriptable server. Each poll consumes the next scripted answer and then
/// repeats the last one, which is how a real sequence is expressed without a
/// clock.
class _FakeServer {
  _FakeServer({
    this.checkoutAnswer,
    List<Map<String, Object?>>? pollAnswers,
    this.openAnswer,
    this.cancelAnswer,
  }) : _polls = List.of(pollAnswers ?? const []);

  Map<String, Object?>? checkoutAnswer;
  final List<Map<String, Object?>> _polls;
  Map<String, Object?>? openAnswer;
  Map<String, Object?>? cancelAnswer;

  final calls = <String>[];
  Map<String, Object?>? _lastPoll;

  PwaPaymentGateway get gateway => PwaPaymentGateway(
        startCheckout: ({required String sku, required String attemptKey}) async {
          calls.add('checkout:$sku:$attemptKey');
          return checkoutAnswer ?? _server(state: 'AWAITING_PAYMENT');
        },
        orderStatus: (tranId) async {
          calls.add('status:$tranId');
          if (_polls.isNotEmpty) _lastPoll = _polls.removeAt(0);
          return _lastPoll ?? _server(state: 'AWAITING_PAYMENT');
        },
        openOrder: () async {
          calls.add('open');
          return openAnswer ?? const {'ok': true, 'open': false};
        },
        cancelOrder: (tranId) async {
          calls.add('cancel:$tranId');
          return cancelAnswer ?? _server(state: 'CANCELLED');
        },
      );
}

/// Counts the entitlement re-reads. The ONE side effect a successful payment is
/// allowed to have.
class _CountingEntitlement extends PwaEntitlementController {
  _CountingEntitlement() : super(() async => _entitlementBody);

  static const _entitlementBody = <String, Object?>{
    'can_generate': true,
    'access_source': 'pass',
    'has_active_pass': true,
    'watermarked': false,
    'pass_credits': 10,
    'credits_available': 10,
  };

  int refreshes = 0;

  @override
  Future<void> refresh() async {
    refreshes++;
    await super.refresh();
  }
}

class _RecordingLauncher implements PwaExternalLauncher {
  final opened = <String>[];

  @override
  void open(String url) => opened.add(url);
}

Widget _app(Widget child, {required List<Override> overrides, String locale = 'en'}) =>
    ProviderScope(
      overrides: [
        localeProvider.overrideWith((ref) => LocaleNotifier(deviceLocale: locale)),
        ...overrides,
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('km'), Locale('fr')],
        home: Scaffold(body: child),
      ),
    );

const _pack = PwaProduct(
  sku: 'pack_10',
  type: 'CREDIT_PACK',
  credits: 10,
  priceUsd: 1.99,
  currency: 'USD',
  storeOnly: false,
  webEnabled: true,
);

/// Tear the tree down between cases.
///
/// Two things depend on it, and both bit during authoring. Replacing one
/// `ProviderScope` with another does NOT reliably re-read an override — the
/// second iteration kept rendering the first one's state — and the scope is
/// what cancels the controller's poll timer, so a test that ends with a live
/// tree ends with a pending timer.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  // ══ the model ═══════════════════════════════════════════════════════════

  group('PAYWAY01-04  the model is a parse, never an inference', () {
    test('PAYWAY01 every server state maps to exactly one client state', () {
      const mapping = {
        'CREATED': PwaPaymentState.created,
        'AWAITING_PAYMENT': PwaPaymentState.awaitingPayment,
        'PAID_PENDING_VERIFICATION': PwaPaymentState.paidPendingVerification,
        'VERIFIED': PwaPaymentState.verified,
        'GRANTED': PwaPaymentState.granted,
        'FAILED': PwaPaymentState.failed,
        'EXPIRED': PwaPaymentState.expired,
        'CANCELLED': PwaPaymentState.cancelled,
      };
      for (final entry in mapping.entries) {
        expect(PwaPayment.parse(_server(state: entry.key)).state, entry.value,
            reason: entry.key);
      }
      // An unknown state is neither success nor failure. Treating it as "still
      // going" keeps the person on a screen that polls, and the SERVER remains
      // the only thing that can end it.
      final unknown = PwaPayment.parse(_server(state: 'SOMETHING_NEW'));
      expect(unknown.state, PwaPaymentState.created);
      expect(unknown.isPolling, isTrue);
      expect(unknown.isTerminal, isFalse);
    });

    test('PAYWAY02 only GRANTED is terminal-and-successful', () {
      const successful = PwaPaymentState.granted;
      for (final state in PwaPaymentState.values) {
        final p = PwaPayment(state: state);
        if (state == successful) {
          expect(p.isTerminal, isTrue);
          expect(p.isPolling, isFalse);
        } else {
          expect(p.state == PwaPaymentState.granted, isFalse);
        }
      }
    });

    test('PAYWAY03 polling stops on every terminal state', () {
      for (final state in ['GRANTED', 'FAILED', 'EXPIRED', 'CANCELLED']) {
        expect(PwaPayment.parse(_server(state: state)).isPolling, isFalse,
            reason: state);
      }
      for (final state in ['CREATED', 'AWAITING_PAYMENT',
        'PAID_PENDING_VERIFICATION', 'VERIFIED']) {
        expect(PwaPayment.parse(_server(state: state)).isPolling, isTrue,
            reason: state);
      }
    });

    test('PAYWAY04 a failure body is parsed into a state, not an exception', () {
      final closed = PwaPayment.parse(const {
        'ok': false,
        'error_code': 'PAYMENTS_UNAVAILABLE',
        'reason': 'PayWayNotConfigured',
      });
      expect(closed.state, PwaPaymentState.unavailable);

      final offline = PwaPayment.parse(const {
        'ok': false, 'error_code': 'UNREACHABLE', 'retryable': true,
      });
      expect(offline.state, PwaPaymentState.unreachable);
      expect(offline.canRetry, isTrue);

      final duplicate = PwaPayment.parse(const {
        'ok': false,
        'error_code': 'PAYMENT_PROVIDER_REFUSED',
        'reason': 'DUPLICATE_TRAN_ID',
        'new_attempt_required': true,
      });
      expect(duplicate.state, PwaPaymentState.failed);
      expect(duplicate.newAttemptRequired, isTrue);

      expect(PwaPayment.parse(const {'ok': true, 'open': false}).state,
          PwaPaymentState.idle);
    });
  });

  // ══ the controller ══════════════════════════════════════════════════════

  group('PAYWAY05-10  the controller never concludes anything', () {
    test('PAYWAY05 the browser sends a sku and an attempt key — and nothing '
        'else', () async {
      final server = _FakeServer();
      final controller = PwaPaymentController(server.gateway, null);
      await controller.start('pack_10');

      expect(server.calls.length, 1);
      expect(server.calls.single, startsWith('checkout:pack_10:'));
      // A UUID, minted here, carrying no price and no entitlement.
      final attempt = server.calls.single.split(':').last;
      expect(attempt.length, greaterThan(20));
      expect(controller.attemptKey, attempt);
      controller.dispose();
    });

    test('PAYWAY06 a retry reuses the attempt; starting over does not',
        () async {
      final server = _FakeServer();
      final controller = PwaPaymentController(server.gateway, null);
      await controller.start('pack_10');
      final first = controller.attemptKey;

      await controller.retry('pack_10');
      expect(controller.attemptKey, first,
          reason: 'the same attempt converges on the same PayWay transaction');

      await controller.start('pack_10');
      expect(controller.attemptKey, isNot(first),
          reason: 'a deliberate restart is a NEW transaction');
      controller.dispose();
    });

    test('PAYWAY07 a transaction PayWay has already seen forces a NEW attempt',
        () async {
      final server = _FakeServer(checkoutAnswer: const {
        'ok': false,
        'error_code': 'PAYMENT_PROVIDER_REFUSED',
        'reason': 'DUPLICATE_TRAN_ID',
        'new_attempt_required': true,
      });
      final controller = PwaPaymentController(server.gateway, null);
      await controller.start('pack_10');
      final first = controller.attemptKey;

      await controller.retry('pack_10');
      expect(controller.attemptKey, isNot(first),
          reason: 'retrying a spent transaction id can only ever earn a 403');
      controller.dispose();
    });

    testWidgets('PAYWAY08 the poll follows the SERVER to GRANTED, and the '
        'entitlement is re-read exactly once', (tester) async {
      final server = _FakeServer(pollAnswers: [
        _server(state: 'AWAITING_PAYMENT'),
        _server(state: 'PAID_PENDING_VERIFICATION'),
        _server(state: 'VERIFIED'),
        _server(state: 'GRANTED'),
      ]);
      final entitlement = _CountingEntitlement();
      final controller =
          PwaPaymentController(server.gateway, entitlement.refresh);

      final seen = <PwaPaymentState>[];
      controller.addListener((p) => seen.add(p.state));

      await controller.start('pack_10');
      // Four scheduled polls at 1 s each, plus slack. `pump` drives the timer;
      // nothing here advances the payment by itself.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
      }

      expect(seen, contains(PwaPaymentState.paidPendingVerification));
      expect(seen, contains(PwaPaymentState.verified));
      expect(controller.state.state, PwaPaymentState.granted);
      expect(entitlement.refreshes, 1,
          reason: 'exactly one re-read, on the transition into GRANTED');

      // And it STOPS: a settled payment is never asked about again.
      final callsAtRest = server.calls.length;
      await tester.pump(const Duration(seconds: 5));
      expect(server.calls.length, callsAtRest);
      controller.dispose();
    });

    testWidgets('PAYWAY09 a dropped connection does not erase a live QR',
        (tester) async {
      final server = _FakeServer(pollAnswers: [
        const {'ok': false, 'error_code': 'UNREACHABLE', 'retryable': true},
        _server(state: 'GRANTED'),
      ]);
      final controller = PwaPaymentController(server.gateway, null);
      await controller.start('pack_10');
      expect(controller.state.isPayable, isTrue);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(controller.state.isPayable, isTrue,
          reason: 'the person is still looking at a valid code');
      expect(controller.state.state, PwaPaymentState.awaitingPayment);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(controller.state.state, PwaPaymentState.granted,
          reason: 'the next tick corrects it');
      controller.dispose();
    });

    test('PAYWAY10 cancelling goes through the server, and money in flight '
        'wins', () async {
      // The person taps Cancel at the exact moment the payment lands. The
      // server verifies before it accepts, so the answer is GRANTED.
      final server = _FakeServer(cancelAnswer: _server(state: 'GRANTED'));
      final entitlement = _CountingEntitlement();
      final controller =
          PwaPaymentController(server.gateway, entitlement.refresh);
      await controller.start('pack_10');
      await controller.cancel();

      expect(server.calls, contains('cancel:A0123456789abcdef012'));
      expect(controller.state.state, PwaPaymentState.granted,
          reason: 'a tap must never throw away a payment that arrived');
      expect(entitlement.refreshes, 1);
      controller.dispose();
    });

    test('PAYWAY11 an in-progress payment is restored from the SERVER, not '
        'from browser storage', () async {
      final server = _FakeServer(
        openAnswer: {'ok': true, 'open': true, ..._server(state: 'AWAITING_PAYMENT')},
      );
      final controller = PwaPaymentController(server.gateway, null);
      await controller.restore();

      expect(server.calls, ['open']);
      expect(controller.state.state, PwaPaymentState.awaitingPayment);
      expect(controller.state.checkoutUrl, isNotEmpty,
          reason: 'F5 gets the SAME checkout back, without a second PayWay call');
      expect(controller.state.isPayable, isTrue,
          reason: 'and it is still usable — the link had not aged out');
      controller.dispose();
    });

    test('PAYWAY12 nothing to restore leaves the surface idle', () async {
      final server = _FakeServer();
      final controller = PwaPaymentController(server.gateway, null);
      await controller.restore();
      expect(controller.state.state, PwaPaymentState.idle);
      controller.dispose();
    });
  });

  // ══ the surface ═════════════════════════════════════════════════════════

  group('PAYWAY13-16  the surface', () {
    testWidgets('PAYWAY13 both devices get ONE handoff to ABA, and no QR of '
        'our own', (tester) async {
      for (final size in [const Size(1400, 1000), const Size(390, 844)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await _teardown(tester);
        final server = _FakeServer();
        final controller = PwaPaymentController(server.gateway, null);
        await controller.start('pack_10');

        await tester.pumpWidget(_app(
          const PwaPaymentSheet(product: _pack),
          overrides: [pwaPaymentProvider.overrideWith((ref) => controller)],
        ));
        await tester.pump();

        final l = pwaL10nFor(const Locale('en'));
        expect(find.widgetWithText(FilledButton, l.payContinueToAba),
            findsOneWidget,
            reason: "the checkout is ABA's, and this is the way to it");
        // ABA draws the QR on ABA's page. Drawing our own was the old rail.
        expect(find.byType(Image), findsNothing,
            reason: "Ayden must not reproduce ABA's payment screen");
      }
      await _teardown(tester);
    });

    testWidgets('PAYWAY14 tapping Continue to ABA NAVIGATES and concludes '
        'nothing', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final server = _FakeServer();
      final controller = PwaPaymentController(server.gateway, null);
      final launcher = _RecordingLauncher();
      final entitlement = _CountingEntitlement();
      await controller.start('pack_10');

      await tester.pumpWidget(_app(
        const PwaPaymentSheet(product: _pack),
        overrides: [
          pwaPaymentProvider.overrideWith((ref) => controller),
          pwaExternalLauncherProvider.overrideWithValue(launcher),
          pwaEntitlementProvider.overrideWith((ref) => entitlement),
        ],
      ));
      await tester.pump();

      final l = pwaL10nFor(const Locale('en'));
      await tester.tap(find.widgetWithText(FilledButton, l.payContinueToAba));
      await tester.pump();

      expect(launcher.opened, [
        'https://checkout-sandbox.payway.com.kh/eyJzdGVwIjoicGF5bWVudCJ9',
      ]);
      expect(controller.state.state, PwaPaymentState.awaitingPayment,
          reason: "opening ABA's checkout is not evidence of payment");
      expect(entitlement.refreshes, 0);
      expect(find.text(l.payDoneTitle), findsNothing);
      await _teardown(tester);
    });

    testWidgets('PAYWAY15 every payment state renders its own copy, in km, en '
        'and fr', (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cases = <String, String Function(PwaL10n)>{
        'AWAITING_PAYMENT': (l) => l.payContinueToAba,
        'PAID_PENDING_VERIFICATION': (l) => l.payConfirmingTitle,
        'VERIFIED': (l) => l.payActivatingTitle,
        'GRANTED': (l) => l.payDoneTitle,
        'EXPIRED': (l) => l.payExpiredTitle,
        'CANCELLED': (l) => l.payCancelledTitle,
        'FAILED': (l) => l.payFailedTitle,
      };

      for (final code in ['km', 'en', 'fr']) {
        for (final entry in cases.entries) {
          await _teardown(tester);
          final server = _FakeServer(
              checkoutAnswer: _server(state: entry.key));
          final controller = PwaPaymentController(server.gateway, null);
          await controller.start('pack_10');

          await tester.pumpWidget(_app(
            const PwaPaymentSheet(product: _pack),
            overrides: [pwaPaymentProvider.overrideWith((ref) => controller)],
            locale: code,
          ));
          await tester.pump();

          final l = pwaL10nFor(Locale(code));
          expect(find.text(entry.value(l)), findsOneWidget,
              reason: '$code / ${entry.key}');
          // Never the machine code, in any locale.
          expect(find.textContaining('AMOUNT_MISMATCH'), findsNothing);
          expect(find.textContaining('_'), findsNothing,
              reason: '$code / ${entry.key} — no raw code leaked into copy');
        }
      }
      await _teardown(tester);
    });

    testWidgets('PAYWAY16 the paywall offers Buy only when the SERVER says a '
        'rail is open', (tester) async {
      for (final configured in [false, true]) {
        await _teardown(tester);
        final controller = PwaEntitlementController(() async => {
              'can_generate': false,
              'billing_state': 'FREE_EXHAUSTED',
              'payment': {
                'provider': configured ? 'khqr' : 'none',
                'configured': configured,
              },
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
        await controller.refresh();

        await tester.pumpWidget(_app(
          const PwaPaywallSheet(),
          overrides: [pwaEntitlementProvider.overrideWith((ref) => controller)],
        ));
        await tester.pumpAndSettle();

        final l = pwaL10nFor(const Locale('en'));
        expect(find.widgetWithText(FilledButton, l.payBuy),
            configured ? findsOneWidget : findsNothing,
            reason: 'configured=$configured — exactly one buyable row, and no '
                'button at all when no rail is open');
        expect(find.text(l.paywallUnavailableTitle),
            configured ? findsNothing : findsOneWidget);
        // The store-only pass is never buyable here, whatever the rail says.
        expect(find.text(l.paywallStoreOnly), findsOneWidget);
      }
      await _teardown(tester);
    });

    test('PAYWAY17 every locale carries the whole payment vocabulary', () {
      const required = [
        'pwaPayBuy', 'pwaPayTitle', 'pwaPayPreparing', 'pwaPayScanTitle',
        'pwaPayScanBody', 'pwaPayOpenAba', 'pwaPayOrScan', 'pwaPayExpiresIn',
        'pwaPayWaiting', 'pwaPayConfirmingTitle', 'pwaPayConfirmingBody',
        'pwaPayActivatingTitle', 'pwaPayActivatingBody', 'pwaPayDoneTitle',
        'pwaPayDoneBody', 'pwaPayContinue', 'pwaPayExpiredTitle',
        'pwaPayExpiredBody', 'pwaPayCancelledTitle', 'pwaPayCancelledBody',
        'pwaPayFailedTitle', 'pwaPayFailedBody', 'pwaPayFailedDeclined',
        'pwaPayFailedAmount', 'pwaPayFailedProvider', 'pwaPayFailedNewAttempt',
        'pwaPayUnreachableTitle', 'pwaPayUnreachableBody', 'pwaPayRetry',
        'pwaPayCancel', 'pwaPaySafeNote',
      ];
      for (final (name, dict) in [
        ('en', pwaEnTranslations),
        ('km', pwaKmTranslations),
        ('fr', pwaFrTranslations),
      ]) {
        for (final key in required) {
          expect(dict.containsKey(key), isTrue, reason: '$name missing $key');
          expect(dict[key]!.trim(), isNotEmpty, reason: '$name empty $key');
        }
      }
      // Khmer must be Khmer, not English left in place. Every Khmer payment
      // string has to contain Khmer script somewhere — the brand names
      // (KHQR, ABA Mobile, Ayden, Spaces) are deliberately kept in Latin.
      final khmer = RegExp(r'[ក-៿]');
      for (final key in required) {
        expect(khmer.hasMatch(pwaKmTranslations[key]!), isTrue,
            reason: 'km/$key is not translated');
      }
    });

    test('PAYWAY18 a machine failure code always becomes a sentence', () {
      for (final code in ['en', 'km', 'fr']) {
        final l = pwaL10nFor(Locale(code));
        for (final reason in [
          'DECLINED', 'AMOUNT_MISMATCH', 'CURRENCY_MISMATCH', 'AMOUNT_MISSING',
          'QR_REFUSED', 'PRODUCT_UNMAPPED', 'EXPIRED', '', 'SOMETHING_NEW',
        ]) {
          final sentence = l.payFailedBody(reason);
          expect(sentence, isNotEmpty, reason: '$code/$reason');
          expect(sentence.contains(reason.isEmpty ? '__never__' : reason),
              isFalse,
              reason: '$code/$reason — the code leaked into the copy');
        }
        expect(l.payFailedBody('ANYTHING', newAttemptRequired: true),
            pwaEnTranslations['pwaPayFailedNewAttempt'] == null
                ? isNotEmpty
                : isNotEmpty);
      }
    });
  });

  test('PAYWAY19 the QR is decoded from what the gateway certified', () {
    // The image is PayWay's own artwork, decoded rather than redrawn: it
    // carries the KHQR branding a Cambodian payer looks for, and generating our
    // own would mean shipping an encoder to redraw a payload we did not author.
    final bytes = base64Decode(_pngBase64);
    expect(bytes, isA<Uint8List>());
    expect(bytes.length, greaterThan(8));
    expect(bytes.sublist(1, 4), equals('PNG'.codeUnits));
  });

  group('PAYWAY20-24  the checkout belongs to ABA', () {
    test('PAYWAY20 a stale checkout link is not payable, and not failed', () {
      final fresh = PwaPayment.parse(_server(state: 'AWAITING_PAYMENT'));
      expect(fresh.isPayable, isTrue);
      expect(fresh.needsFreshCheckout, isFalse);

      // PayWay's checkout token lives 180 seconds; the transaction behind it
      // lives thirty minutes. When the LINK dies the PAYMENT has not.
      final stale =
          PwaPayment.parse(_server(state: 'AWAITING_PAYMENT', checkoutStale: true));
      expect(stale.state, PwaPaymentState.awaitingPayment,
          reason: 'the payment is still open');
      expect(stale.isTerminal, isFalse, reason: 'nothing failed');
      expect(stale.isPayable, isFalse,
          reason: 'but this link would land on a PayWay error page');
      expect(stale.needsFreshCheckout, isTrue);
    });

    test('PAYWAY21 an answer with no checkout url is never payable', () {
      final none =
          PwaPayment.parse(_server(state: 'AWAITING_PAYMENT', checkoutUrl: ''));
      expect(none.isPayable, isFalse);
      expect(none.needsFreshCheckout, isTrue);
    });

    testWidgets('PAYWAY22 a stale link offers a way forward, not an error',
        (tester) async {
      final server = _FakeServer(
          checkoutAnswer:
              _server(state: 'AWAITING_PAYMENT', checkoutStale: true));
      final controller = PwaPaymentController(server.gateway, null);
      await controller.start('pack_10');

      await tester.pumpWidget(_app(
        const PwaPaymentSheet(product: _pack),
        overrides: [pwaPaymentProvider.overrideWith((ref) => controller)],
      ));
      await tester.pump();

      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.payLinkExpiredTitle), findsOneWidget);
      expect(find.widgetWithText(FilledButton, l.payContinueToAba), findsNothing,
          reason: 'offering a dead link is worse than offering none');
      // It must NOT be dressed as a failure — nothing went wrong.
      expect(find.text(l.payFailedTitle), findsNothing);
      await _teardown(tester);
    });

    testWidgets('PAYWAY23 a paid sheet offers the WORK, never the packs again',
        (tester) async {
      final server =
          _FakeServer(checkoutAnswer: _server(state: 'GRANTED'));
      final controller = PwaPaymentController(server.gateway, null);
      await controller.start('pack_10');

      await tester.pumpWidget(_app(
        const PwaPaymentSheet(product: _pack),
        overrides: [pwaPaymentProvider.overrideWith((ref) => controller)],
      ));
      await tester.pump();

      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.payDoneTitle), findsOneWidget);
      expect(find.widgetWithText(FilledButton, l.payStartDesigning),
          findsOneWidget,
          reason: 'what someone wants after paying is to use what they bought');
      expect(find.widgetWithText(TextButton, l.payMaybeLater), findsOneWidget);
      // The single most common way a good purchase flow ends badly.
      expect(find.text(l.payContinueToAba), findsNothing);
      await _teardown(tester);
    });

    test('PAYWAY24 every new payment string exists in km, en and fr', () {
      for (final code in ['km', 'en', 'fr']) {
        final l = pwaL10nFor(Locale(code));
        for (final value in [
          l.payContinueToAba,
          l.payHandoffBodyDesktop,
          l.payHandoffBodyPhone,
          l.payLinkExpiredTitle,
          l.payLinkExpiredBody,
          l.payStartDesigning,
          l.payMaybeLater,
        ]) {
          expect(value, isNotEmpty, reason: code);
          // A missing key falls back to the key itself — which always starts
          // 'pwaPay'. That is the shape of an untranslated string.
          expect(value.startsWith('pwaPay'), isFalse,
              reason: '$code: "$value" is a key, not a translation');
        }
      }
    });
  });
}
