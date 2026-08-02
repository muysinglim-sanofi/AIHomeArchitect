/// Batch 3.0 — the PWA runtime environment boundary (§2 / §28).
///
/// One centralized, explicit boundary between the three environments. There is
/// NO implicit fallback: `mock` is fully offline; `staging` may only target an
/// explicitly configured, allow-listed, non-production host and fails CLOSED
/// otherwise; `production` is not implemented by this batch and refuses to boot.
///
/// Pure Dart (no Flutter, no network, no secrets). The host guard is data, not
/// credentials — the denylist holds production host *substrings* so a staging
/// target that resembles production is rejected before any client is created.
library;

/// The three explicit PWA runtime environments.
enum AydenEnvironment { mock, staging, production }

/// A configuration/boot error. Distinct from data-layer errors so a misconfig
/// surfaces as a controlled "configuration" failure, never a silent fallback.
class PwaConfigError implements Exception {
  const PwaConfigError(this.message);
  final String message;
  @override
  String toString() => 'PwaConfigError: $message';
}

/// Production host / project-ref SUBSTRINGS that PWA staging must NEVER reach.
/// Not secrets — just enough to fail closed. Extend with the real production
/// refs at activation time (still non-secret substrings).
const List<String> kProductionHostDenylist = <String>[
  'api.aydenstudio.com',
  'aydenstudio.com',
  // Placeholder for the production Supabase project ref — replace at activation.
  'prod.supabase.co',
];

/// Tokens that mark a host as *recognizably* staging/local. A staging target
/// must contain one of these (belt-and-braces against pointing at an arbitrary,
/// possibly-production host by mistake).
const List<String> kStagingHostMarkers = <String>[
  'staging',
  'localhost',
  '127.0.0.1',
];

/// Resolved, validated environment configuration.
class PwaEnvironment {
  const PwaEnvironment._(
    this.environment, {
    this.stagingApiBaseUrl,
    this.stagingSupabaseUrl,
    this.stagingSupabaseAnonKey,
    this.allowStagingMigrations = false,
    this.seedDemo = false,
  });

  final AydenEnvironment environment;
  final String? stagingApiBaseUrl;
  final String? stagingSupabaseUrl;

  /// The staging ANON (public) key only — a service-role key must never reach
  /// the client (§12). Kept nullable; the foundation never activates it.
  final String? stagingSupabaseAnonKey;
  final bool allowStagingMigrations;
  final bool seedDemo;

  bool get isMock => environment == AydenEnvironment.mock;
  bool get isStaging => environment == AydenEnvironment.staging;
  bool get isProduction => environment == AydenEnvironment.production;

  /// The validated staging target (Supabase URL preferred, else API base URL).
  String get stagingTarget => (stagingSupabaseUrl?.isNotEmpty ?? false)
      ? stagingSupabaseUrl!
      : (stagingApiBaseUrl ?? '');

  /// Live resolution from compile-time defines (`--dart-define`). Defaults to
  /// mock so a plain build is always the offline experience.
  factory PwaEnvironment.current() => PwaEnvironment.parse(const {
    'AYDEN_ENV': String.fromEnvironment('AYDEN_ENV', defaultValue: 'mock'),
    'AYDEN_STAGING_API_BASE_URL': String.fromEnvironment(
      'AYDEN_STAGING_API_BASE_URL',
    ),
    'AYDEN_STAGING_SUPABASE_URL': String.fromEnvironment(
      'AYDEN_STAGING_SUPABASE_URL',
    ),
    'AYDEN_STAGING_SUPABASE_ANON_KEY': String.fromEnvironment(
      'AYDEN_STAGING_SUPABASE_ANON_KEY',
    ),
    'AYDEN_ALLOW_STAGING_MIGRATIONS': String.fromEnvironment(
      'AYDEN_ALLOW_STAGING_MIGRATIONS',
    ),
    'AYDEN_STAGING_SEED_DEMO': String.fromEnvironment(
      'AYDEN_STAGING_SEED_DEMO',
    ),
  });

  /// Pure parser (unit-testable without touching real dart-defines). Fails
  /// CLOSED: unknown env, production, or a staging target that is empty / not
  /// https / production-looking / not recognizably staging all throw.
  static PwaEnvironment parse(Map<String, String> defines) {
    final envName = (defines['AYDEN_ENV'] ?? 'mock').trim().toLowerCase();
    final environment = switch (envName) {
      'mock' || '' => AydenEnvironment.mock,
      'staging' => AydenEnvironment.staging,
      'production' => AydenEnvironment.production,
      _ => throw PwaConfigError('Unknown AYDEN_ENV "$envName".'),
    };

    if (environment == AydenEnvironment.production) {
      throw const PwaConfigError(
        'AYDEN_ENV=production is not implemented in this build (refusing to boot).',
      );
    }

    final apiUrl = defines['AYDEN_STAGING_API_BASE_URL']?.trim();
    final supaUrl = defines['AYDEN_STAGING_SUPABASE_URL']?.trim();
    final anon = defines['AYDEN_STAGING_SUPABASE_ANON_KEY']?.trim();
    final allowMig =
        (defines['AYDEN_ALLOW_STAGING_MIGRATIONS'] ?? 'false').trim() == 'true';
    final seed =
        (defines['AYDEN_STAGING_SEED_DEMO'] ?? 'false').trim() == 'true';

    if (environment == AydenEnvironment.staging) {
      final target = (supaUrl?.isNotEmpty ?? false) ? supaUrl! : (apiUrl ?? '');
      assertStagingTargetAllowed(target);
    }

    return PwaEnvironment._(
      environment,
      stagingApiBaseUrl: apiUrl,
      stagingSupabaseUrl: supaUrl,
      stagingSupabaseAnonKey: anon,
      allowStagingMigrations: allowMig,
      seedDemo: seed,
    );
  }

  /// The boot guard (§28). Throws [PwaConfigError] unless [target] is a
  /// non-empty https host that is NOT on the production denylist and IS
  /// recognizably staging/local.
  static void assertStagingTargetAllowed(String target) {
    final t = target.trim();
    if (t.isEmpty) {
      throw const PwaConfigError(
        'Staging target is not configured (fail closed — never falls back to production).',
      );
    }
    final lower = t.toLowerCase();
    final isLocal =
        lower.startsWith('http://localhost') ||
        lower.startsWith('http://127.0.0.1');
    if (!lower.startsWith('https://') && !isLocal) {
      throw PwaConfigError('Staging target must be https (got "$target").');
    }
    // Evaluate the denylist and staging markers against the HOST only, never
    // the path — otherwise a production host with a "/staging" path could
    // masquerade as staging and fail open at activation.
    final host = (Uri.tryParse(t)?.host ?? '').toLowerCase();
    final hay = host.isEmpty ? lower : host;
    for (final banned in kProductionHostDenylist) {
      if (hay.contains(banned)) {
        throw PwaConfigError(
          'Refusing a production host in staging (matched "$banned").',
        );
      }
    }
    if (!kStagingHostMarkers.any(hay.contains)) {
      throw PwaConfigError(
        'Staging target "$target" is not recognizably staging/local (fail closed).',
      );
    }
  }
}
