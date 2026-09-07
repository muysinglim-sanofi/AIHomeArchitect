/// The web's REAL destinations for the Profile's legal and support rows.
///
/// A row that looks actionable must go somewhere real. These are the two
/// pages the product actually publishes (`website/privacy`, `website/support`
/// in the repository; both answer 200 at aydenstudio.com). There is no Terms
/// page on the web — iOS's paywall links Apple's standard EULA, which is not a
/// web document — so no Terms row exists here rather than a dead one.
///
/// Opening is behind a provider so a test can observe the URL instead of
/// asking a headless browser to open a tab.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// `website/privacy/index.html` — "Privacy Policy — Ayden Studio".
final Uri kPwaPrivacyUrl = Uri.parse('https://aydenstudio.com/privacy');

/// `website/support/index.html` — "Support — Ayden Studio", carrying the
/// support address the product actually answers (support@aydenstudio.com).
final Uri kPwaSupportUrl = Uri.parse('https://aydenstudio.com/support');

/// The address printed on that page, shown as text beside the button so a
/// person who prefers their own mail client has it.
const String kPwaSupportEmail = 'support@aydenstudio.com';

typedef PwaLinkOpener = Future<bool> Function(Uri url);

/// Opens a link in a NEW tab, so the app — its session, its state, the
/// Profile the person was on — is exactly where they left it.
final pwaLinkOpenerProvider = Provider<PwaLinkOpener>(
  (ref) => (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);
