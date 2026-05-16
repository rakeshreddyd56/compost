/**
 * Time helpers. All gates use the user's local timezone (USER_TIMEZONE env var).
 */

import { demoFlagEnabled } from "./demo-mode";

export function currentHourIn(tz: string): number {
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone: tz, hour: "numeric", hour12: false });
  const h = fmt.formatToParts(new Date()).find((p) => p.type === "hour")?.value ?? "0";
  return Number(h);
}

export function currentDayIn(tz: string): number {
  // 0 = Sunday, 6 = Saturday
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone: tz, weekday: "short" });
  const dayStr = fmt.format(new Date());
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].indexOf(dayStr);
}

export function isLateNight(tz: string): boolean {
  if (demoFlagEnabled("SLEEP_ON_IT_FORCE_FIRE")) return true;
  const h = currentHourIn(tz);
  return h >= 22 || h < 6;
}

export function isMorningReviewWindow(tz: string): boolean {
  const h = currentHourIn(tz);
  return h >= 7 && h < 10;
}

export function isSunday(tz: string): boolean {
  if (demoFlagEnabled("WEEKLY_FORCE_FIRE")) return true;
  return currentDayIn(tz) === 0;
}

export function startOfWeekSunday(tz: string = "America/Los_Angeles"): Date {
  const now = new Date();
  const dow = currentDayIn(tz);
  const sunday = new Date(now);
  sunday.setDate(now.getDate() - dow);
  sunday.setHours(0, 0, 0, 0);
  return sunday;
}
