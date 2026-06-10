"""Wave 5.13e validation — classification matrix dump (throwaway script)."""
from prompt_engine.transformation_classifier import classify_transformation

PHRASES = [
    # Atmosphere switches (expected: ATMOSPHERE_SWITCH)
    ("Nordic instead", "ATMOSPHERE_SWITCH"),
    ("Nordic please", "ATMOSPHERE_SWITCH"),
    ("Nordic Warmth instead", "ATMOSPHERE_SWITCH"),
    ("let's do Japandi", "ATMOSPHERE_SWITCH"),
    ("let's do Japandi now", "ATMOSPHERE_SWITCH"),
    ("let's go Tropical", "ATMOSPHERE_SWITCH"),
    ("let's go Tropical now", "ATMOSPHERE_SWITCH"),
    ("do Soft Luxury now", "ATMOSPHERE_SWITCH"),
    ("give me Desert", "ATMOSPHERE_SWITCH"),
    ("make it Nordic", "ATMOSPHERE_SWITCH"),
    ("make it tropical", "ATMOSPHERE_SWITCH"),
    ("make it tropical please", "ATMOSPHERE_SWITCH"),
    ("switch to Japandi", "ATMOSPHERE_SWITCH"),
    ("switch to nordic warmth", "ATMOSPHERE_SWITCH"),
    ("try nordic", "ATMOSPHERE_SWITCH"),
    ("try the Soft Luxury vibe", "ATMOSPHERE_SWITCH"),
    ("go with japandi", "ATMOSPHERE_SWITCH"),
    ("let's try Bali", "ATMOSPHERE_SWITCH"),
    ("Tropical now", "ATMOSPHERE_SWITCH"),
    ("Desert please", "ATMOSPHERE_SWITCH"),
    ("Redesign this space in the Nordic Warmth style", "ATMOSPHERE_SWITCH"),
    ("I want Japandi", "ATMOSPHERE_SWITCH"),
    ("switch atmosphere to Soft Luxury", "ATMOSPHERE_SWITCH"),
    ("use Nature Retreat", "ATMOSPHERE_SWITCH"),
    ("actually Nordic", "ATMOSPHERE_SWITCH"),
    # Style refinements (expected: STYLE_REFINEMENT)
    ("make it warmer", "STYLE_REFINEMENT"),
    ("cozier", "STYLE_REFINEMENT"),
    ("more dramatic", "STYLE_REFINEMENT"),
    ("more luxurious", "STYLE_REFINEMENT"),
    ("softer lighting", "STYLE_REFINEMENT"),
    ("darker mood", "STYLE_REFINEMENT"),
    ("plus chaud", "STYLE_REFINEMENT"),
    ("less harsh", "STYLE_REFINEMENT"),
    ("push it darker", "STYLE_REFINEMENT"),
    ("make it more luxurious", "STYLE_REFINEMENT"),
    # Object edits (expected: OBJECT_EDIT)
    ("add a plant", "OBJECT_EDIT"),
    ("remove the rug", "OBJECT_EDIT"),
    ("swap the curtains for white", "OBJECT_EDIT"),
    ("change the sofa to navy", "OBJECT_EDIT"),
    ("move the TV to the left", "OBJECT_EDIT"),
    ("move the TV", "OBJECT_EDIT"),
    # Layout reinterpretations (expected: LAYOUT_REINTERPRETATION)
    ("rearrange the furniture", "LAYOUT_REINTERPRETATION"),
    ("move everything around", "LAYOUT_REINTERPRETATION"),
    ("completely different layout", "LAYOUT_REINTERPRETATION"),
    ("start over with new layout", "LAYOUT_REINTERPRETATION"),
    # Structural changes (expected: STRUCTURAL_CHANGE)
    ("open up the wall", "STRUCTURAL_CHANGE"),
    ("knock down the wall", "STRUCTURAL_CHANGE"),
    ("add a window", "STRUCTURAL_CHANGE"),
    ("extend the kitchen", "STRUCTURAL_CHANGE"),
    ("open the wall on the right and show the kitchen", "STRUCTURAL_CHANGE"),
    # Functional reassignment (expected: FUNCTIONAL_REASSIGNMENT)
    ("turn this into a bedroom", "FUNCTIONAL_REASSIGNMENT"),
    ("convert this room into an office", "FUNCTIONAL_REASSIGNMENT"),
    # French phrasings (user requested visibility — not part of patch scope)
    ("passe en nordique", "ATMOSPHERE_SWITCH"),
    ("mets en nordique", "ATMOSPHERE_SWITCH"),
    ("essaie japandi", "ATMOSPHERE_SWITCH"),
    ("fais tropical", "ATMOSPHERE_SWITCH"),
    ("version japandi", "ATMOSPHERE_SWITCH"),
    ("version nordique", "ATMOSPHERE_SWITCH"),
]


def main() -> None:
    ok = 0
    mismatch = 0
    rows: list[str] = []
    rows.append(f"{'PHRASE':<60} {'CURRENT':<24} {'EXPECTED':<24} OK")
    rows.append("-" * 120)
    for phrase, expected in PHRASES:
        actual = classify_transformation(phrase, 2).value.upper()
        mark = "OK" if actual == expected else "FAIL"
        if mark == "OK":
            ok += 1
        else:
            mismatch += 1
        rows.append(f"{phrase:<60} {actual:<24} {expected:<24} {mark}")
    rows.append("-" * 120)
    rows.append(f"Total: {len(PHRASES)}   OK: {ok}   FAIL: {mismatch}")
    print("\n".join(rows))


if __name__ == "__main__":
    main()
