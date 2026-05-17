/**
 * 🧠 Memory — deterministic ingest + recall for Notion memory pages.
 *
 * Source: regular Notion pages with `[!memory]` in the title.
 * Output: notionMemory managed DB rows consumed by the macOS notch app.
 */

import * as Builder from "@notionhq/workers/builder";
import { j } from "@notionhq/workers/schema-builder";
import { pace, withRetryOn429 } from "./utils/rate-limit";
import { sha1 } from "./utils/hashing";
import { notionTokenReady, emptySync, warnMissingToken } from "./utils/env-guard";
import { notionClient } from "./utils/notion-auth";

type MemoryKind = "photo" | "note" | "clip";

interface MemoryRecord {
  id: string;
  title: string;
  sourcePageId: string;
  type: MemoryKind;
  content: string;
  caption: string;
  capturedAt: string;
  tags: string[];
  embeddingId: string;
}

interface RecallItem {
  id: string;
  title: string;
  type: MemoryKind;
  caption: string;
  capturedAt: string;
  score: number | null;
}

const MEMORY_SOURCE_RE = /\[!memory\]/i;
const KNOWN_MEMORY_DATA_SOURCE_ID = "47d8f26b-573c-4288-bee8-1a9fafbb174f";

export function registerMemory(worker: any, dbs: { notionMemory: any; embeddingsCache: any; pacer: any }) {
  worker.sync("memoryIngest", {
    database: dbs.notionMemory,
    mode: "incremental",
    schedule: "15m",
    execute: async (_state: any, context: any) => {
      if (!notionTokenReady()) { warnMissingToken("memoryIngest"); return emptySync(); }
      const notion = notionClient(context);
      const records = await buildMemoryRecords(notion);
      await archiveLiveNonItemRows(notion);
      await upsertLiveMemoryRows(notion, records);
      return {
        changes: records.map(memoryChange),
        hasMore: false,
        nextState: { lastRunAt: new Date().toISOString() },
      };
    },
  });

  const recallItemSchema = j.object({
    id: j.string(),
    title: j.string(),
    type: j.enum("photo", "note", "clip"),
    caption: j.string(),
    capturedAt: j.string(),
    score: j.number().nullable(),
  });

  worker.tool("recallMemory", {
    title: "Recall memory",
    description: "Return recent or semantically relevant Notion memory items for Custom Agents.",
    schema: j.object({
      query: j.string().nullable().describe("Optional semantic query."),
      limit: j.number().nullable().describe("Maximum items to return. Defaults to 8, max 25."),
      since: j.string().nullable().describe("Optional ISO timestamp lower bound."),
    }),
    outputSchema: j.object({ items: j.array(recallItemSchema) }),
    execute: async ({ query, limit, since }: any, context: any) => {
      return { items: await recallMemory(notionClient(context), { query, limit, since }) };
    },
  });
}

async function buildMemoryRecords(notion: any): Promise<MemoryRecord[]> {
  const pages = await findMemorySources(notion);
  const records: MemoryRecord[] = [];

  for (const page of pages) {
    const pageRecords = await recordsForPage(notion, page);
    records.push(...pageRecords);
    await pace();
  }

  return records.slice(0, 100);
}

async function findMemorySources(notion: any): Promise<any[]> {
  const out: any[] = [];
  let cursor: string | undefined = undefined;

  while (out.length < 50) {
    const res: any = await withRetryOn429(() => notion.search({
      filter: { property: "object", value: "page" },
      page_size: 100,
      start_cursor: cursor,
      sort: { timestamp: "last_edited_time", direction: "descending" },
    }));
    for (const page of res.results) {
      if (isMemorySource(page)) out.push(page);
    }
    if (!res.has_more) break;
    cursor = res.next_cursor;
    await pace();
  }

  return out;
}

