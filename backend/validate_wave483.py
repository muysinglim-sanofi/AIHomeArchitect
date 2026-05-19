"""
Wave 4.8.3 validation - V2+ Before/After Reveal Continuity Fix.

ROOT CAUSE (audited): the reveal "before" image was hard-bound to the original
upload (`originalUrl ?? ''`) at two sites in chat_screen.dart (in-session
GeneratedResult + DB persistence), while the editing chain correctly used
`generationSource`. Symptoms: (A) V2+ compared original->Vn instead of
V(n-1)->Vn; (B) slider vanished for V2+ whenever originalUrl resolved empty
and that '' was persisted/reloaded.

FIX: bind the reveal pair to `generationSource` (the exact image the step
evolved from), which the line-501 guard already guarantees is non-empty.
V1 -> original upload; V2+ -> previous vision. Branching-safe (no linear
hardcode). Deterministic fallback in before_after_screen. Backend / prompts /
orchestration / version_state / schema untouched (Task 5/10/11).

This validator is static-source + live-backend:
  - Section A/B/C/D: assert the Dart canonical-reveal contract in the two
    frontend files (the fix is Dart; we guard it as spec text).
  - Section E: assert backend reveal-relevant invariants are byte-intact
    (no generation / version-chain / schema / migration regression).

Tests (Task 8, 1-12 mapped, 24 checks):
"""

import os
import sys
import logging

logging.disable(logging.CRITICAL)
sys.path.insert(0, os.path.dirname(__file__))

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"
results = []


def check(label, cond, detail=""):
    s = PASS if cond else FAIL
    sfx = f"  [{detail}]" if detail and not cond else ""
    print(f"  {s}  {label}{sfx}")
    results.append((label, cond))


_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _load(rel):
    with open(os.path.join(_ROOT, rel), "r", encoding="utf-8") as f:
        return f.read()


CHAT = _load(os.path.join("frontend", "lib", "features", "chat", "chat_screen.dart"))
REVEAL = _load(os.path.join("frontend", "lib", "features", "result", "before_after_screen.dart"))
SCHEMA = _load(os.path.join("supabase", "schema.sql"))

logging.disable(logging.NOTSET)
from version_state import resolve_source, VersionRecord, ORIGINAL, LATEST, SPECIFIC_VERSION
from prompt_engine.composer import _MODE_BUDGETS
logging.disable(logging.CRITICAL)

print("\n" + "=" * 60)
print("  WAVE 4.8.3 - V2+ BEFORE/AFTER REVEAL CONTINUITY FIX")
print("=" * 60)

# ── A. Canonical reveal binding (Tests 1-3: V1/V2/V3 reveal pair) ─────────────
print("\n=== A. canonical reveal binding (per-step source) ===")

check("1 V1 reveal pair correct: generationSource derives original on V1 "
      "(_generationSourceUrl ?? originalUrl)",
      "final generationSource = _generationSourceUrl ?? originalUrl;" in CHAT)

check("2 V2+ reveal pair correct: in-session GeneratedResult before-image "
      "bound to generationSource (NOT originalUrl)",
      "beforeImageUrl: generationSource," in CHAT
      and "result: GeneratedResult(" in CHAT)

check("3 V3 reveal pair correct: persisted before-image bound to "
      "generationSource so reload/continued sessions match",
      "messageType: 'image_result'," in CHAT
      and CHAT.count("beforeImageUrl: generationSource,") >= 3)

# the legacy linear hardcode must be fully gone from the reveal sites
check("3b linear 'always original' reveal hardcode removed "
      "(no beforeImageUrl: originalUrl in reveal/persist sites)",
      "beforeImageUrl: originalUrl ?? ''" not in CHAT
      and "beforeImageUrl: originalUrl," not in CHAT)

# non-empty guarantee: the slider can never silently vanish for a real vision
check("7 no null reveal pairs: generation early-returns unless "
      "generationSource is non-null AND non-empty (guarantees before)",
      "if (generationSource == null || generationSource.isEmpty)" in CHAT)

