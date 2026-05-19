"""
Wave 4.9.3b validation - Confirmation Boundary Fix (post-freeze critical bugfix).

4.9.3a proved: when generation is triggered by a confirmation ("go ahead"),
the frontend echoes that confirmation into the /generate history as the
NEWEST prior_user turn. accumulate_refinements then hit its
`is_confirmation -> reset` boundary on that trailing echo and wiped the
freshly-collected pending batch, so AUTHORIZED USER CHANGES went empty and
the pending request (roses/plants) was lost.

Fix (Option A, surgical, backend-only): exempt the SINGLE trailing
prior_user turn from the reset boundary, and ONLY when it is a confirmation
equal to current_prompt and current_prompt is itself that confirmation
(the frontend echo of the triggering confirmation). Older confirmations
remain reset boundaries -> cross-generation anti-leak byte-unchanged.

Scenarios (Task 3, A-F) + control:
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


logging.disable(logging.NOTSET)
from prompt_engine.refinement_authority import (
    accumulate_refinements, build_authorized_changes_clause)
logging.disable(logging.CRITICAL)


def acc(history, prompt):
    return accumulate_refinements(history, prompt)


print("\n" + "=" * 60)
print("  WAVE 4.9.3b - CONFIRMATION BOUNDARY FIX")
print("=" * 60)

# ── A. The reported bug: pending request survives the triggering go-ahead ──
print("\n=== A. confirmation executes the pending batch ===")
A = acc([
    {"role": "user", "content": "Can you add rose and plant"},
    {"role": "ai", "content": "Lovely — shall I go ahead?"},
    {"role": "user", "content": "Go ahead"},
    {"role": "ai", "content": "Applying that now."},
], "Go ahead")
check("A1 pending request recovered (roses + plant present)",
      "rose" in A.text.lower() and "plant" in A.text.lower(),
      f"text={A.text!r}")
check("A2 not collapsed to the bare confirmation",
      A.text.strip().lower() not in ("", "go ahead"),
      f"text={A.text!r}")
check("A3 AUTHORIZED USER CHANGES clause now non-empty",
      bool(build_authorized_changes_clause(A.text or "Go ahead", 3)))

# ── B. Multi-item stacked batch survives the go-ahead ──────────────────────
print("\n=== B. stacked batch retained ===")
B = acc([
    {"role": "user", "content": "turn rear room into bedroom"},
    {"role": "ai", "content": "ok?"},
    {"role": "user", "content": "also add roses"},
    {"role": "ai", "content": "ok?"},
    {"role": "user", "content": "go ahead"},
], "go ahead")
check("B1 bedroom retained", "bedroom" in B.text.lower(), f"text={B.text!r}")
check("B2 roses retained", "rose" in B.text.lower(), f"text={B.text!r}")
check("B3 both items ordered (2 items)", B.append_count >= 2,
      f"items={B.items}")

# ── C. Atmosphere switch + go-ahead — Task 5 invariant unchanged ──────────
print("\n=== C. atmosphere switch preserved (no spurious accumulation) ===")
C = acc([
    {"role": "user", "content": "switch to Japandi"},
    {"role": "ai", "content": "ok?"},
    {"role": "user", "content": "go ahead"},
], "go ahead")
check("C1 atmosphere switch does NOT accumulate (flows via style_label)",
      C.text == "", f"text={C.text!r}")

# ── D. Bare confirmation with no pending actionable request ───────────────
print("\n=== D. no pending request -> no accidental accumulation ===")
D = acc([
    {"role": "user", "content": "what do you think of this?"},
    {"role": "ai", "content": "I like it."},
    {"role": "user", "content": "go ahead"},
], "go ahead")
check("D1 no spurious accumulation", D.text == "", f"text={D.text!r}")

# ── E. Anti-leak: completed batch must NOT resurface on a later go-ahead ──
print("\n=== E. cross-generation anti-leak preserved (CRITICAL) ===")
E = acc([
    {"role": "user", "content": "add roses"},
    {"role": "user", "content": "go ahead"},          # triggered gen #1
    {"role": "ai", "content": "(generated #1)"},
    {"role": "user", "content": "looks nice"},
    {"role": "ai", "content": "glad you like it"},
    {"role": "user", "content": "go ahead"},          # current trigger, unrelated
], "go ahead")
check("E1 old 'add roses' does NOT leak into the later go-ahead",
      "rose" not in E.text.lower() and E.text == "",
      f"text={E.text!r}")

# ── F. Only the trailing echo is exempted; older confirmations still reset ─
print("\n=== F. older confirmations still reset (echo-only exemption) ===")
F = acc([
    {"role": "user", "content": "add a lamp"},
    {"role": "user", "content": "go ahead"},          # older confirm -> resets lamp
    {"role": "ai", "content": "(gen #1)"},
    {"role": "user", "content": "add a rug"},
    {"role": "ai", "content": "shall I?"},
    {"role": "user", "content": "go ahead"},          # trailing echo (current)
], "go ahead")
check("F1 older 'go ahead' still reset 'add a lamp'",
      "lamp" not in F.text.lower(), f"text={F.text!r}")
check("F2 only post-reset 'add a rug' retained",
      "rug" in F.text.lower(), f"text={F.text!r}")

# ── Control / regression guards ───────────────────────────────────────────
print("\n=== control: non-confirmation path byte-unchanged ===")
G = acc([{"role": "user", "content": "make it warmer"}], "make it warmer")
check("G1 normal non-confirmation prompt unchanged (zero regression)",
      G.text == "make it warmer", f"text={G.text!r}")

# Echo exemption must require BOTH current_prompt AND trailing turn to be the
# SAME confirmation — a non-confirmation current_prompt must not exempt.
H = acc([
    {"role": "user", "content": "add a sofa"},
    {"role": "user", "content": "go ahead"},
    {"role": "ai", "content": "(gen #1)"},
    {"role": "user", "content": "make it warmer"},
], "make it warmer")
check("H1 non-confirmation current_prompt: trailing 'go ahead' still resets "
      "(no over-exemption); only 'make it warmer' kept",
      "sofa" not in H.text.lower() and "warmer" in H.text.lower(),
      f"text={H.text!r}")

# Exemption removes exactly ONE trailing turn (not all confirmations).
I = acc([
    {"role": "user", "content": "add a plant"},
    {"role": "user", "content": "go ahead"},   # older — must still reset
    {"role": "ai", "content": "(gen #1)"},
    {"role": "user", "content": "add curtains"},
    {"role": "user", "content": "go ahead"},   # trailing echo (exempted)
], "go ahead")
check("I1 single-turn exemption: 'add a plant' reset, 'add curtains' kept",
      "plant" not in I.text.lower() and "curtain" in I.text.lower(),
      f"text={I.text!r}")

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
  WAVE 4.9.3b - CONFIRMATION BOUNDARY FIX:
  The triggering confirmation echoed into /generate history no longer
  wipes its own pending batch. Older confirmations still reset
  (anti-leak unchanged). Backend-only, conversational-boundary logic;
  no prompt/DNA/topology/runtime/atmosphere/quality surface touched.
""")
sys.exit(1 if failed else 0)
