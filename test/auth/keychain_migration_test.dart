// BUG 4 — preuve UNITAIRE de la migration device-key (Approche 2) et de la dérivation de
// la clé legacy. Le succès du reinstall = même user_id dépend de DEUX invariants testés ici :
//   1. legacySessionKeyForUrl reproduit EXACTEMENT la clé SharedPreferences de supabase_flutter
//      ("sb-<sous-domaine>-auth-token") — sinon la migration lit à côté et perd la session.
//   2. migrateLegacySessionIfNeeded copie la session legacy dans le Keychain SEULEMENT si le
//      Keychain est vide (idempotent, n'écrase jamais une session Keychain existante).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_home_architect/core/auth/keychain_local_storage.dart';

const _url = 'https://abcdefgh.supabase.co';
const _legacyKey = 'sb-abcdefgh-auth-token';
const _fakeSession = '{"access_token":"a","refresh_token":"r","user":{"id":"u-123"}}';

Future<String?> _keychainSession() =>
    const FlutterSecureStorage().read(key: KeychainLocalStorage.kSessionKey);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BUG 4 — legacySessionKeyForUrl', () {
    test('reproduit la clé SharedPreferences par défaut de supabase_flutter', () {
      expect(KeychainLocalStorage.legacySessionKeyForUrl(_url), _legacyKey);
    });
    test('sous-domaine seul (jusqu\'au 1er point)', () {
      expect(KeychainLocalStorage.legacySessionKeyForUrl('https://xyz.supabase.co'),
          'sb-xyz-auth-token');
    });
    test('URL vide → clé vide (pas de crash)', () {
      expect(KeychainLocalStorage.legacySessionKeyForUrl(''), '');
    });
  });

  group('BUG 4 — migrateLegacySessionIfNeeded', () {
    test('session legacy présente + Keychain vide → COPIÉE dans le Keychain', () async {
      SharedPreferences.setMockInitialValues({_legacyKey: _fakeSession});
      FlutterSecureStorage.setMockInitialValues({});

      await KeychainLocalStorage.migrateLegacySessionIfNeeded(_url);

      expect(await _keychainSession(), _fakeSession,
          reason: 'la session legacy doit être migrée → user_id conservé au reinstall');
    });

    test('Keychain déjà peuplé → migration NO-OP (n\'écrase pas)', () async {
      SharedPreferences.setMockInitialValues({_legacyKey: _fakeSession});
      FlutterSecureStorage.setMockInitialValues({
        KeychainLocalStorage.kSessionKey: '{"user":{"id":"KEYCHAIN-ALREADY"}}',
      });

      await KeychainLocalStorage.migrateLegacySessionIfNeeded(_url);

      expect(await _keychainSession(), '{"user":{"id":"KEYCHAIN-ALREADY"}}',
          reason: 'une session Keychain existante est l\'autorité — jamais écrasée');
    });

    test('aucune session legacy → Keychain reste vide (le « 1 reset unique » D5)', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});

      await KeychainLocalStorage.migrateLegacySessionIfNeeded(_url);

      expect(await _keychainSession(), isNull);
    });
  });
}
