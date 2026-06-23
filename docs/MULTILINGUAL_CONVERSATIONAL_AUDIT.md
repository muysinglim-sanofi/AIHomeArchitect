# AYDEN Studio — Multilingual Conversational Integration (FR/KM/EN)
## Architecture Audit & Design (audit/design only — NO implementation)

Date: 2026-06-15 · Scope: add FR/KM/EN conversation while keeping the
image-generation pipeline **English-internal canonical**. No engine/prompt/DNA
changes proposed here — this is the design that *precedes* any code.

Target architecture (confirmed sound):
```
User FR/KM/EN  →  language detect  →  normalize to English (instruction)
              →  English-only orchestration / classification / generation
              →  localized conversational reply (FR/KM/EN)
```

---

## 1. Current language flow (as built)

### 1.1 Frontend (Flutter)
- **Locale**: `en | fr | km`, chosen in Profile → language picker. Stored
  **in-memory only** (`localeProvider`); **NOT persisted** — reverts to `en` on
  cold start. (Bug to fix in Phase 1.)
- **Room / atmosphere are already English-normalized** (good):
  `roomTypeId = RoomTypeImages.idForLabel(...)` and
  `atmosphereId = atmosphereIdFromLabel(styleLabel)` route **canonical English
  ids**. `room_type` display label is localized but the id is what gates DNA
  (see `room_type_i18n_contract`). ✅
- **User free-text is sent VERBATIM in the user's language** — TWO entry points:
  - Upload Step 4 "Describe your dream space" → `_pendingDescription` → V1 prompt.
  - Chat refinement message (`_send`) → `prompt` on `/generate` + `/chat`.
- **`history`** is JSON of raw messages → **mixed language** (user FR/KM + AI EN).
- **AI replies + suggestion chips** are shown **verbatim from the backend** — i.e.
  currently English regardless of UI locale.
- **Voice (STT)** uses `speech_to_text` with `localeId: null` → **device default
  language**, not the UI locale. No language threading.

### 1.2 Backend (FastAPI)
- **Vision / capture prompts (gpt-4o / gpt-4o-mini)** are English and never receive
  user text → already English-internal. ✅ (no change needed)
- **User free-text `prompt`** flows into:
  - classification: `classify_room`, `surprise_me`, `classify_intent`,
    `classify_transformation`, `classify_edit_mode`;
  - prompt composition: injected **verbatim** into the English prompt
    (`build_local_edit_prompt`, `build_style_refinement_header`,
    `build_structural_transformation_header`, layout header).
- **All classification is English keyword/regex matching** (some EN+FR, no KM):
  - `edit_intent.py` — STRUCTURAL / LAYOUT / LOCAL / STYLE signal lists (EN only).
  - `intent_classifier.py` — EN + FR; **Khmer absent**.
  - `room_classifier.py` — EN substring signals only.
  - `atmosphere_recommender.py` — EN signal bonuses only.
  - `preservation.py` `_TEMPORAL_OVERRIDE_RE` — EN only
    (`evening|night|sunset|sunrise|morning|daylight|golden hour|cinematic|moody`).
- **Conversational replies** are **template-based (not LLM)**: EN full; FR partial
  (clarification/demand/meta); KM partial (clarification/demand only). The main
  `generate_architect_response()` has **no language parameter** → English only.
- **Language detection exists** (`_detect_language`: Khmer script ≥2 chars, French
  accents/markers, else EN) but only drives a few meta-intent templates.
- **No translation layer anywhere.**
- History parsing (`parse_history` → refinement_state) also does English keyword
  matching → breaks on FR/KM history. Atmosphere-transition uses `style_label`
  (canonical) → language-safe.

---

## 2. Risks of multilingual integration

| Risk | Where | Severity |
|---|---|---|
| **Mixed-language generation prompt** (FR/KM verbatim inside the English prompt) | edit_intent headers | 🔴 high — the contamination we must remove |
| **Silent edit-mode mis-classification** (FR/KM scores 0 → defaults to STYLE_REFINEMENT) → structural/layout intent lost → wrong preservation contract | `classify_edit_mode` | 🔴 high — degrades preservation & fidelity |
| **Room mis-inference** → defaults to `living_room` → wrong room DNA | `classify_room` | 🟠 (mitigated when `room_type_id` is provided, but free-text path still matters) |
| **Atmosphere "surprise"/signals ignored** for FR/KM | `atmosphere_recommender` | 🟡 medium |
| **Temporal override ignored** ("cinématique la nuit" not detected) → wrong time-of-day lock | `preservation.py` | 🟡 medium |
| **AI replies in English** inside an FR/KM UI | `architect_response` | 🟠 trust/UX |
| **Khmer semantic ambiguity** (no spaces, script complexity) → weak detection + weak STT | detection + voice | 🔴 KM-specific |
| **Voice STT language mismatch** (`localeId: null`) | `voice_service` | 🟠 |
| **Mixed-language history** poisons `parse_history` refinement state | `parse_history` | 🟠 |
| **Meta/support questions** in KM → fallback/GENERAL | `meta_intent` | 🟡 |
| **DNA never localized** (must stay English) — accidental leakage if someone "fixes" by translating DNA | DNA/preservation | 🔴 must be explicitly forbidden |

