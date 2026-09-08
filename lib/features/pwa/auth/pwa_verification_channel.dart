/// ONE verification abstraction for the PWA. The UI never learns the transport.
///
/// Today the staging transport is EMAIL OTP, because that is what the staging
/// project actually has (`external.email: true`, `external.phone: false`, and no
/// SMS contract). The production target for Cambodia is PHONE OTP. Those are the
/// same *step* in the funnel — "prove you can receive a code" — carried by
/// different wires.
///
/// So the Paywall and the Auth sheet talk to [PwaVerificationChannel] and know:
///   * a destination they can label (an email address today, a number later),
///   * "send a code", "check this code",
///   * a small, closed set of outcomes.
///
/// They do NOT know Supabase, GoTrue, `OtpType`, Twilio, MessageBird or Vonage.
/// Swapping the transport is implementing this interface and choosing it in one
/// place — not a search through widgets for provider-specific branches.
library;

/// What kind of destination a channel verifies. The UI uses this ONLY to label
/// the field and choose a keyboard — never to branch on a vendor.
enum PwaVerificationKind { email, phone }

/// Why a verification attempt did not succeed.
///
/// A closed set on purpose: the UI must be able to say something true about
/// every one of them, and a channel that invents a new failure mode has to come
/// here and say so.
enum PwaVerificationFailure {
  /// The destination is not a usable address/number.
  invalidDestination,

  /// The destination already belongs to an EXISTING Ayden account.
  ///
  /// This is NOT an error to retry — it is a different journey, and the frozen
  /// identity spec treats it differently (rule 3: signing in to an existing
  /// account transfers no Guest credit and grants no bonus). Keeping it as its
  /// own outcome is what stops the two cases being silently merged.
  destinationAlreadyRegistered,

  /// The code was wrong or has expired.
  invalidCode,

  /// Too many attempts, or the transport's own send quota is spent.
  ///
  /// Staging hits this on the send side: the project uses Supabase's BUILT-IN
  /// SMTP, whose quota is small, and it answers `over_email_send_rate_limit`.
  /// That is a mail-delivery limit, not a refusal of the identity operation —
  /// which is why it is a distinct outcome the UI can explain honestly rather
  /// than a generic failure.
  rateLimited,

  /// The transport could not be reached.
  unavailable,

  /// Another verification for this NUMBER is still in flight on a different
  /// account (a `phone_change` that was started and abandoned minutes ago).
  ///
  /// GoTrue resolves a `phone_change` verification by NUMBER, not by session
  /// (`verify.go`, `FindUserByPhoneChangeAndAudience`), so while such a row
  /// exists the code could be checked against the wrong account. The backend
  /// clears rows that are past their expiry; one still inside it is reported
  /// here and the person is asked to wait rather than gamble.
  destinationContested,

  /// The verification finished on a DIFFERENT user than the one that started
  /// it, on a journey that promised to keep the same user. The previous
  /// session was restored and nothing was attached. Never silently accepted.
  identityMismatch,

  /// The person closed or refused the provider's own screen. Not an error to
  /// apologise for — they changed their mind.
  cancelled,

  /// The provider (Facebook) did not share an email address, and GoTrue will
  /// not attach an email-less social identity to an account that has no email
  /// of its own (`linkIdentityToUser`, `internal/api/identity.go`). The
  /// account is untouched; phone or email can still secure it.
  providerNoEmail,

  /// The provider flow could not run: switched off on the project, manual
  /// linking disabled, a bad callback, a stale state. Configuration, not the
  /// person — so the copy says "not available right now", not "wrong".
  providerRefused,

  /// Anything else. The UI shows a generic message; the code is logged.
  unknown,
}

/// The result of asking a channel to do something. Never an exception at the
/// call site: a verification step failing is an ordinary state of the screen.
class PwaVerificationResult {
  const PwaVerificationResult.ok()
      : failure = null,
        detail = '';
  const PwaVerificationResult.failed(this.failure, {this.detail = ''});

  final PwaVerificationFailure? failure;

  /// Non-user-facing. For logs and tests; never rendered.
  final String detail;

  bool get isOk => failure == null;
}

/// The transport that proves someone can receive a code.
abstract class PwaVerificationChannel {
  /// Labels the field and picks the keyboard. Nothing else may branch on it.
  PwaVerificationKind get kind;

  /// Whether this deployment can actually verify right now. False means the UI
  /// must say so rather than collect a destination it cannot use.
  bool get isConfigured;

  /// Cheap, local shape check so the UI can disable a button without a round
  /// trip. The authority is still the server.
  bool looksValid(String destination);

  /// Start verification: send a code to [destination].
  ///
  /// For the NEW-identity path this also attaches the destination to the
  /// current (anonymous) user, which is what makes the upgrade in-place.
  Future<PwaVerificationResult> send(String destination);

  /// Finish verification with the code the person received.
  Future<PwaVerificationResult> verify(String destination, String code);

  /// Re-send the code for the same destination.
  Future<PwaVerificationResult> resend(String destination);
}
