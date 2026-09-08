/// The payment surface. Renders a SERVER state — never an inference.
///
/// Where Ayden stops and ABA starts
/// --------------------------------
/// Here. This sheet's job is to name what is being bought, for how much, and to
/// hand the browser one link: PayWay's own checkout, on PayWay's own domain.
/// ABA renders the payment — their option chooser (cards, ABA Pay, KHQR), their
/// QR, their ABA Mobile handoff — because their integration guideline says the
/// payment screen is theirs, and because a checkout we drew would be a copy we
/// had to keep in step with theirs forever.
///
/// That is why there is no QR in the primary path any more. The earlier rail
/// issued a KHQR and this sheet rendered it; it worked, and it made Ayden the
/// checkout. A QR only appears now when the deployment deliberately pins
/// `abapay_khqr_deeplink`, and even then it is secondary to the link.
///
/// The link expires before the payment does
/// ----------------------------------------
/// Measured on the sandbox: a PayWay checkout token lives 180 seconds, on a
/// transaction whose own lifetime is thirty minutes. So a person who opens this
/// sheet, walks away, and returns to an F5 has a payment that is still perfectly
/// open and a link that is dead. [PwaPayment.needsFreshCheckout] is that case,
/// and it is rendered as "start again" — never as a failure, because nothing
/// failed.
///
/// What is NOT here
/// ----------------
/// No success path the browser can reach on its own. There is no timer that
/// concludes, no "I have paid" button that unlocks, no reading of the browser
/// regaining focus after ABA Mobile, and no interpretation of the URL PayWay
/// returned to. The only widget that says the payment succeeded — Ayden's own
/// result card, `pwa_payment_result.dart` — is behind
/// `PwaPaymentState.granted`, which the SERVER writes after PayWay's Check
/// Transaction and the Billing Engine's grant.
///
/// There is also no progress bar. A payment has no measurable progress — a
/// filling bar would be a fabricated number, and the states below say more.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_layout.dart';
import '../billing/pwa_entitlement.dart';
import '../billing/pwa_payment.dart';
import '../billing/pwa_payment_controller.dart';
import '../data/pwa_external_launcher.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_aba_marks.dart';
import 'pwa_payment_result.dart';
import 'pwa_theme.dart';
import 'pwa_widgets.dart' show pwaSerif;

/// How the payment sheet was left. Two outcomes, because they mean two
/// different things to the screen underneath: a paid attempt closes the
/// paywall behind it; anything else leaves it where it was.
enum PwaPaymentExit {
  /// Paid. The result card was acknowledged with Continue.
  paid,

  /// Not paid — closed, retried, or never concluded.
  none,
}

/// Open the payment surface for [product] and start the checkout.
///
/// Returns how it ended. A GRANTED payment closes the paywall behind it —
/// nobody should be left looking at a purchase screen for something they have
/// just bought — and [PwaPaymentExit.paid] is how it says so.
Future<PwaPaymentExit> showPwaPaymentSheetFor(
  BuildContext context,
  WidgetRef ref,
  PwaProduct product,
) async {
  ref.read(pwaPaymentProvider.notifier).start(product.sku);
  final exit = await showDialog<PwaPaymentExit>(
    context: context,
    // The Wallet stays on screen and stays polling; the payer must be able to
    // see the pack they chose behind this. A near-opaque scrim over a
    // full-height sheet was the rejected treatment — it read as a separate
    // screen wearing a sheet's clothes.
    barrierColor: Colors.black.withValues(alpha: 0.38),
    barrierDismissible: false,
    builder: (_) => _PaymentModalFrame(product: product),
  );
  return exit ?? PwaPaymentExit.none;
}

/// Show the outcome of a payment that is ALREADY in flight — the return from
/// PayWay's checkout.
///
/// It starts nothing. `showPwaPaymentSheetFor` opens by calling `start(sku)`,
/// which mints a new attempt; doing that on a return would create a second
/// order for a payment that has already been made. Here the controller has
/// been restored from the server and the sheet simply renders the state it is
/// in.
///
/// The product it needs for its header is PROJECTED from the payment itself —
/// the same sku, credit count and amount the server just reported — rather
/// than looked up in the catalogue, because the truth about what was bought is
/// the order, not a price list that may have changed since.
Future<PwaPaymentExit> showPwaPaymentReturn(
  BuildContext context,
  WidgetRef ref,
) async {
  final payment = ref.read(pwaPaymentProvider);
  final product = PwaProduct(
    sku: payment.sku,
    type: '',
    credits: payment.credits,
    priceUsd: payment.amount,
    currency: payment.currency,
    storeOnly: false,
    webEnabled: true,
  );
  final exit = await showDialog<PwaPaymentExit>(
    context: context,
    // The Wallet stays on screen and stays polling; the payer must be able to
    // see the pack they chose behind this. A near-opaque scrim over a
    // full-height sheet was the rejected treatment — it read as a separate
    // screen wearing a sheet's clothes.
    barrierColor: Colors.black.withValues(alpha: 0.38),
    // A VERDICT never traps the person: the failure card's one action is
    // "Try again", and someone who cancelled on purpose must be able to
    // return without paying — a tap outside, or Escape. While money is still
    // being confirmed the frame refuses to pop (see `_PaymentModalFrame`).
    barrierDismissible: true,
    builder: (_) => _PaymentModalFrame(product: product),
  );
  return exit ?? PwaPaymentExit.none;
}

