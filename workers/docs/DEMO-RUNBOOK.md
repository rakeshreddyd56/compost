# Compost Worker Demo Runbook

This is the safe worker-side checklist for the live notch demo. It keeps Codex
work isolated from `app/**` so Claude can keep polishing the macOS branch in
parallel.

## Safety boundaries

- Default smoke checks are read-only or preview-only.
- Live sync triggers only write to managed Worker databases.
- `tidyNow` refreshes proposal rows only; it does not mutate target pages.
- `applyProposal` mutates only explicit safe demo pages marked `[!compost]`,
  `[!gardener]`, or `[!stale]`.
- `reviewDraft approve` mutates only explicit safe demo pages marked `[!sleep]`
  or demo-safe in the title/body. `reviewDraft reject` never mutates a source.
- Legacy `applyApproved` only runs when passed `--legacy-apply-approved`.
- `sleepOnItCleanup` is previewed during demo smoke checks, but not triggered by
  `--write`.

## One-command smoke check

From the deployed workers directory:

```bash
cd /Users/rakeshreddy/compost/workers
npm run demo:smoke
```

If `workers.json` is missing in a fresh checkout, pass the public Worker ID:

```bash
COMPOST_WORKER_ID=019e31dc-050f-7a85-974a-21954fd261f5 npm run demo:smoke
```

Expected result:

- TypeScript check passes.
- `ping` returns `{ ok: true, ts: ... }`.
- `cue`, `sleepOnItReviewer`, `gardener`, and `sleepOnItCleanup` all show
  `healthy`.
- Sync previews complete without throwing.

## Live demo trigger

Use this right before launching or refreshing the notch app:

```bash
cd /Users/rakeshreddy/compost/workers
npm run demo:trigger
```

That runs real triggers for:

- `cue`
- `sleepOnItReviewer`
- `gardener`

It intentionally does not trigger `sleepOnItCleanup`.

## Reset safe demo state

Use this before a rehearsal when old frozen rows or applied proposals are making
the notch noisy:

```bash
cd /Users/rakeshreddy/compost/workers
npm run demo:reset
```

This only touches demo-marked rows/pages:

- resets `[!compost]` proposal rows to `Approved=false`, `Applied=false` when
  the managed DB allows direct writes
- unarchives safe `[!compost]` targets if the prior rehearsal applied them
- restores the canonical `[!sleep]` source page to a deliberately loud draft
  so `Use calmer` has a visible Notion-side mutation again
- expires old safe frozen draft rows when the managed DB allows direct writes
- clears the app's local resolved-row hide cache for `com.compost.app`
- resets and retriggers `cue`, `sleepOnItReviewer`, and `gardener`

The reset script treats managed DB row updates as best-effort because Notion
Workers data-source rows can be read-only to the public API. Source pages and
safe target pages are still restored directly. `[!audit]` pages are excluded
from Sleep-On-It source discovery so audit trails cannot become new draft rows.

## Refresh and apply one cleanup

Refresh proposals without mutating target pages:

```bash
cd /Users/rakeshreddy/compost/workers
bash ./test.sh --skip-previews --apply-tools
```

Apply one explicit safe demo proposal from the notch row:

```bash
cd /Users/rakeshreddy/compost/workers
bash ./test.sh --skip-previews --apply-proposal <proposal-id>
```

Certify one draft decision:

```bash
cd /Users/rakeshreddy/compost/workers
bash ./test.sh --skip-previews --review-draft <draft-id> reject
bash ./test.sh --skip-previews --review-draft <fresh-draft-id> approve
```

## Demo force flags

`SLEEP_ON_IT_FORCE_FIRE=true` is useful for generating morning draft rows during
the demo. When it is enabled, the worker logs a visible warning once per process.

Keep it enabled only for rehearsal/demo:

```bash
ntn workers env pull
# remove SLEEP_ON_IT_FORCE_FIRE=true from .env after the demo
ntn workers env push --yes
```

`WEEKLY_FORCE_FIRE=true` is stretch-only and should stay off unless the weekly
digest flow is being demoed.

## Reset flow

Use this if the demo rows drift or a sync gets stuck. Resetting state does not
delete source Notion pages; it only makes the sync run from a clean cursor.

```bash
cd /Users/rakeshreddy/compost/workers
ntn workers sync state reset cue
ntn workers sync state reset sleepOnItReviewer
ntn workers sync state reset gardener
npm run demo:trigger
```

If the app does not show fresh Cue data, trigger Cue alone:

```bash
ntn workers sync trigger cue
```

If Sleep-On-It rows do not appear, verify:

- `SLEEP_ON_IT_FORCE_FIRE=true` is present in remote env for demo mode.
- `[!sleep]` or `demo late-night draft` exists in the source page title.
- The source page has at least 30 words.
- The source page is not already identical to its calmer rewrite; no-op demo
  draft rows are intentionally skipped.

## Notion sharing checklist

The internal integration token must have access to:

- Compost Demo parent page
- Compost Pile managed database
- Frozen Drafts managed database
- Cue Cards managed database

The app uses the same integration token in Keychain to read the managed
databases directly.
