# First Vision Philosophy Refocus

**Version:** Wave 4.5.1  
**Purpose:** Documents the FIRST_VISION philosophy shift from "architectural reconstruction + luxury redesign" to "Premium Restyling Overlay."

---

## Problem Statement

PROD testing revealed that despite `input_fidelity=high`, the structural mask, and the `SAME APARTMENT` task framing, the system was producing outputs that felt more like "AI-generated luxury apartment in this style" than "real apartment transformed by a luxury designer."

The uploaded photo was being treated as **inspiration** — a layout to improve and recompose — rather than as the **dominant source of truth**.

**The target experience is:**
> "A luxury interior designer transformed the REAL photographed apartment."

**NOT:**
> "An AI generated a new luxury apartment inspired by the uploaded room."

---

## Root Cause Analysis

Two prompt signals were over-amplifying compositional authority:

### 1. WOW Directive — "editorial redesign" framing

**Before (Wave 4.3.1):**
```
TRANSFORMATION AMBITION — editorial redesign of THIS apartment, not a new one.
Visible architecture stays recognizable: windows, openings, partitions, equipment.
WOW: materials, lighting, furniture, atmosphere — not reinvention.
Transform the character fully.
```

Issues:
- "editorial redesign" signals license to recompose the image
- "Transform the character fully" pushes the model toward wholesale replacement rather than restyling

### 2. DNA STYLE Key — prescriptive without qualification

**Before (Wave 4.3+):**
```
ROOM (Living Room): honed marble, brushed brass, ivory bouclé.
LIGHT: ... STYLE: deep curved bouclé sofa in ivory; honed marble coffee table; ...
```

Issue:
- `STYLE:` prefix carries no qualification — model treats furniture list as compositional direction
- Creates tension between "use these specific pieces" and "preserve the uploaded furniture"

---

## Changes Made

### 1. New WOW Directive: `build_restyling_wow_directive()`

**After (Wave 4.5.1):**
```
TRANSFORMATION AMBITION — premium restyling of THIS exact apartment photo, not a new apartment.
Visible architecture stays recognizable: windows, openings, partitions, existing equipment.
WOW through: materials, finishes, lighting quality, furniture styling, atmosphere conviction.
Decorate this photo — do not recompose it.
```

Changes:
- "editorial redesign" → "premium restyling" — softer, styling-focused
- "not a new one" → "not a new apartment" — more explicit
- "Transform the character fully" → "Decorate this photo — do not recompose it." — direct constraint
- "Visible architecture stays recognizable" preserved verbatim (load-bearing vocabulary)
- "TRANSFORMATION AMBITION" preserved verbatim (load-bearing for quality validators)

`build_first_vision_wow_directive()` preserved unchanged for backward compat with validators.

### 2. DNA STYLE Key Qualification

**After (Wave 4.5.1):**
```
ATMOSPHERE STYLE (restyle existing elements): deep curved bouclé sofa in ivory; ...
```

Changes:
- `STYLE:` → `ATMOSPHERE STYLE (restyle existing elements):`
- Signals the furniture list is aspirational atmosphere guidance, not compositional instruction
- Content unchanged — all DNA furniture/decor items preserved

---

## What Was NOT Changed

| System | Status | Reason |
|--------|--------|--------|
| `TRANSFORMATION AMBITION` vocabulary | PRESERVED | Required by validators; still present in new directive |
| `Visible architecture stays recognizable` | PRESERVED | Load-bearing exact match in validators |
| `input_fidelity=high` | UNCHANGED | Primary fidelity mechanism — API level |
| Structural mask | UNCHANGED | Pixel-level perimeter protection |
| `SAME APARTMENT` task framing | UNCHANGED | Mental model anchor |
| Atmosphere DNA content | UNCHANGED | Creative quality driver — furniture list, materials, lighting |
| `compact_realism` block | UNCHANGED | Anti-CGI quality floor |
| `build_first_vision_wow_directive()` | UNCHANGED | Backward compat with Wave 4.3.1–4.4.x validators |
| Budget system | UNCHANGED | All priorities and budgets preserved |
| All other prompt paths | UNCHANGED | SR, Structural, Local Edit unaffected |

---

## Why Visual Quality Should Remain High

The DNA blocks continue to specify:
- Exact material palette (honed marble, brushed brass, ivory bouclé, etc.)
- Lighting behavior (warm golden pools, diffused ambient, etc.)
- Atmosphere emotional character
- Room-specific decor language

The `compact_realism` block continues to enforce:
- NOT a CGI render
- DSLR real estate photograph quality
- Real materials, natural light physics

The `build_simplified_fv_contract()` (Tier 1.5) continues to enforce:
- CAMERA LOCK — geometry is fixed
- STRUCTURAL LOCK — windows, doors, walls unchanged
- ATMOSPHERE BOUNDARY — geometry overrides atmosphere

The only signals reduced were those that pushed the model toward recomposition rather than restyling. All signals that drive luxury quality, premium materials, and atmosphere conviction remain at full strength.

---

## Expected Behavioral Change

| Behavior | Before | After |
|----------|--------|-------|
| Furniture replacement | Model may swap all furniture | Model restyled existing furniture to match atmosphere |
| Spatial composition | Model may recompose spatial flow | Model preserves uploaded spatial composition |
| Material surfaces | Materials applied to correct surfaces | Materials applied to correct surfaces (unchanged) |
| Atmosphere conviction | Strong | Strong (unchanged — driven by DNA) |
| Luxury quality | High | High (unchanged — driven by realism + DNA) |
| Architecture fidelity | Mixed (mask helps) | Improved — less "editorial redesign" permission |

---

## Residual Limitations

- The DNA furniture list is still specific (e.g., "deep curved bouclé sofa in ivory"). The model may still introduce new pieces.
- `ATMOSPHERE STYLE (restyle existing elements):` is guidance, not a hard constraint.
- For rooms where the uploaded furniture is very different from the DNA furniture language (e.g., minimalist uploaded room + Soft Luxury DNA), the model must interpret "restyle" vs. "replace."
- Full validation requires PROD testing with the benchmark apartment set.

---

## Future Candidates (Wave 4.6+)

1. **DNA furniture list softening** — change from specific pieces to material/form language: "bouclé seating in warm tones" instead of "deep curved bouclé sofa in ivory or blush"
2. **Source photo description injection** — explicitly list the uploaded furniture from vision analysis, frame DNA as styling guidance for those specific pieces
3. **Explicit "keep existing furniture layout" instruction** — add to Tier 1.5 contract
