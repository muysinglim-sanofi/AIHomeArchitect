/// The PAYMENT SEAM. Defined here, deliberately NOT implemented.
///
/// §11 of the brief is explicit, and this file honours it literally:
///
///     DO NOT implement ABA requests.
///     DO NOT fake ABA callbacks.
///     DO NOT use community ABA docs to write production-like payment code.
///
/// What exists therefore is the SHAPE of a checkout and one implementation that
/// truthfully answers "not available here". That is not a placeholder waiting to
/// be filled with guesswork — it is the correct state of the system today, and
/// the paywall renders it as such.
///
/// Why a seam at all, if nothing is wired
/// --------------------------------------
/// Because the alternative is worse. Without it, "can I buy?" gets answered by
/// scattered `if` statements, and the day ABA (or KHQR, or a card processor) is
/// signed, payment logic lands inside widgets. With it, the whole of the app
/// asks one question — [isConfigured] — and a real provider is a new class plus
/// one server-side value.
///
/// Where the truth comes from
/// --------------------------
/// The SERVER decides which provider exists (`payment.provider` /
/// `payment.configured` on `GET /pwa/staging/entitlement`). The client never
/// assumes: a browser build that believed ABA was live while the backend had no
/// merchant configuration would show a Buy button that cannot complete, which is
/// worse than showing none.
///
/// And what a real provider must NOT do
/// ------------------------------------
/// Grant anything. A payment provider's job ends at "the money moved"; the
/// credits appear because the Billing Engine granted them server-side, on a
/// verified callback, keyed on the transaction. That rule is why
/// [PwaCheckoutOutcome] has no "granted" case: a client cannot mint entitlement,
/// and the only honest thing it can report is that a purchase FLOW finished.
library;

import 'pwa_entitlement.dart';

/// How a checkout attempt ended, from the CLIENT's point of view.
enum PwaCheckoutOutcome {
  /// No provider is wired in this deployment. The only outcome in staging.
  unavailable,

  /// The person closed the flow without paying.
  cancelled,

  /// The provider says the payment flow completed. Entitlement is NOT implied:
  /// the app must re-read the Billing Engine, which is the only thing that can
  /// say a credit exists.
  submitted,

  /// The provider itself failed.
  failed,
}

class PwaCheckoutResult {
  const PwaCheckoutResult(this.outcome, {this.detail = ''});

  final PwaCheckoutOutcome outcome;

  /// Non-user-facing. Logged, never rendered.
  final String detail;
}

/// A way to take money for a [PwaProduct].
abstract class PwaPaymentProvider {
  /// Server-owned identifier: `none`, later `aba`, `khqr`, `stripe`…
  String get id;

  /// Whether this deployment can actually complete a purchase right now.
  bool get isConfigured;

  /// Begin a checkout. Implementations must be safe to call twice: the
  /// Billing Engine keys a grant on the transaction, not on this call.
  Future<PwaCheckoutResult> checkout(PwaProduct product);
}

/// The honest implementation for staging: there is no payment provider.
///
/// It exists so the paywall has something real to render and something real to
/// test against — "Not available yet" is a state with copy, localisation and a
/// visual design, not an absence.
class PwaUnconfiguredPaymentProvider implements PwaPaymentProvider {
  const PwaUnconfiguredPaymentProvider([this.id = 'none']);

  @override
  final String id;

  @override
  bool get isConfigured => false;

  @override
  Future<PwaCheckoutResult> checkout(PwaProduct product) async =>
      const PwaCheckoutResult(PwaCheckoutOutcome.unavailable,
          detail: 'no payment provider configured for this deployment');
}

/// Build the provider this deployment actually has, from what the SERVER said.
///
/// Today every input maps to [PwaUnconfiguredPaymentProvider], because no
/// provider is implemented. When one is, it is registered here — one line, one
/// place — and nothing else in the app changes.
PwaPaymentProvider pwaPaymentProviderFor(PwaEntitlement entitlement) {
  // Intentionally NOT `switch (entitlement.paymentProvider)` with speculative
  // branches. A branch for a provider that does not exist is a claim that it
  // might, and the first person to read it would wire a fake checkout behind it.
  return PwaUnconfiguredPaymentProvider(entitlement.paymentProvider);
}
