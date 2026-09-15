/// GUARD01-GUARD20 — a pack is never bought by a browser, only by an account.
///
/// THE JOURNEY THIS CLOSES, demonstrated by the first real production purchase
/// -------------------------------------------------------------------------
/// An anonymous guest buys Spaces through ABA. The payment succeeds. The
/// ledger is exactly right. Then the browser storage goes, and the session with
/// it — and the entitlement is attached for ever to a user id nobody can sign
/// into again. Nothing is broken in the accounts. From where the customer
/// stands, they paid and received nothing.
///
/// So the fix is not a better recovery: it is not opening the purchase. A Guest
/// may look around, make projects and spend a free trial — lose that and you
/// lose nothing you paid for. A pack is different, and the difference is the
/// whole of this file.
///
/// TWO LOCKS, and the second is the one that matters
/// -------------------------------------------------
/// The Buy button asks for an account first (GUARD02/03/07). The SERVER refuses
/// to create a transaction for an anonymous caller whatever the button did
/// (GUARD09/10), because a stale bundle, a replayed request or a second tab
/// racing a half-finished link must not be able to do what the button will not.
/// The server half is proved in `backend/pwa_payment_account_guard_test.py`
/// against GoTrue's own payload shapes, read off production.
library;

import 'package:ai_home_architect/features/pwa/auth/pwa_auth_controller.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_service.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement_controller.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_payment.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_payment_controller.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_aba_plugin.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_payment_result.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_paywall.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ── doubles ──────────────────────────────────────────────────────────────────

const _catalogue = [
  {
    'sku': 'pack_10',
    'type': 'CREDIT_PACK',
    'credits': 10,
    'price_usd': 4.99,
    'currency': 'USD',
    'store_only': false,
    'web_enabled': true,
  },
];

PwaEntitlement _sellable() => PwaEntitlement.parse({
      'can_generate': false,
      'billing_state': 'FREE_EXHAUSTED',
      'free_credits': 0,
      'credits_available': 0,
      'products': _catalogue,
      'payment': {'provider': 'khqr', 'configured': true},
    });

class _FrozenEntitlement extends PwaEntitlementController {
  _FrozenEntitlement(PwaEntitlement value) : super(null) {
    state = value;
  }

  @override
  Future<void> refresh() async {}
}

/// A guest, or somebody. The ONE fact the purchase gate reads.
class _Auth extends PwaAuthController {
  _Auth({required bool identified}) : super(null) {
    if (identified) {
      state = const PwaAuthState(stage: PwaAuthStage.identified);
    }
  }
}

/// Records every call. What must NOT happen for a guest is anything at all:
/// no attempt, no order, no tran_id, no QR, no billing reservation.
class _Gateway {
  final calls = <String>[];

  PwaPaymentGateway get gateway => PwaPaymentGateway(
        startCheckout: ({required String sku, required String attemptKey}) async {
          calls.add('checkout:$sku');
          return const {'ok': true, 'state': 'AWAITING_PAYMENT'};
        },
        startPluginCheckout:
            ({required String sku, required String attemptKey}) async {
          calls.add('plugin:$sku');
          return const {
            'ok': true,
            'state': 'AWAITING_PAYMENT',
            'tran_id': 'A0',
            'checkout_mode': 'plugin',
          };
        },
        orderStatus: (t) async => const {'ok': true, 'open': false},
        openOrder: () async => const {'ok': true, 'open': false},
        cancelOrder: (t) async => const {'ok': true, 'state': 'CANCELLED'},
      );
}

class _Plugin implements PwaAbaPlugin {
  @override
  bool get isSupported => true;

  @override
  PwaAbaPluginLaunch launch({
    required String formAction,
    required Map<String, String> fields,
  }) => PwaAbaPluginLaunch.launched;
}

