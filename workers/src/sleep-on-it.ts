/**
 * 🌙 Sleep-On-It — late-night draft freezer.
 *
 * See workflows/sleep-on-it.md.
 *
 * - webhook("onLateNightEdit") receives Notion page.content_updated events.
 * - sync("sleepOnItReviewer") flips Status frozen→ready between 07:00-10:00 local.
 * - sync("sleepOnItCleanup") archives stale drafts after 7d.
 * - tool("reviewDraft") executes approve/reject from the app.
 */

import crypto from "node:crypto";
import * as Builder from "@notionhq/workers/builder";
import { j } from "@notionhq/workers/schema-builder";
import { pace, withRetryOn429 } from "./utils/rate-limit";
import { sha1 } from "./utils/hashing";
import { isLateNight, isMorningReviewWindow } from "./utils/time";

class WebhookVerificationError extends Error {}

export function registerSleepOnIt(worker: any, dbs: { frozenDrafts: any }) {

  worker.webhook("onLateNightEdit", {
    title: "Late-night edit handler",
    description: "Receives Notion page.content_updated events; freezes late-night drafts for morning review.",
    execute: async (events: any[], context: any) => {
      for (const event of events) {
        // First-time verification handshake — Notion sends a verification_token
        if (event.body?.verification_token) {
          // The human MUST run `ntn workers env set NOTION_WEBHOOK_SECRET=<token>` next
          console.log("VERIFICATION TOKEN — set as NOTION_WEBHOOK_SECRET:", event.body.verification_token);
          return { challenge: event.body.verification_token };
        }
        verifySignature(event);
        await handleEdit(event, context);
      }
    },
  });

  worker.sync("sleepOnItReviewer", {
    database: dbs.frozenDrafts,
    mode: "incremental",
    schedule: "15m",
    execute: async (state: any, context: any) => {
      const tz = process.env.USER_TIMEZONE || "America/Los_Angeles";
      if (!isMorningReviewWindow(tz)) return { changes: [], hasMore: false };

      const FROZEN_DS = process.env.FROZEN_DRAFTS_DATA_SOURCE_ID;
      if (!FROZEN_DS) return { changes: [], hasMore: false };

      const res = await withRetryOn429(() => context.notion.databases.query({
        database_id: FROZEN_DS,
        filter: { property: "Status", select: { equals: "frozen" } },
      }));
      const changes = res.results.map((row: any) => ({
        type: "upsert" as const,
        key: readText(row, "Draft ID"),
        properties: { Status: Builder.select("ready") },
      }));
      return { changes, hasMore: false };
    },
  });

  worker.sync("sleepOnItCleanup", {
    database: dbs.frozenDrafts,
    mode: "incremental",
    schedule: "1d",
    execute: async (state: any, context: any) => {
      const FROZEN_DS = process.env.FROZEN_DRAFTS_DATA_SOURCE_ID;
      if (!FROZEN_DS) return { changes: [], hasMore: false };

      const sevenDaysAgo = new Date(Date.now() - 7 * 86_400_000).toISOString();
      const res = await withRetryOn429(() => context.notion.databases.query({
        database_id: FROZEN_DS,
        filter: {
          and: [
            { property: "Status", select: { equals: "ready" } },
            { property: "Frozen At", date: { before: sevenDaysAgo } },
          ],
        },
      }));
      const changes = res.results.map((row: any) => ({
        type: "upsert" as const,
        key: readText(row, "Draft ID"),
        properties: { Status: Builder.select("expired") },
      }));
      return { changes, hasMore: false };
    },
  });

  worker.tool("reviewDraft", {
    title: "Review a frozen draft",
    description: "Approve (write rewrite to source page) or reject (discard, source page unchanged).",
    schema: j.object({
      draftId: j.string().describe("Draft ID from frozenDrafts"),
      decision: j.enum("approve", "reject"),
    }),
    outputSchema: j.object({ ok: j.boolean(), error: j.string().nullable() }),
    execute: async ({ draftId, decision }: any, context: any) => {
      const FROZEN_DS = process.env.FROZEN_DRAFTS_DATA_SOURCE_ID;
      if (!FROZEN_DS) return { ok: false, error: "FROZEN_DRAFTS_DATA_SOURCE_ID not set" };

      const row = await fetchDraftRow(context.notion, FROZEN_DS, draftId);
      if (!row) return { ok: false, error: "draft not found" };

      if (decision === "approve") {
        const sourcePageId = readText(row, "Source Page ID");
        const rewrite = readText(row, "Rewrite");
        try {
          await replacePageContent(context.notion, sourcePageId, rewrite);
          await stampDraft(context.notion, row.id, { status: "approved" });
        } catch (e: any) {
          await stampDraft(context.notion, row.id, { status: "error", error: String(e).slice(0, 1900) });
          return { ok: false, error: String(e) };
        }
      } else {
        await stampDraft(context.notion, row.id, { status: "rejected" });
      }
      return { ok: true, error: null };
    },
  });
}

