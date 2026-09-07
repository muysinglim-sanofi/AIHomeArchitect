/// Batch 3.4b — web-only History API + sessionStorage adapters.
///
/// Imported ONLY by `main_pwa` (the web entrypoint). It pulls in `package:web`
/// / `dart:js_interop`, so it must never be reached from the widget tree or the
/// mobile entrypoint (those compile for the VM in `flutter test`, where these
/// libraries are unavailable). Tests use the in-memory fakes instead.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../application/pwa_intro_gate.dart';
import '../application/pwa_url_bridge.dart';
import 'pwa_external_launcher.dart';

/// Real browser history bridge (pushState / replaceState / popstate).
class WebPwaUrlBridge implements PwaUrlBridge {
  JSFunction? _listener;

  @override
  Uri current() {
    final loc = web.window.location;
    return Uri.parse('${loc.pathname}${loc.search}');
  }

  @override
  void push(String location) =>
      web.window.history.pushState(null, '', location);

  @override
  void replace(String location) =>
      web.window.history.replaceState(null, '', location);

  @override
  void onPop(void Function(Uri) callback) {
    _listener = ((web.Event _) => callback(current())).toJS;
    web.window.addEventListener('popstate', _listener);
  }

  @override
  void dispose() {
    final l = _listener;
    if (l != null) {
      web.window.removeEventListener('popstate', l);
      _listener = null;
    }
  }
}

/// Real `window.sessionStorage` — survives F5, cleared when the tab closes, so
/// the cinematic plays once per tab session (§7).
class WebPwaSessionStore implements PwaSessionStore {
  @override
  String? read(String key) => web.window.sessionStorage.getItem(key);

  @override
  void write(String key, String value) =>
      web.window.sessionStorage.setItem(key, value);
}

/// Real navigation to somewhere outside the app — today, the ABA Mobile
/// deeplink from the payment sheet.
///
/// `location.href` rather than `window.open`: a custom scheme opened in a new
/// tab leaves an empty tab behind on every mobile browser, and mobile is where
/// this button exists at all. Assigning href hands the URL to the OS, which
/// either opens ABA Mobile or does nothing — and doing nothing is fine, because
/// the QR is still on screen underneath.
class WebPwaExternalLauncher implements PwaExternalLauncher {
  const WebPwaExternalLauncher();

  @override
  void open(String url) {
    if (url.isEmpty) return;
    web.window.location.href = url;
  }

  @override
  void openNewTab(String url) {
    if (url.isEmpty) return;
    // `noopener` severs `window.opener`, so ABA's page cannot reach back into
    // this one. Standard hygiene for any cross-origin link, and mandatory for
    // one that is about to ask somebody for money.
    web.window.open(url, '_blank', 'noopener,noreferrer');
  }
}
