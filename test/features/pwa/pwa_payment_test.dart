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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/core/providers/locale_provider.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement_controller.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_payment.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_payment_controller.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_aba_plugin.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_external_launcher.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_translations.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_payment_result.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_payment_sheet.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_aba_marks.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_nav_shell.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_paywall.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_site_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

  /// Kept SEPARATE from [opened] on purpose. The two methods have opposite
  /// consequences for the running app — one replaces this document, the other
  /// leaves it running — so a test that asserted only "a URL was launched"
  /// could not tell the regression apart from the fix.
  final newTabs = <String>[];

  @override
  void open(String url) => opened.add(url);

  @override
  void openNewTab(String url) => newTabs.add(url);
}


/// Records what the controller hands to ABA's plugin. Says nothing back about
/// the payment — a real plugin cannot either.
class _RecordingAbaPlugin implements PwaAbaPlugin {
  _RecordingAbaPlugin({this.supported = true});

  final bool supported;
  final launches = <({String action, Map<String, String> fields})>[];

  @override
  bool get isSupported => supported;

  @override
  PwaAbaPluginLaunch launch({
    required String formAction,
    required Map<String, String> fields,
  }) {
    launches.add((action: formAction, fields: fields));
    return PwaAbaPluginLaunch.launched;
  }
}

/// The server's answer on the plugin path: an AWAITING row in plugin mode
/// plus the signed handoff. No QR, no deeplink — those are ABA's, in the popup.
Map<String, Object?> _pluginServer({
  bool withHandoff = true,
  String state = 'AWAITING_PAYMENT',
}) {
  final base = _server(state: state)
    ..['checkout_mode'] = 'plugin'
    ..['checkout_url'] = '';
  if (withHandoff) {
    base['plugin'] = {
      'form_action': 'https://gateway.example/api/purchase',
      'fields': {
        'hash': 'SIGNATURE==',
        'tran_id': 'A0123456789abcdef012',
        'amount': '4.99',
        'req_time': '20260905170000',
        'payment_option': 'abapay_khqr',
        'currency': 'USD',
        // ABA merchant review (2026-09-08): ABA's own Success page is skipped;
        // the server signs the flag and the browser relays it untouched.
        'skip_success_page': '1',
      },
    };
  }
  return base;
}

