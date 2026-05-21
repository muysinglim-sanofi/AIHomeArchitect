"""
Read the filled STRUCTURAL_DRIFT_SCORECARD.md, aggregate, output a report.

Usage:
  python docs/structural_drift_aggregate.py

Reads:   docs/STRUCTURAL_DRIFT_SCORECARD.md
Writes:  docs/structural_drift_report.txt + stdout summary

Scoring rules:
  2 = preserved, 1 = partial, 0 = lost, blank = ignored.
  Preservation rate per feature = (sum of valid scores) / (2 * count of valid cells)
  → 100% means all scored 2; 0% means all scored 0.
  Drift rate = 1 - preservation rate.

Systematic drift: a feature scores < 1 in BOTH runs of the same atmosphere.
Stochastic drift: a feature scores < 2 in exactly ONE of two runs.
"""

from __future__ import annotations
import os
import re
import sys
from collections import defaultdict
from statistics import mean

HERE = os.path.dirname(os.path.abspath(__file__))
SCORECARD = os.path.join(HERE, "STRUCTURAL_DRIFT_SCORECARD.md")
REPORT = os.path.join(HERE, "structural_drift_report.txt")

FEATURES = [
    "F1: Slide door wall",
    "F2: Slide door width",
    "F3: Glass partition",
    "F4: Visible kitchen",
    "F5: Rear window",
    "F6: Ceiling diagonal",
    "F7: Floor herringbone",
    "F8: Perspective",
    "F9: Spatial depth",
]


def _parse_scorecard(path: str) -> tuple[list[dict], str]:
    """Return (rows, notes) where rows = [{atmosphere, run, scores: {feat: 0/1/2 or None}}]."""
    with open(path, encoding="utf-8") as f:
        text = f.read()

    rows: list[dict] = []
    for line in text.splitlines():
        line = line.strip()
        # Match a data row: starts with `|`, contains a digit, has at least 11 columns
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 12:
            continue
        # Skip the header row (cells[0] like '#') and the separator row (dashes)
        if not cells[0].isdigit():
            continue
        atmosphere = cells[1]
        try:
            run = int(cells[2])
        except ValueError:
            continue
        scores = {}
        for i, feat in enumerate(FEATURES):
            raw = cells[3 + i]
            if raw in ("", "_", "-"):
                scores[feat] = None
            else:
                try:
                    val = int(raw)
                    if val in (0, 1, 2):
                        scores[feat] = val
                    else:
                        scores[feat] = None
                except ValueError:
                    scores[feat] = None
        rows.append({"atmosphere": atmosphere, "run": run, "scores": scores})

    # Extract free-form notes section
    notes = ""
    m = re.search(r"## Notes.*?\n(.*?)(?:\n## |\Z)", text, re.S)
    if m:
        notes = m.group(1).strip()
    return rows, notes


def _aggregate(rows: list[dict]) -> dict:
    """Compute per-feature, per-atmosphere, and composite stats."""
    # Per-feature
    per_feature = {}
    for feat in FEATURES:
        scores = [r["scores"][feat] for r in rows if r["scores"][feat] is not None]
        if not scores:
            per_feature[feat] = {"n": 0, "preservation_rate": None, "scored": 0}
            continue
        rate = sum(scores) / (2.0 * len(scores))
        per_feature[feat] = {
            "n": len(scores),
            "preservation_rate": rate,
            "scored_2": sum(1 for s in scores if s == 2),
            "scored_1": sum(1 for s in scores if s == 1),
            "scored_0": sum(1 for s in scores if s == 0),
        }

    # Per-atmosphere
    per_atm: dict[str, dict] = defaultdict(lambda: {"runs": [], "composite": None})
    for r in rows:
        per_atm[r["atmosphere"]]["runs"].append(r)
    for atm, data in per_atm.items():
        all_scores = []
        for r in data["runs"]:
            for v in r["scores"].values():
                if v is not None:
                    all_scores.append(v)
        if all_scores:
            data["composite"] = sum(all_scores) / (2.0 * len(all_scores))
            data["n"] = len(all_scores)
        else:
            data["n"] = 0

    # Overall composite
    all_scores = []
    for r in rows:
        for v in r["scores"].values():
            if v is not None:
                all_scores.append(v)
    overall = sum(all_scores) / (2.0 * len(all_scores)) if all_scores else None

    # Systematic vs stochastic drift: pair up run1/run2 of same atmosphere
    systematic: list[tuple[str, str]] = []   # (atmosphere, feature) where BOTH runs scored < 1
    stochastic: list[tuple[str, str]] = []   # (atmosphere, feature) where ONLY one run < 2
    paired = defaultdict(dict)               # atmosphere → run → scores
    for r in rows:
        paired[r["atmosphere"]][r["run"]] = r["scores"]
    for atm, runs in paired.items():
        if 1 not in runs or 2 not in runs:
            continue
        for feat in FEATURES:
            v1, v2 = runs[1].get(feat), runs[2].get(feat)
            if v1 is None or v2 is None:
                continue
            if v1 < 1 and v2 < 1:
                systematic.append((atm, feat))
            elif (v1 < 2) != (v2 < 2):
                stochastic.append((atm, feat))

    return {
        "n_rows_scored": sum(1 for r in rows if any(v is not None for v in r["scores"].values())),
        "n_rows_total": len(rows),
        "overall_preservation_rate": overall,
        "per_feature": per_feature,
        "per_atmosphere": dict(per_atm),
        "systematic_drift_pairs": systematic,
        "stochastic_drift_pairs": stochastic,
    }


