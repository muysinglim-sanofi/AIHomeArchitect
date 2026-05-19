"""
optimize_ftue_assets.py

Optimizes all FTUE atmosphere hero images in assets/atmospheres/ftue/.

What it does:
  - Backs up originals to assets/atmospheres/ftue/_originals/
  - Resizes to fit within MAX_SIZE (1200x800 by default), maintaining aspect ratio
  - Converts to JPG at QUALITY (83 by default)
  - Overwrites in-place with the same filename
  - Prints a before/after size table and flags spec issues

Usage:
  python optimize_ftue_assets.py [--max-width W] [--max-height H] [--quality Q] [--dry-run]

Flags:
  --max-width   Max output width  (default: 1200)
  --max-height  Max output height (default:  800)
  --quality     JPG quality 1-95  (default:   83)
  --dry-run     Show what would happen without writing any files
"""

import argparse
import os
import shutil
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required. Run: python -m pip install Pillow")

# ── Config ────────────────────────────────────────────────────────────────────

FTUE_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "frontend", "assets", "atmospheres", "ftue",
)
BACKUP_DIR = os.path.join(FTUE_DIR, "_originals")

# Expected filenames per spec (snake_case, no French spelling variants)
EXPECTED_FILENAMES = {
    "ftue_tropical_escape.jpg",
    "ftue_warm_modern.jpg",
    "ftue_zen_retreat.jpg",
    "ftue_bali_sanctuary.jpg",
    "ftue_japandi_calm.jpg",
    "ftue_soft_luxury.jpg",
    "ftue_nordic_warmth.jpg",
    "ftue_dark_contemporary.jpg",
    "ftue_nature_retreat.jpg",
    "ftue_desert_luxe.jpg",
}

IMAGE_EXTS = {".jpg", ".jpeg", ".webp", ".png"}

MAX_FILE_KB = 250  # spec limit


# ── Helpers ───────────────────────────────────────────────────────────────────

def fmt_kb(n_bytes: int) -> str:
    return f"{n_bytes / 1024:>7.1f} KB"


def collect_images(folder: str) -> list[str]:
    return sorted(
        f for f in os.listdir(folder)
        if os.path.splitext(f)[1].lower() in IMAGE_EXTS
        and not f.startswith("_")
    )


def backup_original(src_path: str, backup_dir: str, dry_run: bool) -> None:
    os.makedirs(backup_dir, exist_ok=True) if not dry_run else None
    dst = os.path.join(backup_dir, os.path.basename(src_path))
    if not os.path.exists(dst):
        if not dry_run:
            shutil.copy2(src_path, dst)


