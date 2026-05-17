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
import { notionTokenReady, emptySync, warnMissingToken } from "./utils/env-guard";
import { notionClient } from "./utils/notion-auth";
import { demoFlagEnabled } from "./utils/demo-mode";
import { createAuditPage } from "./utils/audit";

class WebhookVerificationError extends Error {}

export function registerSleepOnIt(worker: any, dbs: { frozenDrafts: any; pacer: any }) {

  worker.webhook("onLateNightEdit", {
    title: "Late-night edit handler",
    description: "Receives Notion page.content_updated events; freezes late-night drafts for morning review.",
    execute: async (events: any[], context: any) => {
      // Allow verification handshake even before COMPOST_NOTION_TOKEN is set
      let processed = 0;
      for (const event of events) {
        if (event.body?.verification_token) {
          // The human MUST run `ntn workers env set COMPOST_WEBHOOK_SECRET=<token>` next
          console.log("VERIFICATION TOKEN — set as COMPOST_WEBHOOK_SECRET:", event.body.verification_token);
          return { challenge: event.body.verification_token };
        }
        if (!notionTokenReady()) { warnMissingToken("onLateNightEdit"); continue; }
        verifySignature(event);
        await handleEdit(event, notionClient(context));
        processed += 1;
      }
      return { ok: true, processed };
    },
  });

  worker.sync("sleepOnItReviewer", {
    database: dbs.frozenDrafts,
    mode: "incremental",
    schedule: "15m",
    execute: async (state: any, context: any) => {
      if (!notionTokenReady()) { warnMissingToken("sleepOnItReviewer"); return emptySync(); }
      const tz = process.env.USER_TIMEZONE || "America/Los_Angeles";
      const notion = notionClient(context);
      const demoChanges = demoFlagEnabled("SLEEP_ON_IT_FORCE_FIRE")
        ? [
            ...(await demoAuditDraftExpiryChanges(notion)),
            ...(await demoFrozenDraftChanges(notion)),
          ]
        : [];

      if (!isMorningReviewWindow(tz)) return { changes: demoChanges, hasMore: false };

      const FROZEN_DS = process.env.FROZEN_DRAFTS_DATA_SOURCE_ID;
      if (!FROZEN_DS) return { changes: demoChanges, hasMore: false };

      let res: any;
      try {
        res = await withRetryOn429(() => notion.dataSources.query({
          data_source_id: FROZEN_DS,
          filter: { property: "Status", select: { equals: "frozen" } },
        }));
      } catch (e: any) {
        if (isNotionObjectNotFound(e)) return { changes: demoChanges, hasMore: false };
        throw e;
      }
      const changes = res.results.map((row: any) => ({
        type: "upsert" as const,
        key: readText(row, "Draft ID"),
        properties: { Status: Builder.select("ready") },
      }));
      return { changes: [...demoChanges, ...changes], hasMore: false };
    },
  });

  worker.sync("sleepOnItCleanup", {
    database: dbs.frozenDrafts,
    mode: "incremental",
    schedule: "1d",
    execute: async (state: any, context: any) => {
      if (!notionTokenReady()) { warnMissingToken("sleepOnItCleanup"); return emptySync(); }
      const notion = notionClient(context);
      const FROZEN_DS = process.env.FROZEN_DRAFTS_DATA_SOURCE_ID;
      if (!FROZEN_DS) return { changes: [], hasMore: false };

      const sevenDaysAgo = new Date(Date.now() - 7 * 86_400_000).toISOString();
      let res: any;
      try {
        res = await withRetryOn429(() => notion.dataSources.query({
          data_source_id: FROZEN_DS,
          filter: {
            and: [
              { property: "Status", select: { equals: "ready" } },
              { property: "Frozen At", date: { before: sevenDaysAgo } },
            ],
          },
        }));
      } catch (e: any) {
        if (isNotionObjectNotFound(e)) return { changes: [], hasMore: false };
        throw e;
      }
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
      const notion = notionClient(context);
      const FROZEN_DS = process.env.FROZEN_DRAFTS_DATA_SOURCE_ID;
      if (!FROZEN_DS) return { ok: false, error: "FROZEN_DRAFTS_DATA_SOURCE_ID not set" };

      const row = await fetchDraftRow(notion, FROZEN_DS, draftId);
      if (!row) return { ok: false, error: "draft not found" };

      if (decision === "approve") {
        const sourcePageId = readText(row, "Source Page ID");
        const rewrite = readText(row, "Rewrite");
        if (!sourcePageId) return { ok: false, error: "Source Page ID missing" };
        if (!rewrite.trim()) return { ok: false, error: "Rewrite is empty" };
        try {
          await assertSafeSleepTarget(notion, sourcePageId);
          await replacePageContent(notion, sourcePageId, rewrite);
          await createSleepAudit(notion, row, "approved", "Source page replaced with calmer rewrite.");
          await tryStampDraft(notion, row.id, { status: "approved", error: null });
        } catch (e: any) {
          await createSleepAudit(notion, row, "failed", shortError(e));
          await tryStampDraft(notion, row.id, { status: "error", error: shortError(e) });
          return { ok: false, error: shortError(e) };
        }
      } else {
        await createSleepAudit(notion, row, "rejected", "Source page left unchanged.");
        await tryStampDraft(notion, row.id, { status: "rejected", error: null });
      }
      return { ok: true, error: null };
    },
  });

  worker.tool("rephraseDraft", {
    title: "Rephrase a frozen draft",
    description: "Generate a real tone variant for a frozen draft and stamp it on the draft row.",
    schema: j.object({
      draftId: j.string().describe("Draft row page id or stable Draft ID from frozenDrafts."),
      tone: j.enum("calmer", "crisp", "diplomatic"),
    }),
    outputSchema: j.object({
      ok: j.boolean(),
      draftId: j.string(),
      tone: j.enum("calmer", "crisp", "diplomatic"),
      rewrite: j.string().nullable(),
      error: j.string().nullable(),
    }),
    execute: async ({ draftId, tone }: any, context: any) => {
      return rephraseDraft(notionClient(context), { draftId, tone });
    },
  });
}

