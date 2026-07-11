/// TEMPORAIRE (debug device BUG 3/4) — remonte des ÉVÉNEMENTS frontend NON SENSIBLES vers le
/// backend (`POST /debug/client-event`) pour lecture dans les logs Render. Motivation :
/// l'utilisateur n'a pas de Mac → pas de Console.app pour lire les logs TestFlight locaux.
///
/// CONTRAT STRICT :
///  - fire-and-forget : ne bloque JAMAIS le boot / Restore / Supabase / RevenueCat ;
///  - ne throw JAMAIS (tout est avalé) ; timeout court (4 s) ;
///  - N'ENVOIE QUE des booléens / ids / états — jamais access/refresh token, receipt Apple,
///    clé RevenueCat, ni session brute (l'appelant est responsable du contenu de `data`) ;
///  - gaté par [FeatureFlags.clientDebugLog] (client) ET `CLIENT_DEBUG_ENABLED` (serveur).
///
/// À RETIRER une fois BUG 3/4 fermés.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../feature_flags.dart';

class ClientDebugLog {
  ClientDebugLog._();

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000',
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
    sendTimeout: const Duration(seconds: 4),
  ));

  /// Envoi fire-and-forget. `data` ne doit contenir QUE des valeurs non sensibles.
  static void send(String event, Map<String, dynamic> data) {
    if (!FeatureFlags.clientDebugLog) return;
    unawaited(_post(event, data));
  }

  static Future<void> _post(String event, Map<String, dynamic> data) async {
    try {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) return; // besoin de l'auth backend
      await _dio.post(
        '/debug/client-event',
        data: {
          'event': event,
          'user_id': Supabase.instance.client.auth.currentUser?.id,
          'data': data,
          'timestamp': DateTime.now().toIso8601String(),
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {/* debug best-effort — ne bloque jamais l'app */}
  }
}
