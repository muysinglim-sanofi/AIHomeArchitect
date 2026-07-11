// BUG 3 — preuve UNITAIRE du mapping /purchases/sync → RestoreOutcome (4 états
// mutuellement exclusifs). Garantit qu'un restore produit TOUJOURS un message honnête :
//   pass mesuré → restored ; abo actif sans space → activeNoSpaces ; aucun abo → noneFound ;
//   map vide (réseau/erreur) → failed. Aucun état ne « disparaît » silencieusement.
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/services/status_service.dart';

void main() {
  group('BUG 3 — restoreOutcomeFromSync', () {
    test('pass mesuré reconstruit → restored', () {
      final o = restoreOutcomeFromSync({
        'synced': true,
        'is_premium': true,
        'has_measurable_pass': true,
        'expires_at': '2026-07-18T00:00:00Z',
      });
      expect(o, RestoreOutcome.restored);
    });

    test('abo actif RC mais AUCUN pass mesurable → activeNoSpaces (jamais restore muet)',
        () {
      final o = restoreOutcomeFromSync({
        'synced': false,
        'is_premium': true,
        'has_measurable_pass': false,
        'state': 'restore_required',
        'reason': 'insufficient_rc_data',
      });
      expect(o, RestoreOutcome.activeNoSpaces);
    });

    test('aucun entitlement actif sur ce compte → noneFound', () {
      final o = restoreOutcomeFromSync({
        'synced': false,
        'is_premium': false,
        'reason': 'no_active_entitlement',
      });
      expect(o, RestoreOutcome.noneFound);
    });

    test('map vide (réseau/erreur backend) → failed', () {
      expect(restoreOutcomeFromSync(const {}), RestoreOutcome.failed);
    });

    test('is_premium absent → traité comme non-premium → noneFound', () {
      expect(restoreOutcomeFromSync({'synced': false}), RestoreOutcome.noneFound);
    });
  });
}
