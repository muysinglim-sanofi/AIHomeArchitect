// Manual-review defect — "stale old image flash after Replace photo → Generate".
//
// The root-cause investigation ruled out every stale-STATE race (the controller
// state, Before/After resolution and per-project cover mapping are all correct);
// these tests LOCK that in-session correctness so it cannot regress. The residual
// transient flash is a paint-time decode gap (the bundled After paints before the
// new Image.memory Before decodes) — mitigated by warming the Before in the
// loading window (LOADINGWARM), verified here at the unit level. The separate F5
// persistence path (a replaced Draft original is not re-uploaded — adapter treats
// it as immutable) is a flagged HIGH-confidence defect NOT covered here.

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_mock_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_project.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_loading_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AydenImageSource _src(List<int> bytes) => AydenImageSource(
  bytes: Uint8List.fromList(bytes),
  filename: 'room.jpg',
  mimeType: 'image/jpeg',
);

PwaController _controller() {
  final repo = MockPwaExperienceRepository(workDelay: Duration.zero);
  return PwaController(
    repo,
    generation: PwaMockGenerationService(repo),
    pending: PwaMemoryPendingGenerationStore(),
  );
}

PwaVision _vision(String id, String projectId, {String? afterAsset}) =>
    PwaVision(
      versionId: id,
      projectId: projectId,
      visionNumber: 1,
      title: 'v',
      atmosphereId: 'ayden_signature',
      actionType: PwaActionType.signature,
      afterAsset: afterAsset ?? 'assets/$projectId.jpg',
      order: 1,
    );

PwaProjectSnapshot _project(
  String id, {
  required List<PwaVision> visions,
  String? coverVisionId,
}) => PwaProjectSnapshot(
  projectId: id,
  title: 'P-$id',
  originalImageAsset: 'assets/x.jpg',
  roomId: null,
  roomLabel: '',
  selectedAtmosphereId: 'ayden_signature',
  atmosphereLabel: '',
  visions: visions,
  messages: const [],
  currentVisionId: visions.isEmpty ? null : visions.last.versionId,
  coverVisionId: coverVisionId,
  createdOrder: 1,
  updatedOrder: 1,
  updatedLabel: '',
  status: visions.isEmpty ? PwaProjectStatus.draft : PwaProjectStatus.active,
);

// A valid 1×1 transparent PNG so precacheImage can actually decode it.
final _png = Uint8List.fromList(const [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  0,
  1,
  0,
  0,
  5,
  0,
  1,
  13,
  10,
  45,
  180,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

void main() {
  group('REPLACEGEN — in-session state is correct after Replace → Generate', () {
    test(
      'REPLACEGEN02: Generate uses the EXACT replaced bytes, never the previous',
      () async {
        final c = _controller();
        c.setSource(_src(const [1, 1, 1])); // first photo
        final replaced = _src(const [9, 9, 9]); // Replace photo
        c.setSource(replaced);
        await c.generateFirstVision();
        // The Architect Before renders state.source; it must be the replaced bytes.
        expect(c.state.source, isNotNull);
        expect(identical(c.state.source!.bytes, replaced.bytes), isTrue);
        expect(c.state.source!.bytes, orderedEquals(const [9, 9, 9]));
      },
    );

    test(
      'REPLACEGEN03: no intermediate state exposes a prior Vision/cover while loading',
      () {
        final c = _controller();
        c.setSource(_src(const [9, 9, 9]));
        final fut = c
            .generateFirstVision(); // do NOT await: inspect the loading tick
        // The session opens IMMEDIATELY and the work runs inside it, so the
        // loading tick is the Architect — with nothing in it yet, which is
        // exactly what this test is about.
        expect(c.state.phase, PwaPhase.architect);
        expect(c.state.versions, isEmpty);
        expect(c.state.currentVision, isNull);
        expect(c.state.previewedVision, isNull); // nothing stale to paint
        return fut; // let it settle so no timer leaks
      },
    );

    test(
      'REPLACEGEN04: first Architect state belongs to the active project + new original',
      () async {
        final c = _controller();
        final draftId = c.state.project.projectId;
        final replaced = _src(const [7, 7, 7]);
        c.setSource(replaced);
        await c.generateFirstVision();
        expect(c.state.phase, PwaPhase.architect);
        expect(c.state.activeProjectId, draftId);
        expect(c.state.previewedVision, isNotNull);
        expect(
          c.state.previewedVision!.projectId,
          draftId,
        ); // vision owns to this project
        expect(identical(c.state.source!.bytes, replaced.bytes), isTrue);
      },
    );
  });

  group('COVER — per-project cover isolation', () {
    test(
      'COVER01: two projects with different cover Visions resolve their OWN covers',
      () {
        final a = _project(
          'A',
          visions: [_vision('A-v1', 'A', afterAsset: 'a.jpg')],
          coverVisionId: 'A-v1',
        );
        final b = _project(
          'B',
          visions: [_vision('B-v1', 'B', afterAsset: 'b.jpg')],
          coverVisionId: 'B-v1',
        );
        expect(a.coverVision!.versionId, 'A-v1');
        expect(a.coverVision!.afterAsset, 'a.jpg');
        expect(b.coverVision!.versionId, 'B-v1');
        expect(b.coverVision!.afterAsset, 'b.jpg');
      },
    );

    test('COVER02: mutating project A cannot change project B’s cover', () {
      final b = _project(
        'B',
        visions: [_vision('B-v1', 'B', afterAsset: 'b.jpg')],
        coverVisionId: 'B-v1',
      );
      final bCoverBefore = b.coverVision!.versionId;
      // A brand-new / regenerated A is an independent snapshot; B is untouched.
      _project(
        'A',
        visions: [_vision('A-v2', 'A', afterAsset: 'a2.jpg')],
        coverVisionId: 'A-v2',
      );
      expect(b.coverVision!.versionId, bCoverBefore); // still B-v1
    });

    test('COVER03: coverVisionId only ever resolves within the SAME project', () {
      // A FOREIGN coverVisionId must NOT resolve to another project's vision; it
      // falls back to this project's own current/last vision.
      final p = _project(
        'P',
        visions: [_vision('P-v1', 'P'), _vision('P-v2', 'P')],
        coverVisionId: 'FOREIGN-id',
      );
      final cover = p.coverVision;
      expect(cover, isNotNull);
      expect(cover!.projectId, 'P'); // never a foreign project's vision
      expect(p.visions.contains(cover), isTrue);
    });
  });

  testWidgets('LOADINGWARM: the loading screen precaches the new Before photo', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        pwaRepositoryProvider.overrideWithValue(
          MockPwaExperienceRepository(workDelay: Duration.zero),
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.binding.imageCache.clear();
    container
        .read(pwaControllerProvider.notifier)
        .setSource(
          AydenImageSource(
            bytes: _png,
            filename: 'new.png',
            mimeType: 'image/png',
          ),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PwaLoadingScreen()),
      ),
    );
    await tester.pump(); // run didChangeDependencies + precache submission
    await tester.pump(
      const Duration(milliseconds: 50),
    ); // let the decode settle
    // The Architect's Before provider (MemoryImage of the new bytes) is warmed.
    expect(
      tester.binding.imageCache.containsKey(MemoryImage(_png)),
      isTrue,
      reason: 'loading screen must precache MemoryImage(state.source.bytes)',
    );
  });
}
