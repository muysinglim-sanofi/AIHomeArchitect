# QA Logique Refine V2 — 50 scénarios (couche logique, 0 génération)

| Catégorie | n | anomalies | green | yellow | red | est_succ moy | t_parse | t_advise |
|---|---|---|---|---|---|---|---|---|
| ADD | 10 | 0 | 10 | 0 | 0 | 0.95 | 1.08s | 0.45s |
| MOVE | 10 | 0 | 10 | 0 | 0 | 0.45 | 0.89s | 0.0s |
| REMOVE | 10 | 0 | 10 | 0 | 0 | 0.95 | 0.8s | 0.0s |
| REPLACE | 10 | 0 | 10 | 0 | 0 | 0.78 | 0.81s | 0.0s |
| COMPLEX | 10 | 0 | 10 | 0 | 0 | 0.582 | 1.38s | 0.52s |
| **TOTAL** | 50 | **0** | 50 | 0 | 0 | 0.742 | 0.99s | 0.19s |

## Anomalies détectées

- Aucune anomalie sur la couche logique (50/50).

## Cas Advisor

| id | attendu | obtenu | conf | OK | message |
|---|---|---|---|---|---|
| g1 | green | green | 0.97 | OK | — |
| y1 | yellow_or_red | green | 0.9 | MISMATCH | — |
| y2 | yellow_or_red | yellow | 0.7 | OK | « Add a huge sectional sofa » may be difficult to achieve — A huge sectional may |
| y3 | yellow_or_red | yellow | 0.7 | OK | « Add a large kitchen island » may be difficult to achieve — A large kitchen isl |
| d1 | red | red | 0.9 | OK | As your architect, I don't recommend « Add a Ferrari » — a Ferrari doesn't sensi |
| d2 | red | red | 0.9 | OK | As your architect, I don't recommend « Add a swimming pool » — a swimming pool d |
| d3 | red | red | 0.9 | OK | As your architect, I don't recommend « Add a boat » — a boat doesn't sensibly be |
| d4 | red | red | 0.9 | OK | As your architect, I don't recommend « Add a giant tree » — A giant tree cannot  |
| d5 | red | red | 0.9 | OK | As your architect, I don't recommend « Add a helicopter » — a helicopter doesn't |

**Advisor : 8/9 verdicts conformes.**
**Logique : 50/50 scénarios sans anomalie.**
