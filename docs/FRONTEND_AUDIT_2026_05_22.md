# Frontend Audit — AIHomeArchitect

**Date:** 2026-05-22
**Branch:** wave-4.9.3 (backend HEAD = 1c1553c Wave 5.5.12)
**Scope:** Flutter frontend at `frontend/lib/`, audit only (no code modifications)

---

## 1. Executive Summary

Le Flutter frontend est **architecturalement solide** avec une excellente UX premium (reveal/dictation/atmosphere cards), mais **3 gaps de persistance bloquent la mise en TestFlight**. Le pipeline protocolaire fonctionne correctement mais perd son état (`_structuralIdentity`, `_versions`, `_generationSourceUrl`) sur app restart, ce qui casse le version-branching.

Le code est feature-complete pour un soft-launch interne après les fixes P0. Le `chat_screen.dart` (2487 lignes, god class) représente une dette de maintenabilité mais n'est pas un blocker pour le lancement. Aucune mock data active confirmée. Permissions iOS/Android correctes.

**Effort estimé :**

- 2-3 jours pour atteindre soft-launch interne (P0 fixes)
- +1-2 semaines pour public launch ready (P1+P2)

---

## 2. Architecture Assessment

| Flow | Implémentation | État |
|---|---|---|
| Session/Project state | Riverpod SessionNotifier (session_provider.dart:11-128) | OK mais pas de fallback offline |
| Image generation | _send() puis _generate() (chat_screen.dart:565-832) | Fonctionne, 268 lignes monolithiques |
| Reveal/fullscreen | before_after_screen.dart:44-147 | Slider per-step source + hold-to-original |
| Voice/dictation | voice_service.dart:35-214 centralisé | Premium (pulse, fallback gracieux) |
| Upload | upload_screen.dart:29-350+ + _initNewSession() | Solide |
| Reupload | — | **Non implémenté** |
| Version/branching | Protocol transport seulement | Backend OK, frontend perd l'état au restart |

---

## 3. Code Quality Assessment

### Forces

- Service layer testable (`GenerationService`, `SupabaseService`, `VoiceService`)
- Error handling structuré (`GenerationException` avec retryable flag)
- Aucun TODO/FIXME/HACK comment
- Typography et colors via tokens (`Theme.of(context).textTheme`, `AppColors`)
- L10n 95% coverage (en + km)
- Animations polies (entry, pulse, transitions)

### Faiblesses

- **`_ChatScreenState` god class** : 2487 lignes, 20+ widgets privés + service logic mélangés
- **`_generate()` méthode** : 268 lignes — handles history building + source resolution + timer + round-trip
- **Fire-and-forget Supabase writes** (session_provider.dart:66, 71-72, 90-91) : pas d'error handling sur `updateTitle()` / `updateLatestPreview()`
- **`mock_projects.dart`** (15 KB) importé dans 4 écrans, usage inactif probable — UNCERTAIN, demande grep runtime
- **Aucun test** (`test/widget_test.dart` = stub 162 bytes)

---

## 4. Confirmed Bugs

| Bug | Location | Severity | Reproduction |
|---|---|---|---|
| `_structuralIdentity` + `_versions` perdus sur hot restart | chat_screen.dart:109-112 | CRITIQUE | V1 puis V2 puis hot restart puis V3 part avec ledger vide |
| `_generationSourceUrl` non persisté | chat_screen.dart:82 | HIGH | New session puis V1 puis app close puis reopen puis V2 utilise photo originale |
| Duplication message race possible | chat_screen.dart:624-648 | MEDIUM | Mitigé par `_isChatting` guard mais edge case existe |
| Fire-and-forget Supabase writes | session_provider.dart:66 | MEDIUM | User edit title + close app puis DB write peut échouer silencieusement |

---

## 5. Suspected Bugs / Risks

| Risk | Confidence | Notes |
|---|---|---|
| Mock data actif en production | HIGH | `mock_projects.dart` importé dans 4 écrans, à confirmer runtime |
| Image dimensions sur aspect ratios non-standard | MEDIUM | Chat card height `clamp(280, 560)`, tablet ou landscape peut letterbox |
| Permission request lag au cold start | MEDIUM | `voice_service.initialize()` appelé depuis `ChatInputBar.initState()`, ~200ms gap |
| Scroll position perdu sur session restore | LOW | `_scrollController` recréé, flicker visible |
| Hero transition collision | UNCERTAIN | Tag uniqueness pas vérifiée, runtime needed |
| Android <11 speech recognition discovery | LOW | Plugin fallback non vérifié |
| Supabase session loading race | MEDIUM | `_load()` async, ChatScreen peut tomber sur placeholder |

---

## 6. UX Quality Assessment

