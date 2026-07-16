/// Account-linking orchestration — PURE + dependency-injected so it is unit
/// tested WITHOUT the RevenueCat/Apple SDKs or a network (the repo convention:
/// inject closures for side effects, no mockito). The Profile "Account" section
/// wires the real services into these functions.
///
/// Two flows:
///   • runLinkNewIdentity — anonymous user attaches a NEW Apple identity; the
///     Supabase UUID is PRESERVED (linkIdentityWithIdToken), so RevenueCat is
///     NOT re-bound.
///   • runConnectExistingAccount — the Apple identity already belongs to an
///     existing Ayden account; a merge ticket is created BEFORE leaving the anon
///     user, then Apple sign-in (UUID changes) → claim → RevenueCat re-bind →
///     status refresh.
///
/// Neither function inspects a specific HTTP status / error_code (no 422 / 501 /
/// identity_already_exists assumption) and neither logs a token/nonce/ticket.
library;

import '../../data/services/auth_service.dart' show SignInResult, SignInOutcome;
import '../../data/services/identity_service.dart'
    show MergeTicketResult, ClaimResult, IdentityOutcome;

enum LinkNewIdentityResult { success, cancelled, failed }

enum ConnectExistingResult {
  notAvailable, // backend merge endpoints dormant / not anonymous → aborted safely
  success,
  pending, // merge accepted, finalizing server-side
  cancelled,
  retryable,
  terminal,
}

/// Structured outcome of a connect-existing attempt.
///
/// [retryTicket] is the ONLY replayable case: the Apple sign-in succeeded (the
/// user IS now connected to their existing account) but the claim/merge failed
/// RETRYABLY. The backend `identity_claim_and_merge` RPC is idempotent and
/// leaves the ticket UNCONSUMED for retryable states (settlement_active /
/// transport-rollback), so re-calling `/identity/claim` with the SAME ticket
/// (no new merge-ticket, no re-sign-in) safely resumes the merge. For every
/// other outcome the ticket is null (success/pending finalize on their own;
/// terminal/notAvailable/cancelled are not replayable).
///
/// [retryTicket] is held IN MEMORY ONLY — never logged, displayed, persisted, or
/// sent anywhere except `/identity/claim`. It is excluded from [toString].
class ConnectExistingAttempt {
  final ConnectExistingResult outcome;
  final bool authConnected; // Apple sign-in to the existing account succeeded
  final bool claimCompleted; // merge finished (non-pending success)
  final bool claimPending; // merge accepted, finalizing server-side
  final String? retryTicket; // in-memory only; non-null ONLY when replayable
  final String?
  retryUidBefore; // in-memory only; for the retry re-bind decision

  const ConnectExistingAttempt({
    required this.outcome,
    this.authConnected = false,
    this.claimCompleted = false,
    this.claimPending = false,
    this.retryTicket,
    this.retryUidBefore,
  });

  bool get canRetry => retryTicket != null;

  @override
  String toString() =>
      'ConnectExistingAttempt(outcome: $outcome, authConnected: $authConnected, '
      'claimCompleted: $claimCompleted, claimPending: $claimPending, '
      'canRetry: $canRetry)'; // NEVER the ticket value

  /// Map a claim result (after a successful sign-in) to a structured attempt.
  static ConnectExistingAttempt fromClaim(
    ClaimResult claimRes, {
    required String ticket,
    required String? uidBefore,
  }) {
    switch (claimRes.outcome) {
      case IdentityOutcome.success:
        final st = claimRes.status;
        final pending =
            st == 'identity_merge_pending' || st == 'billing_pending';
        return ConnectExistingAttempt(
          outcome: pending
              ? ConnectExistingResult.pending
              : ConnectExistingResult.success,
          authConnected: true,
          claimCompleted: !pending,
          claimPending: pending,
        );
      case IdentityOutcome.retryableFailure:
        // Replayable: keep the ticket + the anon uid for a claim-only retry.
        return ConnectExistingAttempt(
          outcome: ConnectExistingResult.retryable,
          authConnected: true,
          retryTicket: ticket,
          retryUidBefore: uidBefore,
        );
      case IdentityOutcome.featureDisabled:
        return const ConnectExistingAttempt(
          outcome: ConnectExistingResult.notAvailable,
          authConnected: true,
        );
      default: // terminalFailure — not replayable
        return const ConnectExistingAttempt(
          outcome: ConnectExistingResult.terminal,
          authConnected: true,
        );
    }
  }
}

