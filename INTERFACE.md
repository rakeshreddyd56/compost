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

### `notionMemory` — captured photo / note / clip events (new S15)
Live data source. Already created in the workspace at
`collection://47d8f26b-573c-4288-bee8-1a9fafbb174f` under the Compost Demo
Workspace parent page. Database id `c7d4a833-f620-413f-be0e-7bc6d55b7a2c`.

| Property | Type | Notes |
|---|---|---|
| `Title` | title | Usually the source page title. |
| `Source Page ID` | rich_text | Notion page id this memory was extracted from. |
| `Type` | select | `photo` \| `note` \| `clip`. |
| `Content` | rich_text | For notes: raw text. For photos: external image URL. |
| `Caption` | rich_text | Photos: Claude vision caption. Notes: short summary. |
| `Captured At` | date | When the block was first seen by the ingest worker. |
| `Tags` | multi_select | `idea` / `todo` / `reference` / `moment`. |
| `Embedding ID` | rich_text | sha1 key into the workers embedding cache. |

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

### `recallMemory` (new S15)
```typescript
input:  { query?: string, limit?: number, since?: string /* ISO-8601 */ }
output: { items: Array<{
  id: string,
  title: string,
  type: "photo" | "note" | "clip",
  caption: string,
  capturedAt: string,
  score?: number   // cosine similarity when query is set
}> }
```
Called by Custom Agents (Memory Curator, Today Brief) to fetch the most
relevant memory items. The macOS app does NOT call this — it polls the
`notionMemory` DB directly for the 🧠 Memory section. Worker should:
- Resolve `query` to embedding via OpenAI `text-embedding-3-small` (reuse
  the existing embedding cache).
- Cosine-rank rows against the query embedding; fall back to date-desc when
  `query` is omitted.
- Default `limit = 8`, max `limit = 25`.

## Worker syncs (new S15)

### `memoryIngest`
- **Backfill** (`mode: "manual"`): walk the Compost Demo Workspace subtree
  once, ingest all blocks under pages whose title contains `[!memory]`.
- **Delta** (`mode: "incremental", schedule: "15m"`): walk new blocks since
  the cursor; pacer budget 80 req / 30s (use the existing pacer pattern).
- Per item:
  - `image` block → upload-by-URL into the `notionMemory` row's `Content`,
    caption via Claude vision into `Caption`, `Type = photo`.
  - `paragraph` / `bulleted_list_item` block → write the text into
    `Content`, embed via OpenAI `text-embedding-3-small` (cache key sha1 of
    text → store key into `Embedding ID`), `Type = note`.

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