---

## 3. Recommended architecture — single English-normalization seam

**Core decision: do NOT translate the keyword lists into FR/KM.** Instead add one
normalization boundary at the top of the generation/chat pipeline that converts the
user's instruction to **canonical English** before any classification or prompt
composition. This fixes mis-classification (A) and prompt contamination (B) at once,
scales to typos/synonyms/voice, and keeps the validated English engine untouched.

### 3.1 Instruction normalization (the seam)
- New backend step `normalize_to_english(text, lang) -> EnglishInstruction`:
  - detect language (reuse `_detect_language`, or trust the client-sent locale);
  - **EN → passthrough byte-identical** (zero-cost, zero-regression for English);
  - **FR/KM → translate to concise, faithful English** via `gpt-4o-mini`
    (temperature 0, seeded, short max_tokens, design-domain system prompt that
    preserves proper nouns: atmosphere names, "Japandi", brand terms).
- Downstream (`classify_*`, `compose_generation_prompt`) receives **only English**.
- The **original text is preserved** for display/history; never used for the pipeline.

### 3.2 Reply language (output side)
- **Authoritative reply language = explicit UI locale sent by the client** (the user
  picked it) — not per-message heuristics. Thread `ui_locale` through `/generate`
  and `/chat`.
- Reply generation strategy (hybrid, lowest risk):
  - keep the existing **deterministic templates** where they exist (fast, free);
  - **thread `target_language` into `generate_architect_response()`** (the missing
    param) so dynamic replies can localize;
  - **fallback: translate the English reply to the target language** via gpt-4o-mini
    when no localized template exists (covers KM gaps without authoring hundreds of
    templates).

### 3.3 Detection vs explicit locale
- **Reply** uses explicit UI locale (deterministic, matches user expectation).
- **Instruction normalization** uses per-message detection (handles code-switching,
  e.g. an FR user typing an English phrase) → translate to EN.

