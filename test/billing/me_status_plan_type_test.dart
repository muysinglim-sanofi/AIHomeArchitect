// Premium Center Lot 1 — preuve que MeStatus parse plan_type/active_product_id AVEC et SANS
// les nouveaux champs (compat backend ancien = défauts sûrs 'none'/null), et round-trip toJson.
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/services/status_service.dart';

void main() {
  group('Premium Center Lot 1 — MeStatus.planType / activeProductId', () {
    test('backend Weekly → planType=weekly, activeProductId, isWeekly', () {
      final s = MeStatus.fromJson({
        'access_source': 'pass',
        'plan_type': 'weekly',
        'active_product_id': 'com.aydenstudio.app.weekly',
      });
      expect(s.planType, 'weekly');
      expect(s.activeProductId, 'com.aydenstudio.app.weekly');
      expect(s.isWeekly, isTrue);
      expect(s.isAnnual, isFalse);
    });

    test('backend Annual → planType=annual, isAnnual', () {
      final s = MeStatus.fromJson({
        'access_source': 'pass',
        'plan_type': 'annual',
        'active_product_id': 'com.aydenstudio.app.annual',
      });
      expect(s.planType, 'annual');
      expect(s.isAnnual, isTrue);
      expect(s.isWeekly, isFalse);
    });

    test('ANCIEN backend (champs ABSENTS) → défauts sûrs none/null', () {
      final s = MeStatus.fromJson({'access_source': 'pass'});
      expect(s.planType, 'none');
      expect(s.activeProductId, isNull);
      expect(s.isWeekly, isFalse);
      expect(s.isAnnual, isFalse);
    });

    test('round-trip toJson → fromJson préserve plan_type/active_product_id', () {
      const s = MeStatus(
        isPremium: true,
        isAdmin: false,
        role: 'premium',
        quotaUsed: 0,
        quotaLimit: 3,
        remainingFreeGenerations: 0,
        accessSource: 'pass',
        planType: 'annual',
        activeProductId: 'com.aydenstudio.app.annual',
      );
      final r = MeStatus.fromJson(s.toJson());
      expect(r.planType, 'annual');
      expect(r.activeProductId, 'com.aydenstudio.app.annual');
    });
  });
}
