// Batch 2 — PWA prototype state-machine tests. Deterministic (zero-delay mock),
// no real services, no real timers, no network.

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_intent.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:flutter_test/flutter_test.dart';

PwaController makeController() =>
    PwaController(MockPwaExperienceRepository(workDelay: Duration.zero));

AydenImageSource fakeSource() => AydenImageSource(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      filename: 'room.jpg',
    );

void main() {
  group('classifyTextIntent', () {
    test('opinion questions → advice', () {
      expect(classifyTextIntent('What do you think?'), PwaIntent.advice);
      expect(classifyTextIntent('Your opinion on the rug?'), PwaIntent.advice);
    });
    test('instructions → refine', () {
      expect(classifyTextIntent('Make it warmer'), PwaIntent.refine);
      expect(classifyTextIntent('Open the kitchen'), PwaIntent.refine);
      expect(classifyTextIntent('More natural light'), PwaIntent.refine);
    });
  });

  group('Primary flow — one photo, one click', () {
    test('generateFirstVision works with NO room/atmosphere selected', () async {
      final c = makeController();
      c.setSource(fakeSource());
      // No atmosphere chosen, no room chosen — just generate.
      await c.generateFirstVision();
      expect(c.state.phase, PwaPhase.architect);
      expect(c.state.versions, hasLength(1));
    });

    test('Ayden Decide + Signature are the defaults', () async {
      final c = makeController();
      c.setSource(fakeSource());
      await c.generateFirstVision();
      expect(c.state.selectedAtmosphereId, 'ayden_signature');
      final v1 = c.state.currentVision!;
      expect(v1.actionType, PwaActionType.signature);
      expect(v1.isCurrent, isTrue);
      expect(v1.visionNumber, 1);
    });

    test('the FIRST rich message is an Ayden reveal bound to V1', () async {
      final c = makeController();
      await c.generateFirstVision();
      final first = c.state.messages.first;
      expect(first.role, PwaRole.ayden);
      expect(first.kind, PwaMessageKind.reveal);
      expect(first.visionId, c.state.currentVision!.versionId);
      expect(first.text, isNotEmpty);
    });
  });

  group('Atmosphere switch → new child version', () {
    test('creates a child of the current vision, inserted in the chronology',
        () async {
      final c = makeController();
      await c.generateFirstVision();
      final parent = c.state.currentVision!;
      await c.selectAtmosphere('japandi_calm');
      expect(c.state.versions, hasLength(2));
      final v2 = c.state.currentVision!;
      expect(v2.parentVersionId, parent.versionId);
      expect(v2.atmosphereId, 'japandi_calm');
      expect(v2.actionType, PwaActionType.switchAtmosphere);
      // chronology: intro reveal, user "Switch to…", ayden reveal (loading gone)
      expect(c.state.messages.any((m) => m.kind == PwaMessageKind.loading), isFalse);
      expect(c.state.messages.last.kind, PwaMessageKind.reveal);
      expect(c.state.messages.any((m) => m.role == PwaRole.user), isTrue);
    });

    test('re-selecting the current atmosphere is a no-op', () async {
      final c = makeController();
      await c.generateFirstVision();
      await c.selectAtmosphere('ayden_signature');
      expect(c.state.versions, hasLength(1));
    });
  });

  group('Advice vs Refine', () {
    test('advice creates text only — NO version, no Space', () async {
      final c = makeController();
      await c.generateFirstVision();
      final before = c.state.versions.length;
      c.sendUserText('What do you think?');
      expect(c.state.versions.length, before); // unchanged
      expect(c.state.messages.last.role, PwaRole.ayden);
      expect(c.state.messages.last.kind, PwaMessageKind.text);
    });

    test('refine offers Apply; applyRefine creates a child version', () async {
      final c = makeController();
      await c.generateFirstVision();
      final parent = c.state.currentVision!;
      c.sendUserText('Make it warmer');
      final advice = c.state.messages.last;
      expect(advice.pendingRefine, 'Make it warmer'); // no version yet
      expect(c.state.versions, hasLength(1));

      await c.applyRefine(advice.pendingRefine!);
      expect(c.state.versions, hasLength(2));
      final child = c.state.currentVision!;
      expect(child.actionType, PwaActionType.refine);
      expect(child.parentVersionId, parent.versionId);
    });
  });

  group('Version preservation + continue-from', () {
    test('old versions are never overwritten', () async {
      final c = makeController();
      await c.generateFirstVision();
      final v1Id = c.state.currentVision!.versionId;
      await c.selectAtmosphere('soft_luxury');
      await c.applyRefine('More natural light');
      expect(c.state.versions.length, 3);
      expect(c.state.versions.any((v) => v.versionId == v1Id), isTrue);
    });

    test('continue-from-old makes it current, adds a marker, and re-parents next',
        () async {
      final c = makeController();
      await c.generateFirstVision();
      final v1Id = c.state.currentVision!.versionId;
      await c.selectAtmosphere('nordic_warmth'); // v2 current
      c.continueFromVision(v1Id);
      expect(c.state.currentVision!.versionId, v1Id);
      expect(c.state.messages.last.text, contains('continuing from Vision 1'));

      await c.applyRefine('Open the kitchen'); // v3 parented on v1
      expect(c.state.currentVision!.parentVersionId, v1Id);
    });

    test('setCurrentVision switches highlight without a chat message', () async {
      final c = makeController();
      await c.generateFirstVision();
      final v1Id = c.state.currentVision!.versionId;
      await c.selectAtmosphere('tropical_escape');
      final msgsBefore = c.state.messages.length;
      c.setCurrentVision(v1Id);
      expect(c.state.currentVision!.versionId, v1Id);
      expect(c.state.messages.length, msgsBefore); // no marker
    });
  });
}
