// Batch 3.1 — mobile/PWA entrypoint & router boundary (source-level assertions).
//
// Proves the two accidental coupling roots found in Step 1 are gone: the mobile
// entrypoint (lib/main.dart) and the mobile router (lib/core/router/app_router)
// reference NO features/pwa code, and the PWA entrypoint (lib/main_pwa.dart)
// pulls in NO mobile/production stack. Plain string checks, no dependency graph.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

Iterable<String> _importLines(String src) =>
    src.split('\n').where((l) => l.trimLeft().startsWith('import '));

bool _importsAny(String src, String needle) =>
    _importLines(src).any((l) => l.contains(needle));

void main() {
  const mainDart = 'lib/main.dart';
  const mainPwa = 'lib/main_pwa.dart';
  const router = 'lib/core/router/app_router.dart';

  group('mobile entrypoint is PWA-free', () {
    test('MOBILE01: lib/main.dart imports no features/pwa path', () {
      expect(_importsAny(_read(mainDart), 'features/pwa'), isFalse);
    });

    test('MOBILE02: lib/main.dart references no PWA/staging symbols', () {
      final src = _read(mainDart);
      for (final token in const [
        'PwaEnvironment',
        'PwaMockApp',
        'PwaBootRestore',
        'PwaStagingSupabaseClient',
        'SupabasePwaPersistenceRepository',
        'AYDEN_STAGING_',
        'eedcahzekpgxvvfxufbk',
      ]) {
        expect(src.contains(token), isFalse, reason: token);
      }
    });
  });

  group('mobile router is PWA-free', () {
    test('MOBILE03: app_router.dart imports no features/pwa path', () {
      expect(_importsAny(_read(router), 'features/pwa'), isFalse);
    });

    test('MOBILE04/ROUTER01: app_router builds no PWA widget', () {
      final src = _read(router);
      expect(src.contains('PwaExperience'), isFalse);
      expect(src.contains('PwaEntryScreen'), isFalse);
      expect(src.contains('kPwaRoutePath'), isFalse);
      expect(src.contains("'/pwa'"), isFalse);
    });
  });

  group('PWA entrypoint is mobile-free', () {
    test(
      'PWA01: lib/main_pwa.dart exists and imports the PWA app + config',
      () {
        expect(File(mainPwa).existsSync(), isTrue);
        final src = _read(mainPwa);
        expect(
          _importsAny(src, 'features/pwa/presentation/pwa_mock_app.dart'),
          isTrue,
        );
        expect(
          _importsAny(src, 'features/pwa/config/pwa_environment.dart'),
          isTrue,
        );
      },
    );

    test('PWA02: lib/main_pwa.dart imports no mobile/production stack', () {
      final src = _read(mainPwa);
      for (final banned in const [
        'core/env/app_environment.dart',
        'core/router/app_router.dart',
        'revenuecat_service',
        'firebase_messaging',
        'firebase_core',
        'local_notification_service',
        'push_service',
        'core/auth/keychain_local_storage',
        'guest',
        'wallet',
        'me_status_provider',
      ]) {
        expect(_importsAny(src, banned), isFalse, reason: banned);
      }
    });

    test('PWA03: main_pwa.dart makes no direct Supabase.initialize call', () {
      // The mock path is fully offline; the staging path delegates init to the
      // isolated PwaStagingSupabaseClient, never inlining the call itself.
      expect(_read(mainPwa).contains('Supabase.initialize('), isFalse);
    });

    test('PWA04: staging boot uses the isolated client + fail-closed env', () {
      final src = _read(mainPwa);
      expect(src.contains('PwaEnvironment.current()'), isTrue); // fails closed
      expect(src.contains('PwaStagingSupabaseClient.create'), isTrue);
      expect(src.contains('SupabasePwaPersistenceRepository'), isTrue);
    });
  });
}
