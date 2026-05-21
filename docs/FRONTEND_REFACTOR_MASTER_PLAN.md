# Master Frontend Architecture Refactor Plan

AIHomeArchitect — Premium Frontend Execution Phase
Planning only (no code). Wave names/numbers verbatim & unchanged. Frontend-only. Backend frozen (backend-mvp-freeze-20260519).

Central thesis: "The product says the image is the product. The code says the image is content inside UI." The refactor inverts this — image-dominant surfaces are primary; chat/controls are secondary overlays.

## 1. Executive Summary

The architecture is two shared surfaces plus one design-system spine, adopted screen-by-screen behind the existing structure (no big-bang rewrite):

- RevealHero / RevealCanvas — the single before/after surface, replacing 3 divergent slider copies. Used by Home, FTUE-1, Reveal, Cinematic Viewer.
- GenerationCanvas — the chat result becomes a dominant canvas; conversation becomes a dismissible overlay (Wave 4.11; highest risk; last).
- Design-system spine — editorial typography tokens, unified AppButton / AppPill / dot / radius / scrim / ambient + AppAdaptive extensions. Near-zero risk, highest premium-per-hour ROI, built first because every surface consumes it.

Sequencing principle: risk-ascending, not impact-descending. Ship the spine + AtmosphereCard V2 (4 screens, zero navigation/state/backend touch) first; defer the chat-to-canvas inversion (4.11) to last.

Two foundational facts (verified in code) that lower risk:

- A unified CTA abstraction already exists (AppButton, 4 variants, routes through theme). The CTA inconsistency is screens bypassing it (_DarkButton, _CardAction, raw ElevatedButton radius-12 x3) — fix = route through an extended AppButton, not build a new system.
- A real adaptive-token system already exists (AppAdaptive, height-keyed, consumed by AtmosphereCard/FTUE/Reveal) — fix = extend it (add canvas/hero tokens), not replace.
- Shell topology: Home/Projects/Profile live inside MainShell (persistent bottom nav); Chat/Upload/Reveal/Onboarding are pushed routes with their own Scaffold. Sticky-CTA strategy must differ by shell membership — this is why Home's CTA collides with nav while Upload's does not.

## 2. Shared Component Architecture

| Component | Purpose | Screens | Files create/update | Replaces | Visual behavior | Risk |
|---|---|---|---|---|---|---|
| Typography tokens | Editorial display face for hero/atmosphere; one type system | all | app_theme.dart (add displayEditorial, atmosphereTitle); pubspec font | Inter-only display; hard-coded 'Lato' in atmosphere_card.dart 129/146 | serif/display for hero+atmosphere names, keep w300/-0.5 calibration | Low |
| Radius system | One premium radius language | all | app_spacing.dart (rationalize cardRadius/buttonRadius; add radiusHero) | ad-hoc 12/16/32/50 | consistent corners | Low |
| AppPill | One pill/label/badge primitive | all | shared/widgets/app_pill.dart (new) | _OverlayPill, _SlideLabel, _CategoryPill, _SessionsBadge, inline chips x~5 | text/icon, light/dark, optional onTap | Low |
| AppButton ext + StickyActionBar | One CTA system; persistent footer | all | app_button.dart (add onImage/dark variant); shared/widgets/sticky_action_bar.dart (new) | _DarkButton, _CardAction, raw ElevatedButton radius-12 x3 | pill; on-image variant w/ scrim; sticky bar = bottom Container + safe-area (port upload_screen pattern) | Low |
| Dot indicator token | One progress dot | FTUE, Home | shared/widgets/app_dots.dart (new) | _Dot (24x7), _HeroProgressDot (20x6) | animated active/inactive | Low |
| Scrim system | Legibility over images | Reveal, FTUE-2, canvases | core/widgets/scrim.dart (new) | inline gradients (onboarding 531, home 435/499, before_after) | top/bottom gradient presets | Low |
| Ambient backdrop | Fill letterbox voids with blurred image | Reveal, Cinematic, Canvas | core/widgets/ambient_backdrop.dart (new) | raw black bands (before_after_screen 154-172) | blurred darkened copy behind fitted image | Med (perf) |
| AtmosphereCard V2 | One image-led atmosphere card | FTUE-3, Session, Reveal strip, Re-upload | rewrite atmosphere_card.dart; _CustomAtmosphereCard folds in | current AtmosphereCard, _CustomAtmosphereCard | full-bleed photo, name over image (token type), no icon badge, no shadow, light/dark + compact/editorial variants, selected = inset accent border | Med (4-screen reuse) |
| RevealHero | One before/after slider | Home, FTUE-1, Reveal | shared/widgets/reveal_hero.dart (new) | _RevealSlide (onb), _HeroSlide/_CompareHandle (home), _CompareView (reveal) | drag + auto-sweep, fraction, handle, labels via AppPill, shadowless | Med (interaction parity) |
| RevealCanvas | Immersive reveal surface | Reveal, Cinematic Viewer | shared/widgets/reveal_canvas.dart (new) | before_after_screen body Column | RevealHero + ambient backdrop + scrim + breathe-beat sheet (controls overlay, not sibling) | Med |
| GenerationCanvas | Result-dominant chat surface | Chat | features/chat/generation_canvas.dart (new) | _ImageResultBubble + _GeneratedImageCard as chat items | latest vision full-bleed; conversation = draggable overlay/sheet; loading = source photo + 4.9.1b phase layer | High |
| DesignDirectionSelector | One room+atmosphere+source selector | Upload, Re-upload | features/shared/design_direction_selector.dart (new) | duplicate logic in upload_screen + _SourcePhotoSheet | source row + room chips + AtmosphereCard V2 grid + StickyActionBar; optional currentVision slot | Med |

