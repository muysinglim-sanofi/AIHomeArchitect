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
log = logging.getLogger("aih")

from .style_dna import StyleDNA, get_style
from .preservation import (
    build_structural_contract,
    build_continuation_contract,
    build_structural_evolution_contract,
    build_atmosphere_switch_contract,
    build_simplified_fv_contract,
)
from .anchor_detector import detect_anchors
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
    build_medium_realism_block,
    build_interior_completeness_rule,
)
from .edit_intent import (
    EditMode,
    classify_edit_mode,
    build_local_edit_prompt,
    build_style_refinement_header,
    build_structural_transformation_header,
)
from .atmosphere_dna import get_room_dna, build_dna_block, label_to_atmosphere_id
from .atmosphere_dna.bimodal_classifier import apply_bimodal, inject_creative_revival  # Wave 5.5.14c/d — no-op unless BIMODAL_ENABLED=1
from .visible_space_logic import build_visible_spaces_block

# ── Budget system ─────────────────────────────────────────────────────────────

_MODE_BUDGETS: dict[str, int] = {
    "FIRST_VISION": 4000,  # Wave 5.5.14g (richness reinvestment): raised 3850→4000 (hard ceiling). Rationale: Wave 5.5.14f freed ~445 chars in preserve mode by dropping 3 boundary voices, but Wave 5.5.14d's creative mode ADDS ~250-300 chars (dormant DNA revival + REIMAGINED framing). Measured tightest creative margin: Tropical Escape at +11 above 3850 → unsafe for real-world prompts with descriptions or extra visible spaces. Raising to the matrix hard ceiling 4000 gives creative mode +130-360 margin while letting preserve mode's P4/P5 sections (natural_enrichment, visible_spaces, design_direction) thrive on rich prompts. No new content added — just headroom for existing sections to survive budget. Default (BIMODAL_ENABLED unset) prompts stay well under any cap. Wave 5.5.3 lineage: 3550→3850 to seat C3 boundary; Wave 5.5.14g: 3850→4000 to seat creative revival headroom.
    # Wave 4.8.2: raised 2400→3500 / 2500→3600. The 4.8.1a audit proved the
    # (legitimately grown 4.6–4.7) P1 preservation/continuity stack alone
    # (~2528 / ~2601) exceeded the old 2400/2500 caps, silently evicting
    # design_intel (atmosphere DNA) + compact_realism. Combined with the 4.8.2
    # header de-duplication, these right-sized budgets let de-duped-P1 + full
    # DNA + realism survive (only P5 refinement memory drops). Still below V1
    # (3550) and the 4000 hard ceiling — quality restoration, not inflation.
    "STYLE_REFINEMENT": 3500,
    "STRUCTURAL_TRANSFORMATION": 3600,
    "LOCAL_EDIT": 1500,
}