/// Re-bind RevenueCat ONLY when the Supabase user id actually changed. A link
/// (new identity) preserves the UUID → returns false → no re-bind. Connecting
/// to an existing account changes the UUID → returns true.
bool shouldRebindRevenueCat({
  required String? uidBefore,
  required String? uidAfter,
}) => uidAfter != null && uidAfter.isNotEmpty && uidAfter != uidBefore;

/// Link a NEW Apple identity to the current anonymous user (UUID preserved).
/// On success refreshes /me/status; never re-binds RevenueCat (same UUID).
Future<LinkNewIdentityResult> runLinkNewIdentity({
  required Future<SignInResult> Function() linkApple,
  required Future<void> Function() refreshStatus,
}) async {
  final res = await linkApple();
  switch (res.outcome) {
    case SignInOutcome.success:
      await refreshStatus();
      return LinkNewIdentityResult.success;
    case SignInOutcome.cancelled:
      return LinkNewIdentityResult.cancelled;
    case SignInOutcome.failed:
      return LinkNewIdentityResult.failed;
  }
}

/// Connect to an EXISTING account. Safety: the merge ticket is created FIRST;
/// if it is not available (dormant backend → featureDisabled, or not_anonymous
/// → terminal), the flow ABORTS and the anonymous session is left untouched
/// (no sign-in happens). Only on a real ticket does it sign in (UUID changes),
/// re-bind RevenueCat to the new user, claim the ticket, and refresh status.
Future<ConnectExistingAttempt> runConnectExistingAccount({
  required String? Function() currentUid,
  required Future<MergeTicketResult> Function() createMergeTicket,
  required Future<SignInResult> Function() signInWithApple,
  required Future<ClaimResult> Function(String ticket) claim,
  required Future<void> Function(String uid) rebindRevenueCat,
  required Future<void> Function() refreshStatus,
}) async {
  final uidBefore = currentUid();

  // 1. Merge ticket BEFORE leaving the anonymous user. On failure the user is
  //    still anonymous → no retry ticket (a retry here would need a NEW ticket).
  final ticketRes = await createMergeTicket();
  if (ticketRes.outcome != IdentityOutcome.success ||
      ticketRes.ticket == null) {
    switch (ticketRes.outcome) {
      case IdentityOutcome.retryableFailure:
        return const ConnectExistingAttempt(
          outcome: ConnectExistingResult.retryable,
        );
      case IdentityOutcome.featureDisabled:
        return const ConnectExistingAttempt(
          outcome: ConnectExistingResult.notAvailable,
        );
      default:
        return const ConnectExistingAttempt(
          outcome: ConnectExistingResult.terminal,
        );
    }
  }
  final ticket = ticketRes.ticket!;

  // 2. Apple sign-in to the existing account (session/UUID changes).
  final signIn = await signInWithApple();
  if (signIn.outcome == SignInOutcome.cancelled) {
    return const ConnectExistingAttempt(
      outcome: ConnectExistingResult.cancelled,
    );
  }
  if (signIn.outcome != SignInOutcome.success) {
    return const ConnectExistingAttempt(
      outcome: ConnectExistingResult.retryable,
    );
  }

  // 3. Claim the ticket on the new account's session (performs the merge).
  //    ALWAYS attempted BEFORE the RevenueCat re-bind, so the claim's real
  //    outcome is captured and never masked by the re-bind.
  final claimRes = await claim(ticket);

  // 4. Re-bind RevenueCat to the current user if the UUID changed — AFTER the
  //    claim but REGARDLESS of its outcome, so RC never stays on the old anon.
  final uidAfter = currentUid();
  if (shouldRebindRevenueCat(uidBefore: uidBefore, uidAfter: uidAfter)) {
    await rebindRevenueCat(uidAfter!);
  }

  // 5. Refresh status regardless (the session changed).
  await refreshStatus();

  return ConnectExistingAttempt.fromClaim(
    claimRes,
    ticket: ticket,
    uidBefore: uidBefore,
  );
}

