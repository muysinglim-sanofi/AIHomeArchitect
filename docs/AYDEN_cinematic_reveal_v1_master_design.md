# AYDEN Studio — Cinematic Reveal V1 — Master Design Document

> Status: **Foundation v1** · Date: 2026-06-06 · Owner: product/architecture
> Scope: product + UX + system architecture + cinematic/QA/monetization philosophy + MVP definition.
> **Not an implementation doc.** No code is specified here beyond architecture shape.
> Companion: the prior strategic audit (same date). This document is the canonical reference.

---

## 0. One-line thesis

> **AYDEN's video is not "an AI video feature". It is the moment a preserved, believable home *breathes*. The differentiator is restraint enforced by the same preserve-first rigor as the image. The day a clip looks like generic AI motion, the premium positioning dies — therefore the quality gate outranks the "wow".**

---

## 1. PRODUCT VISION

**Why it exists.** The still After-image proves *transformation*. The video proves *life* — it converts a design artifact into an emotional, shareable, aspirational moment ("I want to live there"). It is the natural apex of the reveal: still → "bring it to life" → the room breathes.

**Emotional purpose.** Move the user from *evaluation* ("is this nice?") to *projection* ("this is my home, alive"). Motion triggers presence in a way a still cannot.

**Premium differentiation.** Competitors animate and hallucinate — warping lines, sliding furniture, drifting perspective. AYDEN's edge is the **only** product that animates *your real architecture without betraying it*. The feature inherits the brand's core promise (preserve-first) and extends it into time.

**Why restraint is stronger than flashy AI motion (core argument).**
- Motion *amplifies every artifact*. A 2% imperfection in a still becomes a nauseating ripple in motion. So spectacle and realism are inversely correlated in current AI video.
- Luxury communicates through *calm and control*, not energy. Aman/Six Senses films are nearly still. Flash reads as "cheap tech demo"; stillness reads as "expensive and intentional".
- A subtle, believable clip is *infinitely loopable and shareable* without fatigue; a flashy one is a one-time gimmick.
- **Restraint is also the safest engineering path** — less motion = less drift. So the premium choice and the robust choice are the *same* choice. This alignment is the strategic unlock.

**Long-term strategic value.** Video is step 2 of the "AI Home Experience Platform": image → motion → immersive multi-room → architect-narrated tour. It deepens the "AI architect relationship" and raises willingness-to-pay (selling a *film of your future home*, not "a generation").

**Competitive positioning.** "The cinematic real-estate film of a home that doesn't exist yet — faithful enough to build from."

---

## 2. CORE VIDEO PHILOSOPHY

**What AYDEN video SHOULD feel like:** calm, premium, restrained, emotional, architectural, believable. A boutique-hotel/editorial-architecture film. *"This home is alive."*

**What it MUST NEVER become:** Marvel transitions, AI fantasy, over-animated interiors, fake construction, TikTok chaos, moving furniture/walls, unrealistic camera. *"This is an AI effect."*

### Golden rules
1. **Image-to-Video only** (animate the After image). Never text-to-video.
2. **The room is still; only light, air, and soft matter move.**
3. **In doubt → less motion.** Sobriety is both the premium and the safe choice.
4. **Short and loopable** (≤5s, seamless loop).
5. **Quality gate outranks wow** — never ship a doubtful clip; fall back to the image.
6. **The image is the hero; the video is a deepening, not a replacement.**

### Forbidden patterns
- Re-describing the scene in the prompt (invites regeneration → drift).
- Camera spins, fast pushes, handheld, dolly-zoom.
- Any structural element moving/morphing.
- "Cinematic" color grades that betray the source palette.
- People/animals/objects appearing.

### Acceptable motion (whitelist mindset)
Light, shadows, reflections, water ripples, sheer curtains/textiles, foliage/plants, candle flame, steam, dust-in-sunbeam, *very* slow camera push (≤3-4%).

### Non-negotiable preserve principles
Walls, windows, doors, openings, furniture geometry, proportions, layout, perspective, room identity, and **the source color/white-balance** remain exactly fixed across every frame.

---

## 2bis. BEFORE→AFTER ARCHITECTURE (clarification — the hero experience)