### 3.4 Fallbacks
- Translation/LLM error → **fall back to the original text** (today's behaviour) and
  log; never block generation.
- Detection ambiguous → default to UI locale.
- KM unsupported in a sub-feature (voice) → graceful EN fallback or disable.

### 3.5 Language persistence
- Persist UI locale (SharedPreferences) — fixes the cold-start reset.
- Send it on every request; optionally store a per-session preferred language.

### 3.6 What stays English-internal (hard rule)
- DNA, preservation, structural identity, all generation prompts, all classifiers,
  vision/capture prompts. **Never** localized. The only multilingual surfaces are:
  (a) the displayed original user text, (b) the conversational reply.

---

## 4. Voice implications
- **Pass explicit `localeId`** matching UI locale (`en_US` / `fr_FR` / `km_KH`)
  instead of `null`.
- **Khmer STT is the weak link**: on-device recognizers have limited/absent Khmer
  support (varies by OS/version/device). Treat KM voice as **best-effort**:
  - validate per real device; if unsupported, **disable the mic for KM** or fall
    back to EN STT with a notice.
  - whatever text STT yields still passes through the normalization seam, but
    **garbage-in remains the bottleneck** — STT accuracy, not translation.
- **Partial vs final**: only the **final** transcript should enter the pipeline
  (partials are display-only) — confirm this in the input bar.
- Risk: long Khmer utterances + poor STT → corrupted instruction → wrong generation.
  Mitigation: show the transcript for confirmation before sending (KM especially).

---

## 5. Memory / conversational context
- **Pipeline must consume English-normalized history**, not raw mixed-language.
- Recommended: **dual-store per user message** — `content_original` (display) +
  `content_en` (pipeline). Normalize once at write time (reuse the seam), so
  `parse_history`/refinement-state sees English and stays correct.
- Do **not** feed raw FR/KM history into prompt building or keyword parsing.
- Atmosphere-transition logic already keys on canonical `style_label` → unaffected.

---

## 6. Rollout strategy
- **Feature flags** (backend): `MULTILINGUAL_NORMALIZE` (instruction seam),
  `MULTILINGUAL_REPLIES` (output localization), `MULTILINGUAL_KM` (Khmer gate,
  separate because of quality risk). EN path is a **no-op passthrough** → zero
  English regression by construction.
- **Phases** (each independently shippable, low→high risk):
  1. **Locale plumbing** — persist UI locale + send `ui_locale` to backend +
     thread `target_language` into reply generation. (No engine change.)
  2. **Instruction normalization seam** — FR/KM → English before classify/compose;
     EN passthrough. (The big correctness fix.)
  3. **History normalization** — dual-store `content_en`.
  4. **Voice** — explicit localeId + KM device validation + confirm-before-send.
  5. **Reply output-translation fallback** — fill KM/FR reply gaps.
- **Observability**: log `detected_lang`, `ui_locale`, `normalized_en` (truncated),
  resulting `edit_mode`, and EN-passthrough flag. Add a prompt-dump diff for EN to
  prove no change.
- **Metrics to monitor**: edit-mode distribution **by language** (catch
  mis-classification), generation retry rate by language, reply-language correctness,
  STT success rate by language, translation latency p50/p95, fallback rate.
- **Debugging**: a per-request trace `original → detected → normalized_en →
  edit_mode → prompt` makes any contamination visible.

---

## 7. Challenge of the idea (requested)
- **Is English-internal-only best? YES.** gpt-image-1 + the classifiers + the whole
  validated DNA/preservation stack are tuned and benchmarked in English. A single
  canonical internal language avoids maintaining N keyword maps and prevents
  mixed-language prompts. Keep it.
- **Better design than the obvious one.** The naive fix (translate every keyword
  list into FR/KM) is brittle (typos, synonyms, voice transcripts, Khmer
  morphology), never converges, and multiplies maintenance. The **single
  normalization seam** is strictly cleaner: one place, one model call, fixes both
  classification and prompt contamination, and leaves the English engine frozen.
- **Hidden risks we must name:**
  - **Khmer is the weakest link** end-to-end (detection heuristic, STT, translation
    quality) — gate it separately and validate on device.
  - **Latency on the hot path**: the seam adds a serial LLM call for non-EN. Mitigate
    with a cheap model + EN passthrough + caching of identical instructions.
  - **Freeze protection**: EN passthrough MUST be byte-identical — otherwise we risk
    regressing the validated English engine (this is the #1 machine test).
  - **Nuance loss** in translation (idiom, emphasis) — faithful low-temp prompt +
    keep original for the reply context.
- **Should anything stay multilingual internally? NO** for generation/classification.
  **YES** only at the edges: the stored original text (display) and the reply.

---

## 8. Deliverables summary

### Recommended flow (final)
```
client: UI locale (persisted) ──► request {prompt_original, ui_locale}
backend:
  lang = detect(prompt_original) or ui_locale
  prompt_en = EN? passthrough : translate_to_english(prompt_original)   ← SEAM
  classify_* (edit mode / room / atmosphere / temporal) USE prompt_en
  compose_generation_prompt USE prompt_en        ← English-only, DNA untouched
  reply_en = generate_architect_response(..., target_language=ui_locale)
  reply = localized template OR translate(reply_en, ui_locale)
client: show reply (localized) + store {content_original, content_en}
```

### Implementation phases → see §6 (1→5, flag-gated, EN no-op).

### Regression risks
- English users: **must be a strict no-op** (passthrough + unchanged templates).
- FR users: classification now correct (was silently STYLE_REFINEMENT).
- KM users: correctness depends on translation/STT quality — gated.
- Latency: +1 LLM call for non-EN only.
- History: changing to `content_en` must not break existing sessions (backfill / lazy).

### Machine-testable
- EN passthrough byte-identical (prompt-dump diff = 0). **Critical freeze guard.**
- Unit tests: FR/KM sample instructions → expected English → expected `edit_mode`
  (structural/layout/local/style) and temporal-override detection.
- Reply localization: target_language threads to the right template/translation.
- `flutter analyze` + backend import/smoke.

### Needs real-device validation (especially KM + voice)
- Khmer STT accuracy across iOS/Android devices.
- Khmer + French translation faithfulness on real user phrasings.
- End-to-end generation quality FR/KM vs EN (no atmosphere/preservation degradation).
- Voice UX: localeId, partial/final, confirm-before-send, KM fallback.
- Reply readability/tone in FR/KM.

---

## Hard rules (non-negotiable)
1. DNA prompts never in KM/FR. Preservation never in FR. No mixed-language generation
   prompt. Engine stays English canonical.
2. English path is a no-op (protect the frozen, validated engine).
3. Original user text preserved for display; English-normalized text drives the pipeline.
4. Khmer gated separately; validate on device before enabling.