/// Back-compat shim for callers that only need "did it end paid".
Future<bool> showPwaPaymentSheet(
  BuildContext context,
  WidgetRef ref,
  PwaProduct product,
) async =>
    (await showPwaPaymentSheetFor(context, ref, product)) !=
    PwaPaymentExit.none;

/// The dialog shell: a small white card, centred, sized by its content.
///
/// WHAT THIS REPLACED, AND WHY. The first pass put ABA's hosted checkout in a
/// near-full-height bottom sheet. Measured at 340 / 360 / 390 / 420 px iframe
/// widths on 2026-09-05, that page has no mobile breakpoint — it renders the
/// same ~1180 px desktop composition at every width, instruction column and
/// postal footer included — so the sheet had to be tall, and the result read as
/// a bank's web page bolted into the app rather than as the compact modal ABA
/// approved. It was rejected on sight, correctly.
///
/// This is the other half of the same decision: the payment is now composed
/// from the two official fields PayWay returns (`qr_string`, `abapay_deeplink`)
/// inside Ayden's own small card, so the card can be as small as its contents.
class _PaymentModalFrame extends ConsumerWidget {
  const _PaymentModalFrame({required this.product});

  final PwaProduct product;

  /// The card's ceiling. Wide enough for a scannable QR with margins, narrow
  /// enough that the Wallet is unmistakably still there around it.
  static const double maxWidth = 400;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pwaPaymentProvider.select((p) => p.state));
    final kind = pwaPaymentResultKindFor(state);
    // Ayden's RESULT surface is near-black, like the Wallet it concludes — from
    // the moment money is being confirmed through to the verdict, so the card
    // never flips from white to dark in front of the person. The white card is
    // the dormant server-side checkout's, and stays as it was.
    final dark = kind != null || pwaPaymentIsConfirming(state);
    final screen = MediaQuery.sizeOf(context);
    // 20 a side on a phone: a comfortable gutter that still reads as a card
    // over the Wallet rather than as a page. On a wide screen the ceiling
    // takes over.
    final width = (screen.width - 40).clamp(240.0, maxWidth).toDouble();
    final edge = kind != null
        ? pwaPaymentResultBorder(kind)
        : dark
            ? kPwaResultLine
            : Colors.transparent;
    return PopScope(
      // The confirming states cannot be dismissed from outside: the grant is
      // seconds away and the card is what tells the person it landed.
      canPop: kind != null,
      child: Dialog(
      backgroundColor: dark ? kPwaResultSurface : Colors.white,
      surfaceTintColor: dark ? kPwaResultSurface : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: dark ? BorderSide(color: edge) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          // Tall content (a QR plus a deeplink button) still has to fit a short
          // landscape phone, so the card scrolls inside itself rather than
          // overflowing.
          maxHeight: screen.height - 48,
        ),
        child: PwaPaymentSheet(product: product),
      ),
      ),
    );
  }
}

class PwaPaymentSheet extends ConsumerWidget {
  const PwaPaymentSheet({super.key, required this.product});

  final PwaProduct product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payment = ref.watch(pwaPaymentProvider);
    final form = pwaFormFactorForWidth(MediaQuery.sizeOf(context).width);
    final onPhone = form == PwaFormFactor.mobile;

    // A VERDICT. Ayden's own result card, and nothing of the checkout with it:
    // no price header, no method mark, no close glyph — one card, one action.
    if (pwaPaymentResultKindFor(payment.state) != null) {
      final notifier = ref.read(pwaPaymentProvider.notifier);
      return SingleChildScrollView(
        child: PwaPaymentResultCard(
          payment: payment,
          onContinue: () {
            notifier.reset();
            Navigator.of(context).pop(PwaPaymentExit.paid);
          },
          onRetry: () {
            // Close the verdict first, then start over beneath it: ABA's
            // checkout must present over the Wallet, not over this card.
            Navigator.of(context).pop(PwaPaymentExit.none);
            final sku = payment.sku.isNotEmpty ? payment.sku : product.sku;
            notifier.retry(sku);
          },
        ),
      );
    }

