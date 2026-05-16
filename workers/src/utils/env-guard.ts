/**
 * Graceful env-guard for syncs / webhooks that need NOTION_API_TOKEN.
 *
 * `context.notion` throws on FIRST ACCESS if NOTION_API_TOKEN is not set
 * (it's a getter, not a method). So we check the env var first and
 * no-op the sync cycle if missing. Syncs auto-recover once env is pushed.
 */

const EMPTY_SYNC_RESULT = { changes: [], hasMore: false } as const;

export function notionTokenReady(): boolean {
  return Boolean(process.env.NOTION_API_TOKEN);
}

export function emptySync() {
  return EMPTY_SYNC_RESULT;
}

let warnedOnce = false;
export function warnMissingToken(syncKey: string): void {
  if (warnedOnce) return;
  warnedOnce = true;
  console.warn(
    `[${syncKey}] NOTION_API_TOKEN not set; skipping sync cycle. ` +
    `Run 'ntn workers env push' after filling .env to enable.`
  );
}
