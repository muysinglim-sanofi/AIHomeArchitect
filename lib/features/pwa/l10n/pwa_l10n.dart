/// THE PWA's localization surface — one facade, two sources, zero duplication.
///
/// Why a facade and not a second dictionary
/// ----------------------------------------
/// The product is already translated. `lib/core/l10n` carries 424 approved keys
/// in English, Khmer and French, shipped in the mobile app, and that wording is
/// the terminology of record: "Vision", "Atmosphere", "Living Room", the
/// generation loading phrases, the room and atmosphere names. Re-translating any
/// of it here would produce a second Khmer vocabulary for the same product — the
/// exact failure this file exists to prevent.
///
/// So [PwaL10n] resolves in two steps:
///
///   1. a PWA-ONLY map (`pwa_translations.dart`) for copy that exists nowhere in
///      the mobile app — the web hero, drag & drop, the desktop navigation, the
///      billing access states introduced by the Billing Engine phase;
///   2. otherwise it forwards to [AppLocalizations], the mobile dictionary,
///      unchanged.
///
/// Widgets only ever touch `context.pwaL10n`. There is one lookup chain, one
/// fallback rule (locale -> English -> the key itself) and one place to add a
/// string, so nothing in the PWA can grow a `if (locale == 'km')` branch.
///
/// What must never be translated
/// -----------------------------
/// Canonical identifiers — `living_room`, `warm_modern`, `switch_atmosphere`,
/// `refine`, `QUOTA_EXHAUSTED` — are machine vocabulary. They key the DNA, the
/// lineage and the ledger. This file translates LABELS; ids pass through it
/// untouched, and `pwa_i18n_test.dart` proves the ids are byte-identical in all
/// three locales.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/atmosphere_style.dart';
import '../../../core/providers/locale_provider.dart';
import 'pwa_translations.dart';
import '../auth/pwa_verification_channel.dart' show PwaVerificationFailure;
import '../domain/pwa_project.dart' show PwaProjectSort;

class PwaL10n {
  const PwaL10n(this.locale, this._mobile);

  final Locale locale;
  final AppLocalizations _mobile;

  static PwaL10n of(BuildContext context) {
    final mobile = AppLocalizations.of(context);
    // Defensive: a widget rendered outside the app's Localizations scope (a
    // bare `pumpWidget` in a test) still gets English rather than a crash.
    final resolved = mobile ?? AppLocalizations(const Locale('en'));
    return PwaL10n(resolved.locale, resolved);
  }

  static const supportedLocales = AppLocalizations.supportedLocales;
  static const delegate = AppLocalizations.delegate;

  bool get isKhmer => locale.languageCode == 'km';
  bool get isFrench => locale.languageCode == 'fr';

  /// The MOBILE dictionary, for the keys it already owns. Public so a screen
  /// that needs an approved mobile string reads it from the one place it lives.
  AppLocalizations get shared => _mobile;

  String _get(String key) {
    final map = isFrench
        ? pwaFrTranslations
        : (isKhmer ? pwaKmTranslations : pwaEnTranslations);
    return map[key] ?? pwaEnTranslations[key] ?? key;
  }

  // ══ REUSED FROM MOBILE ═════════════════════════════════════════════════════
  // Every getter in this block forwards to the approved mobile wording. They
  // exist so a widget never has to decide which dictionary a string lives in.

  String get appName => _mobile.appName;
  String get beforeLabel => _mobile.beforeLabel;
  String get afterLabel => _mobile.afterLabel;
  String get vision => _mobile.vision;
  String get visions => _mobile.visions;
  String visionCount(int n) => _mobile.visionCount(n);
  String get today => _mobile.today;
  String get yesterday => _mobile.yesterday;
  String get lastUpdated => _mobile.lastUpdated;
  String get continueLabel => _mobile.continueLabel;
  String get skip => _mobile.skip;
  String get seeAll => _mobile.seeAll;
  String get newProject => _mobile.newProject;
  String get noProjects => _mobile.noProjects;
  String get continueDesigning => _mobile.continueDesigning;

  // ── iOS Home — the approved mobile wording, forwarded not re-translated ────
  // All three already exist in en/fr/km. Writing PWA copies would have created
  // a second Khmer vocabulary for the product's most-read screen.
  String get homeHeadline => _mobile.homeHeadline;
  String get newDesignSession => _mobile.newDesignSession;
  String get featuredVision => _mobile.featuredVision;
  String get recentTransformations => _mobile.recentTransformations;
  String get uploadYourSpace => _mobile.uploadYourSpace;
  String get uploadFileTypes => _mobile.uploadFileTypes;
  String get replacePhoto => _mobile.replacePhoto;
  String get sourcePhoto => _mobile.sourcePhoto;
  String get tryAnother => _mobile.tryAnother;
  String get viewBeforeAfter => _mobile.viewBeforeAfter;
  String get exploreOtherAtmospheres => _mobile.exploreOtherAtmospheres;
  String get yourTransformation => _mobile.yourTransformation;
  String get historyTitle => _mobile.historyTitle;
  String get transformations => _mobile.transformations;

  /// "3 redesigns", and "1 redesign" rather than "1 redesigns".
  ///
  /// The plural word is the mobile dictionary's, because it is the approved
  /// terminology of record in all three languages. Only the SINGULAR is owned
  /// here — that dictionary has none, and it belongs to the frozen mobile app.
  String transformationsCount(int n) => n == 1
      ? _get('pwaRedesignOne')
      : '$n ${_mobile.transformations}';
  String get navHome => _mobile.navHome;
  String get navProjects => _mobile.navProjects;
  String get chatPlaceholder => _mobile.chatPlaceholder;
  String get generateButton => _mobile.generateButton;
  String get uplAiDecide => _mobile.uplAiDecide;
  String get uplStepperRoom => _mobile.uplStepperRoom;
  String get uplStepperAtmosphere => _mobile.uplStepperAtmosphere;