The desired V1 clip **starts on the Before and ends on the After**. Critical decision on *how*:

- **We already own BOTH stills** (before + after are stored). The AI must **not "guess" or generate** the transformation.
- **❌ Generative interpolation (send before+after as start/end frames to a video model):** the model invents the in-between → furniture materializes, walls slide, geometry morphs = the exact "fake construction / fantasy morph / cheap AI" the brand forbids. **Not in V1** (high cost + high drift).
- **✅ Deterministic transition (post-production over the two real stills):** compose the before→after as a **cinematic transition** — a soft light-sweep / cross-dissolve / animated reveal-slider — plus an identical gentle ≤3% push (crop of real pixels, zero AI, zero drift). Then a **final beat where the After "breathes"** via subtle I2V ambient motion (After image only).

**Pipeline:** `[Before still] --deterministic transition--> [After still] --I2V ambient tail (After only)--> loop/hold`.

**Who sends what:** the transition is **post-prod compositing of our own images (no AI, no drift)**; the only AI-video call is the optional ambient "life" tail on the **After (1 image)**. **We never send two photos to a video model for interpolation.**

**Why:** Before is pixel-perfect (real photo), After is pixel-perfect (validated render), the transformation is legible and faithful, and cost/latency are far lower than full generative video. This reconciles the before→after vision with the preserve-first doctrine.

---

## 3. MOTION PHILOSOPHY (critical)

### Allowed vs forbidden movers

| MAY move (low amplitude) | MUST stay fixed |
|---|---|
| Sunlight / shadow drift (one soft shift, not a day-night cycle) | Walls, ceiling, floor |
| Sheer curtains / light textiles | Windows, doors, openings, mullions |
| Foliage / potted plants (gentle sway) | All furniture geometry & position |
| Pool/water ripples & reflections | Proportions, perspective, camera framing of structure |
| Candle flame, steam, faint dust | Layout / spatial arrangement |
| Subtle reflective highlights | Materials' shape/edges (texture may shimmer *minimally*, never morph) |

### Motion amplitude philosophy
Treat motion strength like seasoning: the **minimum perceptible** amount. Most drift comes from over-driving amplitude. Target: a viewer should feel life *before* they can point to what moved. If they can immediately identify "the camera is moving" or "that's animated", it's already too much.

### Temporal realism philosophy
- One coherent micro-event over 5s (a breeze passes; light softens) — not multiple competing motions.
- Constant, gentle pacing; no acceleration, no "reveal beat".
- **Loop integrity:** the last frame should rhyme with the first so the loop is invisible.

### Motion hierarchy (where the eye is allowed to rest)
1. Primary (one element): the dominant ambient mover — usually curtains *or* water *or* foliage, chosen by room.
2. Secondary (subtle): light/shadow shift.
3. Tertiary (barely there): reflections, dust.
Never give two "primary" movers equal weight — it reads busy/artificial.

### Why less motion feels more premium
Human perception equates *control* with *quality*. A still room with one breathing element signals a controlled, intentional, expensive production. Abundant motion signals an uncontrolled generative process — i.e., cheap. Less motion = more perceived authorship.

---

## 4. CAMERA PHILOSOPHY (critical)

**Default: locked camera (tripod).** The safest and most architectural. A perfectly still frame with ambient life is *more* premium than any move.

**Maximum allowed:** a **single, linear, ≤3-4% push-in** OR a *micro* lateral drift — slow, constant, no easing drama. One direction only. No return-move, no orbit.

**Forbidden camera behaviors:** parallax-heavy moves (force the model to invent occluded geometry → drift), handheld/shake, zoom punches, spins, crane/drone moves, rack focus as a "reveal".

**Why a fixed/near-fixed camera is architectural and premium.** Architecture photography is shot on tripods with shift lenses precisely to keep verticals true. A still camera respects the building; a moving camera competes with it and, in AI, *destroys* it (every pixel of new parallax is hallucinated). The luxury reference is the *held* architectural shot, not the sweeping drone reel.

**Rule:** camera motion is a *liability budget*, not a feature. Spend as little as possible.

---

