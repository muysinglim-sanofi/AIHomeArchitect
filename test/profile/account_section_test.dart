// AccountSection widget tests — no network/SDK. Uses the widget's injectable
// seam (isAnonymous / onLink / onConnectExisting / onRetry) to drive state +
// results without Supabase/Apple/RevenueCat. Proves anonymous↔connected
// rendering, the failed-link reveal, live refresh to Connected in place, the
// dormant "not available" path, pending≠success, the claim-only Retry, terminal
// with no retry, and that NO technical data (UUID/JWT/status/error_code/ticket)
// is ever shown.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/features/profile/account_link.dart';
import 'package:ai_home_architect/features/profile/account_section.dart';

final _l10n = AppLocalizations(const Locale('en'));

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AccountSection — rendering', () {
    testWidgets('anonymous → section + subtitle + Continue with Apple', (
      tester,
    ) async {
      await _pump(tester, AccountSection(isAnonymous: () => true));
      expect(find.text(_l10n.acctSectionTitle), findsOneWidget);
      expect(find.text(_l10n.acctSaveDesignsSubtitle), findsOneWidget);
      expect(find.text(_l10n.acctContinueWithApple), findsOneWidget);
      expect(find.text(_l10n.acctConnectedWithApple), findsNothing);
      expect(find.text(_l10n.acctSignInExisting), findsNothing);
    });

    testWidgets('signed-in → Connected, no Continue CTA', (tester) async {
      await _pump(tester, AccountSection(isAnonymous: () => false));
      expect(find.text(_l10n.acctConnectedWithApple), findsOneWidget);
      expect(find.text(_l10n.acctContinueWithApple), findsNothing);
    });
  });

  group('AccountSection — link (new identity)', () {
    testWidgets(
      'failed link → generic message + reveals existing CTA, no auto sign-in',
      (tester) async {
        var connectCalls = 0;
        await _pump(
          tester,
          AccountSection(
            isAnonymous: () => true,
            onLink: () async => LinkNewIdentityResult.failed,
            onConnectExisting: () async {
              connectCalls++;
              return const ConnectExistingAttempt(
                outcome: ConnectExistingResult.notAvailable,
              );
            },
          ),
        );
        await tester.tap(find.text(_l10n.acctContinueWithApple));
        await tester.pumpAndSettle();

        expect(find.text(_l10n.acctAppleAlreadyLinked), findsOneWidget);
        expect(find.text(_l10n.acctSignInExisting), findsOneWidget);
        expect(connectCalls, 0);
      },
    );

    testWidgets('successful link → UI refreshes to Connected in place', (
      tester,
    ) async {
      var anon = true;
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => anon,
          onLink: () async {
            anon = false;
            return LinkNewIdentityResult.success;
          },
        ),
      );
      await tester.tap(find.text(_l10n.acctContinueWithApple));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.acctContinueWithApple), findsNothing);
      expect(find.text(_l10n.acctConnectedWithApple), findsOneWidget);
    });
  });

  group('AccountSection — connect existing', () {
    // Reveal the "Sign in to my existing account" CTA then tap it, returning
    // [attempt] from the connect flow (which also flips the user to signed-in).
    Future<void> reveal(
      WidgetTester tester, {
      required ConnectExistingAttempt attempt,
      Future<ConnectExistingAttempt> Function(String ticket)? onRetry,
      void Function()? onConnect,
    }) async {
      var anon = true;
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => anon,
          onLink: () async => LinkNewIdentityResult.failed,
          onConnectExisting: () async {
            anon = false;
            onConnect?.call();
            return attempt;
          },
          onRetry: onRetry,
        ),
      );
      await tester.tap(find.text(_l10n.acctContinueWithApple));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.acctSignInExisting));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'merge unavailable → Not available, still anonymous, no crash',
      (tester) async {
        // isAnonymous stays true (no sign-in) for the dormant case.
        await _pump(
          tester,
          AccountSection(
            isAnonymous: () => true,
            onLink: () async => LinkNewIdentityResult.failed,
            onConnectExisting: () async => const ConnectExistingAttempt(
              outcome: ConnectExistingResult.notAvailable,
            ),
          ),
        );
        await tester.tap(find.text(_l10n.acctContinueWithApple));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_l10n.acctSignInExisting));
        await tester.pumpAndSettle();

        expect(find.text(_l10n.acctNotAvailable), findsOneWidget);
        expect(
          find.text(_l10n.acctContinueWithApple),
          findsOneWidget,
        ); // still anon
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('pending → Connected + finishing-setup, NOT full success', (
      tester,
    ) async {
      await reveal(
        tester,
        attempt: const ConnectExistingAttempt(
          outcome: ConnectExistingResult.pending,
          authConnected: true,
          claimPending: true,
        ),
      );
      expect(find.text(_l10n.acctConnectedWithApple), findsOneWidget);
      expect(
        find.text(_l10n.acctConnectedPending),
        findsWidgets,
      ); // body + snack
      expect(
        find.text(_l10n.acctConnectedSuccess),
        findsNothing,
      ); // NOT success
      expect(find.text(_l10n.acctRetrySetup), findsNothing);
    });

    testWidgets(
      'retryable → Connected + Retry button; Retry re-does claim only',
      (tester) async {
        var retryCalls = 0;
        var connectCalls = 0;
        await reveal(
          tester,
          onConnect: () => connectCalls++,
          attempt: const ConnectExistingAttempt(
            outcome: ConnectExistingResult.retryable,
            authConnected: true,
            retryTicket: 'T-1',
            retryUidBefore: 'anon',
          ),
          onRetry: (ticket) async {
            retryCalls++;
            return const ConnectExistingAttempt(
              outcome: ConnectExistingResult.success,
              authConnected: true,
              claimCompleted: true,
            );
          },
        );
        expect(find.text(_l10n.acctConnectedWithApple), findsOneWidget);
        expect(find.text(_l10n.acctRetrySetup), findsOneWidget);
        expect(connectCalls, 1);

        await tester.tap(find.text(_l10n.acctRetrySetup));
        await tester.pumpAndSettle();

        expect(retryCalls, 1); // Retry used the retry closure only…
        expect(connectCalls, 1); // …NOT a new connect/merge/sign-in
        expect(
          find.text(_l10n.acctRetrySetup),
          findsNothing,
        ); // cleared on success
        expect(find.text(_l10n.acctConnectedWithApple), findsOneWidget);
      },
    );

    testWidgets('terminal → Connected + clean note, NO Retry', (tester) async {
      await reveal(
        tester,
        attempt: const ConnectExistingAttempt(
          outcome: ConnectExistingResult.terminal,
          authConnected: true,
        ),
      );
      expect(find.text(_l10n.acctConnectedWithApple), findsOneWidget);
      expect(find.text(_l10n.acctMergeFailed), findsWidgets);
      expect(find.text(_l10n.acctRetrySetup), findsNothing);
    });
  });

  group('AccountSection — no technical data leaks', () {
    testWidgets('retryable state renders no UUID/JWT/status/ticket', (
      tester,
    ) async {
      var anon = true;
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => anon,
          onLink: () async => LinkNewIdentityResult.failed,
          onConnectExisting: () async {
            anon = false;
            return const ConnectExistingAttempt(
              outcome: ConnectExistingResult.retryable,
              authConnected: true,
              retryTicket: 'SECRET-TICKET-123',
              retryUidBefore: '11111111-2222-3333-4444-555555555555',
            );
          },
        ),
      );
      await tester.tap(find.text(_l10n.acctContinueWithApple));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.acctSignInExisting));
      await tester.pumpAndSettle();

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(
        texts.contains('SECRET-TICKET-123'),
        isFalse,
      ); // ticket never shown
      expect(texts.contains('11111111-2222'), isFalse); // no UUID
      expect(texts.contains('eyJ'), isFalse);
      expect(texts.toLowerCase().contains('bearer'), isFalse);
      expect(texts.contains('identity_already_exists'), isFalse);
      expect(RegExp(r'\b(4\d\d|5\d\d)\b').hasMatch(texts), isFalse);
    });
  });
}
