// ON-mode — état « restauration Guest en attente » : bloque la génération tant que le bon
// Guest n'est pas restauré ; resolve() = recoverSession + RC re-bind ; boot re-tente.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_home_architect/core/providers/guest_restore_pending_provider.dart';

const _kKey = 'guest_restore_pending';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Construit + laisse _init s'exécuter contre les prefs INITIALES avant toute manipulation.
  Future<GuestRestorePendingNotifier> booted({
    Future<String?> Function()? restore,
    Future<void> Function(String uid)? rebindRc,
  }) async {
    final n = GuestRestorePendingNotifier(restore: restore, rebindRc: rebindRc);
    await pumpEventQueue();
    return n;
  }

  group('GuestRestorePendingNotifier — resolve()', () {
    test('installation fraîche (rien persisté) → NON en attente', () async {
      SharedPreferences.setMockInitialValues({});
      var restoreCalls = 0;
      final n = await booted(restore: () async {
        restoreCalls++;
        return 'g';
      });
      expect(n.state, isFalse);
      expect(restoreCalls, 0);
    });

    test('setPending(true/false) pilote l\'état ET persiste', () async {
      SharedPreferences.setMockInitialValues({});
      final n = await booted();
      await n.setPending(true);
      expect(n.state, isTrue);
      expect((await SharedPreferences.getInstance()).getBool(_kKey), isTrue);
      await n.setPending(false);
      expect(n.state, isFalse);
    });

    test('pending + restore SUCCÈS → rebind RC + flag levé', () async {
      SharedPreferences.setMockInitialValues({});
      String? rebound;
      final n = await booted(
        restore: () async => 'guest-1',
        rebindRc: (u) async => rebound = u,
      );
      await n.setPending(true);
      final ok = await n.resolve();
      expect(ok, isTrue);
      expect(n.state, isFalse); // gate ouvert
      expect(rebound, 'guest-1'); // RC re-bindé sur le Guest restauré
    });

    test('pending + restore ÉCHEC (null) → flag MAINTENU (génération reste bloquée)', () async {
      SharedPreferences.setMockInitialValues({});
      var reboundCalled = false;
      final n = await booted(
        restore: () async => null,
        rebindRc: (u) async => reboundCalled = true,
      );
      await n.setPending(true);
      final ok = await n.resolve();
      expect(ok, isFalse);
      expect(n.state, isTrue); // reste bloqué
      expect(reboundCalled, isFalse);
    });

    test('resolve() quand RIEN en attente → true, aucun restore', () async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      final n = await booted(restore: () async {
        calls++;
        return 'g';
      });
      final ok = await n.resolve();
      expect(ok, isTrue);
      expect(calls, 0);
    });
  });

  group('GuestRestorePendingNotifier — BOOT (_init, restore survécu au redémarrage)', () {
    test('pending PERSISTÉ + restore OK → retry AUTO au boot → flag levé', () async {
      SharedPreferences.setMockInitialValues({_kKey: true});
      var calls = 0;
      final n = GuestRestorePendingNotifier(
        restore: () async {
          calls++;
          return 'guest-1';
        },
        rebindRc: (u) async {},
      );
      await pumpEventQueue();
      expect(calls, 1);
      expect(n.state, isFalse);
    });

    test('pending PERSISTÉ + restore ÉCHEC → flag reste levé (génération bloquée)', () async {
      SharedPreferences.setMockInitialValues({_kKey: true});
      final n = GuestRestorePendingNotifier(
        restore: () async => null,
        rebindRc: (u) async {},
      );
      await pumpEventQueue();
      expect(n.state, isTrue);
    });
  });
}
