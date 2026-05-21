# Wave 5.2 — Backend Prompt Architecture Re-Clean Audit

**Scope:** Full composer + preservation-layer architecture review.
**Mode:** Audit only — no code changes.
**Freeze status:** All frozen modules read only, never modified.

---

## 0. Methodology

Static reading of the current frozen `composer.py` + every layer-builder it imports + the post-4.5.0 additions (which the Wave 4.5.0 SIMPLIFICATION_AUDIT didn't yet exist to evaluate). Citations are line-level. No code modified.

---

## 1. Current architecture map (FIRST_VISION, V1)

15 sections enter the FV budget (~3550 chars):

| # | Section | Priority | Typical size | Role | Added |
|---|---|---|---|---|---|
| 1 | task | P1 | ~165–250 | "SAME APARTMENT PHOTO-EDIT" mental anchor (`fidelity_layer.build_first_vision_task`) | 4.3.3 / 4.6.1 reword |
| 2 | full_contract | P1 | ~820 | Tier 1.5 — CAMERA LOCK / STRUCTURAL LOCK / CHANGE ONLY / ATMOSPHERE BOUNDARY (`preservation.build_simplified_fv_contract`) | 4.5.0 simplified |
| 3 | **openings_anchor** | P1 | ~197 | "Openings fidelity" reinforcement | **4.6.2** |
| 4 | **structural_identity** | P1 | up to ~360 | Persistent per-apartment facts | **4.7.2** |
| 5 | **structural_negative_anchors** | P1 | ~280 | "Openings/glass are NOT walls" topology rule | **4.7.4** |
| 6 | **architectural_anchors** | P1 | 0–185 | Anchor-detector regex output | **4.7.1 R1** |
| 7 | source_space | P1 | empty in FV since 4.6.1 | (legacy slot) | 4.6.1 removed |
| 8 | design_intel (DNA) | P2 | ~823–996 | Atmosphere creative intelligence | 4.1 / 4.2 |
| 9 | interior_completeness | P5 | ~298 | "Never sparse" rule | 4.2.5 |
| 10 | scene_completion | P4 | ~280–380 (non-DNA only) | "COMPLETE THE SCENE" furniture list | 4.2.3 |
| 11 | wow_directive | P4 | ~326 | Restyling transformation ambition | 4.3.1 / 4.5.1 reword |
| 12 | **natural_enrichment** | P4 | ~217 | Light natural-decor signal | **4.6.2** |
| 13 | visible_spaces | P5 | 0–200 | Secondary visible room palette | 4.x |
| 14 | design_direction | P5 | 0–300 | User free-text instruction | 4.x |
| 15 | compact_realism | P3 | ~133 | Anti-CGI floor | 4.2.x |

**STYLE_REFINEMENT (V2+)** adds three more P1/P1.5 sections: `source_continuity` (4.7.3), `atmosphere_contract` (with TOPOLOGY LOCKED, 4.3.0), `authorized_user_changes` (P1.5, 4.7.5).

**Total V1 P1 preservation/structure stack:** **6 distinct sections** (excluding the now-empty source_space slot).

---

## 2. Fragility diagnosis

The architecture has become layer-cake-heavy specifically in the preservation tier. Five of the six P1 preservation sections were added **after** the Wave 4.5.0 simplification (4.6.2 openings_anchor, 4.7.1 architectural_anchors, 4.7.2 structural_identity, 4.7.4 structural_negative_anchors, 4.7.5 authorized_user_changes for V2+). Each was a defensive patch for a specific observed failure — bay-window normalisation, multi-zone collapse, partition wall-up, etc. The Wave 4.5.0 savings (~730 chars on the contract) have been more than re-spent.

The system now reads to the model as **6 voices simultaneously insisting "preserve openings/geometry"** — but in the failure cases the user just demonstrated (rear-room window erased, sliding door narrowed across both Japandi and Warm Modern), **none of the six voices points specifically at the lost element**. This is the fragility: defensive sections that are individually correct but collectively dilute attention without enumerating what to defend.

---

## 3. Redundancy / dilution analysis

Concept-repetition map for the V1 P1 stack (chars are typical):

| Concept | Mentions | Sections | Total chars carrying it |
|---|---:|---|---:|
| "SAME APARTMENT / this exact apartment" | 4–5 | task, contract, structural_identity prefix, wow_directive (P4) | ~80 |
| "preserve openings" | 6 | task, contract STRUCTURAL LOCK, openings_anchor (entire), structural_identity (when partition captured), structural_negative_anchors, architectural_anchors (when detected) | ~350 |
| "do not redesign / restructure / compartmentalise" | 5 | task, contract (×2), structural_negative_anchors, wow_directive | ~180 |
| "camera locked" | 2 | task, contract | ~75 |
| "geometry locked / reproduce exactly" | 3 | task, contract, structural_identity | ~110 |
| "change only materials/lighting/atmosphere" | 3 | task, contract (CHANGE ONLY), DNA (ATMOSPHERE STYLE) | ~110 |

The Wave 4.5.2 PROMPT_FLOW_ANALYSIS already measured ~500–600 chars (~18%) repetition before the 4.6/4.7 layers were added. With the new sections it is plausibly **~900–1100 chars of conceptual repetition (≈30–35% of the V1 stack)** for the openings-preservation concept alone.

**The honest answer to "does repetition strengthen or dilute":** at modest scale (2 voices) it reinforces; at this scale (6 voices) it dilutes. Models do not weight a concept linearly with number of restatements — they often weight the **most specific** mention. When no mention specifically enumerates "the sliding door + rear-room window," the abstract repetition becomes prompt noise.

---

## 4. True non-negotiable architectural contract (minimal core)

| Truth | Why non-negotiable | Where it should live |
|---|---|---|
| Same physical apartment | Mental anchor for the entire generation | Opening 1 sentence |
| Camera + perspective + horizon fixed | Without it, model recomposes | Core contract |
| Every photographed opening (windows, sliding doors, balcony access, partitions, archways, **including those visible through partitions in adjacent zones**) is structural, **enumerated when captured** | Specific enumeration > generic preservation text | Source-facts section |
| Spatial depth, multi-zone visibility, open-plan continuity | Cannot be re-introduced once collapsed | Source-facts section |
| Geometry / proportions / wall positions / ceiling height | Pixel-level via mask + text-level via contract | Core contract |
| Allowed-change perimeter (materials, lighting, furniture, decor, atmosphere) | One positive statement is stronger than six negative ones | Core contract |

**That is six bullets, expressible in ~500–600 chars of one coherent CORE block.** The current FV stack carries the same content across ~1850 chars of P1 sections.

---

## 5. What is NOT core (the style/quality layer)

| Layer | Role | Belongs to |
|---|---|---|
| atmosphere DNA materials + lighting + AVOID rules | Atmosphere character | Style layer (keep richness) |
| atmosphere DNA furniture lists | Risk (composition authority on "restyle existing") | Style layer (already flagged in 4.5.2 audit) |
| wow_directive / transformation ambition | Quality target signal | Style layer (one line is enough) |
| interior_completeness | Anti-sparse safety | Style layer (or merge into realism) |
| natural_enrichment | Light decor hint | Style layer (small, optional) |
| compact_realism | Anti-CGI / photographic vocabulary | Quality floor (one short block, untouchable) |
| design_direction / refinement_memory / authorized_user_changes | User intent | User layer (separate from preservation) |
| scene_completion (non-DNA path) | Fallback only | Quality floor (rarely fires) |

The current architecture **interleaves** these with preservation, instead of cleanly **stacking** them. The model has to constantly switch between *"do not change geometry"* and *"use bouclé sofa in ivory"* — the cross-talk between layers may be part of why DNA furniture lists pull toward composition authority.

---

## 6. Complexity-growth timeline

| Wave | Change to FV prompt complexity | Sign |
|---|---|---|
| 4.5.0 (May 2026) | Contract Tier 1 (~1550) → Tier 1.5 (~820) | **−730 chars** |
| 4.6.1 | SOURCE_SPACE removed from FV prompt | −200 |
| 4.6.2 | + openings_anchor (~197) + natural_enrichment (~217) | **+414** |
| 4.7.1 R1 | + architectural_anchors (0–185) | **+0 to +185** |
| 4.7.2 | + structural_identity clause (up to ~360) | **+up to 360** |
| 4.7.4 | + structural_negative_anchors (~280) | **+280** |
| 4.7.5 | + authorized_user_changes (P1.5, V2+ only) | (V2+) +variable |

Net since 4.5.0 simplification: **+~800 chars on the V1 P1 preservation stack** — more than the original simplification's savings. Every addition is independently justifiable (each plugged a measured failure) but the cumulative effect is the dilution this audit is examining.

---

## 7. Maintainability assessment

- **composer.py is 1264 lines and frozen.** The freeze itself is a maintainability signal: the system became reluctant to evolve.
- 15 named sections × 4 EditMode paths × per-path priority arbitration × per-priority drop ordering. Reasoning about *"what does the model actually see for a Japandi V2 refinement on a complex apartment"* requires tracing through ~6 modules.
- The `_SECTION_PRIORITY` table mixes preservation P1, source-fact P1, atmosphere P2, realism P3, ambition P4, niceties P5 — there is no clean hierarchy by **concept** (preservation / source / style / quality / user), only by drop-order.
- Adding the next defensive layer (e.g., the Wave 5.1c `open_continuity` field) makes this worse, not better — and the user explicitly named this as the worry.

**Verdict: the architecture is at the maintainability ceiling. Adding one more layer is the wrong move.**

---

## 8. Recommended simplification strategy

Three principles:

1. **Stack by concept, not by patch.** ONE preservation/contract block (combining task + contract + negative-anchors + openings text); ONE source-facts block (combining structural_identity + architectural_anchors + openings_anchor specifics); ONE style block (DNA + wow line); ONE quality block (compact_realism); ONE user block (direction / refinement). Five conceptually-named sections instead of fifteen patch-named ones.
2. **Specificity over repetition.** Replace 6 voices saying *"preserve openings"* with ONE block that enumerates the captured openings — including rear-zone ones. The Wave 5.1b finding (rear-zone openings not captured) folds in cleanly here: it's the SOURCE-FACTS block's job to capture everything.
3. **Same content, half the surface.** Net target: ~2200–2400 chars for V1 (was ~2900), with stronger specificity. The mask + input_fidelity + DNA are unchanged. The reduction comes from removing repetition, not from removing content.

---

## 9. Composer_v2 — is it needed?

| Option | Pros | Cons | Risk |
|---|---|---|---|
| A. Keep current + simplify in place | Smallest delta | composer.py is FROZEN — every simplification is a freeze touch; impossible to A/B compare | High (no rollback) |
| B. Partial refactor | Targets the worst layers | Still touches frozen code; partial refactor = worst of both worlds | High |
| **C. composer_v2 behind feature flag (recommended)** | Frozen composer.py NEVER modified — stays as the rollback baseline. Clean rebuild can be done freely. APP_ENV / runtime flag toggles which composer runs. A/B benchmark on the same photos. Ship only after benchmark proves equivalence-or-better. | One-time freeze exception needed for: adding the flag dispatch in main.py + adding the new module. The exception is narrow (no edit to composer.py itself). | **Low if disciplined** — full rollback is literally a flag flip |
| D. Rollback to pre-4.6.x baseline | Smallest code | Loses real preservation gains from 4.6.2 / 4.7.x — would re-introduce the bay-window-normalisation and multi-zone-collapse failures those patches were correctly designed for | High |

**Recommendation: Option C — composer_v2 behind feature flag.** It is the only option that respects the freeze contract while enabling a clean rebuild and provable A/B comparison. The freeze exception scope is **additive only** (new file + flag dispatch); the frozen composer.py stays as the immutable safety baseline.

---

## 10. Proposed minimal clean architecture (concept only)

```
[1] CORE SPATIAL CONTRACT — ~550–650 chars, P1, NEVER DROPS
    SAME APARTMENT PHOTO-EDIT. Camera + perspective + horizon frozen.
    Geometry + proportions + ceiling height + wall positions frozen.
    Every photographed opening (windows, doors, partitions, archways,
    open passages, openings visible through partitions into adjacent
    zones) is structural — never converted into a wall, never narrowed,
    never enclosed. Multi-zone visibility, open-plan continuity, and
    spatial depth are structural. CHANGE ONLY: surfaces, materials,
    furniture, lighting, textiles, decor, atmosphere.

[2] SOURCE ARCHITECTURAL FACTS — ~50–400 chars, P1, ONLY when facts present
    Concrete enumeration of THIS apartment's anchors (from
    structural_identity + anchor_detector + openings detection + the
    new rear-zone-openings capture from Wave 5.1c's investigation).
    When empty, omitted entirely.

[3] STYLE TRANSFORMATION — ~900 chars, P2
    Atmosphere DNA (materials + lighting + AVOID) + a single 60-char
    "transformation ambition" line. DNA furniture lists prefixed with
    "restyle existing elements as — not place new pieces" or similar
    to reduce composition-authority pull (the 4.5.2 audit's flagged
    tension).

[4] QUALITY FLOOR — ~133 chars, P3
    compact_realism unchanged.

[5] USER DIRECTION — 0–400 chars, P4
    design_direction (V1) + refinement_memory + authorized_user_changes
    (V2+) merged into one coherent block.

Total V1 typical: ~2100–2400 chars (vs current ~2900).
Lower budget pressure → no section drops → fewer retries.
```

**Five logical sections, conceptually named, mapping 1:1 to the user's mental model.** Adding a future layer means picking which section it belongs in, not creating a sixth section.

---

## 11. Safe rebuild roadmap

| Step | Deliverable | Risk gate |
|---|---|---|
| 1 | **Golden test set** — 5 photos: simple living room (1 window) / complex apartment (sliding door + balcony + partition + visible rear zone, like the user's failing photo) / open-plan kitchen-living / minimalist already-closed room / facade. 5 atmospheres each = 25 generations | none |
| 2 | **Baseline benchmark** — run current composer.py on all 25 with BENCHMARK_PROTOCOL scoring (A/B/C/D/E composite). Document baseline scores per (photo, atmosphere) | none |
| 3 | **composer_v2.py** — clean implementation of the 5-section architecture (Section 10). composer.py untouched. Initial: V1 path only | code-write only |
| 4 | **Feature flag dispatch** — main.py reads `COMPOSER_VERSION` env var; `v1` (default) → existing composer; `v2` → composer_v2. One-line dispatch, frozen composer.py never modified | freeze exception (narrow: new file + flag dispatch) |
| 5 | **Benchmark composer_v2** — same 25 generations under `COMPOSER_VERSION=v2`. **Must match or exceed baseline composite on every (photo, atmosphere) pair.** If any pair regresses, root-cause and iterate composer_v2 only | gate before any default flip |
| 6 | **Implement SR + STRUCTURAL paths in composer_v2** + re-benchmark V2+ refinements. Same gate | gate |
| 7 | **Default flip** — make `v2` the default; `v1` stays as a flag-flip rollback for one full release cycle | reversible in <60 s |
| 8 | **Decommission composer.py** — only after one cycle of `v2` PROD stability. Removed in a separate atomic commit so it's restorable | last step |
| 9 | **Document the complexity budget** — once decommissioned, the new architectural rule: any new layer must justify its addition by showing it's not expressible inside an existing block. Prevents re-accumulation | discipline |

---

## 12. What must remain sacred (do not touch)

| Item | Why |
|---|---|
| `input_fidelity=high` (PROD profile) | 4.5.2 audit: "strongest single preservation signal" |
| `quality=high` (PROD profile) | 4.5.2 audit: primary quality |
| Aspect-ratio output size detection | Room proportion preservation |
| Structural mask (PROD profile) | Only orthogonal-to-text preservation |
| `max_retries=0` SDK | Prevents 9× retry storms |
| Atmosphere DNA material + lighting language | The product's creative IP |
| compact_realism block | Anti-CGI floor — already tiny + load-bearing |
| `structural_identity` capture mechanism (the dataclass + token round-trip) | Wave 4.7.2's apartment-fact persistence is correct |
| `anchor_detector` regex outputs | They feed the SOURCE FACTS block — keep |
| The frozen composer.py file itself | Stays as the rollback baseline through the whole composer_v2 transition |

---

## 13. Final recommendation

The architecture has crossed the maintainability ceiling — six P1 preservation voices repeating the same concept while none of them enumerates the specific elements that are being lost (Wave 5.1b's finding). Adding the Wave 5.1c layers as planned (open_continuity + secondary_zone_openings) is the **right content** but the **wrong shape**: it adds another patch to an architecture already strained.

**The correct next move is Wave 5.2 — Composer V2 (clean rebuild behind feature flag).** It folds the Wave 5.1c content into Section 2 (SOURCE FACTS) of a 5-section clean architecture, while removing the redundant 4.6.2 / 4.7.1 / 4.7.4 separate sections by absorbing their concepts into the unified CORE CONTRACT and SOURCE FACTS blocks. Same protection, half the surface, single conceptual hierarchy, fully reversible via a flag flip.

**Do not** add Wave 5.1c as a new layer to the current composer. **Do not** patch Japandi DNA. **Do** scope Wave 5.2 = composer_v2 + golden benchmark set, with a narrow freeze exception only for the flag dispatch and new module file (the frozen composer.py is never edited).

*Audit complete. No code modified.*
