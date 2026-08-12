/// PWA-ONLY copy, in the three product languages.
///
/// Scope rule, enforced by review and by `pwa_i18n_test.dart`: a key belongs
/// here ONLY if the mobile dictionary has no equivalent. Everything the mobile
/// app already says — "Vision", "Original", "Redesigns", the room names, the
/// atmosphere taglines, the generation loading phrases — is read through
/// [PwaL10n]'s forwarding getters instead, so there is exactly one approved
/// wording per idea and the Khmer of the web product is the Khmer of the phone
/// product.
///
/// What is in here is genuinely web-only:
///   * a landing hero and a "see how it works" affordance a phone app has not;
///   * drag & drop, file constraints, a desktop-width navigation bar;
///   * the expand/collapse controls of the room and atmosphere grids;
///   * project search, sort, rename, duplicate — a library seen on a wide
///     screen;
///   * the four-beat working indicator the web architect screen runs;
///   * the billing access states introduced by the Billing Engine phase, which
///     did not exist on any surface before.
///
/// Tone follows mobile, deliberately and specifically: FR keeps "Vision",
/// "redesign", "espace", "ambiance", "filigrane"; KM keeps ទស្សនៈ (vision),
/// ទីកន្លែង (space), បរិយាកាស (atmosphere), គម្រោង (project), ការរចនាឡើងវិញ
/// (redesign). Brand nouns — AYDEN STUDIO, Ayden, Ayden Decide, Ayden
/// Signature, Premium, Space(s), and every atmosphere name — stay English on
/// every platform, exactly as they do on mobile.
///
/// `{n}`, `{name}`, `{title}`, `{label}`, `{total}` are substituted by the
/// [PwaL10n] method that owns the key. Every locale must carry every
/// placeholder its English counterpart carries; `pwa_i18n_test.dart` checks it.
library;