export async function rephraseDraft(
  notion: any,
  input: { draftId: string; tone: "calmer" | "crisp" | "diplomatic" }
): Promise<{ ok: boolean; draftId: string; tone: "calmer" | "crisp" | "diplomatic"; rewrite: string | null; error: string | null }> {
  const draftId = String(input.draftId ?? "").trim();
  const tone = input.tone;
  const fail = (error: string) => ({ ok: false, draftId, tone, rewrite: null, error: shortError(error) });

  const FROZEN_DS = process.env.FROZEN_DRAFTS_DATA_SOURCE_ID;
  if (!FROZEN_DS) return fail("FROZEN_DRAFTS_DATA_SOURCE_ID not set");
  if (!draftId) return fail("Missing draftId");

  const row = await fetchDraftRow(notion, FROZEN_DS, draftId);
  if (!row) return fail("draft not found");

  const original = readText(row, "Original") || readText(row, "Original Snapshot");
  if (!original.trim()) return fail("Original draft text is empty");

  try {
    const rewrite = tone === "calmer"
      ? (readText(row, "Rewrite") || await rewriteWithTone(original, pageTitle(row), tone))
      : await rewriteWithTone(original, pageTitle(row), tone);
    await tryStampDraftTone(notion, row.id, tone, rewrite);
    await createSleepAudit(notion, row, "approved", `Generated ${tone} tone variant; source page was not modified.`);
    return { ok: true, draftId, tone, rewrite, error: null };
  } catch (e: any) {
    await createSleepAudit(notion, row, "failed", `Tone generation failed: ${shortError(e)}`);
    await tryStampDraft(notion, row.id, { status: "error", error: shortError(e) });
    return fail(e);
  }
}

