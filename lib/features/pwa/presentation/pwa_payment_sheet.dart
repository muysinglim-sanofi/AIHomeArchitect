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
/// returned to. The only widget that says "you are all set" is behind
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
import 'pwa_theme.dart';
import 'pwa_widgets.dart' show pwaSerif;

/// How the payment sheet was left. Three outcomes, because they mean three
/// different things to the screen underneath.
enum PwaPaymentExit {
  /// Paid, and the person chose to go and use it.
  startDesigning,

  /// Paid, and the person chose to stay where they were.
  later,

  /// Not paid.
  none,
}

/// Open the payment surface for [product] and start the checkout.
///
/// Returns how it ended. A GRANTED payment closes the paywall behind it either
/// way — nobody should be left looking at a purchase screen for something they
/// have just bought — and [PwaPaymentExit.startDesigning] additionally says the
/// person asked to go and use it.
Future<PwaPaymentExit> showPwaPaymentSheetFor(
  BuildContext context,
  WidgetRef ref,
  PwaProduct product,
) async {
  ref.read(pwaPaymentProvider.notifier).start(product.sku);
  final exit = await showModalBottomSheet<PwaPaymentExit>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: pwaSurface,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => PwaPaymentSheet(product: product),
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

class PwaPaymentSheet extends ConsumerWidget {
  const PwaPaymentSheet({super.key, required this.product});

  final PwaProduct product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payment = ref.watch(pwaPaymentProvider);
    final form = pwaFormFactorForWidth(MediaQuery.sizeOf(context).width);
    final onPhone = form == PwaFormFactor.mobile;

    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.94),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Grabber(),
                const SizedBox(height: PwaGap.lg),
                _Header(product: product, payment: payment),
                const SizedBox(height: PwaGap.lg),
                _Body(payment: payment, onPhone: onPhone),
                const SizedBox(height: PwaGap.lg),
                _Actions(product: product, payment: payment),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: pwaHairline,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.payTitle,
            style: pwaSerif(fontSize: 24, fontWeight: FontWeight.w500)),
        const SizedBox(height: PwaGap.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l.paywallSpaces(credits),
                style: pwaSans(fontSize: 15, color: pwaMuted)),
            Text(price,
                style: pwaSans(fontSize: 17, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.payment, required this.onPhone});

  final PwaPayment payment;
  final bool onPhone;

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
        ),
      PwaPaymentState.verified => _Working(
          label: l.payActivatingTitle,
          body: l.payActivatingBody,
        ),
      PwaPaymentState.granted => _Outcome(
          icon: Icons.check_circle_outline,
          tone: pwaGold,
          title: l.payDoneTitle,
          body: l.payDoneBody(payment.credits),
        ),
      PwaPaymentState.expired => _Outcome(
          icon: Icons.hourglass_disabled_outlined,
          tone: pwaMuted,
          title: l.payExpiredTitle,
          body: l.payExpiredBody,
        ),
      PwaPaymentState.cancelled => _Outcome(
          icon: Icons.remove_circle_outline,
          tone: pwaMuted,
          title: l.payCancelledTitle,
          body: l.payCancelledBody,
        ),
      PwaPaymentState.failed => _Outcome(
          icon: Icons.error_outline,
          tone: pwaMuted,
          title: l.payFailedTitle,
          body: l.payFailedBody(payment.failureReason,
              newAttemptRequired: payment.newAttemptRequired),
        ),
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
  const _Working({required this.label, this.body = ''});

  final String label;
  final String body;

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
                style: pwaSans(fontSize: 15, fontWeight: FontWeight.w600)),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(body,
                  textAlign: TextAlign.center,
                  style: pwaSans(fontSize: 13, color: pwaMuted, height: 1.5)),
            ],
          ],
        ),
      );
}

/// The live payment: what is being bought, and the way to ABA's checkout.
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

    // Only when the deployment pinned `abapay_khqr_deeplink`. Normally empty —
    // ABA shows the QR on its own page, which is where it belongs.
    final hasQr = payment.qrImage.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No heading here: the sheet header already names the payment. A
        // second copy of the same sentence is noise on a screen whose whole
        // job is one clear action.
        Text(onPhone ? l.payHandoffBodyPhone : l.payHandoffBodyDesktop,
            style: pwaSans(fontSize: 13, color: pwaMuted, height: 1.5)),
        const SizedBox(height: PwaGap.lg),

        _ContinueToAbaButton(url: payment.checkoutUrl),

        if (hasQr) ...[
          const SizedBox(height: PwaGap.md),
          Center(
            child: Text(l.payOrScan,
                textAlign: TextAlign.center,
                style: pwaSans(fontSize: 12, color: pwaFaint)),
          ),
          const SizedBox(height: PwaGap.sm),
          _QrPanel(payment: payment),
        ],

        const SizedBox(height: PwaGap.md),
        _Waiting(payment: payment),
      ],
    );
  }
}

/// The one action on this sheet: go to ABA.
///
/// A NAVIGATION and nothing else. Tapping it writes no state, concludes
/// nothing, and starts no timer — the poll that is already running is what will
/// find out whether money moved, by asking the server, which asks PayWay.
class _ContinueToAbaButton extends ConsumerWidget {
  const _ContinueToAbaButton({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    return FilledButton.icon(
      onPressed: url.isEmpty
          ? null
          : () => ref.read(pwaExternalLauncherProvider).open(url),
      icon: const Icon(Icons.open_in_new_rounded, size: 18),
      label: Text(l.payContinueToAba,
          style: pwaSans(fontSize: 15, fontWeight: FontWeight.w600)),
      style: FilledButton.styleFrom(
        backgroundColor: pwaInk,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PwaGap.radius),
        ),
      ),
    );
  }
}

/// PayWay's own QR artwork, decoded from the base64 PNG it returned.
///
/// Rendered from `qr_image` rather than drawn from `qr_string` on purpose: the
/// image is what the gateway certified, it carries the KHQR branding a
/// Cambodian payer looks for, and generating our own would mean shipping a QR
/// encoder to redraw a payload we did not author.
class _QrPanel extends StatelessWidget {
  const _QrPanel({required this.payment});

  final PwaPayment payment;

  @override
  Widget build(BuildContext context) {
    final bytes = _decode(payment.qrImage);
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
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

    // PAID. What this person wants next is to USE what they bought — so the
    // primary action is the work, not the wallet. Deliberately NOT a route back
    // to the pack list: showing someone the thing they just bought, again, as
    // the next mandatory step reads as "buy more" and is the single most common
    // way a good purchase flow ends badly.
    if (payment.state == PwaPaymentState.granted) {
      return Column(
        children: [
          FilledButton(
            onPressed: () {
              notifier.reset();
              Navigator.of(context).pop(PwaPaymentExit.startDesigning);
            },
            style: FilledButton.styleFrom(
              backgroundColor: pwaInk,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PwaGap.radius),
              ),
            ),
            child: Text(l.payStartDesigning,
                style: pwaSans(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () {
              notifier.reset();
              Navigator.of(context).pop(PwaPaymentExit.later);
            },
            child: Text(l.payMaybeLater,
                style: pwaSans(fontSize: 13, color: pwaMuted)),
          ),
        ],
      );
    }

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
                .pop(granted ? PwaPaymentExit.later : PwaPaymentExit.none);
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
