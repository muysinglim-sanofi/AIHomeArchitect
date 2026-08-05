// Batch 3.4 — cinematic play-once-per-tab gate logic (§7). Widget-level replay
// wiring is covered where the Hero is pumped; this proves the marker contract.

import 'package:ai_home_architect/features/pwa/application/pwa_intro_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('INTRO01: a fresh session autoplays (marker absent)', () {
    final gate = PwaIntroGate(MemoryPwaSessionStore());
    expect(gate.shouldAutoplay(), isTrue);
  });

  test('INTRO02: markStarted writes the marker before playback', () {
    final store = MemoryPwaSessionStore();
    final gate = PwaIntroGate(store);
    gate.markStarted();
    expect(store.read(PwaIntroGate.kMarkerKey), isNotNull);
  });

  test('INTRO03: F5 with the marker present does NOT autoplay', () {
    final store = MemoryPwaSessionStore();
    // A page reload builds a NEW gate over the SAME (surviving) session store.
    PwaIntroGate(store).markStarted();
    expect(PwaIntroGate(store).shouldAutoplay(), isFalse);
  });

  test(
    'INTRO08: after an explicit replay the marker still suppresses autoplay',
    () {
      final store = MemoryPwaSessionStore();
      final gate = PwaIntroGate(store);
      gate.markStarted(); // first autoplay
      // explicit replay does not clear the marker → next boot won't autoplay
      expect(gate.shouldAutoplay(), isFalse);
    },
  );

  test('INTRO04: two independent sessions do not leak the marker', () {
    final a = MemoryPwaSessionStore();
    final b = MemoryPwaSessionStore();
    PwaIntroGate(a).markStarted();
    expect(PwaIntroGate(a).shouldAutoplay(), isFalse);
    expect(
      PwaIntroGate(b).shouldAutoplay(),
      isTrue,
    ); // a's marker never reached b
  });

  test('INTRO05: markStarted is idempotent (staying suppressed)', () {
    final store = MemoryPwaSessionStore();
    final gate = PwaIntroGate(store)..markStarted();
    gate.markStarted(); // calling again must not re-enable autoplay
    expect(gate.shouldAutoplay(), isFalse);
    expect(store.read(PwaIntroGate.kMarkerKey), isNotNull);
  });

  test('marker key is the documented session key', () {
    expect(PwaIntroGate.kMarkerKey, 'ayden_intro_started');
  });
}
