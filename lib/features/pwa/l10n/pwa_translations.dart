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
  'pwaContactSupport': 'Contact support',
  'pwaAboutVersion': 'Version 1.0',
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
  // Step 4 — see PwaL10n.step4Sub / .step4Hint for why these two are the only
  // Create strings the web does not forward from the mobile dictionary.
  'pwaStep4Sub': 'Brief the architect in your own words.',
  'pwaStep4Hint':
      'More natural light, warm colors, cozy, minimalist, modern…',
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
  // Room-neutral, because the four default suggestions are shown under EVERY
  // result. "Open the kitchen" under a terrace was the defect.
  'pwaChipCalmer': 'Make it calmer',
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
  // PHASE 5 — two short sentences, and TRUE ones.
  //
  // The old copy was three sentences and ended "Explore the atmospheres
  // below" — but the atmosphere rail moved to the Full Reveal, so it was
  // telling people to use something that is not on the screen. It also
  // buried the render under a paragraph the person had to read before
  // they could look at what they waited two minutes for.
  //
  // {name} is the atmosphere the ENGINE resolved, so the sentence names
  // the direction that was actually rendered rather than the one asked
  // for.
  'pwaFirstVisionIntro':
      'Your {name} direction is in — same architecture, warmer materials '
      'and softer light. What would you like to change?',
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
  'pwaGetMoreSpaces': 'Get more Spaces',
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
  'pwaUpdatedMonthAgoOne': 'Last month',

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
  'pwaPassSpaceLeftOne': '1 space left',

  // -- Paywall + account (Auth/Paywall foundation) ---------------------------
  'pwaRedesignOne': '1 redesign',
  'pwaPaywallTitle': 'Keep designing',
  'pwaPaywallFreeUsedTitle': 'Your free vision is used',
  'pwaPaywallFreeUsedBody':
      'You have seen what Ayden can do with your space. Unlock more visions to '
      'keep refining it.',
  'pwaPaywallPassExhaustedTitle': 'No spaces left',
  'pwaPaywallPassExhaustedBody':
      'Your pass has been fully used. Add more spaces to continue.',
  'pwaPaywallPassRequiredTitle': 'Restore your access',
  'pwaPaywallPassRequiredBody':
      'Your account has Premium, but no active pass was found. Restore your '
      'purchase to keep designing.',
  'pwaPaywallLoading': 'Checking your account...',
  'pwaPaywallErrorTitle': "We couldn't check your account",
  'pwaPaywallErrorBody':
      'Your access could not be confirmed just now. You can try again.',
  'pwaPaywallActiveTitle': 'Your pass is active',
  'pwaPaywallActiveBody': 'No watermark. Design as much as you like.',
  'pwaPaywallSpaces': '{n} spaces',
  'pwaPaywallSpaceOne': '1 space',
  'pwaPaywallDays': '{n} days',
  'pwaPaywallUnavailableTitle': 'Payments are not open yet',
  'pwaPaywallUnavailableBody':
      'Buying on the web is coming to Cambodia soon. Your work is saved and '
      'will be waiting for you.',
  'pwaPaywallStoreOnly': 'Available in the mobile app',
  'pwaPaywallDiscount': '{n}% OFF',
  'pwaProductBadgeStarter': 'STARTER',
  'pwaProductBadgePopular': 'POPULAR',
  'pwaProductBadgeBestValue': 'BEST VALUE',
  'pwaPaywallRestore': 'I already paid',
  'pwaPaywallClose': 'Not now',

  // -- Payment (ABA KHQR) ----------------------------------------------------
  // Cambodia-first wording. 'KHQR' and 'ABA Mobile' stay untranslated in all
  // three locales: they are the names printed on the thing a person is about to
  // tap, and translating a brand is how an interface becomes unrecognisable.
  // Ayden's OWN sentences name no provider (ABA's merchant review, 2026-09-08:
  // "there is no requirement UI related to ABA PayWay"). The provider's name
  // appears only where it IS the name of the thing on screen: the payment
  // method 'ABA KHQR' (their tile, in pwa_aba_marks.dart) and the bank app a
  // deeplink button opens ('ABA Mobile').
  'pwaPayBuy': 'Buy',
  'pwaPayContinueToAba': 'Continue to payment',
  'pwaAcceptWeAccept': 'We accept',
  'pwaPayMethodTitle': 'Payment method',
  'pwaPayMethodBody': 'Scan to pay with any banking app',
  'pwaPayLinkExpiredTitle': 'This payment link has expired',
  'pwaPayLinkExpiredBody':
      'Payment links are only valid for a few minutes. Nothing was '
      'charged — start again to get a fresh one.',
  'pwaPayPreparing': 'Preparing your payment...',
  'pwaPayScanTitle': 'Scan to pay',
  'pwaPayScanBody':
      'Open any Cambodian bank app that reads KHQR and scan this code.',
  'pwaPayClose': 'Close',
  // Shown BEHIND ABA's popup, and after it closes: the payment is still open
  // and this card will change on its own when the server hears from ABA.
  'pwaPayPluginOpen':
      'The secure checkout is open. Finish there — this will update by '
      'itself.',
  // The line under Buy while a transaction is live. No countdown, no
  // "waiting for your payment": the popup says what is open, and this only
  // says that the server is checking.
  'pwaPayInlineChecking': 'Checking your payment…',
  'pwaPayInlineCancel': 'Cancel this payment',
  // NOT_CREATED — PayWay refused the purchase before a transaction existed
  // (a domain not yet whitelisted, a rejected request). Nothing to wait for.
  'pwaPayFailedNotCreated':
      'Payment could not start. Please try again.',
  'pwaPayOpenAba': 'Open ABA Mobile',
  'pwaPayOrScan': 'or scan the code with another bank app',
  'pwaPayExpiresIn': 'This code expires in {t}',
  'pwaPayWaiting': 'Waiting for your payment',
  'pwaPayConfirmingTitle': 'Confirming your payment',
  'pwaPayConfirmingBody':
      'Your bank has told us. We are confirming the payment before adding '
      'your spaces.',
  'pwaPayActivatingTitle': 'Activating your spaces',
  'pwaPayActivatingBody': 'Payment confirmed. Adding it to your account now.',
  'pwaPayContinue': 'Continue designing',
  'pwaPayExpiredTitle': 'This code expired',
  'pwaPayExpiredBody':
      'Nothing was charged. Start a new payment whenever you are ready.',
  'pwaPayCancelledTitle': 'Payment cancelled',
  'pwaPayCancelledBody': 'Nothing was charged.',
  'pwaPayFailedTitle': 'Payment did not go through',
  'pwaPayFailedBody': 'Nothing was added to your account. You can try again.',
  'pwaPayFailedDeclined': 'Your bank declined the payment. Nothing was charged.',
  'pwaPayFailedAmount':
      'The amount received did not match this purchase, so nothing was added. '
      'Contact us and we will sort it out.',
  'pwaPayFailedProvider':
      'The payment service refused the request. Please try again.',
  'pwaPayFailedNewAttempt':
      'This payment code can no longer be used. Start a new payment.',
  'pwaPayUnreachableTitle': 'We lost the connection',
  'pwaPayUnreachableBody':
      'Your payment may still be going through. Stay on this screen — we will '
      'keep checking.',
  'pwaPayRetry': 'Try again',
  // Ayden's result card (2026-09-08). The pack line reuses pwaPaywallSpaces.
  'pwaPayResultSuccessTitle': 'Payment successful',
  'pwaPayResultSuccessBody': '{n} spaces added to your wallet',
  'pwaPayResultSummaryTitle': 'Purchase summary',
  'pwaPayResultNewBalance': 'New balance',
  'pwaPayResultContinue': 'Continue',
  'pwaPayResultFailedTitle': 'Payment failed / cancelled',
  'pwaPayResultFailedBody': 'No credits were added',
  'pwaPayResultFailedHint':
      'Your wallet remains unchanged. You can return safely or retry the '
      'payment when ready.',
  'pwaPayCancel': 'Cancel payment',
  'pwaPaySafeNote': 'Ayden never sees your banking details.',

  // -- Account / verification ------------------------------------------------
  'pwaAccountTitle': 'Save my designs',
  'pwaAccountBody':
      'Create your Ayden account and keep your designs.',
  'pwaAccountEmailLabel': 'Email address',
  'pwaAccountEmailHint': 'you@example.com',
  'pwaAccountSend': 'Send code',
  'pwaAccountCodeTitle': 'Enter your code',
  'pwaAccountCodeBody': 'We sent a 6-digit code to {email}.',
  'pwaAccountCodeLabel': 'Verification code',
  'pwaAccountVerify': 'Verify',
  'pwaAccountResend': 'Send it again',
  'pwaAccountChangeEmail': 'Use a different address',
  'pwaAccountSignedInAs': 'Signed in as {email}',
  'pwaAccountSignOut': 'Sign out',
  'pwaAccountGuestLabel': 'Guest',
  'pwaAccountLinkedTitle': 'Your work is saved',
  'pwaAccountLinkedBody':
      'Everything you made is on your account. Sign in from any device to find '
      'it again.',
  'pwaAccountSwitchedTitle': "You're signed in",
  'pwaAccountSwitchedBody':
      'This account keeps its own projects and its own access. Anything you '
      'made as a guest stays on this browser.',
  'pwaAccountExistsTitle': 'This email already has an account',
  'pwaAccountExistsBody':
      'Sign in to it instead. Your guest work stays on this browser and does '
      'not move across.',
  'pwaAccountSignInInstead': 'Sign in to that account',
  'pwaAccountSignInTitle': 'Sign in',
  'pwaReplayReveal': 'Replay',
  'pwaShareVision': 'Share',
  'pwaShareVisionText': 'Check out my AI home redesign — {title}!',
  'pwaShareUnavailable': 'Sharing is not available in this browser.',
  'pwaAccountHaveOne': 'Already use Ayden Studio?',
  'pwaAccountSignInBody': 'We will send a code to your email address.',
  'pwaAccountBackToLink': 'Create a new account instead',
  'pwaAuthErrInvalidEmail': 'That email address does not look right.',
  'pwaAuthErrInvalidCode': 'That code is wrong or has expired.',
  'pwaAuthErrRateLimited':
      'Too many codes have been sent. Please wait a few minutes and try again.',
  'pwaAuthErrUnavailable': "We couldn't reach the verification service.",
  'pwaAuthErrUnknown': 'Something went wrong. Please try again.',
  'pwaAuthUnavailable': 'Accounts are not available in this build.',

  // -- Cambodia auth: Facebook + phone first, email second -------------------
  'pwaAuthSecureTitle': 'Secure your Ayden account',
  'pwaAuthSecureBody': 'Access your designs and Spaces from any device.',
  'pwaAuthSignInChooserBody': 'Sign in to the account you already have.',
  'pwaAuthContinueFacebook': 'Continue with Facebook',
  'pwaAuthContinuePhone': 'Continue with phone number',
  'pwaAuthOr': 'or',
  'pwaAuthUseEmail': 'Use email instead',
  'pwaAuthChooseAnother': 'Choose another way',
  'pwaAuthPhoneTitle': 'Your phone number',
  'pwaAuthPhoneBody': "We'll text you a 6-digit code.",
  'pwaAuthPhoneSignInBody': "We'll text a 6-digit code to the number on your account.",
  'pwaAuthPhoneLabel': 'Phone number',
  'pwaAuthPhoneHint': '12 345 678',
  'pwaAuthDialCodeLabel': 'Code',
  'pwaAuthContinue': 'Continue',
  'pwaAuthPhoneCodeBody': 'We sent a 6-digit code to {phone}.',
  'pwaAuthChangePhone': 'Use a different number',
  'pwaAuthResendIn': 'Send it again in {seconds}s',
  'pwaAuthCodeExpiry': 'Codes expire after a few minutes.',
  'pwaAuthWelcomeBack': 'Welcome back',
  'pwaAuthExistsFacebook':
      'This Facebook account already has an Ayden account.',
  'pwaAuthExistsPhone': 'This phone number already has an Ayden account.',
  'pwaAuthExistsEmail': 'This email already has an Ayden account.',
  'pwaAuthContinueExisting': 'Continue to my existing account',
  'pwaAuthErrInvalidPhone': 'That phone number does not look right.',
  'pwaAuthErrContested':
      'A verification for this number is still in progress. Please try '
      'again in a few minutes.',
  'pwaAuthErrMismatch':
      "That code didn't attach to this account. Nothing was changed — "
      'please try again.',
  'pwaAuthErrCancelled': 'Facebook sign-in was cancelled.',
  'pwaAuthErrNoEmail':
      "Facebook didn't share an email address, so it can't be attached to "
      'this account. Use your phone number to secure it instead.',
  'pwaAuthErrProvider':
      "Facebook sign-in isn't available right now. Try your phone number or "
      'email.',
  'pwaAuthFacebookLeaving': 'Taking you to Facebook…',
  'pwaAuthConnectedFacebook': 'Connected with Facebook',
  'pwaAuthConnectedPhone': 'Connected with phone',
  'pwaAuthConnectedEmail': 'Connected with email',
  'pwaAuthMethodsTitle': 'Sign-in methods',
  'pwaAuthMethodFacebook': 'Facebook',
  'pwaAuthMethodPhone': 'Phone',
  'pwaAuthMethodEmail': 'Email',
  'pwaAuthAdd': 'Add',
  'pwaAuthGuestBody': 'Your designs are saved on this device.',
  'pwaAuthSecureCta': 'Secure my account',

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
  'pwaContactSupport': 'ទាក់ទង​ផ្នែក​ជំនួយ',
  'pwaAboutVersion': 'កំណែ 1.0',
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
  'pwaStep4Sub': 'ប្រាប់​ស្ថបត្យករ​តាម​ពាក្យ​របស់​អ្នក។',
  'pwaStep4Hint':
      'ពន្លឺ​ធម្មជាតិ​ច្រើន​ជាង, ពណ៌​ក្តៅ, កក់ក្តៅ, សាមញ្ញ, ទំនើប…',
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
  'pwaChipCalmer': 'ធ្វើ​ឱ្យ​ស្ងប់​ជាង​នេះ',
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
      'ទិសដៅ {name} របស់​អ្នក​រួច​រាល់​ហើយ — ស្ថាបត្យកម្ម​ដដែល សម្ភារៈ​ក្ដៅ​ជាង '
      'និង​ពន្លឺ​ទន់​ភ្លន់។ តើ​អ្នក​ចង់​ផ្លាស់ប្ដូរ​អ្វី?',
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
  'pwaGetMoreSpaces': 'ទិញ Spaces បន្ថែម',
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
  'pwaUpdatedMonthAgoOne': 'ខែ​មុន',

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
  'pwaPassSpaceLeftOne': 'នៅ​សល់ 1 Space',

  // -- Paywall + account (Auth/Paywall foundation) ---------------------------
  'pwaRedesignOne': 'ការ​រចនា​ឡើង​វិញ 1',
  'pwaPaywallTitle': 'បន្ត​រចនា​ត​ទៅ​ទៀត',
  'pwaPaywallFreeUsedTitle': 'ទស្សនៈ​ឥត​គិត​ថ្លៃ​របស់​អ្នក​ត្រូវ​បាន​ប្រើ​អស់​ហើយ',
  'pwaPaywallFreeUsedBody':
      'អ្នក​បាន​ឃើញ​ហើយ​ថា Ayden អាច​ធ្វើ​អ្វី​ខ្លះ​ជាមួយ​ទីកន្លែង​របស់​អ្នក។ '
      'ដោះ​សោ​ទស្សនៈ​បន្ថែម ដើម្បី​បន្ត​កែ​លម្អ​វា។',
  'pwaPaywallPassExhaustedTitle': 'គ្មាន Spaces នៅ​សល់​ទេ',
  'pwaPaywallPassExhaustedBody':
      'Pass របស់​អ្នក​ត្រូវ​បាន​ប្រើ​អស់​ហើយ។ បន្ថែម Spaces ដើម្បី​បន្ត។',
  'pwaPaywallPassRequiredTitle': 'ស្ដារ​សិទ្ធិ​ចូល​ប្រើ​របស់​អ្នក',
  'pwaPaywallPassRequiredBody':
      'គណនី​របស់​អ្នក​មាន Premium ប៉ុន្តែ​រក​មិន​ឃើញ Pass សកម្ម​ទេ។ '
      'សូម​ស្ដារ​ការ​ទិញ​របស់​អ្នក ដើម្បី​បន្ត​រចនា។',
  'pwaPaywallLoading': 'កំពុង​ពិនិត្យ​គណនី​របស់​អ្នក...',
  'pwaPaywallErrorTitle': 'យើង​មិន​អាច​ពិនិត្យ​គណនី​របស់​អ្នក​បាន​ទេ',
  'pwaPaywallErrorBody':
      'សិទ្ធិ​ចូល​ប្រើ​របស់​អ្នក​មិន​អាច​បញ្ជាក់​បាន​ឥឡូវ​នេះ​ទេ។ អ្នក​អាច​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaPaywallActiveTitle': 'Pass របស់​អ្នក​កំពុង​សកម្ម',
  'pwaPaywallActiveBody': 'គ្មាន​ហត្ថលេខា​ទឹក។ រចនា​បាន​តាម​ចិត្ត។',
  'pwaPaywallSpaces': '{n} Spaces',
  'pwaPaywallSpaceOne': '1 Space',
  'pwaPaywallDays': '{n} ថ្ងៃ',
  'pwaPaywallUnavailableTitle': 'ការ​ទូទាត់​មិន​ទាន់​បើក​នៅ​ឡើយ​ទេ',
  'pwaPaywallUnavailableBody':
      'ការ​ទិញ​តាម​គេហទំព័រ​នឹង​មក​ដល់​កម្ពុជា​ក្នុង​ពេល​ឆាប់ៗ។ '
      'ការងារ​របស់​អ្នក​ត្រូវ​បាន​រក្សា​ទុក ហើយ​នឹង​នៅ​រង់ចាំ​អ្នក។',
  'pwaPaywallStoreOnly': 'មាន​នៅ​ក្នុង​កម្មវិធី​ទូរស័ព្ទ',
  'pwaPaywallDiscount': 'បញ្ចុះ​តម្លៃ {n}%',
  'pwaProductBadgeStarter': 'ចាប់​ផ្ដើម',
  'pwaProductBadgePopular': 'ពេញ​និយម',
  'pwaProductBadgeBestValue': 'តម្លៃ​ល្អ​បំផុត',
  'pwaPaywallRestore': 'ខ្ញុំ​បាន​ទូទាត់​រួច​ហើយ',
  'pwaPaywallClose': 'មិន​ទាន់​ទេ',

  // -- Payment (ABA KHQR) ----------------------------------------------------
  'pwaPayBuy': 'ទិញ',
  'pwaPayContinueToAba': 'បន្ត​ទៅ​ការ​ទូទាត់',
  'pwaAcceptWeAccept': 'យើង​ទទួល',
  'pwaPayMethodTitle': 'មធ្យោបាយ​ទូទាត់',
  'pwaPayMethodBody': 'ស្កេន​ដើម្បី​ទូទាត់​ដោយ​កម្មវិធី​ធនាគារ​ណា​មួយ',
  'pwaPayLinkExpiredTitle': 'តំណ​ទូទាត់​នេះ​ផុត​កំណត់​ហើយ',
  'pwaPayLinkExpiredBody':
      'តំណ​ទូទាត់​មាន​សុពលភាព​តែ​ប៉ុន្មាន​នាទី​ប៉ុណ្ណោះ។ គ្មាន​ការ​កាត់​ប្រាក់​ទេ — '
      'សូម​ចាប់​ផ្ដើម​ម្ដង​ទៀត​ដើម្បី​ទទួល​តំណ​ថ្មី។',
  'pwaPayPreparing': 'កំពុង​រៀបចំ​ការ​ទូទាត់​របស់​អ្នក...',
  'pwaPayScanTitle': 'ស្កេន​ដើម្បី​ទូទាត់',
  'pwaPayScanBody':
      'បើក​កម្មវិធី​ធនាគារ​កម្ពុជា​ណា​មួយ​ដែល​អាន KHQR បាន រួច​ស្កេន​កូដ​នេះ។',
  'pwaPayClose': 'បិទ',
  'pwaPayPluginOpen':
      'ទំព័រ​ទូទាត់​សុវត្ថិភាព​បាន​បើក​ហើយ។ សូម​បញ្ចប់​នៅ​ទីនោះ — '
      'ទំព័រ​នេះ​នឹង​ធ្វើ​បច្ចុប្បន្នភាព​ដោយ​ខ្លួន​ឯង។',
  'pwaPayInlineChecking': 'កំពុង​ពិនិត្យ​ការ​ទូទាត់​របស់​អ្នក…',
  'pwaPayInlineCancel': 'បោះបង់​ការ​ទូទាត់​នេះ',
  'pwaPayFailedNotCreated':
      'មិន​អាច​ចាប់ផ្ដើម​ការ​ទូទាត់​បាន​ទេ។ សូម​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaPayOpenAba': 'បើក ABA Mobile',
  'pwaPayOrScan': 'ឬ​ស្កេន​កូដ​ដោយ​កម្មវិធី​ធនាគារ​ផ្សេង',
  'pwaPayExpiresIn': 'កូដ​នេះ​ផុត​កំណត់​ក្នុង​រយៈពេល {t}',
  'pwaPayWaiting': 'កំពុង​រង់ចាំ​ការ​ទូទាត់​របស់​អ្នក',
  'pwaPayConfirmingTitle': 'កំពុង​បញ្ជាក់​ការ​ទូទាត់​របស់​អ្នក',
  'pwaPayConfirmingBody':
      'ធនាគារ​របស់​អ្នក​បាន​ជូន​ដំណឹង​មក​យើង​ហើយ។ '
      'យើង​កំពុង​ផ្ទៀងផ្ទាត់​ការ​ទូទាត់ មុន​ពេល​បន្ថែម Spaces របស់​អ្នក។',
  'pwaPayActivatingTitle': 'កំពុង​ដំណើរការ Spaces របស់​អ្នក',
  'pwaPayActivatingBody':
      'ការ​ទូទាត់​ត្រូវ​បាន​បញ្ជាក់។ កំពុង​បន្ថែម​ទៅ​គណនី​របស់​អ្នក។',
  'pwaPayContinue': 'បន្ត​រចនា',
  'pwaPayExpiredTitle': 'កូដ​នេះ​ផុត​កំណត់​ហើយ',
  'pwaPayExpiredBody':
      'គ្មាន​ការ​កាត់​ប្រាក់​ទេ។ '
      'ចាប់ផ្ដើម​ការ​ទូទាត់​ថ្មី​នៅ​ពេល​ណា​ដែល​អ្នក​ត្រៀម​រួច។',
  'pwaPayCancelledTitle': 'ការ​ទូទាត់​ត្រូវ​បាន​បោះបង់',
  'pwaPayCancelledBody': 'គ្មាន​ការ​កាត់​ប្រាក់​ទេ។',
  'pwaPayFailedTitle': 'ការ​ទូទាត់​មិន​បាន​សម្រេច',
  'pwaPayFailedBody':
      'គ្មាន​អ្វី​ត្រូវ​បាន​បន្ថែម​ទៅ​គណនី​របស់​អ្នក​ទេ។ '
      'អ្នក​អាច​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaPayFailedDeclined':
      'ធនាគារ​របស់​អ្នក​បាន​បដិសេធ​ការ​ទូទាត់។ គ្មាន​ការ​កាត់​ប្រាក់​ទេ។',
  'pwaPayFailedAmount':
      'ចំនួន​ទឹកប្រាក់​ដែល​ទទួល​បាន​មិន​ត្រូវ​គ្នា​នឹង​ការ​ទិញ​នេះ​ទេ '
      'ដូច្នេះ​គ្មាន​អ្វី​ត្រូវ​បាន​បន្ថែម។ សូម​ទាក់ទង​មក​យើង '
      'នោះ​យើង​នឹង​ដោះស្រាយ​ជូន។',
  'pwaPayFailedProvider':
      'សេវា​ទូទាត់​បាន​បដិសេធ​សំណើ។ សូម​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaPayFailedNewAttempt':
      'កូដ​ទូទាត់​នេះ​មិន​អាច​ប្រើ​បាន​ទៀត​ទេ។ សូម​ចាប់ផ្ដើម​ការ​ទូទាត់​ថ្មី។',
  'pwaPayUnreachableTitle': 'ការ​ភ្ជាប់​ត្រូវ​បាន​ដាច់',
  'pwaPayUnreachableBody':
      'ការ​ទូទាត់​របស់​អ្នក​អាច​កំពុង​ដំណើរការ​នៅ​ឡើយ។ '
      'សូម​នៅ​លើ​អេក្រង់​នេះ — យើង​នឹង​បន្ត​ពិនិត្យ។',
  'pwaPayRetry': 'ព្យាយាម​ម្ដង​ទៀត',
  'pwaPayResultSuccessTitle': 'ការ​ទូទាត់​បាន​ជោគជ័យ',
  'pwaPayResultSuccessBody': '{n} Spaces ត្រូវ​បាន​បន្ថែម​ទៅ​កាបូប​របស់​អ្នក',
  'pwaPayResultSummaryTitle': 'សង្ខេប​ការ​ទិញ',
  'pwaPayResultNewBalance': 'សមតុល្យ​ថ្មី',
  'pwaPayResultContinue': 'បន្ត',
  'pwaPayResultFailedTitle': 'ការ​ទូទាត់​បរាជ័យ / ត្រូវ​បាន​បោះបង់',
  'pwaPayResultFailedBody': 'មិន​មាន​ឥណទាន​ត្រូវ​បាន​បន្ថែម​ទេ',
  'pwaPayResultFailedHint':
      'កាបូប​របស់​អ្នក​នៅ​ដដែល។ អ្នក​អាច​ត្រឡប់​ក្រោយ​ដោយ​សុវត្ថិភាព '
      'ឬ​ព្យាយាម​ទូទាត់​ម្ដង​ទៀត​នៅ​ពេល​រួចរាល់។',
  'pwaPayCancel': 'បោះបង់​ការ​ទូទាត់',
  'pwaPaySafeNote': 'Ayden មិន​ដែល​ឃើញ​ព័ត៌មាន​ធនាគារ​របស់​អ្នក​ទេ។',

  // -- Account / verification ------------------------------------------------
  'pwaAccountTitle': 'រក្សា​ទុក​ការ​រចនា​របស់​ខ្ញុំ',
  'pwaAccountBody':
      'បង្កើត​គណនី Ayden របស់​អ្នក ហើយ​រក្សា​ទុក​ការ​រចនា​របស់​អ្នក។',
  'pwaAccountEmailLabel': 'អាសយដ្ឋាន​អ៊ីមែល',
  'pwaAccountEmailHint': 'you@example.com',
  'pwaAccountSend': 'ផ្ញើ​លេខ​កូដ',
  'pwaAccountCodeTitle': 'បញ្ចូល​លេខ​កូដ​របស់​អ្នក',
  'pwaAccountCodeBody': 'យើង​បាន​ផ្ញើ​លេខ​កូដ ៦ ខ្ទង់​ទៅ {email}។',
  'pwaAccountCodeLabel': 'លេខ​កូដ​ផ្ទៀងផ្ទាត់',
  'pwaAccountVerify': 'ផ្ទៀងផ្ទាត់',
  'pwaAccountResend': 'ផ្ញើ​ម្ដង​ទៀត',
  'pwaAccountChangeEmail': 'ប្រើ​អាសយដ្ឋាន​ផ្សេង',
  'pwaAccountSignedInAs': 'បាន​ចូល​ជា {email}',
  'pwaAccountSignOut': 'ចេញ​ពី​គណនី',
  'pwaAccountGuestLabel': 'ភ្ញៀវ',
  'pwaAccountLinkedTitle': 'ការងារ​របស់​អ្នក​ត្រូវ​បាន​រក្សា​ទុក',
  'pwaAccountLinkedBody':
      'អ្វី​គ្រប់​យ៉ាង​ដែល​អ្នក​បាន​បង្កើត​នៅ​ក្នុង​គណនី​របស់​អ្នក។ '
      'ចូល​ពី​ឧបករណ៍​ណា​ក៏​បាន ដើម្បី​រក​វា​ឃើញ​ម្ដង​ទៀត។',
  'pwaAccountSwitchedTitle': 'អ្នក​បាន​ចូល​ហើយ',
  'pwaAccountSwitchedBody':
      'គណនី​នេះ​មាន​គម្រោង​ផ្ទាល់​ខ្លួន និង​សិទ្ធិ​ចូល​ប្រើ​ផ្ទាល់​ខ្លួន។ '
      'អ្វី​ដែល​អ្នក​បាន​បង្កើត​ជា​ភ្ញៀវ​នៅ​តែ​លើ​កម្មវិធី​រុករក​នេះ។',
  'pwaAccountExistsTitle': 'អ៊ីមែល​នេះ​មាន​គណនី​រួច​ហើយ',
  'pwaAccountExistsBody':
      'សូម​ចូល​ទៅ​គណនី​នោះ​ជំនួស​វិញ។ ការងារ​ជា​ភ្ញៀវ​របស់​អ្នក​នៅ​តែ​លើ​កម្មវិធី​រុករក​នេះ '
      'ហើយ​មិន​ផ្លាស់​ទី​ទៅ​តាម​ទេ។',
  'pwaAccountSignInInstead': 'ចូល​ទៅ​គណនី​នោះ',
  'pwaAccountSignInTitle': 'ចូល​គណនី',
  'pwaReplayReveal': 'ចាក់​ឡើង​វិញ',
  'pwaShareVision': 'ចែក​រំលែក',
  'pwaShareVisionText': 'មើល​ការ​រចនា​ផ្ទះ​ឡើង​វិញ​ដោយ AI របស់​ខ្ញុំ — {title}!',
  'pwaShareUnavailable': 'ការ​ចែក​រំលែក​មិន​អាច​ប្រើ​បាន​ក្នុង​កម្មវិធី​រុករក​នេះ​ទេ។',
  'pwaAccountHaveOne': 'ប្រើ Ayden Studio រួច​ហើយ​មែន​ទេ?',
  'pwaAccountSignInBody': 'យើង​នឹង​ផ្ញើ​លេខ​កូដ​ទៅ​អាសយដ្ឋាន​អ៊ីមែល​របស់​អ្នក។',
  'pwaAccountBackToLink': 'បង្កើត​គណនី​ថ្មី​ជំនួស​វិញ',
  'pwaAuthErrInvalidEmail': 'អាសយដ្ឋាន​អ៊ីមែល​នោះ​មើល​ទៅ​មិន​ត្រឹមត្រូវ​ទេ។',
  'pwaAuthErrInvalidCode': 'លេខ​កូដ​នោះ​មិន​ត្រឹមត្រូវ ឬ​ផុត​កំណត់​ហើយ។',
  'pwaAuthErrRateLimited':
      'លេខ​កូដ​ត្រូវ​បាន​ផ្ញើ​ច្រើន​ដង​ពេក។ សូម​រង់ចាំ​ពីរ​បី​នាទី រួច​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaAuthErrUnavailable': 'យើង​មិន​អាច​ភ្ជាប់​ទៅ​សេវា​ផ្ទៀងផ្ទាត់​បាន​ទេ។',
  'pwaAuthErrUnknown': 'មាន​អ្វី​មួយ​មិន​ប្រក្រតី។ សូម​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaAuthUnavailable': 'គណនី​មិន​មាន​នៅ​ក្នុង​កំណែ​នេះ​ទេ។',

  // -- Cambodia auth: Facebook + phone first, email second -------------------
  'pwaAuthSecureTitle': 'ការពារ​គណនី Ayden របស់​អ្នក',
  'pwaAuthSecureBody':
      'ចូល​មើល​ការ​រចនា និង Spaces របស់​អ្នក​ពី​ឧបករណ៍​ណា​ក៏​បាន។',
  'pwaAuthSignInChooserBody': 'ចូល​ទៅ​គណនី​ដែល​អ្នក​មាន​រួច​ហើយ។',
  'pwaAuthContinueFacebook': 'បន្ត​ជាមួយ Facebook',
  'pwaAuthContinuePhone': 'បន្ត​ជាមួយ​លេខ​ទូរស័ព្ទ',
  'pwaAuthOr': 'ឬ',
  'pwaAuthUseEmail': 'ប្រើ​អ៊ីមែល​ជំនួស​វិញ',
  'pwaAuthChooseAnother': 'ជ្រើស​វិធី​ផ្សេង',
  'pwaAuthPhoneTitle': 'លេខ​ទូរស័ព្ទ​របស់​អ្នក',
  'pwaAuthPhoneBody': 'យើង​នឹង​ផ្ញើ​សារ​លេខ​កូដ ៦ ខ្ទង់​ទៅ​អ្នក។',
  'pwaAuthPhoneSignInBody':
      'យើង​នឹង​ផ្ញើ​សារ​លេខ​កូដ ៦ ខ្ទង់​ទៅ​លេខ​នៅ​លើ​គណនី​របស់​អ្នក។',
  'pwaAuthPhoneLabel': 'លេខ​ទូរស័ព្ទ',
  'pwaAuthPhoneHint': '០១២ ៣៤៥ ៦៧៨',
  'pwaAuthDialCodeLabel': 'កូដ',
  'pwaAuthContinue': 'បន្ត',
  'pwaAuthPhoneCodeBody': 'យើង​បាន​ផ្ញើ​លេខ​កូដ ៦ ខ្ទង់​ទៅ {phone}។',
  'pwaAuthChangePhone': 'ប្រើ​លេខ​ផ្សេង',
  'pwaAuthResendIn': 'ផ្ញើ​ម្ដង​ទៀត​ក្នុង {seconds} វិនាទី',
  'pwaAuthCodeExpiry': 'លេខ​កូដ​ផុត​កំណត់​បន្ទាប់​ពី​ពីរ​បី​នាទី។',
  'pwaAuthWelcomeBack': 'សូម​ស្វាគមន៍​ការ​ត្រឡប់​មក​វិញ',
  'pwaAuthExistsFacebook': 'គណនី Facebook នេះ​មាន​គណនី Ayden រួច​ហើយ។',
  'pwaAuthExistsPhone': 'លេខ​ទូរស័ព្ទ​នេះ​មាន​គណនី Ayden រួច​ហើយ។',
  'pwaAuthExistsEmail': 'អ៊ីមែល​នេះ​មាន​គណនី Ayden រួច​ហើយ។',
  'pwaAuthContinueExisting': 'បន្ត​ទៅ​គណនី​ដែល​មាន​ស្រាប់​របស់​ខ្ញុំ',
  'pwaAuthErrInvalidPhone': 'លេខ​ទូរស័ព្ទ​នោះ​មើល​ទៅ​មិន​ត្រឹមត្រូវ​ទេ។',
  'pwaAuthErrContested':
      'ការ​ផ្ទៀងផ្ទាត់​សម្រាប់​លេខ​នេះ​កំពុង​ដំណើរការ​នៅ​ឡើយ។ '
      'សូម​ព្យាយាម​ម្ដង​ទៀត​ក្នុង​ពីរ​បី​នាទី​ទៀត។',
  'pwaAuthErrMismatch':
      'លេខ​កូដ​នោះ​មិន​បាន​ភ្ជាប់​ទៅ​គណនី​នេះ​ទេ។ គ្មាន​អ្វី​ត្រូវ​បាន​ផ្លាស់​ប្ដូរ​ទេ '
      '— សូម​ព្យាយាម​ម្ដង​ទៀត។',
  'pwaAuthErrCancelled': 'ការ​ចូល​ជាមួយ Facebook ត្រូវ​បាន​បោះបង់។',
  'pwaAuthErrNoEmail':
      'Facebook មិន​បាន​ចែក​រំលែក​អាសយដ្ឋាន​អ៊ីមែល​ទេ ដូច្នេះ​មិន​អាច​ភ្ជាប់​ទៅ'
      '​គណនី​នេះ​បាន​ទេ។ សូម​ប្រើ​លេខ​ទូរស័ព្ទ​របស់​អ្នក​ដើម្បី​ការពារ​វា​ជំនួស​វិញ។',
  'pwaAuthErrProvider':
      'ការ​ចូល​ជាមួយ Facebook មិន​អាច​ប្រើ​បាន​ឥឡូវ​នេះ​ទេ។ '
      'សូម​ព្យាយាម​លេខ​ទូរស័ព្ទ ឬ​អ៊ីមែល​របស់​អ្នក។',
  'pwaAuthFacebookLeaving': 'កំពុង​នាំ​អ្នក​ទៅ Facebook…',
  'pwaAuthConnectedFacebook': 'បាន​ភ្ជាប់​ជាមួយ Facebook',
  'pwaAuthConnectedPhone': 'បាន​ភ្ជាប់​ជាមួយ​ទូរស័ព្ទ',
  'pwaAuthConnectedEmail': 'បាន​ភ្ជាប់​ជាមួយ​អ៊ីមែល',
  'pwaAuthMethodsTitle': 'វិធី​ចូល​គណនី',
  'pwaAuthMethodFacebook': 'Facebook',
  'pwaAuthMethodPhone': 'ទូរស័ព្ទ',
  'pwaAuthMethodEmail': 'អ៊ីមែល',
  'pwaAuthAdd': 'បន្ថែម',
  'pwaAuthGuestBody': 'ការ​រចនា​របស់​អ្នក​ត្រូវ​បាន​រក្សា​ទុក​នៅ​លើ​ឧបករណ៍​នេះ។',
  'pwaAuthSecureCta': 'ការពារ​គណនី​របស់​ខ្ញុំ',

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
  'pwaContactSupport': 'Contacter le support',
  'pwaAboutVersion': 'Version 1.0',
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
  'pwaStep4Sub': "Briefez l'architecte avec vos propres mots.",
  'pwaStep4Hint':
      "Plus de lumière naturelle, couleurs chaudes, cosy, minimaliste, moderne…",
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
  'pwaChipCalmer': 'Rends-le plus apaisant',
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
      'Votre direction {name} est en place — même architecture, matières '
      'plus chaleureuses et lumière plus douce. Que souhaitez-vous changer ?',
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
  'pwaGetMoreSpaces': 'Acheter des Spaces',
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
  'pwaUpdatedMonthAgoOne': 'Le mois dernier',

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
  'pwaPassSpaceLeftOne': '1 Space restant',

  // -- Paywall + account (Auth/Paywall foundation) ---------------------------
  'pwaRedesignOne': '1 redesign',
  'pwaPaywallTitle': 'Continuer à créer',
  'pwaPaywallFreeUsedTitle': 'Votre vision gratuite est utilisée',
  'pwaPaywallFreeUsedBody':
      "Vous avez vu ce qu'Ayden peut faire de votre espace. Débloquez plus de "
      "visions pour continuer à l'affiner.",
  'pwaPaywallPassExhaustedTitle': 'Plus aucun Space',
  'pwaPaywallPassExhaustedBody':
      'Votre pass a été entièrement utilisé. Ajoutez des Spaces pour continuer.',
  'pwaPaywallPassRequiredTitle': 'Restaurez votre accès',
  'pwaPaywallPassRequiredBody':
      "Votre compte est Premium, mais aucun pass actif n'a été trouvé. "
      'Restaurez votre achat pour continuer à créer.',
  'pwaPaywallLoading': 'Vérification de votre compte...',
  'pwaPaywallErrorTitle': 'Impossible de vérifier votre compte',
  'pwaPaywallErrorBody':
      "Votre accès n'a pas pu être confirmé pour le moment. Vous pouvez "
      'réessayer.',
  'pwaPaywallActiveTitle': 'Votre pass est actif',
  'pwaPaywallActiveBody': 'Sans filigrane. Créez autant que vous voulez.',
  'pwaPaywallSpaces': '{n} Spaces',
  'pwaPaywallSpaceOne': '1 Space',
  'pwaPaywallDays': '{n} jours',
  'pwaPaywallUnavailableTitle': 'Les paiements ne sont pas encore ouverts',
  'pwaPaywallUnavailableBody':
      "L'achat sur le web arrive bientôt au Cambodge. Votre travail est "
      'enregistré et vous attendra.',
  'pwaPaywallStoreOnly': "Disponible dans l'application mobile",
  'pwaPaywallDiscount': '-{n}%',
  'pwaProductBadgeStarter': 'DÉCOUVERTE',
  'pwaProductBadgePopular': 'POPULAIRE',
  'pwaProductBadgeBestValue': 'MEILLEURE OFFRE',
  'pwaPaywallRestore': "J'ai déjà payé",
  'pwaPaywallClose': 'Pas maintenant',

  // -- Payment (ABA KHQR) ----------------------------------------------------
  'pwaPayBuy': 'Acheter',
  'pwaPayContinueToAba': 'Continuer vers le paiement',
  'pwaAcceptWeAccept': 'Nous acceptons',
  'pwaPayMethodTitle': 'Moyen de paiement',
  'pwaPayMethodBody':
      'Scannez pour payer avec n’importe quelle application bancaire',
  'pwaPayLinkExpiredTitle': 'Ce lien de paiement a expiré',
  'pwaPayLinkExpiredBody':
      'Les liens de paiement ne sont valables que quelques minutes. Rien '
      "n'a été débité — recommencez pour en obtenir un nouveau.",
  'pwaPayPreparing': 'Préparation de votre paiement...',
  'pwaPayScanTitle': 'Scannez pour payer',
  'pwaPayScanBody':
      'Ouvrez une application bancaire cambodgienne qui lit le KHQR et '
      'scannez ce code.',
  'pwaPayClose': 'Fermer',
  'pwaPayPluginOpen':
      'Le paiement sécurisé est ouvert. Terminez là-bas — cet écran se '
      'mettra à jour tout seul.',
  'pwaPayInlineChecking': 'Vérification de votre paiement…',
  'pwaPayInlineCancel': 'Annuler ce paiement',
  'pwaPayFailedNotCreated':
      "Le paiement n'a pas pu démarrer. Veuillez réessayer.",
  'pwaPayOpenAba': 'Ouvrir ABA Mobile',
  'pwaPayOrScan': 'ou scannez le code avec une autre application bancaire',
  'pwaPayExpiresIn': 'Ce code expire dans {t}',
  'pwaPayWaiting': 'En attente de votre paiement',
  'pwaPayConfirmingTitle': 'Confirmation de votre paiement',
  'pwaPayConfirmingBody':
      'Votre banque nous a prévenus. Nous confirmons le paiement avant '
      "d'ajouter vos Spaces.",
  'pwaPayActivatingTitle': 'Activation de vos Spaces',
  'pwaPayActivatingBody': 'Paiement confirmé. Ajout à votre compte en cours.',
  'pwaPayContinue': 'Continuer à créer',
  'pwaPayExpiredTitle': 'Ce code a expiré',
  'pwaPayExpiredBody':
      "Rien n'a été débité. Lancez un nouveau paiement quand vous voulez.",
  'pwaPayCancelledTitle': 'Paiement annulé',
  'pwaPayCancelledBody': "Rien n'a été débité.",
  'pwaPayFailedTitle': "Le paiement n'a pas abouti",
  'pwaPayFailedBody':
      "Rien n'a été ajouté à votre compte. Vous pouvez réessayer.",
  'pwaPayFailedDeclined':
      "Votre banque a refusé le paiement. Rien n'a été débité.",
  'pwaPayFailedAmount':
      "Le montant reçu ne correspond pas à cet achat : rien n'a été ajouté. "
      'Contactez-nous, nous réglerons cela.',
  'pwaPayFailedProvider':
      'Le service de paiement a refusé la demande. Veuillez réessayer.',
  'pwaPayFailedNewAttempt':
      'Ce code de paiement ne peut plus être utilisé. Lancez un nouveau '
      'paiement.',
  'pwaPayUnreachableTitle': 'Connexion perdue',
  'pwaPayUnreachableBody':
      'Votre paiement est peut-être toujours en cours. Restez sur cet écran — '
      'nous continuons à vérifier.',
  'pwaPayRetry': 'Réessayer',
  'pwaPayResultSuccessTitle': 'Paiement réussi',
  'pwaPayResultSuccessBody': '{n} Spaces ajoutés à votre portefeuille',
  'pwaPayResultSummaryTitle': 'Récapitulatif de l’achat',
  'pwaPayResultNewBalance': 'Nouveau solde',
  'pwaPayResultContinue': 'Continuer',
  'pwaPayResultFailedTitle': 'Paiement échoué / annulé',
  'pwaPayResultFailedBody': 'Aucun crédit n’a été ajouté',
  'pwaPayResultFailedHint':
      'Votre portefeuille est inchangé. Vous pouvez revenir en toute sécurité '
      'ou réessayer le paiement quand vous le souhaitez.',
  'pwaPayCancel': 'Annuler le paiement',
  'pwaPaySafeNote': 'Ayden ne voit jamais vos informations bancaires.',

  // -- Account / verification ------------------------------------------------
  'pwaAccountTitle': 'Enregistrer mes créations',
  'pwaAccountBody':
      'Créez votre compte Ayden et conservez vos créations.',
  'pwaAccountEmailLabel': 'Adresse e-mail',
  'pwaAccountEmailHint': 'vous@exemple.com',
  'pwaAccountSend': 'Envoyer le code',
  'pwaAccountCodeTitle': 'Saisissez votre code',
  'pwaAccountCodeBody': 'Nous avons envoyé un code à 6 chiffres à {email}.',
  'pwaAccountCodeLabel': 'Code de vérification',
  'pwaAccountVerify': 'Vérifier',
  'pwaAccountResend': 'Renvoyer le code',
  'pwaAccountChangeEmail': 'Utiliser une autre adresse',
  'pwaAccountSignedInAs': 'Connecté en tant que {email}',
  'pwaAccountSignOut': 'Se déconnecter',
  'pwaAccountGuestLabel': 'Invité',
  'pwaAccountLinkedTitle': 'Votre travail est enregistré',
  'pwaAccountLinkedBody':
      'Tout ce que vous avez créé est sur votre compte. Connectez-vous depuis '
      "n'importe quel appareil pour le retrouver.",
  'pwaAccountSwitchedTitle': 'Vous êtes connecté',
  'pwaAccountSwitchedBody':
      'Ce compte conserve ses propres projets et son propre accès. Ce que vous '
      "avez créé en tant qu'invité reste sur ce navigateur.",
  'pwaAccountExistsTitle': 'Cet e-mail a déjà un compte',
  'pwaAccountExistsBody':
      "Connectez-vous à ce compte. Votre travail d'invité reste sur ce "
      'navigateur et ne sera pas transféré.',
  'pwaAccountSignInInstead': 'Se connecter à ce compte',
  'pwaAccountSignInTitle': 'Se connecter',
  'pwaReplayReveal': 'Revoir',
  'pwaShareVision': 'Partager',
  'pwaShareVisionText':
      "Découvrez le redesign de mon intérieur par l'IA — {title} !",
  'pwaShareUnavailable':
      "Le partage n'est pas disponible dans ce navigateur.",
  'pwaAccountHaveOne': 'Vous utilisez déjà Ayden Studio ?',
  'pwaAccountSignInBody': 'Nous enverrons un code à votre adresse e-mail.',
  'pwaAccountBackToLink': 'Créer un nouveau compte',
  'pwaAuthErrInvalidEmail': 'Cette adresse e-mail ne semble pas valide.',
  'pwaAuthErrInvalidCode': 'Ce code est incorrect ou a expiré.',
  'pwaAuthErrRateLimited':
      'Trop de codes ont été envoyés. Patientez quelques minutes et réessayez.',
  'pwaAuthErrUnavailable': 'Impossible de joindre le service de vérification.',
  'pwaAuthErrUnknown': "Une erreur s'est produite. Veuillez réessayer.",
  'pwaAuthUnavailable':
      'Les comptes ne sont pas disponibles dans cette version.',

  // -- Cambodia auth: Facebook + phone first, email second -------------------
  'pwaAuthSecureTitle': 'Sécurisez votre compte Ayden',
  'pwaAuthSecureBody':
      "Retrouvez vos créations et vos Spaces depuis n'importe quel appareil.",
  'pwaAuthSignInChooserBody': 'Connectez-vous au compte que vous avez déjà.',
  'pwaAuthContinueFacebook': 'Continuer avec Facebook',
  'pwaAuthContinuePhone': 'Continuer avec un numéro de téléphone',
  'pwaAuthOr': 'ou',
  'pwaAuthUseEmail': 'Utiliser un e-mail',
  'pwaAuthChooseAnother': 'Choisir une autre méthode',
  'pwaAuthPhoneTitle': 'Votre numéro de téléphone',
  'pwaAuthPhoneBody': 'Nous vous enverrons un code à 6 chiffres par SMS.',
  'pwaAuthPhoneSignInBody':
      'Nous enverrons un code à 6 chiffres au numéro de votre compte.',
  'pwaAuthPhoneLabel': 'Numéro de téléphone',
  'pwaAuthPhoneHint': '012 345 678',
  'pwaAuthDialCodeLabel': 'Indicatif',
  'pwaAuthContinue': 'Continuer',
  'pwaAuthPhoneCodeBody': 'Nous avons envoyé un code à 6 chiffres au {phone}.',
  'pwaAuthChangePhone': 'Utiliser un autre numéro',
  'pwaAuthResendIn': 'Renvoyer dans {seconds} s',
  'pwaAuthCodeExpiry': 'Les codes expirent après quelques minutes.',
  'pwaAuthWelcomeBack': 'Bon retour',
  'pwaAuthExistsFacebook': 'Ce compte Facebook a déjà un compte Ayden.',
  'pwaAuthExistsPhone': 'Ce numéro de téléphone a déjà un compte Ayden.',
  'pwaAuthExistsEmail': 'Cet e-mail a déjà un compte Ayden.',
  'pwaAuthContinueExisting': 'Continuer vers mon compte existant',
  'pwaAuthErrInvalidPhone': 'Ce numéro de téléphone ne semble pas valide.',
  'pwaAuthErrContested':
      'Une vérification est encore en cours pour ce numéro. Réessayez dans '
      'quelques minutes.',
  'pwaAuthErrMismatch':
      "Ce code n'a pas été rattaché à ce compte. Rien n'a été modifié — "
      'veuillez réessayer.',
  'pwaAuthErrCancelled': 'La connexion Facebook a été annulée.',
  'pwaAuthErrNoEmail':
      "Facebook n'a pas partagé d'adresse e-mail, elle ne peut donc pas être "
      'rattachée à ce compte. Utilisez plutôt votre numéro de téléphone.',
  'pwaAuthErrProvider':
      "La connexion Facebook n'est pas disponible pour le moment. Essayez "
      'votre numéro de téléphone ou votre e-mail.',
  'pwaAuthFacebookLeaving': 'Redirection vers Facebook…',
  'pwaAuthConnectedFacebook': 'Connecté avec Facebook',
  'pwaAuthConnectedPhone': 'Connecté par téléphone',
  'pwaAuthConnectedEmail': 'Connecté par e-mail',
  'pwaAuthMethodsTitle': 'Méthodes de connexion',
  'pwaAuthMethodFacebook': 'Facebook',
  'pwaAuthMethodPhone': 'Téléphone',
  'pwaAuthMethodEmail': 'E-mail',
  'pwaAuthAdd': 'Ajouter',
  'pwaAuthGuestBody': 'Vos créations sont enregistrées sur cet appareil.',
  'pwaAuthSecureCta': 'Sécuriser mon compte',

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
