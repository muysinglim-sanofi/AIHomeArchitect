// ON-mode — orchestration PARK/RESTORE du Guest (logique testée via seams, sans
// Supabase ni Keychain). L'intégration réelle (recoverSession après un signOut compte)
// est validée sur device — cf. rapport final « validations device résiduelles ».
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/core/auth/guest_parking.dart';

void main() {
  group('GuestParking — park/restore (seams)', () {
    test('parkCurrent: session présente → park(json) + renvoie uid', () async {
      String? parked;
      final uid = await GuestParking.parkCurrent(
        sessionData: () => (json: '{"user":{"id":"guest-1"}}', uid: 'guest-1'),
        park: (j) async => parked = j,
      );
      expect(uid, 'guest-1');
      expect(parked, '{"user":{"id":"guest-1"}}');
    });

    test('parkCurrent: aucune session → null, aucun park', () async {
      var called = false;
      final uid = await GuestParking.parkCurrent(
        sessionData: () => null,
        park: (_) async => called = true,
      );
      expect(uid, isNull);
      expect(called, isFalse);
    });

    test('restore: parqué + recover OK → clear + renvoie uid', () async {
      var cleared = false;
      final uid = await GuestParking.restore(
        readParked: () async => '{"blob":1}',
        recover: (j) async => 'guest-1',
        clearParked: () async => cleared = true,
      );
      expect(uid, 'guest-1');
      expect(cleared, isTrue); // slot nettoyé UNIQUEMENT sur succès
    });

    test('restore: recover échoue → GARDE le blob (pas de clear), renvoie null', () async {
      var cleared = false;
      final uid = await GuestParking.restore(
        readParked: () async => '{"blob":1}',
        recover: (j) async => null,
        clearParked: () async => cleared = true,
      );
      expect(uid, isNull);
      expect(cleared, isFalse); // conservé pour un retry ultérieur
    });

    test('restore: aucun parqué → null (aucun recover)', () async {
      var recovered = false;
      final uid = await GuestParking.restore(
        readParked: () async => null,
        recover: (j) async {
          recovered = true;
          return 'x';
        },
        clearParked: () async {},
      );
      expect(uid, isNull);
      expect(recovered, isFalse);
    });
  });
}
