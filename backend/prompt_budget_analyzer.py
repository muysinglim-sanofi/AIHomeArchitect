"""
Wave 4.4.1 — Prompt Budget Analyzer.

Simulates FIRST_VISION prompt assembly for all 10 atmospheres x 3 room types
and reports which sections survive compression and which are dropped.

PURPOSE:
  Provides visibility into budget arbitration — which sections consume the most
  budget, which drop under pressure, and what headroom remains. Informs future
  rebalancing decisions without requiring PROD OpenAI calls.

USAGE:
  cd backend
  python prompt_budget_analyzer.py [--source-length N]

  --source-length N   Simulate SOURCE SPACE with N characters (default: 200)

OUTPUT:
  Per-atmosphere-room analysis + summary compression table.
"""

import os
import sys
import argparse
import logging

logging.disable(logging.CRITICAL)
sys.path.insert(0, os.path.dirname(__file__))

from prompt_engine.fidelity_layer import build_first_vision_task
from prompt_engine.preservation import build_structural_contract
from prompt_engine.atmosphere_dna import (
    get_room_dna, build_dna_block, label_to_atmosphere_id,
)
from prompt_engine.wow_layer import build_first_vision_wow_directive
from prompt_engine.realism_layer import (
    build_compact_realism_block,
    build_medium_realism_block,
    build_interior_completeness_rule,
)
from prompt_engine.composer import (
    _SECTION_PRIORITY,
    _MODE_BUDGETS,
    _assemble_with_budget,
    _style_block,
)
from prompt_engine.style_dna import get_style


# ── Atmosphere registry ───────────────────────────────────────────────────────

_ATMOSPHERES = [
    ("warm_modern",       "Warm Modern · V2"),
    ("japandi_calm",      "Japandi · Harmony"),
    ("soft_luxury",       "Soft Luxury · Gold"),
    ("zen_retreat",       "Zen Retreat · Serenity"),
    ("nordic_warmth",     "Nordic Warmth · Dawn"),
    ("dark_contemporary", "Dark Contemporary · Noir"),
    ("nature_retreat",    "Nature Retreat · Forest"),
    ("desert_luxe",       "Desert Luxe · Dusk"),
    ("tropical_escape",   "Tropical Escape · Bloom"),
]

_ROOM_TYPES = ["living room", "master bedroom", "kitchen"]


# ── Section builder ───────────────────────────────────────────────────────────

def _build_fv_sections(
    atmosphere_id: str,
    style_label: str,
    room_type: str,
    source_length: int,
) -> list[tuple[str, str]]:
    """Build the FIRST_VISION raw_sections list for one atmosphere+room combination."""
    dna_name = style_label.split("·")[0].strip()
    room_ctx = f" {room_type}" if room_type else ""

    task = build_first_vision_task(dna_name, room_ctx)
    contract = build_structural_contract(room_type)
    source = ("SOURCE SPACE: " + "x" * source_length) if source_length > 0 else ""

    room_dna = get_room_dna(atmosphere_id, room_type)
    if room_dna:
        intel = build_dna_block(room_dna)
        used_dna = True
    else:
        # Fall back to style block (non-DNA path)
        try:
            dna = get_style(style_label)
            intel = _style_block(dna, style_label)
        except Exception:
            intel = f"STYLE ({dna_name}): design intelligence."
        used_dna = False

    wow = build_first_vision_wow_directive()
    completeness = build_interior_completeness_rule()
    realism = build_compact_realism_block()

    return [
        ("task", task),
        ("full_contract", contract),
        ("source_space", source),
        ("design_intel", intel),
        ("interior_completeness", completeness),
        ("scene_completion", ""),          # empty on DNA path
        ("wow_directive", wow),
        ("visible_spaces", ""),
        ("design_direction", ""),
        ("compact_realism", realism),
    ], used_dna


# ── Reporting helpers ─────────────────────────────────────────────────────────

def _section_sizes(sections: list[tuple[str, str]]) -> dict[str, int]:
    return {name: len(text) for name, text in sections if text}


def _pct(n: int, total: int) -> str:
    if total == 0:
        return "  0%"
    return f"{100*n//total:3d}%"


# ── Main analysis ─────────────────────────────────────────────────────────────

