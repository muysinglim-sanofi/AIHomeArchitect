# QA FINAL — Refine Engine V2 (Go/No-Go avant Flutter)

**Date :** 2026-07-05 · **Périmètre :** moteur backend assemblé (Parser → Request Advisor →
Normalizer → Conflict Resolver → Smart Planner → Executor → Verify → Retry → async → billing
désactivé → isolation /generate). **Aucun développement pendant cette phase.**

## Méthode (transparence de couverture)
- **Couche logique — EXHAUSTIVE 50/50** (`_refine_qa_logic.py`) : parser+advisor **réels** (LLM),
  normalizer/conflict/planner déterministes, **0 génération image**. + 9 cas Advisor dédiés.
- **Couche image — ÉCHANTILLON RÉEL** (`_refine_qa_image.py`, 15) **+ golden benchmark** (11) =
  **26 générations réelles** gpt-image-2 low sur sources **meublées** (vision V1), avec **retry**
  sur incomplets. Vérifications **visuelles** sur les cas clés (conflit, échecs, complexes).
  → les stats logique sont exhaustives ; les stats image sont **échantillonnées** (26 gens), pas 50.

---

## 1. Couche logique — 50/50 (exhaustif)
| Catégorie | n | anomalies | est_success moy |
|---|---|---|---|
| ADD | 10 | 0 | 0.95 |
| MOVE | 10 | 0 | 0.45 |
| REMOVE | 10 | 0 | 0.95 |
| REPLACE | 10 | 0 | 0.78 |
| COMPLEX | 10 | 0 | 0.58 |
| **TOTAL** | **50** | **0** | 0.742 |

- **Parser** : type dominant correct sur 50/50 ; COMPLEX bien décomposés (jusqu'à 3 changements,
  ex. `structure,replace,add`). **Ordre §10 respecté partout.**
- **Conflict Resolver** : conflits attendus détectés (c02 R-A, c06 R-E) ; **aucun faux positif**.
- **Planner** : `estimated_success` cohérent — flague bien les fragiles (MOVE 0.45, COMPLEX-avec-move ~0.35).
- **Advisor** : **8/9** verdicts conformes. Le seul écart = « Add a TV » (bathroom) → **GREEN**
  (L2 volontairement généreux ; un TV de salle de bain existe en luxe) = **calibration, pas bug**.
  GREEN fast-path (L1) = **t_advise 0 s** → coût LLM évité sur la majorité des edits.

## 2. Couche image — 26 générations réelles (échantillon)
| Source | complets 1ʳᵉ passe | changements | drift identité | Verify indispo |
|---|---|---|---|---|
| QA image (15) | 14/15 | 19/20 = 95% | **0/15** | 0/15 |
| Golden bench (11) | 10/11 | 16/17 = 94% | **0/11** | 0/11 |
| **Cumulé (26)** | **24/26 (92%)** | **35/37 ≈ 95%** | **0/26** | **0/26** |

- **COMPLEX 4/4 (9/9 changements)** sur l'échantillon QA, dont le **conflit réel** (qa_c1 :
  table basse retirée + fleurs re-placées ailleurs, vérifié visuellement).
- **0 drift d'identité sur 26 générations** (règle user : identité ≠ cadrage ; cadrage recomposé = OK).
- **Verify précis** : les 2 seuls INCOMPLETE sont de **vrais négatifs** vérifiés à l'œil
  (qa_m3 rotate sofa non appliqué ; st1 open-kitchen déjà semi-ouverte). **0 faux positif d'identité,
  0 UNAVAILABLE.**

### Temps & coût (mesuré)
| Poste | valeur |
|---|---|
| Génération image (dominant, Moteur 1) | **moy 58 s** · médiane 55 s · min 36 s · max 93 s |
| Parser | ~1,0 s | 
| Advisor | 0 s (L1) → ~1,2 s (L2, rare) |
| Verify | ~3,9 s — **async (hors chemin critique)** |
| **Coût / refine** | ~**$0.021** (gen ~$0.02 estimé low + LLM $0.00094 mesuré) |
| **Coût / retry** | ~$0.021 (1 gen ciblée) |

---

## 3. Erreurs détaillées (P0/P1/P2)
Aucune **P0**, aucune **P1**. Toutes les défaillances sont **honnêtes** (Verify les signale, l'image
est toujours montrée, le retry est user-driven) → **aucune ne casse le contrat « 1 action = 1 gen ».**

