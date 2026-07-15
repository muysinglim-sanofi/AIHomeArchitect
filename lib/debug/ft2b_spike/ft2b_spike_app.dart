/// FT2-B spike — minimal app shell.
///
/// A bare MaterialApp hosting ONLY the spike screen. It does NOT mount the real
/// app's `App` widget, `meStatusProvider`, RevenueCat, billing, or any provider
/// scope — nothing that could touch the production flow or session.
library;

import 'package:flutter/material.dart';

import 'ft2b_spike_screen.dart';

class Ft2bSpikeApp extends StatelessWidget {
  const Ft2bSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'FT2-B Spike',
      debugShowCheckedModeBanner: false,
      home: Ft2bSpikeScreen(),
    );
  }
}
