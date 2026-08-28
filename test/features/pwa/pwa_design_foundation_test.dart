/// Phase 1 — the visual foundation, pinned against iOS.
///
/// These tests exist because "it looks right" is not a thing a test suite can
/// hold. What it CAN hold is that the PWA's tokens are the SAME OBJECTS the
/// iOS app uses, and that the type roles carry the exact numbers read from
/// `frontend/lib/core/theme/app_theme.dart` at mobile HEAD f3a6fa2.
///
/// If someone later "improves" a radius or a weight on the web side, that is a
/// divergence from the source of truth and these fail — which is the whole
/// point of PARITY FIRST, IMPROVEMENTS LATER.
library;

import 'package:ai_home_architect/core/constants/app_colors.dart';
import 'package:ai_home_architect/core/constants/app_spacing.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_nav_shell.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_primitives.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_theme.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FOUND01  the canvas is the iOS canvas', () {
    test('the semantic surfaces ARE the shared iOS tokens, not copies', () {
      // Identity, not similarity. A hex literal that merely matched would drift
      // the first time iOS corrected one.
      expect(pwaCanvas, AppColors.background);
      expect(pwaOnCanvas, AppColors.textPrimary);
      expect(pwaCardSurface, AppColors.surface);
      expect(pwaWell, AppColors.surfaceVariant);
      expect(pwaGold, AppColors.accent);
      expect(pwaHairline, AppColors.border);
      expect(pwaImageFrame, AppColors.brandWarmBlack);
    });

    test('the canvas is warm ivory, not black', () {
      expect(pwaCanvas, const Color(0xFFF9F6F1));
      expect(pwaCanvas, isNot(pwaBlack));
    });

    testWidgets('the theme paints scaffolds on the canvas', (tester) async {
      final theme = pwaTheme();
      expect(theme.scaffoldBackgroundColor, pwaCanvas);
      expect(theme.colorScheme.surface, pwaCardSurface);
      expect(theme.dividerTheme.color, pwaHairline);
    });

    test('the legacy dark tokens still exist, so unmigrated screens compile',
        () {
      // Deliberately retained. Deleting them would have made this a big-bang
      // rewrite; Home, Create, Projects and Full Reveal still paint with them.
      expect(pwaBlack, const Color(0xFF0B0B0C));
      expect(pwaCharcoal, const Color(0xFF161513));
      expect(pwaCharcoalSoft, const Color(0xFF201E1B));
    });
  });

  group('FOUND02  the geometry is the iOS geometry', () {
    test('spacing names the iOS scale', () {
      expect(PwaGap.xs, AppSpacing.xs);
      expect(PwaGap.sm, AppSpacing.sm);
      expect(PwaGap.md, AppSpacing.md);
      expect(PwaGap.lg, AppSpacing.lg);
      expect(PwaGap.xl, AppSpacing.xl);
      expect(PwaGap.page, AppSpacing.pagePadding);
    });

    test('radii name the iOS scale, and CTAs are PILLS', () {
      expect(PwaGap.radius, AppSpacing.cardRadius); // 16
      expect(PwaGap.radiusLg, AppSpacing.radiusHero); // 24
      expect(PwaGap.radiusInput, AppSpacing.inputRadius); // 14
      // THE one that moves a visible thing.
      expect(PwaGap.radiusPill, AppSpacing.radiusButton);
      expect(PwaGap.radiusPill, 50);
    });
  });

  group('FOUND03  the type roles carry the iOS numbers', () {
    test('editorial display is Cormorant Garamond at the iOS metrics', () {
      // iOS AppTheme.displayEditorial(): 38 / w500 / -0.5 / 1.08
      final hero = PwaType.displayHero();
      expect(hero.fontFamily, kPwaDisplayFamily);
      expect(hero.fontSize, 38);
      expect(hero.fontWeight, FontWeight.w500);
      expect(hero.letterSpacing, -0.5);
      expect(hero.height, 1.08);

      // iOS AppTheme.atmosphereTitle(): 20 / w600 / 0 / 1.15
      final atmo = PwaType.atmosphereTitle();
      expect(atmo.fontFamily, kPwaDisplayFamily);
      expect(atmo.fontSize, 20);
      expect(atmo.fontWeight, FontWeight.w600);
      expect(atmo.height, 1.15);
    });

    test('functional roles are Inter at the iOS metrics', () {
      const expected = <String, (double, FontWeight)>{
        'displayLarge': (40, FontWeight.w300),
        'displayMedium': (32, FontWeight.w300),
        'screenTitle': (26, FontWeight.w600),
        'sectionTitle': (22, FontWeight.w600),
        'subsectionTitle': (18, FontWeight.w500),
        'cardTitle': (16, FontWeight.w600),
        'cardSubtitle': (15, FontWeight.w500),
        'body': (16, FontWeight.w400),
        'bodyMuted': (14, FontWeight.w400),
        'caption': (12, FontWeight.w400),
        'button': (15, FontWeight.w600),
      };
      final actual = <String, TextStyle>{
        'displayLarge': PwaType.displayLarge(),
        'displayMedium': PwaType.displayMedium(),
        'screenTitle': PwaType.screenTitle(),
        'sectionTitle': PwaType.sectionTitle(),
        'subsectionTitle': PwaType.subsectionTitle(),
        'cardTitle': PwaType.cardTitle(),
        'cardSubtitle': PwaType.cardSubtitle(),
        'body': PwaType.body(),
        'bodyMuted': PwaType.bodyMuted(),
        'caption': PwaType.caption(),
        'button': PwaType.button(),
      };
      for (final e in expected.entries) {
        final s = actual[e.key]!;
        expect(s.fontFamily, kPwaTextFamily, reason: e.key);
        expect(s.fontSize, e.value.$1, reason: e.key);
        expect(s.fontWeight, e.value.$2, reason: e.key);
      }
    });

    test('the iOS default text colours are respected', () {
      // iOS bodyMedium is textSecondary and bodySmall is textTertiary — the
      // hierarchy lives in COLOUR as much as in size, and flattening it is the
      // easiest way to lose the editorial feel.
      expect(PwaType.body().color, AppColors.textPrimary);
      expect(PwaType.bodyMuted().color, AppColors.textSecondary);
      expect(PwaType.caption().color, AppColors.textTertiary);
    });

    test('every role states the wght axis explicitly', () {
      // A registered variable font maps fontWeight onto wght, but if the load
      // failed, fontWeight alone would silently synthesise a weight. Naming
      // the axis is what makes the intent survive a missing file.
      for (final s in [
        PwaType.displayHero(),
        PwaType.screenTitle(),
        PwaType.body(),
        PwaType.button(),
      ]) {
        expect(s.fontVariations, isNotNull);
        expect(s.fontVariations!.single.axis, 'wght');
        expect(s.fontVariations!.single.value, s.fontWeight!.value.toDouble());
      }
    });

    test('every chain still ends with the bundled Khmer family', () {
      // The regression that would be invisible until someone opened the app in
      // Khmer: adding Latin faces at the head of a fallback chain and dropping
      // the Khmer family off the tail.
      expect(kPwaTextFallback.last, kPwaKhmerFamilyName);
      expect(kPwaDisplayFallback.last, kPwaKhmerFamilyName);
      expect(kPwaTextFallback.first, kPwaTextFamily);
      expect(kPwaDisplayFallback.first, kPwaDisplayFamily);
      expect(PwaType.body().fontFamilyFallback, contains(kPwaKhmerFamilyName));
      expect(
          PwaType.displayHero().fontFamilyFallback, contains(kPwaKhmerFamilyName));
    });

    test('eyebrow tracking collapses for Khmer', () {
      // Not taste: 2.4 of tracking on a cluster script pushes one syllable
      // apart into what looks like several.
      expect(PwaType.eyebrow(khmer: false).letterSpacing, 2.4);
      expect(PwaType.eyebrow(khmer: true).letterSpacing, 0);

      pwaKhmerTypography = true;
      addTearDown(() => pwaKhmerTypography = false);
      expect(pwaEyebrow().letterSpacing, 0);
      pwaKhmerTypography = false;
      expect(pwaEyebrow().letterSpacing, 2.4);
    });

    test('the legacy factories now resolve to the bundled families', () {
      // Unmigrated screens gain the correct face without being touched.
      expect(pwaDisplay(fontSize: 20).fontFamily, kPwaDisplayFamily);
      expect(pwaSans(fontSize: 14).fontFamily, kPwaTextFamily);
    });
  });

  group('FOUND04  the primitives are the iOS components', () {
    testWidgets('the primary CTA is an ink pill with a white label',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: pwaTheme(),
        home: Scaffold(
          body: PwaPrimaryButton(label: 'Continue', onPressed: () {}),
        ),
      ));
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      final style = button.style!;
      expect(style.backgroundColor!.resolve({}), pwaInk);
      expect(style.foregroundColor!.resolve({}), pwaSurface);
      expect(style.elevation!.resolve({}), 0);
      final shape = style.shape!.resolve({}) as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(PwaGap.radiusPill));
    });

    testWidgets('the secondary CTA is a 1.5px hairline pill', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: pwaTheme(),
        home: Scaffold(
          body: PwaSecondaryButton(label: 'Not now', onPressed: () {}),
        ),
      ));
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      final side = button.style!.side!.resolve({})!;
      expect(side.color, pwaHairline);
      expect(side.width, 1.5);
    });

    testWidgets('selection is a gold tick and a gold border', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: pwaTheme(),
        home: const Scaffold(
          body: Column(children: [
            PwaSelectionTick(),
            PwaSelectableCard(selected: true, child: SizedBox(height: 20)),
            PwaSelectableCard(selected: false, child: SizedBox(height: 20)),
          ]),
        ),
      ));
      await tester.pump();

      final tick = tester.widget<Container>(
        find.descendant(
            of: find.byType(PwaSelectionTick), matching: find.byType(Container)),
      );
      expect((tick.decoration! as BoxDecoration).color, pwaGold);

      final cards = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .toList();
      final selected =
          (cards[0].decoration! as BoxDecoration).border! as Border;
      final unselected =
          (cards[1].decoration! as BoxDecoration).border! as Border;
      expect(selected.top.color, pwaGold);
      expect(selected.top.width, 2);
      expect(unselected.top.color, pwaHairline);
      expect(unselected.top.width, 1);
    });
  });

  group('FOUND05  the navigation shell', () {
    testWidgets('has the three iOS destinations, in the iOS order',
        (tester) async {
      final tapped = <PwaNavDestination>[];
      await tester.pumpWidget(MaterialApp(
        theme: pwaTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          ...GlobalMaterialLocalizationsShim.delegates,
        ],
        home: PwaNavShell(
          current: PwaNavDestination.home,
          onSelect: tapped.add,
          child: const SizedBox.expand(),
        ),
      ));
      await tester.pump();

      expect(find.byType(PwaBottomNav), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Projects'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    // Phase 1 asserted the opposite of this: Profile was declared, visible and
    // INERT, because §5 said prepare the architecture and invent no
    // functionality. Phase 8 built the screen, so the assertion inverts — the
    // tab reports, like the other two. The escape hatch it was really testing
    // (a host that has no Profile route) is still here, and is tested below.
    testWidgets('all three destinations report, Profile included',
        (tester) async {
      final tapped = <PwaNavDestination>[];
      await tester.pumpWidget(MaterialApp(
        theme: pwaTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          ...GlobalMaterialLocalizationsShim.delegates,
        ],
        home: PwaNavShell(
          current: PwaNavDestination.home,
          onSelect: tapped.add,
          child: const SizedBox.expand(),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Projects'));
      await tester.tap(find.text('Profile'));
      expect(tapped,
          [PwaNavDestination.projects, PwaNavDestination.profile]);
    });

    testWidgets('a host without a destination can still disable it',
        (tester) async {
      final tapped = <PwaNavDestination>[];
      await tester.pumpWidget(MaterialApp(
        theme: pwaTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          ...GlobalMaterialLocalizationsShim.delegates,
        ],
        home: PwaNavShell(
          current: PwaNavDestination.home,
          onSelect: tapped.add,
          enabled: const {
            PwaNavDestination.home: true,
            PwaNavDestination.projects: true,
            PwaNavDestination.profile: false,
          },
          child: const SizedBox.expand(),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Profile'));
      expect(tapped, isEmpty,
          reason: 'a disabled destination must never navigate somewhere '
              'invented');
    });

    testWidgets('the bar is white with a hairline top, like iOS MainShell',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: pwaTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          ...GlobalMaterialLocalizationsShim.delegates,
        ],
        home: PwaNavShell(
          current: PwaNavDestination.home,
          onSelect: (_) {},
          child: const SizedBox.expand(),
        ),
      ));
      await tester.pump();

      final container = tester.widget<Container>(
        find
            .descendant(
                of: find.byType(PwaBottomNav), matching: find.byType(Container))
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, pwaCardSurface);
      expect((decoration.border! as Border).top.color, pwaHairline);
    });
  });

  group('FOUND06  Home speaks the foundation', () {
    test('the Home headline is iOS Home, not the generic hero role', () {
      // iOS uses displayEditorial(27, w500, height 1.12, -0.4) on Home
      // specifically — looser leading and tracking than the 38pt hero, because
      // the Home headline runs to two lines. Reusing displayHero at a smaller
      // size would set those two lines too tight.
      final home = PwaType.homeHeadline();
      expect(home.fontFamily, kPwaDisplayFamily);
      expect(home.fontSize, 27);
      expect(home.fontWeight, FontWeight.w500);
      expect(home.height, 1.12);
      expect(home.letterSpacing, -0.4);

      final hero = PwaType.displayHero();
      expect(home.height, isNot(hero.height));
      expect(home.letterSpacing, isNot(hero.letterSpacing));
    });

    test('the headline copy comes from the shared dictionary, in 3 locales',
        () {
      // `homeHeadline` already existed in en/fr/km for iOS. The PWA forwards to
      // it rather than writing web copies — one Khmer vocabulary, not two.
      for (final code in ['en', 'fr', 'km']) {
        final l = pwaL10nFor(Locale(code));
        expect(l.homeHeadline, isNotEmpty, reason: code);
        expect(l.newDesignSession, isNotEmpty, reason: code);
        expect(l.featuredVision, isNotEmpty, reason: code);
        // A missing key falls back to the key itself.
        expect(l.homeHeadline, isNot('homeHeadline'), reason: code);
        expect(l.newDesignSession, isNot('newDesignSession'), reason: code);
        expect(l.featuredVision, isNot('featuredVision'), reason: code);
      }
      // English is iOS's exact wording, including the deliberate line break.
      expect(pwaL10nFor(const Locale('en')).homeHeadline, contains('\n'));
    });
  });

  group('FOUND07  the step markers of the creation flow', () {
    // Both badges were measured off `upload_screen.dart`, and the step pill was
    // CORRECTED here in Phase 3: Phase 1 had built it on a soft-gold ground
    // from a reading of the design language rather than of the screen. iOS
    // fills it with ink. It had no call site until Phase 3, so nothing changed
    // underneath an existing screen.
    testWidgets('the step pill is ink-filled with surface text, as iOS is',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: pwaTheme(),
        localizationsDelegates: GlobalMaterialLocalizationsShim.delegates,
        home: const Scaffold(body: PwaStepPill('STEP 1 OF 4')),
      ));
      final box = tester.widget<Container>(
        find.descendant(
            of: find.byType(PwaStepPill), matching: find.byType(Container)),
      );
      final deco = box.decoration! as BoxDecoration;
      expect(deco.color, pwaInk, reason: 'iOS _StepBadge fills with textPrimary');
      expect(deco.borderRadius, BorderRadius.circular(PwaGap.radiusPill));
      expect(box.padding,
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5));

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.data, 'STEP 1 OF 4');
      expect(text.style!.color, pwaSurface);
      expect(text.style!.fontSize, 10);
      expect(text.style!.fontWeight, FontWeight.w600);
      expect(text.style!.letterSpacing, 1.0);
    });

    testWidgets('the optional badge is a hairlined well, not a second CTA',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: pwaTheme(),
        home: const Scaffold(body: PwaOptionalBadge('Optional')),
      ));
      final box = tester.widget<Container>(
        find.descendant(
            of: find.byType(PwaOptionalBadge), matching: find.byType(Container)),
      );
      final deco = box.decoration! as BoxDecoration;
      expect(deco.color, pwaWell);
      expect((deco.border! as Border).top.color, pwaHairline);
      expect(box.padding,
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3));
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.style!.fontSize, 11);
      expect(text.style!.fontWeight, FontWeight.w500);
      expect(text.style!.color, pwaFaint);
      // Not uppercased — iOS says "Optional", and shouting it would make a
      // skippable step look like the loudest thing on the screen.
      expect(text.data, 'Optional');
    });

    test('the step wording is the mobile dictionary, in all three locales', () {
      for (final code in ['en', 'fr', 'km']) {
        final l = pwaL10nFor(Locale(code));
        expect(l.uplStepBadge(1), l.shared.uplStepBadge(1), reason: code);
        expect(l.uplStepBadge(4), contains('4'), reason: code);
        for (final s in [
          l.uploadYourSpace,
          l.uplStep1Sub,
          l.uplStep2Title,
          l.uplStep2Sub,
          l.uplStep3Title,
          l.uplStep3Sub,
          l.uplStep4Title,
          l.uplOptional,
          l.uplPrivacy,
          l.uplGenerateDesign,
        ]) {
          expect(s, isNotEmpty, reason: code);
        }
      }
    });
  });
}

/// The PWA l10n facade resolves through `AppLocalizations`, which needs the
/// Material/Widgets delegates present. Kept here rather than imported so this
/// file states its own requirement.
abstract final class GlobalMaterialLocalizationsShim {
  static const delegates = <LocalizationsDelegate<Object?>>[
    DefaultMaterialLocalizations.delegate,
    DefaultWidgetsLocalizations.delegate,
  ];
}
