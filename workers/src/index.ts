/**
 * Compost — Notion Workers entry point.
 *
 * Three workers:
 *   🪴 Gardener    — nightly cron, scores pages, proposes cleanup, applies approved.
 *   🌙 Sleep-On-It — webhook, freezes late-night drafts, presents calm rewrite in morning.
 *   📰 The Weekly  — daily cron, Sunday-only, semantic diff of last 7 days.
 *
 * Plus tools: `tidyNow`, `reviewDraft` for app-side invocation.
 */

import { Worker, Schema, Builder } from "@notionhq/workers";
import { j } from "@notionhq/workers/schema-builder";

import { registerGardener }   from "./gardener";
import { registerSleepOnIt }  from "./sleep-on-it";
import { registerCue }        from "./cue";
import { registerWeekly }     from "./weekly";  // STRETCH — wired but only built if time permits
import { registerTools }      from "./tools";

const worker = new Worker();

// --- managed databases (shared across workers) ---
// See INTERFACE.md for the canonical schema.

export const compostPile = worker.database("compostPile", {
  type: "managed",
  initialTitle: "🪴 Compost Pile",
  primaryKeyProperty: "Proposal ID",
  schema: {
    properties: {
      Title:                 Schema.title(),
      "Proposal ID":         Schema.richText(),
      "Action":              Schema.select({ options: ["archive","delete_stub","merge","fix_link","add_tag"] }),
      "Target Page ID":      Schema.richText(),
      "Merge With Page ID":  Schema.richText(),
      "Reason":              Schema.richText(),
      "Approved":            Schema.checkbox(),
      "Applied":             Schema.checkbox(),
      "Error":               Schema.richText(),
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
      "Original":       Schema.richText(),
      "Rewrite":        Schema.richText(),
      "Status":         Schema.select({ options: ["pending","frozen","ready","approved","rejected","error","expired"] }),
      "Frozen At":      Schema.date(),
      "Reviewed At":    Schema.date(),
      "Error":          Schema.richText(),
    },
  },
});

export const weeklySnapshots = worker.database("weeklySnapshots", {
  type: "managed",
  initialTitle: "📦 Weekly Snapshots",
  primaryKeyProperty: "Page ID",
  schema: {
    properties: {
      Title:           Schema.title(),
      "Page ID":       Schema.richText(),
      "Content Hash":  Schema.richText(),
      "Markdown":      Schema.richText(),
      "Snapshot Week": Schema.date(),
    },
  },
});

export const weeklyDigests = worker.database("weeklyDigests", {
  type: "managed",
  initialTitle: "📰 Weekly Digests",
  primaryKeyProperty: "Week Start",
  schema: {
    properties: {
      Title:            Schema.title(),
      "Week Start":     Schema.date(),
      "Digest Page ID": Schema.richText(),
      "Stats":          Schema.richText(),
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

// --- register everything ---
registerGardener(worker, { compostPile, embeddingsCache });
registerSleepOnIt(worker, { frozenDrafts });
registerCue(worker, { cueCards });
// registerWeekly(worker, { weeklySnapshots, weeklyDigests });  // STRETCH — uncomment if time permits
registerTools(worker, { compostPile, frozenDrafts });

// Sanity tool for S1 deploys
worker.tool("ping", {
  title: "Ping",
  description: "Sanity check for the Worker.",
  schema: j.object({}),
  outputSchema: j.object({ ok: j.boolean(), ts: j.number() }),
  execute: async () => ({ ok: true, ts: Date.now() }),
});

export default worker;
