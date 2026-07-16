/// Profile → Account section. A VOLUNTARY "Continue with Apple" entry for
/// anonymous users (never blocks Generate, never shown as a boot popup). It
/// wires the real services into the pure orchestration in account_link.dart.
///
/// Anonymous → subtitle + "Continue with Apple" (links a new identity, UUID
/// preserved). If that fails, reveals "Sign in to my existing account"
/// (merge-ticket → Apple sign-in → claim → RevenueCat re-bind → refresh).
///
/// Once signed in the row is "Connected with Apple", PLUS — distinctly — the
/// merge state: pending shows "finishing setup", a retryable claim shows a
/// "Retry account setup" button (claim-only retry, no new ticket / no re-signin),
/// and a terminal merge shows a clean "couldn't recover" note. No UUID / JWT /
/// sub / ticket / status is ever displayed.
///
/// The four optional constructor callbacks are a TEST seam only (no production
/// caller passes them): they drive the anonymous/connected state and the flows
/// WITHOUT the Supabase/Apple/RevenueCat SDKs. When absent the real services are
/// wired lazily.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/me_status_provider.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/identity_service.dart';
import '../../data/services/revenuecat_service.dart';
import '../../shared/widgets/app_button.dart';
import 'account_link.dart';

/// Which Account action is currently in flight. Drives a PER-BUTTON spinner:
/// only the tapped button shows a spinner; the others are disabled (no spinner).
enum AccountAction { none, linkApple, signInExisting, retryMerge, signOut }

