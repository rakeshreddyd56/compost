# Compost Notch v0.5 — Handoff Index

Quick reference. Read `README.md` first for context.

```
handoff_notch_v05/
│
├── README.md                       Overview, fidelity, boundaries
├── CLAUDE_CODE_PROMPT.md           ★ Paste this into Claude Code ★
├── COPY.md                         Every user-facing string
├── INTERACTIONS.md                 Timing, easing, state machines
├── INDEX.md                        you are here
│
├── tokens/
│   └── DESIGN_TOKENS.md            Colors, type, spacing, radii
│
├── scenarios/
│   ├── 01-cue.md                   First meeting prep (+ Gmail / Meet invite)
│   ├── 02-drafts.md                Sleep-on-it + tone picker
│   ├── 03-voice.md                 Mascot voice mode (with cross-scene routing)
│   └── 04-photos.md                Memory pile slideshow + mascot self-sighting
│
├── swiftui/
│   └── SWIFTUI_MAPPING.md          Per-file diff plan for app/
│
├── prototype/
│   ├── index.html                  Run this in a browser
│   ├── styles.css
│   ├── components.jsx
│   ├── scenes.jsx
│   ├── app.jsx
│   ├── tweaks-panel.jsx
│   └── assets/                     Mascot PNGs + sample photos
│
└── assets/
    ├── README.md                   What each file is + where it ships
    ├── mascot-calm.png             ┐
    ├── mascot-nudging.png          ├ ship these (already in xcassets)
    ├── mascot-alert.png            │
    ├── mascot-sweep.png            ┘
    ├── mascot-base.png             fallback
    ├── mascot-sheet.png            reference only (do not ship)
    ├── mascot-key.png              reference only (do not ship)
    ├── photo-soma-1.jpeg           ┐
    ├── photo-soma-2.jpeg           │
    ├── photo-dustbin.jpeg          ├ sample photos for Memory pile preview
    ├── photo-poster-hermanmiller.jpeg
    └── photo-poster-peugeot.jpeg   ┘
```

## How to use

### If you're a designer reviewing this

1. Open `prototype/index.html` in any browser
2. Use the bottom dock to step through scenarios — or the **flow map**
   on the left side to follow the end-to-end demo path
3. Tweaks panel (top-right) flips wallpaper, notch finish, etc; includes
   a "🌱 Run end-to-end demo" button that walks the full path automatically

### If you're an engineer implementing this

1. Paste `CLAUDE_CODE_PROMPT.md` into Claude Code at the repo root
2. Claude Code will read this bundle and propose a PR plan
3. Review the plan, give "go", then review each scenario PR in order:
   Cue → Voice → Photos → Drafts

### If you're updating this handoff

1. Update `prototype/` first (run the prototype, confirm it works)
2. Update the scenario spec in `scenarios/`
3. Update `COPY.md` if any string changed
4. Update `INTERACTIONS.md` if any timing changed
5. Update `swiftui/SWIFTUI_MAPPING.md` if the implementation plan changed
6. Bump the version in `README.md`'s title

## Versions

| Version | Date | Notes |
|---|---|---|
| 0.4 | 2026-05-16 | Initial handoff: Cue, Drafts, Voice, Invoice |
| 0.5 | 2026-05-16 | Replaced Invoice with **Photos / Memory pile** (slideshow + mascot self-sighting); added **Gmail / Meet invite row** to Cue; wired **inter-scene navigation** (voice quick-actions route to their target surface; flow-map dock visualises the path). Prototype is now fully end-to-end clickable. |
