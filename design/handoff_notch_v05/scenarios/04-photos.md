# Scenario 04 — Photos (Memory pile)

> Surface: net-new. Add `app/Views/PhotosView.swift`, extend
> `NotchSummary` with a `memoryPile: [Photo]` collection, propose new
> managed DB `compostPile/Memory pile` in `INTERFACE.md`, propose a
> `tagPhoto` worker tool.

## Why

The notch is a great surface for **ambient looking-back**. Phones
already do "On this day" / "Memories" — but those live behind two taps
in the Photos app. Compost can do it better because:

1. The user's photos already live in Notion (the user explicitly logs
   them to a `Memory pile` database via the Notion mobile app's share
   sheet).
2. Compost knows time + place from the photo's EXIF.
3. The notch is already where the user goes for time-aware nudges.

The "delight moment" of this scenario is the **dustbin sighting**:
the user has, in their Photos roll, an actual photo of a public
stainless-steel compost bin sticker'd with the Compost brand logo —
when the slideshow surfaces that photo, the mascot **recognises
itself** and reacts with a speech bubble ("yes — that's me! the bin
at Pier 9. logged it."). It's a tiny brand-character moment that
makes the system feel sentient.

## States

The Photos surface has three states:

```
peek ── tap ──> expanded(autoplay) ── tap pause ──> expanded(paused)
                       │                                 │
                       └── auto-advance every 3.5s ──────┘
                       │
                       └── photo.mascot ≠ null ──> mascot speech bubble
```

### A. Peek

```
┌──────────────────────────────────────┐
│ 🌱  5 from SoMa yesterday    ╱ 📷 ╲  │
└──────────────────────────────────────┘
```

- Width 300pt, height 38pt
- Label: `{count} from {placeShort} {when}` — e.g. `5 from SoMa yesterday`,
  `3 from Bernal this morning`
- Chip: 📷 in gold pill `rgba(201,168,90,0.18)`
- Mascot mini: `.calm`

If the latest cluster contains a `compost-sighting` tagged photo, the
peek shows `.nudging` mood and chip text `look at this 👀`.

### B. Expanded

```
┌──────────────────────────────────────────────────────────────────┐
│ 🌱  📷 MEMORY PILE · 5 FROM YESTERDAY                          ✕ │
│     Pier 9 cafeteria                                             │
│                                                                  │
│   ┌──────────────────────────────────────────────┐               │
│   │ 🌱 yes — that's me! the bin at Pier 9.       │  (speech      │
│   │    logged it.                                │   bubble)     │
│   │                                              │               │
│   │  ┌  ┌──────────────────────────────────┐  ┐  │               │
│   │  ‹  │                                  │  ›  │ (prev / next) │
│   │     │       [ Photo of compost         │     │               │
│   │     │         dustbin with the         │     │               │
│   │     │         brand sticker ]          │     │               │
│   │  ┌  └──────────────────────────────────┘  ┐  │               │
│   │                                                              │
│   │   saw your logo on a bin at Pier 9 ☺                         │
│   │   📍 Pier 9 cafeteria   · 🕒 yesterday · 2:58 PM              │
│   └──────────────────────────────────────────────┘               │
│                                                                  │
│   ●  ●  ━  ●  ●         (dot indicator, active is wider)         │
│                                                                  │
│   [↗ Open in Notion]  [+ Tag]  [Ask about this ↗]                │
│                                            #compost-sighting #lol│
└──────────────────────────────────────────────────────────────────┘
```

- Outer: 540pt wide (wide variant), auto height (≈420pt), bottom radius 22pt
- Padding: 14×16, gap 12pt

#### Components

1. **Head row** — mascot 36pt + eyebrow + photo place title + close
   - Mascot mood: see "Mascot reactions" below
   - Eyebrow: `📷 MEMORY PILE · {count} FROM {when}`
   - Title: the **place** of the current photo (`photo.place`)

2. **Photo viewer** (260pt tall)
   - Rounded 12pt corners, hairline border, black bg fallback
   - `<img>` with `object-fit: cover`
   - Crossfade on photo change (220ms ease-out)
   - **Prev / Next arrows** — 32pt circles, glass-style: `rgba(0,0,0,0.55)`
     + 8pt backdrop-blur, white chevron
   - **Pause / Play** — top-right, 28pt circle, same style
   - **Caption strip** — bottom 30pt gradient overlay
     `linear-gradient(0deg, rgba(0,0,0,0.75), transparent)`
     - Title: `photo.caption` — 12pt SF Pro Rounded semibold, white
     - Sub: `📍 {place}` + `🕒 {timeLabel}` — 10.5pt, white 75% opacity
   - **Mascot speech bubble** (conditional) — top-left, max-width 260pt
     - Bg `rgba(20,32,19,0.92)`, sage border, sage300 text
     - Renders only when `photo.mascot` is set
     - Slide-in from above 220ms `springExpand`

3. **Dot indicator** — bottom-center, gap 6pt
   - Inactive dot: 6×6pt, `rgba(255,255,255,0.20)`
   - Active dot: 18×6pt pill, `sage400`, animates width transition 0.3s
   - **Sightings get gold-tinted inactive dots** so the user can see
     "ooh there's something special on slide 3" before reaching it:
     `rgba(201,168,90,0.50)`

4. **Action row** — flex, gap 6pt
   - Primary: `↗ Open in Notion` — opens the Memory pile DB at this row
   - Ghost: `+ Tag` — opens an inline text input (focus the input;
     ⏎ saves, ⎋ cancels). Saving calls `tagPhoto` worker tool and
     shows a success toast.
   - Ghost: `Ask about this ↗` — switches to the **voice surface
     with a photo-specific script** (the prototype calls
     `onNavigate("voice-photos")`)
   - Right-aligned: existing tags as sage `#tag` pills
     (the `compost-sighting` tag renders sage; others render neutral)

## Mascot reactions

The interesting design move: certain photos are flagged
`photo.mascot = "<type>"` (string), which drives both the mascot pose
in the head and a speech bubble overlay on the photo. Three types:

| Type | Mood | Bobble | Speech bubble copy |
|---|---|---|---|
| `self-sighting` | `.alert` | yes (once on enter) | `yes — that's me! the bin at Pier 9. logged it.` |
| `delighted` | `.nudging` | no | `this one's good. tag it for the moodboard?` |
| `nostalgic` | `.calm` | no | `oh — this was the day Maya joined.` |

`self-sighting` is the headline easter egg. Detection happens in the
worker (`Memory pile` sync): if the photo contains the Compost brand
logo or a `compost-sighting` tag was added by the user, the row's
`Mascot Reaction` is set to `self-sighting`.

For the v0.4 demo, just inline the flag in the sample data; v0.5 we
can wire it up to a tiny CLIP-style classifier or just trigger on the
tag.

## Slideshow auto-advance

| Frame type | Dwell time |
|---|---|
| Normal photo | 3.5s |
| Photo with `mascot` set | 5.0s (give the user time to read the bubble) |
| Paused | ∞ |

The play / pause button toggles `playing` state. Crossing to a new
photo via prev/next does **not** toggle pause — keeps autoplay
running so the slideshow stays gentle.

Auto-advance pauses while the Tag input is open.

## Data binding

### App-side model

```swift
struct Photo: Identifiable {
    let id: String              // Notion page id
    let photoId: String         // sha1(originalAssetUri + timestamp)
    let caption: String
    let place: String
    let timeISO: Date
    let lat: Double?
    let lng: Double?
    let assetUrl: URL           // file_url from Notion (signed)
    let tags: [String]
    let mascotReaction: String? // "self-sighting" | "delighted" | "nostalgic"

    init?(_ page: NotionPage) {
        // mirror Proposal.init pattern
    }
}
```

Extend `NotchSummary`:

```swift
let memoryPileCount: Int
let memoryPile: [Photo]
```

Extend `hasAnything` accordingly.

### New managed DB — propose in `INTERFACE.md`

```text
compostPile / Memory pile

Title              (title)            "Pier 9 cafeteria · 2:58 PM"
Photo ID           (rich_text)        sha1(assetUri + ISO timestamp)
Caption            (rich_text)        user-editable
Place              (rich_text)        e.g. "Pier 9 cafeteria"
Time               (date)             EXIF DateTimeOriginal in user TZ
Latitude           (number)
Longitude          (number)
Asset              (files)            the photo itself (uploaded via mobile)
Tags               (multi_select)     "walk", "compost-sighting", etc
Mascot Reaction    (select)           "self-sighting" | "delighted" | "nostalgic" | "none"
Logged Via         (select)           "share-sheet" | "auto-camera-roll"
Created            (created_time)
```

The `Mascot Reaction` field is set by the **worker** during a daily
sync; the app just reads it.

### New worker tool — propose in `INTERFACE.md`

```typescript
tagPhoto:
  input:  { photoId: string, tag: string }     // photoId = Photo ID
  output: { ok: boolean, tags: string[], error: string | null }

  Worker behavior:
  - Look up Memory pile row by Photo ID
  - Add `tag` to the Tags multi_select (idempotent)
  - Return full updated tag list
  - If tag = "compost-sighting", also stamp Mascot Reaction = "self-sighting"
```

Optional v0.5: a `findMemoryPilePhotos` tool that takes `{ when, place }`
filters and returns the matching cluster. Useful for voice queries
like "what photos did I take near the gallery yesterday?".

## Voice integration

The voice scene takes a `script` prop (`"default"` | `"photos"`). When
the user is in Photos and taps `Ask about this`, the app calls
`onNavigate("voice-photos")` which:

1. Sets `voiceScript = "photos"`
2. Switches `scenario = "voice"`
3. Expands the notch

The photos voice script runs:
```
User (typed live): "compost, what photos did i take yesterday around the gallery?"
Compost (typed live): "Five from SoMa between 2:30 and 3:15 PM. Two skyline shots near the Salesforce Tower, two posters from the Herman Miller gallery, and — heh — you caught my logo on a trash can."
```

This proves the **bidirectional flow**: photos → voice → (could)
navigate back to photos.

## Polling

Extend `app/Polling/CompostPoller.swift` with a Memory pile fetch.
Filter for recent photos: `Time >= today - 24h`. Don't fetch the
full asset URLs upfront — pull them lazily when the user expands
the Photos surface.

## Caching

Photo asset URLs from Notion are **signed and expire**. Cache the
decoded `NSImage` for the lifetime of the app process keyed by
`Photo ID`; do not persist to disk (privacy + low value).

## Accessibility

- Outer expanded: `.accessibilityElement(children: .contain)`,
  combined label: `"Memory pile, {count} photos from {when}, showing {currentCaption}"`
- Prev / Next: standard hints
- Pause / Play: `.accessibilityLabel("Pause slideshow")` / `"Play slideshow"`
- Dot indicator: `.accessibilityRepresentation` exposes as a
  segmented control with `.accessibilityValue("{idx} of {count}")`
- Mascot speech bubble: announce its text once on photo enter, then
  hide it from VoiceOver focus
- `+ Tag` opens an input — focus it after open; VoiceOver should
  announce "Tag input, enter to save"

## Reduce motion

- Disable crossfade between photos (instant swap)
- Disable mascot bobble on `self-sighting` (still swap mood)
- Disable slideshow auto-advance (require manual prev/next)
- Disable speech bubble slide-in

## Privacy notes

- Photo asset URLs from Notion are short-lived; don't log them
- Lat/Lng are sensitive — show place name only in the caption; lat/lng
  is only used to cluster photos by location
- The "Mascot Reaction" worker logic only sees the photo via Notion's
  file_url; it does not run a face-detect or any biometric model.
  Logo detection is the only ML step (planned for v0.5).
