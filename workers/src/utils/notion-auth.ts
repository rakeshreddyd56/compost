import { Client } from "@notionhq/client";

/**
 * Hosted Workers currently reject user-managed secrets with the NOTION_ prefix.
 * Use COMPOST_NOTION_TOKEN remotely, while keeping NOTION_API_TOKEN as a local
 * fallback because the CLI/docs still use it for local execution.
 */
export function notionToken(): string | undefined {
  return process.env.COMPOST_NOTION_TOKEN || process.env.NOTION_API_TOKEN;
}

export function notionTokenReady(): boolean {
  return Boolean(notionToken());
}

export function notionClient(context: any): any {
  const token = notionToken();
  return token ? new Client({ auth: token }) : context.notion;
}
