# AIHomeArchitect — Validation Protocol
**Version:** Wave 4.2.7+  
**Status:** Active — apply to all future waves

---

## 1. Why This Document Exists

After Wave 4.2.6, an important pattern emerged: DEV mode intentionally degrades image quality, spatial fidelity, and rendering richness to support fast iteration and cost reduction. This is correct behavior. The problem is that degraded DEV output looks indistinguishable from a real regression unless the team knows what to look for.

This document defines the official distinction between:
- **DEV validation** — technical correctness of routing, logic, and orchestration
- **PROD validation** — real product quality, preservation fidelity, and emotional impact

All future waves must apply this protocol. Panic-driven debugging from DEV artifacts ends here.

---

## 2. MVP Priority Hierarchy

These priorities govern roadmap decisions, validation strategy, regression interpretation, preservation logic, atmosphere logic, and AI companion behavior. They are ordered. Priority 1 beats Priority 2 beats Priority 3 when tradeoffs arise.

---

### Priority 1 — Before / After Wow

**This is the most important use case.**

The first render generated from the user's uploaded photo must:

- feel emotionally transformative
- feel premium and architect-designed
- feel believable (it looks like *their* apartment)
- create a "wow" reaction: *"this is my apartment transformed beautifully"*

**This is not primarily about preservation.** It is about transformation impact. The original photo is the emotional anchor, not a pixel-perfect constraint.

| What matters most | What matters less |
|---|---|
| Emotional impact | Pixel-level continuity |
| Realism of materials and lighting | Exact furniture position match |
| Atmosphere completeness | Whether a window moved 10 cm |
| Premium quality | DEV speed |

**Validation focus:** Does this feel stunning to a first-time user?

---

### Priority 2 — Atmosphere Switching

**This is the second most important use case.**

When the user switches atmosphere between iterations, the apartment must remain the **same apartment**:

- same architecture and topology
- same spatial identity and room logic
- same wall positions and openings
- same key equipment anchors (TV, kitchen island, staircase)
- same multi-zone depth and diagonal perspectives

Only the atmosphere changes: materials, lighting, styling, textures, mood, and emotional feeling.

**This is where preservation is critical.** The system must not:

- rewrite topology
- generate a generic luxury apartment instead of the user's room
- collapse multi-zone depth into a flat single-zone composition
- delete architectural anchors that define the room's identity
- reinterpret the space as a completely different floorplan

**Validation focus:** Does this still look like the same apartment with a different soul?

---

### Priority 3 — AI Companion Creative Refinement

**This is the third use case.**

The user is actively collaborating with the AI architect. In this mode the system may:

- move furniture and redesign layout
- add or remove equipment
- increase or reduce openness
- reinterpret room usage creatively

This is the **only mode** where controlled structural creativity is expected and acceptable.

**Validation focus:** Does the conversation feel intelligent? Is the result architecturally plausible and coherent with the user's expressed intent?

---

## 3. DEV vs PROD Testing Rules

### What DEV Mode Is For

| Validate in DEV | Do NOT judge in DEV |
|---|---|
| API routing and endpoint correctness | Final image quality |
| Intent classification | Emotional wow factor |
| Retry logic and error handling | Architectural preservation fidelity |
| Upload and persistence flows | Premium atmosphere quality |
| Generation triggering | Realism |
| Wave validator suites | Spatial depth |
| Profile routing (dev/prod switch) | Whether the apartment "feels right" |
| Orchestration and conversation flow | — |
| Budget and cost-protection logic | — |

### Why DEV Degrades

DEV profile intentionally applies:

| Setting | DEV | PROD |
|---|---|---|
| `quality` | low | high |
| `input_fidelity` | low | high |
| `size` | 1024×1024 (square) | auto (aspect-ratio) |
| `max_attempts` | 1 | 3 |
| `compact_prompts` | True | False |

A landscape apartment photo resized to 1024×1024 **will collapse spatial depth** even with perfect preservation logic. This is not a bug. It is the cost of fast, cheap iteration.

### What PROD Mode Is For

| Validate in PROD | Not necessary in PROD |
|---|---|
| Real UX quality | Validator suite logic |
| Preservation quality between iterations | Retry path unit tests |
| Atmosphere fidelity and emotional impact | Intent classifier correctness |
| Architectural identity continuity | Backend routing |
| Conversational coherence under real load | — |
| Final user experience (Before/After wow) | — |

### PROD Validation Discipline

PROD smoke tests are expensive (real API cost, real latency). Use them sparingly and return to DEV immediately after.

**Rule:** 1–2 targeted PROD smoke renders per wave, not exploratory browsing.

---

## 4. Regression Classification Matrix

When something looks wrong in a test render, apply this classification before escalating:

