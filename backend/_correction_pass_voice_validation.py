"""Correction Pass (Groupe 2026-08-13) — Phase 3 : observabilité + garde de capacité.

100% HORS-LIGNE : le client OpenAI est un objet factice (aucun `openai` importé, aucune
socket ouverte, aucun appel image). On pilote DIRECTEMENT les deux fonctions de voix
(prompt_engine/designer_voice.py), qui sont le point exact où le texte est produit puis
restitué — /chat ne fait que relayer leur retour (main.py:2083-2100 : voice → renvoyé,
None → pool localisé).

Matrice couverte :
  BLOC 1  déni de CAPACITÉ GLOBALE (EN + FR)     → texte NON restitué (None → pool) + WARNING
  BLOC 2  constat de SCÈNE (EN + FR)             → texte restitué INTACT (piège anti-filtre)
  BLOC 3  exception client                        → None + WARNING contenant voice/image/err/latency
  BLOC 4  prompt système (3.4a)                   → plus d'ordre « raisonne sur CETTE pièce »
                                                     quand aucune image n'est jointe, et
                                                     mention de capacité présente
  BLOC 5  hygiène des logs                        → aucune URL, aucun prompt dans la trace
  BLOC 6  observabilité parser /refine (3.3)      → parser=llm|fallback|empty exact ET
                                                     comportement de parse_changes inchangé

Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python _correction_pass_voice_validation.py
"""
import asyncio
import contextlib
import logging
import sys
from types import SimpleNamespace

from prompt_engine.designer_voice import (
    _is_capability_denial, _system_prompt,
    generate_designer_voice, generate_execution_voice,
)
from refine.parser import last_parser_source, parse_changes, parse_deterministic

_fails = 0
_total = 0


def check(label, cond, got=""):
    """Un check = 1 ligne ; `got` est TOUJOURS imprimé (valeur observée, pas juste PASS)."""
    global _fails, _total
    _total += 1
    ok = bool(cond)
    _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}   observed={got!r}")


# ── Client factice (aucun réseau) ────────────────────────────────────────────
class _FakeClient:
    """Reproduit la SEULE surface utilisée : client.chat.completions.create(**kw).
    `content` = ce que le modèle est censé répondre ; `exc` = panne simulée."""

    def __init__(self, content=None, exc=None):
        self._content, self._exc = content, exc
        self.last_kwargs = None
        self.chat = SimpleNamespace(completions=SimpleNamespace(create=self._create))

    async def _create(self, **kw):
        self.last_kwargs = kw
        if self._exc is not None:
            raise self._exc
        return SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=self._content))])


class _Capture(logging.Handler):
    def __init__(self):
        super().__init__()
        self.records = []

    def emit(self, record):
        self.records.append(record)

    def warnings(self):
        return [r.getMessage() for r in self.records if r.levelno >= logging.WARNING]


@contextlib.contextmanager
def _capture_logs():
    """Capture le logger applicatif ('aih', cf. main.py:701) sans toucher aux handlers
    fichier existants — on AJOUTE un handler et on le retire."""
    h = _Capture()
    lg = logging.getLogger("aih")
    prev_level = lg.level
    lg.addHandler(h)
    lg.setLevel(logging.DEBUG)
    try:
        yield h
    finally:
        lg.removeHandler(h)
        lg.setLevel(prev_level)


async def _designer(text, *, image=False, language="en"):
    """Fait dire `text` au modèle et renvoie (sortie_restituée, warnings_loggués)."""
    client = _FakeClient(content=text)
    with _capture_logs() as cap:
        out = await generate_designer_voice(
            client, message="Where should the sofa go?", room_type="living_room",
            atmosphere_label="Warm Modern", has_vision=True, language=language,
            image_url="https://example.test/render.jpg" if image else "")
    return out, cap.warnings()


async def _exec_voice(text, *, language="en"):
    client = _FakeClient(content=text)
    with _capture_logs() as cap:
        out = await generate_execution_voice(
            client, message="Move the sofa.", room_type="living_room",
            atmosphere_label="Warm Modern", language=language)
    return out, cap.warnings()