const Map<String, String> pwaEnTranslations = {
  // ── Chrome / navigation ────────────────────────────────────────────────────
  'pwaWorkspaceLabel': 'DESIGN WORKSPACE',
  'pwaArchitectLabel': 'AYDEN ARCHITECT',
  'pwaBackHome': 'Back home',
  'pwaMyProjects': 'My Projects',
  'pwaMyProjectsCaps': 'MY PROJECTS',
  'pwaNewProjectAction': 'New project',
  'pwaDismiss': 'Dismiss',
  'pwaLanguageLabel': 'Language',
  'pwaCancel': 'Cancel',
  'pwaOpen': 'Open',
  'pwaContinueAction': 'Continue',

  // ── Home ───────────────────────────────────────────────────────────────────
  'pwaHeroLead': 'Your home. ',
  'pwaHeroAccent': 'Reimagined.',
  'pwaHeroSub': 'Turn any room into a vision,\nin the blink of an eye.',
  'pwaSeeHowItWorks': 'See how it works',
  'pwaContinueDesigningEyebrow': 'CONTINUE DESIGNING',
  'pwaPickUpWhereYouLeftOff': 'Pick up where you left off.',
  'pwaViewAllProjects': 'View all projects',
  'pwaFilterAll': 'All',
  'pwaYourSpaceFallback': 'Your space',
  'pwaCreateFirstVisionTitle': 'Create your first vision',
  'pwaReadyToImagine': 'Ready to imagine something new?',
  'pwaOnePhotoIsAll': 'One photo is all Ayden needs to reimagine your space.',
  'pwaStartANewProject': 'Start a new project.',
  'pwaOpenNamed': 'Open {title}',

  // ── Create ─────────────────────────────────────────────────────────────────
  'pwaUploadCta': 'Upload a photo',
  'pwaDragAndDropHint': 'or drag & drop it here',
  'pwaFileConstraints': 'JPG, PNG or WebP · up to 10 MB',
  'pwaTipsForBestResults': 'Tips for best results',
  'pwaTipBody': 'Use a clear, well-lit photo of the room you want to transform.',
  'pwaAutoDetect': 'Auto-detect',
  'pwaSelectedByAyden': 'Selected by Ayden',
  'pwaDataPrivate': 'Your data is private and secure',
  'pwaFirstVisionFree': 'First vision free · No account required',
  'pwaOrStartWithExample': 'Or start with an example',
  'pwaTryAnExample': 'Try an example',
  'pwaStepRoom': '1. ROOM',
  'pwaStepAtmosphere': '2. ATMOSPHERE',
  'pwaMoreRooms': 'More rooms',
  'pwaFewerRooms': 'Fewer rooms',
  'pwaMoreRoomsCaps': 'MORE ROOMS',
  'pwaMoreAtmospheres': 'More atmospheres',
  'pwaFewerAtmospheres': 'Fewer atmospheres',
  'pwaMoreAtmospheresCaps': 'MORE ATMOSPHERES',
  'pwaCreateFirstVision': 'CREATE YOUR FIRST VISION',
  'pwaShapeYourSpace': 'Shape your space with Ayden.',
  'pwaNowChooseRoomAndAtmosphere':
      "Great! Now let's choose the room type\nand the atmosphere you love.",
  'pwaAddPhotoToStart':
      "Add a photo to get started, then we'll help you\ndesign it your way.",
  'pwaFastPathPrefix': 'Ayden will create your first vision using ',
  'pwaRemovePhoto': 'Remove photo',
  'pwaGenerateMyVision': 'Generate my vision',
  'pwaStartWithExample': 'Start with the {label} example',

  // ── Architect ──────────────────────────────────────────────────────────────
  'pwaChipWhatDoYouThink': 'What do you think?',
  'pwaChipWarmer': 'Make it warmer',
  'pwaChipMoreLight': 'More natural light',
  'pwaChipOpenKitchen': 'Open the kitchen',
  'pwaVisionN': 'Vision {n}',
  'pwaVisionNWithAtmosphere': 'Vision {n} · {name}',
  'pwaOpenVisionInReveal': 'Open Vision {n}, {name}, in the Full Reveal',
  'pwaViewFullReveal': 'View full reveal',
  'pwaOpenFullReveal': 'Open full reveal',
  'pwaRefineThis': 'Refine this',
  'pwaTryAnotherAtmosphere': 'Try another atmosphere',
  'pwaRefiningVisionN': 'Refining Vision {n}',
  'pwaCancelRefinement': 'Cancel refinement',
  'pwaWhatWouldYouLikeToChange': 'What would you like to change?',
  'pwaApplyThisChange': 'Apply this change?',
  'pwaCreatesVisionUsesSpace': 'Creates Vision {n} · Uses 1 Space',
  'pwaEditRequest': 'Edit request',
  'pwaContinueAnyway': 'Continue anyway',
  'pwaCreating': 'Creating…',
  'pwaCreateVision': 'Create vision',
  'pwaAskAydenAnything': 'Ask Ayden anything…',
  'pwaAydenDisclaimer': 'Ayden can make mistakes. Always review design details.',
  'pwaSendMessage': 'Send message',
  'pwaCreatingYourVision': 'Creating your vision…',
  'pwaFirstVisionIntro':
      'I created your first vision. I kept the room’s architecture and introduced warmer materials, softer lighting and a more refined balance — my signature direction. Explore the atmospheres below, or tell me what you’d like to change.',
  'pwaSwitchTo': 'Switch to {name}',
  'pwaNoChangeUnderstood':
      "I didn't catch a change to make there — tell me what you'd like "
      "different and I'll take care of it.",

  // ── Working indicator (the four beats of a render) ─────────────────────────
  'pwaWorkRefine1': 'Understanding your change',
  'pwaWorkRefine2': 'Reworking the layout',
  'pwaWorkRefine3': 'Designing your new space',
  'pwaWorkRefine4': 'Finishing your vision',
  'pwaWorkInitial1': 'Preparing your photo',
  'pwaWorkInitial2': 'Understanding your space',
  'pwaWorkInitial3': 'Creating your vision',
  'pwaWorkInitial4': 'Finishing the details',
  'pwaWorkSwitch1': 'Reading the room',
  'pwaWorkSwitch2': 'Shifting the materials',
  'pwaWorkSwitch3': 'Relighting the space',
  'pwaWorkSwitch4': 'Finishing your vision',
  'pwaWorkSwitchNamed1': 'Switching to {name}',
  'pwaWorkSwitchNamed2': 'Reworking the materials and atmosphere',
  'pwaThinking': 'Thinking',
  'pwaWorking': 'Working',
  'pwaUsuallyACoupleOfMinutes': 'This usually takes a couple of minutes.',

  // ── Reveal ─────────────────────────────────────────────────────────────────
  'pwaYourFirstVision': 'YOUR FIRST VISION',
  'pwaContinueWithAyden': 'Continue with Ayden',
  'pwaBackToConversation': 'Back to conversation',
  'pwaFullReveal': 'FULL REVEAL',
  'pwaVisionOfTotal': 'Vision {n} of {total}',
  'pwaPreviousVision': 'Previous vision',
  'pwaNextVision': 'Next vision',
  'pwaCreatedJustNow': 'Created just now',
  'pwaVisionDetails': 'VISION DETAILS',
  'pwaRefineWithAyden': 'Refine with Ayden',
  'pwaContinueInConversation': 'Continue this vision in the conversation',
  'pwaExploreDifferentStyle': 'Explore a different style',
  'pwaPreviewingVisionN': 'Previewing Vision {n}',
  'pwaSetAsCurrent': 'Set as current',
  'pwaContinueFromThisVision': 'Continue from this vision',
  'pwaSelectAtmosphere': 'Select {name} atmosphere',
  'pwaAtmosphereSelected': '{name} selected',
  'pwaCreatesVisionN': '· Creates Vision {n}',
  'pwaUsesOneSpace': '· Uses 1 Space',
  'pwaAtmospheresSection': 'ATMOSPHERES',
  'pwaCompare': 'Compare',

  // ── Versions sheet ─────────────────────────────────────────────────────────
  'pwaOriginalUpload': 'Original upload',
  'pwaYourVisions': 'Your visions',
  'pwaTotalCount': '{n} total',
  'pwaJumpedToVision': 'Jumped to Vision {n} in the conversation',
  'pwaCurrentBadge': 'Current',
  'pwaCreatedFrom': 'Created from {name} · {label}',
  'pwaFindInChat': 'Find in chat',
  'pwaSetCurrent': 'Set current',
  'pwaAllCount': 'All {n}',

  // ── Projects ───────────────────────────────────────────────────────────────
  'pwaYourSpaces': 'YOUR SPACES',
  'pwaContinueShapingHome': 'Continue shaping your home.',
  'pwaReturnToProject':
      'Return to a project, explore its visions, or begin a new space.',
  'pwaSearchProjects': 'Search your projects…',
  'pwaClearSearch': 'Clear search',
  'pwaSortProjects': 'Sort projects',
  'pwaSortRecentlyUpdated': 'Recently updated',
  'pwaSortNewest': 'Newest',
  'pwaSortOldest': 'Oldest',
  'pwaSortNameAz': 'Name A–Z',
  'pwaOpenProject': 'Open project',
  'pwaProjectOptions': 'Project options',
  'pwaDraftBadge': 'Draft',
  'pwaRenameProject': 'Rename project',
  'pwaRename': 'Rename',
  'pwaSave': 'Save',
  'pwaDuplicate': 'Duplicate',
  'pwaDelete': 'Delete',
  'pwaDeleteProjectTitle': 'Delete project?',
  'pwaDeleteProjectBody':
      'This removes “{title}” and its visions from your library. '
      'This cannot be undone.',
  'pwaYourNextSpace': 'Your next space starts here.',
  'pwaUploadAndCreate':
      'Upload a photo and create your first vision with Ayden.',
  'pwaNoMatchingProjects': 'No matching projects',
  'pwaTryAnotherRoom': 'Try another room, atmosphere, or project name.',
  'pwaNoProjectsFoundFor': 'No projects found for ',
  'pwaOneProjectFoundFor': '1 project found for ',
  'pwaNProjectsFoundFor': '{n} projects found for ',
  'pwaUntitledSpace': 'Untitled Space',
  'pwaDraftContinueSetup': 'Draft · Continue setup',
  'pwaContinueSetup': 'Continue setup',
  'pwaUpdatedToday': 'Updated today',
  'pwaUpdatedDaysAgo': 'Updated {n} days ago',
  'pwaUpdatedJustNow': 'Updated just now',
  'pwaUpdatedMinutesAgo': 'Updated {n} min ago',
  'pwaUpdatedYesterday': 'Yesterday',
  'pwaUpdatedLastWeek': 'Last week',
  'pwaUpdatedWeeksAgo': '{n} weeks ago',
  'pwaUpdatedMonthsAgo': '{n} months ago',

  // ── Billing access states ──────────────────────────────────────────────────
  'pwaFreeVisionAvailable': '1 free vision',
  'pwaFreeVisionWatermarked': 'Free visions carry the AYDEN mark.',
  'pwaBillingFreeExhausted': 'Your free vision has been used.',
  'pwaBillingFreeExhaustedSub':
      'Unlock AYDEN Studio to keep designing this space.',
  'pwaBillingPassRequired': 'A pass is required to continue.',
  'pwaBillingPassExhausted': 'Your pass has no spaces left.',
  'pwaBillingUnavailable':
      "We're finishing an update. Please try again in a moment.",
  'pwaPassSpacesLeft': '{n} spaces left',

  // ── Errors ─────────────────────────────────────────────────────────────────
  'pwaErrSessionExpired': 'Your session expired. Reload the page to continue.',
  'pwaErrBackendUnreachable': 'This build cannot reach a generation backend.',
  'pwaErrTimeout': 'This is taking longer than expected. Try again.',
  'pwaErrNetwork': 'Connection lost. Check your network and try again.',
  'pwaErrGenerationFailed':
      "Ayden couldn't complete this vision. You can try again.",
  'pwaErrGenerationLost':
      "Ayden couldn't find that generation. You can try again.",
  'pwaErrCancelled': 'That request was cancelled.',
  'pwaErrStillWorking':
      'Ayden is still working on this one. Give it a moment, then try again.',
  'pwaErrUploadFailed': "Your photo couldn't be uploaded. Try again.",
  'pwaErrPrepareFailed': "Your vision couldn't be prepared. Try again.",
  'pwaErrSaveFailed': 'Your vision could not be saved. Try again.',
  'pwaErrUnknown': 'Something went wrong. Try again.',
  'pwaRetry': 'Try again',
};

