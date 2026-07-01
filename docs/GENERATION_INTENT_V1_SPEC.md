# Generation Intent & Job v1 — Spécification d'architecture

> **Statut** : SPEC — aucune ligne de code tant que ce document n'est pas validé.
> **Auteur** : conception conjointe (user + Claude Opus 4.8), méthode « architecture pro d'abord ».
> **Date** : 2026-06-30
> **Portée** : donner une **existence propre** à chaque intention de génération. On sépare **Intent** (ce que veut l'utilisateur — durable, déterministe, facturable) de **Job** (l'exécution technique — une tentative). Ferme **GATE 1** (frontend ré-émet) et **GATE 2** (backend ré-accepte).
> **V1 impact (pipeline image)** : **NONE** sur la qualité. On ajoute un **claim atomique** d'Intent + des transitions ; le cœur `openai.images.edit` ([main.py:3778](../backend/main.py)) et la stack DNA/preservation/fidelity sont **intouchés**.
> **Prérequis de** : [Billing Engine](BILLING_ENGINE_SPEC.md) — l'`intent_id` défini ici est la clé d'idempotence de `reserve → commit → release`.
> **Note** : remplace `GENERATION_JOB_V1_SPEC.md` (terminologie « Job » unique) — l'entité durable est désormais l'**Intent**, le « Job » est l'exécution technique.

---

## 0 — État actuel (ancrage code, preuve primaire)

> Cartographié par exploration des 2 gates le 2026-06-30. Tout fait cité fichier:ligne.

### 0.1 — Ce qui existe déjà et qu'on RÉUTILISE

| Brique | Où | Rôle |
|---|---|---|
| **`[INTENT-ID]`** : hash déterministe | [main.py:2335-2370](../backend/main.py) — `user:session:src_sha1:iter:room:(mode\|source_mode\|prompt_sha1):atmo:revision` → sha256[:12] | **C'est l'`intent_id`**, aujourd'hui logging-only → à promouvoir en identité |
| **`usage_log`** + reserve/confirm/fail | migration `20260530_wave_5_17b_usage_quota.sql:35-47` ; `quota.py` | Embryon de reserve/commit/release (free-tier) → à **rattacher à l'`intent_id`** |
| Auth ES256 + `current_user` | `auth.py:186-306`, [main.py:2211](../backend/main.py) | `user_id` de confiance |
| Ownership session validé | [main.py:2230-2247](../backend/main.py) | anti quota-bypass par `session_id` forgé |
| `client_request_id` | `generation_service.dart:190-219` | conservé comme **corrélation log** uniquement |
| Réconciliation polling DB | `chat_screen.dart:2051-2142` (5s/90s) | fallback |

### 0.2 — Les 2 gates (ce qu'on FERME)

- **GATE 1 — frontend ré-émet.** Gardes **par-instance widget, RAM, non persistées** : `_isGenerating` ([chat_screen.dart:1405-1414](../frontend/lib/features/chat/chat_screen.dart)), `_succeededGenKeys` (l.156), `_genSeq`/`mySeq` (l.123/1657), `_requestIdForKey` (l.157). `client_request_id` **random** ([l.779-782](../frontend/lib/features/chat/chat_screen.dart)) → widget recréé **re-mint**. `pendingGenerationsProvider` (app-scoped, `pending_generations_provider.dart:22-71`) **perdu au restart d'app**.
- **GATE 2 — backend ré-accepte.** Idempotence **en mémoire-process** : `_idem_results`/`_idem_inflight` ([main.py:167-217](../backend/main.py)). La course concurrente passe quand l'attente inflight **time-out** ([main.py:3420](../backend/main.py)) → **2 appels `openai.images.edit`**.

### 0.3 — Diagnostic en une phrase

> Une génération n'a **pas d'entité partagée persistée**. L'`intent_id` déterministe + persisté donne cette entité — et lui seul ferme les deux gates.

---

## 1 — Ontologie : Intent vs Job *(fondation, FIGÉE 2026-06-30)*

