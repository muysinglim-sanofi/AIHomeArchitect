import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_home_architect/core/providers/pending_generations_provider.dart';
import 'package:ai_home_architect/core/providers/session_provider.dart';
import 'package:ai_home_architect/data/services/supabase_service.dart';
import 'package:ai_home_architect/features/home/home_adoption.dart';

/// GATE ANTI-RÉGRESSION PERMANENT — verrouille la COUTURE recovery↔home que les
/// anciens stress tests ne couvraient PAS (ils couvraient la couche recovery :
/// relaunch/pending/spinner, jamais la carte home / latest_preview / adoption de
/// l'image). La régression VÉCUE : "Generate lancé → je sors → l'image est perdue
/// sur la carte" venait d'un gap de couture (PR2b déléguait l'affichage au home,
/// PR3 n'a fait que le spinner). Ce test prouve le contrat de BOUT EN BOUT :
///
///   intent SUCCEEDED off-session
///   → /v1/intents/latest renvoie after_image_url
///   → decideHomeAdoption → adopt
///   → SessionNotifier.updateLatestPreview appelé (DB + état mémoire)
///   → ProjectModel.afterImageUrl = l'URL générée
///   → lifecycle → readyUnseen (badge "Ready")
///   → 2e passe = noop (aucune ré-écriture)
///
/// SupabaseService._db est un getter paresseux → un fake qui override
/// fetchSessions/updateLatestPreview ne touche jamais le réseau/Supabase.

class FakeSupabaseService extends SupabaseService {
  final List<Map<String, dynamic>> rows;
  final List<List<String>> previewCalls = []; // [sessionId, url] par appel
  FakeSupabaseService(this.rows);

  @override
  Future<List<Map<String, dynamic>>> fetchSessions() async => rows;

  @override
  Future<void> updateLatestPreview(String sessionId, String previewUrl) async {
    previewCalls.add([sessionId, previewUrl]);
  }
}

Map<String, dynamic> _row(String id, {String? preview}) => {
      'id': id,
      'title': 'New Design Session',
      'room_type': '',
      'atmosphere': "AI's choice",
      'before_image_url': 'https://src/$id.jpg',
      'latest_preview': preview, // null = la carte retombe sur la source (le bug)
      'status': 'in_progress',
      'created_at': '2026-07-08T04:20:00.000Z',
      'updated_at': '2026-07-08T04:20:00.000Z',
    };

const _sid = 'd953698c-8852-4914-9153-d34b517e118e';
const _url = 'https://gen/$_sid/vision.jpg';

Future<(ProviderContainer, FakeSupabaseService, SessionNotifier,
        PendingGenerationsNotifier)>
    _bootWith(List<Map<String, dynamic>> rows) async {
  final fake = FakeSupabaseService(rows);
  final container = ProviderContainer(overrides: [
    supabaseServiceProvider.overrideWithValue(fake),
  ]);
  final sessions = container.read(sessionProvider.notifier);
  await sessions.reload(); // attend que _load() peuple l'état de façon déterministe
  final pending = container.read(pendingGenerationsProvider.notifier);
  return (container, fake, sessions, pending);
}

