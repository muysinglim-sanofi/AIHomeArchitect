import 'package:flutter/material.dart';
import 'translations/en.dart';
import 'translations/km.dart';
import '../models/atmosphere_style.dart';

export '../models/atmosphere_style.dart' show AtmosphereStyle;

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations);

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const supportedLocales = [Locale('en'), Locale('km')];

  bool get isKhmer => locale.languageCode == 'km';

  String _get(String key) {
    final map = isKhmer ? kmTranslations : enTranslations;
    return map[key] ?? enTranslations[key] ?? key;
  }

  // ── App ───────────────────────────────────────────────────────────────────
  String get appName => _get('appName');
  String get tagline => _get('tagline');
  String get taglineSub => _get('taglineSub');

  // ── Onboarding ────────────────────────────────────────────────────────────
  String get onboarding1Title => _get('onboarding1Title');
  String get onboarding1Sub => _get('onboarding1Sub');
  String get onboarding2Title => _get('onboarding2Title');
  String get onboarding2Sub => _get('onboarding2Sub');
  String get onboarding3Title => _get('onboarding3Title');
  String get onboarding3Sub => _get('onboarding3Sub');
  String get getStarted => _get('getStarted');
  String get continueLabel => _get('continue');
  String get skip => _get('skip');
  String get skipForNow => _get('skipForNow');

  // ── Home ──────────────────────────────────────────────────────────────────
  String get homeHeadline => _get('homeHeadline');
  String get homeSubtitle => _get('homeSubtitle');
  String get homeCategoryInterior => _get('homeCategoryInterior');
  String get homeCategoryExterior => _get('homeCategoryExterior');
  String get homeGreetingMorning => _get('homeGreetingMorning');
  String get homeGreetingAfternoon => _get('homeGreetingAfternoon');
  String get homeGreetingEvening => _get('homeGreetingEvening');
  String get newDesignSession => _get('newDesignSession');
  String get recentTransformations => _get('recentTransformations');
  String get latestTransformation => _get('latestTransformation');
  String get noProjects => _get('noProjects');
  String get seeAll => _get('seeAll');
  String get continueDesigning => _get('continueDesigning');

  // ── Upload ────────────────────────────────────────────────────────────────
  String get uploadTitle => _get('uploadTitle');
  String get uploadSubtitle => _get('uploadSubtitle');
  String get uploadHint => _get('uploadHint');
  String get uploadPrompt => _get('uploadPrompt');
  String get uploadFileTypes => _get('uploadFileTypes');
  String get roomTypeLabel => _get('roomTypeLabel');
  String get styleLabel => _get('styleLabel');
  String get startDesign => _get('startDesign');
  String get interiorSection => _get('interiorSection');
  String get exteriorSection => _get('exteriorSection');
  String get takePhoto => _get('takePhoto');
  String get takePhotoSub => _get('takePhotoSub');
  String get chooseGallery => _get('chooseGallery');
  String get chooseGallerySub => _get('chooseGallerySub');
  String get uploadYourSpace => _get('uploadYourSpace');

  // ── Room types ────────────────────────────────────────────────────────────
  // Individual room getters for spot use
  String get livingRoom => _get('livingRoom');
  String get masterBedroom => _get('masterBedroom');
  String get kitchen => _get('kitchen');
  String get bathroom => _get('bathroom');
  String get homeOffice => _get('homeOffice');
  String get diningRoom => _get('diningRoom');
  String get entranceHall => _get('entranceHall');
  String get houseFacade => _get('houseFacade');
  String get garden => _get('garden');
  String get poolArea => _get('poolArea');
  String get terrace => _get('terrace');
  String get balcony => _get('balcony');
  String get driveway => _get('driveway');

  List<String> get interiorRooms => [
        _get('livingRoom'),
        _get('masterBedroom'),
        _get('kitchen'),
        _get('bathroom'),
        _get('homeOffice'),
        _get('diningRoom'),
        _get('entranceHall'),
      ];

  List<String> get exteriorRooms => [
        _get('houseFacade'),
        _get('garden'),
        _get('poolArea'),
        _get('terrace'),
        _get('balcony'),
        _get('driveway'),
      ];

  // Emotional atmosphere styles — image-first, evocative naming
  static List<AtmosphereStyle> get atmospheres => kAtmospheres;
  static List<String> get styleNames => kAtmospheres.map((a) => a.name).toList();

  // ── Chat ──────────────────────────────────────────────────────────────────
  String get chatTitle => _get('chatTitle');
  String get chatPlaceholder => _get('chatPlaceholder');
  String get chatGeneratingHint => _get('chatGeneratingHint');
  String get generateButton => _get('generateButton');
  String get generatingInChat => _get('generatingInChat');

  // ── Inline result ─────────────────────────────────────────────────────────
  String get viewBeforeAfter => _get('viewBeforeAfter');
  String get saveDesign => _get('saveDesign');
  String get shareDesign => _get('shareDesign');
  String get tryAnother => _get('tryAnother');

  // ── Generation loading ────────────────────────────────────────────────────
  String get generatingTitle => _get('generatingTitle');
  String get generatingSubtitle => _get('generatingSubtitle');

  // ── Before/After ──────────────────────────────────────────────────────────
  String get beforeLabel => _get('beforeLabel');
  String get afterLabel => _get('afterLabel');
  String get saveResult => _get('saveResult');
  String get shareResult => _get('shareResult');
  String get newVariation => _get('newVariation');
  String get dragToReveal => _get('dragToReveal');
  String get yourTransformation => _get('yourTransformation');

  // ── History ───────────────────────────────────────────────────────────────
  String get historyTitle => _get('historyTitle');
  String get newProject => _get('newProject');

  // ── Sessions ──────────────────────────────────────────────────────────────
  String get sessionsTitle => _get('sessionsTitle');
  String get sessionsBalance => _get('sessionsBalance');
  String get sessionsSubtitle => _get('sessionsSubtitle');
  String get sessionsAvailable => _get('sessionsAvailable');
  String get choosePlan => _get('choosePlan');
  String get bestValue => _get('bestValue');
  String get selectPlan => _get('selectPlan');
  String get perSession => _get('perSession');
  String get session => _get('session');
  String get sessions => _get('sessions');
  String get transformation => _get('transformation');
  String get transformations => _get('transformations');

  String sessionCount(int n) => '$n ${n == 1 ? session : sessions}';
  String transformationCount(int n) =>
      '$n ${n == 1 ? _get('transformation') : _get('transformations')}';
  String unlockLabel(int n, double price) =>
      '${_get('unlockSessions')} ${sessionCount(n)} — \$${price.toStringAsFixed(2)}';

  // ── Profile ───────────────────────────────────────────────────────────────
  String get profileTitle => _get('profileTitle');
  String get signOut => _get('signOut');
  String get projectsCount => _get('projectsCount');
  String get sessionsCount => _get('sessionsCount');
  String get sharedCount => _get('sharedCount');

  // ── Settings ──────────────────────────────────────────────────────────────
  String get settingsLanguage => _get('settingsLanguage');
  String get english => _get('english');
  String get khmer => _get('khmer');
  String get settingsAccount => _get('settingsAccount');
  String get settingsSupport => _get('settingsSupport');
  String get editProfile => _get('editProfile');
  String get notifications => _get('notifications');
  String get privacy => _get('privacy');
  String get helpCenter => _get('helpCenter');
  String get rateApp => _get('rateApp');
  String get about => _get('about');
  String get chooseLanguage => _get('chooseLanguage');

  // ── Chat timeline & project state ─────────────────────────────────────────
  String get today => _get('today');
  String get yesterday => _get('yesterday');
  String get lastUpdated => _get('lastUpdated');
  String get visionCreated => _get('visionCreated');
  String get readyToCreate => _get('readyToCreate');
  String get vision => _get('vision');
  String get visions => _get('visions');
  String visionCount(int n) => '$n ${n == 1 ? _get('vision') : _get('visions')}';

  // ── Hero ──────────────────────────────────────────────────────────────────
  String get featuredVision => _get('featuredVision');

  // ── Source photo ──────────────────────────────────────────────────────────
  String get sourcePhoto => _get('sourcePhoto');
  String get replacePhoto => _get('replacePhoto');
  String get sourcePhotoUpdated => _get('sourcePhotoUpdated');

  // ── Bimodal intent (Wave 5.5.14b.2) ───────────────────────────────────────
  String get modeChooserTitle => _get('modeChooserTitle');
  String get modePreserve => _get('modePreserve');
  String get modePreserveSub => _get('modePreserveSub');
  String get modeCreate => _get('modeCreate');
  String get modeCreateSub => _get('modeCreateSub');
}

// ── Delegate ──────────────────────────────────────────────────────────────────

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'km'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

// ── BuildContext extension ─────────────────────────────────────────────────────

extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
