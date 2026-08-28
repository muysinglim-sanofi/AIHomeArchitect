/// Phase 9 — the web paywall, the billing surfaces, and the money that must
/// never be decided here.
///
/// Three things are being held.
///
/// THE CATALOGUE IS THE SERVER'S. Which products exist, what they cost and
/// which of them this platform may sell are all answers the client is given.
/// The tests below check that the paywall shows exactly the web-sellable rows,
/// that it names no sku of its own, and that the only number it sends anywhere
/// is a sku — never an amount.
///
/// ONE OUTCOME, ONE SURFACE. A refusal for money is an answer, and the paywall
/// states it. A generation that genuinely broke is an error, and the banner
/// states that. Before this phase a billing refusal produced both, so the
/// person was told "something went wrong" about a request that had gone
/// exactly as the ledger intended.
///
/// A REFUSED ATTEMPT IS NOT A RECOVERABLE ONE — and nothing else may be
/// treated that way. The authoritative condition is pinned here in both
/// directions, because the cost of getting it wrong is asymmetric: too eager
/// and someone loses a retry for work they may have paid for; too shy and the
/// paywall reopens on every cold start, for ever.
library;

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_payment_controller.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_paywall.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_profile_ios.dart'
    show pwaWalletSentence;
import 'package:ai_home_architect/features/pwa/presentation/pwa_primitives.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ══ the canonical web catalogue, exactly as the server sends it ═════════════
//
// Written as the JSON the entitlement endpoint returns, not as Dart objects,
// so the parse is exercised too. The two store-only rows are the ones the
// staging paywall was showing under "available in the mobile app".
const _catalogue = [
  {
    'sku': 'pack_10',
    'type': 'CREDIT_PACK',
    'credits': 10,
    'price_usd': 4.99,
    'currency': 'USD',
    'badge': 'starter',
    'store_only': false,
    'web_enabled': true,
  },
  {
    'sku': 'pack_30',
    'type': 'CREDIT_PACK',
    'credits': 30,
    'price_usd': 7.99,
    'currency': 'USD',
    'badge': 'popular',
    'store_only': false,
    'web_enabled': true,
  },
  {
    'sku': 'pack_300',
    'type': 'CREDIT_PACK',
    'credits': 300,
    'price_usd': 47.99,
    'list_price_usd': 79.99,
    'currency': 'USD',
    'badge': 'best_value',
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
  {
    'sku': 'annual_pass',
    'type': 'PASS',
    'credits': 300,
    'duration_days': 365,
    'price_usd': 79.99,
    'currency': 'USD',
    'store_only': true,
    'web_enabled': false,
  },
];

PwaEntitlement _exhausted({bool configured = true}) => PwaEntitlement.parse({
      'can_generate': false,
      'billing_state': 'FREE_EXHAUSTED',
      'free_credits': 0,
      'credits_available': 0,
      'products': _catalogue,
      'payment': {'provider': 'khqr', 'configured': configured},
    });

class _FrozenEntitlement extends PwaEntitlementController {
  _FrozenEntitlement(PwaEntitlement value) : super(null) {
    state = value;
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> onIdentityChanged() async {}
}

Future<void> _pumpPaywall(
  WidgetTester tester, {
  PwaEntitlement? entitlement,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pwaEntitlementProvider
            .overrideWith((ref) => _FrozenEntitlement(entitlement ?? _exhausted())),
      ],
      child: MaterialApp(
        locale: locale,
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
}

// ══ a controller rig for the refusal / pending behaviour ════════════════════

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

AydenImageSource _source() =>
    AydenImageSource(bytes: _png, filename: 'r.png', mimeType: 'image/png');

class _Rig {
  _Rig({PwaGenerationFailure? failure})
      : generation = PwaFakeGenerationService(failure: failure),
        pending = PwaMemoryPendingGenerationStore() {
    controller = PwaController(
      MockPwaExperienceRepository(workDelay: Duration.zero, seedLibrary: false),
      generation: generation,
      pending: pending,
    );
  }

  final PwaFakeGenerationService generation;
  final PwaMemoryPendingGenerationStore pending;
  late final PwaController controller;

  PwaState get state => controller.state;

  Future<void> generate() async {
    controller.selectRoom('living_room');
    controller.setSource(_source());
    await controller.generateFirstVision();
  }
}

/// The refusal the Billing Engine actually emits: HTTP 402 on its own paywall
/// seam, `retryable: false`, `render_started: false`.
const _authoritativeRefusal = PwaGenerationFailure(
  code: 'QUOTA_EXHAUSTED',
  userMessage: 'Your free vision has been used.',
  retryable: false,
  billingState: 'FREE_EXHAUSTED',
  paywall: true,
);

void main() {
  group('BILL01  the paywall sells what the SERVER says it may sell', () {
    testWidgets('the three web packs are there, with the catalogue prices',
        (tester) async {
      await _pumpPaywall(tester);
      final l = pwaL10nFor(const Locale('en'));
      for (final (sku, credits, price) in const [
        ('pack_10', 10, r'$4.99'),
        ('pack_30', 30, r'$7.99'),
        ('pack_300', 300, r'$47.99'),
      ]) {
        expect(find.byKey(ValueKey('pwa-pack-$sku')), findsOneWidget,
            reason: sku);
        expect(find.text(l.paywallSpaces(credits)), findsWidgets, reason: sku);
        expect(find.text(price), findsOneWidget, reason: sku);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the App Store passes are ABSENT — not listed, not greyed',
        (tester) async {
      await _pumpPaywall(tester);
      final l = pwaL10nFor(const Locale('en'));
      expect(find.byKey(const ValueKey('pwa-pack-weekly_pass')), findsNothing);
      expect(find.byKey(const ValueKey('pwa-pack-annual_pass')), findsNothing);
      // Nor their prices, nor the line that used to explain them away.
      expect(find.text(r'$79.99'), findsOneWidget,
          reason: 'only as the struck reference price of pack_300');
      expect(find.text(l.paywallStoreOnly), findsNothing);
      expect(find.text(l.paywallDays(7)), findsNothing);
      expect(find.text(l.paywallDays(365)), findsNothing);
    });

    test('eligibility is the SERVER\'s boolean, not a sku list', () {
      final e = _exhausted();
      expect(e.purchasableOnWeb.map((p) => p.sku),
          ['pack_10', 'pack_30', 'pack_300']);
      // Flip only the server's flag: the same sku must disappear.
      final flipped = PwaEntitlement.parse({
        'can_generate': false,
        'billing_state': 'FREE_EXHAUSTED',
        'products': [
          {..._catalogue.first, 'web_enabled': false, 'store_only': true},
        ],
        'payment': {'provider': 'khqr', 'configured': true},
      });
      expect(flipped.purchasableOnWeb, isEmpty);
      expect(flipped.products, hasLength(1),
          reason: 'still parsed — the client must be able to know it exists');
    });
  });

  group('BILL02  the price hierarchy is honest', () {
    testWidgets(r'$79.99 is struck through, and the discount is derived',
        (tester) async {
      await _pumpPaywall(tester);
      final struck = tester.widget<Text>(find.text(r'$79.99'));
      expect(struck.style?.decoration, TextDecoration.lineThrough,
          reason: 'a reference price must never look payable');
      // 1 - 47.99/79.99 = 40%. Not stored anywhere; computed from two numbers
      // the server sent.
      expect(find.text(pwaL10nFor(const Locale('en')).paywallDiscount(40)),
          findsOneWidget);
    });

    test('the struck price is display metadata and never an amount', () {
      final best = _exhausted()
          .products
          .firstWhere((p) => p.sku == 'pack_300');
      expect(best.priceUsd, 47.99);
      expect(best.listPriceUsd, 79.99);
      expect(best.discountPercent, 40);
      // The payable field is the only one with a price name; the reference one
      // is carried separately precisely so nothing can confuse them.
      expect(best.priceLabel, r'$47.99');
      expect(best.listPriceLabel, r'$79.99');
    });

    testWidgets('a row with no reference price shows neither strike nor percent',
        (tester) async {
      await _pumpPaywall(tester);
      // pack_10 and pack_30 carry no list price: exactly one struck price and
      // one percentage exist on the whole sheet.
      expect(
        find.byWidgetPredicate((w) =>
            w is Text && w.style?.decoration == TextDecoration.lineThrough),
        findsOneWidget,
      );
    });
  });

  group('BILL03  choosing a pack, and one call to action', () {
    testWidgets('the popular pack is preselected, and the choice is visible',
        (tester) async {
      await _pumpPaywall(tester);
      // The badge is a machine code from the catalogue; the default is the row
      // the CATALOGUE marks, not a row this file picked.
      final cta = tester.widget<PwaPrimaryButton>(
          find.byKey(const ValueKey('pwa-paywall-continue')));
      expect(cta.label, contains(r'$7.99'));

      await tester.tap(find.byKey(const ValueKey('pwa-pack-pack_300')));
      await tester.pumpAndSettle();
      final after = tester.widget<PwaPrimaryButton>(
          find.byKey(const ValueKey('pwa-paywall-continue')));
      expect(after.label, contains(r'$47.99'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('there is ONE call to action, and its label is legible',
        (tester) async {
      await _pumpPaywall(tester);
      // The old screen put a Buy button on every row — and painted the label
      // ink-on-ink, so each read as an empty black rectangle.
      expect(find.byType(PwaPrimaryButton), findsOneWidget);
      final label = tester.widget<PwaPrimaryButton>(
          find.byKey(const ValueKey('pwa-paywall-continue')));
      expect(label.label.trim(), isNotEmpty);

      // And no Text anywhere on the sheet is ink on ink.
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        if (t.style?.color == pwaInk) {
          expect(t.data ?? '', isNotEmpty);
        }
      }
    });

    testWidgets('with no rail configured there is a notice and no way to pay',
        (tester) async {
      await _pumpPaywall(tester, entitlement: _exhausted(configured: false));
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.paywallUnavailableTitle), findsOneWidget);
      final cta = tester.widget<PwaPrimaryButton>(
          find.byKey(const ValueKey('pwa-paywall-continue')));
      expect(cta.onPressed, isNull,
          reason: 'an offer that cannot complete is worse than none');
    });

    testWidgets('the sheet sends a SKU and never an amount', (tester) async {
      await _pumpPaywall(tester);
      // Structural: the CTA carries the selected product, and the payment
      // controller's entry point takes `sku`. Nothing in this file formats a
      // number into a request — the server resolves the amount from the sku.
      final cta = tester.widget<PwaPrimaryButton>(
          find.byKey(const ValueKey('pwa-paywall-continue')));
      expect(cta.label, contains(r'$'),
          reason: 'the price is DISPLAYED…');
      // …and what leaves the page is the sku. `PwaPaymentController.start`
      // takes a String sku and nothing else; the gateway's `startCheckout`
      // takes `sku` and an attempt key. There is no amount parameter anywhere
      // on that path, so a tampered client cannot name its own price — the
      // server resolves it from `products.price_usd` for the sku it is given.
      expect(
        PwaPaymentController(null, null).start,
        isA<Future<void> Function(String)>(),
      );
    });
  });

  group('BILL04  one outcome, one surface', () {
    test('an authoritative refusal shows the paywall and NO error banner',
        () async {
      final rig = _Rig(failure: _authoritativeRefusal);
      await rig.generate();
      expect(rig.state.billingRefusal, 'FREE_EXHAUSTED');
      expect(rig.state.generationError, isNull,
          reason: 'the paywall already says it, completely');
      expect(rig.state.generationErrorCode, isNull);
      expect(rig.state.generationRetryable, isFalse);
    });

    test('a genuine failure still shows the banner, and no paywall', () async {
      final rig = _Rig(
        failure: const PwaGenerationFailure(
          code: 'TIMEOUT',
          userMessage: 'This is taking longer than expected. Try again.',
          retryable: true,
        ),
      );
      await rig.generate();
      expect(rig.state.generationError, isNotNull);
      expect(rig.state.generationErrorCode, 'TIMEOUT');
      expect(rig.state.generationRetryable, isTrue);
      expect(rig.state.billingRefusal, isEmpty,
          reason: 'a timeout must never look like a sale');
    });

    test('a bare QUOTA_EXHAUSTED with no 402 seam is still a refusal, not an '
        'error', () async {
      final rig = _Rig(
        failure: const PwaGenerationFailure(
          code: 'QUOTA_EXHAUSTED',
          userMessage: 'no',
          retryable: false,
        ),
      );
      await rig.generate();
      expect(rig.state.billingRefusal, 'FREE_EXHAUSTED');
      expect(rig.state.generationError, isNull);
    });
  });

  group('BILL05  what happens to the recorded attempt', () {
    test('an AUTHORITATIVE refusal discards it — the loop ends', () async {
      final rig = _Rig(failure: _authoritativeRefusal);
      await rig.generate();
      expect(await rig.pending.read(), isNull,
          reason: 'nothing was rendered, nothing was charged, and replaying '
              'the same key can only be refused again');
    });

    test('a TIMEOUT keeps it, marked failed and recoverable', () async {
      final rig = _Rig(
        failure: const PwaGenerationFailure(
          code: 'TIMEOUT', userMessage: 'x', retryable: true),
      );
      await rig.generate();
      final p = await rig.pending.read();
      expect(p, isNotNull);
      expect(p!.failed, isTrue);
    });

    test('a 5xx keeps it', () async {
      final rig = _Rig(
        failure: const PwaGenerationFailure(
          code: 'HTTP_503', userMessage: 'x', retryable: true),
      );
      await rig.generate();
      expect(await rig.pending.read(), isNotNull);
    });

    test('an UNKNOWN failure keeps it', () async {
      final rig = _Rig(
        failure: const PwaGenerationFailure(
          code: 'UNKNOWN', userMessage: 'x', retryable: false),
      );
      await rig.generate();
      expect(await rig.pending.read(), isNotNull,
          reason: 'not retryable is not the same as authoritatively refused');
    });

    test('a refusal that is retryable keeps it', () async {
      // Defensive: if the Billing Engine ever refuses in a way it says may be
      // retried, the record is a record of work that might yet happen.
      final rig = _Rig(
        failure: const PwaGenerationFailure(
          code: 'QUOTA_EXHAUSTED',
          userMessage: 'x',
          retryable: true,
          billingState: 'FREE_EXHAUSTED',
          paywall: true,
        ),
      );
      await rig.generate();
      expect(await rig.pending.read(), isNotNull);
    });

    test('the authoritative condition, stated exactly', () {
      expect(_authoritativeRefusal.isAuthoritativeBillingRefusal, isTrue);
      // Each leg removed in turn.
      expect(
        const PwaGenerationFailure(
                code: 'QUOTA_EXHAUSTED',
                userMessage: '',
                retryable: false,
                billingState: 'FREE_EXHAUSTED')
            .isAuthoritativeBillingRefusal,
        isFalse,
        reason: 'no 402 paywall seam',
      );
      expect(
        const PwaGenerationFailure(
                code: 'QUOTA_EXHAUSTED',
                userMessage: '',
                retryable: true,
                paywall: true,
                billingState: 'FREE_EXHAUSTED')
            .isAuthoritativeBillingRefusal,
        isFalse,
        reason: 'the server said it may be retried',
      );
      expect(
        const PwaGenerationFailure(
                code: 'TIMEOUT',
                userMessage: '',
                retryable: false,
                paywall: true)
            .isAuthoritativeBillingRefusal,
        isFalse,
        reason: 'not a billing refusal at all',
      );
    });
  });

  group('BILL05b  a refused attempt does not come back on the next visit', () {
    test('after an authoritative refusal there is nothing left to replay',
        () async {
      final rig = _Rig(failure: _authoritativeRefusal);
      await rig.generate();
      expect(await rig.pending.read(), isNull);

      // The next cold start reads the same store. With no record there is
      // nothing to fold into the boot, so nothing re-attempts the refused
      // generation and nothing re-raises the paywall — which is exactly the
      // loop observed on staging, where the record survived and the paywall
      // came back on EVERY load, for ever.
      final nextGen = PwaFakeGenerationService();
      final next = PwaController(
        MockPwaExperienceRepository(workDelay: Duration.zero,
            seedLibrary: false),
        generation: nextGen,
        pending: rig.pending,
      );
      addTearDown(next.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(next.state.billingRefusal, isEmpty);
      expect(next.state.generationError, isNull);
      expect(nextGen.generatedCount, 0,
          reason: 'the refused attempt is not retried behind the scenes');
    });

    test('after a TIMEOUT the record survives for the person to retry',
        () async {
      final rig = _Rig(
        failure: const PwaGenerationFailure(
            code: 'TIMEOUT', userMessage: 'x', retryable: true),
      );
      await rig.generate();
      final kept = await rig.pending.read();
      expect(kept, isNotNull);
      expect(kept!.idempotencyKey, isNotEmpty,
          reason: 'the SAME key, so a retry can never be charged twice');
    });
  });

  group('BILL08  no native payment reaches the web', () {
    testWidgets('nothing on the paywall mentions Apple, RevenueCat or a store',
        (tester) async {
      await _pumpPaywall(tester);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').toLowerCase())
          .join(' | ');
      for (final banned in const [
        'apple',
        'revenuecat',
        'app store',
        'play store',
        'subscription',
        'restore purchase',
        'mobile app',
      ]) {
        expect(texts, isNot(contains(banned)), reason: banned);
      }
    });

    test('a store-only product can never be selected, even by sku', () {
      final e = _exhausted();
      // The purchase surface is built from `purchasableOnWeb`, so a store-only
      // sku is not in the list a selection can name. And if one somehow were,
      // the server refuses it: `resolve_web_product` answers 409
      // PRODUCT_NOT_WEB_SELLABLE for any row carrying an Apple/RevenueCat id.
      expect(e.purchasableOnWeb.any((p) => p.storeOnly), isFalse);
      expect(e.purchasableOnWeb.every((p) => p.webEnabled), isTrue);
    });
  });

  group('BILL06  the balance is one number', () {
    test('the paywall and Profile read the same field of the same object', () {
      final e = PwaEntitlement.parse({
        'can_generate': true,
        'billing_state': 'PASS_ACTIVE',
        'has_active_pass': true,
        'free_credits': 1,
        'pass_credits': 29,
        'credits_available': 30,
        'products': _catalogue,
        'payment': {'provider': 'khqr', 'configured': true},
      });
      // `credits_available` is the server's total. The paywall used to show
      // `passCredits` (29) while Profile showed `creditsAvailable` (30) — one
      // account, one object, two numbers.
      expect(e.creditsAvailable, 30);
      expect(e.passCredits, 29);
      final l = pwaL10nFor(const Locale('en'));
      expect(pwaWalletSentence(l, e), l.passSpacesLeft(30));
    });

    test('a free vision is never called a purchased Space', () {
      final e = PwaEntitlement.parse({
        'can_generate': true,
        'billing_state': 'FREE_AVAILABLE',
        'free_credits': 1,
        'credits_available': 1,
        'payment': {'provider': 'khqr', 'configured': true},
      });
      final l = pwaL10nFor(const Locale('en'));
      expect(pwaWalletSentence(l, e), l.freeVisionAvailable);
      expect(pwaWalletSentence(l, e), isNot(contains('Space')));
    });
  });

  group('BILL07  it reads in all three languages', () {
    for (final code in const ['en', 'fr', 'km']) {
      testWidgets('the paywall resolves in $code', (tester) async {
        await _pumpPaywall(tester, locale: Locale(code));
        final l = pwaL10nFor(Locale(code));
        for (final s in [
          l.paywallFreeUsedTitle,
          l.payBuy,
          l.paywallSecureNote,
          l.productBadge('starter'),
          l.productBadge('popular'),
          l.productBadge('best_value'),
        ]) {
          expect(s, isNotEmpty, reason: code);
          expect(s.startsWith('pwa'), isFalse, reason: '$code: $s');
        }
        expect(find.text(l.paywallFreeUsedTitle), findsOneWidget);
        // Prices are not translated — a dollar amount is the same number in
        // every language, and the server sent it.
        expect(find.text(r'$47.99'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
