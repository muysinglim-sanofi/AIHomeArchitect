# AYDEN Studio — Part A: Deterministic Reveal System — Master Specification

> Status: **Spec, no code** · Date: 2026-06-06 · Mobile-first, App-Store-first, luxury-brand-first.
> Part A = **deterministic before→after reveal** built from the **real Before + real After** stills. **No AI, no provider, no geometry risk.**
> Companion: `AYDEN_cinematic_reveal_v1_master_design.md` (Part B = the optional I2V "breathe" tail, not in scope here).
> Builds on the app's existing **reveal slider** — Part A animates it into a cinematic reveal while keeping manual scrub.

---

## 0. Thesis
> **The before→after *is* the product's emotional core. Part A makes that transformation feel like a luxury architectural film — pixel-perfect, instant, free, un-fakeable. It must exist and shine even if Part B never ships. Restraint + readability = premium; spectacle = cheap.**

---

## 1. PART A PRODUCT PURPOSE
- **Why it exists:** the still After proves the result; the *reveal* gives it **emotional payoff and narrative** (this was your room → this is your future home). It is the moment of *transformation*, staged.
- **Roles:** emotional storytelling layer · the **social-sharing engine** (the safe, viral asset) · the **App Store showcase** · the onboarding "aha" · the premium-positioning signal.
- **Why deterministic > AI-generated transition:**
  1. **Pixel-perfect & truthful** — Before is the real photo, After is the validated render; no morph, no hallucination, no warp.
  2. **Instant & free** — local compositing, no provider latency/cost.
  3. **Readable** — a clean reveal *shows the user their actual room transformed*; a generative morph *obscures* that (furniture materializing = confusion, not credibility).
  4. **Zero brand risk** — it can never look "cheap AI". It's the one video asset guaranteed premium.
  5. **Always-on** — exists regardless of Part B's benchmark outcome.

---

## 2. EMOTIONAL EXPERIENCE PHILOSOPHY
The arc is a 3-beat emotional story:
- **BEFORE (recognition):** "this is the real, empty, ordinary space." Hold long enough to *register reality* — this grounds the transformation in truth. Emotion: neutral, honest, a touch of "before".
- **TRANSITION (anticipation→release):** the reveal travels in. Emotion: a held breath releasing. Calm, not a jump-scare. The user *feels* the change arrive rather than being hit by it.
- **AFTER (projection):** "this is my home." Hold/settle so the eye can wander and *inhabit* the space. Emotion: aspiration, ownership, "I want to live there."
- **Pacing psychology:** the BEFORE must earn its hold (without it, there's no contrast and no story). The AFTER must be the longest beat (that's where projection happens). The transition is the *bridge*, not the *show*.

---

## 3. REVEAL PHILOSOPHY (critical)

| Style | Premium feel | Readability | TikTok-cheap risk | Mobile UX | Verdict |
|---|---|---|---|---|---|
| **Luxury soft-edged sweep** (a feathered vertical/diagonal line travels, After replacing Before) | ★★★★★ editorial | ★★★★★ (you see both, then full After) | Low (if soft + slow) | ★★★★★ (= the existing slider, animated) | **PRIMARY** |
| **Luxury cross-dissolve** | ★★★★★ calm | ★★★★ (no spatial "wipe" cue) | Low | ★★★★★ | **SECONDARY** (calm atmospheres / fallback) |
| Cinematic light-sweep (a warm light band passes, revealing After) | ★★★★ | ★★★★ | Med (can look "effect-y") | ★★★★ | V2 option (atmosphere-tinted) |
| Masked/shape reveal (circle, etc.) | ★★ | ★★ | **High** | ★★ | ❌ avoid |
| Parallax/2.5D reveal | ★★★ | ★★ | Med | ★★★ | ❌ avoid (needs depth → fake/drift) |
| Layered reveal (elements pop in) | ★ | ★ | **High** (= furniture materialization look) | ★ | ❌ avoid |
| Hard wipe / fast swipe | ★★ | ★★★ | **High** | ★★★ | ❌ avoid |

