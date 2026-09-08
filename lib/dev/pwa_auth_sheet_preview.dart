/// VISUAL REVIEW HARNESS — not part of the product.
///
/// Renders the Cambodia account sheet (Facebook + phone + email) in every
/// state without a Supabase project that has those providers switched on, so
/// the design can be checked at 390 × 844 and 1440 × 900 before the project
/// configuration exists. It is NOT referenced by `main_pwa.dart` and is never
/// part of the product bundle; it is built explicitly, into its own folder:
///
///   flutter build web --release -t lib/dev/pwa_auth_sheet_preview.dart \
///       -o build/preview-auth --no-web-resources-cdn
///   python -m http.server 8138 -d build/preview-auth
///   http://localhost:8138/?step=chooser&locale=km
///
/// Query parameters:
///   `step`    = chooser | signin | phone | email | welcome-facebook |
///               welcome-phone | cancelled | noemail | refused
///   `locale`  = en | km | fr
///
/// The sheet is the production widget (`showPwaAccountSheet`), driven by the
/// production service over a scripted session and scripted transports — the
/// same technique the widget tests use. Typing a number and tapping Continue
/// walks the real phone → code path (the fake transport always accepts).
///
/// Nothing here talks to Supabase, Facebook, Twilio or the staging API.
library;

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/core/providers/locale_provider.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_intro_gate.dart'
    show MemoryPwaSessionStore;
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_controller.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_auth_service.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_oauth_gateway.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_phone_number.dart';
import 'package:ai_home_architect/features/pwa/auth/pwa_verification_channel.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_fonts.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_khmer_font.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_account_sheet.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _World implements GoTrueSlice, GoTrueProfileSlice, GoTrueSessionGuard {
  final String _id = 'preview-guest';
  String _email = '';
  String _phone = '';
  bool _anon = true;

  @override
  String? get currentUserId => _id;
  @override
  String get currentEmail => _email;
  @override
  bool get isAnonymous => _anon;
  @override
  bool get hasCurrentSession => true;
  @override
  Future<void> signInAnonymously() async {}
  @override
  Future<void> signOutLocal() async {}
  @override
  String get currentPhone => _phone;
  @override
  String get displayName => '';
  @override
  List<String> get providers => [
        if (_phone.isNotEmpty) 'phone',
        if (_email.isNotEmpty) 'email',
      ];
  @override
  String get currentRefreshToken => 'rt';
  @override
  Future<void> restore(String refreshToken) async {}
}

class _Channel implements PwaVerificationChannel {
  _Channel(this.kind, this.onVerified,
      {this.sendResult = const PwaVerificationResult.ok()});
  @override
  final PwaVerificationKind kind;
  final void Function(String) onVerified;
  final PwaVerificationResult sendResult;
  @override
  bool get isConfigured => true;
  @override
  bool looksValid(String d) => kind == PwaVerificationKind.phone
      ? PwaPhoneNumber.looksValid(d)
      : d.contains('@');
  @override
  Future<PwaVerificationResult> send(String d) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return sendResult;
  }

  @override
  Future<PwaVerificationResult> verify(String d, String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    onVerified(d);
    return const PwaVerificationResult.ok();
  }

  @override
  Future<PwaVerificationResult> resend(String d) async =>
      const PwaVerificationResult.ok();
}

class _NoOAuth implements PwaOAuthGateway {
  @override
  Future<bool> startLink(PwaOAuthProviderKind p, {required String redirectTo}) async =>
      true;
  @override
  Future<bool> startSignIn(PwaOAuthProviderKind p,
          {required String redirectTo}) async =>
      true;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([loadPwaKhmerFont(), loadPwaFonts()]);

  final q = Uri.base.queryParameters;
  final step = q['step'] ?? 'chooser';
  final locale = q['locale'] ?? 'en';

