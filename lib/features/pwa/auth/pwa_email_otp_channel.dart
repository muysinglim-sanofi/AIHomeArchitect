/// The EMAIL OTP adapter — the only file in the PWA that knows GoTrue exists.
///
/// It implements [PwaVerificationChannel] twice over, because the frozen
/// identity spec has two DIFFERENT journeys that happen to share a transport,
/// and collapsing them is the exact mistake §3 of the brief forbids:
///
///   linkNewIdentity  — an anonymous visitor attaches an identity they have
///                      never used before. `updateUser(email)` + an
///                      `emailChange` OTP. MEASURED to preserve the user_id
///                      (`backend/pwa_staging_identity_probe.py`, B2/B5/B6:
///                      uid_after == uid_before, the original session still
///                      resolves, is_anonymous flips true -> false). Nothing is
///                      migrated because nothing moves: projects, ledger rows
///                      and every RLS policy are keyed on that same id.
///
///   signInExisting   — the address already belongs to an Ayden account.
///                      `signInWithOtp(shouldCreateUser: false)` + an `email`
///                      OTP. This DOES change which user the browser is, and
///                      the frozen spec is explicit that it carries nothing
///                      over: no Guest credit, no claim, no bonus. Modelled as
///                      a separate journey so that fact is structural rather
///                      than a comment someone can drift away from.
///
/// The two are never chosen implicitly. `linkNewIdentity.send()` reports
/// [PwaVerificationFailure.destinationAlreadyRegistered] and STOPS; moving to
/// the other journey is a decision the person makes on screen.
///
/// Verified against the pinned SDK (gotrue 2.20.0) rather than remembered:
/// `updateUser(UserAttributes, {emailRedirectTo})`, `verifyOTP({email, token,
/// required OtpType type})`, `signInWithOtp({email, shouldCreateUser})`,
/// `resend({email, required OtpType type})`, and `AuthException.code` carrying
/// the machine-readable `email_exists` / `otp_expired` /
/// `over_email_send_rate_limit` values this file switches on.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'pwa_verification_channel.dart';

/// Which of the two journeys an instance carries.
enum PwaVerificationIntent {
  /// Attach a brand-new identity to the CURRENT (anonymous) user. Same user_id.
  linkNewIdentity,

  /// Sign in to an account that already exists. Different user_id.
  signInExisting,
}

class PwaEmailOtpChannel implements PwaVerificationChannel {
  PwaEmailOtpChannel._(this._auth, this.intent);

  /// Attach an identity in place. The measured upgrade path.
  factory PwaEmailOtpChannel.linkNewIdentity(GoTrueClient auth) =>
      PwaEmailOtpChannel._(auth, PwaVerificationIntent.linkNewIdentity);

  /// Sign in to an existing account. A different person, by design.
  factory PwaEmailOtpChannel.signInExisting(GoTrueClient auth) =>
      PwaEmailOtpChannel._(auth, PwaVerificationIntent.signInExisting);

  final GoTrueClient _auth;
  final PwaVerificationIntent intent;

  @override
  PwaVerificationKind get kind => PwaVerificationKind.email;

  /// Staging verifies by email, so the channel is configured whenever there is
  /// a client. The PHONE adapter that replaces it in Cambodia will answer this
  /// from its own vendor config — which is the point of asking here at all.
  @override
  bool get isConfigured => true;

  /// Deliberately permissive: one `@`, something either side, a dot in the
  /// domain. Enough to grey out a button, and no more — a client-side regex
  /// that "knows" what a valid address looks like rejects real ones.
  @override
  bool looksValid(String destination) {
    final v = destination.trim();
    final at = v.indexOf('@');
    if (at <= 0 || at != v.lastIndexOf('@') || at == v.length - 1) return false;
    final domain = v.substring(at + 1);
    return domain.contains('.') &&
        !domain.startsWith('.') &&
        !domain.endsWith('.') &&
        !v.contains(' ');
  }

  @override
  Future<PwaVerificationResult> send(String destination) async {
    final email = destination.trim();
    if (!looksValid(email)) {
      return const PwaVerificationResult.failed(
          PwaVerificationFailure.invalidDestination);
    }
    try {
      switch (intent) {
        case PwaVerificationIntent.linkNewIdentity:
          // Attaches the address to the CURRENT user and mails a change token.
          // Requires a live session — which the PWA always has, because the
          // anonymous one is minted at boot.
          await _auth.updateUser(UserAttributes(email: email));
        case PwaVerificationIntent.signInExisting:
          // `shouldCreateUser: false` is what makes this journey honest: if the
          // account does not exist, GoTrue refuses instead of quietly minting a
          // third identity behind the person's back.
          await _auth.signInWithOtp(email: email, shouldCreateUser: false);
      }
      return const PwaVerificationResult.ok();
    } on AuthException catch (e) {
      return _translate(e);
    } catch (e) {
      return PwaVerificationResult.failed(PwaVerificationFailure.unavailable,
          detail: e.runtimeType.toString());
    }
  }

