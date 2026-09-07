/// Web implementation: one call into a small bridge defined in `web/index.html`.
///
/// The bridge, not Dart, touches the DOM — it builds the hidden form through
/// the DOM API and sets `.value` on each input, so a field value containing
/// a quote cannot break out of an attribute, then calls `AbaPayway.checkout()`.
/// The plugin's own `checkout(data)` convenience builds its form by string
/// interpolation into HTML (`value='${data[key]}'`), which is why the official
/// sample's "pre-built form, then `checkout()` with no arguments" shape is the
/// one used here.
library;

import 'dart:convert';
import 'dart:js_interop';

import 'pwa_aba_plugin.dart';

@JS('aydenAbaCheckout')
external JSString? _aydenAbaCheckout(JSString formAction, JSString fieldsJson);

class _WebAbaPlugin implements PwaAbaPlugin {
  const _WebAbaPlugin();

  @override
  bool get isSupported => true;

  @override
  PwaAbaPluginLaunch launch({
    required String formAction,
    required Map<String, String> fields,
  }) {
    try {
      final result = _aydenAbaCheckout(
        formAction.toJS,
        jsonEncode(fields).toJS,
      );
      final code = result?.toDart ?? 'bridge-missing';
      return switch (code) {
        'ok' => PwaAbaPluginLaunch.launched,
        'plugin-missing' || 'bridge-missing' => PwaAbaPluginLaunch.pluginMissing,
        _ => PwaAbaPluginLaunch.failed,
      };
    } catch (_) {
      return PwaAbaPluginLaunch.failed;
    }
  }
}

PwaAbaPlugin createPlugin() => const _WebAbaPlugin();