  // ── iOS Create — the four steps, forwarded ────────────────────────────────
  // Every one of these already ships in en/fr/km inside the mobile dictionary
  // and is the wording a customer sees on the phone. Re-translating "Choose
  // your atmosphere" for the web would have produced a second Khmer sentence
  // for the same instruction — the failure this facade exists to prevent.
  //
  // `uplStepBadge` composes STEP + n + OF 4 in the mobile dictionary, so the
  // numeral sits where each language puts it rather than where English does.
  String uplStepBadge(int n) => _mobile.uplStepBadge(n);
  String get uplStep1Sub => _mobile.uplStep1Sub;
  String get uplStep2Title => _mobile.uplStep2Title;
  String get uplStep2Sub => _mobile.uplStep2Sub;
  String get uplStep3Title => _mobile.uplStep3Title;
  String get uplStep3Sub => _mobile.uplStep3Sub;
  String get uplStep4Title => _mobile.uplStep4Title;
  String get uplOptional => _mobile.uplOptional;
  String get uplPrivacy => _mobile.uplPrivacy;
  String get uplMoreSpaces => _mobile.uplMoreSpaces;
  String get uplGenerateDesign => _mobile.uplGenerateDesign;
  String get uplWillCreate => _mobile.uplWillCreate;
  String get uploadPrompt => _mobile.uploadPrompt;
  String get uploadTitle => _mobile.uploadTitle;

  /// Step 4's subtitle, and the ONE step string the web does not forward.
  ///
  /// Mobile says "Brief the architect in your own words. You can speak or
  /// type." — the second sentence is an offer of `VoiceService`, an iOS
  /// speech-to-text capability the web build does not have and that Phase 3 is
  /// not adding. Forwarding it verbatim would advertise a microphone that is
  /// not on the screen. Same instruction, same register, minus the promise the
  /// web cannot keep.
  String get step4Sub => _get('pwaStep4Sub');

  /// Placeholder inside the Step 4 field. Mobile hardcodes this one in English
  /// (`upload_screen.dart` builds it inline, not through the dictionary), so
  /// there is nothing to forward and the web supplies its own three locales.
  String get step4Hint => _get('pwaStep4Hint');
  String get settingsLanguage => _mobile.settingsLanguage;
  String get chooseLanguage => _mobile.chooseLanguage;
  String get english => _mobile.english;
  String get khmer => _mobile.khmer;
  String get french => _mobile.french;
  String get genLongWait => _mobile.genLongWait;
  String get genTookLonger => _mobile.genTookLonger;
  String get genTransportInterrupted => _mobile.genTransportInterrupted;
  String get genStartError => _mobile.genStartError;
  List<String> get genInitPhrases => _mobile.genInitPhrases;
  List<String> get genRefinePhrases => _mobile.genRefinePhrases;
  String? genFlavor(String atmosphere) => _mobile.genFlavor(atmosphere);
  String atmosphereTagline(String id) => _mobile.atmosphereTagline(id);
  String atmosphereSubtitle(String id) => _mobile.atmosphereSubtitle(id);

  /// The ROOM label, from the canonical id. The id is what the engine keys its
  /// DNA on and what `RoomTypeImages.enLabelForId` routes; this is only how it
  /// is spelled on screen.
  String roomLabel(String roomId) {
    switch (roomId) {
      case 'living_room':
        return _mobile.livingRoom;
      case 'master_bedroom':
      case 'bedroom':
        return _mobile.masterBedroom;
      case 'kitchen':
        return _mobile.kitchen;
      case 'bathroom':
        return _mobile.bathroom;
      case 'home_office':
      case 'office':
        return _mobile.homeOffice;
      case 'dining_room':
        return _mobile.diningRoom;
      case 'entrance_hall':
        return _mobile.entranceHall;
      case 'house_facade':
      case 'facade':
        return _mobile.houseFacade;
      case 'garden':
        return _mobile.garden;
      case 'pool_area':
        return _mobile.poolArea;
      case 'terrace':
        return _mobile.terrace;
      case 'balcony':
        return _mobile.balcony;
      case 'driveway':
        return _mobile.driveway;
      default:
        return '';
    }
  }

  /// The label of a ROOM CARD, from the card-catalog id.
  ///
  /// The catalog is keyed camelCase (`livingRoom`) while the engine's canonical
  /// ids are snake_case (`living_room`), so this bridges the two and then
  /// reuses the APPROVED mobile wording.
  ///
  /// DISPLAY ONLY. What is SENT to the backend stays `RoomCardData.label`, the
  /// English canonical label — the Room Type i18n contract is that the frontend
  /// routes the EN label and never the localized one, because the per-room DNA
  /// block is keyed on it. Localising the routed value would silently drop the
  /// room's DNA; localising the displayed value is simply correct.
  String roomCardLabel(String cardId, String fallback) {
    const toCanonical = {
      'livingRoom': 'living_room',
      'masterBedroom': 'master_bedroom',
      'kitchen': 'kitchen',
      'bathroom': 'bathroom',
      'terrace': 'terrace',
      'diningRoom': 'dining_room',
      'homeOffice': 'home_office',
      'balcony': 'balcony',
      'entranceHall': 'entrance_hall',
      'poolArea': 'pool_area',
      'garden': 'garden',
      'houseFacade': 'house_facade',
      'driveway': 'driveway',
    };
    final canonical = toCanonical[cardId];
    if (canonical == null) return fallback;
    final label = roomLabel(canonical);
    return label.isEmpty ? fallback : label;
  }

