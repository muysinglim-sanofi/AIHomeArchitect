"""
Wave 5.4b — Trim audit harness.

Decomposes each V1 prompt (scenarios A/B/C/F from wave_5_2b_prompts_raw.txt)
into sections, tabulates per-atmosphere sizes, and quantifies trim candidates.

Read-only.
"""

from __future__ import annotations
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "wave_5_2b_prompts_raw.txt")

# Section detection patterns — heuristic match on the leading marker.
# composer.py joins sections with single \n (not \n\n), so we split on \n
# and identify each section by its prefix.
SECTION_PREFIXES = [
    ("task",                    "SAME APARTMENT PHOTO-EDIT"),
    ("camera+structural+atmosphere_boundary", "CAMERA LOCK"),
    ("openings_anchor",         "OPENINGS ANCHOR"),
    ("structural_identity",     "STRUCTURAL IDENTITY"),
    ("structural_negative_anchors", "STRUCTURAL NEGATIVE ANCHORS"),
    ("architectural_anchors",   "ARCHITECTURAL ANCHORS"),
    ("atmosphere",              "ATMOSPHERE ("),
    ("room",                    "ROOM ("),
    ("wow_directive",           "TRANSFORMATION AMBITION"),
    ("natural_enrichment",      "NATURAL ENRICHMENT"),
    ("visible_spaces",          "VISIBLE SPACES"),
    ("design_direction",        "DESIGN DIRECTION"),
    ("compact_realism",         "NOT a CGI"),
]


def _parse_v1(scenario_block: str) -> dict[str, str]:
    """Extract the V1 raw prompt and break into sections."""
    m = re.search(r">>> RAW v1:\n(.*?)\n<<< end v1", scenario_block, re.S)
    if not m:
        return {}
    prompt = m.group(1)
    lines = prompt.split("\n")
    sections: dict[str, list[str]] = {name: [] for name, _ in SECTION_PREFIXES}
    current = None
    for line in lines:
        matched = False
        for name, prefix in SECTION_PREFIXES:
            if line.startswith(prefix):
                current = name
                sections[current].append(line)
                matched = True
                break
        if not matched and current is not None:
            sections[current].append(line)
    return {name: "\n".join(lines) for name, lines in sections.items() if lines}


def _scenario_label_short(label: str) -> str:
    if label.startswith("A "): return "Warm Modern"
    if label.startswith("B "): return "Japandi Calm"
    if label.startswith("C "): return "Bali Sanctuary"
    if label.startswith("F"):  return "Japandi (simple)"
    return label[:20]


