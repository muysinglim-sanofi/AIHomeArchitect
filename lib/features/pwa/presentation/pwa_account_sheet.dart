/// The account sheet: attach an identity, or sign in to one that exists.
///
/// Two journeys with one shape, and the difference stated OUT LOUD rather than
/// implied. §7 of the brief and the frozen identity spec both turn on the same
/// point — an existing account brings nothing over — so this screen says so
/// before the person commits, not afterwards.
///
/// Where it appears from is also a rule (§8): never on Home, never on Create.
/// Someone may photograph a room, choose an atmosphere and generate their free
/// vision without ever seeing this. It opens from the paywall and from the
/// account chip, which are the two moments where identity is the actual subject.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import '../auth/pwa_auth_controller.dart';
import '../billing/pwa_entitlement_controller.dart';
import '../auth/pwa_auth_service.dart';
import '../auth/pwa_verification_channel.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_theme.dart';
import 'pwa_widgets.dart' show pwaSerif;

/// Opens the sheet. Returns true when the person ended up identified, so the
/// caller (the paywall) can react without watching the provider itself.
/// [signIn] opens on the RETURNING-USER journey rather than on "Save your
/// work". The two are different operations, not two labels for one: linking
/// attaches an address to the anonymous user in place and keeps their work,
/// while signing in switches to an account that already exists and carries
/// nothing over. A person opening Ayden in a fresh browser needs the second,
/// and until now could only reach it by first being TOLD their address was
/// taken — which meant typing an address into a screen offering to save work
/// they had not done yet.
Future<bool> showPwaAccountSheet(
  BuildContext context, {
  bool signIn = false,
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pwaSurface,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PwaAccountSheet(signIn: signIn),
  );
  return done ?? false;
}

/// Make the app BE the current identity: entitlement, and — when the user
/// itself changed — the project library.
///
/// One seam, three callers (verify, and the two sign-out entries). It used to
/// be open-coded at each call site, entitlement only, and the library half was
/// missing everywhere: signing out left the previous account's projects in the
/// working library, and signing in never loaded the new account's at all.
Future<void> pwaHydrateForIdentity(
  WidgetRef ref, {
  required bool switchedUser,
}) async {
  // A different identity is a different entitlement — always re-read, never
  // carry the previous answer forward.
  await ref.read(pwaEntitlementProvider.notifier).onIdentityChanged();
  // …and a different USER owns different work. Not on a link: that keeps the
  // same user, so the library is already correct, and resetting the session
  // would throw away the work being saved.
  if (switchedUser) {
    await ref.read(pwaControllerProvider.notifier).reloadForIdentity();
  }
}

class _PwaAccountSheet extends ConsumerStatefulWidget {
  const _PwaAccountSheet({this.signIn = false});

  /// Which journey the sheet OPENS on. The caller decides, because the caller
  /// is the one that knows which question was asked.
  final bool signIn;

  @override
  ConsumerState<_PwaAccountSheet> createState() => _PwaAccountSheetState();
}