class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({
    super.key,
    this.isAnonymous,
    this.onLink,
    this.onConnectExisting,
    this.onRetry,
    this.onSignOut,
  });

  // TEST seam (all null in production).
  final bool Function()? isAnonymous;
  final Future<LinkNewIdentityResult> Function()? onLink;
  final Future<ConnectExistingAttempt> Function()? onConnectExisting;
  final Future<ConnectExistingAttempt> Function(String ticket)? onRetry;
  final Future<SignOutResult> Function()? onSignOut;

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
  bool _showExisting = false; // revealed after a failed new-identity link

  // Merge (existing-account) state — all in memory.
  bool _mergePending = false;
  bool _mergeTerminal = false;
  String? _retryTicket; // non-null ONLY when a claim-only retry is possible
  String? _retryUidBefore; // for the retry re-bind decision

  bool get _hasSession =>
      widget.isAnonymous != null || _auth.currentUser != null;
  bool get _isAnon => widget.isAnonymous?.call() ?? _auth.isAnonymous;

  Future<void> _refreshStatus() =>
      ref.read(meStatusProvider.notifier).refresh();

  Future<LinkNewIdentityResult> _runLink() =>
      widget.onLink?.call() ??
      runLinkNewIdentity(
        linkApple: _auth.linkAppleIdentity,
        refreshStatus: _refreshStatus,
      );

  Future<ConnectExistingAttempt> _runConnectExisting() =>
      widget.onConnectExisting?.call() ??
      runConnectExistingAccount(
        currentUid: () => _auth.currentUser?.id,
        createMergeTicket: _identity.createMergeTicket,
        signInWithApple: _auth.signInWithApple,
        claim: _identity.claimExistingIdentity,
        rebindRevenueCat: RevenuecatService.instance.logIn,
        refreshStatus: _refreshStatus,
      );

  Future<ConnectExistingAttempt> _runRetry(String ticket) =>
      widget.onRetry?.call(ticket) ??
      retryExistingAccountClaim(
        ticket: ticket,
        uidBefore: _retryUidBefore,
        currentUid: () => _auth.currentUser?.id,
        claim: _identity.claimExistingIdentity,
        rebindRevenueCat: RevenuecatService.instance.logIn,
        refreshStatus: _refreshStatus,
      );

  Future<SignOutResult> _runSignOut() =>
      widget.onSignOut?.call() ??
      runSignOut(
        signOut: _auth.signOut,
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

  /// Fold a connect/retry attempt into the merge display state + a snackbar.
  void _applyAttempt(ConnectExistingAttempt a, AppLocalizations l10n) {
    setState(() {
      _mergePending = a.claimPending;
      _mergeTerminal = a.outcome == ConnectExistingResult.terminal;
      _retryTicket = a.retryTicket;
      _retryUidBefore = a.retryUidBefore;
      if (a.authConnected) {
        _showExisting = false; // connected → drop the anonymous CTA path
      }
    });
    switch (a.outcome) {
      case ConnectExistingResult.success:
        _snack(l10n.acctConnectedSuccess);
      case ConnectExistingResult.pending:
        _snack(l10n.acctConnectedPending);
      case ConnectExistingResult.notAvailable:
        _snack(l10n.acctNotAvailable);
      case ConnectExistingResult.cancelled:
        break; // silent
      case ConnectExistingResult.retryable:
        _snack(l10n.acctGenericError);
      case ConnectExistingResult.terminal:
        _snack(l10n.acctMergeFailed);
    }
  }

  // ── Continue with Apple (link a NEW identity, preserve UUID) ────────────────
  Future<void> _onContinueWithApple() async {
    if (_busy) {
      return;
    }
    setState(() => _action = AccountAction.linkApple);
    final l10n = context.l10n;
    try {
      final result = await _runLink();
      if (!mounted) {
        return;
      }
      switch (result) {
        case LinkNewIdentityResult.success:
          setState(() {
            _showExisting = false;
            _mergePending = false;
            _mergeTerminal = false;
            _retryTicket = null;
          });
          _snack(l10n.acctConnectedSuccess);
        case LinkNewIdentityResult.cancelled:
          break; // silent
        case LinkNewIdentityResult.failed:
          setState(() => _showExisting = true);
          _snack(l10n.acctAppleAlreadyLinked);
      }
    } finally {
      if (mounted) {
        setState(() => _action = AccountAction.none);
      }
    }
  }

  // ── Sign in to my existing account (merge-ticket → sign-in → claim) ──────────
  Future<void> _onSignInExisting() async {
    if (_busy) {
      return;
    }
    setState(() => _action = AccountAction.signInExisting);
    final l10n = context.l10n;
    try {
      final attempt = await _runConnectExisting();
      if (!mounted) {
        return;
      }
      _applyAttempt(attempt, l10n);
    } finally {
      if (mounted) {
        setState(() => _action = AccountAction.none);
      }
    }
  }

  // ── Retry ONLY the claim (already signed in; no new ticket / no re-signin) ──
  Future<void> _onRetryClaim() async {
    final ticket = _retryTicket;
    if (_busy || ticket == null) {
      return;
    }
    setState(() => _action = AccountAction.retryMerge);
    final l10n = context.l10n;
    try {
      final attempt = await _runRetry(ticket);
      if (!mounted) {
        return;
      }
      _applyAttempt(attempt, l10n);
    } finally {
      if (mounted) {
        setState(() => _action = AccountAction.none);
      }
    }
  }

  // ── Sign out → fresh GUEST session (no server data deleted) ─────────────────
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
      final result = await _runSignOut();
      if (!mounted) {
        return;
      }
      if (result == SignOutResult.success) {
        setState(() {
          _showExisting = false;
          _mergePending = false;
          _mergeTerminal = false;
          _retryTicket = null;
          _retryUidBefore = null;
        });
        _snack(l10n.acctSignedOut);
      } else {
        _snack(l10n.acctSignOutFailed);
      }
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

    // No session at all → render nothing (there is normally an anon session).
    if (!_hasSession) {
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
          if (_isAnon) _anonymousBody(l10n) else _connectedBody(l10n),
        ],
      ),
    );
  }

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
          onPressed: _busy ? null : _onContinueWithApple,
          variant: AppButtonVariant.dark,
          loading: _action == AccountAction.linkApple,
          icon: Icons.apple,
          fullWidth: true,
        ),
        if (_showExisting) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: l10n.acctSignInExisting,
            onPressed: _busy ? null : _onSignInExisting,
            variant: AppButtonVariant.secondary,
            loading: _action == AccountAction.signInExisting,
            fullWidth: true,
          ),
        ],
      ],
    );
  }

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
        // Merge still finalizing server-side (NOT full success).
        if (_mergePending) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.acctConnectedPending,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
        // Merge failed permanently — clean, non-technical note; no retry.
        if (_mergeTerminal) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.acctMergeFailed,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
        // Retryable claim — resume the SAME merge (no new ticket / no re-signin).
        if (_retryTicket != null) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: l10n.acctRetrySetup,
            onPressed: _busy ? null : _onRetryClaim,
            variant: AppButtonVariant.secondary,
            loading: _action == AccountAction.retryMerge,
            fullWidth: true,
          ),
        ],
        // Sign out → back to a fresh guest session. No server data is touched.
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
}
