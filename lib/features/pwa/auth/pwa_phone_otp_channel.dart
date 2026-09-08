/// The PHONE OTP adapter — the Cambodia transport, same shape as email.
///
/// Two journeys, never chosen implicitly, mirroring `pwa_email_otp_channel`:
///
///   linkNewIdentity  — the current (anonymous) user gets a phone. On the
///                      wire: `PUT /auth/v1/user {phone}` → GoTrue writes
///                      `phone_change` and texts a code (`sendPhoneConfirmation`,
///                      `internal/api/phone.go`); then `POST /auth/v1/verify
///                      {type: phone_change}`. The user id is preserved — the
///                      same upgrade-in-place the email probe measured, on the
///                      same code path (`updateUser`).
///
///   signInExisting   — `POST /auth/v1/otp {phone, create_user: false}` then
///                      `verify {type: sms}`. A DIFFERENT user by design, and
///                      the frozen spec's rule 3 applies: nothing comes across.
///
/// The one thing phone has that email does not: a PREPARE step before the
/// link. GoTrue resolves a `phone_change` verification by NUMBER, not by
/// session (`verify.go`: `FindUserByPhoneChangeAndAudience`), and the column
/// has no uniqueness — so an abandoned attempt on another account can catch a
/// later verification of the same number. The backend clears expired rows for
/// this number first and reports any still live; the channel refuses to start
/// while one is (`destinationContested`). See `docs/auth/…` §phone_change.
///
/// Verified against the pinned SDK (gotrue 2.20.0): `updateUser(UserAttributes
/// (phone:))`, `verifyOTP({phone, token, type})` with `OtpType.phoneChange` /
/// `OtpType.sms`, `signInWithOtp({phone, shouldCreateUser})`, `resend({phone,
/// type})`, and `AuthException.code` carrying `phone_exists`,
/// `over_sms_send_rate_limit`, `sms_send_failed`, `otp_expired`.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'pwa_email_otp_channel.dart' show PwaVerificationIntent;
import 'pwa_phone_number.dart';
import 'pwa_verification_channel.dart';

/// What the backend says after clearing stale `phone_change` rows.
class PwaPhonePrepareResult {
  const PwaPhonePrepareResult({
    required this.ok,
    this.contested = 0,
    this.cleared = 0,
    this.detail = '',
  });

  /// The backend answered. False = it could not be reached or refused; the
  /// link still proceeds, guarded by the user-id check after verification.
  final bool ok;

  /// Rows for this number, on OTHER users, still inside their OTP window.
  final int contested;
  final int cleared;
  final String detail;
}

/// The backend seam. Injected so the channel is testable without a network
/// and so the URL lives with the other API calls, not here.
typedef PwaPhonePrepare = Future<PwaPhonePrepareResult> Function(String e164);

class PwaPhoneOtpChannel implements PwaVerificationChannel {
  PwaPhoneOtpChannel._(this._auth, this.intent, this._prepare);

  /// Attach a number in place. [prepare] runs before the SMS is requested.
  factory PwaPhoneOtpChannel.linkNewIdentity(GoTrueClient auth,
          {PwaPhonePrepare? prepare}) =>
      PwaPhoneOtpChannel._(auth, PwaVerificationIntent.linkNewIdentity, prepare);

  /// Sign in to the account that owns the number. No prepare: a sign-in is
  /// resolved by the `phone` column, which IS unique.
  factory PwaPhoneOtpChannel.signInExisting(GoTrueClient auth) =>
      PwaPhoneOtpChannel._(auth, PwaVerificationIntent.signInExisting, null);

  final GoTrueClient _auth;
  final PwaVerificationIntent intent;
  final PwaPhonePrepare? _prepare;

  @override
  PwaVerificationKind get kind => PwaVerificationKind.phone;

  /// Whether the PROJECT can text anyone is answered by `/auth/v1/settings`
  /// at boot (`PwaAuthProviders.phone`), not here: this instance exists only
  /// when that answer was yes.
  @override
  bool get isConfigured => true;

  @override
  bool looksValid(String destination) =>
      PwaPhoneNumber.looksValid(destination);

