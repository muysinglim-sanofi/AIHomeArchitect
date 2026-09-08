/// Round 2 — the visual-parity corrections the real-phone review asked for.
///
/// Three of the four defects here were INVISIBLE to the existing suite because
/// every one of them is about how a surface LOOKS, and the suite only knew what
/// it did. These tests hold the look at the level a test can: which family a
/// style resolves to, which colours a surface is built from, and which
/// affordances a person is actually offered.
///
/// The fourth — the header identity menu — was a plain omission: Round 1 gave
/// Profile two doors and left the menu with one, and nothing said the two had
/// to agree. Now something does.
library;

import 'dart:io';

import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';

import 'package:ai_home_architect/features/pwa/presentation/pwa_paywall.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_reveal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── §2 — why the atmosphere card was set in the wrong face ────────────────
  //
  // The PWA reuses the FROZEN iOS `AtmosphereHeroCard`, which states its type
  // through `AppTheme.atmosphereTitle` → `GoogleFonts.cormorantGaramond(...)`.
  // On iOS that fetches and registers a per-variant family. On the web
  // `pwaDisableRemoteFonts()` forbids the fetch — deliberately — so the
  // primary family never exists; and `AppTheme` ends with
  // `.copyWith(fontFamilyFallback: khmerFallback)`, which REPLACES the
  // `[CormorantGaramond]` fallback google_fonts had put there. Both names the
  // renderer could have used were gone, and the card fell to sans-serif.
  //
  // The fix registers the bundled bytes under the names google_fonts asks for.
  // These tests pin the two halves of that: the names it asks for, and the
  // fact that the loader covers every one of them.
  group('FONT01  the reused iOS widgets resolve to the bundled faces', () {
    // These are SOURCE assertions, and deliberately so: calling
    // `GoogleFonts.cormorantGaramond(...)` with fetching disabled throws
    // asynchronously and the harness reports it before any expectation can
    // speak — which is itself the defect, seen from the inside. The names
    // below were MEASURED once, by running that call and printing what came
    // back (`CormorantGaramond_500` / `_regular`, fallback
    // `[CormorantGaramond]`); what is pinned here is that the pieces which
    // make those names resolve are all still in place.

    test('FONT01: the frozen iOS style still routes through google_fonts AND '
        'still overwrites its fallback', () {
      // The two halves of the root cause, in the frozen file. If iOS ever
      // stops doing either, the aliases stop being necessary — and this test
      // is where a reader finds out.
      final theme = File('lib/core/theme/app_theme.dart').readAsStringSync();
      final atmo = theme.substring(theme.indexOf('atmosphereTitle'));
      expect(atmo, contains('GoogleFonts.cormorantGaramond'),
          reason: 'the primary family is a per-variant google_fonts name');
      expect(atmo, contains('copyWith(fontFamilyFallback: khmerFallback)'),
          reason:
              'which REPLACES google_fonts own [CormorantGaramond] fallback — '
              'the one name the web loader registers');
    });

    test('FONT02: the web loader registers every variant name those styles '
        'can produce', () {
      // `pwa_fonts.dart` is web-only (`dart:js_interop`) and cannot be
      // imported into a VM test, so the contract is read from its source —
      // the same technique the deployment tests use for `firebase.json`.
      final src =
          File('lib/features/pwa/data/pwa_fonts.dart').readAsStringSync();
      final start = src.indexOf('_kVariantSuffixes');
      expect(start, greaterThan(0),
          reason: 'the alias list is what makes the reused widgets resolve');
      final list = src.substring(start, src.indexOf('];', start));

      // `GoogleFontsVariant.toString()` is weight followed by style, with w400
      // rendering as `regular`. Every pair the product's reused widgets can
      // ask for:
      for (final suffix in const [
        'regular', 'italic',
        '300', '300italic',
        '500', '500italic',
        '600', '600italic',
        '700', '700italic',
      ]) {
        expect(list, contains("'$suffix'"), reason: suffix);
      }
      // The two families every reused iOS widget draws from.
      expect(src, contains('CormorantGaramond-Latin.ttf'));
      expect(src, contains('Inter-Latin.ttf'));
    });

    test('FONT03: and the loader registers the plain family too', () {
      final src =
          File('lib/features/pwa/data/pwa_fonts.dart').readAsStringSync();
      // The product's own type (`PwaType`) asks for the bare name; the aliases
      // must be IN ADDITION to it, never instead of it.
      expect(src, contains('family,'));
      expect(src, contains(r"'${family}_$v'"));
    });
  });

  // ── §3 — the Full Reveal is a dark gallery ───────────────────────────────
  group('REVEAL12  the Full Reveal canvas is the native one', () {
    test('REVEAL12: the walnut is iOS\'s four colours, in order', () {
      // Read off the frozen `before_after_screen.dart`, which builds its
      // full-bleed canvas from exactly these stops.
      expect(kPwaRevealCanvas, const [
        Color(0xFF3F3220),
        Color(0xFF2F2519),
        Color(0xFF221C14),
        Color(0xFF181410),
      ]);
    });

    test('REVEAL13: no ambient blur backdrop repaints the render behind '
        'itself', () {
      // THE defect: the hero used to fill itself with a blurred copy of the
      // render "to turn the letterbox into the picture's own extended colour".
      // On a pale interior that is a pale wash covering the top half of the
      // screen — the flat taupe block the phone review saw, painted OVER the
      // walnut. iOS dropped the same thing in Wave 5.13b and says so.
      final src =
          File('lib/features/pwa/presentation/pwa_reveal_screen.dart')
              .readAsStringSync();
      expect(src, isNot(contains('ImageFiltered')),
          reason: 'the ambient halo is what made the screen read as taupe');
      expect(src, isNot(contains('kPwaRevealMatteBlur')));
      // …and the gradient that is supposed to be visible still is.
      expect(src, contains('kPwaRevealCanvas'));
    });

    test('REVEAL14: the render is TOP-anchored, so the light stop stays '
        'covered', () {
      // iOS anchors the render "to the very top" of the safe area. Expanding
      // the hero instead centred it and exposed #3F3220 — the gradient's
      // lightest end — as a wide band above the picture.
      final src =
          File('lib/features/pwa/presentation/pwa_reveal_screen.dart')
              .readAsStringSync();
      expect(src, contains('SizedBox(\n                          height: heroH'),
          reason: 'a fixed, top-anchored hero — not an Expanded one');
      // The strip and the slot stay FIXED, which is what keeps the rail
      // stable. Round 3 replaced the flat 132 with iOS's own chain — the
      // number is derived now, not declared, so this asserts the property
      // (a strip that does not depend on selection) at both form factors.
      expect(pwaRevealStripHeight(800, 390), pwaRevealStripHeight(800, 390));
      expect(pwaRevealStripHeight(800, 390), closeTo(270, 1),
          reason: 'a phone gets the native strip');
      expect(pwaRevealStripHeight(900, 1440), 132,
          reason: 'a wide window keeps the render, not the rail');
      expect(kPwaRevealSlotH, 104);
    });
  });

  // ── §1 — the paywall is the native surface, selling web products ─────────
  group('PAY20  the paywall is iOS\'s surface', () {
    test('PAY20: it is built from the native paywall\'s own palette', () {
      final src =
          File('lib/features/pwa/presentation/pwa_paywall.dart')
              .readAsStringSync();
      // Every one of these is copied from `features/paywall/paywall_sheet.dart`
      // rather than matched by eye. If the native file moves, these are the
      // values to re-read.
      for (final hex in const [
        '0xFF0E0C09', // _paywallBg
        '0xFFD6B25E', // _goldBright
        '0xFFE7CB82', // _goldLight
        '0xFFFFF3DC', // _champagne
        '0xFFC8B99B', // _planMuted
        '0xFFE2C06B', '0xFFC79B3A', '0xFFB8862C', // the CTA gradient
      ]) {
        expect(src, contains(hex), reason: hex);
      }
      // The immersive ground, and the three overlays that darken it.
      expect(src, contains('warm_modern.png'));
      expect(src, contains('ayden_logo_mixed.png'));
      expect(src, contains('_PwPaywallBackdrop'));
    });

    test('PAY21: the CTA is the gold one, and the ink pill is gone', () {
      final src = _code('lib/features/pwa/presentation/pwa_paywall.dart');
      expect(src, contains('class PwaGoldCta'));
      // `PwaPrimaryButton` is the product's cream-canvas pill. On this one
      // dark screen it was the "generic web pricing" look the review rejected.
      expect(src, isNot(contains('PwaPrimaryButton')));
      // And there is no second large action under Buy: identity is text.
      expect(src, isNot(contains('OutlinedButton')));
      expect(src, contains('_PwIdentityLine'));
    });

    test('PAY22: nothing from the App Store ladder can appear here', () {
      final src =
          _code('lib/features/pwa/presentation/pwa_paywall.dart').toLowerCase();
      for (final word in const [
        'revenuecat',
        'annual',
        'weekly',
        'unlimited',
        'subscription',
        'restorepurchases',
      ]) {
        expect(src, isNot(contains(word)), reason: word);
      }
      // What it DOES read is the server's own web-sellable list.
      expect(
          File('lib/features/pwa/presentation/pwa_paywall.dart')
              .readAsStringSync(),
          contains('purchasableOnWeb'));
    });

    testWidgets('PAY23: the gold CTA states its own label colour', (
      tester,
    ) async {
      // The bug this guards against has now appeared twice: a button whose
      // foreground is delivered as a DefaultTextStyle loses to any explicit
      // style on the child, and the label renders ink-on-ink. Both of the
      // CTA's own colours are stated on the child.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PwaGoldCta(label: 'Acheter', onPressed: _noop),
        ),
      ));
      final label = tester.widget<Text>(find.text('Acheter'));
      expect(label.style?.color, const Color(0xFF120E08));
      expect(label.style?.fontWeight, FontWeight.w800);
      expect(tester.takeException(), isNull);
    });
  });

  // ── §1 (2.1) — the headline is set in iOS's own two faces ────────────────
  group('PAY24  the paywall headline uses the native typefaces', () {
    Future<void> pump(WidgetTester tester, Size size) async {
      // `setSurfaceSize` does NOT change what `MediaQuery.sizeOf` reports in
      // this binding — measured: it stayed at the 800 default — and the whole
      // point here is a width-dependent type ramp. The view's own physical
      // size at dpr 1 is the logical size the widget reads.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(
        locale: Locale('en'),
        supportedLocales: PwaL10n.supportedLocales,
        localizationsDelegates: [PwaL10n.delegate],
        home: Scaffold(body: PwaPaywallHeadline()),
      ));
      // `PwaL10n.delegate` resolves asynchronously, so the FIRST frame carries
      // no text at all. One more pump is the difference between reading the
      // headline and reading an empty tree.
      await tester.pump();
    }

    testWidgets('PAY24: Playfair for the two serif lines, Great Vibes for the '
        'accent, at iOS metrics', (tester) async {
      await pump(tester, const Size(390, 900));
      final l = pwaL10nFor(const Locale('en'));
      TextStyle styleOf(String t) => tester.widget<Text>(find.text(t)).style!;

      // Line 1 — lead, Playfair, 32 / w500 / 0.95 / -0.5.
      final s1 = styleOf(l.paywallHeadlineLead);
      expect(s1.fontFamily, 'PlayfairDisplay');
      expect(s1.fontSize, 32);
      expect(s1.fontWeight, FontWeight.w500);
      expect(s1.height, 0.95);
      expect(s1.letterSpacing, -0.5);

      // Line 2 — trail, Playfair, 40 / w600 / 0.95 / -0.9, and the DOMINANT
      // line: bigger and heavier than the one above it.
      final s2 = styleOf(l.paywallHeadlineTrail);
      expect(s2.fontFamily, 'PlayfairDisplay');
      expect(s2.fontSize, 40);
      expect(s2.fontWeight, FontWeight.w600);
      expect(s2.height, 0.95);
      expect(s2.letterSpacing, -0.9);
      expect(s2.fontSize!, greaterThan(s1.fontSize!));

      // Line 3 — the accent, Great Vibes, 32 / w400 / 0.82, and GOLD where the
      // other two are champagne.
      final s3 = styleOf(l.paywallHeadlineAccent);
      expect(s3.fontFamily, 'GreatVibes');
      expect(s3.fontSize, 32);
      expect(s3.fontWeight, FontWeight.w400);
      expect(s3.height, 0.82);
      expect(s3.color, const Color(0xFFD6B25E));
      expect(s1.color, const Color(0xFFFFF3DC));
      expect(s2.color, s1.color);

      for (final s in [s1, s2, s3]) {
        expect(s.shadows, hasLength(2), reason: 'iOS shadows, on all three');
        // EVERY chain still ends in the bundled Khmer family: neither Latin
        // face has Khmer glyphs, and Khmer must be right on the first frame,
        // offline.
        expect(s.fontFamilyFallback!.last, 'NotoSansKhmer');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('PAY25: the small-phone sizes are iOS sizes too',
        (tester) async {
      // `small = width < 380` on iOS: 30 / 37 / 29.
      await pump(tester, const Size(360, 900));
      final l = pwaL10nFor(const Locale('en'));
      double sizeOf(String t) =>
          tester.widget<Text>(find.text(t)).style!.fontSize!;
      expect(sizeOf(l.paywallHeadlineLead), 30);
      expect(sizeOf(l.paywallHeadlineTrail), 37);
      expect(sizeOf(l.paywallHeadlineAccent), 29);
    });

    test('PAY26: the copy is the shared dictionary, in all three languages — '
        'nothing new was written', () {
      for (final code in const ['en', 'fr', 'km']) {
        final l = pwaL10nFor(Locale(code));
        expect(l.paywallHeadlineLead, l.shared.pwHeadlineLead, reason: code);
        expect(l.paywallHeadlineTrail, l.shared.pwHeadlineTrail, reason: code);
        expect(l.paywallHeadlineAccent, l.shared.pwHeadlineAccent,
            reason: code);
        for (final s in [
          l.paywallHeadlineLead,
          l.paywallHeadlineTrail,
          l.paywallHeadlineAccent,
        ]) {
          expect(s, isNotEmpty, reason: code);
          expect(s.startsWith('pw'), isFalse, reason: code);
        }
      }
    });

    test('PAY27: Great Vibes appears on the paywall and nowhere else', () {
      // A display script for one accent word. Having bundled it is not a
      // reason to start using it.
      final users = <String>[];
      for (final f in Directory('lib/features/pwa')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        // The paywall names the face through `kPwaPaywallScriptFamily`, which
        // is the point — one declaration, one spelling — so the search is for
        // either the literal or the constant that stands for it.
        final src = f.readAsStringSync();
        if (src.contains('GreatVibes') ||
            src.contains('kPwaPaywallScriptFamily')) {
          users.add(f.uri.pathSegments.last);
        }
      }
      users.sort();
      expect(users, const [
        'pwa_fonts.dart', // registers it
        'pwa_paywall.dart', // uses it
        'pwa_type.dart', // names it
      ]);
    });

    test('PAY28: both faces are bundled locally, with their licences', () {
      for (final f in const [
        'web/fonts/PlayfairDisplay-Latin.ttf',
        'web/fonts/GreatVibes-Regular.ttf',
        'web/fonts/OFL-PlayfairDisplay.txt',
        'web/fonts/OFL-GreatVibes.txt',
      ]) {
        expect(File(f).existsSync(), isTrue, reason: f);
      }
      // Served from web/, never declared as a Flutter asset: `pubspec.yaml` is
      // shared with the frozen mobile app and must not grow by 750 KB it will
      // never use.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('PlayfairDisplay')));
      expect(pubspec, isNot(contains('GreatVibes')));
      // …and nothing is fetched at runtime. Read as CODE: the file's own
      // comments explain WHY gstatic is forbidden, and naming it there is the
      // opposite of doing it.
      final fonts = _code('lib/features/pwa/data/pwa_fonts.dart');
      expect(fonts, contains('PlayfairDisplay-Latin.ttf'));
      expect(fonts, contains('GreatVibes-Regular.ttf'));
      expect(fonts, isNot(contains('gstatic')));
    });
  });

  // ── §2 (2.1) — one identity vocabulary, everywhere ───────────────────────
  group('AUTH10  the identity copy is one vocabulary', () {
    test('AUTH10: the renamed strings are the ones on screen', () {
      final en = pwaL10nFor(const Locale('en'));
      expect(en.accountTitle, 'Save my designs');
      expect(en.accountHaveOne, 'Already use Ayden Studio?');
      expect(en.accountSignInTitle, 'Sign in');

      final fr = pwaL10nFor(const Locale('fr'));
      expect(fr.accountTitle, 'Enregistrer mes créations');
      expect(fr.accountHaveOne, 'Vous utilisez déjà Ayden Studio ?');
      expect(fr.accountSignInTitle, 'Se connecter');

      // Khmer is checked for SHAPE rather than for a string a reader of this
      // file cannot verify: Khmer script, naming the product where the other
      // two do, and no longer saying "work".
      final km = pwaL10nFor(const Locale('km'));
      expect(km.accountTitle, matches(RegExp('[ក-៿]')));
      expect(km.accountHaveOne, contains('Ayden Studio'));
      expect(km.accountTitle, isNot(contains('ការងារ')),
          reason: 'the old wording meant "work", not "designs"');
      expect(km.accountBody, contains('Ayden'));
    });

    test('AUTH11: no surface still says the old thing', () {
      // The rename is only real if nothing reintroduces the previous sentence,
      // in a hardcoded literal or a stale dictionary entry.
      final dict = File('lib/features/pwa/l10n/pwa_translations.dart')
          .readAsStringSync();
      for (final old in const [
        'Save your work',
        'Enregistrez votre travail',
        'Already have an Ayden account?',
      ]) {
        expect(dict, isNot(contains(old)), reason: old);
      }
    });

    test('AUTH12: every entry point reads the SAME keys', () {
      // Not "says the same words" — reads the same keys, which is the only
      // version of that promise a rename cannot break.
      for (final f in const [
        'lib/features/pwa/presentation/pwa_profile_ios.dart',
        'lib/features/pwa/presentation/pwa_account_chip.dart',
        'lib/features/pwa/presentation/pwa_paywall.dart',
      ]) {
        final src = File(f).readAsStringSync();
        // Profile's guest CTA became "Secure my account" with Cambodia auth
        // (`authSecureCta`); the paywall and the header keep "Save my designs"
        // at the moment work has just been made. Both are dictionary keys.
        expect(src, anyOf(contains('accountTitle'), contains('authSecureCta')),
            reason: f);
        expect(src, contains('accountSignInTitle'), reason: f);
      }
      // The question line belongs to the two surfaces with room for it.
      for (final f in const [
        'lib/features/pwa/presentation/pwa_profile_ios.dart',
        'lib/features/pwa/presentation/pwa_paywall.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('accountHaveOne'),
            reason: f);
      }
    });
  });

  // ── §4 — one identity story, everywhere ──────────────────────────────────
  group('AUTH07  every anonymous entry point offers both doors', () {
    test('AUTH07: the header menu carries a Sign in item', () {
      // Round 1 added the returning-user door to Profile and left this menu
      // with only "Save your work", so the two entry points disagreed about
      // what was possible. Held as a source assertion because the menu lives
      // inside a PopupMenuButton overlay, and what matters is that the ITEM
      // and its route exist at all.
      final src =
          File('lib/features/pwa/presentation/pwa_account_chip.dart')
              .readAsStringSync();
      expect(src, contains("ValueKey('pwa-account-signin')"));
      expect(src, contains('accountSignInTitle'));
      // …and it opens the SIGN-IN journey, not the link one.
      expect(src, contains('showPwaAccountSheet(context, signIn: true)'));
      // Only a Guest is offered it: a verified account sees who it is.
      expect(src, contains('if (!identified)'));
    });

    test('AUTH08: the paywall offers both, as text, under one action', () {
      final src =
          File('lib/features/pwa/presentation/pwa_paywall.dart')
              .readAsStringSync();
      expect(src, contains("ValueKey('pwa-paywall-save-work')"));
      expect(src, contains("ValueKey('pwa-paywall-sign-in')"));
      expect(src, contains('signIn: true'));
    });

    test('AUTH09: all three surfaces reach the SAME two journeys', () {
      // One behaviour, three entries. If a fourth appears, it has to route
      // through this call too — there is no other way in.
      for (final f in const [
        'lib/features/pwa/presentation/pwa_profile_ios.dart',
        'lib/features/pwa/presentation/pwa_account_chip.dart',
        'lib/features/pwa/presentation/pwa_paywall.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src, contains('showPwaAccountSheet(context)'), reason: '$f link');
        expect(src, contains('signIn: true'), reason: '$f sign-in');
      }
    });
  });
}

void _noop() {}

/// A source file with its comments stripped.
///
/// These assertions are about what the CODE does. Reading the whole file made
/// them fail on the sentences that EXPLAIN the code — a comment naming the
/// native button it replaced, or the store the web does not sell through.
String _code(String path) => File(path)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join(String.fromCharCode(10));