async function recordsForPage(notion: any, page: any): Promise<MemoryRecord[]> {
  const blocks = await fetchFirstBlocks(notion, page.id, 60);
  const title = pageTitle(page);
  const noteText = blocks.map(extractBlockText).filter(Boolean).join("\n").trim();
  const manualCaption = extractManualCaption(noteText);
  const imageBlocks = blocks.filter(isImageLikeBlock);
  const capturedAt = page.last_edited_time ?? page.created_time ?? new Date().toISOString();

  if (imageBlocks.length > 0) {
    const records: MemoryRecord[] = [];
    for (const block of imageBlocks.slice(0, 4)) {
      const url = imageUrl(block);
      if (!url) continue;
      const caption = manualCaption || await captionImage(url, title, noteText);
      const contentForEmbedding = `${title}\n${caption}\n${noteText}`.trim();
      const embeddingId = await ensureEmbedding(notion, contentForEmbedding, title);
      records.push({
        id: sha1(`photo|${page.id}|${block.id}|${url}`),
        title,
        sourcePageId: page.id,
        type: "photo",
        content: url,
        caption,
        capturedAt,
        tags: inferTags(`${caption}\n${noteText}`),
        embeddingId,
      });
      await pace();
    }
    if (records.length > 0) return records;
  }

  if (noteText.length === 0) return [];
  const caption = manualCaption || await summarizeNote(noteText, title);
  const embeddingId = await ensureEmbedding(notion, `${title}\n${caption}\n${noteText}`, title);
  return [{
    id: sha1(`note|${page.id}|${noteText}`),
    title,
    sourcePageId: page.id,
    type: "note",
    content: noteText.slice(0, 1800),
    caption,
    capturedAt,
    tags: inferTags(`${caption}\n${noteText}`),
    embeddingId,
  }];
}

function memoryChange(record: MemoryRecord) {
  return {
    type: "upsert" as const,
    key: record.id,
    properties: {
      Title:            Builder.title(record.title),
      "Memory ID":      Builder.richText(record.id),
      "Source Page ID": Builder.richText(record.sourcePageId),
      Type:             Builder.select(record.type),
      Content:          Builder.richText(record.content),
      Caption:          Builder.richText(record.caption),
      "Captured At":    Builder.dateTime(record.capturedAt),
      Tags:             Builder.multiSelect(...record.tags),
      "Embedding ID":   Builder.richText(record.embeddingId),
    },
  };
}

export async function recallMemory(
  notion: any,
  input: { query?: string | null; limit?: number | null; since?: string | null }
): Promise<RecallItem[]> {
  const limit = Math.max(1, Math.min(Number(input.limit ?? 8) || 8, 25));
  const rows = await fetchMemoryRows(notion, input.since);
  const query = String(input.query ?? "").trim();

  if (!query) {
    return rows
      .sort((a, b) => b.capturedAt.localeCompare(a.capturedAt))
      .slice(0, limit)
      .map((row) => toRecallItem(row, null));
  }

  const queryEmbedding = await embedText(query);
  const scored: RecallItem[] = [];

  for (const row of rows) {
    const textScore = lexicalScore(query, `${row.title}\n${row.caption}`);
    const embedding = queryEmbedding ? await readEmbedding(notion, row.id) : null;
    const score = embedding && queryEmbedding
      ? cosine(queryEmbedding, embedding)
      : textScore;
    scored.push(toRecallItem(row, Number(score.toFixed(4))));
    await pace();
  }

  return scored
    .sort((a, b) => (b.score ?? 0) - (a.score ?? 0) || b.capturedAt.localeCompare(a.capturedAt))
    .slice(0, limit);
}

function toRecallItem(row: RecallItem & { embeddingId: string }, score: number | null): RecallItem {
  return {
    id: row.id,
    title: row.title,
    type: row.type,
    caption: row.caption,
    capturedAt: row.capturedAt,
    score,
  };
}

async function fetchMemoryRows(notion: any, since?: string | null): Promise<Array<RecallItem & { embeddingId: string }>> {
  const dataSourceId = memoryDataSourceId();
  if (!dataSourceId) return [];

  const filter = since
    ? { property: "Captured At", date: { on_or_after: since } }
    : undefined;
  const rows: any[] = [];
  let cursor: string | undefined = undefined;

  do {
    const res: any = await withRetryOn429(() => notion.dataSources.query({
      data_source_id: dataSourceId,
      page_size: 100,
      start_cursor: cursor,
      ...(filter ? { filter } : {}),
    }));
    rows.push(...res.results);
    cursor = res.has_more ? res.next_cursor : undefined;
    await pace();
  } while (cursor && rows.length < 300);

  return rows.map((row) => ({
    id: row.id,
    title: readTitle(row),
    type: (readSelect(row, "Type") || "note") as MemoryKind,
    caption: readText(row, "Caption") || readText(row, "Content"),
    capturedAt: readDate(row, "Captured At"),
    score: null,
    embeddingId: readText(row, "Embedding ID"),
  }));
}

