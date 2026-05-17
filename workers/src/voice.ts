import { j } from "@notionhq/workers/schema-builder";
import { createAuditPage } from "./utils/audit";
import { notionClient } from "./utils/notion-auth";
import { recallMemory } from "./memory";

type VoiceMode = "general" | "briefing" | "memory" | "draft";

export function registerVoice(worker: any) {
  worker.tool("voiceReply", {
    title: "Voice reply",
    description: "Return a real assistant reply for the notch voice surface using Compost context.",
    schema: j.object({
      transcript: j.string().describe("User's recognized speech transcript."),
      mode: j.enum("general", "briefing", "memory", "draft").nullable(),
      context: j.string().nullable().describe("Optional app-provided visible context."),
    }),
    outputSchema: j.object({
      ok: j.boolean(),
      reply: j.string(),
      mode: j.enum("general", "briefing", "memory", "draft"),
      usedMemory: j.boolean(),
      error: j.string().nullable(),
    }),
    execute: async ({ transcript, mode, context }: any, workerContext: any) => {
      return voiceReply(notionClient(workerContext), { transcript, mode, context });
    },
  });
}

export async function voiceReply(
  notion: any,
  input: { transcript: string; mode?: VoiceMode | null; context?: string | null }
): Promise<{ ok: boolean; reply: string; mode: VoiceMode; usedMemory: boolean; error: string | null }> {
  const transcript = cleanOneLine(input.transcript);
  const mode = (input.mode || inferMode(transcript)) as VoiceMode;
  const context = cleanOneLine(input.context ?? "");

  if (!transcript) {
    return { ok: false, reply: "I did not catch anything yet.", mode, usedMemory: false, error: "Missing transcript" };
  }

  const memories = mode === "memory" || /\b(photo|memory|remember|saw|picture)\b/i.test(transcript)
    ? await recallMemory(notion, { query: transcript, limit: 4, since: null })
    : [];
  const memoryText = memories.map((m) => `- ${m.title}: ${m.caption}`).join("\n");
  const reply = await generateVoiceReply(transcript, mode, context, memoryText);

  await createAuditPage(notion, {
    title: "[!audit] Compost voice reply",
    lines: [
      `Time: ${new Date().toISOString()}`,
      `Mode: ${mode}`,
      `Transcript: ${transcript}`,
      `Used memory: ${memories.length > 0 ? "yes" : "no"}`,
      `Reply: ${reply}`,
    ],
  });

  return { ok: true, reply, mode, usedMemory: memories.length > 0, error: null };
}

async function generateVoiceReply(transcript: string, mode: VoiceMode, context: string, memoryText: string): Promise<string> {
  if (!process.env.ANTHROPIC_API_KEY) return fallbackReply(transcript, mode, memoryText);

  const prompt = `You are Compost, a calm notch assistant for a Notion workspace.

Reply to the user's voice command in 1-3 short spoken sentences.
Be specific, grounded, and do not claim to perform actions unless context says they happened.

Mode: ${mode}
Transcript: ${transcript}
Visible context: ${context || "(none)"}
Relevant memories:
${memoryText || "(none)"}

Output only the spoken reply.`;

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
        max_tokens: 180,
        messages: [{ role: "user", content: prompt }],
      }),
    });
    if (!r.ok) return fallbackReply(transcript, mode, memoryText);
    const json: any = await r.json();
    return cleanOneLine(json.content?.[0]?.text) || fallbackReply(transcript, mode, memoryText);
  } catch {
    return fallbackReply(transcript, mode, memoryText);
  }
}

function fallbackReply(transcript: string, mode: VoiceMode, memoryText: string): string {
  if (mode === "memory" && memoryText) return "I found a few matching memories. The strongest ones are now ready in the Memory section.";
  if (mode === "briefing") return "Your briefing is ready in Up Next. I can read the current cue and next item from Notion.";
  if (mode === "draft") return "Drafts on ice are ready. Choose Keep mine or Use calmer when you want to apply a real Notion change.";
  return `I heard: ${transcript}. I can help with briefing, memory, tidy, or draft review.`;
}

function inferMode(transcript: string): VoiceMode {
  if (/\b(photo|memory|remember|saw|picture)\b/i.test(transcript)) return "memory";
  if (/\b(meeting|calendar|brief|next|gmail|email)\b/i.test(transcript)) return "briefing";
  if (/\b(draft|rewrite|calmer|tone)\b/i.test(transcript)) return "draft";
  return "general";
}

function cleanOneLine(text: string): string {
  return String(text ?? "").replace(/\s+/g, " ").trim().slice(0, 1000);
}