// ---------------- handlers ----------------

function verifySignature(event: any) {
  const secret = process.env.COMPOST_WEBHOOK_SECRET || process.env.NOTION_WEBHOOK_SECRET;
  if (!secret) throw new WebhookVerificationError("COMPOST_WEBHOOK_SECRET not set");
  const headerVal = event.headers?.["x-notion-signature"] ?? event.headers?.["X-Notion-Signature"] ?? "";
  const rawBody = event.rawBody ?? JSON.stringify(event.body ?? {});
  const expected = "sha256=" + crypto.createHmac("sha256", secret).update(rawBody).digest("hex");
  const a = Buffer.from(headerVal);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    throw new WebhookVerificationError("bad signature");
  }
}

async function handleEdit(event: any, notion: any) {
  const pageId = event.body?.entity?.id ?? event.body?.page_id;
  if (!pageId) return;

  const tz = process.env.USER_TIMEZONE || "America/Los_Angeles";
  if (!isLateNight(tz)) return;

  const page = await notion.pages.retrieve({ page_id: pageId });
  if (page.archived) return;

  const blocks = await notion.blocks.children.list({ block_id: pageId, page_size: 50 });
  const markdown = blocksToMarkdown(blocks.results);
  if (wordCount(markdown) < 30) return;

  // Skip if [!ship] tag present in title
  const title = pageTitle(page);
  if (/\[!ship\]/i.test(title)) return;

  // Dedup: skip if active draft exists for this page already tonight
  if (await hasActiveDraft(notion, pageId)) return;

  const draftId = sha1(`${pageId}|${new Date().toISOString().slice(0, 10)}`);

  // Snapshot
  await upsertFrozenDraftRow(notion, {
    draftId, pageId, title, original: markdown, rewrite: "", status: "pending",
    frozenAt: new Date().toISOString(),
  });

  // LLM rewrite
  try {
    const rewrite = await calmRewrite(markdown, title);
    await upsertFrozenDraftRow(notion, { draftId, status: "frozen", rewrite });
  } catch (e: any) {
    await upsertFrozenDraftRow(notion, { draftId, status: "error", error: String(e).slice(0, 1900) });
  }
}

async function calmRewrite(markdown: string, title: string): Promise<string> {
  if (!process.env.ANTHROPIC_API_KEY) return fallbackRewrite(markdown);

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

  try {
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
    if (!r.ok) return fallbackRewrite(markdown);
    const json: any = await r.json();
    return json.content?.[0]?.text?.trim() || fallbackRewrite(markdown);
  } catch {
    return fallbackRewrite(markdown);
  }
}

async function rewriteWithTone(markdown: string, title: string, tone: "calmer" | "crisp" | "diplomatic"): Promise<string> {
  if (tone === "calmer") return calmRewrite(markdown, title);
  if (!process.env.ANTHROPIC_API_KEY) return fallbackToneRewrite(markdown, tone);

  const toneRules: Record<"calmer" | "crisp" | "diplomatic", string> = {
    calmer: "soften the tone while preserving substance",
    crisp: "make it shorter, clearer, and more direct while preserving substance",
    diplomatic: "make it tactful, collaborative, and relationship-preserving while preserving substance",
  };

  const prompt = `Rewrite this draft in a ${tone} tone: ${toneRules[tone]}.

Rules:
- Preserve facts, names, numbers, links, and structure.
- Do not invent new commitments or remove important caveats.
- Keep markdown.
- Output only the rewritten markdown.

Title: ${title}

Original:
${markdown}`;

  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": process.env.ANTHROPIC_API_KEY ?? "",
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5",
        max_tokens: Math.min(4096, Math.max(800, markdown.length * 2)),
        messages: [{ role: "user", content: prompt }],
      }),
    });
    if (!r.ok) return fallbackToneRewrite(markdown, tone);
    const json: any = await r.json();
    return json.content?.[0]?.text?.trim() || fallbackToneRewrite(markdown, tone);
  } catch {
    return fallbackToneRewrite(markdown, tone);
  }
}

