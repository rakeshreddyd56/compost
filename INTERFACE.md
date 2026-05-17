# INTERFACE.md — Compost cross-component contract

> Single source of truth for what crosses the `workers/` ↔ `app/` boundary.
> Update this **first**, commit, then implement on either side.

## Notion managed databases

### `compostPile` — Gardener proposals
| Property | Type | Notes |
|---|---|---|
| `Title` | title | Human-readable summary, e.g. "Archive 'Q2 Brainstorm'" |
| `Proposal ID` | rich_text | Stable ID (sha1 of action + target) — primary key |
| `Action` | select | `archive` \| `merge` \| `fix_link` \| `add_tag` \| `delete_stub` |
| `Target Page ID` | rich_text | Notion page ID being acted on |
| `Merge With Page ID` | rich_text | For `merge` only |
| `Reason` | rich_text | "94 days untouched, no inbound links" |
| `Approved` | checkbox | User toggles |
| `Applied` | checkbox | Worker stamps after execution |
| `Error` | rich_text | Last apply failure, if any |
| `Created` | created_time | auto |

### `frozenDrafts` — Sleep-On-It holds
| Property | Type | Notes |
|---|---|---|
| `Title` | title | Original page title |
| `Draft ID` | rich_text | Stable sha1(page + date) id for idempotency |
| `Source Page ID` | rich_text | Notion page that was edited late |
| `Original Snapshot` | rich_text | Markdown of original content |
| `Rewrite` | rich_text | Markdown of calmer rewrite |
| `Status` | select | `pending` \| `frozen` \| `ready` \| `approved` \| `rejected` \| `error` \| `expired` |
| `Frozen At` | date | When edit happened |
| `Reviewed At` | date | When user decided |
| `Error` | rich_text | Last processing/review error, if any |

### `weeklyDigests` — Weekly archive (STRETCH)
| Property | Type | Notes |
|---|---|---|
| `Title` | title | "Week of 2026-05-11" |
| `Week Start` | date | Sunday of the week |
| `Summary Page ID` | rich_text | Link to the rendered Notion page |

### `cueCards` — Cue worker output (one row per Cue source page)
| Property | Type | Notes |
|---|---|---|
| `Title` | title | Source page title |
| `Card ID` | rich_text | sha1(pageId + currentStartISO) — idempotency key |
| `Source Page ID` | rich_text | Notion page that's being "Cue'd" |
| `Source Title` | rich_text | Source page title (denorm) |
| `Current Time` | date | Start of current moment, today's date in user TZ |
| `Current Heading` | rich_text | Section heading of current moment |
| `Current Bullets` | rich_text | Newline-joined bullets |
| `Next Time` | date | Next moment's time |
| `Next Heading` | rich_text |  |
| `Next Bullets` | rich_text |  |
| `Minutes Until Next` | number | App pulses when < 10 |
| `Calm Cue` | rich_text | 1-2 line Claude-rephrased card |
| `Generated At` | date | When this row was last written |

### `notionMemory` — Memory/photo recall
| Property | Type | Notes |
|---|---|---|
| `Title` | title | Human-readable memory title |
| `Memory ID` | rich_text | Stable worker-managed ID when present |
| `Source Page ID` | rich_text | Source `[!memory]` page ID |
| `Type` | select | `photo` \| `note` \| `clip` |
| `Content` | rich_text | Image URL, note excerpt, or clip text |
| `Caption` | rich_text | Short app-facing caption |
| `Captured At` | date | Source page timestamp, edit time, or captured time |
| `Tags` | multi_select | `idea` \| `todo` \| `reference` \| `moment` |
| `Embedding ID` | rich_text | Optional recall cache key |

The source of truth is the regular Notion page under `[!memory] Compost Memory
Inbox`; the Worker writes rows here. Notion Custom Agents may add captions or
metadata to source pages, but should avoid manually duplicating `notionMemory`
rows unless the Worker is unavailable.

