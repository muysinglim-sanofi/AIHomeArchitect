// Premium Center Lot 1 — preuve UNITAIRE de la sélection d'état PURE (premiumCenterViewFor),
// sans widget ni l10n. Couvre Free / Weekly / Annual / Promo / admin / restore_required, et
// garantit qu'AUCUN état ne montre « Upgrade » en Lot 1 (showUpgrade toujours false).
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/services/status_service.dart';
import 'package:ai_home_architect/features/premium/premium_center_sheet.dart';

MeStatus _s(String accessSource, {String planType = 'none'}) => MeStatus(
      isPremium: accessSource != 'free' && accessSource != 'restore_required',
      isAdmin: accessSource == 'admin',
      role: 'x',
      quotaUsed: 0,
      quotaLimit: 3,
      remainingFreeGenerations: 0,
      accessSource: accessSource,
      planType: planType,
    );

void main() {
  group('Premium Center Lot 1 — premiumCenterViewFor', () {
    test('free → purchase (parcours d\'achat existant), pas de restore', () {
      final v = premiumCenterViewFor(_s('free'));
      expect(v.mode, PremiumCenterMode.purchase);
      expect(v.showRestore, isFalse);
    });

    test('pass + weekly → mode weekly + restore', () {
      final v = premiumCenterViewFor(_s('pass', planType: 'weekly'));
      expect(v.mode, PremiumCenterMode.weekly);
      expect(v.showRestore, isTrue);
    });

    test('pass + annual → mode annual + restore', () {
      final v = premiumCenterViewFor(_s('pass', planType: 'annual'));
      expect(v.mode, PremiumCenterMode.annual);
    });

    test('pass + plan inconnu (none) → premiumGeneric (jamais un crash/mauvais plan)', () {
      final v = premiumCenterViewFor(_s('pass', planType: 'none'));
      expect(v.mode, PremiumCenterMode.premiumGeneric);
      expect(v.showRestore, isTrue);
    });

    test('promo → mode promo, pas de restore/manage', () {
      final v = premiumCenterViewFor(_s('promo'));
      expect(v.mode, PremiumCenterMode.promo);
      expect(v.showRestore, isFalse);
    });

    test('admin → mode admin (informatif)', () {
      expect(premiumCenterViewFor(_s('admin')).mode, PremiumCenterMode.admin);
    });

    test('restore_required → mode restoreRequired + restore', () {
      final v = premiumCenterViewFor(_s('restore_required'));
      expect(v.mode, PremiumCenterMode.restoreRequired);
      expect(v.showRestore, isTrue);
    });

    test('AUCUN état ne montre Upgrade en Lot 1 (showUpgrade toujours false)', () {
      for (final src in ['free', 'pass', 'promo', 'admin', 'restore_required']) {
        for (final plan in ['none', 'weekly', 'annual']) {
          expect(premiumCenterViewFor(_s(src, planType: plan)).showUpgrade, isFalse,
              reason: 'Upgrade est Lot 2 (après subscription group ASC)');
        }
      }
    });
  });
}
