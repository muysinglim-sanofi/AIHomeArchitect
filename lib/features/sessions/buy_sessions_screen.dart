import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/mock/mock_projects.dart';

class BuySessionsScreen extends StatefulWidget {
  const BuySessionsScreen({super.key});

  @override
  State<BuySessionsScreen> createState() => _BuySessionsScreenState();
}

class _BuySessionsScreenState extends State<BuySessionsScreen> with SingleTickerProviderStateMixin {
  String? _selectedId;

  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _selectedId = mockSessionPacks.firstWhere((p) => p.popular).id;
    _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = _selectedId != null
        ? mockSessionPacks.firstWhere((p) => p.id == _selectedId)
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.sessionsTitle),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pagePadding,
                    AppSpacing.pagePadding,
                    AppSpacing.pagePadding,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BalanceCard(),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        l10n.choosePlan,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.sessionsSubtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ...mockSessionPacks.asMap().entries.map((entry) {
                        final i = entry.key;
                        final pack = entry.value;
                        return AnimatedOpacity(
                          opacity: 1.0,
                          duration: Duration(milliseconds: 200 + i * 80),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _PackCard(
                              pack: pack,
                              selected: _selectedId == pack.id,
                              onTap: () => setState(() => _selectedId = pack.id),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.sm,
                  AppSpacing.pagePadding,
                  AppSpacing.md,
                ),
                child: _BuyButton(
                  selected: selected,
                  onTap: selected != null ? () => _showConfirm(context) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConfirm(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Payment flow coming soon!'),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

// ── Balance card ──────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.sessionsBalance,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.surface.withAlpha(140),
                      ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '5',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            color: AppColors.surface,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        l10n.sessionsAvailable,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.surface.withAlpha(160),
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.accent.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: AppColors.accent, size: 24),
          ),
        ],
      ),
    );
  }
}

// ── Pack card ─────────────────────────────────────────────────────────────────

class _PackCard extends StatelessWidget {
  final SessionPack pack;
  final bool selected;
  final VoidCallback onTap;
  const _PackCard({required this.pack, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? AppColors.accent.withAlpha(40) : AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 18,
                color: selected ? AppColors.accent : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          pack.label,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: selected ? AppColors.surface : AppColors.textPrimary,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (pack.popular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text(
                            l10n.bestValue,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.surface,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.transformationCount(pack.sessions),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: selected ? AppColors.accentLight : AppColors.textTertiary,
                        ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${pack.price.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: selected ? AppColors.surface : AppColors.textPrimary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '\$${(pack.price / pack.sessions).toStringAsFixed(2)}${l10n.perSession}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: selected ? AppColors.accentLight : AppColors.textTertiary,
                          fontSize: 10,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Buy button ────────────────────────────────────────────────────────────────

class _BuyButton extends StatelessWidget {
  final SessionPack? selected;
  final VoidCallback? onTap;
  const _BuyButton({this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: selected != null ? AppColors.textPrimary : AppColors.border,
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        ),
        child: Center(
          child: Text(
            selected != null
                ? l10n.unlockLabel(selected!.sessions, selected!.price)
                : l10n.selectPlan,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected != null ? AppColors.surface : AppColors.textTertiary,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
