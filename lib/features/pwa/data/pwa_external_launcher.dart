/// Leaving the app for somewhere else — an interface, so the widget tree never
/// imports `package:web`.
///
/// Same shape as [PwaUrlBridge]: the contract lives here (pure Dart, safe in
/// `flutter test`, which compiles for the VM), the browser implementation lives
/// in `pwa_web_navigation.dart`, and `main_pwa.dart` is the only file that wires
/// the two together.
///
/// Today it has exactly one caller: the ABA Mobile deeplink on the payment
/// sheet. That is deliberately a NAVIGATION and nothing else — no state is
/// written when it fires, and nothing is concluded when the person comes back.
/// A browser regaining focus is not evidence that a bank moved money; the poll
/// that was already running is what will find out.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class PwaExternalLauncher {
  /// Send the browser to [url]. May be an `https:` link or an app scheme such
  /// as `abamobile://`.
  ///
  /// Returns nothing on purpose: a browser cannot reliably tell whether a
  /// custom scheme was handled, and a Boolean here would be a guess the UI
  /// would then be tempted to branch on.
  void open(String url);

  /// Send the browser to [url] in a SEPARATE tab, leaving this one running.
  ///
  /// Distinct from [open] because the two have opposite correct behaviours.
  /// [open] carries an `abamobile://` scheme, where staying in the same tab is
  /// right — a custom scheme opened in a new tab strands an empty tab on every
  /// mobile browser. This carries ABA's `https` checkout, where staying in the
  /// same tab is a defect: it unloads the Flutter app, and the Wallet, the
  /// payment attempt and the poll that is waiting on it all die with it.
  void openNewTab(String url);
}

/// The default outside a browser (tests, the mock build): do nothing.
///
/// A no-op rather than a throw, because "there is no ABA Mobile here" is a
/// perfectly ordinary situation and a widget test that taps the button should
/// be exercising the button, not handling an exception.
class PwaNoopExternalLauncher implements PwaExternalLauncher {
  const PwaNoopExternalLauncher();

  @override
  void open(String url) {}

  @override
  void openNewTab(String url) {}
}

final pwaExternalLauncherProvider = Provider<PwaExternalLauncher>(
  (ref) => const PwaNoopExternalLauncher(),
);
