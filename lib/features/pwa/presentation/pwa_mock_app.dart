/// Batch 2.0.1 — self-contained OFFLINE root for Flutter Web + AYDEN_ENV=mock.
///
/// Deliberately bypasses the shared `App` / `appRouter` (which build Supabase-
/// coupled providers and the notification host). This root has NO router, NO
/// Supabase, NO remote providers, NO API client — just the local, deterministic
/// PWA prototype. main() runs this ONLY when
/// `AppEnvironment.instance.skipsRemoteBootstrap` is true (web + mock); iOS /
/// Android and web staging keep the normal `App` root.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'pwa_experience.dart';

class PwaMockApp extends StatelessWidget {
  const PwaMockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AYDEN Studio',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const PwaExperience(),
    );
  }
}
