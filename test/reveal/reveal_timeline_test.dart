import 'package:ai_home_architect/shared/reveal/reveal_profile.dart';
import 'package:ai_home_architect/shared/reveal/reveal_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

RevealFrameProgress _at(RevealProfile p, int ms) {
  final f = RevealTimeline.sample(p, Duration(milliseconds: ms));
  return RevealFrameProgress(f.progress, f.zoom);
}

class RevealFrameProgress {
  final double progress;
  final double zoom;
  RevealFrameProgress(this.progress, this.zoom);
}

void main() {
  group('RevealTimeline — cinematic', () {
    const p = RevealProfile.cinematic;

    test('holds BEFORE through the start delay and before-hold', () {
      expect(_at(p, 0).progress, 0.0); // during 300ms delay
      expect(_at(p, 900).progress, 0.0); // local 600ms, inside before-hold
      expect(_at(p, 1500).progress, 0.0); // local 1200ms, sweep start
    });

    test('settles fully on AFTER', () {
      expect(_at(p, 3300).progress, closeTo(1.0, 1e-9)); // local 3000, sweep end
      expect(_at(p, 5800).progress, closeTo(1.0, 1e-9)); // total
      expect(_at(p, 99999).progress, 1.0); // past end
    });

    test('sweep is monotonic increasing (no bounce/overshoot)', () {
      var prev = -1.0;
      for (var ms = 1500; ms <= 3300; ms += 20) {
        final v = _at(p, ms).progress;
        expect(v, greaterThanOrEqualTo(prev - 1e-9));
        expect(v, inInclusiveRange(0.0, 1.0));
        prev = v;
      }
    });

    test('zoom ramps 1.0 -> 1.05 monotonically', () {
      expect(_at(p, 0).zoom, closeTo(1.0, 1e-9));
      expect(_at(p, 5800).zoom, closeTo(1.05, 1e-9));
      var prev = 0.0;
      for (var ms = 300; ms <= 5800; ms += 50) {
        final z = _at(p, ms).zoom;
        expect(z, inInclusiveRange(1.0, 1.05 + 1e-9));
        expect(z, greaterThanOrEqualTo(prev - 1e-9));
        prev = z;
      }
    });
  });

  group('RevealTimeline — compareTease (1:1 with existing auto-sweep)', () {
    const p = RevealProfile.compareTease;

    // Existing RevealHero: fraction 0.30 -> 0.66 (hold) -> 0.42, 800ms delay,
    // 2800ms duration. In progress space (1 - fraction): 0.70 -> 0.34 -> 0.58.
    test('exact values at segment boundaries', () {
      expect(_at(p, 800).progress, closeTo(0.70, 1e-9)); // delay end / start
      expect(_at(p, 800 + 1400).progress, closeTo(0.34, 1e-9)); // sweep-open end
      expect(_at(p, 800 + 1736).progress, closeTo(0.34, 1e-9)); // hold end
      expect(_at(p, 800 + 2800).progress, closeTo(0.58, 1e-9)); // settle
    });

    test('holds at 0.34 across the constant segment', () {
      for (var ms = 800 + 1400; ms <= 800 + 1736; ms += 20) {
        expect(_at(p, ms).progress, closeTo(0.34, 1e-9));
      }
    });

    test('no zoom (preserves the existing look)', () {
      for (var ms = 0; ms <= 800 + 2800; ms += 100) {
        expect(_at(p, ms).zoom, 1.0);
      }
    });
  });

  group('RevealTimeline — invariants', () {
    test('progress and zoom stay in range for every preset', () {
      for (final p in RevealProfile.presets.values) {
        final totalMs = p.total.inMilliseconds;
        for (var ms = -200; ms <= totalMs + 200; ms += 25) {
          final f = RevealTimeline.sample(p, Duration(milliseconds: ms));
          expect(f.progress, inInclusiveRange(0.0, 1.0),
              reason: '${p.id} @ ${ms}ms progress');
          final zMax = (p.zoomFrom > p.zoomTo ? p.zoomFrom : p.zoomTo);
          final zMin = (p.zoomFrom < p.zoomTo ? p.zoomFrom : p.zoomTo);
          expect(f.zoom, inInclusiveRange(zMin - 1e-9, zMax + 1e-9),
              reason: '${p.id} @ ${ms}ms zoom');
        }
      }
    });

    test('is deterministic', () {
      const p = RevealProfile.cinematic;
      for (var ms = 0; ms <= 5800; ms += 137) {
        final a = RevealTimeline.sample(p, Duration(milliseconds: ms));
        final b = RevealTimeline.sample(p, Duration(milliseconds: ms));
        expect(a, b);
      }
    });
  });
}