## 3. Refactor Dependency Graph

Design-System Spine (typography, radius, AppPill, AppButton+Sticky, dots, scrim, ambient, AppAdaptive ext) — zero nav/state/backend — unblocks:

- AtmosphereCard V2 -> FTUE-3 (4.2), New Design Session (4.3), Reveal strip (4.5), Re-upload (4.6)
- RevealHero -> Home hero (4.1), FTUE-1 (4.2), Reveal (4.5) -> RevealCanvas -> Cinematic Viewer (4.4)
- StickyActionBar -> Home CTA (4.1), Re-upload CTA (4.6), Upload (already correct -> adopt)
- DesignDirectionSelector -> New Design Session (4.3) + Re-upload (4.6) [needs AtmosphereCard V2]

GenerationCanvas (4.11) requires RevealHero + RevealCanvas + 4.9.1b phase engine + spine — BUILT LAST.
Wave 4.7 (version/continuity data surfacing) is independent of the spine; interleave after 4.6.

Build-before rule (must hold): Spine -> AtmosphereCard V2 -> RevealHero -> RevealCanvas -> GenerationCanvas. DesignDirectionSelector after AtmosphereCard V2. Nothing structural starts before the spine.

## 4. Wave-by-Wave Execution Plan

Wave 4.2 — FTUE Premium Rework. Scope: adopt spine + AtmosphereCard V2 + RevealHero in onboarding_screen.dart; swap FTUE-1 mismatched assets (same-room before/after) and FTUE-2 exterior asset; hero full-bleed; single skip; brand wordmark token. Must not change: PageView routing, context.go('/home'). Acceptance: image >=52% viewport; before/after reads same room; one skip; no overflow >=568pt. Manual: SE-to-Max, single skip, asset continuity.

Wave 4.3 — New Design Session V2. Scope: upload_screen.dart adopts DesignDirectionSelector + AtmosphereCard V2; redesign _UploadZone; progress scaffolding; real disabled-CTA + hint. Must not change: context.pushReplacement('/chat/new?...') query contract, image picker. Acceptance: one type system; custom tile = same shell; CTA reachable. Manual: pick photo/room/atmosphere, disabled-to-enabled, camera+gallery.

Wave 4.1 — Homepage UX Optimization. Scope: home_screen.dart hierarchy re-rank (image-led), RevealHero for _HeroCarousel/_HeroSlide, StickyActionBar for CTA (shell-aware, above MainShell nav), kill _SessionsBadge sparkle / fake _CategoryPill, redesign _ContinueCard (larger thumb, suppress "0 visions", real title). Must not change: sessionProvider reads, context.push routes, _latestVisionUrl. Acceptance: hero is visual lead; CTA never below fold with nav present. Manual: short/tall, scroll, tap Continue, empty-sessions.

