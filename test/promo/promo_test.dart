// Sprint 1B — promo data + i18n unit tests (no network/UI mocking needed).
//
// Covers: MeStatus.fromJson promo parsing + hasActivePromo priority, the
// error_code → localized message mapping, and the templated promo strings
// across EN/FR/KM. The full redeem/admin flows are device-validated (they need
// the live backend) per the manual validation guide.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/data/services/status_service.dart';

void main() {
  group('MeStatus.fromJson — promo fields', () {
    test('limited promo (free exhausted) → hasActivePromo, not premium', () {
      final s = MeStatus.fromJson(const {
        'is_premium': false,
        'is_admin': false,
        'role': 'free',
        'quota_used': 3,
        'quota_limit': 3,
        'remaining_free_generations': 0,
        'promo_generations_remaining': 25,
        'promo_unlimited_active': false,
        'active_promo_campaign': 'INFLUENCER25',
        'effective_access_state': 'promo_limited',
        'can_generate': true,
      });
      expect(s.hasActivePromo, isTrue);
      expect(s.isPremium, isFalse);
      expect(s.promoGenerationsRemaining, 25);
      expect(s.promoUnlimitedActive, isFalse);
      expect(s.activePromoCampaign, 'INFLUENCER25');
      expect(s.effectiveAccessState, 'promo_limited');
      expect(s.canGenerate, isTrue);
    });

    test('unlimited promo → hasActivePromo + unlimited flag', () {
      final s = MeStatus.fromJson(const {
        'is_premium': false,
        'promo_unlimited_active': true,
        'effective_access_state': 'promo_unlimited',
      });
      expect(s.hasActivePromo, isTrue);
      expect(s.promoUnlimitedActive, isTrue);
    });

    test('premium hides promo (premium priority)', () {
      final s = MeStatus.fromJson(const {
        'is_premium': true,
        'promo_generations_remaining': 25, // present but premium wins
      });
      expect(s.isPremium, isTrue);
      expect(s.hasActivePromo, isFalse); // premium suppresses promo display
    });

    test('plain free → no promo, defaults safe', () {
      final s = MeStatus.fromJson(const {
        'is_premium': false,
        'role': 'free',
        'quota_used': 1,
        'quota_limit': 3,
        'remaining_free_generations': 2,
      });
      expect(s.hasActivePromo, isFalse);
      expect(s.promoGenerationsRemaining, 0);
      expect(s.canGenerate, isTrue); // default when absent
      expect(s.effectiveAccessState, 'free');
    });
  });

  group('AppLocalizations — promo strings (EN/FR/KM)', () {
    final locales = [
      const Locale('en'),
      const Locale('fr'),
      const Locale('km'),
    ];

    test('promoError maps every backend code to a non-empty message', () {
      const codes = [
        'invalid_code',
        'expired_code',
        'inactive_code',
        'already_redeemed',
        'max_redemptions_reached',
        'rate_limited',
        'network',
        'something_unknown', // → generic fallback
      ];
      for (final loc in locales) {
        final l10n = AppLocalizations(loc);
        for (final c in codes) {
          expect(l10n.promoError(c).trim(), isNotEmpty,
              reason: '${loc.languageCode}/$c');
        }
      }
    });

    test('promoSuccessLimited / promoAccessLimited interpolate {n}', () {
      for (final loc in locales) {
        final l10n = AppLocalizations(loc);
        expect(l10n.promoSuccessLimited(25), contains('25'));
        expect(l10n.promoSuccessLimited(25), isNot(contains('{n}')));
        expect(l10n.promoAccessLimited(7), contains('7'));
        expect(l10n.promoAccessLimited(7), isNot(contains('{n}')));
      }
    });

    test('key promo/admin getters are localized (not raw keys)', () {
      for (final loc in locales) {
        final l10n = AppLocalizations(loc);
        for (final v in [
          l10n.promoHaveCode,
          l10n.promoApply,
          l10n.promoAccessUnlimited,
          l10n.admPromoCodes,
          l10n.admGenerateCode,
          l10n.admCreate,
        ]) {
          expect(v.trim(), isNotEmpty);
          expect(v.startsWith('promo'), isFalse); // not the raw key
          expect(v.startsWith('adm'), isFalse);
        }
      }
    });
  });
}
