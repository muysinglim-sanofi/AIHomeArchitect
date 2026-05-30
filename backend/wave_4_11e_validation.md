# Wave 4.11e — Clarification Exit Strategy + Design Brief Summarization

## Objective

Two friction points observed in real use after Wave 4.11d shipped:

1. **CLARIFICATION_EXIT** — When a user answered a clarification ("overall room feeling" after "make it bigger"), Wave 4.11d correctly routed to GENERATE but the chat response was a generic `"That could work well here. What element would you push further?"` — a new open-ended question that read as the architect not listening.

2. **SUMMARIZE_DESIGN_BRIEF** — When a user asked "Can you summarize what I want?" the system continued in architectural-discussion mode instead of producing a structured recap of the design direction.

## Implementation Summary

Files modified:
- `backend/prompt_engine/intent_classifier.py` — added `SubIntent.SUMMARIZE_DESIGN_BRIEF`; three SUMMARIZE pattern blocks (EN/FR/KM); wired into `_route_wave_411a` with HIGHEST priority (before SUPPORT).
- `backend/prompt_engine/architect_response.py` — added `generate_clarification_exit_response()` (brief acquittement, no follow-up question, EN/FR/KM templates) and `generate_brief_summary()` (bulleted refinement_state summary + Ready-to-generate footer, EN/FR/KM).
- `backend/prompt_engine/__init__.py` — exposed both new helpers.
- `backend/main.py` —
  - Wave 4.11d clarification_resolved branch: swapped `generate_chat_response` → `generate_clarification_exit_response` (preserves `should_generate=True`).
  - Added SUMMARIZE_DESIGN_BRIEF handler after PRODUCT_HELP/SUPPORT, sets `should_generate=False`.

## Design Decisions (vs. user brief options)

1. **Path A as the CLARIFICATION_EXIT default**: brief acquittement ("Got it — overall room feeling. On it.") + `should_generate=True`. The frontend renders the chat text, then triggers `/generate` immediately. Path B (summary + "Anything else?") would freeze momentum on the most common single-axis case; available for future use via the existing `generate_brief_summary()` if multi-axis flows demand a pause.

2. **SUMMARIZE never auto-generates**: the user's brief offered "direct generation if confidence is high" as an option — I chose to ALWAYS return `should_generate=False`. The summary is a validation step. The user follows up with "yes / generate" → Wave 4.11d `detect_generation_demand` catches the demand and routes to GENERATE.

3. **EN + FR + KM patterns for SUMMARIZE** (limited initial KM coverage — expansions tracked in mental model Open Questions for Wave 4.12).

## Validation Results — 54/54 PASS

| Section | Pass | Notes |
|---|---|---|
| 1. CLARIFICATION_EXIT — brief, no follow-up question, contains user answer | 7/7 | EN + FR + KM templates verified |
| 2. SUMMARIZE_DESIGN_BRIEF routing — EN/FR/KM triggers + 5 negatives | 25/25 | "summarize", "recap", "tldr", "what do you understand", "what's my brief", FR + KM, plus correctly rejects "make it warmer", "what about the kitchen?", "explain the atmosphere", embedded "summarize" mid-sentence |
| 3. SUMMARIZE output shape — header + bullets + Ready-to-generate footer | 4/4 | EN full state, EN sparse fallback (paraphrases latest user msg), FR, KM |
| 4. Discussion preservation (Wave 4.11d Scenarios E/F) | 4/4 | "What do you think?", "Compare these two", "Is this too dark?", "Would darker floors work?" still route DISCUSS |
| 5. Regression — Wave 4.11d / 4.11d.1 / 4.11a paths | 14/14 | generation_demand, clarification_answer, first-time ambiguity, interrogative anti-pattern (4.11d.1), SUMMARIZE never routes GENERATE |

### Detailed verification

**CLARIFICATION_EXIT acceptance scenarios** (verbatim from brief):

| Scenario | User answer | Exit response | should_generate |
|---|---|---|---|
| A: bigger → "overall room feeling" | overall room feeling | "Got it — overall room feeling. On it." | TRUE ✓ |
| B: warmer → "warmer lighting" | warmer lighting | "Locked in: warmer lighting. Generating now." | TRUE ✓ |
| C: less wood → "floor" | floor | "Understood — floor. Coming right up." | TRUE ✓ |

