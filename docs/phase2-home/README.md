# Phase 2 — Home parity

Preview: <https://ayden-studio--phase2-home-zvw4fq0e.web.app> (expires 2026-09-03)
Live staging still serves the archived design.

| file | state |
|---|---|
| `before-home-firsttime.png` | archived Home, no history |
| `before-home-with-history.png` | archived Home, with history — dark, three competing blocks |
| `after-home-firsttime-en.png` | **first-time**: showcase hero, English |
| `after-home-firsttime-fr.png` | first-time, French |
| `after-home-returning-en.png` | **returning**: the person's OWN before/after |
| `after-home-returning-km.png` | returning, Khmer |

---

## iOS reference vs PWA Home

| | iOS `home_screen.dart` | PWA before | PWA now |
|---|---|---|---|
| canvas | `#F9F6F1` | `#0B0B0C` | **`#F9F6F1`** |
| top spacing | `pagePadding` / `sm` | 64px dark bar | **24 / 8, no bar** |
| wordmark | uppercase, 11, w600, ls 2.0, secondary | 14 w600 on dark | 16 w600 ink (see note) |
| headline | `displayEditorial(27, w500, 1.12, −0.4)` | sans, 2 CTAs inside a stock hero | **identical role** |
| hero height | `h × 0.45`, clamp 260–460 | fixed video block | **identical** |
| hero radius | `radiusHero` 24 | 22 | **24** |
| compare | `RevealHero`, `initialFraction 0.30`, `dragMode: handle` | none on Home | **the same widget, same params** |
| labels | `Original` / style | — | **`Original` / atmosphere** |
| overlay | eyebrow + `atmosphereTitle(19, w600, white)` | — | **identical** |
| CTA | sticky `New Design Session`, pill | 3 competing CTAs | **one sticky pill** |
| bottom nav | white, hairline, Home/Projects/Profile | none | **identical** |
| vertical rhythm | headline → hero → CTA → nav | headline → hero → grid → block | **headline → hero → CTA → nav** |

**Wordmark note.** iOS renders it as a small uppercase tracked label because its
header also carries a Premium pill and an intro-replay icon competing for the
row. The PWA header carries a language switcher and an identity chip instead, so
the wordmark is the row's anchor and is set at `cardTitle`. Perceived hierarchy
matches; the literal type role does not. Flagged rather than silently copied.

---

## The one deliberate divergence: real user data

iOS fills its hero from `featuredShowcase` — a curated list, the same three
rooms for everyone. The brief requires the web to use real history, and it is
the better product: a returning customer sees the room they were working on.

```
featured = state.visibleProjects.first        // deduped, most recent first
vision   = project.coverVision                // guaranteed non-null by visibleProjects
before   = pwaBeforeImage(source, descriptor, vision:, versions:)   // lineage-aware
after    = pwaAfterImage(vision)
caption  = "<roomLabel> · <atmosphereLabel>"
tap      → controller.openProject(projectId)  → the design session
```

`visibleProjects` already guarantees *at least one vision AND a project-owned
cover*, so no new state, provider or endpoint was needed, and Home cannot
disagree with Projects about what exists.

First-time visitors fall back to `featuredShowcase` — the **same** list iOS
uses, genuine before/after pairs with real room and style labels.

---

## What was removed, and why it is a fix

The old Home had three competing blocks: a stock hero with two CTAs, a
"Continue designing" grid, and a second full-width "New project" panel. Two said
the same thing and the third duplicated Projects.

The Featured Vision *is* the continuation now — tapping it reopens that project
— and Projects is a permanent nav destination rather than a "See all" link that
only existed when history did. That is also what makes the iOS rhythm reachable:
on a 390×844 phone the CTA is visible without scrolling.

---

## Safari / installed PWA

* Sticky CTA uses `PwaStickyFooter` → `max(viewInsets, viewPadding)`, so it
  clears the home indicator and rises with the keyboard without doubling.
* The nav owns the bottom inset (`PwaScreen(bottom: false)`), so the two never
  add up.
* No `100vh` anywhere — the hero is derived from `MediaQuery.sizeOf`.
* `dragMode: RevealDragMode.handle` — **only the handle strip takes the drag**,
  which is iOS's own choice and the reason the compare does not fight page
  scroll on a touch screen.
