"""
Modular prompt composer — assembles the final generation prompt.

ROUTING LOGIC:
  Vision 1 (iteration == 1) → full redesign path
  Vision 2+ with LOCAL_EDIT intent  → targeted edit path (no style DNA)
  Vision 2+ with STYLE_REFINEMENT   → compact refinement path
  Vision 2+ with STRUCTURAL_TRANSFORM → structural evolution path

Wave 4.2.1 — CONDITIONING COMPRESSION:

  Problem: STYLE_REFINEMENT prompt was ~4397 chars before DNA/source/realism were added.
  Budget is 3800. DNA, refinement memory, and realism block were fully truncated.
  The model received 3800 chars of geometry-preservation constraints and near-zero
  creative instruction — causing both visual failure and probable server-side timeout.

  Solution: three-tier structural contract system + mode-specific realism tier.

  FIRST_VISION:           full contract (~1288 chars) + full realism (~995 chars)
  STYLE_REFINEMENT:       continuation contract (~375 chars) + compact realism (~130 chars)
  STRUCTURAL_TRANSFORM:   evolution contract (~719 chars) + compact realism (~130 chars)
  LOCAL_EDIT:             edit intent block + compact realism (~130 chars)

  Per-section audit logging is emitted at DEBUG level on every call.

Wave 4.2.4 — PROMPT COMPRESSION + STABLE DREAM RICHNESS:

  Replaces blind character-boundary truncation with a priority-based budget system.
  Hard budgets per mode (chars):
    FIRST_VISION:              3200
    STYLE_REFINEMENT:          2400
    STRUCTURAL_TRANSFORMATION: 2500
    LOCAL_EDIT:                1500

Wave 4.7.5 — LOCALIZED AUTHORIZED CHANGES (refinement authority, prompt-only):

  The 4.7.1–4.7.4 structural stack became strong enough that explicit user
  refinements ("turn the rear area into a bedroom") were under-applied. Adds a
  concise P1.5 "authorized_user_changes" section to V2 (Path B) and V3 (Path C)
  only — NOT V1. Ordered AFTER the structural P1 anchors and BEFORE atmosphere/
  design_intel: GLOBAL STRUCTURE LOCK + LOCAL USER AUTHORITY. It grants local
  precedence over atmosphere/furniture/decor/room-function defaults and demands
  the change be visibly present, while explicitly keeping openings/bay window/
  facade/perspective/identity fixed unless the user requested changing them
  (consistent with structural_identity's V3 clause + negative anchors, which
  forbid UNREQUESTED walls only). Priority 1 -> never trimmed (Task 15). ""
  for V1 / pure-atmosphere / empty request -> filtered (zero regression).
  LOCAL_EDIT (Path A) already carries explicit visible-change authority via
  build_local_edit_prompt and is intentionally left unchanged.

Wave 4.7.4 — STRUCTURAL NEGATIVE ANCHORS (no-new-wall topology, prompt-only):

  Positive preservation alone left ~30% randomness: the model still walls-off
  the bay window / compartmentalises the open facade / converts glass continuity
  into decorative wall planes (worse under wall-symmetry atmospheres). Adds a
  concise P1 "structural_negative_anchors" section to V1 (Path D), V2 (Path B)
  and V3 (Path C): concrete "this is open glass, NOT a wall; do not insert walls
  / compartmentalize; atmosphere adapts to architecture, do not restructure the
  facade for symmetry". Derived ONLY from the persistent identity
  (structural_identity.render_negative_anchors) — architecture-only, leak-guarded,
  ≤450 chars, "" (filtered) when no identity. Reinforces (never contradicts) the
  positive structural_identity/openings anchors. No runtime/OpenAI change.

Wave 4.7.3 — ARCHITECTURAL STATE CONTINUITY & VERSION SOURCE SELECTION:

  State/source-selection wave (no runtime/OpenAI change). The visual/design
  source for V2+ is now the LATEST generated vision (design continuity), while
  the original apartment + structural_identity remain the separate, authoritative
  architectural truth (injected as text). A concise P1 "source_continuity" clause
  is added to V2 (Path B) and V3 (Path C) only: "continue from current design,
  preserve its layout/furniture unless explicitly changed; original structural
  identity authoritative for windows/openings/partitions/depth". V1 (Path D) is
  unchanged (always edits the original). source_continuity defaults "" -> section
  filtered -> zero regression when absent.

Wave 4.7.2 — PERSISTENT STRUCTURAL IDENTITY (architecture-driven, not runtime):

  Wave 4.7.1 R1 depended on room_description, which mobile_mvp_baseline disables
  for V1 (vision_analysis_fv=False) — so concrete anchoring was INERT on the
  tested path. 4.7.2 introduces a persistent ApartmentStructuralIdentity captured
  ONCE (at V1 / session creation; never per-generation), persisted via a
  client round-trip token (same pattern as history / original_image_url), and
  injected as a P1 "structural_identity" declarative-facts section into V1
  (Path D), V2 (Path B) and V3 (Path C). Same identity reused across all modes;
  V3's renderer permits change only for the explicitly requested structural edit.
  Provider-agnostic: structural_identity.py has no model/SDK imports; the one
  capture (runtime layer) feeds short text through the same deterministic parser.
  structural_identity defaults to "" -> section filtered -> zero regression when
  absent. Task-6 leak guard drops any non-architectural (atmosphere/decor/
  furniture/emotional) candidate fact.

Wave 4.7.1 — STRUCTURAL FIDELITY STABILIZATION (R1 + R2, prompt-only):

  No runtime/OpenAI features. Reduces structural variance in V1 via the prompt
  architecture only.

  R1 — image-specific structural anchors in FIRST_VISION:
    detect_anchors(room_description) (the same deterministic, no-ML detector V2
    already uses) is wired into Path D as a P1 "architectural_anchors" section,
    placed right after openings_anchor. Descriptive-only, architecture-only,
    <=185 chars, empty when no description → zero cost. V1 is no longer LESS
    spatially anchored than V2.

  R2 — unify DNA / non-DNA fidelity policy:
    (a) Non-DNA FIRST_VISION completeness="" (was build_interior_completeness_rule()).
        Removes "never sparse / every functional zone completed" spatial-completion
        authority absent from the DNA path.
    (b) _style_block drops the specific "Furniture — <piece>" segment (composition
        authority) and restyles existing elements via material vocabulary only —
        mirroring the Wave 4.6.0 DNA decision. Same image+atmosphere now yields
        consistent structural behaviour regardless of DNA registration.

  Out of scope (deferred by explicit instruction): R3/R4/R5/R6, Tasks 3/4/5/6/7.

Wave 4.6.2 — OPENINGS FIDELITY + NATURAL DECORATION PASS:

  Micro-calibration only. Wave 4.6.1 philosophy is correct and preserved.

  Problem 1: openings still being normalized.
    Model treats bay windows as "design decisions" even with CAMERA LOCK +
    STRUCTURAL LOCK. Root cause: those constraints address camera and structural
    elements broadly; opening proportions receive implicit creative latitude.
    Fix: build_openings_anchor() (P1, ~197 chars) — explicit photographed-fact framing.
    Injected at P1 immediately after full_contract in FIRST_VISION.

  Problem 2: outputs under-decorated after Wave 4.6.1 removed composition authority.
    Missing TV, sparse accessory layering, low hospitality feel.
    Fix: build_natural_enrichment() (P4, ~217 chars) — light secondary decor signal.
    Strict rule: secondary to architecture, enriches without recomposing.
    No sofa grouping, no furniture arrangement, no composition directives.

  Preserved: all Wave 4.6.1 foundations (source="", PHOTO-EDIT task, pure-material
  DNA, photo_edit_wow, structural mask, input_fidelity=high, quality=high).

Wave 4.6.1 — FIRST_VISION PHOTO-EDIT REFOCUS:

  Problem: SOURCE_SPACE text summary reinterprets the room BEFORE generation,
  destroying fidelity ("Two large floor-to-ceiling windows" misses bay opening,
  partition, diagonal depth). DNA furniture_language still contained furniture
  object references at Wave 4.6.0 level ("seating", "armchair frame", "bed").

  Changes:
  1. SOURCE_SPACE removed from FIRST_VISION Path D — source="" for all FV calls.
     input_fidelity=high + image upload makes the image the source of truth.
     Vision analysis text summaries simplify/reinterpret rooms, contradicting photo-first.
  2. All 10 DNA files — living_room + master_bedroom furniture_language changed
     from material/texture with furniture objects ("on curved seating", "on armchair")
     to pure material/texture/atmosphere language with zero furniture object references.
     "bouclé upholstery on curved seating" → "warm bouclé in ivory — plush tactile richness"
  3. build_photo_edit_wow_directive() replaces build_restyling_wow_directive() in Path D.
     "furniture styling" signal removed; "photo edit" framing makes operation explicit.
  4. build_first_vision_task — added "PHOTO-EDIT" to task header.
     "SAME APARTMENT PHOTO-EDIT — apply" eliminates residual reconstruction framing.
  build_restyling_wow_directive kept imported for backward compat.

Wave 4.6.0 — CORE PRODUCT SIMPLIFICATION:

  Problem: DNA furniture lists specified specific pieces ("deep curved bouclé sofa")
  which instructed the model to REPLACE uploaded furniture rather than RESTYLE it —
  directly contradicting "Decorate this photo — do not recompose it."

  Changes:
  1. All 10 atmosphere DNA files — living_room + master_bedroom furniture_language
     changed from specific piece names to material/texture/form vocabulary.
     "deep curved bouclé sofa in ivory" → "bouclé upholstery in warm ivory on curved seating"
  2. build_simplified_fv_contract(): removed _room_note() ROOM LOCK phrases —
     not grounded in uploaded photo ("preserve TV wall or fireplace position, sofa zone").
  3. build_first_vision_task — "reproduce... Then transform" → "preserve... Restyle only"
     Removes implicit reconstruction license; keeps photo as dominant source of truth.
  4. build_scene_completion(): removed element checklist ("COMPLETE THE SCENE: include
     sofa grouping, coffee table..."). Only quality/atmosphere note remains.
  5. FIRST_VISION DNA path: interior_completeness = "" — DNA handles furnishing richness;
     "never sparse, empty" contradicts photo-first when upload is intentionally minimal.
     Source line kept for backward compat with validator source-code ordering checks.

Wave 4.5.1 — FIRST_VISION PHILOSOPHY REFOCUS:

  Problem: PROD testing showed the system behaved like "architectural reconstruction
  + luxury redesign" instead of "faithful premium restyling of the SAME photo."
  The uploaded photo was being treated as inspiration, not as the dominant source.

  Fix (two-part):
  1. WOW directive: build_first_vision_wow_directive() (editorial redesign framing)
     replaced with build_restyling_wow_directive() (photo-first restyling framing).
     "Decorate this photo — do not recompose it." replaces "Transform the character fully."
  2. DNA STYLE key: "STYLE:" changed to "ATMOSPHERE STYLE (restyle existing elements):"
     — reduces compositional authority without changing content.

  build_first_vision_wow_directive() preserved unchanged for backward compatibility
  with validator suites (validate_wave431.py, validate_wave432.py, etc.).

Wave 4.5.0 — SIMPLIFICATION & CONTRACT REALIGNMENT:

  Philosophy shift: input_fidelity=high + structural mask + SAME APARTMENT task
  framing do the heavy architectural preservation work. The contract provides
  vocabulary alignment, not defensive repetition. Simpler = clearer.

  FIRST_VISION now uses build_simplified_fv_contract() (Tier 1.5, ~820 chars)
  instead of build_structural_contract() (Tier 1, ~1550 chars). All required
  vocabulary is preserved; redundant defensive prose removed.

  Effect: ~730-char reduction in FIRST_VISION prompts. interior_completeness (P5)
  now survives at 200-char source for all 10 atmospheres including Soft Luxury Gold
  and Dark Contemporary. Zero drops at standard usage.

Wave 4.4.1 — PROMPT BUDGET REBALANCING:

  Problem: Compression was dropping wow_directive before realism for large-DNA
  atmospheres (Soft Luxury Gold, ~939-char DNA block). wow_directive is at least
  as important as the realism quality floor — losing it produces flat transformations.

  Fix (three-part):
  1. FIRST_VISION budget raised 3350→3550 (+200 chars headroom).
  2. FIRST_VISION realism downgraded: build_medium_realism_block() (325 chars) →
     build_compact_realism_block() (133 chars). Saves 192 chars. The compact block
     preserves all critical vocabulary (NOT a CGI render, DSLR, natural light physics,
     real materials) — only extended cinematic prose is shed.
  3. interior_completeness priority: P4→P5. Drops before wow_directive and all
     P4 dream-richness sections. It's a nicety; wow_directive is load-bearing.

  Combined effect: For Soft Luxury Gold living room (200-char description),
  wow_directive now survives where it previously dropped. Budget arbitration order:
    P5 (interior_completeness) → P4 (wow_directive) → P3 (compact_realism) → P2 (DNA)

  Section priority (P5 dropped first, P1 never dropped):
    P1 — task, header, contracts, source (structural anchors)
    P2 — design_intel (core DNA or style block)
    P3 — realism block (quality floor)
    P4 — dream richness (scene_completion, dream_addendum, dream_micro)
    P5 — optional context (visible_spaces, refinement_memory, design_direction)

  FIRST_VISION now uses build_medium_realism_block() (~310 chars) instead of
  build_realism_block() (~995 chars) — saving ~685 chars as primary compression.

  Dream richness micro-layer (build_dream_micro_layer, ~78 chars) is injected
  on DNA paths in FIRST_VISION and STYLE_REFINEMENT.

ORDERING PRINCIPLE: Constraints appear before transformation instructions.
"""

