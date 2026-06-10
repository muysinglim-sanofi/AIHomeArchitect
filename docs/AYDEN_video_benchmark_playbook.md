# AYDEN Studio — Video Provider Benchmark Playbook (Phase 1)

> Status: **Phase 1 — Benchmark (no implementation)** · Date: 2026-06-06
> Companion to: `AYDEN_cinematic_reveal_v1_master_design.md` (canonical philosophy).
> **No coding.** Manual upload → manual generation → manual scoring. Goal: pick **1 primary + 1 backup** I2V provider.
> Provider pricing/API specifics are at knowledge cutoff Jan 2026 — **verify live before testing.**

## Scope clarification (read first)
The V1 clip = **Part A (deterministic before→after transition)** + **Part B (After "breathing" I2V tail)**.
- **Part A needs NO benchmark** — it is post-production compositing of two real stills (dissolve / luxury reveal-sweep / animated slider / non-generative push). Zero AI, zero drift. It is an implementation detail, not a provider question.
- **Phase 1 benchmarks ONLY Part B**: subtle ambient I2V motion on the **After image alone**. The entire feature's viability hinges on this one question (below).

---

## 1. PHASE 1 OBJECTIVE

**The one question:** *Can a current I2V provider add subtle ambient architectural motion to a real AYDEN After-image while keeping geometry, perspective, lighting and realism perfectly intact — repeatably, affordably, and at a quality a luxury brand would publish?*

- **Success** = at least **one** provider clears the bar (PASS, §6) on the V1-eligible rooms, **repeatably** (not a lucky single take), with acceptable cost/latency, and **zero brand-damaging artifacts**.
- **Failure** = no provider clears the bar → **do not build generative video in V1.** Ship **Part A only** (deterministic before→after + optional non-generative Ken-Burns), defer Part B to a re-benchmark when models improve.
- **Must be proven before any implementation:** (a) structural stability at low motion is *achievable and repeatable*; (b) the "would a luxury brand publish this?" bar is met on real images; (c) cost/latency are viable for a premium-gated feature.

**Overriding gate (every decision serves this):** *"Would a luxury architectural brand confidently publish this clip publicly?"* — NOT "is this impressive AI?".

---

## 2. PROVIDER SHORTLIST (prioritized; verify specifics live)

Optimized for **preservation + subtle realism**, NOT flashy cinematic AI.

