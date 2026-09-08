/// The account sheet: secure the account you have, or sign in to one that
/// exists — by Facebook, by phone, or by email.
///
/// Two journeys with one shape, and the difference stated OUT LOUD rather than
/// implied. §7 of the brief and the frozen identity spec both turn on the same
/// point — an existing account brings nothing over — so this screen says so
/// before the person commits, not afterwards.
///
/// Cambodia first (2026-09-08): Facebook and phone are the primary doors,
/// email is the visibly secondary one. Which doors exist is the PROJECT's
/// answer (`PwaAuthProviders`, read from GoTrue at boot), so a deployment with
/// email alone opens straight on the address field, exactly as before.
///
/// Where it appears from is also a rule (§8): never on Home, never on Create.
/// Someone may photograph a room, choose an atmosphere and generate their free
/// vision without ever seeing this. It opens from the paywall, from Profile
/// and from the account chip, which are the moments where identity is the
/// actual subject — and from Profile again when a Facebook round-trip lands.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import '../auth/pwa_auth_controller.dart';
import '../auth/pwa_auth_service.dart';
import '../auth/pwa_phone_number.dart';
import '../auth/pwa_verification_channel.dart';
import '../billing/pwa_entitlement_controller.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_theme.dart';
import 'pwa_widgets.dart' show pwaSerif;

/// How long the person waits before a code can be sent again. GoTrue refuses
/// sooner than this on its side (`sms_max_frequency`, 60 s by default); the
/// client mirrors it so the button says "in 42 s" rather than failing.
const Duration kPwaAuthResendCooldown = Duration(seconds: 60);