# P5 dropped first; P1 never dropped. Unknown sections default to P3 (realism tier).
_SECTION_PRIORITY: dict[str, int] = {
    # P1 — structural anchors and task framing (never dropped)
    "task": 1,
    "header": 1,
    "edit_block": 1,
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
    # P3 — realism quality floor
    "full_realism": 3,
    "compact_realism": 3,
    # P4 — dream richness / scene enrichment
    # P5 — interior completeness (nice-to-have; drops before wow_directive — Wave 4.4.1)
    "interior_completeness": 5,
    "scene_completion": 4,
    "dream_addendum": 4,
    "dream_micro": 4,
    "wow_directive": 4,   # Wave 4.3.1 — FIRST_VISION transformation ambition
    "natural_enrichment": 4,  # Wave 4.6.2 — light natural decoration (FIRST_VISION only)
    # P5 — optional enrichment context (dropped first)
    "visible_spaces": 5,
    "refinement_memory": 5,
    "design_direction": 5,
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
    """
    dna = get_style(style_label)
    atmosphere_id = label_to_atmosphere_id(style_label)
    refinement_state = parse_history(history, iteration)
    mode = classify_edit_mode(user_instruction, iteration)

    log.info("  edit_mode: %s  atmosphere: %s  room: %s", mode.value, atmosphere_id, room_type or "(none)")

    # ── Path A: LOCAL EDIT ────────────────────────────────────────────────────
    if mode == EditMode.LOCAL_EDIT:
        edit_block = build_local_edit_prompt(
            user_instruction=user_instruction,
            style_name=dna.name,
            room_type=room_type,
            room_description=room_description,
        )
        realism = build_compact_realism_block()
        raw_sections = [("edit_block", edit_block), ("compact_realism", realism)]
        _audit("LOCAL_EDIT", raw_sections)
        prompt, dropped = _assemble_with_budget("LOCAL_EDIT", raw_sections)
        log.info(
            "[Prompt Budget] mode=LOCAL_EDIT  budget=%d  actual=%d  "
            "compression_applied=%s  removed_sections=%s",
            _MODE_BUDGETS["LOCAL_EDIT"], len(prompt), bool(dropped), dropped or [],
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

        raw_sections = [
            ("header", header),
            ("source_continuity", source_continuity),  # P1 — Wave 4.7.3: continue from current design vs restart
            ("atmosphere_contract", contract),
            ("structural_identity", structural_identity),  # P1 — Wave 4.7.2: same persistent identity as V1
            ("structural_negative_anchors", structural_negative_anchors),  # P1 — Wave 4.7.4: no-new-wall topology
            ("authorized_user_changes", authorized_user_changes),  # P1.5 — Wave 4.7.5: local user authority
            ("source_space", source),
            ("design_intel", intel_block),
            (dream_key, dream_block),
            ("visible_spaces", vs_block),
            ("refinement_memory", refinement_block),
            ("compact_realism", realism),
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

        raw_sections = [
            ("header", header),
            ("source_continuity", source_continuity),  # P1 — Wave 4.7.3: continue from current design vs restart
            ("evolution_contract", contract),
            ("structural_identity", structural_identity),  # P1 — Wave 4.7.2: same identity; only the explicit edit may alter it
            ("structural_negative_anchors", structural_negative_anchors),  # P1 — Wave 4.7.4: no-new-wall topology
            ("authorized_user_changes", authorized_user_changes),  # P1.5 — Wave 4.7.5: local user authority
            ("source_space", source),
            ("design_intel", intel_block),
            ("refinement_memory", refinement_block),
            ("compact_realism", realism),
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
    # Wave 4.3.3: reconstruction-first task framing via fidelity_layer.
    # Replaces "REDESIGN —" (Wave 4.3.1) with "SAME APARTMENT — reconstruct then transform".
    # Establishes spatial truth from the input photo before any atmosphere instruction.
    # Wave 4.5.0: uses build_simplified_fv_contract() (Tier 1.5, ~820 chars) instead
    # of build_structural_contract() (Tier 1, ~1550 chars). All required vocabulary
    # preserved; redundant defensive prose removed. Saves ~730 chars per prompt.
    room_ctx = f" {room_type}" if room_type else ""
    # Wave 5.5.14f — task suffix (voice #1) trims in preserve mode when
    # BIMODAL_ENABLED is on. Default + creative paths emit the full string
    # → byte-identical to pre-5.5.14f.
    task = build_first_vision_task(dna.name, room_ctx, generation_mode)

    contract = build_simplified_fv_contract(room_type, generation_mode)  # Wave 4.5.0 / 5.5.14d
    openings_anchor = build_openings_anchor(generation_mode)  # Wave 4.6.2 / 5.5.14d
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

    # DEV compact mode: skip all P4 enrichments, use compact realism.
    # PROD mode: wow_directive replaces dream_micro/addendum (Wave 4.3.1).
    if compact_prompts:
        completion_block = ""
        wow_block = ""
        natural_enrichment = ""  # Wave 4.6.2: skip P4 enrichments in compact mode
        completeness = ""
        realism = build_compact_realism_block()
    elif used_dna:
        # DNA path: wow_directive replaces dream_micro — expresses transformation
        # ambition that dream_micro's richness note did not carry.
        # Wave 4.4.1: compact realism (133 chars) frees budget for wow_directive vs medium (325 chars).
        # Wave 4.5.1: restyling_wow_directive — photo-first framing, no "editorial redesign".
        # Wave 4.6.0: completeness="" — DNA handles furnishing richness; "never sparse/empty"
        # contradicts photo-first when uploaded room is intentionally minimal.
        # Wave 4.6.1: build_photo_edit_wow_directive() — "photo edit" framing, no "furniture styling".
        # Wave 4.6.2: natural_enrichment added (P4) — light accessory layering, no composition.
        completion_block = ""
        wow_block = build_photo_edit_wow_directive(generation_mode)
        natural_enrichment = build_natural_enrichment()
        completeness = ""  # Wave 4.6.0: DNA handles richness; empty string filtered by budget system
        realism = build_compact_realism_block()
    else:
        # Non-DNA path: scene_completion provides the element checklist;
        # wow_directive adds the transformation ambition layer (was absent before 4.3.1).
        # Wave 4.4.1: compact realism — same budget saving as DNA path.
        # Wave 4.6.1: build_photo_edit_wow_directive() — consistent photo-edit framing.
        # Wave 4.6.2: natural_enrichment added (P4) — light accessory layering.
        # Wave 4.7.1 R2: completeness="" — unify with the DNA path. The non-DNA
        # fallback previously injected INTERIOR COMPLETENESS ("never sparse...
        # every major functional zone completed"), composition-authoritative
        # spatial-completion pressure absent from the DNA path. Same image + same
        # atmosphere must not yield different structural behaviour. Premium
        # richness now comes from material/lighting/atmosphere, not spatial
        # completion. build_interior_completeness_rule stays imported (still used
        # by validator harnesses); only the FIRST_VISION usage is removed.
        completion_block = build_scene_completion(room_type, atmosphere_id)
        wow_block = build_photo_edit_wow_directive(generation_mode)
        natural_enrichment = build_natural_enrichment()
        completeness = ""  # Wave 4.7.1 R2: unified with DNA path (was build_interior_completeness_rule())
        realism = build_compact_realism_block()

    vs_block = ""
    if secondary_visible_spaces:
        vs_block = build_visible_spaces_block(atmosphere_id, secondary_visible_spaces) or ""

    direction = f"DESIGN DIRECTION: {user_instruction.strip()[:300]}" if user_instruction.strip() else ""

    # Wave 5.5.14f / Wave 5.5.14i — voice #3 (atmosphere DNA boundary) is
    # the middle counter-signal that arbitrates DNA-vs-photo conflict.
    #
    # - Preserve mode (5.5.14f): DNA architectural tokens stripped → section
    #   becomes defensive prose against a non-existent threat → drop.
    # - Creative mode (5.5.14i): section says "Preserve the photographed
    #   apartment's geometry exactly" which DIRECTLY CONTRADICTS the
    #   SAME SPACE REIMAGINED + ARCHITECTURAL MEMORY blocks earlier in the
    #   prompt. Was ankylosing creative outputs → drop.
    #
    # Default (BIMODAL_ENABLED unset): section emits in full → byte-
    # identical baseline.
    from .atmosphere_dna.bimodal_classifier import should_drop_boundary_voices
    dna_boundary = (
        "" if should_drop_boundary_voices(generation_mode)
        else build_atmosphere_dna_boundary()
    )

    raw_sections = [
        ("task", task),
        ("full_contract", contract),
        ("openings_anchor", openings_anchor),      # P1 — Wave 4.6.2: openings fidelity
        ("structural_identity", structural_identity),  # P1 — Wave 4.7.2: persistent concrete apartment identity
        ("structural_negative_anchors", structural_negative_anchors),  # P1 — Wave 4.7.4: no-new-wall topology
        ("architectural_anchors", fv_anchor_clause),  # P1 — Wave 4.7.1 R1: concrete image anchors (text-derived)
        ("source_space", source),                  # P1 — source="" in FV (Wave 4.6.1)
        ("design_intel", intel_block),
        ("atmosphere_dna_boundary", dna_boundary),  # P1 — Wave 5.5.3 / dropped by Wave 5.5.14f in preserve mode
        ("interior_completeness", completeness),   # P5 — drops first (Wave 4.4.1: was P4)
        ("scene_completion", completion_block),    # P4 — drops before wow_directive
        ("wow_directive", wow_block),              # P4 — most protected of the P4 group
        ("natural_enrichment", natural_enrichment),  # P4 — Wave 4.6.2: light natural decor
        ("visible_spaces", vs_block),
        ("design_direction", direction),
        ("compact_realism", realism),              # P3 — compact block (Wave 4.4.1: was full_realism/medium)
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
