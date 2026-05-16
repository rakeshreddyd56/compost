/**
 * ☀️ Cue — the right thing at the right time.
 *
 * See workflows/cue.md.
 *
 * - Reads Cue source pages (property Cue=true OR title contains [!cue]).
 * - Parses time markers; builds sorted moment timeline.
 * - Computes current + next based on USER_TIMEZONE.
 * - Calls Claude to produce a calm 1-2 line cue.
 * - Upserts to cueCards (idempotent by pageId + currentStartISO).
 */

import * as Builder from "@notionhq/workers/builder";
import { pace, withRetryOn429 } from "./utils/rate-limit";
import { sha1 } from "./utils/hashing";

interface Moment {
  startISO: string;
  startMinutes: number;
  heading: string;
  bullets: string[];
  rawTimeText: string;
}

const TIME_RE = /\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?\b/i;

export function registerCue(worker: any, dbs: { cueCards: any; pacer: any }) {

  worker.sync("cue", {
    database: dbs.cueCards,
    mode: "incremental",
    schedule: "5m",
    execute: async (state: any, context: any) => {
      const sources = await findCueSources(context.notion);
      const changes: any[] = [];
      for (const page of sources) {
        try {
          const timeline = await parseTimeline(context.notion, page);
          const { current, next } = pickCurrentAndNext(timeline);
          if (!current && !next) continue;
          const calmCue = await calmRephrase(current, next, page);
          changes.push(buildCardChange(page, current, next, calmCue));
        } catch (e) {
          console.error("cue source failed", page.id, e);
        }
        await pace();
      }
      return { changes, hasMore: false };
    },
  });
}

// ---------------- Phase 1: find sources ----------------

async function findCueSources(notion: any): Promise<any[]> {
  const out: any[] = [];
  let cursor: string | undefined = undefined;
  while (true) {
    const res: any = await withRetryOn429(() => notion.search({
      filter: { property: "object", value: "page" },
      page_size: 100,
      start_cursor: cursor,
    }));
    for (const page of res.results) {
      if (isCueSource(page)) out.push(page);
    }
    if (!res.has_more) break;
    cursor = res.next_cursor;
    await pace();
  }
  return out;
}

function isCueSource(page: any): boolean {
  const title = pageTitle(page);
  if (/\[!cue\]/i.test(title)) return true;
  const cue = page.properties?.Cue;
  if (cue?.type === "checkbox" && cue.checkbox === true) return true;
  return false;
}

// ---------------- Phase 2: parse timeline ----------------

async function parseTimeline(notion: any, page: any): Promise<Moment[]> {
  const res: any = await notion.blocks.children.list({ block_id: page.id, page_size: 100 });
  const moments: Moment[] = [];

  let currentHeading = "";
  let currentBullets: string[] = [];
  let currentTime: { text: string; minutes: number } | null = null;

  const flush = () => {
    if (currentTime) {
      moments.push({
        startISO: toTodayISO(currentTime.minutes),
        startMinutes: currentTime.minutes,
        heading: currentHeading || currentTime.text,
        bullets: currentBullets.slice(0, 5),
        rawTimeText: currentTime.text,
      });
    }
    currentBullets = [];
    currentTime = null;
  };

  for (const b of res.results) {
    const text = extractText(b);
    const time = parseTimeMarker(text);

    if (typeof b.type === "string" && b.type.startsWith("heading_")) {
      flush();
      currentHeading = text;
      if (time) currentTime = time;
      continue;
    }
    if (time) {
      flush();
      currentTime = time;
      const remainder = text.replace(time.text, "").trim();
      if (remainder) currentHeading = remainder;
      continue;
    }
    if (text && currentTime) currentBullets.push(text);
  }
  flush();

  return moments.sort((a, b) => a.startMinutes - b.startMinutes);
}

function parseTimeMarker(text: string): { text: string; minutes: number } | null {
  const m = TIME_RE.exec(text);
  if (!m) return null;
  let hour = parseInt(m[1] ?? "0", 10);
  const minute = m[2] ? parseInt(m[2], 10) : 0;
  const meridiem = m[3]?.toLowerCase().replace(/\./g, "");
  if (meridiem === "pm" && hour < 12) hour += 12;
  if (meridiem === "am" && hour === 12) hour = 0;
  if (!meridiem && (hour > 23 || (hour < 7 && minute === 0))) return null;
  if (hour > 23) return null;
  return { text: m[0], minutes: hour * 60 + minute };
}

