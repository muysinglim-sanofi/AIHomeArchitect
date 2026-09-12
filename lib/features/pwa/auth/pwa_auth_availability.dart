/// Which sign-in methods THIS deployment can actually offer.
///
/// Read from GoTrue's own public `/auth/v1/settings` at boot, not from a build
/// flag: the moment a provider is switched on in the Supabase project, the
/// button appears — no rebuild, no redeploy, and no button that leads to a
/// `provider_disabled` error. The reverse holds too: a provider switched off
/// disappears instead of failing.
///
/// Fails CLOSED to email only. Email OTP is the one transport this project has
/// had since the first identity round, so a settings fetch that times out or
/// returns nonsense degrades to exactly the screen that shipped before this.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Cambodia launch (2026-09-12): the phone door is HIDDEN, whatever the
/// project says. The transport stays in the code — `pwa.auth_phone_change_release`
/// is deployed and the OTP channel is tested — but the launch offers Facebook,
/// Telegram and Guest, and a fourth door nobody chose would dilute that.
///
/// Flip this to false to bring the phone door back; nothing else changes.
const bool kPwaPhoneDoorHidden = true;

class PwaAuthProviders {
  const PwaAuthProviders({
    this.facebook = false,
    this.phone = false,
    this.telegram = false,
    this.email = true,
  });

  /// The fail-closed answer: the transport that has always been there.
  static const PwaAuthProviders emailOnly = PwaAuthProviders();

  final bool facebook;

  /// What the PROJECT says about the phone provider. [kPwaPhoneDoorHidden]
  /// decides whether the door is offered — see [phoneDoor].
  final bool phone;

  /// `custom:telegram`, and only when the SERVER says it is really enabled.
  /// GoTrue's `/auth/v1/settings` never mentions custom providers, so this
  /// flag comes from the backend gate, never from a build define.
  final bool telegram;
  final bool email;

  /// The phone door as the UI must treat it.
  bool get phoneDoor => phone && !kPwaPhoneDoorHidden;

  /// True when there is a choice to make. With email alone the sheet opens
  /// straight on the address field, as it always has.
  bool get hasPrimaryChoice => facebook || telegram || phoneDoor;

  PwaAuthProviders copyWith({bool? telegram}) => PwaAuthProviders(
        facebook: facebook,
        phone: phone,
        telegram: telegram ?? this.telegram,
        email: email,
      );

  /// GoTrue's `/auth/v1/settings` body → the three flags. Unknown or
  /// malformed input reads as email only.
  static PwaAuthProviders parse(Object? body) {
    if (body is! Map) return emailOnly;
    final ext = body['external'];
    if (ext is! Map) return emailOnly;
    bool flag(String k) => ext[k] == true;
    return PwaAuthProviders(
      facebook: flag('facebook'),
      phone: flag('phone'),
      // GoTrue reports `email` for the email provider; a project with it off
      // could not have verified anyone so far, so true is the only value ever
      // seen — but it is read rather than assumed.
      email: ext.containsKey('email') ? flag('email') : true,
    );
  }

  @override
  String toString() => 'PwaAuthProviders(facebook: $facebook, phone: $phone, '
      'telegram: $telegram, email: $email)';
}

/// Ask the BACKEND which custom providers are really enabled. One GET, no
/// token: the answer is booleans about the deployment, not about the person.
/// Every failure is "no custom door" — a button that leads to a refusal is
/// worse than no button at all.
Future<bool> fetchPwaTelegramEnabled({
  required String backendUrl,
  required String apiPrefix,
  http.Client? client,
  Duration timeout = const Duration(seconds: 4),
}) async {
  final c = client ?? http.Client();
  try {
    final uri = Uri.parse('${backendUrl.replaceAll(RegExp(r'/+$'), '')}'
        '$apiPrefix/auth/providers');
    final res = await c.get(uri).timeout(timeout);
    if (res.statusCode != 200) return false;
    final body = jsonDecode(res.body);
    return body is Map && body['telegram'] == true;
  } catch (_) {
    return false;
  } finally {
    if (client == null) c.close();
  }
}

/// Ask the project which providers are on. One GET with the publishable key,
/// bounded by [timeout]; every failure is [PwaAuthProviders.emailOnly].
Future<PwaAuthProviders> fetchPwaAuthProviders({
  required String supabaseUrl,
  required String publishableKey,
  http.Client? client,
  Duration timeout = const Duration(seconds: 4),
}) async {
  final c = client ?? http.Client();
  try {
    final uri = Uri.parse('${supabaseUrl.replaceAll(RegExp(r'/+$'), '')}'
        '/auth/v1/settings');
    final res = await c
        .get(uri, headers: {'apikey': publishableKey})
        .timeout(timeout);
    if (res.statusCode != 200) return PwaAuthProviders.emailOnly;
    return PwaAuthProviders.parse(jsonDecode(res.body));
  } catch (_) {
    return PwaAuthProviders.emailOnly;
  } finally {
    if (client == null) c.close();
  }
}
