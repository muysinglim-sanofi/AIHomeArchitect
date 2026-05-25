# Vocabulary Lessons Registry

**Wave 5.5.23 — append-only documentation of empirical word/phrase risk per atmosphere×mode.**

Not a gate. Not auto-classifier. Just memory of what we've learned, organized by category. Append after each bench. Reference before each wave.

## How to use

Before adding/removing any word in a prompt or DNA file:
1. Search this doc for the word
2. Check observed risk in similar context
3. If found : use the empirical risk score
4. If not found : flag as "untested" in the wave planning template

Risk scale :
- **SAFE** : empirically demonstrated to NOT cause regression across ≥1 bench
- **LOW** : occasional minor regression (<1/9 across benches)
- **MEDIUM** : regression rate 1-2/9 across benches OR strong DNA conflict
- **HIGH** : ≥3/9 regression OR direct trap word (banned in user's specs)
- **CRITICAL** : known to break preservation reliably (rollback required)

---

## Nouns (objects)

| Token | Risk | Context | Evidence |
|---|---|---|---|
| `television` | MEDIUM (preserve) / LOW (creative) | Living room, geometry-anchored | Wave 5.5.19→22 : appears inconsistently despite multiple positive signals. Atmosphere-DNA blockers were main cause (Wave 5.5.22 audit) |
| `coffee table` | SAFE | Living room, anchored to seating footprint | Wave 5.5.19 : appears reliably when wording is "within the seating footprint" |
| `area rug` | SAFE | Living room, anchored "within seating footprint" | Wave 5.5.19 : not benched extensively but no observed regression |
| `sofa` | SAFE | Anywhere — already present in DNA realism_constraints | Long-standing, no regression |
| `vessel` | MEDIUM | DNA decor_language — competes with TV for wall focal area | Wave 5.5.21 dropped `"oversized ceramic vessel on floating oak shelf"` from warm_modern decor to free wall for TV |
| `fireplace` | SAFE | DNA — natural focal element | Long-standing, no regression. Coexists fine with TV after Wave 5.5.21-22 focal-wall edits |
| `console` | MEDIUM (preserve) | Indirect wall-invention vector — console needs wall to lean against | Wave 5.5.16 preserve bench : "console behind partition" was evidence of kitchen→sitting conversion |
| `curtains / window treatments` | SAFE | Anchored to window lines | Wave 5.5.19 : appears reliably with `"along window lines"` |
| `side lighting / lamp` | SAFE | Anchored to seating geometry | Wave 5.5.19 : appears reliably |
| `media presence` | LOW (creative only) | Replaces explicit `TV` in early Wave 5.5.16 to dodge focal-wall pressure | Worked safely but failed the actual TV-appearance goal (Wave 5.5.19 went back to explicit `television`) |
| `media wall` | CRITICAL | Banned vocabulary per user spec Wave 5.5.16 | Triggers wall invention to host the media wall. Never use |
| `mirror` | **MEDIUM/HIGH (preserve)** / LOW (creative) | User-locked 2026-05-25. Mirrors can behave visually like openings, create fake depth, simulate windows/walls, trigger spatial reinterpretation | **Preserve smoke bench MANDATORY before any mirror addition. NO EXCEPTIONS.** Must be anchored to existing vanity/wall geometry in DNA wording. If no vanity in source, no mirror added |

---

## Spatial / architectural adjectives

| Token | Risk | Context | Evidence |
|---|---|---|---|
| `airy` | CRITICAL | Banned per user spec Wave 5.5.16 | Triggers openness drift / wall removal |
| `expansive` | CRITICAL | Same | Same |
| `grand` | HIGH | Banned per user spec | Composition pressure |
| `open-plan` | HIGH | Banned per user spec | Triggers wall removal |
| `seamless flow` | HIGH | Banned per user spec | Cross-room bleed |
| `immersive` | HIGH | Banned per user spec | Spatial expansion |
| `gallery-like` | HIGH | Banned per user spec | Triggers focal-wall solving |
| `hospitality-grade` | CRITICAL | Banned per user spec Wave 5.5.15a | One of the 3 toxic phrases from Wave 4.2.5 INTERIOR_COMPLETENESS trap |
| `fully designed` | CRITICAL | Banned per user spec Wave 5.5.15a | Same trap origin |
| `fully equipped` | CRITICAL | Same | Same |

---

## Focal semantics

| Token | Risk | Context | Evidence |
|---|---|---|---|
| `focal wall` (positive) | MEDIUM | Allows the model to designate ONE wall as focal — but constrains options | Wave 5.5.21-22 : "fireplace, artwork, or a television" focal-wall expansion was needed to unblock TV |
| `single clear focal wall` | MEDIUM | Limits the room to ONE focal element | Same — restrictive but compatible with TV when listed as option |
| `focal point` | MEDIUM | Generic — atmosphere-dependent risk | Nordic: "fireplace or wood stove as focal point" → blocked TV until Wave 5.5.22 |
| `media wall` | CRITICAL | Triggers wall invention | Never use |
| `statement wall` | HIGH | Composition pressure | Similar trap to media wall |
| `feature wall` | HIGH | Same risk as statement wall | Same |

---

## Continuity semantics

| Token | Risk | Context | Evidence |
|---|---|---|---|
| `visible continuity` | MEDIUM | Wave 5.5.18 dna_room_context exposes `visible_transition_logic` (e.g. "oak floor continues into adjacent rooms") — helps with kitchen continuity but can extend furnishing into adjacent zones | Mixed bench results: helps cross-zone consistency, but risk of kitchen→sitting conversion when furnishing signal extends |
| `flow into adjacent` | MEDIUM | Same risk pattern | Same |
| `subtly inhabited` | LOW (preserve) | Wave 5.5.16 preserve mini-signal | Did not cause direct regression but did not produce visible improvement either |
| `functionally inhabited` | MEDIUM | "Functional" reads as completion pressure | Wave 5.5.16 trial : "functionally" replaced by "subtly" in V2 — reduced furniture-solving behavior |
| `into the kitchen / kitchen visibility` | MEDIUM | Helps preserve kitchen but can also push furnishing INTO kitchen | Wave 5.5.18 visible_transition_logic field |

---

## Negation patterns (suppression = high signal)

| Original negation | Effect when REMOVED | Evidence |
|---|---|---|
| `"not TV-facing row"` (warm_modern DNA) | Unblocks TV placement | Wave 5.5.20 fix #2 : removed → TV becomes consideratable |
| `"no visible TV above fireplace"` (soft_luxury negative_rules) | Unblocks TV near fireplace | Wave 5.5.22 fix : removed → TV placement above fireplace becomes possible |
| `"no TV directly facing bed"` (warm_modern master_bedroom) | Would allow TV in bedroom | NOT removed — bedroom signal doesn't include TV anyway |
| `"no TV in bedroom"` (japandi master_bedroom) | Would allow TV in Japandi bedroom | NOT removed — Japandi philosophy spare |
| Preserve-mode emotional signal (Wave 5.5.15d set to "") | Re-introduction risks 1+/9 walls | Wave 5.5.15d empirical : ANY non-empty preserve-mode signal touching surface/density costs walls |

**Key lesson : removing a negation can unblock as much (or more) than adding a positive instruction. Always log suppressions in wave planning.**

---

## Cross-cutting waves history

| Wave | Wording change | Risk predicted | Actual outcome | Lesson |
|---|---|---|---|---|
| 5.5.15b | `"lived-in micro-layering"` + 2 others | LOW | 3/9 walls | Surface-implying nouns trigger surface invention |
| 5.5.15c | `"soft shadow falloff, restrained imperfections"` (trim) | LOW | 1/9 walls | Even minimum signal causes walls in preserve |
| 5.5.15d | preserve signal → `""` | SAFE | 0/9 walls | Empty = baseline |
| 5.5.16 | `"a low coffee table or restrained side lighting where existing wall geometry naturally supports them"` | LOW | 2-3/10 walls (kitchen suppression) | Furnishing extension into adjacent zones requires walls |
| 5.5.18 | DNA dormant fields revival | LOW | Small TV improvement, no major regression | DNA-pre-existing wording is safer than newly-invented prompt content |
| 5.5.19 | `"and a television on existing wall geometry"` | MEDIUM | TV did NOT appear on Warm Modern / Soft Luxury | DNA conflicts blocked it; needed Wave 5.5.20-22 to unblock |
| 5.5.21-22 | DNA edits (focal wall accepts TV + drop blockers) | LOW | TV appearance still inconsistent | gpt-image-1 has inherent bias against TV in luxury imagery |
| **5.5.25 Bali fix #3+#4** | `"open side to garden or pool — pavilion character"` → `"where the photographed apartment shows an open side to garden or pool, preserve and emphasize that connection"` | LOW | **Complete perspective change** on Bali — apartment not recognizable | **ROLLED BACK.** Bali's pavilion identity is too deeply embedded across architectural_language + material_palette + visible_transition_logic. Softening one constraint isn't enough — the strong identity tokens elsewhere still drove full scene reframing. **Lesson : on atmospheres with strong architectural identity (pavilion, open-pavilion volumes), single-constraint softening insufficient ; need holistic identity restructure or atmosphere-specific approach.** |
| **5.5.25 Soft Luxury fix #5** | `"symmetry in furniture placement — not haphazard"` → `"considered furniture placement that respects the photographed layout"` | LOW | Wall added on right | **ROLLED BACK.** The symmetry mandate was indirectly providing architectural discipline. Removing it lost structural protection. **Lesson : composition mandates can serve double duty as architecture anchors. Dropping them entirely loses protection. Better : anchor to "where apartment allows" rather than dropping.** |
| 5.5.25 Tropical fix #1+#2 | `"open side to terrace or garden"` → conditional | LOW | OK | ✓ **KEPT.** Same wording pattern as Bali but worked on Tropical. Possibly because Tropical's atmosphere identity has fewer compound architectural directives in other fields. |

**Meta-lesson : pure prompt engineering has hit a ceiling for furniture deficit. Wave 5.5.17b competitor audit identified hybrid pipeline (segmentation + targeted inpainting) as the empirical path forward.**

---

---

## Reference Profile : Warm Modern preserve V1 (locked 2026-05-25)

**Empirical reference :** After cumulative tuning Wave 5.5.20 + 5.5.21 + 5.5.22, Warm Modern living_room preserve V1 consistently produces "perfect" renders : TV present, structure preserved, atmosphere identity intact, kitchen continuity respected.

User confirmed (2026-05-25) : 10/10 last preserve V1 generations on Warm Modern reach this quality bar. **Other atmospheres do not yet match this level.**

This is the empirical reference for what a TV-friendly + preserve-safe atmosphere looks like structurally.

### The 5-dimension profile

| Dimension | Warm Modern living_room current state | Why it works |
|---|---|---|
| `room_specific_constraints` | `"seating in conversation grouping"` + `"single clear focal wall — fireplace, artwork, or a television, not multiple"` | TV explicitly listed in focal options ; no anti-TV negation ; no symmetry mandate |
| `decor_language` | 1 item only : `"floor-length warm linen curtains"` | LEAN. No wall-competing decor (vessel was dropped Wave 5.5.21) ; curtains anchored to existing window |
| `negative_rules` | style-only : palette, hardware, matching suite, floating furniture | ZERO anti-furniture / anti-TV / anti-rug rules. Restrictions are stylistic not structural |
| `visible_transition_logic` | continuity wording : oak floor flows into adjacent rooms, brass echoes through visible kitchen / hallway | Continuity-friendly, not architectural-directive |
| `core.forbidden_elements` | stylistic : cold minimalism, sterile white, glossy marble overload, fake luxury gold, overdecorated | ZERO architectural forbidden (no "no open-plan" / "no pavilion") |

### Profile pattern summary

A TV-friendly + preserve-safe atmosphere DNA has :
1. Focal-wall constraint EXPLICITLY listing TV as an option
2. `decor_language` LEAN (1-2 items max, all anchored to existing geometry)
3. ZERO anti-TV / anti-rug / anti-furniture rules in `negative_rules`
4. `room_specific_constraints` = simple structural rules, NO composition mandates (no "symmetry", no "must center on X")
5. `core.forbidden_elements` = style-only, NO architectural directives

### Per-atmosphere alignment status (post Wave 5.5.26)

| Atm | Alignment | Gap | Effort to align | Risk |
|---|---|---|---|---|
| **warm_modern** | ✓ **REFERENCE** | (none — this IS the reference) | — | — |
| **nordic_warmth** | ✓ Aligned post Wave 5.5.22 | Minimal | — | LOW |
| **dark_contemporary** | ✓ Aligned post Wave 5.5.22 + 5.5.26 | Minimal — artwork removed from decor | — | LOW |
| **soft_luxury** | ⚠️ Partial | Symmetry mandate restant (post Wave 5.5.25 rollback). Need anchor "where apartment allows" instead of drop | Mineur, careful wording | MEDIUM (rollback once already) |
| **tropical_escape** | ⚠️ Partial | "open side" softened ✓ ; plant-focal mandate restant | Soften "plant as primary accent" | MEDIUM |
| **bali_sanctuary** | ❌ Major gap | Pavilion identity spread across architectural_language + material_palette + visible_transition_logic + room_specific_constraints. Single fix insufficient (rollback proved Wave 5.5.25) | Holistic redesign required | HIGH |
| **nature_retreat** | ⚠️ Partial | Bedroom "no technology visible" = identity (skip). Living mostly aligned | Living-only edits | LOW |
| **desert_luxe** | ⚠️ Partial | Density limit "max 2 decorative objects" too restrictive vs WM | Tunable density (Wave 5.5.29) | LOW |
| **japandi_calm** | n/a — anti-furnishing by identity | (do not align — identity protection) | — | — |
| **zen_retreat** | n/a — anti-furnishing by identity | (do not align — identity protection) | — | — |

### How to use as evaluation checklist

Before any future DNA edit on an atmosphere, evaluate against the 5-dimension profile :

```
For atmosphere X, living_room :
1. Does room_specific_constraints explicitly list TV as a focal option ?    [Y/N]
2. Is decor_language LEAN (1-2 items max, all geometry-anchored) ?           [Y/N]
3. Are negative_rules style-only (no anti-furniture rules) ?                 [Y/N]
4. Is room_specific_constraints free of composition mandates ?               [Y/N]
5. Is core.forbidden_elements style-only (no architectural directives) ?     [Y/N]
```

If all 5 = Y → atmosphere is WM-aligned, preserve-safe + TV-friendly profile
If any = N → identify gap, design surgical edit, bench gate per Wave 5.5.23 protocol

### Important caveat

Aligning to the WM reference profile means following the **structural pattern**, NOT copying WM's content. Each atmosphere keeps its own :
- Material palette (Soft Luxury = marble/cashmere, Dark Contemporary = charcoal/bronze, etc.)
- Color palette
- Texture vocabulary
- Decor character

The profile is about STRUCTURE of the DNA, not its AESTHETIC content.

---

## Appending new lessons

Template per entry :

```markdown
| `<token or phrase>` | <RISK> | <atmosphere/room/mode context> | <wave_id> : <observed outcome>. |
```

Always include :
- The wave ID where evidence was gathered
- The atmosphere×room×mode tested
- The OBSERVED outcome (not prediction)
