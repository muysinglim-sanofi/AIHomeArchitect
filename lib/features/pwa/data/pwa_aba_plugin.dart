/// Handing a signed purchase to ABA's own checkout plugin — an interface, so
/// the widget tree and the controller never import `dart:js_interop`.
///
/// THE SHAPE OF THE INTEGRATION, as ABA published it (2026-09-05)
/// --------------------------------------------------------------
/// The merchant page loads ABA's checkout plugin script (the include lives in
/// `web/index.html`; a guard keeps the gateway host out of `lib/` entirely),
/// holds a `<form method="POST" target="aba_webservice" id="aba_merchant_request">`
/// of hidden inputs carrying the SERVER-signed fields, and calls
/// `AbaPayway.checkout()`. The plugin creates an `<iframe name="aba_webservice">`
/// — a centred modal on desktop, a bottom sheet on a phone — and submits the
/// form into it. `target="aba_webservice"` is the form's target: it names the
/// plugin's iframe, so the purchase POST lands inside ABA's own popup rather
/// than navigating anywhere.
///
/// WHAT THIS LAYER DOES, AND ALL IT DOES
/// -------------------------------------
/// It relays two values from the server to that form: the action URL and the
/// fields, as an opaque map. It names no field. It reads no field. It signs
/// nothing — the api key never leaves the backend, and what arrives here is
/// the signature OUTPUT plus the identifiers ABA's own sample already puts in
/// hidden inputs. Whether money moved is learned exactly as before: the poll
/// asks our server, which asks Check Transaction. The plugin's callbacks are
/// not wired, because a payment surface that can be told "success" by page
/// JavaScript is a payment surface that can be lied to.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pwa_aba_plugin_stub.dart'
    if (dart.library.js_interop) 'pwa_aba_plugin_web.dart' as impl;

/// What happened when the plugin was asked to open.
///
/// This is a PRESENTATION result. None of these values says anything about the
/// payment; `launched` means ABA's popup was asked to appear, nothing more.
enum PwaAbaPluginLaunch {
  /// `AbaPayway.checkout()` was called.
  launched,

  /// ABA's script was not on the page (blocked, offline, or a non-web build).
  pluginMissing,

  /// The bridge threw. The message is logged, never shown as a payment state.
  failed,
}

abstract class PwaAbaPlugin {
  /// True where ABA's script can exist at all — the web build.
  bool get isSupported;

  /// Build the merchant form from [fields] and hand it to the plugin.
  ///
  /// [formAction] is PayWay's Purchase endpoint as the SERVER stated it;
  /// [fields] are the signed values, passed through untouched and unread.
  PwaAbaPluginLaunch launch({
    required String formAction,
    required Map<String, String> fields,
  });
}

/// Non-web default: nothing to launch. Tests and the mock build land here, and
/// so would the mobile app if it ever reached this code — it does not.
class PwaNoopAbaPlugin implements PwaAbaPlugin {
  const PwaNoopAbaPlugin();

  @override
  bool get isSupported => false;

  @override
  PwaAbaPluginLaunch launch({
    required String formAction,
    required Map<String, String> fields,
  }) => PwaAbaPluginLaunch.pluginMissing;
}

PwaAbaPlugin createPwaAbaPlugin() => impl.createPlugin();

/// Null by default — the controller then uses the server-side checkout path.
/// `main_pwa.dart` overrides it with the web plugin for staging and preprod.
final pwaAbaPluginProvider = Provider<PwaAbaPlugin?>((ref) => null);
