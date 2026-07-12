// Lot 2 — WIDGET-TESTS du Premium Center avec INJECTION de dépendances (UpgradeDeps) + provider
// meStatusProvider.forTest → aucun appel RevenueCat/Supabase réel. Couvre : carte visible/masquée,
// dialog de confirmation, Not now (pas d'achat), double-tap (1 achat), spinner + CTA désactivé,
// annulation (pas de sync), échec (message + CTA réactivé), succès confirmé (carte disparaît),
// deferred (carte "Refresh plan"), Refresh plan (sync only, jamais purchase), Manage/Restore présents.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/core/providers/me_status_provider.dart';
import 'package:ai_home_architect/data/services/revenuecat_service.dart' show PurchaseAttempt;
import 'package:ai_home_architect/data/services/status_service.dart';
import 'package:ai_home_architect/features/premium/premium_center_sheet.dart';
import 'package:ai_home_architect/shared/widgets/app_button.dart';

MeStatus _weekly() => MeStatus(
      isPremium: true, isAdmin: false, role: 'x', quotaUsed: 0, quotaLimit: 3,
      remainingFreeGenerations: 0, accessSource: 'pass', planType: 'weekly',
      availableCredits: 18, activeProductId: 'com.aydenstudio.app.weekly',
    );

MeStatus _annual() => MeStatus(
      isPremium: true, isAdmin: false, role: 'x', quotaUsed: 0, quotaLimit: 3,
      remainingFreeGenerations: 0, accessSource: 'pass', planType: 'annual',
      availableCredits: 300, activeProductId: kAnnualProductId,
    );

/// Annual actif MAIS Spaces pas encore projetés (capacité < 300) → doit rester « deferred ».
MeStatus _annual299() => MeStatus(
      isPremium: true, isAdmin: false, role: 'x', quotaUsed: 0, quotaLimit: 3,
      remainingFreeGenerations: 0, accessSource: 'pass', planType: 'annual',
      availableCredits: 299, activeProductId: kAnnualProductId,
    );

class _FakeDeps {
  int purchaseCalls = 0;
  int syncCalls = 0;
  final bool annualAvailable;
  final PurchaseAttempt result;
  final Completer<PurchaseAttempt>? gate; // si non-null : purchase attend ce completer
  final Future<void> Function()? onSync;
  _FakeDeps({this.annualAvailable = true, this.result = PurchaseAttempt.activated, this.gate, this.onSync});

  UpgradeDeps build() => UpgradeDeps(
        loadAnnualAvailable: () async => annualAvailable,
        purchase: () async {
          purchaseCalls++;
          if (gate != null) return gate!.future;
          return result;
        },
        syncAndRefresh: () async {
          syncCalls++;
          if (onSync != null) await onSync!();
        },
      );
}

Future<void> _pump(WidgetTester tester, MeStatusNotifier notifier, MeStatus initial, UpgradeDeps deps) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [meStatusProvider.overrideWith((ref) => notifier)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: PremiumCenterSheet(status: initial, deps: deps)),
    ),
  ));
  await tester.pumpAndSettle();
}

// Finders (labels EN). CTA = AppButton ; confirmation dialog = FilledButton (désambiguïse
// « Upgrade to Annual » présent aux 2 endroits quand le dialog est ouvert).
final _cta = find.widgetWithText(AppButton, 'Upgrade to Annual');
final _confirm = find.widgetWithText(FilledButton, 'Upgrade to Annual');
final _card = find.text('UPGRADE YOUR PLAN'); // titre de la carte upgrade
final _dialogNo = find.text('Not now');