const Map<String, String> pwaKmTranslations = {
  // ── Chrome / navigation ────────────────────────────────────────────────────
  'pwaWorkspaceLabel': 'កន្លែង​ធ្វើការ​រចនា',
  'pwaArchitectLabel': 'AYDEN ARCHITECT',
  'pwaBackHome': 'ត្រឡប់​ទៅ​ដើម',
  'pwaMyProjects': 'គម្រោង​របស់​ខ្ញុំ',
  'pwaMyProjectsCaps': 'គម្រោង​របស់​ខ្ញុំ',
  'pwaNewProjectAction': 'គម្រោង​ថ្មី',
  'pwaDismiss': 'បិទ',
  'pwaLanguageLabel': 'ភាសា',
  'pwaCancel': 'បោះបង់',
  'pwaOpen': 'បើក',
  'pwaContinueAction': 'បន្ត',

  // ── Home ───────────────────────────────────────────────────────────────────
  'pwaHeroLead': 'ផ្ទះ​របស់​អ្នក ',
  'pwaHeroAccent': 'ស្រមៃ​ឡើង​វិញ។',
  'pwaHeroSub': 'ប្រែក្លាយ​បន្ទប់​ណាមួយ​ទៅ​ជា​ទស្សនៈ\nក្នុង​ពេល​តែ​ប៉ុន្មាន​វិនាទី។',
  'pwaSeeHowItWorks': 'មើល​របៀប​ដំណើរការ',
  'pwaContinueDesigningEyebrow': 'បន្ត​ការ​រចនា',
  'pwaPickUpWhereYouLeftOff': 'បន្ត​ពី​កន្លែង​ដែល​អ្នក​បាន​ឈប់។',
  'pwaViewAllProjects': 'មើល​គម្រោង​ទាំងអស់',
  'pwaFilterAll': 'ទាំងអស់',
  'pwaYourSpaceFallback': 'ទីកន្លែង​របស់​អ្នក',
  'pwaCreateFirstVisionTitle': 'បង្កើត​ទស្សនៈ​ដំបូង​របស់​អ្នក',
  'pwaReadyToImagine': 'រួចរាល់​ដើម្បី​ស្រមៃ​អ្វី​ថ្មី​ហើយ​ឬ​នៅ?',
  'pwaOnePhotoIsAll':
      'រូបថត​តែ​មួយ​សន្លឹក​គឺ​គ្រប់គ្រាន់​ឲ្យ Ayden ស្រមៃ​ទីកន្លែង​របស់​អ្នក​ឡើង​វិញ។',
  'pwaStartANewProject': 'ចាប់ផ្ដើម​គម្រោង​ថ្មី។',
  'pwaOpenNamed': 'បើក {title}',

  // ── Create ─────────────────────────────────────────────────────────────────
  'pwaUploadCta': 'ផ្ទុក​រូបថត',
  'pwaDragAndDropHint': 'ឬ​អូស​ទម្លាក់​នៅ​ទីនេះ',
  'pwaFileConstraints': 'JPG, PNG ឬ WebP · រហូត​ដល់ 10 MB',
  'pwaTipsForBestResults': 'គន្លឹះ​សម្រាប់​លទ្ធផល​ល្អ​បំផុត',
  'pwaTipBody':
      'ប្រើ​រូបថត​ច្បាស់ និង​មាន​ពន្លឺ​គ្រប់គ្រាន់​នៃ​បន្ទប់​ដែល​អ្នក​ចង់​បំប្លែង។',
  'pwaAutoDetect': 'រក​ឃើញ​ស្វ័យប្រវត្តិ',
  'pwaSelectedByAyden': 'ជ្រើស​ដោយ Ayden',
  'pwaDataPrivate': 'ទិន្នន័យ​របស់​អ្នក​ឯកជន និង​សុវត្ថិភាព',
  'pwaFirstVisionFree': 'ទស្សនៈ​ដំបូង​ឥត​គិត​ថ្លៃ · មិន​ចាំបាច់​មាន​គណនី',
  'pwaOrStartWithExample': 'ឬ​ចាប់ផ្ដើម​ជាមួយ​ឧទាហរណ៍',
  'pwaTryAnExample': 'សាកល្បង​ឧទាហរណ៍',
  'pwaStepRoom': '១. បន្ទប់',
  'pwaStepAtmosphere': '២. បរិយាកាស',
  'pwaMoreRooms': 'បន្ទប់​បន្ថែម',
  'pwaFewerRooms': 'បន្ទប់​តិច​ជាង',
  'pwaMoreRoomsCaps': 'បន្ទប់​បន្ថែម',
  'pwaMoreAtmospheres': 'បរិយាកាស​បន្ថែម',
  'pwaFewerAtmospheres': 'បរិយាកាស​តិច​ជាង',
  'pwaMoreAtmospheresCaps': 'បរិយាកាស​បន្ថែម',
  'pwaCreateFirstVision': 'បង្កើត​ទស្សនៈ​ដំបូង​របស់​អ្នក',
  'pwaShapeYourSpace': 'រៀបចំ​ទីកន្លែង​របស់​អ្នក​ជាមួយ Ayden។',
  'pwaNowChooseRoomAndAtmosphere':
      'ល្អ​ណាស់! ឥឡូវ​សូម​ជ្រើស​ប្រភេទ​បន្ទប់\nនិង​បរិយាកាស​ដែល​អ្នក​ចូល​ចិត្ត។',
  'pwaAddPhotoToStart':
      'បន្ថែម​រូបថត​ដើម្បី​ចាប់ផ្ដើម បន្ទាប់​មក​យើង​នឹង​ជួយ​អ្នក\nរចនា​តាម​របៀប​របស់​អ្នក។',
  'pwaFastPathPrefix': 'Ayden នឹង​បង្កើត​ទស្សនៈ​ដំបូង​របស់​អ្នក​ដោយ​ប្រើ ',
  'pwaRemovePhoto': 'លុប​រូបថត',
  'pwaGenerateMyVision': 'បង្កើត​ទស្សនៈ​របស់​ខ្ញុំ',
  'pwaStartWithExample': 'ចាប់ផ្ដើម​ជាមួយ​ឧទាហរណ៍ {label}',

  // ── Architect ──────────────────────────────────────────────────────────────
  'pwaChipWhatDoYouThink': 'តើ​អ្នក​គិត​យ៉ាង​ណា?',
  'pwaChipWarmer': 'ធ្វើ​ឱ្យ​ក្ដៅ​ជាង​នេះ',
  'pwaChipMoreLight': 'ពន្លឺ​ធម្មជាតិ​បន្ថែម',
  'pwaChipOpenKitchen': 'បើក​ផ្ទះ​បាយ',
  'pwaVisionN': 'ទស្សនៈ {n}',
  'pwaVisionNWithAtmosphere': 'ទស្សនៈ {n} · {name}',
  'pwaOpenVisionInReveal': 'បើក​ទស្សនៈ {n}, {name}, ក្នុង​ការ​បង្ហាញ​ពេញលេញ',
  'pwaViewFullReveal': 'មើល​ការ​បង្ហាញ​ពេញលេញ',
  'pwaOpenFullReveal': 'បើក​ការ​បង្ហាញ​ពេញលេញ',
  'pwaRefineThis': 'កែ​លម្អ​ទស្សនៈ​នេះ',
  'pwaTryAnotherAtmosphere': 'សាកល្បង​បរិយាកាស​ផ្សេង',
  'pwaRefiningVisionN': 'កំពុង​កែ​លម្អ​ទស្សនៈ {n}',
  'pwaCancelRefinement': 'បោះបង់​ការ​កែ​លម្អ',
  'pwaWhatWouldYouLikeToChange': 'តើ​អ្នក​ចង់​ផ្លាស់ប្ដូរ​អ្វី?',
  'pwaApplyThisChange': 'អនុវត្ត​ការ​ផ្លាស់ប្ដូរ​នេះ?',
  'pwaCreatesVisionUsesSpace': 'បង្កើត​ទស្សនៈ {n} · ប្រើ 1 Space',
  'pwaEditRequest': 'កែ​សំណើ',
  'pwaContinueAnyway': 'បន្ត​ទោះ​យ៉ាង​ណា',
  'pwaCreating': 'កំពុង​បង្កើត…',
  'pwaCreateVision': 'បង្កើត​ទស្សនៈ',
  'pwaAskAydenAnything': 'សួរ Ayden អ្វី​ក៏​បាន…',
  'pwaAydenDisclaimer':
      'Ayden អាច​មាន​កំហុស។ សូម​ពិនិត្យ​ព័ត៌មាន​លម្អិត​នៃ​ការ​រចនា​ជានិច្ច។',
  'pwaSendMessage': 'ផ្ញើ​សារ',
  'pwaCreatingYourVision': 'កំពុង​បង្កើត​ទស្សនៈ​របស់​អ្នក…',
  'pwaFirstVisionIntro':
      'ខ្ញុំ​បាន​បង្កើត​ទស្សនៈ​ដំបូង​របស់​អ្នក។ ខ្ញុំ​បាន​រក្សា​ស្ថាបត្យកម្ម​នៃ​បន្ទប់ ហើយ​បាន​បន្ថែម​សម្ភារៈ​ក្ដៅ​ជាង ពន្លឺ​ទន់​ភ្លន់ និង​តុល្យភាព​ដ៏​ប្រណីត — ទិសដៅ​ហត្ថលេខា​របស់​ខ្ញុំ។ ស្វែងរក​បរិយាកាស​ខាង​ក្រោម ឬ​ប្រាប់​ខ្ញុំ​ថា​អ្នក​ចង់​ផ្លាស់ប្ដូរ​អ្វី។',
  'pwaSwitchTo': 'ប្ដូរ​ទៅ {name}',
  'pwaNoChangeUnderstood':
      'ខ្ញុំ​មិន​យល់​ច្បាស់​ពី​ការ​ផ្លាស់ប្ដូរ​ទេ — សូម​ប្រាប់​ខ្ញុំ​ថា​អ្នក​ចង់​បាន​អ្វី​ខុស​ពី​នេះ '
      'ហើយ​ខ្ញុំ​នឹង​ចាត់ចែង​ជូន។',

  // ── Working indicator ──────────────────────────────────────────────────────
  'pwaWorkRefine1': 'កំពុង​យល់​ពី​ការ​ផ្លាស់ប្ដូរ​របស់​អ្នក',
  'pwaWorkRefine2': 'កំពុង​រៀបចំ​ប្លង់​ឡើង​វិញ',
  'pwaWorkRefine3': 'កំពុង​រចនា​ទីកន្លែង​ថ្មី​របស់​អ្នក',
  'pwaWorkRefine4': 'កំពុង​បញ្ចប់​ទស្សនៈ​របស់​អ្នក',
  'pwaWorkInitial1': 'កំពុង​រៀបចំ​រូបថត​របស់​អ្នក',
  'pwaWorkInitial2': 'កំពុង​យល់​ពី​ទីកន្លែង​របស់​អ្នក',
  'pwaWorkInitial3': 'កំពុង​បង្កើត​ទស្សនៈ​របស់​អ្នក',
  'pwaWorkInitial4': 'កំពុង​បញ្ចប់​ព័ត៌មាន​លម្អិត',
  'pwaWorkSwitch1': 'កំពុង​អាន​បន្ទប់',
  'pwaWorkSwitch2': 'កំពុង​ប្ដូរ​សម្ភារៈ',
  'pwaWorkSwitch3': 'កំពុង​ដាក់​ពន្លឺ​ឡើង​វិញ',
  'pwaWorkSwitch4': 'កំពុង​បញ្ចប់​ទស្សនៈ​របស់​អ្នក',
  'pwaWorkSwitchNamed1': 'កំពុង​ប្ដូរ​ទៅ {name}',
  'pwaWorkSwitchNamed2': 'កំពុង​រៀបចំ​សម្ភារៈ និង​បរិយាកាស​ឡើង​វិញ',
  'pwaThinking': 'កំពុង​គិត',
  'pwaWorking': 'កំពុង​ធ្វើការ',
  'pwaUsuallyACoupleOfMinutes': 'ជាធម្មតា​ចំណាយ​ពេល​ប្រហែល​ពីរ​បី​នាទី។',

  // ── Reveal ─────────────────────────────────────────────────────────────────
  'pwaYourFirstVision': 'ទស្សនៈ​ដំបូង​របស់​អ្នក',
  'pwaContinueWithAyden': 'បន្ត​ជាមួយ Ayden',
  'pwaBackToConversation': 'ត្រឡប់​ទៅ​ការ​សន្ទនា',
  'pwaFullReveal': 'ការ​បង្ហាញ​ពេញលេញ',
  'pwaVisionOfTotal': 'ទស្សនៈ {n} ក្នុង​ចំណោម {total}',
  'pwaPreviousVision': 'ទស្សនៈ​មុន',
  'pwaNextVision': 'ទស្សនៈ​បន្ទាប់',
  'pwaCreatedJustNow': 'បង្កើត​អម្បាញ់​មិញ',
  'pwaVisionDetails': 'ព័ត៌មាន​លម្អិត​ទស្សនៈ',
  'pwaRefineWithAyden': 'កែ​លម្អ​ជាមួយ Ayden',
  'pwaContinueInConversation': 'បន្ត​ទស្សនៈ​នេះ​ក្នុង​ការ​សន្ទនា',
  'pwaExploreDifferentStyle': 'ស្វែងរក​រចនាបថ​ផ្សេង',
  'pwaPreviewingVisionN': 'កំពុង​មើល​ទស្សនៈ {n}',
  'pwaSetAsCurrent': 'កំណត់​ជា​បច្ចុប្បន្ន',
  'pwaContinueFromThisVision': 'បន្ត​ពី​ទស្សនៈ​នេះ',
  'pwaSelectAtmosphere': 'ជ្រើស​បរិយាកាស {name}',
  'pwaAtmosphereSelected': 'បាន​ជ្រើស {name}',
  'pwaCreatesVisionN': '· បង្កើត​ទស្សនៈ {n}',
  'pwaUsesOneSpace': '· ប្រើ 1 Space',
  'pwaAtmospheresSection': 'បរិយាកាស',
  'pwaCompare': 'ប្រៀបធៀប',

  // ── Versions sheet ─────────────────────────────────────────────────────────
  'pwaOriginalUpload': 'រូបថត​ដើម​ដែល​បាន​ផ្ទុក',
  'pwaYourVisions': 'ទស្សនៈ​របស់​អ្នក',
  'pwaTotalCount': 'សរុប {n}',
  'pwaJumpedToVision': 'បាន​លោត​ទៅ​ទស្សនៈ {n} ក្នុង​ការ​សន្ទនា',
  'pwaCurrentBadge': 'បច្ចុប្បន្ន',
  'pwaCreatedFrom': 'បង្កើត​ពី {name} · {label}',
  'pwaFindInChat': 'រក​ក្នុង​ការ​សន្ទនា',
  'pwaSetCurrent': 'កំណត់​បច្ចុប្បន្ន',
  'pwaAllCount': 'ទាំងអស់ {n}',

  // ── Projects ───────────────────────────────────────────────────────────────
  'pwaYourSpaces': 'ទីកន្លែង​របស់​អ្នក',
  'pwaContinueShapingHome': 'បន្ត​រៀបចំ​ផ្ទះ​របស់​អ្នក។',
  'pwaReturnToProject':
      'ត្រឡប់​ទៅ​គម្រោង​មួយ ស្វែងរក​ទស្សនៈ​របស់​វា ឬ​ចាប់ផ្ដើម​ទីកន្លែង​ថ្មី។',
  'pwaSearchProjects': 'ស្វែងរក​គម្រោង​របស់​អ្នក…',
  'pwaClearSearch': 'សម្អាត​ការ​ស្វែងរក',
  'pwaSortProjects': 'តម្រៀប​គម្រោង',
  'pwaSortRecentlyUpdated': 'ធ្វើ​បច្ចុប្បន្នភាព​ថ្មីៗ',
  'pwaSortNewest': 'ថ្មី​បំផុត',
  'pwaSortOldest': 'ចាស់​បំផុត',
  'pwaSortNameAz': 'ឈ្មោះ ក–អ',
  'pwaOpenProject': 'បើក​គម្រោង',
  'pwaProjectOptions': 'ជម្រើស​គម្រោង',
  'pwaDraftBadge': 'សេចក្ដី​ព្រាង',
  'pwaRenameProject': 'ប្ដូរ​ឈ្មោះ​គម្រោង',
  'pwaRename': 'ប្ដូរ​ឈ្មោះ',
  'pwaSave': 'រក្សា​ទុក',
  'pwaDuplicate': 'ចម្លង',
  'pwaDelete': 'លុប',
  'pwaDeleteProjectTitle': 'លុប​គម្រោង​នេះ?',
  'pwaDeleteProjectBody':
      'នេះ​នឹង​លុប “{title}” និង​ទស្សនៈ​របស់​វា​ចេញ​ពី​បណ្ណាល័យ​របស់​អ្នក។ '
      'វា​មិន​អាច​ត្រឡប់​វិញ​បាន​ទេ។',
  'pwaYourNextSpace': 'ទីកន្លែង​បន្ទាប់​របស់​អ្នក​ចាប់ផ្ដើម​នៅ​ទីនេះ។',
  'pwaUploadAndCreate':
      'ផ្ទុក​រូបថត ហើយ​បង្កើត​ទស្សនៈ​ដំបូង​របស់​អ្នក​ជាមួយ Ayden។',
  'pwaNoMatchingProjects': 'គ្មាន​គម្រោង​ត្រូវ​គ្នា',
  'pwaTryAnotherRoom': 'សាកល្បង​បន្ទប់ បរិយាកាស ឬ​ឈ្មោះ​គម្រោង​ផ្សេង។',
  'pwaNoProjectsFoundFor': 'រក​មិន​ឃើញ​គម្រោង​សម្រាប់ ',
  'pwaOneProjectFoundFor': 'រក​ឃើញ 1 គម្រោង​សម្រាប់ ',
  'pwaNProjectsFoundFor': 'រក​ឃើញ {n} គម្រោង​សម្រាប់ ',
  'pwaUntitledSpace': 'ទីកន្លែង​គ្មាន​ឈ្មោះ',
  'pwaDraftContinueSetup': 'សេចក្ដី​ព្រាង · បន្ត​ការ​រៀបចំ',
  'pwaContinueSetup': 'បន្ត​ការ​រៀបចំ',
  'pwaUpdatedToday': 'ធ្វើ​បច្ចុប្បន្នភាព​ថ្ងៃ​នេះ',
  'pwaUpdatedDaysAgo': 'ធ្វើ​បច្ចុប្បន្នភាព {n} ថ្ងៃ​មុន',
  'pwaUpdatedJustNow': 'ធ្វើ​បច្ចុប្បន្នភាព​អម្បាញ់​មិញ',
  'pwaUpdatedMinutesAgo': 'ធ្វើ​បច្ចុប្បន្នភាព {n} នាទី​មុន',
  'pwaUpdatedYesterday': 'ម្សិល​មិញ',
  'pwaUpdatedLastWeek': 'សប្ដាហ៍​មុន',
  'pwaUpdatedWeeksAgo': '{n} សប្ដាហ៍​មុន',
  'pwaUpdatedMonthsAgo': '{n} ខែ​មុន',

  // ── Billing access states ──────────────────────────────────────────────────
  'pwaFreeVisionAvailable': 'ទស្សនៈ​ឥត​គិត​ថ្លៃ 1',
  'pwaFreeVisionWatermarked': 'ទស្សនៈ​ឥត​គិត​ថ្លៃ​មាន​ស្លាក​ទឹក AYDEN។',
  'pwaBillingFreeExhausted': 'ទស្សនៈ​ឥត​គិត​ថ្លៃ​របស់​អ្នក​ត្រូវ​បាន​ប្រើ​អស់​ហើយ។',
  'pwaBillingFreeExhaustedSub':
      'ដោះ​សោ AYDEN Studio ដើម្បី​បន្ត​រចនា​ទីកន្លែង​នេះ។',
  'pwaBillingPassRequired': 'ត្រូវការ Pass ដើម្បី​បន្ត។',
  'pwaBillingPassExhausted': 'Pass របស់​អ្នក​អស់ Spaces ហើយ។',
  'pwaBillingUnavailable':
      'យើង​កំពុង​បញ្ចប់​ការ​ធ្វើ​បច្ចុប្បន្នភាព។ សូម​ព្យាយាម​ម្ដង​ទៀត​ក្នុង​ពេល​ឆាប់ៗ។',
  'pwaPassSpacesLeft': 'នៅ​សល់ {n} Spaces',

  // ── Errors ─────────────────────────────────────────────────────────────────
  'pwaErrSessionExpired': 'វគ្គ​របស់​អ្នក​ផុត​កំណត់។ សូម​ផ្ទុក​ទំព័រ​ឡើង​វិញ​ដើម្បី​បន្ត។',
  'pwaErrBackendUnreachable': 'កំណែ​នេះ​មិន​អាច​ភ្ជាប់​ទៅ​ម៉ាស៊ីន​បម្រើ​បង្កើត​បាន​ទេ។',
  'pwaErrTimeout': 'វា​ចំណាយ​ពេល​យូរ​ជាង​ការ​រំពឹង​ទុក។ សូម​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaErrNetwork': 'បាត់​ការ​តភ្ជាប់។ សូម​ពិនិត្យ​បណ្ដាញ ហើយ​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaErrGenerationFailed':
      'Ayden មិន​អាច​បញ្ចប់​ទស្សនៈ​នេះ​បាន​ទេ។ អ្នក​អាច​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaErrGenerationLost':
      'Ayden រក​មិន​ឃើញ​ការ​បង្កើត​នោះ​ទេ។ អ្នក​អាច​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaErrCancelled': 'សំណើ​នោះ​ត្រូវ​បាន​បោះបង់។',
  'pwaErrStillWorking':
      'Ayden នៅ​តែ​កំពុង​ធ្វើការ​លើ​ការ​នេះ។ សូម​រង់ចាំ​បន្តិច រួច​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaErrUploadFailed': 'រូបថត​របស់​អ្នក​មិន​អាច​ផ្ទុក​បាន​ទេ។ សូម​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaErrPrepareFailed': 'ទស្សនៈ​របស់​អ្នក​មិន​អាច​រៀបចំ​បាន​ទេ។ សូម​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaErrSaveFailed': 'ទស្សនៈ​របស់​អ្នក​មិន​អាច​រក្សា​ទុក​បាន​ទេ។ សូម​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaErrUnknown': 'មាន​អ្វី​មួយ​មិន​ប្រក្រតី។ សូម​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaRetry': 'ព្យាយាម​ម្ដង​ទៀត',
};

