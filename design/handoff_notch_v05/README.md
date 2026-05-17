# Handoff — Compost Notch Interactions v0.5

> A four-scenario expansion of the Compost macOS notch UI:
> **Cue · Drafts · Voice · Photos (Memory pile)**.

This bundle is the **design reference** for implementing four new notch
interaction surfaces in `compost/app/` — the SwiftUI/AppKit macOS client
that already exists at `compost/app/CompostApp.swift` and is wired to
`DynamicNotchKit` and the Notion Workers in `compost/workers/`.

The HTML in `prototype/` is **not production code to copy**. It is a
high-fidelity behavioral spec: exact colors, layouts, copy, timing, and
state machines, captured in a medium that's easy to interact with. Your
job is to re-implement those interactions in SwiftUI using the patterns
already established in `app/Views/`, `app/GardenStyle.swift`, and
`app/NotchManager.swift`.

---

## Quick start for Claude Code

1. Drop this folder anywhere inside the Compost repo — recommended path:
   `compost/design/handoff_notch_v04/`.
2. Open `CLAUDE_CODE_PROMPT.md` and paste it as your first message in a
   Claude Code session.
3. The prompt tells Claude Code to:
   - read this README and the per-scenario specs in `scenarios/`
   - implement each scenario as a new `Views/` SwiftUI view
   - extend `NotchManager` and `NotchSummary` with the new state
   - reuse mascot assets via the existing `Mascot.swift` (no new image targets needed for the four mood pngs — already in `Assets.xcassets`)
4. Review per-scenario diffs in PRs, merge in this order:
   `Cue refinements (incl. Gmail row) → Voice → Photos → Drafts tone-picker`.
   Cue and Drafts already exist in `Views/`; this handoff refines them.
   Voice and Photos are net-new.

---

## Fidelity

**High-fidelity** for visual + interaction design.
- Exact color values match `GardenStyle.swift` where possible (sage
  `#4F7942`, etc.) and extend it for cream / gold / rose tones used in
  Voice and Invoice. Full token list in `tokens/DESIGN_TOKENS.md`.
- Exact layouts, paddings, and corner radii are documented in
  `scenarios/<name>.md` with both pixel measurements and the equivalent
  `GardenStyle` constants.
- Exact copy is in `COPY.md` — paste verbatim, then localize.
- Timing/easing for every animation is in `INTERACTIONS.md`.

**Low-fidelity** for:
- Wallpaper / desktop window stubs in the prototype. These exist only to
  show the notch in context; do not implement.
- The "MacBook bezel" rendering — your app runs on a real notch, so
  there is no bezel to render.

---

## What's in this bundle

```
handoff_notch_v04/
├── README.md                      ← you are here
├── CLAUDE_CODE_PROMPT.md          ← paste this into Claude Code
├── COPY.md                        ← every string, verbatim
├── INTERACTIONS.md                ← timing, easing, state machines
├── tokens/
│   └── DESIGN_TOKENS.md           ← colors, type, spacing, radii
├── scenarios/
│   ├── 01-cue.md                  ← first meeting prep (+ Gmail / Meet invite)
│   ├── 02-drafts.md               ← sleep-on-it + tone picker
│   ├── 03-voice.md                ← talking to the mascot
│   └── 04-photos.md               ← memory pile slideshow + mascot self-sighting
├── swiftui/
│   └── SWIFTUI_MAPPING.md         ← per-file changes in compost/app/
├── prototype/
│   ├── index.html                 ← runnable HTML reference
│   ├── styles.css
│   ├── components.jsx
│   ├── scenes.jsx
│   ├── app.jsx
│   └── tweaks-panel.jsx
└── assets/
    ├── mascot-calm.png            ← already in Assets.xcassets
    ├── mascot-nudging.png         ← already in Assets.xcassets
    ├── mascot-alert.png           ← already in Assets.xcassets
    ├── mascot-sweep.png           ← already in Assets.xcassets
    └── mascot-sheet.png           ← reference sheet, not for shipping
```