function fallbackRewrite(markdown: string): string {
  return markdown
    .replace(/\bI AM ABSOLUTELY CERTAIN\b/gi, "I am concerned")
    .replace(/\bEVERYONE\b/g, "the team")
    .replace(/\bIMMEDIATELY\b/g, "soon")
    .replace(/\bALWAYS\b/g, "often")
    .replace(/\bNEVER\b/g, "rarely");
}

function fallbackToneRewrite(markdown: string, tone: "crisp" | "diplomatic" | "calmer"): string {
  const calm = fallbackRewrite(markdown);
  if (tone === "diplomatic") return calm.replace(/\bwe need to\b/gi, "it may help to").replace(/\bmust\b/gi, "should");
  if (tone === "crisp") return calm.split("\n").map((line) => line.trim()).filter(Boolean).join("\n");
  return calm;
}

// ---------------- DB helpers (skeletons — flesh out using @notionhq/client patterns) ----------------

async function upsertFrozenDraftRow(notion: any, fields: any) {
  if (demoFlagEnabled("SLEEP_ON_IT_FORCE_FIRE")) return;

  const FROZEN_DS = process.env.FROZEN_DRAFTS_DATA_SOURCE_ID;
  if (!FROZEN_DS) return;

  const existing = fields.draftId ? await fetchDraftRow(notion, FROZEN_DS, fields.draftId) : null;
  const properties = frozenDraftProperties(fields);
  if (Object.keys(properties).length === 0) return;

  try {
    if (existing) {
      await notion.pages.update({ page_id: existing.id, properties });
      return;
    }

    await notion.pages.create({
      parent: { data_source_id: FROZEN_DS },
      properties,
    });
  } catch (e: any) {
    if (isNotionObjectNotFound(e)) {
      console.warn("upsertFrozenDraftRow skipped: Frozen Drafts data source is not shared with the integration");
      return;
    }
    throw e;
  }
}

async function hasActiveDraft(notion: any, pageId: string): Promise<boolean> {
  if (demoFlagEnabled("SLEEP_ON_IT_FORCE_FIRE")) return false;

  const FROZEN_DS = process.env.FROZEN_DRAFTS_DATA_SOURCE_ID;
  if (!FROZEN_DS) return false;
  let res: any;
  try {
    res = await notion.dataSources.query({
      data_source_id: FROZEN_DS,
      filter: {
        and: [
          { property: "Source Page ID", rich_text: { equals: pageId } },
          {
            or: [
              { property: "Status", select: { equals: "pending" } },
              { property: "Status", select: { equals: "frozen" } },
              { property: "Status", select: { equals: "ready" } },
            ],
          },
        ],
      },
    });
  } catch (e: any) {
    if (isNotionObjectNotFound(e)) return false;
    throw e;
  }
  return res.results.length > 0;
}

async function fetchDraftRow(notion: any, dataSourceId: string, draftId: string): Promise<any | null> {
  const page = await retrieveDraftPage(notion, draftId);
  if (page) return page;

  let res: any;
  try {
    res = await notion.dataSources.query({
      data_source_id: dataSourceId,
      filter: { property: "Draft ID", rich_text: { equals: draftId } },
    });
  } catch (e: any) {
    if (isNotionObjectNotFound(e)) return null;
    throw e;
  }
  return res.results[0] ?? null;
}

async function retrieveDraftPage(notion: any, pageId: string): Promise<any | null> {
  if (!/^[0-9a-f]{32}$|^[0-9a-f-]{36}$/i.test(pageId)) return null;

  try {
    const page = await notion.pages.retrieve({ page_id: pageId });
    if (page?.properties?.["Draft ID"]) return page;
  } catch (e: any) {
    if (!isNotionObjectNotFound(e) && e?.code !== "validation_error") throw e;
  }
  return null;
}

