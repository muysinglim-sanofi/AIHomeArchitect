/// The Profile's two informational sheets and its stat card — iOS's, on the
/// web's chrome.
///
/// Read from `features/profile/profile_screen.dart` (frozen):
///
///   `_StatsRow` / `_StatCard`   one card: the count of finished redesigns,
///                               headlineMedium over bodySmall, surface card.
///   `_HelpCenterSheet`          title + subtitle, four expandable `_FaqCard`s,
///                               then a boxed "Still need help?" with a mail
///                               address. iOS prints an address and nothing
///                               else; the web adds the one action that is
///                               real here — the published support page.
///   `_AboutSheet`               64-square mark, app name, version line,
///                               tagline, copyright — all already localized
///                               in EN / FR / KM under the shared `sp*` keys.
///
/// Every string below comes from the SHARED dictionary iOS uses
/// (`l.shared.*`), so the three languages are the phone's, not a retyping.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_external_links.dart';
import 'pwa_primitives.dart';
import 'pwa_theme.dart';
import 'pwa_type.dart';

const double _kSheetRadius = 24;

/// iOS's `_StatCard`: one number, one label.
class PwaStatCard extends StatelessWidget {
  const PwaStatCard({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(value, style: PwaType.screenTitle().copyWith(fontSize: 26)),
            const SizedBox(height: 2),
            Text(label, style: PwaType.caption()),
          ],
        ),
      );
}

Widget _handle() => Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

Future<void> _showSheet(BuildContext context, Widget sheet) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: pwaSurface,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(_kSheetRadius)),
      ),
      builder: (_) => sheet,
    );

// ── Help Center ─────────────────────────────────────────────────────────────

Future<void> showPwaHelpCenter(BuildContext context) =>
    _showSheet(context, const PwaHelpCenterSheet());

class PwaHelpCenterSheet extends ConsumerWidget {
  const PwaHelpCenterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.pwaL10n;
    final s = l.shared;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // iOS ships four FAQs. Three of them answer for the PHONE app and would
    // be false here: "What's included in Premium?" describes Weekly / Annual
    // App Store plans (the web sells Spaces packs); "Can I replace the source
    // photo?" points at the iOS source-photo strip and Design Direction
    // workspace; "Can I share?" promises a before/after sent to anyone and
    // saved to the gallery (the web shares text). Only the first is true of
    // both, so only the first is shown — an accurate short FAQ over a long
    // misleading one. Web-specific answers are product copy to be written and
    // translated, not invented here.
    final faqs = [
      (s.spFaq1Q, s.spFaq1A),
    ];
    return SingleChildScrollView(
      key: const ValueKey('pwa-profile-help-sheet'),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + safeBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _handle(),
          const SizedBox(height: 20),
          Text(s.helpCenter, style: PwaType.sectionTitle()),
          const SizedBox(height: 4),
          Text(s.spHelpSubtitle, style: PwaType.bodyMuted()),
          const SizedBox(height: 20),
          for (final (i, (q, a)) in faqs.indexed) ...[
            _FaqCard(key: ValueKey('pwa-faq-$i'), question: q, answer: a),
            if (i < faqs.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.mail_outline,
                    size: 28, color: AppColors.textSecondary),
                const SizedBox(height: 8),
                Text(s.spStillNeedHelp,
                    style: PwaType.body().copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(kPwaSupportEmail,
                    style: PwaType.bodyMuted(color: pwaGold)),
                const SizedBox(height: 12),
                // The one real action: the support page the product
                // publishes (`website/support`). Opens in a new tab; this
                // sheet, and the Profile under it, stay exactly as they are.
                PwaPrimaryButton(
                  key: const ValueKey('pwa-profile-contact-support'),
                  label: l.contactSupport,
                  icon: Icons.open_in_new,
                  onPressed: () => ref.read(pwaLinkOpenerProvider)(kPwaSupportUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS's `_FaqCard`: a question row that opens onto its answer.
class _FaqCard extends StatefulWidget {
  const _FaqCard({super.key, required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(widget.question,
                          style: PwaType.body()
                              .copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 8),
                  Text(widget.answer,
                      style: PwaType.bodyMuted().copyWith(height: 1.5)),
                ],
              ],
            ),
          ),
        ),
      );
}

// ── About ───────────────────────────────────────────────────────────────────

Future<void> showPwaAbout(BuildContext context) =>
    _showSheet(context, const PwaAboutSheet());

class PwaAboutSheet extends StatelessWidget {
  const PwaAboutSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final s = l.shared;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      key: const ValueKey('pwa-profile-about-sheet'),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 32 + safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          const SizedBox(height: 24),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.textPrimary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.architecture,
                color: AppColors.surface, size: 32),
          ),
          const SizedBox(height: 16),
          Text(s.appName, style: PwaType.sectionTitle()),
          const SizedBox(height: 4),
          Text(l.aboutVersion, style: PwaType.caption()),
          const SizedBox(height: 20),
          Text(
            s.spAboutTagline,
            textAlign: TextAlign.center,
            style: PwaType.bodyMuted().copyWith(height: 1.6),
          ),
          const SizedBox(height: 28),
          Text(s.spCopyright,
              textAlign: TextAlign.center,
              style: PwaType.caption().copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}
