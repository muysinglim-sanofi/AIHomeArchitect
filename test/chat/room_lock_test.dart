import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/models/message_model.dart';

// CHANTIER A — room lock regression test.
// The room is settable only before the first generated vision; once the
// lineage has any vision it is immutable (atmosphere switches AND re-uploads
// must keep the session's room — the Living Room → Home Office bug).
void main() {
  MessageModel msg(MessageType type) => MessageModel(
        id: 't',
        content: '',
        isAi: false,
        type: type,
        createdAt: DateTime(2026, 1, 1),
      );

  group('sessionHasVision — room lock gate', () {
    test('empty session → room still editable (no vision yet)', () {
      expect(sessionHasVision(const <MessageModel>[]), isFalse);
    });

    test('only text/loading messages → room still editable', () {
      expect(
        sessionHasVision([msg(MessageType.text), msg(MessageType.loading)]),
        isFalse,
      );
    });

    test('once a vision exists → room LOCKED', () {
      expect(
        sessionHasVision([msg(MessageType.text), msg(MessageType.imageResult)]),
        isTrue,
      );
    });

    test('after re-upload (prior visions kept in chat) → still LOCKED', () {
      // _applyReplacedSource appends a system marker but keeps earlier visions.
      final afterReupload = [
        msg(MessageType.imageResult), // earlier vision (Apartment A)
        msg(MessageType.system), // "new source" marker
      ];
      expect(sessionHasVision(afterReupload), isTrue);
    });
  });
}
