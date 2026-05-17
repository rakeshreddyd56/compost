/**
 * 🪴 Gardener — workspace hygiene worker.
 *
 * See ~/ObsidianVault/compost-hackathon/workflows/gardener.md for the full spec.
 *
 * Sprint phasing:
 *   S2 → Phases 1, 2 (walk + 3 signals), Phase 4 (propose) — archive + delete_stub only.
 *   S3 → Phase 5 (apply, idempotent) + tidyNow tool wiring.
 *   S5 → remaining signals (tagless, broken_link) + actions (fix_link, add_tag).
 *   S8 → Phase 3 (embedding-based dedup) + merge action.
 */

import * as Builder from "@notionhq/workers/builder";
import { pace, sleep, withRetryOn429 } from "./utils/rate-limit";
import { sha1, proposalId } from "./utils/hashing";
import { notionTokenReady, emptySync, warnMissingToken } from "./utils/env-guard";
import { notionClient } from "./utils/notion-auth";
import { createAuditPage } from "./utils/audit";
import {
  ageScore, orphanScore, stubScore, taglessScore, brokenLinkScore,
  decay, describeReason, pickAction, DECAY_THRESHOLD, type Signals,
} from "./utils/scoring";

const WORKSPACE_CAP = 500;
const DEMO_GARDENER_RE = /\[!(?:compost|gardener|stale)\]/i;

export interface ApplyApprovedResult {
  proposalId: string;
  applied: boolean;
  error?: string;
}

export interface ApplyProposalResult {
  ok: boolean;
  proposalId: string;
  action: string | null;
  targetPageId: string | null;
  applied: boolean;
  error: string | null;
}

export interface RefreshProposalsResult {
  proposed: number;
  upserted: number;
  errors: number;
}

export function registerGardener(worker: any, dbs: { compostPile: any; embeddingsCache: any; pacer: any }) {

  worker.sync("gardener", {
    database: dbs.compostPile,
    mode: "incremental",
    schedule: "1d",
    execute: async (state: any, context: any) => {
      if (!notionTokenReady()) { warnMissingToken("gardener"); return emptySync(); }
      const notion = notionClient(context);
      // --- Phase 1: Walk ---
      const pages = await walkWorkspace(notion);

      // --- Phase 2: Score ---
      const proposalChanges = buildProposalChanges(pages);

      // --- Phase 5: Apply ---
      const applyChanges = (await applyApproved(notion)).map(toApplyChange);

      return { changes: [...proposalChanges, ...applyChanges], hasMore: false };
    },
  });
}

export async function refreshProposals(notion: any): Promise<RefreshProposalsResult> {
  const COMPOST_PILE_DATA_SOURCE_ID = process.env.COMPOST_PILE_DATA_SOURCE_ID;
  if (!COMPOST_PILE_DATA_SOURCE_ID) return { proposed: 0, upserted: 0, errors: 1 };

  const proposals = buildProposals(await walkWorkspace(notion));
  let upserted = 0;
  let errors = 0;

  for (const proposal of proposals) {
    try {
      await upsertProposalRow(notion, COMPOST_PILE_DATA_SOURCE_ID, proposal);
      upserted += 1;
    } catch (e: any) {
      console.warn(`tidyNow failed to upsert ${proposal.proposalId}:`, String(e));
      errors += 1;
    }
    await pace();
  }

  return { proposed: proposals.length, upserted, errors };
}

// ---------------- Phase 1 ----------------

async function walkWorkspace(notion: any): Promise<any[]> {
  const pages: any[] = [];
  let cursor: string | undefined = undefined;

  while (pages.length < WORKSPACE_CAP) {
    const res: any = await withRetryOn429(() => notion.search({
      filter: { property: "object", value: "page" },
      page_size: 100,
      start_cursor: cursor,
      sort: { timestamp: "last_edited_time", direction: "descending" },
    }));
    pages.push(...res.results);
    if (!res.has_more) break;
    cursor = res.next_cursor;
    await pace();
  }

  // Fetch content blocks for each page
  for (const p of pages) {
    if (p.archived) continue;
    p._blocks = await fetchFirstBlocks(notion, p.id, 20);
    await pace();
  }
  return pages
    .filter((p) => !p.archived && !isCompostManagedRow(p))
    .slice(0, WORKSPACE_CAP);
}

