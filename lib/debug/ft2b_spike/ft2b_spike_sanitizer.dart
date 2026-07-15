/// FT2-B spike — PURE, testable log/report redaction.
///
/// NOTHING sensitive may ever reach a log line or the copyable report: no JWT,
/// no Apple identity token, no raw nonce, no Bearer header, no email, no
/// Supabase key. Every user-facing string passes through [sanitizeText] first.
/// This file has NO Flutter/SDK dependency so it is trivially unit-tested.
library;

/// Hard cap on any surfaced message length (defense against dumping a large
/// blob that might embed a secret we did not anticipate).
const int kMaxSanitizedMessageLength = 300;

// Order matters: Bearer before JWT (so "Bearer eyJ..." is caught whole), then
// standalone JWTs, then emails, then sensitive key=value pairs.
final RegExp _bearerRe = RegExp(r'[Bb]earer\s+[A-Za-z0-9._~+/=-]+');
final RegExp _jwtRe = RegExp(
  r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)?',
);
final RegExp _emailRe = RegExp(
  r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
);
// The value class excludes brackets so an already-inserted placeholder like
// `[REDACTED_BEARER]` is NOT re-clobbered by a later key match (e.g.
// `Authorization: [REDACTED_BEARER]`), keeping each marker meaningful.
final RegExp _sensitiveKvRe = RegExp(
  r'(nonce|id[_-]?token|access[_-]?token|refresh[_-]?token|authorization|'
  r'apikey|api[_-]?key|password|secret)(\s*[:=]\s*)([^\s,;&})"\[\]]+)',
  caseSensitive: false,
);

// JSON-quoted form `"nonce":"rawValue"` — the plain k=v rule above cannot see
// the value (it begins with a quote). Real tokens are JWTs caught by _jwtRe, but
// this closes the residual (e.g. a raw nonce embedded in a JSON error body).
final RegExp _sensitiveJsonKvRe = RegExp(
  r'"(nonce|id[_-]?token|access[_-]?token|refresh[_-]?token|authorization|'
  r'apikey|api[_-]?key|password|secret)"(\s*:\s*)"([^"]*)"',
  caseSensitive: false,
);

/// Redact then bound [input]. Returns '' for null/empty. Keeps the human-useful
/// remainder of a Supabase error message intact.
String sanitizeText(
  String? input, {
  int maxLength = kMaxSanitizedMessageLength,
}) {
  if (input == null || input.isEmpty) {
    return '';
  }
  var s = input;
  s = s.replaceAll(_bearerRe, '[REDACTED_BEARER]');
  s = s.replaceAll(_jwtRe, '[REDACTED_JWT]');
  s = s.replaceAll(_emailRe, '[REDACTED_EMAIL]');
  s = s.replaceAllMapped(_sensitiveKvRe, (m) => '${m[1]}${m[2]}[REDACTED]');
  s = s.replaceAllMapped(
    _sensitiveJsonKvRe,
    (m) => '"${m[1]}"${m[2]}"[REDACTED]"',
  );
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.length > maxLength) {
    s = '${s.substring(0, maxLength)}…[truncated]';
  }
  return s;
}
