// Parity guards: the PWA must not own business decisions.
//
// Every divergence in this codebase was found the same expensive way — a human
// running the app and noticing something wrong. Each guard below names one
// decision that belongs to the canonical backend and fails if the PWA starts
// making it again.
//
// These assert ABSENCE. An earlier version of this file asserted that the local
// heuristics were still present, as a way of not forgetting them; they are gone
// now, and the tests were inverted rather than deleted.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// Source with comments and doc text stripped, so a guard measures the code and
/// not the prose that explains it.
String _code(String path) {
  final out = StringBuffer();
  var inBlock = false;
  for (final line in _read(path).split('\n')) {
    var l = line;
    if (inBlock) {
      final end = l.indexOf('*/');
      if (end == -1) continue;
      l = l.substring(end + 2);
      inBlock = false;
    }
    final block = l.indexOf('/*');
    if (block != -1) {
      inBlock = true;
      l = l.substring(0, block);
    }
    final t = l.trimLeft();
    if (t.startsWith('///') || t.startsWith('//')) continue;
    final slash = l.indexOf('//');
    if (slash != -1 && !l.contains('://')) l = l.substring(0, slash);
    out.writeln(l);
  }
  return out.toString();
}

const _controller = 'lib/features/pwa/application/pwa_controller.dart';
const _mainPwa = 'lib/main_pwa.dart';

