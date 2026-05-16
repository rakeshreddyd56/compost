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
import {
  ageScore, orphanScore, stubScore, taglessScore, brokenLinkScore,
  decay, describeReason, pickAction, DECAY_THRESHOLD, type Signals,
} from "./utils/scoring";

const WORKSPACE_CAP = 500;

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
      const linkGraph = buildLinkGraph(pages);
      const scored = pages.map((p) => scoreOne(p, linkGraph));

      // --- Phase 4: Propose ---
      const proposalChanges = scored
        .filter((s) => s.decay >= DECAY_THRESHOLD)
        .map(toProposalChange);

      // --- Phase 5: Apply ---
      const applyChanges = await applyApproved(notion);

      return {
        changes: [...proposalChanges, ...applyChanges],
        hasMore: false,
      };
    },
  });
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
  return pages.filter((p) => !p.archived).slice(0, WORKSPACE_CAP);
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

  return { page, signals, decay: decay(signals) };
}

// ---------------- Phase 4: Propose ----------------

function toProposalChange(s: { page: any; signals: Signals; decay: number }) {
  const action = pickAction(s.signals);
  const id = proposalId(action, [s.page.id]);
  const emoji: Record<string, string> = { archive: "🗑️", delete_stub: "🌱", fix_link: "🔗", add_tag: "🏷️", merge: "🔀" };
  return {
    type: "upsert" as const,
    key: id,
    properties: {
      Title:            Builder.title(`${emoji[action] ?? "•"} ${pageTitle(s.page)}`),
      "Proposal ID":    Builder.richText(id),
      "Action":         Builder.select(action),
      "Target Page ID": Builder.richText(s.page.id),
      "Reason":         Builder.richText(describeReason(s.signals)),
      "Approved":       Builder.checkbox(false),
      "Applied":        Builder.checkbox(false),
    },
  };
}

// ---------------- Phase 5: Apply ----------------

export async function applyApproved(notion: any): Promise<any[]> {
  // TODO: replace with actual DB data-source ID once known after first deploy
  const COMPOST_PILE_DATA_SOURCE_ID = process.env.COMPOST_PILE_DATA_SOURCE_ID;
  if (!COMPOST_PILE_DATA_SOURCE_ID) return [];

  const res: any = await withRetryOn429(() =>
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

  const changes: any[] = [];
  for (const row of res.results) {
    const id = readText(row, "Proposal ID");
    try {
      await executeAction(notion, row);
      changes.push({
        type: "upsert",
        key: id,
        properties: { Applied: Builder.checkbox(true) },
      });
    } catch (e: any) {
      changes.push({
        type: "upsert",
        key: id,
        properties: { Error: Builder.richText(String(e).slice(0, 1900)) },
      });
    }
    await pace();
  }
  return changes;
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
      // TODO S5: walk page, find dead internal mentions, remove or replace
      break;
    case "merge": {
      // TODO S8: merge implementation
      const mergeWith = readText(row, "Merge With Page ID");
      if (mergeWith) await mergeIntoTarget(notion, mergeWith, target);
      break;
    }
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
