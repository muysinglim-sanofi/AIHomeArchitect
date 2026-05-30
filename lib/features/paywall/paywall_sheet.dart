/// Wave 5.17b — Paywall sheet (placeholder).
///
/// Surfaced when the backend returns HTTP 402 QUOTA_EXHAUSTED — i.e. the
/// anonymous user has used all 3 free generations. The sheet's job in
/// Wave 5.17b is :
///
///   1. Present the locked premium-positioning copy (Decision Q5).
///   2. Offer a "Continue" path that opens the existing Wave 5.17a
///      SignInScreen — for users who already have a paid subscription
///      on another device and want to sign in to restore it.
///   3. Offer a "Maybe later" exit that dismisses the sheet.
///
/// In Wave 5.17c, this file will be replaced (or wrapped) by the real
/// RevenueCat paywall. The architecture here is intentionally minimal
/// so it can be discarded without ceremony.
///
/// NO subscription purchase, NO RevenueCat call, NO entitlement update
/// happens in this sheet for Wave 5.17b.
library;

import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../auth/sign_in_screen.dart';

class PaywallSheet extends StatelessWidget {
  const PaywallSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Decorative handle bar — consistent with other modal sheets.
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Headline — premium positioning, no aggressive sales language
            // (Decision Q5 final copy).
            Text(
              'Your free architectural explorations are complete.',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Unlock unlimited redesigns and continue working with '
              'your AI Architect.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),

            // Primary action — Wave 5.17b only opens the sign-in screen
            // (used for "restore an existing subscription on a new
            // device"). Wave 5.17c will replace this with the RevenueCat
            // purchase flow ; on successful purchase, the caller will
            // retry the /generate call that was blocked by the 402.
            AppButton(
              label: 'Continue',
              variant: AppButtonVariant.primary,
              fullWidth: true,
              onPressed: () async {
                final signedIn = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const SignInScreen(
                      headline: 'Continue with your AI architect',
                      subhead:
                          'Sign in to restore your subscription or '
                          'continue your design exploration.',
                    ),
                    fullscreenDialog: true,
                  ),
                );
                if (!context.mounted) return;
                // Wave 5.17b — sign-in alone does NOT unlock the quota.
                // The user's lifetime free count is preserved across
                // anon-upgrade, so they still hit the same paywall. The
                // sheet returns the sign-in outcome to its caller for
                // observability ; the caller may retry /generate but
                // will get the same 402 unless the user has an active
                // premium role. Wave 5.17c will add the purchase step.
                Navigator.of(context).pop(signedIn == true);
              },
            ),
            const SizedBox(height: AppSpacing.sm),

            // Secondary action — dismiss without subscribing.
            AppButton(
              label: 'Maybe later',
              variant: AppButtonVariant.ghost,
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
