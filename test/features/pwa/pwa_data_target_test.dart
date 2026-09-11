// Which database schema and image bucket each build talks to. The first
// production build queried `pwa_staging` on the production project (PGRST106,
// 2026-09-11) because the repository hard-coded it. DATA01-07.

import 'dart:io';

import 'package:ai_home_architect/features/pwa/config/pwa_environment.dart';
import 'package:flutter_test/flutter_test.dart';

PwaEnvironment _staging() => PwaEnvironment.parse({
  'AYDEN_ENV': 'staging',
  'AYDEN_STAGING_SUPABASE_URL': 'https://eedcahzekpgxvvfxufbk.supabase.co',
  'AYDEN_STAGING_PROJECT_REF': 'eedcahzekpgxvvfxufbk',
  'AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_test_only',
  'AYDEN_STAGING_BACKEND_URL': 'https://ayden-api-staging.fly.dev',
});

PwaEnvironment _production() => PwaEnvironment.parse({
  'AYDEN_ENV': 'production',
  'AYDEN_PROD_SUPABASE_URL': 'https://vtxkciupyafukhdsgxgw.supabase.co',
  'AYDEN_PROD_PROJECT_REF': 'vtxkciupyafukhdsgxgw',
  'AYDEN_PROD_SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_test_only',
  'AYDEN_PROD_BACKEND_URL': 'https://api.aydenstudio.com',
});

void main() {
  test('DATA01: a staging build uses pwa_staging and its bucket', () {
    final e = _staging();
    expect(e.dataSchema, 'pwa_staging');
    expect(e.imageBucket, 'pwa-staging-images');
  });

  test('DATA02: a production build uses pwa and its bucket', () {
    final e = _production();
    expect(e.dataSchema, 'pwa');
    expect(e.imageBucket, 'pwa-images');
  });

  test('DATA03: a production build can never emit a staging schema or bucket', () {
    final e = _production();
    expect(e.dataSchema.contains('staging'), isFalse);
    expect(e.imageBucket.contains('staging'), isFalse);
  });

  test('DATA04: a staging build can never emit the production schema or bucket', () {
    final e = _staging();
    expect(e.dataSchema, isNot(kProductionDataSchema));
    expect(e.imageBucket, isNot(kProductionImageBucket));
  });

  test('DATA05: a mock build has no database — asking is refused', () {
    final e = PwaEnvironment.parse({'AYDEN_ENV': 'mock'});
    expect(() => e.dataSchema, throwsA(isA<PwaConfigError>()));
    expect(() => e.imageBucket, throwsA(isA<PwaConfigError>()));
  });

  test('DATA06: the repository names no schema and no bucket of its own', () {
    final src = File(
      'lib/features/pwa/data/supabase_pwa_persistence_repository.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(src.contains("schema('pwa"), isFalse);
    expect(src.contains("'pwa_staging'"), isFalse);
    expect(src.contains("'pwa-staging-images'"), isFalse);
    expect(src.contains("'pwa-images'"), isFalse);
    expect(src.contains('_c.schema(_staging.environment.dataSchema)'), isTrue);
    expect(src.contains('_staging.environment.imageBucket'), isTrue);
  });

  test('DATA07: the pairs match the backend (backend/pwa_target.py)', () {
    // The backend resolves the same values from PWA_TARGET; a drift here is a
    // client and a server writing to two different places.
    expect(kProductionDataSchema, 'pwa');
    expect(kProductionImageBucket, 'pwa-images');
    expect(kStagingDataSchema, 'pwa_staging');
    expect(kStagingImageBucket, 'pwa-staging-images');
  });
}
