// Batch 2.2 — PWA Architect controller semantics. Deterministic (zero-delay
// mock), no real services / timers / network — pure state-machine assertions.

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_route.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_mock_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:flutter_test/flutter_test.dart';

PwaController makeController() {
  final repo = MockPwaExperienceRepository(workDelay: Duration.zero);
  return PwaController(
    repo,
    generation: PwaMockGenerationService(repo),
    pending: PwaMemoryPendingGenerationStore(),
  );
}

AydenImageSource fakeSource() => AydenImageSource(
  bytes: Uint8List.fromList(const [1, 2, 3]),
  filename: 'r.jpg',
);

/// A controller whose generation seam can answer with an advisory, standing in
/// for what the canonical backend advisor would return.
class _AdvisoryRig {
  _AdvisoryRig()
    : generation = PwaFakeGenerationService(),
      _repo = MockPwaExperienceRepository(
        workDelay: Duration.zero,
        seedLibrary: false,
      ) {
    controller = PwaController(
      _repo,
      generation: generation,
      pending: PwaMemoryPendingGenerationStore(),
    );
  }

  final PwaFakeGenerationService generation;
  final MockPwaExperienceRepository _repo;
  late final PwaController controller;
}

_AdvisoryRig _advisoryRig() => _AdvisoryRig();

Future<PwaController> generated() async {
  final c = makeController();
  c.setSource(fakeSource());
  await c.generateFirstVision();
  return c;
}

