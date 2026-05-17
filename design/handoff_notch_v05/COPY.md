# Copy — Compost Notch v0.4

> Every user-facing string in the prototype, in one place.
> Paste verbatim, then localize. Strings are grouped by scenario.

## Global

| Key | English |
|---|---|
| `notch.close.a11y` | `Close` |
| `notch.expand.a11y` | `Expand` |
| `notch.collapse.a11y` | `Collapse` |
| `meta.openInNotion` | `Open in Notion` |
| `meta.openInNotion.a11y` | `Open in Notion` |
| `error.generic` | `Something went sideways. Try again in a moment.` |

## Cue

### Peek

| Key | English |
|---|---|
| `cue.peek.chip.normal` | `in {minutes}m` |
| `cue.peek.chip.imminent` | `in {minutes}m` (amber tint when <10) |
| `cue.peek.chip.now` | `now` |

### Expanded

| Key | English |
|---|---|
| `cue.eyebrow` | `☀ UP NEXT · {time}` |
| `cue.title.fallback` | `(your next moment)` |
| `cue.countdown.full` | `in {minutes} min · {duration}` |
| `cue.countdown.solo` | `in {minutes} min` |
| `cue.invite.title` | `From Calendar via Gmail` |
| `cue.invite.attendees` | `{name1} & {name2} · accepted · {count} attendees` |
| `cue.invite.attendees.solo` | `{name1} · accepted` |
| `cue.invite.btn.joinMeet` | `Join Meet` |
| `cue.invite.btn.joinMeet.a11y` | `Join the Google Meet for this event` |
| `cue.btn.openInNotion` | `↗ Open in Notion` |
| `cue.btn.snooze` | `Snooze 5m` |
| `cue.btn.askCompost` | `Ask Compost ↗` |
| `cue.btn.askCompost.a11y` | `Switch the notch into voice mode to ask about this event` |
| `cue.meta.suffix` | `[!cue] · {sourceTitle}` |
| `cue.checklist.empty` | `No prep items in this page — just show up.` |
| `cue.toast.openedNotion` | `Opened {sourceTitle} in Notion` |
| `cue.toast.joiningMeet` | `Joining Google Meet…` |
| `cue.toast.snoozed` | `Snoozed — back in 5m` |

### Sample copy (sample data — feel free to swap)

- Title: `App shell checkpoint`
- Body line: `You promised the notch would feel *alive* by today. Maya is bringing the worker logs.`
- Checklist:
  - `Skim last week's notes`
  - `Pull the Figma file`
  - `Decide on top 2 questions`
  - `Open the Loom from yesterday`

## Drafts

### Peek

| Key | English |
|---|---|
| `drafts.peek.label` | `{count} {drafts} on ice` |
| `drafts.peek.label.singular` | `1 draft on ice` |
| `drafts.peek.label.plural` | `{count} drafts on ice` |
| `drafts.peek.chip` | `review` |

### Expanded

| Key | English |
|---|---|
| `drafts.eyebrow` | `🌙 SLEEP-ON-IT · {count} FROZEN DRAFTS` |
| `drafts.title` | `Morning review` |
| `drafts.row.tag` | `frozen` |
| `drafts.row.frozenAtFmt` | `{HH:mm a}` |
| `drafts.diff.original.label` | `ORIGINAL · {time} you` |
| `drafts.diff.original.suffix` | `raw` |
| `drafts.diff.calmer.label` | `{TONE} REWRITE` |
| `drafts.diff.calmer.suffix` | `Haiku` |
| `drafts.tone.label` | `Tone` |
| `drafts.tone.calmer` | `Calmer` |
| `drafts.tone.crisp` | `Crisp` |
| `drafts.tone.diplomatic` | `Diplomatic` |
| `drafts.tone.rephrase` | `↻ rephrase` |
| `drafts.btn.keepMine` | `Keep mine` |
| `drafts.btn.use` | `✓ Use {tone}` |
| `drafts.btn.use.help` | `Approve the rewrite — Notion page gets updated` |
| `drafts.btn.keepMine.help` | `Reject the rewrite and keep your original` |

### Sample drafts (3 used in prototype)

#### Draft 1 — `Re: Q2 contractor scope` (1:47 AM)
- Original: `We need this WRAPPED by Friday or the whole launch FALLS APART. I'm not going to keep chasing you — just GET it done.`
- Calmer: `We're aiming to wrap this by Friday so the launch holds. Could you share where things stand and what would help you finish?`
- Crisp: `Need this complete by Friday for the launch. What's blocking you, and how can I help?`
- Diplomatic: `Friday is our launch checkpoint and we'd love to land this by then. Want to find a 15-minute window to align on what's left?`

