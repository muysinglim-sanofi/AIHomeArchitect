# Phase 7 — Projects

Preview: <https://ayden-studio--phase7-projects-i0d4siiq.web.app> (expires 2026-09-04)
Live staging and the Phase 1–6 previews are all **untouched** — verified, see
"The deploy log says something alarming" below.

| file | target | what it shows |
|---|---|---|
| `01-projects-fr.png` | **staging** | the screen, French, one real generation made through this build |
| `02-projects-km.png` | **staging** | the same project in Khmer |
| `03-home-km.png` | **staging** | Home, same project, same Khmer room name |
| `04-projects-desktop-km.png` | **staging** | 1440 — a bounded, centred column |
| `05-projects-tablet-km.png` | **staging** | 768 — two columns |
| `06-projects-empty-fr.png` | **staging** | a visitor with no work yet |
| `07-projects-mock-fr.png` | mock | five projects, 1–4 visions each |
| `08-projects-mock-desktop.png` | mock | 1440 — four columns of work |
| `09-home-mock-fr.png` | mock | Home over the same five projects |

**On the two targets.** `01`–`06` are the deployed staging build against the
public staging backend, with a real generation performed through it (upload →
Master Bedroom → Warm Modern → render). `07`–`09` are the local **mock** build,
and they are here for one reason: a staging guest gets **one** free vision, and
this one was spent on `01`. A portfolio screen has to be shown holding a
portfolio, and the alternative was to buy Spaces. The mock target is the
development fixture — five projects with real bundled imagery — and it is
labelled as such in every row above.

---

## What it was, and what it is

```
Redesigns                          Redesigns
[ search field............ ]       3 redesigns
[ Sort ▾ ]  3 projects found       ┌────────┐ ┌────────┐
┌──────────────┐                   │ ▓ 3 vis│ │ ▓ 2 vis│
│  thumbnail   │                   │        │ │        │
│ Living Room Concept          │   │ picture│ │ picture│
│ Living Room · Ayden Signature│   │ Salon  │ │ Cuisine│
│ 3 visions · Updated today    │   │ Ayden S│ │ Warm M │
└──────────────┘                   │ aujourd│ │ 3 jours│
                                   └────────┘ └────────┘
```

The old screen was a project database: a search field, a sort menu, a
"3 projects found for …" context row, a Clear-search control, a separate
search-empty state, and under each thumbnail two dense metadata lines. The new
one is iOS's: a title, a count, a grid of covers, one button.

---

## Measured against iOS

`lib/features/history/projects_history_screen.dart` and
`lib/shared/widgets/project_card.dart` (CHANTIER D).

| | iOS | PWA before | PWA now |
|---|---|---|---|
| title | `historyTitle`, `headlineLarge` (Inter 26/w600/−0.3) | eyebrow + display face | **iOS's role, `PwaType.screenTitle`** |
| subtitle | `'{n} {transformations}'`, `bodyMedium` | "3 projects found for …" | **iOS's line** |
| controls | none | search + sort + clear | **none** — see below |
| grid | 2 columns, gap 8, ratio 0.72 | 1–4 cols, own ratio | **0.72, gap 8; 2/3/4 by width** |
| card | cover full-bleed, no surface | image + white text block | **cover full-bleed** |
| scrim | `#E60C0906 → transparent`, `end: Alignment(0,-0.05)` | flat 45% black | **iOS's gradient, exactly** |
| title on card | room, localized, 15/w600/+0.1 | stored project title | **room, localized** |
| second line | atmosphere, 12 | "Room · Atmosphere" | **atmosphere alone** |
| third line | updated-ago, 11 | "3 visions · Updated today" | **updated-ago alone** |
| visions | chip, top-left 9/9 | in the metadata line | **chip, 9/9** |
| menu | `more_horiz`, bottom 4 / right 2 | 60% until hover | **always legible** |
| CTA | `newProject` under the grid | FAB + tooltip | **under the grid** |
| empty | `noProjects` + one button | search-empty + library-empty | **one calm state** |

