/// Batch 1A — explicit environment resolution for AYDEN Studio.
///
/// MOBILE (iOS / Android): behaviour is byte-identical to the previous `main()`
/// — the values come from the bundled `.env` via `flutter_dotenv`, with the
/// same keys and the same fallbacks.
///
/// WEB (Flutter Web / PWA): the mobile `.env` is NEVER read. Every value must be
/// supplied explicitly at build time via `--dart-define`, and a deterministic
/// guard refuses to start against production. This exists so the web build can
/// never silently transact against the live iOS backend / Supabase project.
///
/// The web validation runs BEFORE `Supabase.initialize`, anonymous sign-in, or
/// any API client construction (it is awaited first in `main()`), so a
/// misconfigured web build fails fast with a clear message instead of quietly
/// pointing at production.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Thrown (web only) when the explicit environment configuration is missing,
/// unknown, or points at production. Fatal by design.
class WebEnvironmentError extends StateError {
  WebEnvironmentError(super.message);
}

/// Resolved, validated runtime environment. Access via [instance] after
/// [initialize] has been awaited.
class AppEnvironment {
  AppEnvironment._({
    required this.name,
    required this.apiBaseUrl,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.isWeb,
  });

  /// Environment name. On mobile this is the literal `'mobile'`; on web it is
  /// the validated `AYDEN_ENV` (`staging` or `mock`).
  final String name;
  final String apiBaseUrl;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final bool isWeb;

  static AppEnvironment? _instance;

  /// The resolved environment. Throws if [initialize] has not completed.
  static AppEnvironment get instance {
    final i = _instance;
    if (i == null) {
      throw StateError(
        'AppEnvironment.initialize() must be awaited before AppEnvironment.instance.',
      );
    }
    return i;
  }

  // ── Web-only compile-time configuration (via --dart-define) ───────────────
  static const String _kEnvName = String.fromEnvironment('AYDEN_ENV');
  static const String _kApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _kSupabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _kBlockedHostsCsv =
      String.fromEnvironment('AYDEN_BLOCKED_HOSTS');

  /// Known production hosts the web build must NEVER point at. These are
  /// REJECT-ONLY constants (used to REFUSE startup), never connection targets.
  /// The URLs are not secrets — a Supabase project URL and its anon/publishable
  /// key ship in every client — so hard-blocking them here is safe and closes
  /// the "forgot the --dart-define" hole (Batch 1A.1). Additional prod hosts
  /// (aliases, other projects) can still be added at build time via
  /// `--dart-define=AYDEN_BLOCKED_HOSTS=host1,host2`.
  static const String kProductionBackendHost = 'ayden-backend.onrender.com';
  static const String kProductionSupabaseHost =
      'vtxkciupyafukhdsgxgw.supabase.co';

  /// Web environment names permitted during the PWA development phase.
  static const Set<String> allowedWebEnvNames = {'staging', 'mock'};

  /// Resolve the environment. Idempotent.
  ///
  /// MOBILE: `await dotenv.load('.env')` then read the same keys (unchanged).
  /// WEB: validate the `--dart-define` values (fail-fast) and seed `dotenv`
  /// from them so existing `dotenv.env['API_BASE_URL']` readers keep working
  /// WITHOUT ever reading the mobile `.env` asset.
  static Future<void> initialize() async {
    if (_instance != null) return;

    if (kIsWeb) {
      final env = validateWebConfig(
        envName: _kEnvName,
        apiBaseUrl: _kApiBaseUrl,
        supabaseUrl: _kSupabaseUrl,
        supabaseAnonKey: _kSupabaseAnonKey,
        blockedHostsCsv: _kBlockedHostsCsv,
      );
      // Seed dotenv from the validated web values (no `.env` asset read on web).
      dotenv.testLoad(mergeWith: {
        'API_BASE_URL': env.apiBaseUrl,
        'SUPABASE_URL': env.supabaseUrl,
        'SUPABASE_ANON_KEY': env.supabaseAnonKey,
      });
      _instance = env;
      return;
    }

    // MOBILE — identical to the previous main() behaviour.
    await dotenv.load(fileName: '.env');
    _instance = AppEnvironment._(
      name: 'mobile',
      apiBaseUrl: dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000',
      supabaseUrl: dotenv.env['SUPABASE_URL'] ?? '',
      supabaseAnonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
      isWeb: false,
    );
  }

  /// Pure, deterministic validation of the WEB configuration. Extracted so it
  /// is unit-testable without a web runtime. Throws [WebEnvironmentError] on any
  /// violation; returns the validated [AppEnvironment] otherwise.
  static AppEnvironment validateWebConfig({
    required String envName,
    required String apiBaseUrl,
    required String supabaseUrl,
    required String supabaseAnonKey,
    String blockedHostsCsv = '',
  }) {
    final name = envName.trim().toLowerCase();

    // 1) Environment name must be explicit, non-production, and known.
    if (name.isEmpty) {
      throw WebEnvironmentError(
        'Flutter Web refused to start: missing --dart-define=AYDEN_ENV '
        '(expected one of ${allowedWebEnvNames.join(", ")}).',
      );
    }
    if (name == 'production' || name == 'prod') {
      throw WebEnvironmentError(
        'Flutter Web refused to start: AYDEN_ENV="$envName" is not allowed '
        'during the PWA development phase.',
      );
    }
    if (!allowedWebEnvNames.contains(name)) {
      throw WebEnvironmentError(
        'Flutter Web refused to start: unknown AYDEN_ENV="$envName" '
        '(expected one of ${allowedWebEnvNames.join(", ")}).',
      );
    }

    // 2) Required endpoint values must be present.
    final missing = <String>[
      if (apiBaseUrl.trim().isEmpty) 'API_BASE_URL',
      if (supabaseUrl.trim().isEmpty) 'SUPABASE_URL',
      if (supabaseAnonKey.trim().isEmpty) 'SUPABASE_ANON_KEY',
    ];
    if (missing.isNotEmpty) {
      throw WebEnvironmentError(
        'Flutter Web refused to start: missing --dart-define ${missing.join(", ")}.',
      );
    }

    // 3) Reject known production endpoints (hard-blocked hosts + team blocklist).
    final blocked = <String>{
      kProductionBackendHost,
      kProductionSupabaseHost,
      for (final h in blockedHostsCsv.split(','))
        if (h.trim().isNotEmpty) h.trim().toLowerCase(),
    };
    final toCheck = <String, String>{
      'API_BASE_URL': apiBaseUrl,
      'SUPABASE_URL': supabaseUrl,
    };
    for (final entry in toCheck.entries) {
      final host = _hostOf(entry.value);
      if (host != null && blocked.contains(host)) {
        throw WebEnvironmentError(
          'Flutter Web refused to start because a production configuration was '
          'detected for ${entry.key} (host "$host").',
        );
      }
    }

    return AppEnvironment._(
      name: name,
      apiBaseUrl: apiBaseUrl.trim(),
      supabaseUrl: supabaseUrl.trim(),
      supabaseAnonKey: supabaseAnonKey.trim(),
      isWeb: true,
    );
  }

  static String? _hostOf(String url) {
    try {
      final host = Uri.parse(url.trim()).host;
      return host.isEmpty ? null : host.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  /// TEST-ONLY — reset the resolved singleton between test cases.
  static void debugReset() => _instance = null;
}
