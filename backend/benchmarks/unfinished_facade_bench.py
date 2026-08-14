"""
Bench FAÇADE INACHEVÉE — flag AYDEN_UNFINISHED_FACADE_COMPLETION (Lot B, 2026-08-13).

SQUELETTE NON LANCÉ. Il manque le seul ingrédient qui compte : un corpus de façades
RÉELLEMENT inachevées. `benchmarks/source/` ne contient aujourd'hui que garden.jpg et
terrace.jpg — aucune façade, aucun chantier. Générer sur des façades terminées ne
prouverait rien (le cas nominal est justement « ne rien faire ») et coûterait des
appels payants pour rien.

ISOLÉ : ne touche PAS main.py. Compose le VRAI prompt (composer + apply_stage_mode),
en A/B sur le MÊME source et la MÊME atmosphère :
    A = build_state "finished"   → prompt de prod d'aujourd'hui (référence)
    B = build_state "unfinished" → prompt gaté (complétion)
Le A/B est le cœur du bench : sans le bras A, aucune dérive géométrique n'est
imputable au bloc de complétion plutôt qu'au modèle.

PROTOCOLE DE NOTATION (grille imprimée à la fin, à remplir à l'œil, en aveugle si
possible — cf. benchmarks/review_build_blind.py) :

  GÉOMÉTRIE — BLOQUANT. Un seul NON = l'image est REJETÉE, quelle que soit la beauté
  du rendu, et la cellule compte comme un échec du bloc de complétion :
    G1  aucun mur déplacé, ajouté, supprimé, élargi ou rétréci
    G2  aucune ouverture déplacée, redimensionnée, ajoutée ou supprimée
        (compter les ouvertures une à une, façade par façade)
    G3  mêmes niveaux / mêmes étages (aucun étage ajouté ou retiré)
    G4  même toiture : même pente, même débord, même faîtage
    G5  mêmes proportions générales et même point de vue caméra
    G6  abords inchangés : allée, murs de clôture, portail, arbres établis

  COMPLÉTION — la valeur produite (noter 0/1 chacun) :
    C1  vitrage posé dans TOUTES les baies qui en manquaient
    C2  porte d'entrée et fermeture de garage en place
    C3  la façade ne se lit plus comme un chantier (enduit / parement finis)
    C4  l'atmosphère est visible (matériaux et lumière de la DNA, pas un rendu neutre)
    C5  aucune invention architecturale (ni balcon, ni auvent, ni volet, ni extension)

  Verdict d'une cellule : PASS si G1..G6 tous OUI ET C1..C3 tous à 1.
  Gate de décision proposé (à confirmer par le client avant tout passage à ON) :
      GÉOMÉTRIE 100 % (zéro violation sur tout le corpus) ET ≥ 80 % de PASS.
  Toute violation géométrique isolée doit rester un NO-GO : c'est la régression que
  le double verrou d'origine existait précisément pour empêcher.

Usage :
    cd backend
    .venv/Scripts/python.exe benchmarks/unfinished_facade_bench.py --src benchmarks/source_unfinished          # dry-run (défaut) : compose + diff les prompts
    .venv/Scripts/python.exe benchmarks/unfinished_facade_bench.py --src benchmarks/source_unfinished --run    # GÉNÈRE (appels payants)

Sorties :
  benchmarks/unfinished_facade/prompts/<src>__<atmo>__<A|B>.txt
  benchmarks/unfinished_facade/out/<src>__<atmo>__<A|B>.png
  benchmarks/unfinished_facade/scoring.md     (grille vide, à remplir)
  benchmarks/unfinished_facade/results.md     (coût + latence)
"""
import argparse, base64, io, os, sys, time
from PIL import Image
from dotenv import load_dotenv

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.dirname(HERE)
sys.path.insert(0, BACKEND)
load_dotenv(os.path.join(BACKEND, ".env"), override=True)

# Le flag est forcé ICI, dans le processus du bench UNIQUEMENT — jamais dans .env,
# jamais sur le serveur. Doit être posé AVANT l'import de preservation (lecture à
# l'appel, mais on ne laisse aucune ambiguïté au lecteur).
os.environ["AYDEN_UNFINISHED_FACADE_COMPLETION"] = "1"

import openai
from prompt_engine.composer import compose_generation_prompt
from prompt_engine.preservation import apply_stage_mode

client = openai.OpenAI()

ATMOSPHERES = [
    ("warm_modern", "Warm Modern"),
    ("soft_luxury", "Soft Luxury"),
    ("japandi_calm", "Japandi Calm"),
    ("nordic_warmth", "Nordic Warmth"),
    ("tropical_escape", "Tropical Escape"),
]
ROOM = "facade"
MODEL = "gpt-image-2"
PRICES = {"img_in": 8.0, "txt_in": 5.0, "out": 30.0}  # USD / 1M tokens
ARMS = [("A", "finished"), ("B", "unfinished")]