### Search and sort are gone — and the state is not

iOS's Projects has neither control, and the brief names "a dense project
database" as the thing to avoid, so both surfaces went. `librarySearch` and
`librarySort` are untouched in the controller, still filter and order
`visibleProjects`, and are still under test (`pwa_projects_polish_test.dart`,
"search and sort survive as state"). Putting a field back is a few lines. This
is the one intentional removal in this phase and it is flagged for approval.

---

## Nothing underneath moved

* **Which projects, in what order** — `state.visibleProjects`, the same list
  Home reads. The screen does not filter, sort or hide anything.
* **Which image is a project's cover** — `PwaProjectSnapshot.coverVision`
  (`coverVisionId ?? currentVisionId ?? visions.last`) → `pwaAfterImage`. A test
  renders **Home and Projects from one container** and compares the
  `versionId` each shows, because "reuse the canonical resolver" is exactly the
  instruction a rewrite drifts away from.
* **Tapping a project** → `controller.openProject(projectId)`, the route that
  already existed. It generates nothing, creates no duplicate, and a test
  asserts the project count and vision count are identical after the tap.
* **Delete / rename** → the same `PwaProjectCardMenu`, promoted from private to
  public and given an `onDark` flag. Its actions are byte-identical.
* **The empty state's button** → `controller.newProject()`, the same entry Home
  uses.

---

## Four defects found by looking at it

All four were found on the staging preview, in a browser, after the widget
tests were green. Each now has a test.

**1. A Khmer reader was shown "Living Room".** `room_type` is canonical English
on purpose — it keys the prompt engine's DNA and is routed, never translated —
so the localisation has to happen at display time. iOS has done this for years
in `ProjectCard` via `RoomTypeImages.displayLabel`. The PWA never did, on Home
either. There is now one resolver, `pwaRoomDisplayLabel`, in `pwa_widgets.dart`
next to the image resolvers, and **both screens call it**, so they cannot
disagree about the same project in front of the same reader. Nothing stored,
routed or compared changed. `03-home-km.png` and `02-projects-km.png` are the
same project, same word: **បន្ទប់គេងធំ**.

**2. "Updated 4 minutes ago" under a French interface.**
`PwaL10n.updatedLabelFor` localises the *timestamp* and falls back to the
stored English sentence only when there is none — and `_activeSnapshot` was
rebuilding the open project **without carrying `updatedAt` over**, so the
fallback was what every reader got. The rebuild now keeps it (`now` when the
write is the one bumping the freshness, the previous value otherwise).

  This is the one change in this phase that is not presentation, and it is
  disclosed deliberately: `PwaProject.sortedBy(recentlyUpdated)` prefers the
  database timestamp when *both* sides have one, so filling in a value that used
  to be null could in principle reshuffle a library. It does not — the bumped
  project carries both the newest timestamp and the highest counter, and the two
  agree — and a test pins the ordering as unchanged.

**3. On a 1440 window the header sat against the left edge and the button ran
the full width of the monitor.** The max-width constant existed and nothing read
it. Projects now uses the product's own `pwaMaxContentWidth`, so it widens
exactly as far as the rest of the web app and no further, and columns are
counted from the **bounded** width — the ceiling decides the layout instead of
clipping it. Phone geometry is unchanged (full bleed).

**4. The three-dot menu sat at 60% opacity until the pointer entered the card.**
That was safe on the old dark card. The Phase 7 card is the person's own render,
and dimming a control to 60% over a photograph nobody chose is the same contrast
bet this alignment has been removing everywhere. It is always legible now.

A fifth, in the development fixture: the five mock projects carried an English
`updatedLabel` and no timestamp, so the mock target went down the same fallback
path. They carry real ages now, which also means the widget suite exercises the
localised path rather than the fallback.

---

## Observed, not fixed