void main() {
  test('COUTURE — SUCCEEDED off-session → updateLatestPreview + ProjectModel + '
      'readyUnseen ; 2e passe = noop (scénarios 1 + 5)', () async {
    final (container, fake, sessions, pending) =
        await _bootWith([_row(_sid, preview: null)]);
    addTearDown(container.dispose);

    // Départ : la carte retombe sur la source (latest_preview null) = le bug.
    expect(container.read(sessionProvider).first.afterImageUrl, isNull);

    final probe = {'status': 'SUCCEEDED', 'after_image_url': _url, 'intent_id': 'x'};
    final decision = decideHomeAdoption(
        probe: probe,
        currentPreview: container.read(sessionProvider).first.afterImageUrl);
    expect(decision.action, HomeAdoptionAction.adopt);

    applyAdoptionToNotifiers(
      sessions: sessions,
      pending: pending,
      sessionId: _sid,
      decision: decision,
      inFlightContext: false,
      currentLifecycle: container.read(pendingGenerationsProvider)[_sid],
    );

    // Couture prouvée : DB écrite, ProjectModel muté, badge Ready.
    expect(fake.previewCalls, [
      [_sid, _url]
    ]);
    expect(container.read(sessionProvider).first.afterImageUrl, _url);
    expect(container.read(pendingGenerationsProvider)[_sid],
        GenerationLifecycle.readyUnseen);

    // 2e passe : la preview locale == url → noop, AUCUNE ré-écriture (idempotent).
    final d2 = decideHomeAdoption(
        probe: probe,
        currentPreview: container.read(sessionProvider).first.afterImageUrl);
    expect(d2.action, HomeAdoptionAction.noop);
    applyAdoptionToNotifiers(
      sessions: sessions,
      pending: pending,
      sessionId: _sid,
      decision: d2,
      inFlightContext: false,
      currentLifecycle: container.read(pendingGenerationsProvider)[_sid],
    );
    expect(fake.previewCalls.length, 1); // toujours 1 write
  });

  test('COUTURE — pending déjà supprimé mais latest SUCCEEDED → adopte quand '
      'même via latest (scénario 2)', () async {
    // Aucun pending / aucun flag RAM : l'adoption ne dépend QUE du backend probe.
    final (container, fake, sessions, pending) =
        await _bootWith([_row(_sid, preview: 'https://src/$_sid.jpg')]);
    addTearDown(container.dispose);

    final probe = {'status': 'SUCCEEDED', 'after_image_url': _url, 'intent_id': 'x'};
    final decision = decideHomeAdoption(
        probe: probe,
        currentPreview: container.read(sessionProvider).first.afterImageUrl);
    expect(decision.action, HomeAdoptionAction.adopt);
    applyAdoptionToNotifiers(
      sessions: sessions,
      pending: pending,
      sessionId: _sid,
      decision: decision,
      inFlightContext: false,
      currentLifecycle: null,
    );
    expect(container.read(sessionProvider).first.afterImageUrl, _url);
    expect(fake.previewCalls, [
      [_sid, _url]
    ]);
  });

  test('COUTURE — RUNNING → keepSpinner : latest_preview intact, pas d\'adoption '
      '(scénario 3, côté home)', () async {
    final (container, fake, sessions, pending) =
        await _bootWith([_row(_sid, preview: null)]);
    addTearDown(container.dispose);

    final probe = {'status': 'RUNNING', 'intent_id': 'x'};
    final decision = decideHomeAdoption(
        probe: probe,
        currentPreview: container.read(sessionProvider).first.afterImageUrl);
    expect(decision.action, HomeAdoptionAction.keepSpinner);
    applyAdoptionToNotifiers(
      sessions: sessions,
      pending: pending,
      sessionId: _sid,
      decision: decision,
      inFlightContext: false, // lancement → pose le spinner
      currentLifecycle: null,
    );
    expect(fake.previewCalls, isEmpty); // AUCUN write de preview sur RUNNING
    expect(container.read(sessionProvider).first.afterImageUrl, isNull);
    expect(container.read(pendingGenerationsProvider)[_sid],
        GenerationLifecycle.inFlight); // spinner posé
  });

  test('COUTURE — SUCCEEDED sans after_image_url → clearSpinner : ne PAS écraser '
      'latest_preview (scénario 4)', () async {
    final existing = 'https://gen/$_sid/old.jpg';
    final (container, fake, sessions, pending) =
        await _bootWith([_row(_sid, preview: existing)]);
    addTearDown(container.dispose);

    final probe = {'status': 'SUCCEEDED', 'after_image_url': '', 'intent_id': 'x'};
    final decision = decideHomeAdoption(
        probe: probe,
        currentPreview: container.read(sessionProvider).first.afterImageUrl);
    expect(decision.action, HomeAdoptionAction.clearSpinner);
    applyAdoptionToNotifiers(
      sessions: sessions,
      pending: pending,
      sessionId: _sid,
      decision: decision,
      inFlightContext: true, // poll : nettoie le spinner
      currentLifecycle: GenerationLifecycle.inFlight,
    );
    expect(fake.previewCalls, isEmpty); // pas d'écrasement
    expect(container.read(sessionProvider).first.afterImageUrl, existing); // intact
  });
}