async function fetchFirstBlocks(notion: any, pageId: string, limit: number): Promise<any[]> {
  try {
    const res: any = await withRetryOn429(() =>
      notion.blocks.children.list({ block_id: pageId, page_size: limit })
    );
    return res.results;
  } catch {
    return [];
  }
}

// ---------------- Phase 2 ----------------

function buildLinkGraph(pages: any[]) {
  const inbound = new Map<string, number>();
  const knownIds = new Set(pages.map((p) => p.id));
  for (const p of pages) {
    for (const target of extractMentionedPageIds(p._blocks ?? [])) {
      inbound.set(target, (inbound.get(target) ?? 0) + 1);
    }
    for (const v of Object.values(p.properties ?? {})) {
      if ((v as any)?.type === "relation") {
        for (const r of (v as any).relation) {
          inbound.set(r.id, (inbound.get(r.id) ?? 0) + 1);
        }
      }
    }
  }
  return { inbound, knownIds };
}

function scoreOne(page: any, linkGraph: { inbound: Map<string, number>; knownIds: Set<string> }) {
  const days = (Date.now() - new Date(page.last_edited_time).getTime()) / 86_400_000;
  const blocks = page._blocks ?? [];
  const words = wordCountOfBlocks(blocks);
  const internalIds = extractMentionedPageIds(blocks);

  const signals: Signals = {
    age:     ageScore(page.last_edited_time),
    orphan:  orphanScore(linkGraph.inbound.get(page.id) ?? 0),
    stub:    stubScore(words, hasChildBlocks(blocks), days),
    tagless: taglessScore(page, days),
    broken:  brokenLinkScore(internalIds, linkGraph.knownIds),
  };

  if (isDemoGardenerSeed(page, blocks)) {
    const demoSignals: Signals = { age: 1, orphan: 1, stub: 1, tagless: 1, broken: 0 };
    return { page, signals: demoSignals, decay: decay(demoSignals) };
  }

  return { page, signals, decay: decay(signals) };
}

// ---------------- Phase 4: Propose ----------------

interface Proposal {
  title: string;
  proposalId: string;
  action: string;
  targetPageId: string;
  reason: string;
}

function buildProposalChanges(pages: any[]) {
  return buildProposals(pages).map(proposalChangeFromProposal);
}

function buildProposals(pages: any[]) {
  const linkGraph = buildLinkGraph(pages);
  return pages
    .map((p) => scoreOne(p, linkGraph))
    .filter((s) => s.decay >= DECAY_THRESHOLD)
    .map(toProposal);
}

function proposalChangeFromProposal(proposal: Proposal) {
  return {
    type: "upsert" as const,
    key: proposal.proposalId,
    properties: {
      Title:            Builder.title(proposal.title),
      "Proposal ID":    Builder.richText(proposal.proposalId),
      "Action":         Builder.select(proposal.action),
      "Target Page ID": Builder.richText(proposal.targetPageId),
      "Reason":         Builder.richText(proposal.reason),
      "Approved":       Builder.checkbox(false),
      "Applied":        Builder.checkbox(false),
    },
  };
}

function toProposal(s: { page: any; signals: Signals; decay: number }): Proposal {
  const action = pickAction(s.signals);
  const id = proposalId(action, [s.page.id]);
  const emoji: Record<string, string> = { archive: "🗑️", delete_stub: "🌱", fix_link: "🔗", add_tag: "🏷️", merge: "🔀" };
  return {
    title: `${emoji[action] ?? "•"} ${pageTitle(s.page)}`,
    proposalId: id,
    action,
    targetPageId: s.page.id,
    reason: describeReason(s.signals),
  };
}

