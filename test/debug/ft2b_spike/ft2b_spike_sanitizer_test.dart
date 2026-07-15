// FT2-B spike — redaction unit tests (no network, no device).
// Proves the sanitizer strips every secret class before any string can reach a
// log or the copyable report, while keeping the human-useful error text.
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/debug/ft2b_spike/ft2b_spike_sanitizer.dart';

void main() {
  group('sanitizeText — redaction', () {
    test('redacts a JWT (eyJ...)', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMifQ.SflKxwRJSMeK';
      final out = sanitizeText('token verification failed for $jwt end');
      expect(out.contains('eyJ'), isFalse);
      expect(out.contains('[REDACTED_JWT]'), isTrue);
    });

    test('redacts a Bearer header', () {
      final out = sanitizeText('sent Authorization: Bearer abc123DEF456ghi789');
      expect(out.contains('abc123DEF456ghi789'), isFalse);
      expect(out.contains('[REDACTED_BEARER]'), isTrue);
    });

    test('redacts an email address', () {
      final out = sanitizeText('conflict for john.doe@example.com now');
      expect(out.contains('john.doe@example.com'), isFalse);
      expect(out.contains('[REDACTED_EMAIL]'), isTrue);
    });

    test('redacts nonce= and id_token= values', () {
      final out = sanitizeText('nonce=NoNcEsecret_1 id_token=RaWtokenVALUE');
      expect(out.contains('NoNcEsecret_1'), isFalse);
      expect(out.contains('RaWtokenVALUE'), isFalse);
      expect(out.contains('[REDACTED]'), isTrue);
    });

    test('redacts JSON-quoted "nonce":"…" values', () {
      final out = sanitizeText('body {"nonce":"jsonSecretVALUE","x":1}');
      expect(out.contains('jsonSecretVALUE'), isFalse);
      expect(out.contains('[REDACTED]'), isTrue);
    });

    test('truncates over-long input', () {
      final long = 'x' * 500;
      final out = sanitizeText(long);
      expect(out.length, lessThan(500));
      expect(out.contains('[truncated]'), isTrue);
    });

    test('keeps the useful Supabase error text', () {
      final out = sanitizeText('Identity is already linked to another user');
      expect(out, 'Identity is already linked to another user');
    });

    test('null / empty → empty string', () {
      expect(sanitizeText(null), '');
      expect(sanitizeText(''), '');
    });

    test('combined blob leaves no raw secret', () {
      const blob =
          'AuthApiException: already linked. Bearer abcTOKEN123456 '
          'jwt eyJhbGciOiJI.eyJzdWIi.SIGabc email a@b.com nonce=NONCEsecretVALUE';
      final out = sanitizeText(blob);
      expect(out.contains('abcTOKEN123456'), isFalse);
      expect(out.contains('eyJhbGciOiJI'), isFalse);
      expect(out.contains('a@b.com'), isFalse);
      expect(out.contains('NONCEsecretVALUE'), isFalse);
      // useful text survives
      expect(out.toLowerCase().contains('already linked'), isTrue);
    });
  });
}
