/// The paywall. Renders a BILLING STATE — never a counter.
///
/// Every branch below comes from [PwaEntitlement], which is parsed from what the
/// server said. There is no `if (generationsUsed >= 1)` anywhere in this file,
/// and there cannot be: the browser is not told what a free generation costs,
/// and a second tab, a refund, a granted pass or a shared account would each
/// make a local count wrong in a different way.
///
/// The seven states it can be in are all real, including the two that are easy
/// to skip: we have not asked yet, and we asked and could not find out. Neither
/// shows a purchase.
///
/// Honesty about payment
/// ---------------------
/// Whether a purchase can be completed is a SERVER fact, read from
/// `payment.configured` on the entitlement, and this file renders whichever
/// answer it gets:
///
///   configured    the web-sellable products carry a Buy button that opens the
///                 KHQR payment sheet. The two subscription passes still do
///                 not: they carry app-store product ids, so they are marked
///                 mobile-only rather than presented as web merchandise (§10).
///   not           the "payments are not open yet" notice, and NO Buy button
///                 anywhere — an offer that cannot complete is worse than none.
///
/// The client never assumes either way. A browser build that believed ABA was
/// live while the backend had no merchant configuration would show a button
/// that dead-ends, and the whole point of putting the answer on the server is
/// that wiring a rail is a deployment, not a release.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/pwa_auth_controller.dart';
import '../auth/pwa_auth_service.dart';
import '../billing/pwa_entitlement.dart';
import '../billing/pwa_entitlement_controller.dart';
import '../billing/pwa_payment.dart';
import '../billing/pwa_payment_controller.dart';
import '../data/pwa_aba_plugin.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_account_sheet.dart';
import 'pwa_payment_sheet.dart';
import 'pwa_aba_marks.dart';
import 'pwa_theme.dart';
import 'pwa_type.dart'
    show kPwaKhmerFamilyName, kPwaPaywallDisplayFamily, kPwaPaywallScriptFamily;

/// Show the paywall for the state the BILLING ENGINE named.
///
/// [refusal] is the `billing_state` a 402 carried, when the paywall was opened
/// by a refusal rather than by a tap. It is applied to the entitlement before
/// the sheet builds, so the first frame already shows the right state.
// ── The native paywall's palette, read off the frozen iOS source ────────────
//
// `features/paywall/paywall_sheet.dart` is a 2 500-line native sheet that
// cannot be reused here: it is built around RevenueCat packages, an Apple
// subscription ladder (weekly / annual) and store-restore semantics, none of
// which exist on the web. What CAN be reused — and is, verbatim — is its
// visual language. Every constant below is copied from that file, not matched
// by eye.
const Color _pwBg = Color(0xFF0E0C09); // _paywallBg
const Color _pwGoldBright = Color(0xFFD6B25E); // _goldBright
const Color _pwGoldLight = Color(0xFFE7CB82); // _goldLight
const Color _pwChampagne = Color(0xFFFFF3DC); // _champagne
const Color _pwPlanMuted = Color(0xFFC8B99B); // _planMuted
const Color _pwTextDim = Color(0xFF8C857B); // _textDim
const Color _pwCardSoft = Color(0xFF15110D); // _paywallCardSoft
const Color _pwBorderSubtle = Color(0xFF2A241D); // _borderSubtle
const Color _pwInk = Color(0xFF120E08); // the CTA's ink

/// The gold CTA fill — iOS's exact three stops.
const LinearGradient _pwCtaGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFE2C06B), Color(0xFFC79B3A), Color(0xFFB8862C)],
);

/// Legible over artwork — iOS's headline shadows.
const List<Shadow> _pwHeadlineShadows = [
  Shadow(color: Color(0xB3000000), blurRadius: 12),
  Shadow(color: Color(0x66000000), blurRadius: 4),
];