def main() -> None:
    with open(SRC, encoding="utf-8") as f:
        txt = f.read()
    blocks = re.split(r"={100}\nSCENARIO ", txt)[1:]

    v1_per_atm: dict[str, dict[str, str]] = {}
    for b in blocks:
        head = b.split("\n")[0].strip()
        if head[:1] not in ("A", "B", "C", "F"):
            continue
        sections = _parse_v1(b)
        if sections:
            v1_per_atm[_scenario_label_short(head)] = sections

    out = io.StringIO()
    out.write("=" * 100 + "\n")
    out.write("WAVE 5.4b — V1 prompt size decomposition by section, per atmosphere\n")
    out.write("=" * 100 + "\n\n")

    # Header row
    atm_names = list(v1_per_atm.keys())
    col_w = 18
    header = f"{'Section':40} | " + " | ".join(f"{a:>{col_w}}" for a in atm_names)
    out.write(header + "\n")
    out.write("-" * len(header) + "\n")

    # One row per section
    total_per_atm: dict[str, int] = {a: 0 for a in atm_names}
    for name, _ in SECTION_PREFIXES:
        cells = []
        for atm in atm_names:
            sec_txt = v1_per_atm[atm].get(name, "")
            n = len(sec_txt)
            total_per_atm[atm] += n
            cells.append(f"{n:>{col_w}}" if n else f"{'-':>{col_w}}")
        out.write(f"{name:40} | " + " | ".join(cells) + "\n")
    out.write("-" * len(header) + "\n")
    out.write(f"{'TOTAL':40} | " + " | ".join(f"{total_per_atm[a]:>{col_w}}" for a in atm_names) + "\n")
    out.write("\n")

    # Detailed inspection of each candidate's contents for the Warm Modern V1
    target = "Warm Modern"
    out.write("=" * 100 + "\n")
    out.write(f"DETAILED CONTENT — {target} V1 (the trim audit's reference apartment)\n")
    out.write("=" * 100 + "\n\n")
    for name, _ in SECTION_PREFIXES:
        sec = v1_per_atm.get(target, {}).get(name, "")
        if not sec:
            continue
        out.write(f"--- [{name}] ({len(sec)} chars) ---\n")
        out.write(sec + "\n\n")

    # Trim candidate analysis — per-atmosphere chars saved
    out.write("=" * 100 + "\n")
    out.write("TRIM CANDIDATE QUANTIFICATION\n")
    out.write("=" * 100 + "\n\n")

    candidates = [
        # (name, description, fn(section_text) → chars saved estimate, target sections)
        ("C1: shorten wow_directive opening list", [
            "wow_directive",
            "Keep architecture-recognition clause ('windows, openings, partitions, existing equipment' — load-bearing). Trim the duplicated 'do not recompose' (already in task) and the redundant 'premium photo-edit / not a new apartment' which repeats the task framing. Estimated savings: ~120-180 chars."
        ]),
        ("C2: shorten NATURAL ENRICHMENT", [
            "natural_enrichment",
            "Trim the example list ('plants, floor lamp, cushions, textiles, hospitality accessories, TV if appropriate'). Keep the directive 'enrich, do not recompose'. Estimated savings: ~80-120 chars."
        ]),
        ("C3: strip atmosphere bracket tag", [
            "atmosphere",
            "Remove the trailing '[Boutique hotel / premium urban residence]' marketing tag — purely decorative, no spatial/atmospheric instruction. Estimated savings: ~35-55 chars per V1."
        ]),
        ("C4: fix double-period typos in atmosphere DNA", [
            "atmosphere",
            "Many DNA lines end in 'unhurried..' / 'urban premium living..' (double period). Cosmetic, near-zero savings (~10 chars total) but worth doing if we open the DNA freeze for other reasons."
        ]),
        ("C5: dedup 'SAME APARTMENT' phrasing between task + wow_directive", [
            "task,wow_directive",
            "task says 'SAME APARTMENT PHOTO-EDIT — apply X atmosphere. The photo defines spatial truth...' AND wow_directive says 'premium photo-edit of THIS exact apartment, not a new apartment'. Two voices of the same idea. Drop one of the two redundant 'apartment' framings. Estimated savings: ~80-120 chars."
        ]),
        ("C6: drop empty DESIGN DIRECTION line", [
            "design_direction",
            "V1 has user_instruction=='' so DESIGN DIRECTION is not emitted in the assembled prompt (composer.py filters empty sections). Zero savings — already optimal. CONFIRM."
        ]),
        ("C7: shorten ROOM block AVOID list", [
            "room",
            "Each ROOM block ends with 'AVOID: <room-specific avoid items>, <atmosphere core forbidden items>'. The 5-item room-specific AVOID + 2-item atmosphere-forbidden gives ~7 items. Trimming to 4 most distinctive items could save 50-100 chars per atmosphere. DNA-frozen file though — requires freeze exception."
        ]),
        ("C8: simplify ATMOSPHERE STYLE prefix", [
            "room",
            "Each ROOM block contains 'ATMOSPHERE STYLE (restyle existing elements):' — the parenthetical is redundant since the task already says 'Restyle only'. Save ~30 chars per V1. DNA-frozen — requires freeze exception."
        ]),
        ("C9: shorten REALISM constraints", [
            "room",
            "Each ROOM block ends with REALISM: <2 constraints>. Some are highly specific (e.g. 'sofa low — 40-45 cm — Balinese floor-culture scale'). Keeping them is fine; consider only if other trims aren't enough. Estimated savings: 30-60 chars per atmosphere. DNA-frozen."
        ]),
    ]

    for name, body in candidates:
        out.write(f"• {name}\n")
        out.write(f"  Target sections : {body[0]}\n")
        out.write(f"  Analysis : {body[1]}\n\n")

    # Confirm DESIGN DIRECTION is empty
    out.write("=" * 100 + "\n")
    out.write("EMPTY-SECTION CHECK on V1 (these contribute 0 chars in current state)\n")
    out.write("=" * 100 + "\n\n")
    for atm in atm_names:
        present = list(v1_per_atm[atm].keys())
        missing = [name for name, _ in SECTION_PREFIXES if name not in present]
        out.write(f"  {atm:20} missing sections: {missing}\n")
    out.write("\n")

    # Visible spaces specifically
    out.write("VISIBLE_SPACES per atmosphere (this is the kitchen-continuity section, ~241 chars):\n")
    for atm in atm_names:
        v = v1_per_atm[atm].get("visible_spaces", "")
        out.write(f"  {atm:20}  {'PRESENT (' + str(len(v)) + ' chars)' if v else 'ABSENT'}\n")
    out.write("\n")

    path = os.path.join(HERE, "wave_5_4b_trim_audit.txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write(out.getvalue())
    print(f"Wrote {path}  ({os.path.getsize(path):,} bytes)")


if __name__ == "__main__":
    main()
