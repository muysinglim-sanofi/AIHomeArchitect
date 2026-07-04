"""Refine Engine V2 — validation du Composant 4 (Executor), MOCK (no real image call).
Run: PYTHONPATH=. python _refine_executor_validation.py"""
import asyncio
import base64
import sys

from refine import executor

# 1x1 PNG transparent (b64) que le fake client renverra
_PNG_1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

_fails = 0
def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  got='+repr(got)) if (got and not ok) else ''}")


class _FakeImages:
    def __init__(self): self.kw = None
    async def edit(self, **kw):
        self.kw = kw  # capture les params
        return type("R", (), {"data": [type("D", (), {"b64_json": _PNG_1x1})()]})()

class _FakeClient:
    def __init__(self): self.images = _FakeImages()


async def main():
    client = _FakeClient()
    out = await executor.execute(client, b"SOURCEBYTES", "image/jpeg", "PROMPT HERE")
    kw = client.images.kw
    check("renvoie les bytes décodés du PNG", out == base64.b64decode(_PNG_1x1))
    check("model = IMAGE_MODEL (gpt-image-2)", kw["model"] == executor.IMAGE_MODEL)
    check("quality = low", kw["quality"] == "low")
    check("size = 1536x1024", kw["size"] == "1536x1024")
    check("n = 1 (une seule génération)", kw["n"] == 1)
    check("prompt transmis", kw["prompt"] == "PROMPT HERE")
    check("input_fidelity ABSENT (omis)", "input_fidelity" not in kw)
    name, data, mime = kw["image"]
    check("image = (name, bytes, mime) jpg", data == b"SOURCEBYTES" and mime == "image/jpeg" and name.endswith(".jpg"))
    # mime png → nom .png
    await executor.execute(client, b"X", "image/png", "P")
    check("mime png → source.png", client.images.kw["image"][0].endswith(".png"))

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(asyncio.run(main()))