function toApplyChange(result: ApplyApprovedResult) {
  return {
    type: "upsert" as const,
    key: result.proposalId,
    properties: result.applied
      ? { Applied: Builder.checkbox(true) }
      : { Error: Builder.richText(result.error ?? "Unknown apply error") },
  };
}

// ---------------- Phase 5: Apply ----------------

export async function applyApproved(notion: any): Promise<ApplyApprovedResult[]> {
  // TODO: replace with actual DB data-source ID once known after first deploy
  const COMPOST_PILE_DATA_SOURCE_ID = process.env.COMPOST_PILE_DATA_SOURCE_ID;
  if (!COMPOST_PILE_DATA_SOURCE_ID) return [];

  let res: any;
  try {
    res = await withRetryOn429(() =>
      notion.dataSources.query({
        data_source_id: COMPOST_PILE_DATA_SOURCE_ID,
        filter: {
          and: [
            { property: "Approved", checkbox: { equals: true } },
            { property: "Applied",  checkbox: { equals: false } },
          ],
        },
      })
    );
  } catch (e: any) {
    if (isNotionObjectNotFound(e)) {
      console.warn("applyApproved skipped: Compost Pile data source is not shared with the integration");
      return [];
    }
    throw e;
  }

  const changes: ApplyApprovedResult[] = [];
  for (const row of res.results) {
    const result = await applyProposalRow(notion, row);
    changes.push({
      proposalId: result.proposalId,
      applied: result.ok && result.applied,
      error: result.error ?? undefined,
    });
    await pace();
  }
  return changes;
}

export async function applyProposal(notion: any, rawProposalId: string): Promise<ApplyProposalResult> {
  const proposalId = String(rawProposalId ?? "").trim();
  const empty = (error: string): ApplyProposalResult => ({
    ok: false,
    proposalId,
    action: null,
    targetPageId: null,
    applied: false,
    error,
  });

  if (!proposalId) return empty("Missing proposalId");

  const COMPOST_PILE_DATA_SOURCE_ID = process.env.COMPOST_PILE_DATA_SOURCE_ID;
  if (!COMPOST_PILE_DATA_SOURCE_ID) {
    return empty("COMPOST_PILE_DATA_SOURCE_ID not set");
  }

  let row: any | null;
  try {
    row = await fetchProposalRow(notion, COMPOST_PILE_DATA_SOURCE_ID, proposalId);
  } catch (e: any) {
    if (isNotionObjectNotFound(e)) return empty("Compost Pile data source is not shared with the integration");
    return empty(shortError(e));
  }

  if (!row) return empty("proposal not found");
  return applyProposalRow(notion, row);
}

async function applyProposalRow(notion: any, row: any): Promise<ApplyProposalResult> {
  const proposalId = readText(row, "Proposal ID");
  const action = readSelect(row, "Action");
  const targetPageId = readText(row, "Target Page ID");
  const fail = async (error: string): Promise<ApplyProposalResult> => {
    await createAuditPage(notion, {
      title: `[!audit] Compost proposal failed - ${proposalId || "missing proposal"}`,
      lines: [
        `Time: ${new Date().toISOString()}`,
        `Proposal ID: ${proposalId || "(missing)"}`,
        `Action: ${action || "(missing)"}`,
        `Target Page ID: ${targetPageId || "(missing)"}`,
        `Result: failed`,
        `Error: ${shortError(error)}`,
      ],
    });
    await tryStampProposal(notion, row.id, { applied: false, error: shortError(error) });
    return { ok: false, proposalId, action, targetPageId, applied: false, error: shortError(error) };
  };

  if (!proposalId) return fail("Missing Proposal ID");
  if (!action) return fail("Missing Action");
  if (!targetPageId) return fail("Missing Target Page ID");
  if (readCheckbox(row, "Applied")) {
    return { ok: true, proposalId, action, targetPageId, applied: true, error: null };
  }

  try {
    await assertSafeDemoTarget(notion, targetPageId);
    await executeAction(notion, row);
    await createAuditPage(notion, {
      title: `[!audit] Compost proposal applied - ${proposalId}`,
      lines: [
        `Time: ${new Date().toISOString()}`,
        `Proposal ID: ${proposalId}`,
        `Action: ${action}`,
        `Target Page ID: ${targetPageId}`,
        `Result: applied`,
        "Safety: target was explicitly marked as a Compost demo page.",
      ],
    });
    await tryStampProposal(notion, row.id, { approved: true, applied: true, error: null });
    return { ok: true, proposalId, action, targetPageId, applied: true, error: null };
  } catch (e: any) {
    return fail(e);
  }
}

