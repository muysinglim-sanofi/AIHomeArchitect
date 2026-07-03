/// FAST_BOOT (2026-06-23) — startup orchestration moved OFF the pre-runApp path.
///
/// `main()` does only the local minimum before `runApp()` (ensureInitialized +
/// dotenv + Supabase.initialize) so the Flutter splash paints ASAP and the
/// native iOS Launch Screen drops under ~1s. The SplashScreen then drives this
/// orchestrator:
///   • [ensureSession] — AWAITED (a valid session is required for a working
///     Home: every screen queries Supabase under RLS).
///   • [captureColdStartDeepLink] — AWAITED, fast (no permission dialog), so the
///     cold-start notification deep-link is preserved before the splash routes.
///   • [startBackgroundInit] — FIRE-AND-FORGET: Firebase, RevenueCat configure,
///     notification permissions/channel, FCM/push registration. None of these
///     gate the first frame or Home.
///
/// Gated by FeatureFlags.fastBoot; when off, main() runs the legacy sequential
/// chain and this file is unused.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/revenuecat_service.dart';
import '../../firebase_options.dart';
import '../services/local_notification_service.dart';
import '../services/pending_recovery_service.dart';
import '../services/push_service.dart';

/// One-line boot timing log. Visible in release (Console.app on a TestFlight
/// device), so the real per-step cost can be measured on a real iPhone.
void bootLog(Stopwatch sw, String step) {
  debugPrint('[Boot] +${sw.elapsedMilliseconds}ms  $step');
}

class AppBoot {
  AppBoot._();

  /// Set by main() so the splash can log total time-to-Home on the same clock.
  static Stopwatch? bootStopwatch;

  static bool _heavyStarted = false;

  /// CRITICAL — ensure an auth session exists (restore the persisted one, else
  /// sign in anonymously). Awaited by the splash before Home. Network only on
  /// the first ever launch; instant on every subsequent launch.
  static Future<void> ensureSession() async {
    final auth = Supabase.instance.client.auth;
    if (auth.currentSession != null) {
      debugPrint('[DB] Existing session RESTORED — user_id: ${auth.currentUser?.id}');
      return;
    }
    debugPrint('[DB] No existing session — calling signInAnonymously()');
    try {
      final res = await auth.signInAnonymously();
      debugPrint('[DB] signInAnonymously() success — user_id: ${res.user?.id}');
    } catch (e) {
      debugPrint('[DB] signInAnonymously() FAILED: $e');
    }
  }

  /// CRITICAL-FAST — initialise the local-notif plugin and capture any
  /// cold-start launch payload, WITHOUT the permission dialog. Awaited before
  /// the splash navigates so the deep-link (consumePendingDeepLink) survives.
  static Future<void> captureColdStartDeepLink() async {
    try {
      await LocalNotificationService.instance.initFast();
    } catch (e) {
      debugPrint('[Notif] initFast() failed (non-fatal): $e');
    }
  }

  /// NON-CRITICAL — fire-and-forget every heavy init behind the splash/Home.
  /// Idempotent. Needs the session (for the RevenueCat App User ID), so call it
  /// AFTER [ensureSession].
  static void startBackgroundInit() {
    if (_heavyStarted) return;
    _heavyStarted = true;
    // Intentionally not awaited.
    _runBackgroundInit();
  }

  static Future<void> _runBackgroundInit() async {
    final sw = Stopwatch()..start();

    // Firebase (FCM). Non-critical → never blocks start.
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
      bootLog(sw, 'bg: Firebase ready');
    } catch (e) {
      debugPrint('[Push] Firebase init failed (non-fatal): $e');
    }

    // RevenueCat configure (needs the Supabase UUID). No rethrow — graceful
    // degradation; the paywall awaits ensureConfigured before showing offers.
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        await RevenuecatService.instance.ensureConfigured(userId: userId);
        bootLog(sw, 'bg: RevenueCat ready');
      } catch (e) {
        debugPrint('[RevenuecatService] configure() failed at boot (non-fatal): $e');
      }
    }

    // Notification channel + permission (the iOS dialog) — off the splash path.
    try {
      await LocalNotificationService.instance.setupPermissionsAndChannel();
      bootLog(sw, 'bg: notifications ready');
    } catch (e) {
      debugPrint('[Notif] permissions/channel failed (non-fatal): $e');
    }

    // FCM token registration with the backend + push-tap wiring.
    try {
      await PushService.instance.init();
      bootLog(sw, 'bg: push ready');
    } catch (e) {
      debugPrint('[Push] init() failed (non-fatal): $e');
    }

    // PR2b Slice 3 — recover generations INTENDED before a kill / sleep / network
    // drop. Runs AFTER ensureSession (probe/re-launch need the auth). Registers
    // the app-resume observer + runs one sweep now. Fire-and-forget; the service
    // self-guards against overlap. Backend generation_intents stays the truth.
    try {
      PendingRecoveryService.instance.registerResumeSweep();
      await PendingRecoveryService.instance.sweep(reason: 'startup');
      bootLog(sw, 'bg: pending recovery swept');
    } catch (e) {
      debugPrint('[Recovery] boot sweep failed (non-fatal): $e');
    }
  }
}
