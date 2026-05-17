# Assets

All files in `assets/`.

## Mascot — production assets

These are the same PNGs already shipping in
`compost/app/Assets.xcassets/`. They're duplicated here so this bundle
is self-contained for review without opening the Xcode asset catalog.

| File | Maps to xcasset | Mood | When used |
|---|---|---|---|
| `mascot-calm.png` | `MascotCalm.imageset` | `.calm` | Default / cue idle / voice listening + thinking |
| `mascot-nudging.png` | `MascotNudging.imageset` | `.nudging` | Pending work / voice speaking / invoice ready |
| `mascot-alert.png` | `MascotAlert.imageset` | `.alert` | Imminent cue (<10m) / successful payment |
| `mascot-sweep.png` | `MascotSweep.imageset` | `.sweep` | Gardener tidy in flight |
| `mascot-base.png` | `Mascot.imageset` | (default) | Fallback if a mood asset is missing |

Source: 1024×1024 transparent PNG. The @1x / @2x / @3x triple already
exists in the xcasset; the file here is the @3x.

## Mascot — reference sheets (not for shipping)

| File | Purpose |
|---|---|
| `mascot-sheet.png` | 40-pose sheet from the original art generation. Use this for picking new moods if we add them later. **Do not ship.** |
| `mascot-key.png` | 10-pose turnaround sheet (front / 3⁄4 / profile / back, plus action poses). Reference for the brand book. **Do not ship.** |

## Sample photos for Memory pile (Scenario 04)

These are the user's real photos from May 15, 2026 — used as the
sample slideshow in the Photos scene. **Ship as imageset previews
only**; the production app reads from Notion's `file_url`.

| File | Caption | Location | Time | Mascot reaction |
|---|---|---|---|---|
| `photo-soma-1.jpeg` | Salesforce Tower from 2nd St | SoMa, San Francisco | 2:32 PM | — |
| `photo-soma-2.jpeg` | Looking up the Salesforce spire | Mission & 2nd, SF | 2:41 PM | — |
| `photo-dustbin.jpeg` | saw your logo on a bin at Pier 9 ☺ | Pier 9 cafeteria | 2:58 PM | **self-sighting** |
| `photo-poster-hermanmiller.jpeg` | "Things Are Getting Better All The Time" — Herman Miller, 1980 | MoMA gift shop | 3:08 PM | **delighted** |
| `photo-poster-peugeot.jpeg` | Cycles Peugeot, Roger Pérot, 1931 | MoMA gift shop | 3:11 PM | — |

The dustbin photo is the **headline moment**: an actual public
Compost-brand bin caught in the wild, which triggers the mascot
self-sighting reaction. Save this one — it's the demo's punchline.

In Xcode, place each as an imageset under `Assets.xcassets/Photos/`
named `photo-{slug}.imageset` for the SwiftUI previews. The production
app fetches via Notion `file_url` and never bundles photos.

## What's missing

These would be nice to commission for v0.5, not blocking for v0.4:

- **mascot-voice** — mascot with a small leaf-shaped microphone, ears
  perked. Currently the Voice scene reuses `.nudging` + a sage halo.
- **mascot-invoice** — mascot holding a paper invoice. Currently the
  Invoice scene reuses `.nudging`.
- **mascot-paid** — mascot with a stamp / "paid" tag in hand for the
  post-pay confirmation. Currently reuses `.alert`.

If we add these, drop them in `compost/app/Assets.xcassets/` as
`MascotVoice.imageset` / `MascotInvoice.imageset` / `MascotPaid.imageset`
and extend the `Mascot.Mood` enum in `compost/app/Views/Mascot.swift`.

## License

The mascot art is original to the Compost project. MIT-licensed with
the rest of the repo (`compost/LICENSE`).