Future<void> showPwaPaywall(
  BuildContext context,
  WidgetRef ref, {
  String refusal = '',
}) {
  if (refusal.isNotEmpty) {
    ref.read(pwaEntitlementProvider.notifier).applyRefusal(refusal);
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // The sheet paints its own cinematic ground edge to edge, so the route
    // must not put a surface behind it — and there is no rounded ivory cap:
    // iOS's paywall is a near-full-screen immersive surface, not a card.
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => const PwaPaywallSheet(),
  );
}

/// The cinematic ground: interior photograph, then three fixed overlays that
/// darken it into the warm dark interface. iOS layers exactly these three, in
/// this order, over an image occupying the top 72% of the sheet.
class _PwPaywallBackdrop extends StatelessWidget {
  const _PwPaywallBackdrop({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: _pwBg)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: height * 0.72,
            child: Image.asset(
              // iOS's own choice for this surface.
              'assets/cards/atmospheres/warm_modern.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, _, _) => const ColoredBox(color: _pwBg),
            ),
          ),
          // Smoky cinematic "dark glass" — iOS's seven stops.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.24, 0.42, 0.58, 0.74, 0.90, 1.0],
                    colors: [
                      Color(0x080E0C09),
                      Color(0x180E0C09),
                      Color(0x3D0E0C09),
                      Color(0x700E0C09),
                      Color(0xA80E0C09),
                      Color(0xD90E0C09),
                      Color(0xF20E0C09),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // A very subtle warm brown from the top, and gentle bottom depth.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.2,
                    stops: [0.0, 0.45, 1.0],
                    colors: [
                      Color(0x186B431F),
                      Color(0x00000000),
                      Color(0x660E0C09),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // The top film that lets the gold wordmark read.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    stops: [0.0, 0.25, 0.45],
                    colors: [
                      Color(0xB30B0B0B),
                      Color(0x4D0B0B0B),
                      Color(0x000B0B0B),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

class PwaPaywallSheet extends ConsumerStatefulWidget {
  const PwaPaywallSheet({super.key});

  @override
  ConsumerState<PwaPaywallSheet> createState() => _PwaPaywallSheetState();
}

class _PwaPaywallSheetState extends ConsumerState<PwaPaywallSheet> {
  /// The pack the person is about to buy. A SKU, never an amount: the price
  /// this screen shows is the catalogue's, and the price PayWay charges is
  /// resolved by the server from this sku alone.
  String? _sku;

  /// The pack a first look should land on. `popular` when the catalogue says
  /// so — the badge is a machine code from the products table, not a marketing
  /// word this file invented — otherwise the first row.
  PwaProduct? _defaultPack(List<PwaProduct> packs) {
    if (packs.isEmpty) return null;
    for (final p in packs) {
      if (p.badge == 'popular') return p;
    }
    return packs.first;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final e = ref.watch(pwaEntitlementProvider);
    final auth = ref.watch(pwaAuthProvider);

    // THE PLUGIN PATH HAS NO AYDEN CHECKOUT SURFACE.
    //
    // Found on a real phone: pressing Buy opened Ayden's own payment sheet
    // ("secure checkout is open… waiting for your payment… 29:49") and ABA's
    // bottom sheet then opened on top of it — two payment surfaces, one of
    // them ours, for a checkout ABA owns. When ABA's plugin presents the
    // checkout, the only thing behind it must be THIS Wallet.
    //
    // So on the plugin path Buy starts the payment and shows nothing. State
    // continues underneath — the order, the tran_id, the poll, Check
    // Transaction, the grant — and surfaces here as a line under the CTA, not
    // as a modal: "checking…" while a transaction is live, a short error when
    // it failed or was never created, nothing at all when it was cancelled.
    // Success is the one moment that earns a surface, and it is the existing
    // success card, shown by the payment-return watcher once the poll says
    // GRANTED. This sheet just gets out of its way.
    final plugin = ref.watch(pwaAbaPluginProvider);
    final usesPlugin = plugin != null && plugin.isSupported;
    final payment = ref.watch(pwaPaymentProvider);
    ref.listen<PwaPaymentState>(
      pwaPaymentProvider.select((p) => p.state),
      (_, next) {
        if (!usesPlugin || !mounted) return;
        if (next == PwaPaymentState.granted) {
          // Nobody should be left on a purchase screen for something they
          // have just bought. The success card is the watcher's.
          Navigator.of(context).maybePop();
        }
      },
    );
    // While a plugin payment is live, Buy is not a thing to press again.
    final paymentBusy = usesPlugin &&
        (payment.state == PwaPaymentState.starting ||
            payment.state == PwaPaymentState.created ||
            payment.isPolling);
    // iOS: `final sheetHeight = media.size.height * 0.94;` — the same
    // fraction, so the strip of the page left showing above the sheet is the
    // one the phone already shows.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.94;

    // ONLY what this platform can actually sell. The app-store passes are real
    // products in their own ecosystem and are not merchandise here: the row
    // that says "available in the mobile app" is an advertisement for a shop
    // the reader is not standing in. `webEnabled` is the SERVER's word for it
    // (`khqr_enabled AND NOT store_only`), so nothing here filters by sku.
    final packs = e.purchasableOnWeb;
    final selected = packs.isEmpty
        ? null
        : (packs.where((p) => p.sku == _sku).firstOrNull ?? _defaultPack(packs));

    final (title, body) = switch (e.state) {
      PwaBillingState.loading => (l.paywallTitle, l.paywallLoading),
      PwaBillingState.billingError => (l.paywallErrorTitle, l.paywallErrorBody),
      PwaBillingState.passActive => (l.paywallActiveTitle, l.paywallActiveBody),
      PwaBillingState.entitled => (l.paywallActiveTitle, l.paywallActiveBody),
      // The balance the person actually has — the same figure Profile shows.
      // This used to say "1 free vision" to someone holding three hundred.
      PwaBillingState.freeAvailable => (
          l.paywallTitle,
          e.creditsAvailable > 1
              ? l.passSpacesLeft(e.creditsAvailable)
              : l.freeVisionAvailable
        ),
      PwaBillingState.passExhausted => (
          l.paywallPassExhaustedTitle,
          l.paywallPassExhaustedBody
        ),
      PwaBillingState.passRequired => (
          l.paywallPassRequiredTitle,
          l.paywallPassRequiredBody
        ),
      PwaBillingState.freeExhausted => (
          l.paywallFreeUsedTitle,
          l.paywallFreeUsedBody
        ),
    };

    // WHAT MAY BE BOUGHT, and when it is shown.
    //
    // The catalogue used to appear only behind `requiresPurchase` — the three
    // refused states. That made this sheet, opened from Profile by a person
    // holding a balance, a 92%-tall dark surface carrying a title, one line and
    // "Not now": the "malformed paywall with a large empty region" the phone
    // review reported. iOS never has that shape because its sheet always lays
    // out its passes; here the passes are the packs, and they are on offer
    // whenever the server lists one — a person with Spaces may simply want
    // more. Nothing about GATING moves: `requiresPurchase` still decides when
    // generation opens this sheet; this only decides what the sheet contains.
    final catalogueOpen = e.state != PwaBillingState.loading &&
        e.state != PwaBillingState.billingError &&
        packs.isNotEmpty;

    return SizedBox(
      height: maxHeight,
      child: Stack(
        children: [
          _PwPaywallBackdrop(height: maxHeight),
          SafeArea(
        top: false,
        // The sheet is a FIXED height — iOS's `Container(height: sheetHeight)`
        // — so its content must be laid out against that height, not against
        // its own length. A bare `SingleChildScrollView` sized the column to
        // its content and left the remainder of the sheet as unexplained dark.
        //
        // The column is therefore given the sheet's height as a MINIMUM and
        // split in two groups laid out `spaceBetween`: the headline group
        // stays at the top, the catalogue-and-footer group sits on the bottom
        // edge, and any slack falls between them — over the photograph, where
        // iOS's own 43%-of-screen hero gap is. Content longer than the sheet
        // scrolls, because the maximum is still unbounded. (A Spacer inside
        // `SliverFillRemaining` does the same on paper, but sizes the column
        // from intrinsic heights, and the pack cards' intrinsics run short by
        // a few pixels — measured: an 18 px overflow. `spaceBetween` uses the
        // laid-out sizes, so it cannot.)
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                // The brand, on the film that exists to let it read. iOS pins
                // the same asset at the top of its own paywall.
                Center(
                  child: Opacity(
                    opacity: 0.90,
                    child: Image.asset(
                      'assets/branding/ayden_logo_mixed.png',
                      width: 128,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Text(
                        'AYDEN STUDIO',
                        style: pwaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _pwGoldBright,
                            letterSpacing: 2.4),
                      ),
                    ),
                  ),
                ),
                // Enough of the photograph shows between the wordmark and the
                // headline for the surface to read as a room, not a panel —
                // and no more: measured on a 390×844 phone, this is what keeps
                // the gold CTA on the FIRST screen. A paywall whose only
                // action needs a scroll is a paywall that reads as a poster.
                // Re-measured when the headline became three lines.
                const SizedBox(height: 16),
                // EDITORIAL, over the artwork — iOS's own three lines, in
                // iOS's own two faces. See `PwaPaywallHeadline`.
                const PwaPaywallHeadline(),
                const SizedBox(height: 10),
                // Where iOS puts its marketing subheadline, the web puts the
                // reason this sheet opened. `pwSubheadline` is a promise; the
                // billing state is a FACT, and a person who has just been
                // stopped is owed the fact — first the four words that say
                // what happened, then the sentence that says what to do about
                // it. iOS's subheadline metrics for the first, a step down for
                // the second.
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            textAlign: TextAlign.center,
                            style: pwaSans(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFE9DDC7),
                                    height: 1.32)
                                .copyWith(shadows: const [
                              Shadow(color: Color(0x99000000), blurRadius: 8),
                            ])),
                        const SizedBox(height: 4),
                        Text(body,
                            textAlign: TextAlign.center,
                            style: pwaSans(
                                    fontSize: 13,
                                    color: _pwPlanMuted,
                                    height: 1.35)
                                .copyWith(shadows: const [
                              Shadow(color: Color(0x99000000), blurRadius: 8),
                            ])),
                      ],
                    ),
                  ),
                ),

                  ],
                ),
                // Slack lands between the two groups — over the photograph,
                // never under the footer.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                if (e.state == PwaBillingState.loading) ...[
                  const SizedBox(height: PwaGap.xl),
                  const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: pwaGold),
                    ),
                  ),
                  const SizedBox(height: PwaGap.xl),
                ] else ...[
                  // A balance is shown as a fact, not a pitch — and it is the
                  // SAME number Profile shows. `creditsAvailable` is the
                  // server's `credits_available`, free bucket plus pass bucket;
                  // this used to render `passCredits` alone, so a person with
                  // both read one figure here and a larger one on Profile for
                  // the same account, from the same object.
                  if (e.hasActivePass && e.creditsAvailable > 0) ...[
                    const SizedBox(height: PwaGap.md),
                    _Badge(l.paywallSpaces(e.creditsAvailable)),
                  ],

                  if (e.requiresPurchase) ...[
                    const SizedBox(height: PwaGap.lg),
                    _PaymentNotice(entitlement: e),
                  ],
                  if (catalogueOpen) ...[
                    if (!e.requiresPurchase) const SizedBox(height: PwaGap.lg),
                    ...[
                      const SizedBox(height: PwaGap.md),
                      for (final p in packs)
                        _PackCard(
                          key: ValueKey('pwa-pack-${p.sku}'),
                          product: p,
                          selected: p.sku == selected?.sku,
                          // Choosing is free. Nothing is ordered, nothing is
                          // charged, and no request leaves the page until the
                          // one CTA below is pressed.
                          onTap: () => setState(() => _sku = p.sku),
                        ),
                      const SizedBox(height: PwaGap.md),
                      // ABA's merchant review asks that the payment method be
                      // named on the Wallet itself, before the CTA — so nobody
                      // reaches ABA's page wondering what they are about to
                      // pay with. There is exactly one method, and the
                      // deployment enforces that at the source
                      // (`PAYWAY_PAYMENT_OPTION=abapay_khqr`), not by hiding
                      // choices in this UI.
                      const PwaAbaMethodRow(tone: PwaMarkTone.dark),
                      const SizedBox(height: PwaGap.md),
                      // ONE call to action, for the pack that is selected. The
                      // old screen put a Buy button on every row, which asked a
                      // person to compare three prices and three buttons at
                      // once; and its label was painted ink-on-ink, so all
                      // three read as empty black rectangles.
                      PwaGoldCta(
                        key: const ValueKey('pwa-paywall-continue'),
                        label: selected == null
                            ? l.payBuy
                            : '${l.payBuy} · ${selected.priceLabel}',
                        onPressed: (!e.paymentConfigured ||
                                selected == null ||
                                paymentBusy)
                            ? null
                            : usesPlugin
                                // PLUGIN PATH: start, and open nothing. The
                                // controller hands the signed fields to ABA's
                                // plugin, which presents the checkout over
                                // this Wallet. No PwaPaymentSheet is mounted.
                                ? () => ref
                                    .read(pwaPaymentProvider.notifier)
                                    .start(selected.sku)
                                : () async {
                                    final granted = await showPwaPaymentSheet(
                                        context, ref, selected);
                                    // A completed purchase closes the paywall
                                    // behind the sheet: leaving someone on a
                                    // purchase screen for something they have
                                    // just bought reads as a bug.
                                    if (granted && context.mounted) {
                                      Navigator.of(context).maybePop();
                                    }
                                  },
                      ),
                      if (usesPlugin)
                        _PaymentInline(
                          payment: payment,
                          onCancel: () => ref
                              .read(pwaPaymentProvider.notifier)
                              .cancel(),
                        ),
                    ],
                  ],

                  const SizedBox(height: PwaGap.lg),

                  // Identity, offered here at the moment it means something —
                  // but NOT as a second purchase CTA. It used to be a full
                  // outlined button directly under Buy, which put two equal
                  // large actions on a screen that has exactly one thing to
                  // do. Both journeys are still reachable, as text, at the
                  // weight a secondary consideration deserves.
                  if (auth.stage != PwaAuthStage.identified)
                    _PwIdentityLine(
                      // The sheet owns the post-authentication hydration —
                      // entitlement included, which is what this screen cares
                      // about most.
                      onSave: () => showPwaAccountSheet(context),
                      onSignIn: () =>
                          showPwaAccountSheet(context, signIn: true),
                    )
                  else
                    Center(
                      child: TextButton(
                        onPressed: () => ref
                            .read(pwaEntitlementProvider.notifier)
                            .refresh(),
                        child: Text(l.paywallRestore,
                            style: pwaSans(
                                fontSize: 13, color: _pwPlanMuted)),
                      ),
                    ),

                  const SizedBox(height: PwaGap.xs),
                  Center(
                    child: TextButton(
                      key: const ValueKey('pwa-paywall-close'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(l.paywallClose,
                          style: pwaSans(fontSize: 13, color: _pwTextDim)),
                    ),
                  ),
                ],
                  ],
                ),
              ],
            ),
            ),
          ),
          ),
        ),
      ),
        ],
      ),
    );
  }
}

