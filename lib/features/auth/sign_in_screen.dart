/// Wave 5.17a — Sign-In screen with continuation-feeling UX.
///
/// Shown ONLY when the user attempts Generation #2 while still anonymous
/// (see `chat_screen.dart` Gen #2 gate). The framing is deliberately
/// "save and continue", NOT "create account" — per product spec :
///
///   "Save your project and continue with your AI Architect."
///
/// On success, the existing anonymous user UUID is preserved (Decision 4 —
/// anonymous-upgrade flow via `auth.signInWithIdToken`). The user returns
/// to the chat with their project, messages, and Gen #1 image intact, and
/// the pending /generate call is resumed by the caller.
library;

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/feature_flags.dart';
import '../../data/services/auth_service.dart';
import '../../shared/widgets/app_button.dart';

class SignInScreen extends StatefulWidget {
  /// Optional override of the headline — useful when the screen is shown
  /// from a context other than the Gen #2 gate (e.g. profile screen
  /// "Sign back in" affordance). Defaults to the Gen #2 copy.
  final String? headline;
  final String? subhead;

  const SignInScreen({
    super.key,
    this.headline,
    this.subhead,
  });

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _auth = AuthService();
  bool _isAppleLoading = false;
  bool _isGoogleLoading = false;
  String? _errorMessage;

  bool get _platformIsiOS => !kIsWeb && Platform.isIOS;

  Future<void> _handleApple() async {
    if (_isAppleLoading || _isGoogleLoading) return;
    setState(() {
      _isAppleLoading = true;
      _errorMessage = null;
    });
    final result = await _auth.signInWithApple();
    if (!mounted) return;
    setState(() => _isAppleLoading = false);
    _handleResult(result);
  }

  Future<void> _handleGoogle() async {
    if (_isAppleLoading || _isGoogleLoading) return;
    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });
    final result = await _auth.signInWithGoogle();
    if (!mounted) return;
    setState(() => _isGoogleLoading = false);
    _handleResult(result);
  }

  void _handleResult(SignInResult result) {
    switch (result.outcome) {
      case SignInOutcome.success:
        // Return `true` so the caller knows to resume the pending action.
        // The caller (e.g. chat_screen Gen #2 gate) will then re-issue
        // the /generate call with the now-non-anonymous JWT.
        Navigator.of(context).pop(true);
        break;
      case SignInOutcome.cancelled:
        // Silently dismiss — no error, just no change.
        break;
      case SignInOutcome.failed:
        setState(() {
          _errorMessage = result.errorMessage
              ?? 'Sign-in could not complete. Please try again.';
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Apple goes first on iOS (most familiar there + App Store §5.1.1(v)),
    // Google goes first on Android. Both visible everywhere.
    final appleFirst = _platformIsiOS;

    final headlineText = widget.headline
        ?? 'Your first vision is ready.';
    final subheadText = widget.subhead
        ?? 'Save your project and continue exploring '
           'new ideas with your AI architect.';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Lightweight back affordance — preserves the principle that
              // sign-in is "continue your project", not a hard wall. User
              // can dismiss and remain anonymous (they keep Gen #1).
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textPrimary),
                  onPressed: () => Navigator.of(context).pop(false),
                  tooltip: 'Close',
                ),
              ),
              const Spacer(),
              // Headline
              Text(
                headlineText,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                subheadText,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              // Sign-in buttons. Order varies by platform (Apple first on
              // iOS, Google first on Android) but BOTH are shown — App
              // Store Guideline §5.1.1(v) requires Apple to be present
              // when any third-party login is offered.
              // Google is provider-gated (Unified Identity): QA-1 is Apple-only
              // so the Google button is HIDDEN and `signInWithGoogle` (which is
              // the only place a GoogleSignIn() is constructed) is never reached.
              if (appleFirst) ...[
                _AppleButton(
                  loading: _isAppleLoading,
                  onPressed: _handleApple,
                ),
                if (FeatureFlags.googleSignInEnabled) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _GoogleButton(
                    loading: _isGoogleLoading,
                    onPressed: _handleGoogle,
                  ),
                ],
              ] else ...[
                if (FeatureFlags.googleSignInEnabled) ...[
                  _GoogleButton(
                    loading: _isGoogleLoading,
                    onPressed: _handleGoogle,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                _AppleButton(
                  loading: _isAppleLoading,
                  onPressed: _handleApple,
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.red.shade700,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              // Privacy reassurance — keeps the upgrade feeling architectural
              // rather than transactional.
              Text(
                'We use sign-in only to save your projects across devices.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  const _AppleButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'Continue with Apple',
      onPressed: loading ? null : onPressed,
      variant: AppButtonVariant.dark,
      loading: loading,
      icon: Icons.apple,
      fullWidth: true,
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  const _GoogleButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'Continue with Google',
      onPressed: loading ? null : onPressed,
      variant: AppButtonVariant.secondary,
      loading: loading,
      fullWidth: true,
    );
  }
}