import logging
import os  # TRUST_PIXELS_V1 validation toggle (Phase C A/B; Phase D will grave it)
import re  # P2 — DNA_SPATIAL_LIGHT strip of spatial micro-management
log = logging.getLogger("aih")

# ── DNA_CLEANUP_V1 (2026-06-13) — grouped DNA cleanup ─────────────────────────
# Goal: reduce CONTRADICTIONS + spatial micro-rules that make gpt-image-1
# "recompute the room" — WITHOUT reducing richness. Keeps every decor item,
# materials, palette, lighting, textiles + the atmosphere identity. Supersedes
# P2 (DNA_SPATIAL_LIGHT). Flagged: DNA_CLEANUP_V1.
#   1. decor spatial micro-rules removed (anchored corner / never floating /
#      else-omit conditional). These are pure placement fluff for plant/art.
#   2. light "existing" reduction — only before FURNITURE nouns (the contract's
#      furniture-fix already guards them); KEEP "existing walls/window/glazing"
#      (architecture preservation signal).
# DELIBERATELY KEPT (do NOT strip — load-bearing, not micro-management):
#   • The TV placement clause "clearly present on an existing wall or low media
#     console, never a new wall…". Stripping it caused DOUBLE TVs (2026-06-14):
#     it is the SINGULAR placement anchor (one TV, one surface) AND the
#     anti-faux-mur guard (engineered over many waves). "include a television
#     as the focal point" alone is count-ambiguous → the model renders a wall TV
#     + a console TV when staging an empty room. Keeping the clause is the PROPER
#     fix (a positive placement spec), NOT a "never two TVs" band-aid.
# NOT done: no "never show two televisions" rule, no mood-adjective trim.
_SPATIAL_MICRORULE_PATTERNS = (
    re.compile(r",?\s*never floating in the room", re.IGNORECASE),
    re.compile(r"\s*anchored in the existing corner[^—\-,;]*", re.IGNORECASE),
    re.compile(r"\s*[—\-]?\s*only if (?:that )?wall is (?:solid and )?free,?\s*else omit", re.IGNORECASE),
)
# Light "existing" reduction — furniture nouns only (NOT walls/window/glazing).
_EXISTING_FURNITURE_RE = re.compile(
    r"\bexisting ((?:low |coffee |side |dining |media )?(?:sofa|table|console|"
    r"sideboard|armchair|chair|chaise|bed|desk))\b",
    re.IGNORECASE,
)


def _dna_cleanup_v1(text: str) -> str:
    """DNA_CLEANUP_V1 — strip contradictions/spatial micro-rules + lighten
    'existing'; KEEP every decor item, materials, lighting, identity + newlines.
    No negative band-aids (no never-two-TV, no adjective trim)."""
    if not text:
        return text
    for _pat in _SPATIAL_MICRORULE_PATTERNS:
        text = _pat.sub("", text)
    text = _EXISTING_FURNITURE_RE.sub(r"\1", text)   # lighten "existing" (furniture only)
    text = re.sub(r" {2,}", " ", text)               # collapse double spaces (NOT newlines)
    text = re.sub(r" +([;,.])", r"\1", text)         # space before punctuation
    text = re.sub(r"—\s*([;,])", r"\1", text)        # dangling em-dash before separator
    return text