async function fetchFirstBlocks(notion: any, pageId: string, limit: number): Promise<any[]> {
  try {
    const res: any = await withRetryOn429(() =>
      notion.blocks.children.list({ block_id: pageId, page_size: limit })
    );
    return res.results ?? [];
  } catch {
    return [];
  }
}

async function upsertLiveMemoryRows(notion: any, records: MemoryRecord[]) {
  const dataSourceId = memoryDataSourceId();
  if (!dataSourceId) return;

  for (const record of records) {
    try {
      const existing = await findLiveMemoryRow(notion, record);
      const properties = liveMemoryProperties(record);
      if (existing) {
        await notion.pages.update({ page_id: existing.id, properties });
      } else {
        await notion.pages.create({
          parent: { data_source_id: dataSourceId },
          properties,
        });
      }
    } catch (e: any) {
      console.warn("live memory row upsert skipped:", shortError(e));
    }
    await pace();
  }
}

async function archiveLiveNonItemRows(notion: any) {
  const dataSourceId = memoryDataSourceId();
  if (!dataSourceId) return;

  try {
    const res: any = await notion.dataSources.query({
      data_source_id: dataSourceId,
      page_size: 50,
      filter: {
        or: [
          { property: "Title", title: { contains: "Compost Memory Inbox" } },
          { property: "Caption", rich_text: { contains: "landing zone for memory" } },
        ],
      },
    });
    for (const row of res.results ?? []) {
      await notion.pages.update({ page_id: row.id, archived: true });
      await pace();
    }
  } catch (e: any) {
    console.warn("live memory cleanup skipped:", shortError(e));
  }
}

async function findLiveMemoryRow(notion: any, record: MemoryRecord): Promise<any | null> {
  const dataSourceId = memoryDataSourceId();
  if (!dataSourceId) return null;

  try {
    const res: any = await notion.dataSources.query({
      data_source_id: dataSourceId,
      page_size: 1,
      filter: {
        and: [
          { property: "Source Page ID", rich_text: { equals: record.sourcePageId } },
          { property: "Type", select: { equals: record.type } },
          { property: "Content", rich_text: { equals: record.content } },
        ],
      },
    });
    return res.results?.[0] ?? null;
  } catch {
    return null;
  }
}

function liveMemoryProperties(record: MemoryRecord) {
  return {
    Title: titleProp(record.title),
    "Source Page ID": richTextProp(record.sourcePageId),
    Type: { select: { name: record.type } },
    Content: richTextProp(record.content),
    Caption: richTextProp(record.caption),
    "Captured At": { date: { start: record.capturedAt } },
    Tags: { multi_select: record.tags.map((name) => ({ name })) },
    "Embedding ID": richTextProp(record.embeddingId),
  };
}

async function captionImage(url: string, title: string, context: string): Promise<string> {
  if (!process.env.ANTHROPIC_API_KEY) {
    return fallbackCaption(title, context, "Photo");
  }

  try {
    const image = await fetchImageAsBase64(url);
    if (!image) return fallbackCaption(title, context, "Photo");

    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": process.env.ANTHROPIC_API_KEY ?? "",
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5",
        max_tokens: 120,
        messages: [{
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: image.mediaType, data: image.base64 } },
            {
              type: "text",
              text: `Caption this memory photo for a tiny notch UI in one short sentence.
Page title: ${title}
Nearby note text: ${context.slice(0, 800)}
No preamble.`,
            },
          ],
        }],
      }),
    });
    if (!r.ok) return fallbackCaption(title, context, "Photo");
    const json: any = await r.json();
    return cleanOneLine(json.content?.[0]?.text) || fallbackCaption(title, context, "Photo");
  } catch {
    return fallbackCaption(title, context, "Photo");
  }
}

