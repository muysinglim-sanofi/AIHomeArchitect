/// Phone numbers, the way the identity layer needs them: E.164 in, E.164 out.
///
/// Pure Dart, no Flutter, no network. Two jobs:
///
///   * [normalize] — what a person typed → `+85512345678`, or null. Cambodia
///     (+855) is the default country because that is where the product
///     launches, and a Cambodian types `012 345 678`, not `+855 12 345 678`.
///     An international number typed with its `+` (or `00`) prefix is kept as
///     is, so the default never overrides an explicit country.
///   * [mask] — `+85512345678` → `+855 •• ••• 5678`, for a profile that must
///     say WHICH number is attached without printing all of it.
///
/// The E.164 string is what goes to GoTrue and what GoTrue stores (it strips
/// the `+`; `formatPhoneNumber` in `internal/api/phone.go`). It is NOT the
/// account key — the Supabase user id is — which is why nothing here is ever
/// used to look a user up.
library;

class PwaPhoneNumber {
  const PwaPhoneNumber._();

  /// Cambodia. The launch market, and the only default this file has.
  static const String defaultDialCode = '+855';

  /// Dial codes the picker offers by name. Anything else is still accepted
  /// when typed in full with `+`; this list only decides what the chip shows.
  static const List<String> knownDialCodes = <String>[
    '+855', // Cambodia
    '+66', // Thailand
    '+84', // Vietnam
    '+856', // Laos
    '+60', // Malaysia
    '+65', // Singapore
    '+63', // Philippines
    '+62', // Indonesia
    '+86', // China
    '+82', // Korea
    '+81', // Japan
    '+61', // Australia
    '+33', // France
    '+44', // United Kingdom
    '+49', // Germany
    '+1', // USA / Canada
  ];

  /// Khmer digits (U+17E0–U+17E9) → Latin, so a Khmer keyboard works.
  static String _latinDigits(String s) {
    final buf = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x17E0 && r <= 0x17E9) {
        buf.writeCharCode(0x30 + (r - 0x17E0));
      } else {
        buf.writeCharCode(r);
      }
    }
    return buf.toString();
  }

  /// `+855` → `855`, or '' when the chip holds something that is not a code.
  static String _codeDigits(String dialCode) =>
      dialCode.replaceAll(RegExp(r'[^0-9]'), '');

  /// What a person typed → E.164, or null when it cannot be a phone number.
  ///
  /// [dialCode] applies ONLY when [raw] carries no country of its own. A
  /// leading trunk `0` is dropped in that case (`012 345 678` → `+85512345678`).
  static String? normalize(String raw, {String dialCode = defaultDialCode}) {
    var s = _latinDigits(raw.trim());
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (s.startsWith('00')) s = '+${s.substring(2)}';

    String digits;
    if (s.startsWith('+')) {
      digits = s.substring(1);
    } else {
      final cc = _codeDigits(dialCode);
      if (cc.isEmpty) return null;
      var local = s;
      if (local.startsWith('0')) local = local.substring(1);
      digits = cc + local;
    }
    // E.164: 8–15 digits, no leading zero. Fewer than 8 is not a phone number
    // anywhere the product ships; more than 15 is not E.164 at all.
    if (!RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(digits)) return null;
    return '+$digits';
  }

  /// Cheap shape check for a button's enabled state. The authority is GoTrue.
  static bool looksValid(String raw, {String dialCode = defaultDialCode}) =>
      normalize(raw, dialCode: dialCode) != null;

  /// The dial code an E.164 number carries, when it is one this file knows.
  /// Longest match wins (`+855` before `+8`), so `+855…` is never read as `+8`.
  static String? dialCodeOf(String e164) {
    if (!e164.startsWith('+')) return null;
    String? best;
    for (final code in knownDialCodes) {
      if (e164.startsWith(code) &&
          (best == null || code.length > best.length)) {
        best = code;
      }
    }
    return best;
  }

  /// `+85512345678` → `+855 •• ••• 5678`. The country stays readable, the last
  /// four digits identify the number to its owner, and the rest is hidden.
  ///
  /// The hidden part is a FIXED shape, not one dot per digit: a mask that
  /// counts the digits leaks the length, and "•• •••" is how a Cambodian
  /// number is read aloud whatever its length.
  static String mask(String e164) {
    final n = normalize(e164);
    if (n == null) return e164;
    final code = dialCodeOf(n) ?? '+${n.substring(1, 2)}';
    final rest = n.substring(code.length);
    if (rest.length <= 4) return '$code •• •••';
    final tail = rest.substring(rest.length - 4);
    return '$code •• ••• $tail';
  }
}