| # | Scénario | Cause | Composant | Impact user | Correction recommandée | Gravité |
|---|---|---|---|---|---|---|
| 1 | qa_m3 « Rotate the sofa » (retry aussi KO) | gpt-image-2 ne réoriente pas un gros meuble ancré | **Executor/modèle (Moteur 1)** | changement non appliqué, signalé honnêtement + retry proposé (échoue) | Gater via `estimated_success<seuil → Advisor YELLOW` (hook déjà présent) | **P2** |
| 2 | st1 « Open the kitchen » (cuisine déjà semi-ouverte) | cible structurelle ambiguë | Modèle + ambiguïté requête | idem #1 | idem (YELLOW si structure sans mur clair) | **P2** |
| 3 | Advisor « TV / bathroom » → GREEN | L2 généreux par design | Advisor L2 | requête inhabituelle passe (Verify rattrape la non-application) | resserrer le prompt L2 si data le justifie | **P2** |

**Constante :** les échecs se concentrent sur **ROTATE/gros-MOVE** et **STRUCTURE sans cible claire**
— exactement ce que `estimated_success` (0.45 / 0.80) pré-signale déjà. Le **retry ne « répare » pas
une limite du modèle** (rotate resté KO) : à terme, gater en amont plutôt que retenter aveuglément.

## 4. Isolation
- Endpoints `/refine` + `/refine/verify` : **test ASGI 24/24** — advisory = 0 génération, `/generate`
  toujours enregistré et intact.
- Le package `refine/` n'importe **rien** du composer/DNA/preservation/structural-identity (seule
  réutilisation : `edit_intent._split_changes`, un split regex read-only). **Moteur 1 jamais touché.**

---

## 5. Verdict Go/No-Go (réponses obligatoires)

**1. Déploierais-tu ce moteur en production aujourd'hui ?**
Le **moteur backend + endpoints : OUI** (isolé, testé, honnête). Le **produit user-facing : PAS
ENCORE** — il manque le Flutter et l'**enforcement billing** (câblé mais désactivé). Donc : engine
production-ready ; produit non-shippable tant que 8b + billing ne sont pas branchés.

**2. Risques restants ?**
(a) **Latence gen ~58 s** (Moteur 1, irréductible) — principal risque UX. (b) **Fragilité
ROTATE/gros-MOVE + STRUCTURE ambiguë** (~5 % des changements, honnêtement signalés). (c) **Advisor L2
généreux** (calibration). (d) **Billing désactivé** (pas de quota). (e) Stats image = **échantillon
26 gens**, pas 50 (extrapolation).

**3. Bugs à corriger IMPÉRATIVEMENT avant Flutter ?**
**Aucun (0 P0, 0 P1).** Rien ne bloque l'intégration.

**4. Bugs qui peuvent attendre après lancement ?**
Les 3 P2 : gating `estimated_success→YELLOW` (rotate/structure), calibration Advisor L2, optim
latence (down-scale Verify, déjà async). Enforcement billing = chantier séparé (déjà spécifié).

**5. Tech Lead : GO ou NO-GO pour l'intégration Flutter ?**
**GO.** L'architecture est prouvée de bout en bout (logique 50/50, image 95 %/0 drift, isolation
24/24). Les problèmes restants sont **UX/calibration, pas architecture/logique** — exactement le
seuil que tu as fixé (« Flutter ne doit plus révéler que des problèmes d'interface »).

**6. Notes /10**
| Axe | Note | Justification |
|---|---|---|
| Architecture | **9** | séparation nette, isolé, seams (strategy/confidence/estimated_success), stateless, async-ready |
| Robustesse | **8** | fail-open honnête, Verify 3 états, Conflict Resolver ; fragilité rotate/structure = externe (modèle) |
| UX | **7** | transparent + advisory + retry ; pénalisé par gen ~58 s et rotate KO (à gater) |
| Maintenabilité | **9** | 1 composant/fichier, tests offline chacun, endpoint contigu isolé, spec à jour |
| Performance | **6** | gen ~58 s dominante (Moteur 1) ; overhead LLM bien géré (L1 fast-path + Verify async −4 s) |
| Coût | **8** | ~$0.021/refine ; overhead LLM ~$0.001 négligeable ; Verify 9× l'estimation mais minime |
| Évolutivité | **9** | ExecutionStrategy, hooks confidence/estimated_success, L3 Vision différée, retry engine |
| **Global** | **8,0/10** | **GO franc pour Flutter.** Moteur robuste ; reste = UX + calibration + billing. |
