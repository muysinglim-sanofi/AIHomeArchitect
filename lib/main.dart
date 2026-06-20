import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/l10n/app_localizations.dart';
import 'core/providers/locale_provider.dart';
import 'core/providers/me_status_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/push_service.dart';
import 'core/theme/app_theme.dart';
import 'data/services/revenuecat_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  debugPrint('[DB] SUPABASE_URL loaded: ${supabaseUrl.isNotEmpty} (${supabaseUrl.substring(0, supabaseUrl.length.clamp(0, 30))}...)');
  debugPrint('[DB] SUPABASE_ANON_KEY loaded: ${supabaseKey.isNotEmpty} (${supabaseKey.substring(0, supabaseKey.length.clamp(0, 20))}...)');

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  debugPrint('[DB] Supabase.initialize() complete');

  // Phase B — Firebase (FCM push). initializeApp from the flutterfire-generated
  // options; register the top-level background handler BEFORE runApp. Guarded so
  // a Firebase hiccup never blocks app start (push is non-critical).
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
  final existingSession = auth.currentSession;

  if (existingSession == null) {
    debugPrint('[DB] No existing session — calling signInAnonymously()');
    try {
      final res = await auth.signInAnonymously();
      debugPrint('[DB] signInAnonymously() success — user_id: ${res.user?.id}');
    } catch (e) {
      debugPrint('[DB] signInAnonymously() FAILED: $e');
    }
  } else {
    debugPrint('[DB] Existing session RESTORED — user_id: ${existingSession.user.id} | expires: ${existingSession.expiresAt}');
  }

  final userId = auth.currentUser?.id;
  debugPrint('[DB] Active user_id at app start: $userId');

  // Wave 5.17d — Configure RevenueCat with the Supabase UUID as the App
  // User ID (Decision D6). configure() is fail-fast in dev — see
  // FeatureFlags.revenuecatGracefulDegradation for the production
  // fallback. We only configure when we have a userId ; an absent UUID
  // means anon sign-in failed above and the app is already in a
  // degraded state where the paywall won't be reachable anyway.
  if (userId != null) {
    try {
      await RevenuecatService.instance.configure(userId: userId);
    } catch (e) {
      debugPrint('[RevenuecatService] configure() failed at boot: $e');
      rethrow;
    }
  }

  // Phase A — init local notifications (channel + permission) and capture any
  // cold-start launch payload, AFTER auth is ready and BEFORE runApp so the
  // splash can consume the deep-link target on first frame.
  try {
    await LocalNotificationService.instance.init();
  } catch (e) {
    debugPrint('[Notif] init() failed (non-fatal): $e');
  }

  // Phase B — register this device's FCM token with the backend (after auth so
  // the JWT exists) + wire push-tap deep-linking. Non-fatal.
  try {
    await PushService.instance.init();
  } catch (e) {
    debugPrint('[Push] init() failed (non-fatal): $e');
  }

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
    );
  }
}