async function upsertProposalRow(notion: any, dataSourceId: string, proposal: Proposal) {
  const existing = await fetchProposalRow(notion, dataSourceId, proposal.proposalId);
  const properties = proposalProperties(proposal, { includeWorkflowFields: !existing });

  if (existing) {
    await notion.pages.update({ page_id: existing.id, properties });
    return;
  }

  await notion.pages.create({
    parent: { data_source_id: dataSourceId },
    properties,
  });
}

async function fetchProposalRow(notion: any, dataSourceId: string, proposalId: string): Promise<any | null> {
  const res: any = await withRetryOn429(() =>
    notion.dataSources.query({
      data_source_id: dataSourceId,
      filter: { property: "Proposal ID", rich_text: { equals: proposalId } },
    })
  );
  return res.results[0] ?? null;
}

function proposalProperties(proposal: Proposal, opts: { includeWorkflowFields: boolean }) {
  const properties: any = {
    Title: titleProp(proposal.title),
    "Proposal ID": richTextProp(proposal.proposalId),
    Action: { select: { name: proposal.action } },
    "Target Page ID": richTextProp(proposal.targetPageId),
    Reason: richTextProp(proposal.reason),
  };
  if (opts.includeWorkflowFields) {
    properties.Approved = { checkbox: false };
    properties.Applied = { checkbox: false };
    properties.Error = { rich_text: [] };
  }
  return properties;
}

async function stampProposal(notion: any, pageId: string, fields: { approved?: boolean; applied?: boolean; error?: string | null }) {
  const properties: any = {};
  if (fields.approved != null) properties.Approved = { checkbox: fields.approved };
  if (fields.applied != null) properties.Applied = { checkbox: fields.applied };
  if (fields.error === null) {
    properties.Error = { rich_text: [] };
  } else if (fields.error) {
    properties.Error = richTextProp(fields.error);
  }
  if (Object.keys(properties).length === 0) return;
  await notion.pages.update({ page_id: pageId, properties });
}

async function tryStampProposal(notion: any, pageId: string, fields: { approved?: boolean; applied?: boolean; error?: string | null }) {
  try {
    await stampProposal(notion, pageId, fields);
  } catch (e: any) {
    console.warn("proposal row stamp skipped:", shortError(e));
  }
}

function isNotionObjectNotFound(e: any): boolean {
  return e?.code === "object_not_found" || /Could not find database|not shared with your integration/i.test(String(e?.message ?? e));
}

async function executeAction(notion: any, row: any) {
  const action = row.properties.Action?.select?.name;
  const target = readText(row, "Target Page ID");
  if (!target) throw new Error("missing Target Page ID");

  switch (action) {
    case "archive":
    case "delete_stub":
      await notion.pages.update({ page_id: target, archived: true });
      break;
    case "add_tag":
      await notion.pages.update({
        page_id: target,
        properties: { Status: { select: { name: "Inbox" } } },
      });
      break;
    case "fix_link":
      throw new Error("fix_link proposals are not implemented in the live demo yet");
    case "merge":
      throw new Error("merge proposals are not implemented in the live demo yet");
    default:
      throw new Error(`unknown action: ${action}`);
  }
}

