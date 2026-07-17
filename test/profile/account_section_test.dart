// AccountSection widget tests — no network/SDK. Uses the widget's injectable
// seam (isAnonymous / onLink / onConnectExisting / onRetry) to drive state +
// results without Supabase/Apple/RevenueCat. Proves anonymous↔connected
// rendering, the failed-link reveal, live refresh to Connected in place, the
// dormant "not available" path, pending≠success, the claim-only Retry, terminal
// with no retry, and that NO technical data (UUID/JWT/status/error_code/ticket)
// is ever shown.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/features/profile/account_link.dart';
import 'package:ai_home_architect/features/profile/account_section.dart';
import 'package:ai_home_architect/shared/widgets/app_button.dart';

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

    // PATCH 4 (2026-07-16) — terminal SANS sign-in (Path A : échec de création du ticket →
    // encore anonyme). Le message ne doit JAMAIS affirmer « Connected » ; message NEUTRE.
    testWidgets(
      'PATCH 4 — terminal without sign-in (Path A) → neutral message, NEVER "Connected"',
      (tester) async {
        var anon = true;
        await _pump(
          tester,
          AccountSection(
            isAnonymous: () => anon, // stays anonymous: ticket creation failed, no sign-in
            onLink: () async => LinkNewIdentityResult.failed, // reveals 2nd button
            onConnectExisting: () async => const ConnectExistingAttempt(
              outcome: ConnectExistingResult.terminal,
              authConnected: false,
            ),
          ),
        );
        await tester.tap(find.text(_l10n.acctContinueWithApple));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_l10n.acctSignInExisting));
        await tester.pumpAndSettle();

        // No false "Connected." (acctMergeFailed) — the user never signed in.
        expect(find.text(_l10n.acctMergeFailed), findsNothing);
        // A neutral, honest message is shown instead.
        expect(find.text(_l10n.acctGenericError), findsWidgets);
        // Still the guest (anonymous body still visible).
        expect(find.text(_l10n.acctContinueWithApple), findsOneWidget);
      },
    );
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

  group('AccountSection — spinner isolation (per-button)', () {
    AppButton btn(WidgetTester tester, String label) => tester
        .widgetList<AppButton>(find.byType(AppButton))
        .firstWhere((b) => b.label == label);

    testWidgets('Sign in existing spins ALONE — Continue does NOT (the bug)', (
      tester,
    ) async {
      final gate = Completer<ConnectExistingAttempt>();
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => true,
          onLink: () async => LinkNewIdentityResult.failed, // reveals 2nd button
          onConnectExisting: () => gate.future, // held mid-flight
        ),
      );
      await tester.tap(find.text(_l10n.acctContinueWithApple));
      await tester.pumpAndSettle(); // reveals "Sign in to my existing account"
      await tester.tap(find.text(_l10n.acctSignInExisting));
      await tester.pump(); // one frame — action in flight
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(btn(tester, _l10n.acctSignInExisting).loading, isTrue);
      expect(btn(tester, _l10n.acctContinueWithApple).loading, isFalse);
      expect(btn(tester, _l10n.acctContinueWithApple).onPressed, isNull); // disabled
      gate.complete(
        const ConnectExistingAttempt(
          outcome: ConnectExistingResult.notAvailable,
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('Continue with Apple spins ALONE', (tester) async {
      final gate = Completer<LinkNewIdentityResult>();
      await _pump(
        tester,
        AccountSection(isAnonymous: () => true, onLink: () => gate.future),
      );
      await tester.tap(find.text(_l10n.acctContinueWithApple));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(btn(tester, _l10n.acctContinueWithApple).loading, isTrue);
      gate.complete(LinkNewIdentityResult.cancelled);
      await tester.pumpAndSettle();
    });

    testWidgets('Retry spins ALONE — Sign out does NOT', (tester) async {
      final gate = Completer<ConnectExistingAttempt>();
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
              retryTicket: 'T-1',
              retryUidBefore: 'anon',
            );
          },
          onRetry: (t) => gate.future,
        ),
      );
      await tester.tap(find.text(_l10n.acctContinueWithApple));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.acctSignInExisting));
      await tester.pumpAndSettle(); // connected + retryable → Retry + Sign out
      await tester.tap(find.text(_l10n.acctRetrySetup));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(btn(tester, _l10n.acctRetrySetup).loading, isTrue);
      expect(btn(tester, _l10n.acctSignOut).loading, isFalse);
      gate.complete(
        const ConnectExistingAttempt(
          outcome: ConnectExistingResult.terminal,
          authConnected: true,
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('Sign out spins ALONE + no double-tap', (tester) async {
      final gate = Completer<SignOutResult>();
      var calls = 0;
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => false, // connected
          onSignOut: () {
            calls++;
            return gate.future;
          },
        ),
      );
      await tester.tap(find.text(_l10n.acctSignOut));
      await tester.pumpAndSettle(); // confirmation dialog
      await tester.tap(
        find.widgetWithText(TextButton, _l10n.acctSignOutConfirm),
      );
      await tester.pump(); // action in flight
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(btn(tester, _l10n.acctSignOut).loading, isTrue);
      expect(calls, 1);
      await tester.tap(
        find.byType(AppButton).first,
        warnIfMissed: false,
      ); // disabled → ignored
      await tester.pump();
      expect(calls, 1); // no double invocation
      gate.complete(SignOutResult.failed);
      await tester.pumpAndSettle();
    });
  });

  group('AccountSection — sign out', () {
    testWidgets('nominal: confirm → GUEST (Connected + Sign out gone, Continue back)', (
      tester,
    ) async {
      var anon = false;
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => anon,
          onSignOut: () async {
            anon = true; // becomes guest
            return SignOutResult.success;
          },
        ),
      );
      expect(find.text(_l10n.acctConnectedWithApple), findsOneWidget);
      await tester.tap(find.text(_l10n.acctSignOut));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.acctSignOutConfirmTitle), findsOneWidget);
      await tester.tap(
        find.widgetWithText(TextButton, _l10n.acctSignOutConfirm),
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n.acctConnectedWithApple), findsNothing);
      expect(find.text(_l10n.acctSignOut), findsNothing);
      expect(find.text(_l10n.acctContinueWithApple), findsOneWidget); // guest
      expect(find.text(_l10n.acctSignedOut), findsWidgets); // snackbar
    });

    testWidgets('cancel → nothing happens (stays connected, onSignOut NOT called)', (
      tester,
    ) async {
      var calls = 0;
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => false,
          onSignOut: () async {
            calls++;
            return SignOutResult.success;
          },
        ),
      );
      await tester.tap(find.text(_l10n.acctSignOut));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, _l10n.acctSignOutCancel));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text(_l10n.acctConnectedWithApple), findsOneWidget);
    });

    testWidgets('failure → error snackbar', (tester) async {
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => false,
          onSignOut: () async => SignOutResult.failed,
        ),
      );
      await tester.tap(find.text(_l10n.acctSignOut));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, _l10n.acctSignOutConfirm),
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n.acctSignOutFailed), findsWidgets);
    });

    testWidgets('no old UUID/JWT leaks after sign-out', (tester) async {
      var anon = false;
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => anon,
          onSignOut: () async {
            anon = true;
            return SignOutResult.success;
          },
        ),
      );
      await tester.tap(find.text(_l10n.acctSignOut));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, _l10n.acctSignOutConfirm),
      );
      await tester.pumpAndSettle();
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(texts.contains('11111111-2222'), isFalse);
      expect(texts.contains('eyJ'), isFalse);
      expect(texts.toLowerCase().contains('bearer'), isFalse);
    });
  });
}