/// iOS's three-line headline, in iOS's two faces.
///
/// Mapped from `features/paywall/paywall_sheet.dart` line for line — the
/// strings are the shared dictionary's own `pwHeadlineLead/Trail/Accent`,
/// already approved in all three languages, so nothing here is new copy:
///
/// | line | string | face | size (<380 / ≥380) | weight | height | tracking |
/// |---|---|---|---|---|---|---|
/// | 1 | `pwHeadlineLead`   | Playfair Display | 30 / 32 | w500 | 0.95 | −0.5 |
/// | 2 | `pwHeadlineTrail`  | Playfair Display | 37 / 40 | w600 | 0.95 | −0.9 |
/// | 3 | `pwHeadlineAccent` | Great Vibes      | 29 / 32 | w400 | 0.82 | —    |
///
/// Lines 2 and 3 carry iOS's vertical nudges (−2 and −6) so the script sits
/// into the serif rather than under it. Both shadows are iOS's.
///
/// Line 3 is GOLD; the other two are champagne. Great Vibes appears here and
/// in no other place in the product.
///
/// Every chain still ends in the bundled Khmer family: neither Latin face has
/// Khmer glyphs, and Khmer must be right on the first frame, offline.
class PwaPaywallHeadline extends StatelessWidget {
  const PwaPaywallHeadline({super.key});

