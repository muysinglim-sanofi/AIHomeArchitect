"""
Prompt Diff Inspector — Wave 5.5.23 validation infrastructure.

Compares the V1 prompt produced by the CURRENT working tree against the
prompt produced at a baseline git ref (default HEAD~1), tokenizes both by
5 semantic categories, and emits a structured diff focused on the
empirically-known risk vectors.

DESIGN PRINCIPLES
=================

1. SUPPRESSIONS ARE FIRST-CLASS SIGNALS.
   Wave 5.5.15→22 chain proved that removing words (the ceramic vessel,
   the TV-facing-row clause, the "no visible TV above fireplace" rule)
   can have as much impact as adding words. The diff tracks BOTH adds
   and removes per category.

2. NO AUTO-CLASSIFIER, NO BLOCKING.
   This tool produces DATA for a human to review before bench. It never
   gates a wave automatically. Semantic prediction is unreliable (proven
   empirically Wave 5.5.15c-d); the human keeps judgment authority.

3. 5 CATEGORIES (not arbitrary).
   Each category maps to an empirical failure mode we've observed:
     - Nouns (objects)       → furniture invention / replacement
     - Spatial adjectives    → architectural drift (airy, expansive, ...)
     - Focal semantics       → media-wall / statement-wall invention
     - Continuity semantics  → kitchen suppression / cross-zone bleed
     - Negation patterns     → trap suppression (when removed)

4. CATEGORY VOCABULARIES LIVE IN docs/VOCABULARY_LESSONS.md
   Empirical risk labels (HIGH/MEDIUM/LOW) sourced from that doc, not
   hardcoded here. Append-only doc grows with each wave's lessons.

USAGE
=====

  python tools/prompt_diff.py                              # diff vs HEAD~1
  python tools/prompt_diff.py --before HEAD~3              # diff vs older ref
  python tools/prompt_diff.py --atm warm_modern --mode preserve
  python tools/prompt_diff.py --json                       # machine-readable
  python tools/prompt_diff.py --room dining_room
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

# ── Repo paths ──────────────────────────────────────────────────────────────

_HERE = Path(__file__).resolve().parent
_REPO_ROOT = _HERE.parent
_BACKEND = _REPO_ROOT / "backend"
_VOCAB_DOC = _REPO_ROOT / "docs" / "VOCABULARY_LESSONS.md"

# Default cells exercised when no --atm / --mode / --room flags are given.
# Mirrors the 3-atmosphere bench protocol most waves use.
_DEFAULT_CELLS: list[tuple[str, str, str]] = [
    ("Warm Modern", "living_room", "preserve"),
    ("Warm Modern", "living_room", "creative"),
    ("Japandi Calm", "living_room", "preserve"),
    ("Japandi Calm", "living_room", "creative"),
    ("Nordic Warmth", "living_room", "preserve"),
    ("Nordic Warmth", "living_room", "creative"),
]


# ── Semantic categorization ─────────────────────────────────────────────────
#
# Vocabularies are seeds. The docs/VOCABULARY_LESSONS.md registry overrides
# / extends them by wave.

# Concrete object nouns the model can populate.
_NOUN_VOCAB = {
    "television", "tv", "coffee table", "sofa", "armchair", "rug", "area rug",
    "vessel", "fireplace", "console", "shelf", "lamp", "pendant", "chandelier",
    "curtains", "drapes", "blinds", "artwork", "mirror", "bedding", "headboard",
    "nightstand", "dresser", "wardrobe", "dining table", "chair", "bench",
    "ottoman", "credenza", "sideboard", "bookcase", "fireplace", "wood stove",
    "media", "screen", "monitor", "speaker", "stereo",
}

# Spatial / architectural adjectives historically associated with drift.
_SPATIAL_ADJ_VOCAB = {
    "airy", "expansive", "grand", "spacious", "open-plan", "open plan",
    "seamless", "immersive", "fully designed", "fully equipped",
    "hospitality-grade", "gallery-like", "designer-staged", "luxury composition",
    "spatial harmony", "elegant circulation", "premium spatial",
}

# Focal-element semantics that trigger composition solving.
_FOCAL_SEMANTICS = {
    "focal wall", "focal point", "focal element", "statement wall",
    "media wall", "tv wall", "centerpiece", "feature wall",
    "single focal", "dominant focal",
}

# Continuity / cross-zone semantics that risk kitchen suppression or
# zone-bleed.
_CONTINUITY_SEMANTICS = {
    "continuity", "echo", "transition", "flow into", "into adjacent",
    "into the kitchen", "into kitchen", "visible kitchen", "visible hallway",
    "between adjacent", "through the partition", "across rooms",
    "inhabited", "subtly inhabited", "extend into",
}

# Negation patterns. Tracked because REMOVING a negation often "untraps"
# something the model was previously forbidden from doing (e.g. removing
# "no visible TV above fireplace" unblocked TV placement).
_NEGATION_PATTERNS = [
    re.compile(r"\bno\s+\w+", re.I),
    re.compile(r"\bnever\s+\w+", re.I),
    re.compile(r"\bnot\s+\w+(?:\s+\w+)?", re.I),
    re.compile(r"\bavoid\s+\w+", re.I),
    re.compile(r"—\s*not\s+", re.I),
]


def _tokens_in_text(text: str, vocab: set[str]) -> set[str]:
    """Return the subset of vocabulary phrases that appear in text (case-
    insensitive, whole-phrase match — no partial word matches)."""
    low = text.lower()
    out: set[str] = set()
    for word in vocab:
        # Word boundary if single token; substring with surrounding
        # whitespace/punct for multi-word phrases.
        if " " in word:
            if word in low:
                out.add(word)
        else:
            if re.search(rf"\b{re.escape(word)}\b", low):
                out.add(word)
    return out


def _negations_in_text(text: str) -> set[str]:
    """Return the set of negation phrases (canonicalized) appearing in text."""
    out: set[str] = set()
    for pattern in _NEGATION_PATTERNS:
        for match in pattern.finditer(text):
            out.add(match.group(0).strip().lower())
    return out


@dataclass
class CategoryDiff:
    category: str
    added: list[str] = field(default_factory=list)
    removed: list[str] = field(default_factory=list)

    @property
    def has_changes(self) -> bool:
        return bool(self.added or self.removed)

    def as_dict(self) -> dict:
        return {"category": self.category, "added": self.added, "removed": self.removed}


@dataclass
class CellDiff:
    atmosphere: str
    room: str
    mode: str
    chars_before: int
    chars_after: int
    chars_delta: int
    categories: list[CategoryDiff]

    def as_dict(self) -> dict:
        return {
            "atmosphere": self.atmosphere,
            "room": self.room,
            "mode": self.mode,
            "chars_before": self.chars_before,
            "chars_after": self.chars_after,
            "chars_delta": self.chars_delta,
            "categories": [c.as_dict() for c in self.categories],
        }


# ── Prompt building (shared with bench scripts) ─────────────────────────────

def _build_prompt(atmosphere: str, room: str, mode: str) -> str:
    """Build a V1 prompt for the given cell using the CURRENT working tree.

    Mirrors the synthetic identity used by validate_byteexact_5515b.py and
    capture_baseline_5515b.py so diffs are comparable to the existing bench
    infrastructure.
    """
    # Ensure backend is importable.
    if str(_BACKEND) not in sys.path:
        sys.path.insert(0, str(_BACKEND))

    from prompt_engine import compose_generation_prompt
    from prompt_engine.structural_identity import (
        extract_from_description,
        render_clause,
        render_negative_anchors,
    )

    os.environ["BIMODAL_ENABLED"] = "1"
    desc = (
        "Living room with wide floor-to-ceiling window dominating the rear "
        "wall and an open kitchen visible on the left, with a glass partition."
    )
    identity = extract_from_description(desc)
    return compose_generation_prompt(
        style_label=atmosphere,
        room_type=room,
        room_description=desc,
        user_instruction="",
        iteration=1,
        history=[],
        structural_identity=render_clause(identity, "V1", mode),
        structural_negative_anchors=render_negative_anchors(identity, mode),
        generation_mode=mode,
    )


def _build_prompt_at_ref(
    ref: str,
    atmosphere: str,
    room: str,
    mode: str,
) -> str:
    """Build the prompt as it would have been at a git ref by spawning a
    subprocess in a worktree at that ref. This avoids module-cache poisoning
    when comparing the same Python process against two different code states.
    """
    # Use git worktree for isolated checkout.
    with tempfile.TemporaryDirectory(prefix="prompt_diff_") as tmp:
        worktree = Path(tmp) / "wt"
        subprocess.run(
            ["git", "worktree", "add", "--detach", str(worktree), ref],
            cwd=_REPO_ROOT,
            check=True,
            capture_output=True,
        )
        try:
            # Re-invoke this same script inside the worktree to build the
            # prompt with its code state.
            self_path_in_wt = worktree / "tools" / "prompt_diff.py"
            backend_in_wt = worktree / "backend"
            cmd = [
                sys.executable,
                "-c",
                (
                    "import os, sys\n"
                    f"sys.path.insert(0, {repr(str(backend_in_wt))})\n"
                    "os.environ['BIMODAL_ENABLED'] = '1'\n"
                    "from prompt_engine import compose_generation_prompt\n"
                    "from prompt_engine.structural_identity import extract_from_description, render_clause, render_negative_anchors\n"
                    "desc = 'Living room with wide floor-to-ceiling window dominating the rear wall and an open kitchen visible on the left, with a glass partition.'\n"
                    "identity = extract_from_description(desc)\n"
                    f"prompt = compose_generation_prompt(\n"
                    f"    style_label={repr(atmosphere)},\n"
                    f"    room_type={repr(room)},\n"
                    f"    room_description=desc,\n"
                    f"    user_instruction='',\n"
                    f"    iteration=1,\n"
                    f"    history=[],\n"
                    f"    structural_identity=render_clause(identity, 'V1', {repr(mode)}),\n"
                    f"    structural_negative_anchors=render_negative_anchors(identity, {repr(mode)}),\n"
                    f"    generation_mode={repr(mode)},\n"
                    ")\n"
                    "import sys\n"
                    "sys.stdout.buffer.write(prompt.encode('utf-8'))\n"
                ),
            ]
            result = subprocess.run(cmd, capture_output=True, check=True)
            return result.stdout.decode("utf-8")
        finally:
            subprocess.run(
                ["git", "worktree", "remove", "--force", str(worktree)],
                cwd=_REPO_ROOT,
                check=False,
                capture_output=True,
            )


# ── Diff logic ──────────────────────────────────────────────────────────────


def _categorize_diff(before: str, after: str) -> list[CategoryDiff]:
    """Compute the 5 semantic-category diffs between before and after."""
    diffs: list[CategoryDiff] = []

    for category, vocab in [
        ("Nouns (objects)", _NOUN_VOCAB),
        ("Spatial adjectives", _SPATIAL_ADJ_VOCAB),
        ("Focal semantics", _FOCAL_SEMANTICS),
        ("Continuity semantics", _CONTINUITY_SEMANTICS),
    ]:
        before_set = _tokens_in_text(before, vocab)
        after_set = _tokens_in_text(after, vocab)
        diffs.append(
            CategoryDiff(
                category=category,
                added=sorted(after_set - before_set),
                removed=sorted(before_set - after_set),
            )
        )

    # Negations are special: extracted by regex, not from a fixed vocab.
    before_negs = _negations_in_text(before)
    after_negs = _negations_in_text(after)
    diffs.append(
        CategoryDiff(
            category="Negation patterns",
            added=sorted(after_negs - before_negs),
            removed=sorted(before_negs - after_negs),
        )
    )

    return diffs


def _diff_cell(
    before_ref: str,
    atmosphere: str,
    room: str,
    mode: str,
) -> CellDiff:
    before_prompt = _build_prompt_at_ref(before_ref, atmosphere, room, mode)
    after_prompt = _build_prompt(atmosphere, room, mode)
    return CellDiff(
        atmosphere=atmosphere,
        room=room,
        mode=mode,
        chars_before=len(before_prompt),
        chars_after=len(after_prompt),
        chars_delta=len(after_prompt) - len(before_prompt),
        categories=_categorize_diff(before_prompt, after_prompt),
    )


# ── Output formatting ───────────────────────────────────────────────────────


def _format_human(diffs: list[CellDiff]) -> str:
    """Human-readable terminal output."""
    lines: list[str] = []
    lines.append("=" * 78)
    lines.append("Prompt Diff Inspector — Wave 5.5.23")
    lines.append("=" * 78)

    for cell in diffs:
        lines.append("")
        lines.append(f"[{cell.atmosphere} / {cell.room} / {cell.mode}]")
        lines.append(
            f"  chars: {cell.chars_before} → {cell.chars_after} "
            f"(delta {cell.chars_delta:+d})"
        )
        any_change = any(c.has_changes for c in cell.categories)
        if not any_change:
            lines.append("  no semantic-category changes detected")
            continue

        for cat in cell.categories:
            if not cat.has_changes:
                continue
            lines.append(f"  {cat.category}:")
            for item in cat.added:
                lines.append(f"    + {item}")
            for item in cat.removed:
                lines.append(f"    - {item}")

    lines.append("")
    lines.append("=" * 78)
    lines.append(
        "Reminder: this tool produces DATA. Risk is judged by you, not the "
        "tool. Cross-reference any added/removed items against "
        "docs/VOCABULARY_LESSONS.md before bench."
    )
    lines.append("=" * 78)
    return "\n".join(lines)


# ── CLI ─────────────────────────────────────────────────────────────────────


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prompt diff inspector (semantic categories + suppression tracking)."
    )
    parser.add_argument("--before", default="HEAD~1", help="git ref to diff against (default HEAD~1)")
    parser.add_argument("--atm", default=None, help="single atmosphere to diff")
    parser.add_argument("--room", default="living_room", help="single room (default living_room)")
    parser.add_argument("--mode", default=None, help="single mode (preserve|creative)")
    parser.add_argument("--json", action="store_true", help="machine-readable JSON output")
    args = parser.parse_args()

    # Resolve cells to diff.
    if args.atm and args.mode:
        cells = [(args.atm, args.room, args.mode)]
    elif args.atm:
        cells = [(args.atm, args.room, "preserve"), (args.atm, args.room, "creative")]
    elif args.mode:
        cells = [(a, args.room, args.mode) for a, _r, _m in _DEFAULT_CELLS if _m == args.mode]
    else:
        cells = _DEFAULT_CELLS

    diffs = [_diff_cell(args.before, atm, room, mode) for atm, room, mode in cells]

    if args.json:
        print(json.dumps([d.as_dict() for d in diffs], indent=2, ensure_ascii=False))
    else:
        print(_format_human(diffs))

    return 0


if __name__ == "__main__":
    sys.exit(main())
