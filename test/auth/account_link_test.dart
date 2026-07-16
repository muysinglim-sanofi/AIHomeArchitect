// Account-linking orchestration tests — pure, injected closures, no SDK/network
// (repo convention: no mockito). Proves: RC re-bind only on a real UUID change;
// merge-ticket created BEFORE sign-in with a safe abort on a dormant backend;
// order merge→signin→claim→rebind→refresh; NO verdict keyed on a status/code;
// and the structured retry semantics (ticket kept ONLY for a replayable claim,
// retry re-does the claim ONLY — no new ticket, no re-signin).
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/core/feature_flags.dart';
import 'package:ai_home_architect/data/services/auth_service.dart'
    show SignInResult, SignInOutcome;
import 'package:ai_home_architect/data/services/identity_service.dart'
    show MergeTicketResult, ClaimResult, IdentityOutcome;
import 'package:ai_home_architect/features/profile/account_link.dart';

MergeTicketResult _ticket(String t) =>
    MergeTicketResult(outcome: IdentityOutcome.success, ticket: t);
ClaimResult _claim(IdentityOutcome o, {String? status}) =>
    ClaimResult(outcome: o, status: status);
SignInResult _signInOk([String? uid]) =>
    SignInResult(outcome: SignInOutcome.success, userId: uid);

