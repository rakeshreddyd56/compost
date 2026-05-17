#!/usr/bin/env node
/**
 * Reset only explicit Compost demo rows/sources.
 *
 * This script is intentionally local-only. It uses the same internal Notion
 * integration token as the workers, but only touches rows/pages with demo
 * markers in their title/body.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { Client } from "@notionhq/client";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const workersDir = path.resolve(__dirname, "..");

loadEnv(path.join(workersDir, ".env"));

const token = process.env.COMPOST_NOTION_TOKEN || process.env.NOTION_API_TOKEN;
const compostDs = process.env.COMPOST_PILE_DATA_SOURCE_ID;
const frozenDs = process.env.FROZEN_DRAFTS_DATA_SOURCE_ID;

if (!token) die("COMPOST_NOTION_TOKEN or NOTION_API_TOKEN is required");
if (!compostDs) die("COMPOST_PILE_DATA_SOURCE_ID is required");
if (!frozenDs) die("FROZEN_DRAFTS_DATA_SOURCE_ID is required");

const notion = new Client({ auth: token });
const gardenerRe = /\[!(?:compost|gardener|stale)\]/i;
const sleepRe = /\[!sleep\]|safe demo late-night draft|demo late-night draft/i;
const canonicalSleepDemoTitleRe = /\[!sleep\].*safe demo late-night draft/i;
const loudSleepDemoMarkdown = `## Draft
I AM ABSOLUTELY CERTAIN this whole plan will fall apart if the team does not tighten the demo flow IMMEDIATELY. EVERYONE keeps adding ideas, and it feels like the important pieces are getting buried. We should NEVER pretend the app is done just because the UI looks good, and we should ALWAYS require proof that the buttons trigger real Worker-backed actions.

The actual requirement is simple: every visible button has to do a real Worker-backed action, every action needs to leave an audit trail in Notion, and the app needs to show the truth even when Notion is slow.

This is a safe demo source page. The calmer rewrite should make this draft less intense without changing the meaning.`;

const stats = {
  proposalRowsReset: 0,
  proposalRowsReadOnly: 0,
  gardenerTargetsUnarchived: 0,
  frozenDraftRowsExpired: 0,
  frozenDraftRowsReadOnly: 0,
  sleepSourcesRestored: 0,
  appResolvedStateCleared: 0,
  skipped: 0,
};

clearAppResolvedState();
await resetGardenerRows();
await resetFrozenDraftRows();

console.log(JSON.stringify({ ok: true, ...stats }, null, 2));

async function resetGardenerRows() {
  const rows = await queryAll(compostDs);
  for (const row of rows) {
    const title = pageTitle(row);
    if (!gardenerRe.test(title)) {
      stats.skipped += 1;
      continue;
    }

    if (await tryUpdatePage(row.id, {
      Approved: { checkbox: false },
      Applied: { checkbox: false },
      Error: { rich_text: [] },
    })) {
      stats.proposalRowsReset += 1;
      await pace();
    } else {
      stats.proposalRowsReadOnly += 1;
    }

    const targetPageId = readText(row, "Target Page ID");
    if (!targetPageId) continue;
    if (await isSafeTarget(targetPageId, gardenerRe)) {
      await notion.pages.update({ page_id: targetPageId, archived: false });
      stats.gardenerTargetsUnarchived += 1;
      await pace();
    }
  }
}

async function resetFrozenDraftRows() {
  const rows = await queryAll(frozenDs);
  const sourceRestores = new Map();

  for (const row of rows) {
    const title = pageTitle(row);
    if (isAuditTitle(title)) {
      stats.skipped += 1;
      continue;
    }
    if (!sleepRe.test(title)) {
      stats.skipped += 1;
      continue;
    }

    const sourcePageId = readText(row, "Source Page ID");
    const original = canonicalSleepDemoTitleRe.test(title)
      ? loudSleepDemoMarkdown
      : readText(row, "Original Snapshot") || readText(row, "Original");

    if (sourcePageId && original && await isSafeTarget(sourcePageId, sleepRe)) {
      const existing = sourceRestores.get(sourcePageId);
      if (!existing || loudness(original) > loudness(existing.markdown)) {
        sourceRestores.set(sourcePageId, { markdown: original });
      }
    }

    if (await tryUpdatePage(row.id, {
      Status: { select: { name: "expired" } },
      Error: { rich_text: [] },
    })) {
      stats.frozenDraftRowsExpired += 1;
      await pace();
    } else {
      stats.frozenDraftRowsReadOnly += 1;
    }
  }

  for (const [sourcePageId, restore] of sourceRestores) {
    await replacePageContent(sourcePageId, restore.markdown);
    stats.sleepSourcesRestored += 1;
  }
}

async function tryUpdatePage(pageId, properties) {
  try {
    await notion.pages.update({ page_id: pageId, properties });
    return true;
  } catch (error) {
    if (/read-only property|Cannot modify read-only/i.test(String(error?.message ?? error))) {
      return false;
    }
    throw error;
  }
}

function clearAppResolvedState() {
  for (const key of ["compost.resolvedDraftIds", "compost.resolvedProposalIds"]) {
    try {
      execFileSync("defaults", ["delete", "com.compost.app", key], { stdio: "ignore" });
      stats.appResolvedStateCleared += 1;
    } catch {
      // Missing keys are fine; this reset should be idempotent.
    }
  }
}

function loudness(markdown) {
  const text = String(markdown);
  const capsWords = text.match(/\b[A-Z]{3,}\b/g)?.length ?? 0;
  const absolutes = text.match(/\b(?:ALWAYS|NEVER|EVERYONE|ABSOLUTELY|IMMEDIATELY)\b/g)?.length ?? 0;
  return capsWords + absolutes * 2;
}

function isAuditTitle(title) {
  return /^\s*\[!audit\]/i.test(String(title));
}

async function queryAll(dataSourceId) {
  const results = [];
  let cursor;
  do {
    const res = await notion.dataSources.query({
      data_source_id: dataSourceId,
      page_size: 100,
      start_cursor: cursor,
    });
    results.push(...res.results);
    cursor = res.has_more ? res.next_cursor : undefined;
    await pace();
  } while (cursor);
  return results;
}

async function isSafeTarget(pageId, marker) {
  try {
    const page = await notion.pages.retrieve({ page_id: pageId });
    const title = pageTitle(page);
    if (isAuditTitle(title)) return false;
    if (marker.test(title)) return true;
    const blocks = await notion.blocks.children.list({ block_id: pageId, page_size: 20 });
    return blocks.results.some((block) => marker.test(blockText(block)));
  } catch {
    return false;
  }
}

async function replacePageContent(pageId, markdown) {
  const current = await notion.blocks.children.list({ block_id: pageId, page_size: 100 });
  for (const block of current.results) {
    await notion.blocks.delete({ block_id: block.id });
    await pace();
  }
  const children = markdownToBlocks(markdown);
  if (children.length > 0) {
    await notion.blocks.children.append({ block_id: pageId, children });
    await pace();
  }
}

function markdownToBlocks(markdown) {
  return String(markdown)
    .split("\n")
    .slice(0, 95)
    .map((line) => {
      if (line.startsWith("# ")) return heading(1, line.slice(2));
      if (line.startsWith("## ")) return heading(2, line.slice(3));
      if (line.startsWith("### ")) return heading(3, line.slice(4));
      if (line.startsWith("- ")) return richBlock("bulleted_list_item", line.slice(2));
      if (line.trim() === "---") return { type: "divider", divider: {} };
      return richBlock("paragraph", line);
    });
}

function heading(level, text) {
  return richBlock(`heading_${level}`, text);
}

function richBlock(type, text) {
  return {
    type,
    [type]: {
      rich_text: text
        ? [{ type: "text", text: { content: String(text).slice(0, 1800) } }]
        : [],
    },
  };
}

function pageTitle(page) {
  for (const value of Object.values(page.properties ?? {})) {
    if (value?.type === "title") {
      return (value.title ?? []).map((part) => part.plain_text ?? "").join("") || "Untitled";
    }
  }
  return "Untitled";
}

function readText(page, key) {
  const prop = page.properties?.[key];
  if (!prop) return "";
  if (prop.type === "rich_text") return (prop.rich_text ?? []).map((part) => part.plain_text ?? "").join("");
  if (prop.type === "title") return (prop.title ?? []).map((part) => part.plain_text ?? "").join("");
  return "";
}

function blockText(block) {
  const richText = block?.[block?.type]?.rich_text;
  if (!Array.isArray(richText)) return "";
  return richText.map((part) => part.plain_text ?? "").join("");
}

function loadEnv(file) {
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;
    const index = trimmed.indexOf("=");
    const key = trimmed.slice(0, index).trim();
    const rawValue = trimmed.slice(index + 1).trim();
    if (process.env[key]) continue;
    process.env[key] = rawValue.replace(/^['"]|['"]$/g, "");
  }
}

function pace() {
  return new Promise((resolve) => setTimeout(resolve, 350));
}

function die(message) {
  console.error(message);
  process.exit(2);
}
