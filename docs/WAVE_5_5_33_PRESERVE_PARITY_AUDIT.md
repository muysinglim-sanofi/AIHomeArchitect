# Wave 5.5.33 — Preserve Parity Audit (living_room)

**Date :** 2026-05-25
**Type :** read-only audit (no code)
**Trigger :** Systematic visual bench 2026-05-25 across 8 atmospheres preserve mode living_room. Result: Warm Modern PERFECT (canonical), all 7 others have at least one structural regression and/or missing TV anchor. User confirms not a regression — first systematic check — and locks the requirement "WM parity for all".

**Scope :** 7 non-WM atmospheres × living_room only × preserve mode. Audit derives the WM canonical profile and diffs each non-WM atmosphere against it on 5 measurable axes. Outputs a remediation matrix and suggested wave sequence.

**Out of scope :** other rooms (bedroom, kitchen, bathroom, etc.), creative mode behavior, generation infrastructure.

---

## 1. Bench observations (2026-05-25)

| Atmosphere | TV | Baie vitrée | Coin cuisine | Wall added | Other |
|---|:-:|:-:|:-:|:-:|---|
| Warm Modern (ref) | ✓ | ✓ | ✓ | – | – |
| Tropical Escape | ✗ | ✗ | ✗ | – | – |
| Japandi Calm | ✗ | – | – | ✗ left at baie | – |
| Soft Luxury | ✗ | – | ✗ | ✗ right | – |
| Nordic Warmth | (not benched) | (not benched) | (not benched) | – | – |
| Dark Contemporary | ✗ | – | ✗ | ✗ left at baie | trop sombre |
| Nature Retreat | ✗ | – | ✗ | – | fenêtre fond supprimée |
| Desert Luxe | (not benched) | (not benched) | (not benched) | – | – |

→ Warm Modern is the **only atmosphere passing all preserve axes**.

---

## 2. Method

Compare each non-WM atmosphere's `RoomAdaptationDNA` for `living_room` against the WM canonical profile across 5 axes :

1. **TV anchor presence** in `room_specific_constraints` (the field that drives focal-wall semantics)
2. **Anti-wall pressure** — tokens that explicitly or implicitly push the model to alter walls
3. **Kitchen visibility signal** in `visible_transition_logic` (the field that primes the model to keep the visible kitchen frame)
4. **Window preservation hint** — anything in the DNA that protects the baie vitrée from being narrowed/replaced
5. **Luminosity floor** in `lighting_behavior` — does the DNA permit too-dark renders ?

For each axis, the gate is :
- **PASS** = WM-equivalent (or better) signal present
- **WEAK** = signal present but underweighted (conditional / qualifier / competing clause)
- **MISSING** = no signal at all
- **PRESSURE** = signal actively pushes against preserve

---

## 3. Canonical reference profile — Warm Modern living_room

```python
room_specific_constraints=[
    "seating in conversation grouping",
    "single clear focal wall — fireplace, artwork, or a television, not multiple"
]
visible_transition_logic=(
    "oak floor and warm plaster continue into adjacent rooms; "
    "brass accents echo through visible kitchen or hallway"
)
realism_constraints=[
    "sofa at residential scale — not model-set proportions",
    "furniture legs visible and grounded on floor"
]
lighting_behavior=(
    "Concealed ceiling cove + tungsten-glow table lamps; warm evening tone."
)
material_palette=[
    "wide-plank European oak floor",
    "warm sand plaster walls",
    "travertine slab surfaces"
]
```

**Why WM works** :
- `room_specific_constraints[1]` carries the TV anchor in **slot 0** of focal options ("fireplace, artwork, or a television"), is **unconditional**, and **caps focal count** ("not multiple"). Model has explicit permission + clear constraint.
- `room_specific_constraints[0]` is **furniture-only** ("seating in conversation grouping") — no architectural push.
- `visible_transition_logic` explicitly mentions **"visible kitchen or hallway"** — primes model to keep the kitchen frame.
- `realism_constraints` are **furniture-only** (scale, legs).
- `lighting_behavior` is **warm but not dark** ("warm evening tone" — not "by glow not flood").
- `material_palette` describes **existing surfaces** (floor, walls, surfaces) — no "accent wall" or "feature wall" addition.

