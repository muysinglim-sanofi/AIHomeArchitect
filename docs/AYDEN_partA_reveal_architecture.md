# AYDEN Studio — Part A Reveal Engine — Technical Architecture (Flutter)

> Status: **architecture proposal — NO code yet** · Date: 2026-06-06
> Companion: `AYDEN_partA_reveal_spec.md` (UX/motion spec). This doc = how to build it.
> Constraint: **frontend-only for interactive**; export adds ONE additive backend route later. Honors `feedback_video_isolation` (never touch the image core/DNA).

---

## 0. Grounding — what already exists (we EVOLVE, not rebuild)

The app already has a clean Wave-4 reveal foundation:
- **[`RevealHero`](../frontend/lib/shared/widgets/reveal_hero.dart)** — the shared before/after compare surface: `fraction` semantics (portion from LEFT showing BEFORE), an imperative **auto-sweep** (`TweenSequence`: 0.30→0.66→settle **0.42**), manual drag (`handle`/`surface`/`none`), magnetic snap, labels, overlay. Wipe = **hard-edged** `ClipRect`+`OverflowBox`+1px divider+handle.
- **[`RevealCanvas`](../frontend/lib/shared/widgets/reveal_canvas.dart)** — immersive framing (ambient blur backdrop, scrims, overlays). Stateless, performance-conscious (static blur in `RepaintBoundary`).
- **[`before_after_screen.dart`](../frontend/lib/features/result/before_after_screen.dart)** — the reveal screen.

**Decision: the "RevealController" the spec asks for is the principled refactor of `RevealHero`'s animation brain into a declarative, reusable, export-ready engine — keeping `RevealCanvas` as the framing layer untouched.**

---

## 1. Three challenges to the brief (resolve BEFORE coding)

**Challenge A — Product divergence: "compare-tease" vs "cinematic reveal".**
Today's auto-sweep **settles half-open at 0.42** (after-dominant from the start, a *compare tease*) — intentionally, because Home/FTUE want "the result is the hero immediately". Part A's cinematic spec wants the **opposite ordering**: hold **full BEFORE** → sweep → **settle on full AFTER** (recognition → projection). These are two *different* emotional intents on the same widget.
→ **Resolution:** do NOT overwrite the existing behavior (it powers Home/FTUE). Introduce a **`RevealProfile`** (declarative timeline). Keep the current behavior as `RevealProfile.compareTease`; add `RevealProfile.cinematic` (before→after, settle on after) for the result reveal + export. This is the isolation principle applied *inside* the frontend.

**Challenge B — Export parity is THE hard problem.**
"Exported MP4 reproduces EXACTLY the in-app animation" is the riskiest requirement. A Flutter `ShaderMask` render and a server `ffmpeg` render will **not** be bit-identical. Two honest options:
- (1) **Server-side ffmpeg** implementing the SAME serializable timeline spec → light, consistent, watermarkable, scalable; parity is **visual** (verified by golden-frame QA), not bit-exact.
- (2) **Client-side frame capture** (`RepaintBoundary.toImage()` per frame → encode) → **guaranteed parity** (same widget) but heavy: jank, memory, slow encode on mid Android, large-image cost.
→ **Resolution:** make the **timeline declarative & serializable NOW** (the one architectural decision that matters this phase) so EITHER renderer is a pure consumer. Recommend **server-side ffmpeg + shared spec + golden-frame parity tests** for V1 (quality/watermark/consistency win; "visually identical" is the realistic, sufficient bar). Keep client-capture as a documented fallback if true parity is ever mandated.

**Challenge C — Soft feathered edge vs the existing hard divider.**
The cinematic sweep needs a **feathered** edge (spec §3/§4); today's wipe is a hard `ClipRect`+1px line+handle. The handle/divider belong to **manual** mode (a tool), not the cinematic auto-reveal (a film).
→ **Resolution:** render the wipe via a **`ShaderMask` (linear gradient with a small feather band)** driven by `revealProgress`. Show the divider+handle **only in manual mode**; the cinematic auto profile shows a clean feathered sweep, no chrome.

---

## 2. Technical architecture proposal

**One source of truth:** a single `revealProgress` ∈ [0,1] (0 = full BEFORE, 1 = full AFTER) that **both** the auto-timeline and the manual scrub write to, and that **both** the on-screen widget and the export renderer read. This is what makes it ONE system, not two.

```
        ┌──────────────────────────────────────────────┐
        │              RevealController                  │  (ChangeNotifier/Listenable)
        │  • revealProgress 0..1  (single source)        │
        │  • mode: auto | manual                         │
        │  • RevealProfile (declarative timeline)        │
        │  • AnimationController drives auto;             │
        │    gesture sets progress in manual             │
        └───────────────┬───────────────┬───────────────┘
                         │ reads          │ reads
              ┌──────────▼─────┐   ┌──────▼──────────────┐
              │  RevealWidget  │   │  RevealExportSpec    │ (serializable)
              │  (on-screen)   │   │  → server ffmpeg     │
              └──────────┬─────┘   └─────────────────────┘
                         │ wrapped by
                   ┌─────▼───────┐
                   │ RevealCanvas │ (existing framing, unchanged)
                   └─────────────┘
```

