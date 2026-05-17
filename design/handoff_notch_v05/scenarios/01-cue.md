# Scenario 01 — Cue (first meeting prep)

> Surface: refines existing `app/Views/CueRow.swift` + the `Cue` section
> of `ExpandedView.swift`. Net-new: prep checklist, hero time strip,
> calm-cue body line.

## Why

The current notch shows a 1-line cue (`Current` + `Next` arrow). For
the first meeting of the day, that one line isn't enough — users open
Notion anyway to skim prep notes, defeating the notch's purpose.

This scenario makes the **expanded** state into a full prep card:
- Big countdown number (the meeting is the only number you care about)
- 1-line calm rephrasing of what the meeting is about
- 3–4 prep items that come from the same `[!cue]` Notion page
- A "Snooze 5m" and "Open in Notion"

Peek state is unchanged in shape — just the new tokens.

## States

### A. Peek (live activity)

```
┌──────────────────────────────────────────────┐
│ 🌱  App shell checkpoint        ╱ in 12m ╲  │
└──────────────────────────────────────────────┘
   ↑ mascot mini (calm)                ↑ chip
```

- Width: 300pt, height: 38pt
- Background: `notchBg` (the notch itself)
- Mascot mini: 26×26pt circle, sage tint, mascot image clipped inside
- Label: `App shell checkpoint` — SF Pro Rounded 12.5pt semibold
- Chip: `in 12m` — sage 11.5pt semibold, pill `rgba(135,168,119,0.18)`,
  text `sage300`
- The chip switches to **amber** when minutesUntilNext < 10
- The chip pulses (1s ease-in-out) when minutesUntilNext < 10 — gate on
  `GardenStyle.reduceMotion`

### B. Expanded

```
┌──────────────────────────────────────────────────────────┐
│ 🌱   ☀ UP NEXT · 10:30 AM                              ✕ │
│      App shell checkpoint                                │
│                                                          │
│   10:30 AM   ┌ in 12 min · 25 min · Maya & Theo ┐        │
│                                                          │
│   You promised the notch would feel alive by today.      │
│   Maya is bringing the worker logs.                      │
│                                                          │
│   ☑ Skim last week's notes                               │
│   ☑ Pull the Figma file                                  │
│   ☐ Decide on top 2 questions                            │
│   ☐ Open the Loom from yesterday                         │
│                                                          │
│   [↗ Open in Notion]  [Snooze 5m]      [!cue] · agenda.md│
└──────────────────────────────────────────────────────────┘
```

#### Layout

- Outer: 440pt wide, auto height, bottom-corner radius 22pt
- Padding: 14pt top, 16pt sides, 14pt bottom
- Vertical gap between blocks: 12pt

#### Components

1. **Head row** — `Mascot(size: 36, mood: .calm)` + text stack + close
   - Eyebrow: `☀ UP NEXT · 10:30 AM` — caption uppercase 10.5pt
     weight 700, color `sage300`, tracking +1pt
   - Title: `App shell checkpoint` — SF Pro Rounded 16pt semibold
   - Close: 24×24pt circle, `rgba(255,255,255,0.06)` bg, "✕" 12pt

2. **Time strip**
   - "10:30" — 30pt rounded bold, **tabular-nums**, `ink`
   - "AM" — 14pt rounded semibold inline, `ink3`
   - Countdown pill: `in 12 min · 25 min · Maya & Theo`
     12pt semibold, `sage300`, pill border `0.5pt rgba(135,168,119,0.3)`,
     bg `rgba(135,168,119,0.14)`, padding `4×10`
   - Pill text colour goes amber when minutesUntilNext < 10

3. **Body line**
   - 12.5pt `ink2`, line-height 1.45
   - Sourced from the existing `cueCards.Calm Cue` rich_text field
   - Italic on the word `alive` is from the source data — render any
     `*foo*` markdown in the source as italic

4. **Prep checklist**
   - Source: parse bullets from `cueCards.Current Bullets` (newline-joined)
   - Row: 14pt checkbox + label
   - Checkbox: 14×14pt rounded-rect 4pt radius, 1pt border `ink4`
   - Checked: fill + border = `sage600`, 10pt white ✓
   - Checked label: `ink3`, strikethrough, strike colour `ink4`
   - Tap toggles **local** state — do not write back to Notion (this
     keeps the demo low-stakes)

5. **Action row** — flex, gap 6pt
   - Primary: `↗ Open in Notion` — pill `sage600`, white text 12pt semibold
   - Ghost: `Snooze 5m` — pill `rgba(255,255,255,0.08)`, `ink` text
   - Right side meta: `[!cue] · Hackathon · agenda.md` — 11pt `ink3`

## Data binding

Reuse the existing `CueCard` model from `Models/NotchSummary.swift`.
**New fields needed** — none. The prep checklist parses
`currentBullets`, the body line is `calmCue`, the meeting time is
`currentTime`. Pin Maya & Theo style attendee strings to the **last
30 chars of `currentHeading`** for now; later split into a separate
`Attendees` rich_text.

## Open in Notion

Reuse the existing deeplink pattern from `CueRow.swift`:
```swift
URL(string: "notion://www.notion.so/\(sourcePageId.replacingOccurrences(of: "-", with: ""))")
```

## Snooze 5m

Local-only state. Increment `currentTime` by 5 min in the manager and
mark `snoozedAt = Date()`. Don't post anywhere — the cue worker will
re-derive the right value on the next poll (1 min interval).

## Accessibility

- Outer expanded view: `.accessibilityElement(children: .contain)`
- Each checklist row: `.accessibilityLabel("Prep: \(label)")`, hint
  `"Tap to toggle"`
- Time strip combines as: `"10:30 AM. In 12 minutes. With Maya and Theo."`

## Mascot

`.calm` by default. Switches to `.alert` (the sparkle pose) when
`minutesUntilNext < 5`. Bobble animation fires once when the user
finishes the last checklist item (delightful prep-complete moment).