async function mergeIntoTarget(notion: any, keepId: string, archiveId: string) {
  const blocks = await notion.blocks.children.list({ block_id: archiveId });
  await notion.blocks.children.append({
    block_id: keepId,
    children: [
      { type: "divider", divider: {} },
      { type: "heading_3", heading_3: { rich_text: [{ type: "text", text: { content: "↪ Merged content" } }] } },
      ...blocks.results.map(stripBlockIds),
    ],
  });
  await notion.pages.update({ page_id: archiveId, archived: true });
}

// ---------------- helpers ----------------

function pageTitle(page: any): string {
  for (const v of Object.values(page.properties ?? {})) {
    if ((v as any)?.type === "title") {
      return ((v as any).title ?? []).map((t: any) => t.plain_text).join("") || "Untitled";
    }
  }
  return "Untitled";
}

function readText(row: any, key: string): string {
  const p = row.properties?.[key];
  if (!p) return "";
  if (p.type === "rich_text") return (p.rich_text ?? []).map((t: any) => t.plain_text).join("");
  if (p.type === "title")     return (p.title ?? []).map((t: any) => t.plain_text).join("");
  return "";
}

function readSelect(row: any, key: string): string {
  return row.properties?.[key]?.select?.name ?? "";
}

function readCheckbox(row: any, key: string): boolean {
  return row.properties?.[key]?.checkbox === true;
}

async function assertSafeDemoTarget(notion: any, pageId: string) {
  const page: any = await withRetryOn429(() => notion.pages.retrieve({ page_id: pageId }));
  if (DEMO_GARDENER_RE.test(pageTitle(page))) return;

  const blocks = page.archived ? [] : await fetchFirstBlocks(notion, pageId, 20);
  if (isDemoGardenerSeed(page, blocks)) return;

  throw new Error("Refusing to mutate non-demo page. Add [!compost] to the target page title/body for this hackathon demo.");
}

function wordCountOfBlocks(blocks: any[]): number {
  const text = blocks.map((b) => extractBlockText(b)).join(" ");
  return text.split(/\s+/).filter(Boolean).length;
}

function extractBlockText(block: any): string {
  const rt = block?.[block?.type]?.rich_text;
  if (Array.isArray(rt)) return rt.map((t: any) => t.plain_text ?? "").join("");
  return "";
}

function hasChildBlocks(blocks: any[]): boolean {
  return blocks.some((b) => b.has_children);
}

function extractMentionedPageIds(blocks: any[]): string[] {
  const out: string[] = [];
  for (const b of blocks) {
    const rt = b?.[b?.type]?.rich_text ?? [];
    for (const t of rt) {
      if (t.type === "mention" && t.mention?.type === "page") out.push(t.mention.page.id);
    }
  }
  return out;
}

function stripBlockIds(b: any): any {
  const copy: any = { type: b.type, [b.type]: b[b.type] };
  return copy;
}

function isCompostManagedRow(page: any): boolean {
  const props = page.properties ?? {};
  return Boolean(props["Proposal ID"] || props["Draft ID"] || props["Card ID"] || props["Content Hash"]);
}

function isDemoGardenerSeed(page: any, blocks: any[]): boolean {
  if (DEMO_GARDENER_RE.test(pageTitle(page))) return true;
  return blocks.some((b) => DEMO_GARDENER_RE.test(extractBlockText(b)));
}

function richTextProp(text: string) {
  return {
    rich_text: chunkText(text).map((content) => ({
      type: "text",
      text: { content },
    })),
  };
}

function titleProp(text: string) {
  return {
    title: [{ type: "text", text: { content: String(text).slice(0, 1800) || "Untitled" } }],
  };
}

function shortError(e: any): string {
  return String(e?.message ?? e).slice(0, 1900);
}

function chunkText(text: string, size = 1800): string[] {
  if (!text) return [];
  const out: string[] = [];
  for (let i = 0; i < text.length; i += size) out.push(text.slice(i, i + size));
  return out;
}