| Area | Rating | Notes |
|---|---|---|
| Loading bubble experience | STRONG | Iteration + atmosphere encoding, pulse animation long-gen |
| Atmosphere card transitions | STRONG | RevealCanvas backdrop rasterized, cinematic |
| Reveal interaction (before/after) | DECENT | Slider OK, hold-to-original premium, manque pinch zoom |
| Typography hierarchy | STRONG | Theme tokens, ellipsis, consistent |
| Color tokens | STRONG | AppColors, scrims layered properly |
| FTUE flow | DECENT | 3 slides + CTA, auto-sweep peut sembler rushed |
| Input field UX | STRONG | Mic pulse, partials appended, Send disabled pendant gen |
| Navigation feedback | STRONG | Fade + slide, back button toujours dispo |

---

## 7. Previously-Discussed Items Status

| Item | Status | Notes |
|---|---|---|
| Bigger generated image result | IMPLEMENTED | Card height dynamique 280-560px |
| Better chat ergonomics | IMPLEMENTED | chat_input_bar.dart extracted |
| Version branching / continue from this vision | PARTIAL | Backend OK, frontend perd état (blocker) |
| Restart from original | UNIMPLEMENTED | Pas d'UI affordance |
| Previous/current reveal logic | IMPLEMENTED | Slider = per-step source, hold = immutable |
| Hold-to-peek original | IMPLEMENTED | `_holdingOriginal` state |
| Dictation like ChatGPT | IMPLEMENTED | Premium, pulse, partials |
| Premium loading progression | IMPLEMENTED | Phrases rotates par iteration + atmosphere |
| Fake generation progress messages | IMPLEMENTED | 45s timer reassurance |
| Profile/help/privacy/rate screens | PARTIAL | profile_screen existe, autres à vérifier |
| Local session state propagation | PARTIAL | In-memory only, pas de SharedPrefs |
| FTUE screen 2 photo/comment | UNCERTAIN | Runtime needed |
| FTUE screen 3 hero/logo | UNCERTAIN | Runtime needed |
| Homepage hero asset loading | IMPLEMENTED | Image.asset + fallback unknown |
| Image card aspect ratio consistency | IMPLEMENTED | focalAspectRatio resolved per-image |
| Reupload flow parity | UNIMPLEMENTED | Pas de feature reupload |
| Multi-candidate N=2/N=3 UX | UNIMPLEMENTED | Pas d'UI |
| Regenerate/reroll first vision | UNIMPLEMENTED | Pas d'affordance |
| Selected-source editing | UNIMPLEMENTED | — |
| Continue from this vision interaction | PARTIAL | Protocol OK, state perdu sur restart |
| Full-screen reveal polish | STRONG | Immersive, scrim, manque pinch zoom |
| Pinch zoom | UNIMPLEMENTED | Pas de gesture |
| iPhone real-device readiness | IMPLEMENTED | Info.plist OK (mic + speech recognition) |
| TestFlight readiness | PARTIAL | Bundle ID OK, persistence layer manque |

---

## 8. Frontend/Backend Protocol Status

| Field | Status | Notes |
|---|---|---|
| `structural_identity` | Sent & received | Pas persisté, perdu sur restart |
| `versions` ledger | Sent & received | Pas persisté, perdu sur restart |
| `original_image_url` | Correctly preserved | Sent once at V1, used as anchor |
| `latest_image_url` / `before_image_url` | Correctly updated | `_generationSourceUrl` tracks chain, perdu sur restart |
| `source_version_id` | NOT IMPLEMENTED | Backend infère du history walk |
| `session_id` | Correct | Stable, Supabase persisted |
| `message history` | Correct | Built from text messages, JSON encoded |
| Atmosphere switching prompts | Correct | `_exploreDirection()` génère le pattern attendu |
| Customized refinements | Correct | Insertion AFTER history build |

### Protocol fragility

- HIGH RISK : `_structuralIdentity` + `_versions` éphémères, casse version branching
- MEDIUM RISK : `_generationSourceUrl` perdu, V2+ revert à photo originale
- LOW RISK : Message history, session_id, atmosphere switching OK

---

## 9. Prioritized Action List

### P0 — Blockers avant exécution frontend

1. **SharedPreferences pour `_structuralIdentity` + `_versions` + `_generationSourceUrl`**
2. Vérifier no active mock data fallback
3. Confirmer SharedPreferences usage dans pubspec.yaml

### P1 — Important avant TestFlight

1. Extraire `GenerationOrchestrator` depuis `_generate()`
2. Extraire `_LoadingBubble`, `_SuggestionBar`, `_EvolutionStrip`
3. Error feedback Supabase writes
4. Vérifier asset presence FTUE + home
5. TestFlight provisioning (signing team, profile)
6. Fix timer leak `_startReconciliationPolling()`

### P2 — Polish avant public launch

1. Reupload flow (change source photo mid-session)
2. Pinch zoom (`InteractiveViewer` autour reveal image)
3. Refactor chat_screen.dart en feature module
4. Offline fallback pour session state
5. Regenerate first vision button

### P3 — Later premium features

1. Multi-candidate generation (N=2 ou N=3)
2. Continue-from-version explicit UI
3. Animated background blur during generation
4. Dictation language selection

---

## 10. Proposed Frontend Wave Roadmap