# ═══════════════════════════════════════════════════════════════════════════
async def bloc1():
    """3.4b — un déni de capacité GLOBALE ne doit jamais atteindre l'utilisateur.
    Le contrat de repli est INCHANGÉ : la fonction renvoie None, et l'appelant
    (main.py:2100) sert le pool localisé — exactement comme sur une panne LLM."""
    print("\n=== BLOC 1 — Déni de capacité GLOBALE : NON restitué (→ pool) ===")
    for t in [
        "I cannot generate images.",
        "I'm sorry, but I can't generate images of interiors.",
        "I am unable to create images, but I can describe the change.",
        "I don't have the ability to generate images.",
        "Je ne peux pas générer d'images.",
        "Désolé, je ne suis pas capable de créer des images.",
        "Je n'ai pas la capacité de générer des images.",
        "Je ne peux pas voir d'images.",
    ]:
        out, warns = await _designer(t)
        check(f"designer {t!r} → non restitué", out is None, f"out={out}")
        check(f"designer {t!r} → WARNING loggué",
              any("capability_denial_filtered" in w for w in warns), warns[:1])

    print("  -- même garde sur la voix d'exécution (text-only)")
    out, warns = await _exec_voice("I cannot generate images.")
    check("execution_voice 'I cannot generate images.' → non restitué", out is None,
          f"out={out} warns={warns[:1]}")


async def bloc2():
    """PIÈGE À NE PAS DÉCLENCHER — un constat ancré dans la SCÈNE nomme un objet de la
    pièce, pas « des images » : c'est un propos de designer LÉGITIME (contrat
    anti-paternalisme, advisor.py:15-16) et il doit ressortir MOT POUR MOT."""
    print("\n=== BLOC 2 — Constat de scène : restitué INTACT ===")
    for t, lang in [
        ("I can't clearly see the TV from this angle, but I'd move the sofa.", "en"),
        ("I can't see the rug in this image, so I'd keep the sofa where it is.", "en"),
        ("I cannot judge the ceiling height here — I'd still lower the pendant.", "en"),
        ("Je ne vois pas bien la télé sous cet angle, mais je décalerais le canapé.", "fr"),
        ("Je ne peux pas juger la hauteur sous plafond ici ; je baisserais la suspension.", "fr"),
        ("Je ne vois pas cette image assez nettement, mais je garderais le tapis.", "fr"),
    ]:
        out, warns = await _designer(t, language=lang)
        check(f"{t[:48]!r}… restitué intact", out == t, f"out={out}")
        check(f"{t[:48]!r}… aucun WARNING", not warns, warns)

    print("  -- contrôle direct du prédicat (sans LLM)")
    check("_is_capability_denial('I can't clearly see the TV from this angle')",
          not _is_capability_denial("I can't clearly see the TV from this angle"), False)
    check("_is_capability_denial('I cannot generate images')",
          _is_capability_denial("I cannot generate images"), True)
    check("_is_capability_denial('') == False", not _is_capability_denial(""), False)


async def bloc3():
    """3.1 — l'exception avalée doit laisser une TRACE exploitable, et le repli reste
    propre (None → pool). Mécanisme visé : designer_voice.py, anciens
    `except Exception: return None` sans aucun log."""
    print("\n=== BLOC 3 — Exception client : WARNING + repli propre ===")
    client = _FakeClient(exc=RuntimeError("simulated LLM failure"))
    with _capture_logs() as cap:
        out = await generate_designer_voice(
            client, message="Where should the sofa go?", room_type="living_room",
            atmosphere_label="Warm Modern", has_vision=True, language="en",
            image_url="https://example.test/render.jpg")
    warns = cap.warnings()
    check("designer_voice exception → None (repli pool)", out is None, f"out={out}")
    check("designer_voice exception → exactement 1 WARNING", len(warns) == 1, warns)
    w = warns[0] if warns else ""
    for field in ("voice=designer_voice", "image=yes", "RuntimeError",
                  "simulated LLM failure", "latency_ms="):
        check(f"WARNING contient {field!r}", field in w, w)

    client = _FakeClient(exc=TimeoutError("timed out"))
    with _capture_logs() as cap:
        out = await generate_execution_voice(
            client, message="Move the sofa.", room_type="living_room",
            atmosphere_label="Warm Modern", language="en")
    warns = cap.warnings()
    check("execution_voice exception → None", out is None, f"out={out}")
    check("execution_voice WARNING → tag [AYDEN-EXEC-VOICE] + voice= + image=no",
          bool(warns) and warns[0].startswith("[AYDEN-EXEC-VOICE]")
          and "voice=execution_voice" in warns[0] and "image=no" in warns[0],
          warns)