  static const List<String> _serifFallback = [
    kPwaPaywallDisplayFamily,
    'Georgia',
    'serif',
    kPwaKhmerFamilyName,
  ];
  static const List<String> _scriptFallback = [
    kPwaPaywallScriptFamily,
    'Georgia',
    'serif',
    kPwaKhmerFamilyName,
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final small = MediaQuery.sizeOf(context).width < 380;

    TextStyle serif(double size, FontWeight weight, double tracking) =>
        TextStyle(
          fontFamily: kPwaPaywallDisplayFamily,
          fontFamilyFallback: _serifFallback,
          color: _pwChampagne,
          fontSize: size,
          fontWeight: weight,
          height: 0.95,
          letterSpacing: tracking,
          shadows: _pwHeadlineShadows,
        );

    return Column(
      key: const ValueKey('pwa-paywall-headline'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.paywallHeadlineLead,
            textAlign: TextAlign.center,
            style: serif(small ? 30 : 32, FontWeight.w500, -0.5)),
        Transform.translate(
          offset: const Offset(0, -2),
          child: Text(l.paywallHeadlineTrail,
              textAlign: TextAlign.center,
              style: serif(small ? 37 : 40, FontWeight.w600, -0.9)),
        ),
        Transform.translate(
          offset: const Offset(0, -6),
          child: Text(
            l.paywallHeadlineAccent,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: kPwaPaywallScriptFamily,
              fontFamilyFallback: _scriptFallback,
              color: _pwGoldBright,
              fontSize: small ? 29 : 32,
              fontWeight: FontWeight.w400,
              height: 0.82,
              shadows: _pwHeadlineShadows,
            ),
          ),
        ),
      ],
    );
  }
}

