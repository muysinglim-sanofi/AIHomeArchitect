# Wave 5.5.40 — Atmosphere Consolidation & Product Simplification Audit

**Date :** 2026-05-25
**Type :** read-only audit (no code)
**Trigger :** Strategic pivot 2026-05-25 — reduce atmosphere fragmentation. Remove Bali Sanctuary + Zen Retreat (Phase 1). Re-evaluate Nordic Warmth + Desert Luxe later (Phase 2 deferred).

**Scope :** Impact analysis of removing Bali + Zen atmospheres from the engine.

**Wave numbering :** Renamed from Wave 5.5.31 to **Wave 5.5.40** to mark product architecture pivot vs iterative furnishing waves.

**Sequencing (user-locked) :**
```
1. Wave 5.5.40 (NOW)  — Consolidation audit (no code) ← this doc
2. Wave 5.5.32        — Bimodal leak fixes (Tropical + Nature + Soft Luxury, skip Bali)
3. Wave 5.5.41        — Bali Sanctuary removal implementation
4. Wave 5.5.42        — Zen Retreat removal implementation
5. Future re-evaluation — Nordic + Desert (Phase 2 decision)
```

**Warm Modern protection :** Untouched throughout. No semantic contamination.

---

## 1. Executive summary

**Total files affected by Bali + Zen removal :** 11 backend + 1 frontend + 6 asset files + ~17 test files (historical, mostly cosmetic).

**Code changes required :**
- 8 backend files with active references (mandatory edits)
- 1 backend file with regex pattern update (transformation_classifier)
- 1 frontend file (atmosphere_style.dart) — 2 entries to remove
- 6 asset files (jpg/png/ftue) to delete
- ~17 older test files (validate_wave*.py) — atmosphere lists, no functional impact

**Frontend/UX impact :**
- Atmosphere chooser UI : 10 cards → 8 cards
- Existing user sessions referencing Bali/Zen : need graceful handling
- "Surprise Me" recommender : 4 fewer candidates per room
- Marketing/SPEC docs : update from "10 atmospheres" to "8 atmospheres"

**Estimated effort :**
- Wave 5.5.41 (Bali removal) : ~1h code + 15 min bench validation
- Wave 5.5.42 (Zen removal) : ~1h code + 15 min bench validation
- Total : ~2-2.5h for both removals

**Risks :**
- LOW : Backend changes are surgical deletions, no logic changes
- MEDIUM : Frontend persisted state — existing users with Bali/Zen sessions need fallback
- LOW : Test files updates trivial (atmosphere list reduction)

---

## 2. Backend impact map

### 2.1 Atmosphere DNA registration

| File | Change | Risk |
|---|---|---|
| `atmosphere_dna/bali_sanctuary.py` | DELETE file (13 RoomAdaptationDNA entries + 1 AtmosphereCoreDNA) | None |
| `atmosphere_dna/zen_retreat.py` | DELETE file (13 entries + 1 core) | None |
| `atmosphere_dna/__init__.py` | Remove 2 import lines (lines 32 + 37) | None — fast-fail at module load if forgotten |
| `atmosphere_dna/bimodal_classifier.py` | Remove `_STRIPS["bali_sanctuary"]` + `_STRIPS["zen_retreat"]` entries + remove from `_EXPECTED_ATMOSPHERES` set | None — `_self_check()` validates set |
| `atmosphere_dna/_base.py` | Cosmetic : docstring example mentions Zen (line 180). Leave as historical comment. | None |

### 2.2 Atmosphere-aware engines

| File | What references | Change scope |
|---|---|---|
| `atmosphere_recommender.py` | 30+ entries : room weights (10 room types × 2 atms) + emotional_intent weights + keyword weights | Remove all entries with `"bali_sanctuary"` or `"zen_retreat"` keys |
| `emotional_realism.py` | Wave 5.5.15c per-atm dict has 2 entries to remove (bali_sanctuary + zen_retreat creative sentences) | Remove 2 dict entries |
| `dream_scene_completion.py` | `_ATMOSPHERE_QUALITY` dict has 2 entries | Remove 2 dict entries |
| `suggestion_engine.py` | 2 suggestion lists (zen_retreat at line 63, bali_sanctuary at line 123) | Remove 2 list entries |
| `architect_response.py` | Vocabulary dicts (zen at line 63, bali at line 118) + AI response phrases (zen at line 320-321) | Remove 2-4 dict/list entries |
| `style_dna.py` | LEGACY DNA (pre-atmosphere_dna). Bali StyleDNA at lines 80-218 + Zen StyleDNA at line 218+ | Remove 2 StyleDNA entries. **Note** : legacy system, may already be unused except as fallback |
| `transformation_classifier.py` | Regex pattern includes "zen" and "bali" as user-intent keywords (lines 41-43) | Remove `zen|` and `bali|` from regex alternations |
| `wow_layer.py` | Comments only (Bali V1 mention in historical doc-comments) | Leave (historical reference) |

