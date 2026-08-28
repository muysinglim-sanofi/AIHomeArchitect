/// Batch 2 / 2.1 — the PWA entry widget.
///
/// Switches on the controller phase: a single continuous vertical ENTRY
/// experience (cinematic hero → upload showroom → Ayden Decide → Ayden Signature
/// → Generate) → loading → Ayden Architect. Additive and web-only; the mobile
/// route tree never reaches this widget.
///
/// It also owns the ONE place a generation failure is shown. A failed render is
/// a real event with a real cause, and the app says so here rather than
/// pretending on any individual screen — which is what makes "no fixture on
/// failure" a visible promise instead of an invisible one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../application/pwa_controller.dart';
import '../billing/pwa_entitlement_controller.dart';
import '../billing/pwa_payment.dart';
import '../billing/pwa_payment_controller.dart';
import 'pwa_payment_sheet.dart';
import 'pwa_paywall.dart';
import 'pwa_architect_screen.dart';
import 'pwa_create_ios.dart';
import 'pwa_design_session_screen.dart';
import 'pwa_home_ios.dart';
import 'pwa_profile_ios.dart';
import 'pwa_projects_ios.dart';
import 'pwa_first_reveal_screen.dart';
import 'pwa_reveal_screen.dart';
import 'pwa_theme.dart';
import 'pwa_type.dart';
import '../l10n/pwa_l10n.dart';

class PwaExperience extends ConsumerWidget {
  const PwaExperience({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(pwaControllerProvider.select((s) => s.phase));
    final screen = switch (phase) {
      // Phase 2 — the iOS-aligned Home. `PwaHomeScreen` (the dark original)
      // is retained, unreferenced, until the remaining screens migrate: it is
      // the fastest way back if this needs reverting, and the archive tag is
      // the slower one.
      PwaPhase.home => const PwaHomeIos(),
      // Phase 3 — the iOS-aligned Create. `PwaEntryScreen` (the dark original)
      // is retained, unreferenced, on the same terms as `PwaHomeScreen`: it
      // still owns the shared catalogue constants this screen imports, and it
      // is the fast way back if this needs reverting.
      PwaPhase.entry => const PwaCreateIos(),
      // Phase 4 — the wait is a SESSION, not a spinner. `PwaLoadingScreen` is
      // retained, unreferenced, on the same terms as the other two originals.
      PwaPhase.loading => const PwaDesignSessionScreen(),
      PwaPhase.architect => const PwaArchitectScreen(),
      PwaPhase.firstReveal => const PwaFirstRevealScreen(),
      PwaPhase.reveal => const PwaRevealScreen(),
      // Phase 7 — Projects on the product canvas. `PwaProjectsScreen` (the dark
      // original) is retained, unreferenced, on the same terms as the other
      // originals — and it still owns the project action menu this one calls.
      PwaPhase.projects => const PwaProjectsIos(),
      PwaPhase.profile => const PwaProfileIos(),
    };
    return Stack(
      children: [
        Positioned.fill(child: screen),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(child: _PwaGenerationErrorBar()),
        ),
        const _PwaBillingWatcher(),
        const _PwaPaymentReturnWatcher(),
      ],
    );
  }
}

/// Re-joins a payment the browser walked away from.
///
/// THE GAP THIS CLOSES
///
/// Paying replaces the page: `WebPwaExternalLauncher` assigns
/// `location.href` to PayWay's checkout, deliberately, because a custom scheme
/// opened in a new tab leaves an empty tab behind on mobile. So the tab that
/// started the purchase is gone, its poll is gone with it, and coming back is
/// a COLD BOOT. Nothing knew a payment had happened; the person landed on the
/// Hero, and the next refusal showed them the packs again — for something they
/// had already bought.
///
/// `PwaPaymentController.restore()` was written for exactly this and had no
/// caller in production. It asks the server — `GET /payments/open` — which
/// verifies the open attempt with PayWay before answering, so a payment made
/// while the browser was away is settled by the question itself.
///
/// WHAT IT WILL AND WILL NOT DO
///
/// It presents the outcome ONLY when money actually moved (`verified` or
/// `granted`). An abandoned attempt still sitting at `awaitingPayment` opens
/// nothing: someone who chose not to pay must not be met by a payment sheet on
/// every visit, which is the same mistake the replayed pending generation was
/// making. Nothing here writes payment state — the server is asked, and the
/// answer is shown.
class _PwaPaymentReturnWatcher extends ConsumerStatefulWidget {
  const _PwaPaymentReturnWatcher();

  @override
  ConsumerState<_PwaPaymentReturnWatcher> createState() =>
      _PwaPaymentReturnWatcherState();
}

