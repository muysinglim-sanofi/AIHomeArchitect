/// The language selector — one widget, present in every top bar.
///
/// Three properties it must have, and each is a real requirement rather than
/// polish:
///
///   * each language is written IN that language (ភាសាខ្មែរ / English /
///     Français). A menu that says "Khmer" in English is unreadable to the
///     person most likely to need it.
///   * choosing a language changes the UI immediately AND persists. It writes
///     through [LocaleNotifier], which stores `ui_locale` — the SAME key mobile
///     uses — so there is one preference, not a web copy of one.
///   * it is inert. Changing language rebuilds widgets and nothing else: no
///     generation is started, no project is written, no request leaves the
///     page. `pwa_i18n_test.dart` (I18N14/I18N15) pins that as a test rather
///     than a promise, because "the locale triggered a render" is exactly the
///     kind of bug that only shows up on the invoice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/locale_provider.dart';
import '../l10n/pwa_l10n.dart';

class PwaLanguageSwitcher extends ConsumerWidget {
  const PwaLanguageSwitcher({
    super.key,
    this.onDark = false,
    this.compact = false,
  });

  /// The top bars are black; the sheets are ivory.
  final bool onDark;

  /// Narrow viewports show the code only (KM / EN / FR).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final l = context.pwaL10n;
    final fg = onDark ? const Color(0xFFF4F1EC) : const Color(0xFF1C1917);

    return Semantics(
      button: true,
      label: l.languageLabel,
      child: Tooltip(
        message: l.languageLabel,
        child: PopupMenuButton<Locale>(
          key: const ValueKey('pwa-language-switcher'),
          tooltip: '',
          position: PopupMenuPosition.under,
          initialValue: locale,
          onSelected: (chosen) =>
              ref.read(localeProvider.notifier).setLocale(chosen),
          itemBuilder: (context) => [
            for (final candidate in kPwaLocaleOrder)
              PopupMenuItem<Locale>(
                key: ValueKey('pwa-language-${candidate.languageCode}'),
                value: candidate,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      child: candidate.languageCode == locale.languageCode
                          ? const Icon(Icons.check, size: 16)
                          : null,
                    ),
                    // Endonym first — the readable part — then the code, which
                    // is what a returning user scans for.
                    Flexible(
                      child: Text(
                        pwaLanguageEndonym(candidate.languageCode),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      candidate.languageCode.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFA8A29E),
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Container(
            height: 34,
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: onDark ? const Color(0x33D3B064) : const Color(0x22000000),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language_rounded, size: 16, color: fg),
                const SizedBox(width: 6),
                // The CODE, never the endonym, in the collapsed control: Khmer
                // script is tall and would push the 34px bar out of shape.
                Text(
                  locale.languageCode.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
