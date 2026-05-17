# Scenario 02 — Drafts (Sleep-On-It + tone picker)

> Surface: refines existing `app/Views/DraftRow.swift`. Net-new: hero
> calmer pane (instead of "Compare" button), tone picker, rephrase tool.

## Why

The current Drafts row leads with the **original**, hides the rewrite
behind a "Compare" button, and offers a binary "Keep mine / Use calmer".

v0.4 inverts this:
1. The **calmer rewrite is the hero** — that's the offer.
2. The original is still visible but compressed (one column).
3. A **tone picker** (Calmer / Crisp / Diplomatic) lets the user shape
   the rewrite without typing.
4. Comparison happens **side-by-side, always visible** in the expanded
   state — no toggle needed.

The list of frozen drafts moves to the top of the expanded card so the
user can scrub between 3 drafts without leaving the notch.

## States

### A. Peek

```
┌──────────────────────────────────────┐
│ 🌱  3 drafts on ice    ╱ review ╲   │
└──────────────────────────────────────┘
```

- Width 300pt, height 38pt
- Label: `3 drafts on ice` — pluralize properly
- Chip: amber, text `review`
- Mascot mini: `.nudging`

If 0 drafts, the section is hidden in `ExpandedView` (existing behavior).

### B. Expanded — wide

```
┌──────────────────────────────────────────────────────────────────┐
│ 🌱  🌙 SLEEP-ON-IT · 3 FROZEN DRAFTS                          ✕  │
│     Morning review                                               │
│                                                                  │
│ ┌──── Re: Q2 contractor scope ───── [frozen] ─────── 1:47 AM ──┐ │
│ │ ← selected                                                   │ │
│ └──────────────────────────────────────────────────────────────┘ │
│ ┌──── Hackathon retro thoughts ──── [frozen] ─────── 2:14 AM ──┐ │
│ └──────────────────────────────────────────────────────────────┘ │
│ ┌──── Note to self · pricing page ── [frozen] ────── 12:53 AM ─┐ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ ┌── ORIGINAL · 1:47 AM you  raw ──┬── CALMER REWRITE   Haiku ──┐ │
│ │ We need this ~~WRAPPED~~ by     │ We're aiming to wrap this  │ │
│ │ Friday or the whole launch      │ by Friday so the launch    │ │
│ │ ~~FALLS~~ APART. I'm not going  │ holds. Could you share     │ │
│ │ to keep chasing you — just      │ where things stand and     │ │
│ │ ~~GET~~ it done.                │ what would help you finish?│ │
│ └─────────────────────────────────┴────────────────────────────┘ │
│                                                                  │
│  Tone  [Calmer]  Crisp  Diplomatic   ↻ rephrase                  │
│                              [Keep mine]  [✓ Use calmer]         │
└──────────────────────────────────────────────────────────────────┘
```

#### Layout

- Outer: 540pt wide (the wide variant), auto height
- Padding: 14pt top, 16pt sides, 14pt bottom
- Vertical gap: 12pt

#### Components

1. **Head row** — same pattern as Cue
   - Mascot 36pt, mood `.nudging`
   - Eyebrow: `🌙 SLEEP-ON-IT · {count} FROZEN DRAFTS`
   - Title: `Morning review`

2. **Draft list** — vertical stack of selectable rows
   - Row: padding `9×12`, radius 12pt, hairline border `rgba(255,255,255,0.10)`
   - Background: `rgba(255,255,255,0.05)`, hover `rgba(255,255,255,0.08)`
   - Selected: bg `rgba(79,121,66,0.16)`, border `rgba(135,168,119,0.5)`
   - Row content (single line, baseline-aligned):
     - Title — 12pt SF Pro Rounded semibold `ink`
     - `frozen` tag — `rgba(255,255,255,0.06)` pill, 10.5pt; sage tint when selected
     - frozenAt time — pushed right, `ink3` 11pt