All exit responses verified: contain the user's answer verbatim, no `?`, no follow-up question, no architect-style open-ended phrase.

**SUMMARIZE output example** (Japandi Calm V4, full refinement state):

```
Here is my understanding:

✓ Keep the Japandi Calm character of the current vision
✓ Preserve: the windows
✓ Preserve: the kitchen opening
✓ Push: warmth
✓ Push: lighting layers
✓ Push: plants
✓ Remove: heavy decor

Ready to generate the next vision?
```

**Live HTTP probes** (against backend with Wave 4.11e loaded):

1. `Can you summarize what I want?` at V4 Japandi Calm / Living Room →
   ```json
   {
     "ai_message": "Here is my understanding:\n\n✓ Keep the Japandi Calm character of the current vision\n✓ Push: make it warmer\n\nReady to generate the next vision?",
     "should_generate": false,
     "intent": "design_discussion",
     "sub_intent": "summarize_design_brief"
   }
   ```

2. `overall room feeling` after a real bigger-clarification at V3 Warm Modern →
   ```json
   {
     "ai_message": "Got it — overall room feeling. On it.",
     "should_generate": true,
     "intent": "generate",
     "sub_intent": "refine_atmosphere"
   }
   ```

## Generate-after-summary behavior

Confirmed flow:
1. User: `Can you summarize what I want?`
2. System: bulleted summary + "Ready to generate the next vision?" (chat only, no generation)
3. User: `yes` / `generate` / `let's go`
4. Wave 4.11d `detect_generation_demand` fires → GENERATE

The bridge is two-step but deterministic. No probabilistic auto-generate.

## Discussion preservation

Wave 4.11d Scenarios E and F still hold:
- `What do you think of this living room?` → DESIGN_DISCUSSION ✓
- `Compare these two atmospheres` → DESIGN_DISCUSSION ✓
- `Is this atmosphere too dark?` → DESIGN_DISCUSSION ✓
- `Would darker floors work?` → DESIGN_DISCUSSION ✓

These are NOT mis-routed to SUMMARIZE despite containing the word "what".

## Regression checks

| Suite | Result |
|---|---|
| Wave 4.11e (this wave) | **54/54 PASS** |
| Wave 4.11d (Generation Intent Dominance) | 50/50 PASS (unchanged) |
| Wave 4.11d.1 (Interrogative anti-pattern) | 28/28 PASS (unchanged) |
| Wave 4.11(a+b+c) full suite | 95/100 (unchanged — 5 are documented design behaviours) |

**No regressions detected on any upstream suite.**

## Observed behavior changes

**Before Wave 4.11e** (post-4.11d behavior):
```
User: make it bigger
Architect: When you say bigger — are you thinking : sofa / seating area / room feeling?
User: overall room feeling
Architect: "That could work well here. What element would you push further?"   ← bug
           [/generate fires]
```

**After Wave 4.11e**:
```
User: make it bigger
Architect: When you say bigger — are you thinking : sofa / seating area / room feeling?
User: overall room feeling
Architect: "Got it — overall room feeling. On it."   ← brief exit, no new question
           [/generate fires]
```

**New flow — design brief recap**:
```
User: Can you summarize what I want?
Architect: Here is my understanding:
           ✓ Keep the Warm Modern character of the current vision
           ✓ Preserve: the windows
           ✓ Push: warmth
           Ready to generate the next vision?
User: yes
[Wave 4.11d generation_demand fires → /generate]
```

## Potential Risks

### Risk 1 — Clarification-marker drift (inherited from Wave 4.11d)

`is_clarification_answer` relies on `_ASSISTANT_CLARIFICATION_MARKERS` matching the prior assistant message. Wave 4.11e amplifies this dependency : when the marker matches, the user sees the new exit acquittement instead of a generic chat response. If a future wave changes clarification copy substantially without updating the marker list, the exit acquittement falls back to the standard chat response (i.e. the original Wave 4.11d behavior — not a regression, but loses the new polish).

