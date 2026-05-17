# Design Tokens — Compost Notch v0.4

These extend `compost/app/GardenStyle.swift`. Add the new tokens to that
enum; keep the existing ones untouched.

## Color

### Palette — sage (brand)

| Token | Hex | OKLCH approx | Use |
|---|---|---|---|
| `sage900` | `#1f2e18` | `oklch(0.25 0.06 135)` | deep ground (rare, expanded card stroke) |
| `sage700` | `#3a5d2f` | `oklch(0.42 0.10 135)` | primary button hover / pressed |
| `sage600` ← existing `accentGreen` | `#4F7942` | `oklch(0.52 0.12 135)` | brand accent, primary CTA, mascot tint |
| `sage500` | `#6a9258` | `oklch(0.62 0.11 132)` | hover affordance |
| `sage400` | `#87a877` | `oklch(0.72 0.10 130)` | live waveform, accent text on dark |
| `sage300` | `#b9d0ac` | `oklch(0.84 0.07 130)` | secondary accent text, eyebrow labels |
| `sage100` | `#e3edd8` | `oklch(0.94 0.04 130)` | sage-tinted surfaces (light mode only) |

### Palette — secondary accents (new)

These appear in the new scenarios. Add to `GardenStyle.swift` as a flat
namespace, e.g. `GardenStyle.accentGold`, `.accentRose`, `.accentAmber`.

| Token | Hex | Use |
|---|---|---|
| `accentGold` | `#c9a85a` | Invoice amount glyph, "verified payee" tag |
| `accentRose` | `#d77a6b` | Voice "LIVE" indicator, shouty diff strikethrough, Decline button |
| `accentAmber` | `#f0a444` | Sleep-On-It warn chip, "review" peek pill |
| `accentSky` | `#6fa8c7` | reserved for future use; do not introduce yet |

### Mascot face / cream

| Token | Hex | Use |
|---|---|---|
| `cream` | `#f3ead4` | mascot face fill — reference only, comes from PNGs |
| `bone` | `#f5f0e3` | future light-mode surface |

### Neutrals (dark mode — default)

| Token | Hex | rgba on dark | Use |
|---|---|---|---|
| `ink` | `#f4f4ee` | – | primary text |
| `ink2` | – | `rgba(244,244,238,0.74)` | body text |
| `ink3` | – | `rgba(244,244,238,0.50)` | secondary text, meta |
| `ink4` | – | `rgba(244,244,238,0.30)` | hairlines, disabled |

| Token | rgba | Use |
|---|---|---|
| `card` | `rgba(255,255,255,0.05)` | inner card surface |
| `cardHi` | `rgba(255,255,255,0.08)` | hover card surface |
| `hair` | `rgba(255,255,255,0.10)` | hairline border |

### Notch shell

| Token | Hex | Use |
|---|---|---|
| `notchBg` | `#050608` | the notch fill itself (matches Mac display) |
| `peekBackground` ← existing | `rgba(0,0,0,0.75)` | peek capsule (kept for back-compat) |

## Typography

Two faces, both system. The display face is **SF Pro Rounded** — match
the existing `.system(.title3, design: .rounded)` usage in
`ExpandedView.swift`.

| Role | Family | Weight | Size | Line height | Tracking |
|---|---|---|---|---|---|
| Header title | SF Pro Rounded | 600 | 16pt | 20pt | -0.16 |
| Eyebrow | SF Pro Rounded | 700 (uppercase) | 10.5pt | 14pt | +1.0 |
| Body callout | SF Pro Text | 500 | 13pt | 17pt | -0.06 |
| Caption | SF Pro Text | 400 / 600 emphasis | 11.5pt | 15pt | 0 |
| Caption2 | SF Pro Text | 500 | 10.5pt | 13pt | +0.1 |
| Big number (cue time, invoice amount) | SF Pro Rounded | 700 | 30pt / 36pt | 1.0 | -0.6 (tabular-nums) |
| Mono (proposal id, account ending) | SF Mono | 400 | 11pt | 14pt | 0 |

SwiftUI equivalents:

