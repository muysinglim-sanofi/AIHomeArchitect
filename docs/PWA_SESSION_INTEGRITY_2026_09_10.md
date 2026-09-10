# AYDEN STUDIO PWA — SESSION / VISION INTEGRITY PASS — 2026-09-10

Scope: PREPROD / STAGING only. Production, production Supabase, ABA PayWay,
payment credentials, Billing semantics, Wallet, grants, RevenueCat, the
Supabase identity model, the Facebook OAuth architecture and the native iOS
sources (`frontend/`) were **not modified**.

| | |
|---|---|
| Backend | `ayden-api-staging` (Fly, sin) — deployed 2026-09-10, both machines healthy, `/health` 200 |
| Client | `preprod.aydenstudio.com` — deployed; live `main.dart.js` sha256 `5cc98ccb305146e0…` **= local build** |
| Flutter | `flutter analyze`: no issues · `flutter test test/features/pwa`: **1221 passed, 0 failed** |
| Backend offline suites | adapter 278/0 · billing 81/0 · billing contract OK · **new** vision ordinal 17/17 · orientation OK |

---

## 1. P0 — SESSION / VISION LINEAGE

### 1.1 The incident, from the staging database (read-only, preserved)

Owner `253f7fa6…` (Mike Lim). All rows below are still in place — nothing was
repaired, deleted or rewritten, so the evidence survives this pass.

| Time (UTC) | Row | What it shows |
|---|---|---|
| 16:40:05 | project `440a715e` V1 `77e40370` | the real project, its own photo `users/253f…/projects/440a715e…/original/ba785e61….jpg` |
| 16:40:41 | claim `99f9ccf8` | the Soft Luxury switch starts (HOLD −1) |
| 16:41:04 | V2 `7c27a0e3` in `440a715e` | the switch **finished server-side, in the right project** (COMMIT 16:41:05) |
| — | `440a715e` messages: `generation_status=1, text=1, vision_result=1` | the navigation stored the **loading bubble** as a row (the zombie spinner); V2 never got its reveal |
| 16:41:11 | project `c0ee05e9`, `original=assets/showcase/apartment_before.jpg`, 0 visions | the render came back into the **fresh Create** on screen: a project nobody made, with the showcase condo as its "original" |
| 16:42:51 | claim `ac4c6cb8`, parent V1 | the reopened stale copy (V1 + spinner) switched again, asking for `vision_number = 2` |
| 16:43:15 | claim `ac4c6cb8` COMPLETED → `result_vision_id = b7fe1dea` — **no such vision** | `UNIQUE (project_id, vision_number)` refused the row; the refusal was handled as a transport failure: image returned, claim settled, **HOLD 16:42:51 → COMMIT 16:43:15: one Space committed for a vision that exists nowhere** |
| later | switches with parent `b7fe1dea` | refused `PARENT_FORBIDDEN` **before** the claim (no charge) → "Something went wrong" + repeated user bubbles |

Every other claim of this owner maps 1:1 to a real vision and one HOLD/COMMIT
(11 claims, 11 holds). The only billing defect is the one Space of `ac4c6cb8`.
**It was not refunded** — that is a Billing action and is left to the owner.

### 1.2 Root causes (proven in code)

1. **A generation had no owner.** `applyAtmosphere` / `applyRefine` /
   `generateFirstVision` awaited the render and then wrote into *whatever
   session was on screen*: `returnToStudio → _freshSession` had replaced it with
   a new draft whose placeholder original is the showcase condo, and
   `_commitNewVision` + `_syncActiveProject` persisted that draft as project
   `c0ee05e9` with the switch as its "Vision 1".
2. **The loading bubble was persisted.** Every navigation save serialised the
   `loading` message as a `generation_status` row, and a load restored it as a
   spinner no answer could ever replace.
3. **The client owned the ordinal** (`state.versions.length + 1`). A stale copy
   asked for a taken number; the backend's 409 branch only recognised a
   *key* twin, and fell through to "row not persisted" — COMPLETED, charged,
   `persisted: False` — for a vision that was never written.
4. **Message order was the in-memory index**, recomputed on each save and
   compared as an immutable column. Removing a bubble from the middle shifted
   later messages; the next save declared a divergence and threw *after* the
   project row had been bumped — `440a715e` is at revision 7 with 3 messages.
5. **After the upload `await`, `_pendingFor` and `_prepareOriginal` read
   `state`**: someone who navigated during the upload sent project B's id/room
   with project A's photo, and wrote A's photo path into B's session.