async function summarizeNote(text: string, title: string): Promise<string> {
  if (!process.env.ANTHROPIC_API_KEY) return fallbackCaption(title, text, "Note");

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
        max_tokens: 100,
        messages: [{
          role: "user",
          content: `Summarize this Notion memory note for a tiny notch UI in one short sentence.
Title: ${title}
Note:
${text.slice(0, 1800)}

Output only the sentence.`,
        }],
      }),
    });
    if (!r.ok) return fallbackCaption(title, text, "Note");
    const json: any = await r.json();
    return cleanOneLine(json.content?.[0]?.text) || fallbackCaption(title, text, "Note");
  } catch {
    return fallbackCaption(title, text, "Note");
  }
}

async function fetchImageAsBase64(url: string): Promise<{ base64: string; mediaType: string } | null> {
  const r = await fetch(url);
  if (!r.ok) return null;
  const contentType = r.headers.get("content-type") || "image/jpeg";
  if (!contentType.startsWith("image/")) return null;
  const buffer = Buffer.from(await r.arrayBuffer());
  if (buffer.byteLength > 4_000_000) return null;
  return { base64: buffer.toString("base64"), mediaType: contentType.split(";")[0] };
}

async function ensureEmbedding(notion: any, text: string, title: string): Promise<string> {
  const clean = text.trim();
  if (!clean) return "";
  const embeddingId = sha1(`embedding|${clean}`);
  const cacheDs = process.env.EMBEDDINGS_CACHE_DATA_SOURCE_ID;
  if (!cacheDs) return embeddingId;

  const existing = await fetchEmbeddingRow(notion, embeddingId);
  if (existing) return embeddingId;

  const embedding = await embedText(clean);
  if (!embedding) return embeddingId;

  try {
    await notion.pages.create({
      parent: { data_source_id: cacheDs },
      properties: {
        Title:          titleProp(title),
        "Page ID":      richTextProp(embeddingId),
        "Content Hash": richTextProp(embeddingId),
        Embedding:      richTextProp(JSON.stringify(embedding)),
      },
    });
  } catch (e: any) {
    console.warn("embedding cache write skipped:", shortError(e));
  }

  return embeddingId;
}

async function readEmbedding(notion: any, memoryRowId: string): Promise<number[] | null> {
  const dataSourceId = memoryDataSourceId();
  if (!dataSourceId) return null;

  try {
    const row = await notion.pages.retrieve({ page_id: memoryRowId });
    const embeddingId = readText(row, "Embedding ID");
    if (!embeddingId) return null;
    const cached = await fetchEmbeddingRow(notion, embeddingId);
    const raw = cached ? readText(cached, "Embedding") : "";
    const parsed = raw ? JSON.parse(raw) : null;
    return Array.isArray(parsed) ? parsed.filter((n) => typeof n === "number") : null;
  } catch {
    return null;
  }
}

async function fetchEmbeddingRow(notion: any, embeddingId: string): Promise<any | null> {
  const cacheDs = process.env.EMBEDDINGS_CACHE_DATA_SOURCE_ID;
  if (!cacheDs || !embeddingId) return null;
  try {
    const res: any = await notion.dataSources.query({
      data_source_id: cacheDs,
      filter: { property: "Page ID", rich_text: { equals: embeddingId } },
      page_size: 1,
    });
    return res.results?.[0] ?? null;
  } catch {
    return null;
  }
}

async function embedText(text: string): Promise<number[] | null> {
  if (!process.env.OPENAI_API_KEY) return null;
  try {
    const r = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: "text-embedding-3-small",
        input: text.slice(0, 8000),
      }),
    });
    if (!r.ok) return null;
    const json: any = await r.json();
    return json.data?.[0]?.embedding ?? null;
  } catch {
    return null;
  }
}

function isMemorySource(page: any): boolean {
  const title = pageTitle(page);
  if (/^\s*\[!audit\]/i.test(title)) return false;
  if (/compost memory inbox/i.test(title)) return false;
  if (page.properties?.["Source Page ID"] || page.properties?.["Captured At"]) return false;
  return MEMORY_SOURCE_RE.test(title);
}

function isImageLikeBlock(block: any): boolean {
  return block?.type === "image" || block?.type === "file";
}

