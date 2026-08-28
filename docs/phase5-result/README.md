# Phase 5 — the generated result, and the conversation it starts

Preview: <https://ayden-studio--phase5-result-vi3uaf41.web.app> (expires 2026-09-04)
Live staging and the Phase 2 / 3 / 4 previews are all **untouched**.

| file | what it shows |
|---|---|
| `02-result-fr.png` | **the result** — a real staging generation, uncropped, image first |
| `04-result-desktop-fr.png` | the same at 1440×900 |
| `01-first-reveal-fr.png` | the one-off unveiling, now on the canvas |
| `03-result-km-mock.png` | Khmer — shaping, and the four suggestions wrapping |

`02` and `04` are a **real generation on staging**: an example bedroom, resolved
by the engine to Warm Modern. `01` and `03` are the offline mock build — same
presentation code, and this phase does not spend a customer's free vision to
take a screenshot.

---

## The one rule, and the thing it was hiding behind

IMAGE FIRST, COMMENTARY SECOND, ACTIONS THIRD.

The first vision already led with its render — that ordering was decided in an
earlier pass and is not new here. What was new to find is what the render was
*behind*:

* a **title strip inside the card**, so the first thing read after a two-minute
  wait was the label "Vision 1 · Warm Modern";
* **three action pills**, between the render and Ayden's line, so a person met a
  row of buttons before being told anything about what they were looking at;
* a **16:9 crop**, taking roughly a tenth off the top and bottom of the one
  image they had waited for.

All three are gone. The caption moved under the image where a caption belongs,
the actions moved below Ayden's two sentences, and the frame is now the shape
the engine actually returns.

---

## Measured

| | before | now |
|---|---|---|
| canvas | blurred living-room photo + ivory veil + glass plate | `#F9F6F1` |
| render frame | 16:9, `cover` → cropped | **3:2 — the engine's own output** |
| render position | under a title strip, inside a card | **first, no card, no frame at rest** |
| render size | ≤ 820 × 470 | **≤ 820 × 560** |
| caption | above the image | **below it**, `bodyMuted` |
| commentary | 3 sentences, 45 words, after the actions | **2 sentences, 18 words, before them** |
| Ayden bubble | platform sans on warm cream | **Inter on `pwaSurface`, hairline** |
| user bubble | `#2B211C` @ 94% | **`pwaInk`** |
| suggestions | gold-edged pills on translucent glass | **hairline pills on `pwaSurface`** |
| primary action | gold fill | **ink pill** |
| composer | 18px radius, glass field | **`radiusInput` 14, `pwaWell`, gold focus ring** |
| send | gold circle | **ink circle** |
| header | `#080806` bar, controls crammed left | **canvas + hairline, back / title / actions** |
| First Reveal | `Colors.black`, full-bleed cover-crop | **canvas, render at 3:2, ink CTA** |

### The room behind the conversation

The thread used to float on a photograph of a Warm Modern living room —
softened, veiled, and on desktop under a sheet of translucent glass. Sixteen
constants described that surface: two gradient stops, two alpha ceilings, two
blur radii, a border alpha, and an ink pair for each side of it.

It is all gone, and the reason is not that it was ugly. **The person has just
generated a picture of their own room, and the app was showing them somebody
else's behind it.** Two rooms competing, and the one that wins is not theirs.

---

## Nothing underneath moved

This is a presentation phase, and the things it would be easy to break quietly
are asserted rather than assumed:

* **A suggestion is a sentence.** Tapping one calls `sendUserText` — identical
  to typing it — and the canonical turn decides what the line means. Nothing
  here routes, and nothing here decides that a line is a refine.
* **A backend-sent `chips` list still wins** over the local set. The precedence
  was not reversed by restyling the pills.
* **The free-form field** sends through the same path.
* **The refine confirmation card** keeps every semantic, including the one that
  matters most: a **red** advisory verdict has no override — the button is
  absent, not disabled — and `dismissRefine` still runs before `applyRefine`
  so an offer cannot be fired twice.