→ WM = bulletproof because its DNA is **already de-architecturalized**. No `_STRIPS` entry needed.

---

## 4. Per-atmosphere matrix

### 4.1 Tropical Escape — living_room

| Axis | State | Diff vs WM |
|---|---|---|
| TV anchor | **MISSING** | `room_specific_constraints` = ["where the photographed apartment shows an open side to terrace or garden, preserve and emphasize that opening", "plant as living room's primary accent — one large specimen"]. No TV. |
| Anti-wall | **PRESSURE (low)** | "open side to terrace" is conditional but suggests opening pressure. `visible_transition_logic` references terrace continuity (assumes terrace exists). |
| Kitchen visibility | **MISSING** | `visible_transition_logic` = "white walls and concrete floor continue into terrace; rattan furniture palette echoes outdoor seating". Mentions terrace only, no kitchen. |
| Window preservation | **MISSING** | No explicit window anchor; "open side" semantics may push wall opening. |
| Luminosity floor | **PASS** | "Warm rattan pendant + concealed warm ceiling slot; bright in day, warm in evening." |

**Bench effects** : ✗ TV missing, ✗ baie vitrée altered, ✗ kitchen missing. Aligns with audit findings.

**Remediation** :
1. Add TV to `room_specific_constraints` : insert "single clear focal wall — fireplace, plant, or a television, not multiple" (mirrors WM structure, swaps "artwork" for atmosphere-coherent "plant").
2. Rewrite `visible_transition_logic` to include kitchen mention : "white walls and concrete floor continue into adjacent rooms; rattan accents echo through visible kitchen or terrace if present".
3. Keep "open side" constraint as conditional (already softened Wave 5.5.25) but move to slot [1] so TV anchor takes [0].

---

### 4.2 Japandi Calm — living_room

| Axis | State | Diff vs WM |
|---|---|---|
| TV anchor | **MISSING** | `room_specific_constraints` = ["maximum 3 decorative objects in room", "solid neutral rug or no rug — no pattern"]. No TV. |
| Anti-wall | **WEAK** | `realism_constraints` "empty floor space is deliberate, not absent" → stripped by Wave 5.5.14b (preserve mode). But user bench shows wall ADDED — possibly model interpreting "negative space" semantics from philosophy/architectural_language. |
| Kitchen visibility | **PASS** | "ceramic palette echoes through visible kitchen". |
| Window preservation | **MISSING** | No anchor. |
| Luminosity floor | **PASS** | "Paper lantern pendant + concealed warm floor slot; no harsh downlights." |

**Bench effects** : ✗ TV missing, ✗ wall added left at baie vitrée.

**Remediation** :
1. Add TV to `room_specific_constraints` : "single clear focal wall — fireplace, artwork, or a television, not multiple" (WM-identical wording — works for Japandi minimal-art aesthetic).
2. Investigate wall addition cause : likely upstream from `core.architectural_language` ("deliberate negative space in clean residential volumes") emitted via `inject_creative_revival` in creative mode — but user bench was preserve, so check whether dormant fields leak through `build_dna_room_context_signal`. Currently `core.architectural_language` is NOT in `room_specific_constraints` or `visible_transition_logic`, so the leak path isn't via Wave 5.5.18. Hypothesis : "wabi-sabi plaster walls" in `material_palette` is rendered as a material substitution directive that the model interprets as "redo the walls" — but this is `build_dna_block` content, gated by `apply_bimodal`, with no strip. **Investigation needed before remediation.**
3. Already has kitchen continuity ✓ — no change.

---

### 4.3 Soft Luxury — living_room

