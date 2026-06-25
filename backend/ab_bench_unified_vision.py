"""A/B classification bench — AYDEN_UNIFIED_VISION (run from backend/ in the venv).

Usage:
    .venv/Scripts/python.exe ab_bench_unified_vision.py <photo_dir>

For each photo it calls _classify_ayden TWICE on the SAME image — flag OFF
(old interior-only) then flag ON (unified) — and reports:
  • interior room parity  (OFF room == ON room, for photos OFF sees as interior)
  • interior atmosphere parity (OFF atmo == ON atmo)
  • exterior classification (what ON returns for the exterior shots)

Put interior shots and exterior shots in <photo_dir>. Name exterior files with a
hint (terrace_*, garden_*, pool_*, facade_*, balcony_*, driveway_*) to eyeball
correctness. Costs 2 gpt-4o low-detail calls per photo.

SHIP GATE before enabling AYDEN_UNIFIED_VISION on Render:
  - room parity == 100% on interiors
  - atmosphere parity == 100% (no regression) on interiors
  - terrace / balcony / garden / pool_area / facade / driveway detected correctly
"""
import asyncio, os, sys, glob
sys.path.insert(0, os.getcwd())  # import main from backend/
from main import _classify_ayden  # noqa: E402

_EXT = {"garden", "terrace", "facade", "balcony", "pool_area", "driveway"}


async def _classify(img: bytes, unified: bool):
    os.environ["AYDEN_UNIFIED_VISION"] = "1" if unified else "0"
    return await _classify_ayden(img)


async def run(folder: str):
    paths = []
    for ext in ("*.jpg", "*.jpeg", "*.png"):
        paths += glob.glob(os.path.join(folder, ext))
    paths.sort()
    n_int = room_par = atmo_par = 0
    print(f"{'file':32} {'OFF (room,atmo)':28} {'ON (room,atmo)':28} kind")
    for p in paths:
        img = open(p, "rb").read()
        off = await _classify(img, False)
        on = await _classify(img, True)
        kind = "EXTERIOR" if on["room"] in _EXT else "interior"
        print(f"{os.path.basename(p):32} "
              f"{(off['room'] + ',' + off['atmosphere']):28} "
              f"{(on['room'] + ',' + on['atmosphere']):28} {kind}")
        # interior parity: only where OFF (the baseline) saw an interior room
        if off["room"] and off["room"] not in _EXT:
            n_int += 1
            room_par += (off["room"] == on["room"])
            atmo_par += (off["atmosphere"] == on["atmosphere"])
    print("\n=== PARITY (interiors, OFF baseline) ===")
    if n_int:
        print(f"  room parity : {room_par}/{n_int}  ({100 * room_par // n_int}%)")
        print(f"  atmo parity : {atmo_par}/{n_int}  ({100 * atmo_par // n_int}%)")
        print("  SHIP GATE: require room parity AND atmo parity == 100% on interiors")
    else:
        print("  no interior baseline photos found")


if __name__ == "__main__":
    asyncio.run(run(sys.argv[1] if len(sys.argv) > 1 else "."))