  /// ATMOSPHERE names are BRAND names and stay English on every platform —
  /// "Warm Modern", "Soft Luxury", "Japandi Calm". Mobile made that choice
  /// deliberately (`app_localizations.dart`: "names stay English brand; tagline
  /// + subtitle are localized by atmosphere id") and the PWA preserves it. Only
  /// the tagline and subtitle are localized, via [atmosphereTagline] /
  /// [atmosphereSubtitle].
  String atmosphereName(String atmosphereId) {
    for (final a in kAtmospheresOrdered) {
      if (a.id == atmosphereId) return a.name;
    }
    return '';
  }

  // ══ NEW, PWA-ONLY ══════════════════════════════════════════════════════════

  // Chrome / navigation (a desktop browser has affordances a phone has not).
  String get workspaceLabel => _get('pwaWorkspaceLabel');
  String get architectLabel => _get('pwaArchitectLabel');
  String get backHome => _get('pwaBackHome');
  String get myProjects => _get('pwaMyProjects');
  String get myProjectsCaps => _get('pwaMyProjectsCaps');
  String get newProjectAction => _get('pwaNewProjectAction');
  String get dismiss => _get('pwaDismiss');
  String get languageLabel => _get('pwaLanguageLabel');
  String get cancel => _get('pwaCancel');
  String get open => _get('pwaOpen');
  String get continueAction => _get('pwaContinueAction');

  // Home.
  String get heroLead => _get('pwaHeroLead');
  String get heroAccent => _get('pwaHeroAccent');
  String get heroSub => _get('pwaHeroSub');
  String get seeHowItWorks => _get('pwaSeeHowItWorks');
  String get contactSupport => _get('pwaContactSupport');

  /// The public version line. iOS's shared `spAboutVersion` reads
  /// "Version 1.0 · MVP Preview" — an internal phase label that has no
  /// business on a public screen; the web shows the version alone.
  String get aboutVersion => _get('pwaAboutVersion');
  String get continueDesigningEyebrow => _get('pwaContinueDesigningEyebrow');
  String get pickUpWhereYouLeftOff => _get('pwaPickUpWhereYouLeftOff');
  String get viewAllProjects => _get('pwaViewAllProjects');
  String get filterAll => _get('pwaFilterAll');
  String get yourSpaceFallback => _get('pwaYourSpaceFallback');

  // Create / upload.
  String get uploadCta => _get('pwaUploadCta');
  String get dragAndDropHint => _get('pwaDragAndDropHint');
  String get fileConstraints => _get('pwaFileConstraints');
  String get tipsForBestResults => _get('pwaTipsForBestResults');
  String get autoDetect => _get('pwaAutoDetect');
  String get stepRoom => _get('pwaStepRoom');
  String get stepAtmosphere => _get('pwaStepAtmosphere');
  String get moreRooms => _get('pwaMoreRooms');
  String get fewerRooms => _get('pwaFewerRooms');
  String get moreAtmospheres => _get('pwaMoreAtmospheres');
  String get fewerAtmospheres => _get('pwaFewerAtmospheres');
  String get createFirstVision => _get('pwaCreateFirstVision');
  String get removePhoto => _get('pwaRemovePhoto');
  String startWithExample(String label) =>
      _get('pwaStartWithExample').replaceAll('{label}', label);

  // First reveal / reveal.
  String get yourFirstVision => _get('pwaYourFirstVision');
  String get fullReveal => _get('pwaFullReveal');
  String get visionDetails => _get('pwaVisionDetails');
  String get atmospheresSection => _get('pwaAtmospheresSection');
  String get viewFullReveal => _get('pwaViewFullReveal');
  String get compare => _get('pwaCompare');
  String get usesOneSpace => _get('pwaUsesOneSpace');

  // Home, continued.
  String get createFirstVisionTitle => _get('pwaCreateFirstVisionTitle');
  String get readyToImagine => _get('pwaReadyToImagine');
  String get onePhotoIsAll => _get('pwaOnePhotoIsAll');
  String get startANewProject => _get('pwaStartANewProject');
  String openNamed(String title) =>
      _get('pwaOpenNamed').replaceAll('{title}', title);

  // Create, continued.
  String get tipBody => _get('pwaTipBody');
  String get selectedByAyden => _get('pwaSelectedByAyden');
  String get dataPrivate => _get('pwaDataPrivate');
  String get firstVisionFree => _get('pwaFirstVisionFree');
  String get orStartWithExample => _get('pwaOrStartWithExample');
  String get tryAnExample => _get('pwaTryAnExample');
  String get moreRoomsCaps => _get('pwaMoreRoomsCaps');
  String get moreAtmospheresCaps => _get('pwaMoreAtmospheresCaps');
  String get shapeYourSpace => _get('pwaShapeYourSpace');
  String get nowChooseRoomAndAtmosphere =>
      _get('pwaNowChooseRoomAndAtmosphere');
  String get addPhotoToStart => _get('pwaAddPhotoToStart');
  String get fastPathPrefix => _get('pwaFastPathPrefix');
  String get generateMyVision => _get('pwaGenerateMyVision');