void main() {
  group('a typed line is not classified locally', () {
    // Replaces the old `classifyTextIntent` unit tests. That heuristic decided
    // advice-vs-refine from a keyword list in the browser, and it is gone: the
    // canonical `refine.parser` + `refine.advisor` decide on the backend, as
    // they already do for mobile. What is asserted now is the DELEGATION.
    test('every typed line reaches the canonical pipeline', () async {
      final c = await generated();
      final before = c.state.versions.length;

      c.sendUserText('What do you think about opening this wall?');
      await pumpEventQueue();

      // The user's words are in the conversation…
      expect(
        c.state.messages.any(
          (m) => m.role == PwaRole.user && m.text.contains('opening this wall'),
        ),
        isTrue,
      );
      // …and the outcome came from the pipeline, not from a local verdict:
      // exactly one new vision, and no invented "Want me to apply it?" copy.
      expect(c.state.versions.length, before + 1);
      expect(
        c.state.messages.any((m) => m.text.contains('Want me to apply')),
        isFalse,
        reason: 'the PWA must not compose Ayden advice',
      );
    });

    test('an empty line does nothing at all', () async {
      final c = await generated();
      final before = c.state.messages.length;
      c.sendUserText('   ');
      await pumpEventQueue();
      expect(c.state.messages, hasLength(before));
    });
  });

  group('Primary flow — the session IS the container (§31)', () {
    test(
      'generateFirstVision → the architect, holding Vision 1',
      () async {
        final c = await generated();
        // No unveiling in between: the render arrives in the conversation.
        expect(c.state.phase, PwaPhase.architect);
        expect(c.state.versions, hasLength(1));
        expect(c.state.hasSource, isTrue); // the "Original" source is preserved
        final v1 = c.state.currentVision!;
        expect(v1.visionNumber, 1);
        expect(v1.actionType, PwaActionType.signature);
        expect(c.state.selectedAtmosphereId, 'ayden_signature');
      },
    );

    test('FIRST rich message is an Ayden reveal bound to V1 (§11)', () async {
      final c = await generated();
      final first = c.state.messages.first;
      expect(first.role, PwaRole.ayden);
      expect(first.kind, PwaMessageKind.reveal);
      expect(first.visionId, c.state.currentVision!.versionId);
      expect(first.text, isNotEmpty);
    });
  });

  group('Advice — decided by the canonical advisor', () {
    // The verdict is the BACKEND's. These tests configure the seam to answer
    // the way the canonical advisor would, and assert how the controller
    // presents it: an objection is an answer, never a vision and never an error.
    test(
      'an advisory creates no version and shows the advisor words',
      () async {
        final rig = _advisoryRig();
        final c = rig.controller;
        c.setSource(fakeSource());
        await c.generateFirstVision();
        final beforeVer = c.state.versions.length;
        final beforeReveal = c.state.currentVision!.versionId;

        rig.generation.advisory = const PwaGenerationAdvisory(
          verdict: 'yellow',
          message: 'Which wall do you mean — the left or the right one?',
        );
        c.sendUserText('open the wall');
        await pumpEventQueue();

        expect(c.state.versions.length, beforeVer, reason: 'no vision');
        expect(c.state.currentVision!.versionId, beforeReveal);
        expect(c.state.generating, isFalse);
        expect(c.state.generationError, isNull, reason: 'not a failure');

        final last = c.state.messages.last;
        expect(last.kind, PwaMessageKind.text);
        expect(last.role, PwaRole.ayden);
        expect(last.text, contains('Which wall do you mean'));
        expect(last.pendingRefine, 'open the wall');
        expect(last.chips, contains('Continue anyway'));
        // No placeholder is left behind.
        expect(
          c.state.messages.where((m) => m.kind == PwaMessageKind.loading),
          isEmpty,
        );
      },
    );

    test('Continue anyway resends the SAME instruction with confirm', () async {
      final rig = _advisoryRig();
      final c = rig.controller;
      c.setSource(fakeSource());
      await c.generateFirstVision();

      rig.generation.advisory = const PwaGenerationAdvisory(
        verdict: 'red',
        message: 'I would not recommend that.',
      );
      c.sendUserText('add a bathtub');
      await pumpEventQueue();
      expect(c.state.versions, hasLength(1));

      await c.applyRefine('add a bathtub', confirm: true);
      await pumpEventQueue();

      final last = rig.generation.calls.last;
      expect(last.confirm, isTrue);
      expect(last.userInstruction, 'add a bathtub');
      expect(c.state.versions, hasLength(2), reason: 'the user overrode it');
    });
  });

  group('Refine confirm (§17–24)', () {
    test('a green instruction EXECUTES — no "Apply this change" step', () async {
      // The old contract asked the user to confirm every instruction, using
      // copy composed in the browser. The canonical contract executes what the
      // advisor passes, and only objects when the advisor objects.
      final c = await generated();
      final parent = c.state.currentVision!;
      c.sendUserText('Make it warmer');
      await pumpEventQueue();

      expect(c.state.versions, hasLength(2), reason: 'it ran');
      final child = c.state.currentVision!;
      expect(child.actionType, PwaActionType.refine);
      expect(child.parentVersionId, parent.versionId);
      expect(c.state.messages.last.kind, PwaMessageKind.reveal);
      expect(
        c.state.messages.any((m) => m.text.contains('Want me to apply')),
        isFalse,
      );
    });

    test('Cancel (dismissRefine) creates no version', () async {
      // Still reachable: an advisory offers "Continue anyway", and dismissing
      // it must leave the project untouched.
      final rig = _advisoryRig();
      final c = rig.controller;
      c.setSource(fakeSource());
      await c.generateFirstVision();
      rig.generation.advisory = const PwaGenerationAdvisory(
        verdict: 'yellow',
        message: 'Which wall?',
      );
      c.sendUserText('open the wall');
      await pumpEventQueue();

      final offer = c.state.messages.last;
      c.dismissRefine(offer.id);
      expect(c.state.versions, hasLength(1));
      expect(c.state.messages.every((m) => m.pendingRefine == null), isTrue);
    });

    test(
      'applyRefine creates exactly ONE child; parent = source vision',
      () async {
        final c = await generated();
        final parent = c.state.currentVision!;
        await c.applyRefine('Make it warmer');
        expect(c.state.versions, hasLength(2));
        final child = c.state.currentVision!;
        expect(child.actionType, PwaActionType.refine);
        expect(child.parentVersionId, parent.versionId);
        expect(c.state.messages.last.kind, PwaMessageKind.reveal);
      },
    );
  });

  group('Atmosphere switch confirm (§25–30)', () {
    test('staging is pending only — no version, reveal unchanged', () async {
      final c = await generated();
      final shown = c.state.currentVision!.versionId;
      c.stageAtmosphere('japandi_calm');
      expect(c.state.pendingAtmosphereId, 'japandi_calm');
      expect(c.state.versions, hasLength(1)); // no version on selection
      expect(c.state.currentVision!.versionId, shown); // reveal unchanged
    });

    test('selecting the current atmosphere clears pending', () async {
      final c = await generated();
      c.stageAtmosphere('japandi_calm');
      c.stageAtmosphere('ayden_signature'); // = current → clears
      expect(c.state.pendingAtmosphereId, isNull);
    });

    test('Cancel clears pending, creates no version', () async {
      final c = await generated();
      c.stageAtmosphere('soft_luxury');
      c.cancelPendingAtmosphere();
      expect(c.state.pendingAtmosphereId, isNull);
      expect(c.state.versions, hasLength(1));
    });

    test('Confirm creates ONE child storing the atmosphere', () async {
      final c = await generated();
      final parent = c.state.currentVision!;
      c.stageAtmosphere('japandi_calm');
      await c.applyAtmosphere();
      expect(c.state.versions, hasLength(2));
      final child = c.state.currentVision!;
      expect(child.actionType, PwaActionType.switchAtmosphere);
      expect(child.atmosphereId, 'japandi_calm');
      expect(child.parentVersionId, parent.versionId);
      expect(c.state.pendingAtmosphereId, isNull);
    });
  });

  group('Version preservation & lineage (§32–33)', () {
    test('every generated vision stays; none overwritten', () async {
      final c = await generated();
      final v1 = c.state.currentVision!;
      c.stageAtmosphere('soft_luxury');
      await c.applyAtmosphere();
      await c.applyRefine('More natural light');
      expect(c.state.versions, hasLength(3));
      // v1 still present, byte-identical fields (immutable).
      final stillV1 = c.state.versions.firstWhere(
        (v) => v.versionId == v1.versionId,
      );
      expect(stillV1.visionNumber, v1.visionNumber);
      expect(stillV1.atmosphereId, v1.atmosphereId);
      expect(stillV1.afterAsset, v1.afterAsset);
    });
  });

  group('Preview / Set current / Continue (§34–38)', () {
    test('previewVision shows an older version, current unchanged', () async {
      final c = await generated();
      final v1 = c.state.currentVision!.versionId;
      c.stageAtmosphere('nordic_warmth');
      await c.applyAtmosphere(); // v2 current
      c.previewVision(v1);
      expect(c.state.previewedVision!.versionId, v1);
      expect(c.state.isPreviewingOther, isTrue);
      expect(c.state.currentVisionId, isNot(v1)); // current still v2
      expect(c.state.versions, hasLength(2)); // no new version
    });

    test('setCurrentVision — no version, no chat marker', () async {
      final c = await generated();
      final v1 = c.state.currentVision!.versionId;
      c.stageAtmosphere('tropical_escape');
      await c.applyAtmosphere();
      final msgs = c.state.messages.length;
      c.setCurrentVision(v1);
      expect(c.state.currentVisionId, v1);
      expect(c.state.messages.length, msgs); // no marker
      expect(c.state.versions, hasLength(2));
    });

    test('continueFromVision reparents the NEXT child (branch)', () async {
      final c = await generated();
      final v1 = c.state.currentVision!.versionId;
      c.stageAtmosphere('nordic_warmth');
      await c.applyAtmosphere(); // v2 current
      c.continueFromVision(v1); // sets source=v1, adds marker, current stays v2
      expect(c.state.messages.last.text, contains('Continuing from Vision 1'));
      expect(c.state.currentVisionId, isNot(v1)); // current unchanged
      await c.applyRefine('Open the kitchen'); // v3 branches off v1
      expect(c.state.currentVision!.parentVersionId, v1);
    });

    test(
      'revealMessageIdForVersion resolves the reveal message (§37)',
      () async {
        final c = await generated();
        c.stageAtmosphere('japandi_calm');
        await c.applyAtmosphere();
        final v2 = c.state.currentVision!;
        final mid = c.state.revealMessageIdForVersion(v2.versionId);
        expect(mid, isNotNull);
        final msg = c.state.messages.firstWhere((m) => m.id == mid);
        expect(msg.kind, PwaMessageKind.reveal);
        expect(msg.visionId, v2.versionId);
      },
    );
  });

  group('Vision navigation — preview only (§25 / V7)', () {
    Future<PwaController> withThreeVisions() async {
      final c = await generated(); // v1
      c.stageAtmosphere('soft_luxury');
      await c.applyAtmosphere(); // v2 (current)
      await c.applyRefine('More natural light'); // v3 (current)
      return c;
    }

    test('previewedIndex + bounds reflect the shown vision', () async {
      final c = await withThreeVisions();
      // Current (v3) is the last → no next, has previous.
      expect(c.state.previewedIndex, 2);
      expect(c.state.hasNextVision, isFalse);
      expect(c.state.hasPreviousVision, isTrue);
    });

    test('previewPrevious/Next step without creating a version', () async {
      final c = await withThreeVisions();
      final before = c.state.versions.length;
      c.previewPrevious(); // → v2
      expect(c.state.previewedVision!.visionNumber, 2);
      expect(c.state.isPreviewingOther, isTrue);
      expect(c.state.currentVision!.visionNumber, 3); // current unchanged
      c.previewPrevious(); // → v1
      expect(c.state.previewedVision!.visionNumber, 1);
      expect(c.state.hasPreviousVision, isFalse);
      c.previewPrevious(); // clamped — no-op
      expect(c.state.previewedVision!.visionNumber, 1);
      c.previewNext(); // → v2
      expect(c.state.previewedVision!.visionNumber, 2);
      expect(c.state.versions.length, before); // never created a version
    });

    test('previewNext clamps at the newest vision', () async {
      final c = await withThreeVisions();
      expect(c.state.hasNextVision, isFalse);
      c.previewNext(); // no-op at the end
      expect(c.state.previewedVision!.visionNumber, 3);
    });
  });

  group('Back home (§5)', () {
    test(
      'returnToStudio → the dashboard, project saved, session dropped',
      () async {
        final c = await generated();
        c.selectRoom('kitchen');
        c.stageAtmosphere('soft_luxury');
        await c.applyAtmosphere();
        final id = c.state.activeProjectId;
        final versions = c.state.versions.length;
        c.returnToStudio();
        // Home is a dashboard, not a half-finished Create: the in-memory session
        // is dropped so Back can never resurrect the last photo.
        expect(c.state.phase, PwaPhase.home);
        expect(c.state.hasSource, isFalse);
        expect(c.state.versions, isEmpty);
        // …and the durable project is intact and reopenable.
        final saved = c.state.library.where((p) => p.projectId == id);
        expect(saved, hasLength(1));
        expect(saved.first.visions.length, versions);
        await c.openProject(id);
        expect(c.state.phase, PwaPhase.architect);
        expect(c.state.versions.length, versions);
      },
    );
  });

  group('New Project always opens an EMPTY Create', () {
    test(
      'the previous photo, room and atmosphere never leak forward',
      () async {
        final c = await generated();
        c.selectRoom('kitchen');
        expect(c.state.hasSource, isTrue);
        c.newProject();
        expect(c.state.phase, PwaPhase.entry);
        expect(c.state.hasSource, isFalse);
        expect(c.state.selectedRoomId, isNull); // Ayden Decide
        expect(c.state.selectedAtmosphereId, 'ayden_signature');
        expect(c.state.versions, isEmpty);
        expect(c.state.messages, isEmpty);
        expect(c.state.canonicalRoute, PwaRoute.create);
      },
    );

    test('the app opens on the dashboard, not on Create', () {
      final c = makeController();
      expect(c.state.phase, PwaPhase.home);
      expect(c.state.canonicalRoute, PwaRoute.home);
    });
  });

  group('Isolation (§46–47)', () {
    test('generation is deterministic + guards concurrency', () async {
      final c = await generated();
      c.stageAtmosphere('japandi_calm');
      final f1 = c.applyAtmosphere();
      // A second confirm while generating is a no-op (no duplicate).
      await c.applyAtmosphere();
      await f1;
      expect(c.state.versions, hasLength(2));
    });
  });

  group('Coverage hardening', () {
    test('Ayden Signature is first in the atmosphere catalogue (§30)', () {
      final c = makeController();
      expect(c.state.atmospheres.first.id, 'ayden_signature');
      expect(c.state.atmospheres.first.isSignature, isTrue);
    });

    test(
      'refine double-apply while generating cannot duplicate (§22.22)',
      () async {
        final c = await generated();
        final f1 = c.applyRefine('Make it warmer');
        await c.applyRefine('Make it warmer'); // no-op while generating
        await f1;
        expect(c.state.versions, hasLength(2));
      },
    );

    test('child vision carries a correct lineage reason label (§38)', () async {
      final c = await generated();
      c.stageAtmosphere('japandi_calm');
      await c.applyAtmosphere();
      final child = c.state.currentVision!;
      expect(child.parentVersionId, isNotNull);
      // The NAME, not the canonical id. `japandi_calm` is what the engine
      // speaks; it was being shown to the person verbatim.
      expect(child.reasonLabel, 'Atmosphere · Japandi Calm');
    });
  });
}
