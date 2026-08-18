/// Batch 3.1 / 3.4b — the DEDICATED Flutter Web PWA entrypoint (mobile/PWA
/// boundary + web-native navigation wiring).
///
/// Build with `-t lib/main_pwa.dart`. This is the ONLY supported PWA entrypoint;
/// `lib/main.dart` is mobile-only and no longer imports any PWA code. Environment
/// authority here is [PwaEnvironment] alone (never [AppEnvironment]); there is NO
/// fallback from staging → production or from mock → any remote bootstrap.
///
/// - AYDEN_ENV=mock    → fully offline: no Supabase, no remote, seeded demo.
/// - AYDEN_ENV=staging → the isolated staging Supabase client + durable restore.
/// - AYDEN_ENV=production is refused by [PwaEnvironment.current] (fail closed).
///
/// This entrypoint (and ONLY this entrypoint) wires the browser History API: it
/// reads the boot URL, resolves the durable route, and injects the web history
/// bridge + sessionStorage-backed intro gate + [PwaUrlSyncScope]. Those web-only
/// libraries (`package:web`) live behind interfaces so nothing in the widget
/// tree or `main.dart` imports them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'core/providers/locale_provider.dart';
import 'features/pwa/application/pwa_controller.dart';
import 'features/pwa/application/pwa_intro_gate.dart';
import 'features/pwa/application/pwa_route.dart';
import 'features/pwa/application/pwa_url_bridge.dart';
import 'features/pwa/auth/pwa_auth_controller.dart';
import 'features/pwa/auth/pwa_auth_service.dart';
import 'features/pwa/billing/pwa_entitlement_controller.dart';
import 'features/pwa/billing/pwa_payment_controller.dart';
import 'features/pwa/config/pwa_environment.dart';
import 'features/pwa/data/mock_pwa_experience_repository.dart';
import 'features/pwa/data/pwa_external_launcher.dart';
import 'features/pwa/data/pwa_generation_api.dart';
import 'features/pwa/data/pwa_generation_service.dart';
import 'features/pwa/data/pwa_image_url_resolver.dart';
import 'features/pwa/data/pwa_pending_generation.dart';
import 'features/pwa/data/pwa_staging_supabase_client.dart';
import 'features/pwa/data/pwa_web_navigation.dart';
import 'features/pwa/data/pwa_khmer_font.dart';
import 'features/pwa/data/supabase_pwa_persistence_repository.dart';
import 'features/pwa/domain/pwa_project.dart';
import 'features/pwa/presentation/pwa_mock_app.dart';
import 'features/pwa/presentation/pwa_url_sync_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khmer BEFORE the first frame. CanvasKit has no system fonts to fall back
  // on, and Flutter's own remote Noto fetch arrives after the first paint —
  // measured: the language menu showed nine tofu boxes, then corrected itself.
  // A Cambodia-first product cannot open on tofu. Awaited because it is a
  // local file (~114 KB, no network), and non-fatal by construction: if it
  // fails the app still boots and the remote fallback still applies.
  await loadPwaKhmerFont();

  // Single environment authority for the web app. Fails CLOSED on production /
  // misconfigured staging BEFORE anything else runs (no remote side effects).
  final env = PwaEnvironment.current();

  // The live browser-history bridge + the durable boot route (both PWA-only).
  final bridge = WebPwaUrlBridge();
  final bootRoute = PwaRoute.parse(bridge.current());

  if (env.isStaging) {
    await _bootPwaStaging(env, bridge, bootRoute);
    return;
  }

  _bootPwaMock(bridge, bootRoute);
}

