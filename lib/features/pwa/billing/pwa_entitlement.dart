/// The BILLING STATE the PWA renders from. Read from the server, never counted
/// locally.
///
/// §9 of the brief is a rule about where truth lives: "Paywall must be driven by
/// structured Billing state, NOT local counters." A browser cannot know what a
/// free generation costs, whether a pass is still active, what a purchase
/// granted, or whether an earlier tab already spent the credit. The ledger knows
/// all four. So this file has no arithmetic in it — it is a parse of what
/// `GET /pwa/staging/entitlement` said, plus the small amount of naming needed
/// to make a screen out of it.
///
/// The states are exhaustive on purpose. Every one of them is something a real
/// person can be in, including the two that are easy to forget: we have not
/// asked yet ([PwaBillingState.loading]) and we asked and could not find out
/// ([PwaBillingState.billingError]). Collapsing either into "blocked" invents a
/// paywall for someone who has already paid; collapsing them into "allowed"
/// gives away renders. Both are separate states here so neither can happen by
/// accident.
library;

/// What the app knows about this person's right to generate.
enum PwaBillingState {
  /// No answer yet. Show the UI, disable nothing irreversibly, ask.
  loading,

  /// The free generation is available. D1: ONE, at full quality and full
  /// resolution, carrying the canonical watermark.
  freeAvailable,

  /// The free generation has been used and there is no pass. THE paywall state.
  freeExhausted,

  /// A measured pass is active with credits left. Generation is allowed and the
  /// output is clean.
  passActive,

  /// A pass exists but its credits are spent.
  passExhausted,

  /// The role says premium but no measured pass backs it (RC-PR3b: the role is
  /// features, the pass is the generation). The person must restore or buy —
  /// telling them "you have no credits" would be wrong, they may well have paid.
  passRequired,

  /// An entitlement that is not a purchase: admin, promo, comped. Allowed.
  entitled,

  /// We asked and could not get an answer. NOT a refusal and NOT permission.
  billingError,
}

/// A product as the canonical `products` table defines it. The client never
/// invents a price, a SKU or a credit count.
class PwaProduct {
  const PwaProduct({
    required this.sku,
    required this.type,
    required this.credits,
    required this.priceUsd,
    required this.currency,
    required this.storeOnly,
    required this.webEnabled,
    this.durationDays,
    this.listPriceUsd,
    this.badge = '',
  });

  final String sku;

  /// `pass` | `subscription` | whatever the catalogue defines. Not switched on
  /// for behaviour — only shown.
  final String type;

  /// How many generations this actually grants, straight from the row that the
  /// Billing Engine will use when granting.
  final int credits;
  final double? priceUsd;
  final String currency;
  final int? durationDays;

  /// True when the row exists to be sold in an APP STORE (it carries an Apple or
  /// RevenueCat product id). The Web cannot sell it. Surfaced rather than hidden
  /// so the paywall can be honest instead of implying a checkout that does not
  /// exist (§10: do not duplicate mobile products blindly as Web products).
  final bool storeOnly;

  /// True when this row is purchasable on the Web today.
  final bool webEnabled;

  /// The CROSSED-OUT reference price, when this product is being discounted.
  ///
  /// Display only, and deliberately a separate field from [priceUsd] rather
  /// than a second "price": nothing may ever charge it, and the server resolves
  /// the PayWay amount from the catalogue row's own `price_usd` without this
  /// payload being involved at all. Null when there is no promotion.
  final double? listPriceUsd;

  /// A MACHINE code for the marketing label — `starter`, `popular`,
  /// `best_value` — or empty. Translated by the client, exactly like
  /// `billing_state`: an English word stored in a database is an untranslated
  /// string in the one place no translator will look.
  final String badge;

  /// Whether this product is being shown at a discount.
  ///
  /// Both halves matter: a reference price that is not ABOVE the real one is
  /// not a discount, and rendering "0% OFF" beside two identical numbers would
  /// be worse than rendering nothing.
  bool get isDiscounted {
    final list = listPriceUsd;
    final now = priceUsd;
    return list != null && now != null && list > now;
  }