  @override
  Future<PwaVerificationResult> send(String destination) async {
    final phone = PwaPhoneNumber.normalize(destination);
    if (phone == null) {
      return const PwaVerificationResult.failed(
          PwaVerificationFailure.invalidDestination);
    }
    try {
      switch (intent) {
        case PwaVerificationIntent.linkNewIdentity:
          final prep = _prepare;
          if (prep != null) {
            final p = await prep(phone);
            if (p.ok && p.contested > 0) {
              return PwaVerificationResult.failed(
                  PwaVerificationFailure.destinationContested,
                  detail: 'contested=${p.contested}');
            }
          }
          // Attaches the number to the CURRENT user (phone_change) and texts
          // the code. Requires the live session the PWA always has.
          await _auth.updateUser(UserAttributes(phone: phone));
        case PwaVerificationIntent.signInExisting:
          // `shouldCreateUser: false`: an unknown number is refused, not
          // quietly minted into a third identity.
          await _auth.signInWithOtp(phone: phone, shouldCreateUser: false);
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
    final phone = PwaPhoneNumber.normalize(destination);
    final token = code.trim();
    if (phone == null) {
      return const PwaVerificationResult.failed(
          PwaVerificationFailure.invalidDestination);
    }
    if (token.isEmpty) {
      return const PwaVerificationResult.failed(
          PwaVerificationFailure.invalidCode);
    }
    try {
      // Not interchangeable: a token minted by `updateUser` is a
      // `phone_change` token; one minted by `signInWithOtp` is an `sms` token.
      final type = intent == PwaVerificationIntent.linkNewIdentity
          ? OtpType.phoneChange
          : OtpType.sms;
      final res = await _auth.verifyOTP(phone: phone, token: token, type: type);
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
    final phone = PwaPhoneNumber.normalize(destination);
    if (phone == null) {
      return const PwaVerificationResult.failed(
          PwaVerificationFailure.invalidDestination);
    }
    try {
      if (intent == PwaVerificationIntent.linkNewIdentity) {
        await _auth.resend(phone: phone, type: OtpType.phoneChange);
      } else {
        await _auth.signInWithOtp(phone: phone, shouldCreateUser: false);
      }
      return const PwaVerificationResult.ok();
    } on AuthException catch (e) {
      return _translate(e);
    } catch (e) {
      return PwaVerificationResult.failed(PwaVerificationFailure.unavailable,
          detail: e.runtimeType.toString());
    }
  }

  static PwaVerificationResult translateForTest(AuthException e) =>
      _translate(e);

  static PwaVerificationResult _translate(AuthException e) {
    final code = (e.code ?? '').toLowerCase();
    final msg = e.message.toLowerCase();
    final status = int.tryParse(e.statusCode ?? '') ?? 0;

    // The one refusal that is a JOURNEY, not an error.
    if (code == 'phone_exists' ||
        code == 'user_already_exists' ||
        msg.contains('already been registered')) {
      return PwaVerificationResult.failed(
          PwaVerificationFailure.destinationAlreadyRegistered, detail: code);
    }
    // `shouldCreateUser: false` against a number with no account.
    if (code == 'otp_disabled' ||
        code == 'user_not_found' ||
        code == 'signup_disabled' ||
        msg.contains('signups not allowed')) {
      return PwaVerificationResult.failed(
          PwaVerificationFailure.invalidDestination, detail: code);
    }
    if (code == 'validation_failed' ||
        code == 'same_phone' ||
        msg.contains('invalid phone')) {
      return PwaVerificationResult.failed(
          PwaVerificationFailure.invalidDestination, detail: code);
    }
    if (code == 'otp_expired' ||
        msg.contains('token has expired') ||
        msg.contains('invalid token')) {
      return PwaVerificationResult.failed(PwaVerificationFailure.invalidCode,
          detail: code.isEmpty ? 'otp_invalid' : code);
    }
    // GoTrue's own send cadence (`sms_max_frequency`, 60 s by default) and
    // the project's SMS quota both land here. The identity operation is not
    // refused — only the delivery — so the UI says "wait", not "failed".
    if (status == 429 ||
        code == 'over_sms_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        msg.contains('for security purposes')) {
      return PwaVerificationResult.failed(PwaVerificationFailure.rateLimited,
          detail: code.isEmpty ? 'rate_limited' : code);
    }
    // The project cannot text: provider off, or the provider refused.
    if (code == 'sms_send_failed' ||
        code == 'phone_provider_disabled' ||
        code == 'provider_disabled' ||
        msg.contains('unsupported phone provider') ||
        msg.contains('error sending')) {
      return PwaVerificationResult.failed(PwaVerificationFailure.unavailable,
          detail: code.isEmpty ? 'sms' : code);
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