## 5. ROOM ELIGIBILITY STRATEGY

Scoring: Wow potential, Geometry-drift risk, Emotional impact, Natural-motion availability. (H/M/L)

| Room | Natural motion source | Wow | Geometry risk | Emotional | **V1 verdict** |
|---|---|---|---|---|---|
| **Pool area** | water ripples, reflections, foliage | H | **L** (motion is water, not structure) | H | ✅ **V1 — flagship** |
| **Terrace** | curtains, foliage, light | H | L–M | H | ✅ **V1** |
| **Garden** | foliage, light, grasses | M–H | L | M–H | ✅ **V1** |
| **Balcony** | curtains, plants, light | M | L–M | M | ✅ **V1** |
| **Living room** | sheer curtains, light shift | H | M (furniture-dense) | H | ✅ **V1 (light + curtains only, locked cam)** — it's the MVP hero room |
| **Bedroom** | curtains, light | M | M | M–H | 🟡 V1-risky → light-only, validate |
| **Entrance hall** | light, maybe a plant | L | M (openings/passages) | L | 🟡 risky → V2 |
| **Facade** | foliage, sky, light | M | **H** (whole building can drift) | M | 🔴 **V2+ only**, light/foliage only, high fidelity |
| **Driveway** | foliage, light | L | **H** (architecture/approach) | L | 🔴 **forbidden V1** |
| **Kitchen** | light only (hard surfaces) | L | **H** (cabinetry lines, fixtures) | L–M | 🔴 **forbidden V1** |
| **Bathroom** | light, maybe steam | L | **H** (tight, reflective, fixtures) | L | 🔴 **forbidden V1** |

**Principle:** prioritize rooms where *motion is naturally expected and lives away from hard structural lines* (water, foliage, fabric). Forbid rooms that are hard-edged, fixture-dense, and reflective (kitchen/bathroom) and architecture-defining (facade/driveway) for V1.

**V1 allowed:** pool, terrace, garden, balcony, living room. **V1 risky (gated/validate):** bedroom. **V1 forbidden:** kitchen, bathroom, facade, driveway, entrance hall.

---

## 6. ATMOSPHERE COMPATIBILITY

| Atmosphere | Motion compatibility | Best movement | Danger zone | Cinematic potential |
|---|---|---|---|---|
| **Tropical Escape** | ★★★★★ | foliage, water, breeze in linen | over-lush "jungle" motion | Highest — motion is the genre |
| **Warm Modern** | ★★★★ | soft daylight shift, sheer curtains | warm cast over-warming in motion (watch de-orange) | High |
| **Nordic Warmth** | ★★★★ | candle flame, soft light, light wool drift | "too evening"/flicker | High (hygge) |
| **Soft Luxury** | ★★★☆ | slow light on marble, gentle sheers | reflective surfaces shimmer/morph | High but reflective-risk |
| **Japandi Calm** | ★★★☆ | one branch, soft diffuse light, faint shadow | any motion can break the stillness ethos | Medium — restraint is the brand; keep *barely* moving |

**Naturally best for video:** Tropical (motion = its identity) and Nordic (candle/light = hygge). Japandi must move the *least* — its premium is silence; a single drifting branch + light is enough. Soft Luxury: beware marble/mirror reflections morphing — keep camera locked.

---

## 7. UX MASTER FLOW

Design principle: **the still moment must exist before motion is offered.** Never auto-animate.

| Stage | What happens | User emotion | Timing/perf philosophy |
|---|---|---|---|
| 1. After-image reveal | The redesign appears (existing reveal/slider) | Surprise, evaluation | Let it breathe; no competing CTA |
| 2. CTA appears | Secondary, elegant button **"Bring your vision to life"** below the hero image | Curiosity | Appears after a beat (e.g., ~1.5s) — not instant noise |
| 3. Tap → processing | Still After-image stays on screen with a **subtle "coming alive" shimmer/grain** + calm copy ("composing your film…") | Anticipation, not waiting | **Perceived perf:** never a raw spinner. Turn 30-120s latency into anticipation over the image itself |
| 4. Ready → transition | Video **cross-fades in** over the still and **loops** | Delight, presence | Soft fade, no pop |
| 5. Playback | Autoplay, muted, seamless loop. Discreet controls: Share · Save · "Back to image" | Immersion | Loop = no perceptible cut |
| 6. Share/Export | 9:16 + native ratio, watermark (premium removes) | Pride | One-tap to system share |
| 7. Retry/Fallback | If QA fails → **never show a bad clip**; keep the image + "your film is being refined" + silent retry, or graceful "image only this time" | Trust preserved | Failure must feel like care, not error |

