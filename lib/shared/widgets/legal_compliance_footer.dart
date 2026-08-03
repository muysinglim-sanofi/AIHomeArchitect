/// App Store compliance (Apple Guideline 3.1.2) — shared legal footer shown
/// next to ANY subscription purchase CTA (the paywall AND the Premium Center
/// upgrade). Renders, in order:
///   • Privacy Policy + Terms of Use links (prominent, directly under the CTA
///     so a reviewer sees them the moment they reach the purchase button);
///   • the auto-renewable subscription disclosure text below.
///
/// PURE UI — no billing / RevenueCat / purchase logic. It only renders text and
/// opens two external URLs in the system browser. Colours are injected so the
/// same widget fits the dark paywall AND the themed Premium Center without
/// duplicating the logic or changing any other flow.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_localizations.dart';

/// Ayden Studio privacy policy (hosted on the official site).
const String kPrivacyPolicyUrl = 'https://aydenstudio.com/privacy';

/// Apple's standard EULA — used as our Terms of Use (no self-hosted terms page).
const String kTermsOfUseUrl =
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

class LegalComplianceFooter extends StatelessWidget {
  /// Colour of the disclosure paragraph (muted).
  final Color disclosureColor;

  /// Colour of the Privacy / Terms link labels (clearly legible).
  final Color linkColor;

  /// Colour of the underline under each link.
  final Color underlineColor;

  const LegalComplianceFooter({
    super.key,
    required this.disclosureColor,
    required this.linkColor,
    required this.underlineColor,
  });

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      /* best-effort : n'interrompt jamais le parcours */
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        // Links FIRST, prominent, directly under the CTA. Wrap (not Row) so the
        // longer FR/KM labels fold onto a second line instead of overflowing on
        // narrow devices.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _LegalLink(
              label: l10n.pwPrivacyPolicy,
              color: linkColor,
              underline: underlineColor,
              onTap: () => _open(kPrivacyPolicyUrl),
            ),
            _LegalLink(
              label: l10n.pwTermsOfUse,
              color: linkColor,
              underline: underlineColor,
              onTap: () => _open(kTermsOfUseUrl),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.pwLegalDisclosure,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: disclosureColor,
            fontSize: 10.5,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _LegalLink extends StatelessWidget {
  final String label;
  final Color color;
  final Color underline;
  final VoidCallback onTap;

  const _LegalLink({
    required this.label,
    required this.color,
    required this.underline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: color,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: underline,
            decorationThickness: 1.5,
          ),
        ),
      ),
    );
  }
}
