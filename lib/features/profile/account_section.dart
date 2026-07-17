/// Profile → Account section — ON-mode (FeatureFlags.accountSystemEnabled=true).
///
/// This widget is rendered ONLY when the master account-system flag is ON
/// (profile_screen gates it). It wires the real services into the PURE ON
/// orchestration in account_link.dart (Guest durable — park/restore model,
/// docs/GUEST_ACCOUNT_IDENTITY_SPEC.md). The OLD merge model (linkIdentity /
/// merge-ticket / mint-fresh-anon on sign-out) is NOT used here anymore — the
/// three flows are exclusively:
///   • CREATE_NEW_ACCOUNT  → runCreateAccountOn (park Guest → local signOut →
///     fresh Apple sign-in → claim Free+bonus once → RC re-bind → refresh).
///   • SIGN_IN_EXISTING    → runSignInExistingOn (park Guest → switch account →
///     RC re-bind → refresh ; NO claim, NO bonus).
///   • SIGN_OUT            → runSignOutOn (restore the EXACT parked Guest ; on a
///     transient restore failure with a parked blob still present it raises
///     guestRestorePending — NEVER a new anonymous Guest — which gates Generate
///     and shows a Retry banner).
///
/// No UUID / JWT / sub / ticket / status is ever displayed.
///
/// The three optional constructor callbacks are a TEST seam only (no production
/// caller passes them): they drive the flows WITHOUT the Supabase/Apple/
/// RevenueCat SDKs. When absent the real services are wired lazily.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/guest_parking.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/active_session_provider.dart';
import '../../core/providers/guest_restore_pending_provider.dart';
import '../../core/providers/me_status_provider.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/identity_service.dart';
import '../../data/services/revenuecat_service.dart';
import '../../shared/widgets/app_button.dart';
import 'account_link.dart';

/// Which Account action is currently in flight. Drives a PER-BUTTON spinner:
/// only the tapped button shows a spinner; the others are disabled (no spinner).
enum AccountAction { none, create, signInExisting, signOut, restore }