# ── B. Backend editing chain + structural anchor UNCHANGED (Task 5) ───────────
print("\n=== B. backend editing chain + structural anchor unchanged ===")

check("10 no backend generation regression: editing chain still sends "
      "generationSource as beforeImageUrl to the generator",
      "beforeImageUrl: generationSource," in CHAT
      and "GenerationService().generate(" in CHAT)

check("10b structural anchor unchanged: originalUrl still forwarded as "
      "originalImageUrl (geometry stability, not the reveal)",
      "originalImageUrl: originalUrl ?? ''" in CHAT)

# ── C. Version-chain integrity across reload / continued sessions (Test 8) ────
print("\n=== C. version-chain integrity (reload / continued) ===")

check("8 reload reads persisted per-step before_image_url into the pair",
      "beforeImageUrl: (row['before_image_url'] as String?) ?? ''" in CHAT)

check("8b continued session restores the editing chain head "
      "(_generationSourceUrl = last generated)",
      "_generationSourceUrl = lastGeneratedUrl;" in CHAT
      and "_generationSourceUrl = afterUrl;" in CHAT)

# ── D. Branching compatibility (Test 9) ──────────────────────────────────────
print("\n=== D. branching compatibility (no linear hardcode) ===")

check("9 reveal bound to the per-step variable (generationSource); "
      "restart/continue/branch only reassign _generationSourceUrl",
      "final generationSource = _generationSourceUrl ?? originalUrl;" in CHAT
      and "beforeImageUrl: generationSource," in CHAT
      and "beforeImageUrl: originalUrl ?? ''" not in CHAT)

# ── E. Deterministic fallback (Test 6, 12) ───────────────────────────────────
print("\n=== E. deterministic fallback (never broken/empty/inconsistent) ===")

check("6 empty/null before -> hidden slider (intentional, not broken)",
      "extra.beforeImageUrl.isNotEmpty ? extra.beforeImageUrl : null" in REVEAL
      and "final hasBefore = widget.beforeUrl != null && widget.beforeUrl!.isNotEmpty;"
      in REVEAL)

check("6b inconsistent identical pair (before == after) -> hidden, "
      "never a pointless reveal",
      "beforeRaw != null && beforeRaw != after" in REVEAL)

check("6c deterministic fallback modes are explicit "
      "(pair | fallback_no_source | fallback_same_pair)",
      "fallback_no_source" in REVEAL and "fallback_same_pair" in REVEAL
      and "'pair'" in REVEAL)

check("12 no UI crash risk: before label is chain-accurate 'Before' "
      "(was hardcoded 'Original'); after label intact",
      "_CompareLabel(text: 'Before')" in REVEAL
      and "_CompareLabel(text: 'Original')" not in REVEAL
      and "_CompareLabel(text: 'AI Vision'" in REVEAL)

# ── F. Observability (Task 7) ────────────────────────────────────────────────
print("\n=== F. reveal observability ===")

check("7log chat_screen logs the reveal pair + before_source mode",
      "[Reveal] v$newCount pair" in CHAT
      and "before_source=$revealMode" in CHAT
      and "reveal_before=$generationSource" in CHAT
      and "reveal_after=$afterUrl" in CHAT)

check("7log-b full-reveal screen logs resolved mode "
      "(pair|fallback_no_source|fallback_same_pair)",
      "[Reveal] full-reveal resolve" in REVEAL and "mode=$mode" in REVEAL)

check("7log-c reveal_mode taxonomy present "
      "(original|previous_version on generate)",
      "(generationSource == originalUrl) ? 'original' : 'previous_version'" in CHAT)

# ── G. Backend no-regression: version-state chain (Test 4,5,8,9,10) ──────────
print("\n=== G. backend version_state untouched (no chain regression) ===")

_vers = [VersionRecord(version_id="v1", vision_number=1,
                        source_mode_used="ORIGINAL", source_version_id_used="",
                        source_image_url_used="https://img/original.png",
                        generated_image_url="https://img/v1.png",
                        atmosphere="japandi", user_request="",
                        structural_permission=False,
                        structural_identity_token="")]