## Worker tools (callable by app or Notion Custom Agents)

### `tidyNow`
```typescript
input:  {}
output: { proposed: number, upserted: number, errors: number }
```
Refreshes Gardener proposals in `compostPile`. It does **not** apply or mutate
target pages.

### `applyApproved`
```typescript
input:  {}
output: { applied: number, errors: number }
```
Legacy batch path. Uses the same safe-demo guard as `applyProposal`.

### `applyProposal`
```typescript
input:  { proposalId: string } // stable `Proposal ID` rich_text from compostPile
output: {
  ok: boolean,
  proposalId: string,
  action: string | null,
  targetPageId: string | null,
  applied: boolean,
  error: string | null
}
```
Per-proposal apply path. The macOS app calls this when the user clicks
`Approve & apply` on a single row. Worker behavior:
- Look up the `compostPile` row by `Proposal ID = proposalId`.
- Refuse to mutate any target page that is not explicitly marked safe for demo
  with `[!compost]`, `[!gardener]`, or `[!stale]` in the title/body.
- Execute the action and stamp `Approved = true`, `Applied = true`, clear
  `Error` on success.
- Return `{ ok: false, error: "..." }` on failure instead of throwing so the
  row can show the exact reason inline.

### `reviewDraft`
```typescript
input:  { draftId: string, decision: "approve" | "reject" } // accepts row page id or Draft ID
output: { ok: boolean, error: string | null }
```
`reject` is non-destructive and stamps `Status = rejected`. `approve` replaces
the source page only when the source is explicitly marked safe for this demo with
`[!sleep]` or demo-safe text in the title/body; otherwise it returns `ok=false`.

### `recallMemory`
```typescript
input:  { query?: string | null, limit?: number | null, since?: string | null }
output: {
  items: Array<{
    id: string,
    title: string,
    type: "photo" | "note" | "clip",
    caption: string,
    capturedAt: string,
    score: number | null
  }>
}
```
Returns recent or relevant memory rows for Notion Custom Agents and future
voice/recall surfaces. If embeddings are unavailable, recall falls back to
lexical matching and recency.

### `refreshBridge`
```typescript
input:  { surface: "cue" | "memory" | "tidy" | "all" }
output: {
  ok: boolean,
  surface: "cue" | "memory" | "tidy" | "all",
  cueCards: number,
  memoryRecords: number,
  tidyProposals: number,
  notes: string[],
  errors: string[]
}
```
Agent-callable bridge refresh. `memory` runs the memory ingest path immediately.
`tidy` refreshes Gardener proposals immediately. `cue` is Worker-sync managed:
the agent should update `[!cue] Agent Briefing Inbox`, then the 5-minute `cue`
sync publishes Cue Cards. This is intentional because Cue Cards are Worker-owned
managed rows whose date fields are read-only to direct tool writes.

### `rephraseDraft`
```typescript
input:  { draftId: string, tone: "calmer" | "crisp" | "diplomatic" }
output: {
  ok: boolean,
  draftId: string,
  tone: "calmer" | "crisp" | "diplomatic",
  rewrite: string | null,
  error: string | null
}
```
Generates a real tone variant from the frozen draft's `Original` /
`Original Snapshot`, stamps `Rewrite`, `Rewrite Variants`, and `Active Tone` on
the draft row, and does not mutate the source page. `reviewDraft approve` still
performs the actual source-page replacement.

### `voiceReply`
```typescript
input:  {
  transcript: string,
  mode: "general" | "briefing" | "memory" | "draft" | null,
  context: string | null
}
output: {
  ok: boolean,
  reply: string,
  mode: "general" | "briefing" | "memory" | "draft",
  usedMemory: boolean,
  error: string | null
}
```
Returns a real spoken response for the notch voice surface. For memory-like
queries it calls `recallMemory` first, then produces a short reply. The app may
feed this output to local text-to-speech.