class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({
    super.key,
    this.isAnonymous,
    this.onCreate,
    this.onSignInExisting,
    this.onSignOut,
  });

  // TEST seam (all null in production).
  final bool Function()? isAnonymous;
  final Future<CreateAccountAttempt> Function()? onCreate;
  final Future<SignInExistingResult> Function()? onSignInExisting;
  final Future<SignOutRestoreResult> Function()? onSignOut;

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  // Real services created lazily — never instantiated when the test seam is
  // used (so widget tests need no Supabase).
  AuthService? _authOrNull;
  IdentityService? _identityOrNull;
  AuthService get _auth => _authOrNull ??= AuthService();
  IdentityService get _identity => _identityOrNull ??= IdentityService();

  // Per-button spinner driver: exactly one action can be in flight; the tapped
  // button shows the spinner, the others are disabled without one.
  AccountAction _action = AccountAction.none;
  bool get _busy => _action != AccountAction.none; // any action in flight

  bool get _hasSession =>
      widget.isAnonymous != null || _auth.currentUser != null;
  bool get _isAnon => widget.isAnonymous?.call() ?? _auth.isAnonymous;

  Future<void> _refreshStatus() =>
      ref.read(meStatusProvider.notifier).refresh();

  // ── ON flows wired to the real services (test seams short-circuit these) ────

  /// CREATE — defensive: the claim ticket is issued to the GUEST session FIRST,
  /// then the Guest is parked, the local session is dropped, and a FRESH Apple
  /// sign-in creates a SEPARATE account (no active anon → GoTrue cannot auto-link).
  Future<CreateAccountAttempt> _runCreate() =>
      widget.onCreate?.call() ??
      runCreateAccountOn(
        getClaimTicket: _identity.getClaimTicket,
        parkGuest: GuestParking.parkCurrent,
        signOutLocal: _auth.signOut,
        signIn: _auth.signInWithApple,
        restoreGuest: GuestParking.restore,
        claim: _identity.claimGuestOnCreate,
        currentUid: () => _auth.currentUser?.id,
        rebindRevenueCat: RevenuecatService.instance.logIn,
        refreshStatus: _refreshStatus,
      );

  /// SIGN_IN_EXISTING — no claim, no bonus. Park the Guest, switch to the
  /// existing account, re-bind RevenueCat, refresh. Guest restored on sign-out.
  Future<SignInExistingResult> _runSignInExisting() =>
      widget.onSignInExisting?.call() ??
      runSignInExistingOn(
        parkGuest: GuestParking.parkCurrent,
        signOutLocal: _auth.signOut,
        signIn: _auth.signInWithApple,
        restoreGuest: GuestParking.restore,
        currentUid: () => _auth.currentUser?.id,
        rebindRevenueCat: RevenuecatService.instance.logIn,
        refreshStatus: _refreshStatus,
      );

  /// SIGN_OUT — restore the EXACT parked Guest. On a transient restore failure
  /// with a parked blob still present → SignOutRestoreResult.restorePending
  /// (the caller raises guestRestorePending; NEVER a new anon).
  Future<SignOutRestoreResult> _runSignOut() =>
      widget.onSignOut?.call() ??
      runSignOutOn(
        signOutLocal: _auth.signOut,
        hasParked: GuestParking.hasParked,
        restoreGuest: GuestParking.restore,
        signInAnonymously: _auth.signInAnonymouslyIfNeeded,
        currentUid: () => _auth.currentUser?.id,
        rebindRevenueCat: RevenuecatService.instance.logIn,
        refreshStatus: _refreshStatus,
      );

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Create a NEW account (Guest stays a distinct identity server-side) ──────
  Future<void> _onCreate() async {
    if (_busy) {
      return;
    }
    setState(() => _action = AccountAction.create);
    final l10n = context.l10n;
    try {
      final r = await _runCreate();
      if (!mounted) {
        return;
      }
      switch (r.outcome) {
        case CreateAccountResult.success:
          setState(() {});
          _snack(l10n.acctConnectedSuccess);
        case CreateAccountResult.cancelled:
          break; // silent — Guest was restored, nothing changed
        case CreateAccountResult.failed:
          _snack(l10n.acctGenericError);
      }
    } finally {
      if (mounted) {
        setState(() => _action = AccountAction.none);
      }
    }
  }

  // ── Sign in to an EXISTING account (returning user; no claim, no bonus) ──────
  Future<void> _onSignInExisting() async {
    if (_busy) {
      return;
    }
    setState(() => _action = AccountAction.signInExisting);
    final l10n = context.l10n;
    try {
      final r = await _runSignInExisting();
      if (!mounted) {
        return;
      }
      switch (r) {
        case SignInExistingResult.success:
          setState(() {});
          _snack(l10n.acctConnectedSuccess);
        case SignInExistingResult.cancelled:
          break; // silent
        case SignInExistingResult.failed:
          _snack(l10n.acctGenericError);
      }
    } finally {
      if (mounted) {
        setState(() => _action = AccountAction.none);
      }
    }
  }

  // ── Sign out → restore the EXACT parked GUEST (never a new anon) ────────────
  Future<void> _onSignOut() async {
    if (_busy) {
      return;
    }
    final l10n = context.l10n;
    final confirmed = await _confirmSignOut(l10n);
    if (confirmed != true || !mounted) {
      return; // cancelled → nothing happens
    }
    setState(() => _action = AccountAction.signOut);
    try {
      final r = await _runSignOut();
      if (!mounted) {
        return;
      }
      // The old chat context is stale after the session swap. sessionProvider and
      // pendingGenerationsProvider self-invalidate on the auth change via their
      // own listeners; the ephemeral active-session pointer has no notifier, so
      // reset it here.
      ref.read(activeSessionProvider.notifier).state = null;
      switch (r) {
        case SignOutRestoreResult.restored:
        case SignOutRestoreResult.newGuest:
          setState(() {});
          _snack(l10n.acctSignedOut);
        case SignOutRestoreResult.restorePending:
          // CORRECTION anti-anon (obligatoire) — le Guest parqué existe mais la
          // restauration a échoué (réseau / refresh token indispo). On lève le
          // flag persistant → la génération/wallet est BLOQUÉE (single choke-point)
          // et un bandeau Retry re-tente recoverSession. JAMAIS un nouvel anonyme,
          // donc aucun trial fantôme, aucun historique vide, aucune identité fantôme.
          await ref
              .read(guestRestorePendingProvider.notifier)
              .setPending(true);
          setState(() {});
          _snack(l10n.acctSignOutFailed);
        case SignOutRestoreResult.failed:
          _snack(l10n.acctSignOutFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _action = AccountAction.none);
      }
    }
  }

  // ── Retry the parked-Guest restoration (banner) ─────────────────────────────
  Future<void> _onRetryRestore() async {
    if (_busy) {
      return;
    }
    setState(() => _action = AccountAction.restore);
    try {
      // resolve() re-tries recoverSession + RC re-bind; on success it lowers the
      // flag (the banner disappears via the watch below) and re-opens Generate.
      await ref.read(guestRestorePendingProvider.notifier).resolve();
    } finally {
      if (mounted) {
        setState(() => _action = AccountAction.none);
      }
    }
  }

  /// Confirmation dialog before signing out. Returns true only if confirmed.
  Future<bool?> _confirmSignOut(AppLocalizations l10n) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.acctSignOutConfirmTitle),
        content: Text(l10n.acctSignOutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.acctSignOutCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.acctSignOutConfirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final restorePending = ref.watch(guestRestorePendingProvider);

    // No session AND no restore pending → render nothing (there is normally an
    // anon session). While a restore is pending the session may be momentarily
    // absent (signOut ran, recoverSession failed) — we STILL show the banner.
    if (!_hasSession && !restorePending) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        0,
        AppSpacing.pagePadding,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.acctSectionTitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (restorePending)
            _restoreBanner(l10n)
          else if (_isAnon)
            _anonymousBody(l10n)
          else
            _connectedBody(l10n),
        ],
      ),
    );
  }

  /// Guest → CREATE a new account (primary) OR SIGN IN to an existing one. Both
  /// are ON flows; neither ever deletes server data.
  Widget _anonymousBody(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.acctSaveDesignsSubtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: l10n.acctContinueWithApple,
          onPressed: _busy ? null : _onCreate,
          variant: AppButtonVariant.dark,
          loading: _action == AccountAction.create,
          icon: Icons.apple,
          fullWidth: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: l10n.acctSignInExisting,
          onPressed: _busy ? null : _onSignInExisting,
          variant: AppButtonVariant.secondary,
          loading: _action == AccountAction.signInExisting,
          fullWidth: true,
        ),
      ],
    );
  }

  /// Connected account → "Connected" + Sign out (restores the parked Guest).
  Widget _connectedBody(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(
              l10n.acctConnectedWithApple,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: l10n.acctSignOut,
          onPressed: _busy ? null : _onSignOut,
          variant: AppButtonVariant.secondary,
          loading: _action == AccountAction.signOut,
          fullWidth: true,
        ),
      ],
    );
  }

  /// Restore-pending banner (anti-anon correction) — the parked Guest could not
  /// be restored (transient). Generation is gated elsewhere; here we surface a
  /// clear state + a Retry that re-runs recoverSession. No new anonymous Guest.
  Widget _restoreBanner(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kGuestRestorePendingMessage,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: l10n.acctRetrySetup,
          onPressed: _busy ? null : _onRetryRestore,
          variant: AppButtonVariant.secondary,
          loading: _action == AccountAction.restore,
          fullWidth: true,
        ),
      ],
    );
  }
}