/// Opens the sheet. Returns true when the person ended up identified, so the
/// caller (the paywall) can react without watching the provider itself.
///
/// [signIn] opens on the RETURNING-USER journey rather than on "Secure my
/// account". The two are different operations, not two labels for one:
/// linking attaches an identity to the current user in place and keeps their
/// work, while signing in switches to an account that already exists and
/// carries nothing over.
///
/// [method] skips the chooser: Profile's "Phone — Add" opens on the phone
/// field directly, because the choice has already been made.
Future<bool> showPwaAccountSheet(
  BuildContext context, {
  bool signIn = false,
  PwaAuthMethod? method,
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pwaSurface,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    // A bottom sheet the width of a 1440 px monitor is a banner, not a
    // dialog. Capped and centred on desktop; full width on a phone.
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PwaAccountSheet(signIn: signIn, method: method),
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
  const _PwaAccountSheet({this.signIn = false, this.method});

  /// Which journey the sheet OPENS on. The caller decides, because the caller
  /// is the one that knows which question was asked.
  final bool signIn;

  /// Which transport, when the caller already knows. Null = let the person
  /// choose (or, with email alone, go straight to it).
  final PwaAuthMethod? method;

  @override
  ConsumerState<_PwaAccountSheet> createState() => _PwaAccountSheetState();
}

class _PwaAccountSheetState extends ConsumerState<_PwaAccountSheet> {
  final _email = TextEditingController();
  final _dial = TextEditingController(text: PwaPhoneNumber.defaultDialCode);
  final _phone = TextEditingController();
  final _code = TextEditingController();

  /// The person chose to sign in to an existing account — either by opening
  /// the sheet on that journey, or after being told the identity was taken.
  /// Held here, not in the service: it is a UI journey choice, and the service
  /// must never infer it.
  late bool _signInMode = widget.signIn;

  /// Which transport is on screen. Null = the chooser.
  PwaAuthMethod? _method;

  /// Authentication has SUCCEEDED and the account's own state is being read.
  /// Nothing is handed back until identity, entitlement and library have all
  /// settled — a half-old, half-new account must never be on screen.
  bool _settling = false;

  /// Seconds until a code can be sent again. Zero = allowed.
  int _cooldown = 0;
  Timer? _ticker;

  /// A Facebook outcome that landed with the page: shown once, then cleared.
  bool _oauthShown = false;

  /// Held from initState: `ref` may not be touched once the sheet is disposed,
  /// and the outcome flag is cleared exactly then.
  late final PwaAuthController _authController;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(pwaAuthProvider.notifier);
    _authController = controller;
    final auth = ref.read(pwaAuthProvider);
    if (auth.oauthPending) {
      // The sheet is the OUTCOME of a round-trip. Method and journey come
      // from the state the boot code measured, not from how we were opened.
      _method = PwaAuthMethod.facebook;
      _signInMode = auth.journey == PwaAuthJourney.signInExisting;
      _oauthShown = true;
      if (auth.isIdentified && auth.failure == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _settleAfter(auth));
      }
    } else {
      _method = widget.method ??
          (controller.providers.hasPrimaryChoice ? null : PwaAuthMethod.email);
      // A previous journey's remnants (journey, failure) must not shape a
      // NEW opening; the session is the only thing carried in. Deferred one
      // tick: a provider may not be written while the tree is being built.
      _ready = false;
      Future<void>.microtask(() {
        if (!mounted) return;
        controller.cancel();
        setState(() => _ready = true);
      });
    }
  }

  /// False for the one tick between opening and the reset above.
  bool _ready = true;

  @override
  void dispose() {
    _ticker?.cancel();
    // The outcome was shown by this sheet; a reopen must not show it again.
    // One tick later: a provider may not be written while the tree is being
    // torn down, and the notifier checks its own `mounted` if it is gone.
    if (_oauthShown) {
      final c = _authController;
      Future<void>.microtask(c.consumeOAuthOutcome);
    }
    _email.dispose();
    _dial.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _cooldown = kPwaAuthResendCooldown.inSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldown = _cooldown > 0 ? _cooldown - 1 : 0;
        if (_cooldown == 0) t.cancel();
      });
    });
  }

  /// The E.164 number the two phone fields describe, or null.
  String? get _e164 {
    final raw = _phone.text.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('+') || raw.startsWith('00')) {
      return PwaPhoneNumber.normalize(raw);
    }
    return PwaPhoneNumber.normalize(raw, dialCode: _dial.text);
  }

  Future<void> _sendEmail() async {
    final c = ref.read(pwaAuthProvider.notifier);
    if (_signInMode) {
      await c.beginSignIn(_email.text);
    } else {
      await c.beginLink(_email.text);
    }
    _afterSend();
  }

  Future<void> _sendPhone() async {
    final e164 = _e164;
    if (e164 == null) return;
    final c = ref.read(pwaAuthProvider.notifier);
    if (_signInMode) {
      await c.beginPhoneSignIn(e164);
    } else {
      await c.beginPhoneLink(e164);
    }
    _afterSend();
  }

  void _afterSend() {
    if (!mounted) return;
    if (ref.read(pwaAuthProvider).stage == PwaAuthStage.awaitingCode) {
      _code.clear();
      _startCooldown();
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0) return;
    final s = ref.read(pwaAuthProvider);
    await ref.read(pwaAuthProvider.notifier).resend(s.destination);
    if (!mounted) return;
    if (ref.read(pwaAuthProvider).failure == null) _startCooldown();
  }

  Future<void> _facebook() =>
      ref.read(pwaAuthProvider.notifier).startFacebook(signIn: _signInMode);

  /// The person was told the identity belongs to an existing account and
  /// CHOSE to sign in to it. The only place the journey flips — by their hand.
  Future<void> _continueToExisting() async {
    final s = ref.read(pwaAuthProvider);
    final c = ref.read(pwaAuthProvider.notifier);
    setState(() => _signInMode = true);
    switch (s.method) {
      case PwaAuthMethod.email:
        await c.beginSignIn(s.destination.isNotEmpty ? s.destination : _email.text);
        _afterSend();
      case PwaAuthMethod.phone:
        await c.beginPhoneSignIn(s.destination);
        _afterSend();
      case PwaAuthMethod.facebook:
        await c.startFacebook(signIn: true);
    }
  }

  /// Verify the code, and — only if it worked — make the app be this account.
  Future<void> _verifyAndSettle() async {
    final auth = ref.read(pwaAuthProvider.notifier);
    final destination = ref.read(pwaAuthProvider).destination;
    await auth.submitCode(destination, _code.text);
    if (!mounted) return;
    final s = ref.read(pwaAuthProvider);
    if (s.stage != PwaAuthStage.identified) return; // refused, or mismatch
    await _settleAfter(s);
  }

  Future<void> _settleAfter(PwaAuthState s) async {
    if (!mounted || _settling) return;
    setState(() => _settling = true);
    await pwaHydrateForIdentity(ref, switchedUser: s.switchedAccount);
    if (!mounted) return;
    // Authentication has succeeded and everything it changes has settled.
    // There is nothing left to ask, so nothing is asked.
    Navigator.of(context).pop(true);
  }

  void _chooseAnother() {
    ref.read(pwaAuthProvider.notifier).cancel();
    _code.clear();
    setState(() => _method =
        ref.read(pwaAuthProvider.notifier).providers.hasPrimaryChoice
            ? null
            : PwaAuthMethod.email);
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
    } else if (!_ready) {
      body = const SizedBox(height: 120);
    } else if (_settling ||
        (_oauthShown &&
            auth.stage == PwaAuthStage.identified &&
            auth.failure == null)) {
      // SUCCESS — nothing to decide. Which promise is honest depends on a
      // MEASURED fact: the same user_id means the work came along, a
      // different one means it did not.
      body = _Settling(
        title: auth.switchedAccount
            ? l.accountSwitchedTitle
            : l.accountLinkedTitle,
        body: auth.switchedAccount ? l.accountSwitchedBody : l.accountLinkedBody,
        footnote: auth.identityLabel.isEmpty
            ? null
            : l.accountSignedInAs(auth.identityLabel),
      );
    } else if (auth.failure ==
        PwaVerificationFailure.destinationAlreadyRegistered) {
      // A fork, not an error. Nothing happens until the person picks.
      body = _Message(
        title: l.authWelcomeBack,
        body: l.authExistsFor(auth.method),
        note: l.accountExistsBody,
        primary: l.authContinueExisting,
        primaryKey: const ValueKey('pwa-auth-continue-existing'),
        busy: auth.busy,
        onPrimary: _continueToExisting,
        secondary: switch (auth.method) {
          PwaAuthMethod.email => l.accountChangeEmail,
          PwaAuthMethod.phone => l.authChangePhone,
          PwaAuthMethod.facebook => l.authChooseAnother,
        },
        onSecondary: () {
          setState(() => _signInMode = false);
          _chooseAnother();
          if (auth.method != PwaAuthMethod.facebook) {
            setState(() => _method = auth.method);
          }
        },
      );
    } else if (auth.stage == PwaAuthStage.awaitingCode) {
      body = _CodeStep(
        controller: _code,
        method: auth.method,
        destination: auth.destination,
        busy: auth.busy,
        failure: auth.failure,
        cooldown: _cooldown,
        onVerify: _settling ? null : _verifyAndSettle,
        onResend: _resend,
        onBack: () {
          _code.clear();
          controller.cancel();
          if (auth.method == PwaAuthMethod.email) {
            setState(() => _method = PwaAuthMethod.email);
          } else {
            setState(() => _method = PwaAuthMethod.phone);
          }
        },
      );
    } else if (_method == PwaAuthMethod.phone) {
      body = _PhoneStep(
        dial: _dial,
        phone: _phone,
        signInMode: _signInMode,
        busy: auth.busy,
        failure: auth.method == PwaAuthMethod.phone ? auth.failure : null,
        canSubmit: _e164 != null,
        onChanged: () => setState(() {}),
        onSubmit: _sendPhone,
        onBack: controller.providers.hasPrimaryChoice ? _chooseAnother : null,
      );
    } else if (_method == PwaAuthMethod.email) {
      body = _EmailStep(
        controller: _email,
        signInMode: _signInMode,
        busy: auth.busy,
        failure: auth.method == PwaAuthMethod.email ? auth.failure : null,
        canSubmit: controller.looksValid(_email.text),
        onChanged: () => setState(() {}),
        onSubmit: _sendEmail,
        onToggleMode: () {
          setState(() => _signInMode = !_signInMode);
          controller.cancel();
        },
        onBack: controller.providers.hasPrimaryChoice ? _chooseAnother : null,
      );
    } else {
      // The chooser. A Facebook outcome that was not a success (cancelled,
      // no email, provider off) is shown here, under the doors, once.
      body = _Chooser(
        signInMode: _signInMode,
        busy: auth.busy,
        facebook: controller.canFacebook,
        phone: controller.canPhone,
        leaving: auth.busy && auth.method == PwaAuthMethod.facebook,
        failure: (_oauthShown || auth.method == PwaAuthMethod.facebook)
            ? auth.failure
            : null,
        onFacebook: _facebook,
        onPhone: () => setState(() => _method = PwaAuthMethod.phone),
        onEmail: () => setState(() => _method = PwaAuthMethod.email),
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

// ── Step 0: the chooser ──────────────────────────────────────────────────────

class _Chooser extends StatelessWidget {
  const _Chooser({
    required this.signInMode,
    required this.busy,
    required this.facebook,
    required this.phone,
    required this.leaving,
    required this.failure,
    required this.onFacebook,
    required this.onPhone,
    required this.onEmail,
    required this.onToggleMode,
  });

  final bool signInMode;
  final bool busy;
  final bool facebook;
  final bool phone;
  final bool leaving;
  final PwaVerificationFailure? failure;
  final VoidCallback onFacebook;
  final VoidCallback onPhone;
  final VoidCallback onEmail;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(signInMode ? l.accountSignInTitle : l.authSecureTitle,
            style: pwaSerif(fontSize: 24, fontWeight: FontWeight.w500)),
        const SizedBox(height: PwaGap.sm),
        Text(signInMode ? l.authSignInChooserBody : l.authSecureBody,
            style: pwaSans(fontSize: 14, color: pwaMuted, height: 1.5)),
        const SizedBox(height: PwaGap.lg),
        if (facebook) ...[
          _PrimaryButton(
            key: const ValueKey('pwa-auth-facebook'),
            label: l.authContinueFacebook,
            icon: Icons.facebook,
            busy: leaving,
            onPressed: busy ? null : onFacebook,
          ),
          if (leaving) ...[
            const SizedBox(height: PwaGap.xs),
            // The page is about to navigate away. Said in words, under the
            // spinner, so a slow redirect does not look like a hang.
            Text(l.authFacebookLeaving,
                textAlign: TextAlign.center,
                style: pwaSans(fontSize: 12, color: pwaFaint)),
          ],
          const SizedBox(height: PwaGap.sm),
        ],
        if (phone)
          _OutlinedButton(
            key: const ValueKey('pwa-auth-phone'),
            label: l.authContinuePhone,
            icon: Icons.phone_iphone,
            onPressed: busy ? null : onPhone,
          ),
        if (failure != null &&
            failure != PwaVerificationFailure.destinationAlreadyRegistered)
          _FailureLine(failure!, method: PwaAuthMethod.facebook),
        const SizedBox(height: PwaGap.md),
        Row(
          children: [
            const Expanded(child: Divider(color: pwaHairline, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(l.authOr,
                  style: pwaSans(fontSize: 12, color: pwaFaint)),
            ),
            const Expanded(child: Divider(color: pwaHairline, height: 1)),
          ],
        ),
        const SizedBox(height: PwaGap.xs),
        TextButton(
          key: const ValueKey('pwa-auth-email'),
          onPressed: busy ? null : onEmail,
          child: Text(l.authUseEmail,
              style: pwaSans(
                  fontSize: 14, fontWeight: FontWeight.w600, color: pwaInk)),
        ),
        const SizedBox(height: PwaGap.xs),
        // The returning-user door, phrased as Profile phrases it: a question
        // and a verb — not "that account", which only makes sense after a
        // collision has named one.
        TextButton(
          onPressed: busy ? null : onToggleMode,
          child: Text(
            signInMode
                ? l.accountBackToLink
                : '${l.accountHaveOne} ${l.accountSignInTitle}',
            textAlign: TextAlign.center,
            style: pwaSans(fontSize: 13, color: pwaMuted),
          ),
        ),
      ],
    );
  }
}

