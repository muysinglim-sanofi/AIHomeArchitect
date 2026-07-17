// ON-mode — orchestration CREATE / SIGN_IN_EXISTING / SIGN_OUT (logique via seams, sans SDK).
// L'intégration réelle (signInWithIdToken, recoverSession, RC) est validée sur device — cf.
// rapport final « validations device résiduelles ». Ici on prouve l'ORCHESTRATION + la
// correction : sign-out restore échoué AVEC blob parqué → restorePending, JAMAIS un nouvel anon.
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/services/auth_service.dart'
    show SignInResult, SignInOutcome;
import 'package:ai_home_architect/data/services/identity_service.dart'
    show ClaimGuestOutcome;
import 'package:ai_home_architect/features/profile/account_link.dart';

void main() {
  group('runCreateAccountOn (défensif : park → signOut local → fresh signin → claim)', () {
    test('nominal → success + claimApplied ; ordre ticket→park→signOut→signIn→claim→rebind→refresh',
        () async {
      final log = <String>[];
      var uid = 'guest';
      final r = await runCreateAccountOn(
        getClaimTicket: () async {
          log.add('ticket');
          return 'TICKET';
        },
        parkGuest: () async {
          log.add('park');
          return 'guest';
        },
        signOutLocal: () async => log.add('signOut'),
        signIn: () async {
          log.add('signIn');
          uid = 'account';
          return const SignInResult(outcome: SignInOutcome.success);
        },
        restoreGuest: () async {
          log.add('restore');
          return 'guest';
        },
        claim: (t) async {
          log.add('claim:$t');
          return ClaimGuestOutcome.claimed;
        },
        currentUid: () => uid,
        rebindRevenueCat: (u) async => log.add('rebind:$u'),
        refreshStatus: () async => log.add('refresh'),
      );
      expect(r.outcome, CreateAccountResult.success);
      expect(r.claimApplied, isTrue);
      expect(log,
          ['ticket', 'park', 'signOut', 'signIn', 'claim:TICKET', 'rebind:account', 'refresh']);
      expect(log.contains('restore'), isFalse); // pas de rollback sur succès
    });

    test('signIn annulé APRÈS signOut → RESTORE le Guest + cancelled + aucun claim', () async {
      final log = <String>[];
      final r = await runCreateAccountOn(
        getClaimTicket: () async => 'T',
        parkGuest: () async => 'guest',
        signOutLocal: () async => log.add('signOut'),
        signIn: () async => const SignInResult(outcome: SignInOutcome.cancelled),
        restoreGuest: () async {
          log.add('restore');
          return 'guest';
        },
        claim: (t) async {
          log.add('claim');
          return ClaimGuestOutcome.claimed;
        },
        currentUid: () => 'guest',
        rebindRevenueCat: (u) async {},
        refreshStatus: () async {},
      );
      expect(r.outcome, CreateAccountResult.cancelled);
      expect(log.contains('restore'), isTrue); // Guest restauré (jamais stranded)
      expect(log.contains('claim'), isFalse);
    });

    test('pas de ticket → failed (aucune bascule d\'identité)', () async {
      var parked = false;
      final r = await runCreateAccountOn(
        getClaimTicket: () async => null,
        parkGuest: () async {
          parked = true;
          return 'guest';
        },
        signOutLocal: () async {},
        signIn: () async => const SignInResult(outcome: SignInOutcome.success),
        restoreGuest: () async => 'guest',
        claim: (t) async => ClaimGuestOutcome.claimed,
        currentUid: () => 'x',
        rebindRevenueCat: (u) async {},
        refreshStatus: () async {},
      );
      expect(r.outcome, CreateAccountResult.failed);
      expect(parked, isFalse); // on n'a même pas parké
    });
  });

  group('runSignInExistingOn (aucun claim, aucun bonus)', () {
    test('nominal → success, re-bind sur le compte', () async {
      final log = <String>[];
      var uid = 'guest';
      final r = await runSignInExistingOn(
        parkGuest: () async => 'guest',
        signOutLocal: () async => log.add('signOut'),
        signIn: () async {
          uid = 'existing-account';
          return const SignInResult(outcome: SignInOutcome.success);
        },
        restoreGuest: () async => 'guest',
        currentUid: () => uid,
        rebindRevenueCat: (u) async => log.add('rebind:$u'),
        refreshStatus: () async => log.add('refresh'),
      );
      expect(r, SignInExistingResult.success);
      expect(log, ['signOut', 'rebind:existing-account', 'refresh']);
    });

    test('signIn échoue → RESTORE Guest + failed', () async {
      var restored = false;
      final r = await runSignInExistingOn(
        parkGuest: () async => 'guest',
        signOutLocal: () async {},
        signIn: () async => const SignInResult(outcome: SignInOutcome.failed),
        restoreGuest: () async {
          restored = true;
          return 'guest';
        },
        currentUid: () => 'guest',
        rebindRevenueCat: (u) async {},
        refreshStatus: () async {},
      );
      expect(r, SignInExistingResult.failed);
      expect(restored, isTrue);
    });
  });

  group('runSignOutOn (restore Guest exact ; CORRECTION anti-anon)', () {
    test('restore OK → restored + rebind(guestUid)', () async {
      final log = <String>[];
      final r = await runSignOutOn(
        signOutLocal: () async => log.add('signOut'),
        hasParked: () async => true,
        restoreGuest: () async {
          log.add('restore');
          return 'guest-1';
        },
        signInAnonymously: () async => log.add('anon'),
        currentUid: () => 'guest-1',
        rebindRevenueCat: (u) async => log.add('rebind:$u'),
        refreshStatus: () async => log.add('refresh'),
      );
      expect(r, SignOutRestoreResult.restored);
      expect(log, ['signOut', 'restore', 'rebind:guest-1', 'refresh']);
      expect(log.contains('anon'), isFalse);
    });

    test('★ restore ÉCHOUE + blob parqué existe → restorePending, JAMAIS d\'anon', () async {
      var anon = false;
      final r = await runSignOutOn(
        signOutLocal: () async {},
        hasParked: () async => true, // le blob est toujours là
        restoreGuest: () async => null, // échec (réseau / refresh token indispo)
        signInAnonymously: () async => anon = true,
        currentUid: () => null,
        rebindRevenueCat: (u) async {},
        refreshStatus: () async {},
      );
      expect(r, SignOutRestoreResult.restorePending);
      expect(anon, isFalse); // ← LA correction : aucun nouvel anonyme
    });

    test('restore échoue + AUCUN blob (storage vide prouvé) → newGuest (anon)', () async {
      var anon = false;
      final r = await runSignOutOn(
        signOutLocal: () async {},
        hasParked: () async => false, // plus aucun blob parqué
        restoreGuest: () async => null,
        signInAnonymously: () async => anon = true,
        currentUid: () => 'fresh-anon',
        rebindRevenueCat: (u) async {},
        refreshStatus: () async {},
      );
      expect(r, SignOutRestoreResult.newGuest);
      expect(anon, isTrue); // nouvel anon UNIQUEMENT si aucun blob
    });
  });
}
