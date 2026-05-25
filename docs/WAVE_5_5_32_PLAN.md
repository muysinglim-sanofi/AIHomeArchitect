# Wave 5.5.32 — Bimodal architecture leak fix (room context)

**Date :** 2026-05-25
**Lead :** muysi
**Branch :** wave-4.9.3
**Predecessor :** Wave 5.5.42 Zen Retreat removal (commit fe9c436)
**Audit reference :** Wave 5.5.31 audit (commit 8d8ba36)

## 1. Hypothesis

Two coupled fixes eliminate the `build_dna_room_context_signal` bypass identified in Wave 5.5.31 audit (the leak that killed Bali Sanctuary in Wave 5.5.25):

1. **Mechanism fix (gate)** — pipe the room-context signal through `apply_bimodal()` at all 3 call sites in `composer.py` so the strip mechanism actually applies to this section. Today it bypasses entirely.
2. **Content fix (strips)** — extend per-atmosphere `_STRIPS` to cover the architectural directives leaking through `room_specific_constraints` for Tropical Escape and Nature Retreat. Soft Luxury is in scope of the audit but its room_context content is dominantly material/furniture, no immediate strips needed.

## 2. Expected outcome

- `build_dna_room_context_signal()` output goes through `apply_bimodal()` in preserve mode
- Tropical Escape preserve: kitchen "open shelf mandatory — no upper cabinets to ceiling" and facade "louvred element visible — facade identity" tokens neutralised
- Nature Retreat preserve: living_room "single statement stone or timber wall", master_bedroom "clay plaster wall as composition", bathroom "single stone throughout — no tile mixing", pool_area "natural material deck only — no artificial surface" tokens neutralised
- Soft Luxury preserve: unchanged (no targeted strips this wave)
- Warm Modern preserve: **byte-identical** (no `_STRIPS` entry — gating is no-op)
- Bimodal regression: updated test counts (added strip tuples)

## 3. Decision rule

- Ship if : bimodal regression PASS + backend starts cleanly + Warm Modern preserve prompt byte-identical
- Rollback if : any preserve regression on Warm Modern (canonical) OR test failure unrelated to new strips

## 4. Bench tier

- Smoke regression check (bimodal validator + margin diagnostic)
- Visual bench RECOMMENDED post-wave : Tropical preserve × 3, Nature preserve × 3 on same source photo. Look for: wall invention, kitchen cabinetry alteration, facade material override.
- Warm Modern preserve × 3 to confirm canonical untouched.

## 5. Framework alignment

- Wave 5.5.31 audit explicitly identified `build_dna_room_context_signal` bypass as CRITICAL
- User-locked discipline 2026-05-25: Warm Modern protected (no contamination) — preserved because no _STRIPS entry exists for warm_modern
- Frontend untouched (backend-only wave)

## 6. Risk acknowledgement

- LOW (gate) : `apply_bimodal()` is a no-op for atmospheres with no _STRIPS entry. Warm Modern, Japandi Calm, Soft Luxury, Nordic Warmth pass through unchanged.
- MEDIUM (strips) : new strips may neutralise too aggressively; visual bench required post-wave to confirm Tropical/Nature still feel like themselves in preserve.
- LOW (regression) : added strip tuples increase test count but don't alter pass/fail of existing assertions.

## 7. Rollback plan

Single commit. `git revert HEAD` restores:
- The bypass (build_dna_room_context_signal no longer goes through apply_bimodal)
- The previous strip dict size for Tropical and Nature

Alternative finer rollback : remove specific strip tuples by edit-revert if a particular strip is over-aggressive.

## 8. Execution order

1. composer.py : wrap each `build_dna_room_context_signal(...)` call site (3 locations: lines 580, 627, 759) with `apply_bimodal(..., atmosphere_id, generation_mode)`.
2. bimodal_classifier.py _STRIPS : extend Tropical Escape entry with 2 new strips, extend Nature Retreat entry with 4 new strips.
3. validate_wave5514b : strip counts adjust automatically (printed metadata); add 2-3 assertion lines to verify new strips trigger on a rendered room_context block.
4. Run validators + restart backend + commit.

## 9. Post-implementation

- Visual bench when user has time (Tropical × 3 + Nature × 3 preserve; Warm Modern × 3 as control)
- If bench shows residual leaks, iterate by adding more strips (one bench round = one strip iteration)
- Soft Luxury can get the same treatment in a follow-up sub-wave if/when bench shows preserve issues there
