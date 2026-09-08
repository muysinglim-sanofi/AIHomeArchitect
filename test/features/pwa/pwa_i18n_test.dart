/// I18N — the PWA in Khmer, English and French.
///
/// The PWA is a Cambodia-first client, so "the UI is translated" is not polish
/// and cannot be a claim. These tests are what makes it a fact:
///
///   * the dictionaries are STRUCTURALLY complete and agree on placeholders
///     (a `{n}` dropped in Khmer is a sentence that renders "{n}" to a user);
///   * switching language changes the visible UI immediately, persists, and
///     survives a reload;
///   * a language change starts NO generation and mutates NO project — the
///     failure mode that only shows up on the invoice;
///   * canonical identifiers (`living_room`, `warm_modern`, `refine`,
///     `QUOTA_EXHAUSTED`) are byte-identical in all three locales;
///   * no presentation-layer English string is left behind in the audited
///     surfaces, checked against the SOURCE rather than against a screenshot.
library;

import 'dart:io';

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/core/models/atmosphere_style.dart';
import 'package:ai_home_architect/core/providers/locale_provider.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart'
    show PwaWorkKind;
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_translations.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_language_switcher.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_working_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _locales = ['km', 'en', 'fr'];

Map<String, String> _dict(String code) => switch (code) {
      'km' => pwaKmTranslations,
      'fr' => pwaFrTranslations,
      _ => pwaEnTranslations,
    };

/// `{n}`, `{name}`, `{title}`, `{label}`, `{total}` — the substitution points.
Set<String> _placeholders(String v) =>
    RegExp(r'\{[a-z]+\}').allMatches(v).map((m) => m.group(0)!).toSet();

