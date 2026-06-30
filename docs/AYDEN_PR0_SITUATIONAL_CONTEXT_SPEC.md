# PR0 — Conscience situationnelle (spec technique)

> **Statut : spec, AUCUN code.** Première brique du chantier Ayden Companion.
> Objectif : avant qu'Ayden réponde, construire la couche qui dit **« où on en est maintenant »**.
> Doctrines amont : [AYDEN_PERSONA_SPEC.md](AYDEN_PERSONA_SPEC.md) · [AYDEN_DESIGN_PRINCIPLES.md](AYDEN_DESIGN_PRINCIPLES.md) · [AYDEN_CONVERSATION_PRINCIPLES.md](AYDEN_CONVERSATION_PRINCIPLES.md).
> **Contraintes dures : pas de LLM dans PR0 · pas de vision input · zéro changement image/refine/DNA/STAGE/`/generate` · fallback actuel intact.**

---

## 0. Principe

PR0 ne change **aucune décision** (ni génération, ni refus, ni voix). Il rend Ayden **conscient**. Il produit un objet `SituationalContext` :
- **assemblé** tôt dans `/chat`,
- **loggé** (`[SITCTX]`),
- **retourné** en JSON propre (prêt pour la future Voice + le futur vision input),
- **injecté légèrement** dans 1-2 réponses déterministes existantes pour prouver que le contexte est vivant — **sans LLM**.

La couche a **deux moitiés** :
- **(A) Faits situationnels** — viennent du **frontend** (déjà en mémoire), transportés en nouveaux champs `/chat` optionnels.
- **(B) Cadre conversationnel** — **dérivé côté backend** des classifieurs déjà exécutés (`classify_meta_intent`, `classify_intent`, `detect_product_help`). Aucune nouvelle entrée.

---

## 1. Les signaux situationnels (liste exacte)

| Signal | Origine | Existe déjà ? | Envoyé à `/chat` aujourd'hui ? | Plan PR0 |
|---|---|---|---|---|
| **room affichée** | FE `_currentRoomType` | ✅ | ✅ (`room_type`) | inchangé |
| **atmosphère courante** | FE `_currentStyle` (suffixe « · Vision N ») | ✅ | ✅ (`style_label`) | inchangé — parser le suffixe proprement |
| **version / itération** | FE `_iterationCount` | ✅ | ✅ (`iteration`) | inchangé |
| **version affichée (id)** | FE `_branchSourceVersionId` / dernière `imageResult` | ✅ en mémoire | ❌ | **nouveau champ** `displayed_version_id` (optionnel) |
| **image visible (after)** | FE `_generationSourceUrl` / dernière `imageResult.afterImageUrl` | ✅ | ❌ | **nouveau champ** `current_image_url` — *hook* futur vision, **non utilisé en PR0** |
| **image source (before / V1)** | FE `_project.beforeImageUrl` | ✅ | ❌ | **nouveau champ** `original_image_url` (optionnel) |
| **génération en cours ?** | FE `_isGenerating` / `_v1Priming` | ✅ | ❌ | **nouveau champ** `generation_in_progress` (bool). Backend n'a aucun état job → seule source fiable = FE |
| **projet vide / a une vision ?** | FE `_hasGenerated` (ou `iteration>1`) | ✅ | ⚠️ dérivable | **nouveau champ** `has_vision` (sinon fallback `iteration>1`) |
| **dernière vision dispo ?** | FE `_versions` / `_hasGenerated` | ✅ | ❌ | couvert par `has_vision` + `current_image_url` |
| **mode actuel** (design / support / action / ambigu / meta) | **Backend, dérivé** des classifieurs | ✅ logique existe | n/a (calculé) | **assemblé** dans `SituationalContext.mode` |
| **question porte sur l'image ?** | **Backend, dérivé** (mode design/coach ∧ `has_vision`) | — | n/a | **dérivé** `is_about_image` |
| **compare / reveal mode** | FE — écran `/result` séparé | ❌ pas dans le chat screen | ❌ | **DIFFÉRÉ** (nécessiterait un nouvel état FE ; hors PR0) |
| **out-of-scope** | — | ❌ pas de garde | ❌ | **PR1** (mode `oos` reste `unknown` en PR0) |

