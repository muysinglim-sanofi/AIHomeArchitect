import 'dart:convert';

import 'package:ai_home_architect/shared/reveal/reveal_export_spec.dart';
import 'package:ai_home_architect/shared/reveal/reveal_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RevealExportSpec', () {
    test('round-trips losslessly through JSON for every preset', () {
      for (final profile in RevealProfile.presets.values) {
        final spec = RevealExportSpec(
          beforeUrl: 'https://example/b.jpg',
          afterUrl: 'https://example/a.jpg',
          profile: profile,
          aspect: 9 / 16,
          watermark: true,
        );
        final encoded = jsonEncode(spec.toJson());
        final decoded = RevealExportSpec.fromJson(
            jsonDecode(encoded) as Map<String, dynamic>);
        expect(jsonEncode(decoded.toJson()), encoded);
      }
    });

    test('carries the full timeline contract needed for server parity', () {
      final json = RevealExportSpec(
        beforeUrl: 'b',
        afterUrl: 'a',
        profile: RevealProfile.cinematic,
        aspect: 9 / 16,
      ).toJson();

      final profile = json['profile'] as Map<String, dynamic>;
      expect(profile['id'], 'cinematic');
      expect(profile['startDelayMs'], isA<num>());
      expect(profile['keyframes'], isA<List>());
      expect(profile['zoomFrom'], 1.0);
      expect(profile['zoomTo'], 1.05);
      expect(profile['feather'], 0.06);

      final firstKf = (profile['keyframes'] as List).first as Map;
      expect(firstKf['atMs'], isA<num>());
      expect(firstKf['progress'], isA<num>());
      expect(firstKf['curveToNext'], isA<Map>());
    });

    test('profile round-trips independently', () {
      for (final profile in RevealProfile.presets.values) {
        final back = RevealProfile.fromJson(profile.toJson());
        expect(jsonEncode(back.toJson()), jsonEncode(profile.toJson()));
      }
    });
  });
}