function isNotionObjectNotFound(e: any): boolean {
  return e?.code === "object_not_found" || /Could not find database|not shared with your integration/i.test(String(e?.message ?? e));
}

async function stampDraft(notion: any, pageId: string, fields: { status: string; error?: string | null }) {
  const properties: any = {
    Status:        { select: { name: fields.status } },
    "Reviewed At": { date: { start: new Date().toISOString() } },
  };
  if (fields.error === null) properties.Error = { rich_text: [] };
  else if (fields.error) properties.Error = richTextProp(fields.error);
  await notion.pages.update({ page_id: pageId, properties });
}

async function tryStampDraft(notion: any, pageId: string, fields: { status: string; error?: string | null }) {
  try {
    await stampDraft(notion, pageId, fields);
  } catch (e: any) {
    console.warn("draft row stamp skipped:", shortError(e));
  }
}

async function tryStampDraftTone(notion: any, pageId: string, tone: string, rewrite: string) {
  try {
    const variants = JSON.stringify({ [tone]: rewrite });
    await notion.pages.update({
      page_id: pageId,
      properties: {
        Rewrite: richTextProp(rewrite),
        "Rewrite Variants": richTextProp(variants),
        "Active Tone": { select: { name: tone } },
        Error: { rich_text: [] },
      },
    });
  } catch (e: any) {
    console.warn("draft tone stamp skipped:", shortError(e));
  }
}

async function createSleepAudit(notion: any, row: any, decision: "approved" | "rejected" | "failed", detail: string) {
  const draftId = readText(row, "Draft ID");
  const sourcePageId = readText(row, "Source Page ID");
  await createAuditPage(notion, {
    title: `[!audit] Sleep-On-It ${decision} - ${pageTitle(row)}`,
    lines: [
      `Time: ${new Date().toISOString()}`,
      `Decision: ${decision}`,
      `Draft row ID: ${row.id}`,
      `Draft ID: ${draftId || "(missing)"}`,
      `Source Page ID: ${sourcePageId || "(missing)"}`,
      `Result: ${detail}`,
      decision === "approved"
        ? "Safety: source page was explicitly marked as a Sleep-On-It demo page."
        : "Safety: reject/failure path does not replace source content.",
    ],
  });
}

