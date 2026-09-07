// The PRODUCTION build target — implemented 2026-09-04, guarded like staging.
//
// Until Phase B1 `AYDEN_ENV=production` threw outright, and that was the right
// answer while no production deployment existed. It now resolves — but only
// against an EXACT project, an EXACT ref that matches that project's host, a
// key proved not to be a secret, and an EXACT backend origin. These tests are
// those conditions, plus the two symmetric ones that matter most:
//
//   * a PRODUCTION build may not be pointed at STAGING;
//   * a STAGING build may still not be pointed at PRODUCTION (unchanged).
//
// Nothing here contacts a network. `PwaEnvironment.parse` is a pure function
// over a define map, which is why the guard can be tested at all.

import 'package:ai_home_architect/features/pwa/config/pwa_environment.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// A publishable key shaped like the real ones: a JWT whose role is `anon`.
/// (header.payload.signature — only the payload is ever read.)
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
    '.eyJyb2xlIjoiYW5vbiIsInJlZiI6InZ0eGtjaXVweWFmdWtoZHNneHZ3In0'
    '.c2ln';

/// A key that must never reach a browser bundle.
const _serviceKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
    '.eyJyb2xlIjoic2VydmljZV9yb2xlIn0'
    '.c2ln';

Map<String, String> prodDefines({
  String url = 'https://vtxkciupyafukhdsgxgw.supabase.co',
  String ref = 'vtxkciupyafukhdsgxgw',
  String key = _anonKey,
  String backend = 'https://api.aydenstudio.com',
}) => {
      'AYDEN_ENV': 'production',
      'AYDEN_PROD_SUPABASE_URL': url,
      'AYDEN_PROD_PROJECT_REF': ref,
      'AYDEN_PROD_SUPABASE_PUBLISHABLE_KEY': key,
      'AYDEN_PROD_BACKEND_URL': backend,
    };

void main() {
  group('PROD01  a complete production configuration resolves', () {
    test('and every value is the production one', () {
      final e = PwaEnvironment.parse(prodDefines());
      expect(e.isProduction, isTrue);
      expect(e.isStaging, isFalse);
      expect(e.isRemote, isTrue);
      expect(e.supabaseUrl, 'https://vtxkciupyafukhdsgxgw.supabase.co');
      expect(e.projectRef, 'vtxkciupyafukhdsgxgw');
      expect(e.publishableKey, _anonKey);
      expect(e.backendUrl, 'https://api.aydenstudio.com');
      // The staging fields stay empty: one build, one target.
      expect(e.stagingSupabaseUrl, isNull);
      expect(e.stagingBackendUrl, isNull);
    });

    test('the API prefix is /pwa in production and /pwa/staging in staging',
        () {
      expect(PwaEnvironment.parse(prodDefines()).apiPrefix, '/pwa');
      final staging = PwaEnvironment.parse({
        'AYDEN_ENV': 'staging',
        'AYDEN_STAGING_SUPABASE_URL':
            'https://eedcahzekpgxvvfxufbk.supabase.co',
        'AYDEN_STAGING_PROJECT_REF': 'eedcahzekpgxvvfxufbk',
        'AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY': _anonKey,
        'AYDEN_STAGING_BACKEND_URL': 'https://ayden-api-staging.fly.dev',
      });
      expect(staging.apiPrefix, '/pwa/staging');
      expect(staging.isProduction, isFalse);
      expect(staging.isRemote, isTrue);
    });
  });

  group('PROD02  a production build cannot be pointed at staging', () {
    test('not the staging Supabase project', () {
      expect(
        () => PwaEnvironment.parse(prodDefines(
            url: 'https://eedcahzekpgxvvfxufbk.supabase.co',
            ref: 'eedcahzekpgxvvfxufbk')),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('not the staging API host', () {
      expect(
        () => PwaEnvironment.parse(
            prodDefines(backend: 'https://ayden-api-staging.fly.dev')),
        throwsA(isA<PwaConfigError>()),
      );
    });

    test('and the staging guard still refuses production, as before', () {
      expect(
        () => PwaEnvironment.parse({
          'AYDEN_ENV': 'staging',
          'AYDEN_STAGING_SUPABASE_URL':
              'https://vtxkciupyafukhdsgxgw.supabase.co',
          'AYDEN_STAGING_PROJECT_REF': 'vtxkciupyafukhdsgxgw',
          'AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY': _anonKey,
          'AYDEN_STAGING_BACKEND_URL': 'https://api.aydenstudio.com',
        }),
        throwsA(isA<PwaConfigError>()),
      );
    });
  });

  group('PROD03  every missing or wrong value fails CLOSED', () {
    final cases = <String, Map<String, String>>{
      'no Supabase URL': prodDefines(url: ''),
      'a lookalike host': prodDefines(
          url: 'https://vtxkciupyafukhdsgxgw.supabase.co.evil.com'),
      'plain http': prodDefines(url: 'http://vtxkciupyafukhdsgxgw.supabase.co'),
      'no project ref': prodDefines(ref: ''),
      'a ref that is not the production one': prodDefines(ref: 'someotherref'),
      'no publishable key': prodDefines(key: ''),
      'a SERVICE ROLE key': prodDefines(key: _serviceKey),
      'a sb_secret_ key': prodDefines(key: 'sb_secret_abc123'),
      'no backend URL': prodDefines(backend: ''),
      'an unlisted backend origin':
          prodDefines(backend: 'https://api.example.com'),
      'a backend URL carrying a path':
          prodDefines(backend: 'https://api.aydenstudio.com/pwa'),
      'a plain-http backend': prodDefines(backend: 'http://api.aydenstudio.com'),
    };
    cases.forEach((name, defines) {
      test('refuses: $name', () {
        expect(() => PwaEnvironment.parse(defines),
            throwsA(isA<PwaConfigError>()), reason: name);
      });
    });
  });

  group('PROD04  the API client hangs its routes under the given prefix', () {
    test('the default is the staging prefix — nothing existing moved', () {
      final api = PwaGenerationApi(
        baseUrl: 'https://example.invalid',
        tokenProvider: () async => null,
      );
      addTearDown(api.dispose);
      expect(api, isNotNull);
    });

    test('a production client is built with /pwa', () {
      final api = PwaGenerationApi(
        baseUrl: 'https://api.aydenstudio.com',
        apiPrefix: PwaEnvironment.parse(prodDefines()).apiPrefix,
        tokenProvider: () async => null,
      );
      addTearDown(api.dispose);
      expect(api, isNotNull);
    });
  });

  group('PROD05  the bundle still ships no secret', () {
    test('the production allowlists name addresses, never credentials', () {
      expect(kProductionProjectRef, 'vtxkciupyafukhdsgxgw');
      expect(kProductionHostAllowlist,
          contains('vtxkciupyafukhdsgxgw.supabase.co'));
      expect(kProductionBackendOriginAllowlist,
          equals(<String>['https://api.aydenstudio.com']));
      for (final s in [
        ...kProductionHostAllowlist,
        ...kProductionBackendOriginAllowlist,
        ...kStagingHostDenylist,
      ]) {
        expect(s.contains('sb_secret_'), isFalse);
        expect(s.contains('service_role'), isFalse);
      }
    });
  });
}
