/// PRICE-01..20 — Cambodia credit packs: one-time purchases, one price source.
///
/// WHAT THE PRODUCT IS NOW
/// -----------------------
/// Three free Spaces, then one-time packs. No subscription, no renewal, no
/// expiry, no Apple commission. 10/$2.50, 25/$5, 50/$8, 100/$14 — with 25 as
/// MOST POPULAR and 100 as BEST VALUE.
///
/// WHERE THE PRICE LIVES, and why these tests look the way they do
/// ---------------------------------------------------------------
/// The authoritative catalogue is the `public.products` table. The client never
/// holds a price: it receives the catalogue in the entitlement payload and
/// sends back only a SKU, and the server resolves the payable amount from
/// `products.price_usd` by that SKU alone (`resolve_web_product`). So there is
/// nothing in Dart to "change the price of" — and the tests that matter here
/// are that the client cannot influence the amount, that it renders whatever
/// the catalogue says, and that the wording no longer sells a subscription.
///
/// The four price ROWS are data, not code; their values are asserted against a
/// catalogue payload shaped exactly like the server's.
library;

import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement_controller.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_payment.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_translations.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_paywall.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:io';

// ── the catalogue, in the shape `pwa_staging_billing.catalogue()` emits ──────

const _cambodiaPacks = [
  {
    'sku': 'pack_10', 'type': 'CREDIT_PACK', 'credits': 10,
    'duration_days': null, 'price_usd': 2.50, 'currency': 'USD',
    'store_only': false, 'web_enabled': true, 'badge': '',
  },
  {
    'sku': 'pack_25', 'type': 'CREDIT_PACK', 'credits': 25,
    'duration_days': null, 'price_usd': 5.00, 'currency': 'USD',
    'store_only': false, 'web_enabled': true, 'badge': 'popular',
  },
  {
    'sku': 'pack_50', 'type': 'CREDIT_PACK', 'credits': 50,
    'duration_days': null, 'price_usd': 8.00, 'currency': 'USD',
    'store_only': false, 'web_enabled': true, 'badge': '',
  },
  {
    'sku': 'pack_100', 'type': 'CREDIT_PACK', 'credits': 100,
    'duration_days': null, 'price_usd': 14.00, 'currency': 'USD',
    'store_only': false, 'web_enabled': true, 'badge': 'best_value',
  },
];

PwaEntitlement _entitlement({List<Object?> products = _cambodiaPacks}) =>
    PwaEntitlement.parse({
      'can_generate': false,
      'billing_state': 'FREE_EXHAUSTED',
      'free_credits': 0,
      'credits_available': 0,
      'trial_materialized': true,
      'products': products,
      'payment': {'provider': 'khqr', 'configured': true},
    });

PwaProduct _pack(String sku) =>
    _entitlement().products.firstWhere((p) => p.sku == sku);

class _Frozen extends PwaEntitlementController {
  _Frozen(PwaEntitlement v) : super(null) {
    state = v;
  }
  @override
  Future<void> refresh() async {}
}

