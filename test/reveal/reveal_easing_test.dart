import 'package:ai_home_architect/shared/reveal/reveal_easing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RevealEasing', () {
    test('endpoints map to 0 and 1', () {
      for (final e in [
        RevealEasing.linear,
        RevealEasing.easeInOutCubic,
        RevealEasing.easeOutCubic,
      ]) {
        expect(e.transform(0.0), closeTo(0.0, 1e-6));
        expect(e.transform(1.0), closeTo(1.0, 1e-6));
      }
    });

    test('input is clamped outside [0,1]', () {
      expect(RevealEasing.easeInOutCubic.transform(-1.0), 0.0);
      expect(RevealEasing.easeInOutCubic.transform(2.0), 1.0);
    });

    test('linear is the identity', () {
      for (final t in [0.1, 0.25, 0.5, 0.75, 0.9]) {
        expect(RevealEasing.linear.transform(t), closeTo(t, 1e-9));
      }
    });

    test('easeInOutCubic is monotonic increasing and stays in [0,1]', () {
      var prev = -1.0;
      for (var i = 0; i <= 100; i++) {
        final y = RevealEasing.easeInOutCubic.transform(i / 100);
        expect(y, greaterThanOrEqualTo(0.0));
        expect(y, lessThanOrEqualTo(1.0));
        expect(y, greaterThanOrEqualTo(prev - 1e-9));
        prev = y;
      }
    });

    test('easeInOut is ~symmetric about its midpoint', () {
      expect(RevealEasing.easeInOutCubic.transform(0.5), closeTo(0.5, 0.05));
    });

    test('round-trips through JSON', () {
      for (final e in [
        RevealEasing.linear,
        RevealEasing.easeInOutCubic,
        RevealEasing.easeOutCubic,
      ]) {
        expect(RevealEasing.fromJson(e.toJson()), e);
      }
    });
  });
}