---

## Why these four scenarios?

The existing app surfaces three things from Notion managed databases:
**Cue** (current/next page moment), **Gardener** (cleanup proposals),
and **Sleep-On-It** (frozen late-night drafts). The notch UI in v0.3 is
list-shaped — every section is a stack of rows.

v0.4 pushes the notch closer to a **live activity**:

| Scenario | What the user sees | Why a notch? |
|---|---|---|
| **Cue** | A countdown + meeting prep checklist + the Calendar/Gmail invite | The notch already pulses for imminent cues — extend it into a real prep surface, with one-tap Join Meet so the user doesn't have to dig through Gmail |
| **Drafts** | One frozen draft, side-by-side, with a tone picker | The current side-by-side is buried behind a "Compare" toggle. v0.4 makes the calmer rewrite the hero, and adds the missing primitive: **rephrasing in a chosen tone** |
| **Voice** | The mascot reacts to your voice | Hands-free morning check-in. The notch is the only macOS surface where this can live without stealing focus. Quick-actions actually **navigate to the matching surface** so voice becomes a router. |
| **Photos** | A slideshow of yesterday's photos from your Notion `Memory pile`, with the mascot reacting when its own logo shows up in one of them | The notch is the right ambient surface for time-aware looking-back. The mascot self-sighting easter-egg is a brand moment — when a public Compost bin shows up in a photo, the mascot says "yes — that's me!" |

Drafts + Cue are refinements of existing files (`Views/CueRow.swift`,
`Views/DraftRow.swift`). Voice + Photos are new and need plumbing
through `NotchManager` and `NotchSummary`. See
`swiftui/SWIFTUI_MAPPING.md` for the diff plan.

---

## Boundaries (do not cross)

These came directly from `compost/AGENTS.md` and `compost/INTERFACE.md`.
Claude Code must respect them.

1. **Nothing auto-deletes in user's Notion.** Invoice pay = stamp
   `Applied=true` on the Notion row; do not silently mutate other pages.
2. **Worker contracts live in `INTERFACE.md`.** If Voice or Invoice
   needs a new tool, propose the signature in `INTERFACE.md` first,
   commit, then implement on either side.
3. **Storage = Notion managed databases only.** No external DB for
   transcripts, voice audio, invoice metadata, etc. Voice transcripts
   are ephemeral.
4. **Ownership boundary:** `compost/app/**` is owned by Claude Code.
   `compost/workers/**` is owned by Codex. Cross-tree work needs a
   handoff via `INTERFACE.md`.

---

## Open questions (please answer before starting)

1. **Voice — speech-to-text source?** Apple Speech framework
   (`SFSpeechRecognizer`) is the default. If you want Whisper on-device
   via `whisper.cpp`, that's a different package add and we should
   confirm before wiring.
2. **Photos — Notion schema.** The prototype assumes a managed DB
   `compostPile/Memory pile` with fields { Photo ID, Caption, Place,
   Time, Latitude, Longitude, Asset (files), Tags, Mascot Reaction }.
   Logo detection for the `self-sighting` reaction is **out of scope
   for v0.4** — for the demo it triggers on a `compost-sighting`
   user-applied tag. Confirm the schema in `INTERFACE.md`.
3. **Drafts tone picker — Worker tool or local call?** The cleanest
   path is to add a `rephraseDraft` worker tool that takes
   `{ draftId, tone }` and writes the new rewrite back to the
   `frozenDrafts` row. Cheaper short-term: call Claude directly from
   the app. Recommend the worker path — it matches existing patterns.
4. **Cue — Gmail / Calendar integration.** The prototype shows a
   "From Calendar via Gmail" row + Join Meet button. The cleanest
   path is to read the Notion page's embedded Google Calendar block
   (if present) and surface the Meet link from there. Alternative:
   the user grants a narrow Calendar OAuth read scope. Don't
   build that for v0.4 — render the row from a hard-coded sample
   if the Notion page doesn't have a calendar block.