| Tier | Provider | Why test it | Expected strength (AYDEN) | Expected weakness / risk |
|---|---|---|---|---|
| **1 — test first** | **Runway (Gen-3/Gen-4) I2V** | Best **motion control** (amplitude, motion brush to **mask static regions**), mature API, strong I2V | Fine low-amplitude control = best shot at preservation | Can still drift if pushed; cost moderate |
| **1** | **Kling (1.6 / 2.x) I2V** | Top-tier **realism & physics** (water/fabric/foliage look real) | Most "believable life", great for tropical/pool | Access via aggregators (fal/Replicate); latency variable; **data/region** considerations; less fine amplitude control |
| **1** | **Luma Dream Machine (Ray2) I2V** | Soft, natural realism; good ambient motion; API | Gentle, non-flashy motion suits restraint | Less explicit motion masking; occasional softness/drift |
| **2 — if accessible** | **Google Veo 2/3 I2V** | Best-in-class realism/coherence | Could be the quality ceiling | Access/quota/**premium cost**; control surface uncertain |
| **Excluded V1** | **Pika** | — | — | Effects/gimmick-oriented → **wrong brand fit** |
| **Excluded V1** | **Stability (SVD)** | — | cheap/self-host | Lower realism, more drift → not premium |

**Access tip:** test Tier-1 via an **aggregator (fal.ai / Replicate)** to compare Runway/Kling/Luma on the *same* images fast, without 3 native integrations (this is benchmark-only, not the production path).

**Priority order to actually run:** Runway → Kling → Luma → (Veo if accessible).

---

## 3. BENCHMARK DATASET

Use **real, validated AYDEN After-images** (not demos). Cover the V1-eligible rooms × the risk spectrum. Each case is chosen to probe a *specific* failure mode.

| # | Room × Atmosphere | Difficulty | What it probes |
|---|---|---|---|
| 1 | **Pool × Tropical** | Easy | Best case — natural water/foliage motion; baseline "does it work at all" |
| 2 | Terrace × Warm Modern | Easy-Med | Curtains + light; colour-cast (de-orange) under motion |
| 3 | Garden × Japandi | Med | Restraint test — can motion stay *barely there*? |
| 4 | Balcony × Nordic | Med | Candle/light + textiles; flicker risk |
| 5 | **Living × Warm Modern** | Med-Hard | Hero room; furniture density + sheer curtains + light |
| 6 | **Living × Soft Luxury** | **Hard** | Marble/mirror **reflection morph** + furniture density (worst-case) |
| 7 | Pool × Soft Luxury | Med | Reflective water + symmetry stability |
| 8 | Terrace × Tropical | Easy-Med | Lush foliage without "jungle" over-motion |
| (stress) 9 | A furniture-dense / strong-line source (any) | **Hard** | Straight-line stability (door/window mullions) |
| (stress) 10 | A source with a person/plant edge case | Hard | Hallucination tendency |

**Size:** ~8 core + 2 stress = **10 images**. Per image, test on each Tier-1 provider (§5). Keep a **fixed, frozen set** so every provider is judged on identical inputs.

---

## 4. BASELINE MOTION PROMPT (official AYDEN reference)

**Doctrine:** describe **MOTION + ATMOSPHERE**, never the scene. Layered, identical structure across providers (translate to each provider's fields).

**Canonical baseline (living/terrace example):**
> *Subtle ambient motion only. Sheer curtains drift gently in a faint breeze; soft daylight shifts slowly; foliage outside sways lightly. Camera locked, no movement. Photoreal, calm, premium, architectural. Walls, windows, doors, furniture, proportions and perspective stay perfectly fixed and undistorted; colours stay true to the source.*
> Negative/preserve: *no warping, morphing, bending lines, moving furniture, layout change, camera shake, fast motion, zoom, people or objects appearing, colour-cast shift.*

**Room preset swaps (the only part that changes):**
- Pool: *gentle water ripples and reflections; foliage swaying softly.*
- Garden: *grasses and foliage swaying softly; soft light shifting.*
- Balcony/Nordic: *candle flame flickering softly; light textiles drifting; warm calm light.*
- Japandi: *barely-there motion — a single branch and soft shadow only; deep stillness.*

**Forbidden / dangerous words (AI-cheapness triggers):** cinematic, dynamic, dramatic, epic, sweeping, reveal, transformation, fast, zoom, push (hard), flythrough, hyperlapse, magical, morph, particles, lens flare, "4D".

**Settings doctrine:** lowest viable **motion strength**, **camera = locked** (no push-in in the benchmark — isolate ambient motion), duration **5s**, native aspect ratio, **motion mask on static regions** if the provider supports it.

---

## 5. TESTING PROTOCOL (manual, reproducible)

1. **Per (image × provider): generate N = 3 takes.** (Variance is the point — one good take ≠ a reliable provider.)
2. **Seeds:** if exposed, vary seed across the 3; record each.
3. **Params (constant):** motion = minimum viable; camera = locked; duration = 5s; aspect = native; mask static if available.
4. **Retry policy:** if a take is a hard structural FAIL, note it (do NOT silently re-roll to flatter the provider) — failure rate is data.
5. **Logging:** one row per take in the comparison sheet (§8): provider, image, seed, params, latency, est. cost, scores, verdict, notes, link to clip.
6. **Viewing discipline:** judge on a **phone screen, looped, muted, at the size users will see** — not zoomed-in on a 4K monitor. Premium perception is the metric.
7. **Blind-ish scoring:** ideally score without knowing which provider (reduce bias); at minimum, score before reading other providers' results.

---

## 6. AYDEN OFFICIAL SCORING MATRIX

Each criterion 0–5. Weighted total /100. **The "publishable?" gate overrides the number.**

| Criterion | Weight | Auto-FAIL trigger |
|---|---|---|
| **Geometry preservation** (lines/openings/walls don't move or bend) | **25%** | Any visible wall/window/door/mullion movement or curvature |
| **Structural stability over time** (no breathing/morph of structure) | **15%** | Any structural "breathing"/morph |
| **Furniture/object integrity** (no sliding/melting/appearing) | **15%** | Any furniture move/melt or object/person hallucination |
| Lighting & colour consistency (no cast shift vs source) | 10% | Obvious colour-cast betrayal |
| Camera stability | 10% | Shake/unrequested move |
| Motion realism (physical, believable) | 8% | — |
| Absence of artifacts (no shimmer/flicker/texture crawl) | 7% | Severe shimmer/flicker |
| Luxury / premium perception | 5% | "cheap AI" gut read |
| Loop quality (seamless) | 3% | — |
| Emotional impact ("alive") | 2% | — |

**PASS/WARN/FAIL:**
- **FAIL** = any auto-fail trigger, OR weighted < 70/100, OR "would a luxury brand publish?" = No.
- **WARN** = 70–84, no auto-fail (usable only via best-of-N selection).
- **PASS** = ≥ 85, no auto-fail, and "publishable?" = Yes.

**Golden rule:** a **single severe structural drift FAILS the clip**, regardless of how beautiful the rest is. Preservation is categorical, not averaged.

---

## 7. FAILURE TYPOLOGY ("wall of shame")

**Geometry/structure**
- Breathing walls/ceiling; bending/curving straight lines; window-mullion or door-frame distortion; perspective drift; opening narrowing/closing; room "leaning".

**Furniture/object**
- Furniture sliding/scaling/melting; legs/edges warping; objects appearing/vanishing; plant/person hallucination; reflection inventing fake objects.

**Motion**
- Over-motion (too much amplitude); fake/unphysical motion (curtains like liquid); multiple competing movers (busy); abrupt start/stop; non-loopable.

**Camera**
- Unrequested push/zoom/shake; parallax revealing hallucinated geometry; orbit/drift.

**Lighting/colour**
- Colour-cast shift (e.g. WM re-warming to orange); flicker/strobe; blown highlights; "cinematic teal-orange" grade betraying source.

**Artifact/AI-tells**
- Shimmer/temporal crawl on textures; mirror/marble morph; edge boiling; denoise "swim"; watermark-like ghosting.

**Luxury/branding**
- "Cheap TikTok AI" gut read; over-cinematic spectacle; gimmicky transition; anything that reads as *effect* rather than *life*.

*(This taxonomy seeds the future automated QA gate: structural-edge stability, static-region optical-flow, colour-delta, flicker variance.)*

---

## 8. PROVIDER COMPARISON TEMPLATE

One sheet, one row per **take**; one summary block per **provider**.

**Per-take row:** `provider | image(room×atmo) | seed | motion | camera | dur | latency(s) | est_cost | geom | struct | furniture | light | camera_stab | realism | artifacts | luxury | loop | emotion | weighted/100 | verdict(PASS/WARN/FAIL) | publishable?(Y/N) | top failure | notes | clip_link`

**Per-provider summary:**
| Field | Value |
|---|---|
| PASS rate (of all takes) | |
| Auto-FAIL rate | |
| Best room compatibility | |
| Worst room/atmo | |
| Dominant drift pattern | |
| Motion-control quality | |
| Avg latency / est cost per clip | |
| Strengths | |
| Weaknesses | |
| **Recommendation level** | Primary / Backup / Reject |

---

## 9. BENCHMARK EXECUTION PLAN (order)

1. **Runway — easy case first** (Pool × Tropical). If it can't keep an *easy* case stable at low motion → big red flag.
2. **Runway — hard case** (Living × Soft Luxury). The make-or-break: reflective + furniture-dense.
3. If Runway clears easy + survives hard → **deep-test Runway** across the full 10-image set.
4. **Kling** on the same easy + hard cases. Compare realism vs Runway's control.
5. **Luma** on easy + hard. 
6. **Narrow to 2** strongest → run the **full frozen set** on both.
7. **Stress** the 2 finalists on the hard/edge cases (#6, #9, #10) with N=3 each.
8. (Optional) **Veo** if accessible, as a quality ceiling reference.

**Eliminate a provider when:** it auto-FAILs the **easy** case repeatably, OR FAIL rate > 50% on core set, OR shows a *systematic* structural-drift pattern no setting fixes.
**Deep-test a provider when:** it PASSes easy + at least WARNs the hard case with a clean structural record.

---

## 10. SUCCESS CRITERIA (go/no-go)

**GO to implementation** if ALL:
- ≥ 1 provider achieves **PASS** on ≥ 70% of the **V1-eligible easy/med set**, repeatably (≥ 2 of 3 takes).
- That provider has **0 brand-damaging clips** in the sample that would be publishable (i.e., its FAILs are *caught*, not subtle).
- It at least **WARNs (no auto-fail)** on the hard cases (living/SL) — i.e., hard rooms can be gated/limited, not catastrophic.
- **Latency** acceptable for an async premium flow (target ≲ 60–120s).
- **Cost/clip** within premium-gated economics.
- A clear **#2 backup** exists.

**NO-GO (defer Part B)** if: no provider passes the easy set repeatably, OR structural drift is uncontrollable, OR economics don't work. → Ship **Part A only**; re-benchmark in N months.

---

## 11. FINAL RECOMMENDATION FRAMEWORK

Pick **Primary** = best **preservation + premium perception + repeatability** (NOT the flashiest). Pick **Backup** = different vendor/architecture (failover + price leverage), ideally complementary strength.

**Tradeoff doctrine (AYDEN-aligned):**
- **Realism vs cinematic motion** → always realism. Reject "impressive" if it drifts.
- **Consistency vs creativity** → consistency. A boring-but-stable provider beats a brilliant-but-erratic one.
- **Quality vs latency** → quality wins (async UI absorbs latency), within reason.
- **Quality vs cost** → quality wins (premium-gated), but cap with caching/best-of-N.
- **Control > raw quality** when close: a provider that lets us *mask static regions / cap amplitude* is safer long-term.

---

# EXECUTIVE BENCHMARK PLAN

**Next actions (in order)**
1. **(Pre-req) Verify live** the Tier-1 providers' current I2V capabilities, motion controls, pricing, latency (web check) — or proceed via fal.ai/Replicate aggregator.
2. **Curate the frozen 10-image dataset** from real validated AYDEN After-images (rooms × atmospheres per §3).
3. **Run §9 order**: Runway (easy → hard) → Kling → Luma → narrow to 2 → full set → stress finalists.
4. **Score every take** with the §6 matrix in the §8 sheet; apply the "publishable?" gate.
5. **Decide** with §10 go/no-go and §11 framework → name **Primary + Backup** (or NO-GO → Part A only).

**Provider priorities:** Runway, then Kling, then Luma, (Veo optional).
**Success bar:** repeatable PASS on easy/med eligible rooms, hard rooms at least gated-WARN, zero publishable brand-damage, viable latency/cost.
**Stop/go:** GO only if ≥1 provider + 1 backup meet §10; else NO-GO → ship deterministic Part A and re-benchmark later.

**The whole feature lives or dies on one finding:** can a model keep AYDEN's architecture *perfectly still* while the home gently breathes? Prove that first. Build nothing until it's proven.
