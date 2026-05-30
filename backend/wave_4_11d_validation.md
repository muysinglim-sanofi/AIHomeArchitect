# Wave 4.11d — Generation Intent Dominance — Validation Report

## Objective

After Wave 4.11a/b/c the architect became too clarification-happy. Users answered a clarification but got asked another one instead of seeing the next vision. Wave 4.11d adds a **Generation Intent Dominance** layer that resolves the imbalance without sacrificing architectural intelligence.

## Implementation Summary

Two stateless detectors added to `prompt_engine/intent_classifier.py`, wired into `main.py /chat` BEFORE `detect_ambiguity`:

| Detector | What it catches | Resolution |
|---|---|---|
| `detect_generation_demand(msg)` | Bare demand for next vision — "generate", "why don't you generate?", "just do it", "show me", "make it" (alone), "let's see", "create it", "do it now", etc. | Immediate GENERATE, ambiguity bypassed |
| `is_clarification_answer(msg, history)` | Previous assistant turn was a clarification AND user gave a short (≤10 words) direct answer (no question, no redirect, no negative feedback) | GENERATE / REFINE_ATMOSPHERE, ambiguity bypassed |

Plus minor pattern extensions:
- `_REFINE` += cozy / elegant / modern / premium / sleek / sophisticated / spacious (single-adjective design directives, Principle 3)
- `_DESIGN_DISCUSSION_PATTERNS` += "compare these/those/the/both X", "can you compare X vs Y", "pros and cons", "trade-offs" (Scenario F + adversarial probe)

**Constraint compliance**:
- No new OpenAI calls
- No embeddings, no vector DB, no agents
- No frontend changes
- No response shape changes
- No new persistence (purely reads `history` already passed per-request)

## Validation Results — 50/50 PASS

| Section | Pass | Total |
|---|---|---|
| 1. Clarification Resolution | 6/6 | ✓ |
| 2. Generation Dominance | 8/8 | ✓ |
| 3. Frustration Override | 13/13 | ✓ |
| 4. Discussion Preservation | 9/9 | ✓ |
| 5. Regression Checks | 11/11 | ✓ |
| 6. Adversarial Probes | 3/3 | ✓ |

### Section 1 — Clarification Resolution

| Test | Before | After |
|---|---|---|
| **Scenario A**: User answers "overall room feeling" after bigger-clarification | clarification loop | **GENERATE** ✓ |
| Short answer "warmer lighting" → GENERATE | conversation/general (lost) | GENERATE ✓ |
| Short answer "finishes" → GENERATE | conversation/general (lost) | GENERATE ✓ |
| Short answer "the sofa" → GENERATE | conversation/general (lost) | GENERATE ✓ |
| Short answer "overall feeling" → GENERATE | conversation/general (lost) | GENERATE ✓ |
| **Scenario B**: "material palette" after better-clarification | clarification loop | **GENERATE** ✓ |

### Section 2 — Generation Dominance (design directives)

| Directive | Route |
|---|---|
| make it warmer | generate ✓ |
| make it brighter | generate ✓ |
| more luxurious | generate ✓ |
| cozy | **generate** ✓ (was conversation; Wave 4.11d expanded _REFINE) |
| add a TV | generate ✓ |
| open the kitchen | generate ✓ |
| more natural light | generate ✓ |
| less wood | generate ✓ |

### Section 3 — Frustration / Explicit Demand Override

| User Message | Route | Reason |
|---|---|---|
| **Scenario C**: "why don't you generate?" | **generate** ✓ | `wave_4_11d_generation_demand` |
| **Scenario D**: "generate" | **generate** ✓ | `wave_4_11d_generation_demand` |
| "just do it" | generate ✓ | demand |
| "show me" | generate ✓ | demand |
| "let's see" | generate ✓ | demand |
| "render it" | generate ✓ | demand |
| "make it" (alone) | generate ✓ | demand |
| "try it" | generate ✓ | demand |
| "create it" | generate ✓ | demand |
| "do it now" | generate ✓ | demand |
| "go ahead" | generate ✓ | demand |
| "generate now" | generate ✓ | demand |
| "just do it" (empty history) | generate ✓ | demand (no history dependency) |

### Section 4 — Discussion Preservation

| User Message | Route |
|---|---|
| **Scenario E**: "What do you think of this living room?" | design_discussion ✓ |
| **Scenario F**: "Compare these two atmospheres" | design_discussion ✓ |
| "Compare these two designs" | design_discussion ✓ |
| "Compare both options" | design_discussion ✓ |
| "What are the pros and cons?" | design_discussion ✓ |
| "Is this atmosphere too dark?" (Wave 4.11c) | design_discussion ✓ |
| "Would darker floors work?" (Wave 4.11a) | design_discussion ✓ |
| "Should I keep the TV wall?" | design_discussion ✓ |
| "Is the kitchen too bright?" | design_discussion ✓ |

### Section 5 — Regression Checks

| Test | Expected | Got |
|---|---|---|
| First-time "make it bigger" → still AMBIGUITY_CLARIFY | AMBIGUITY | ✓ |
| First-time "make it pop" → still AMBIGUITY_CLARIFY | AMBIGUITY | ✓ |
| First-time "change it" → still AMBIGUITY_CLARIFY | AMBIGUITY | ✓ |
| First-time "more" / "less" → still AMBIGUITY_CLARIFY | AMBIGUITY | ✓ |
| Negative feedback after clarification: "I don't like this" | design_discussion / negative_feedback | ✓ |
| Negative feedback after clarification: "this is worse" | design_discussion / negative_feedback | ✓ |
| Negative feedback after clarification: "I preferred the previous" | design_discussion / negative_feedback | ✓ |
| PRODUCT_HELP question after clarification | product_help | ✓ |
| Long redirect ("Actually, can we discuss…") after clarification | NOT generate | ✓ |
| "compare X" after clarification → design_discussion (not auto-generate) | design_discussion | ✓ |
| V1 always generates regardless of message | generate | ✓ |

