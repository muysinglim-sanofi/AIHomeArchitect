import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/feature_flags.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/providers/locale_provider.dart';
import '../../core/providers/me_status_provider.dart';
import '../../core/providers/session_provider.dart';
import '../../data/services/status_service.dart';
import '../paywall/paywall_sheet.dart';
import '../../data/services/auth_service.dart';
import '../auth/sign_in_screen.dart';
import '../admin/admin_promo_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final currentLocale = ref.watch(localeProvider);
    final sessionCount = ref.watch(sessionProvider).length;
    final meStatus = ref.watch(meStatusProvider); // Sprint 1B — admin entry gate

    void show(Widget sheet) => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => sheet,
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.lg,
                  AppSpacing.pagePadding,
                  0,
                ),
                child: Text(l10n.profileTitle, style: Theme.of(context).textTheme.headlineLarge),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.pagePadding),
                child: _ProfileHeader(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  0,
                  AppSpacing.pagePadding,
                  AppSpacing.lg,
                ),
                child: _StatsRow(projectCount: sessionCount),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  0,
                  AppSpacing.pagePadding,
                  AppSpacing.lg,
                ),
                child: const _PremiumStatusCard(),
              ),
            ),
            _SectionHeader(label: l10n.settingsAccount),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
                child: _SettingsCard(
                  items: [
                    _SettingItem(
                      icon: Icons.person_outline,
                      label: l10n.editProfile,
                      onTap: () => show(const _EditProfileSheet()),
                    ),
                    _SettingItem(
                      icon: Icons.notifications_outlined,
                      label: l10n.notifications,
                      onTap: () => show(const _NotificationsSheet()),
                    ),
                    _SettingItem(
                      icon: Icons.lock_outline,
                      label: l10n.privacy,
                      onTap: () => show(const _PrivacySheet()),
                    ),
                    _SettingItem(
                      icon: Icons.language,
                      label: l10n.settingsLanguage,
                      onTap: () => showModalBottomSheet(
                        context: context,
                        backgroundColor: AppColors.surface,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                        builder: (_) => _LanguageSelectorSheet(
                          currentLocale: currentLocale,
                          onSelect: (locale) {
                            ref.read(localeProvider.notifier).setLocale(locale);
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
            _SectionHeader(label: l10n.settingsSupport),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
                child: _SettingsCard(
                  items: [
                    _SettingItem(
                      icon: Icons.help_outline,
                      label: l10n.helpCenter,
                      onTap: () => show(const _HelpCenterSheet()),
                    ),
                    _SettingItem(
                      icon: Icons.star_outline,
                      label: l10n.rateApp,
                      onTap: () => show(const _RateAppSheet()),
                    ),
                    _SettingItem(
                      icon: Icons.info_outline,
                      label: l10n.about,
                      onTap: () => show(const _AboutSheet()),
                    ),
                  ],
                ),
              ),
            ),
            // ── Sprint 1B — Admin section (visible ONLY if backend says admin;
            // the real gate is server-side is_admin_role on every endpoint) ──
            if (meStatus?.isAdmin == true) ...[
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              _SectionHeader(label: l10n.admTitle),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.pagePadding),
                  child: _SettingsCard(
                    items: [
                      _SettingItem(
                        icon: Icons.confirmation_number_outlined,
                        label: l10n.admPromoCodes,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const AdminPromoScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // ── Voluntary sign-in entry (Wave 5.17b, hidden in 5.17d) ─────
            // The funnel no longer requires sign-in (Decision Wave 5.17d).
            // Restore Purchases lives on the paywall sheet (D7). To
            // re-enable a sign-in entry here in a future wave, flip
            // FeatureFlags.signInEnabled — no other change required.
            if (FeatureFlags.signInEnabled && AuthService().isAnonymous) ...[
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
                  child: _SettingsCard(
                    items: [
                      _SettingItem(
                        icon: Icons.login,
                        label: 'Sign In',
                        onTap: () async {
                          final result = await Navigator.of(context).push<bool>(
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
                          if (result == true && context.mounted) {
                            context.go('/home');
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // ── Sign-out (Wave 5.17a, hidden in 5.17d) ────────────────────
            // With sign-in hidden, there is nothing to sign out of. Also
            // closes the quota-reset abuse path (sign-out → fresh anon
            // UUID → fresh free gens). To re-enable, flip the same flag.
            if (FeatureFlags.signInEnabled) ...[
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
                  child: _SettingsCard(
                    items: [
                      _SettingItem(
                        icon: Icons.logout,
                        label: l10n.signOut,
                        onTap: () async {
                          final auth = AuthService();
                          await auth.signOut();
                          try {
                            await auth.signInAnonymouslyIfNeeded();
                          } catch (_) {
                            // Best-effort — onboarding will retry on
                            // next launch via main.dart.
                          }
                          if (context.mounted) {
                            context.go('/onboarding');
                          }
                        },
                        destructive: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl)),
          ],
        ),
      ),
    );
  }
}

// ── Language selector sheet ───────────────────────────────────────────────────

class _LanguageSelectorSheet extends StatelessWidget {
  final Locale currentLocale;
  final ValueChanged<Locale> onSelect;
  const _LanguageSelectorSheet({required this.currentLocale, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHandle(),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.chooseLanguage, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              leading: const Text('🇬🇧', style: TextStyle(fontSize: 24)),
              title: Text(l10n.english),
              trailing: currentLocale.languageCode == 'en'
                  ? const Icon(Icons.check_rounded, color: AppColors.accent)
                  : null,
              onTap: () => onSelect(const Locale('en')),
            ),
            ListTile(
              leading: const Text('🇰🇭', style: TextStyle(fontSize: 24)),
              title: Text(l10n.khmer),
              trailing: currentLocale.languageCode == 'km'
                  ? const Icon(Icons.check_rounded, color: AppColors.accent)
                  : null,
              onTap: () => onSelect(const Locale('km')),
            ),
            ListTile(
              leading: const Text('🇫🇷', style: TextStyle(fontSize: 24)),
              title: Text(l10n.french),
              trailing: currentLocale.languageCode == 'fr'
                  ? const Icon(Icons.check_rounded, color: AppColors.accent)
                  : null,
              onTap: () => onSelect(const Locale('fr')),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edit profile sheet ────────────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet();

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: 'Alex Martin');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        20,
        AppSpacing.pagePadding,
        AppSpacing.xl + safeBottom + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _SheetHandle()),
          const SizedBox(height: 20),
          Text(
            context.l10n.editProfile,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Stack(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
                  child: const Center(
                    child: Text('A', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: AppColors.accentDark)),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    child: const Icon(Icons.edit, size: 12, color: AppColors.surface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            context.l10n.spDisplayName,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceVariant,
              hintText: context.l10n.spYourName,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.l10n.spEmail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'alex@example.com',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() => _saved = true);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: AppColors.surface,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(_saved ? context.l10n.spSaved : context.l10n.spSaveChanges,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.surface)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Notifications sheet ───────────────────────────────────────────────────────

class _NotificationsSheet extends StatefulWidget {
  const _NotificationsSheet();

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  bool _redesigns = true;
  bool _generated = true;
  bool _inspiration = false;
  bool _product = false;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.pagePadding, 20, AppSpacing.pagePadding, AppSpacing.xl + safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _SheetHandle()),
          const SizedBox(height: 20),
          Text(context.l10n.notifications, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(context.l10n.spNotifSubtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpacing.lg),
          _NotifToggle(
            icon: Icons.auto_awesome_outlined,
            title: context.l10n.spNotif1Title,
            subtitle: context.l10n.spNotif1Sub,
            value: _redesigns,
            onChanged: (v) => setState(() => _redesigns = v),
          ),
          _NotifToggle(
            icon: Icons.check_circle_outline,
            title: context.l10n.spNotif2Title,
            subtitle: context.l10n.spNotif2Sub,
            value: _generated,
            onChanged: (v) => setState(() => _generated = v),
          ),
          _NotifToggle(
            icon: Icons.wb_sunny_outlined,
            title: context.l10n.spNotif3Title,
            subtitle: context.l10n.spNotif3Sub,
            value: _inspiration,
            onChanged: (v) => setState(() => _inspiration = v),
          ),
          _NotifToggle(
            icon: Icons.campaign_outlined,
            title: context.l10n.spNotif4Title,
            subtitle: context.l10n.spNotif4Sub,
            value: _product,
            onChanged: (v) => setState(() => _product = v),
          ),
        ],
      ),
    );
  }
}

class _NotifToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _NotifToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.surfaceVariant, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.textPrimary,
          ),
        ],
      ),
    );
  }
}

// ── Privacy sheet ─────────────────────────────────────────────────────────────

class _PrivacySheet extends StatelessWidget {
  const _PrivacySheet();

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpacing.pagePadding, 20, AppSpacing.pagePadding, AppSpacing.xl + safeBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _SheetHandle()),
          const SizedBox(height: 20),
          Text(context.l10n.spPrivacyTitle, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(context.l10n.spPrivacySubtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpacing.xl),
          _PrivacySection(
            icon: Icons.photo_outlined,
            title: context.l10n.spPrivacy1Title,
            body: context.l10n.spPrivacy1Body,
          ),
          const SizedBox(height: AppSpacing.lg),
          _PrivacySection(
            icon: Icons.auto_awesome_outlined,
            title: context.l10n.spPrivacy2Title,
            body: context.l10n.spPrivacy2Body,
          ),
          const SizedBox(height: AppSpacing.lg),
          _PrivacySection(
            icon: Icons.tune_outlined,
            title: context.l10n.spPrivacy3Title,
            body: context.l10n.spPrivacy3Body,
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              context.l10n.spPrivacyComingSoon,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.accentDark, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _PrivacySection({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: AppColors.surfaceVariant, shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(body, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.6)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Help center sheet ─────────────────────────────────────────────────────────

class _HelpCenterSheet extends StatelessWidget {
  const _HelpCenterSheet();

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpacing.pagePadding, 20, AppSpacing.pagePadding, AppSpacing.xl + safeBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _SheetHandle()),
          const SizedBox(height: 20),
          Text(context.l10n.helpCenter, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(context.l10n.spHelpSubtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpacing.lg),
          _FaqCard(
            question: context.l10n.spFaq1Q,
            answer: context.l10n.spFaq1A,
          ),
          const SizedBox(height: AppSpacing.sm),
          _FaqCard(
            question: context.l10n.spFaq2Q,
            answer: context.l10n.spFaq2A,
          ),
          const SizedBox(height: AppSpacing.sm),
          _FaqCard(
            question: context.l10n.spFaq3Q,
            answer: context.l10n.spFaq3A,
          ),
          const SizedBox(height: AppSpacing.sm),
          _FaqCard(
            question: context.l10n.spFaq4Q,
            answer: context.l10n.spFaq4A,
          ),
          const SizedBox(height: AppSpacing.xl),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.mail_outline, size: 28, color: AppColors.textSecondary),
                const SizedBox(height: 8),
                Text(context.l10n.spStillNeedHelp, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('support@aihomearchitect.com', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqCard extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqCard({required this.question, required this.answer});

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _expanded ? AppColors.textPrimary.withAlpha(60) : AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.question, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.textTertiary),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Text(widget.answer, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.6)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Rate app sheet ────────────────────────────────────────────────────────────

class _RateAppSheet extends StatefulWidget {
  const _RateAppSheet();

  @override
  State<_RateAppSheet> createState() => _RateAppSheetState();
}

class _RateAppSheetState extends State<_RateAppSheet> {
  int _stars = 0;
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.pagePadding, 20, AppSpacing.pagePadding, AppSpacing.xl + safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHandle(),
          const SizedBox(height: 24),
          if (!_submitted) ...[
            const Icon(Icons.auto_awesome, size: 36, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              context.l10n.spRateTitle,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.spRateSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < _stars;
                return GestureDetector(
                  onTap: () => setState(() => _stars = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 44,
                      color: filled ? const Color(0xFFF59E0B) : AppColors.border,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _stars > 0 ? () => setState(() => _submitted = true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  foregroundColor: AppColors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  disabledBackgroundColor: AppColors.border,
                ),
                child: Text(context.l10n.spSubmit, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.surface)),
              ),
            ),
          ] else ...[
            const Icon(Icons.favorite, size: 36, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(context.l10n.spThankYou, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              context.l10n.spThankYouSub,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.spClose, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── About sheet ───────────────────────────────────────────────────────────────

class _AboutSheet extends StatelessWidget {
  const _AboutSheet();

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.pagePadding, 20, AppSpacing.pagePadding, AppSpacing.xl + safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHandle(),
          const SizedBox(height: 24),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.architecture, color: AppColors.surface, size: 32),
          ),
          const SizedBox(height: 16),
          Text(context.l10n.appName, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(context.l10n.spAboutVersion, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpacing.lg),
          Text(
            context.l10n.spAboutTagline,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            context.l10n.spCopyright,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ── Section header sliver ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: AppColors.textTertiary,
              ),
        ),
      ),
    );
  }
}

// ── Profile header ────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
          child: const Center(
            child: Text('A', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: AppColors.accentDark)),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Alex Martin', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text('alex@example.com', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ],
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

// Sprint 1 — additive premium/quota status card. Reads the backend snapshot
// (GET /me/status via meStatusProvider). Renders nothing until the first
// successful fetch (graceful: a status error never shows a broken card).
class _PremiumStatusCard extends ConsumerStatefulWidget {
  const _PremiumStatusCard();

  @override
  ConsumerState<_PremiumStatusCard> createState() => _PremiumStatusCardState();
}

class _PremiumStatusCardState extends ConsumerState<_PremiumStatusCard> {
  @override
  void initState() {
    super.initState();
    // Refresh on open so the quota reflects generations done since boot
    // (the provider otherwise only refetches on auth / premium signals).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(meStatusProvider.notifier).refresh();
    });
  }

  Future<void> _openPaywall(PaywallTrigger trigger) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PaywallSheet(trigger: trigger),
    );
    // Returning from the paywall may have flipped premium — refresh the card.
    if (mounted) ref.read(meStatusProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final MeStatus? status = ref.watch(meStatusProvider);
    if (status == null) return const SizedBox.shrink();

    final bool premium = status.isPremium;
    // Sprint 1B — promo is shown ONLY when not premium (premium/admin priority).
    final bool promo = status.hasActivePromo;
    final bool entitled = premium || promo;  // has access → nothing to upsell
    final Color accent =
        entitled ? AppColors.accent : AppColors.textSecondary;
    final l10n = context.l10n;
    final IconData icon = premium
        ? Icons.workspace_premium
        : (promo ? Icons.redeem : Icons.bolt_outlined);

    final String title;
    final String subtitle;
    if (status.isAdmin) {
      title = l10n.stAdminFullAccess;
      subtitle = l10n.stUnlimited;
    } else if (premium) {
      title = l10n.stPremiumActive;
      subtitle = l10n.stUnlimited;
    } else if (promo && status.promoUnlimitedActive) {
      title = l10n.promoAccessUnlimited;
      subtitle = status.activePromoCampaign ?? l10n.stUnlimited;
    } else if (promo) {
      title = l10n.promoAccessLabel;
      subtitle = l10n.promoAccessLimited(status.promoGenerationsRemaining);
    } else {
      title = l10n.stFreePlan;
      subtitle = l10n.freeGenerationsLeft(status.remaining);
    }

    // Free users tap the card to open the paywall (upgrade) — quota trigger
    // when exhausted, generic otherwise. Entitled users (premium/promo) have
    // nothing to upsell.
    final VoidCallback? onTap = entitled
        ? null
        : () => _openPaywall(
              status.remaining <= 0
                  ? PaywallTrigger.quota
                  : PaywallTrigger.locked,
            );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: entitled
                  ? AppColors.accent.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          if (entitled)
            const Icon(Icons.verified, color: AppColors.accent, size: 20)
          else
            const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 22),
        ],
      ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int projectCount;
  const _StatsRow({required this.projectCount});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Wave 5.17d.1 — the legacy 3-card stats row (Transformations /
    // Sessions / Shared) referenced the now-retired credit-pack model
    // ("5 sessions" was the default pack balance). With Premium replacing
    // credit packs, we keep only the two real stats : redesigns count
    // (projects) + shared count. No fake "credits" number.
    return Row(
      children: [
        _StatCard(value: '$projectCount', label: l10n.projectsCount),
        const SizedBox(width: AppSpacing.sm),
        _StatCard(value: '2', label: l10n.sharedCount),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ── Settings card ─────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final List<_SettingItem> items;
  const _SettingsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Column(
            children: [
              ListTile(
                leading: Icon(
                  item.icon,
                  color: item.destructive ? AppColors.error : AppColors.textSecondary,
                  size: 22,
                ),
                title: Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: item.destructive ? AppColors.error : AppColors.textPrimary,
                      ),
                ),
                trailing: item.destructive
                    ? null
                    : const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
                onTap: item.onTap,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              ),
              if (i < items.length - 1) const Divider(height: 1, indent: 54),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _SettingItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  const _SettingItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

// ── Shared handle ─────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
    );
  }
}
