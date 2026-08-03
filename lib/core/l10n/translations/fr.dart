// French (Français) translations for AYDEN Studio.
// Phase 1 i18n — native French (launch market). Double-quoted values so French
// apostrophes need no escaping.
const Map<String, String> frTranslations = {
  // App — brand name stays as-is
  'appName': 'AYDEN Studio',
  'tagline': "Votre architecte d'intérieur IA personnel.",
  'taglineSub': "Intérieur · Extérieur · Architecture",
  // Sprint 2A — brand signature lines (splash + generation loading)
  'brandSignature': "VOTRE ARCHITECTE IA PERSONNEL",
  'brandDesigningSpace': "Conception de votre espace de rêve…",

  // Onboarding
  'onboarding1Title': "Votre espace.\nTransformé.",
  'onboarding1Sub':
      "Importez une photo. Votre architecture est préservée — la vision est entièrement nouvelle.",
  'onboarding2Title': "Parlez à votre\narchitecte.",
  'onboarding2Sub':
      "Décrivez ce que vous voulez. L'IA affine votre espace, itération après itération.",
  'onboarding3Title': "Une maison,\ndes redesigns infinis.",
  'onboarding3Sub': "Transformez votre espace en un geste.",
  'getStarted': "Commencer",
  'continue': "Continuer",
  'skip': "Passer",
  'skipForNow': "Passer pour l'instant",

  // Home
  'homeHeadline': "Réimaginez\nvotre maison.",
  'homeSubtitle': "Votre architecte d'intérieur IA personnel.",
  'homeCategoryInterior': "Intérieur",
  'homeCategoryExterior': "Extérieur",
  'homeGreetingMorning': "Bonjour",
  'homeGreetingAfternoon': "Bon après-midi",
  'homeGreetingEvening': "Bonsoir",
  'newDesignSession': "Nouveau projet de design",
  'recentTransformations': "Redesigns récents",
  'latestTransformation': "Dernier redesign",
  'noProjects': "Votre première transformation\ncommence ici.",
  'seeAll': "Tout voir",
  'continueDesigning': "Continuer le design",

  // Upload
  'uploadTitle': "Votre espace",
  'uploadSubtitle': "Montrez-nous votre espace",
  'uploadHint': "Pièce intérieure, façade, jardin, piscine, terrasse...",
  'uploadPrompt': "Touchez pour importer une photo",
  'uploadFileTypes': "JPG · PNG · HEIC",
  'roomTypeLabel': "Que transformons-nous ?",
  'styleLabel': "Choisissez votre ambiance",
  'startDesign': "Lancer la transformation",
  'interiorSection': "Intérieur",
  'exteriorSection': "Extérieur",
  'takePhoto': "Prendre une photo",
  'takePhotoSub': "Meilleurs résultats avec une bonne lumière naturelle",
  'chooseGallery': "Choisir depuis la galerie",
  'chooseGallerySub': "Sélectionnez votre meilleur angle",
  'uploadYourSpace': "Importez votre espace",

  // Room types
  'livingRoom': "Salon",
  'masterBedroom': "Chambre principale",
  'kitchen': "Cuisine",
  'bathroom': "Salle de bain",
  'homeOffice': "Bureau",
  'diningRoom': "Salle à manger",
  'entranceHall': "Entrée",
  'houseFacade': "Façade",
  'garden': "Jardin",
  'poolArea': "Espace piscine",
  'terrace': "Terrasse",
  'balcony': "Balcon",
  'driveway': "Allée",

  // Suggestion chips — fallback statique (affiché quand pas de suggestion dynamique)
  'suggPushFurther': "Accentuer cette direction",
  'suggMoreDaylight': "Plus de lumière naturelle",
  'suggCalmerAtmo': "Atmosphère plus calme",
  'suggOpenSpace': "Ouvrir l'espace visuellement",
  'suggSofterLighting': "Éclairage indirect plus doux",
  'suggOtherPalette': "Essayer une autre palette",
  'suggCalmerStrong': "Rendre l'atmosphère plus apaisante",

  // Chat
  'chatTitle': "Session de design",
  'chatPlaceholder': "Comment cet espace doit-il évoluer ?",
  'chatGeneratingHint': "Génération de votre vision...",
  'voiceListening': "À l'écoute… Touchez pour arrêter",
  'genReadyAiSurprise': "Votre espace est prêt. Je vais lire l'architecture, choisir une direction adaptée et générer votre première vision.",
  'genReadySurprise': "Votre espace est prêt. Je vais choisir une ambiance qui convient à cet espace et générer votre première vision.",
  'genReadyAiDecide': "Votre espace est prêt. Je vais analyser votre espace et générer votre première vision {style}.",
  'genReadyDefault': "Votre espace est prêt. Génération de votre première vision {style}.",
  'genStartError': "Impossible de lancer la génération. Veuillez réessayer.",
  'sessionUnavailable': "Cette session n'est plus disponible.",
  'reuploadError': "Impossible d'envoyer la nouvelle photo. Veuillez réessayer.",
  'genLongWait': "Votre vision prend un peu plus de temps que d'habitude, mais j'y travaille toujours.",
  'genTransportInterrupted': "Une interruption de connexion s'est produite. Votre design est peut-être en route — veuillez patienter un instant.",
  'genTookLonger': "Votre design a pris plus de temps que prévu. Il arrivera peut-être bientôt — ou touchez le bouton pour réessayer.",
  'continuingFromVision': "On continue à partir de cette vision. Décrivez le prochain changement, ou ouvrez Direction artistique pour explorer une autre ambiance.",
  'homeDesignReady': "Un design est prêt — touchez la session pour le voir.",
  'homeDesignFailed': "Une génération a échoué — touchez la session pour voir les détails.",
  'notifReadyTitle': "Votre vision est prête",
  'notifReadyBody': "Touchez pour voir votre nouveau design.",
  'notifFailedTitle': "Échec de la génération",
  'notifFailedBody': "Touchez pour ouvrir la session et voir ce qui s'est passé.",
  'notifViewAction': "Voir",
  'generateButton': "Générer",
  'generatingInChat': "Génération de votre transformation...",

  // Inline result
  'viewBeforeAfter': "Voir le résultat complet",
  'saveDesign': "Enregistrer",
  'shareDesign': "Partager",
  'tryAnother': "En essayer un autre",

  // Generation
  'generatingTitle': "Création de votre\ntransformation",
  'generatingSubtitle': "Chaque détail, pensé.",

  // Before/After
  'beforeLabel': "Original",
  'afterLabel': "Vision",
  'exploreOtherAtmospheres': "Explorer d'autres ambiances",
  'saveResult': "Enregistrer",
  'shareResult': "Partager",
  'newVariation': "En essayer un autre",
  'dragToReveal': "Glissez pour révéler",
  'yourTransformation': "Votre redesign",

  // History
  'historyTitle': "Redesigns",
  'newProject': "+ Nouveau redesign",

  // Redesign vocabulary
  'transformation': "redesign",
  'transformations': "redesigns",

  // Profile
  'profileTitle': "Profil",
  'signOut': "Se déconnecter",
  'projectsCount': "Redesigns",
  'sharedCount': "Partagés",

  // Account (Continuer avec Apple)
  'acctSectionTitle': "COMPTE",
  'acctSaveDesignsSubtitle':
      "Enregistrez vos designs et retrouvez-les sur vos autres appareils.",
  'acctContinueWithApple': "Lier ce profil invité à Apple",
  'acctConnectedWithApple': "Connecté avec Apple",
  'acctSignInExisting': "Utiliser un autre compte Ayden",
  'acctAppleAlreadyLinked':
      "Impossible de lier ce compte Apple ici. Vous pouvez utiliser un autre compte Ayden à la place.",
  'acctConnectedSuccess': "Votre compte est maintenant connecté.",
  'acctConnectedPending':
      "Votre compte est connecté. Nous terminons la configuration.",
  'acctMergeFailed':
      "Connecté. Certains anciens designs peuvent ne pas apparaître ici pour l'instant — ils restent en sécurité sur votre compte.",
  'acctRetrySetup': "Réessayer la configuration du compte",
  'acctNotAvailable': "La connexion au compte n'est pas encore disponible.",
  'acctGenericError': "Une erreur s'est produite. Veuillez réessayer.",
  'acctSignOut': "Se déconnecter",
  'acctSignOutConfirmTitle': "Se déconnecter ?",
  'acctSignOutConfirmBody':
      "Vous reviendrez en mode invité. Votre compte et vos designs restent intacts ; vous pourrez vous reconnecter à tout moment.",
  'acctSignOutConfirm': "Se déconnecter",
  'acctSignOutCancel': "Annuler",
  'acctSignedOut': "Vous êtes maintenant en mode invité.",
  'acctSignOutFailed': "Impossible de se déconnecter. Veuillez réessayer.",

  // Settings
  'settingsLanguage': "Langue",
  'english': "English",
  'khmer': "ខ្មែរ",
  'french': "Français",
  'settingsAccount': "COMPTE",
  'settingsSupport': "ASSISTANCE",
  'editProfile': "Modifier le profil",
  'notifications': "Notifications",
  'privacy': "Confidentialité",
  'helpCenter': "Centre d'aide",
  'rateApp': "Noter l'application",
  'about': "À propos",
  'chooseLanguage': "Choisir la langue",

  // Hero
  'featuredVision': "Vision en vedette",

  // Source photo
  'sourcePhoto': "Photo source",
  'replacePhoto': "Remplacer la photo",
  'sourcePhotoUpdated': "Photo source mise à jour",

  // Chat timeline & project state
  'vision': "vision",
  'visions': "visions",
  'lastUpdated': "Dernière mise à jour",
  'visionCreated': "Vision créée",
  'today': "Aujourd'hui",
  'yesterday': "Hier",
  'readyToCreate': "Prêt à créer",

  // FTUE (onboarding demo)
  'ftueBefore': "Avant",
  'ftueAfter': "Après",
  'ftueAiVision': "Vision IA",
  'ftueDemoUser': "Rendez mon salon chaleureux et accueillant, surprenez-moi",
  'ftueDemoAi': "Warm Modern — bois, lumière douce du soir",
  'ftueDemoRefining': "Affinement de l'espace…",

  // Atmosphere taglines + subtitles (noms gardés en anglais — option A)
  'atmoTagline_warm_modern': "Confort contemporain et chaleur accueillante",
  'atmoTagline_japandi_calm': "Harmonie nippo-scandinave et sobriété",
  'atmoTagline_soft_luxury': "Matières élégantes et lumière du soir raffinée",
  'atmoTagline_nordic_warmth':
      "Tons scandinaves chaleureux et lumière naturelle",
  'atmoTagline_tropical_escape':
      "Chaleur luxuriante de resort et textures naturelles",
  'atmoSubtitle_warm_modern':
      "Inspiré des villas boutique au coucher du soleil",
  'atmoSubtitle_japandi_calm': "Inspiré des retraites sereines de Kyoto",
  'atmoSubtitle_soft_luxury': "Inspiré des hôtels boutique 5 étoiles",
  'atmoSubtitle_nordic_warmth':
      "Inspiré des escapades hivernales scandinaves",
  'atmoSubtitle_tropical_escape': "Inspiré des resorts de luxe de Bali",

  // Paywall (V2)
  'pwHeadline': "Créez votre maison de rêve avec l'IA",
  // V2 hero — découpé pour le retour ligne + le mot accent en or.
  'pwHeadlineLead': "Créez votre",
  'pwHeadlineAccent': "avec l'IA",
  'pwHeadlineTrail': "maison de rêve",
  'pwSubheadline':
      "Redessinez votre espace avec votre architecte IA personnel.",
  'pwLovedBy': "Adoré par ",
  'pwHomeowners': " propriétaires",
  'pwAnnual': "Annuel",
  'pwWeekly': "Hebdomadaire",
  'pwBestValue': "MEILLEURE OFFRE",
  'pwPopular': "POPULAIRE",
  'pwPerYear': "/ an",
  'pwPerWeek': "/ semaine",
  'pwAnnualPositioning': "Idéal pour un projet maison complet",
  'pwWeeklyPositioning': "Parfait pour essayer Ayden",
  'pwBenefitEveryRoom': "Toutes les pièces et ambiances",
  'pwBenefitUnlimited': "Transformations illimitées",
  'pwBenefitPriority': "Support prioritaire",
  'pwBenefitHd': "Exports HD",
  'pwSavings': "Économisez 65 % · seulement 1,55 \$ / semaine",
  'pwSavingsShort': "−65 %",
  'pwChoose': "Choisir",
  'pwBilledYearly': "Facturé annuellement · Annulable à tout moment",
  'pwBilledWeekly': "Facturé chaque semaine · Annulable à tout moment",
  'pwHowItWorks': "Comment ça marche",
  'pwStep1': "Importez votre pièce",
  'pwStep2': "Explorez styles et ambiances",
  'pwStep3': "Affinez avec votre architecte IA",
  'pwStep4': "Révélez la transformation de vos rêves",
  'pwGuarantee': "Satisfaction garantie 7 jours",
  'pwGuaranteeSub': "Pas convaincu ? Remboursement intégral sous 7 jours.",
  'pwSecurePayments': "Paiements sécurisés",
  'pwFeatUnlimited': "Chaque pièce",
  'pwFeatHd': "Rendus HD",
  'pwFeatAllStyles': "Tous les styles",
  'pwFeatNoWatermark': "Sans filigrane",
  // Contenu des cartes (V2) — langage « espaces », jamais « crédits »/« générations ».
  'pwPlanBadgeAnnual': "Maison complète",
  'pwPlanBadgeWeekly': "Démarrage rapide",
  'pwAnnualSpaces': "Jusqu'à 300 espaces",
  'pwAnnualSpacesSub': "Idéal pour condos, maisons et rénovations",
  'pwWeeklySpaces': "Jusqu'à 30 espaces",
  'pwWeeklySpacesSub': "Idéal pour maisons et appartements",
  'pwUnlockPremium': "Débloquer Premium",
  'pwCancelAnytime': "Annulable à tout moment. Sans engagement.",
  // Apple Guideline 3.1.2 — mentions obligatoires abonnement auto-renouvelable.
  'pwLegalDisclosure':
      "Le paiement est débité sur votre compte Apple ID à la confirmation de "
      "l'achat. L'abonnement se renouvelle automatiquement sauf annulation au "
      "moins 24 heures avant la fin de la période en cours, et le renouvellement "
      "est facturé dans les 24 heures précédant la fin de la période. Vous pouvez "
      "gérer ou annuler votre abonnement dans les réglages de votre compte Apple. "
      "Déjà abonné ? Utilisez Restaurer l'achat sur cet écran.",
  'pwPrivacyPolicy': "Politique de confidentialité",
  'pwTermsOfUse': "Conditions d'utilisation",
  'pwAlreadySubscribed': "Déjà abonné ? ",
  'pwRestore': "Restaurer l'achat",
  'pwNotNow': "Plus tard",
  'pwErrIncomplete': "L'achat n'a pas abouti. Veuillez réessayer.",
  'pwPurchasePendingActivation':
      "Achat reçu — activation en cours. Si Premium n'apparaît pas, touchez Restaurer l'achat.",
  'pwErrNotAvailable':
      "Les achats ne sont pas encore disponibles dans cette version de test.",
  'pwErrFailed': "L'achat a échoué. Veuillez réessayer.",
  'pwErrNoRestore': "Aucun achat précédent trouvé sur cet appareil.",

  // Bottom navigation
  'navHome': "Accueil",
  'navProjects': "Projets",
  'navProfile': "Profil",

  // Upload (new design flow + premium picker)
  'uplGenerateDesign': "Générer le design",
  'uplWillCreate': "L'IA va créer votre redesign",
  'uplPrivacy': "Vos photos sont privées et sécurisées.",
  'uplPickerSubtitle':
      "Choisissez votre photo, ou découvrez Ayden instantanément.",
  'uplCamera': "Appareil photo",
  'uplGallery': "Galerie",
  'uplExamplePhotos': "Photos d'exemple",
  'uplExampleHint':
      "Essayez avec une de nos photos d'exemple pour voir la magie.",
  'uplExampleLoadError': "Impossible de charger la photo d'exemple.",
  'uplOwnSpace': "Importez votre propre espace",
  'uplTryInstantly': "Essayez Ayden instantanément",
  'uplOr': "OU",
  'uplRecommended': "Recommandé",
  'uplMoreSpaces': "Plus d'espaces",
  'uplAiDecide': 'Ayden décide',
  'uplAiDecideSub': "Laissez l'IA détecter l'espace pour moi",
  'uplSurpriseMe': "Surprenez-moi",
  'uplSurpriseSub': "Laissez l'IA choisir une ambiance adaptée",
  'uplCustomSub': "Dites-le avec vos propres mots",
  'uplStep1Sub': "Importez une photo de la pièce, façade, jardin ou tout espace à redessiner.",
  'uplStep2Title': "Quel type d'espace transformons-nous ?",
  'uplStep2Sub': "Choisissez le type d'espace à transformer.",
  'uplStep3Title': "Choisissez votre ambiance",
  'uplStep3Sub':
      "Sélectionnez l'atmosphère et le style qui définissent votre espace.",
  'uplStep4Title': "Décrivez votre vision",
  'uplStep4Sub':
      "Briefez l'architecte avec vos propres mots. Vous pouvez parler ou écrire.",
  'uplStepWord': "ÉTAPE",
  'uplStepOf4': "SUR 4",
  'uplOptional': "Optionnel",
  'uplStepperUpload': "Importer",
  'uplStepperRoom': "Type de pièce",
  'uplStepperAtmosphere': "Ambiance",
  'uplStepperVision': "Votre vision",
  'uplHintAddPhoto': "Ajoutez une photo de votre espace pour commencer",
  'uplHintChooseRoom': "Choisissez une pièce — ou laissez l'IA décider",
  'uplHintPickAtmosphere':
      "Choisissez une ambiance — ou laissez l'IA vous surprendre",

  // Premium / quota status card
  'stFreePlan': "Forfait gratuit",
  'stPremiumActive': "Premium actif",
  'stAdminFullAccess': "Admin · accès complet",
  'stUnlimited': "Accès complet · toutes les pièces et ambiances",
  'stGenerationSingular': "espace gratuit restant",
  'stGenerationPlural': "espaces gratuits restants",
  'stPassCreditsRemaining': "{n} Spaces restants",
  'stPassValidUntil': "Valable jusqu'au {date}",
  'stRestoreRequired': "Restaurer l'achat",
  'stRestoreRequiredSub': "Restaurez votre abonnement pour continuer",
  'stRestoring': "Restauration de votre achat…",
  'stPassNoSpaces': '0 Spaces restants',
  'pcPassNoSpaces': 'Aucun Space restant',
  'pcPassActiveNoSpacesNoDate': 'Votre formule est active, mais il ne reste aucun Space.',
  'stPassRenews': 'Renouvellement le {date}',
  'stRestoreDone': 'Achat restauré',
  'stRestoreActiveNoSpaces': 'Abonnement actif — les espaces se rechargent au renouvellement',
  'stRestoreNoneFound': 'Aucun abonnement actif trouvé sur ce compte',
  'stRestoreFailed': 'Restauration impossible. Veuillez réessayer.',
  'pcCurrentPlan': 'Formule actuelle',
  'pcWeeklyPremium': 'Premium hebdomadaire',
  'pcAnnualPremium': 'Premium annuel',
  'pcPromotionActive': 'Promotion active',
  'pcPremiumAccess': 'Accès Premium',
  'pcManageSubscription': 'Gérer l\'abonnement',
  'pcUpgradeTitle': 'Améliorez votre formule',
  'pcUpgradeSpaces': '300 Spaces',
  'pcUpgradeBestValue': 'Meilleure offre',
  'pcUpgradeCta': 'Passer à l\'annuel',
  'pcUpgradeConfirmTitle': 'Passer à l\'annuel ?',
  'pcUpgradeConfirmBody':
      'Votre formule annuelle démarrera immédiatement avec 300 Spaces. Vos Spaces hebdomadaires restants seront remplacés. Apple appliquera tout remboursement au prorata éligible.',
  'pcUpgradeConfirmYes': 'Passer à l\'annuel',
  'pcUpgradeConfirmNo': 'Pas maintenant',
  'pcUpgradeActivating': 'Activation de votre formule annuelle…',
  'pcUpgradeDone': 'Vous êtes maintenant en Premium annuel.',
  'pcUpgradeFailed':
      'Impossible de finaliser le changement. Veuillez réessayer.',
  'pcUpgradeDeferred':
      'Votre achat a réussi. Nous mettons encore votre formule à jour.',
  'pcUpgradeRefreshPlan': 'Actualiser la formule',

  // Chat reupload / design-direction sheet
  'chatPleaseUpload': "Veuillez d'abord importer une photo source.",
  'chatNewSourceMsg': "Nouvelle photo source — nouvelle vision.",
  'chatEvolvingVision': "Évolution de cette vision",
  'chatDesignEvolution': "ÉVOLUTION DU DESIGN",
  'chatSpaceType': "TYPE D'ESPACE",
  'chatAtmosphere': "AMBIANCE",
  'chatApplyDirection': "Appliquer",
  'chatCurrent': "Actuel",

  // Profile sheets (settings)
  'spDisplayName': "NOM AFFICHÉ",
  'spFirstName': "PRÉNOM",
  'spLastName': "NOM",
  'spEmail': "E-MAIL",
  'spYourName': "Votre nom",
  'spSaveChanges': "Enregistrer",
  'spSaved': "Enregistré",
  'spSaveFailed': "Échec de l'enregistrement. Réessayez.",
  'spNotifSubtitle': "Choisissez ce qui vous inspire.",
  'spNotif1Title': "Mises à jour de redesign",
  'spNotif1Sub': "Progrès de vos designs en cours",
  'spNotif2Title': "Génération terminée",
  'spNotif2Sub': "Quand votre vision est prête à être révélée",
  'spNotif3Title': "Inspiration hebdomadaire",
  'spNotif3Sub': "Idées architecturales sélectionnées",
  'spNotif4Title': "Nouveautés produit",
  'spNotif4Sub': "Nouvelles fonctionnalités et améliorations",
  'spPrivacyTitle': "Confidentialité et données",
  'spPrivacySubtitle':
      "Votre confiance est le fondement de tout ce que nous construisons.",
  'spPrivacy1Title': "Vos photos",
  'spPrivacy1Body':
      "Les photos que vous importez sont traitées de manière sécurisée pour générer vos visions architecturales. Elles ne sont jamais conservées au-delà de votre session active, jamais utilisées pour entraîner des modèles d'IA, et jamais partagées avec des tiers.",
  'spPrivacy2Title': "Génération IA",
  'spPrivacy2Body':
      "Vos sessions de design sont traitées par notre pipeline de génération IA. Les conversations et les prompts servent uniquement à produire votre vision — ils ne sont pas conservés après la génération.",
  'spPrivacy3Title': "Votre contrôle",
  'spPrivacy3Body':
      "Vous pouvez supprimer vos sessions de design à tout moment. L'export complet des données, la suppression de compte et des contrôles de confidentialité avancés arrivent dans la prochaine version.",
  'spPrivacyComingSoon':
      "D'autres contrôles de confidentialité arrivent bientôt. Nous nous engageons à vous donner la pleine propriété de vos données.",
  'spHelpSubtitle': "Tout ce qu'il vous faut pour créer la maison de vos rêves.",
  'spFaq1Q': "Comment fonctionne AYDEN Studio ?",
  'spFaq1A':
      "Importez une photo de votre espace, choisissez une direction d'ambiance, et décrivez ce que vous ressentez. Notre architecte IA transforme votre espace en une vision avant/après cinématique.",
  'spFaq2Q': "Qu'inclut le Premium ?",
  'spFaq2A':
      "Le Premium débloque toutes les pièces et toutes les ambiances avec votre architecte IA personnel, plus les exports HD. Deux formules : Premium Hebdomadaire pour un projet maison complet, ou Premium Annuel pour toute l'année.",
  'spFaq3Q': "Puis-je remplacer la photo source ?",
  'spFaq3A':
      "Oui. Dans n'importe quel redesign, touchez la bande de la photo source en haut pour ouvrir l'espace Direction de design. Vous pouvez changer la photo et ajuster votre ambiance à tout moment.",
  'spFaq4Q': "Puis-je partager mes redesigns ?",
  'spFaq4A':
      "Oui — depuis n'importe quel écran de résultat, touchez Partager pour envoyer votre révélation avant/après à qui vous voulez. Enregistrez-la aussi dans votre galerie.",
  'spStillNeedHelp': "Besoin d'aide ?",
  'spRateTitle': "Comment trouvez-vous l'expérience jusqu'ici ?",
  'spRateSubtitle':
      "Vos retours nous aident à créer une meilleure expérience de design.",
  'spSubmit': "Envoyer",
  'spThankYou': "Merci !",
  'spThankYouSub': "Vos retours comptent énormément pour nous.",
  'spClose': "Fermer",
  'spAboutVersion': "Version 1.0 · Aperçu MVP",
  'spAboutTagline':
      "Votre architecte IA personnel.\nImaginez. Affinez. Révélez.",
  'spCopyright': "© 2026 AYDEN Studio. Tous droits réservés.",

  // Generation loading phrases (ordered narrative)
  'genInit1': "Lecture de votre espace…",
  'genInit2': "Préservation de l'architecture…",
  'genInit3': "Étude de la lumière et des ouvertures…",
  'genInit4': "Composition des matières et de la palette…",
  'genInit5': "Équilibre du réalisme et des proportions…",
  'genInit6': "Affinement de la composition…",
  'genInit7': "Finalisation de votre vision…",
  'genRef1': "Reprise du design actuel…",
  'genRef2': "Maintien stable de l'architecture…",
  'genRef3': "Application de votre direction…",
  'genRef4': "Évolution des matières et de la lumière…",
  'genRef5': "Équilibre du réalisme et de la profondeur…",
  'genRef6': "Affinement des détails…",
  'genRef7': "Finalisation de votre vision…",
  'genFlavorSoftLuxury': "Superposition de chaleur, douceur et luxe discret…",
  'genFlavorWarmModern': "Réchauffement des matières et de la lumière…",
  'genFlavorJapandi': "Équilibre du calme, du bois et de l'espace…",
  'genFlavorZen': "Installation du calme et de la sérénité…",
  'genFlavorTropical': "Apport de texture naturelle et de lumière…",
  'genFlavorBali': "Tissage de texture organique et de calme…",
  'genFlavorNordic': "Adoucissement avec bois pâle et chaleur hygge…",
  'genFlavorDesert': "Superposition de tons sable et d'ombres sculptées…",
  'genFlavorNatureRetreat': "Apport de nature brute et de calme ancré…",

  // Accès promo — libellés de statut passifs uniquement. La rédemption in-app
  // et le panneau admin ont été retirés (conformité App Store ; Premium débloqué
  // uniquement via StoreKit/RevenueCat) ; ceci ne fait qu'étiqueter un octroi promo.
  'promoAccessUnlimited': "Accès VIP actif",
  'promoAccessLabel': "Accès promo",
  'promoAccessLimited': "Accès promo · {n} générations restantes",
};
