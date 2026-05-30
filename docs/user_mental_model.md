# User Mental Model — AIHomeArchitect

> **How Muy expects AIHomeArchitect to behave.**

This is a **living document**. It is the canonical reference for the product owner's mental model of how AIHomeArchitect should feel and behave from a user's perspective — independent of technical correctness.

## How to use this document

**Before proposing any wave, UX change, routing modification, prompt change, or response-shape change**, consult this document. Ask the five questions in [§7 — Decision Framework](#7--decision-framework). If a proposal conflicts with a recorded mental-model insight, flag it explicitly before proceeding.

This document is NOT a list of features. It is a reference for **product judgment**. Validation suites verify code correctness; this document verifies behavioural alignment with the target user.

## Conventions

- Each observation is logged with the format requested in the originating task (Situation / User Expectation / Actual Behavior / Why It Felt Wrong / Mental Model Insight / Product Impact).
- Each pattern is tagged **[STATED]** (user said it explicitly) or **[INFERRED]** (extracted from frustration / delight / context). Inferred patterns require more scrutiny.
- Sources are cited with their origin: `[real conversation: 2026-XX-XX]`, `[user brief: Wave X.Yz]`, etc. No observation is recorded without a source.
- Last updated: **2026-05-30**

---

## 1 — Core Product Promise

> **Photo → Conversation → New Vision**

Not:
> Photo → Endless Clarifications

Not:
> Photo → Architectural Lecture

The user comes to AIHomeArchitect to **see architectural transformations**. Conversation is a tool to refine them, not an end in itself. Anything that interrupts the flow Photo → Vision creates friction and erodes the product promise.

**Source**: User brief, Wave 4.11d framing, 2026-05-30. **[STATED]**

---

## 2 — Observation Log

### Observation #1 — Repeated clarification loop

**Source**: Real conversation transcript surfaced by user, 2026-05-30 (Wave 4.11d brief).

#### Situation

```
User:      make it bigger and brighter
AI:        asks clarification (sofa / seating area / overall feeling?)
User:      overall room feeling
AI:        asks another clarification
User:      yes
AI:        continues discussing
```

#### User Expectation

After answering the first clarification ("overall room feeling"), generate the next vision.

#### Actual Behavior

System asked a second clarification, then continued discussing instead of generating.

#### Why It Felt Wrong

The user believed the clarification had already been answered. Continuing to discuss after a direct answer reads as **the architect not listening**.

#### Mental Model Insight

> **When a clarification has been answered, generation should become the default behaviour. Each clarification topic has a budget of one round.**

#### Product Impact

**High** — directly breaks the Photo → Conversation → Vision promise. Drove Wave 4.11d.

---

### Observation #2 — Short brief, expected immediate action

**Source**: User brief, Wave 4.11d, "real examples observed", 2026-05-30.

#### Situation

```
User:      missing quality
AI:        asks clarification
User:      provides clarification
AI:        continues discussing instead of generating
```

#### User Expectation

After providing the clarification, see the next vision.

#### Actual Behavior

Continued discussion after the answer.

#### Why It Felt Wrong

Same mechanism as Observation #1 — the system treated a resolved ambiguity as an open one.

#### Mental Model Insight

> **A short answer is a sufficient answer. The user is not obligated to elaborate. Brevity is not under-specification.**

#### Product Impact

**High** — reinforces Observation #1. Same root cause, same fix (Wave 4.11d).

---

### Observation #3 — Direct demand for generation

**Source**: User brief, Wave 4.11d, "real examples observed", 2026-05-30.

#### Situation

```
User:      why don't you generate?
AI:        continues to clarify / discuss
```

#### User Expectation

Immediate generation. No more clarification. No more discussion.

#### Actual Behavior

System continued in conversational mode despite the explicit demand.

#### Why It Felt Wrong

The user has **explicitly told the system** what they want. Continuing to ask reads as the system overruling the user.

#### Mental Model Insight

> **Explicit user demand for generation must dominate everything else (except meta intents like STOP_GENERATION and explicit dissatisfaction). When the user says "generate", "show me", "just do it", "why don't you generate?", "make it" — generate.**

#### Product Impact

**Critical** — direct user override being ignored is the single most damaging behaviour to perceived intelligence. Drove Wave 4.11d Principle 4 (Frustration Override).

---

### Observation #4 — Production log: interrogative form mis-classified as STOP_GENERATION

**Source**: `backend/logs/backend.log` at `2026-05-30 09:07:02`, session `437578ac-f272-450e-bbd6-1bb380aae14b`. Real user, real production conversation.

#### Situation

```
[V3 user]      "why you don't generate?"     ← real user input (verbatim from log)
[V3 system]    detected meta_intent = stop_generation  (confidence 0.90)
[V3 response]  "Of course — let's discuss first. What are you thinking about?"
```

Atmosphere: Desert Luxe. Room: Living Room. Iteration: 3 (V3+).

#### User Expectation

Frustrated demand for generation. The user means: **"Pourquoi tu ne génères pas ?"** / "Why aren't you generating?" — Wave 4.11d Principle 4 territory.

#### Actual Behavior

System classified the message as STOP_GENERATION ("the user is asking me to NOT generate") and offered to discuss first. **The literal opposite of what the user meant.**

#### Why It Felt Wrong

The pattern `_STOP_GENERATION` in `meta_intent.py` is `\b(don'?t\s*(generate|create|make|...))\b` — it matches the literal substring `"don't generate"` anywhere in the message. The user's word order — `"why you don't generate?"` (French-influenced) — contains that substring while meaning the **opposite** intent. `_STOP_GENERATION` fires, meta intent wins absolute precedence over Wave 4.11d, and the user gets a "let's discuss" response when they just demanded action.

This was NOT caught by Wave 4.11d's synthetic validation suite because the suite used the canonical English word order (`"why don't you generate?"`) which does NOT contain `"don't generate"` adjacent (the words are `don't / you / generate`). The real user's word order is the mirror.

#### Mental Model Insight

> **Production conversations contain phrasings that synthetic tests will not predict. Word order influenced by the user's native language (here: French) produces strings that match the WRONG meta intent. The fix is not "add more synthetic patterns" — it's "treat interrogative-form demands for generation as a protected class that meta_intent's STOP_GENERATION must never claim".**

This generalizes beyond this specific case: **any meta intent that uses a "verb + don't" or "don't + verb" sub-pattern must check whether the message is actually an interrogative demand for the opposite action.** The same risk exists with `_FRUSTRATION` ("don't work", "not good") and other negative-form meta patterns.

#### Product Impact

**Critical** — directly contradicts Wave 4.11d Principle 4 (Frustration Override). A user demanding generation is being told to wait. This is the worst possible feel for the user's actual mental state (frustrated, wants action). Drove Wave 4.11d.1.

---

### Observation #5 — Clarification answered, system still asks open-ended question

**Source**: Real conversation review post-Wave 4.11d ship, 2026-05-30 (Wave 4.11e brief).

#### Situation

```
[V2 user]      "I want it bigger"
[V2 assistant] "What do you want bigger?
                • sofa
                • seating area
                • overall room feeling"
[V3 user]      "overall room feeling"
[V3 assistant] "Does the empty space feel intentional?"   ← unwanted new topic
               (or another architect-style follow-up)
```

#### User Expectation

After the V3 answer, one of two things:
- **Path A** — generate immediately
- **Path B** — summarize what's been agreed AND ask "anything else before I generate?"

#### Actual Behavior (post-Wave 4.11d, pre-Wave 4.11e)

Wave 4.11d correctly routed to GENERATE (`should_generate=True`) but the chat response surfaced a new open-ended architectural question. The frontend rendered the question BEFORE triggering /generate, so the user saw a new discussion branch opened at the very moment they expected forward momentum.

#### Why It Felt Wrong

The clarification question was answered. The user has already made their decision. Opening a new architectural question signals "the architect is still uncertain" — exactly the opposite of the perceived intelligence the user wants. From the user's mental model: the assistant should commit visibly to what was just resolved, not branch into a new architectural inquiry.

This is **not the same bug as Observation #1/#2** (where the system asked ANOTHER clarification). Here Wave 4.11d already did the routing right — `should_generate=True`. The remaining issue is the chat TEXT shown alongside the routing decision.

#### Mental Model Insight

> **A resolved clarification must have a clean exit. Valid exits are GENERATE (with brief commit text) or FINAL_CONFIRMATION (summary + "anything else?"). Invalid exit: open a new architectural discussion topic. The bridge from clarification answer to vision must read like the architect locking in, not exploring further.**

This generalises: **routing decisions and chat text must agree on momentum**. When `should_generate=True`, the chat text must not undermine it by opening discussion. When `should_generate=False`, the chat text should not feel like an evasion.

#### Product Impact

**High** — directly attached to the core promise (Photo → Conversation → Vision). The damaging perception is not lack of generation — it's the architect APPEARING uncertain after the user committed. Drove Wave 4.11e CLARIFICATION_EXIT.

---

### Observation #6 — Summarization request treated as architectural discussion

**Source**: Real conversation review post-Wave 4.11d ship, 2026-05-30 (Wave 4.11e brief).

#### Situation

```
[V≥3 user]     "Can you summarize what I want?"
[assistant]    [architect-style discussion / generic chat response]
```

#### User Expectation

Structured recap of the agreed direction (atmosphere, preservations, refinements) + an explicit bridge to generation: "Ready to generate the next vision?"

#### Actual Behavior (pre-Wave 4.11e)

`"Can you summarize…"` fell through `classify_intent` to either CONVERSATION/QUESTION or CONVERSATION/general — both produce open-ended chat responses. The user got a discussion-style reply instead of a structured recap.

#### Why It Felt Wrong

The user uses summarization as a **validation step**, not as a request for discussion. They want to confirm the architect understood the brief before generating. Receiving more discussion in response reads as the architect not even recognizing the meta-request.

#### Mental Model Insight

> **Users use summarization requests as a validation step before generation. When asking "Can you summarize what I want?" they are not requesting discussion — they are verifying that the architect correctly understood the brief. The expected next step is generation.** The summary itself should be structured (bulleted, atmosphere-anchored, preservation + push/remove buckets) and end with an explicit bridge ("Ready to generate the next vision?").

#### Product Impact

**Medium-High** — affects power users who explicitly check their brief mid-conversation. Drove Wave 4.11e SUMMARIZE_DESIGN_BRIEF.

---

## 3 — Recurring Patterns

Patterns are derived from observations and other product-owner statements. Each pattern cites its evidence base.

### Pattern A — User prefers action over discussion. **[STATED]**

Repeated in user brief: "The user ultimately comes to AIHomeArchitect to see architectural transformations, not to remain trapped in discussion loops."

**Evidence**: Observations #1, #2, #3. Wave 4.11d brief title: "Generation Intent Dominance".

**Operational rule**: When the routing decision is borderline between GENERATE and DISCUSS, lean GENERATE. The exception is genuine architectural opinion-seeking (Scenario E/F — "What do you think?", "Compare these two").

### Pattern B — User values momentum. **[STATED]**

User brief: "Favor progress. If the conversation already contains an atmosphere, a room, a previous vision, a clear refinement instruction — then bias toward generation. Avoid repeated clarification loops."

**Operational rule**: Once the user has provided context (atmosphere + room + vision + refinement), repeated clarification reads as regression. The architect should compound context, not re-collect it.

### Pattern C — User interprets short answers as sufficient. **[STATED]**

User brief: "The answer itself may be short. Short answers should not automatically trigger additional clarification."

**Operational rule**: When a user gives a short on-topic answer after an architect question, treat the ambiguity as resolved. Do not test for completeness. The user knows what they meant.

### Pattern D — User expects the system to behave like an architect, not an interviewer. **[STATED]**

User brief Pattern list (Wave 4.11d).

**Operational rule**: An architect makes judgment calls under uncertainty. An interviewer keeps asking. When the system is uncertain, it should still produce work (a vision, a recommendation) rather than freeze on the user's input. **The first vision is law** (V1 always generates regardless of message) — this principle should ripple into V2+ where possible.

### Pattern E — User is primarily seeking visual transformation. **[STATED]**

User brief Pattern list (Wave 4.11d): "User is primarily seeking visual transformation."

**Operational rule**: Text responses are scaffolding around images. When in doubt about whether to emit text or generate an image, the image wins. Text exists to set up the next image, not to be the end-state.

### Pattern F — User explicitly demanding action must dominate. **[STATED]**

User brief Wave 4.11d Principle 4.

**Operational rule**: "generate", "just do it", "show me", "let's see", "make it" (alone), "why don't you generate?" — these bypass everything else (except STOP_GENERATION / explicit dissatisfaction). No clarification. No discussion. Generate.

### Pattern G — User reads repeated clarification as architectural weakness. **[INFERRED]**

**Evidence**: Observation #1, #2 — the frustration manifests as repeated clarifications, not as the absence of generation. The user reads "the system keeps asking" as "the system doesn't know what to do".

**Operational rule**: A clarification implies the architect couldn't make the judgment call. One clarification is forgivable (sometimes the brief really is ambiguous). Two consecutive clarifications on the same topic reads as incompetence. The clarification budget is one.

### Pattern I — Routing and chat text must agree on momentum. **[INFERRED, post Wave 4.11d ship]**

**Evidence**: Observation #5. After Wave 4.11d shipped, `should_generate=True` was correct but the accompanying chat text undermined it by opening a new architectural question. The user perceived the inconsistency immediately even though the next `/generate` POST WAS firing.

**Operational rule**: When the routing decision sets `should_generate=True`, the chat text must NOT contain an open-ended architect-style follow-up question. The chat text should either: (a) be a brief commit ("Got it — X. On it."), or (b) be a summary + final-confirmation question that names the upcoming generation explicitly. When `should_generate=False` (e.g. SUMMARIZE_DESIGN_BRIEF, PRODUCT_HELP, DESIGN_DISCUSSION), the chat text should NOT feel like an evasion — it must do its specific job (recap / answer / discuss) and bridge cleanly.

### Pattern J — Summarization is a validation step, not a discussion request. **[STATED, Wave 4.11e brief]**

**Evidence**: Observation #6. User brief: "Users often use summarization requests as a validation step before generation. ... they are verifying that the architect correctly understood the brief. The expected next step is generation."

**Operational rule**: Summarization output must be (a) structured (bulleted, scan-able in 3 seconds), (b) anchored in the atmosphere chosen, (c) end with an explicit bridge to action ("Ready to generate?"). Never end a summary with an open-ended discussion question. The summary itself is the answer to the user's validation question.

### Pattern K — A user complaint must NEVER be reformulated as something to preserve. **[STATED, Wave 4.11e sanity-check follow-up]**

**Evidence**: Pre-commit UX sanity check (2026-05-30). Scenario 4 turn 5 surfaced a SUMMARIZE bullet reading `✓ Preserve: The colors are not good` — the architect was claiming to preserve a thing the user had explicitly complained about. Root cause: `_KEEP_PATTERNS` in refinement_memory.py included the bare word `good`, which the negation phrase "are not good" matched on the trailing token, scoring the complaint as a keep signal.

**Operational rule**: Negative-feedback turns must never populate any refinement bucket — not `keep`, not `enhance`, not `add`, not `remove`, not `directions`. They are signals to the architect that the user is unhappy but they do NOT describe what to DO. Any downstream consumer of `refinement_state` (summary, prompt composition, memory injection) must treat the absence of a complaint as the correct behavior. If a user said "the colors are not good", the brief summary should NOT echo it back — the absence is the acknowledgement. The complaint is handled inline by the NEGATIVE_FEEDBACK chat response template, not by recording it as a directive.

**Generalisation**: any time the system parses user intent into structured state, it must distinguish between (a) directives the user is GIVING ("keep the windows", "add plants"), (b) directives the user is RECEIVING ("the architect suggests X"), and (c) sentiment ("I don't like X") — and only (a) belongs in refinement buckets. (c) must be filtered out at the parser level, not at the surface layer.

### Pattern H — Architectural Q&A is the protected exception, not the default. **[INFERRED + partially STATED]**

User brief Wave 4.11d Principle 5: "Preserve discussion mode for genuine architectural discussion. ... These should remain discussion-oriented. Do not reduce architectural intelligence."

**Evidence**: User does NOT want to flatten everything into GENERATE. "What do you think of this living room?", "Is this atmosphere too dark?", "Compare these two designs" — these stay discussion-mode by design.

**Operational rule**: There is a small, well-defined set of architectural Q&A shapes (opinion-seeking questions, comparisons, pros-and-cons, recommendations). These keep their discussion routing. Everything else biases toward generation.

---

## 4 — Unresolvable Tensions

Where Muy's expectations conflict with feasibility. These are recorded honestly — the document is useful precisely because it surfaces tensions instead of pretending alignment is total.

### Tension 1 — "Feels instant" vs. gpt-image-1 latency

**Expectation**: User wants the next vision to feel immediate after a refinement.

**Reality**: gpt-image-1 generation takes ~30 seconds. JPEG transport adds 2–6 seconds.

**Current mitigation**: None at the model layer. UX-side: pre-flight progress indicator. Backend memory note `pending_job_queue_notifications.md` proposes job-queue + notifications so users can navigate away during generation without losing the result.

**Implication for waves**: Do not pursue "make generation faster" through prompt compaction or quality reduction alone — Wave 5.13 froze the prompt engine at 61.5% PASS baseline. Faster generation requires gpt-image-2 or batching. Latency is mostly an irreducible cost at the model layer.

### Tension 2 — Architectural intelligence vs. zero friction

**Expectation**: User wants minimal friction (Pattern A, B, F) AND architectural intelligence (Pattern H).

**Reality**: A genuine architect asks clarifying questions when the brief is truly ambiguous. A zero-friction generator never does. These two values fight each other in borderline cases ("make it bigger" with no scope).

**Current mitigation**: Wave 4.11a clarification budget = 1; Wave 4.11d resolves the budget on the user's first answer. The architect gets ONE chance to clarify, then must commit.

**Implication for waves**: When in doubt, lean toward commit. The Wave 4.11a confidence threshold (≥0.7 to fire ambiguity) is the dial — raising it shifts toward zero friction, lowering it shifts toward architect interrogation. Default is 0.7; do not raise above 0.85 or genuine clarifications get suppressed.

### Tension 3 — Cambodia-launch KM coverage vs. EN-first authoring

**Expectation**: KM users get first-class architectural intelligence (Wave 4.11 KM patterns, KM clarifications, KM language detection).

**Reality**: All EN classifier patterns get developed first. KM patterns lag behind. Real-world KM corpus that would inform pattern authoring is not yet collected.

**Current mitigation**: Wave 4.11c added Khmer Unicode language detection + expanded KM patterns for the highest-leverage topics (reveal_compare, support, generation_failed). Wave 4.12 backlog item #1 = Khmer Architectural Discussion.

**Implication for waves**: KM coverage will lag EN coverage by 1–2 waves. Acceptable as long as the gap is visible and on the backlog, not invisible.

### Tension 4 — Synthetic validation vs. real-conversation feel

**Expectation**: User wants the validated, shipped product to feel right in real use.

**Reality**: Synthetic test suites (the 100-test Wave 4.11 harness, the 50-test Wave 4.11d harness) verify routing correctness. They do not verify subjective "feel". Wave 4.11d itself was triggered by real-conversation observations that bypassed all synthetic validation.

**Current mitigation**: This document. Real-conversation observations now feed back into the mental model and inform future waves.

**Implication for waves**: After every shipped wave, log a real-conversation observation here (if any) within 1 week. If no observation is logged, that itself is a signal — either the wave didn't get tested, or it didn't surface friction.

---

## 5 — Decision Log

Future waves that consult this document should record which mental-model insights drove the decision. This creates traceability.

### Wave 4.11d — Generation Intent Dominance

**Date**: 2026-05-30  
**Insights consulted**: Observations #1, #2, #3. Patterns A, B, C, F, G. Tension 2.  
**Decisions driven by mental model**:
- Clarification budget = 1 round (Pattern G, Observation #1, #2)
- Generation demand override (Pattern F, Observation #3)
- Short answer = sufficient answer (Pattern C, Observation #1)
- Architectural Q&A stays protected (Pattern H — Scenarios E/F)
- Negative feedback NEVER auto-promotes to GENERATE (Pattern H — protected discussion mode for dissatisfaction)

**Outcome**: 50/50 validation pass; Wave 4.11(a+b+c) regression suite unchanged at 95/100.

### Wave 4.11d.1 — Interrogative-form Generation Demand Anti-Pattern

**Date**: 2026-05-30 (same day, immediately after Wave 4.11d)  
**Insights consulted**: Observation #4 (production log). Pattern F. Tension 4 ("synthetic validation vs. real-conversation feel").  
**Trigger**: Production conversation at backend.log 09:07:02 — real user typed `"why you don't generate?"` and the system replied "let's discuss first" (the literal opposite of what the user meant).

**Decisions driven by mental model**:
- `_STOP_GENERATION` must never claim interrogative forms that contain its tokens (e.g., "why you don't generate?", "why aren't you generating?", "pourquoi tu ne génères pas?"). Added `_INTERROGATIVE_GENERATION_DEMAND` anti-pattern in `meta_intent.py` that suppresses STOP_GENERATION on these shapes.
- Wave 4.11d `_GENERATION_DEMAND` extended to recognise:
  - The French-influenced word order ("why you don't" instead of "why don't you")
  - Gerund forms ("why aren't you generating")
  - "are you not going to generate?"
  - French verbs ("pourquoi tu ne génères pas", "génère", "vas-y génère")
- The fix is a **3-line conditional** in `classify_meta_intent` + one regex addition. No new meta intent class. No response-shape change.

**Generalised insight added to Observation #4**: Any meta intent using "verb + don't" or "don't + verb" sub-patterns must check for interrogative-form anti-patterns. The same risk exists for `_FRUSTRATION`, `_CORRECTION` — not yet observed in production but tagged in Open Questions (§8).

**Outcome**: 28/28 Wave 4.11d.1 validation. Wave 4.11d suite unchanged at 50/50. Wave 4.11(a+b+c) suite unchanged at 95/100. Live HTTP probe against the exact production string `"why you don't generate?"` (Desert Luxe / Living Room / V3) now routes to `generate/refine_atmosphere` via `[Wave 4.11d] generation dominance fired : generation_demand`. **The production bug is fixed.**

**Methodological lesson** (captured in Tension 4): Wave 4.11d shipped after 50/50 synthetic validation and 8/8 regression. The production bug surfaced within hours of restart because the synthetic suite used `"why don't you generate?"` (canonical word order) but the real user typed `"why you don't generate?"` (French-influenced). **Real-conversation observation is irreplaceable.** Going forward: every shipped wave must log at least one real-conversation observation here within 1 week of shipping, or be flagged as untested in the wild.

### Wave 4.11e — CLARIFICATION_EXIT + SUMMARIZE_DESIGN_BRIEF

**Date**: 2026-05-30 (same day as Wave 4.11d / 4.11d.1)
**Insights consulted**: Observations #5, #6. Patterns A, B, E, I, J. Tensions 2, 4.
**Trigger**: Real-conversation review surfaced two friction points that survived Wave 4.11d/4.11d.1 — (a) clarification-exit chat text opened a new question even when `should_generate=True`, (b) summarization requests were treated as architectural discussion instead of validation steps.

**Decisions driven by mental model**:
- **Path A as default exit**: brief commit ("Got it — X. On it.") + immediate /generate. Path B (summary + "anything else?") deferred to multi-axis flows — single-axis answers don't need a pause (Pattern B — momentum).
- **SUMMARIZE never auto-generates**: explicit two-step bridge (summary → user confirms → Wave 4.11d catches "yes/generate"). Pattern J says the summary IS the validation answer ; auto-generating would skip the validation the user explicitly asked for.
- **EN + FR + KM coverage for both features**: KM patterns initial-only (5 forms for SUMMARIZE, 2 templates for CLARIFICATION_EXIT) — expand based on real KM usage.
- **Bulleted output format with ✓ checkmarks**: user's brief example explicitly used ✓ — honored despite project convention of no emojis.
- **Atmosphere-anchored summary**: every summary opens with the atmosphere identity ("Keep the Warm Modern character") — anchors the brief in the visible product axis.

**Outcome**: 54/54 Wave 4.11e validation. Wave 4.11d suite unchanged at 50/50. Wave 4.11d.1 unchanged at 28/28. Wave 4.11(a+b+c) unchanged at 95/100. Live HTTP probes confirm end-to-end behavior on backend with full Wave 4.11(a..e) stack loaded.

**Real-conversation observations to capture post-ship**:
- Does "Got it — X. On it." read naturally for short single-axis answers, or does it feel template-y after repetition?
- Does the bulleted summary's atmosphere anchor add value, or does the user just want the buckets?
- Do real KM users use any SUMMARIZE phrasing NOT in `_SUMMARIZE_BRIEF_KM`? If yes, log here and expand.

### Wave 4.11e — sanity-check follow-up (3 Tier-1 fixes)

**Date**: 2026-05-30 (same day as Wave 4.11e initial implementation)
**Insights consulted**: Pattern I (routing and chat text must agree on momentum), Pattern J (summarization is validation), **Pattern K (complaint never reformulated as preservation — added in this follow-up)**.
**Trigger**: Pre-commit UX sanity check surfaced 3 critical gaps that synthetic validation missed.

**Decisions driven by mental model**:
- **Fix 1 — `generation_demand` exit template**: same lesson as Wave 4.11e's CLARIFICATION_EXIT (Pattern I). Routing was right (`should_generate=true`) but chat text undermined it ("What would you change next?" after the user demanded action). Added `generate_generation_demand_response()` with action-oriented commit templates ("Got it — generating the next vision now.", "Coming right up.", etc.) for EN/FR/KM.
- **Fix 2 — plural negative-feedback patterns**: real users say "the colors are not good" / "these aren't right" / "the materials weren't fitting" — the pre-existing pattern was singular-only. Broadened `(this|it|that|the\s+\w+)\s+(is\s+not|isn't)` → `(this|it|that|these|those|the\s+\w+)(\s+\w+){0,3}\s+(is\s+not|isn't|are\s+not|aren't|don't|do\s+not|...)` with an optional 0-3 word noun slot between determiner and aux verb. Also added bare-plural-noun anchored at message start ("colors are not good").
- **Fix 3 — refinement_memory negative-feedback guard**: the root cause of the worst bug (Pattern K) was the word `good` in `_KEEP_PATTERNS`, causing "are not good" to match `keep` via the trailing `good` token. Added `_NEGATIVE_FEEDBACK_GUARD` regex in refinement_memory.py + a "skip" sentinel returned by `_classify` when the clause is a complaint. `parse_history` then drops the clause from all refinement buckets. Pattern K is now enforced at the parser level, not the surface layer.

**Outcome**:
- Wave 4.11e suite : 54/54 (unchanged)
- Wave 4.11d suite : 50/50 (unchanged)
- Wave 4.11d.1 suite : 28/28 (unchanged)
- Wave 4.11(a+b+c) suite : 94/100 (was 95/100 — 1 documented behavior change : `"the dark wood is not good for this kitchen because of stains"` now correctly routes to negative_feedback. The pre-existing test expected this complaint to NOT route as negative_feedback because it had a "for X" qualifier ; the new behavior is more aligned with Pattern J + K — a complaint with rationale is still a complaint).
- 5-scenario sanity check : all 5 pass post-fixes.

**Methodological lesson**: Synthetic validation suites have a survivorship bias — they test the patterns we already thought of. The Wave 4.11e sanity check followed Pattern I (routing+chat text alignment) but applied it only to `clarification_resolved`, missing the parallel `generation_demand` branch. Similarly, the negative-feedback pattern was authored against singular subjects only because the test cases used singular subjects. **Real conversations break test coverage in ways synthetic tests cannot predict.** Going forward: when fixing one branch of a pattern (e.g. CLARIFICATION_EXIT), explicitly enumerate ALL branches of that pattern before declaring the wave shipped. The pre-commit UX sanity check is the gate that catches this.

---

## 6 — Maintenance Workflow

When new feedback arrives (screenshots, conversation excerpts, real-device frustrations, delight moments):

1. **Analyze the situation.** Re-read the actual conversation. Resist summarizing.
2. **Extract the deeper expectation.** What was the user trying to accomplish, not what was typed?
3. **Add to the Observation Log** (§2) using the canonical format. Cite the source.
4. **Update or add a Pattern** (§3) if the observation reveals a new recurring theme. Mark **[STATED]** or **[INFERRED]**.
5. **Update Unresolvable Tensions** (§4) if the observation surfaces a feasibility conflict.
6. **Highlight contradictions** with existing patterns. If a new observation conflicts with a recorded pattern, log it — the contradiction is more informative than either side alone.

**When proposing a wave**: open this document, scan Patterns (§3) and Tensions (§4), then add a Decision Log entry (§5) recording which insights drove the proposal.

**When validating a wave**: cite the observation log entry that the wave was supposed to resolve. If no observation exists, the wave is speculative — flag this explicitly.

---

## 7 — Decision Framework

Before any proposed change, answer these five questions:

1. **Does this align with the user's mental model?** (consult §3 Patterns)
2. **Does this create friction?** (consult §1 Core Promise and Patterns A/B)
3. **Does this accelerate progress?** (consult Patterns B/E/F)
4. **Does this increase perceived intelligence?** (consult Patterns D/G/H)
5. **Does this increase perceived architectural value?** (consult Pattern D, Tension 2)

If three or more answers are "no", reconsider the proposal. If a "yes" creates tension with a recorded pattern, surface the tension explicitly in the proposal.

---

## 8 — Open Questions

Pending observations that haven't been resolved into the model yet. These should be revisited when more real-conversation data arrives.

- **How does Muy react to a 30-second wait between turns?** (Tension 1) — Does the UX-side progress indicator carry enough confidence, or does silence read as "stuck"?
- **What does Muy expect when atmosphere DNA can't fulfill a request?** (e.g., "make it more brutalist" — Brutalism isn't in the DNA registry). Does he expect a graceful redirect ("we don't support brutalist; closest is industrial — proceed?") or silent best-effort?
- **Does the architect's voice register need to soften between V2 and V5?** As the conversation matures, does the user expect MORE architectural opinion (since trust has built) or LESS (since the user has shown direction)?
- **Does "Got it — X. On it." (Wave 4.11e CLARIFICATION_EXIT default) read naturally after repetition?** Or does it become template-y after the user sees it 3+ times in a session?
- **Do real KM users use SUMMARIZE phrasings not in `_SUMMARIZE_BRIEF_KM`?** Initial coverage is 5 forms (`សង្ខេប`, `សារសំខាន់`, `តើ\s*អ្នក\s*យល់`, `និយាយ\s*សង្ខេប`, `រំលឹក\s*ខ្ញុំ`). Real corpus needed.
- **Path B (summary + "anything else?" pause before generate) — when should it activate?** Wave 4.11e ships Path A only. Path B might be useful when the user gives a MULTI-AXIS clarification answer (e.g. "bigger feeling AND warmer materials AND brighter") — but no real observation yet.

These remain open until real conversations surface answers.

---

*Maintained by: the product owner (Muy) + Claude. Updated whenever new observations arrive. Last updated: 2026-05-30 (post Wave 4.11e ship).*