void main() {
  group('shouldRebindRevenueCat', () {
    test('same uid → false (link preserves UUID)', () {
      expect(shouldRebindRevenueCat(uidBefore: 'u', uidAfter: 'u'), isFalse);
    });
    test('different uid → true', () {
      expect(shouldRebindRevenueCat(uidBefore: 'a', uidAfter: 'b'), isTrue);
    });
    test('null / empty after → false', () {
      expect(shouldRebindRevenueCat(uidBefore: 'a', uidAfter: null), isFalse);
      expect(shouldRebindRevenueCat(uidBefore: 'a', uidAfter: ''), isFalse);
    });
  });

  group('runLinkNewIdentity (new identity, UUID preserved)', () {
    test('success → refreshes status, returns success', () async {
      var refreshed = 0;
      final r = await runLinkNewIdentity(
        linkApple: () async => _signInOk('u1'),
        refreshStatus: () async => refreshed++,
      );
      expect(r, LinkNewIdentityResult.success);
      expect(refreshed, 1);
    });
    test('cancelled → no refresh', () async {
      var refreshed = 0;
      final r = await runLinkNewIdentity(
        linkApple: () async =>
            const SignInResult(outcome: SignInOutcome.cancelled),
        refreshStatus: () async => refreshed++,
      );
      expect(r, LinkNewIdentityResult.cancelled);
      expect(refreshed, 0);
    });
    test('failed → no refresh (caller offers existing-account)', () async {
      var refreshed = 0;
      final r = await runLinkNewIdentity(
        linkApple: () async =>
            const SignInResult(outcome: SignInOutcome.failed),
        refreshStatus: () async => refreshed++,
      );
      expect(r, LinkNewIdentityResult.failed);
      expect(refreshed, 0);
    });
  });

  group('runConnectExistingAccount', () {
    Future<ConnectExistingAttempt> run({
      required String? Function() currentUid,
      required Future<MergeTicketResult> Function() merge,
      required Future<SignInResult> Function() signIn,
      required Future<ClaimResult> Function(String) claim,
      required Future<void> Function(String) rebind,
      required Future<void> Function() refresh,
    }) => runConnectExistingAccount(
      currentUid: currentUid,
      createMergeTicket: merge,
      signInWithApple: signIn,
      claim: claim,
      rebindRevenueCat: rebind,
      refreshStatus: refresh,
    );

    test('dormant backend (featureDisabled) → aborts BEFORE sign-in', () async {
      final log = <String>[];
      final a = await run(
        currentUid: () => 'anon',
        merge: () async {
          log.add('merge');
          return const MergeTicketResult(
            outcome: IdentityOutcome.featureDisabled,
          );
        },
        signIn: () async {
          log.add('signin');
          return _signInOk();
        },
        claim: (t) async => _claim(IdentityOutcome.success),
        rebind: (u) async => log.add('rebind'),
        refresh: () async => log.add('refresh'),
      );
      expect(a.outcome, ConnectExistingResult.notAvailable);
      expect(a.authConnected, isFalse);
      expect(a.retryTicket, isNull);
      expect(log, ['merge']); // anon session untouched
    });

    test('merge retryable → retryable, no sign-in, no retry ticket', () async {
      final log = <String>[];
      final a = await run(
        currentUid: () => 'anon',
        merge: () async {
          log.add('merge');
          return const MergeTicketResult(
            outcome: IdentityOutcome.retryableFailure,
          );
        },
        signIn: () async {
          log.add('signin');
          return _signInOk();
        },
        claim: (t) async => _claim(IdentityOutcome.success),
        rebind: (u) async {},
        refresh: () async {},
      );
      expect(a.outcome, ConnectExistingResult.retryable);
      expect(a.retryTicket, isNull); // still anonymous, no replayable claim
      expect(log, ['merge']);
    });

    test(
      'happy path → order merge→signin→claim→rebind→refresh, ticket passed',
      () async {
        final log = <String>[];
        var uid = 'anon-1';
        final a = await run(
          currentUid: () => uid,
          merge: () async {
            log.add('merge');
            return _ticket('T-abc');
          },
          signIn: () async {
            log.add('signin');
            uid = 'perm-2';
            return _signInOk('perm-2');
          },
          claim: (t) async {
            log.add('claim:$t');
            return _claim(IdentityOutcome.success, status: 'completed');
          },
          rebind: (u) async => log.add('rebind:$u'),
          refresh: () async => log.add('refresh'),
        );
        expect(a.outcome, ConnectExistingResult.success);
        expect(a.claimCompleted, isTrue);
        expect(a.retryTicket, isNull); // completed → nothing to retry
        expect(log, [
          'merge',
          'signin',
          'claim:T-abc',
          'rebind:perm-2',
          'refresh',
        ]);
      },
    );

    test('sign-in cancelled → cancelled, no claim/rebind', () async {
      final log = <String>[];
      final a = await run(
        currentUid: () => 'anon',
        merge: () async => _ticket('T-1'),
        signIn: () async {
          log.add('signin');
          return const SignInResult(outcome: SignInOutcome.cancelled);
        },
        claim: (t) async {
          log.add('claim');
          return _claim(IdentityOutcome.success);
        },
        rebind: (u) async => log.add('rebind'),
        refresh: () async => log.add('refresh'),
      );
      expect(a.outcome, ConnectExistingResult.cancelled);
      expect(a.retryTicket, isNull);
      expect(log, ['signin']);
    });

    test('no rebind when the UUID did not change after sign-in', () async {
      final log = <String>[];
      final a = await run(
        currentUid: () => 'same',
        merge: () async => _ticket('T-1'),
        signIn: () async => _signInOk('same'),
        claim: (t) async {
          log.add('claim');
          return _claim(IdentityOutcome.success, status: 'completed');
        },
        rebind: (u) async => log.add('rebind'),
        refresh: () async => log.add('refresh'),
      );
      expect(a.outcome, ConnectExistingResult.success);
      expect(log, ['claim', 'refresh']); // no needless re-bind
    });

    test(
      'claim pending (identity_merge_pending) → pending, no retry ticket',
      () async {
        var uid = 'anon';
        final a = await run(
          currentUid: () => uid,
          merge: () async => _ticket('T-1'),
          signIn: () async {
            uid = 'perm';
            return _signInOk('perm');
          },
          claim: (t) async =>
              _claim(IdentityOutcome.success, status: 'identity_merge_pending'),
          rebind: (u) async {},
          refresh: () async {},
        );
        expect(a.outcome, ConnectExistingResult.pending);
        expect(a.claimPending, isTrue);
        expect(a.claimCompleted, isFalse);
        expect(a.retryTicket, isNull); // finalizes on its own
      },
    );

    test('claim billing_pending → pending', () async {
      var uid = 'anon';
      final a = await run(
        currentUid: () => uid,
        merge: () async => _ticket('T-1'),
        signIn: () async {
          uid = 'perm';
          return _signInOk('perm');
        },
        claim: (t) async =>
            _claim(IdentityOutcome.success, status: 'billing_pending'),
        rebind: (u) async {},
        refresh: () async {},
      );
      expect(a.outcome, ConnectExistingResult.pending);
      expect(a.claimPending, isTrue);
    });

    test(
      'claim retryable → connected + retry ticket kept (order claim→rebind→refresh)',
      () async {
        final log = <String>[];
        var uid = 'anon';
        final a = await run(
          currentUid: () => uid,
          merge: () async => _ticket('T-keep'),
          signIn: () async {
            uid = 'perm';
            return _signInOk('perm');
          },
          claim: (t) async {
            log.add('claim');
            return _claim(IdentityOutcome.retryableFailure);
          },
          rebind: (u) async => log.add('rebind'),
          refresh: () async => log.add('refresh'),
        );
        expect(a.outcome, ConnectExistingResult.retryable);
        expect(a.authConnected, isTrue); // signed in to the existing account
        expect(a.retryTicket, 'T-keep'); // replayable — ticket kept in memory
        expect(a.retryUidBefore, 'anon');
        expect(log, ['claim', 'rebind', 'refresh']);
      },
    );

    test('claim terminal → connected, NO retry ticket', () async {
      var uid = 'anon';
      final a = await run(
        currentUid: () => uid,
        merge: () async => _ticket('T-1'),
        signIn: () async {
          uid = 'perm';
          return _signInOk('perm');
        },
        claim: (t) async => _claim(IdentityOutcome.terminalFailure),
        rebind: (u) async {},
        refresh: () async {},
      );
      expect(a.outcome, ConnectExistingResult.terminal);
      expect(a.authConnected, isTrue);
      expect(a.retryTicket, isNull); // not replayable
    });

    test('attempt.toString never exposes the ticket value', () {
      const a = ConnectExistingAttempt(
        outcome: ConnectExistingResult.retryable,
        authConnected: true,
        retryTicket: 'SECRET-TICKET-123',
        retryUidBefore: 'anon',
      );
      expect(a.toString().contains('SECRET-TICKET-123'), isFalse);
      expect(a.canRetry, isTrue);
    });
  });

  group('retryExistingAccountClaim (claim-only retry)', () {
    Future<ConnectExistingAttempt> retry({
      required String ticket,
      String? uidBefore,
      required String? Function() currentUid,
      required Future<ClaimResult> Function(String) claim,
      required Future<void> Function(String) rebind,
      required Future<void> Function() refresh,
    }) => retryExistingAccountClaim(
      ticket: ticket,
      uidBefore: uidBefore,
      currentUid: currentUid,
      claim: claim,
      rebindRevenueCat: rebind,
      refreshStatus: refresh,
    );

    test(
      'retry success → completed, ticket cleared, order claim→refresh',
      () async {
        final log = <String>[];
        final a = await retry(
          ticket: 'T-1',
          uidBefore: 'perm', // already signed in — no UUID change → no rebind
          currentUid: () => 'perm',
          claim: (t) async {
            log.add('claim:$t');
            return _claim(IdentityOutcome.success, status: 'completed');
          },
          rebind: (u) async => log.add('rebind'),
          refresh: () async => log.add('refresh'),
        );
        expect(a.outcome, ConnectExistingResult.success);
        expect(a.retryTicket, isNull); // cleared
        expect(log, ['claim:T-1', 'refresh']); // no rebind needed
      },
    );

    test('retry still retryable → ticket kept', () async {
      final a = await retry(
        ticket: 'T-2',
        uidBefore: 'perm',
        currentUid: () => 'perm',
        claim: (t) async => _claim(IdentityOutcome.retryableFailure),
        rebind: (u) async {},
        refresh: () async {},
      );
      expect(a.outcome, ConnectExistingResult.retryable);
      expect(a.retryTicket, 'T-2');
    });

    test('retry terminal → ticket cleared, no further retry', () async {
      final a = await retry(
        ticket: 'T-3',
        uidBefore: 'perm',
        currentUid: () => 'perm',
        claim: (t) async => _claim(IdentityOutcome.terminalFailure),
        rebind: (u) async {},
        refresh: () async {},
      );
      expect(a.outcome, ConnectExistingResult.terminal);
      expect(a.retryTicket, isNull);
      expect(a.canRetry, isFalse);
    });
  });

  group('flags', () {
    test(
      'freeTrialAuthGate stays false (Account section does not flip it)',
      () {
        expect(FeatureFlags.freeTrialAuthGate, isFalse);
        expect(FeatureFlags.signInEnabled, isFalse);
      },
    );
  });

  group('runSignOut', () {
    Future<SignOutResult> run({
      required Future<void> Function() signOut,
      required Future<void> Function() signInAnonymously,
      required String? Function() currentUid,
      required Future<void> Function(String) rebind,
      required Future<void> Function() refresh,
      Future<bool> Function()? markTrialConsumed,
      Future<void> Function(bool)? setMarkerPending,
    }) => runSignOut(
      signOut: signOut,
      signInAnonymously: signInAnonymously,
      markTrialConsumed: markTrialConsumed ?? () async => true,
      setMarkerPending: setMarkerPending ?? (_) async {},
      currentUid: currentUid,
      rebindRevenueCat: rebind,
      refreshStatus: refresh,
    );

    test('nominal → success; order signOut→anon→rebind(new uid)→refresh', () async {
      final log = <String>[];
      var uid = 'apple-user';
      final r = await run(
        signOut: () async => log.add('signOut'),
        signInAnonymously: () async {
          uid = 'anon-new';
          log.add('anon');
        },
        currentUid: () => uid,
        rebind: (u) async => log.add('rebind:$u'),
        refresh: () async => log.add('refresh'),
      );
      expect(r, SignOutResult.success);
      expect(log, ['signOut', 'anon', 'rebind:anon-new', 'refresh']);
    });

    test('post-signout order: signOut→anon→pending:true→marker→pending:false→rebind→refresh', () async {
      final log = <String>[];
      var uid = 'apple-user';
      final r = await run(
        signOut: () async => log.add('signOut'),
        signInAnonymously: () async {
          uid = 'anon-new';
          log.add('anon');
        },
        setMarkerPending: (v) async => log.add('pending:$v'),
        markTrialConsumed: () async {
          log.add('marker');
          return true;
        },
        currentUid: () => uid,
        rebind: (u) async => log.add('rebind'),
        refresh: () async => log.add('refresh'),
      );
      expect(r, SignOutResult.success);
      // Flag raised BEFORE the marker, lowered ONLY after a confirmed success.
      expect(log,
          ['signOut', 'anon', 'pending:true', 'marker', 'pending:false', 'rebind', 'refresh']);
    });

    test('marker SUCCESS → pending raised then cleared (gate opens)', () async {
      final pend = <bool>[];
      final r = await run(
        signOut: () async {},
        signInAnonymously: () async {},
        setMarkerPending: (v) async => pend.add(v),
        markTrialConsumed: () async => true,
        currentUid: () => 'anon-new',
        rebind: (u) async {},
        refresh: () async {},
      );
      expect(r, SignOutResult.success);
      expect(pend, [true, false]); // ON before write, OFF on confirmed success
    });

    test('marker FAILS (false×2) → pending RAISED and NEVER cleared (gate stays closed)', () async {
      final pend = <bool>[];
      final r = await run(
        signOut: () async {},
        signInAnonymously: () async {},
        setMarkerPending: (v) async => pend.add(v),
        markTrialConsumed: () async => false,
        currentUid: () => 'anon-new',
        rebind: (u) async {},
        refresh: () async {},
      );
      expect(r, SignOutResult.success); // Sign out stays simple
      expect(pend, [true]); // raised, never lowered → Generate stays gated + boot-retry
    });

    test('marker THROWS → pending RAISED before the throw and never cleared', () async {
      final pend = <bool>[];
      final r = await run(
        signOut: () async {},
        signInAnonymously: () async {},
        setMarkerPending: (v) async => pend.add(v),
        markTrialConsumed: () async => throw Exception('network'),
        currentUid: () => 'anon-new',
        rebind: (u) async {},
        refresh: () async {},
      );
      expect(r, SignOutResult.success);
      expect(pend, [true]); // flag up (set before the write); the throw is swallowed
    });

    test('trial marker fails (false) twice → still SUCCESS (non-blocking), retried once', () async {
      var calls = 0;
      final r = await run(
        signOut: () async {},
        signInAnonymously: () async {},
        markTrialConsumed: () async {
          calls++;
          return false;
        },
        currentUid: () => 'anon-new',
        rebind: (u) async {},
        refresh: () async {},
      );
      expect(r, SignOutResult.success); // Sign out stays simple; marker is best-effort
      expect(calls, 2); // one retry attempted
    });

    test('trial marker succeeds on retry (false then true) → success', () async {
      var calls = 0;
      final r = await run(
        signOut: () async {},
        signInAnonymously: () async {},
        markTrialConsumed: () async {
          calls++;
          return calls >= 2;
        },
        currentUid: () => 'anon-new',
        rebind: (u) async {},
        refresh: () async {},
      );
      expect(r, SignOutResult.success);
      expect(calls, 2);
    });

    test('trial marker throws → caught → still SUCCESS (non-blocking)', () async {
      var calls = 0;
      final r = await run(
        signOut: () async {},
        signInAnonymously: () async {},
        markTrialConsumed: () async {
          calls++;
          throw Exception('network');
        },
        currentUid: () => 'anon-new',
        rebind: (u) async {},
        refresh: () async {},
      );
      expect(r, SignOutResult.success); // a network blip never blocks Sign out
      expect(calls, 1); // throw short-circuits the retry
    });

    test('Case A — anon sign-in fails → failed + best-effort re-anon; no rebind/refresh', () async {
      final log = <String>[];
      var attempts = 0;
      final r = await run(
        signOut: () async => log.add('signOut'),
        signInAnonymously: () async {
          attempts++;
          log.add('anon:$attempts');
          throw Exception('anon down');
        },
        currentUid: () => 'stale',
        rebind: (u) async => log.add('rebind'),
        refresh: () async => log.add('refresh'),
      );
      expect(r, SignOutResult.failed);
      expect(attempts, 2); // best-effort re-anon attempted
      expect(log.contains('rebind'), isFalse); // never reached (no clean session)
      expect(log.contains('refresh'), isFalse);
    });

    test('Case B — rebind fails → failed BUT session is new anon and refresh STILL runs', () async {
      final log = <String>[];
      var uid = 'apple-user';
      final r = await run(
        signOut: () async => log.add('signOut'),
        signInAnonymously: () async {
          uid = 'anon-new';
          log.add('anon');
        },
        currentUid: () => uid,
        rebind: (u) async {
          log.add('rebind-throw');
          throw Exception('RC down');
        },
        refresh: () async => log.add('refresh'),
      );
      expect(r, SignOutResult.failed);
      expect(uid, 'anon-new'); // on the NEW anon, never the old identity
      expect(log, ['signOut', 'anon', 'rebind-throw', 'refresh']); // refresh NOT skipped
    });

    test('Case C — refresh fails → failed BUT session new anon, rebind ran', () async {
      final log = <String>[];
      var uid = 'apple-user';
      final r = await run(
        signOut: () async => log.add('signOut'),
        signInAnonymously: () async {
          uid = 'anon-new';
          log.add('anon');
        },
        currentUid: () => uid,
        rebind: (u) async => log.add('rebind'),
        refresh: () async {
          log.add('refresh-throw');
          throw Exception('status down');
        },
      );
      expect(r, SignOutResult.failed);
      expect(uid, 'anon-new');
      expect(log, ['signOut', 'anon', 'rebind', 'refresh-throw']);
    });

    test('anti-abuse — only signOut/anon/rebind/refresh fire; no bonus/grant/wallet/pass hook', () async {
      // The ONLY side-effect closures are these 4 — there is no parameter, hence no
      // code path, for a signup bonus, credit grant, wallet/pass transfer, or ledger/
      // merge mutation. Full success path exercises exactly those effects.
      final effects = <String>[];
      final r = await run(
        signOut: () async => effects.add('signOut'),
        signInAnonymously: () async => effects.add('anon'),
        currentUid: () => 'anon-new',
        rebind: (u) async => effects.add('rebind'),
        refresh: () async => effects.add('refresh'),
      );
      expect(r, SignOutResult.success);
      expect(effects.toSet(), {'signOut', 'anon', 'rebind', 'refresh'});
      expect(FeatureFlags.freeTrialAuthGate, isFalse); // untouched
    });

    test('no rebind when the new uid is null/empty (defensive)', () async {
      final log = <String>[];
      final r = await run(
        signOut: () async => log.add('signOut'),
        signInAnonymously: () async => log.add('anon'),
        currentUid: () => null,
        rebind: (u) async => log.add('rebind'),
        refresh: () async => log.add('refresh'),
      );
      expect(r, SignOutResult.success);
      expect(log, ['signOut', 'anon', 'refresh']); // no rebind on null uid
    });
  });
}