**`RevealTimeline` (pure, the keystone):** a *pure function* `sample(elapsed) → RevealFrame { progress, zoom }` derived from a declarative `RevealProfile { beforeHold, sweep, afterHold, easing, feather, zoomPct, settle }`. No widget/imperative state. Both the AnimationController loop and the export renderer evaluate the same function → deterministic, reproducible, testable.

**`RevealProfile` presets:** `compareTease` (existing 0.30→0.66→0.42), `cinematic` (default ~5.5s: hold BEFORE → sweep → settle AFTER), `social` (~4s), `appStore` (~5s), `fast` (preview). Profiles are data, not code paths.

---

## 3. Flutter implementation plan (widget hierarchy)

```
RevealCanvas (existing, unchanged)            ← immersive frame + ambient backdrop
 └─ RevealWidget (new; supersedes RevealHero internals)
     └─ Transform (shared ≤3% zoom, outermost → both layers scale identically)
         └─ Stack
             ├─ AfterImage  (full-bleed base)
             ├─ BeforeImage (full-bleed, masked by ShaderMask(progress, feather))
             ├─ [manual only] divider + handle (chrome)
             ├─ [optional] labels (AppPill)
             └─ [manual only] GestureDetector (handle/surface drag → controller.setProgress)
```

- **`RevealController`** (new, `frontend/lib/shared/reveal/reveal_controller.dart`): owns `revealProgress`, `mode`, the `AnimationController`, profile playback (`play()`, `replay()`, `scrubTo()`, `pause()`), disposes cleanly.
- **`RevealTimeline` + `RevealProfile` + `RevealFrame`** (new, pure Dart, no Flutter import → unit-testable + shareable with export spec).
- **`RevealWidget`** (new): stateless-ish, rebuilds only on `revealProgress` via `AnimatedBuilder`/`ListenableBuilder` around the mask+transform (images are static → no decode per frame).
- **`RevealExportSpec`** (new, serializable): `{ beforeUrl, afterUrl, profile, aspect, watermark }` → sent to the backend export route later.
- **Migration:** `RevealHero` is refactored to delegate to `RevealController`+`RevealWidget` with `RevealProfile.compareTease`, so Home/FTUE/Reveal keep identical behavior (1:1, per its docstring intent). No call-site breakage.

---

## 4. Animation strategy

- **Auto:** one `AnimationController` (duration = profile total) → `elapsed` → `RevealTimeline.sample(elapsed)` → sets `revealProgress` + `zoom`. Easing lives in the timeline (documented cubic-bezier, e.g. `easeInOutCubic`) so export can replicate it.
- **Manual:** gesture → `controller.scrubTo(progress)`; the AnimationController is stopped; same `revealProgress` notifier → seamless hand-off (no dual state). Magnetic snap (existing logic) becomes a profile option on release.
- **Interruptibility:** any drag cancels auto (existing `_userInteracted` pattern, formalized as `mode`).
- **Rebuild discipline:** `AnimatedBuilder` scoped to mask+transform only; `RepaintBoundary` around `RevealWidget`; images via `gaplessPlayback` cached providers → only the GPU mask/transform updates per frame.

---

## 5. State flow

```
generation completes
   → result card builds RevealController(profile: cinematic, autoplay: once)
   → controller.play(): BEFORE hold → sweep (progress 0→1, zoom 1→1.03) → settle AFTER
   → on settle: subtle HapticFeedback.selectionClick(); mode=manual idle
   → user can: scrubTo (drag) | replay() | open fullscreen | share→export
fullscreen: same controller/profile, dragMode=surface, gentle loop
export: build RevealExportSpec from the same profile → backend render → MP4
```
Controller is **scoped per result** (not global); disposed with the widget (no leaks). No global reveal state.

---

## 6. Export compatibility strategy

- **Now (this phase):** implement **only** the declarative timeline + `RevealExportSpec` serialization. NO renderer yet. This guarantees export is later a *pure consumer* of the same spec.
- **Later (Phase A3):** a **new additive backend route** `POST /reveal/export` (own module, e.g. `backend/reveal_export/`) → ffmpeg renders the spec (2 images + gradient-wipe + zoompan + watermark) → returns MP4 to storage. **Isolation-safe**: reads image URLs, writes a clip, never touches `/generate` or the DNA.
- **Parity guarantee:** a **golden-frame test harness** — render N timestamps in Flutter (`toImage`) and on the server; compare side-by-side; tune the ffmpeg gradient feather + easing until visually identical. Document the easing curve as the contract between the two renderers.
- **Honest bar:** "visually identical", not bit-identical (see Challenge B).