### 2.3 Backend tests

| File | Change |
|---|---|
| `validate_wave5514b.py` | Atmosphere list (10 → 8) |
| `validate_wave5514g_margins.py` | `_ATMOSPHERES` list (10 → 8) |
| `validate_byteexact_5515b.py` | No atmosphere-specific reference (uses dynamic resolution) |
| Older `validate_wave*.py` (~15 files : wave25, wave34, wave341-343, wave41, wave421-440, wave450-462, wave479, wave481b, wave_conv_fix) | Atmosphere lists in test data — non-blocking, can update lazily |

### 2.4 Backend docs

| File | Action |
|---|---|
| `docs/PROMPT_FLOW_ANALYSIS.md` | Historical doc, leave |
| `docs/SIMPLIFICATION_AUDIT.md` | Historical doc, leave |
| `docs/WAVE_5_5_15a_*` to `WAVE_5_5_31_*` | Historical wave docs, leave (record of decisions) |

---

## 3. Frontend impact map

### 3.1 Code

| File | Change | Lines |
|---|---|---|
| `lib/core/models/atmosphere_style.dart` | Remove 2 `AtmosphereStyle(...)` entries (zen_retreat lines 83-94 + bali_sanctuary lines 95-106) | 24 lines |

### 3.2 Assets

| Asset | Action |
|---|---|
| `assets/atmospheres/zen_retreat.jpg` | DELETE |
| `assets/atmospheres/zen_retreat_icon.png` | DELETE |
| `assets/atmospheres/bali_sanctuary.jpg` | DELETE |
| `assets/atmospheres/bali_sanctuary_icon.png` | DELETE |
| `assets/atmospheres/ftue/ftue_zen_retreat.jpg` | DELETE |
| `assets/atmospheres/ftue/ftue_bali_sanctuary.jpg` | DELETE |

### 3.3 Frontend SPEC docs

| File | Action |
|---|---|
| `frontend/assets/atmospheres/SPEC.md` | Update atmosphere count + remove 2 entries |
| `frontend/assets/atmospheres/ftue/SPEC.md` | Update FTUE atmosphere count + remove 2 entries |

### 3.4 Session/history persisted state

**Risk : MEDIUM.** Frontend persists sessions to local storage. Existing user sessions may reference :
- `atmosphere_id = "bali_sanctuary"` or `"zen_retreat"` in `SessionState`
- `style_label = "Bali Sanctuary"` or `"Zen Retreat"` in chat history

**Mitigation options :**

A. **Graceful fallback** : if loaded session has unknown atmosphere_id, display as "Atmosphere (legacy)" or fallback to Warm Modern. Don't crash.

B. **One-shot migration** : on first app launch post-removal, scan session list and either delete sessions or auto-migrate to Warm Modern.

C. **No migration** : assume early-stage app, no real user data to worry about, sessions referencing removed atmospheres just fail to reload (acceptable).

**Recommended :** Option A (graceful fallback) — minimal effort, handles edge case cleanly.

---

## 4. Per-atmosphere removal detail

### 4.1 Bali Sanctuary — Wave 5.5.41

**Backend deletions :**
- `atmosphere_dna/bali_sanctuary.py` (entire file, 13 RoomAdaptationDNA + 1 core)
- 1 import in `__init__.py`
- 1 entry in `bimodal_classifier._STRIPS`
- 1 element in `bimodal_classifier._EXPECTED_ATMOSPHERES` frozenset
- ~10 entries in `atmosphere_recommender.py` (per-room weights × 8 rooms + emotional weights + keyword weights)
- 1 entry in `emotional_realism._EMOTIONAL_REALISM_CREATIVE_BY_ATM` dict
- 1 entry in `dream_scene_completion._ATMOSPHERE_QUALITY` dict
- 1 list entry in `suggestion_engine`
- 1 dict entry in `architect_response`
- 1 `StyleDNA` entry in `style_dna.py` (legacy)
- `"bali"` token in `transformation_classifier.py` regex (lines 41 + 43)