const Map<String, String> pwaFrTranslations = {
  // ── Chrome / navigation ────────────────────────────────────────────────────
  'pwaWorkspaceLabel': 'ESPACE DE DESIGN',
  'pwaArchitectLabel': 'AYDEN ARCHITECT',
  'pwaBackHome': "Retour à l'accueil",
  'pwaMyProjects': 'Mes projets',
  'pwaMyProjectsCaps': 'MES PROJETS',
  'pwaNewProjectAction': 'Nouveau projet',
  'pwaDismiss': 'Fermer',
  'pwaLanguageLabel': 'Langue',
  'pwaCancel': 'Annuler',
  'pwaOpen': 'Ouvrir',
  'pwaContinueAction': 'Continuer',

  // ── Home ───────────────────────────────────────────────────────────────────
  'pwaHeroLead': 'Votre maison. ',
  'pwaHeroAccent': 'Réimaginée.',
  'pwaHeroSub': "Transformez n'importe quelle pièce en vision,\nen un clin d'œil.",
  'pwaSeeHowItWorks': 'Voir comment ça marche',
  'pwaContinueDesigningEyebrow': 'CONTINUER LE DESIGN',
  'pwaPickUpWhereYouLeftOff': 'Reprenez où vous vous étiez arrêté.',
  'pwaViewAllProjects': 'Voir tous les projets',
  'pwaFilterAll': 'Tous',
  'pwaYourSpaceFallback': 'Votre espace',
  'pwaCreateFirstVisionTitle': 'Créez votre première vision',
  'pwaReadyToImagine': "Prêt à imaginer quelque chose de nouveau ?",
  'pwaOnePhotoIsAll':
      "Une seule photo suffit à Ayden pour réimaginer votre espace.",
  'pwaStartANewProject': 'Commencez un nouveau projet.',
  'pwaOpenNamed': 'Ouvrir {title}',

  // ── Create ─────────────────────────────────────────────────────────────────
  'pwaUploadCta': 'Importer une photo',
  'pwaDragAndDropHint': 'ou glissez-déposez-la ici',
  'pwaFileConstraints': "JPG, PNG ou WebP · jusqu'à 10 Mo",
  'pwaTipsForBestResults': 'Conseils pour un meilleur résultat',
  'pwaTipBody':
      'Utilisez une photo nette et bien éclairée de la pièce à transformer.',
  'pwaAutoDetect': 'Détection auto',
  'pwaSelectedByAyden': 'Sélectionné par Ayden',
  'pwaDataPrivate': 'Vos données sont privées et sécurisées',
  'pwaFirstVisionFree': 'Première vision offerte · Sans compte',
  'pwaOrStartWithExample': 'Ou commencez avec un exemple',
  'pwaTryAnExample': 'Essayer un exemple',
  'pwaStepRoom': '1. PIÈCE',
  'pwaStepAtmosphere': '2. AMBIANCE',
  'pwaMoreRooms': 'Plus de pièces',
  'pwaFewerRooms': 'Moins de pièces',
  'pwaMoreRoomsCaps': 'PLUS DE PIÈCES',
  'pwaMoreAtmospheres': "Plus d'ambiances",
  'pwaFewerAtmospheres': "Moins d'ambiances",
  'pwaMoreAtmospheresCaps': "PLUS D'AMBIANCES",
  'pwaCreateFirstVision': 'CRÉER VOTRE PREMIÈRE VISION',
  'pwaShapeYourSpace': 'Façonnez votre espace avec Ayden.',
  'pwaNowChooseRoomAndAtmosphere':
      "Parfait ! Choisissons le type de pièce\net l'ambiance que vous aimez.",
  'pwaAddPhotoToStart':
      "Ajoutez une photo pour commencer, puis nous vous aiderons\nà la dessiner à votre façon.",
  'pwaFastPathPrefix': 'Ayden va créer votre première vision avec ',
  'pwaRemovePhoto': 'Retirer la photo',
  'pwaGenerateMyVision': 'Générer ma vision',
  'pwaStartWithExample': "Commencer avec l'exemple {label}",

  // ── Architect ──────────────────────────────────────────────────────────────
  'pwaChipWhatDoYouThink': "Qu'en pensez-vous ?",
  'pwaChipWarmer': 'Rends-le plus chaleureux',
  'pwaChipMoreLight': 'Plus de lumière naturelle',
  'pwaChipOpenKitchen': 'Ouvre la cuisine',
  'pwaVisionN': 'Vision {n}',
  'pwaVisionNWithAtmosphere': 'Vision {n} · {name}',
  'pwaOpenVisionInReveal':
      'Ouvrir la Vision {n}, {name}, dans la révélation complète',
  'pwaViewFullReveal': 'Voir la révélation complète',
  'pwaOpenFullReveal': 'Ouvrir la révélation complète',
  'pwaRefineThis': 'Affiner cette vision',
  'pwaTryAnotherAtmosphere': 'Essayer une autre ambiance',
  'pwaRefiningVisionN': 'Affinage de la Vision {n}',
  'pwaCancelRefinement': "Annuler l'affinage",
  'pwaWhatWouldYouLikeToChange': 'Que souhaitez-vous changer ?',
  'pwaApplyThisChange': 'Appliquer ce changement ?',
  'pwaCreatesVisionUsesSpace': 'Crée la Vision {n} · Utilise 1 Space',
  'pwaEditRequest': 'Modifier la demande',
  'pwaContinueAnyway': 'Continuer quand même',
  'pwaCreating': 'Création…',
  'pwaCreateVision': 'Créer la vision',
  'pwaAskAydenAnything': 'Posez une question à Ayden…',
  'pwaAydenDisclaimer':
      'Ayden peut se tromper. Vérifiez toujours les détails du design.',
  'pwaSendMessage': 'Envoyer le message',
  'pwaCreatingYourVision': 'Création de votre vision…',
  'pwaFirstVisionIntro':
      "J'ai créé votre première vision. J'ai conservé l'architecture de la pièce et introduit des matières plus chaleureuses, une lumière plus douce et un équilibre plus raffiné — ma direction signature. Explorez les ambiances ci-dessous, ou dites-moi ce que vous souhaitez changer.",
  'pwaSwitchTo': 'Passer à {name}',
  'pwaNoChangeUnderstood':
      "Je n'ai pas saisi le changement à faire — dites-moi ce que vous "
      "voulez de différent et je m'en occupe.",

  // ── Working indicator ──────────────────────────────────────────────────────
  'pwaWorkRefine1': 'Compréhension de votre changement',
  'pwaWorkRefine2': 'Reprise de la disposition',
  'pwaWorkRefine3': 'Conception de votre nouvel espace',
  'pwaWorkRefine4': 'Finition de votre vision',
  'pwaWorkInitial1': 'Préparation de votre photo',
  'pwaWorkInitial2': 'Compréhension de votre espace',
  'pwaWorkInitial3': 'Création de votre vision',
  'pwaWorkInitial4': 'Finition des détails',
  'pwaWorkSwitch1': 'Lecture de la pièce',
  'pwaWorkSwitch2': 'Changement des matières',
  'pwaWorkSwitch3': "Nouvel éclairage de l'espace",
  'pwaWorkSwitch4': 'Finition de votre vision',
  'pwaWorkSwitchNamed1': 'Passage à {name}',
  'pwaWorkSwitchNamed2': "Reprise des matières et de l'ambiance",
  'pwaThinking': 'Réflexion',
  'pwaWorking': 'En cours',
  'pwaUsuallyACoupleOfMinutes': 'Cela prend généralement une à deux minutes.',

  // ── Reveal ─────────────────────────────────────────────────────────────────
  'pwaYourFirstVision': 'VOTRE PREMIÈRE VISION',
  'pwaContinueWithAyden': 'Continuer avec Ayden',
  'pwaBackToConversation': 'Retour à la conversation',
  'pwaFullReveal': 'RÉVÉLATION COMPLÈTE',
  'pwaVisionOfTotal': 'Vision {n} sur {total}',
  'pwaPreviousVision': 'Vision précédente',
  'pwaNextVision': 'Vision suivante',
  'pwaCreatedJustNow': "Créée à l'instant",
  'pwaVisionDetails': 'DÉTAILS DE LA VISION',
  'pwaRefineWithAyden': 'Affiner avec Ayden',
  'pwaContinueInConversation': 'Continuer cette vision dans la conversation',
  'pwaExploreDifferentStyle': 'Explorer un autre style',
  'pwaPreviewingVisionN': 'Aperçu de la Vision {n}',
  'pwaSetAsCurrent': 'Définir comme actuelle',
  'pwaContinueFromThisVision': 'Continuer depuis cette vision',
  'pwaSelectAtmosphere': "Choisir l'ambiance {name}",
  'pwaAtmosphereSelected': '{name} sélectionnée',
  'pwaCreatesVisionN': '· Crée la Vision {n}',
  'pwaUsesOneSpace': '· Utilise 1 Space',
  'pwaAtmospheresSection': 'AMBIANCES',
  'pwaCompare': 'Comparer',

  // ── Versions sheet ─────────────────────────────────────────────────────────
  'pwaOriginalUpload': 'Photo importée',
  'pwaYourVisions': 'Vos visions',
  'pwaTotalCount': '{n} au total',
  'pwaJumpedToVision': 'Accès à la Vision {n} dans la conversation',
  'pwaCurrentBadge': 'Actuelle',
  'pwaCreatedFrom': 'Créée depuis {name} · {label}',
  'pwaFindInChat': 'Retrouver dans la conversation',
  'pwaSetCurrent': 'Définir comme actuelle',
  'pwaAllCount': 'Les {n}',

  // ── Projects ───────────────────────────────────────────────────────────────
  'pwaYourSpaces': 'VOS ESPACES',
  'pwaContinueShapingHome': 'Continuez à façonner votre maison.',
  'pwaReturnToProject':
      'Revenez à un projet, explorez ses visions, ou commencez un nouvel espace.',
  'pwaSearchProjects': 'Rechercher vos projets…',
  'pwaClearSearch': 'Effacer la recherche',
  'pwaSortProjects': 'Trier les projets',
  'pwaSortRecentlyUpdated': 'Récemment mis à jour',
  'pwaSortNewest': 'Plus récents',
  'pwaSortOldest': 'Plus anciens',
  'pwaSortNameAz': 'Nom A–Z',
  'pwaOpenProject': 'Ouvrir le projet',
  'pwaProjectOptions': 'Options du projet',
  'pwaDraftBadge': 'Brouillon',
  'pwaRenameProject': 'Renommer le projet',
  'pwaRename': 'Renommer',
  'pwaSave': 'Enregistrer',
  'pwaDuplicate': 'Dupliquer',
  'pwaDelete': 'Supprimer',
  'pwaDeleteProjectTitle': 'Supprimer le projet ?',
  'pwaDeleteProjectBody':
      'Cela retire « {title} » et ses visions de votre bibliothèque. '
      'Cette action est irréversible.',
  'pwaYourNextSpace': 'Votre prochain espace commence ici.',
  'pwaUploadAndCreate':
      'Importez une photo et créez votre première vision avec Ayden.',
  'pwaNoMatchingProjects': 'Aucun projet correspondant',
  'pwaTryAnotherRoom': "Essayez une autre pièce, ambiance ou nom de projet.",
  'pwaNoProjectsFoundFor': 'Aucun projet trouvé pour ',
  'pwaOneProjectFoundFor': '1 projet trouvé pour ',
  'pwaNProjectsFoundFor': '{n} projets trouvés pour ',
  'pwaUntitledSpace': 'Espace sans titre',
  'pwaDraftContinueSetup': 'Brouillon · Continuer la configuration',
  'pwaContinueSetup': 'Continuer la configuration',
  'pwaUpdatedToday': "Mis à jour aujourd'hui",
  'pwaUpdatedDaysAgo': 'Mis à jour il y a {n} jours',
  'pwaUpdatedJustNow': "Mis à jour à l'instant",
  'pwaUpdatedMinutesAgo': 'Mis à jour il y a {n} min',
  'pwaUpdatedYesterday': 'Hier',
  'pwaUpdatedLastWeek': 'La semaine dernière',
  'pwaUpdatedWeeksAgo': 'Il y a {n} semaines',
  'pwaUpdatedMonthsAgo': 'Il y a {n} mois',

  // ── Billing access states ──────────────────────────────────────────────────
  'pwaFreeVisionAvailable': '1 vision gratuite',
  'pwaFreeVisionWatermarked': 'Les visions gratuites portent la marque AYDEN.',
  'pwaBillingFreeExhausted': 'Votre vision gratuite a été utilisée.',
  'pwaBillingFreeExhaustedSub':
      'Débloquez AYDEN Studio pour continuer à dessiner cet espace.',
  'pwaBillingPassRequired': 'Un pass est nécessaire pour continuer.',
  'pwaBillingPassExhausted': "Votre pass n'a plus de Spaces.",
  'pwaBillingUnavailable':
      'Nous terminons une mise à jour. Veuillez réessayer dans un instant.',
  'pwaPassSpacesLeft': '{n} Spaces restants',

  // ── Errors ─────────────────────────────────────────────────────────────────
  'pwaErrSessionExpired':
      'Votre session a expiré. Rechargez la page pour continuer.',
  'pwaErrBackendUnreachable':
      "Cette version ne peut atteindre aucun serveur de génération.",
  'pwaErrTimeout': 'Cela prend plus de temps que prévu. Réessayez.',
  'pwaErrNetwork': 'Connexion perdue. Vérifiez votre réseau et réessayez.',
  'pwaErrGenerationFailed':
      "Ayden n'a pas pu terminer cette vision. Vous pouvez réessayer.",
  'pwaErrGenerationLost':
      "Ayden n'a pas retrouvé cette génération. Vous pouvez réessayer.",
  'pwaErrCancelled': 'Cette demande a été annulée.',
  'pwaErrStillWorking':
      'Ayden travaille encore dessus. Patientez un instant, puis réessayez.',
  'pwaErrUploadFailed': "Votre photo n'a pas pu être importée. Réessayez.",
  'pwaErrPrepareFailed': "Votre vision n'a pas pu être préparée. Réessayez.",
  'pwaErrSaveFailed': "Votre vision n'a pas pu être enregistrée. Réessayez.",
  'pwaErrUnknown': "Une erreur s'est produite. Réessayez.",
  'pwaRetry': 'Réessayer',
};
