/// Batch 3.1 — the PWA runtime environment boundary (§2 / §9).
///
/// One centralized, explicit boundary between the three environments. There is
/// NO implicit fallback: `mock` is fully offline; `staging` may only target the
/// ONE authorized staging project by EXACT host + EXACT project ref and fails
/// CLOSED otherwise; `production` is not implemented by this batch and refuses
/// to boot.
///
/// Batch 3.1 REPLACES the earlier "host must contain the word 'staging'"
/// heuristic (§2: "Never infer safety from the word 'staging' alone"). The real
/// staging host `eedcahzekpgxvvfxufbk.supabase.co` does not contain that word,
/// so the guard now matches an EXACT host allowlist + EXACT project ref, and
/// keeps a production denylist as defense-in-depth.
///
/// Pure Dart (no Flutter, no network, no secrets). Never imports the production
/// app_environment / production Supabase singleton (§2).
library;

import 'dart:convert';

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

/// The ONE authorized staging Supabase project ref (EXACT match).
const String kStagingProjectRef = 'eedcahzekpgxvvfxufbk';

/// The ONE authorized staging Supabase host (EXACT match).
const String kStagingSupabaseHost = 'eedcahzekpgxvvfxufbk.supabase.co';

/// Exact hosts allowed as a staging target: the authorized project + local dev.
/// Matched by EXACT equality on the URL host — never substring.
const List<String> kStagingHostAllowlist = <String>[
  kStagingSupabaseHost,
  'localhost',
  '127.0.0.1',
];

/// Production hosts / project refs PWA staging must NEVER reach. The exact
/// allowlist already excludes everything else; this denylist is defense-in-depth
/// and is matched as a substring on the host. Not secrets.
const List<String> kProductionHostDenylist = <String>[
  // AIHomeArchitect production Supabase project (found in lib/core/env/app_environment.dart).
  'vtxkciupyafukhdsgxgw.supabase.co',
  'vtxkciupyafukhdsgxgw',
  'api.aydenstudio.com',
  'aydenstudio.com',
];

/// Resolved, validated environment configuration.
class PwaEnvironment {
  const PwaEnvironment._(
    this.environment, {
    this.stagingSupabaseUrl,
    this.stagingProjectRef,
    this.stagingPublishableKey,
    this.allowStagingMigrations = false,
    this.seedDemo = false,
  });

  final AydenEnvironment environment;
  final String? stagingSupabaseUrl;
  final String? stagingProjectRef;

  /// The staging PUBLISHABLE (public) key only — a service-role/secret key must
  /// never reach the client (§3). Kept nullable; mock never holds it.
  final String? stagingPublishableKey;
  final bool allowStagingMigrations;
  final bool seedDemo;

  bool get isMock => environment == AydenEnvironment.mock;
  bool get isStaging => environment == AydenEnvironment.staging;
  bool get isProduction => environment == AydenEnvironment.production;

  /// The validated staging target (the Supabase URL). Batch 3.1 talks to
  /// Supabase directly (anonymous auth + RLS); there is no separate API facade.
  String get stagingTarget => stagingSupabaseUrl ?? '';

  /// Live resolution from compile-time defines (`--dart-define` /
  /// `--dart-define-from-file`). Defaults to mock so a plain build is always
  /// the offline experience.
  factory PwaEnvironment.current() => PwaEnvironment.parse(const {
        'AYDEN_ENV': String.fromEnvironment('AYDEN_ENV', defaultValue: 'mock'),
        'AYDEN_STAGING_SUPABASE_URL':
            String.fromEnvironment('AYDEN_STAGING_SUPABASE_URL'),
        'AYDEN_STAGING_PROJECT_REF':
            String.fromEnvironment('AYDEN_STAGING_PROJECT_REF'),
        'AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY':
            String.fromEnvironment('AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY'),
        'AYDEN_ALLOW_STAGING_MIGRATIONS':
            String.fromEnvironment('AYDEN_ALLOW_STAGING_MIGRATIONS'),
        'AYDEN_STAGING_SEED_DEMO':
            String.fromEnvironment('AYDEN_STAGING_SEED_DEMO'),
      });

  /// Pure parser (unit-testable without touching real dart-defines). Fails
  /// CLOSED: unknown env, production, or any staging config that is not the
  /// EXACT authorized host + ref + a present non-secret publishable key throws.
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

