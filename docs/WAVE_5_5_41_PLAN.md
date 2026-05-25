# Wave 5.5.41 — Bali Sanctuary removal

**Date :** 2026-05-25
**Lead :** muysi
**Branch :** wave-4.9.3
**Predecessor :** Wave 5.5.40 audit (commit 6519a48)

## 1. Hypothesis

Removing Bali Sanctuary entirely from the engine eliminates the worst preserve-mode regressor (Wave 5.5.25 KO empirical evidence) without harming any of the 9 remaining atmospheres. The Wave 5.5.31 CRITICAL leak disappears with the atmosphere.

## 2. Expected outcome

- Atmosphere chooser : 10 → 9 atmospheres
- Backend DNA registry : 10 → 9 atmospheres
- `_EXPECTED_ATMOSPHERES` frozenset : 9 entries
- Bimodal regression : updated baseline (test count may change if test counts Bali-specific checks)
- Legacy sessions with `atmosphere_id="bali_sanctuary"` : graceful fallback to Warm Modern
- Bench any remaining atmosphere : no regression (Bali removal doesn't affect others)

## 3. Decision rule

- Ship if : bimodal regression PASS (151/151 → updated count) + backend starts cleanly + no broken imports
- Rollback if : any test failure unrelated to Bali removal, OR any preserve regression on remaining atmospheres

## 4. Bench tier

- Smoke regression check (bimodal validator + margin diagnostic)
- No new visual bench needed (Bali was the worst performer ; removing it can't degrade quality elsewhere)

## 5. Framework alignment

- Wave 5.5.40 audit recommended this removal
- Per discipline locked 2026-05-25 : Warm Modern protected (no contamination)
- Frontend-first / backend-second order per audit

## 6. Risk acknowledgement

- LOW : Bali was empirically the worst atmosphere (Wave 5.5.25 KO)
- MEDIUM : Legacy session graceful fallback must work (mitigation : findById fallback)
- LOW : Test updates trivial (atmosphere list reduction)

## 7. Rollback plan

Single commit. `git revert HEAD` restores instantly.

## 8. Execution order (per Wave 5.5.40 audit Section 6.1)

1. Frontend FIRST :
   - Remove `AtmosphereStyle(...)` for `bali_sanctuary` in `atmosphere_style.dart`
   - Add graceful fallback in `findById` (legacy session safety)
   - Delete 3 asset files (jpg + icon + ftue)
   - Update SPEC.md files
2. Backend SECOND :
   - Delete `bali_sanctuary.py`
   - Remove from `__init__.py` import
   - Remove from `_STRIPS` + `_EXPECTED_ATMOSPHERES` in `bimodal_classifier.py`
   - Remove ~10 entries from `atmosphere_recommender.py`
   - Remove from `emotional_realism._EMOTIONAL_REALISM_CREATIVE_BY_ATM`
   - Remove from `dream_scene_completion._ATMOSPHERE_QUALITY`
   - Remove suggestion_engine entry
   - Remove architect_response vocabulary entry
   - Remove `Bali Sanctuary` StyleDNA from `style_dna.py` (legacy)
   - Remove `bali` from `transformation_classifier.py` regex
3. Tests : update `validate_wave5514g_margins.py` + `validate_wave5514b.py` atmosphere lists
4. Validations : bimodal regression + margin check
5. Restart backend
6. Commit

## 9. Post-implementation

- Wave 5.5.42 Zen removal next (same pattern)
- Wave 5.5.32 leak fix : reduced scope (Tropical + Nature + Soft Luxury, no Bali)
- Future re-evaluation : Nordic + Desert (Phase 2)
