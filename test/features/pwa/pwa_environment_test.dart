// Batch 3.0 — environment boundary + boot guard (§28/§32) and production/iOS
// isolation invariants (§39). Pure, offline, no network.

import 'dart:io';

import 'package:ai_home_architect/features/pwa/config/pwa_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('environment parsing (§2/§32)', () {
    test('1. mock parses fully offline (no staging config needed)', () {
      final e = PwaEnvironment.parse({'AYDEN_ENV': 'mock'});
      expect(e.isMock, isTrue);
      expect(e.isStaging, isFalse);
      expect(e.isProduction, isFalse);
    });

    test('2. empty AYDEN_ENV defaults to mock', () {
      expect(PwaEnvironment.parse({}).isMock, isTrue);
    });

    test('3. production is refused (not implemented)', () {
      expect(
        () => PwaEnvironment.parse({'AYDEN_ENV': 'production'}),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('4. unknown environment is refused', () {
      expect(
        () => PwaEnvironment.parse({'AYDEN_ENV': 'prod-ish'}),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('5. staging accepts an allow-listed staging https host', () {
      final e = PwaEnvironment.parse({
        'AYDEN_ENV': 'staging',
        'AYDEN_STAGING_SUPABASE_URL': 'https://abc-staging.supabase.co',
      });
      expect(e.isStaging, isTrue);
      expect(e.stagingTarget, contains('staging'));
    });

    test('6. staging rejects a known production host (denylist)', () {
      expect(
        () => PwaEnvironment.parse({
          'AYDEN_ENV': 'staging',
          'AYDEN_STAGING_SUPABASE_URL': 'https://api.aydenstudio.com',
        }),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('7. staging fails CLOSED when no target is configured', () {
      expect(
        () => PwaEnvironment.parse({'AYDEN_ENV': 'staging'}),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('8. staging rejects a non-recognizably-staging host', () {
      expect(
        () => PwaEnvironment.parse({
          'AYDEN_ENV': 'staging',
          'AYDEN_STAGING_SUPABASE_URL': 'https://random.example.com',
        }),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('9. staging rejects non-https (except localhost)', () {
      expect(
        () => PwaEnvironment.parse({
          'AYDEN_ENV': 'staging',
          'AYDEN_STAGING_SUPABASE_URL': 'http://abc-staging.supabase.co',
        }),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('10. staging accepts localhost for a local backend', () {
      final e = PwaEnvironment.parse({
        'AYDEN_ENV': 'staging',
        'AYDEN_STAGING_API_BASE_URL': 'http://localhost:54321',
      });
      expect(e.isStaging, isTrue);
    });

    test('11. migration + seed flags parse explicitly (default false)', () {
      final off = PwaEnvironment.parse({'AYDEN_ENV': 'mock'});
      expect(off.allowStagingMigrations, isFalse);
      expect(off.seedDemo, isFalse);
      final on = PwaEnvironment.parse({
        'AYDEN_ENV': 'staging',
        'AYDEN_STAGING_SUPABASE_URL': 'https://x-staging.supabase.co',
        'AYDEN_ALLOW_STAGING_MIGRATIONS': 'true',
        'AYDEN_STAGING_SEED_DEMO': 'true',
      });
      expect(on.allowStagingMigrations, isTrue);
      expect(on.seedDemo, isTrue);
    });

    test(
      '12b. current() with no dart-define is the offline mock fail-safe',
      () {
        // The real boot entry point: a plain build (no --dart-define) must boot
        // into the offline mock experience, never staging/production.
        expect(PwaEnvironment.current().isMock, isTrue);
      },
    );

    test(
      '12c. staging rejects a non-staging HOST even with a /staging path',
      () {
        // A production host cannot masquerade as staging via the URL path.
        expect(
          () => PwaEnvironment.parse({
            'AYDEN_ENV': 'staging',
            'AYDEN_STAGING_SUPABASE_URL': 'https://prod-host.example/staging',
          }),
          throwsA(isA<PwaConfigError>()),
        );
        expect(
          () => PwaEnvironment.parse({
            'AYDEN_ENV': 'staging',
            'AYDEN_STAGING_SUPABASE_URL': 'https://api.aydenstudio.com/staging',
          }),
          throwsA(isA<PwaConfigError>()),
        );
      },
    );
  });

  group('production / secret isolation (§32/§39)', () {
    Iterable<File> pwaDart() => Directory('lib/features/pwa')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    test('12. no service-role key is USED anywhere in PWA code', () {
      // Dangerous concrete patterns (a key literal, an env name, an identifier)
      // — NOT prose safety notes that say the key must stay server-side.
      for (final f in pwaDart()) {
        final s = f.readAsStringSync();
        expect(
          s.contains('service_role'),
          isFalse,
          reason: '${f.path} literal',
        );
        expect(s.contains('serviceRole'), isFalse, reason: '${f.path} ident');
        expect(
          s.toUpperCase().contains('SUPABASE_SERVICE'),
          isFalse,
          reason: '${f.path} env',
        );
      }
    });

    test(
      '13. staging adapter imports no supabase/http client (offline build)',
      () {
        final imports =
            File('lib/features/pwa/data/staging_pwa_persistence_repository.dart')
                .readAsStringSync()
                .split('\n')
                .where((l) => l.trimLeft().startsWith('import '))
                .join('\n')
                .toLowerCase();
        for (final banned in const [
          'supabase',
          'package:http',
          'package:dio',
        ]) {
          expect(imports.contains(banned), isFalse, reason: banned);
        }
      },
    );

    test(
      '14. no RevenueCat / wallet / production-auth imports in persistence',
      () {
        const files = [
          'lib/features/pwa/config/pwa_environment.dart',
          'lib/features/pwa/data/pwa_persistence_repository.dart',
          'lib/features/pwa/data/mock_pwa_persistence_repository.dart',
          'lib/features/pwa/data/staging_pwa_persistence_repository.dart',
          'lib/features/pwa/data/pwa_project_serialization.dart',
          'lib/features/pwa/data/pwa_project_ops.dart',
          'lib/features/pwa/data/pwa_repository_error.dart',
        ];
        for (final path in files) {
          final imports = File(path)
              .readAsStringSync()
              .split('\n')
              .where((l) => l.trimLeft().startsWith('import '))
              .join('\n')
              .toLowerCase();
          for (final banned in const [
            'purchases_flutter',
            'revenue',
            'wallet',
            'authservice',
            'supabase',
            'dart:html',
            'dart:io',
          ]) {
            expect(
              imports.contains(banned),
              isFalse,
              reason: '$path → $banned',
            );
          }
        }
      },
    );

    test('15. the migration SQL is guarded and isolated (not production)', () {
      final sql = File(
        'supabase/staging/pwa/0001_pwa_staging_foundation.sql',
      ).readAsStringSync();
      expect(sql.contains('ayden_allow_staging_migrations'), isTrue);
      expect(sql.contains('create schema if not exists pwa_staging'), isTrue);
      expect(sql.toLowerCase().contains('enable row level security'), isTrue);
    });

    test('16. env template carries no real secret values', () {
      final env = File('.env.pwa-staging.example').readAsStringSync();
      // Keys present but EMPTY (template only).
      expect(
        RegExp(
          r'AYDEN_STAGING_SUPABASE_ANON_KEY=\s*$',
          multiLine: true,
        ).hasMatch(env),
        isTrue,
      );
      expect(env.toLowerCase().contains('service_role'), isFalse);
    });
  });
}
