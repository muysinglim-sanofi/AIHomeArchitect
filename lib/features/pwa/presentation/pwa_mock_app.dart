/// Batch 2.0.1 / 2.1 — self-contained root for Flutter Web (mock AND staging).
///
/// Bypasses the shared `App` / `appRouter` (Supabase-coupled providers) and
/// uses the PWA's own offline theme — no google_fonts runtime fetch, no router,
/// no Supabase, no remote providers.
///
/// Localization (Phase B) is wired HERE and nowhere else. This is the single
/// `MaterialApp` of the web product, so it is the single place a locale can be
/// installed: `locale:` from the shared [localeProvider], `supportedLocales` and
/// the delegate from the MOBILE dictionary. Mounting the same
/// `AppLocalizations.delegate` mobile mounts is what makes `context.pwaL10n`
/// able to forward to approved wording instead of re-translating it.
///
/// It watches the provider, so changing the language rebuilds the whole tree
/// immediately — no reload, no navigation, and nothing else happens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/providers/locale_provider.dart';
import 'pwa_experience.dart';
import 'pwa_theme.dart';

class PwaMockApp extends ConsumerWidget {
  const PwaMockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Batch 2.1 — guarantee no external font request in the offline mock.
    pwaDisableRemoteFonts();
    // Tranche 1.2 — guarantee no debug baseline/size overlays (the "yellow
    // lines"): none is set in source, this is a defensive hard-off.
    pwaHardenDebugPaints();

    final locale = ref.watch(localeProvider);

    return MaterialApp(
      // Browser tab title (§9/§11) — a constant "Ayden Studio". Flutter web's
      // runtime title overrides the HTML <title>, so it must match exactly.
      // Deliberately NOT localized: it is the brand, and mobile keeps `appName`
      // as "AYDEN Studio" in all three dictionaries for the same reason.
      title: 'Ayden Studio',
      theme: pwaTheme(),
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const PwaExperience(),
    );
  }
}