    // Money is being CONFIRMED: the same near-black surface as the verdict,
    // with no controls — the server settles this in seconds, and nothing a
    // person taps here can hurry it or take it back.
    final confirming = pwaPaymentIsConfirming(payment.state);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!confirming) ...[
              _Header(product: product, payment: payment),
              const SizedBox(height: PwaGap.md),
            ],
            _Body(payment: payment, onPhone: onPhone, onDark: confirming),
            if (!confirming) _Actions(product: product, payment: payment),
          ],
        ),
      ),
    );
  }
}

/// The one line that never changes while a person pays: what they are buying
/// and what it costs. Shown from the PRODUCT until the server echoes its own
/// figures, so the amount on screen is never a client's idea of the price.
class _Header extends StatelessWidget {
  const _Header({required this.product, required this.payment});

  final PwaProduct product;
  final PwaPayment payment;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final credits = payment.credits > 0 ? payment.credits : product.credits;
    final price = payment.amountLabel.isNotEmpty
        ? payment.amountLabel
        : product.priceLabel;
    // ABA merchant review (2026-09-08): "Please remove ABA KHQR on your
    // success screen header." This header exists only while a person is
    // PAYING; a verdict renders Ayden's result card instead, which carries no
    // payment-method branding at all.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const PwaAbaMethodMark(size: 26),
            const SizedBox(width: 8),
            // The method's own name, never translated.
            Expanded(
              child: Text('ABA KHQR',
                  style: pwaSans(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            // Always reachable, in every state. A payment card with no way out
            // is the one thing worse than a payment card that is too big.
            IconButton(
              key: const ValueKey('pwa-pay-close'),
              onPressed: () =>
                  Navigator.of(context).maybePop(PwaPaymentExit.none),
              icon: const Icon(Icons.close_rounded, size: 20),
              color: pwaMuted,
              splashRadius: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              tooltip: l.payClose,
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: pwaHairline),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l.paywallSpaces(credits),
                style: pwaSans(fontSize: 13.5, color: pwaMuted)),
            Text(price,
                style: pwaSans(fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(
      {required this.payment, required this.onPhone, this.onDark = false});

  final PwaPayment payment;
  final bool onPhone;

  /// True on the near-black confirming surface, where ink-on-dark is invisible.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return switch (payment.state) {
      PwaPaymentState.idle ||
      PwaPaymentState.starting ||
      PwaPaymentState.created =>
        _Working(label: l.payPreparing),
      PwaPaymentState.awaitingPayment => _Payable(
          payment: payment,
          onPhone: onPhone,
        ),
      PwaPaymentState.paidPendingVerification => _Working(
          label: l.payConfirmingTitle,
          body: l.payConfirmingBody,
          onDark: onDark,
        ),
      PwaPaymentState.verified => _Working(
          label: l.payActivatingTitle,
          body: l.payActivatingBody,
          onDark: onDark,
        ),
      // Verdicts never reach this switch: `PwaPaymentSheet` renders Ayden's
      // result card for them before building a body at all.
      PwaPaymentState.granted ||
      PwaPaymentState.expired ||
      PwaPaymentState.cancelled ||
      PwaPaymentState.failed =>
        const SizedBox.shrink(),
      PwaPaymentState.unreachable => _Outcome(
          icon: Icons.wifi_off_outlined,
          tone: pwaMuted,
          title: l.payUnreachableTitle,
          body: l.payUnreachableBody,
        ),
      PwaPaymentState.unavailable => _Outcome(
          icon: Icons.lock_clock_outlined,
          tone: pwaMuted,
          title: l.paywallUnavailableTitle,
          body: l.paywallUnavailableBody,
        ),
    };
  }
}

/// Something is happening on a server we cannot hurry.
///
/// A spinner and a sentence, deliberately: no percentage, because there is no
/// quantity to report, and a bar that filled itself would be a lie told with
/// animation.
class _Working extends StatelessWidget {
  const _Working({required this.label, this.body = '', this.onDark = false});

  final String label;
  final String body;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: PwaGap.xl),
        child: Column(
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2, color: pwaGold),
            ),
            const SizedBox(height: PwaGap.md),
            Text(label,
                textAlign: TextAlign.center,
                style: pwaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: onDark ? kPwaResultText : pwaInk)),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(body,
                  textAlign: TextAlign.center,
                  style: pwaSans(
                      fontSize: 13,
                      color: onDark ? kPwaResultMuted : pwaMuted,
                      height: 1.5)),
            ],
          ],
        ),
      );
}

