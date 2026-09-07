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

/// The EXACT origins allowed for the staging generation backend — the canonical
/// FastAPI run locally against the staging project.
///
/// An exact-ORIGIN allowlist, not a host one: the scheme and the port are part
/// of the decision, so `http://127.0.0.1:9999` and `https://127.0.0.1:8000` are
/// both rejected. A remote entry is added here BY REVIEW when a real staging
/// host exists — never inferred at runtime from the page's own origin, which is
/// the shortcut that turns a compromised host into a credential exfiltrator.
const List<String> kStagingBackendOriginAllowlist = <String>[
  'http://127.0.0.1:8000',
  'http://localhost:8000',
  // The PUBLIC staging API (Fly.io, deployed 2026-08-26). Added deliberately
  // and reviewed, which is the entire point of this list existing rather than a
  // `startsWith('https://')` check.
  //
  // It is safe to name here for the same reason the Supabase URL is: it is an
  // address, not a credential. Every secret it needs — the service-role key,
  // the OpenAI key, the PayWay signing key — lives in that host's own secret
  // store and has no path into this bundle.
  //
  // It is HTTPS-only. A plain-http remote entry would still be rejected below
  // even if someone added one, because a generation request carries the user's
  // session token and there is no version of that which may travel in clear.
  'https://ayden-api-staging.fly.dev',
];

/// The PRODUCTION Supabase project. Named for the same reason the staging ref
/// is: it is an address, not a credential, and naming it is what makes the
/// cross-check ("this ref must match this host") possible at all.
const String kProductionProjectRef = 'vtxkciupyafukhdsgxgw';

/// The EXACT Supabase host a production build may talk to.
const List<String> kProductionHostAllowlist = <String>[
  'vtxkciupyafukhdsgxgw.supabase.co',
];

/// The EXACT origin of the production generation backend — the Fly.io app that
/// serves the Web API, behind `api.aydenstudio.com`.
///
/// Reviewed and written down here rather than derived at runtime, exactly as
/// the staging list is: a production build that guessed its backend from the
/// page's own origin would turn a compromised host into a token exfiltrator.
/// HTTPS only, no path — a session token never travels in clear.
const List<String> kProductionBackendOriginAllowlist = <String>[
  'https://api.aydenstudio.com',
];

/// The hosts a PRODUCTION build must refuse: the staging project and the
/// staging API. The mirror image of [kProductionHostDenylist], so the guard is
/// symmetric and a production bundle can never be pointed at staging data.
const List<String> kStagingHostDenylist = <String>[
  'eedcahzekpgxvvfxufbk.supabase.co',
  'eedcahzekpgxvvfxufbk',
  'ayden-api-staging.fly.dev',
];

/// Resolved, validated environment configuration.
class PwaEnvironment {
  const PwaEnvironment._(
    this.environment, {
    this.prodSupabaseUrl,
    this.prodProjectRef,
    this.prodPublishableKey,
    this.prodBackendUrl,
    this.stagingSupabaseUrl,
    this.stagingProjectRef,
    this.stagingPublishableKey,
    this.stagingBackendUrl,
    this.allowStagingMigrations = false,
    this.seedDemo = false,
  });

  final AydenEnvironment environment;
  final String? stagingSupabaseUrl;
  final String? stagingProjectRef;

  /// The staging PUBLISHABLE (public) key only — a service-role/secret key must
  /// never reach the client (§3). Kept nullable; mock never holds it.
  final String? stagingPublishableKey;

  /// Origin of the canonical generation backend for staging. Validated against
  /// [kStagingBackendOriginAllowlist]; null in mock, never null in staging.
  ///
  /// The client only ever holds this URL — every provider secret stays on the
  /// server, which is the whole reason generation goes through the backend
  /// instead of the browser.
  final String? stagingBackendUrl;
  final bool allowStagingMigrations;
  final bool seedDemo;

  /// The PRODUCTION equivalents. Only one set is ever populated: a build is
  /// staging or production, never both, and the parser refuses anything else.
  final String? prodSupabaseUrl;
  final String? prodProjectRef;
  final String? prodPublishableKey;
  final String? prodBackendUrl;

  // ── What every consumer should read ──────────────────────────────────────
  //
  // Before production existed, callers read `staging*` directly. That was
  // honest then and would be a lie now, so the resolved values live here and
  // the `staging*` fields stay as the raw parse result (and as what the
  // existing guards assert on).

  /// The Supabase URL this build talks to.
  String? get supabaseUrl => isProduction ? prodSupabaseUrl : stagingSupabaseUrl;

  /// The Supabase project ref this build talks to.
  String? get projectRef => isProduction ? prodProjectRef : stagingProjectRef;

  /// The publishable (never secret) key this build ships.
  String? get publishableKey =>
      isProduction ? prodPublishableKey : stagingPublishableKey;

  /// The generation backend origin this build calls.
  String? get backendUrl => isProduction ? prodBackendUrl : stagingBackendUrl;