---

## 7. Performance considerations

- **Cost model:** 2 cached images + 1 `ShaderMask` gradient + 1 `Transform` = negligible GPU; 60fps target on mid Android.
- **Large images:** display-resolution decode for interactive (`ResizeImage`/cacheWidth); full-res only at export (server-side anyway).
- **Preload:** prefetch BOTH before/after (`precacheImage`) before `play()` so the reveal is **instant, no spinner** (spec hard rule).
- **Memory:** dispose controllers; rely on Flutter image cache (shared with `RevealCanvas` ambient — same provider, single decode).
- **Low-end fallback:** if frame budget slips, **drop zoom to 0%** (keep the wipe) before dropping frames; optionally reduce feather.
- **No `BackdropFilter` per frame** (RevealCanvas already avoids this).

---

## 8. Risk analysis

| Risk | Sev | Mitigation |
|---|---|---|
| **Export ≠ in-app animation** | **High** | declarative shared spec + golden-frame harness; accept "visually identical" |
| Breaking Home/FTUE by changing auto-sweep | High | profiles; keep `compareTease` 1:1; refactor behind same API |
| Image decode jank on large images | Med | precache + cacheWidth + downscale for display |
| Dual slider/auto state desync | Med | single `revealProgress` source of truth |
| AnimationController leaks | Med | scoped controller, dispose in widget |
| ShaderMask feather perf low-end | Low-Med | reduce feather / fallback hard edge |
| Before/after aspect mismatch | Low | same source → same aspect; assert + letterbox via RevealCanvas |
| Scope creep (building export now) | Med | this phase = timeline+spec only |

---

## 9. Suggested packages

- **Interactive: zero new deps** — `AnimationController`, `ShaderMask`, `Transform`, `RepaintBoundary`, `HapticFeedback`, `AspectRatio`, `precacheImage` (all Flutter SDK). Image caching = existing `cached_network_image`.
- **Sharing (Phase A3):** `share_plus`.
- **Export render (Phase A3):** **server-side `ffmpeg`** (recommended, no Flutter dep). Documented fallback: client `ffmpeg_kit_flutter_new` (heavy — only if bit-parity ever mandated).
- **Testing:** Flutter golden tests for `RevealWidget` frames; pure unit tests for `RevealTimeline`.

---

## 10. Phased implementation plan (go/no-go gated)

| Phase | Deliverable | Touches | Go/No-Go |
|---|---|---|---|
| **A0 (this)** | Architecture validated | docs only | user approves §1 resolutions |
| **A1** | `RevealTimeline`+`RevealProfile`+`RevealController` (pure brain) + unit tests | new frontend files | timeline reproducible in tests |
| **A2** | `RevealWidget` (ShaderMask sweep + shared zoom) + `cinematic` profile in result card; auto-play once → settle AFTER | new frontend; result card | 60fps mid-Android; feels premium |
| **A3** | Refactor `RevealHero`→delegate (compareTease), preserve Home/FTUE | RevealHero internals | Home/FTUE visually 1:1 (golden tests) |
| **A4** | Manual scrub + replay + fullscreen on the unified controller | frontend | seamless auto↔manual hand-off |
| **A5** | `RevealExportSpec` serialization + `POST /reveal/export` ffmpeg + watermark + golden-frame parity | new backend module (additive) + share | exported MP4 visually matches in-app |
| **A6** | Timing profiles (social/appStore/fast) + share flow | frontend | profiles ship |

**Critical gate:** A3 must prove Home/FTUE unchanged (golden tests) before merge. A5 must pass the parity harness before any social/App-Store export is published.

---

# EXECUTIVE ARCHITECTURE SUMMARY
- **Evolve, don't fork:** the "RevealController" = principled refactor of the existing `RevealHero` brain into a **declarative, profile-driven, export-ready** engine; `RevealCanvas` stays as the frame.
- **One source of truth:** a single `revealProgress` 0..1 shared by auto-timeline, manual scrub, and export → genuinely ONE system.
- **The one decision that matters now:** make the **timeline declarative & serializable** so export is a pure consumer later.
- **3 resolved challenges:** profiles (don't break Home/FTUE); export parity via shared spec + golden frames (server-side ffmpeg, "visually identical"); feathered `ShaderMask` sweep (chrome only in manual mode).
- **Isolation:** all interactive work is frontend; export is ONE additive backend route — image core/DNA untouched.
- **Recommended first build:** Phase A1 (pure timeline/controller + tests), then A2 (cinematic reveal in the result card). Ship premium value with zero provider/AI dependency.

**→ Validate the §1 resolutions (profiles, server-side export parity, feathered ShaderMask) and I'll propose the A1 execution steps.**