#### Draft 2 — `Hackathon retro thoughts` (2:14 AM)
- Original: `Honestly the whole demo workflow is BROKEN. Nobody tested it. I am DONE babysitting deploys for people who refuse to read the runbook.`
- Calmer: `The demo workflow snagged a few times today, mostly around deploys. Could we walk through the runbook together next time to surface what's missing?`
- Crisp: `Demo workflow is fragile, especially around deploys. Want to do a runbook review so the next pass is smoother?`
- Diplomatic: `I think there's an opportunity to harden the demo workflow — the deploy steps tripped us up. Could we revisit the runbook as a team?`

#### Draft 3 — `Note to self · pricing page` (12:53 AM)
- Original: `ditch the 3-column thing it is UGLY and nobody reads the middle one anyway. start over with literally one button and a price tag`
- Calmer: `The three-column layout isn't landing — the middle tier gets ignored. Try a single, clear price with one CTA and see if it converts better.`
- Crisp: `Three-column pricing isn't working. Test a single-tier page with one price and one button.`
- Diplomatic: `The current three-column pricing may be doing more harm than good. Could be worth A/B testing against a simpler single-tier page.`

## Voice

### Peek

| Key | English |
|---|---|
| `voice.peek.live` | `LIVE` |
| `voice.peek.chip.listening` | `listening` |
| `voice.peek.chip.thinking` | `thinking` |
| `voice.peek.chip.speaking` | `speaking` |

### Expanded

| Key | English |
|---|---|
| `voice.stage.listening` | `Listening` |
| `voice.stage.thinking` | `Thinking` |
| `voice.stage.speaking` | `Compost` |
| `voice.stage.idle` | `Compost · finished` |
| `voice.placeholder.thinking` | `checking the pile…` |
| `voice.quick.tidyNow` | `Tidy now` |
| `voice.quick.recap` | `What did I miss?` |
| `voice.quick.drafts` | `Read drafts` |
| `voice.btn.end` | `Tap to end` |
| `voice.permission.prompt` | `Compost would like to listen for short voice commands when you press ⌥⌘V. Audio is not stored.` |
| `voice.error.noMic` | `No microphone access. Enable in System Settings → Privacy & Security → Microphone.` |
| `voice.error.noSpeech` | `Speech recognition isn't available right now.` |

### Sample script (for prototype demo loop)

The voice scene has two scripts. The default one runs when voice is
launched from the hotkey; the photos one runs when launched from the
Photos surface's "Ask about this" button.

#### Default script

1. User says: `hey compost, what's on the pile this morning…`
2. (mascot thinks)
3. Compost says: `Three things. Maya's checkpoint in twelve minutes. Two drafts you wrote at 2 AM. And five photos from yesterday's walk waiting in Memory pile.`

#### Photos script (entered from Photos surface)

1. User says: `compost, what photos did i take yesterday around the gallery?`
2. (mascot thinks)
3. Compost says: `Five from SoMa between 2:30 and 3:15 PM. Two skyline shots near the Salesforce Tower, two posters from the Herman Miller gallery, and — heh — you caught my logo on a trash can.`
4. (idle): `Tap the Photos tab to flip through them.`

## Photos (Memory pile)

### Peek

| Key | English |
|---|---|
| `photos.peek.label` | `{count} from {placeShort} {when}` |
| `photos.peek.label.sighting` | `look at this 👀` |
| `photos.peek.chip` | `📷` (gold tint) |
| `photos.peek.chip.sighting` | `+ sighting` |

### Expanded

| Key | English |
|---|---|
| `photos.eyebrow` | `📷 MEMORY PILE · {count} FROM {when}` |
| `photos.title.fallback` | `Untitled location` |
| `photos.caption.line.place` | `📍 {place}` |
| `photos.caption.line.time` | `🕒 {timeLabel}` |
| `photos.btn.openInNotion` | `↗ Open in Notion` |
| `photos.btn.tag` | `+ Tag` |
| `photos.btn.askAboutThis` | `Ask about this ↗` |
| `photos.btn.askAboutThis.a11y` | `Open voice mode pre-primed with this photo cluster` |
| `photos.prev.a11y` | `Previous photo` |
| `photos.next.a11y` | `Next photo` |
| `photos.pause.a11y` | `Pause slideshow` |
| `photos.play.a11y` | `Play slideshow` |
| `photos.dot.a11y` | `Go to photo {n}` |
| `photos.tag.placeholder` | `add a tag, then ⏎` |
| `photos.tag.btn.save` | `Save` |
| `photos.tag.btn.cancel` | `Cancel` |
| `photos.toast.openedNotion` | `Opened Memory pile in Notion` |
| `photos.toast.tagged` | `Tagged "{tag}" · written to Notion` |
| `photos.toast.tagFailed` | `Couldn't save the tag — try again` |
| `photos.bubble.selfSighting` | `yes — that's me! the bin at {place}. logged it.` |
| `photos.bubble.delighted` | `this one's good. tag it for the moodboard?` |
| `photos.bubble.nostalgic` | `oh — this was the day {name} joined.` |

