/**
 * 📰 The Weekly — Sunday-only semantic diff of last 7 days.
 *
 * See workflows/weekly.md.
 *
 * - Runs daily via schedule "1d"; gates Sunday-only inside execute().
 * - Walks workspace, compares to last week's snapshot, categorizes, summarizes substantive edits via Claude.
 * - Composes a beautiful digest page in Notion.
 */

import * as Builder from "@notionhq/workers/builder";
import { pace, withRetryOn429 } from "./utils/rate-limit";
import { sha1 } from "./utils/hashing";
import { isSunday, startOfWeekSunday } from "./utils/time";

const WORKSPACE_CAP = 500;
const SUBSTANTIVE_TOKEN_DELTA = 40;

export function registerWeekly(worker: any, dbs: { weeklySnapshots: any; weeklyDigests: any }) {

  worker.sync("weekly", {
    database: dbs.weeklyDigests,
    mode: "incremental",
    schedule: "1d",
    execute: async (state: any, context: any) => {
      const tz = process.env.USER_TIMEZONE || "America/Los_Angeles";
      if (!isSunday(tz)) return { changes: [], hasMore: false };

      const weekStart = startOfWeekSunday(tz);
      const thisWeek = await captureWorkspaceState(context.notion);
      const lastWeek = await loadSnapshots(context.notion);
      const cats = categorize(thisWeek, lastWeek);
      const summaries = await summarizeChanges(cats.substantively_edited);
      const digest = await composeDigestPage(context.notion, { cats, summaries, weekStart });
      await upsertSnapshots(context.notion, thisWeek, weekStart);

      return {
        changes: [{
          type: "upsert",
          key: weekStart.toISOString(),
          properties: {
            Title:             Builder.title(`Week of ${weekStart.toISOString().slice(0, 10)}`),
            "Week Start":      Builder.date(weekStart.toISOString()),
            "Digest Page ID":  Builder.richText(digest.id),
            "Stats":           Builder.richText(JSON.stringify(digest.stats)),
          },
        }],
        hasMore: false,
      };
    },
  });
}

// ---------------- state capture ----------------

interface PageState {
  id: string;
  title: string;
  archived: boolean;
  markdown: string;
  hash: string;
  lastEditedTime: string;
}

async function captureWorkspaceState(notion: any): Promise<Map<string, PageState>> {
  const out = new Map<string, PageState>();
  let cursor: string | undefined = undefined;
  let count = 0;

  while (count < WORKSPACE_CAP) {
    const res = await withRetryOn429(() => notion.search({
      filter: { property: "object", value: "page" },
      page_size: 100,
      start_cursor: cursor,
      sort: { timestamp: "last_edited_time", direction: "descending" },
    }));
    for (const page of res.results) {
      if (count >= WORKSPACE_CAP) break;
      const blocks = await notion.blocks.children.list({ block_id: page.id, page_size: 50 }).catch(() => ({ results: [] }));
      const md = blocksToMarkdown(blocks.results).slice(0, 4000);
      out.set(page.id, {
        id: page.id,
        title: pageTitle(page),
        archived: page.archived,
        markdown: md,
        hash: sha1(md),
        lastEditedTime: page.last_edited_time,
      });
      count++;
      await pace();
    }
    if (!res.has_more) break;
    cursor = res.next_cursor;
  }
  return out;
}

async function loadSnapshots(notion: any): Promise<Map<string, PageState>> {
  const out = new Map<string, PageState>();
  const SNAPSHOTS_DS = process.env.WEEKLY_SNAPSHOTS_DATA_SOURCE_ID;
  if (!SNAPSHOTS_DS) return out;

  let cursor: string | undefined = undefined;
  while (true) {
    const res = await withRetryOn429(() => notion.databases.query({
      database_id: SNAPSHOTS_DS,
      page_size: 100,
      start_cursor: cursor,
    }));
    for (const row of res.results) {
      const id = readText(row, "Page ID");
      if (!id) continue;
      out.set(id, {
        id,
        title: readTitle(row, "Title"),
        archived: false,
        markdown: readText(row, "Markdown"),
        hash: readText(row, "Content Hash"),
        lastEditedTime: row.last_edited_time,
      });
    }
    if (!res.has_more) break;
    cursor = res.next_cursor;
    await pace();
  }
  return out;
}

// ---------------- categorize ----------------

interface Categorized {
  created: PageState[];
  substantively_edited: Array<PageState & { prev: PageState }>;
  touched_not_changed: PageState[];
  archived: PageState[];
  unchanged: PageState[];
}

function categorize(thisWeek: Map<string, PageState>, lastWeek: Map<string, PageState>): Categorized {
  const out: Categorized = { created: [], substantively_edited: [], touched_not_changed: [], archived: [], unchanged: [] };
  for (const [id, cur] of thisWeek) {
    const prev = lastWeek.get(id);
    if (!prev) { out.created.push(cur); continue; }
    if (cur.archived && !prev.archived) { out.archived.push(cur); continue; }
    if (cur.hash === prev.hash) { out.unchanged.push(cur); continue; }
    const delta = Math.abs(wordCount(prev.markdown) - wordCount(cur.markdown));
    if (delta > SUBSTANTIVE_TOKEN_DELTA) out.substantively_edited.push({ ...cur, prev });
    else out.touched_not_changed.push(cur);
  }
  for (const [id, prev] of lastWeek) {
    if (!thisWeek.has(id)) out.archived.push({ ...prev, archived: true });
  }
  return out;
}

