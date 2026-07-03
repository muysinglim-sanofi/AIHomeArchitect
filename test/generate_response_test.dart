import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/features/chat/generate_response.dart';

// PR2b Slice 1 — the /generate response contract, tested as a pure function.
void main() {
  group('classifyGenerateResult', () {
    test('after_image_url present → image (normal success)', () {
      expect(classifyGenerateResult({'after_image_url': 'http://x/y.jpg'}),
          GenerateResultKind.image);
    });

    test('has image + replayed flag → image (byte-identical replay)', () {
      expect(
          classifyGenerateResult(
              {'after_image_url': 'http://x', 'replayed': true}),
          GenerateResultKind.image);
    });

    test('status running, NO image → running (202 duplicate)', () {
      expect(
          classifyGenerateResult({'status': 'running', 'intent_id': 'a'}),
          GenerateResultKind.running);
    });

    test('empty after_image_url + running → running (not misread as image)', () {
      expect(
          classifyGenerateResult({'after_image_url': '', 'status': 'running'}),
          GenerateResultKind.running);
    });

    test('status failed → failed', () {
      expect(classifyGenerateResult({'status': 'failed'}),
          GenerateResultKind.failed);
    });

    test('status failed_terminal → failed', () {
      expect(classifyGenerateResult({'status': 'failed_terminal'}),
          GenerateResultKind.failed);
    });

    test('unknown/absent status, no image → image (legacy default)', () {
      expect(classifyGenerateResult({}), GenerateResultKind.image);
    });
  });
}