Iterable<File> _dart(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  group('the canonical engine is never re-implemented in the PWA', () {
    test('PARITY01: no prompt text is built in Flutter', () {
      for (final dir in const [
        'lib/features/pwa/application',
        'lib/features/pwa/data',
        'lib/features/pwa/presentation',
      ]) {
        for (final f in _dart(dir)) {
          final code = _code(f.path);
          for (final marker in const [
            'PRESERVE MODE',
            'SAME APARTMENT CONTRACT',
            'Reproduce the photographed',
            'photorealistic',
            'DSLR',
          ]) {
            expect(
              code.contains(marker),
              isFalse,
              reason: '${f.path} builds prompt text ($marker)',
            );
          }
        }
      }
    });

    test('PARITY02: the client sends structured intent, never a prompt', () {
      final api = _code('lib/features/pwa/data/pwa_generation_api.dart');
      expect(api.contains("'prompt'"), isFalse, reason: 'no prompt field');
      for (final field in const [
        'room_label',
        'atmosphere_id',
        'action_type',
        'user_instruction',
        'idempotency_key',
        'confirm',
      ]) {
        expect(api.contains(field), isTrue, reason: 'missing $field');
      }
    });

    test('PARITY03: staging never builds the offline generation service', () {
      final src = _code(_mainPwa);
      expect(src.contains('PwaMockGenerationService('), isFalse);
      expect(src.contains('PwaStagingGenerationService('), isTrue);
    });

    test('PARITY04: staging never seeds the demo library', () {
      expect(
        _code(
          _mainPwa,
        ).contains('MockPwaExperienceRepository(seedLibrary: false)'),
        isTrue,
      );
    });
  });

  group('the advice / execute decision belongs to the backend', () {
    test('PARITY10: the local intent heuristic is GONE', () {
      // Was `lib/features/pwa/domain/pwa_intent.dart` — a 47-line keyword list
      // deciding advice-vs-refine. `refine.parser` + `refine.advisor` decide it
      // now, on the backend, exactly as they do for mobile.
      expect(
        File('lib/features/pwa/domain/pwa_intent.dart').existsSync(),
        isFalse,
        reason: 'the PWA must not classify intent locally',
      );
      for (final dir in const [
        'lib/features/pwa/application',
        'lib/features/pwa/presentation',
        'lib/features/pwa/data',
      ]) {
        for (final f in _dart(dir)) {
          expect(
            _code(f.path).contains('classifyTextIntent'),
            isFalse,
            reason: f.path,
          );
        }
      }
    });

    test('PARITY11: no canned Ayden advice reaches the runtime', () {
      // The exact sentences that contradicted a structural instruction.
      for (final dir in const [
        'lib/features/pwa/application',
        'lib/features/pwa/presentation',
      ]) {
        for (final f in _dart(dir)) {
          final code = _code(f.path);
          for (final banned in const [
            'refineAdvice',
            'adviceResponse',
            'refineSummary',
            'keep the architecture intact',
            'Want me to apply it',
          ]) {
            expect(
              code.contains(banned),
              isFalse,
              reason: '${f.path}: $banned',
            );
          }
        }
      }
    });

    test(
      'PARITY12: a typed line is judged by the canonical CHAT gate before '
      'anything can be spent on it',
      () {
        final code = _code(_controller);
        // `sendUserText` must not reach the paid path itself. It used to call
        // applyRefine directly, and that is exactly how a question became a
        // paid render and a permanent Vision.
        expect(
          code.contains('unawaited(applyRefine(text))'),
          isFalse,
          reason: 'sendUserText must go through the conversational turn first',
        );
        // The gate exists, and the ONLY thing that authorises a render is the
        // backend's own answer.
        expect(code.contains('_generation.chat('), isTrue);
        expect(code.contains('if (turn.shouldGenerate)'), isTrue);
        // An advisory is handled as its own outcome, never as a failure.
        expect(code.contains('on PwaAdvisoryRaised'), isTrue);
      },
    );

    test('PARITY12b: nothing local decides whether a line deserves a render', () {
      // The forbidden shapes, by name. Each was proposed at some point and each
      // is wrong for the same measured reason: a real edit ("make the sofa
      // white") can look conversational to a local rule, and a real question
      // looks like an edit to the refine parser. Only the canonical brain
      // answers "does this need generating?".
      //
      // Scoped to the layers where money can be decided. `presentation` is
      // deliberately excluded: it holds things like the chip GLYPH picker, which
      // reads a label to choose an icon and routes nothing. The rule is "no
      // local rule decides a render", not "no widget may look at a string" —
      // and PARITY12c below is what keeps presentation out of the paid path.
      for (final dir in const [
        'lib/features/pwa/application',
        'lib/features/pwa/data',
      ]) {
        for (final f in _dart(dir)) {
          final code = _code(f.path);
          for (final banned in const [
            "endsWith('?')",
            "contains('?')",
            'classifyTextIntent',
            'looksLikeQuestion',
            '_questionWords',
            'conversationalPhrases',
          ]) {
            expect(code.contains(banned), isFalse, reason: '${f.path}: $banned');
          }
        }
      }
    });

    test('PARITY12c: the UI never reaches the paid path itself', () {
      // Every widget hands text to `sendUserText` — the gated door. A screen
      // that called applyRefine directly would walk straight past the
      // conversational turn, which is the defect this whole change removes.
      // `applyRefine(..., confirm: true)` from a Continue-anyway card is the one
      // legitimate exception: the objection has already been shown and answered.
      for (final f in _dart('lib/features/pwa/presentation')) {
        final code = _code(f.path);
        for (final line in code.split('\n')) {
          if (!line.contains('applyRefine(')) continue;
          expect(
            line.contains('confirm: true'),
            isTrue,
            reason: '${f.path}: only a confirmed continue may bypass the gate '
                '— everything else goes through sendUserText',
          );
        }
      }
    });

    test('PARITY13: an advisory produces NO vision and NO error banner', () {
      final code = _code(_controller);
      final start = code.indexOf('on PwaAdvisoryRaised');
      expect(start, greaterThan(-1));
      final rest = code.substring(start);
      final nextCatch = rest.indexOf('} catch (');
      final block = nextCatch > 0 ? rest.substring(0, nextCatch) : rest;
      expect(
        block.contains('_visionFrom('),
        isFalse,
        reason: 'an objection is not a vision',
      );
      expect(
        block.contains('_failGeneration('),
        isFalse,
        reason: 'an objection is not a failure',
      );
      expect(
        block.contains('raised.advisory.message'),
        isTrue,
        reason: "the advisor's own words must be shown",
      );
    });
  });

  group('the loading state cannot finish a generation', () {
    const indicator =
        'lib/features/pwa/presentation/pwa_working_indicator.dart';

    test('PARITY20: the working indicator only moves text and pixels', () {
      final code = _code(indicator);
      for (final banned in const [
        'Navigator',
        'context.go',
        'pushReplacement',
        'pwaControllerProvider',
        'PwaController',
        'ref.read',
        'ref.watch',
        'PwaVision',
        'applyRefine',
        'generateFirstVision',
      ]) {
        expect(
          code.contains(banned),
          isFalse,
          reason: 'the indicator must not be able to end anything ($banned)',
        );
      }
    });

    test('PARITY21: no fake percentage anywhere in the loading surface', () {
      for (final f in [
        File(indicator),
        File('lib/features/pwa/presentation/pwa_loading_screen.dart'),
      ]) {
        if (!f.existsSync()) continue;
        final code = _code(f.path);
        expect(
          code.contains('LinearProgressIndicator(') &&
              !code.contains('value: null'),
          isFalse,
          reason: '${f.path} shows a measured progress it cannot know',
        );
      }
    });

    test('PARITY22: the phases are qualitative and end open-ended', () {
      final code = _code(indicator);
      expect(code.contains('kPwaRefinePhases'), isTrue);
      expect(code.contains('Finishing your vision'), isTrue);
      // The timer stops at the last phase rather than looping to "done".
      expect(code.contains('t.cancel()'), isTrue);
    });
  });

  group('what the backend now owns', () {
    test(
      'PARITY30: the controller does not choose a preservation contract',
      () {
        final code = _code(_controller);
        for (final banned in const ['preserve', 'structural', 'architecture']) {
          expect(
            code.toLowerCase().contains('$banned ='),
            isFalse,
            reason: 'the controller must not decide "$banned"',
          );
        }
      },
    );

    test('PARITY31: refine sends the raw instruction, unrewritten', () {
      final code = _code(_controller);
      expect(code.contains('userInstruction: instruction'), isTrue);
      expect(
        code.contains('instruction.replaceAll') ||
            code.contains('instruction.toLowerCase()'),
        isFalse,
        reason: 'the PWA must not pre-process what the parser will read',
      );
    });

    test('PARITY32: "continue anyway" is carried to the backend', () {
      // The user overriding an objection is a decision the BACKEND must see,
      // not one the client acts on by skipping the advisor itself.
      expect(_code(_controller).contains('confirm: confirm'), isTrue);
      expect(
        _code(
          'lib/features/pwa/data/pwa_generation_service.dart',
        ).contains('confirm: intent.confirm'),
        isTrue,
      );
    });
  });
}