/// The live payment: ABA's KHQR, ABA's deeplink, and a poll that decides.
///
/// COMPOSED, NOT EMBEDDED. ABA's hosted checkout was measured at 340 / 360 /
/// 390 / 420 px iframe widths on 2026-09-05 and has no mobile breakpoint: the
/// same ~1180 px desktop page at every width. It cannot be the compact modal
/// ABA approved without scaling or cropping their page, which is not ours to
/// do. So this shows the two official fields PayWay returns instead — the exact
/// `qr_string`, rendered to pixels by the server, and the exact
/// `abapay_deeplink` — in a card small enough to sit over the Wallet.
class _Payable extends StatelessWidget {
  const _Payable({required this.payment, required this.onPhone});

  final PwaPayment payment;
  final bool onPhone;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;

    // The link has aged out. The PAYMENT has not — so this is an invitation to
    // start again, not an error, and it must not read like one.
    if (payment.needsFreshCheckout) {
      return _Outcome(
        icon: Icons.link_off_outlined,
        tone: pwaMuted,
        title: l.payLinkExpiredTitle,
        body: l.payLinkExpiredBody,
      );
    }

    // THE ACTIVE PATH. ABA's own plugin is presenting the checkout in its own
    // popup, above this card. What belongs here is the status of the payment
    // and the way to end it — not a QR, not a deeplink, not instructions: all
    // of those are ABA's, inside the popup, and a second copy underneath would
    // be the duplicate checkout ABA's review rejected.
    if (payment.checkoutMode == kPwaCheckoutModePlugin) {
      return Column(
        key: const ValueKey('pwa-pay-plugin-open'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: PwaGap.sm),
          Text(
            l.payPluginOpen,
            textAlign: TextAlign.center,
            style: pwaSans(fontSize: 13, color: pwaMuted, height: 1.45),
          ),
          const SizedBox(height: PwaGap.md),
          _Waiting(payment: payment),
        ],
      );
    }

    final hasQr = payment.qrImage.isNotEmpty || payment.qrString.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: PwaGap.sm),
        if (hasQr) ...[
          _QrPanel(payment: payment),
          const SizedBox(height: PwaGap.md),
          Text(
            l.payScanBody,
            textAlign: TextAlign.center,
            style: pwaSans(fontSize: 12.5, color: pwaMuted, height: 1.4),
          ),
          if (payment.deeplink.isNotEmpty) ...[
            const SizedBox(height: PwaGap.md),
            _OpenAbaMobileButton(url: payment.deeplink),
          ],
        ] else
          // No QR on this rail — the older `abapay_khqr` shape returns only a
          // checkout URL. Not a dead end and not a fabricated QR: the official
          // page, in a new tab, so the Wallet and its poll survive.
          _OpenCheckoutButton(url: payment.checkoutUrl),
        const SizedBox(height: PwaGap.md),
        _Waiting(payment: payment),
      ],
    );
  }
}

/// ABA Mobile, opened with ABA's own link.
///
/// The URL is PayWay's `abapay_deeplink`, verbatim — never assembled here. It
/// goes through `open` rather than `openNewTab` because a custom scheme in a
/// new tab strands an empty tab on every mobile browser, and because the QR is
/// still on screen underneath if the OS does nothing.
///
/// Tapping it concludes NOTHING. The poll that is already running is what will
/// find out whether money moved.
class _OpenAbaMobileButton extends ConsumerWidget {
  const _OpenAbaMobileButton({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    return OutlinedButton(
      key: const ValueKey('pwa-pay-open-aba-mobile'),
      onPressed: url.isEmpty
          ? null
          : () => ref.read(pwaExternalLauncherProvider).open(url),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        side: const BorderSide(color: pwaHairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PwaGap.radius),
        ),
      ),
      child: Text(l.payOpenAba,
          style: pwaSans(
              fontSize: 14, fontWeight: FontWeight.w600, color: pwaInk)),
    );
  }
}