// ── Step 1a: the email ───────────────────────────────────────────────────────

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
    required this.onBack,
  });

  final TextEditingController controller;
  final bool signInMode;
  final bool busy;
  final PwaVerificationFailure? failure;
  final bool canSubmit;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onToggleMode;

  /// Back to the chooser, when there is one.
  final VoidCallback? onBack;

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
          autofillHints: const [AutofillHints.email],
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
        if (onBack != null)
          TextButton(
            key: const ValueKey('pwa-auth-back'),
            onPressed: busy ? null : onBack,
            child: Text(l.authChooseAnother,
                style: pwaSans(fontSize: 13, color: pwaMuted)),
          )
        else
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

// ── Step 1b: the phone ───────────────────────────────────────────────────────

class _PhoneStep extends StatelessWidget {
  const _PhoneStep({
    required this.dial,
    required this.phone,
    required this.signInMode,
    required this.busy,
    required this.failure,
    required this.canSubmit,
    required this.onChanged,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController dial;
  final TextEditingController phone;
  final bool signInMode;
  final bool busy;
  final PwaVerificationFailure? failure;
  final bool canSubmit;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(signInMode ? l.accountSignInTitle : l.authPhoneTitle,
            style: pwaSerif(fontSize: 24, fontWeight: FontWeight.w500)),
        const SizedBox(height: PwaGap.sm),
        Text(signInMode ? l.authPhoneSignInBody : l.authPhoneBody,
            style: pwaSans(fontSize: 14, color: pwaMuted, height: 1.5)),
        const SizedBox(height: PwaGap.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The country. Cambodia by default; editable, so a person with
            // a Thai or French number types their own code — or types the
            // whole number with its `+`, which wins over this field.
            SizedBox(
              width: 96,
              child: TextField(
                key: const ValueKey('pwa-auth-dial'),
                controller: dial,
                onChanged: (_) => onChanged(),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[+0-9]')),
                  LengthLimitingTextInputFormatter(5),
                ],
                style: pwaSans(fontSize: 15),
                decoration: _fieldDecoration(l.authDialCodeLabel, '+855'),
              ),
            ),
            const SizedBox(width: PwaGap.sm),
            Expanded(
              child: TextField(
                key: const ValueKey('pwa-auth-phone-field'),
                controller: phone,
                onChanged: (_) => onChanged(),
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (canSubmit && !busy) onSubmit();
                },
                style: pwaSans(fontSize: 15),
                decoration:
                    _fieldDecoration(l.authPhoneLabel, l.authPhoneHint),
              ),
            ),
          ],
        ),
        if (failure != null) _FailureLine(failure!, method: PwaAuthMethod.phone),
        const SizedBox(height: PwaGap.lg),
        _PrimaryButton(
          label: l.authContinue,
          busy: busy,
          onPressed: canSubmit && !busy ? onSubmit : null,
        ),
        if (onBack != null) ...[
          const SizedBox(height: PwaGap.sm),
          TextButton(
            key: const ValueKey('pwa-auth-back'),
            onPressed: busy ? null : onBack,
            child: Text(l.authChooseAnother,
                style: pwaSans(fontSize: 13, color: pwaMuted)),
          ),
        ],
      ],
    );
  }
}