**Wave 4.11(a+b+c) full suite re-run after Wave 4.11d wiring: 95/100 — identical to the pre-4.11d baseline. No regression.**

### Section 6 — Adversarial Probes

| Probe | Got | Verdict |
|---|---|---|
| "please generate a version with darker wood" | generate (via _REFINE / _LOCAL_EDIT, not demand override) | ✓ Correct — embedded "generate" + edit doesn't trigger bare demand |
| "Can you compare X vs Y?" | design_discussion | ✓ Wave 4.11d compare-vs pattern |
| Confusion after clarification ("I'm not sure what you mean") | meta/confusion (NOT generate) | ✓ Correct — confusion is meta, not a clarification answer |

## Observed Behavior Changes

**Before Wave 4.11d** (real conversation excerpt from user observation):
```
User:      make it bigger and brighter
Architect: When you say bigger — are you thinking : sofa / seating area / room feeling?
User:      overall room feeling
Architect: Better in which direction — materials / lighting / atmosphere?      ← unwanted
User:      yes
Architect: <still discussing>                                                   ← friction
```

**After Wave 4.11d** (same input chain):
```
User:      make it bigger and brighter
Architect: When you say bigger — are you thinking : sofa / seating area / room feeling?
User:      overall room feeling     →     [Wave 4.11d clarification_resolved]
Architect: <generates next vision>                                              ← desired
```

## Potential Risks

1. **Marker-list drift**: `_ASSISTANT_CLARIFICATION_MARKERS` mirrors phrasing from `ambiguity_detector._RULES`. If clarification copy changes substantially in a future wave, the detector misses the "previous turn was a clarification" signal and 4.11d falls back to the existing chain. **Mitigation**: documented in the code; paired update required.

2. **Short answers that aren't really answers**: A user might type a short message that LOOKS like a clarification answer but means something else ("nothing" / "skip" / "later"). The `_NOT_AN_ANSWER` regex catches the common cases (redirects, questions, confusion, dissatisfaction). Unusual responses may slip through and force an unwanted generation. **Mitigation**: real-device feedback will surface these; can extend `_NOT_AN_ANSWER` patterns.

3. **"make it" override**: "make it" alone is routed as bare demand. If a user types just "make it" mid-conversation, they get a generation. This is intentional per Principle 4. Edge case: user types "make it" intending "make it [something I forgot to add]". Rare in practice.

4. **Wave 4.11a brevity discipline**: Wave 4.11d does NOT touch the brevity guardrail. Generated responses on the 4.11d path still go through `generate_chat_response` with the same length controls. The 5 documented design behaviors (LOCAL_EDIT silences trade-offs, alts suppresses memory) are unchanged.

5. **No KM-specific generation demand patterns**: The `_GENERATION_DEMAND` regex is EN-only. A Khmer user typing "បង្កើតឥឡូវ" (generate now) would fall through to the existing chain. **Acceptable for v1**: real KM user feedback will inform a future KM-demand pattern.

## Performance Impact

- `detect_generation_demand`: one regex match against the message → ~0.05 ms
- `is_clarification_answer`: at most one history scan (reverse to last assistant) + 3 regex tests → ~0.1 ms
- New `_GENERATION_DEMAND` and `_ASSISTANT_CLARIFICATION_MARKERS` patterns precompiled at import time

**Total added overhead per /chat: ~0.15 ms**. Negligible vs the existing ~2.7 ms Wave 4.11(a+b+c) layer and the ~30 000 ms gpt-image-1 generation cost.

## Final Recommendation

# Ready To Ship

All 50 validation cases pass. The full Wave 4.11(a+b+c) regression suite (100 tests) holds at 95/100 — identical to the pre-4.11d baseline. All 6 acceptance scenarios from the task spec pass. All 11 documented regression checks pass. All 3 adversarial probes pass.

The principle ordering is preserved:
- Meta intents (greeting / frustration / stop_generation) still win first
- Negative feedback still routes to DESIGN_DISCUSSION / NEGATIVE_FEEDBACK
- First-time ambiguous messages still get a clarification
- Genuine architectural questions still route to DESIGN_DISCUSSION
- Wave 4.11d only fires on the second user turn of an ambiguity dialog, or on explicit demand

The product promise — **Photo → Conversation → New Vision** — is restored.

## Files Changed

| File | Lines added | Purpose |
|---|---|---|
| `prompt_engine/intent_classifier.py` | ~145 | `_GENERATION_DEMAND` + `_ASSISTANT_CLARIFICATION_MARKERS` + `_NOT_AN_ANSWER` patterns; `detect_generation_demand` / `last_assistant_was_clarification` / `is_clarification_answer` helpers; `_REFINE` cozy/elegant/etc; `_DESIGN_DISCUSSION_PATTERNS` compare/pros-and-cons |
| `main.py` | ~50 | Wave 4.11d layer wired into `/chat` between meta_intent and detect_ambiguity |

Validation harness (untracked, kept for regression): `_wave_411d_validation.py`.