**Recommended:** **PRIMARY = luxury soft-edged sweep** (feathered edge, slow, single direction) + a synchronized gentle push (≤3%) applied **identically to both layers** (so it's a crop of real pixels → geometry preserved). **SECONDARY = cross-dissolve** for the calmest atmospheres (e.g. Japandi). Both keep before/after perfectly **readable** and **editorial**. The sweep doubles as the existing **manual slider** — auto-play first, then the user can scrub.

**Why the sweep:** it mirrors the physical "drawing back a curtain" of an architectural reveal, it's spatially legible (you watch the new room arrive across the frame), and it's literally the slider the user already understands.

---

## 4. MOTION PHILOSOPHY (all deterministic)
- **Camera/zoom:** a single **≤3–4% push-in** (or none), applied **identically to Before and After layers** — it's a crop of real pixels, **never** generated, so zero geometry risk. No parallax (parallax fakes depth → uncanny). One direction, no return.
- **Wipe motion:** constant or gently eased; **soft/feathered edge** (never a hard line); single axis (vertical or slight diagonal).
- **Easing:** **slow-in / slow-out (ease-in-out)**, no bounce/elastic/overshoot (bounce = toy-like = cheap).
- **Amplitude rule:** the viewer should feel *elegance*, not notice *effects*. If a motion calls attention to itself, halve it.
- **Why less = more premium:** restraint signals authored control (luxury); abundant motion signals a hype reel. The transformation is the star; the motion is the *usher*, not the act.

---

## 5. TIMING & PACING SYSTEM

| Beat | Ultra-premium calm | **AYDEN default** | Social-optimized |
|---|---|---|---|
| BEFORE hold | 1.8s | **1.2s** | 0.6s (hook fast) |
| Transition (sweep) | 2.5s | **1.8s** | 1.2s |
| AFTER settle/hold | 3.0s | **2.5s** | 2.2s |
| **Total** | ~7.3s | **~5.5s** | ~4.0s |
| Loop | optional, 1s fade gap | optional | hard loop for Reels |

**Recommended default ≈ 5.5s** — long enough to tell the story, short enough to share/replay. **App Store** preview ≈ 5s (clear before→after by second 3). **Social** export = the social-optimized profile (hook in <1s, payoff by ~2.5s). Provide the 3 profiles; ship the default + social-export.

**Golden timing rule:** never start the sweep before the BEFORE has registered (~1s min), and always let the AFTER be the **longest** beat.

---

## 6. MOBILE UX SPECIFICATION
- **Surface:** the reveal plays **in-place** in the chat/result card; **tap → fullscreen** immersive.
- **Autoplay:** **auto-play once** on first appearance of the result (the reward), then settle on the AFTER with the **manual slider** available.
- **Mute:** silent by default (V1 has no audio).
- **Loop:** fullscreen = gentle loop (with a soft fade gap); in-card = play once then hold AFTER.
- **Gesture:** **drag to scrub** the sweep (manual before/after — the existing slider), **tap to replay** the auto-reveal, swipe-down to exit fullscreen.
- **Haptics:** one **subtle** haptic tick at the *moment the reveal completes* (the "settle"). Nothing else — restraint.
- **Loading/buffering:** **none** — both images are local/cached, so the reveal is **instant**; never show a spinner for Part A.
- **Smoothness:** target **60fps**; the animation is 2 layers + a mask = trivially light.
- **Orientation:** portrait-first; respect the image's native aspect; fullscreen adapts.

---

## 7. CTA HIERARCHY (reward, not feature)
- The reveal **is the reward** for generating — it should feel *given*, not *operated*.
- **Flow:** generation completes → AFTER result card → **auto-reveal plays once** → settles on AFTER with a subtle **replay** affordance + the manual slider. 
- **Copy:** understated — a small **↺ "Replay"** and, if labeled, *"Your transformation"*. No loud "GENERATE VIDEO!" button for Part A.
- **Separation from Part B:** the **"Bring your vision to life"** (Part B I2V breathe) is a **distinct, secondary** CTA shown *after* the user has enjoyed the reveal — never conflated with Part A.
- **Replayable & shareable** from the result card (share icon → renders the export).

---

## 8. SOCIAL MEDIA & SHARING STRATEGY
**Part A is the social engine** (not Part B) — it's the safe, premium, un-fakeable viral asset.
- **Export:** render the deterministic reveal to **MP4** (and optional GIF), **9:16** primary + native ratio.
- **Pacing for social:** the *social-optimized* profile (hook <1s, payoff ~2.5s, hard loop) — distinct from the in-app default.
- **Watermark:** **subtle, premium** AYDEN mark (thin, semi-transparent, corner or integrated); premium plan = clean export.
- **Format variants:** Reels/TikTok (9:16 loop), Stories (9:16), feed (native/1:1), ad (9:16 with a touch more BEFORE-hold for context).
- **Brand rule:** it must read as **luxury architectural content** (editorial pacing, calm) — never AI-spam (no flashy text, no effect stacking, no captions-on-fire).

---

## 9. APP STORE STRATEGY
- **Preview video:** the deterministic reveal (before→after) — clean, instant, **zero AI-artifact risk** → the safest, most convincing showcase of *transformation*.
- **Screenshots:** a **mid-reveal frame** (both visible) + a clean AFTER + a before/after split.
- **Onboarding:** a single sample reveal on first launch communicates the whole value prop wordlessly.
- **Why Part A for the store:** it demonstrates the core promise (your space, transformed) with guaranteed premium quality — no dependency on a video model passing QA.

---

## 10. FRONTEND IMPLEMENTATION PHILOSOPHY (no code)
- **Reusable `RevealController`** component: inputs = (beforeUrl, afterUrl, profile) → plays a **deterministic timeline** (keyframes for wipe position + synchronized transform).
- **Two image layers** (Before under, After over) + an **animated soft-edged mask** (the sweep) + a **shared transform** (the ≤3% push, identical to both layers).
- **Manual mode** = the same component with the mask position bound to a drag gesture (the existing slider).
- **Export** = render the same timeline to video (client-side canvas/ffmpeg-wasm, or a small server-side ffmpeg render for quality/watermark) — **one timeline, two outputs** (interactive + exported).
- **Reusable across the app** (result card, fullscreen, share, onboarding, App Store asset generation) — single source of truth for the reveal.

---

## 11. PERFORMANCE & OPTIMIZATION
- **Lightweight:** 2 images + a mask + a transform = negligible GPU; 60fps even on low-end.
- **Preload both images** before the reveal triggers (the After is already fetched for the result; prefetch the Before).
- **Memory:** downscale to display resolution for the interactive view; full-res only for export.
- **Instant:** local/cached → no buffering, ever.
- **Export generation:** offload the watermarked MP4 render (server-side ffmpeg recommended for consistent quality across devices); keep interactive playback purely client-side.
- **Low-end fallback:** if the device struggles, **drop the push to 0%** and keep the wipe (still premium) — never drop frames.

---

## 12. FAILURE MODES & HARD RULES

| Failure | Why it's bad | Hard rule |
|---|---|---|
| Transition too fast (<1s) | no emotional register, unreadable | sweep ≥ 1.2s; BEFORE hold ≥ 1s |
| Over-zoom (>~4%) | feels like drift, crops content | push ≤ 4%, identical both layers |
| Hard-edged/shape wipe | TikTok-cheap | feathered soft edge only |
| Bounce/elastic easing | toy-like | ease-in-out only, no overshoot |
| Parallax/2.5D | fake depth, uncanny | no parallax in Part A |
| Effect stacking (flares, particles, grain pulses) | AI-spam look | one effect only (sweep + optional push) |
| Laggy/janky transition | breaks premium | 60fps target; degrade push before frames |
| Unreadable before/after | loses the "aha" | both states clearly visible; AFTER longest beat |
| Loud CTAs/captions | gimmick | restrained copy, reward framing |

---

## 13. MVP SCOPE RECOMMENDATION
- **Reveal type:** ONE — **luxury soft-edged sweep** + synchronized **≤3% push** (identical both layers).
- **Timing:** the **AYDEN default ~5.5s** (BEFORE 1.2s · sweep 1.8s · AFTER 2.5s).
- **Motion:** ease-in-out, single direction, feathered edge, no parallax.
- **UX:** auto-play once → settle on AFTER + **manual drag slider** + **replay**; tap→fullscreen; subtle settle haptic; silent.
- **Export:** **9:16 MP4** (+native), social-optimized pacing, **subtle watermark** (premium = clean).
- **Reusable `RevealController`** powering card / fullscreen / share / App-Store asset.
- **Why limit:** one flawless reveal = zero failure surface, instant ship, and a consistent brand signature. Variety is cheap to add later; a coherent first impression is not.

---

## 14. FUTURE EVOLUTION ROADMAP
- **V2:** atmosphere-aware pacing (Japandi → slower/dissolve; Tropical → slightly livelier sweep); a tasteful **light-sweep** variant; subtle **soundtrack** (optional, off by default); aspect-ratio presets.
- **V3:** multi-room **sequence** (a short edited "home tour" of several reveals); adaptive pacing by content; light emotional personalization.
- **Dangerous (avoid):** generative morph transitions, parallax/3D camera, flashy editing packs, auto-music that screams "AI app", per-user effect overload.

---

## 15. FINAL STRATEGIC CONCLUSION (brutal)
- **A. Can Part A alone be a signature?** **Yes.** A premium, readable before→after reveal is the experience that *built* this category — done with luxury restraint, it's a complete, shippable signature on its own. Part B is a bonus, not a prerequisite.
- **B. Why deterministic > generative transition?** Pixel-perfect, instant, free, zero-risk, and — most importantly — **readable**: it shows the user *their real room* becoming *their future home*. A generative morph trades that clarity for spectacle and invites artifacts. Truth beats trickery.
- **C. What makes it "luxury architectural" not "AI gimmick"?** Restraint (one soft sweep, ≤3% push), **editorial pacing** (earn the BEFORE, dwell on the AFTER), feathered/soft motion, silence, and *readability*. The transformation, not the transition, is the star.
- **D. Never:** fast/flashy wipes, shape/parallax reveals, effect stacking, bounce easing, loud CTAs, generative morph, anything that says "look at the effect" instead of "look at your home".

---

# EXECUTIVE REVEAL SPEC SUMMARY
- **Recommended reveal:** **luxury soft-edged sweep** (feathered, single-direction) + synchronized **≤3% push** on both layers; **cross-dissolve** as the calm secondary. Doubles as the existing manual slider.
- **Recommended timing:** **~5.5s default** (BEFORE 1.2s · sweep 1.8s · AFTER 2.5s); social-export profile ~4s; App-Store ~5s.
- **Recommended UX:** reward-framed auto-play once → settle on AFTER + manual scrub + replay; tap→fullscreen; silent; subtle settle haptic; **instant (no buffering)**.
- **Biggest risks:** too-fast/flashy transition, over-zoom, parallax, effect stacking → all banned by hard rules (§12).
- **V1 recommendation:** ONE reveal (sweep + ≤3% push), default pacing, reusable `RevealController`, 9:16 watermarked MP4 export.
- **Implement first:** the **`RevealController`** (timeline + two-layer mask + shared transform) powering in-card auto-reveal + manual slider; then the **watermarked export** for sharing/App-Store. This ships premium value **with zero provider/AI dependency** — do it before Part B.