  @override
  Future<PwaVerificationResult> verify(String destination, String code) async {
    final email = destination.trim();
    final token = code.trim();
    if (token.isEmpty) {
      return const PwaVerificationResult.failed(
          PwaVerificationFailure.invalidCode);
    }
    try {
      // The OTP TYPE is what differs, and it is not interchangeable: a token
      // minted by `updateUser` is an emailChange token; one minted by
      // `signInWithOtp` is an email token.
      final type = intent == PwaVerificationIntent.linkNewIdentity
          ? OtpType.emailChange
          : OtpType.email;
      final res = await _auth.verifyOTP(email: email, token: token, type: type);
      if (res.user == null) {
        return const PwaVerificationResult.failed(
            PwaVerificationFailure.unknown,
            detail: 'verifyOTP returned no user');
      }
      return const PwaVerificationResult.ok();
    } on AuthException catch (e) {
      return _translate(e);
    } catch (e) {
      return PwaVerificationResult.failed(PwaVerificationFailure.unavailable,
          detail: e.runtimeType.toString());
    }
  }

  @override
  Future<PwaVerificationResult> resend(String destination) async {
    final email = destination.trim();
    try {
      if (intent == PwaVerificationIntent.linkNewIdentity) {
        await _auth.resend(email: email, type: OtpType.emailChange);
      } else {
        await _auth.signInWithOtp(email: email, shouldCreateUser: false);
      }
      return const PwaVerificationResult.ok();
    } on AuthException catch (e) {
      return _translate(e);
    } catch (e) {
      return PwaVerificationResult.failed(PwaVerificationFailure.unavailable,
          detail: e.runtimeType.toString());
    }
  }

  /// GoTrue's vocabulary -> the closed set the UI understands. Kept as a pure,
  /// static function so the mapping is testable without a network or a client.
  static PwaVerificationResult translateForTest(AuthException e) => _translate(e);

  static PwaVerificationResult _translate(AuthException e) {
    final code = (e.code ?? '').toLowerCase();
    final msg = e.message.toLowerCase();
    final status = int.tryParse(e.statusCode ?? '') ?? 0;

    // The one refusal that is a JOURNEY, not an error.
    if (code == 'email_exists' ||
        code == 'user_already_exists' ||
        msg.contains('already been registered')) {
      return PwaVerificationResult.failed(
          PwaVerificationFailure.destinationAlreadyRegistered, detail: code);
    }
    // `shouldCreateUser: false` against an address with no account.
    if (code == 'otp_disabled' ||
        code == 'user_not_found' ||
        msg.contains('signups not allowed')) {
      return PwaVerificationResult.failed(
          PwaVerificationFailure.invalidDestination, detail: code);
    }
    if (code == 'email_address_invalid' ||
        code == 'validation_failed' ||
        code == 'email_address_not_authorized') {
      return PwaVerificationResult.failed(
          PwaVerificationFailure.invalidDestination, detail: code);
    }
    if (code == 'otp_expired' || msg.contains('token has expired') ||
        msg.contains('invalid token')) {
      return PwaVerificationResult.failed(PwaVerificationFailure.invalidCode,
          detail: code.isEmpty ? 'otp_invalid' : code);
    }
    // Staging's built-in SMTP quota lands here. The identity operation is not
    // refused — only the delivery — so the UI says "wait", not "failed".
    if (status == 429 ||
        code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit') {
      return PwaVerificationResult.failed(PwaVerificationFailure.rateLimited,
          detail: code.isEmpty ? 'rate_limited' : code);
    }
    if (e is AuthRetryableFetchException || status >= 500 || status == 0) {
      return PwaVerificationResult.failed(PwaVerificationFailure.unavailable,
          detail: code.isEmpty ? 'transport' : code);
    }
    if (status == 401 || status == 403 || status == 400) {
      return PwaVerificationResult.failed(PwaVerificationFailure.invalidCode,
          detail: code.isEmpty ? 'rejected_$status' : code);
    }
    return PwaVerificationResult.failed(PwaVerificationFailure.unknown,
        detail: code.isEmpty ? 'status_$status' : code);
  }
}
