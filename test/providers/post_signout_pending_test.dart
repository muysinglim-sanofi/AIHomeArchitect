// BUG 2 (anti-abus Sign out) — flag local persistant `postSignoutMarkerPending`.
//
// Prouve, sans réseau ni Supabase (seams injectés) :
//   • installation FRAÎCHE (aucune valeur persistée) → pas en attente, aucun marqueur reposté ;
//   • setPending persiste (true/false) et pilote l'état ;
//   • resolve() : anon+pending+succès → flag levé (false) ; échec → flag maintenu (true) ;
//     NON-anonyme → flag PÉRIMÉ nettoyé (aucun marqueur) ; session indéterminée → flag maintenu ;
//   • BOOT (_init) : un pending PERSISTÉ (survécu au redémarrage) → retry auto au démarrage.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_home_architect/core/providers/post_signout_pending_provider.dart';

const _kKey = 'post_signout_marker_pending';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Construit le notifier PUIS laisse son _init (fire-and-forget) s'exécuter contre les prefs
  // INITIALES avant toute manipulation — sinon _init lirait une valeur écrite par setPending et
  // déclencherait un resolve() parasite (artefact de test ; en prod setPending arrive au sign-out,
  // longtemps après le boot).
  Future<PostSignoutPendingNotifier> booted({
    Future<bool> Function()? postMarker,
    bool? Function()? isAnonymous,
  }) async {
    final n = PostSignoutPendingNotifier(
        postMarker: postMarker, isAnonymous: isAnonymous);
    await pumpEventQueue();
    return n;
  }

  group('PostSignoutPendingNotifier — resolve() (retry / bouton Retry)', () {
    test('installation fraîche (rien persisté) → NON en attente, aucun marqueur', () async {
      SharedPreferences.setMockInitialValues({});
      var markerCalls = 0;
      final n = await booted(
        postMarker: () async {
          markerCalls++;
          return true;
        },
        isAnonymous: () => true,
      );
      expect(n.state, isFalse); // gate ouvert
      expect(markerCalls, 0); // pas de _init retry → pas de POST
    });

    test('setPending(true/false) pilote l\'état ET persiste', () async {
      SharedPreferences.setMockInitialValues({});
      final n = await booted(isAnonymous: () => true);
      await n.setPending(true);
      expect(n.state, isTrue);
      expect((await SharedPreferences.getInstance()).getBool(_kKey), isTrue);
      await n.setPending(false);
      expect(n.state, isFalse);
      expect((await SharedPreferences.getInstance()).getBool(_kKey), isFalse);
    });

    test('pending + anon + marqueur SUCCÈS → flag levé (false) + persisté false', () async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      final n = await booted(
        postMarker: () async {
          calls++;
          return true;
        },
        isAnonymous: () => true,
      );
      await n.setPending(true);
      final ok = await n.resolve();
      expect(ok, isTrue);
      expect(calls, 1);
      expect(n.state, isFalse);
      expect((await SharedPreferences.getInstance()).getBool(_kKey), isFalse);
    });

    test('pending + anon + marqueur ÉCHEC → flag MAINTENU (true)', () async {
      SharedPreferences.setMockInitialValues({});
      final n = await booted(
        postMarker: () async => false,
        isAnonymous: () => true,
      );
      await n.setPending(true);
      final ok = await n.resolve();
      expect(ok, isFalse);
      expect(n.state, isTrue); // gate reste fermé
    });

    test('pending + marqueur THROWS → capturé → flag MAINTENU (true)', () async {
      SharedPreferences.setMockInitialValues({});
      final n = await booted(
        postMarker: () async => throw Exception('network'),
        isAnonymous: () => true,
      );
      await n.setPending(true);
      final ok = await n.resolve();
      expect(ok, isFalse);
      expect(n.state, isTrue);
    });

    test('pending + NON-anonyme (lié/connecté) → flag PÉRIMÉ nettoyé, AUCUN marqueur', () async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      final n = await booted(
        postMarker: () async {
          calls++;
          return true;
        },
        isAnonymous: () => false, // compte permanent
      );
      await n.setPending(true);
      final ok = await n.resolve();
      expect(ok, isTrue);
      expect(calls, 0); // le marqueur ne s'applique pas → aucun POST
      expect(n.state, isFalse); // périmé → nettoyé (ne bloque pas un compte connecté)
    });

    test('pending + session INDÉTERMINÉE (null) → flag MAINTENU, AUCUN marqueur', () async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      final n = await booted(
        postMarker: () async {
          calls++;
          return true;
        },
        isAnonymous: () => null, // pas de session restaurée
      );
      await n.setPending(true);
      final ok = await n.resolve();
      expect(ok, isFalse);
      expect(calls, 0);
      expect(n.state, isTrue); // on garde le flag → retry plus tard
    });

    test('resolve() quand RIEN en attente → true, aucun marqueur', () async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      final n = await booted(
        postMarker: () async {
          calls++;
          return true;
        },
        isAnonymous: () => true,
      );
      final ok = await n.resolve();
      expect(ok, isTrue);
      expect(calls, 0);
    });
  });

  group('PostSignoutPendingNotifier — BOOT (_init, pending survécu au redémarrage)', () {
    test('pending PERSISTÉ + anon → retry AUTO au boot → succès → flag levé', () async {
      SharedPreferences.setMockInitialValues({_kKey: true});
      var calls = 0;
      final n = PostSignoutPendingNotifier(
        postMarker: () async {
          calls++;
          return true;
        },
        isAnonymous: () => true,
      );
      await pumpEventQueue(); // laisse _init lire les prefs + resolve()
      expect(calls, 1); // re-POST automatique au démarrage
      expect(n.state, isFalse); // succès → gate ouvert
    });

    test('pending PERSISTÉ + anon + échec réseau → flag reste levé (Generate gardé bloqué)', () async {
      SharedPreferences.setMockInitialValues({_kKey: true});
      final n = PostSignoutPendingNotifier(
        postMarker: () async => false,
        isAnonymous: () => true,
      );
      await pumpEventQueue();
      expect(n.state, isTrue); // échec → reste bloqué, retry au prochain boot / Retry
    });

    test('pending PERSISTÉ + NON-anonyme → nettoyé au boot (aucun blocage résiduel)', () async {
      SharedPreferences.setMockInitialValues({_kKey: true});
      var calls = 0;
      final n = PostSignoutPendingNotifier(
        postMarker: () async {
          calls++;
          return true;
        },
        isAnonymous: () => false,
      );
      await pumpEventQueue();
      expect(calls, 0);
      expect(n.state, isFalse); // flag périmé purgé
    });
  });
}
