# Claude Code Prompt — Compost Notch v0.5

> **How to use:** open Claude Code at the root of the Compost repo
> (`cd compost && claude`), then paste everything below the line as
> your first message. The prompt assumes this handoff folder lives at
> `compost/design/handoff_notch_v05/`. Adjust the path on line 1 of the
> prompt if you put it elsewhere.

---

You are working in the **Compost** repo, a macOS notch app for Notion
built for the Notion Developer Platform Hackathon (May 16–17 2026).

I have placed a design handoff bundle at
`design/handoff_notch_v05/`. **Read every file in that folder before
writing any code.** Specifically, read in this order:

1. `design/handoff_notch_v05/README.md`
2. `design/handoff_notch_v05/tokens/DESIGN_TOKENS.md`
3. `design/handoff_notch_v05/swiftui/SWIFTUI_MAPPING.md`
4. `design/handoff_notch_v05/scenarios/01-cue.md`
5. `design/handoff_notch_v05/scenarios/02-drafts.md`
6. `design/handoff_notch_v05/scenarios/03-voice.md`
7. `design/handoff_notch_v05/scenarios/04-photos.md`
8. `design/handoff_notch_v05/INTERACTIONS.md`
9. `design/handoff_notch_v05/COPY.md`

Then read the existing app context:

- `AGENTS.md` / `CLAUDE.md` — hard rules, ownership boundaries
- `INTERFACE.md` — Worker tool contracts (the cross-component spec; do
  not implement Worker changes, but propose signature edits here if
  needed and stop for confirmation)
- `app/CompostApp.swift`, `app/NotchManager.swift`,
  `app/Models/NotchSummary.swift`, `app/GardenStyle.swift`
- Every file in `app/Views/`

## Your scope

You own `app/**` per `AGENTS.md`. Do **not** modify `workers/**`.
If a worker change is needed (e.g. for the tone-rephrase tool or an
invoice apply tool), edit `INTERFACE.md` to add the proposed signature
and stop — wait for confirmation before assuming the worker side is in.

## What to build

Implement four notch interaction surfaces, mapped to existing models
where possible. The two existing scenarios (Cue, Drafts) get refined;
two are new (Voice, Invoice).

| Scenario | Status in app | Files to touch |
|---|---|---|
| **Cue** | Exists as `Views/CueRow.swift` | Refine: add the prep checklist, the calm-cue rephrasing, the time-strip pattern, and the new **Gmail / Calendar invite row + Join Meet button** from `scenarios/01-cue.md` |
| **Drafts** | Exists as `Views/DraftRow.swift` | Refine: promote the calmer rewrite from "behind Compare" to the hero pane; add a tone picker (Calmer / Crisp / Diplomatic) wired to a new `rephraseDraft` worker tool — propose in `INTERFACE.md` |
| **Voice** | New | Add `Views/VoiceView.swift`, `WakeTrigger.swift` integration, mascot waveform state, SFSpeechRecognizer pipeline. Quick-actions should **navigate to the matching surface** (so voice becomes a router into Drafts/Cue/Photos). Do **not** persist transcripts. |
| **Photos** | New | Add `Views/PhotosView.swift`, extend `NotchSummary` with `memoryPile: [Photo]`, propose `compostPile/Memory pile` managed DB in `INTERFACE.md`, propose `tagPhoto` tool. The headline detail: **mascot self-sighting** — when a photo is tagged `compost-sighting`, the mascot reacts with a speech bubble overlay. |

See `swiftui/SWIFTUI_MAPPING.md` for the file-by-file diff plan with
exact symbol names.

## Hard rules (from AGENTS.md)

1. **Nothing auto-mutates in user's Notion.** All destructive actions
   require an approval action in the notch and stamp `Applied=true`
   idempotently.
2. **Storage = Notion managed databases only.** No SQLite/Postgres/Redis.
3. **Worker contracts live in `INTERFACE.md`.** Update first, commit,
   then implement.
4. **Reuse `GardenStyle` tokens.** Do not introduce new color literals
   that conflict with the sage palette. Adding new tokens
   (`accentGold`, `accentRose`, `accentSky`) **is** expected — see
   `tokens/DESIGN_TOKENS.md` — extend `GardenStyle.swift` rather than
   sprinkling literals.

## Working agreement

- Commit every 30–60 min using the convention `[app] ...`.
- Run the app between commits — never commit a build that doesn't
  compile.
- Match the existing accessibility pattern: every interactive view
  gets `.accessibilityLabel`/`.accessibilityHint`. Decorative mascot
  views stay `.accessibilityHidden(true)`.
- Match the existing reduce-motion gate via `GardenStyle.reduceMotion`.
- Mascot moods route through the existing `Mascot.swift` enum
  (`.calm / .nudging / .alert / .sweep`). New mood states should reuse
  these — do not add new image assets.
- Print-style debug logs are fine during dev; remove before commit.

## Deliverable

A PR (or series of PRs) per scenario, each with:
- Code changes scoped to `app/`
- `INTERFACE.md` edits for any new worker contract (do not implement
  the worker side)
- A 1-minute screen recording of the scenario working in the notch
- A short test note: how you faked the data locally to exercise the UI

## Order of work

Recommend tackling in this order so each PR is reviewable:

1. **Cue refinement** — smallest diff, exercises the design tokens.
   Includes the Gmail / Calendar invite row + Join Meet button.
2. **Voice** — new surface, no Notion writes, lowest risk. Wire the
   quick-actions to switch the notch surface (it's a router).
3. **Photos** — needs new managed DB schema in `INTERFACE.md`; pause
   for confirmation after that edit before writing the SwiftUI.
   Worker-side logo detection is **out of scope** — `self-sighting`
   reaction triggers on a user-applied `compost-sighting` tag.
4. **Drafts tone picker** — needs new worker tool; pause after the
   `INTERFACE.md` edit.

## When you're done reading the handoff

Reply with:
1. A one-paragraph summary of what you understood from the handoff
2. The list of `INTERFACE.md` edits you intend to propose
3. The order in which you'll attack the PRs
4. Any questions about the open questions section of the README

Then wait for my "go" before writing code.