class _PwaAccountSheetState extends ConsumerState<_PwaAccountSheet> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  /// The person chose to sign in to an existing account — either by opening
  /// the sheet on that journey, or after being told the address was taken.
  /// Held here, not in the service: it is a UI journey choice, and the service
  /// must never infer it.
  late bool _signInMode = widget.signIn;

  /// Authentication has SUCCEEDED and the account's own state is being read.
  ///
  /// This is the whole of §4. The sheet used to hand back control the instant
  /// `verifyOTP` returned, which put a verified email on screen beside the
  /// previous identity's entitlement and the previous identity's (empty)
  /// project library — a half-old, half-new account the person could see and
  /// act on. Now nothing is handed back until identity, entitlement and
  /// library have all settled.
  bool _settling = false;

  /// Verify the code, and — only if it worked — make the app be this account.
  ///
  /// The refresh used to be the CALLER's job, done after the sheet returned
  /// `true`. That had two holes: the sheet returned `true` only from one
  /// button, so dismissing it by swipe or barrier tap skipped the refresh
  /// entirely; and even when it ran, it ran after the authenticated UI was
  /// already on screen. Both are gone: the work happens here, before the sheet
  /// closes, on every path that succeeds.
  Future<void> _verifyAndSettle() async {
    final auth = ref.read(pwaAuthProvider.notifier);
    final destination = ref.read(pwaAuthProvider).destination;
    await auth.submitCode(destination, _code.text);
    if (!mounted) return;

    final s = ref.read(pwaAuthProvider);
    if (s.stage != PwaAuthStage.identified) return; // the code was refused

    setState(() => _settling = true);
    await pwaHydrateForIdentity(ref, switchedUser: s.switchedAccount);
    if (!mounted) return;
    // Authentication has succeeded and everything it changes has settled.
    // There is nothing left to ask, so nothing is asked: the sheet closes
    // itself and the person is returned to what they were doing.
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final auth = ref.watch(pwaAuthProvider);
    final controller = ref.read(pwaAuthProvider.notifier);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    Widget body;
    if (!controller.isAvailable) {
      body = _Message(title: l.accountTitle, body: l.authUnavailable);
    } else if (auth.stage == PwaAuthStage.identified) {
      // SUCCESS — and therefore nothing to decide. This state used to offer a
      // single button labelled `l.paywallClose`, which is the PAYWALL's "Not
      // now": an invitation to postpone something that had already happened,
      // and the only path that told the app to refresh itself. It is now a
      // settling state with no action at all; `_verifyAndSettle` closes the
      // sheet as soon as the account's own state is on screen behind it.
      //
      // Which promise is honest depends on a MEASURED fact: the same user_id
      // means the work came along, a different one means it did not.
      body = _Settling(
        title: auth.switchedAccount
            ? l.accountSwitchedTitle
            : l.accountLinkedTitle,
        body: auth.switchedAccount ? l.accountSwitchedBody : l.accountLinkedBody,
        footnote: auth.email.isEmpty ? null : l.accountSignedInAs(auth.email),
      );
    } else if (auth.failure ==
        PwaVerificationFailure.destinationAlreadyRegistered) {
      // A fork, not an error. Nothing happens until the person picks.
      body = _Message(
        title: l.accountExistsTitle,
        body: l.accountExistsBody,
        primary: l.accountSignInInstead,
        busy: auth.busy,
        onPrimary: () {
          setState(() => _signInMode = true);
          controller.beginSignIn(_email.text);
        },
        secondary: l.accountChangeEmail,
        onSecondary: () {
          setState(() => _signInMode = false);
          controller.cancel();
        },
      );
    } else if (auth.stage == PwaAuthStage.awaitingCode) {
      body = _CodeStep(
        controller: _code,
        destination: auth.destination,
        busy: auth.busy,
        failure: auth.failure,
        onVerify: _settling ? null : _verifyAndSettle,
        onResend: () => controller.resend(auth.destination),
        onBack: () {
          _code.clear();
          controller.cancel();
        },
      );
    } else {
      body = _EmailStep(
        controller: _email,
        signInMode: _signInMode,
        busy: auth.busy,
        failure: auth.failure,
        canSubmit: controller.looksValid(_email.text),
        onChanged: () => setState(() {}),
        onSubmit: () => _signInMode
            ? controller.beginSignIn(_email.text)
            : controller.beginLink(_email.text),
        onToggleMode: () {
          setState(() => _signInMode = !_signInMode);
          controller.cancel();
        },
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: pwaHairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: PwaGap.lg),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Step 1: the destination ──────────────────────────────────────────────────

class _EmailStep extends StatelessWidget {
  const _EmailStep({
    required this.controller,
    required this.signInMode,
    required this.busy,
    required this.failure,
    required this.canSubmit,
    required this.onChanged,
    required this.onSubmit,
    required this.onToggleMode,
  });

  final TextEditingController controller;
  final bool signInMode;
  final bool busy;
  final PwaVerificationFailure? failure;
  final bool canSubmit;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(signInMode ? l.accountSignInTitle : l.accountTitle,
            style: pwaSerif(fontSize: 24, fontWeight: FontWeight.w500)),
        const SizedBox(height: PwaGap.sm),
        Text(signInMode ? l.accountSignInBody : l.accountBody,
            style: pwaSans(fontSize: 14, color: pwaMuted, height: 1.5)),
        const SizedBox(height: PwaGap.lg),
        TextField(
          controller: controller,
          onChanged: (_) => onChanged(),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (canSubmit && !busy) onSubmit();
          },
          style: pwaSans(fontSize: 15),
          decoration: _fieldDecoration(l.accountEmailLabel, l.accountEmailHint),
        ),
        if (failure != null) _FailureLine(failure!),
        const SizedBox(height: PwaGap.lg),
        _PrimaryButton(
          label: l.accountSend,
          busy: busy,
          onPressed: canSubmit && !busy ? onSubmit : null,
        ),
        const SizedBox(height: PwaGap.sm),
        TextButton(
          onPressed: busy ? null : onToggleMode,
          child: Text(
            signInMode ? l.accountBackToLink : l.accountSignInInstead,
            style: pwaSans(fontSize: 13, color: pwaMuted),
          ),
        ),
      ],
    );
  }
}

// ── Step 2: the code ─────────────────────────────────────────────────────────

class _CodeStep extends StatelessWidget {
  const _CodeStep({
    required this.controller,
    required this.destination,
    required this.busy,
    required this.failure,
    required this.onVerify,
    required this.onResend,
    required this.onBack,
  });