  /// The discount as a whole percentage, DERIVED rather than stored.
  ///
  /// A third stored number is a third thing that can drift out of step with the
  /// two beside it; computing it means "40% OFF" can never contradict \$79.99
  /// and \$47.99 sitting next to it. Zero when there is no discount.
  int get discountPercent {
    if (!isDiscounted) return 0;
    final list = listPriceUsd!;
    return ((1 - (priceUsd! / list)) * 100).round();
  }

  /// The reference price as a person reads it. Same currency rule as
  /// [priceLabel] — a price is a property of the product, not translated copy.
  String get listPriceLabel {
    final list = listPriceUsd;
    if (list == null) return '';
    final amount = list.toStringAsFixed(2);
    return currency == 'USD' ? '\$$amount' : '$amount $currency';
  }

  /// The price as a person reads it.
  ///
  /// It lives here rather than in the widget because a currency symbol is a
  /// property of the PRODUCT, not of the screen: the catalogue names the
  /// currency, and every surface that shows this product must show the same
  /// thing. Prices are not localised copy — a `$7.99` pass costs $7.99 in
  /// Khmer, French and English alike, and translating the number would be a
  /// pricing change disguised as a translation.
  String get priceLabel {
    final p = priceUsd;
    if (p == null) return '';
    final amount = p.toStringAsFixed(2);
    return currency == 'USD' ? '\$$amount' : '$amount $currency';
  }

  static PwaProduct? parse(Object? raw) {
    if (raw is! Map) return null;
    final sku = raw['sku'];
    if (sku is! String || sku.isEmpty) return null;
    return PwaProduct(
      sku: sku,
      type: (raw['type'] as String?) ?? '',
      credits: (raw['credits'] as num?)?.toInt() ?? 0,
      priceUsd: (raw['price_usd'] as num?)?.toDouble(),
      currency: (raw['currency'] as String?) ?? 'USD',
      durationDays: (raw['duration_days'] as num?)?.toInt(),
      storeOnly: raw['store_only'] == true,
      webEnabled: raw['web_enabled'] == true,
      listPriceUsd: (raw['list_price_usd'] as num?)?.toDouble(),
      badge: (raw['badge'] as String?) ?? '',
    );
  }
}

class PwaEntitlement {
  const PwaEntitlement({
    required this.state,
    this.canGenerate = false,
    this.accessSource = '',
    this.tier = '',
    this.freeCredits = 0,
    this.passCredits = 0,
    this.creditsAvailable = 0,
    this.hasActivePass = false,
    this.watermarked = true,
    this.products = const [],
    this.paymentProvider = 'none',
    this.paymentConfigured = false,
  });

  /// Before the first answer. Deliberately `canGenerate: false` — but the UI
  /// must branch on [isKnown], not on [canGenerate], so nobody is shown a
  /// paywall during a round trip.
  const PwaEntitlement.loading() : this(state: PwaBillingState.loading);

  /// We asked and could not find out. The generate button stays enabled: the
  /// SERVER refuses generations, so failing open here costs a 402 the user can
  /// read, while failing closed would lock out a paying customer over a dropped
  /// packet.
  const PwaEntitlement.unavailable()
      : this(state: PwaBillingState.billingError, canGenerate: true);

  final PwaBillingState state;
  final bool canGenerate;

  /// `pass` | `entitlement` | `free` — WHY, in the RC-PR3b vocabulary.
  final String accessSource;
  final String tier;
  final int freeCredits;
  final int passCredits;
  final int creditsAvailable;
  final bool hasActivePass;

  /// Whether the NEXT generation will carry the canonical watermark.
  final bool watermarked;

  final List<PwaProduct> products;

  /// Which payment adapter this deployment would use, and whether it can
  /// actually take money. Both come from the server (§11): the client must never
  /// assume ABA, or any provider, is wired.
  final String paymentProvider;
  final bool paymentConfigured;

