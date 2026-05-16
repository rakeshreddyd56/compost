/**
 * Compost decay scoring.
 *
 * 5 signals — each returns [0, 1]. Composite:
 *   decay = 0.35*age + 0.25*orphan + 0.20*stub + 0.10*tagless + 0.10*broken_link
 * Surface if decay >= 0.6.
 */

export interface Signals {
  age: number;
  orphan: number;
  stub: number;
  tagless: number;
  broken: number;
}

export const WEIGHTS = { age: 0.35, orphan: 0.25, stub: 0.20, tagless: 0.10, broken: 0.10 } as const;
export const DECAY_THRESHOLD = 0.60;

const REQUIRED_PROPS = ["Status", "Owner", "Priority", "Assignee", "Stage"];

export function ageScore(lastEditedTime: string): number {
  const days = (Date.now() - new Date(lastEditedTime).getTime()) / 86_400_000;
  return Math.min(1, Math.max(0, days / 180));
}

export function orphanScore(inboundCount: number): number {
  if (inboundCount === 0) return 1;
  return Math.max(0, 1 - inboundCount / 3);
}

export function stubScore(wordCount: number, hasChildren: boolean, daysSinceEdit: number): number {
  return (wordCount < 50 && !hasChildren && daysSinceEdit > 30) ? 1 : 0;
}

export function taglessScore(page: any, daysSinceEdit: number): number {
  if (page?.parent?.type !== "database_id") return 0;
  const props = page.properties ?? {};
  const missing = REQUIRED_PROPS.filter((k) => k in props && isPropertyEmpty(props[k]));
  if (missing.length === 0) return 0;
  return daysSinceEdit > 7 ? 1 : 0.5;
}

export function brokenLinkScore(internalIds: string[], knownIds: Set<string>): number {
  if (internalIds.length === 0) return 0;
  const broken = internalIds.filter((id) => !knownIds.has(id)).length;
  return broken / internalIds.length;
}

export function decay(s: Signals): number {
  return (
    WEIGHTS.age     * s.age +
    WEIGHTS.orphan  * s.orphan +
    WEIGHTS.stub    * s.stub +
    WEIGHTS.tagless * s.tagless +
    WEIGHTS.broken  * s.broken
  );
}

export function describeReason(s: Signals): string {
  const bits: string[] = [];
  if (s.age >= 0.5)     bits.push(`untouched ${Math.round(s.age * 180)}+ days`);
  if (s.orphan >= 0.5)  bits.push("no inbound links");
  if (s.stub >= 0.5)    bits.push("stub");
  if (s.tagless >= 0.5) bits.push("missing required tags");
  if (s.broken >= 0.5)  bits.push(`${Math.round(s.broken * 100)}% dead links`);
  return bits.join(" · ");
}

export function pickAction(s: Signals): "archive" | "delete_stub" | "fix_link" | "add_tag" {
  if (s.stub >= 0.7)    return "delete_stub";
  if (s.broken >= 0.5)  return "fix_link";
  if (s.tagless >= 0.5) return "add_tag";
  return "archive";
}

function isPropertyEmpty(prop: any): boolean {
  if (!prop) return true;
  switch (prop.type) {
    case "title":      return (prop.title ?? []).length === 0;
    case "rich_text":  return (prop.rich_text ?? []).length === 0;
    case "select":     return prop.select == null;
    case "multi_select": return (prop.multi_select ?? []).length === 0;
    case "people":     return (prop.people ?? []).length === 0;
    case "checkbox":   return false; // checkboxes always present
    case "number":     return prop.number == null;
    case "date":       return prop.date == null;
    case "relation":   return (prop.relation ?? []).length === 0;
    default:           return false;
  }
}
