/**
 * Worker tools exposed to the macOS app (and to Notion Custom Agents).
 */

import { j } from "@notionhq/workers/schema-builder";
import { applyApproved as applyApprovedRows } from "./gardener";
import { notionClient } from "./utils/notion-auth";

export function registerTools(worker: any, dbs: { compostPile: any; frozenDrafts: any }) {
  const applySchema = j.object({
    applied: j.number(),
    errors: j.number(),
  });

  const runApplyApproved = async (context: any) => {
    const changes = await applyApprovedRows(notionClient(context));
    const applied = changes.filter((c) => c.applied).length;
    const errors = changes.filter((c) => !c.applied).length;
    return { applied, errors };
  };

  worker.tool("tidyNow", {
    title: "Tidy now",
    description: "Apply approved Gardener proposals from the Compost Pile immediately.",
    schema: j.object({}),
    outputSchema: applySchema,
    execute: async (_input: any, context: any) => {
      return runApplyApproved(context);
    },
  });

  worker.tool("applyApproved", {
    title: "Apply approved",
    description: "Apply approved Gardener proposals and stamp the Compost Pile rows.",
    schema: j.object({}),
    outputSchema: applySchema,
    execute: async (_input: any, context: any) => {
      return runApplyApproved(context);
    },
  });

  // reviewDraft is registered inside sleep-on-it.ts because it needs the same scope.
}