// ---------------- handlers ----------------

function verifySignature(event: any) {
  const secret = process.env.NOTION_WEBHOOK_SECRET;
  if (!secret) throw new WebhookVerificationError("NOTION_WEBHOOK_SECRET not set");
  const headerVal = event.headers?.["x-notion-signature"] ?? "";
  const expected = "sha256=" + crypto.createHmac("sha256", secret).update(event.rawBody).digest("hex");
  const a = Buffer.from(headerVal);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    throw new WebhookVerificationError("bad signature");
  }
}

async function handleEdit(event: any, context: any) {
  const pageId = event.body?.entity?.id ?? event.body?.page_id;
  if (!pageId) return;

  const tz = process.env.USER_TIMEZONE || "America/Los_Angeles";
  if (!isLateNight(tz)) return;

  const page = await context.notion.pages.retrieve({ page_id: pageId });
  if (page.archived) return;

  const blocks = await context.notion.blocks.children.list({ block_id: pageId, page_size: 50 });
  const markdown = blocksToMarkdown(blocks.results);
  if (wordCount(markdown) < 30) return;

  // Skip if [!ship] tag present in title
  const title = pageTitle(page);
  if (/\[!ship\]/i.test(title)) return;

  // Dedup: skip if active draft exists for this page already tonight
  if (await hasActiveDraft(context.notion, pageId)) return;

  const draftId = sha1(`${pageId}|${new Date().toISOString().slice(0, 10)}`);

  // Snapshot
  await upsertFrozenDraftRow(context.notion, {
    draftId, pageId, title, original: markdown, rewrite: "", status: "pending",
    frozenAt: new Date().toISOString(),
  });

  // LLM rewrite
  try {
    const rewrite = await calmRewrite(markdown, title);
    await upsertFrozenDraftRow(context.notion, { draftId, status: "frozen", rewrite });
  } catch (e: any) {
    await upsertFrozenDraftRow(context.notion, { draftId, status: "error", error: String(e).slice(0, 1900) });
  }
}

async function calmRewrite(markdown: string, title: string): Promise<string> {
  const prompt = `You are a calm morning editor. Below is something I wrote late at night. Rewrite it preserving every fact, name, and structural section — but soften the tone for a calmer audience.

Rules:
- Keep all facts and references intact.
- Convert ALL-CAPS phrases to normal capitalization unless they're acronyms.
- Soften rhetorical absolutes ("never", "always", "everyone") to measured language; keep factual absolutes intact.
- Defang accusations and inflammatory framings; keep the substance.
- Preserve markdown structure (headings, lists, code blocks).
- Do NOT add new opinions or change the author's voice — just tone down the volume.
- Output ONLY the rewritten markdown. No preamble.

Title: ${title}

Original:
${markdown}`;

  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": process.env.ANTHROPIC_API_KEY ?? "",
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5",
      max_tokens: Math.min(4096, markdown.length * 2),
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!r.ok) throw new Error(`Anthropic API ${r.status}: ${await r.text()}`);
  const json: any = await r.json();
  return json.content?.[0]?.text ?? "";
}

