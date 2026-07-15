/// FT2-B spike — LOCAL Apple identity-token claim reader (PURE).
///
/// Decodes ONLY the JWT payload segment of an Apple identity token to read the
/// `sub` / `aud` / `iss` claims, for a LOCAL same-Apple-account comparison
/// between Phase B and Phase C. It does NOT — and must never claim to —
/// cryptographically verify the signature; the token was just produced on-device
/// by Sign in with Apple, and we only read claims that are already trusted for
/// this comparison.
///
/// Hard rules (enforced by design + tests):
///   • never returns the full token;
///   • never extracts or retains `email` / `name` (PII);
///   • `sub` is returned to the caller to hold IN MEMORY ONLY — it must never be
///     logged, persisted, or placed in the copyable report;
///   • malformed tokens return null (no throw).
library;

import 'dart:convert';

/// The claims we read from an Apple identity token. Intentionally minimal.
class AppleTokenClaims {
  /// Apple subject — the pseudonymous, team-scoped user id. IN-MEMORY ONLY.
  final String? sub;

  /// Audience — always the requesting app's bundle id (String or List in JWT).
  final List<String> aud;

  /// Issuer — https://appleid.apple.com (diagnostic only).
  final String? iss;

  const AppleTokenClaims({this.sub, this.aud = const [], this.iss});

  bool get hasSub => sub != null && sub!.isNotEmpty;

  bool audContains(String bundleId) => aud.contains(bundleId);

  /// Deliberately DOES NOT print sub/aud — avoids accidental leakage via logs.
  @override
  String toString() =>
      'AppleTokenClaims(hasSub: $hasSub, audCount: ${aud.length})';
}

/// Decode the payload claims of an Apple identity token, or null if malformed.
/// Signature is NOT verified (see file header).
AppleTokenClaims? decodeAppleIdentityTokenClaims(String? idToken) {
  if (idToken == null || idToken.isEmpty) {
    return null;
  }
  final parts = idToken.split('.');
  if (parts.length != 3) {
    return null; // not a well-formed JWS compact serialization
  }
  try {
    final payloadJson = _b64UrlDecodeToString(parts[1]);
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map) {
      return null;
    }
    final subVal = decoded['sub'];
    final issVal = decoded['iss'];
    final audRaw = decoded['aud'];

    final aud = <String>[];
    if (audRaw is String) {
      aud.add(audRaw);
    } else if (audRaw is List) {
      for (final a in audRaw) {
        if (a is String) {
          aud.add(a);
        }
      }
    }

    return AppleTokenClaims(
      sub: subVal is String ? subVal : null,
      aud: List.unmodifiable(aud),
      iss: issVal is String ? issVal : null,
    );
  } catch (_) {
    return null; // any decode/parse failure → malformed
  }
}

/// base64url (no-padding tolerant) → UTF-8 String. Throws on invalid input,
/// which the caller catches and maps to "malformed".
String _b64UrlDecodeToString(String segment) =>
    utf8.decode(base64Url.decode(base64Url.normalize(segment)));
