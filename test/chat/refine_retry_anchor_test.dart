import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/models/message_model.dart';

// 8b-4b — le [Retry] d'une carte « Still missing » ne doit JAMAIS appliquer les
// changements manquants d'une vision ancienne sur une vision plus récente
// (« bonne modif, mauvaise vision »). L'ancrage est une fonction pure testable.
void main() {
  RefineReportInfo info({
    String after = 'https://cdn/v6.jpg',
    List<String>? missing,
  }) =>
      RefineReportInfo(
        report: 'Still missing\n□ add a round rug',
        missingRaws: missing ?? const ['add a round rug'],
        afterUrl: after,
        sourceVersionId: 'ver_6',
      );

  group('refineRetryAllowed — ancrage à la vision incomplète exacte', () {
    test('la carte est encore le tip actif → autorisé', () {
      expect(
        refineRetryAllowed(info(after: 'https://cdn/v6.jpg'), 'https://cdn/v6.jpg'),
        isTrue,
      );
    });

    test('old report after newer generation → refusé (bonne modif, mauvaise vision)', () {
      // La carte ancre la Vision 6 (v6.jpg) ; l'utilisateur a généré une Vision 7,
      // donc la source active est maintenant v7.jpg. Le Retry doit être refusé.
      expect(
        refineRetryAllowed(info(after: 'https://cdn/v6.jpg'), 'https://cdn/v7.jpg'),
        isFalse,
      );
    });

    test('continue-from-vision vers une vision plus ancienne → refusé', () {
      // _continueFromVision a repointé la source active sur une AUTRE vision (v1).
      expect(
        refineRetryAllowed(info(after: 'https://cdn/v6.jpg'), 'https://cdn/v1.jpg'),
        isFalse,
      );
    });

    test('aucune source active (null) → refusé', () {
      expect(refineRetryAllowed(info(), null), isFalse);
    });

    test('ancre vide → refusé (jamais deviner la cible)', () {
      expect(refineRetryAllowed(info(after: ''), 'https://cdn/v6.jpg'), isFalse);
    });

    test('aucun changement manquant → refusé', () {
      expect(
        refineRetryAllowed(info(missing: const <String>[]), 'https://cdn/v6.jpg'),
        isFalse,
      );
    });
  });

  group('dedupePreservingOrder — un seul appel /refine par instruction distincte', () {
    test('supprime les doublons (trim + casse) en préservant l\'ordre', () {
      expect(
        dedupePreservingOrder(
            ['Move the sofa', 'move the sofa ', 'add a rug', 'MOVE THE SOFA']),
        ['Move the sofa', 'add a rug'],
      );
    });

    test('écarte les entrées vides / blanches', () {
      expect(dedupePreservingOrder(['', '   ', 'add a lamp']), ['add a lamp']);
    });

    test('liste vide → liste vide', () {
      expect(dedupePreservingOrder(const <String>[]), isEmpty);
    });
  });
}
