// Batch 3.4 — browser branding: title "Ayden Studio" + Ayden favicon/icons.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

int _pngWidth(List<int> b) =>
    (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];

void main() {
  test('BRAND01: index.html title is exactly "Ayden Studio"', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html.contains('<title>Ayden Studio</title>'), isTrue);
    // Never the wrong capitalizations.
    expect(html.contains('AYDEN Studio'), isFalse);
    expect(html.contains('ai_home_architect'), isFalse);
  });

  test('BRAND02/03: manifest name + short_name are "Ayden Studio"', () {
    final m = jsonDecode(File('web/manifest.json').readAsStringSync()) as Map;
    expect(m['name'], 'Ayden Studio');
    expect(m['short_name'], 'Ayden Studio');
  });

  test(
    'BRAND04: favicon is the regenerated Ayden icon, not the Flutter default',
    () {
      final f = File('web/favicon.png');
      expect(f.existsSync(), isTrue);
      final bytes = f.readAsBytesSync();
      // Regenerated at 64×64 from the official app icon (the default Flutter
      // favicon is 16×16) — a reliable "not default" signal.
      expect(_pngWidth(bytes), 64);
    },
  );

  test('BRAND05: the expected Ayden icon files exist', () {
    for (final p in const [
      'web/favicon.png',
      'web/icons/Icon-192.png',
      'web/icons/Icon-512.png',
      'web/icons/Icon-maskable-192.png',
      'web/icons/Icon-maskable-512.png',
    ]) {
      expect(File(p).existsSync(), isTrue, reason: p);
    }
    // The 512 PWA icon is the full-size Ayden app icon.
    expect(_pngWidth(File('web/icons/Icon-512.png').readAsBytesSync()), 512);
  });

  test('BRAND: source app icon exists (favicon provenance)', () {
    expect(
      File('assets/branding/app_icon_1024_black.png').existsSync(),
      isTrue,
    );
  });

  test(
    'BRAND: runtime MaterialApp title is "Ayden Studio" (overrides <title>)',
    () {
      // Flutter web's MaterialApp.title sets document.title at runtime, so it must
      // also be the exact casing — the PWA shell is the authority for the tab.
      final src = File(
        'lib/features/pwa/presentation/pwa_mock_app.dart',
      ).readAsStringSync();
      expect(src.contains("title: 'Ayden Studio'"), isTrue);
      expect(src.contains("title: 'AYDEN Studio'"), isFalse);
    },
  );
}
