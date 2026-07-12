// RC-PR3b — routing du PREFLIGHT génératif.
//  • Décision PURE (generationPreflightDestinationFor) : proceed + 3 destinations de deny.
//  • Intégration (ensureCanGenerateOrShowPaywall) via un PRESENTER INJECTÉ (seam de test) :
//    prouve que le hot path autorisé (`proceed`) rend `true` SANS appeler le presenter et SANS
//    l'attendre, et que le deny appelle le presenter EXACTEMENT une fois avec la bonne surface.
//    On n'ouvre PAS les vraies sheets ici (le vrai PaywallSheet dépend de Supabase/RevenueCat).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_home_architect/core/billing/generation_preflight.dart';
import 'package:ai_home_architect/core/providers/me_status_provider.dart';
import 'package:ai_home_architect/data/services/status_service.dart';

MeStatus _st({
  required bool canGenerate,
  required String accessSource,
  String gateReason = '',
  String planType = 'none',
}) =>
    MeStatus(
      isPremium: accessSource != 'free' && accessSource != 'restore_required',
      isAdmin: accessSource == 'admin',
      role: 'x',
      quotaUsed: 0,
      quotaLimit: 3,
      remainingFreeGenerations: 0,
      accessSource: accessSource,
      gateReason: gateReason,
      planType: planType,
      canGenerate: canGenerate,
    );