**Lecture clé :** les seuls « manquants » réels sont *compare mode* (différé) et *out-of-scope* (PR1). Tout le reste est soit déjà envoyé, soit en mémoire FE et trivial à transporter.

---

## 2. L'objet `SituationalContext`

Nouveau module **`backend/prompt_engine/situational_context.py`** — un dataclass + un assembleur + un sérialiseur JSON + un formateur déterministe de « préambule contextuel ». Zéro dépendance LLM.

```
SituationalContext:
  # (A) faits — du frontend (defaults sûrs si build FE ancien)
  room_type: str
  atmosphere_id: str
  iteration: int
  has_vision: bool                 # défaut: iteration > 1
  generation_in_progress: bool     # défaut: False
  displayed_version_id: str|None
  current_image_url: str|None      # hook vision futur — NON lu en PR0
  original_image_url: str|None

  # (B) cadre — dérivé backend des classifieurs existants
  mode: Literal["design","support","action","ambiguous","meta","unknown"]
  is_about_image: bool             # design/coach ∧ has_vision
  session_language: str
```

- **Assemblé** dans `/chat` juste après le parsing, **avant** les branches de réponse, en réutilisant `meta`, `intent_class`, `detect_product_help` **déjà calculés**.
- **Sérialisable** en JSON propre (`to_dict()`), renvoyé dans la réponse `/chat` sous une clé `context` (additive, le frontend l'ignore tant qu'il ne s'en sert pas).
- `current_image_url` est **transporté mais jamais ouvert** en PR0 (pas de fetch, pas de modèle) → **zéro latence, zéro coût.** C'est la prise pour le vision input du mode Designer (décision déjà tranchée), branchée plus tard en PR2.

---

## 3. Injection dans les réponses existantes — sans LLM

But : que **même les templates actuels** cessent d'être « morts », en nommant le réel.

- Le pattern existe déjà : `generate_project_aware_greeting` ([main.py:1529](backend/main.py#L1529)) personnalise déjà via `SessionMemory`. PR0 **enrichit l'entrée** de ce type de chemin avec `SituationalContext`.
- Ajout d'un **formateur déterministe** `context_lead(ctx) -> str` (ex. « Sur la version 3 de ta cuisine, … ») appliqué **uniquement** à 2 chemins sûrs : le **fallback générique** (`_GENERAL_RESPONSES`) et le **résumé** (`generate_brief_summary`). Pas touché aux chemins meta/support/refus.
- **Garde-fou anti-robot :** le lead n'est ajouté que si `has_vision` est vrai et qu'il apporte un fait non trivial ; jamais en boucle, jamais sur les réponses qui se suffisent (cf. Conversation Principles §6).

**Important :** PR0 ne prétend pas rendre la voix vivante — ça, c'est la Voice (PR2). PR0 **prouve la tuyauterie** sur 2 spots sûrs et rend le contexte disponible partout.

---

## 4. Préparer la future Voice (sans en dépendre)

- `SituationalContext.to_dict()` = **le contrat d'entrée** que la future Voice consommera tel quel. PR0 le fige maintenant, en JSON propre, indépendant du modèle.
- `current_image_url` y figure déjà → quand la Voice arrivera, le vision input du Designer se branche **sans nouvelle plomberie**.
- PR0 reste **100 % déterministe** : aucun champ n'exige d'appel modèle ; tout est dérivé ou transporté.

---

## 5. Fichiers à modifier

**Backend**
- `backend/prompt_engine/situational_context.py` — **NOUVEAU** (dataclass + assembleur + `to_dict` + `context_lead`).
- `backend/main.py` `/chat` — ajouter les Form params optionnels (defaults sûrs), assembler `SituationalContext`, logger `[SITCTX]`, ajouter `context` à la réponse, brancher `context_lead` sur 2 chemins.

**Frontend** (minimal, additif)
- `frontend/lib/data/services/generation_service.dart` `chat()` — étendre la signature avec params optionnels + les ajouter à `FormData`.
- `frontend/lib/features/chat/chat_screen.dart` (~[appel `/chat` l. 1304]) — passer les valeurs **déjà en mémoire** (`_iterationCount`, `_hasGenerated`, `_isGenerating`/`_v1Priming`, `_branchSourceVersionId`, `_generationSourceUrl`, `_project.beforeImageUrl`).

**Aucun autre fichier.** Rien de la chaîne image (`composer*`, DNA, STAGE, `preservation`, `transformation_classifier`, `/generate`).

---

## 6. Validation

### Logs attendus (`/chat`)
```
=== /chat called === session=... iteration=3
[SITCTX] mode=design is_about_image=True has_vision=True gen_in_progress=False
         room=kitchen atmo=soft_luxury version=v_abc displayed=v_abc img=present
```

### 5 messages de test

| # | Message | `mode` (PR0) | `is_about_image` | Effet PR0 | Encore PR1+ |
|---|---|---|---|---|---|
| a | « Que penses-tu de cette TV ? » | `design` | True (si vision) | contexte loggé + lead possible | vrai avis = Voice (PR2) |
| b | « C'est quoi re-upload ? » | `support` | False | contexte loggé, réponse KB statique inchangée | — |
| c | « Combien il me reste de générations ? » | `support` | False | contexte loggé (question compte) | honnêteté dynamique = **PR1** |
| d | « Tu peux faire mieux ? » | `ambiguous` | — | contexte loggé, clarification existante | — |
| e | « Quelle est la capitale du Japon ? » | `unknown` (pas de match) | False | contexte loggé : aucun match design/support | refus OOS = **PR1** |

PR0 se valide sur **la justesse du `SituationalContext`** (le bon mode, la bonne version, le bon `is_about_image`), pas sur la qualité des réponses — celle-ci vient après.

---

## 7. Risques

1. **Build FE non à jour** → nouveaux champs absents. Mitigation : tous **optionnels avec defaults** ; backend dérive ce qu'il peut (`has_vision←iteration>1`). Fallback strictement intact.
2. **`_currentStyle` porte le suffixe « · Vision N »** → parsing atmosphère. Mitigation : réutiliser `label_to_atmosphere_id` (déjà tolérant).
3. **`generation_in_progress` faux/obsolète** (course FE) → simple signal d'awareness en PR0, **aucune décision** ne s'y appuie encore. Risque nul tant que PR0 ne change pas de comportement.
4. **Sur-injection « robotique »** du `context_lead`. Mitigation : limité à 2 chemins + garde `has_vision` + non répétitif.
5. **Couplage partagé** (`intent_class` lu aussi par `/generate`) → **on ne modifie pas `classify_intent`** en PR0 (on le *lit*). Aucun risque image.
6. **`context` dans la réponse JSON** → additif ; frontend l'ignore. Pas de rupture de contrat.

---

## 8. Plan PR minimal

- **PR0a (backend seul)** — `situational_context.py` + assemblage + log `[SITCTX]` + `context` en réponse, en **dérivant tout** des champs déjà reçus (room, iteration, classifieurs). Aucun changement frontend. Vérifiable immédiatement dans `backend.log`.
- **PR0b (frontend)** — envoyer les champs en plus (`has_vision`, `generation_in_progress`, `current_image_url`, `displayed_version_id`, `original_image_url`). Enrichit le `SituationalContext` ; backend déjà prêt.
- **PR0c (injection)** — `context_lead` sur fallback générique + résumé. Le seul pas qui touche le *texte* visible, le plus petit possible.

Découpage qui permet de **livrer la conscience avant tout transport FE**, et d'arrêter après PR0a/b si on veut garder la voix strictement inchangée jusqu'à la Voice.

---

*Suite : PR1 (Out-of-Scope + honnêteté dynamique) → PR2 (Ayden Voice + vision input Designer).*
