# AYDEN Studio — Phase 1B: Live Provider Reality Check (June 2026)

> Status: **research, no implementation** · Date: 2026-06-06 · Source basis: live web research June 2026 (links at end).
> Companion to: `AYDEN_video_benchmark_playbook.md`, `AYDEN_cinematic_reveal_v1_master_design.md`.
> **Caveat:** prices/limits move monthly — figures are current-as-of-June-2026 estimates; reconfirm on provider dashboards at integration.

---

## 1. EXECUTIVE MARKET OVERVIEW

The I2V market in mid-2026 is **mature enough for AYDEN's *restrained* use case — but only on AYDEN's terms (locked camera, low motion).** Brutally honest read:

- The current frontier is **Google Veo 3.1**, **Kling 3.0**, **Runway Gen-4.5** (Sora 2 is being **discontinued** — web/app shutting, API to follow later 2026 → **do not build on Sora**). Cheaper challengers: ByteDance **Seedance 2.0** and **Wan 2.5**.
- **The thing AYDEN needs (subtle ambient motion on a fixed image) is the *easy* regime for these models.** The hard regime — which AYDEN deliberately avoids — is camera movement + dynamic action.
- **Key external confirmation of our doctrine:** research explicitly notes *"straight lines and precise geometry… columns, window mullions, structural grids can warp or drift during camera movement, particularly in text-to-video."* → Our two core decisions (I2V, locked camera) are not stylistic; they are **the** levers that the market itself says reduce architectural warp.
- **Are we early?** For *flashy* AI interiors, the market is past-ready. For *flawless* preservation on reflective/furniture-dense rooms, we're at the edge — achievable on easy rooms, fragile on hard ones. That's exactly why the playbook gates rooms.

**Verdict:** the vision is realistic **today** for outdoor/ambient rooms; partially for the living-room hero; not for kitchen/bathroom/facade (correctly excluded).

---

## 2. PROVIDER-BY-PROVIDER ANALYSIS

### Runway (Gen-4 / Gen-4.5 / Gen-4 Turbo)
- **A. Capabilities:** mature I2V; up to 10s/gen (Gen-4 up to 60s native + extend); **Motion Brush 3.0 = paint/mask which regions move with speed+direction vectors** (= the static-region masking AYDEN wants); camera-motion descriptors. Native API + developer portal.
- **B. Preservation:** **best controllability** for our use case — masking static regions + amplitude control = the strongest lever to keep walls/furniture frozen while only curtains/foliage move. Low-motion behavior good.
- **C. API maturity:** native API, dev portal, credit billing, documented; production-grade. Strong.
- **D. Economics:** $0.01/credit. **Gen-4 Turbo = 5 cr/s → $0.05/s → 5s ≈ $0.25**; Gen-4 = 12 cr/s → $0.12/s → 5s ≈ $0.60. (Plans from ~$12-15/user/mo for UI.)
- **E. Risks:** can still drift if motion pushed; cost mid.
- **F. Strategic fit:** ★★★★★ control = preservation. **AYDEN fit 9/10.** Prioritizes production control over spectacle — perfectly aligned.

### Kling (3.0)
- **A. Capabilities:** I2V, **start+end frame**, motion brush (extra credit), multi-ref identity, clip extension; multi-shot/audio (irrelevant to us).
- **B. Preservation:** **best organic-motion realism** (water, fabric, foliage physics) — ideal for **pool/terrace/garden/tropical**. Slightly **less fine amplitude control** than Runway → marginally higher drift risk on hard interiors.
- **C. API maturity:** dev API exists but **best accessed via aggregators (fal.ai/Replicate)**; prepaid packages; consumer plans ≠ API.
- **D. Economics (via fal):** Standard **$0.084/s**, Pro **$0.112/s** → 5s ≈ **$0.42–0.56**. I2V costs ~10-30% more than T2V.
- **E. Risks:** **data/region (China-based)** considerations; latency variable; motion-brush surcharge.
- **F. Strategic fit:** ★★★★☆ realism is its identity, great for outdoor. **AYDEN fit 8/10** (knock for control + region).