Future<_Gateway> _pumpPaywall(WidgetTester tester,
    {required bool identified}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final gw = _Gateway();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pwaEntitlementProvider
            .overrideWith((ref) => _FrozenEntitlement(_sellable())),
        pwaAuthProvider.overrideWith((ref) => _Auth(identified: identified)),
        pwaPaymentGatewayProvider.overrideWithValue(gw.gateway),
        pwaAbaPluginProvider.overrideWithValue(_Plugin()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: PwaL10n.supportedLocales,
        localizationsDelegates: const [
          PwaL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: PwaPaywallSheet()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return gw;
}

Future<void> _tapBuy(WidgetTester tester) async {
  final buy = find.byKey(const ValueKey('pwa-paywall-continue'));
  expect(buy, findsOneWidget, reason: 'the paywall must offer Buy at all');
  // The paywall scrolls; a tap at a widget's centre must land inside the
  // viewport or it hits whatever IS there and the handler never runs.
  await tester.ensureVisible(buy);
  await tester.pump();
  await tester.tap(buy, warnIfMissed: true);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('THE TAP  a Guest is asked for an account, not for money', () {
    testWidgets('GUARD02 a Guest pressing Buy creates NOTHING', (tester) async {
      final gw = await _pumpPaywall(tester, identified: false);
      await _tapBuy(tester);

      expect(gw.calls, isEmpty,
          reason: 'no PayWay transaction, no order, no checkout, no QR, '
              'no billing reservation — the request is never made');
      await tester.pumpAndSettle();
    });

    testWidgets('GUARD03 …and is shown the account flow instead',
        (tester) async {
      await _pumpPaywall(tester, identified: false);
      await _tapBuy(tester);

      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'the secure-account sheet, opened in the LINK journey');
      await tester.pumpAndSettle();
    });

    testWidgets('GUARD07/GUARD15 a secured account goes straight to checkout',
        (tester) async {
      final gw = await _pumpPaywall(tester, identified: true);
      await _tapBuy(tester);

      expect(gw.calls, ['plugin:pack_10'],
          reason: 'the existing ABA flow, unchanged, for somebody who has an '
              'account to attach it to');
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'nothing to ask: no extra step for a secured buyer');
      await tester.pumpAndSettle();
    });
  });

  group('THE WORDS  a prerequisite never reads as a payment failure', () {
    test('GUARD14 ACCOUNT_REQUIRED is its own class and its own state', () {
      expect(pwaClassifyPaymentError('ACCOUNT_REQUIRED'),
          PwaPaymentErrorClass.account);
      final p = PwaPayment.parse(
          const {'ok': false, 'http_status': 403, 'error_code': 'ACCOUNT_REQUIRED'});
      expect(p.state, PwaPaymentState.accountRequired);
      expect(p.state, isNot(PwaPaymentState.failed));
    });

    test('GUARD14b it shows no verdict card, from either origin', () {
      expect(pwaPaymentResultKindFor(PwaPaymentState.accountRequired), isNull,
          reason: 'no red cross, no "Payment failed / cancelled"');
      for (final origin in PwaPaymentOrigin.values) {
        expect(
            pwaPaymentAnnouncementFor(PwaPaymentState.accountRequired, origin),
            PwaPaymentAnnouncement.none);
      }
    });

    test('GUARD14c the copy it maps to is about the ACCOUNT, not about money',
        () {
      for (final locale in const [Locale('en'), Locale('km'), Locale('fr')]) {
        final l = pwaL10nFor(locale);
        expect(l.authSecurePurchaseTitle.trim(), isNotEmpty, reason: '$locale');
        expect(l.authSecurePurchaseBody.trim(), isNotEmpty, reason: '$locale');
        // It must not be the key falling through, and must not borrow the
        // payment-failure vocabulary.
        expect(l.authSecurePurchaseTitle, isNot(contains('pwaAuth')));
        expect(l.authSecurePurchaseTitle.toLowerCase(),
            isNot(contains('fail')));
        expect(l.authSecurePurchaseBody, isNot(equals(l.payResultFailedBody)));
      }
    });
  });

  group('THE OTHER STATES  nothing else moved', () {
    test('GUARD18 the stale-return rule is untouched', () {
      // A restored failure stays silent; an active one still speaks.
      expect(
          pwaPaymentAnnouncementFor(
              PwaPaymentState.failed, PwaPaymentOrigin.restore),
          PwaPaymentAnnouncement.none);
      expect(
          pwaPaymentAnnouncementFor(
              PwaPaymentState.failed, PwaPaymentOrigin.activeCheckout),
          PwaPaymentAnnouncement.failure);
      expect(
          pwaPaymentAnnouncementFor(
              PwaPaymentState.granted, PwaPaymentOrigin.restore),
          PwaPaymentAnnouncement.success);
    });

    test('GUARD17 an authoritative terminal state still means what it said',
        () {
      for (final (raw, want) in const [
        ('GRANTED', PwaPaymentState.granted),
        ('FAILED', PwaPaymentState.failed),
        ('AWAITING_PAYMENT', PwaPaymentState.awaitingPayment),
      ]) {
        expect(
            PwaPayment.parse({'ok': true, 'state': raw, 'tran_id': 'A0'}).state,
            want);
      }
    });

    test('the refusal vocabulary still keeps everything else off `failed`', () {
      for (final code in const [
        'SESSION_EXPIRED',
        'PAYMENTS_CLOSED',
        'PAYMENT_UNAVAILABLE',
        'UNKNOWN_TRANSACTION',
        'ACCOUNT_REQUIRED',
      ]) {
        expect(
            PwaPayment.parse({'ok': false, 'error_code': code}).state,
            isNot(PwaPaymentState.failed),
            reason: code);
      }
      expect(
          PwaPayment.parse(
              const {'ok': false, 'error_code': 'PAYMENT_PROVIDER_REFUSED'})
              .state,
          PwaPaymentState.failed,
          reason: 'a gateway that actually refused still is a failure');
    });
  });
}