## Notion Custom Agent bridge

The Notion agent can use Mail, Calendar, Web, GitHub, Notion, and the Compost
Worker, but it should write through the same safe bridge surfaces:

| Agent job | Writes to | Worker/app path |
|---|---|---|
| Today briefing from Gmail/Calendar/notes | `[!cue] Agent Briefing Inbox` | `cue` sync writes `cueCards`; app shows Up Next |
| Photo or voice memory curation | `[!memory]` source pages | `memoryIngest` sync writes `notionMemory`; app shows Memory |
| Cleanup setup | `[!compost]` safe pages or proposal content | `tidyNow`/`applyProposal` stamp `compostPile` |
| Draft setup | `[!sleep]` safe pages | `sleepOnItReviewer`/`reviewDraft` stamp `frozenDrafts` |
| Audit trail | `[!audit] Compost Demo State` | Readable by humans; excluded from draft/memory ingestion |

The agent must not mutate untagged personal notes. If Notion marks managed DB
properties read-only, the agent should write structured content into the row/page
body and ask the Worker to stamp the canonical properties.

## App display contract for Claude design work

The notch app should remain data-driven:

| UI section/action | Data source | Action endpoint |
|---|---|---|
| Up Next / current context | newest `cueCards` row by `Generated At` | `tidyNow` only for Refresh tidy; `cue` sync refreshes cards |
| Tidy proposals | `compostPile` where `Approved=false` and `Applied=false` | `applyProposal({ proposalId })` |
| Drafts on ice | `frozenDrafts` where `Status=frozen`, newest `Frozen At` first | `reviewDraft({ draftId, decision })` |
| Memory | `notionMemory`, newest `Captured At` first | `recallMemory` for search/voice recall |
| Read aloud / voice | app-native audio + Worker reply text | `voiceReply({ transcript, mode, context })` |

Design can change layout, hierarchy, animation, and visual treatment, but should
not invent mock-only fields. Missing data should render as empty/error states,
not fake successful content.

## Worker webhooks

### `onLateNightEdit`
- URL: published via `ntn workers webhooks list`, format: `https://www.notion.so/webhooks/worker/{spaceId}/{workerId}/{uniqueWebhookId}/onLateNightEdit`
- Triggered by: **Notion's native webhook subscription** on `page.content_updated` event (registered in UI at `developers.notion.com` → Connection settings → Webhooks tab)
- First POST contains `verification_token` — Worker echoes back to complete handshake; token stored as `COMPOST_WEBHOOK_SECRET` env var
- Subsequent POSTs include `X-Notion-Signature: sha256=<hmac>` — verify HMAC-SHA256(rawBody, secret) with `crypto.timingSafeEqual`
- Body: standard Notion webhook payload (page ID, event type, timestamp)

## Environment variables

| Name | Where set | Used by |
|---|---|---|
| `COMPOST_NOTION_TOKEN` | Workers env | workers (Notion API client for syncs/webhooks) |
| `OPENAI_API_KEY` | Workers env (`ntn workers env set`) | workers (embeddings) |
| `ANTHROPIC_API_KEY` | Workers env | workers (LLM rewrites) |
| `COMPOST_PARENT_PAGE_ID` | Workers env | workers (where Compost Dashboard lives) |
| `USER_TIMEZONE` | Workers env | workers (Sleep-On-It gate) |
| `COMPOST_WEBHOOK_SECRET` | Workers env (set after first verification POST) | workers (Sleep-On-It HMAC verify) |
| `NOTION_INTEGRATION_TOKEN` | App keychain (v1 internal integration shortcut) | app (Notion API) |

## App ↔ Workers communication

- App reads Notion managed databases directly via Notion API (using user's OAuth token)
- App invokes Worker tools via Notion API tool-call endpoint
- Webhook URL is server-side only — app does not call it

## Versioning
Bump a `version` rich_text property on each managed DB row if schema changes mid-build.