from .style_dna import StyleDNA, get_style
from .preservation import (
    build_structural_contract,
    build_continuation_contract,
    build_structural_evolution_contract,
    build_atmosphere_switch_contract,
    build_simplified_fv_contract,
    build_mode_contract,  # Wave 5.13f — single MODE_CONTRACT replaces 6 layers in FIRST_VISION
    HIGH_FIDELITY_ATMOSPHERES,  # PHASE 1.2 — shared fidelity allow-list (also used by main.py)
)
from .anchor_detector import detect_anchors
from .switch_redesign import build_switch_hero_block  # SWITCH_REDESIGN_PILOT (R3)
from .dream_scene_completion import (
    build_scene_completion,
    build_dream_addendum,
    build_dream_micro_layer,
    build_natural_enrichment,
)
from .wow_layer import build_first_vision_wow_directive, build_restyling_wow_directive, build_photo_edit_wow_directive, build_atmosphere_dna_boundary
from .fidelity_layer import build_first_vision_task, build_openings_anchor
from .refinement_memory import RefinementState, parse_history, build_refinement_block
from .realism_layer import (
    build_compact_realism_block,
    build_editorial_realism_block,  # Wave 5.14A — additive editorial-realism layer
    build_photographic_credibility_block,  # Wave 5.14B — re-enabled in Wave 5.14A Last-Chance Step 2 (combined with quality=low)
    build_medium_realism_block,
    build_interior_completeness_rule,
)
from .edit_intent import (
    EditMode,
    classify_edit_mode,
    build_local_edit_prompt,
    build_layout_change_prompt,  # Wave 5.13c — new LAYOUT_CHANGE path
    build_style_refinement_header,
    build_structural_transformation_header,
)
from .atmosphere_dna import (
    get_room_dna,
    build_dna_block,
    build_dna_room_context_signal,  # Wave 5.5.18 — revives dormant DNA fields
    label_to_atmosphere_id,
)
from .atmosphere_dna.bimodal_classifier import apply_bimodal, inject_creative_revival  # Wave 5.5.14c/d — no-op unless BIMODAL_ENABLED=1
# Wave 6.1 — Decorative Foundation pilot (WM + Living + FV + preserve only).
# Both helpers return "" outside the pilot gate — production prompts stay
# byte-identical for any non-WM-Living-FV-preserve call.
from .decorative_manifest import (
    build_decoration_anchor_rule,
    build_staging_manifest,
)
# Wave 5.5.15c — trimmed retry of emotional_realism.
# Wave 5.5.15b shipped "lived-in micro-layering" (preserve) + "layered texture
# realism" + "lived-in storytelling" (creative) → wall invention 3/9 on bench
# (Warm M #1 wall right, Japandi #1 wall left, Japandi #3 wall right + rear
# window suppressed). Suspected cause: surface-implying nouns ("layering",
# "texture", "lived-in") invite the model to invent walls to layer ON.
# Wave 5.5.15c drops those nouns entirely and keeps ONLY lighting/atmosphere
# concepts that carry no spatial implication:
#   Preserve : shadow falloff + restrained imperfections
#   Creative : cinematic lighting depth + restrained imperfections +
#              atmospheric warmth around the existing focal zone
# All bimodal-gated → no-op when BIMODAL_ENABLED is unset.
from .emotional_realism import build_emotional_realism_signal
# Wave 5.5.16 — geometry-attached furnishing semantics (5 rooms × 2 modes).
# Replaces the Wave 5.5.15g safe_furnishing_intelligence module: same
# bimodal-split + room-keyed dict shape, but every named furnishing item
# is anchored to a specific existing geometric element of the photographed
# apartment (coffee table → seating footprint, TV → existing wall geometry,
# etc.). See geometry_attached_furnishing.py docstring for the full design
# contract and anchor architecture.
from .geometry_attached_furnishing import build_furnishing_signal
from .visible_space_logic import build_visible_spaces_block

# ── Budget system ─────────────────────────────────────────────────────────────

_MODE_BUDGETS: dict[str, int] = {
    "FIRST_VISION": 4300,  # Wave 6.16 (2026-06-10): raised 4000→4300. The 6.14 styling layer (decor 2→6) + 6.16 emphatic curtains & focal-TV legitimately enriched the preserve prompt; the 5 styled livings landed at ~3810-3840 (margin only ~170), and WM-Living already overflowed at 4022 → the budget dropped dna_room_context (the TV anchor!). 4300 gives ~460 margin so the TV anchor survives even on feature-rich sources. Same "headroom for existing sections" rationale as 5.5.14g. ~1075 tokens — still cheap vs the image gen. ↓ original 5.5.14g note ↓ Wave 5.5.14g (richness reinvestment): raised 3850→4000 (hard ceiling). Rationale: Wave 5.5.14f freed ~445 chars in preserve mode by dropping 3 boundary voices, but Wave 5.5.14d's creative mode ADDS ~250-300 chars (dormant DNA revival + REIMAGINED framing). Measured tightest creative margin: Tropical Escape at +11 above 3850 → unsafe for real-world prompts with descriptions or extra visible spaces. Raising to the matrix hard ceiling 4000 gives creative mode +130-360 margin while letting preserve mode's P4/P5 sections (natural_enrichment, visible_spaces, design_direction) thrive on rich prompts. No new content added — just headroom for existing sections to survive budget. Default (BIMODAL_ENABLED unset) prompts stay well under any cap. Wave 5.5.3 lineage: 3550→3850 to seat C3 boundary; Wave 5.5.14g: 3850→4000 to seat creative revival headroom.
    # Wave 4.8.2: raised 2400→3500 / 2500→3600. The 4.8.1a audit proved the
    # (legitimately grown 4.6–4.7) P1 preservation/continuity stack alone
    # (~2528 / ~2601) exceeded the old 2400/2500 caps, silently evicting
    # design_intel (atmosphere DNA) + compact_realism. Combined with the 4.8.2
    # header de-duplication, these right-sized budgets let de-duped-P1 + full
    # DNA + realism survive (only P5 refinement memory drops). Still below V1
    # (3550) and the 4000 hard ceiling — quality restoration, not inflation.
    "STYLE_REFINEMENT": 3500,
    "STRUCTURAL_TRANSFORMATION": 3600,
    # Wave 5.13c — LOCAL_EDIT budget raised 1500→2200 to accommodate the
    # retrofitted structural_identity + source_continuity sections on top
    # of the stricter (longer) differential edit prompt. New estimate :
    # source_continuity ~200 + structural_identity ~400 + edit_block ~1200
    # + compact_realism ~150 ≈ 1950, leaving ~250 chars of safety margin.
    "LOCAL_EDIT": 2200,
    # Wave 5.13c — LAYOUT_CHANGE budget : same family as LOCAL_EDIT but
    # adds the partial DNA intel block (~350 chars). edit_block ~1300 +
    # partial DNA ~350 + structural_identity ~400 + source_continuity
    # ~200 + compact_realism ~150 ≈ 2400. Round up to 2600.
    "LAYOUT_CHANGE": 2600,
}

# P5 dropped first; P1 never dropped. Unknown sections default to P3 (realism tier).
_SECTION_PRIORITY: dict[str, int] = {
    # P1 — structural anchors and task framing (never dropped)
    "task": 1,
    "header": 1,
    "edit_block": 1,
    "mode_contract": 1,         # Wave 5.13f — single authoritative MODE_CONTRACT (FIRST_VISION)
    "full_contract": 1,
    "continuation_contract": 1,
    "atmosphere_contract": 1,   # Wave 4.3.0 — replaces continuation_contract in SR path
    "evolution_contract": 1,
    "source_space": 1,
    "openings_anchor": 1,       # Wave 4.6.2 — openings fidelity (FIRST_VISION only)
    "architectural_anchors": 1, # Wave 4.7.1 R1 — concrete image anchors (FIRST_VISION)
    "structural_identity": 1,   # Wave 4.7.2 — persistent apartment identity (V1/V2/V3)
    "source_continuity": 1,     # Wave 4.7.3 — visual-source continuity (V2/V3 only)
    "structural_negative_anchors": 1,  # Wave 4.7.4 — no-new-wall topology (V1/V2/V3)
    "authorized_user_changes": 1,      # Wave 4.7.5 — P1.5 local user authority (V2+); never dropped
    "atmosphere_dna_boundary": 1,      # Wave 5.5.3 — DNA-vs-photo boundary clause; placed after design_intel; never dropped
    # P2 — core design intelligence (dropped only if forced)
    "design_intel": 2,
    "design_intel_partial": 2,  # Wave 5.13c — LAYOUT_CHANGE atmosphere + lighting only
    # P3 — realism quality floor
    "full_realism": 3,
    "compact_realism": 3,
    "editorial_realism": 3,  # Wave 5.14A — additive editorial-realism layer (drops alongside compact under tight budget)
    "photographic_credibility": 3,  # Wave 5.14B — additive photographic-credibility layer (same tier)
    "dna_room_context": 3,  # Wave 5.5.18 — revives dormant DNA fields (room_specific_constraints + visible_transition_logic). Same tier as realism: drops before P4/P5 enrichments but after P2 design_intel.
    # P4 — dream richness / scene enrichment
    # P5 — interior completeness (nice-to-have; drops before wow_directive — Wave 4.4.1)
    "interior_completeness": 5,
    "scene_completion": 4,
    "dream_addendum": 4,
    "dream_micro": 4,
    "wow_directive": 4,   # Wave 4.3.1 — FIRST_VISION transformation ambition
    "natural_enrichment": 4,  # Wave 4.6.2 — light natural decoration (FIRST_VISION only)
    # Wave 6.1 — Decorative Foundation (pilot WM-Living-FV-preserve).
    # decoration_anchor_rule is P3 (safety rail — must outlive the manifest
    # under budget pressure so latitude never opens without anchoring).
    # staging_manifest is P4 (drops first under tight budget — the anchor
    # rule keeps decoration safe in that case).
    "decoration_anchor_rule": 3,
    "staging_manifest": 4,
    # P5 — optional enrichment context (dropped first)
    "visible_spaces": 5,
    "refinement_memory": 5,
    "design_direction": 5,
    "emotional_realism": 5,  # Wave 5.5.15c — bimodal-gated opportunistic signal; P5 drops first under budget pressure
    "geometry_attached_furnishing": 5,  # Wave 5.5.16 — geometry-anchored furnishing (replaces Wave 5.5.15g safe_furnishing); P5 drops first under budget pressure
}


