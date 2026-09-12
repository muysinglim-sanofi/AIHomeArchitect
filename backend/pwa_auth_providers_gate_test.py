"""The custom-provider gate: a Telegram button appears only when the project
REALLY has `custom:telegram` enabled.

Offline. `telegram_enabled` is the whole decision, so the contract is proved
without a network: GoTrue's own admin payloads in, one boolean out, and every
unexpected shape reads CLOSED.

    backend/.venv/Scripts/python.exe pwa_auth_providers_gate_test.py
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pwa_staging_auth_api as auth_api  # noqa: E402

passed: list = []
failed: list = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (passed if ok else failed).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else '  ' + detail}")


ENABLED = {"providers": [{"identifier": "custom:telegram", "enabled": True,
                          "provider_type": "oidc", "client_id": "x"}]}
DISABLED = {"providers": [{"identifier": "custom:telegram", "enabled": False,
                           "provider_type": "oidc", "client_id": "x"}]}
OTHER = {"providers": [{"identifier": "custom:something-else", "enabled": True}]}

print("\n== the custom-provider gate ==")
check("GATE01 enabled provider -> the door is open",
      auth_api.telegram_enabled(ENABLED) is True)
check("GATE02 provider exists but is DISABLED -> closed (today's production)",
      auth_api.telegram_enabled(DISABLED) is False)
check("GATE03 no providers at all -> closed",
      auth_api.telegram_enabled({"providers": []}) is False)
check("GATE04 a different custom provider does not open Telegram",
      auth_api.telegram_enabled(OTHER) is False)
for label, payload in (
    ("null", None),
    ("a list", [{"identifier": "custom:telegram", "enabled": True}]),
    ("a string", "providers"),
    ("providers not a list", {"providers": {"identifier": "custom:telegram"}}),
    ("enabled as a string", {"providers": [{"identifier": "custom:telegram",
                                            "enabled": "true"}]}),
    ("enabled missing", {"providers": [{"identifier": "custom:telegram"}]}),
):
    check(f"GATE05 malformed payload ({label}) fails CLOSED",
          auth_api.telegram_enabled(payload) is False)

check("GATE06 the identifier is the one production created",
      auth_api.TELEGRAM_IDENTIFIER == "custom:telegram")

src = (HERE / "pwa_staging_auth_api.py").read_text(encoding="utf-8")
check("GATE07 the route answers booleans only — no client id, no secret",
      "client_id" not in src.split("async def auth_providers")[1]
      and "client_secret" not in src.split("async def auth_providers")[1])
check("GATE08 the admin call carries the SERVICE key, never the caller's token",
      'f"Bearer {key}"' in src and "_service_key()" in src)

print(f"\n{'ALL PASS' if not failed else 'FAILED'} "
      f"({len(passed)} passed, {len(failed)} failed)")
raise SystemExit(1 if failed else 0)
