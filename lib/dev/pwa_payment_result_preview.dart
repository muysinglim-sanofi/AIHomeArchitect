/// VISUAL REVIEW HARNESS — not part of the product.
///
/// Renders Ayden's payment result card in every terminal state without a
/// payment, so the design can be checked at 390 × 844 and 1440 × 900 before a
/// preprod deploy. It is NOT referenced by `main_pwa.dart` and is never part of
/// the product bundle; it is built explicitly, into its own folder:
///
///   flutter build web --release -t lib/dev/pwa_payment_result_preview.dart \
///       -o build/preview --no-web-resources-cdn
///   python -m http.server 8137 -d build/preview
///   http://localhost:8137/?state=granted&credits=10&amount=4.99&balance=10
///
/// Query parameters: `state` = granted | failed | cancelled | expired;
/// `credits` / `amount` = what the fake server echoes for the ORDER; `balance`
/// = what the fake entitlement answers AFTER the grant; `locale` = en | km |
/// fr. The card itself is the production widget (`PwaPaymentSheet` behind
/// `showPwaPaymentReturn`), driven by a controller whose fake gateway answers
/// the requested terminal state — the same technique the widget tests use.
///
/// Nothing here talks to Supabase, PayWay or the staging API.
library;

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/core/providers/locale_provider.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement_controller.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_payment_controller.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_fonts.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_khmer_font.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_payment_sheet.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([loadPwaKhmerFont(), loadPwaFonts()]);

  final q = Uri.base.queryParameters;
  final state = (q['state'] ?? 'granted').toUpperCase();
  final credits = int.tryParse(q['credits'] ?? '') ?? 10;
  final amount = double.tryParse(q['amount'] ?? '') ?? 4.99;
  final balance = int.tryParse(q['balance'] ?? '') ?? credits;
  final locale = q['locale'] ?? 'en';

  Map<String, Object?> row() => <String, Object?>{
        'ok': true,
        'tran_id': 'PREVIEW',
        'state': state,
        'sku': 'pack_$credits',
        'credits': credits,
        'amount': amount,
        'currency': 'USD',
        'checkout_url': '',
        'checkout_mode': 'plugin',
        'failure_reason': state == 'FAILED' ? 'DECLINED' : '',
        'poll_interval_ms': 3000,
      };
  final gateway = PwaPaymentGateway(
    startCheckout: ({required sku, required attemptKey}) async => row(),
    orderStatus: (_) async => row(),
    openOrder: () async => const {'ok': true, 'open': false},
    cancelOrder: (_) async => row(),
  );
  final controller = PwaPaymentController(gateway, null);
  await controller.start('pack_$credits');

  final entitlement = PwaEntitlementController(() async => <String, Object?>{
        'can_generate': true,
        'access_source': 'pass',
        'has_active_pass': true,
        'watermarked': false,
        'pass_credits': balance,
        'credits_available': balance,
      });

  runApp(
    ProviderScope(
      overrides: [
        localeProvider.overrideWith((ref) => LocaleNotifier(deviceLocale: locale)),
        pwaPaymentProvider.overrideWith((ref) => controller),
        pwaEntitlementProvider.overrideWith((ref) => entitlement),
      ],
      child: const _PreviewApp(),
    ),
  );
}

class _PreviewApp extends ConsumerWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    pwaDisableRemoteFonts();
    pwaHardenDebugPaints();
    final locale = ref.watch(localeProvider);
    pwaKhmerTypography = locale.languageCode == 'km';
    return MaterialApp(
      title: 'Ayden Studio — result preview',
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
      home: const _PreviewHome(),
    );
  }
}

class _PreviewHome extends ConsumerStatefulWidget {
  const _PreviewHome();

  @override
  ConsumerState<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends ConsumerState<_PreviewHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showPwaPaymentReturn(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: pwaCanvas,
        body: Center(
          child: Text(
            'Ayden Studio — payment result preview',
            style: pwaSans(fontSize: 13, color: pwaFaint),
          ),
        ),
      );
}