  // Architect.
  String get editRequest => _get('pwaEditRequest');
  String get continueAnyway => _get('pwaContinueAnyway');
  String get chipWhatDoYouThink => _get('pwaChipWhatDoYouThink');
  String get chipWarmer => _get('pwaChipWarmer');
  String get chipMoreLight => _get('pwaChipMoreLight');
  String get chipOpenKitchen => _get('pwaChipOpenKitchen');
  String get openFullReveal => _get('pwaOpenFullReveal');
  String get refineThis => _get('pwaRefineThis');
  String get tryAnotherAtmosphere => _get('pwaTryAnotherAtmosphere');
  String get cancelRefinement => _get('pwaCancelRefinement');
  String get whatWouldYouLikeToChange => _get('pwaWhatWouldYouLikeToChange');
  String get applyThisChange => _get('pwaApplyThisChange');
  String get creating => _get('pwaCreating');
  String get createVision => _get('pwaCreateVision');
  String get askAydenAnything => _get('pwaAskAydenAnything');
  String get aydenDisclaimer => _get('pwaAydenDisclaimer');
  String get sendMessage => _get('pwaSendMessage');
  String get creatingYourVision => _get('pwaCreatingYourVision');
  String get noChangeUnderstood => _get('pwaNoChangeUnderstood');

  /// Ayden's opening line after the first vision.
  ///
  /// UI-OWNED, not a canonical chat turn: the controller reads it from the
  /// repository, so it never passes through `localize_reply` and stayed English
  /// for every reader. It is the FIRST thing Ayden says — measured in the
  /// browser sitting in English under a fully Khmer interface.
  /// Ayden's opening line on a first result. Takes the atmosphere the ENGINE
  /// resolved, so it names the direction that was actually rendered rather than
  /// the one that was asked for — "Ayden Signature" is a delegation, not a
  /// direction, and printing it back would tell the person nothing.
  String firstVisionIntro(String atmosphere) =>
      _get('pwaFirstVisionIntro').replaceAll('{name}', atmosphere);
  String get chipCalmer => _get('pwaChipCalmer');

  String visionN(int n) => _get('pwaVisionN').replaceAll('{n}', '$n');
  String visionNWithAtmosphere(int n, String name) => _get(
        'pwaVisionNWithAtmosphere',
      ).replaceAll('{n}', '$n').replaceAll('{name}', name);
  String openVisionInReveal(int n, String name) => _get(
        'pwaOpenVisionInReveal',
      ).replaceAll('{n}', '$n').replaceAll('{name}', name);
  String refiningVisionN(int n) =>
      _get('pwaRefiningVisionN').replaceAll('{n}', '$n');
  String createsVisionUsesSpace(int n) =>
      _get('pwaCreatesVisionUsesSpace').replaceAll('{n}', '$n');
  String switchTo(String name) =>
      _get('pwaSwitchTo').replaceAll('{name}', name);

  // The four beats of a render. The ORDER and the count are the existing
  // product behaviour; only the words are translated.
  List<String> get workRefinePhases => [
        _get('pwaWorkRefine1'),
        _get('pwaWorkRefine2'),
        _get('pwaWorkRefine3'),
        _get('pwaWorkRefine4'),
      ];
  List<String> get workInitialPhases => [
        _get('pwaWorkInitial1'),
        _get('pwaWorkInitial2'),
        _get('pwaWorkInitial3'),
        _get('pwaWorkInitial4'),
      ];
  List<String> get workSwitchPhases => [
        _get('pwaWorkSwitch1'),
        _get('pwaWorkSwitch2'),
        _get('pwaWorkSwitch3'),
        _get('pwaWorkSwitch4'),
      ];
  List<String> workSwitchNamedPhases(String name) => [
        _get('pwaWorkSwitchNamed1').replaceAll('{name}', name),
        _get('pwaWorkSwitchNamed2'),
        _get('pwaWorkSwitch3'),
        _get('pwaWorkSwitch4'),
      ];
  String get thinking => _get('pwaThinking');
  String get working => _get('pwaWorking');
  String get usuallyACoupleOfMinutes => _get('pwaUsuallyACoupleOfMinutes');

  // Reveal, continued.
  String get continueWithAyden => _get('pwaContinueWithAyden');
  String get backToConversation => _get('pwaBackToConversation');
  String get previousVision => _get('pwaPreviousVision');
  String get nextVision => _get('pwaNextVision');
  String get createdJustNow => _get('pwaCreatedJustNow');
  String get refineWithAyden => _get('pwaRefineWithAyden');
  String get continueInConversation => _get('pwaContinueInConversation');
  String get exploreDifferentStyle => _get('pwaExploreDifferentStyle');
  String get setAsCurrent => _get('pwaSetAsCurrent');
  String get continueFromThisVision => _get('pwaContinueFromThisVision');
  String visionOfTotal(int n, int total) => _get('pwaVisionOfTotal')
      .replaceAll('{n}', '$n')
      .replaceAll('{total}', '$total');
  String previewingVisionN(int n) =>
      _get('pwaPreviewingVisionN').replaceAll('{n}', '$n');
  String selectAtmosphere(String name) =>
      _get('pwaSelectAtmosphere').replaceAll('{name}', name);
  String atmosphereSelected(String name) =>
      _get('pwaAtmosphereSelected').replaceAll('{name}', name);
  String createsVisionN(int n) =>
      _get('pwaCreatesVisionN').replaceAll('{n}', '$n');

  // Versions sheet.
  String get originalUpload => _get('pwaOriginalUpload');
  String get yourVisions => _get('pwaYourVisions');
  String get currentBadge => _get('pwaCurrentBadge');
  String get findInChat => _get('pwaFindInChat');
  String get setCurrent => _get('pwaSetCurrent');
  String totalCount(int n) => _get('pwaTotalCount').replaceAll('{n}', '$n');
  String jumpedToVision(int n) =>
      _get('pwaJumpedToVision').replaceAll('{n}', '$n');
  String createdFrom(String name, String label) => _get('pwaCreatedFrom')
      .replaceAll('{name}', name)
      .replaceAll('{label}', label);
  String allCount(int n) => _get('pwaAllCount').replaceAll('{n}', '$n');