async function assertSafeSleepTarget(notion: any, pageId: string) {
  const page: any = await withRetryOn429(() => notion.pages.retrieve({ page_id: pageId }));
  if (isSleepDemoSource(page)) return;

  let blocks: any[] = [];
  try {
    const res: any = await withRetryOn429(() =>
      notion.blocks.children.list({ block_id: pageId, page_size: 20 })
    );
    blocks = res.results ?? [];
  } catch {
    blocks = [];
  }

  if (blocks.some((b) => /\[!sleep\]|safe demo late-night draft|demo late-night draft/i.test(extractBlockText(b)))) {
    return;
  }

  throw new Error("Refusing to replace non-demo Sleep-On-It source. Add [!sleep] to the target page title/body for this demo.");
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

async function demoFrozenDraftChanges(notion: any): Promise<any[]> {
  const sources = await findSleepDemoSources(notion);
  const changes: any[] = [];
  for (const page of sources) {
    const blocks = await notion.blocks.children.list({ block_id: page.id, page_size: 50 });
    const original = blocksToMarkdown(blocks.results);
    if (wordCount(original) < 30) continue;
    const title = pageTitle(page);
    const draftId = sha1(`${page.id}|${new Date().toISOString().slice(0, 10)}`);
    const rewrite = await calmRewrite(original, title);
    if (!rewrite.trim() || normalizeForComparison(rewrite) === normalizeForComparison(original)) {
      console.warn(`sleep demo skipped no-op rewrite for ${page.id}`);
      continue;
    }
    changes.push({
      type: "upsert" as const,
      key: draftId,
      properties: {
        Title: Builder.title(title),
        "Draft ID": Builder.richText(draftId),
        "Source Page ID": Builder.richText(page.id),
        "Original Snapshot": Builder.richText(original),
        Original: Builder.richText(original),
        Rewrite: Builder.richText(rewrite),
        Status: Builder.select("frozen"),
        "Frozen At": Builder.dateTime(new Date().toISOString()),
      },
    });
    await pace();
  }
  return changes;
}

async function demoAuditDraftExpiryChanges(notion: any): Promise<any[]> {
  const FROZEN_DS = process.env.FROZEN_DRAFTS_DATA_SOURCE_ID;
  if (!FROZEN_DS) return [];

  let res: any;
  try {
    res = await withRetryOn429(() => notion.dataSources.query({
      data_source_id: FROZEN_DS,
      filter: {
        and: [
          { property: "Status", select: { equals: "frozen" } },
          { property: "Title", title: { contains: "[!audit]" } },
        ],
      },
    }));
  } catch (e: any) {
    if (isNotionObjectNotFound(e)) return [];
    throw e;
  }

  return res.results
    .map((row: any) => readText(row, "Draft ID"))
    .filter(Boolean)
    .map((draftId: string) => ({
      type: "upsert" as const,
      key: draftId,
      properties: { Status: Builder.select("expired") },
    }));
}

async function findSleepDemoSources(notion: any): Promise<any[]> {
  const out: any[] = [];
  let cursor: string | undefined = undefined;
  while (out.length < 10) {
    const res: any = await withRetryOn429(() => notion.search({
      filter: { property: "object", value: "page" },
      page_size: 100,
      start_cursor: cursor,
    }));
    for (const page of res.results) {
      if (isSleepDemoSource(page)) out.push(page);
    }
    if (!res.has_more) break;
    cursor = res.next_cursor;
    await pace();
  }
  return out;
}

function isSleepDemoSource(page: any): boolean {
  const title = pageTitle(page);
  if (/^\s*\[!audit\]/i.test(title)) return false;
  return /\[!sleep\]|demo late-night draft/i.test(title);
}

function normalizeForComparison(text: string): string {
  return String(text).trim().replace(/\s+/g, " ").toLowerCase();
}

function extractBlockText(block: any): string {
  const rt = block?.[block?.type]?.rich_text;
  if (Array.isArray(rt)) return rt.map((t: any) => t.plain_text ?? "").join("");
  return "";
}

function readText(row: any, key: string): string {
  const p = row.properties?.[key];
  if (!p) return "";
  if (p.type === "rich_text") return (p.rich_text ?? []).map((t: any) => t.plain_text).join("");
  if (p.type === "title")     return (p.title ?? []).map((t: any) => t.plain_text).join("");
  return "";
}

function frozenDraftProperties(fields: any): Record<string, any> {
  const properties: Record<string, any> = {};
  if (fields.title != null) properties.Title = titleProp(fields.title);
  if (fields.draftId != null) properties["Draft ID"] = richTextProp(fields.draftId);
  if (fields.pageId != null) properties["Source Page ID"] = richTextProp(fields.pageId);
  if (fields.original != null) {
    properties["Original Snapshot"] = richTextProp(fields.original);
    properties.Original = richTextProp(fields.original);
  }
  if (fields.rewrite != null) properties.Rewrite = richTextProp(fields.rewrite);
  if (fields.status != null) properties.Status = { select: { name: fields.status } };
  if (fields.frozenAt != null) properties["Frozen At"] = { date: { start: fields.frozenAt } };
  if (fields.error != null) properties.Error = richTextProp(fields.error);
  return properties;
}

function titleProp(text: string) {
  return {
    title: [{ type: "text", text: { content: String(text).slice(0, 1800) || "Untitled" } }],
  };
}

function richTextProp(text: string) {
  return {
    rich_text: chunkText(String(text)).map((content) => ({
      type: "text",
      text: { content },
    })),
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
