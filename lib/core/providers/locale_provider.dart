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
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleKey);
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
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, locale.languageCode);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>(
  (ref) => LocaleNotifier(),
);