/// The provider overrides every web boot shares: the live history bridge, a
/// sessionStorage-backed intro gate (cinematic once per tab, surviving F5), and
/// the locale seeded with the BROWSER's preference.
///
/// The locale override is the whole of the web-specific language resolution.
/// [LocaleNotifier] already owns "explicit choice > persisted choice >
/// fallback"; passing `deviceLocale` inserts the browser between the last two,
/// so a visitor whose browser is set to Khmer reads Khmer on their first visit
/// without touching a menu — and their first explicit pick still wins for good.
/// Mobile constructs the same notifier with no argument and is unchanged.
List<Override> _webNavOverrides(PwaUrlBridge bridge) => [
  pwaUrlBridgeProvider.overrideWithValue(bridge),
  pwaIntroGateProvider.overrideWithValue(PwaIntroGate(WebPwaSessionStore())),
  localeProvider.overrideWith(
    (ref) => LocaleNotifier(deviceLocale: _browserLanguage()),
  ),
];

/// The browser's preferred language, as a bare code ('km', 'en', 'fr'), or null.
///
/// Read from `platformDispatcher.locales`, which Flutter Web populates from
/// `navigator.languages` — the user's OWN ordered preference list. The first
/// entry the product supports wins, so a browser set to `km-KH, th, en-US`
/// resolves to Khmer rather than falling through to English.
///
/// Deliberately NOT geolocation: where a request comes from is not what
/// language a person reads, and inferring Khmer from a Cambodian IP would be
/// wrong for a large part of the actual audience.
String? _browserLanguage() {
  for (final locale in WidgetsBinding.instance.platformDispatcher.locales) {
    final code = locale.languageCode.toLowerCase();
    if (code == 'km' || code == 'en' || code == 'fr') return code;
  }
  return null;
}

/// AYDEN_ENV=mock — self-contained offline prototype. No Supabase, no network.
/// The boot URL still drives the first screen (F5 on a seeded project restores
/// it) and the address bar tracks navigation via [PwaUrlSyncScope].
void _bootPwaMock(PwaUrlBridge bridge, PwaRoute bootRoute) {
  final repo = MockPwaExperienceRepository();
  final restore = _mockBootRestore(repo, bootRoute);
  bridge.replace(restore.route?.location ?? PwaRoute.home.location);
  runApp(
    ProviderScope(
      overrides: [
        pwaRepositoryProvider.overrideWithValue(repo),
        pwaBootRestoreProvider.overrideWithValue(restore),
        // Left at their defaults (null) on purpose: mock has no backend, so
        // entitlement reads as `unavailable` (fails open, the demo generates)
        // and the account sheet says accounts are not available in this build.
        // Inventing either would make the prototype claim something untrue.
        ..._webNavOverrides(bridge),
      ],
      child: const PwaUrlSyncScope(child: PwaMockApp()),
    ),
  );
}

/// Build the offline boot restore from the seeded mock library, honouring the
/// boot URL (the URL is authority; there is no most-recent fallback in mock —
/// an unknown/absent project route normalizes to My Projects or Hero).
PwaBootRestore _mockBootRestore(
  MockPwaExperienceRepository repo,
  PwaRoute bootRoute,
) {
  final library = repo.listProjects();
  final norm = PwaRoute.normalize(
    bootRoute,
    lookup: (id) => pwaFindProject(library, id),
    libraryEmpty: library.isEmpty,
  );
  PwaProjectSnapshot? active;
  if (norm.projectId != null &&
      (norm.page == PwaPage.draft || norm.page == PwaPage.architect)) {
    active = repo.openProject(norm.projectId!);
  }
  return PwaBootRestore(
    library: library,
    active: active,
    activeSource: active?.source,
    route: norm,
  );
}

