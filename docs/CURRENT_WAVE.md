# Current Wave — Freeze Checkpoint: Stabilization Phase 4.2.x

> **Update this file at the start of each new wave.** It defines the active sprint scope, intent, and explicit exclusions.

---

## Wave Identity

| Field | Value |
|-------|-------|
| Checkpoint | Stabilization Freeze — Post Wave 4.2.7 |
| Status | **FROZEN — transition to Wave 4.3.0** |
| Date frozen | 2026-05-16 |
| All validators | PASSING (238 checks total, 0 failures) |

---

## What Is Now Frozen

The following modules are considered stable, validated, and frozen. Do not modify without explicit scope in a named wave.

| Module | File | Frozen since |
|--------|------|-------------|
| Generation profiles | `generation_profiles.py` | Wave 4.2.6 |
| Retry classifier | `retry_classifier.py` | Wave 4.2.7 |
| Intent classifier | `prompt_engine/intent_classifier.py` | Mini Wave (Conv Fix) |
| DEV/PROD routing | `main.py` profile selection | Wave 4.2.6 |
| Generation triggering | `main.py` retry loop + decision path | Wave 4.2.7 |
| Validation protocol | `docs/VALIDATION_PROTOCOL.md` | Wave 4.2.7+ |
| All Wave 3 systems | See `FREEZE_CONTRACT.md` | Wave 3 |

---

## Validated Wave History

| Wave | Name | Validator | Checks | Status |
|------|------|-----------|--------|--------|
| Wave 3 | DNA + Intelligence Systems | `validate_intelligence.py` | 130 entries | Complete |
| Wave 4.2.5 | Error Handling Overhaul | `validate_wave425.py` | 57 checks | **PASSING** |
| Wave 4.2.6 | DEV/PROD Profiles + Cost Protection | `validate_wave426.py` | 65 checks | **PASSING** |
| Wave 4.2.7 | Smart Retry System | `validate_wave427.py` | 63 checks | **PASSING** |
| Mini Wave | Conversation Orchestration Fix | `validate_wave_conv_fix.py` | 53 checks | **PASSING** |

**Total automated checks: 238. All passing.**

---

## Known Limitations (Active)

| ID | Summary | Status |
|----|---------|--------|
| L1 | Architectural identity preservation (topology rewrite during atmosphere switch) | Deferred → Wave 4.3.0 |
| L2 | DEV/PROD quality gap | By design |
| L3 | Interior completeness rule drops under budget pressure | By design |
| L4 | Reconciliation polling terminates at 90s | By design |

Full details: `backend/KNOWN_LIMITATIONS.md`

---

## Deferred Items (Confirmed — Do Not Touch in 4.3.0 Unless Scoped)

| Item | Assigned wave |
|------|--------------|
| Retry backoff / exponential delay | Wave 4.2.8 |
| UNCLASSIFIED exception monitoring hardening | Wave 4.2.8 |
| `OPENAI_NON_RETRYABLE` frontend error code | Wave 5.x |
| Advanced conversational UX polish | Wave 5.x |
| Full preservation intelligence | Wave 4.3.0 |
| Topology-aware architecture detection layer | Wave 4.3.0 |

---

## MVP Priority Hierarchy (Approved)

1. **Before/After Wow** — transformation impact, emotional reaction, premium realism
2. **Atmosphere Switching** — strict preservation of spatial identity and topology
3. **AI Companion Refinement** — controlled creativity through conversation

Full definition: `docs/VALIDATION_PROTOCOL.md` § 2

---

## Transition to Wave 4.3.0

Wave 4.3.0 is the next active wave. Its scope is **Preservation Intelligence**.

### What is now stable and trusted
- Backend routing, error handling, and retry logic
- DEV/PROD profile system and cost protection
- Intent classification and generation triggering
- Atmosphere DNA and prompt composition (frozen since Wave 3)
- Validation infrastructure and regression baselines

### What remains unsolved (Wave 4.3.0 focus)
- Structural anchor detection — the system has no explicit awareness of columns, archways, ceiling vaults, mezzanines, or unusual floor plans
- Priority arbitration — when atmosphere DNA conflicts with structural preservation, there are no explicit priority rules
- Topology continuity — atmosphere switches can rewrite room layout, especially for complex multi-zone spaces
- Per-room preservation contracts — current structural contract is universal, not room-type-aware

### Risks entering Wave 4.3.0
- Prompt budget is tight (3800 chars hard cap, FIRST_VISION already near 3250). Preservation enhancements must be budget-neutral or use conditional injection.
- Structural anchor detection changes the prompt engine, which touches frozen systems. Any `composer.py` modification requires careful justification against `FREEZE_CONTRACT.md`.
- Preservation improvements target Priority 2 (atmosphere switching) — they must not degrade Priority 1 (Before/After transformation quality). These are in tension.
- DEV mode renders will still degrade (by design). Do not evaluate preservation quality in DEV.

### Recommendations for Wave 4.3.0

1. Read `VALIDATION_PROTOCOL.md` section 2 (MVP hierarchy) before scoping. Preservation is Priority 2, not Priority 1.
2. Run 1 PROD smoke test for Before/After (Priority 1) before and after any preservation change to confirm transformation quality is not degraded.
3. Run 1 PROD atmosphere switch test (Priority 2) to evaluate preservation fidelity improvement.
4. Do not change prompt budgets or `_MAX_CHARS`. Work within the existing budget envelope.
5. Treat `FREEZE_CONTRACT.md` as authoritative. If `composer.py` must change, get explicit approval first.

---

## Wave History

| Wave | Name | Status |
|------|------|--------|
| Wave 1 | Core redesign pipeline | Complete |
| Wave 2 | Conversation + refinement memory | Complete |
| Wave 3 | DNA + Intelligence Systems | Complete and validated |
| Wave 2.5 | Architect Conversation Layer | Complete |
| Wave 4.2.5 | Error Handling Overhaul | Complete and validated |
| Wave 4.2.6 | DEV/PROD Profiles + Cost Protection | Complete and validated |
| Wave 4.2.7 | Smart Retry System | Complete and validated |
| Mini Wave | Conversation Orchestration Fix | Complete and validated |
| **Wave 4.3.0** | **Preservation Intelligence** | **NEXT** |
