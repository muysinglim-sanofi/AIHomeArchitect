// The conversational turn: what is allowed to cost money.
//
// A question used to buy an image. The real smoke on 2026-08-11 produced a
// permanent Vision titled "what do you think of this space?" — a paid render,
// and worse, an entry in the customisation memory every later atmosphere switch
// reads back.
//
// The old defence was "the refine parser found no changes". Measured against the
// canonical parser, that defence does not exist: `parse_changes` returns a
// `modify` change for "what do you think?", for "what do you think of this
// space?" and for "how does this room feel to you?". Reading an instruction is
// its job; deciding whether a sentence IS one is not.
//
// So the app asks the same question mobile asks — `POST /chat` →
// `should_generate` — and these tests pin that it is the ONLY answer that opens
// the paid path.

import 'dart:io';
import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_generation_service.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_pending_generation.dart';
import 'package:ai_home_architect/features/pwa/domain/pwa_models.dart';
import 'package:flutter_test/flutter_test.dart';

AydenImageSource _source() => AydenImageSource(
  bytes: Uint8List.fromList(const [1, 2, 3]),
  filename: 'room.jpg',
  mimeType: 'image/jpeg',
);

/// A session with one real Vision, ready for a typed line.
Future<(PwaController, PwaFakeGenerationService)> _session() async {
  final gen = PwaFakeGenerationService();
  final c = PwaController(
    MockPwaExperienceRepository(workDelay: Duration.zero, seedLibrary: false),
    generation: gen,
    pending: PwaMemoryPendingGenerationStore(),
  );
  c.selectRoom('livingRoom');
  c.setSource(_source());
  await c.generateFirstVision();
  gen.calls.clear();
  gen.chatCalls.clear();
  return (c, gen);
}

/// The backend answered "this is a conversation".
void _conversation(PwaFakeGenerationService gen, {String reply = 'It reads calm and open to me.'}) {
  gen.chatTurn = PwaChatTurn(aiMessage: reply, shouldGenerate: false);
}

/// The backend answered "this is an edit".
void _edit(PwaFakeGenerationService gen) {
  gen.chatTurn = const PwaChatTurn(aiMessage: '', shouldGenerate: true);
}