def analyze(source_length: int = 200) -> None:
    budget = _MODE_BUDGETS["FIRST_VISION"]
    print(f"\n{'='*80}")
    print(f"FIRST_VISION PROMPT BUDGET ANALYZER — Wave 4.4.1")
    print(f"Budget: {budget}  |  Source description length: {source_length} chars")
    print(f"{'='*80}\n")

    # Header
    col_atm  = 22
    col_room = 14
    col_dna  = 7
    col_p1   = 7
    col_tot  = 7
    col_rem  = 8
    col_drop = 30

    hdr = (
        f"{'Atmosphere':<{col_atm}} {'Room':<{col_room}} {'DNA?':<{col_dna}}"
        f" {'P1':>{col_p1}} {'Total':>{col_tot}} {'Headrm':>{col_rem}} {'Dropped sections':<{col_drop}}"
    )
    print(hdr)
    print("-" * len(hdr))

    summary = {
        "total": 0,
        "compressed": 0,
        "wow_dropped": 0,
        "realism_dropped": 0,
        "dna_dropped": 0,
        "interior_dropped": 0,
    }

    for atmosphere_id, style_label in _ATMOSPHERES:
        for room_type in _ROOM_TYPES:
            try:
                raw_sections, used_dna = _build_fv_sections(
                    atmosphere_id, style_label, room_type, source_length
                )
            except Exception as exc:
                print(f"  ERROR building sections for {atmosphere_id}/{room_type}: {exc}")
                continue

            sizes = _section_sizes(raw_sections)
            p1_sections = [
                "task", "full_contract", "source_space", "header", "edit_block",
                "full_contract", "continuation_contract", "atmosphere_contract",
                "evolution_contract",
            ]
            p1_total = sum(sizes.get(k, 0) for k in p1_sections)
            raw_total = sum(sizes.values()) + max(0, len(sizes) - 1)

            prompt, dropped = _assemble_with_budget("FIRST_VISION", raw_sections)
            final_len = len(prompt)
            headroom = budget - final_len

            dna_marker = "DNA" if used_dna else "style"
            atm_short = atmosphere_id.replace("_", " ").title()[:col_atm]
            drop_str = ", ".join(dropped) if dropped else "none"

            print(
                f"{atm_short:<{col_atm}} {room_type:<{col_room}} {dna_marker:<{col_dna}}"
                f" {p1_total:>{col_p1}} {raw_total:>{col_tot}} {headroom:>{col_rem}} {drop_str:<{col_drop}}"
            )

            summary["total"] += 1
            if dropped:
                summary["compressed"] += 1
            if "wow_directive" in dropped:
                summary["wow_dropped"] += 1
            if "compact_realism" in dropped or "full_realism" in dropped:
                summary["realism_dropped"] += 1
            if "design_intel" in dropped:
                summary["dna_dropped"] += 1
            if "interior_completeness" in dropped:
                summary["interior_dropped"] += 1

        print()  # blank line between atmospheres

    # ── Section size reference ────────────────────────────────────────────────
    print("\n--- FIXED SECTION SIZES (same for all atmospheres) ---")
    ref_sections, _ = _build_fv_sections(
        "japandi_calm", "Japandi · Harmony", "living room", source_length
    )
    ref_sizes = _section_sizes(ref_sections)
    for name, size in sorted(ref_sizes.items(), key=lambda x: -x[1]):
        prio = _SECTION_PRIORITY.get(name, "?")
        label = f"P{prio}"
        print(f"  {name:<25} {size:>5} chars  {label}")

    # ── DNA block size by atmosphere ──────────────────────────────────────────
    print("\n--- DNA BLOCK SIZES (living room) ---")
    for atmosphere_id, style_label in _ATMOSPHERES:
        dna = get_room_dna(atmosphere_id, "living room")
        if dna:
            block = build_dna_block(dna)
            print(f"  {atmosphere_id:<22}  {len(block):>5} chars  (DNA)")
        else:
            try:
                sdna = get_style(style_label)
                block = _style_block(sdna, style_label)
                print(f"  {atmosphere_id:<22}  {len(block):>5} chars  (style fallback)")
            except Exception:
                print(f"  {atmosphere_id:<22}  ????? chars  (error)")

    # ── Summary ───────────────────────────────────────────────────────────────
    total = summary["total"]
    print(f"\n{'='*60}")
    print(f"COMPRESSION SUMMARY ({total} atmosphere+room combinations)")
    print(f"{'='*60}")
    print(f"  Combos with any compression:   {summary['compressed']:>3} / {total}")
    print(f"  wow_directive dropped:          {summary['wow_dropped']:>3} / {total}")
    print(f"  realism dropped:               {summary['realism_dropped']:>3} / {total}")
    print(f"  design_intel (DNA) dropped:    {summary['dna_dropped']:>3} / {total}")
    print(f"  interior_completeness dropped: {summary['interior_dropped']:>3} / {total}")

    if summary["wow_dropped"] > 0:
        pct = 100 * summary["wow_dropped"] // total
        print(f"\n  [WARNING] wow_directive dropped in {pct}% of combos.")
        print(f"  Cause: P1+DNA > budget after P5+P4 exhausted.")
        print(f"  Consider: raise budget, trim DNA blocks, or shorten source descriptions.")
    else:
        print(f"\n  [OK] wow_directive survives in all {source_length}-char source scenarios.")

    if summary["dna_dropped"] > 0:
        print(f"\n  [CRITICAL] design_intel dropped in some combos.")
        print(f"  This means source_space is extremely long OR atmosphere DNA is very large.")
        print(f"  P1 content alone must be near-budget. Check source description length.")

    print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="FIRST_VISION prompt budget analyzer")
    parser.add_argument(
        "--source-length", type=int, default=200,
        help="Simulate SOURCE SPACE with this many chars (default: 200)"
    )
    args = parser.parse_args()
    analyze(args.source_length)