  // Projects.
  String get yourSpaces => _get('pwaYourSpaces');
  String get getMoreSpaces => _get('pwaGetMoreSpaces');
  String get searchProjects => _get('pwaSearchProjects');
  String get clearSearch => _get('pwaClearSearch');
  String get sortProjects => _get('pwaSortProjects');
  String get sortRecentlyUpdated => _get('pwaSortRecentlyUpdated');
  String get sortNewest => _get('pwaSortNewest');
  String get sortOldest => _get('pwaSortOldest');
  String get sortNameAz => _get('pwaSortNameAz');
  String get draftBadge => _get('pwaDraftBadge');
  String get save => _get('pwaSave');
  String get duplicate => _get('pwaDuplicate');
  String get delete => _get('pwaDelete');
  String get deleteProjectTitle => _get('pwaDeleteProjectTitle');
  String get updatedToday => _get('pwaUpdatedToday');
  String get contineShapingHome => _get('pwaContinueShapingHome');
  String get returnToProject => _get('pwaReturnToProject');
  String get openProject => _get('pwaOpenProject');
  String get projectOptions => _get('pwaProjectOptions');
  String get renameProject => _get('pwaRenameProject');
  String get rename => _get('pwaRename');
  String get yourNextSpace => _get('pwaYourNextSpace');
  String get uploadAndCreate => _get('pwaUploadAndCreate');
  String get noMatchingProjects => _get('pwaNoMatchingProjects');
  String get tryAnotherRoom => _get('pwaTryAnotherRoom');
  String get noProjectsFoundFor => _get('pwaNoProjectsFoundFor');
  String get oneProjectFoundFor => _get('pwaOneProjectFoundFor');
  String get untitledSpace => _get('pwaUntitledSpace');
  String get draftContinueSetup => _get('pwaDraftContinueSetup');
  String get continueSetup => _get('pwaContinueSetup');
  /// The label of a sort order.
  ///
  /// `PwaProjectSort.label` stays as it is: it is the English fallback and it
  /// sits next to the enum, where the SORTING semantics live. Nothing about the
  /// enum values or the ordering changes — only what the control says.
  String sortLabel(PwaProjectSort order) => switch (order) {
        PwaProjectSort.recentlyUpdated => sortRecentlyUpdated,
        PwaProjectSort.newest => sortNewest,
        PwaProjectSort.oldest => sortOldest,
        PwaProjectSort.nameAsc => sortNameAz,
      };

  String nProjectsFoundFor(int n) =>
      _get('pwaNProjectsFoundFor').replaceAll('{n}', '$n');
  String deleteProjectBody(String title) =>
      _get('pwaDeleteProjectBody').replaceAll('{title}', title);
  String updatedDaysAgo(int n) =>
      _get('pwaUpdatedDaysAgo').replaceAll('{n}', '$n');

  /// The freshness of a project, rendered in the CURRENT language.
  ///
  /// Deliberately a function of the TIMESTAMP rather than a translation of a
  /// pre-rendered English string: `updatedLabel` is baked in when a row is
  /// deserialised, long before anyone knows what language it will be read in,
  /// which is exactly why the project cards showed "2 days ago" inside a French
  /// UI. `updatedAt` is documented as the authority for freshness — so it is
  /// what gets formatted, at the moment of display.
  ///
  /// The bucket boundaries mirror `pwaRelativeUpdatedLabel` so the two never
  /// disagree; calendar days, not 24-hour windows, because something touched
  /// last night reads as "yesterday" to a person.
  String updatedRelative(DateTime updatedAt, {DateTime? now}) {
    final ref = (now ?? DateTime.now()).toUtc();
    final then = updatedAt.toUtc();
    final delta = ref.difference(then);
    if (delta.isNegative || delta.inMinutes < 1) return _get('pwaUpdatedJustNow');
    if (delta.inMinutes < 60) {
      return _get('pwaUpdatedMinutesAgo')
          .replaceAll('{n}', '${delta.inMinutes}');
    }
    final days = DateTime.utc(ref.year, ref.month, ref.day)
        .difference(DateTime.utc(then.year, then.month, then.day))
        .inDays;
    if (days == 0) return updatedToday;
    if (days == 1) return _get('pwaUpdatedYesterday');
    if (days < 7) return updatedDaysAgo(days);
    if (days < 14) return _get('pwaUpdatedLastWeek');
    if (days < 31) return _get('pwaUpdatedWeeksAgo').replaceAll('{n}', '${days ~/ 7}');
    final months = days ~/ 30;
    // 31 days is "1 months ago" without this, and 31 days is common.
    if (months <= 1) return _get('pwaUpdatedMonthAgoOne');
    return _get('pwaUpdatedMonthsAgo').replaceAll('{n}', '$months');
  }

  /// [updatedRelative] when the timestamp is known, the stored English label
  /// otherwise. Callers pass both and never have to branch.
  String updatedLabelFor(DateTime? updatedAt, String fallback) =>
      updatedAt == null ? fallback : updatedRelative(updatedAt);

  // Billing access states (Phase A). The BACKEND sends a code; this translates
  // it. No billing decision depends on the locale.
  String get freeVisionAvailable => _get('pwaFreeVisionAvailable');
  String get freeVisionWatermarked => _get('pwaFreeVisionWatermarked');
  String get billingFreeExhausted => _get('pwaBillingFreeExhausted');
  String get billingFreeExhaustedSub => _get('pwaBillingFreeExhaustedSub');
  String get billingPassRequired => _get('pwaBillingPassRequired');
  String get billingPassExhausted => _get('pwaBillingPassExhausted');
  String get billingUnavailable => _get('pwaBillingUnavailable');
  /// COUNTS ARE NOT INTERPOLATION.
  ///
  /// '{n} spaces left' with n = 1 reads "1 spaces left", and it was doing so on
  /// a real wallet. Khmer has no grammatical plural, so its singular and plural
  /// are the same sentence — written out rather than left as a gap, because a
  /// missing key falls back to English and that is worse than a duplicate.
  String passSpacesLeft(int n) => n == 1
      ? _get('pwaPassSpaceLeftOne')
      : _get('pwaPassSpacesLeft').replaceAll('{n}', '$n');

