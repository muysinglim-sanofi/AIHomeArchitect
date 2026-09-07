// Round 3 — what the phone found, pinned.
//
// Two of the four phone findings are testable without a device, and both were
// the same kind of defect: a screen that changed its data but not its shape.
//
//   RCN — Create Vision from the Full Reveal cleared the pending bar and left
//         the person on the reveal while the render was made off-screen.
//         iOS pops back to the chat the instant Generate is pressed
//         (`context.pop(_selectedAtmosphere)`); now so does the web.
//   PWL — the paywall opened from Profile by a person holding a balance was a
//         92%-tall dark sheet with a title, one line and "Not now" in its top
//         third, and nothing below. The catalogue is now on offer whenever
//         the server lists a pack, and the sheet lays its content out against
//         its own height instead of against the content's length.

import 'dart:typed_data';

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/core/providers/locale_provider.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_route.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_paywall.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AydenImageSource _source() => AydenImageSource(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      filename: 'room.jpg',
      mimeType: 'image/jpeg',
    );

/// A session with one Vision, opened in its Full Reveal, and a generation
/// service whose next call stays in flight for [hold].
Future<(PwaController, PwaFakeGenerationService)> _revealSession({
  Duration hold = const Duration(minutes: 5),
}) async {
  final gen = PwaFakeGenerationService();
  final c = PwaController(
    MockPwaExperienceRepository(workDelay: Duration.zero, seedLibrary: false),
    generation: gen,
    pending: PwaMemoryPendingGenerationStore(),
  );
  c.selectRoom('livingRoom');
  c.setSource(_source());
  await c.generateFirstVision();
  gen.calls.clear();
  gen.delay = hold;
  c.openReveal(c.state.currentVisionId!);
  expect(c.state.phase, PwaPhase.reveal, reason: 'precondition');
  return (c, gen);
}

void _unawaited(Future<void> f) {}

