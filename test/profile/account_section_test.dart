// AccountSection widget tests — ON-mode (Guest durable : park/restore). No
// network/SDK: the widget's injectable seams (isAnonymous / onCreate /
// onSignInExisting / onSignOut) drive the flows + results without Supabase/
// Apple/RevenueCat. Proves anonymous↔connected rendering, create/sign-in
// snackbars, sign-out → signed-out, the ★ anti-anon correction (restorePending
// → Retry banner, NEVER a new anon), per-button spinner isolation, and that NO
// technical data (UUID/JWT/status/ticket) is ever shown.
//
// The widget watches guestRestorePendingProvider (SharedPreferences-backed) at
// build → each test seeds empty mock prefs in setUp.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/core/providers/guest_restore_pending_provider.dart';
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
  setUp(() {
    // guestRestorePendingProvider._init reads SharedPreferences at build.
    SharedPreferences.setMockInitialValues({});
  });

  group('AccountSection — rendering (ON)', () {
    testWidgets('anonymous → section + subtitle + Create + Sign in existing', (
      tester,
    ) async {
      await _pump(tester, AccountSection(isAnonymous: () => true));
      expect(find.text(_l10n.acctSectionTitle), findsOneWidget);
      expect(find.text(_l10n.acctSaveDesignsSubtitle), findsOneWidget);
      expect(find.text(_l10n.acctContinueWithApple), findsOneWidget); // Create
      expect(find.text(_l10n.acctSignInExisting), findsOneWidget); // Sign in
      expect(find.text(_l10n.acctConnectedWithApple), findsNothing);
    });

    testWidgets('signed-in → Connected + Sign out, no Create CTA', (
      tester,
    ) async {
      await _pump(tester, AccountSection(isAnonymous: () => false));
      expect(find.text(_l10n.acctConnectedWithApple), findsOneWidget);
      expect(find.text(_l10n.acctSignOut), findsOneWidget);
      expect(find.text(_l10n.acctContinueWithApple), findsNothing);
      expect(find.text(_l10n.acctSignInExisting), findsNothing);
    });
  });

  group('AccountSection — create new account', () {
    testWidgets('success → success snackbar', (tester) async {
      var anon = true;
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => anon,
          onCreate: () async {
            anon = false;
            return const CreateAccountAttempt(
              outcome: CreateAccountResult.success,
              claimApplied: true,
            );
          },
        ),
      );
      await tester.tap(find.text(_l10n.acctContinueWithApple));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.acctConnectedSuccess), findsWidgets);
      // Flipped to connected in place.
      expect(find.text(_l10n.acctConnectedWithApple), findsOneWidget);
    });

    testWidgets('cancelled → silent (stays guest, no snackbar)', (tester) async {
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => true,
          onCreate: () async =>
              const CreateAccountAttempt(outcome: CreateAccountResult.cancelled),
        ),
      );
      await tester.tap(find.text(_l10n.acctContinueWithApple));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.acctConnectedSuccess), findsNothing);
      expect(find.text(_l10n.acctContinueWithApple), findsOneWidget); // guest
    });

    testWidgets('failed → generic error snackbar', (tester) async {
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => true,
          onCreate: () async =>
              const CreateAccountAttempt(outcome: CreateAccountResult.failed),
        ),
      );
      await tester.tap(find.text(_l10n.acctContinueWithApple));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.acctGenericError), findsWidgets);
    });
  });

  group('AccountSection — sign in to existing account', () {
    testWidgets('success → success snackbar + Connected', (tester) async {
      var anon = true;
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => anon,
          onSignInExisting: () async {
            anon = false;
            return SignInExistingResult.success;
          },
        ),
      );
      await tester.tap(find.text(_l10n.acctSignInExisting));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.acctConnectedSuccess), findsWidgets);
      expect(find.text(_l10n.acctConnectedWithApple), findsOneWidget);
    });

    testWidgets('failed → generic error (stays guest)', (tester) async {
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => true,
          onSignInExisting: () async => SignInExistingResult.failed,
        ),
      );
      await tester.tap(find.text(_l10n.acctSignInExisting));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.acctGenericError), findsWidgets);
      expect(find.text(_l10n.acctSignInExisting), findsOneWidget); // still guest
    });
  });

  group('AccountSection — sign out (restore parked Guest)', () {
    testWidgets('restored → Connected gone, Create back, signed-out snackbar', (
      tester,
    ) async {
      var anon = false;
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => anon,
          onSignOut: () async {
            anon = true; // guest restored
            return SignOutRestoreResult.restored;
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
      expect(find.text(_l10n.acctContinueWithApple), findsOneWidget); // guest
      expect(find.text(_l10n.acctSignedOut), findsWidgets);
    });

    testWidgets('newGuest (no parked blob) → signed-out snackbar', (
      tester,
    ) async {
      var anon = false;
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => anon,
          onSignOut: () async {
            anon = true;
            return SignOutRestoreResult.newGuest;
          },
        ),
      );
      await tester.tap(find.text(_l10n.acctSignOut));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, _l10n.acctSignOutConfirm),
      );
      await tester.pumpAndSettle();
      expect(find.text(_l10n.acctSignedOut), findsWidgets);
    });

    testWidgets(
      '★ restorePending → Retry banner shown, NEVER a new anon (gate raised)',
      (tester) async {
        await _pump(
          tester,
          AccountSection(
            isAnonymous: () => false,
            // Parked blob exists but recoverSession failed → restorePending.
            onSignOut: () async => SignOutRestoreResult.restorePending,
          ),
        );
        await tester.tap(find.text(_l10n.acctSignOut));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(TextButton, _l10n.acctSignOutConfirm),
        );
        await tester.pumpAndSettle();

        // The banner (kGuestRestorePendingMessage) + a Retry button replace the
        // account body — the correct Guest is NOT yet restored.
        expect(find.text(kGuestRestorePendingMessage), findsOneWidget);
        expect(find.text(_l10n.acctRetrySetup), findsOneWidget);
        // The gate flag is up → generation is blocked elsewhere.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AccountSection)),
        );
        expect(container.read(guestRestorePendingProvider), isTrue);
      },
    );

    testWidgets('cancel → nothing happens (onSignOut NOT called)', (
      tester,
    ) async {
      var calls = 0;
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => false,
          onSignOut: () async {
            calls++;
            return SignOutRestoreResult.restored;
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

    testWidgets('failed → error snackbar', (tester) async {
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => false,
          onSignOut: () async => SignOutRestoreResult.failed,
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
  });

  group('AccountSection — spinner isolation (per-button)', () {
    AppButton btn(WidgetTester tester, String label) => tester
        .widgetList<AppButton>(find.byType(AppButton))
        .firstWhere((b) => b.label == label);

    testWidgets('Create spins ALONE — Sign in existing is disabled, no spinner', (
      tester,
    ) async {
      final gate = Completer<CreateAccountAttempt>();
      await _pump(
        tester,
        AccountSection(isAnonymous: () => true, onCreate: () => gate.future),
      );
      await tester.tap(find.text(_l10n.acctContinueWithApple));
      await tester.pump(); // one frame — action in flight
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(btn(tester, _l10n.acctContinueWithApple).loading, isTrue);
      expect(btn(tester, _l10n.acctSignInExisting).loading, isFalse);
      expect(btn(tester, _l10n.acctSignInExisting).onPressed, isNull); // disabled
      gate.complete(
        const CreateAccountAttempt(outcome: CreateAccountResult.cancelled),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('Sign out spins ALONE + no double-tap', (tester) async {
      final gate = Completer<SignOutRestoreResult>();
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
      gate.complete(SignOutRestoreResult.failed);
      await tester.pumpAndSettle();
    });
  });

  group('AccountSection — no technical data leaks', () {
    testWidgets('restorePending banner renders no UUID/JWT', (tester) async {
      await _pump(
        tester,
        AccountSection(
          isAnonymous: () => false,
          onSignOut: () async => SignOutRestoreResult.restorePending,
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
      expect(RegExp(r'\b(4\d\d|5\d\d)\b').hasMatch(texts), isFalse);
    });
  });
}
