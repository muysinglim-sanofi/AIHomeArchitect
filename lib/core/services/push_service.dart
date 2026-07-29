import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_notification_service.dart';

/// Phase B — FCM push client.
///
/// Registers this device's FCM token with the backend (POST /devices) so the
/// server can push "vision ready" when the app is backgrounded/suspended (iOS
/// local notifications can't fire then). Tapping a push deep-links to the
/// session (reuses LocalNotificationService.navigateToSession). Foreground
/// messages are intentionally NOT shown here — the in-app reconciliation /
/// snackbar already covers that (no double-notify).

/// Background isolate handler — MUST be a top-level function. FCM displays
/// "notification" messages itself when the app is backgrounded, so there is
/// nothing to do here; it exists so onBackgroundMessage has a valid entry-point.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _started = false;

  Future<void> init() async {
    if (_started) return;
    // Batch 1A — no FCM / web push in this batch (no VAPID, no service worker).
    // Skip cleanly on web so boot never touches FirebaseMessaging / Platform.
    if (kIsWeb) return;
    _started = true;
    final fm = FirebaseMessaging.instance;

    // Permission (iOS + Android 13+). If denied, getToken still returns a token
    // on Android but pushes won't display; on iOS no push is delivered.
    await fm.requestPermission(alert: true, badge: true, sound: true);

    // Register the current token + keep it fresh.
    try {
      final token = await fm.getToken();
      if (token != null && token.isNotEmpty) await _register(token);
    } catch (e) {
      debugPrint('[Push] getToken failed (non-fatal): $e');
    }
    fm.onTokenRefresh.listen(_register);

    // Tap handling — cold start (app was terminated) + warm (background→fg).
    final initial = await fm.getInitialMessage();
    if (initial != null) _handleTap(initial);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
  }

  void _handleTap(RemoteMessage m) {
    final sid = m.data['session_id'];
    if (sid != null && sid.toString().isNotEmpty) {
      LocalNotificationService.navigateToSession(sid.toString());
    }
  }

  Future<void> _register(String token) async {
    try {
      final jwt = Supabase.instance.client.auth.currentSession?.accessToken;
      if (jwt == null) return; // not authed yet — onTokenRefresh / next boot retries
      final base = dotenv.env['API_BASE_URL'] ?? '';
      if (base.isEmpty) return;
      final platform = Platform.isIOS
          ? 'ios'
          : (Platform.isAndroid ? 'android' : 'unknown');
      final dio = Dio(BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));
      await dio.post(
        '/devices',
        data: FormData.fromMap({'token': token, 'platform': platform}),
        options: Options(headers: {'Authorization': 'Bearer $jwt'}),
      );
      // Push now owns the "vision ready" signal for backgrounded/suspended apps,
      // so the LOCAL "ready" notification must stop firing (it was double-notifying
      // — one local + one push for a single generation). Failure notifications are
      // unaffected (push covers success only).
      LocalNotificationService.instance.pushHandlesReady = true;
      debugPrint('[Push] device token registered ($platform)');
    } catch (e) {
      debugPrint('[Push] device register failed (non-fatal): $e');
    }
  }
}
