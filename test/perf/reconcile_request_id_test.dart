import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/models/message_model.dart';

// PR0 — reconcile (>60s) re-attach of the ORIGINAL request_id to the DB-rebuilt
// result, so long gens still emit exactly one [PerfC2P]. Pure → free tests.
void main() {
  MessageModel img({
    String? requestId,
    String after = 'http://x/after.jpg',
    String id = 'm-img',
  }) =>
      MessageModel(
        id: id,
        content: '',
        isAi: true,
        type: MessageType.imageResult,
        result: GeneratedResult(
          beforeImageUrl: 'http://x/before.jpg',
          afterImageUrl: after,
          styleLabel: 'Warm Modern',
          projectId: 'proj',
          roomType: 'living room',
          requestId: requestId,
        ),
        createdAt: DateTime(2026, 7, 6),
      );
  MessageModel txt(String id) => MessageModel(
      id: id,
      content: 't',
      isAi: true,
      type: MessageType.text,
      createdAt: DateTime(2026, 7, 6));

  group('attachRequestIdToLatestImage', () {
    test('#2/#3/#4 long gen via reconcile: null → attached with the ORIGINAL id, non-null', () {
      final out = attachRequestIdToLatestImage([txt('a'), img(requestId: null)], 'REQ-123');
      expect(out.last.result!.requestId, 'REQ-123'); // exact original id, not minted
      expect(out.last.result!.requestId, isNotNull);
    });

    test('#1 HTTP-success normal: latest already attributed → NO-OP (unchanged)', () {
      final msgs = [txt('a'), img(requestId: 'REQ-123')];
      expect(identical(attachRequestIdToLatestImage(msgs, 'REQ-123'), msgs), isTrue);
    });

    test('#6/#7 HTTP+reconcile race: 2nd attach is a no-op (exactly one attribution)', () {
      final first = attachRequestIdToLatestImage([img(requestId: null)], 'REQ-9');
      final second = attachRequestIdToLatestImage(first, 'REQ-9');
      expect(second.last.result!.requestId, 'REQ-9');
      expect(identical(second, first), isTrue); // no second rebuild → no double
    });

    test('picks the NEWEST imageResult; earlier ones untouched', () {
      final out = attachRequestIdToLatestImage([
        img(requestId: null, after: 'old.jpg', id: 'old'),
        txt('x'),
        img(requestId: null, after: 'new.jpg', id: 'new'),
      ], 'REQ-7');
      expect(out.firstWhere((m) => m.id == 'old').result!.requestId, isNull);
      expect(out.firstWhere((m) => m.id == 'new').result!.requestId, 'REQ-7');
    });

    test('never mints on empty id → no-op', () {
      final msgs = [img(requestId: null)];
      expect(identical(attachRequestIdToLatestImage(msgs, ''), msgs), isTrue);
    });

    test('no attributable imageResult → no-op', () {
      final msgs = [txt('a'), txt('b')];
      expect(identical(attachRequestIdToLatestImage(msgs, 'REQ'), msgs), isTrue);
    });

    test('preserves every other field of the target message + result', () {
      final out = attachRequestIdToLatestImage(
          [img(requestId: null, after: 'keep.jpg', id: 'keep')], 'REQ');
      final m = out.single;
      expect(m.id, 'keep');
      expect(m.type, MessageType.imageResult);
      expect(m.result!.afterImageUrl, 'keep.jpg');
      expect(m.result!.styleLabel, 'Warm Modern');
      expect(m.result!.roomType, 'living room');
      expect(m.result!.beforeImageUrl, 'http://x/before.jpg');
    });
  });
}