  final world = _World();
  // ignore: invalid_use_of_visible_for_testing_member
  final service = PwaAuthService.forTest(
    world,
    _Channel(PwaVerificationKind.email, (d) {
      world._email = d;
      world._anon = false;
    }),
    _Channel(PwaVerificationKind.email, (d) {}),
    phoneLink: _Channel(
      PwaVerificationKind.phone,
      (d) {
        world._phone = d;
        world._anon = false;
      },
      // `welcome-phone`: the number is taken — type one and tap Continue.
      sendResult: step == 'welcome-phone'
          ? const PwaVerificationResult.failed(
              PwaVerificationFailure.destinationAlreadyRegistered)
          : const PwaVerificationResult.ok(),
    ),
    phoneSignIn: _Channel(PwaVerificationKind.phone, (d) {}),
    oauth: _NoOAuth(),
    handoffStore: MemoryPwaSessionStore(),
    providers: const PwaAuthProviders(facebook: true, phone: true),
    profile: world,
    guard: world,
  );

  runApp(
    ProviderScope(
      overrides: [
        localeProvider.overrideWith((ref) => LocaleNotifier(deviceLocale: locale)),
        pwaAuthServiceProvider.overrideWithValue(service),
      ],
      child: _PreviewApp(step: step),
    ),
  );
}

class _PreviewApp extends ConsumerWidget {
  const _PreviewApp({required this.step});
  final String step;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    pwaDisableRemoteFonts();
    pwaHardenDebugPaints();
    final locale = ref.watch(localeProvider);
    pwaKhmerTypography = locale.languageCode == 'km';
    return MaterialApp(
      title: 'Ayden Studio — account sheet preview',
      theme: pwaTheme(),
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _PreviewHome(step: step),
    );
  }
}

class _PreviewHome extends ConsumerStatefulWidget {
  const _PreviewHome({required this.step});
  final String step;

  @override
  ConsumerState<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends ConsumerState<_PreviewHome> {
  PwaAuthHandoff _handoff(PwaOAuthJourney j) => PwaAuthHandoff(
        journey: j,
        provider: PwaOAuthProviderKind.facebook,
        userId: 'preview-guest',
        projectIds: const [],
        startedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  PwaOAuthReturn _ret(String q) => PwaOAuthReturn.parse(Uri.parse('https://x/p?$q'))!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final c = ref.read(pwaAuthProvider.notifier);
      switch (widget.step) {
        case 'signin':
          await showPwaAccountSheet(context, signIn: true);
        case 'phone':
          await showPwaAccountSheet(context, method: PwaAuthMethod.phone);
        case 'email':
          await showPwaAccountSheet(context, method: PwaAuthMethod.email);
        case 'welcome-facebook':
          c.applyOAuthReturn(
              _handoff(PwaOAuthJourney.link),
              _ret('error_code=identity_already_exists'
                  '&error_description=Identity+is+already+linked+to+another+user'));
          await showPwaAccountSheet(context);
        case 'welcome-phone':
          // The phone fork is reached the real way: the transport says the
          // number is taken once one is typed and Continue is tapped.
          await showPwaAccountSheet(context, method: PwaAuthMethod.phone);
        case 'cancelled':
          c.applyOAuthReturn(_handoff(PwaOAuthJourney.link),
              _ret('error=access_denied&error_description=Permissions+error'));
          await showPwaAccountSheet(context);
        case 'noemail':
          c.applyOAuthReturn(
              _handoff(PwaOAuthJourney.link),
              _ret('error=server_error&error_description='
                  'Error+getting+user+email+from+external+provider'));
          await showPwaAccountSheet(context);
        case 'refused':
          c.applyOAuthReturn(_handoff(PwaOAuthJourney.link),
              _ret('error_code=manual_linking_disabled'));
          await showPwaAccountSheet(context);
        default:
          await showPwaAccountSheet(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: pwaCanvas,
        body: Center(
          child: Text(
            'Ayden Studio — account sheet preview (${widget.step})',
            style: pwaSans(fontSize: 13, color: pwaFaint),
          ),
        ),
      );
}