/// Retry ONLY the claim/merge after a retryable failure — the user is already
/// signed in to their existing account. Re-calls `/identity/claim` with the
/// SAME ticket (the backend RPC is idempotent and resumes the merge); it NEVER
/// creates a new merge ticket and NEVER re-runs the Apple sign-in. Order:
/// claim → RevenueCat re-bind (only if still needed) → refresh. On success the
/// caller drops the ticket from memory; on terminal it drops it (no more retry).
Future<ConnectExistingAttempt> retryExistingAccountClaim({
  required String ticket,
  required String? uidBefore,
  required String? Function() currentUid,
  required Future<ClaimResult> Function(String ticket) claim,
  required Future<void> Function(String uid) rebindRevenueCat,
  required Future<void> Function() refreshStatus,
}) async {
  final claimRes = await claim(ticket);

  final uidAfter = currentUid();
  if (shouldRebindRevenueCat(uidBefore: uidBefore, uidAfter: uidAfter)) {
    await rebindRevenueCat(uidAfter!);
  }

  await refreshStatus();

  return ConnectExistingAttempt.fromClaim(
    claimRes,
    ticket: ticket,
    uidBefore: uidBefore,
  );
}

enum SignOutResult { success, failed }

/// Sign out of the permanent (Apple) account and return to a fresh GUEST session.
/// Order: Supabase signOut → create a NEW anonymous session → re-bind RevenueCat
/// to the new anonymous UUID → refresh /me/status.
///
/// SAFETY (all server data is preserved): this NEVER deletes auth.users, the Apple
/// identity, server sessions/projects, or ledger/passes/orders; it NEVER detaches
/// Apple from the account and NEVER modifies the already-completed merge. It only
/// swaps the LOCAL session back to a guest. It NEVER grants a signup bonus and
/// NEVER transfers quota — the fresh anonymous user gets nothing from the logout;
/// server-side quota remains the single authority against free-tier abuse.
///
/// On any failure it still tries to leave SOME session active (best-effort
/// re-anonymize) so the app stays usable, and reports [SignOutResult.failed].
Future<SignOutResult> runSignOut({
  required Future<void> Function() signOut,
  required Future<void> Function() signInAnonymously,
  required String? Function() currentUid,
  required Future<void> Function(String uid) rebindRevenueCat,
  required Future<void> Function() refreshStatus,
}) async {
  // Phase 1 (CRITICAL) — drop the old identity and establish a fresh GUEST
  // session. signOut clears the old session first, so even on failure the app is
  // never left on the old identity; we retry the anon sign-in best-effort so the
  // app stays usable.
  try {
    await signOut();
    await signInAnonymously();
  } catch (_) {
    try {
      await signInAnonymously();
    } catch (_) {}
    return SignOutResult.failed;
  }

  // Phase 2 (BEST-EFFORT) — the session is already the fresh anon. Re-bind
  // RevenueCat to it and refresh /me/status. Each is ISOLATED: a rebind failure
  // must not skip the refresh (so the old account's premium never stays visible),
  // and vice-versa. A failure here reports `failed` but the session stays clean.
  var ok = true;
  final uidAfter = currentUid();
  if (uidAfter != null && uidAfter.isNotEmpty) {
    try {
      await rebindRevenueCat(uidAfter); // detach old user → bind fresh anon
    } catch (_) {
      ok = false;
    }
  }
  try {
    await refreshStatus();
  } catch (_) {
    ok = false;
  }
  return ok ? SignOutResult.success : SignOutResult.failed;
}