  /// The path every Web API route hangs under.
  ///
  /// The staging deployment answers on `/pwa/staging` and keeps that address
  /// for as long as it exists; production answers on `/pwa`. The backend
  /// resolves the same two values from `PWA_TARGET` (`backend/pwa_target.py`),
  /// so the pair is defined once on each side and nowhere else.
  String get apiPrefix => isProduction ? '/pwa' : '/pwa/staging';

  /// True when this build talks to a real backend (staging or production), as
  /// opposed to the offline mock.
  bool get isRemote => isStaging || isProduction;

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
    'AYDEN_STAGING_SUPABASE_URL': String.fromEnvironment(
      'AYDEN_STAGING_SUPABASE_URL',
    ),
    'AYDEN_STAGING_PROJECT_REF': String.fromEnvironment(
      'AYDEN_STAGING_PROJECT_REF',
    ),
    'AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY': String.fromEnvironment(
      'AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY',
    ),
    'AYDEN_STAGING_BACKEND_URL': String.fromEnvironment(
      'AYDEN_STAGING_BACKEND_URL',
    ),
    'AYDEN_ALLOW_STAGING_MIGRATIONS': String.fromEnvironment(
      'AYDEN_ALLOW_STAGING_MIGRATIONS',
    ),
    'AYDEN_STAGING_SEED_DEMO': String.fromEnvironment(
      'AYDEN_STAGING_SEED_DEMO',
    ),
    'AYDEN_PROD_SUPABASE_URL': String.fromEnvironment(
      'AYDEN_PROD_SUPABASE_URL',
    ),
    'AYDEN_PROD_PROJECT_REF': String.fromEnvironment(
      'AYDEN_PROD_PROJECT_REF',
    ),
    'AYDEN_PROD_SUPABASE_PUBLISHABLE_KEY': String.fromEnvironment(
      'AYDEN_PROD_SUPABASE_PUBLISHABLE_KEY',
    ),
    'AYDEN_PROD_BACKEND_URL': String.fromEnvironment(
      'AYDEN_PROD_BACKEND_URL',
    ),
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

    final prodUrl = defines['AYDEN_PROD_SUPABASE_URL']?.trim();
    final prodRef = defines['AYDEN_PROD_PROJECT_REF']?.trim();
    final prodKey = defines['AYDEN_PROD_SUPABASE_PUBLISHABLE_KEY']?.trim();
    final prodBackend = defines['AYDEN_PROD_BACKEND_URL']?.trim();

    if (environment == AydenEnvironment.production) {
      // Implemented 2026-09-04, and implemented the same way staging is: an
      // EXACT host, an EXACT ref that must match that host, a key proved not
      // to be a secret, and an EXACT backend origin. Nothing is inferred, and
      // a missing value is a refusal to boot rather than a fallback.
      assertProductionTargetAllowed(prodUrl ?? '');
      assertProductionRefAllowed(prodRef ?? '', prodUrl ?? '');
      assertPublishableKeyAllowed(prodKey ?? '');
      assertProductionBackendUrlAllowed(prodBackend ?? '');
      return PwaEnvironment._(
        environment,
        prodSupabaseUrl: prodUrl,
        prodProjectRef: prodRef,
        prodPublishableKey: prodKey,
        prodBackendUrl: prodBackend,
      );
    }

    final supaUrl = defines['AYDEN_STAGING_SUPABASE_URL']?.trim();
    final projectRef = defines['AYDEN_STAGING_PROJECT_REF']?.trim();
    final pubKey = defines['AYDEN_STAGING_SUPABASE_PUBLISHABLE_KEY']?.trim();
    final backendUrl = defines['AYDEN_STAGING_BACKEND_URL']?.trim();
    final allowMig =
        (defines['AYDEN_ALLOW_STAGING_MIGRATIONS'] ?? 'false').trim() == 'true';
    final seed =
        (defines['AYDEN_STAGING_SEED_DEMO'] ?? 'false').trim() == 'true';

    if (environment == AydenEnvironment.staging) {
      final url = supaUrl ?? '';
      assertStagingTargetAllowed(url);
      assertProjectRefAllowed(projectRef ?? '', url);
      assertPublishableKeyAllowed(pubKey ?? '');
      assertBackendUrlAllowed(backendUrl ?? '');
    }