  /// A backend `billing_state` code -> the sentence a person reads.
  ///
  /// The switch is exhaustive on the codes `pwa_staging_billing._BILLING_STATE`
  /// can emit; anything unknown falls back to the generic exhausted message
  /// rather than showing a raw code.
  String billingState(String code) {
    switch (code) {
      case 'FREE_EXHAUSTED':
        return billingFreeExhausted;
      case 'PASS_REQUIRED':
        return billingPassRequired;
      case 'PASS_EXHAUSTED':
        return billingPassExhausted;
      case 'BILLING_UNAVAILABLE':
        return billingUnavailable;
      default:
        return billingFreeExhausted;
    }
  }

  // Errors surfaced by the generation API. Keyed by the backend's `error_code`
  // so the wording lives here and the transport carries a code (see §24 of the
  // monetization brief and `pwa_staging_billing._deny`).
  String get errSessionExpired => _get('pwaErrSessionExpired');
  String get errBackendUnreachable => _get('pwaErrBackendUnreachable');
  String get errTimeout => _get('pwaErrTimeout');
  String get errNetwork => _get('pwaErrNetwork');
  String get errGenerationFailed => _get('pwaErrGenerationFailed');
  String get errGenerationLost => _get('pwaErrGenerationLost');
  String get errCancelled => _get('pwaErrCancelled');
  String get errStillWorking => _get('pwaErrStillWorking');
  String get errUploadFailed => _get('pwaErrUploadFailed');
  String get errPrepareFailed => _get('pwaErrPrepareFailed');
  String get errSaveFailed => _get('pwaErrSaveFailed');
  String get errUnknown => _get('pwaErrUnknown');
  String get retry => _get('pwaRetry');

  String errorForCode(String code) {
    switch (code) {
      case 'SESSION_EXPIRED':
      case 'MISSING_TOKEN':
        return errSessionExpired;
      case 'BACKEND_UNREACHABLE':
        return errBackendUnreachable;
      case 'TIMEOUT':
        return errTimeout;
      case 'NETWORK_ERROR':
        return errNetwork;
      case 'GENERATION_FAILED':
      case 'ENGINE_REJECTED':
      case 'EMPTY_RESULT':
      case 'MALFORMED_RESPONSE':
        return errGenerationFailed;
      case 'GENERATION_LOST':
        return errGenerationLost;
      case 'CANCELLED':
        return errCancelled;
      case 'PROCESSING':
        return errStillWorking;
      case 'UPLOAD_FAILED':
        return errUploadFailed;
      case 'PREPARE_FAILED':
        return errPrepareFailed;
      case 'SAVE_FAILED':
      case 'PERSIST_FAILED':
        return errSaveFailed;
      case 'QUOTA_EXHAUSTED':
        return billingFreeExhausted;
      case 'BILLING_UNAVAILABLE':
        return billingUnavailable;
      default:
        return errUnknown;
    }
  }

  // ── Paywall ────────────────────────────────────────────────────────────────
  String get paywallTitle => _get('pwaPaywallTitle');
  String get paywallFreeUsedTitle => _get('pwaPaywallFreeUsedTitle');
  String get paywallFreeUsedBody => _get('pwaPaywallFreeUsedBody');
  String get paywallPassExhaustedTitle => _get('pwaPaywallPassExhaustedTitle');
  String get paywallPassExhaustedBody => _get('pwaPaywallPassExhaustedBody');
  String get paywallPassRequiredTitle => _get('pwaPaywallPassRequiredTitle');
  String get paywallPassRequiredBody => _get('pwaPaywallPassRequiredBody');
  String get paywallLoading => _get('pwaPaywallLoading');
  String get paywallErrorTitle => _get('pwaPaywallErrorTitle');
  String get paywallErrorBody => _get('pwaPaywallErrorBody');
  String get paywallActiveTitle => _get('pwaPaywallActiveTitle');
  String get paywallActiveBody => _get('pwaPaywallActiveBody');
  String paywallSpaces(int n) => n == 1
      ? _get('pwaPaywallSpaceOne')
      : _get('pwaPaywallSpaces').replaceAll('{n}', '$n');
  String paywallDays(int n) => _get('pwaPaywallDays').replaceAll('{n}', '$n');
  String get paywallUnavailableTitle => _get('pwaPaywallUnavailableTitle');
  String get paywallUnavailableBody => _get('pwaPaywallUnavailableBody');
  String get paywallStoreOnly => _get('pwaPaywallStoreOnly');
  String paywallDiscount(int n) =>
      _get('pwaPaywallDiscount').replaceAll('{n}', '$n');

  /// Translate a product's marketing badge CODE. Unknown codes render as
  /// nothing rather than as the raw code — a new badge added server-side must
  /// look absent here, never look like a bug leaking machine vocabulary at a
  /// customer.
  String productBadge(String code) => switch (code) {
        'starter' => _get('pwaProductBadgeStarter'),
        'popular' => _get('pwaProductBadgePopular'),
        'best_value' => _get('pwaProductBadgeBestValue'),
        _ => '',
      };
  String get paywallRestore => _get('pwaPaywallRestore');
  String get paywallClose => _get('pwaPaywallClose');
  String get paywallSecureNote => _get('pwaPaywallSecureNote');

