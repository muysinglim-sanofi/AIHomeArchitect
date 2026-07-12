// Lot 2 — Upgrade Weekly → Annual : preuves UNITAIRES de la logique PURE (sans SDK ni widget).
// Couvre : preuve du PRODUIT Annual exact (pas « premium actif »), garde de rendu, orchestrateur
// (annulation/échec/succès/deferred), condition de succès robuste (plan_type+active_product_id, PAS
// available_credits==300), copie de confirmation honnête, complétude des traductions EN/FR/KM.
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/services/status_service.dart';
import 'package:ai_home_architect/data/services/revenuecat_service.dart'
    show PurchaseAttempt, annualPurchaseActivated;
import 'package:ai_home_architect/features/premium/premium_center_sheet.dart';
import 'package:ai_home_architect/core/l10n/translations/en.dart';
import 'package:ai_home_architect/core/l10n/translations/fr.dart';
import 'package:ai_home_architect/core/l10n/translations/km.dart';

const _weeklyId = 'com.aydenstudio.app.weekly';

MeStatus _status({
  required String planType,
  int credits = 0,
  String? productId,
  String accessSource = 'pass',
}) =>
    MeStatus(
      isPremium: accessSource != 'free' && accessSource != 'restore_required',
      isAdmin: accessSource == 'admin',
      role: 'x',
      quotaUsed: 0,
      quotaLimit: 3,
      remainingFreeGenerations: 0,
      accessSource: accessSource,
      planType: planType,
      availableCredits: credits,
      activeProductId: productId,
    );

const _upgradeKeys = [
  'pcUpgradeTitle', 'pcUpgradeSpaces', 'pcUpgradeBestValue', 'pcUpgradeCta',
  'pcUpgradeConfirmTitle', 'pcUpgradeConfirmBody', 'pcUpgradeConfirmYes', 'pcUpgradeConfirmNo',
  'pcUpgradeActivating', 'pcUpgradeDone', 'pcUpgradeFailed', 'pcUpgradeDeferred', 'pcUpgradeRefreshPlan',
];

