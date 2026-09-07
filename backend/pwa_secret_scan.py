"""SECRET SCAN — prove the ABA PayWay credentials are nowhere they must not be.

Three questions, and the brief wants three NOs:

    ABA API KEY IN GIT         = NO
    ABA API KEY IN WEB BUNDLE  = NO
    ABA API KEY IN LOGS        = NO

How it answers them without becoming the leak
---------------------------------------------
It reads the real values from the ignored staging file and then never prints,
returns, logs or stores them. What it prints is a VERDICT and a location. A
secret scanner that echoes what it found in order to prove it found it is the
most embarrassing possible bug, so the only thing that ever reaches stdout here
is a boolean and a path.

It also refuses to be vacuous. A scan that passes because the file is empty has
proved nothing, so an unconfigured deployment is reported as INCONCLUSIVE for
the value checks — and the STRUCTURAL checks (is the file ignored, does any
tracked file mention the variable with a value, does the web bundle contain the
protocol) run either way, because those are the ones that catch a mistake before
the credentials arrive rather than after.

Run:  cd backend && python pwa_secret_scan.py
"""
from __future__ import annotations

import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent
ENV = HERE / ".env.pwa-staging.local"

#: The PWA frontend is a separate git worktree; both are scanned.
WEB_REPO = pathlib.Path("C:/Projects/ayden-pwa-web")
WEB_BUILD = WEB_REPO / "build" / "web"

LOG_DIRS = [HERE / "logs", REPO / "logs"]

#: Names that must never appear WITH A VALUE in anything tracked.
SECRET_VARS = ("PAYWAY_API_KEY", "PAYWAY_MERCHANT_ID")

#: Protocol the SERVER owns. None of it may be in a browser bundle: a client
#: that could sign a PayWay request is a client that holds the key.
BUNDLE_FORBIDDEN = (
    "checkout-sandbox.payway.com.kh",
    "checkout.payway.com.kh",
    "payment-gateway/v1/payments",
    "generate-qr",
    "check-transaction-2",
    "PAYWAY_API_KEY",
    "PAYWAY_MERCHANT_ID",
    "abapay_khqr",
    "qr_image_template",
)

#: The ONE gateway URL the bundle is allowed to carry, verbatim.
#:
#: ABA's website integration (their guidance of 2026-09-05) requires the
#: merchant page to load their checkout plugin from this exact address; it is
#: how the popup is presented and it is not ours to host or rename. It is
#: removed from the text before the needles above are applied, so the rule
#: "the bundle speaks no PayWay protocol" still holds for everything else on
#: that host — the API paths, the sandbox host, the option names — and a
#: second script from `checkout.payway.com.kh` would still fail this check.
BUNDLE_ALLOWED_VERBATIM = (
    "https://checkout.payway.com.kh/plugins/checkout2-0.js",
)

# The PayWay list above answers "does the browser speak the gateway's
# protocol". It does not answer the OTHER question a public bundle raises:
# does it carry a private credential of any kind. A scanner that checks one
# family of secret certifies the families it did not look for, which is the
# same failure the bundle-reading comment below was written about.
#
# These are PATTERNS, never values: a service-role JWT carries the literal
# `"service_role"` in its base64 payload, which encodes to `InNlcnZpY2Vfcm9sZSI`
# whatever the project. Nothing here is itself a secret, so this file stays
# safe to read and to commit.
#
# DELIBERATELY ABSENT: the production Supabase and backend HOSTNAMES. They are
# compiled into the bundle ON PURPOSE — `app_environment.dart` carries them as
# a reject-list so a web build can refuse to talk to production — so finding
# them proves the guard is present, not that a secret leaked.
BUNDLE_CREDENTIALS = (
    "InNlcnZpY2Vfcm9sZSI",      # base64("service_role") — a service-role JWT
    "SUPABASE_SERVICE_ROLE",
    "OPENAI_API_KEY",
    "sk-proj-",                  # OpenAI project key prefix
    "sk-ant-",                   # Anthropic key prefix
    "REVENUECAT_SECRET",
    "REVENUECAT_API_KEY",
    "DATABASE_URL",
    "postgresql://",
    "postgres://",
)