GEOMETRY = [
    ("G1", "aucun mur déplacé, ajouté, supprimé, élargi ou rétréci"),
    ("G2", "aucune ouverture déplacée, redimensionnée, ajoutée ou supprimée"),
    ("G3", "mêmes niveaux / mêmes étages"),
    ("G4", "même toiture (pente, débord, faîtage)"),
    ("G5", "mêmes proportions générales et même caméra"),
    ("G6", "abords inchangés (allée, clôture, portail, arbres établis)"),
]
COMPLETION = [
    ("C1", "vitrage posé dans toutes les baies qui en manquaient"),
    ("C2", "porte d'entrée et fermeture de garage en place"),
    ("C3", "la façade ne se lit plus comme un chantier"),
    ("C4", "atmosphère visible (matériaux + lumière de la DNA)"),
    ("C5", "aucune invention architecturale"),
]


def detect_size(path):
    with Image.open(path) as im:
        w, h = im.size
    return "1536x1024" if w > h else "1024x1536" if h > w else "1024x1024"


def compose(atmo_id, atmo_label, build_state):
    """Le VRAI chemin de prod : composer (preserve) puis swap STAGE extérieur."""
    prompt = compose_generation_prompt(
        style_label=atmo_label, room_type=ROOM, room_description="",
        user_instruction="", iteration=1, history=[],
        generation_mode="preserve", edit_mode=None,
    )
    prompt, staged = apply_stage_mode(
        prompt, room_label=ROOM, atmosphere_label=atmo_label,
        atmosphere_id=atmo_id, build_state=build_state,
    )
    return prompt, staged


def cost_usd(u):
    itd = u.input_tokens_details if u else None
    img_in = (itd.image_tokens or 0) if itd else 0
    txt_in = (itd.text_tokens or 0) if itd else 0
    out = (u.output_tokens or 0) if u else 0
    return (img_in * PRICES["img_in"] + txt_in * PRICES["txt_in"]
            + out * PRICES["out"]) / 1_000_000


def save_output(resp, path):
    d = resp.data[0]
    if getattr(d, "b64_json", None):
        open(path, "wb").write(base64.b64decode(d.b64_json)); return True
    if getattr(d, "url", None):
        import urllib.request; urllib.request.urlretrieve(d.url, path); return True
    return False