void main() {
  group('Lot 2 — annualPurchaseActivated (PRODUIT exact, pas juste premium)', () {
    test('Annual dans activeSubscriptions → activé', () {
      expect(
        annualPurchaseActivated(
          activeSubscriptions: [kAnnualProductId],
          premiumProductId: null,
          expectedProductId: kAnnualProductId,
        ),
        isTrue,
      );
    });
    test('entitlement premium porté par l\'Annual → activé', () {
      expect(
        annualPurchaseActivated(
          activeSubscriptions: const [],
          premiumProductId: kAnnualProductId,
          expectedProductId: kAnnualProductId,
        ),
        isTrue,
      );
    });
    test('CAS CLÉ : premium déjà actif via WEEKLY, Annual ABSENT → NON activé', () {
      expect(
        annualPurchaseActivated(
          activeSubscriptions: const [_weeklyId], // toujours Weekly
          premiumProductId: _weeklyId, // premium porté par Weekly
          expectedProductId: kAnnualProductId,
        ),
        isFalse,
      );
    });
    test('ni actif ni porteur → non activé', () {
      expect(
        annualPurchaseActivated(
          activeSubscriptions: const [],
          premiumProductId: null,
          expectedProductId: kAnnualProductId,
        ),
        isFalse,
      );
    });
  });

  group('Lot 2 — upgradeConfirmed (annual + product exact + capacité >= 300)', () {
    test('annual + product exact + 300 → confirmé', () {
      expect(upgradeConfirmed(_status(planType: 'annual', productId: kAnnualProductId, credits: 300)), isTrue);
    });
    test('annual + product exact + 305 (reliquat free accepté) → confirmé', () {
      expect(upgradeConfirmed(_status(planType: 'annual', productId: kAnnualProductId, credits: 305)), isTrue);
    });
    test('annual + product exact + 299 (Spaces pas encore projetés) → NON confirmé', () {
      expect(upgradeConfirmed(_status(planType: 'annual', productId: kAnnualProductId, credits: 299)), isFalse);
    });
    test('annual + product exact + 0 / 18 → NON confirmé', () {
      expect(upgradeConfirmed(_status(planType: 'annual', productId: kAnnualProductId, credits: 0)), isFalse);
      expect(upgradeConfirmed(_status(planType: 'annual', productId: kAnnualProductId, credits: 18)), isFalse);
    });
    test('annual mais product-id différent (+300) → NON confirmé', () {
      expect(upgradeConfirmed(_status(planType: 'annual', productId: _weeklyId, credits: 300)), isFalse);
    });
    test('encore weekly → NON confirmé', () {
      expect(upgradeConfirmed(_status(planType: 'weekly', productId: _weeklyId, credits: 18)), isFalse);
    });
    test('null → NON confirmé', () {
      expect(upgradeConfirmed(null), isFalse);
    });
  });

  group('Lot 2 — shouldRenderUpgrade (garde de rendu du CTA)', () {
    final weekly = premiumCenterViewFor(_status(planType: 'weekly', credits: 18, productId: _weeklyId));
    final annual =
        premiumCenterViewFor(_status(planType: 'annual', credits: 300, productId: kAnnualProductId));

    test('weekly + package Annual disponible → CTA rendu', () {
      expect(shouldRenderUpgrade(weekly, annualAvailable: true), isTrue);
    });
    test('weekly + package Annual ABSENT → CTA masqué (gracieux)', () {
      expect(shouldRenderUpgrade(weekly, annualAvailable: false), isFalse);
    });
    test('annual → jamais de CTA même si package disponible', () {
      expect(shouldRenderUpgrade(annual, annualAvailable: true), isFalse);
    });
  });

  group('Lot 2 — runAnnualUpgrade (orchestrateur)', () {
    test('annulation → cancelled, AUCUN /purchases/sync, UNE seule tentative', () async {
      var synced = 0, purchased = 0;
      final r = await runAnnualUpgrade(
        purchase: () async {
          purchased++;
          return PurchaseAttempt.cancelled;
        },
        syncAndRefresh: () async => synced++,
        readStatus: () => null,
      );
      expect(r, UpgradeResult.cancelled);
      expect(synced, 0);
      expect(purchased, 1);
    });

    test('échec (produit Annual non confirmé) → failed, AUCUN sync, statut inchangé', () async {
      var synced = 0;
      final r = await runAnnualUpgrade(
        purchase: () async => PurchaseAttempt.failed,
        syncAndRefresh: () async => synced++,
        readStatus: () => _status(planType: 'weekly', credits: 18, productId: _weeklyId),
      );
      expect(r, UpgradeResult.failed);
      expect(synced, 0);
    });

    test('succès + backend annual & product-id exact → confirmed (sync appelé)', () async {
      var synced = 0;
      final r = await runAnnualUpgrade(
        purchase: () async => PurchaseAttempt.activated,
        syncAndRefresh: () async => synced++,
        readStatus: () => _status(planType: 'annual', productId: kAnnualProductId, credits: 300),
      );
      expect(r, UpgradeResult.confirmed);
      expect(synced, 1);
    });

    test('succès mais backend encore weekly → deferred', () async {
      final r = await runAnnualUpgrade(
        purchase: () async => PurchaseAttempt.activated,
        syncAndRefresh: () async {},
        readStatus: () => _status(planType: 'weekly', credits: 18, productId: _weeklyId),
      );
      expect(r, UpgradeResult.deferred);
    });

    test('succès annual+product mais Spaces pas encore projetés (299) → deferred', () async {
      final r = await runAnnualUpgrade(
        purchase: () async => PurchaseAttempt.activated,
        syncAndRefresh: () async {},
        readStatus: () => _status(planType: 'annual', productId: kAnnualProductId, credits: 299),
      );
      expect(r, UpgradeResult.deferred);
    });

    test('succès mais sync/refresh en erreur → deferred (achat préservé)', () async {
      final r = await runAnnualUpgrade(
        purchase: () async => PurchaseAttempt.activated,
        syncAndRefresh: () async => throw Exception('network'),
        readStatus: () => _status(planType: 'annual', productId: kAnnualProductId),
      );
      expect(r, UpgradeResult.deferred);
    });
  });

  group('Lot 2 — copie de confirmation + traductions', () {
    test('confirmation EN : 300 Spaces + remplacement + proration prudente (pas de montant)', () {
      final body = enTranslations['pcUpgradeConfirmBody']!;
      expect(body.contains('300 Spaces'), isTrue);
      expect(body.toLowerCase().contains('replaced'), isTrue);
      expect(body.toLowerCase().contains('prorated'), isTrue);
    });

    test('« Spaces » (unité produit) conservé dans les 3 langues, jamais traduit', () {
      for (final m in [enTranslations, frTranslations, kmTranslations]) {
        expect(m['pcUpgradeSpaces'], '300 Spaces');
        expect(m['pcUpgradeConfirmBody']!.contains('300 Spaces'), isTrue);
      }
      // FR/KM ne doivent PAS retomber sur une traduction physique de « Spaces ».
      expect(frTranslations['pcUpgradeSpaces']!.contains('espaces'), isFalse);
      expect(kmTranslations['pcUpgradeSpaces']!.contains('កន្លែង'), isFalse);
    });

    test('EN / FR / KM : toutes les clés upgrade présentes et non vides', () {
      for (final k in _upgradeKeys) {
        expect(enTranslations[k]?.isNotEmpty ?? false, isTrue, reason: 'EN manque $k');
        expect(frTranslations[k]?.isNotEmpty ?? false, isTrue, reason: 'FR manque $k');
        expect(kmTranslations[k]?.isNotEmpty ?? false, isTrue, reason: 'KM manque $k');
      }
    });
  });
}
