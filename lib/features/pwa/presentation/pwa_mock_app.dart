/// Batch 2.0.1 / 2.1 — self-contained OFFLINE root for Flutter Web +
/// AYDEN_ENV=mock.
///
/// Bypasses the shared `App` / `appRouter` (Supabase-coupled providers) and
/// uses the PWA's own offline theme — no google_fonts runtime fetch, no router,
/// no Supabase, no remote providers. main() runs this only when
/// `AppEnvironment.instance.skipsRemoteBootstrap` is true (web + mock); iOS /
/// Android and web staging keep the normal `App` root.
library;

import 'package:flutter/material.dart';

import 'pwa_experience.dart';
import 'pwa_theme.dart';

class PwaMockApp extends StatelessWidget {
  const PwaMockApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Batch 2.1 — guarantee no external font request in the offline mock.
    pwaDisableRemoteFonts();
    // Tranche 1.2 — guarantee no debug baseline/size overlays (the "yellow
    // lines"): none is set in source, this is a defensive hard-off.
    pwaHardenDebugPaints();
    return MaterialApp(
      // Browser tab title (§9/§11) — a constant "Ayden Studio". Flutter web's
      // runtime title overrides the HTML <title>, so it must match exactly.
      title: 'Ayden Studio',
      theme: pwaTheme(),
      debugShowCheckedModeBanner: false,
      home: const PwaExperience(),
    );
  }
}