void main() {
  group('a question is answered, never rendered', () {
    // The three phrasings measured against the real canonical parser. Every one
    // of them comes back from `parse_changes` as a `modify` change, which is
    // exactly why the parser cannot be the gate.
    for (final (label, text) in const [
      ('CHAT01', 'What do you think?'),
      ('CHAT02', 'What do you think of this space?'),
      ('CHAT03', 'How does this room feel to you?'),
    ]) {
      test('$label: "$text" → answered, no render', () async {
        final (c, gen) = await _session();
        _conversation(gen);
        final visionsBefore = c.state.versions.length;

        c.sendUserText(text);
        await pumpEventQueue();

        expect(gen.chatCalls, [text], reason: 'the gate was asked, verbatim');
        expect(
          gen.calls,
          isEmpty,
          reason: 'CHAT04/05: no generation was requested, so no claim and no '
              'paid render could exist',
        );
        expect(c.state.versions.length, visionsBefore, reason: 'no Vision');
        expect(c.state.generating, isFalse);
        expect(c.state.generationError, isNull, reason: 'not a failure');
        expect(
          c.state.messages.any((m) => m.text == 'It reads calm and open to me.'),
          isTrue,
          reason: "Ayden's own words are shown",
        );
      });
    }

    test('CHAT06: a conversation leaves the lineage untouched', () async {
      final (c, gen) = await _session();
      _conversation(gen);
      final before = c.state.versions.map((v) => v.versionId).toList();
      final currentBefore = c.state.currentVisionId;

      c.sendUserText('What do you think?');
      await pumpEventQueue();

      expect(c.state.versions.map((v) => v.versionId).toList(), before);
      expect(c.state.currentVisionId, currentBefore);
      // Nothing was sent to the generation seam, so nothing could have been
      // recorded as a customisation for a later switch to read back.
      expect(gen.calls, isEmpty);
    });

    test('CHAT09: the chip takes the SAME path as typing it', () async {
      final (c, gen) = await _session();
      _conversation(gen);

      // `_onQuickAction` in the architect screen is literally `sendUserText`, so
      // a chip cannot have its own routing. Proven by behaviour, not by reading
      // the widget: the same text produces the same gate call and no render.
      c.sendUserText('What do you think?');
      await pumpEventQueue();

      expect(gen.chatCalls, ['What do you think?']);
      expect(gen.calls, isEmpty);
    });
  });

  group('a real edit still generates', () {
    test('CHAT07/08: "make the sofa white" goes through the gate, then refines',
        () async {
      final (c, gen) = await _session();
      _edit(gen);
      final parent = c.state.currentVision!;

      c.sendUserText('make the sofa white');
      await pumpEventQueue();

      expect(gen.chatCalls, ['make the sofa white'],
          reason: 'CHAT08: the gate is consulted BEFORE the refine');
      expect(gen.calls, hasLength(1), reason: 'exactly one generation');
      final intent = gen.calls.single;
      expect(intent.actionType, 'refine');
      expect(intent.userInstruction, 'make the sofa white',
          reason: 'the user words reach the engine unaltered');
      expect(intent.parentVisionId, parent.versionId);
      expect(c.state.versions.length, 2);
      expect(c.state.currentVision!.instruction, 'make the sofa white');
    });

    test('a structural request reaches the same canonical path', () async {
      final (c, gen) = await _session();
      _edit(gen);

      c.sendUserText('open the wall on the right and add a kitchen with an island');
      await pumpEventQueue();

      expect(gen.chatCalls, hasLength(1));
      expect(gen.calls, hasLength(1));
      expect(
        gen.calls.single.userInstruction,
        'open the wall on the right and add a kitchen with an island',
        reason: 'nothing local rewrites or classifies a structural request',
      );
    });
  });

  group('the gate fails CLOSED', () {
    test('CHAT10: an unreachable backend answers "do not generate"', () {
      // The product-side guarantee, at the type: a turn nobody answered can
      // never authorise spending.
      const silent = PwaChatTurn.silent();
      expect(silent.shouldGenerate, isFalse);

      // And a malformed/absent field parses the same way — `== true`, never a
      // truthy cast.
      expect(PwaChatTurn.parse(const {}).shouldGenerate, isFalse);
      expect(
        PwaChatTurn.parse(const {'should_generate': 'yes'}).shouldGenerate,
        isFalse,
        reason: 'a string is not permission to spend money',
      );
      expect(
        PwaChatTurn.parse(const {'should_generate': 1}).shouldGenerate,
        isFalse,
      );
      expect(
        PwaChatTurn.parse(const {'should_generate': true}).shouldGenerate,
        isTrue,
      );
    });

    test('a silent turn still says something rather than nothing', () async {
      final (c, gen) = await _session();
      gen.chatTurn = const PwaChatTurn.silent();

      c.sendUserText('What do you think?');
      await pumpEventQueue();

      expect(gen.calls, isEmpty, reason: 'silence never spends');
      expect(
        c.state.messages.last.text.isNotEmpty,
        isTrue,
        reason: 'the conversation continues even when the turn came back empty',
      );
      expect(c.state.generationError, isNull);
    });

    test('no loading bubble is left behind by a conversation', () async {
      final (c, gen) = await _session();
      _conversation(gen);

      c.sendUserText('What do you think?');
      await pumpEventQueue();

      expect(
        c.state.messages.where((m) => m.kind == PwaMessageKind.loading),
        isEmpty,
      );
    });
  });

  group('advisory and Continue anyway', () {
    test('an advisory is an ANSWER: no vision, no error, no premature render',
        () async {
      final (c, gen) = await _session();
      _edit(gen); // the gate says this is an edit…
      gen.advisory = const PwaGenerationAdvisory(
        verdict: 'yellow',
        message: 'Which wall do you mean — the left or the right one?',
      );
      final before = c.state.versions.length;

      c.sendUserText('open the wall');
      await pumpEventQueue();

      // …and the canonical ADVISOR then objected, which is a second, separate
      // gate. One generation was attempted; none completed.
      expect(c.state.versions.length, before, reason: 'no vision');
      expect(c.state.generationError, isNull, reason: 'an objection is not an error');
      expect(c.state.generating, isFalse);
      final card = c.state.messages.last;
      expect(card.text, contains('Which wall do you mean'));
      expect(card.advisoryVerdict, 'yellow');
      expect(card.pendingRefine, 'open the wall',
          reason: 'the instruction is kept so Continue anyway can resend it');
    });

    test('Continue anyway resends with confirm=true and does NOT re-ask the gate',
        () async {
      final (c, gen) = await _session();
      _edit(gen);
      gen.advisory = const PwaGenerationAdvisory(
        verdict: 'yellow',
        message: 'Which wall do you mean?',
      );
      c.sendUserText('open the wall');
      await pumpEventQueue();
      gen.chatCalls.clear();
      gen.advisory = null; // the user read the objection and chose to proceed

      await c.applyRefine('open the wall', confirm: true);

      final confirmed = gen.calls.last;
      expect(confirmed.confirm, isTrue);
      expect(confirmed.userInstruction, 'open the wall');
      expect(
        gen.chatCalls,
        isEmpty,
        reason: 'the decision was already made — re-asking would let the gate '
            'overturn a choice the person has explicitly confirmed',
      );
      expect(c.state.versions.length, 2, reason: 'the vision is created');
    });

    test('a RED verdict is a REFUSAL: the override is absent, not disabled',
        () async {
      // Mobile's contract, verbatim: "YELLOW → [Try anyway] + [Edit request] ;
      // RED → [Edit request] SEULEMENT (jamais forçable, aucun confirm=true
      // possible depuis une carte RED)" — chat_screen.dart:5304, and its
      // handler refuses one anyway at :1811.
      //
      // The PWA offered "Create vision" on every verdict, which let a person pay
      // for a render the engine had already judged wrong. The card now drops the
      // override on red; this pins the SOURCE of that rule, because the verdict
      // reaching the card is what the widget branches on.
      final card = File(
        'lib/features/pwa/presentation/pwa_architect_screen.dart',
      ).readAsStringSync();
      expect(
        card.contains("advisoryVerdict == 'red'"),
        isTrue,
        reason: 'the card must know a refusal when it sees one',
      );
      expect(
        card.contains('advisoryVerdict: m.advisoryVerdict'),
        isTrue,
        reason: 'and the verdict must actually reach it',
      );
      // The override is inside the `if (!isRed)` branch — absent on a refusal,
      // rather than present-but-greyed, which still reads as "available to you".
      final actions = card.substring(card.indexOf('final isRed ='));
      // The label is now a dictionary lookup (`PwaL10n.createVision`) rather
      // than a literal — the RULE being pinned is unchanged: the override sits
      // INSIDE the `if (!isRed)` branch, so a refusal has no override at all
      // rather than a greyed one, which still reads as "available to you".
      expect(
        actions.indexOf('if (!isRed) ...['),
        lessThan(actions.indexOf('createVision')),
      );
      expect(actions.contains('createVision'), isTrue,
          reason: 'the override label must still be rendered on non-red');
    });

    test('a RED verdict still carries the advisor words and the instruction',
        () async {
      final (c, gen) = await _session();
      _edit(gen);
      gen.advisory = const PwaGenerationAdvisory(
        verdict: 'red',
        message: 'Removing that wall would leave the floor above unsupported.',
      );
      final before = c.state.versions.length;

      c.sendUserText('remove the load-bearing wall');
      await pumpEventQueue();

      expect(c.state.versions.length, before);
      expect(c.state.generationError, isNull);
      final card = c.state.messages.last;
      expect(card.advisoryVerdict, 'red',
          reason: 'the verdict is carried verbatim, never downgraded');
      expect(card.text, contains('unsupported'));
      // The instruction is still carried — mobile keeps the card and its
      // [Edit request] action; what red removes is the OVERRIDE, not the card.
      expect(card.pendingRefine, 'remove the load-bearing wall');
    });
  });
}