### Luma Dream Machine (Ray2 / Ray2 Flash)
- **A. Capabilities:** I2V, gentle/natural motion; API; Flash (cheap/fast) + Standard tiers.
- **B. Preservation:** soft, non-flashy motion suits restraint; **less explicit static masking**; occasional softness/minor drift.
- **C. API maturity:** official API + on fal.ai; separate API wallet.
- **D. Economics:** ~**$0.08–0.10/s** (fal: Ray2 I2V ≈ **$0.50 / 5s**; Flash cheaper). Among the cheapest premium-grade.
- **E. Risks:** less control surface; quality below Veo/Kling ceiling.
- **F. Strategic fit:** ★★★★☆ calm realism + cheap = excellent **backup**. **AYDEN fit 7.5/10.**

### Google Veo (3.1 / 3.1 Lite) — ⚠️ commercial caveat
- **A. Capabilities:** I2V with strong physics; 720p/1080p, up to 4K (landscape+portrait); via **Vertex AI** (enterprise) + **Gemini API** (dev).
- **B. Preservation:** **most temporally STABLE** of all (re-runs are structurally similar — gold for our repeatability bar) + top realism. Best raw preservation ceiling.
- **C. API maturity:** strong (Vertex + Gemini), pay-per-use, enterprise-ready.
- **D. Economics:** **Veo 3.1 Lite (no audio) ~$0.03/s → 5s ≈ $0.15** (cheap!); Veo 3.1 w/audio ~$0.40/s; Veo 3.0 Vertex $0.50/s.
- **E. Risks (BIG):** **Veo 3 (base) commercial use PROHIBITED (Pre-GA)** — must use **Veo 3.1** for commercial; **mandatory SynthID watermark** on Veo output (invisible — acceptable since we add our own visible mark anyway, but note it); access/quota.
- **F. Strategic fit:** ★★★★☆ best stability+realism+cheap-Lite, **if** we use 3.1 (not 3.0) and accept SynthID. **AYDEN fit 8/10** (knock for commercial-terms vigilance + control surface less explicit than Runway).

### Excluded
- **Sora 2:** ★ — **being discontinued.** Do not build on it.
- **Pika:** ★★ — effects/gimmick orientation → wrong brand fit.
- **Stability (SVD):** ★★ — lower realism, more drift.
- **Seedance 2.0 / Wan 2.5:** cheap ($0.03–0.05/s), worth a *cost-reference* test later, but unproven for AYDEN preservation — not a V1 primary.

---

## 3. MOTION CONTROL COMPARISON

| Capability | Runway G4.5 | Kling 3.0 | Luma Ray2 | Veo 3.1 |
|---|---|---|---|---|
| Motion amplitude control | **Best** (vectors) | Med (brush surcharge) | Low-Med | Med |
| Camera lock | Yes (omit camera tokens) | Yes | Yes | Yes |
| **Static-region masking** | **Yes (Motion Brush 3.0)** | Partial (brush) | Limited | Limited |
| Subtle-motion quality | High | High | **High (gentle)** | High |
| Temporal consistency | High | High | Med-High | **Best** |
| Loop quality | Med (post-process) | Med | Med | Med |
| Realism at low motion | High | **High** | High | **High** |

**Takeaway:** **Runway = control king** (masking + amplitude = preservation). **Veo = stability king.** **Kling = organic-realism king.** All support the locked-camera regime AYDEN requires.

---

## 4. PRESERVATION RISK COMPARISON (expected)

| Surface | Expected weak point (all models) | Best handled by |
|---|---|---|
| Walls / straight lines / mullions | Warp **if camera moves** → keep camera locked | Runway (mask), Veo (stable) |
| Furniture integrity | Drift if motion high → low amplitude | Runway (mask static) |
| **Mirror / marble reflections** | **Highest morph risk** (Soft Luxury) | Veo (stable) / Runway (mask) — still risky |
| Foliage / plants | Easy + natural | Kling, Veo |
| Water (pool) | Easy + natural, looks great | **Kling**, Veo |
| Curtains / textiles | Easy, occasionally "liquid" if over-driven | Runway (amplitude), Kling |
| Lighting stability | Occasional cast shift/flicker | Veo (stable); enforce "colours true to source" |