**Frontend deletions :**
- 1 `AtmosphereStyle(...)` entry in `atmosphere_style.dart` (lines 95-106)
- `bali_sanctuary.jpg` + `bali_sanctuary_icon.png` + `ftue_bali_sanctuary.jpg` assets
- SPEC.md updates

**Recommender impact :**
- Bali was scoring 0.35-0.90 across various intent categories
- After removal : those intents redistribute to remaining atmospheres
- Most affected : "tropical" / "vacation" / "spa" intents → would now route only to Tropical Escape (no Bali alternative)

### 4.2 Zen Retreat — Wave 5.5.42

**Backend deletions :**
- `atmosphere_dna/zen_retreat.py` (entire file)
- 1 import in `__init__.py`
- 1 entry in `bimodal_classifier._STRIPS`
- 1 element in `_EXPECTED_ATMOSPHERES`
- ~12 entries in `atmosphere_recommender.py`
- 1 entry in `emotional_realism` dict
- 1 entry in `dream_scene_completion` dict
- 1 list in `suggestion_engine`
- 1 dict entry + 1 AI response list in `architect_response`
- 1 `StyleDNA` entry in `style_dna.py`
- `"zen"` token in `transformation_classifier.py` regex

**Frontend deletions :**
- 1 `AtmosphereStyle(...)` entry (lines 83-94)
- `zen_retreat.jpg` + `zen_retreat_icon.png` + `ftue_zen_retreat.jpg` assets
- SPEC.md updates

**Recommender impact :**
- Zen was scoring high on "calm" / "minimal" / "spa" / "small spaces" intents
- After removal : those intents → Japandi Calm (similar profile, less anti-furnishing)
- This is actually a NET POSITIVE — Zen was anti-furnishing identity, Japandi is more livable

---

## 5. Quality/stability gains from simplification

### 5.1 Empirical evidence per atmosphere

| Removed atm | Latest bench evidence | Gain from removal |
|---|---|---|
| Bali | Wave 5.5.25 KO (full perspective change) | Eliminates the engine's worst preserve regressor. CRITICAL win. |
| Zen | Atmosphere-identity opt-out (per framework) | Removes 2 atmospheres × N benches × every future wave. Reduced maintenance significantly. |

### 5.2 Benchmark matrix simplification

| Metric | Before (10 atms) | After Phase 1 (8 atms) | Reduction |
|---|---|---|---|
| Full ship-gate bench | 10 atms × 3 photos × 2 modes × 3 cells = 180 cells | 8 × 3 × 2 × 3 = 144 cells | -20% |
| Standard bench | 3 atms × 3 cells = 9 | unchanged | 0% (3 picked from 8 vs 10) |
| Margin diagnostic | 10 × 3 modes = 30 cells | 24 cells | -20% |

### 5.3 Wave 5.5.31 leak audit impact

Wave 5.5.31 identified Bali as CRITICAL leak source. After Bali removal :
- CRITICAL leak ELIMINATED (no atmosphere → no leak)
- Wave 5.5.32 leak fix scope reduces : Tropical + Nature + Soft Luxury only (3 atms instead of 4)
- 1 less risk vector to monitor in future waves

### 5.4 Maintenance burden reduction

- DNA file count : 10 → 8
- bimodal_classifier strip table entries : 10 → 8
- atmosphere_recommender weight tables : 10 → 8 columns
- Future per-atm DNA edits : 20% less work per wave

---

## 6. Migration concerns + recommendations

### 6.1 Order of operations within Wave 5.5.41 / 5.5.42

Per atmosphere :

1. **Frontend first :** remove from `atmosphere_style.dart` + assets
2. **Backend second :** remove DNA file, imports, recommender entries, etc.

Rationale : if frontend goes first, backend still serves the atmosphere (no harm). If backend goes first, frontend tries to display an atmosphere that's no longer registered → crash on session load.

### 6.2 Graceful fallback for legacy sessions

Add to frontend `SessionState.fromJson` :
```dart
// If atmosphere_id not in current atmosphere registry, fallback to default
final atm = AtmosphereStyleRegistry.findById(json['atmosphere_id'])
  ?? AtmosphereStyleRegistry.findById('warm_modern');
```

OR add to `AtmosphereStyleRegistry.findById` :
```dart
static AtmosphereStyle? findById(String id) {
  // Legacy atmospheres fallback to warm_modern (Wave 5.5.41/42)
  if (id == 'bali_sanctuary' || id == 'zen_retreat') {
    return findById('warm_modern');
  }
  return allAtmospheres.firstWhereOrNull((a) => a.id == id);
}
```

Effort : ~5 min code addition.