    return PwaEnvironment._(
      environment,
      stagingSupabaseUrl: supaUrl,
      stagingProjectRef: projectRef,
      stagingPublishableKey: pubKey,
      stagingBackendUrl: backendUrl,
      allowStagingMigrations: allowMig,
      seedDemo: seed,
    );
  }

  /// Backend guard (§"URL backend PWA staging"). Throws [PwaConfigError] unless
  /// [url] is EXACTLY one of [kStagingBackendOriginAllowlist].
  ///
  /// Deliberately origin-exact rather than host-based: a generation backend
  /// receives the user's session token, so "close enough" is not a category
  /// that may exist here. Absent, ambiguous, production, or plain-http remote
  /// all land in the same place — refuse to boot.
  static void assertBackendUrlAllowed(String url) {
    final u = url.trim();
    if (u.isEmpty) {
      throw const PwaConfigError(
        'AYDEN_STAGING_BACKEND_URL is not configured (fail closed — the PWA '
        'never guesses a generation backend).',
      );
    }
    final parsed = Uri.tryParse(u);
    final host = (parsed?.host ?? '').toLowerCase();
    if (parsed == null || host.isEmpty) {
      throw PwaConfigError('Staging backend URL has no host (got "$url").');
    }
    // Denylist first, so a production host is named as such in the error even
    // if it would also have failed the allowlist.
    for (final banned in kProductionHostDenylist) {
      if (host.contains(banned)) {
        throw PwaConfigError(
          'Refusing a production backend host in staging (matched "$banned").',
        );
      }
    }
    if (parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.path.replaceAll('/', '').isNotEmpty) {
      throw PwaConfigError(
        'Staging backend URL must be a bare origin, no path or query '
        '(got "$url").',
      );
    }
    final origin =
        '${parsed.scheme.toLowerCase()}://$host'
        '${parsed.hasPort ? ':${parsed.port}' : ''}';
    if (!kStagingBackendOriginAllowlist.contains(origin)) {
      throw PwaConfigError(
        'Staging backend origin "$origin" is not authorized (fail closed). '
        'Allowed: ${kStagingBackendOriginAllowlist.join(", ")}.',
      );
    }
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
    if (!lower.startsWith('https://') &&
        !(isLocal && lower.startsWith('http://'))) {
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

  /// Host guard, production side: an EXACT https host on
  /// [kProductionHostAllowlist] and NOT on [kStagingHostDenylist].
  static void assertProductionTargetAllowed(String target) {
    final t = target.trim();
    if (t.isEmpty) {
      throw const PwaConfigError(
        'AYDEN_PROD_SUPABASE_URL is not configured (fail closed — a production '
        'build never guesses its project).',
      );
    }
    final host = (Uri.tryParse(t)?.host ?? '').toLowerCase();
    if (host.isEmpty) {
      throw PwaConfigError('Production target has no host (got "$target").');
    }
    if (!t.toLowerCase().startsWith('https://')) {
      throw PwaConfigError('Production target must be https (got "$target").');
    }
    for (final banned in kStagingHostDenylist) {
      if (host.contains(banned)) {
        throw PwaConfigError(
          'Refusing a STAGING host in a production build (matched "$banned").',
        );
      }
    }
    if (!kProductionHostAllowlist.contains(host)) {
      throw PwaConfigError(
        'Production host "$host" is not the authorized production host '
        '(fail closed).',
      );
    }
  }

  /// Project-ref guard, production side: exactly [kProductionProjectRef], and
  /// it must match the URL's host.
  static void assertProductionRefAllowed(String ref, String url) {
    final r = ref.trim();
    if (r.isEmpty) {
      throw const PwaConfigError(
        'AYDEN_PROD_PROJECT_REF is not configured (fail closed).',
      );
    }
    if (r != kProductionProjectRef) {
      throw PwaConfigError(
        'Project ref "$r" is not the authorized production ref (fail closed).',
      );
    }
    final host = (Uri.tryParse(url.trim())?.host ?? '').toLowerCase();
    if (host != '$r.supabase.co') {
      throw PwaConfigError(
        'Project ref "$r" does not match the production URL host "$host" '
        '(fail closed).',
      );
    }
  }

  /// Backend guard, production side: EXACTLY one of
  /// [kProductionBackendOriginAllowlist], never a staging host.
  static void assertProductionBackendUrlAllowed(String url) {
    final u = url.trim();
    if (u.isEmpty) {
      throw const PwaConfigError(
        'AYDEN_PROD_BACKEND_URL is not configured (fail closed — the PWA never '
        'guesses a generation backend).',
      );
    }
    final parsed = Uri.tryParse(u);
    final host = (parsed?.host ?? '').toLowerCase();
    if (parsed == null || host.isEmpty) {
      throw PwaConfigError('Production backend URL has no host (got "$url").');
    }
    for (final banned in kStagingHostDenylist) {
      if (host.contains(banned)) {
        throw PwaConfigError(
          'Refusing a STAGING backend host in production (matched "$banned").',
        );
      }
    }
    if (parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.path.replaceAll('/', '').isNotEmpty) {
      throw PwaConfigError(
        'Production backend URL must be a bare origin, no path or query '
        '(got "$url").',
      );
    }
    final origin =
        '${parsed.scheme.toLowerCase()}://$host'
        '${parsed.hasPort ? ':${parsed.port}' : ''}';
    if (!kProductionBackendOriginAllowlist.contains(origin)) {
      throw PwaConfigError(
        'Production backend origin "$origin" is not authorized (fail closed). '
        'Allowed: ${kProductionBackendOriginAllowlist.join(", ")}.',
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
