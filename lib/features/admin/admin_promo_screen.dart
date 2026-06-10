/// Sprint 1B — in-app Admin promo panel (admin-only; backend-authoritative).
///
/// Generate codes, list them, enable/disable, copy. The frontend only renders +
/// calls the admin endpoints; every action is re-validated server-side by
/// is_admin_role. Reachable only from the admin entry in Profile (gated on
/// /me/status.is_admin) — but that gate is convenience, not security.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/promo_service.dart';
import '../../shared/widgets/app_button.dart';

class AdminPromoScreen extends ConsumerStatefulWidget {
  const AdminPromoScreen({super.key});

  @override
  ConsumerState<AdminPromoScreen> createState() => _AdminPromoScreenState();
}

class _AdminPromoScreenState extends ConsumerState<AdminPromoScreen> {
  final _promo = PromoService();
  final _codeCtrl = TextEditingController();
  final _genLimitCtrl = TextEditingController(text: '25');
  final _maxRedCtrl = TextEditingController();
  final _campaignCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _unlimited = false;
  DateTime? _expiresAt;
  bool _creating = false;
  String? _createError; // localized
  PromoCode? _justCreated;

  bool _loading = true;
  List<PromoCode> _codes = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _genLimitCtrl.dispose();
    _maxRedCtrl.dispose();
    _campaignCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final codes = await _promo.adminList();
    if (!mounted) return;
    setState(() {
      _codes = codes;
      _loading = false;
    });
  }

  Future<void> _create() async {
    if (_creating) return;
    final l10n = context.l10n;
    setState(() {
      _creating = true;
      _createError = null;
      _justCreated = null;
    });
    String? errCode;
    final created = await _promo.adminCreate(
      type: _unlimited ? 'unlimited' : 'limited_generations',
      code: _codeCtrl.text,
      generationLimit:
          _unlimited ? null : int.tryParse(_genLimitCtrl.text.trim()),
      maxRedemptions: int.tryParse(_maxRedCtrl.text.trim()),
      expiresAt: _expiresAt?.toUtc().toIso8601String(),
      campaign: _campaignCtrl.text,
      note: _noteCtrl.text,
      errorOut: (c) => errCode = c,
    );
    if (!mounted) return;
    if (created != null) {
      _codeCtrl.clear();
      setState(() {
        _creating = false;
        _justCreated = created;
      });
      await _refresh();
    } else {
      setState(() {
        _creating = false;
        _createError = errCode == 'code_conflict'
            ? l10n.admErrConflict
            : l10n.admErrCreate;
      });
    }
  }

  Future<void> _toggle(PromoCode c) async {
    final ok = await _promo.adminSetActive(c.id, !c.active);
    if (ok) await _refresh();
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.admCopied),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(l10n.admPromoCodes)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          children: [
            _buildForm(l10n),
            const SizedBox(height: AppSpacing.xl),
            Text(l10n.admCodesTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_codes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(l10n.admNoCodes,
                    style: const TextStyle(color: AppColors.textTertiary)),
              )
            else
              ..._codes.map((c) => _codeTile(l10n, c)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.admGenerateCode,
              style: AppTheme.displayEditorial(
                  fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          // type
          Row(
            children: [
              _typeChip(l10n.admTypeLimited, !_unlimited,
                  () => setState(() => _unlimited = false)),
              const SizedBox(width: 8),
              _typeChip(l10n.admTypeUnlimited, _unlimited,
                  () => setState(() => _unlimited = true)),
            ],
          ),
          const SizedBox(height: 12),
          if (!_unlimited)
            _numField(_genLimitCtrl, l10n.admGenerationLimit),
          _numField(_maxRedCtrl, '${l10n.admMaxRedemptions} (${l10n.admOptional})'),
          _textField(_codeCtrl, '${l10n.admCustomCode} (${l10n.admOptional})',
              hint: l10n.admCustomCodeHint),
          _textField(_campaignCtrl, '${l10n.admCampaign} (${l10n.admOptional})'),
          _textField(_noteCtrl, '${l10n.admNote} (${l10n.admOptional})'),
          // expiry
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _expiresAt == null
                        ? l10n.admExpiresNone
                        : '${l10n.admExpiresAt}: ${_expiresAt!.toLocal().toString().split(' ').first}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _expiresAt ?? now.add(const Duration(days: 30)),
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 3650)),
                    );
                    if (picked != null) setState(() => _expiresAt = picked);
                  },
                  child: Text(l10n.admExpiresAt),
                ),
                if (_expiresAt != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _expiresAt = null),
                  ),
              ],
            ),
          ),
          if (_createError != null) ...[
            const SizedBox(height: 4),
            Text(_createError!,
                style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
          ],
          if (_justCreated != null) ...[
            const SizedBox(height: 10),
            _createdBanner(l10n, _justCreated!),
          ],
          const SizedBox(height: 14),
          AppButton(
            label: l10n.admCreate,
            loading: _creating,
            onPressed: _creating ? null : _create,
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent.withValues(alpha: 0.14) : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? AppColors.accent : AppColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.accentDark : AppColors.textSecondary)),
        ),
      ),
    );
  }

  Widget _textField(TextEditingController c, String label, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }

  Widget _createdBanner(AppLocalizations l10n, PromoCode c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              c.code,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 1.5,
                  color: AppColors.accentDark),
            ),
          ),
          TextButton.icon(
            onPressed: () => _copy(c.code),
            icon: const Icon(Icons.copy, size: 16),
            label: Text(l10n.admCopy),
          ),
        ],
      ),
    );
  }

  Widget _codeTile(AppLocalizations l10n, PromoCode c) {
    final typeLabel = c.isUnlimited
        ? l10n.admUnlimited
        : '${c.generationLimit ?? 0} ${l10n.admGenerationLimit.toLowerCase()}';
    final redeemed = c.maxRedemptions == null
        ? '${l10n.admRedeemedLabel}: ${c.redeemedCount}'
        : '${l10n.admRedeemedLabel}: ${c.redeemedCount} / ${c.maxRedemptions}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: c.active ? AppColors.border : AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.code,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    letterSpacing: 1.0,
                    color: c.active
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                  ),
                ),
              ),
              _statusChip(l10n, c.active),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$typeLabel · $redeemed${c.campaign != null ? ' · ${c.campaign}' : ''}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _copy(c.code),
                icon: const Icon(Icons.copy, size: 15),
                label: Text(l10n.admCopy),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _toggle(c),
                child: Text(c.active ? l10n.admDisable : l10n.admEnable,
                    style: TextStyle(
                        color: c.active ? AppColors.error : AppColors.accentDark)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(AppLocalizations l10n, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active
            ? AppColors.accent.withValues(alpha: 0.14)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? l10n.admActive : l10n.admInactive,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: active ? AppColors.accentDark : AppColors.textTertiary,
        ),
      ),
    );
  }
}
