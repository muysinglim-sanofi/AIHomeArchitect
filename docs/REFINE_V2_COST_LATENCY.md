# Refine V2 — Coût & latence RÉELS par composant (mesuré 2026-07-04)

Mesure directe (`backend/_refine_cost_probe.py`, N=20, appels gpt-4o-mini réels, tokens via
`usage`). **Aucune estimation.** Tarifs gpt-4o-mini : in $0.15/1M · out $0.60/1M.

| Composant | Latence moy | p50 | max | tok in | tok out | **Coût / appel** | Quand |
|---|---|---|---|---|---|---|---|
| **Parser** (gpt-4o-mini texte) | ~1620 ms | 1500 ms | 3859 ms | 173 | 74 | **$0.000071** | chaque refine |
| **Advisor L2** (gpt-4o-mini texte) | ~1172 ms | 945 ms | 2797 ms | 152 | 31 | **$0.000041** | seulement si ESCALATE |
| **Verify** (gpt-4o-mini **vision**, 2 images low) | ~3885 ms | 3804 ms | 4828 ms | 5738 | 24 | **$0.000875** | chaque refine |

## Coût LLM d'un Refine (hors génération image)
| Cas | Coût LLM | Latence LLM ajoutée |
|---|---|---|
| **GREEN** (Advisor L1, 0 appel LLM) | **$0.00095** | **+~5,5 s** (Parser + Verify) |
| **ESCALADE** (Advisor L2 appelé) | **$0.00099** | **+~6,7 s** (Parser + Advisor + Verify) |

## Lectures clés
- **Le Verify domine l'overhead LLM** : ~$0.00088 et **~3,9 s** à lui seul. Les 2 images en
  `detail:low` coûtent **5738 tokens** sur gpt-4o-mini (≈ 9× mon estimation initiale de $0.0001).
  Toujours négligeable en $ (~0,09 ¢), mais **~4 s de latence** s'ajoutent à chaque refine.
- **Parser + Advisor sont quasi gratuits** (< $0.0001, ~1–1,6 s). L'Advisor L1 (règles) évite
  l'appel L2 sur la grande majorité des edits → coût Advisor souvent **$0**.
- **La génération `gpt-image-2 low` reste le poste dominant** (coût + 15–40 s), mesurée via la
  télémétrie `/generate` — l'overhead LLM (~$0.001, +5,5 s) est marginal devant elle.

## Pistes d'optimisation (si la latence Verify gêne)
- Down-scaler les 2 images avant le Verify (réduit les ~5738 tokens → latence).
- Sauter le Verify quand le plan ne contient qu'**1 changement combinable** trivial (faible risque).
- Ces pistes sont **hors périmètre Moteur 1** (Verify = Moteur 2) — à décider plus tard.
