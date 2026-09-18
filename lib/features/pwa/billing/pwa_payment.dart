/// The PAYMENT ATTEMPT the PWA renders. Read from the server, never inferred.
///
/// The rule this file exists to enforce
/// ------------------------------------
/// A browser cannot know whether it was paid. It can know that ABA Mobile came
/// back to the foreground, that a QR disappeared, that a redirect happened, or
/// that thirty seconds elapsed — and every one of those is a lie waiting to be
/// told. The money lives at a bank; the entitlement lives in a ledger; the
/// browser is a screen.
///
/// So there is no client-side transition in here at all. [PwaPaymentState] is
/// parsed from what `/pwa/staging/payments/...` said, and the ONLY state that
/// unlocks anything is [PwaPaymentState.granted] — which the server writes after
/// it has called PayWay's Check Transaction itself and handed the verified
/// payment to the Billing Engine.
///
/// Why the states are the server's, verbatim
/// -----------------------------------------
/// They could have been collapsed to three (waiting / done / failed) and the
/// screen would still work. They are not, because a person waiting to pay is
/// owed a different sentence in each of them:
///
///   awaitingPayment          "scan this" — the QR is live
///   paidPendingVerification  "we've been told, we're checking" — the doorbell
///                            rang, and saying "paid" here would be a promise
///                            the server has not made
///   verified                 "confirmed, activating" — PayWay said APPROVED,
///                            the credits are landing
///   granted                  "it's yours"
///   expired / cancelled      distinct from [failed]: nothing went wrong, and
///                            offering "try again" reads differently from
///                            "something broke"
library;

import 'pwa_entitlement.dart' show pwaMoney;

/// Where a payment attempt is, as the SERVER sees it.
enum PwaPaymentState {
  /// Nothing in progress. The paywall shows products.
  idle,

  /// We asked; no answer yet. Never rendered as a failure.
  starting,

  /// Claimed, but PayWay has not yet returned a QR. Usually milliseconds.
  created,

  /// The QR and deeplink are live. THE state a person pays in.
  awaitingPayment,

  /// PayWay rang our callback. It proves nothing on its own — the server is
  /// verifying — and the copy must not say "paid".
  paidPendingVerification,

  /// Check Transaction said APPROVED. The grant is running.
  verified,

  /// The Billing Engine granted. The ONLY state that unlocks generation.
  granted,

  /// The gateway refused, declined, or paid something we did not ask for.
  failed,

  /// The QR's lifetime ran out unpaid.
  expired,

  /// The person closed the sheet before paying.
  cancelled,

  /// Payments are not open in this deployment (no credentials configured).
  unavailable,

  /// We could not reach our own server. NOT a refusal — the attempt may well
  /// still be alive, and the next poll asks again.
  unreachable,

  /// The server will not open a purchase for an ANONYMOUS account.
  ///
  /// Not a refusal of money — no gateway was asked, no transaction exists, and
  /// nothing failed. It is a prerequisite: buy a pack with a session that lives
  /// only in one browser's storage and the entitlement outlives the only way
  /// back to it. The screen's answer is the secure-account flow, never a
  /// payment error.
  accountRequired,
}

/// WHERE a payment result came from — the fact the UI needs and the server
/// cannot supply.
///
/// The server is authoritative about what a transaction IS. It is not
/// authoritative about whether the person in front of the screen is expecting
/// an answer about it, and that is a different question with a different
/// consequence: a full-screen "Payment failed / cancelled — no credits were
/// added" is correct for a purchase someone just attempted, and a lie about
/// their money for an attempt they abandoned two days ago and have forgotten.
///
/// This is carried explicitly rather than inferred from the age of a tran_id,
/// because age is a proxy: a genuine checkout that a person leaves open for
/// half an hour is old, and a stale attempt reconciled the second the app
/// opens is young. Intent is what matters, and only the client knows it.
enum PwaPaymentOrigin {
  /// The person pressed Buy in THIS journey. Every verdict is theirs to see.
  activeCheckout,

  /// `restore()` asked the server, at boot or on resume, whether anything was
  /// still open. Whatever came back, nobody asked for it just now.
  restore,
}

/// WHAT a backend refusal was about. Five kinds, because exactly one of them
/// is entitled to tell a person that their payment failed.
///
/// THE DEFECT THIS REPLACES. Every code the client did not recognise used to
/// become [PwaPaymentState.failed], and [PwaPaymentState.failed] is the state
/// the full-screen red card is built on. So an expired session token, a rail an
/// operator had closed, and a typo in a product sku all rendered as "Payment
/// failed / cancelled" and "No credits were added" — a statement about
/// somebody's money, made by code that had just failed to ask the question.
///
/// Fail closed technically; do not lie financially.
enum PwaPaymentErrorClass {
  /// The gateway refused the purchase, or the transaction itself is terminal.
  /// The ONLY class allowed to say a payment failed.
  payment,

