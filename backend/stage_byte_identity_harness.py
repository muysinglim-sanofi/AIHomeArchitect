"""Byte-identity harness for INTERIOR STAGE contracts (run from backend/).

Dumps every interior STAGE contract (8 rooms x 5 atmospheres) with length + sha,
so a before/after diff proves an exterior-STAGE PR did NOT touch interiors.

Usage:
    .venv/Scripts/python.exe stage_byte_identity_harness.py > before.txt
    # ... make the exterior-STAGE change ...
    .venv/Scripts/python.exe stage_byte_identity_harness.py > after.txt
    diff before.txt after.txt   # MUST be empty
"""
import sys, os, hashlib
sys.path.insert(0, os.getcwd())
from prompt_engine.preservation import build_stage_contract  # noqa: E402

INTERIOR = ["living_room", "bedroom", "kitchen", "bathroom",
            "dining_room", "office", "entrance", "hallway"]
ATMO = [("warm_modern", "Warm Modern"), ("soft_luxury", "Soft Luxury"),
        ("japandi_calm", "Japandi"), ("nordic_warmth", "Nordic Warmth"),
        ("tropical_escape", "Tropical")]

for room in INTERIOR:
    for aid, alabel in ATMO:
        c = build_stage_contract(room, alabel, aid)
        h = hashlib.sha1(c.encode("utf-8")).hexdigest()
        print(f"{room:14} {aid:16} len={len(c):5} sha={h}")
