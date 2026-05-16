/**
 * Worker tools exposed to the macOS app (and to Notion Custom Agents).
 */

import { j } from "@notionhq/workers/schema-builder";
import {
  applyApproved as applyApprovedRows,
  applyProposal,
  refreshProposals,
} from "./gardener";
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

  // reviewDraft is registered inside sleep-on-it.ts because it needs the same scope.
}