function imageUrl(block: any): string {
  const payload = block?.[block?.type];
  if (!payload) return "";
  if (payload.type === "external") return payload.external?.url ?? "";
  if (payload.type === "file") return payload.file?.url ?? "";
  return "";
}

function extractBlockText(block: any): string {
  const richText = block?.[block?.type]?.rich_text;
  if (!Array.isArray(richText)) return "";
  return richText.map((part: any) => part.plain_text ?? "").join("").trim();
}

function inferTags(text: string): string[] {
  const out = new Set<string>();
  if (/\b(todo|remember|remind|follow up|follow-up|need to|should)\b/i.test(text)) out.add("todo");
  if (/\b(idea|maybe|what if|concept)\b/i.test(text)) out.add("idea");
  if (/\b(photo|image|picture|screenshot)\b/i.test(text)) out.add("moment");
  if (out.size === 0) out.add("reference");
  return [...out].slice(0, 3);
}

function extractManualCaption(text: string): string {
  const match = text.match(/^Caption\s*\(manual\):\s*(.+)$/im);
  const caption = cleanOneLine(match?.[1] ?? "");
  if (!caption || /^add after dropping/i.test(caption)) return "";
  return caption;
}

function lexicalScore(query: string, text: string): number {
  const q = words(query);
  const t = new Set(words(text));
  if (q.length === 0 || t.size === 0) return 0;
  return q.filter((word) => t.has(word)).length / q.length;
}

function words(text: string): string[] {
  return text.toLowerCase().match(/[a-z0-9]+/g)?.filter((w) => w.length > 2) ?? [];
}

function cosine(a: number[], b: number[]): number {
  const n = Math.min(a.length, b.length);
  let dot = 0;
  let aa = 0;
  let bb = 0;
  for (let i = 0; i < n; i++) {
    dot += (a[i] ?? 0) * (b[i] ?? 0);
    aa += (a[i] ?? 0) ** 2;
    bb += (b[i] ?? 0) ** 2;
  }
  return aa && bb ? dot / (Math.sqrt(aa) * Math.sqrt(bb)) : 0;
}

function fallbackCaption(title: string, text: string, prefix: string): string {
  const body = cleanOneLine(text) || title;
  return `${prefix}: ${body}`.slice(0, 240);
}

function cleanOneLine(text: string): string {
  return String(text ?? "").replace(/\s+/g, " ").trim().slice(0, 500);
}

function memoryDataSourceId(): string {
  return process.env.NOTION_MEMORY_DATA_SOURCE_ID
    || process.env.NOTION_MEMORY_DB_DATA_SOURCE_ID
    || KNOWN_MEMORY_DATA_SOURCE_ID;
}

function pageTitle(page: any): string {
  return readTitle(page);
}

function readTitle(page: any): string {
  for (const value of Object.values(page.properties ?? {})) {
    if ((value as any)?.type === "title") {
      return ((value as any).title ?? []).map((part: any) => part.plain_text ?? "").join("") || "Untitled memory";
    }
  }
  return "Untitled memory";
}

function readText(page: any, key: string): string {
  const prop = page.properties?.[key];
  if (!prop) return "";
  if (prop.type === "rich_text") return (prop.rich_text ?? []).map((part: any) => part.plain_text ?? "").join("");
  if (prop.type === "title") return (prop.title ?? []).map((part: any) => part.plain_text ?? "").join("");
  return "";
}

function readSelect(page: any, key: string): string {
  const prop = page.properties?.[key];
  if (!prop) return "";
  if (prop.type === "select") return prop.select?.name ?? "";
  if (prop.type === "rich_text") return readText(page, key);
  return "";
}

function readDate(page: any, key: string): string {
  const prop = page.properties?.[key];
  return prop?.type === "date" ? prop.date?.start ?? "" : "";
}

function titleProp(text: string) {
  return {
    title: [{ type: "text", text: { content: String(text).slice(0, 1800) || "Untitled" } }],
  };
}

function richTextProp(text: string) {
  return {
    rich_text: [{ type: "text", text: { content: String(text).slice(0, 1900) } }],
  };
}

function shortError(e: any): string {
  return String(e?.message ?? e).slice(0, 500);
}