| Axis | State | Diff vs WM |
|---|---|---|
| TV anchor | **PASS** | `room_specific_constraints` = ["seating centred on focal element — fireplace, art wall, or a television", "symmetry in furniture placement — not haphazard"]. TV anchor in slot [0]. |
| Anti-wall | **PRESSURE** | "symmetry in furniture placement — not haphazard" → model may interpret as "make the right wall mirror the left" → wall addition. Confirmed by Wave 5.5.25 rollback (dropping symmetry caused wall added, restoring symmetry caused wall added too — symmetry is load-bearing AND leaky). |
| Kitchen visibility | **MISSING** | `visible_transition_logic` = "ivory plaster walls and marble floor flow continuously into dining and hallway; brass accents echo across visible rooms". Mentions dining + hallway, no kitchen. |
| Window preservation | **MISSING** | No anchor. |
| Luminosity floor | **PASS** | "Concealed perimeter cove + silk shade floor lamps; warm evening tone, no ceiling spotlights." |

**Bench effects** : ✗ TV missing (despite anchor present), ✗ wall added right, ✗ kitchen missing.

**TV emission mystery** : anchor exists in slot [0], yet model didn't emit TV. Hypothesis : the "symmetry in furniture placement" in slot [1] reinforces a fireplace-centric classical setup which the model defaults to. The anchor "fireplace, art wall, or a television" gives 3 options ; "symmetry" tips the model toward the most classically symmetric (fireplace) instead of TV.

**Remediation** :
1. Strengthen TV anchor : change to "single clear focal wall — fireplace, art wall, or a television, not multiple" (add "not multiple" cap like WM, force a choice).
2. Resolve symmetry paradox : replace "symmetry in furniture placement — not haphazard" with "balanced furniture placement — not haphazard" (drops the wall-symmetry pressure, keeps the discipline).
3. Add kitchen to `visible_transition_logic` : "...flow continuously into dining, hallway, or visible kitchen if present...".

---

### 4.4 Nordic Warmth — living_room

| Axis | State | Diff vs WM |
|---|---|---|
| TV anchor | **WEAK** | `room_specific_constraints` = ["layered rugs permitted — wool flatweave under pile", "fireplace, wood stove, or a television as focal point if present"]. TV anchor exists but "if present" qualifier weakens it ; model may interpret as "skip if not photographed". |
| Anti-wall | **PASS** | No architectural pressure in DNA. |
| Kitchen visibility | **PASS** | "pine floor and warm white plaster continue into kitchen". |
| Window preservation | **MISSING** | No anchor. |
| Luminosity floor | **WEAK** | "Amber floor lamp behind sofa + hanging filament bulb pendant; candle-warm, no ceiling wash." — "no ceiling wash" might over-darken on small windows. |

**Bench effects** : not benched in 2026-05-25 round. Audit predicts TV emission inconsistency due to "if present" qualifier.

**Remediation** :
1. Strengthen TV anchor : change to "single clear focal wall — fireplace, wood stove, or a television, not multiple" (drop "if present", mirror WM cap).

---

### 4.5 Dark Contemporary — living_room

| Axis | State | Diff vs WM |
|---|---|---|
| TV anchor | **PASS** | `room_specific_constraints` = ["artwork or a television as single focal wall — not gallery cluster", "balanced dark-to-warm lighting ratio — not pure darkness"]. TV in slot [0], capped. |
| Anti-wall | **PRESSURE** | "single focal wall" phrasing may be interpreted as "the wall I will treat as feature" → wall material change (charcoal plaster + smoked oak). |
| Kitchen visibility | **MISSING** | `visible_transition_logic` mentions dining, no kitchen. |
| Window preservation | **MISSING** | No anchor. |
| Luminosity floor | **PRESSURE** | "room lit by glow, not flood" — too aggressive. User reports "trop sombre, on voit quasiment rien". The slot [1] constraint "balanced dark-to-warm lighting ratio — not pure darkness" tries to mitigate but isn't strong enough. |

**Bench effects** : ✗ TV missing (despite strong anchor), ✗ wall added left, ✗ kitchen missing, ✗ too dark.

**TV emission mystery** : anchor in slot [0], strong wording, yet model didn't emit TV. Hypothesis : overwhelming dark atmosphere directive ("darkness as design element" in core, "room lit by glow, not flood" in room) prioritizes mood over content. Model goes minimal-content + dramatic-light.