/// The one call to action, in iOS's gold.
///
/// Its own widget rather than `PwaPrimaryButton` because that button is the
/// product's INK pill — correct on every cream surface and wrong on this one.
/// Geometry, gradient, border, glow and label weight are the native button's.
class PwaGoldCta extends StatelessWidget {
  const PwaGoldCta({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 150),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _pwCtaGradient,
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: _pwGoldLight.withValues(alpha: 0.55)),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _pwGoldBright.withValues(alpha: 0.22),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.workspace_premium_rounded,
                        color: _pwInk, size: 20),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Stated on the CHILD, because a DefaultTextStyle
                        // foreground loses to an explicit style — the bug that
                        // once rendered every Buy label ink-on-ink.
                        style: pwaSans(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: _pwInk,
                            letterSpacing: 0.2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: _pwInk, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Both identity journeys, as text, under the one action that matters.
///
/// Same two operations as everywhere else and the same hierarchy: attaching an
/// address to THIS guest keeps their work; signing in switches to an account
/// that already exists and carries nothing over. Neither competes with Buy.
class _PwIdentityLine extends StatelessWidget {
  const _PwIdentityLine({required this.onSave, required this.onSignIn});

  final VoidCallback onSave;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Column(
      children: [
        TextButton(
          key: const ValueKey('pwa-paywall-save-work'),
          onPressed: onSave,
          child: Text(l.accountTitle,
              style: pwaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: _pwChampagne)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(l.accountHaveOne,
                  textAlign: TextAlign.right,
                  style: pwaSans(fontSize: 12.5, color: _pwTextDim)),
            ),
            TextButton(
              key: const ValueKey('pwa-paywall-sign-in'),
              onPressed: onSignIn,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(l.accountSignInTitle,
                  style: pwaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _pwGoldBright)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Says plainly that no purchase can be completed here yet.
///
/// Shown whenever the provider is unconfigured, which is every deployment
/// today. It is the FIRST thing under the headline for a reason: a person who
/// cannot buy should learn that before they read prices.
class _PaymentNotice extends StatelessWidget {
  const _PaymentNotice({required this.entitlement});

  final PwaEntitlement entitlement;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    if (entitlement.paymentConfigured) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _pwCardSoft,
        borderRadius: BorderRadius.circular(PwaGap.radius),
        border: Border.all(color: _pwBorderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.paywallUnavailableTitle,
              style: pwaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _pwChampagne)),
          const SizedBox(height: 6),
          Text(l.paywallUnavailableBody,
              style: pwaSans(
                  fontSize: 13, color: _pwPlanMuted, height: 1.5)),
        ],
      ),
    );
  }
}

