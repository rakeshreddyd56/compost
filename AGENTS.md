# AGENTS.md — Compost

> This file is the spec both Codex 5.5 and Claude Code read at the start of every session.
> Same content lives in `CLAUDE.md` (Claude Code convention).

## What we're building
**Compost** — a Notion app that gives your workspace a sense of time. Three Notion Workers run overnight:
- 🪴 **Gardener** — tidies rot (stale pages, dupes, dead links) with your approval
- 🌙 **Sleep-On-It** — freezes late-night drafts, presents calmer rewrite in the morning
- 📰 **The Weekly** — Sunday semantic diff of what actually changed in your workspace

Surfaced via a calm macOS notch UI.

Submission for Notion Developer Platform Hackathon, Sat-Sun May 16-17 2026.

## Stack
- `workers/` — TypeScript on Notion Workers runtime (scaffolded from `makenotion/workers-template`)
- `app/` — SwiftUI macOS app + AppKit + DynamicNotchKit (MIT)
- Storage: Notion managed databases (`worker.database({ type: "managed" })`)
- Embeddings: OpenAI `text-embedding-3-small`
- LLM: Claude (`claude-haiku-4-5` for short rewrites)
- Deploy: `ntn workers deploy`

## Ownership boundaries
| Path | Owner | Other agent allowed to read? |
|---|---|---|
| `workers/**` | **Codex 5.5** | Read-only |
| `app/**` | **Claude Code** | Read-only |
| `AGENTS.md`, `CLAUDE.md`, `INTERFACE.md`, `TASKS.md`, `README.md`, `LICENSE` | Either (coordinate) | Yes |

**Hard rule:** never edit a file outside your subtree without explicit user permission.

## Hard rules (apply to all code)
1. **Nothing auto-deletes in user's Notion.** Every destructive action requires a user-checked checkbox in a `🪴 Tonight's Compost` page. Apply pass is idempotent (stamps `Applied=true`).
2. **Worker schedules are interval strings**, not cron. Max `"7d"`. For "specific hour" behavior, use `"1d"` + internal time gate that no-ops outside the target window.
3. **Storage = Notion managed databases.** No external DBs (no Postgres/SQLite/Redis).
4. **All cross-component contracts live in `INTERFACE.md`.** If you need a new Notion property, env var, or worker tool signature, update INTERFACE.md *first*, commit, then implement.
5. **MIT license.** No GPL/AGPL deps.
6. **Open source.** Everything in the repo, every dep, public from Sat 10:45am.

## How to start a session
1. `git pull`
2. Read `INTERFACE.md` for the current contract
3. Read `TASKS.md` for your next task
4. Mark task as in-progress
5. Work in your subtree
6. Commit every 30-60 min with prefix `[workers]` or `[app]`
7. Update `TASKS.md` when done

## Commit message convention
```
[workers] add decay scoring for age/orphan signals
[app] notch expanded state with proposal list
[shared] document tidyNow tool signature in INTERFACE.md
```

## Where we are
See `TASKS.md` for live progress. See [BRAIN.md in the Obsidian vault](~/ObsidianVault/compost-hackathon/BRAIN.md) for full context.

## What to NOT do
- Don't add Gmail/Slack/Calendar OAuth (eats time, breaks thesis)
- Don't write a chatbot, RAG, or AI companion (banned anti-projects)
- Don't use Streamlit (banned)
- Don't auto-delete anything in the user's Notion
- Don't fork BoringNotch/NotchDrop (allowed to use as a *library* via `DynamicNotchKit`; not allowed to fork apps)
- Don't switch storage to anything other than Notion managed DBs
