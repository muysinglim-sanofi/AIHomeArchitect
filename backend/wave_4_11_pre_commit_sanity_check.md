# Wave 4.11 — Pre-Commit UX Sanity Check

**Methodology**: All 5 scenarios were sent through the live backend (task `bes8yifed` running with Wave 4.11(a+b+c+d+d.1+e) loaded) as multipart `POST /chat`. Every `ai_message` shown below is the **literal, unedited string** returned by the running server — no paraphrasing, no shortening, no synthetic substitutes.

---

## 1 — Scenario Outputs

### Scenario 1 — Clarification + answer

**Turn 1**

User message: `I want it bigger`

Routing: `intent=design_discussion / sub_intent=design_discussion`, `should_generate=false`

Assistant response (verbatim):
```
When you say bigger — are you thinking :
• the sofa or specific seating piece
• the seating area (more generous arrangement)
• the overall room feeling (architectural openness)

Tell me which and I'll calibrate the next vision.
```

**Turn 2**

User message: `overall room feeling`

Routing: `intent=generate / sub_intent=refine_atmosphere`, `should_generate=true`, reason=`wave_4_11d_clarification_resolved`

Assistant response (verbatim):
```
Locked in: overall room feeling. Generating now.
```

---

### Scenario 2 — SUMMARIZE design brief

**Case A — Fresh conversation, no prior turns**

User message: `Can you summarize what I want?`

Routing: `intent=design_discussion / sub_intent=summarize_design_brief`, `should_generate=false`

Assistant response (verbatim):
```
Here is my understanding:

✓ Keep the Warm Modern character of the current vision
✓ Latest direction: "Can you summarize what I want"

Ready to generate the next vision?
```

**Case B — Realistic history (5 turns: keep windows + warmer materials + add plants)**

User message: `Can you summarize what I want?`

Routing: `intent=design_discussion / sub_intent=summarize_design_brief`, `should_generate=false`

Assistant response (verbatim):
```
Here is my understanding:

✓ Keep the Warm Modern character of the current vision
✓ Push: warmer materials
✓ Push: add more plants

Ready to generate the next vision?
```

---

### Scenario 3 — `"why you don't generate?"` (frustrated demand)

User message: `why you don't generate?`

Routing: `intent=generate / sub_intent=refine_atmosphere`, `should_generate=true`, reason=`wave_4_11d_generation_demand`

Assistant response (verbatim):
```
Worth trying. What would you change next?
```

---

### Scenario 4 — Realistic 5-turn conversation

**Turn 1** — User: `I don't like the last one`

Routing: `design_discussion / negative_feedback`, `should_generate=false`

Assistant response:
```
Noted. Before we change tack, what would you keep from this version and what should genuinely move ? That gives us a clean brief.
```

**Turn 2** — User: `The colors are not good`

Routing: `conversation / general`, `should_generate=false`  ← **mis-routed, NOT negative_feedback**

Assistant response:
```
That could work well here. Does the warmth feel right, or should we adjust it?
```

**Turn 3** — User: `I want it bigger`

Routing: `design_discussion / design_discussion (AMBIGUITY_CLARIFY)`, `should_generate=false`

Assistant response:
```
When you say bigger — are you thinking :
• the sofa or specific seating piece
• the seating area (more generous arrangement)
• the overall room feeling (architectural openness)

Tell me which and I'll calibrate the next vision.
```

**Turn 4** — User: `overall room feeling`

Routing: `generate / refine_atmosphere`, `should_generate=true`, reason=`wave_4_11d_clarification_resolved`

Assistant response:
```
Locked in: overall room feeling. Generating now.
```

**Turn 5** — User: `Can you summarize what I want?`

Routing: `design_discussion / summarize_design_brief`, `should_generate=false`

Assistant response:
```
Here is my understanding:

✓ Keep the Warm Modern character of the current vision
✓ Preserve: The colors are not good
✓ Push: I want it bigger
✓ Push: overall room feeling

Ready to generate the next vision?
```

---

### Scenario 5 — Imperfect English compound

**Turn 1** — User: `can make bigger but keep windows`

Routing: `design_discussion / design_discussion (AMBIGUITY_CLARIFY)`, `should_generate=false`

Assistant response:
```
When you say bigger — are you thinking :
• the sofa or specific seating piece
• the seating area (more generous arrangement)
• the overall room feeling (architectural openness)

Tell me which and I'll calibrate the next vision.
```

**Turn 2** — User: `overall room feeling` (answer)

Routing: `generate / refine_atmosphere`, `should_generate=true`, reason=`wave_4_11d_clarification_resolved`

Assistant response:
```
Locked in: overall room feeling. Generating now.
```