  /// The caller has no usable session. Nothing whatsoever is known about any
  /// payment — including, especially, one that already succeeded.
  auth,

  /// The caller is a Guest, and a Guest may not buy. An account prerequisite,
  /// deliberately its own class so that no surface can render it as money
  /// having gone wrong.
  account,

  /// The rail is closed or misconfigured, or this product cannot be sold here.
  /// No payment was ever attempted.
  availability,

  /// The request could not be understood, or named something the server does
  /// not have. A defect on one side or the other, never a decline.
  contract,

  /// No answer, or an answer in a vocabulary this build does not know. The
  /// default, deliberately: an unrecognised code is an unknown, and an unknown
  /// is not a failed payment.
  technical,
}

/// Classify one backend `error_code`.
///
/// The vocabulary is the backend's, read from `pwa_staging_payments.py`. A code
/// added there and not added here lands on [PwaPaymentErrorClass.technical] —
/// which is why the default matters more than the table.
PwaPaymentErrorClass pwaClassifyPaymentError(String code) =>
    switch (code.toUpperCase()) {
      // The gateway itself said no to the purchase. The server has already
      // written the attempt terminal.
      'PAYMENT_PROVIDER_REFUSED' => PwaPaymentErrorClass.payment,

      // The secured-account guard. 403, before any transaction is created.
      'ACCOUNT_REQUIRED' => PwaPaymentErrorClass.account,

      // `_caller` -> `_verify_user`: 401 on every payment route, including the
      // `GET /payments/open` that runs at every cold start.
      'SESSION_EXPIRED' || 'MISSING_TOKEN' => PwaPaymentErrorClass.auth,

      // The operator's kill switch and the two "not configured" refusals. Note
      // the backend has BOTH spellings, singular and plural; they are one
      // meaning and both belong here.
      'PAYMENTS_CLOSED' ||
      'PAYMENTS_UNAVAILABLE' ||
      'PAYMENT_UNAVAILABLE' ||
      // A product this deployment may not sell is the same answer to the
      // person: there is nothing to buy here, and no money moved.
      'UNKNOWN_PRODUCT' ||
      'PRODUCT_NOT_WEB_SELLABLE' ||
      'PRODUCT_NOT_PRICED' =>
        PwaPaymentErrorClass.availability,

      'UNKNOWN_TRANSACTION' || 'BAD_REQUEST' => PwaPaymentErrorClass.contract,

      'UNREACHABLE' || 'CANCELLED' || 'PAYMENT_PROVIDER_UNREACHABLE' =>
        PwaPaymentErrorClass.technical,

      _ => PwaPaymentErrorClass.technical,
    };

/// A payment attempt, exactly as the server described it.
/// `checkout_mode` when ABA's own plugin presents the checkout and the BROWSER
/// posts the signed purchase — the active Web path since 2026-09-05. The other
/// two modes ('redirect', 'json') are the server-side Purchase call, dormant.
const String kPwaCheckoutModePlugin = 'plugin';

class PwaPayment {
  const PwaPayment({
    required this.state,
    this.tranId = '',
    this.sku = '',
    this.credits = 0,
    this.amount,
    this.currency = 'USD',
    this.checkoutUrl = '',
    this.checkoutMode = '',
    this.checkoutStale = false,
    this.qrString = '',
    this.qrImage = '',
    this.deeplink = '',
    this.expiresAt,
    this.failureReason = '',
    this.newAttemptRequired = false,
    this.pollIntervalMs = 3000,
    this.origin = PwaPaymentOrigin.activeCheckout,
  });

  const PwaPayment.idle() : this(state: PwaPaymentState.idle);
  const PwaPayment.starting() : this(state: PwaPaymentState.starting);

  final PwaPaymentState state;
  final String tranId;
  final String sku;

  /// What this purchase grants, straight from the canonical catalogue.
  final int credits;
  final double? amount;
  final String currency;

  /// WHERE THE PERSON PAYS: PayWay's own checkout, on PayWay's own domain.
  ///
  /// ABA's integration guideline puts the payment screen with ABA, and this is
  /// the whole of Ayden's part in it — hand the browser this URL. Ayden does not
  /// draw a KHQR, does not host ABA's option chooser, and does not frame their
  /// page. A checkout we rendered ourselves would be a copy we had to keep in
  /// step with theirs forever, and it would be the wrong copy the first time
  /// they changed anything.
  final String checkoutUrl;

