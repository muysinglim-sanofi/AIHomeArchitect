// Batch 3.1 — environment boundary + EXACT-allowlist boot guard (§43 config)
// and production/iOS isolation invariants. Pure, offline, no network.

import 'dart:io';

import 'package:ai_home_architect/features/pwa/config/pwa_environment.dart';
import 'package:flutter_test/flutter_test.dart';

/// A well-formed staging config for the ONE authorized project.
Map<String, String> stagingDefines({
  String? url = 'https://eedcahzekpgxvvfxufbk.supabase.co',
  String? ref = kStagingProjectRef,
  String? key = 'sb_publishable_TEST_placeholder_not_a_real_key',
  String? allowMig,
  String? seed,
  String? backend = 'http://127.0.0.1:8000',
}) => {
  'AYDEN_ENV': 'staging',
  'AYDEN_STAGING_SUPABASE_URL': ?url,
  'AYDEN_STAGING_PROJECT_REF': ?ref,
  'AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY': ?key,
  'AYDEN_STAGING_BACKEND_URL': ?backend,
  'AYDEN_ALLOW_STAGING_MIGRATIONS': ?allowMig,
  'AYDEN_STAGING_SEED_DEMO': ?seed,
};

void main() {
  group('environment parsing — env selection', () {
    test('mock parses fully offline (no staging config needed)', () {
      final e = PwaEnvironment.parse({'AYDEN_ENV': 'mock'});
      expect(e.isMock, isTrue);
      expect(e.isStaging, isFalse);
      expect(e.isProduction, isFalse);
    });

    test('empty AYDEN_ENV defaults to mock', () {
      expect(PwaEnvironment.parse({}).isMock, isTrue);
    });

    test('9. production environment is refused (not implemented)', () {
      expect(
        () => PwaEnvironment.parse({'AYDEN_ENV': 'production'}),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('unknown environment is refused', () {
      expect(
        () => PwaEnvironment.parse({'AYDEN_ENV': 'prod-ish'}),
        throwsA(isA<PwaConfigError>()),
      );
    });
  });

  group('staging guard — §43 host/ref/key', () {
    test('1. exact staging host accepted', () {
      final e = PwaEnvironment.parse(stagingDefines());
      expect(e.isStaging, isTrue);
      expect(e.stagingSupabaseUrl, 'https://eedcahzekpgxvvfxufbk.supabase.co');
    });

    test('2. exact staging project ref accepted / exposed', () {
      final e = PwaEnvironment.parse(stagingDefines());
      expect(e.stagingProjectRef, kStagingProjectRef);
    });

    test('3. similar/lookalike host rejected (exact match only)', () {
      for (final bad in const [
        'https://eedcahzekpgxvvfxufbk.supabase.co.evil.com',
        'https://xeedcahzekpgxvvfxufbk.supabase.co',
        'https://eedcahzekpgxvvfxufbk.supabase.co.',
        'https://eedcahzekpgxvvfxufbkx.supabase.co',
      ]) {
        expect(
          () => PwaEnvironment.parse(stagingDefines(url: bad)),
          throwsA(isA<PwaConfigError>()),
          reason: bad,
        );
      }
    });

    test('4. staging host in URL PATH but not host is rejected', () {
      expect(
        () => PwaEnvironment.parse(
          stagingDefines(
            url: 'https://evil.example/eedcahzekpgxvvfxufbk.supabase.co',
          ),
        ),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('5. http staging host rejected; explicit localhost accepted', () {
      expect(
        () => PwaEnvironment.parse(
          stagingDefines(url: 'http://eedcahzekpgxvvfxufbk.supabase.co'),
        ),
        throwsA(isA<PwaConfigError>()),
      );
      // localhost dev over http is allowed (no project ref required locally).
      final local = PwaEnvironment.parse(
        stagingDefines(url: 'http://localhost:54321', ref: null),
      );
      expect(local.isStaging, isTrue);
    });

    test('6. production denylist host rejected (real prod ref)', () {
      for (final prod in const [
        'https://vtxkciupyafukhdsgxgw.supabase.co',
        'https://api.aydenstudio.com',
      ]) {
        expect(
          () => PwaEnvironment.parse(stagingDefines(url: prod)),
          throwsA(isA<PwaConfigError>()),
          reason: prod,
        );
      }
    });

    test('7. missing URL rejected (fail closed, no fallback)', () {
      expect(
        () => PwaEnvironment.parse(stagingDefines(url: null)),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('8. missing publishable key rejected', () {
      expect(
        () => PwaEnvironment.parse(stagingDefines(key: null)),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('8b. a secret/service_role key in the client is rejected (§3)', () {
      expect(
        () => PwaEnvironment.parse(
          stagingDefines(key: 'sb_secret_should_never_be_here'),
        ),
        throwsA(isA<PwaConfigError>()),
      );
      // A service_role JWT (role claim) is rejected too.
      const serviceRoleJwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig';
      expect(
        () => PwaEnvironment.parse(stagingDefines(key: serviceRoleJwt)),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('ref must match the URL host (cross-check)', () {
      expect(
        () => PwaEnvironment.parse(stagingDefines(ref: 'someotherref12345678')),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('migration + seed flags parse explicitly (default false)', () {
      final off = PwaEnvironment.parse({'AYDEN_ENV': 'mock'});
      expect(off.allowStagingMigrations, isFalse);
      expect(off.seedDemo, isFalse);
      final on = PwaEnvironment.parse(
        stagingDefines(allowMig: 'true', seed: 'true'),
      );
      expect(on.allowStagingMigrations, isTrue);
      expect(on.seedDemo, isTrue);
    });

    test(
      '10/12. current() with no dart-define is the offline mock fail-safe',
      () {
        expect(PwaEnvironment.current().isMock, isTrue);
      },
    );
  });

  group('production / secret isolation', () {
    Iterable<File> pwaDart() => Directory('lib/features/pwa')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    test('no service-role key literal/identifier/env anywhere in PWA code', () {
      for (final f in pwaDart()) {
        final s = f.readAsStringSync();
        // pwa_environment.dart legitimately NAMES 'service_role' to REJECT it.
        if (f.path
            .replaceAll('\\', '/')
            .endsWith('config/pwa_environment.dart')) {
          continue;
        }
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

    test('11/12. staging never reads the production env / prod Supabase', () {
      // The exact production ref must be in the guard's DENYLIST (rejected),
      // never used as a target; and the PWA guard must not import the prod env.
      final guard = File(
        'lib/features/pwa/config/pwa_environment.dart',
      ).readAsStringSync();
      expect(
        guard.contains('vtxkciupyafukhdsgxgw'),
        isTrue,
        reason: 'prod ref must be denylisted',
      );
      expect(
        guard.contains("import '../../../core/env/app_environment.dart'"),
        isFalse,
        reason: 'staging guard must not import the production env',
      );
    });

    test('migration SQL is guarded and isolated (not production)', () {
      final sql = File(
        'supabase/staging/pwa/0001_pwa_staging_foundation.sql',
      ).readAsStringSync();
      expect(sql.contains('ayden_allow_staging_migrations'), isTrue);
      expect(sql.contains('create schema if not exists pwa_staging'), isTrue);
      expect(sql.toLowerCase().contains('enable row level security'), isTrue);
    });

    test('JSON env template carries no real secret values', () {
      final env = File('.env.pwa-staging.example.json').readAsStringSync();
      expect(
        env.contains('"AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY": ""'),
        isTrue,
      );
      expect(env.toLowerCase().contains('service_role'), isFalse);
      expect(env.toLowerCase().contains('sb_secret_'), isFalse);
    });
  });

  // ── The generation backend origin ─────────────────────────────────────────
  // The client hands this origin the user's session token, so the guard is
  // exact-origin: scheme, host AND port all decide. Everything else fails
  // closed rather than resolving to "probably fine".
  group('staging guard — generation backend origin', () {
    test('the authorized local origins are accepted and exposed', () {
      for (final origin in kStagingBackendOriginAllowlist) {
        final e = PwaEnvironment.parse(stagingDefines(backend: origin));
        expect(e.stagingBackendUrl, origin);
      }
    });

    test('an absent backend URL refuses to boot', () {
      expect(
        () => PwaEnvironment.parse(stagingDefines(backend: null)),
        throwsA(isA<PwaConfigError>()),
      );
      expect(
        () => PwaEnvironment.parse(stagingDefines(backend: '   ')),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('a production backend host is refused by name', () {
      for (final bad in const [
        'https://api.aydenstudio.com',
        'https://vtxkciupyafukhdsgxgw.supabase.co',
      ]) {
        expect(
          () => PwaEnvironment.parse(stagingDefines(backend: bad)),
          throwsA(isA<PwaConfigError>()),
          reason: '$bad must never be reachable from staging',
        );
      }
    });

    test('a plain-http remote host is refused', () {
      expect(
        () => PwaEnvironment.parse(
          stagingDefines(backend: 'http://staging.example.com:8000'),
        ),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('the port is part of the decision', () {
      expect(
        () => PwaEnvironment.parse(
          stagingDefines(backend: 'http://127.0.0.1:9000'),
        ),
        throwsA(isA<PwaConfigError>()),
      );
      expect(
        () => PwaEnvironment.parse(stagingDefines(backend: 'http://127.0.0.1')),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('the scheme is part of the decision', () {
      expect(
        () => PwaEnvironment.parse(
          stagingDefines(backend: 'https://127.0.0.1:8000'),
        ),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('a lookalike host is refused (no substring matching)', () {
      for (final bad in const [
        'http://127.0.0.1.evil.com:8000',
        'http://localhost.evil.com:8000',
        'http://evil.com:8000/127.0.0.1:8000',
      ]) {
        expect(
          () => PwaEnvironment.parse(stagingDefines(backend: bad)),
          throwsA(isA<PwaConfigError>()),
          reason: '$bad is not the local backend',
        );
      }
    });

    test('a path or query on the origin is refused', () {
      for (final bad in const [
        'http://127.0.0.1:8000/generate',
        'http://127.0.0.1:8000?token=x',
        'http://127.0.0.1:8000#frag',
      ]) {
        expect(
          () => PwaEnvironment.parse(stagingDefines(backend: bad)),
          throwsA(isA<PwaConfigError>()),
          reason: '$bad is not a bare origin',
        );
      }
    });

    test('a trailing slash is still the same origin', () {
      final e = PwaEnvironment.parse(
        stagingDefines(backend: 'http://127.0.0.1:8000/'),
      );
      expect(e.stagingBackendUrl, 'http://127.0.0.1:8000/');
    });

    test('mock needs no backend URL at all', () {
      final e = PwaEnvironment.parse({'AYDEN_ENV': 'mock'});
      expect(e.stagingBackendUrl, isNull);
    });

    test('the allowlist itself holds no remote entry', () {
      // A remote staging domain is added here deliberately, in review — never
      // inferred at runtime from something that merely looks like staging.
      for (final origin in kStagingBackendOriginAllowlist) {
        final host = Uri.parse(origin).host;
        expect(
          host == '127.0.0.1' || host == 'localhost',
          isTrue,
          reason: '$origin is not local',
        );
      }
    });
  });
}
