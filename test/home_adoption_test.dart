import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/features/home/home_adoption.dart';

// Fix "adopt completed generations after session exit" — la décision d'adoption
// de l'accueil est une fonction PURE (backend-first). Ces tests épinglent chaque
// branche, mappée aux scénarios du spec.
void main() {
  group('decideHomeAdoption', () {
    test('probe null (requête échouée) → noop (ne jamais agir à l\'aveugle)', () {
      final d = decideHomeAdoption(probe: null, currentPreview: null);
      expect(d.action, HomeAdoptionAction.noop);
    });

    test('RUNNING → keepSpinner (scénario 3 : ne pas clear, pas de double POST)', () {
      final d = decideHomeAdoption(
          probe: {'intent_id': 'x', 'status': 'RUNNING'}, currentPreview: null);
      expect(d.action, HomeAdoptionAction.keepSpinner);
    });

    test('SUCCEEDED + after_image_url + carte sans preview → adopt (scénario 1)', () {
      final d = decideHomeAdoption(
        probe: {'status': 'SUCCEEDED', 'after_image_url': 'http://img.jpg'},
        currentPreview: null,
      );
      expect(d.action, HomeAdoptionAction.adopt);
      expect(d.afterUrl, 'http://img.jpg');
    });

    test('SUCCEEDED + after_image_url remplace une source → adopt (scénario 2 : '
        'pending déjà supprimé, on adopte quand même via latest)', () {
      final d = decideHomeAdoption(
        probe: {'status': 'SUCCEEDED', 'after_image_url': 'http://new.jpg'},
        currentPreview: 'http://source.jpg',
      );
      expect(d.action, HomeAdoptionAction.adopt);
      expect(d.afterUrl, 'http://new.jpg');
    });

    test('SUCCEEDED + after_image_url == preview locale → noop (scénario 5 : déjà '
        'adopté, aucune ré-écriture)', () {
      final d = decideHomeAdoption(
        probe: {'status': 'SUCCEEDED', 'after_image_url': 'http://img.jpg'},
        currentPreview: 'http://img.jpg',
      );
      expect(d.action, HomeAdoptionAction.noop);
    });

    test('SUCCEEDED sans after_image_url → clearSpinner (scénario 4 : ne pas '
        'écraser latest_preview)', () {
      final d = decideHomeAdoption(
        probe: {'status': 'SUCCEEDED', 'after_image_url': ''},
        currentPreview: 'http://source.jpg',
      );
      expect(d.action, HomeAdoptionAction.clearSpinner);
    });

    test('FAILED → markError', () {
      final d = decideHomeAdoption(
          probe: {'status': 'FAILED'}, currentPreview: null);
      expect(d.action, HomeAdoptionAction.markError);
    });

    test('FAILED_TERMINAL → markError (statut terminal légitime, #5)', () {
      final d = decideHomeAdoption(
          probe: {'status': 'FAILED_TERMINAL'}, currentPreview: null);
      expect(d.action, HomeAdoptionAction.markError);
    });

    test('refine terminé hors-session (backend a mappé generated_image_url → '
        'after_image_url) → adopt (scénario 7 : refine récupéré, pas cassé)', () {
      final d = decideHomeAdoption(
        probe: {'status': 'SUCCEEDED', 'after_image_url': 'http://refine.jpg'},
        currentPreview: 'http://old.jpg',
      );
      expect(d.action, HomeAdoptionAction.adopt);
      expect(d.afterUrl, 'http://refine.jpg');
    });
  });
}