def _bar(pct: float | None, width: int = 30) -> str:
    if pct is None:
        return " " * width + "  (no data)"
    filled = int(round(pct * width))
    return "█" * filled + "░" * (width - filled) + f"  {pct * 100:5.1f}%"


def _verdict(score: float | None) -> str:
    if score is None:
        return "N/A"
    if score >= 0.85: return "HIGH preservation — no Option 1 needed"
    if score >= 0.70: return "MODERATE preservation — Option 1 likely worth 3-4 days dev"
    if score >= 0.50: return "SIGNIFICANT drift — Option 1 mandatory, consider GPU upgrade later"
    return "SEVERE drift — Option 1 alone may not be enough, segmentation needed"


def main() -> None:
    if not os.path.exists(SCORECARD):
        print(f"[ERR] Scorecard not found at {SCORECARD}", file=sys.stderr)
        sys.exit(1)

    rows, notes = _parse_scorecard(SCORECARD)
    if not rows:
        print("[ERR] No rows parsed from scorecard. Did you fill it in?", file=sys.stderr)
        sys.exit(1)

    stats = _aggregate(rows)

    lines: list[str] = []
    lines.append("=" * 78)
    lines.append("STRUCTURAL DRIFT REPORT")
    lines.append("=" * 78)
    lines.append(f"Rows with at least one score: {stats['n_rows_scored']} / {stats['n_rows_total']}")
    lines.append("")
    lines.append(f"OVERALL PRESERVATION SCORE: {_bar(stats['overall_preservation_rate'])}")
    lines.append(f"VERDICT: {_verdict(stats['overall_preservation_rate'])}")
    lines.append("")
    lines.append("-" * 78)
    lines.append("PER FEATURE")
    lines.append("-" * 78)
    for feat, f in stats["per_feature"].items():
        if f["n"] == 0:
            lines.append(f"  {feat:30}  (no data)")
            continue
        lines.append(
            f"  {feat:30} {_bar(f['preservation_rate'])}  "
            f"(2={f['scored_2']}, 1={f['scored_1']}, 0={f['scored_0']}, n={f['n']})"
        )
    lines.append("")
    lines.append("-" * 78)
    lines.append("PER ATMOSPHERE (composite)")
    lines.append("-" * 78)
    sorted_atm = sorted(stats["per_atmosphere"].items(),
                        key=lambda x: x[1]["composite"] if x[1]["composite"] is not None else -1)
    for atm, data in sorted_atm:
        lines.append(f"  {atm:22} {_bar(data['composite'])}  (n={data['n']})")
    lines.append("")

    if stats["systematic_drift_pairs"]:
        lines.append("-" * 78)
        lines.append("SYSTEMATIC DRIFT (both runs of an atmosphere failed the same feature)")
        lines.append("-" * 78)
        for atm, feat in stats["systematic_drift_pairs"]:
            lines.append(f"  {atm:22}  →  {feat}")
        lines.append("  ↑ These are PROMPT-LEVEL or DNA-LEVEL issues, not stochastic.")
        lines.append("")
    if stats["stochastic_drift_pairs"]:
        lines.append("-" * 78)
        lines.append("STOCHASTIC DRIFT (one run preserved, the other did not)")
        lines.append("-" * 78)
        for atm, feat in stats["stochastic_drift_pairs"]:
            lines.append(f"  {atm:22}  →  {feat}")
        lines.append("  ↑ Likely gpt-image-1 sampling variance — Option 1 (edge composite) helps these.")
        lines.append("")

    if notes:
        lines.append("-" * 78)
        lines.append("FREE-FORM NOTES")
        lines.append("-" * 78)
        lines.append(notes)
        lines.append("")

    report = "\n".join(lines)
    print(report)
    with open(REPORT, "w", encoding="utf-8") as f:
        f.write(report)
    print(f"\n[saved] {REPORT}")


if __name__ == "__main__":
    main()