**Remediation** :
1. Add luminosity floor : change `lighting_behavior` to "Concealed warm ceiling cove + sculptural bronze floor lamp; warm glow with maintained visual readability — not pure darkness."
2. Strengthen `room_specific_constraints` luminosity clause : move "balanced dark-to-warm lighting ratio — not pure darkness" from slot [1] to dual emphasis : "artwork or a television as single focal wall — not gallery cluster; maintain natural daylight from windows + balanced warm interior glow — not pure darkness".
3. Add kitchen to `visible_transition_logic` : "...continue into adjacent rooms; bronze accents echo through visible kitchen or dining area".

---

### 4.6 Nature Retreat — living_room

| Axis | State | Diff vs WM |
|---|---|---|
| TV anchor | **MISSING** | `room_specific_constraints` = ["single statement stone or timber accent" (post-Wave 5.5.32 strip), "planting: maximum 2 large statement plants"]. No TV. |
| Anti-wall | **PRESSURE (mitigated)** | Original "single statement stone or timber wall — not all four walls" stripped to "accent" by Wave 5.5.32. But `material_palette` still includes "rough-cut stone accent wall" → directly directs wall material addition. |
| Kitchen visibility | **MISSING** | `visible_transition_logic` mentions dining, no kitchen. |
| Window preservation | **MISSING** | No anchor. `realism_constraints` "stone wall texture visible" may push background changes including window obstruction. |
| Luminosity floor | **PASS** | "Warm concealed cove above stone wall + timber-shaded floor lamp". |

**Bench effects** : ✗ TV missing, ✗ kitchen missing, ✗ back window deleted.

**Window deletion hypothesis** : "stone wall texture visible — not flat CGI" + `material_palette` "rough-cut stone accent wall" → model adds a stone wall, displacing the window in the process. Wave 5.5.32 stripped the `room_specific_constraints` push but left `material_palette` pressure intact.

**Remediation** :
1. Add TV : change `room_specific_constraints[0]` from "single statement stone or timber accent" to "single clear focal wall — stone, timber, or a television, not multiple".
2. Remove wall material directive : change `material_palette[2]` from "rough-cut stone accent wall" to "rough-cut stone accents on existing surfaces" (no "accent wall" noun).
3. Drop `realism_constraints[1]` "stone wall texture visible — not flat CGI" — too ambiguous, contributes to window deletion. Replace with "stone or timber texture on existing surfaces — not flat CGI".
4. Add kitchen to `visible_transition_logic`.

---

### 4.7 Desert Luxe — living_room

| Axis | State | Diff vs WM |
|---|---|---|
| TV anchor | **MISSING** | `room_specific_constraints` = ["no pattern on walls — tadelakt is the texture", "maximum 2 decorative objects in room"]. No TV. |
| Anti-wall | **PRESSURE** | "no pattern on walls — tadelakt is the texture" implies tadelakt should cover existing walls (material override). `material_palette` "tadelakt plaster walls in terracotta or warm sand" reinforces. |
| Kitchen visibility | **WEAK** | `visible_transition_logic` = "tadelakt floor and plaster walls continue into adjacent rooms; warm sand palette unbroken through visible spaces" — generic "adjacent rooms" + "visible spaces", no explicit kitchen. |
| Window preservation | **MISSING** | No anchor. |
| Luminosity floor | **PASS** | "Single hammered brass pendant + concealed warm floor slot; low-angled warm glow." |

**Bench effects** : not benched in 2026-05-25 round. Audit predicts TV missing + possible material wall override.

**Remediation** :
1. Add TV : change `room_specific_constraints[0]` from "no pattern on walls — tadelakt is the texture" to "single clear focal wall — sandstone niche, artwork, or a television, not multiple". Move "no pattern on walls" to `negative_rules`.
2. Soften material override : change `material_palette[1]` from "tadelakt plaster walls in terracotta or warm sand" to "tadelakt or warm plaster wall finish in terracotta or warm sand".
3. Add explicit kitchen to `visible_transition_logic`.