class _PwaPaymentReturnWatcherState
    extends ConsumerState<_PwaPaymentReturnWatcher> {
  bool _asked = false;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _asked) return;
      _asked = true;
      // Fire-and-forget: a boot must not wait on it, and there is nothing to
      // do if it fails — the paywall still works and the entitlement read
      // still tells the truth about the balance.
      ref.read(pwaPaymentProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PwaPaymentState>(
      pwaPaymentProvider.select((p) => p.state),
      (_, next) {
        if (_shown) return;
        if (next != PwaPaymentState.verified &&
            next != PwaPaymentState.granted) {
          return;
        }
        _shown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          // The payment sheet already renders both of these states — the
          // spinner while the grant runs, then the success outcome with its
          // own two actions. Reusing it keeps one description of a payment in
          // the product rather than a second success screen that could drift.
          await showPwaPaymentReturn(context, ref);
          if (!mounted) return;
          // The balance changed. Ask, never assume by how much.
          await ref.read(pwaEntitlementProvider.notifier).refresh();
        });
      },
    );
    return const SizedBox.shrink();
  }
}

/// Turns billing EVENTS into the paywall, in one place.
///
/// It listens rather than renders (it occupies no space) because the paywall is
/// a response to something that happened — a refusal, a settled generation —
/// and every screen would otherwise have to remember to handle it. Two rules
/// live here and nowhere else:
///
///   * only a refusal the BILLING ENGINE issued opens the paywall. A timeout, an
///     unreachable backend or a failed upload must never look like a sale;
///   * a generation that SUCCEEDED spent a credit, so entitlement is re-read
///     from the server instead of decremented locally.
class _PwaBillingWatcher extends ConsumerStatefulWidget {
  const _PwaBillingWatcher();

  @override
  ConsumerState<_PwaBillingWatcher> createState() => _PwaBillingWatcherState();
}

class _PwaBillingWatcherState extends ConsumerState<_PwaBillingWatcher> {
  /// The refusal already shown. Without it, every rebuild while the state still
  /// carries a refusal would push a second sheet.
  String _shown = '';
  bool _wasGenerating = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(
      pwaControllerProvider.select((s) => s.billingRefusal),
      (_, refusal) {
        if (refusal.isEmpty) {
          _shown = '';
          return;
        }
        if (refusal == _shown) return;
        _shown = refusal;
        // After the frame: this fires from a state change, and pushing a route
        // during a build is how you get a "setState during build" crash.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showPwaPaywall(context, ref, refusal: refusal);
        });
      },
    );

    ref.listen<bool>(
      pwaControllerProvider.select((s) => s.generating),
      (_, generating) {
        final finished = _wasGenerating && !generating;
        _wasGenerating = generating;
        if (!finished) return;
        // Only a generation that produced something spent a credit; a failure
        // released its hold, and the server will say so on the next read.
        //
        // BOTH outcomes count as "did not produce": since Phase 9 a billing
        // refusal writes `billingRefusal` and deliberately leaves
        // `generationError` null, so testing the error field alone would have
        // read a refusal as a success.
        final s = ref.read(pwaControllerProvider);
        final failed = s.generationError != null || s.billingRefusal.isNotEmpty;
        if (!failed) {
          ref.read(pwaEntitlementProvider.notifier).onGenerationSettled();
        }
      },
    );

    return const SizedBox.shrink();
  }
}

/// The failure notice. Present only when the last generation failed, and gone
/// the moment a new one starts.
class _PwaGenerationErrorBar extends ConsumerWidget {
  const _PwaGenerationErrorBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = ref.watch(
      pwaControllerProvider.select((s) => s.generationError),
    );
    if (fallback == null) return const SizedBox.shrink();
    // A refusal for money is not an error banner. It has a whole sheet, opened
    // by `_PwaBillingWatcher`, and showing both would say the same thing twice —
    // once as a failure, which it is not.
    final billing = ref.watch(
      pwaControllerProvider.select((s) => s.billingRefusal),
    );
    if (billing.isNotEmpty) return const SizedBox.shrink();
    // The CODE is what is rendered; the English sentence the controller wrote
    // is the fallback for a code this build does not know. Translating here
    // rather than where the failure happened is what lets the banner follow a
    // language change that occurs while it is on screen.
    final code = ref.watch(
      pwaControllerProvider.select((s) => s.generationErrorCode),
    );
    final message = code == null || code.isEmpty
        ? fallback
        : context.pwaL10n.errorForCode(code);
    final retryable = ref.watch(
      pwaControllerProvider.select((s) => s.generationRetryable),
    );
    final busy = ref.watch(pwaControllerProvider.select((s) => s.generating));
    final controller = ref.read(pwaControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Material(
        key: const ValueKey('pwa-generation-error'),
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 20,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  // Phase 4 — the type role only. A failure message is body
                  // copy, and on iOS body copy is Inter; the serif here was a
                  // holdover from before the foundation existed. Every word,
                  // every code path, every retry semantic is untouched.
                  message,
                  style: PwaType.bodyMuted(color: pwaOnCanvas),
                ),
              ),
              if (retryable && !busy)
                TextButton(
                  key: const ValueKey('pwa-generation-retry'),
                  onPressed: controller.retryGeneration,
                  child: Text(context.pwaL10n.retry),
                ),
              IconButton(
                key: const ValueKey('pwa-generation-error-dismiss'),
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: context.pwaL10n.dismiss,
                onPressed: controller.clearGenerationError,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
