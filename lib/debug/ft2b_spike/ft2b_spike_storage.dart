/// FT2-B spike — ISOLATED Supabase session storage.
///
/// The spike must NEVER read, overwrite, or delete the real app's Supabase
/// session. The live app persists its session in the iOS Keychain under the key
/// `sb_supabase_session` (see the app's KeychainLocalStorage). This class uses a
/// DELIBERATELY DIFFERENT key — `sb_supabase_session_ft2b_spike` — so the spike
/// physically cannot collide with the production session, even though it shares
/// the same bundle id / Keychain namespace on-device.
///
/// Mirrors the real KeychainLocalStorage shape (verified against supabase_flutter
/// 2.12.4 `LocalStorage`): initialize / hasAccessToken / accessToken /
/// persistSession / removePersistedSession. Fail-safe: every secure-storage
/// error is swallowed and degrades to "no session".
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SpikeSecureLocalStorage extends LocalStorage {
  SpikeSecureLocalStorage();

  /// DISTINCT from the production key `sb_supabase_session`. Do not change this
  /// to the production key under any circumstance.
  static const String kSpikeSessionKey = 'sb_supabase_session_ft2b_spike';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false, // never iCloud-synced
    ),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    try {
      final v = await _storage.read(key: kSpikeSessionKey);
      return v != null && v.isNotEmpty;
    } catch (e) {
      debugPrint(
        '[FT2B-spike/storage] hasAccessToken failed (non-fatal): '
        '${e.runtimeType}',
      );
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      return await _storage.read(key: kSpikeSessionKey);
    } catch (e) {
      debugPrint(
        '[FT2B-spike/storage] accessToken read failed (non-fatal): '
        '${e.runtimeType}',
      );
      return null;
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _storage.write(key: kSpikeSessionKey, value: persistSessionString);
    } catch (e) {
      debugPrint(
        '[FT2B-spike/storage] persistSession failed (non-fatal): '
        '${e.runtimeType}',
      );
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _storage.delete(key: kSpikeSessionKey);
    } catch (e) {
      debugPrint(
        '[FT2B-spike/storage] removePersistedSession failed '
        '(non-fatal): ${e.runtimeType}',
      );
    }
  }
}
