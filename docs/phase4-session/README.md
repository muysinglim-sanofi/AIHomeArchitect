# Phase 4 — the New Design Session, and the wait inside it

Preview: <https://ayden-studio--phase4-session-ou1auyx1.web.app> (expires 2026-09-04)
Live staging, the Phase 2 preview and the Phase 3 preview are all **untouched**.

| file | what it shows |
|---|---|
| `00-create-step4-brief-fr.png` | Step 4 with a brief typed, gold focus ring — the input side |
| `02-session-brief-fr.png` | **the session** — photo, room · atmosphere, Ayden's voice, their own words |
| `01-session-fr.png` | the same with Step 4 skipped: no empty quote, nothing missing |
| `03-session-km-mock.png` | Khmer — the shaping check that matters |
| `03-session-desktop-en.png` | 1440×900, English — "Reading your space…" |
| `04-after-session.png` | a refused generation: the session does **not** dress it up as success |

The Khmer capture is from the offline **mock** build. Same presentation code,
same `PwaDesignSessionScreen`, no backend — the staging identity's free vision
was spent by the first end-to-end run and this phase does not spend money to
take a screenshot.

---

## What was actually wrong with the old wait

It was already cream. It already had no percentage. It already said only what
it could know, and its own source file argued the case. It was **not** a legacy
dark loading screen, and it was not dishonest.

What it was, was **disconnected**. A gold compass on an empty canvas — and the
person's photo, their room, their atmosphere and the sentence they had just
typed all vanished the moment they pressed Generate. Two minutes of watching a
form be processed.

So this phase is not a restyle of a loader. It is the difference between "a
server is working on your request" and "Ayden is reading **your** space", and
the way to say the second is to keep the space on the screen.

---

## The session, measured against iOS

iOS has no separate loading screen: the wait is `_LoadingBubble` inside the
chat feed. Its geometry is what was reproduced.

| | iOS `_LoadingBubble` | PWA before | PWA now |
|---|---|---|---|
| canvas | chat feed | `#F9F6F1` | `#F9F6F1` |
| the photo | **present**, `BoxFit.cover` | **absent** | **present**, `BoxFit.contain` |
| card height | `height × 0.52`, clamp 280–560 | — | **identical** |
| card radius | `radiusCard` 16 | — | **16** |
| ambient | blurred 18, ink-muted 0.5 | — | **identical** |
| bottom scrim | yes | — | **yes** |
| overlay pad | 18 / 0 / 18 / 22 | — | **identical** |
| dots | 3, ~450ms | — | **identical** |
| status text | `titleSmall` w500 on surface | serif 20 centred | **`cardSubtitle` on surface** |
| phrases | `genInitPhrases`, 7 beats | 4 PWA-only beats | **`genInitPhrases`, forwarded** |
| cadence | 3.2→9.0s, widening, holds last | 30s flat, holds last | **iOS's cadence** |
| progress | asymptotic 0.04→0.96 / 80s | travelling highlight | **travelling highlight** |
| session identity | — | — | **eyebrow + room · atmosphere** |
| the brief | — | — | **quoted back** |

### Why the photo is CONTAINed and not COVERed

iOS fills its card. On a phone holding a 4:3 photo that is nearly free. On the
web the card is a different shape at every breakpoint, and cover-cropping cuts
away part of the room the person is asking to have redesigned — the one thing
this screen exists to show. So the focal image is contained and **iOS's own
ambient backdrop** fills the rest. That backdrop already exists in
`RevealCanvas` for exactly this purpose; on iOS it is simply never visible,
because the focal image covers it.

Both layers read the **same** `MemoryImage`, so the bytes are decoded once.

### Why there is no progress bar

iOS eases a line from 0.04 to 0.96 over eighty seconds and never completes it.
It is calm, and it is invented: nothing in this pipeline reports progress. A
person who watches it sit near the end for a minute learns that the bar is
decorative, and everything else on the screen inherits that doubt.

The travelling highlight says the one true thing — *still working* — and never
implies a distance covered. A test sweeps every rendered string for `\d+%` so a
number cannot be added later by accident.

### Why seven phrases and not three

The brief suggested three and said to prefer fewer over fake precision. Seven
was chosen anyway, and the reason is that these seven are **already approved
product copy**, already translated in en/fr/km, already shipping on the phone,
and already experiential rather than telemetric — "Reading your space…",
"Studying natural light and openings…". Writing a new three-phrase set would
have meant new production copy in three languages, which the brief forbids.

The honest constraint was never the count; it was whether the words claim a
stage the system does not have. These do not. They advance on iOS's widening
cadence, and the last one **holds** for as long as the render takes — looping
back to "Reading your space…" after four minutes would tell the person the work
had restarted, and it has not.

---

## The generation contract is untouched

The only controller change is one recorded field:

```dart
final String visionBrief;   // what this session was STARTED with
```

written **once**, in the same synchronous `copyWith` that starts the
generation, and read only by the screen. The request still takes the argument
`generateFirstVision` was called with, and a retry still replays the persisted
`PwaPendingGeneration`, which has carried `userInstruction` since Phase 3. This
field therefore cannot change what is sent — and a test asserts the words on
screen and the words in the intent are the same string.

Nothing else moved: no endpoint, no field, no engine, no billing, no route. The
URL during generation is still `/create`, so a refresh still resumes through
the pending record exactly as before.

---

## Deliberate decisions

**No way out while a generation is in flight.** No back, no close, no nav. A
second entry into Create is a second billable request, and the surest way not to
offer one is not to draw one. The person is not trapped — the session leaves on
its own, and refresh resumes.

**The brief is quoted, not labelled.** A heading would have meant new copy in
three languages. Quotation marks and position already say what it is: the thing
they wrote, a moment ago, on the screen before this one.

**The failure banner was restyled — type role only.** A failure message is body
copy, and body copy is Inter; the serif was a holdover from before the
foundation existed. Every word, code path and retry semantic is untouched, and
a test drives a real mid-session failure and asserts the return to Create with
the photo, room, atmosphere and brief all intact.

---

## Verified end to end, including the part that cannot be faked

A real staging generation was run from Create through the session to the
result. It **succeeded**: Home now shows a genuine before/after of the uploaded
bedroom, resolved by the engine to `Bedroom · Warm Modern` — the room and
atmosphere Ayden read from the photo, adopted by the app exactly as before.

A second run was **refused** — the free vision was spent by the first — and
`04-after-session.png` is that moment: the paywall states the real reason and
the session did not pretend to succeed.

---

## Observed, not fixed

**A billing refusal raises two surfaces at once**: the paywall sheet (accurate)
and the generic "Something went wrong. Try again." banner (noise). Pre-existing
— nothing in this phase touches the billing watcher or the error bar's logic —
and billing semantics are frozen, so it is reported rather than changed.

**Projects is still the legacy dark screen.** Out of scope; Result parity is
the next phase and Projects after it.

**The first reveal is still `Colors.black`.** That is the Result surface and it
is the stated stopping boundary of this phase.