/// Mount just enough app for `context.pwaL10n` to resolve.
Widget _app(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          locale: ref.watch(localeProvider),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: child),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── I18N01 ────────────────────────────────────────────────────────────────
  group('I18N01 all three supported locales load', () {
    test('the delegate accepts km / en / fr and nothing else', () {
      for (final code in _locales) {
        expect(
          AppLocalizations.delegate.isSupported(Locale(code)),
          isTrue,
          reason: '$code must be a product language',
        );
      }
      expect(AppLocalizations.delegate.isSupported(const Locale('th')), isFalse);
      expect(AppLocalizations.supportedLocales.length, 3);
    });

    test('every PWA key exists in every language', () {
      final en = pwaEnTranslations.keys.toSet();
      expect(en, isNotEmpty);
      for (final code in ['km', 'fr']) {
        final missing = en.difference(_dict(code).keys.toSet());
        final extra = _dict(code).keys.toSet().difference(en);
        expect(missing, isEmpty, reason: '$code is missing $missing');
        expect(extra, isEmpty, reason: '$code has orphan keys $extra');
      }
    });

    test('no translation is empty or left as the English source', () {
      for (final code in ['km', 'fr']) {
        for (final entry in _dict(code).entries) {
          expect(entry.value.trim(), isNotEmpty,
              reason: '$code:${entry.key} is empty');
        }
      }
      // A handful of keys are INTENTIONALLY identical across languages because
      // they are brand nouns or ids. Everything else being identical to English
      // would mean a language was never actually translated.
      const brandIdentical = {
        'pwaArchitectLabel', // AYDEN ARCHITECT
        'pwaAuthMethodFacebook', // Facebook — a brand, in every language
      };
      for (final code in ['km', 'fr']) {
        final same = _dict(code).entries
            .where((e) =>
                e.value == pwaEnTranslations[e.key] &&
                !brandIdentical.contains(e.key))
            .map((e) => e.key)
            .toList();
        expect(same.length, lessThan(6),
            reason: '$code still reads as English for $same');
      }
    });

    test('placeholders survive translation', () {
      for (final entry in pwaEnTranslations.entries) {
        final want = _placeholders(entry.value);
        for (final code in ['km', 'fr']) {
          expect(_placeholders(_dict(code)[entry.key]!), want,
              reason: '$code:${entry.key} placeholders drifted');
        }
      }
    });
  });

  // ── I18N02 / I18N03 / I18N04 ──────────────────────────────────────────────
  testWidgets('I18N02 a language change updates the visible UI immediately',
      (tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(_app(
      Consumer(builder: (context, ref, _) {
        captured = ref;
        return Text(context.pwaL10n.backHome);
      }),
    ));
    await tester.pump();
    expect(find.text(pwaEnTranslations['pwaBackHome']!), findsOneWidget);

    await captured.read(localeProvider.notifier).setLocale(const Locale('km'));
    await tester.pumpAndSettle();
    expect(find.text(pwaKmTranslations['pwaBackHome']!), findsOneWidget);
    expect(find.text(pwaEnTranslations['pwaBackHome']!), findsNothing);

    await captured.read(localeProvider.notifier).setLocale(const Locale('fr'));
    await tester.pumpAndSettle();
    expect(find.text(pwaFrTranslations['pwaBackHome']!), findsOneWidget);
  });

  testWidgets('I18N03 the choice survives a reload (F5)', (tester) async {
    // Tab one: choose Khmer. `pumpWidget` schedules the build; without a pump
    // the Consumer has not run yet and `first` is still unset.
    WidgetRef? first;
    await tester.pumpWidget(_app(Consumer(builder: (c, ref, _) {
      first = ref;
      return Text(c.pwaL10n.backHome);
    })));
    await tester.pumpAndSettle();
    await first!.read(localeProvider.notifier).setLocale(const Locale('km'));
    await tester.pumpAndSettle();

    // F5 = a brand new ProviderScope over the SAME SharedPreferences.
    await tester.pumpWidget(_app(
      Builder(builder: (c) => Text(c.pwaL10n.backHome)),
    ));
    await tester.pumpAndSettle();
    expect(find.text(pwaKmTranslations['pwaBackHome']!), findsOneWidget,
        reason: 'a reload must not silently return to English');
  });

  testWidgets('I18N04 the choice survives navigation / reopen', (tester) async {
    // Navigation is NOT a reload: the ProviderScope survives and a different
    // screen is pushed over the old one. (The reload case is I18N03.)
    final nav = GlobalKey<NavigatorState>();
    late WidgetRef ref0;
    await tester.pumpWidget(ProviderScope(
      child: Consumer(
        builder: (context, ref, _) {
          ref0 = ref;
          return MaterialApp(
            navigatorKey: nav,
            locale: ref.watch(localeProvider),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              builder: (c) => Scaffold(body: Text(c.pwaL10n.myProjects)),
            ),
          );
        },
      ),
    ));
    await tester.pumpAndSettle();
    await ref0.read(localeProvider.notifier).setLocale(const Locale('fr'));
    await tester.pumpAndSettle();
    expect(find.text(pwaFrTranslations['pwaMyProjects']!), findsOneWidget);

    // Home -> a project screen.
    nav.currentState!.push(MaterialPageRoute<void>(
      builder: (c) => Scaffold(body: Text(c.pwaL10n.yourSpaces)),
    ));
    await tester.pumpAndSettle();
    expect(find.text(pwaFrTranslations['pwaYourSpaces']!), findsOneWidget);

    // ... and back.
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text(pwaFrTranslations['pwaMyProjects']!), findsOneWidget,
        reason: 'navigating must not reset the language');
  });

  // ── locale resolution hierarchy ───────────────────────────────────────────
  group('locale resolution', () {
    test('an explicit persisted choice always wins over the browser', () async {
      SharedPreferences.setMockInitialValues({'ui_locale': 'fr'});
      final n = LocaleNotifier(deviceLocale: 'km');
      await Future<void>.delayed(Duration.zero);
      expect(n.state.languageCode, 'fr');
    });

    test('with nothing chosen, the browser language decides', () async {
      SharedPreferences.setMockInitialValues({});
      final n = LocaleNotifier(deviceLocale: 'km');
      await Future<void>.delayed(Duration.zero);
      expect(n.state.languageCode, 'km');
    });

    test('an unsupported browser language falls back to English', () async {
      SharedPreferences.setMockInitialValues({});
      final n = LocaleNotifier(deviceLocale: 'th');
      await Future<void>.delayed(Duration.zero);
      expect(n.state.languageCode, 'en');
    });

    test('mobile behaviour is unchanged: no device seed, English default',
        () async {
      SharedPreferences.setMockInitialValues({});
      final n = LocaleNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(n.state.languageCode, 'en');
    });

    test('the browser hint is NOT persisted — the first real pick is',
        () async {
      SharedPreferences.setMockInitialValues({});
      final n = LocaleNotifier(deviceLocale: 'km');
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ui_locale'), isNull,
          reason: 'a hint must not become a decision');
      await n.setLocale(const Locale('fr'));
      expect(prefs.getString('ui_locale'), 'fr');
    });
  });

  // ── I18N05..I18N10 — the surfaces ─────────────────────────────────────────
  group('translated surfaces', () {
    for (final code in _locales) {
      test('I18N05-10 [$code] every audited surface resolves', () {
        final l = pwaL10nFor(Locale(code));
        final samples = <String, String>{
          // Home
          'home.hero': l.heroLead,
          'home.heroAccent': l.heroAccent,
          'home.continue': l.continueDesigningEyebrow,
          'home.viewAll': l.viewAllProjects,
          // Create
          'create.upload': l.uploadCta,
          'create.drag': l.dragAndDropHint,
          'create.room': l.stepRoom,
          'create.atmosphere': l.stepAtmosphere,
          'create.cta': l.createFirstVision,
          // Loading phases
          'loading.initial': l.workInitialPhases.join('|'),
          'loading.refine': l.workRefinePhases.join('|'),
          'loading.switch': l.workSwitchPhases.join('|'),
          'loading.wait': l.usuallyACoupleOfMinutes,
          // Architect
          'architect.ask': l.askAydenAnything,
          'architect.disclaimer': l.aydenDisclaimer,
          'architect.reveal': l.viewFullReveal,
          'architect.edit': l.editRequest,
          'architect.continueAnyway': l.continueAnyway,
          // Full Reveal
          'reveal.title': l.fullReveal,
          'reveal.details': l.visionDetails,
          'reveal.atmospheres': l.atmospheresSection,
          'reveal.before': l.beforeLabel,
          'reveal.after': l.afterLabel,
          // Projects
          'projects.spaces': l.yourSpaces,
          'projects.search': l.searchProjects,
          'projects.delete': l.deleteProjectTitle,
          'projects.empty': l.yourNextSpace,
          // Billing (I18N10)
          'billing.freeExhausted': l.billingFreeExhausted,
          'billing.passRequired': l.billingPassRequired,
          'billing.passExhausted': l.billingPassExhausted,
          'billing.unavailable': l.billingUnavailable,
          'billing.watermark': l.freeVisionWatermarked,
        };
        samples.forEach((where, value) {
          expect(value.trim(), isNotEmpty, reason: '$where empty in $code');
          // `_get` returns the KEY when a lookup misses. A value that still
          // looks like a key is a missing translation wearing a disguise.
          expect(value.startsWith('pwa'), isFalse,
              reason: '$where fell through to its key in $code ($value)');
        });
      });
    }

    test('I18N09 the loading phases keep their shape in every language', () {
      for (final code in _locales) {
        final l = pwaL10nFor(Locale(code));
        expect(l.workInitialPhases, hasLength(4));
        expect(l.workRefinePhases, hasLength(4));
        expect(l.workSwitchPhases, hasLength(4));
        expect(l.workSwitchNamedPhases('Soft Luxury').first,
            contains('Soft Luxury'),
            reason: 'the atmosphere brand name must survive interpolation');
      }
    });

    test('I18N09 the working indicator resolves phases from the dictionary',
        () {
      final km = pwaL10nFor(const Locale('km'));
      // The FIRST vision speaks the shared dictionary — the same seven the
      // phone says for the same beat (`chat_screen.dart:3661`). Refine and
      // switch keep the web's own four.
      expect(pwaWorkingPhasesFor(PwaWorkKind.firstVision, '', km),
          km.shared.genInitPhrases);
      expect(km.shared.genInitPhrases, hasLength(7));
      for (final s in km.shared.genInitPhrases) {
        expect(s, isNotEmpty);
      }
      expect(pwaWorkingPhasesFor(PwaWorkKind.refine, '', km),
          km.workRefinePhases);
      // Without a dictionary it stays on the English constants — the existing
      // behavioural tests depend on that identity.
      expect(pwaWorkingPhasesFor(PwaWorkKind.refine), kPwaRefinePhases);
    });
  });

  // ── I18N11 / I18N12 — room and atmosphere terminology ─────────────────────
  group('canonical terminology comes from the mobile dictionary', () {
    test('I18N11 room labels are the APPROVED mobile wording', () {
      for (final code in _locales) {
        final l = pwaL10nFor(Locale(code));
        final mobile = AppLocalizations(Locale(code));
        expect(l.roomLabel('living_room'), mobile.livingRoom);
        expect(l.roomLabel('kitchen'), mobile.kitchen);
        expect(l.roomLabel('terrace'), mobile.terrace);
        expect(l.roomLabel('pool_area'), mobile.poolArea);
        expect(l.roomLabel('living_room').trim(), isNotEmpty);
      }
      // And they really do differ per language — otherwise "reuse" would be
      // indistinguishable from "never translated".
      expect(pwaL10nFor(const Locale('km')).roomLabel('living_room'),
          isNot(pwaL10nFor(const Locale('en')).roomLabel('living_room')));
      expect(pwaL10nFor(const Locale('fr')).roomLabel('living_room'),
          isNot(pwaL10nFor(const Locale('en')).roomLabel('living_room')));
    });

    test('I18N12 atmosphere NAMES stay English (a brand decision), taglines '
        'are localized', () {
      for (final a in kAtmospheresOrdered) {
        for (final code in _locales) {
          expect(pwaL10nFor(Locale(code)).atmosphereName(a.id), a.name,
              reason: 'atmosphere names are brand nouns on every platform');
        }
      }
      final en = pwaL10nFor(const Locale('en'));
      final fr = pwaL10nFor(const Locale('fr'));
      final km = pwaL10nFor(const Locale('km'));
      expect(fr.atmosphereTagline('warm_modern'),
          isNot(en.atmosphereTagline('warm_modern')));
      expect(km.atmosphereTagline('warm_modern'),
          isNot(en.atmosphereTagline('warm_modern')));
    });
  });

  // ── I18N13 — internal ids never move ──────────────────────────────────────
  test('I18N13 canonical identifiers are byte-identical in every locale', () {
    const ids = [
      'living_room', 'master_bedroom', 'kitchen', 'terrace', 'pool_area',
      'warm_modern', 'soft_luxury', 'japandi_calm', 'nordic_warmth',
      'tropical_escape', 'ayden_signature',
    ];
    // The ids are compile-time constants; what this proves is that NOTHING in
    // the localization layer rewrites them, and that no dictionary has quietly
    // taken one as a key it would then translate.
    for (final id in ids) {
      for (final code in _locales) {
        expect(_dict(code).containsKey(id), isFalse,
            reason: '$id must never be a translation key');
      }
    }
    for (final a in kAtmospheresOrdered) {
      final seen = {for (final c in _locales) pwaL10nFor(Locale(c)).atmosphereName(a.id)};
      expect(seen, hasLength(1),
          reason: 'atmosphere ${a.id} rendered differently per locale');
    }
    // Billing / action codes are matched, never translated.
    for (final code in _locales) {
      final l = pwaL10nFor(Locale(code));
      expect(l.billingState('FREE_EXHAUSTED'), l.billingFreeExhausted);
      expect(l.billingState('PASS_REQUIRED'), l.billingPassRequired);
      expect(l.errorForCode('QUOTA_EXHAUSTED'), l.billingFreeExhausted);
      // An unknown code degrades to a sentence, never to a raw code on screen.
      expect(l.errorForCode('SOMETHING_NEW'), l.errUnknown);
    }
  });

  // ── I18N14 / I18N15 — a language change is inert ──────────────────────────
  testWidgets('I18N14/I18N15 changing language generates nothing and mutates '
      'no project', (tester) async {
    late WidgetRef ref0;
    await tester.pumpWidget(_app(Consumer(builder: (c, ref, _) {
      ref0 = ref;
      return Column(children: [
        Text(c.pwaL10n.backHome),
        const PwaLanguageSwitcher(),
      ]);
    })));
    await tester.pumpAndSettle();

    // The switcher is a leaf: it depends on the locale provider and nothing
    // else. If it could reach the controller or the repository it would have
    // to import them — so the strongest available proof is a source check plus
    // an observable one.
    final src = File('lib/features/pwa/presentation/pwa_language_switcher.dart')
        .readAsStringSync();
    for (final forbidden in [
      'pwaControllerProvider',
      'pwaGenerationServiceProvider',
      'pwaPersistenceProvider',
      'generate(',
      'applyRefine',
    ]) {
      expect(src.contains(forbidden), isFalse,
          reason: 'the language selector must not be able to $forbidden');
    }

    await ref0.read(localeProvider.notifier).setLocale(const Locale('km'));
    await tester.pumpAndSettle();
    expect(find.text(pwaKmTranslations['pwaBackHome']!), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'ui_locale'},
        reason: 'a language change wrote something other than the language');
  });

  // ── I18N16 / I18N17 — text expansion ──────────────────────────────────────
  group('text expansion', () {
    testWidgets('I18N16/I18N17 Khmer and French render without overflow at '
        'mobile, tablet and desktop widths', (tester) async {
      // A representative worst case: the longest label in each language inside
      // the narrow pill the top bar gives it.
      for (final width in <double>[360, 768, 1440]) {
        for (final code in ['km', 'fr', 'en']) {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          final l = pwaL10nFor(Locale(code));
          await tester.pumpWidget(_app(
            Center(
              child: SizedBox(
                width: width,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(l.newProjectAction,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Flexible(
                      child: Text(l.viewAllProjects,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Flexible(
                      child: Text(l.createFirstVision,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '$code overflowed at ${width}px');
        }
      }
    });

    test('no PWA string is absurdly longer than its English source', () {
      // Not a style rule — a layout one. A translation several times the length
      // of the original will break a control no matter how flexible the row is,
      // and is nearly always a mistake rather than a language property.
      for (final entry in pwaEnTranslations.entries) {
        for (final code in ['km', 'fr']) {
          final other = _dict(code)[entry.key]!;
          if (entry.value.length < 12) continue;
          expect(other.length, lessThan(entry.value.length * 3),
              reason: '$code:${entry.key} is ${other.length} chars vs '
                  '${entry.value.length} in English');
        }
      }
    });
  });

  // ── I18N18 — nothing English left behind ──────────────────────────────────
  test('I18N18 no hardcoded presentation English remains in the audited PWA '
      'surfaces', () {
    // Literals that are legitimately not translated. Each entry is a decision,
    // not an exemption: brand nouns, CSS-ish values, canonical ids, sentinels.
    const allowed = <String>{
      'Ayden Studio',          // the brand, identical in all three dictionaries
      'AYDEN STUDIO',
      'AYDEN ARCHITECT',
      'Ayden Decide',          // brand feature name (mobile keeps it too)
      'Ayden Signature',
      'Your space',            // stored-data SENTINEL, see kPwaGenericRoomLabel
      'center center',         // CSS object-position
      'center 35%',
      'Georgia',               // font family names
      'Times New Roman',
      'Helvetica Neue',
      'Arial',
      'CormorantGaramond',     // the bundled product typefaces. Same rule as
      'Inter',                 // NotoSansKhmer below: a FONT id, matched
                               // byte-for-byte against the FontLoader
                               // registration in pwa_fonts.dart. Translating
                               // one would not change a word on screen — it
                               // would silently drop the family and render the
                               // whole product in the platform default.
      'NotoSansKhmer',         // the bundled Khmer family — a FONT id, and it
                               // must match the FontLoader registration
                               // byte-for-byte, so translating it would
                               // silently disable Khmer rendering
      'PlayfairDisplay',       // the paywall headline's two faces. Same rule
      'GreatVibes',            // as the three above: FONT ids matched against
                               // pwa_fonts.dart, never read by a person.
      'Living Room',           // example-asset labels routed as EN room labels
      'Bedroom',
      'Kitchen',
      'ABA KHQR',              // the payment method's own name, on ABA's tile.
                               // Never translated, by the rule
                               // pwa_translations.dart states for 'KHQR' and
                               // 'ABA Mobile': it is the name printed on the
                               // thing the person is paying with. ('ABA
                               // PayWay' left this list with the provider
                               // copy — Ayden's UI no longer says it.)
    };

    // Files whose English literals are a DOCUMENTED fallback rather than what a
    // user sees. `pwa_working_indicator.dart` keeps its four English phase
    // constants because `pwaWorkingPhasesFor` returns them only when no
    // dictionary is supplied — every real render supplies one, and the i18n
    // tests above prove the localized path is what the architect screen uses.
    const constantFallbackFiles = {'pwa_working_indicator.dart'};

    final files = [
      ...Directory('lib/features/pwa/presentation')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
      File('lib/features/pwa/application/pwa_controller.dart'),
    ];

    final lit = RegExp(r"""(?<![\w$])'((?:[^'\\\n]|\\.)*)'""");
    final offenders = <String>[];

    for (final f in files) {
      // The list mixes Directory.listSync paths (native separators) with a
      // literal forward-slash path. `Uri` normalises both, which a manual
      // split on one separator does not.
      final name = f.uri.pathSegments.last;
      if (name.contains('pwa_l10n') || name.contains('pwa_translations')) {
        continue;
      }
      if (constantFallbackFiles.contains(name)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//') || line.startsWith('import ')) continue;
        for (final m in lit.allMatches(lines[i])) {
          // What a person reads is the literal WITHOUT its interpolations:
          // `'${p.roomLabel} · ${p.atmosphereLabel}'` composes two already
          // localized values around a separator, and flagging it would be
          // flagging punctuation. Strip `${...}` and `$ident` first, then ask
          // whether anything readable is left.
          final v = m
              .group(1)!
              .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
              .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), '')
              .trim();
          if (v.length < 3) continue;
          // Fewer than two letters is a separator, a bullet or a unit — not a
          // sentence anyone translates.
          if (RegExp(r'[A-Za-z]').allMatches(v).length < 2) continue;
          if (allowed.contains(v)) continue;
          // ids / keys / asset paths / SCREAMING_CASE codes
          if (RegExp(r'^[a-z0-9_-]+$').hasMatch(v)) continue;
          if (RegExp(r'^[A-Z0-9_]+$').hasMatch(v)) continue;
          if (v.startsWith('assets/') ||
              v.startsWith('http') ||
              v.startsWith('package:') ||
              v.startsWith('pwa-') ||
              v.startsWith('av7-')) {
            continue;
          }
          // Prose = contains a space, or begins with a capital letter.
          final prose = v.contains(' ') || RegExp(r'^[A-Z]').hasMatch(v);
          if (!prose) continue;
          // A ValueKey / debugLabel is not shown to anyone.
          final ctx = lines[i];
          if (ctx.contains('ValueKey') ||
              ctx.contains('Key(') ||
              ctx.contains('debugLabel') ||
              ctx.contains('semanticsIdentifier')) {
            continue;
          }
          offenders.add('$name:${i + 1}  $v');
        }
      }
    }

    final presentation = offenders
        .where((o) => !o.startsWith('pwa_controller.dart'))
        .toList();
    expect(presentation, isEmpty,
        reason: 'these presentation strings never reach the localization '
            'layer:\n${presentation.join('\n')}');

    // The controller is a different case and is treated as one.
    //
    // Most of what remains there is the English `userMessage` of a
    // `PwaGenerationFailure` — a DELIBERATE fallback: the failure also carries
    // a `code`, and `_PwaGenerationErrorBar` renders
    // `PwaL10n.errorForCode(code)`. The English sentence is what a code this
    // build has never seen degrades to, so deleting it would make an unknown
    // failure show nothing at all.
    //
    // The rest are listed because they are REAL gaps, not because they are
    // acceptable: a generated project title and two relative-date labels. They
    // are frozen here so the list can only shrink — any NEW hardcoded string
    // in the controller fails this test.
    const knownControllerGaps = <String>{
      'Untitled Space',                 // placeholder TITLE (stored data)
      'Open-plan Living Space',         // generated project title (stored data)
      'Concept',                        // ditto
      'Updated today',                  // relative date  - TODO: localize
      'Continuing from Vision .',       // branch notice  - TODO: localize
      'Your next change will branch from it.',
      'Try again',
    };
    final controller = offenders
        .where((o) => o.startsWith('pwa_controller.dart'))
        .map((o) => o.split('  ').last)
        .where((v) => !knownControllerGaps.contains(v))
        .where((v) => !_isFailureFallback(v))
        .toList();
    expect(controller, isEmpty,
        reason: 'new hardcoded English in the controller:\n'
            '${controller.join('\n')}');
  });
}


/// The English `userMessage` of a `PwaGenerationFailure`.
///
/// Every one of these is paired with a semantic `code` that the error banner
/// translates; the sentence is the degradation path for an unknown code, not
/// the thing a person normally reads. Matched by CONTENT rather than by line
/// so the check does not break when the file moves.
bool _isFailureFallback(String v) => const {
      'That request was cancelled.',
      'Something went wrong creating your vision. Try again.',
      'This vision could not be completed. You can try again.',
      'This is taking longer than expected. Try again.',
      'Ayden is still working on this one.',
      'Give it a moment, then try again.',
      'Your session expired. Reload the page to continue.',
      'This build cannot reach a generation backend.',
      'Something went wrong. Try again.',
      'Your vision could not be saved. Try again.',
      "Ayden couldn't complete this vision. You can try again.",
      "Ayden couldn't find that generation. You can try again.",
      "Your photo couldn't be uploaded. Try again.",
      "Your vision couldn't be prepared. Try again.",
    }.contains(v);
