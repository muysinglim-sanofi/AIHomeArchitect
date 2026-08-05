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

import 'features/pwa/application/pwa_controller.dart';
import 'features/pwa/application/pwa_intro_gate.dart';
import 'features/pwa/application/pwa_route.dart';
import 'features/pwa/application/pwa_url_bridge.dart';
import 'features/pwa/config/pwa_environment.dart';
import 'features/pwa/data/mock_pwa_experience_repository.dart';
import 'features/pwa/data/pwa_staging_supabase_client.dart';
import 'features/pwa/data/pwa_web_navigation.dart';
import 'features/pwa/data/supabase_pwa_persistence_repository.dart';
import 'features/pwa/domain/pwa_project.dart';
import 'features/pwa/presentation/pwa_mock_app.dart';
import 'features/pwa/presentation/pwa_url_sync_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

/// The provider overrides every web boot shares: the live history bridge and a
/// sessionStorage-backed intro gate (cinematic once per tab, surviving F5).
List<Override> _webNavOverrides(PwaUrlBridge bridge) => [
  pwaUrlBridgeProvider.overrideWithValue(bridge),
  pwaIntroGateProvider.overrideWithValue(PwaIntroGate(WebPwaSessionStore())),
];

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
/// address bar, then mount the PWA with staging persistence + boot restore + the
/// web navigation overrides injected. Config errors propagate (fail closed).
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
  final restore = await pwaResolveBootRestore(persistence, route: bootRoute);
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
        pwaBootRestoreProvider.overrideWithValue(restore),
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