**"1 redesigns".** The count line is `'{n} {transformations}'` and there is no
singular form; iOS prints the same thing. `historyTitle` / `transformations`
live in `lib/core/l10n`, the frozen mobile dictionary, and inventing a PWA-only
plural rule for three languages would make the two products disagree about their
own vocabulary. Reported rather than patched. (French says "Redesigns" by
design, not by omission — the approved FR dictionary uses the loanword
throughout: "Redesigns récents", "Dernier redesign", "Votre redesign".)

**A refused generation is replayed forever.** After the staging guest's free
vision was spent, every cold start of the app restored the design session AND
re-raised both the paywall and the generic "Une erreur s'est produite"
banner — dismiss either and it comes back on the next load. The cause is in
`localStorage`: `flutter.pwa_pending_generation_v1` survives a billing refusal
and is replayed on boot. This is the paywall/error-banner duplication reported
since Phase 4, with a root cause attached. Out of scope here; it belongs to the
final billing polish, and it is the most user-visible thing left on this app.

**The web paywall still lists app-store products** ("Disponible dans
l'application mobile", $7.99 / 7 jours, $79.99 / 365 jours). Reported since
Phase 4.

**Home is not bounded on a desktop window** — its hero runs the full 1440 while
Projects now stops at 1360. Phase 2's surface; an 80px difference at this width,
larger on a 1920 monitor.

**Long room names ellipsise on a phone card** ("Chambre prin…"). iOS does the
same (`maxLines: 1`), and the full name is on the project itself; kept as
parity rather than changed unilaterally.

---

## No iOS screenshot

The mobile app is frozen under Apple review and this work never builds or runs
it. The comparison above is measured from the iOS source — the widths, the
gradient stops, the type roles and the positions are quoted from
`projects_history_screen.dart` and `project_card.dart` rather than eyeballed
from a photograph.

---

## Gate

* `flutter test` — **1211 passed, 0 failed** (was 1183 before the phase: +32 new
  Projects parity tests, minus the retired search/sort surface tests, plus the
  migrations).
* `flutter analyze` — 2 issues, both pre-existing `info` lints in
  `pwa_i18n_test.dart` (lines 622, 654), a file this phase does not touch.
* `tool/build_pwa.sh staging` — clean; "stripped 1 dotenv file from the bundle".
* `backend/pwa_secret_scan.py` — **PASS 10, LEAKS 0**. ABA key in git / bundle /
  logs: NO. dotenv in bundle: NO.
* Deployed to the **phase7-projects** channel only.

### The deploy log says something alarming

`firebase hosting:channel:deploy` prints a generic block —
`=== Deploying to 'ayden-studio' … release complete … Hosting URL:
https://ayden-studio.web.app` — before it prints the channel URL. It reads
exactly like a production deploy. It is not one, and that was verified rather
than assumed: the bundle served at `ayden-studio.web.app` does not contain this
build (`pwa-projects-new` absent, `pwa-sort-sheet` still present — it is a
pre-Phase-7 build), and `firebase hosting:channel:list` shows only
`phase7-projects` with a release time from this session. Worth knowing before
someone reads that line in a future log and panics.

---

## Driving the browser

`cdp.mjs` grew four commands this phase, all documented in the file:

* `upload` — intercepts the file chooser (`Page.setInterceptFileChooserDialog`
  → `Page.fileChooserOpened` → `DOM.setFileInputFiles`) so a real photograph
  goes through `image_picker`'s real input.
* `swipe` — touch events. `wheel` never returns against this CanvasKit surface
  and a *mouse* drag does not scroll a `Scrollable` on any platform. Needs
  `Page.bringToFront` first: an occluded tab never acks an input event, so the
  call hangs instead of failing.
* `lang` — sets `acceptLanguage`. Kept, but **it does not work**: this Chrome
  leaves `navigator.language` alone, which is what Flutter reads. The in-app
  switcher was used instead.
* `carry` — moves a staging session between preview origins (each channel is
  its own origin, so its own empty storage, so its own brand-new anonymous
  user). Key names are logged; values never are.

Also worth recording: a full-page capture is far easier than scrolling — set
the viewport to `390×2200@1`, and the whole four-step Create page is visible and
clickable at once.