Widget _app(Widget child, {required List<Override> overrides, String locale = 'en'}) =>
    ProviderScope(
      overrides: [
        localeProvider.overrideWith((ref) => LocaleNotifier(deviceLocale: locale)),
        // The marks are drawn from the checked-in files, so what these tests
        // render is the artwork ABA supplied — not a stub, not a network call.
        pwaMarkLoaderProvider.overrideWithValue(
            (asset) => SvgFileLoader(File('web/$asset'))),
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
    testWidgets('PAYWAY13 a rail with no QR still has ONE way forward, on '
        'both devices', (tester) async {
      // The `abapay_khqr` shape returns a checkout URL and nothing else, so
      // there is no QR to show and no deeplink to offer. That is not a dead end
      // and it is not an excuse to draw a QR: the way forward is ABA's own
      // page, in a NEW tab, so the Wallet and its poll survive.
      //
      // (The shipped rail is `abapay_khqr_deeplink`, which does return a
      // payload — ABA01/ABA02 cover that one.)
      for (final size in [const Size(1400, 1000), const Size(390, 844)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await _teardown(tester);
        final server = _FakeServer();   // no qr, no deeplink
        final controller = PwaPaymentController(server.gateway, null);
        await controller.start('pack_10');

        await tester.pumpWidget(_app(
          const PwaPaymentSheet(product: _pack),
          overrides: [pwaPaymentProvider.overrideWith((ref) => controller)],
        ));
        await tester.pump();

        expect(find.byKey(const ValueKey('pwa-pay-open-checkout')),
            findsOneWidget,
            reason: "the checkout is ABA's, and this is the way to it");
        // No QR is invented to fill the gap.
        final images = tester.widgetList<Image>(find.byType(Image));
        expect(images.any((i) => i.image is MemoryImage), isFalse,
            reason: 'with no payload there is nothing to render');
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

      await tester.tap(find.byKey(const ValueKey('pwa-pay-open-checkout')));
      await tester.pump();

      // A NEW TAB, and specifically not `open`. `open` assigns
      // `location.href`, which unloads the Flutter app — taking the Wallet, the
      // attempt and the poll waiting on it with it, so a returning payer lands
      // on a cold boot. That was the behaviour here until 2026-09-04, and this
      // is the assertion that keeps it from coming back.
      expect(launcher.newTabs, [
        'https://checkout-sandbox.payway.com.kh/eyJzdGVwIjoicGF5bWVudCJ9',
      ]);
      expect(launcher.opened, isEmpty,
          reason: 'same-tab navigation would destroy the app mid-payment');
      expect(controller.state.state, PwaPaymentState.awaitingPayment,
          reason: "opening ABA's checkout is not evidence of payment");
      expect(entitlement.refreshes, 0);
      expect(find.text(pwaL10nFor(const Locale('en')).payResultSuccessTitle),
          findsNothing);
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
        'GRANTED': (l) => l.payResultSuccessTitle,
        'EXPIRED': (l) => l.payResultFailedTitle,
        'CANCELLED': (l) => l.payResultFailedTitle,
        'FAILED': (l) => l.payResultFailedTitle,
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
        // Phase 9 changed the SHAPE of this answer, not its rule. There is one
        // CTA for the selected pack instead of a Buy button per row, and it is
        // disabled rather than absent when no rail is open — a person who
        // cannot pay should see what is on offer and be told why, not find the
        // control missing.
        final cta = tester.widget<PwaGoldCta>(
            find.byKey(const ValueKey('pwa-paywall-continue')));
        expect(cta.onPressed, configured ? isNotNull : isNull,
            reason: 'configured=$configured — the SERVER decides whether a '
                'purchase can complete');
        expect(find.text(l.paywallUnavailableTitle),
            configured ? findsNothing : findsOneWidget);
        // The store-only pass is not merchandise here at all any more: it is
        // absent from the purchase surface rather than listed with an excuse.
        expect(find.text(l.paywallStoreOnly), findsNothing);
        expect(find.byKey(const ValueKey('pwa-pack-weekly_pass')), findsNothing);
        expect(find.byKey(const ValueKey('pwa-pack-pack_10')), findsOneWidget);
      }
      await _teardown(tester);
    });

    test('PAYWAY17 every locale carries the whole payment vocabulary', () {
      const required = [
        'pwaPayBuy', 'pwaPayPreparing', 'pwaPayScanTitle',
        'pwaPayScanBody', 'pwaPayOpenAba', 'pwaPayOrScan', 'pwaPayExpiresIn',
        'pwaPayWaiting', 'pwaPayConfirmingTitle', 'pwaPayConfirmingBody',
        'pwaPayActivatingTitle', 'pwaPayActivatingBody',
        'pwaPayResultSuccessTitle', 'pwaPayResultSuccessBody',
        'pwaPayResultSummaryTitle', 'pwaPayResultNewBalance',
        'pwaPayResultContinue', 'pwaPayResultFailedTitle',
        'pwaPayResultFailedBody', 'pwaPayResultFailedHint',
        'pwaPayContinue', 'pwaPayExpiredTitle',
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

    testWidgets('PAYWAY23 a paid sheet is the result card: one verdict, one '
        'action, never the packs again', (tester) async {
      final server =
          _FakeServer(checkoutAnswer: _server(state: 'GRANTED'));
      final controller = PwaPaymentController(server.gateway, null);
      await controller.start('pack_10');

      await tester.pumpWidget(_app(
        const PwaPaymentSheet(product: _pack),
        overrides: [
          pwaPaymentProvider.overrideWith((ref) => controller),
          pwaEntitlementProvider.overrideWith((ref) => _CountingEntitlement()),
        ],
      ));
      await tester.pump();

      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.payResultSuccessTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-pay-result-continue')),
          findsOneWidget, reason: 'Continue is the one action');
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(TextButton), findsNothing,
          reason: 'no "maybe later", no second choice');
      // The single most common way a good purchase flow ends badly.
      expect(find.text(l.payContinueToAba), findsNothing);
      await _teardown(tester);
    });

    test('PAYWAY24 every new payment string exists in km, en and fr', () {
      for (final code in ['km', 'en', 'fr']) {
        final l = pwaL10nFor(Locale(code));
        for (final value in [
          l.payContinueToAba,
          l.payLinkExpiredTitle,
          l.payLinkExpiredBody,
          l.payResultSuccessTitle,
          l.payResultFailedHint,
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

  group('CAT01-05  the catalogue is the price authority, the discount is not', () {
    PwaProduct parse(Map<String, Object?> raw) => PwaProduct.parse(raw)!;

    Map<String, Object?> row({
      required String sku,
      required int credits,
      required double price,
      double? listPrice,
      String badge = '',
    }) => {
          'sku': sku,
          'type': 'CREDIT_PACK',
          'credits': credits,
          'price_usd': price,
          'currency': 'USD',
          'store_only': false,
          'web_enabled': true,
          'list_price_usd': listPrice,
          'badge': badge,
        };

    test('CAT01 the three packs parse at their canonical prices', () {
      final starter = parse(row(
          sku: 'pack_10', credits: 10, price: 4.99, badge: 'starter'));
      final popular = parse(row(
          sku: 'pack_30', credits: 30, price: 7.99, badge: 'popular'));
      final best = parse(row(
          sku: 'pack_300', credits: 300, price: 47.99,
          listPrice: 79.99, badge: 'best_value'));

      expect((starter.credits, starter.priceLabel), (10, r'$4.99'));
      expect((popular.credits, popular.priceLabel), (30, r'$7.99'));
      expect((best.credits, best.priceLabel), (300, r'$47.99'));
    });

    test('CAT02 the 300 pack shows 79.99 struck through and 40% off', () {
      final best = parse(row(
          sku: 'pack_300', credits: 300, price: 47.99,
          listPrice: 79.99, badge: 'best_value'));
      expect(best.isDiscounted, isTrue);
      expect(best.listPriceLabel, r'$79.99');
      expect(best.discountPercent, 40,
          reason: 'derived from the two prices, never stored beside them');
      // The payable label is the discounted one. This is the whole point.
      expect(best.priceLabel, r'$47.99');
    });

    test('CAT03 an undiscounted pack renders no reference price at all', () {
      final starter = parse(row(
          sku: 'pack_10', credits: 10, price: 4.99, badge: 'starter'));
      expect(starter.isDiscounted, isFalse);
      expect(starter.listPriceLabel, isEmpty);
      expect(starter.discountPercent, 0);
    });

    test('CAT04 a reference price that is not ABOVE the price is not a discount',
        () {
      for (final bad in [4.99, 3.00, 0.0]) {
        final p = parse(row(
            sku: 'pack_10', credits: 10, price: 4.99, listPrice: bad));
        expect(p.isDiscounted, isFalse, reason: 'list=$bad');
        expect(p.discountPercent, 0, reason: 'list=$bad — never a 0% badge');
      }
    });

    test('CAT05 badge codes translate in km/en/fr; unknown codes render empty',
        () {
      for (final code in ['km', 'en', 'fr']) {
        final l = pwaL10nFor(Locale(code));
        for (final badge in ['starter', 'popular', 'best_value']) {
          final label = l.productBadge(badge);
          expect(label, isNotEmpty, reason: '$code/$badge');
          expect(label, isNot(badge),
              reason: '$code/$badge — the raw code must never reach a customer');
          expect(label.startsWith('pwaProduct'), isFalse,
              reason: '$code/$badge is an untranslated key');
        }
        // A badge the server adds later must look ABSENT, not broken.
        expect(l.productBadge('flash_sale'), isEmpty);
        expect(l.productBadge(''), isEmpty);
        expect(l.paywallDiscount(40), contains('40'));
      }
    });

    test('CAT06 there is no unlimited concept to parse into', () {
      // `credits` is an int with no sentinel. A server that tried to express
      // "unlimited" as 0 or a missing value produces a pack that grants
      // nothing, not a pack that grants everything.
      final weird = parse({
        'sku': 'x', 'type': 'CREDIT_PACK', 'credits': null,
        'price_usd': 9.99, 'currency': 'USD',
        'store_only': false, 'web_enabled': true,
      });
      expect(weird.credits, 0);
      expect(weird.credits, isA<int>());
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ABA MERCHANT REVIEW (2026-09-04) — what the bank asked to see, and what we
  // refused to fabricate for it.
  // ══════════════════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════════════════
  // ABA MERCHANT REVIEW — the compact KHQR modal, and the acceptance mark that
  // lives in the navigation bar rather than in a strip of its own.
  // ══════════════════════════════════════════════════════════════════════════
  group('ABA merchant review', () {
    /// A payment sitting at AWAITING with the shape the deployed rail returns:
    /// the official KHQR payload, a server-rendered PNG of it, and ABA's own
    /// deeplink.
    PwaPaymentController awaiting() {
      final server = _FakeServer(
        checkoutAnswer: _server(state: 'AWAITING_PAYMENT', qr: 'KHQR-PAYLOAD',
            deeplink: 'abamobilebank://ababank.com?type=payway&qrcode=x'),
      );
      return PwaPaymentController(server.gateway, null);
    }

    testWidgets('ABA01 the payment modal is COMPACT, and shows ABA KHQR',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = awaiting();
      await controller.start('pack_10');
      await tester.pumpWidget(_app(
        const PwaPaymentSheet(product: _pack),
        overrides: [pwaPaymentProvider.overrideWith((ref) => controller)],
      ));
      await tester.pump();

      // The method names itself, and the way out is always reachable.
      expect(find.text('ABA KHQR'), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-pay-close')), findsOneWidget);

      // ABA's own deeplink, offered as ABA returned it.
      expect(find.byKey(const ValueKey('pwa-pay-open-aba-mobile')),
          findsOneWidget);

      // AND NOT the rejected treatment: no embedded hosted page, and no
      // paragraph of Ayden instructions duplicating what ABA's QR already says
      // — the handoff paragraphs are retired; one instruction line remains,
      // and it names no provider.
      final l = pwaL10nFor(const Locale('en'));
      expect(find.textContaining('own page'), findsNothing);
      expect(find.text(l.payScanBody), findsOneWidget);
      expect(l.payScanBody.contains('ABA'), isFalse);
      await _teardown(tester);
    });

    testWidgets('ABA09 / ABA-REVIEW-08 the SUCCESS card carries no ABA KHQR '
        'header', (tester) async {
      // ABA merchant review (2026-09-08): "Please remove ABA KHQR on your
      // success screen header." Once the payment has an outcome the card is
      // Ayden's, about Ayden's account.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final server = _FakeServer(checkoutAnswer: _server(state: 'GRANTED'));
      final controller = PwaPaymentController(server.gateway, null);
      await controller.start('pack_10');
      await tester.pumpWidget(_app(
        const PwaPaymentSheet(product: _pack),
        overrides: [pwaPaymentProvider.overrideWith((ref) => controller)],
      ));
      await tester.pump();

      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.payResultSuccessTitle), findsOneWidget,
          reason: 'this IS the success card');
      expect(find.text('ABA KHQR'), findsNothing,
          reason: 'no payment-method name on the result card');
      expect(find.byKey(const ValueKey('pwa-aba-method-mark')), findsNothing,
          reason: 'no ABA tile on the result card');
      expect(find.byKey(const ValueKey('pwa-pay-close')), findsNothing,
          reason: 'one card, one action: Continue is the way out');
      expect(find.byKey(const ValueKey('pwa-pay-result-continue')),
          findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('ABA10 while a person is PAYING the method is still named',
        (tester) async {
      // The header change is scoped to outcomes: during the payment the tile
      // and "ABA KHQR" remain, because that is what the person is paying with.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = awaiting();
      await controller.start('pack_10');
      await tester.pumpWidget(_app(
        const PwaPaymentSheet(product: _pack),
        overrides: [pwaPaymentProvider.overrideWith((ref) => controller)],
      ));
      await tester.pump();

      expect(find.text('ABA KHQR'), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-aba-method-mark')), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('ABA02 the QR shown is the SERVER-rendered image of ABA\'s '
        'payload', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = awaiting();
      await controller.start('pack_10');
      await tester.pumpWidget(_app(
        const PwaPaymentSheet(product: _pack),
        overrides: [pwaPaymentProvider.overrideWith((ref) => controller)],
      ));
      await tester.pump();

      // `Image.memory` — decoded from what the server sent, never encoded here.
      expect(find.byType(Image), findsWidgets);
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.any((i) => i.image is MemoryImage), isTrue,
          reason: 'the QR is a server-rendered PNG, not a client-drawn symbol');

      // And the client ships no QR ENCODER. The pixels must come from the
      // server, so a payload can never be turned into a symbol in the browser.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final pkg in ['qr_flutter', 'qr:', 'barcode', 'zxing', 'pretty_qr']) {
        expect(pubspec.contains(pkg), isFalse,
            reason: 'no client-side QR encoder may enter the bundle ($pkg)');
      }
      await _teardown(tester);
    });

    testWidgets('ABA03 no payment method other than ABA KHQR is ever named, '
        'in any locale', (tester) async {
      const forbidden = [
        'card', 'carte', 'កាត',
        'Visa', 'Mastercard', 'Alipay', 'WeChat', 'ABA Pay',
        'Apple Pay', 'Google Pay',
      ];
      const surfaces = [
        'pwaPayMethodTitle',
        'pwaPayMethodBody',
        'pwaPayScanTitle',
        'pwaPayScanBody',
        'pwaPayOrScan',
        'pwaAcceptWeAccept',
        'pwaPayInlineChecking',
        'pwaPayFailedNotCreated',
        'pwaPayPluginOpen',
        'pwaPayContinueToAba',
      ];
      for (final table in [
        pwaEnTranslations,
        pwaKmTranslations,
        pwaFrTranslations,
      ]) {
        for (final key in surfaces) {
          final value = table[key];
          if (value == null) continue;
          // Nothing to strip any more: Ayden's copy names no provider, so
          // "ABA Pay" can only appear if a method is actually being named.
          final hay = value.toLowerCase();
          for (final word in forbidden) {
            expect(hay.contains(word.toLowerCase()), isFalse,
                reason: '$key names "$word", which ABA no longer offers');
          }
        }
      }
    });

    test('ABA04 / ABA-REVIEW-13 Ayden writes no sentence about the provider: '
        'the note under Buy is gone and no dictionary value says PayWay', () {
      // ABA's second review round (2026-09-08): "Can you please remove all
      // those message please? There is no requirement UI related to ABA
      // Payway." The note under Buy is retired in every locale, with the
      // unused handoff copy that said the same thing; the provider's name
      // survives only where it IS the name on screen.
      const retired = [
        'pwaPaywallSecureNote',
        'pwaPayTitle',
        'pwaPayOpenInNewTab',
        'pwaPayHandoffBodyDesktop',
        'pwaPayHandoffBodyPhone',
        'pwaPayReturnTitle',
        'pwaPayReturnBody',
      ];
      for (final (name, table) in [
        ('en', pwaEnTranslations),
        ('km', pwaKmTranslations),
        ('fr', pwaFrTranslations),
      ]) {
        for (final key in retired) {
          expect(table.containsKey(key), isFalse,
              reason: '$name still carries $key');
        }
        for (final entry in table.entries) {
          expect(entry.value.contains('PayWay'), isFalse,
              reason: '$name:${entry.key} names the provider');
          // 'ABA' may appear only inside the payment method's own name or
          // the name of the bank app a deeplink opens — never in a
          // sentence of ours.
          final residue = entry.value
              .replaceAll('ABA KHQR', '')
              .replaceAll('ABA Mobile', '');
          expect(residue.contains('ABA'), isFalse,
              reason: '$name:${entry.key} talks about ABA: ${entry.value}');
        }
      }
      // The two lines ABA's reviewer still meets, word for word.
      final en = pwaL10nFor(const Locale('en'));
      expect(en.payInlineChecking, 'Checking your payment…');
      expect(en.payFailedBody('NOT_CREATED'),
          'Payment could not start. Please try again.');
      // And the getter behind the note is gone, so no widget can bring it
      // back without a dictionary change that this test would see.
      expect(
          File('lib/features/pwa/l10n/pwa_l10n.dart')
              .readAsStringSync()
              .contains('paywallSecureNote'),
          isFalse);
      expect(
          File('lib/features/pwa/presentation/pwa_paywall.dart')
              .readAsStringSync()
              .contains('SecureNote'),
          isFalse);
    });

    testWidgets('ABA05 every locale carries the payment vocabulary',
        (tester) async {
      const added = [
        'pwaAcceptWeAccept',
        'pwaPayMethodTitle',
        'pwaPayMethodBody',
        'pwaPayClose',
        'pwaPayOpenAba',
        'pwaPayScanBody',
      ];
      for (final table in [
        pwaEnTranslations,
        pwaKmTranslations,
        pwaFrTranslations,
      ]) {
        for (final key in added) {
          expect(table[key], isNotNull, reason: '$key is missing');
          expect(table[key]!.trim(), isNotEmpty);
        }
        expect(table.containsKey('pwaPayTitle'), isFalse,
            reason: 'retired with the provider copy (ABA04)');
      }
    });

    testWidgets('ABA06 the modal is a DIALOG over the Wallet, not a full sheet',
        (tester) async {
      // A source assertion, because what is being pinned is how the surface is
      // PRESENTED — and the previous implementation's defect was exactly that:
      // a 0.90-height bottom sheet reads as a separate screen, which is what
      // ABA rejected. `showDialog` centres a content-sized card instead.
      final src = File(
        'lib/features/pwa/presentation/pwa_payment_sheet.dart',
      ).readAsStringSync();

      expect(src.contains('showDialog<PwaPaymentExit>'), isTrue,
          reason: 'the payment surface must be a centred modal');
      expect(src.contains('showModalBottomSheet'), isFalse,
          reason: 'a near-full-height bottom sheet was the rejected treatment');
      expect(src.contains('maxWidth = 400'), isTrue,
          reason: 'the card is capped so the Wallet stays visible around it');

      // The hosted checkout is no longer embedded anywhere.
      expect(src.contains('createPwaAbaCheckoutFrame'), isFalse,
          reason: "ABA's desktop page has no compact layout and is not framed");
      expect(src.contains('HtmlElementView'), isFalse);
    });

    testWidgets('ABA07 closing the modal grants nothing', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = awaiting();
      final entitlement = _CountingEntitlement();
      await controller.start('pack_10');

      await tester.pumpWidget(_app(
        const PwaPaymentSheet(product: _pack),
        overrides: [
          pwaPaymentProvider.overrideWith((ref) => controller),
          pwaEntitlementProvider.overrideWith((ref) => entitlement),
        ],
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pwa-pay-close')));
      await tester.pump();

      expect(controller.state.state, PwaPaymentState.awaitingPayment,
          reason: 'closing a card is not a payment outcome');
      expect(entitlement.refreshes, 0);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.payResultSuccessTitle), findsNothing);
      await _teardown(tester);
    });

    testWidgets('ABA08 the ABA Mobile button opens ABA\'s OWN deeplink',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = awaiting();
      final launcher = _RecordingLauncher();
      await controller.start('pack_10');

      await tester.pumpWidget(_app(
        const PwaPaymentSheet(product: _pack),
        overrides: [
          pwaPaymentProvider.overrideWith((ref) => controller),
          pwaExternalLauncherProvider.overrideWithValue(launcher),
        ],
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pwa-pay-open-aba-mobile')));
      await tester.pump();

      // Verbatim, and never assembled in the client.
      expect(launcher.opened,
          ['abamobilebank://ababank.com?type=payway&qrcode=x']);
      final src = File(
        'lib/features/pwa/presentation/pwa_payment_sheet.dart',
      ).readAsStringSync();
      expect(src.contains('abamobilebank://'), isFalse,
          reason: 'the deeplink is PayWay\'s, never built here');
      expect(controller.state.state, PwaPaymentState.awaitingPayment,
          reason: 'opening a bank app is not evidence of payment');
      await _teardown(tester);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // THE ACCEPTANCE LOCKUP — ABA's OFFICIAL artwork, in the website FOOTER.
  // ABA's merchant review (2026-09-08) asked for it there; it no longer rides
  // the Profile label in the navigation bar.
  // ══════════════════════════════════════════════════════════════════════════
  group('acceptance mark', () {
    Widget navBar() => PwaBottomNav(
          current: PwaNavDestination.home,
          onSelect: (_) {},
        );

    testWidgets('NAV01 the bottom navigation carries NO acceptance mark',
        (tester) async {
      tester.view.physicalSize = const Size(390, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_app(navBar(), overrides: []));
      await tester.pump();

      expect(find.byKey(const ValueKey('pwa-accept-mark')), findsNothing,
          reason: 'the lockup moved to the website footer');
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.shared.navHome), findsOneWidget);
      expect(find.text(l.shared.navProjects), findsOneWidget);
      expect(find.text(l.shared.navProfile), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('NAV02 / ABA-REVIEW-03 the footer shows ABA\'s official '
        'lockup, byte for byte, with a localised caption', (tester) async {
      tester.view.physicalSize = const Size(390, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      for (final locale in ['en', 'km', 'fr']) {
        await tester.pumpWidget(
            _app(const PwaSiteFooter(), overrides: [], locale: locale));
        await tester.pump();

        expect(find.byKey(const ValueKey('pwa-site-footer')), findsOneWidget);
        // An SVG picture, never a raster stand-in.
        expect(
            tester.widget<SvgPicture>(
                find.byKey(const ValueKey('pwa-accept-mark'))),
            isNotNull);
        // The lockup has no words of its own, so the caption is REQUIRED —
        // and it is the dictionary's, in the page's language.
        final l = pwaL10nFor(Locale(locale));
        expect(find.text(l.acceptWeAccept), findsOneWidget);
        await _teardown(tester);
      }

      // The constants name the official files under web/aba/ …
      expect(kPwaAcceptMarkAsset, 'aba/abakhqr-we-accept.svg');
      expect(kPwaAbaMethodMarkAsset, 'aba/aba_khqr_payment_option.svg');
      // … and the served files ARE the files ABA sent, unchanged.
      expect(File('web/aba/abakhqr-we-accept.svg').readAsBytesSync(),
          File('docs/aba/official/abakhqr-we-accept.svg').readAsBytesSync(),
          reason: 'the We accept lockup must be ABA\'s file, byte for byte');
      expect(File('web/aba/aba_khqr_payment_option.svg').readAsBytesSync(),
          File('docs/aba/official/ABA BANK.svg').readAsBytesSync(),
          reason: 'the payment-option tile must be ABA\'s file, byte for byte');
    });

    testWidgets('NAV03 the footer is placed on each tab page, and the lockup '
        'nowhere else', (tester) async {
      String src(String path) => File(path).readAsStringSync();
      const dir = 'lib/features/pwa/presentation/';
      // One footer per page; Projects declares it in both of its branches
      // (empty library, grid) and only ever renders one.
      expect('PwaSiteFooter('.allMatches(src('${dir}pwa_home_ios.dart')).length,
          1);
      expect(
          'PwaSiteFooter('.allMatches(src('${dir}pwa_profile_ios.dart')).length,
          1);
      expect(
          'PwaSiteFooter('.allMatches(src('${dir}pwa_projects_ios.dart')).length,
          2);
      // Never in the Wallet, the payment card, the working screens, or the bar.
      for (final f in [
        'pwa_paywall.dart',
        'pwa_payment_sheet.dart',
        'pwa_architect_screen.dart',
        'pwa_reveal_screen.dart',
        'pwa_create_ios.dart',
        'pwa_nav_shell.dart',
      ]) {
        final text = src('$dir$f');
        expect(text.contains('PwaSiteFooter'), isFalse,
            reason: '$f must not host the website footer');
        expect(text.contains('PwaAcceptMark'), isFalse,
            reason: '$f must not place the lockup on its own');
      }
      // The lockup widget is defined in one file and placed by exactly one.
      final users = Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('PwaAcceptMark('))
          .map((f) => f.path.split(RegExp(r'[\\/]')).last)
          .toList()
        ..sort();
      expect(users, ['pwa_aba_marks.dart', 'pwa_site_footer.dart']);
    });

    testWidgets('NAV04 the bar does not overflow on a small phone',
        (tester) async {
      for (final size in [
        const Size(320, 200),
        const Size(390, 200),
        const Size(430, 200),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(_app(navBar(), overrides: []));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'no overflow at ${size.width.toInt()}px');
        await _teardown(tester);
      }
    });

    testWidgets('NAV06 the footer is metadata: small, captioned, and not a '
        'control', (tester) async {
      tester.view.physicalSize = const Size(390, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_app(const PwaSiteFooter(), overrides: []));
      await tester.pump();

      final mark = tester.getRect(find.byKey(const ValueKey('pwa-accept-mark')));
      final caption =
          tester.getRect(find.byKey(const ValueKey('pwa-site-footer-caption')));
      expect(mark.height, lessThanOrEqualTo(18.0),
          reason: 'a footer mark, not a banner');
      expect(mark.width, greaterThan(mark.height * 3),
          reason: 'the 72:20 lockup keeps its own proportions');
      expect(caption.right, lessThanOrEqualTo(mark.left),
          reason: 'the caption reads first, then the lockup');
      expect((caption.center.dy - mark.center.dy).abs(), lessThan(3.0),
          reason: 'one line');
      final footer = find.byKey(const ValueKey('pwa-site-footer'));
      expect(find.descendant(of: footer, matching: find.byType(InkWell)),
          findsNothing);
      expect(
          find.descendant(of: footer, matching: find.byType(GestureDetector)),
          findsNothing);
      await _teardown(tester);
    });

    testWidgets('NAV07 in production the marks are fetched same-origin from '
        'web/aba/, and a missing file draws nothing', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final loader =
          container.read(pwaMarkLoaderProvider)(kPwaAcceptMarkAsset);
      expect(loader, isA<PwaSvgUrlLoader>());
      expect((loader as PwaSvgUrlLoader).url, 'aba/abakhqr-we-accept.svg');
      // The trap this loader exists for: an error page handed to the SVG
      // parser fails a widget test asynchronously even with an errorBuilder.
      // Anything but a 200 becomes an empty picture instead.
      expect(loader.provideSvg(null), contains('viewBox="0 0 0 0"'));
    });

    testWidgets('NAV05 Profile is still tappable', (tester) async {
      tester.view.physicalSize = const Size(390, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final taps = <PwaNavDestination>[];
      await tester.pumpWidget(_app(
        PwaBottomNav(
          current: PwaNavDestination.home,
          onSelect: taps.add,
        ),
        overrides: [],
      ));
      await tester.pump();

      final l = pwaL10nFor(const Locale('en'));
      await tester.tap(find.text(l.shared.navProfile));
      await tester.pump();
      expect(taps, [PwaNavDestination.profile]);
      await _teardown(tester);
    });

    testWidgets('ABA-REVIEW-04 no generated ABA artwork is served or used',
        (tester) async {
      // The AI-generated PNG stand-ins of the first preprod review are gone
      // from the served folder and from every Dart file.
      final served = Directory('web/aba')
          .listSync()
          .whereType<File>()
          .map((f) => f.path.split(RegExp(r'[\\/]')).last)
          .toList()
        ..sort();
      expect(served, ['aba_khqr_payment_option.svg', 'abakhqr-we-accept.svg']);
      final dart = Directory('lib/features/pwa')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      for (final generated in [
        'we_accept_aba_khqr',
        'aba_khqr_logo',
        'aba/we_accept',
      ]) {
        expect(dart.contains(generated), isFalse,
            reason: 'the generated mark "$generated" must not be referenced');
      }
    });
  });


  // ══════════════════════════════════════════════════════════════════════════
  // THE RESULT CARD — Ayden's verdict after ABA's checkout (2026-09-08).
  // Near-black, one action, the server's figures. No provider branding.
  // ══════════════════════════════════════════════════════════════════════════
  group('payment result cards', () {
    Future<PwaPaymentController> settled(String state,
        {int credits = 10, double amount = 1.99}) async {
      final server = _FakeServer(
          checkoutAnswer:
              _server(state: state, credits: credits, amount: amount));
      final controller = PwaPaymentController(server.gateway, null);
      await controller.start('pack_10');
      return controller;
    }

    Future<void> pumpCard(
      WidgetTester tester,
      PwaPaymentController controller, {
      required PwaEntitlementController entitlement,
      String locale = 'en',
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_app(
        const PwaPaymentSheet(product: _pack),
        overrides: [
          pwaPaymentProvider.overrideWith((ref) => controller),
          pwaEntitlementProvider.overrideWith((ref) => entitlement),
        ],
        locale: locale,
      ));
      await tester.pump(); // the card
      await tester.pump(); // the entitlement re-read settles
    }

    PwaEntitlementController holding(int credits) =>
        PwaEntitlementController(() async => {
              'can_generate': true,
              'access_source': 'pass',
              'has_active_pass': true,
              'watermarked': false,
              'pass_credits': credits,
              'credits_available': credits,
            });

    String textOf(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data ?? '';

    for (final (credits, amount, price) in [
      (10, 4.99, r'$4.99'),
      (30, 7.99, r'$7.99'),
      (300, 47.99, r'$47.99'),
    ]) {
      testWidgets('RESULT01 pack of $credits: the success card carries the '
          'server\'s figures and one Continue', (tester) async {
        final controller =
            await settled('GRANTED', credits: credits, amount: amount);
        await pumpCard(tester, controller, entitlement: holding(credits));

        final l = pwaL10nFor(const Locale('en'));
        expect(find.byKey(const ValueKey('pwa-pay-result-success')),
            findsOneWidget);
        expect(l.payResultSuccessTitle, 'Payment successful');
        expect(find.text('Payment successful'), findsOneWidget);
        expect(find.text('$credits spaces added to your wallet'),
            findsOneWidget);
        expect(find.text('Purchase summary'), findsOneWidget);
        // The pack line and the amount are the server's echo of the ORDER.
        expect(textOf(tester, 'pwa-pay-result-pack'), '$credits spaces');
        expect(textOf(tester, 'pwa-pay-result-amount'), price);
        // The new balance is what the entitlement answered after the grant.
        expect(find.text('New balance'), findsOneWidget);
        expect(textOf(tester, 'pwa-pay-result-balance'), '$credits spaces');
        expect(find.byKey(const ValueKey('pwa-pay-result-continue')),
            findsOneWidget);
        expect(find.text('Continue'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    }

    for (final state in ['FAILED', 'CANCELLED', 'EXPIRED']) {
      testWidgets('RESULT02 $state renders the failure card: no credits, '
          'Try again', (tester) async {
        final controller = await settled(state);
        final entitlement = _CountingEntitlement();
        await pumpCard(tester, controller, entitlement: entitlement);

        final l = pwaL10nFor(const Locale('en'));
        expect(find.byKey(const ValueKey('pwa-pay-result-failure')),
            findsOneWidget);
        expect(l.payResultFailedTitle, 'Payment failed / cancelled');
        expect(find.text('Payment failed / cancelled'), findsOneWidget);
        expect(find.text('No credits were added'), findsOneWidget);
        expect(find.text(l.payResultFailedHint), findsOneWidget);
        expect(find.byKey(const ValueKey('pwa-pay-result-retry')),
            findsOneWidget);
        expect(find.text(l.payRetry), findsOneWidget);
        // Nothing that belongs to a success.
        expect(find.byKey(const ValueKey('pwa-pay-result-success')),
            findsNothing);
        expect(find.byKey(const ValueKey('pwa-pay-result-balance')),
            findsNothing);
        expect(entitlement.refreshes, 0,
            reason: 'a failed payment changed no balance; nothing to re-read');
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    }

    test('RESULT03 the retired result copy is gone from every locale and from '
        'the sheet', () {
      for (final dict in [
        pwaEnTranslations,
        pwaKmTranslations,
        pwaFrTranslations,
      ]) {
        for (final key in [
          'pwaPayDoneTitle',
          'pwaPayDoneBody',
          'pwaPayStartDesigning',
          'pwaPayMaybeLater',
        ]) {
          expect(dict.containsKey(key), isFalse, reason: '$key must be gone');
        }
      }
      expect(
          pwaEnTranslations.values.any((v) =>
              v.contains('You are all set') ||
              v.contains('Start a new design') ||
              v == 'Maybe later'),
          isFalse);
      final sheet = File(
        'lib/features/pwa/presentation/pwa_payment_sheet.dart',
      ).readAsStringSync();
      expect(sheet.contains('pwa-pay-balance'), isFalse,
          reason: 'no standalone balance pill');
      expect(sheet.contains('_BalanceAfterPurchase'), isFalse);
    });

    testWidgets('RESULT04 neither card carries payment-provider branding, '
        'and neither has a second control', (tester) async {
      for (final state in ['GRANTED', 'FAILED']) {
        final controller = await settled(state);
        await pumpCard(tester, controller, entitlement: _CountingEntitlement());
        expect(find.textContaining('ABA'), findsNothing, reason: state);
        expect(find.textContaining('PayWay'), findsNothing, reason: state);
        expect(find.textContaining('KHQR'), findsNothing, reason: state);
        expect(find.byKey(const ValueKey('pwa-aba-method-mark')), findsNothing);
        expect(find.byKey(const ValueKey('pwa-accept-mark')), findsNothing);
        expect(find.byKey(const ValueKey('pwa-pay-close')), findsNothing,
            reason: 'one card, one action');
        await _teardown(tester);
      }
    });

    testWidgets('RESULT05 the new balance is the refreshed entitlement, never '
        'the pack added to anything', (tester) async {
      // The server says the account now holds 25 — say a balance that was
      // already there plus this grant. The pack bought was 10. The card must
      // say 25, and must never have worked that out itself.
      final controller = await settled('GRANTED', credits: 10, amount: 4.99);
      await pumpCard(tester, controller, entitlement: holding(25));
      expect(textOf(tester, 'pwa-pay-result-balance'), '25 spaces');
      expect(textOf(tester, 'pwa-pay-result-pack'), '10 spaces');
      await _teardown(tester);
    });

    testWidgets('RESULT06 until the entitlement has been re-read the balance '
        'shows nothing, not the old number', (tester) async {
      final controller = await settled('GRANTED');
      final gate = Completer<Map<String, Object?>>();
      final entitlement = PwaEntitlementController(() => gate.future);
      await pumpCard(tester, controller, entitlement: entitlement);
      expect(textOf(tester, 'pwa-pay-result-balance'), '—',
          reason: 'no stale figure next to "New balance"');

      gate.complete({
        'can_generate': true,
        'access_source': 'pass',
        'has_active_pass': true,
        'pass_credits': 10,
        'credits_available': 10,
      });
      await tester.pump();
      await tester.pump();
      expect(textOf(tester, 'pwa-pay-result-balance'), '10 spaces');
      await _teardown(tester);
    });

    test('RESULT07 only terminal states are verdicts; the return watcher '
        'opens the card on those alone', () {
      expect(pwaPaymentResultKindFor(PwaPaymentState.granted),
          PwaPaymentResultKind.success);
      for (final s in [
        PwaPaymentState.failed,
        PwaPaymentState.cancelled,
        PwaPaymentState.expired,
      ]) {
        expect(pwaPaymentResultKindFor(s), PwaPaymentResultKind.failure);
      }
      for (final s in [
        PwaPaymentState.idle,
        PwaPaymentState.starting,
        PwaPaymentState.created,
        PwaPaymentState.awaitingPayment,
        PwaPaymentState.paidPendingVerification,
        PwaPaymentState.verified,
        PwaPaymentState.unreachable,
        PwaPaymentState.unavailable,
      ]) {
        expect(pwaPaymentResultKindFor(s), isNull,
            reason: '$s: PayWay may still legitimately say PENDING');
      }
      final watcher = File(
        'lib/features/pwa/presentation/pwa_experience.dart',
      ).readAsStringSync();
      expect(watcher.contains('pwaPaymentResultKindFor(next) == null'), isTrue,
          reason: 'the return watcher shows the card on verdicts only');
    });

    testWidgets('RESULT08 Continue closes the card as PAID and resets the '
        'attempt', (tester) async {
      final controller = await settled('GRANTED');
      PwaPaymentExit? exit;
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              exit = await showDialog<PwaPaymentExit>(
                context: context,
                builder: (_) => const PwaPaymentSheet(product: _pack),
              );
            },
            child: const Text('open'),
          ),
        ),
        overrides: [
          pwaPaymentProvider.overrideWith((ref) => controller),
          pwaEntitlementProvider.overrideWith((ref) => _CountingEntitlement()),
        ],
      ));
      await tester.pump(); // localisations load before the first frame
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pwa-pay-result-continue')));
      await tester.pumpAndSettle();
      expect(exit, PwaPaymentExit.paid);
      expect(controller.state.state, PwaPaymentState.idle,
          reason: 'the attempt is over; the Wallet shows nothing for it');
      await _teardown(tester);
    });

    testWidgets('RESULT09 Try again closes the card and starts the SAME '
        'purchase over, beneath it', (tester) async {
      var starts = 0;
      final gateway = PwaPaymentGateway(
        startCheckout: ({required sku, required attemptKey}) async {
          starts++;
          return _server(
              state: starts == 1 ? 'FAILED' : 'AWAITING_PAYMENT',
              failureReason: starts == 1 ? 'DECLINED' : '');
        },
        orderStatus: (_) async => _server(state: 'AWAITING_PAYMENT'),
        openOrder: () async => const {'ok': true, 'open': false},
        cancelOrder: (_) async => _server(state: 'CANCELLED'),
      );
      final controller = PwaPaymentController(gateway, null);
      await controller.start('pack_10');
      expect(controller.state.state, PwaPaymentState.failed);

      PwaPaymentExit? exit;
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              exit = await showDialog<PwaPaymentExit>(
                context: context,
                builder: (_) => const PwaPaymentSheet(product: _pack),
              );
            },
            child: const Text('open'),
          ),
        ),
        overrides: [
          pwaPaymentProvider.overrideWith((ref) => controller),
          pwaEntitlementProvider.overrideWith((ref) => _CountingEntitlement()),
        ],
      ));
      await tester.pump(); // localisations load before the first frame
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pwa-pay-result-retry')));
      await tester.pump();
      await tester.pump();
      expect(exit, PwaPaymentExit.none, reason: 'nothing was paid');
      expect(starts, 2, reason: 'the same attempt is opened again');
      expect(controller.state.state, PwaPaymentState.awaitingPayment);
      expect(find.byKey(const ValueKey('pwa-pay-result-failure')),
          findsNothing, reason: 'the verdict closed before the new checkout');
      await _teardown(tester);
    });

    testWidgets('RESULT10 the return surface is Ayden\'s near-black card with '
        'a gold (success) or red (failure) edge', (tester) async {
      for (final (state, edge) in [
        ('GRANTED', kPwaResultGold),
        ('FAILED', kPwaResultRed),
      ]) {
        final controller = await settled(state);
        await tester.pumpWidget(_app(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showPwaPaymentReturn(context, ref),
              child: const Text('return'),
            ),
          ),
          overrides: [
            pwaPaymentProvider.overrideWith((ref) => controller),
            pwaEntitlementProvider
                .overrideWith((ref) => _CountingEntitlement()),
          ],
        ));
        await tester.pump(); // localisations load before the first frame
        await tester.tap(find.text('return'));
        await tester.pumpAndSettle();

        final dialog = tester.widget<Dialog>(find.byType(Dialog));
        expect(dialog.backgroundColor, kPwaResultSurface, reason: state);
        final shape = dialog.shape! as RoundedRectangleBorder;
        expect(shape.side.color.withValues(alpha: 1.0),
            edge.withValues(alpha: 1.0),
            reason: '$state edge');
        expect(shape.side.color.a, lessThan(0.6),
            reason: 'a tint at the edge, not a frame');
        await _teardown(tester);
      }
    });

    testWidgets('RESULT12 a verdict can be dismissed from outside (a person '
        'who cancelled must be able to return); a confirming card cannot',
        (tester) async {
      for (final (state, dismissible) in [
        ('FAILED', true),
        ('GRANTED', true),
        ('VERIFIED', false),
      ]) {
        final controller = await settled(state);
        PwaPaymentExit? exit;
        var closed = false;
        await tester.pumpWidget(_app(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async {
                exit = await showPwaPaymentReturn(context, ref);
                closed = true;
              },
              child: const Text('return'),
            ),
          ),
          overrides: [
            pwaPaymentProvider.overrideWith((ref) => controller),
            pwaEntitlementProvider
                .overrideWith((ref) => _CountingEntitlement()),
          ],
        ));
        await tester.pump();
        await tester.tap(find.text('return'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(Dialog), findsOneWidget, reason: state);

        // A tap on the scrim, well outside the 400-wide card.
        await tester.tapAt(const Offset(4, 4));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(closed, dismissible,
            reason: '$state: dismissible from outside = $dismissible');
        if (dismissible) {
          expect(exit, PwaPaymentExit.none,
              reason: 'leaving by the scrim is not paying');
        } else {
          expect(find.byType(Dialog), findsOneWidget,
              reason: 'the confirming card stays until the verdict');
        }
        await _teardown(tester);
      }
    });

    testWidgets('RESULT11 both cards fit a phone and a desktop without '
        'overflow, in every locale', (tester) async {
      for (final size in [const Size(390, 844), const Size(1440, 900)]) {
        for (final locale in ['en', 'km', 'fr']) {
          for (final state in ['GRANTED', 'FAILED']) {
            final controller = await settled(state);
            await pumpCard(tester, controller,
                entitlement: _CountingEntitlement(),
                locale: locale,
                size: size);
            expect(tester.takeException(), isNull,
                reason: '$state / $locale / ${size.width.toInt()}');
            await _teardown(tester);
          }
        }
      }
    });
  });


  // ══════════════════════════════════════════════════════════════════════════
  // THE WALLET'S PAYMENT METHOD — a statement, not a door.
  // ══════════════════════════════════════════════════════════════════════════
  group('wallet payment method', () {
    testWidgets('WAL01 the ABA KHQR row has NO chevron', (tester) async {
      // The phone review found a false affordance: a trailing chevron promised
      // a chooser, and tapping the row did nothing — because there is nothing
      // to choose. ABA KHQR is the only method this deployment offers.
      tester.view.physicalSize = const Size(390, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_app(
        const PwaAbaMethodRow(tone: PwaMarkTone.dark),
        overrides: [],
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('pwa-aba-method-row')), findsOneWidget);
      expect(find.text('ABA KHQR'), findsOneWidget);
      for (final glyph in [
        Icons.chevron_right_rounded,
        Icons.chevron_right,
        Icons.arrow_forward_ios,
        Icons.keyboard_arrow_right,
      ]) {
        expect(find.byIcon(glyph), findsNothing,
            reason: 'no affordance may promise a destination that is not there');
      }
      // And no other interactive affordance stood in for it.
      expect(find.byType(Radio<Object?>), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      await _teardown(tester);
    });

    testWidgets('WAL02 the row is not a button, and BUY is still the only CTA',
        (tester) async {
      final src = File(
        'lib/features/pwa/presentation/pwa_aba_marks.dart',
      ).readAsStringSync();
      // No tap handler of any kind on the method row.
      for (final tappable in [
        'onTap:',
        'GestureDetector',
        'InkWell',
        'onPressed:',
      ]) {
        expect(src.contains(tappable), isFalse,
            reason: 'the payment-method row is informational ($tappable)');
      }
      // The Wallet keeps exactly one control that starts a payment.
      final paywall = File(
        'lib/features/pwa/presentation/pwa_paywall.dart',
      ).readAsStringSync();
      expect('showPwaPaymentSheet('.allMatches(paywall).length, 1,
          reason: 'one checkout CTA on the Wallet, and it is Buy');
    });

    testWidgets('WAL03 / ABA-REVIEW-01+02 the row follows ABA\'s payment '
        'option format: their tile, "ABA KHQR", their one-line description',
        (tester) async {
      tester.view.physicalSize = const Size(390, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_app(
        const PwaAbaMethodRow(tone: PwaMarkTone.dark),
        overrides: [],
      ));
      await tester.pump();

      // ABA's official tile, as an SVG picture of the file they supplied.
      final tile = tester.widget<SvgPicture>(
          find.byKey(const ValueKey('pwa-aba-method-mark')));
      expect(tile, isNotNull);
      expect(find.text('ABA KHQR'), findsOneWidget);
      // The exact description, in English, with nothing added.
      final en = pwaL10nFor(const Locale('en'));
      expect(en.payMethodBody, 'Scan to pay with any banking app');
      expect(find.text('Scan to pay with any banking app'), findsOneWidget);
      expect(find.textContaining('supports KHQR'), findsNothing);
      // Khmer and French say the same thing, translated, without the old tail.
      for (final locale in ['km', 'fr']) {
        final l = pwaL10nFor(Locale(locale));
        expect(l.payMethodBody, isNot(en.payMethodBody));
        expect(l.payMethodBody.contains('KHQR'), isFalse,
            reason: 'the "that supports KHQR" tail is gone in $locale too');
      }
      await _teardown(tester);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ABA'S PLUGIN — the active Web checkout since 2026-09-05.
  // ══════════════════════════════════════════════════════════════════════════
  group('ABA checkout plugin', () {
    testWidgets('PLG01 Buy hands the SERVER-signed fields to the plugin, '
        'verbatim', (tester) async {
      var pluginCalls = 0;
      var legacyCalls = 0;
      final gateway = PwaPaymentGateway(
        startCheckout: ({required sku, required attemptKey}) async {
          legacyCalls++;
          return _server(state: 'AWAITING_PAYMENT');
        },
        startPluginCheckout: ({required sku, required attemptKey}) async {
          pluginCalls++;
          return _pluginServer();
        },
        orderStatus: (_) async => _pluginServer(withHandoff: false),
        openOrder: () async => const {'ok': true, 'open': false},
        cancelOrder: (_) async => _server(state: 'CANCELLED'),
      );
      final plugin = _RecordingAbaPlugin();
      final controller = PwaPaymentController(gateway, null, plugin: plugin);
      await controller.start('pack_10');

      expect(pluginCalls, 1, reason: 'the plugin path is the active one');
      expect(legacyCalls, 0, reason: 'the server-side Purchase path is dormant');
      expect(plugin.launches.length, 1);
      expect(plugin.launches.single.action,
          'https://gateway.example/api/purchase');
      // Relayed, not read: every key the server sent, and nothing added.
      expect(plugin.launches.single.fields, {
        'hash': 'SIGNATURE==',
        'tran_id': 'A0123456789abcdef012',
        'amount': '4.99',
        'req_time': '20260905170000',
        'payment_option': 'abapay_khqr',
        'currency': 'USD',
        'skip_success_page': '1',
      });
      // ABA-REVIEW-05 (PWA side): the flag reaches the plugin as the server
      // signed it — the client never decides what ABA shows after payment.
      expect(plugin.launches.single.fields['skip_success_page'], '1');
      expect(controller.lastPluginLaunch, PwaAbaPluginLaunch.launched);
      expect(controller.state.state, PwaPaymentState.awaitingPayment,
          reason: 'opening the popup is not a payment');
      controller.dispose();
    });

    testWidgets('PLG02 without a plugin the controller keeps the old path',
        (tester) async {
      var pluginCalls = 0;
      var legacyCalls = 0;
      final gateway = PwaPaymentGateway(
        startCheckout: ({required sku, required attemptKey}) async {
          legacyCalls++;
          return _server(state: 'AWAITING_PAYMENT');
        },
        startPluginCheckout: ({required sku, required attemptKey}) async {
          pluginCalls++;
          return _pluginServer();
        },
        orderStatus: (_) async => _server(state: 'AWAITING_PAYMENT'),
        openOrder: () async => const {'ok': true, 'open': false},
        cancelOrder: (_) async => _server(state: 'CANCELLED'),
      );
      final controller = PwaPaymentController(gateway, null);
      await controller.start('pack_10');
      expect(legacyCalls, 1);
      expect(pluginCalls, 0);
      controller.dispose();
    });

    testWidgets('PLG03 a rejoin launches nothing — one Purchase per tran_id',
        (tester) async {
      final gateway = PwaPaymentGateway(
        startCheckout: ({required sku, required attemptKey}) async =>
            _server(state: 'AWAITING_PAYMENT'),
        startPluginCheckout: ({required sku, required attemptKey}) async =>
            _pluginServer(withHandoff: false),
        orderStatus: (_) async => _pluginServer(withHandoff: false),
        openOrder: () async => const {'ok': true, 'open': false},
        cancelOrder: (_) async => _server(state: 'CANCELLED'),
      );
      final plugin = _RecordingAbaPlugin();
      final controller = PwaPaymentController(gateway, null, plugin: plugin);
      await controller.start('pack_10');
      expect(plugin.launches, isEmpty,
          reason: 'no fields came back, so there is nothing to post');
      expect(controller.lastPluginLaunch, isNull);
      controller.dispose();
    });

    testWidgets('PLG04 behind the popup the card is a STATUS, not a second '
        'checkout', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final gateway = PwaPaymentGateway(
        startCheckout: ({required sku, required attemptKey}) async =>
            _server(state: 'AWAITING_PAYMENT'),
        startPluginCheckout: ({required sku, required attemptKey}) async =>
            _pluginServer(),
        orderStatus: (_) async => _pluginServer(withHandoff: false),
        openOrder: () async => const {'ok': true, 'open': false},
        cancelOrder: (_) async => _server(state: 'CANCELLED'),
      );
      final plugin = _RecordingAbaPlugin();
      final controller = PwaPaymentController(gateway, null, plugin: plugin);
      await controller.start('pack_10');

      await tester.pumpWidget(_app(
        const PwaPaymentSheet(product: _pack),
        overrides: [pwaPaymentProvider.overrideWith((ref) => controller)],
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('pwa-pay-plugin-open')), findsOneWidget);
      // None of the dormant custom-checkout pieces are rendered.
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images.any((i) => i.image is MemoryImage), isFalse,
          reason: 'no server-rendered QR on the plugin path');
      expect(find.byKey(const ValueKey('pwa-pay-open-aba-mobile')), findsNothing,
          reason: 'no custom ABA Mobile button — the plugin owns that prompt');
      expect(find.byKey(const ValueKey('pwa-pay-open-checkout')), findsNothing,
          reason: 'no new-tab handoff either');
      // What IS here: the status, the timer, and the way out.
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.payPluginOpen), findsOneWidget);
      expect(find.text(l.payWaiting), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-pay-close')), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('PLG05 the plugin launch result never becomes a payment state',
        (tester) async {
      // A launch that "succeeds" and a launch that fails must leave the
      // payment exactly where the SERVER put it.
      for (final supported in [true, false]) {
        final gateway = PwaPaymentGateway(
          startCheckout: ({required sku, required attemptKey}) async =>
              _server(state: 'AWAITING_PAYMENT'),
          startPluginCheckout: ({required sku, required attemptKey}) async =>
              _pluginServer(),
          orderStatus: (_) async => _pluginServer(withHandoff: false),
          openOrder: () async => const {'ok': true, 'open': false},
          cancelOrder: (_) async => _server(state: 'CANCELLED'),
        );
        final plugin = _RecordingAbaPlugin(supported: supported);
        final entitlement = _CountingEntitlement();
        final controller = PwaPaymentController(
          gateway, entitlement.refresh, plugin: plugin);
        await controller.start('pack_10');
        expect(controller.state.state, PwaPaymentState.awaitingPayment,
            reason: 'supported=$supported: the popup decides nothing');
        expect(entitlement.refreshes, 0);
        controller.dispose();
      }
    });

    testWidgets('PLG06 Dart names no PayWay field and builds no iframe',
        (tester) async {
      // The bridge relays an opaque map. If a field name ever appears in Dart
      // the client has started to KNOW the protocol, which is the first step
      // toward signing it. And ABA's plugin owns the iframe — we build none.
      for (final path in [
        'lib/features/pwa/data/pwa_aba_plugin.dart',
        'lib/features/pwa/data/pwa_aba_plugin_web.dart',
        'lib/features/pwa/data/pwa_aba_plugin_stub.dart',
        'lib/features/pwa/billing/pwa_payment_controller.dart',
      ]) {
        final src = File(path).readAsStringSync();
        for (final banned in [
          "'merchant_id'", "'hash'", "'req_time'", "'amount'",
          "'payment_option'", 'HTMLIFrameElement', 'createElement',
          'HtmlElementView',
        ]) {
          expect(src.contains(banned), isFalse,
              reason: '$path must not contain $banned');
        }
      }
      // The official script, from ABA's host, with the flag that stops a
      // close from reloading the page.
      final index = File('web/index.html').readAsStringSync();
      expect(index.contains(
          'https://checkout.payway.com.kh/plugins/checkout2-0.js?hide-close=2'),
          isTrue, reason: "ABA's plugin, from ABA, with hide-close=2");
      expect(index.contains("form.target = 'aba_webservice'"), isTrue,
          reason: 'the form targets the iframe the plugin names');
      expect(index.contains("form.id = 'aba_merchant_request'"), isTrue);
      // The BARE identifier: the plugin's `const AbaPayway` is not on window.
      expect(index.contains('AbaPayway.checkout();'), isTrue);
      expect(index.contains('window.AbaPayway'), isFalse,
          reason: 'a top-level const is not a window property');
      // And the page ships no PayWay secret or endpoint of its own.
      for (final banned in [
        'payment-gateway/v1/payments', 'checkout-sandbox', 'PAYWAY_',
        'merchant_id', 'sha512',
      ]) {
        expect(index.contains(banned), isFalse,
            reason: 'index.html must not contain $banned');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ONE CHECKOUT SURFACE — the plugin's. Found on a real phone: Ayden's own
  // payment sheet opened first and ABA's sheet opened over it.
  // ══════════════════════════════════════════════════════════════════════════
  group('double modal', () {
    /// A Wallet with one purchasable pack, a configured rail, a plugin, and a
    /// scriptable gateway — the exact production wiring, in miniature.
    Future<({PwaEntitlementController entitlement, _RecordingAbaPlugin plugin})>
        pumpWallet(
      WidgetTester tester, {
      required Map<String, Object?> Function() onStatus,
      Map<String, Object?> Function()? onPluginStart,
    }) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final entitlement = PwaEntitlementController(() async => {
            'can_generate': false,
            'billing_state': 'FREE_EXHAUSTED',
            'payment': {'provider': 'payway', 'configured': true},
            'products': [
              {
                'sku': 'pack_10', 'type': 'CREDIT_PACK', 'credits': 10,
                'price_usd': 4.99, 'currency': 'USD',
                'store_only': false, 'web_enabled': true,
                'metadata': {'badge': 'popular'},
              },
            ],
          });
      await entitlement.refresh();
      final plugin = _RecordingAbaPlugin();
      final gateway = PwaPaymentGateway(
        startCheckout: ({required sku, required attemptKey}) async =>
            _server(state: 'AWAITING_PAYMENT'),
        startPluginCheckout: ({required sku, required attemptKey}) async =>
            (onPluginStart ?? _pluginServer)(),
        orderStatus: (_) async => onStatus(),
        openOrder: () async => const {'ok': true, 'open': false},
        cancelOrder: (_) async => _server(state: 'CANCELLED'),
      );
      await tester.pumpWidget(_app(
        const PwaPaywallSheet(),
        overrides: [
          pwaEntitlementProvider.overrideWith((ref) => entitlement),
          pwaPaymentGatewayProvider.overrideWithValue(gateway),
          pwaAbaPluginProvider.overrideWithValue(plugin),
        ],
      ));
      await tester.pumpAndSettle();
      return (entitlement: entitlement, plugin: plugin);
    }

    testWidgets('DM01/DM02/DM03 Buy launches the plugin and mounts NO Ayden '
        'payment sheet', (tester) async {
      final w = await pumpWallet(
          tester, onStatus: () => _pluginServer(withHandoff: false));

      expect(find.byType(PwaPaymentSheet), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pwa-paywall-continue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // DM02 — the plugin was invoked, once, right after preparation.
      expect(w.plugin.launches.length, 1);
      // DM01 / DM03 — and nothing of ours is presenting a checkout.
      expect(find.byType(PwaPaymentSheet), findsNothing,
          reason: 'the plugin owns the checkout surface');
      expect(find.byType(Dialog), findsNothing);
      // The Wallet is still the surface: packs and CTA are still there.
      expect(find.byKey(const ValueKey('pwa-pack-pack_10')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-paywall-continue')), findsOneWidget);
      // DM04 — what IS shown is one quiet line, not a second surface.
      expect(find.byKey(const ValueKey('pwa-paywall-payment-inline')),
          findsOneWidget);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.payInlineChecking), findsOneWidget);
      expect(find.text(l.payPluginOpen), findsNothing,
          reason: 'no "checkout is open" card');
      expect(find.text(l.payWaiting), findsNothing);
      await _teardown(tester);
    });

    testWidgets('DM07 / ABA-REVIEW-13 the Wallet says nothing about the '
        'provider — before Buy, and while the payment is being checked',
        (tester) async {
      final w = await pumpWallet(tester, onStatus: _pluginServer);
      final l = pwaL10nFor(const Locale('en'));
      Iterable<String> visible() => tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');
      void noProviderProse(String when) {
        for (final s in visible()) {
          expect(s.contains('PayWay'), isFalse, reason: '$when: "$s"');
          expect(s.replaceAll('ABA KHQR', '').contains('ABA'), isFalse,
              reason: '$when: "$s"');
        }
        expect(find.textContaining('secure page'), findsNothing,
            reason: when);
      }
      // The method is named exactly once: ABA's tile, "ABA KHQR", their
      // description — and nothing under Buy.
      expect(find.text('ABA KHQR'), findsOneWidget);
      expect(find.text(l.payMethodBody), findsOneWidget);
      noProviderProse('before Buy');

      await tester.tap(find.byKey(const ValueKey('pwa-paywall-continue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(w.plugin.launches.length, 1);
      // The status line is kept — useful feedback — without a provider in it.
      expect(find.text('Checking your payment…'), findsOneWidget);
      noProviderProse('while checking');
      await _teardown(tester);
    });

    testWidgets('DM05/DM06 Ayden builds no checkout iframe; the plugin does',
        (tester) async {
      for (final path in [
        'lib/features/pwa/presentation/pwa_paywall.dart',
        'lib/features/pwa/presentation/pwa_payment_sheet.dart',
        'lib/features/pwa/billing/pwa_payment_controller.dart',
        'lib/features/pwa/data/pwa_aba_plugin_web.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src.contains('HTMLIFrameElement'), isFalse, reason: path);
        expect(src.contains('HtmlElementView'), isFalse, reason: path);
        expect(src.contains("createElement('iframe')"), isFalse, reason: path);
      }
      final index = File('web/index.html').readAsStringSync();
      expect(index.contains("createElement('iframe')"), isFalse,
          reason: 'the bridge builds a FORM; the iframe is the plugin\'s');
      expect(index.contains("form.target = 'aba_webservice'"), isTrue);
    });

    testWidgets('ERR02/ERR03/ERR05/ERR06 NOT_CREATED leaves no waiting state '
        'and returns the Wallet', (tester) async {
      // The server concluded the transaction was never created (Error 6 →
      // "tran_id not found" past the grace window) and answers the poll with
      // FAILED / NOT_CREATED.
      var polls = 0;
      final w = await pumpWallet(tester, onStatus: () {
        polls++;
        return _server(state: 'FAILED', failureReason: 'NOT_CREATED')
          ..['checkout_mode'] = 'plugin'
          ..['checkout_url'] = '';
      });
      await tester.tap(find.byKey(const ValueKey('pwa-paywall-continue')));
      await tester.pump();
      // First poll fires at the server's interval.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();

      final l = pwaL10nFor(const Locale('en'));
      // ERR02 — no "waiting", ERR03 — no countdown.
      expect(find.text(l.payWaiting), findsNothing);
      expect(find.textContaining(':'), findsNothing,
          reason: 'no mm:ss countdown anywhere on the Wallet');
      expect(find.byKey(const ValueKey('pwa-paywall-payment-inline')),
          findsNothing, reason: 'the checking line is gone');
      // ERR06 — the Wallet is what the person sees, with a short reason.
      expect(find.byKey(const ValueKey('pwa-pack-pack_10')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-paywall-payment-error')),
          findsOneWidget);
      expect(find.text(l.payFailedBody('NOT_CREATED')), findsOneWidget);
      expect(find.byType(PwaPaymentSheet), findsNothing);
      // ERR05 — polling stopped: no further poll after the terminal answer.
      final before = polls;
      await tester.pump(const Duration(seconds: 10));
      expect(polls, before, reason: 'a terminal answer ends the poll');
      // ERR04 — nothing granted.
      expect(w.entitlement.state.creditsAvailable, 0);
      // And Buy is live again for a NEW attempt.
      final cta = tester.widget<PwaGoldCta>(
          find.byKey(const ValueKey('pwa-paywall-continue')));
      expect(cta.onPressed, isNotNull);
      expect(w.plugin.launches.length, 1);
      await _teardown(tester);
    });

    testWidgets('PAY02 a cancelled plugin payment returns to the Wallet with '
        'no line at all', (tester) async {
      await pumpWallet(
          tester, onStatus: () => _pluginServer(withHandoff: false));
      await tester.tap(find.byKey(const ValueKey('pwa-paywall-continue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('pwa-paywall-payment-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('pwa-paywall-payment-inline')),
          findsNothing);
      expect(find.byKey(const ValueKey('pwa-paywall-payment-error')),
          findsNothing, reason: 'cancelling is a decision, not an error');
      expect(find.byType(PwaPaymentSheet), findsNothing);
      await _teardown(tester);
    });

    testWidgets('PAY03 GRANTED closes the Wallet — and grants once',
        (tester) async {
      // The Wallet is a modal ROUTE in production (`showPwaPaywall` →
      // showModalBottomSheet), and closing it is a pop. So here it is pushed
      // the same way, from a host page, rather than pumped bare — a bare sheet
      // has no route to pop and would sit there whatever the code did.
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final entitlement = PwaEntitlementController(() async => {
            'can_generate': false,
            'billing_state': 'FREE_EXHAUSTED',
            'payment': {'provider': 'payway', 'configured': true},
            'products': [
              {
                'sku': 'pack_10', 'type': 'CREDIT_PACK', 'credits': 10,
                'price_usd': 4.99, 'currency': 'USD',
                'store_only': false, 'web_enabled': true,
                'metadata': {'badge': 'popular'},
              },
            ],
          });
      await entitlement.refresh();
      final plugin = _RecordingAbaPlugin();
      final gateway = PwaPaymentGateway(
        startCheckout: ({required sku, required attemptKey}) async =>
            _server(state: 'AWAITING_PAYMENT'),
        startPluginCheckout: ({required sku, required attemptKey}) async =>
            _pluginServer(),
        orderStatus: (_) async => _pluginServer(state: 'GRANTED'),
        openOrder: () async => const {'ok': true, 'open': false},
        cancelOrder: (_) async => _server(state: 'CANCELLED'),
      );
      await tester.pumpWidget(_app(
        Builder(
          builder: (ctx) => TextButton(
            key: const ValueKey('open-wallet'),
            onPressed: () => showModalBottomSheet<void>(
              context: ctx,
              isScrollControlled: true,
              builder: (_) => const PwaPaywallSheet(),
            ),
            child: const Text('open'),
          ),
        ),
        overrides: [
          pwaEntitlementProvider.overrideWith((ref) => entitlement),
          pwaPaymentGatewayProvider.overrideWithValue(gateway),
          pwaAbaPluginProvider.overrideWithValue(plugin),
        ],
      ));
      // The localisation delegates load asynchronously: the first frame is
      // empty until they do, so settle before looking for the host button.
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-wallet')));
      await tester.pumpAndSettle();
      expect(find.byType(PwaPaywallSheet), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pwa-paywall-continue')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      // The sheet popped itself. Success is presented by the return watcher
      // (see pwa_experience.dart), not by a second surface here.
      expect(find.byType(PwaPaywallSheet), findsNothing);
      expect(find.byType(PwaPaymentSheet), findsNothing);
      expect(plugin.launches.length, 1);
      await _teardown(tester);
    });
  });
}