def _assemble_with_budget(
    mode: str,
    raw_sections: list[tuple[str, str]],
) -> tuple[str, list[str]]:
    """
    Priority-aware prompt assembly within the mode's char budget.
    Drops the lowest-priority non-empty sections first when over budget.
    Never truncates mid-sentence. Returns (prompt, dropped_section_names).
    """
    budget = _MODE_BUDGETS.get(mode, 3200)
    active = [(name, text) for name, text in raw_sections if text]
    dropped: list[str] = []

    def _chars(secs: list[tuple[str, str]]) -> int:
        if not secs:
            return 0
        return sum(len(t) for _, t in secs) + len(secs) - 1  # one \n per join

    # Drop from P5 down to P2; P1 is always kept
    for drop_priority in range(5, 1, -1):
        while _chars(active) > budget:
            target_idx = next(
                (i for i, (name, _) in enumerate(active)
                 if _SECTION_PRIORITY.get(name, 3) == drop_priority),
                None,
            )
            if target_idx is None:
                break
            dropped.append(active[target_idx][0])
            active.pop(target_idx)

    return "\n".join(t for _, t in active), dropped


# ── Internal helpers ──────────────────────────────────────────────────────────

def _style_block(dna: StyleDNA, style_label: str) -> str:
    """
    Generic style block used when no room-specific DNA is registered.
    Wave 4.2.1: capped to ~500 chars. Each list is truncated to the most
    essential items so the block fits within tight refinement budgets.

    Wave 4.7.1 (R2 — unify DNA/non-DNA fidelity policy): the specific
    "Furniture — <piece>, <piece>" segment was removed. It emitted concrete
    furniture-generation authority ("sculptural curved sofa in velvet",
    "drapery floor-to-ceiling") on the non-DNA fallback while the DNA path
    (Wave 4.6.0) carries only pure-material restyle vocabulary. That asymmetry
    produced different structural behaviour for the same image/atmosphere.
    Material/palette/lighting still deliver premium richness; furniture is now
    restyled in place, never re-composed — matching the DNA philosophy.
    """
    mat = ", ".join(dna.materials[:4])
    pal = ", ".join(dna.color_palette[:3])
    lit = ", ".join(dna.lighting[:2])
    mood = ", ".join(dna.mood[:2])
    avoid = ", ".join(dna.avoid[:3])

    return (
        f"STYLE ({style_label.split('·')[0].strip()}): "
        f"Character — {mood}. "
        f"Materials — {mat}. "
        f"Palette — {pal}. "
        f"Lighting — {lit}. "
        f"ATMOSPHERE STYLE (restyle existing elements only): {mat}. "
        f"Avoid — {avoid}."
    )


def _design_intelligence_block(
    atmosphere_id: str,
    room_type: str,
    style_dna: StyleDNA,
    style_label: str,
    generation_mode: str = "preserve",  # Wave 5.5.14c — bimodal hook
) -> tuple[str, bool]:
    room_dna = get_room_dna(atmosphere_id, room_type)
    # Wave 4.8.1b: observability for the label→DNA resolution fix.
    log.info(
        "[AtmosphereDNA] label=%r  atmosphere_id=%s  room=%s  "
        "dna_matched=%s  path=%s",
        style_label, atmosphere_id, room_type or "(none)",
        bool(room_dna), "DNA" if room_dna else "fallback_style_block",
    )
    if room_dna:
        # Wave 5.5.14c — apply_bimodal is a no-op unless BIMODAL_ENABLED env
        # var is set AND generation_mode == "preserve". Default → byte-
        # identical to pre-5.5.14c output.
        block = build_dna_block(room_dna)
        block = apply_bimodal(block, atmosphere_id, generation_mode)
        # Wave 5.5.14d — in creative mode, append the dormant DNA fields
        # (architectural_language, room_specific_constraints, keywords).
        # No-op for preserve / default paths.
        block = inject_creative_revival(
            block, atmosphere_id, room_type, generation_mode
        )
        return block, True
    return _style_block(style_dna, style_label), False


# ── Wave 5.13f — compact structural_identity wrapper (FIRST_VISION only) ─────
#
# render_clause() (structural_identity.py) ships the same verbose wrapper to
# V1/V2/V3 paths: "STRUCTURAL IDENTITY — this apartment already contains
# these architectural facts; reproduce them exactly, do not normalize,
# narrow, or restyle them: [facts]. These are existing structural truths,
# not design choices." MODE_CONTRACT now states that intent authoritatively,
# so for FIRST_VISION the wrapper is rewrapped inline as a 30-char header.
# V2/V3 paths keep the verbose form unchanged.

_PRESERVE_IDENTITY_PREFIX = (
    "STRUCTURAL IDENTITY — this apartment already contains these "
    "architectural facts; reproduce them exactly, do not normalize, "
    "narrow, or restyle them: "
)
_PRESERVE_IDENTITY_SUFFIXES = (
    ". These are existing structural truths, not design choices. "
    "Only the explicitly requested structural change may alter them.",
    ". These are existing structural truths, not design choices.",
)
_CREATIVE_IDENTITY_PREFIX = (
    "ARCHITECTURAL MEMORY — this space contains these photographed "
    "architectural facts as creative starting points; they may be "
    "reinterpreted to express the atmosphere's character: "
)
_CREATIVE_IDENTITY_SUFFIX = (
    ". Use them as an architectural reference, not as constraints."
)


def _compact_structural_identity_wrapper(verbose_clause: str) -> str:
    """
    Wave 5.13f — rewrap render_clause output for FIRST_VISION compactness.

    Preserve "STRUCTURAL IDENTITY — ..." → "PHOTO FACTS TO RESPECT: [facts]."
    Creative "ARCHITECTURAL MEMORY — ..." → "PHOTO CONTEXT: [facts]."
    Unrecognised wrapper returned unchanged (defensive — never silently
    swallow content). Empty input returns "".
    """
    if not verbose_clause:
        return ""
    if verbose_clause.startswith(_PRESERVE_IDENTITY_PREFIX):
        body = verbose_clause[len(_PRESERVE_IDENTITY_PREFIX):]
        for sfx in _PRESERVE_IDENTITY_SUFFIXES:
            if body.endswith(sfx):
                body = body[: -len(sfx)]
                break
        return f"PHOTO FACTS TO RESPECT: {body}."
    if verbose_clause.startswith(_CREATIVE_IDENTITY_PREFIX):
        body = verbose_clause[len(_CREATIVE_IDENTITY_PREFIX):]
        if body.endswith(_CREATIVE_IDENTITY_SUFFIX):
            body = body[: -len(_CREATIVE_IDENTITY_SUFFIX)]
        return f"PHOTO CONTEXT: {body}."
    return verbose_clause


# ── Wave 5.13c — LAYOUT_CHANGE partial DNA helper ────────────────────────────
#
# LAYOUT_CHANGE rearranges existing furniture without restyling. Emitting
# the FULL atmosphere DNA (materials + furniture vocabulary) tells the
# model to materialize specific pieces — exactly what we want to avoid.
# This helper emits a TRIMMED DNA block : atmosphere identity (philosophy,
# emotional intent, luxury level) + room-specific lighting_behavior ONLY.
# material_palette, furniture_language, decor_language and realism
# constraints are dropped — the existing image already carries those.
# Atmosphere-agnostic : works for every registered atmosphere.