---

## 2 — UX Evaluation

| # | PASS / FAIL | Beta-tester rating | One-line reason |
|---|---|---|---|
| 1 | **PASS** | **8/10** | Clarification clean, exit text brief and action-oriented. Slightly terse but works. |
| 2A | **FAIL** | **3/10** | Fresh-conversation fallback echoes the SUMMARIZE request itself as "Latest direction". Reads broken. |
| 2B | **PARTIAL PASS** | **6/10** | Bullets present + bridge-to-generate. But `keep the windows` from history was NOT captured in the "Preserve:" bucket — only the "Push:" items came through. parse_history is missing the preservation parse for this phrasing. |
| 3 | **FAIL** | **4/10** | Routing fires correctly (`should_generate=true`) but the chat text `"Worth trying. What would you change next?"` literally asks the user what to change — they JUST demanded generation. Same class of bug Wave 4.11e was supposed to fix, only fixed for `clarification_resolved`, NOT for `generation_demand`. |
| 4 turn 1 | PASS | 7/10 | "I don't like the last one" routes correctly to negative_feedback; response is diagnostic ("what would you keep / what should genuinely move"). |
| 4 turn 2 | **FAIL** | **3/10** | **"The colors are not good"** mis-routes to `conversation/general` and the architect replies "That could work well here." — literally agreeing with a complaint. `_NEGATIVE_FEEDBACK_PATTERNS` requires `is not / isn't / doesn't` but the user used `are not` (plural subject). |
| 4 turn 3 | PASS | 8/10 | Clarification correctly fires for bigger. |
| 4 turn 4 | PASS | 8/10 | Exit clean. |
| 4 turn 5 | **FAIL** | **3/10** | Summary contains: `Preserve: The colors are not good` — **mis-categorizes a negative-feedback message as a preservation directive**. Also `Push: I want it bigger` / `Push: overall room feeling` are raw user message echoes, not parsed directions. The summary is actively misleading. |
| 5 turn 1 | PARTIAL PASS | 6/10 | Clarification fires correctly for bigger but the response IGNORES the explicit "keep windows" preservation in the same message — no acknowledgment that the windows are being respected. |
| 5 turn 2 | PARTIAL PASS | 6/10 | Exit acknowledges "overall room feeling" but not "keep windows". The user has no chat-text confirmation that their preservation was understood (the backend will still send "keep windows" to /generate via refinement_memory, but the user can't see that). |

**Average rating across scenarios: 5.5 / 10** — below ship-quality for a polished beta experience.

---

## 3 — Remaining Friction

### CRITICAL (would break a real beta test)

1. **`generation_demand` branch has the same bug Wave 4.11e was meant to fix.** When `should_generate=true` is set via `generation_demand` (frustrated user typed "generate", "why don't you generate?", etc.), the chat text is still `generate_chat_response(...)` which produces open-ended follow-ups like "What would you change next?". This contradicts the user's intent. Wave 4.11e fixed it for `clarification_resolved` but the parallel branch was left unfixed.

2. **`_NEGATIVE_FEEDBACK_PATTERNS` does not handle plural subjects** (`are not`, `aren't`, `weren't`). Real users say "the colors are not good", "the materials aren't right", "the chairs are not what I wanted" — all of which currently mis-route to `conversation/general` and get cheerful agreement responses. This is a high-frequency phrasing pattern.

3. **`parse_history` mis-categorizes negative feedback as preservation.** The Scenario 4 summary contains `Preserve: The colors are not good` — actively misleading. The summary template (`generate_brief_summary`) is correct ; the bug is upstream in refinement_memory which treats the negative-feedback turn as input to the `keep` bucket. The summary surfaces the misclassification visibly.

### MEDIUM

4. **Fresh-conversation SUMMARIZE fallback echoes the SUMMARIZE request itself** as "Latest direction". A user trying the SUMMARIZE feature for the first time on a fresh project sees:
   ```
   ✓ Latest direction: "Can you summarize what I want"
   ```
   This reads as broken. Acceptable correct behavior would be either: (a) silently skip the "Latest direction" line when the last user message IS the SUMMARIZE request, or (b) emit "We haven't agreed on a direction yet — what would you like to start with?".

5. **`parse_history` doesn't capture preservation directives like `keep the windows`** into the `keep` bucket. The Scenario 2 Case B history explicitly contained "keep the windows" but the summary didn't include any `Preserve:` line.

### LOW

6. **CLARIFICATION_EXIT doesn't acknowledge the non-clarified half of a compound message.** Scenario 5: user said "can make bigger but keep windows", got the bigger-clarification, answered, got "Locked in: overall room feeling. Generating now." — the windows preservation is honored by the backend but the chat text doesn't confirm it to the user.

7. **Architect chat tone after generation_demand** ("Worth trying.") feels slightly off for a frustrated demand. Even fixing #1 above, the underlying tone selection treats this branch as REFINE_ATMOSPHERE which loads chipper tone variants ("Worth trying", "Yeah, that direction makes sense") that don't read as commitment.

---

## 4 — Improvement Opportunities (no code in this review)

Without writing any code, these are the corrections that would close the gaps above. Each is small and well-scoped.

### Tier 1 — Block-list before commit

1. Extend the `generation_demand` branch in `main.py /chat` (around line 552) to ALSO use `generate_clarification_exit_response` (or a sibling `generate_generation_demand_response`) instead of `generate_chat_response`. The user's demand is more decisive than a clarification answer ; the response should match: `"Generating now."` / `"On it."` / `"Coming right up."` — no question back. ETA: 5 lines + 1 new template pool.

2. Extend `_NEGATIVE_FEEDBACK_PATTERNS` to cover plural-subject negation:
   - `(this|it|that|the\s+\w+|these|those)\s+(doesn'?t|does\s+not|isn'?t|is\s+not|aren'?t|are\s+not|weren'?t)\s+...`
   ETA: 2 chars in the regex.

3. Fix `parse_history` to NOT add a turn's text to the `keep` bucket when the turn is classified as `negative_feedback`. This is a refinement_memory.py change. ETA: ~5 lines.

### Tier 2 — Block-list ideally

4. In `generate_brief_summary`, when the last user message in history IS the SUMMARIZE request itself, skip the "Latest direction:" fallback line. Use a different fallback (e.g. `"You haven't named a specific change yet — share a direction and I'll build the brief"`). ETA: ~5 lines.

5. Extend `generate_clarification_exit_response` to include the OTHER half of a compound user message (the V2 message before the clarification) when it contained a preservation directive: e.g. `"Locked in: overall room feeling. Keeping the windows. Generating now."`. ETA: ~10 lines, needs to read history.

### Tier 3 — Polish

6. Add a `generation_demand` chat-text variant that uses commit-oriented vocabulary ("Generating now.", "On it.", "Coming right up.") instead of the REFINE_ATMOSPHERE tone pool.

---

## 5 — Final Recommendation

# NEEDS ADJUSTMENT

### Honest justification

Wave 4.11d, 4.11d.1, and 4.11e all pass synthetic validation (50/50, 28/28, 54/54). But this UX review surfaced **3 critical gaps** that a beta tester would hit within the first 10 minutes:

- **Critical #1**: Scenario 3 is the EXACT pattern the user reported for Wave 4.11e — the frustrated demand still gets a "what would you change next?" response. We fixed half the bug.
- **Critical #2**: Scenario 4 turn 2 — "the colors are not good" reads as direct user complaint. The architect replied "That could work well here." in production. This is a worse UX than Wave 4.11d.1's interrogative bug because the architect appears to agree with a complaint.
- **Critical #3**: The Scenario 4 turn 5 summary contains `Preserve: The colors are not good` — actively misleading the user about what was agreed.

If we ship these waves as-is, the user will:
- Type a phrasing the synthetic tests didn't cover ("the colors are not good", "the chairs aren't great") and get cheerful agreement
- Demand generation explicitly and get asked what to change next
- Ask for a summary and see their dislikes labeled as "Preserve:"

Each of these is the **exact failure mode** Wave 4.11d/4.11e was supposed to eliminate. The wave-level intent is right ; the coverage is incomplete.

### What I recommend before commit

Apply the 3 Tier-1 fixes above. They're small, well-scoped, and address the exact patterns the user surfaced in this sanity check.

**Estimated implementation time**: 30-45 minutes.

**Estimated re-validation**: 10 minutes (extend existing 4.11d/4.11d.1/4.11e harnesses with regression cases for plural negation + generation_demand chat text + summary parse_history coverage).

After those fixes, the rating curve should rise to ~7-8/10 across all scenarios — ship-quality for beta.

### What I do NOT recommend

Shipping as-is and discovering these in production logs. The user explicitly invoked this sanity check because synthetic validation has been insufficient ; the findings here validate that concern.

---

## Appendix — Live HTTP probe transcripts

All probes were executed against `http://localhost:8000/chat` on backend task `bes8yifed` (Wave 4.11(a+b+c+d+d.1+e) loaded). Multipart form payload included `session_id`, `message`, `style_label=Warm Modern`, `room_type=living_room`, `iteration`, and `history` (JSON array). No transcript edited or simplified.