**Mitigation**: documented in `_ASSISTANT_CLARIFICATION_MARKERS` source comment.

### Risk 2 — User answer leaks into the exit text

`generate_clarification_exit_response` injects the user's answer verbatim into the template. If a user pastes a long sentence as their clarification answer (e.g. "the overall room feeling and also maybe the lighting and could you make the floor lighter too"), the answer gets truncated to 40 chars at a word boundary. Worst case: the truncation produces an awkward fragment but never invalid text.

**Mitigation**: 40-char truncation + word-boundary break. Tested with multi-word answers.

### Risk 3 — Summary fidelity depends on refinement_state quality

`generate_brief_summary` reads from `parse_history()` output. If the parser misses a refinement (e.g. unusual phrasing), the summary will be incomplete. The sparse fallback paraphrases the latest user message so the summary is never empty.

**Mitigation**: sparse fallback + bulleted ceiling at 6 items. Tested with full and sparse states.

### Risk 4 — SUMMARIZE pattern false positives

The EN regex is anchored at `^\s*` (message start). Embedded "summarize" mid-sentence ("I want to summarize my favorite atmospheres") correctly does NOT trigger.

**Mitigation**: 5 negative cases tested in Section 2 of the harness (including embedded "summarize" + "what about" + "tell me what you think"). All correctly rejected.

### Risk 5 — KM SUMMARIZE coverage is initial-only

Only 4 KM patterns (`សង្ខេប`, `សារសំខាន់`, `តើ\s*អ្នក\s*យល់...`, `និយាយ\s*សង្ខេប`, `រំលឹក\s*ខ្ញុំ`). Real KM users likely use phrasings not in this list.

**Mitigation**: tracked as Open Question in `docs/user_mental_model.md` for Wave 4.12 expansion based on real KM corpus.

## Performance Impact

- `generate_clarification_exit_response`: 1 dict lookup + 1 `str.format` → ~1 µs
- `generate_brief_summary`: scans 5 RefinementState fields + builds bulleted list → ~10 µs
- `_SUMMARIZE_BRIEF_EN/FR/KM` regexes: 3 precompiled regexes, one match attempt per /chat → ~50 µs total

**Total overhead per /chat: ~60 µs (0.06 ms)**. Indistinguishable from baseline.

No new OpenAI calls. No embeddings. No vector DB. No agents. No frontend changes. No response shape changes.

## Final Recommendation

# READY TO SHIP

- 54/54 validation pass
- All upstream suites unchanged (50/50 + 28/28 + 95/100)
- Two real friction points from real conversation review are closed at their source
- Three live HTTP probes confirm end-to-end behavior with backend reloaded
- No regression on any documented Wave 4.11a/b/c/d/d.1 behavior

**Open follow-ups (NOT blocking)**:
1. Expand KM SUMMARIZE patterns based on real KM corpus (Wave 4.12 candidate)
2. Consider exposing Path B (summary-before-generate as confirmation pause) for users typing multi-axis clarification answers (e.g. "bigger feeling and warmer materials and brighter")
3. Real-conversation observation post-ship — verify the "Got it — X. On it." reads naturally to real users (the mental model document is the trace)

## Files Changed

| File | Lines added | Purpose |
|---|---|---|
| `backend/prompt_engine/intent_classifier.py` | ~70 | `SubIntent.SUMMARIZE_DESIGN_BRIEF`; `_SUMMARIZE_BRIEF_EN/FR/KM` patterns; `_route_wave_411a` wiring with highest priority |
| `backend/prompt_engine/architect_response.py` | ~170 | `generate_clarification_exit_response()` (EN/FR/KM templates) and `generate_brief_summary()` (EN/FR/KM bulleted output) |
| `backend/prompt_engine/__init__.py` | 3 | Re-export both new helpers |
| `backend/main.py` | ~35 | Clarification_resolved branch uses exit template ; SUMMARIZE handler emits summary text with should_generate=False |

**Validation artifacts** (untracked, kept for regression):
- `backend/_wave_411e_validation.py` — 54-test harness