def _layout_change_intel_block(atmosphere_id: str, room_type: str) -> str:
    """
    Wave 5.13c — partial DNA block for LAYOUT_CHANGE.

    Emits :
      ATMOSPHERE (Name): philosophy — emotional_intent. [luxury_level]
      ROOM (Room) LIGHTING (preserve): {room_dna.lighting_behavior}
      ROOM CONTEXT: {room_dna.room_specific_constraints[:2]}.

    Returns "" when the atmosphere is not registered.

    Wave 5.13c bugfix (2026-05-31) — restore `room_specific_constraints`
    emission. See composer_v2.py docstring for the full rationale.
    Kept in sync with composer_v2._layout_change_intel_block so V1
    fallback behavior (if ever exercised) matches the runtime path.
    """
    from .atmosphere_dna import get_core, get_room_dna
    core = get_core(atmosphere_id)
    if not core:
        return ""

    atm_name = atmosphere_id.replace("_", " ").title()
    lines = [
        f"ATMOSPHERE ({atm_name}): {core.philosophy} — {core.emotional_intent}. "
        f"[{core.luxury_level}]"
    ]
    room_dna = get_room_dna(atmosphere_id, room_type)
    if room_dna:
        room_name = room_dna.room_type.replace("_", " ").title()
        if room_dna.lighting_behavior:
            lines.append(
                f"ROOM ({room_name}) LIGHTING (preserve): {room_dna.lighting_behavior}"
            )
        if room_dna.room_specific_constraints:
            ctx = "; ".join(room_dna.room_specific_constraints[:2])
            lines.append(f"ROOM CONTEXT: {ctx}.")
    return "\n".join(lines)


def _audit(
    mode: str,
    sections: list[tuple[str, str]],
    dropped: list[str] | None = None,
) -> None:
    """
    Emit per-section prompt size audit at DEBUG level.
    sections: list of (label, text) pairs in assembly order.
    """
    budget = _MODE_BUDGETS.get(mode, 3200)
    total = sum(len(t) for _, t in sections if t)
    lines = [
        f"[Prompt Audit] mode={mode}  budget={budget}  total={total}  "
        f"est_tokens~{total // 4}"
    ]
    for label, text in sections:
        lines.append(f"  {label}: {len(text)}")
    if dropped:
        lines.append(f"  [Budget Drop] removed_sections={dropped}")
    log.debug("\n".join(lines))


