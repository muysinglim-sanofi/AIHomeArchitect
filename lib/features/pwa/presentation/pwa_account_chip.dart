/// The account affordance in the top bar. Deliberately small, and deliberately
/// NOT a gate.
///
/// §8: account creation belongs at the paywall moment, not on Home or Create.
/// So this is an icon that opens a menu — never a wall, never a modal on
/// arrival, never a condition on uploading a photo or generating the free
/// vision. A person can use the whole product without touching it.
///
/// It exists anyway because two things need somewhere to live once someone HAS
/// an account: seeing which one they are in, and leaving it. Hiding those
/// behind the paywall would mean the only way to check your own identity is to
/// run out of credit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart' show pwaControllerProvider;
import '../auth/pwa_auth_controller.dart';
import '../auth/pwa_auth_service.dart';
import '../billing/pwa_entitlement_controller.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_account_sheet.dart';
import 'pwa_paywall.dart';
import 'pwa_theme.dart' show pwaGold, pwaMuted, pwaTextFallback;

class PwaAccountChip extends ConsumerWidget {
  const PwaAccountChip({super.key, this.onDark = false});

  /// The top bars are black; the sheets are ivory.
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    final auth = ref.watch(pwaAuthProvider);
    final controller = ref.read(pwaAuthProvider.notifier);
    if (!controller.isAvailable) return const SizedBox.shrink();

    final fg = onDark ? const Color(0xFFF4F1EC) : const Color(0xFF1C1917);
    final identified = auth.stage == PwaAuthStage.identified;
    // The account's own label — a name, an email, a MASKED phone. An account
    // with no email is still an account; it used to read as "Guest" here.
    final label = identified && auth.identityLabel.isNotEmpty
        ? l.accountSignedInAs(auth.identityLabel)
        : (identified ? l.accountLinkedTitle : l.accountGuestLabel);
    // Someone whose free vision is spent should be able to find that out — and
    // do something about it — without first uploading a photo and being turned
    // away. Offered in this menu, so it is available and never in the way (§8).
    final needsPurchase = ref.watch(
        pwaEntitlementProvider.select((e) => e.requiresPurchase));

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: PopupMenuButton<String>(
          key: const ValueKey('pwa-account-chip'),
          tooltip: '',
          position: PopupMenuPosition.under,
          onSelected: (choice) async {
            switch (choice) {
              case 'paywall':
                await showPwaPaywall(context, ref);
              case 'account':
                // A GUEST's door. An identified account never reaches the
                // sheet from here: the sheet is where an account is secured,
                // and offering "Continue with Facebook" to someone already
                // signed in with Facebook is the defect the phone found.
                if (identified) {
                  ref.read(pwaControllerProvider.notifier).openProfile();
                } else {
                  // The sheet owns the post-authentication hydration.
                  await showPwaAccountSheet(context);
                }
              case 'profile':
                ref.read(pwaControllerProvider.notifier).openProfile();
              case 'signin':
                // The RETURNING user, from the header. Same call Profile
                // makes, same separate journey underneath: sign-in switches
                // to an account that already exists and carries nothing over
                // from the guest. Nothing merges.
                await showPwaAccountSheet(context, signIn: true);
              case 'signout':
                // One helper for both doors: sign out, raise the anti-abuse
                // flag before anything can be generated, re-read identity,
                // then confirm the marker.
                await pwaSignOutAndSecureGuest(ref);
            }
          },
          itemBuilder: (context) => [
            if (needsPurchase)
              PopupMenuItem<String>(
                key: const ValueKey('pwa-account-paywall'),
                value: 'paywall',
                child: Text(
                  l.paywallTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamilyFallback: pwaTextFallback,
                  ),
                ),
              ),
            // THE IDENTITY, STATED — for an account that has one. The name
            // and how it is connected, exactly as Profile shows it, and
            // nothing to tap: it is a fact, not a door. It used to be a menu
            // item that opened the account sheet, which for a Facebook
            // account meant "Secure your Ayden account" and "Continue with
            // Facebook" — the phone review's defect, and a way to start a
            // second sign-in from inside the first.
            if (identified) ...[
              PopupMenuItem<String>(
                key: const ValueKey('pwa-account-identity'),
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      auth.identityLabel.isNotEmpty
                          ? auth.identityLabel
                          : l.accountLinkedTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1C1917),
                        fontFamilyFallback: pwaTextFallback,
                      ),
                    ),
                    if (auth.connectedVia != null)
                      Text(
                        l.authConnectedVia(auth.connectedVia!),
                        style: TextStyle(
                          fontSize: 12,
                          color: pwaMuted,
                          fontFamilyFallback: pwaTextFallback,
                        ),
                      ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                key: const ValueKey('pwa-account-profile'),
                value: 'profile',
                child: Text(
                  l.shared.profileTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamilyFallback: pwaTextFallback,
                  ),
                ),
              ),
            ],
            // A Guest sees the two things a Guest can do, and they are not
            // equals: saving the work in front of them is the primary act,
            // signing in to an account that already exists is the returning-
            // user door. One behaviour, two entries, as Profile has.
            if (!identified)
              PopupMenuItem<String>(
                key: const ValueKey('pwa-account-open'),
                value: 'account',
                child: Text(
                  l.accountTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamilyFallback: pwaTextFallback,
                  ),
                ),
              ),
            if (!identified)
              PopupMenuItem<String>(
                key: const ValueKey('pwa-account-signin'),
                value: 'signin',
                child: Text(
                  l.accountSignInTitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: pwaGold,
                    fontFamilyFallback: pwaTextFallback,
                  ),
                ),
              ),
            if (identified)
              PopupMenuItem<String>(
                key: const ValueKey('pwa-account-signout'),
                value: 'signout',
                child: Text(
                  l.accountSignOut,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamilyFallback: pwaTextFallback,
                  ),
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Icon(
              identified
                  ? Icons.account_circle_rounded
                  : Icons.account_circle_outlined,
              size: 20,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