/// One pack, as a thing you can choose.
///
/// The old row was a read-only line with its own Buy button. This is a card:
/// the whole surface is the tap target, the selected one is stated in gold and
/// with a tick, and the price ladder reads top to bottom — badge, what you get,
/// what it costs, and (only when the catalogue says so) what it would otherwise
/// have cost.
///
/// The struck price and the percentage are DISPLAY, and they are kept visibly
/// subordinate to the payable one for that reason: `list_price_usd` lives in
/// `products.metadata`, the amount PayWay charges is resolved server-side from
/// `price_usd`, and this widget is not in that path.
class _PackCard extends StatelessWidget {
  const _PackCard({
    super.key,
    required this.product,
    required this.selected,
    required this.onTap,
  });

  final PwaProduct product;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    // Dark glass, exactly as iOS builds `_PlanCardV2`: a top-left→bottom-right
    // gradient that lifts when selected, a gold border that thickens, and a
    // gold glow underneath. 22 radius, 16 padding — the native numbers.
    return Padding(
      padding: const EdgeInsets.only(bottom: PwaGap.sm),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: selected
                    ? const [Color(0xFF1E170F), Color(0xFF0D0A07)]
                    : const [Color(0xFF15120E), Color(0xFF0B0907)],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? _pwGoldBright
                    : _pwGoldBright.withValues(alpha: 0.16),
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: _pwGoldBright.withValues(alpha: 0.22),
                        blurRadius: 22,
                        spreadRadius: 1,
                        offset: const Offset(0, 9),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.38),
                        blurRadius: 18,
                        offset: const Offset(0, 12),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Row(
              children: [
                _SelectionDot(selected: selected),
                const SizedBox(width: PwaGap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The marketing label, translated from a machine code.
                      if (product.badge.isNotEmpty) ...[
                        _BadgeChip(
                          label: l.productBadge(product.badge),
                          highlight: product.isDiscounted,
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(l.paywallSpaces(product.credits),
                          style: pwaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _pwChampagne)),
                      if (product.durationDays != null) ...[
                        const SizedBox(height: 2),
                        Text(l.paywallDays(product.durationDays!),
                            style: pwaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _pwPlanMuted)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: PwaGap.md),
                if (product.priceLabel.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Above the real one and struck through, so the number a
                      // person acts on is the one they will be charged.
                      if (product.isDiscounted) ...[
                        Text(product.listPriceLabel,
                            style: pwaSans(
                                    fontSize: 12, color: _pwTextDim)
                                .copyWith(
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: _pwTextDim)),
                        const SizedBox(height: 1),
                      ],
                      Text(product.priceLabel,
                          style: pwaSans(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              color: selected
                                  ? _pwGoldBright
                                  : _pwChampagne)),
                      if (product.isDiscounted) ...[
                        const SizedBox(height: 2),
                        Text(l.paywallDiscount(product.discountPercent),
                            style: pwaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _pwGoldBright)),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The selection mark — a gold ring, filled with a tick when chosen. Shape as
/// well as colour, so the choice survives a screenshot in greyscale and a
/// reader who does not see the gold.
class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? _pwGoldBright : Colors.transparent,
          border: Border.all(
            color: selected
                ? _pwGoldBright
                : _pwChampagne.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 14, color: _pwInk)
            : null,
      );
}

/// The marketing label on a product row — a translated word, never a code.
class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label, this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _pwGoldBright.withValues(alpha: highlight ? 0.24 : 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: pwaSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: highlight ? _pwGoldBright : _pwChampagne)),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _pwGoldBright.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: pwaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _pwGoldBright)),
        ),
      );
}