String _read(String p) => File(p).readAsStringSync();

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  group('THE FOUR PACKS  price and quantity are independent', () {
    for (final (label, sku, credits, price, money) in const [
      ('PRICE-01', 'pack_10', 10, 2.50, r'$2.50'),
      ('PRICE-02', 'pack_25', 25, 5.00, r'$5'),
      ('PRICE-03', 'pack_50', 50, 8.00, r'$8'),
      ('PRICE-04', 'pack_100', 100, 14.00, r'$14'),
    ]) {
      test('$label $sku = $credits Spaces at $money', () {
        final p = _pack(sku);
        expect(p.credits, credits, reason: 'the GRANT, untouched by pricing');
        expect(p.priceUsd, price, reason: 'the authoritative amount');
        expect(p.priceLabel, money, reason: 'and how a person reads it');
        expect(p.type, 'CREDIT_PACK');
        expect(p.durationDays, isNull, reason: 'a pack does not expire');
        expect(p.webEnabled, isTrue);
        expect(p.storeOnly, isFalse);
      });
    }

    test('cents survive where they carry information', () {
      // 2.50 must never become "2.5" or "3"; 5.00 must never read "5.00".
      expect(pwaMoney(2.50), '2.50');
      expect(pwaMoney(5.00), '5');
      expect(pwaMoney(8.00), '8');
      expect(pwaMoney(14.00), '14');
      expect(pwaMoney(11.99), '11.99');
    });

    test('PRICE-10 no subscription product is introduced', () {
      for (final p in _entitlement().products) {
        expect(p.type, 'CREDIT_PACK', reason: '${p.sku} is not a PASS');
        expect(p.durationDays, isNull,
            reason: '${p.sku} carries no renewal period');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('THE PRICE PATH  the client never gets a say', () {
    test('PRICE-05/06 nothing the client sends carries an amount', () {
      // The two checkout calls take a sku and an attempt key. There is no
      // amount, no price and no currency anywhere in the request the browser
      // composes — so there is nothing to forge.
      final api = _read('lib/features/pwa/data/pwa_generation_api.dart');
      final checkout = api.substring(
          api.indexOf('Future<Map<String, Object?>> startCheckout('),
          api.indexOf('Future<Map<String, Object?>> orderStatus('));
      expect(checkout, contains("'sku': sku"));
      expect(checkout, contains("'attempt_key': attemptKey"));
      for (final forbidden in const [
        "'amount'", "'price'", "'price_usd'", "'currency'", "'total'",
      ]) {
        expect(checkout.contains(forbidden), isFalse,
            reason: 'a checkout body must never name $forbidden');
      }
    });

    test('PRICE-06b the PWA holds no price table of its own', () {
      // Every price on screen came from the server's catalogue. A constant here
      // would be a second source of truth, and the first one to rot.
      final dir = Directory('lib/features/pwa');
      final offenders = <String>[];
      for (final f in dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        for (final sku in const ['pack_10', 'pack_25', 'pack_50', 'pack_100']) {
          if (src.contains("'$sku'")) offenders.add('${f.path}: $sku');
        }
      }
      expect(offenders, isEmpty,
          reason: 'no SKU may be named in the client: it selects what the '
              'catalogue offered, it does not know the catalogue');
    });

    test('PRICE-07 an unknown sku yields no product and no price', () {
      final e = _entitlement();
      expect(e.products.where((p) => p.sku == 'pack_999'), isEmpty);
      // A malformed catalogue row is dropped rather than half-parsed.
      expect(PwaProduct.parse(const {'type': 'CREDIT_PACK'}), isNull);
      expect(PwaProduct.parse(const {'sku': ''}), isNull);
    });

    test('the payment card shows the amount the SERVER reported', () {
      // Not the catalogue, and not a local multiplication: the payment row's
      // own amount, formatted by the one money helper.
      final paid = PwaPayment.parse(const {
        'ok': true, 'state': 'GRANTED', 'tran_id': 'A0',
        'sku': 'pack_25', 'credits': 25, 'amount': 5.0, 'currency': 'USD',
      });
      expect(paid.amountLabel, r'$5');
      expect(paid.credits, 25);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('THE MERCHANDISING  badges come from the catalogue', () {
    test('PRICE-12 pack_25 is MOST POPULAR', () {
      expect(_pack('pack_25').badge, 'popular');
      for (final locale in const [Locale('en'), Locale('km'), Locale('fr')]) {
        final label = pwaL10nFor(locale).productBadge('popular');
        expect(label.trim(), isNotEmpty, reason: '$locale');
        expect(label, isNot(contains('pwaProduct')), reason: '$locale');
      }
      expect(pwaL10nFor(const Locale('en')).productBadge('popular'),
          'MOST POPULAR');
    });

    test('PRICE-13 pack_100 is BEST VALUE', () {
      expect(_pack('pack_100').badge, 'best_value');
      expect(pwaL10nFor(const Locale('en')).productBadge('best_value'),
          'BEST VALUE');
      for (final locale in const [Locale('km'), Locale('fr')]) {
        expect(pwaL10nFor(locale).productBadge('best_value').trim(), isNotEmpty,
            reason: '$locale');
      }
    });

    test('the other two packs carry no badge', () {
      expect(_pack('pack_10').badge, isEmpty);
      expect(_pack('pack_50').badge, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('THE WORDS  a pack is not a subscription', () {
    /// Every user-facing string in the three dictionaries.
    Iterable<MapEntry<String, String>> allStrings() sync* {
      for (final d in [pwaEnTranslations, pwaKmTranslations, pwaFrTranslations]) {
        yield* d.entries;
      }
    }

    test('PRICE-14 "Your pass is active" is gone from every language', () {
      for (final e in allStrings()) {
        expect(e.value.toLowerCase(), isNot(contains('pass is active')),
            reason: e.key);
        expect(e.value.toLowerCase(), isNot(contains('pass est actif')),
            reason: e.key);
      }
      for (final locale in const [Locale('en'), Locale('km'), Locale('fr')]) {
        final l = pwaL10nFor(locale);
        expect(l.paywallActiveTitle.toLowerCase(), isNot(contains('pass')),
            reason: '$locale');
      }
    });

    test('PRICE-15 no subscription or unlimited wording in the pack flow', () {
      // The strings the credit-pack journey actually renders.
      for (final locale in const [Locale('en'), Locale('km'), Locale('fr')]) {
        final l = pwaL10nFor(locale);
        final flow = <String>[
          l.paywallTitle,
          l.paywallFreeUsedTitle,
          l.paywallFreeUsedBody,
          l.paywallPassExhaustedTitle,
          l.paywallPassExhaustedBody,
          l.paywallActiveTitle,
          l.paywallActiveBody,
          l.payBuy,
          l.payResultSuccessTitle,
        ].join(' ').toLowerCase();
        // The DENIALS are the point of the new copy — "No subscription",
        // "Sans abonnement" — so they are removed before the word itself is
        // searched for. What must not survive is a subscription being OFFERED.
        var claims = flow;
        for (final denial in const [
          'no subscription',
          'sans abonnement',
          'គ្មាន​ការ​ជាវ​ប្រចាំ',
        ]) {
          claims = claims.replaceAll(denial, '');
        }
        for (final banned in const [
          'subscription', 'monthly', 'weekly', 'annually', 'auto-renew',
          'unlimited', 'design as much as you like',
          'abonnement', 'mensuel', 'hebdomadaire', 'illimité',
          'autant que vous voulez',
        ]) {
          expect(claims.contains(banned), isFalse,
              reason: '$locale still offers "$banned"');
        }
        // …and the denial really is there, in this language.
        expect(flow.length, greaterThan(claims.length),
            reason: '$locale never says the purchase is one-time');
      }
    });

    test('the one-time purchase promise is made, in all three languages', () {
      // en: "One-time purchase. No subscription. Your Spaces never expire."
      final en = pwaL10nFor(const Locale('en'));
      expect(en.paywallFreeUsedTitle, 'Get more Spaces');
      expect(en.paywallFreeUsedBody, contains('One-time purchase'));
      expect(en.paywallFreeUsedBody, contains('No subscription'));
      expect(en.paywallFreeUsedBody, contains('never expire'));

      final fr = pwaL10nFor(const Locale('fr'));
      expect(fr.paywallFreeUsedTitle, 'Obtenir plus de Spaces');
      expect(fr.paywallFreeUsedBody, contains('Paiement unique'));
      expect(fr.paywallFreeUsedBody, contains('Sans abonnement'));

      final km = pwaL10nFor(const Locale('km'));
      expect(km.paywallFreeUsedTitle.trim(), isNotEmpty);
      expect(km.paywallFreeUsedBody.trim(), isNotEmpty);
      expect(km.paywallFreeUsedBody, isNot(equals(en.paywallFreeUsedBody)),
          reason: 'Khmer must be Khmer, not the English source');
    });

    test('the success line counts Spaces, it does not announce a plan', () {
      for (final locale in const [Locale('en'), Locale('km'), Locale('fr')]) {
        final body = pwaL10nFor(locale).payResultSuccessBody(10);
        expect(body, contains('10'), reason: '$locale');
        expect(body.toLowerCase(), isNot(contains('subscription')));
        expect(body.toLowerCase(), isNot(contains('abonnement')));
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('THE GUARDS  nothing else moved', () {
    test('PRICE-08 the anonymous-purchase refusal is untouched', () {
      final p = PwaPayment.parse(
          const {'ok': false, 'http_status': 403, 'error_code': 'ACCOUNT_REQUIRED'});
      expect(p.state, PwaPaymentState.accountRequired);
      expect(p.state, isNot(PwaPaymentState.failed));
    });

    test('PRICE-09/20 the payment vocabulary and states are unchanged', () {
      for (final (raw, want) in const [
        ('GRANTED', PwaPaymentState.granted),
        ('AWAITING_PAYMENT', PwaPaymentState.awaitingPayment),
        ('FAILED', PwaPaymentState.failed),
      ]) {
        expect(
            PwaPayment.parse({'ok': true, 'state': raw, 'tran_id': 'A0'}).state,
            want);
      }
      expect(pwaClassifyPaymentError('PAYMENT_PROVIDER_REFUSED'),
          PwaPaymentErrorClass.payment);
      expect(pwaClassifyPaymentError('ACCOUNT_REQUIRED'),
          PwaPaymentErrorClass.account);
    });

    test('PRICE-16 the free trial is untouched by pricing', () {
      final fresh = PwaEntitlement.parse(const {
        'can_generate': true,
        'free_credits': 3,
        'credits_available': 3,
        'trial_materialized': false,
        'products': <Object?>[],
      });
      expect(fresh.freeCredits, 3);
      expect(fresh.creditsAvailable, 3);
      expect(fresh.trialMaterialized, isFalse);
    });

    test('PRICE-17/18/19 this change touches only copy and formatting', () {
      // Asserted on what the diff CAN reach: no auth, generation, RevenueCat or
      // ABA file is named by the money helper or the strings that moved.
      final ent = _read('lib/features/pwa/billing/pwa_entitlement.dart');
      final money = ent.substring(
          ent.indexOf('String pwaMoney('), ent.indexOf('class PwaProduct {'));
      for (final forbidden in const [
        'payway', 'PayWay', 'revenuecat', 'RevenueCat', 'signIn', 'generate',
        'ledger', 'hash',
      ]) {
        expect(money.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('THE SCREEN  all four packs render', () {
    testWidgets('PRICE-11 four cards, right Spaces, right prices, right badges',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          pwaEntitlementProvider.overrideWith((ref) => _Frozen(_entitlement())),
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
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final l = pwaL10nFor(const Locale('en'));
      for (final (sku, credits, money) in const [
        ('pack_10', 10, r'$2.50'),
        ('pack_25', 25, r'$5'),
        ('pack_50', 50, r'$8'),
        ('pack_100', 100, r'$14'),
      ]) {
        expect(find.byKey(ValueKey('pwa-pack-$sku')), findsOneWidget,
            reason: sku);
        expect(find.text(l.paywallSpaces(credits)), findsWidgets, reason: sku);
        expect(find.text(money), findsWidgets, reason: sku);
      }
      expect(find.text(l.productBadge('popular')), findsOneWidget);
      expect(find.text(l.productBadge('best_value')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
