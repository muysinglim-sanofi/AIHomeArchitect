# Provenance record — SUPERSEDED BY ABA'S OFFICIAL ARTWORK

**Status, 2026-09-08: ABA supplied its official SVG artwork in the merchant
review (`docs/aba/official/`). The two generated PNGs below have been removed
from `web/aba/` and are referenced by no UI code.** This file stays as the
provenance record of the interim.

**Status, 2026-09-05: the owner has reviewed the finding below and explicitly
authorised these two files for the PREPROD ABA review.** They were in
`web/aba/` and used by the footer until 2026-09-08.

The original finding follows, unchanged.

---

# Original finding — these are not ABA assets

**Not shipped at the time this was written.** They were placed in `web/aba/` on 2026-09-04 to
serve the "We accept" strip required by ABA's merchant review. They are image
generations, not ABA artwork, and they were moved here instead of being
deployed.

## What was checked

**Provenance.** Both files landed with modification times of 09:25:00 and
09:29:16 on 2026-09-04. `~/Downloads` on this machine holds dozens of files
named `ChatGPT Image <date>, <HH_MM_SS> <AM/PM>.png`, and the two entries for
those exact timestamps are absent from that folder — consistent with having been
moved out and renamed. Neither PNG carries any `tEXt`, `iTXt`, `eXIf` or `tIME`
chunk, so there is no embedded authorship to contradict that.

**The artwork itself.** ABA's real mark is visible in the footer of ABA's own
hosted checkout page, captured from the sandbox in
[`../../preprod/iframe-khqr-only.png`](../../preprod/iframe-khqr-only.png): a
navy `ABA' BANK` wordmark with an endorsement line reading
`NATIONAL BANK OF CANADA GROUP`. Neither quarantined file resembles it.

| File | What it shows | Why it fails |
| --- | --- | --- |
| `we_accept_aba_khqr.png` | "We accept" + a blue `ABA` tile + a red `KHQR` tile | The red slash floats detached over the final `A`; the `KHQR` lockup renders the `Q` as an invented rounded-square glyph; tile edges are painted, not vector |
| `aba_khqr_logo.png` | One rounded app-icon tile, blue `ABA` over red `KHQR` | No such combined ABA-KHQR lockup exists; the tile carries a generated bevel and a visible red-white diffusion smear below its bottom edge |

## Why this is a stop, not a workaround

A "We accept" strip is an **acceptance mark**: an assertion of a commercial
relationship, rendered in a third party's registered trademark. Submitting a
fabricated version of ABA Bank's and KHQR's marks to ABA, inside the merchant
review ABA is conducting, is a false attestation regardless of intent. No amount
of retouching fixes provenance.

## What ships instead

`lib/features/pwa/presentation/pwa_aba_marks.dart` names the payment method in
type — `ABA KHQR` in Ayden's own ink, in a hairline chip — which is true and
verifiable. It exposes two constants, `kPwaAbaAcceptStripAsset` and
`kPwaAbaMethodMarkAsset`, both `null`. Drop ABA's official file in `web/aba/`
and point a constant at it, and both widgets switch from type to artwork with
no other change.

The payment **modal needs nothing from ABA**: it embeds ABA's own checkout page,
which carries ABA's own KHQR header and ABA's own footer logo.

## What to ask ABA for

1. The official "We accept ABA KHQR" acceptance strip, in PNG or SVG.
2. The official compact ABA KHQR mark for the payment-method row.
3. Written permission to display both, which merchant brand kits normally grant
   explicitly and which should be kept alongside the files.