Wave 4.5 — Hybrid Reveal System V2 + Wave 4.4 — Fullscreen Cinematic Viewer (designed together). Scope: before_after_screen.dart -> RevealCanvas (fill + AmbientBackdrop, no letterbox), breathe-beat sheet, title scrim, dark AtmosphereCard V2 strip; unify _CompareView -> RevealHero; 4.4 = same surface, fullscreen entry. Must not change: 4.8.3 source-resolution + null/empty fallback + _loadImageAspectRatio; context.pop(_selectedAtmosphere) return contract. Acceptance: no black bands; climax breathes before controls; title legible on bright renders. Manual: landscape+portrait renders, bright-render title, select-to-Generate returns correctly.

Wave 4.6 — Re-upload Experience Consistency. Scope: _SourcePhotoSheet -> shared DesignDirectionSelector + StickyActionBar; single room taxonomy (drop local _roomTypes const -> l10n); show current-vision context; camera+gallery parity. Must not change: onDirectionChanged setState contract, _replaceSourcePhoto file-pick + MessageType.system insert. Acceptance: CTA pinned; same selector as 4.3; current vision shown. Manual: change room/atmosphere, replace photo (camera+gallery), apply, generate uses new direction.

Wave 4.9 — Generation UX Stabilization. Scope: cinematic wait (source photo + 4.9.1b phase layer instead of empty thread), fix loading-phrase transition artifact (_LoadingBubble AnimatedSwitcher stacking), resolve dual generate affordances, make Save real or remove (Chat + Reveal no-op). Must not change: 4.9.1b '<iter>|<style>' encoding + parse, 4.9.3b accumulation, GenerationService calls, _longGenerationTimer/poll. Acceptance: no empty void; no double-text artifact; one generate path; Save honest. Manual: V1 60-90s wait, transitions, Save behavior.

Wave 4.11 — Hybrid Conversational Rendering (LAST, highest risk, feature-flagged). Scope: GenerationCanvas — latest vision dominant/full-bleed; message list -> dismissible overlay/sheet; loading = canvas state; result flows into RevealCanvas. Must not change (critical): GenerationService/payloads, /generate+/chat contracts, message_model shape, _loadMessages session restore, 4.8.3 reveal-source, 4.9.3b accumulation, Supabase persistence. Acceptance: image dominant; chat secondary & non-destructive; session restore identical; backend bytes unchanged. Manual: full E2E (new->V1->refine->V2->reveal->re-upload->kill app->restore).

Wave 4.7 — Version Branching & Design Evolution: data-surfacing (real titles, no "0 visions", re-direction = visible branch). Independent of spine; interleave after 4.6.
Wave 4.8 / Wave 4.10: unchanged, later; no spine dependency.

## 5. Incremental Migration Strategy

1. Spine PR first — additive only (new tokens/widgets, no call-site changes). Nothing breaks; old widgets still compile.
2. Adopt per leaf component, one screen at a time. AtmosphereCard V2 rolled out FTUE-3 -> Upload -> Reveal strip -> Re-upload across separate PRs; old AtmosphereCard kept until last consumer migrated, then deleted in a cleanup PR.
3. Feature-flag the two high-risk surfaces (RevealCanvas, GenerationCanvas): build alongside the old path, switch via a const flag, validate, then remove the old path. Never delete _ImageResultBubble until the canvas passes full E2E + session-restore.
4. One wave -> validate -> next. Each wave is independently shippable and reversible (branch per wave; backend already tagged/frozen).
5. Backend invariants are guardrails on every PR: no edits under data/services/, core/providers/session_provider.dart, no change to generation_service.dart request shape, route query contracts, context.pop(atmosphere) return, message_model.dart, loading '<iter>|<style>' encoding, 4.8.3/4.9.3b logic.
6. Old widgets stay until proven replaced; deletion is a deliberate final step per component.

## 6. Exact File Refactor Map