function toTodayISO(minutesSinceMidnight: number): string {
  const tz = process.env.USER_TIMEZONE || "America/Los_Angeles";
  const now = new Date();
  const local = new Date(now.toLocaleString("en-US", { timeZone: tz }));
  local.setHours(0, 0, 0, 0);
  local.setMinutes(minutesSinceMidnight);
  return local.toISOString();
}

// ---------------- Phase 3: pick current + next ----------------

function pickCurrentAndNext(timeline: Moment[]): { current: Moment | null; next: Moment | null } {
  const tz = process.env.USER_TIMEZONE || "America/Los_Angeles";
  const nowMin = currentMinutesIn(tz);
  let current: Moment | null = null;
  let next: Moment | null = null;
  for (const m of timeline) {
    if (m.startMinutes <= nowMin && nowMin - m.startMinutes <= 60) {
      current = m;
    } else if (m.startMinutes > nowMin && !next) {
      next = m;
    }
  }
  return { current, next };
}

function currentMinutesIn(tz: string): number {
  const now = new Date();
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone: tz, hour: "numeric", minute: "numeric", hour12: false });
  const parts = fmt.formatToParts(now);
  const h = Number(parts.find((p) => p.type === "hour")?.value ?? "0");
  const m = Number(parts.find((p) => p.type === "minute")?.value ?? "0");
  return h * 60 + m;
}

// ---------------- Phase 4: calm rephrase via Claude ----------------

async function calmRephrase(current: Moment | null, next: Moment | null, page: any): Promise<string> {
  if (!current && !next) return "";
  const title = pageTitle(page);
  const prompt = `You write calm, scannable notch cards. Given the current and next moment from a time-bound Notion page, produce 1-2 short lines (max ~80 chars each) for a small ambient UI.

Rules:
- Output ONLY the lines. No preamble, no quotes.
- Lead with the imminent thing (or current, if no next).
- Include location, wifi, or one critical bullet if it fits.
- Plain language. No emoji.

Source page: ${title}

${current ? `Current moment (${current.rawTimeText}): ${current.heading}\nDetails:\n- ${current.bullets.join("\n- ")}` : ""}
${next ? `Next moment (${next.rawTimeText}): ${next.heading}\nDetails:\n- ${next.bullets.join("\n- ")}` : ""}`;

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
        max_tokens: 150,
        messages: [{ role: "user", content: prompt }],
      }),
    });
    if (!r.ok) return fallbackCue(current, next);
    const json: any = await r.json();
    const out = (json.content?.[0]?.text ?? "").trim();
    return out || fallbackCue(current, next);
  } catch {
    return fallbackCue(current, next);
  }
}

function fallbackCue(current: Moment | null, next: Moment | null): string {
  if (next && current) return `${current.heading}. Next: ${next.heading} at ${next.rawTimeText}.`;
  if (next)            return `Next: ${next.heading} at ${next.rawTimeText}.`;
  if (current)         return current.heading;
  return "";
}

// ---------------- Phase 5: upsert card ----------------

function buildCardChange(page: any, current: Moment | null, next: Moment | null, calmCue: string) {
  const anchor = current?.startISO ?? next?.startISO ?? new Date().toISOString();
  const id = sha1(`${page.id}|${anchor}`);
  const tz = process.env.USER_TIMEZONE || "America/Los_Angeles";
  const nowMin = currentMinutesIn(tz);
  const untilNext = next ? Math.max(0, next.startMinutes - nowMin) : -1;

  return {
    type: "upsert" as const,
    key: id,
    properties: {
      Title:                Builder.title(pageTitle(page)),
      "Card ID":            Builder.richText(id),
      "Source Page ID":     Builder.richText(page.id),
      "Source Title":       Builder.richText(pageTitle(page)),
      "Current Time":       current ? Builder.date(current.startISO) : Builder.richText(""),
      "Current Heading":    Builder.richText(current?.heading ?? ""),
      "Current Bullets":    Builder.richText((current?.bullets ?? []).join("\n")),
      "Next Time":          next ? Builder.date(next.startISO) : Builder.richText(""),
      "Next Heading":       Builder.richText(next?.heading ?? ""),
      "Next Bullets":       Builder.richText((next?.bullets ?? []).join("\n")),
      "Minutes Until Next": Builder.number(untilNext),
      "Calm Cue":           Builder.richText(calmCue),
      "Generated At":       Builder.date(new Date().toISOString()),
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

function extractText(b: any): string {
  const rt = b?.[b?.type]?.rich_text;
  if (Array.isArray(rt)) return rt.map((t: any) => t.plain_text ?? "").join("").trim();
  return "";
}