---

## 5. Remediation summary matrix

| Atmosphere | Add TV | Fix wall pressure | Add kitchen | Fix lighting | Notes |
|---|:-:|:-:|:-:|:-:|---|
| Tropical | ✓ | – | ✓ | – | TV in slot [0] |
| Japandi | ✓ | ❓ investigate | – | – | Wall cause unclear before TV add |
| Soft Luxury | ✓ (strengthen) | ✓ symmetry→balanced | ✓ | – | TV emission paradox to resolve |
| Nordic | ✓ (strengthen, drop "if present") | – | – | – | Smallest change |
| Dark Contemp | ✓ (strengthen) | ✓ | ✓ | ✓ luminosity floor | Largest change |
| Nature | ✓ | ✓ material_palette + realism | ✓ | – | Window deletion mitigated |
| Desert | ✓ | ✓ tadelakt→finish | ✓ | – | Untested in bench |

**Standardized TV anchor wording** (target for all 7) :
```
"single clear focal wall — <atmosphere-coherent option 1>, <option 2>, or a television, not multiple"
```

Where `<options>` are atmosphere-coherent choices :
- Tropical : `fireplace, plant`
- Japandi : `fireplace, artwork`
- Soft Luxury : `fireplace, art wall`
- Nordic : `fireplace, wood stove`
- Dark Contemp : `artwork, fireplace`
- Nature : `stone, timber accent`
- Desert : `sandstone niche, artwork`

**Standardized kitchen continuity wording** (target for atmospheres lacking it) :
Insert "through visible kitchen" or "into visible kitchen if present" alongside the atmosphere's natural continuity narrative.

---

## 6. Gate criteria

A remediation is shippable when, for the target atmosphere :

1. **TV anchor** : `room_specific_constraints[0]` includes "or a television" with "not multiple" cap, WM-pattern wording.
2. **Anti-wall** : no token in `room_specific_constraints`, `material_palette`, or `realism_constraints` that names a "wall" / "feature wall" / "accent wall" as something to ADD (existing-surface references only).
3. **Kitchen visibility** : `visible_transition_logic` mentions "kitchen" or "visible kitchen".
4. **Bench evidence** : preserve mode × 3 generations on the canonical bench photo shows TV present in ≥ 2/3 + zero wall addition + kitchen visible in ≥ 2/3.
5. **Cross-atmosphere control** : Warm Modern preserve × 3 on same photo remains perfect (no regression of canonical).

---

## 7. Wave sequence (locked 2026-05-25 with user)

Smallest-change-first to validate the WM-parity pattern on the easiest case before tackling the messy ones. Order updated per user direction 2026-05-25.

1. **Wave 5.5.34 — Nordic Warmth parity** : single edit (drop "if present" qualifier, add "not multiple"). Bench × 3. If TV reliably emits → pattern validated.

2. **Wave 5.5.35 — Tropical Escape parity** : add TV anchor, fix kitchen continuity, keep "open side" conditional. Bench × 3.
   - **Strategic context** : post-Bali removal, Tropical is the new tropical canonical profile. Higher visibility than initially scoped.

3. **Wave 5.5.36 — Soft Luxury parity** (promoted from slot 4) : strengthen TV anchor (resolve emission paradox), replace symmetry → balanced, fix kitchen. Bench × 3.
   - **Insight to document** : "symmetry as implicit structural stabilizer". Wave 5.5.25 history showed both dropping AND keeping symmetry caused wall regressions. Replace strategy must preserve the structural discipline function while removing the wall-symmetry interpretation pressure. This is the most subtle remediation in the audit.
   - **Priority** : high. Soft Luxury is a top product/business profile.

4. **Wave 5.5.37 — Nature Retreat parity** : add TV anchor, remove `material_palette` wall directive, soften `realism_constraints`. Bench × 3.
   - **ROI** : Nature is currently the closest atmosphere to WM post-bench. Three targeted edits (TV + rough-cut stone wall pressure + kitchen continuity) likely stabilize it rapidly.