  /// `redirect` | `json` — how PayWay answered. Diagnostic only.
  final String checkoutMode;

  /// True once PayWay's checkout TOKEN has aged out (180 seconds, measured).
  ///
  /// This is NOT a failed payment and must never be shown as one. The
  /// transaction is still perfectly payable; only the link to it has expired.
  /// The right response is to offer a fresh attempt, not an error.
  final bool checkoutStale;

  /// The KHQR payload, and PayWay's rendering of it as a base64 PNG. Populated
  /// only when the deployment pins `abapay_khqr_deeplink`; empty is the normal
  /// answer and is not a degraded state. Both are the payment request itself —
  /// public by nature, which is why they may be in a browser at all.
  final String qrString;
  final String qrImage;

  /// `abapay_deeplink` — opens ABA Mobile straight onto this payment. Empty when
  /// PayWay did not provide one, and the UI must then not offer the button.
  final String deeplink;

  final DateTime? expiresAt;

  /// A machine code the client translates: AMOUNT_MISMATCH, DECLINED, EXPIRED,
  /// QR_REFUSED, DUPLICATE_TRAN_ID, PRODUCT_UNMAPPED… Never rendered as-is.
  final String failureReason;

  /// True when retrying this attempt cannot work and a NEW one is required —
  /// PayWay refuses a transaction id it has already seen.
  final bool newAttemptRequired;

  final int pollIntervalMs;

  /// Whether this answer belongs to a checkout the person just started, or to
  /// one `restore()` went looking for. Stamped by the controller — a parsed
  /// server body cannot know it, and defaults to [PwaPaymentOrigin.activeCheckout]
  /// so that forgetting to stamp can only ever be over-informative, never
  /// silent about a real payment.
  final PwaPaymentOrigin origin;

  /// The same answer, attributed to [origin].
  PwaPayment withOrigin(PwaPaymentOrigin origin) => PwaPayment(
        state: state,
        tranId: tranId,
        sku: sku,
        credits: credits,
        amount: amount,
        currency: currency,
        checkoutUrl: checkoutUrl,
        checkoutMode: checkoutMode,
        checkoutStale: checkoutStale,
        qrString: qrString,
        qrImage: qrImage,
        deeplink: deeplink,
        expiresAt: expiresAt,
        failureReason: failureReason,
        newAttemptRequired: newAttemptRequired,
        pollIntervalMs: pollIntervalMs,
        origin: origin,
      );

  /// Whether the sheet should keep asking. False on every terminal state, so a
  /// finished payment stops polling rather than being stopped by a timer.
  bool get isPolling => const {
        PwaPaymentState.created,
        PwaPaymentState.awaitingPayment,
        PwaPaymentState.paidPendingVerification,
        PwaPaymentState.verified,
      }.contains(state);

  /// Whether there is a live place for a person to pay right now.
  ///
  /// Both halves matter. A checkout whose token has aged out is not payable
  /// through THIS link even though the payment behind it is still open — so
  /// offering it would send someone to a PayWay error page.
  ///
  /// On the PLUGIN path there is no link at all: ABA's own script posted the
  /// signed form into its own iframe, and the place to pay is that popup, for
  /// as long as the transaction lives. `checkoutUrl` is empty there by design
  /// and `checkoutStale` measures a token this path never used — so neither
  /// may decide payability, or every plugin checkout would read as expired the
  /// moment it opened.
  bool get isPayable =>
      state == PwaPaymentState.awaitingPayment &&
      (checkoutMode == kPwaCheckoutModePlugin ||
          (checkoutUrl.isNotEmpty && !checkoutStale));

  /// The attempt is alive but its link is not. A fresh attempt is the only way
  /// back to a payable state — PayWay refuses a second checkout for the same
  /// transaction id.
  ///
  /// Never true on the plugin path, for the reason given on [isPayable]: there
  /// is no link to age out.
  bool get needsFreshCheckout =>
      state == PwaPaymentState.awaitingPayment &&
      checkoutMode != kPwaCheckoutModePlugin &&
      (checkoutUrl.isEmpty || checkoutStale);

  /// Whether offering "try again" makes sense.
  bool get canRetry => const {
        PwaPaymentState.failed,
        PwaPaymentState.expired,
        PwaPaymentState.cancelled,
        PwaPaymentState.unreachable,
      }.contains(state);

  bool get isTerminal => const {
        PwaPaymentState.granted,
        PwaPaymentState.failed,
        PwaPaymentState.expired,
        PwaPaymentState.cancelled,
      }.contains(state);

