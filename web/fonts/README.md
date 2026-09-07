# PWA fonts — why a font file lives here

## What this is

`NotoSansKhmer-Regular.ttf` — Noto Sans Khmer, Regular, 114 096 bytes.

* Family: `Noto Sans Khmer`
* Copyright 2016-2022 Google Inc.
* **SIL Open Font License 1.1** — the licence and its URL
  (`http://scripts.sil.org/OFL`) are recorded in the font's own `name` table
  (IDs 13 and 14), so the terms travel with the file and cannot drift from it.
* Source: `googlefonts/noto-fonts`, `hinted/ttf/NotoSansKhmer/`.
* Verified before adoption: 114 of the 128 code points in the Khmer block
  (U+1780..U+17FF) are covered — the remainder are unassigned — and the font
  carries **GSUB and GPOS**, which Khmer requires: without shaping tables the
  script renders as a row of unjoined marks even when every glyph exists.

## Why it is in `web/` and not in `assets/`

`web/` is the Flutter **web** directory. Everything in it is copied into
`build/web` and served as a static file; **nothing in it is ever packaged into
the iOS or Android bundle**, and `pubspec.yaml` is not touched. That is the
whole point: this repository is shared with the frozen mobile app, and adding a
font under `assets/` with a `pubspec.yaml` entry would have shipped 114 KB into
a mobile binary that neither needs it nor is allowed to change.

The font is therefore loaded at runtime by `pwa_khmer_font.dart` (via
`FontLoader`), which only `main_pwa.dart` imports.

## Why it is needed at all — measured, not assumed

The PWA renders with **CanvasKit** (verified: a single `<canvas>` inside
`flt-glass-pane`'s shadow root, plus `flt-scene-host`; no `flt-paragraph`).
CanvasKit does not use the browser's system fonts. When it meets a code point
no loaded font covers, Flutter downloads a Noto fallback **from
`fonts.gstatic.com` at runtime** — observed doing exactly that for
`notosanssymbols` and `roboto` on a cold start.

That mechanism does work: the language menu first painted ភាសាខ្មែរ as nine
tofu boxes, and after the download completed the same menu painted correctly.
Which is precisely the problem:

* **the first paint of any Khmer text is tofu**, on every cold load;
* a blocked, slow or filtered CDN leaves it tofu permanently;
* it makes the readability of a Cambodia-first product depend on a third-party
  CDN reachable at the moment the user needs it.

Bundling the font removes the round trip: Khmer is correct on the first frame,
offline, and without contacting anyone.

## What it does NOT change

Latin text is unaffected. The family is registered as a **fallback**, never as
the primary family, so English and French keep the exact typography they had —
only code points no other font covers reach it.

## The paywall's two faces — Playfair Display and Great Vibes

Added for Round 2.1, on the same terms and by the same mechanism.

`PlayfairDisplay-Latin.ttf` — 300 724 bytes, variable (`wght`).

* Family: `Playfair Display`
* Copyright 2017 The Playfair Display Project Authors
  (<https://github.com/clauseggers/Playfair-Display>), Reserved Font Name
  "Playfair Display"
* **SIL Open Font License 1.1** — recorded in the font's own `name` table
  (ID 13 = the licence text, ID 14 = `http://scripts.sil.org/OFL`), verified by
  reading the table, and copied beside it as `OFL-PlayfairDisplay.txt`.
* Source: `google/fonts`, `ofl/playfairdisplay/PlayfairDisplay[wght].ttf`.

`GreatVibes-Regular.ttf` — 457 588 bytes, static regular.

* Family: `Great Vibes`
* Copyright 2015 The Great Vibes Pro Project Authors
  (<https://github.com/googlefonts/great-vibes>)
* **SIL Open Font License 1.1** — same evidence: name table IDs 13/14
  (`https://openfontlicense.org`), plus `OFL-GreatVibes.txt`.
* Source: `google/fonts`, `ofl/greatvibes/GreatVibes-Regular.ttf`.

OFL 1.1 §2 permits redistribution of the font software, bundled or standalone,
provided the licence travels with it. It does here twice over: as the `OFL-*.txt`
files, and inside the fonts' own name tables, where it cannot drift from the
binary it describes. Neither face is sold, and neither is renamed (§3/§4).

### Why these two, and only on the paywall

iOS composes the paywall headline in Playfair Display with a Great Vibes accent
word (`features/paywall/paywall_sheet.dart`). Round 2 substituted the product's
own Cormorant, which was honest but not parity. These are the real faces, and a
test (`PAY27`) fails if Great Vibes is ever used anywhere else in the product
just because it is now available.

### Why they are NOT awaited at boot

`loadPwaFonts()` (Inter + Cormorant, ~300 KB) is awaited before the first paint
because a face that arrives late causes a visible reflow on CanvasKit. These two
are ~750 KB and belong to ONE surface that is never the first screen, so
`loadPwaPaywallFonts()` is started at boot and deliberately not awaited: no
visitor pays a boot cost for a screen most of them never open, and they land
long before the paywall can be reached.