| Class | Label | Definition | Action |
|---|---|---|---|
| **A** | Real Regression | Previously working functionality is broken by this wave's changes | Fix before wave closes |
| **B** | Expected DEV Degradation | Visual artifact caused by DEV quality/fidelity/square-resize settings | Document; verify disappears in PROD |
| **C** | Known Limitation | Already identified in `KNOWN_LIMITATIONS.md` (L1–L4); not introduced by this wave | Link to limitation entry; defer |
| **D** | Future Product Improvement | Enhancement opportunity, not a broken behavior | Log in backlog; do not block wave |

### How to Classify

Ask in order:

1. **Does it reproduce in PROD?** If not → Class B (DEV degradation).
2. **Is it listed in `KNOWN_LIMITATIONS.md`?** If yes → Class C.
3. **Did it work in the wave before this one?** If yes → Class A (real regression).
4. **Is it a quality improvement that was never implemented?** → Class D.

Only Class A blocks a wave from closing.

---

## 5. Preservation Validation Rules

Preservation means different things depending on which use case is being tested. Do not apply a single preservation standard across all three.

| Use Case | Preservation Expectation | What to Prioritize |
|---|---|---|
| **Before/After (Priority 1)** | Loose — the apartment is the emotional anchor, not a pixel constraint | Transformation quality, emotional impact, realism |
| **Atmosphere Switching (Priority 2)** | Strict — same topology, same anchors, only atmosphere changes | Spatial identity, architectural continuity |
| **AI Companion Refinement (Priority 3)** | Flexible — controlled creativity expected and allowed | Intent coherence, architectural plausibility |

**A topology change in Priority 1 is acceptable.**  
**A topology change in Priority 2 is a regression.**  
**A topology change in Priority 3 may be intentional.**

Never evaluate all three with the same pass/fail rule.

---

## 6. Recommended Validation Workflow for Future Waves

Apply this sequence for every wave, in order:

```
Step 1 — DEV implementation
  Write code, update prompts (if needed), run validator suite.
  Target: all checks pass. No deviations.

Step 2 — DEV functional testing
  Test the specific behaviors introduced by the wave.
  Use DEV for flow correctness only. Do not judge image quality.

Step 3 — PROD smoke validation (1–2 renders max)
  Switch APP_ENV=prod in .env.
  Run 1 Before/After render (Priority 1 check).
  Run 1 atmosphere switch if preservation was touched (Priority 2 check).
  Document what you see. Screenshot or note the result.

Step 4 — Return to DEV
  Switch APP_ENV=dev in .env immediately.
  Do not leave PROD enabled between sessions.

Step 5 — Document findings
  Update CURRENT_WAVE.md with wave result.
  Classify any anomalies using the regression matrix (Section 4).
  Update KNOWN_LIMITATIONS.md if new limitations were discovered.
```

---

## 7. Anomaly Response Rules

| Observation | First question | Likely classification |
|---|---|---|
| Image looks flat/square/washed out | Was this run in DEV? | B — DEV degradation |
| Topology changed during atmosphere switch | Does it reproduce in PROD? | A if PROD, B if DEV only |
| Furniture moved when it shouldn't | Which priority use case was this? | A if Priority 2 in PROD |
| Color is off / materials look cheap | DEV or PROD? | B if DEV, A if PROD |
| Intent routing sent wrong signal | Check validator | A — real regression |
| Retry didn't fire when it should | Check retry classifier | A — real regression |
| App crashed or returned 5xx | Always real | A — real regression |
| Image looks "good but not wow" | Is this PROD? Is this Priority 1? | D — future improvement |

---

## 8. Future Wave Testing Recommendations

### Waves touching prompts or preservation logic
- Mandatory PROD smoke on Priority 2 (atmosphere switch)
- Before and after screenshots for comparison
- Document in wave summary with explicit preservation verdict

### Waves touching orchestration or intent classification
- Full validator suite in DEV
- 1 PROD conversational flow test (type 3–4 messages, verify intent routing in logs)
- No PROD image generation needed unless the prompt engine changed

### Waves touching retry or error handling
- DEV validator suite only (wave 427 pattern)
- No PROD needed unless testing real OpenAI error behavior

### Waves touching profile routing or cost protection
- DEV validator only
- Verify profile logs at startup: `[GenerationProfile] ACTIVE: DEV`

### Major product waves (Wave 4.3.0+, Wave 5.x)
- Full DEV validator suite
- Minimum 3 PROD renders: 1× Before/After, 1× atmosphere switch, 1× refinement sequence
- Written wave summary before closing

---

## 9. What AIHomeArchitect Is Becoming

This product is not an AI image generator.

It is an AI architectural companion. The testing philosophy must reflect that:

- **Technical validators** verify the architecture of the system.
- **PROD smoke tests** verify the soul of the product.
- **MVP priorities** define what "working correctly" means for a user.

A wave that passes all validators but produces a flat, joyless first render has failed Priority 1. A wave that produces a stunning Before/After but breaks atmosphere switching has failed Priority 2.

Both matter. Neither replaces the other. This protocol exists to make both visible.

---

*Last updated: Wave 4.2.7+ — Conversation Orchestration Fix*  
*Owner: AIHomeArchitect engineering*