    final supaUrl = defines['AYDEN_STAGING_SUPABASE_URL']?.trim();
    final projectRef = defines['AYDEN_STAGING_PROJECT_REF']?.trim();
    final pubKey = defines['AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY']?.trim();
    final allowMig =
        (defines['AYDEN_ALLOW_STAGING_MIGRATIONS'] ?? 'false').trim() == 'true';
    final seed =
        (defines['AYDEN_STAGING_SEED_DEMO'] ?? 'false').trim() == 'true';

    if (environment == AydenEnvironment.staging) {
      final url = supaUrl ?? '';
      assertStagingTargetAllowed(url);
      assertProjectRefAllowed(projectRef ?? '', url);
      assertPublishableKeyAllowed(pubKey ?? '');
    }

    return PwaEnvironment._(
      environment,
      stagingSupabaseUrl: supaUrl,
      stagingProjectRef: projectRef,
      stagingPublishableKey: pubKey,
      allowStagingMigrations: allowMig,
      seedDemo: seed,
    );
  }

  /// Host guard (§2/§9). Throws [PwaConfigError] unless [target] is a non-empty
  /// https URL (http allowed ONLY for explicit localhost dev) whose HOST is on
  /// the EXACT staging allowlist and NOT on the production denylist.
  static void assertStagingTargetAllowed(String target) {
    final t = target.trim();
    if (t.isEmpty) {
      throw const PwaConfigError(
        'Staging target is not configured (fail closed — never falls back to production).',
      );
    }
    final lower = t.toLowerCase();
    final host = (Uri.tryParse(t)?.host ?? '').toLowerCase();
    if (host.isEmpty) {
      throw PwaConfigError('Staging target has no host (got "$target").');
    }
    final isLocal = host == 'localhost' || host == '127.0.0.1';
    // https required; http tolerated ONLY for an explicit localhost dev target.
    if (!lower.startsWith('https://') && !(isLocal && lower.startsWith('http://'))) {
      throw PwaConfigError('Staging target must be https (got "$target").');
    }
    // Denylist (substring on HOST only — never the path) as defense-in-depth.
    for (final banned in kProductionHostDenylist) {
      if (host.contains(banned)) {
        throw PwaConfigError(
          'Refusing a production host in staging (matched "$banned").',
        );
      }
    }
    // EXACT allowlist — lookalikes and path-embedded hosts are rejected.
    if (!kStagingHostAllowlist.contains(host)) {
      throw PwaConfigError(
        'Staging host "$host" is not the authorized staging host (fail closed).',
      );
    }
  }

  /// Project-ref guard (§2). The ref must EXACTLY equal the authorized ref, and
  /// for a Supabase host it must match `<ref>.supabase.co` (cross-check).
  static void assertProjectRefAllowed(String ref, String url) {
    final host = (Uri.tryParse(url.trim())?.host ?? '').toLowerCase();
    // Local dev target (supabase start) has no project ref — skip the ref gate.
    if (host == 'localhost' || host == '127.0.0.1') return;
    final r = ref.trim();
    if (r.isEmpty) {
      throw const PwaConfigError(
        'AYDEN_STAGING_PROJECT_REF is not configured (fail closed).',
      );
    }
    if (r != kStagingProjectRef) {
      throw PwaConfigError(
        'Project ref "$r" is not the authorized staging ref (fail closed).',
      );
    }
    if (host != '$r.supabase.co') {
      throw PwaConfigError(
        'Project ref "$r" does not match the staging URL host "$host" (fail closed).',
      );
    }
  }

  /// Publishable-key guard (§3). Must be present and must NEVER be a secret /
  /// service-role key. Rejects the `sb_secret_` prefix and any JWT whose `role`
  /// claim is `service_role`.
  static void assertPublishableKeyAllowed(String key) {
    final k = key.trim();
    if (k.isEmpty) {
      throw const PwaConfigError(
        'AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY is not configured (fail closed).',
      );
    }
    if (k.startsWith('sb_secret_')) {
      throw const PwaConfigError(
        'A secret key (sb_secret_*) must never be used in the client (§3).',
      );
    }
    if (_jwtRole(k) == 'service_role') {
      throw const PwaConfigError(
        'A service_role key must never be used in the client (§3).',
      );
    }
  }

  /// If [key] is a JWT, return its `role` claim; else null. Pure Dart.
  static String? _jwtRole(String key) {
    final parts = key.split('.');
    if (parts.length != 3) return null;
    try {
      var seg = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      seg = seg.padRight(seg.length + ((4 - seg.length % 4) % 4), '=');
      final payload =
          jsonDecode(utf8.decode(base64.decode(seg))) as Map<String, dynamic>;
      final role = payload['role'];
      return role is String ? role : null;
    } catch (_) {
      return null;
    }
  }
}
