/// Phase D — the ISOLATED staging Supabase client for the PWA.
///
/// Created only in `AYDEN_ENV=staging`, pointed at the exact allow-listed
/// staging project (re-validated here, defense-in-depth). This file never
/// imports `core/env/app_environment.dart` or any production config (§2/§7).
///
/// Session persistence is NATIVE: `Supabase.initialize` wires supabase_flutter's
/// own SharedPreferences-backed local storage, so a hard refresh restores the
/// SAME `auth.uid()` with NO manual token handling. In a staging build the
/// production `Supabase.initialize` is never reached (the boot path returns
/// before it), so this is the only client and stays isolated from production.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/pwa_environment.dart';

class PwaStagingSupabaseClient {
  PwaStagingSupabaseClient._(this.client);

  final SupabaseClient client;

  /// Build the isolated client. Fails CLOSED on any allowlist mismatch, BEFORE
  /// initialising anything.
  static Future<PwaStagingSupabaseClient> create(PwaEnvironment env) async {
    if (!env.isStaging) {
      throw const PwaConfigError(
        'PwaStagingSupabaseClient requested outside AYDEN_ENV=staging.',
      );
    }
    final url = env.stagingSupabaseUrl ?? '';
    // Re-assert the exact host + ref + non-secret key (never production).
    PwaEnvironment.assertStagingTargetAllowed(url);
    PwaEnvironment.assertProjectRefAllowed(env.stagingProjectRef ?? '', url);
    PwaEnvironment.assertPublishableKeyAllowed(env.stagingPublishableKey ?? '');

    // Native persistence: supabase_flutter installs its SharedPreferences-backed
    // localStorage and restores any existing session during initialize().
    await Supabase.initialize(url: url, anonKey: env.stagingPublishableKey!);
    return PwaStagingSupabaseClient._(Supabase.instance.client);
  }

  /// Restore-or-create the anonymous session. Returns the stable `auth.uid()`.
  /// The native persistence restores an existing session, so a refresh REUSES
  /// the same anonymous user — [signInAnonymously] runs only when none exists.
  Future<String> ensureSession() async {
    if (needsAnonymousSignIn(client.auth.currentSession)) {
      await client.auth.signInAnonymously();
    }
    final user = client.auth.currentUser;
    if (user == null) {
      throw const PwaConfigError('Anonymous sign-in did not yield a user.');
    }
    return user.id;
  }

  /// Pure decision (unit-testable): sign in anonymously ONLY when there is no
  /// session. A restored (native) session means the same user is reused — no new
  /// anonymous user is created. supabase_flutter auto-refreshes a live session,
  /// so a non-null [current] is a usable session.
  static bool needsAnonymousSignIn(Session? current) => current == null;
}
