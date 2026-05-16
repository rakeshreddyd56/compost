# TASKS — Compost

> Shared todo log. Both Codex and Claude tick boxes after commits.
> Format: `- [x] [owner] task` — owner = `workers` | `app` | `shared`.

## Block A — Sat 10:45a-12p (Scaffold)
- [ ] [shared] Create GitHub repo, push initial commit with AGENTS.md, CLAUDE.md, INTERFACE.md, TASKS.md, LICENSE, README stub
- [ ] [workers] `ntn workers new` in `workers/`, deploy hello-world `tool("ping")`, verify via `ntn workers exec ping --local`
- [ ] [app] New SwiftUI app `Compost.app` in `app/`, add `DynamicNotchKit` Swift package, render hello-world notch
- [ ] [shared] Verify both halves run before lunch

## Block B — Sat 12:30-3p (Gardener core)
- [ ] [workers] Define `compostPile` managed DB per INTERFACE.md
- [ ] [workers] Implement age decay signal
- [ ] [workers] Implement orphan signal (link graph from mentions+relations)
- [ ] [workers] Implement stub signal
- [ ] [workers] Combine into decay score, surface ≥0.60 → write proposals to `compostPile`
- [ ] [workers] Schedule: `worker.sync("gardener", { schedule: "1d", ... })` (internal hour-gate optional in v1)
- [ ] [app] Poll Notion for `compostPile` row count, show as badge on notch

## Block C — Sat 3-4:30p (Approve + apply)
- [ ] [workers] Apply pass: read `Approved=true AND Applied=false`, execute (archive/merge/fix), stamp `Applied=true`
- [ ] [workers] Idempotency: never re-apply stamped rows
- [ ] [app] Expanded notch state with proposal list (read from `compostPile`)
- [ ] [app] Tap row → open in Notion via deep link

## Block D — Sat 4:30-6p (Sleep-On-It)
- [ ] [workers] `webhook("onLateNightEdit")` accepting Notion automation payload
- [ ] [workers] Time-of-day gate (22:00-06:00 in `USER_TIMEZONE`)
- [ ] [workers] LLM rewrite with calm-tone prompt
- [ ] [workers] Write to `frozenDrafts` DB per INTERFACE.md
- [ ] [shared] Configure Notion-side automation: page.updated → POST webhook
- [ ] [app] "Drafts on ice" panel in notch expanded state

## Block E — Sat 6:30-8p (Integration + dry-run)
- [ ] [shared] End-to-end test: messy workspace → tidy → approve → apply → cleaner workspace
- [ ] [shared] First 3-min pitch dry-run (timed)
- [ ] [shared] Tag `git tag day1-end`

## Sprint S7 — Sat 8:30-10p home (Cue worker + wake/hotkey)
- [ ] [workers] Declare cueCards managed DB (already in scaffold's index.ts)
- [ ] [workers] Implement cue.ts: findCueSources, parseTimeline, pickCurrentAndNext, calmRephrase, buildCardChange
- [ ] [workers] Deploy and test against the actual Hacker Resources doc with [!cue] in title
- [ ] [app] Models/CueCard.swift + Views/CueRow.swift
- [ ] [app] CompostPoller fetches latest cueCards row
- [ ] [app] ExpandedView shows ☀️ Up Next section at top
- [ ] [app] WakeTrigger via NSWorkspace.didWakeNotification → greet with current cue
- [ ] [app] HotkeyManager ⌘⇧C global monitor

## Sprint S8 — Sat 10-11:30p home (polish OR stretch)
- [ ] [app] Spring animations + GardenStyle polish (default)
- [ ] [workers] Embedding dedup (alternative)
- [ ] [workers] The Weekly stretch (only if everything rock solid)

## Block G — Sun 9-10:30a (Polish + edge cases)
- [ ] [shared] Re-seed demo workspace
- [ ] [workers] Error handling: Notion API rate limits, missing properties
- [ ] [app] Pre-notch Mac fallback to menubar
- [ ] [shared] Second dry-run pitch

## Block H — Sun 10:30-11:30a (Demo + rehearsal)
- [ ] [shared] Record 60s Cerebral Valley demo video
- [ ] [shared] Pre-record 20s notch-wake screencap (insurance)
- [ ] [shared] 3 rehearsal pitch runs

## Block I — Sun 11:30a-12p (Submission)
- [ ] [shared] Make repo public
- [ ] [shared] Write final README with screenshots
- [ ] [shared] Upload demo video
- [ ] [shared] Submit Cerebral Valley form
- [ ] [shared] Verify all submission checklist items per BRAIN.md

## Stretch (only if Block H reached with time)
- [ ] [workers] 🧭 Where I Left Off — auto-breadcrumb on page close
- [ ] [app] Sunday digest treatment (different visual)

## Cut-line decisions log
| Time | Block | Decision | Reason |
|---|---|---|---|
| | | | |

---

## 🔥 Current focus (post-S1, pre-S2)

**Codex 5.5 — start here in S2:**
1. Open `.agents/skills/sync-guide/SKILL.md` — it auto-loads but read it explicitly
2. Update each `registerX(worker, { ..., pacer })` function signature to type and use the pacer
3. Inside every `execute()` that calls `context.notion.*`, do `await pacer.wait()` first
4. Type the awaited responses (the 17 `'res' is of type unknown'` errors) — use `as any` initially if SDK types are obscure, then refine
5. `npm run check` should be green before considering S2 done

**Verify environment first:**
- `ntn doctor` — should be 5/5 once Workers enabled
- `cat .env` — every key filled in (NOTION_API_TOKEN, ANTHROPIC, OPENAI, MINIMAX, USER_TIMEZONE, NOTION_PARENT_PAGE_ID)
- `ntn workers env push` — pushes .env to deployed worker
- `ntn workers exec ping --remote -d '{}'` — sanity (should return ts)