  // ── Payment (ABA PayWay / KHQR) ────────────────────────────────────────────
  //
  // Every string a person sees while paying goes through here, including the
  // failure copy. The backend sends MACHINE codes — `AMOUNT_MISMATCH`,
  // `DECLINED`, `QR_REFUSED` — and [payFailedBody] is the one place that turns
  // a code into a sentence, so no widget ever renders a reason string raw and
  // no locale can drift from another.
  String get payBuy => _get('pwaPayBuy');
  String get payTitle => _get('pwaPayTitle');
  String get payPreparing => _get('pwaPayPreparing');
  String get payScanTitle => _get('pwaPayScanTitle');
  String get payScanBody => _get('pwaPayScanBody');
  String get payOpenAba => _get('pwaPayOpenAba');
  String get payClose => _get('pwaPayClose');
  String get payPluginOpen => _get('pwaPayPluginOpen');
  String get payInlineChecking => _get('pwaPayInlineChecking');
  String get payInlineCancel => _get('pwaPayInlineCancel');
  String get payOrScan => _get('pwaPayOrScan');
  String get payContinueToAba => _get('pwaPayContinueToAba');
  String get payOpenInNewTab => _get('pwaPayOpenInNewTab');
  String get acceptWeAccept => _get('pwaAcceptWeAccept');
  String get payMethodTitle => _get('pwaPayMethodTitle');
  String get payMethodBody => _get('pwaPayMethodBody');
  String get payHandoffBodyDesktop => _get('pwaPayHandoffBodyDesktop');
  String get payHandoffBodyPhone => _get('pwaPayHandoffBodyPhone');
  String get payLinkExpiredTitle => _get('pwaPayLinkExpiredTitle');
  String get payLinkExpiredBody => _get('pwaPayLinkExpiredBody');
  String get payReturnTitle => _get('pwaPayReturnTitle');
  String get payReturnBody => _get('pwaPayReturnBody');
  String payExpiresIn(String remaining) =>
      _get('pwaPayExpiresIn').replaceAll('{t}', remaining);
  String get payWaiting => _get('pwaPayWaiting');
  String get payConfirmingTitle => _get('pwaPayConfirmingTitle');
  String get payConfirmingBody => _get('pwaPayConfirmingBody');
  String get payActivatingTitle => _get('pwaPayActivatingTitle');
  String get payActivatingBody => _get('pwaPayActivatingBody');
  String get payContinue => _get('pwaPayContinue');
  String get payExpiredTitle => _get('pwaPayExpiredTitle');
  String get payExpiredBody => _get('pwaPayExpiredBody');
  String get payCancelledTitle => _get('pwaPayCancelledTitle');
  String get payCancelledBody => _get('pwaPayCancelledBody');
  String get payFailedTitle => _get('pwaPayFailedTitle');
  String get payUnreachableTitle => _get('pwaPayUnreachableTitle');
  String get payUnreachableBody => _get('pwaPayUnreachableBody');
  String get payRetry => _get('pwaPayRetry');

  // Ayden's RESULT card, after ABA's checkout (`pwa_payment_result.dart`):
  // the verdict, the purchase summary, the one action.
  String get payResultSuccessTitle => _get('pwaPayResultSuccessTitle');
  String payResultSuccessBody(int n) =>
      _get('pwaPayResultSuccessBody').replaceAll('{n}', '$n');
  String get payResultSummaryTitle => _get('pwaPayResultSummaryTitle');
  String get payResultNewBalance => _get('pwaPayResultNewBalance');
  String get payResultContinue => _get('pwaPayResultContinue');
  String get payResultFailedTitle => _get('pwaPayResultFailedTitle');
  String get payResultFailedBody => _get('pwaPayResultFailedBody');
  String get payResultFailedHint => _get('pwaPayResultFailedHint');
  String get payCancel => _get('pwaPayCancel');
  String get paySafeNote => _get('pwaPaySafeNote');

  /// The sentence for a machine failure code. Unknown codes fall back to the
  /// generic body rather than to the code itself — a person must never be shown
  /// `PRODUCT_UNMAPPED`.
  String payFailedBody(String reason, {bool newAttemptRequired = false}) {
    if (newAttemptRequired || reason == 'DUPLICATE_TRAN_ID') {
      return _get('pwaPayFailedNewAttempt');
    }
    return switch (reason.toUpperCase()) {
      'DECLINED' || 'CANCELLED' => _get('pwaPayFailedDeclined'),
      'AMOUNT_MISMATCH' ||
      'CURRENCY_MISMATCH' ||
      'AMOUNT_MISSING' =>
        _get('pwaPayFailedAmount'),
      'QR_REFUSED' || 'UNREACHABLE' => _get('pwaPayFailedProvider'),
      // PayWay refused before a transaction existed — the whitelist case.
      'NOT_CREATED' => _get('pwaPayFailedNotCreated'),
      _ => _get('pwaPayFailedBody'),
    };
  }