def compose_generation_prompt(
    style_label: str,
    room_type: str,
    room_description: str,
    user_instruction: str,
    iteration: int,
    history: list[dict],
    secondary_visible_spaces: list[str] | None = None,
    compact_prompts: bool = False,
    structural_identity: str = "",
    source_continuity: str = "",
    structural_negative_anchors: str = "",
    authorized_user_changes: str = "",
    generation_mode: str = "preserve",  # Wave 5.5.14c — bimodal intent; passed to _design_intelligence_block. No-op unless BIMODAL_ENABLED env var is truthy.
    edit_mode: "EditMode | None" = None,  # Wave 5.13d Phase 1 — single source of truth for edit_mode (passed from main.py).
    editorial_realism_enabled: bool = True,  # Wave 5.14A — gate the editorial-realism layer (FIRST_VISION only ; REBOOT_FRESH delegation passes False). Default True preserves direct V1 callers (main.py iteration=1).
    switch_redesign: bool = False,  # SWITCH_REDESIGN_PILOT — set True ONLY by composer_v2's REBOOT_FRESH delegation (switch). Injects in-place furniture-replacement (R1) + hero signatures (R3) into FIRST_VISION. Default False → real V1 byte-identical.
    prev_atmosphere_id: str = "",  # (2026-06-22) signature-compat with composer_v2 (env-dispatch). Accepted + IGNORED here — the frozen V1 path has no switch detection. No effect on V1 output.
    lineage_customized=None,  # β (2026-06-22) signature-compat with composer_v2. Accepted + IGNORED here (V1 path has no switch/customization gate). No effect on V1 output.
) -> str:
    """
    Build the complete generation prompt from all intelligence layers.

    Routes to one of four assembly strategies based on edit mode:
      LOCAL_EDIT            → targeted edit (no redesign language, no style DNA)
      STYLE_REFINEMENT      → compact header + continuation contract + DNA
      STRUCTURAL_TRANSFORM  → structural header + evolution contract + DNA
      FIRST_VISION          → full redesign (task + full contract + full DNA + medium realism)

    compact_prompts=True (DEV mode): compact realism everywhere, P4 enrichments
    (dream richness, scene completion, interior completeness) skipped.

    Wave 5.13d Phase 1 (2026-05-31) — `edit_mode` parameter accepted from
    main.py. If provided, it overrides internal `classify_edit_mode` call,
    establishing main.py as the single source of truth. Previous behavior :
    main.py and composer.py / composer_v2.py each independently classified
    on different inputs (raw prompt vs enriched_instruction), producing
    schizophrenic prompts when classifications diverged (e.g. main.py said
    STRUCTURAL, composer_v2 said LOCAL_EDIT on the same request). Fallback
    to classify_edit_mode when None preserves backward compat for any
    caller not yet updated.
    """
    dna = get_style(style_label)
    atmosphere_id = label_to_atmosphere_id(style_label)
    refinement_state = parse_history(history, iteration)
    if edit_mode is None:
        mode = classify_edit_mode(user_instruction, iteration)
        log.info("  edit_mode: %s (classified internally)  atmosphere: %s  room: %s", mode.value, atmosphere_id, room_type or "(none)")
    else:
        mode = edit_mode
        log.info("  edit_mode: %s (received from caller)  atmosphere: %s  room: %s", mode.value, atmosphere_id, room_type or "(none)")

    # ── Path A: LOCAL EDIT ────────────────────────────────────────────────────
    # Wave 5.13c — retrofit. The previous Path A was the thinnest in the
    # composer (edit_block + compact_realism only). Combined with the
    # LATEST-as-source default and input_fidelity=high, V3 LOCAL_EDITs
    # produced cascade-degraded outputs : artefacts, regenerated textures,
    # unrequested modifications. The retrofit injects two P1 anchors that
    # already exist in V2/V3 STYLE_REFINEMENT and STRUCTURAL_TRANSFORMATION
    # paths : source_continuity ("CONTINUE FROM CURRENT DESIGN") and
    # structural_identity (windows/openings/depth facts). No atmosphere DNA
    # added — keeping LOCAL_EDIT differentiated from STYLE_REFINEMENT.
    if mode == EditMode.LOCAL_EDIT:
        edit_block = build_local_edit_prompt(
            user_instruction=user_instruction,
            style_name=dna.name,
            room_type=room_type,
            room_description=room_description,
        )
        realism = build_compact_realism_block()
        raw_sections = [
            ("source_continuity", source_continuity),   # P1 — Wave 5.13c retrofit
            ("structural_identity", structural_identity),  # P1 — Wave 5.13c retrofit
            ("edit_block", edit_block),
            ("compact_realism", realism),
            # Wave 5.14A Fix — editorial_realism intentionally NOT wired here.
            # LOCAL_EDIT uses quality=low + fidelity=OMIT (main.py:1788). The
            # rich editorial vocabulary (Material depth / Subtle imperfections /
            # Natural light physics) at low fidelity degrades source-anchor
            # crispness. Editorial is FIRST_VISION-only (medium+high params).
        ]
        _audit("LOCAL_EDIT", raw_sections)
        prompt, dropped = _assemble_with_budget("LOCAL_EDIT", raw_sections)
        log.info(
            "[Prompt Budget] mode=LOCAL_EDIT  budget=%d  actual=%d  "
            "compression_applied=%s  removed_sections=%s",
            _MODE_BUDGETS["LOCAL_EDIT"], len(prompt), bool(dropped), dropped or [],
        )
        return prompt

    # ── Path E: LAYOUT_CHANGE ─────────────────────────────────────────────────
    # Wave 5.13c — new path for spatial rearrangement intents ("move TV in
    # front of sofa", "rearrange the seating"). Sits between LOCAL_EDIT
    # (no position change allowed) and STYLE_REFINEMENT (full DNA, redesign
    # permitted). Source stays LATEST (continue the vision). Prompt permits
    # position/orientation changes for the named pieces while forbidding
    # material/colour/model substitution. Paired with a PARTIAL DNA block
    # (atmosphere identity + lighting only — furniture_language and
    # material_palette dropped to avoid the model rerendering furniture
    # pieces it should just move).
    if mode == EditMode.LAYOUT_CHANGE:
        edit_block = build_layout_change_prompt(
            user_instruction=user_instruction,
            style_name=dna.name,
            room_type=room_type,
            room_description=room_description,
        )
        partial_dna = _layout_change_intel_block(atmosphere_id, room_type)
        realism = build_compact_realism_block()
        raw_sections = [
            ("source_continuity", source_continuity),
            ("structural_identity", structural_identity),
            ("structural_negative_anchors", structural_negative_anchors),
            ("edit_block", edit_block),
            ("design_intel_partial", partial_dna),
            ("compact_realism", realism),
            # Wave 5.14A Fix — editorial_realism NOT wired here. LAYOUT_CHANGE
            # uses quality=low + fidelity=OMIT ; see LOCAL_EDIT note above.
        ]
        _audit("LAYOUT_CHANGE", raw_sections)
        prompt, dropped = _assemble_with_budget("LAYOUT_CHANGE", raw_sections)
        log.info(
            "[Prompt Budget] mode=LAYOUT_CHANGE  budget=%d  actual=%d  "
            "compression_applied=%s  removed_sections=%s",
            _MODE_BUDGETS["LAYOUT_CHANGE"], len(prompt), bool(dropped), dropped or [],
        )
        return prompt

    # ── Path B: STYLE REFINEMENT ─────────────────────────────────────────────
    # Wave 4.3.0: Uses build_atmosphere_switch_contract() (Tier 3.5) instead of
    # build_continuation_contract() (Tier 3). Tier 3.5 adds explicit topology
    # lock, multi-zone protection, and named anchor preservation detected from
    # room_description. FIRST_VISION, STRUCTURAL_TRANSFORMATION, and LOCAL_EDIT
    # paths are unchanged.
    if mode == EditMode.STYLE_REFINEMENT:
        header = build_style_refinement_header(user_instruction, dna.name, room_type)

        anchor_profile = detect_anchors(room_description)
        if anchor_profile.anchors:
            log.info(
                "[AnchorDetect] mode=STYLE_REFINEMENT  anchors=%s",
                list(anchor_profile.anchors),
            )
        contract = build_atmosphere_switch_contract(room_type, anchor_profile.clause)

        intel_block, used_dna = _design_intelligence_block(atmosphere_id, room_type, dna, style_label, generation_mode)

        source = f"SOURCE SPACE: {room_description}" if room_description else ""

        vs_block = ""
        if secondary_visible_spaces:
            vs_block = build_visible_spaces_block(atmosphere_id, secondary_visible_spaces) or ""

        refinement_block = build_refinement_block(refinement_state, iteration)
        realism = build_compact_realism_block()

        # DNA paths: inject dream_micro (already covers richness via decor_language).
        # Non-DNA paths: inject dream_addendum (atmosphere quality note).
        # DEV compact mode: skip all P4 dream/richness enrichments.
        if compact_prompts:
            dream_block = ""
            dream_key = "dream_micro"
        elif used_dna:
            dream_block = build_dream_micro_layer()
            dream_key = "dream_micro"
        else:
            dream_block = build_dream_addendum(atmosphere_id)
            dream_key = "dream_addendum"

        # Wave 5.5.18 — revive dormant DNA fields (room_specific_constraints +
        # visible_transition_logic). Bimodal-gated to creative-mode only in v1.
        # Returns "" for default + preserve → byte-identical baseline.
        # Wave 5.5.32 — gate through apply_bimodal so per-atmosphere strips
        # neutralise architectural directives that previously bypassed.
        sr_room_dna = get_room_dna(atmosphere_id, room_type)
        dna_context_sr = build_dna_room_context_signal(sr_room_dna, generation_mode)
        dna_context_sr = apply_bimodal(dna_context_sr, atmosphere_id, generation_mode)

        raw_sections = [
            ("header", header),
            ("source_continuity", source_continuity),  # P1 — Wave 4.7.3: continue from current design vs restart
            ("atmosphere_contract", contract),
            ("structural_identity", structural_identity),  # P1 — Wave 4.7.2: same persistent identity as V1
            ("structural_negative_anchors", structural_negative_anchors),  # P1 — Wave 4.7.4: no-new-wall topology
            ("authorized_user_changes", authorized_user_changes),  # P1.5 — Wave 4.7.5: local user authority
            ("source_space", source),
            ("design_intel", intel_block),
            ("dna_room_context", dna_context_sr),  # P3 — Wave 5.5.18 dormant fields revival
            (dream_key, dream_block),
            ("visible_spaces", vs_block),
            ("refinement_memory", refinement_block),
            ("compact_realism", realism),
            # Wave 5.14A Fix — editorial_realism NOT wired here. STYLE_REFINEMENT
            # uses quality=low + fidelity=OMIT ; see LOCAL_EDIT note above.
        ]
        _audit("STYLE_REFINEMENT", raw_sections)
        prompt, dropped = _assemble_with_budget("STYLE_REFINEMENT", raw_sections)
        log.info(
            "[Prompt Budget] mode=STYLE_REFINEMENT  budget=%d  actual=%d  "
            "compression_applied=%s  removed_sections=%s",
            _MODE_BUDGETS["STYLE_REFINEMENT"], len(prompt), bool(dropped), dropped or [],
        )
        log.info(
            "[V2V3Budget] path=V2  total=%d  budget=%d  dna_retained=%s  "
            "realism_retained=%s  dropped=%s",
            len(prompt), _MODE_BUDGETS["STYLE_REFINEMENT"],
            "design_intel" not in dropped, "compact_realism" not in dropped,
            dropped or [],
        )
        return prompt

    # ── Path C: STRUCTURAL TRANSFORMATION ────────────────────────────────────
    if mode == EditMode.STRUCTURAL_TRANSFORMATION:
        header = build_structural_transformation_header(user_instruction, dna.name, room_type)
        contract = build_structural_evolution_contract(room_type)

        source = f"SOURCE SPACE: {room_description}" if room_description else ""
        intel_block, used_dna = _design_intelligence_block(atmosphere_id, room_type, dna, style_label, generation_mode)
        # room_context omitted from STRUCTURAL_TRANSFORMATION for the same budget
        # reason as STYLE_REFINEMENT — the header's architectural intent is sufficient.
        refinement_block = build_refinement_block(refinement_state, iteration)
        realism = build_compact_realism_block()

        # Wave 5.5.18 — dormant DNA fields revival (creative-only via signal gate).
        # Wave 5.5.32 — gate through apply_bimodal (see room_context fix at
        # STYLE_REFINEMENT call site for rationale).
        st_room_dna = get_room_dna(atmosphere_id, room_type)
        dna_context_st = build_dna_room_context_signal(st_room_dna, generation_mode)
        dna_context_st = apply_bimodal(dna_context_st, atmosphere_id, generation_mode)

        raw_sections = [
            ("header", header),
            ("source_continuity", source_continuity),  # P1 — Wave 4.7.3: continue from current design vs restart
            ("evolution_contract", contract),
            ("structural_identity", structural_identity),  # P1 — Wave 4.7.2: same identity; only the explicit edit may alter it
            ("structural_negative_anchors", structural_negative_anchors),  # P1 — Wave 4.7.4: no-new-wall topology
            ("authorized_user_changes", authorized_user_changes),  # P1.5 — Wave 4.7.5: local user authority
            ("source_space", source),
            ("design_intel", intel_block),
            ("dna_room_context", dna_context_st),  # P3 — Wave 5.5.18 dormant fields revival
            ("refinement_memory", refinement_block),
            ("compact_realism", realism),
            # Wave 5.14A Fix — editorial_realism NOT wired here. STRUCTURAL
            # uses quality=low + fidelity=OMIT ; see LOCAL_EDIT note above.
        ]
        _audit("STRUCTURAL_TRANSFORMATION", raw_sections)
        prompt, dropped = _assemble_with_budget("STRUCTURAL_TRANSFORMATION", raw_sections)
        log.info(
            "[Prompt Budget] mode=STRUCTURAL_TRANSFORMATION  budget=%d  actual=%d  "
            "compression_applied=%s  removed_sections=%s",
            _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"], len(prompt), bool(dropped), dropped or [],
        )
        log.info(
            "[V2V3Budget] path=V3  total=%d  budget=%d  dna_retained=%s  "
            "realism_retained=%s  authorized_retained=%s  dropped=%s",
            len(prompt), _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"],
            "design_intel" not in dropped, "compact_realism" not in dropped,
            "authorized_user_changes" not in dropped, dropped or [],
        )
        return prompt

    # ── Path D: FIRST VISION (full redesign) ──────────────────────────────────
    # Wave 5.13f — single MODE_CONTRACT replaces 6 overlapping structural sections:
    #   task / full_contract / openings_anchor / structural_negative_anchors /
    #   wow_directive / natural_enrichment.
    # The mode contract authoritatively states what is locked (preserve) or
    # flexible (creative). STRUCTURAL_IDENTITY (vision-captured facts) remains
    # injected separately as PHOTO FACTS TO RESPECT. Scope: FIRST_VISION only —
    # STYLE_REFINEMENT and STRUCTURAL_TRANSFORMATION paths are untouched.
    # Wave 6.3 — user_instruction is forwarded so the TEMPORAL CONTINUITY
    # guardrail can be suppressed when the user explicitly requests a
    # temporal transformation (evening / night / cinematic / etc.).
    # PHASE 1.2 — the light contract is safe only where the image is pixel-
    # anchored = V1 (FIRST_VISION) preserve on a fidelity=high atmosphere. Uses
    # the SAME shared tuple as main.py's fidelity decision → cannot desync, so
    # we never ship the light contract on a low-fidelity path. Tropical (low)
    # and every switch (non-FIRST_VISION) keep the full contract.
    _pixel_anchored = (
        mode == EditMode.FIRST_VISION
        and generation_mode == "preserve"
        and atmosphere_id in HIGH_FIDELITY_ATMOSPHERES
    )
    mode_contract = build_mode_contract(
        generation_mode, user_instruction, pixel_anchored=_pixel_anchored
    )

    # SWITCH_REDESIGN_PILOT (R1+R3) — switch-only (forwarded True ONLY by
    # composer_v2's REBOOT_FRESH delegation; never on a real V1). Append an
    # in-place furniture-REPLACEMENT directive + the atmosphere's hero signatures
    # to the kept (P1) mode_contract so the budget assembler can't drop them, and
    # the switch reads as a distinct STYLE instead of a recolor of V1's furniture.
    if switch_redesign:
        # SWITCH_BLOCK_COMPACT (2026-06-23) — switch-only compaction. The full
        # SWITCH REDESIGN clause re-asserts architecture preservation (already in
        # the PRESERVE contract + STRUCTURAL IDENTITY) and footprint (already in
        # PRESERVE), and the full HERO carries verbose parentheticals + duplicate
        # mood adjectives. On feature-rich atmospheres (Soft Luxury) the ~834-char
        # switch appendage pushed the FIRST_VISION prompt past 4300, so the budget
        # assembler dropped dna_room_context — the section carrying the TV / room
        # anchors (proven WM→Soft Luxury: brut 4534 → dropped → TV gone). The
        # compact variant removes only the redundant/verbose parts (keeps REPLACE
        # intent + per-atmosphere hero forms/materials + prev-atmosphere contrast),
        # so the prompt fits and dna_room_context survives.
        # Default OFF → byte-identical to the shipped switch block. NEVER reached
        # on a real V1 (switch_redesign=False) → V1/STAGE byte-identical whatever
        # the flag. Kill-switch: SWITCH_BLOCK_COMPACT=0.
        _compact_switch = os.environ.get("SWITCH_BLOCK_COMPACT", "0") == "1"
        # HERO leak fix (Option A, 2026-06-23) — HERO FURNISHING names living-room
        # pieces (sofa / coffee table / rug). It must NEVER reach a non-living
        # switch: proven that bedroom switches carried sofa+coffee table+rug in the
        # prompt alongside the bed (4/4 atmospheres in backend.log). Gate HERO to
        # the canonical living_room only; elsewhere _hero="". Uses the existing
        # canonical resolver (get_room_dna → _normalise_room), so "Living"/"lounge"/
        # "reception" qualify while "bedroom"/"Master"/Kitchen/Bathroom do not.
        # ALWAYS ON (independent of SWITCH_BLOCK_COMPACT) — it's a live bugfix.
        # The generic SWITCH REDESIGN clause below stays for ALL rooms (a non-living
        # switch must still restyle its own pieces, just without the sofa hero).
        _hero_room_dna = get_room_dna(atmosphere_id, room_type)
        _is_living_room = (
            _hero_room_dna is not None
            and _hero_room_dna.room_type == "living_room"
        )
        _hero = (
            build_switch_hero_block(atmosphere_id, compact=_compact_switch)
            if _is_living_room else ""
        )
        if _compact_switch:
            _switch_clause = (
                " SWITCH REDESIGN — keep every piece in its existing position, but"
                " REPLACE each piece's design with this atmosphere's signature"
                " pieces; do not keep the previous atmosphere's furniture style."
            )
        else:
            _switch_clause = (
                " SWITCH REDESIGN — keep the existing furniture LAYOUT and positions"
                " (each piece stays in place, same footprint and scale), but REPLACE"
                " each piece's design/identity with this atmosphere's signature pieces;"
                " do NOT keep the previous atmosphere's furniture style; keep"
                " architecture (walls, windows, doors, openings, ceiling)"
                " pixel-identical."
            )
        mode_contract = (
            mode_contract
            + _switch_clause
            + ((" " + _hero) if _hero else "")
        )
        log.info(
            "[SWITCH_REDESIGN_PILOT] composer Path D — switch_redesign=True "
            "atmosphere=%s hero_injected=%s compact=%s",
            atmosphere_id, bool(_hero), _compact_switch,
        )

    # Wave 5.13f — compact STRUCTURAL_IDENTITY wrapper for FIRST_VISION only.
    # render_clause emits "STRUCTURAL IDENTITY — this apartment already contains
    # these architectural facts; reproduce them exactly, do not normalize,
    # narrow, or restyle them: [facts]. These are existing structural truths,
    # not design choices." (V1/V2/V3 paths shared). For FV the MODE_CONTRACT
    # already covers the "reproduce exactly / do not modify" intent, so the
    # verbose wrapper is replaced inline by "PHOTO FACTS TO RESPECT: [facts]".
    # Saves ~150 chars per prompt. V2/V3 paths keep the original wording.
    # TRUST PIXELS (2026-06-13) — at V1 fidelity=high the source IS the
    # architectural truth (pixel-anchored), and the MODE_CONTRACT already
    # carries the generic preservation rule. Injecting the per-photo enumerated
    # facts only adds a hallucination vector: a mis-read "painted door" / "wall"
    # in the token overrides the clean pixels. So DROP the enumeration on
    # pixel-anchored V1 — rely on pixels + the generic contract. The token is
    # still captured + persisted for the low-fidelity SWITCH paths (where text
    # is the only guard).
    # SWITCH_REDESIGN_PILOT — on a redesign SWITCH, KEEP the structural-identity
    # enumeration (the openings/facts text guard). The switch runs at LOW fidelity
    # on V1's AI render, so dropping the enumeration (TRUST_PIXELS, meant for the
    # pixel-anchored real V1) left the back openings unguarded → they got closed
    # (V2-V4). Forcing it back is switch-only; real V1 keeps trust-pixels.
    _trust_pixels = (
        _pixel_anchored
        and os.environ.get("TRUST_PIXELS_V1", "1") != "0"
        and not switch_redesign
    )
    structural_identity_fv = (
        "" if _trust_pixels
        else _compact_structural_identity_wrapper(structural_identity)
    )

    # Wave 4.7.1 R1: concrete image-specific structural anchors for FIRST_VISION.
    # detect_anchors() is deterministic text matching (no ML, no latency, no vision
    # reintroduction) over room_description. Output is descriptive-only,
    # architecture-only, <=185 chars, no atmosphere/generation verbs; empty clause
    # when no description/anchors → zero prompt cost. This mirrors the V2 anchor
    # wiring so V1 is no longer LESS spatially anchored than V2 — the dominant
    # remaining structural-fidelity-variance cause per the 4.7.1 audit.
    fv_anchor_profile = detect_anchors(room_description)
    if fv_anchor_profile.anchors:
        log.info("[AnchorDetect] mode=FIRST_VISION  anchors=%s", list(fv_anchor_profile.anchors))
    fv_anchor_clause = fv_anchor_profile.clause
    # Wave 4.6.1: source="" — vision analysis text reinterprets the room before generation,
    # destroying fidelity. input_fidelity=high + image upload makes the image the source of truth.
    source = ""
    intel_block, used_dna = _design_intelligence_block(atmosphere_id, room_type, dna, style_label, generation_mode)
    # DNA_CLEANUP_V1 — strip spatial micro-rules + de-dup TV + lighten "existing"
    # in the DNA room text (keep all decor items). Reduces the "recompute the
    # room" pressure that closes openings / invents walls. FIRST_VISION, all rooms.
    if os.environ.get("DNA_CLEANUP_V1", "1") != "0":
        intel_block = _dna_cleanup_v1(intel_block)

    # DEV compact mode: skip all P4 enrichments, use compact realism.
    # Wave 5.13f: wow_directive (TRANSFORMATION AMBITION) and natural_enrichment
    # were redundant with the new MODE_CONTRACT — removed from FIRST_VISION.
    # scene_completion stays only for the non-DNA fallback path (rare in
    # production where all 7 atmospheres have full DNA).
    if compact_prompts:
        completion_block = ""
        completeness = ""
        realism = build_compact_realism_block()
    elif used_dna:
        completion_block = ""
        completeness = ""  # Wave 4.6.0: DNA handles richness; empty string filtered by budget system
        realism = build_compact_realism_block()
    else:
        # Non-DNA fallback path: scene_completion provides the element checklist
        # (kept because the fallback lacks DNA's furnishing language).
        completion_block = build_scene_completion(room_type, atmosphere_id)
        completeness = ""  # Wave 4.7.1 R2: unified with DNA path
        realism = build_compact_realism_block()

    vs_block = ""
    if secondary_visible_spaces:
        vs_block = build_visible_spaces_block(atmosphere_id, secondary_visible_spaces) or ""

    # Wave 5.13f — design_direction was a placeholder ("Generate the first
    # architectural vision for this space.") on iteration=1. Removed entirely
    # from FIRST_VISION since the MODE_CONTRACT already states intent.

    # Wave 5.5.18 — revive dormant DNA fields (room_specific_constraints +
    # visible_transition_logic). Bimodal-gated to creative-mode only in v1.
    # Returns "" for default + preserve → byte-identical baseline.
    # Wave 5.5.32 — gate through apply_bimodal so per-atmosphere strips
    # neutralise architectural directives that previously bypassed.
    fv_room_dna = get_room_dna(atmosphere_id, room_type)
    dna_context_fv = build_dna_room_context_signal(fv_room_dna, generation_mode)
    dna_context_fv = apply_bimodal(dna_context_fv, atmosphere_id, generation_mode)
    # DNA_CLEANUP_V1 — also clean the ROOM CONTEXT (TV placement micro-rule +
    # TV de-duplication).
    if os.environ.get("DNA_CLEANUP_V1", "1") != "0":
        dna_context_fv = _dna_cleanup_v1(dna_context_fv)

    # Wave 5.13f — FIRST_VISION assembly:
    # MODE_CONTRACT (single authoritative preserve/creative contract) +
    # STRUCTURAL_IDENTITY (vision-captured facts, compact wrapper) +
    # design_intel (atmosphere DNA) + dna_room_context (TV anchor + visible
    # continuity merged into ROOM DESIGN) + realism + P5 enrichments.
    #
    # Removed from FIRST_VISION (now subsumed by MODE_CONTRACT):
    #   task, full_contract, openings_anchor, structural_negative_anchors,
    #   wow_directive (TRANSFORMATION AMBITION), natural_enrichment,
    #   atmosphere_dna_boundary, design_direction (placeholder filler).
    # STYLE_REFINEMENT and STRUCTURAL_TRANSFORMATION paths are untouched
    # in this wave.
    # Wave 6.1 — Decorative Foundation pilot (WM + Living + FV + preserve only).
    # Both helpers return "" outside the strict pilot gate. Order matters :
    # anchor_rule is placed BEFORE staging_manifest so the model reads
    # "decoration anchors on existing surfaces" before reading the dense
    # manifest of staging items. Same-prompt safety net.
    _wave61_em_value = mode.value if hasattr(mode, "value") else str(mode)
    decoration_anchor_block = build_decoration_anchor_rule(
        atmosphere_id, room_type or "", generation_mode, _wave61_em_value
    )
    staging_manifest_block = build_staging_manifest(
        atmosphere_id, room_type or "", generation_mode, _wave61_em_value
    )
    if decoration_anchor_block or staging_manifest_block:
        log.info(
            "[Wave6.1] decorative pilot ACTIVE  atm=%s  room=%s  mode=%s  "
            "anchor_chars=%d  manifest_chars=%d",
            atmosphere_id, room_type, generation_mode,
            len(decoration_anchor_block), len(staging_manifest_block),
        )

    raw_sections = [
        ("mode_contract", mode_contract),         # P1 — Wave 5.13f: single authoritative MODE_CONTRACT
        ("structural_identity", structural_identity_fv),  # P1 — Wave 4.7.2 facts + Wave 5.13f compact wrapper
        ("architectural_anchors", fv_anchor_clause),  # P1 — Wave 4.7.1 R1: concrete image anchors (text-derived)
        ("source_space", source),                  # P1 — source="" in FV (Wave 4.6.1)
        ("design_intel", intel_block),
        ("dna_room_context", dna_context_fv),     # P3 — Wave 5.5.18 dormant fields revival (TV anchor + visible continuity)
        # Wave 6.1 — Decorative Foundation pilot sections (gated to
        # WM-Living-FV-preserve ; "" everywhere else → byte-identical for
        # any non-pilot call). Anchor rule first (P3 — safety), manifest
        # second (P4 — content). Placed after DNA so the staging vocabulary
        # builds on top of the atmosphere's furniture_language rather than
        # competing with it.
        ("decoration_anchor_rule", decoration_anchor_block),
        ("staging_manifest", staging_manifest_block),
        ("interior_completeness", completeness),   # P5 — drops first (Wave 4.4.1: was P4)
        ("scene_completion", completion_block),    # P4 — non-DNA fallback path only
        ("visible_spaces", vs_block),
        # Wave 5.5.15c — per-atmosphere creative emotional signal (P5, BIMODAL-gated).
        ("emotional_realism", build_emotional_realism_signal(generation_mode, atmosphere_id)),
        # Wave 5.5.16 — geometry-attached furnishing semantics (P5, BIMODAL-gated).
        ("geometry_attached_furnishing", build_furnishing_signal(generation_mode, room_type)),
        ("compact_realism", realism),              # P3 — compact realism block
        # Wave 5.14A Fix — editorial_realism gated on the caller's intent.
        # True for direct V1 calls (main.py iteration=1 with full quality=medium
        # + fidelity=high params). False for composer_v2 REBOOT_FRESH delegation
        # which keeps main.py's STYLE_REFINEMENT classification → quality=low
        # + fidelity=OMIT — editorial degrades crispness at those params.
        ("editorial_realism",
         build_editorial_realism_block() if editorial_realism_enabled else ""),
        # Wave 5.14A Last-Chance Step 2 (2026-06-02, TEMPORARY) — re-introduce
        # Wave 5.14B Photographic Credibility ONLY in combination with the
        # quality=low override (main.py Wave 5.14A Last-Chance block).
        # Hypothesis : 5.14B regressed at quality=medium (Wave 5.14B Step 1
        # — render became flat/bland under cumulative "natural/subtle/uniform"
        # pressure on already-detailed medium render), but at quality=low
        # (pictorial smoothing baseline) the same cues may COMPENSATE the
        # "very drawn / illustrated" feel reported by user on quality=low
        # alone. Different rendering regime ⇒ different cue interaction.
        # REVERT = re-comment the tuple below.
        ("photographic_credibility",
         build_photographic_credibility_block() if editorial_realism_enabled else ""),
    ]
    _audit("FIRST_VISION", raw_sections)
    prompt, dropped = _assemble_with_budget("FIRST_VISION", raw_sections)
    log.info(
        "[Prompt Budget] mode=FIRST_VISION  budget=%d  actual=%d  "
        "compression_applied=%s  removed_sections=%s",
        _MODE_BUDGETS["FIRST_VISION"], len(prompt), bool(dropped), dropped or [],
    )
    return prompt


