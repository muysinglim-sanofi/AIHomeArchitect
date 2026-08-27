# Phase 1 — the visual foundation

Preview: <https://ayden-studio--phase1-foundation-3t6s26ce.web.app> (expires 2026-09-03)
Live staging is **untouched** and still serves the archived design.

## What these screenshots do and do not show

They show the **grammar** changing, not the screens. Phase 1 deliberately did
not redesign Home, Create or Full Reveal — so Home is still dark here, and that
is the correct result, not an unfinished one. What changed is the type, the
geometry and the tokens underneath it.

| file | what to look at |
|---|---|
| `before-home-en.png` | the archived build: headline in the platform default sans |
| `after-home-en.png` | the same headline in **Cormorant Garamond**; body in **Inter**; CTAs are pills |
| `after-home-fr.png` | French, same foundation |
| `after-home-khmer.png` | **the regression check that mattered** — full Khmer UI, correct cluster shaping, no tofu, and the Latin "Ayden" inside Khmer copy picking up Inter |

## The comparison, measured rather than described

| | iOS reference (`f3a6fa2`) | PWA before | PWA now |
|---|---|---|---|
| canvas | `#F9F6F1` | `#0B0B0C` on Home/Create/Projects/Reveal | theme canvas `#F9F6F1`; those four screens still dark **by design**, pending their phases |
| display face | Cormorant Garamond | platform default | **Cormorant Garamond**, bundled |
| body face | Inter | platform default | **Inter**, bundled |
| hero metrics | 38 / w500 / −0.5 / 1.08 | 38 / w300 / −0.4 / 1.1 | **38 / w500 / −0.5 / 1.08** |
| screen title | 26 / w600 / −0.3 | ad hoc per call site | **26 / w600 / −0.3** |
| body / muted / caption | 16·w400 ink / 14·w400 secondary / 12·w400 tertiary | ad hoc | **identical to iOS** |
| CTA radius | 50 (pill) | 16 on some, pill on others | **50 everywhere** |
| card radius | 16 | 16 | 16 |
| hero radius | 24 | 22 | **24** |
| input radius | 14 | — | **14**, gold focus ring |
| gold accent | `#C8A86A` | `#C8A86A` | same object (`AppColors.accent`) |
| nav | white bar, hairline top, 3 tabs | none — header chips | **built**, not yet mounted |
| spacing xs/sm/xl | 4 / 8 / 32 | 6 / 10 / 40 | **4 / 8 / 32** |

## Fonts

Bundled in `web/fonts/`, loaded by `FontLoader` from `pwa_fonts.dart`, exactly
as the Khmer font already was — **not** added to `pubspec.yaml`, because that
file is shared with the frozen mobile app and a Flutter asset would ship into
the iOS binary.

| file | before subset | shipped |
|---|---|---|
| `CormorantGaramond-Latin.ttf` | 1 195 560 B | **149 584 B** |
| `Inter-Latin.ttf` | 876 576 B | **161 808 B** |
| total | 2 072 136 B | **311 392 B** (−85%) |

Both keep their `wght` variable axis, so one file covers every weight. Subset to
Latin + the Latin-Extended range EN/FR needs; coverage asserted on
`AaZz0é€$—'""…àçùôêî` before adoption. Licences travel with them
(`OFL-CormorantGaramond.txt`, `OFL-Inter.txt`).

Runtime fetching stays disabled. A paywall that blocks on `fonts.gstatic.com` is
a paywall that breaks behind a firewall.