_PASS: list[str] = []
_FAIL: list[str] = []
_INCONCLUSIVE: list[str] = []


def verdict(label: str, ok: bool, where: str = "") -> None:
    (_PASS if ok else _FAIL).append(label)
    print(f"  [{'OK ' if ok else 'LEAK'}] {label}{'' if ok else f'  -- {where}'}")


def unknown(label: str, why: str) -> None:
    _INCONCLUSIVE.append(label)
    print(f"  [ ?  ] {label}  -- {why}")


def section(title: str) -> None:
    print(f"\n== {title} " + "=" * max(0, 60 - len(title)))


def _values() -> dict[str, str]:
    """The real secrets, read once, held in memory, never printed."""
    if not ENV.exists():
        return {}
    out = {}
    for raw in ENV.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if "=" not in line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip().strip('"').strip("'")
        # Short values are not credentials; treating a 3-character placeholder
        # as a secret would make every file "contain" it.
        if key in SECRET_VARS and len(value) >= 8:
            out[key] = value
    return out


def _git(repo: pathlib.Path, *args: str) -> str:
    try:
        return subprocess.run(["git", "-C", str(repo), *args],
                              capture_output=True, text=True, timeout=120).stdout
    except Exception as exc:  # noqa: BLE001
        return f"__ERROR__{type(exc).__name__}"


def _tracked_files(repo: pathlib.Path) -> list[pathlib.Path]:
    out = _git(repo, "ls-files")
    if out.startswith("__ERROR__"):
        return []
    return [repo / line for line in out.splitlines() if line.strip()]


def _scan(paths, needles: dict[str, str], *, label: str,
          binary_ok: bool = True) -> list[str]:
    """Return the HITS as 'path: which needle' — never the needle's value."""
    hits = []
    for path in paths:
        if not path.is_file():
            continue
        try:
            blob = path.read_bytes()
        except OSError:
            continue
        if not binary_ok and b"\x00" in blob[:1024]:
            continue
        text = blob.decode("utf-8", "ignore")
        for name, value in needles.items():
            if value and value in text:
                hits.append(f"{path.relative_to(path.anchor)}: {name}")
    del label
    return hits