// ── Step 2: the code ─────────────────────────────────────────────────────────

class _CodeStep extends StatelessWidget {
  const _CodeStep({
    required this.controller,
    required this.method,
    required this.destination,
    required this.busy,
    required this.failure,
    required this.cooldown,
    required this.onVerify,
    required this.onResend,
    required this.onBack,
  });

  final TextEditingController controller;
  final PwaAuthMethod method;
  final String destination;
  final bool busy;
  final PwaVerificationFailure? failure;
  final int cooldown;

  /// Null while the account's own state is being read: authentication has
  /// already succeeded and re-submitting the code would mean nothing.
  final VoidCallback? onVerify;
  final VoidCallback onResend;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final isPhone = method == PwaAuthMethod.phone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.accountCodeTitle,
            style: pwaSerif(fontSize: 24, fontWeight: FontWeight.w500)),
        const SizedBox(height: PwaGap.sm),
        Text(
            isPhone
                ? l.authPhoneCodeBody(destination)
                : l.accountCodeBody(destination),
            style: pwaSans(fontSize: 14, color: pwaMuted, height: 1.5)),
        const SizedBox(height: PwaGap.lg),
        TextField(
          key: const ValueKey('pwa-auth-code'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          // Lets iOS and Android offer the code straight from the SMS.
          autofillHints: const [AutofillHints.oneTimeCode],
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
        if (failure != null) _FailureLine(failure!, method: method),
        const SizedBox(height: PwaGap.xs),
        Text(l.authCodeExpiry,
            style: pwaSans(fontSize: 12, color: pwaFaint)),
        const SizedBox(height: PwaGap.md),
        _PrimaryButton(
          label: l.accountVerify,
          busy: busy,
          onPressed: (busy || onVerify == null) ? null : onVerify,
        ),
        const SizedBox(height: PwaGap.xs),
        // Two short actions that both run long in French and Khmer ("Renvoyer
        // dans 42 s"): each takes half the width and wraps, never overflows.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextButton(
                key: const ValueKey('pwa-auth-back'),
                onPressed: busy ? null : onBack,
                child: Text(isPhone ? l.authChangePhone : l.accountChangeEmail,
                    textAlign: TextAlign.left,
                    style: pwaSans(fontSize: 13, color: pwaMuted)),
              ),
            ),
            Expanded(
              child: TextButton(
                key: const ValueKey('pwa-auth-resend'),
                onPressed: (busy || cooldown > 0) ? null : onResend,
                child: Text(
                    cooldown > 0 ? l.authResendIn(cooldown) : l.accountResend,
                    textAlign: TextAlign.right,
                    style: pwaSans(
                        fontSize: 13,
                        color: cooldown > 0 ? pwaFaint : pwaGold)),
              ),
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
    this.note,
    this.primary,
    this.primaryKey,
    this.onPrimary,
    this.secondary,
    this.onSecondary,
    this.busy = false,
  });

  final String title;
  final String body;

  /// A second, quieter paragraph — the rule that guest work stays put.
  final String? note;
  final String? primary;
  final Key? primaryKey;
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
        if (note != null) ...[
          const SizedBox(height: PwaGap.sm),
          Text(note!, style: pwaSans(fontSize: 13, color: pwaFaint, height: 1.5)),
        ],
        if (primary != null) ...[
          const SizedBox(height: PwaGap.lg),
          _PrimaryButton(
              key: primaryKey, label: primary!, busy: busy, onPressed: onPrimary),
        ],
        if (secondary != null) ...[
          const SizedBox(height: PwaGap.xs),
          TextButton(
            onPressed: busy ? null : onSecondary,
            child: Text(secondary!,
                style: pwaSans(fontSize: 13, color: pwaMuted)),
          ),
        ],
      ],
    );
  }
}