  bool get isKnown => state != PwaBillingState.loading;

  /// Whether the paywall should be shown when someone tries to generate.
  bool get requiresPurchase =>
      state == PwaBillingState.freeExhausted ||
      state == PwaBillingState.passExhausted ||
      state == PwaBillingState.passRequired;

  /// Products the Web can actually sell right now — and, since Phase 9, the
  /// only ones the paywall shows.
  ///
  /// `webEnabled` is the SERVER's verdict (`khqr_enabled AND NOT store_only`),
  /// so no sku is named here and no marketing string is matched. The same rule
  /// is enforced again where it matters: `resolve_web_product` refuses a
  /// store-only sku with 409 PRODUCT_NOT_WEB_SELLABLE, so a client that showed
  /// one anyway could still never charge for it.
  ///
  /// There used to be a `productsForDisplay` beside this, which grouped rather
  /// than filtered and so put the two App Store passes at the bottom of the
  /// web purchase list under the line "available in the mobile app". Honest,
  /// and still an advertisement for a shop the reader is not standing in.
  List<PwaProduct> get purchasableOnWeb =>
      [for (final p in products) if (p.webEnabled) p];

  static PwaEntitlement parse(Map<String, Object?>? body) {
    if (body == null) return const PwaEntitlement.unavailable();
    final can = body['can_generate'] == true;
    final source = (body['access_source'] as String?) ?? '';
    final hasPass = body['has_active_pass'] == true;
    final serverState = ((body['billing_state'] as String?) ?? '').toUpperCase();

    // The server's refusal code wins when it sent one; otherwise the state is
    // derived from WHY access was granted. Never from a count — a positive
    // balance with an inactive pass is not the same permission as a free credit.
    final PwaBillingState state;
    if (!can) {
      state = switch (serverState) {
        'PASS_EXHAUSTED' => PwaBillingState.passExhausted,
        'PASS_REQUIRED' => PwaBillingState.passRequired,
        _ => PwaBillingState.freeExhausted,
      };
    } else if (hasPass || source == 'pass') {
      state = PwaBillingState.passActive;
    } else if (source == 'entitlement') {
      state = PwaBillingState.entitled;
    } else {
      state = PwaBillingState.freeAvailable;
    }

    final payment = body['payment'];
    return PwaEntitlement(
      state: state,
      canGenerate: can,
      accessSource: source,
      tier: (body['tier'] as String?) ?? '',
      freeCredits: (body['free_credits'] as num?)?.toInt() ?? 0,
      passCredits: (body['pass_credits'] as num?)?.toInt() ?? 0,
      creditsAvailable: (body['credits_available'] as num?)?.toInt() ?? 0,
      hasActivePass: hasPass,
      watermarked: body['watermarked'] != false,
      products: [
        for (final p in (body['products'] as List? ?? const []))
          ?PwaProduct.parse(p),
      ],
      paymentProvider:
          payment is Map ? (payment['provider'] as String?) ?? 'none' : 'none',
      paymentConfigured: payment is Map && payment['configured'] == true,
    );
  }

  /// The state a 402 from `/generate` implies, applied WITHOUT waiting for a
  /// re-read. The refusal is itself authoritative billing news — the server just
  /// told us it will not render — and showing the paywall a round trip later
  /// looks like a bug.
  PwaEntitlement afterRefusal(String billingState) => PwaEntitlement(
        state: switch (billingState.toUpperCase()) {
          'PASS_EXHAUSTED' => PwaBillingState.passExhausted,
          'PASS_REQUIRED' => PwaBillingState.passRequired,
          _ => PwaBillingState.freeExhausted,
        },
        canGenerate: false,
        accessSource: accessSource,
        tier: tier,
        freeCredits: 0,
        passCredits: passCredits,
        creditsAvailable: creditsAvailable,
        hasActivePass: hasActivePass,
        watermarked: watermarked,
        products: products,
        paymentProvider: paymentProvider,
        paymentConfigured: paymentConfigured,
      );
}