**Frustration management:** latency is the enemy. Mitigations: anticipation UI over the image, optional "notify me when ready" if >X s (ties to the existing job-queue gap), and **honesty** ("a film takes a moment — it's worth it").

**Emotional pacing of the whole arc:** stillness (respect) → invitation (calm) → anticipation (build) → life (release) → loop (lingering). No spikes.

---

## 8. PROVIDER ARCHITECTURE STRATEGY (no provider chosen here)

Goal: **provider-agnostic, async, hot-swappable.** The model is a commodity that will change; the pipeline must not.

### Shape (text diagram)
```
[App] --POST /reveal/video--> [API]
   |                            |-- enqueue job (job_id) --> [Video Job Queue]
   |<-- 202 {job_id} -----------|
[App] --poll GET /reveal/video/{job_id}--> [API] (status: queued|running|qa|ready|failed)
                                  [Worker] pulls job:
                                     1. resolve VideoProvider (adapter)  <-- registry/flag
                                     2. build motion prompt (room+atmo aware)
                                     3. call provider I2V (after_image + prompt + params)
                                     4. await provider (poll/webhook)
                                     5. QA gate (auto) -> PASS/WARN/FAIL
                                     6. store result (CDN) OR fallback-to-image
                                     7. mark ready/failed
```

### Components
- **`VideoProvider` abstraction** (one interface): `submit(after_image, motion_spec) -> provider_job`, `poll(provider_job) -> status/asset`, capabilities flags (max_duration, supports_motion_mask, supports_webhook, cost_tier, aspect_ratios).
- **Adapters** per provider (Runway/Luma/Kling/Veo/…), each translating our neutral `motion_spec` to provider params. Mirrors the existing `quality_overrides`/per-cell pattern — same engineering DNA.
- **Async pipeline + queue:** generation is 30-120s → must be a background job, not a request-blocking call (don't repeat the 10-min /generate hang). Decoupled worker.
- **Polling + webhook:** support both; webhook preferred when the provider offers it, poll as fallback. App polls *our* API, never the provider.
- **Storage/CDN:** store the source After-image reference + the rendered clip; serve via signed URLs (reuse existing Supabase storage pattern). Keep the After-image as canonical fallback.
- **Caching/idempotency:** key by (after_image_hash, motion_spec, provider, version). Same input → return cached clip (video is expensive; never regenerate identical requests). Idempotency keys on submit.
- **Failover & hot-swap:** provider chosen via config/flag; on provider error or QA-FAIL, optionally retry on a secondary provider, else fallback-to-image. Switching providers = config change, no app change.
- **Observability:** per-job log of provider, params, latency, cost, QA verdict (mirror the `[VersionState]`/`[PERF SUMMARY]` discipline already in the codebase).

**Non-negotiable:** the App never talks to a provider directly and never blocks on generation.

### Isolation guarantee (foundational)
The video feature is a **strict super-layer on top of the existing image system. It does not read-modify or alter any existing behavior.**
- **Untouched:** the 5 atmosphere DNA files (all room attributes — decor/furniture/lighting/material/realism/room_specific), the image core (`composer.py`, `build_dna_block`, `input_fidelity`/`quality` logic, BIMODAL, `/generate`, structural-preservation).
- **Input = the finished After-image artifact** (a stored JPEG), NOT the generation pipeline → natural decoupling.
- **All integration is additive & isolated:** (1) a new `backend/video/` module + new routes (`/reveal/video…`) registered in main.py without modifying `/generate`; (2) a **separate** motion-preset table keyed *read-only* by `room_type`/`atmosphere_id` (never edited into the DNA files); (3) storage reuse (read After-image URL, write clip alongside).
- **"Super-layer" ≠ "no new code"** — it means zero modification of existing behavior; only additive, isolated code.
- **Proof obligation:** every video change ships with the standard non-regression snapshot (65 DNA blocks byte-identical) and an unchanged `/generate` path.

---

## 9. VIDEO PROMPTING PHILOSOPHY (critical)

**The prompt describes MOTION + ATMOSPHERE, never the SCENE.** The After-image already defines the scene; re-describing it tells the model to *re-imagine* it → geometry drift. This is the exact failure class we fought in stills (scene reinvention), and it is worse in video.

### Layering strategy (composed, not free-text)
```
[GLOBAL MOTION LAW]  (constant, every clip)
  + [CAMERA SPEC]    (locked | ≤3% push)
  + [ROOM MOTION PRESET]   (what may move, by room)
  + [ATMOSPHERE TINT]      (emotional pacing, by atmosphere)
  + [NEGATIVE / PRESERVE]  (constant anti-drift block)
```
- **Global motion law (constant):** "Subtle ambient motion only. Photoreal, calm, premium, architectural. Architecture, walls, windows, doors, furniture, proportions and perspective remain perfectly fixed and undistorted; colours stay true to the source."
- **Room preset (whitelist):** e.g. pool → "gentle water ripples and reflections; foliage swaying softly"; living → "sheer curtains drifting gently; soft daylight slowly shifting".
- **Atmosphere tint:** e.g. Japandi → "barely-there motion, deep stillness"; Tropical → "warm relaxed resort air".
- **Negative/preserve (constant):** "no warping, morphing, bending lines, moving furniture, layout change, camera shake, fast motion, people or objects appearing, colour-cast shift."

### Room-aware & atmosphere-aware
The preset library is keyed by `room_type` (eligibility + whitelist) and modulated by `atmosphere_id` (amplitude/pacing). Reuses the room×atmosphere structure already in the DNA.

### Motion-token philosophy
Prefer *physical, low-energy* verbs (drift, sway, ripple, soften, shift) over *cinematic* verbs (sweep, push, reveal, dramatic). Energy words = amplitude = drift.

### Forbidden prompt patterns
Scene re-description; furniture/material lists; "cinematic camera"; "dynamic/epic/dramatic"; time-of-day changes (unless user-requested); anything that could spawn a new object.

---

## 10. QA GATE SYSTEM (critical)

**Doctrine: a doubtful clip is a brand wound. Default action on uncertainty = withhold the video, keep the image.**

### What makes a video FAIL
Geometry drift (lines bend), wall/ceiling "breathing", melting/sliding furniture, window/door/mullion distortion, temporal flicker/strobe, inconsistent lighting jumps, fake/over motion, camera instability, texture morphing, object/person hallucination, colour-cast shift vs source.

### PASS / WARN / FAIL logic
- **PASS** → deliver. No visible structural change vs the After-image; motion confined to whitelist; loop clean.
- **WARN** → deliver only with the *best-of-N* selection, or downgrade motion and retry once; never if any structural element is implicated.
- **FAIL** → discard; retry (lower amplitude / different seed / secondary provider) up to N; else **fallback-to-image**.

### Automatic rejection criteria (V1 = cheap heuristics; later = learned)
- **Structural-edge stability (V1, feasible):** detect strong straight edges (door/window/wall lines) in frame 0; measure their displacement/curvature in frames mid/last. Movement beyond a small threshold → FAIL. (Classic CV: edge/Hough/optical-flow on masked structural regions.)
- **Static-region flow check:** optical-flow magnitude in "should-be-static" regions (walls/floor) above threshold → FAIL.
- **Global colour drift:** mean colour-temperature delta frame0→frameN beyond threshold → WARN/FAIL.
- **Temporal flicker:** frame-to-frame luminance variance spikes → WARN.
- **Best-of-N:** generate 2-3 takes, auto-rank by lowest structural-flow, pick the calmest.

### Future automated QA
- Learned classifier ("AYDEN-real vs AI-cheap") trained on labeled pass/fail clips.
- VLM judge ("does any wall/furniture move or warp? yes/no") as a second opinion (mirrors the adversarial-verify pattern used elsewhere).

### Human QA philosophy (pre-scale)
Before broad rollout, a human reviews a sample daily; maintain a "wall of shame" of failure exemplars to tune thresholds. The bar: *would a luxury brand publish this?* If hesitation → FAIL.

### Fallback-to-image logic
Always retain the After-image as canonical. On FAIL after retries: show image + reassuring copy; optionally queue a silent off-peak retry; never surface a hard error or a bad clip.

---

## 11. MONETIZATION STRATEGY

**Reality:** video costs ~10-50× an image and is slow. It cannot be free-unlimited.

| Question | Recommendation | Rationale |
|---|---|---|
| Premium-only? | **Yes, primarily.** | Cost + premium signaling. Video = the "wow" of paid. |
| Free access? | **One single watermarked teaser** (e.g. 1 lifetime, living-room only) | Acquisition: let free users *feel* it once → conversion hook + shareable. |
| Credits vs unlimited? | **Metered within plan** (video credits separate from image), not unlimited | Protects unit economics; "credits" framed as "films", not raw counts. |
| Duration by plan? | V1 fixed 5s for all; reserve longer/loops-HD for higher tiers later | Keep V1 simple. |
| Export by plan? | Free = watermarked; Premium = clean + higher res | Standard premium lever. |

**Framing (consistent with strategy):** sell *"cinematic films of your home project"*, not "X video generations". Weekly plan includes a sensible film allotment per project. **Cost guardrails:** caching/idempotency (never regenerate identical), best-of-N capped, per-user daily ceiling, fail-fast timeouts (reuse the 180s lesson). Watch margin per film closely; video is the line item that can sink unit economics if uncapped.

---

## 12. MVP SCOPE RECOMMENDATION

**Smallest premium-feeling V1:**
- **Duration:** 5s, seamless loop.
- **Input:** the existing After-image only (I2V).
- **Rooms:** pool, terrace, garden, balcony, **living room** (light+curtains). *(Bedroom behind a flag for validation.)*
- **Atmospheres:** all 5 supported, but **amplitude modulated** (Japandi lowest, Tropical highest).
- **Motion:** ONE ambient preset per room (no user motion control), camera **locked** (no push-in in V1 — add later once stable).
- **Generation limits:** premium-metered; 1 watermarked free teaser; best-of-N=2-3 server-side, user sees the chosen one.
- **Export:** 9:16 + native; watermark; premium clean.
- **Quality:** QA gate live from day 1; fallback-to-image guaranteed.

**Why limiting scope increases quality:** every removed variable (camera moves, multiple presets, risky rooms, user controls) is a removed failure mode. A tiny, flawless V1 protects the brand and ships fast; breadth is cheap to add later, reputation is not.

**MVP traps to avoid:** (a) shipping kitchen/bathroom/facade video to "be complete" — they're the drift minefield; (b) adding a camera move because it "looks more cinematic" — it's the #1 drift source; (c) before→after *generative* morph — do a post-prod cross-fade instead; (d) blocking the request on generation — must be async.

---

## 13. RISK ANALYSIS

| Risk | Sev | Prob | Mitigation |
|---|---|---|---|
| Geometry drift / warping | **High** | High (if uncontrolled) | I2V, low amplitude, locked cam, QA gate, eligible rooms only |
| "Cheap AI" look → brand damage | **High** | Med | Restraint philosophy, QA gate, best-of-N, human review pre-scale |
| Cost blowout (margins) | High | Med | Premium-gating, caching/idempotency, caps, best-of-N limit |
| Latency / user frustration | Med | High | Async pipeline, anticipation UI, notify-when-ready, fail-fast |
| Provider dependency / API change | Med | Med | Provider abstraction, hot-swap, secondary failover |
| Reflective-surface morph (SL/marble, bathroom) | Med | Med | Exclude bathroom; SL locked cam + light-only; QA |
| Colour-cast shift (re-warming WM) | Med | Med | Preserve-colour negative; QA colour-delta check |
| User expectation inflation (wants Hollywood) | Med | Med | Position as "subtle architectural film"; copy sets expectation |
| Over-animation creep over time | Med | Med | Philosophy doc as guardrail; amplitude as a hard config ceiling |
| Loop seam / jarring playback | Low | Med | Loop-aware generation + fade |

**Top-3 to obsess over:** geometry drift, cheap-look (brand), cost. All three are mitigated by the *same* lever set: restraint + I2V + QA gate + eligibility.

---

## 14. IMPLEMENTATION ROADMAP

| Phase | Goal | Validation / Go-No-Go | Blockers |
|---|---|---|---|
| **0. Philosophy/doc** (this) | Shared foundation | Doc approved | — |
| **1. Provider benchmark** | Find the model that stays stable at low motion on *our real After-images* (pool/terrace/living ×5 atmos) | ≥ X% PASS on structural stability across a fixed test set; pick 1 primary (+1 backup) | Access/keys; test-set curation |
| **2. Isolated prototype** | Manual I2V + prompt layering on test images, no app | Human "luxury-publishable?" yes on the eligible set | Prompt tuning |
| **3. Backend abstraction** | `VideoProvider` interface + 1 adapter + async job queue + storage + idempotency | Job lifecycle works; no request blocking; cached repeats | Queue infra |
| **4. Internal QA gate** | Auto structural/flow/colour checks + best-of-N + fallback | FAIL rate caught ≥ target; zero bad clips pass in sample | CV thresholds tuning |
| **5. Limited rollout** | Behind flag, internal + few users, living+pool only | No brand-damaging clips; cost/film within target; latency acceptable | — |
| **6. Premium rollout** | Paywall integration, free teaser, all V1 rooms | Conversion lift; margin OK; share metrics | Pricing finalized |

**Hard go/no-go gate before any public exposure:** Phase 4 must guarantee *no structurally-broken clip ever reaches a user* (gate + fallback). If that can't be guaranteed, do not launch — ship image-only.

---

## 15. FINAL STRATEGIC CONCLUSION

**Can this become a true AYDEN signature differentiator? — Yes, conditionally.**

It becomes a signature **iff**:
1. It is **I2V + restrained + locked-camera** (premium = robust = same path).
2. A **QA gate + image fallback** guarantees a bad clip *never* ships.
3. It launches **narrow** (eligible rooms only) and grows on validation, not ambition.
4. Economics are **capped** (premium-gated, cached, best-of-N limited).

It **fails** (and damages the brand more than no feature) if: camera moves are added for spectacle, risky rooms ship early, the prompt re-describes scenes, or a single cheap/warping clip becomes the shareable that defines AYDEN.

**Biggest success factors:** restraint as doctrine; the QA gate; provider-agnostic async architecture; room/atmosphere-aware motion presets.
**Biggest dangers:** drift, cheap-look, cost — all the same mitigation family.
**Long-term opportunity:** the bridge from "AI image app" to "AI Home Experience Platform" (image → film → immersive tour → architect-narrated lifestyle).

---

# FINAL EXECUTIVE SUMMARY

**Top strategic decisions**
1. **Image-to-Video only**, animating the existing After-image — the single decision that makes preservation possible.
2. **Restraint is the product**: locked camera, one low-amplitude ambient mover, ≤5s loop. Premium = robust = identical path.
3. **QA gate + image fallback is mandatory and outranks "wow"** — no broken clip ever ships.
4. **Provider-agnostic, async, hot-swappable** architecture; the model is a commodity, the pipeline is the asset.
5. **Launch narrow**: pool/terrace/garden/balcony/living only; kitchen/bathroom/facade/driveway forbidden in V1.
6. **Premium-gated economics** with caching/caps; sell "films of your project", not generations.

**Top risks**
1. Geometry drift / warping (High/High).
2. "Cheap AI" look → brand damage (High/Med).
3. Cost blowout (High/Med).
*(All three share one mitigation family: restraint + I2V + QA gate + eligibility.)*

**Recommended next action**
→ **Phase 1: provider benchmark on our real After-images** (pool/terrace/living × 5 atmospheres), scored on *structural stability at low motion*. Pick 1 primary + 1 backup. Nothing else gets built until a model proves it can keep AYDEN's architecture still.