  // ── Account / verification ─────────────────────────────────────────────────
  String get accountTitle => _get('pwaAccountTitle');
  String get accountBody => _get('pwaAccountBody');
  String get accountEmailLabel => _get('pwaAccountEmailLabel');
  String get accountEmailHint => _get('pwaAccountEmailHint');
  String get accountSend => _get('pwaAccountSend');
  String get accountCodeTitle => _get('pwaAccountCodeTitle');
  String accountCodeBody(String email) =>
      _get('pwaAccountCodeBody').replaceAll('{email}', email);
  String get accountCodeLabel => _get('pwaAccountCodeLabel');
  String get accountVerify => _get('pwaAccountVerify');
  String get accountResend => _get('pwaAccountResend');
  String get accountChangeEmail => _get('pwaAccountChangeEmail');
  String accountSignedInAs(String email) =>
      _get('pwaAccountSignedInAs').replaceAll('{email}', email);
  String get accountSignOut => _get('pwaAccountSignOut');
  String get accountGuestLabel => _get('pwaAccountGuestLabel');
  String get accountLinkedTitle => _get('pwaAccountLinkedTitle');
  String get accountLinkedBody => _get('pwaAccountLinkedBody');
  String get accountSwitchedTitle => _get('pwaAccountSwitchedTitle');
  String get accountSwitchedBody => _get('pwaAccountSwitchedBody');
  String get accountExistsTitle => _get('pwaAccountExistsTitle');
  String get accountExistsBody => _get('pwaAccountExistsBody');
  String get accountSignInInstead => _get('pwaAccountSignInInstead');
  String get accountSignInTitle => _get('pwaAccountSignInTitle');

  /// The returning user's question, above the Sign in door.
  String get accountHaveOne => _get('pwaAccountHaveOne');

  // The Full Reveal's own chrome, mapped from iOS's floating circle buttons.
  String get replayReveal => _get('pwaReplayReveal');
  String get shareVision => _get('pwaShareVision');
  String shareVisionText(String title) =>
      _get('pwaShareVisionText').replaceAll('{title}', title);
  String get shareUnavailable => _get('pwaShareUnavailable');

  // The paywall's three headline lines are the SHARED dictionary's own — the
  // same strings the phone shows, already approved in en/km/fr. Reading them
  // through here keeps the paywall's copy in one place with the rest of its
  // text, and means no new string was invented for a screen that already had
  // one.
  String get paywallHeadlineLead => _mobile.pwHeadlineLead;
  String get paywallHeadlineTrail => _mobile.pwHeadlineTrail;
  String get paywallHeadlineAccent => _mobile.pwHeadlineAccent;
  String get accountSignInBody => _get('pwaAccountSignInBody');
  String get accountBackToLink => _get('pwaAccountBackToLink');
  String get authUnavailable => _get('pwaAuthUnavailable');

  /// A verification failure -> the sentence a person reads.
  ///
  /// `destinationAlreadyRegistered` is deliberately ABSENT: it is not an error
  /// message, it is a fork in the journey, and the sheet renders a whole screen
  /// for it. Anything that fell through to here would be mislabelled.
  String verificationFailure(PwaVerificationFailure f) {
    switch (f) {
      case PwaVerificationFailure.invalidDestination:
        return _get('pwaAuthErrInvalidEmail');
      case PwaVerificationFailure.invalidCode:
        return _get('pwaAuthErrInvalidCode');
      case PwaVerificationFailure.rateLimited:
        return _get('pwaAuthErrRateLimited');
      case PwaVerificationFailure.unavailable:
        return _get('pwaAuthErrUnavailable');
      case PwaVerificationFailure.destinationAlreadyRegistered:
      case PwaVerificationFailure.unknown:
        return _get('pwaAuthErrUnknown');
    }
  }
}

/// Resolve the dictionary WITHOUT a BuildContext.
///
/// [PwaController] produces user-facing error text and suggestion chips, and it
/// is a `StateNotifier` with a `ref` but no element in the tree. Rather than
/// give it a second, context-free copy of the strings — the exact duplication
/// this layer exists to prevent — it builds the SAME facade from the locale it
/// already watches. `AppLocalizations` is a plain object over three maps, so
/// constructing one costs nothing and needs no widget.
PwaL10n pwaL10nFor(Locale locale) =>
    PwaL10n(locale, AppLocalizations(locale));

/// `context.pwaL10n` — the ONLY accessor a PWA widget needs.
extension PwaBuildContextL10n on BuildContext {
  PwaL10n get pwaL10n => PwaL10n.of(this);
}

/// The three languages, in the order the selector shows them. Khmer first is
/// deliberate: this is a Cambodia-first product, and the selector should read
/// as such rather than as an English app with translations bolted on.
const List<Locale> kPwaLocaleOrder = [Locale('km'), Locale('en'), Locale('fr')];

/// The name of a language, written IN that language — the only labelling that
/// works when the person cannot read the current one.
/// The flag shown beside a language, in the language sheet and on the
/// Profile's Language row. Emoji, as the brief asked — rendered by the same
/// emoji fallback the Create screen's "✨" already relies on.
String pwaLanguageFlag(String code) {
  switch (code) {
    case 'km':
      return '🇰🇭';
    case 'fr':
      return '🇫🇷';
    default:
      return '🇬🇧';
  }
}

/// The short name that follows the flag: "ខ្មែរ", not the longer
/// "ភាសាខ្មែរ" ("Khmer language") the endonym helper keeps for the top bar.
String pwaLanguageShortName(String code) {
  switch (code) {
    case 'km':
      return 'ខ្មែរ';
    case 'fr':
      return 'Français';
    default:
      return 'English';
  }
}

/// "🇫🇷 Français" — flag and short name, as one string.
String pwaLanguageFlagLabel(String code) =>
    '${pwaLanguageFlag(code)} ${pwaLanguageShortName(code)}';

String pwaLanguageEndonym(String code) {
  switch (code) {
    case 'km':
      return 'ភាសាខ្មែរ';
    case 'fr':
      return 'Français';
    default:
      return 'English';
  }
}

/// Read the locale without a BuildContext (controllers, services, the
/// `ui_locale` sent to the canonical chat turn).
final pwaLocaleCodeProvider = Provider<String>(
  (ref) => ref.watch(localeProvider).languageCode,
);