### 6.3 Tests update strategy

- Update `validate_wave5514b.py` + `validate_wave5514g_margins.py` (active tests)
- Leave older `validate_wave*.py` (historical waves, atmosphere lists are stale by definition once those waves shipped)
- Add note in commit message about test update strategy

### 6.4 Memory notes

`wave_5_5a_calibration_matrix` in memory references Bali as "openness/depth reference atmosphere". After removal :
- Update memory note OR
- Leave (historical, documents pre-consolidation decision)

Recommended : update with note "Bali removed Wave 5.5.41 — openness reference no longer needed".

---

## 7. Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Frontend crash on legacy session load | MEDIUM | Graceful fallback in `findById` (Section 6.2) |
| Recommender returning empty results for "tropical" intent (no Bali alternative) | LOW | Tropical Escape covers those intents |
| User confusion from atmosphere reduction | LOW | Personal app, early stage, no public commitment to "10 atmospheres" |
| Test regression on update | LOW | Updated tests are atmosphere-list-only |
| Wave 5.5.32 leak fix complexity | MITIGATED | Bali was 1 of the 4 leaks ; after Bali removal, leak fix scope shrinks |
| Lost atmospheric diversity (Bali had unique pavilion character) | ACCEPTED | User strategic decision — overlap with Tropical |

---

## 8. Recommended execution order (post-audit)

### Step 1 — Wave 5.5.32 — Bimodal leak fixes (FIRST per user lock)

- Fix Tropical + Nature + Soft Luxury leaks per Wave 5.5.31 audit
- SKIP Bali (being removed in 5.5.41)
- SKIP Zen (atmosphere identity opt-out, being removed in 5.5.42)
- Cleaner engine before removing atmospheres

### Step 2 — Wave 5.5.41 — Bali Sanctuary removal

- Frontend first : remove from `atmosphere_style.dart` + assets + SPEC
- Add graceful fallback in `findById` for legacy sessions
- Backend second : DNA file + all references + tests update
- Bimodal regression test (151/151 → fewer, recompute baseline)
- Visual sanity check : Tropical bench (Bali's neighbor) still works correctly

### Step 3 — Wave 5.5.42 — Zen Retreat removal

- Same pattern as Wave 5.5.41
- Visual sanity check : Japandi bench (Zen's neighbor) still works

### Step 4 — Re-evaluation (deferred wave, no immediate)

- After living with simplified 8-atmosphere product for a while :
  - Does Nordic still feel necessary or merged-into-WM ?
  - Does Desert still feel unique or redundant with Soft Luxury / Nature ?
- Decision based on actual product feel, not just analysis

---

## 9. What this audit does NOT propose

- ❌ Removing atmospheres beyond Bali + Zen in this phase (Nordic + Desert deferred)
- ❌ Touching Warm Modern in any way (canonical reference, protected)
- ❌ Removing infrastructure files (only atmosphere-specific data)
- ❌ Breaking existing user sessions (graceful fallback proposed)
- ❌ Removing atmosphere_dna folder structure (just 2 of 10 files)
- ❌ Aggressive test update (historical validate_wave*.py left as-is)

## 10. What it DOES propose

- ✓ Wave 5.5.32 first (leak fixes), then 5.5.41 (Bali), then 5.5.42 (Zen)
- ✓ Frontend changes first, backend second (avoid crash window)
- ✓ Graceful fallback for legacy sessions referencing removed atmospheres
- ✓ Surgical deletions in 8 backend files + 1 frontend file + 6 asset files
- ✓ Test updates in 2 active validators
- ✓ Memory note update reflecting removal
- ✓ Wave 5.5.30 doc remains valid (10 canonical rules apply to remaining 8 atmospheres)
- ✓ Future re-evaluation of Nordic + Desert based on lived product experience

---

## 11. Effort summary

| Wave | Activity | Estimated effort |
|---|---|---|
| **5.5.40 (this)** | Audit | DONE (~30 min) |
| **5.5.32** | Bimodal leak fixes (Tropical + Nature + Soft Luxury) | ~45 min code + 30 min bench |
| **5.5.41** | Bali removal | ~1h code (FE+BE) + 15 min bench validation |
| **5.5.42** | Zen removal | ~1h code (FE+BE) + 15 min bench validation |
| **Total** | All 4 waves above | ~3.5-4h work + ~1h bench |

After all 4 waves : engine has 8 atmospheres, all leak-free, all WM-aligned (Warm Modern + 7 stylistic overlays). Wave 5.5.30 long-term migration sequence can resume in future if needed.