**Artifact signatures to expect:** edge "boiling" on textures, denoise "swim", mirror morph, minor shimmer. **Perfect** preservation is not guaranteed by any model — the gate + best-of-N + locked camera are what make it shippable.

---

## 5. AGGREGATOR STRATEGY

- **fal.ai:** cheapest for video breadth, **low latency (~0.5s warm start)**, hosts Kling/Luma/Veo/Seedance/Wan. **Best for a click-and-wait UX** and for fast multi-model benchmarking on identical inputs.
- **Replicate:** 1000+ models, very mature/reliable, but **higher start latency (~2-3s)** — better for batch than interactive.
- **Runway:** best via **native API** (its control features are first-class there).

**Recommendation:** **benchmark Kling + Luma + Veo via fal.ai** (one integration, identical inputs, low latency) and **Runway via its native API** (to get Motion Brush). This is benchmark-only; production can keep fal as a multi-provider backbone + Runway native. Using an aggregator also de-risks **provider hot-swap** (our architecture principle).

---

## 6. REALISTIC BENCHMARK EXPECTATIONS (honest)

- ✅ **Pool / terrace / garden (organic motion):** likely **PASS** — water/foliage motion is natural and lives away from hard lines. This is where AYDEN video will shine first.
- 🟡 **Living room (hero):** likely **WARN** — sheer-curtain + light-shift can work with locked camera + low motion, but furniture density raises drift odds. Expect best-of-N needed.
- 🔴 **Soft Luxury reflective (marble/mirror):** **hardest** — reflection morph is the #1 failure; expect frequent FAIL; may need to limit motion to "light only" or exclude reflective scenes.
- ❌ **Kitchen / bathroom / facade / driveway:** correctly excluded V1 — hard lines/fixtures/whole-building drift.
- **Universal truths:** *perfect* preservation is unrealistic; **minor shimmer is sometimes unavoidable**; **camera must stay locked** (movement = warp); **low amplitude is mandatory**; **best-of-N (2-3) is not optional** — it's how you get a shippable take.
- **Loops** likely need a light post-process (fade) — don't expect perfect native loops.

---

## 7. UPDATED PROVIDER PRIORITY (post-research)

1. **Runway Gen-4.5** — *control = preservation* (Motion Brush static-masking + amplitude). Best odds of keeping AYDEN architecture frozen. **Test first.**
2. **Kling 3.0** — *organic realism* for the flagship outdoor rooms (pool/terrace). Test second (via fal).
3. **Veo 3.1** — *stability + realism ceiling*, cheap Lite tier; **use 3.1 not 3.0** (commercial), accept SynthID. Test as ceiling/backup.
4. **Luma Ray2** — *cheap, gentle* — strong economical **backup**.
*(Seedance 2.0 / Wan 2.5 = later cost-reference only.)*

**Why this order:** AYDEN's #1 failure mode is structural drift → the provider that lets us *mechanically lock structure* (Runway masking) is tested first; the realism kings (Kling/Veo) validate the "believable life" bar on the easy rooms.

---

## 8. UPDATED GO/NO-GO RISK ANALYSIS

| Dimension | Real risk today |
|---|---|
| **Will subtle ambient motion work at all?** | **Low risk** — yes, on easy rooms. The market is ready for this regime. |
| **Will it preserve hard interiors (SL marble, dense living)?** | **Medium-High risk** — the genuine uncertainty. Mitigate via masking + low motion + best-of-N + room gating. |
| **Cost** | Medium — $0.15–0.60/clip × best-of-N → premium-gating mandatory; Veo Lite + caching keep it sane. |
| **Latency** | Low-Med — async pipeline absorbs it; fal warm pools help. |
| **Commercial/legal** | Medium — **Veo 3 base prohibited; SynthID forced on Veo; Kling region/data; verify ToS per provider.** |
| **Provider volatility** | Medium — Sora dying proves it; mitigate with abstraction + 2-provider strategy. |

