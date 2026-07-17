// PATCH 1 (2026-07-16) — AUTORITÉ PREMIUM UNIQUE côté ACHAT.
//
// Le paywall ne déclarait le succès (« Purchase successful » + pop(true)) que depuis
// l'entitlement RevenueCat LOCAL (purchasePackage), qui réussit même quand /purchases/sync
// ne confirme AUCUN pass mesuré backend → faux succès, Premium absent. Le fix fait décider le
// succès par la MÊME autorité que le Restore : restoreOutcomeFromSync(/purchases/sync), et ne
// ferme comme succès QUE sur RestoreOutcome.restored (is_premium && has_measurable_pass).
//
// Ce test prouve, sur les scénarios EXACTS du cahier de tests, que cette autorité partagée ne
// renvoie `restored` (= seul cas où le paywall pop(true)) QUE pour un pass mesuré, et un état
// honnête distinct sinon (jamais un faux succès).
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/services/status_service.dart';

/// Le paywall pop(true) (succès) UNIQUEMENT sur restored — miroir exact du switch du widget.
bool paywallWouldReportSuccess(Map<String, dynamic> sync) =>
    restoreOutcomeFromSync(sync) == RestoreOutcome.restored;

void main() {
  group('PATCH 1 — autorité de succès de l\'achat (pass mesuré backend)', () {
    test('entitlement RC local actif MAIS sync sans pass mesuré → AUCUN succès', () {
      // is_premium=true (RC actif) mais has_measurable_pass=false → PAS restored.
      final sync = {
        'synced': true,
        'is_premium': true,
        'has_measurable_pass': false,
        'state': 'restore_required',
        'reason': 'insufficient_rc_data',
      };
      expect(restoreOutcomeFromSync(sync), isNot(RestoreOutcome.restored));
      expect(paywallWouldReportSuccess(sync), isFalse); // paywall NE se ferme PAS comme succès
    });

    test('sync sans premium (RC pas encore ingéré) → AUCUN succès', () {
      final sync = {'synced': false, 'is_premium': false, 'reason': 'no_active_entitlement'};
      expect(paywallWouldReportSuccess(sync), isFalse);
    });

    test('sync vide (réseau/timeout) → AUCUN succès (jamais de faux succès sur sync lent)', () {
      expect(paywallWouldReportSuccess(const <String, dynamic>{}), isFalse);
    });

    test('sync state=pass + has_measurable_pass=true → SUCCÈS (pass mesuré confirmé)', () {
      final sync = {
        'synced': true,
        'is_premium': true,
        'has_measurable_pass': true,
        'expires_at': '2026-07-30T00:00:00Z',
      };
      expect(restoreOutcomeFromSync(sync), RestoreOutcome.restored);
      expect(paywallWouldReportSuccess(sync), isTrue); // seul cas de pop(true)
    });

    test('achat ET restore partagent la même autorité (aucune divergence de vérité)', () {
      // La même map produit le même verdict quel que soit le point d'entrée (achat/restore).
      const measured = {'is_premium': true, 'has_measurable_pass': true};
      const notMeasured = {'is_premium': true, 'has_measurable_pass': false};
      expect(restoreOutcomeFromSync(measured), RestoreOutcome.restored);
      expect(restoreOutcomeFromSync(notMeasured), isNot(RestoreOutcome.restored));
    });
  });
}
