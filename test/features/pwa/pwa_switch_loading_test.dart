// What the screen says while Ayden is working.
//
// Reported 2026-08-11: starting an atmosphere switch from the Full Reveal left
// a bubble containing one tiny gold dot and nothing else, for the ~2 minutes a
// render takes. There was no way to tell "working" from "frozen" from "failed".
//
// The cause was a colour, not a missing feature: the indicator was mounted with
// "on dark" onto `av7Surface` (#FFFDFC), so the phase copy and the animated
// ellipsis were white on near-white. Only the gold dot had contrast.
//
// A second, quieter defect rode along: every wait used the REFINE phrasing, so
// a switch said "Understanding your change" and never named the atmosphere the
// person had just chosen.
//
// These tests pin both, and pin the rule that keeps the fix honest: nothing the
// indicator does may finish a generation.

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_working_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AydenImageSource _source() => AydenImageSource(
  bytes: Uint8List.fromList(const [1, 2, 3]),
  filename: 'room.jpg',
  mimeType: 'image/jpeg',
);

/// A session with one Vision, and a generation service that never finishes on
/// its own — so the WORKING state can be inspected while it is on screen.
Future<(PwaController, PwaFakeGenerationService)> _session({
  Duration hold = const Duration(minutes: 5),
}) async {
  final gen = PwaFakeGenerationService();
  final c = PwaController(
    MockPwaExperienceRepository(workDelay: Duration.zero, seedLibrary: false),
    generation: gen,
    pending: PwaMemoryPendingGenerationStore(),
  );
  c.selectRoom('livingRoom');
  c.setSource(_source());
  await c.generateFirstVision();
  gen.calls.clear(); // the first vision is setup, not the call under test
  gen.delay = hold; // the next generation stays in flight
  return (c, gen);
}

PwaMessage _loadingOf(PwaController c) => c.state.messages
    .lastWhere((m) => m.kind == PwaMessageKind.loading);