void main() {
  testWidgets('Weekly + Annual dispo → carte Upgrade visible', (tester) async {
    await _pump(tester, MeStatusNotifier.forTest(_weekly()), _weekly(), _FakeDeps(annualAvailable: true).build());
    expect(_card, findsOneWidget);
    expect(_cta, findsOneWidget);
  });

  testWidgets('Weekly + package Annual ABSENT → carte masquée', (tester) async {
    await _pump(tester, MeStatusNotifier.forTest(_weekly()), _weekly(), _FakeDeps(annualAvailable: false).build());
    expect(_card, findsNothing);
  });

  testWidgets('Annual → jamais de carte Upgrade, mais Restore présent', (tester) async {
    await _pump(tester, MeStatusNotifier.forTest(_annual()), _annual(), _FakeDeps().build());
    expect(_card, findsNothing);
    expect(find.text('Restore Purchase'), findsOneWidget);
  });

  testWidgets('Tap Upgrade → dialog de confirmation', (tester) async {
    await _pump(tester, MeStatusNotifier.forTest(_weekly()), _weekly(), _FakeDeps().build());
    await tester.tap(_cta);
    await tester.pumpAndSettle();
    expect(find.text('Upgrade to Annual?'), findsOneWidget);
    expect(_dialogNo, findsOneWidget);
  });

  testWidgets('Not now → aucun achat', (tester) async {
    final fake = _FakeDeps();
    await _pump(tester, MeStatusNotifier.forTest(_weekly()), _weekly(), fake.build());
    await tester.tap(_cta);
    await tester.pumpAndSettle();
    await tester.tap(_dialogNo);
    await tester.pumpAndSettle();
    expect(fake.purchaseCalls, 0);
    expect(fake.syncCalls, 0);
    expect(_card, findsOneWidget); // toujours Weekly
  });

  testWidgets('Double tap → une seule tentative d\'achat', (tester) async {
    final fake = _FakeDeps();
    await _pump(tester, MeStatusNotifier.forTest(_weekly()), _weekly(), fake.build());
    await tester.tap(_cta);
    await tester.tap(_cta, warnIfMissed: false); // 2ᵉ tap immédiat → garde _upgrading
    await tester.pumpAndSettle();
    expect(_dialogNo, findsOneWidget); // une seule dialog
    await tester.tap(_confirm); // confirmer (seul le bouton dialog a le texte)
    await tester.pumpAndSettle();
    expect(fake.purchaseCalls, 1);
  });

  testWidgets('Pendant l\'achat → spinner + CTA désactivé (2ᵉ tap ignoré)', (tester) async {
    final gate = Completer<PurchaseAttempt>();
    final notifier = MeStatusNotifier.forTest(_weekly());
    final fake = _FakeDeps(gate: gate, onSync: () async => notifier.debugSetStatus(_annual()));
    await _pump(tester, notifier, _weekly(), fake.build());
    await tester.tap(_cta);
    await tester.pumpAndSettle();
    await tester.tap(_confirm); // confirmer
    await tester.pump(); // achat en cours (gate non résolu)
    expect(find.byType(CircularProgressIndicator), findsWidgets); // spinner
    expect(fake.purchaseCalls, 1);
    await tester.tap(find.byType(AppButton).first, warnIfMissed: false); // CTA désactivé
    await tester.pump();
    expect(fake.purchaseCalls, 1); // toujours 1
    gate.complete(PurchaseAttempt.activated);
    await tester.pumpAndSettle();
  });

  testWidgets('Annulation Apple → aucun sync, reste Weekly', (tester) async {
    final fake = _FakeDeps(result: PurchaseAttempt.cancelled);
    await _pump(tester, MeStatusNotifier.forTest(_weekly()), _weekly(), fake.build());
    await tester.tap(_cta);
    await tester.pumpAndSettle();
    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    expect(fake.purchaseCalls, 1);
    expect(fake.syncCalls, 0); // AUCUN /purchases/sync
    expect(_card, findsOneWidget); // toujours Weekly, CTA visible
    expect(find.byType(CircularProgressIndicator), findsNothing); // CTA réactivé
  });

  testWidgets('Échec → message honnête, aucun sync, CTA réactivé', (tester) async {
    final fake = _FakeDeps(result: PurchaseAttempt.failed);
    await _pump(tester, MeStatusNotifier.forTest(_weekly()), _weekly(), fake.build());
    await tester.tap(_cta);
    await tester.pumpAndSettle();
    await tester.tap(_confirm);
    await tester.pump(); // exécute le flux (achat échoué instantané)
    await tester.pump(const Duration(milliseconds: 750)); // anime le snackbar d'erreur
    expect(fake.syncCalls, 0);
    expect(find.text("We couldn't complete the upgrade. Please try again."), findsOneWidget);
    expect(_card, findsOneWidget); // reste Weekly, CTA de nouveau dispo
    expect(find.byType(CircularProgressIndicator), findsNothing); // CTA réactivé
  });

  testWidgets('Succès confirmé (annual + product-id) → carte Upgrade disparaît', (tester) async {
    final notifier = MeStatusNotifier.forTest(_weekly());
    final fake = _FakeDeps(result: PurchaseAttempt.activated, onSync: () async => notifier.debugSetStatus(_annual()));
    await _pump(tester, notifier, _weekly(), fake.build());
    await tester.tap(_cta);
    await tester.pumpAndSettle();
    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    expect(fake.purchaseCalls, 1);
    expect(fake.syncCalls, 1);
    expect(_card, findsNothing); // passé en Annual → plus de CTA
  });

  testWidgets('Sync différé → carte "Refresh plan" ; Refresh relance sync SANS rachat', (tester) async {
    // onSync ne flippe PAS le statut → reste weekly → deferred.
    final notifier = MeStatusNotifier.forTest(_weekly());
    final fake = _FakeDeps(result: PurchaseAttempt.activated);
    await _pump(tester, notifier, _weekly(), fake.build());
    await tester.tap(_cta);
    await tester.pumpAndSettle();
    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    expect(find.text('Refresh plan'), findsOneWidget);
    expect(fake.purchaseCalls, 1);
    final syncBefore = fake.syncCalls; // 1
    await tester.tap(find.text('Refresh plan'));
    await tester.pumpAndSettle();
    expect(fake.purchaseCalls, 1); // Refresh ne rappelle JAMAIS purchase
    expect(fake.syncCalls, syncBefore + 1); // sync relancé
  });

  testWidgets('Annual actif mais 299 (Spaces pas projetés) → Refresh plan ; refresh→300 la fait disparaître',
      (tester) async {
    final notifier = MeStatusNotifier.forTest(_weekly());
    var synced = 0;
    // 1er sync → annual mais 299 (deferred) ; 2e sync (Refresh plan) → annual 300 (confirmé).
    final deps = UpgradeDeps(
      loadAnnualAvailable: () async => true,
      purchase: () async => PurchaseAttempt.activated,
      syncAndRefresh: () async {
        synced++;
        notifier.debugSetStatus(synced >= 2 ? _annual() : _annual299());
      },
    );
    await _pump(tester, notifier, _weekly(), deps);
    await tester.tap(_cta);
    await tester.pumpAndSettle();
    await tester.tap(_confirm);
    await tester.pumpAndSettle();
    expect(find.text('Refresh plan'), findsOneWidget); // 299 → deferred, pas de faux succès
    await tester.tap(find.text('Refresh plan'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh plan'), findsNothing); // 300 → carte deferred disparaît
    expect(_card, findsNothing); // Annual confirmé
  });
}