  final TextEditingController controller;
  final String destination;
  final bool busy;
  final PwaVerificationFailure? failure;
  /// Null while the account's own state is being read: authentication has
  /// already succeeded and re-submitting the code would mean nothing.
  final VoidCallback? onVerify;
  final VoidCallback onResend;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.accountCodeTitle,
            style: pwaSerif(fontSize: 24, fontWeight: FontWeight.w500)),
        const SizedBox(height: PwaGap.sm),
        Text(l.accountCodeBody(destination),
            style: pwaSans(fontSize: 14, color: pwaMuted, height: 1.5)),
        const SizedBox(height: PwaGap.lg),
        TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!busy) onVerify?.call();
          },
          // Latin digits, widely spaced: a code is read character by character.
          style: pwaSans(fontSize: 22, letterSpacing: 6),
          textAlign: TextAlign.center,
          decoration: _fieldDecoration(l.accountCodeLabel, '– – – – – –'),
        ),
        if (failure != null) _FailureLine(failure!),
        const SizedBox(height: PwaGap.lg),
        _PrimaryButton(
          label: l.accountVerify,
          busy: busy,
          onPressed: (busy || onVerify == null) ? null : onVerify,
        ),
        const SizedBox(height: PwaGap.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: busy ? null : onBack,
              child: Text(l.accountChangeEmail,
                  style: pwaSans(fontSize: 13, color: pwaMuted)),
            ),
            TextButton(
              onPressed: busy ? null : onResend,
              child: Text(l.accountResend,
                  style: pwaSans(fontSize: 13, color: pwaGold)),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Shared pieces ────────────────────────────────────────────────────────────

/// Authentication has succeeded; the account's own state is being read.
///
/// It says what happened and shows that something is still finishing — and
/// offers NOTHING to press, because there is nothing left to decide. The sheet
/// removes itself as soon as the work behind it is done.
class _Settling extends StatelessWidget {
  const _Settling({
    required this.title,
    required this.body,
    this.footnote,
  });

  final String title;
  final String body;
  final String? footnote;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('pwa-account-settling'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: pwaSerif(fontSize: 22, fontWeight: FontWeight.w500)),
          const SizedBox(height: PwaGap.sm),
          Text(body, style: pwaSans(fontSize: 14, color: pwaMuted, height: 1.5)),
          if (footnote != null) ...[
            const SizedBox(height: PwaGap.xs),
            Text(footnote!, style: pwaSans(fontSize: 13, color: pwaFaint)),
          ],
          const SizedBox(height: PwaGap.lg),
          const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: pwaGold),
              ),
            ],
          ),
          const SizedBox(height: PwaGap.md),
        ],
      );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.body,
    this.primary,
    this.onPrimary,
    this.secondary,
    this.onSecondary,
    this.busy = false,
  });

  final String title;
  final String body;
  final String? primary;
  final VoidCallback? onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: pwaSerif(fontSize: 24, fontWeight: FontWeight.w500)),
        const SizedBox(height: PwaGap.sm),
        Text(body, style: pwaSans(fontSize: 14, color: pwaMuted, height: 1.5)),
        if (primary != null) ...[
          const SizedBox(height: PwaGap.lg),
          _PrimaryButton(label: primary!, busy: busy, onPressed: onPrimary),
        ],
        if (secondary != null) ...[
          const SizedBox(height: PwaGap.xs),
          TextButton(
            onPressed: onSecondary,
            child: Text(secondary!,
                style: pwaSans(fontSize: 13, color: pwaMuted)),
          ),
        ],
      ],
    );
  }
}

class _FailureLine extends StatelessWidget {
  const _FailureLine(this.failure);

  final PwaVerificationFailure failure;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: PwaGap.sm),
        child: Text(
          context.pwaL10n.verificationFailure(failure),
          style: pwaSans(fontSize: 13, color: const Color(0xFFB4472E)),
        ),
      );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && onPressed != null;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: pwaBlack,
        foregroundColor: pwaOnDark,
        disabledBackgroundColor: pwaBlack.withValues(alpha: 0.35),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PwaGap.radius),
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: pwaOnDark),
            )
          // Wraps rather than truncates: French and Khmer both run long, and a
          // clipped button label is a broken promise.
          //
          // The colour is passed EXPLICITLY and follows the ENABLED state,
          // because two things are true at once: `pwaSans` defaults to `pwaInk`
          // and an explicit TextStyle beats the button's `foregroundColor` — so
          // omitting it paints near-black on the black pill — while the DISABLED
          // pill is a pale grey on which light text vanishes just as badly.
          // One fixed colour cannot serve both; the Khmer review showed the
          // first half and the fix's own screenshot showed the second.
          : Text(label,
              textAlign: TextAlign.center,
              style: pwaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: enabled ? pwaOnDark : pwaInk,
              )),
    );
  }
}

InputDecoration _fieldDecoration(String label, String hint) => InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: pwaSans(fontSize: 13, color: pwaMuted),
      hintStyle: pwaSans(fontSize: 15, color: pwaFaint),
      filled: true,
      fillColor: pwaIvory,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PwaGap.radius),
        borderSide: const BorderSide(color: pwaHairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PwaGap.radius),
        borderSide: const BorderSide(color: pwaHairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PwaGap.radius),
        borderSide: const BorderSide(color: pwaGold, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    );