/// Payment STATE on the Wallet, as one quiet line under Buy — never a sheet.
///
/// The plugin owns the checkout surface. What Ayden owns is the state behind
/// it, and this is where that state shows: a spinner while the server prepares
/// or a live transaction is being checked, a sentence when it ended badly, and
/// nothing when there is nothing to say. It never counts down and never
/// promises a payment is "open": the popup says what is open, and Check
/// Transaction says what happened.
class _PaymentInline extends StatelessWidget {
  const _PaymentInline({required this.payment, required this.onCancel});

  final PwaPayment payment;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final quiet = pwaSans(fontSize: 12.5, color: _pwPlanMuted, height: 1.4);

    Widget spinnerRow(String text, {Widget? trailing}) => Row(
          key: const ValueKey('pwa-paywall-payment-inline'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                  strokeWidth: 1.6, color: _pwGoldBright),
            ),
            const SizedBox(width: 9),
            Flexible(child: Text(text, style: quiet)),
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
          ],
        );

    Widget errorLine(String text) => Padding(
          key: const ValueKey('pwa-paywall-payment-error'),
          padding: const EdgeInsets.only(top: PwaGap.sm),
          child: Text(text,
              textAlign: TextAlign.center,
              style: pwaSans(
                  fontSize: 12.5, color: const Color(0xFFE8A9A0), height: 1.4)),
        );

    final body = switch (payment.state) {
      PwaPaymentState.starting ||
      PwaPaymentState.created =>
        spinnerRow(l.payPreparing),
      // A live transaction, or one the server is verifying. The cancel is
      // the existing server-verified cancel: money that landed a second ago
      // still wins.
      PwaPaymentState.awaitingPayment => spinnerRow(
          l.payInlineChecking,
          trailing: TextButton(
            key: const ValueKey('pwa-paywall-payment-cancel'),
            onPressed: onCancel,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l.payInlineCancel,
                style: pwaSans(fontSize: 12.5, color: _pwGoldLight)),
          ),
        ),
      PwaPaymentState.paidPendingVerification ||
      PwaPaymentState.verified =>
        spinnerRow(l.payConfirmingTitle),
      // NOT_CREATED lands here: "could not start", and Buy is live again.
      PwaPaymentState.failed => errorLine(l.payFailedBody(
          payment.failureReason,
          newAttemptRequired: payment.newAttemptRequired)),
      PwaPaymentState.expired => errorLine(l.payExpiredTitle),
      PwaPaymentState.unreachable => errorLine(l.payUnreachableTitle),
      // Cancelled is a decision, not a problem: back to the Wallet, no line.
      PwaPaymentState.cancelled ||
      PwaPaymentState.granted ||
      PwaPaymentState.unavailable ||
      PwaPaymentState.idle =>
        null,
    };
    if (body == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: PwaGap.sm),
      child: body,
    );
  }
}
