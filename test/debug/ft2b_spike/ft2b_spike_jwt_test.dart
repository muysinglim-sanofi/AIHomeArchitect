// FT2-B spike — Apple identity-token claim reader tests (no network, no device).
// Uses SYNTHETIC, obviously-fake JWTs (never a real Apple token). Proves the
// parser reads sub/aud safely, tolerates base64url-without-padding, and refuses
// malformed input.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/debug/ft2b_spike/ft2b_spike_jwt.dart';

/// Build a synthetic JWS-compact token: base64url(header).base64url(payload).sig
/// with padding stripped (mimics Apple's no-padding tokens). NOT signed.
String _fakeJwt(Object payload) {
  String seg(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  final header = seg({'alg': 'RS256', 'kid': 'fake'});
  return '$header.${seg(payload)}.ZmFrZS1zaWc';
}

void main() {
  group('decodeAppleIdentityTokenClaims', () {
    test('valid token with sub + aud String', () {
      final t = _fakeJwt({
        'iss': 'https://appleid.apple.com',
        'sub': '001999.fakesubject.0001',
        'aud': 'com.aydenstudio.app',
      });
      final c = decodeAppleIdentityTokenClaims(t);
      expect(c, isNotNull);
      expect(c!.hasSub, isTrue);
      expect(c.sub, '001999.fakesubject.0001');
      expect(c.aud, ['com.aydenstudio.app']);
      expect(c.iss, 'https://appleid.apple.com');
    });

    test('tolerates base64url without padding', () {
      // A payload whose base64 length is not a multiple of 4 (needs padding).
      final t = _fakeJwt({'sub': 'x', 'aud': 'com.aydenstudio.app'});
      // sanity: our fake segments are already unpadded
      expect(t.contains('='), isFalse);
      final c = decodeAppleIdentityTokenClaims(t);
      expect(c, isNotNull);
      expect(c!.sub, 'x');
    });

    test('malformed — not 3 segments → null', () {
      expect(decodeAppleIdentityTokenClaims('only.two'), isNull);
      expect(decodeAppleIdentityTokenClaims('nodots'), isNull);
      expect(decodeAppleIdentityTokenClaims(''), isNull);
      expect(decodeAppleIdentityTokenClaims(null), isNull);
    });

    test('malformed — payload not valid base64/JSON → null', () {
      expect(decodeAppleIdentityTokenClaims('aaa.@@@.bbb'), isNull);
    });

    test('sub missing → hasSub false, aud still parsed', () {
      final t = _fakeJwt({'aud': 'com.aydenstudio.app'});
      final c = decodeAppleIdentityTokenClaims(t);
      expect(c, isNotNull);
      expect(c!.hasSub, isFalse);
      expect(c.sub, isNull);
      expect(c.audContains('com.aydenstudio.app'), isTrue);
    });

    test('aud as List → all string entries kept', () {
      final t = _fakeJwt({
        'sub': 's',
        'aud': ['com.aydenstudio.app', 'other.client'],
      });
      final c = decodeAppleIdentityTokenClaims(t);
      expect(c!.aud, ['com.aydenstudio.app', 'other.client']);
      expect(c.audContains('com.aydenstudio.app'), isTrue);
    });

    test('aud incorrect (wrong audience) → audContains false', () {
      final t = _fakeJwt({'sub': 's', 'aud': 'com.example.wrong'});
      final c = decodeAppleIdentityTokenClaims(t);
      expect(c!.audContains('com.aydenstudio.app'), isFalse);
    });

    test('toString exposes neither sub nor aud values', () {
      final t = _fakeJwt({
        'sub': 'SECRETsubVALUE',
        'aud': 'com.aydenstudio.app',
      });
      final c = decodeAppleIdentityTokenClaims(t);
      final dump = c.toString();
      expect(dump.contains('SECRETsubVALUE'), isFalse);
      expect(dump.contains('com.aydenstudio.app'), isFalse);
    });
  });
}