3. **Diff pane** — 2 columns, equal width, gap 8pt
   - Each column: padding 10pt, radius 8pt, hairline border, min-height 80pt, max-height 130pt with internal scroll
   - **Original column** (left): bg `rgba(255,255,255,0.05)`, border hairline
     - Diff label: `ORIGINAL · 1:47 AM you` + right "raw" — 9.5pt 700
       uppercase, `ink3`, tracking +0.8pt
     - Shouty words (all-caps, len ≥ 4): `accentRose` + strikethrough
     - Reuse the `ToneDiff` logic already in `DraftRow.swift`
   - **Calmer column** (right): bg `rgba(79,121,66,0.10)`, border `rgba(135,168,119,0.30)`
     - Diff label: `{TONE} REWRITE` + right "Haiku" — sage300
     - Novel words (in calmer but not in original, len > 3, not in
       stopword list): `sage300` + semibold

4. **Tone picker row** — flex, wrap, gap 6pt
   - `Tone` label — 11pt `ink3`
   - Three tone pills: `Calmer · Crisp · Diplomatic`
     - Off: bg `rgba(255,255,255,0.05)`, text `ink2`
     - Hover: bg `rgba(255,255,255,0.10)`
     - On: bg `rgba(135,168,119,0.20)`, border `rgba(135,168,119,0.40)`,
       text `sage300`
   - `↻ rephrase` pill — same off-style; clicking re-runs the same tone
     for a fresh rephrasing
   - Pushed right: `Keep mine` (ghost) + `✓ Use calmer` (primary)

## Data binding

Existing `FrozenDraft` model. **New fields needed:**

| Field | Type | Notes |
|---|---|---|
| `rewrites: [String: String]` | dictionary | keyed by tone name; `Calmer / Crisp / Diplomatic` |
| `activeTone: String` | rich_text | last tone the user picked (default `Calmer`) |

The current `rewrite: String` becomes a computed property:
`rewrites[activeTone] ?? rewrite`.

## Worker contract — propose in `INTERFACE.md`

```typescript
// New tool — propose in INTERFACE.md, do not implement
rephraseDraft:
  input:  { draftId: string, tone: "Calmer" | "Crisp" | "Diplomatic" }
  output: { ok: boolean, rewrite: string, error: string | null }

  Worker behavior:
  - Look up frozenDrafts row by Draft ID = draftId
  - Read Original Snapshot
  - Call Claude with a tone-specific system prompt
  - Write the result into Rewrite (overwrite) AND into a new field
    Rewrite Variants (JSON dictionary { tone: text }) so we keep history
  - Update Active Tone to the new tone
  - Return { ok: true, rewrite }
```

The app calls this when the user picks a different tone OR clicks
`↻ rephrase`. While the call is in flight, the calmer pane shows a
shimmer overlay; on success it crossfades to the new text (180ms).

## Approve / Reject

Unchanged. `reviewDraft({ draftId, decision: "approve" | "reject" })`.

## Mascot

`.nudging` whenever the panel is expanded. Switches to a quick
`.calm` bobble when the user clicks `Use calmer` — the "thanks, I
took your gentler version" beat.

## Accessibility

- Each draft row: `.accessibilityLabel("\(title), frozen at \(time)")`,
  hint `"Tap to compare"`
- Diff pane: `.accessibilityElement(children: .contain)`,
  label `"Original on left, \(tone) rewrite on right"`
- Tone pills: standard `accessibilityValue("\(tone), \(isSelected ? "selected" : "")")`
- Read-aloud should prefer the calmer text — VoiceOver users get the
  helpful version first.

## State machine

```
idle ──tap draft──> draft-selected
draft-selected ──tap tone──> rephrasing(tone)
rephrasing ──worker ok──> draft-selected (rewrite swapped)
rephrasing ──worker error──> draft-selected + inline error banner
draft-selected ──Keep mine──> reviewDraft(reject) ──> dismissed
draft-selected ──Use calmer──> reviewDraft(approve) ──> dismissed
```

Errors render in the existing red banner pattern from `DraftRow.swift`.
