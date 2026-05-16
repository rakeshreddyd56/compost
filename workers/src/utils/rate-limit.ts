/**
 * Notion API average rate limit: 3 rps.
 * We pace at 350ms (≈ 2.85 rps) for a safety margin.
 * Burst is allowed but we stay flat to avoid 429s mid-demo.
 */

const SLEEP_MS = 350;

export function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

export function pace(): Promise<void> {
  return sleep(SLEEP_MS);
}

/**
 * Retry a Notion call once on 429, honoring Retry-After.
 * Use sparingly — most loops use pace() which prevents 429 in the first place.
 */
export async function withRetryOn429<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e: any) {
    const status = e?.status ?? e?.response?.status;
    if (status !== 429) throw e;
    const retryAfter = Number(e?.headers?.["retry-after"] ?? e?.response?.headers?.["retry-after"] ?? 1);
    await sleep((retryAfter + 0.2) * 1000);
    return await fn();
  }
}