### Sample data (used in prototype)

5 photos from May 15, 2026, 2:32 – 3:11 PM in SoMa, San Francisco:

| # | Caption | Place | Time | Tags | Mascot reaction |
|---|---|---|---|---|---|
| 1 | `Salesforce Tower from 2nd St` | SoMa, San Francisco | 2:32 PM | walk, skyline | — |
| 2 | `Looking up the Salesforce spire` | Mission & 2nd, SF | 2:41 PM | walk, skyline | — |
| 3 | `saw your logo on a bin at Pier 9 ☺` | Pier 9 cafeteria | 2:58 PM | compost-sighting, lol | **self-sighting** |
| 4 | `"Things Are Getting Better All The Time" — Herman Miller, 1980` | MoMA gift shop | 3:08 PM | poster, design-history | **delighted** |
| 5 | `Cycles Peugeot, Roger Pérot, 1931` | MoMA gift shop | 3:11 PM | poster, design-history | — |

## A11y patterns

| Element | Label | Hint |
|---|---|---|
| Cue expanded card | `Up next: {title}, in {minutes} minutes` | `Tap for prep checklist` |
| Cue invite row | `From Calendar via Gmail: {attendees}` | `Tap Join Meet to start the call` |
| Cue Join Meet button | `Join Google Meet for {title}` | — |
| Cue Ask Compost button | `Switch to voice mode` | `Lets you ask about this event hands-free` |
| Cue checklist item | `Prep: {label}` | `Tap to toggle` |
| Draft row | `{title}, frozen at {time}` | `Tap to compare` |
| Tone pill | `{tone} tone, {selected ? "selected" : "not selected"}` | `Tap to change tone` |
| Rephrase button | `Rephrase in {tone} tone` | `Generates a fresh rewrite` |
| Voice mascot slot | (hidden — decorative) | — |
| Voice transcript | `{transcript}` | — |
| Voice quick-action | `{label}, voice quick action` | `Switches the notch to {target surface}` |
| Photo viewer | `{caption}, taken {timeLabel} at {place}` | — |
| Photo prev / next | `Previous photo` / `Next photo` | — |
| Photo pause / play | `Pause slideshow` / `Play slideshow` | — |
| Photo dot indicator | `Photo {n} of {total}` | — |
| Photo + Tag | `Add a tag to this photo` | `Writes the tag to the Notion Memory pile row` |
| Photo Ask about this | `Ask Compost about this photo cluster` | `Switches to voice mode` |
| Mascot speech bubble | `(announce text once on photo enter)` | — |

## Tone words (for filter / dictionary)

These are case-insensitive flags the prototype uses to differentiate
shouts (highlight + strikethrough) vs. normal text.

- **Shouty pattern**: word length ≥ 4 AND fully uppercase AND contains
  at least one letter (`/^[A-Z]{4,}$/`)
- **Skip in highlight**: stopwords listed in `prototype/scenes.jsx`
  under `DraftsScene`'s `originalSet` derivation

## Tooltips

| Element | Tooltip |
|---|---|
| `Refresh tidy` (existing) | `Refresh Gardener proposals (does not apply anything)` |
| `↻ rephrase` | `Generate a fresh rewrite in the selected tone` |
| `Calmer` pill | `Soften the tone and clarify the ask` |
| `Crisp` pill | `Shorten to the bare ask` |
| `Diplomatic` pill | `Wrap the ask in context and invitation` |
| `Join Meet` (Cue) | `Opens the Google Meet for this calendar event` |
| `Ask Compost ↗` (Cue) | `Switches the notch into voice mode` |
| `+ Tag` (Photos) | `Add a tag to this photo. Writes to Notion immediately.` |
| `Ask about this ↗` (Photos) | `Open voice mode primed with this photo cluster` |
| `Pause` / `Play` (Photos) | `Toggle slideshow auto-advance` |
