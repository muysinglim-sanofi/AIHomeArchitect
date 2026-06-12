import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/models/message_model.dart';

// Regression test for the multi-upload atmosphere-switch bug.
//
// Repro that produced the two reported failures:
//   1. Generate V1 (photo A) — Living Room / Japandi.
//   2. Re-upload photo B in the SAME session → a second V1 (Living Room / Japandi).
//   3. Open the SECOND V1 and change atmosphere → Soft Luxury.
//
// Observed before the fix:
//   • BUG 2 (local) — the switch used the FIRST V1 as its source image.
//   • BUG 1 (iPhone) — the switch ran with room "Home Office" instead of
//     "Living Room".
//
// Root cause: the switch read session-level globals (current source url /
// current room) instead of the clicked vision. `resolveAtmosphereSwitchTarget`
// now binds source + room to the vision itself; these tests pin that contract.
void main() {
  group('resolveAtmosphereSwitchTarget — switch binds to the clicked vision', () {
    const visionA = GeneratedResult(
      beforeImageUrl: 'photo_a.jpg',
      afterImageUrl: 'render_a_japandi.jpg',
      styleLabel: 'Japandi Calm',
      projectId: 'p1',
      roomType: 'Living Room',
    );
    const visionB = GeneratedResult(
      beforeImageUrl: 'photo_b.jpg',
      afterImageUrl: 'render_b_japandi.jpg',
      styleLabel: 'Japandi Calm',
      projectId: 'p1',
      roomType: 'Living Room',
    );

    test('BUG 2 — source is the clicked vision, never an older one', () {
      final t = resolveAtmosphereSwitchTarget(visionB, fallbackRoom: 'Living Room');
      expect(t.sourceUrl, 'render_b_japandi.jpg');
      expect(t.sourceUrl, isNot(visionA.afterImageUrl)); // not the first V1
    });

    test('BUG 1 — room comes from the vision, overriding a stale global', () {
      // The stale session global is polluted with the wrong room (iPhone repro).
      final t = resolveAtmosphereSwitchTarget(visionB, fallbackRoom: 'Home Office');
      expect(t.room, 'Living Room'); // vision wins over the stale global
    });

    test('legacy vision without a room falls back to the current room', () {
      const legacy = GeneratedResult(
        beforeImageUrl: 'b.jpg',
        afterImageUrl: 'r.jpg',
        styleLabel: 'X',
        projectId: 'p1',
        // roomType omitted → null (a result loaded from DB before the fix)
      );
      final t = resolveAtmosphereSwitchTarget(legacy, fallbackRoom: 'Bedroom');
      expect(t.room, 'Bedroom');
    });

    test('empty afterImageUrl yields a null source (guard, no crash)', () {
      const empty = GeneratedResult(
        beforeImageUrl: 'b.jpg',
        afterImageUrl: '',
        styleLabel: 'X',
        projectId: 'p1',
        roomType: 'Living Room',
      );
      final t = resolveAtmosphereSwitchTarget(empty);
      expect(t.sourceUrl, isNull);
      expect(t.room, 'Living Room');
    });
  });
}