class _FailureLine extends StatelessWidget {
  const _FailureLine(this.failure, {this.method = PwaAuthMethod.email});

  final PwaVerificationFailure failure;
  final PwaAuthMethod method;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: PwaGap.sm),
        child: Text(
          context.pwaL10n.verificationFailure(failure, method: method),
          style: pwaSans(fontSize: 13, color: const Color(0xFFB4472E)),
        ),
      );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && onPressed != null;
    // The colour is passed EXPLICITLY and follows the ENABLED state, because
    // two things are true at once: `pwaSans` defaults to `pwaInk` and an
    // explicit TextStyle beats the button's `foregroundColor` — so omitting
    // it paints near-black on the black pill — while the DISABLED pill is a
    // pale grey on which light text vanishes just as badly.
    final fg = enabled ? pwaOnDark : pwaInk;
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
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 10),
                ],
                // Wraps rather than truncates: French and Khmer both run
                // long, and a clipped button label is a broken promise.
                Flexible(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: pwaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: fg)),
                ),
              ],
            ),
    );
  }
}

/// The second door. Same height and radius as the first, ink on ivory, so the
/// two read as ONE pair rather than a primary and an afterthought.
class _OutlinedButton extends StatelessWidget {
  const _OutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = enabled ? pwaInk : pwaFaint;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: pwaInk,
        backgroundColor: pwaIvory,
        side: const BorderSide(color: pwaHairline, width: 1.5),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PwaGap.radius),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(label,
                textAlign: TextAlign.center,
                style: pwaSans(
                    fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
          ),
        ],
      ),
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
