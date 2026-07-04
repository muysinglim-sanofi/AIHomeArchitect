"""Refine Engine V2 — Composant 4 : EXECUTOR (1 génération).

Le SEUL endroit où le refine appelle `images.edit`. **Moteur 2 isolé** : n'importe
NI main, NI le composer, NI la DNA, NI la préservation. Config = prod refine
(gpt-image-2, quality low, pas d'input_fidelity). 1 appel = 1 génération consommée.
"""
from __future__ import annotations

import base64
import os

# Config image du refine (= prod ; jamais Moteur 1). Rollback = IMAGE_MODEL env.
IMAGE_MODEL = os.environ.get("IMAGE_MODEL", "gpt-image-2")
REFINE_QUALITY = "low"        # figé (P1) ; medium = piste Premium future
REFINE_SIZE = "1536x1024"


async def execute(client, image_bytes: bytes, mime: str, prompt: str) -> bytes:
    """UNE génération : `images.edit(prompt)` sur `image_bytes`. Renvoie les bytes
    PNG du résultat. Lève sur erreur (l'appelant/endpoint décide — un échec ne doit
    pas débiter de crédit). AUCUN autre effet."""
    name = "source.png" if mime == "image/png" else "source.jpg"
    resp = await client.images.edit(
        model=IMAGE_MODEL,
        image=(name, image_bytes, mime),
        prompt=prompt,
        n=1,
        size=REFINE_SIZE,
        quality=REFINE_QUALITY,
    )
    return base64.b64decode(resp.data[0].b64_json)
