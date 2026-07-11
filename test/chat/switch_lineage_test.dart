// BUG 5 — preuve déterministe : la logique de switch (resolveAtmosphereSwitchTarget)
// est CORRECTE si la room est présente. Donc si le switch envoie room=(none), c'est que
// NI vision.roomType NI _currentRoomType n'avaient la room au moment du switch → la perte
// est EN AMONT (adoption de la réponse V1), pas dans la résolution du switch.
//
// Log prod prouvé : V1 backend renvoie room_type='living_room' (06:29:53) ; switch envoie
// room=(none) (06:30:30). Donc le frontend a reçu 'living_room' mais l'a perdu avant le switch.
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/models/message_model.dart';

GeneratedResult _vision({String? roomType}) => GeneratedResult(
      beforeImageUrl: 'before.jpg',
      afterImageUrl: 'v1_after.jpg',
      styleLabel: 'Warm Modern',
      projectId: 's1',
      roomType: roomType,
    );

void main() {
  group('BUG 5 — resolveAtmosphereSwitchTarget (logique switch)', () {
    test('vision porte la room → le switch la garde', () {
      final t = resolveAtmosphereSwitchTarget(_vision(roomType: 'living_room'),
          fallbackRoom: '');
      expect(t.room, 'living_room');
      expect(t.sourceUrl, 'v1_after.jpg');
    });

    test('vision sans room + fallback (_currentRoomType) présent → utilise le fallback', () {
      final t = resolveAtmosphereSwitchTarget(_vision(roomType: null),
          fallbackRoom: 'Living Room');
      expect(t.room, 'Living Room');
    });

    test('LE BUG : vision sans room ET _currentRoomType vide → room=null = le "(none)" du log',
        () {
      final t = resolveAtmosphereSwitchTarget(_vision(roomType: null), fallbackRoom: '');
      expect((t.room ?? '').isEmpty, isTrue); // ← room vide/null = le "(none)" envoyé au backend
    });

    test('room vide chaîne "" traitée comme absente → fallback', () {
      final t = resolveAtmosphereSwitchTarget(_vision(roomType: ''),
          fallbackRoom: 'living_room');
      expect(t.room, 'living_room');
    });
  });
}