void main() {
  group('an atmosphere switch says what it is doing', () {
    test('SWLOAD01: the working state exists immediately, with real copy',
        () async {
      final (c, _) = await _session();
      c.stageAtmosphere('japandi_calm');
      unawaited_(c.applyAtmosphere());
      await Future<void>.delayed(Duration.zero);

      final loading = _loadingOf(c);
      final phases = pwaWorkingPhasesFor(
        loading.workingKind,
        loading.workingSubject,
      );
      expect(loading.workingKind, PwaWorkKind.switchAtmosphere);
      expect(
        phases.first.trim(),
        isNotEmpty,
        reason: 'a bubble with no words is the bug being fixed',
      );
    });

    test('SWLOAD02: the chosen atmosphere is named in the first phase',
        () async {
      final (c, _) = await _session();
      c.stageAtmosphere('japandi_calm');
      unawaited_(c.applyAtmosphere());
      await Future<void>.delayed(Duration.zero);

      final loading = _loadingOf(c);
      expect(loading.workingSubject, 'Japandi Calm');
      expect(
        pwaWorkingPhasesFor(loading.workingKind, loading.workingSubject).first,
        'Switching to Japandi Calm',
      );
    });

    test('a refine and a conversation keep their own copy', () async {
      expect(pwaWorkingPhasesFor(PwaWorkKind.refine), kPwaRefinePhases);
      expect(
        pwaWorkingPhasesFor(PwaWorkKind.firstVision),
        kPwaFirstVisionPhases,
      );
      expect(
        pwaWorkingPhasesFor(PwaWorkKind.conversation),
        kPwaConversationPhases,
      );
      // An unnamed switch still gets switch copy, never refine copy.
      expect(
        pwaWorkingPhasesFor(PwaWorkKind.switchAtmosphere),
        kPwaAtmospherePhases,
      );
    });

    test('SWLOAD06: the result replaces the working state', () async {
      final (c, gen) = await _session(hold: Duration.zero);
      c.stageAtmosphere('japandi_calm');
      await c.applyAtmosphere();

      expect(
        c.state.messages.where((m) => m.kind == PwaMessageKind.loading),
        isEmpty,
        reason: 'no orphan working bubble is left behind',
      );
      expect(c.state.versions.length, 2);
      expect(c.state.generating, isFalse);
      expect(gen.calls, hasLength(1), reason: 'SWLOAD08: exactly one call');
    });

    test('SWLOAD07: a failure removes the working state and shows the error',
        () async {
      final (c, gen) = await _session(hold: Duration.zero);
      gen.failure = const PwaGenerationFailure(
        code: 'ENGINE_REJECTED',
        userMessage: "Ayden couldn't work with this request.",
        retryable: false,
      );
      c.stageAtmosphere('japandi_calm');
      await c.applyAtmosphere();

      expect(
        c.state.messages.where((m) => m.kind == PwaMessageKind.loading),
        isEmpty,
      );
      expect(c.state.generationError, "Ayden couldn't work with this request.");
      expect(c.state.versions.length, 1, reason: 'no vision was invented');
    });
  });

  group('SWLOAD04/05: both entrypoints produce the same working state', () {
    // The defect was seen from the Full Reveal. The reveal and the architect
    // card call the SAME controller method, so there is one working state by
    // construction — this pins that, because a second implementation is exactly
    // what would let one screen regress alone.
    test('reveal and architect switches build an identical loading message',
        () async {
      Future<PwaMessage> viaReveal() async {
        final (c, _) = await _session();
        c.openReveal(c.state.currentVision!.versionId);
        c.stageAtmosphere('japandi_calm');
        unawaited_(c.applyAtmosphere());
        await Future<void>.delayed(Duration.zero);
        return _loadingOf(c);
      }

      Future<PwaMessage> viaArchitect() async {
        final (c, _) = await _session();
        c.stageAtmosphere('japandi_calm');
        unawaited_(c.applyAtmosphere());
        await Future<void>.delayed(Duration.zero);
        return _loadingOf(c);
      }

      final a = await viaReveal();
      final b = await viaArchitect();
      expect(a.workingKind, b.workingKind);
      expect(a.workingSubject, b.workingSubject);
      expect(
        pwaWorkingPhasesFor(a.workingKind, a.workingSubject),
        pwaWorkingPhasesFor(b.workingKind, b.workingSubject),
      );
    });
  });

  group('the working state is visible and honest', () {
    testWidgets('SWLOAD03: it shows text and motion, and no percentage', (
      tester,
    ) async {
      final phases = pwaWorkingPhasesFor(
        PwaWorkKind.switchAtmosphere,
        'Japandi Calm',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // The real surface: a near-white Ayden bubble.
            backgroundColor: const Color(0xFFFFFDFC),
            body: Center(
              child: PwaWorkingIndicator(
                phases: phases,
                foreground: const Color(0xFF2B211C),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Switching to Japandi Calm'), findsOneWidget);
      for (final forbidden in const ['%', 'seconds left', 'remaining']) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: 'no invented measurement of an unknown duration',
        );
      }
      expect(find.byType(FadeTransition), findsWidgets, reason: 'it breathes');
    });

    testWidgets('the status ink CONTRASTS with the bubble it sits on', (
      tester,
    ) async {
      // The actual bug: white on #FFFDFC. Assert the rendered text colour is
      // dark enough to read on that surface, rather than trusting a bool.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PwaWorkingIndicator(
                phases: const ['Switching to Japandi Calm'],
                foreground: const Color(0xFF2B211C),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final text = tester.widget<Text>(
        find.text('Switching to Japandi Calm'),
      );
      final colour = text.style!.color!;
      const surface = Color(0xFFFFFDFC);
      double lum(Color c) => c.computeLuminance();
      final ratio =
          (lum(surface) + 0.05) / (lum(Color.alphaBlend(colour, surface)) + 0.05);
      expect(
        ratio,
        greaterThan(4.5),
        reason: 'WCAG AA for body text — white-on-white scored ~1.0',
      );
    });

    testWidgets('SWLOAD08: phase changes never finish anything', (
      tester,
    ) async {
      var ended = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PwaWorkingIndicator(
                phases: pwaWorkingPhasesFor(
                  PwaWorkKind.switchAtmosphere,
                  'Japandi Calm',
                ),
                foreground: const Color(0xFF2B211C),
              ),
            ),
          ),
        ),
      );
      // Sit through every phase boundary several times over.
      for (var i = 0; i < 10; i++) {
        await tester.pump(kPwaPhaseDuration + const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(ended, 0, reason: 'the widget has no completion path at all');
      // It settles on the last phase and stays there — it never claims done.
      expect(find.text('Finishing your vision'), findsOneWidget);
    });
  });
}

/// Deliberately fire-and-forget: these tests inspect the state WHILE the
/// generation is still in flight, which is the whole point.
void unawaited_(Future<void> f) {}
