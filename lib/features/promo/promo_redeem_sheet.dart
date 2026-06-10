/// Sprint 1B — promo redemption sheet (discreet, premium).
///
/// Code input → Apply → backend /promo/redeem (authoritative). On success it
/// refreshes /me/status so the UI reflects the new promo grant. Localised
/// EN/FR/KM. The backend decides everything; this only sends + renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/me_status_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/promo_service.dart';
import '../../shared/widgets/app_button.dart';

/// Opens the redeem sheet. Returns true if a code was successfully applied.
Future<bool?> showPromoRedeemSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _PromoRedeemSheet(),
  );
}

class _PromoRedeemSheet extends ConsumerStatefulWidget {
  const _PromoRedeemSheet();

  @override
  ConsumerState<_PromoRedeemSheet> createState() => _PromoRedeemSheetState();
}

class _PromoRedeemSheetState extends ConsumerState<_PromoRedeemSheet> {
  final _controller = TextEditingController();
  final _promo = PromoService();
  bool _busy = false;
  String? _error; // localized message
  PromoRedeemResult? _success;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _controller.text.trim();
    if (code.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await _promo.redeem(code);
    if (!mounted) return;
    if (result.ok) {
      // Backend granted it → refresh authoritative status before showing success.
      await ref.read(meStatusProvider.notifier).refresh();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _success = result;
      });
    } else {
      setState(() {
        _busy = false;
        _error = context.l10n.promoError(result.errorCode ?? 'invalid_code');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: 24 + media.viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (_success != null) _successView(l10n) else _inputView(l10n),
        ],
      ),
    );
  }

  Widget _inputView(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.promoRedeemTitle,
          style: AppTheme.displayEditorial(
              fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.promoRedeemSubtitle,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _apply(),
          style: const TextStyle(
              letterSpacing: 1.5, fontWeight: FontWeight.w600, fontSize: 16),
          decoration: InputDecoration(
            hintText: l10n.promoCodeHint,
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: _error != null ? AppColors.error : AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(color: AppColors.error, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 16),
        AppButton(
          label: l10n.promoApply,
          loading: _busy,
          onPressed: _busy ? null : _apply,
        ),
      ],
    );
  }

  Widget _successView(AppLocalizations l10n) {
    final r = _success!;
    final message = r.unlimited
        ? l10n.promoSuccessUnlimited
        : l10n.promoSuccessLimited(r.generationLimit ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        const Center(
          child: Icon(Icons.check_circle_rounded,
              color: AppColors.accent, size: 44),
        ),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTheme.displayEditorial(
              fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 22),
        AppButton(
          label: l10n.promoDone,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// Discreet "Have a promo code?" link — placed below Restore Purchase in the
/// paywall. Intentionally subtle so it never competes with the subscription CTAs.
class PromoCodeLink extends StatelessWidget {
  final Color? color;
  const PromoCodeLink({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () {
          HapticFeedback.selectionClick();
          showPromoRedeemSheet(context);
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          context.l10n.promoHaveCode,
          style: TextStyle(
            color: color ?? AppColors.textTertiary,
            fontSize: 12.5,
            decoration: TextDecoration.underline,
            decorationColor: color ?? AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
