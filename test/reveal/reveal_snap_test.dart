import 'package:ai_home_architect/shared/reveal/reveal_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SnapConfig.resolve (assistance, not constraint)', () {
    const snap = SnapConfig(targets: [0.0, 0.5, 1.0], threshold: 0.06);

    test('snaps to the nearest target when released within threshold', () {
      expect(snap.resolve(0.03), 0.0);
      expect(snap.resolve(0.97), 1.0);
      expect(snap.resolve(0.52), 0.5);
    });

    test('returns null when released outside every attractor', () {
      expect(snap.resolve(0.30), isNull);
      expect(snap.resolve(0.70), isNull);
    });

    test('exact target resolves to itself', () {
      expect(snap.resolve(0.0), 0.0);
      expect(snap.resolve(0.5), 0.5);
      expect(snap.resolve(1.0), 1.0);
    });

    test('picks the NEAREST when two targets are both in range', () {
      const wide = SnapConfig(targets: [0.4, 0.5], threshold: 0.2);
      expect(wide.resolve(0.46), 0.5); // 0.04 to 0.5 vs 0.06 to 0.4
      expect(wide.resolve(0.43), 0.4); // 0.03 to 0.4 vs 0.07 to 0.5
    });

    test('cinematic profile carries snap targets', () {
      final s = RevealProfile.cinematic.snap;
      expect(s, isNotNull);
      expect(s!.targets, [0.0, 0.5, 1.0]);
    });
  });
}