6. **The idempotency key survived a failure** and was handed to the next
   generation whatever it was.

### 1.3 The 16 lifecycle points — before → now

| # | Point | Before | Now |
|---|---|---|---|
| 1 | Tap / confirm | `generating` guard | unchanged, plus **one generation at a time across projects** (`BUSY_ELSEWHERE`) |
| 2 | User event | appended to the session | appended; **stored** on the next save (it is what the person did) |
| 3 | Idempotency key | `_activeGenerationKey ??= uuid` — reused by the next intent | **one key per intent** (action, project, parent, choice); a retry of the same intent reuses it |
| 4 | Ownership | none | `_GenerationJob{projectId, key, loading, request, base}` registered **before the first await** |
| 5 | Pending record | written before the POST; cleared unconditionally | written before the POST; **cleared / settled only if it is still this key** |
| 6 | Upload of the original | read `state` after the await | reads the **job**; writes the path into the session only if the owner is still on screen |
| 7 | POST `/generate` | project/room read from `state` after the upload | **the owner's**, captured at the start |
| 8 | Claim + HOLD | unchanged | unchanged (existing durable claim + ledger, no second system) |
| 9 | Ordinal | client's number stored as-is | **server's**: `max(vision_number)+1` read after the render |
| 10 | Insert 409 | key twin → replay; anything else → "not persisted", COMPLETED | key twin → replay; **number taken → re-read and retry** (3 offers); never a phantom |
| 11 | Response | client number echoed | **the stored number** echoed; `persisted:false` makes the vision client-owned (the client writes the row) |
| 12 | Landing | into whatever session is open | **into the owner**: on screen → the conversation; elsewhere → its working copy + durable save, nothing else touched |
| 13 | Failure | banner in whatever session is open | on screen → banner; elsewhere → record settled, **shown when that project is reopened** |
| 14 | Navigation saves | stored the loading bubble | **never** store a loading bubble; a load drops a legacy `generation_status` row |
| 15 | Reopen while running | fresh thread, `generating:false` (a 2nd render could start) | **its bubble and its wait come back**, `generating:true` |
| 16 | Reload / restore | recent record → re-POST; old → "couldn't complete" | **status first**: COMPLETED → adopt (no request) · PROCESSING → wait (poll, no POST) · FAILED → Retry offered · UNKNOWN → recent re-sent with its key, old reported |

Also: deleting a project or switching identity drops its job — a late result
can never resurrect a deleted project or land in another account's library; a
chat turn answered after the person left never renders in the project they
moved to.

---

## 2. P0 — WRONG ORIGINAL IMAGE

Isolation audit of every path that writes an original:

