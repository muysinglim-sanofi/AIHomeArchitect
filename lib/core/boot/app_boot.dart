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
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/revenuecat_service.dart';
import '../../data/services/status_service.dart';
import '../auth/identity_convergence.dart';
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
    // ── ISSUE 14 (2026-08-25) — VALIDER L'IDENTITÉ AVANT DE LIER REVENUECAT ──
    // Auparavant on liait RevenueCat à `currentUser.id` sans jamais vérifier que
    // cette identité était encore la bonne. Une session anonyme périmée redevenue
    // active a ainsi capté l'abonnement Weekly, et le renouvellement suivant a été
    // crédité au mauvais compte. La liaison est destructrice même à la PREMIÈRE
    // configuration : le SDK poste le reçu StoreKit au démarrage, ce qui peut
    // déclencher un transfert côté RevenueCat. On sonde donc le backend d'abord.
    // Dans le doute on ne lie pas : une liaison différée se rattrape au boot
    // suivant, un abonnement transféré demande une réparation en base.
    final userId = Supabase.instance.client.auth.currentUser?.id;
    try {
      final probe = await StatusService().probeIdentityHealth();
      final configured = RevenuecatService.instance.isConfigured;
      final rcId = configured ? await Purchases.appUserID : null;
      final action = decideRcBinding(
        supabaseUserId: userId,
        rcAppUserId: rcId,
        health: probe.health,
        rcHasActiveEntitlement:
            configured && RevenuecatService.instance.isPremium,
        backendSaysEntitled: probe.backendEntitled,
      );
      applyIdentityVerdict(action);
      debugPrint('[IDENTITY][CONVERGE] health=${probe.health} '
          'backend_entitled=${probe.backendEntitled} rc=${rcId ?? "-"} '
          'supabase=${userId ?? "-"} action=$action');
      switch (action) {
        case RcBindAction.bindToSupabase:
          // `applyBinding` exige la décision : toute autre valeur serait un no-op.
          await RevenuecatService.instance.applyBinding(action, userId!);
          bootLog(sw, 'bg: RevenueCat ready');
        case RcBindAction.noop:
          bootLog(sw, 'bg: RevenueCat déjà aligné');
        case RcBindAction.recoveryRequired:
          debugPrint('[IDENTITY][CONVERGE] identité FERMÉE — aucune liaison '
              'RevenueCat, récupération requise');
        case RcBindAction.holdSafe:
          debugPrint('[IDENTITY][CONVERGE] état indéterminé — liaison RevenueCat '
              'différée (aucun transfert)');
      }
    } catch (e) {
      // Fail-safe absolu : une erreur de convergence ne lie RIEN et ne casse pas
      // le boot. L'app reste utilisable ; la liaison sera retentée au prochain boot.
      debugPrint('[IDENTITY][CONVERGE] échec non fatal (${e.runtimeType}) — '
          'aucune action RevenueCat');
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