// ---------------- summarize via Claude ----------------

async function summarizeChanges(pages: Array<PageState & { prev: PageState }>): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  for (let i = 0; i < pages.length; i += 5) {
    const batch = pages.slice(i, i + 5);
    const results = await Promise.all(batch.map((p) => summarizeOne(p)));
    batch.forEach((p, j) => out.set(p.id, results[j]));
  }
  return out;
}

async function summarizeOne(p: PageState & { prev: PageState }): Promise<string> {
  const beforeLines = new Set(p.prev.markdown.split("\n").filter(Boolean));
  const afterLines = new Set(p.markdown.split("\n").filter(Boolean));
  const added = [...afterLines].filter((l) => !beforeLines.has(l));
  const removed = [...beforeLines].filter((l) => !afterLines.has(l));
  if (added.length === 0 && removed.length === 0) return "";

  const prompt = `You are summarizing what *meaningfully* changed in a Notion page this week. Skip formatting tweaks, whitespace, and trivial edits. Output 1-2 sentences in past tense, focused on the meaning of the change (e.g., "Q3 roadmap shifted from mobile-first to web-first"), not the mechanics ("added 47 chars"). If nothing meaningful changed, output exactly "TRIVIAL".

Page title: ${p.title}

Lines added this week:
${added.slice(0, 30).join("\n")}

Lines removed this week:
${removed.slice(0, 30).join("\n")}`;

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
        max_tokens: 200,
        messages: [{ role: "user", content: prompt }],
      }),
    });
    if (!r.ok) return "";
    const json: any = await r.json();
    const out = (json.content?.[0]?.text ?? "").trim();
    return out === "TRIVIAL" ? "" : out;
  } catch {
    return "";
  }
}

// ---------------- compose digest page ----------------

async function composeDigestPage(
  notion: any,
  args: { cats: Categorized; summaries: Map<string, string>; weekStart: Date }
): Promise<{ id: string; stats: any }> {
  const { cats, summaries, weekStart } = args;
  const title = `📰 Your week — ${weekStart.toISOString().slice(0, 10)}`;
  const stats = {
    created: cats.created.length,
    edited: cats.substantively_edited.length,
    archived: cats.archived.length,
    touched: cats.touched_not_changed.length,
  };

  const children: any[] = [
    h(1, title),
    para(`Across your workspace this week: ${stats.edited} pages meaningfully changed, ${stats.created} were created, ${stats.archived} were archived, and ${stats.touched} were touched without substantive change.`),
    div(),
    h(2, `✍️ Substantively edited (${stats.edited})`),
    ...cats.substantively_edited.slice(0, 30).map((p) => bullet(p.id, p.title, summaries.get(p.id) ?? "")),
    h(2, `✨ Created (${stats.created})`),
    ...cats.created.slice(0, 30).map((p) => bullet(p.id, p.title, "")),
    h(2, `🗑️ Archived (${stats.archived})`),
    ...cats.archived.slice(0, 20).map((p) => bullet(p.id, p.title, "")),
    h(2, `💨 Touched but unchanged (${stats.touched})`),
    para(`${stats.touched} pages had minor edits this week. Probably formatting or whitespace; not surfaced individually.`),
  ];

  const parent = process.env.NOTION_PARENT_PAGE_ID;
  if (!parent) throw new Error("NOTION_PARENT_PAGE_ID env var not set");

  const page = await notion.pages.create({
    parent: { page_id: parent },
    properties: { title: { title: [{ type: "text", text: { content: title } }] } },
    children: children.slice(0, 100),
  });

  // Notion's create-page block limit is ~100; append the rest in chunks
  for (let i = 100; i < children.length; i += 100) {
    await notion.blocks.children.append({ block_id: page.id, children: children.slice(i, i + 100) });
    await pace();
  }
  return { id: page.id, stats };
}

// ---------------- snapshot persistence ----------------

async function upsertSnapshots(notion: any, thisWeek: Map<string, PageState>, weekStart: Date) {
  // TODO: upsert via the sync's own change machinery (the wrapping sync writes to weeklyDigests; we need a side-call for snapshots).
  // Simplest: directly call notion.pages.create / update against weeklySnapshots' data source.
  // Implementation deferred — Sprint S7. Pseudo:
  //   for each (id, state) in thisWeek:
  //     if existing row in weeklySnapshots with Page ID = id: update Content Hash, Markdown, Snapshot Week
  //     else: create new row
  //     await pace()
}

// ---------------- block builders ----------------

function h(n: 1 | 2 | 3, t: string): any {
  const key = `heading_${n}` as const;
  return { type: key, [key]: { rich_text: [{ type: "text", text: { content: t } }] } };
}
function para(t: string): any {
  return { type: "paragraph", paragraph: { rich_text: [{ type: "text", text: { content: t } }] } };
}
function div(): any { return { type: "divider", divider: {} }; }
function bullet(pageId: string, title: string, summary: string): any {
  const text = summary ? ` — ${summary}` : "";
  return {
    type: "bulleted_list_item",
    bulleted_list_item: {
      rich_text: [
        { type: "mention", mention: { type: "page", page: { id: pageId } }, plain_text: title },
        { type: "text", text: { content: text } },
      ],
    },
  };
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
function readTitle(row: any, key: string): string {
  return readText(row, key);
}
function wordCount(s: string): number {
  return s.split(/\s+/).filter(Boolean).length;
}
function blocksToMarkdown(blocks: any[]): string {
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