**Likely to work:** outdoor/ambient. **Likely to fail/limit:** reflective + furniture-dense. **Biggest remaining danger:** shipping a subtly-warped clip (caught only by a strict gate).

---

## 9. RECOMMENDED BENCHMARK EXECUTION PLAN (concrete)

1. **Provider to test first:** **Runway Gen-4.5** (native API), then **Kling 3.0** + **Luma Ray2** + **Veo 3.1** via **fal.ai**.
2. **Room to test first:** **Pool × Tropical** (easiest, organic water motion) → prove the regime works; then **Living × Soft Luxury** (hardest) to find the ceiling.
3. **Settings first:** I2V; **camera locked** (no camera tokens); **lowest viable motion**; **5s**; native aspect; **Runway: mask everything except curtains/water/foliage**; baseline prompt from playbook §4.
4. **Success looks like:** Pool/terrace PASS repeatably (≥2/3 takes), zero structural drift, "publishable" = yes; Living at least WARN with no auto-fail.
5. **Failure looks like:** any wall/furniture/mullion movement, mirror morph, colour-cast shift, or "cheap AI" gut read → FAIL; if even Pool can't pass on any provider → NO-GO (ship Part A only).

---

## 10. FINAL STRATEGIC RECOMMENDATION (brutal)

**A. Achievable today?** **Yes — conditionally and narrowly.** Subtle "breathing" of preserved interiors is within reach *now* for outdoor/ambient rooms with locked camera + low motion + masking + best-of-N. It is **not** reliably achievable on reflective/furniture-dense interiors yet.

**B. Realistic quality today?** Premium-publishable on **pool/terrace/garden** and many **living** scenes; **inconsistent** on Soft-Luxury reflective and dense rooms (gate or limit to light-only). Perfect preservation everywhere = not yet.

**C. Absolutely avoid:** camera movement, high motion, text-to-video, generative before→after morph, Sora (dying), Veo **3.0** for commercial, shipping any un-gated clip.

**D. Smartest MVP path:** **Part A deterministic before→after (always) + Part B I2V "breathe" gated to outdoor + easy living, premium-only, best-of-N, strict QA gate, image fallback.** Launch the breathe on the rooms that *can't fail* (pool/terrace/garden) first; expand on evidence.

**E. Most promising provider now:** **Runway Gen-4.5** for preservation/control (primary candidate), **Kling 3.0** for outdoor realism (co-primary to bench), **Veo 3.1** as stability/quality ceiling + backup (mind commercial terms), **Luma Ray2** as cheap backup. Final pick = whoever wins the §9 bench on *your* images.

---

# EXECUTIVE DECISION SUMMARY

- **Top candidates:** **Runway Gen-4.5** (control/preservation) + **Kling 3.0** (outdoor realism); **Veo 3.1** (stability ceiling, use 3.1 not 3.0, SynthID) + **Luma Ray2** (cheap) as backups. **Avoid Sora (EOL), Pika, Stability, Veo 3.0-commercial.**
- **Biggest risks:** structural drift on reflective/dense interiors; shipping a subtly-warped clip; cost × best-of-N; provider volatility & Veo commercial terms.
- **Realistic expectations:** outdoor/ambient = publishable now; living = best-of-N/WARN; reflective SL = limit/exclude; perfect preservation = not guaranteed; minor shimmer possible; **locked camera + low motion are non-negotiable**.
- **Recommended next action:** **Benchmark via fal.ai (Kling/Luma/Veo3.1) + Runway native**, starting **Pool×Tropical** then **Living×Soft-Luxury**, locked camera + min motion + Runway static-mask, scored on the playbook matrix. **GO** only if an easy room PASSes repeatably with zero structural drift; else ship **Part A only**.