void main() {
  group('RC-PR3b — generationPreflightDestinationFor (décision pure)', () {
    test('canGenerate=true + promo → proceed (jamais de paywall dans l\'état normal)', () {
      expect(generationPreflightDestinationFor(_st(canGenerate: true, accessSource: 'promo')),
          GenerationPreflightDestination.proceed);
    });
    test('canGenerate=true + admin → proceed', () {
      expect(generationPreflightDestinationFor(_st(canGenerate: true, accessSource: 'admin')),
          GenerationPreflightDestination.proceed);
    });
    test('canGenerate=true + pass (avec solde) → proceed', () {
      expect(
          generationPreflightDestinationFor(
              _st(canGenerate: true, accessSource: 'pass', planType: 'annual')),
          GenerationPreflightDestination.proceed);
    });

    test('canGenerate=false + free + insufficient_credits → freePaywall', () {
      expect(
          generationPreflightDestinationFor(_st(
              canGenerate: false, accessSource: 'free', gateReason: 'insufficient_credits')),
          GenerationPreflightDestination.freePaywall);
    });

    test('canGenerate=false + pass weekly + pass_exhausted → passExhausted', () {
      expect(
          generationPreflightDestinationFor(_st(
              canGenerate: false, accessSource: 'pass', planType: 'weekly',
              gateReason: 'pass_exhausted')),
          GenerationPreflightDestination.passExhausted);
    });
    test('canGenerate=false + pass annual + pass_exhausted → passExhausted', () {
      expect(
          generationPreflightDestinationFor(_st(
              canGenerate: false, accessSource: 'pass', planType: 'annual',
              gateReason: 'pass_exhausted')),
          GenerationPreflightDestination.passExhausted);
    });

    test('canGenerate=false + restore_required → restoreRequired', () {
      expect(
          generationPreflightDestinationFor(
              _st(canGenerate: false, accessSource: 'restore_required')),
          GenerationPreflightDestination.restoreRequired);
    });

    test('CAS CLÉ : pass + no_active_pass → restoreRequired (proposer Restore, PAS un rachat)', () {
      final d = generationPreflightDestinationFor(_st(
          canGenerate: false, accessSource: 'pass', gateReason: 'no_active_pass'));
      expect(d, GenerationPreflightDestination.restoreRequired);
      // Et surtout : ni un rachat d'abonnement (freePaywall) ni « Spaces épuisés » (passExhausted).
      expect(d, isNot(GenerationPreflightDestination.freePaywall));
      expect(d, isNot(GenerationPreflightDestination.passExhausted));
    });

    test('no_active_pass prime pass_exhausted quand les deux seraient possibles (ordre des gardes)',
        () {
      // gateReason == 'no_active_pass' → restore, même avec accessSource 'pass'.
      expect(
          generationPreflightDestinationFor(_st(
              canGenerate: false, accessSource: 'pass', gateReason: 'no_active_pass')),
          GenerationPreflightDestination.restoreRequired);
    });
  });

  group('RC-PR3b — ensureCanGenerateOrShowPaywall (intégration, presenter injecté)', () {
    // Monte un bouton qui appelle la porte avec un PRESENTER INJECTÉ. Aucune vraie sheet →
    // aucune dépendance Supabase/RevenueCat ; on observe la DÉCISION (true/false) et le ROUTAGE.
    Future<void> pumpGate(
      WidgetTester tester,
      MeStatus? status, {
      required DenyPresenter presentDeny,
      required void Function(bool) onResult,
    }) async {
      final notifier = MeStatusNotifier.forTest(status);
      await tester.pumpWidget(ProviderScope(
        overrides: [meStatusProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final r = await ensureCanGenerateOrShowPaywall(
                      ref, context, fresh: false, presentDeny: presentDeny);
                    onResult(r);
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('free épuisé → false + presenter(freePaywall) appelé EXACTEMENT une fois',
        (tester) async {
      int calls = 0;
      GenerationPreflightDestination? routed;
      bool? result;
      await pumpGate(
        tester,
        _st(canGenerate: false, accessSource: 'free', gateReason: 'insufficient_credits'),
        presentDeny: (ref, context, dest) async {
          calls++;
          routed = dest;
        },
        onResult: (r) => result = r,
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(result, isFalse);
      expect(calls, 1);
      expect(routed, GenerationPreflightDestination.freePaywall);
    });

    testWidgets('pass épuisé (weekly) → false + presenter(passExhausted), JAMAIS freePaywall',
        (tester) async {
      int calls = 0;
      GenerationPreflightDestination? routed;
      bool? result;
      await pumpGate(
        tester,
        _st(canGenerate: false, accessSource: 'pass', planType: 'weekly', gateReason: 'pass_exhausted'),
        presentDeny: (ref, context, dest) async {
          calls++;
          routed = dest;
        },
        onResult: (r) => result = r,
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(result, isFalse);
      expect(calls, 1);
      expect(routed, GenerationPreflightDestination.passExhausted);
    });

    testWidgets('restore_required → false + presenter(restoreRequired)', (tester) async {
      int calls = 0;
      GenerationPreflightDestination? routed;
      bool? result;
      await pumpGate(
        tester,
        _st(canGenerate: false, accessSource: 'restore_required'),
        presentDeny: (ref, context, dest) async {
          calls++;
          routed = dest;
        },
        onResult: (r) => result = r,
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(result, isFalse);
      expect(calls, 1);
      expect(routed, GenerationPreflightDestination.restoreRequired);
    });

    testWidgets('no_active_pass → false + presenter(restoreRequired) (bout-en-bout via la porte)',
        (tester) async {
      int calls = 0;
      GenerationPreflightDestination? routed;
      bool? result;
      await pumpGate(
        tester,
        _st(canGenerate: false, accessSource: 'pass', gateReason: 'no_active_pass'),
        presentDeny: (ref, context, dest) async {
          calls++;
          routed = dest;
        },
        onResult: (r) => result = r,
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(result, isFalse);
      expect(calls, 1);
      expect(routed, GenerationPreflightDestination.restoreRequired);
    });

    testWidgets('proceed (canGenerate=true) → true SANS appeler le presenter (hot path inchangé)',
        (tester) async {
      int calls = 0;
      bool? result;
      await pumpGate(
        tester,
        _st(canGenerate: true, accessSource: 'pass', planType: 'annual'),
        presentDeny: (ref, context, dest) async {
          calls++;
        },
        onResult: (r) => result = r,
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(result, isTrue);
      expect(calls, 0); // aucune surface, aucun await ajouté sur le chemin autorisé
    });

    testWidgets(
        'proceed → true MÊME si le presenter ne se résout JAMAIS (le hot path ne l\'attend pas)',
        (tester) async {
      final never = Completer<void>(); // ne se complète jamais
      bool? result;
      await pumpGate(
        tester,
        _st(canGenerate: true, accessSource: 'pass', planType: 'annual'),
        presentDeny: (ref, context, dest) => never.future,
        onResult: (r) => result = r,
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      // Si le hot path attendait le presenter, `result` resterait null pour toujours.
      expect(result, isTrue);
    });

    testWidgets('statut inconnu (null) → true (fail-open) SANS presenter (le HOLD atomique décide)',
        (tester) async {
      int calls = 0;
      bool? result;
      await pumpGate(
        tester,
        null,
        presentDeny: (ref, context, dest) async {
          calls++;
        },
        onResult: (r) => result = r,
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(result, isTrue);
      expect(calls, 0);
    });
  });
}
