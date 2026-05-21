# Wave 5.5.10c — Diagnosis: Vision Prompt / Parser Vocabulary Desync

**Date:** 2026-05-21
**Status:** Minimal fix APPLIED (vocab door only) — pending validation re-run
**Severity:** Root cause of 3.5/9 benchmark failure on Wave 5.5.10b

## Applied changes (Step 1 — minimal scope)

- [backend/main.py:289+](../backend/main.py#L289) — Wave 5.5.10c paragraph added to `_capture_structural_text` docstring
- [backend/main.py:303-309](../backend/main.py#L303-L309) — vision prompt (1) Primary opening section: vocab extended with door variants in parser priority order + explicit anti-rabotage rule for sliding glass panels
- Syntax check: `python -m py_compile main.py` → OK
- Parser, composer.py, composer_v2.py, Wave 5.5.6 delegation: **unchanged**
- V1/V2/V3 byte-identity invariant: **preserved** (clause materialization downstream of capture)

Pending: user-driven validation re-run (3 V1 on benchmark photo) before deciding Step 2 (mirror-flip diagnostic test).

## Summary

Wave 5.5.10 extended the structural-identity parser to recognize sliding glass doors but **forgot to update the vision-capture prompt sent to GPT-4o-mini**. The mini is given an explicit, exhaustive vocabulary for "Primary opening" that contains **only window-type terms**. When it observes a sliding glass door in the input photo, it has no authorized term to describe it and rabotes the description to `"floor-to-ceiling window"`. Downstream, gpt-image-1 receives a prompt that literally says "window" and dutifully renders a mullioned window — never a sliding door.

This explains:
- ✅ Why the parser unit test passes (it correctly handles "sliding glass door" *if* it sees that token)
- ❌ Why the 3 V1 generations of 21 May 2026 all rendered the apartment's sliding glass door as a window with carreaux

## Evidence chain

### 1. Vision capture prompt forces windows-only vocab

**File:** [backend/main.py:300-307](../backend/main.py#L300-L307)

```python
"Analyze this room photograph for architectural preservation. "
"List the FIXED architectural facts using these EXACT vocabulary "
"terms when applicable (downstream parser depends on them): "
"(1) Primary opening — use 'floor-to-ceiling window', 'bay window', "
"'panoramic window', 'corner window', 'glazed wall', 'glazed facade', "
"or 'picture window' when it matches. Add a size qualifier "
"('wide', 'large', 'tall', 'full-height', 'dominant'). State the wall "
"(left/right/back). "
...
```

No `sliding glass door`, `patio door`, `balcony door`, or `french doors`.

### 2. Parser already knows about doors (Wave 5.5.10)

**File:** [backend/prompt_engine/structural_identity.py:120-126](../backend/prompt_engine/structural_identity.py#L120-L126)

```python
# Wave 5.5.10 — door variants (specific → generic).
"floor-to-ceiling sliding glass door",
"sliding glass door",
"floor-to-ceiling door",
"balcony door",
"patio door",
"sliding door",
```

The parser is fully door-aware. It just never receives a door string from the mini.

### 3. Runtime confirmation — log evidence

`backend/server_3.log` from 21 May 2026 19:54-20:04 contains the 3 V1 generations. Final clauses sent to gpt-image-1:

| Generation | Primary opening string in clause |
|---|---|
| Warm Modern (19:54:43) | `large floor-to-ceiling window` |
| Japandi (19:57:58) | `wide floor-to-ceiling window` |
| Nordic (19:59:58) | `large floor-to-ceiling window` |

All 3 runs: `present=True facts=6 token_chars≈423 source=vision_capture_v1`. **Word "sliding" never appears in any of the 3 runtime clauses.** Parser is doing exactly what it should — the upstream input is wrong.

### 4. Visual analysis confirms (user, 21 May ~18:04)

| Fact | Warm Modern | Japandi | Nordic | Score |
|---|---|---|---|---|
| Sliding door (floor-to-ceiling glass) | ⚠️ Hidden behind curtain, ambiguous | ❌ Mullioned window | ❌ Mullioned window | **0.5/3** |
| Black-framed glass partition | ✅ | ✅ | ✅ | **3/3** |
| Open kitchen visible (right side per user) | ❌ Console + lamps | ❌ Bench + vase | ❌ Armchair + window | **0/3** |
| **Total** | | | | **3.5/9** |

Threshold to validate Wave 5.5.10b was 5/9. Failed.

## Why "plafond gpt-image-1 / Option 1 post-process" was the wrong diagnosis

The session was about to pivot to an OpenCV edge composite post-process under the theory that gpt-image-1 was ignoring explicit prompt facts (sliding door, kitchen). The runtime log analysis disproves this: gpt-image-1 was **never told** about a sliding door. The chain failure is upstream.

## Proposed fix (Wave 5.5.10c) — NOT YET APPLIED

Extend the (1) Primary opening vocabulary in [backend/main.py:303-305](../backend/main.py#L303-L305) to include door variants, in the same priority order as the parser keyword list (specific → generic). Approximate diff:

```python
"(1) Primary opening — use 'floor-to-ceiling sliding glass door', "
"'sliding glass door', 'patio door', 'balcony door', 'french doors', "
"'floor-to-ceiling window', 'bay window', 'panoramic window', "
"'corner window', 'glazed wall', 'glazed facade', or 'picture window' "
"when it matches. ..."
```

**Cost:** ~70 chars in the vision prompt. Mini max_tokens=220 unaffected.

**Risk:** None to the Wave 5.5.6 byte-identity invariant on pure atmosphere switches — the change happens BEFORE the structural identity is materialized; once captured, V1/V2/V3 still receive the identical clause via the existing delegation in [composer_v2.py:786](../backend/prompt_engine/composer_v2.py#L786).

**Validation gate after applying:**
1. Re-generate 3 V1 (Warm Modern + Japandi + Nordic) on the same benchmark photo
2. Grep runtime clause for "sliding" — must be present
3. Visual score: sliding door fact ≥ 2.5/3 to confirm fix lands
4. Kitchen fact still ❌ → that's the secondary bug, handled separately

## Confirmed secondary bug — mini mirror-flips left/right

User confirmed 2026-05-21 20:14: the kitchen is on the **RIGHT** in the benchmark photo. All 3 V1 runs of 19:54–20:00 reported `open kitchen visible on the LEFT`. **H1 confirmed: mini systematically mirror-flips orientation.**

**Implications wider than kitchen:**
- The mini's prompt also asks it to "state the wall (left/right/back)" for the primary opening — that field is likely flipped too on every run (currently dropped by `render_clause` trim loop so we don't see it in the final clause, but the parser stores it).
- Glass partition's position field — same risk.
- This bug is **independent of the door vocab bug** but lives in the same vision-capture step. Fixing both together is natural since we're already editing the prompt at [main.py:300+].

**Proposed sub-fix (part of 5.5.10c):** add an explicit anchor in the vision prompt:

```
Use the photographer's viewpoint: 'left' means YOUR left as you look at the photo,
'right' means YOUR right. Do NOT use the room occupant's perspective.
```

Risk: if the mini was already using photographer-perspective (and somehow still got it wrong), this won't help — we'd need a programmatic mirror test (e.g. ask twice with the image flipped and reconcile). Start with the prompt anchor and re-test before escalating.

## Session recovery context

This diagnosis was completed in a session-recovery context after the previous Claude Code session (`9856408b-d026-45b8-ba47-e51659a6b1ad.jsonl`, started 11 May, crashed 21 May 18:09 at 1,735,605 tokens > 1M limit). The last action before the crash was the user attempting to share `backend/server_3.log` (this file) — the very evidence needed to diagnose the root cause. Recovered via JSONL replay + targeted log greps on 21 May 20:13.
