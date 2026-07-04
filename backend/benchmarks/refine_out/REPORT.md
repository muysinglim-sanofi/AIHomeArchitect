# Golden Benchmark Refine V2 — moteur assemblé (Conflict Resolver + Verify 3 états)

- Scénarios : 11  ·  erreurs : 0
- **Complets (tout appliqué) : 10/11**
- **Changements appliqués : 16/17 = 94%**
- **Drift identité : 0/11**
- Verify indisponible : 0/11

| sid | cat | status | applied | identity | conflicts | complete | dt |
|---|---|---|---|---|---|---|---|
| add1 | ADD | verified | 2/2 | OK | 0 | True | 55s |
| rm1 | REMOVE | verified | 1/1 | OK | 0 | True | 43s |
| rp1 | REPLACE | verified | 1/1 | OK | 0 | True | 52s |
| md1 | MODIFY | verified | 1/1 | OK | 0 | True | 49s |
| mv1 | MOVE | verified | 1/1 | OK | 0 | True | 71s |
| mix1 | MIXED | verified | 3/3 | OK | 0 | True | 38s |
| cf1 | CONFLICT | verified | 2/2 | OK | 1 | True | 40s |
| st1 | STRUCTURE | incomplete | 0/1 | OK | 0 | False | 66s |
| st2 | STRUCTURE | verified | 1/1 | OK | 0 | True | 44s |
| ext1 | ADD-EXT | verified | 2/2 | OK | 0 | True | 40s |
| ext2 | ADD-EXT | verified | 2/2 | OK | 0 | True | 41s |