| Path | Defect | Fix |
|---|---|---|
| fresh draft (`createDraftProject`) | placeholder `assets/showcase/apartment_before.jpg` became a durable project's original through the ownerless landing | landing is owner-bound; and staging now **refuses to persist** a project with visions whose original is a bundle asset and which carries no photo bytes (logged `persist_refused_bundle_original`) |
| `_prepareOriginal` after the upload await | wrote A's durable path into B's session, and marked A's photo as B's persisted source (B's next save re-uploaded) | writes only if the owner is still the session on screen |
| `_pendingFor` after the upload await | B's id/room with A's photo | reads the job |
| first vision finishing after the person left | landed in the new session | lands in its own project with its own uploaded photo (LIN05) |

A/B/C matrix (LIN16): three projects with distinct photos; a switch started in
A; navigation A→B→C→Home→A (running bubble)→B; completion; then a reload from
the durable rows alone. At every checkpoint (memory, durable, after reload):
each project keeps its own original, every vision belongs to its project, A
has V1 and V2 (sequential), B and C one each, all ids unique, no loading row,
no extra project.

---

## 3. P0 — PENDING GENERATION TERMINATES

Exactly one terminal state per job, reached without a second render:
COMPLETED (landed once — a replay that answers with a vision already held adds
nothing, `_commitNewVision` dedupes by id), FAILED (settled record, Retry
offered, shown in its own project), or dropped (project deleted / identity
changed; the backend keeps what it made). Restore reconciles by asking the
backend about the key before anything else (§1.3 #16; LIN17–LIN20). Legacy
spinner rows are ignored on load (LIN22) and new messages are ordered after
every stored row, so they can no longer block appends (LIN23).

---

## 4. P0 — V4+ FAILURES

The "Something went wrong" after V3/V4 was **not an engine failure**: it was
`403 PARENT_FORBIDDEN` for the phantom `b7fe1dea` (pre-claim, nothing charged),
compounded by the message-order conflict that stopped the thread from being
stored. Fixed at the source (server ordinal, key-twin vs number-race, stable
order, owner-bound landing). PARENT_FORBIDDEN is now logged with both ids
(`vision b7fe1dea is not in project 33333333`), and client failures are logged
by code (`generation_failed code=… retryable=…`) instead of prose.

V1→V5 in one session (LIN15): ordinals 1..5, each parent the previous current,
5 distinct keys, one job and one reveal each, no pending left, no loading row,
one project, 5 durable visions. Backend end to end (ORD10–ORD15): a stale
number is stored under the server's, the answer carries it, a number race is
retried, never `persisted: False`.

---

## 5. IDEMPOTENCY

One selection = one user event, one request, one pending record, one hold.
Rapid taps start one switch (LIN12). A key is one intent (LIN13). A second
project waits for the first render instead of overwriting its pending record
(LIN14). Backend: our own key already stored → that row is the answer (ORD07);
a taken number → next number (ORD06); three offers then a typed answer that
names the number actually tried (ORD08/ORD09). Existing claim + ledger reused;
no new idempotency system.

---

## 6. P1 — FULL REVEAL SPACING

Phones get **28pt** between the toolbar and the canvas (was 12); a desktop
window keeps 12. On an installed iPhone the hero is bounded by what the rail
and the reserved action slot leave, so extra air taken from the hero would
have shrunk the canvas — and a portrait render with it. The **rail pays**: it
is at its 270 cap there and its cards are width-clamped (0.86 × screen), so it
gives 16pt of height (cards 335×221 → 335×208) and the canvas keeps its exact
size. Only what the rail can give above its 150 floor is taken.

| Viewport | Gap | Canvas | Rail |
|---|---|---|---|
| 390×797 (installed iPhone) | 12 → **28** | 277 → **277** | 270 → 254 |
| 390×664 (Safari with toolbars) | 12 → **28** | unchanged | 252 → 236 |
| 1440×900 | 12 → 12 | unchanged | 132 |

Proven for four phone sizes by REVEAL-SPACING-03 (pure geometry: canvas
before = canvas after); REVEAL-SPACING-01/02 measure the live widget tree at
390×844 and 1440×900 (V1/V2/V3 share one width). Screenshots before/after:
session scratchpad `QA/p0p1/`.

---

## 7. LIVE QA (preprod, build `5cc98ccb…`, staging DB read back)

Driven through CDP at 390×844, each run in a **fresh isolated browser
context** (a new guest with the free trial vision), photo
`backend/benchmarks/source/bedroom.jpg`. The browser's own session (guest A)
was left untouched. The staging machine runs through NordLynx; nothing here
needed a response longer than its 61 s cut.

| Run | What was done | Database afterwards (read-only) | Verdict |
|---|---|---|---|
| guest `3fb3380a` | Generate, then the whole Chrome process died (external; not the app) | draft `4d78c6ba` with its uploaded photo · **0 claims · 0 ledger rows** — the API log shows only the CORS preflight | nothing charged, nothing invented |
| guest `34ed52bc` | Generate → account menu → Home at 18:51:01 | project `179eb963`: own photo · V1 `ad88dfc3` 18:50:46 · messages `vision_result=1` (no `generation_status`) · 1 claim → existing vision · TRIAL +1 / HOLD −1 / COMMIT | clean, but the render beat the tap: landed while its session was on screen |
| guest `54c09d5b` | Generate → **Home 3.5 s later (18:53:29.97)** | project `0e6ada90`: own photo `users/54c0…/projects/0e6ada90…/original/62b6….jpg` · **V1 `bd1d0cb9` persisted 18:53:59, 30 s after the session was replaced** · messages `vision_result=1`, no `generation_status` · 1 claim → existing vision · one HOLD/COMMIT · **no other project** | **landed away, in its own project** |

Guest `54c09d5b`, on screen: Home right after leaving has no project section
(the fresh session did not become one); when the result arrived the "Continue
designing" card appeared by itself; the pending record was gone from
`localStorage` (terminal state reached, key cleared). Opening the card: "Vision
1 · Warm Modern" with its intro and no spinner; its Full Reveal's **Original is
this guest's own unfinished bedroom**; Projects reads "1 redesign". API log:
`18:53:59 [pwa-staging] vision bd1d0cb9 persisted for project 0e6ada90`,
`18:54:00 POST /pwa/staging/generate 200` — the answer reached a page that had
left the session 30 s earlier, and landed in the project that asked.

Not reproducible live without Spaces (guest trials are one vision; guest A's
balance is 0): V2+ switches with navigation, V1→V5, refine with a real image.
Those are covered by LIN01–LIN23 / ORD01–ORD17 and are the real-device
sequence in §9.

Console: every page load logs `google_fonts` "allowRuntimeFetching is false
but font … was not found in the application assets" as an uncaught async
error — a font variant requested without a bundled file. Pre-existing (seen on
guest A's untouched session too), not caused by this pass, no visible effect;
recorded for a follow-up.

---

## 8. TESTS

| Suite | Result |
|---|---|
| `flutter analyze` (lib/features/pwa, test/features/pwa) | no issues |
| `flutter test test/features/pwa` | **1221 passed** |
| new `pwa_session_integrity_test.dart` | LIN01–LIN23, all pass |
| `pwa_staging_adapter_test.py` | 278/0 |
| `pwa_staging_billing_test.py` | 81/0 |
| `pwa_staging_billing_contract_test.py` | OK |
| new `pwa_staging_vision_ordinal_test.py` | 17/17 |
| `pwa_staging_orientation_test.py` | ALL PASS |

Updated tests (and why): I18N18 documents the BUSY_ELSEWHERE fallback (the UI
renders it by code, translated en/fr/km); REVEAL-SPACING-01/02, CAN03 and
REVEAL10 follow the phone gap paid by the rail (card width assertion kept).

---

## 9. REAL-DEVICE SEQUENCE (installed PWA, funded account)

Clear the site's data once first (old icon-font subset, see the font-cache
note of the previous pass). Then, on one account with Spaces:

1. **Session A (bedroom photo):** V1 → confirm a switch (Soft Luxury) → while
   it renders: Profile → Home → wait for it → reopen A from Projects. Expect V2
   in A, no new project, no spinner, Reveal "Original" = the bedroom.
2. In A, switch → leave for Projects → open **session B (a condo)** → come back
   to A: A shows its running bubble, B never shows A's photo or result.
3. In A, continue to **V5** (switch/refine alternating): ordinals 1…5, one
   bubble and one Space each, no "Something went wrong".
4. Rapid-tap Confirm on a switch: one user bubble, one render, one Space.
5. While A renders, try a switch in B: "Ayden is still finishing a vision in
   another project" — nothing starts, nothing is charged.
6. Start a switch, force-close the PWA, reopen after ~2 min: the vision is
   there, adopted without a second render.
7. Full Reveal on the phone: 28pt of air under the toolbar, same picture size;
   fullscreen button opens the current vision and returns to it; Share.
8. Authenticated Facebook menu (Mike Lim): identity, Profile, Sign out only.
9. Refine follow-up (RED advisory → "yes" → Ayden's proposal rendered).
10. Profile count equals the number of finished visions.

After each step the staging rows can be read back with the read-only
inspector used here (projects / visions / message kinds / claims → does the
named vision exist / ledger).

## 10. DATA LEFT IN PLACE (evidence)

Nothing was repaired or deleted: `440a715e` (V1, V2, one `generation_status`
row — now ignored on load, V2 now visible), `c0ee05e9` (showcase original, no
visions — hidden by the library's usable-project rule), claim `ac4c6cb8` →
missing `b7fe1dea` with its HOLD/COMMIT (**one Space committed for nothing —
refund is a Billing decision, not taken here**), and the interrupted QA draft
`4d78c6ba`.

## 11. REPO / SAFETY

Starting HEADs: backend `pwa-monetization` @ `fff6bee`; PWA
`pwa-web-ios-alignment` @ `c5e6c46`. WIP of both repos saved before any edit
(session scratchpad `backup/*_pre_p0_200029.patch`). Committed locally, **not
pushed**. The backend history gets two commits: first the 2026-09-03 refine
`size` passthrough (`backend/refine/engine.py`, `executor.py`, pinned by
`pwa_staging_orientation_test.py`) — uncommitted until now although the staging
wrapper calls `refine_generate(..., size=size)`, so a HEAD without it would
raise on every staging refine; keyword-only, default unchanged, mobile callers
untouched — then this pass. Not committed (not authored here):
`.claude/settings.json`, the generated Android plugin registrant, earlier
screenshot folders. Production, ABA, Billing,
Wallet, grants, RevenueCat, native iOS: **not touched**.