def main() -> int:  # noqa: PLR0915
    print("SECRET SCAN — ABA PayWay credentials\n")
    secrets = _values()
    if secrets:
        print(f"  loaded {len(secrets)} credential value(s) from "
              f"{ENV.name} (values never printed)")
    else:
        print(f"  {ENV.name} holds no PayWay credential values yet")

    # ── 1. the file that holds them is IGNORED ─────────────────────────────
    section("1  the secrets file is ignored by git")
    ignored = _git(REPO, "check-ignore", "-v", str(ENV.relative_to(REPO)))
    verdict("the staging secrets file is gitignored",
            bool(ignored.strip()) and not ignored.startswith("__ERROR__"),
            "backend/.env.pwa-staging.local is NOT ignored")
    tracked = _git(REPO, "ls-files", "--error-unmatch",
                   str(ENV.relative_to(REPO)).replace("\\", "/"))
    verdict("the staging secrets file is not tracked", not tracked.strip(),
            "it is in the index")

    # ── 2. no tracked file assigns a value to a PAYWAY_ variable ───────────
    section("2  no tracked file assigns a PayWay credential")
    # HORIZONTAL whitespace only. `\s*` after the `=` would happily cross the
    # newline and match the NEXT line's variable name as this line's value,
    # which is exactly how the template — whose whole point is empty values —
    # first reported itself as a leak.
    horizontal = r"[^\S\n]"
    assignment = re.compile(
        rf"^{horizontal}*(?:export{horizontal}+)?("
        + "|".join(SECRET_VARS)
        + rf"){horizontal}*={horizontal}*(\S+)",
        re.MULTILINE)
    offenders = []
    for repo in (REPO, WEB_REPO):
        for path in _tracked_files(repo):
            if not path.is_file() or path.suffix in (".png", ".jpg", ".ttf"):
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for match in assignment.finditer(text):
                value = match.group(2)
                # `PAYWAY_API_KEY=` in a template is the whole point of a
                # template. Only a VALUE is a finding.
                if value and value not in ("", '""', "''"):
                    offenders.append(f"{path}: {match.group(1)}")
    verdict("no tracked file assigns a PayWay credential a value",
            not offenders, "; ".join(offenders[:5]))

    # ── 3. the values themselves are in no tracked file, and no history ────
    section("3  the credential VALUES are nowhere in git")
    if not secrets:
        unknown("the credential values are absent from tracked files",
                "no values configured yet — structural checks above still apply")
        unknown("the credential values are absent from git history",
                "no values configured yet")
    else:
        hits = []
        for repo in (REPO, WEB_REPO):
            hits += _scan(_tracked_files(repo), secrets, label="tracked",
                          binary_ok=False)
        verdict("the credential values are in no tracked file", not hits,
                "; ".join(hits[:5]))

        # History, not just the working tree: a value committed and then
        # removed is still published.
        history_hits = []
        for repo in (REPO, WEB_REPO):
            for name, value in secrets.items():
                found = _git(repo, "log", "--all", "-S", value,
                             "--oneline", "--max-count=3")
                if found.strip() and not found.startswith("__ERROR__"):
                    history_hits.append(f"{repo.name}: {name} in "
                                        f"{found.splitlines()[0].split()[0]}")
        verdict("the credential values appear in no commit, ever",
                not history_hits, "; ".join(history_hits[:5]))

    # ── 4. the WEB BUNDLE ──────────────────────────────────────────────────
    section("4  the compiled web bundle")
    if not WEB_BUILD.is_dir():
        unknown("the web bundle holds no PayWay protocol",
                f"{WEB_BUILD} does not exist — run `flutter build web` first")
        unknown("the web bundle holds no PayWay credential", "no bundle")
    else:
        # EVERY delivered file, filtered by what it CANNOT be rather than by
        # what we expect it to be.
        #
        # This used to be an allowlist of suffixes — .js, .json, .html, .wasm,
        # .map, .dart — and on 2026-08-27 that allowlist walked straight past
        # `build/web/assets/.env`, a file Flutter bundles because `pubspec.yaml`
        # declares it as an asset, and which Firebase Hosting then served at a
        # guessable URL with HTTP 200. It held placeholders, so nothing leaked;
        # the scan reporting "NO" while an unread `.env` sat in the payload is
        # the part worth fixing.
        #
        # A scanner that only looks where it expects secrets is a scanner that
        # certifies the places it did not look. So: read everything, and skip
        # only binaries that cannot carry a readable credential.
        _BINARY = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico",
                   ".ttf", ".otf", ".woff", ".woff2", ".mp4", ".webm"}
        bundle = [p for p in WEB_BUILD.rglob("*")
                  if p.is_file() and p.suffix.lower() not in _BINARY]
        found = []
        allowed_seen = []
        for path in bundle:
            try:
                text = path.read_bytes().decode("utf-8", "ignore")
            except OSError:
                continue
            # The plugin include is struck out BEFORE the needles run, so the
            # host name it contains cannot satisfy them — and nothing else on
            # that host can hide behind it, because only this exact string goes.
            for verbatim in BUNDLE_ALLOWED_VERBATIM:
                if verbatim in text:
                    allowed_seen.append(f"{path.name}: {verbatim}")
                    text = text.replace(verbatim, "")
            for needle in BUNDLE_FORBIDDEN:
                if needle in text:
                    found.append(f"{path.name}: {needle}")
        verdict(f"the web bundle ({len(bundle)} files) speaks NO PayWay protocol "
                f"(ABA's plugin include excepted, seen {len(allowed_seen)}x)",
                not found, "; ".join(found[:5]))

        # The same files, asked the other question.
        private = []
        for path in bundle:
            try:
                text = path.read_bytes().decode("utf-8", "ignore")
            except OSError:
                continue
            for needle in BUNDLE_CREDENTIALS:
                if needle in text:
                    private.append(f"{path.name}: {needle}")
        verdict("the web bundle holds NO private credential "
                "(service-role, OpenAI, RevenueCat, database)",
                not private, "; ".join(private[:5]))

        # A NAMED check, because "no PayWay key in it" is not the only thing
        # wrong with shipping a .env to a public host. This one answers the
        # question directly rather than hoping a needle search covers it.
        dotenvs = [p for p in WEB_BUILD.rglob("*")
                   if p.is_file() and (p.name == ".env" or p.name.startswith(".env."))
                   and p.name != ".env.example"]
        # LABEL MATTERS HERE. `answer()` below decides the API-KEY verdicts by
        # substring, and the first version of this line said "the web bundle
        # ships NO .env file" — which flipped "ABA API KEY IN WEB BUNDLE" to
        # YES over a file of placeholders. That is precisely the cry-wolf the
        # comment above `answer()` warns about, committed by the check added to
        # prevent a different one. It gets its own question instead.
        verdict("hygiene: no dotenv file is delivered",
                not dotenvs,
                ", ".join(str(p.relative_to(WEB_BUILD)) for p in dotenvs))
        if secrets:
            leaks = _scan(bundle, secrets, label="bundle")
            verdict("the web bundle holds NO PayWay credential", not leaks,
                    "; ".join(leaks[:5]))
        else:
            unknown("the web bundle holds NO PayWay credential value",
                    "no values configured yet")

    # ── 5. the LOGS ────────────────────────────────────────────────────────
    section("5  the logs")
    logs = [p for d in LOG_DIRS if d.is_dir() for p in d.rglob("*")
            if p.is_file()]
    logs += [p for p in REPO.glob("*.log") if p.is_file()]
    if not logs:
        unknown("no PayWay credential is in a log", "no log files found")
    elif not secrets:
        unknown("no PayWay credential VALUE is in a log",
                "no values configured yet")
    else:
        leaks = _scan(logs, secrets, label="logs")
        verdict(f"no PayWay credential is in any of the {len(logs)} log file(s)",
                not leaks, "; ".join(leaks[:5]))

    # A hash is derived from the key, and §2 of the brief forbids logging one.
    # The adapter strips `hash` before it logs a request; this checks the result
    # rather than the intention.
    if logs:
        hash_lines = 0
        for path in logs:
            try:
                text = path.read_bytes().decode("utf-8", "ignore")
            except OSError:
                continue
            for line in text.splitlines():
                if "[payway" in line and re.search(r"hash['\"]?\s*[:=]", line):
                    hash_lines += 1
        verdict("no PayWay log line carries a hash", hash_lines == 0,
                f"{hash_lines} line(s)")

    # ── report ─────────────────────────────────────────────────────────────
    print(f"\n{'=' * 72}")
    print(f"PASS {len(_PASS)}   LEAKS {len(_FAIL)}   INCONCLUSIVE "
          f"{len(_INCONCLUSIVE)}")
    for name in _FAIL:
        print(f"  LEAK         - {name}")
    for name in _INCONCLUSIVE:
        print(f"  INCONCLUSIVE - {name}")
    print()
    # Answered per question, from the checks that actually address it. A single
    # blanket verdict would report "key in the web bundle = YES" because a
    # template line in git looked wrong, which is the sort of answer that gets
    # a real finding ignored the next time.
    def answer(*labels: str) -> str:
        if any(any(k in name for k in labels) for name in _FAIL):
            return "YES"
        if any(any(k in name for k in labels) for name in _INCONCLUSIVE):
            return "NO (structurally) / INCONCLUSIVE (no values configured yet)"
        return "NO"

    print(f"  ABA API KEY IN GIT        = "
          f"{answer('tracked file', 'commit', 'git history')}")
    print(f"  ABA API KEY IN WEB BUNDLE = {answer('web bundle')}")
    print(f"  ABA API KEY IN LOGS       = {answer('log')}")
    # A separate question, because a delivered .env is a hygiene failure even
    # when it holds nothing secret — and conflating the two makes the serious
    # answer unreadable.
    print(f"  DOTENV IN WEB BUNDLE      = {answer('hygiene: no dotenv')}")
    print("=" * 72)
    return 1 if _FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