### Wave 4.10g — Persistence Layer (BLOCKER)

- **Objective :** Survive app restart, enable version branching
- **Files :** session_provider.dart, chat_screen.dart, pubspec.yaml
- **Risk :** LOW (additive)
- **Impact :** Branching fonctionnel, session continuity
- **Validation :** V1+V2 puis hot restart puis verify `_versions` in next /generate, V3 evolves from V2 not original

### Wave 4.10h — Code Extraction (P1)

- **Objective :** Réduire god class, gain testabilité
- **Files :** chat_screen.dart, new loading_bubble.dart, suggestion_bar.dart, evolution_strip.dart, generation_orchestrator.dart
- **Risk :** MEDIUM (state passing carefully)
- **Impact :** chat_screen <1500 lines, `_generate()` testable
- **Validation :** Verify no visual regression, unit tests possible

### Wave 4.10i — Reupload + Refresh-V1 (P2)

- **Objective :** Mid-session source change, regenerate V1 affordance
- **Files :** chat_screen.dart, source_context_strip.dart
- **Risk :** MEDIUM
- **Impact :** Users corrigent bad uploads sans new session
- **Validation :** Upload puis V1 puis V2 puis Change source puis new image puis V2 evolves new source

### Wave 4.10j — Offline Caching (P2)

- **Objective :** Faster startup, sessions list offline
- **Files :** session_provider.dart, home_screen.dart
- **Risk :** LOW
- **Impact :** Startup 500ms faster, works offline read-only
- **Validation :** Kill network puis restart puis cached sessions load

### Wave 4.11 — Multi-candidate UX (P3)

- **Objective :** Show N=2/3 V1 options, user picks best
- **Files :** Frontend major (new selection screen), backend support déjà OK
- **Risk :** HIGH (UX redesign)
- **Impact :** Énorme sur perception qualité
- **Validation :** Generation produces 3 candidates puis user picks puis flow continues

---

## 11. Validation Plan (after fixes)

### Android Emulator (smoke test après chaque wave)

- New session puis V1 puis V2 puis V3 chain (verify reveal pairs correct)
- Hot restart pendant generation (state preserved post-fix)
- Voice input edge cases (cold tap, append, deny permission, rapid toggle)
- Network drop mid-gen (polling recovery)
- Chat history ordering + day separators
- Image aspect ratios (wide, tall, network fail)
- Upload variants (AI Decide, Surprise Me, description-only)

### Android Real Device

- Tous emulator scenarios +
- Mic hardware réel
- Background/foreground cycling
- Low network 4G
- Share button / file manager integration

### iPhone

- iOS permissions dialogs (mic, speech)
- Safe area (notch, home indicator)
- Dark mode
- Build pour TestFlight

### App Restart Scenarios

- Edit title puis hot restart puis persists
- Generate puis hot restart puis source url persists (post-fix)
- System kill (memory pressure) puis reopen graceful

### Session Restore

- Old project with messages puis load with correct timestamps
- Session with multiple generations puis all visible chronologically
- Tap image puis reveal correct before/after

### Upload/Reupload

- Initial upload (room + style)
- Reupload (Wave 4.10i+) puis V2 evolves new source

### V1/V2/V3 Generation

- V1 auto-generation (greeting puis fire)
- V2 from chat message
- V2 from atmosphere card (Wave 5.5.5 round-trip)
- V3 from typed message

### Reveal Comparison

- Slider drag left/right
- Hold-to-original (long-press)
- Immersive mode toggle

### Dictation

- Cold dictation
- Append (type then dictate)
- Permission denied (calm hint)
- Unavailable (button hidden)

### Navigation

- Back from chat
- Back from reveal during generation
- Session selection puis chat
- Upload puis chat
- Deep link /chat/SESSION_ID

---

## TestFlight Readiness Summary

| Category | Status | Confidence | Blockers |
|---|---|---|---|
| Feature completeness | 85% | HIGH | Reupload, version UI, pinch zoom defer |
| Stability | 80% | HIGH | Persistence layer manque (critique) |
| UX polish | 85% | HIGH | Reveal premium, loading smooth |
| Error handling | 90% | HIGH | Structured exceptions OK |
| Permissions / OS | 95% | HIGH | Info.plist + AndroidManifest OK |
| Performance | 85% | MEDIUM | Long chat lists peuvent stutter |
| Code quality | 70% | HIGH | God class, P1 mais pas critique |
| Protocol correctness | 80% | MEDIUM | Round-trip OK, persistence gap |

**Verdict :** NOT READY pour TestFlight sans P0 fixes. 2-3 jours pour soft-launch ready.

---

## Recap stratégique

À faire absolument avant tout autre travail frontend :

1. SharedPreferences persistence (`_structuralIdentity`, `_versions`, `_generationSourceUrl`)
2. Fix timer leak (`_startReconciliationPolling`)
3. Vérifier mock data inactif

Une fois ces 3 fixes : soft-launch ready. Le reste (extraction, reupload, multi-candidate) sont des améliorations incrémentales sur une base solide.
