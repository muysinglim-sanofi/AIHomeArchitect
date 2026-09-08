/// The website footer: "We accept" and ABA's official lockup, once per page.
///
/// ABA's merchant review (2026-09-08): "Please add We accept logo on your
/// Website footer." Before that the lockup rode the Profile label in the
/// bottom navigation; ABA asks for a footer, so it is a footer — the LAST
/// thing on each of the three tab pages, below the content, above the bar.
///
/// WHAT IT IS NOT. Not a strip between the page and the navigation (that
/// bolted-on banner was rejected in an earlier pass), not a pinned element
/// that steals height from Home's "New design session" button, not a link. It
/// scrolls with the page: on a 390 × 844 phone it sits below the fold and is
/// reached by scrolling; on a 1440 × 900 desktop it sits at the foot of the
/// viewport inside the page's bounded column.
///
/// The caption is needed and localised: ABA's lockup contains no words, only
/// the two tiles.
library;

import 'package:flutter/material.dart';

import '../l10n/pwa_l10n.dart';
import 'pwa_aba_marks.dart';
import 'pwa_theme.dart';

class PwaSiteFooter extends StatelessWidget {
  const PwaSiteFooter({super.key});

  /// The lockup's height. 72:20, so 16 px tall is 57.6 px wide — metadata,
  /// not a banner.
  static const double markHeight = 16;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    return Padding(
      key: const ValueKey('pwa-site-footer'),
      padding: const EdgeInsets.fromLTRB(
          PwaGap.page, PwaGap.lg, PwaGap.page, PwaGap.md),
      child: MergeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l.acceptWeAccept,
              key: const ValueKey('pwa-site-footer-caption'),
              style: pwaSans(fontSize: 11.5, color: pwaFaint),
            ),
            const SizedBox(width: 8),
            const PwaAcceptMark(height: markHeight),
          ],
        ),
      ),
    );
  }
}