void main() {
  group('RCN  Create Vision from the Full Reveal returns to the conversation',
      () {
    test('RCN01: the phase is the Architect the instant Create is confirmed',
        () async {
      final (c, gen) = await _revealSession();
      final projectId = c.state.activeProjectId;
      c.stageAtmosphere('japandi_calm');
      expect(c.state.pendingAtmosphereId, 'japandi_calm');
      expect(c.state.phase, PwaPhase.reveal,
          reason: 'staging alone moves nothing — iOS parity');

      _unawaited(c.applyAtmosphere());
      // No awaiting the render: the whole point is what is true BEFORE it.
      expect(c.state.phase, PwaPhase.architect,
          reason: 'iOS pops the reveal on Generate; the web must not wait');
      expect(c.state.generating, isTrue);
      expect(c.state.pendingAtmosphereId, isNull);
      expect(c.state.previewVisionId, isNull,
          reason: 'land on the working bubble, not on the explored vision');
      expect(c.state.activeProjectId, projectId,
          reason: 'the SAME session — no new project, no new conversation');
      expect(
        c.state.canonicalRoute,
        PwaRoute(PwaPage.architect, projectId: projectId),
        reason: 'the address is the conversation, immediately',
      );

      // The pending state is visible INSIDE the conversation.
      final loading = c.state.messages.lastWhere(
        (m) => m.kind == PwaMessageKind.loading,
      );
      expect(loading.workingKind, PwaWorkKind.switchAtmosphere);
      expect(loading.workingSubject, 'Japandi Calm');

      // Exactly one request, for exactly the atmosphere that was chosen.
      await Future<void>.delayed(Duration.zero);
      expect(gen.calls, hasLength(1));
      expect(gen.calls.single.atmosphereId, 'japandi_calm');
      expect(gen.calls.single.parentVisionId, c.state.versions.first.versionId);
    });

    test('RCN02: while it is working, a second confirm spends nothing',
        () async {
      final (c, gen) = await _revealSession();
      c.stageAtmosphere('japandi_calm');
      _unawaited(c.applyAtmosphere());
      await Future<void>.delayed(Duration.zero);

      // Anything a person could still tap: stage again, confirm again.
      c.stageAtmosphere('soft_luxury');
      expect(c.state.pendingAtmosphereId, isNull,
          reason: 'staging is refused while a generation is in flight');
      await c.applyAtmosphere();
      await Future<void>.delayed(Duration.zero);
      expect(gen.calls, hasLength(1),
          reason: 'one tap = one generation = one Space');
    });

    test('RCN03: the result joins the same conversation as Vision 2',
        () async {
      final (c, gen) = await _revealSession(hold: Duration.zero);
      final projectId = c.state.activeProjectId;
      final v1 = c.state.versions.single.versionId;
      c.stageAtmosphere('japandi_calm');
      await c.applyAtmosphere();

      expect(c.state.phase, PwaPhase.architect);
      expect(c.state.generating, isFalse);
      expect(c.state.activeProjectId, projectId);
      expect(c.state.versions, hasLength(2));
      final v2 = c.state.versions.last;
      expect(v2.atmosphereId, 'japandi_calm',
          reason: 'the atmosphere chosen in the reveal is the one generated');
      expect(v2.parentVersionId, v1, reason: 'lineage: a child of Vision 1');
      expect(c.state.currentVisionId, v2.versionId);
      expect(
        c.state.messages.where((m) => m.kind == PwaMessageKind.loading),
        isEmpty,
        reason: 'the working bubble was replaced, not left behind',
      );
      expect(
        c.state.messages.last.kind,
        PwaMessageKind.reveal,
        reason: 'the render arrives as a message in the conversation',
      );
      expect(gen.calls, hasLength(1));
    });

    test('RCN04: Back from the reveal still keeps the explored vision in view',
        () async {
      // The preview is cleared on a SWITCH only; the plain return keeps it so
      // the Architect can scroll to the vision that was being looked at.
      final (c, _) = await _revealSession();
      final id = c.state.currentVisionId;
      c.backToConversation();
      expect(c.state.phase, PwaPhase.architect);
      expect(c.state.previewVisionId, id);
    });
  });

  group('PWL  the paywall fills its own height', () {
    Future<void> pumpPaywall(
      WidgetTester tester, {
      required Size size,
      required Map<String, Object?> entitlement,
      String locale = 'en',
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = PwaEntitlementController(() async => entitlement);
      await controller.refresh();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          pwaEntitlementProvider.overrideWith((ref) => controller),
          localeProvider.overrideWith(
              (ref) => LocaleNotifier(deviceLocale: locale)),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('km'), Locale('fr')],
          home: const Scaffold(body: PwaPaywallSheet()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// A person holding Spaces, with one pack the web can sell.
    const holding300 = <String, Object?>{
      'can_generate': true,
      'billing_state': 'FREE_AVAILABLE',
      'free_credits': 300,
      'credits_available': 300,
      'payment': {'provider': 'khqr', 'configured': true},
      'products': [
        {
          'sku': 'pack_10',
          'type': 'CREDIT_PACK',
          'credits': 10,
          'price_usd': 1.99,
          'currency': 'USD',
          'store_only': false,
          'web_enabled': true,
        },
      ],
    };

    for (final size in const [Size(390, 844), Size(430, 932), Size(1440, 900)]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('PWL01 @$label: a holder of Spaces is offered the catalogue',
          (tester) async {
        await pumpPaywall(tester, size: size, entitlement: holding300);
        final l = pwaL10nFor(const Locale('en'));

        // The state is not a refusal (PWL05 pins the gate) — and yet the pack
        // and the one CTA are there to be chosen.
        expect(find.byKey(const ValueKey('pwa-pack-pack_10')), findsOneWidget);
        expect(find.byKey(const ValueKey('pwa-paywall-continue')),
            findsOneWidget);
        // The balance it states is the real one, not "1 free vision".
        expect(find.text(l.passSpacesLeft(300)), findsOneWidget);
        expect(find.text(l.freeVisionAvailable), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('PWL02 @$label: the footer reaches the bottom of the sheet',
          (tester) async {
        await pumpPaywall(tester, size: size, entitlement: holding300);

        final sheet = tester.getRect(find.byType(PwaPaywallSheet));
        expect(sheet.height, closeTo(size.height * 0.94, 0.5),
            reason: 'iOS: `media.size.height * 0.94`, a fixed sheet');

        // The last thing on the sheet is "Not now". Before the fix it sat
        // wherever the content ended — about a third of the way down — and
        // the rest of the sheet was dark. Now it sits on the sheet's bottom
        // padding (24), or below it when the content is long enough to
        // scroll; either way there is no unexplained region beneath it.
        final close =
            tester.getRect(find.byKey(const ValueKey('pwa-paywall-close')));
        expect(close.bottom, greaterThanOrEqualTo(sheet.bottom - 24 - 1),
            reason: 'no dark void under the footer');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('PWL03: a refused state still shows the catalogue as before',
        (tester) async {
      await pumpPaywall(
        tester,
        size: const Size(390, 844),
        entitlement: {
          ...holding300,
          'can_generate': false,
          'billing_state': 'FREE_EXHAUSTED',
          'free_credits': 0,
          'credits_available': 0,
        },
      );
      final l = pwaL10nFor(const Locale('en'));
      expect(find.text(l.paywallFreeUsedTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-pack-pack_10')), findsOneWidget);
      expect(find.byKey(const ValueKey('pwa-paywall-continue')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PWL04: with nothing to sell, nothing is offered', (tester) async {
      await pumpPaywall(
        tester,
        size: const Size(390, 844),
        entitlement: {...holding300, 'products': <Object?>[]},
      );
      expect(find.byKey(const ValueKey('pwa-paywall-continue')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('PWL05: the gate itself is untouched', () {
      const holder = PwaEntitlement(
        state: PwaBillingState.freeAvailable,
        canGenerate: true,
        freeCredits: 300,
        creditsAvailable: 300,
      );
      expect(holder.requiresPurchase, isFalse);
      expect(holder.canGenerate, isTrue);
    });
  });
}
