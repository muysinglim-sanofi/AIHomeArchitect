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
  LocaleNotifier() : super(const Locale('en')) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleKey);
    if (code != null && _kSupportedLanguageCodes.contains(code)) {
      state = Locale(code);
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
