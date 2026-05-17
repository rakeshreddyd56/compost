import { withRetryOn429 } from "./rate-limit";

export interface AuditEntry {
  title: string;
  lines: string[];
}

export async function createAuditPage(notion: any, entry: AuditEntry): Promise<boolean> {
  const parent = process.env.COMPOST_PARENT_PAGE_ID || process.env.NOTION_PARENT_PAGE_ID;
  if (!parent) {
    console.warn("audit skipped: COMPOST_PARENT_PAGE_ID env var not set");
    return false;
  }

  try {
    await withRetryOn429(() =>
      notion.pages.create({
        parent: { page_id: parent },
        properties: {
          title: {
            title: [{ type: "text", text: { content: entry.title.slice(0, 1800) } }],
          },
        },
        children: entry.lines.slice(0, 40).map((line) => ({
          type: "paragraph",
          paragraph: {
            rich_text: line
              ? [{ type: "text", text: { content: line.slice(0, 1800) } }]
              : [],
          },
        })),
      })
    );
    return true;
  } catch (e: any) {
    console.warn("audit page create failed:", String(e?.message ?? e));
    return false;
  }
}
