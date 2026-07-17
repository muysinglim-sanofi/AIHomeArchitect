/// Account orchestration — ON-mode (Guest durable : park/restore + create/sign-in).
///
/// PURE + dependency-injected so it is unit tested WITHOUT the RevenueCat/Apple
/// SDKs or a network (repo convention: inject closures for side effects, no
/// mockito). The Profile "Account" section (account_section.dart) wires the real
/// services into these functions. Rendered ONLY when
/// FeatureFlags.accountSystemEnabled is ON.
///
/// Model — docs/GUEST_ACCOUNT_IDENTITY_SPEC.md. The Guest and the account stay
/// TWO distinct Supabase identities. The Guest local session is PARKED (2nd
/// Keychain slot) whenever an account becomes active, and RESTORED exactly on
/// sign-out — never a fresh anonymous Guest. Three flows only:
///   • runCreateAccountOn      — defensive create (park → local signOut → fresh
///     signInWithIdToken → claim Free+bonus ONCE → RC re-bind → refresh). The
///     account is ALWAYS separate from the Guest whatever U4's outcome, because
///     there is no active anon at sign-in time (GoTrue cannot auto-link).
///   • runSignInExistingOn     — returning user; NO claim, NO bonus, NO transfer.
///   • runSignOutOn            — restore the EXACT parked Guest ; on a transient
///     restore failure WITH a parked blob still present → restorePending (the
///     caller gates Generate + offers Retry), NEVER a new anonymous Guest.
///
/// No function inspects a specific HTTP status / error_code and none logs a
/// token / nonce / ticket.
library;

import '../../data/services/auth_service.dart' show SignInResult, SignInOutcome;
import '../../data/services/identity_service.dart' show ClaimGuestOutcome;

enum CreateAccountResult { success, cancelled, failed }

class CreateAccountAttempt {
  final CreateAccountResult outcome;
  final bool claimApplied; // le backend a appliqué (ou déjà) le transfert Free + bonus
  const CreateAccountAttempt({required this.outcome, this.claimApplied = false});
}

/// CREATE_NEW_ACCOUNT (ON) — Guest et compte restent DEUX identités distinctes ; seul le Free
/// admissible est réclamé + bonus +2 une fois. Rollback (restore Guest) si le sign-in échoue.
Future<CreateAccountAttempt> runCreateAccountOn({
  required Future<String?> Function() getClaimTicket,
  required Future<String?> Function() parkGuest,
  required Future<void> Function() signOutLocal,
  required Future<SignInResult> Function() signIn,
  required Future<String?> Function() restoreGuest,
  required Future<ClaimGuestOutcome> Function(String ticket) claim,
  required String? Function() currentUid,
  required Future<void> Function(String uid) rebindRevenueCat,
  required Future<void> Function() refreshStatus,
}) async {
  final ticket = await getClaimTicket(); // émis à la session GUEST, AVANT toute bascule
  if (ticket == null) return const CreateAccountAttempt(outcome: CreateAccountResult.failed);
  final guestUid = await parkGuest(); // copie durable ; le blob reste pour rollback/restore
  if (guestUid == null) return const CreateAccountAttempt(outcome: CreateAccountResult.failed);
  await signOutLocal(); // plus de session anon active → pas d'auto-link (U4 moot)
  final res = await signIn(); // fresh → compte SÉPARÉ
  if (res.outcome != SignInOutcome.success) {
    await restoreGuest(); // signé out le Guest → le restaurer (jamais stranded)
    return CreateAccountAttempt(
      outcome: res.outcome == SignInOutcome.cancelled
          ? CreateAccountResult.cancelled
          : CreateAccountResult.failed);
  }
  final accountUid = currentUid();
  final claimOut = await claim(ticket); // transfert Free admissible + bonus +2 (atomique, backend)
  if (accountUid != null && accountUid.isNotEmpty) {
    try {
      await rebindRevenueCat(accountUid);
    } catch (_) {/* isolé */}
  }
  try {
    await refreshStatus();
  } catch (_) {/* isolé */}
  return CreateAccountAttempt(
    outcome: CreateAccountResult.success,
    claimApplied: claimOut == ClaimGuestOutcome.claimed ||
        claimOut == ClaimGuestOutcome.alreadySetUp,
  );
}