  /// Seconds left on the QR, or null when there is no live deadline.
  ///
  /// Shown as information, never used to DECIDE anything: a countdown reaching
  /// zero does not expire a payment — the server does, after asking PayWay one
  /// last time whether the money landed.
  int? secondsRemaining({DateTime? now}) {
    final deadline = expiresAt;
    if (deadline == null || !isPolling) return null;
    final left = deadline.difference(now ?? DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  static PwaPaymentState _stateFrom(String raw) => switch (raw.toUpperCase()) {
        'CREATED' => PwaPaymentState.created,
        'AWAITING_PAYMENT' => PwaPaymentState.awaitingPayment,
        'PAID_PENDING_VERIFICATION' => PwaPaymentState.paidPendingVerification,
        'VERIFIED' => PwaPaymentState.verified,
        'GRANTED' => PwaPaymentState.granted,
        'FAILED' => PwaPaymentState.failed,
        'EXPIRED' => PwaPaymentState.expired,
        'CANCELLED' => PwaPaymentState.cancelled,
        // An unknown state is NOT success and NOT failure. Treating it as
        // "still going" keeps the person on a screen that polls, and the server
        // remains the thing that ends it.
        _ => PwaPaymentState.created,
      };

  /// The state a refusal of [cls] is rendered as.
  ///
  /// Only [PwaPaymentErrorClass.payment] may reach [PwaPaymentState.failed],
  /// which is the state the red "Payment failed / cancelled — no credits were
  /// added" card is built on. Everything else lands on a state that says we
  /// have no verdict, because we have no verdict.
  static PwaPaymentState stateForErrorClass(PwaPaymentErrorClass cls) =>
      switch (cls) {
        PwaPaymentErrorClass.payment => PwaPaymentState.failed,
        PwaPaymentErrorClass.account => PwaPaymentState.accountRequired,
        PwaPaymentErrorClass.availability => PwaPaymentState.unavailable,
        // Auth, contract and technical all share the ONE state this class
        // already had for "no answer, and the attempt may well still be
        // alive": nothing is concluded, the next ask decides, and the person
        // is never told about money that did not move.
        PwaPaymentErrorClass.auth ||
        PwaPaymentErrorClass.contract ||
        PwaPaymentErrorClass.technical =>
          PwaPaymentState.unreachable,
      };

  /// Parse one server answer.
  ///
  /// The failure branch is deliberate: a non-2xx carries a machine code, and
  /// mapping it here means the widget never has to know that 503 is
  /// "payments closed" while 502 is "the gateway said no".
  static PwaPayment parse(Map<String, Object?> body) {
    if (body['ok'] != true) {
      final code = (body['error_code'] as String?) ?? '';
      return PwaPayment(
        state: code == 'CHECKOUT_BUSY'
            // Not an error at all: the server is already opening this very
            // attempt and says so. Stay on the preparing screen.
            ? PwaPaymentState.created
            : stateForErrorClass(pwaClassifyPaymentError(code)),
        failureReason: (body['reason'] as String?)?.toUpperCase() ?? code,
        newAttemptRequired: body['new_attempt_required'] == true,
      );
    }

    // `/payments/open` answers {open: false} when there is nothing to restore.
    if (body.containsKey('open') && body['open'] != true) {
      return const PwaPayment.idle();
    }

    return PwaPayment(
      state: _stateFrom((body['state'] as String?) ?? ''),
      tranId: (body['tran_id'] as String?) ?? '',
      sku: (body['sku'] as String?) ?? '',
      credits: (body['credits'] as num?)?.toInt() ?? 0,
      amount: (body['amount'] as num?)?.toDouble(),
      currency: (body['currency'] as String?) ?? 'USD',
      checkoutUrl: (body['checkout_url'] as String?) ?? '',
      checkoutMode: (body['checkout_mode'] as String?) ?? '',
      checkoutStale: body['checkout_stale'] == true,
      qrString: (body['qr_string'] as String?) ?? '',
      qrImage: (body['qr_image'] as String?) ?? '',
      deeplink: (body['deeplink'] as String?) ?? '',
      expiresAt: DateTime.tryParse((body['expires_at'] as String?) ?? ''),
      failureReason: (body['failure_reason'] as String?) ?? '',
      pollIntervalMs: (body['poll_interval_ms'] as num?)?.toInt() ?? 3000,
    );
  }

  /// The price as a person reads it. Same rule as [PwaProduct.priceLabel]: a
  /// price is a property of the product, not translated copy.
  String get amountLabel {
    final value = amount;
    if (value == null) return '';
    return currency == 'USD'
        ? '\$${pwaMoney(value)}'
        : '${pwaMoney(value)} $currency';
  }
}
