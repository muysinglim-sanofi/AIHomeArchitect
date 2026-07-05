# QA Image Refine V2 — échantillon réel (sources meublées) + retry

- Scénarios : 15 · erreurs : 0
- **Complets 1ʳᵉ passe : 14/15**
- **Changements appliqués 1ʳᵉ passe : 19/20 = 95%**
- **Drift identité : 0/15**
- Verify indisponible : 0/15
- **Retry : 1 déclenchés, 0 résolus après retry**
- Temps gen : moy 58s · médiane 55s · min 36s · max 93s
- Temps retry : moy 74s
- Coût estimé/refine : gen ~$0.02 + LLM $0.00094 ≈ **$0.021** (gen = ESTIMATION low)

## Par catégorie

| cat | n | complets | applied | drift | retries | retry_fixed |
|---|---|---|---|---|---|---|
| ADD | 2 | 2/2 | 2/2 | 0 | 0 | 0 |
| MOVE | 3 | 2/3 | 2/3 | 0 | 1 | 0 |
| REMOVE | 3 | 3/3 | 3/3 | 0 | 0 | 0 |
| REPLACE | 2 | 2/2 | 2/2 | 0 | 0 | 0 |
| STRUCTURE | 1 | 1/1 | 1/1 | 0 | 0 | 0 |
| COMPLEX | 4 | 4/4 | 9/9 | 0 | 0 | 0 |

## Détail par scénario

| id | cat | status | applied | identity | complete | retry→complete | gen(s) |
|---|---|---|---|---|---|---|---|
| qa_a1 | ADD | verified | 1/1 | OK | True | — | 62 |
| qa_a2 | ADD | verified | 1/1 | OK | True | — | 39 |
| qa_m1 | MOVE | verified | 1/1 | OK | True | — | 36 |
| qa_m2 | MOVE | verified | 1/1 | OK | True | — | 36 |
| qa_m3 | MOVE | incomplete | 0/1 | OK | False | 0/1→False | 55 |
| qa_r1 | REMOVE | verified | 1/1 | OK | True | — | 51 |
| qa_r2 | REMOVE | verified | 1/1 | OK | True | — | 70 |
| qa_r3 | REMOVE | verified | 1/1 | OK | True | — | 73 |
| qa_p1 | REPLACE | verified | 1/1 | OK | True | — | 61 |
| qa_p2 | REPLACE | verified | 1/1 | OK | True | — | 69 |
| qa_c1 | COMPLEX | verified | 2/2 | OK | True | — | 54 |
| qa_c2 | COMPLEX | verified | 2/2 | OK | True | — | 48 |
| qa_c3 | COMPLEX | verified | 3/3 | OK | True | — | 93 |
| qa_s1 | STRUCTURE | verified | 1/1 | OK | True | — | 76 |
| qa_c4 | COMPLEX | verified | 2/2 | OK | True | — | 47 |
