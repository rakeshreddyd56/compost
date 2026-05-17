# Scenario 03 — Voice (talking to the mascot)

> Surface: net-new. Add `app/Views/VoiceView.swift`. Plumb wake trigger
> via existing `app/WakeTrigger.swift`. Mascot becomes a live agent
> on the notch.

## Why

Compost's thesis is a workspace with a sense of time, surfaced through
a calm UI. Voice is the only macOS surface where a user can ask
"what's on the pile?" without breaking flow — keyboard + window
attention belongs to whatever they were already doing.

The notch is the only system surface that can host this without
stealing focus. The mascot is the listener; the waveform is the
feedback; the transcript is the receipt.

## States

The voice mode is a 4-step state machine that loops:

```
idle ──hotkey / "hey compost"──> listening ──silence 800ms──> thinking
thinking ──claude.complete──> speaking ──TTS done──> idle (auto-collapse after 4s)
```

### A. Peek

```
┌──────────────────────────────────────┐
│ ● LIVE   ░▒█▓█▒░▒█▓█▒░    [listening] │
└──────────────────────────────────────┘
```

- Width 300pt, height 38pt
- Left: red `accentRose` "● LIVE" indicator — 7pt dot pulsing
- Center: live waveform (20 bars, ~24pt tall)
- Right: chip — text changes by stage:
  - `listening` (rose tint)
  - `thinking` (amber tint)
  - `speaking` (sage tint)

### B. Expanded

```
┌──────────────────────────────────────────────────────────────┐
│  ┌─────┐    ● LISTENING                                      │
│  │ 🌱  │    hey compost, what's on the pile this morning…|   │
│  │     │    ░▒█▓█▒░▒█▓█▒░▒█▓█▒░▒█▓█▒░▒█▓█▒░▒█▓█▒░▒█▓█▒░▒    │
│  │     │    [Tidy now] [What did I miss?] [Read drafts]      │
│  │     │                                       [Tap to end]  │
│  └─────┘                                                     │
└──────────────────────────────────────────────────────────────┘
```

- Outer: 440pt wide, auto height (≈160pt), bottom radius 22pt
- Padding: 14×16

#### Components

1. **Mascot slot** — 96×96pt, with a sage halo behind it
   - Halo: radial gradient, `rgba(135,168,119,0.20) → transparent`, 8pt
     blur, animates `glowPulse` (scale 0.95↔1.05, opacity 0.5↔1, 2.5s
     ease-in-out infinite, gated on `reduceMotion`)
   - Mascot mood:
     - `listening` → `.calm` with a tiny "head tilt" (rotate ±2° 1.6s
       sin-loop)
     - `thinking` → `.calm`
     - `speaking` → `.nudging`, with a `.bobble` once at the start of
       speech (0.7s spring) — same bobble we use elsewhere

2. **State pill** — top-left of body
   - Eyebrow style: 10.5pt 700 uppercase, +1pt tracking
   - With a 6pt dot prefix, dot pulses (1s) and is colored by stage:
     - listening → `accentRose`
     - thinking → `accentAmber`
     - speaking → `sage400`
   - Label: `Listening` / `Thinking` / `Compost` / `Compost · finished`

3. **Transcript** — 15pt SF Pro Rounded medium, line-height 1.35
   - Listening: types out the user's recognized text live, with a sage
     blinking caret. Use `SFSpeechRecognizer`'s partial results.
   - Thinking: italic `ink3` "checking the pile…"
   - Speaking: types out Claude's response progressively (24ms/char) so
     the user reads at speaking pace. The actual TTS may run in
     parallel via `AVSpeechSynthesizer`.

4. **Waveform** — 42 bars, 26pt tall
   - Bars 3pt wide, 3pt gap, 2pt radius
   - Animated via `requestAnimationFrame`-equivalent (CADisplayLink in
     SwiftUI). On a Mac with no input audio, fall back to a 2-sin mix
     animation purely for visual life (the prototype's pattern).
   - Color: `sage400` during thinking / speaking; `accentRose` during
     listening.
   - When the user is actually speaking, real RMS amplitude drives the
     envelope.

5. **Quick-action row** — flex, gap 6pt
   - Three ghost-button pills with stable intents:
     - `Tidy now` → calls existing `tidyNow` tool
     - `What did I miss?` → expands the "Up next" cue inline
     - `Read drafts` → switches to the Drafts scenario
   - Pushed right: muted text button `Tap to end` — closes voice mode
   - These are "fallback hands" — if voice fails, the user has buttons.

## Wake trigger

`app/WakeTrigger.swift` already exists. Extend it to:
- Listen for a global hotkey (configurable; default `⌥⌘V`)
- Optional: a "Hey Compost" hotword via a local Porcupine-style model.
  Skip for the hackathon — hotkey is enough.

When triggered, post a `voiceStarted` notification through
`NotchManager` which transitions the notch into voice expanded state
**regardless of what was previously shown**. The previously shown
state is restored after voice mode ends.

## Speech recognition

Use Apple's `SFSpeechRecognizer` with on-device recognition where
available:

```swift
let recognizer = SFSpeechRecognizer(locale: .current)
recognizer?.supportsOnDeviceRecognition  // prefer true
```

Privacy:
- Request microphone permission only when voice mode is first invoked
- **Do not persist** audio or transcripts to disk
- The Notion page is not modified by voice — voice is a query surface

## LLM call

Use the existing `claude-haiku-4-5` configuration. The system prompt
should be calm and short:

```
You are Compost, a small ambient assistant living in a Mac notch.
Answer in 2–3 short sentences. You can reference the user's pending
Notion items by reading the NotchSummary context. Never invent
content. If you don't know, say so.
```

Pass the current `NotchSummary` as a structured `<context>` blob.

## TTS

`AVSpeechSynthesizer` with a soft voice (Samantha / Tom in en-US).
Pause at sentence boundaries. Cancel TTS immediately if the user starts
speaking again.

## Auto-collapse

After 4s of `idle` (speaking finished, no follow-up speech detected),
the notch returns to its previous peek/expanded state. Cancellable by
any user interaction.

## Tap to end

Tapping anywhere on the notch (or the explicit "Tap to end" button)
flushes the recognizer, stops TTS, and collapses the surface.

## Accessibility

- The voice surface should be **fully reachable from keyboard** as a
  fallback — the hotkey opens it; ⏎ submits; ⎋ closes
- VoiceOver should announce stage transitions:
  `"Compost is listening"`, `"Compost is thinking"`, then the response
- Mascot stays `.accessibilityHidden(true)`
- The waveform is decorative — `accessibilityHidden(true)`

## Mascot

- `listening`: `.calm`
- `thinking`: `.calm`
- `speaking`: `.nudging` with one-shot `.bobble` at speech start
- Halo only renders in voice mode (it's the surface's signature)

## What this scenario does NOT do (yet)

- Cross-app context (no reading Slack, no reading Mail)
- Voice-driven Notion mutations (cannot say "apply that proposal")
- Multi-turn conversations — each invocation is one round-trip
- Custom wake word — hotkey only for the hackathon
