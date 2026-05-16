/**
 * Compost — Notion Workers entry point.
 *
 * Four workers + tools:
 *   🪴 Gardener    — nightly cron, scores pages, proposes cleanup, applies approved.
 *   🌙 Sleep-On-It — webhook, freezes late-night drafts, presents calm rewrite in morning.
 *   ☀️ Cue         — every 5m, surfaces the "right thing at the right time" from tagged Notion pages.
 *   📰 The Weekly  — daily cron, Sunday-only, semantic diff of last 7 days (STRETCH).
 */

import { Worker } from "@notionhq/workers";
import * as Builder from "@notionhq/workers/builder";
import * as Schema from "@notionhq/workers/schema";
import { j } from "@notionhq/workers/schema-builder";

import { registerGardener }   from "./gardener.js";
import { registerSleepOnIt }  from "./sleep-on-it.js";
import { registerCue }        from "./cue.js";
// import { registerWeekly }  from "./weekly.js";  // STRETCH
import { registerTools }      from "./tools.js";

const worker = new Worker();

// --- Notion API pacer (3 rps avg) ---
export const notionPacer = worker.pacer("notion", { allowedRequests: 3, intervalMs: 1000 });

// --- managed databases (canonical schema in /INTERFACE.md) ---

export const compostPile = worker.database("compostPile", {
  type: "managed",
  initialTitle: "🪴 Compost Pile",
  primaryKeyProperty: "Proposal ID",
  schema: {
    properties: {
      Title:                Schema.title(),
      "Proposal ID":        Schema.richText(),
      "Action":             Schema.select([
        { name: "archive" },
        { name: "delete_stub" },
        { name: "merge" },
        { name: "fix_link" },
        { name: "add_tag" },
      ]),
      "Target Page ID":     Schema.richText(),
      "Merge With Page ID": Schema.richText(),
      "Reason":             Schema.richText(),
      "Approved":           Schema.checkbox(),
      "Applied":            Schema.checkbox(),
      "Error":              Schema.richText(),
    },
  },
});

export const frozenDrafts = worker.database("frozenDrafts", {
  type: "managed",
  initialTitle: "🌙 Frozen Drafts",
  primaryKeyProperty: "Draft ID",
  schema: {
    properties: {
      Title:            Schema.title(),
      "Draft ID":       Schema.richText(),
      "Source Page ID": Schema.richText(),
      "Original Snapshot": Schema.richText(),
      "Original":       Schema.richText(),
      "Rewrite":        Schema.richText(),
      "Status":         Schema.select([
        { name: "pending" },
        { name: "frozen" },
        { name: "ready" },
        { name: "approved" },
        { name: "rejected" },
        { name: "error" },
        { name: "expired" },
      ]),
      "Frozen At":      Schema.date(),
      "Reviewed At":    Schema.date(),
      "Error":          Schema.richText(),
    },
  },
});

export const cueCards = worker.database("cueCards", {
  type: "managed",
  initialTitle: "☀️ Cue Cards",
  primaryKeyProperty: "Card ID",
  schema: {
    properties: {
      Title:                Schema.title(),
      "Card ID":            Schema.richText(),
      "Source Page ID":     Schema.richText(),
      "Source Title":       Schema.richText(),
      "Current Time":       Schema.date(),
      "Current Heading":    Schema.richText(),
      "Current Bullets":    Schema.richText(),
      "Next Time":          Schema.date(),
      "Next Heading":       Schema.richText(),
      "Next Bullets":       Schema.richText(),
      "Minutes Until Next": Schema.number(),
      "Calm Cue":           Schema.richText(),
      "Generated At":       Schema.date(),
    },
  },
});

export const embeddingsCache = worker.database("embeddingsCache", {
  type: "managed",
  initialTitle: "🌱 Embeddings Cache",
  primaryKeyProperty: "Page ID",
  schema: {
    properties: {
      Title:          Schema.title(),
      "Page ID":      Schema.richText(),
      "Content Hash": Schema.richText(),
      "Embedding":    Schema.richText(),
    },
  },
});

// --- register workers ---
// Codex 5.5: in S2, finish wiring each registerX function to consume the pacer.
// Use `await notionPacer.wait()` before every notion.* call inside execute().
registerGardener(worker, { compostPile, embeddingsCache, pacer: notionPacer });
registerSleepOnIt(worker, { frozenDrafts, pacer: notionPacer });
registerCue(worker, { cueCards, pacer: notionPacer });
// registerWeekly(worker, { weeklySnapshots, weeklyDigests, pacer: notionPacer });  // STRETCH
registerTools(worker, { compostPile, frozenDrafts });

// --- S1 sanity ping ---
worker.tool("ping", {
  title: "Ping",
  description: "Sanity check for the Worker.",
  schema: j.object({}),
  execute: async () => ({ ok: true, ts: Date.now() }),
});

export default worker;