/// The fallback when PayWay returned no QR: ABA's own page, in a NEW tab.
///
/// A new tab and not this one — same-tab navigation unloads the Flutter app and
/// takes the Wallet and the poll with it.
class _OpenCheckoutButton extends ConsumerWidget {
  const _OpenCheckoutButton({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    return FilledButton.icon(
      key: const ValueKey('pwa-pay-open-checkout'),
      onPressed: url.isEmpty
          ? null
          : () => ref.read(pwaExternalLauncherProvider).openNewTab(url),
      icon: const Icon(Icons.open_in_new_rounded, size: 18),
      label: Text(l.payContinueToAba,
          style: pwaSans(
              fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
      style: FilledButton.styleFrom(
        backgroundColor: pwaInk,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PwaGap.radius),
        ),
      ),
    );
  }
}

/// ABA's payload, as pixels.
///
/// The image is rendered BY THE SERVER from the exact `qr_string` PayWay
/// returned (`backend/pwa_qr.py`), because ABA hands the payment back as a
/// string and never as an image on this rail. Nothing here parses, rebuilds or
/// decorates it: no logo in the middle, no rounded modules, no colour. If the
/// image is missing the payload itself is shown rather than a placeholder that
/// pretends to be a code.
class _QrPanel extends StatelessWidget {
  const _QrPanel({required this.payment});

  final PwaPayment payment;

  @override
  Widget build(BuildContext context) {
    final bytes = _decode(payment.qrImage);
    return Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(PwaGap.radius),
          border: Border.all(color: pwaHairline),
        ),
        child: bytes == null
            // PayWay answered without an image. The payload is still valid, so
            // the person is not stuck — but we do not pretend to show a code.
            ? SizedBox(
                width: 220,
                child: SelectableText(
                  payment.qrString,
                  textAlign: TextAlign.center,
                  style: pwaSans(fontSize: 11, color: pwaInk),
                ),
              )
            : Image.memory(
                bytes,
                width: 220,
                height: 220,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => SizedBox(
                  width: 220,
                  child: SelectableText(payment.qrString,
                      textAlign: TextAlign.center,
                      style: pwaSans(fontSize: 11, color: pwaInk)),
                ),
              ),
      ),
    );
  }

  /// Tolerant of both a bare base64 payload and a `data:` URL, because the two
  /// are indistinguishable to a caller and only one of them decodes.
  static Uint8List? _decode(String raw) {
    if (raw.isEmpty) return null;
    final payload = raw.contains(',') ? raw.split(',').last : raw;
    try {
      return base64Decode(payload.trim());
    } catch (_) {
      return null;
    }
  }
}

/// "We are waiting", with the QR's own deadline as information only.
///
/// Stateless, and no ticker: the countdown refreshes when a poll returns, which
/// is the only moment anything real can have changed. A ticking second-hand
/// would suggest the browser knows something between polls. It does not.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.payment});

  final PwaPayment payment;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final left = payment.secondsRemaining();
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: pwaGold),
            ),
            const SizedBox(width: 10),
            Text(l.payWaiting,
                style: pwaSans(fontSize: 13, color: pwaMuted)),
          ],
        ),
        if (left != null) ...[
          const SizedBox(height: 6),
          Text(l.payExpiresIn(_mmss(left)),
              style: pwaSans(fontSize: 12, color: pwaFaint)),
        ],
        const SizedBox(height: PwaGap.sm),
        Text(l.paySafeNote,
            textAlign: TextAlign.center,
            style: pwaSans(fontSize: 11, color: pwaFaint)),
      ],
    );
  }

  static String _mmss(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: PwaGap.lg),
        child: Column(
          children: [
            Icon(icon, size: 40, color: tone),
            const SizedBox(height: PwaGap.md),
            Text(title,
                textAlign: TextAlign.center,
                style: pwaSerif(fontSize: 20, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: pwaSans(fontSize: 13, color: pwaMuted, height: 1.55)),
          ],
        ),
      );
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.product, required this.payment});

  final PwaProduct product;
  final PwaPayment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    final notifier = ref.read(pwaPaymentProvider.notifier);

    return Column(
      children: [
        if (payment.canRetry)
          OutlinedButton(
            onPressed: () => notifier.retry(product.sku),
            style: OutlinedButton.styleFrom(
              foregroundColor: pwaInk,
              side: const BorderSide(color: pwaInk),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PwaGap.radius),
              ),
            ),
            child: Text(l.payRetry,
                style: pwaSans(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        TextButton(
          onPressed: () async {
            // Cancel goes through the SERVER, which verifies before it accepts:
            // a payment that landed a second ago is granted rather than thrown
            // away by a tap.
            await notifier.cancel();
            if (!context.mounted) return;
            final granted =
                ref.read(pwaPaymentProvider).state == PwaPaymentState.granted;
            notifier.reset();
            Navigator.of(context)
                .pop(granted ? PwaPaymentExit.paid : PwaPaymentExit.none);
          },
          child: Text(
            payment.isTerminal ? l.paywallClose : l.payCancel,
            style: pwaSans(fontSize: 13, color: pwaMuted),
          ),
        ),
      ],
    );
  }
}