5. **Wave 5.5.38 — Dark Contemporary parity** (deeper repositioning than initial scope) : NOT just lighting floor. Concept-level rewrite.
   - **Reduce** : "darkness as design element" framing (core.lighting_behavior) — the concept itself overwhelms architectural readability.
   - **Increase** : "cinematic warmth" emphasis (core + room).
   - **Preserve** : minimum architecture readability floor.
   - **Keep** : mood. Drop : black-room interpretation.
   - **Specific edits** : core.lighting_behavior, core.philosophy ("darkness as design element"), room.lighting_behavior ("room lit by glow, not flood"), strengthen TV anchor positioning, add kitchen continuity.
   - **Bench × 3 control even stricter** : readability of architecture must be confirmed.

6. **Wave 5.5.39 — Japandi Calm parity** (LAST in active sequence) : prudence maximale.
   - **Investigate first** : why does Japandi push wall reinterpretation ? Japandi is philosophically the most opposed to "better inhabited" — "negative space as design", "deliberate emptiness" semantics may be doing the work. Investigation prerequisite before any DNA edit.
   - **Then** : add TV anchor (only if investigation confirms no upstream cause that the TV anchor wouldn't conflict with).
   - **Mandatory prerequisite** : investigation memo or code-trace showing the wall-addition root cause before any DNA edit ships.

7. **Wave 5.5.40b — Desert Luxe parity** : **DEFERRED**. Pending final decision on Desert removal (Phase 2 closed C, but kept open as low-investment optional). Status options :
   - **A. Minimal maintenance only** : just the TV anchor add (single low-risk edit) so users testing Desert get the same TV behavior as the rest.
   - **B. Full skip** : no remediation work, accept that Desert is the weakest preserve atmosphere until product-level decision changes.
   - **Default** : B (skip) unless bench evidence shows Desert is non-trivially used.

**Why this order** : Nordic + Tropical = predominantly "ADD" remediations (low risk). Soft Luxury (high priority + symmetry insight) + Nature (high ROI) follow. Dark Contemp = deeper concept rewrite (largest change). Japandi = investigation required before edit. Desert = deferred.

Between each wave : **MANDATORY** preserve bench × 3 of the touched atmosphere + Warm Modern × 3 control before merging. Warm Modern is the canonical invariant — zero modifications across the entire sequence.

---

## 8. Risk acknowledgement

- **HIGH** : Each remediation touches living_room DNA — a load-bearing field. Per past wave history (5.5.25 Soft Luxury rollback), even seemingly innocuous changes (dropping "symmetry mandate") have caused regressions.
- **MEDIUM** : TV anchor wording standardization is theoretically safe (WM pattern proven) but model may interpret differently when the atmosphere mood is at odds (e.g. Dark Contemp luminosity).
- **LOW** : Kitchen continuity additions are pure additive, unlikely to cause regression.
- **LOW** : Wave 5.5.32 leak fix mechanism (gate + strips) remains active and benefits all 7 atmospheres going forward.

---

## 9. What this audit does NOT propose

- ❌ Touching Warm Modern (canonical reference, protected).
- ❌ Remediations for other rooms (bedroom, kitchen, bathroom, etc.) — out of scope, deferred to a future audit if bench shows non-living-room issues.
- ❌ Removing more atmospheres — Phase 2 closed by user decision 2026-05-25 (8-atmosphere lineup is final).
- ❌ Touching `bimodal_classifier._STRIPS` — Wave 5.5.32 work stands.
- ❌ Frontend changes — backend-only remediations.

---

## 10. Acceptance criteria for the audit itself

This audit is complete when :
- ✓ 7 atmospheres × living_room analyzed against WM canonical
- ✓ Per-atmosphere remediation list specified with concrete DNA edits
- ✓ Standardized TV anchor + kitchen continuity wording derived
- ✓ Wave execution sequence proposed with risk-graded order
- ✓ Gate criteria for shippable remediations defined
- ✓ User reviews and approves wave sequence before implementation begins
