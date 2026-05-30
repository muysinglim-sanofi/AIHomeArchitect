/// Wave 5.17d — Premium subscription provider.
///
/// Exposes `RevenuecatService.instance.isPremium` as a reactive Riverpod
/// value. Widgets watch this provider to dim/lock free-tier-only cards
/// and refresh the moment a purchase completes (the paywall does not
/// itself rebuild upstream screens — the provider does).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/revenuecat_service.dart';

class PremiumNotifier extends StateNotifier<bool> {
  PremiumNotifier() : super(RevenuecatService.instance.isPremium) {
    _sub = RevenuecatService.instance.premiumStream.listen((v) => state = v);
  }

  late final StreamSubscription<bool> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final premiumProvider = StateNotifierProvider<PremiumNotifier, bool>(
  (ref) => PremiumNotifier(),
);