```
INTENT  ── ce que veut l'utilisateur ───────────────  durable · déterministe · FACTURABLE
   │                                                   (1 Intent = au plus 1 débit)
   │ peut donner lieu à 1..N
   ▼
 JOB    ── une exécution technique (une tentative) ──  jetable · 1 appel OpenAI · observabilité
```

**Exemple canonique** :

```
Intent X (Living Room · Warm Modern · revision 0)
   ├─ Job 1  → openai.images.edit → timeout transient
   └─ Job 2  → openai.images.edit → succès
Résultat : 1 Intent, 2 Jobs, 1 seul débit.
```

| | **Intent** | **Job** |
|---|---|---|
| Identité | `intent_id` **déterministe** (hash de l'intention) | `job_id` **aléatoire** (uuid par exécution) |
| Durée de vie | durable (table, source de vérité) | une tentative |
| Facturation | **oui** — reserve/commit/release keyés `intent_id` | non (porte le coût OpenAI réel pour l'audit) |
| Multiplicité | 1 | 1..N par Intent |
| Ce que ferme | GATE 1 + GATE 2 (claim atomique sur `intent_id`) | rien — c'est le log d'exécution |

**Pourquoi cette séparation est saine** : on **facture une intention réussie, pas chaque tentative technique**. Les retries, la reprise après crash, les notifications, les analytics et le support (« que s'est-il passé avec l'Intent X ? ») se branchent tous sur l'Intent. Le Job reste le journal technique.

---

## 2 — Définition de l'`intent_id`

### 2.1 — Promotion du `[INTENT-ID]` existant

On **promeut** le `[INTENT-ID]` ([main.py:2350-2363](../backend/main.py)) de logging vers identité, composition **inchangée** :

```
intent_id = sha256(
   user_id : session_id : src_sha1[:12] : iteration :
   room : (generation_mode | source_mode | prompt_sha1[:8]) : atmosphere : revision
)[:12]
```

| Composant | Source | Sémantique |
|---|---|---|
| `src_sha1` | `source_version_id > original_image_url > before_image_url`, hashé | ancre source stable |
| `room` / `atmosphere` | `*_id > label` (ou `let-decide`/`surprise`) | **intention** (pas la résolue) |
| `prompt_sha1` | sha1 du `prompt`[:8] | direction texte |
| `revision` | `generation_attempt` (sens métier) | Regenerate **incrémente** ; Retry **garde** |

### 2.2 — Gate-of-proof (pré-validée 5/5 en local)

| Action | `intent_id` |
|---|---|
| Retry / re-tir du même intent | **même** (re-attache, pas de re-bill) |
| Regenerate (bouton) | `revision++` → **nouveau** |
| Switch atmosphère | **nouveau** |
| Re-upload / source changée | **nouveau** |
| Surprise me re-tir | atmosphère = `surprise` (stable) → **même** |

---

## 3 — Locus de calcul & propagation *(GJ-OD-1 — FIGÉE 2026-06-30)*

**Le backend est l'unique propriétaire de l'algorithme.** Une seule implémentation → **aucun risque de drift** (espace, trim, locale, encodage, null) entre Flutter et Python.

```
1. Frontend POST /generate avec les infos brutes
   (session, source, room, atmosphere, attempt, trigger, prompt…)   ← PAS de hash côté Dart
2. Backend calcule l'intent_id OFFICIEL                              ← unique implémentation
3. Backend renvoie l'intent_id dans la réponse
4. Frontend MÉMORISE l'intent_id (genKey → intent_id) dans SessionState
5. Toute reprise / statut / retry utilise CE intent_id ; le Billing travaille dessus
```

### 3.1 — Le trou « avant retour de l'ID » (traité honnêtement)

Problème : si le widget est détruit / l'app tuée **avant** l'étape 3, le frontend n'a jamais reçu l'`intent_id`. Il ne peut donc pas (encore) le citer.

**Filet de sécurité** : le frontend persiste, **avant** le POST, le **tuple d'intention** (les infos brutes, pas un hash) keyé par `genKey` dans `SessionState`. Sur recréation/restart, il **renvoie ces mêmes infos** → le backend recalcule **le même `intent_id`** → `INSERT ON CONFLICT` → ré-attachement. Le frontend ne calcule donc **jamais** de hash ; il garantit seulement le **déterminisme des entrées**. Une fois l'ID reçu, il bascule sur les requêtes de statut par `intent_id` (plus léger).

---

## 4 — Quand l'Intent / le Job sont créés

### 4.1 — Intent : claim atomique à l'entrée de `/generate`

```
POST /generate  →  intent_id = compute(...)                     [promotion de main.py:2350-2363]
                →  INSERT INTO generation_intents (intent_id, ...) 
                   ON CONFLICT (intent_id) DO NOTHING  RETURNING status
```

- **Inséré (je possède l'Intent)** → `status = RUNNING` → je crée un **Job** et je continue.
- **Conflit (l'Intent existe)** → je **ne crée pas de Job**, je **ne lance pas OpenAI** → je lis l'état (§5) et je réponds.

> Ce `INSERT ON CONFLICT` (atomique, DB) remplace `_idem_inflight` (mémoire-process) et **ferme la course de GATE 2**, y compris entre workers uvicorn / instances Render.

### 4.2 — Job : un par tentative d'exécution

Une fois l'Intent en `RUNNING`, chaque **tentative** (la boucle de retry interne `max(profile.max_attempts, 2)`, [main.py:3404-3960](../backend/main.py)) crée un **Job** (`generation_jobs`) : insert avant l'appel OpenAI, update à l'issue (succès/échec + coût). Append-only, additif — **ne touche pas** le cœur OpenAI.

### 4.3 — Pré-déclaration frontend *(ferme GATE 1)*

Avant le POST, le frontend persiste le tuple d'intention (§3.1). Sur recréation/restart, **avant** d'auto-générer, il vérifie « ai-je une intention non-terminale pour ce `genKey` ? » → si oui, il **interroge le statut** (§7.2) au lieu de re-générer. Ferme GATE 1 **y compris à travers un restart d'app** (trou actuel).

---

## 5 — Persistance & machine d'état

### 5.1 — Table `generation_intents` *(source de vérité — facturable)*

| Colonne | Type | Notes |
|---|---|---|
| `intent_id` | text PK | hash déterministe (§2.1) |
| `user_id` | uuid FK | RLS `auth.uid() = user_id` |
| `session_id` | uuid FK | indexé |
| `iteration` | int | |
| `status` | text | `RUNNING` \| `SUCCEEDED` \| `FAILED` \| `FAILED_TERMINAL` |
| `intent` | jsonb | `{room, atmosphere, mode, source_mode, src_sha1, revision}` |
| `result_ref` | jsonb NULL | à SUCCEEDED : `{message_id, after_image_url, versions, structural_identity}` (replay) |
| `error` | jsonb NULL | à FAILED : `{type, message}` |
| `reclaim_count` | int | re-claims FAILED→RUNNING ; `CHECK (reclaim_count >= 0)` (borne métier `MAX=3`) |
| `client_request_id` | text | corrélation log |
| `created/updated/started/completed_at` | timestamptz | `updated_at` mis à jour par **trigger** `BEFORE UPDATE` (auto) |

### 5.2 — Table `generation_jobs` *(exécutions techniques — observabilité)*

| Colonne | Type | Notes |
|---|---|---|
| `job_id` | uuid PK | une exécution |
| `intent_id` | text FK | parent ; **`UNIQUE (intent_id, attempt_no)`** (pas 2 Jobs pour la même tentative) |
| `attempt_no` | int **NOT NULL** | 1, 2… dans l'Intent |
| `status` | text | `RUNNING` \| `SUCCEEDED` \| `FAILED` |
| `openai_request_id` | text NULL | corrélation OpenAI |
| `cost_usd_estimate` | numeric | coût **réel** de cette tentative (audit, ≠ facturation) |
| `error_type` | text NULL | `transient` \| `non_transient` (de `classify_for_retry`) |
| `started/ended_at` | timestamptz | |

### 5.3 — Machine d'état de l'Intent

```
                          claim (INSERT ON CONFLICT sur intent_id)
        (aucun)  ─────────────────────────────────────────────►  RUNNING
                                                                    │
                       ┌───────────────────┬────────────────────────┤
                       │ un Job succès      │ tous Jobs transient    │ Job non-transient
                       ▼                    ▼ épuisés                ▼ (content-policy, 4xx…)
                  ┌───────────┐        ┌──────────┐          ┌──────────────────┐
                  │ SUCCEEDED │        │  FAILED  │          │ FAILED_TERMINAL  │
                  └───────────┘        └──────────┘          └──────────────────┘
                   (replay)             │ re-claim                (pas de re-claim,
                                        │ (même intent_id,         surfacé à l'user)
                                        ▼  reclaim_count++)
                                     RUNNING
```

| Transition Intent | Condition | Effet billing (§8) |
|---|---|---|
| (aucun) → `RUNNING` | claim gagné | `reserve(user, intent_id)` |
| `RUNNING` → `SUCCEEDED` | **un** Job réussit + résultat persisté | `commit(intent_id)` |
| `RUNNING` → `FAILED` | tous Jobs transient épuisés | `release(intent_id)` |
| `RUNNING` → `FAILED_TERMINAL` | Job non-transient | `release(intent_id)` |
| `FAILED` → `RUNNING` | retry même intent (`reclaim_count < MAX`) | `release` puis `reserve` (idempotent) |
| `SUCCEEDED` → (rien) | terminal | re-fire → **renvoie `result_ref`**, aucun Job, aucun bill |
| `RUNNING` + 2ᵉ requête | claim perdu | **pas de Job**, renvoie « en cours » |

**Réponse au conflit (claim perdu)** : `SUCCEEDED`→200+`result_ref` ; `RUNNING`→202 `{running}` ; `FAILED`→re-claim si possible, sinon `{failed}` ; `FAILED_TERMINAL`→`{failed_terminal, error}`.

> `FAILED` vs `FAILED_TERMINAL` mappe `classify_for_retry` ([retry_classifier.py:66-147](../backend/retry_classifier.py)).

---

## 6 — Idempotence frontend / backend

| Vecteur | Aujourd'hui | Avec Intent v1 |
|---|---|---|
| Frontend re-mint (widget/restart) | `client_request_id` random | tuple d'intention persisté → mêmes entrées → même `intent_id` → ré-attache (**GATE 1**) |
| Backend re-exécute (worker/restart) | cache mémoire raté → re-bill | `INSERT ON CONFLICT` DB → conflit → pas de Job (**GATE 2**) |
| Course concurrente | inflight wait time-out → 2 OpenAI ([main.py:3420](../backend/main.py)) | un seul gagne le claim ; l'autre voit RUNNING |
| Replay après succès | content-key bloque *après* stockage | `SUCCEEDED` → `result_ref` immédiat |

**Clé d'idempotence unique = `intent_id`** (déterministe, calculée **backend**), partagée frontend↔backend↔billing.

---

## 7 — Intégration avec `/generate`

### 7.1 — Chemin (points d'insertion minimaux)

```
1. (existant) JWT → user_id ; ownership session                 [main.py:2211, 2230-2247]
2. (NEW) intent_id = compute_intent_id(...)                      [promotion de main.py:2350-2363]
3. (NEW) claim = INSERT generation_intents ON CONFLICT DO NOTHING
         ├─ conflit → SUCCEEDED→result_ref | RUNNING→202 | FAILED→reclaim | FAILED_TERMINAL→error
         └─ gagné → status=RUNNING ; renvoie intent_id dans la réponse
4. (NEW, billing) reserve(user_id, intent_id)  → insufficient/no_pass → 402 + rollback Intent
5. (NEW) créer Job (attempt_no) ; (existant) openai.images.edit  ← cœur INTOUCHÉ [main.py:3778]
         (retry interne = nouveaux Jobs sous le même Intent)
6. (existant) compression + upload + INSERT messages             [main.py:4022-4057, 4254-4262]
7. (NEW) succès → Intent=SUCCEEDED (result_ref) + commit(intent_id)
         échec  → Intent=FAILED|FAILED_TERMINAL + release(intent_id)
```

### 7.2 — Endpoint de statut

```
GET /v1/intents/{intent_id}  → 200 { status, result_ref?, error? }
```

Le frontend l'interroge sur ré-attachement (RUNNING) au lieu de re-POSTer. Le polling DB `fetchMessages` ([chat_screen.dart:2051-2142](../frontend/lib/features/chat/chat_screen.dart)) reste en **fallback**.

---

## 8 — Relation avec le Billing Engine

**Le Billing travaille sur l'`intent_id`, jamais sur le `job_id`.** Une Intent = au plus un débit, quel que soit le nombre de Jobs.

| Transition Intent | Hook Billing ([BILLING_ENGINE_SPEC.md](BILLING_ENGINE_SPEC.md) §3.2) |
|---|---|
| → `RUNNING` (claim) | `reserve(user, intent_id)` → `HOLD(-1, key="hold:<intent_id>")` |
| → `SUCCEEDED` | `commit(intent_id)` → `COMMIT(key="commit:<intent_id>")` |
| → `FAILED` / `FAILED_TERMINAL` | `release(intent_id)` → `RELEASE(+1, key="release:<intent_id>")` |

- L'Intent fournit l'**identité** ; le ledger fournit l'**effet crédit**. Idempotents par `intent_id`.
- `usage_log` (free-tier, déjà reserve/confirm/fail) gagne une colonne `intent_id` et **s'aligne**.
- **Le double-bill intra-requête** (2 Jobs facturés par OpenAI sur un même Intent) est un sujet **local** (RemoteProtocolError, jamais reproduit sur Render) et **non** un coût prod — l'Intent garantit **1 reserve / 1 commit** côté **notre** facturation crédit quoi qu'il arrive.

---

## 9 — Échecs / retry / timeout

| Cas | Traitement |
|---|---|
| Échec transient | retry interne → nouveaux **Jobs** sous le même Intent ; si épuisé → Intent `FAILED` → `release` ; re-tir user = même `intent_id` → re-claim |
| Échec non-transient | Intent `FAILED_TERMINAL` → `release` → surfacé ; **pas** de re-claim auto |
| Re-claim borné | `FAILED → RUNNING` tant que `reclaim_count < MAX` (*GJ-OD-2*) |
| Intent orphelin (process mort RUNNING) | **timeout** `> JOB_TIMEOUT` → `FAILED` + `release` par réconciliation. Pas de heartbeat/takeover en v1 (→ v2). |
| Crash après upload, avant SUCCEEDED | réconciliation : `messages` image_result existe mais Intent ≠ SUCCEEDED → réparer SUCCEEDED + commit (idempotent) |

### 9.1 — Frontière v1 / v2

- **v1 (IN)** : `intent_id` déterministe ; tables Intent + Job ; claim atomique (GATE 2) ; frontend persiste l'intent et se ré-attache (GATE 1) ; resume léger (SUCCEEDED→replay, RUNNING→attendre) ; FAILED→re-claim borné ; auto-fail par **timeout**.
- **v2 (OUT)** : reprise active d'orphelin par **heartbeat/takeover** ; job-queue ; push FCM « vision prête » ([pending_job_queue_notifications], [phase_b_fcm_push_setup]).

---

## 10 — Tests d'acceptation *(Given / When / Then)*

**IT-1 — Identité déterministe.** Given une intention I · When `/generate` ×2 mêmes params · Then même `intent_id`.

**IT-2 — Gate-of-proof.** switch/regenerate/re-upload → `intent_id` **différent** ; re-tir / Surprise re-tir → **identique**.

**IT-3 — GATE 2 course concurrente.** 2 requêtes simultanées même `intent_id` → **un seul** OpenAI (1 Job), l'autre 202 `running`.

**IT-4 — Replay après succès.** Intent `SUCCEEDED` → re-fire → `result_ref`, aucun Job, aucun bill.

**IT-5 — GATE 1 restart d'app.** inFlight, app tuée+rouverte → ré-attache via tuple persisté → un seul Intent.

**IT-6 — Retry technique = Jobs multiples, 1 Intent.** Job 1 timeout transient, Job 2 succès → Intent `SUCCEEDED`, 2 lignes `generation_jobs`, **1 seul** `COMMIT`.

**IT-7 — Échec non-transient terminal.** content-policy → `FAILED_TERMINAL`, pas de re-claim, erreur surfacée.

**IT-8 — Orphelin par timeout.** Intent `RUNNING` > `JOB_TIMEOUT` → `FAILED` + `release`.

**IT-9 — Réparation post-upload.** `messages` image_result sans Intent SUCCEEDED → réconciliation → SUCCEEDED + commit (idempotent).

**IT-10 — Une Intent = un débit.** quels que soient N Jobs (retries/re-claims), le ledger ne contient **jamais** plus d'un `COMMIT` non compensé pour un `intent_id`.

---

## 11 — Sécurité & réconciliation

| # | Surface | Mesure |
|---|---|---|
| IS-1 | Identité de confiance | `intent_id` inclut `user_id` du **JWT ES256** ([auth.py:186-306](../backend/auth.py)) + ownership session ([main.py:2230-2247](../backend/main.py)) |
| IS-2 | Claim atomique | `INSERT ON CONFLICT` **DB** (pas mémoire-process), multi-worker |
| IS-3 | RLS | un user ne lit que **ses** `generation_intents`/`generation_jobs` ; écritures service role |
| IS-4 | Anti-forge | `intent_id` **recalculé backend** depuis les params reçus ; jamais fait confiance à un id client |
| IS-5 | Anti-boucle | `reclaim_count < MAX` |
| IS-6 | Observabilité | `generation_jobs` (coût réel/tentative, `openai_request_id`) → détection double-exécution résiduelle |

### 11.1 — Workers de réconciliation (mutualisés avec Billing §8.2)

1. **Stuck intents** — `RUNNING` > `JOB_TIMEOUT` → `FAILED` + `release` (= « stuck holds »).
2. **Post-upload repair** — `messages` image_result sans Intent SUCCEEDED → réparer + `commit`.
3. **Intent/ledger drift** — Intent SUCCEEDED sans COMMIT (ou inverse) → alerte + réconcilier.

---

## 12 — Décisions *(toutes FIGÉES 2026-06-30)*

| ID | Décision figée |
|---|---|
| **Ontologie** | Intent (durable, déterministe, facturable) **vs** Job (exécution technique, 1..N par Intent). Billing keye sur `intent_id`. |
| **GJ-OD-1** | **Backend autoritaire** : calcule l'`intent_id`, le **renvoie** au frontend qui le mémorise. Frontend ne hash jamais ; persiste le tuple d'intention comme filet (pré-retour de l'ID). |
| **GJ-OD-2** | Re-claim `FAILED → RUNNING` : **`MAX=3`**. `FAILED_TERMINAL` **jamais** re-claim. |
| **GJ-OD-3** | **`JOB_TIMEOUT = 12 minutes`** (auto-fail orphelin RUNNING). |
| **GJ-OD-4** | **`GET /v1/intents/{intent_id}` livré en v1.** Polling DB = fallback seulement. |
| **GJ-OD-5** | **`usage_log` gagne `intent_id` dès v1** (aligne free-tier/quota sur l'identité durable). |
| **GJ-OD-6** | **`generation_jobs` (log par tentative) livré dès v1** — support, audit coût OpenAI, debug retry, analytics, preuve « 1 Intent / N Jobs / 1 débit ». |

---

## 13 — Plan d'implémentation Generation Intent v1 *(séquence — à valider avant tout code)*

> Principe : chaque PR est **additive, isolée et vérifiable** ; le cœur `openai.images.edit` n'est jamais touché. On suit le process 7 étapes (`feedback_verify_active_code_path`) : audit chemin actif → test → non-régression → revert-first si casse. On câble dans l'ordre **observabilité d'abord, enforcement ensuite** (on n'allume le comportement qu'une fois la donnée prouvée correcte en prod).

### PR0 — Schéma (DB only, dormant) — **ÉCRIT** : [`supabase/migrations/20260630_generation_intent_v1_pr0_schema.sql`](../supabase/migrations/20260630_generation_intent_v1_pr0_schema.sql)
- Migration : tables `generation_intents` (§5.1) + `generation_jobs` (§5.2) + colonne `intent_id` sur `usage_log` (GJ-OD-5).
- RLS : `auth.uid() = user_id` en lecture ; écritures service role (IS-3). `generation_jobs` lu via le parent Intent.
- Grants explicites (service_role SELECT/INSERT/UPDATE ; authenticated SELECT ; anon rien).
- `session_id` **nullable** : `'new'` (1re génération, non-uuid) → NULL au write (PR1).
- **Aucun** code applicatif ne les lit/écrit encore. Risque = nul (tables inertes).
- *Gate* : à appliquer (Supabase SQL Editor) → sanity-checks en bas du fichier (0 ligne, RLS=true), zéro impact runtime.

### PR1 — `intent_id` promu (calcul, sans enforcement) — **ÉCRIT** : [`backend/intent_observer.py`](../backend/intent_observer.py) + 10 insertions dans [`backend/main.py`](../backend/main.py)
- `compute_intent_id(...)` = fonction **pure**, réplique **byte-identique** de l'ancien `[INTENT-ID]` (prouvé sur 3 cas incl. let-decide/surprise/prompt-vide/SPECIFIC_VERSION → hash inchangé).
- Écrit `generation_intents` (RUNNING à l'entrée, terminal SUCCEEDED/FAILED/FAILED_TERMINAL) + une ligne `generation_jobs` par tentative — **observation pure**, best-effort (avale ses erreurs), **avant** le garde idempotency (mesure NEW/DUP = GATE 2).
- `client_request_id` **inchangé** = clé active. `intent_id` ajouté au payload (propagation/debug, non load-bearing).
- Logs `[INTENT-OBS] intent_start … result=NEW|DUP`, `job_start`, `job_end`, `intent_end`.
- *Gate (prod)* : lire la gate-of-proof (§2.2) + « 1 Intent / N Jobs » sur logs+tables. **Ne rien activer (PR2) tant que ce n'est pas prouvé.**

**PR1.1 — durcissement observation + dashboard** — [`backend/intent_observer.py`](../backend/intent_observer.py) + migration [`…pr1_1_dup_counter_and_dashboard.sql`](../supabase/migrations/20260701_generation_intent_v1_pr1_1_dup_counter_and_dashboard.sql)
- **Transition terminale idempotente/safe-race** : `SUCCEEDED` gagne toujours ; un `FAILED`/`FAILED_TERMINAL` ne peut **jamais** écraser un `SUCCEEDED` (garde `.neq(status,'SUCCEEDED')` sur les écritures d'échec). Corrige une course où un duplicata concurrent aurait pu corrompre la donnée d'observation.
- **`%DUP` en SQL** : colonne `fire_count` + RPC atomique `increment_intent_fire` (incrément sur chaque DUP). `fires = sum(fire_count)`, `DUP = fires − count(*)`.
- **Dashboard** : vues `v_generation_intent_daily` (volume, %NEW/%DUP, succès/échec transient/terminal, running) + `v_generation_jobs_daily` (jobs/intent, transient vs non_transient). Décision PR2 sur données, pas sur tests manuels.

> **RÉORDONNANCEMENT 2026-07-01 (données d'observation)** : PR1 déployé, dashboard opérationnel. Sur 8+ générations manuelles (dont 3 scénarios kill-app), **`dup_pct = 0`** — le doublon GATE 2 **n'est pas reproductible à la main** (phénomène de timing prod). En revanche, le kill-app mid-flight révèle un **bug UX avéré** : session **vide** à la réouverture (détection inFlight en RAM app-scoped `pendingGenerationsProvider`, perdue au kill — [chat_screen.dart:1133-1167](../frontend/lib/features/chat/chat_screen.dart)), résultat visible seulement après sortir/rentrer manuel. **Décision : PR3 AVANT PR2.** PR3 corrige un problème utilisateur tangible ; PR2 (claim) reste **⏸️ en attente** de DUP organiques (le dashboard mesure en parallèle) — le claim est safe-by-construction, donc non urgent tant que `dup_pct=0`.

### PR2 — Claim atomique (ferme GATE 2) — ⏸️ EN ATTENTE (DUP organiques)
- Remplacer l'idempotence mémoire-process ([main.py:167-217](../backend/main.py)) par le claim `INSERT ON CONFLICT (intent_id) DO NOTHING` (§4.1) comme **source de vérité**.
- Brancher la machine d'état Intent (§5.3) + réponses au conflit (SUCCEEDED→replay, RUNNING→202, FAILED→reclaim borné `MAX=3`, FAILED_TERMINAL→error).
- Garder `_idem_results` en cache best-effort **devant** la DB (lecture rapide), non load-bearing.
- *Gate* : IT-3 (course concurrente → 1 seul OpenAI), IT-4 (replay), IT-6 (N Jobs/1 Intent), non-régression /generate nominal.

### PR3 — Reprise d'état (state recovery) après interruption — ▶️ MAINTENANT
> **Design raffiné par l'observation prod (2026-07-01)** : le bug réel n'est pas un re-fire (GATE 1 « théorique »), c'est une **session vide** au kill-app car la détection inFlight vit en RAM (`pendingGenerationsProvider`, perdue au kill). Deux contraintes que l'observation impose :
> 1. **Ré-attache par `session_id`, pas `intent_id`** — l'app tuée avant la réponse `/generate` n'a **jamais reçu** l'`intent_id`.
> 2. **LECTURE SEULE, jamais de re-POST `/generate`** — PR2 (claim) n'existe pas encore, donc un re-POST **créerait** le doublon. La ré-attache doit être un statut read-only + reprise du polling existant.
- **Backend** : `GET /v1/intents/latest?session_id=<id>` → `{intent_id, status, iteration, has_result}` (JWT, user-scoped, **read-only**). (`GET /v1/intents/{intent_id}` §7.2 = complément optionnel.)
- **Frontend** : dans `_loadMessages` ([chat_screen.dart:1133-1167](../frontend/lib/features/chat/chat_screen.dart)), `inFlightResume = pendingGenerations.inFlight OR backend.status==RUNNING`. Si RUNNING → chemin existant (bulle chargement + `_startReconciliationPolling`). Best-effort (échec → comportement actuel).
- *Gate* : kill-app mid-flight → réouverture → spinner + image auto (plus de session vide / reload manuel). Cœur image + `/generate` intouchés.

### PR4 — Réconciliation (timeout + repair)
- Worker : stuck intents `RUNNING > 12 min` → `FAILED` (§11.1 #1, mutualisé « stuck holds » Billing) ; post-upload repair (#2) ; drift alert (#3).
- *Gate* : IT-8 (orphelin), IT-9 (repair post-upload).

> **Billing branché APRÈS** : les hooks `reserve/commit/release` (§8) ne sont câblés qu'à l'étape **Billing Engine** (ordre global [BILLING_ENGINE_SPEC.md](BILLING_ENGINE_SPEC.md) §12). PR0–PR4 livrent l'identité + le lifecycle ; le ledger s'y branche ensuite sur les transitions déjà en place. `usage_log.intent_id` (PR0) prépare cette convergence.

### Séquence & dépendances
```
PR0 (schéma) → PR1 (observabilité, prouver en prod) → PR2 (claim, GATE 2)
                                                          → PR3 (statut + frontend, GATE 1)
                                                          → PR4 (réconciliation)
            puis [Billing Engine] branche reserve/commit/release sur les transitions
```

---

*Spec rédigée par Claude Opus 4.8 (1M). Aucun code, aucun commit. Sépare Intent (facturable) / Job (technique). Ferme GATE 1 + GATE 2. Fournit l'`intent_id` au [Billing Engine](BILLING_ENGINE_SPEC.md). Remplace `GENERATION_JOB_V1_SPEC.md`.*