def optimize(src_path: str, max_w: int, max_h: int, quality: int, dry_run: bool) -> tuple[int, int, tuple[int,int]]:
    """Returns (original_bytes, optimized_bytes, output_dimensions)."""
    original_bytes = os.path.getsize(src_path)

    with Image.open(src_path) as img:
        orig_dims = img.size
        img = img.convert("RGB")  # ensure no alpha channel in JPG

        # Resize only if larger than max — maintain aspect ratio
        if img.width > max_w or img.height > max_h:
            img.thumbnail((max_w, max_h), Image.LANCZOS)

        out_dims = img.size

        if not dry_run:
            # Write to a temp path first, then replace (atomic-ish)
            tmp_path = src_path + ".tmp"
            img.save(tmp_path, format="JPEG", quality=quality, optimize=True, progressive=True)
            # Only replace if the output is actually smaller (never inflate a tiny file)
            tmp_size = os.path.getsize(tmp_path)
            if tmp_size < original_bytes:
                os.replace(tmp_path, src_path)
                optimized_bytes = tmp_size
            else:
                os.remove(tmp_path)
                optimized_bytes = original_bytes  # kept original
        else:
            optimized_bytes = original_bytes  # unknown in dry-run; show original

    return original_bytes, optimized_bytes, out_dims


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--max-width",  type=int, default=1200, help="Max output width  (default: 1200)")
    parser.add_argument("--max-height", type=int, default=800,  help="Max output height (default:  800)")
    parser.add_argument("--quality",    type=int, default=83,   help="JPG quality 1-95  (default:   83)")
    parser.add_argument("--dry-run",    action="store_true",    help="Preview without writing files")
    args = parser.parse_args()

    if not os.path.isdir(FTUE_DIR):
        sys.exit(f"FTUE directory not found:\n  {FTUE_DIR}")

    images = collect_images(FTUE_DIR)
    if not images:
        sys.exit("No image files found in the FTUE directory.")

    mode_label = "[DRY RUN] " if args.dry_run else ""
    print(f"\n{mode_label}Optimizing FTUE assets")
    print(f"  Directory : {FTUE_DIR}")
    print(f"  Max size  : {args.max_width} × {args.max_height} px")
    print(f"  Quality   : {args.quality}")
    print(f"  Backup    : {BACKUP_DIR}")
    print()

    # ── Filename spec check ───────────────────────────────────────────────────
    warnings = []
    found_names = set(images)
    for name in found_names:
        if name not in EXPECTED_FILENAMES:
            # Try to suggest the correct name
            suggestion = None
            if "contemporain" in name:
                suggestion = name.replace("contemporain", "contemporary")
            elif "luxe" in name and "desert" not in name:
                suggestion = name.replace("luxe", "luxury")
            hint = f" -> did you mean '{suggestion}'?" if suggestion else " (not in spec)"
            warnings.append(f"  WARN  '{name}'{hint}")
    for name in EXPECTED_FILENAMES:
        if name not in found_names:
            warnings.append(f"  MISSING  '{name}'")

    if warnings:
        print("Filename issues detected:")
        for w in warnings:
            print(w)
        print()

    # ── Process images ────────────────────────────────────────────────────────
    col_w = max(len(f) for f in images) + 2
    header = f"  {'File':<{col_w}}  {'Before':>10}  {'After':>10}  {'Saved':>9}  {'Dims'}"
    print(header)
    print("  " + "-" * (len(header) - 2))

    total_before = total_after = 0
    over_limit = []

    for filename in images:
        src_path = os.path.join(FTUE_DIR, filename)
        backup_original(src_path, BACKUP_DIR, args.dry_run)

        before, after, dims = optimize(src_path, args.max_width, args.max_height, args.quality, args.dry_run)
        saved = before - after
        saved_pct = (saved / before * 100) if before else 0

        total_before += before
        total_after += after

        flag = " !" if after > MAX_FILE_KB * 1024 else "  "
        dim_str = f"{dims[0]}×{dims[1]}"
        print(f"{flag} {filename:<{col_w}}  {fmt_kb(before)}  {fmt_kb(after)}  {saved_pct:>7.1f}%  {dim_str}")

        if after > MAX_FILE_KB * 1024:
            over_limit.append((filename, after))

    # ── Summary ───────────────────────────────────────────────────────────────
    total_saved = total_before - total_after
    total_pct = (total_saved / total_before * 100) if total_before else 0
    print("  " + "-" * (len(header) - 2))
    print(f"  {'TOTAL':<{col_w}}  {fmt_kb(total_before)}  {fmt_kb(total_after)}  {total_pct:>7.1f}%")
    print()

    if over_limit:
        print(f"WARNING: {len(over_limit)} file(s) still exceed the {MAX_FILE_KB} KB spec limit:")
        for name, size in over_limit:
            print(f"  {name}  ({size/1024:.1f} KB) — try lower --quality or smaller --max-width/--max-height")
        print()

    if not args.dry_run:
        print(f"Originals backed up to: {BACKUP_DIR}")
        print("Done. Drop-in complete — no Flutter code changes needed.")
    else:
        print("Dry run complete. No files were modified.")


if __name__ == "__main__":
    main()
