/**
 * Worker tools exposed to the macOS app (and to Notion Custom Agents).
 */

import { j } from "@notionhq/workers/schema-builder";
import {
  applyApproved as applyApprovedRows,
  applyProposal,
  refreshProposals,
} from "./gardener";
import { ingestMemoryNow } from "./memory";
import { notionClient } from "./utils/notion-auth";

export function registerTools(worker: any, dbs: { compostPile: any; frozenDrafts: any }) {
  const applySchema = j.object({
    applied: j.number(),
    errors: j.number(),
  });
  const refreshSchema = j.object({
    proposed: j.number(),
    upserted: j.number(),
    errors: j.number(),
  });
  const applyProposalSchema = j.object({
    ok: j.boolean(),
    proposalId: j.string(),
    action: j.string().nullable(),
    targetPageId: j.string().nullable(),
    applied: j.boolean(),
    error: j.string().nullable(),
  });
  const bridgeSchema = j.object({
    ok: j.boolean(),
    surface: j.enum("cue", "memory", "tidy", "all"),
    cueCards: j.number(),
    memoryRecords: j.number(),
    tidyProposals: j.number(),
    notes: j.array(j.string()),
    errors: j.array(j.string()),
  });

  const runApplyApproved = async (context: any) => {
    const changes = await applyApprovedRows(notionClient(context));
    const applied = changes.filter((c) => c.applied).length;
    const errors = changes.filter((c) => !c.applied).length;
    return { applied, errors };
  };

  worker.tool("tidyNow", {
    title: "Refresh tidy proposals",
    description: "Rescan the workspace and refresh Gardener proposals in the Compost Pile. Does not apply proposals.",
    schema: j.object({}),
    outputSchema: refreshSchema,
    execute: async (_input: any, context: any) => {
      return refreshProposals(notionClient(context));
    },
  });

  worker.tool("applyApproved", {
    title: "Apply approved",
    description: "Legacy batch apply for approved Gardener proposals. Uses the same safe-demo guard as applyProposal.",
    schema: j.object({}),
    outputSchema: applySchema,
    execute: async (_input: any, context: any) => {
      return runApplyApproved(context);
    },
  });

  worker.tool("applyProposal", {
    title: "Apply one proposal",
    description: "Approve and apply one Gardener proposal by Proposal ID. Refuses non-demo targets.",
    schema: j.object({
      proposalId: j.string().describe("Stable Proposal ID from the Compost Pile row."),
    }),
    outputSchema: applyProposalSchema,
    execute: async ({ proposalId }: any, context: any) => {
      return applyProposal(notionClient(context), proposalId);
    },
  });

  worker.tool("refreshBridge", {
    title: "Refresh Compost bridge",
    description: "Agent-callable refresh for cue, memory, tidy, or all bridge surfaces.",
    schema: j.object({
      surface: j.enum("cue", "memory", "tidy", "all"),
    }),
    outputSchema: bridgeSchema,
    execute: async ({ surface }: any, context: any) => {
      const notion = notionClient(context);
      const errors: string[] = [];
      const notes: string[] = [];
      let cueCards = 0;
      let memoryRecords = 0;
      let tidyProposals = 0;

      if (surface === "cue" || surface === "all") {
        notes.push("Cue Cards are Worker-sync managed; update [!cue] Agent Briefing Inbox and the 5-minute cue sync publishes them.");
      }

      if (surface === "memory" || surface === "all") {
        try {
          const r = await ingestMemoryNow(notion);
          memoryRecords = r.records;
          if (r.errors) errors.push(`memory:${r.errors}`);
        } catch (e: any) {
          errors.push(`memory:${shortError(e)}`);
        }
      }

      if (surface === "tidy" || surface === "all") {
        try {
          const r = await refreshProposals(notion);
          tidyProposals = r.upserted || r.proposed;
          if (r.errors) errors.push(`tidy:${r.errors}`);
        } catch (e: any) {
          errors.push(`tidy:${shortError(e)}`);
        }
      }

      return { ok: errors.length === 0, surface, cueCards, memoryRecords, tidyProposals, notes, errors };
    },
  });

  // reviewDraft is registered inside sleep-on-it.ts because it needs the same scope.
}

function shortError(e: any): string {
  return String(e?.message ?? e).slice(0, 500);
}
