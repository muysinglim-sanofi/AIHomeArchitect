# Wave 5.5.42 — Zen Retreat removal

**Date :** 2026-05-25
**Lead :** muysi
**Branch :** wave-4.9.3
**Predecessor :** Wave 5.5.41 Bali Sanctuary removal (commit f207a10)

## 1. Hypothesis

Removing Zen Retreat (per Wave 5.5.40 audit recommendation, Phase 1 second target) eliminates a second weak atmosphere whose minimalist DNA overlaps with Japandi Calm. Goes from 9 → 8 atmospheres, same surgical pattern as Wave 5.5.41.

## 2. Expected outcome

- Atmosphere chooser : 9 → 8 atmospheres
- Backend DNA registry : 9 → 8 atmospheres
- `_EXPECTED_ATMOSPHERES` frozenset : 8 entries
- Bimodal regression : updated baseline (test count reduces because Zen had per-atmosphere strips coverage)
- Legacy sessions with `atmosphere_id="zen_retreat"` : graceful fallback to Warm Modern via `_LEGACY_ALIASES`
- Bench any remaining atmosphere : no regression (Zen removal doesn't affect others)

## 3. Decision rule

- Ship if : bimodal regression PASS + backend starts cleanly + no broken imports
- Rollback if : any test failure unrelated to Zen removal, OR any preserve regression on remaining atmospheres

## 4. Bench tier

- Smoke regression check (bimodal validator + margin diagnostic)
- No new visual bench needed (Zen overlapped with Japandi ; removing it can't degrade Japandi quality)

## 5. Framework alignment

- Wave 5.5.40 audit recommended Zen removal alongside Bali (Phase 1)
- Per discipline locked 2026-05-25 : Warm Modern protected (no contamination)
- Frontend-first / backend-second order per audit
- Legacy alias safety added in Wave 5.5.41 `_LEGACY_ALIASES` extended

## 6. Risk acknowledgement

- LOW : Zen overlapped with Japandi (DNA matrix flagged "HIGH-priority target" in Wave 5.5a)
- MEDIUM : Legacy session graceful fallback (mitigation : `_LEGACY_ALIASES["zen_retreat"] = "warm_modern"`)
- LOW : Test updates trivial (atmosphere list reduction + 1 case removal)
- MEDIUM : `transformation_classifier.py:256` has special-case `if atmosphere_id == "zen_retreat":` — needs careful review

## 7. Rollback plan

Single commit. `git revert HEAD` restores instantly.

## 8. Execution order (mirroring Wave 5.5.41)

1. Frontend FIRST :
   - Remove `AtmosphereStyle(id: 'zen_retreat')` in `atmosphere_style.dart`
   - Delete asset files (jpg + icon + ftue)
   - Update SPEC.md files (counts 9 → 8)
2. Backend SECOND :
   - Delete `zen_retreat.py`
   - Remove from `__init__.py` import
   - Remove from `_STRIPS` + `_EXPECTED_ATMOSPHERES` in `bimodal_classifier.py`
   - Remove ~14 entries from `atmosphere_recommender.py`
   - Remove from `emotional_realism`, `dream_scene_completion`, `suggestion_engine`
   - Remove from `architect_response.py` (4 dicts)
   - Remove from `style_dna.py` if present
   - Remove from `transformation_classifier.py` regex AND special-case at line 256
   - Remove from `intent_classifier.py`, `refinement_authority.py` regexes
   - Remove from `prompt_budget_analyzer.py`
   - Add `_LEGACY_ALIASES["zen_retreat"] = "warm_modern"` in `_base.py`
3. Tests :
   - Update `validate_wave5514g_margins.py` atmosphere list (remove "Zen Retreat")
   - Update `validate_wave5514b.py` cases (remove zen_retreat) + idempotency count (9 → 8)
4. Validations : bimodal regression + margin check
5. Restart backend
6. Commit

## 9. Post-implementation

- Future re-evaluation : Nordic + Desert (Phase 2)
- Wave 5.5.32 leak fix still deferred (per Wave 5.5.41 user choice)
- 8-atmosphere chooser : Tropical / Warm Modern / Japandi / Soft Luxury / Nordic / Dark Contemporary / Nature / Desert