* **Full Reveal** opens for *that* vision, through the existing route, and
  creates nothing.
* Lineage, parent selection, current-vision selection and atmosphere-switch
  semantics: untouched.

`kPwaRenderAspect = 3/2` is the only new constant, and it describes what the
engine returns rather than changing anything about it.

---

## Copy: two changes, both PWA-owned, both through the dictionary

**Ayden's opening line.** It was three sentences and ended *"Explore the
atmospheres below"* — but the atmosphere rail moved to the Full Reveal in an
earlier pass, so it was telling people to use something that is not on the
screen. It is now two short sentences that name the direction the engine
actually resolved:

> Your Warm Modern direction is in — same architecture, warmer materials and
> softer light. What would you like to change?

`{name}` is `chosen.name`, the **resolved** atmosphere. On a delegated "Ayden
Signature" the requested and rendered directions differ, and naming the
delegation back at someone says nothing about their room.

**"Open the kitchen" → "Make it calmer".** The four default suggestions sit
under *every* result. Offering "Open the kitchen" under a terrace or a bathroom
was a suggestion a person could tap and pay for. The replacement is
room-neutral and travels the identical contract. The old key is left in the
dictionary; nothing reads it.

Both exist in en / fr / km. A message's text is written **once**, in the
language of the moment, and stored — changing the language afterwards does not
rewrite what Ayden already said. `03-result-km-mock.png` shows exactly that: a
Khmer interface around a French sentence Ayden said earlier, which is correct.

---

## Defects found by looking

1. **French overflowed the pills by 9px** on a 390px phone. A `Wrap` hands its
   children loose constraints, so a `Row` inside one sizes to its natural width
   and `Flexible` has nothing to shrink against. Both pill rows now take a
   ceiling measured from the row they wrap in.
2. **The First Reveal's brand line was unreadable.** It was positioned *over*
   the render — safe on black, a contrast bet on cream, and it lost against a
   pale bedroom wall. It is a header on the canvas now, not an overlay.
3. **The First Reveal overflowed by 1–4px**, because its render aspect was
   computed from an estimate of the header and CTA bands. It is measured.
4. **The First Reveal cover-cropped a 3:2 render into a 0.45 portrait** — most
   of the room gone, at the moment the room is the point. It shows the render
   whole, at the same shape the result screen uses.

---

## What was retired from the test suite

About twenty tests measured the glass: `kPwaGlassTop`'s channels,
`kPwaDesktopGlassTopAlpha` ≤ 0.18, the backdrop veil, the blur ceilings, and
which ink each layer demanded. The surface they describe does not exist, so
they were not migrated — there is nothing left for them to describe.

What replaces them is the rule the phase actually has to hold: no photograph
behind the conversation, the canvas is the product canvas, the render is the
largest thing on screen, it is shown whole, and it comes first. Suite green at
**1151**.

---

## Observed, not fixed

**A billing refusal still raises two surfaces** — the paywall (accurate) and the
generic error banner (noise). Explicitly out of scope for this phase, reported
again for final polish.

**`av7Sans` sets no `fontFamily`.** Every screen still using the V7 token
helpers renders in the platform default rather than Inter — Full Reveal and
Projects among them. The result screen no longer uses those helpers, so it is
correct; the token file was deliberately **not** touched, because it is shared
with the Full Reveal, which this phase must leave alone. It is a one-line fix
to make in the phase that owns those screens.

**The First Reveal is quiet on a tall phone.** A 3:2 card on a 390px screen is
247px tall in ~650px of space. It is truthful and uncropped, but the moment has
less weight than the full-bleed version had. Worth revisiting when its sibling,
the Full Reveal, gets designed.

**Projects and Full Reveal remain legacy dark.** That is the stated stopping
boundary: tapping "View full reveal" from this screen still lands on the old
surface, by design.
