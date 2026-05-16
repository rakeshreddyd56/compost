# CODEX-RUNBOOK.md — for Codex 5.5

> This file is Codex 5.5's operating manual for the Compost project. Read it at the start of every session in addition to `AGENTS.md` (the shared spec). Lives in the repo at root.

## Who you are
You are Codex 5.5, working solo on the **TypeScript Workers** half of Compost. You own `workers/`. You do not edit `app/`. You commit to `main` with prefix `[workers]`.

## Your one job
Ship three Notion Workers (Gardener, Sleep-On-It, The Weekly) that compose into a calm "workspace time hygiene" product, deployed via the `ntn` CLI on Notion's hosted runtime. The macOS client (handled by Claude Code) reads from the managed Notion databases your Workers populate.

## How to start every session

```bash
git pull --rebase
cat AGENTS.md INTERFACE.md TASKS.md   # read in this order
ls workers/                            # know your tree
```

Then state in your first reply what sprint you're starting and what you'll have done by sprint end.

## Hard rules (do not violate)

1. **Stay in `workers/`** — never edit files in `app/` even if it would be "easier".
2. **Update `INTERFACE.md` BEFORE implementing a schema change**, commit, then implement.
3. **No external storage** — only Notion managed databases (`worker.database({ type: "managed" })`).
4. **Schedules are interval strings**, not cron — `"5m"` to `"7d"`. Specific-hour behavior via `"1d"` + internal time gate.
5. **350ms sleep between Notion API calls** to stay under the 3 rps limit. Use the `pace()` helper in `utils/rate-limit.ts`.
6. **Never auto-delete user content** — apply-pass only acts on `Approved=true AND Applied=false` rows and stamps idempotently.
7. **Verify webhook signatures** via `crypto.timingSafeEqual` and `HMAC-SHA256(rawBody, NOTION_WEBHOOK_SECRET)`. Throw `WebhookVerificationError` on mismatch.
8. **Secrets via `ntn workers env set`**, accessed as `process.env.KEY`. Never commit `.env`.
9. **Commit at sprint boundary**. Format: `[workers] S<n> <imperative>: <one-liner>`.
10. **If you blow past sprint time-box, stop and ask** — don't ship a half-feature.

## Where things live

```
workers/
├── package.json                  # @notionhq/workers, openai (or raw fetch)
├── tsconfig.json
├── src/
│   ├── index.ts                  # Worker entry; registers DBs, syncs, webhooks, tools
│   ├── gardener.ts               # Gardener sync (Phase 1-5 from workflows/gardener.md)
│   ├── sleep-on-it.ts            # webhook handler + reviewer sync + cleanup sync
│   ├── weekly.ts                 # Weekly sync (Sunday gate inside)
│   ├── tools.ts                  # tidyNow, reviewDraft tool definitions
│   └── utils/
│       ├── notion-walker.ts      # walk pages with cap + pace
│       ├── scoring.ts            # 5 rot signals + decay composite
│       ├── embeddings.ts         # OpenAI embedding + cosine
│       ├── markdown.ts           # blocks ↔ markdown converters
│       ├── rate-limit.ts         # pace() helper
│       ├── hashing.ts            # sha1 wrapper
│       └── time.ts               # isSunday, isLateNight, isMorningReview
└── README.md                     # short — link to vault
```

## Reading order for each file

| Goal | File to read first |
|---|---|
| What you're building | `AGENTS.md` (root) |
| Cross-component contracts | `INTERFACE.md` (root) |
| Current sprint goal | `TASKS.md` (root) |
| Detailed workflow | `~/ObsidianVault/compost-hackathon/workflows/<feature>.md` |
| Research-backed decisions | `~/ObsidianVault/compost-hackathon/design/research-notes.md` |
| Sprint prompts (what your user wants this session) | `~/ObsidianVault/compost-hackathon/templates/SPRINT-PROMPTS.md` |

## Common pitfalls (calibrate against these)

1. **Don't invent SDK methods.** If you're unsure whether `Builder.checkbox()` exists, read `node_modules/@notionhq/workers/dist/*.d.ts` instead of guessing. Adjust INTERFACE.md if naming differs.
2. **Don't hand-roll pagination.** Use `while (has_more) { … }` with `start_cursor` — every Notion list endpoint follows this.
3. **Don't skip the rate-limit pacing**, even in dev. You'll get 429-blocked mid-demo otherwise.
4. **Don't store secrets in TypeScript files.** Only `process.env.X`.
5. **Don't add npm packages without checking the Workers sandbox first.** If `openai` SDK fails to install, fall back to raw `fetch`.
6. **Don't call the Notion SDK from inside a `worker.tool()` that itself triggers a `worker.sync()`.** Likely unsupported. Re-implement the apply pass inline in `tidyNow`.
7. **Don't ship without idempotency stamps.** Every apply must check `Applied=false` before executing and set `Applied=true` after.

## Common patterns

### Pace a loop of Notion calls
```typescript
import { pace } from "./utils/rate-limit";
for (const item of items) {
  await doNotionThing(item);
  await pace();  // sleeps 350ms
}
```

### Idempotent upsert into a managed DB
```typescript
return {
  changes: [{
    type: "upsert",
    key: proposalId,                 // deterministic sha1 of (action + targets)
    properties: { Applied: Builder.checkbox(true) },
  }],
  hasMore: false,
};
```

### Webhook signature verify
```typescript
function verify(event) {
  const sig = event.headers["x-notion-signature"];
  const expected = "sha256=" + crypto.createHmac("sha256", process.env.NOTION_WEBHOOK_SECRET).update(event.rawBody).digest("hex");
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) {
    throw new WebhookVerificationError("bad sig");
  }
}
```

### Sunday-only sync
```typescript
worker.sync("weekly", {
  schedule: "1d",
  execute: async (state, ctx) => {
    if (!isSunday(process.env.USER_TIMEZONE)) return { changes: [], hasMore: false };
    // ... real work
  }
});
```

## Deployment

```bash
cd workers
ntn workers deploy                       # ships everything in src/index.ts
ntn workers env set OPENAI_API_KEY=…     # secrets
ntn workers env set ANTHROPIC_API_KEY=…
ntn workers env set USER_TIMEZONE=America/Los_Angeles
ntn workers webhooks list                # grab the URL for Notion webhook subscription
ntn workers runs logs --follow           # live logs (open in side terminal during demo)
ntn workers sync trigger gardener        # force-fire a sync (demo / testing)
ntn workers sync trigger weekly          # same; set WEEKLY_FORCE_FIRE=true via env first
ntn workers exec tidyNow --remote -d '{}' # run a tool manually
ntn workers sync state reset gardener    # nuke state if a run got corrupted
```

## How to debug stuck syncs

1. `ntn workers runs logs <runId>` — look for unhandled rejections
2. Did Notion 429? Look for `Retry-After` in logs
3. Did the Schema/Builder property name not exist? Print `Object.keys(Builder)` once in a sync
4. Did the cursor loop forget to break on `has_more === false`? Check `pages.length` cap
5. If wholly stuck >15 min, ask a Notion staffer at the venue

## Handoff to your human at sprint end

After each sprint, your final message should be:

```
S<n> COMPLETE
- DoD demo'd: <yes/no>
- What works: <bullets>
- What's still rough: <bullets>
- Open question for human: <one line, if any>
- Commit: <hash> <message>
```

The human switches contexts to Claude Code in 5 min. Make their re-entry fast.