def write_scoring(path, cells):
    """Grille VIDE, à remplir à l'œil. La géométrie est en tête et bloquante."""
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Bench façade inachevée — grille de notation\n\n")
        f.write("Bras A = prompt de prod actuel (build_state=finished) — RÉFÉRENCE.\n")
        f.write("Bras B = prompt gaté (build_state=unfinished) — sous test.\n\n")
        f.write("**GÉOMÉTRIE = BLOQUANT.** Un seul NON sur G1..G6 ⇒ cellule REJETÉE, "
                "quelle que soit la qualité du rendu.\n\n")
        for code, label in GEOMETRY:
            f.write(f"- **{code}** {label}\n")
        f.write("\nComplétion (0/1) :\n\n")
        for code, label in COMPLETION:
            f.write(f"- **{code}** {label}\n")
        f.write("\n| source | atmosphère | bras | "
                + " | ".join(c for c, _ in GEOMETRY) + " | "
                + " | ".join(c for c, _ in COMPLETION) + " | verdict | note |\n")
        f.write("|---|---|---|" + "---|" * (len(GEOMETRY) + len(COMPLETION) + 2) + "\n")
        for src, atmo, arm in cells:
            f.write(f"| {src} | {atmo} | {arm} |"
                    + " |" * (len(GEOMETRY) + len(COMPLETION)) + "  |  |\n")
        f.write("\nVerdict cellule : PASS si G1..G6 tous OUI ET C1..C3 tous à 1.\n")
        f.write("Gate de décision : GÉOMÉTRIE 100 % ET ≥ 80 % de PASS — sinon NO-GO, "
                "le flag reste OFF.\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(HERE, "source_unfinished"),
                    help="dossier de façades INACHEVÉES (.jpg/.png)")
    ap.add_argument("--run", action="store_true",
                    help="génère réellement (appels payants). Défaut = dry-run.")
    ap.add_argument("--quality", default="low")
    ap.add_argument("--atmo", default="", help="sous-ensemble d'atmosphères, séparées par ','")
    args = ap.parse_args()

    base = os.path.join(HERE, "unfinished_facade")
    OUT_DIR, PROMPT_OUT = os.path.join(base, "out"), os.path.join(base, "prompts")
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(PROMPT_OUT, exist_ok=True)

    atmos = ([a for a in ATMOSPHERES if a[0] in args.atmo.split(",")]
             if args.atmo.strip() else ATMOSPHERES)

    sources = []
    if os.path.isdir(args.src):
        sources = sorted(f for f in os.listdir(args.src)
                         if f.lower().endswith((".jpg", ".jpeg", ".png")))
    if not sources:
        print(f"!! AUCUNE source dans {args.src}.")
        print("!! Le dépôt ne contient PAS de corpus de façades inachevées : ce bench "
              "ne peut pas encore être lancé. Déposer 5 à 10 photos (chantiers réels, "
              "baies sans vitrage, garage ouvert, maçonnerie brute), puis relancer.")

    # ── composition (toujours faite : c'est gratuit et c'est déjà une preuve) ────
    cells, matrix = [], []
    for atmo_id, atmo_label in atmos:
        prompts = {}
        for arm, state in ARMS:
            p, staged = compose(atmo_id, atmo_label, state)
            prompts[arm] = p
            for src in sources or ["(aucune-source)"]:
                stem = os.path.splitext(src)[0]
                open(os.path.join(PROMPT_OUT, f"{stem}__{atmo_id}__{arm}.txt"),
                     "w", encoding="utf-8").write(p)
                matrix.append((src, atmo_id, atmo_label, arm, p, staged))
                cells.append((stem, atmo_id, arm))
        delta = len(prompts["B"]) - len(prompts["A"])
        print(f"  {atmo_id:16} A={len(prompts['A']):5} chars   B={len(prompts['B']):5} "
              f"chars   delta={delta:+5}")
        if delta == 0:
            print(f"  !! {atmo_id}: A et B IDENTIQUES — le flag n'est pas actif, "
                  f"le bench ne mesurerait rien. Vérifier "
                  f"AYDEN_UNFINISHED_FACADE_COMPLETION.")

    write_scoring(os.path.join(base, "scoring.md"),
                  cells if sources else [])
    print(f"Prompts -> {PROMPT_OUT}\nGrille  -> {os.path.join(base, 'scoring.md')}")

    if not args.run or not sources:
        print("\nDRY-RUN : aucune génération, aucun appel payant. "
              "Ajouter --run (et un corpus) pour générer.")
        return

    rows = []
    for src, atmo_id, atmo_label, arm, prompt, staged in matrix:
        path = os.path.join(args.src, src)
        img_bytes, size = open(path, "rb").read(), detect_size(path)
        stem = os.path.splitext(src)[0]
        try:
            f = io.BytesIO(img_bytes); f.name = src
            t0 = time.monotonic()
            resp = client.images.edit(model=MODEL, image=f, prompt=prompt, n=1,
                                      size=size, quality=args.quality)
            dt = time.monotonic() - t0
            out_path = os.path.join(OUT_DIR, f"{stem}__{atmo_id}__{arm}.png")
            save_output(resp, out_path)
            c = cost_usd(resp.usage)
            print(f"OK   {stem:20} {atmo_id:16} {arm} ${c:.4f} {dt:.1f}s")
            rows.append(dict(src=stem, atmo=atmo_id, arm=arm, size=size,
                             cost=f"${c:.4f}", latency=f"{dt:.1f}s",
                             file=os.path.basename(out_path)))
        except Exception as e:
            print(f"FAIL {stem:20} {atmo_id:16} {arm} {type(e).__name__}: {e}")
            rows.append(dict(src=stem, atmo=atmo_id, arm=arm,
                             error=f"{type(e).__name__}: {e}"))

    with open(os.path.join(base, "results.md"), "w", encoding="utf-8") as f:
        f.write(f"# Bench façade inachevée — {MODEL} quality={args.quality}\n\n")
        f.write("| source | atmosphère | bras | size | coût | latence | fichier |\n")
        f.write("|---|---|---|---|---|---|---|\n")
        for r in rows:
            if "error" in r:
                f.write(f"| {r['src']} | {r['atmo']} | {r['arm']} | ERREUR | | | "
                        f"{r['error']} |\n")
            else:
                f.write(f"| {r['src']} | {r['atmo']} | {r['arm']} | {r['size']} | "
                        f"{r['cost']} | {r['latency']} | {r['file']} |\n")
    ok = [r for r in rows if "error" not in r]
    if ok:
        tot = sum(float(r["cost"][1:]) for r in ok)
        print(f"\nTotal {len(ok)} OK -> ${tot:.4f}  (moy ${tot / len(ok):.4f}/img)")
    print(f"Images -> {OUT_DIR}")


if __name__ == "__main__":
    main()
