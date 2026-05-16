/**
 * Worker tools exposed to the macOS app (and to Notion Custom Agents).
 */

import { j } from "@notionhq/workers/schema-builder";
import { applyApproved } from "./gardener";

export function registerTools(worker: any, dbs: { compostPile: any; frozenDrafts: any }) {

  worker.tool("tidyNow", {
    title: "Tidy now",
    description: "Apply approved Gardener proposals from the Compost Pile immediately.",
    schema: j.object({}),
    outputSchema: j.object({
      applied: j.number(),
      errors: j.number(),
    }),
    execute: async (_input: any, context: any) => {
      const changes = await applyApproved(context.notion);
      const applied = changes.filter((c: any) => c?.properties?.Applied).length;
      const errors  = changes.filter((c: any) => c?.properties?.Error).length;
      return { applied, errors };
    },
  });

  // reviewDraft is registered inside sleep-on-it.ts because it needs the same scope.
}