/// Staging boot (§5 order): build the ISOLATED staging Supabase client, restore
/// or create the anonymous session, hydrate the durable library + the URL-named
/// project (NOT most-recent) + its photo BEFORE the first frame, normalize the
/// address bar, then mount the PWA with staging persistence + the REAL
/// generation service + boot restore + the web navigation overrides injected.
/// Config errors propagate (fail closed).
///
/// The generation service is built HERE and nowhere else. No widget constructs
/// one, no provider falls back to a mock, and nothing reads [PwaEnvironment]
/// downstream: staging gets the real engine or the boot fails.
Future<void> _bootPwaStaging(
  PwaEnvironment env,
  PwaUrlBridge bridge,
  PwaRoute bootRoute,
) async {
  final client = await PwaStagingSupabaseClient.create(env);
  final installationId = await _pwaStagingInstallationId();
  final persistence = SupabasePwaPersistenceRepository(
    client,
    installationId: installationId,
  );

  // The real engine. The URL was validated against the exact-origin allowlist by
  // PwaEnvironment.parse; the token is read fresh per call so a session renewed
  // mid-session is used, and it is never stored in this closure.
  final api = PwaGenerationApi(
    baseUrl: env.stagingBackendUrl!,
    tokenProvider: () async {
      await client.ensureSession();
      return client.client.auth.currentSession?.accessToken;
    },
  );
  final generation = PwaStagingGenerationService(api);

  // Identity and money, built HERE for the same reason as the engine: one
  // instance, wired to the one isolated staging client, and no widget able to
  // construct its own. Both are null in mock builds, where there is no backend
  // to be honest with — and an auth UI that pretended otherwise would be a lie
  // the demo tells.
  final auth = PwaAuthService(auth: client.client.auth);

  // Private images are rendered through short-lived signed URLs minted from the
  // durable path. The path is what is stored; this is only how a pixel arrives.
  final resolver = PwaImageUrlResolver(signer: persistence.signedImageUrl);

  final pendingStore = PwaPrefsPendingGenerationStore(
    await SharedPreferences.getInstance(),
  );
  final base = await pwaResolveBootRestore(persistence, route: bootRoute);
  // A generation that was in flight when the tab was reloaded. Carried into the
  // restore so the controller can replay it with the SAME key on the first
  // frame — the backend then returns the vision it already made, if it made one.
  final pending = await pendingStore.read();
  final restore = pending == null
      ? base
      : await pwaRestoreWithPending(persistence, base, pending);

  bridge.replace(restore.route?.location ?? PwaRoute.home.location);
  runApp(
    ProviderScope(
      overrides: [
        // Staging library comes ONLY from the durable restore — never mix in the
        // offline demo seeds.
        pwaRepositoryProvider.overrideWithValue(
          MockPwaExperienceRepository(seedLibrary: false),
        ),
        pwaPersistenceProvider.overrideWithValue(persistence),
        pwaGenerationServiceProvider.overrideWithValue(generation),
        pwaImageUrlResolverProvider.overrideWithValue(resolver),
        pwaPendingGenerationStoreProvider.overrideWithValue(pendingStore),
        pwaBootRestoreProvider.overrideWithValue(restore),
        // The paywall reads THIS and never a local counter (§9).
        pwaEntitlementReaderProvider.overrideWithValue(api.entitlement),
        // The KHQR payment rail. Four server calls and no gateway: the browser
        // holds no merchant id, no api key and no signing material, because a
        // credential in a web bundle is a credential published.
        pwaPaymentGatewayProvider.overrideWithValue(
          PwaPaymentGateway(
            startCheckout: api.startCheckout,
            orderStatus: api.orderStatus,
            openOrder: api.openOrder,
            cancelOrder: api.cancelOrder,
          ),
        ),
        // Opening ABA Mobile is a browser navigation, so its implementation
        // lives with the other `package:web` adapters and is injected here.
        pwaExternalLauncherProvider
            .overrideWithValue(const WebPwaExternalLauncher()),
        pwaAuthServiceProvider.overrideWithValue(auth),
        ..._webNavOverrides(bridge),
      ],
      child: const PwaUrlSyncScope(child: PwaMockApp()),
    ),
  );
}

/// A stable per-browser installation id (client-generated UUID), persisted in
/// SharedPreferences so it survives refreshes. Non-secret; stamped on project
/// rows (nullable column) for provenance only.
Future<String> _pwaStagingInstallationId() async {
  const key = 'pwa_staging_installation_id_v1';
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString(key);
  if (id == null || id.isEmpty) {
    id = const Uuid().v4();
    await prefs.setString(key, id);
  }
  return id;
}
