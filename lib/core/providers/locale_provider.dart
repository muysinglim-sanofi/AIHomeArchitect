import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 1 (multilingual plumbing) — the UI locale is now PERSISTED across cold
/// starts (it previously reset to English on every relaunch) and is the single
/// authoritative source for the conversational reply language sent to the
/// backend as `ui_locale`. It does NOT touch the generation pipeline — DNA /
/// preservation / prompts stay English-internal.
const String _kLocaleKey = 'ui_locale';
const Set<String> _kSupportedLanguageCodes = {'en', 'fr', 'km'};

class LocaleNotifier extends StateNotifier<Locale> {
  /// [deviceLocale] is the platform's own preferred language code, used ONLY
  /// when nothing has been chosen and persisted yet.
  ///
  /// Mobile passes nothing, so its resolution is unchanged and byte-identical:
  /// persisted choice, else English. The PWA passes the browser's language
  /// (`navigator.languages`), which gives the Web the hierarchy it needs —
  /// explicit choice > persisted choice > browser language > English — without
  /// a second provider, a second storage key or a second supported set. A
  /// visitor in Phnom Penh should not have to find a language menu to read the
  /// product in Khmer; an iOS user's language was already settled at install.
  LocaleNotifier({String? deviceLocale})
      : _deviceLocale = deviceLocale,
        super(const Locale('en')) {
    _load();
  }

  final String? _deviceLocale;

  Future<void> _load() async {
    String? code;
    try {
      code = (await SharedPreferences.getInstance()).getString(_kLocaleKey);
    } catch (_) {
      // Storage is unavailable — a browser with site data blocked, a private
      // window with a strict policy, or a widget test that never installed the
      // plugin. None of those is a reason to fail: the language simply falls
      // back to the device hint and then to English, and the next successful
      // write persists it. Reading a PREFERENCE must never be able to take the
      // app down.
      code = null;
    }
    if (code != null && _kSupportedLanguageCodes.contains(code)) {
      state = Locale(code);
      return;
    }
    // Nothing chosen yet. The platform's preference is a HINT, never a
    // decision: it is not persisted, so the first explicit pick still wins and
    // still becomes the durable answer.
    final device = _deviceLocale;
    if (device != null && _kSupportedLanguageCodes.contains(device)) {
      state = Locale(device);
    }
  }

  /// Set + persist the UI locale. Ignored for unsupported codes.
  Future<void> setLocale(Locale locale) async {
    if (!_kSupportedLanguageCodes.contains(locale.languageCode)) return;
    // The UI changes FIRST and unconditionally; persistence is best-effort.
    // A visitor who cannot write storage should still be able to read the
    // product in their language for the length of the session.
    state = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLocaleKey, locale.languageCode);
    } catch (_) {
      // Nothing to do: the choice holds for this session and is retried the
      // next time the person picks a language.
    }
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>(
  (ref) => LocaleNotifier(),
);