def compose_result_message(
    style_label: str,
    iteration: int,
    refinement_state: RefinementState,
    edit_mode: EditMode = EditMode.FIRST_VISION,
) -> str:
    """
    Generate the AI companion message that appears below the result image.
    This is conversational and specific to what changed — not generic.
    """
    style_name = style_label.split("·")[0].strip()

    if iteration == 1:
        return (
            f"Here's your {style_name} transformation — Vision 1. "
            "The architecture of your space is preserved; the new aesthetic "
            "lives in the materials, light, and spatial layering. "
            "Want to push further, or shift direction entirely?"
        )

    if edit_mode == EditMode.LOCAL_EDIT:
        latest = refinement_state.latest[:80] if refinement_state.latest else "your edit"
        return (
            f"Vision {iteration} — applied: '{latest}'. "
            "The structure and composition are preserved. "
            "What else would you like to change?"
        )

    if edit_mode == EditMode.STRUCTURAL_TRANSFORMATION:
        return (
            f"Vision {iteration} — architectural evolution applied. "
            "Tell me what to push further, or refine the details."
        )

    # STYLE_REFINEMENT and fallback
    what_changed = []
    if refinement_state.enhance:
        what_changed.append(f"enhanced {refinement_state.enhance[-1][:50]}")
    if refinement_state.add:
        what_changed.append(f"added {refinement_state.add[-1][:50]}")
    if refinement_state.remove:
        what_changed.append(f"reduced {refinement_state.remove[-1][:50]}")
    if refinement_state.keep:
        what_changed.append(f"preserved {refinement_state.keep[-1][:50]}")

    if what_changed:
        changes = ", ".join(what_changed)
        return (
            f"Vision {iteration} — {changes}. "
            "Each iteration builds on the last. "
            "Tell me what to push next, or we can explore a completely different direction."
        )

    if refinement_state.latest:
        return (
            f"Vision {iteration} — applied your direction: '{refinement_state.latest[:80]}'. "
            "Want to refine further or change course?"
        )

    return (
        f"Vision {iteration} — the {style_name} direction, pushed further. "
        "Each generation deepens the design intent. What do you want to change next?"
    )