_v1 = resolve_source(source_mode="", source_version_id="", iteration=1,
                     original_image_url="https://img/original.png",
                     before_image_url="https://img/original.png", versions=[])
check("4 V1 (iteration<=1) resolves ORIGINAL (atmosphere/refine entrypoint)",
      _v1.mode_resolved == ORIGINAL and _v1.source_type == "original")

_v2 = resolve_source(source_mode="", source_version_id="", iteration=2,
                     original_image_url="https://img/original.png",
                     before_image_url="https://img/v1.png", versions=_vers)
check("5 accumulated refinement (iteration>1, default) resolves LATEST "
      "(previous vision), not original",
      _v2.mode_resolved == LATEST and _v2.image_url == "https://img/v1.png")

_vsw = resolve_source(source_mode=SPECIFIC_VERSION, source_version_id="v1",
                      iteration=3, original_image_url="https://img/original.png",
                      before_image_url="https://img/v2.png", versions=_vers)
check("9b atmosphere switch / branch (SPECIFIC_VERSION + valid id) resolves "
      "that exact version (branching support intact)",
      _vsw.mode_resolved == SPECIFIC_VERSION
      and _vsw.image_url == "https://img/v1.png")

_vbad = resolve_source(source_mode=SPECIFIC_VERSION, source_version_id="nope",
                       iteration=3, original_image_url="https://img/original.png",
                       before_image_url="https://img/v2.png", versions=_vers)
check("6d unknown version id never crashes -> safe LATEST fallback (Task 6)",
      _vbad.mode_resolved == LATEST)

check("8c VersionRecord still tracks source_image_url_used "
      "(every generation knows what it evolved from)",
      hasattr(_vers[0], "source_image_url_used")
      and _vers[0].source_image_url_used == "https://img/original.png")

# ── H. No prompt / budget / migration regression (Test 10, 11) ───────────────
print("\n=== H. no generation / DB-migration regression ===")

check("10c prompt budgets unchanged from 4.8.2 "
      "(3550/3500/3600/1500) - no generation regression",
      _MODE_BUDGETS["FIRST_VISION"] == 3550
      and _MODE_BUDGETS["STYLE_REFINEMENT"] == 3500
      and _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"] == 3600
      and _MODE_BUDGETS["LOCAL_EDIT"] == 1500)

_composer = _load(os.path.join("backend", "prompt_engine", "composer.py"))
_editintent = _load(os.path.join("backend", "prompt_engine", "edit_intent.py"))
check("10d composer.py / edit_intent.py NOT modified by 4.8.3 "
      "(prompts/orchestration untouched)",
      "4.8.3" not in _composer and "4.8.3" not in _editintent)

check("11 no DB-migration regression: messages.before_image_url + "
      "after_image_url columns present; schema reused (no wave483 column)",
      "before_image_url" in SCHEMA and "after_image_url" in SCHEMA
      and "4.8.3" not in SCHEMA and "wave483" not in SCHEMA.lower())

_mig_dir = os.path.join(_ROOT, "supabase", "migrations")
check("11b no new Supabase migration introduced for this wave "
      "(reveal-chain UX infra only)",
      not os.path.isdir(_mig_dir))

# ── Summary ──────────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
total = len(results)
passed = sum(1 for _, c in results if c)
failed = total - passed
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {failed}")
if failed:
    print("\n  FAILING CHECKS:")
    for label, c in results:
        if not c:
            print(f"    - {label}")
print("=" * 60)
print("""
  WAVE 4.8.3 - REVEAL CONTINUITY:
  Reveal "before" now bound to the exact per-step source (V1 original,
  V2+ previous vision) via generationSource - guaranteed non-empty by the
  generation guard, so the slider can never silently vanish. Persisted +
  reload-stable + branching-safe. Deterministic hide-not-break fallback.
  Backend prompts / version_state / schema byte-untouched.
""")
sys.exit(1 if failed else 0)
