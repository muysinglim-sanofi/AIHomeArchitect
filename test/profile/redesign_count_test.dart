// P0 bloc (b) H — "Redesigns" = générations RÉUSSIES uniquement (plus sessionProvider.length).
// Une session ne porte un afterImageUrl (row latest_preview) qu'APRÈS une génération réussie,
// donc une 4e tentative bloquée par le paywall (session vide) ne doit JAMAIS incrémenter.
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/features/profile/profile_screen.dart';
import 'package:ai_home_architect/data/models/project_model.dart';

ProjectModel _p({String? after}) => ProjectModel(
      id: 'x',
      title: 't',
      roomType: 'living_room',
      style: 'warm_modern',
      afterImageUrl: after,
      status: ProjectStatus.inProgress,
      createdAt: DateTime(2026),
      lastUpdatedAt: DateTime(2026),
      messages: const [],
      iterationCount: 0,
    );

void main() {
  group('P0 bloc (b) H — countSuccessfulRedesigns', () {
    test('compte uniquement les sessions ayant produit une image finale', () {
      final sessions = [
        _p(after: 'https://cdn/img1.jpg'),
        _p(after: null), // tentative bloquée / paywall → session vide
        _p(after: ''), // pas d'image finale
        _p(after: 'https://cdn/img2.jpg'),
      ];
      expect(countSuccessfulRedesigns(sessions), 2);
    });

    test('3 réussies + 4e tentative bloquée (sans image) → 3, jamais 4', () {
      final trois = List.generate(3, (_) => _p(after: 'url'));
      expect(countSuccessfulRedesigns(trois), 3);
      final avecBloquee = [...trois, _p(after: null)];
      expect(countSuccessfulRedesigns(avecBloquee), 3);
    });

    test('liste vide → 0', () {
      expect(countSuccessfulRedesigns(const []), 0);
    });
  });
}
