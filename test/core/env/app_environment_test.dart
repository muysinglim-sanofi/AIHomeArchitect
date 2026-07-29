// Batch 1A — targeted tests for the web environment safety guard.
//
// These exercise the PURE validation logic (AppEnvironment.validateWebConfig)
// with no web runtime, no dotenv, no network. They prove that Flutter Web
// cannot start without an explicit non-production configuration and rejects
// known production endpoints.

import 'package:ai_home_architect/core/env/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEnvironment.validateWebConfig — accepts explicit non-prod', () {
    test('valid staging → returns trimmed, web env', () {
      final env = AppEnvironment.validateWebConfig(
        envName: 'staging',
        apiBaseUrl: 'https://api.staging.invalid',
        supabaseUrl: 'https://project.staging.invalid',
        supabaseAnonKey: 'staging-placeholder-key',
      );
      expect(env.isWeb, isTrue);
      expect(env.name, 'staging');
      expect(env.apiBaseUrl, 'https://api.staging.invalid');
      expect(env.supabaseUrl, 'https://project.staging.invalid');
      expect(env.supabaseAnonKey, 'staging-placeholder-key');
    });

    test('mock env is allowed', () {
      final env = AppEnvironment.validateWebConfig(
        envName: 'mock',
        apiBaseUrl: 'https://api.mock.invalid',
        supabaseUrl: 'https://project.mock.invalid',
        supabaseAnonKey: 'mock-key',
      );
      expect(env.name, 'mock');
    });

    test('env name is case-insensitive and trimmed', () {
      final env = AppEnvironment.validateWebConfig(
        envName: '  Staging ',
        apiBaseUrl: '  https://api.staging.invalid ',
        supabaseUrl: 'https://project.staging.invalid',
        supabaseAnonKey: 'k',
      );
      expect(env.name, 'staging');
      expect(env.apiBaseUrl, 'https://api.staging.invalid');
    });
  });

  group('AppEnvironment.validateWebConfig — rejects unsafe environments', () {
    test('empty AYDEN_ENV fails fast', () {
      expect(
        () => AppEnvironment.validateWebConfig(
          envName: '',
          apiBaseUrl: 'https://api.staging.invalid',
          supabaseUrl: 'https://project.staging.invalid',
          supabaseAnonKey: 'k',
        ),
        throwsA(isA<WebEnvironmentError>()
            .having((e) => e.message, 'message', contains('AYDEN_ENV'))),
      );
    });

    test('AYDEN_ENV=production is refused', () {
      expect(
        () => AppEnvironment.validateWebConfig(
          envName: 'production',
          apiBaseUrl: 'https://api.staging.invalid',
          supabaseUrl: 'https://project.staging.invalid',
          supabaseAnonKey: 'k',
        ),
        throwsA(isA<WebEnvironmentError>()),
      );
    });

    test('AYDEN_ENV=prod is refused', () {
      expect(
        () => AppEnvironment.validateWebConfig(
          envName: 'prod',
          apiBaseUrl: 'https://api.staging.invalid',
          supabaseUrl: 'https://project.staging.invalid',
          supabaseAnonKey: 'k',
        ),
        throwsA(isA<WebEnvironmentError>()),
      );
    });

    test('unknown env name is refused', () {
      expect(
        () => AppEnvironment.validateWebConfig(
          envName: 'qa',
          apiBaseUrl: 'https://api.staging.invalid',
          supabaseUrl: 'https://project.staging.invalid',
          supabaseAnonKey: 'k',
        ),
        throwsA(isA<WebEnvironmentError>()
            .having((e) => e.message, 'message', contains('unknown AYDEN_ENV'))),
      );
    });
  });

  group('AppEnvironment.validateWebConfig — missing values fail fast', () {
    test('missing API_BASE_URL is named in the error', () {
      expect(
        () => AppEnvironment.validateWebConfig(
          envName: 'staging',
          apiBaseUrl: '',
          supabaseUrl: 'https://project.staging.invalid',
          supabaseAnonKey: 'k',
        ),
        throwsA(isA<WebEnvironmentError>()
            .having((e) => e.message, 'message', contains('API_BASE_URL'))),
      );
    });

    test('missing SUPABASE_URL is named in the error', () {
      expect(
        () => AppEnvironment.validateWebConfig(
          envName: 'staging',
          apiBaseUrl: 'https://api.staging.invalid',
          supabaseUrl: '',
          supabaseAnonKey: 'k',
        ),
        throwsA(isA<WebEnvironmentError>()
            .having((e) => e.message, 'message', contains('SUPABASE_URL'))),
      );
    });

    test('missing SUPABASE_ANON_KEY is named in the error', () {
      expect(
        () => AppEnvironment.validateWebConfig(
          envName: 'staging',
          apiBaseUrl: 'https://api.staging.invalid',
          supabaseUrl: 'https://project.staging.invalid',
          supabaseAnonKey: '   ',
        ),
        throwsA(isA<WebEnvironmentError>()
            .having((e) => e.message, 'message', contains('SUPABASE_ANON_KEY'))),
      );
    });
  });

  group('AppEnvironment.validateWebConfig — rejects production endpoints', () {
    test('production backend host is rejected by default', () {
      expect(
        () => AppEnvironment.validateWebConfig(
          envName: 'staging',
          apiBaseUrl: 'https://${AppEnvironment.kProductionBackendHost}',
          supabaseUrl: 'https://project.staging.invalid',
          supabaseAnonKey: 'k',
        ),
        throwsA(isA<WebEnvironmentError>().having(
            (e) => e.message, 'message', contains('production configuration'))),
      );
    });

    test('production Supabase host is rejected by DEFAULT (no AYDEN_BLOCKED_HOSTS needed)', () {
      expect(
        () => AppEnvironment.validateWebConfig(
          envName: 'staging',
          apiBaseUrl: 'https://api.staging.invalid',
          supabaseUrl: 'https://${AppEnvironment.kProductionSupabaseHost}',
          supabaseAnonKey: 'k',
        ),
        throwsA(isA<WebEnvironmentError>().having(
            (e) => e.message, 'message', contains('production configuration'))),
      );
    });

    test('a production Supabase host supplied via AYDEN_BLOCKED_HOSTS is rejected', () {
      expect(
        () => AppEnvironment.validateWebConfig(
          envName: 'staging',
          apiBaseUrl: 'https://api.staging.invalid',
          supabaseUrl: 'https://prod-abc123.supabase.co',
          supabaseAnonKey: 'k',
          blockedHostsCsv: 'prod-abc123.supabase.co, another.prod.host',
        ),
        throwsA(isA<WebEnvironmentError>()),
      );
    });

    test('a staging Supabase host NOT in the blocklist is accepted', () {
      final env = AppEnvironment.validateWebConfig(
        envName: 'staging',
        apiBaseUrl: 'https://api.staging.invalid',
        supabaseUrl: 'https://staging-xyz.supabase.co',
        supabaseAnonKey: 'k',
        blockedHostsCsv: 'prod-abc123.supabase.co',
      );
      expect(env.supabaseUrl, 'https://staging-xyz.supabase.co');
    });
  });
}