// ---------------- DB helpers (skeletons — flesh out using @notionhq/client patterns) ----------------

async function upsertFrozenDraftRow(notion: any, fields: any) {
  // TODO: implement using FROZEN_DRAFTS_DATA_SOURCE_ID and pages.create / pages.update
  // Look up by Draft ID first; create if missing, update if exists.
}

async function hasActiveDraft(notion: any, pageId: string): Promise<boolean> {
  // TODO: query frozenDrafts where Source Page ID = pageId AND Status in (pending, frozen, ready)
  return false;
}

async function fetchDraftRow(notion: any, dataSourceId: string, draftId: string): Promise<any | null> {
  const res = await notion.databases.query({
    database_id: dataSourceId,
    filter: { property: "Draft ID", rich_text: { equals: draftId } },
  });
  return res.results[0] ?? null;
}

async function stampDraft(notion: any, pageId: string, fields: { status: string; error?: string }) {
  const properties: any = {
    Status:        { select: { name: fields.status } },
    "Reviewed At": { date: { start: new Date().toISOString() } },
  };
  if (fields.error) properties["Error"] = { rich_text: [{ type: "text", text: { content: fields.error } }] };
  await notion.pages.update({ page_id: pageId, properties });
}

async function replacePageContent(notion: any, pageId: string, markdown: string) {
  const current = await notion.blocks.children.list({ block_id: pageId });
  for (const b of current.results) {
    await notion.blocks.delete({ block_id: b.id });
    await pace();
  }
  const newBlocks = markdownToBlocks(markdown);
  await notion.blocks.children.append({ block_id: pageId, children: newBlocks });
}

// ---------------- text helpers (TODO: implement) ----------------

function blocksToMarkdown(blocks: any[]): string {
  // TODO: minimal converter — paragraph, heading_1-3, bulleted_list_item, numbered_list_item, code, divider
  return blocks
    .map((b) => {
      const text = (b?.[b?.type]?.rich_text ?? []).map((t: any) => t.plain_text).join("");
      switch (b.type) {
        case "heading_1": return `# ${text}`;
        case "heading_2": return `## ${text}`;
        case "heading_3": return `### ${text}`;
        case "bulleted_list_item": return `- ${text}`;
        case "numbered_list_item": return `1. ${text}`;
        case "code": return "```\n" + text + "\n```";
        case "divider": return "---";
        default: return text;
      }
    })
    .filter(Boolean)
    .join("\n");
}

function markdownToBlocks(md: string): any[] {
  // TODO: minimal inverse converter
  return md.split("\n").map((line) => {
    if (line.startsWith("# "))   return blockH(1, line.slice(2));
    if (line.startsWith("## "))  return blockH(2, line.slice(3));
    if (line.startsWith("### ")) return blockH(3, line.slice(4));
    if (line.startsWith("- "))   return blockBullet(line.slice(2));
    if (line === "---")          return { type: "divider", divider: {} };
    if (line.trim() === "")      return { type: "paragraph", paragraph: { rich_text: [] } };
    return blockPara(line);
  });
}

function blockPara(t: string) {
  return { type: "paragraph", paragraph: { rich_text: [{ type: "text", text: { content: t } }] } };
}
function blockH(n: 1 | 2 | 3, t: string): any {
  const key = `heading_${n}` as const;
  return { type: key, [key]: { rich_text: [{ type: "text", text: { content: t } }] } };
}
function blockBullet(t: string): any {
  return { type: "bulleted_list_item", bulleted_list_item: { rich_text: [{ type: "text", text: { content: t } }] } };
}

function wordCount(s: string): number {
  return s.split(/\s+/).filter(Boolean).length;
}

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
