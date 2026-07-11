import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/auth/keychain_local_storage.dart';
import 'core/boot/app_boot.dart';
import 'core/feature_flags.dart';
import 'core/l10n/app_localizations.dart';
import 'core/providers/locale_provider.dart';
import 'core/providers/me_status_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/local_notification_service.dart';
import 'core/widgets/ready_notification_host.dart';
import 'core/services/push_service.dart';
import 'core/theme/app_theme.dart';
import 'data/services/revenuecat_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  final bootSw = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  bootLog(bootSw, 'ensureInitialized');
  await dotenv.load(fileName: '.env');
  bootLog(bootSw, 'dotenv');

  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  debugPrint('[DB] SUPABASE_URL loaded: ${supabaseUrl.isNotEmpty}');

  // BUG 4 (device-key, Approche 2) — CONDITION 1 : migrer l'ancienne session
  // SharedPreferences → Keychain AVANT initialize (sinon un user existant qui met à
  // jour perdrait son user_id au 1er boot). Fail-safe : no-op en cas d'erreur.
  await KeychainLocalStorage.migrateLegacySessionIfNeeded(supabaseUrl);

  // KEPT before runApp in BOTH modes: Supabase.instance must exist when App /
  // providers (meStatusProvider, etc.) build, and it's local/fast (~<200ms).
  // BUG 4 — la session est persistée dans le Keychain (survit au reinstall iOS) → user_id
  // stable → free/pass/RC-appUserID conservés. CONDITION 2 : la session est restaurée ICI,
  // AVANT toute config RevenueCat (faite plus tard dans app_boot/splash).
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
    authOptions: FlutterAuthClientOptions(localStorage: KeychainLocalStorage()),
  );
  bootLog(bootSw, 'Supabase.initialize');

  if (!FeatureFlags.fastBoot) {
    // ── LEGACY pre-runApp chain (rollback path; today's behaviour, minus the
    //    RevenueCat rethrow). All heavy/network inits are awaited here → the
    //    native Launch Screen lingers for their sum. ────────────────────────
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
      debugPrint('[Push] Firebase.initializeApp() complete');
    } catch (e) {
      debugPrint('[Push] Firebase init failed (non-fatal): $e');
    }

    final auth = Supabase.instance.client.auth;
    if (auth.currentSession == null) {
      try {
        final res = await auth.signInAnonymously();
        debugPrint('[DB] signInAnonymously() success — user_id: ${res.user?.id}');
      } catch (e) {
        debugPrint('[DB] signInAnonymously() FAILED: $e');
      }
    } else {
      debugPrint('[DB] Existing session RESTORED — user_id: ${auth.currentUser?.id}');
    }

    final userId = auth.currentUser?.id;
    if (userId != null) {
      // No rethrow — a RevenueCat hiccup must never block app start.
      try {
        await RevenuecatService.instance.configure(userId: userId);
      } catch (e) {
        debugPrint('[RevenuecatService] configure() failed at boot (non-fatal): $e');
      }
    }

    try {
      await LocalNotificationService.instance.init();
    } catch (e) {
      debugPrint('[Notif] init() failed (non-fatal): $e');
    }

    try {
      await PushService.instance.init();
    } catch (e) {
      debugPrint('[Push] init() failed (non-fatal): $e');
    }
  }
  // FAST_BOOT: the heavy chain above is SKIPPED here — the SplashScreen runs it
  // (auth awaited + the rest fire-and-forget) behind the Ayden splash.

  AppBoot.bootStopwatch = bootSw;
  bootLog(bootSw, 'runApp');
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    // Sprint 1 — instantiate + keep the status/reconcile notifier alive for the
    // whole app lifetime (listen, not watch → no MaterialApp rebuilds). This is
    // what runs POST /purchases/sync on premium signals app-wide.
    ref.listen(meStatusProvider, (_, _) {});
    return MaterialApp.router(
      title: 'AYDEN Studio',
      theme: AppTheme.light,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // BUG 2+3 — notification in-app "ready" globale/tappable/session-aware,
      // montée au-dessus de toutes les routes (écoute route-agnostique).
      builder: (context, child) =>
          ReadyNotificationHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