| File | Current problem | Target responsibility | Modify | Delete/merge | Consumes |
|---|---|---|---|---|---|
| core/theme/app_theme.dart | Inter-only; no atmosphere/display token | own all type tokens incl. displayEditorial, atmosphereTitle | add tokens, font asset | - | - |
| core/constants/app_spacing.dart | 12/16/32/50 ad-hoc | one radius language | add radiusHero, rationalize | - | - |
| core/constants/app_colors.dart | strength - keep | unchanged | none | - | - |
| core/layout/adaptive_layout.dart | no canvas/hero tokens | extend (don't replace) | add homeHeroHeight, revealCanvas* | - | - |
| shared/widgets/app_button.dart | bypassed by 3 ad-hoc CTAs | sole CTA system | add onImage/dark variant | absorb _DarkButton, _CardAction, raw ElevatedButtons | spine |
| shared/widgets/atmosphere_card.dart | Lato!=Inter, icon badge, shadow, truncation | image-led, token-typed, variants | rewrite -> V2 | merge _CustomAtmosphereCard | typography token, AppAdaptive |
| shared/widgets/project_card.dart (read JIT) | likely Home/history card dup | use shared card shell | align to V2 shell | - | spine |
| shared/widgets/main_shell.dart | nav z-order vs Home sticky CTA | host shell-aware sticky region | verify only | - | - |
| features/onboarding/onboarding_screen.dart | boxed hero, mismatched assets, dup slider/pills/dots | thin screen over shared surfaces | adopt RevealHero/AtmosphereCardV2/AppPill/AppDots | delete _RevealSlide, _OverlayPill, _Dot slider/handle | RevealHero, AtmosphereCard V2, spine |
| features/home/home_screen.dart | text>image, CTA below fold, sparkle badge, fake pills, dup slider | image-led shell | re-rank, RevealHero, StickyActionBar | delete _HeroSlide, _CompareHandle, _SlideLabel, _CategoryPill, _SessionsBadge, _HeroProgressDot | RevealHero, AppPill, AppDots, StickyActionBar |
| features/upload/upload_screen.dart | dup selector; generic dropzone | host DesignDirectionSelector | extract selector | _StyleGrid, _GroupedRoomSelector, _Chip, _CustomAtmosphereCard -> selector | DesignDirectionSelector, AtmosphereCard V2 |
| features/result/before_after_screen.dart | letterbox, light strip on dark, no scrim, dup slider | thin screen over RevealCanvas | replace body | delete _CompareView, _DarkButton | RevealCanvas, RevealHero, AtmosphereCard V2 (dark) |
| features/chat/chat_screen.dart | result = chat attachment; empty wait; dup sheet | host GenerationCanvas + conversation overlay | invert (4.11), stabilize (4.9), share selector (4.6) | _ImageResultBubble, _GeneratedImageCard, _CardAction, _SourcePhotoSheet dup logic | GenerationCanvas, RevealCanvas, DesignDirectionSelector, spine |
| features/generation/generation_loading_screen.dart (read JIT) | possibly orphaned vs in-chat loading | consolidate cinematic wait | reconcile w/ 4.9.1b phase engine | possibly merge into canvas wait | phase engine |

## 7. Risk Register

| Risk | Where | Mitigation |
|---|---|---|
| Visual regression on shared adoption | every migrated screen | feature-flag high-risk; per-screen visual diff vs audit screenshots |
| Slider gesture vs PageView/sheet drag conflict | FTUE-1, Re-upload | RevealHero exposes onDragStart to stop parent; test nested-gesture explicitly |
| Image sizing / ambient backdrop perf | Reveal, Canvas, large renders | downsample backdrop; cacheWidth; profile low-end device before removing old path |
| Safe-area / sticky CTA vs MainShell nav | Home (in shell) vs pushed routes | StickyActionBar shell-aware; test both topologies |
| Scroll/state loss on canvas inversion | Wave 4.11 | keep ListView source of truth; canvas reads same message list; flag + full restore test |
| Session/history regression | 4.6, 4.9, 4.11 | never touch _loadMessages/session_provider/message_model; E2E kill-and-restore per wave |
| Backend contract drift | 4.3 route query, 4.5/4.6 pop value, 4.9 loading encoding | enumerated as must-not-change; PR checklist rejects edits to those symbols |
| Real-device viewport (SE to Max, notch) | all | AppAdaptive tiers already exist; validate at 568/667/812/Max each wave |
| Font asset load (editorial face) | spine | bundle locally (no network), fallback to Inter; verify Khmer fallback chain intact |
| Navigation regression | 4.1/4.3/4.6 | app_router.dart unchanged; only widget internals change, not routes |

## 8. Validation Checklist (per wave)

Run for every wave before the next: iPhone SE-568 / 667 / 812 / Max viewports; light & dark surfaces (Reveal/Canvas dark); generation in progress (60-90s); generated result; reveal drag + auto-sweep; atmosphere switch (and return value); re-upload (camera+gallery); kill app -> session restore identical; no vertical/horizontal overflow; no CTA below fold / hidden by nav; no fake/no-op Save remaining; no double-text/transition artifact; backend payload unchanged (network log diff vs freeze); flutter analyze clean.

## 9. Recommended Implementation Order

(Honest: this re-sequences delivery vs the numeric order; wave names/numbers unchanged — only execution order differs, which the roadmap permits.)

1. Design-System Spine (typography incl. editorial+atmosphereTitle, radius, AppPill, AppButton+StickyActionBar, AppDots, scrim, ambient, AppAdaptive ext) — additive, zero nav/state/backend.
2. AtmosphereCard V2 (consumes spine) — lands FTUE-3, Upload, Reveal-strip, Re-upload presentation at once.
3. RevealHero then RevealCanvas (consume spine).
4. Wave 4.2 — FTUE Premium Rework + Wave 4.3 — New Design Session V2 (adopt V2 card/RevealHero/selector; FTUE asset swap).
5. Wave 4.1 — Homepage UX Optimization (RevealHero + StickyActionBar + Continue redesign).
6. Wave 4.5 — Hybrid Reveal System V2 + Wave 4.4 — Fullscreen Cinematic Viewer (RevealCanvas: fill/ambient/scrim/breathe).
7. Wave 4.6 — Re-upload Experience Consistency (shared DesignDirectionSelector + continuity context).
8. Wave 4.9 — Generation UX Stabilization (cinematic wait, transition fix, honest Save, single CTA path).
9. Wave 4.11 — Hybrid Conversational Rendering (GenerationCanvas, flagged, last).
10. Wave 4.7 — Version Branching & Design Evolution (continuity data; interleavable after 4.6). Wave 4.8 / Wave 4.10 later.

## 10. Final Decision Table

| Component / Wave | Priority | Risk | Key files | Expected premium impact |
|---|---|---|---|---|
| Design-System Spine | P0 (first) | Low | app_theme, app_spacing, app_button, +new primitives | High — fixes Inter/Lato + CTA + pill incoherence app-wide |
| AtmosphereCard V2 | P0 | Med | atmosphere_card.dart | High — 4 screens, signature component |
| RevealHero / RevealCanvas | P0 | Med | reveal_hero/canvas (new) | High — unifies core interaction; enables image dominance |
| Wave 4.2 FTUE | P0 | Med | onboarding_screen.dart | High — first impression + asset continuity |
| Wave 4.3 New Design Session | P0 | Med | upload_screen.dart | High — core mechanic screen |
| Wave 4.1 Homepage | P0 | Med | home_screen.dart, main_shell | High — sets tone; fixes below-fold CTA |
| Wave 4.5+4.4 Reveal/Cinematic | P0 | Med | before_after_screen.dart | Highest emotional — fixes letterboxed climax |
| Wave 4.6 Re-upload | P1 | Med | chat_screen.dart (_SourcePhotoSheet) | Med-High — continuity restored |
| Wave 4.9 Gen Stabilization | P1 | Low-Med | chat_screen.dart, generation_loading | Med — cinematic wait, honest Save |
| Wave 4.11 Hybrid Conv. Rendering | P0-impact / last | High | chat_screen.dart + generation_canvas (new) | Highest structural — resolves core thesis |
| Wave 4.7 Version/Evolution | P1 | Low | project/session surfacing | Med |

## What should we implement first?

The Design-System Spine + AtmosphereCard V2, as one foundational change-set (two PRs: spine, then card).

It is the highest premium-impact-per-unit-risk action available: it touches zero navigation, state, routing, or backend code (backend stays frozen), it is purely additive then a contained component swap, and it immediately lifts premium perception on 4 of 8 screens (FTUE-3, New Design Session, Reveal strip, Re-upload) by killing the worst defect (Lato/Inter fracture + icon-badge/shadow) and the app-wide CTA/pill incoherence. It also de-risks every subsequent wave by giving them stable shared primitives. The high-impact/high-risk chat inversion (4.11) stays last, behind a flag, after the spine and reveal surfaces have proven themselves.
