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

class PwaAuthProviders {
  const PwaAuthProviders({
    this.facebook = false,
    this.phone = false,
    this.email = true,
  });

  /// The fail-closed answer: the transport that has always been there.
  static const PwaAuthProviders emailOnly = PwaAuthProviders();

  final bool facebook;
  final bool phone;
  final bool email;

  /// True when there is a choice to make. With email alone the sheet opens
  /// straight on the address field, as it always has.
  bool get hasPrimaryChoice => facebook || phone;

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
  String toString() =>
      'PwaAuthProviders(facebook: $facebook, phone: $phone, email: $email)';
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
