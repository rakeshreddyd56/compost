# Compost Worker Demo Runbook

This is the safe worker-side checklist for the live notch demo. It keeps Codex
work isolated from `app/**` so Claude can keep polishing the macOS branch in
parallel.

## Safety boundaries

- Default smoke checks are read-only or preview-only.
- Live sync triggers only write to managed Worker databases.
- `tidyNow` and `applyApproved` only run when passed `--apply-tools`.
- Gardener actions still require `Approved=true` and `Applied=false`.
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

## Apply approved cleanup

Only run this after you have checked `Approved` on the intended Compost Pile
rows:

```bash
cd /Users/rakeshreddy/compost/workers
bash ./test.sh --skip-previews --apply-tools
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

## Notion sharing checklist

The internal integration token must have access to:

- Compost Demo parent page
- Compost Pile managed database
- Frozen Drafts managed database
- Cue Cards managed database

The app uses the same integration token in Keychain to read the managed
databases directly.