async def bloc4():
    """3.4a — le prompt ne doit plus ordonner de raisonner sur CETTE pièce comme si elle
    était vue quand AUCUNE image n'est jointe (l'ancienne branche has_vision), et doit
    porter la mention de capacité (conditionnelle, jamais une promesse d'action)."""
    print("\n=== BLOC 4 — Prompt système (image jointe ou non) ===")
    p_noimg = _system_prompt("living_room", "Warm Modern", True, "en", has_image=False)
    p_img = _system_prompt("living_room", "Warm Modern", True, "en", has_image=True)

    check("sans image : ne prétend plus que la pièce est vue ('NOT attached')",
          "NOT attached" in p_noimg and "have NOT seen it" in p_noimg,
          p_noimg[p_noimg.find("A render"):p_noimg.find("A render") + 70])
    check("sans image : plus d'ordre 'reason about THIS room'",
          "reason about THIS room" not in p_noimg, "reason about THIS room" in p_noimg)
    check("avec image : la consigne d'observation est CONSERVÉE",
          "ACTUALLY in THIS image" in p_img, "ACTUALLY in THIS image" in p_img)
    for p, tag in ((p_noimg, "sans image"), (p_img, "avec image")):
        check(f"{tag} : mention de capacité présente",
              "never claim you cannot generate or see images" in p, True)
        check(f"{tag} : formulation CONDITIONNELLE (pas de promesse d'action)",
              "once they ask for it" in p and "I will generate" not in p, True)
        check(f"{tag} : 'Take a clear position' intact (non touché)",
              "Take a clear position" in p, True)


async def bloc5():
    """Hygiène : la trace d'erreur ne doit contenir NI URL (le render est servi par une
    URL potentiellement signée) NI le prompt/message utilisateur."""
    print("\n=== BLOC 5 — Hygiène des logs (pas d'URL, pas de prompt) ===")
    secret = "https://storage.example.test/signed/render.jpg?token=SECRET123"
    client = _FakeClient(exc=RuntimeError(f"connection to {secret} failed"))
    with _capture_logs() as cap:
        await generate_designer_voice(
            client, message="Where should the sofa go?", room_type="living_room",
            atmosphere_label="Warm Modern", has_vision=True, language="en",
            image_url=secret)
    w = cap.warnings()[0] if cap.warnings() else ""
    check("l'URL signée est purgée du log", "SECRET123" not in w and "https://" not in w, w)
    check("l'URL est remplacée par <url>", "<url>" in w, w)
    check("le message utilisateur n'est pas loggué", "Where should the sofa go" not in w, w)
    check("le prompt système n'est pas loggué", "You are Ayden" not in w, w)


async def bloc6():
    """3.3 — le log de /refine doit pouvoir dire QUEL parser a répondu, SANS que le
    comportement de parse_changes bouge d'un iota (le résultat reste la référence :
    fallback ⇒ exactement parse_deterministic)."""
    print("\n=== BLOC 6 — Observabilité parser /refine (llm | fallback | empty) ===")
    msg = "move the sofa to the right wall"

    chs = await parse_changes("", client=None)
    check("message vide → [] + source 'empty'",
          chs == [] and last_parser_source() == "empty", last_parser_source())

    chs = await parse_changes(msg, client=None)
    ref = parse_deterministic(msg)
    check("sans client → source 'fallback'", last_parser_source() == "fallback",
          last_parser_source())
    check("sans client → résultat IDENTIQUE à parse_deterministic (0 changement de comportement)",
          [(c.type, c.object, c.detail, c.raw) for c in chs]
          == [(c.type, c.object, c.detail, c.raw) for c in ref],
          [(c.type, c.object) for c in chs])

    llm_json = ('{"changes":[{"type":"move","object":"sofa",'
                '"detail":"to the right wall","raw":"move the sofa to the right wall"}]}')
    chs = await parse_changes(msg, client=_FakeClient(content=llm_json))
    check("client OK → source 'llm'", last_parser_source() == "llm", last_parser_source())
    check("client OK → le résultat vient bien du LLM",
          len(chs) == 1 and chs[0].object == "sofa", [(c.type, c.object) for c in chs])

    chs = await parse_changes(msg, client=_FakeClient(exc=RuntimeError("LLM down")))
    check("client en panne → source 'fallback' (repli déterministe)",
          last_parser_source() == "fallback", last_parser_source())
    check("client en panne → résultat = parse_deterministic (contrat de repli intact)",
          [(c.type, c.object) for c in chs] == [(c.type, c.object) for c in ref],
          [(c.type, c.object) for c in chs])


async def main():
    print("=== CORRECTION PASS Phase 3 — voix : observabilité + garde de capacité (offline) ===")
    await bloc1()
    await bloc2()
    await bloc3()
    await bloc4()
    await bloc5()
    await bloc6()
    passed = _total - _fails
    print(f"\n=== RÉCAPITULATIF : {passed}/{_total} PASS ({_fails} FAILURE(S)) ===")
    return 1 if _fails else 0


sys.exit(asyncio.run(main()))
