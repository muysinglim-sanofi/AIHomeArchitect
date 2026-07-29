import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../router/app_router.dart';
import '../l10n/app_localizations.dart';

/// Phase A — OS-level "your vision is ready" local notification + deep-link.
///
/// Scope (deliberate):
///   • Fires ONLY when the app is NOT in the foreground (lifecycle != resumed),
///     so the in-app home snackbar (Wave 5.6c) stays the foreground signal and
///     we never double-notify.
///   • Tapping the notification deep-links straight to the originating session
///     (`/chat/<sessionId>`), both app-alive (background→foreground) and
///     cold-start (app was killed while the notification sat in the tray).
///   • Local only — NO server push (FCM/APNs), NO backend, NO Phase B. A
///     notification can only be fired while the Dart isolate is alive; if the
///     OS suspends/kills the app mid-generation the completion code never runs,
///     so that case is explicitly out of Phase A (it needs server push).
///
/// The completion code in chat_screen runs in a `!mounted` branch where the
/// widget `ref`/`context` are dead, so every public method here is static-safe
/// and navigates via the global [appRouter] (no BuildContext required).
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'generation_ready';
  static const String _channelName = 'Design generation';
  static const String _channelDescription =
      'Tells you when an architectural vision has finished generating.';

  /// Set when the app was COLD-STARTED by tapping a notification. The splash
  /// screen consumes it (instead of routing to onboarding) so the user lands
  /// directly on their session. Null on a normal launch.
  String? _pendingDeepLinkSessionId;

  bool _initialized = false;

  /// Legacy (FAST_BOOT=0) — full init before runApp: initialise the plugin,
  /// create the channel, request permission, and capture the cold-start payload.
  /// Same operations/order as before; just factored into the helpers below.
  Future<void> init() async {
    if (kIsWeb) return; // Batch 1A — no local notifications on web.
    if (_initialized) return;
    _initialized = true;
    await _initializePlugin();
    await _setupChannelAndPermissions();
    await _captureLaunchPayload();
  }

  /// FAST_BOOT — the FAST half: initialise the plugin + capture the cold-start
  /// deep-link, WITHOUT requesting permission (no blocking iOS permission
  /// dialog). Awaited by the splash bootstrap BEFORE it navigates, so the
  /// cold-start deep-link is preserved. The slow half runs fire-and-forget via
  /// [setupPermissionsAndChannel].
  Future<void> initFast() async {
    if (kIsWeb) return; // Batch 1A — no local notifications on web.
    if (_initialized) return;
    _initialized = true;
    await _initializePlugin();
    await _captureLaunchPayload();
  }

  /// FAST_BOOT — the SLOW half: Android channel + runtime permission (iOS
  /// dialog). Run fire-and-forget after the first frame so it never blocks the
  /// splash. Safe to call after [initFast].
  Future<void> setupPermissionsAndChannel() async {
    if (kIsWeb) return; // Batch 1A — no local notifications on web.
    await _setupChannelAndPermissions();
  }

  Future<void> _initializePlugin() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      // Permission is requested explicitly below so we control the timing.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onTap,
    );
  }

  Future<void> _setupChannelAndPermissions() async {
    // Android 8+ notification channel (high importance → heads-up + sound).
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );

    // Runtime permission: Android 13+ POST_NOTIFICATIONS, iOS alert/sound.
    await android?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> _captureLaunchPayload() async {
    // Cold-start: was the app launched by tapping a notification?
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final payload = launch?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        _pendingDeepLinkSessionId = payload;
        debugPrint('[Notif] cold-start launch payload → session $payload');
      }
    }
  }

  /// Returns and clears the cold-start deep-link target (splash consumes it).
  String? consumePendingDeepLink() {
    final id = _pendingDeepLinkSessionId;
    _pendingDeepLinkSessionId = null;
    return id;
  }

  /// Set true by [PushService] once the device's FCM token is registered: the
  /// SERVER then owns the "vision ready" signal for backgrounded/suspended apps,
  /// so the local notification must NOT also fire — otherwise the user gets TWO
  /// "ready" notifications (one local + one push) for a single generation. When
  /// push is NOT registered (permission denied / token failed) the backend has no
  /// token to push to, so this stays false and the local notification remains the
  /// only fallback. Failures are unaffected ([notifyFailed]): the push only covers
  /// success, so the local failure notification still fires in the background.
  bool pushHandlesReady = false;

  /// Fire the "vision ready" notification. No-op in the foreground (the in-app
  /// snackbar covers that) AND no-op once push owns "ready" (avoids the double).
  Future<void> notifyReady({required String sessionId}) {
    if (pushHandlesReady) return Future.value();
    return _show(sessionId: sessionId, isError: false);
  }

  /// Fire the "generation failed" notification (background only).
  Future<void> notifyFailed({required String sessionId}) =>
      _show(sessionId: sessionId, isError: true);

  Future<void> _show({required String sessionId, required bool isError}) async {
    if (!_initialized || sessionId.isEmpty || sessionId == 'new') return;

    // Foreground guard — don't double up with the in-app snackbar. Only notify
    // when the app is backgrounded/inactive (or lifecycle not yet reported).
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == AppLifecycleState.resumed) return;

    // #7 — localize the OS notification. This service is BuildContext-free
    // (runs in the !mounted completion branch / cold-start), so we read the
    // persisted UI locale ('ui_locale', written by LocaleNotifier) and build an
    // AppLocalizations off it instead of context.l10n. Falls back to English.
    String langCode = 'en';
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('ui_locale');
      if (code != null && code.isNotEmpty) langCode = code;
    } catch (_) {/* default 'en' */}
    final l10n = AppLocalizations(Locale(langCode));

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    // Stable id per session → re-notifying the same session REPLACES the
    // previous one instead of stacking duplicates.
    final notifId = sessionId.hashCode & 0x7fffffff;
    await _plugin.show(
      id: notifId,
      title: isError ? l10n.notifFailedTitle : l10n.notifReadyTitle,
      body: isError ? l10n.notifFailedBody : l10n.notifReadyBody,
      notificationDetails: details,
      payload: sessionId,
    );
  }

  /// Tap handler while the app is ALIVE (background→foreground). Cold-start is
  /// handled separately via [consumePendingDeepLink] from the splash.
  static void _onTap(NotificationResponse response) {
    final sessionId = response.payload;
    if (sessionId == null || sessionId.isEmpty) return;
    navigateToSession(sessionId);
  }

  /// Navigate to a session, home-first so "back" returns to home (not a blank
  /// stack). `from=notif` lets the chat screen bounce home cleanly if the
  /// session was deleted between completion and the tap.
  static void navigateToSession(String sessionId) {
    debugPrint('[Notif] deep-link → /chat/$sessionId');
    appRouter.go('/home');
    appRouter.push('/chat/$sessionId?from=notif');
  }
}