enum SignInExistingResult { success, cancelled, failed }

/// SIGN_IN_EXISTING_ACCOUNT (ON) — AUCUN claim, AUCUN bonus, AUCUN transfert. Park le Guest,
/// bascule vers le compte existant, re-bind RC, refresh. Guest restauré au sign-out.
Future<SignInExistingResult> runSignInExistingOn({
  required Future<String?> Function() parkGuest,
  required Future<void> Function() signOutLocal,
  required Future<SignInResult> Function() signIn,
  required Future<String?> Function() restoreGuest,
  required String? Function() currentUid,
  required Future<void> Function(String uid) rebindRevenueCat,
  required Future<void> Function() refreshStatus,
}) async {
  final guestUid = await parkGuest();
  if (guestUid == null) return SignInExistingResult.failed;
  await signOutLocal();
  final res = await signIn();
  if (res.outcome != SignInOutcome.success) {
    await restoreGuest();
    return res.outcome == SignInOutcome.cancelled
        ? SignInExistingResult.cancelled
        : SignInExistingResult.failed;
  }
  final accountUid = currentUid();
  if (accountUid != null && accountUid.isNotEmpty) {
    try {
      await rebindRevenueCat(accountUid);
    } catch (_) {/* isolé */}
  }
  try {
    await refreshStatus();
  } catch (_) {/* isolé */}
  return SignInExistingResult.success;
}

enum SignOutRestoreResult { restored, restorePending, newGuest, failed }

/// SIGN_OUT (ON) — restaure EXACTEMENT le Guest parqué. CORRECTION OBLIGATOIRE : si un blob
/// parqué existe MAIS que le restore échoue (réseau / refresh token indispo), NE PAS créer de
/// nouvel anonyme → renvoyer restorePending (l'appelant lève guestRestorePending qui BLOQUE la
/// génération/wallet + propose Retry). Nouvel anon UNIQUEMENT s'il est PROUVÉ qu'aucun blob
/// n'existe (storage réellement vide/supprimé) → aucun trial fantôme, aucune identité fantôme.
Future<SignOutRestoreResult> runSignOutOn({
  required Future<void> Function() signOutLocal,
  required Future<bool> Function() hasParked,
  required Future<String?> Function() restoreGuest,
  required Future<void> Function() signInAnonymously,
  required String? Function() currentUid,
  required Future<void> Function(String uid) rebindRevenueCat,
  required Future<void> Function() refreshStatus,
}) async {
  await signOutLocal();
  final restoredUid = await restoreGuest();
  if (restoredUid != null && restoredUid.isNotEmpty) {
    try {
      await rebindRevenueCat(restoredUid); // RC.logIn(guestId)
    } catch (_) {/* isolé */}
    try {
      await refreshStatus();
    } catch (_) {/* isolé */}
    return SignOutRestoreResult.restored;
  }
  // Restore raté → un blob parqué existe-t-il ENCORE ?
  if (await hasParked()) {
    // OUI → JAMAIS d'anon (panne transitoire). L'appelant lève guestRestorePending.
    return SignOutRestoreResult.restorePending;
  }
  // NON (blob réellement absent) → nouvel anon (comportement fresh install prouvé).
  try {
    await signInAnonymously();
    final uid = currentUid();
    if (uid != null && uid.isNotEmpty) {
      try {
        await rebindRevenueCat(uid);
      } catch (_) {/* isolé */}
    }
    try {
      await refreshStatus();
    } catch (_) {/* isolé */}
    return SignOutRestoreResult.newGuest;
  } catch (_) {
    return SignOutRestoreResult.failed;
  }
}
