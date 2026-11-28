import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import type { AiMessageAttachment } from "@/lib/server/ai/aiConversationTypes"
import { signedUrlsForAttachments } from "@/lib/server/ai/aiAttachmentStorage"

type Db = SupabaseClient<Database>

export function parseAttachments(raw: unknown): AiMessageAttachment[] {
  if (!Array.isArray(raw)) return []
  return raw
    .map((item): AiMessageAttachment | null => {
      if (!item || typeof item !== "object") return null
      const o = item as Record<string, unknown>
      const tradeId =
        typeof o.tradeId === "string"
          ? o.tradeId
          : typeof o.trade_id === "string"
            ? o.trade_id
            : null
      const kindRaw = typeof o.kind === "string" ? o.kind : "uploaded_image"
      if (kindRaw === "trade") {
        if (!tradeId?.trim()) return null
        return { kind: "trade", tradeId: tradeId.trim(), url: "", storagePath: null }
      }
      const url = typeof o.url === "string" ? o.url : ""
      const storagePath =
        typeof o.storagePath === "string"
          ? o.storagePath
          : typeof o.storage_path === "string"
            ? o.storage_path
            : null
      const kind =
        kindRaw === "screenshot" || kindRaw === "uploaded_image"
          ? kindRaw
          : "uploaded_image"
      if (!url && !storagePath) return null
      return { kind, url: url || storagePath || "", storagePath }
    })
    .filter((v): v is AiMessageAttachment => v != null)
}

export async function resolveAttachmentUrls(
  db: Db,
  attachments: AiMessageAttachment[]
): Promise<string[]> {
  return signedUrlsForAttachments(db, attachments)
}