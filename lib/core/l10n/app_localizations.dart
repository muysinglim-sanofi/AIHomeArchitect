import 'package:flutter/material.dart';
import 'translations/en.dart';
import 'translations/km.dart';
import 'translations/fr.dart';
import '../models/atmosphere_style.dart';

export '../models/atmosphere_style.dart' show AtmosphereStyle;

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations);

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const supportedLocales = [Locale('en'), Locale('km'), Locale('fr')];

  bool get isKhmer => locale.languageCode == 'km';
  bool get isFrench => locale.languageCode == 'fr';

  String _get(String key) {
    final map = isFrench
        ? frTranslations
        : (isKhmer ? kmTranslations : enTranslations);
    return map[key] ?? enTranslations[key] ?? key;
  }

  // ── App ───────────────────────────────────────────────────────────────────
  String get appName => _get('appName');
  String get tagline => _get('tagline');
  String get taglineSub => _get('taglineSub');
  String get brandSignature => _get('brandSignature');
  String get brandDesigningSpace => _get('brandDesigningSpace');

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

  // Suggestion chips — localized STATIC fallback (used by chat _suggestions when
  // there is no dynamic backend suggestion). Same order/role as the former
  // const lists in mock_projects.dart. Dynamic backend suggestions bypass these.
  List<String> get preGenerationSuggestions => [
        _get('suggPushFurther'),
        _get('suggMoreDaylight'),
        _get('suggCalmerAtmo'),
        _get('suggOpenSpace'),
      ];

  List<String> get postGenerationSuggestions => [
        _get('suggPushFurther'),
        _get('suggSofterLighting'),
        _get('suggOtherPalette'),
        _get('suggCalmerStrong'),
      ];

  // Emotional atmosphere styles — image-first, evocative naming.
  // Wave 5.17d.1 — display order honors the free pair (Warm Modern,
  // Nordic Warmth) first so non-premium users see what they can do
  // before what's locked. Single switch propagates to upload_screen,
  // chat_screen Re-upload modal, and before_after_screen Full Reveal
  // carousel — all of which read through these getters.
  static List<AtmosphereStyle> get atmospheres => kAtmospheresOrdered;
  static List<String> get styleNames =>
      kAtmospheresOrdered.map((a) => a.name).toList();

  // ── Chat ──────────────────────────────────────────────────────────────────
  String get chatTitle => _get('chatTitle');
  String get chatPlaceholder => _get('chatPlaceholder');
  String get chatGeneratingHint => _get('chatGeneratingHint');
  String get voiceListening => _get('voiceListening');
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
  String get exploreOtherAtmospheres => _get('exploreOtherAtmospheres');
  String get saveResult => _get('saveResult');
  String get shareResult => _get('shareResult');
  String get newVariation => _get('newVariation');
  String get dragToReveal => _get('dragToReveal');
  String get yourTransformation => _get('yourTransformation');

  // ── History ───────────────────────────────────────────────────────────────
  String get historyTitle => _get('historyTitle');
  String get newProject => _get('newProject');

  // ── Redesigns (Wave 5.17d.1 — replaces the legacy "Sessions" credit
  //    pack vocabulary ; getters tied to the deleted BuySessionsScreen
  //    have been removed) ─────────────────────────────────────────────
  String get transformation => _get('transformation');
  String get transformations => _get('transformations');

  String transformationCount(int n) =>
      '$n ${n == 1 ? _get('transformation') : _get('transformations')}';

  // ── Profile ───────────────────────────────────────────────────────────────
  String get profileTitle => _get('profileTitle');
  String get signOut => _get('signOut');
  String get projectsCount => _get('projectsCount');
  String get sharedCount => _get('sharedCount');

  // ── Settings ──────────────────────────────────────────────────────────────
  String get settingsLanguage => _get('settingsLanguage');
  String get english => _get('english');
  String get khmer => _get('khmer');
  String get french => _get('french');
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

  // ── FTUE (onboarding demo) ────────────────────────────────────────────────
  String get ftueBefore => _get('ftueBefore');
  String get ftueAfter => _get('ftueAfter');
  String get ftueAiVision => _get('ftueAiVision');
  String get ftueDemoUser => _get('ftueDemoUser');
  String get ftueDemoAi => _get('ftueDemoAi');
  String get ftueDemoRefining => _get('ftueDemoRefining');

  // ── Atmosphere descriptive text (names stay English brand; tagline +
  //    subtitle are localized by atmosphere id — option A) ───────────────────
  String atmosphereTagline(String id) => _get('atmoTagline_$id');
  String atmosphereSubtitle(String id) => _get('atmoSubtitle_$id');

  // ── Paywall (V2) ──────────────────────────────────────────────────────────
  String get pwHeadline => _get('pwHeadline');
  String get pwHeadlineLead => _get('pwHeadlineLead');
  String get pwHeadlineAccent => _get('pwHeadlineAccent');
  String get pwHeadlineTrail => _get('pwHeadlineTrail');
  String get pwSubheadline => _get('pwSubheadline');
  String get pwLovedBy => _get('pwLovedBy');
  String get pwHomeowners => _get('pwHomeowners');
  String get pwAnnual => _get('pwAnnual');
  String get pwWeekly => _get('pwWeekly');
  String get pwBestValue => _get('pwBestValue');
  String get pwPopular => _get('pwPopular');
  String get pwPerYear => _get('pwPerYear');
  String get pwPerWeek => _get('pwPerWeek');
  String get pwAnnualPositioning => _get('pwAnnualPositioning');
  String get pwWeeklyPositioning => _get('pwWeeklyPositioning');
  String get pwBenefitEveryRoom => _get('pwBenefitEveryRoom');
  String get pwBenefitUnlimited => _get('pwBenefitUnlimited');
  String get pwBenefitPriority => _get('pwBenefitPriority');
  String get pwBenefitHd => _get('pwBenefitHd');
  String get pwSavings => _get('pwSavings');
  String get pwSavingsShort => _get('pwSavingsShort');
  String get pwChoose => _get('pwChoose');
  String get pwBilledYearly => _get('pwBilledYearly');
  String get pwBilledWeekly => _get('pwBilledWeekly');
  String get pwHowItWorks => _get('pwHowItWorks');
  String get pwStep1 => _get('pwStep1');
  String get pwStep2 => _get('pwStep2');
  String get pwStep3 => _get('pwStep3');
  String get pwStep4 => _get('pwStep4');
  String get pwGuarantee => _get('pwGuarantee');
  String get pwGuaranteeSub => _get('pwGuaranteeSub');
  String get pwSecurePayments => _get('pwSecurePayments');
  String get pwFeatUnlimited => _get('pwFeatUnlimited');
  String get pwFeatHd => _get('pwFeatHd');
  String get pwFeatAllStyles => _get('pwFeatAllStyles');
  String get pwFeatNoWatermark => _get('pwFeatNoWatermark');
  String get pwPlanBadgeAnnual => _get('pwPlanBadgeAnnual');
  String get pwPlanBadgeWeekly => _get('pwPlanBadgeWeekly');
  String get pwAnnualSpaces => _get('pwAnnualSpaces');
  String get pwAnnualSpacesSub => _get('pwAnnualSpacesSub');
  String get pwWeeklySpaces => _get('pwWeeklySpaces');
  String get pwWeeklySpacesSub => _get('pwWeeklySpacesSub');
  String get pwUnlockPremium => _get('pwUnlockPremium');
  String get pwCancelAnytime => _get('pwCancelAnytime');
  String get pwAlreadySubscribed => _get('pwAlreadySubscribed');
  String get pwRestore => _get('pwRestore');
  String get pwNotNow => _get('pwNotNow');
  String get pwErrIncomplete => _get('pwErrIncomplete');
  String get pwErrNotAvailable => _get('pwErrNotAvailable');
  String get pwErrFailed => _get('pwErrFailed');
  String get pwErrNoRestore => _get('pwErrNoRestore');

  // ── Bottom navigation ─────────────────────────────────────────────────────
  String get navHome => _get('navHome');
  String get navProjects => _get('navProjects');
  String get navProfile => _get('navProfile');

  // ── Upload (new design flow + premium picker) ─────────────────────────────
  String get uplGenerateDesign => _get('uplGenerateDesign');
  String get uplWillCreate => _get('uplWillCreate');
  String get uplPrivacy => _get('uplPrivacy');
  String get uplPickerSubtitle => _get('uplPickerSubtitle');
  String get uplCamera => _get('uplCamera');
  String get uplGallery => _get('uplGallery');
  String get uplExamplePhotos => _get('uplExamplePhotos');
  String get uplExampleHint => _get('uplExampleHint');
  String get uplExampleLoadError => _get('uplExampleLoadError');
  String get uplOwnSpace => _get('uplOwnSpace');
  String get uplTryInstantly => _get('uplTryInstantly');
  String get uplOr => _get('uplOr');
  String get uplRecommended => _get('uplRecommended');
  String get uplMoreSpaces => _get('uplMoreSpaces');
  String get uplAiDecide => _get('uplAiDecide');
  String get uplAiDecideSub => _get('uplAiDecideSub');
  String get uplSurpriseMe => _get('uplSurpriseMe');
  String get uplSurpriseSub => _get('uplSurpriseSub');
  String get uplCustomSub => _get('uplCustomSub');
  String get uplStep1Sub => _get('uplStep1Sub');
  String get uplStep2Title => _get('uplStep2Title');
  String get uplStep2Sub => _get('uplStep2Sub');
  String get uplStep3Title => _get('uplStep3Title');
  String get uplStep3Sub => _get('uplStep3Sub');
  String get uplStep4Title => _get('uplStep4Title');
  String get uplStep4Sub => _get('uplStep4Sub');
  String get uplOptional => _get('uplOptional');
  String get uplStepperUpload => _get('uplStepperUpload');
  String get uplStepperRoom => _get('uplStepperRoom');
  String get uplStepperAtmosphere => _get('uplStepperAtmosphere');
  String get uplStepperVision => _get('uplStepperVision');
  String get uplHintAddPhoto => _get('uplHintAddPhoto');
  String get uplHintChooseRoom => _get('uplHintChooseRoom');
  String get uplHintPickAtmosphere => _get('uplHintPickAtmosphere');
  String uplStepBadge(int n) =>
      '${_get('uplStepWord')} $n ${_get('uplStepOf4')}';

  // ── Generation messages (#7 localization — were hardcoded English) ──────────
  String get genReadyAiSurprise => _get('genReadyAiSurprise');
  String get genReadySurprise => _get('genReadySurprise');
  String genReadyAiDecide(String style) =>
      _get('genReadyAiDecide').replaceAll('{style}', style);
  String genReadyDefault(String style) =>
      _get('genReadyDefault').replaceAll('{style}', style);
  String get genStartError => _get('genStartError');
  String get sessionUnavailable => _get('sessionUnavailable');
  String get reuploadError => _get('reuploadError');
  String get genLongWait => _get('genLongWait');
  String get genTransportInterrupted => _get('genTransportInterrupted');
  String get genTookLonger => _get('genTookLonger');
  String get continuingFromVision => _get('continuingFromVision');
  String get homeDesignReady => _get('homeDesignReady');
  String get homeDesignFailed => _get('homeDesignFailed');
  String get notifReadyTitle => _get('notifReadyTitle');
  String get notifReadyBody => _get('notifReadyBody');
  String get notifFailedTitle => _get('notifFailedTitle');
  String get notifFailedBody => _get('notifFailedBody');
  // BUG3 — action tappable de la notif in-app "ready" (→ ouvre la session).
  String get notifViewAction => _get('notifViewAction');

  // ── Premium / quota status card ───────────────────────────────────────────
  String get stFreePlan => _get('stFreePlan');
  String get stPremiumActive => _get('stPremiumActive');
  String get stAdminFullAccess => _get('stAdminFullAccess');
  String get stUnlimited => _get('stUnlimited');
  String freeGenerationsLeft(int n) =>
      '$n ${n == 1 ? _get('stGenerationSingular') : _get('stGenerationPlural')}';
  // BUG4 (RC-PR2b) — pass mesuré (weekly/annual) : crédits/générations restants.
  String stPassCreditsRemaining(int n) =>
      _get('stPassCreditsRemaining').replaceAll('{n}', '$n');
  String stPassValidUntil(String date) =>
      _get('stPassValidUntil').replaceAll('{date}', date);
  String get stRestoreRequired => _get('stRestoreRequired');
  String get stRestoreRequiredSub => _get('stRestoreRequiredSub');
  String get stRestoring => _get('stRestoring');

  // ── Chat reupload / design-direction sheet ────────────────────────────────
  String get chatPleaseUpload => _get('chatPleaseUpload');
  String get chatNewSourceMsg => _get('chatNewSourceMsg');
  String get chatEvolvingVision => _get('chatEvolvingVision');
  String get chatDesignEvolution => _get('chatDesignEvolution');
  String get chatSpaceType => _get('chatSpaceType');
  String get chatAtmosphere => _get('chatAtmosphere');
  String get chatApplyDirection => _get('chatApplyDirection');
  String get chatCurrent => _get('chatCurrent');

  // ── Profile sheets (settings) ─────────────────────────────────────────────
  String get spDisplayName => _get('spDisplayName');
  String get spFirstName => _get('spFirstName');
  String get spLastName => _get('spLastName');
  String get spEmail => _get('spEmail');
  String get spYourName => _get('spYourName');
  String get spSaveChanges => _get('spSaveChanges');
  String get spSaved => _get('spSaved');
  String get spSaveFailed => _get('spSaveFailed');
  String get spNotifSubtitle => _get('spNotifSubtitle');
  String get spNotif1Title => _get('spNotif1Title');
  String get spNotif1Sub => _get('spNotif1Sub');
  String get spNotif2Title => _get('spNotif2Title');
  String get spNotif2Sub => _get('spNotif2Sub');
  String get spNotif3Title => _get('spNotif3Title');
  String get spNotif3Sub => _get('spNotif3Sub');
  String get spNotif4Title => _get('spNotif4Title');
  String get spNotif4Sub => _get('spNotif4Sub');
  String get spPrivacyTitle => _get('spPrivacyTitle');
  String get spPrivacySubtitle => _get('spPrivacySubtitle');
  String get spPrivacy1Title => _get('spPrivacy1Title');
  String get spPrivacy1Body => _get('spPrivacy1Body');
  String get spPrivacy2Title => _get('spPrivacy2Title');
  String get spPrivacy2Body => _get('spPrivacy2Body');
  String get spPrivacy3Title => _get('spPrivacy3Title');
  String get spPrivacy3Body => _get('spPrivacy3Body');
  String get spPrivacyComingSoon => _get('spPrivacyComingSoon');
  String get spHelpSubtitle => _get('spHelpSubtitle');
  String get spFaq1Q => _get('spFaq1Q');
  String get spFaq1A => _get('spFaq1A');
  String get spFaq2Q => _get('spFaq2Q');
  String get spFaq2A => _get('spFaq2A');
  String get spFaq3Q => _get('spFaq3Q');
  String get spFaq3A => _get('spFaq3A');
  String get spFaq4Q => _get('spFaq4Q');
  String get spFaq4A => _get('spFaq4A');
  String get spStillNeedHelp => _get('spStillNeedHelp');
  String get spRateTitle => _get('spRateTitle');
  String get spRateSubtitle => _get('spRateSubtitle');
  String get spSubmit => _get('spSubmit');
  String get spThankYou => _get('spThankYou');
  String get spThankYouSub => _get('spThankYouSub');
  String get spClose => _get('spClose');
  String get spAboutVersion => _get('spAboutVersion');
  String get spAboutTagline => _get('spAboutTagline');
  String get spCopyright => _get('spCopyright');

  // ── Generation loading phrases ────────────────────────────────────────────
  String get genInit1 => _get('genInit1');
  String get genInit2 => _get('genInit2');
  String get genInit3 => _get('genInit3');
  String get genInit4 => _get('genInit4');
  String get genInit5 => _get('genInit5');
  String get genInit6 => _get('genInit6');
  String get genInit7 => _get('genInit7');
  String get genRef1 => _get('genRef1');
  String get genRef2 => _get('genRef2');
  String get genRef3 => _get('genRef3');
  String get genRef4 => _get('genRef4');
  String get genRef5 => _get('genRef5');
  String get genRef6 => _get('genRef6');
  String get genRef7 => _get('genRef7');
  List<String> get genInitPhrases =>
      [genInit1, genInit2, genInit3, genInit4, genInit5, genInit6, genInit7];
  List<String> get genRefinePhrases =>
      [genRef1, genRef2, genRef3, genRef4, genRef5, genRef6, genRef7];
  // Atmosphere-flavoured slot, keyed by a substring of the atmosphere name.
  String? genFlavor(String atmosphere) {
    final a = atmosphere.toLowerCase();
    const map = {
      'soft luxury': 'genFlavorSoftLuxury',
      'warm modern': 'genFlavorWarmModern',
      'japandi': 'genFlavorJapandi',
      'zen': 'genFlavorZen',
      'tropical': 'genFlavorTropical',
      'bali': 'genFlavorBali',
      'nordic': 'genFlavorNordic',
      'desert': 'genFlavorDesert',
      'nature retreat': 'genFlavorNatureRetreat',
    };
    for (final e in map.entries) {
      if (a.contains(e.key)) return _get(e.value);
    }
    return null;
  }

  // ── Hero ──────────────────────────────────────────────────────────────────
  String get featuredVision => _get('featuredVision');

  // ── Source photo ──────────────────────────────────────────────────────────
  String get sourcePhoto => _get('sourcePhoto');
  String get replacePhoto => _get('replacePhoto');
  String get sourcePhotoUpdated => _get('sourcePhotoUpdated');

  // Wave 5.16b — bimodal l10n getters (modeChooserTitle / modePreserve /
  // modePreserveSub / modeCreate / modeCreateSub) removed together with
  // the FTUE step 4 (Wave 5.16) and the chat sheet MODE toggle (5.16b).
  // Backend `generation_mode` still accepted ; UI no longer renders a
  // choice. Re-introduce here if creative mode ever returns to the UI.

  // ── Sprint 1B — Promo codes (redemption) ──────────────────────────────────
  String get promoHaveCode => _get('promoHaveCode');
  String get promoRedeemTitle => _get('promoRedeemTitle');
  String get promoRedeemSubtitle => _get('promoRedeemSubtitle');
  String get promoCodeHint => _get('promoCodeHint');
  String get promoApply => _get('promoApply');
  String get promoDone => _get('promoDone');
  String get promoSuccessUnlimited => _get('promoSuccessUnlimited');
  String promoSuccessLimited(int n) =>
      _get('promoSuccessLimited').replaceAll('{n}', '$n');
  String get promoAccessUnlimited => _get('promoAccessUnlimited');
  String get promoAccessLabel => _get('promoAccessLabel');
  String promoAccessLimited(int n) =>
      _get('promoAccessLimited').replaceAll('{n}', '$n');

  /// Maps a backend error_code → a localized message.
  String promoError(String code) {
    switch (code) {
      case 'invalid_code':
        return _get('promoErrInvalidCode');
      case 'expired_code':
        return _get('promoErrExpired');
      case 'inactive_code':
        return _get('promoErrInactive');
      case 'already_redeemed':
        return _get('promoErrAlready');
      case 'max_redemptions_reached':
        return _get('promoErrMaxRedemptions');
      case 'rate_limited':
        return _get('promoErrRateLimited');
      case 'network':
        return _get('promoErrNetwork');
      default:
        return _get('promoErrGeneric');
    }
  }

  // ── Sprint 1B — Admin promo panel ─────────────────────────────────────────
  String get admTitle => _get('admTitle');
  String get admPromoCodes => _get('admPromoCodes');
  String get admGenerateCode => _get('admGenerateCode');
  String get admType => _get('admType');
  String get admTypeLimited => _get('admTypeLimited');
  String get admTypeUnlimited => _get('admTypeUnlimited');
  String get admCustomCode => _get('admCustomCode');
  String get admCustomCodeHint => _get('admCustomCodeHint');
  String get admGenerationLimit => _get('admGenerationLimit');
  String get admMaxRedemptions => _get('admMaxRedemptions');
  String get admExpiresAt => _get('admExpiresAt');
  String get admExpiresNone => _get('admExpiresNone');
  String get admCampaign => _get('admCampaign');
  String get admNote => _get('admNote');
  String get admOptional => _get('admOptional');
  String get admCreate => _get('admCreate');
  String get admCreating => _get('admCreating');
  String get admCodesTitle => _get('admCodesTitle');
  String get admNoCodes => _get('admNoCodes');
  String get admActive => _get('admActive');
  String get admInactive => _get('admInactive');
  String get admDisable => _get('admDisable');
  String get admEnable => _get('admEnable');
  String get admCopy => _get('admCopy');
  String get admCopied => _get('admCopied');
  String get admUnlimited => _get('admUnlimited');
  String get admErrCreate => _get('admErrCreate');
  String get admErrConflict => _get('admErrConflict');
  String get admRedeemedLabel => _get('admRedeemedLabel');
}

// ── Delegate ──────────────────────────────────────────────────────────────────

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'km', 'fr'].contains(locale.languageCode);

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