```swift
.font(.system(.title3, design: .rounded).weight(.semibold))   // header
.font(.system(size: 30, weight: .bold, design: .rounded))     // cue time
.font(.system(size: 36, weight: .bold, design: .rounded))     // invoice value
.font(.caption.weight(.semibold))                              // eyebrow (uppercased)
.font(.callout)                                                // body
.font(.caption)                                                // small body
.font(.caption2)                                               // meta
.font(.system(.caption2, design: .monospaced))                 // ids
```

Use `.monospacedDigit()` for any number that updates (countdowns,
amounts) so digits don't jitter.

## Spacing

8pt grid. Existing tokens in `GardenStyle.swift`:

| Token | Value | Use |
|---|---|---|
| `spacing` | 6 | tight inline gap |
| `rowGap` | 8 | between rows in a list |
| `sectionGap` | 12 | between major sections |
| `cardPadding` | 16 | card outer padding |

Additions for v0.4:

| Token | Value | Use |
|---|---|---|
| `peekPadV` | 6 | peek vertical padding |
| `peekPadH` | 14 | peek horizontal padding |
| `expandedInnerGap` | 10 | between blocks inside expanded card |
| `actionRowGap` | 6 | between buttons in an action row |

## Radii

| Token | Value | Use |
|---|---|---|
| `peekCornerRadius` ← existing | 10 | (kept; not used in v0.4) |
| `peekR` (new) | 16 | peek capsule corner |
| `cornerRadius` ← existing | 8 | inner cards, buttons |
| `cardCornerRadius` ← existing | 14 | (kept) |
| `expandedR` (new) | 22 | expanded card bottom corner — matches macOS notch radius |
| `wideR` (new) | 22 | same; the wider variant |

The top corners of any notch surface are **0** — the notch is flush
with the top of the display.

## Notch sizes

The HTML prototype renders at a simulated display scale; SwiftUI on a
real notched MacBook needs these absolute values, measured from
`DynamicNotchKit`'s coordinate system (1× notch ≈ 200×32 pts):

| State | Width | Height | Bottom corner radius |
|---|---|---|---|
| Idle (no badge) | 220 | 34 | 16 |
| Peek (live activity) | 300 | 38 | 18 |
| Expanded (standard) | 440 | auto, min 180 | 22 |
| Expanded (wide — drafts) | 540 | auto, min 230 | 22 |

These are the same numbers the prototype's CSS uses; transcribe them
into a `NotchSize` enum in SwiftUI.

## Shadow

The notch itself doesn't cast a shadow on a real Mac, but inner cards
and the dock-style action shelf do:

```
shadow: 0 12px 36px rgba(0,0,0,0.45)
```

SwiftUI:
```swift
.shadow(color: .black.opacity(0.45), radius: 18, y: 6)
```

## Motion

| Token | Curve | Duration |
|---|---|---|
| `springExpand` | `interactiveSpring(response: 0.55, dampingFraction: 0.78)` | natural |
| `springCollapse` | `interactiveSpring(response: 0.40, dampingFraction: 0.85)` | snappier |
| `easeInOut` | `easeInOut` | 0.20s for hover / state pills |
| `pulse` | `easeInOut.repeatForever(autoreverses: true)` | 1.0s for live dot |
| `glow` | same as `pulse` | 2.5s for voice-mode mascot halo |

Every animation must be gated through `GardenStyle.reduceMotion`. See
`INTERACTIONS.md` for the table of which animation fires when.

## Mascot moods → existing assets

No new assets needed for the v0.4 work. Use:

| Mood | Existing asset | When |
|---|---|---|
| `.calm` | `MascotCalm` (Assets.xcassets) | idle / cue with no urgency |
| `.nudging` | `MascotNudging` | drafts pending / voice speaking / invoice ready |
| `.alert` | `MascotAlert` | cue < 10m / payment confirmation pulse |
| `.sweep` | `MascotSweep` | gardener actively running (no UI change in v0.4) |

The mascot **never** casts a literal drop shadow on the notch — the
notch is already shadowed. Inner mascot uses a subtle sage halo
(`radial-gradient` glow) only in the Voice scenario.
